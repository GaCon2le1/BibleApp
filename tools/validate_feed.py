#!/usr/bin/env python3
"""Validate a built feed_verses.json against the vendored KJV source."""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "source" / "KJV.json"
BOOKS = ROOT / "BibleApp" / "BibleApp" / "Resources" / "bible_books.json"

TOPICS = {"anxiety", "hope", "love", "forgiveness", "strength", "guidance",
          "peace", "doubt", "purpose", "gratitude", "grief", "worth"}
CONTEXT_MIN, CONTEXT_MAX = 60, 220

# bible_books.json uses Arabic-numeral prefixes ("1 Samuel", "2 Kings") and a
# bare "Revelation"; KJV.json uses Roman-numeral prefixes ("I Samuel",
# "II Kings") and "Revelation of John". Both name a book title -> a
# normalized form so the two conventions compare equal without masking a
# genuine mismatch (e.g. a transposed book pair).
_ROMAN_PREFIX = {"I": "1", "II": "2", "III": "3"}


def _normalize_book_name(name):
    name = (name or "").strip()
    parts = name.split(" ", 1)
    if len(parts) == 2 and parts[0] in _ROMAN_PREFIX:
        name = f"{_ROMAN_PREFIX[parts[0]]} {parts[1]}"
    if name.endswith(" of John"):
        name = name[: -len(" of John")]
    return name


class SourceDataError(Exception):
    """Raised when KJV.json / bible_books.json fail a structural sanity
    check (book count, chapter count, or book identity). Callers must catch
    this and report it as a validation error rather than let it propagate,
    per the validate_feed(path) -> list[str] contract."""


def _kjv_index():
    """Map (bookId, chapter, verse) -> verse text, using canonical book order."""
    try:
        kjv = json.loads(SOURCE.read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise SourceDataError(f"failed to read or parse {SOURCE}: {e}")
    try:
        meta = json.loads(BOOKS.read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise SourceDataError(f"failed to read or parse {BOOKS}: {e}")
    prot = [b for b in meta["books"] if b["canon"] == "protestant"]

    if len(prot) != len(kjv["books"]):
        raise SourceDataError(
            f"book count mismatch: bible_books.json has {len(prot)} "
            f"protestant books, KJV.json has {len(kjv['books'])} books")

    index = {}
    for i, book in enumerate(prot):
        src = kjv["books"][i]
        if len(src["chapters"]) != book["chapters"]:
            raise SourceDataError(f"source/book chapter-count mismatch at {book['id']}")
        if _normalize_book_name(src.get("name")) != _normalize_book_name(book["name"]):
            raise SourceDataError(
                f"source/book identity mismatch at position {i} (id {book['id']}): "
                f"bible_books.json name {book['name']!r} vs KJV.json name {src.get('name')!r}")
        for ch in src["chapters"]:
            for v in ch["verses"]:
                key = (book["id"], int(ch["chapter"]), int(v["verse"]))
                index[key] = re.sub(r"\s+", " ", v["text"]).strip()
    return index


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
