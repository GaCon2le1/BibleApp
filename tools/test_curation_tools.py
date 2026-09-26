import json, pathlib, sys, tempfile, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from curation_tools import (Sources, lookup, marker_problems, merge_expansion,
                            near_duplicate_pairs, overlap, propose_cpdv_ref, read_staging,
                            selected_ids)

SOURCES = Sources()


class OverlapTests(unittest.TestCase):
    def test_identical_text_scores_one(self):
        self.assertEqual(overlap("Jesus wept bitterly", "Jesus wept bitterly"), 1.0)

    def test_stop_words_alone_score_zero(self):
        self.assertEqual(overlap("the lord and the god", "unrelated words entirely"), 0.0)

    def test_is_measured_against_the_reference(self):
        # Every content word of the reference appears in the longer text.
        self.assertEqual(overlap("mercy endures", "his mercy endures forever and ever"), 1.0)


class LookupTests(unittest.TestCase):
    def test_flags_selected_missing_and_fragment(self):
        rows = {r["id"]: r for r in lookup(
            ["JHN.3.16", "PSA.151.1", "ROM.3.23", "GEN.21.17"], SOURCES,
            selected={"JHN.3.16"})}
        self.assertEqual(rows["JHN.3.16"]["flags"], ["selected"])
        self.assertEqual(rows["PSA.151.1"]["flags"], ["missing"])
        # BSB ROM.3.23 ends "...the glory of God," -- it runs into 3:24.
        self.assertIn("fragment", rows["ROM.3.23"]["flags"])
        self.assertEqual(rows["GEN.21.17"]["flags"], [])

    def test_returns_real_text(self):
        (row,) = lookup(["JHN.11.35"], SOURCES, selected=set())
        self.assertEqual(row["kjv"], "Jesus wept.")


class ProposeCpdvRefTests(unittest.TestCase):
    def test_same_numbering_keeps_candidate(self):
        p = propose_cpdv_ref("JHN.11.35", SOURCES)
        self.assertEqual(p["best"], (11, 35))
        self.assertEqual(p["best"], p["candidate"])

    def test_finds_plus_one_shift_in_jonah_2(self):
        # CPDV Jonah 2 opens with KJV 1:17, so KJV 2:9 is CPDV 2:10.
        self.assertEqual(propose_cpdv_ref("JON.2.9", SOURCES)["best"], (2, 10))

    def test_finds_plus_one_shift_in_haggai_2(self):
        self.assertEqual(propose_cpdv_ref("HAG.2.4", SOURCES)["best"], (2, 5))

    def test_uses_psalm_resolver_for_candidate(self):
        # KJV Psalm 23 is CPDV Psalm 22, with the heading as its own verse.
        self.assertEqual(propose_cpdv_ref("PSA.23.4", SOURCES)["candidate"][0], 22)


class NearDuplicatePairsTests(unittest.TestCase):
    def test_reports_pairs_at_or_above_threshold_most_similar_first(self):
        texts = {"A.1.1": "love one another deeply",
                 "B.1.1": "love one another deeply always",
                 "C.1.1": "love one another",
                 "D.1.1": "completely different sentence here"}
        pairs = near_duplicate_pairs(texts, threshold=0.75)
        self.assertEqual(pairs, [(0.8, "A.1.1", "B.1.1"), (0.75, "A.1.1", "C.1.1")])

    def test_empty_text_never_pairs(self):
        self.assertEqual(near_duplicate_pairs({"A.1.1": "", "B.1.1": ""}), [])


class MarkerProblemsTests(unittest.TestCase):
    def test_reports_unlisted_psalm_heading(self):
        # PSA.4.1 carries "To the chief Musician on Neginoth..." in KJV and
        # "For the choirmaster..." in BSB, and neither is in build_feed's
        # superscription tables.
        found = {(name, vid) for name, vid, _ in
                 marker_problems(["PSA.4.1"], SOURCES, {"PSA.4.1": (4, 2)})}
        self.assertIn(("KJV", "PSA.4.1"), found)
        self.assertIn(("BSB", "PSA.4.1"), found)

    def test_listed_heading_and_plain_verse_pass(self):
        refs = {"PSA.23.1": (22, 1), "JHN.11.35": (11, 35)}
        self.assertEqual(marker_problems(list(refs), SOURCES, refs), [])


class StagingTests(unittest.TestCase):
    def test_read_staging_parses_all_three_files(self):
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            (d / "picks.tsv").write_text("JHN.11.35 2 grief,love\n\n")
            (d / "cpdv_refs.json").write_text(json.dumps({"JHN.11.35": {"chapter": 11, "verse": 35}}))
            (d / "contexts.tsv").write_text("JHN.11.35\tAt the tomb of Lazarus, Jesus weeps.\n")
            picks, refs, contexts = read_staging(d)
        self.assertEqual(picks, [("JHN.11.35", 2, ["grief", "love"])])
        self.assertEqual(refs, {"JHN.11.35": {"chapter": 11, "verse": 35}})
        self.assertEqual(contexts, {"JHN.11.35": "At the tomb of Lazarus, Jesus weeps."})

    def test_merge_appends_after_existing_entries(self):
        sel, cmap, ctx = merge_expansion(
            {"selected": [{"id": "GEN.1.1", "tier": 1, "topics": ["hope"]}]},
            {"GEN.1.1": {"chapter": 1, "verse": 1}}, {"GEN.1.1": "old"},
            [("JHN.11.35", 2, ["grief"])], {"JHN.11.35": {"chapter": 11, "verse": 35}},
            {"JHN.11.35": "new"})
        self.assertEqual([e["id"] for e in sel["selected"]], ["GEN.1.1", "JHN.11.35"])
        self.assertEqual(list(cmap), ["GEN.1.1", "JHN.11.35"])
        self.assertEqual(ctx["JHN.11.35"], "new")

    def test_merge_rejects_reselected_and_unmatched_ids(self):
        with self.assertRaises(ValueError) as cm:
            merge_expansion(
                {"selected": [{"id": "GEN.1.1", "tier": 1, "topics": ["hope"]}]}, {}, {},
                [("GEN.1.1", 2, ["hope"]), ("JHN.11.35", 2, ["grief"])],
                {"GEN.1.1": {"chapter": 1, "verse": 1}}, {"GEN.1.1": "x", "ROM.1.1": "y"})
        message = str(cm.exception)
        self.assertIn("GEN.1.1 is already selected", message)
        self.assertIn("JHN.11.35 has no cpdv_refs entry", message)
        self.assertIn("ROM.1.1 in contexts is not a pick", message)


# Pairs already shipped before this guard existed, each read and kept on
# purpose: two synoptic sayings the original curators chose to keep, a
# repeated line inside the Song of Songs, and an Isaiah prophecy quoted in
# Matthew.
KNOWN_NEAR_DUPLICATES = {
    ("MAT.20.28", "MRK.10.45"),
    ("LUK.16.13", "MAT.6.24"),
    ("SNG.2.16", "SNG.6.3"),
    ("ISA.42.3", "MAT.12.20"),
}


class ShippedSelectionNearDuplicateTests(unittest.TestCase):
    """Exact-text duplicates are caught in test_check_selection. This
    catches the near misses a reader would still see as a repeated card,
    such as 1CH.16.11 and PSA.105.4 (the same line in two books, differing
    by one word in KJV)."""

    def test_no_new_near_duplicate_kjv_texts(self):
        texts = {}
        for vid in selected_ids():
            book, chapter, verse = vid.split(".")
            texts[vid] = SOURCES.kjv[(book, int(chapter), int(verse))]
        found = {(a, b) for _, a, b in near_duplicate_pairs(texts, threshold=0.7)}
        self.assertEqual(found - KNOWN_NEAR_DUPLICATES, set())

    def test_guard_catches_a_real_near_duplicate(self):
        texts = {vid: SOURCES.kjv[key] for vid, key in
                 (("1CH.16.11", ("1CH", 16, 11)), ("PSA.105.4", ("PSA", 105, 4)))}
        self.assertEqual([(a, b) for _, a, b in near_duplicate_pairs(texts, 0.7)],
                         [("1CH.16.11", "PSA.105.4")])


if __name__ == "__main__":
    unittest.main()
