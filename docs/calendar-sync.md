# 📅 Calendar Sync — Google Calendar → Supabase

## Overview
This automation keeps the **bespoke ordering system** calendar in sync with Google Calendar.  
Events created, updated, or cancelled in Google Calendar are mirrored into the Supabase table `busy_times`.  

**Flow:**  
`Google Calendar → Make.com → Supabase`

## Make.com Scenario
- **Scenario name**: `bespoke-ordering-system__calendar__sync-gcal-to-supabase`
- **Modules:**
  1. `gcal__watch-events` (Google Calendar / Watch Events)
  2. Router  
     - Branch `when_cancelled` → `supabase__busy-times__delete`  
     - Branch `when_created-or-updated` → `supabase__busy-times__upsert`
  3. `supabase__busy-times__delete` (HTTP / DELETE → Supabase)
  4. `supabase__busy-times__upsert` (HTTP / POST → Supabase)

- **Credentials:**  
  - `supabase__no-auth` (Make HTTP keychain, no username/password)  
  - Supabase headers (Service Role only; server-side):  
    - `apikey: <SERVICE_ROLE_KEY>`  
    - `Authorization: Bearer <SERVICE_ROLE_KEY>`

## Supabase
- **Tables:** `google_calendars`, `busy_times`, `schedule_slots`  
- **Functions:** `ranges_overlap`, `generate_slots_excluding_busy`  
- **Migrations:** `0004_google_calendars.sql`, `0005_generate_slots.sql`, `0006_busy_times_event_id.sql` *(if present)*

## Data Flow
- **Create/Update:** upsert into `busy_times` (`source_calendar_id`, `external_event_id`, `starts_at`, `ends_at`).  
- **Cancel/Delete:** delete from `busy_times` by `source_calendar_id + external_event_id`.

## Notes
- `source_calendar_id` = your Google Calendar ID (URL-encoded).  
- Writes to `busy_times` require **service role**; only Make uses this key. Never expose it in the app.