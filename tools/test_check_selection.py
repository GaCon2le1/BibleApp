import json, pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from check_selection import check_selection, TOPICS, TOTAL

REPO = pathlib.Path(__file__).resolve().parents[1]
SELECTION = REPO / "data" / "curation" / "selection.json"
KJV_SOURCE = REPO / "data" / "source" / "KJV.json"
BIBLE_BOOKS = REPO / "BibleApp" / "BibleApp" / "Resources" / "bible_books.json"


def _load_kjv_verse_ids():
    """Build the set of every "BOOK.CHAPTER.VERSE" id that actually exists in
    the vendored KJV text.

    data/source/KJV.json pairs by index with the 66 canon == "protestant"
    entries of bible_books.json (that file also lists deuterocanonical
    books, which KJV.json does not carry) -- see the module docstring
    contract check_selection.py's callers rely on. This lives in the test
    file, not in check_selection.py, so the checker itself stays free of a
    hard dependency on the 8 MB KJV file.
    """
    books_meta = json.loads(BIBLE_BOOKS.read_text())["books"]
    protestant = [b for b in books_meta if b["canon"] == "protestant"]
    kjv_books = json.loads(KJV_SOURCE.read_text())["books"]
    assert len(protestant) == len(kjv_books) == 66, (
        "expected 66 protestant-canon books lined up with 66 KJV books, "
        "got %d and %d" % (len(protestant), len(kjv_books)))

    ids = set()
    for meta, book in zip(protestant, kjv_books):
        for chapter in book["chapters"]:
            for verse in chapter["verses"]:
                ids.add("%s.%d.%d" % (meta["id"], chapter["chapter"], verse["verse"]))
    return ids

# Real book ids with their real chapter counts, so every fixture id below is a
# verse that actually exists in the KJV (chapter N verse 1 of a real chapter).
# Psalms has 150 chapters -- fixtures must never invent PSA.151.1 and beyond.
# Enough books are listed to cover TOTAL=600 fixture ids with margin.
REAL_BOOKS = [("GEN", 50), ("EXO", 40), ("PSA", 150), ("PRO", 31),
              ("ISA", 66), ("MAT", 28), ("JHN", 21), ("ROM", 16),
              ("JER", 52), ("EZK", 48), ("ACT", 28), ("LUK", 24),
              ("1KI", 22), ("2KI", 25), ("1CH", 29), ("2CH", 36)]

SORTED_TOPICS = sorted(TOPICS)


def real_ids(count):
    """Return `count` distinct ids that resolve against the real KJV."""
    out = []
    for book, chapters in REAL_BOOKS:
        for chapter in range(1, chapters + 1):
            out.append("%s.%d.1" % (book, chapter))
            if len(out) == count:
                return out
    raise AssertionError("not enough real ids for %d entries" % count)


def valid_selection():
    """A well-formed selection: TOTAL entries, legal tiers, every topic well
    over the floor of 20."""
    ids = real_ids(TOTAL)
    # 120 / 320 / 160 sits inside the current TIER_BOUNDS and sums to TOTAL.
    tiers = [1] * 120 + [2] * 320 + [3] * 160
    selected = []
    for index, (vid, tier) in enumerate(zip(ids, tiers)):
        # Two topics per entry, rotating: every topic lands ~66 times.
        a = SORTED_TOPICS[index % len(SORTED_TOPICS)]
        b = SORTED_TOPICS[(index + 5) % len(SORTED_TOPICS)]
        selected.append({"id": vid, "tier": tier, "topics": [a, b]})
    return {"selected": selected}


class ValidSelectionTests(unittest.TestCase):
    def test_well_formed_selection_has_no_errors(self):
        self.assertEqual(check_selection(valid_selection()), [])

    def test_fixture_ids_are_real(self):
        ids = real_ids(TOTAL)
        self.assertEqual(len(set(ids)), TOTAL)
        limits = dict(REAL_BOOKS)
        for vid in ids:
            book, chapter, _verse = vid.split(".")
            self.assertLessEqual(int(chapter), limits[book], vid)


class ShippedSelectionTests(unittest.TestCase):
    def test_repository_selection_is_clean(self):
        doc = json.loads(SELECTION.read_text())
        self.assertEqual(check_selection(doc), [])


class ShippedSelectionIdsResolveTests(unittest.TestCase):
    """check_selection.py only checks an id's shape (BOOK.CHAPTER.VERSE), not
    whether it names a real verse -- it would happily accept "ZZZ.0.0". This
    is the permanent guard against that: every id in the real selection.json
    must resolve against the vendored KJV text."""

    def test_every_selected_id_resolves_against_kjv(self):
        valid_ids = _load_kjv_verse_ids()
        doc = json.loads(SELECTION.read_text())
        bad = [e["id"] for e in doc["selected"] if e.get("id") not in valid_ids]
        self.assertEqual(bad, [], "ids not found in data/source/KJV.json: %s" % bad)


def _load_kjv_text_by_id():
    """Map every "BOOK.CHAPTER.VERSE" id to its real, whitespace-normalized
    KJV text -- the same index tools/validate_feed.py and tools/build_feed.py
    build, reconstructed here so this test has no import-time dependency on
    either."""
    import re as _re
    books_meta = json.loads(BIBLE_BOOKS.read_text())["books"]
    protestant = [b for b in books_meta if b["canon"] == "protestant"]
    kjv_books = json.loads(KJV_SOURCE.read_text())["books"]
    text_by_id = {}
    for meta, book in zip(protestant, kjv_books):
        for chapter in book["chapters"]:
            for verse in chapter["verses"]:
                vid = "%s.%d.%d" % (meta["id"], chapter["chapter"], verse["verse"])
                text_by_id[vid] = _re.sub(r"\s+", " ", verse["text"]).strip()
    return text_by_id


class ShippedSelectionTextsAreUniqueTests(unittest.TestCase):
    """Two different ids can carry the identical KJV sentence (synoptic
    parallels, or a psalm quoted verbatim elsewhere) -- id-uniqueness alone
    does not catch that, and a duplicate reads as a repeated card in the
    feed. This is the permanent guard: no two selected verses' real KJV text
    may be identical. (Case is not folded and whitespace is normalized the
    same way the id-resolution index above does, matching how a user would
    actually perceive two cards as "the same sentence.")"""

    def test_no_two_selected_verses_share_identical_text(self):
        text_by_id = _load_kjv_text_by_id()
        doc = json.loads(SELECTION.read_text())
        by_text = {}
        for entry in doc["selected"]:
            vid = entry.get("id")
            text = text_by_id.get(vid)
            if text is None:
                continue  # already reported by ShippedSelectionIdsResolveTests
            by_text.setdefault(text, []).append(vid)
        dupes = {text: ids for text, ids in by_text.items() if len(ids) > 1}
        self.assertEqual(
            dupes, {},
            "duplicate KJV text shared by multiple selected ids: %s" % dupes)


class CountAndDistributionTests(unittest.TestCase):
    def test_flags_wrong_count(self):
        errs = check_selection(
            {"selected": [{"id": "JHN.3.16", "tier": 1, "topics": ["love"]}]})
        self.assertTrue(any("expected %d" % TOTAL in e for e in errs), errs)

    def test_flags_topic_below_floor(self):
        doc = valid_selection()
        for entry in doc["selected"]:
            entry["topics"] = ["hope"]
        errs = check_selection(doc)
        self.assertTrue(any("topic 'anxiety' has 0" in e for e in errs), errs)

    def test_flags_tier_distribution(self):
        doc = valid_selection()
        for entry in doc["selected"]:
            entry["tier"] = 1
        errs = check_selection(doc)
        self.assertTrue(any("tier 1 count %d" % TOTAL in e for e in errs), errs)

    def test_flags_duplicate_ids(self):
        doc = valid_selection()
        doc["selected"][7]["id"] = doc["selected"][3]["id"]
        errs = check_selection(doc)
        self.assertTrue(any("duplicate ids in selection" in e for e in errs), errs)
        self.assertTrue(any(doc["selected"][3]["id"] in e for e in errs), errs)

    def test_duplicate_ids_is_the_only_complaint(self):
        """The duplicate branch fires on an otherwise clean document."""
        doc = valid_selection()
        doc["selected"][7]["id"] = doc["selected"][3]["id"]
        self.assertEqual(len(check_selection(doc)), 1)


class EntryValidationTests(unittest.TestCase):
    def one_bad(self, mutate):
        """Apply `mutate` to a single entry of an otherwise clean selection and
        return the errors."""
        doc = valid_selection()
        mutate(doc["selected"][0])
        return check_selection(doc)

    def test_flags_misspelled_and_unknown_topics(self):
        errs = self.one_bad(lambda e: e.update(topics=["anxeity", "joy"]))
        self.assertTrue(any("unknown topic 'anxeity'" in e for e in errs), errs)
        self.assertTrue(any("unknown topic 'joy'" in e for e in errs), errs)

    def test_flags_empty_topics(self):
        errs = self.one_bad(lambda e: e.update(topics=[]))
        self.assertTrue(any("has no topics" in e for e in errs), errs)

    def test_flags_too_many_topics(self):
        errs = self.one_bad(
            lambda e: e.update(topics=["hope", "love", "peace", "grief"]))
        self.assertTrue(any("has 4 topics" in e for e in errs), errs)

    def test_flags_repeated_topic_within_entry(self):
        errs = self.one_bad(lambda e: e.update(topics=["hope", "hope"]))
        self.assertTrue(any("repeats topic 'hope'" in e for e in errs), errs)

    def test_flags_non_list_topics(self):
        errs = self.one_bad(lambda e: e.update(topics="hope"))
        self.assertTrue(any("'topics' is str" in e for e in errs), errs)

    def test_flags_missing_topics(self):
        errs = self.one_bad(lambda e: e.pop("topics"))
        self.assertTrue(any("missing 'topics'" in e for e in errs), errs)

    def test_flags_out_of_range_tier(self):
        errs = self.one_bad(lambda e: e.update(tier=7))
        self.assertTrue(any("tier 7 is not 1, 2 or 3" in e for e in errs), errs)

    def test_flags_boolean_tier(self):
        errs = self.one_bad(lambda e: e.update(tier=True))
        self.assertTrue(any("tier True is not 1, 2 or 3" in e for e in errs), errs)

    def test_flags_float_tier(self):
        errs = self.one_bad(lambda e: e.update(tier=1.0))
        self.assertTrue(any("tier 1.0 is not 1, 2 or 3" in e for e in errs), errs)

    def test_flags_missing_tier(self):
        errs = self.one_bad(lambda e: e.pop("tier"))
        self.assertTrue(any("missing 'tier'" in e for e in errs), errs)

    def test_missing_id_is_reported_not_raised(self):
        errs = self.one_bad(lambda e: e.pop("id"))
        self.assertTrue(any("missing 'id'" in e for e in errs), errs)

    def test_flags_non_string_id(self):
        errs = self.one_bad(lambda e: e.update(id=316))
        self.assertTrue(any("'id' is int" in e for e in errs), errs)

    def test_flags_malformed_id(self):
        errs = self.one_bad(lambda e: e.update(id="John 3:16"))
        self.assertTrue(
            any("is not BOOK.CHAPTER.VERSE" in e for e in errs), errs)

    def test_flags_unexpected_keys(self):
        errs = self.one_bad(lambda e: e.update(note="tweak later"))
        self.assertTrue(any("unexpected key(s): note" in e for e in errs), errs)

    def test_flags_non_object_entry(self):
        doc = valid_selection()
        doc["selected"][0] = "JHN.3.16"
        errs = check_selection(doc)
        self.assertTrue(any("entry 0 is str" in e for e in errs), errs)


class MalformedDocumentTests(unittest.TestCase):
    def test_non_object_document(self):
        self.assertTrue(
            any("expected an object" in e for e in check_selection([])))

    def test_non_list_selected(self):
        errs = check_selection({"selected": {"id": "JHN.3.16"}})
        self.assertTrue(any("'selected' is dict" in e for e in errs), errs)

    def test_missing_selected(self):
        errs = check_selection({})
        self.assertTrue(any("found 0" in e for e in errs), errs)


if __name__ == "__main__":
    unittest.main()
