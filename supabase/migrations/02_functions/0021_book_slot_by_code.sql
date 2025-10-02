-- 0021_book_slot_by_code.sql
-- Add a book_slot variant that accepts human-readable slot_code (text).
-- Validates reservation and hold ownership, then books and confirms.

set search_path = public;

create or replace function public.book_slot(
  p_slot_code       text,
  p_reservation_id  uuid
)
returns table (
  reservation_id   uuid,
  reservation_code text,
  slot_code        text,
  starts_at        timestamptz,
  ends_at          timestamptz,
  reservation_status text
)
language plpgsql
security definer
as $$
declare
  v_slot_id      uuid;
  v_slot_status  text;
  v_held_by      uuid;
  v_expires_at   timestamptz;
  v_starts_at    timestamptz;
  v_ends_at      timestamptz;

  v_res_cust_id  uuid;
  v_res_status   text;
  v_res_code     text;
begin
  -- 1) Load slot
  select id, status, held_by_customer_id, hold_expires_at, starts_at, ends_at
    into v_slot_id, v_slot_status, v_held_by, v_expires_at, v_starts_at, v_ends_at
  from public.schedule_slots
  where slot_code = p_slot_code
  limit 1;

  if v_slot_id is null then
    raise exception 'Slot % not found', p_slot_code using errcode = 'P0001';
  end if;

  -- 2) Load reservation
  select customer_id, status, reservation_code
    into v_res_cust_id, v_res_status, v_res_code
  from public.reservations
  where id = p_reservation_id
  limit 1;

  if v_res_cust_id is null then
    raise exception 'Reservation % not found', p_reservation_id using errcode = 'P0001';
  end if;

  if v_res_status is distinct from 'pending' then
    raise exception 'Reservation % is not pending (current: %)', p_reservation_id, v_res_status
      using errcode = 'P0001';
  end if;

  -- 3) Validate slot is held and not expired
  if v_slot_status is distinct from 'held' then
    raise exception 'Slot % is not held (current: %)', p_slot_code, v_slot_status using errcode = 'P0001';
  end if;

  if v_expires_at is null or v_expires_at <= now() then
    -- clean up and report
    perform public.release_expired_holds();
    raise exception 'Hold on slot % has expired', p_slot_code using errcode = 'P0001';
  end if;

  -- 4) Enforce ownership: if hold is attributed to someone, it must match reservation.customer_id
  if v_held_by is not null and v_held_by <> v_res_cust_id then
    raise exception 'Slot % is held by a different customer', p_slot_code using errcode = 'P0001';
  end if;

  -- 5) Book the slot (only if still held by same customer / or un-attributed)
  update public.schedule_slots s
     set status = 'booked',
         held_by_customer_id = null,
         hold_expires_at = null
   where s.id = v_slot_id
     and s.status = 'held'
     and (s.held_by_customer_id is null or s.held_by_customer_id = v_res_cust_id);

  if not found then
    raise exception 'Slot % could not be booked (state changed)', p_slot_code using errcode = 'P0001';
  end if;

  -- 6) Confirm reservation and attach slot_code
  update public.reservations r
     set status   = 'confirmed',
         slot_code = p_slot_code
   where r.id = p_reservation_id;

  if not found then
    raise exception 'Reservation % could not be updated', p_reservation_id using errcode = 'P0001';
  end if;

  -- 7) Return a helpful row
  reservation_id := p_reservation_id;
  reservation_code := v_res_code;
  slot_code := p_slot_code;
  starts_at := v_starts_at;
  ends_at := v_ends_at;
  reservation_status := 'confirmed';
  return next;
end;
$$;