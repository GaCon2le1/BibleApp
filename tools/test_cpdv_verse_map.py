import json, pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import load_source_by_name
from check_selection import TOTAL

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAP = ROOT / "data" / "curation" / "cpdv_verse_map.json"
SELECTION = ROOT / "data" / "curation" / "selection.json"


class CpdvVerseMapTests(unittest.TestCase):
    def test_has_one_entry_per_selected_id(self):
        m = json.loads(MAP.read_text())
        sel_ids = {e["id"] for e in json.loads(SELECTION.read_text())["selected"]}
        self.assertEqual(set(m), sel_ids)
        # set(m) == sel_ids already implies len(m) == len(sel_ids) (dict keys
        # are unique), so re-asserting that would be tautological. Cross-check
        # against check_selection.TOTAL instead -- catching TOTAL and the
        # map's actual size drifting apart, which len(m) == len(sel_ids)
        # cannot.
        self.assertEqual(len(m), TOTAL)

    def test_every_entry_resolves_to_a_real_cpdv_verse(self):
        m = json.loads(MAP.read_text())
        by_book = load_source_by_name(ROOT / "data" / "source" / "CPDV.json")
        bad = []
        for vid, ref in m.items():
            book = vid.split(".")[0]
            chapters = by_book[book]["chapters"]
            chapter = next((c for c in chapters if c["chapter"] == ref["chapter"]), None)
            if chapter is None:
                bad.append((vid, "no such chapter"))
                continue
            verse = next((v for v in chapter["verses"] if v["verse"] == ref["verse"]), None)
            if verse is None:
                bad.append((vid, "no such verse"))
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
