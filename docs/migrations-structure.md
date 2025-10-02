# Bespoke Ordering System — Migration Structure

We follow the same discipline as MycoTrack: migrations are **sequentially numbered** (0001, 0002, …) but also **sectioned** into folders for clarity.  

This makes it easy to read, debug, and squash later into a clean `0001_init.sql` if needed.

---

## Folder Layout

---

## Numbering Rules

- **Never renumber old files** (keeps Git history stable).
- New migrations continue numbering (`0016`, `0017`, …).
- Place each new file into the correct section folder.
- If a migration covers more than one concern, file it under the **primary dependency** (e.g. table + function = put in `01_tables/`).

---

## Examples

- **0012_locations_and_v2_rpcs.sql** → `01_tables/`  
  (creates `locations` table + RPCs, but table is the dependency)

- **0015_backfill_slot_type.sql** → `05_maintenance/`  
  (data patch/backfill, no schema change)

- **0014_seed_showroom_mayfair.sql** → `04_seeds/`  
  (adds demo data, uses generator from earlier migration)

---

## Supabase Studio

Supabase applies migrations in **numeric order**, not folder order.  
Example: `0011_seed_schedule_slots.sql` always runs before `0012_locations_and_v2_rpcs.sql`, even though they are in different folders.

---

## Developer Notes

- Keep migrations **idempotent** where possible (`on conflict do nothing`, `if not exists`).
- Always run each migration in **Supabase SQL Editor** once to sync local + cloud.
- Use `git mv` when reorganising (to preserve history).

---

## Next Steps

- When schema stabilises, squash early migrations (0001–0015) into a clean `0001_init.sql` for new environments.
- Until then, keep sequential files intact for audit trail.