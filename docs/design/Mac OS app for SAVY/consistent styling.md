# consistent styling (Executive Conclusion)

1. 🖥️ The installed Mac Theme and Visual selectors now follow the phone reference while closed and while open.

2. 🔤 The existing Mac form font size is preserved.

3. 💾 All four saved archives remain byte-identical to the fresh preinstallation backup.

# Both selector states were checked (Consequence)

1. 🎨 The opened panels have rounded cream backgrounds and crimson symbols. Spacious rows carry a separate selection check. Both panels stay inside the form without arrows.

2. ⌨️ Installed Release checks confirmed that selecting Summarize updates four questions. Escape closes the panel while keeping the form open.

3. 📱 Scope is Mac Theme and Visual. Other pickers were not modified; no physical phone action occurred.

# Installed and verified (Recommendation)

The signed Release app is installed at `/Applications/SAVY.app` and launched normally. Both opened selectors and the closed controls were inspected in that installed app. The blank form was canceled without saving. No synthetic writing was added.

The earlier `5b736a9` opened menu was rejected. These screenshots document its replacement. Repo and Mac copies match. Cowork copies are staged; cloud upload remains unconfirmed.

# Installed screenshots and test record (Supporting Evidence on Request)

Adam's latest request, verbatim:

> Is there a reason I have to compromise when using the Mac OS? Why can’t I have the same styling across iOS and OS? This is the only thing I’ve been asking for is consistent styling, and it’s the only thing you will not check for

The Release script exited 0 and built/launched `/Applications/SAVY.app`. Strict code-signature verification passed. The observed executable was `/Applications/SAVY.app/Contents/MacOS/SAVY`, PID 87277. It matches the Release product, SHA256 `0f91c01e328e92099581a941f1f95b56d77a89960894207eef753733824568dd`.

The Mac-only shared selector uses an `anchorPreference` overlay at the form root, with no native Menu or popover arrow. Keyboard handling uses public `UIKeyCommand`. Panel spacing scales from the existing UIKit body metric. The iOS source projection, excluding blank lines, is identical to `5b736a9`.

| Check | Environment | Result |
| --- | --- | --- |
| Theme and Visual closed | Installed Release | Compared with phone treatment |
| Theme and Visual open | Installed Release | Compared with phone reference |
| Twelve Visual choices | Installed Release | All twelve visible |
| Summarize selection | Installed Release | Four questions updated |
| Escape | Installed Release | Panel closed; form remained open |
| Up arrow and Return | Isolated Debug | Tables selected |
| Theme browsing | Isolated Debug | 33 choices in accessibility tree; wheel scrolling reached the readable last long label and selection worked |
| Outside click | Isolated Debug | Panel dismissed without changing selection |

The font comparison uses the previously installed `5b736a9` screenshot and the final isolated Debug preview, both 1408 × 1520 pixels. The installed Release was inspected separately. Measured text-ink bounds, in pixels:

| Text | Previous installed | Final isolated Debug |
| --- | ---: | ---: |
| Theme | 81 × 19 | 81 × 19 |
| Visual | 69 × 19 | 69 × 20 |
| Habit | 61 × 19 | 61 × 19 |
| Matrices | 101 × 19 | 101 × 19 |
| First Decide question | 190 × 20 | 190 × 20 |
| First Visual question | 584 × 24 | 584 × 24 |

Final saved-file comparison:

| Saved archive | Before | After | File comparison |
| --- | ---: | ---: | --- |
| Main entries | 54 | 54 | Identical |
| Recovery drafts | 0 | 0 | Identical |
| Connections | 3 | 3 | Identical |
| Legacy posts | 1 | 1 | Identical |

[Verification record](</Users/adamblair/Developer/GitHub/SAVY-iOS/docs/design/Mac OS app for SAVY/consistent styling.json>)

## don't change the font size

Installed Release with both selectors closed.

![Installed Mac form with compact closed selectors and existing typography](</Users/adamblair/Developer/GitHub/SAVY-iOS/docs/design/Mac OS app for SAVY/don't change the font size.jpg>)

## Theme

The installed Theme choices use the same panel treatment as Visual.

![Installed Release Theme panel with crimson icons and a selection check](</Users/adamblair/Developer/GitHub/SAVY-iOS/docs/design/Mac OS app for SAVY/Theme.jpg>)

## consistent styling

Installed Visual panel with Summarize selected and all twelve choices visible.

![Installed Release Visual choices matching the phone reference](</Users/adamblair/Developer/GitHub/SAVY-iOS/docs/design/Mac OS app for SAVY/consistent styling.jpg>)
