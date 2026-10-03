#!/usr/bin/env python3
"""Static security checks for the plugin, as the Omarchy marketplace reviews
it. Fails on any occurrence of:

  rich-text      RichText / StyledText / MarkdownText (text is PlainText only)
  text-format    a Text or Label without textFormat: Text.PlainText
                 (including "component X: Text {" and "p: Label {")
  dynamic-code   eval( / new Function( / new RegExp( on a non-literal
  shell-concat   "sh"/"bash", "-c", "<literal>" + ...: data spliced into a
                 shell command instead of passed as $1..
  python-c       inline python3 -c programs (they belong in scripts/)

and lists, without failing, the call sites that need a reviewer's eye:
"hyprctl", "eval" (Lua built from strings) and notify-send (bodies render
markup). Usage: security-grep.py [ROOT]
"""
import pathlib
import re
import sys

FAIL_RULES = {
    "rich-text": re.compile(r"\b(RichText|StyledText|MarkdownText)\b"),
    "dynamic-code": re.compile(r"\beval\s*\(|new\s+Function\s*\(|new\s+RegExp\s*\(\s*[^\"'/]"),
    "shell-concat": re.compile(r"\"(ba)?sh\",\s*\"-c\",\s*\"(?:[^\"\\]|\\.)*\"\s*\+"),
    "python-c": re.compile(r"\"python3\",\s*\"-c\""),
}
REVIEW_RULES = {
    "hyprctl-eval": re.compile(r"\"hyprctl\",\s*\"eval\""),
    "notify-send": re.compile(r"notify-send"),
}
TEXT_OPEN = re.compile(r"(^\s*|:\s*)(Text|Label)\s*\{")
SKIP_DIRS = {"tests", "docs", ".git", ".github", "node_modules"}


def text_blocks_without_plaintext(src):
    lines = src.splitlines()
    found = []
    for i, line in enumerate(lines):
        if not TEXT_OPEN.search(line):
            continue
        depth, body = 0, []
        for l in lines[i:]:
            body.append(l)
            depth += l.count("{") - l.count("}")
            if depth <= 0:
                break
        if "Text.PlainText" not in "\n".join(body):
            found.append(i + 1)
    return found


def scan(root):
    root = pathlib.Path(root)
    failures, review = [], []
    for p in sorted(root.rglob("*")):
        rel = p.relative_to(root)
        if p.suffix not in (".qml", ".js", ".py", ".sh") or SKIP_DIRS & set(rel.parts):
            continue
        try:
            src = p.read_text(errors="replace")
        except OSError:
            continue
        for n, line in enumerate(src.splitlines(), 1):
            for rule, rx in FAIL_RULES.items():
                if rx.search(line):
                    failures.append(f"{rel}:{n}: {rule}")
            for rule, rx in REVIEW_RULES.items():
                if rx.search(line):
                    review.append(f"{rel}:{n}: {rule}")
        if p.suffix == ".qml":
            for n in text_blocks_without_plaintext(src):
                failures.append(f"{rel}:{n}: text-format")
    return failures, review


def main(argv):
    root = argv[1] if len(argv) > 1 else pathlib.Path(__file__).resolve().parents[2]
    failures, review = scan(root)
    for line in review:
        print(f"review: {line}")
    for line in failures:
        print(f"FAIL: {line}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
