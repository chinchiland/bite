# Bite's community server

Shared dish estimates live in a Supabase project. Reading is open to everyone; sharing, agreeing and rating need Sign in with Apple, asked only the first time someone does one of those. Your food log never leaves the phone.

The app ships with sharing switched off: `CommunityServer.url` in `Bite/Services/Community/CommunityClient.swift` is empty, so no share row, sheet or Community settings appear. Fill it in once the steps below are done.

## Set it up (about an hour, once)

1. **Project.** Create a Supabase project in **Zurich (eu-central-2)**. The free plan is enough to start: it pauses after a week without database activity, so add the repo secrets `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` and `.github/workflows/keep-awake.yml` reads from it every other day. Move to Pro ($25 a month) when real people depend on it, and delete that workflow.
2. **Database.** Wait for the Server check on GitHub to be green, then with the Supabase CLI: `supabase link --project-ref <ref>`, then `supabase db push`. That runs `supabase/migrations/20261013000000_community.sql`: the tables, row level security, counters, the three-reports auto-hide, and the functions the app calls.
3. **Sign in with Apple.**
   - In the Apple Developer account: give the app id (`com.dylan.bite`) the Sign in with Apple capability, and create a Sign in with Apple key (.p8).
   - In Supabase, Authentication › Providers › Apple: turn it on and add `com.dylan.bite` as a client id (native sign-in needs no secret there).
   - In the app: add the Sign in with Apple capability (`com.apple.developer.applesignin` = `Default` in `Bite.entitlements`).
4. **Functions.** Set the secrets, then deploy:
   ```sh
   supabase secrets set APPLE_TEAM_ID=CKPJMS3P4U APPLE_KEY_ID=<key id> APPLE_CLIENT_ID=com.dylan.bite \
     APPLE_PRIVATE_KEY="$(cat AuthKey_<key id>.p8)" OPENAI_API_KEY=<key> MODERATION_SECRET=<random>
   supabase functions deploy apple-token delete-account moderate
   ```
   - `apple-token` keeps Apple's refresh token after sign-in, so deleting an account can revoke it (Apple requires that).
   - `delete-account` is Settings › Community › Delete my shared counts and account.
   - `moderate` checks a new dish's name with OpenAI's free moderation endpoint before others see it.
5. **Webhook.** Database › Webhooks: on INSERT into `public.dishes`, call the `moderate` function with the header `x-webhook-secret: <MODERATION_SECRET>`.
6. **Rules page.** Publish a short community rules page (no tolerance for abuse, reports acted on within 24 hours, a contact email) and put its address in `CommunityServer.rulesURL`.
7. **The app.** Put the project URL and its publishable (anon) key in `CommunityServer`: that key only opens what the rules below allow. The secret (service role) key never goes in the app or this repo, which is public. Then update `Bite/PrivacyInfo.xcprivacy` and the App Store privacy answers: User ID, Name, Other User Content (estimates, stars, reports) and Precise Location (a place's position), all linked to the person, for App Functionality.

## Safe by default

- **Writes only through the functions.** No client role can insert, update or delete a table; every write is one of the eight functions in the migration, which take who you are from the token. Your profile is yours to read; others see names only next to dishes.
- **It fails closed.** Supabase gives the client roles every right on new public objects; the migration takes them all back, so a table added later is private until a migration grants it, and a function added later fails the tests until it is granted on purpose.
- **Every change is tested before it ships.** `.github/workflows/server.yml` starts a real local Supabase on each push that touches `server/`, applies the migrations, lints the functions and runs `supabase/tests/community_test.sql` (39 checks: who can read, write, agree, rate, report, hide, delete, and the rate limit). Locally, with Docker: `cd server && supabase db start && supabase test db`.
- **An agent never writes to the live project.** Changes go in as migration files through Git and that check; `supabase db push` is run by you. For reading, connect the Supabase MCP server read only and scoped to the one project: `https://mcp.supabase.com/mcp?project_ref=<ref>&read_only=true`.

## Every day

Reports land in `public.reports`. Three different people reporting the same thing hide it at once. Look at the queue in the Supabase dashboard: remove what breaks the rules, and set `profiles.is_banned` for people who do it again.
