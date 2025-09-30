-- 0005_generate_slots.sql
-- Helpers to generate schedule slots while avoiding busy times

create or replace function public.ranges_overlap(
  a_start timestamptz, a_end timestamptz,
  b_start timestamptz, b_end timestamptz
) returns boolean language sql immutable as $$
  select tstzrange(a_start, a_end) && tstzrange(b_start, b_end)
$$;

create or replace function public.generate_slots_excluding_busy(
  dfrom date, dto date, slot_minutes int, weekdays int[], tz text default 'Europe/London',
  work_start time default '10:00', work_end time default '16:00', location text default 'Studio'
) returns int
language plpgsql
as $$
declare
  d date;
  slot_start timestamptz;
  slot_end   timestamptz;
  inserted   int := 0;
begin
  for d in select generate_series(dfrom, dto, interval '1 day')::date loop
    continue when extract(dow from d)::int <> any(weekdays);

    slot_start := (d::timestamptz at time zone tz) + work_start;
    while (slot_start::time < work_end) loop
      slot_end := slot_start + make_interval(mins => slot_minutes);

      if not exists (
        select 1 from public.busy_times bt
        where ranges_overlap(slot_start, slot_end, bt.starts_at, bt.ends_at)
      )
      and not exists (
        select 1 from public.schedule_slots s
        where s.starts_at = slot_start and s.ends_at = slot_end
      ) then
        insert into public.schedule_slots (slot_code, starts_at, ends_at, location, status)
        values (public.next_code('SLOT'), slot_start, slot_end, location, 'open');
        inserted := inserted + 1;
      end if;

      slot_start := slot_end;
    end loop;
  end loop;

  return inserted;
end;
$$;