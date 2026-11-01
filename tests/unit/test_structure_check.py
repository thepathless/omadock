"""The structure check walks this branch's files only.

`experiment/` is a Git worktree of the `experimental` branch living inside the
root directory. Capping its files against `main`'s ceilings reported Dock.qml
and DockModel.js as violations (2417 > 800) every time the check ran from the
root worktree, while GitHub CI - which has no nested worktree - stayed green.
A directory holding a `.git` entry is its own working tree and is skipped.

STRUCTURE_CHECK overrides the script under test (to check the test can fail).
"""
import contextlib
import importlib.util
import io
import os
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = pathlib.Path(os.environ.get(
    "STRUCTURE_CHECK", ROOT / "tests" / "static" / "structure-check.py"))
FILLER = "// filler\n"


def load():
    spec = importlib.util.spec_from_file_location("structure_check", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build():
    """A worktree with an oversized file, plus a nested oversized worktree."""
    tmp = tempfile.TemporaryDirectory()
    root = pathlib.Path(tmp.name)
    (root / "components").mkdir()
    (root / "components" / "Big.qml").write_text(FILLER * 900)
    (root / "Dock.qml").write_text(FILLER * 100)
    nested = root / "experiment"
    nested.mkdir()
    (nested / ".git").write_text("gitdir: /elsewhere/worktrees/experiment\n")
    (nested / "Dock.qml").write_text(FILLER * 3000)
    return tmp, root


class NestedWorktree(unittest.TestCase):
    def test_nested_worktree_is_skipped(self):
        module = load()
        tmp, root = build()
        with tmp:
            module.ROOT = root
            found = sorted(p.relative_to(root).as_posix() for p in module.source_files())
            self.assertEqual(found, ["Dock.qml", "components/Big.qml"])

    def test_violations_of_this_branch_are_still_reported(self):
        module = load()
        tmp, root = build()
        with tmp, contextlib.redirect_stdout(io.StringIO()) as out:
            module.ROOT = root
            self.assertEqual(module.main(), 1)
            reported = out.getvalue()
        self.assertIn("components/Big.qml: 900 lines exceeds file-size cap of 800",
                      reported)
        self.assertNotIn("experiment/Dock.qml", reported)


class ShellSuites(unittest.TestCase):
    """Rule 5: shell files are capped, and the live suites are ratcheted.

    Before this rule the walker took only .qml/.js/.mjs, so the largest test
    file in the repo (a live suite) could have doubled unnoticed. Every suite
    must carry an entry too: the table had fallen behind the newest harnesses
    while AGENTS.md claimed it covered every `tests/live/*.sh`.
    """

    def build(self, pinned_lines, fresh_lines, tool_lines=0):
        tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(tmp.name)
        live = root / "tests" / "live"
        live.mkdir(parents=True)
        (live / "pinned.sh").write_text("# filler\n" * pinned_lines)
        (live / "fresh.sh").write_text("# filler\n" * fresh_lines)
        if tool_lines:
            scripts = root / "scripts"
            scripts.mkdir()
            (scripts / "tool.sh").write_text("# filler\n" * tool_lines)
        return tmp, root

    def run_check(self, module, root, ceilings):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            module.ROOT = root
            module.SHELL_CEILINGS = ceilings
            rc = module.main()
        return rc, out.getvalue()

    def test_shell_files_are_capped_and_live_suites_ratcheted(self):
        module = load()
        tmp, root = self.build(pinned_lines=11, fresh_lines=3, tool_lines=900)
        with tmp:
            rc, reported = self.run_check(module, root, {
                "tests/live/pinned.sh": 10, "tests/live/fresh.sh": 3})
        self.assertEqual(rc, 1)
        self.assertIn("tests/live/pinned.sh: 11 lines exceeds suite ratchet of 10",
                      reported)
        self.assertIn("scripts/tool.sh: 900 lines exceeds file-size cap of 800",
                      reported)

    def test_a_suite_at_its_ceiling_passes(self):
        module = load()
        tmp, root = self.build(pinned_lines=10, fresh_lines=3)
        with tmp:
            rc, reported = self.run_check(module, root, {
                "tests/live/pinned.sh": 10, "tests/live/fresh.sh": 3})
        self.assertEqual(rc, 0, reported)

    def test_a_live_suite_without_a_ratchet_is_reported(self):
        module = load()
        tmp, root = self.build(pinned_lines=10, fresh_lines=3)
        with tmp:
            rc, reported = self.run_check(module, root, {"tests/live/pinned.sh": 10})
        self.assertEqual(rc, 1)
        self.assertIn("tests/live/fresh.sh: live suite has no SHELL_CEILINGS "
                      "ratchet", reported)


if __name__ == "__main__":
    unittest.main()
