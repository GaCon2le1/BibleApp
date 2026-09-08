#!/usr/bin/env python3
"""Join KJV source, selection and contexts into the shipped feed file."""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "BibleApp" / "BibleApp" / "Resources" / "feed_verses.json"
CONTENT_VERSION = "2026-09-07.1"

# The KJV source stores psalm superscriptions and Hebrew acrostic letters inside
# the text of verse 1. These are the exact prefixes to remove for display, keyed
# by verse id. Listed explicitly rather than matched by pattern, so the builder
# can never over-strip. Verified against data/source/KJV.json.
SUPERSCRIPTIONS = {
    "PSA.19.1": "To the chief Musician, A Psalm of David. ",
    "PSA.22.1": "To the chief Musician upon Aijeleth Shahar, A Psalm of David. ",
    "PSA.23.1": "A Psalm of David. ",
    "PSA.24.1": "A Psalm of David. ",
    "PSA.27.1": "A Psalm of David. ",
    "PSA.32.1": "A Psalm of David, Maschil. ",
    "PSA.42.1": "To the chief Musician, Maschil, for the sons of Korah. ",
    "PSA.46.1": "To the chief Musician for the sons of Korah, A Song upon Alamoth. ",
    "PSA.89.1": "Maschil of Ethan the Ezrahite. ",
    "PSA.90.1": "A Prayer of Moses the man of God. ",
    "PSA.119.105": "נ NUN. ",
    "PSA.121.1": "A Song of degrees. ",
    "PSA.127.1": "A Song of degrees for Solomon. ",
    "PSA.130.1": "A Song of degrees. ",
    "PSA.133.1": "A Song of degrees of David. ",
}

# Some verses carry a trailing musical or liturgical marker rather than a
# leading heading. Same explicit-table treatment, keyed by verse id.
TRAILING_MARKERS = {
    "HAB.3.19": " To the chief singer on my stringed instruments.",
    "PSA.62.8": " Selah.",
    "PSA.77.9": " Selah.",
    "2PE.3.18": " To him be glory both now and for ever. Amen.",
}

# Any selected verse whose text looks like it carries a heading but is not in
# SUPERSCRIPTIONS is a build error, not something to strip silently.
HEADING_HINT = re.compile(
    r"^(?:[^.]{0,120}?(?:Psalm|Song|Maschil|Michtam|Prayer|chief Musician|degrees)"
    r"[^.]{0,120}?\.\s)|^(?:[^\x00-\x7F][^.]{0,20}\.\s)"
)


def display_text_for(vid, text):
    """Return the card-facing text: `text` minus any known superscription."""
    prefix = SUPERSCRIPTIONS.get(vid)
    if prefix is not None:
        if not text.startswith(prefix):
            raise SystemExit(
                f"{vid}: SUPERSCRIPTIONS prefix does not match source text")
        stripped = text[len(prefix):].strip()
        if not stripped:
            raise SystemExit(f"{vid}: stripping the superscription empties the verse")
        return stripped
    if HEADING_HINT.match(text):
        raise SystemExit(
            f"{vid}: text looks like it carries a heading but is not in "
            f"SUPERSCRIPTIONS — add it explicitly or confirm it is verse content")
    suffix = TRAILING_MARKERS.get(vid)
    if suffix is not None:
        if not text.endswith(suffix):
            raise SystemExit(
                f"{vid}: TRAILING_MARKERS suffix does not match source text")
        return text[:-len(suffix)].strip()
    # "Selah" is a liturgical marker, never verse content. Catch any that were
    # not listed rather than shipping one onto a card.
    if text.rstrip().endswith("Selah."):
        raise SystemExit(
            f"{vid}: text ends with 'Selah.' but is not in TRAILING_MARKERS")
    return text


def main():
    kjv = json.loads((ROOT / "data/source/KJV.json").read_text())
    meta = json.loads((ROOT / "BibleApp/BibleApp/Resources/bible_books.json").read_text())
    selection = json.loads((ROOT / "data/curation/selection.json").read_text())["selected"]
    contexts = json.loads((ROOT / "data/curation/contexts.json").read_text())

    prot = [b for b in meta["books"] if b["canon"] == "protestant"]
    names = {b["id"]: b["name"] for b in prot}
    text = {}
    for i, book in enumerate(prot):
        for ch in kjv["books"][i]["chapters"]:
            for v in ch["verses"]:
                text[(book["id"], int(ch["chapter"]), int(v["verse"]))] = \
                    re.sub(r"\s+", " ", v["text"]).strip()

    verses = []
    for entry in selection:
        book, chapter, verse = entry["id"].split(".")
        chapter, verse = int(chapter), int(verse)
        if entry["id"] not in contexts:
            raise SystemExit(f"missing context for {entry['id']}")
        verse_text = text[(book, chapter, verse)]
        verses.append({
            "id": entry["id"],
            "reference": f"{names[book]} {chapter}:{verse}",
            "book": book, "chapter": chapter, "verse": verse,
            "text": verse_text,
            "displayText": display_text_for(entry["id"], verse_text),
            "context": contexts[entry["id"]],
            "topics": entry["topics"],
            "tier": entry["tier"],
        })

    doc = {"schemaVersion": 1, "contentVersion": CONTENT_VERSION,
           "translation": "KJV", "verses": verses}
    OUT.write_text(json.dumps(doc, indent=1, ensure_ascii=False))
    print(f"wrote {len(verses)} verses to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
