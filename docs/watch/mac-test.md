# SAVY Watch: the last look on Adam's devices

Only when Adam asks for it. Adam, Nov 21: “No, no more testing. I mean, for me to have to be here while you fucking test it, you have to be kidding me.” And: “Do 1000% of your tests on a fucking simulator.”

Everything a simulator can show is proven on GitHub first; see “Test in simulators first” in [SAVY Watch](savy-watch.md). What is left needs his own iPhone and Watch: his iCloud account, the real microphone, and the words written out from his voice.

What his devices hold: the fixed build, installed on Nov 21 at about 6:57 pm his time, when he asked the session on his Mac Studio for it. The iPhone app is this branch at `35f567c` merged with Send to AI, with the Watch app inside it, and the Watch has the copy from inside that iPhone app.

His own look, that evening: he recorded one sentence on the Watch and the words were on his wrist 1.4 seconds after he stopped. The capture then reached iCloud and became a Social entry on the iPhone, with the words and the recording. SAVY was open and unlocked on the iPhone.

Then he asked: “test it with the iPhone locked in my pocket”. Both pocket cases passed, each with the words on his wrist 2.1 seconds after he stopped: the iPhone locked with SAVY in the background, and the iPhone locked with SAVY not running, where the Watch's message opened SAVY by itself.

Still not shown on his devices: the iPhone out of reach, and a recording that continues after the wrist drops. The steps below are for the next install, or for reading those cases when he chooses to try them.

When he asks, a Claude session on his Mac Studio, which can reach his iPhone and Apple Watch Ultra 3:

1. Fetches `claude/awesome-heisenberg-s7jdkk` and checks that GitHub's last “Watch build” run on it passed, link test included.
2. Builds the iPhone app from a local merge of that branch and `claude/ai-communication-interface-b714f9` (Send to AI, which already contains `main`). The merge conflicts only in `AGENTS.md`; keep both sides. Never install the iPhone app from the Watch branch alone. Do not push the merge unless Adam says to.
3. Before touching the iPhone, follows `AGENTS.md`: confirms with Adam that SAVY has no open editor with unsaved writing, backs up its saved files, installs in place, then compares the saved files.
4. Installs the iPhone app. The Watch app is inside it and should arrive on the Watch through it. If it does not arrive, installs the copy from inside the built iPhone app (`SAVY.app/Watch/SAVYWatch.app`) on the Watch; the simulator test installs it that way and the pair works. Does not build and install the `SAVYWatch` scheme by itself: that left the two apps unable to see each other on Nov 21. On his devices on Nov 21 the system carried the Watch app across by itself: installs on the Watch were refused while it did (CoreDeviceError 3002), and one made about 40 seconds after the iPhone install went through. So wait a minute after the iPhone install before touching the Watch.
5. Asks Adam to open SAVY on the iPhone once, then to record one real sentence on the Watch and look at the review screen. The words must be his: no made-up test entries in his live SAVY or iCloud.
6. Runs:

   ```bash
   python3 .cursor/skills/watch-capture/scripts/watchtrail.py pull --config watch-capture.json
   ```

   It copies each app's `Library/Application Support/SAVYWatch/trail.jsonl` off the Watch and iPhone and prints where the capture stopped.
7. Tells Adam in a few lines: did the words reach the wrist, did the entry appear, and if not, the exact step and reason.

Keep every answer to a few lines, and do not keep him at his desk: one capture, one answer. Do not change the approved Watch look or the frozen entry form styling.
