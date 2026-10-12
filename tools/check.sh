#!/bin/bash
# Checks Bite without Xcode, on Linux or WSL with a Swift toolchain on the PATH:
#   1. every Swift file parses
#   2. the data layer (models, Open Food Facts decoding, basics, scores and ranks, the Claude
#      photo estimate request and parsing, goal math) compiles and passes its tests
# The SwiftUI screens need Xcode or the GitHub Actions workflow to build.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== parse"
find Bite -name '*.swift' -print0 | xargs -0 swiftc -parse
echo "all $(find Bite -name '*.swift' | wc -l) files parse"

echo "== translations"
python3 tools/check_strings.py

echo "== logic tests"
OUT="$(mktemp -d)"
swiftc -o "$OUT/logic-tests" \
  Bite/Model/Localization.swift \
  Bite/Model/Nutrients.swift \
  Bite/Model/Formatting.swift \
  Bite/Model/Food.swift \
  Bite/Model/FoodTint.swift \
  Bite/Model/Meal.swift \
  Bite/Model/Highlights.swift \
  Bite/Model/Goals.swift \
  Bite/Model/SearchText.swift \
  Bite/Model/Insights.swift \
  Bite/Model/MealEstimate.swift   Bite/Model/MealPlace.swift   Bite/Model/Consensus.swift   Bite/Model/Forecast.swift   Bite/Model/Usual.swift   Bite/Model/LogExport.swift \
  Bite/Services/OFFModels.swift \
  Bite/Services/OpenFoodFacts.swift \
  Bite/Services/BasicFoods.swift \
  Bite/Services/ClaudeVision.swift \
  tools/LogicTests/main.swift
"$OUT/logic-tests" "$PWD"
