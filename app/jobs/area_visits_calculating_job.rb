# frozen_string_literal: true

class AreaVisitsCalculatingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(user_id)
    Rails.logger.info("[AreaVisitsCalculatingJob] started user_id=#{user_id}")
    user = User.find(user_id)
    areas = user.areas

    Areas::Visits::Create.new(user, areas).call
    Rails.logger.info("[AreaVisitsCalculatingJob] done user_id=#{user_id} areas=#{areas.size}")
  end
end
