# Bite

A calm, friendly calorie tracker for iPhone, in SwiftUI, that reads like a food journal: your latest meal photo is the day's cover, a white sheet rises over it with your macros and your meals, in DM Sans on warm paper (Liquid Glass chrome on iOS 26). Press the scan button on the home screen and either scan a barcode (the product's nutrition comes from Open Food Facts) or snap your plate or a nutrition label (Claude estimates the calories and macros). Everyday foods come from a bundled USDA list and work offline. Steps and burned calories come from Apple Health. The design rules live in [DESIGN.md](DESIGN.md).

## What it does

- **Today**: your latest meal photo as the cover with the calories left on it, then a dotted ring of the day's calories beside the three macros against your targets (a drumstick, a wheat ear and an avocado mark them), burned and steps, Your day as a timeline of food tiles, and your saved foods one tap away. The day's name opens a switcher: the last seven days, then the last 7 and 30 days.
- **Scan**: four modes. Barcode finds the product. Scan food sends a photo of your plate for an estimate. Food label reads a nutrition label or a pack. Menu reads a restaurant's menu. Pick from your gallery too.
- **Where you ate**: pick the restaurant or cafe from the places around you (Apple Maps) when you log; the cover says where, and each place shows the dishes people counted there, with Directions and Order (Uber Eats).
- **Dishes the community counts**: each dish's calories are what people's estimates add up to (an AI scan of their plate, or typed by hand), weighted by how many agree, with an accuracy score that says how close and how many. Add your own estimate, like the ones that match your plate, rate the dish. Local to the phone until the shared server is set up.
- **Where your weight is heading**: your weighings from Apple Health and a dotted line to your weight four weeks on at the way you have been eating, with how many calories a day under or over what your body burns. After two weeks of weighings and meals, Bite learns what your body really burns and offers the daily goal that fits it, one tap to use.
- **Water**: one tap a glass, the chip filling toward the day's glasses.
- **Your mirror**: a progress photo every four weeks that lands in the same frame as the first. Hold the phone up to a mirror, or prop it on a sink and step back while it speaks; marks at the screen's edges show where the first photo's shoulders and hips were, the light is held to the first photo's, and the photo takes itself once you're lined up and still. One photo at a time, a comparison you drag, the weeks between them and your two weighings. Encrypted on the phone behind Face ID, never in iCloud, the camera roll or any server; Bite measures where you stand, never your body.
- **Photo estimate**: your photo as the hero, Claude's calories and macros on the sheet under it, its biggest doubt as a one-tap question ("How much dressing was on it?"), each ingredient can be adjusted, then add the meal or save it.
- **Menus**: photograph a restaurant's menu and every dish on it comes back with the calories of the portion a place like this usually serves, in five to fifteen seconds. The menu is kept on the phone (its photo too, to read again at the table), so the next visit is one tap, and its dishes show up when you search.
- **Typical portions**: type a dish in search ("shawarma") and the first answer is a typical portion of it. Two taps make it yours: how rich it was (lean, regular, rich: the oil, sauce and cheese, and their calories) and how big (small, usual, big, huge). Below it come the dishes on your menus, the basics and the Open Food Facts products ("coca zero").
- **Saved foods**: bookmark any food, a whole meal or a photo estimate. Choose its picture (an emoji on a color, the product photo, or your own photo), its name and a line under it, how much one tap adds, and its meal.
- **Last 7 and 30 days**: the daily average, how it moved and a column of dots for each day; each day as a line of the diary with its verdict and its food (tap it to open the day); your best days ranked with laurels, and the foods you come back to.
- **Quick to fix**: every add and delete has Undo, a meal's time is a tap away, and holding a food adds it again (or yesterday's meal to today). Your usual meal waits on the timeline around its time, one tap to add. Search forgives a typo.
- **Siri, Shortcuts and the Action button**: "Scan food with Bite" opens the camera, "Log Morning skyr in Bite" adds a saved food without opening the app.
- **Settings**: daily goal with a calculator (Mifflin-St Jeor), macro split, Apple Health, your Claude API key, and your whole log as a spreadsheet.
- **English, French and Spanish**: the app follows the phone's language. Every word lives in `Shared/Resources/Localizable.xcstrings` (French uses tu, Spanish is from Spain), the 105 basics carry their French and Spanish names and portions, and Claude answers in your language. `python3 tools/check_strings.py` lists anything left untranslated.

## Run it

**With a Mac:** `tools/install-on-iphone.sh` builds Bite and Bite Demo with your Apple team and installs them on the plugged-in iPhone (Xcode 26 with your Apple ID in Settings › Accounts; details in [docs/mac.md](docs/mac.md)). Or open `Bite.xcodeproj`, choose your team under Signing & Capabilities and press Run; turn on `-demo YES` in the scheme's Arguments for two weeks of sample data.

**Without a Mac:** push this folder to a GitHub repository. The `Build Bite` workflow builds the app on a cloud Mac and attaches three downloads to the run: `screenshots` (every screen, light and dark, a fresh install, and Bite Demo), `Bite-unsigned-ipa` (the real app) and `Bite-Demo-unsigned-ipa` (Bite Demo, which opens on two weeks of sample meals and sits next to Bite). Install them with [Sideloadly](https://sideloadly.io) and your Apple ID: the steps, the Apple Health check and the weekly refresh are in [docs/iphone.md](docs/iphone.md). A free Apple ID re-signs every 7 days; a paid developer account lasts a year and allows TestFlight.

## Photo estimates

Add a Claude API key in Settings (get one at platform.claude.com/settings/keys). The key stays in the iOS Keychain. Each photo goes to Claude Opus 5.5 with a strict JSON answer format, and costs about two cents on your Anthropic account. If the model declines a photo, the API retries on Anthropic's recommended fallback model.

## Check it without Xcode

The data layer (Open Food Facts decoding and search ranking, basics search, portions, highlights, day scores, streaks and ranks, the Claude request and its parsing, goal math) runs on Linux or WSL with a Swift toolchain:

```
source tools/wsl-swift-env.sh   # in WSL, puts Swift 6.4 on the PATH
bash tools/check.sh
```

It parses every Swift file and runs the logic tests against real Open Food Facts responses saved in `tools/LogicTests/fixtures`.

## Data

- [Open Food Facts](https://world.openfoodfacts.org), the free and open food database (ODbL, images CC BY-SA). No account or key.
- [USDA FoodData Central](https://fdc.nal.usda.gov), SR Legacy (public domain). Rebuild the basics with `python tools/build_basics.py <sr_legacy_csv_folder> Bite/Resources/basics.json`.
- Apple Health, read only: steps and active energy.
- Google's Gemini 3.1 Flash-Lite through Bite's own server for photo estimates (no photo kept, ceilings no honest use reaches), or Claude when you set your own key.
- [DM Sans](https://github.com/googlefonts/dm-fonts) by Colophon, SIL Open Font License (`Bite/Resources/Fonts`). The demo plate photos in `Bite/Resources/Demo` are from [Unsplash](https://unsplash.com), the two shawarmas are public domain (CC0: Andy Li on [Wikimedia Commons](https://commons.wikimedia.org/w/index.php?curid=130489661), Joan Namunina on [WordPress Photos](https://wordpress.org/photos/photo/8636a6d0de/)), and they ship in Debug builds and Bite Demo only.
