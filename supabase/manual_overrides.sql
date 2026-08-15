-- =====================================================================
-- Soka Edge KE — manual form-override storage
-- =====================================================================
-- What this does
--   Stores the recent-form numbers you type by hand for a team whenever
--   the live feed (API-Football) has no recent results for them — so
--   your edits survive a page refresh, a new browser tab, or a different
--   device, instead of only living in memory for the current session.
--
-- Security note — please read
--   This table is written to directly from the browser using your
--   Supabase anon/publishable key, the same way the rest of the site
--   reads leagues/teams/derbies. That key is necessarily public (it
--   ships inside index.html's JS), so the policies below intentionally
--   allow ANYONE who has your site's URL to insert/update/delete rows
--   in *this table only* — never leagues/teams/derbies, which stay
--   read-only. Worst case if someone abuses this: they overwrite a
--   team's stored form numbers with junk, which you'd notice and can
--   just re-enter or delete. If that risk isn't acceptable to you (e.g.
--   you plan to share this site's URL publicly), say so and this can
--   be moved behind a Netlify function with basic validation instead.
--
-- How to use it
--   Paste this into the Supabase SQL editor and run it once.
-- =====================================================================

create table if not exists public.manual_form_overrides (
  team_name   text primary key,
  n           integer not null check (n >= 1),
  w           integer not null check (w >= 0),
  d           integer not null check (d >= 0),
  l           integer not null check (l >= 0),
  gf          numeric not null check (gf >= 0),
  ga          numeric not null check (ga >= 0),
  updated_at  timestamptz not null default now()
);

alter table public.manual_form_overrides enable row level security;

drop policy if exists "Public read overrides" on public.manual_form_overrides;
create policy "Public read overrides" on public.manual_form_overrides
  for select using (true);

drop policy if exists "Public insert overrides" on public.manual_form_overrides;
create policy "Public insert overrides" on public.manual_form_overrides
  for insert with check (true);

drop policy if exists "Public update overrides" on public.manual_form_overrides;
create policy "Public update overrides" on public.manual_form_overrides
  for update using (true) with check (true);

drop policy if exists "Public delete overrides" on public.manual_form_overrides;
create policy "Public delete overrides" on public.manual_form_overrides
  for delete using (true);
