import pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from transcribe_audio import build_lines, collapse_repeats, parse_whisper_json, split_segment


def seg(start, end, text):
    return {"start": start, "end": end, "text": text}


class ParseWhisperJsonTests(unittest.TestCase):
    def test_reads_offsets_in_seconds_and_strips_text(self):
        data = {"transcription": [
            {"offsets": {"from": 0, "to": 2000}, "text": " Dòng đầu tiên."},
            {"offsets": {"from": 2000, "to": 5500}, "text": " Dòng thứ hai. "},
        ]}
        self.assertEqual(parse_whisper_json(data),
                         [seg(0.0, 2.0, "Dòng đầu tiên."), seg(2.0, 5.5, "Dòng thứ hai.")])


class CollapseRepeatsTests(unittest.TestCase):
    def test_repeated_text_extends_the_previous_segment(self):
        segments = [seg(0, 2, "A."), seg(2, 4, "A."), seg(4, 6, "B."), seg(6, 8, "A.")]
        self.assertEqual(collapse_repeats(segments),
                         [seg(0, 4, "A."), seg(4, 6, "B."), seg(6, 8, "A.")])

    def test_does_not_mutate_input(self):
        segments = [seg(0, 2, "A."), seg(2, 4, "A.")]
        collapse_repeats(segments)
        self.assertEqual(segments[0]["end"], 2)


class SplitSegmentTests(unittest.TestCase):
    def test_short_segment_is_one_line(self):
        self.assertEqual(split_segment(seg(1, 3, "Thành là ai?")), [seg(1, 3, "Thành là ai?")])

    def test_splits_sentences_and_shares_time_by_length(self):
        lines = split_segment(seg(10, 20, "Một hai ba. Bốn năm sáu bảy tám chín mười."), max_chars=80)
        self.assertEqual([l["text"] for l in lines], ["Một hai ba.", "Bốn năm sáu bảy tám chín mười."])
        self.assertEqual(lines[0]["start"], 10)
        self.assertAlmostEqual(lines[0]["end"], 10 + 10 * 11 / 41)
        self.assertEqual(lines[1]["start"], lines[0]["end"])
        self.assertEqual(lines[1]["end"], 20)

    def test_long_sentence_breaks_at_a_comma(self):
        text = "Bà vừa khóc vừa nói rằng sau khi chôn con, có người quen bên họ hàng biết một gia đình."
        lines = split_segment(seg(0, 9, text), max_chars=60)
        self.assertEqual([l["text"] for l in lines],
                         ["Bà vừa khóc vừa nói rằng sau khi chôn con,",
                          "có người quen bên họ hàng biết một gia đình."])

    def test_long_sentence_without_comma_breaks_at_a_space(self):
        text = "một hai ba bốn năm sáu bảy tám chín mười"
        lines = split_segment(seg(0, 4, text), max_chars=20)
        self.assertTrue(all(len(l["text"]) <= 20 for l in lines))
        self.assertEqual(" ".join(l["text"] for l in lines), text)

    def test_early_comma_is_not_used_as_a_break(self):
        text = "Rồi, anh ngẩng lên nhìn tấm bia thật lâu mà không nói gì"
        lines = split_segment(seg(0, 4, text), max_chars=40)
        self.assertNotEqual(lines[0]["text"], "Rồi,")

    def test_word_longer_than_limit_is_hard_cut(self):
        lines = split_segment(seg(0, 1, "x" * 25), max_chars=10)
        self.assertEqual([len(l["text"]) for l in lines], [10, 10, 5])


class BuildLinesTests(unittest.TestCase):
    def test_drops_empty_collapses_repeats_and_rounds(self):
        segments = [seg(0, 1, "  "), seg(1, 2.3333, "A."), seg(2.3333, 4.6666, "A."), seg(4.6666, 6, "B.")]
        self.assertEqual(build_lines(segments),
                         [seg(1, 4.67, "A."), seg(4.67, 6, "B.")])


if __name__ == "__main__":
    unittest.main()
