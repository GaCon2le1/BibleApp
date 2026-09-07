#!/usr/bin/env python3
"""Structural checks on the hand-curated selection of 400 verses.

Every problem is reported as a string in the returned list. check_selection
never raises on malformed input: a caller can hand it any JSON document and
get back a description of what is wrong with it.
"""
import json, pathlib, re, sys

TOPICS = {"anxiety", "hope", "love", "forgiveness", "strength", "guidance",
          "peace", "doubt", "purpose", "gratitude", "grief", "worth"}
TOTAL = 400
TOPIC_FLOOR = 20          # every topic must sustain its own feed
TIER_BOUNDS = {1: (80, 120), 2: (170, 230), 3: (80, 120)}
MAX_TOPICS = 3
ENTRY_KEYS = {"id", "tier", "topics"}
ID_RE = re.compile(r"^[A-Z0-9]{3}\.[0-9]+\.[0-9]+$")


def _is_tier(value):
    """True only for the ints 1, 2, 3.

    bool is a subclass of int, so True would otherwise pass as tier 1; a
    float 1.0 compares equal to 1 but is not a valid tier either.
    """
    return type(value) is int and value in TIER_BOUNDS


def _check_entry(index, entry, errors):
    """Validate one entry. Returns (tier, topics) with None for unusable parts."""
    where = "entry %d" % index
    if not isinstance(entry, dict):
        errors.append("%s is %s, expected an object" % (where, type(entry).__name__))
        return None, None

    # --- id
    if "id" not in entry:
        errors.append("%s is missing 'id'" % where)
    elif not isinstance(entry["id"], str):
        errors.append("%s 'id' is %s, expected a string"
                      % (where, type(entry["id"]).__name__))
    else:
        where = "entry %d (%s)" % (index, entry["id"])
        if not ID_RE.match(entry["id"]):
            errors.append("%s id is not BOOK.CHAPTER.VERSE" % where)

    # --- unexpected keys
    if isinstance(entry, dict):
        extra = sorted(k for k in entry if k not in ENTRY_KEYS)
        if extra:
            errors.append("%s has unexpected key(s): %s" % (where, ", ".join(map(str, extra))))

    # --- tier
    tier = None
    if "tier" not in entry:
        errors.append("%s is missing 'tier'" % where)
    elif not _is_tier(entry["tier"]):
        errors.append("%s tier %r is not 1, 2 or 3" % (where, entry["tier"]))
    else:
        tier = entry["tier"]

    # --- topics
    topics = None
    if "topics" not in entry:
        errors.append("%s is missing 'topics'" % where)
    elif not isinstance(entry["topics"], list):
        errors.append("%s 'topics' is %s, expected a list"
                      % (where, type(entry["topics"]).__name__))
    else:
        topics = entry["topics"]
        if not topics:
            errors.append("%s has no topics" % where)
        if len(topics) > MAX_TOPICS:
            errors.append("%s has %d topics, at most %d allowed"
                          % (where, len(topics), MAX_TOPICS))
        seen = set()
        dupes = []
        for t in topics:
            if not isinstance(t, str):
                errors.append("%s topic %r is %s, expected a string"
                              % (where, t, type(t).__name__))
                continue
            if t not in TOPICS:
                errors.append("%s has unknown topic '%s'" % (where, t))
            if t in seen and t not in dupes:
                dupes.append(t)
            seen.add(t)
        for t in dupes:
            errors.append("%s repeats topic '%s'" % (where, t))

    return tier, topics


def check_selection(doc):
    errors = []

    if not isinstance(doc, dict):
        return ["document is %s, expected an object" % type(doc).__name__]

    sel = doc.get("selected", [])
    if not isinstance(sel, list):
        return ["'selected' is %s, expected a list" % type(sel).__name__]

    if len(sel) != TOTAL:
        errors.append("expected %d selected verses, found %d" % (TOTAL, len(sel)))

    counts = {t: 0 for t in TOPICS}
    tiers = {1: 0, 2: 0, 3: 0}
    ids = []

    for index, entry in enumerate(sel):
        tier, topics = _check_entry(index, entry, errors)
        if isinstance(entry, dict) and isinstance(entry.get("id"), str):
            ids.append(entry["id"])
        if tier is not None:
            tiers[tier] += 1
        for t in topics or []:
            if t in counts:
                counts[t] += 1

    seen = set()
    dupe_ids = []
    for vid in ids:
        if vid in seen and vid not in dupe_ids:
            dupe_ids.append(vid)
        seen.add(vid)
    if dupe_ids:
        errors.append("duplicate ids in selection: %s" % ", ".join(sorted(dupe_ids)))

    for topic in sorted(TOPICS):
        if counts[topic] < TOPIC_FLOOR:
            errors.append(
                "topic '%s' has %d verses, floor is %d"
                % (topic, counts[topic], TOPIC_FLOOR))

    for tier in sorted(TIER_BOUNDS):
        lo, hi = TIER_BOUNDS[tier]
        if not lo <= tiers[tier] <= hi:
            errors.append("tier %d count %d outside %d-%d" % (tier, tiers[tier], lo, hi))

    return errors


def main():
    path = pathlib.Path(sys.argv[1])
    errors = check_selection(json.loads(path.read_text()))
    for e in errors:
        print(e)
    print("%d error(s)" % len(errors))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
