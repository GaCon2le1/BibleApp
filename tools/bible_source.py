"""Shared helpers for reading the vendored Bible source JSON files (KJV,
BSB, CPDV, ...) and pairing their books against the 66-book Protestant
canon in BibleApp/BibleApp/Resources/bible_books.json.

Two pairing strategies exist because the sources are not laid out the same
way. KJV and BSB list exactly the 66 Protestant books, in Protestant order,
so they pair by array index. CPDV lists 78 books with the deuterocanon
interleaved through the Old Testament in traditional Catholic order, so it
must pair by (normalized) book name instead -- see load_source_by_name.
"""
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
BOOKS = ROOT / "BibleApp" / "BibleApp" / "Resources" / "bible_books.json"

# bible_books.json uses Arabic-numeral prefixes ("1 Samuel", "2 Kings") and a
# bare "Revelation"; several vendored sources use Roman-numeral prefixes
# ("I Samuel", "II Kings") and "Revelation of John". Both name a book title
# -> a normalized form so the two conventions compare equal without masking
# a genuine mismatch (e.g. a transposed book pair).
_ROMAN_PREFIX = {"I": "1", "II": "2", "III": "3"}


def normalize_book_name(name):
    name = (name or "").strip()
    parts = name.split(" ", 1)
    if len(parts) == 2 and parts[0] in _ROMAN_PREFIX:
        name = f"{_ROMAN_PREFIX[parts[0]]} {parts[1]}"
    if name.endswith(" of John"):
        name = name[: -len(" of John")]
    return name


class SourceDataError(Exception):
    """Raised when a vendored source file or bible_books.json fails a
    structural sanity check (missing file, malformed JSON, book count,
    chapter count, or book identity). Callers must catch this and report it
    as a validation error rather than let it propagate."""


def load_protestant_books():
    """Return the 66 canon == 'protestant' entries from bible_books.json,
    in their existing order (Genesis..Revelation)."""
    try:
        meta = json.loads(BOOKS.read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise SourceDataError(f"failed to read or parse {BOOKS}: {e}")
    return [b for b in meta["books"] if b["canon"] == "protestant"]


def load_source_by_index(path):
    """Load a source whose `books` array is already index-aligned with the
    66 protestant books (KJV, BSB). Returns
    {(book_id, chapter, verse): normalized_text}."""
    prot = load_protestant_books()
    try:
        data = json.loads(pathlib.Path(path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise SourceDataError(f"failed to read or parse {path}: {e}")

    if len(prot) != len(data["books"]):
        raise SourceDataError(
            f"book count mismatch: bible_books.json has {len(prot)} "
            f"protestant books, {path} has {len(data['books'])} books")

    index = {}
    for i, book in enumerate(prot):
        src = data["books"][i]
        if len(src["chapters"]) != book["chapters"]:
            raise SourceDataError(
                f"{path}: source/book chapter-count mismatch at {book['id']}")
        if normalize_book_name(src.get("name")) != normalize_book_name(book["name"]):
            raise SourceDataError(
                f"{path}: source/book identity mismatch at position {i} "
                f"(id {book['id']}): bible_books.json name {book['name']!r} "
                f"vs source name {src.get('name')!r}")
        for ch in src["chapters"]:
            for v in ch["verses"]:
                key = (book["id"], int(ch["chapter"]), int(v["verse"]))
                index[key] = re.sub(r"\s+", " ", v["text"]).strip()
    return index


def load_source_by_name(path):
    """Load a source whose books must be paired by normalized name rather
    than array index (CPDV, whose deuterocanon is interleaved through the
    Old Testament). Returns {book_id: raw_book_dict}, keyed by the
    protestant book id -- callers resolve chapter/verse themselves, since a
    name-paired source's own chapter/verse numbers do not always equal the
    protestant ones (see tools/cpdv_psalm_offsets.py for Psalms)."""
    prot = load_protestant_books()
    try:
        data = json.loads(pathlib.Path(path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise SourceDataError(f"failed to read or parse {path}: {e}")

    by_name = {normalize_book_name(b.get("name")): b for b in data["books"]}
    out = {}
    for book in prot:
        src = by_name.get(normalize_book_name(book["name"]))
        if src is None:
            raise SourceDataError(
                f"{path}: no book matching {book['name']!r} (id {book['id']})")
        out[book["id"]] = src
    return out
