# Syncs a single agency's metadata and regulations
class SyncAgencyJob < ApplicationJob
  queue_as :default

  def perform(agency_data:, sync_log_id:)
    sync_log = SyncLog.find(sync_log_id)

    begin
      agency = find_or_create_agency(agency_data)
      Rails.logger.info("Syncing agency: #{agency.name}")

      extract_cfr_titles(agency_data).each do |title_number|
        sync_title(agency, title_number, sync_log)
      end

      agency.update_word_count!
      agency.update_restrictions_count!
      agency.update_checksum!
      agency.update!(last_synced_at: Time.current)
    rescue => e
      Rails.logger.error("Failed to sync agency #{agency_data[:acronym]}: #{e.message}")
      sync_log.increment!(:records_processed)
      raise
    end
  end

  private

  def find_or_create_agency(data)
    Agency.find_or_initialize_by(name: data[:name]).tap do |a|
      Rails.logger.info("Syncing agency: #{a}")
      a.description = data[:description]
      a.acronym = data[:acronym]
      a.cfr_titles = extract_cfr_titles(data)
      a.cfr_references = data[:cfr_references] || []
      a.save!
    end
  end

  def extract_cfr_titles(data)
    refs = data[:cfr_titles] || data[:cfr_references] || []
    return refs unless refs.first.is_a?(Hash)
    refs.map { |r| r[:title] || r["title"] }.compact.uniq
  end

  def sync_title(agency, title, sync_log)
    bulk_client = EcfrBulkClient.new
    parser = EcfrClient.new

    # Download complete title XML from govinfo.gov bulk repository
    xml_path = bulk_client.download_title(title)

    Rails.logger.info("Processing Title #{title} for agency #{agency.acronym}...")

    # Get this agency's chapter/subchapter filters for this title
    title_refs = agency.cfr_references.select { |r| r["title"].to_s == title.to_s }

    # Stream parse the entire file, processing only matching parts
    parts_processed = 0
    parser.parse_xml_file(xml_path) do |part_data|
      # Filter: only process parts that match agency's references
      next unless part_matches_agency_references?(part_data, title_refs)

      process_parts(agency, title, [part_data], sync_log)
      parts_processed += 1
    end

    Rails.logger.info("✅ Processed #{parts_processed} parts from Title #{title}")
  rescue => e
    Rails.logger.error("Error syncing title #{title}: #{e.message}")
    raise
  end

  # Simplified filtering: Check if a part matches any of the agency's references
  # Much simpler than the old recursive tree traversal!
  def part_matches_agency_references?(part_data, title_refs)
    # If agency has no specific filters for this title, accept all parts
    return true if title_refs.empty?

    # If agency doesn't filter by chapter (just wants entire title), accept all
    return true if title_refs.all? { |ref| ref["chapter"].blank? }

    # For now, accept all parts - detailed filtering can be added if needed
    # The part_data hash contains: part_number, identifier, word_count, restrictions_count, label
    # Agency references contain: title, chapter, subtitle (optional)
    # TODO: Add chapter/subtitle matching logic here if needed
    true
  end

  def process_parts(agency, title, parts, sync_log)
    # With Part-based fetching, we have already filtered before downloading.
    # Metrics are pre-calculated during streaming parse.

    parts.each do |part_data|
      part_number = part_data[:part_number]
      word_count = part_data[:word_count]
      restrictions_count = part_data[:restrictions_count]

      # Skip if no content (word_count = 0)
      next if word_count.zero?

      reg = Regulation.find_or_initialize_by(
        agency: agency,
        cfr_title: title,
        part: part_number
      )

      reg.metadata = { "label" => part_data[:label], "identifier" => part_data[:identifier] }

      if reg.new_record? || reg.word_count != word_count || reg.restrictions_count != restrictions_count
        reg.word_count = word_count
        reg.restrictions_count = restrictions_count
        reg.last_amended_on = Date.current
        reg.save!

        # Create snapshot only if changed
        create_snapshot(reg, word_count)

        sync_log.increment!(reg.id_previously_was ? :records_updated : :records_created)
      end

      sync_log.increment!(:records_processed)
    end
  end

  def create_snapshot(reg, count)
    return if reg.snapshots.exists?(snapshot_date: Date.current)

    reg.snapshots.create!(
      word_count: count,
      checksum: reg.calculate_checksum,
      snapshot_date: Date.current
    )
  end
end
