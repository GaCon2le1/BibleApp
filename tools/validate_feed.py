#!/usr/bin/env python3
"""Validate a built feed_verses.json against the vendored KJV source."""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "source" / "KJV.json"
BOOKS = ROOT / "BibleApp" / "BibleApp" / "Resources" / "bible_books.json"

TOPICS = {"anxiety", "hope", "love", "forgiveness", "strength", "guidance",
          "peace", "doubt", "purpose", "gratitude", "grief", "worth"}
CONTEXT_MIN, CONTEXT_MAX = 60, 220


def _kjv_index():
    """Map (bookId, chapter, verse) -> verse text, using canonical book order."""
    kjv = json.loads(SOURCE.read_text())
    meta = json.loads(BOOKS.read_text())
    prot = [b for b in meta["books"] if b["canon"] == "protestant"]
    index = {}
    for i, book in enumerate(prot):
        src = kjv["books"][i]
        if len(src["chapters"]) != book["chapters"]:
            raise SystemExit(f"source/book mismatch at {book['id']}")
        for ch in src["chapters"]:
            for v in ch["verses"]:
                key = (book["id"], int(ch["chapter"]), int(v["verse"]))
                index[key] = re.sub(r"\s+", " ", v["text"]).strip()
    return index


def validate_feed(path):
    errors = []
    doc = json.loads(pathlib.Path(path).read_text())
    index = _kjv_index()
    seen_ids = set()

    for entry in doc.get("verses", []):
        vid = entry.get("id", "<missing id>")

        if vid in seen_ids:
            errors.append(f"{vid}: duplicate id")
        seen_ids.add(vid)

        key = (entry.get("book"), entry.get("chapter"), entry.get("verse"))
        if key not in index:
            errors.append(f"{vid}: no such verse in KJV source")
        elif entry.get("text") != index[key]:
            errors.append(f"{vid}: text does not match KJV source")

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
