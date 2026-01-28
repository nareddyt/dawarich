# frozen_string_literal: true

class Areas::Visits::Create
  attr_reader :user, :areas

  def initialize(user, areas)
    @user = user
    @areas = areas
    @time_threshold_minutes = 30 || user.safe_settings.time_threshold_minutes
    @merge_threshold_minutes = 15 || user.safe_settings.merge_threshold_minutes
  end

  def call
    areas.each { area_visits(_1) }
  end

  private

  def area_visits(area)
    area_points(area).each do |month, points|
      visits = Visits::Group.new(
        time_threshold_minutes: @time_threshold_minutes,
        merge_threshold_minutes: @merge_threshold_minutes
      ).call(points)

      Rails.logger.info("Month: #{month}, Total visits: #{visits.size}")

      visits.each do |time_range, visit_points|
        create_or_update_visit(area, time_range, visit_points)
      end
    end
  end

  def area_points(area)
    area_radius =
      if user.safe_settings.distance_unit == :km
        area.radius / ::DISTANCE_UNITS[:km]
      else
        area.radius / ::DISTANCE_UNITS[user.safe_settings.distance_unit.to_sym]
      end

    points = Point.where(user_id: user.id)
                  .near([area.latitude, area.longitude], area_radius, user.safe_settings.distance_unit)
                  .order(timestamp: :asc)

    # check if all points within the area are assigned to a visit

    points.group_by { |point| Time.zone.at(point.timestamp).strftime('%Y-%m') }
  end

  def create_or_update_visit(area, time_range, visit_points)
    Rails.logger.info("Visit from #{time_range}, Points: #{visit_points.size}")

    ActiveRecord::Base.transaction do
      visit = find_or_initialize_visit(area.id, visit_points.first.timestamp)

      visit.tap do |v|
        v.name = "#{area.name}, #{time_range}"
        v.ended_at = Time.zone.at(visit_points.last.timestamp)
        v.duration = (visit_points.last.timestamp - visit_points.first.timestamp) / 60
        v.status = :suggested
      end

      visit.save!

      visit_points.each { _1.update!(visit_id: visit.id) }
    end
  end

  def find_or_initialize_visit(area_id, timestamp)
    Visit.find_or_initialize_by(
      area_id:,
      user_id: user.id,
      started_at: Time.zone.at(timestamp)
    )
  end
end
