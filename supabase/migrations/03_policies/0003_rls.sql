-- 0003_rls.sql
-- Minimal Row-Level Security (RLS) for the reservation layer.
-- Notes:
-- - Service Role key in Supabase bypasses RLS automatically (Make/Server).
-- - We link app users to customers via customers.user_id = auth.uid().
-- - Schedule slots are readable by everyone; updates allowed for authenticated (tighten later if needed).

-- 1) Link auth users to customers
alter table public.customers
  add column if not exists user_id uuid;

create unique index if not exists uq_customers_user_id on public.customers(user_id);

-- 2) Enable RLS on all tables
alter table public.customers enable row level security;
alter table public.reservations enable row level security;
alter table public.reservation_agreements enable row level security;
alter table public.schedule_slots enable row level security;
alter table public.payments enable row level security;

-- 3) Customers policies (owner = auth user)
drop policy if exists "customers_select_own" on public.customers;
drop policy if exists "customers_modify_own" on public.customers;
create policy "customers_select_own"
  on public.customers
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "customers_modify_own"
  on public.customers
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 4) Reservations policies (via owning customer)
drop policy if exists "reservations_owner" on public.reservations;
create policy "reservations_owner"
  on public.reservations
  for all
  to authenticated
  using (
    customer_id in (
      select c.id from public.customers c
      where c.user_id = auth.uid()
    )
  )
  with check (
    customer_id in (
      select c.id from public.customers c
      where c.user_id = auth.uid()
    )
  );

-- 5) Reservation agreements (via reservation → customer)
drop policy if exists "agreements_owner" on public.reservation_agreements;
create policy "agreements_owner"
  on public.reservation_agreements
  for all
  to authenticated
  using (
    reservation_id in (
      select r.id
      from public.reservations r
      join public.customers c on c.id = r.customer_id
      where c.user_id = auth.uid()
    )
  )
  with check (
    reservation_id in (
      select r.id
      from public.reservations r
      join public.customers c on c.id = r.customer_id
      where c.user_id = auth.uid()
    )
  );

-- 6) Payments (via reservation → customer)
drop policy if exists "payments_owner" on public.payments;
create policy "payments_owner"
  on public.payments
  for all
  to authenticated
  using (
    reservation_id in (
      select r.id
      from public.reservations r
      join public.customers c on c.id = r.customer_id
      where c.user_id = auth.uid()
    )
  )
  with check (
    reservation_id in (
      select r.id
      from public.reservations r
      join public.customers c on c.id = r.customer_id
      where c.user_id = auth.uid()
    )
  );

-- 7) Schedule slots
-- Readable by anyone (lets you show availability pre-login if you want)
drop policy if exists "slots_read_all" on public.schedule_slots;
create policy "slots_read_all"
  on public.schedule_slots
  for select
  to anon, authenticated
  using (true);

-- Allow authenticated users to update (hold/book) via RPCs for now.
-- (Later we can tighten with SECURITY DEFINER RPCs + specific checks.)
drop policy if exists "slots_update_auth" on public.schedule_slots;
create policy "slots_update_auth"
  on public.schedule_slots
  for update
  to authenticated
  using (true)
  with check (true);

-- Schedule slots: insert & delete (one command per policy)

-- INSERT
drop policy if exists "slots_insert_auth" on public.schedule_slots;
create policy "slots_insert_auth"
  on public.schedule_slots
  for insert
  to authenticated
  with check (true);

-- DELETE
drop policy if exists "slots_delete_auth" on public.schedule_slots;
create policy "slots_delete_auth"
  on public.schedule_slots
  for delete
  to authenticated
  using (true);