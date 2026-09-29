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
      q("initiatives",  "id, slug, name, type, brand_code, owner_department_id, priority, launch_on, late_days, started_on, created_at, days_working, days_waiting, days_blocked"),
      q("departments",  "id, name, sort_order"),
      q("tracks",       "id, initiative_id, slug, name, department_id, position, status, summary"),
      q("stages",       "id, track_id, name, position, department_id, second_department_id, status, note, closed_on, last_update_on"),
      q("gates",        "id, track_id, name, after_stage_position, status"),
      q("gate_reviews", "gate_id, revision, outcome, reviewer_department_id, reason, note, flags, reviewed_on"),
      q("blockers",     "id, initiative_id, title, raised_by_department_id, against_department_id, status, raised_on, note"),
      q("track_dependencies", "blocking_track_id, blocked_track_id, critical, note")
    ]).then(function (r) {
      return build({ initiatives: r[0], departments: r[1], tracks: r[2], stages: r[3],
                     gates: r[4], reviews: r[5], blockers: r[6], deps: r[7] });
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

    /* ---- One initiative in the Initiative Detail shape ------------------- */
    var rowBySlug = {};
    db.initiatives.forEach(function (i) { rowBySlug[i.slug] = i; });
    var tracksByInit = group(db.tracks, function (t) { return t.initiative_id; });
    var stagesByTrack = group(db.stages, function (s) { return s.track_id; });
    var gatesByTrack = group(db.gates, function (g) { return g.track_id; });
    var trackById = {};
    db.tracks.forEach(function (t) { trackById[t.id] = t; });

    function getInitiative(slug) {
      var row = rowBySlug[slug], summary = byId[slug];
      if (!row || !summary) return null;
      var tracks = (tracksByInit[row.id] || []).sort(function (a, b) { return a.position - b.position; });
      if (!tracks.length) return synthesize(row, summary, dept, today);

      var started = row.started_on ? parseDate(row.started_on) : null;
      var stuck = null, events = [];

      if (started) events.push({ d: row.started_on, k: "good", t: "Initiative created", s: "Work started" });

      var outTracks = tracks.map(function (t) {
        var stages = (stagesByTrack[t.id] || []).sort(function (a, b) { return a.position - b.position; });
        var gates = gatesByTrack[t.id] || [];
        var incoming = db.deps.filter(function (d) { return d.blocked_track_id === t.id; });
        var outgoing = db.deps.filter(function (d) { return d.blocking_track_id === t.id; });
        var firstOpen = stages.filter(function (s) { return s.status !== "done"; })[0];

        /* Progress strip: a segment per stage, a gate after the flagged stages. */
        var strip = [];
        stages.forEach(function (s) {
          var k = s.status === "done" ? "done" : s.status === "blocked" ? "blocked"
                : s.status === "working" ? "active"
                : (s === firstOpen && incoming.length ? "wait" : "");
          strip.push({ t: "seg", k: k });
          gates.forEach(function (g) {
            if (g.after_stage_position !== s.position) return;
            var rej = g.reviews.filter(function (r) { return r.outcome === "rejected"; }).length;
            strip.push({ t: "gate", k: g.status, rev: g.status === "failed" && rej ? rej : undefined });
          });
        });

        /* Gate card: only for a gate that has been rejected and not passed. */
        var failed = gates.filter(function (g) { return g.status === "failed"; })[0];
        var gate = null;
        if (failed) {
          var rejections = failed.reviews.filter(function (r) { return r.outcome === "rejected"; });
          var repeats = rejections.filter(function (r) { return (r.flags || []).indexOf("repeat") > -1; }).length;
          gate = {
            name: failed.name, revisions: rejections.length,
            repeatFlag: repeats > 0,
            upstreamFlag: rejections.some(function (r) { return (r.flags || []).indexOf("upstream") > -1; }),
            history: rejections.map(function (r) {
              return { rev: r.revision, date: shortDate(r.reviewed_on), by: dept(r.reviewer_department_id),
                       reason: r.reason || "", note: r.note || "", flags: r.flags || [] };
            })
          };
          if (t.status === "blocked" && !stuck) {
            stuck = { track: t.name, gate: failed.name, revisions: rejections.length, sameReason: repeats ? repeats + 1 : 0 };
          }
        }

        /* Timeline events from real dates. */
        stages.forEach(function (s) {
          if (s.closed_on) {
            /* The date is shown already — keep only what the note adds. */
            var extra = (s.note || "").replace(/^Closed \d+ \w+\s*(—\s*)?/, "");
            events.push({ d: s.closed_on, k: "good", t: s.name + " closed", s: t.name + (extra ? " · " + extra : "") });
          }
        });
        gates.forEach(function (g) {
          g.reviews.forEach(function (r) {
            var flags = (r.flags || []).map(function (f) {
              return f === "repeat" ? "Same reason as rev " + (r.revision - 1) + " · flagged" : "Upstream-caused";
            });
            events.push({
              d: r.reviewed_on, k: r.outcome === "rejected" ? "bad" : "good",
              t: g.name + " " + r.outcome + " — rev " + r.revision,
              s: [r.reason].concat(flags).filter(Boolean).join(" · ")
            });
          });
        });

        var deps = outgoing.map(function (d) {
          return { critical: d.critical, text: "Blocks → " + (d.note || (trackById[d.blocked_track_id] || {}).name) };
        }).concat(incoming.map(function (d) {
          var from = trackById[d.blocking_track_id] || {};
          var fg = (gatesByTrack[from.id] || []).filter(function (g) { return g.status !== "passed"; })[0];
          return { critical: false, text: "Depends on → " + from.name + (fg ? " · " + fg.name : "") };
        }));

        return {
          id: t.slug, name: t.name, dept: dept(t.department_id), state: t.status,
          summary: t.summary || "", strip: strip, deps: deps, gate: gate,
          stages: stages.map(function (s) {
            return { name: s.name,
                     who: dept(s.department_id) + (s.second_department_id ? " + " + dept(s.second_department_id) : ""),
                     state: s.status, note: s.note || "" };
          })
        };
      });

      /* What's open right now closes the timeline. */
      db.stages.forEach(function (s) {
        if (trackInit[s.track_id] === row.id && s.status === "blocked") {
          events.push({ d: null, k: "", t: s.name + " — " + (s.note || "blocked"),
                        s: (trackById[s.track_id] || {}).name + " · blocked now" });
        }
      });
      events.sort(function (a, b) { return !a.d ? 1 : !b.d ? -1 : (a.d < b.d ? -1 : a.d > b.d ? 1 : 0); });

      var late = row.late_days || 0;
      var projected = null;
      if (row.launch_on && late) {
        var p = parseDate(row.launch_on); p.setDate(p.getDate() + late);
        projected = p.getDate() + " " + MONTHS[p.getMonth()];
      }

      return {
        id: slug, name: row.name, type: row.type, brand: row.brand_code,
        owner: dept(row.owner_department_id),
        launch: row.launch_on ? longDate(parseDate(row.launch_on)) : "Not set",
        elapsed: started ? daysBetween(started, today) : 0,
        late: late,
        reason: summary.reason, state: summary.state, band: summary.band,
        stuck: stuck, projected: projected,
        breakdown: { working: row.days_working || 0, waiting: row.days_waiting || 0, blocked: row.days_blocked || 0 },
        timeline: events.map(function (e) { return { k: e.k, d: e.d ? shortDate(e.d) : "Today", t: e.t, s: e.s }; }),
        blockers: (blockersByInit[row.id] || []).map(function (b) {
          return { title: b.title, against: dept(b.against_department_id), days: b.days, status: b.status };
        }),
        tracks: outTracks
      };
    }

    var data = {
      today: longDate(today),
      getInitiative: getInitiative,
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

  /* ---- Template fallback --------------------------------------------------
     Only Mango Kulfi has its tracks in the database so far. Any other
     initiative is drawn from its template (same as the prototype), marked
     synthesized: true, until its real tracks are added. */
  var TEMPLATES = {
    "NPD": [
      { name: "Recipe",      dept: "R&D",          stages: ["Concept & benchmark", "Trial batch 1", "Sensory panel", "Trial batch 2", "Recipe sign-off"], gateAfter: [2, 4] },
      { name: "Packaging",   dept: "Marketing",    stages: ["Structural spec", "Key visual", "Artwork production", "Vendor proof"],                      gateAfter: [2] },
      { name: "Codes / BOM", dept: "Supply Chain", stages: ["SKU creation", "BOM finalisation", "Costing sign-off"],                                     gateAfter: [1] },
      { name: "Procurement", dept: "Procurement",  stages: ["Vendor shortlist", "Material sourcing", "PO release"],                                      gateAfter: [1] }
    ],
    "Seasonal (FOM)": [
      { name: "Recipe",    dept: "R&D",       stages: ["Flavour concept", "Trial batch", "Recipe sign-off"],       gateAfter: [1] },
      { name: "Campaign",  dept: "Marketing", stages: ["Campaign brief", "Key visual", "Channel plan", "Go-live"], gateAfter: [1] },
      { name: "Packaging", dept: "Marketing", stages: ["Artwork adaptation", "Vendor proof"],                       gateAfter: [0] }
    ],
    "Packaging redesign": [
      { name: "Packaging", dept: "Marketing", stages: ["Structural spec", "Key visual", "Artwork production", "Vendor proof", "Print release"], gateAfter: [2] }
    ],
    "Price revision": [
      { name: "Approval chain", dept: "Finance", stages: ["Costing input", "Finance review", "CEO approval", "Trade communication"], gateAfter: [1, 2] }
    ],
    "Volume update": [
      { name: "Approval chain", dept: "Supply Chain", stages: ["Pack spec change", "BOM update", "Costing sign-off", "Production release"], gateAfter: [1, 2] }
    ]
  };

  function synthesize(row, init, dept, today) {
    var shape = TEMPLATES[init.type] || TEMPLATES["Packaging redesign"];
    var pending = init.band === "pending";
    var progress = pending ? 0 : (init.band === "risk" ? 0.55 : 0.45);
    var blockedTrack = init.band === "risk" ? Math.min(1, shape.length - 1) : -1;

    var tracks = shape.map(function (t, ti) {
      var done = Math.floor(t.stages.length * progress);
      var blocked = ti === blockedTrack;
      var state = pending ? "queued" : blocked ? "blocked" : (done >= t.stages.length ? "done" : "working");
      var stages = t.stages.map(function (name, si) {
        var st = si < done ? "done" : (blocked && si === done) ? "blocked"
               : si === done ? (pending ? "queued" : "working") : "queued";
        return { name: name, who: t.dept, state: st,
                 note: st === "done" ? "Closed" : st === "blocked" ? init.reason
                     : st === "working" ? "In progress" : "Not yet actionable" };
      });
      var strip = [];
      t.stages.forEach(function (_, si) {
        var k = si < done ? "done" : (blocked && si === done) ? "blocked" : si === done && !pending ? "active" : "";
        strip.push({ t: "seg", k: k });
        if (t.gateAfter.indexOf(si) > -1) {
          strip.push({ t: "gate", k: si < done ? "passed" : (blocked ? "failed" : "pending") });
        }
      });
      return {
        id: t.name.toLowerCase().replace(/[^a-z]+/g, "-"), name: t.name, dept: t.dept, state: state,
        summary: pending ? "Not started — awaiting prioritisation" : blocked ? init.reason
               : state === "done" ? "All stages complete" : done + " of " + t.stages.length + " stages complete",
        strip: strip, stages: stages,
        deps: blocked && shape.length > 1
          ? [{ critical: true, text: "Blocks → downstream tracks cannot close until this clears." }]
          : (ti > 0 && shape.length > 1 ? [{ critical: false, text: "Depends on → " + shape[0].name }] : []),
        gate: null
      };
    });

    var late = init.late || 0;
    return {
      id: init.id, name: init.name, type: init.type, brand: init.brand,
      owner: dept(row.owner_department_id),
      launch: init.launch === "—" ? "Not set" : init.launch + " " + today.getFullYear(),
      elapsed: pending ? 0 : 12 + late,
      late: late, reason: init.reason, state: init.state, band: init.band,
      synthesized: true,
      breakdown: pending ? { working: 0, waiting: 0, blocked: 0 }
                         : { working: 12, waiting: Math.max(2, late), blocked: init.band === "risk" ? Math.ceil(late / 2) : 0 },
      tracks: tracks
    };
  }

  return { load: load };
})();
