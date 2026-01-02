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
  # @param part [String] Optional specific part to fetch (e.g., "1", "100"). Takes precedence over chapter if both likely.
  def fetch_regulations(title, date = nil, chapter: nil, part: nil)
    date ||= get_latest_version_date(title)

    label = "Title #{title}"
    label += " Chapter #{chapter}" if chapter.present?
    label += " Part #{part}" if part.present?

    Rails.logger.info("Downloading XML for #{label}...")

    # Ideally only one of chapter or part is used.
    # If part is present, use part. If chapter is present, use chapter.
    url = "#{BASE_URL}/versioner/v1/full/#{date}/title-#{title}.xml"
    if part.present?
      url += "?part=#{part}"
    elsif chapter.present?
      url += "?chapter=#{chapter}"
    end

    # We return the tempfile path so the caller can attach it to a model
    # or process it immediately.
    filename_parts = [ "title-#{title}" ]
    filename_parts << "-chap-#{chapter}" if chapter.present?
    filename_parts << "-part-#{part}" if part.present?

    Tempfile.create([ filename_parts.join, ".xml" ]) do |tempfile|
      download_with_retry(url, tempfile.path)
      yield tempfile.path if block_given?
    end
  end

  # Fetch the structure (Table of Contents) for a Title
  # Returns a JSON hash representing the hierarchy
  def fetch_structure(title, date = nil)
    date ||= get_latest_version_date(title)
    cache_key = "ecfr/structure/#{date}/title-#{title}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRES_IN) do
      url = "#{BASE_URL}/versioner/v1/structure/#{date}/title-#{title}.json"
      response = get_with_retry(url)
      JSON.parse(response)
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
    # Calculate metrics on-the-fly without storing full content
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
                  GC.start # Force garbage collection between parts
                else
                  parts << current_part
                end
              end

              current_part = {
                part_number: node.attribute("N"),
                identifier: "Part #{node.attribute("N")}",
                word_count: 0,
                restrictions_count: 0
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
            # Calculate metrics WITHOUT storing the full text
            text = node.value
            current_part[:word_count] += text.split.size
            current_part[:restrictions_count] += text.scan(/\b(shall|must|prohibited|required)\b/i).size
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
          GC.start # Force garbage collection for the final part
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
  rescue Net::OpenTimeout, Net::ReadTimeout, RateLimitError, ApiError, OpenSSL::SSL::SSLError => e
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

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 600) do |http|
      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

      case response.code.to_i
      when 200 then response.body
      when 404 then raise NotFoundError, "Resource not found: #{url}"
      when 429 then raise RateLimitError, "Rate limit exceeded"
      when 500..599 then raise ApiError, "Server error: #{response.code}"
      else raise ApiError, "Unexpected status: #{response.code}"
      end
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, RateLimitError, ApiError, OpenSSL::SSL::SSLError => _e
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
