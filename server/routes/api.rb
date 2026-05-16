module ApiRoutes
  def route_api(r)
    r.on "api" do
      r.get "version" do
        json_response({app: "big-fluffy-puffy", env: BFP.env})
      end

      r.on "fire-restrictions" do
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
