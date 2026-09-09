#!/usr/bin/env python3
"""Validate a built feed_verses.json against the vendored translation sources."""
import json, pathlib, sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import SourceDataError, load_source_by_index

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "source" / "KJV.json"

TOPICS = {"anxiety", "hope", "love", "forgiveness", "strength", "guidance",
          "peace", "doubt", "purpose", "gratitude", "grief", "worth"}
CONTEXT_MIN, CONTEXT_MAX = 60, 220
# Grows to {"KJV", "BSB", "CPDV"} as Tasks 5 and 11 add those translations.
TRANSLATIONS = {"KJV"}


def _kjv_index():
    return load_source_by_index(SOURCE)


def validate_feed(path):
    errors = []
    try:
        doc = json.loads(pathlib.Path(path).read_text())
    except OSError as e:
        errors.append(f"failed to read feed file {path}: {e}")
        return errors
    except json.JSONDecodeError as e:
        errors.append(f"feed file {path} contains invalid JSON: {e}")
        return errors

    if not isinstance(doc, dict):
        errors.append(
            "feed file must contain a JSON object with a top-level "
            f"\"verses\" array, got {type(doc).__name__}")
        return errors

    try:
        index = _kjv_index()
    except SourceDataError as e:
        errors.append(f"source data error: {e}")
        return errors

    seen_ids = set()

    for entry in doc.get("verses", []):
        vid = entry.get("id", "<missing id>")

        if vid in seen_ids:
            errors.append(f"{vid}: duplicate id")
        seen_ids.add(vid)

        key = (entry.get("book"), entry.get("chapter"), entry.get("verse"))
        translations = entry.get("translations")
        if not isinstance(translations, dict) or not translations:
            errors.append(f"{vid}: translations is missing or empty")
            translations = {}

        for code in TRANSLATIONS:
            t = translations.get(code)
            if t is None:
                errors.append(f"{vid}: missing translation {code}")
                continue
            if not isinstance(t, dict):
                errors.append(f"{vid}: translation {code} is not an object")
                continue
            text = t.get("text")
            display = t.get("displayText")
            if code == "KJV":
                if key not in index:
                    errors.append(f"{vid}: no such verse in KJV source")
                elif text != index[key]:
                    errors.append(f"{vid}: KJV text does not match KJV source")
            if display is None:
                errors.append(f"{vid}: {code} displayText is missing")
            elif not isinstance(display, str) or not display.strip():
                errors.append(f"{vid}: {code} displayText is empty")
            elif not isinstance(text, str) or display not in text:
                # Substring, not suffix: most strips remove a leading superscription,
                # but some verses remove a trailing colophon instead.
                errors.append(f"{vid}: {code} displayText is not part of {code} text")

        unknown_codes = set(translations) - TRANSLATIONS
        if unknown_codes:
            errors.append(f"{vid}: unknown translation code(s) {sorted(unknown_codes)}")

        if vid != f"{key[0]}.{key[1]}.{key[2]}":
            errors.append(f"{vid}: id does not match book/chapter/verse fields")

        unknown = set(entry.get("topics", [])) - TOPICS
        if unknown:
            errors.append(f"{vid}: unknown topic {sorted(unknown)}")
        if not entry.get("topics"):
            errors.append(f"{vid}: topics must not be empty")

        if entry.get("tier") not in (1, 2, 3):
            errors.append(f"{vid}: tier must be 1, 2 or 3")

        ctx = entry.get("context", "")
        if not CONTEXT_MIN <= len(ctx) <= CONTEXT_MAX:
            errors.append(
                f"{vid}: context length {len(ctx)} outside {CONTEXT_MIN}-{CONTEXT_MAX}")

    return errors


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate_feed.py <feed.json>")
    errors = validate_feed(sys.argv[1])
    for e in errors:
        print(e)
    print(f"{len(errors)} error(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
