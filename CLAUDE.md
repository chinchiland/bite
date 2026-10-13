# Bite

A calm calorie tracker for iPhone in SwiftUI (iOS 17+, SwiftData, Swift 5 language mode, Xcode 26). The design system is `DESIGN.md`; what the app does is in `README.md`. Where things stand, how Dylan works and what comes next: `docs/handoff.md`.

## Where things are

- `Shared/`: compiled into the app and the widgets. `Shared/Model` is the Foundation-only logic (nutrients, goals, insights, forecast, the weekly check-in, usual meal, first run, widget snapshot, Health plan, search, export), tested without Xcode by `tools/check.sh`; `Shared/Design` holds the tokens (`Theme.swift`), the typeface and the macro glyphs; `Shared/Services` the SwiftData store (`BiteStore`, versioned schema, in the App Group `group.<bundle id>`), and the intents widgets and Siri run (`LogIntents.swift`); `Shared/Resources` the string catalog and the fonts.
- `Bite/Services`: Open Food Facts, the USDA basics, photo estimates (`PhotoEstimator`: your own Claude key through `ClaudeVision`, otherwise Bite's server through `BiteVision`, Gemini 3.1 Flash-Lite with daily ceilings, an anonymous session, and a one-time 18+ question), Apple Health (read, and opt-in write via `HealthSync`), places, the widget bridge, the demo data.
- `Bite/Views`, `Bite/Design`: screens and components; `Bite/Views/Start` is the first run.
- `BiteWidgets/`: the widget extension's timelines (Today, Log, Scan, Water, and the Scan food and Add water controls); their faces are in `Shared/Widgets`, which the app also draws for `-screen widgets` and `-screen widgets-lock`. Its bundle id follows the app's (`BITE_BUNDLE_ID`, `.widgets`); set `BITE_BUNDLE_ID` and `BITE_APP_ICON`, never `PRODUCT_BUNDLE_IDENTIFIER`, on the command line.
- `docs/`: research, the iPhone guides (`docs/mac.md`, `docs/iphone.md`).

## On a Mac

- **Install on the plugged-in iPhone:** `tools/install-on-iphone.sh` (Bite and Bite Demo, signed with team CKPJMS3P4U). See `docs/mac.md`.
- **Checks:** `tools/check.sh` (every file parses, every string is translated, the logic tests pass). Run it before committing.
- **Demo data:** a Debug run with the `-demo YES` argument, or the Bite Demo app (Release with the compile condition `BITE_DEMO`; demo code sits behind `#if DEBUG || BITE_DEMO`). Screenshot arguments (Debug only): `-onboarded YES`, `-health.asked YES`, `-screen food|search|settings|week|month|dish|...`, `-anchor center|bottom|usual`, `-clock 19:30`, `-query skyr`.

## CI

Every push to main runs `.github/workflows/ios.yml` on a macOS runner: a Debug build, about 50 simulator screenshots (light, dark, French, Spanish, a fresh install, Bite Demo), and two IPAs for sideloading (`Bite-unsigned-ipa`, `Bite-Demo-unsigned-ipa`). Markdown and `docs/` changes don't trigger it. The repo is public, so the minutes are free, but a run takes about 25 minutes: batch pushes. Everything pushed is public: never commit a key or private data.

## Rules for the code

- Every word on screen lives in `Shared/Resources/Localizable.xcstrings` with French (tu, curly apostrophes, a narrow no-break space before `: ? ! %`) and Spanish from Spain (tú). Model code uses `tr()`. `tools/check_strings.py` fails on any untranslated literal.
- Copy is short and plain, never an em dash. Comments are full sentences that say why, in the "you" voice the app uses.
- Commit with `git -c user.name=Dylan`; never change the global git config.
