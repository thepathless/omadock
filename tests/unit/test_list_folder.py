"""scripts/list-folder.py, run as the dock runs it (a subprocess)."""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "list-folder.py"


class ListFolder(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.base = pathlib.Path(tmp.name)
        self.dir = self.base / "f"
        self.dir.mkdir()
        self.env = dict(os.environ, XDG_CACHE_HOME=str(self.base / "cache"))

    def run_script(self, *args, folder=None):
        r = subprocess.run([sys.executable, str(SCRIPT), str(folder or self.dir), *args],
                           capture_output=True, timeout=120, env=self.env)
        return json.loads(r.stdout)

    def touch(self, name, size=1):
        p = self.dir / name
        p.write_bytes(b"\0" * size)
        return p

    def test_non_utf8_name_still_gives_json(self):
        with open(os.fsencode(str(self.dir)) + b"/bad\xff.png", "wb") as f:
            f.write(b"x")
        self.assertEqual(self.run_script()["count"], 1)

    def test_svg_and_gif_never_preview_the_original(self):
        self.touch("x.svg")
        self.touch("y.gif")
        self.assertEqual([i["thumb"] for i in self.run_script("name")["items"]], ["", ""])

    def test_small_png_previews_the_original(self):
        p = self.touch("a.png")
        self.assertEqual(self.run_script()["items"][0]["thumb"], str(p))

    def test_huge_png_has_no_preview(self):
        with open(self.dir / "big.png", "wb") as f:
            f.truncate(50 * 1024 * 1024)  # sparse, no disk use
        self.assertEqual(self.run_script()["items"][0]["thumb"], "")

    def test_cached_thumbnail_is_used_even_for_svg(self):
        p = self.touch("x.svg")
        uri = "file://" + urllib.parse.quote(str(p), safe="/!$&'()*+,;=:@-._~")
        d = self.base / "cache" / "thumbnails" / "large"
        d.mkdir(parents=True)
        t = d / (hashlib.md5(uri.encode()).hexdigest() + ".png")
        t.write_bytes(b"png")
        self.assertEqual(self.run_script()["items"][0]["thumb"], str(t))

    def test_scan_stops_at_budget(self):
        for i in range(20005):
            (self.dir / f"f{i}").touch()
        out = self.run_script("name", "5")
        self.assertEqual(out["count"], 20000)
        self.assertTrue(out["truncated"])
        self.assertEqual(len(out["items"]), 5)

    def test_small_folder_is_not_truncated(self):
        self.touch("a")
        out = self.run_script()
        self.assertFalse(out["truncated"])
        self.assertFalse(out["failed"])

    def test_missing_folder_gives_valid_json(self):
        out = self.run_script(folder=self.base / "nope")
        self.assertEqual((out["count"], out["items"]), (0, []))
        # A missing folder is unreadable, not empty: the popup must not claim
        # there is nothing inside a folder it could not open.
        self.assertTrue(out["failed"])

    def test_unreadable_folder_is_failed_not_empty(self):
        if os.geteuid() == 0:
            self.skipTest("root can read a mode-000 directory")
        self.dir.chmod(0)
        self.addCleanup(self.dir.chmod, 0o755)
        out = self.run_script()
        self.assertEqual((out["count"], out["items"]), (0, []))
        self.assertTrue(out["failed"])

    def test_natural_name_sort_and_hidden_skipped(self):
        for n in ("a10", "a2", "A1", ".hidden"):
            self.touch(n)
        self.assertEqual([i["name"] for i in self.run_script("name")["items"]], ["A1", "a2", "a10"])

    def test_limit_is_clamped(self):
        for n in range(20):
            self.touch(f"f{n}")
        self.assertEqual(len(self.run_script("name", "abc")["items"]), 16)
        self.assertEqual(len(self.run_script("name", "-5")["items"]), 1)


if __name__ == "__main__":
    unittest.main()
