# Bite on your iPhone, from a Mac

The easy way: Xcode signs with your Apple team, so Apple Health works and nothing needs a weekly refresh.

## Once per Mac

1. **Xcode 26 or later** from the App Store. Open it once and let it install its components.
2. **Your Apple ID in Xcode**: Xcode › Settings › Accounts › + › Apple ID, the account of team **CKPJMS3P4U**. Without it nothing signs (`No Accounts`). It also keeps your development certificate: one lasts a year, and when it runs out (`No signing certificate "iOS Development" found`) Xcode makes the next one, but only while the Apple ID is there.
3. **The code**: `gh repo clone chinchiland/bite` (the repo is public; `gh auth login` first if you will push), or `git pull` in an existing copy.

## Once per iPhone

Plug it in, unlock it, tap **Trust This Computer**. Turn on **Developer Mode** (Settings › Privacy & Security › Developer Mode, at the bottom; it shows up once the phone has met Xcode), let it restart, tap Turn On.

Use a cable that carries data: a charge-only one charges the phone, but the Mac never sees it. If the phone has forgotten the Mac (an iOS update can do that), the install script asks it to trust the Mac again. Xcode 26.2 installs on iOS 27 fine. Keep the phone unlocked when the script starts: Xcode sets it up for development only then (`The developer disk image could not be mounted`), and the script waits for it.

Signing needs the Mac awake: with the display asleep the keychain refuses to sign (`errSecInternalComponent`). The App Groups for the widgets are registered once at developer.apple.com › Identifiers › + › App Groups (`group.com.dylan.bite`, `group.com.dylan.bite.demo`), since Xcode never registers one from the command line; until then the script builds without them.

## Install

```sh
tools/install-on-iphone.sh          # Bite and Bite Demo
tools/install-on-iphone.sh bite     # only Bite
tools/install-on-iphone.sh demo     # only Bite Demo
```

It builds each app in Release for the plugged-in iPhone, signs it with team CKPJMS3P4U (Xcode registers the iPhone and the app ids, Apple Health included, the first time), installs it and opens it.

- Both open in **Glass**, the dark look where your food's color is the room. Settings › Look switches to **Paper**, the light one.
- **Bite** starts on a welcome screen, then the first bite and your goal over Today. It comes with widgets (Today and Log on the Home Screen, Today on the Lock Screen, a water control): Xcode signs the widget extension and the App Group `group.<bundle id>` with the team the first time. If signing ever refuses the App Group, the app still runs on its own folder and the widgets say "Open Bite once". Tap **Connect Health** on Today for Apple's Health window. Photo estimates work with no key. Your mirror (progress photos) is in Settings › Your mirror. A free Apple team can't sign Sign in with Apple: the script then builds without it, and only sharing a count to the community stays off.
- **Bite Demo** opens on the El Beirout day with two weeks of sample meals. Nothing you add in it is kept.

If Apple says `com.dylan.bite` is not available, pick your own: `BUNDLE_ID=ch.dylan.bite tools/install-on-iphone.sh`. Two iPhones plugged in: `DEVICE=<udid> tools/install-on-iphone.sh` (`xcrun devicectl list devices` lists them).

**Updates:** `git pull`, then the same command. Same bundle id, so your log stays. With a paid team the apps stay signed for a year; with a free one, 7 days.

## Or by hand in Xcode

Open `Bite.xcodeproj`, select the Bite target › Signing & Capabilities › Team: CKPJMS3P4U. Pick your iPhone at the top, press Run. To see the demo from Xcode: Product › Scheme › Edit Scheme › Run › Arguments, add `-demo YES` (Debug runs only).

## A prompt for Claude Code on the Mac

> In ~/Repositories, clone https://github.com/chinchiland/bite if it is not there, else pull main. Read CLAUDE.md, docs/mac.md and the "Two looks" part of DESIGN.md, then install Bite and Bite Demo on my plugged-in iPhone with tools/install-on-iphone.sh. The script has not been proven on a real Mac yet, so fix whatever stops the build, the signing or the install, and tell me exactly what to tap on the phone. If Apple refuses com.dylan.bite, use BUNDLE_ID=ch.dylan.bite and keep it from then on. Once it is on the phone, walk me through checking that both apps open in Glass, that Settings > Look switches to Paper and back, and that Connect Health on Today shows Apple's window. Commit your fixes with `git -c user.name=Dylan` and push to main. The repo is public: never commit a key or private data.

## Later: TestFlight

With the paid team, a GitHub Action can send every build to TestFlight: no cable at all, builds last 90 days. It needs an App Store Connect API key (Admin) and the app record, made once on appstoreconnect.apple.com; `Bite/PrivacyInfo.xcprivacy` is already in place.
