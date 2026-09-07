import json, pathlib, subprocess, sys, tempfile, unittest
from unittest import mock
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import validate_feed as vf
from validate_feed import validate_feed

FIX = pathlib.Path(__file__).parent / "fixtures"
ROOT = pathlib.Path(__file__).resolve().parent.parent


def _chapters(count):
    """Minimal chapters list of the given length; verse content is irrelevant
    to the structural checks these tests exercise."""
    return [{"chapter": c, "verses": [{"verse": 1, "text": "x"}]}
            for c in range(1, count + 1)]


class ValidateFeedTests(unittest.TestCase):
    def test_valid_feed_has_no_errors(self):
        self.assertEqual(validate_feed(FIX / "valid_feed.json"), [])

    def test_catches_wrong_verse_text(self):
        errs = validate_feed(FIX / "invalid_feed.json")
        self.assertTrue(any("text does not match KJV" in e for e in errs), errs)

    def test_catches_bad_topic(self):
        errs = validate_feed(FIX / "invalid_feed.json")
        self.assertTrue(any("unknown topic" in e for e in errs), errs)

    def test_catches_context_too_short(self):
        errs = validate_feed(FIX / "invalid_feed.json")
        self.assertTrue(any("context length" in e for e in errs), errs)

    def test_cli_exits_nonzero_on_invalid(self):
        r = subprocess.run([sys.executable, "tools/validate_feed.py",
                            str(FIX / "invalid_feed.json")],
                           cwd=ROOT, capture_output=True)
        self.assertEqual(r.returncode, 1)

    def test_catches_display_text_not_in_text(self):
        errs = validate_feed(FIX / "invalid_feed.json")
        self.assertTrue(
            any("displayText is not part of text" in e for e in errs), errs)

    def _feed_with(self, mutate):
        import json, tempfile, os
        doc = json.loads((FIX / "valid_feed.json").read_text())
        mutate(doc["verses"][0])
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(doc, f)
            return f.name

    def test_accepts_stripped_leading_superscription(self):
        # Mutating JHN.3.16 with a fabricated prefix would fail the
        # unrelated, pre-existing KJV-verbatim check (the fixture's text
        # would no longer match its real KJV source). PSA.23.1 genuinely
        # carries this superscription in the KJV source, so both checks see
        # legitimate data and only the displayText logic is under test.
        import os

        def mutate(entry):
            entry["id"] = "PSA.23.1"
            entry["reference"] = "Psalms 23:1"
            entry["book"] = "PSA"
            entry["chapter"] = 23
            entry["verse"] = 1
            entry["text"] = "A Psalm of David. The Lord is my shepherd; I shall not want."
            entry["displayText"] = "The Lord is my shepherd; I shall not want."

        path = self._feed_with(mutate)
        try:
            self.assertEqual(validate_feed(path), [])
        finally:
            os.unlink(path)

    def test_accepts_stripped_trailing_colophon(self):
        # Same reasoning as above: HAB.3.19 genuinely ends in this colophon
        # in the KJV source, so this is real data, not a fabricated mutation.
        import os

        def mutate(entry):
            entry["id"] = "HAB.3.19"
            entry["reference"] = "Habakkuk 3:19"
            entry["book"] = "HAB"
            entry["chapter"] = 3
            entry["verse"] = 19
            entry["text"] = (
                "The Lord God is my strength, and he will make my feet like "
                "hinds’ feet, and he will make me to walk upon mine high "
                "places. To the chief singer on my stringed instruments.")
            entry["displayText"] = (
                "The Lord God is my strength, and he will make my feet like "
                "hinds’ feet, and he will make me to walk upon mine high "
                "places.")

        path = self._feed_with(mutate)
        try:
            self.assertEqual(validate_feed(path), [])
        finally:
            os.unlink(path)

    def test_catches_missing_display_text(self):
        import os

        def mutate(entry):
            del entry["displayText"]

        path = self._feed_with(mutate)
        try:
            self.assertTrue(
                any("displayText is missing" in e for e in validate_feed(path)))
        finally:
            os.unlink(path)

    # -- Finding 1: positional pairing can't detect a transposition --------

    def test_catches_transposed_books_with_equal_chapter_counts(self):
        # Two adjacent "books" that happen to share a chapter count (like
        # Romans/1 Corinthians in the real data, both 16 chapters), but
        # whose order has drifted between the two source files. The chapter
        # count check alone can't see this; a name check must.
        books_meta = {"books": [
            {"id": "AAA", "name": "Alpha", "canon": "protestant", "chapters": 3},
            {"id": "BBB", "name": "Beta", "canon": "protestant", "chapters": 3},
        ]}
        kjv_source = {"books": [
            {"name": "Beta", "chapters": _chapters(3)},   # swapped with Alpha
            {"name": "Alpha", "chapters": _chapters(3)},
        ]}
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            books_path = td / "bible_books.json"
            source_path = td / "KJV.json"
            feed_path = td / "feed.json"
            books_path.write_text(json.dumps(books_meta))
            source_path.write_text(json.dumps(kjv_source))
            feed_path.write_text(json.dumps({"verses": []}))
            with mock.patch.object(vf, "BOOKS", books_path), \
                 mock.patch.object(vf, "SOURCE", source_path):
                errs = validate_feed(feed_path)
        self.assertTrue(errs, "expected a reported error, got none")
        self.assertTrue(any("AAA" in e or "name" in e.lower() for e in errs), errs)

    def test_naming_convention_difference_alone_is_not_a_mismatch(self):
        # Roman-numeral / "of John" style differences between the two files
        # are a real, expected convention difference (see bible_books.json
        # "1 Samuel" vs KJV.json "I Samuel", "Revelation" vs "Revelation of
        # John") and must NOT be flagged as a mismatch.
        books_meta = {"books": [
            {"id": "1SA", "name": "1 Samuel", "canon": "protestant", "chapters": 2},
            {"id": "REV", "name": "Revelation", "canon": "protestant", "chapters": 2},
        ]}
        kjv_source = {"books": [
            {"name": "I Samuel", "chapters": _chapters(2)},
            {"name": "Revelation of John", "chapters": _chapters(2)},
        ]}
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            books_path = td / "bible_books.json"
            source_path = td / "KJV.json"
            feed_path = td / "feed.json"
            books_path.write_text(json.dumps(books_meta))
            source_path.write_text(json.dumps(kjv_source))
            feed_path.write_text(json.dumps({"verses": []}))
            with mock.patch.object(vf, "BOOKS", books_path), \
                 mock.patch.object(vf, "SOURCE", source_path):
                errs = validate_feed(feed_path)
        self.assertEqual(errs, [])

    # -- Finding 2: book-count mismatch must not crash ----------------------

    def test_book_count_mismatch_reported_not_raised(self):
        books_meta = {"books": [
            {"id": "AAA", "name": "Alpha", "canon": "protestant", "chapters": 3},
            {"id": "BBB", "name": "Beta", "canon": "protestant", "chapters": 3},
        ]}
        kjv_source = {"books": [
            {"name": "Alpha", "chapters": _chapters(3)},
            # KJV.json is missing a matching second book entirely.
        ]}
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            books_path = td / "bible_books.json"
            source_path = td / "KJV.json"
            feed_path = td / "feed.json"
            books_path.write_text(json.dumps(books_meta))
            source_path.write_text(json.dumps(kjv_source))
            feed_path.write_text(json.dumps({"verses": []}))
            with mock.patch.object(vf, "BOOKS", books_path), \
                 mock.patch.object(vf, "SOURCE", source_path):
                errs = validate_feed(feed_path)  # must not raise IndexError
        self.assertTrue(errs, "expected a reported error, got none")

    # -- Finding 3: malformed top-level feed JSON must not crash ------------

    def test_feed_top_level_array_reported_not_raised(self):
        with tempfile.TemporaryDirectory() as td:
            feed_path = pathlib.Path(td) / "feed.json"
            feed_path.write_text("[]")
            errs = validate_feed(feed_path)  # must not raise AttributeError
        self.assertTrue(errs, "expected a reported error, got none")

    # -- Finding 4: missing feed file must not crash -------------------------

    def test_missing_feed_file_reported_not_raised(self):
        errs = validate_feed("/nonexistent/path/feed.json")
        self.assertTrue(errs, "expected a reported error, got none")
        self.assertTrue(any("file" in e.lower() or "nonexistent" in e.lower() or "not found" in e.lower()
                           for e in errs), f"error should mention file issue: {errs}")

    # -- Finding 5: malformed JSON in feed must not crash -------------------

    def test_malformed_json_reported_not_raised(self):
        with tempfile.TemporaryDirectory() as td:
            feed_path = pathlib.Path(td) / "feed.json"
            feed_path.write_text("{not valid json")
            errs = validate_feed(feed_path)
        self.assertTrue(errs, "expected a reported error, got none")
        self.assertTrue(any("json" in e.lower() or "invalid" in e.lower() or "parse" in e.lower()
                           for e in errs), f"error should mention JSON/parse issue: {errs}")


class ShippedFeedTests(unittest.TestCase):
    """validate_feed.py has no automated coverage of the file the app actually
    ships. This is the permanent guard for that: run the real validator
    against the real shipped feed_verses.json, so bad data fails the build
    instead of only being caught by someone remembering to run the script by
    hand."""

    def test_shipped_feed_verses_has_no_errors(self):
        shipped = ROOT / "BibleApp" / "BibleApp" / "Resources" / "feed_verses.json"
        self.assertTrue(shipped.is_file(), f"missing shipped feed file: {shipped}")
        self.assertEqual(validate_feed(shipped), [])


if __name__ == "__main__":
    unittest.main()
