#!/usr/bin/env python3
"""Produce narrated .m4a clips for the shipped feed and the manifest
(audio_index.json) describing them. Resumable: an id already present in the
manifest and on disk is left untouched, so a partial run (or a targeted
re-take of one id, after deleting its manifest entry and file) can be
re-run safely. Requires network access and a narration provider API key —
not run as part of any automated test suite."""
import json, os, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
AUDIO_DIR = ROOT / "BibleApp/BibleApp/Resources/Audio"
INDEX_PATH = ROOT / "BibleApp/BibleApp/Resources/audio_index.json"
FEED_INDEX = ROOT / "BibleApp/BibleApp/Resources/feed_index.json"


def ids_needing_audio(all_ids, already_done):
    """all_ids in their existing feed order; already_done is the set of ids
    with both a manifest entry and a file on disk. Order is preserved so
    reruns narrate in a predictable sequence."""
    return [vid for vid in all_ids if vid not in already_done]


def run_pipeline(texts, audio_dir, index_path, provider, content_version):
    """texts: {id: kjv_display_text} for every id this run should ensure has
    audio. provider: object with narrate(id, text) -> (bytes, durationMs).
    Skips any id whose manifest entry AND file already exist."""
    audio_dir = pathlib.Path(audio_dir)
    index_path = pathlib.Path(index_path)
    doc = json.loads(index_path.read_text())
    entries = {e["id"]: e for e in doc["entries"]}

    already_done = {
        vid for vid in entries
        if (audio_dir / f"{vid}.m4a").exists()
    }
    for vid in ids_needing_audio(list(texts.keys()), already_done):
        clip_bytes, duration_ms = provider.narrate(vid, texts[vid])
        (audio_dir / f"{vid}.m4a").write_bytes(clip_bytes)
        entries[vid] = {"id": vid, "durationMs": duration_ms}

    doc["contentVersion"] = content_version
    doc["entries"] = [entries[vid] for vid in sorted(entries)]
    index_path.write_text(json.dumps(doc, indent=2) + "\n")


class NarrationAPIError(Exception):
    pass


class RealNarrationProvider:
    """Talks to the actual narration API. Import-guarded and only
    constructed by main() for a real run, never by tests."""

    def __init__(self, api_key):
        self.api_key = api_key

    def narrate(self, verse_id, text):
        raise NotImplementedError(
            "Wire this to the chosen narration provider's HTTP API before "
            "running tools/build_audio.py for real. Deliberately left "
            "unimplemented in this plan, since the provider/voice is a "
            "production decision made at run time, not at plan-writing time.")


def main():
    api_key = os.environ.get("NARRATION_API_KEY")
    if not api_key:
        sys.exit("NARRATION_API_KEY is not set — see tools/build_audio.py's "
                 "RealNarrationProvider before running this for real.")

    all_ids = [v["id"] for v in json.loads(FEED_INDEX.read_text())["verses"]]
    # Real run only: load each id's KJV displayText from its shard file.
    # (Left as a TODO for whoever runs this for real — shard lookup mirrors
    # ContentStore.content(for:) but in Python; do not duplicate KJV text by
    # hand here.)
    raise NotImplementedError(
        "Wire shard-file KJV text lookup here before running for real.")


if __name__ == "__main__":
    main()
