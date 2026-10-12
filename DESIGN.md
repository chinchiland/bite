# Bite design system: Journal

Every element either carries data or gets out of the way. Your day reads like a food journal: the day's meal photos are the cover, melting into the page right above the number that matters, then the ring and the macros, where your weight is heading, your meals, what fits, the dishes near you and your week. Brandsearch's discipline: one ground, numbers as the anchors, color that always means something.

## Surfaces

- **Paper**: the warm page every screen sits on (#FAFAF8; #121110 in dark mode). **Sheet and card**: white (#1C1B19 dark). A sheet that rises over a cover has 28 pt rounded top corners; a card has 22 pt corners and a 1 pt hairline edge instead of a shadow. **Inset**: the softer box for an amount or an adjuster, 16 pt corners.
- **Covers.** Today's cover is every photo of the day, latest first (plates Claude estimated, restaurant dishes, saved foods with your picture). Each runs clear down to the number, then softens through its own blur into the page, so the number sits in ink right under the food and needs no dark scrim. Tap or swipe for the next; page dots on dark glass say how many. When the meal has a place, the line under the number is a pin and the place, and opens it; else the meal's name. Before the first photo the cover is a fresh gradient, green into butter, with a greeting for the hour. A food's hero is your photo, or the product standing on a soft light in its tint, or its emoji, big. Pulling down stretches a cover instead of opening a gap.
- **No drop shadows.** Chrome on a cover is glass: dark on a photo (white words), light on paper (ink words). The dock and the toast are Liquid Glass on iOS 26 and frosted before.
- Screen margin 20 pt. Hairlines only between moments of the day, days of the diary and ranked rows.

## Type

DM Sans only, bundled (SIL Open Font License), one variable font: weight and optical size, which follows the point size so small labels open up and big numbers tighten. Text is regular or medium; semibold is for titles and numbers.

| Use | Size | Weight |
|---|---|---|
| The day's number on the cover | 66 | medium, tracking −4% |
| Range average | 36 | medium |
| Screen title (Last 7 days) | 30 | semibold |
| Calories in the ring | 30 | medium |
| A food's name, a meal's name on its page | 27 | medium |
| Macro grams | 17 | semibold |
| Section title (Your day, Calorie estimates), with its symbol | 20 | semibold |
| Meal and day names | 16 | semibold |
| Body, list rows | 15 to 17 | regular or medium |
| Chips, captions, times | 13 to 14 | regular or medium |
| Smallest labels | 12 | regular |

- A number is the biggest thing in its block. Its unit sits beside it, smaller and in the secondary color: `967 kcal left today`, `62 / 125 g`.
- Nothing smaller than 12 pt.

## Color: one job each

| Job | Color | Where |
|---|---|---|
| Protein, carbs, fat | #D2693C, #4C7FC0, #3E9A76 | the ring's dots, the glyph tiles and the rules under the macros, always with their names. The trio passes the color-vision checks on paper and on the dark page. |
| Still to eat | warm gray dots | the rest of the ring |
| Over the goal | red #D9482B | the ring's outer dots, a day's dot and number, a bar |
| A day's verdict | green on target, gray light, red over | the dot beside a day |
| Burned, steps | the Move ring's pink, indigo | their two chips under the macros |
| The streak | sunny flame | the streak pill on the cover |
| Status | green (good, with a leaf), warm (worth a look), blue (info) | soft chips, always with words |
| Rank | gold for 1, green for 2 and 3 | laurels |
| Food tiles | sand, peach, butter, mint, sky, lilac, blush | a basic food's emoji sits on its tint; a product's hero glows in its tint |
| Water | #2E9BD6 | the drop on the water chip and its fill; the drop means water only, fat wears the avocado |
| Accuracy | green, blue #2F7FD8, orange #E0872B, gray | a dish's gauge and its tier dot, by tier |
| An estimate's source | blue sparkle, gray pencil #5E5C57 | the badge on the avatar of the person who counted it |
| Main action | ink capsule | one per screen: Scan on home, Add to today on a food |
| Scan | the laser red | the barcode glyph in the Scan capsule, the only thing that moves on home |

## Media

One tile shape for every food (corners 19% of the size): 76 pt on Today and Saved, 58 pt in the diary.

- **Product photo** (Open Food Facts): whole, on a white tile with a hairline, its white background multiplied away.
- **Your photo** (a plate Claude estimated, a saved food): fills the tile, and becomes the day's cover. Photos are kept at 1000 px so a cover stays sharp.
- **Basic food or quick add**: its emoji on its pastel.

## Icons and emoji

- **SF Symbols** for everything that is not a food: actions, chips (flame, shoe prints, leaf, drop), the streak flame, the settings gear. Outline for actions, filled for data and to show state (`bookmark.fill` means saved). Never bold.
- **Section titles carry their symbol**, Apple Health style: ink, or the color of what the section counts (the calories flame in amber for Calorie estimates, gold for Best days).
- **Macro glyphs**, drawn in `MacroGlyph` on a 24 point grid like SF Symbols: a drumstick for protein, a wheat ear of tapered kernels for carbs, half an avocado with its stone for fat (a drop read as water). Foods people know at a glance, so the glyph says the macro before the color does. In a list they lead the row on a tile, Settings style: the macro's color at 24%, the glyph a step deeper (a step lighter at night). On the ring they sit on a disc in the middle of their arc. The glyph fills about three quarters of its tile or disc: bigger glyphs, never bigger discs. Rows beside them that are not macros (calories in the editor) get a `SymbolTile` of the same shape and strength.
- **Emoji** only as food pictures: tiles, ingredients, the meal an estimate found.

## Charts

- **The dotted ring**: six rings of fine dots, a halftone. On Today the lit dots are the day's calories against its goal, in the colors of where they came from (protein, carbs, fat), with a one-dot gap between parts; gray dots are still to eat; past the goal, the overflow runs round the outer ring in red. On a food the ring is that food's calories, all lit. The dots light up round the ring when it appears.
- **Each macro's glyph rides its arc** on a disc, when the arc is at least 8% of the ring, and appears as the light reaches it.
- **The macro list** beside the ring, one line per macro: the glyph tile, the name, the grams. On Today the grams sit over the target (`62 / 125 g`) and a 3 pt rule under the line fills toward it, red when carbs or fat pass it (more protein is fine). On a food the line ends with the macro's share of the calories, and hairlines part the lines. One block, `MacroBlock`, on Today, a food and a photo estimate: the 150 pt ring on the left, the list on the right. The words in the ring stay short in every language ("kcal" over "mangées"), since the inner ring narrows below the number.
- **Range columns**: each day a column of dots, the ring's halftone, against the goal's dashed line; ink up to the goal and red for the dots past it; they rise from the baseline when they appear. Seven on the right of the week's average, thirty under the month's.
- **Where your weight is heading**: your weighings from Apple Health as dots, today as a hairline, then a dotted road to the weight four weeks on at the way you ate over the last week's whole days (at least three days of 800 kcal or more), against what your body burns (Mifflin-St Jeor times activity, about 7,700 kcal to a kilo). Green when it heads toward your goal, gray otherwise; the weight at its end in big numbers, one sentence on why, and "An estimate" in small print.
- **Accuracy gauge**: a ring filled to a dish's accuracy with the number inside, in its tier's color.
- Labels wear text colors, never the series color.

## Scores, verdicts, ranks

- **Day score, out of 100**: 60 for landing near the calorie goal, 25 for protein, 15 for food quality (Nutri-Score, weighted by calories). Same rule every day, so days rank fairly.
- **Verdicts**: On target (90 to 105% of the goal), Light day, N kcal over. Friendly, never shaming.
- **Streak**: days logged in a row. Today joins as soon as something is logged, and a light or over day keeps it going: the streak is for showing up, never a punishment for a dinner out. The week's dots say how the days went.
- **Ranks**: best days and most eaten foods, with laurels for the top three.
- **Moves**: ▲ / ▼ with the percentage against the days before, colored only when the direction is good or bad news.

## Screens

- **Today**: the cover (switcher, streak, settings; the number left or over; the place or the meal, and the goal), then the ring and the macros; burned, steps and water as chips (the water chip fills toward the day's glasses, one tap a glass); If you keep this up; Your day as a timeline (time, meal, calories, tiles), and after it your usual meal when its hour comes (the same foods at the same meal on three days of the last two weeks, from an hour before its time to two hours after, its tiles faded until you add it, Not today to put it away); the saved shelf, titled "Fits your 967 left" while there is room, foods that fit first, protein-dense first when protein is behind, with one line saying so; Near you, the dishes people counted around you; This week, a dot a day (tap one to open it). The dock floats at the bottom: search, Scan, quick add.
- **Where you ate**: a Place row beside the time on every log. It opens the places around you (Apple Maps, nearest first, a search by name), asking for location the first time, While Using, with a line on why.
- **A place**: its name, kind, area and distance, Directions (Apple Maps, walking) and Order (Uber Eats), then its dishes, each with its picture, calories, how many estimates, and the accuracy gauge; Add a dish.
- **A dish**: the hero, the name and its place, stars and estimates in one line, the ring and the macros the estimates add up to, then Calorie estimates: the accuracy row (gauge, tier, what it rests on; it opens how it is worked out), each estimate (avatar with a sparkle badge for an AI scan or a pencil for one typed by hand, the calories, and a like that says it matches your plate), Add your estimate (by hand or from a photo), your stars, and Add to today. Accuracy is agreement times coverage: how close the counts are, times how many people stand behind them (each count weighs one plus its likes). Very accurate from 90, Accurate from 70, Roughly right from 50.
- **The switcher** behind the day's name: today and the six days before it, then the last 7 and 30 days.
- **Last 7 days, last 30 days**: the daily average and its dot columns (a faint dot for a day with nothing logged), the days as a food diary (dot, calories, up to four foods, photos first; tap one to open it), best days, most eaten. Whole days only: today joins tomorrow.
- **A food, a photo estimate**: the hero, then the sheet: name, brand, chips (Nutri-Score, processing, highlights), the ring and the macros, the amount (portions, then − and +), the label on demand. Meal picker and the ink button at the bottom. A photo estimate asks its biggest doubt as a question under the confidence chip ("How much dressing was on it?": No dressing, A drizzle, Poured on), the likeliest answer chosen; a tap sets that ingredient and every number above it.

## Components

`DayCover`, `DottedRing`, `MacroList`, `MacroBlock`, `MacroGlyph`, `MacroTile`, `SymbolTile`, `ActivityChips`, `DayTimeline`, `SavedShelf`, `RangeView`, `FoodHero`, `ScanDock`, `ScanGlyph`, `AddedToast`, `GlassCircleButton`, `coverGlass(in:onPhoto:)`, `floatingGlass(in:)`, `Card`, `InsetBox`, `SectionLabel`, `FoodThumb`, `TintChip`, `NutriScoreChip`, `LaurelBadge`, `ChangeLabel`, `ProgressBar`, `MealMenuLabel`, `BookmarkButton`. Buttons: `PrimaryButtonStyle` (ink, one per screen), `SoftButtonStyle`, `ChipButtonStyle`, `PressableStyle`. Tokens live in `Bite/Design/Theme.swift`, the typeface in `Bite/Design/Typeface.swift`.

## Interactions

- **Do, then offer Undo; never "are you sure?".** An add or a delete happens at once and a toast slides up over the dock for 4 seconds with Undo. A delete keeps a copy of the entry until the toast leaves.
- **Edit in place.** Tap a meal's time to move it with a wheel in a small popover. A food's page has its own Time, set to now on its own, so logging late never needs a form.
- **Repeat without retyping.** Press and hold a food for Add again (Add to today on a past day); hold a past meal for Add to today. Most people eat the same few meals.
- **Haptics only where they mean something:** a tick when the switcher changes day, a rising or falling tick on − and +, a success on add and the moment today lands on target. Navigation taps stay silent.
- **Teach once, in place.** Two tips, never a tour: hold a food (on the first tile), and the switcher (from the third visit). Each disappears once you have used the gesture.
- **Beyond the app.** Scan food (opens the camera, for the Action button, Siri, Spotlight and Shortcuts) and Log a saved food ("Log Morning skyr in Bite", without opening the app).
- **No dead ends.** A barcode with no data offers Snap the label first, then Type it in. A typo still finds its food: when nothing matches as typed, one slip per word of four letters or more is forgiven (a letter wrong, missing, added or swapped; the first letter has to be right).
- **Your data is yours.** Settings exports the whole log as a spreadsheet (CSV, a point for decimals, accents kept), and says the log stays on the phone.

## Motion

The scan laser sweeps, numbers roll, the ring's dots light up round from twelve o'clock and each macro's glyph appears as the light reaches it, the range bars grow, covers stretch when pulled, and "Added to Breakfast" slides up over the dock, then leaves after 2.6 seconds. Reduce Motion stops the laser and lights everything at once.

## Copy

Short and friendly. The first words carry the meaning. No dashes.

**Languages: English, French, Spanish.** Written in each language, never translated word for word. French says *tu*, uses a narrow no-break space before `: ? ! %` and curly apostrophes; Spanish is from Spain and says *tú*. Apple's own words win: Réglages and Ajustes, l'app Santé and la app Salud. Labels next to a number agree with what it counts ("kcal mangées", "quemadas": calories). Every key lives in `Bite/Resources/Localizable.xcstrings`; `tools/check_strings.py` fails on any word without both translations.
