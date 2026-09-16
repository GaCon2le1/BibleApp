# Verse Read-Aloud + Lock Screen Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Listen mode that narrates the feed's verses (KJV) with AVPlayer,
shows standard Lock Screen media controls via `MPNowPlayingInfoCenter`, and
additionally renders a custom "lyrics" Live Activity (current verse + its
`context` as a stacked secondary line) on the Lock Screen and Dynamic Island,
driven by a new `BibleAppWidgets` extension target.

**Architecture:** See `docs/superpowers/specs/2026-09-15-verse-lock-screen-lyrics-design.md`
for the full design. Summary: narration is produced once, offline, by
`tools/build_audio.py` and shipped bundled (`Resources/Audio/<id>.m4a` +
`Resources/audio_index.json`) — no runtime network calls, no CDN, matching
how every other content file in this app is shipped. `BibleFeedKit` gains a
plain-data `VerseAudioEntry`/`AudioIndex` pair. The `BibleApp` target gains
`AudioPlaybackEngine` (AVPlayer/Now Playing/Remote Commands) and
`VerseActivityController` (ActivityKit). A new `BibleAppWidgets` extension
target renders the Live Activity UI only, with no business logic of its own.

**Tech Stack:** Swift 6.3 (BibleFeedKit package + BibleApp + new
BibleAppWidgets extension), Python 3.9.6 stdlib (content pipeline),
SwiftUI/SwiftData, AVFoundation, MediaPlayer, ActivityKit/WidgetKit.

## Global Constraints

- Xcode project: iOS 26.4 deployment target, Xcode 26.4, Swift 6.3. Build with
  `xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
- **Toolchain split, unlike every prior plan in this repo:** Phases 1 and 2
  (the `BibleFeedKit` package changes and the Python content pipeline) can be
  implemented and verified — `swift test --package-path packages/BibleFeedKit`
  and the `/usr/bin/python3 -m unittest` commands — in any environment with
  Swift/Python installed, remote sandboxes included. Phases 3 onward touch
  `BibleApp.xcodeproj` itself (a new Widget Extension target, entitlements,
  ActivityKit, AVFoundation background audio) and require Xcode running on
  macOS to create the target, build, and run — they cannot be created or
  verified from a Linux-only session. Each phase's tasks say explicitly which
  category they're in.
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` is enabled — any Swift
  file directly accessing a `BibleFeedKit` member needs its own
  `import BibleFeedKit`.
- `BibleApp.xcodeproj` uses Xcode's `PBXFileSystemSynchronizedRootGroup` for
  the `BibleApp` target (its whole `BibleApp/BibleApp/` folder is one
  synchronized root). Practically: any new `.swift` file created on disk
  anywhere under `BibleApp/BibleApp/` (e.g. `Audio/`, `LiveActivity/`) is
  automatically part of the `BibleApp` target the next time the project is
  opened — no manual "add to target" step, and Phase 4/Task 6/7/9/11's files
  need none. This does **not** extend to `BibleAppWidgets/` until Task 4
  creates that target (Xcode establishes its own synchronized root then) —
  and `VerseLyricsAttributes.swift` (Task 8) still needs its one manual dual
  target-membership checkbox, since it must belong to both roots at once.
- Python is 3.9.6 at `/usr/bin/python3` on the Mac doing the build (also
  available as plain `python3` in a Linux sandbox for Phase 2's own tests,
  since that phase has no macOS dependency). No pytest, no third-party
  dependencies, no pip. Tests use stdlib `unittest`.
- `BibleFeedKit` imports neither SwiftUI, SwiftData, AVFoundation, nor
  ActivityKit — Phase 1 must not break that; it is what keeps the package
  testable with plain `swift test`.
- Every existing content file stays bundled, not networked. Audio follows
  the same rule: no CDN, no on-demand download, nothing added to
  `ContentStore` that performs a network request.
- Listen mode is KJV-only in v1 (see design doc "Why KJV-only narration") —
  do not wire it to `state.preferredTranslation`.
- `NARRATION_API_KEY` (or whichever the chosen provider needs) is an
  environment variable at build-pipeline time only, never committed, never
  logged, never referenced from app runtime code.
- Every task ends with a commit. Work happens on branch
  `feature/verse-lyrics-live-activity`.
- Never run `git add -A` or `git add .` — stage only the exact files each
  task names.

---

## File Structure

| Path | Responsibility |
|---|---|
| `packages/BibleFeedKit/Sources/BibleFeedKit/VerseAudioEntry.swift` | `VerseAudioEntry`, `AudioIndex` — plain data, mirrors `VerseIndexEntry`/`FeedIndex`. |
| `BibleApp/BibleApp/Resources/audio_index.json` | Shipped manifest: which ids have narration + duration. |
| `BibleApp/BibleApp/Resources/Audio/*.m4a` | Shipped narration clips, one per narrated verse id. |
| `tools/build_audio.py` | One-time/incremental pipeline: calls the narration API, writes clips + manifest. |
| `tools/validate_audio.py` | No-network check that the manifest and clips are internally consistent. |
| `BibleApp/BibleApp/Content/ContentStore.swift` | Extended: loads `audio_index.json`, resolves `audioURL(for:)`/`hasAudio(for:)`. |
| `BibleApp/BibleApp/Audio/AudioPlaybackEngine.swift` | New: AVPlayer, AVAudioSession, Remote Command Center, Now Playing info, queue sequencing. |
| `BibleApp/BibleApp/LiveActivity/VerseLyricsAttributes.swift` | New: `ActivityAttributes` shared by dual target membership (`BibleApp` + `BibleAppWidgets`). |
| `BibleApp/BibleApp/LiveActivity/VerseActivityController.swift` | New: owns the `Activity<VerseLyricsAttributes>` lifecycle. |
| `BibleAppWidgets/` (new target) | New: `BibleAppWidgetsBundle.swift`, `VerseLiveActivity.swift` — Lock Screen + Dynamic Island views only. |
| `BibleApp/BibleApp/Views/VerseCard.swift` | Gains a Listen/play button. |
| `BibleApp/BibleApp/Views/FeedView.swift` | Gains a mini-player overlay; auto-scrolls to the narrating verse. |
| `BibleApp/BibleApp/Info.plist` | `NSSupportsLiveActivities = YES`. |

---

## Phase 1 — `BibleFeedKit`: audio data model (Swift package, testable anywhere)

### Task 1: `VerseAudioEntry` and `AudioIndex`

**Files:**
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/VerseAudioEntry.swift`
- Create: `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseAudioEntryTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `VerseAudioEntry { id, durationMs }`, `AudioIndex { schemaVersion, contentVersion, entries }`. Phase 4's `ContentStore` extension decodes `AudioIndex` from `audio_index.json`.

- [ ] **Step 1: Write the failing test**

Create `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseAudioEntryTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

private let sampleJSON = """
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "entries": [
    { "id": "PSA.23.1", "durationMs": 8200 },
    { "id": "JHN.3.16", "durationMs": 11400 }
  ]
}
""".data(using: .utf8)!

@Test func decodesAudioIndex() throws {
    let index = try JSONDecoder().decode(AudioIndex.self, from: sampleJSON)
    #expect(index.schemaVersion == 1)
    #expect(index.entries.count == 2)
    #expect(index.entries[0].id == "PSA.23.1")
    #expect(index.entries[0].durationMs == 8200)
}

@Test func roundTripsThroughEncodeDecode() throws {
    let entry = VerseAudioEntry(id: "PSA.23.1", durationMs: 8200)
    let data = try JSONEncoder().encode(entry)
    let decoded = try JSONDecoder().decode(VerseAudioEntry.self, from: data)
    #expect(decoded == entry)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path packages/BibleFeedKit`
Expected: FAIL — `cannot find 'AudioIndex' in scope` / `cannot find 'VerseAudioEntry' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `packages/BibleFeedKit/Sources/BibleFeedKit/VerseAudioEntry.swift`:

```swift
import Foundation

/// One narrated verse: which id, and how long the clip runs. Always KJV in
/// v1 (see docs/superpowers/specs/2026-09-15-verse-lock-screen-lyrics-design.md)
/// — there is deliberately no `translation` field here to avoid implying
/// otherwise.
public struct VerseAudioEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let durationMs: Int

    public init(id: String, durationMs: Int) {
        self.id = id
        self.durationMs = durationMs
    }
}

public struct AudioIndex: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let entries: [VerseAudioEntry]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path packages/BibleFeedKit`
Expected: PASS, 2 new tests (all pre-existing tests in the package still pass — this task adds a file, touches nothing else).

- [ ] **Step 5: Commit**

```bash
git add packages/BibleFeedKit/Sources/BibleFeedKit/VerseAudioEntry.swift packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseAudioEntryTests.swift
git commit -m "Add VerseAudioEntry/AudioIndex data model to BibleFeedKit"
```

---

## Phase 2 — Content pipeline (Python, no macOS dependency)

### Task 2: `tools/validate_audio.py` (written before the builder, so the builder has a check to satisfy)

**Files:**
- Create: `tools/validate_audio.py`
- Create: `tools/test_validate_audio.py`
- Create: `tools/fixtures/valid_audio_index.json`
- Create: `tools/fixtures/invalid_audio_index.json`
- Create: `tools/fixtures/audio_fixture/` (a tiny directory standing in for `Resources/Audio/` in tests)

**Interfaces:**
- Consumes: `feed_index.json` (for the set of valid ids), an `audio_index.json`, and a directory of `.m4a` files.
- Produces: `validate_audio(index_path, audio_dir, feed_index_path) -> list[str]` (error strings, empty means valid) — a CLI entry point mirroring `validate_feed.py`'s.

- [ ] **Step 1: Fixtures**

Create `tools/fixtures/valid_audio_index.json`:

```json
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "entries": [
    { "id": "JHN.3.16", "durationMs": 8000 }
  ]
}
```

Create `tools/fixtures/invalid_audio_index.json` (duplicate id, out-of-range duration, and an id absent from the feed):

```json
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "entries": [
    { "id": "JHN.3.16", "durationMs": 8000 },
    { "id": "JHN.3.16", "durationMs": 9000 },
    { "id": "NOPE.1.1", "durationMs": 500000 }
  ]
}
```

Create the fixture audio directory with a placeholder file for the one valid
entry only (so the missing-file check has something to fail against for the
invalid fixture's ids):

```bash
mkdir -p tools/fixtures/audio_fixture
: > tools/fixtures/audio_fixture/JHN.3.16.m4a
```

Reuse (do not duplicate) `tools/fixtures/valid_feed.json` as the stand-in
feed index for these tests — it already contains `JHN.3.16`.

- [ ] **Step 2: Write the failing test**

Create `tools/test_validate_audio.py`:

```python
import pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from validate_audio import validate_audio

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIX = ROOT / "tools" / "fixtures"


class ValidateAudioTests(unittest.TestCase):
    def test_valid_index_has_no_errors(self):
        errors = validate_audio(
            FIX / "valid_audio_index.json",
            FIX / "audio_fixture",
            FIX / "valid_feed.json",
        )
        self.assertEqual(errors, [])

    def test_invalid_index_reports_duplicate(self):
        errors = validate_audio(
            FIX / "invalid_audio_index.json",
            FIX / "audio_fixture",
            FIX / "valid_feed.json",
        )
        self.assertTrue(any("duplicate" in e.lower() for e in errors))

    def test_invalid_index_reports_unknown_id(self):
        errors = validate_audio(
            FIX / "invalid_audio_index.json",
            FIX / "audio_fixture",
            FIX / "valid_feed.json",
        )
        self.assertTrue(any("NOPE.1.1" in e and "not in feed" in e for e in errors))

    def test_invalid_index_reports_duration_out_of_range(self):
        errors = validate_audio(
            FIX / "invalid_audio_index.json",
            FIX / "audio_fixture",
            FIX / "valid_feed.json",
        )
        self.assertTrue(any("duration" in e.lower() for e in errors))

    def test_invalid_index_reports_missing_file(self):
        errors = validate_audio(
            FIX / "invalid_audio_index.json",
            FIX / "audio_fixture",
            FIX / "valid_feed.json",
        )
        self.assertTrue(any("NOPE.1.1" in e and "missing" in e.lower() for e in errors))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run test to verify it fails**

Run: `python3 -m unittest discover -s tools -p 'test_validate_audio.py' -v`
Expected: ERROR — `ModuleNotFoundError: No module named 'validate_audio'`.

- [ ] **Step 4: Write minimal implementation**

Create `tools/validate_audio.py`:

```python
#!/usr/bin/env python3
"""Validate audio_index.json against feed_index.json and the shipped .m4a files.
No network access, no audio decoding — file presence and manifest shape only."""
import json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_INDEX = ROOT / "BibleApp/BibleApp/Resources/audio_index.json"
DEFAULT_AUDIO_DIR = ROOT / "BibleApp/BibleApp/Resources/Audio"
DEFAULT_FEED_INDEX = ROOT / "BibleApp/BibleApp/Resources/feed_index.json"

MIN_DURATION_MS, MAX_DURATION_MS = 1000, 60000


def validate_audio(index_path, audio_dir, feed_index_path):
    errors = []

    try:
        feed_ids = {v["id"] for v in json.loads(feed_index_path.read_text())["verses"]}
    except (OSError, json.JSONDecodeError, KeyError) as e:
        return [f"failed to read feed index {feed_index_path}: {e}"]

    try:
        doc = json.loads(index_path.read_text())
    except (OSError, json.JSONDecodeError) as e:
        return [f"failed to read audio index {index_path}: {e}"]

    seen = set()
    for entry in doc.get("entries", []):
        vid = entry.get("id")
        duration = entry.get("durationMs")

        if vid in seen:
            errors.append(f"{vid}: duplicate id in audio_index.json")
        seen.add(vid)

        if vid not in feed_ids:
            errors.append(f"{vid}: id is not in feed_index.json")

        if not isinstance(duration, int) or not (MIN_DURATION_MS <= duration <= MAX_DURATION_MS):
            errors.append(f"{vid}: duration {duration!r}ms is out of range "
                           f"[{MIN_DURATION_MS}, {MAX_DURATION_MS}]")

        clip = pathlib.Path(audio_dir) / f"{vid}.m4a"
        if not clip.exists():
            errors.append(f"{vid}: audio file missing at {clip}")

    return errors


def main():
    errors = validate_audio(DEFAULT_INDEX, DEFAULT_AUDIO_DIR, DEFAULT_FEED_INDEX)
    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        print(f"{len(errors)} error(s)", file=sys.stderr)
        sys.exit(1)
    print("0 errors")


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python3 -m unittest discover -s tools -p 'test_validate_audio.py' -v`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add tools/validate_audio.py tools/test_validate_audio.py tools/fixtures/valid_audio_index.json tools/fixtures/invalid_audio_index.json tools/fixtures/audio_fixture
git commit -m "Add validate_audio.py for the narration manifest"
```

---

### Task 3: `tools/build_audio.py`

**Files:**
- Create: `tools/build_audio.py`
- Create: `tools/test_build_audio.py`

**Interfaces:**
- Consumes: `data/curation/selection.json`, `BibleApp/BibleApp/Resources/feed_index.json` + `feed_shard_*.json` (KJV `displayText` per id), a narration provider client (injected, so tests never call a real API).
- Produces: `Resources/Audio/<id>.m4a` (real runs only) and a rewritten `audio_index.json`. `build_ids_to_process(...)` is the pure, testable core; the provider call and file I/O are kept thin and separately testable via a fake.

Since the real narration API is not something this plan can call from an
automated test (no network, no committed API key), this task separates the
**resumable id-selection logic** (fully unit-testable) from the **narration
call + file write** (exercised with a fake provider in tests, and for real
only when a maintainer runs the script by hand with a real key).

- [ ] **Step 1: Write the failing test**

Create `tools/test_build_audio.py`:

```python
import json, pathlib, sys, tempfile, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from build_audio import ids_needing_audio, run_pipeline


class FakeProvider:
    """Stands in for the real narration API: returns fixed bytes and a
    deterministic fake duration, and records every id it was asked to narrate."""
    def __init__(self):
        self.calls = []

    def narrate(self, verse_id, text):
        self.calls.append((verse_id, text))
        return b"FAKE-AUDIO-BYTES", 7500  # (clip bytes, durationMs)


class IdsNeedingAudioTests(unittest.TestCase):
    def test_all_ids_needed_when_index_empty(self):
        needed = ids_needing_audio(all_ids=["A.1.1", "B.1.1"], already_done=set())
        self.assertEqual(needed, ["A.1.1", "B.1.1"])

    def test_already_done_ids_are_skipped(self):
        needed = ids_needing_audio(all_ids=["A.1.1", "B.1.1"], already_done={"A.1.1"})
        self.assertEqual(needed, ["B.1.1"])

    def test_order_is_stable_and_matches_input(self):
        needed = ids_needing_audio(all_ids=["C.1.1", "A.1.1", "B.1.1"], already_done=set())
        self.assertEqual(needed, ["C.1.1", "A.1.1", "B.1.1"])


class RunPipelineTests(unittest.TestCase):
    def test_writes_clip_and_appends_manifest_entry(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            audio_dir = tmp / "Audio"
            audio_dir.mkdir()
            index_path = tmp / "audio_index.json"
            index_path.write_text(json.dumps(
                {"schemaVersion": 1, "contentVersion": "0", "entries": []}))

            provider = FakeProvider()
            run_pipeline(
                texts={"JHN.3.16": "For God so loved the world."},
                audio_dir=audio_dir,
                index_path=index_path,
                provider=provider,
                content_version="test.1",
            )

            self.assertEqual(provider.calls, [("JHN.3.16", "For God so loved the world.")])
            self.assertTrue((audio_dir / "JHN.3.16.m4a").exists())
            self.assertEqual((audio_dir / "JHN.3.16.m4a").read_bytes(), b"FAKE-AUDIO-BYTES")

            doc = json.loads(index_path.read_text())
            self.assertEqual(doc["contentVersion"], "test.1")
            self.assertEqual(doc["entries"], [{"id": "JHN.3.16", "durationMs": 7500}])

    def test_is_resumable_and_does_not_renarrate_existing_ids(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            audio_dir = tmp / "Audio"
            audio_dir.mkdir()
            index_path = tmp / "audio_index.json"
            index_path.write_text(json.dumps({
                "schemaVersion": 1, "contentVersion": "0",
                "entries": [{"id": "JHN.3.16", "durationMs": 8000}],
            }))
            (audio_dir / "JHN.3.16.m4a").write_bytes(b"EXISTING")

            provider = FakeProvider()
            run_pipeline(
                texts={"JHN.3.16": "text", "PSA.23.1": "other text"},
                audio_dir=audio_dir,
                index_path=index_path,
                provider=provider,
                content_version="test.2",
            )

            # Only the new id was narrated; the existing clip is untouched.
            self.assertEqual(provider.calls, [("PSA.23.1", "other text")])
            self.assertEqual((audio_dir / "JHN.3.16.m4a").read_bytes(), b"EXISTING")

            doc = json.loads(index_path.read_text())
            ids = sorted(e["id"] for e in doc["entries"])
            self.assertEqual(ids, ["JHN.3.16", "PSA.23.1"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest discover -s tools -p 'test_build_audio.py' -v`
Expected: ERROR — `ModuleNotFoundError: No module named 'build_audio'`.

- [ ] **Step 3: Write minimal implementation**

Create `tools/build_audio.py`:

```python
#!/usr/bin/env python3
"""Produce narrated .m4a clips for the shipped feed and the manifest
(audio_index.json) describing them. Resumable: an id already present in the
manifest and on disk is left untouched, so a partial run (or a targeted
re-take of one id, after deleting its manifest entry and file) can be
re-run safely. Requires network access and a narration provider API key —
not run as part of any automated test suite."""
import json, os, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
AUDIO_DIR = ROOT / "BibleApp/BibleApp/Resources/Audio"
INDEX_PATH = ROOT / "BibleApp/BibleApp/Resources/audio_index.json"
FEED_INDEX = ROOT / "BibleApp/BibleApp/Resources/feed_index.json"


def ids_needing_audio(all_ids, already_done):
    """all_ids in their existing feed order; already_done is the set of ids
    with both a manifest entry and a file on disk. Order is preserved so
    reruns narrate in a predictable sequence."""
    return [vid for vid in all_ids if vid not in already_done]


def run_pipeline(texts, audio_dir, index_path, provider, content_version):
    """texts: {id: kjv_display_text} for every id this run should ensure has
    audio. provider: object with narrate(id, text) -> (bytes, durationMs).
    Skips any id whose manifest entry AND file already exist."""
    audio_dir = pathlib.Path(audio_dir)
    index_path = pathlib.Path(index_path)
    doc = json.loads(index_path.read_text())
    entries = {e["id"]: e for e in doc["entries"]}

    already_done = {
        vid for vid in entries
        if (audio_dir / f"{vid}.m4a").exists()
    }
    for vid in ids_needing_audio(list(texts.keys()), already_done):
        clip_bytes, duration_ms = provider.narrate(vid, texts[vid])
        (audio_dir / f"{vid}.m4a").write_bytes(clip_bytes)
        entries[vid] = {"id": vid, "durationMs": duration_ms}

    doc["contentVersion"] = content_version
    doc["entries"] = [entries[vid] for vid in sorted(entries)]
    index_path.write_text(json.dumps(doc, indent=2) + "\n")


class NarrationAPIError(Exception):
    pass


class RealNarrationProvider:
    """Talks to the actual narration API. Import-guarded and only
    constructed by main() for a real run, never by tests."""

    def __init__(self, api_key):
        self.api_key = api_key

    def narrate(self, verse_id, text):
        raise NotImplementedError(
            "Wire this to the chosen narration provider's HTTP API before "
            "running tools/build_audio.py for real. Deliberately left "
            "unimplemented in this plan, since the provider/voice is a "
            "production decision made at run time, not at plan-writing time.")


def main():
    api_key = os.environ.get("NARRATION_API_KEY")
    if not api_key:
        sys.exit("NARRATION_API_KEY is not set — see tools/build_audio.py's "
                 "RealNarrationProvider before running this for real.")

    all_ids = [v["id"] for v in json.loads(FEED_INDEX.read_text())["verses"]]
    # Real run only: load each id's KJV displayText from its shard file.
    # (Left as a TODO for whoever runs this for real — shard lookup mirrors
    # ContentStore.content(for:) but in Python; do not duplicate KJV text by
    # hand here.)
    raise NotImplementedError(
        "Wire shard-file KJV text lookup here before running for real.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest discover -s tools -p 'test_build_audio.py' -v`
Expected: PASS, 5 tests. (`main()` itself is intentionally untested here —
it requires a real API key and real shard files; `run_pipeline` and
`ids_needing_audio` carry all the logic worth unit testing.)

- [ ] **Step 5: Commit**

```bash
git add tools/build_audio.py tools/test_build_audio.py
git commit -m "Add build_audio.py pipeline scaffold (resumable, provider-agnostic)"
```

**Follow-up, not part of this plan's automated steps:** before a real
production run, replace `RealNarrationProvider.narrate` with a real HTTP call
to the chosen narration API, and `main()`'s KJV-text lookup with real shard
reads, then run once with a real `NARRATION_API_KEY`, then run
`validate_audio.py`, then commit the resulting `Resources/Audio/*.m4a` +
`audio_index.json` as a dedicated task (binary assets, reviewed for size —
expect roughly 30–60 KB per clip × however many of the 600 ids are narrated
in the first pass).

---

## Phase 3 — Xcode project changes (macOS + Xcode only, no automated test)

These steps have no automated pass/fail — they change project structure, not
testable logic. Perform them in Xcode; there is nothing to run from the
command line to "verify" beyond a successful build at the end of Phase 6.

### Task 4: Add the Widget Extension target

- [ ] In Xcode: **File → New → Target… → Widget Extension**. Product Name:
  `BibleAppWidgets`. Uncheck "Include Configuration Intent" (not needed —
  this widget has no user-configurable settings). Ensure "Activate scheme"
  is checked and it embeds in the `BibleApp` target.
- [ ] Delete the template's placeholder `TimelineProvider`/static widget
  files that Xcode generates by default (`BibleAppWidgets.swift`'s sample
  `Provider`/`SimpleEntry`/static `Widget`) — this extension only ever hosts
  a Live Activity, not a Home Screen widget.
- [ ] Confirm the new target's own deployment target matches the app
  target's (iOS 26.4) in Build Settings.
- [ ] Build once (`Cmd+B`) to confirm the empty extension target compiles
  before adding any custom code.
- [ ] Commit the Xcode project changes alone, before writing any Live
  Activity code, so the target-creation diff is reviewable on its own:

```bash
git add BibleApp/BibleApp.xcodeproj BibleAppWidgets
git commit -m "Add BibleAppWidgets Widget Extension target (empty scaffold)"
```

### Task 5: App Group + entitlements + Info.plist

- [ ] Select the `BibleApp` target → Signing & Capabilities → **+ Capability
  → App Groups** → add `group.<your-bundle-id>.bibleapp`.
- [ ] Select the `BibleAppWidgets` target → Signing & Capabilities → **+
  Capability → App Groups** → check the same group.
- [ ] `BibleApp/BibleApp/Info.plist`: add key `NSSupportsLiveActivities`,
  Boolean, `YES`.
- [ ] `BibleApp` target → Signing & Capabilities → **+ Capability →
  Background Modes** → check **Audio, AirPlay, and Picture in Picture**.
- [ ] Build both targets (`Cmd+B`).
- [ ] Commit:

```bash
git add BibleApp/BibleApp.xcodeproj BibleApp/BibleApp/Info.plist BibleApp/BibleApp/BibleApp.entitlements BibleAppWidgets/BibleAppWidgets.entitlements
git commit -m "Add App Group, Live Activities and background audio capabilities"
```

---

## Phase 4 — Runtime: `ContentStore` audio lookup + `AudioPlaybackEngine`

> Verification for this phase is a local Xcode build + Simulator run — this
> app has no unit test target of its own (only `BibleFeedKit` is
> headless-testable, by original design). Each task still specifies exactly
> what to build and run manually.

### Task 6: `ContentStore` resolves audio files

**Files:**
- Modify: `BibleApp/BibleApp/Content/ContentStore.swift`

**Interfaces:**
- Consumes: `AudioIndex` (Phase 1), `Bundle.main` resources `audio_index.json` and `Audio/<id>.m4a`.
- Produces: `ContentStore.hasAudio(for id: String) -> Bool`, `ContentStore.audioURL(for id: String) -> URL?`. `VerseCard` (Task 10) and `AudioPlaybackEngine` (Task 7) both call these.

- [ ] **Step 1: Extend `ContentStore`**

Add to `BibleApp/BibleApp/Content/ContentStore.swift`, alongside the existing
`index`/`indexByID` properties and `load()`:

```swift
private var audioIDs: Set<String> = []

/// Whether `id` has a narrated clip bundled. `VerseCard` uses this to hide
/// its Listen control on a card with no audio, rather than showing a
/// control that would silently do nothing.
func hasAudio(for id: String) -> Bool {
    audioIDs.contains(id)
}

/// `nil` if `id` has no bundled clip (see `hasAudio`) — callers that reach
/// this without checking `hasAudio` first (e.g. a stale queue built before
/// a data update) get a safe nil rather than a URL to a missing file.
func audioURL(for id: String) -> URL? {
    guard audioIDs.contains(id) else { return nil }
    return Bundle.main.url(forResource: id, withExtension: "m4a", subdirectory: "Audio")
}
```

Extend `load()` to also read the audio index (append after the existing feed
index load, inside the same method, as its own independent try so a missing
audio index degrades the Listen feature only, not the whole feed — unlike
`feed_index.json`, whose absence already fails the whole app):

```swift
loadAudioIndex()
```

```swift
private func loadAudioIndex() {
    guard let url = Bundle.main.url(forResource: "audio_index", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(AudioIndex.self, from: data)
    else {
        audioIDs = []  // Listen mode unavailable; rest of the app is unaffected.
        return
    }
    audioIDs = Set(decoded.entries.map(\.id))
}
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. (`audio_index.json`/`Resources/Audio/`
do not exist in the bundle yet at this point in the plan — `hasAudio`
returning `false` for everything is the correct, safe state until Phase 2's
follow-up production run ships real clips.)

- [ ] **Step 3: Commit**

```bash
git add BibleApp/BibleApp/Content/ContentStore.swift
git commit -m "ContentStore resolves narrated audio files by verse id"
```

### Task 7: `AudioPlaybackEngine`

**Files:**
- Create: `BibleApp/BibleApp/Audio/AudioPlaybackEngine.swift`

**Interfaces:**
- Consumes: `ContentStore.audioURL(for:)`, a `[VerseIndexEntry]` queue + start index (from `FeedView`, Task 11), `VerseContent` for the KJV text shown on the Now Playing card.
- Produces: `AudioPlaybackEngine` — `currentVerseID`, `isPlaying`, `elapsed`, `duration`, `start(queue:at:)`, `togglePlayPause()`, `stop()`, and an `onVerseChanged: ((VerseIndexEntry) -> Void)?` hook `VerseActivityController` (Task 8) and `FeedView` (Task 11) both observe.

- [ ] **Step 1: Write the engine**

Create `BibleApp/BibleApp/Audio/AudioPlaybackEngine.swift`:

```swift
import AVFoundation
import MediaPlayer
import BibleFeedKit

/// Owns narrated playback end to end: the AVPlayer itself, the system Now
/// Playing card (MPNowPlayingInfoCenter), Lock Screen / Control Center
/// remote commands, and walking forward through the feed's current queue.
/// KJV-only in v1 — every clip it plays is the KJV narration regardless of
/// `UserState.preferredTranslation` (see the design doc's "Why KJV-only").
@MainActor
@Observable
final class AudioPlaybackEngine: NSObject {
    private(set) var currentVerseID: String?
    private(set) var isPlaying = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    /// Fires whenever playback moves to a new verse (including the first
    /// one `start` plays), so observers can update Now Playing info, the
    /// Live Activity, and feed auto-scroll without polling.
    var onVerseChanged: ((VerseIndexEntry) -> Void)?
    var onStopped: (() -> Void)?

    private let contentStore: ContentStore
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var queue: [VerseIndexEntry] = []
    private var position = 0

    init(contentStore: ContentStore) {
        self.contentStore = contentStore
        super.init()
        configureRemoteCommands()
    }

    func start(queue: [VerseIndexEntry], at index: Int) {
        guard queue.indices.contains(index) else { return }
        activateAudioSession()
        self.queue = queue
        self.position = index
        playCurrent()
    }

    func stop() {
        teardownCurrentItem()
        player = nil
        isPlaying = false
        currentVerseID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onStopped?()
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func advance() {
        guard position + 1 < queue.count else { stop(); return }
        position += 1
        playCurrent()
    }

    func rewindToPrevious() {
        guard position > 0 else { return }
        position -= 1
        playCurrent()
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    private func playCurrent() {
        guard queue.indices.contains(position) else { return }
        let entry = queue[position]
        guard let url = contentStore.audioURL(for: entry.id) else {
            // No narration for this verse — skip it rather than stalling
            // Listen mode on a silent gap.
            advance()
            return
        }

        teardownCurrentItem()
        let item = AVPlayerItem(url: url)
        let newPlayer = player ?? AVPlayer()
        newPlayer.replaceCurrentItem(with: item)
        player = newPlayer
        currentVerseID = entry.id
        isPlaying = true
        newPlayer.play()
        observe(item: item, on: newPlayer)
        onVerseChanged?(entry)
        updateNowPlayingInfo()
    }

    private func observe(item: AVPlayerItem, on player: AVPlayer) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.elapsed = time.seconds
            self.duration = item.asset.duration.seconds.isFinite ? item.asset.duration.seconds : 0
        }
    }

    private func teardownCurrentItem() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        elapsed = 0
        duration = 0
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self, !self.isPlaying, self.player != nil else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.advance()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.rewindToPrevious()
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let verseID = currentVerseID,
              let entry = queue.first(where: { $0.id == verseID }) else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: entry.reference,
            MPMediaItemPropertyArtist: "BibleApp",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. `AudioPlaybackEngine` is not yet wired to any UI, so nothing is runtime-testable yet — Task 11 wires it in.

- [ ] **Step 3: Commit**

```bash
git add BibleApp/BibleApp/Audio/AudioPlaybackEngine.swift
git commit -m "Add AudioPlaybackEngine (AVPlayer, Now Playing, Remote Commands)"
```

---

## Phase 5 — Live Activity

### Task 8: `VerseLyricsAttributes` (dual target membership)

**Files:**
- Create: `BibleApp/BibleApp/LiveActivity/VerseLyricsAttributes.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `VerseLyricsAttributes`, `VerseLyricsAttributes.ContentState`. Consumed by both `VerseActivityController` (Task 9, `BibleApp` target) and `VerseLiveActivity` (Task 10, `BibleAppWidgets` target) — this one file must belong to both targets.

- [ ] **Step 1: Create the file**

```swift
import ActivityKit
import Foundation

/// Shared between the BibleApp and BibleAppWidgets targets (dual target
/// membership — this file, not a framework, since it is the only type
/// either side needs from the other). No static attributes: every field the
/// widget renders changes as playback advances, so all of it lives in
/// ContentState.
public struct VerseLyricsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var verseText: String
        public var reference: String
        public var secondaryText: String
        public var elapsedSeconds: Double
        public var durationSeconds: Double
        public var isPlaying: Bool

        public init(verseText: String, reference: String, secondaryText: String,
                    elapsedSeconds: Double, durationSeconds: Double, isPlaying: Bool) {
            self.verseText = verseText
            self.reference = reference
            self.secondaryText = secondaryText
            self.elapsedSeconds = elapsedSeconds
            self.durationSeconds = durationSeconds
            self.isPlaying = isPlaying
        }
    }

    public init() {}
}
```

- [ ] **Step 2: Set target membership in Xcode**

Select the file in the Project Navigator → File Inspector (right panel) →
Target Membership → check both `BibleApp` and `BibleAppWidgets`.

- [ ] **Step 3: Build both targets**

`Cmd+B` with each scheme, or:
```bash
xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 4: Commit**

```bash
git add BibleApp/BibleApp/LiveActivity/VerseLyricsAttributes.swift BibleApp/BibleApp.xcodeproj
git commit -m "Add VerseLyricsAttributes shared by BibleApp and BibleAppWidgets"
```

### Task 9: `VerseActivityController`

**Files:**
- Create: `BibleApp/BibleApp/LiveActivity/VerseActivityController.swift`

**Interfaces:**
- Consumes: `AudioPlaybackEngine` (Task 7, via its `onVerseChanged`/`isPlaying`/`elapsed`/`duration`), `VerseContent.context` for the secondary line, `VerseLyricsAttributes` (Task 8).
- Produces: `VerseActivityController.start(entry:content:engine:)`, `.updateProgress()`, `.end()`. `FeedView` (Task 11) owns one instance alongside `AudioPlaybackEngine`.

- [ ] **Step 1: Create the controller**

```swift
import ActivityKit
import BibleFeedKit

/// Owns the single Live Activity's lifecycle. Never blocks or fails
/// playback if Live Activities are unavailable or denied — checked once,
/// up front, per the design doc's error-handling table.
@MainActor
final class VerseActivityController {
    private var activity: Activity<VerseLyricsAttributes>?

    func start(entry: VerseIndexEntry, content: VerseContent, engine: AudioPlaybackEngine) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = contentState(entry: entry, content: content, engine: engine)
        do {
            activity = try Activity.request(
                attributes: VerseLyricsAttributes(),
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            // Not fatal: playback and the system Now Playing card continue
            // regardless (see design doc's error-handling table).
            activity = nil
        }
    }

    func update(entry: VerseIndexEntry, content: VerseContent, engine: AudioPlaybackEngine) {
        guard let activity else { return }
        let state = contentState(entry: entry, content: content, engine: engine)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    private func contentState(entry: VerseIndexEntry, content: VerseContent,
                               engine: AudioPlaybackEngine) -> VerseLyricsAttributes.ContentState {
        .init(
            verseText: content.translations[.kjv]?.displayText ?? "",
            reference: entry.reference,
            secondaryText: content.context,
            elapsedSeconds: engine.elapsed,
            durationSeconds: engine.duration,
            isPlaying: engine.isPlaying
        )
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add BibleApp/BibleApp/LiveActivity/VerseActivityController.swift
git commit -m "Add VerseActivityController"
```

### Task 10: `VerseLiveActivity` widget UI

**Files:**
- Create: `BibleAppWidgets/VerseLiveActivity.swift`
- Modify: `BibleAppWidgets/BibleAppWidgetsBundle.swift` (Xcode-generated; register the new activity configuration)

**Interfaces:**
- Consumes: `VerseLyricsAttributes` (Task 8) only.
- Produces: the rendered Lock Screen banner and Dynamic Island compact/minimal/expanded regions. No logic — purely a function of whatever `ContentState` Task 9 last pushed.

- [ ] **Step 1: Create the widget**

```swift
import ActivityKit
import SwiftUI
import WidgetKit

struct VerseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VerseLyricsAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "book.fill")
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBody(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "book.fill")
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
            } minimal: {
                Image(systemName: "book.fill")
            }
        }
    }
}

private struct LockScreenView: View {
    let state: VerseLyricsAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.reference)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(state.verseText)
                .font(.headline)
                .lineLimit(3)
            Text(state.secondaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if state.durationSeconds > 0 {
                ProgressView(value: state.elapsedSeconds, total: state.durationSeconds)
                    .tint(.white)
            }
        }
        .padding(16)
    }
}

private struct ExpandedBody: View {
    let state: VerseLyricsAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.reference)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(state.verseText)
                .font(.subheadline)
                .lineLimit(3)
        }
        .padding(.horizontal)
    }
}
```

- [ ] **Step 2: Register it in the widget bundle**

In `BibleAppWidgets/BibleAppWidgetsBundle.swift` (the file Xcode generated
with Task 4), replace its body with:

```swift
import WidgetKit
import SwiftUI

@main
struct BibleAppWidgetsBundle: WidgetBundle {
    var body: some Widget {
        VerseLiveActivity()
    }
}
```

(Remove any leftover static-widget struct the template generated, per Task
4's instruction to delete the placeholder.)

- [ ] **Step 3: Build**

```bash
xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add BibleAppWidgets/VerseLiveActivity.swift BibleAppWidgets/BibleAppWidgetsBundle.swift
git commit -m "Add VerseLiveActivity Lock Screen and Dynamic Island UI"
```

---

## Phase 6 — Feed integration

### Task 11: Listen control on `VerseCard`, mini-player + auto-scroll on `FeedView`

**Files:**
- Modify: `BibleApp/BibleApp/Views/VerseCard.swift`
- Modify: `BibleApp/BibleApp/Views/FeedView.swift`

**Interfaces:**
- Consumes: `AudioPlaybackEngine` (Task 7), `VerseActivityController` (Task 9), `ContentStore.hasAudio(for:)` (Task 6).
- Produces: user-visible Listen mode. This is the task that finally makes every earlier piece observable end to end.

- [ ] **Step 1: `VerseCard` gains a Listen button**

In `BibleApp/BibleApp/Views/VerseCard.swift`, add a parameter and a control
next to the existing save button:

```swift
let hasAudio: Bool
let isNarrating: Bool
let onListen: () -> Void
```

```swift
if hasAudio {
    Button(action: onListen) {
        Image(systemName: isNarrating ? "waveform" : "play.circle")
            .font(.title3)
    }
    .accessibilityLabel(isNarrating ? "Now narrating" : "Listen (KJV)")
}
```

placed inside the existing `HStack` alongside the bookmark button.

- [ ] **Step 2: `FeedView` owns playback and the mini-player**

In `BibleApp/BibleApp/Views/FeedView.swift`, add state:

```swift
@State private var audioEngine: AudioPlaybackEngine?
@State private var activityController = VerseActivityController()
@State private var isListening = false
@State private var scrolledID: String?
```

Initialize `audioEngine` in `rebuild()` (or `onAppear`) with
`AudioPlaybackEngine(contentStore: store)`, and wire its callbacks once:

```swift
audioEngine?.onVerseChanged = { [weak audioEngine] entry in
    guard let audioEngine else { return }
    Task {
        let content = await store.content(for: [entry.id])
        guard let verseContent = content[entry.id] else { return }
        if isListening {
            activityController.update(entry: entry, content: verseContent, engine: audioEngine)
        } else {
            activityController.start(entry: entry, content: verseContent, engine: audioEngine)
            isListening = true
        }
        // Auto-scroll the feed to follow the narrating verse.
        withAnimation { scrolledID = entry.id }
    }
}
audioEngine?.onStopped = {
    activityController.end()
    isListening = false
}
```

`isListening` is `FeedView`'s own flag for "has a Live Activity been started
this session" — `VerseActivityController` intentionally exposes no such
query itself, so the caller tracks it.

Pass `hasAudio`/`isNarrating`/`onListen` down to each `VerseCard`:

```swift
VerseCard(entry: entry,
          content: loadedContent[entry.id],
          translation: state.preferredTranslation,
          isSaved: state.savedSet.contains(entry.id),
          onSave: { state.toggleSaved(entry.id) },
          hasAudio: store.hasAudio(for: entry.id),
          isNarrating: audioEngine?.currentVerseID == entry.id,
          onListen: {
              guard let position = queue.firstIndex(where: { $0.id == entry.id }) else { return }
              audioEngine?.start(queue: queue, at: position)
          })
```

Add a `ScrollViewReader` around the existing `ScrollView` (if not already
present) so `scrolledID` can drive `scrollTo`, following the same pattern
`.scrollTargetLayout()`/`.scrollTargetBehavior(.paging)` already establishes
for the feed's own paging.

- [ ] **Step 2: Build and run on the Simulator**

```bash
xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

Launch on the Simulator. With no real `.m4a` files bundled yet (Phase 2's
follow-up production run has not happened in this plan), every card's
`hasAudio` is `false` and the Listen button is correctly absent everywhere —
this task's own visible confirmation is exactly that absence, not broken UI.
Full end-to-end confirmation of tapping Listen, hearing narration, and
seeing the Lock Screen/Dynamic Island update happens in Phase 8, once real
clips exist.

- [ ] **Step 3: Commit**

```bash
git add BibleApp/BibleApp/Views/VerseCard.swift BibleApp/BibleApp/Views/FeedView.swift
git commit -m "Wire Listen mode into VerseCard and FeedView"
```

---

## Phase 7 — Produce real narration (one-time, manual, costs money)

### Task 12: Run the pipeline for real

- [ ] Implement `RealNarrationProvider.narrate` in `tools/build_audio.py`
  against the chosen narration API (left unimplemented by Phase 2 on
  purpose — provider/voice selection is a production decision, not a
  planning one).
- [ ] Implement the KJV shard-text lookup in `main()`.
- [ ] Run with a real key, starting with a small subset (e.g. the 12 tier-1
  ids used in existing test fixtures) to sanity-check voice quality before
  spending the full budget on all 600:
  ```bash
  NARRATION_API_KEY=... python3 tools/build_audio.py
  ```
- [ ] Run `python3 tools/validate_audio.py` — expect `0 errors`.
- [ ] Spot-listen to a handful of clips.
- [ ] Once satisfied, run the full 600.
- [ ] Commit the binary assets as their own reviewable change:

```bash
git add BibleApp/BibleApp/Resources/Audio BibleApp/BibleApp/Resources/audio_index.json
git commit -m "Add narrated audio clips for the KJV feed"
```

---

## Phase 8 — On-device QA (manual, real iPhone required for Dynamic Island)

- [ ] Tap Listen on a card with audio → narration starts, system Lock
  Screen Now Playing card appears when the phone is locked, showing the
  right reference/progress.
- [ ] Lock Screen Live Activity appears alongside/below the system Now
  Playing card, showing verse text + `context` as the secondary line,
  progress bar advancing.
- [ ] Verse finishes narrating → auto-advances to the next audio-bearing
  verse; a verse with no audio in between is skipped, not silently stalled.
- [ ] Dynamic Island: compact view while another app is foregrounded; long
  press → expanded view matches the Lock Screen content.
- [ ] Remote commands: play/pause from Lock Screen and Control Center;
  next/previous (if the device's control surface exposes them).
- [ ] Incoming phone call interrupts playback; after the call ends, state is
  left paused (not silently resumed with the Live Activity now showing
  stale "isPlaying: true").
  Confirm the Live Activity's `isPlaying` flag was actually pushed to
  `false` by an update on the interruption — this is the concrete
  behavior the design doc's "Phone call" row commits to; re-check it here,
  don't just assume the AVAudioSession pause implies it.
- [ ] Switching to AirPods mid-playback keeps playing without a glitch.
- [ ] Force-quit the app mid-playback → confirm Live Activity freezes at
  its last state rather than crashing or disappearing (expected per design
  doc; this step is about confirming *that* documented behavior, not fixing
  it).
- [ ] Toggle this app's Live Activities off in iOS Settings → Listen mode
  still narrates and the system Now Playing card still works; no crash.

## Out of scope (same as the design doc)

Word-level lyric highlighting · BSB/CPDV narration · push-to-update Live
Activities after the app is killed · CDN/on-demand audio · per-user
speed/voice picker · Apple Watch companion · sharing the now-playing verse
as an image.
