#!/usr/bin/env python3
"""One-off generator: produce a starting-candidate CPDV verse map for the
Psalms ids among the 130 affected selected verses. NOT authoritative --
every entry gets read against real text before being trusted. See Task 9 of
docs/superpowers/plans/2026-09-09-multi-translation.md."""
import json, pathlib, sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import load_source_by_index, load_source_by_name
from cpdv_psalm_offsets import resolve_psalm_verse

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    kjv_raw = json.loads((ROOT / "data/source/KJV.json").read_text())
    cpdv_raw = json.loads((ROOT / "data/source/CPDV.json").read_text())
    kjv_psa = next(b for b in kjv_raw["books"] if b["name"] == "Psalms")
    cpdv_psa = next(b for b in cpdv_raw["books"] if b["name"] == "Psalms")
    kjv_counts = {c["chapter"]: len(c["verses"]) for c in kjv_psa["chapters"]}
    cpdv_counts = {c["chapter"]: len(c["verses"]) for c in cpdv_psa["chapters"]}
    kjv_text = {c["chapter"]: {v["verse"]: v["text"] for v in c["verses"]}
                for c in kjv_psa["chapters"]}
    cpdv_text = {c["chapter"]: {v["verse"]: v["text"] for v in c["verses"]}
                 for c in cpdv_psa["chapters"]}

    selection = json.loads((ROOT / "data/curation/selection.json").read_text())["selected"]
    psalm_ids = [e["id"] for e in selection if e["id"].startswith("PSA.")]

    out = {}
    for vid in psalm_ids:
        _, ch, v = vid.split(".")
        ch, v = int(ch), int(v)
        cch, cv = resolve_psalm_verse(ch, v, kjv_counts, cpdv_counts)
        out[vid] = {
            "candidate": {"chapter": cch, "verse": cv},
            "kjv_text": kjv_text[ch][v],
            "cpdv_text_at_candidate": cpdv_text.get(cch, {}).get(cv, "<MISSING>"),
        }

    report_path = ROOT / ".superpowers/sdd/cpdv-map-candidates.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(out, indent=1, ensure_ascii=False))
    print(f"wrote {len(out)} candidates to {report_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
