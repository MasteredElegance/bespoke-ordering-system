-- 0007_metadata_calendar_sync.sql
-- Lightweight metadata note so DB + automations stay in lockstep.

create table if not exists public.metadata (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz default now()
);

insert into public.metadata (key, value)
values (
  'calendar_sync',
  jsonb_build_object(
    'scenario', 'bespoke-ordering-system__calendar__sync-gcal-to-supabase',
    'version', 'v1',
    'notes', 'Google Calendar events mirrored into public.busy_times via Make.com'
  )
)
on conflict (key) do update
set value = excluded.value,
    updated_at = now();