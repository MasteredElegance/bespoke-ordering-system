-- 0006_busy_times_event_id.sql
-- Add Google event id so we can upsert/delete reliably

alter table public.busy_times
  add column if not exists external_event_id text not null;

-- one row per (calendar, event)
create unique index if not exists uq_busy_times_event
  on public.busy_times (source_calendar_id, external_event_id);

-- helpful read index
create index if not exists idx_busy_times_event_lookup
  on public.busy_times (external_event_id);

-- (busy_times already has grants; service role will write)