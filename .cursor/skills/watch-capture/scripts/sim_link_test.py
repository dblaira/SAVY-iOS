#!/usr/bin/env python3
"""Watch capture kit: tests the Watch-to-iPhone link in paired simulators, with no one at a desk.

Adam, Nov 21, 2026: "Do 1000% of your tests on a fucking simulator. That's what you should do. It
should work perfectly on a goddamn fucking simulator. Instead of sitting here holding me to this
fucking desk."

What it does, on a Mac with Xcode (a GitHub runner, or Adam's Mac with no device attached):
  1. Finds or makes a paired iPhone and Apple Watch simulator, boots both, and waits until the
     two are connected as a pair. Apps installed before that never see each other.
  2. Installs the iPhone app and the Watch app, and opens both.
  3. A simulator-only hook in the Watch app sends a spoken recording to the iPhone simulator,
     exactly as a finished recording is sent. A simulator-only hook in the iPhone app answers with
     set words, because a build machine has no one to allow Speech Recognition.
  4. Reads both apps' trails and prints, per capture, what worked and what stopped.

It runs up to four times: with the Watch app inside the iPhone app and both installed; if the
two apps did not see each other, once more with a second install, because a pair of simulators
that has just started for the first time can need longer; then with the iPhone app closed, as it
is in a pocket on a run, so the Watch's message has to open it; and last with the Watch app
installed on its own, which is how it was on Adam's devices on Nov 21, where the link failed with
WatchConnectivity 7018. It passes only when the words come back to the Watch with the Watch app
inside the iPhone app. The closed-iPhone run is reported beside it.

What a simulator cannot show: his iCloud account, the real microphone and Bluetooth. Those parts
(recording, iCloud, entry on the iPhone) worked on his own devices on Nov 21.

  sim_link_test.py --config watch-capture.json --app build/.../SAVY.app [--watch-app .../SAVYWatch.app]
                   [--phone UDID] [--out build/linktest]

Standard library only.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import watchtrail  # noqa: E402

WORDS = "Blue's Clues pauses so the kid can answer"
RECORDING = "linktest.m4a"
WORDS_FILE = "linktest-words.txt"  # read by the iPhone app's simulator-only hook when no one opens it
TRAIL = "trail.jsonl"

INSIDE = "inside the iPhone app"
AGAIN = "inside the iPhone app, second install"
CLOSED = "inside the iPhone app with the iPhone app closed"
ALONE = "installed on its own"
DECIDES = {INSIDE, AGAIN}  # the runs that decide the result


def run(command, check=False, quiet=False, timeout=300):
    if not quiet:
        print("$", " ".join(str(c) for c in command), flush=True)
    done = subprocess.run([str(c) for c in command], capture_output=True, text=True, timeout=timeout)
    if done.returncode != 0 and not quiet:
        print((done.stderr or done.stdout).strip()[:600], flush=True)
    if check and done.returncode != 0:
        sys.exit(f"failed: {' '.join(str(c) for c in command)}")
    return done


def simctl(*args, **kwargs):
    return run(["xcrun", "simctl", *args], **kwargs)


def available_devices():
    data = json.loads(simctl("list", "devices", "available", "-j", quiet=True, check=True).stdout)
    phones, watches = [], []
    for runtime in sorted(data["devices"], reverse=True):
        for device in data["devices"][runtime]:
            if "iOS" in runtime and device["name"].startswith("iPhone"):
                phones.append(device)
            elif "watchOS" in runtime and device["name"].startswith("Apple Watch"):
                watches.append(device)
    return phones, watches


def pick_pair(wanted_phone):
    """A paired (phone udid, watch udid), using an existing pair when there is one."""
    phones, watches = available_devices()
    if not phones or not watches:
        sys.exit(f"need an iPhone and an Apple Watch simulator; found {len(phones)} and {len(watches)}")
    phone_ids, watch_ids = {d["udid"] for d in phones}, {d["udid"] for d in watches}
    pairs = json.loads(simctl("list", "pairs", "-j", quiet=True, check=True).stdout).get("pairs", {})
    usable = [(p["phone"]["udid"], p["watch"]["udid"]) for p in pairs.values()
              if p.get("phone", {}).get("udid") in phone_ids and p.get("watch", {}).get("udid") in watch_ids]
    for phone, watch in usable:
        if wanted_phone in (None, phone):
            print(f"using the existing pair: iPhone {phone} + Watch {watch}")
            return phone, watch
    phone = wanted_phone or phones[0]["udid"]
    paired_watches = {p.get("watch", {}).get("udid") for p in pairs.values()}
    free = [d["udid"] for d in watches if d["udid"] not in paired_watches]
    for watch in free:
        if simctl("pair", watch, phone).returncode == 0:
            print(f"paired: iPhone {phone} + Watch {watch}")
            return phone, watch
    # Every Watch simulator is taken or would not pair: make a new one of the newest kind.
    newest = watches[0]
    made = simctl("create", "Link Test Watch", newest["deviceTypeIdentifier"], check=True).stdout.strip()
    simctl("pair", made, phone, check=True)
    print(f"made and paired: iPhone {phone} + Watch {made}")
    return phone, made


def boot(udid):
    simctl("boot", udid, quiet=True)
    simctl("bootstatus", udid, "-b", timeout=600)


def pair_state(phone, watch):
    """How the two simulators stand as a pair, in simctl's words, such as "active, connected"."""
    listed = simctl("list", "pairs", "-j", quiet=True).stdout
    try:
        pairs = json.loads(listed).get("pairs", {})
    except ValueError:
        pairs = {}
    for pair in pairs.values():
        if pair.get("phone", {}).get("udid") == phone and pair.get("watch", {}).get("udid") == watch:
            if pair.get("state"):
                return str(pair["state"]).strip("() ")
    # Older simctl: read the plain list, where each pair's first line ends with its state.
    for block in re.split(r"\n(?=\S)", simctl("list", "pairs", quiet=True).stdout):
        if phone in block and watch in block:
            found = re.search(r"\(([^()]*)\)\s*$", block.splitlines()[0])
            return found.group(1).strip() if found else block.splitlines()[0].strip()
    return "not listed"


def is_connected(state):
    return "connected" in state and "disconnected" not in state


def wait_for_pair(phone, watch, limit=420):
    """Waits until the two simulators are connected as a pair. Apps installed before that never
    see each other as a pair: on a GitHub runner the pair is new, and it connects a few minutes
    after both simulators have started."""
    start, last = time.time(), None
    while True:
        state = pair_state(phone, watch)
        if state != last:
            print(f"the simulator pair after {int(time.time() - start)}s: {state}", flush=True)
            last = state
        if is_connected(state):
            return True
        if time.time() - start > limit:
            print(f"the simulators were not connected as a pair after {limit}s; going on anyway", flush=True)
            return False
        time.sleep(10)


def container(udid, bundle):
    done = simctl("get_app_container", udid, bundle, "data", quiet=True)
    return Path(done.stdout.strip()) if done.returncode == 0 and done.stdout.strip() else None


def store_folder(udid, bundle, folder):
    """Where the app keeps its trail, in the simulator's files."""
    data = container(udid, bundle)
    return data / "Library/Application Support" / folder if data else None


def how_installed(udid, bundle):
    """Prints how the simulator has the app on record (its companion, its type), to explain a pairing."""
    listing = simctl("listapps", udid, quiet=True).stdout
    at = listing.find(f'"{bundle}" =')
    if at < 0:
        at = listing.find(f"{bundle} =")
    if at >= 0:
        block = listing[at:at + 1600]
        keep = [line.strip() for line in block.splitlines()
                if any(key in line for key in ("ApplicationType", "Companion", "WK", "CFBundleVersion", "Path ="))]
        print("on record on the Watch simulator: " + "; ".join(keep)[:700], flush=True)


def system_notes(phone, watch):
    """When the two apps never saw each other: what each simulator's own WatchConnectivity
    service logged in the last few minutes, to show why."""
    for name, udid in (("iPhone", phone), ("Watch", watch)):
        try:
            done = simctl("spawn", udid, "log", "show", "--last", "4m", "--style", "compact",
                          "--predicate", 'process == "wcd" OR process == "appconduitd"',
                          quiet=True, timeout=180)
        except subprocess.TimeoutExpired:
            print(f"--- {name} simulator: its log took too long to read ---", flush=True)
            continue
        lines = [line[:300] for line in done.stdout.splitlines() if line.strip()]
        print(f"--- {name} simulator, WatchConnectivity service, last {min(len(lines), 30)} of {len(lines)} lines ---")
        for line in lines[-30:]:
            print("  " + line)
        sys.stdout.flush()


def read_trail(path):
    events = []
    if path and path.exists():
        for line in path.read_text(errors="replace").splitlines():
            try:
                events.append(json.loads(line))
            except ValueError:
                pass
    return events


def one_run(label, phone, watch, phone_app, watch_app, cfg, recording, out, install=True, phone_open=True):
    """Runs the link test once, and returns (words came back, the Watch's last link state).
    With `install` False, the apps stay as the run before left them. With `phone_open` False, the
    test closes the iPhone app and does not open it again: the Watch's message has to do that, as
    it does with the iPhone in a pocket."""
    phone_bundle, watch_bundle = cfg["xcode"]["companionBundleID"], cfg["xcode"]["watchBundleID"]
    folder = cfg["storageFolder"]
    print(f"\n===== Link test: Watch app {label} =====", flush=True)
    for udid, bundle in ((watch, watch_bundle), (phone, phone_bundle)):
        simctl("terminate", udid, bundle, quiet=True)
        if install:
            simctl("uninstall", udid, bundle, quiet=True)
    time.sleep(5)
    print(f"the simulator pair: {pair_state(phone, watch)}", flush=True)
    if install:
        simctl("install", phone, phone_app, check=True)
        simctl("install", watch, watch_app, check=True)
        # Give the two systems a moment to tell each other what was installed.
        time.sleep(20)

    store = store_folder(watch, watch_bundle, folder)
    if store is None:
        sys.exit("the Watch app's data folder was not found after install")
    if install:
        how_installed(watch, watch_bundle)
    (store / "Audio").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(recording, store / "Audio" / RECORDING)
    watch_trail = store / TRAIL
    if watch_trail.exists():
        watch_trail.unlink()

    phone_store = store_folder(phone, phone_bundle, folder)
    if phone_open:
        simctl("launch", phone, phone_bundle, "-WatchCaptureLinkTestWords", WORDS, check=True)
        time.sleep(10)
    else:
        if phone_store is None:
            return False, "the iPhone app's data folder was not found"
        phone_store.mkdir(parents=True, exist_ok=True)
        (phone_store / WORDS_FILE).write_text(WORDS)
        if (phone_store / TRAIL).exists():
            (phone_store / TRAIL).unlink()
        print("the iPhone app is closed and the test does not open it", flush=True)
    simctl("launch", watch, watch_bundle, "-WatchCaptureLinkTest", RECORDING, check=True)

    deadline = time.time() + 300
    done = False
    while time.time() < deadline and not done:
        time.sleep(5)
        done = any(e.get("step") == "linktest.done" for e in read_trail(watch_trail))
    if not done:
        print("the Watch app did not finish the link test in time", flush=True)

    phone_store = phone_store or store_folder(phone, phone_bundle, folder)
    phone_trail = phone_store / TRAIL if phone_store else None
    saved = out / label.replace(",", "").replace(" ", "-")
    saved.mkdir(parents=True, exist_ok=True)
    files = []
    for name, path in (("watch-trail.jsonl", watch_trail), ("iphone-trail.jsonl", phone_trail)):
        if path and path.exists():
            shutil.copyfile(path, saved / name)
            files.append(saved / name)
    for udid, name in ((watch, "watch.png"), (phone, "iphone.png")):
        simctl("io", udid, "screenshot", saved / name, quiet=True)
    if not phone_open and phone_store and (phone_store / WORDS_FILE).exists():
        (phone_store / WORDS_FILE).unlink()

    events, notes = watchtrail.load(files)
    print("--- every step, both simulators ---")
    for event in events:
        print(f"  {event['when'].strftime('%H:%M:%S')} {event.get('side', '?'):<6} "
              f"{'ok    ' if event.get('ok') else 'FAILED'} {event.get('step', ''):<16} "
              f"{(event.get('capture') or '-')[:8]:<8} {event.get('detail') or ''}")
    watchtrail.report(events, notes)
    if not phone_open:
        opened = any(e.get("side") != "watch" and e.get("step") == "app.launch" for e in events)
        print(f"the Watch's message opened the iPhone app by itself: {'yes' if opened else 'no'}", flush=True)
    words_back = any(e.get("step") == "link.words" and e.get("ok") for e in events)
    state = next((e.get("detail") for e in reversed(events)
                  if e.get("side") == "watch" and e.get("step") in ("link.activate", "link.reach", "link.state")),
                 "no link line")
    if not words_back and label != ALONE and "iPhoneAppInstalled=no" in state:
        system_notes(phone, watch)
    return words_back, state


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", required=True)
    parser.add_argument("--app", required=True, help="the iPhone app built for the simulator, with the Watch app inside")
    parser.add_argument("--watch-app", help="the Watch app built for the simulator; default: the one inside --app")
    parser.add_argument("--phone", help="iPhone simulator to use")
    parser.add_argument("--out", default="build/linktest")
    args = parser.parse_args()
    cfg = json.loads(Path(args.config).read_text())
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    app = Path(args.app)
    inside = sorted((app / "Watch").glob("*.app")) if (app / "Watch").is_dir() else []
    watch_app = Path(args.watch_app) if args.watch_app else (inside[0] if inside else None)
    if watch_app is None or not watch_app.exists():
        sys.exit(f"no Watch app found inside {app} and none given with --watch-app")
    print(f"iPhone app: {app}\nWatch app: {watch_app}\nWatch app inside the iPhone app: {'yes' if inside else 'NO'}")

    recording = out / RECORDING
    if run(["say", "-o", recording, WORDS]).returncode != 0 or not recording.exists():
        recording.write_bytes(b"\0" * 4096)  # the link only needs bytes to carry
    print(f"test recording: {recording} ({recording.stat().st_size} bytes)")

    # The same iPhone app with its Watch folder taken out: how it was on Adam's devices on Nov 21.
    alone = out / "alone" / app.name
    if alone.parent.exists():
        shutil.rmtree(alone.parent)
    shutil.copytree(app, alone, symlinks=True)
    shutil.rmtree(alone / "Watch", ignore_errors=True)

    phone, watch = pick_pair(args.phone)
    boot(phone)
    boot(watch)

    wait_for_pair(phone, watch)
    time.sleep(30)

    results = []
    if inside:
        results.append((INSIDE, *one_run(INSIDE, phone, watch, app, watch_app, cfg, recording, out)))
        if not results[-1][1] and "iPhoneAppInstalled=no" in results[-1][2]:
            # The two apps never saw each other. A pair of simulators that has just started for
            # the first time can need longer; install once more now that it has been up a while.
            results.append((AGAIN, *one_run(AGAIN, phone, watch, app, watch_app, cfg, recording, out)))
        if results[-1][1]:
            # Adam: "Common scenario is that I am out for a run and have an idea hit me." The
            # iPhone app is closed then. The same install, with the iPhone app closed and left
            # closed: the Watch's message has to open it.
            results.append((CLOSED, *one_run(CLOSED, phone, watch, app, watch_app, cfg, recording, out,
                                             install=False, phone_open=False)))
    else:
        print("\nthis iPhone app does not carry the Watch app; only the stand-alone run is possible")
    # How it was on Adam's devices on Nov 21. This run is expected to fail; it shows the test
    # can tell the difference.
    results.append((ALONE, *one_run(ALONE, phone, watch, alone, watch_app, cfg, recording, out)))

    print("\n===== Result =====")
    for label, words_back, state in results:
        print(f"Watch app {label}: words back on the Watch: {'YES' if words_back else 'NO'}  ({state})")
    passed = any(words_back for label, words_back, state in results if label in DECIDES)
    closed = [words_back for label, words_back, state in results if label == CLOSED]
    if closed and not closed[0]:
        print("With the iPhone app closed the words did not come back. That run is reported and does "
              "not decide the result: a simulator may not open the iPhone app the way a real iPhone does.")
    print("LINK TEST PASSED" if passed else "LINK TEST FAILED")
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
