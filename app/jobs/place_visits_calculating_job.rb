# frozen_string_literal: true

class PlaceVisitsCalculatingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(user_id)
    Rails.logger.warn("[PlaceVisitsCalculatingJob] started user_id=#{user_id}")
    user = User.find(user_id)
    places = user.places # Only user-owned places (with user_id)

    Places::Visits::Create.new(user, places).call
    Rails.logger.warn("[PlaceVisitsCalculatingJob] done user_id=#{user_id} places=#{places.size}")
  end
end
