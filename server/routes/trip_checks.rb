module TripCheckRoutes
  def route_trip_checks(r)
    r.on "trip-check" do
      r.get String do |slug|
        check = trip_check_detail(slug)
        next html_response(render_view("errors/not_found", title: "Trip Check Not Found", message: "BFP does not have that destination in the place index yet."), status: 404) unless check

        html_response(render_view("trip_checks/show", check: check))
      end

      r.get do
        query = r.params["q"].to_s.strip
        results = trip_check_search_results(query, limit: 8)

        if results.length == 1
          r.redirect results.first.fetch(:url)
        end

        html_response(render_view("trip_checks/search", query: query, results: results))
      end
    end
  end
end
