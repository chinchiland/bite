# Bite

A calm calorie tracker for iPhone in SwiftUI (iOS 17+, SwiftData, Swift 5 language mode, Xcode 26). The design system is `DESIGN.md`; what the app does is in `README.md`. Where things stand, how Dylan works and what comes next: `docs/handoff.md`.

## Where things are

- `Bite/Model`: Foundation-only logic (nutrients, goals, insights, forecast, usual meal, search, export). Tested without Xcode by `tools/check.sh`.
- `Bite/Services`: Open Food Facts, the USDA basics, the Claude photo estimate (raw HTTP, `claude-opus-5-5`), Apple Health, places, the SwiftData store (`BiteStore`, versioned schema), the demo data.
- `Bite/Views`, `Bite/Design`: screens and components. Tokens in `Bite/Design/Theme.swift`.
- `docs/`: research, the iPhone guides (`docs/mac.md`, `docs/iphone.md`).

## On a Mac

- **Install on the plugged-in iPhone:** `tools/install-on-iphone.sh` (Bite and Bite Demo, signed with team CKPJMS3P4U). See `docs/mac.md`.
- **Checks:** `tools/check.sh` (every file parses, every string is translated, the logic tests pass). Run it before committing.
- **Demo data:** a Debug run with the `-demo YES` argument, or the Bite Demo app (Release with the compile condition `BITE_DEMO`; demo code sits behind `#if DEBUG || BITE_DEMO`). Screenshot arguments (Debug only): `-onboarded YES`, `-health.asked YES`, `-screen food|search|settings|week|month|dish|...`, `-anchor center|bottom|usual`, `-clock 19:30`, `-query skyr`.

## CI

Every push to main runs `.github/workflows/ios.yml` on a macOS runner: a Debug build, about 50 simulator screenshots (light, dark, French, Spanish, a fresh install, Bite Demo), and two IPAs for sideloading (`Bite-unsigned-ipa`, `Bite-Demo-unsigned-ipa`). Markdown and `docs/` changes don't trigger it. macOS minutes are billed 10x, so batch pushes.

## Rules for the code

- Every word on screen lives in `Bite/Resources/Localizable.xcstrings` with French (tu, curly apostrophes, a narrow no-break space before `: ? ! %`) and Spanish from Spain (tú). Model code uses `tr()`. `tools/check_strings.py` fails on any untranslated literal.
- Copy is short and plain, never an em dash. Comments are full sentences that say why, in the "you" voice the app uses.
- Commit with `git -c user.name=Dylan`; never change the global git config.
