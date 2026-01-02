class Regulation < ApplicationRecord
  belongs_to :agency, counter_cache: true
  has_many :snapshots, class_name: "RegulationSnapshot", dependent: :destroy

  validates :cfr_title, presence: true
  validates :word_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :cfr_title, uniqueness: { scope: [ :agency, :part, :section ] }

  scope :by_title, ->(title) { where(cfr_title: title) }
  scope :recently_amended, -> { order(last_amended_on: :desc) }
  scope :by_word_count, -> { order(word_count: :desc) }

  def citation
    parts = [ cfr_title, "CFR" ]
    parts << part if part.present?
    parts << section if section.present?
    parts.join(" ")
  end

  def label
    metadata&.dig("label") || citation
  end

  def identifier
    "#{cfr_title} CFR #{part}"
  end

  # Calculate checksum from regulation metadata (not content)
  def calculate_checksum
    data = "#{cfr_title}:#{part}:#{section}:#{word_count}:#{last_amended_on}"
    Digest::SHA256.hexdigest(data)
  end

  # Get the most recent snapshot
  def current_snapshot
    snapshots.order(snapshot_date: :desc).first
  end

  # Get change count from snapshots where checksum changed
  def change_count
    return 0 if snapshots.count <= 1

    snapshots.order(:snapshot_date).each_cons(2).count do |prev, curr|
      prev.checksum != curr.checksum
    end
  end

  # Get last change date from snapshots
  def last_changed_at
    snapshots.order(:snapshot_date).each_cons(2).find do |prev, curr|
      prev.checksum != curr.checksum
    end&.last&.snapshot_date
  end
end
