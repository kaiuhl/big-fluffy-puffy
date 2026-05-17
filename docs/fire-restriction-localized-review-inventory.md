# Fire Restriction Localized Review Inventory

Checked date: 2026-05-16.

## Scope

This inventory supports `config/fire_restriction_curated_rules.yml`, a seed data file for localized camping and backpacking fire-use restrictions that are too specific to publish as forestwide status. Official Forest Service sources were used for accepted Forest Service orders and recreation pages. Mt. Hood wilderness-detail rows use Wilderness Connect pages that the official Mt. Hood fire page links as its year-round wilderness fire-regulation detail source.

The seed uses static generated or digitized geometry only where the rule shape can be represented from an official geodata source with clear provenance. Current generated lake-buffer shapes are approximate buffers around official NHD waterbody polygons. Elevation rules, trail-bounded areas, lake basins, and order-exhibit areas stay unmapped until a repeatable derivation, official map exhibit, or official GIS layer is available. The Willamette Mt. Jefferson/Mt. Washington lake-basin row is mapped because the order defines those named lake basins as 1/4-mile high-water buffers.

## Seed Summary

- Rules in seed file: 53
- High-confidence accepted rules: 49
- Needs-review rules: 4
- Primary `source_url` values: 39
- Generated localized GeoJSON files: 27
- Approximate NHD waterbody-buffer polygons generated: 81
- Approximate GNIS named-feature buffers generated: 2
- Approximate USFS trail/boundary polygons generated: 1
- Checked date embedded in metadata: 2026-05-16

## Generated Geometry

Generated files live in `data/fire_restrictions/localized_geometries/` and are created by:

```sh
mise exec -- bundle exec ruby scripts/fire_restrictions/generate_localized_geometries.rb
```

The generator uses RGeo/GEOS and requires the GEOS system library. Docker installs `libgeos-dev` for parity with local generation.

Generated geometries are intentionally labeled `derived_nhd_waterbody_buffer` with `geometry_accuracy: approximate`.
They are good enough to show "roughly where this named lake buffer is" and not good enough to treat as official legal boundaries.
The Jefferson Park and Waldo Lake island GeoJSON files in the same directory are exceptions: they are hand-digitized `source_pdf_map` polygons from official PDF map exhibits or USGS GeoPDF quadrangles.

Generated coverage:

| Rule group | Buffer count | Missing names | Notes |
| --- | ---: | --- | --- |
| Wallowa-Whitman Eagle Cap named lakes | 22 | none | 1/4-mile approximate buffers |
| Okanogan-Wenatchee Alpine Lakes named lakes | 25 | Upper Park Lake | 1/2-mile approximate buffers |
| Okanogan-Wenatchee Henry M. Jackson named lakes | 6 | none | 1/4-mile approximate buffers |
| Okanogan-Wenatchee Glacier Peak Ice Lakes | 1 | none | 1/2-mile approximate buffer |
| Okanogan-Wenatchee William O. Douglas named lakes | 2 | none | 1/4-mile approximate buffers |
| Gifford Pinchot Goat Rocks named lakes | 2 | none | Partial geometry only; Snowgrass Flats and Dana Yelverton Shelter are not represented |
| Mt. Hood Ramona Falls and McNeil Point | 2 | none | 500-foot GNIS named-feature point buffers; other Mount Hood Wilderness meadow/island/Paradise Park language is not represented |
| Mt. Hood Burnt Lake | 1 | none | 1/2-mile approximate buffer |
| Mt. Hood Wahtum Lake | 1 | none | 200-foot approximate buffer |
| Gifford Pinchot William O. Douglas Dewey Lakes | 1 | none | 1/4-mile approximate buffer |
| Gifford Pinchot Mt. Adams high-country area | 1 polygon | none | Derived from official USFS trail centerlines, forest boundary, wilderness boundary, and checked against the official map exhibit |
| Willamette Mt. Jefferson/Mt. Washington named lakes | 8 | none | 1/4-mile approximate buffers around Marion Lake, Lake Ann, Table Lake, Benson Lake, and four Tenas Lakes NHD polygons |

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
- The Willamette Mt. Jefferson/Mt. Washington named lake geometry maps the order's "within 1/4 mile of the high water mark" language for Marion Lake, Lake Ann, Table Lake, Benson Lake, and Tenas Lakes. It uses approximate NHD waterbody buffers and was spot-checked against Exhibits L and M.
- The Jefferson Park page is seeded as a separate permanent campfire prohibition because it explicitly states that campfires are not permitted inside Jefferson Park. Its stove and charcoal fields remain `unknown` because that page does not describe them.
- The Jefferson Park geometry is hand-digitized from the official Forest Service Jefferson Park Vicinity GeoPDF Fire Ban Area map. The original Forest Service document URL now returns 404, so the archived official PDF is retained as the geometry source. Treat it as an approximate planning polygon, not a surveyed legal boundary.

### P0 Portland-Area Audit

Audited Portland-adjacent catalog forests: Mt. Hood, Gifford Pinchot, Willamette, and Siuslaw. Columbia River Gorge National Scenic Area is not yet a BFP land unit; Mark O. Hatfield Wilderness rules linked from the official Mt. Hood fire page are currently seeded under Mt. Hood with cross-unit provenance notes.

New accepted rules added from the audit:

- `willamette-waldo-lake-islands-campfire-prohibition`
- `willamette-cedar-creek-fire-closure`
- `willamette-beachie-lionshead-fire-closure`
- `mt-hood-bull-run-watershed-fire-prohibition`
- `mt-hood-sportsmans-park-fire-occupancy-prohibition`
- `mt-hood-mount-hood-wilderness-named-area-campfire-prohibitions`
- `mt-hood-burnt-lake-half-mile-campfire-prohibition`
- `mt-hood-mark-o-hatfield-wahtum-lake-campfire-prohibition`
- `mt-hood-mark-o-hatfield-eagle-creek-trail-campfire-prohibition`
- `siuslaw-snowy-plover-dry-sand-burning-prohibition`
- `gifford-pinchot-william-o-douglas-dewey-lakes-campfire-prohibition`
- `gifford-pinchot-drift-creek-cove-fire-prohibition`
- `gifford-pinchot-mount-st-helens-area-three-margaret-fire-prohibition`

Primary sources:

- https://www.fs.usda.gov/r06/willamette/recreation/waldo-lake-area
- https://www.fs.usda.gov/r06/willamette/alerts/cedar-creek-fire-closure
- https://www.fs.usda.gov/r06/willamette/alerts/beachie-creek-and-lionshead-fires-closure
- https://www.fs.usda.gov/r06/mthood/fire
- https://www.fs.usda.gov/r06/mthood/alerts/bull-run-watershed-closure
- https://www.fs.usda.gov/r06/mthood/alerts/sportsmans-park-fire-occupancy-restrictions
- https://wilderness.net/visit-wilderness/?ID=374#area-management
- https://wilderness.net/visit-wilderness/?ID=342#area-management
- https://www.fs.usda.gov/r06/siuslaw/alerts/beach-restrictions-effect-march-15-sept-15-protect-nesting-western-snowy-plover
- https://www.fs.usda.gov/media/151852
- https://www.fs.usda.gov/r06/giffordpinchot/alerts/drift-creek-cove-fire-restrictions
- https://www.fs.usda.gov/r06/giffordpinchot/alerts/mount-st-helens-volcanic-monument-restrictions

Decision notes:

- Mt. Hood's official fire page explicitly points users to year-round area-specific campfire restrictions. BFP captures the linked Mount Hood Wilderness and Mark O. Hatfield Wilderness rules, with Burnt Lake and Wahtum Lake mapped from approximate NHD waterbody buffers. The Mount Hood Wilderness named-area row now also maps the explicit 500-foot Ramona Falls and McNeil Point buffers from the current Timberline Trail #600 guide using approximate GNIS point buffers.
- Bull Run, Cedar Creek, Beachie/Lionshead, Mount St. Helens, and snowy plover rows are closure/status rows. Where access is prohibited, BFP marks campfire policy as prohibited and records that the campfire policy is inferred from the active access closure rather than from a campfire-only order.
- Beachie/Lionshead is active on the checked date but expires on 2026-05-21; it is due for immediate post-expiration review.
- Waldo Lake islands are mapped from official USGS 1997 Waldo Lake and Waldo Mountain GeoPDF quadrangles because the Forest Service recreation page gives the day-use/campfire rule but does not publish machine-readable island boundaries. The geometry represents primary mapped island landforms and remains approximate.
- The Siuslaw snowy plover row is a 2026 seasonal closure from 2026-03-15 through 2026-09-15. It should be refreshed from the current year's order before the 2027 nesting season.
- Drift Creek Cove and Mount St. Helens official orders include map exhibits, but BFP has not digitized those polygons yet.
- Lewis River and broad Goat Rocks "No campfires" recreation-page language remain unseeded because current official evidence is less specific or conflicts with narrower order text.
- Opal Creek has vague page-level campfire-prohibition wording, but the current closure order reviewed in this pass did not clearly establish a separate active campfire restriction.
- Siuslaw sand-camping and general beach-fire FAQ guidance are not seeded as localized fire restrictions because the audit did not find a clean active Forest Service order for those backpacking/campfire scenarios.

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

### P1 Gifford Pinchot Named Wilderness And Localized Closure Rules

Seeded six accepted rules:

- `gifford-pinchot-mt-adams-high-country-campfire-prohibition`
- `gifford-pinchot-goat-rocks-named-campfire-prohibitions`
- `gifford-pinchot-tatoosh-lakes-basin-campfire-prohibition`
- `gifford-pinchot-william-o-douglas-dewey-lakes-campfire-prohibition`
- `gifford-pinchot-drift-creek-cove-fire-prohibition`
- `gifford-pinchot-mount-st-helens-area-three-margaret-fire-prohibition`

Official sources:

- https://www.fs.usda.gov/r06/giffordpinchot/wilderness/wilderness-regulations
- https://www.fs.usda.gov/r06/giffordpinchot/recreation/wilderness-goat-rocks
- https://www.fs.usda.gov/r06/giffordpinchot/recreation/wilderness-tatoosh
- https://www.fs.usda.gov/media/151852
- https://www.fs.usda.gov/r06/giffordpinchot/alerts/drift-creek-cove-fire-restrictions
- https://www.fs.usda.gov/r06/giffordpinchot/alerts/mount-st-helens-volcanic-monument-restrictions

Decision notes:

- Mt. Adams, Goat Rocks named areas, and Tatoosh Lakes Basin have direct official evidence.
- The seed uses the narrower Goat Rocks named prohibitions from the regulations/order rather than the broader recreation-page "No campfires" wording, because the broad wording conflicts with the narrower order text.
- Mt. Adams is accepted as text-supported and now has approximate generated geometry derived from official USFS Trail #2000, #114, and #9 centerlines, the Gifford Pinchot/Yakama forest boundary, and the Mount Adams Wilderness polygon, checked against the official Mt. Adams campfire restriction map exhibit.
- Dewey Lakes is mapped as an approximate NHD waterbody buffer because the order states a 1/4-mile shoreline buffer. The generated shape buffers the NHD waterbody polygon, not an official legal exhibit.
- Drift Creek Cove and Mount St. Helens are accepted as active temporary orders with official exhibit geometry pending.

## Source URLs

Primary source URLs in the seed:

- https://wilderness.net/visit-wilderness/?ID=342#area-management
- https://wilderness.net/visit-wilderness/?ID=374#area-management
- https://www.fs.usda.gov/media/144510
- https://www.fs.usda.gov/media/151852
- https://www.fs.usda.gov/media/234596
- https://www.fs.usda.gov/r05/klamath/alerts/trinity-alps-wilderness-area-restrictions
- https://www.fs.usda.gov/r05/shasta-trinity/alerts/trinity-alps-wilderness-area-restrictions
- https://www.fs.usda.gov/r05/sixrivers/alerts/trinity-wilderness-area-restrictions
- https://www.fs.usda.gov/r06/deschutes/wilderness
- https://www.fs.usda.gov/r06/giffordpinchot/alerts/drift-creek-cove-fire-restrictions
- https://www.fs.usda.gov/r06/giffordpinchot/alerts/mount-st-helens-volcanic-monument-restrictions
- https://www.fs.usda.gov/r06/giffordpinchot/wilderness/wilderness-regulations
- https://www.fs.usda.gov/r06/mthood/alerts/bull-run-watershed-closure
- https://www.fs.usda.gov/r06/mthood/alerts/sportsmans-park-fire-occupancy-restrictions
- https://www.fs.usda.gov/r06/okanogan-wenatchee/fire/info/wilderness-area-fire-restrictions-always-effect
- https://www.fs.usda.gov/r06/okanogan-wenatchee/recreation/glacier-peak-wilderness-okanogan-wenatchee
- https://www.fs.usda.gov/r06/olympic/wilderness
- https://www.fs.usda.gov/r06/siuslaw/alerts/beach-restrictions-effect-march-15-sept-15-protect-nesting-western-snowy-plover
- https://www.fs.usda.gov/r06/wallowa-whitman/recreation/eagle-cap-wilderness
- https://www.fs.usda.gov/r06/willamette/alerts/beachie-creek-and-lionshead-fires-closure
- https://www.fs.usda.gov/r06/willamette/alerts/cedar-creek-fire-closure
- https://www.fs.usda.gov/r06/willamette/recreation/jefferson-park-area-mt-jefferson-wilderness
- https://www.fs.usda.gov/r06/willamette/recreation/waldo-lake-area
- https://www.fs.usda.gov/r06/willamette/wilderness

Related official URLs captured in metadata or review notes:

- https://www.fs.usda.gov/r06/mthood/fire
- https://www.fs.usda.gov/r06/mthood/recreation/trails/timberline-trail-600
- https://www.fs.usda.gov/media/202123
- https://www.fs.usda.gov/r06/okanogan-wenatchee/alerts/campfire-and-camping-restrictions-henry-m-jackson-wilderness
- https://www.fs.usda.gov/r06/giffordpinchot/recreation/wilderness-goat-rocks
- https://www.fs.usda.gov/r06/giffordpinchot/recreation/wilderness-tatoosh

## Uncertainty Ledger

- Central Cascades: The joint order is strong, but it expires on 2029-04-30 unless extended or rescinded earlier. Annual review is still needed.
- Central Cascades: Alcohol stove policy is unresolved. The order excepts liquid-fuel stoves but does not specifically identify alcohol stoves or shutoff-valve requirements.
- Okanogan-Wenatchee: Several official pages state only campfire prohibitions. Stove and charcoal policy fields are therefore `unknown` unless the source explicitly provides an exception.
- Okanogan-Wenatchee: Named lake buffers are generated as approximate NHD waterbody buffers. Upper Park Lake did not resolve cleanly in NHD and remains unmapped.
- Wallowa-Whitman: The Eagle Cap named-lake 1/4-mile buffers are generated as approximate NHD waterbody buffers. The general 100-foot all-lake rule is not separately seeded because it would require a broader hydrography buffer workflow.
- Trinity Alps: The restriction is real and active, but publication needs Exhibit B geometry and cross-forest handling. It stays `needs_review`.
- Olympic: The 3,500-foot wilderness rule is direct, but the source does not map BFP stove fuel classes.
- Mt. Hood: Wilderness Connect is used for Burnt Lake and Mark O. Hatfield rows because the official Mt. Hood fire page links it as a detail source for year-round wilderness fire rules. The Mount Hood Wilderness named-area row uses the current official Timberline Trail #600 guide for the explicit Ramona Falls/McNeil Point buffer text and retains Wilderness Connect as prior-source provenance.
- Mt. Hood: The Mount Hood Wilderness named-area geometry is partial. Meadows, Elk Cove and Elk Meadows tree-covered islands, and Paradise Park remain unmapped until official polygons or repeatable boundary data are available.
- Mt. Hood: Mark O. Hatfield Wilderness crosses Mt. Hood and Columbia River Gorge administration. BFP should add a Columbia River Gorge land unit before these rules can be assigned perfectly.
- Mt. Hood: Eagle Creek Trail needs official trail-segment geometry and a 1000-foot buffer clipped to the described endpoints before mapping.
- Mt. Hood: Bull Run and Sportsman's Park need official exhibit geometry digitized before mapping.
- Willamette: Beachie Creek/Lionshead expires on 2026-05-21 and should be removed or refreshed immediately after that date.
- Willamette: Cedar Creek and Beachie/Lionshead closure rows are access closures, not campfire-only restrictions. Their campfire prohibition is inferred from the fact that public entry is prohibited in the affected areas.
- Willamette: Opal Creek page-level campfire-prohibition wording needs a clearer current order or official detail source before it should be seeded.
- Siuslaw: Snowy plover beach restriction geometry is map/exhibit-derived and not yet digitized. General sand-camping and beach-fire FAQ guidance was not accepted as an active localized fire restriction.
- Gifford Pinchot: Goat Rocks has broader "No campfires" wording on a recreation page and narrower named prohibitions in the regulations/order. The seed accepts only the narrower named restrictions. Generated geometry is partial for Goat Lake and Shoe Lake only.
- Gifford Pinchot: Mt. Adams is mapped as an approximate generated trail/boundary polygon. It should be treated as a planning shape checked against the official map exhibit, not a surveyed legal boundary.
- Gifford Pinchot: Lewis River "No campfires" wording was not seeded because the audit did not find an active order/date with enough specificity.
- Gifford Pinchot: Drift Creek Cove and Mount St. Helens exhibit maps are official but not yet digitized.
