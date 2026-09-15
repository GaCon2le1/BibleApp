import json, pathlib, sys, tempfile, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from build_audio import ids_needing_audio, run_pipeline


class FakeProvider:
    """Stands in for the real narration API: returns fixed bytes and a
    deterministic fake duration, and records every id it was asked to narrate."""
    def __init__(self):
        self.calls = []

    def narrate(self, verse_id, text):
        self.calls.append((verse_id, text))
        return b"FAKE-AUDIO-BYTES", 7500  # (clip bytes, durationMs)


class IdsNeedingAudioTests(unittest.TestCase):
    def test_all_ids_needed_when_index_empty(self):
        needed = ids_needing_audio(all_ids=["A.1.1", "B.1.1"], already_done=set())
        self.assertEqual(needed, ["A.1.1", "B.1.1"])

    def test_already_done_ids_are_skipped(self):
        needed = ids_needing_audio(all_ids=["A.1.1", "B.1.1"], already_done={"A.1.1"})
        self.assertEqual(needed, ["B.1.1"])

    def test_order_is_stable_and_matches_input(self):
        needed = ids_needing_audio(all_ids=["C.1.1", "A.1.1", "B.1.1"], already_done=set())
        self.assertEqual(needed, ["C.1.1", "A.1.1", "B.1.1"])


class RunPipelineTests(unittest.TestCase):
    def test_writes_clip_and_appends_manifest_entry(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            audio_dir = tmp / "Audio"
            audio_dir.mkdir()
            index_path = tmp / "audio_index.json"
            index_path.write_text(json.dumps(
                {"schemaVersion": 1, "contentVersion": "0", "entries": []}))

            provider = FakeProvider()
            run_pipeline(
                texts={"JHN.3.16": "For God so loved the world."},
                audio_dir=audio_dir,
                index_path=index_path,
                provider=provider,
                content_version="test.1",
            )

            self.assertEqual(provider.calls, [("JHN.3.16", "For God so loved the world.")])
            self.assertTrue((audio_dir / "JHN.3.16.m4a").exists())
            self.assertEqual((audio_dir / "JHN.3.16.m4a").read_bytes(), b"FAKE-AUDIO-BYTES")

            doc = json.loads(index_path.read_text())
            self.assertEqual(doc["contentVersion"], "test.1")
            self.assertEqual(doc["entries"], [{"id": "JHN.3.16", "durationMs": 7500}])

    def test_is_resumable_and_does_not_renarrate_existing_ids(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            audio_dir = tmp / "Audio"
            audio_dir.mkdir()
            index_path = tmp / "audio_index.json"
            index_path.write_text(json.dumps({
                "schemaVersion": 1, "contentVersion": "0",
                "entries": [{"id": "JHN.3.16", "durationMs": 8000}],
            }))
            (audio_dir / "JHN.3.16.m4a").write_bytes(b"EXISTING")

            provider = FakeProvider()
            run_pipeline(
                texts={"JHN.3.16": "text", "PSA.23.1": "other text"},
                audio_dir=audio_dir,
                index_path=index_path,
                provider=provider,
                content_version="test.2",
            )

            # Only the new id was narrated; the existing clip is untouched.
            self.assertEqual(provider.calls, [("PSA.23.1", "other text")])
            self.assertEqual((audio_dir / "JHN.3.16.m4a").read_bytes(), b"EXISTING")

            doc = json.loads(index_path.read_text())
            ids = sorted(e["id"] for e in doc["entries"])
            self.assertEqual(ids, ["JHN.3.16", "PSA.23.1"])


if __name__ == "__main__":
    unittest.main()
