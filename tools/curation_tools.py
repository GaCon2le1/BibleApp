#!/usr/bin/env python3
"""Helpers for curating a new batch of feed verses: look up candidate ids
against the vendored sources, propose CPDV verse mappings for a human to
review, and find near-duplicate verse texts.

None of these helpers is an authority. Each one produces material for a
human reading pass, the same way cpdv_psalm_offsets.resolve_psalm_verse
does for Psalms.
"""
import json, pathlib, re, sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import load_source_by_index, load_source_by_name
from cpdv_psalm_offsets import resolve_psalm_verse

ROOT = pathlib.Path(__file__).resolve().parent.parent
CURATION = ROOT / "data" / "curation"
SELECTION = CURATION / "selection.json"
CPDV_MAP = CURATION / "cpdv_verse_map.json"
CONTEXTS = CURATION / "contexts.json"

# Words too common to say anything about whether two verses match.
_STOP = set(
    "the and of to a in that is for his he i my you your will be with me not "
    "are was it on as all by from who have has but they them their our us we "
    "o lord god this which shall unto thee thy thou ye hath".split())

# A KJV/BSB verse whose text ends like this usually continues into the next
# verse. Colons and semicolons are fine: KJV ends complete thoughts with them.
_FRAGMENT_ENDINGS = (",", "—", "-")


def _split_id(vid):
    book, chapter, verse = vid.split(".")
    return book, int(chapter), int(verse)


def _content_words(text):
    return {w for w in re.findall(r"[a-z]+", text.lower())
            if w not in _STOP and len(w) > 2}


def overlap(reference, candidate):
    """Share of `reference`'s content words that also appear in `candidate`,
    from 0.0 to 1.0. Asymmetric on purpose: a CPDV verse that merges two
    KJV verses still scores high against the KJV verse it contains."""
    ref = _content_words(reference)
    if not ref:
        return 0.0
    return len(ref & _content_words(candidate)) / len(ref)


class Sources:
    """The three vendored translations, loaded once and indexed by
    (book_id, chapter, verse). CPDV is keyed by its own numbering."""

    def __init__(self):
        self.kjv = load_source_by_index(ROOT / "data" / "source" / "KJV.json")
        self.bsb = load_source_by_index(ROOT / "data" / "source" / "BSB.json")
        self.cpdv = {}
        for book_id, book in load_source_by_name(ROOT / "data" / "source" / "CPDV.json").items():
            for ch in book["chapters"]:
                for v in ch["verses"]:
                    self.cpdv[(book_id, int(ch["chapter"]), int(v["verse"]))] = \
                        re.sub(r"\s+", " ", v["text"]).strip()
        # (kjv_counts, cpdv_counts) in the shape resolve_psalm_verse takes.
        self.psalm_verse_counts = (self._counts(self.kjv), self._counts(self.cpdv))

    @staticmethod
    def _counts(index):
        counts = {}
        for book, chapter, verse in index:
            if book == "PSA":
                counts[chapter] = max(counts.get(chapter, 0), verse)
        return counts


def selected_ids():
    return [e["id"] for e in json.loads(SELECTION.read_text())["selected"]]


def lookup(ids, sources, selected=None):
    """One row per id: its KJV and BSB text plus review flags.

    flags can contain "missing" (no such verse), "selected" (already in the
    feed) and "fragment" (KJV or BSB text looks like it continues into the
    next verse)."""
    selected = set(selected_ids() if selected is None else selected)
    rows = []
    for vid in ids:
        key = _split_id(vid)
        row = {"id": vid, "kjv": sources.kjv.get(key), "bsb": sources.bsb.get(key),
               "flags": []}
        if row["kjv"] is None:
            row["flags"].append("missing")
        else:
            if vid in selected:
                row["flags"].append("selected")
            kjv, bsb = row["kjv"].rstrip(), row["bsb"].rstrip()
            if (kjv.endswith(_FRAGMENT_ENDINGS) or bsb.endswith(_FRAGMENT_ENDINGS)
                    or bsb[:1].islower()):
                row["flags"].append("fragment")
        rows.append(row)
    return rows


def propose_cpdv_ref(vid, sources, window=4, margin=0.15):
    """Propose where `vid`'s content lives in CPDV numbering.

    Starts from the obvious candidate (same chapter:verse, or the Psalms
    resolver for PSA), then searches `window` verses either side in the
    same and neighbouring chapters. A neighbour replaces the candidate only
    when it overlaps the KJV+BSB text by more than `margin` more.

    Returns {"candidate": (ch, v), "best": (ch, v), "candidate_score": f,
    "best_score": f}. Review every id whose best differs from its candidate
    or whose best_score is under 0.3."""
    book, chapter, verse = _split_id(vid)
    reference = sources.bsb[(book, chapter, verse)] + " " + sources.kjv[(book, chapter, verse)]
    if book == "PSA":
        candidate = resolve_psalm_verse(chapter, verse, *sources.psalm_verse_counts)
    else:
        candidate = (chapter, verse)
    candidate_score = overlap(reference, sources.cpdv.get((book,) + candidate, ""))
    best, best_score = candidate, candidate_score
    for dc in (-1, 0, 1):
        for dv in range(-window, window + 1):
            ref = (candidate[0] + dc, candidate[1] + dv)
            text = sources.cpdv.get((book,) + ref)
            if text is None:
                continue
            score = overlap(reference, text)
            if score > best_score + margin:
                best, best_score = ref, score
    return {"candidate": candidate, "best": best,
            "candidate_score": round(candidate_score, 2), "best_score": round(best_score, 2)}


def near_duplicate_pairs(texts, threshold=0.7):
    """Every pair of ids in `texts` ({id: text}) whose texts have a Jaccard
    similarity of at least `threshold`, as (score, id_a, id_b) sorted from
    most to least similar, with id_a < id_b."""
    words = {vid: set(re.findall(r"[a-z]+", t.lower())) for vid, t in texts.items()}
    ids = sorted(words)
    pairs = []
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            wa, wb = words[a], words[b]
            if not wa or not wb:
                continue
            score = len(wa & wb) / len(wa | wb)
            if score >= threshold:
                pairs.append((round(score, 2), a, b))
    return sorted(pairs, reverse=True)


def marker_problems(ids, sources, cpdv_refs):
    """Run each id's KJV, BSB and CPDV text through build_feed's display-text
    guards and return (translation, id, text) for every one that fails: an
    unlisted psalm heading, acrostic marker or trailing Selah, or a table
    entry that no longer matches its text. `cpdv_refs` maps id -> (ch, v)."""
    import build_feed
    checks = (("KJV", build_feed.kjv_display_text_for),
              ("BSB", build_feed.bsb_display_text_for),
              ("CPDV", build_feed.cpdv_display_text_for))
    problems = []
    for vid in ids:
        book, chapter, verse = _split_id(vid)
        texts = {"KJV": sources.kjv[(book, chapter, verse)],
                 "BSB": sources.bsb[(book, chapter, verse)],
                 "CPDV": sources.cpdv[(book,) + tuple(cpdv_refs[vid])]}
        for name, display_text_for in checks:
            try:
                display_text_for(vid, texts[name])
            except SystemExit:
                problems.append((name, vid, texts[name]))
    return problems


def read_staging(staging_dir):
    """Read an expansion's three staging files from `staging_dir`:

    picks.tsv     one verse per line: "ID TIER TOPIC[,TOPIC...]"
    cpdv_refs.json {id: {"chapter": int, "verse": int}}
    contexts.tsv  one per line: "ID<TAB>context sentence"

    Returns (picks, refs, contexts) with picks as [(id, tier, [topics])]."""
    staging_dir = pathlib.Path(staging_dir)
    picks = []
    for line in (staging_dir / "picks.tsv").read_text().splitlines():
        if line.strip():
            vid, tier, topics = line.split()
            picks.append((vid, int(tier), topics.split(",")))
    refs = json.loads((staging_dir / "cpdv_refs.json").read_text())
    contexts = {}
    for line in (staging_dir / "contexts.tsv").read_text().splitlines():
        if line.strip():
            vid, text = line.split("\t")
            contexts[vid] = text
    return picks, refs, contexts


def merge_expansion(selection, cpdv_map, contexts, picks, refs, new_contexts):
    """Append an expansion's staged verses to the three curation documents
    and return the new (selection, cpdv_map, contexts). Raises ValueError
    unless every pick is new and has exactly one ref and one context."""
    pick_ids = [vid for vid, _, _ in picks]
    problems = []
    already = {e["id"] for e in selection["selected"]}
    problems += [f"{vid} is already selected" for vid in pick_ids if vid in already]
    if len(set(pick_ids)) != len(pick_ids):
        problems.append("picks contain duplicate ids")
    for name, staged in (("cpdv_refs", refs), ("contexts", new_contexts)):
        problems += [f"{vid} has no {name} entry" for vid in pick_ids if vid not in staged]
        problems += [f"{vid} in {name} is not a pick" for vid in staged if vid not in pick_ids]
    if problems:
        raise ValueError("; ".join(problems))
    selection = {**selection, "selected": selection["selected"] + [
        {"id": vid, "tier": tier, "topics": topics} for vid, tier, topics in picks]}
    cpdv_map = {**cpdv_map, **{vid: {"chapter": refs[vid]["chapter"], "verse": refs[vid]["verse"]}
                               for vid in pick_ids}}
    contexts = {**contexts, **{vid: new_contexts[vid] for vid in pick_ids}}
    return selection, cpdv_map, contexts


def write_curation(selection, cpdv_map, contexts):
    """Write the curation documents in the formatting they already use."""
    SELECTION.write_text(json.dumps(selection, indent=2, ensure_ascii=False) + "\n")
    CPDV_MAP.write_text(json.dumps(cpdv_map, indent=1, ensure_ascii=False) + "\n")
    CONTEXTS.write_text(json.dumps(contexts, indent=2, ensure_ascii=False) + "\n")


def main():
    """usage: curation_tools.py lookup ID [ID ...]
              curation_tools.py cpdv ID [ID ...]
              curation_tools.py markers CPDV_REFS.json
              curation_tools.py apply STAGING_DIR"""
    if len(sys.argv) == 3 and sys.argv[1] == "apply":
        merged = merge_expansion(
            json.loads(SELECTION.read_text()), json.loads(CPDV_MAP.read_text()),
            json.loads(CONTEXTS.read_text()), *read_staging(sys.argv[2]))
        write_curation(*merged)
        print(f"selection now has {len(merged[0]['selected'])} verses")
        return
    if len(sys.argv) == 3 and sys.argv[1] == "markers":
        refs = json.loads(pathlib.Path(sys.argv[2]).read_text())
        for name, vid, text in marker_problems(list(refs), Sources(),
                                               {k: (v["chapter"], v["verse"]) for k, v in refs.items()}):
            print(f"{name} {vid} | {text}")
        return
    if len(sys.argv) < 3 or sys.argv[1] not in ("lookup", "cpdv"):
        raise SystemExit(main.__doc__)
    sources = Sources()
    ids = sys.argv[2:]
    if sys.argv[1] == "lookup":
        for row in lookup(ids, sources):
            flags = ",".join(row["flags"])
            print(f"{row['id']} [{flags}] | {row['bsb']}")
    else:
        for vid in ids:
            p = propose_cpdv_ref(vid, sources)
            book = vid.split(".")[0]
            review = p["best"] != p["candidate"] or p["best_score"] < 0.3
            print(f"{vid} candidate={p['candidate']} ({p['candidate_score']}) "
                  f"best={p['best']} ({p['best_score']}){'  REVIEW' if review else ''}")
            if review:
                print("   CPDV candidate:", sources.cpdv.get((book,) + p["candidate"], "<MISSING>"))
                if p["best"] != p["candidate"]:
                    print("   CPDV best     :", sources.cpdv.get((book,) + p["best"]))


if __name__ == "__main__":
    main()
