#!/usr/bin/env python3
"""scripts/icon-theme.sh: the list it prints, the files an apply writes, and
the install/apply failure paths a real user hits.

Every apply below runs against a throwaway HOME and a stub `gsettings` on
PATH: the real dconf would be the live desktop's icon theme, and a test must
never change that (a sandbox HOME does not scope gsettings — measured, it is a
D-Bus call into the session). Installs use a stub `git`; no network is touched.
"""
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "icon-theme.sh"


def run(args, home, path=None, extra_env=None):
    env = dict(os.environ)
    env["HOME"] = str(home)
    if path is not None:
        env["PATH"] = path
    if extra_env:
        env.update(extra_env)
    return subprocess.run(["bash", str(SCRIPT)] + args, capture_output=True, text=True, env=env)


def write_theme(home, theme, complete=True):
    """A theme directory, optionally the index-only husk a killed copy leaves."""
    base = home / ".local/share/icons" / theme
    base.mkdir(parents=True, exist_ok=True)
    (base / "index.theme").write_text("[Icon Theme]\nName=%s\n" % theme)
    if complete:
        (base / "apps").mkdir(exist_ok=True)
        (base / "apps" / "app.svg").write_text("<svg/>")
    return base


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

    def test_an_index_only_husk_is_not_advertised_until_it_has_artwork(self):
        home = Path(tempfile.mkdtemp())
        base = write_theme(home, "WhiteSur", complete=False)
        done = run(["list"], home)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertNotIn("WhiteSur", done.stdout)
        (base / "apps").mkdir()
        (base / "apps" / "app.svg").write_text("<svg/>")
        done = run(["list"], home)
        self.assertIn("WhiteSur|WhiteSur|", done.stdout)

    def test_space_and_non_ascii_ids_are_not_offered(self):
        home = Path(tempfile.mkdtemp())
        write_theme(home, "Bad Theme")
        write_theme(home, "Tëma")
        done = run(["list"], home)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertNotIn("Bad Theme", done.stdout)
        self.assertNotIn("Tëma", done.stdout)


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
        write_theme(self.home, "Papirus")
        gtk3 = self.home / ".config/gtk-3.0/settings.ini"
        gtk3.parent.mkdir(parents=True)
        gtk3.write_text("[Settings]\ngtk-theme-name=Adwaita-dark\n")
        staged = self.home / ".local/state/omarchy/current/theme"
        staged.mkdir(parents=True)
        (staged / "icons.theme").write_text("Yaru-yellow\n")

        done = self.apply("Papirus")
        self.assertEqual(done.returncode, 0, done.stderr)

        self.assertIn("set org.gnome.desktop.interface icon-theme Papirus", self.log.read_text())
        self.assertEqual(gtk3.read_text(), "[Settings]\ngtk-icon-theme-name=Papirus\ngtk-theme-name=Adwaita-dark\n")
        self.assertEqual((self.home / ".config/gtk-4.0/settings.ini").read_text(), "[Settings]\ngtk-icon-theme-name=Papirus\n")
        self.assertEqual((self.home / ".icons/default/index.theme").read_text(), "[Icon Theme]\nInherits=Papirus\n")
        self.assertEqual((staged / "icons.theme").read_text(), "Papirus\n")

    def test_an_existing_icon_key_is_replaced_not_duplicated(self):
        write_theme(self.home, "Yaru")
        gtk3 = self.home / ".config/gtk-3.0/settings.ini"
        gtk3.parent.mkdir(parents=True)
        gtk3.write_text("[Settings]\ngtk-icon-theme-name=Adwaita\ngtk-theme-name=Adwaita-dark\n")
        self.assertEqual(self.apply("Yaru").returncode, 0)
        self.assertEqual(gtk3.read_text(), "[Settings]\ngtk-icon-theme-name=Yaru\ngtk-theme-name=Adwaita-dark\n")

    def test_kde_and_qt_files_are_only_touched_when_present(self):
        write_theme(self.home, "Papirus")
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

    def test_a_theme_removed_after_the_list_was_read_is_refused(self):
        base = write_theme(self.home, "Papirus")
        self.assertEqual(self.apply("Papirus").returncode, 0)
        before = self.log.read_text()
        shutil.rmtree(base)
        done = self.apply("Papirus")
        self.assertEqual(done.returncode, 6, done.stderr)
        self.assertIn("not installed", done.stderr)
        self.assertEqual(self.log.read_text(), before, "gsettings must not run for a missing theme")

    def test_uppercase_ids_are_applicable(self):
        write_theme(self.home, "MixedCase")
        done = self.apply("MixedCase")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("icon-theme MixedCase", self.log.read_text())

    def test_space_and_non_ascii_ids_are_refused_before_any_write(self):
        for bad in ["../etc", "a b", "Bad Theme", "Tëma", "日本", "$(id)", "a;b", ""]:
            done = self.apply(bad)
            self.assertEqual(done.returncode, 2, bad)
            self.assertIn("invalid theme id", done.stderr)
        self.assertFalse(self.log.exists(), "gsettings must not be called for a rejected id")
        self.assertFalse((self.home / ".config/gtk-3.0/settings.ini").exists())


class InstallTheme(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.bin = Path(tempfile.mkdtemp())
        self.log = self.bin / "gsettings.log"
        stub = self.bin / "gsettings"
        stub.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> " + str(self.log) + "\nexit 0\n")
        stub.chmod(0o755)
        self.path = str(self.bin) + ":" + os.environ.get("PATH", "/usr/bin:/bin")
        self.clone_log = self.bin / "clone.log"

    def git(self, body):
        stub = self.bin / "git"
        stub.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"$*\" >> " + str(self.clone_log) + "\n"
            "dest=\"${@: -1}\"\n" + body
        )
        stub.chmod(0o755)

    def successful_clone(self, name="WhiteSur"):
        self.git(
            "mkdir -p \"$dest\"\n"
            "cat > \"$dest/install.sh\" <<'EOF'\n"
            "#!/usr/bin/env bash\n"
            "while [ $# -gt 0 ]; do case \"$1\" in -d) dest=$2; shift 2;; *) shift;; esac; done\n"
            "mkdir -p \"$dest/" + name + "/apps\"\n"
            "printf '<svg/>' > \"$dest/" + name + "/apps/app.svg\"\n"
            "printf '[Icon Theme]\\nName=" + name + "\\n' > \"$dest/" + name + "/index.theme\"\n"
            "echo \"Installing '" + name + "'...\"\n"
            "EOF\n"
        )

    def install(self, extra_env=None):
        return run(["install"], self.home, self.path, extra_env)

    def git_config(self, path, body, extra_env=None):
        path.write_text(body)
        env = {"GIT_CONFIG_GLOBAL": str(path), "GIT_CONFIG_NOSYSTEM": "1",
               "GIT_ASKPASS": "/bin/false", "SSH_ASKPASS": "/bin/false",
               "HTTP_PROXY": "", "HTTPS_PROXY": "", "ALL_PROXY": "",
               "http_proxy": "", "https_proxy": "", "all_proxy": "",
               "NO_PROXY": "*"}
        if extra_env:
            env.update(extra_env)
        return env

    def local_upstream(self, slow=False):
        """A real git repository with the pinned tag and a fake installer."""
        repo = self.home / "upstream"
        repo.mkdir()
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@example.invalid"], check=True)
        subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
        install = repo / "install.sh"
        delay = "sleep 1\n" if slow else ""
        install.write_text(
            "#!/usr/bin/env bash\n"
            "while [ $# -gt 0 ]; do case \"$1\" in -d) dest=$2; shift 2;; *) shift;; esac; done\n"
            + delay +
            "mkdir -p \"$dest/WhiteSur/apps\"\n"
            "printf '<svg/>' > \"$dest/WhiteSur/apps/app.svg\"\n"
            "printf '[Icon Theme]\\nName=WhiteSur\\n' > \"$dest/WhiteSur/index.theme\"\n"
        )
        subprocess.run(["git", "-C", str(repo), "add", "install.sh"], check=True)
        subprocess.run(["git", "-C", str(repo), "commit", "-qm", "fake upstream"], check=True)
        subprocess.run(["git", "-C", str(repo), "tag", "2026-09-10"], check=True)
        return repo

    def slow_git(self):
        """Real git, with the clone delayed so two runs overlap for real."""
        real = shutil.which("git")
        stub = self.bin / "git"
        stub.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"$*\" >> " + str(self.clone_log) + "\n"
            "if [ \"${1:-}\" = clone ]; then sleep 0.4; fi\n"
            "exec " + real + " \"$@\"\n"
        )
        stub.chmod(0o755)

    def start_install(self, env):
        run_env = dict(os.environ, HOME=str(self.home), PATH=self.path)
        run_env.update(env)
        return subprocess.Popen(["bash", str(SCRIPT), "install"], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, env=run_env)

    def start_slow_clone(self, body):
        self.git(
            "mkdir -p \"$dest\"\n"
            "printf 'partial clone' > \"$dest/partial\"\n" + body
        )
        env = dict(os.environ, HOME=str(self.home), PATH=self.path)
        return subprocess.Popen(["bash", str(SCRIPT), "install"], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, env=env, start_new_session=True)

    def wait_for_partial_stage(self, proc):
        for _ in range(100):
            stages = list((self.home / ".local/share").glob(".omadock-whitesur.*"))
            if stages and any((s / "src/partial").exists() for s in stages):
                return stages
            if proc.poll() is not None:
                break
            time.sleep(0.05)
        out, err = proc.communicate(timeout=10)
        self.fail("the clone never reached its partial stage: %s %s" % (out, err))

    def list_ids(self):
        done = run(["list"], self.home)
        self.assertEqual(done.returncode, 0, done.stderr)
        return {line.split("|")[0] for line in done.stdout.splitlines() if line}

    def test_network_failure_leaves_no_theme_and_the_retry_installs(self):
        flag = self.bin / "fail-once"
        flag.write_text("1")
        self.git(
            "if [ -f \"" + str(flag) + "\" ]; then\n"
            "  rm -f \"" + str(flag) + "\"\n"
            "  mkdir -p \"$dest\"\n"
            "  printf 'partial' > \"$dest/partial\"\n"
            "  exit 128\n"
            "fi\n"
            "mkdir -p \"$dest\"\n"
            "cat > \"$dest/install.sh\" <<'EOF'\n"
            "#!/usr/bin/env bash\n"
            "while [ $# -gt 0 ]; do case \"$1\" in -d) dest=$2; shift 2;; *) shift;; esac; done\n"
            "mkdir -p \"$dest/WhiteSur/apps\"\n"
            "printf '<svg/>' > \"$dest/WhiteSur/apps/app.svg\"\n"
            "printf '[Icon Theme]\\nName=WhiteSur\\n' > \"$dest/WhiteSur/index.theme\"\n"
            "EOF\n"
        )
        failed = self.install()
        self.assertEqual(failed.returncode, 4, failed.stderr)
        self.assertIn("check your connection", failed.stderr)
        self.assertNotIn("WhiteSur", self.list_ids())
        self.assertFalse((self.home / ".local/share/icons/WhiteSur").exists())

        retried = self.install()
        self.assertEqual(retried.returncode, 0, retried.stderr)
        self.assertEqual(retried.stdout.strip(), "WhiteSur")
        self.assertIn("WhiteSur", self.list_ids())
        self.assertTrue((self.home / ".local/share/icons/WhiteSur/apps").is_dir())
        self.assertEqual(len(list((self.home / ".local/share/icons").glob("WhiteSur*"))), 1)
        self.assertEqual(list((self.home / ".local/share").glob(".omadock-*")), [])

    def test_a_clone_killed_mid_fetch_leaves_nothing_advertised_and_retries(self):
        proc = self.start_slow_clone("sleep 30\n")
        stages = self.wait_for_partial_stage(proc)
        self.assertTrue(stages)
        # The whole session, as a terminal's Ctrl-C or a shell shutdown would:
        # the clone dies, the script's trap removes the stage.
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        proc.communicate(timeout=10)
        self.assertNotEqual(proc.returncode, 0)
        self.assertNotIn("WhiteSur", self.list_ids())
        self.assertFalse((self.home / ".local/share/icons/WhiteSur").exists())
        self.assertEqual(list((self.home / ".local/share").glob(".omadock-*")), [])

        self.successful_clone()
        retried = self.install()
        self.assertEqual(retried.returncode, 0, retried.stderr)
        self.assertIn("WhiteSur", self.list_ids())
        self.assertEqual(list((self.home / ".local/share").glob(".omadock-*")), [])

    def test_a_kill_9_mid_fetch_is_never_advertised_and_does_not_block_a_retry(self):
        proc = self.start_slow_clone("sleep 30\n")
        self.wait_for_partial_stage(proc)
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        proc.communicate(timeout=10)
        # SIGKILL cannot run the trap: the stage stays, but it is hidden,
        # outside both icon roots, and has no index.theme, so `list` never
        # advertises it and `apply` cannot reach it.
        self.assertNotIn("WhiteSur", self.list_ids())
        self.assertFalse((self.home / ".local/share/icons/WhiteSur").exists())

        self.successful_clone()
        retried = self.install()
        self.assertEqual(retried.returncode, 0, retried.stderr)
        self.assertIn("WhiteSur", self.list_ids())
        self.assertTrue((self.home / ".local/share/icons/WhiteSur/index.theme").is_file())
        # The retry holds the lock and sees the dead owner's PID, so the orphan
        # is reclaimed; the theme itself was never advertised.
        self.assertEqual(list((self.home / ".local/share").glob(".omadock-*")), [])

    def test_an_orphan_without_a_pid_file_is_left_alone(self):
        orphan = self.home / ".local/share/.omadock-whitesur.old"
        orphan.mkdir(parents=True)
        (orphan / "partial").write_text("unknown owner")
        self.successful_clone()
        done = self.install()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue((orphan / "partial").is_file(),
                        "a stage with no proven-dead owner must not be deleted")

    def test_a_real_clone_against_an_unreachable_remote_is_one_quiet_sentence(self):
        cfg = self.git_config(
            self.bin / "gitconfig-unreachable",
            '[url "https://127.0.0.1:1/blocked/"]\n'
            "\tinsteadOf = https://github.com/vinceliuice/WhiteSur-icon-theme\n",
        )
        cfg["OMADOCK_ICON_TIMEOUT"] = "20"
        failed = self.install(cfg)
        self.assertEqual(failed.returncode, 4, failed.stderr)
        self.assertIn("could not download WhiteSur", failed.stderr)
        self.assertIn("check your connection", failed.stderr)
        # Git's own diagnostics (fatal:, the host, the proxy) belong in the
        # stage log, not in the settings row.
        self.assertNotIn("fatal:", failed.stderr.lower())
        self.assertNotIn("127.0.0.1", failed.stderr)
        self.assertNotIn("WhiteSur", self.list_ids())
        self.assertEqual(list((self.home / ".local/share").glob(".omadock-*")), [])
        self.assertFalse(self.log.exists(), "a failed download must not apply anything")

    def test_a_real_local_remote_installs_once_and_applies_it(self):
        repo = self.local_upstream()
        cfg = self.git_config(
            self.bin / "gitconfig-local",
            '[url "file://%s"]\n\tinsteadOf = https://github.com/vinceliuice/WhiteSur-icon-theme.git\n' % repo,
        )
        cfg["OMADOCK_ICON_TIMEOUT"] = "30"
        done = self.install(cfg)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "WhiteSur")
        self.assertIn("WhiteSur", self.list_ids())
        self.assertIn("icon-theme WhiteSur", self.log.read_text())
        self.assertEqual(list((self.home / ".local/share").glob(".omadock-*")), [])

    def test_two_real_installs_overlap_without_a_nested_or_duplicate_theme(self):
        repo = self.local_upstream(slow=True)
        self.slow_git()
        cfg = self.git_config(
            self.bin / "gitconfig-concurrent",
            '[url "file://%s"]\n\tinsteadOf = https://github.com/vinceliuice/WhiteSur-icon-theme.git\n' % repo,
        )
        cfg["OMADOCK_ICON_TIMEOUT"] = "30"
        first = self.start_install(cfg)
        second = self.start_install(cfg)
        first_out = first.communicate(timeout=30)
        second_out = second.communicate(timeout=30)
        self.assertEqual(first.returncode, 0, first_out)
        self.assertEqual(second.returncode, 0, second_out)

        icons = self.home / ".local/share/icons"
        self.assertFalse((icons / "WhiteSur/WhiteSur").exists(), "one install moved the other's theme into its own directory")
        self.assertEqual(len(list(icons.glob("WhiteSur*"))), 1)
        rows = [line for line in run(["list"], self.home).stdout.splitlines() if line.startswith("WhiteSur|")]
        self.assertEqual(len(rows), 1, rows)
        self.assertTrue((icons / "WhiteSur/index.theme").is_file())
        self.assertEqual(list((self.home / ".local/share").glob(".omadock-*")), [])
        # A serialised pair clones once: the second waits, then applies the
        # complete theme the first installed.
        self.assertEqual(len(self.clone_log.read_text().splitlines()), 1)

    def test_apply_arriving_during_an_install_wins_after_it_finishes(self):
        write_theme(self.home, "Yaru")
        repo = self.local_upstream(slow=True)
        self.slow_git()
        cfg = self.git_config(
            self.bin / "gitconfig-apply-during-install",
            '[url "file://%s"]\n\tinsteadOf = https://github.com/vinceliuice/WhiteSur-icon-theme.git\n' % repo,
        )
        cfg["OMADOCK_ICON_TIMEOUT"] = "30"
        installing = self.start_install(cfg)
        # Wait until the install has its lock and a stage on disk, so apply
        # genuinely arrives in the middle of the clone rather than before it.
        for _ in range(100):
            if list((self.home / ".local/share").glob(".omadock-whitesur.*")):
                break
            time.sleep(0.05)
        else:
            installing.kill()
            self.fail("the install never staged")
        applied = run(["apply", "Yaru"], self.home, self.path, cfg)
        _out, err = installing.communicate(timeout=30)
        self.assertEqual(installing.returncode, 0, err)
        self.assertEqual(applied.returncode, 0, applied.stderr)
        self.assertEqual((self.home / ".icons/default/index.theme").read_text(),
                         "[Icon Theme]\nInherits=Yaru\n")
        self.assertEqual(self.log.read_text().splitlines()[-1],
                         "set org.gnome.desktop.interface icon-theme Yaru")

    def test_second_install_is_idempotent_and_does_not_clone_again(self):
        self.successful_clone()
        first = self.install()
        self.assertEqual(first.returncode, 0, first.stderr)
        clones = self.clone_log.read_text().splitlines()
        self.assertTrue(clones)
        # The picker hides the entry once installed; a direct second call must
        # still not download or duplicate anything.
        self.git("exit 99\n")
        second = self.install()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout.strip(), "WhiteSur")
        self.assertEqual(self.clone_log.read_text().splitlines(), clones, "a complete install must not clone again")
        self.assertEqual(len(list((self.home / ".local/share/icons").glob("WhiteSur*"))), 1)

    def test_an_index_only_white_sur_is_replaced_by_a_complete_install(self):
        base = write_theme(self.home, "WhiteSur", complete=False)
        self.assertNotIn("WhiteSur", self.list_ids())
        self.successful_clone()
        done = self.install()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue((base / "apps").is_dir())
        self.assertIn("WhiteSur", self.list_ids())

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
        self.successful_clone()
        done = self.install()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "WhiteSur")
        clone = self.clone_log.read_text()
        self.assertIn("--branch 2026-09-10", clone)
        self.assertIn("vinceliuice/WhiteSur-icon-theme", clone)
        self.assertTrue((self.home / ".local/share/icons/WhiteSur/index.theme").is_file())
        self.assertIn("icon-theme WhiteSur", self.log.read_text())


if __name__ == "__main__":
    unittest.main()
