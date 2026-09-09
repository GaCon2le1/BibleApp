import pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cpdv_psalm_offsets import resolve_psalm_verse
from bible_source import load_source_by_index, load_source_by_name

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _verse_counts(chapters_key_source):
    """{chapter: verse_count} from a book's raw `chapters` list."""
    return {c["chapter"]: len(c["verses"]) for c in chapters_key_source}


class ResolvePsalmVerseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        kjv_index = load_source_by_index(ROOT / "data" / "source" / "KJV.json")
        cpdv_by_book = load_source_by_name(ROOT / "data" / "source" / "CPDV.json")
        # Rebuild per-chapter verse counts directly from the raw sources,
        # since load_source_by_index only gives a flat (book,chapter,verse)->text
        # map, not counts, and CPDV's own chapter/verse numbers are not the
        # protestant ones load_source_by_name resolves against.
        import json
        kjv_raw = json.loads((ROOT / "data" / "source" / "KJV.json").read_text())
        cpdv_raw = json.loads((ROOT / "data" / "source" / "CPDV.json").read_text())
        kjv_psa = next(b for b in kjv_raw["books"] if b["name"] == "Psalms")
        cpdv_psa = next(b for b in cpdv_raw["books"] if b["name"] == "Psalms")
        cls.kjv_counts = _verse_counts(kjv_psa["chapters"])
        cls.cpdv_counts = _verse_counts(cpdv_psa["chapters"])
        cls.kjv_text = {c["chapter"]: {v["verse"]: v["text"] for v in c["verses"]}
                         for c in kjv_psa["chapters"]}
        cls.cpdv_text = {c["chapter"]: {v["verse"]: v["text"] for v in c["verses"]}
                          for c in cpdv_psa["chapters"]}

    def _assert_content_overlaps(self, kjv_ref, cpdv_ref, shared_word):
        kch, kv = kjv_ref
        cch, cv = cpdv_ref
        self.assertIn(shared_word, self.kjv_text[kch][kv].lower())
        self.assertIn(shared_word, self.cpdv_text[cch][cv].lower())

    def test_simple_range_offset_minus_one(self):
        # KJV 23:1 ("The Lord is my shepherd") is the famous anchor point:
        # confirmed by direct reading earlier in this investigation to be
        # CPDV 22:1. No shared-word content check here -- CPDV renders this
        # verse as "The Lord directs me, and nothing will be lacking to me",
        # which shares no vocabulary with KJV's "shepherd" despite being the
        # same verse, so the numeric assertion is the real proof.
        result = resolve_psalm_verse(23, 1, self.kjv_counts, self.cpdv_counts)
        self.assertEqual(result, (22, 1))

    def test_psalm_1_offset_zero(self):
        # Psalm 1 has no musical/authorship heading in either translation,
        # so it is the one chapter in 1-8 with zero verse-level shift too --
        # chapters 2-8 map to an unchanged chapter number but still shift by
        # +1 at the verse level (see the module docstring).
        self.assertEqual(resolve_psalm_verse(1, 1, self.kjv_counts, self.cpdv_counts), (1, 1))

    def test_chapters_148_through_150_offset_zero(self):
        self.assertEqual(resolve_psalm_verse(150, 6, self.kjv_counts, self.cpdv_counts), (150, 6))

    def test_psalm_9_10_merge(self):
        # KJV 9 and 10 both live inside CPDV's single chapter 9. KJV 9:1 folds
        # its heading into verse 1 the way most psalms do; CPDV 9's heading is
        # its own separate verse 1, so content starts at CPDV 9:2.
        self.assertEqual(resolve_psalm_verse(9, 1, self.kjv_counts, self.cpdv_counts), (9, 2))
        self.assertEqual(resolve_psalm_verse(10, 1, self.kjv_counts, self.cpdv_counts), (9, 22))

    def test_psalm_114_115_merge(self):
        self.assertEqual(resolve_psalm_verse(114, 1, self.kjv_counts, self.cpdv_counts), (113, 1))
        self.assertEqual(resolve_psalm_verse(115, 1, self.kjv_counts, self.cpdv_counts), (113, 9))

    def test_psalm_116_split(self):
        self.assertEqual(resolve_psalm_verse(116, 9, self.kjv_counts, self.cpdv_counts), (114, 9))
        self.assertEqual(resolve_psalm_verse(116, 10, self.kjv_counts, self.cpdv_counts), (115, 1))

    def test_psalm_147_split(self):
        self.assertEqual(resolve_psalm_verse(147, 11, self.kjv_counts, self.cpdv_counts), (146, 11))
        self.assertEqual(resolve_psalm_verse(147, 12, self.kjv_counts, self.cpdv_counts), (147, 1))

    def test_psalm_4_known_exception(self):
        # A naive count-based delta (2) is wrong here -- confirmed by reading
        # real text. Verses 2-7 are +1; verse 8 is where content genuinely
        # starts in CPDV 4:9 (its second half spills into CPDV 4:10, but 4:9
        # is where a reader should land).
        self.assertEqual(resolve_psalm_verse(4, 2, self.kjv_counts, self.cpdv_counts), (4, 3))
        self.assertEqual(resolve_psalm_verse(4, 8, self.kjv_counts, self.cpdv_counts), (4, 9))

    def test_psalm_56_known_exception(self):
        # A naive count-based delta (0, since both chapters have 13 verses)
        # is wrong here too -- confirmed by reading real text. +1 through
        # verse 11, then +0 for verses 12-13.
        self.assertEqual(resolve_psalm_verse(56, 3, self.kjv_counts, self.cpdv_counts), (55, 4))
        self.assertEqual(resolve_psalm_verse(56, 8, self.kjv_counts, self.cpdv_counts), (55, 9))
        self.assertEqual(resolve_psalm_verse(56, 12, self.kjv_counts, self.cpdv_counts), (55, 12))

    def test_out_of_range_chapter_raises(self):
        with self.assertRaises(ValueError):
            resolve_psalm_verse(151, 1, self.kjv_counts, self.cpdv_counts)


if __name__ == "__main__":
    unittest.main()
