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
    parser.add_argument("--language", default="auto",
                        help="whisper language code, or auto to detect it")
    args = parser.parse_args()

    lines = build_lines(parse_whisper_json(run_whisper(args.mp3, args.model, args.language)))
    target = args.mp3.with_name(args.mp3.stem + ".transcript.json")
    target.write_text(json.dumps({"lines": lines}, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    print(f"Wrote {len(lines)} lines to {target}")


if __name__ == "__main__":
    main()
