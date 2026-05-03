FROM ghcr.io/osgeo/gdal:ubuntu-small-3.10.3

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential python3-dev python3-pip python3-venv \
  && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/climate-venv

ENV PATH="/opt/climate-venv/bin:${PATH}"

RUN pip install --upgrade pip \
  && pip install \
  numpy==2.1.3 \
  pyproj==3.7.0 \
  rasterio==1.4.3 \
  shapely==2.0.6

WORKDIR /work

ENTRYPOINT ["/opt/climate-venv/bin/python", "scripts/climate/build_normals.py"]
