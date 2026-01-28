# frozen_string_literal: true

class Places::Visits::Create
  attr_reader :user, :places

  # Default radius for place visit detection (in meters)
  DEFAULT_PLACE_RADIUS = 100

  def initialize(user, places)
    @user = user
    @places = places
    @time_threshold_minutes = 30 || user.safe_settings.time_threshold_minutes
    @merge_threshold_minutes = 15 || user.safe_settings.merge_threshold_minutes
  end

  def call
    places.each { place_visits(_1) }
  end

  private

  def place_visits(place)
    place_points(place).each do |month, points|
      visits = Visits::Group.new(
        time_threshold_minutes: @time_threshold_minutes,
        merge_threshold_minutes: @merge_threshold_minutes
      ).call(points)

      Rails.logger.info("Month: #{month}, Total visits: #{visits.size}")

      visits.each do |time_range, visit_points|
        create_or_update_visit(place, time_range, visit_points)
      end
    end
  end

  def place_points(place)
    place_radius =
      if user.safe_settings.distance_unit == :km
        DEFAULT_PLACE_RADIUS / ::DISTANCE_UNITS[:km]
      else
        DEFAULT_PLACE_RADIUS / ::DISTANCE_UNITS[user.safe_settings.distance_unit.to_sym]
      end

    points = Point.where(user_id: user.id)
                  .near([place.latitude, place.longitude], place_radius, user.safe_settings.distance_unit)
                  .order(timestamp: :asc)

    points.group_by { |point| Time.zone.at(point.timestamp).strftime('%Y-%m') }
  end

  def create_or_update_visit(place, time_range, visit_points)
    Rails.logger.info("Visit from #{time_range}, Points: #{visit_points.size}")

    ActiveRecord::Base.transaction do
      visit = find_or_initialize_visit(place.id, visit_points.first.timestamp)

      visit.tap do |v|
        v.name = "#{place.name}, #{time_range}"
        v.ended_at = Time.zone.at(visit_points.last.timestamp)
        v.duration = (visit_points.last.timestamp - visit_points.first.timestamp) / 60
        v.status = :suggested
      end

      visit.save!

      visit_points.each { _1.update!(visit_id: visit.id) }
    end
  end

  def find_or_initialize_visit(place_id, timestamp)
    Visit.find_or_initialize_by(
      place_id:,
      user_id: user.id,
      started_at: Time.zone.at(timestamp)
    )
  end
end
