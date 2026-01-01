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
  # Fetch full regulation text for a CFR title - STREAMS to file to save memory
  # @param title [Integer] CFR title number
  # @param date [String] Date for version (defaults to latest available)
  def fetch_regulations(title, date = nil)
    date ||= get_latest_version_date(title)

    # We do NOT cache the full XML in Redis/Memory anymore as it's too large.
    # We download, parse, and discard.
    Rails.logger.info("Downloading XML for Title #{title}...")
    url = "#{BASE_URL}/versioner/v1/full/#{date}/title-#{title}.xml"

    Tempfile.create([ "title-#{title}", ".xml" ]) do |tempfile|
      download_with_retry(url, tempfile.path)
      # Pass the file handle to Nokogiri instead of the huge string
      parse_xml_file(tempfile.path)
    end
  end

  # ... (get_latest_version_date remains same)

  private

  # Streams download directly to a file path
  def download_with_retry(url, destination_path, attempt: 1)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
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
    # ... (original implementation)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 60

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

  def parse_xml_file(file_path)
    # Parse directly from file IO to avoid loading string into memory
    File.open(file_path, "r") do |f|
      doc = Nokogiri::XML(f)

      # Extract parts and their sections from XML
      parts = doc.xpath("//DIV5[@TYPE='PART']").map do |part|
        part_number = part.attr("N")
        part_title = part.xpath("HEAD").text.strip

        chapter_node = part.xpath("ancestor::DIV3[@TYPE='CHAPTER']").first
        chapter = chapter_node&.attr("N")

        subtitle_node = part.xpath("ancestor::DIV2[@TYPE='SUBTITLE']").first
        subtitle = subtitle_node&.attr("N")

        {
            part_number: part_number,
            identifier: "Part #{part_number}",
            label: part_title,
            chapter: chapter,
            subtitle: subtitle,
            content: extract_text_content(part)
        }
      end

      { parts: parts }
    end
  rescue Nokogiri::XML::SyntaxError
    { parts: [] }
  end

  def extract_text_content(node)
    node.xpath(".//P").map(&:text).join("\n\n")
  end

  def extract_acronym(name)
    name.split.select { |word| word[0] == word[0].upcase }.map { |word| word[0] }.join
  end
end
