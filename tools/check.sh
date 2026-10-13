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
  Shared/Model/MealEstimate.swift   Shared/Model/HealthMeal.swift   Shared/Model/CheckIn.swift   Shared/Model/FirstRun.swift   Shared/Model/WidgetSnapshot.swift   Shared/Model/CommunityRemote.swift   Shared/Model/MealPlace.swift   Shared/Model/Consensus.swift   Shared/Model/Forecast.swift   Shared/Model/Usual.swift   Shared/Model/LogExport.swift \
  Bite/Services/OFFModels.swift \
  Bite/Services/OpenFoodFacts.swift \
  Bite/Services/BasicFoods.swift \
  Bite/Services/ClaudeVision.swift \
  tools/LogicTests/main.swift
"$OUT/logic-tests" "$PWD"
