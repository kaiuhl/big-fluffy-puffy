(function () {
  function normalize(value) {
    return value.toLowerCase().replace(/\s+/g, " ").trim();
  }

  function forestCount(count) {
    return count + " " + (count === 1 ? "forest" : "forests");
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
      year: "numeric"
    });
  }

  function setSectionCount(section, visibleCount, totalCount, hasQuery) {
    var counter = section.querySelector(".restrictions-section-count");
    if (!counter) return;

    counter.textContent = hasQuery
      ? forestCount(visibleCount) + " of " + forestCount(totalCount)
      : forestCount(totalCount);
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
        ? "Showing " + forestCount(visibleTotal) + " matching \"" + input.value.trim() + "\"."
        : "Showing " + forestCount(sectionState.reduce(function (sum, state) {
            return sum + state.total;
          }, 0)) + ".";
    }

    input.addEventListener("input", applyFilter);
    applyFilter();
  }

  function mapColor(status) {
    return {
      active: "#ff4b1f",
      none: "#2f7f62",
      unknown: "#8b8b8b"
    }[status] || "#8b8b8b";
  }

  function popupContent(properties) {
    var sourceUrl = safeHttpUrl(properties.source_url);
    var sourceTitle = properties.source_title || "Source";
    var sourceLink = sourceUrl
      ? '<p class="map-popup-source"><a href="' + escapeHtml(sourceUrl) + '" rel="noreferrer">View ' + escapeHtml(sourceTitle) + "</a></p>"
      : "";

    return [
      '<div class="map-popup">',
      "<strong>" + escapeHtml(properties.name) + "</strong>",
      "<dl>",
      "<dt>Status</dt><dd>" + escapeHtml(labelize(properties.map_status)) + "</dd>",
      "<dt>Campfires</dt><dd>" + escapeHtml(labelize(properties.campfire_policy)) + "</dd>",
      "<dt>Checked</dt><dd>" + escapeHtml(formattedDate(properties.last_checked_at)) + "</dd>",
      "</dl>",
      sourceLink,
      "</div>"
    ].join("");
  }

  function setupFireRestrictionMap() {
    var container = document.getElementById("restrictions-map");
    var status = document.getElementById("restrictions-map-status");

    if (!container) return;

    function setStatus(message) {
      if (status) status.textContent = message;
    }

    if (typeof L === "undefined" || typeof fetch === "undefined") {
      setStatus("Map unavailable; forest list remains below.");
      return;
    }

    var map = L.map(container, {
      scrollWheelZoom: false
    }).setView([43.9, -121.9], 6);

    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 12,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(map);

    fetch(container.dataset.mapEndpoint || "/api/fire-restrictions/map")
      .then(function (response) {
        if (!response.ok) throw new Error("Map request failed");

        return response.json();
      })
      .then(function (data) {
        var features = Array.isArray(data.features) ? data.features : [];

        if (features.length === 0) {
          setStatus("Map boundaries unavailable; forest list remains below.");
          return;
        }

        var layer = L.geoJSON(data, {
          style: function (feature) {
            var color = mapColor(feature.properties && feature.properties.map_status);

            return {
              color: color,
              fillColor: color,
              fillOpacity: 0.56,
              opacity: 1,
              weight: 2
            };
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
              }
            });
          }
        }).addTo(map);

        var bounds = layer.getBounds();
        if (bounds.isValid()) {
          map.fitBounds(bounds, {
            padding: [18, 18]
          });
        }

        setStatus("Map showing " + forestCount(features.length) + ".");
      })
      .catch(function () {
        setStatus("Map unavailable; forest list remains below.");
      });
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
