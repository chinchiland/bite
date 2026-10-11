# Bite design system

Every element either carries data or gets out of the way. Apple's grouped look, Brandsearch's discipline: one ground, cards on it, soft insets for the quieter facts, numbers as the anchors, and color that always means something.

## Surfaces

- iOS system colors, so contrast and dark mode come from the system. **Page**: grouped background. **Card**: the grouped card color, 22 pt continuous corners. **Inset**: the tertiary grouped color inside a card, 16 pt corners, for facts that belong together (eaten, burned, steps).
- **No drop shadows.** Cards separate by color. Chrome that floats over content (the dock, the toast, pills on a photo) is Liquid Glass on iOS 26 and frosted material with a hairline edge before. The scan shutter sits in a page-colored ring instead of a shadow.
- Space and insets do the grouping. Hairlines appear only between rows of a list or columns of stats.
- Screen margin 16 pt, 12 pt between cards, 16 to 18 pt inside a card.

## Type

SF Pro only. Text is regular or medium; semibold is for titles and numbers; bold only for the screen title.

| Use | Size | Weight |
|---|---|---|
| Screen title (Today, Last 7 days) | 32 | bold |
| Sheet title (a food, a photo estimate) | 26 to 28 | semibold |
| Section and card title (Saved, Breakfast) | 20 | semibold |
| Title inside a card (Best days, Ingredients) | 17 | semibold |
| Names, body, list rows | 17 | regular or medium |
| Details, units, captions | 15 | regular |
| Small print, stat labels | 13 | regular |
| Chart axes, day letters, dock labels | 12 | medium |

- **Numbers** use `Font.number`: tabular digits; 34 pt and up are medium (the gauge's 52, a food's 50), smaller ones semibold.
- A number is the biggest thing in its block. Its unit sits beside it, smaller and in the secondary color: `68 kcal`, `62 / 125 g`.
- Nothing smaller than 12 pt.

## Color: one job each

| Job | Color | Where |
|---|---|---|
| Calories | sunny amber, warming from light yellow on the gauge | the gauge, the flame, the kcal pill, chart bars |
| Protein, carbs, fat | orange, blue, teal | always with their icon: dumbbell, bolt, drop. The trio passes the color-vision checks in both modes. |
| Burned, steps | the Move ring's pink, indigo | their two stats under the gauge |
| Over the goal | red | gauge ticks, the day dot, chart bars |
| Status | green (good), amber (worth a look), blue (info) | soft fill, strong text, always with words |
| Rank | gold for 1, green for 2 and 3 | laurels |
| Food tiles | sand, peach, butter, mint, sky, lilac, blush | fruit warm, grains golden, vegetables green, dairy and drinks blue, sweets lilac, meat and fish pink |
| Interactive text | system blue | toolbar buttons, links, the + on a list row |
| Main action | ink capsule | one per screen |
| Scan | the laser red | the only thing that moves on Home |

## Media

One tile shape for every food (corner radius 28% of the size), so lists read as a set.

- **Product photo** (Open Food Facts): shown whole on a light tile, its white background multiplied away so the pack floats.
- **Your photo** (a plate Claude estimated, a saved food): fills the tile.
- **Basic food or quick add**: its emoji on its pastel.

## Icons and emoji

- **SF Symbols** for everything that is not a food: actions, stats (fork and knife, flame, figure walking), verdicts (target, leaf, arrow up), the streak flame. Outline for actions, filled for data and to show state (`bookmark.fill` means saved). Regular or medium weight, never bold.
- **Emoji** only as food pictures: food tiles, ingredients, the meal an estimate found.

## Charts

- **Gauge**: 41 fine ticks on a half dial, filled as you eat. Over the goal every tick turns red.
- **Week and Month**: the Health app's chart. A caption (DAILY AVERAGE), the number, the dates; bars with the goal as a dashed line labeled on the axis; light gridlines with values on the right; weekday letters under the week. Touch a bar and the header shows that day and its verdict; the other bars dim.
- Bars and progress tracks are 4 to 5 pt with rounded ends. Labels wear text colors, never the series color.

## Scores, verdicts, ranks

- **Day score, out of 100**: 60 for landing near the calorie goal, 25 for protein, 15 for food quality (Nutri-Score, weighted by calories). Same rule every day, so days rank fairly.
- **Verdicts**: On target (90 to 105% of the goal), Light day, N kcal over. Friendly, never shaming.
- **Streak**: on-target days in a row. Today joins only once it is on target, so an unfinished day never breaks it.
- **Ranks**: best days and most eaten foods, with laurels for the top three.
- **Moves**: ▲ / ▼ with the percentage, colored only when the direction is good or bad news (protein up is good; calories stay neutral).

## Components

`Card`, `InsetBox`, `SectionLabel`, `CalorieGauge`, `DayStat`, `MacroColumn`, `MacroMinis`, `MacroPill`, `KcalPill`, `FoodThumb`, `TintChip`, `LaurelBadge`, `StatTile`, `ChangeLabel`, `ScanDock`, `ShutterButton`, `ScanGlyph`, `AddedToast`, `MealMenuLabel`, `BookmarkButton`, `floatingGlass(in:)`. Buttons: `PrimaryButtonStyle` (ink, one per screen), `SoftButtonStyle`, `ChipButtonStyle`, `PressableStyle`. Tokens live in `Bite/Design/Theme.swift`.

## Motion

The scan laser sweeps, numbers roll, the gauge's ticks light up one by one on a spring, and "Added to Breakfast" slides up over the dock, then leaves after 2.6 seconds. Reduce Motion stops the laser and the scan band.

## Copy

Short and friendly. The first words carry the meaning. No dashes.
