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
