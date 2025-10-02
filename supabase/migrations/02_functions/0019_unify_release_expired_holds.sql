-- 0019_unify_release_expired_holds.sql
-- Ensure a single canonical definition of release_expired_holds() returning void.

set search_path = public;

-- Drop any existing version (regardless of prior return type)
drop function if exists public.release_expired_holds();

-- Recreate canonical version (void)
create or replace function public.release_expired_holds()
returns void
language sql
security definer
set search_path = public
as $$
  update public.schedule_slots s
     set status = 'open',
         held_by_customer_id = null,
         hold_expires_at = null
   where s.status = 'held'
     and s.hold_expires_at is not null
     and s.hold_expires_at < now();
$$;