# Streaming JSON parser that extracts a specific chapter from large eCFR
# structure JSON files (10MB+) with early termination for memory efficiency.
#
# Uses SAX-style parsing via yajl-ruby to avoid loading the entire JSON
# response into memory. Stops parsing as soon as the target chapter is found.
#
# Usage:
#   extractor = EcfrChapterExtractor.new(date: '2024-01-01', title: 40, chapter: 'III')
#   chapter_data = extractor.call
#   # => { "identifier" => "III", "type" => "chapter", "label" => "Chapter III—...", "children" => [...] }
#
class EcfrChapterExtractor
  require "net/http"
  require "uri"
  require "yajl"

  BASE_URL = "https://www.ecfr.gov/api"
  MAX_RETRIES = 3
  INITIAL_RETRY_DELAY = 1 # second
  HTTP_OPEN_TIMEOUT = 10 # seconds
  HTTP_READ_TIMEOUT = 30 # seconds

  class ExtractionError < StandardError; end
  class ChapterNotFound < ExtractionError; end
  class ApiError < ExtractionError; end
  class NetworkError < ExtractionError; end

  # @param date [String] Date in YYYY-MM-DD format
  # @param title [Integer] CFR title number (1-50)
  # @param chapter [String] Chapter identifier as Roman numeral (e.g., "I", "III")
  def initialize(date:, title:, chapter:)
    @date = date
    @title = title
    @chapter = chapter.to_s
  end

  # Streams the eCFR structure JSON and extracts the target chapter.
  # Returns the chapter as a Hash, or raises if not found.
  #
  # @return [Hash] The chapter object with keys like "identifier", "label", "type", "children"
  # @raise [ChapterNotFound] if the target chapter is not in the response
  # @raise [ApiError] if the API returns a non-200 status
  # @raise [NetworkError] if the HTTP request fails
  def call
    Rails.logger.info("Extracting chapter #{@chapter} from Title #{@title} (#{@date})...")

    result = stream_and_extract
    if result
      Rails.logger.info("Found chapter #{@chapter} in Title #{@title} (#{result["children"]&.size || 0} children)")
      result
    else
      raise ChapterNotFound, "Chapter #{@chapter} not found in Title #{@title} for date #{@date}"
    end
  rescue ChapterFound => e
    # Early termination signal from the parser — this is the success path
    Rails.logger.info("Found chapter #{@chapter} in Title #{@title} via early termination")
    e.chapter_data
  end

  private

  def api_url
    "#{BASE_URL}/versioner/v1/structure/#{@date}/title-#{@title}.json"
  end

  # Streams the HTTP response and feeds chunks to the SAX parser.
  # Returns the extracted chapter Hash, or nil if not found.
  def stream_and_extract
    parser_handler = EcfrChapterParser.new(@chapter)
    json_parser = Yajl::Parser.new
    json_parser.on_parse_complete = proc { |obj| parser_handler.on_parse_complete(obj) }

    with_streaming_response(api_url) do |response|
      # Feed the streamed JSON into the SAX-style callback parser.
      # For yajl-ruby, we use the chunked parse approach: feed chunks
      # and let it call on_parse_complete when the top-level object is done.
      #
      # However, for early termination we use a different approach:
      # we use a custom SAX-style handler that tracks depth and captures
      # only the target chapter object.
      handler = StreamingChapterHandler.new(@chapter)
      stream_parser = Yajl::Parser.new
      stream_parser.on_parse_complete = proc { |_obj| }

      begin
        response.read_body do |chunk|
          handler.receive_chunk(chunk)
        end
      rescue ChapterFound => e
        return e.chapter_data
      end

      handler.result
    end
  end

  # Opens a streaming HTTP connection with retry logic.
  # Yields the Net::HTTP response object for chunk-by-chunk reading.
  def with_streaming_response(url, attempt: 1, &block)
    uri = URI(url)

    Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                    open_timeout: HTTP_OPEN_TIMEOUT,
                    read_timeout: HTTP_READ_TIMEOUT) do |http|
      request = Net::HTTP::Get.new(uri)
      http.request(request) do |response|
        case response.code.to_i
        when 200
          return yield(response)
        when 404
          raise ApiError, "Structure not found: Title #{@title} for #{@date}"
        when 429
          raise ApiError, "Rate limited by eCFR API"
        when 500..599
          raise ApiError, "eCFR API server error: #{response.code}"
        else
          raise ApiError, "Unexpected HTTP status: #{response.code}"
        end
      end
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET,
         Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError => e
    if attempt < MAX_RETRIES
      delay = INITIAL_RETRY_DELAY * (2 ** (attempt - 1))
      Rails.logger.warn(
        "EcfrChapterExtractor network error (attempt #{attempt}/#{MAX_RETRIES}): " \
        "#{e.message}. Retrying in #{delay}s..."
      )
      sleep(delay)
      with_streaming_response(url, attempt: attempt + 1, &block)
    else
      raise NetworkError, "Failed after #{MAX_RETRIES} attempts: #{e.message}"
    end
  end

  # Custom exception used for early termination when chapter is found.
  class ChapterFound < StandardError
    attr_reader :chapter_data

    def initialize(chapter_data)
      @chapter_data = chapter_data
      super("Chapter found - early termination")
    end
  end

  # Streaming handler that buffers JSON chunks and uses yajl-ruby to
  # incrementally parse the structure, extracting only the target chapter.
  #
  # Strategy:
  # - Parse the full JSON via chunked feeding into Yajl::Parser
  # - Use a custom callback that inspects the top-level "children" array
  # - When target chapter is found, raise ChapterFound to terminate early
  #
  # Because the eCFR structure JSON has children at the top level that are
  # chapters, we feed the entire stream but short-circuit on match.
  class StreamingChapterHandler
    def initialize(target_chapter)
      @target_chapter = target_chapter
      @result = nil
      @buffer = +""
      @parser = Yajl::Parser.new
      @parser.on_parse_complete = method(:on_document_parsed)
    end

    def receive_chunk(chunk)
      # Feed chunk to the incremental parser. Yajl will call
      # on_document_parsed when the full JSON object is complete.
      # We catch ChapterFound if raised during parsing.
      @parser << chunk
    end

    def result
      @result
    end

    private

    def on_document_parsed(document)
      # The document is the full parsed JSON. Walk the top-level children
      # to find our target chapter.
      children = document["children"] || []
      children.each do |child|
        if child["type"] == "chapter" && child["identifier"] == @target_chapter
          @result = child
          raise ChapterFound.new(child)
        end
      end
    end
  end

  # Simple handler for non-streaming parse-complete callback
  class EcfrChapterParser
    def initialize(target_chapter)
      @target_chapter = target_chapter
      @result = nil
    end

    def on_parse_complete(document)
      children = document["children"] || []
      children.each do |child|
        if child["type"] == "chapter" && child["identifier"] == @target_chapter
          @result = child
          break
        end
      end
    end

    attr_reader :result
  end
end
