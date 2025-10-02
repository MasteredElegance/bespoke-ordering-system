-- 0023_reservations_add_slot_code.sql
-- Add slot_code on reservations and enforce sensible constraints.

set search_path = public;

-- 1) Add the column (nullable until booking)
alter table public.reservations
  add column if not exists slot_code text;

-- 2) Optional FK: keep codes in sync with schedule_slots
--    Using ON UPDATE CASCADE lets you rename a slot_code safely (rare).
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fk_reservations_slot_code__schedule_slots'
  ) then
    alter table public.reservations
      add constraint fk_reservations_slot_code__schedule_slots
      foreign key (slot_code)
      references public.schedule_slots (slot_code)
      on update cascade
      on delete set null;
  end if;
end $$;

-- 3) Prevent two confirmed reservations pointing at the same slot
--    (allows duplicates while 'pending', but enforces uniqueness when 'confirmed').
create unique index if not exists uq_reservations_slot_code_when_confirmed
  on public.reservations (slot_code)
  where status = 'confirmed';

-- 4) Helpful index for lookups by slot_code regardless of status
create index if not exists ix_reservations_slot_code
  on public.reservations (slot_code);