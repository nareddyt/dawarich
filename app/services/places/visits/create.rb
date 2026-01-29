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
    # Don't return unnecessary values, causes high memory usage (see #2119)
    places.each { place_visits(_1) }
  end

  private

  def place_visits(place)
    # Process month-by-month sequentially to avoid loading all points into memory.
    # Loading all points and grouping in Ruby caused 16GB+ memory usage (see #2119).
    # Query distinct months first (no point data), then process each month separately.
    # Process visits immediately per month - DO NOT build a hash of all visits for all months
    # before processing (removing that intermediate hash was a key optimization).
    months = distinct_months_for_place(place)

    months.each do |month|
      points = place_points_for_month(place, month)
      next if points.empty?

      visits = Visits::Group.new(
        time_threshold_minutes: @time_threshold_minutes,
        merge_threshold_minutes: @merge_threshold_minutes
      ).call(points, already_sorted: true)

      Rails.logger.info("Month: #{month}, Total visits: #{visits.size}")

      visits.each do |time_range, visit_points|
        create_or_update_visit(place, time_range, visit_points)
      end
    end
  end

  def distinct_months_for_place(place)
    place_radius =
      if user.safe_settings.distance_unit == :km
        DEFAULT_PLACE_RADIUS / ::DISTANCE_UNITS[:km]
      else
        DEFAULT_PLACE_RADIUS / ::DISTANCE_UNITS[user.safe_settings.distance_unit.to_sym]
      end

    Point.where(user_id: user.id)
         .near([place.latitude, place.longitude], place_radius, user.safe_settings.distance_unit)
         .select("DISTINCT TO_CHAR(TO_TIMESTAMP(timestamp), 'YYYY-MM') AS month")
         .order('month ASC')
         .pluck('month')
  end

  def place_points_for_month(place, month)
    place_radius =
      if user.safe_settings.distance_unit == :km
        DEFAULT_PLACE_RADIUS / ::DISTANCE_UNITS[:km]
      else
        DEFAULT_PLACE_RADIUS / ::DISTANCE_UNITS[user.safe_settings.distance_unit.to_sym]
      end

    year, month_num = month.split('-').map(&:to_i)
    month_start = Time.utc(year, month_num, 1).to_i
    month_end = (Time.utc(year, month_num, 1) + 1.month).to_i - 1

    Point.where(user_id: user.id)
         # Drop raw_data JSON to keep memory usage reasonable (see #2119)
         .without_raw_data
         .near([place.latitude, place.longitude], place_radius, user.safe_settings.distance_unit)
         .where(timestamp: month_start..month_end)
         .order(timestamp: :asc)
         .to_a
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
