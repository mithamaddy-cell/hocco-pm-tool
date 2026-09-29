/* ==========================================================================
   HOCCO PM TOOL — shared UI helpers
   Small, deliberately un-clever. This is a prototype for user testing,
   not an application shell.
   ========================================================================== */

window.UI = (function () {

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  /* Brand is an ATTRIBUTE, not a workspace (spec §4).
     Always paired with a text label — never colour alone. */
  function brandChip(brand) {
    /* Neutral, not indigo — the type tag next to it is indigo, and two
       identical tags side by side read as one repeated thing. */
    if (brand === "Shared") return '<span class="chip chip--queued">Both brands</span>';
    var cls = brand === "A" ? "chip--brand-a" : "chip--brand-b";
    return '<span class="chip ' + cls + '">Brand ' + esc(brand) + "</span>";
  }

  /* State chips. The class sets colour; the text sets meaning.
     Greyscale-safe by construction. */
  var STATE_CHIP = {
    "Blocked":  "risk",  "Overdue": "risk",  "Stale": "risk",
    "Rework":   "risk",  "Disputed": "risk",
    "Awaiting": "pending",
    "On track": "ok",
    "Queued":   "queued",
    "Waiting":  "wait",
    "Approved": "news",  "Launched": "news"
  };

  function stateChip(state) {
    var k = STATE_CHIP[state] || "queued";
    var icon = (k === "risk") ? "▲ " : "";
    return '<span class="chip chip--' + k + '">' + icon + esc(state) + "</span>";
  }

  /* Bottom bar — Portfolio (landing) · My Work · Blockers · New.
     (Settings stays folded into the user menu.) */
  function bottomNav(active, badge) {
    var items = [
      { key: "portfolio", label: "Portfolio", icon: "▦", href: "hocco-portfolio-mobile.html" },
      { key: "mywork",    label: "My Work",   icon: "◈", href: "hocco-mywork-mobile.html" },
      { key: "blockers",  label: "Blockers",  icon: "▲", href: "hocco-blockers-mobile.html" },
      { key: "new",       label: "New",       icon: "＋", href: "hocco-new-initiative.html" }
    ];
    return '<nav class="bottomnav">' + items.map(function (i) {
      var cur = i.key === active ? ' aria-current="page"' : "";
      var b = (i.key === "blockers" && badge) ? '<span class="navitem__badge">' + badge + "</span>" : "";
      return '<a class="navitem" href="' + i.href + '"' + cur + ">" + b +
             '<span class="navitem__icon" aria-hidden="true">' + i.icon + "</span>" +
             "<span>" + i.label + "</span></a>";
    }).join("") + "</nav>";
  }

  /* Bottom sheet controller — status change lives in the thumb zone (spec §9) */
  function sheet(id) {
    var el = document.getElementById(id);
    var scrim = document.getElementById(id + "-scrim");
    var lastFocus = null;

    function open() {
      lastFocus = document.activeElement;
      el.setAttribute("data-open", "true");
      scrim.setAttribute("data-open", "true");
      el.removeAttribute("aria-hidden");
      document.body.style.overflow = "hidden";
      var f = el.querySelector("button, [href], input, select, textarea");
      if (f) f.focus();
    }
    function close() {
      el.setAttribute("data-open", "false");
      scrim.setAttribute("data-open", "false");
      el.setAttribute("aria-hidden", "true");
      document.body.style.overflow = "";
      if (lastFocus) lastFocus.focus();
    }
    scrim.addEventListener("click", close);
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && el.getAttribute("data-open") === "true") close();
    });
    return { open: open, close: close, el: el };
  }

  /* Toast — used for the "Done settles" and "blocker raised" confirmations.
     Motion is spent only where it means something (spec §8). */
  function toast(msg) {
    var t = document.createElement("div");
    t.className = "toast glass-strong";
    t.setAttribute("role", "status");
    t.innerHTML = msg;
    document.body.appendChild(t);
    requestAnimationFrame(function () { t.setAttribute("data-in", "true"); });
    setTimeout(function () {
      t.setAttribute("data-in", "false");
      setTimeout(function () { t.remove(); }, 300);
    }, 2600);
  }

  /* ---- Filter control (spec: sort the list easily) ----------------------
     One reusable trigger + bottom sheet, shared by every list screen. Three
     facets — brand, category, priority — each single-select with an "All"
     default. Filters apply live so the count updates as you tap; the sheet is
     in the thumb zone like every other choice in the app (spec §9).

     The trigger and its options are CONTROLS, so they use the outlined-pill
     button shape — never the flat tag shape, which is reserved for labels. */
  var _filterSeq = 0;
  function filters(mountEl, onChange) {
    var D = window.HOCCO;
    var state = { brand: "all", category: "all", priority: "all" };
    /* Unique id — a screen may mount more than one filter (e.g. Portfolio's
       Calendar and Initiatives tabs), and two #filter-sheet nodes would fight. */
    var uid = "filter-" + (++_filterSeq);

    var FACETS = [
      { key: "brand", label: "Brand",
        opts: [["all", "All brands"], ["A", "Brand A"], ["B", "Brand B"], ["Shared", "Both brands"]] },
      { key: "category", label: "Category",
        opts: [["all", "All categories"]].concat(D.categories.map(function (c) { return [c, c]; })) },
      { key: "priority", label: "Priority",
        opts: [["all", "All priorities"], ["High", "High"], ["Medium", "Medium"], ["Low", "Low"], ["Awaiting", "Awaiting"]] }
    ];

    /* Build the sheet once, appended to <body>. */
    var scrim = document.createElement("div");
    scrim.className = "scrim"; scrim.id = uid + "-scrim";
    var sh = document.createElement("div");
    sh.className = "sheet"; sh.id = uid;
    sh.setAttribute("role", "dialog"); sh.setAttribute("aria-modal", "true");
    sh.setAttribute("aria-label", "Filter list"); sh.setAttribute("aria-hidden", "true");
    sh.setAttribute("data-open", "false");
    document.body.appendChild(scrim); document.body.appendChild(sh);
    var ctl = sheet(uid);

    function facetHTML(f) {
      return '<div class="fgroup"><div class="fgroup__label">' + esc(f.label) + "</div>" +
        '<div class="fopts">' + f.opts.map(function (o) {
          var on = state[f.key] === o[0];
          return '<button class="fopt' + (on ? " fopt--on" : "") + '" data-facet="' + f.key +
                 '" data-val="' + esc(o[0]) + '"' + (on ? ' aria-pressed="true"' : "") + ">" +
                 esc(o[1]) + "</button>";
        }).join("") + "</div></div>";
    }

    function renderSheet(count) {
      sh.innerHTML =
        '<div class="sheet__grip" aria-hidden="true"></div>' +
        '<h2 class="sheet__h">Filter</h2>' +
        '<p class="sheet__ctx filter-count"></p>' +
        FACETS.map(facetHTML).join("") +
        '<button class="btn btn--primary btn--block" id="filter-done" style="margin-top:var(--s2)">' +
          'Show ' + count + ' result' + (count === 1 ? "" : "s") + "</button>" +
        '<button class="btn btn--ghost btn--block" id="filter-clear" style="margin-top:var(--s2)">Clear all</button>';
    }

    function activeCount() {
      var n = 0; ["brand", "category", "priority"].forEach(function (k) { if (state[k] !== "all") n++; });
      return n;
    }

    function label(key, val) {
      for (var i = 0; i < FACETS.length; i++) {
        if (FACETS[i].key === key) {
          for (var j = 0; j < FACETS[i].opts.length; j++)
            if (FACETS[i].opts[j][0] === val) return FACETS[i].opts[j][1];
        }
      }
      return val;
    }

    /* The bar: a trigger button, then a removable pill per active facet. */
    function renderBar() {
      var n = activeCount();
      var pills = ["brand", "category", "priority"].filter(function (k) { return state[k] !== "all"; })
        .map(function (k) {
          return '<button class="filterpill" data-clear="' + k + '">' +
                 esc(label(k, state[k])) + ' <span aria-hidden="true">×</span></button>';
        }).join("");
      mountEl.innerHTML =
        '<button class="filterbtn' + (n ? " filterbtn--active" : "") + '" id="filter-open" aria-haspopup="dialog">' +
          '<span aria-hidden="true">⇅</span> Filter' + (n ? ' <span class="filterbtn__n">' + n + "</span>" : "") +
        "</button>" +
        pills +
        (n ? '<button class="filterbar__clear" data-clear="all">Clear</button>' : "");
    }

    function emit() { renderBar(); if (onChange) onChange(match); }

    /* The predicate every screen applies to its own items. */
    function match(item) {
      if (!item) return true;
      if (state.brand !== "all" && item.brand !== state.brand) return false;
      if (state.category !== "all" && item.type !== state.category) return false;
      if (state.priority !== "all" && item.priority !== state.priority) return false;
      return true;
    }

    /* Count matches against the full initiative set, for the sheet's CTA. */
    function resultCount() {
      var n = 0;
      D.initiatives.forEach(function (i) { if (match(i)) n++; });
      return n;
    }

    mountEl.addEventListener("click", function (e) {
      var open = e.target.closest("#filter-open");
      if (open) { renderSheet(resultCount()); ctl.open(); return; }
      var clr = e.target.closest("[data-clear]");
      if (clr) {
        var k = clr.dataset.clear;
        if (k === "all") state = { brand: "all", category: "all", priority: "all" };
        else state[k] = "all";
        emit();
      }
    });

    sh.addEventListener("click", function (e) {
      var opt = e.target.closest("[data-facet]");
      if (opt) {
        state[opt.dataset.facet] = opt.dataset.val;
        renderSheet(resultCount());
        var cc = sh.querySelector(".filter-count");
        if (cc) cc.textContent = activeCount() ? activeCount() + " filter" + (activeCount() > 1 ? "s" : "") + " applied" : "Showing everything";
        emit();      /* live — the list updates behind the sheet */
        return;
      }
      if (e.target.closest("#filter-done")) { ctl.close(); return; }
      if (e.target.closest("#filter-clear")) {
        state = { brand: "all", category: "all", priority: "all" };
        renderSheet(resultCount()); emit(); return;
      }
    });

    renderBar();
    return { match: match, state: function () { return state; } };
  }

  return {
    esc: esc, brandChip: brandChip, stateChip: stateChip, bottomNav: bottomNav,
    sheet: sheet, toast: toast, filters: filters
  };
})();
