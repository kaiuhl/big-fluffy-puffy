(function () {
  function normalize(value) {
    return value.toLowerCase().replace(/\s+/g, " ").trim();
  }

  function forestCount(count) {
    return count + " " + (count === 1 ? "forest" : "forests");
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

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", setupFireRestrictionSearch);
  } else {
    setupFireRestrictionSearch();
  }
})();
