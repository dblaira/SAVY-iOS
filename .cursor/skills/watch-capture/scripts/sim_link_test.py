#!/usr/bin/env python3
"""Watch capture kit: tests the Watch-to-iPhone link in paired simulators, with no one at a desk.

Adam, Nov 21, 2026: "Do 1000% of your tests on a fucking simulator. That's what you should do. It
should work perfectly on a goddamn fucking simulator. Instead of sitting here holding me to this
fucking desk."

What it does, on a Mac with Xcode (a GitHub runner, or Adam's Mac with no device attached):
  1. Finds or makes a paired iPhone and Apple Watch simulator, and boots both.
  2. Installs the iPhone app and the Watch app, and opens both.
  3. A simulator-only hook in the Watch app sends a spoken recording to the iPhone simulator,
     exactly as a finished recording is sent. A simulator-only hook in the iPhone app answers with
     set words, because a build machine has no one to allow Speech Recognition.
  4. Reads both apps' trails and prints, per capture, what worked and what stopped.

It runs twice: with the Watch app installed on its own (how it was on Adam's devices on Nov 21,
where the link failed with WatchConnectivity 7018), then with the Watch app inside the iPhone app.
It passes only when the words come back to the Watch in the second run.

What a simulator cannot show: his iCloud account, the real microphone and Bluetooth. Those parts
(recording, iCloud, entry on the iPhone) worked on his own devices on Nov 21.

  sim_link_test.py --config watch-capture.json --app build/.../SAVY.app [--watch-app .../SAVYWatch.app]
                   [--phone UDID] [--out build/linktest]

Standard library only.
"""
import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import watchtrail  # noqa: E402

WORDS = "Blue's Clues pauses so the kid can answer"
RECORDING = "linktest.m4a"


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


def container(udid, bundle):
    done = simctl("get_app_container", udid, bundle, "data", quiet=True)
    return Path(done.stdout.strip()) if done.returncode == 0 and done.stdout.strip() else None


def read_trail(path):
    events = []
    if path and path.exists():
        for line in path.read_text(errors="replace").splitlines():
            try:
                events.append(json.loads(line))
            except ValueError:
                pass
    return events


def one_run(label, phone, watch, phone_app, watch_app, cfg, recording, out):
    """Installs, runs the link test once, and returns (words came back, the Watch's last link state)."""
    phone_bundle, watch_bundle = cfg["xcode"]["companionBundleID"], cfg["xcode"]["watchBundleID"]
    folder = cfg["storageFolder"]
    print(f"\n===== Link test: Watch app {label} =====", flush=True)
    for udid, bundle in ((watch, watch_bundle), (phone, phone_bundle)):
        simctl("terminate", udid, bundle, quiet=True)
        simctl("uninstall", udid, bundle, quiet=True)
    simctl("install", phone, phone_app, check=True)
    simctl("install", watch, watch_app, check=True)

    watch_data = container(watch, watch_bundle)
    if watch_data is None:
        sys.exit("the Watch app's data folder was not found after install")
    store = watch_data / "Library/Application Support" / folder
    (store / "Audio").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(recording, store / "Audio" / RECORDING)
    watch_trail = store / watchtrail_name()
    if watch_trail.exists():
        watch_trail.unlink()

    simctl("launch", phone, phone_bundle, "-WatchCaptureLinkTestWords", WORDS, check=True)
    time.sleep(8)
    simctl("launch", watch, watch_bundle, "-WatchCaptureLinkTest", RECORDING, check=True)

    deadline = time.time() + 200
    done = False
    while time.time() < deadline and not done:
        time.sleep(5)
        done = any(e.get("step") == "linktest.done" for e in read_trail(watch_trail))
    if not done:
        print("the Watch app did not finish the link test in time", flush=True)

    phone_data = container(phone, phone_bundle)
    phone_trail = phone_data / "Library/Application Support" / folder / watchtrail_name() if phone_data else None
    saved = out / label.replace(" ", "-")
    saved.mkdir(parents=True, exist_ok=True)
    files = []
    for name, path in (("watch-trail.jsonl", watch_trail), ("iphone-trail.jsonl", phone_trail)):
        if path and path.exists():
            shutil.copyfile(path, saved / name)
            files.append(saved / name)
    for udid, name in ((watch, "watch.png"), (phone, "iphone.png")):
        simctl("io", udid, "screenshot", saved / name, quiet=True)

    events, notes = watchtrail.load(files)
    watchtrail.report(events, notes)
    words_back = any(e.get("step") == "link.words" and e.get("ok") for e in events)
    state = next((e.get("detail") for e in reversed(events)
                  if e.get("side") == "watch" and e.get("step") in ("link.activate", "link.reach")), "no link line")
    return words_back, state


def watchtrail_name():
    return "trail.jsonl"


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

    results = []
    for label, phone_app in (("installed on its own", alone), ("inside the iPhone app", app)):
        if label == "inside the iPhone app" and not inside:
            print("\nskipping the second run: this iPhone app does not carry the Watch app")
            continue
        results.append((label, *one_run(label, phone, watch, phone_app, watch_app, cfg, recording, out)))

    print("\n===== Result =====")
    for label, words_back, state in results:
        print(f"Watch app {label}: words back on the Watch: {'YES' if words_back else 'NO'}  ({state})")
    passed = bool(results) and results[-1][0] == "inside the iPhone app" and results[-1][1]
    print("LINK TEST PASSED" if passed else "LINK TEST FAILED")
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
