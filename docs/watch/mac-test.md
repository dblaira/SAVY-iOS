# SAVY Watch: the test, run from Adam's Mac

Adam, Nov 21: “The Apple Watch SAVY app works and doesn't work. It needs a lot of testing. Help me figure out how to test it or test it yourself.”

For a Claude session running on Adam's Mac Studio, which can reach his iPhone and Apple Watch Ultra 3. Give Adam a one-line update at every change of stage, and at least once a minute while anything runs. Keep every answer to a few lines.

1. Fetch `claude/awesome-heisenberg-s7jdkk` (head `6cdfc7e` or later; GitHub built both apps from it and its Watch tests pass). Read the “Apple Watch” section of `AGENTS.md` on that branch.
2. Find out, and tell Adam in one line: does the SAVY now on his iPhone contain the Watch code? The suspicion is that it does not. The iPhone app is normally built from `claude/ai-communication-interface-b714f9` (Send to AI), which has no Watch code. Without it, the words never come back to the wrist and no entry appears.
3. Build the iPhone app from a local merge of `claude/awesome-heisenberg-s7jdkk` and `claude/ai-communication-interface-b714f9` (it already contains `main`). A trial merge conflicted only in `AGENTS.md`; keep both sides. Never install the iPhone app from the Watch branch alone: it has no Send to AI. Do not push the merge unless Adam says to.
4. Before touching the iPhone, follow `AGENTS.md`: confirm with Adam that SAVY has no open editor with unsaved writing, back up its saved files, install in place, then compare the saved files. Install the Watch app (scheme `SAVYWatch`) on the Ultra 3 from the Watch branch.
5. Ask Adam to open SAVY on the iPhone once, allowing Speech Recognition if it asks, then to record one real sentence on the Watch and tap Save. The words must be his: no made-up test entries in his live SAVY or iCloud.
6. Run:

   ```bash
   python3 .cursor/skills/watch-capture/scripts/watchtrail.py pull --config watch-capture.json
   ```

   It copies each app's `Library/Application Support/SAVYWatch/trail.jsonl` off the Watch and iPhone and prints where the capture stopped. Its `devicectl` commands were written without a Mac and have not run. If one fails, fix it, or copy the two files by hand and use `watchtrail.py read`, and commit the fix to the Watch branch.
7. Tell Adam in a few lines: did the words reach the wrist, did the entry appear, and if not, the exact step and reason. If the cause is in the code, fix it. After changing kit files in SAVY, run `watchkit.py sync` and `watchkit.py files --check`.

Do not change the approved Watch look or the frozen entry form styling. The longer background is in [SAVY Watch](savy-watch.md), under “Testing on the Watch and iPhone”.
