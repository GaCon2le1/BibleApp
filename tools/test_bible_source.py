import pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import normalize_book_name, load_protestant_books, load_source_by_index, SourceDataError

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


if __name__ == "__main__":
    unittest.main()
