require "test_helper"
require "webmock/minitest"

class EcfrClientTest < ActiveSupport::TestCase
  setup do
    @client = EcfrClient.new
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.reset!
    Rails.cache.clear
  end

  test "fetch_agencies returns parsed agency data" do
    stub_agencies_api

    agencies = @client.fetch_agencies

    assert_equal 2, agencies.length
    assert_equal "Environmental Protection Agency", agencies.first[:name]
    assert_equal "EPA", agencies.first[:acronym]
    assert_includes agencies.first[:cfr_titles], 40
  end

  test "fetch_agencies caches response" do
    stub_agencies_api

    # First call hits API
    @client.fetch_agencies

    # Second call should use cache (stub will not be called again)
    WebMock.reset!
    agencies = @client.fetch_agencies

    assert_equal 2, agencies.length
  end

  test "fetch_title_structure returns structure data" do
    stub_structure_api(1)

    structure = @client.fetch_title_structure(1, Date.new(2024, 1, 1))

    assert_equal 1, structure[:title_number]
    assert_equal "Title 1", structure[:label]
    assert structure[:children].any?
  end

  test "fetch_regulations returns regulation data in JSON format" do
    stub_regulations_api(40, :json)

    regulations = @client.fetch_regulations(40, Date.new(2024, 1, 1), format: :json)

    assert regulations.present?
    assert regulations.is_a?(Hash)
  end

  test "fetch_regulations returns regulation data in XML format" do
    stub_regulations_api(40, :xml)

    regulations = @client.fetch_regulations(40, Date.new(2024, 1, 1), format: :xml)

    assert regulations.present?
    assert_equal 2, regulations[:sections].length
    assert_equal "261.1", regulations[:sections].first[:section_number]
  end

  test "fetch_part returns specific part data" do
    stub_part_api(40, "261")

    part = @client.fetch_part(40, "261", Date.new(2024, 1, 1))

    assert_equal 40, part[:title]
    assert_equal "261", part[:part]
    assert part[:content].present?
  end

  test "handles 404 errors" do
    stub_request(:get, %r{ecfr.gov/api/})
      .to_return(status: 404, body: "Not Found")

    assert_raises(EcfrClient::NotFoundError) do
      @client.fetch_agencies
    end
  end

  test "handles 429 rate limit errors with retry" do
    # First two calls return 429, third succeeds
    stub_request(:get, %r{ecfr.gov/api/admin/v1/agencies})
      .to_return({ status: 429 }, { status: 429 }, { status: 200, body: agencies_response })

    agencies = @client.fetch_agencies

    assert agencies.present?
  end

  test "handles 500 server errors with retry" do
    # First call fails, second succeeds
    stub_request(:get, %r{ecfr.gov/api/admin/v1/agencies})
      .to_return({ status: 500 }, { status: 200, body: agencies_response })

    agencies = @client.fetch_agencies

    assert agencies.present?
  end

  test "raises error after max retries exceeded" do
    stub_request(:get, %r{ecfr.gov/api/admin/v1/agencies})
      .to_return(status: 500)

    assert_raises(EcfrClient::ApiError) do
      @client.fetch_agencies
    end
  end

  test "handles JSON parse errors gracefully" do
    stub_request(:get, %r{ecfr.gov/api/admin/v1/agencies})
      .to_return(status: 200, body: "invalid json{")

    agencies = @client.fetch_agencies

    assert_equal [], agencies
  end

  test "handles XML parse errors gracefully" do
    stub_request(:get, %r{ecfr.gov/api/versioner/v1/full/.*\.xml})
      .to_return(status: 200, body: "invalid xml<>")

    regulations = @client.fetch_regulations(40, Date.new(2024, 1, 1), format: :xml)

    assert_equal({ sections: [] }, regulations)
  end

  test "extracts acronym from agency name when not provided" do
    stub_request(:get, %r{ecfr.gov/api/admin/v1/agencies})
      .to_return(status: 200, body: {
        agencies: [
          { name: "Food and Drug Administration", short_name: nil }
        ]
      }.to_json)

    agencies = @client.fetch_agencies

    assert_equal "FDA", agencies.first[:acronym]
  end

  private

  def stub_agencies_api
    stub_request(:get, "#{EcfrClient::BASE_URL}/admin/v1/agencies.json")
      .to_return(status: 200, body: agencies_response)
  end

  def stub_structure_api(title_number)
    stub_request(:get, %r{ecfr.gov/api/versioner/v1/structure/.*title-#{title_number}\.json})
      .to_return(status: 200, body: structure_response(title_number))
  end

  def stub_regulations_api(title, format)
    extension = format == :xml ? "xml" : "json"
    body = format == :xml ? xml_response : json_response

    stub_request(:get, %r{ecfr.gov/api/versioner/v1/full/.*title-#{title}\.#{extension}})
      .to_return(status: 200, body: body)
  end

  def stub_part_api(title, part)
    stub_request(:get, %r{ecfr.gov/api/versioner/v1/full/.*title-#{title}/part-#{part}\.json})
      .to_return(status: 200, body: part_response(title, part))
  end

  def agencies_response
    {
      agencies: [
        {
          name: "Environmental Protection Agency",
          short_name: "EPA",
          description: "Protects human health and the environment",
          title_numbers: [40]
        },
        {
          name: "Food and Drug Administration",
          short_name: "FDA",
          description: "Protects public health",
          title_numbers: [21]
        }
      ]
    }.to_json
  end

  def structure_response(title_number)
    {
      title_number: title_number,
      identifier: "title-#{title_number}",
      label: "Title #{title_number}",
      reserved: false,
      children: [
        {
          identifier: "part-1",
          label: "Part 1",
          type: "part",
          reserved: false,
          children: [
            {
              identifier: "section-1.1",
              label: "Section 1.1",
              type: "section",
              reserved: false,
              children: []
            }
          ]
        }
      ]
    }.to_json
  end

  def json_response
    {
      title: 40,
      parts: [
        {
          part_number: "261",
          label: "Part 261 - Identification of Hazardous Waste",
          content: "This part identifies solid wastes that are hazardous waste."
        }
      ]
    }.to_json
  end

  def xml_response
    <<~XML
      <?xml version="1.0"?>
      <CFR>
        <SECTION N="261.1">
          <SUBJECT>Purpose and scope</SUBJECT>
          <P>This section establishes criteria for identifying hazardous waste.</P>
          <P>The criteria are used to determine which wastes require regulation.</P>
        </SECTION>
        <SECTION N="261.2">
          <SUBJECT>Definition of solid waste</SUBJECT>
          <P>A solid waste is any discarded material.</P>
        </SECTION>
      </CFR>
    XML
  end

  def part_response(title, part)
    {
      title: title,
      part_number: part,
      label: "Part #{part}",
      text: "This is the regulation content for Title #{title}, Part #{part}.",
      children: [
        {
          identifier: "section-#{part}.1",
          text: "Section content here",
          children: []
        }
      ]
    }.to_json
  end
end
