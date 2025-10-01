-- 1) Function: get_available_slots(dfrom, dto)
-- Returns only 'open' schedule_slots that do NOT overlap any busy_times
create or replace function public.get_available_slots(
  dfrom date,
  dto   date
)
returns table (
  slot_code text,
  starts_at timestamptz,
  ends_at   timestamptz,
  location  text
)
language sql
stable
as $$
  select s.slot_code, s.starts_at, s.ends_at, s.location
  from public.schedule_slots s
  where s.status = 'open'
    and s.starts_at >= dfrom
    and s.ends_at   <  (dto + 1)  -- inclusive end-day
    and not exists (
      select 1
      from public.busy_times b
      where b.source_calendar_id is not null
        and public.ranges_overlap(s.starts_at, s.ends_at, b.starts_at, b.ends_at)
    )
  order by s.starts_at;
$$;


-- 2) View: available_slots_next_14
-- Convenience view for the app to read “what’s bookable in the next 14 days”
create or replace view public.available_slots_next_14 as
select *
from public.get_available_slots(current_date, current_date + 14);


-- 3) Helpful index (if not already present)
-- Speeds up the date range + status filter on schedule_slots
create index if not exists idx_schedule_slots_open_window
  on public.schedule_slots (status, starts_at, ends_at);