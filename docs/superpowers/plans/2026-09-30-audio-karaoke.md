# Audio Karaoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the sentence currently being spoken as the Now Playing title (expanded Dynamic Island, Lock Screen) and in the in-app player.

**Architecture:** A Python tool turns whisper.cpp output into short timed lines saved as `<episode>.transcript.json` beside the mp3. `BibleFeedKit` decodes it and finds the line for a playback time. `AudioPlayer` tracks the current line on its time observer and rewrites the Now Playing title only when the line changes.

**Tech Stack:** Python 3.9 stdlib + `unittest`, whisper.cpp (`whisper-cli`), ffmpeg, Swift 6 / SwiftUI, MediaPlayer, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-30-audio-karaoke-design.md`

## Global Constraints

- Branch `feature/audio-listen`. The working tree holds the user's uncommitted resource reorganisation: commit **only** this plan's files with `/usr/bin/git commit -m "…" -- <paths>`. Never commit `Resources/audio/test.mp3`, `Resources/json/*`, or any Whisper model.
- Python tools use only the standard library and `unittest` (no pytest), run with `/usr/bin/python3`.
- Lines are at most **80** characters. Default model `~/.cache/whisper/ggml-large-v3-turbo.bin`, default language **`vi`**.
- Time observer interval **0.25 s**; Now Playing is refreshed only when the line changes.
- App target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

Build: `xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'generic/platform=iOS Simulator' -quiet build`

---

### Task 1: `tools/transcribe_audio.py`

**Files:** Create `tools/transcribe_audio.py`, `tools/test_transcribe_audio.py`

**Produces:** `parse_whisper_json(data)`, `collapse_repeats(segments)`, `split_segment(segment, max_chars=80)`, `build_lines(segments, max_chars=80)`; CLI `tools/transcribe_audio.py <mp3> [--model PATH] [--language vi]` writing `<stem>.transcript.json`.

- [ ] **Step 1: Failing tests** — `tools/test_transcribe_audio.py`:

```python
import pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from transcribe_audio import build_lines, collapse_repeats, parse_whisper_json, split_segment


def seg(start, end, text):
    return {"start": start, "end": end, "text": text}


class ParseWhisperJsonTests(unittest.TestCase):
    def test_reads_offsets_in_seconds_and_strips_text(self):
        data = {"transcription": [
            {"offsets": {"from": 0, "to": 2000}, "text": " Dòng đầu tiên."},
            {"offsets": {"from": 2000, "to": 5500}, "text": " Dòng thứ hai. "},
        ]}
        self.assertEqual(parse_whisper_json(data),
                         [seg(0.0, 2.0, "Dòng đầu tiên."), seg(2.0, 5.5, "Dòng thứ hai.")])


class CollapseRepeatsTests(unittest.TestCase):
    def test_repeated_text_extends_the_previous_segment(self):
        segments = [seg(0, 2, "A."), seg(2, 4, "A."), seg(4, 6, "B."), seg(6, 8, "A.")]
        self.assertEqual(collapse_repeats(segments),
                         [seg(0, 4, "A."), seg(4, 6, "B."), seg(6, 8, "A.")])

    def test_does_not_mutate_input(self):
        segments = [seg(0, 2, "A."), seg(2, 4, "A.")]
        collapse_repeats(segments)
        self.assertEqual(segments[0]["end"], 2)


class SplitSegmentTests(unittest.TestCase):
    def test_short_segment_is_one_line(self):
        self.assertEqual(split_segment(seg(1, 3, "Thành là ai?")), [seg(1, 3, "Thành là ai?")])

    def test_splits_sentences_and_shares_time_by_length(self):
        lines = split_segment(seg(10, 20, "Một hai ba. Bốn năm sáu bảy tám chín mười."), max_chars=80)
        self.assertEqual([l["text"] for l in lines], ["Một hai ba.", "Bốn năm sáu bảy tám chín mười."])
        self.assertEqual(lines[0]["start"], 10)
        self.assertAlmostEqual(lines[0]["end"], 10 + 10 * 11 / 41)
        self.assertEqual(lines[1]["start"], lines[0]["end"])
        self.assertEqual(lines[1]["end"], 20)

    def test_long_sentence_breaks_at_a_comma(self):
        text = "Bà vừa khóc vừa nói rằng sau khi chôn con, có người quen bên họ hàng biết một gia đình."
        lines = split_segment(seg(0, 9, text), max_chars=60)
        self.assertEqual([l["text"] for l in lines],
                         ["Bà vừa khóc vừa nói rằng sau khi chôn con,",
                          "có người quen bên họ hàng biết một gia đình."])

    def test_long_sentence_without_comma_breaks_at_a_space(self):
        text = "một hai ba bốn năm sáu bảy tám chín mười"
        lines = split_segment(seg(0, 4, text), max_chars=20)
        self.assertTrue(all(len(l["text"]) <= 20 for l in lines))
        self.assertEqual(" ".join(l["text"] for l in lines), text)

    def test_early_comma_is_not_used_as_a_break(self):
        text = "Rồi, anh ngẩng lên nhìn tấm bia thật lâu mà không nói gì"
        lines = split_segment(seg(0, 4, text), max_chars=40)
        self.assertNotEqual(lines[0]["text"], "Rồi,")

    def test_word_longer_than_limit_is_hard_cut(self):
        lines = split_segment(seg(0, 1, "x" * 25), max_chars=10)
        self.assertEqual([len(l["text"]) for l in lines], [10, 10, 5])


class BuildLinesTests(unittest.TestCase):
    def test_drops_empty_collapses_repeats_and_rounds(self):
        segments = [seg(0, 1, "  "), seg(1, 2.3333, "A."), seg(2.3333, 4.6666, "A."), seg(4.6666, 6, "B.")]
        self.assertEqual(build_lines(segments),
                         [seg(1, 4.67, "A."), seg(4.67, 6, "B.")])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2:** `/usr/bin/python3 -m unittest tools/test_transcribe_audio.py` → FAIL (`ModuleNotFoundError: transcribe_audio`).

- [ ] **Step 3: Implement** — `tools/transcribe_audio.py`:

```python
#!/usr/bin/env python3
"""Generate the karaoke transcript for a bundled audio episode.

Runs whisper.cpp on an mp3 and writes <stem>.transcript.json beside it:
{"lines": [{"start": 12.3, "end": 15.8, "text": "..."}]} -- short timed lines
the app shows as the Now Playing title. Whisper mishears some words, so read
the output through and fix the text by hand before shipping it.

Usage: tools/transcribe_audio.py BibleApp/BibleApp/Resources/audio/test.mp3
"""
import argparse, json, pathlib, re, shutil, subprocess, sys, tempfile

DEFAULT_MODEL = pathlib.Path.home() / ".cache" / "whisper" / "ggml-large-v3-turbo.bin"
MAX_CHARS = 80
SENTENCE_END = re.compile(r"(?<=[.!?;…])\s+")


def parse_whisper_json(data):
    """whisper.cpp `-oj` output -> [{"start", "end", "text"}] in seconds."""
    return [{"start": item["offsets"]["from"] / 1000,
             "end": item["offsets"]["to"] / 1000,
             "text": item["text"].strip()}
            for item in data["transcription"]]


def collapse_repeats(segments):
    """Folds a segment that repeats the previous one's text into it --
    whisper sometimes loops on one sentence over music."""
    result = []
    for segment in segments:
        if result and segment["text"] == result[-1]["text"]:
            result[-1] = dict(result[-1], end=segment["end"])
        else:
            result.append(dict(segment))
    return result


def _wrap(text, max_chars):
    """Cuts text into pieces of at most max_chars: at the last comma in the
    second half of the window, else the last space, else a hard cut."""
    pieces = []
    while len(text) > max_chars:
        window = text[:max_chars + 1]
        comma = window.rfind(", ")
        if comma >= max_chars // 2:
            cut = comma + 1
        else:
            cut = window.rfind(" ")
            if cut <= 0:
                cut = max_chars
        pieces.append(text[:cut].strip())
        text = text[cut:].strip()
    if text:
        pieces.append(text)
    return pieces


def split_segment(segment, max_chars=MAX_CHARS):
    """One whisper segment -> lines of at most max_chars, sharing the
    segment's time in proportion to their length."""
    pieces = [piece
              for sentence in SENTENCE_END.split(segment["text"].strip())
              for piece in _wrap(sentence.strip(), max_chars)]
    total = sum(len(piece) for piece in pieces)
    span = segment["end"] - segment["start"]
    lines, start = [], segment["start"]
    for index, piece in enumerate(pieces):
        last = index == len(pieces) - 1
        end = segment["end"] if last else start + span * len(piece) / total
        lines.append({"start": start, "end": end, "text": piece})
        start = end
    return lines


def build_lines(segments, max_chars=MAX_CHARS):
    kept = [segment for segment in segments if segment["text"].strip()]
    return [{"start": round(line["start"], 2), "end": round(line["end"], 2), "text": line["text"]}
            for segment in collapse_repeats(kept)
            for line in split_segment(segment, max_chars)]


def run_whisper(mp3, model, language):
    for tool, formula in (("ffmpeg", "ffmpeg"), ("whisper-cli", "whisper-cpp")):
        if shutil.which(tool) is None:
            sys.exit(f"{tool} not found; install it with: brew install {formula}")
    if not model.exists():
        sys.exit(f"Whisper model not found at {model}; "
                 "download it from https://huggingface.co/ggerganov/whisper.cpp")
    with tempfile.TemporaryDirectory() as tmp:
        wav = pathlib.Path(tmp) / "audio.wav"
        out = pathlib.Path(tmp) / "whisper"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(mp3),
                        "-ar", "16000", "-ac", "1", str(wav)], check=True)
        subprocess.run(["whisper-cli", "-m", str(model), "-f", str(wav), "-l", language,
                        "-oj", "-of", str(out), "-np"], check=True)
        return json.loads(out.with_suffix(".json").read_text(encoding="utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("mp3", type=pathlib.Path)
    parser.add_argument("--model", type=pathlib.Path, default=DEFAULT_MODEL)
    parser.add_argument("--language", default="vi")
    args = parser.parse_args()

    lines = build_lines(parse_whisper_json(run_whisper(args.mp3, args.model, args.language)))
    target = args.mp3.with_name(args.mp3.stem + ".transcript.json")
    target.write_text(json.dumps({"lines": lines}, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    print(f"Wrote {len(lines)} lines to {target}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4:** `/usr/bin/python3 -m unittest tools/test_transcribe_audio.py` → all PASS.
- [ ] **Step 5:** `chmod +x tools/transcribe_audio.py`; commit both files.

---

### Task 2: `Transcript` and `Episode.transcript` (BibleFeedKit)

**Files:** Create `packages/BibleFeedKit/Sources/BibleFeedKit/Transcript.swift`, `packages/BibleFeedKit/Tests/BibleFeedKitTests/TranscriptTests.swift`; modify `Episode.swift`, `EpisodeTests.swift`.

**Produces:** `TranscriptLine { start: Double; text: String }`, `Transcript { lines; init(lines:); static func decode(_ data: Data) throws -> Transcript; func line(at seconds: Double) -> TranscriptLine? }`; `Episode.transcript: String?` with init parameter `transcript: String? = nil`.

- [ ] **Step 1: Failing tests** — `TranscriptTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

private let transcript = Transcript(lines: [
    TranscriptLine(start: 2, text: "Một"),
    TranscriptLine(start: 5, text: "Hai"),
    TranscriptLine(start: 9, text: "Ba"),
])

@Test func noLineBeforeTheFirstStarts() {
    #expect(transcript.line(at: 0) == nil)
    #expect(transcript.line(at: 1.99) == nil)
}

@Test func lineStartsExactlyAtItsStart() {
    #expect(transcript.line(at: 2)?.text == "Một")
    #expect(transcript.line(at: 5)?.text == "Hai")
}

@Test func lineStaysUpUntilTheNextOne() {
    #expect(transcript.line(at: 4.99)?.text == "Một")
    #expect(transcript.line(at: 8)?.text == "Hai")
}

@Test func lastLineStaysUpAfterItStarts() {
    #expect(transcript.line(at: 500)?.text == "Ba")
}

@Test func emptyTranscriptHasNoLine() {
    #expect(Transcript(lines: []).line(at: 3) == nil)
}

@Test func linesAreSortedByStart() {
    let unsorted = Transcript(lines: [TranscriptLine(start: 5, text: "B"), TranscriptLine(start: 1, text: "A")])
    #expect(unsorted.lines.map(\.text) == ["A", "B"])
    #expect(unsorted.line(at: 2)?.text == "A")
}

@Test func decodesToolOutputIgnoringEnd() throws {
    let json = #"{"lines": [{"start": 5.5, "end": 7, "text": "Hai"}, {"start": 1.25, "end": 5.5, "text": "Một"}]}"#
    let decoded = try Transcript.decode(Data(json.utf8))
    #expect(decoded.lines == [TranscriptLine(start: 1.25, text: "Một"), TranscriptLine(start: 5.5, text: "Hai")])
}
```

Append to `EpisodeTests.swift`:

```swift
@Test func catalogReadsOptionalTranscript() throws {
    let json = """
    {"episodes": [{"id": "a", "title": "A", "subtitle": "S", "file": "a.mp3",
                   "durationSeconds": 10, "transcript": "a.transcript.json"},
                  {"id": "b", "title": "B", "subtitle": "S", "file": "b.mp3",
                   "durationSeconds": 10}]}
    """
    let episodes = try EpisodeCatalog.decode(Data(json.utf8))
    #expect(episodes.map(\.transcript) == ["a.transcript.json", nil])
}
```

- [ ] **Step 2:** `cd packages/BibleFeedKit && swift test --filter "TranscriptTests|EpisodeTests"` → FAIL (cannot find `Transcript`, no member `transcript`).

- [ ] **Step 3: Implement** — `Transcript.swift`:

```swift
import Foundation

/// One karaoke line: shown from `start` until the next line begins.
public struct TranscriptLine: Codable, Hashable, Sendable {
    public let start: Double
    public let text: String

    public init(start: Double, text: String) {
        self.start = start
        self.text = text
    }
}

/// Timed lines for an episode, written by `tools/transcribe_audio.py`.
public struct Transcript: Codable, Hashable, Sendable {
    /// Sorted by `start`.
    public let lines: [TranscriptLine]

    public init(lines: [TranscriptLine]) {
        self.lines = lines.sorted { $0.start < $1.start }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(lines: try container.decode([TranscriptLine].self, forKey: .lines))
    }

    public static func decode(_ data: Data) throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: data)
    }

    /// The line being spoken at `seconds`: the last one that has started, so
    /// a line stays up through the pause after it. Nil before the first line.
    public func line(at seconds: Double) -> TranscriptLine? {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start <= seconds {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? nil : lines[low - 1]
    }
}
```

`Episode.swift`: add after `durationSeconds`:

```swift
    /// Bundle file name of the karaoke transcript, if the episode has one.
    public let transcript: String?
```

and change the initializer to

```swift
    public init(id: String, title: String, subtitle: String, file: String,
                durationSeconds: Double, transcript: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.file = file
        self.durationSeconds = durationSeconds
        self.transcript = transcript
    }
```

- [ ] **Step 4:** `cd packages/BibleFeedKit && swift test` → all PASS.
- [ ] **Step 5:** Commit `packages/BibleFeedKit`.

---

### Task 3: Karaoke line in `AudioPlayer`, Now Playing and `PlayerView`

**Files:** Modify `BibleApp/BibleApp/Audio/EpisodeLibrary.swift`, `BibleApp/BibleApp/Audio/AudioPlayer.swift`, `BibleApp/BibleApp/Views/PlayerView.swift`.

**Consumes:** `Transcript`, `Episode.transcript` (Task 2). **Produces:** `EpisodeLibrary.transcript(for:in:)`, `AudioPlayer.currentLine: String?`, `AudioPlayer.hasTranscript: Bool`.

- [ ] **Step 1: `EpisodeLibrary`** — replace `fileURL(for:in:)` with:

```swift
    static func fileURL(for episode: Episode, in bundle: Bundle = .main) -> URL? {
        url(forFile: episode.file, in: bundle)
    }

    /// The episode's karaoke transcript, if it has one.
    static func transcript(for episode: Episode, in bundle: Bundle = .main) -> Transcript? {
        guard let file = episode.transcript else { return nil }
        guard let url = url(forFile: file, in: bundle),
              let transcript = try? Transcript.decode(Data(contentsOf: url)) else {
            assertionFailure("\(file) is missing from the bundle or invalid")
            return nil
        }
        return transcript
    }

    private static func url(forFile file: String, in bundle: Bundle) -> URL? {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext)
    }
```

- [ ] **Step 2: `AudioPlayer`**
  - Add after `private(set) var duration: Double = 0`:
    ```swift
        /// The transcript line being spoken, shown as the Now Playing title.
        private(set) var currentLine: String?
        private(set) var hasTranscript = false
    ```
  - Add with the other ignored properties: `@ObservationIgnored private var transcript: Transcript?`
  - Time observer interval: `CMTime(seconds: 0.25, preferredTimescale: 600)`.
  - In `play(_:)`, after `duration = episode.durationSeconds`:
    ```swift
            transcript = EpisodeLibrary.transcript(for: episode)
            hasTranscript = transcript != nil
    ```
    and after `lastSavedElapsed = start`: `currentLine = transcript?.line(at: start)?.text`
  - In `resume()`, inside the "finished earlier" branch after `elapsed = 0`: `currentLine = transcript?.line(at: 0)?.text`
  - In `seek(to:)`, after `elapsed = target`: `currentLine = transcript?.line(at: target)?.text`
  - In `tick(_:)`, after `elapsed = seconds`: `refreshLine()`
  - Add:
    ```swift
        /// Follows the transcript to `elapsed`, refreshing Now Playing only
        /// when the line changes.
        private func refreshLine() {
            let line = transcript?.line(at: elapsed)?.text
            guard line != currentLine else { return }
            currentLine = line
            updateNowPlaying()
        }
    ```
  - In `updateNowPlaying()`, replace the title and artist entries with:
    ```swift
                // Karaoke: the spoken line takes the title slot, which the
                // expanded Dynamic Island and Lock Screen show most prominently.
                MPMediaItemPropertyTitle: currentLine ?? current.title,
                MPMediaItemPropertyArtist: currentLine == nil ? "Bible App" : current.title,
    ```
- [ ] **Step 3: `PlayerView`** — change artwork `.frame(maxWidth: 280)` to `.frame(maxWidth: 240)`, and insert after the title/subtitle `VStack`:

```swift
            if audio.hasTranscript {
                Text(audio.currentLine ?? "")
                    .font(.system(.title3, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineLimit(3, reservesSpace: true)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: audio.currentLine)
            }
```

- [ ] **Step 4:** Build → success. Commit the three files.

---

### Task 4: Generate the test transcript and verify on device

**Files:** Create `BibleApp/BibleApp/Resources/audio/test.transcript.json`; modify `BibleApp/BibleApp/Resources/audio/episodes.json`.

- [ ] **Step 1:** `/usr/bin/python3 tools/transcribe_audio.py BibleApp/BibleApp/Resources/audio/test.mp3` → "Wrote N lines to …/test.transcript.json".
- [ ] **Step 2:** Read through the output: check timings increase, no line over 80 characters, spot-check spelling around 5:00 against the audio. Report obvious whisper errors to the user rather than guessing fixes.
- [ ] **Step 3:** In `episodes.json` add `"transcript": "test.transcript.json"` to the test episode.
- [ ] **Step 4:** Build, install on the user's iPhone (`xcrun devicectl device install app …`), play: expanded island / Lock Screen title follows the voice; the player sheet shows the same line.
- [ ] **Step 5:** Commit `test.transcript.json` and `episodes.json`.
