# Alternative to SyncAgencyJob that uses the streaming JSON parser
# (EcfrChapterExtractor) instead of downloading bulk XML files.
#
# This approach is more memory-efficient on resource-constrained environments
# (512MB RAM, 0.5 CPU) because it:
#   1. Streams the eCFR structure JSON instead of loading it entirely
#   2. Extracts only the specific chapter(s) needed via early termination
#   3. Uses the structure data to build regulation records without downloading XML
#
# Usage:
#   StreamingSyncAgencyJob.perform_later(
#     agency_data: { name: "EPA", acronym: "EPA", cfr_references: [...] },
#     sync_log_id: sync_log.id
#   )
#
class StreamingSyncAgencyJob < ApplicationJob
  queue_as :default

  def perform(agency_data:, sync_log_id:)
    sync_log = SyncLog.find(sync_log_id)

    begin
      agency = find_or_create_agency(agency_data)
      Rails.logger.info("[StreamingSync] Syncing agency: #{agency.name}")

      extract_cfr_references(agency_data).each do |ref|
        sync_title_reference(agency, ref, sync_log)
      end

      agency.update_word_count!
      agency.update_restrictions_count!
      agency.update_checksum!
      agency.update!(last_synced_at: Time.current)

      Rails.logger.info("[StreamingSync] Completed sync for #{agency.name}")
    rescue => e
      Rails.logger.error("[StreamingSync] Failed to sync agency #{agency_data[:acronym]}: #{e.message}")
      sync_log.increment!(:records_processed)
      raise
    end
  end

  private

  def find_or_create_agency(data)
    Agency.find_or_initialize_by(name: data[:name]).tap do |a|
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

  # CFR reference types that can appear in agency cfr_references.
  # The eCFR API returns references keyed by structural level.
  REFERENCE_TYPES = %w[chapter subtitle subchapter part].freeze

  # Returns an array of { title:, identifier:, type: } hashes for this agency.
  # Checks all structural reference types (chapter, subtitle, subchapter, part).
  # Falls back to title-only references if no structural info is present.
  def extract_cfr_references(data)
    refs = data[:cfr_references] || []

    parsed = refs.filter_map do |r|
      next unless r.is_a?(Hash)
      title = r[:title] || r["title"]
      next unless title

      ref_type, ref_id = extract_reference_type_and_id(r)
      { title: title.to_i, identifier: ref_id&.to_s, type: ref_type }
    end.uniq

    if parsed.any? { |r| r[:identifier].present? }
      parsed
    else
      extract_cfr_titles(data).map { |t| { title: t.to_i, identifier: nil, type: nil } }
    end
  end

  # Finds the first present structural key from the reference hash.
  def extract_reference_type_and_id(ref)
    REFERENCE_TYPES.each do |type|
      value = ref[type.to_sym] || ref[type]
      return [type, value] if value.present?
    end
    [nil, nil]
  end

  def sync_title_reference(agency, ref, sync_log)
    title = ref[:title]
    identifier = ref[:identifier]
    type = ref[:type]

    if identifier.present?
      sync_with_streaming_parser(agency, title, identifier, type, sync_log)
    else
      sync_title_structure(agency, title, sync_log)
    end
  rescue EcfrChapterExtractor::ExtractionError => e
    Rails.logger.warn("[StreamingSync] Extraction failed for Title #{title} #{type} #{identifier}: #{e.message}")
  rescue => e
    Rails.logger.error("[StreamingSync] Error syncing Title #{title} #{type} #{identifier}: #{e.message}")
    raise
  end

  # Use the streaming extractor to get structure data for a specific node
  def sync_with_streaming_parser(agency, title, identifier, type, sync_log)
    date = latest_date_for_title(title)

    extractor = EcfrChapterExtractor.new(date: date, title: title, chapter: identifier, type: type)
    node_data = extractor.call

    Rails.logger.info(
      "[StreamingSync] Extracted #{type} #{identifier} from Title #{title}: " \
      "#{node_data["children"]&.size || 0} top-level children"
    )

    process_chapter_children(agency, title, node_data, sync_log)
  end

  # Fallback: fetch full structure for a title (no chapter filter)
  def sync_title_structure(agency, title, sync_log)
    client = EcfrClient.new
    date = latest_date_for_title(title)
    structure = client.fetch_structure(title, date)

    children = structure["children"] || structure[:children] || []
    children.each do |child|
      process_chapter_children(agency, title, child, sync_log) if child_is_chapter?(child)
    end
  end

  # Walk the chapter's children tree to find parts and create/update regulations
  def process_chapter_children(agency, title, node, sync_log)
    type = node["type"] || node[:type]
    children = node["children"] || node[:children] || []

    if type == "part"
      process_part(agency, title, node, sync_log)
    else
      children.each do |child|
        process_chapter_children(agency, title, child, sync_log)
      end
    end
  end

  def process_part(agency, title, part_node, sync_log)
    identifier = part_node["identifier"] || part_node[:identifier]
    label = part_node["label"] || part_node[:label]
    children = part_node["children"] || part_node[:children] || []

    # Estimate word count from the structure tree (count of descendant sections)
    section_count = count_sections(part_node)
    # Use section count as a proxy — the structure doesn't have full text
    estimated_word_count = section_count

    return if identifier.blank?

    reg = Regulation.find_or_initialize_by(
      agency: agency,
      cfr_title: title,
      part: identifier
    )

    reg.metadata = { "label" => label, "identifier" => identifier }

    # Only update if this is new or the section count has changed
    if reg.new_record? || reg.word_count != estimated_word_count
      reg.word_count = estimated_word_count
      reg.restrictions_count ||= 0
      reg.last_amended_on = Date.current
      reg.save!

      create_snapshot(reg)

      sync_log.increment!(reg.id_previously_was ? :records_updated : :records_created)
    end

    sync_log.increment!(:records_processed)
  end

  def count_sections(node)
    type = node["type"] || node[:type]
    children = node["children"] || node[:children] || []

    count = (type == "section") ? 1 : 0
    children.each { |child| count += count_sections(child) }
    count
  end

  def create_snapshot(reg)
    return if reg.snapshots.exists?(snapshot_date: Date.current)

    reg.snapshots.create!(
      word_count: reg.word_count,
      checksum: reg.calculate_checksum,
      snapshot_date: Date.current
    )
  end

  def child_is_chapter?(node)
    (node["type"] || node[:type]) == "chapter"
  end

  def latest_date_for_title(title)
    @latest_dates ||= {}
    @latest_dates[title] ||= EcfrClient.new.get_latest_version_date(title)
  end
end
