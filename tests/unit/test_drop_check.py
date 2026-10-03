import importlib.util
import pathlib
import subprocess
import sys
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "scripts" / "drop-check.py"
# The MIME matching needs GIO (PyGObject), which a bare CI runner lacks;
# without it the script answers "no", which the CLI tests still check.
HAVE_GI = importlib.util.find_spec("gi") is not None
drop_check = None
if HAVE_GI:
    spec = importlib.util.spec_from_file_location("drop_check", SCRIPT)
    drop_check = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(drop_check)


@unittest.skipUnless(HAVE_GI, "PyGObject (gi) is not installed")
class Supported(unittest.TestCase):
    def test_exact_and_inherited_types(self):
        self.assertTrue(drop_check.supported("text/plain", ["text/plain"]))
        self.assertTrue(drop_check.supported("text/x-python", ["text/plain"]))

    def test_wildcards(self):
        self.assertTrue(drop_check.supported("image/png", ["image/*"]))
        self.assertFalse(drop_check.supported("text/plain", ["image/*"]))

    def test_unlisted(self):
        self.assertFalse(drop_check.supported("image/png", ["text/plain"]))
        self.assertFalse(drop_check.supported("image/png", []))


class Cli(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True,
                              text=True, timeout=30).stdout.strip()

    def test_too_few_arguments(self):
        self.assertEqual(self.run_cli(), "no")
        self.assertEqual(self.run_cli("foot"), "no")

    def test_unknown_app(self):
        self.assertEqual(self.run_cli("no-such-app-xyz", "/etc/hostname"), "no")


if __name__ == "__main__":
    unittest.main()
