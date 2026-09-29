/* ==========================================================================
   HOCCO PM TOOL — seed data
   One dataset shared by every prototype screen, so the story stays
   consistent across the two user-testing tasks (spec §11).

   "Today" is 11 Aug 2026.
   Hero initiative: Mango Kulfi 750ml — the CEO's where-is-it-stuck task.
   ========================================================================== */

window.HOCCO = (function () {

  var TODAY = "11 Aug 2026";

  /* ---- Portfolio: all 30 concurrent initiatives (spec §6) ----------------
     band: "risk" | "pending" | "ontrack"
     reason: plain-language, never a bare red dot (spec §7). Never truncated.
  ------------------------------------------------------------------------ */
  var initiatives = [
    /* At Risk — ranked by launch-proximity × lateness */
    { id: "belgian-dark",  name: "Belgian Dark 90ml Bar",     type: "NPD",                brand: "B",      launch: "18 Aug", band: "risk",    reason: "Launch in 7 days, Codes/BOM track still incomplete", state: "Overdue",  late: 4 },
    { id: "trade-price",   name: "Trade Price Revision Q3",   type: "Price revision",     brand: "Shared", launch: "18 Aug", band: "risk",    reason: "Blocked 6 days at Finance approval",                  state: "Blocked",  late: 6 },
    { id: "cone-sleeve",   name: "Cone Sleeve Refresh",       type: "Packaging redesign", brand: "A",      launch: "22 Aug", band: "risk",    reason: "2nd revision — upstream requirement changed",         state: "Rework",   late: 3 },
    { id: "festive-pack",  name: "Festive Gift Pack",         type: "Packaging redesign", brand: "B",      launch: "28 Aug", band: "risk",    reason: "Blocked 9 days at Procurement, unacknowledged",       state: "Disputed", late: 9 },
    { id: "tender-coco",   name: "Tender Coconut",            type: "Seasonal (FOM)",     brand: "A",      launch: "5 Sep",  band: "risk",    reason: "Stale 14 days — no update on Recipe Sign-off",        state: "Stale",    late: 14 },
    { id: "mango-kulfi",   name: "Mango Kulfi 750ml",         type: "NPD",                brand: "A",      launch: "14 Sep", band: "risk",    reason: "3rd revision, 2× same reason at Artwork Approval",   state: "Blocked",  late: 9, hero: true },

    /* Awaiting Prioritisation — open creation is safe because priority gates
       resourcing; these sit here until the CEO places them (spec §5) */
    { id: "jamun",         name: "Jamun Sorbet Trial",        type: "NPD",                brand: "A",      launch: "—", band: "pending", reason: "Created 3 days ago by R&D · no launch date set",     state: "Awaiting" },
    { id: "litchi-w2",     name: "Litchi FOM Wave 2",         type: "Seasonal (FOM)",     brand: "B",      launch: "—", band: "pending", reason: "Created 6 days ago by Marketing",                     state: "Awaiting" },
    { id: "fam-pack-vol",  name: "1L Family Pack Volume",     type: "Volume update",      brand: "Shared", launch: "—", band: "pending", reason: "Created 8 days ago by Supply Chain",                  state: "Awaiting" },
    { id: "kesar-relabel", name: "Kesar Pista Tub Relabel",   type: "Packaging redesign", brand: "A",      launch: "—", band: "pending", reason: "Created 12 days ago by Production",                   state: "Awaiting" },

    /* On Track — quiet. Present but recessive (spec §3: quiet when healthy) */
    { id: "mrp-100",       name: "MRP Revision — 100ml Cups", type: "Price revision", brand: "A",      launch: "25 Aug", band: "ontrack", reason: "At Finance approval · on schedule",                 state: "On track" },
    { id: "cone-120",      name: "Volume Update — Cone 120ml", type: "Volume update", brand: "B",      launch: "29 Aug", band: "ontrack", reason: "Production sign-off pending",                        state: "On track" },
    { id: "inst-price",    name: "Institutional Price List",  type: "Price revision",     brand: "Shared", launch: "1 Sep",  band: "ontrack", reason: "Awaiting CEO approval",                              state: "On track" },
    { id: "bulk-5l",       name: "Bulk Pack 5L Volume",       type: "Volume update",      brand: "B",      launch: "3 Sep",  band: "ontrack", reason: "BOM update in progress",                             state: "On track" },
    { id: "distrib-slab",  name: "Distributor Slab Revision", type: "Price revision",     brand: "Shared", launch: "5 Sep",  band: "ontrack", reason: "Finance modelling in progress",                      state: "On track" },
    { id: "pista-4l",      name: "Pista Badam 4L Party Pack", type: "Volume update",      brand: "A",      launch: "12 Sep", band: "ontrack", reason: "Packaging artwork approved",                         state: "On track" },
    { id: "sitaphal",      name: "Sitaphal FOM",              type: "Seasonal (FOM)",     brand: "B",      launch: "12 Sep", band: "ontrack", reason: "Campaign brief in progress",                         state: "On track" },
    { id: "modular-lid",   name: "Modular Tub Lid",           type: "Packaging redesign", brand: "Shared", launch: "15 Sep", band: "ontrack", reason: "Vendor mockup approved 1st pass",                    state: "On track" },
    { id: "guava-chilli",  name: "Guava Chilli FOM",          type: "Seasonal (FOM)",     brand: "A",      launch: "18 Sep", band: "ontrack", reason: "Recipe locked · packaging started",                 state: "On track" },
    { id: "label-comp",    name: "Label Compliance Refresh",  type: "Packaging redesign", brand: "B",      launch: "20 Sep", band: "ontrack", reason: "Statutory review with QC",                           state: "On track" },
    { id: "filter-coffee", name: "Filter Coffee FOM",         type: "Seasonal (FOM)",     brand: "A",      launch: "25 Sep", band: "ontrack", reason: "Recipe trials underway",                             state: "On track" },
    { id: "multipack",     name: "Multipack Carton Update",   type: "Packaging redesign", brand: "A",      launch: "26 Sep", band: "ontrack", reason: "Structural sample approved",                         state: "On track" },
    { id: "kesar-1l",      name: "Kesar Pista 1L",            type: "NPD",                brand: "A",      launch: "30 Sep", band: "ontrack", reason: "All four tracks progressing",                        state: "On track" },
    { id: "rose-falooda",  name: "Rose Falooda FOM",          type: "Seasonal (FOM)",     brand: "B",      launch: "2 Oct",  band: "ontrack", reason: "Concept approved",                                   state: "On track" },
    { id: "shipper",       name: "Corrugated Shipper Redesign", type: "Packaging redesign", brand: "Shared", launch: "8 Oct", band: "ontrack", reason: "Costing with Procurement",                          state: "On track" },
    { id: "choco-chip",    name: "Choco Chip 500ml",          type: "NPD",                brand: "A",      launch: "15 Oct", band: "ontrack", reason: "Recipe track at trial batch 2",                      state: "On track" },
    { id: "almond-bar",    name: "Roasted Almond Bar",        type: "NPD",                brand: "B",      launch: "20 Oct", band: "ontrack", reason: "Recipe track in R&D",                                state: "On track" },
    { id: "malai-stick",   name: "Malai Kulfi Stick",         type: "NPD",                brand: "B",      launch: "5 Nov",  band: "ontrack", reason: "Kicked off · all tracks queued",                    state: "On track" },
    { id: "cookie-cream",  name: "Cookie Cream Sandwich",     type: "NPD",                brand: "B",      launch: "22 Nov", band: "ontrack", reason: "Concept stage",                                      state: "On track" },
    { id: "sugarfree",     name: "Sugar-Free Vanilla",        type: "NPD",                brand: "A",      launch: "30 Nov", band: "ontrack", reason: "Concept stage",                                      state: "On track" }
  ];

  /* ---- Priority — CEO-set, a computed ordering derived from launch date
     (spec §5). Not self-assigned. Pending items carry NO priority: they wait
     in Awaiting Prioritisation until the CEO places them, which is the whole
     safety valve for open creation. -------------------------------------- */
  var MONTH_IDX = { Aug: 0, Sep: 1, Oct: 2, Nov: 3 };
  function launchScore(l) {
    if (!l || l === "—") return 999;
    var p = l.split(" ");
    return MONTH_IDX[p[1]] * 31 + parseInt(p[0], 10);
  }
  initiatives.forEach(function (i) {
    if (i.band === "pending") { i.priority = "Awaiting"; return; }
    var s = launchScore(i.launch);
    /* At-risk work is urgent by definition; otherwise nearer launch = higher. */
    i.priority = i.band === "risk" ? "High"
               : (s <= 40 ? "High" : (s <= 60 ? "Medium" : "Low"));
  });

  /* Launch health for the Calendar — three distinct signals the spec's palette
     can express without a bare colour: on-track / delayed / blocked. Blocked
     points at an unblocking action; delayed is late but moving; the two must
     not collapse into one dot. */
  function launchStatus(i) {
    if (i.state === "Blocked" || i.state === "Disputed") return "blocked";
    if (i.band === "risk") return "delayed";
    return "ontrack";
  }

  /* Lookups so a task or a blocker can resolve its parent initiative's
     brand / category / priority for filtering. */
  var byId = {}, byName = {};
  initiatives.forEach(function (i) { byId[i.id] = i; byName[i.name] = i; });

  var categories = [];
  initiatives.forEach(function (i) { if (categories.indexOf(i.type) < 0) categories.push(i.type); });
  categories.sort();

  /* ---- Departments tab: capacity vs process (spec §7) --------------------
     Load per department across BOTH brands. Never individual behaviour.
  ------------------------------------------------------------------------ */
  var departments = [
    { name: "Marketing",    working: 4, queued: 3, blocked: 1 },
    { name: "Supply Chain", working: 5, queued: 4, blocked: 0 },
    { name: "Procurement",  working: 2, queued: 6, blocked: 2 },
    { name: "Finance",      working: 3, queued: 1, blocked: 1 },
    { name: "R&D",          working: 4, queued: 2, blocked: 0 },
    { name: "Production",   working: 3, queued: 2, blocked: 0 },
    { name: "QC",           working: 2, queued: 5, blocked: 1 }
  ];

  /* ---- My Work: the rep's home (spec §7) --------------------------------
     Signed in as a Marketing representative.
     Three zones, ordered by urgency — the triage is done FOR the user.
  ------------------------------------------------------------------------ */
  var me = { name: "Aarti Shah", dept: "Marketing", initials: "AS" };

  var myWork = {
    /* Zone 1 — actionable now, launch-date-ranked. Full visual weight. */
    now: [
      { id: "s-artwork",  title: "Artwork v4 — resubmit to vendor", initiative: "Mango Kulfi 750ml", init_id: "mango-kulfi",
        tier: "surface", due: "Due today", reason: "Gate rejected 3rd time · 2× same reason", chips: [["risk","Rework"]],
        stale: null },
      { id: "s-keyvis",   title: "Approve final key visual", initiative: "Festive Gift Pack", init_id: "festive-pack",
        tier: "present", due: "Due 13 Aug", reason: "Vendor delivered v2 yesterday", chips: [],
        stale: "No update in 3 days" },
      { id: "s-tradecom", title: "Trade communication draft", initiative: "Trade Price Revision Q3", init_id: "trade-price",
        tier: "present", due: "Due 14 Aug", reason: "Needs final MRP before send", chips: [], stale: null },
      { id: "s-brief",    title: "Campaign brief", initiative: "Sitaphal FOM", init_id: "sitaphal",
        tier: "present", due: "Due 18 Aug", reason: "", chips: [], stale: null },
      { id: "s-cover",    title: "Vendor PO follow-up", initiative: "Cone Sleeve Refresh", init_id: "cone-sleeve",
        tier: "present", due: "Due 15 Aug", reason: "", chips: [["queued","Covering for Rohit"]], stale: null }
    ],
    /* Zone 2 — the anti-blame zone. Each names WHO and HOW LONG. */
    waiting: [
      { id: "w-quote", title: "Vendor quote for POS units", initiative: "Festive Gift Pack", init_id: "festive-pack",
        tier: "surface", who: "Procurement", days: 9, note: "Blocker not acknowledged — escalates to both HODs tomorrow" },
      { id: "w-mrp",   title: "Final MRP figure", initiative: "Trade Price Revision Q3", init_id: "trade-price",
        tier: "present", who: "Finance", days: 6, note: "" },
      { id: "w-copy",  title: "Pack copy statutory sign-off", initiative: "Tender Coconut", init_id: "tender-coco",
        tier: "present", who: "QC", days: 4, note: "" }
    ],
    /* Zone 3 — not yet actionable. Recessive, collapsed by default. */
    upcoming: [
      { id: "u-teaser", title: "Launch teaser plan",        initiative: "Kesar Pista 1L",          when: "Opens 2 Sep" },
      { id: "u-infl",   title: "Influencer brief",          initiative: "Guava Chilli FOM",        when: "Opens 25 Aug" },
      { id: "u-strip",  title: "Retail shelf strip artwork", initiative: "Multipack Carton Update", when: "Opens 30 Aug" },
      { id: "u-photo",  title: "Menu photography",          initiative: "Filter Coffee FOM",       when: "Opens 8 Sep" }
    ]
  };

  /* ---- Mango Kulfi 750ml — the initiative under the microscope ---------- */
  var mangoKulfi = {
    id: "mango-kulfi",
    name: "Mango Kulfi 750ml",
    type: "NPD",
    brand: "A",
    owner: "Rohit Desai · Supply Chain",
    launch: "14 Sep 2026",
    started: "9 Jul 2026",
    elapsed: 33,
    late: 9,

    /* Delay breakdown — the most persuasive artefact (spec §7).
       Turns "33 days in and late" into a pointer at a process step. */
    breakdown: { working: 11, waiting: 16, blocked: 6 },

    /* Four parallel tracks. Blocked one expanded by default on mobile. */
    tracks: [
      {
        id: "recipe", name: "Recipe", dept: "R&D", state: "done",
        summary: "5 of 5 stages complete · signed off 4 Aug",
        strip: [ {t:"seg",k:"done"}, {t:"seg",k:"done"}, {t:"gate",k:"passed"}, {t:"seg",k:"done"}, {t:"seg",k:"done"}, {t:"gate",k:"passed"} ],
        stages: [
          { name: "Concept & benchmark",   who: "R&D",        state: "done", note: "Closed 16 Jul" },
          { name: "Trial batch 1",         who: "R&D",        state: "done", note: "Closed 23 Jul" },
          { name: "Sensory panel",         who: "QC",         state: "done", note: "Closed 29 Jul" },
          { name: "Trial batch 2",         who: "R&D",        state: "done", note: "Closed 2 Aug" },
          { name: "Recipe sign-off",       who: "R&D + QC",   state: "done", note: "Closed 4 Aug — spec revised at sign-off" }
        ],
        deps: []
      },
      {
        id: "packaging", name: "Packaging", dept: "Marketing", state: "blocked",
        summary: "Stuck at Artwork Approval · 3rd revision",
        strip: [ {t:"seg",k:"done"}, {t:"seg",k:"done"}, {t:"gate",k:"passed"}, {t:"seg",k:"blocked"}, {t:"gate",k:"failed",rev:3}, {t:"seg",k:""} ],
        stages: [
          { name: "Structural spec",       who: "Supply Chain", state: "done",    note: "Closed 18 Jul" },
          { name: "Key visual",            who: "Marketing",    state: "done",    note: "Closed 21 Jul" },
          { name: "Artwork production",    who: "Marketing",    state: "blocked", note: "Rejected 3× · v4 due today" },
          { name: "Vendor proof",          who: "Procurement",  state: "queued",  note: "Cannot start until artwork approved" }
        ],
        /* Critical dependency of a blocked stage — shown BY DEFAULT.
           Troubled initiatives surface their own diagnosis (spec §3, §7). */
        deps: [
          { critical: true, text: "Blocks → Codes/BOM cannot finalise pack codes until artwork is approved. 6 days lost so far." }
        ],
        gate: {
          name: "Artwork Approval",
          revisions: 3,
          repeatFlag: true,
          upstreamFlag: true,
          history: [
            { rev: 1, date: "22 Jul", by: "Rohit Desai · Supply Chain", reason: "Statutory declarations incorrect", note: "FSSAI licence block missing on rear panel", flags: [] },
            { rev: 2, date: "30 Jul", by: "Rohit Desai · Supply Chain", reason: "Statutory declarations incorrect", note: "Licence block added but net-weight placement still non-compliant", flags: ["repeat"] },
            { rev: 3, date: "6 Aug",  by: "Meera Iyer · QC",           reason: "Nutritional panel mismatch",     note: "Panel reflects pre-revision recipe", flags: ["upstream"] }
          ]
        }
      },
      {
        id: "codes", name: "Codes / BOM", dept: "Supply Chain", state: "queued",
        summary: "Queued behind Packaging · waiting 6 days",
        strip: [ {t:"seg",k:"done"}, {t:"seg",k:"wait"}, {t:"gate",k:"pending"}, {t:"seg",k:""}, {t:"seg",k:""} ],
        stages: [
          { name: "SKU creation",          who: "Supply Chain", state: "done",   note: "Closed 25 Jul" },
          { name: "BOM finalisation",      who: "Supply Chain", state: "queued", note: "Waiting on approved artwork" },
          { name: "Costing sign-off",      who: "Finance",      state: "queued", note: "Not yet actionable" }
        ],
        deps: [
          { critical: false, text: "Depends on → Packaging · Artwork Approval" }
        ]
      },
      {
        id: "procurement", name: "Procurement", dept: "Procurement", state: "working",
        summary: "Laminate sourcing in progress · on schedule",
        strip: [ {t:"seg",k:"done"}, {t:"seg",k:"active"}, {t:"gate",k:"pending"}, {t:"seg",k:""} ],
        stages: [
          { name: "Vendor shortlist",      who: "Procurement", state: "done",    note: "Closed 28 Jul" },
          { name: "Laminate sourcing",     who: "Procurement", state: "working", note: "In progress · 2 quotes received" },
          { name: "PO release",            who: "Procurement", state: "queued",  note: "After artwork approval" }
        ],
        deps: []
      }
    ]
  };

  /* ---- Blockers screen: open claims + disputes (neutral ground) ---------- */
  var blockers = [
    { id: "b-pos",   title: "Vendor quote for POS units", initiative: "Festive Gift Pack", raisedBy: "Marketing", against: "Procurement",
      days: 9, state: "disputed", note: "Claim not acknowledged · auto-escalates to both HODs in 1 day" },
    { id: "b-fin",   title: "Final MRP figure",           initiative: "Trade Price Revision Q3", raisedBy: "Marketing", against: "Finance",
      days: 6, state: "open",     note: "Acknowledged 5 Aug by Finance" },
    { id: "b-art",   title: "Artwork Approval loop",      initiative: "Mango Kulfi 750ml", raisedBy: "Marketing", against: "QC",
      days: 6, state: "open",     note: "Acknowledged · nutritional panel depends on revised recipe spec" },
    { id: "b-lam",   title: "Laminate lead time",         initiative: "Belgian Dark 90ml Bar", raisedBy: "Production", against: "Procurement",
      days: 3, state: "open",     note: "Acknowledged 8 Aug" }
  ];

  /* ---- Controlled picklist for raising a blocker (spec §5) --------------
     Fast to give, or people won't give it. */
  var blockerReasons = [
    "Waiting on an input from another department",
    "Vendor / external party delay",
    "Approval pending longer than expected",
    "Requirement changed upstream",
    "Capacity — my team is on other priorities",
    "Missing information or unclear spec"
  ];

  /* ---- Template shapes (spec §6) --------------------------------------
     Creating an initiative instantiates the whole dependency graph, so every
     one of the 30 has tracks — not just the modelled hero. These are the five
     v1 templates; the detail screen composes a graph from them for any
     initiative that isn't hand-modelled.
  ---------------------------------------------------------------------- */
  var TEMPLATES = {
    "NPD": [
      { name: "Recipe",      dept: "R&D",          stages: ["Concept & benchmark", "Trial batch 1", "Sensory panel", "Trial batch 2", "Recipe sign-off"], gateAfter: [2, 4] },
      { name: "Packaging",   dept: "Marketing",    stages: ["Structural spec", "Key visual", "Artwork production", "Vendor proof"],                      gateAfter: [2] },
      { name: "Codes / BOM", dept: "Supply Chain", stages: ["SKU creation", "BOM finalisation", "Costing sign-off"],                                     gateAfter: [1] },
      { name: "Procurement", dept: "Procurement",  stages: ["Vendor shortlist", "Material sourcing", "PO release"],                                      gateAfter: [1] }
    ],
    "Seasonal (FOM)": [
      { name: "Recipe",    dept: "R&D",       stages: ["Flavour concept", "Trial batch", "Recipe sign-off"],            gateAfter: [1] },
      { name: "Campaign",  dept: "Marketing", stages: ["Campaign brief", "Key visual", "Channel plan", "Go-live"],      gateAfter: [1] },
      { name: "Packaging", dept: "Marketing", stages: ["Artwork adaptation", "Vendor proof"],                            gateAfter: [0] }
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

  /* Compose a viewable initiative from the template + its portfolio state.
     The hero returns its fully hand-modelled graph (gate history and all). */
  function getInitiative(id) {
    if (!id || id === mangoKulfi.id) return mangoKulfi;

    var init = null;
    initiatives.forEach(function (i) { if (i.id === id) init = i; });
    if (!init) return mangoKulfi;

    var shape = TEMPLATES[init.type] || TEMPLATES["Packaging redesign"];

    /* How far along, by band. Awaiting-prioritisation work hasn't started —
       nothing is resourced until the CEO places it (spec §5). */
    var progress = init.band === "pending" ? 0 : (init.band === "risk" ? 0.55 : 0.45);
    var blockedTrack = init.band === "risk" ? Math.min(1, shape.length - 1) : -1;

    var tracks = shape.map(function (t, ti) {
      var done = Math.floor(t.stages.length * progress);
      var blocked = ti === blockedTrack;
      var state = init.band === "pending" ? "queued"
                : blocked ? "blocked"
                : (done >= t.stages.length ? "done" : "working");

      var stages = t.stages.map(function (name, si) {
        var st = si < done ? "done"
               : (blocked && si === done) ? "blocked"
               : si === done ? (init.band === "pending" ? "queued" : "working")
               : "queued";
        return {
          name: name, who: t.dept, state: st,
          note: st === "done"    ? "Closed"
              : st === "blocked" ? init.reason
              : st === "working" ? "In progress"
              : "Not yet actionable"
        };
      });

      /* Strip: a segment per stage, a gate diamond after the flagged ones. */
      var strip = [];
      t.stages.forEach(function (_, si) {
        var k = si < done ? "done" : (blocked && si === done) ? "blocked"
              : si === done && init.band !== "pending" ? "active" : "";
        strip.push({ t: "seg", k: k });
        if (t.gateAfter.indexOf(si) > -1) {
          strip.push({ t: "gate", k: si < done ? "passed" : (blocked ? "failed" : "pending") });
        }
      });

      return {
        id: t.name.toLowerCase().replace(/[^a-z]+/g, "-"),
        name: t.name, dept: t.dept, state: state,
        summary: init.band === "pending" ? "Not started — awaiting prioritisation"
               : blocked ? init.reason
               : state === "done" ? "All stages complete"
               : done + " of " + t.stages.length + " stages complete",
        strip: strip,
        stages: stages,
        deps: blocked && shape.length > 1
          ? [{ critical: true, text: "Blocks → downstream tracks cannot close until this clears." }]
          : (ti > 0 && shape.length > 1
              ? [{ critical: false, text: "Depends on → " + shape[0].name }]
              : []),
        gate: null   /* only the hero carries a full rejection history */
      };
    });

    var late = init.late || 0;
    return {
      id: init.id, name: init.name, type: init.type, brand: init.brand,
      owner: init.type === "NPD" ? "Rohit Desai · Supply Chain" : shape[0].dept + " lead",
      launch: init.launch === "—" ? "Not set" : init.launch + " 2026",
      elapsed: init.band === "pending" ? 0 : 12 + late,
      late: late,
      reason: init.reason,
      state: init.state,
      band: init.band,
      synthesized: true,
      breakdown: init.band === "pending"
        ? { working: 0, waiting: 0, blocked: 0 }
        : { working: 12, waiting: Math.max(2, late), blocked: init.band === "risk" ? Math.ceil(late / 2) : 0 },
      tracks: tracks
    };
  }

  return {
    today: TODAY,
    me: me,
    templates: TEMPLATES,
    getInitiative: getInitiative,
    launchStatus: launchStatus,
    categories: categories,
    byId: byId,
    byName: byName,
    initiatives: initiatives,
    departments: departments,
    myWork: myWork,
    mangoKulfi: mangoKulfi,
    blockers: blockers,
    blockerReasons: blockerReasons,
    counts: function () {
      var c = { risk: 0, pending: 0, ontrack: 0 };
      initiatives.forEach(function (i) { c[i.band]++; });
      return c;
    }
  };
})();
