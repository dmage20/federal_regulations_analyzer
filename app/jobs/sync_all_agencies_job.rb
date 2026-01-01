# Orchestrator job to sync all agencies from eCFR API
# Fetches the agency list and enqueues individual SyncAgencyJob for each
class SyncAllAgenciesJob < ApplicationJob
  queue_as :default

  def perform(sync_type: "full")
    sync_log = SyncLog.create!(
      sync_type: sync_type,
      started_at: Time.current,
      status: "running"
    )

    begin
      client = EcfrClient.new
      agencies_data = client.fetch_agencies

      Rails.logger.info("Enqueuing sync jobs for #{agencies_data.length} agencies from eCFR")

      agencies_data.each do |agency_data|
        SyncAgencyJob.perform_later(
          agency_data: agency_data,
          sync_log_id: sync_log.id
        )
      end

      sync_log.update!(
        summary: {
          total_agencies: agencies_data.length,
          enqueued_at: Time.current
        }
      )

      finalize_sync(sync_log, "success")
    rescue StandardError => e
      handle_sync_error(sync_log, e)
      raise
    end
  end

  private

  def finalize_sync(sync_log, status)
    sync_log.update!(
      status: status,
      completed_at: Time.current
    )

    Rails.logger.info(
      "Sync orchestration completed: #{sync_log.summary['total_agencies']} agencies enqueued"
    )
  end

  def handle_sync_error(sync_log, error)
    sync_log.update!(
      status: "failed",
      completed_at: Time.current,
      error_messages: error.message + "\n" + error.backtrace.first(5).join("\n")
    )

    Rails.logger.error("Sync orchestration failed: #{error.message}")
  end
end
