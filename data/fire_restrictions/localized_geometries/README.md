# Localized Fire-Use Geometries

These GeoJSON files support curated localized camping and backpacking fire-use
rules in `config/fire_restriction_curated_rules.yml`.

Generate them with:

```sh
mise exec -- bundle exec ruby scripts/fire_restrictions/generate_localized_geometries.rb
```

Current files are approximate buffers around official NHD waterbody centroids,
not legal closure boundaries. The app labels them as approximate and links back
to the official rule source.
