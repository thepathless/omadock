import importlib.util
import os
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("bench", ROOT / "tests" / "bench" / "bench.py")
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class ParseStat(unittest.TestCase):
    def test_plain_name(self):
        line = "123 (quickshell) S 1 2 3 4 5 6 7 8 9 10 250 50 0 0 20 0 18 0"
        self.assertEqual(bench.parse_stat(line), ("quickshell", 300))

    def test_name_with_spaces_and_parens(self):
        line = "124 ([pango] fon(t)) S 1 2 3 4 5 6 7 8 9 10 7 3 0 0 20 0 1 0"
        self.assertEqual(bench.parse_stat(line), ("[pango] fon(t)", 10))


class ReadProc(unittest.TestCase):
    def test_missing_pid_returns_none(self):
        self.assertIsNone(bench.read_proc_sample(999999999))
        self.assertIsNone(bench.read_threads(999999999))

    def test_self_sample_has_fields(self):
        s = bench.read_proc_sample(os.getpid())
        for key in ("rss_kb", "pss_kb", "threads", "fds", "ctxsw"):
            self.assertIn(key, s)
        self.assertGreater(s["rss_kb"], 0)
        self.assertGreaterEqual(s["threads"], 1)


class NvidiaXml(unittest.TestCase):
    def test_parses_graphics_processes(self):
        xml = """<nvidia_smi_log><gpu><processes>
        <process_info><pid>1507</pid><type>G</type><used_memory>757 MiB</used_memory></process_info>
        <process_info><pid>42</pid><type>G</type><used_memory>692 MiB</used_memory></process_info>
        <process_info><pid>7</pid><type>C</type><used_memory>N/A</used_memory></process_info>
        </processes></gpu></nvidia_smi_log>"""
        self.assertEqual(bench.parse_nvidia_xml(xml), {1507: 757, 42: 692})

    def test_garbage_gives_empty(self):
        self.assertEqual(bench.parse_nvidia_xml("not xml"), {})


class Stats(unittest.TestCase):
    def test_cpu_pct(self):
        self.assertAlmostEqual(bench.cpu_pct(50, 10.0, 100), 5.0)
        self.assertEqual(bench.cpu_pct(5, 0.0, 100), 0.0)

    def test_summarize(self):
        self.assertEqual(bench.summarize([3, 1, 2]), {"median": 2, "min": 1, "max": 3})
        self.assertEqual(bench.summarize([]), {"median": None, "min": None, "max": None})


class SamplerSelf(unittest.TestCase):
    def test_sampler_on_own_process(self):
        s = bench.Sampler(os.getpid(), None, interval=0.05, vram_interval=10)
        s.start()
        sum(i * i for i in range(300000))
        m = s.stop()
        self.assertTrue(m["valid"])
        self.assertGreater(m["rss_mb"], 0)
        self.assertGreaterEqual(m["cpu_pct"], 0)
        self.assertIn("cpu_threads", m)


class Geometry(unittest.TestCase):
    ITEMS = [
        {"id": "b", "kind": "app", "x": 300, "y": 1300, "w": 60, "h": 60, "windows": 3, "urgent": False},
        {"id": "a", "kind": "app", "x": 200, "y": 1300, "w": 60, "h": 60, "windows": 1, "urgent": True},
        {"id": "f", "kind": "folder", "x": 400, "y": 1300, "w": 60, "h": 60, "windows": 0, "urgent": False},
    ]

    def test_to_screen_adds_centres(self):
        out = bench.to_screen(self.ITEMS, {"x": 10, "y": 36})
        self.assertEqual((out[0]["cx"], out[0]["cy"]), (340, 1366))

    def test_sweep_path_goes_there_and_back(self):
        pts = bench.sweep_path(bench.to_screen(self.ITEMS, {"x": 0, "y": 0}))
        self.assertEqual([p[0] for p in pts], [230, 330, 430, 330])

    def test_sweep_path_empty(self):
        self.assertEqual(bench.sweep_path([]), [])

    def test_pick_targets(self):
        t = bench.pick_targets(self.ITEMS)
        self.assertEqual(t["multi"]["id"], "b")
        self.assertEqual(t["urgent"]["id"], "a")

    def test_pick_targets_none(self):
        t = bench.pick_targets([self.ITEMS[2]])
        self.assertIsNone(t["multi"])
        self.assertIsNone(t["urgent"])


class Workspaces(unittest.TestCase):
    def test_free_workspace_skips_used(self):
        self.assertEqual(bench.first_free_workspace([1, 2, 3, 5]), "4")
        self.assertEqual(bench.first_free_workspace([]), "1")
        self.assertEqual(bench.first_free_workspace([-98, 1]), "2")

class Report(unittest.TestCase):
    def test_result_path(self):
        import time as _t
        when = _t.strptime("2026-10-02 14:05", "%Y-%m-%d %H:%M")
        self.assertEqual(bench.result_path("bench/results", "tower", when),
                         "bench/results/2026-10-02-1405-tower.json")

    def test_dock_cost(self):
        cost = bench.dock_cost({"vram_mib": 496, "rss_mb": 858.0, "cpu_pct": None},
                               {"vram_mib": 690, "rss_mb": 896.5, "cpu_pct": 1.2})
        self.assertEqual(cost["vram_mib"], 194)
        self.assertAlmostEqual(cost["rss_mb"], 38.5)
        self.assertIsNone(cost["cpu_pct"])

def _report(cpu_runs, vram, commit="abc", pkgs=("quickshell 0.3.1-1",)):
    runs = [{"valid": True, "cpu_pct": c, "vram_mib": vram} for c in cpu_runs]
    return {"conditions": {"cpu": "X", "gpu": "G", "packages": list(pkgs),
                           "config_sha256": "h", "monitors": ["DP-1"], "dock_commit": commit},
            "scenarios": {"S0": {"runs": runs, "summary": bench.summarize_runs(runs), "skipped": None},
                          "S2": {"runs": [], "summary": {}, "skipped": "no app"}}}


class Compare(unittest.TestCase):
    def test_rows_and_noise(self):
        a = _report([1.0, 1.2, 1.1], 690)
        b = _report([0.5, 0.6, 0.55], 520, commit="def")
        rows, warnings = bench.compare_reports(a, b)
        cpu = next(r for r in rows if r["scenario"] == "S0" and r["metric"] == "cpu_pct")
        self.assertAlmostEqual(cpu["diff"], -0.55)
        self.assertFalse(cpu["noise"])
        self.assertEqual(warnings, [])
        self.assertFalse(any(r["scenario"] == "S2" for r in rows))

    def test_small_diff_is_noise(self):
        rows, _ = bench.compare_reports(_report([1.0, 1.4], 690), _report([1.1, 1.3], 690))
        cpu = next(r for r in rows if r["metric"] == "cpu_pct")
        self.assertTrue(cpu["noise"])

    def test_warns_on_different_conditions(self):
        _, warnings = bench.compare_reports(_report([1], 1), _report([1], 1, pkgs=("quickshell 0.4.0-1",)))
        self.assertTrue(any("packages" in w for w in warnings))

class ExitedThreads(unittest.TestCase):
    def _burn(self, seconds):
        import time as _t
        end = _t.thread_time() + seconds
        while _t.thread_time() < end:
            pass

    def test_cpu_counts_threads_that_exit_mid_window(self):
        import threading
        s = bench.Sampler(os.getpid(), None, interval=0.05, vram_interval=100)
        s.start()
        t = threading.Thread(target=self._burn, args=(0.4,))
        t.start()
        t.join()
        m = s.stop()
        cpu_seconds = m["cpu_pct"] * m["seconds"] / 100
        self.assertGreaterEqual(cpu_seconds, 0.3)

    def test_read_proc_ticks(self):
        self.assertIsNone(bench.read_proc_ticks(999999999))
        self.assertGreaterEqual(bench.read_proc_ticks(os.getpid()), 0)


class ContextSwitches(unittest.TestCase):
    def test_ctxsw_counts_every_thread(self):
        import threading, time as _t
        stop = threading.Event()

        def nap():
            while not stop.is_set():
                _t.sleep(0.001)

        t = threading.Thread(target=nap)
        t.start()
        _t.sleep(0.3)
        try:
            main_only = sum(bench._status_value(open(f"/proc/{os.getpid()}/status").read(), k)
                            for k in ("voluntary_ctxt_switches", "nonvoluntary_ctxt_switches"))
            sample = bench.read_proc_sample(os.getpid())
        finally:
            stop.set()
            t.join()
        self.assertGreater(sample["ctxsw"], main_only + 50)


class FakeDesktop:
    def __init__(self, visible_after_reveal=True):
        self.revealed = False
        self.visible_after_reveal = visible_after_reveal
        self.calls = []

    def ipc(self, fn, *args):
        self.calls.append(fn)
        if fn == "reveal":
            self.revealed = True
        return ""

    def items(self):
        if self.revealed and self.visible_after_reveal:
            return [{"id": "a", "kind": "app", "cx": 10, "cy": 20, "windows": 2}]
        return []

    def layer(self):
        return {"x": 0, "y": 0, "w": 100, "h": 100} if self.visible_after_reveal else None


class Reveal(unittest.TestCase):
    def test_prepare_items_reveals_hidden_dock(self):
        d = FakeDesktop()
        self.assertEqual(len(bench.prepare_items(d, wait=0)), 1)
        self.assertIn("reveal", d.calls)

    def test_prepare_items_gives_up(self):
        self.assertEqual(bench.prepare_items(FakeDesktop(visible_after_reveal=False), wait=0), [])


class Dwell(unittest.TestCase):
    def _cfg(self, text):
        import tempfile
        f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        f.write(text)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_dwell_exceeds_tooltip_delay(self):
        self.assertAlmostEqual(bench.hover_dwell(self._cfg('{"tooltipDelay": 1000}')), 1.15)

    def test_dwell_default(self):
        self.assertAlmostEqual(bench.hover_dwell(self._cfg("garbage{")), 0.6)
        self.assertAlmostEqual(bench.hover_dwell("/nonexistent/omadock.json"), 0.6)


class FullState(unittest.TestCase):
    def test_disabled_dock_must_have_no_layer(self):
        self.assertIsNone(bench.full_state_error(FakeDesktop(visible_after_reveal=False), False))
        self.assertIn("still mapped", bench.full_state_error(FakeDesktop(), False))

    def test_enabled_dock_must_have_layer(self):
        self.assertIsNone(bench.full_state_error(FakeDesktop(), True))
        self.assertIn("not mapped", bench.full_state_error(FakeDesktop(visible_after_reveal=False), True))

class ShellPid(unittest.TestCase):
    def test_picks_the_omarchy_shell_not_another_quickshell(self):
        out = "2969780 /usr/bin/quickshell\n2973246 quickshell -n -p /usr/share/omarchy/shell\n"
        self.assertEqual(bench.pick_shell_pid(out), 2973246)

    def test_none_when_absent(self):
        self.assertIsNone(bench.pick_shell_pid("2969780 /usr/bin/quickshell\n"))
        self.assertIsNone(bench.pick_shell_pid(""))

class Soak(unittest.TestCase):
    def test_slope_per_hour(self):
        # 2 MB more every 30 minutes = 4 MB per hour
        xs = [0, 1800, 3600, 5400]
        ys = [100, 102, 104, 106]
        self.assertAlmostEqual(bench.slope_per_hour(xs, ys), 4.0)

    def test_slope_needs_two_points(self):
        self.assertIsNone(bench.slope_per_hour([0], [1]))
        self.assertIsNone(bench.slope_per_hour([5, 5], [1, 2]))

    def test_soak_summary_splits_at_restarts(self):
        samples = [
            {"t": 0, "pid": 1, "rss_mb": 100, "vram_mib": 400, "fds": 10},
            {"t": 3600, "pid": 1, "rss_mb": 110, "vram_mib": 400, "fds": 10},
            {"t": 3700, "pid": 2, "rss_mb": 50, "vram_mib": 300, "fds": 8},
            {"t": 7300, "pid": 2, "rss_mb": 51, "vram_mib": 300, "fds": 8},
        ]
        out = bench.soak_summary(samples)
        self.assertEqual(len(out["segments"]), 2)
        self.assertAlmostEqual(out["segments"][0]["rss_mb_per_h"], 10.0)
        self.assertAlmostEqual(out["segments"][1]["rss_mb_per_h"], 1.0)

if __name__ == "__main__":
    unittest.main()
