"""tests/static/security-grep.py catches what it promises and passes the tree."""
import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("security_grep", ROOT / "tests" / "static" / "security-grep.py")
grep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grep)


def scan_snippet(name, text):
    with tempfile.TemporaryDirectory() as tmp:
        (pathlib.Path(tmp) / name).write_text(text)
        return grep.scan(tmp)


class Rules(unittest.TestCase):
    def test_rich_text(self):
        failures, _ = scan_snippet("A.qml", 'Text { textFormat: Text.RichText; text: "x" }\n')
        self.assertTrue(any("rich-text" in f for f in failures))

    def test_text_without_plaintext_including_components(self):
        failures, _ = scan_snippet("B.qml", 'Item {\n  component Lbl: Text {\n    text: "x"\n  }\n}\n')
        self.assertTrue(any("text-format" in f for f in failures))

    def test_plaintext_text_passes(self):
        failures, _ = scan_snippet("C.qml", 'Text {\n  text: name\n  textFormat: Text.PlainText\n}\n')
        self.assertEqual(failures, [])

    def test_shell_concat_eval_and_python_c(self):
        src = 'var a = ["bash", "-c", "rm " + path]\nvar b = eval(s)\nvar c = ["python3", "-c", "print(1)"]\n'
        failures, _ = scan_snippet("D.qml", src)
        rules = {f.split(": ")[-1] for f in failures}
        self.assertEqual(rules, {"shell-concat", "dynamic-code", "python-c"})

    def test_review_sites_do_not_fail(self):
        failures, review = scan_snippet("E.qml", 'var a = ["hyprctl", "eval", lua]\nvar b = ["notify-send", "x"]\n')
        self.assertEqual(failures, [])
        self.assertEqual(len(review), 2)


class Tree(unittest.TestCase):
    def test_plugin_tree_is_clean(self):
        failures, _ = grep.scan(ROOT)
        self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main()
