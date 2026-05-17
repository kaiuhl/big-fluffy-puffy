module BFP
  module Places
    module Normalizer
      module_function

      TOKEN_REPLACEMENTS = {
        "mt" => "mount",
        "mtn" => "mountain",
        "nf" => "national forest",
        "natl" => "national",
        "cg" => "campground",
        "th" => "trailhead",
        "trl" => "trail",
        "lk" => "lake",
        "rvr" => "river"
      }.freeze

      def normalize(value)
        value.to_s
          .downcase
          .gsub("&", " and ")
          .gsub(/['`]/, "")
          .gsub(/[^a-z0-9]+/, " ")
          .split
          .flat_map { |token| TOKEN_REPLACEMENTS.fetch(token, token).split }
          .join(" ")
          .strip
      end

      def slugify(value)
        normalize(value)
          .gsub(/\b(national forest|forest|wilderness|campground|trailhead)\b/, "")
          .split
          .join("-")
          .gsub(/\A-+|-+\z/, "")
      end
    end
  end
end
