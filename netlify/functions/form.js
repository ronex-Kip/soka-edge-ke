// "Recent form" lookups. Checks the Supabase fixtures_history cache first
// (populated by scripts/backfill-history.mjs) so most requests cost zero
// API-Football calls; falls back to a live API-Football lookup for
// leagues/teams that haven't been backfilled yet (e.g. KPL before batch2).
const API_BASE = "https://v3.football.api-sports.io";

async function apiFootball(path, key) {
  const res = await fetch(`${API_BASE}${path}`, { headers: { "x-apisports-key": key } });
  if (!res.ok) throw new Error(`API-Football HTTP ${res.status}`);
  return res.json();
}

async function resolveTeamId(name, key) {
  const data = await apiFootball(`/teams?search=${encodeURIComponent(name)}`, key);
  const match = (data.response || [])[0];
  return match ? match.team.id : null;
}

async function fetchFromCache(team, last) {
  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  if (!url || !anonKey) return null; // cache not configured, skip straight to live API

  const t = encodeURIComponent(team);
  const filter = `or=(home_team.eq.${t},away_team.eq.${t})`;
  const res = await fetch(
    `${url}/rest/v1/fixtures_history?${filter}&order=match_date.desc&limit=${last}`,
    { headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}` } }
  );
  if (!res.ok) return null; // don't hard-fail on cache errors, just fall through to live
  return res.json();
}

exports.handler = async (event) => {
  const params = event.queryStringParameters || {};
  const { team, n } = params;
  const last = Math.min(20, Math.max(1, parseInt(n, 10) || 10));
  if (!team) {
    return { statusCode: 400, body: JSON.stringify({ error: "Missing team parameter" }) };
  }

  // 1) Try the cache first — zero API-Football cost.
  try {
    const cached = await fetchFromCache(team, last);
    if (cached && cached.length) {
      const matches = cached.map(r => ({
        date: r.match_date,
        homeTeamId: r.home_team,   // cache stores names, not API-Football ids
        awayTeamId: r.away_team,
        homeGoals: r.home_goals,
        awayGoals: r.away_goals
      }));
      // teamId is set to the queried team's own name (not a numeric id) so
      // that the frontend's `e.idHomeTeam === teamId` home/away check still
      // works correctly against the name-based rows this cache returns —
      // it's guaranteed to match one side since the query above filtered on it.
      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ teamId: team, matches, source: "cache" })
      };
    }
  } catch (_e) {
    // cache lookup failed silently — fall through to live API below
  }

  // 2) Fall back to a live API-Football lookup.
  const key = process.env.APIFOOTBALL_KEY;
  if (!key) {
    return { statusCode: 500, body: JSON.stringify({ error: "APIFOOTBALL_KEY is not set on the server" }) };
  }

  try {
    const teamId = await resolveTeamId(team, key);
    if (!teamId) {
      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ teamId: null, matches: [] })
      };
    }

    const data = await apiFootball(`/fixtures?team=${teamId}&last=${last}&status=FT`, key);
    const matches = (data.response || []).map(f => ({
      date: f.fixture.date,
      homeTeamId: f.teams.home.id,
      awayTeamId: f.teams.away.id,
      homeGoals: f.goals.home,
      awayGoals: f.goals.away
    })).filter(m => m.homeGoals !== null && m.awayGoals !== null);

    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ teamId, matches, source: "live" })
    };
  } catch (err) {
    return { statusCode: 502, body: JSON.stringify({ error: "Upstream fetch failed", detail: String(err) }) };
  }
};
