# Streaming JSON parser that extracts a specific node (chapter, subtitle,
# subchapter, or part) from large eCFR structure JSON files (10MB+) with
# early termination for memory efficiency.
#
# Uses SAX-style parsing via yajl-ruby to avoid loading the entire JSON
# response into memory. Stops parsing as soon as the target node is found.
#
# Usage:
#   extractor = EcfrChapterExtractor.new(date: '2024-01-01', title: 40, chapter: 'III')
#   chapter_data = extractor.call
#   # => { "identifier" => "III", "type" => "chapter", "label" => "Chapter III—...", "children" => [...] }
#
#   # Extract by a different structural type:
#   extractor = EcfrChapterExtractor.new(date: '2024-01-01', title: 21, chapter: 'A', type: 'subtitle')
#   subtitle_data = extractor.call
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

  # Supported structural types in eCFR hierarchy
  VALID_TYPES = %w[chapter subtitle subchapter part].freeze

  class ExtractionError < StandardError; end
  class ChapterNotFound < ExtractionError; end
  class ApiError < ExtractionError; end
  class NetworkError < ExtractionError; end

  # @param date [String] Date in YYYY-MM-DD format
  # @param title [Integer] CFR title number (1-50)
  # @param chapter [String] Node identifier (e.g., "III", "A", "1500")
  # @param type [String] Structural type to match: "chapter", "subtitle", "subchapter", or "part".
  #   Defaults to "chapter".
  def initialize(date:, title:, chapter:, type: "chapter")
    @date = date
    @title = title
    @chapter = chapter.to_s
    @type = VALID_TYPES.include?(type.to_s) ? type.to_s : "chapter"
  end

  # Streams the eCFR structure JSON and extracts the target chapter.
  # Returns the chapter as a Hash, or raises if not found.
  #
  # @return [Hash] The chapter object with keys like "identifier", "label", "type", "children"
  # @raise [ChapterNotFound] if the target chapter is not in the response
  # @raise [ApiError] if the API returns a non-200 status
  # @raise [NetworkError] if the HTTP request fails
  def call
    Rails.logger.info("Extracting #{@type} #{@chapter} from Title #{@title} (#{@date})...")

    result = stream_and_extract
    if result
      Rails.logger.info("Found #{@type} #{@chapter} in Title #{@title} (#{result["children"]&.size || 0} children)")
      result
    else
      raise ChapterNotFound, "#{@type.capitalize} #{@chapter} not found in Title #{@title} for date #{@date}"
    end
  rescue ChapterFound => e
    # Early termination signal from the parser — this is the success path
    Rails.logger.info("Found #{@type} #{@chapter} in Title #{@title} via early termination")
    e.chapter_data
  end

  private

  def api_url
    "#{BASE_URL}/versioner/v1/structure/#{@date}/title-#{@title}.json"
  end

  # Streams the HTTP response and feeds chunks to the SAX parser.
  # Returns the extracted chapter Hash, or nil if not found.
  def stream_and_extract
    with_streaming_response(api_url) do |response|
      handler = StreamingChapterHandler.new(@chapter, @type)

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
  # incrementally parse the structure, extracting only the target node.
  #
  # Strategy:
  # - Parse the full JSON via chunked feeding into Yajl::Parser
  # - Use a custom callback that inspects the top-level "children" array
  # - When target node is found, raise ChapterFound to terminate early
  #
  # The eCFR structure JSON has children at the top level that can be
  # chapters, subtitles, subchapters, or parts depending on the title.
  class StreamingChapterHandler
    def initialize(target_identifier, target_type)
      @target_identifier = target_identifier
      @target_type = target_type
      @result = nil
      @parser = Yajl::Parser.new
      @parser.on_parse_complete = method(:on_document_parsed)
    end

    def receive_chunk(chunk)
      @parser << chunk
    end

    def result
      @result
    end

    private

    def on_document_parsed(document)
      search_children(document["children"] || [])
    end

    # Recursively searches children for the target node. This allows
    # matching nodes that may be nested (e.g., a subchapter inside a chapter).
    def search_children(children)
      children.each do |child|
        if child["type"] == @target_type && child["identifier"] == @target_identifier
          @result = child
          raise ChapterFound.new(child)
        end
        # Continue searching nested children for non-chapter types
        search_children(child["children"] || []) if child["children"]
      end
    end
  end
end
