-- ==========================================================================
-- HOCCO PM TOOL — seed data (from hocco-data.js, "today" = 11 Aug 2026)
--
-- Run once in Supabase → SQL Editor, AFTER schema.sql.
-- All-or-nothing: if any line fails, nothing is saved.
--
-- Rules followed:
--   • Departments only — people's names from the prototype are not stored.
--     (e.g. gate reviews "by Rohit Desai · Supply Chain" → Supply Chain)
--   • Brand A = Hocco, B = H&H, Shared = both brands.
--   • The 4 "Awaiting prioritisation" initiatives have NO priority.
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Brands
-- --------------------------------------------------------------------------
insert into public.brands (code, name) values
  ('A',      'Hocco'),
  ('B',      'H&H'),
  ('Shared', 'Both brands');


-- --------------------------------------------------------------------------
-- 2. Departments (7 from the prototype + Leadership for CEO approvals)
-- --------------------------------------------------------------------------
insert into public.departments (id, name, is_leadership, sort_order) values
  ('marketing',    'Marketing',    false, 1),
  ('supply_chain', 'Supply Chain', false, 2),
  ('procurement',  'Procurement',  false, 3),
  ('finance',      'Finance',      false, 4),
  ('rnd',          'R&D',          false, 5),
  ('production',   'Production',   false, 6),
  ('qc',           'QC',           false, 7),
  ('leadership',   'Leadership',   true,  8);


-- --------------------------------------------------------------------------
-- 3. Blocker reasons (the picklist)
-- --------------------------------------------------------------------------
insert into public.blocker_reasons (id, label, sort_order) values
  (1, 'Waiting on an input from another department', 1),
  (2, 'Vendor / external party delay',               2),
  (3, 'Approval pending longer than expected',       3),
  (4, 'Requirement changed upstream',                4),
  (5, 'Capacity — my team is on other priorities',   5),
  (6, 'Missing information or unclear spec',         6);


-- --------------------------------------------------------------------------
-- 4. Initiatives — all 30
--    owner = the department leading it (NPD → Supply Chain, others → the
--    department of the template's first track).
--    priority follows the prototype: at-risk = High; otherwise by launch date.
-- --------------------------------------------------------------------------
insert into public.initiatives
  (slug, name, type, brand_code, owner_department_id, created_by_department_id,
   priority, status, status_reason, launch_on, late_days, created_at)
select v.slug, v.name, v.type, v.brand, v.owner, v.created_by,
       v.priority, v.status, v.reason, v.launch::date, v.late,
       coalesce(v.created::timestamptz, now())
from (values
  -- At risk
  ('belgian-dark',  'Belgian Dark 90ml Bar',       'NPD',                'B',      'supply_chain', 'supply_chain', 'High',   'Overdue',  'Launch in 7 days, Codes/BOM track still incomplete', '2026-08-18', 4,  null),
  ('trade-price',   'Trade Price Revision Q3',     'Price revision',     'Shared', 'finance',      'finance',      'High',   'Blocked',  'Blocked 6 days at Finance approval',                  '2026-08-18', 6,  null),
  ('cone-sleeve',   'Cone Sleeve Refresh',         'Packaging redesign', 'A',      'marketing',    'marketing',    'High',   'Rework',   '2nd revision — upstream requirement changed',         '2026-08-22', 3,  null),
  ('festive-pack',  'Festive Gift Pack',           'Packaging redesign', 'B',      'marketing',    'marketing',    'High',   'Disputed', 'Blocked 9 days at Procurement, unacknowledged',       '2026-08-28', 9,  null),
  ('tender-coco',   'Tender Coconut',              'Seasonal (FOM)',     'A',      'rnd',          'rnd',          'High',   'Stale',    'Stale 14 days — no update on Recipe Sign-off',        '2026-09-05', 14, null),
  ('mango-kulfi',   'Mango Kulfi 750ml',           'NPD',                'A',      'supply_chain', 'supply_chain', 'High',   'Blocked',  '3rd revision, 2× same reason at Artwork Approval',    '2026-09-14', 9,  null),

  -- Awaiting prioritisation (no priority, no launch date)
  ('jamun',         'Jamun Sorbet Trial',          'NPD',                'A',      'supply_chain', 'rnd',          null,     'Awaiting', 'Created 3 days ago by R&D · no launch date set',      null,         0,  '2026-08-08'),
  ('litchi-w2',     'Litchi FOM Wave 2',           'Seasonal (FOM)',     'B',      'rnd',          'marketing',    null,     'Awaiting', 'Created 6 days ago by Marketing',                     null,         0,  '2026-08-05'),
  ('fam-pack-vol',  '1L Family Pack Volume',       'Volume update',      'Shared', 'supply_chain', 'supply_chain', null,     'Awaiting', 'Created 8 days ago by Supply Chain',                  null,         0,  '2026-08-03'),
  ('kesar-relabel', 'Kesar Pista Tub Relabel',     'Packaging redesign', 'A',      'marketing',    'production',   null,     'Awaiting', 'Created 12 days ago by Production',                   null,         0,  '2026-07-30'),

  -- On track
  ('mrp-100',       'MRP Revision — 100ml Cups',   'Price revision',     'A',      'finance',      'finance',      'High',   'On track', 'At Finance approval · on schedule',                   '2026-08-25', 0,  null),
  ('cone-120',      'Volume Update — Cone 120ml',  'Volume update',      'B',      'supply_chain', 'supply_chain', 'High',   'On track', 'Production sign-off pending',                         '2026-08-29', 0,  null),
  ('inst-price',    'Institutional Price List',    'Price revision',     'Shared', 'finance',      'finance',      'High',   'On track', 'Awaiting CEO approval',                               '2026-09-01', 0,  null),
  ('bulk-5l',       'Bulk Pack 5L Volume',         'Volume update',      'B',      'supply_chain', 'supply_chain', 'High',   'On track', 'BOM update in progress',                              '2026-09-03', 0,  null),
  ('distrib-slab',  'Distributor Slab Revision',   'Price revision',     'Shared', 'finance',      'finance',      'High',   'On track', 'Finance modelling in progress',                       '2026-09-05', 0,  null),
  ('pista-4l',      'Pista Badam 4L Party Pack',   'Volume update',      'A',      'supply_chain', 'supply_chain', 'Medium', 'On track', 'Packaging artwork approved',                          '2026-09-12', 0,  null),
  ('sitaphal',      'Sitaphal FOM',                'Seasonal (FOM)',     'B',      'rnd',          'rnd',          'Medium', 'On track', 'Campaign brief in progress',                          '2026-09-12', 0,  null),
  ('modular-lid',   'Modular Tub Lid',             'Packaging redesign', 'Shared', 'marketing',    'marketing',    'Medium', 'On track', 'Vendor mockup approved 1st pass',                     '2026-09-15', 0,  null),
  ('guava-chilli',  'Guava Chilli FOM',            'Seasonal (FOM)',     'A',      'rnd',          'rnd',          'Medium', 'On track', 'Recipe locked · packaging started',                   '2026-09-18', 0,  null),
  ('label-comp',    'Label Compliance Refresh',    'Packaging redesign', 'B',      'marketing',    'marketing',    'Medium', 'On track', 'Statutory review with QC',                            '2026-09-20', 0,  null),
  ('filter-coffee', 'Filter Coffee FOM',           'Seasonal (FOM)',     'A',      'rnd',          'rnd',          'Medium', 'On track', 'Recipe trials underway',                              '2026-09-25', 0,  null),
  ('multipack',     'Multipack Carton Update',     'Packaging redesign', 'A',      'marketing',    'marketing',    'Medium', 'On track', 'Structural sample approved',                          '2026-09-26', 0,  null),
  ('kesar-1l',      'Kesar Pista 1L',              'NPD',                'A',      'supply_chain', 'supply_chain', 'Low',    'On track', 'All four tracks progressing',                         '2026-09-30', 0,  null),
  ('rose-falooda',  'Rose Falooda FOM',            'Seasonal (FOM)',     'B',      'rnd',          'rnd',          'Low',    'On track', 'Concept approved',                                    '2026-10-02', 0,  null),
  ('shipper',       'Corrugated Shipper Redesign', 'Packaging redesign', 'Shared', 'marketing',    'marketing',    'Low',    'On track', 'Costing with Procurement',                            '2026-10-08', 0,  null),
  ('choco-chip',    'Choco Chip 500ml',            'NPD',                'A',      'supply_chain', 'supply_chain', 'Low',    'On track', 'Recipe track at trial batch 2',                       '2026-10-15', 0,  null),
  ('almond-bar',    'Roasted Almond Bar',          'NPD',                'B',      'supply_chain', 'supply_chain', 'Low',    'On track', 'Recipe track in R&D',                                 '2026-10-20', 0,  null),
  ('malai-stick',   'Malai Kulfi Stick',           'NPD',                'B',      'supply_chain', 'supply_chain', 'Low',    'On track', 'Kicked off · all tracks queued',                      '2026-11-05', 0,  null),
  ('cookie-cream',  'Cookie Cream Sandwich',       'NPD',                'B',      'supply_chain', 'supply_chain', 'Low',    'On track', 'Concept stage',                                       '2026-11-22', 0,  null),
  ('sugarfree',     'Sugar-Free Vanilla',          'NPD',                'A',      'supply_chain', 'supply_chain', 'Low',    'On track', 'Concept stage',                                       '2026-11-30', 0,  null)
) as v(slug, name, type, brand, owner, created_by, priority, status, reason, launch, late, created);

-- Mango Kulfi's detail: started 9 Jul; 33 days split into working / waiting / blocked.
update public.initiatives
set started_on = '2026-07-09', days_working = 11, days_waiting = 16, days_blocked = 6
where slug = 'mango-kulfi';


-- --------------------------------------------------------------------------
-- 5. Mango Kulfi — its four tracks
-- --------------------------------------------------------------------------
insert into public.tracks (initiative_id, slug, name, department_id, position, status, summary)
select i.id, v.slug, v.name, v.dept, v.pos, v.status, v.summary
from public.initiatives i
cross join (values
  ('recipe',      'Recipe',      'rnd',          1, 'done',    '5 of 5 stages complete · signed off 4 Aug'),
  ('packaging',   'Packaging',   'marketing',    2, 'blocked', 'Stuck at Artwork Approval · 3rd revision'),
  ('codes',       'Codes / BOM', 'supply_chain', 3, 'queued',  'Queued behind Packaging · waiting 6 days'),
  ('procurement', 'Procurement', 'procurement',  4, 'working', 'Laminate sourcing in progress · on schedule')
) as v(slug, name, dept, pos, status, summary)
where i.slug = 'mango-kulfi';


-- --------------------------------------------------------------------------
-- 6. Mango Kulfi — stages inside each track (15 in total)
-- --------------------------------------------------------------------------
insert into public.stages (track_id, position, name, department_id, second_department_id, status, note, closed_on)
select t.id, v.pos, v.name, v.dept, v.dept2, v.status, v.note, v.closed::date
from (values
  ('recipe',      1, 'Concept & benchmark', 'rnd',          null, 'done',    'Closed 16 Jul',                           '2026-07-16'),
  ('recipe',      2, 'Trial batch 1',       'rnd',          null, 'done',    'Closed 23 Jul',                           '2026-07-23'),
  ('recipe',      3, 'Sensory panel',       'qc',           null, 'done',    'Closed 29 Jul',                           '2026-07-29'),
  ('recipe',      4, 'Trial batch 2',       'rnd',          null, 'done',    'Closed 2 Aug',                            '2026-08-02'),
  ('recipe',      5, 'Recipe sign-off',     'rnd',          'qc', 'done',    'Closed 4 Aug — spec revised at sign-off', '2026-08-04'),
  ('packaging',   1, 'Structural spec',     'supply_chain', null, 'done',    'Closed 18 Jul',                           '2026-07-18'),
  ('packaging',   2, 'Key visual',          'marketing',    null, 'done',    'Closed 21 Jul',                           '2026-07-21'),
  ('packaging',   3, 'Artwork production',  'marketing',    null, 'blocked', 'Rejected 3× · v4 due today',              null),
  ('packaging',   4, 'Vendor proof',        'procurement',  null, 'queued',  'Cannot start until artwork approved',     null),
  ('codes',       1, 'SKU creation',        'supply_chain', null, 'done',    'Closed 25 Jul',                           '2026-07-25'),
  ('codes',       2, 'BOM finalisation',    'supply_chain', null, 'queued',  'Waiting on approved artwork',             null),
  ('codes',       3, 'Costing sign-off',    'finance',      null, 'queued',  'Not yet actionable',                      null),
  ('procurement', 1, 'Vendor shortlist',    'procurement',  null, 'done',    'Closed 28 Jul',                           '2026-07-28'),
  ('procurement', 2, 'Laminate sourcing',   'procurement',  null, 'working', 'In progress · 2 quotes received',         null),
  ('procurement', 3, 'PO release',          'procurement',  null, 'queued',  'After artwork approval',                  null)
) as v(track, pos, name, dept, dept2, status, note, closed)
join public.tracks t on t.slug = v.track
join public.initiatives i on i.id = t.initiative_id and i.slug = 'mango-kulfi';


-- --------------------------------------------------------------------------
-- 7. Mango Kulfi — gates (approval checkpoints)
--    Positions follow the NPD template. Only "Artwork Approval" is named in
--    the prototype; the other three names are placeholders to confirm.
-- --------------------------------------------------------------------------
insert into public.gates (track_id, name, after_stage_position, department_id, status)
select t.id, v.name, v.after_pos, v.dept, v.status
from (values
  ('recipe',      'Sensory approval',  3, 'qc',           'passed'),
  ('recipe',      'Recipe approval',   5, 'qc',           'passed'),
  ('packaging',   'Artwork Approval',  3, 'supply_chain', 'failed'),
  ('codes',       'BOM approval',      2, 'supply_chain', 'pending'),
  ('procurement', 'Sourcing approval', 2, 'procurement',  'pending')
) as v(track, name, after_pos, dept, status)
join public.tracks t on t.slug = v.track
join public.initiatives i on i.id = t.initiative_id and i.slug = 'mango-kulfi';


-- --------------------------------------------------------------------------
-- 8. Artwork Approval — the three rejections
-- --------------------------------------------------------------------------
insert into public.gate_reviews (gate_id, revision, outcome, reviewer_department_id, reason, note, flags, reviewed_on)
select g.id, v.rev, 'rejected', v.dept, v.reason, v.note, v.flags::text[], v.reviewed::date
from (values
  (1, 'supply_chain', 'Statutory declarations incorrect', 'FSSAI licence block missing on rear panel',                        '{}',         '2026-07-22'),
  (2, 'supply_chain', 'Statutory declarations incorrect', 'Licence block added but net-weight placement still non-compliant', '{repeat}',   '2026-07-30'),
  (3, 'qc',           'Nutritional panel mismatch',       'Panel reflects pre-revision recipe',                               '{upstream}', '2026-08-06')
) as v(rev, dept, reason, note, flags, reviewed)
cross join public.gates g
join public.tracks t on t.id = g.track_id and t.slug = 'packaging'
join public.initiatives i on i.id = t.initiative_id and i.slug = 'mango-kulfi'
where g.name = 'Artwork Approval';


-- --------------------------------------------------------------------------
-- 9. Mango Kulfi — Packaging blocks Codes / BOM
-- --------------------------------------------------------------------------
insert into public.track_dependencies (blocking_track_id, blocked_track_id, critical, note)
select p.id, c.id, true,
       'Codes/BOM cannot finalise pack codes until artwork is approved. 6 days lost so far.'
from public.initiatives i
join public.tracks p on p.initiative_id = i.id and p.slug = 'packaging'
join public.tracks c on c.initiative_id = i.id and c.slug = 'codes'
where i.slug = 'mango-kulfi';


-- --------------------------------------------------------------------------
-- 10. Blockers — the four open claims
-- --------------------------------------------------------------------------
insert into public.blockers
  (initiative_id, stage_id, title, raised_by_department_id, against_department_id,
   reason_id, note, status, raised_on, acknowledged_on)
select i.id,
       (select s.id from public.stages s
          join public.tracks t on t.id = s.track_id
         where t.initiative_id = i.id and t.slug = v.track and s.position = v.stage_pos),
       v.title, v.raised_by, v.against, v.reason_id, v.note, v.status,
       v.raised::date, v.acked::date
from (values
  ('festive-pack', null,        null, 'Vendor quote for POS units', 'marketing',  'procurement', 1, 'Claim not acknowledged · auto-escalates to both HODs in 1 day',        'disputed',     '2026-08-02', null),
  ('trade-price',  null,        null, 'Final MRP figure',           'marketing',  'finance',     3, 'Acknowledged 5 Aug by Finance',                                        'acknowledged', '2026-08-05', '2026-08-05'),
  ('mango-kulfi',  'packaging', 3,    'Artwork Approval loop',      'marketing',  'qc',          4, 'Acknowledged · nutritional panel depends on revised recipe spec',      'acknowledged', '2026-08-05', '2026-08-06'),
  ('belgian-dark', null,        null, 'Laminate lead time',         'production', 'procurement', 2, 'Acknowledged 8 Aug',                                                   'acknowledged', '2026-08-08', '2026-08-08')
) as v(slug, track, stage_pos, title, raised_by, against, reason_id, note, status, raised, acked)
join public.initiatives i on i.slug = v.slug;


commit;

-- Quick check — should show: 3 brands, 8 departments, 6 reasons, 30 initiatives,
-- 4 tracks, 15 stages, 5 gates, 3 gate reviews, 1 dependency, 4 blockers.
select 'brands' as table_name, count(*) from public.brands
union all select 'departments',        count(*) from public.departments
union all select 'blocker_reasons',    count(*) from public.blocker_reasons
union all select 'initiatives',        count(*) from public.initiatives
union all select 'tracks',             count(*) from public.tracks
union all select 'stages',             count(*) from public.stages
union all select 'gates',              count(*) from public.gates
union all select 'gate_reviews',       count(*) from public.gate_reviews
union all select 'track_dependencies', count(*) from public.track_dependencies
union all select 'blockers',           count(*) from public.blockers;
