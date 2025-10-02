-- 0015_backfill_slot_type.sql
-- Backfill slot_type for any existing schedule_slots where it's NULL.
-- Rules (Europe/London local time):
--   FULL_DAY  → duration >= 6 hours
--   AM        → starts < 12:00 local
--   PM        → starts >= 12:00 local
-- Leaves existing non-null slot_type values untouched.

-- A) Classify by duration first (long → FULL_DAY)
with to_fill as (
  select id,
         (ends_at - starts_at) as dur,
         (starts_at at time zone 'Europe/London')::time as start_local_time
  from public.schedule_slots
  where slot_type is null
)
update public.schedule_slots s
set slot_type = 'FULL_DAY'::slot_type_enum
from to_fill tf
where s.id = tf.id
  and tf.dur >= interval '6 hours'
  and s.slot_type is null;

-- B) Remaining NULLs → AM or PM by local start time
with to_fill as (
  select id,
         (starts_at at time zone 'Europe/London')::time as start_local_time
  from public.schedule_slots
  where slot_type is null
)
update public.schedule_slots s
set slot_type = case
                  when tf.start_local_time < time '12:00' then 'AM'::slot_type_enum
                  else 'PM'::slot_type_enum
                end
from to_fill tf
where s.id = tf.id
  and s.slot_type is null;

-- C) Optional housekeeping: backfill the legacy text 'location' from locations (if blank)
update public.schedule_slots s
set location = l.name
from public.locations l
where s.location_id = l.id
  and (s.location is null or s.location = '');

-- D) (Optional) Enforce NOT NULL after backfill if safe
do $$
declare
  missing int;
begin
  select count(*) into missing from public.schedule_slots where slot_type is null;
  if missing = 0 then
    alter table public.schedule_slots alter column slot_type set not null;
  end if;
end$$;