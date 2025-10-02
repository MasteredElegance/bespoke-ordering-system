-- 0014_seed_showroom_mayfair.sql
-- Adds a second location (Showroom – Mayfair) and seeds a few AM/PM slots using the daypart generator.
-- Requires 0012 (locations) and 0013 (daypart generator) to have run.

-- A) Upsert the new location
insert into public.locations (code, name, address_line1, city, postcode, country, timezone, active)
values ('showroom-mayfair', 'Showroom – Mayfair', '10 Hanover St', 'London', 'W1S 1YZ', 'UK', 'Europe/London', true)
on conflict (code) do update
  set name = excluded.name,
      address_line1 = excluded.address_line1,
      city = excluded.city,
      postcode = excluded.postcode,
      country = excluded.country,
      timezone = excluded.timezone,
      active = excluded.active;

-- B) Generate next 5 weekdays of AM and PM slots for the showroom (idempotent by exact window)
-- Uses the generator from 0013 (generate_daypart_slots)
select public.generate_daypart_slots(
  dfrom := current_date + 1,
  dto   := current_date + 7,
  weekdays := array[1,2,3,4,5],      -- Mon..Fri
  dayparts := array['AM','PM'],
  tz := 'Europe/London',
  am_start := '09:00', am_end := '12:00',
  pm_start := '13:00', pm_end := '16:00',
  location_code := 'showroom-mayfair'
);