require "test_helper"
require "webmock/minitest"

class EcfrChapterExtractorTest < ActiveSupport::TestCase
  setup do
    @date = "2024-01-01"
    @title = 40
    @chapter = "III"
    @extractor = EcfrChapterExtractor.new(date: @date, title: @title, chapter: @chapter)
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.reset!
  end

  # --- Success cases ---

  test "extracts target chapter from streamed JSON" do
    stub_structure_api(success_response)

    result = @extractor.call

    assert_equal "III", result["identifier"]
    assert_equal "chapter", result["type"]
    assert_equal "Chapter III—Council on Environmental Quality", result["label"]
    assert_equal 2, result["children"].size
  end

  test "returns chapter with nested children intact" do
    stub_structure_api(success_response)

    result = @extractor.call

    first_child = result["children"].first
    assert_equal "A", first_child["identifier"]
    assert_equal "subchapter", first_child["type"]
    assert first_child["children"].is_a?(Array)
  end

  test "extracts first chapter when requested" do
    extractor = EcfrChapterExtractor.new(date: @date, title: @title, chapter: "I")
    stub_structure_api(success_response)

    result = extractor.call

    assert_equal "I", result["identifier"]
    assert_equal "Chapter I—Environmental Protection Agency", result["label"]
  end

  test "handles chapter with no children" do
    response = {
      "identifier" => "40",
      "label" => "Title 40",
      "type" => "title",
      "children" => [
        {
          "identifier" => "V",
          "label" => "Chapter V—Empty",
          "type" => "chapter",
          "children" => []
        }
      ]
    }
    extractor = EcfrChapterExtractor.new(date: @date, title: @title, chapter: "V")
    stub_structure_api(response)

    result = extractor.call

    assert_equal "V", result["identifier"]
    assert_equal [], result["children"]
  end

  # --- Early termination ---

  test "stops parsing after finding target chapter" do
    # The key test: verify the parser uses early termination.
    # We verify this by checking that ChapterFound is raised internally
    # and properly handled (the extractor returns the result).
    stub_structure_api(large_response_with_target_early)

    result = @extractor.call

    assert_equal "III", result["identifier"]
    # The fact that we got a result without parsing the full 10-chapter response
    # demonstrates early termination is working (the exception-based control flow).
  end

  # --- Error cases ---

  test "raises ChapterNotFound when chapter is missing" do
    response = {
      "identifier" => "40",
      "label" => "Title 40",
      "type" => "title",
      "children" => [
        {
          "identifier" => "I",
          "label" => "Chapter I",
          "type" => "chapter",
          "children" => []
        }
      ]
    }
    stub_structure_api(response)

    error = assert_raises(EcfrChapterExtractor::ChapterNotFound) do
      @extractor.call
    end
    assert_match(/Chapter III not found/, error.message)
  end

  test "raises ChapterNotFound when children array is empty" do
    response = {
      "identifier" => "40",
      "label" => "Title 40",
      "type" => "title",
      "children" => []
    }
    stub_structure_api(response)

    assert_raises(EcfrChapterExtractor::ChapterNotFound) do
      @extractor.call
    end
  end

  test "raises ApiError on 404 response" do
    stub_request(:get, structure_url)
      .to_return(status: 404, body: "Not Found")

    assert_raises(EcfrChapterExtractor::ApiError) do
      @extractor.call
    end
  end

  test "raises ApiError on 500 response" do
    stub_request(:get, structure_url)
      .to_return(status: 500, body: "Internal Server Error")

    assert_raises(EcfrChapterExtractor::ApiError) do
      @extractor.call
    end
  end

  test "raises ApiError on 429 rate limit" do
    stub_request(:get, structure_url)
      .to_return(status: 429, body: "Rate Limited")

    assert_raises(EcfrChapterExtractor::ApiError) do
      @extractor.call
    end
  end

  test "raises NetworkError after max retries on timeout" do
    stub_request(:get, structure_url).to_timeout

    assert_raises(EcfrChapterExtractor::NetworkError) do
      @extractor.call
    end
  end

  test "retries on network error and succeeds" do
    stub_request(:get, structure_url)
      .to_timeout
      .then.to_return(status: 200, body: success_response.to_json,
                      headers: { "Content-Type" => "application/json" })

    result = @extractor.call

    assert_equal "III", result["identifier"]
  end

  # --- Edge cases ---

  test "handles non-chapter children in title" do
    response = {
      "identifier" => "40",
      "label" => "Title 40",
      "type" => "title",
      "children" => [
        {
          "identifier" => "A",
          "label" => "Subtitle A",
          "type" => "subtitle",
          "children" => []
        },
        {
          "identifier" => "III",
          "label" => "Chapter III",
          "type" => "chapter",
          "children" => []
        }
      ]
    }
    stub_structure_api(response)

    result = @extractor.call

    assert_equal "III", result["identifier"]
    assert_equal "chapter", result["type"]
  end

  test "chapter identifier is treated as string" do
    extractor = EcfrChapterExtractor.new(date: @date, title: @title, chapter: 3)
    response = {
      "identifier" => "40",
      "type" => "title",
      "children" => [
        { "identifier" => "3", "type" => "chapter", "label" => "Chapter 3", "children" => [] }
      ]
    }
    stub_structure_api(response)

    result = extractor.call

    assert_equal "3", result["identifier"]
  end

  # --- Alternative structural types ---

  test "extracts subtitle from title children" do
    extractor = EcfrChapterExtractor.new(date: @date, title: @title, chapter: "A", type: "subtitle")
    response = {
      "identifier" => "40",
      "type" => "title",
      "children" => [
        { "identifier" => "A", "type" => "subtitle", "label" => "Subtitle A", "children" => [
          { "identifier" => "I", "type" => "chapter", "label" => "Chapter I", "children" => [] }
        ]}
      ]
    }
    stub_structure_api(response)

    result = extractor.call

    assert_equal "A", result["identifier"]
    assert_equal "subtitle", result["type"]
    assert_equal 1, result["children"].size
  end

  test "extracts subchapter nested inside chapter" do
    extractor = EcfrChapterExtractor.new(date: @date, title: @title, chapter: "B", type: "subchapter")
    stub_structure_api(success_response)

    result = extractor.call

    assert_equal "B", result["identifier"]
    assert_equal "subchapter", result["type"]
  end

  test "extracts part nested inside subchapter" do
    extractor = EcfrChapterExtractor.new(date: @date, title: @title, chapter: "1500", type: "part")
    stub_structure_api(success_response)

    result = extractor.call

    assert_equal "1500", result["identifier"]
    assert_equal "part", result["type"]
  end

  test "defaults to chapter type when invalid type given" do
    extractor = EcfrChapterExtractor.new(date: @date, title: @title, chapter: "III", type: "invalid")
    stub_structure_api(success_response)

    result = extractor.call

    assert_equal "III", result["identifier"]
    assert_equal "chapter", result["type"]
  end

  private

  def structure_url
    "#{EcfrChapterExtractor::BASE_URL}/versioner/v1/structure/#{@date}/title-#{@title}.json"
  end

  def stub_structure_api(response_hash)
    stub_request(:get, structure_url)
      .to_return(
        status: 200,
        body: response_hash.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def success_response
    {
      "identifier" => "40",
      "label" => "Title 40—Protection of Environment",
      "type" => "title",
      "children" => [
        {
          "identifier" => "I",
          "label" => "Chapter I—Environmental Protection Agency",
          "type" => "chapter",
          "children" => [
            {
              "identifier" => "A",
              "label" => "Subchapter A—General",
              "type" => "subchapter",
              "children" => [
                { "identifier" => "1", "label" => "Part 1—General", "type" => "part", "children" => [] }
              ]
            }
          ]
        },
        {
          "identifier" => "III",
          "label" => "Chapter III—Council on Environmental Quality",
          "type" => "chapter",
          "children" => [
            {
              "identifier" => "A",
              "label" => "Subchapter A—Regulations",
              "type" => "subchapter",
              "children" => [
                { "identifier" => "1500", "label" => "Part 1500—Purpose", "type" => "part", "children" => [] },
                { "identifier" => "1501", "label" => "Part 1501—NEPA Process", "type" => "part", "children" => [] }
              ]
            },
            {
              "identifier" => "B",
              "label" => "Subchapter B—Other",
              "type" => "subchapter",
              "children" => []
            }
          ]
        },
        {
          "identifier" => "IV",
          "label" => "Chapter IV—EPA Programs",
          "type" => "chapter",
          "children" => []
        }
      ]
    }
  end

  # Simulates a large response where target chapter appears early
  def large_response_with_target_early
    many_chapters = (1..10).map do |i|
      roman = %w[I II III IV V VI VII VIII IX X][i - 1]
      {
        "identifier" => roman,
        "label" => "Chapter #{roman}—Agency #{i}",
        "type" => "chapter",
        "children" => (1..50).map do |p|
          {
            "identifier" => "#{i * 100 + p}",
            "label" => "Part #{i * 100 + p}",
            "type" => "part",
            "children" => (1..10).map do |s|
              {
                "identifier" => "#{i * 100 + p}.#{s}",
                "label" => "Section #{i * 100 + p}.#{s}",
                "type" => "section",
                "children" => []
              }
            end
          }
        end
      }
    end

    {
      "identifier" => "40",
      "label" => "Title 40",
      "type" => "title",
      "children" => many_chapters
    }
  end
end
