# Localized Fire-Use Geometries

These GeoJSON files support curated localized camping and backpacking fire-use
rules in `config/fire_restriction_curated_rules.yml`.

Generate them with:

```sh
mise exec -- bundle exec ruby scripts/fire_restrictions/generate_localized_geometries.rb
```

The generator uses RGeo/GEOS to buffer official NHD waterbody polygons. Current
files are not legal closure boundaries. The app labels them as approximate and
links back to the official rule source.
