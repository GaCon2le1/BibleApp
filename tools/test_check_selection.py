import json, pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from check_selection import check_selection, TOPICS, TOTAL

REPO = pathlib.Path(__file__).resolve().parents[1]
SELECTION = REPO / "data" / "curation" / "selection.json"

# Real book ids with their real chapter counts, so every fixture id below is a
# verse that actually exists in the KJV (chapter N verse 1 of a real chapter).
# Psalms has 150 chapters -- fixtures must never invent PSA.151.1 and beyond.
REAL_BOOKS = [("GEN", 50), ("EXO", 40), ("PSA", 150), ("PRO", 31),
              ("ISA", 66), ("MAT", 28), ("JHN", 21), ("ROM", 16)]

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
    """A well-formed selection: 400 entries, legal tiers, every topic well over
    the floor of 20."""
    ids = real_ids(TOTAL)
    # 100 / 200 / 100 sits inside 80-120 / 170-230 / 80-120.
    tiers = [1] * 100 + [2] * 200 + [3] * 100
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


class CountAndDistributionTests(unittest.TestCase):
    def test_flags_wrong_count(self):
        errs = check_selection(
            {"selected": [{"id": "JHN.3.16", "tier": 1, "topics": ["love"]}]})
        self.assertTrue(any("expected 400" in e for e in errs), errs)

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
        self.assertTrue(any("tier 1 count 400" in e for e in errs), errs)

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
