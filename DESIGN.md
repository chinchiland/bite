# Bite design system: Journal

Every element either carries data or gets out of the way. Your day reads like a food journal: your latest meal photo is the cover, the number that matters sits on it, and a white sheet rises over it with the macros, the ring and your meals. Brandsearch's discipline: one ground, numbers as the anchors, color that always means something.

## Surfaces

- **Paper**: the warm page every screen sits on (#FAFAF8; #121110 in dark mode). **Sheet and card**: white (#1C1B19 dark). A sheet that rises over a cover has 28 pt rounded top corners; a card has 22 pt corners and a 1 pt hairline edge instead of a shadow. **Inset**: the softer box for an amount or an adjuster, 16 pt corners.
- **Covers.** Today's cover is the day's latest photo (a plate Claude estimated, or a saved food with your picture), darkened at the foot so white numbers read on any photo. Before the first photo it is a fresh gradient, green into butter, with ink numbers. A food's hero is your photo, or the product standing on a soft light in its tint, or its emoji, big. Pulling down stretches a cover instead of opening a gap.
- **No drop shadows.** Chrome on a cover is glass: dark on a photo (white words), light on paper (ink words). The dock and the toast are Liquid Glass on iOS 26 and frosted before.
- Screen margin 20 pt. Hairlines only between moments of the day, days of the diary and ranked rows.

## Type

DM Sans only, bundled (SIL Open Font License), one variable font: weight and optical size, which follows the point size so small labels open up and big numbers tighten. Text is regular or medium; semibold is for titles and numbers.

| Use | Size | Weight |
|---|---|---|
| The day's number on the cover | 66 | medium, tracking −4% |
| A food's calories in its ring | 40 | medium |
| Range average | 36 | medium |
| Screen title (Last 7 days) | 30 | semibold |
| A food's name, a meal's name on its page | 27 | medium |
| Calories in Today's ring | 28 | semibold |
| Macro grams | 22 | semibold |
| Section title (Your day, Saved) | 20 | semibold |
| Meal and day names | 16 | semibold |
| Body, list rows | 15 to 17 | regular or medium |
| Chips, captions, times | 13 to 14 | regular or medium |
| Smallest labels | 12 | regular |

- A number is the biggest thing in its block. Its unit sits beside it, smaller and in the secondary color: `967 kcal left today`, `62 g / 125`.
- Nothing smaller than 12 pt.

## Color: one job each

| Job | Color | Where |
|---|---|---|
| Protein, carbs, fat | #D2693C, #4C7FC0, #3E9A76 | the ring's dots and the macro bars, always with their names. The trio passes the color-vision checks on paper and on the dark page. |
| Still to eat | warm gray dots | the rest of the ring |
| Over the goal | red #D9482B | the ring's outer dots, a day's dot and number, a bar |
| A day's verdict | green on target, gray light, red over | the dot beside a day |
| Burned, steps | the Move ring's pink, indigo | their two chips under the macros |
| The streak | sunny flame | the streak pill on the cover |
| Status | green (good, with a leaf), warm (worth a look), blue (info) | soft chips, always with words |
| Rank | gold for 1, green for 2 and 3 | laurels |
| Food tiles | sand, peach, butter, mint, sky, lilac, blush | a basic food's emoji sits on its tint; a product's hero glows in its tint |
| Main action | ink capsule | one per screen: Scan on home, Add to today on a food |
| Scan | the laser red | the barcode glyph in the Scan capsule, the only thing that moves on home |

## Media

One tile shape for every food (corners 19% of the size): 76 pt on Today and Saved, 58 pt in the diary.

- **Product photo** (Open Food Facts): whole, on a white tile with a hairline, its white background multiplied away.
- **Your photo** (a plate Claude estimated, a saved food): fills the tile, and becomes the day's cover. Photos are kept at 1000 px so a cover stays sharp.
- **Basic food or quick add**: its emoji on its pastel.

## Icons and emoji

- **SF Symbols** for everything that is not a food: actions, chips (flame, shoe prints, leaf), the streak flame, the settings gear. Outline for actions, filled for data and to show state (`bookmark.fill` means saved). Never bold.
- **Emoji** only as food pictures: tiles, ingredients, the meal an estimate found.

## Charts

- **The dotted ring**: six rings of fine dots, a halftone. On Today the lit dots are the day's calories against its goal, in the colors of where they came from (protein, carbs, fat), with a one-dot gap between parts; gray dots are still to eat; past the goal, the overflow runs round the outer ring in red. On a food the ring is that food's calories, all lit. The dots light up round the ring when it appears.
- **Macro bars**: name, grams (over the target on Today), a 4 pt bar toward the day's target.
- **Range bars**: one thin bar per day against the goal's dashed line, ink when fine, red when over; they grow from the baseline when they appear. Seven on the right of the week's average, thirty under the month's.
- Labels wear text colors, never the series color.

## Scores, verdicts, ranks

- **Day score, out of 100**: 60 for landing near the calorie goal, 25 for protein, 15 for food quality (Nutri-Score, weighted by calories). Same rule every day, so days rank fairly.
- **Verdicts**: On target (90 to 105% of the goal), Light day, N kcal over. Friendly, never shaming.
- **Streak**: on-target days in a row. Today joins only once it is on target, so an unfinished day never breaks it.
- **Ranks**: best days and most eaten foods, with laurels for the top three.
- **Moves**: ▲ / ▼ with the percentage against the days before, colored only when the direction is good or bad news.

## Screens

- **Today**: the cover (switcher, streak, settings; the number left or over; the photo's meal and the goal), then the sheet: macros and ring, burned and steps, Your day as a timeline (time, meal, calories, tiles), Saved. The dock floats at the bottom: search, Scan, quick add.
- **The switcher** behind the day's name: today and the six days before it, then the last 7 and 30 days.
- **Last 7 days, last 30 days**: the daily average and its bars, the days as a food diary (dot, calories, up to four foods, photos first; tap one to open it), best days, most eaten. Whole days only: today joins tomorrow.
- **A food, a photo estimate**: the hero, then the sheet: name, brand, chips (Nutri-Score, processing, highlights), the macros and the ring, the amount (portions, then − and +), the label on demand. Meal picker and the ink button at the bottom.

## Components

`DayCover`, `DottedRing`, `MacroBars`, `MacroBlock`, `ActivityChips`, `DayTimeline`, `SavedShelf`, `RangeView`, `FoodHero`, `ScanDock`, `ScanGlyph`, `AddedToast`, `GlassCircleButton`, `coverGlass(in:onPhoto:)`, `floatingGlass(in:)`, `Card`, `InsetBox`, `SectionLabel`, `FoodThumb`, `TintChip`, `NutriScoreChip`, `LaurelBadge`, `ChangeLabel`, `ProgressBar`, `MealMenuLabel`, `BookmarkButton`. Buttons: `PrimaryButtonStyle` (ink, one per screen), `SoftButtonStyle`, `ChipButtonStyle`, `PressableStyle`. Tokens live in `Bite/Design/Theme.swift`, the typeface in `Bite/Design/Typeface.swift`.

## Motion

The scan laser sweeps, numbers roll, the ring's dots light up round from twelve o'clock, the range bars grow, covers stretch when pulled, and "Added to Breakfast" slides up over the dock, then leaves after 2.6 seconds. Reduce Motion stops the laser and lights everything at once.

## Copy

Short and friendly. The first words carry the meaning. No dashes.

**Languages: English, French, Spanish.** Written in each language, never translated word for word. French says *tu*, uses a narrow no-break space before `: ? ! %` and curly apostrophes; Spanish is from Spain and says *tú*. Apple's own words win: Réglages and Ajustes, l'app Santé and la app Salud. Labels next to a number agree with what it counts ("kcal consommées", "quemadas": calories). Every key lives in `Bite/Resources/Localizable.xcstrings`; `tools/check_strings.py` fails on any word without both translations.
