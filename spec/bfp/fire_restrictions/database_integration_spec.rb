require "digest"
require_relative "../../spec_helper"

RSpec.describe "fire restriction database integration", :db do
  before do
    skip "Set RUN_DB_SPECS=true with TEST_DATABASE_URL to run database integration specs." unless ENV["RUN_DB_SPECS"] == "true"
  end

  it "seeds the catalog and exposes presenter rows" do
    prepare_fire_restriction_database

    counts = BFP::FireRestrictions::SourceSeeder.new.seed

    expect(counts[:land_units]).to be > 20
    expect(counts[:sources]).to be > 80
    expect(BFP::FireRestrictions::StatusPresenter.new.forests.first).to include(:name, :status, :sources)
  end

  it "processes a fixture restriction fetch for every active forest" do
    prepare_fire_restriction_database
    BFP::FireRestrictions::SourceSeeder.new.seed

    land_units = BFP::FireRestrictions::LandUnit.where(active: true).order(:slug).all
    expect(land_units.length).to be > 20

    land_units.each do |land_unit|
      aggregate_failures(land_unit.slug) do
        source = preferred_html_source(land_unit)
        fetch = create_fixture_fetch(land_unit, source)
        observation = BFP::FireRestrictions::SourceParser.new.parse_fetch(fetch)

        expect(observation.status).to eq("stage_1")
        expect(observation.campfire_policy).to eq("developed_sites_only")
        expect(observation.review_status).to eq("needs_review")
        expect(observation.validation_errors).to eq([])

        observation.update(review_status: "accepted")
        BFP::FireRestrictions::Resolver.new.resolve(land_unit)

        public_status = BFP::FireRestrictions::RestrictionStatus.first(land_unit_id: land_unit.id)
        expect(public_status.status).to eq("stage_1")
        expect(public_status.campfire_policy).to eq("developed_sites_only")
        expect(public_status.restriction_observation_id).to eq(observation.id)
      end
    end

    rows = BFP::FireRestrictions::StatusPresenter.new.forests
    expect(rows.count { |row| row[:status] == "stage_1" }).to eq(land_units.length)
  end

  it "presents observations for human review" do
    prepare_fire_restriction_database
    BFP::FireRestrictions::SourceSeeder.new.seed

    land_unit = BFP::FireRestrictions::LandUnit.first(slug: "willamette")
    source = preferred_html_source(land_unit)
    fetch = create_fixture_fetch(land_unit, source)
    observation = BFP::FireRestrictions::SourceParser.new.parse_fetch(fetch)
    presenter = BFP::FireRestrictions::ReviewPresenter.new

    expect(presenter.queue(limit: 5).first).to include(
      id: observation.id,
      forest: "Willamette National Forest",
      status: "stage_1"
    )
    expect(presenter.candidates(land_unit: "willamette").first).to include(
      id: observation.id,
      best_candidate: true
    )
    expect(presenter.forest("willamette").first).to include(id: observation.id)

    detail = presenter.detail(observation.id)
    expect(detail[:commands]).to include("bin/prod-console -e 'accept_observation(#{observation.id})'")
    expect(detail[:evidence_quotes]).not_to be_empty
    expect(presenter.format_candidates(land_unit: "willamette")).to include("Willamette National Forest")
    expect(presenter.format_forest("willamette")).to include("willamette-fire-info")
    expect(presenter.format_detail(observation.id)).to include("Observation #{observation.id}")
  end

  it "seeds curated localized rules with approximate mapped geometry" do
    prepare_fire_restriction_database
    BFP::FireRestrictions::SourceSeeder.new.seed

    counts = BFP::FireRestrictions::CuratedRuleSeeder.new(now: Time.utc(2026, 5, 16)).seed

    expect(counts[:rules]).to eq(35)
    expect(BFP::FireRestrictions::LocalizedFireUseRule.where(review_status: "accepted").count).to eq(32)
    expect(BFP::FireRestrictions::LocalizedFireUseRule.where(review_status: "needs_review").count).to eq(3)

    detail = BFP::FireRestrictions::ForestStatusPresenter.new(on: Date.new(2026, 5, 16)).forest("wallowa-whitman")
    eagle_cap = detail.fetch(:localized_restrictions).find { |rule| rule[:slug] == "wallowa-whitman-eagle-cap-named-lakes-campfire-prohibition" }

    expect(eagle_cap).to include(
      status: "year_round",
      campfire_policy: "prohibited",
      mapped: true,
      geometry_source_type: "derived_nhd_waterbody_buffer"
    )
    expect(eagle_cap.dig(:geometry_provenance, "geometry_accuracy")).to eq("approximate")

    willamette_detail = BFP::FireRestrictions::ForestStatusPresenter.new(on: Date.new(2026, 5, 16)).forest("willamette")
    jefferson_park = willamette_detail.fetch(:localized_restrictions).find { |rule| rule[:slug] == "willamette-jefferson-park-campfire-prohibition" }

    expect(jefferson_park).to include(
      status: "year_round",
      campfire_policy: "prohibited",
      affected_area: "Jefferson Park area within Mt. Jefferson Wilderness on the Willamette National Forest",
      mapped: false
    )

    mt_hood_detail = BFP::FireRestrictions::ForestStatusPresenter.new(on: Date.new(2026, 5, 16)).forest("mt-hood")
    mt_hood_slugs = mt_hood_detail.fetch(:localized_restrictions).map { |rule| rule[:slug] }
    expect(mt_hood_slugs).to include(
      "mt-hood-bull-run-watershed-fire-prohibition",
      "mt-hood-burnt-lake-half-mile-campfire-prohibition",
      "mt-hood-mark-o-hatfield-wahtum-lake-campfire-prohibition"
    )

    burnt_lake = mt_hood_detail.fetch(:localized_restrictions).find { |rule| rule[:slug] == "mt-hood-burnt-lake-half-mile-campfire-prohibition" }
    expect(burnt_lake).to include(
      campfire_policy: "prohibited",
      mapped: true,
      geometry_source_type: "derived_nhd_waterbody_buffer"
    )

    gifford_detail = BFP::FireRestrictions::ForestStatusPresenter.new(on: Date.new(2026, 5, 16)).forest("gifford-pinchot")
    dewey_lakes = gifford_detail.fetch(:localized_restrictions).find { |rule| rule[:slug] == "gifford-pinchot-william-o-douglas-dewey-lakes-campfire-prohibition" }
    expect(dewey_lakes).to include(
      campfire_policy: "prohibited",
      mapped: true,
      geometry_source_type: "derived_nhd_waterbody_buffer"
    )

    siuslaw_detail = BFP::FireRestrictions::ForestStatusPresenter.new(on: Date.new(2026, 5, 16)).forest("siuslaw")
    expect(siuslaw_detail.fetch(:localized_restrictions).map { |rule| rule[:slug] }).to include("siuslaw-snowy-plover-dry-sand-burning-prohibition")

    map = BFP::FireRestrictions::ForestMapPresenter.new(slug: "wallowa-whitman").geojson
    localized_feature = map.fetch(:features).find { |feature| feature.dig(:properties, :kind) == "localized_restriction" }

    expect(localized_feature.dig(:geometry, "type")).to eq("MultiPolygon")
    expect(localized_feature.dig(:properties, :geometry_is_approximate)).to be(true)

    trinity_detail = BFP::FireRestrictions::ForestStatusPresenter.new(on: Date.new(2026, 5, 16)).forest("klamath")
    expect(trinity_detail.fetch(:localized_restrictions)).to be_empty
  end

  def prepare_fire_restriction_database
    require_relative "../../../config/boot"
    require "sequel/extensions/migration"

    Sequel::Migrator.run(BFP.db, File.join(BFP.root, "db/migrations"))
    require "bfp/fire_restrictions"
    BFP.db.run(<<~SQL)
      TRUNCATE
        restriction_statuses,
        restriction_observations,
        source_fetches,
        source_documents,
        restriction_sources,
        land_units
      RESTART IDENTITY CASCADE
    SQL
  end

  def preferred_html_source(land_unit)
    land_unit.restriction_sources_dataset
      .where(slug: "#{land_unit.slug}-fire-info")
      .first ||
      land_unit.restriction_sources_dataset
        .where(source_type: "fs_fire_info_page")
        .first ||
      land_unit.restriction_sources_dataset.first
  end

  def create_fixture_fetch(land_unit, source)
    body = fixture_html_for(land_unit)
    document = BFP::FireRestrictions::SourceDocument.create(
      content_hash: Digest::SHA256.hexdigest(body),
      content_type: "text/html; charset=utf-8",
      body: Sequel.blob(body),
      metadata_json: BFP::FireRestrictions::Jsonb.wrap({})
    )

    BFP::FireRestrictions::SourceFetch.create(
      restriction_source_id: source.id,
      source_document_id: document.id,
      fetched_at: Time.now,
      http_status: 200,
      final_url: source.url,
      content_type: "text/html; charset=utf-8",
      content_hash: document.content_hash,
      content_changed: true,
      metadata_json: BFP::FireRestrictions::Jsonb.wrap({})
    )
  end

  def fixture_html_for(land_unit)
    <<~HTML
      <!doctype html>
      <html>
        <head>
          <title>#{land_unit.name} Fire Restrictions</title>
          <link rel="canonical" href="#{land_unit.official_url}/fire/info">
        </head>
        <body>
          <main>
            <h1>#{land_unit.name} Fire Restrictions</h1>
            <p>Stage 1 public-use restrictions are in effect for #{land_unit.name}. Campfires are only allowed in developed campgrounds.</p>
            <p>Portable stoves using pressurized liquid fuel are allowed.</p>
          </main>
        </body>
      </html>
    HTML
  end
end
