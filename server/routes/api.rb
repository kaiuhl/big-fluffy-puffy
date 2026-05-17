module ApiRoutes
  def route_api(r)
    r.on "api" do
      r.get "version" do
        json_response({app: "big-fluffy-puffy", env: BFP.env})
      end

      r.on "fire-restrictions" do
        r.get "land-units", String, "map" do |slug|
          map = land_unit_fire_restriction_map(slug)
          next json_response({error: "unknown land unit"}, status: 404) unless map

          geojson_response(map)
        end

        r.get "land-units", String do |slug|
          detail = land_unit_fire_restriction_detail(slug)
          next json_response({error: "unknown land unit"}, status: 404) unless detail

          json_response(detail)
        end

        r.get "land-units" do
          json_response({land_units: fire_restriction_records})
        end

        r.get "forests", String, "map" do |slug|
          map = forest_fire_restriction_map(slug)
          next json_response({error: "unknown forest"}, status: 404) unless map

          geojson_response(map)
        end

        r.get "forests", String do |slug|
          detail = forest_fire_restriction_detail(slug)
          next json_response({error: "unknown forest"}, status: 404) unless detail

          json_response(detail)
        end

        r.get "forests" do
          json_response({forests: fire_restriction_records})
        end

        r.get "map" do
          geojson_response(fire_restriction_map)
        end
      end

      r.on "places" do
        r.get "search" do
          limit = Integer(r.params.fetch("limit", 8))
          limit = limit.clamp(1, 20)
          json_response({places: place_search_suggestions(r.params["q"].to_s, limit: limit)})
        rescue ArgumentError
          json_response({places: place_search_suggestions(r.params["q"].to_s, limit: 8)})
        end
      end

      r.on "trip-check" do
        r.get String, "map" do |slug|
          map = trip_check_map(slug)
          next json_response({error: "unknown place"}, status: 404) unless map

          geojson_response(map)
        end

        r.get String do |slug|
          check = trip_check_detail(slug)
          next json_response({error: "unknown place"}, status: 404) unless check

          json_response(check)
        end
      end
    end
  end

  private

  def json_response(payload, status: 200)
    response.status = status
    response["Content-Type"] = "application/json"
    JSON.generate(payload)
  end

  def geojson_response(payload, status: 200)
    response.status = status
    response["Content-Type"] = "application/geo+json"
    JSON.generate(payload)
  end
end
