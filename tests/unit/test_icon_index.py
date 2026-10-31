#!/usr/bin/env python3
"""scripts/icon-index.sh: the theme-first, size-first icon name index.

The dock draws every icon through this index. A theme's 16x16 artwork is often
a dark outline (WhiteSur's places/16/folder.svg) while its scalable artwork is
the real icon, so the scan must prefer the largest file inside the active
theme instead of the first one find(1) happens to list. These cases pin that
rule, the theme chain's precedence, and the mimetypes/mimes spellings.
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "icon-index.sh"


def touch(path, data="<svg/>"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data)


def index(home, system, chain):
    env = dict(os.environ)
    env["HOME"] = str(home)
    env["XDG_DATA_DIRS"] = str(system)
    done = subprocess.run(["bash", str(SCRIPT)] + chain, capture_output=True, text=True, env=env)
    assert done.returncode == 0, done.stderr
    out = {}
    for line in done.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        path = Path(line)
        out.setdefault(path.stem, path)
    return out


class IconIndex(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.home = self.tmp / "home"
        self.system = self.tmp / "system"
        icons = self.home / ".local/share/icons"
        active = icons / "Active"
        touch(active / "places/16x16/folder.svg")
        touch(active / "places/scalable/folder.svg")
        touch(active / "apps/16x16/app.svg")
        touch(active / "apps/256x256/app.png", "")
        touch(active / "mimes/16/text-x-generic.svg")
        touch(active / "mimes/scalable/text-x-generic.svg")

        inherited = self.system / "icons/Inherited"
        touch(inherited / "places/scalable/folder.svg")
        touch(inherited / "apps/scalable/inherited-only.svg")
        touch(inherited / "apps/256x256/app.png", "")

        stranger = self.system / "icons/Stranger"
        touch(stranger / "places/scalable/stranger-only.svg")

        # KDE themes name their size directories without a "x", e.g. places/96.
        # Under a standard root, so the chain can name it (XDG extras are only
        # reached by the generic fallback pass).
        bare = icons / "Bare"
        touch(bare / "places/16/folder.svg")
        touch(bare / "places/96/folder.svg")

        # Only 16px artwork exists for this name: it must still resolve.
        touch(self.system / "icons/Stranger/apps/16x16/tiny-only.svg")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def active(self, name, chain=("Active", "Inherited")):
        return index(self.home, self.system, list(chain))

    def test_active_theme_prefers_its_largest_artwork(self):
        got = self.active("folder")
        self.assertEqual(got["folder"], self.home / ".local/share/icons/Active/places/scalable/folder.svg")
        self.assertEqual(got["app"], self.home / ".local/share/icons/Active/apps/256x256/app.png")

    def test_active_theme_beats_an_inherited_one(self):
        got = self.active("folder")
        self.assertNotIn("Inherited", str(got["folder"]))
        self.assertEqual(got["inherited-only"], self.system / "icons/Inherited/apps/scalable/inherited-only.svg")

    def test_unrelated_theme_is_the_last_resort(self):
        got = self.active("stranger-only")
        self.assertEqual(got["stranger-only"], self.system / "icons/Stranger/places/scalable/stranger-only.svg")

    def test_bare_size_directories_rank_by_number(self):
        got = self.active("folder", ("Bare",))
        self.assertEqual(got["folder"], self.home / ".local/share/icons/Bare/places/96/folder.svg")

    def test_only_small_artwork_still_resolves(self):
        got = self.active("tiny-only")
        self.assertEqual(got["tiny-only"], self.system / "icons/Stranger/apps/16x16/tiny-only.svg")

    def test_mimes_spelling_is_indexed(self):
        got = self.active("text-x-generic")
        self.assertEqual(got["text-x-generic"], self.home / ".local/share/icons/Active/mimes/scalable/text-x-generic.svg")

    def test_no_chain_still_indexes_the_desktop(self):
        got = self.active("folder", ())
        self.assertIn("folder", got)


if __name__ == "__main__":
    unittest.main()
