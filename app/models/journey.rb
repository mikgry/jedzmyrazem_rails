# Model for manage journeys
class Journey < ActiveRecord::Base
  belongs_to :driver, class_name: 'User', foreign_key: :driver_id
  has_many :waypoints

  def self.create_with_path(journey_with_path, user)
    Journey.transaction do
      journey = Journey.create!(date: journey_with_path[:date],
                                spaces: journey_with_path[:spaces],
                                driver: user)
      Waypoint.create_from_array(journey_with_path[:path], journey)
      journey
    end
  end

  def format
    result = as_json
    result['waypoints'] = []
    waypoints.each do |waypoint|
      result['waypoints'].push("point":
        { "lat": waypoint.point.x, "lng": waypoint.point.y },
                               "time": waypoint.time)
    end
    result['user'] = driver.username
    result
  end

  def self.get_formated_journays(parameters)
    result = []
    Journey.includes(:waypoints).where(date: parameters[:date])
      .where('ST_Distance(waypoints.point, '\
        "'POINT(#{parameters[:start_lat]} "\
          "#{parameters[:start_lng]})') < 5000")
      .where('waypoints.time > ?', parameters[:start_time])
      .references(:waypoints).each do |j|
        result.push j.format
      end
    result
  end

  def self.search_journeys(parameters)
    candidates = Journey.get_journeys_in_period(parameters[:start_time],
                                                parameters[:date])
    sorted_js = Journey.sort_journeys(candidates, parameters)
    Journey.get_matched_journeys_from_sorted_journeys(sorted_js)
  end

  def self.get_journeys_in_period(start_time, date)
    Journey.includes(:waypoints).where(date: date)
      .where('waypoints.time BETWEEN ? AND ?', start_time,
             (Time.zone.parse(start_time) + 2.hour).to_formatted_s(:db))
      .references(:waypoints)
  end

  def find_start_and_finish(parameters)
    start = find_point(parameters[:start_lat], parameters[:start_lng])
    finish = find_point(parameters[:finish_lat], parameters[:finish_lng])
    [start, finish]
  end

  def find_point(lat, lng)
    waypoints.find_by('ST_Distance(point, '\
        "'POINT(#{lat} "\
          "#{lng})') < 800")
  end

  def self.sort_journeys(journeys, parameters)
    sorted_js = { direct: [], with_start: [], with_finish: [], rest: [] }
    journeys.each_with_index do |journey|
      start, finish = journey.find_start_and_finish(parameters)
      sorted_js[journey.choose_category(start, finish)].push journey
    end
    sorted_js
  end

  def choose_category(start, finish)
    if !start.nil? && !finish.nil? && start.id < finish.id
      return :direct
    elsif !start.nil?
      return :with_start
    elsif !finish.nil?
      return :with_finish
    else
      return :rest
    end
  end

  def self.get_matched_journeys_from_sorted_journeys(sorted_js)
    results = []
    sorted_js[:direct].each do |j|
      results.push passes: [j.format], intersections: []
    end
    sorted_js[:with_start].each do |j|
      matched_js = j.match_with_journays_from_array(sorted_js[:with_finish])
      results.concat matched_js
    end
    results
  end

  def match_with_journays_from_array(journeys)
    results = []
    journeys.each do |j|
      p1, p2 = find_intersection_point(j)
      if !p1.nil? && !p2.nil?
        results.push passes: [format, j.format], intersections: [p1, p2]
      end
    end
    results
  end

  def find_intersection_point(journay)
    journay.waypoints[0..-2].each do |point|
      waypoints.each do |self_point|
        if point.point.distance(self_point.point) < 800 &&
           point.time > self_point.time
          return self_point, point
        end
      end
    end
    [nil, nil]
  end
end
