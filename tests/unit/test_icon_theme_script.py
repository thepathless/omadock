#!/usr/bin/env python3
"""scripts/icon-theme.sh: the list it prints and the files an apply writes.

Every apply below runs against a throwaway HOME and a stub `gsettings` on
PATH: the real dconf would be the live desktop's icon theme, and a test must
never change that (a sandbox HOME does not scope gsettings — measured, it is a
D-Bus call into the session).
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "icon-theme.sh"


def run(args, home, path=None):
    env = dict(os.environ)
    env["HOME"] = str(home)
    if path is not None:
        env["PATH"] = path
    return subprocess.run(["bash", str(SCRIPT)] + args, capture_output=True, text=True, env=env)


class ListThemes(unittest.TestCase):
    def test_each_line_is_id_pipe_name_pipe_inherits(self):
        done = run(["list"], Path(tempfile.mkdtemp()))
        self.assertEqual(done.returncode, 0, done.stderr)
        lines = [l for l in done.stdout.splitlines() if l]
        self.assertGreater(len(lines), 0, "no icon theme found on this host")
        for line in lines:
            m = re.fullmatch(r"([A-Za-z0-9][A-Za-z0-9._+-]*)\|([^|]+)\|([^|]*)", line)
            self.assertIsNotNone(m, line)

    def test_lookup_fallbacks_are_not_offered(self):
        done = run(["list"], Path(tempfile.mkdtemp()))
        ids = {l.split("|")[0] for l in done.stdout.splitlines() if l}
        self.assertFalse(ids & {"hicolor", "locolor", "default", "default-dark"})


class ApplyTheme(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.bin = Path(tempfile.mkdtemp())
        self.log = self.bin / "gsettings.log"
        stub = self.bin / "gsettings"
        stub.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> " + str(self.log) + "\nexit 0\n")
        stub.chmod(0o755)
        # A stub PATH keeps dconf untouched; coreutils come from the real PATH.
        self.path = str(self.bin) + ":" + os.environ.get("PATH", "/usr/bin:/bin")

    def apply(self, theme):
        return run(["apply", theme], self.home, self.path)

    def test_apply_writes_the_places_the_desktop_reads(self):
        gtk3 = self.home / ".config/gtk-3.0/settings.ini"
        gtk3.parent.mkdir(parents=True)
        gtk3.write_text("[Settings]\ngtk-theme-name=Adwaita-dark\n")
        staged = self.home / ".local/state/omarchy/current/theme"
        staged.mkdir(parents=True)
        (staged / "icons.theme").write_text("Yaru-yellow\n")

        done = self.apply("Papirus")
        self.assertEqual(done.returncode, 0, done.stderr)

        self.assertIn('set org.gnome.desktop.interface icon-theme Papirus', self.log.read_text())
        self.assertEqual(gtk3.read_text(), "[Settings]\ngtk-icon-theme-name=Papirus\ngtk-theme-name=Adwaita-dark\n")
        self.assertEqual((self.home / ".config/gtk-4.0/settings.ini").read_text(), "[Settings]\ngtk-icon-theme-name=Papirus\n")
        self.assertEqual((self.home / ".icons/default/index.theme").read_text(), "[Icon Theme]\nInherits=Papirus\n")
        self.assertEqual((staged / "icons.theme").read_text(), "Papirus\n")

    def test_an_existing_icon_key_is_replaced_not_duplicated(self):
        gtk3 = self.home / ".config/gtk-3.0/settings.ini"
        gtk3.parent.mkdir(parents=True)
        gtk3.write_text("[Settings]\ngtk-icon-theme-name=Adwaita\ngtk-theme-name=Adwaita-dark\n")
        self.assertEqual(self.apply("Yaru").returncode, 0)
        self.assertEqual(gtk3.read_text(), "[Settings]\ngtk-icon-theme-name=Yaru\ngtk-theme-name=Adwaita-dark\n")

    def test_kde_and_qt_files_are_only_touched_when_present(self):
        self.assertEqual(self.apply("Papirus").returncode, 0)
        self.assertFalse((self.home / ".config/kdeglobals").exists())
        self.assertFalse((self.home / ".config/qt6ct/qt6ct.conf").exists())

        kde = self.home / ".config/kdeglobals"
        kde.write_text("[General]\nColorScheme=BreezeDark\n\n[Icons]\nTheme=Adwaita\n")
        qt = self.home / ".config/qt6ct/qt6ct.conf"
        qt.parent.mkdir(parents=True)
        qt.write_text("[Appearance]\nstyle=kvantum\nicon_theme=Adwaita\n")
        self.assertEqual(self.apply("Papirus").returncode, 0)
        self.assertEqual(kde.read_text(), "[General]\nColorScheme=BreezeDark\n\n[Icons]\nTheme=Papirus\n")
        self.assertEqual(qt.read_text(), "[Appearance]\nstyle=kvantum\nicon_theme=Papirus\n")

    def test_install_without_git_refuses_before_touching_anything(self):
        # A PATH holding bash and nothing else: `command -v git` must fail
        # before a download or a write can start.
        os.symlink(shutil.which("bash"), self.bin / "bash")
        done = run(["install"], self.home, str(self.bin))
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("git is not installed", done.stderr)
        self.assertFalse(self.log.exists())
        self.assertFalse((self.home / ".local/share/icons").exists())

    def test_install_fetches_the_pinned_release_and_applies_what_it_installed(self):
        clone_log = self.bin / "clone.log"
        git = self.bin / "git"
        git.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"$*\" >> " + str(clone_log) + "\n"
            "dest=\"${@: -1}\"\n"
            "mkdir -p \"$dest\"\n"
            "cat > \"$dest/install.sh\" <<'EOF'\n"
            "#!/usr/bin/env bash\n"
            "while [ $# -gt 0 ]; do case \"$1\" in -d) dest=$2; shift 2;; *) shift;; esac; done\n"
            "mkdir -p \"$dest/WhiteSur\"\n"
            "printf '[Icon Theme]\\nName=WhiteSur\\n' > \"$dest/WhiteSur/index.theme\"\n"
            "echo \"Installing 'WhiteSur'...\"\n"
            "EOF\n"
        )
        git.chmod(0o755)

        done = run(["install"], self.home, self.path)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "WhiteSur")
        clone = clone_log.read_text()
        self.assertIn("--branch 2026-09-10", clone)
        self.assertIn("vinceliuice/WhiteSur-icon-theme", clone)
        self.assertTrue((self.home / ".local/share/icons/WhiteSur/index.theme").is_file())
        self.assertIn("icon-theme WhiteSur", self.log.read_text())

    def test_a_theme_id_that_is_not_a_name_is_refused_before_any_write(self):
        for bad in ["../etc", "a b", "$(id)", "a;b", ""]:
            done = self.apply(bad)
            self.assertEqual(done.returncode, 2, bad)
            self.assertIn("invalid theme id", done.stderr)
        self.assertFalse(self.log.exists(), "gsettings must not be called for a rejected id")
        self.assertFalse((self.home / ".config/gtk-3.0/settings.ini").exists())


if __name__ == "__main__":
    unittest.main()
