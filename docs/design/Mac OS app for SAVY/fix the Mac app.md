# fix the Mac app (Executive Conclusion)

1. 🖥️ The installed Mac app now shows matching compact crimson Theme and Visual controls without gray dropdown boxes.

2. 🔤 The existing Mac body font size is preserved. Question and editor sizing is unchanged.

3. 💾 All four saved archives match their fresh preinstallation backups byte-for-byte.

# The installed controls match (Consequence)

1. 🎨 The installed Social form shows Theme/Habit and Visual/Matrices with compact crimson controls. The redundant standalone headings remain absent.

2. 🧪 Isolated Debug checks passed Theme selection, including a long Theme label. The Visual menu displayed all twelve choices; selecting Summarize updated its four questions.

3. 📱 The change is conditional to Mac Catalyst. No physical iPhone action occurred.

# Installed and inspected (Recommendation)

The signed Release app is installed at `/Applications/SAVY.app` and launched normally. The blank Social form was canceled without saving after its appearance was inspected.

The earlier Mac deferral was reopened by Adam's explicit request. Repo and Mac evidence copies match. Cowork copies are staged; cloud upload remains unconfirmed.

# Installed Release evidence (Supporting Evidence on Request)

Adam's request, verbatim:

> Now fix the Mac app so Visual matches Theme like it does on the phone. No obvious dropdown boxes, and don't change the font size.

The Release build logged `BUILD SUCCEEDED`, and strict code-signature verification passed. The running executable was `/Applications/SAVY.app/Contents/MacOS/SAVY`, observed as PID 79061. The installed executable matches the signed Release product with SHA256 `84cb8de0b026a1593a1596c63a35274c3385b8d41e5ebbe94ad7f9373bbea4b8`.

Both controls use the same Mac-only plain Menu helper and existing selection bindings. Explicit body typography preserves the Mac's previous size. Existing question/editor sizing is unchanged.

The font comparison uses the original installed Mac screenshot and the final isolated Debug preview, both 1408 × 1520 pixels. The final installed Release was inspected separately. Measured text-ink bounds, in pixels:

| Text | Before width × height | After width × height |
| --- | ---: | ---: |
| Theme | 81 × 19 | 81 × 19 |
| Visual | 69 × 19 | 69 × 20 |
| Habit | 61 × 19 | 61 × 19 |
| Matrices | 101 × 19 | 101 × 19 |
| Make it Obvious | 190 × 20 | 190 × 20 |
| First Visual question | 584 × 25 | 584 × 25 |

Final saved-file comparison:

| Saved archive | Before | After | File comparison |
| --- | ---: | ---: | --- |
| Main entries | 54 | 54 | Identical |
| Recovery drafts | 0 | 0 | Identical |
| Connections | 3 | 3 | Identical |
| Legacy posts | 1 | 1 | Identical |

[Verification record](</Users/adamblair/Developer/GitHub/SAVY-iOS/docs/design/Mac OS app for SAVY/fix the Mac app.json>)

The original screenshot below shows the installed signed Release app.

![Installed Mac app with matching compact Theme and Visual controls](</Users/adamblair/Developer/GitHub/SAVY-iOS/docs/design/Mac OS app for SAVY/fix the Mac app.png>)
