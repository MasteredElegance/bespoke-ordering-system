-- 0011_seed_schedule_slots.sql
-- Seed open Studio slots (weekdays, 09:00–16:00 UK time), for the next 7 days.
-- Slots are stored as UTC (timestamptz) using Europe/London local wall-clock.

with gen as (
  select
    d::date                                        as d,
    h::int                                         as h,
    concat('STUDIO-', to_char(d::date,'YYYYMMDD'), '-', lpad(h::text,2,'0')) as slot_code,
    -- local "Europe/London" -> timestamptz (UTC) for storage
    ((d + make_time(h,0,0))::timestamp at time zone 'Europe/London')          as starts_at,
    (((d + make_time(h,0,0))::timestamp + interval '1 hour') at time zone 'Europe/London') as ends_at,
    'open'::text                                   as status,
    'Studio'::text                                 as location
  from generate_series(current_date + 1, current_date + 7, interval '1 day') d
  cross join generate_series(9,16,1) h   -- 09:00..16:00 inclusive
  where extract(dow from d) not in (0,6) -- exclude Sun(0) & Sat(6)
)
insert into public.schedule_slots (slot_code, starts_at, ends_at, status, location)
select g.slot_code, g.starts_at, g.ends_at, g.status, g.location
from gen g
left join public.schedule_slots s on s.slot_code = g.slot_code
where s.slot_code is null;  -- idempotent: re-running won't duplicate