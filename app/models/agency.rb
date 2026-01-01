class Agency < ApplicationRecord
  has_many :regulations, dependent: :destroy

  validates :name, presence: true
  validates :acronym, presence: true

  scope :with_regulations, -> { joins(:regulations).distinct }
  scope :by_word_count, -> { order(total_word_count: :desc) }

  def calculate_word_count
    regulations.sum(:word_count)
  end

  def update_word_count!
    update!(total_word_count: calculate_word_count)
  end

  def calculate_restrictions_count
    regulations.sum(:restrictions_count)
  end

  def update_restrictions_count!
    update!(total_restrictions_count: calculate_restrictions_count)
  end

  def calculate_checksum
    # Calculate checksum from regulation metadata since content is no longer stored
    data = regulations.order(:id).pluck(:id, :word_count, :last_amended_on).map(&:to_s).join
    Digest::SHA256.hexdigest(data)
  end

  def update_checksum!
    update!(content_checksum: calculate_checksum)
  end

  def amendment_frequency(period = 1.year)
    regulations.where("last_amended_on > ?", period.ago).count
  end

  def total_regulations
    regulations.count
  end
end
