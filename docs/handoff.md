# Handoff: where Bite stands (13 October 2026)

Read this with `CLAUDE.md`, `DESIGN.md`, `README.md` and `docs/mac.md`. Until now Bite was built from a Windows PC with no Mac: Swift checks in WSL (`tools/check.sh`) and every SwiftUI build, screenshot and IPA on GitHub Actions. On a Mac you can finally build, run and debug in Xcode directly.

## How Dylan works

- Replies: the point first, short, plain words, links at the end. No em dashes anywhere (copy, docs, commits).
- Do, don't ask: pick the sensible default, ship it, say what you picked. Ask only when it is really his call.
- Show, don't tell: anything visual gets rendered and looked at before it is handed back (simulator or device screenshots, at full size). Test layouts against the worst data: four-digit numbers, French and Spanish.
- He decides design by picking between variants. Design rounds live on the canvas artifact https://claude.ai/artifact/Qx8mMTu7AJxApbEQJyu1cr (pages r1 to r10). The whole app as screenshots: https://claude.ai/artifact/TS9RYfM9wyj7dsVAdUMVQX.
- He lives in Lausanne. Real local places beat stock content (the demo is a lunch at El Beirout by the Parc de Milan).

## The first job on the Mac

Put Bite and Bite Demo on his iPhone: `tools/install-on-iphone.sh` (see `docs/mac.md`). It has never run on a Mac, so expect to fix small things:
- Xcode must be signed in to his Apple ID (Settings › Accounts), team **CKPJMS3P4U** ("Dylan Trigos"). If the membership turns out to be free, signing still works but lasts 7 days.
- If Apple refuses `com.dylan.bite` (bundle ids are global), use `BUNDLE_ID=ch.dylan.bite` and keep it from then on, or his log resets.
- The iPhone needs Developer Mode and must trust the Mac.
- Check after install: Bite opens on the goal screen, then **Connect Health** on Today shows Apple's Health window (the HealthKit entitlement is in `Bite.entitlements`); Bite Demo opens on the El Beirout day.
- His Claude API key goes in Settings › Photo estimates (from platform.claude.com/settings/keys).

Context: a Windows attempt with Sideloadly got past the Apple sign-in, then timed out reaching Apple (probably his VPN). Not worth retrying now that there is a Mac.

## What the app is today

Journal design (`DESIGN.md`): the day's meal photos as a cover that melts into the page (M2, his pick), the number that matters under it, a dotted macro ring with food glyphs (drumstick, wheat ear, avocado), water and Health chips, "If you keep this up" (weight forecast, a goal learned from weighings after two weeks), the day as a timeline, your usual meal waiting at its time, the saved shelf ("Fits your 750 left"), dishes near you, the week as dots. Scan: barcode (Open Food Facts), plate photo or nutrition label (Claude, with its biggest doubt as a one-tap question), 105 USDA basics with typo-tolerant search. Eating out: places from Apple Maps, community dishes with an accuracy score from people's estimates (local to the phone until there is a server). Week and month: dot columns, best days, most eaten. Settings: goal calculator, macros, Health, the Claude key, CSV export. English, French (tu) and Spanish (Spain, tú).

## How the code is checked

- `tools/check.sh`: parse, translations, about 250 logic tests. Run it before every commit.
- Push to main: CI builds, shoots about 50 screenshots (`screenshots` artifact) and two IPAs. On the Mac you can also just run the app in the simulator: launch arguments in `CLAUDE.md` (`-demo YES`, `-onboarded YES`, `-screen ...`).
- Before handing back UI, look at the screens, French and Spanish included.

## Next, roughly in order

1. Get it on the phone (above), then fix what he finds using it for real.
2. Apple Health write, opt-in (meals to Health). The `NSHealthUpdateUsageDescription` text still says Bite never writes: change it with the feature, in both configurations and in `InfoPlist.xcstrings`.
3. TestFlight from GitHub Actions: manual signing with one Apple Distribution .p12 and an App Store profile stored as secrets (cloud signing mints a new development certificate on every fresh runner), upload with `xcodebuild -exportArchive` and an App Store Connect API key. He makes the app record and an Admin API key once; `Bite/PrivacyInfo.xcprivacy` is ready.
4. A server for community dishes (Supabase by default) so estimates are shared; until then they stay on the phone.
5. Smaller: a fiber line for the day, a weekly check-in for the learned goal, widgets (need an App Group and an extension target), the doubt question showing a calorie range.
6. Needs him: Uber Eats (Impact) and Just Eat (Awin) partner sign-ups for the Order button.
