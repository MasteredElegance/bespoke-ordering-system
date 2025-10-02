-- 0010_available_slots_timezone.sql
-- Timezone-aware RPCs for available slots.
-- Returns both UTC and local-time projections so the app can display correctly.

-- A) RPC: rpc_get_available_slots_tz(dfrom, dto, tz)
-- tz example: 'Europe/London' (IANA tz name)
create or replace function public.rpc_get_available_slots_tz(
  dfrom date,
  dto   date,
  tz    text default 'Europe/London'
)
returns table (
  slot_code       text,
  starts_at_utc   timestamptz,
  ends_at_utc     timestamptz,
  starts_local    timestamp,    -- local wall clock time in tz
  ends_local      timestamp,    -- local wall clock time in tz
  location        text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.slot_code,
    s.starts_at as starts_at_utc,
    s.ends_at   as ends_at_utc,
    (s.starts_at at time zone tz) as starts_local,
    (s.ends_at   at time zone tz) as ends_local,
    s.location
  from public.get_available_slots(dfrom, dto) s
  order by s.starts_at;
$$;


-- B) RPC with location filter + tz
create or replace function public.rpc_get_available_slots_by_location_tz(
  dfrom date,
  dto   date,
  p_location text,
  tz    text default 'Europe/London'
)
returns table (
  slot_code       text,
  starts_at_utc   timestamptz,
  ends_at_utc     timestamptz,
  starts_local    timestamp,
  ends_local      timestamp,
  location        text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.slot_code,
    s.starts_at as starts_at_utc,
    s.ends_at   as ends_at_utc,
    (s.starts_at at time zone tz) as starts_local,
    (s.ends_at   at time zone tz) as ends_local,
    s.location
  from public.get_available_slots(dfrom, dto) s
  where (p_location is null or s.location = p_location)
  order by s.starts_at;
$$;

-- Notes:
-- - schedule_slots.starts_at/ends_at are timestamptz (UTC). We project both UTC and local.
-- - "AT TIME ZONE tz" returns timestamp (without tz) in that local wall clock for display.