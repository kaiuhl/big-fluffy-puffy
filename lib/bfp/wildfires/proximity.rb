require "rgeo"
require_relative "../places/geometry"

module BFP
  module Wildfires
    # Request-time proximity classification between a query point (or forest
    # boundary) and the active wildfire set. Uses an AABB prefilter before any
    # real geometry work, then a local equirectangular meters projection
    # centered on the query so GEOS distances come back in meters.
    module Proximity
      module_function

      NEAR_MILES = 10
      REGIONAL_MILES = 30
      REGIONAL_MIN_ACRES = 100
      # Land-unit pages cover huge areas already; fires beyond this distance
      # from the boundary are regional noise there (trip-check points keep
      # the wider REGIONAL_MILES context).
      LAND_UNIT_NEARBY_MILES = 10
      METERS_PER_MILE = 1609.344
      EARTH_RADIUS_METERS = 6_378_137.0
      ACRE_SQUARE_METERS = 4046.86
      DEFAULT_POINT_RADIUS_METERS = 500.0

      TIER_SEVERITY = {inside: 3, near: 2, regional: 1}.freeze

      def factory
        BFP::Places::Geometry.factory
      end

      # Effective footprint in lon/lat degrees: the perimeter polygon when
      # mapped, otherwise the point buffered by a radius derived from acres.
      def effective_geometry(incident)
        perimeter = incident.perimeter_geometry
        geometry = BFP::Places::Geometry.geojson_geometry(perimeter) if perimeter
        return geometry if geometry

        buffered_point_geometry(incident)
      end

      def buffered_point_geometry(incident)
        longitude = incident.longitude&.to_f
        latitude = incident.latitude&.to_f
        return unless longitude && latitude

        origin = [longitude, latitude]
        x, y = project_coordinate(longitude, latitude, origin)
        buffered = factory.point(x, y).buffer(point_radius_meters(incident))
        reproject(buffered) { |mx, my| unproject_coordinate(mx, my, origin) }
      rescue RGeo::Error::InvalidGeometry
        nil
      end

      # Sorted [{incident:, tier:, distance_miles:}] for a query point.
      def classify(longitude:, latitude:, incidents:)
        distances(longitude: longitude, latitude: latitude, incidents: incidents).filter_map do |entry|
          tier = tier_for(entry[:distance_miles], entry[:incident])
          next unless tier

          entry.merge(tier: tier)
        end
      end

      # Sorted [{incident:, distance_miles:}] for every incident within
      # within_miles of the query point (no acres filter).
      def distances(longitude:, latitude:, incidents:, within_miles: REGIONAL_MILES)
        origin = [longitude, latitude]
        query_bounds = expanded_bounds(longitude, latitude, within_miles)
        origin_point = factory.point(0.0, 0.0)

        incidents.filter_map do |incident|
          next unless BFP::Places::Geometry.bounds_intersect?(query_bounds, incident_bounds(incident))

          geometry = effective_geometry(incident)
          next unless geometry

          projected = reproject(geometry) { |x, y| project_coordinate(x, y, origin) }
          distance_miles = projected.distance(origin_point) / METERS_PER_MILE
          next if distance_miles > within_miles

          {incident: incident, distance_miles: distance_miles}
        end.sort_by { |entry| entry[:distance_miles] }
      end

      # Classification against an arbitrary rgeo geometry (a forest boundary):
      # :inside when the incident footprint intersects the boundary, otherwise
      # the boundary-to-footprint distance.
      def for_geometry(geometry, incidents:, within_miles: REGIONAL_MILES)
        return [] unless geometry

        bounds = geometry_bounds(geometry)
        return [] unless bounds

        origin = [(bounds[0] + bounds[2]) / 2.0, (bounds[1] + bounds[3]) / 2.0]
        boundary_bounds = expanded_geometry_bounds(geometry, within_miles)
        return [] unless boundary_bounds
        projected_boundary = reproject(geometry) { |x, y| project_coordinate(x, y, origin) }

        incidents.filter_map do |incident|
          next unless BFP::Places::Geometry.bounds_intersect?(boundary_bounds, incident_bounds(incident))

          footprint = effective_geometry(incident)
          next unless footprint

          if BFP::Places::Geometry.intersects?(geometry, footprint)
            {incident: incident, tier: :inside, distance_miles: 0.0}
          else
            projected_footprint = reproject(footprint) { |x, y| project_coordinate(x, y, origin) }
            distance_miles = projected_boundary.distance(projected_footprint) / METERS_PER_MILE
            next if distance_miles > within_miles

            tier = tier_for(distance_miles, incident)
            {incident: incident, tier: tier, distance_miles: distance_miles} if tier
          end
        end.sort_by { |entry| entry[:distance_miles] }
      end

      def tier_for(distance_miles, incident)
        return :inside if distance_miles <= 0.0
        return :near if distance_miles <= NEAR_MILES
        return :regional if distance_miles <= REGIONAL_MILES && acres_of(incident) >= REGIONAL_MIN_ACRES

        nil
      end

      def acres_of(incident)
        incident.acres.to_f
      end

      def point_radius_meters(incident)
        acres = acres_of(incident)
        return DEFAULT_POINT_RADIUS_METERS if acres <= 0

        [Math.sqrt(acres * ACRE_SQUARE_METERS / Math::PI), DEFAULT_POINT_RADIUS_METERS].max
      end

      def incident_bounds(incident)
        [incident.min_lon, incident.min_lat, incident.max_lon, incident.max_lat]
      end

      def expanded_bounds(longitude, latitude, miles)
        meters = miles * METERS_PER_MILE
        origin = [longitude, latitude]
        min = unproject_coordinate(-meters, -meters, origin)
        max = unproject_coordinate(meters, meters, origin)
        [min[0], min[1], max[0], max[1]]
      end

      # Expand the geometry's own bounding box, not a box around its centroid:
      # a large land unit can have fires within range of its edge that sit well
      # beyond REGIONAL_MILES of its centroid.
      def expanded_geometry_bounds(geometry, miles)
        bounds = geometry_bounds(geometry)
        return unless bounds

        min_lon, min_lat, max_lon, max_lat = bounds
        meters = miles * METERS_PER_MILE
        mid_lat = (min_lat + max_lat) / 2.0
        delta_lon = meters / (EARTH_RADIUS_METERS * Math.cos(mid_lat * Math::PI / 180.0)) * 180.0 / Math::PI
        delta_lat = meters / EARTH_RADIUS_METERS * 180.0 / Math::PI
        [min_lon - delta_lon.abs, min_lat - delta_lat, max_lon + delta_lon.abs, max_lat + delta_lat]
      end

      def geometry_bounds(geometry)
        envelope = geometry.envelope
        points = envelope.respond_to?(:exterior_ring) ? envelope.exterior_ring.points : [envelope]
        return if points.empty?

        xs = points.map { |point| point.x.to_f }
        ys = points.map { |point| point.y.to_f }
        [xs.min, ys.min, xs.max, ys.max]
      rescue RGeo::Error::InvalidGeometry, NoMethodError
        nil
      end

      # Equirectangular projection helpers hoisted from
      # scripts/fire_restrictions/generate_point_buffer_geometries.rb so nothing
      # loads that CLI script at runtime.
      def project_coordinate(lon, lat, origin)
        origin_lon, origin_lat = origin
        origin_lat_radians = origin_lat * Math::PI / 180.0

        [
          (lon - origin_lon) * Math::PI / 180.0 * EARTH_RADIUS_METERS * Math.cos(origin_lat_radians),
          (lat - origin_lat) * Math::PI / 180.0 * EARTH_RADIUS_METERS
        ]
      end

      def unproject_coordinate(x, y, origin)
        origin_lon, origin_lat = origin
        origin_lat_radians = origin_lat * Math::PI / 180.0

        [
          origin_lon + (x / (EARTH_RADIUS_METERS * Math.cos(origin_lat_radians)) * 180.0 / Math::PI),
          origin_lat + (y / EARTH_RADIUS_METERS * 180.0 / Math::PI)
        ]
      end

      def reproject(geometry, &block)
        case geometry.geometry_type.type_name
        when "Point"
          x, y = block.call(geometry.x, geometry.y)
          factory.point(x, y)
        when "LineString", "LinearRing"
          factory.line_string(reproject_points(geometry.points, &block))
        when "MultiLineString"
          factory.multi_line_string(geometry.map { |line| factory.line_string(reproject_points(line.points, &block)) })
        when "Polygon"
          reproject_polygon(geometry, &block)
        when "MultiPolygon"
          factory.multi_polygon(geometry.map { |polygon| reproject_polygon(polygon, &block) })
        when "GeometryCollection"
          factory.collection(geometry.map { |part| reproject(part, &block) })
        else
          geometry
        end
      end

      def reproject_polygon(polygon, &block)
        exterior = factory.linear_ring(reproject_points(polygon.exterior_ring.points, &block))
        holes = polygon.interior_rings.map { |ring| factory.linear_ring(reproject_points(ring.points, &block)) }
        factory.polygon(exterior, holes)
      end

      def reproject_points(points, &block)
        points.map do |point|
          x, y = block.call(point.x, point.y)
          factory.point(x, y)
        end
      end
    end
  end
end
