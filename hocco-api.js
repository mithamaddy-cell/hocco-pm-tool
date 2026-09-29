/* ==========================================================================
   HOCCO PM TOOL — data from Supabase
   Loads the database and returns the SAME shapes hocco-data.js provides, so
   screens change minimally. Needs, in this order:
     <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
     <script src="hocco-config.js"></script>
     <script src="hocco-api.js"></script>

   HoccoAPI.load() → Promise of { today, initiatives, departments, blockers,
   categories, byId, byName, launchStatus, counts }. Also sets window.HOCCO,
   which hocco-ui.js (filters) reads.

   Band and reason are CALCULATED here, never typed by hand:
     pending — priority is empty (awaiting the CEO)
     risk    — a disputed or open blocker, a blocked stage, a gate rejected and
               not yet passed, a stale stage, or launch expected later than planned
     ontrack — none of the above
   The reason line states the most serious signal, in plain words.
   ========================================================================== */

window.HoccoAPI = (function () {

  var STALE_DAYS = 7;
  var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

  function client() {
    var cfg = window.HOCCO_CONFIG || {};
    if (!window.supabase || !window.supabase.createClient) {
      throw new Error("The database library didn't load. Check the internet connection.");
    }
    if (!cfg.supabaseUrl || !cfg.supabaseKey || /PASTE_/.test(cfg.supabaseKey)) {
      throw new Error("The database key hasn't been added to hocco-config.js yet.");
    }
    return window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey);
  }

  /* ---- Dates -------------------------------------------------------------- */
  function todayDate() {
    var t = (window.HOCCO_CONFIG || {}).today;
    return t ? parseDate(t) : new Date(new Date().toDateString());
  }
  function parseDate(s) {                       /* "2026-08-18" → local midnight */
    var p = String(s).split("-");
    return new Date(+p[0], +p[1] - 1, +p[2]);
  }
  function daysBetween(from, to) { return Math.round((to - from) / 86400000); }
  function shortDate(s) {                       /* "2026-08-18" → "18 Aug" */
    if (!s) return "—";
    var d = parseDate(s);
    return d.getDate() + " " + MONTHS[d.getMonth()];
  }
  function longDate(d) { return d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear(); }
  function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s"); }
  function ordinal(n) {
    var s = ["th", "st", "nd", "rd"], v = n % 100;
    return n + (s[(v - 20) % 10] || s[v] || s[0]);
  }

  /* ---- Signals, most serious first. Each returns {state, reason} or null.
     `ctx` holds this initiative's stages, gates, blockers and dept names. --- */
  var SIGNALS = [

    /* 1. A disputed blocker — the claim itself is contested. */
    function (i, ctx) {
      var b = ctx.blockers.filter(function (b) { return b.status === "disputed"; })[0];
      if (!b) return null;
      return { state: "Disputed",
               reason: "Blocked " + plural(b.days, "day") + " at " + ctx.dept(b.against_department_id) + ", disputed" };
    },

    /* 2. A blocked stage. If its track's gate has been rejected, say so. */
    function (i, ctx) {
      var s = ctx.stages.filter(function (s) { return s.status === "blocked"; })[0];
      if (!s) return null;
      var g = ctx.gates.filter(function (g) { return g.track_id === s.track_id && g.status === "failed"; })[0];
      if (g) return { state: "Blocked", reason: gateReason(g) };
      return { state: "Blocked", reason: "Blocked at " + s.name + " (" + ctx.dept(s.department_id) + ")" };
    },

    /* 3. A gate rejected and not yet passed. */
    function (i, ctx) {
      var g = ctx.gates.filter(function (g) { return g.status === "failed"; })[0];
      if (!g) return null;
      return { state: "Rework", reason: gateReason(g) };
    },

    /* 4. A stale stage — in progress but no update for STALE_DAYS or more. */
    function (i, ctx) {
      var worst = null;
      ctx.stages.forEach(function (s) {
        if ((s.status === "working" || s.status === "blocked") && s.last_update_on) {
          var d = daysBetween(parseDate(s.last_update_on), ctx.today);
          if (d >= STALE_DAYS && (!worst || d > worst.d)) worst = { s: s, d: d };
        }
      });
      if (!worst) return null;
      return { state: "Stale", reason: "Stale " + plural(worst.d, "day") + " — no update on " + worst.s.name };
    },

    /* 5. An open or acknowledged blocker. */
    function (i, ctx) {
      var b = ctx.blockers.filter(function (b) { return b.status === "open" || b.status === "acknowledged"; })
                          .sort(function (a, b) { return b.days - a.days; })[0];
      if (!b) return null;
      return { state: "Blocked",
               reason: "Blocked " + plural(b.days, "day") + " at " + ctx.dept(b.against_department_id) +
                       (b.status === "open" ? ", not yet acknowledged" : "") };
    },

    /* 6. Launch expected later than planned. */
    function (i) {
      if (!(i.late_days > 0)) return null;
      return { state: "Overdue",
               reason: "Launch expected " + plural(i.late_days, "day") + " later than planned" };
    }
  ];

  /* "3rd revision, 2× same reason at Artwork Approval" */
  function gateReason(g) {
    var rejections = g.reviews.filter(function (r) { return r.outcome === "rejected"; });
    var n = rejections.length;
    var repeats = rejections.filter(function (r) { return (r.flags || []).indexOf("repeat") > -1; }).length;
    if (!n) return "Rejected at " + g.name;
    return ordinal(n) + " revision" + (repeats ? ", " + (repeats + 1) + "× same reason" : "") + " at " + g.name;
  }

  /* ---- Load everything ---------------------------------------------------- */
  function load() {
    var sb;
    try { sb = client(); } catch (e) { return Promise.reject(e); }

    function q(table, cols) {
      return sb.from(table).select(cols).then(function (res) {
        if (res.error) throw new Error("Couldn't read " + table + ": " + res.error.message);
        return res.data;
      });
    }

    return Promise.all([
      q("initiatives",  "id, slug, name, type, brand_code, priority, launch_on, late_days"),
      q("departments",  "id, name, sort_order"),
      q("tracks",       "id, initiative_id"),
      q("stages",       "id, track_id, name, department_id, second_department_id, status, last_update_on"),
      q("gates",        "id, track_id, name, status"),
      q("gate_reviews", "gate_id, revision, outcome, flags"),
      q("blockers",     "id, initiative_id, title, raised_by_department_id, against_department_id, status, raised_on, note")
    ]).then(function (r) {
      return build({ initiatives: r[0], departments: r[1], tracks: r[2], stages: r[3],
                     gates: r[4], reviews: r[5], blockers: r[6] });
    });
  }

  function build(db) {
    var today = todayDate();
    var deptName = {};
    db.departments.forEach(function (d) { deptName[d.id] = d.name; });
    function dept(id) { return deptName[id] || id; }

    var trackInit = {};
    db.tracks.forEach(function (t) { trackInit[t.id] = t.initiative_id; });

    function group(list, keyFn) {
      var m = {};
      list.forEach(function (x) { var k = keyFn(x); (m[k] = m[k] || []).push(x); });
      return m;
    }
    var reviewsByGate = group(db.reviews, function (r) { return r.gate_id; });
    db.gates.forEach(function (g) {
      g.reviews = (reviewsByGate[g.id] || []).sort(function (a, b) { return a.revision - b.revision; });
    });
    db.blockers.forEach(function (b) { b.days = Math.max(0, daysBetween(parseDate(b.raised_on), today)); });

    var stagesByInit   = group(db.stages,   function (s) { return trackInit[s.track_id]; });
    var gatesByInit    = group(db.gates,    function (g) { return trackInit[g.track_id]; });
    var blockersByInit = group(db.blockers.filter(function (b) { return b.status !== "resolved"; }),
                               function (b) { return b.initiative_id; });

    /* Initiatives in the shape the screens expect. */
    var initiatives = db.initiatives.map(function (row) {
      var ctx = {
        today: today, dept: dept,
        stages:   stagesByInit[row.id]   || [],
        gates:    gatesByInit[row.id]    || [],
        blockers: blockersByInit[row.id] || []
      };
      var out = {
        id: row.slug, name: row.name, type: row.type, brand: row.brand_code,
        launch: shortDate(row.launch_on), late: row.late_days || 0,
        _launchOn: row.launch_on
      };

      if (!row.priority) {
        out.band = "pending"; out.state = "Awaiting"; out.priority = "Awaiting";
        out.reason = "Awaiting prioritisation" + (row.launch_on ? "" : " · no launch date set");
        return out;
      }
      out.priority = row.priority;
      for (var k = 0; k < SIGNALS.length; k++) {
        var hit = SIGNALS[k](row, ctx);
        if (hit) { out.band = "risk"; out.state = hit.state; out.reason = hit.reason; return out; }
      }
      out.band = "ontrack"; out.state = "On track"; out.reason = "No blockers, rejections or delays";
      return out;
    });

    /* Ranked: at-risk first by launch date, then everything else by launch date. */
    initiatives.sort(function (a, b) {
      if (!a._launchOn || !b._launchOn) return a._launchOn ? -1 : (b._launchOn ? 1 : a.name.localeCompare(b.name));
      return a._launchOn < b._launchOn ? -1 : a._launchOn > b._launchOn ? 1 : a.name.localeCompare(b.name);
    });

    /* Departments tab: count of open stages by state, per department.
       Load only — never a per-person or per-department "delay score". */
    var departments = db.departments
      .filter(function (d) { return d.id !== "leadership"; })
      .sort(function (a, b) { return a.sort_order - b.sort_order; })
      .map(function (d) {
        var c = { name: d.name, working: 0, queued: 0, blocked: 0 };
        db.stages.forEach(function (s) {
          if (s.department_id !== d.id && s.second_department_id !== d.id) return;
          if (s.status === "working") c.working++;
          else if (s.status === "queued") c.queued++;
          else if (s.status === "blocked") c.blocked++;
        });
        return c;
      });

    /* Blockers in the Blockers-screen shape (used now for the nav badge). */
    var byUuid = {};
    db.initiatives.forEach(function (i) { byUuid[i.id] = i; });
    var blockers = db.blockers.filter(function (b) { return b.status !== "resolved"; }).map(function (b) {
      return {
        id: b.id, title: b.title, initiative: (byUuid[b.initiative_id] || {}).name,
        raisedBy: dept(b.raised_by_department_id), against: dept(b.against_department_id),
        days: b.days, state: b.status === "disputed" ? "disputed" : "open", note: b.note || ""
      };
    });

    var byId = {}, byName = {}, categories = [];
    initiatives.forEach(function (i) {
      byId[i.id] = i; byName[i.name] = i;
      if (categories.indexOf(i.type) < 0) categories.push(i.type);
    });
    categories.sort();

    var data = {
      today: longDate(today),
      initiatives: initiatives,
      departments: departments,
      blockers: blockers,
      categories: categories,
      byId: byId,
      byName: byName,
      launchStatus: function (i) {
        if (i.state === "Blocked" || i.state === "Disputed") return "blocked";
        if (i.band === "risk") return "delayed";
        return "ontrack";
      },
      counts: function () {
        var c = { risk: 0, pending: 0, ontrack: 0 };
        initiatives.forEach(function (i) { c[i.band]++; });
        return c;
      }
    };
    window.HOCCO = data;
    return data;
  }

  return { load: load };
})();
