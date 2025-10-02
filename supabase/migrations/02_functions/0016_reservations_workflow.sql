-- 0016_reservations_workflow.sql
-- Hold → auto-release → book workflow for schedule slots.

-- A) Columns for holding
alter table public.schedule_slots
  add column if not exists held_by_customer_id uuid,
  add column if not exists hold_expires_at    timestamptz;

-- Helpful indexes
create index if not exists idx_schedule_slots_hold_expiry
  on public.schedule_slots (hold_expires_at);
create unique index if not exists uq_schedule_slots_code
  on public.schedule_slots (slot_code);

-- B) Housekeeping: release expired holds
create or replace function public.release_expired_holds()
returns int
language sql
security definer
set search_path = public
as $$
  with rel as (
    update public.schedule_slots s
       set held_by_customer_id = null,
           hold_expires_at     = null,
           status              = 'open'
     where s.status = 'held'
       and s.hold_expires_at is not null
       and s.hold_expires_at <= now()
     returning 1
  )
  select count(*)::int from rel;
$$;

-- C) RPC: hold a slot for a customer (defaults to 20 minutes)
-- Uses slot_code for UX simplicity; dedup via unique index.
create or replace function public.hold_slot(
  p_slot_code text,
  p_customer_id uuid,
  p_hold_minutes int default 20
) returns table (
  slot_code text,
  starts_at timestamptz,
  ends_at   timestamptz,
  hold_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expires timestamptz := now() + make_interval(mins => greatest(p_hold_minutes, 5));
begin
  -- First, release any expired holds globally (cheap)
  perform public.release_expired_holds();

  -- Attempt to place a hold only if the slot is 'open'
  update public.schedule_slots s
     set status = 'held',
         held_by_customer_id = p_customer_id,
         hold_expires_at     = v_expires
   where s.slot_code = p_slot_code
     and s.status = 'open'
  returning s.slot_code, s.starts_at, s.ends_at, s.hold_expires_at
  into slot_code, starts_at, ends_at, hold_expires_at;

  if slot_code is null then
    raise exception 'Slot % is not available to hold' using errcode = 'P0001';
  end if;

  return next;
end;
$$;

-- D) RPC: book a slot into a reservation
-- Preconditions:
--   - slot exists and is 'held' by the same customer, and not expired
--   - the reservation row exists and belongs to that customer_id (owner check)
-- Effects:
--   - slot becomes 'booked'
--   - reservation.status -> 'confirmed'
--   - reservation gets a reference to slot_code (for simplicity)
alter table public.reservations
  add column if not exists slot_code text;

create or replace function public.book_slot(
  p_slot_code   text,
  p_reservation_id uuid,
  p_customer_id uuid
) returns table (
  reservation_id uuid,
  reservation_code text,
  slot_code text,
  starts_at timestamptz,
  ends_at   timestamptz,
  status    text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_starts timestamptz;
  v_ends   timestamptz;
  v_res_code text;
begin
  -- Release any expired holds first
  perform public.release_expired_holds();

  -- Verify the slot is held by this customer and not expired
  select s.starts_at, s.ends_at
    into v_starts, v_ends
  from public.schedule_slots s
  where s.slot_code = p_slot_code
    and s.status = 'held'
    and s.held_by_customer_id = p_customer_id
    and (s.hold_expires_at is null or s.hold_expires_at > now())
  for update;

  if v_starts is null then
    raise exception 'Slot % is not held by this customer or hold expired', p_slot_code using errcode = 'P0001';
  end if;

  -- Ensure reservation exists and belongs to the same customer (owner check)
  perform 1
  from public.reservations r
  join public.customers c on c.id = r.customer_id
  where r.id = p_reservation_id
    and r.customer_id = p_customer_id
  for update;

  if not found then
    raise exception 'Reservation does not exist or does not belong to this customer' using errcode = 'P0001';
  end if;

  -- Book the slot and attach to reservation
  update public.schedule_slots s
     set status = 'booked',
         hold_expires_at = null
   where s.slot_code = p_slot_code
     and s.status = 'held'
     and s.held_by_customer_id = p_customer_id;

  if not found then
    raise exception 'Failed to transition slot to booked (concurrency)' using errcode = 'P0001';
  end if;

  update public.reservations r
     set status = 'confirmed',
         slot_code = p_slot_code
   where r.id = p_reservation_id
  returning r.id, r.reservation_code, r.status
  into reservation_id, v_res_code, status;

  slot_code := p_slot_code;
  starts_at := v_starts;
  ends_at   := v_ends;

  return next;
end;
$$;

-- E) Optional: simple RPC to release a hold manually (e.g., user cancels)
create or replace function public.release_hold(
  p_slot_code text,
  p_customer_id uuid
) returns boolean
language sql
security definer
set search_path = public
as $$
  with rel as (
    update public.schedule_slots s
       set status = 'open',
           held_by_customer_id = null,
           hold_expires_at = null
     where s.slot_code = p_slot_code
       and s.status = 'held'
       and s.held_by_customer_id = p_customer_id
     returning 1
  )
  select exists(select 1 from rel);
$$;