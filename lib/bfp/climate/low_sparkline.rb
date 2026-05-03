require "rack/utils"

module BFP
  module Climate
    class LowSparkline
      WIDTH = 154.0
      HEIGHT = 48.0
      PAD = {
        left: 8.0,
        right: 8.0,
        top: 12.0,
        bottom: 14.0
      }.freeze
      TEMP_STOPS = [
        [20.0, [47, 127, 163]],
        [34.0, [95, 159, 114]],
        [47.0, [200, 135, 46]],
        [60.0, [255, 75, 31]]
      ].freeze

      def self.render(context)
        new(context).render
      end

      def initialize(context)
        @context = context || {}
        @bands = Array(@context[:bands])
        @month_name = @context[:month_name].to_s
      end

      def render
        return "" if @bands.empty?

        points = sparkline_points
        guide_top = PAD.fetch(:top) - 1
        guide_bottom = HEIGHT - PAD.fetch(:bottom) + 1

        <<~HTML
          <svg
            class="climate-low-sparkline"
            viewBox="0 0 #{svg_number(WIDTH)} #{svg_number(HEIGHT)}"
            role="img"
            aria-label="#{h(aria_label)}">
            #{guides(points, guide_top, guide_bottom)}
            #{path_markup(points)}
            #{dot_markup(points)}
          </svg>
        HTML
      end

      private

      def sparkline_points
        values = @bands.map { |band| band[:mean_low_f].to_f }
        y_min = values.min
        y_max = values.max
        y_center = (y_min + y_max) / 2.0

        if (y_max - y_min) < 10.0
          y_min = y_center - 5.0
          y_max = y_center + 5.0
        else
          y_min -= 1.2
          y_max += 1.2
        end

        usable_width = WIDTH - PAD.fetch(:left) - PAD.fetch(:right)
        usable_height = HEIGHT - PAD.fetch(:top) - PAD.fetch(:bottom)
        x_step = (@bands.length > 1) ? usable_width / (@bands.length - 1) : 0

        @bands.each_with_index.map do |band, index|
          mean_low_f = band[:mean_low_f].to_f

          {
            band: band,
            mean_low_f: mean_low_f,
            x: PAD.fetch(:left) + (x_step * index),
            y: PAD.fetch(:top) + (((y_max - mean_low_f) / (y_max - y_min)) * usable_height)
          }
        end
      end

      def guides(points, guide_top, guide_bottom)
        points.map do |point|
          <<~HTML.chomp
            <line class="climate-low-guide" x1="#{svg_number(point.fetch(:x))}" y1="#{svg_number(guide_top)}" x2="#{svg_number(point.fetch(:x))}" y2="#{svg_number(guide_bottom)}"></line>
          HTML
        end.join
      end

      def path_markup(points)
        return "" if points.length < 2

        path = smooth_svg_path(points)

        <<~HTML
          <path class="climate-low-path-shadow" d="#{h(path)}"></path>
          <path class="climate-low-path" d="#{h(path)}"></path>
        HTML
      end

      def dot_markup(points)
        points.map do |point|
          band = point.fetch(:band)
          mean_low_f = point.fetch(:mean_low_f)
          x = point.fetch(:x)
          y = point.fetch(:y)

          <<~HTML
            <text class="climate-low-temp" x="#{svg_number(x)}" y="#{svg_number([8.0, y - 6.0].max)}">#{mean_low_f.round}&#176;</text>
            <circle class="climate-low-dot" cx="#{svg_number(x)}" cy="#{svg_number(y)}" r="3.4" fill="#{temperature_color(mean_low_f)}"></circle>
            <text class="climate-low-elevation" x="#{svg_number(x)}" y="#{svg_number(HEIGHT - 3)}">#{h(elevation_midpoint_label(band))}</text>
          HTML
        end.join
      end

      def smooth_svg_path(points)
        return svg_move_to(points.first) if points.length == 1
        return "#{svg_move_to(points.first)} L #{svg_point(points.last)}" if points.length == 2

        path = svg_move_to(points.first)

        points.each_cons(2).with_index do |(point, next_point), index|
          previous_point = points[[index - 1, 0].max]
          following_point = points[[index + 2, points.length - 1].min]
          c1x = point.fetch(:x) + ((next_point.fetch(:x) - previous_point.fetch(:x)) / 6.0)
          c1y = point.fetch(:y) + ((next_point.fetch(:y) - previous_point.fetch(:y)) / 6.0)
          c2x = next_point.fetch(:x) - ((following_point.fetch(:x) - point.fetch(:x)) / 6.0)
          c2y = next_point.fetch(:y) - ((following_point.fetch(:y) - point.fetch(:y)) / 6.0)

          path += " C #{svg_number(c1x)} #{svg_number(c1y)}, #{svg_number(c2x)} #{svg_number(c2y)}, #{svg_point(next_point)}"
        end

        path
      end

      def svg_move_to(point)
        "M #{svg_point(point)}"
      end

      def svg_point(point)
        "#{svg_number(point.fetch(:x))} #{svg_number(point.fetch(:y))}"
      end

      def svg_number(value)
        format("%.1f", value).sub(/\.0\z/, "")
      end

      def elevation_midpoint_label(band)
        max = band[:elevation_max_ft]
        midpoint = if max
          (band[:elevation_min_ft].to_f + max.to_f) / 2.0
        else
          band[:elevation_min_ft].to_f + 1000.0
        end

        "#{(midpoint / 1000.0).round}K"
      end

      def temperature_color(value)
        value = value.to_f
        return rgb_hex(TEMP_STOPS.first.fetch(1)) if value <= TEMP_STOPS.first.fetch(0)
        return rgb_hex(TEMP_STOPS.last.fetch(1)) if value >= TEMP_STOPS.last.fetch(0)

        upper_index = TEMP_STOPS.index { |stop| value <= stop.fetch(0) }
        lower_value, lower_color = TEMP_STOPS.fetch(upper_index - 1)
        upper_value, upper_color = TEMP_STOPS.fetch(upper_index)
        amount = (value - lower_value) / (upper_value - lower_value)

        rgb_hex(
          lower_color.each_with_index.map do |channel, index|
            (channel + ((upper_color.fetch(index) - channel) * amount)).round
          end
        )
      end

      def rgb_hex(channels)
        "#%02x%02x%02x" % channels
      end

      def aria_label
        band_labels = @bands.map do |band|
          "#{elevation_midpoint_label(band)} #{temperature_label(band[:mean_low_f])}"
        end.join(", ")

        "Average #{@month_name} overnight lows by elevation: #{band_labels}"
      end

      def temperature_label(value)
        "#{value.to_f.round} degrees Fahrenheit"
      end

      def h(value)
        Rack::Utils.escape_html(value.to_s)
      end
    end
  end
end
