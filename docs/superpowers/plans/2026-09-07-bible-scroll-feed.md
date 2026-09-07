# Bible Scroll Feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an iOS app where a seeker learns the Bible by scrolling a vertical feed of 400 famous KJV verses, each carrying a plain-English explanation, ranked by chosen topics and never repeated.

**Architecture:** Three layers. Content is static JSON in the app bundle, generated and validated by Python tooling that reads a vendored KJV source. The ranking engine lives in a local Swift package, `BibleFeedKit`, so it can be tested headless with `swift test` — the Xcode project has no unit test target. SwiftUI views hold no ordering logic and read from the engine.

**Tech Stack:** Swift 6.3, SwiftUI, SwiftData, Swift Testing (`import Testing`), Xcode 26.4, Python 3 for content tooling.

## Global Constraints

- Xcode project deployment target is **iOS 26.4**; Xcode 26.4; Swift 6.3.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup`. Any file placed under `BibleApp/BibleApp/` joins the app target automatically. **Never hand-edit `project.pbxproj`** except for the one package-link step in Task 9.
- `BibleFeedKit` must import neither SwiftUI nor SwiftData.
- Verse `text` is KJV verbatim, extracted programmatically from `data/source/KJV.json`. **Never type verse text by hand.**
- Verse `displayText` is what the UI renders. It is `text` with any leading psalm
  superscription, Hebrew acrostic letter, or trailing musical marker removed, derived
  programmatically and validated as an **exact contiguous substring of `text`**.
  Equal to `text` for most verses.
  Source spelling is preserved otherwise, including "The Lord" rather than "LORD".
- `context` is 60–220 characters inclusive, plain modern English, no theological jargon.
- `topics` is a non-empty subset of exactly these twelve, lowercase:
  `anxiety hope love forgiveness strength guidance peace doubt purpose gratitude grief worth`
- `tier` is 1, 2 or 3. Target distribution across the 400: ~100 tier 1, ~200 tier 2, ~100 tier 3.
- Python is **3.9.6, system `/usr/bin/python3`, and pytest is NOT installed**.
  Python tests use the stdlib `unittest` module. Do not add third-party
  Python dependencies; do not `pip install` anything.
- Every task ends with a commit. Work happens on branch `design/scroll-feed`.

---

## File Structure

**Content tooling and data (not shipped in the app):**

| Path | Responsibility |
|---|---|
| `data/source/KJV.json` | Vendored KJV, 66 books / 31,102 verses. Read-only source of truth for verse text. Already in place. |
| `data/candidates/key_verses.json` | The 1,189 one-per-chapter verses. Candidate pool for selection. Already in place. |
| `data/curation/selection.json` | Which 400 verses ship, with `tier` and `topics`. Hand-curated, machine-validated. |
| `data/curation/contexts.json` | `id` → `context` string, written in batches. |
| `tools/validate_feed.py` | Single validator for the built feed file. Exit code 1 on any violation. |
| `tools/build_feed.py` | Joins source + selection + contexts into the shipped JSON. |

**Shipped app content:**

| Path | Responsibility |
|---|---|
| `BibleApp/BibleApp/Resources/bible_books.json` | 66 books metadata. Already in place, unchanged. |
| `BibleApp/BibleApp/Resources/feed_verses.json` | The 400 feed entries. Generated, never edited by hand. |

**Engine package:**

| Path | Responsibility |
|---|---|
| `packages/BibleFeedKit/Package.swift` | Package manifest. |
| `packages/BibleFeedKit/Sources/BibleFeedKit/Verse.swift` | `Verse`, `Topic`, `Tier` value types and decoding. |
| `packages/BibleFeedKit/Sources/BibleFeedKit/FeedEngine.swift` | Ranking, no-repeat, pool exhaustion. |
| `packages/BibleFeedKit/Sources/BibleFeedKit/StreakCalculator.swift` | Streak arithmetic over a set of dates. |
| `packages/BibleFeedKit/Tests/BibleFeedKitTests/*.swift` | Headless tests. |

**App:**

| Path | Responsibility |
|---|---|
| `BibleApp/BibleApp/Content/ContentStore.swift` | Loads and decodes bundle JSON once at launch. |
| `BibleApp/BibleApp/State/UserState.swift` | SwiftData model: seen, saved, topics, streak dates. |
| `BibleApp/BibleApp/Views/OnboardingView.swift` | First-run topic picker. |
| `BibleApp/BibleApp/Views/FeedView.swift` | Vertical paging container. |
| `BibleApp/BibleApp/Views/VerseCard.swift` | One card. |
| `BibleApp/BibleApp/Views/LibraryView.swift` | Saved verses. |
| `BibleApp/BibleApp/ContentView.swift` | Root router: onboarding vs feed. Modify existing. |

---

## Phase 1 — Content

### Task 1: Feed validator

Build the validator before the data it validates, so every later batch is checked the moment it is written.

**Files:**
- Create: `tools/validate_feed.py`
- Create: `tools/fixtures/valid_feed.json`
- Create: `tools/fixtures/invalid_feed.json`
- Create: `tools/test_validate_feed.py`

**Interfaces:**
- Consumes: `data/source/KJV.json` (already vendored)
- Produces: `validate_feed(path) -> list[str]` returning human-readable error strings, empty when valid. CLI entry point `python3 tools/validate_feed.py <feed.json>` exits 1 when errors exist.

- [ ] **Step 1: Write the failing test**

Create `tools/test_validate_feed.py`:

```python
import pathlib, subprocess, sys, unittest
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from validate_feed import validate_feed

FIX = pathlib.Path(__file__).parent / "fixtures"
ROOT = pathlib.Path(__file__).resolve().parent.parent


class ValidateFeedTests(unittest.TestCase):
    def test_valid_feed_has_no_errors(self):
        self.assertEqual(validate_feed(FIX / "valid_feed.json"), [])

    def test_catches_wrong_verse_text(self):
        errs = validate_feed(FIX / "invalid_feed.json")
        self.assertTrue(any("text does not match KJV" in e for e in errs), errs)

    def test_catches_bad_topic(self):
        errs = validate_feed(FIX / "invalid_feed.json")
        self.assertTrue(any("unknown topic" in e for e in errs), errs)

    def test_catches_context_too_short(self):
        errs = validate_feed(FIX / "invalid_feed.json")
        self.assertTrue(any("context length" in e for e in errs), errs)

    def test_cli_exits_nonzero_on_invalid(self):
        r = subprocess.run([sys.executable, "tools/validate_feed.py",
                            str(FIX / "invalid_feed.json")],
                           cwd=ROOT, capture_output=True)
        self.assertEqual(r.returncode, 1)


if __name__ == "__main__":
    unittest.main()
```

Create `tools/fixtures/valid_feed.json`:

```json
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "translation": "KJV",
  "verses": [
    {
      "id": "JHN.3.16", "reference": "John 3:16",
      "book": "JHN", "chapter": 3, "verse": 16,
      "text": "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.",
      "context": "Jesus said this at night to a religious leader who came to him in secret, afraid of being seen asking questions.",
      "topics": ["love", "hope"], "tier": 1
    }
  ]
}
```

Create `tools/fixtures/invalid_feed.json` — one entry breaking three rules at once:

```json
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "translation": "KJV",
  "verses": [
    {
      "id": "JHN.3.16", "reference": "John 3:16",
      "book": "JHN", "chapter": 3, "verse": 16,
      "text": "For God so loved the world that he gave his only Son.",
      "context": "Too short.",
      "topics": ["love", "prosperity"], "tier": 1
    }
  ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && python3 -m unittest discover -s tools -p 'test_validate_feed.py' -v`
Expected: ERROR — `ModuleNotFoundError: No module named 'validate_feed'`

- [ ] **Step 3: Write minimal implementation**

Create `tools/validate_feed.py`:

```python
#!/usr/bin/env python3
"""Validate a built feed_verses.json against the vendored KJV source."""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "source" / "KJV.json"
BOOKS = ROOT / "BibleApp" / "BibleApp" / "Resources" / "bible_books.json"

TOPICS = {"anxiety", "hope", "love", "forgiveness", "strength", "guidance",
          "peace", "doubt", "purpose", "gratitude", "grief", "worth"}
CONTEXT_MIN, CONTEXT_MAX = 60, 220


def _kjv_index():
    """Map (bookId, chapter, verse) -> verse text, using canonical book order."""
    kjv = json.loads(SOURCE.read_text())
    meta = json.loads(BOOKS.read_text())
    prot = [b for b in meta["books"] if b["canon"] == "protestant"]
    index = {}
    for i, book in enumerate(prot):
        src = kjv["books"][i]
        if len(src["chapters"]) != book["chapters"]:
            raise SystemExit(f"source/book mismatch at {book['id']}")
        for ch in src["chapters"]:
            for v in ch["verses"]:
                key = (book["id"], int(ch["chapter"]), int(v["verse"]))
                index[key] = re.sub(r"\s+", " ", v["text"]).strip()
    return index


def validate_feed(path):
    errors = []
    doc = json.loads(pathlib.Path(path).read_text())
    index = _kjv_index()
    seen_ids = set()

    for entry in doc.get("verses", []):
        vid = entry.get("id", "<missing id>")

        if vid in seen_ids:
            errors.append(f"{vid}: duplicate id")
        seen_ids.add(vid)

        key = (entry.get("book"), entry.get("chapter"), entry.get("verse"))
        if key not in index:
            errors.append(f"{vid}: no such verse in KJV source")
        elif entry.get("text") != index[key]:
            errors.append(f"{vid}: text does not match KJV source")

        if vid != f"{key[0]}.{key[1]}.{key[2]}":
            errors.append(f"{vid}: id does not match book/chapter/verse fields")

        unknown = set(entry.get("topics", [])) - TOPICS
        if unknown:
            errors.append(f"{vid}: unknown topic {sorted(unknown)}")
        if not entry.get("topics"):
            errors.append(f"{vid}: topics must not be empty")

        if entry.get("tier") not in (1, 2, 3):
            errors.append(f"{vid}: tier must be 1, 2 or 3")

        ctx = entry.get("context", "")
        if not CONTEXT_MIN <= len(ctx) <= CONTEXT_MAX:
            errors.append(
                f"{vid}: context length {len(ctx)} outside {CONTEXT_MIN}-{CONTEXT_MAX}")

    return errors


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate_feed.py <feed.json>")
    errors = validate_feed(sys.argv[1])
    for e in errors:
        print(e)
    print(f"{len(errors)} error(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && python3 -m unittest discover -s tools -p 'test_validate_feed.py' -v`
Expected: `OK`, 5 tests run

- [ ] **Step 5: Commit**

```bash
git add tools/
git commit -m "Add feed validator with fixture tests"
```

---

### Task 2: Select the 400 verses

**Files:**
- Create: `data/curation/selection.json`
- Create: `tools/check_selection.py`
- Create: `tools/test_check_selection.py`

**Interfaces:**
- Consumes: `data/candidates/key_verses.json` for candidate ids and reference text
- Produces: `data/curation/selection.json`, shape `{"selected": [{"id": "JHN.3.16", "tier": 1, "topics": ["love","hope"]}, ...]}`. Task 4 reads this.

The candidate pool holds 1,189 verses. Roughly 100–150 of them are genealogies, temple measurements and territory lists that must not ship. Selection is a judgement call per verse; the checker below enforces only what a machine can know.

- [ ] **Step 1: Write the failing test**

Create `tools/test_check_selection.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && python3 -m unittest discover -s tools -p 'test_check_selection.py' -v`
Expected: ERROR — `ModuleNotFoundError: No module named 'check_selection'`

- [ ] **Step 3: Write minimal implementation**

Create `tools/check_selection.py`:

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && python3 -m unittest discover -s tools -p 'test_check_selection.py' -v`
Expected: `OK`, 3 tests run

- [ ] **Step 5: Curate the selection**

Write `data/curation/selection.json` by working through `data/candidates/key_verses.json` book by book. Rules:

- Exclude every verse from a genealogy, census, territory list, temple measurement or offering schedule. In practice this removes most of 1 Chronicles 1–9, Numbers 26, Joshua 13–21 and Ezekiel 40–42.
- Where a chapter holds several famous verses and the candidate file picked only one, add the others. Psalm 23, Psalm 91, Isaiah 40, John 14, Romans 8, 1 Corinthians 13 and Philippians 4 each justify three or more entries.
- Tier by the spec's criteria: tier 1 is recognisable to someone who has never attended church.
- Give each verse one to three topics. A verse with no honest topic fit does not belong in the 400.

Work in book order and append to the file as you go, so progress is inspectable.

- [ ] **Step 6: Run the checker**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && python3 tools/check_selection.py data/curation/selection.json`
Expected: `0 error(s)`, exit 0

- [ ] **Step 7: Commit**

```bash
git add tools/check_selection.py tools/test_check_selection.py data/curation/selection.json
git commit -m "Select 400 feed verses with tier and topic assignments"
```

---

### Task 3: Write the 400 context lines

**Files:**
- Create: `data/curation/contexts.json`

**Interfaces:**
- Consumes: `data/curation/selection.json` ids
- Produces: `data/curation/contexts.json`, shape `{"JHN.3.16": "Jesus said this at night to...", ...}`. Task 4 reads this.

Each line answers: who is speaking, to whom, in what situation. Plain modern English. No "thus", no "covenant", no "atonement". 60–220 characters.

Good: `Paul wrote this from a prison cell, to a church that had just sent him money while he was locked up.`

Bad: `This verse teaches us about God's providential care.` — explains nothing, and would be true of half the file.

- [ ] **Step 1: Write batch 1 (ids 1–50)**

Append the first fifty entries to `data/curation/contexts.json`, in selection order.

- [ ] **Step 2: Check batch 1 lengths**

Run:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && python3 -c "
import json
d=json.load(open('data/curation/contexts.json'))
bad=[(k,len(v)) for k,v in d.items() if not 60<=len(v)<=220]
print(f'{len(d)} contexts, {len(bad)} out of range')
[print(' ',k,n) for k,n in bad[:10]]
"
```
Expected: `50 contexts, 0 out of range`

- [ ] **Step 3: Commit batch 1**

```bash
git add data/curation/contexts.json
git commit -m "Add context lines for feed verses 1-50"
```

- [ ] **Step 4: Repeat steps 1–3 for batches 2 through 8**

Batches cover ids 51–100, 101–150, 151–200, 201–250, 251–300, 301–350, 351–400. Run the length check after each batch and commit each batch separately. Expected after batch 8: `400 contexts, 0 out of range`.

---

### Task 4: Build the shipped feed file

**Files:**
- Create: `tools/build_feed.py`
- Create: `BibleApp/BibleApp/Resources/feed_verses.json` (generated)

**Interfaces:**
- Consumes: `data/source/KJV.json`, `data/curation/selection.json`, `data/curation/contexts.json`
- Produces: `BibleApp/BibleApp/Resources/feed_verses.json`, the exact shape `tools/fixtures/valid_feed.json` demonstrates. Task 5 decodes it.

- [ ] **Step 1: Extend the validator with the displayText rule**

`displayText` is what the card renders; `text` stays KJV verbatim. The rule that
makes the pair trustworthy is that `displayText` must be an **exact contiguous
substring** of `text` — so no wording can be invented in the gap between them.
Substring rather than suffix, because most strips remove a leading superscription
but `HAB.3.19` removes a trailing colophon instead.

First add these two tests to `tools/test_validate_feed.py`, inside
`class ValidateFeedTests`:

```python
    def test_catches_display_text_not_in_text(self):
        errs = validate_feed(FIX / "invalid_feed.json")
        self.assertTrue(
            any("displayText is not part of text" in e for e in errs), errs)

    def _feed_with(self, mutate):
        import json, tempfile, os
        doc = json.loads((FIX / "valid_feed.json").read_text())
        mutate(doc["verses"][0])
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(doc, f)
            return f.name

    def test_accepts_stripped_leading_superscription(self):
        # Mutating JHN.3.16 with a fabricated prefix would fail the
        # unrelated, pre-existing KJV-verbatim check (the fixture's text
        # would no longer match its real KJV source). PSA.23.1 genuinely
        # carries this superscription in the KJV source, so both checks see
        # legitimate data and only the displayText logic is under test.
        import os

        def mutate(entry):
            entry["id"] = "PSA.23.1"
            entry["reference"] = "Psalms 23:1"
            entry["book"] = "PSA"
            entry["chapter"] = 23
            entry["verse"] = 1
            entry["text"] = "A Psalm of David. The Lord is my shepherd; I shall not want."
            entry["displayText"] = "The Lord is my shepherd; I shall not want."

        path = self._feed_with(mutate)
        try:
            self.assertEqual(validate_feed(path), [])
        finally:
            os.unlink(path)

    def test_accepts_stripped_trailing_colophon(self):
        # Same reasoning as above: HAB.3.19 genuinely ends in this colophon
        # in the KJV source, so this is real data, not a fabricated mutation.
        import os

        def mutate(entry):
            entry["id"] = "HAB.3.19"
            entry["reference"] = "Habakkuk 3:19"
            entry["book"] = "HAB"
            entry["chapter"] = 3
            entry["verse"] = 19
            entry["text"] = (
                "The Lord God is my strength, and he will make my feet like "
                "hinds’ feet, and he will make me to walk upon mine high "
                "places. To the chief singer on my stringed instruments.")
            entry["displayText"] = (
                "The Lord God is my strength, and he will make my feet like "
                "hinds’ feet, and he will make me to walk upon mine high "
                "places.")

        path = self._feed_with(mutate)
        try:
            self.assertEqual(validate_feed(path), [])
        finally:
            os.unlink(path)

    def test_catches_missing_display_text(self):
        import os

        def mutate(entry):
            del entry["displayText"]

        path = self._feed_with(mutate)
        try:
            self.assertTrue(
                any("displayText is missing" in e for e in validate_feed(path)))
        finally:
            os.unlink(path)
```

Add `"displayText"` to both fixtures. In `tools/fixtures/valid_feed.json` give it
the same value as `text`. In `tools/fixtures/invalid_feed.json` set it to
`"Something never found in the verse."` so it violates the substring rule.

Then add this block to `validate_feed()` in `tools/validate_feed.py`, inside the
per-entry loop, immediately after the existing `text` comparison:

```python
        display = entry.get("displayText")
        if display is None:
            errors.append(f"{vid}: displayText is missing")
        elif not isinstance(display, str) or not display.strip():
            errors.append(f"{vid}: displayText is empty")
        elif display not in entry.get("text", ""):
            # Substring, not suffix: most strips remove a leading superscription,
            # but HAB.3.19 removes a trailing colophon.
            errors.append(f"{vid}: displayText is not part of text")
```

- [ ] **Step 2: Run the validator tests**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_validate_feed.py' -v`
Expected: `OK`, 15 tests run

- [ ] **Step 3: Write the builder**

Create `tools/build_feed.py`:

```python
#!/usr/bin/env python3
"""Join KJV source, selection and contexts into the shipped feed file."""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "BibleApp" / "BibleApp" / "Resources" / "feed_verses.json"
CONTENT_VERSION = "2026-09-07.1"

# The KJV source stores psalm superscriptions and Hebrew acrostic letters inside
# the text of verse 1. These are the exact prefixes to remove for display, keyed
# by verse id. Listed explicitly rather than matched by pattern, so the builder
# can never over-strip. Verified against data/source/KJV.json.
SUPERSCRIPTIONS = {
    "PSA.19.1": "To the chief Musician, A Psalm of David. ",
    "PSA.22.1": "To the chief Musician upon Aijeleth Shahar, A Psalm of David. ",
    "PSA.23.1": "A Psalm of David. ",
    "PSA.27.1": "A Psalm of David. ",
    "PSA.46.1": "To the chief Musician for the sons of Korah, A Song upon Alamoth. ",
    "PSA.119.105": "\u05e0 NUN. ",
    "PSA.121.1": "A Song of degrees. ",
    "PSA.133.1": "A Song of degrees of David. ",
}

# Some verses carry a trailing musical or liturgical marker rather than a
# leading heading. Same explicit-table treatment, keyed by verse id.
TRAILING_MARKERS = {
    "HAB.3.19": " To the chief singer on my stringed instruments.",
    "PSA.77.9": " Selah.",
}

# Any selected verse whose text looks like it carries a heading but is not in
# SUPERSCRIPTIONS is a build error, not something to strip silently.
HEADING_HINT = re.compile(
    r"^(?:[^.]{0,120}?(?:Psalm|Song|Maschil|Michtam|Prayer|chief Musician|degrees)"
    r"[^.]{0,120}?\.\s)|^(?:[^\x00-\x7F][^.]{0,20}\.\s)"
)


def display_text_for(vid, text):
    """Return the card-facing text: `text` minus any known superscription."""
    prefix = SUPERSCRIPTIONS.get(vid)
    if prefix is not None:
        if not text.startswith(prefix):
            raise SystemExit(
                f"{vid}: SUPERSCRIPTIONS prefix does not match source text")
        stripped = text[len(prefix):].strip()
        if not stripped:
            raise SystemExit(f"{vid}: stripping the superscription empties the verse")
        return stripped
    if HEADING_HINT.match(text):
        raise SystemExit(
            f"{vid}: text looks like it carries a heading but is not in "
            f"SUPERSCRIPTIONS — add it explicitly or confirm it is verse content")
    suffix = TRAILING_MARKERS.get(vid)
    if suffix is not None:
        if not text.endswith(suffix):
            raise SystemExit(
                f"{vid}: TRAILING_MARKERS suffix does not match source text")
        return text[:-len(suffix)].strip()
    # "Selah" is a liturgical marker, never verse content. Catch any that were
    # not listed rather than shipping one onto a card.
    if text.rstrip().endswith("Selah."):
        raise SystemExit(
            f"{vid}: text ends with 'Selah.' but is not in TRAILING_MARKERS")
    return text


def main():
    kjv = json.loads((ROOT / "data/source/KJV.json").read_text())
    meta = json.loads((ROOT / "BibleApp/BibleApp/Resources/bible_books.json").read_text())
    selection = json.loads((ROOT / "data/curation/selection.json").read_text())["selected"]
    contexts = json.loads((ROOT / "data/curation/contexts.json").read_text())

    prot = [b for b in meta["books"] if b["canon"] == "protestant"]
    names = {b["id"]: b["name"] for b in prot}
    text = {}
    for i, book in enumerate(prot):
        for ch in kjv["books"][i]["chapters"]:
            for v in ch["verses"]:
                text[(book["id"], int(ch["chapter"]), int(v["verse"]))] = \
                    re.sub(r"\s+", " ", v["text"]).strip()

    verses = []
    for entry in selection:
        book, chapter, verse = entry["id"].split(".")
        chapter, verse = int(chapter), int(verse)
        if entry["id"] not in contexts:
            raise SystemExit(f"missing context for {entry['id']}")
        verse_text = text[(book, chapter, verse)]
        verses.append({
            "id": entry["id"],
            "reference": f"{names[book]} {chapter}:{verse}",
            "book": book, "chapter": chapter, "verse": verse,
            "text": verse_text,
            "displayText": display_text_for(entry["id"], verse_text),
            "context": contexts[entry["id"]],
            "topics": entry["topics"],
            "tier": entry["tier"],
        })

    doc = {"schemaVersion": 1, "contentVersion": CONTENT_VERSION,
           "translation": "KJV", "verses": verses}
    OUT.write_text(json.dumps(doc, indent=1, ensure_ascii=False))
    print(f"wrote {len(verses)} verses to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Build**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && python3 tools/build_feed.py`
Expected: `wrote 400 verses to BibleApp/BibleApp/Resources/feed_verses.json`

- [ ] **Step 5: Validate the built file**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && python3 tools/validate_feed.py BibleApp/BibleApp/Resources/feed_verses.json`
Expected: `0 error(s)`, exit 0

- [ ] **Step 6: Commit**

```bash
git add tools/ BibleApp/BibleApp/Resources/feed_verses.json
git commit -m "Build validated 400-verse feed file with displayText"
```

---

## Phase 2 — Engine

### Task 5: Package scaffold and value types

**Files:**
- Create: `packages/BibleFeedKit/Package.swift`
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/Verse.swift`
- Test: `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseTests.swift`

**Interfaces:**
- Consumes: the JSON shape produced by Task 4
- Produces: `Topic` (RawRepresentable enum, 12 cases), `Verse` (struct with `id: String`, `reference: String`, `book: String`, `chapter: Int`, `verse: Int`, `text: String`, `displayText: String`, `context: String`, `topics: [Topic]`, `tier: Int`), `FeedContent` (struct with `schemaVersion: Int`, `contentVersion: String`, `translation: String`, `verses: [Verse]`). Tasks 6, 7, 8 and 9 all use these.

- [ ] **Step 1: Create the package skeleton**

Run:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && mkdir -p packages/BibleFeedKit && cd packages/BibleFeedKit && swift package init --type library --name BibleFeedKit
```

Then replace `packages/BibleFeedKit/Package.swift` with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BibleFeedKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "BibleFeedKit", targets: ["BibleFeedKit"])
    ],
    targets: [
        .target(name: "BibleFeedKit"),
        .testTarget(name: "BibleFeedKitTests", dependencies: ["BibleFeedKit"])
    ]
)
```

Delete the generated placeholder source and test:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && rm -f packages/BibleFeedKit/Sources/BibleFeedKit/BibleFeedKit.swift packages/BibleFeedKit/Tests/BibleFeedKitTests/BibleFeedKitTests.swift
```

- [ ] **Step 2: Write the failing test**

Create `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

private let sampleJSON = """
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "translation": "KJV",
  "verses": [
    {
      "id": "JHN.3.16", "reference": "John 3:16",
      "book": "JHN", "chapter": 3, "verse": 16,
      "text": "A Psalm of David. For God so loved the world",
      "displayText": "For God so loved the world",
      "context": "Jesus said this at night to a religious leader.",
      "topics": ["love", "hope"], "tier": 1
    }
  ]
}
""".data(using: .utf8)!

@Test func decodesFeedContent() throws {
    let content = try JSONDecoder().decode(FeedContent.self, from: sampleJSON)
    #expect(content.schemaVersion == 1)
    #expect(content.verses.count == 1)
    #expect(content.verses[0].id == "JHN.3.16")
    #expect(content.verses[0].topics == [.love, .hope])
    #expect(content.verses[0].tier == 1)
    // displayText is the card-facing form; text keeps the source prefix.
    #expect(content.verses[0].displayText == "For God so loved the world")
    #expect(content.verses[0].text.hasSuffix(content.verses[0].displayText))
}

@Test func topicHasTwelveCases() {
    #expect(Topic.allCases.count == 12)
}

@Test func unknownTopicFailsDecoding() {
    let bad = """
    {"schemaVersion":1,"contentVersion":"t","translation":"KJV","verses":[
      {"id":"A.1.1","reference":"A 1:1","book":"A","chapter":1,"verse":1,
       "text":"x","displayText":"x","context":"y","topics":["prosperity"],"tier":1}]}
    """.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(FeedContent.self, from: bad)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: FAIL — `cannot find 'FeedContent' in scope`

- [ ] **Step 4: Write minimal implementation**

Create `packages/BibleFeedKit/Sources/BibleFeedKit/Verse.swift`:

```swift
import Foundation

public enum Topic: String, Codable, CaseIterable, Sendable, Hashable {
    case anxiety, hope, love, forgiveness, strength, guidance
    case peace, doubt, purpose, gratitude, grief, worth
}

public struct Verse: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let reference: String
    public let book: String
    public let chapter: Int
    public let verse: Int
    public let text: String
    public let displayText: String
    public let context: String
    public let topics: [Topic]
    public let tier: Int

    public init(id: String, reference: String, book: String, chapter: Int,
                verse: Int, text: String, displayText: String, context: String,
                topics: [Topic], tier: Int) {
        self.id = id
        self.reference = reference
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.text = text
        self.displayText = displayText
        self.context = context
        self.topics = topics
        self.tier = tier
    }
}

public struct FeedContent: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let translation: String
    public let verses: [Verse]
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: PASS, 3 tests

- [ ] **Step 6: Commit**

```bash
git add packages/BibleFeedKit
git commit -m "Add BibleFeedKit package with Verse and Topic types"
```

---

### Task 6: Ranking

**Files:**
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/SeededGenerator.swift`
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/FeedEngine.swift`
- Test: `packages/BibleFeedKit/Tests/BibleFeedKitTests/FeedEngineTests.swift`

**Interfaces:**
- Consumes: `Verse`, `Topic` from Task 5
- Produces: `FeedEngine.init(verses: [Verse])`, `FeedEngine.queue(selectedTopics: Set<Topic>, seen: Set<String>, saved: Set<String>, seed: UInt64) -> FeedQueue`, and `FeedQueue` with `verses: [Verse]` and `isReplay: Bool`. Task 7 extends the same method; Task 9 calls it.

Scoring per the spec: tier 1 scores 3, tier 2 scores 2, tier 3 scores 1, plus 2 when the verse carries a selected topic. Verses are sorted by score descending, and shuffled within each score band so two sessions do not open identically.

- [ ] **Step 1: Write the failing test**

Create `packages/BibleFeedKit/Tests/BibleFeedKitTests/FeedEngineTests.swift`:

```swift
import Testing
@testable import BibleFeedKit

private func verse(_ id: String, tier: Int, topics: [Topic] = [.hope]) -> Verse {
    Verse(id: id, reference: id, book: "PSA", chapter: 1, verse: 1,
          text: "text", displayText: "text", context: "context",
          topics: topics, tier: tier)
}

@Test func higherTierComesFirst() {
    let engine = FeedEngine(verses: [
        verse("c", tier: 3), verse("a", tier: 1), verse("b", tier: 2)
    ])
    let q = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 1)
    #expect(q.verses.map(\.id) == ["a", "b", "c"])
    #expect(q.isReplay == false)
}

@Test func selectedTopicOutranksTier() {
    // tier 3 with a selected topic scores 1 + 2 = 3, beating tier 2 scoring 2.
    let engine = FeedEngine(verses: [
        verse("tier2", tier: 2, topics: [.grief]),
        verse("tier3match", tier: 3, topics: [.anxiety])
    ])
    let q = engine.queue(selectedTopics: [.anxiety], seen: [], saved: [], seed: 1)
    #expect(q.verses.map(\.id) == ["tier3match", "tier2"])
}

@Test func sameSeedGivesSameOrder() {
    let verses = (1...20).map { verse("v\($0)", tier: 2) }
    let engine = FeedEngine(verses: verses)
    let a = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 42)
    let b = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 42)
    #expect(a.verses.map(\.id) == b.verses.map(\.id))
}

@Test func differentSeedsReorderWithinBand() {
    let verses = (1...20).map { verse("v\($0)", tier: 2) }
    let engine = FeedEngine(verses: verses)
    let a = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 1)
    let b = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 2)
    #expect(a.verses.map(\.id) != b.verses.map(\.id))
}

@Test func shufflingLosesNoVerses() {
    let verses = (1...50).map { verse("v\($0)", tier: ($0 % 3) + 1) }
    let engine = FeedEngine(verses: verses)
    let q = engine.queue(selectedTopics: [.hope], seen: [], saved: [], seed: 7)
    #expect(Set(q.verses.map(\.id)) == Set(verses.map(\.id)))
    #expect(q.verses.count == 50)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: FAIL — `cannot find 'FeedEngine' in scope`

- [ ] **Step 3: Write the seeded generator**

Create `packages/BibleFeedKit/Sources/BibleFeedKit/SeededGenerator.swift`:

```swift
/// SplitMix64. Deterministic, so feed ordering is reproducible in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
```

- [ ] **Step 4: Write minimal implementation**

Create `packages/BibleFeedKit/Sources/BibleFeedKit/FeedEngine.swift`:

```swift
import Foundation

public struct FeedQueue: Equatable, Sendable {
    public let verses: [Verse]
    public let isReplay: Bool

    public init(verses: [Verse], isReplay: Bool) {
        self.verses = verses
        self.isReplay = isReplay
    }
}

public struct FeedEngine: Sendable {
    private let verses: [Verse]

    public init(verses: [Verse]) {
        self.verses = verses
    }

    /// Score is tier weight plus a bonus when the verse matches a chosen topic.
    /// Tier 1 weighs 3, tier 2 weighs 2, tier 3 weighs 1.
    static func score(_ verse: Verse, selectedTopics: Set<Topic>) -> Int {
        let tierWeight = max(0, 4 - verse.tier)
        let topicBonus = verse.topics.contains(where: selectedTopics.contains) ? 2 : 0
        return tierWeight + topicBonus
    }

    public func queue(selectedTopics: Set<Topic>,
                      seen: Set<String>,
                      saved: Set<String>,
                      seed: UInt64) -> FeedQueue {
        let unseen = verses.filter { !seen.contains($0.id) }
        return FeedQueue(verses: rank(unseen, selectedTopics: selectedTopics, seed: seed),
                         isReplay: false)
    }

    private func rank(_ pool: [Verse],
                      selectedTopics: Set<Topic>,
                      seed: UInt64) -> [Verse] {
        var generator = SeededGenerator(seed: seed)
        var bands: [Int: [Verse]] = [:]
        for verse in pool {
            bands[Self.score(verse, selectedTopics: selectedTopics), default: []].append(verse)
        }
        return bands.keys.sorted(by: >).flatMap { key in
            bands[key]!.shuffled(using: &generator)
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: PASS, 8 tests

- [ ] **Step 6: Commit**

```bash
git add packages/BibleFeedKit
git commit -m "Add FeedEngine ranking with seeded in-band shuffle"
```

---

### Task 7: No-repeat and pool exhaustion

**Files:**
- Modify: `packages/BibleFeedKit/Sources/BibleFeedKit/FeedEngine.swift`
- Modify: `packages/BibleFeedKit/Tests/BibleFeedKitTests/FeedEngineTests.swift`

**Interfaces:**
- Consumes: `FeedEngine.queue` from Task 6
- Produces: the same signature, now returning `isReplay: true` with saved verses first once the unseen pool empties. Task 9 branches on `isReplay` to show the milestone screen.

- [ ] **Step 1: Write the failing test**

Append to `packages/BibleFeedKit/Tests/BibleFeedKitTests/FeedEngineTests.swift`:

```swift
@Test func seenVersesAreExcluded() {
    let engine = FeedEngine(verses: [
        verse("a", tier: 1), verse("b", tier: 1), verse("c", tier: 1)
    ])
    let q = engine.queue(selectedTopics: [], seen: ["a", "c"], saved: [], seed: 1)
    #expect(q.verses.map(\.id) == ["b"])
    #expect(q.isReplay == false)
}

@Test func exhaustedPoolReplaysWithSavedFirst() {
    let engine = FeedEngine(verses: [
        verse("a", tier: 3), verse("b", tier: 1), verse("c", tier: 2)
    ])
    let q = engine.queue(selectedTopics: [], seen: ["a", "b", "c"],
                         saved: ["a"], seed: 1)
    #expect(q.isReplay == true)
    #expect(q.verses.first?.id == "a")
    #expect(q.verses.count == 3)
}

@Test func exhaustedPoolWithNoSavedStillReplaysEverything() {
    let engine = FeedEngine(verses: [verse("a", tier: 1), verse("b", tier: 2)])
    let q = engine.queue(selectedTopics: [], seen: ["a", "b"], saved: [], seed: 1)
    #expect(q.isReplay == true)
    #expect(Set(q.verses.map(\.id)) == ["a", "b"])
}

@Test func emptyLibraryProducesEmptyQueue() {
    let engine = FeedEngine(verses: [])
    let q = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 1)
    #expect(q.verses.isEmpty)
    #expect(q.isReplay == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: FAIL — `exhaustedPoolReplaysWithSavedFirst` fails, `isReplay` is false and `verses` is empty

- [ ] **Step 3: Write minimal implementation**

Replace the `queue` method in `packages/BibleFeedKit/Sources/BibleFeedKit/FeedEngine.swift` with:

```swift
    public func queue(selectedTopics: Set<Topic>,
                      seen: Set<String>,
                      saved: Set<String>,
                      seed: UInt64) -> FeedQueue {
        let unseen = verses.filter { !seen.contains($0.id) }
        if !unseen.isEmpty || verses.isEmpty {
            return FeedQueue(verses: rank(unseen, selectedTopics: selectedTopics, seed: seed),
                             isReplay: false)
        }

        // Every verse has been seen. Reopen the queue, saved verses first.
        let savedVerses = verses.filter { saved.contains($0.id) }
        let rest = verses.filter { !saved.contains($0.id) }
        let replay = rank(savedVerses, selectedTopics: selectedTopics, seed: seed)
            + rank(rest, selectedTopics: selectedTopics, seed: seed &+ 1)
        return FeedQueue(verses: replay, isReplay: true)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: PASS, 12 tests

- [ ] **Step 5: Commit**

```bash
git add packages/BibleFeedKit
git commit -m "Exclude seen verses and replay saved first when pool empties"
```

---

### Task 8: Streak

**Files:**
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/StreakCalculator.swift`
- Test: `packages/BibleFeedKit/Tests/BibleFeedKitTests/StreakCalculatorTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: `StreakCalculator.currentStreak(activeDays: Set<Date>, today: Date, calendar: Calendar) -> Int`. Task 10 stores `activeDays`; Task 12 displays the result.

Per the spec: a day counts once at least one card is marked seen, in device local time. The streak survives a today with no activity yet — it breaks only after a full calendar day passes with none. No grace days.

- [ ] **Step 1: Write the failing test**

Create `packages/BibleFeedKit/Tests/BibleFeedKitTests/StreakCalculatorTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func day(_ day: Int) -> Date {
    DateComponents(calendar: calendar, timeZone: calendar.timeZone,
                   year: 2026, month: 9, day: day).date!
}

@Test func noActivityIsZero() {
    #expect(StreakCalculator.currentStreak(
        activeDays: [], today: day(10), calendar: calendar) == 0)
}

@Test func todayOnlyIsOne() {
    #expect(StreakCalculator.currentStreak(
        activeDays: [day(10)], today: day(10), calendar: calendar) == 1)
}

@Test func consecutiveDaysEndingTodayCount() {
    #expect(StreakCalculator.currentStreak(
        activeDays: [day(8), day(9), day(10)],
        today: day(10), calendar: calendar) == 3)
}

@Test func gapBreaksTheStreak() {
    #expect(StreakCalculator.currentStreak(
        activeDays: [day(5), day(6), day(9), day(10)],
        today: day(10), calendar: calendar) == 2)
}

@Test func streakSurvivesATodayWithNoActivityYet() {
    // Yesterday counted, today has not started. The streak is still alive.
    #expect(StreakCalculator.currentStreak(
        activeDays: [day(8), day(9)],
        today: day(10), calendar: calendar) == 2)
}

@Test func aFullMissedDayBreaksIt() {
    #expect(StreakCalculator.currentStreak(
        activeDays: [day(7), day(8)],
        today: day(10), calendar: calendar) == 0)
}

@Test func timesOfDayDoNotMatter() {
    let morning = calendar.date(byAdding: .hour, value: 7, to: day(10))!
    let evening = calendar.date(byAdding: .hour, value: 22, to: day(9))!
    #expect(StreakCalculator.currentStreak(
        activeDays: [evening, morning], today: morning, calendar: calendar) == 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: FAIL — `cannot find 'StreakCalculator' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `packages/BibleFeedKit/Sources/BibleFeedKit/StreakCalculator.swift`:

```swift
import Foundation

public enum StreakCalculator {
    /// Counts back from today over consecutive days that saw activity.
    /// A today with no activity yet does not break the streak; a full
    /// calendar day with none does.
    public static func currentStreak(activeDays: Set<Date>,
                                     today: Date,
                                     calendar: Calendar = .current) -> Int {
        let days = Set(activeDays.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        let start = calendar.startOfDay(for: today)
        var cursor = days.contains(start)
            ? start
            : calendar.date(byAdding: .day, value: -1, to: start)!

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: PASS, 20 tests

- [ ] **Step 5: Commit**

```bash
git add packages/BibleFeedKit
git commit -m "Add streak calculator"
```

---

## Phase 3 — App

### Task 9: Link the package and load content

**Files:**
- Modify: `BibleApp/BibleApp.xcodeproj` (via Xcode GUI — the one manual step in this plan)
- Create: `BibleApp/BibleApp/Content/ContentStore.swift`

**Interfaces:**
- Consumes: `FeedContent`, `Verse` from Task 5; `feed_verses.json` from Task 4
- Produces: `ContentStore` — an `@Observable` class with `verses: [Verse]`, `loadFailed: Bool`, and `load()`. Tasks 11, 12 and 13 read `verses` from it.

- [ ] **Step 1: Link BibleFeedKit into the app target**

This cannot be scripted safely. In Xcode:

1. Open `BibleApp/BibleApp.xcodeproj`.
2. File → Add Package Dependencies… → **Add Local…**
3. Choose `packages/BibleFeedKit`, click Add Package.
4. In the dialog that follows, set the `BibleFeedKit` library's target to **BibleApp**.
5. Select the BibleApp target → General → Frameworks, Libraries, and Embedded Content. Confirm `BibleFeedKit` is listed.

- [ ] **Step 2: Verify the link builds**

Run:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Write the content store**

Create `BibleApp/BibleApp/Content/ContentStore.swift`:

```swift
import Foundation
import BibleFeedKit

@Observable
final class ContentStore {
    private(set) var verses: [Verse] = []
    private(set) var loadFailed = false

    func load() {
        guard let url = Bundle.main.url(forResource: "feed_verses",
                                        withExtension: "json") else {
            fail("feed_verses.json is missing from the bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let content = try JSONDecoder().decode(FeedContent.self, from: data)
            verses = content.verses
            loadFailed = false
        } catch {
            fail("feed_verses.json failed to decode: \(error)")
        }
    }

    private func fail(_ message: String) {
        // A decode failure is a programming or packaging error, not a user
        // condition, so make it loud in debug and recoverable in release.
        assertionFailure(message)
        verses = []
        loadFailed = true
    }
}
```

- [ ] **Step 4: Verify content loads at runtime**

Replace the body of `BibleApp/BibleApp/ContentView.swift` with a temporary probe:

```swift
import SwiftUI

struct ContentView: View {
    @State private var store = ContentStore()

    var body: some View {
        VStack(spacing: 8) {
            Text("\(store.verses.count) verses loaded")
                .font(.headline)
            if let first = store.verses.first {
                Text(first.reference).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { store.load() }
    }
}

#Preview {
    ContentView()
}
```

Build and run on the simulator, then screenshot to confirm.
Expected on screen: `400 verses loaded`

- [ ] **Step 5: Commit**

```bash
git add BibleApp/
git commit -m "Link BibleFeedKit and load feed content from bundle"
```

---

### Task 10: User state

**Files:**
- Create: `BibleApp/BibleApp/State/UserState.swift`
- Modify: `BibleApp/BibleApp/BibleAppApp.swift`

**Interfaces:**
- Consumes: `Topic` from Task 5, `StreakCalculator` from Task 8
- Produces: `@Model final class UserState` with stored `seenIDs: [String]`, `savedIDs: [String]`, `topicsRaw: [String]`, `activeDays: [Date]`, plus computed `topics: Set<Topic>`, `streak: Int`, and mutating methods `markSeen(_ id: String)`, `toggleSaved(_ id: String)`, `setTopics(_ topics: Set<Topic>)`. Tasks 11, 12 and 13 call these.

- [ ] **Step 1: Write the state model**

Create `BibleApp/BibleApp/State/UserState.swift`:

```swift
import Foundation
import SwiftData
import BibleFeedKit

@Model
final class UserState {
    var seenIDs: [String] = []
    var savedIDs: [String] = []
    var topicsRaw: [String] = []
    var activeDays: [Date] = []
    var hasCompletedOnboarding: Bool = false

    init() {}

    var topics: Set<Topic> {
        Set(topicsRaw.compactMap(Topic.init(rawValue:)))
    }

    var seenSet: Set<String> { Set(seenIDs) }
    var savedSet: Set<String> { Set(savedIDs) }

    var streak: Int {
        StreakCalculator.currentStreak(activeDays: Set(activeDays), today: .now)
    }

    func setTopics(_ topics: Set<Topic>) {
        topicsRaw = topics.map(\.rawValue).sorted()
        hasCompletedOnboarding = true
    }

    /// Marking a card seen is also what counts a day toward the streak.
    func markSeen(_ id: String) {
        if !seenIDs.contains(id) {
            seenIDs.append(id)
        }
        let today = Calendar.current.startOfDay(for: .now)
        if !activeDays.contains(where: { Calendar.current.isDate($0, inSameDayAs: today) }) {
            activeDays.append(today)
        }
    }

    func toggleSaved(_ id: String) {
        if let index = savedIDs.firstIndex(of: id) {
            savedIDs.remove(at: index)
        } else {
            savedIDs.append(id)
        }
    }
}
```

- [ ] **Step 2: Install the SwiftData container**

Replace `BibleApp/BibleApp/BibleAppApp.swift` with:

```swift
import SwiftUI
import SwiftData

@main
struct BibleAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: UserState.self)
    }
}
```

- [ ] **Step 3: Verify it builds**

Run:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add BibleApp/
git commit -m "Add SwiftData UserState for seen, saved, topics and streak"
```

---

### Task 11: Onboarding

**Files:**
- Create: `BibleApp/BibleApp/Views/OnboardingView.swift`

**Interfaces:**
- Consumes: `Topic` from Task 5, `UserState.setTopics` from Task 10
- Produces: `OnboardingView(state: UserState)`. Task 12's router presents it while `hasCompletedOnboarding` is false.

Per the spec, the picker takes three to five topics and is skippable. Skipping leaves `topicsRaw` empty, which makes the topic bonus contribute nothing and ranking fall back to tier alone.

- [ ] **Step 1: Write the view**

Create `BibleApp/BibleApp/Views/OnboardingView.swift`:

```swift
import SwiftUI
import BibleFeedKit

struct OnboardingView: View {
    let state: UserState

    @State private var chosen: Set<Topic> = []

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
    private var canContinue: Bool { (3...5).contains(chosen.count) }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("What's on your mind?")
                    .font(.largeTitle.bold())
                Text("Pick three to five. We'll start there.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Topic.allCases, id: \.self) { topic in
                    Button {
                        toggle(topic)
                    } label: {
                        Text(topic.rawValue.capitalized)
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(chosen.contains(topic) ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(chosen.contains(topic) ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Continue") {
                    state.setTopics(chosen)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinue)

                Button("Skip for now") {
                    state.setTopics([])
                }
                .font(.footnote)
            }
        }
        .padding(24)
    }

    private func toggle(_ topic: Topic) {
        if chosen.contains(topic) {
            chosen.remove(topic)
        } else if chosen.count < 5 {
            chosen.insert(topic)
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add BibleApp/
git commit -m "Add onboarding topic picker"
```

---

### Task 12: Feed and card

**Files:**
- Create: `BibleApp/BibleApp/Views/VerseCard.swift`
- Create: `BibleApp/BibleApp/Views/FeedView.swift`
- Modify: `BibleApp/BibleApp/ContentView.swift` (replace the Task 9 probe)

**Interfaces:**
- Consumes: `ContentStore` (Task 9), `UserState` (Task 10), `FeedEngine` and `FeedQueue` (Tasks 6–7), `OnboardingView` (Task 11)
- Produces: `FeedView(store:state:)` and `VerseCard(verse:isSaved:onSave:)`. Task 13 links to `LibraryView` from the feed header.

The card shows the KJV text, then the reference, then the context. The two-second seen rule from the spec is a task started on appear and cancelled on disappear.

- [ ] **Step 1: Write the card**

Create `BibleApp/BibleApp/Views/VerseCard.swift`:

```swift
import SwiftUI
import BibleFeedKit

struct VerseCard: View {
    let verse: Verse
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Text(verse.displayText)
                .font(.system(.title2, design: .serif))
                .lineSpacing(6)

            Text(verse.reference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Divider()

            Text(verse.context)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Spacer()

            HStack {
                ForEach(verse.topics, id: \.self) { topic in
                    Text(topic.rawValue.capitalized)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                Spacer()
                Button(action: onSave) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                }
                .accessibilityLabel(isSaved ? "Remove from saved" : "Save verse")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Write the feed**

Create `BibleApp/BibleApp/Views/FeedView.swift`:

```swift
import SwiftUI
import BibleFeedKit

struct FeedView: View {
    let store: ContentStore
    let state: UserState

    @State private var queue: [Verse] = []
    @State private var isReplay = false
    @State private var seenTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if isReplay {
                    MilestoneCard(count: store.verses.count)
                        .containerRelativeFrame(.vertical)
                }
                ForEach(queue) { verse in
                    VerseCard(verse: verse,
                              isSaved: state.savedSet.contains(verse.id),
                              onSave: { state.toggleSaved(verse.id) })
                        .containerRelativeFrame(.vertical)
                        .onAppear { startSeenTimer(verse) }
                        .onDisappear { cancelSeenTimer(verse) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .onAppear(perform: rebuild)
    }

    private func rebuild() {
        let engine = FeedEngine(verses: store.verses)
        let result = engine.queue(selectedTopics: state.topics,
                                  seen: state.seenSet,
                                  saved: state.savedSet,
                                  seed: UInt64.random(in: 0...UInt64.max))
        queue = result.verses
        isReplay = result.isReplay
    }

    /// A card counts as seen only after two seconds on screen, so a flick
    /// past does not consume it.
    private func startSeenTimer(_ verse: Verse) {
        guard seenTasks[verse.id] == nil else { return }
        seenTasks[verse.id] = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            state.markSeen(verse.id)
        }
    }

    private func cancelSeenTimer(_ verse: Verse) {
        seenTasks[verse.id]?.cancel()
        seenTasks[verse.id] = nil
    }
}

private struct MilestoneCard: View {
    let count: Int

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("You've read all \(count) verses")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Starting again with the ones you saved.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
```

- [ ] **Step 3: Write the router**

Replace `BibleApp/BibleApp/ContentView.swift` with:

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var states: [UserState]
    @State private var store = ContentStore()

    var body: some View {
        Group {
            if store.loadFailed {
                ContentUnavailableView {
                    Label("Content unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The verse library could not be loaded.")
                } actions: {
                    Button("Try again") { store.load() }
                }
            } else if let state = states.first {
                if state.hasCompletedOnboarding {
                    FeedView(store: store, state: state)
                } else {
                    OnboardingView(state: state)
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            store.load()
            if states.isEmpty {
                context.insert(UserState())
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserState.self, inMemory: true)
}
```

- [ ] **Step 4: Build and run on the simulator**

Run:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

Then launch on the simulator and verify by screenshot: the topic picker appears, Continue enables only at three selections, and after Continue a verse fills the screen and swiping up pages to the next one.

- [ ] **Step 5: Commit**

```bash
git add BibleApp/
git commit -m "Add scrolling verse feed with onboarding router"
```

---

### Task 13: Library

**Files:**
- Create: `BibleApp/BibleApp/Views/LibraryView.swift`
- Modify: `BibleApp/BibleApp/Views/FeedView.swift`

**Interfaces:**
- Consumes: `ContentStore` (Task 9), `UserState` (Task 10)
- Produces: `LibraryView(store:state:)`, presented as a sheet from the feed. It renders
  its own compact rows rather than reusing `VerseCard`, which is sized for a full page.

- [ ] **Step 1: Write the library**

Create `BibleApp/BibleApp/Views/LibraryView.swift`:

```swift
import SwiftUI
import BibleFeedKit

struct LibraryView: View {
    let store: ContentStore
    let state: UserState

    @Environment(\.dismiss) private var dismiss
    @State private var filter: Topic?

    private var saved: [Verse] {
        let savedSet = state.savedSet
        return store.verses
            .filter { savedSet.contains($0.id) }
            .filter { filter == nil || $0.topics.contains(filter!) }
    }

    private var availableTopics: [Topic] {
        let savedSet = state.savedSet
        let topics = store.verses
            .filter { savedSet.contains($0.id) }
            .flatMap(\.topics)
        return Array(Set(topics)).sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.savedIDs.isEmpty {
                    ContentUnavailableView("Nothing saved yet",
                                           systemImage: "bookmark",
                                           description: Text("Tap the bookmark on a verse to keep it here."))
                } else {
                    List {
                        if !availableTopics.isEmpty {
                            Section {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) {
                                        FilterChip(title: "All", isOn: filter == nil) { filter = nil }
                                        ForEach(availableTopics, id: \.self) { topic in
                                            FilterChip(title: topic.rawValue.capitalized,
                                                       isOn: filter == topic) { filter = topic }
                                        }
                                    }
                                }
                                .scrollIndicators(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                        ForEach(saved) { verse in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verse.displayText)
                                    .font(.system(.body, design: .serif))
                                Text(verse.reference)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    state.toggleSaved(verse.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isOn ? Color.accentColor : Color(.secondarySystemBackground))
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .clipShape(Capsule())
    }
}
```

- [ ] **Step 2: Add the header to the feed**

In `BibleApp/BibleApp/Views/FeedView.swift`, add this state property alongside the others:

```swift
    @State private var showLibrary = false
```

and attach these modifiers to the `ScrollView`, after `.ignoresSafeArea(edges: .bottom)`:

```swift
        .overlay(alignment: .top) {
            HStack {
                Label("\(state.streak)", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.streak > 0 ? .orange : .secondary)
                Spacer()
                Button {
                    showLibrary = true
                } label: {
                    Image(systemName: "bookmark")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Saved verses")
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(store: store, state: state)
        }
```

- [ ] **Step 3: Let the user change their topics**

The spec promises topics stay editable after onboarding. Reuse the existing
router rather than building a second picker: clearing `hasCompletedOnboarding`
sends `ContentView` back to `OnboardingView`.

Add this method to `UserState` in `BibleApp/BibleApp/State/UserState.swift`:

```swift
    func reopenTopicPicker() {
        hasCompletedOnboarding = false
    }
```

In `BibleApp/BibleApp/Views/LibraryView.swift`, add a second toolbar item inside
the existing `.toolbar { ... }` block, after the `confirmationAction` item:

```swift
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit topics") {
                        state.reopenTopicPicker()
                        dismiss()
                    }
                    .font(.subheadline)
                }
```

- [ ] **Step 4: Build and verify**

Run:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

On the simulator: save a verse, open the bookmark sheet, confirm it appears and
the topic filter narrows the list. Tap Edit topics and confirm the picker returns
with the previous choices clearable.

- [ ] **Step 5: Run the full test suite one more time**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit && python3 -m unittest discover -s tools && python3 tools/validate_feed.py BibleApp/BibleApp/Resources/feed_verses.json`
Expected: Swift and Python test counts may have grown via review fix rounds since this plan was drafted — check actual counts pass, not the literal numbers, `0 error(s)`

- [ ] **Step 6: Commit**

```bash
git add BibleApp/
git commit -m "Add saved verse library with topic filter and topic editing"
```

---

## Done when

- `swift test --package-path packages/BibleFeedKit` passes, 19 tests
- `python3 -m unittest discover -s tools` passes, 8 tests
- `python3 tools/validate_feed.py BibleApp/BibleApp/Resources/feed_verses.json` exits 0
- The app builds for iPhone 17 Pro and, on a clean install, shows the topic
  picker, then a swipeable feed of verses, a working save button, a saved list
  and a streak count.
