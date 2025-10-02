-- 0017_fix_hold_slot_raise.sql
-- Fix RAISE EXCEPTION formatting in hold_slot (pass slot_code parameter).

create or replace function public.hold_slot(
  p_slot_code   text,
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
  -- Release any expired holds (cheap housekeeping)
  perform public.release_expired_holds();

  -- Try to place a hold only if slot is currently 'open'
  update public.schedule_slots s
     set status = 'held',
         held_by_customer_id = p_customer_id,
         hold_expires_at     = v_expires
   where s.slot_code = p_slot_code
     and s.status = 'open'
  returning s.slot_code, s.starts_at, s.ends_at, s.hold_expires_at
  into slot_code, starts_at, ends_at, hold_expires_at;

  if slot_code is null then
    -- ✅ pass the parameter for the % placeholder:
    RAISE EXCEPTION 'Slot % is not available to hold', p_slot_code
      USING ERRCODE = 'P0001';
  end if;

  return next;
end;
$$;