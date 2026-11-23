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

Its runs: with the Watch app inside the iPhone app and both installed, up to three times with a
fresh install each time, because a pair of simulators that has just started for the first time
often fails its first try (the apps do not see each other yet, or the Watch cannot reach the
iPhone yet); then with the iPhone app closed, as it is in a pocket on a run, so the Watch's
message has to open it; and last with the Watch app installed on its own, which is how it was on
Adam's devices on Nov 21, where the link failed with WatchConnectivity 7018. It passes only when
the words come back to the Watch with the Watch app inside the iPhone app, both with the iPhone
app open and with it closed. Every try is printed, passed or failed.

What a simulator cannot show: his iCloud account, the real microphone and Bluetooth. Those parts
(recording, iCloud, entry on the iPhone) worked on his own devices on Nov 21.

For an app on the iPhone route ("route": "iphone" in the config, no iCloud) the iPhone app makes
the entry, so the test asks for more. The Watch app saves the test capture as Save does, and a run
passes only when the words come back to the Watch AND the entry is in the iPhone app's own test
store. The config's "linkTest" block says how the iPhone app is given a test store of its own
("{run}" stands for a new id each run):
  "phoneArguments"    arguments the test opens the iPhone app with
  "phoneEnvironment"  environment values it opens the iPhone app with
  "phoneFiles"        files placed in the iPhone app's data folder first; these also reach an
                      iPhone app the Watch's message opens by itself, which gets no arguments
  "entryStore"        the file in the iPhone app's data folder that holds its test store's entries
On this route the run with the Watch app installed on its own has to fail. If it passes, the test
can no longer tell a working link from a broken one, and the whole test fails.

This route has one more run, which also has to pass: the iPhone out of reach, then close again.
The test turns the iPhone simulator off, and the Watch app saves a capture. The capture has to
wait on the Watch, with no entry made. Then the test turns the iPhone simulator on again and
never opens the iPhone app. The capture has to become the entry in the iPhone app's test store,
and the Watch has to be told. A simulator that is off stands in for an iPhone out of Bluetooth
range; it is not the same thing.
When the test ends, both apps are removed from the simulators, so nothing of the test stays.

  sim_link_test.py --config watch-capture.json --app build/.../SAVY.app [--watch-app .../SAVYWatch.app]
                   [--phone UDID] [--out build/linktest]

Standard library only.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import watchtrail  # noqa: E402

WORDS = "Blue's Clues pauses so the kid can answer"
RECORDING = "linktest.m4a"
WORDS_FILE = "linktest-words.txt"  # read by the iPhone app's simulator-only hook when no one opens it
TRAIL = "trail.jsonl"

INSIDE = "inside the iPhone app"
AGAIN = "inside the iPhone app, second install"
THIRD = "inside the iPhone app, third install"
CLOSED = "inside the iPhone app with the iPhone app closed"
CLOSED_AGAIN = "inside the iPhone app with the iPhone app closed, second try"
AWAY = "inside the iPhone app with the iPhone out of reach, then close again"
AWAY_AGAIN = "inside the iPhone app with the iPhone out of reach, then close again, second try"
ALONE = "installed on its own"
OPEN_TRIES = (INSIDE, AGAIN, THIRD)      # one of these has to pass,
CLOSED_TRIES = (CLOSED, CLOSED_AGAIN)    # and one of these,
AWAY_TRIES = (AWAY, AWAY_AGAIN)          # and on the iPhone route one of these
QUEUE = "captures.json"  # the Watch app's own list of captures, with when the iPhone confirmed each


def run(command, check=False, quiet=False, timeout=300, env=None):
    if not quiet:
        print("$", " ".join(str(c) for c in command), flush=True)
    done = subprocess.run([str(c) for c in command], capture_output=True, text=True, timeout=timeout, env=env)
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


# What a simulator's own link service says when it cannot tell whether the other app is installed.
# On a pair that has just started for the first time, the Watch's says "App database is out of
# sync" (ACXErrorDomain 43) until the two systems have exchanged their lists of apps.
TELLING = ("companion app installed", "out of sync", "acxerrordomain", "counterpart bundle")


def system_notes(phone, watch):
    """When the two apps never saw each other: what each simulator's own link service logged
    about it in the last few minutes, to show why."""
    for name, udid in (("iPhone", phone), ("Watch", watch)):
        try:
            done = simctl("spawn", udid, "log", "show", "--last", "6m", "--style", "compact",
                          "--predicate", 'process == "wcd" OR process == "appconduitd"',
                          quiet=True, timeout=180)
        except subprocess.TimeoutExpired:
            print(f"--- {name} simulator: its log took too long to read ---", flush=True)
            continue
        lines = [line.strip()[:400] for line in done.stdout.splitlines() if line.strip()]
        telling = [line for line in lines if any(mark in line.lower() for mark in TELLING)]
        if telling:
            print(f"--- why, from the {name} simulator's own link service ---")
        else:
            print(f"--- {name} simulator's own link service says nothing about the other app; its last lines ---")
        for line in (telling or lines)[-6:]:
            print("  " + line)
        sys.stdout.flush()


def by_iphone(cfg):
    """True for an app on the iPhone route: no iCloud, and the iPhone app makes the entry."""
    return cfg.get("route", "icloud") == "iphone"


def strings_in(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item)


def entry_in_store(path, capture, words):
    """True when the iPhone app's test store holds an entry with the capture's id and the words."""
    if not capture or path is None or not path.exists():
        return False
    try:
        found = list(strings_in(json.loads(path.read_text(errors="replace"))))
    except ValueError:
        return False
    return any(text.lower() == capture.lower() for text in found) and any(words in text for text in found)


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
    # On the iPhone route, each run gives the iPhone app a new test store of its own.
    test = cfg.get("linkTest", {}) if by_iphone(cfg) else {}
    run_id = str(uuid.uuid4()).upper()
    fill = lambda text: text.replace("{run}", run_id)
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
    phone_data = container(phone, phone_bundle)
    staged = []
    for name, content in test.get("phoneFiles", {}).items():
        if phone_data is None:
            return False, "the iPhone app's data folder was not found"
        staged.append(phone_data / fill(name))
        staged[-1].parent.mkdir(parents=True, exist_ok=True)
        staged[-1].write_text(fill(content))
    if phone_open:
        environment = None
        if test.get("phoneEnvironment"):
            environment = dict(os.environ)
            environment.update({"SIMCTL_CHILD_" + key: fill(value) for key, value in test["phoneEnvironment"].items()})
        simctl("launch", phone, phone_bundle, *test.get("phoneArguments", []),
               "-WatchCaptureLinkTestWords", WORDS, check=True, env=environment)
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

    # The Watch app waits up to 120 seconds for the pair and up to 170 for the words. On the
    # iPhone route it then waits up to 120 more for the iPhone to say the entry is saved.
    deadline = time.time() + (490 if by_iphone(cfg) else 360)
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
    for path in staged:
        if path.exists():
            path.unlink()

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
                  if e.get("side") == "watch"
                  and e.get("step") in ("link.activate", "link.reach", "link.state", "linktest.ready")),
                 "no link line")
    if not words_back and label != ALONE:
        system_notes(phone, watch)
    if by_iphone(cfg):
        # The words alone are not enough here: the entry has to be in the iPhone app's test store.
        capture = next((e.get("capture") for e in events if e.get("step") == "linktest.done"), None)
        store_file = phone_data / fill(test["entryStore"]) if phone_data and test.get("entryStore") else None
        entry = entry_in_store(store_file, capture, WORDS)
        told = any(e.get("step") == "linktest.entry" and e.get("ok") for e in events)
        print(f"words back on the Watch: {'yes' if words_back else 'no'}; "
              f"entry in the iPhone app's test store: {'yes' if entry else 'no'}; "
              f"the Watch was told the entry is saved: {'yes' if told else 'no'}", flush=True)
        if store_file is not None and store_file.exists():
            shutil.copyfile(store_file, saved / "iphone-test-store.json")
        state += f"; entry in the iPhone app's test store: {'YES' if entry else 'NO'}"
        return words_back and entry and told, state
    return words_back, state


def queued_on_watch(path, capture):
    """The capture's line in the Watch app's own queue, or None when it is not there."""
    try:
        items = json.loads(path.read_text(errors="replace"))
    except (OSError, ValueError):
        return None
    for item in items if isinstance(items, list) else []:
        if str(item.get("capture", {}).get("id", "")).lower() == str(capture).lower():
            return item
    return None


def show_new(path, side, seen):
    """Prints the trail lines written since the last look, and returns how many there are now."""
    events = read_trail(path)
    for event in events[seen:]:
        print(f"  {side:<6} {'ok    ' if event.get('ok') else 'FAILED'} {event.get('step', ''):<16} "
              f"{(event.get('capture') or '-')[:8]:<8} {event.get('detail') or ''}", flush=True)
    return len(events)


def away_run(label, phone, watch, cfg, recording, out):
    """The iPhone route only: the iPhone is out of reach when a capture is saved, then close again.

    The apps stay as the run before left them. The test turns the iPhone simulator off, and the
    Watch app saves a capture. It passes only when the capture waits on the Watch while the iPhone
    is away, with no entry made, and then, after the iPhone simulator is on again, becomes the
    entry in the iPhone app's test store with the Watch told. The test never opens the iPhone app.
    Returns (passed, what happened)."""
    phone_bundle, watch_bundle = cfg["xcode"]["companionBundleID"], cfg["xcode"]["watchBundleID"]
    folder = cfg["storageFolder"]
    test = cfg.get("linkTest", {})
    run_id = str(uuid.uuid4()).upper()
    fill = lambda text: text.replace("{run}", run_id)
    print(f"\n===== Link test: Watch app {label} =====", flush=True)
    for udid, bundle in ((watch, watch_bundle), (phone, phone_bundle)):
        simctl("terminate", udid, bundle, quiet=True)
    time.sleep(5)

    # Everything the iPhone app needs is put in place while its simulator is still on.
    store = store_folder(watch, watch_bundle, folder)
    phone_data = container(phone, phone_bundle)
    if store is None or phone_data is None or not test.get("entryStore"):
        return False, "the apps' data folders were not found"
    (store / "Audio").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(recording, store / "Audio" / RECORDING)
    watch_trail, queue = store / TRAIL, store / QUEUE
    if watch_trail.exists():
        watch_trail.unlink()
    staged = []
    for name, content in test.get("phoneFiles", {}).items():
        staged.append(phone_data / fill(name))
        staged[-1].parent.mkdir(parents=True, exist_ok=True)
        staged[-1].write_text(fill(content))
    phone_store = phone_data / "Library/Application Support" / folder
    phone_store.mkdir(parents=True, exist_ok=True)
    (phone_store / WORDS_FILE).write_text(WORDS)
    phone_trail = phone_store / TRAIL
    if phone_trail.exists():
        phone_trail.unlink()
    entries = phone_data / fill(test["entryStore"])

    print("turning the iPhone simulator off: the iPhone is out of reach", flush=True)
    simctl("shutdown", phone, check=True)
    time.sleep(5)
    print(f"the simulator pair: {pair_state(phone, watch)}", flush=True)
    simctl("launch", watch, watch_bundle, "-WatchCaptureLinkTest", RECORDING, check=True)
    # The Watch app waits up to 120 seconds for the pair, up to 170 for the words, and 15 more.
    seen, deadline = 0, time.time() + 340
    while time.time() < deadline:
        time.sleep(5)
        seen = show_new(watch_trail, "watch", seen)
        if any(e.get("step") == "linktest.done" for e in read_trail(watch_trail)):
            break
    capture = next((e.get("capture") for e in read_trail(watch_trail) if e.get("step") == "linktest.done"), None)
    item = queued_on_watch(queue, capture)
    waited = item is not None and not item.get("sentAt") and not entry_in_store(entries, capture, WORDS)
    print(f"with the iPhone away: the capture waits on the Watch: {'yes' if waited else 'no'}; "
          f"entry in the iPhone app's test store: {'yes' if entry_in_store(entries, capture, WORDS) else 'no'}", flush=True)

    print("turning the iPhone simulator on again: the iPhone is close; the test does not open the iPhone app", flush=True)
    boot(phone)
    wait_for_pair(phone, watch, limit=300)
    start, phone_seen, arrived, reopened = time.time(), 0, False, False
    while waited and time.time() - start < 300:
        time.sleep(5)
        seen = show_new(watch_trail, "watch", seen)
        phone_seen = show_new(phone_trail, "iphone", phone_seen)
        item = queued_on_watch(queue, capture)
        if entry_in_store(entries, capture, WORDS) and item is not None and item.get("sentAt"):
            arrived = True
            break
        if not reopened and time.time() - start > 120:
            # The Watch tries again whenever its app is opened, as it is at the next look at the wrist.
            print("not there yet; opening the Watch app again, as a look at the wrist does", flush=True)
            simctl("terminate", watch, watch_bundle, quiet=True)
            simctl("launch", watch, watch_bundle, check=True)
            reopened = True
    after = int(time.time() - start)

    saved = out / label.replace(",", "").replace(" ", "-")
    saved.mkdir(parents=True, exist_ok=True)
    for name, path in (("watch-trail.jsonl", watch_trail), ("iphone-trail.jsonl", phone_trail),
                       ("iphone-test-store.json", entries), ("watch-queue.json", queue)):
        if path.exists():
            shutil.copyfile(path, saved / name)
    for udid, name in ((watch, "watch.png"), (phone, "iphone.png")):
        simctl("io", udid, "screenshot", saved / name, quiet=True)
    opened = any(e.get("step") == "app.launch" for e in read_trail(phone_trail))
    for path in staged + [phone_store / WORDS_FILE]:
        if path.exists():
            path.unlink()
    print(f"after the iPhone came back: entry in the iPhone app's test store and the Watch told: "
          f"{'yes' if arrived else 'no'} (after {after}s; the Watch app opened again by the test: "
          f"{'yes' if reopened else 'no'}; the iPhone app opened by itself: {'yes' if opened else 'no'})", flush=True)
    if not arrived:
        system_notes(phone, watch)
    state = (f"waited on the Watch while the iPhone was away: {'YES' if waited else 'NO'}; "
             f"entry in the iPhone app's test store after it came back: {'YES' if arrived else 'NO'}")
    return waited and arrived, state


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
        # A pair of simulators that has just started for the first time often fails its first
        # try: the two apps do not see each other yet ("App database is out of sync"), or the
        # Watch cannot reach the iPhone yet. Install again and try again, three tries at most.
        for label in OPEN_TRIES:
            results.append((label, *one_run(label, phone, watch, app, watch_app, cfg, recording, out)))
            if results[-1][1]:
                break
        if results[-1][1]:
            # Adam: "Common scenario is that I am out for a run and have an idea hit me." The
            # iPhone app is closed then. The same install, with the iPhone app closed and left
            # closed: the Watch's message has to open it.
            for label in CLOSED_TRIES:
                results.append((label, *one_run(label, phone, watch, app, watch_app, cfg, recording, out,
                                                install=False, phone_open=False)))
                if results[-1][1]:
                    break
            if by_iphone(cfg) and results[-1][1]:
                # A capture made with the iPhone out of reach waits on the Watch until the iPhone
                # is close. The same install; the iPhone simulator is turned off, then on again.
                for label in AWAY_TRIES:
                    results.append((label, *away_run(label, phone, watch, cfg, recording, out)))
                    if results[-1][1]:
                        break
    else:
        print("\nthis iPhone app does not carry the Watch app; only the stand-alone run is possible")
    # How it was on Adam's devices on Nov 21. This run is expected to fail; it shows the test
    # can tell the difference.
    results.append((ALONE, *one_run(ALONE, phone, watch, alone, watch_app, cfg, recording, out)))

    if by_iphone(cfg):
        # Nothing of the test stays behind: no test capture on the Watch, no test store on the iPhone.
        for udid, bundle in ((watch, cfg["xcode"]["watchBundleID"]), (phone, cfg["xcode"]["companionBundleID"])):
            simctl("terminate", udid, bundle, quiet=True)
            simctl("uninstall", udid, bundle, quiet=True)

    print("\n===== Result =====")
    what = "words back on the Watch and the entry on the iPhone" if by_iphone(cfg) else "words back on the Watch"
    for label, words_back, state in results:
        if label in AWAY_TRIES:
            print(f"Watch app {label}: {'YES' if words_back else 'NO'}  ({state})")
        else:
            print(f"Watch app {label}: {what}: {'YES' if words_back else 'NO'}  ({state})")
    opened = any(words_back for label, words_back, state in results if label in OPEN_TRIES)
    closed = any(words_back for label, words_back, state in results if label in CLOSED_TRIES)
    if opened and not closed:
        print("With the iPhone app closed the words did not come back: the Watch's message has to open "
              "the iPhone app, as it does with the iPhone in a pocket.")
    passed = opened and closed
    if by_iphone(cfg) and opened and closed and not any(ok for label, ok, state in results if label in AWAY_TRIES):
        print("With the iPhone out of reach and then close again, the capture did not become an entry.")
        passed = False
    if by_iphone(cfg) and any(words_back for label, words_back, state in results if label == ALONE):
        print("The Watch app installed on its own was counted as working. That run has to fail, "
              "so this test cannot tell a working link from a broken one.")
        passed = False
    print("LINK TEST PASSED" if passed else "LINK TEST FAILED")
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
