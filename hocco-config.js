/* ==========================================================================
   HOCCO PM TOOL — connection settings
   Only the PUBLISHABLE key goes here — it is safe in website files.
   NEVER put the secret key (sb_secret_… / service_role) in this file.
   ========================================================================== */

window.HOCCO_CONFIG = {
  supabaseUrl: "https://eupmubyrizsarzvwqslv.supabase.co",

  /* Supabase → Project Settings → API Keys → Publishable key (sb_publishable_…) */
  supabaseKey: "sb_publishable_5ZcMyvTTY9eoH9UBgnor2g_yzLsNqrD",

  /* The sample data is set on 11 Aug 2026. Staleness and "days blocked" are
     counted from this date. Set to null to use the real date once live data
     replaces the sample data. */
  today: "2026-08-11"
};
