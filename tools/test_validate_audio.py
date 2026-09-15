import pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from validate_audio import validate_audio

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIX = ROOT / "tools" / "fixtures"


class ValidateAudioTests(unittest.TestCase):
    def test_valid_index_has_no_errors(self):
        errors = validate_audio(
            FIX / "valid_audio_index.json",
            FIX / "audio_fixture",
            FIX / "valid_feed.json",
        )
        self.assertEqual(errors, [])

    def test_invalid_index_reports_duplicate(self):
        errors = validate_audio(
            FIX / "invalid_audio_index.json",
            FIX / "audio_fixture",
            FIX / "valid_feed.json",
        )
        self.assertTrue(any("duplicate" in e.lower() for e in errors))

    def test_invalid_index_reports_unknown_id(self):
        errors = validate_audio(
            FIX / "invalid_audio_index.json",
            FIX / "audio_fixture",
            FIX / "valid_feed.json",
        )
        self.assertTrue(any("NOPE.1.1" in e and "not in feed" in e for e in errors))

    def test_invalid_index_reports_duration_out_of_range(self):
        errors = validate_audio(
            FIX / "invalid_audio_index.json",
            FIX / "audio_fixture",
            FIX / "valid_feed.json",
        )
        self.assertTrue(any("duration" in e.lower() for e in errors))

    def test_invalid_index_reports_missing_file(self):
        errors = validate_audio(
            FIX / "invalid_audio_index.json",
            FIX / "audio_fixture",
            FIX / "valid_feed.json",
        )
        self.assertTrue(any("NOPE.1.1" in e and "missing" in e.lower() for e in errors))


if __name__ == "__main__":
    unittest.main()
