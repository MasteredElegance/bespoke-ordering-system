-- 0024_reservations_defaults.sql
-- Add safe default values so inserts never fail

alter table public.reservations
  alter column requested_service set default 'unspecified',
  alter column status set default 'pending';