import pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import normalize_book_name, load_protestant_books, load_source_by_index, load_source_by_name, SourceDataError

ROOT = pathlib.Path(__file__).resolve().parent.parent


class NormalizeBookNameTests(unittest.TestCase):
    def test_roman_numeral_prefix(self):
        self.assertEqual(normalize_book_name("II Kings"), "2 Kings")
        self.assertEqual(normalize_book_name("I Samuel"), "1 Samuel")
        self.assertEqual(normalize_book_name("III John"), "3 John")

    def test_of_john_suffix(self):
        self.assertEqual(normalize_book_name("Revelation of John"), "Revelation")

    def test_unaffected_name_unchanged(self):
        self.assertEqual(normalize_book_name("Genesis"), "Genesis")

    def test_none_and_empty(self):
        self.assertEqual(normalize_book_name(None), "")
        self.assertEqual(normalize_book_name(""), "")


class LoadProtestantBooksTests(unittest.TestCase):
    def test_returns_66_books_in_order(self):
        books = load_protestant_books()
        self.assertEqual(len(books), 66)
        self.assertEqual(books[0]["id"], "GEN")
        self.assertEqual(books[-1]["id"], "REV")


class LoadSourceByIndexTests(unittest.TestCase):
    def test_loads_real_kjv(self):
        index = load_source_by_index(ROOT / "data" / "source" / "KJV.json")
        self.assertEqual(len(index), 31102)
        self.assertEqual(index[("JHN", 3, 16)],
                          "For God so loved the world, that he gave his only "
                          "begotten Son, that whosoever believeth in him should "
                          "not perish, but have everlasting life.")

    def test_missing_file_raises_source_data_error(self):
        with self.assertRaises(SourceDataError):
            load_source_by_index(ROOT / "data" / "source" / "NOPE.json")


class LoadSourceByNameTests(unittest.TestCase):
    def test_loads_real_cpdv_paired_by_name_not_index(self):
        by_book = load_source_by_name(ROOT / "data" / "source" / "CPDV.json")
        self.assertEqual(len(by_book), 66)
        # CPDV interleaves the deuterocanon through the Old Testament, so its
        # array position for Psalms differs from bible_books.json's — proving
        # this loaded correctly (by name) rather than by coincidence of index.
        psalms = by_book["PSA"]
        self.assertEqual(psalms["name"], "Psalms")
        self.assertEqual(len(psalms["chapters"]), 150)

    def test_esther_pairs_correctly_despite_deuterocanon_between_ezra_and_job(self):
        # Genesis..Nehemiah then Tobit/Judith (deuterocanon) sit before Esther
        # in CPDV's own array order; a naive index pairing would land on the
        # wrong book here. Confirm the real content is Esther's, not Tobit's
        # or Judith's.
        by_book = load_source_by_name(ROOT / "data" / "source" / "CPDV.json")
        self.assertEqual(by_book["EST"]["name"], "Esther")


if __name__ == "__main__":
    unittest.main()
