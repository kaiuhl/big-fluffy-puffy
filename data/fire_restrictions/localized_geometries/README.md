# Localized Fire-Use Geometries

These GeoJSON files support curated localized camping and backpacking fire-use
rules in `config/fire_restriction_curated_rules.yml`.

Generate them with:

```sh
mise exec -- bundle exec ruby scripts/fire_restrictions/generate_localized_geometries.rb
mise exec -- bundle exec ruby scripts/fire_restrictions/generate_elevation_band_geometries.rb
mise exec -- bundle exec ruby scripts/fire_restrictions/generate_wilderness_geometries.rb
```

The generator uses RGeo/GEOS to buffer official NHD waterbody polygons. Current
files are not legal closure boundaries. The app labels them as approximate and
links back to the official rule source.

The elevation-band generator uses USFS EDW wilderness boundaries, BFP's cached
forest boundaries, and the PRISM 800m DEM cached by `scripts/climate/build_normals.py`.
It produces approximate planning polygons for rules such as "above 5,700 feet";
they are not surveyed legal order boundaries.

The wilderness generator clips official USFS EDW wilderness polygons to BFP's
forest boundaries for rules whose legal affected area is an entire wilderness
area.
