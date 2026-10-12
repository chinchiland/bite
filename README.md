# Bite

A calm, friendly calorie tracker for iPhone, in SwiftUI, that reads like a food journal: your latest meal photo is the day's cover, a white sheet rises over it with your macros and your meals, in DM Sans on warm paper (Liquid Glass chrome on iOS 26). Press the scan button on the home screen and either scan a barcode (the product's nutrition comes from Open Food Facts) or snap your plate or a nutrition label (Claude estimates the calories and macros). Everyday foods come from a bundled USDA list and work offline. Steps and burned calories come from Apple Health. The design rules live in [DESIGN.md](DESIGN.md).

## What it does

- **Today**: your latest meal photo as the cover with the calories left on it, then the three macros against your targets beside a dotted ring of the day's calories, burned and steps, Your day as a timeline of food tiles, and your saved foods one tap away. The day's name opens a switcher: the last seven days, then the last 7 and 30 days.
- **Scan**: three modes. Barcode finds the product. Scan food sends a photo of your plate to Claude. Food label reads a nutrition label or a pack. Pick from your gallery too.
- **Photo estimate**: your photo as the hero, Claude's calories and macros on the sheet under it, each ingredient can be adjusted, then add the meal or save it.
- **Saved foods**: bookmark any food, a whole meal or a photo estimate. Choose its picture (an emoji on a color, the product photo, or your own photo), its name and a line under it, how much one tap adds, and its meal.
- **Last 7 and 30 days**: the daily average, how it moved and a bar for each day; each day as a line of the diary with its verdict and its food (tap it to open the day); your best days ranked with laurels, and the foods you come back to.
- **Quick to fix**: every add and delete has Undo, a meal's time is a tap away, and holding a food adds it again (or yesterday's meal to today).
- **Siri, Shortcuts and the Action button**: "Scan food with Bite" opens the camera, "Log Morning skyr in Bite" adds a saved food without opening the app.
- **Settings**: daily goal with a calculator (Mifflin-St Jeor), macro split, Apple Health, and your Claude API key.
- **English, French and Spanish**: the app follows the phone's language. Every word lives in `Bite/Resources/Localizable.xcstrings` (French uses tu, Spanish is from Spain), the 105 basics carry their French and Spanish names and portions, and Claude answers in your language. `python3 tools/check_strings.py` lists anything left untranslated.

## Run it

**With a Mac:** open `Bite.xcodeproj` in Xcode 16 or later, choose your Apple ID team under Signing & Capabilities, plug in your iPhone and press Run. In the scheme's Arguments, turn on `-demo YES` to start with two weeks of sample data.

**Without a Mac:** push this folder to a GitHub repository. The `Build Bite` workflow builds the app on a cloud Mac and attaches two downloads to the run: `screenshots` (every screen, light and dark) and `Bite-unsigned-ipa`. Install the .ipa with [Sideloadly](https://sideloadly.io) and your Apple ID. A free Apple ID re-signs every 7 days; a paid developer account lasts a year.

## Photo estimates

Add a Claude API key in Settings (get one at console.anthropic.com). The key stays in the iOS Keychain. Each photo goes to Claude Opus 5.5 with a strict JSON answer format, and costs about two cents on your Anthropic account. If the model declines a photo, the API retries on Anthropic's recommended fallback model.

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
- Claude, for photo estimates you ask for.
- [DM Sans](https://github.com/googlefonts/dm-fonts) by Colophon, SIL Open Font License (`Bite/Resources/Fonts`). The demo plate photos in `Bite/Resources/Demo` are from [Unsplash](https://unsplash.com) and ship in Debug builds only.
