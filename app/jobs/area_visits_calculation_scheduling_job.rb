# frozen_string_literal: true

class AreaVisitsCalculationSchedulingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform
    user_count = 0
    Rails.logger.warn("[AreaVisitsCalculationSchedulingJob] started")
    User.find_each do |user|
      AreaVisitsCalculatingJob.perform_later(user.id)
      PlaceVisitsCalculatingJob.perform_later(user.id)
      user_count += 1
    end
    Rails.logger.warn("[AreaVisitsCalculationSchedulingJob] finished enqueued #{user_count} users (2 jobs each)")
  end
end
