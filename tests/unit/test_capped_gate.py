"""The CappedFileView pre-read gate, taken from the QML and run the way the
dock runs it (sh -c GATE name PATH MAX): exit 0 with the content, 2 for
anything that is not a readable regular file, 3 for a file over the cap.
GATE_QML overrides the QML file (to check that the test can fail)."""
import os
import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
QML = pathlib.Path(os.environ.get("GATE_QML", ROOT / "components" / "CappedFileView.qml"))


def gate_script():
    src = QML.read_text()
    block = re.search(r'gateScript:\s*\[(.*?)\]\.join\("\\n"\)', src, re.S).group(1)
    return "\n".join(re.findall(r"'((?:[^'\\]|\\.)*)'", block))


class Gate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gate = gate_script()

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)

    def run_gate(self, path, cap):
        return subprocess.run(["sh", "-c", self.gate, "gate", str(path), str(cap)],
                              capture_output=True, text=True, timeout=10)

    def test_small_regular_file_is_read(self):
        (self.dir / "small").write_text("hello")
        r = self.run_gate(self.dir / "small", 100)
        self.assertEqual((r.returncode, r.stdout), (0, "hello"))

    def test_oversize_file_is_refused(self):
        (self.dir / "big").write_bytes(b"\0" * 2000)
        self.assertEqual(self.run_gate(self.dir / "big", 1000).returncode, 3)

    def test_directory_fifo_device_and_missing_are_refused(self):
        (self.dir / "dir").mkdir()
        os.mkfifo(self.dir / "fifo")
        (self.dir / "zero").symlink_to("/dev/zero")
        for name in ("dir", "fifo", "zero", "missing"):
            with self.subTest(name=name):
                self.assertEqual(self.run_gate(self.dir / name, 1000).returncode, 2)


if __name__ == "__main__":
    unittest.main()
