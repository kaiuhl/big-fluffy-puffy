#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
import rasterio
from rasterio.transform import from_origin

import build_normals


class BuildNormalsTest(unittest.TestCase):
    def test_raster_rows_aggregate_by_elevation_band(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            dem_path = tmp_path / "dem.tif"
            tmin_paths = {}
            transform = from_origin(0, 4, 1, 1)

            dem_m = np.array(
                [
                    [100, 100, 800, 800],
                    [100, 100, 800, 800],
                    [1400, 1400, 2000, 2000],
                    [1400, 1400, 2000, 2000],
                ],
                dtype="float32",
            )
            tmin_c = np.array(
                [
                    [0, 0, 5, 5],
                    [0, 0, 5, 5],
                    [10, 10, 15, 15],
                    [10, 10, 15, 15],
                ],
                dtype="float32",
            )

            write_raster(dem_path, dem_m, transform)
            for month in range(1, 13):
                path = tmp_path / f"tmin_{month}.tif"
                write_raster(path, tmin_c, transform)
                tmin_paths[str(month)] = {"raster_path": str(path)}

            features = load_fixture_features()
            rows = build_normals.raster_rows(
                features,
                {
                    "dem": {"raster_path": str(dem_path)},
                    "tmin": tmin_paths,
                },
            )

            may_rows = [row for row in rows if row["month"] == 5]
            self.assertEqual(len(rows), 48)
            self.assertEqual([row["elevation_band_label"] for row in may_rows], [
                "0-2,000 ft",
                "2,000-4,000 ft",
                "4,000-6,000 ft",
                "6,000-8,000 ft",
            ])
            self.assertEqual([row["mean_low_f"] for row in may_rows], [32.0, 41.0, 50.0, 59.0])
            self.assertEqual([row["sample_cell_count"] for row in may_rows], [4, 4, 4, 4])
            self.assertEqual([row["area_pct_of_forest"] for row in may_rows], [25.0, 25.0, 25.0, 25.0])


def write_raster(path, values, transform):
    with rasterio.open(
        path,
        "w",
        driver="GTiff",
        height=values.shape[0],
        width=values.shape[1],
        count=1,
        dtype=values.dtype,
        crs="EPSG:4326",
        transform=transform,
        nodata=-9999,
    ) as dataset:
        dataset.write(values, 1)


def load_fixture_features():
    path = Path("spec/fixtures/climate/synthetic_boundaries.geojson")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)["features"]


if __name__ == "__main__":
    unittest.main()
