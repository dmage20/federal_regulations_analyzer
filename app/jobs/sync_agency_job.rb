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
    allowed_refs = agency.cfr_references.select { |r| r["title"].to_s == title.to_s }
    specific_chapters = allowed_refs.map { |r| r["chapter"] }.compact.uniq

    # If we have specific chapters, fetch specific chapters only
    # If no specific chapters (e.g. whole title assigned), fetch whole title (nil chapter)
    chapters_to_fetch = specific_chapters.any? ? specific_chapters : [ nil ]

    chapters_to_fetch.each do |chapter|
       EcfrClient.new.fetch_regulations(title, chapter: chapter) do |file_path|
         EcfrClient.new.parse_xml_file(file_path) do |part_data|
           # If we are fetching by chapter, we don't need to filter again,
           # but the processing logic is generic so keeping it safe.
           process_parts(agency, title, [ part_data ], sync_log)
         end
       end
    end
  rescue => e
    Rails.logger.error("Error syncing title #{title}: #{e.message}")
  end

  def process_parts(agency, title, parts, sync_log)
    allowed_refs = agency.cfr_references.select { |r| r["title"].to_s == title.to_s }
    has_specific_filters = allowed_refs.any? { |r| r["chapter"].present? || r["subtitle"].present? }

    parts.each do |part_data|
      # Filter by chapter/subtitle if agency has specific assignments
      if has_specific_filters
        # A part is allowed if it matches ANY of the allowed references
        match = allowed_refs.any? do |ref|
          # A reference matches if all its specified constraints are met by the part
          # KNOWN LIMITATION: WHEN CHAPTER IS NOT PRESENT BUT SUBTITLE IS, IT IS NOT MATCHED
          chapter_match = ref["chapter"].blank? || (ref["chapter"] == part_data[:chapter])
          subtitle_match = ref["subtitle"].blank? || (ref["subtitle"] == part_data[:subtitle])

          chapter_match && subtitle_match
        end

        next unless match
      end

      # Skip if no content
      next if part_data[:content].blank?

      part_number = part_data[:part_number]
      content = part_data[:content]
      word_count = content.split.size
      restrictions_count = content.scan(/\b(shall|must|may not|prohibited|required)\b/i).size

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
