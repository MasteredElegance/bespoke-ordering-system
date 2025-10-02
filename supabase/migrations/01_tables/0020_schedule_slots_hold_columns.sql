-- 0020_schedule_slots_hold_columns.sql
-- Ensure hold columns + indexes exist on schedule_slots, and (re)create cleanup function.

set search_path = public;

-- A) Columns (idempotent)
alter table public.schedule_slots
  add column if not exists held_by_customer_id uuid,
  add column if not exists hold_expires_at    timestamptz;

-- B) Helpful indexes (idempotent)
create index if not exists idx_schedule_slots_hold_expiry
  on public.schedule_slots (hold_expires_at);

create unique index if not exists uq_schedule_slots_code
  on public.schedule_slots (slot_code);

-- C) Canonical cleanup function (void)
drop function if exists public.release_expired_holds();

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