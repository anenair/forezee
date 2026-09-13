# send-push

Server-side only, no UI. Sends an APNs push to every device registered
for a given user. This is the piece that lets Coach Mode reach someone
outside the app — the local notifications shipped earlier can't do that
on their own.

## One-time setup

1. **Get an APNs Auth Key** (Apple Developer Program required — same
   paid-account gate as HealthKit/WeatherKit):
   Apple Developer → Certificates, IDs & Profiles → Keys → create a key
   with the "Apple Push Notifications service (APNs)" capability.
   Download the `.p8` file once — Apple only lets you download it once.
   Note the **Key ID** shown on that page, and your **Team ID**
   (Membership page).

2. **Link this repo to your Supabase project** (skip if already linked):
   ```
   supabase link --project-ref <your-project-ref>
   ```

3. **Set the secrets** (never commit the `.p8` contents anywhere):
   ```
   supabase secrets set APNS_KEY_ID=XXXXXXXXXX
   supabase secrets set APNS_TEAM_ID=YYYYYYYYYY
   supabase secrets set APNS_BUNDLE_ID=com.forzee.app
   supabase secrets set APNS_ENVIRONMENT=sandbox
   supabase secrets set APNS_AUTH_KEY="$(cat /path/to/AuthKey_XXXXXXXXXX.p8)"
   ```
   Use `APNS_ENVIRONMENT=sandbox` while testing via Xcode/TestFlight-via-Xcode,
   `production` once distributing through App Store Connect (TestFlight-via-App-Store-Connect
   or the App Store itself use the production APNs environment).

4. **Deploy:**
   ```
   supabase functions deploy send-push
   ```

## Calling it

`POST https://<project-ref>.supabase.co/functions/v1/send-push`

```json
{ "user_id": "<uuid>", "title": "Kai", "body": "..." }
```

Header: `Authorization: Bearer <token>` — either:
- The **service role key**, from a cron job or other backend process.
  Can push to any `user_id`.
- A **user's own session token**, only valid when `user_id` matches
  that same user (e.g. a future "send me a test notification" button).
  Any other combination is rejected with 403.

## What's deliberately not built here

This function only *sends* a push when told to. Deciding *who* should
get nudged and *why* — e.g. "HRV crashed overnight, suggest a rest day"
computed from `context_signals` — is a separate, larger piece: something
has to run on a schedule (Supabase Cron / `pg_cron`), read the signals,
and decide. Not attempted in this pass; this function is the primitive
that piece would call once it exists.
