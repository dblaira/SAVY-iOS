# visual themes

## Same native selector as Theme (Executive Conclusion)

1. 🎨 Format now uses the same native menu Picker and Label pattern as Theme.

2. ↕️ Its selected format has a crimson icon and name with the native chevrons. The gray custom box is removed.

## Writing stays intact (Consequence)

1. 💾 The picker keeps independent answers for all twelve formats and retains an unknown saved selected format as a tagged option.

2. 📐 This change leaves the fixed 17-point form font and existing Decide spacing unchanged.

## Ready off-phone (Recommendation)

The signed Debug iPhone build passed with unchanged source hashes during the final build. No phone installation or launch occurred during this correction.

## Screenshot and verification (Supporting Evidence on Request)

![visual themes](visual%20themes.png)

The simulator checked the matching Theme/Format presentation and all twelve menu choices. It verified exact answers across format switching, draft recovery, Save, relaunch and reopening. The question tap and long-answer expansion test also passed. The scrolling helper now uses bounded drags; recovered Save returns to Home, and the test navigates to Posts explicitly while asserting exactly one saved entry.

The native icon probe confirmed all twelve SF Symbols exist. The final build receipt is build-verification.json. This is a local signed Xcode build, not a GitHub Actions result.

Original typography was measured separately: all four prompts in IMG_3129.png matched 17-point semibold native renders at more than 99.3% glyph-pixel overlap. The first installation screenshot also matched 17-point semibold. The later 17-point regular override changed weight and font-setting behavior. The research and reproducible rendering probe are preserved in the social-media repository under artifacts/Visual templates/font size/.

Final exact-source verification: eight model/recovery tests and the native selector/all-twelve-choice smoke passed (9/9). Both tested production source files matched the checkout byte for byte. The earlier three selector/persistence/expansion cases passed (3/3). Raw test summaries are in test-verification.json.
