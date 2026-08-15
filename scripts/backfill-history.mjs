// One-time/occasional backfill: pulls completed-season fixtures from
// API-Football and upserts them into Supabase's fixtures_history table
// (see supabase/history_schema.sql). Run this locally with Node 18+.
//
// Usage:
//   APIFOOTBALL_KEY=xxx SUPABASE_URL=https://xxx.supabase.co \
//   SUPABASE_SERVICE_ROLE_KEY=xxx node scripts/backfill-history.mjs batch1
//
//   ...then whenever you're ready for the rest:
//   APIFOOTBALL_KEY=xxx SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//   node scripts/backfill-history.mjs batch2
//
// Notes:
// - Uses your Supabase SERVICE ROLE key (not the anon key) because this
//   script writes data and RLS only allows public reads. Never put the
//   service role key in Netlify env vars or client code — it stays on
//   your machine for this one-off script only.
// - Each league+season costs exactly 1 API-Football request (the /fixtures
//   endpoint returns a full season per call), so batch1 (EPL + Championship,
//   2 seasons each) costs 4 requests total — trivially inside the free
//   100/day cap. batch2 (remaining 6 leagues) costs 12 requests.

const API_BASE = "https://v3.football.api-sports.io";
const APIFOOTBALL_KEY = process.env.APIFOOTBALL_KEY;
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!APIFOOTBALL_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Missing required env vars: APIFOOTBALL_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

// Diagnostic only — never logs the actual secret values, just enough to
// sanity-check they look like real keys (right rough length, no stray
// whitespace) rather than an empty/malformed secret slipping past the
// truthy check above.
console.log(`APIFOOTBALL_KEY: length=${APIFOOTBALL_KEY.length}, trimmedDiffers=${APIFOOTBALL_KEY !== APIFOOTBALL_KEY.trim()}`);
console.log(`SUPABASE_URL: length=${SUPABASE_URL.length}, startsWithHttps=${SUPABASE_URL.startsWith("https://")}`);
console.log(`SUPABASE_SERVICE_ROLE_KEY: length=${SUPABASE_SERVICE_ROLE_KEY.length}, trimmedDiffers=${SUPABASE_SERVICE_ROLE_KEY !== SUPABASE_SERVICE_ROLE_KEY.trim()}`);

// league_key matches LEAGUES[].id in index.html. apiFootballId is looked up
// dynamically below (via /leagues?search=) rather than hardcoded, so a
// wrong guess can't silently corrupt the data — it just skips with a warning.
const ALL_LEAGUES = [
  { key: "4328", name: "Premier League", country: "England" },
  { key: "4329", name: "Championship", country: "England" },
  { key: "4335", name: "La Liga", country: "Spain" },
  { key: "4332", name: "Serie A", country: "Italy" },
  { key: "4331", name: "Bundesliga", country: "Germany" },
  { key: "4334", name: "Ligue 1", country: "France" },
  { key: "4401", name: "Ligue 2", country: "France" },
  { key: "4745", name: "Premier League", country: "Kenya" }
];

const BATCHES = {
  batch1: ["4328", "4329"],                                   // EPL + Championship, as requested
  batch2: ["4335", "4332", "4331", "4334", "4401", "4745"]     // everything else
};

// Last 2 completed seasons as of now. API-Football's "season" is the
// start year, e.g. 2024 = the 2024/25 season.
const SEASONS = [2024, 2025];

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function apiFootball(path) {
  const res = await fetch(`${API_BASE}${path}`, { headers: { "x-apisports-key": APIFOOTBALL_KEY } });
  if (!res.ok) throw new Error(`API-Football HTTP ${res.status} on ${path}`);
  const data = await res.json();
  if (data.errors && Object.keys(data.errors).length) {
    throw new Error(`API-Football error on ${path}: ${JSON.stringify(data.errors)}`);
  }
  return data;
}

async function resolveLeagueId(name, country) {
  const data = await apiFootball(`/leagues?search=${encodeURIComponent(name)}`);
  const candidates = data.response || [];
  const match = candidates.find(c => (c.country?.name || "").toLowerCase() === country.toLowerCase());
  return (match || candidates[0])?.league?.id || null;
}

async function fetchSeasonFixtures(apiFootballLeagueId, season) {
  const data = await apiFootball(`/fixtures?league=${apiFootballLeagueId}&season=${season}&status=FT`);
  return data.response || [];
}

function toRow(leagueKey, season, fixture) {
  return {
    api_football_fixture_id: fixture.fixture.id,
    league_key: leagueKey,
    season,
    match_date: fixture.fixture.date,
    home_team: fixture.teams.home.name,
    away_team: fixture.teams.away.name,
    home_goals: fixture.goals.home,
    away_goals: fixture.goals.away,
    status: "FT"
  };
}

async function upsertRows(rows) {
  if (!rows.length) return;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/fixtures_history?on_conflict=api_football_fixture_id`, {
    method: "POST",
    headers: {
      "apikey": SUPABASE_SERVICE_ROLE_KEY,
      "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      "Prefer": "resolution=merge-duplicates"
    },
    body: JSON.stringify(rows)
  });
  if (!res.ok) {
    throw new Error(`Supabase upsert failed: ${res.status} ${await res.text()}`);
  }
}

async function main() {
  const batchName = process.argv[2];
  const leagueKeys = BATCHES[batchName];
  if (!leagueKeys) {
    console.error(`Usage: node backfill-history.mjs <batch1|batch2>`);
    process.exit(1);
  }

  for (const leagueKey of leagueKeys) {
    const league = ALL_LEAGUES.find(l => l.key === leagueKey);
    console.log(`\n== ${league.name} (${league.country}) ==`);

    const apiFootballLeagueId = await resolveLeagueId(league.name, league.country);
    if (!apiFootballLeagueId) {
      console.warn(`  Could not resolve API-Football league id for ${league.name}/${league.country} — skipping.`);
      continue;
    }
    await sleep(1500); // be polite to the free-tier rate limit

    for (const season of SEASONS) {
      console.log(`  Season ${season}...`);
      const fixtures = await fetchSeasonFixtures(apiFootballLeagueId, season);
      const rows = fixtures
        .filter(f => f.goals.home !== null && f.goals.away !== null)
        .map(f => toRow(leagueKey, season, f));
      await upsertRows(rows);
      console.log(`    ${rows.length} fixtures upserted.`);
      await sleep(1500);
    }
  }

  console.log("\nDone.");
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
