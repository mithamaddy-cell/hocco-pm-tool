# Hocco PM Tool

Internal, mobile-first web app for Hocco Ice Cream that shows where every
initiative is, why it's stuck, and which department it's waiting on — replacing
spreadsheets and WhatsApp chasing. Full product rundown: @docs/product-brief.md

## Who you're working with

- The project owner is a **designer, not a developer**. Explain what you're
  doing in plain language, define technical terms the first time, and say
  what changed after every step.
- Work **one small step at a time**. Stop after each step so she can check it
  in the browser before you continue. Never do several phases in one go.
- **Ask before** installing anything, creating accounts, deleting files, or
  changing the database structure.
- She creates all accounts (GitHub, Supabase, Cloudflare) herself. Never ask
  her to paste passwords or secret keys into the chat.
- After each working step, suggest a git commit with a clear message
  ("save point"), and explain how to roll back if needed.

## Decided stack (don't change without asking)

- **Frontend:** the existing plain HTML + CSS + JavaScript files. No framework
  migration (no React/Next.js) for the pilot.
- **Backend:** Supabase — PostgreSQL database, Auth (login), Row Level
  Security, Storage (approval PDFs), Edge Functions + scheduled jobs.
  Load the Supabase JS client from a CDN `<script>` tag; no build step.
- **Hosting:** Cloudflare Pages (free tier allows commercial use; Vercel's
  free tier does not — don't suggest it).
- **Code history:** GitHub, **private** repository (real company data).
- **Budget:** free tiers only for the pilot.

## Must not break (product rules)

- **Design is approved.** Do not change `hocco-tokens.css`, fonts, colours,
  spacing or component styles unless explicitly asked. Change data sources,
  not visuals.
- Delays are shown against **departments, never individual names**.
- Leadership view (Portfolio) is **read-only**. Leadership edits only stages
  that belong to their own department (e.g. the CEO's approval gates).
- Never build individual performance metrics or department "delay scores".
  Attribution stays per initiative, per step.
- A blocker is a **claim**: the other department can acknowledge or dispute.
  Disputes escalate to **both** heads of department, never one side.
- Anyone can create an initiative; it stays **"Awaiting prioritisation"**
  (priority empty) until leadership sets it.
- Colour roles: raspberry = actions/buttons only; amber = risk; slate =
  waiting. Never convey state with colour alone (always text or icon too).
- Reason text on cards is **never truncated**.
- Mobile-first at **390px**; check nothing breaks at 360px; touch targets
  at least 44px.
- **Calendar** is the default Portfolio tab.
- Brand codes: `A` = **Hocco**, `B` = **H&H**, `Shared` = both brands.

## Security rules

- Row Level Security stays **on** for every table (see `supabase/schema.sql`).
- Only the Supabase **publishable/anon key** may appear in frontend code.
  The **service role / secret key** never goes in frontend files or git.
- Keys live in a `.env` file that is listed in `.gitignore`.
- No analytics, trackers or third-party scripts beyond Supabase and fonts.
- Real data (costing, MRP, item codes) is **confidential**: never commit it
  to a public repo, never paste it into external services.

## Files

- `hocco-portfolio-mobile.html` — Portfolio (Calendar / Initiatives / Departments)
- `hocco-mywork-mobile.html` — a rep's My Work (3 zones, status bottom sheet)
- `hocco-initiative-detail.html` — Initiative Detail (tracks, gates, delay)
- `hocco-blockers-mobile.html`, `hocco-new-initiative.html` — other screens
- `hocco-data.js` — CURRENT seed data (real Jar Sundae world). Will be
  replaced by Supabase reads/writes. Its object shapes are what the screens
  expect — keep those shapes when swapping in the database.
- `hocco-ui.js` — shared UI helpers (chips, nav, sheets, filters, toast)
- `hocco-tokens.css`, `hocco-theme.js` — design tokens and theme (don't edit)
- `supabase/schema.sql` — database tables + security rules (tested draft)
- `docs/product-brief.md` — what the app does and why

## Build plan — one phase at a time

1. **Set-up:** git + private GitHub repo; `.gitignore`; confirm the prototype
   runs locally in a browser.
2. **Database:** she runs `supabase/schema.sql` in the Supabase SQL Editor.
   Then write `supabase/seed.sql` from `hocco-data.js` (departments, the 30
   initiatives, Jar Sundae's tracks/stages/gate history, blockers).
3. **Read:** a small `hocco-api.js` that loads from Supabase and returns the
   same shapes as `hocco-data.js`, so screens change minimally. One screen at
   a time: Portfolio → Initiative Detail → My Work → Blockers.
4. **Write:** status changes, raise blocker, acknowledge/dispute, gate
   approve/reject — each writes to the database and the activity log.
5. **Login & roles:** Supabase Auth (magic link email); rep lands on My Work,
   leadership on Portfolio; test that the security rules hold.
6. **Automations:** scheduled jobs for staleness nudges (private first, then
   visible) and dispute escalation; email notifications. WhatsApp comes
   later (needs Meta-approved templates via a provider).
7. **Deploy:** Cloudflare Pages from GitHub; pilot with 7 reps.

## Known issues to fix along the way

- `hocco-initiative-detail.html` has a hardcoded projected date ("slip to
  23 Sep") — should be calculated from data.
- `hocco-ui.js` and Portfolio show "Brand A / Brand B" — should read
  "Hocco" / "H&H".
- `hocco-data.js` exports `mangoKulfi` as an alias for `jarSundae` (older
  screens reference it) — remove once screens use the API.

## How to check work

Open the HTML file in a browser, use device mode at 390px wide, click
through: Portfolio → Jar Sundae → back; My Work → status → Blocked → pick a
department → confirm. Nothing should look different from the approved design.
