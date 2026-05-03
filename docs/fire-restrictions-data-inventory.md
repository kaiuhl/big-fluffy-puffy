# Fire Restrictions Data Inventory

Research date: 2026-05-02 and 2026-05-03.

## Scope

BFP's launch market, per the planning document, is Oregon, Washington, and Northern California. For database planning, I would treat the official Pacific Northwest Region forests as the core inventory, then add a Northern California tier that can be turned on or off depending on how far south the product definition of "our area" should reach.

Core Forest Service Region 6 units:

- Colville National Forest
- Deschutes National Forest
- Fremont-Winema National Forest
- Gifford Pinchot National Forest
- Malheur National Forest
- Mount Baker-Snoqualmie National Forest
- Mt. Hood National Forest
- Ochoco National Forest and Crooked River National Grassland
- Okanogan-Wenatchee National Forest
- Olympic National Forest
- Rogue River-Siskiyou National Forest
- Siuslaw National Forest
- Umatilla National Forest
- Umpqua National Forest
- Wallowa-Whitman National Forest
- Willamette National Forest

Northern California first-pass units:

- Klamath National Forest and Butte Valley National Grassland
- Six Rivers National Forest
- Shasta-Trinity National Forest
- Mendocino National Forest
- Modoc National Forest
- Lassen National Forest
- Plumas National Forest
- Tahoe National Forest
- Lake Tahoe Basin Management Unit, if Tahoe is included even though it is not a national forest
- Eldorado National Forest, if the Tahoe/northern Sierra boundary is included

## Bottom Line

There is no single official USFS feed or API that normalizes public-use fire restrictions across these forests.

The best ingestion strategy is mixed:

- Use official Forest Service geodata for stable unit boundaries.
- Scrape the Forest Service Drupal pages for forest-level restriction status, fire danger, alerts, forest orders, and release text.
- Use ArcGIS FeatureServer layers where they exist, especially Central Oregon.
- Use InciWeb and NIFC/WFIGS only for active incident context, not as the source of whether campfires are banned.
- Keep a human-review queue for changed orders, new PDFs, contradictory pages, and first-time parser misses.

The good news: this is feasible. The annoying news: "is there a campfire ban?" is not a pure boolean. Restrictions can be forestwide, ranger-district-specific, wilderness-specific, river-corridor-specific, seasonal, incident-closure-based, or limited to undeveloped/dispersed areas.

## Data Surfaces

### Forest Service Drupal Pages

Most forests now share a common `www.fs.usda.gov/{region}/{forest}` structure:

- `/fire`
- `/fire/info`
- `/alerts`
- `/newsroom/releases`

The page header/dropdown commonly exposes "Alerts and Fire Danger Status" with:

- top alert links
- fire danger rating zones
- links to IFPL, public-use restrictions, InciWeb, partner sites, or maps

These pages are HTML, not JSON, but the structure is regular enough to scrape. Store the full HTML snapshot and extract:

- page title and canonical URL
- last updated date
- alert names and links
- fire danger zones and ratings
- fire restriction links
- IFPL links or labels
- body text around "Current Restrictions", "Public Use Restrictions", "Seasonal Fire Restrictions", "Forest Orders", "Stage 1", "Stage 2", "campfire", and "prohibited"

I did not find advertised RSS or Atom links on the Forest Service forest news/alerts pages, and test paths such as `/newsroom/releases/rss` and `/newsroom/releases.xml` returned 404. The newsroom listing is a Drupal view that can likely be paged/scraped as HTML.

### Forest Service Geodata

Use the Forest Service geodata portals for stable reference layers, not restriction status:

- Forest/unit boundaries
- roads and trails
- recreation sites
- wilderness and special areas
- map products

This is useful for "which national forest is this trail/campground in?" and for default geometry when a restriction is forestwide.

### ArcGIS Restriction Layers

Only Central Oregon turned up as a strong, direct public restriction data source during this pass.

Deschutes/Ochoco/Crooked River link an embedded ArcGIS app:

- ArcGIS app: `b008d24ccb1f4908b8bc3afa2f4666c8`
- Web map: `7306cc7c1e0d4ed186f8cfcea501b55b`
- Feature service: `Fire_Restriction_Status_2023PublicView2`
- Useful layer: `FireRestrictionStatus_2023`

That layer is queryable and has fields:

- `Status`
- `Comments`
- `DataSource`

Sample values from the public layer on 2026-05-03 included `DataSource = "USFS - Deschutes National Forest"` and comment URLs pointing to Central Oregon Fire updates. The app description says statuses include "No Restrictions", "Partial Restrictions", and "Full Restrictions". This is good enough to ingest directly, with a source-specific mapping from numeric status codes to BFP status enums.

I searched ArcGIS Online for comparable Region 6 and Region 5 fire restriction feature services. I found Central Oregon, but not a regionwide R6/R5 equivalent. Other forests have fire closure maps or prescribed-fire maps, which are useful context but not the same as public-use restriction status.

### InciWeb and NIFC/WFIGS

InciWeb has RSS and Google Earth feeds for incident information. NIFC/WFIGS publishes current wildfire perimeter/location feature services. These are valuable for active wildfire context, but they do not answer the core BFP question: whether campfires/open fires are currently allowed in a forest or sub-area.

Use them as secondary layers:

- "active fire nearby"
- "incident closure may exist"
- "large fire info link"

Do not use them as the authoritative public-use restriction state.

### Partner and State Sources

Several forests defer meaningful status to partner sites:

- Central Oregon Fire for Deschutes/Ochoco/Crooked River
- South Central Oregon Fire Management Partnership for Fremont-Winema
- Washington DNR fire danger and IFPL pages for Washington forests
- Blue Mountain Interagency Dispatch Center for Wallowa-Whitman and sometimes Blue Mountain-area context
- Oregon Department of Forestry fire restriction GIS for state-protected lands

These matter because public-facing messaging often aligns across federal, state, BLM, and county lands. But for a "national forest list", the database should distinguish USFS restrictions from adjacent/state restrictions.

## Forest Inventory

### Core Region 6

| Unit | Primary official sources | Machine-readable source found? | Ingestion recommendation |
| --- | --- | --- | --- |
| Colville NF | `/fire`, `/fire/info`, `/alerts`, releases | Prescribed-fire ArcGIS map only; no restriction layer found | Scrape FS fire/info/alerts and release pages |
| Deschutes NF | `/fire/info/public-use-restrictions`, `/alerts`, Central Oregon Fire | Yes: Central Oregon restriction FeatureServer | Ingest ArcGIS layer plus scrape FS page and alerts |
| Fremont-Winema NF | `/fire`, `/fire/info`, `/alerts`, South Central Oregon Fire Management Partnership | No restriction layer found | Scrape FS plus partner status pages |
| Gifford Pinchot NF | `/fire`, `/fire/info`, `/alerts` | No restriction layer found | Scrape FS fire/info/alerts and releases |
| Malheur NF | `/fire`, `/fire/info`, `/fire/prevention`, `/alerts` | No restriction layer found | Scrape FS prevention/info pages for IFPL/restrictions |
| Mount Baker-Snoqualmie NF | `/fire`, `/fire/info`, `/alerts`, WA DNR links | No restriction layer found | Scrape FS and optionally WA DNR fire danger/IFPL context |
| Mt. Hood NF | `/fire`, `/fire/info`, `/alerts` | No restriction layer found | Scrape FS fire/info/alerts |
| Ochoco NF and Crooked River NG | `/fire/info/public-use-restrictions`, `/alerts`, Central Oregon Fire | Yes: same Central Oregon restriction FeatureServer | Ingest ArcGIS layer plus scrape FS page and alerts |
| Okanogan-Wenatchee NF | `/fire/info`, `/alerts`, WA DNR IFPL, interactive fire closure map | Fire closure map, but no public-use restriction layer found | Scrape dropdown/alerts; treat closure map as incident-closure context |
| Olympic NF | `/fire`, `/fire/info`, `/alerts`, WA DNR IFPL | No restriction layer found | Scrape FS and WA DNR context |
| Rogue River-Siskiyou NF | `/fire`, `/fire/info`, `/alerts` | No restriction layer found | Scrape alerts closely; local standing fire prohibitions appear as forest orders |
| Siuslaw NF | `/fire`, `/fire/info`, `/alerts` | No restriction layer found | Scrape FS fire/info/alerts |
| Umatilla NF | `/fire`, `/fire/info`, `/alerts` | No restriction layer found | Scrape FS; useful page-level "no public use restrictions" style text appears |
| Umpqua NF | `/fire`, `/fire/info`, public-use restriction page, `/alerts` | No restriction layer found | Scrape FS, including explicit no-restriction pages |
| Wallowa-Whitman NF | `/fire`, `/fire/info`, `/alerts`, Blue Mountain IDC links | Static/partner fire danger map; no restriction layer found | Scrape FS and BMIDC context |
| Willamette NF | `/fire`, `/fire/info`, `/alerts`, releases | No restriction layer found | Scrape FS fire page table/dropdown; it exposes PUR, fire danger, IFPL |

### Northern California

| Unit | Primary official sources | Machine-readable source found? | Ingestion recommendation |
| --- | --- | --- | --- |
| Klamath NF and Butte Valley NG | `/fire`, `/fire/info`, `/alerts`, releases | No restriction layer found | Scrape FS pages and alerts |
| Six Rivers NF | `/fire`, `/fire/info`, `/alerts`, interactive maps | No restriction layer found | Scrape FS pages and alerts |
| Shasta-Trinity NF | `/fire/info`, `/alerts`, releases | No restriction layer found | Scrape alerts/orders and releases; fire restriction order pages are high-value |
| Mendocino NF | `/fire`, `/fire/info`, `/alerts` | No restriction layer found | Scrape FS pages and alerts |
| Modoc NF | `/fire`, `/fire/info`, `/alerts/forest-fire-restrictions` | No restriction layer found | Scrape the dedicated forest-fire-restrictions alert/page |
| Lassen NF | `/fire`, `/fire/info`, `/alerts` | No restriction layer found | Scrape FS pages and alerts |
| Plumas NF | `/fire`, `/fire/info`, `/alerts` | No restriction layer found | Scrape FS pages and alerts |
| Tahoe NF | `/fire`, `/fire/info`, `/alerts` | No restriction layer found | Include only if Tahoe is in product scope; scrape alerts |
| Lake Tahoe Basin MU | `/fire`, `/fire/info`, fire restriction orders | No restriction layer found | Include only if Tahoe is in product scope; model as a USFS management unit, not a national forest |
| Eldorado NF | `/fire`, `/fire/info`, `/alerts` | No restriction layer found | Include only if northern Sierra/Tahoe is in product scope; scrape FS pages and alerts |

## Data Model Implications

Do not model this as only:

```text
national_forests.fire_ban = true
```

That will collapse too much meaning. A safer v1 model:

### `land_units`

Canonical places BFP tracks.

- `id`
- `name`
- `unit_type`: `national_forest`, `national_grassland`, `scenic_area`, `management_unit`, `wilderness`, `ranger_district`, `special_area`
- `agency`: `USFS`
- `region_code`: `R06`, `R05`
- `forest_slug`
- `parent_land_unit_id`
- `market_bucket`: `core_pnw`, `northern_california`, `extended_tahoe`
- `official_url`
- `boundary_source_url`
- `geometry`

### `restriction_sources`

Every monitored URL/feed/layer.

- `id`
- `land_unit_id`
- `source_type`: `fs_fire_page`, `fs_fire_info_page`, `fs_alerts_page`, `fs_release_page`, `fs_alert_detail`, `arcgis_feature_layer`, `partner_page`, `inciweb_feed`, `nifc_feature_layer`, `state_feature_layer`
- `url`
- `authority`: `official_usfs`, `partner_interagency`, `state`, `incident_context`
- `poll_interval_minutes`
- `parser_key`
- `active`

### `source_fetches`

Raw fetch history.

- `id`
- `restriction_source_id`
- `fetched_at`
- `http_status`
- `etag`
- `last_modified`
- `content_type`
- `content_hash`
- `raw_storage_key`
- `error`

### `restriction_snapshots`

Parsed state for a land unit or sub-area at a point in time.

- `id`
- `land_unit_id`
- `source_fetch_id`
- `status`: `unknown`, `none`, `advisory`, `partial`, `stage_1`, `stage_2`, `full`, `closure`, `year_round`
- `campfire_policy`: `unknown`, `allowed`, `developed_sites_only`, `prohibited`, `propane_allowed`, `stoves_only`
- `public_use_restrictions`
- `ifpl_level`
- `fire_danger_rating`
- `effective_start_at`
- `effective_end_at`
- `announced_at`
- `rescinded_at`
- `order_number`
- `source_url`
- `source_title`
- `confidence`: `low`, `medium`, `high`
- `review_status`: `unreviewed`, `accepted`, `needs_review`, `superseded`
- `parser_version`

### `restriction_areas`

Geometry-specific restrictions when available.

- `id`
- `restriction_snapshot_id`
- `name`
- `area_type`: `forestwide`, `district`, `wilderness`, `river_corridor`, `campground`, `road_trail_closure`, `custom_polygon`
- `geometry`
- `gis_source_url`
- `gis_external_id`
- `attributes`

### `restriction_evidence`

Human-readable extracted evidence for audits and public display.

- `id`
- `restriction_snapshot_id`
- `evidence_type`: `html_text`, `pdf_text`, `arcgis_attributes`, `press_release`
- `quote`
- `source_url`
- `source_date`

This lets the public page say something like:

> Willamette National Forest: no public-use fire restrictions currently listed. Fire danger: Low. IFPL: I. Last checked 2026-05-03. Source: USFS fire page.

And it also lets a more granular page say:

> Deschutes National Forest: no forestwide restrictions, but standing seasonal river-corridor campfire restrictions apply in mapped areas.

## Suggested V1 Workflow

1. Seed `land_units` with the Region 6 forests and chosen Northern California tier.
2. Seed `restriction_sources` with each unit's `/fire`, `/fire/info`, `/alerts`, and `/newsroom/releases`.
3. Add source-specific pages discovered from those links, such as Deschutes public-use restrictions or Modoc forest-fire restrictions.
4. Add the Central Oregon ArcGIS FeatureServer as a first direct GIS ingestion.
5. Fetch all sources daily during off-season and hourly or every 2-4 hours during fire season.
6. Parse conservatively and flag changes for human review before sending outbound alerts.
7. Show `unknown` when sources conflict or a parser cannot classify a changed page.

## Sources Checked

- Forest Service Pacific Northwest Region: https://www.fs.usda.gov/r06
- Forest Service Pacific Southwest Region forests list: https://www.fs.usda.gov/r05/forests-grasslands
- Region 6 geospatial data: https://www.fs.usda.gov/r06/data-tools/gis
- Region 5 geospatial data: https://www.fs.usda.gov/r05/data-tools/gis
- Deschutes public-use restrictions: https://www.fs.usda.gov/r06/deschutes/fire/info/public-use-restrictions
- Okanogan-Wenatchee incident information: https://www.fs.usda.gov/r06/okanogan-wenatchee/fire/info
- Willamette fire page: https://www.fs.usda.gov/r06/willamette/fire
- Shasta-Trinity fire information and alerts: https://www.fs.usda.gov/r05/shasta-trinity/fire/info and https://www.fs.usda.gov/r05/shasta-trinity/alerts
- Central Oregon Fire Restrictions ArcGIS app: https://www.arcgis.com/home/item.html?id=b008d24ccb1f4908b8bc3afa2f4666c8
- Central Oregon Fire Restriction Status feature service: https://services1.arcgis.com/gGHDlz6USftL5Pau/arcgis/rest/services/Fire_Restriction_Status_2023PublicView2/FeatureServer
- InciWeb feeds: https://inciweb.wildfire.gov/feeds
- NIFC/WFIGS current fire perimeters: https://data-nifc.opendata.arcgis.com/
