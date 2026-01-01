# Run with: bin/rails runner bin/clear_jobs.rb
Rails.logger.level = :warn
puts "Clearing all Solid Queue jobs..."
SolidQueue::Job.delete_all
SolidQueue::Process.delete_all
puts "Done. Queue is empty."
