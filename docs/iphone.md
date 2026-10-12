# Bite on your iPhone, from Windows

Two apps come out of every build (GitHub Actions, run "Build Bite"):

- **Bite Demo** (`Bite-Demo-unsigned-ipa`, copied to `_previews/Bite-Demo.ipa`): the app with two weeks of sample meals, El Beirout and the community dishes. It opens straight on the demo day, never touches your log, and moves its story to each new day. Every photo you scan in it reads as the demo's salmon bowl, and what you add is gone at the next launch: it is a demo. Its icon is the inverted cookie.
- **Bite** (`Bite-unsigned-ipa`, copied to `_previews/Bite.ipa`): the real app. It starts on the goal screen, then an empty Today, and keeps your log.

Both install side by side with a free Apple ID. Checked in October 2026 with Sideloadly 0.70.1. About 30 to 40 minutes the first time, 0 CHF.

## Once

1. **iTunes from Apple's site**, not the Microsoft Store: <https://www.apple.com/itunes/download/win64>. It brings the iPhone's USB driver. Don't install Apple Devices, Apple Music or Apple TV from the Store: they break the connection.
2. **iCloud from Apple's site**: <https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe>. No need to sign in. Restart the PC if it asks.
3. **Sideloadly**: <https://sideloadly.io/SideloadlySetup64.exe>. Allow it on private networks and leave its background service on.
4. **Pair the iPhone**: plug it in with a data cable, unlock it, tap Trust and type the passcode. In iTunes click the phone icon, then Summary. Tick "Sync with this iPhone over Wi-Fi", untick automatic syncing, Apply, close iTunes.
5. **Bite Demo first**: in Sideloadly pick the iPhone, type your Apple ID, drag `Bite-Demo.ipa` in. Keep the auto-refresh icon (bottom left) on, then Start. Type your Apple ID password and the code your iPhone shows: they go only to Apple. Accept the Anisette download if it offers one.
6. **Developer Mode** on the iPhone: Settings, Privacy & Security, Developer Mode at the bottom (Réglages, Confidentialité et sécurité, Mode développeur). Switch it on, Restart, then Turn On and the passcode.
7. **Trust yourself**: Settings, General, VPN & Device Management (Réglages, Général, VPN et gestion de l'appareil). Under Developer App, tap your Apple ID, then Trust. Open Bite Demo: it lands on the El Beirout day.
8. **Bite**: step 5 again with `Bite.ipa`. Open it, set your goal, then tap **Connect Health** on Today.

## Apple Health

If Apple's Health window appears after Connect Health, Health came through. If it doesn't, Bite says so in Settings: Sideloadly left the Health capability out, which is likely with a free Apple ID. Everything else works, but steps, burned calories, weighings and the learned goal stay off.

To keep Health, before you log real meals:

1. Delete both apps and turn off Sideloadly's auto-refresh for them.
2. Install Impactor (open source): <https://github.com/claration/impactor/releases/download/v2.6.5/Impactor-windows-x86_64-setup.exe>.
3. Sign in with the same Apple ID, install both files, trust again on the iPhone.
4. Use only Impactor from then on: two signing tools on one Apple ID can cancel each other.

Impactor asks Apple for every capability Bite declares, Health included; it has not been confirmed on a phone yet. TestFlight (below) always has Health.

## Every week, and every new build

- A free Apple ID signs for **7 days**. Sideloadly re-signs on its own while the PC is on and awake and the phone is on the same Wi-Fi. If an app stops opening, plug in, drag the same file, Start.
- **Never delete Bite**: deleting deletes your log. Installing over it keeps everything, the Claude key too.
- A new build: drag the new file in, same Apple ID, same tool, Start. On the first update, check that no second Bite icon appears.
- A free Apple ID allows 3 sideloaded apps on the phone and 10 new app IDs a week.

## Photo estimates

In Bite: Settings, Photo estimates, paste your key from <https://platform.claude.com/settings/keys>, then Done. About 2 cents a photo, on your Anthropic account.

## Later: TestFlight, no cable, no weekly refresh

With a paid Apple Developer Program membership (CHF 109 a year), a GitHub Action can send each build to TestFlight: install from the TestFlight app, builds last 90 days, Health always works. You would enroll, create the app in App Store Connect and an API key; the signing setup and the workflow are ready to add. `Bite/PrivacyInfo.xcprivacy` already declares what App Store Connect asks for.
