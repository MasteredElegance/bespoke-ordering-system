-- 0012_locations_and_v2_rpcs.sql
-- Adds a proper locations table and links schedule_slots to it.
-- Provides v2 timezone RPCs that include location_code and location_name.

-- A) Locations master
create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,          -- e.g. 'studio', 'client-home', 'showroom-mayfair'
  name text not null,                 -- Display name: 'Studio', 'Client Home', 'Showroom – Mayfair'
  address_line1 text,
  address_line2 text,
  city text,
  postcode text,
  country text,
  timezone text not null default 'Europe/London',
  active boolean not null default true,
  created_at timestamptz default now()
);

-- B) Seed a default Studio location (idempotent)
insert into public.locations (code, name, timezone)
values ('studio', 'Studio', 'Europe/London')
on conflict (code) do nothing;

-- C) Link schedule_slots to locations
alter table public.schedule_slots
  add column if not exists location_id uuid;

-- Backfill existing text-based slots to Studio
update public.schedule_slots s
set location_id = (select id from public.locations where code = 'studio')
where (s.location_id is null) and (s.location ilike 'studio');

-- If any slots still null, optionally default them to Studio too
update public.schedule_slots s
set location_id = (select id from public.locations where code = 'studio')
where s.location_id is null;

-- Enforce FK (after backfill)
alter table public.schedule_slots
  add constraint schedule_slots_location_id_fkey
  foreign key (location_id) references public.locations(id) on delete restrict;

-- Optional: keep the old text column for now (backward compat). We will deprecate it later.

-- D) Helpful indexes
create index if not exists idx_locations_active on public.locations (active);
create index if not exists idx_schedule_slots_location_time on public.schedule_slots (location_id, starts_at);

-- E) New function & RPCs that include location details (v2)

-- E1) Core function v2: availability with locations
create or replace function public.get_available_slots_v2(
  dfrom date,
  dto   date
)
returns table (
  slot_code text,
  starts_at timestamptz,
  ends_at   timestamptz,
  location_id uuid,
  location_code text,
  location_name text
)
language sql
stable
as $$
  select
    s.slot_code,
    s.starts_at,
    s.ends_at,
    s.location_id,
    l.code  as location_code,
    l.name  as location_name
  from public.schedule_slots s
  join public.locations l on l.id = s.location_id and l.active = true
  where s.status = 'open'
    and s.starts_at >= dfrom
    and s.ends_at   <  (dto + 1)
    and not exists (
      select 1
      from public.busy_times b
      where public.ranges_overlap(s.starts_at, s.ends_at, b.starts_at, b.ends_at)
    )
  order by s.starts_at;
$$;

-- E2) TZ RPC v2 (all locations)
create or replace function public.rpc_get_available_slots_tz_v2(
  dfrom date,
  dto   date,
  tz    text default 'Europe/London'
)
returns table (
  slot_code       text,
  starts_at_utc   timestamptz,
  ends_at_utc     timestamptz,
  starts_local    timestamp,
  ends_local      timestamp,
  location_id     uuid,
  location_code   text,
  location_name   text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    v.slot_code,
    v.starts_at as starts_at_utc,
    v.ends_at   as ends_at_utc,
    (v.starts_at at time zone tz) as starts_local,
    (v.ends_at   at time zone tz) as ends_local,
    v.location_id,
    v.location_code,
    v.location_name
  from public.get_available_slots_v2(dfrom, dto) v
  order by v.starts_at;
$$;

-- E3) TZ RPC v2 with location filter by code
create or replace function public.rpc_get_available_slots_by_location_tz_v2(
  dfrom date,
  dto   date,
  p_location_code text,
  tz    text default 'Europe/London'
)
returns table (
  slot_code       text,
  starts_at_utc   timestamptz,
  ends_at_utc     timestamptz,
  starts_local    timestamp,
  ends_local      timestamp,
  location_id     uuid,
  location_code   text,
  location_name   text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    v.slot_code,
    v.starts_at as starts_at_utc,
    v.ends_at   as ends_at_utc,
    (v.starts_at at time zone tz) as starts_local,
    (v.ends_at   at time zone tz) as ends_local,
    v.location_id,
    v.location_code,
    v.location_name
  from public.get_available_slots_v2(dfrom, dto) v
  where (p_location_code is null or v.location_code = p_location_code)
  order by v.starts_at;
$$;

-- Notes:
-- - We keep your existing RPCs (backward compatible).
-- - New v2 RPCs add location_id/code/name for richer UI filtering.