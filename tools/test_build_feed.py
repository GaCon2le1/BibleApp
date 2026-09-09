import json, pathlib, re, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from build_feed import (kjv_display_text_for, KJV_SUPERSCRIPTIONS,
                         KJV_TRAILING_MARKERS, KJV_HEADING_HINT)

REPO = pathlib.Path(__file__).resolve().parents[1]
KJV_SOURCE = REPO / "data" / "source" / "KJV.json"
BIBLE_BOOKS = REPO / "BibleApp" / "BibleApp" / "Resources" / "bible_books.json"


def _load_kjv_text():
    """Map "BOOK.CHAPTER.VERSE" id -> the real, whitespace-collapsed verse
    text from the vendored KJV source, using the same book-index pairing and
    whitespace normalization build_feed.py itself applies (see
    ShippedSelectionIdsResolveTests in test_check_selection.py for the
    precedent this follows)."""
    books_meta = json.loads(BIBLE_BOOKS.read_text())["books"]
    protestant = [b for b in books_meta if b["canon"] == "protestant"]
    kjv_books = json.loads(KJV_SOURCE.read_text())["books"]
    assert len(protestant) == len(kjv_books) == 66, (
        "expected 66 protestant-canon books lined up with 66 KJV books, "
        "got %d and %d" % (len(protestant), len(kjv_books)))

    text = {}
    for meta, book in zip(protestant, kjv_books):
        for chapter in book["chapters"]:
            for verse in chapter["verses"]:
                vid = "%s.%d.%d" % (meta["id"], chapter["chapter"], verse["verse"])
                text[vid] = re.sub(r"\s+", " ", verse["text"]).strip()
    return text


class LeadingSuperscriptionTests(unittest.TestCase):
    def test_strips_known_leading_superscription(self):
        # PSA.23.1 is a real KJV_SUPERSCRIPTIONS entry: "A Psalm of David. The
        # Lord is my shepherd; I shall not want."
        prefix = KJV_SUPERSCRIPTIONS["PSA.23.1"]
        text = prefix + "The Lord is my shepherd; I shall not want."
        self.assertEqual(
            kjv_display_text_for("PSA.23.1", text),
            "The Lord is my shepherd; I shall not want.")

    def test_strips_all_known_leading_superscriptions_against_real_text(self):
        kjv_text = _load_kjv_text()
        for vid, prefix in KJV_SUPERSCRIPTIONS.items():
            real_text = kjv_text[vid]
            self.assertTrue(
                real_text.startswith(prefix),
                f"{vid}: real KJV text does not start with recorded prefix "
                f"{prefix!r}; real text is {real_text!r}")
            stripped = kjv_display_text_for(vid, real_text)
            self.assertEqual(stripped, real_text[len(prefix):].strip())
            self.assertFalse(stripped.startswith(prefix))


class TrailingMarkerTests(unittest.TestCase):
    def test_strips_known_trailing_marker(self):
        # HAB.3.19 is a real KJV_TRAILING_MARKERS entry.
        suffix = KJV_TRAILING_MARKERS["HAB.3.19"]
        text = "The Lord God is my strength, and he will make my feet like hinds' feet." + suffix
        self.assertEqual(
            kjv_display_text_for("HAB.3.19", text),
            "The Lord God is my strength, and he will make my feet like hinds' feet.")

    def test_strips_all_known_trailing_markers_against_real_text(self):
        kjv_text = _load_kjv_text()
        for vid, suffix in KJV_TRAILING_MARKERS.items():
            real_text = kjv_text[vid]
            self.assertTrue(
                real_text.endswith(suffix),
                f"{vid}: real KJV text does not end with recorded suffix "
                f"{suffix!r}; real text is {real_text!r}")
            stripped = kjv_display_text_for(vid, real_text)
            self.assertEqual(stripped, real_text[: -len(suffix)].strip())
            self.assertFalse(stripped.endswith(suffix.strip()))


class PassThroughTests(unittest.TestCase):
    def test_ordinary_verse_returns_text_unchanged(self):
        # JHN.3.16 carries no superscription or trailing marker.
        text = "For God so loved the world, that he gave his only begotten Son."
        self.assertEqual(kjv_display_text_for("JHN.3.16", text), text)


class HeadingHintGuardTests(unittest.TestCase):
    def test_unlisted_heading_like_text_raises(self):
        # Looks like a psalm superscription (matches KJV_HEADING_HINT) but the id
        # is not in KJV_SUPERSCRIPTIONS -- must fail loudly rather than ship the
        # heading onto a card.
        text = "A Psalm of Asaph. Give ear, O my people, to my law."
        self.assertTrue(KJV_HEADING_HINT.match(text))
        with self.assertRaises(SystemExit):
            kjv_display_text_for("PSA.999.1", text)

    def test_heading_hint_does_not_false_positive_on_ordinary_text(self):
        text = "For God so loved the world, that he gave his only begotten Son."
        self.assertIsNone(KJV_HEADING_HINT.match(text))


class TableDriftGuardTests(unittest.TestCase):
    def test_superscription_prefix_mismatch_raises(self):
        # A KJV_SUPERSCRIPTIONS id whose actual text does not start with the
        # table's recorded prefix must fail loudly (the table has drifted out
        # of sync with the source), not silently strip nothing / the wrong
        # thing. Constructed directly, not by editing the real table.
        with self.assertRaises(SystemExit):
            kjv_display_text_for("PSA.23.1", "The Lord is my shepherd; I shall not want.")

    def test_trailing_marker_suffix_mismatch_raises(self):
        with self.assertRaises(SystemExit):
            kjv_display_text_for(
                "HAB.3.19",
                "The Lord God is my strength, and he will make my feet like hinds' feet.")

    def test_stripping_superscription_to_empty_raises(self):
        prefix = KJV_SUPERSCRIPTIONS["PSA.23.1"]
        with self.assertRaises(SystemExit):
            kjv_display_text_for("PSA.23.1", prefix)

    def test_unlisted_trailing_selah_raises(self):
        # "Selah." at the end is a liturgical marker; any id carrying it that
        # is not explicitly in KJV_TRAILING_MARKERS must fail loudly.
        with self.assertRaises(SystemExit):
            kjv_display_text_for("PSA.999.1", "Some verse text. Selah.")


if __name__ == "__main__":
    unittest.main()
