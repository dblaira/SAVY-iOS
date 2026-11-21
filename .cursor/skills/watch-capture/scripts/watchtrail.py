#!/usr/bin/env python3
"""Watch capture kit: reads the capture trail, so a capture that stops says where and why.

The Watch app and the iPhone or Mac app each write one line per step to a small file,
`Application Support/<storageFolder>/trail.jsonl` (see WatchCaptureTrail in WatchCapture.swift).
A line holds a time, the step, whether it worked, the capture's id and a short reason. It never
holds the words or the recording.

  watchtrail.py read FILE [FILE ...]
      Prints, for each capture, the four things that must happen (recorded on the Watch, words
      back on the wrist, in iCloud, entry in the app) and the first one that did not.
      Give it the Watch's file and the iPhone's and Mac's files together.

  watchtrail.py pull --config watch-capture.json [--out DIR] [--watch ID] [--iphone ID]
      On Adam's Mac, with the iPhone connected and the Watch paired: copies each trail file off
      the devices with `xcrun devicectl`, then reads them. Written in a cloud session without a
      Mac, so the device commands are untested: each one is printed before it runs.

  watchtrail.py selftest
      Checks the reader against two made-up trails. Needs no device.

Standard library only.
"""
import argparse
import json
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

STEP_WORDS = {
    "app.launch": "App opened",
    "link.activate": "Watch and iPhone link",
    "link.state": "Watch and iPhone link",
    "link.reach": "iPhone in reach",
    "record.start": "Recording started",
    "record.cut": "Recording cut short",
    "record.stop": "Recording stopped",
    "keep": "Kept on the Watch",
    "save": "Saved on the Watch",
    "siri": "Siri capture saved on the Watch",
    "discard": "Thrown away on the Watch",
    "link.ask": "Recording sent to the iPhone",
    "link.part": "Part of the recording did not reach the iPhone",
    "link.wake": "iPhone woken by the Watch",
    "link.receive": "Recording received on the iPhone",
    "words": "Words written out",
    "link.reply": "Words sent back to the Watch",
    "link.words": "Words back on the wrist",
    "cloud.send": "Sent to iCloud",
    "import.skip": "Import waiting",
    "import.fetch": "Looked in the Watch inbox",
    "import.read": "Capture read from iCloud",
    "import.audio": "Recording kept on this device",
    "import.seen": "Already an entry",
    "import.claim": "Claimed in iCloud",
    "import.entry": "Entry saved",
}

# What to do about a failure, matched against "<step> <detail>". First match wins.
HINTS = [
    ("iPhoneAppInstalled=no", "The Watch does not see the iPhone app as its partner. Install the iPhone app from "
                              "the branch that has the Watch code."),
    ("companionAppNotInstalled", "The Watch does not see the iPhone app as its partner. Install the iPhone app "
                                 "from the branch that has the Watch code."),
    ("watchAppNotInstalled", "The iPhone does not see the Watch app. Reinstall the Watch app."),
    ("iPhoneReachable=no", "The iPhone was out of reach or its Bluetooth was off. The words are written out "
                           "later, from iCloud."),
    ("notReachable", "The iPhone could not be reached at that moment. The words are written out later, from iCloud."),
    ("no answer from the iPhone", "The iPhone did not answer. Its trail shows whether the recording arrived and "
                                  "whether the words could be written out."),
    ("payloadTooLarge", "A part of the recording was too large for a live message. Lower partSize in WatchPhoneLink."),
    ("never asked", "Open the app on the iPhone once and allow Speech Recognition."),
    ("turned off in Settings", "Turn on Speech Recognition for the app in the iPhone's Settings, Privacy & Security."),
    ("status 1)", "Sign in to iCloud on that device (or iCloud is restricted on it)."),
    ("notAuthenticated", "Sign in to iCloud on that device."),
    ("missingEntitlement", "That build may not use iCloud. In Xcode, Signing & Capabilities for the target, tick "
                           "iCloud, CloudKit and the app's container, then install again."),
    ("permissionFailure", "iCloud refused the write. Check the container and that the build is signed for the "
                          "Development environment."),
    ("badContainer", "The iCloud container is not on that build. In Xcode, Signing & Capabilities, tick the "
                     "app's container, then install again."),
    ("quotaExceeded", "iCloud storage is full."),
    ("networkUnavailable", "No network at that moment. It retries by itself."),
    ("networkFailure", "The network dropped. It retries by itself."),
    ("import.skip", "The app's own iCloud sync was not ready, so Watch captures waited. The status in the line "
                    "says why."),
    ("stopped before the second press", "The recording ended before Adam pressed stop. The Watch likely "
                                        "suspended the app when the wrist dropped."),
    ("record.cut", "The system stopped the recording. A call, Siri or the wrist dropping can do this."),
    ("microphone is off", "Turn on the Microphone for the app in the Watch's Settings, Privacy & Security."),
]


def load(paths):
    """Every readable line from every file, oldest first. Returns (events, notes)."""
    events, notes = [], []
    for path in paths:
        path = Path(path)
        if not path.exists():
            notes.append(f"not found: {path}")
            continue
        count = 0
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
                event["when"] = datetime.fromisoformat(event["at"].replace("Z", "+00:00"))
            except (ValueError, KeyError):
                continue
            events.append(event)
            count += 1
        notes.append(f"{count} steps from {path}")
    events.sort(key=lambda e: e["when"])
    return events, notes


def local(when):
    return when.astimezone().strftime("%a %b %-d %-I:%M:%S %p")


def hint_for(event):
    text = f"{event.get('step', '')} {event.get('detail') or ''}"
    for needle, hint in HINTS:
        if needle in text:
            return hint
    return None


def checkpoint(events, steps, sides=None):
    """The last event for any of `steps` (on `sides`, if given), or None."""
    found = [e for e in events if e.get("step") in steps and (sides is None or e.get("side") in sides)]
    return found[-1] if found else None


def describe(events, sides_seen):
    """The four things that must happen to one capture: (label, state, detail, event)."""
    rows = []

    kept = checkpoint(events, {"keep", "siri"})
    stopped = checkpoint(events, {"record.stop", "record.cut"})
    if kept is None:
        rows.append(("Recorded on the Watch", "missing", "no step from the Watch for this capture", None))
    elif not kept["ok"]:
        rows.append(("Recorded on the Watch", "FAILED", kept.get("detail") or "", kept))
    elif stopped is not None and not stopped["ok"]:
        rows.append(("Recorded on the Watch", "FAILED", stopped.get("detail") or "", stopped))
    else:
        rows.append(("Recorded on the Watch", "ok", kept.get("detail") or "", kept))

    was_siri = kept is not None and kept.get("step") == "siri"
    back = checkpoint(events, {"link.words"})
    asked = checkpoint(events, {"link.ask"})
    part = checkpoint(events, {"link.part"})
    phone_words = checkpoint(events, {"words"}, {"iphone"})
    if was_siri:
        rows.append(("Words back on the wrist", "n/a", "Siri wrote the words", None))
    elif back is not None and back["ok"]:
        rows.append(("Words back on the wrist", "ok", back.get("detail") or "", back))
    else:
        cause = None
        for candidate in (asked, part, phone_words, back):
            if candidate is not None and not candidate["ok"]:
                cause = candidate
                break
        if cause is None and asked is None:
            rows.append(("Words back on the wrist", "missing", "the Watch never tried to send it to the iPhone", None))
        elif cause is None:
            rows.append(("Words back on the wrist", "waiting", "sent to the iPhone; no answer recorded yet", asked))
        else:
            rows.append(("Words back on the wrist", "FAILED", cause.get("detail") or "", cause))

    sent = checkpoint(events, {"cloud.send"})
    if sent is None:
        rows.append(("In iCloud", "waiting", "the Watch has not tried to send it (not saved yet, or still a draft)", None))
    else:
        rows.append(("In iCloud", "ok" if sent["ok"] else "FAILED", sent.get("detail") or "", sent))

    entry = checkpoint(events, {"import.entry"})
    seen = checkpoint(events, {"import.seen"})
    blocker = None
    for candidate_steps in ({"import.claim"}, {"import.audio"}, {"import.read"}):
        candidate = checkpoint(events, candidate_steps)
        if candidate is not None and not candidate["ok"]:
            blocker = candidate
            break
    if entry is not None and entry["ok"]:
        rows.append(("Entry in the app", "ok", f"on the {entry['side']}: {entry.get('detail') or ''}", entry))
    elif entry is not None:
        rows.append(("Entry in the app", "FAILED", entry.get("detail") or "", entry))
    elif seen is not None:
        rows.append(("Entry in the app", "ok", f"{seen.get('detail') or ''} (seen on the {seen['side']})", seen))
    elif blocker is not None:
        rows.append(("Entry in the app", "FAILED", blocker.get("detail") or "", blocker))
    elif not ({"iphone", "mac"} & sides_seen):
        rows.append(("Entry in the app", "missing", "no trail from an iPhone or Mac was read", None))
    elif sent is None or not sent["ok"]:
        rows.append(("Entry in the app", "waiting", "it has not reached iCloud yet", None))
    else:
        rows.append(("Entry in the app", "missing", "it is in iCloud, and no iPhone or Mac has picked it up", None))
    return rows


def attach_recordings(events):
    """Recording steps carry the file's tag, not the capture's id; `keep` carries both."""
    by_tag = {}
    for event in events:
        if event.get("step") == "keep" and event.get("capture"):
            for word in (event.get("detail") or "").split():
                if word.startswith("file="):
                    by_tag[word] = event["capture"]
    for event in events:
        if event.get("capture") is None and event.get("step", "").startswith("record."):
            for word in (event.get("detail") or "").split():
                if word in by_tag:
                    event["capture"] = by_tag[word]


def report(events, notes, out=sys.stdout):
    """Prints the report. Returns the number of captures whose journey has a failed or missing step."""
    write = lambda text="": print(text, file=out)
    for note in notes:
        write(note)
    if not events:
        write()
        write("No steps were read. Either no trail file was found, or the apps on the devices were built")
        write("before the trail existed. Install the Watch and iPhone apps from the current Watch branch first.")
        return 0
    attach_recordings(events)
    sides_seen = {e.get("side") for e in events}

    write()
    write("Devices")
    names = {"watch": "Watch", "iphone": "iPhone", "mac": "Mac"}
    for side in ("watch", "iphone", "mac"):
        launches = [e for e in events if e.get("side") == side and e.get("step") == "app.launch"]
        link = checkpoint(events, {"link.activate", "link.state", "link.reach"}, {side})
        if side not in sides_seen:
            if side == "mac":
                continue
            write(f"  {names[side]:<7} no trail. Its app has no trail code, or has not been opened since it was installed.")
            continue
        opened = f"last opened {local(launches[-1]['when'])}, {launches[-1].get('detail') or ''}" if launches else "no launch recorded"
        write(f"  {names[side]:<7} {opened}")
        if link is not None:
            write(f"          {link.get('detail') or ''}")
    general = [e for e in events if not e.get("capture") and not e["ok"]]
    if general:
        write()
        write("Trouble not tied to one capture (newest last)")
        for event in general[-8:]:
            write(f"  {local(event['when'])}  {event.get('side', '?'):<6} {STEP_WORDS.get(event['step'], event['step'])}: {event.get('detail') or ''}")

    order = []
    by_capture = {}
    for event in events:
        capture = event.get("capture")
        if not capture:
            continue
        if capture not in by_capture:
            by_capture[capture] = []
            order.append(capture)
        by_capture[capture].append(event)

    troubled = 0
    first_fix = None
    for capture in order:
        steps = by_capture[capture]
        if any(e.get("step") == "discard" for e in steps):
            continue
        saved = checkpoint(steps, {"save", "siri"})
        kind = ""
        if saved is not None and (saved.get("detail") or "").startswith("as "):
            kind = ", saved as " + (saved["detail"].split()[1].rstrip(":"))
        write()
        write(f"Capture {capture[:8]}  {local(steps[0]['when'])}{kind}")
        rows = describe(steps, sides_seen)
        first_bad = None
        for label, state, detail, event in rows:
            write(f"  {state:<8} {label:<24} {detail}")
            if state in ("FAILED", "missing"):
                hint = hint_for(event) if event else None
                if hint:
                    write(f"           {'':<24} -> {hint}")
                if first_bad is None:
                    first_bad = (capture, label, detail, hint)
        if first_bad is not None:
            troubled += 1
            first_fix = first_bad
        write("  steps:")
        for event in steps:
            mark = "ok    " if event["ok"] else "FAILED"
            write(f"    {event['when'].astimezone().strftime('%H:%M:%S')} {event.get('side', '?'):<6} {mark} "
                  f"{STEP_WORDS.get(event['step'], event['step'])}: {event.get('detail') or ''}")

    write()
    shown = len([c for c in order if not any(e.get('step') == 'discard' for e in by_capture[c])])
    if shown == 0:
        write("No captures in the trail yet. Make one on the Watch, open the app on the iPhone, then read again.")
    elif troubled == 0:
        write(f"All {shown} captures made it from the wrist to an entry.")
    else:
        write(f"{troubled} of {shown} captures stopped somewhere. The newest one, capture {first_fix[0][:8]}, first "
              f"stopped at \"{first_fix[1]}\": {first_fix[2]}")
        if first_fix[3]:
            write(f"What to do: {first_fix[3]}")
    return troubled


# ---------------------------------------------------------------- devices (Adam's Mac only)

def run(command):
    print("$", " ".join(command))
    done = subprocess.run(command, capture_output=True, text=True)
    if done.returncode != 0:
        print((done.stderr or done.stdout).strip())
    return done.returncode == 0


def find_devices():
    """(watch id, iphone id) from `devicectl list devices`, or None for one that is not found."""
    with tempfile.TemporaryDirectory() as folder:
        listing = Path(folder) / "devices.json"
        if not run(["xcrun", "devicectl", "list", "devices", "--json-output", str(listing)]) or not listing.exists():
            return None, None
        devices = json.loads(listing.read_text()).get("result", {}).get("devices", [])
    watch = iphone = None
    for device in devices:
        hardware = device.get("hardwareProperties", {})
        kind = f"{hardware.get('platform', '')} {hardware.get('deviceType', '')} {hardware.get('productType', '')}".lower()
        identifier = device.get("identifier") or hardware.get("udid")
        name = device.get("deviceProperties", {}).get("name", "")
        print(f"found: {name} ({kind.strip()}) {identifier}")
        if "watch" in kind:
            watch = watch or identifier
        elif "iphone" in kind:
            iphone = iphone or identifier
    return watch, iphone


def cmd_pull(args):
    cfg = json.loads(Path(args.config).read_text())
    folder = cfg["storageFolder"]
    out = Path(args.out or tempfile.mkdtemp(prefix="watchtrail-"))
    out.mkdir(parents=True, exist_ok=True)
    watch, iphone = args.watch, args.iphone
    if not (watch and iphone):
        found_watch, found_iphone = find_devices()
        watch, iphone = watch or found_watch, iphone or found_iphone
    source = f"Library/Application Support/{folder}/trail.jsonl"
    files = []
    for label, device, bundle in (("watch", watch, cfg["xcode"]["watchBundleID"]),
                                  ("iphone", iphone, cfg["xcode"]["companionBundleID"])):
        if not device:
            print(f"no {label} found by devicectl; pass --{label} ID (from `xcrun devicectl list devices`)")
            continue
        destination = out / f"{label}-trail.jsonl"
        if run(["xcrun", "devicectl", "device", "copy", "from", "--device", device,
                "--domain-type", "appDataContainer", "--domain-identifier", bundle,
                "--source", source, "--destination", str(destination)]):
            files.append(destination)
    mac = Path.home() / "Library/Containers" / cfg["xcode"]["companionBundleID"] / "Data" / source
    try:
        if mac.exists():
            copy = out / "mac-trail.jsonl"
            copy.write_bytes(mac.read_bytes())
            files.append(copy)
    except OSError as error:
        print(f"the Mac app's trail could not be read ({error}); macOS guards other apps' folders")
    print(f"trail files are in {out}")
    events, notes = load(files)
    return report(events, notes)


# ---------------------------------------------------------------- selftest

def _line(seconds, side, step, ok=True, capture=None, detail=None):
    at = datetime.fromtimestamp(1_795_000_000 + seconds, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    event = {"at": at, "side": side, "step": step, "ok": ok}
    if capture:
        event["capture"] = capture
    if detail:
        event["detail"] = detail
    return json.dumps(event)


def selftest():
    import io
    one, two = "11111111-aaaa-4bbb-8ccc-000000000001", "22222222-aaaa-4bbb-8ccc-000000000002"
    with tempfile.TemporaryDirectory() as folder:
        # 1. The iPhone app has no Watch code: the Watch records and reaches iCloud; nothing else happens.
        watch = Path(folder) / "watch.jsonl"
        watch.write_text("\n".join([
            _line(0, "watch", "app.launch", detail="v1.0 (1)"),
            _line(1, "watch", "link.activate", detail="link=activated iPhoneReachable=yes iPhoneAppInstalled=no"),
            _line(5, "watch", "record.start", detail="file=ab12cd34"),
            _line(12, "watch", "record.stop", detail="file=ab12cd34 recorded=7.0s pressed=7.1s"),
            _line(12, "watch", "keep", capture=one, detail="file=ab12cd34 7.0s 21KB"),
            _line(13, "watch", "link.ask", ok=False, capture=one,
                  detail="not sent to the iPhone: link=activated iPhoneReachable=no iPhoneAppInstalled=no"),
            _line(15, "watch", "save", capture=one, detail="as post"),
            _line(17, "watch", "cloud.send", capture=one, detail="in iCloud, with its recording"),
        ]) + "\n")
        text = io.StringIO()
        events, notes = load([watch, Path(folder) / "iphone.jsonl"])
        troubled = report(events, notes, out=text)
        output = text.getvalue()
        assert troubled == 1, output
        assert "iPhone  no trail" in output, output
        assert "ok       Recorded on the Watch" in output, output
        assert "FAILED   Words back on the wrist" in output, output
        assert "ok       In iCloud" in output, output
        assert "missing  Entry in the app" in output, output
        assert "Install the iPhone app from the branch that has the Watch code" in output, output
        assert "Recording stopped: file=ab12cd34" in output, "recording steps join their capture by file tag"

        # 2. Everything works: words come back in the pocket, and the iPhone makes the entry.
        watch.write_text("\n".join([
            _line(0, "watch", "app.launch", detail="v1.0 (2)"),
            _line(12, "watch", "keep", capture=two, detail="file=ef56ab78 7.0s 21KB"),
            _line(13, "watch", "link.ask", capture=two, detail="sent to the iPhone: parts=1 21KB"),
            _line(18, "watch", "link.words", capture=two, detail="chars=64 after 5.2s"),
            _line(20, "watch", "save", capture=two, detail="as post"),
            _line(22, "watch", "cloud.send", capture=two, detail="in iCloud, with its recording"),
        ]) + "\n")
        phone = Path(folder) / "iphone.jsonl"
        phone.write_text("\n".join([
            _line(-50, "iphone", "app.launch", detail="v1.0 (30) speechRecognition=allowed"),
            _line(14, "iphone", "link.wake", capture=two, detail="first of 1 parts arrived from the Watch"),
            _line(14, "iphone", "link.receive", capture=two, detail="parts=1 21KB app=background unlocked=no"),
            _line(17, "iphone", "words", capture=two, detail="engine=analyzer chars=64 in 3.1s"),
            _line(17, "iphone", "link.reply", capture=two, detail="chars=64 sent live"),
            _line(90, "iphone", "import.fetch", detail="new or changed in the Watch inbox: 1"),
            _line(93, "iphone", "import.entry", capture=two, detail="entry saved as post chars=64 recording=yes"),
        ]) + "\n")
        text = io.StringIO()
        events, notes = load([watch, phone])
        troubled = report(events, notes, out=text)
        output = text.getvalue()
        assert troubled == 0, output
        assert "All 1 captures made it from the wrist to an entry." in output, output
        assert "ok       Entry in the app         on the iphone" in output, output
    print("watchtrail selftest passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    read = commands.add_parser("read")
    read.add_argument("files", nargs="+")
    pull = commands.add_parser("pull")
    pull.add_argument("--config", required=True)
    pull.add_argument("--out")
    pull.add_argument("--watch")
    pull.add_argument("--iphone")
    commands.add_parser("selftest")
    args = parser.parse_args()
    if args.command == "selftest":
        selftest()
    elif args.command == "read":
        events, notes = load(args.files)
        sys.exit(1 if report(events, notes) else 0)
    else:
        sys.exit(1 if cmd_pull(args) else 0)


if __name__ == "__main__":
    main()
