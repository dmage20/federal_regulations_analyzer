# Service class for interacting with the eCFR (Electronic Code of Federal Regulations) API
# Provides methods to fetch agency data and full regulation text
class EcfrClient
  require "net/http"
  require "uri"
  require "json"
  require "nokogiri"

  BASE_URL = "https://www.ecfr.gov/api"
  MAX_RETRIES = 3
  INITIAL_RETRY_DELAY = 1 # second
  CACHE_EXPIRES_IN = 24.hours

  class ApiError < StandardError; end
  class NotFoundError < ApiError; end
  class RateLimitError < ApiError; end

  # Fetch list of all federal agencies from eCFR
  def fetch_agencies
    cache_key = "ecfr/agencies"

    Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRES_IN) do
      url = "#{BASE_URL}/admin/v1/agencies.json"
      response = get_with_retry(url)
      parse_agencies_response(response)
    end
  end

  # Check connectivity to eCFR API (skips cache)
  def check_connection
    url = "#{BASE_URL}/admin/v1/agencies.json"
    # Use a HEAD request for efficiency if supported, otherwise lightweight GET
    # The get_with_retry method does a GET, which is fine for agencies list (~150KB)
    get_with_retry(url)
    true
  rescue
    false
  end

  # Fetch full regulation text for a CFR title
  # @param title [Integer] CFR title number
  # @param date [String] Date for version (defaults to latest available)
  # @param chapter [String] Optional specific chapter to fetch (e.g., "I", "IV")
  def fetch_regulations(title, date = nil, chapter: nil)
    date ||= get_latest_version_date(title)

    Rails.logger.info("Downloading XML for Title #{title}#{chapter ? " Chapter #{chapter}" : ""}...")
    url = "#{BASE_URL}/versioner/v1/full/#{date}/title-#{title}.xml"
    url += "?chapter=#{chapter}" if chapter.present?

    # We return the tempfile path so the caller can attach it to a model
    # or process it immediately.
    Tempfile.create([ "title-#{title}#{chapter ? "-chap-#{chapter}" : ""}", ".xml" ]) do |tempfile|
      download_with_retry(url, tempfile.path)
      yield tempfile.path if block_given?
    end
  end

  # Get the latest available version date for a title
  def get_latest_version_date(title)
    cache_key = "ecfr/latest_date/title-#{title}"

    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      fallback_date = (Date.today - 60.days).strftime("%Y-%m-%d")
      begin
        url = "#{BASE_URL}/versioner/v1/versions/title-#{title}.json"
        response = get_with_retry(url)
        data = JSON.parse(response)
        data.dig("available_on")&.max || fallback_date
      rescue => e
        Rails.logger.warn("Could not fetch latest version date: #{e.message}")
        fallback_date
      end
    end
  end

  def parse_agencies_response(body)
    data = JSON.parse(body)
    (data.dig("agencies") || []).map do |agency|
      cfr_refs = agency["cfr_references"] || []
      title_numbers = cfr_refs.map { |ref| ref["title"] }.compact.uniq

      {
        name: agency["name"],
        acronym: agency["short_name"].presence || extract_acronym(agency["name"]),
        description: agency["description"],
        cfr_titles: title_numbers,
        cfr_references: cfr_refs
      }
    end
  rescue JSON::ParserError
    []
  end

  def parse_xml_file(file_path)
    # Use streaming reader to avoid loading entire file into memory
    parts = []
    current_part = nil
    capture_text = false

    File.open(file_path, "r") do |f|
      reader = Nokogiri::XML::Reader(f)
      reader.each do |node|
        if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
          case node.name
          when "DIV5"
            if node.attribute("TYPE") == "PART"

              # YIELD THE PREVIOUS PART if it exists
              if current_part
                if block_given?
                  yield current_part
                  current_part = nil # Free memory
                else
                  parts << current_part
                end
              end

              current_part = {
                part_number: node.attribute("N"),
                identifier: "Part #{node.attribute("N")}",
                content: "" # We will accumulate text content here
              }
            end
          when "HEAD"
             if current_part && current_part[:label].nil?
               # The first HEAD inside the DIV5 is usually the title
               # We need to read the text content of this node.
               # Nokogiri Reader is forward-only, so we read untill text.
             end
          when "P"
            capture_text = true if current_part
          end
        elsif node.node_type == Nokogiri::XML::Reader::TYPE_TEXT
          if capture_text && current_part
            current_part[:content] << node.value << "\n\n"
          end
          # Rudimentary label extraction (improving this would require more complex state tracking)
          if current_part && current_part[:label].nil? && !node.value.strip.empty?
             current_part[:label] = node.value.strip
          end
        elsif node.node_type == Nokogiri::XML::Reader::TYPE_END_ELEMENT
          if node.name == "P"
            capture_text = false
          end
        end
      end

      # Yield/Save the last part
      if current_part
        if block_given?
          yield current_part
        else
          parts << current_part
        end
      end
    end

    { parts: parts }
  rescue Nokogiri::XML::SyntaxError
    { parts: [] }
  end

  private

  # Streams download directly to a file path
  def download_with_retry(url, destination_path, attempt: 1)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 120) do |http|
      request = Net::HTTP::Get.new(uri)

      http.request(request) do |response|
        case response.code.to_i
        when 200
          File.open(destination_path, "wb") do |io|
            response.read_body do |chunk|
              io.write(chunk)
            end
          end
        when 404 then raise NotFoundError, "Resource not found: #{url}"
        when 429 then raise RateLimitError, "Rate limit exceeded"
        when 500..599 then raise ApiError, "Server error: #{response.code}"
        else raise ApiError, "Unexpected status: #{response.code}"
        end
      end
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, RateLimitError, ApiError => e
    if attempt < MAX_RETRIES
      delay = INITIAL_RETRY_DELAY * (2 ** (attempt - 1))
      sleep(delay)
      download_with_retry(url, destination_path, attempt: attempt + 1)
    else
      raise
    end
  end

  def get_with_retry(url, attempt: 1)
    # Keeps existing behavior for small JSON headers (fetch_agencies)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 300 # Title 40 (EPA) can take > 60s to generate

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    case response.code.to_i
    when 200 then response.body
    when 404 then raise NotFoundError, "Resource not found: #{url}"
    when 429 then raise RateLimitError, "Rate limit exceeded"
    when 500..599 then raise ApiError, "Server error: #{response.code}"
    else raise ApiError, "Unexpected status: #{response.code}"
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, RateLimitError, ApiError => _e
    if attempt < MAX_RETRIES
      delay = INITIAL_RETRY_DELAY * (2 ** (attempt - 1))
      sleep(delay)
      get_with_retry(url, attempt: attempt + 1)
    else
      raise
    end
  end

  def extract_acronym(name)
    name.split.select { |word| word[0] == word[0].upcase }.map { |word| word[0] }.join
  end
end
