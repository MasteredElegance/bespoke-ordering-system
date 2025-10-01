-- A) RPC: rpc_get_available_slots(dfrom, dto)
-- Thin wrapper over public.get_available_slots for PostgREST
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


-- B) RPC with location filter (optional): rpc_get_available_slots_by_location
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


-- C) Helpful policy for read-only access (if you want anon/auth to read)
-- Comment these out if you prefer server-only access.
do $$
begin
  -- enable RLS if not already
  perform 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='schedule_slots' and c.relrowsecurity;
  -- expose only SELECT via RPCs and view is safe (function is STABLE, no writes)
  -- Nothing to do if your API role already can execute functions.
end $$;