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
    structure = EcfrClient.new.fetch_structure(title)

    # Identify all Parts that this agency cares about
    parts_to_fetch = collect_matching_parts(structure, agency.cfr_references)

    Rails.logger.info("Agency #{agency.acronym} needs #{parts_to_fetch.size} parts for Title #{title}")

    parts_to_fetch.each do |part_node|
       part_number = part_node["identifier"]

       EcfrClient.new.fetch_regulations(title, part: part_number) do |file_path|
         EcfrClient.new.parse_xml_file(file_path) do |part_data|
           process_parts(agency, title, [ part_data ], sync_log)
         end
       end
    end
  rescue => e
    Rails.logger.error("Error syncing title #{title}: #{e.message}")
  end

  # Recursively traverse the structure to find 'part' nodes that match the allowed references
  def collect_matching_parts(node, references, current_context = {})
    matches = []

    # Update context based on current node
    context = current_context.dup
    case node["type"]
    when "title"
      context[:title] = node["identifier"]
    when "chapter"
      context[:chapter] = node["identifier"]
    when "subchapter"
      context[:subtitle] = node["identifier"] # Agency ref calls it "subtitle", API says "subchapter"
    end

    # If it's a PART, check if it matches
    if node["type"] == "part"
       if part_matches_references?(context, references)
         matches << node
       end
    elsif node["children"].present?
      # Recurse
      node["children"].each do |child|
        matches.concat(collect_matching_parts(child, references, context))
      end
    end

    matches
  end

  def part_matches_references?(context, references)
    # Filter references for this Title
    title_refs = references.select { |r| r["title"].to_s == context[:title].to_s }
    return false if title_refs.empty?

    # If any reference allows this part based on Chapter/Subtitle, return true
    title_refs.any? do |ref|
      chapter_match = ref["chapter"].blank? || (ref["chapter"] == context[:chapter])
      subtitle_match = ref["subtitle"].blank? || (ref["subtitle"] == context[:subtitle])

      chapter_match && subtitle_match
    end
  end

  def process_parts(agency, title, parts, sync_log)
    # With Part-based fetching, we have already filtered before downloading.
    # However, we keep the processing logic simple.

    parts.each do |part_data|
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
