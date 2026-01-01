class SyncLog < ApplicationRecord
  SYNC_TYPES = %w[full incremental agency manual_agency].freeze
  STATUSES = %w[running success failed partial pending].freeze

  validates :sync_type, presence: true, inclusion: { in: SYNC_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "failed") }
  scope :running, -> { where(status: "running") }

  def self.start!(sync_type)
    create!(
      sync_type: sync_type,
      status: "running",
      started_at: Time.current,
      records_processed: 0,
      records_created: 0,
      records_updated: 0
    )
  end

  def complete!(stats = {})
    update!(
      status: "success",
      completed_at: Time.current,
      records_processed: stats[:processed] || records_processed,
      records_created: stats[:created] || records_created,
      records_updated: stats[:updated] || records_updated,
      summary: stats[:summary] || {}
    )
  end

  def fail!(error_message)
    update!(
      status: "failed",
      completed_at: Time.current,
      error_messages: error_message
    )
  end

  def duration
    return nil unless completed_at

    completed_at - started_at
  end
end
