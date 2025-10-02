-- 0009_available_slots_rpcs.sql
-- RPC wrappers for available slots

-- A) RPC: rpc_get_available_slots(dfrom, dto)
create or replace function public.rpc_get_available_slots(
  dfrom date,
  dto   date
)
returns table (
  slot_code text,
  starts_at timestamptz,
  ends_at   timestamptz,
  location  text
)
language sql
stable
security definer
set search_path = public
as $$
  select * from public.get_available_slots(dfrom, dto);
$$;


-- B) RPC with location filter
create or replace function public.rpc_get_available_slots_by_location(
  dfrom date,
  dto   date,
  p_location text
)
returns table (
  slot_code text,
  starts_at timestamptz,
  ends_at   timestamptz,
  location  text
)
language sql
stable
security definer
set search_path = public
as $$
  select s.slot_code, s.starts_at, s.ends_at, s.location
  from public.get_available_slots(dfrom, dto) s
  where (p_location is null or s.location = p_location)
  order by s.starts_at;
$$;