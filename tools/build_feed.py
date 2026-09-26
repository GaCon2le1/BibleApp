#!/usr/bin/env python3
"""Join KJV source, selection and contexts into the shipped feed file."""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "BibleApp" / "BibleApp" / "Resources"
OUT_INDEX = OUT_DIR / "feed_index.json"
SHARD_SIZE = 100
CONTENT_VERSION = "2026-09-26.1"

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import load_source_by_index, load_source_by_name

# The KJV source stores psalm superscriptions and Hebrew acrostic letters inside
# the text of verse 1. These are the exact prefixes to remove for display, keyed
# by verse id. Listed explicitly rather than matched by pattern, so the builder
# can never over-strip. Verified against data/source/KJV.json.
KJV_SUPERSCRIPTIONS = {
    "PSA.9.1": "To the chief Musician upon Muth–labben, A Psalm of David. ",
    "PSA.13.1": "To the chief Musician, A Psalm of David. ",
    # The heading runs on with no period at all -- straight into "And he
    # said, " -- so KJV_HEADING_HINT needs its own leading alternative for
    # "To the chief Musician," to catch this one (see below).
    "PSA.18.1": "To the chief Musician, A Psalm of David, the servant of the Lord, who spake unto the Lord the words of this song in the day that the Lord delivered him from the hand of all his enemies, and from the hand of Saul: And he said, ",
    "PSA.19.1": "To the chief Musician, A Psalm of David. ",
    "PSA.22.1": "To the chief Musician upon Aijeleth Shahar, A Psalm of David. ",
    "PSA.23.1": "A Psalm of David. ",
    "PSA.24.1": "A Psalm of David. ",
    "PSA.25.1": "A Psalm of David. ",
    "PSA.27.1": "A Psalm of David. ",
    "PSA.32.1": "A Psalm of David, Maschil. ",
    "PSA.34.1": "A Psalm of David, when he changed his behaviour before Abimelech; who drove him away, and he departed. ",
    "PSA.40.1": "To the chief Musician, A Psalm of David. ",
    "PSA.41.1": "To the chief Musician, A Psalm of David. ",
    "PSA.42.1": "To the chief Musician, Maschil, for the sons of Korah. ",
    "PSA.46.1": "To the chief Musician for the sons of Korah, A Song upon Alamoth. ",
    "PSA.51.1": "To the chief Musician, A Psalm of David, when Nathan the prophet came unto him, after he had gone in to Bath–sheba. ",
    "PSA.57.1": "To the chief Musician, Al–taschith, Michtam of David, when he fled from Saul in the cave. ",
    "PSA.62.1": "To the chief Musician, to Jeduthun, A Psalm of David. ",
    "PSA.63.1": "A Psalm of David, when he was in the wilderness of Judah. ",
    "PSA.69.1": "To the chief Musician upon Shoshannim, A Psalm of David. ",
    "PSA.89.1": "Maschil of Ethan the Ezrahite. ",
    "PSA.90.1": "A Prayer of Moses the man of God. ",
    "PSA.103.1": "A Psalm of David. ",
    "PSA.119.25": "ד DALETH. ",
    "PSA.119.73": "י JOD. ",
    "PSA.119.81": "כ CAPH. ",
    "PSA.119.89": "ל LAMED. ",
    "PSA.119.97": "מ MEM. ",
    "PSA.119.105": "נ NUN. ",
    "PSA.120.1": "A Song of degrees. ",
    "PSA.121.1": "A Song of degrees. ",
    "PSA.122.1": "A Song of degrees of David. ",
    "PSA.127.1": "A Song of degrees for Solomon. ",
    "PSA.130.1": "A Song of degrees. ",
    "PSA.131.1": "A Song of degrees of David. ",
    "PSA.133.1": "A Song of degrees of David. ",
    "PSA.138.1": "A Psalm of David. ",
    "PSA.139.1": "To the chief Musician, A Psalm of David. ",
}

# Some verses carry a trailing musical or liturgical marker rather than a
# leading heading. Same explicit-table treatment, keyed by verse id.
KJV_TRAILING_MARKERS = {
    "HAB.3.19": " To the chief singer on my stringed instruments.",
    "PSA.32.5": " Selah.",
    "PSA.32.7": " Selah.",
    "PSA.46.7": " Selah.",
    "PSA.49.15": " Selah.",
    "PSA.61.4": " Selah.",
    "PSA.62.8": " Selah.",
    "PSA.68.19": " Selah.",
    "PSA.77.9": " Selah.",
    "PSA.85.2": " Selah.",
    # The closing benediction is followed by a scribal subscription noting
    # where and by whom the epistle was written -- not part of the verse.
    "2CO.13.14": " The second epistle to the Corinthians was written from Philippi, a city of Macedonia, by Titus and Lucas.",
    "2PE.3.18": " To him be glory both now and for ever. Amen.",
}

# Any selected verse whose text looks like it carries a heading but is not in
# KJV_SUPERSCRIPTIONS is a build error, not something to strip silently.
KJV_HEADING_HINT = re.compile(
    r"^(?:[^.]{0,120}?(?:Psalm|Song|Maschil|Michtam|Prayer|chief Musician|degrees|Shiggaion)"
    r"[^.]{0,120}?\.\s)|^(?:[^\x00-\x7F][^.]{0,20}\.\s)"
    # PSA.18.1's heading runs straight from "To the chief Musician" through
    # "And he said, " with no period anywhere in between, so the general
    # keyword-then-period alternative above never fires for it -- this
    # leading-only alternative catches it by its distinctive opening words.
    # Matched on the bare phrase (not just the ",\s" comma form) so headings
    # like "To the chief Musician on Neginoth..." and "...upon
    # Shushan-eduth..." are caught too, not only the plain comma form.
    r"|^To the chief Musician\b"
)


BSB_SUPERSCRIPTIONS = {
    "PSA.9.1": "For the choirmaster. To the tune of “The Death of the Son.” A Psalm of David. ",
    "PSA.13.1": "For the choirmaster. A Psalm of David. ",
    "PSA.18.1": "For the choirmaster. Of David the servant of the LORD, who sang this song to the LORD on the day the LORD had delivered him from the hand of all his enemies and from the hand of Saul. He said: ",
    "PSA.19.1": "For the choirmaster. A Psalm of David. ",
    "PSA.22.1": "For the choirmaster. To the tune of “The Doe of the Dawn.” A Psalm of David. ",
    "PSA.23.1": "A Psalm of David. ",
    "PSA.24.1": "A Psalm of David. ",
    "PSA.25.1": "Of David. ",
    "PSA.27.1": "Of David. ",
    "PSA.32.1": "Of David. A Maskil. ",
    "PSA.34.1": "Of David, when he pretended to be insane before Abimelech, so that the king drove him away. ",
    "PSA.40.1": "For the choirmaster. A Psalm of David. ",
    "PSA.41.1": "For the choirmaster. A Psalm of David. ",
    "PSA.42.1": "For the choirmaster. A Maskil of the sons of Korah. ",
    "PSA.46.1": "For the choirmaster. Of the sons of Korah. According to Alamoth. A song. ",
    "PSA.51.1": "For the choirmaster. A Psalm of David. When Nathan the prophet came to him after his adultery with Bathsheba. ",
    "PSA.57.1": "For the choirmaster. To the tune of “Do Not Destroy.” A Miktam of David, when he fled from Saul into the cave. ",
    "PSA.62.1": "For the choirmaster. According to Jeduthun. A Psalm of David. ",
    "PSA.63.1": "A Psalm of David, when he was in the Wilderness of Judah. ",
    "PSA.69.1": "For the choirmaster. To the tune of “Lilies.” Of David. ",
    "PSA.89.1": "A Maskil of Ethan the Ezrahite. ",
    "PSA.90.1": "A prayer of Moses the man of God. ",
    "PSA.103.1": "Of David. ",
    "PSA.120.1": "A song of ascents. ",
    "PSA.121.1": "A song of ascents. ",
    "PSA.122.1": "A song of ascents. Of David. ",
    "PSA.127.1": "A song of ascents. Of Solomon. ",
    "PSA.130.1": "A song of ascents. ",
    "PSA.131.1": "A song of ascents. Of David. ",
    "PSA.133.1": "A song of ascents. Of David. ",
    "PSA.138.1": "Of David. ",
    "PSA.139.1": "For the choirmaster. A Psalm of David. ",
}

BSB_TRAILING_MARKERS = {
    "HAB.3.19": " For the choirmaster. With stringed instruments.",
    "PSA.32.5": " Selah",
    "PSA.32.7": " Selah",
    "PSA.46.7": " Selah",
    "PSA.49.15": " Selah",
    "PSA.61.4": " Selah",
    "PSA.62.8": " Selah",
    "PSA.68.19": " Selah",
    "PSA.77.9": " Selah",
    "PSA.85.2": " Selah",
    "2PE.3.18": " To Him be the glory both now and to the day of eternity. Amen.",
}

def _heading_hint(keywords, max_leading_sentences=3, leading=()):
    """Build a heading-hint regex for one translation: matches (as a
    zero-width lookahead, so `.match()` keeps behaving as a simple truthy
    check for callers) if any of `keywords` appears, case-insensitively,
    within the text's first up to `max_leading_sentences` leading sentences.
    Scanning multiple sentences (not just the first) matters in principle
    because BSB and CPDV headings are sometimes two sentences long, e.g.
    "For the choirmaster. A Psalm of David. " -- the keyword can land in the
    second sentence. In practice every current BSB/CPDV_SUPERSCRIPTIONS
    entry's keyword lands in its first sentence once the keyword list below
    is specific enough (see module history: a bare "psalm"/"prayer"/
    "understanding"/"alleluia" over-matched ordinary prose elsewhere in the
    first 1-3 sentences of unrelated verses, which is why those are
    multi-word phrases below rather than single generic words), so scanning
    stays capped rather than unconditionally always spanning 3 sentences.

    `leading` holds case-sensitive regex fragments that only count when they
    open the text. They cover headings whose only telltale is how they start
    ("Of David, when...", "To David himself.", a bare Hebrew letter name)
    and whose wording would over-match ordinary prose if allowed anywhere
    in the first sentence (e.g. "the throne of David,")."""
    kw = "|".join(re.escape(k) for k in keywords)
    segment = r"[^.]{0,160}?"
    skips = max(0, max_leading_sentences - 1)
    anywhere = rf"(?:{segment}\.\s+){{0,{skips}}}{segment}(?:{kw})"
    if leading:
        anywhere += "|(?-i:" + "|".join(leading) + ")"
    return re.compile(rf"^(?={anywhere})", re.IGNORECASE)


# Hebrew letter names that CPDV prints as a leading "NAME. " marker on each
# verse of an acrostic (Lamentations 1-4). The vendored CPDV spells the
# third and last letters GHIMEL and THAU (not GIMEL/TAU); both spellings
# are kept here since the source is inconsistent across editions.
_HEBREW_LETTER_MARKER = (
    r"(?:ALEPH|BETH|GIMEL|GHIMEL|DALETH|HE|VAU|ZAIN|HETH|TETH|JOD|CAPH|LAMED|MEM|"
    r"NUN|SAMECH|AIN|PHE|SADE|COPH|RES|SIN|TAU|THAU)\.\s")

BSB_HEADING_HINT = _heading_hint(
    ["psalm", "maskil", "choirmaster", "song of ascents", "prayer of", "of david."],
    max_leading_sentences=1, leading=[r"Of David,"])

# Ids whose text trips a translation's heading hint but has been read and
# confirmed to be ordinary verse content (e.g. "prayer offered" containing
# "prayer of", or "sing psalms" in an epistle). Listed explicitly, per
# translation, so a real unlisted heading still fails the build.
BSB_HEADING_HINT_CONFIRMED_CONTENT = {"PSA.102.17", "COL.3.16", "JAS.5.15"}

# CPDV keeps a Psalm's heading as its own separate verse for most psalms,
# but not all -- for these ids the heading is folded into the same verse as
# the content (same as KJV/BSB), so it must be stripped for display just
# like the KJV/BSB tables above. Verified against data/source/CPDV.json.
CPDV_SUPERSCRIPTIONS = {
    "PSA.13.1": "Unto the end. A Psalm of David. ",
    "PSA.23.1": "A Psalm of David. ",
    "PSA.24.1": "For the First Sabbath. A Psalm of David. ",
    "PSA.25.1": "Unto the end. A Psalm of David. ",
    "PSA.27.1": "A Psalm of David, before he was sealed. ",
    "PSA.32.1": "The understanding of David himself. ",
    "PSA.90.1": "A prayer of Moses, the man of God. ",
    "PSA.91.1": "The Praise of a Canticle, of David. ",
    "PSA.96.1": "A Canticle of David himself, when the house was built after the captivity. ",
    "PSA.103.1": "To David himself. ",
    "PSA.107.1": "Alleluia. ",
    "PSA.116.1": "Alleluia. ",
    "PSA.120.1": "A Canticle in steps. ",
    "PSA.121.1": "A Canticle in steps. ",
    "PSA.122.1": "A Canticle in steps. ",
    "PSA.127.1": "A Canticle in steps: of Solomon. ",
    "PSA.130.1": "A Canticle in steps. ",
    "PSA.131.1": "A Canticle in steps: of David. ",
    "PSA.133.1": "A Canticle in steps: of David. ",
    "PSA.137.1": "A Psalm of David: to Jeremiah. ",
    # "Of David himself." reads like ordinary prose (no "of david." keyword
    # match -- "David" is followed by "himself.", not directly by a period)
    # and starts differently from the existing "To David himself." leading
    # case, so CPDV_HEADING_HINT needs its own leading alternative for it
    # too (see below) -- it slipped past every hint until a manual reading
    # pass over every psalm's verse-1/2 CPDV text caught it.
    "PSA.138.1": "Of David himself. ",
    "PSA.139.1": "Unto the end. A Psalm of David. ",
    "PSA.147.1": "Alleluia. ",
    # Lamentations 1-4 are acrostics; CPDV keeps each verse's Hebrew letter
    # name as a leading marker.
    "LAM.1.12": "LAMED. ",
    "LAM.2.19": "COPH. ",
    "LAM.3.8": "GHIMEL. ",
    "LAM.3.17": "VAU. ",
    "LAM.3.18": "VAU. ",
    "LAM.3.22": "HETH. ",
    "LAM.3.23": "HETH. ",
    "LAM.3.24": "HETH. ",
    "LAM.3.26": "TETH. ",
    "LAM.3.31": "CAPH. ",
    "LAM.3.32": "CAPH. ",
    "LAM.3.33": "CAPH. ",
    "LAM.3.40": "NUN. ",
    "LAM.3.55": "COPH. ",
    "LAM.3.57": "COPH. ",
    "LAM.3.58": "RES. ",
}

CPDV_TRAILING_MARKERS = {
    "2PE.3.18": " To him be glory, both now and in the day of eternity. Amen.",
}

CPDV_HEADING_HINT = _heading_hint(
    ["unto the end", "alleluia", "a psalm of", "canticle in steps",
     "of a canticle", "prayer of", "inscription", "the first sabbath",
     "understanding of", "of david."],
    max_leading_sentences=1,
    leading=[r"To David himself\.", r"Of David himself\.",
             r"A Canticle of David", _HEBREW_LETTER_MARKER])

# Ids whose text trips CPDV_HEADING_HINT but has been read and confirmed to
# be ordinary verse content, per the same rule as
# BSB_HEADING_HINT_CONFIRMED_CONTENT above: NEH.1.11 contains "the prayer of
# your servant" (matches the "prayer of" keyword) and REV.19.6 contains
# "Alleluia!" spoken mid-verse by a heavenly multitude (matches the
# "alleluia" keyword) -- neither is a heading.
CPDV_HEADING_HINT_CONFIRMED_CONTENT = {
    "PSA.89.46", "PSA.102.17", "JAS.5.15", "NEH.1.11", "REV.19.6"}


def display_text_for(vid, text, superscriptions, trailing_markers, heading_hint, table_name,
                     confirmed_content=frozenset()):
    """Return the card-facing text: `text` minus any known superscription
    and/or trailing marker for one translation's marker tables. A leading
    superscription strip and a trailing-marker strip on the remaining text
    can both apply to the same verse -- not currently exercised by any
    shipped id (no id appears in both a *_SUPERSCRIPTIONS and its matching
    *_TRAILING_MARKERS table for any translation), but structurally
    supported rather than short-circuited after the prefix strip alone.
    The heading-hint/Selah safety-net checks only apply when NEITHER a
    prefix nor a suffix table entry existed for this id, and the heading
    hint is skipped for ids listed in `confirmed_content`."""
    remaining = text
    had_prefix = False
    prefix = superscriptions.get(vid)
    if prefix is not None:
        if not remaining.startswith(prefix):
            raise SystemExit(f"{vid}: {table_name} prefix does not match source text")
        remaining = remaining[len(prefix):].strip()
        if not remaining:
            raise SystemExit(f"{vid}: stripping the superscription empties {table_name}'s verse")
        had_prefix = True

    had_suffix = False
    suffix = trailing_markers.get(vid)
    if suffix is not None:
        if not remaining.endswith(suffix):
            raise SystemExit(f"{vid}: {table_name} suffix does not match source text")
        remaining = remaining[: -len(suffix)].strip()
        if not remaining:
            raise SystemExit(f"{vid}: stripping the trailing marker empties {table_name}'s verse")
        had_suffix = True

    if had_prefix or had_suffix:
        return remaining

    if vid not in confirmed_content and heading_hint.match(remaining):
        raise SystemExit(
            f"{vid}: text looks like it carries a heading but is not in "
            f"{table_name} — add it explicitly or confirm it is verse content")
    if remaining.rstrip().endswith(("Selah", "Selah.")):
        raise SystemExit(f"{vid}: text ends with 'Selah' but is not in {table_name}")
    return remaining


def kjv_display_text_for(vid, text):
    return display_text_for(vid, text, KJV_SUPERSCRIPTIONS, KJV_TRAILING_MARKERS,
                             KJV_HEADING_HINT, "KJV_SUPERSCRIPTIONS/KJV_TRAILING_MARKERS")


def bsb_display_text_for(vid, text):
    return display_text_for(vid, text, BSB_SUPERSCRIPTIONS, BSB_TRAILING_MARKERS,
                             BSB_HEADING_HINT, "BSB_SUPERSCRIPTIONS/BSB_TRAILING_MARKERS",
                             BSB_HEADING_HINT_CONFIRMED_CONTENT)


def cpdv_display_text_for(vid, text):
    return display_text_for(vid, text, CPDV_SUPERSCRIPTIONS, CPDV_TRAILING_MARKERS,
                             CPDV_HEADING_HINT, "CPDV_SUPERSCRIPTIONS/CPDV_TRAILING_MARKERS",
                             CPDV_HEADING_HINT_CONFIRMED_CONTENT)


def shard_verses(verses, shard_size, schema_version=3, content_version=CONTENT_VERSION):
    """Split `verses` (each a dict with at least id/reference/book/chapter/
    verse/topics/tier/translations/context) into an index doc's "verses"
    entries and the shard file docs to write.

    Returns (index_entries, shard_files) where index_entries is the list of
    feed_index.json entries (each carrying a `shard` field computed as
    `i // shard_size`) and shard_files is a list of (filename, shard_doc)
    pairs in shard order, ready to be written verbatim under OUT_DIR.

    Pulled out of main() so the sharding arithmetic itself -- shard
    assignment, chunk boundaries, remainder handling, and file naming -- can
    be unit tested against a small synthetic verse list without needing the
    real content pipeline. main()'s behavior is unchanged: it just calls
    this and writes the results.
    """
    index_entries = []
    for i, v in enumerate(verses):
        shard = i // shard_size
        index_entries.append({
            "id": v["id"], "reference": v["reference"], "book": v["book"],
            "chapter": v["chapter"], "verse": v["verse"],
            "topics": v["topics"], "tier": v["tier"], "shard": shard,
        })

    shard_count = (len(verses) + shard_size - 1) // shard_size if verses else 0
    shard_files = []
    for shard in range(shard_count):
        chunk = verses[shard * shard_size:(shard + 1) * shard_size]
        shard_content = [{
            "id": v["id"], "translations": v["translations"], "context": v["context"],
        } for v in chunk]
        shard_doc = {"schemaVersion": schema_version, "contentVersion": content_version,
                     "verses": shard_content}
        shard_files.append((f"feed_shard_{shard:04d}.json", shard_doc))

    return index_entries, shard_files


def main():
    meta = json.loads((ROOT / "BibleApp/BibleApp/Resources/bible_books.json").read_text())
    selection = json.loads((ROOT / "data/curation/selection.json").read_text())["selected"]
    contexts = json.loads((ROOT / "data/curation/contexts.json").read_text())

    prot = [b for b in meta["books"] if b["canon"] == "protestant"]
    names = {b["id"]: b["name"] for b in prot}
    text = load_source_by_index(ROOT / "data/source/KJV.json")

    bsb_text = load_source_by_index(ROOT / "data/source/BSB.json")

    cpdv_by_book = load_source_by_name(ROOT / "data/source/CPDV.json")
    cpdv_map = json.loads((ROOT / "data/curation/cpdv_verse_map.json").read_text())

    def cpdv_text_for(vid, book):
        ref = cpdv_map.get(vid)
        if ref is None:
            raise SystemExit(f"{vid}: no entry in cpdv_verse_map.json")
        chapters = cpdv_by_book[book]["chapters"]
        chapter = next((c for c in chapters if c["chapter"] == ref["chapter"]), None)
        if chapter is None:
            raise SystemExit(f"{vid}: no chapter {ref['chapter']} in CPDV {book}")
        verse = next((v for v in chapter["verses"] if v["verse"] == ref["verse"]), None)
        if verse is None:
            raise SystemExit(
                f"{vid}: no verse {ref['verse']} in CPDV {book} chapter {ref['chapter']}")
        return re.sub(r"\s+", " ", verse["text"]).strip()

    verses = []
    for entry in selection:
        book, chapter, verse = entry["id"].split(".")
        chapter, verse = int(chapter), int(verse)
        if entry["id"] not in contexts:
            raise SystemExit(f"missing context for {entry['id']}")
        verse_text = text[(book, chapter, verse)]
        bsb_verse_text = bsb_text[(book, chapter, verse)]
        cpdv_verse_text = cpdv_text_for(entry["id"], book)
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
                "CPDV": {
                    "text": cpdv_verse_text,
                    "displayText": cpdv_display_text_for(entry["id"], cpdv_verse_text),
                },
            },
            "context": contexts[entry["id"]],
            "topics": entry["topics"],
            "tier": entry["tier"],
        })

    for old_shard in OUT_DIR.glob("feed_shard_*.json"):
        old_shard.unlink()

    index_entries, shard_files = shard_verses(verses, SHARD_SIZE)

    index_doc = {"schemaVersion": 3, "contentVersion": CONTENT_VERSION, "verses": index_entries}
    OUT_INDEX.write_text(json.dumps(index_doc, indent=1, ensure_ascii=False))

    for filename, shard_doc in shard_files:
        (OUT_DIR / filename).write_text(json.dumps(shard_doc, indent=1, ensure_ascii=False))

    print(f"wrote {len(index_entries)} verses to {OUT_INDEX.relative_to(ROOT)} "
          f"across {len(shard_files)} shard file(s)")


if __name__ == "__main__":
    main()
