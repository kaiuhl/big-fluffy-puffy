(function () {
  var DEFAULT_FIT_MAX_ZOOM = 8;

  function normalize(value) {
    return value.toLowerCase().replace(/\s+/g, " ").trim();
  }

  function areaCount(count) {
    return count + " " + (count === 1 ? "area" : "areas");
  }

  function localizedRestrictionCount(count) {
    return count + " localized " + (count === 1 ? "restriction" : "restrictions");
  }

  function labelize(value) {
    return (value || "unknown").toString().replace(/_/g, " ").replace(/\b\w/g, function (character) {
      return character.toUpperCase();
    });
  }

  function escapeHtml(value) {
    return (value || "").toString().replace(/[&<>"']/g, function (character) {
      return {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        "\"": "&quot;",
        "'": "&#39;"
      }[character];
    });
  }

  function safeHttpUrl(value) {
    var url = (value || "").toString();

    return /^https?:\/\//i.test(url) ? url : "";
  }

  function formattedDate(value) {
    if (!value) return "not checked";

    var date = new Date(value);
    if (Number.isNaN(date.getTime())) return "checked";

    return date.toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      timeZone: "UTC",
      year: "numeric"
    });
  }

  function setSectionCount(section, visibleCount, totalCount, hasQuery) {
    var counter = section.querySelector(".restrictions-section-count");
    if (!counter) return;

    counter.textContent = hasQuery
      ? areaCount(visibleCount) + " of " + areaCount(totalCount)
      : areaCount(totalCount);
  }

  function setupFireRestrictionSearch() {
    var input = document.getElementById("restrictions-search");
    var status = document.getElementById("restrictions-filter-status");
    var sections = Array.prototype.slice.call(document.querySelectorAll(".restrictions-section"));

    if (!input || !status || sections.length === 0) return;

    var sectionState = sections.map(function (section) {
      var rows = Array.prototype.slice.call(section.querySelectorAll(".restrictions-table tbody tr"));
      var emptyMessage = section.querySelector(".restrictions-filter-empty");

      rows.forEach(function (row) {
        row.dataset.filterText = normalize(row.textContent || "");
      });

      return {
        section: section,
        rows: rows,
        emptyMessage: emptyMessage,
        total: rows.length
      };
    });

    function applyFilter() {
      var query = normalize(input.value);
      var hasQuery = query.length > 0;
      var visibleTotal = 0;

      sectionState.forEach(function (state) {
        var visibleCount = 0;

        state.rows.forEach(function (row) {
          var matches = !hasQuery || row.dataset.filterText.indexOf(query) !== -1;

          row.hidden = !matches;
          if (matches) visibleCount += 1;
        });

        visibleTotal += visibleCount;

        setSectionCount(state.section, visibleCount, state.total, hasQuery);

        if (state.emptyMessage) {
          state.emptyMessage.hidden = !hasQuery || visibleCount > 0;
        }

        state.section.hidden = hasQuery && visibleCount === 0;
      });

      status.textContent = hasQuery
        ? "Showing " + areaCount(visibleTotal) + " matching \"" + input.value.trim() + "\"."
        : "Showing " + areaCount(sectionState.reduce(function (sum, state) {
            return sum + state.total;
          }, 0)) + ".";
    }

    input.addEventListener("input", applyFilter);
    applyFilter();
  }

  function mapColor(status) {
    return {
      active: "#ff4b1f",
      boundary: "#3f5f52",
      destination: "#050505",
      forestwide_active: "#d92312",
      none: "#2f7f62",
      unknown: "#8b8b8b"
    }[status] || "#8b8b8b";
  }

  function mapStyle(feature) {
    var status = feature.properties && feature.properties.map_status;
    var color = mapColor(status);
    var forestwide = status === "forestwide_active";

    return {
      color: color,
      fillColor: color,
      fillOpacity: forestwide ? 0.46 : 0.56,
      fillRule: "nonzero",
      lineCap: "round",
      lineJoin: "round",
      opacity: 1,
      weight: forestwide ? 3 : 2
    };
  }

  function addBaseMap(map, baseMap) {
    if (baseMap === "osm") {
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
      }).addTo(map);
      return;
    }

    L.tileLayer("https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}", {
      maxZoom: 16,
      attribution: 'Tiles: <a href="https://www.usgs.gov/programs/national-geospatial-program/national-map">USGS The National Map</a>'
    }).addTo(map);
  }

  function fitZoomOffset(value) {
    var offset = parseInt(value || "0", 10);

    return Number.isNaN(offset) || offset < 1 ? 0 : offset;
  }

  function ringToLatLngs(ring) {
    return ring.map(function (coordinate) {
      return [coordinate[1], coordinate[0]];
    });
  }

  function isBoundaryFeature(feature) {
    return feature.properties && feature.properties.map_status === "boundary";
  }

  function isForestwideRestrictionFeature(feature) {
    return feature.properties && feature.properties.kind === "forestwide_restriction";
  }

  function isLocalizedRestrictionFeature(feature) {
    return feature.properties && feature.properties.kind === "localized_restriction";
  }

  function isTripCheckPlaceFeature(feature) {
    return feature.properties && feature.properties.kind === "trip_check_place";
  }

  function visibleMapFeatures(features) {
    return features.filter(function (feature) {
      return !isBoundaryFeature(feature);
    });
  }

  function localizedMapFeatures(features) {
    return features.filter(isLocalizedRestrictionFeature);
  }

  function forestwideRestrictionCount(features) {
    return features.filter(isForestwideRestrictionFeature).length;
  }

  function uniqueLocalizedRestrictionCount(features) {
    return Object.keys(localizedMapFeatures(features).reduce(function (seen, feature) {
      var properties = feature.properties || {};
      var key = properties.rule_slug || properties.slug;

      if (key) seen[key] = true;
      return seen;
    }, {})).length;
  }

  function forestwideRestrictionMappedMessage(count) {
    if (count === 0) return "";

    return count === 1
      ? "Forest-wide restriction mapped"
      : count + " forest-wide restrictions mapped";
  }

  function mapStatusMessage(container, features) {
    var visibleCount = container.dataset.mapStatusMode === "localized-restrictions"
      ? uniqueLocalizedRestrictionCount(features)
      : visibleMapFeatures(features).length;
    var forestwideCount = forestwideRestrictionCount(features);
    var forestwideMessage = forestwideRestrictionMappedMessage(forestwideCount);
    var totalRestrictions = parseInt(container.dataset.mapTotalRestrictions || "", 10);

    if (container.dataset.mapStatusMode === "localized-restrictions") {
      if (Number.isNaN(totalRestrictions)) {
        if (forestwideMessage) {
          return forestwideMessage + (
            visibleCount > 0 ? "; map showing " + localizedRestrictionCount(visibleCount) + "." : "."
          );
        }

        return "Map showing " + localizedRestrictionCount(visibleCount) + ".";
      }

      if (totalRestrictions === 0) {
        if (forestwideMessage) return forestwideMessage + ".";

        return "No localized restrictions mapped.";
      }

      if (forestwideMessage) {
        return forestwideMessage + "; " + localizedRestrictionCount(visibleCount) + " mapped of " + totalRestrictions + " total.";
      }

      return localizedRestrictionCount(visibleCount) + " mapped of " + totalRestrictions + " total.";
    }

    return "Map showing " + areaCount(visibleCount) + ".";
  }

  function focusMapOnWaypoint(map, container) {
    var latitude = parseFloat(container.dataset.mapFocusLat || "");
    var longitude = parseFloat(container.dataset.mapFocusLon || "");
    var zoom = parseInt(container.dataset.mapFocusZoom || "8", 10);

    if (Number.isNaN(latitude) || Number.isNaN(longitude)) return;

    map.setView([latitude, longitude], Number.isNaN(zoom) ? 8 : zoom, {
      animate: false
    });
  }

  function boundaryMaskHoles(features) {
    return features.reduce(function (holes, feature) {
      var geometry = feature.geometry || {};

      if (!isBoundaryFeature(feature)) return holes;

      if (geometry.type === "Polygon") {
        holes.push(ringToLatLngs(geometry.coordinates[0] || []));
      } else if (geometry.type === "MultiPolygon") {
        geometry.coordinates.forEach(function (polygon) {
          holes.push(ringToLatLngs(polygon[0] || []));
        });
      }

      return holes;
    }, []).filter(function (hole) {
      return hole.length >= 4;
    });
  }

  function addOutsideBoundaryMask(map, features) {
    var holes = boundaryMaskHoles(features);

    if (holes.length === 0) return;

    L.polygon(
      [
        [
          [-89.9, -360],
          [-89.9, 360],
          [89.9, 360],
          [89.9, -360]
        ]
      ].concat(holes),
      {
        fillColor: "#111111",
        fillOpacity: 0.66,
        fillRule: "evenodd",
        interactive: false,
        stroke: false
      }
    ).addTo(map);
  }

  function isInteractiveMapShape(target, container) {
    if (!target || target === container || typeof target.closest !== "function") return false;

    var interactiveTarget = target.closest(".leaflet-interactive");

    return !!(interactiveTarget && container.contains(interactiveTarget));
  }

  function enableShapeDoubleClickZoom(map, container) {
    container.addEventListener("dblclick", function (event) {
      if (!isInteractiveMapShape(event.target, container)) return;

      L.DomEvent.stop(event);
      zoomMapAround(map, map.mouseEventToLatLng(event), event);
    }, true);
  }

  function zoomMapAround(map, latlng, originalEvent) {
    var zoomDelta = map.options.zoomDelta || 1;
    var nextZoom = map.getZoom() + (originalEvent && originalEvent.shiftKey ? -zoomDelta : zoomDelta);

    map.setZoomAround(latlng, nextZoom);
  }

  function mapResizeIcon(expanded) {
    var paths = expanded
      ? '<path d="M4 14h6v6"></path><path d="M10 14l-7 7"></path><path d="M20 10h-6V4"></path><path d="M14 10l7-7"></path>'
      : '<path d="M15 3h6v6"></path><path d="M21 3l-7 7"></path><path d="M9 21H3v-6"></path><path d="M3 21l7-7"></path>';

    return [
      '<svg class="restrictions-map-size-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">',
      paths,
      "</svg>"
    ].join("");
  }

  function refreshMapSize(map) {
    var ticks = 0;

    function refresh() {
      map.invalidateSize({
        pan: false
      });

      ticks += 1;
      if (ticks < 4) setTimeout(refresh, 55);
    }

    afterLayout(refresh);
  }

  function addMapResizeControl(map, container) {
    var ResizeControl = L.Control.extend({
      options: {
        position: "bottomright"
      },

      onAdd: function () {
        var control = L.DomUtil.create("div", "leaflet-bar restrictions-map-size-control");
        var button = L.DomUtil.create("button", "restrictions-map-size-button", control);

        button.type = "button";
        button.innerHTML = '<span class="restrictions-map-size-icon" aria-hidden="true"></span>';

        function setExpanded(expanded) {
          container.classList.toggle("restrictions-map-expanded", expanded);
          button.innerHTML = mapResizeIcon(expanded);
          button.setAttribute("aria-label", expanded ? "Collapse map" : "Expand map");
          button.setAttribute("aria-pressed", expanded ? "true" : "false");
          button.title = expanded ? "Collapse map" : "Expand map";
          refreshMapSize(map);
        }

        setExpanded(false);

        L.DomEvent.disableClickPropagation(control);
        L.DomEvent.disableScrollPropagation(control);
        L.DomEvent.on(button, "click", function (event) {
          L.DomEvent.stop(event);
          setExpanded(!container.classList.contains("restrictions-map-expanded"));
        });

        return control;
      }
    });

    new ResizeControl().addTo(map);
  }

  function shapeRepeatedClickZoomHandler(map) {
    var lastClick = null;

    return function (event) {
      var originalEvent = event.originalEvent || {};
      var point = event.containerPoint;
      var now = Date.now();
      var repeatedClick = originalEvent.detail > 1;

      if (!repeatedClick && lastClick && point && lastClick.point) {
        repeatedClick = now - lastClick.time < 450 && point.distanceTo(lastClick.point) < 12;
      }

      lastClick = {
        point: point,
        time: now
      };

      if (!repeatedClick) return;

      lastClick = null;
      if (event.originalEvent && L.DomEvent) {
        L.DomEvent.stop(event.originalEvent);
      }
      zoomMapAround(map, event.latlng, originalEvent);
    };
  }

  function setupFireRestrictionMap() {
    var container = document.getElementById("restrictions-map");
    var status = document.getElementById("restrictions-map-status");

    if (!container) return;

    function setStatus(message) {
      if (status) status.textContent = message;
    }

    if (typeof L === "undefined" || typeof fetch === "undefined") {
      setStatus("Map unavailable; area list remains below.");
      return;
    }

    var map = L.map(container, {
      scrollWheelZoom: false
    }).setView([43.9, -121.9], 6);
    var zoomOffset = fitZoomOffset(container.dataset.mapFitZoomOffset);

    enableShapeDoubleClickZoom(map, container);
    addBaseMap(map, container.dataset.mapBasemap);
    addMapResizeControl(map, container);

    fetch(container.dataset.mapEndpoint || "/api/fire-restrictions/map")
      .then(function (response) {
        if (!response.ok) throw new Error("Map request failed");

        return response.json();
      })
      .then(function (data) {
        var features = Array.isArray(data.features) ? data.features : [];

        if (features.length === 0) {
          setStatus("Map boundaries unavailable; area list remains below.");
          return;
        }

        addOutsideBoundaryMask(map, features);

        var boundsLayer = L.geoJSON(data);
        var shapeClickZoom = shapeRepeatedClickZoomHandler(map);
        var layer = L.geoJSON(data, {
          filter: function (feature) {
            return !isBoundaryFeature(feature);
          },
          style: mapStyle,
          pointToLayer: function (feature, latlng) {
            if (!isTripCheckPlaceFeature(feature)) return L.marker(latlng);

            return L.marker(latlng, {
              icon: tripCheckWaypointIcon()
            });
          },
          onEachFeature: function (feature, featureLayer) {
            featureLayer.bindPopup(popupContent(feature.properties || {}));
            featureLayer.on({
              mouseover: function () {
                featureLayer.setStyle({
                  fillOpacity: 0.72,
                  weight: 3
                });
              },
              mouseout: function () {
                layer.resetStyle(featureLayer);
              },
              click: function (event) {
                shapeClickZoom(event);
              }
            });
          }
        }).addTo(map);

        fitMapToLayer(map, boundsLayer, zoomOffset, function () {
          focusMapOnWaypoint(map, container);
        });

        setStatus(mapStatusMessage(container, features));
      })
      .catch(function () {
        setStatus("Map unavailable; area list remains below.");
      });
  }

  function popupContent(properties) {
    if (properties.kind === "trip_check_place") return tripCheckPlacePopupContent(properties);

    var sourceUrl = safeHttpUrl(properties.source_url);
    var forestUrl = (properties.land_unit_url || properties.forest_url || "").toString();
    var sourceTitle = properties.source_title || "Source";
    var partName = properties.part_name || "";
    var title = partName || properties.name;
    var ruleContext = partName && properties.name
      ? '<p class="map-popup-rule">' + escapeHtml(properties.name) + "</p>"
      : "";
    var boundaryNote = properties.geometry_is_approximate
      ? "Approximation shown on map. Read official sources and signs for exact boundaries."
      : "";
    var restrictionDetail = properties.restriction_detail
      ? "<dt>Detail</dt><dd>" + escapeHtml(properties.restriction_detail) + "</dd>"
      : "";
    var geometryBasis = properties.geometry_basis
      ? "<dt>Mapped as</dt><dd>" + escapeHtml(properties.geometry_basis) + "</dd>"
      : "";
    var sourceLink = sourceUrl
      ? '<p class="map-popup-source"><a href="' + escapeHtml(sourceUrl) + '" rel="noreferrer">View ' + escapeHtml(sourceTitle) + "</a></p>"
      : "";
    var forestLink = /^\/fire-restrictions\/[^/]+$/i.test(forestUrl)
      ? '<p class="map-popup-source"><a href="' + escapeHtml(forestUrl) + '">Open area page</a></p>'
      : "";

    return [
      '<div class="map-popup">',
      "<strong>" + escapeHtml(title) + "</strong>",
      ruleContext,
      "<dl>",
      "<dt>Status</dt><dd>" + escapeHtml(properties.status_label || labelize(properties.map_status)) + "</dd>",
      "<dt>Campfires</dt><dd>" + escapeHtml(labelize(properties.campfire_policy)) + "</dd>",
      restrictionDetail,
      geometryBasis,
      boundaryNote ? "<dt>Boundary</dt><dd>" + escapeHtml(boundaryNote) + "</dd>" : "",
      "<dt>Checked</dt><dd>" + escapeHtml(properties.last_checked_label || formattedDate(properties.last_checked_at)) + "</dd>",
      "</dl>",
      forestLink,
      sourceLink,
      "</div>"
    ].join("");
  }

  function tripCheckWaypointIcon() {
    return L.divIcon({
      className: "trip-check-waypoint-icon",
      html: '<span class="trip-check-waypoint-ring"></span><span class="trip-check-waypoint-dot"></span>',
      iconAnchor: [14, 14],
      iconSize: [28, 28],
      popupAnchor: [0, -16]
    });
  }

  function tripCheckPlacePopupContent(properties) {
    var landUnitUrl = (properties.land_unit_url || properties.forest_url || "").toString();
    var landUnitLabel = properties.land_unit_name || properties.forest_name || "";
    var landUnitValue = /^\/fire-restrictions\/[^/]+$/i.test(landUnitUrl)
      ? '<a href="' + escapeHtml(landUnitUrl) + '">' + escapeHtml(landUnitLabel) + "</a>"
      : escapeHtml(landUnitLabel);
    var locationParts = [
      properties.county_name ? properties.county_name + " County" : "",
      properties.map_name ? properties.map_name + " USGS quad" : ""
    ].filter(Boolean);
    var location = locationParts.length
      ? '<p class="map-popup-place-meta">' + escapeHtml(locationParts.join(" / ")) + "</p>"
      : "";
    var forest = landUnitLabel
      ? '<p class="map-popup-place-forest">In ' + landUnitValue + "</p>"
      : "";

    return [
      '<div class="map-popup map-popup-place">',
      "<strong>" + escapeHtml(properties.name) + "</strong>",
      forest,
      location,
      "</div>"
    ].join("");
  }

  function afterLayout(callback) {
    if (typeof requestAnimationFrame !== "function") {
      setTimeout(callback, 0);
      return;
    }

    requestAnimationFrame(function () {
      requestAnimationFrame(callback);
    });
  }

  function fitMapToLayer(map, layer, zoomOffset, afterFit) {
    var bounds = layer.getBounds();
    var fitQueued = false;
    var attempts = 0;

    if (!bounds.isValid()) return;

    function fit() {
      fitQueued = false;

      map.invalidateSize({
        pan: false
      });

      var size = map.getSize();
      if (size.x === 0 || size.y === 0) {
        if (attempts < 5) {
          attempts += 1;
          setTimeout(queueFit, 60);
        }
        return;
      }

      attempts = 0;
      map.fitBounds(bounds, {
        animate: false,
        maxZoom: DEFAULT_FIT_MAX_ZOOM,
        padding: [18, 18]
      });
      zoomMapAfterFit(map, zoomOffset);
      if (typeof afterFit === "function") afterFit();
    }

    function queueFit() {
      if (fitQueued) return;

      fitQueued = true;
      afterLayout(fit);
    }

    queueFit();
    window.addEventListener("load", queueFit, {
      once: true
    });
    window.addEventListener("pageshow", queueFit);
    window.addEventListener("resize", queueFit);
  }

  function zoomMapAfterFit(map, zoomOffset) {
    if (!zoomOffset) return;

    var currentZoom = map.getZoom();
    var mapMaxZoom = map.getMaxZoom();

    if (typeof mapMaxZoom !== "number") {
      mapMaxZoom = DEFAULT_FIT_MAX_ZOOM;
    }

    var targetZoom = Math.min(
      currentZoom + zoomOffset,
      DEFAULT_FIT_MAX_ZOOM,
      mapMaxZoom
    );

    if (targetZoom > currentZoom) {
      map.setZoom(targetZoom, {
        animate: false
      });
    }
  }

  function setupFireRestrictionsPage() {
    setupFireRestrictionSearch();
    setupFireRestrictionMap();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", setupFireRestrictionsPage);
  } else {
    setupFireRestrictionsPage();
  }
})();
