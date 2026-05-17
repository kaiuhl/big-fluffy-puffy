require "csv"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"
require "yaml"
require "zip"

module BFP
  module Places
    class Importer
      CONFIG_PATH = File.join(BFP.root, "config/place_datasets.yml")
      CACHE_DIR = File.join(BFP.root, "tmp/place_imports")
      LAUNCH_BOUNDS = {
        min_lat: 37.0,
        max_lat: 49.1,
        min_lon: -125.1,
        max_lon: -116.0
      }.freeze
      STATE_CODES = {
        "california" => "ca",
        "oregon" => "or",
        "washington" => "wa"
      }.freeze
      CACHE_EXTENSIONS = {
        "csv" => ".csv",
        "geojson" => ".geojson",
        "json" => ".json",
        "tsv" => ".tsv",
        "txt" => ".txt",
        "zip" => ".zip"
      }.freeze

      def initialize(path: CONFIG_PATH, cache_dir: CACHE_DIR)
        @path = path
        @cache_dir = cache_dir
      end

      def import(dataset_slugs: nil)
        config = YAML.load_file(@path)
        counts = {datasets: 0, places: 0, names: 0}
        selected_slugs = Array(dataset_slugs).compact.map(&:to_s)

        BFP.db.transaction do
          Array(config.fetch("datasets")).each do |dataset_config|
            next unless selected_slugs.empty? || selected_slugs.include?(dataset_config.fetch("slug"))

            dataset = upsert_dataset(dataset_config)
            counts[:datasets] += 1
            next unless dataset_config.fetch("enabled", false)

            records_for(dataset_config).each do |record|
              next unless in_launch_bounds?(record)

              place = upsert_place(dataset, dataset_config, record)
              counts[:places] += 1
              counts[:names] += upsert_names(place, names_for(record)).length
            end
          end
        end

        counts
      end

      private

      def upsert_dataset(config)
        now = Time.now
        dataset = PlaceDataset.first(slug: config.fetch("slug")) || PlaceDataset.new(slug: config.fetch("slug"), created_at: now)
        dataset.set(
          name: config.fetch("name"),
          source_url: config["source_url"],
          license_name: config.fetch("license_name"),
          license_url: config["license_url"],
          attribution_text: config["attribution_text"],
          retrieved_at: parse_time(config["retrieved_at"]),
          metadata_json: Jsonb.wrap(config["metadata_json"] || {}),
          updated_at: now
        )
        dataset.save
        dataset
      end

      def records_for(config)
        source_paths(config).flat_map do |source_path|
          next [] unless File.file?(source_path)

          records_from_path(source_path, config)
        end
      end

      def records_from_path(source_path, config)
        case format_for(source_path, config)
        when "zip"
          zip_records(source_path, config)
        when "geojson", "json"
          geojson_records(source_path, config)
        when "csv"
          delimited_records(source_path, config, col_sep: ",")
        when "tsv", "txt"
          delimited_records(source_path, config, col_sep: col_sep_for(config))
        else
          []
        end
      end

      def source_paths(config)
        configured_paths = Array(config["paths"]) + Array(config["path"]).reject { |path| path.to_s.empty? }
        local_paths = configured_paths.map { |path| File.expand_path(path, BFP.root) }
        data_urls = Array(config["data_urls"]) + Array(config["data_url"]).reject { |url| url.to_s.empty? }

        local_paths + data_urls.map { |data_url| download_source(config, data_url) }
      end

      def download_source(config, data_url)
        FileUtils.mkdir_p(@cache_dir)
        uri = URI.parse(data_url)
        url_path = uri.path
        basename = File.basename(url_path)
        basename = cache_basename(config, data_url, basename) if basename.empty? || uri.query.to_s != "" || File.extname(basename).empty?
        target = File.join(@cache_dir, basename)
        return target if File.file?(target)

        response = Net::HTTP.get_response(URI(data_url))
        raise "Place import failed for #{data_url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        File.binwrite(target, response.body)
        target
      end

      def cache_basename(config, data_url, basename)
        extension = CACHE_EXTENSIONS[config["format"].to_s] || File.extname(URI.parse(data_url).path)
        extension = ".dat" if extension.to_s.empty?
        slug = config.fetch("slug")
        digest = Digest::SHA1.hexdigest(data_url)[0, 12]
        stem = File.extname(basename).empty? ? slug : File.basename(basename, File.extname(basename))

        "#{stem}-#{digest}#{extension}"
      end

      def zip_records(path, config)
        Zip::File.open(path) do |zip_file|
          zip_file.glob(config.fetch("zip_glob", "*")).flat_map do |entry|
            next [] if entry.directory?

            content = entry.get_input_stream.read.force_encoding(Encoding::UTF_8)
            case format_for(entry.name, config, inside_zip: true)
            when "csv"
              delimited_records_from_string(content, config, col_sep: ",")
            when "tsv", "txt"
              delimited_records_from_string(content, config, col_sep: col_sep_for(config))
            when "geojson", "json"
              geojson_records_from_string(content, config)
            else
              []
            end
          end
        end
      end

      def geojson_records(path, config)
        geojson_records_from_string(File.read(path), config)
      end

      def geojson_records_from_string(content, config)
        payload = JSON.parse(content)
        raise "Place import failed for #{config.fetch("slug")}: GeoJSON source exceeded transfer limit." if geojson_exceeded_transfer_limit?(payload)

        features = payload.fetch("features", [])
        mapping = config.fetch("mapping", {})
        features.filter_map do |feature|
          properties = feature.fetch("properties", {})
          record_from_properties(properties, mapping).merge(
            "geometry_json" => feature["geometry"],
            "latitude" => point_latitude(feature["geometry"], properties, mapping),
            "longitude" => point_longitude(feature["geometry"], properties, mapping)
          )
        end
      end

      def geojson_exceeded_transfer_limit?(payload)
        payload["exceededTransferLimit"] || payload.dig("properties", "exceededTransferLimit")
      end

      def delimited_records(path, config, col_sep:)
        delimited_records_from_string(File.read(path, mode: "r:bom|utf-8"), config, col_sep: col_sep)
      end

      def delimited_records_from_string(content, config, col_sep:)
        mapping = config.fetch("mapping", {})
        CSV.parse(content, headers: true, col_sep: col_sep).filter_map do |row|
          record = record_from_properties(normalized_properties(row.to_h), mapping)
          record_allowed?(record, config) ? record : nil
        end
      end

      def record_from_properties(properties, mapping)
        place_type = value_at(properties, mapping["place_type"]) || mapping["default_place_type"] || "place"
        state_code = value_at(properties, mapping["state_code"])
        state_code = STATE_CODES[value_at(properties, mapping["state_name"]).to_s.downcase] if state_code.to_s.empty?

        {
          "external_id" => value_at(properties, mapping["external_id"]),
          "name" => value_at(properties, mapping.fetch("name")),
          "place_type" => mapped_place_type(place_type, mapping),
          "source_place_type" => place_type,
          "latitude" => numeric(value_at(properties, mapping["latitude"])),
          "longitude" => numeric(value_at(properties, mapping["longitude"])),
          "state_code" => state_code.to_s.downcase,
          "source_url" => value_at(properties, mapping["source_url"]),
          "aliases" => split_aliases(value_at(properties, mapping["aliases"])),
          "search_rank" => search_rank_for(place_type, mapping),
          "confidence" => Float(mapping.fetch("confidence", 0.7)),
          "metadata_json" => metadata_for(properties, mapping)
        }
      end

      def upsert_place(dataset, config, record)
        now = Time.now
        slug = place_slug(dataset, record)
        place = Place.first(slug: slug) || Place.new(slug: slug, created_at: now)
        place.set(
          name: record.fetch("name").to_s.strip,
          place_type: normalized_place_type(record["place_type"]),
          latitude: record["latitude"],
          longitude: record["longitude"],
          geometry_json: Jsonb.wrap(record["geometry_json"]),
          metadata_json: Jsonb.wrap(record["metadata_json"] || {}),
          state_code: record["state_code"].to_s.downcase,
          source_dataset_id: dataset.id,
          source_external_id: record["external_id"],
          source_url: record["source_url"] || config["source_url"],
          confidence: record["confidence"].to_f,
          search_rank: record["search_rank"].to_i,
          active: true,
          updated_at: now
        )
        place.save
        place
      end

      def upsert_names(place, names)
        names.uniq.filter_map do |name|
          normalized = Normalizer.normalize(name)
          next if normalized.empty?

          record = PlaceName.first(place_id: place.id, normalized_name: normalized) ||
            PlaceName.new(place_id: place.id, normalized_name: normalized, created_at: Time.now)
          record.set(name: name, kind: (name == place.name) ? "official" : "alias", weight: (name == place.name) ? 100 : 70, updated_at: Time.now)
          record.save
        end
      end

      def names_for(record)
        [record.fetch("name"), *Array(record["aliases"])].compact.map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def in_launch_bounds?(record)
        lat = record["latitude"].to_f
        lon = record["longitude"].to_f
        return true if lat.zero? && lon.zero? && record["geometry_json"]

        lat.between?(LAUNCH_BOUNDS.fetch(:min_lat), LAUNCH_BOUNDS.fetch(:max_lat)) &&
          lon.between?(LAUNCH_BOUNDS.fetch(:min_lon), LAUNCH_BOUNDS.fetch(:max_lon))
      end

      def place_slug(dataset, record)
        base = Normalizer.slugify(record.fetch("name"))
        suffix = record["external_id"].to_s.strip
        suffix = Digest::SHA1.hexdigest("#{dataset.slug}:#{record.fetch("name")}:#{record["latitude"]}:#{record["longitude"]}")[0, 8] if suffix.empty?

        "#{dataset.slug}-#{base}-#{Normalizer.slugify(suffix)}".squeeze("-")
      end

      def normalized_place_type(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      end

      def value_at(properties, key)
        Array(key).each do |candidate|
          next if candidate.to_s.empty?

          value = properties[candidate] || properties[candidate.to_s] || properties[candidate.to_sym]
          return value unless value.to_s.empty?
        end

        nil
      end

      def split_aliases(value)
        value.to_s.split(/[|;]/).map(&:strip).reject(&:empty?)
      end

      def numeric(value)
        return if value.to_s.strip.empty?

        Float(value)
      rescue ArgumentError
        nil
      end

      def parse_time(value)
        return if value.to_s.empty?

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def point_latitude(geometry, properties, mapping)
        numeric(value_at(properties, mapping["latitude"])) || ((geometry["type"] == "Point") ? geometry["coordinates"][1].to_f : nil)
      end

      def point_longitude(geometry, properties, mapping)
        numeric(value_at(properties, mapping["longitude"])) || ((geometry["type"] == "Point") ? geometry["coordinates"][0].to_f : nil)
      end

      def format_for(path, config, inside_zip: false)
        return "zip" if File.extname(path).downcase == ".zip" && !inside_zip

        configured_format = config["format"].to_s
        return configured_format if configured_format != "" && !(inside_zip && configured_format == "zip")

        File.extname(path).downcase.delete_prefix(".")
      end

      def col_sep_for(config)
        separator = config.fetch("col_sep", "\t")
        (separator == "\\t") ? "\t" : separator
      end

      def mapped_place_type(place_type, mapping)
        place_type_map = mapping.fetch("place_type_map", {})
        place_type_map.fetch(place_type.to_s, place_type)
      end

      def search_rank_for(place_type, mapping)
        search_rank_map = mapping.fetch("search_rank_map", {})
        Integer(search_rank_map.fetch(place_type.to_s, mapping.fetch("search_rank", 0)))
      end

      def record_allowed?(record, config)
        feature_class_filter = Array(config["feature_class_filter"]).map(&:to_s)
        return true if feature_class_filter.empty?

        feature_class_filter.include?(record["source_place_type"].to_s)
      end

      def metadata_for(properties, mapping)
        mapping.fetch("metadata_fields", {}).filter_map do |key, source|
          value = value_at(properties, source)
          next if value.to_s.empty?

          [key, value]
        end.to_h
      end

      def normalized_properties(properties)
        properties.to_h.transform_keys do |key|
          key.to_s.encode("UTF-8", invalid: :replace, undef: :replace).delete_prefix("\uFEFF")
        end
      end
    end
  end
end
