import pathlib, subprocess, sys, unittest
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from validate_feed import validate_feed

FIX = pathlib.Path(__file__).parent / "fixtures"
ROOT = pathlib.Path(__file__).resolve().parent.parent


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


if __name__ == "__main__":
    unittest.main()
