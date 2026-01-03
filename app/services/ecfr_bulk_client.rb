# Service class for downloading bulk eCFR data from govinfo.gov
# Uses pre-generated XML files instead of the eCFR API to avoid timeouts and rate limiting
class EcfrBulkClient
  require "net/http"
  require "uri"
  require "fileutils"

  BULK_BASE_URL = "https://www.govinfo.gov/bulkdata/ECFR"
  MAX_RETRIES = 3
  INITIAL_RETRY_DELAY = 2 # seconds
  CACHE_DIR = Rails.root.join("tmp", "ecfr_bulk")

  class DownloadError < StandardError; end

  def initialize
    # Ensure cache directory exists
    FileUtils.mkdir_p(CACHE_DIR)
  end

  # Download a complete CFR title XML file
  # @param title [Integer] CFR title number (1-50)
  # @param use_cache [Boolean] Whether to use cached file if available
  # @return [String] Path to downloaded XML file
  def download_title(title, use_cache: true)
    cache_file = cache_path_for_title(title)

    # Check cache first
    if use_cache && cache_file.exist? && cache_fresh?(cache_file)
      Rails.logger.info("Using cached Title #{title} (#{file_size_mb(cache_file)} MB)")
      return cache_file.to_s
    end

    # Download fresh copy
    url = "#{BULK_BASE_URL}/title-#{title}/ECFR-title#{title}.xml"
    Rails.logger.info("Downloading bulk Title #{title} from govinfo.gov...")

    download_with_retry(url, cache_file.to_s)

    Rails.logger.info("✅ Downloaded Title #{title}: #{file_size_mb(cache_file)} MB")
    cache_file.to_s
  end

  # Check if bulk data is available for a title
  def title_available?(title)
    (1..50).include?(title)
  end

  private

  def cache_path_for_title(title)
    CACHE_DIR.join("title-#{title}.xml")
  end

  def cache_fresh?(cache_file)
    # Consider cache fresh if modified within last 24 hours
    cache_file.mtime > 24.hours.ago
  end

  def file_size_mb(file_path)
    (File.size(file_path) / 1_048_576.0).round(2)
  end

  def download_with_retry(url, destination_path, attempt: 1)
    uri = URI(url)

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 600) do |http|
      request = Net::HTTP::Get.new(uri)

      http.request(request) do |response|
        case response.code.to_i
        when 200
          File.open(destination_path, "wb") do |file|
            response.read_body do |chunk|
              file.write(chunk)
            end
          end
        when 404
          raise DownloadError, "Title not found in bulk repository: #{url}"
        when 500..599
          raise DownloadError, "Server error: #{response.code}"
        else
          raise DownloadError, "Unexpected status: #{response.code}"
        end
      end
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, DownloadError => e
    if attempt < MAX_RETRIES
      delay = INITIAL_RETRY_DELAY * (2 ** (attempt - 1))
      Rails.logger.warn("Download failed (attempt #{attempt}/#{MAX_RETRIES}): #{e.message}. Retrying in #{delay}s...")
      sleep(delay)
      download_with_retry(url, destination_path, attempt: attempt + 1)
    else
      raise DownloadError, "Failed to download after #{MAX_RETRIES} attempts: #{e.message}"
    end
  end
end
