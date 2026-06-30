(function () {
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

  function setupPlaceSearch(form) {
    var input = form.querySelector("[data-place-search-input]");
    var results = form.querySelector("[data-place-search-results]");
    var timer = null;

    if (!input || !results || typeof fetch === "undefined") return;

    function render(matches) {
      if (!matches.length) {
        results.hidden = true;
        results.innerHTML = "";
        return;
      }

      results.innerHTML = matches.map(function (result) {
        return [
          '<a class="place-search-result" href="',
          escapeHtml(result.url),
          '">',
          "<strong>",
          escapeHtml(result.name),
          "</strong>",
          "<span>",
          escapeHtml(result.subtitle || result.place_type),
          "</span>",
          "</a>"
        ].join("");
      }).join("");
      results.hidden = false;
    }

    function search() {
      var query = input.value.trim();

      if (query.length < 2) {
        render([]);
        return;
      }

      fetch("/api/places/search?q=" + encodeURIComponent(query) + "&limit=6")
        .then(function (response) {
          if (!response.ok) throw new Error("Place search failed");

          return response.json();
        })
        .then(function (data) {
          var matches = Array.isArray(data.results) ? data.results : data.places;

          render(Array.isArray(matches) ? matches : []);
        })
        .catch(function () {
          render([]);
        });
    }

    input.addEventListener("input", function () {
      clearTimeout(timer);
      timer = setTimeout(search, 140);
    });

    input.addEventListener("keydown", function (event) {
      var firstLink = results.querySelector("a");

      if (event.key === "ArrowDown" && firstLink) {
        event.preventDefault();
        firstLink.focus();
      }
    });

    document.addEventListener("click", function (event) {
      if (!form.contains(event.target)) results.hidden = true;
    });
  }

  function setupAllPlaceSearches() {
    Array.prototype.forEach.call(document.querySelectorAll("[data-place-search]"), setupPlaceSearch);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", setupAllPlaceSearches);
  } else {
    setupAllPlaceSearches();
  }
})();
