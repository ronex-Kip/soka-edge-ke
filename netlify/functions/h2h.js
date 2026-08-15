// Head-to-head lookups. Checks the Supabase fixtures_history cache first
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

async function fetchFromCache(team1, team2) {
  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  if (!url || !anonKey) return null; // cache not configured, skip straight to live API

  const t1 = encodeURIComponent(team1);
  const t2 = encodeURIComponent(team2);
  // Match either home/away order: (home=t1 AND away=t2) OR (home=t2 AND away=t1)
  const filter = `or=(and(home_team.eq.${t1},away_team.eq.${t2}),and(home_team.eq.${t2},away_team.eq.${t1}))`;
  const res = await fetch(
    `${url}/rest/v1/fixtures_history?${filter}&order=match_date.desc&limit=10`,
    { headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}` } }
  );
  if (!res.ok) return null; // don't hard-fail on cache errors, just fall through to live
  const rows = await res.json();
  return rows;
}

exports.handler = async (event) => {
  const params = event.queryStringParameters || {};
  const { team1, team2 } = params;
  if (!team1 || !team2) {
    return { statusCode: 400, body: JSON.stringify({ error: "Missing team1 or team2 parameter" }) };
  }

  // 1) Try the cache first — zero API-Football cost.
  try {
    const cached = await fetchFromCache(team1, team2);
    if (cached && cached.length) {
      const fixtures = cached.map(r => ({
        date: r.match_date,
        homeTeam: r.home_team,
        awayTeam: r.away_team,
        homeGoals: r.home_goals,
        awayGoals: r.away_goals
      }));
      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ n: fixtures.length, fixtures, source: "cache" })
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
    const [id1, id2] = await Promise.all([resolveTeamId(team1, key), resolveTeamId(team2, key)]);
    if (!id1 || !id2) {
      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ n: 0, fixtures: [], note: "Could not resolve one or both team names" })
      };
    }

    const h2h = await apiFootball(`/fixtures/headtohead?h2h=${id1}-${id2}&last=10`, key);
    const fixtures = (h2h.response || []).map(f => ({
      date: f.fixture.date,
      homeTeam: f.teams.home.name,
      awayTeam: f.teams.away.name,
      homeGoals: f.goals.home,
      awayGoals: f.goals.away
    })).filter(f => f.homeGoals !== null && f.awayGoals !== null);

    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ n: fixtures.length, fixtures, source: "live" })
    };
  } catch (err) {
    return { statusCode: 502, body: JSON.stringify({ error: "Upstream fetch failed", detail: String(err) }) };
  }
};
