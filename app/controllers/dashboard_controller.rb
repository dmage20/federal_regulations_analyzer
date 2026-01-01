class DashboardController < ApplicationController
  def index
    # Get all agencies
    @agencies = Agency.all.order(total_word_count: :desc)

    # Key metrics
    @total_agencies = @agencies.count
    @total_regulations = Regulation.count
    @total_words = @agencies.sum(:total_word_count)
    @agencies_with_data = @agencies.where("regulations_count > 0").count

    # Chart data - top 15 agencies by word count
    @top_agencies_chart_data = @agencies
      .where("total_word_count > 0")
      .limit(15)
      .map { |a| [ a.acronym, a.total_word_count ] }

    # Snapshot analytics (if any snapshots exist)
    if RegulationSnapshot.exists?
      @total_snapshots = RegulationSnapshot.count
      @most_changed_regulations = Regulation
        .joins(:snapshots)
        .select("regulations.*, COUNT(DISTINCT regulation_snapshots.checksum) as change_count")
        .group("regulations.id")
        .having("COUNT(DISTINCT regulation_snapshots.checksum) > 1")
        .order("change_count DESC")
        .limit(5)
    end

    # Agency data for table
    @agency_table_data = @agencies.map do |agency|
      {
        agency: agency,
        word_count: agency.total_word_count,
        checksum: agency.content_checksum,
        regulations_count: agency.regulations_count,
        last_synced: agency.last_synced_at
      }
    end
  end

  def system_health
    # System Health Metrics
    @queue_depth = SolidQueue::Job.where(finished_at: nil).count
    @last_sync = SyncLog.where(status: "success").order(completed_at: :desc).first
    @api_status = check_api_status
    @agencies = Agency.order(:name)
  end

  def sync_agency
    agency = Agency.find(params[:id])

    sync_log = SyncLog.create!(
      sync_type: "manual_agency",
      status: "pending",
      started_at: Time.current
    )

    SyncAgencyJob.perform_later(
      agency_data: {
        name: agency.name,
        acronym: agency.acronym,
        description: agency.description,
        cfr_titles: agency.cfr_titles,
        cfr_references: agency.cfr_references
      },
      sync_log_id: sync_log.id
    )

    redirect_to system_health_path, notice: "Sync for #{agency.name} has been queued."
  end

  private

  def check_api_status
    # Cache the status for 2 minutes to prevent hammering the API
    # and slowing down the dashboard on every page load.
    Rails.cache.fetch("system_health/api_status", expires_in: 2.minutes) do
      begin
        if EcfrClient.new.check_connection
          :online
        else
          :offline
        end
      rescue StandardError => e
        Rails.logger.error("API Check Failed: #{e.message}")
        :offline
      end
    end
  end
end
