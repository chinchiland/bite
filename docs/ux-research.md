# Premium details: what the best apps do, what Bite does

Research from October 2026: Apple's guidelines and WWDC sessions, what MacroFactor, Cal AI, MyFitnessPal, Cronometer, Foodnoms and others are praised and blamed for, and how community apps (Waze, Google Maps, Apple Maps) collect data people trust. Each finding says where Bite stands. The rules that came out of it live in [DESIGN.md](../DESIGN.md#interactions).

## In the app now

| Finding | Where it comes from | In Bite |
|---|---|---|
| Undo beats "are you sure?". Users of one tracker that added a confirmation step to delete now call deleting a three-action chore; the ask everywhere is a Gmail-style undo. | Apple HIG, [Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo); user threads summarized by Gemini | Every add and delete happens at once, with Undo in the toast for 4 s. |
| Food belongs to a time, not a box, and the time should be set for you but easy to move. | MacroFactor, [timeline food log](https://macrofactor.com/timeline-based-food-logger/) | The timeline shows each meal's time; tap it to move the meal with a wheel. A food's page has a Time row set to now. |
| Speed is counted in actions. MacroFactor's own index puts it at 24 actions across four common logs; the average app needs about 70% more, mostly from re-entering repeat foods and extra steps for servings. | MacroFactor, [Fastest Food Logger Index 2025](https://macrofactor.com/fastest-food-logger-2025/) (their own test) | One-tap adds from Saved and Recent stay in search; quick add is 3 actions; hold a food to Add again, hold a past meal to add it to today. |
| Haptics sparingly, only when they carry meaning. | Apple HIG, [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics) | A tick when the switcher changes, rising and falling ticks on − and +, success on add and when today lands on target. Nothing else buzzes. |
| Teach hidden gestures in context, never with a tour. | WWDC23, [Discover TipKit](https://developer.apple.com/videos/play/wwdc2023/10228/) | Two tips: hold a food (first tile) and the day switcher (from the third visit). |
| The app should work from outside its icon: Siri, Spotlight, Shortcuts, the Action button. MacroFactor maps the Action button to its scanner. | WWDC24, [What's new in App Intents](https://developer.apple.com/videos/play/wwdc2024/10134/) | Scan food (opens the camera) and Log a saved food (runs without opening the app). |
| A barcode with no data should not be a dead end: read the label instead. | Foodnoms and FitBee, as summarized by Gemini | Not found now offers Snap the label first, then Type it in. |
| Fix one ingredient of an AI estimate without starting over; oil and butter are what photos miss. | Cal AI reviews, [Kimola report](https://kimola.com/reports/unveil-user-insights-on-cal-ai-calorie-tracker-app-store-us-155190) | Ingredients are bubbles you tap to adjust (already there). |

## Next for the app

1. **Widgets**: calories left with the ring on the Home and Lock Screen, and an interactive Scan button. Needs a widget extension and a shared app group. ([WWDC23, Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/))
2. **Control Center and Lock Screen control** for Scan. ([WWDC24, Extend your app's controls](https://developer.apple.com/videos/play/wwdc2024/10114/))
3. **Dynamic Type** for DM Sans: scale with the reader's text size, capped on the big numbers. ([HIG, Typography](https://developer.apple.com/design/human-interface-guidelines/typography))
4. **Log by sentence**: "two eggs and a coffee" to Claude, for things a photo can't catch.
5. **A quick "+ oil" chip** on photo estimates, the most common miss.
6. **Break a saved meal back into its foods** for one day, without changing the saved meal (MacroFactor calls it explode).
7. **Meal reminders**, opt-in, at the times you usually eat.
8. **Apple Watch**: calories left and Quick add only.

## For the community dishes

| Pattern | Who does it | For Bite |
|---|---|---|
| Ask for one tap when it is fresh: "Still there?" pops up as you pass a report; each report has a confidence score from those taps, plus a reliability score from the reporter's experience. | Waze ([support](https://support.google.com/waze/partners/answer/10618551)) | After you log a community dish, the next time you open Bite: "Was Salmon poke bowl about right? ✓ / Fix". Confirmations drive C3's levels; a new contributor's entries start lower than a trusted one's. |
| Rate with one tap, details optional on a second screen. | Apple Maps ratings, thumbs then attributes ([9to5Mac](https://9to5mac.com/2021/08/23/apple-maps-native-ratings-and-photo-system-now-available-in-the-us/)) | Stars or thumbs in one tap on the dish; tags (spicy, big portion) only if you want. |
| Points for real contributions, levels that unlock trust, a badge from level 4. A rating or a fact check is 1 point, a photo 5, a review 10. | Google Maps Local Guides ([official](https://support.google.com/maps/answer/6225851?hl=en)) | Contributor levels that let trusted people fix entries; never a pop-up celebration after every log. |
| Tap the location to change it: a half sheet with search, your current location and a pin you can drag. Ask for location the first time it is needed, with a line on why. | Google Maps, Yelp, Foursquare (Gemini summary) | The restaurant chip on Add a dish opens that sheet; "Near me" asks for location in place. |
| Competing answers ranked by the community. | Stack Overflow, Reddit | C3 with D-round's list: the Verified entry leads, the others follow by confirmations. |
| Votes and confirmations show at once and sync after. | Common practice | Optimistic updates, undone if the server refuses. |

## What to avoid

- Interruptions after every log (spin wheels, streak pop-ups, forced tips). Users are leaving apps over it.
- Forcing an exact time or a form to log late. The time is set for you; changing it is optional.
- Hiding the barcode scanner or quick add behind a paywall or a carousel.
- Confirmation dialogs for routine deletes.
