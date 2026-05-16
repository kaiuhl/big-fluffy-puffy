# Fire Restriction Localized Review Inventory

Checked date: 2026-05-16.

## Scope

This inventory supports `config/fire_restriction_curated_rules.yml`, a seed data file for localized camping and backpacking fire-use restrictions that are too specific to publish as forestwide status. Only official Forest Service sources were used.

The seed uses static generated geometry only where the rule shape can be represented from an official geodata source with clear provenance. Current generated shapes are approximate lake-buffer circles derived from official NHD waterbody centroids. Elevation rules, trail-bounded areas, lake basins, and order-exhibit areas stay unmapped until a repeatable derivation or official GIS layer is available.

## Seed Summary

- Rules in seed file: 22
- High-confidence accepted rules: 19
- Needs-review rules: 3
- Official source URLs used as primary `source_url` values: 11
- Generated localized GeoJSON files: 6
- Approximate NHD centroid-buffer polygons generated: 58
- Checked date embedded in metadata: 2026-05-16

## Generated Geometry

Generated files live in `data/fire_restrictions/localized_geometries/` and are created by:

```sh
mise exec -- bundle exec ruby scripts/fire_restrictions/generate_localized_geometries.rb
```

Generated geometries are intentionally labeled `derived_nhd_centroid_buffer` with `geometry_accuracy: approximate`.
They are good enough to show "roughly where this named lake buffer is" and not good enough to treat as official legal boundaries.

Generated coverage:

| Rule group | Buffer count | Missing names | Notes |
| --- | ---: | --- | --- |
| Wallowa-Whitman Eagle Cap named lakes | 22 | none | 1/4-mile approximate buffers |
| Okanogan-Wenatchee Alpine Lakes named lakes | 25 | Upper Park Lake | 1/2-mile approximate buffers |
| Okanogan-Wenatchee Henry M. Jackson named lakes | 6 | none | 1/4-mile approximate buffers |
| Okanogan-Wenatchee Glacier Peak Ice Lakes | 1 | none | 1/2-mile approximate buffer |
| Okanogan-Wenatchee William O. Douglas named lakes | 2 | none | 1/4-mile approximate buffers |
| Gifford Pinchot Goat Rocks named lakes | 2 | none | Partial geometry only; Snowgrass Flats and Dana Yelverton Shelter are not represented |

## Priority Coverage

### P0 Central Cascades, Deschutes and Willamette

Seeded seven accepted rules from the joint Deschutes and Willamette order and the Willamette Jefferson Park recreation page:

- `deschutes-central-cascades-5700-ft-fire-prohibition`
- `willamette-central-cascades-5700-ft-fire-prohibition`
- `deschutes-diamond-peak-6000-ft-fire-prohibition`
- `willamette-diamond-peak-6000-ft-fire-prohibition`
- `deschutes-mt-jefferson-washington-lake-basins-fire-prohibition`
- `willamette-mt-jefferson-washington-lake-basins-fire-prohibition`
- `willamette-jefferson-park-campfire-prohibition`

Official sources:

- https://www.fs.usda.gov/media/144510
- https://www.fs.usda.gov/r06/deschutes/wilderness
- https://www.fs.usda.gov/r06/willamette/wilderness
- https://www.fs.usda.gov/r06/willamette/recreation/jefferson-park-area-mt-jefferson-wilderness

Decision notes:

- The order is active from 2024-05-01 through 2029-04-30.
- `duration_type` is `temporary` because the order has an explicit end date.
- `status` is `year_round` because the restrictions apply as standing non-seasonal localized rules while the order is active.
- Gas and liquid-fuel stoves are accepted as allowed because the order excepts stoves fueled with liquid or compressed gas.
- Alcohol stove policy is `unknown` because the order does not specifically name alcohol stoves or a shutoff-valve requirement.
- The Jefferson Park page is seeded as a separate permanent campfire prohibition because it explicitly states that campfires are not permitted inside Jefferson Park. Its stove and charcoal fields remain `unknown` because that page does not describe them.

### P0 Okanogan-Wenatchee Always-In-Effect Rules

Seeded seven accepted rules:

- `okanogan-wenatchee-alpine-lakes-5000-ft-campfire-prohibition`
- `okanogan-wenatchee-alpine-lakes-named-lakes-campfire-prohibition`
- `okanogan-wenatchee-henry-jackson-named-lakes-campfire-prohibition`
- `okanogan-wenatchee-glacier-peak-lake-buffers-campfire-prohibition`
- `okanogan-wenatchee-glacier-peak-lime-ridge-4000-ft-campfire-prohibition`
- `okanogan-wenatchee-william-o-douglas-named-lakes-campfire-prohibition`
- `okanogan-wenatchee-goat-rocks-shoe-snowgrass-campfire-prohibition`

Official sources:

- https://www.fs.usda.gov/r06/okanogan-wenatchee/fire/info/wilderness-area-fire-restrictions-always-effect
- https://www.fs.usda.gov/r06/okanogan-wenatchee/alerts/campfire-and-camping-restrictions-henry-m-jackson-wilderness
- https://www.fs.usda.gov/r06/okanogan-wenatchee/recreation/glacier-peak-wilderness-okanogan-wenatchee

Decision notes:

- The Okanogan-Wenatchee always-in-effect page directly states that campfires are never allowed in the listed areas.
- Where official text says only "campfires," BFP stove and charcoal policy fields are left `unknown`.
- Henry M. Jackson and Glacier Peak pages except self-contained carry-in stoves, but do not break out BFP stove fuel classes, so stove fuel fields remain `unknown`.

### P1 Wallowa-Whitman Eagle Cap

Seeded one accepted rule:

- `wallowa-whitman-eagle-cap-named-lakes-campfire-prohibition`

Official source:

- https://www.fs.usda.gov/r06/wallowa-whitman/recreation/eagle-cap-wilderness

Decision notes:

- The named lake 1/4-mile campfire prohibition is accepted.
- The general 100-foot lake camping and campfire rule is recorded in metadata, but not separately seeded because the current geometry strategy list does not include a general waterbody buffer strategy.
- Stove and charcoal policies are left `unknown` because the source does not resolve them.

### P1 Trinity Alps, Klamath/Shasta-Trinity/Six Rivers

Seeded three needs-review rules:

- `klamath-trinity-alps-campfire-prohibition-areas`
- `shasta-trinity-trinity-alps-campfire-prohibition-areas`
- `six-rivers-trinity-alps-campfire-prohibition-areas`

Official sources:

- https://www.fs.usda.gov/r05/klamath/alerts/trinity-alps-wilderness-area-restrictions
- https://www.fs.usda.gov/r05/shasta-trinity/alerts/trinity-alps-wilderness-area-restrictions
- https://www.fs.usda.gov/r05/sixrivers/alerts/trinity-wilderness-area-restrictions

Decision notes:

- The order is active from 2025-09-19 through 2028-09-19.
- The order is cross-forest and depends on Exhibit B for the Campfire Prohibition Areas 1, 2, and 3 geometry.
- These are intentionally `needs_review` with `geometry_strategy: official_map_pending` until the exhibit geometry is digitized or otherwise represented.
- Gas, jellied petroleum, and pressurized liquid-fuel stoves with shutoff valves are accepted as allowed. Alcohol, solid-fuel, and charcoal policies remain `unknown`.

### P1 Olympic Elevation Rule

Seeded one accepted rule:

- `olympic-wilderness-3500-ft-open-fire-prohibition`

Official source:

- https://www.fs.usda.gov/r06/olympic/wilderness

Decision notes:

- The wilderness page directly prohibits starting or maintaining open fires above 3,500 feet.
- The rule uses `geometry_strategy: elevation_above`.
- Stove and charcoal sub-policies are left `unknown` because the current page resolves open-fire policy, not BFP stove fuel classes.

### P1 Gifford Pinchot Named Wilderness Rules

Seeded three accepted rules:

- `gifford-pinchot-mt-adams-high-country-campfire-prohibition`
- `gifford-pinchot-goat-rocks-named-campfire-prohibitions`
- `gifford-pinchot-tatoosh-lakes-basin-campfire-prohibition`

Official sources:

- https://www.fs.usda.gov/r06/giffordpinchot/wilderness/wilderness-regulations
- https://www.fs.usda.gov/r06/giffordpinchot/recreation/wilderness-goat-rocks
- https://www.fs.usda.gov/r06/giffordpinchot/recreation/wilderness-tatoosh
- https://www.fs.usda.gov/media/151852

Decision notes:

- Mt. Adams, Goat Rocks named areas, and Tatoosh Lakes Basin have direct official evidence.
- The seed uses the narrower Goat Rocks named prohibitions from the regulations/order rather than the broader recreation-page "No campfires" wording, because the broad wording conflicts with the narrower order text.
- Mt. Adams is accepted as text-supported but uses `named_area_manual_review` because the boundary is described by trails and forest boundaries rather than coordinates.

## Source URLs

Primary source URLs in the seed:

- https://www.fs.usda.gov/media/144510
- https://www.fs.usda.gov/r06/okanogan-wenatchee/fire/info/wilderness-area-fire-restrictions-always-effect
- https://www.fs.usda.gov/r06/okanogan-wenatchee/alerts/campfire-and-camping-restrictions-henry-m-jackson-wilderness
- https://www.fs.usda.gov/r06/okanogan-wenatchee/recreation/glacier-peak-wilderness-okanogan-wenatchee
- https://www.fs.usda.gov/r06/wallowa-whitman/recreation/eagle-cap-wilderness
- https://www.fs.usda.gov/r05/klamath/alerts/trinity-alps-wilderness-area-restrictions
- https://www.fs.usda.gov/r05/shasta-trinity/alerts/trinity-alps-wilderness-area-restrictions
- https://www.fs.usda.gov/r05/sixrivers/alerts/trinity-wilderness-area-restrictions
- https://www.fs.usda.gov/r06/olympic/wilderness
- https://www.fs.usda.gov/r06/giffordpinchot/wilderness/wilderness-regulations

Related official URLs captured in metadata or review notes:

- https://www.fs.usda.gov/r06/deschutes/wilderness
- https://www.fs.usda.gov/r06/willamette/wilderness
- https://www.fs.usda.gov/r06/giffordpinchot/recreation/wilderness-goat-rocks
- https://www.fs.usda.gov/r06/giffordpinchot/recreation/wilderness-tatoosh
- https://www.fs.usda.gov/media/151852

## Uncertainty Ledger

- Central Cascades: The joint order is strong, but it expires on 2029-04-30 unless extended or rescinded earlier. Annual review is still needed.
- Central Cascades: Alcohol stove policy is unresolved. The order excepts liquid-fuel stoves but does not specifically identify alcohol stoves or shutoff-valve requirements.
- Okanogan-Wenatchee: Several official pages state only campfire prohibitions. Stove and charcoal policy fields are therefore `unknown` unless the source explicitly provides an exception.
- Okanogan-Wenatchee: Named lake buffers are generated as approximate NHD centroid buffers. Upper Park Lake did not resolve cleanly in NHD and remains unmapped.
- Wallowa-Whitman: The Eagle Cap named-lake 1/4-mile buffers are generated as approximate NHD centroid buffers. The general 100-foot all-lake rule is not separately seeded because it would require a broader hydrography buffer workflow.
- Trinity Alps: The restriction is real and active, but publication needs Exhibit B geometry and cross-forest handling. It stays `needs_review`.
- Olympic: The 3,500-foot wilderness rule is direct, but the source does not map BFP stove fuel classes.
- Gifford Pinchot: Goat Rocks has broader "No campfires" wording on a recreation page and narrower named prohibitions in the regulations/order. The seed accepts only the narrower named restrictions. Generated geometry is partial for Goat Lake and Shoe Lake only.
- Gifford Pinchot: Mt. Adams requires later manual geometry work because the official boundary is described by named trails and forest boundaries.
