-- 0001_reservations_schema.sql
-- Foundation schema for the Bespoke Ordering System (reservation layer)

-- Customers (basic profile; auth linkage comes later)
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  customer_code text unique not null,
  first_name text not null,
  last_name text not null,
  email text not null,
  phone text,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists idx_customers_email on public.customers (lower(email));

-- Reservations (entry point of the workflow)
create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  reservation_code text unique not null,
  customer_id uuid not null references public.customers(id) on delete restrict,
  status text not null check (status in ('pending','offered','accepted','scheduled','cancelled','expired')),
  requested_service text not null,     -- e.g. lounge_coat, full_suit, alterations
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists idx_reservations_customer_id on public.reservations (customer_id);
create index if not exists idx_reservations_status on public.reservations (status);

-- Versioned agreements (T&Cs captured per reservation)
create table if not exists public.reservation_agreements (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  version text not null,               -- e.g. AGREE-2025-09-v1
  accepted boolean not null default false,
  accepted_at timestamptz
);

create index if not exists idx_reservation_agreements_reservation_id on public.reservation_agreements (reservation_id);

-- Offerable/schedulable measuring slots
create table if not exists public.schedule_slots (
  id uuid primary key default gen_random_uuid(),
  slot_code text unique not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location text not null default 'Studio',
  status text not null check (status in ('open','held','booked','blocked')),
  held_by_reservation uuid references public.reservations(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint slot_time_valid check (ends_at > starts_at)
);

create index if not exists idx_schedule_slots_status on public.schedule_slots (status);
create index if not exists idx_schedule_slots_starts_at on public.schedule_slots (starts_at);
create index if not exists idx_schedule_slots_held_by on public.schedule_slots (held_by_reservation);

-- Payments (Stripe or other provider; Supabase is source of truth)
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  amount_pennies integer not null check (amount_pennies >= 0), -- store money as integer
  currency text not null default 'GBP',
  kind text not null check (kind in ('deposit','balance','refund')),
  provider text not null default 'stripe',
  provider_ref text,                           -- payment_intent / charge id
  status text not null check (status in ('requires_payment','succeeded','failed','refunded')),
  created_at timestamptz not null default now()
);

create index if not exists idx_payments_reservation_id on public.payments (reservation_id);
create index if not exists idx_payments_status on public.payments (status);

-- Helpful uniques (codes)
create unique index if not exists uq_customers_customer_code on public.customers (customer_code);
create unique index if not exists uq_reservations_reservation_code on public.reservations (reservation_code);
create unique index if not exists uq_schedule_slots_slot_code on public.schedule_slots (slot_code);