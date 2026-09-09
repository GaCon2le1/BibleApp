"""Resolve a Protestant/KJV Psalms (chapter, verse) to its CPDV counterpart.

CPDV follows the historic Vulgate/Septuagint numbering, which diverges from
KJV's for most of the Psalter. See this file's companion test and the
implementation plan's Task 8 for the full investigation behind these
constants -- every one of them is confirmed against real vendored text, not
computed from reference literature alone.

This function is a CANDIDATE generator, not an authority: two confirmed
counter-examples (Psalms 4 and 56) show the general per-chapter delta rule
can be wrong even when it looks self-consistent, so every one of the 130
ids this project actually needs resolved gets a human reading pass in
data/curation/cpdv_verse_map.json regardless of what this function returns.
"""

# KJV chapters that live, wholly or partly, inside a CPDV chapter shared
# with a neighboring KJV chapter (a genuine merge or split, not a constant
# per-verse shift). Each is resolved explicitly rather than through the
# general delta below.
_MERGE_SPLIT_CHAPTERS = {9, 10, 114, 115, 116, 147}

# Confirmed exceptions to the general "constant delta per chapter" rule,
# found by reading real text (see the module docstring). Each maps
# kjv_chapter -> {kjv_verse: cpdv_verse} for every verse actually needed.
_KNOWN_EXCEPTIONS = {
    4: {2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 8, 8: 9},
    56: {2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 8, 8: 9, 9: 10, 10: 11, 11: 11,
         12: 12, 13: 13},
}


def resolve_psalm_verse(kjv_chapter, kjv_verse, kjv_verse_counts, cpdv_verse_counts):
    """Return (cpdv_chapter, cpdv_verse) -- a candidate, not a final answer."""
    if not 1 <= kjv_chapter <= 150:
        raise ValueError(f"chapter {kjv_chapter} is out of range for Psalms")

    # Each branch below handles a genuine merge/split chapter (see
    # _MERGE_SPLIT_CHAPTERS above); the assertion keeps the two from
    # silently drifting apart if a future edit adds or removes a branch
    # here without updating that set (or vice versa).
    if kjv_chapter == 9:
        assert 9 in _MERGE_SPLIT_CHAPTERS
        return (9, kjv_verse + 1)
    if kjv_chapter == 10:
        assert 10 in _MERGE_SPLIT_CHAPTERS
        return (9, kjv_verse + 21)
    if kjv_chapter == 114:
        assert 114 in _MERGE_SPLIT_CHAPTERS
        return (113, kjv_verse)
    if kjv_chapter == 115:
        assert 115 in _MERGE_SPLIT_CHAPTERS
        return (113, kjv_verse + 8)
    if kjv_chapter == 116:
        assert 116 in _MERGE_SPLIT_CHAPTERS
        return (114, kjv_verse) if kjv_verse <= 9 else (115, kjv_verse - 9)
    if kjv_chapter == 147:
        assert 147 in _MERGE_SPLIT_CHAPTERS
        return (146, kjv_verse) if kjv_verse <= 11 else (147, kjv_verse - 11)

    if 1 <= kjv_chapter <= 8 or 148 <= kjv_chapter <= 150:
        cpdv_chapter = kjv_chapter
    elif 11 <= kjv_chapter <= 113 or 117 <= kjv_chapter <= 146:
        cpdv_chapter = kjv_chapter - 1
    else:
        raise ValueError(f"chapter {kjv_chapter} has no general-rule mapping")

    if kjv_chapter in _KNOWN_EXCEPTIONS:
        cpdv_verse = _KNOWN_EXCEPTIONS[kjv_chapter].get(kjv_verse)
        if cpdv_verse is not None:
            return (cpdv_chapter, cpdv_verse)
        # Fall through to the general rule for any verse in an exception
        # chapter this table doesn't explicitly cover (e.g. verse 1, a
        # heading, which no id in this project resolves to).

    delta = cpdv_verse_counts[cpdv_chapter] - kjv_verse_counts[kjv_chapter]
    return (cpdv_chapter, kjv_verse + delta)
