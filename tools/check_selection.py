#!/usr/bin/env python3
"""Structural checks on the hand-curated selection of 400 verses."""
import json, pathlib, sys

TOPICS = {"anxiety", "hope", "love", "forgiveness", "strength", "guidance",
          "peace", "doubt", "purpose", "gratitude", "grief", "worth"}
TOTAL = 400
TOPIC_FLOOR = 20          # every topic must sustain its own feed
TIER_BOUNDS = {1: (80, 120), 2: (170, 230), 3: (80, 120)}


def check_selection(doc):
    errors = []
    sel = doc.get("selected", [])

    if len(sel) != TOTAL:
        errors.append(f"expected {TOTAL} selected verses, found {len(sel)}")

    ids = [e["id"] for e in sel]
    if len(ids) != len(set(ids)):
        errors.append("duplicate ids in selection")

    counts = {t: 0 for t in TOPICS}
    tiers = {1: 0, 2: 0, 3: 0}
    for e in sel:
        for t in e.get("topics", []):
            if t in counts:
                counts[t] += 1
        if e.get("tier") in tiers:
            tiers[e["tier"]] += 1

    for topic in sorted(TOPICS):
        if counts[topic] < TOPIC_FLOOR:
            errors.append(
                f"topic '{topic}' has {counts[topic]} verses, floor is {TOPIC_FLOOR}")

    for tier, (lo, hi) in TIER_BOUNDS.items():
        if not lo <= tiers[tier] <= hi:
            errors.append(f"tier {tier} count {tiers[tier]} outside {lo}-{hi}")

    return errors


def main():
    path = pathlib.Path(sys.argv[1])
    errors = check_selection(json.loads(path.read_text()))
    for e in errors:
        print(e)
    print(f"{len(errors)} error(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
