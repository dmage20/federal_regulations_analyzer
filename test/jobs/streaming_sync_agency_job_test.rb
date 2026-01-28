require "test_helper"
require "webmock/minitest"

class StreamingSyncAgencyJobTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)

    @sync_log = SyncLog.create!(
      sync_type: "full",
      status: "running",
      started_at: Time.current,
      records_processed: 0,
      records_created: 0,
      records_updated: 0
    )

    @agency_data = {
      name: "Council on Environmental Quality",
      acronym: "CEQ",
      description: "Coordinates federal environmental efforts",
      cfr_titles: [ 40 ],
      cfr_references: [
        { "title" => 40, "chapter" => "III" }
      ]
    }

    stub_latest_version_date
  end

  teardown do
    WebMock.reset!
    Rails.cache.clear
  end

  test "creates agency and syncs regulations from streaming chapter data" do
    stub_chapter_structure_api(chapter_response)

    assert_difference "Agency.count", 1 do
      assert_difference "Regulation.count", 2 do
        StreamingSyncAgencyJob.new.perform(
          agency_data: @agency_data,
          sync_log_id: @sync_log.id
        )
      end
    end

    agency = Agency.find_by(acronym: "CEQ")
    assert_not_nil agency
    assert_equal "Council on Environmental Quality", agency.name
    assert_equal [ 40 ], agency.cfr_titles
    assert_not_nil agency.last_synced_at
  end

  test "creates regulation records for each part found in chapter" do
    stub_chapter_structure_api(chapter_response)

    StreamingSyncAgencyJob.new.perform(
      agency_data: @agency_data,
      sync_log_id: @sync_log.id
    )

    agency = Agency.find_by(acronym: "CEQ")
    regulations = agency.regulations.order(:part)

    assert_equal 2, regulations.size
    assert_equal "1500", regulations.first.part
    assert_equal "1501", regulations.second.part
    assert_equal 40, regulations.first.cfr_title
  end

  test "updates existing agency on re-sync" do
    Agency.create!(
      name: "Council on Environmental Quality",
      acronym: "CEQ",
      description: "Old description"
    )

    stub_chapter_structure_api(chapter_response)

    assert_no_difference "Agency.count" do
      StreamingSyncAgencyJob.new.perform(
        agency_data: @agency_data,
        sync_log_id: @sync_log.id
      )
    end

    agency = Agency.find_by(acronym: "CEQ")
    assert_equal "Coordinates federal environmental efforts", agency.description
  end

  test "creates snapshots for new regulations" do
    stub_chapter_structure_api(chapter_response)

    assert_difference "RegulationSnapshot.count", 2 do
      StreamingSyncAgencyJob.new.perform(
        agency_data: @agency_data,
        sync_log_id: @sync_log.id
      )
    end
  end

  test "increments sync_log counters" do
    stub_chapter_structure_api(chapter_response)

    StreamingSyncAgencyJob.new.perform(
      agency_data: @agency_data,
      sync_log_id: @sync_log.id
    )

    @sync_log.reload
    assert @sync_log.records_processed >= 2
  end

  test "handles agency with no chapter references gracefully" do
    @agency_data[:cfr_references] = []
    @agency_data[:cfr_titles] = [ 40 ]

    # Falls back to fetching full structure
    stub_full_structure_api

    StreamingSyncAgencyJob.new.perform(
      agency_data: @agency_data,
      sync_log_id: @sync_log.id
    )

    agency = Agency.find_by(acronym: "CEQ")
    assert_not_nil agency
  end

  test "handles extraction error without crashing" do
    stub_request(:get, %r{versioner/v1/structure/.*title-40\.json})
      .to_return(status: 200, body: {
        "identifier" => "40",
        "type" => "title",
        "children" => []
      }.to_json, headers: { "Content-Type" => "application/json" })

    # Should log the ChapterNotFound but not re-raise
    StreamingSyncAgencyJob.new.perform(
      agency_data: @agency_data,
      sync_log_id: @sync_log.id
    )

    agency = Agency.find_by(acronym: "CEQ")
    assert_not_nil agency
  end

  test "handles multiple title references" do
    @agency_data[:cfr_references] = [
      { "title" => 40, "chapter" => "III" },
      { "title" => 21, "chapter" => "I" }
    ]
    @agency_data[:cfr_titles] = [ 40, 21 ]

    stub_chapter_structure_api(chapter_response)
    stub_latest_version_date(21)
    stub_request(:get, %r{versioner/v1/structure/.*title-21\.json})
      .to_return(status: 200, body: {
        "identifier" => "21",
        "type" => "title",
        "children" => [
          {
            "identifier" => "I",
            "type" => "chapter",
            "label" => "Chapter I—FDA",
            "children" => [
              { "identifier" => "100", "type" => "part", "label" => "Part 100", "children" => [
                { "identifier" => "100.1", "type" => "section", "label" => "Section 100.1", "children" => [] }
              ] }
            ]
          }
        ]
      }.to_json, headers: { "Content-Type" => "application/json" })

    StreamingSyncAgencyJob.new.perform(
      agency_data: @agency_data,
      sync_log_id: @sync_log.id
    )

    agency = Agency.find_by(acronym: "CEQ")
    assert agency.regulations.count >= 2
  end

  private

  def stub_latest_version_date(title = 40)
    stub_request(:get, %r{versioner/v1/versions/title-#{title}\.json})
      .to_return(status: 200, body: {
        "available_on" => [ "2024-01-01", "2023-06-01" ]
      }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_chapter_structure_api(response_hash)
    stub_request(:get, %r{versioner/v1/structure/.*title-40\.json})
      .to_return(
        status: 200,
        body: full_title_response_with_chapter(response_hash).to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_full_structure_api
    stub_request(:get, %r{versioner/v1/structure/.*title-40\.json})
      .to_return(
        status: 200,
        body: {
          "identifier" => "40",
          "type" => "title",
          "label" => "Title 40",
          "children" => [
            {
              "identifier" => "I",
              "type" => "chapter",
              "label" => "Chapter I",
              "children" => [
                { "identifier" => "1", "type" => "part", "label" => "Part 1", "children" => [
                  { "identifier" => "1.1", "type" => "section", "label" => "Section 1.1", "children" => [] }
                ] }
              ]
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def full_title_response_with_chapter(chapter_data)
    {
      "identifier" => "40",
      "type" => "title",
      "label" => "Title 40—Protection of Environment",
      "children" => [
        {
          "identifier" => "I",
          "type" => "chapter",
          "label" => "Chapter I—EPA",
          "children" => []
        },
        chapter_data,
        {
          "identifier" => "IV",
          "type" => "chapter",
          "label" => "Chapter IV—Other",
          "children" => []
        }
      ]
    }
  end

  def chapter_response
    {
      "identifier" => "III",
      "type" => "chapter",
      "label" => "Chapter III—Council on Environmental Quality",
      "children" => [
        {
          "identifier" => "A",
          "type" => "subchapter",
          "label" => "Subchapter A—Regulations",
          "children" => [
            {
              "identifier" => "1500",
              "type" => "part",
              "label" => "Part 1500—Purpose, Policy, and Mandate",
              "children" => [
                { "identifier" => "1500.1", "type" => "section", "label" => "Section 1500.1", "children" => [] },
                { "identifier" => "1500.2", "type" => "section", "label" => "Section 1500.2", "children" => [] },
                { "identifier" => "1500.3", "type" => "section", "label" => "Section 1500.3", "children" => [] }
              ]
            },
            {
              "identifier" => "1501",
              "type" => "part",
              "label" => "Part 1501—NEPA and Agency Planning",
              "children" => [
                { "identifier" => "1501.1", "type" => "section", "label" => "Section 1501.1", "children" => [] },
                { "identifier" => "1501.2", "type" => "section", "label" => "Section 1501.2", "children" => [] }
              ]
            }
          ]
        }
      ]
    }
  end
end
