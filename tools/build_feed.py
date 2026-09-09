#!/usr/bin/env python3
"""Join KJV source, selection and contexts into the shipped feed file."""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "BibleApp" / "BibleApp" / "Resources" / "feed_verses.json"
CONTENT_VERSION = "2026-09-09.1"

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import load_source_by_index

# The KJV source stores psalm superscriptions and Hebrew acrostic letters inside
# the text of verse 1. These are the exact prefixes to remove for display, keyed
# by verse id. Listed explicitly rather than matched by pattern, so the builder
# can never over-strip. Verified against data/source/KJV.json.
KJV_SUPERSCRIPTIONS = {
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
KJV_TRAILING_MARKERS = {
    "HAB.3.19": " To the chief singer on my stringed instruments.",
    "PSA.62.8": " Selah.",
    "PSA.77.9": " Selah.",
    "2PE.3.18": " To him be glory both now and for ever. Amen.",
}

# Any selected verse whose text looks like it carries a heading but is not in
# KJV_SUPERSCRIPTIONS is a build error, not something to strip silently.
KJV_HEADING_HINT = re.compile(
    r"^(?:[^.]{0,120}?(?:Psalm|Song|Maschil|Michtam|Prayer|chief Musician|degrees)"
    r"[^.]{0,120}?\.\s)|^(?:[^\x00-\x7F][^.]{0,20}\.\s)"
)


BSB_SUPERSCRIPTIONS = {
    "PSA.19.1": "For the choirmaster. A Psalm of David. ",
    "PSA.22.1": "For the choirmaster. To the tune of “The Doe of the Dawn.” A Psalm of David. ",
    "PSA.23.1": "A Psalm of David. ",
    "PSA.24.1": "A Psalm of David. ",
    "PSA.27.1": "Of David. ",
    "PSA.32.1": "Of David. A Maskil. ",
    "PSA.42.1": "For the choirmaster. A Maskil of the sons of Korah. ",
    "PSA.46.1": "For the choirmaster. Of the sons of Korah. According to Alamoth. A song. ",
    "PSA.89.1": "A Maskil of Ethan the Ezrahite. ",
    "PSA.90.1": "A prayer of Moses the man of God. ",
    "PSA.121.1": "A song of ascents. ",
    "PSA.127.1": "A song of ascents. Of Solomon. ",
    "PSA.130.1": "A song of ascents. ",
    "PSA.133.1": "A song of ascents. Of David. ",
}

BSB_TRAILING_MARKERS = {
    "HAB.3.19": " For the choirmaster. With stringed instruments.",
    "PSA.62.8": " Selah",
    "PSA.77.9": " Selah",
    "2PE.3.18": " To Him be the glory both now and to the day of eternity. Amen.",
}

BSB_HEADING_HINT = re.compile(
    r"^(?:[^.]{0,140}?(?:Psalm|Maskil|Choirmaster|song of ascents|prayer of)"
    r"[^.]{0,140}?\.\s)"
)


def display_text_for(vid, text, superscriptions, trailing_markers, heading_hint, table_name):
    """Return the card-facing text: `text` minus any known superscription or
    trailing marker for one translation's marker tables."""
    prefix = superscriptions.get(vid)
    if prefix is not None:
        if not text.startswith(prefix):
            raise SystemExit(f"{vid}: {table_name} prefix does not match source text")
        stripped = text[len(prefix):].strip()
        if not stripped:
            raise SystemExit(f"{vid}: stripping the superscription empties {table_name}'s verse")
        return stripped
    suffix = trailing_markers.get(vid)
    if suffix is not None:
        if not text.endswith(suffix):
            raise SystemExit(f"{vid}: {table_name} suffix does not match source text")
        stripped = text[: -len(suffix)].strip()
        if not stripped:
            raise SystemExit(f"{vid}: stripping the trailing marker empties {table_name}'s verse")
        return stripped
    if heading_hint.match(text):
        raise SystemExit(
            f"{vid}: text looks like it carries a heading but is not in "
            f"{table_name} — add it explicitly or confirm it is verse content")
    if text.rstrip().endswith(("Selah", "Selah.")):
        raise SystemExit(f"{vid}: text ends with 'Selah' but is not in {table_name}")
    return text


def kjv_display_text_for(vid, text):
    return display_text_for(vid, text, KJV_SUPERSCRIPTIONS, KJV_TRAILING_MARKERS,
                             KJV_HEADING_HINT, "KJV_SUPERSCRIPTIONS/KJV_TRAILING_MARKERS")


def bsb_display_text_for(vid, text):
    return display_text_for(vid, text, BSB_SUPERSCRIPTIONS, BSB_TRAILING_MARKERS,
                             BSB_HEADING_HINT, "BSB_SUPERSCRIPTIONS/BSB_TRAILING_MARKERS")


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

    bsb_text = load_source_by_index(ROOT / "data/source/BSB.json")

    verses = []
    for entry in selection:
        book, chapter, verse = entry["id"].split(".")
        chapter, verse = int(chapter), int(verse)
        if entry["id"] not in contexts:
            raise SystemExit(f"missing context for {entry['id']}")
        verse_text = text[(book, chapter, verse)]
        bsb_verse_text = bsb_text[(book, chapter, verse)]
        verses.append({
            "id": entry["id"],
            "reference": f"{names[book]} {chapter}:{verse}",
            "book": book, "chapter": chapter, "verse": verse,
            "translations": {
                "KJV": {
                    "text": verse_text,
                    "displayText": kjv_display_text_for(entry["id"], verse_text),
                },
                "BSB": {
                    "text": bsb_verse_text,
                    "displayText": bsb_display_text_for(entry["id"], bsb_verse_text),
                },
            },
            "context": contexts[entry["id"]],
            "topics": entry["topics"],
            "tier": entry["tier"],
        })

    doc = {"schemaVersion": 1, "contentVersion": CONTENT_VERSION, "verses": verses}
    OUT.write_text(json.dumps(doc, indent=1, ensure_ascii=False))
    print(f"wrote {len(verses)} verses to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
