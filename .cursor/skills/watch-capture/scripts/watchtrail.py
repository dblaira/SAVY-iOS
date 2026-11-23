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
      Checks the reader against made-up trails. Needs no device.

An app on the iPhone route ("route": "iphone" in its config, no iCloud) writes a "route" step when
it opens. For its trails the third thing is "Handed to the iPhone" in place of "In iCloud": the
Watch hands each capture to the iPhone, which makes the entry.

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
    "link.answer": "Watch's request for the words was not answered",
    "link.words": "Words back on the wrist",
    "linktest.start": "Simulator link test started",
    "linktest.ready": "Simulators see each other as a pair",
    "linktest.done": "Simulator link test finished",
    "cloud.send": "Sent to iCloud",
    "import.skip": "Import waiting",
    "import.fetch": "Looked in the Watch inbox",
    "import.read": "Capture read from iCloud",
    "import.audio": "Recording kept on this device",
    "import.seen": "Already an entry",
    "import.claim": "Claimed in iCloud",
    "import.entry": "Entry saved",
    "route": "How captures travel",
    "phone.wait": "Waiting for the iPhone",
    "phone.queue": "Left with the system for the iPhone",
    "phone.recording": "Recording sent because the iPhone asked",
    "phone.send": "Handed to the iPhone",
    "phone.arrive": "Capture delivered by the system",
    "phone.ask": "iPhone asked for the recording",
    "phone.read": "Capture read on the iPhone",
    "phone.seen": "Already an entry",
    "phone.entry": "Entry saved",
    "linktest.entry": "Simulator link test: the iPhone's answer",
}

# Seen on Adam's devices on Nov 21, 2026: both apps had the Watch code and a running link, and each
# said the other was not installed (WatchConnectivity 7018). The Watch app had been installed on its own.
PAIR_HINT = ("The Watch app and the iPhone app do not see each other as a pair. The iPhone app has to "
             "carry the Watch app (watchkit.py embed), and the Watch app has to arrive through the iPhone app.")

# What to do about a failure, matched against "<step> <detail>". First match wins.
HINTS = [
    ("iPhoneAppInstalled=no", PAIR_HINT),
    ("companionAppNotInstalled", PAIR_HINT),
    ("watchAppNotInstalled", PAIR_HINT),
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


# The iPhone route has no iCloud to fall back on: a capture waits on the Watch for the iPhone.
PHONE_HINTS = [
    ("iPhoneAppInstalled=no", PAIR_HINT),
    ("companionAppNotInstalled", PAIR_HINT),
    ("watchAppNotInstalled", PAIR_HINT),
    ("iPhoneReachable=no", "The iPhone was out of reach or its Bluetooth was off. The capture waits on the Watch "
                           "and goes when the iPhone is close."),
    ("notReachable", "The iPhone could not be reached at that moment. The capture waits on the Watch and goes "
                     "when the iPhone is close."),
    ("no answer from the iPhone", "The iPhone did not answer. Its trail shows whether the recording arrived and "
                                  "whether the words could be written out. The capture still goes to the iPhone."),
    ("entries could not be read", "The iPhone app could not open its own entries, so it saved nothing. Open the "
                                  "app on the iPhone and look at what it says."),
    ("did not answer as expected", "The iPhone app is one from before captures travelled this way. Install the "
                                   "iPhone app that carries this Watch app."),
]


def on_iphone_route(events):
    """True for trails from an app on the iPhone route (no iCloud)."""
    return any(e.get("step") == "route" and (e.get("detail") or "").startswith("iphone")
               or e.get("step", "").startswith("phone.") for e in events)


def hint_for(event, phone_route=False):
    text = f"{event.get('step', '')} {event.get('detail') or ''}"
    for needle, hint in (PHONE_HINTS if phone_route else []) + HINTS:
        if needle in text:
            return hint
    return None


def checkpoint(events, steps, sides=None):
    """The last event for any of `steps` (on `sides`, if given), or None."""
    found = [e for e in events if e.get("step") in steps and (sides is None or e.get("side") in sides)]
    return found[-1] if found else None


def describe_handover(events, sides_seen, watch_read, unread):
    """The iPhone route's last two things: handed to the iPhone, and its entry there."""
    rows = []
    sent = checkpoint(events, {"phone.send"})
    line = checkpoint(events, {"phone.wait", "phone.queue"})
    there = checkpoint(events, {"phone.entry", "phone.seen", "phone.arrive", "phone.ask"}, {"iphone"})
    if sent is not None and sent["ok"]:
        rows.append(("Handed to the iPhone", "ok", sent.get("detail") or "", sent))
    elif there is not None:
        rows.append(("Handed to the iPhone", "ok", "it reached the iPhone", there))
    elif sent is not None and line is not None and line["when"] >= sent["when"]:
        rows.append(("Handed to the iPhone", "waiting", line.get("detail") or "", line))
    elif sent is not None:
        rows.append(("Handed to the iPhone", "FAILED", sent.get("detail") or "", sent))
    elif line is not None:
        rows.append(("Handed to the iPhone", "waiting" if line["ok"] else "FAILED", line.get("detail") or "", line))
    elif not watch_read:
        rows.append(("Handed to the iPhone", "unread", unread, None))
    else:
        rows.append(("Handed to the iPhone", "waiting",
                     "the Watch has not tried to hand it over (not saved yet, or still a draft)", None))

    entry = checkpoint(events, {"phone.entry"})
    seen = checkpoint(events, {"phone.seen"})
    unreadable = checkpoint(events, {"phone.read"})
    if entry is not None and entry["ok"]:
        rows.append(("Entry in the app", "ok", f"on the {entry['side']}: {entry.get('detail') or ''}", entry))
    elif seen is not None:
        rows.append(("Entry in the app", "ok", f"{seen.get('detail') or ''} (seen on the {seen['side']})", seen))
    elif entry is not None:
        rows.append(("Entry in the app", "FAILED", entry.get("detail") or "", entry))
    elif unreadable is not None and not unreadable["ok"]:
        rows.append(("Entry in the app", "FAILED", unreadable.get("detail") or "", unreadable))
    elif "iphone" not in sides_seen:
        rows.append(("Entry in the app", "unread", "no trail from the iPhone was read", None))
    else:
        rows.append(("Entry in the app", "waiting", "it has not reached the iPhone yet", None))
    return rows


def describe(events, sides_seen, phone_route=False):
    """The four things that must happen to one capture: (label, state, detail, event)."""
    rows = []

    # A device whose trail could not be copied is "unread", which is not the same as a step that stopped.
    watch_read = "watch" in sides_seen
    unread = "the Watch's trail was not read"
    kept = checkpoint(events, {"keep", "siri"})
    stopped = checkpoint(events, {"record.stop", "record.cut"})
    if kept is None and not watch_read:
        rows.append(("Recorded on the Watch", "unread", unread, None))
    elif kept is None:
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
        if cause is None and asked is None and not watch_read:
            rows.append(("Words back on the wrist", "unread", unread, None))
        elif cause is None and asked is None:
            rows.append(("Words back on the wrist", "missing", "the Watch never tried to send it to the iPhone", None))
        elif cause is None:
            rows.append(("Words back on the wrist", "waiting", "sent to the iPhone; no answer recorded yet", asked))
        else:
            rows.append(("Words back on the wrist", "FAILED", cause.get("detail") or "", cause))

    if phone_route:
        return rows + describe_handover(events, sides_seen, watch_read, unread)

    sent = checkpoint(events, {"cloud.send"})
    fetched = checkpoint(events, {"import.entry", "import.seen", "import.claim", "import.audio"})
    if sent is None and fetched is not None:
        rows.append(("In iCloud", "ok", f"it reached iCloud: the {fetched['side']} fetched it", fetched))
    elif sent is None and not watch_read:
        rows.append(("In iCloud", "unread", unread, None))
    elif sent is None:
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
        rows.append(("Entry in the app", "unread", "no trail from an iPhone or Mac was read", None))
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
    """Prints the report. Returns (stopped, on_their_way): captures with a failed or missing step,
    and captures with nothing failed that have not become an entry yet."""
    write = lambda text="": print(text, file=out)
    for note in notes:
        write(note)
    if not events:
        write()
        write("No steps were read. Either no trail file was found, or the apps on the devices were built")
        write("before the trail existed. Install the Watch and iPhone apps from the current Watch branch first.")
        return 0, 0
    attach_recordings(events)
    sides_seen = {e.get("side") for e in events}
    phone_route = on_iphone_route(events)

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
    unfinished = 0
    first_fix = None
    for capture in order:
        steps = by_capture[capture]
        # A recording he threw away is not shown. The simulator link test throws its own away
        # when it is done, and that one is the whole point, so it stays.
        if any(e.get("step") == "discard" for e in steps) and not any(
                e.get("step", "").startswith("linktest") for e in steps):
            continue
        saved = checkpoint(steps, {"save", "siri"})
        kind = ""
        if saved is not None and (saved.get("detail") or "").startswith("as "):
            kind = ", saved as " + (saved["detail"].split()[1].rstrip(":"))
        write()
        write(f"Capture {capture[:8]}  {local(steps[0]['when'])}{kind}")
        rows = describe(steps, sides_seen, phone_route)
        first_bad = None
        for label, state, detail, event in rows:
            write(f"  {state:<8} {label:<24} {detail}")
            if state in ("FAILED", "missing"):
                hint = hint_for(event, phone_route) if event else None
                if hint:
                    write(f"           {'':<24} -> {hint}")
                if first_bad is None:
                    first_bad = (capture, label, detail, hint)
        if first_bad is not None:
            troubled += 1
            first_fix = first_bad
        elif rows[-1][1] != "ok":
            # Nothing failed, but there is no entry yet: it is on its way, not delivered.
            unfinished += 1
        write("  steps:")
        for event in steps:
            mark = "ok    " if event["ok"] else "FAILED"
            write(f"    {event['when'].astimezone().strftime('%H:%M:%S')} {event.get('side', '?'):<6} {mark} "
                  f"{STEP_WORDS.get(event['step'], event['step'])}: {event.get('detail') or ''}")

    write()
    shown = len([c for c in order if not any(e.get('step') == 'discard' for e in by_capture[c])
                 or any(e.get('step', '').startswith('linktest') for e in by_capture[c])])
    if shown == 0:
        write("No captures in the trail yet. Make one on the Watch, open the app on the iPhone, then read again.")
    elif troubled == 0 and unfinished == 0:
        write(f"All {shown} captures made it from the wrist to an entry.")
    elif troubled == 0 and phone_route:
        write(f"{shown - unfinished} of {shown} captures made it to an entry. {unfinished} still on the way: "
              f"nothing failed, and no entry yet. Bring the iPhone close and open the app on the Watch, then read again.")
    elif troubled == 0:
        write(f"{shown - unfinished} of {shown} captures made it to an entry. {unfinished} still on the way: "
              f"nothing failed, and no entry yet. Open the app on the iPhone, then read again.")
    else:
        write(f"{troubled} of {shown} captures stopped somewhere. The newest one, capture {first_fix[0][:8]}, first "
              f"stopped at \"{first_fix[1]}\": {first_fix[2]}")
        if first_fix[3]:
            write(f"What to do: {first_fix[3]}")
        if unfinished:
            write(f"{unfinished} more still on the way, with nothing failed.")
    return troubled, unfinished


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
        # Simulators are listed too, and a simulated Watch can come before the real one.
        if hardware.get("reality", "physical") != "physical":
            continue
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
    return exit_code(*report(events, notes))


# ---------------------------------------------------------------- selftest

def exit_code(stopped, on_their_way):
    """0 only when every capture became an entry; 1 when one stopped; 2 when some are still on the way."""
    return 1 if stopped else 2 if on_their_way else 0


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
        troubled, unfinished = report(events, notes, out=text)
        output = text.getvalue()
        assert (troubled, unfinished) == (1, 0), output
        assert "iPhone  no trail" in output, output
        assert "ok       Recorded on the Watch" in output, output
        assert "FAILED   Words back on the wrist" in output, output
        assert "ok       In iCloud" in output, output
        assert "unread   Entry in the app" in output, output
        assert "do not see each other as a pair" in output, output
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
        troubled, unfinished = report(events, notes, out=text)
        output = text.getvalue()
        assert (troubled, unfinished) == (0, 0), output
        assert "All 1 captures made it from the wrist to an entry." in output, output
        assert "ok       Entry in the app         on the iphone" in output, output

        # 3. Kept, and the words came back, but it has not been sent or imported yet: on its way,
        #    not delivered. The report must not say it made it.
        three = "33333333-aaaa-4bbb-8ccc-000000000003"
        watch.write_text("\n".join([
            _line(12, "watch", "keep", capture=three, detail="file=aa11bb22 5.0s 15KB"),
            _line(13, "watch", "link.ask", capture=three, detail="sent to the iPhone: parts=1 15KB"),
            _line(18, "watch", "link.words", capture=three, detail="chars=40 after 5.0s"),
        ]) + "\n")
        phone.write_text(_line(-50, "iphone", "app.launch", detail="v1.0 (30) speechRecognition=allowed") + "\n")
        text = io.StringIO()
        events, notes = load([watch, phone])
        troubled, unfinished = report(events, notes, out=text)
        output = text.getvalue()
        assert (troubled, unfinished) == (0, 1), output
        assert "made it from the wrist to an entry" not in output, output
        assert "still on the way" in output, output
        assert exit_code(troubled, unfinished) == 2

        # 4. Only the iPhone's trail could be copied (the Watch was asleep). The entry exists, so
        #    the capture is delivered; the Watch's steps are unread, not stopped.
        phone.write_text("\n".join([
            _line(-50, "iphone", "app.launch", detail="v1.0 (30) speechRecognition=allowed"),
            _line(93, "iphone", "import.entry", capture=two, detail="entry saved as post chars=64 recording=yes"),
        ]) + "\n")
        text = io.StringIO()
        events, notes = load([Path(folder) / "missing-watch.jsonl", phone])
        troubled, unfinished = report(events, notes, out=text)
        output = text.getvalue()
        assert (troubled, unfinished) == (0, 0), output
        assert "unread   Recorded on the Watch" in output, output
        assert "stopped somewhere" not in output, output

        # 5. The Nov 21 failure on Adam's devices names the pairing, not a missing branch.
        watch.write_text("\n".join([
            _line(12, "watch", "keep", capture=three, detail="file=aa11bb22 5.0s 15KB"),
            _line(13, "watch", "link.ask", capture=three, detail="sent to the iPhone: parts=1 15KB"),
            _line(14, "watch", "link.part", ok=False, capture=three,
                  detail="WatchConnectivity 7018 companionAppNotInstalled"),
        ]) + "\n")
        text = io.StringIO()
        events, notes = load([watch])
        report(events, notes, out=text)
        assert "do not see each other as a pair" in text.getvalue(), text.getvalue()
        assert "branch that has the Watch code" not in text.getvalue(), text.getvalue()

        # 6. The iPhone route (no iCloud): the Watch hands the capture to the iPhone, the iPhone
        #    makes the entry and says so. Nothing is said about iCloud.
        four = "44444444-aaaa-4bbb-8ccc-000000000004"
        watch.write_text("\n".join([
            _line(0, "watch", "app.launch", detail="v1.0 (1)"),
            _line(0, "watch", "route", detail="iphone"),
            _line(12, "watch", "keep", capture=four, detail="file=cd34ef56 7.0s 21KB"),
            _line(13, "watch", "link.ask", capture=four, detail="sent to the iPhone: parts=1 21KB"),
            _line(15, "watch", "link.words", capture=four, detail="chars=41 after 2.1s"),
            _line(20, "watch", "save", capture=four, detail="as social"),
            _line(21, "watch", "phone.send", capture=four, detail="on the iPhone, with its recording"),
        ]) + "\n")
        phone.write_text("\n".join([
            _line(-50, "iphone", "app.launch", detail="v1.0 (1) speechRecognition=allowed"),
            _line(-50, "iphone", "route", detail="iphone"),
            _line(14, "iphone", "link.receive", capture=four, detail="parts=1 21KB app=background unlocked=no"),
            _line(21, "iphone", "phone.entry", capture=four, detail="entry saved as social chars=41 recording=yes"),
        ]) + "\n")
        text = io.StringIO()
        events, notes = load([watch, phone])
        troubled, unfinished = report(events, notes, out=text)
        output = text.getvalue()
        assert (troubled, unfinished) == (0, 0), output
        assert "ok       Handed to the iPhone     on the iPhone, with its recording" in output, output
        assert "ok       Entry in the app         on the iphone" in output, output
        assert "iCloud" not in output, output

        # 7. The iPhone route with the iPhone out of reach: the capture waits on the Watch. That is
        #    waiting, not a failure, and the report says how it gets going again.
        watch.write_text("\n".join([
            _line(0, "watch", "route", detail="iphone"),
            _line(12, "watch", "keep", capture=four, detail="file=cd34ef56 7.0s 21KB"),
            _line(13, "watch", "link.ask", ok=False, capture=four,
                  detail="not sent to the iPhone: link=activated iPhoneReachable=no iPhoneAppInstalled=yes"),
            _line(20, "watch", "save", capture=four, detail="as social"),
            _line(21, "watch", "phone.wait", capture=four,
                  detail="the iPhone is out of reach: link=activated iPhoneReachable=no iPhoneAppInstalled=yes"),
            _line(21, "watch", "phone.queue", capture=four, detail="left with the system, to send when the iPhone is close"),
        ]) + "\n")
        phone.write_text(_line(-50, "iphone", "route", detail="iphone") + "\n")
        text = io.StringIO()
        events, notes = load([watch, phone])
        troubled, unfinished = report(events, notes, out=text)
        output = text.getvalue()
        assert "waiting  Handed to the iPhone" in output, output
        assert "waiting  Entry in the app         it has not reached the iPhone yet" in output, output
        assert "goes when the iPhone is close" in output, output
        assert "iCloud" not in output, output
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
        sys.exit(exit_code(*report(events, notes)))
    else:
        sys.exit(cmd_pull(args))


if __name__ == "__main__":
    main()
