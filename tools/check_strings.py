"""Checks that every word the app shows has a French and a Spanish translation.

It reads Shared/Resources/Localizable.xcstrings and every string literal in the Swift sources
(the app, the shared code and the widgets),
turns SwiftUI interpolations into the catalog's format (Int becomes %lld, anything else %@),
and lists literals with no translation. Literals that are not words (symbol names, keys,
emoji, numbers with a unit) are skipped. Run: python3 tools/check_strings.py
"""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LANGUAGES = ("fr", "es")

# Interpolated values that are whole numbers in the code, so SwiftUI keys them as %lld.
INTEGERS = {
    "streak", "rank", "now.loggedDays", "now.daysOnTarget", "range.days", "item.score",
    "food.times", "status", "(abs(change) * 100).safeInt", "(share * 100).safeInt", "event.count",
    "water", "waterGoal", "tally.onTarget", "tally.logged", "consensus.estimates", "consensus.spreadPercent",
    "consensus.agrees", "consensus.accuracy", "count", "star", "forecast.days", "learned.days",
    "day.known", "day.counted", "checkIn.wholeDays",
    "snapshot.water", "snapshot.waterGoal", "entry.snapshot.water", "entry.snapshot.waterGoal",
    "days", "weeks", "months", "years",
}

# Literals that are not shown as words, or are deliberately left as they are.
NOT_WORDS = re.compile(
    r"""^(
        [a-z0-9]+(\.[a-z0-9]+)+                     # SF Symbols
      | [a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)*     # keys and identifiers
      | saved:.*|-.*|https?://.*|bite://.*         # internal ids, launch arguments, links
      | [A-Z]                                       # Nutri-Score letters
      | %@|%@\ %@|%@\ (g|kcal|ml)|\+%@|\ /\ %@\ g|×%lld|%lld|\#%lld|%@\ ·\ %@|100\ %@
      | (g|kcal|ml|cm|kg)
      | DMSans(-\w+)?                              # the font file and its PostScript name
    )$""",
    re.X,
)

SKIP_FILES = {"Services/DemoData.swift"}  # its words go through tr() and are checked there


def literals(line: str):
    """Yields (start, text) for each string literal on a line, interpolations included whole."""
    i = 0
    while i < len(line):
        if line.startswith("//", i):
            return
        if line[i] != '"':
            i += 1
            continue
        start, i = i, i + 1
        text = []
        while i < len(line) and line[i] != '"':
            if line.startswith("\\(", i):
                depth, j = 1, i + 2
                while j < len(line) and depth:
                    if line[j] == '"':  # a string inside the interpolation
                        j = line.index('"', j + 1) + 1
                        continue
                    depth += {"(": 1, ")": -1}.get(line[j], 0)
                    j += 1
                text.append(line[i:j])
                i = j
            elif line[i] == "\\":
                text.append(line[i:i + 2])
                i += 2
            else:
                text.append(line[i])
                i += 1
        yield start, "".join(text)
        i += 1


def catalog_key(literal: str) -> str:
    """The key SwiftUI looks up for a literal: interpolations become %lld or %@."""
    out, i = [], 0
    has_interpolation = "\\(" in literal
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(literal) and depth:
                if literal[j] == '"':
                    j = literal.index('"', j + 1) + 1
                    continue
                depth += {"(": 1, ")": -1}.get(literal[j], 0)
                j += 1
            expr = literal[i + 2:j - 1].strip()
            out.append("%lld" if expr in INTEGERS else "%@")
            i = j
        elif literal[i] == "%" and has_interpolation:
            out.append("%%")
            i += 1
        elif literal.startswith('\\"', i):
            out.append('"')
            i += 2
        else:
            out.append(literal[i])
            i += 1
    return "".join(out)


def values(entry: dict, language: str) -> list:
    local = entry.get("localizations", {}).get(language, {})
    if "stringUnit" in local:
        return [local["stringUnit"].get("value", "")]
    return [v["stringUnit"]["value"] for v in local.get("variations", {}).get("plural", {}).values()]


def specifiers(text: str) -> list:
    return sorted(re.sub(r"\d\$", "", s) for s in re.findall(r"%(?:\d\$)?(?:lld|@)", text.replace("%%", "")))


def main() -> int:
    catalog = json.load(open(os.path.join(ROOT, "Shared/Resources/Localizable.xcstrings"), encoding="utf-8"))
    strings = catalog["strings"]
    problems = []

    for key, entry in strings.items():
        for language in LANGUAGES:
            found = values(entry, language)
            if not found or not all(found):
                problems.append(f"catalog: {key!r} has no {language}")
            for value in found:
                if specifiers(value) != specifiers(key):
                    problems.append(f"catalog: {key!r} in {language} has {specifiers(value)}, the key has {specifiers(key)}")

    sources = []
    for top in ("Bite", "Shared", "BiteWidgets"):
        for folder, _, files in os.walk(os.path.join(ROOT, top)):
            sources += [(top, os.path.join(folder, name)) for name in sorted(files) if name.endswith(".swift")]
    for top, path in sources:
            rel = os.path.relpath(path, os.path.join(ROOT, top)).replace(os.sep, "/")
            if top == "BiteWidgets":
                rel = "Views/" + rel
            if rel in SKIP_FILES:
                continue
            in_views = rel.startswith(("Views/", "Design/", "Widgets/"))
            for number, line in enumerate(open(path, encoding="utf-8"), 1):
                if line.strip().startswith("//") or "fatalError(" in line:
                    continue
                for start, literal in literals(line):
                    before = line[:start]
                    if not (re.search(r"\btr\($", before) or re.search(r"String\(localized:\s*$", before) or in_views):
                        continue
                    if re.search(r"(verbatim|systemImage|systemName|forKey|forResource|withExtension|named|id|comment):\s*$", before):
                        continue
                    if re.search(r"(AppStorage|Image)\($", before) or re.search(r"case\s+$", before):
                        continue
                    key = catalog_key(literal)
                    if not re.search(r"[A-Za-zÀ-ÿ]", key) or NOT_WORDS.match(key) or key in strings:
                        continue
                    problems.append(f"{rel}:{number}: no translation for {key!r}")

    for problem in problems:
        print(problem)
    print(f"{len(strings)} keys, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
