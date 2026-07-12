# Reality Merge — v1

Location-unlocked social Drops. See `reality-merge-v1.md` (the blueprint doc)
for the product scope. This repo is the v1 implementation of that scope only
— no AR, no dating, no marketplace.

## Setup

1. **Create a Supabase project** at https://supabase.com/dashboard.
2. Run `supabase/schema.sql` in the Supabase SQL editor. This creates all
   tables, RLS policies, and the two RPC functions (`nearby_drops`,
   `attempt_unlock`) that the app depends on.
3. In Supabase Storage, create a public bucket named `drop-media` (used for
   Drop photos).
4. **Disable email confirmation for now** (dev convenience, not a code
   change): Authentication -> Providers -> Email -> turn off "Confirm
   email". With it off, `signUp` logs the user in immediately. With it on,
   Supabase won't create a session until the user clicks a confirmation
   link — the current sign-up screen doesn't yet handle that "check your
   email" state, so leave it off until that's added, and turn it back on
   before any real launch.
5. Copy `.env.example` to `.env` and fill in:
   - `SUPABASE_URL` / `SUPABASE_ANON_KEY` from Project Settings -> API
   - `MAPBOX_ACCESS_TOKEN` from https://account.mapbox.com/ (only needed
     if/when you wire in the map view — the feed view works without it)
6. Install Flutter dependencies:
   ```
   flutter pub get
   ```
7. Run on a device or simulator (location permissions require a real device
   or a simulator with a mocked location — the iOS Simulator and most
   Android emulators support this):
   ```
   flutter run
   ```

## What's actually implemented here

- Email/password auth (username login is stubbed — see the note in
  `supabase_service.dart`; needs a `resolve_login_email` RPC before it's
  usable, left as a TODO so nothing about auth security is faked)
- Feed of nearby Drops, locked (distance only) vs. unlocked (full content)
- Server-verified unlock: the `attempt_unlock` RPC recalculates distance
  server-side — the client's claimed GPS position is never trusted alone
- Creating a Drop at your current location, with photo + caption + a
  configurable unlock radius
- Profile stats: Drops created, places visited

## What's intentionally not here

Per the v1 blueprint: AR camera mode, dating, marketplace, world room,
sponsored locations, multiple content layers, AI features. Don't add these
until the core loop above is retaining users in a real launch geography —
see the blueprint's "Success metrics" section for what to check first.

## Seeding a launch area

Before opening this to real users, seed 30-50 Drops manually at high-traffic
points in your launch geography (campus entrances, plazas, popular spots).
There's no seed script in this repo yet — for v1, writing these by hand as
a real user (or a small ambassador group) is more valuable than automating
it, since the content itself needs to be genuinely worth walking to.
