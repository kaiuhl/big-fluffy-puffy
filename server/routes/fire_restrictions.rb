module FireRestrictionsRoutes
  def route_fire_restrictions(r)
    r.on "fire-restrictions" do
      r.get "changes" do
        html_response(render_view("fire_restrictions/changes", day_groups: fire_restriction_change_log))
      end

      r.get String do |slug|
        detail = land_unit_fire_restriction_detail(slug)
        next html_response(render_view("errors/not_found", title: "Area Not Found", message: "BFP does not track that active forest or park."), status: 404) unless detail

        html_response(render_view("fire_restrictions/show", detail: detail))
      end

      r.get do
        html_response(render_view("fire_restrictions/index", records: fire_restriction_records))
      end
    end
  end

  private

  def html_response(body, status: 200)
    response.status = status
    response["Content-Type"] = "text/html"
    body
  end
end
