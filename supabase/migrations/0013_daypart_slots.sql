-- 0013_daypart_slots.sql
-- Adds slot_type (AM/PM/FULL_DAY) and a generator for daypart slots.

-- A) Enum for slot types (idempotent pattern)
do $$
begin
  if not exists (select 1 from pg_type where typname = 'slot_type_enum') then
    create type slot_type_enum as enum ('AM','PM','FULL_DAY');
  end if;
end$$;

-- B) Add column to schedule_slots
alter table public.schedule_slots
  add column if not exists slot_type slot_type_enum;

-- C) Helpful partial index by type (optional)
create index if not exists idx_schedule_slots_type_time
  on public.schedule_slots (slot_type, starts_at);

-- D) Generator: create AM/PM/FULL_DAY slots in a local timezone, stored as UTC
--   - dfrom..dto dates inclusive
--   - weekdays: array of DOW ints (Sun=0..Sat=6)
--   - dayparts: array of text values in ('AM','PM','FULL_DAY')
--   - workday anchors (local time): am_start, am_end, pm_start, pm_end, full_start, full_end
create or replace function public.generate_daypart_slots(
  dfrom date,
  dto   date,
  weekdays int[] default array[1,2,3,4,5],                -- Mon..Fri
  dayparts text[] default array['AM','PM'],                -- which to create
  tz text default 'Europe/London',
  am_start time default '09:00', am_end time default '12:00',
  pm_start time default '13:00', pm_end time default '16:00',
  full_start time default '09:00', full_end time default '17:00',
  location_code text default 'studio'                      -- ties to public.locations(code)
) returns int
language plpgsql
as $$
declare
  d date;
  part text;
  start_local timestamp;
  end_local   timestamp;
  start_utc   timestamptz;
  end_utc     timestamptz;
  loc_id uuid;
  inserted int := 0;
  slotcode text;
begin
  -- resolve location_id from code
  select id into loc_id from public.locations where code = location_code and active = true;
  if loc_id is null then
    raise exception 'Location code % not found or inactive in public.locations', location_code;
  end if;

  for d in select generate_series(dfrom, dto, interval '1 day')::date loop
    continue when extract(dow from d)::int <> any(weekdays);

    foreach part in array dayparts loop
      if part = 'AM' then
        start_local := (d::timestamp + am_start);
        end_local   := (d::timestamp + am_end);
      elsif part = 'PM' then
        start_local := (d::timestamp + pm_start);
        end_local   := (d::timestamp + pm_end);
      elsif part = 'FULL_DAY' then
        start_local := (d::timestamp + full_start);
        end_local   := (d::timestamp + full_end);
      else
        continue; -- ignore unknown values
      end if;

      -- convert local -> UTC timestamptz for storage
      start_utc := (start_local at time zone tz);
      end_utc   := (end_local   at time zone tz);

      -- dedupe by exact window & location
      if not exists (
        select 1 from public.schedule_slots s
        where s.location_id = loc_id and s.starts_at = start_utc and s.ends_at = end_utc
      ) then
        slotcode := upper(location_code) || '-' || to_char(d, 'YYYYMMDD') || '-' || part;

        insert into public.schedule_slots (slot_code, starts_at, ends_at, status, location_id, slot_type, location)
        values (
          slotcode,
          start_utc,
          end_utc,
          'open',
          loc_id,
          part::slot_type_enum,
          (select name from public.locations where id = loc_id) -- legacy text column (kept for now)
        );

        inserted := inserted + 1;
      end if;
    end loop;
  end loop;

  return inserted;
end;
$$;