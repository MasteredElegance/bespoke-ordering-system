-- 0002_rpcs.sql
-- Codes + simple slot offering helpers

-- A tiny counters table for daily sequences (idempotent create)
create table if not exists public.counters(
  scope text primary key,
  value int not null default 0,
  updated_at timestamptz not null default now()
);

-- next_code('CUS') -> CUS-YYYYMMDD-###
create or replace function public.next_code(prefix text)
returns text
language plpgsql
as $$
declare
  ymd text := to_char((now() at time zone 'Europe/London'), 'YYYYMMDD');
  key text := prefix||'-'||ymd;
  seq int;
begin
  insert into public.counters(scope,value)
  values (key, 0)
  on conflict (scope) do nothing;

  update public.counters
     set value = value + 1, updated_at = now()
   where scope = key
   returning value into seq;

  return format('%s-%s-%03s', prefix, ymd, seq);
end;
$$;

-- Offer the next N open slots from a timepoint, and mark the reservation as 'offered'
create or replace function public.offer_slots(res_id uuid, from_ts timestamptz, limit_n int default 5)
returns setof public.schedule_slots
language sql
as $$
  update public.reservations
     set status = 'offered'
   where id = res_id;

  select *
    from public.schedule_slots
   where status = 'open'
     and starts_at >= from_ts
   order by starts_at
   limit limit_n;
$$;

-- Hold a slot for a reservation (UI should release after ~30 mins if not taken)
create or replace function public.hold_slot(slot_id uuid, res_id uuid)
returns public.schedule_slots
language sql
as $$
  update public.schedule_slots
     set status = 'held',
         held_by_reservation = res_id
   where id = slot_id
     and status = 'open'
  returning *;
$$;

-- Book a held slot and mark reservation as scheduled
create or replace function public.book_slot(slot_id uuid, res_id uuid)
returns public.schedule_slots
language plpgsql
as $$
declare
  s public.schedule_slots;
begin
  update public.schedule_slots
     set status = 'booked'
   where id = slot_id
     and (status = 'held' and held_by_reservation = res_id)
  returning * into s;

  if not found then
    raise exception 'Slot not held by this reservation or not holdable';
  end if;

  update public.reservations
     set status = 'scheduled'
   where id = res_id;

  return s;
end;
$$;