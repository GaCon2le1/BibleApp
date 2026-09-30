# Audio Karaoke Text on Now Playing — Design

Date: 2026-09-30
Status: Approved

## Problem

While an episode plays, the Dynamic Island and Lock Screen only show the
episode title. We want the sentence currently being spoken to appear there,
karaoke style, and in the in-app player.

## Decisions

| Question | Decision |
|---|---|
| Mechanism | Rewrite the system Now Playing title as the current line (option A). No custom Live Activity, so the island never splits in two |
| Where text shows | Expanded Dynamic Island and Lock Screen (the compact island has no room for text; it keeps artwork + waveform), plus the in-app `PlayerView` |
| Transcript source | Generated offline with whisper.cpp by a repo script; the output JSON is hand-editable and bundled next to the mp3 |
| Language / model | Episodes may be English or Vietnamese, so the language is auto-detected. `ggml-large-v3-turbo.bin` (~1.6 GB, kept in `~/.cache/whisper/`, never committed); `small.en` hallucinated on Vietnamese and multilingual `small` misspelled many Vietnamese words |
| Line size | At most 80 characters, split at sentence punctuation first |
| Granularity | One line at a time; no per-word highlighting |

## Architecture

### `tools/transcribe_audio.py` (Python 3.9, stdlib only, `unittest`)

- `parse_whisper_json(data) -> [{"start", "end", "text"}]` — reads
  whisper.cpp `-oj` output (`transcription[].offsets.from/to` in ms).
- `split_segment(segment, max_chars=80) -> [line]` — splits at `. ! ? ;`,
  then splits pieces longer than `max_chars` at the last comma, else the
  last space, within the limit. Time is shared out in proportion to
  character count; the first line starts at the segment start and the last
  ends at the segment end.
- `build_lines(segments, max_chars=80)` — strips whitespace, drops empty
  segments, applies `split_segment`, rounds times to 2 decimals.
- `collapse_repeats(segments)` — drops a segment whose text equals the
  previous one (whisper's repetition loop over music), extending the
  previous segment's `end` instead.
- `main`: `transcribe_audio.py <mp3> [--model PATH] [--language auto]` →
  converts to 16 kHz mono WAV with ffmpeg in a temp dir, runs
  `whisper-cli -l <language> -oj`, writes
  `<same folder>/<basename>.transcript.json` as
  `{"lines": [{"start", "end", "text"}]}` (UTF-8, no `\u` escapes,
  indented). Default model `~/.cache/whisper/ggml-large-v3-turbo.bin`,
  default language `auto`.

### `BibleFeedKit` (TDD)

- `TranscriptLine: Codable, Hashable, Sendable` — `start: Double`,
  `text: String` (`end` in the JSON is ignored by the app; it is there for
  hand editing).
- `Transcript` — `lines` sorted by `start`; `static func decode(_:)`;
  `line(at seconds:) -> TranscriptLine?` returns the last line whose `start`
  is ≤ `seconds` (lines stay up through pauses), nil before the first line.
- `Episode` gains `transcript: String?` (bundle file name). Old
  `episodes.json` without the key still decodes.

### App

- `EpisodeLibrary.transcript(for:) -> Transcript?` — loads the named file
  from the bundle; a missing or invalid file is an `assertionFailure` and
  nil.
- `AudioPlayer`
  - `currentLine: String?` and `hasTranscript: Bool` (observable).
  - Time observer every 0.25 s. The line is recomputed on every tick and on
    seek; Now Playing is refreshed only when the line changes.
  - Now Playing: when a line is showing, title = line, artist = episode
    title; otherwise title = episode title, artist = "Bible App".
- `PlayerView` — when the episode has a transcript, the current line in
  serif `.title3`, centered, `lineLimit(3, reservesSpace: true)`, with an
  opacity transition between lines.
- `episodes.json` — the test episode gets
  `"transcript": "test.transcript.json"`.

## Error handling

- Transcript file missing or invalid → playback works as before, with no
  karaoke text.
- The script exits non-zero with a clear message if ffmpeg, `whisper-cli`
  or the model is missing.

## Out of scope

Per-word highlighting, a scrolling full transcript, translations, a custom
Live Activity.

## Testing

- Python unit tests for `parse_whisper_json`, `split_segment`, `build_lines`.
- Swift tests for `Transcript.line(at:)` (before first, exact start,
  between lines, after last, empty transcript, unsorted input) and
  `Episode` decoding with and without `transcript`.
- Real iPhone: expanded island and Lock Screen change lines in step with
  the voice; the in-app player shows the same line.
