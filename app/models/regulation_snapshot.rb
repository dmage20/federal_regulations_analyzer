class RegulationSnapshot < ApplicationRecord
  belongs_to :regulation
  has_one_attached :xml_content

  validates :word_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :checksum, presence: true
  validates :snapshot_date, presence: true
  validates :regulation_id, uniqueness: { scope: :snapshot_date }

  scope :recent, -> { order(snapshot_date: :desc) }
  scope :for_date, ->(date) { where(snapshot_date: date) }
  scope :between_dates, ->(start_date, end_date) { where(snapshot_date: start_date..end_date) }

  # Find the most recent snapshot before or on a given date
  def self.at_date(date)
    where("snapshot_date <= ?", date).order(snapshot_date: :desc).first
  end

  # Check if this snapshot represents a change from the previous one
  def changed_from_previous?
    previous = regulation.snapshots
      .where("snapshot_date < ?", snapshot_date)
      .order(snapshot_date: :desc)
      .first

    return true if previous.nil? # First snapshot is always a "change"
    previous.checksum != checksum
  end

  # Calculate word count delta from previous snapshot
  def word_count_delta
    previous = regulation.snapshots
      .where("snapshot_date < ?", snapshot_date)
      .order(snapshot_date: :desc)
      .first

    return word_count if previous.nil?
    word_count - previous.word_count
  end
end
