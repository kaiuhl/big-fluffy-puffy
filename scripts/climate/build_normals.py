#!/usr/bin/env python3
import argparse
import csv
import hashlib
import json
import math
import sys
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import rasterio
from rasterio.errors import WindowError
from rasterio.features import geometry_mask, geometry_window
from rasterio.warp import transform_geom


DATASET_SLUG = "prism-1991-2020-tmin-800m"
PRISM_NORMALS_URL = "https://prism.oregonstate.edu/normals/"
PRISM_TMIN_BASE_URL = "https://data.prism.oregonstate.edu/normals/us/800m/tmin/monthly"
PRISM_DEM_URL = "https://prism.oregonstate.edu/downloads/data/PRISM_us_dem_800m_bil.zip"
BOUNDARY_SOURCE = "data/fire_restriction_boundaries.geojson"
FT_PER_METER = 3.280839895
ACRES_PER_SQUARE_METER = 0.00024710538146717

ELEVATION_BANDS = [
    (0, 2000),
    (2000, 4000),
    (4000, 6000),
    (6000, 8000),
    (8000, 10000),
    (10000, 12000),
    (12000, None),
]

CSV_COLUMNS = [
    "land_unit_slug",
    "land_unit_name",
    "climate_dataset_slug",
    "month",
    "elevation_min_ft",
    "elevation_max_ft",
    "elevation_band_label",
    "mean_low_f",
    "cold_p10_low_f",
    "warm_p90_low_f",
    "sample_cell_count",
    "area_acres",
    "area_pct_of_forest",
    "metadata_json",
]


def parse_args():
    parser = argparse.ArgumentParser(description="Build forest climate low normals by elevation band.")
    parser.add_argument("--boundaries", default=BOUNDARY_SOURCE)
    parser.add_argument("--cache-dir", default="tmp/climate")
    parser.add_argument("--output-csv", default="data/climate/prism_1991_2020_tmin_forest_elevation_bands.csv")
    parser.add_argument("--output-manifest", default="data/climate/prism_1991_2020_tmin_manifest.json")
    return parser.parse_args()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.stat().st_size > 0:
        return target

    request = urllib.request.Request(
        url,
        headers={"User-Agent": "BigFluffyPuffyClimateNormals/1.0 (https://bigfluffypuffy.org)"},
    )
    with urllib.request.urlopen(request, timeout=180) as response, open(target, "wb") as output:
        output.write(response.read())
    return target


def extract_zip(zip_path, extract_root):
    destination = extract_root / zip_path.stem
    marker = destination / ".extracted"
    if marker.exists():
        return destination

    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(destination)
    marker.write_text(datetime.now(timezone.utc).isoformat(), encoding="utf-8")
    return destination


def raster_path(extracted_dir):
    candidates = sorted(
        [
            path
            for path in extracted_dir.rglob("*")
            if path.suffix.lower() in {".bil", ".tif", ".tiff"}
        ]
    )
    if not candidates:
        raise RuntimeError(f"No raster found in {extracted_dir}")
    return candidates[0]


def tmin_url(month):
    return f"{PRISM_TMIN_BASE_URL}/prism_tmin_us_30s_2020{month:02d}_avg_30y.zip"


def download_sources(cache_dir):
    raw_dir = cache_dir / "raw"
    extracted_dir = cache_dir / "extracted"
    downloads = {}

    dem_zip = download(PRISM_DEM_URL, raw_dir / Path(PRISM_DEM_URL).name)
    downloads["dem"] = {
        "url": PRISM_DEM_URL,
        "zip_path": str(dem_zip),
        "sha256": sha256_file(dem_zip),
        "raster_path": str(raster_path(extract_zip(dem_zip, extracted_dir))),
    }

    downloads["tmin"] = {}
    for month in range(1, 13):
        url = tmin_url(month)
        zip_path = download(url, raw_dir / Path(url).name)
        downloads["tmin"][str(month)] = {
            "url": url,
            "zip_path": str(zip_path),
            "sha256": sha256_file(zip_path),
            "raster_path": str(raster_path(extract_zip(zip_path, extracted_dir))),
        }

    return downloads


def load_boundaries(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    return data.get("features", [])


def band_label(min_ft, max_ft):
    if max_ft is None:
        return f"{min_ft:,}+ ft"
    return f"{min_ft:,}-{max_ft:,} ft"


def fahrenheit(celsius_values):
    return (celsius_values * 9.0 / 5.0) + 32.0


def finite_data(masked):
    data = np.asarray(masked, dtype="float64")
    mask = np.ma.getmaskarray(masked)
    return data, mask


def transformed_geometry(feature, raster_crs):
    geometry = feature.get("geometry")
    if raster_crs is None:
        return geometry
    return transform_geom("EPSG:4326", raster_crs, geometry)


def forest_window(src, geometry):
    try:
        return geometry_window(src, [geometry], pad_x=0, pad_y=0)
    except WindowError:
        return None


def raster_rows(features, downloads):
    rows = []
    tmin_paths = {int(month): info["raster_path"] for month, info in downloads["tmin"].items()}

    with rasterio.open(downloads["dem"]["raster_path"]) as dem_src:
        raster_crs = dem_src.crs

        with rasterio.open(tmin_paths[1]) as first_tmin:
            if dem_src.width != first_tmin.width or dem_src.height != first_tmin.height:
                raise RuntimeError("DEM and Tmin rasters do not have matching shapes.")

        for feature in features:
            properties = feature.get("properties", {})
            slug = properties.get("slug")
            name = properties.get("name")
            gis_acres = float(properties.get("gis_acres") or 0.0)
            geometry = transformed_geometry(feature, raster_crs)
            window = forest_window(dem_src, geometry)
            if window is None:
                print(f"warning: {slug} does not overlap PRISM DEM", file=sys.stderr)
                continue

            transform = dem_src.window_transform(window)
            dem_masked = dem_src.read(1, window=window, masked=True)
            dem_data, dem_nodata_mask = finite_data(dem_masked)
            inside_mask = geometry_mask(
                [geometry],
                out_shape=dem_data.shape,
                transform=transform,
                invert=True,
            )
            valid_dem = inside_mask & ~dem_nodata_mask & np.isfinite(dem_data)
            total_dem_cells = int(valid_dem.sum())
            if total_dem_cells == 0:
                print(f"warning: {slug} has no DEM cells", file=sys.stderr)
                continue

            dem_ft = dem_data * FT_PER_METER
            band_masks = {}
            for min_ft, max_ft in ELEVATION_BANDS:
                if max_ft is None:
                    band_masks[(min_ft, max_ft)] = valid_dem & (dem_ft >= min_ft)
                else:
                    band_masks[(min_ft, max_ft)] = valid_dem & (dem_ft >= min_ft) & (dem_ft < max_ft)

            for month in range(1, 13):
                with rasterio.open(tmin_paths[month]) as tmin_src:
                    tmin_masked = tmin_src.read(1, window=window, masked=True)
                    tmin_data, tmin_nodata_mask = finite_data(tmin_masked)
                    valid_tmin = ~tmin_nodata_mask & np.isfinite(tmin_data)

                for min_ft, max_ft in ELEVATION_BANDS:
                    band_dem_mask = band_masks[(min_ft, max_ft)]
                    band_dem_count = int(band_dem_mask.sum())
                    if band_dem_count == 0:
                        continue

                    value_mask = band_dem_mask & valid_tmin
                    values_c = tmin_data[value_mask]
                    if values_c.size == 0:
                        continue

                    values_f = fahrenheit(values_c)
                    area_pct = (band_dem_count / total_dem_cells) * 100.0
                    area_acres = gis_acres * (band_dem_count / total_dem_cells) if gis_acres else None
                    metadata = {
                        "dem_cell_count": total_dem_cells,
                        "band_dem_cell_count": band_dem_count,
                        "temperature_units_in_source": "C",
                        "elevation_units_in_source": "m",
                        "area_estimation": "forest_gis_acres_times_prism_dem_cell_fraction",
                    }

                    rows.append(
                        {
                            "land_unit_slug": slug,
                            "land_unit_name": name,
                            "climate_dataset_slug": DATASET_SLUG,
                            "month": month,
                            "elevation_min_ft": min_ft,
                            "elevation_max_ft": "" if max_ft is None else max_ft,
                            "elevation_band_label": band_label(min_ft, max_ft),
                            "mean_low_f": round(float(np.mean(values_f)), 2),
                            "cold_p10_low_f": round(float(np.percentile(values_f, 10)), 2),
                            "warm_p90_low_f": round(float(np.percentile(values_f, 90)), 2),
                            "sample_cell_count": int(values_f.size),
                            "area_acres": "" if area_acres is None else round(area_acres, 2),
                            "area_pct_of_forest": round(area_pct, 3),
                            "metadata_json": json.dumps(metadata, separators=(",", ":"), sort_keys=True),
                        }
                    )

    return sorted(rows, key=lambda row: (row["land_unit_slug"], int(row["month"]), int(row["elevation_min_ft"])))


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def write_manifest(path, args, downloads, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    boundary_path = Path(args.boundaries)
    manifest = {
        "dataset": {
            "slug": DATASET_SLUG,
            "name": "PRISM 1991-2020 Monthly Minimum Temperature Normals",
            "provider": "PRISM",
            "variable": "tmin",
            "normal_period_start_year": 1991,
            "normal_period_end_year": 2020,
            "spatial_resolution_m": 800,
            "source_url": PRISM_NORMALS_URL,
            "citation": "PRISM Climate Group, Oregon State University, https://prism.oregonstate.edu, data created 2025-01-30.",
            "metadata": {
                "temperature_statistic": "monthly average daily minimum temperature",
                "temperature_output_units": "F",
                "elevation_output_units": "ft",
                "elevation_source": "PRISM 800m DEM supporting dataset aligned to PRISM normals grid",
                "display_band_policy": {
                    "band_size_ft": 2000,
                    "hide_public_bands_below_sample_cells": 5,
                    "hide_public_bands_below_area_pct": 0.5,
                },
            },
        },
        "build": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "boundary_path": str(boundary_path),
            "boundary_sha256": sha256_file(boundary_path),
            "row_count": len(rows),
            "forest_count": len(set(row["land_unit_slug"] for row in rows)),
            "script": "scripts/climate/build_normals.py",
            "python": sys.version.split()[0],
            "rasterio": rasterio.__version__,
            "numpy": np.__version__,
        },
        "sources": {
            "prism_normals_page": PRISM_NORMALS_URL,
            "prism_tmin_base_url": PRISM_TMIN_BASE_URL,
            "prism_dem_url": PRISM_DEM_URL,
            "downloads": downloads,
        },
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")


def main():
    args = parse_args()
    cache_dir = Path(args.cache_dir)
    output_csv = Path(args.output_csv)
    output_manifest = Path(args.output_manifest)

    downloads = download_sources(cache_dir)
    features = load_boundaries(args.boundaries)
    rows = raster_rows(features, downloads)
    write_csv(output_csv, rows)
    write_manifest(output_manifest, args, downloads, rows)
    print(f"Wrote {len(rows)} climate normal rows to {output_csv}")
    print(f"Wrote manifest to {output_manifest}")


if __name__ == "__main__":
    main()
