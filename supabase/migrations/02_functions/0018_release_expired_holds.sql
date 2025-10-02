-- 0018_release_expired_holds.sql
-- feat(db): add helper function release_expired_holds()

set search_path = public;

create or replace function public.release_expired_holds()
returns void
language plpgsql
as $$
begin
  update public.schedule_slots s
     set status = 'open',
         held_by_customer_id = null,
         hold_expires_at = null
   where s.status = 'held'
     and s.hold_expires_at is not null
     and s.hold_expires_at < now();
end;
$$;
