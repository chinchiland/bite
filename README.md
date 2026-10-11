# Bite

A calm, friendly calorie tracker for iPhone, in SwiftUI, in Apple's own look (system colors, SF Pro, Liquid Glass on iOS 26). Press the scan button on the home screen and either scan a barcode (the product's nutrition comes from Open Food Facts) or snap your plate or a nutrition label (Claude estimates the calories and macros). Everyday foods come from a bundled USDA list and work offline. Steps and burned calories come from Apple Health. The design rules live in [DESIGN.md](DESIGN.md).

## What it does

- **Today**: a half-dial gauge of calories left, what explains it (eaten, burned, steps), the three macros against your targets, your saved foods one tap away, and each meal as a card with its foods.
- **Scan**: three modes. Barcode finds the product. Scan food sends a photo of your plate to Claude. Food label reads a nutrition label or a pack. Pick from your gallery too.
- **Photo estimate**: Claude's calories and macros float on your photo, each ingredient can be adjusted, then add the meal or save it.
- **Saved foods**: bookmark any food, a whole meal or a photo estimate. Choose its picture (an emoji on a color, the product photo, or your own photo), its name and a line under it, how much one tap adds, and its meal.
- **Week and Month**: the Health app's kind of chart (touch a bar to see that day), the daily average and how it moved, your best days ranked with laurels, and the foods you come back to.
- **Settings**: daily goal with a calculator (Mifflin-St Jeor), macro split, Apple Health, and your Claude API key.

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
