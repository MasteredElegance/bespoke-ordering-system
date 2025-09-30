-- 0004_google_calendars.sql
-- Tables for Google Calendar sync (calendars + busy intervals)

create table if not exists public.google_calendars (
  id uuid primary key default gen_random_uuid(),
  calendar_id text not null unique,   -- e.g. 'primary' or 'you@domain.com'
  summary text,
  active boolean not null default true,
  created_at timestamptz default now()
);

create table if not exists public.busy_times (
  id uuid primary key default gen_random_uuid(),
  source_calendar_id uuid not null references public.google_calendars(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz default now()
);

create index if not exists idx_busy_times_range on public.busy_times (starts_at, ends_at);
create index if not exists idx_busy_times_source on public.busy_times (source_calendar_id);

-- Allow reading in the app; writes will come from service role (Make)
grant usage on schema public to anon, authenticated;
grant select on public.busy_times, public.google_calendars to anon, authenticated;