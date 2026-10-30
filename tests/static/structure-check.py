#!/usr/bin/env python3
"""Maintainability structure check (AGENTS.md "Maintainability Rules").

Rules enforced:
  1. File-size cap: every .qml/.js/.mjs/.sh file is at most MAX_LINES lines.
  2. Composition roots (Dock.qml, DockModel.js) are the only exceptions and
     carry ratchet ceilings: they may shrink over time, never grow. Lowering
     a ceiling is part of any refactor that moves code out of a root.
  3. components/logic/*.qml are pure logic: QtObject with functions only -
     no timers, processes, file views, windows, or visual items.
  4. components/logic/*.qml functions take the owner root as the FIRST
     parameter (`root`), keeping every module call uniform.
  5. The live suites (tests/live/*.sh) carry the same ratchet as the
     composition roots: they are the repo's largest shell files, so the size
     each had when the cap reached them is recorded in SHELL_CEILINGS and may
     only be lowered.

Exit codes: 0 = all rules hold; 1 = violations (printed one per line).
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

MAX_LINES = 800

# Composition roots: single-owner state + wiring must live somewhere, and it
# lives here. These ceilings are ratchets - see rule 2.
ROOT_CEILINGS = {
    "Dock.qml": 2379,    "DockModel.js": 1326,
}

# Rule 5: the live suites, ratcheted at the size they had when the cap was
# extended to shell files (they were uncapped before, so the largest test in the
# repo could have doubled unnoticed). Lower one when a suite shrinks; move code
# out of a suite rather than raising it.
SHELL_CEILINGS = {
    "tests/live/presets.sh": 388,
    "tests/live/indicators.sh": 346,
    "tests/live/probe.sh": 328,
    "tests/live/place-restore.sh": 250,
    "tests/live/teardown.sh": 125,
    "tests/live/layout.sh": 115,
    "tests/live/ipc-roundtrip.sh": 115,
    "tests/live/label-metrics.sh": 110,
    "tests/live/config-fuzz.sh": 84,
    "tests/live/common.sh": 24,
}

# Rule 3: objects that belong in the composition root or in a visual
# component, never in a logic module.
FORBIDDEN_IN_LOGIC = re.compile(
    r"^\s*(Timer|Process|CappedFileView|PanelWindow|Window|Connections|Repeater|"
    r"ListView|Flickable|Rectangle|Image|Loader|LazyLoader|MouseArea|"
    r"WheelHandler|DragHandler|HoverHandler|TapHandler)\s*\{")

# Rule 4: module functions take `root` first.
ROOT_FIRST = re.compile(r"^  function [A-Za-z_]\w*\((?!root[,)])")

SKIP_DIRS = {".git", "node_modules", "__pycache__"}


def source_files():
    """This branch's QML, JS and shell, walking around nested working trees.

    The `experiment/` worktree lives inside the root directory, and its files
    belong to the `experimental` branch: capping them against this branch's
    ceilings reported the composition roots as violations whenever the check
    ran from `main` (GitHub CI has no nested worktree, so CI never saw it).
    A directory holding a `.git` entry is its own working tree - skip it.
    """
    for dirpath, dirnames, filenames in os.walk(ROOT):
        here = Path(dirpath)
        if here != ROOT and ".git" in dirnames + filenames:
            dirnames[:] = []
            continue
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in sorted(filenames):
            path = here / name
            if path.suffix in {".qml", ".js", ".mjs", ".sh"}:
                yield path


def main():
    violations = []
    for path in source_files():
        rel = path.relative_to(ROOT).as_posix()
        lines = path.read_text(errors="replace").splitlines()
        cap = ROOT_CEILINGS.get(rel) or SHELL_CEILINGS.get(rel) or MAX_LINES
        if len(lines) > cap:
            if rel in ROOT_CEILINGS:
                kind = "root ratchet"
            elif rel in SHELL_CEILINGS:
                kind = "suite ratchet"
            else:
                kind = "file-size cap"
            violations.append(f"{rel}: {len(lines)} lines exceeds {kind} of {cap}")
        if rel.startswith("components/logic/"):
            for n, line in enumerate(lines, 1):
                if FORBIDDEN_IN_LOGIC.search(line):
                    violations.append(
                        f"{rel}:{n}: logic module declares {line.strip()} "
                        f"- timers/processes/visuals belong in Dock.qml or a component")
                if line.startswith("  function ") and ROOT_FIRST.match(line):
                    violations.append(
                        f"{rel}:{n}: logic function must take `root` as first parameter")

    if violations:
        print("structure-check FAILED:")
        for v in violations:
            print("  " + v)
        print(f"\n{len(violations)} violation(s). See AGENTS.md "
              f"\"Maintainability Rules\". Composition-root and live-suite "
              f"ceilings may only be lowered, never raised.")
        return 1
    print("structure-check PASSED: no file exceeds its cap; "
          "logic modules are pure.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
