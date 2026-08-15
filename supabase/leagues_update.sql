-- =====================================================================
-- Soka Edge KE — Supabase schema + data sync for leagues/teams/derbies
-- =====================================================================
-- What this does
--   1. Creates three tables (if they don't already exist) that mirror
--      the LEAGUES / ODDS_API_LEAGUE_MAP / DERBIES structures hard-coded
--      in index.html: leagues, teams, derbies.
--   2. Upserts the CURRENT full data set — all 8 leagues, including the
--      two just added (French Ligue 2, English Championship) — so this
--      script is safe to re-run any time a league or team list changes.
--      Re-running it updates existing rows and inserts new ones; it
--      never duplicates rows because of the UNIQUE constraints below.
--   3. Enables Row Level Security with a public read-only policy, since
--      this is reference data the front end only ever needs to SELECT.
--
-- How to use it
--   Paste this whole file into the Supabase SQL editor and run it.
--   To update again later (e.g. when Ligue 2 or the Championship do
--   their summer promotion/relegation shuffle), edit the INSERT blocks
--   below with the new team names and re-run the file — it's idempotent.
--
-- Note: the site itself (index.html) does NOT read from Supabase today —
-- it pulls the LEAGUES/DERBIES data from the hard-coded JS arrays and
-- team form/H2H data live from TheSportsDB via the Netlify functions.
-- This schema is provided so you have a proper database copy of the
-- league/team/derby data you can maintain going forward (e.g. from an
-- admin screen, a cron job, or just the SQL editor) instead of hand-
-- editing the HTML every transfer window. If you want the front end to
-- read from Supabase instead of the hard-coded arrays, see the note at
-- the bottom of this file.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

create table if not exists public.leagues (
  id            text primary key,          -- TheSportsDB idLeague, e.g. '4328'
  name          text not null,             -- display name shown in the League <select>
  query_name    text not null,             -- strLeague used to query TheSportsDB's search_all_teams.php
  odds_api_key  text,                      -- The Odds API sport key, null if not covered (e.g. KPL)
  sort_order    integer not null default 0,
  updated_at    timestamptz not null default now()
);

create table if not exists public.teams (
  id            bigint generated always as identity primary key,
  league_id     text not null references public.leagues(id) on delete cascade,
  name          text not null,
  sort_order    integer not null default 0,
  updated_at    timestamptz not null default now(),
  unique (league_id, name)
);

create table if not exists public.derbies (
  id            bigint generated always as identity primary key,
  league_id     text not null references public.leagues(id) on delete cascade,
  team_a        text not null,
  team_b        text not null,
  name          text not null,
  intensity     numeric(3,2) not null check (intensity >= 0 and intensity <= 1),
  note          text not null,
  updated_at    timestamptz not null default now(),
  unique (league_id, team_a, team_b)
);

create index if not exists teams_league_id_idx   on public.teams (league_id);
create index if not exists derbies_league_id_idx on public.derbies (league_id);

-- ---------------------------------------------------------------------
-- 2. Row Level Security — public, read-only
-- ---------------------------------------------------------------------

alter table public.leagues enable row level security;
alter table public.teams   enable row level security;
alter table public.derbies enable row level security;

drop policy if exists "Public read leagues" on public.leagues;
create policy "Public read leagues" on public.leagues for select using (true);

drop policy if exists "Public read teams" on public.teams;
create policy "Public read teams" on public.teams for select using (true);

drop policy if exists "Public read derbies" on public.derbies;
create policy "Public read derbies" on public.derbies for select using (true);

-- No insert/update/delete policies are created for the anon/public role,
-- so writes (like the upserts below) must be run as a privileged role —
-- e.g. via the SQL editor (service role) or the Supabase dashboard —
-- not from the browser.

-- ---------------------------------------------------------------------
-- 3. Leagues — upsert
-- ---------------------------------------------------------------------

insert into public.leagues (id, name, query_name, odds_api_key, sort_order) values
  ('4745', 'Kenyan Premier League (FKF-PL)', 'Kenyan Premier League',       null,                          1),
  ('4328', 'English Premier League',         'English Premier League',      'soccer_epl',                  2),
  ('4329', 'English Championship',           'English League Championship', 'soccer_efl_champ',            3),
  ('4335', 'Spanish La Liga',                'Spanish La Liga',             'soccer_spain_la_liga',        4),
  ('4332', 'Italian Serie A',                'Italian Serie A',             'soccer_italy_serie_a',        5),
  ('4331', 'German Bundesliga',              'German Bundesliga',           'soccer_germany_bundesliga',   6),
  ('4334', 'French Ligue 1',                 'French Ligue 1',              'soccer_france_ligue_one',     7),
  ('4401', 'French Ligue 2',                 'French Ligue 2',              'soccer_france_ligue_two',     8)
on conflict (id) do update set
  name         = excluded.name,
  query_name   = excluded.query_name,
  odds_api_key = excluded.odds_api_key,
  sort_order   = excluded.sort_order,
  updated_at   = now();

-- ---------------------------------------------------------------------
-- 4. Teams — upsert (delete-then-insert per league keeps rosters exact
--    across promotion/relegation, since ON CONFLICT alone won't remove
--    a team that dropped out of a league)
-- ---------------------------------------------------------------------

delete from public.teams where league_id = '4745';
insert into public.teams (league_id, name, sort_order) values
  ('4745','AFC Leopards',1),('4745','APS Bomet',2),('4745','Bandari',3),('4745','Bidco United',4),
  ('4745','Gor Mahia',5),('4745','Kakamega Homeboyz',6),('4745','Kariobangi Sharks',7),('4745','KCB',8),
  ('4745','Kenya Police',9),('4745','Mara Sugar',10),('4745','Murang''a Seal',11),('4745','Nairobi City Stars',12),
  ('4745','Posta Rangers',13),('4745','Shabana',14),('4745','Sofapaka',15),('4745','Tusker',16),
  ('4745','Ulinzi Stars',17),('4745','Mathare United',18);

delete from public.teams where league_id = '4328';
insert into public.teams (league_id, name, sort_order) values
  ('4328','Arsenal',1),('4328','Aston Villa',2),('4328','Bournemouth',3),('4328','Brentford',4),
  ('4328','Brighton',5),('4328','Burnley',6),('4328','Chelsea',7),('4328','Crystal Palace',8),
  ('4328','Everton',9),('4328','Fulham',10),('4328','Leeds United',11),('4328','Liverpool',12),
  ('4328','Manchester City',13),('4328','Manchester United',14),('4328','Newcastle United',15),
  ('4328','Nottingham Forest',16),('4328','Sunderland',17),('4328','Tottenham',18),
  ('4328','West Ham United',19),('4328','Wolverhampton Wanderers',20);

delete from public.teams where league_id = '4329';
insert into public.teams (league_id, name, sort_order) values
  ('4329','Birmingham City',1),('4329','Blackburn Rovers',2),('4329','Bolton Wanderers',3),
  ('4329','Bristol City',4),('4329','Burnley',5),('4329','Cardiff City',6),('4329','Charlton Athletic',7),
  ('4329','Derby County',8),('4329','Lincoln City',9),('4329','Middlesbrough',10),('4329','Millwall',11),
  ('4329','Norwich City',12),('4329','Portsmouth',13),('4329','Preston North End',14),
  ('4329','Queens Park Rangers',15),('4329','Sheffield United',16),('4329','Southampton',17),
  ('4329','Stoke City',18),('4329','Swansea City',19),('4329','Watford',20),
  ('4329','West Bromwich Albion',21),('4329','West Ham United',22),('4329','Wolverhampton Wanderers',23),
  ('4329','Wrexham',24);

delete from public.teams where league_id = '4335';
insert into public.teams (league_id, name, sort_order) values
  ('4335','Alaves',1),('4335','Athletic Bilbao',2),('4335','Atletico Madrid',3),('4335','Barcelona',4),
  ('4335','Celta Vigo',5),('4335','Elche',6),('4335','Espanyol',7),('4335','Getafe',8),
  ('4335','Girona',9),('4335','Levante',10),('4335','Mallorca',11),('4335','Osasuna',12),
  ('4335','Rayo Vallecano',13),('4335','Real Betis',14),('4335','Real Madrid',15),('4335','Real Oviedo',16),
  ('4335','Real Sociedad',17),('4335','Sevilla',18),('4335','Valencia',19),('4335','Villarreal',20);

delete from public.teams where league_id = '4332';
insert into public.teams (league_id, name, sort_order) values
  ('4332','Atalanta',1),('4332','Bologna',2),('4332','Cagliari',3),('4332','Como',4),
  ('4332','Cremonese',5),('4332','Fiorentina',6),('4332','Genoa',7),('4332','Inter Milan',8),
  ('4332','Juventus',9),('4332','Lazio',10),('4332','Lecce',11),('4332','AC Milan',12),
  ('4332','Napoli',13),('4332','Parma',14),('4332','Pisa',15),('4332','Roma',16),
  ('4332','Sassuolo',17),('4332','Torino',18),('4332','Udinese',19),('4332','Hellas Verona',20);

delete from public.teams where league_id = '4331';
insert into public.teams (league_id, name, sort_order) values
  ('4331','Augsburg',1),('4331','Bayer Leverkusen',2),('4331','Bayern Munich',3),('4331','Borussia Dortmund',4),
  ('4331','Borussia Monchengladbach',5),('4331','Eintracht Frankfurt',6),('4331','Freiburg',7),
  ('4331','Hamburg',8),('4331','Heidenheim',9),('4331','Hoffenheim',10),('4331','FC Koln',11),
  ('4331','Mainz',12),('4331','RB Leipzig',13),('4331','St Pauli',14),('4331','Stuttgart',15),
  ('4331','Union Berlin',16),('4331','Werder Bremen',17),('4331','Wolfsburg',18);

delete from public.teams where league_id = '4334';
insert into public.teams (league_id, name, sort_order) values
  ('4334','Angers',1),('4334','Auxerre',2),('4334','Brest',3),('4334','Le Havre',4),
  ('4334','Lens',5),('4334','Lille',6),('4334','Lorient',7),('4334','Lyon',8),
  ('4334','Marseille',9),('4334','Metz',10),('4334','Monaco',11),('4334','Nantes',12),
  ('4334','Nice',13),('4334','Paris FC',14),('4334','Paris Saint-Germain',15),('4334','Rennes',16),
  ('4334','Strasbourg',17),('4334','Toulouse',18);

delete from public.teams where league_id = '4401';
insert into public.teams (league_id, name, sort_order) values
  ('4401','Annecy',1),('4401','Boulogne',2),('4401','Clermont',3),('4401','Dijon',4),
  ('4401','Dunkerque',5),('4401','Grenoble',6),('4401','Guingamp',7),('4401','Laval',8),
  ('4401','Metz',9),('4401','Montpellier',10),('4401','Nancy',11),('4401','Nantes',12),
  ('4401','Pau',13),('4401','Red Star',14),('4401','Reims',15),('4401','Rodez',16),
  ('4401','Saint-Étienne',17),('4401','Sochaux',18);

-- ---------------------------------------------------------------------
-- 5. Derbies — upsert
-- ---------------------------------------------------------------------

insert into public.derbies (league_id, team_a, team_b, name, intensity, note) values
  ('4745','Gor Mahia','AFC Leopards','Mashemeji Derby',0.95,
    'Kenya''s fiercest rivalry. Historically tighter, more foul-heavy and more draw-prone than either side''s league form alone suggests.'),

  ('4328','Arsenal','Tottenham','North London Derby',0.85,'League position often counts for less than usual on derby day.'),
  ('4328','Liverpool','Everton','Merseyside Derby',0.8,'Historically tight and physical — one of England''s lowest average-margin derbies.'),
  ('4328','Manchester United','Manchester City','Manchester Derby',0.8,'High-stakes local rivalry; recent meetings have been unusually unpredictable.'),
  ('4328','Manchester United','Liverpool','Man Utd v Liverpool',0.85,'England''s most storied fixture — big-occasion unpredictability tends to narrow the gap.'),
  ('4328','Chelsea','Tottenham','London rivalry',0.6,'Combative London derby; form usually matters less than the occasion.'),
  ('4328','West Ham United','Tottenham','London rivalry',0.5,'Feisty East vs North London meeting.'),

  ('4329','West Bromwich Albion','Wolverhampton Wanderers','Black Country Derby',0.85,
    'One of England''s fiercest local rivalries — table position rarely settles this one.'),
  ('4329','Portsmouth','Southampton','South Coast Derby',0.9,
    'Among the most hostile derbies in English football — expect a tighter, more combative game than form suggests.'),

  ('4335','Real Madrid','Barcelona','El Clasico',1.0,'The biggest club fixture in the world — table position is often a poor guide.'),
  ('4335','Real Madrid','Atletico Madrid','Madrid Derby',0.75,'Atletico''s organisation and physicality historically narrow the gap regardless of form.'),
  ('4335','Sevilla','Real Betis','Seville Derby',0.85,'One of Europe''s most hostile derbies — home advantage is amplified further here.'),
  ('4335','Barcelona','Espanyol','Barcelona Derby',0.55,'Local rivalry — Espanyol traditionally raise their level for this one.'),

  ('4332','AC Milan','Inter Milan','Derby della Madonnina',0.9,'Tactical, tight, often lower-scoring than both sides'' season averages.'),
  ('4332','Roma','Lazio','Derby della Capitale',0.9,'Among Europe''s most volatile derbies — form counts for less.'),
  ('4332','Juventus','Torino','Derby della Mole',0.55,'Torino traditionally punch above their league position in this fixture.'),
  ('4332','Napoli','Juventus','Historic rivalry',0.55,'Fierce non-geographic rivalry with an unusually heated atmosphere.'),

  ('4331','Borussia Dortmund','Bayern Munich','Der Klassiker',0.65,'Germany''s biggest fixture, though Bayern''s squad depth usually still tells in the end.'),
  ('4331','FC Koln','Borussia Monchengladbach','Rhine Derby',0.7,'Local pride tightens the gap between the sides.'),

  ('4334','Paris Saint-Germain','Marseille','Le Classique',0.85,'France''s fiercest rivalry — PSG''s quality usually still wins out, but margins compress.'),
  ('4334','Nice','Monaco','Cote d''Azur Derby',0.5,'Regional rivalry along the French Riviera.'),

  ('4401','Nancy','Metz','Lorraine Derby',0.7,'Historic Lorraine rivalry — local pride tends to matter more than league form.')
on conflict (league_id, team_a, team_b) do update set
  name       = excluded.name,
  intensity  = excluded.intensity,
  note       = excluded.note,
  updated_at = now();

-- ---------------------------------------------------------------------
-- Done. Sanity check:
-- ---------------------------------------------------------------------
-- select l.name, count(t.id) as teams
-- from public.leagues l left join public.teams t on t.league_id = l.id
-- group by l.name order by l.sort_order;

-- =====================================================================
-- Optional next step — wiring the front end to Supabase instead of the
-- hard-coded arrays:
--   1. Add the Supabase JS client to index.html (CDN script tag) with
--      your project URL + anon key.
--   2. On load, replace the LEAGUES.forEach(...) population of the
--      League <select> with a call to:
--        supabase.from('leagues').select('*').order('sort_order')
--   3. In loadTeams(), instead of `lg.teams.forEach(...)`, query:
--        supabase.from('teams').select('name').eq('league_id', lg.id).order('sort_order')
--   4. In findDerby(), replace the DERBIES[leagueId] lookup with:
--        supabase.from('derbies').select('*').eq('league_id', leagueId)
--   This is optional — the site works today entirely from the JS
--   arrays in index.html. Only do this if you want league/team/derby
--   edits to happen in Supabase (or from an admin panel) instead of by
--   hand-editing HTML each transfer window.
-- =====================================================================
