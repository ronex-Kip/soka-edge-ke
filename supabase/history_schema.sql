-- Historical fixtures cache: backing store for head-to-head and recent-form
-- lookups so the live app doesn't have to burn API-Football requests on
-- every button click. Populated by scripts/backfill-history.mjs.
-- Safe to re-run (idempotent).

create table if not exists fixtures_history (
  id bigserial primary key,
  api_football_fixture_id bigint unique not null,
  league_key text not null,        -- matches LEAGUES[].id in index.html, e.g. '4328'
  season int not null,             -- start year of the season, e.g. 2024 for 2024/25
  match_date timestamptz not null,
  home_team text not null,
  away_team text not null,
  home_goals int not null,
  away_goals int not null,
  status text not null default 'FT'
);

create index if not exists idx_fixtures_history_home on fixtures_history (home_team);
create index if not exists idx_fixtures_history_away on fixtures_history (away_team);
create index if not exists idx_fixtures_history_league_season on fixtures_history (league_key, season);

alter table fixtures_history enable row level security;

drop policy if exists "public read fixtures_history" on fixtures_history;
create policy "public read fixtures_history" on fixtures_history
  for select using (true);

-- Writes only happen via the backfill script using the Supabase service role
-- key, which bypasses RLS, so no insert/update policy is needed for the
-- anon key the browser/functions use to read.
