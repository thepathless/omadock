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


def index(home, system, chain, *, no_cache=False, env_extra=None):
    env = dict(os.environ)
    env["HOME"] = str(home)
    env["XDG_DATA_DIRS"] = str(system)
    # Keep the on-disk cache inside the probe home so unit runs never touch
    # the developer's real ~/.cache/omadock.
    env["XDG_CACHE_HOME"] = str(home / ".cache")
    if no_cache:
        env["OMADOCK_ICON_INDEX_NO_CACHE"] = "1"
    else:
        env.pop("OMADOCK_ICON_INDEX_NO_CACHE", None)
    if env_extra:
        env.update(env_extra)
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


def cache_path(home, chain):
    key = "_".join(chain) if chain else "fallback"
    # Must match scripts/icon-index.sh: tr -c 'A-Za-z0-9._-' '_'
    safe = "".join(c if c.isalnum() or c in "._-" else "_" for c in key)
    return home / ".cache" / "omadock" / f"icon-index-{safe}.cache"


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

    def test_second_run_reuses_cache_with_same_paths(self):
        chain = ("Active", "Inherited")
        first = index(self.home, self.system, list(chain))
        cached = cache_path(self.home, chain)
        self.assertTrue(cached.is_file(), "first scan should publish a cache file")
        second = index(self.home, self.system, list(chain))
        self.assertEqual(first, second)
        self.assertEqual(second["folder"], self.home / ".local/share/icons/Active/places/scalable/folder.svg")

    def test_newer_theme_directory_invalidates_cache(self):
        chain = ("Active", "Inherited")
        index(self.home, self.system, list(chain))
        cached = cache_path(self.home, chain)
        older = cached.read_text()
        # Land a new name after the cache was written; bump the theme dir
        # mtime so the script treats the cache as stale.
        import time
        time.sleep(0.01)
        touch(self.home / ".local/share/icons/Active/apps/scalable/brand-new.svg")
        os.utime(self.home / ".local/share/icons/Active", None)
        got = index(self.home, self.system, list(chain))
        self.assertIn("brand-new", got)
        self.assertNotEqual(older, cached.read_text())


if __name__ == "__main__":
    unittest.main()
