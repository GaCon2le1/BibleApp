import pathlib, sys, unittest
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from check_selection import check_selection


class CheckSelectionTests(unittest.TestCase):
    def test_flags_wrong_count(self):
        errs = check_selection(
            {"selected": [{"id": "JHN.3.16", "tier": 1, "topics": ["love"]}]})
        self.assertTrue(any("expected 400" in e for e in errs), errs)

    def test_flags_topic_below_floor(self):
        sel = [{"id": "PSA.%d.1" % i, "tier": 2, "topics": ["hope"]}
               for i in range(1, 401)]
        errs = check_selection({"selected": sel})
        self.assertTrue(any("topic 'anxiety' has 0" in e for e in errs), errs)

    def test_flags_tier_distribution(self):
        sel = [{"id": "PSA.%d.1" % i, "tier": 1, "topics": ["hope"]}
               for i in range(1, 401)]
        errs = check_selection({"selected": sel})
        self.assertTrue(any("tier 1 count 400" in e for e in errs), errs)


if __name__ == "__main__":
    unittest.main()
