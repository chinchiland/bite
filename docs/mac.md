# Bite on your iPhone, from a Mac

The easy way: Xcode signs with your Apple team, so Apple Health works and nothing needs a weekly refresh.

## Once per Mac

1. **Xcode 26 or later** from the App Store. Open it once and let it install its components.
2. **Your Apple ID in Xcode**: Xcode › Settings › Accounts › + › Apple ID, the account of team **CKPJMS3P4U**.
3. **The code**: `gh repo clone chinchiland/bite` (the repo is public; `gh auth login` first if you will push), or `git pull` in an existing copy.

## Once per iPhone

Plug it in, unlock it, tap **Trust This Computer**. Turn on **Developer Mode** (Settings › Privacy & Security › Developer Mode, at the bottom; it shows up once the phone has met Xcode), let it restart, tap Turn On.

## Install

```sh
tools/install-on-iphone.sh          # Bite and Bite Demo
tools/install-on-iphone.sh bite     # only Bite
tools/install-on-iphone.sh demo     # only Bite Demo
```

It builds each app in Release for the plugged-in iPhone, signs it with team CKPJMS3P4U (Xcode registers the iPhone and the app ids, Apple Health included, the first time), installs it and opens it.

- **Bite** starts on a welcome screen, then the first bite and your goal over Today. It comes with widgets (Today and Log on the Home Screen, Today on the Lock Screen, a water control): Xcode signs the widget extension and the App Group `group.<bundle id>` with the team the first time. If signing ever refuses the App Group, the app still runs on its own folder and the widgets say "Open Bite once". Tap **Connect Health** on Today for Apple's Health window, and paste your Claude key in Settings › Photo estimates (from <https://platform.claude.com/settings/keys>).
- **Bite Demo** opens on the El Beirout day with two weeks of sample meals. Nothing you add in it is kept.

If Apple says `com.dylan.bite` is not available, pick your own: `BUNDLE_ID=ch.dylan.bite tools/install-on-iphone.sh`. Two iPhones plugged in: `DEVICE=<udid> tools/install-on-iphone.sh` (`xcrun devicectl list devices` lists them).

**Updates:** `git pull`, then the same command. Same bundle id, so your log stays. With a paid team the apps stay signed for a year; with a free one, 7 days.

## Or by hand in Xcode

Open `Bite.xcodeproj`, select the Bite target › Signing & Capabilities › Team: CKPJMS3P4U. Pick your iPhone at the top, press Run. To see the demo from Xcode: Product › Scheme › Edit Scheme › Run › Arguments, add `-demo YES` (Debug runs only).

## A prompt for Claude Code on the Mac

> In ~/Repositories, clone chinchiland/bite with gh if it is not there, else pull it. Read CLAUDE.md and docs/mac.md, then install Bite and Bite Demo on my plugged-in iPhone with tools/install-on-iphone.sh. Fix whatever stops the build or the install, and tell me what to tap on the phone.

## Later: TestFlight

With the paid team, a GitHub Action can send every build to TestFlight: no cable at all, builds last 90 days. It needs an App Store Connect API key (Admin) and the app record, made once on appstoreconnect.apple.com; `Bite/PrivacyInfo.xcprivacy` is already in place.
