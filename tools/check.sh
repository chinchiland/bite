#!/bin/bash
# Checks Bite without Xcode, on Linux or WSL with a Swift toolchain on the PATH:
#   1. every Swift file parses
#   2. the data layer (models, Open Food Facts decoding, basics, scores and ranks, the Claude
#      photo estimate request and parsing, goal math) compiles and passes its tests
# The SwiftUI screens need Xcode or the GitHub Actions workflow to build.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== parse"
find Bite Shared BiteWidgets -name '*.swift' -print0 | xargs -0 swiftc -parse
echo "all $(find Bite Shared BiteWidgets -name '*.swift' | wc -l) files parse"

echo "== translations"
python3 tools/check_strings.py

echo "== your mirror stays apart"
# The progress photos never reach the code the widgets compile, never sit in the store as a
# blob, and have no path to the photo estimate (which sends pictures away) or back.
walls=0
if grep -rln --include=*.swift "Mirror" Shared BiteWidgets; then echo "the mirror must stay out of Shared and the widgets"; walls=1; fi
if grep -rn "externalStorage" Bite/Model/MirrorShot.swift Bite/Services/Mirror*.swift; then echo "no photo in the mirror's store"; walls=1; fi
if grep -rln "MirrorPicture\|MirrorVault" Bite/Services/ClaudeVision.swift Bite/Services/BiteVision.swift Bite/Views/Scan; then echo "no mirror photo near the estimate"; walls=1; fi
if grep -rln "ClaudeVision\|claudeKey\|BiteVision\|PhotoEstimator" Bite/Views/Mirror Bite/Services/Mirror*.swift; then echo "no estimate near the mirror"; walls=1; fi
[ "$walls" -eq 0 ] || exit 1
echo "the mirror stays apart"

echo "== logic tests"
OUT="$(mktemp -d)"
swiftc -o "$OUT/logic-tests" \
  Shared/Model/Localization.swift \
  Shared/Model/Nutrients.swift \
  Shared/Model/Formatting.swift \
  Shared/Model/Food.swift \
  Shared/Model/FoodTint.swift \
  Shared/Model/Meal.swift \
  Shared/Model/Highlights.swift \
  Shared/Model/Goals.swift \
  Shared/Model/SearchText.swift \
  Shared/Model/Insights.swift \
  Shared/Model/MealEstimate.swift   Shared/Model/HealthMeal.swift   Shared/Model/CheckIn.swift   Shared/Model/FirstRun.swift   Shared/Model/WidgetSnapshot.swift   Shared/Model/CommunityRemote.swift   Shared/Model/MealReminder.swift   Shared/Model/MealPlace.swift   Shared/Model/Consensus.swift   Shared/Model/Forecast.swift   Shared/Model/Usual.swift   Shared/Model/LogExport.swift \
  Bite/Services/OFFModels.swift \
  Bite/Services/OpenFoodFacts.swift \
  Bite/Services/BasicFoods.swift \
  Bite/Services/ClaudeVision.swift \
  Bite/Services/MirrorGuide.swift \
  Bite/Services/MirrorRules.swift \
  tools/LogicTests/main.swift
"$OUT/logic-tests" "$PWD"
