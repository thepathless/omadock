#!/usr/bin/env python3
"""OmaDock performance benchmark (stdlib only; needs a running Omarchy shell).

Measures the quickshell process (Omarchy shell + dock) and Hyprland in
fixed scenarios on the live desktop and writes a JSON report. Pointer
moves only; never clicks or types. See tests/bench/README.md.
"""

import argparse
import hashlib
import json
import os
import socket
import statistics
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET

CLK_TCK = os.sysconf("SC_CLK_TCK")


# --- pure helpers -----------------------------------------------------------

def parse_stat(text):
    """(comm, utime+stime) from a /proc stat line; comm may hold spaces/parens."""
    head, _, rest = text.rpartition(")")
    comm = head.split("(", 1)[1]
    fields = rest.split()
    # rest starts at field 3 (state); utime/stime are fields 14/15.
    return comm, int(fields[11]) + int(fields[12])


def read_threads(pid):
    """Ticks summed per thread name, or None when the process is gone."""
    try:
        tids = os.listdir(f"/proc/{pid}/task")
    except OSError:
        return None
    out = {}
    for tid in tids:
        try:
            with open(f"/proc/{pid}/task/{tid}/stat") as f:
                comm, ticks = parse_stat(f.read())
        except (OSError, IndexError, ValueError):
            continue
        out[comm] = out.get(comm, 0) + ticks
    return out


def _status_value(text, key):
    for line in text.splitlines():
        if line.startswith(key + ":"):
            return int(line.split()[1])
    return 0


def read_proc_sample(pid):
    """Memory/thread/fd snapshot, or None when the process is gone."""
    try:
        with open(f"/proc/{pid}/status") as f:
            status = f.read()
        with open(f"/proc/{pid}/smaps_rollup") as f:
            rollup = f.read()
        fds = len(os.listdir(f"/proc/{pid}/fd"))
    except OSError:
        return None
    return {
        "rss_kb": _status_value(status, "VmRSS"),
        "pss_kb": _status_value(rollup, "Pss"),
        "threads": _status_value(status, "Threads"),
        "fds": fds,
        "ctxsw": _task_ctxsw(pid),
    }


def _task_ctxsw(pid):
    """Context switches summed over every thread (status covers one task)."""
    total = 0
    try:
        tids = os.listdir(f"/proc/{pid}/task")
    except OSError:
        return 0
    for tid in tids:
        try:
            with open(f"/proc/{pid}/task/{tid}/status") as f:
                text = f.read()
        except OSError:
            continue
        total += (_status_value(text, "voluntary_ctxt_switches")
                  + _status_value(text, "nonvoluntary_ctxt_switches"))
    return total


def read_proc_ticks(pid):
    """utime+stime of the whole process, including threads that already
    exited (unlike a sum over /proc/<pid>/task), or None when it is gone."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            return parse_stat(f.read())[1]
    except (OSError, IndexError, ValueError):
        return None


def parse_nvidia_xml(xml_text):
    """pid -> used MiB for every process nvidia-smi reports with a number."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return {}
    out = {}
    for p in root.iter("process_info"):
        mem = (p.findtext("used_memory") or "").split()
        try:
            out[int(p.findtext("pid"))] = int(mem[0])
        except (TypeError, ValueError, IndexError):
            continue
    return out


def read_vram():
    try:
        r = subprocess.run(["nvidia-smi", "-q", "-x"], capture_output=True,
                           text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return {}
    return parse_nvidia_xml(r.stdout) if r.returncode == 0 else {}


def cpu_pct(ticks, seconds, clk_tck=CLK_TCK):
    if seconds <= 0:
        return 0.0
    return 100.0 * ticks / clk_tck / seconds


def summarize(values):
    vals = [v for v in values if v is not None]
    if not vals:
        return {"median": None, "min": None, "max": None}
    return {"median": statistics.median(vals), "min": min(vals), "max": max(vals)}


# --- sampler ----------------------------------------------------------------

class Sampler:
    """Samples a process (and optionally Hyprland) in a background thread."""

    def __init__(self, pid, hypr_pid, interval=0.25, vram_interval=1.0):
        self.pid, self.hypr_pid = pid, hypr_pid
        self.interval, self.vram_interval = interval, vram_interval
        self._stop = threading.Event()
        self._samples, self._vram, self._hvram = [], [], []
        self.valid = True

    def start(self):
        self._t0 = time.monotonic()
        self._threads0 = read_threads(self.pid)
        self._ticks0 = read_proc_ticks(self.pid)
        self._hyp0 = read_proc_ticks(self.hypr_pid) if self.hypr_pid else None
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def _loop(self):
        next_vram = 0.0
        while not self._stop.is_set():
            s = read_proc_sample(self.pid)
            if s is None:
                self.valid = False
                return
            self._samples.append(s)
            now = time.monotonic()
            if now >= next_vram:
                v = read_vram()
                self._vram.append(v.get(self.pid))
                if self.hypr_pid:
                    self._hvram.append(v.get(self.hypr_pid))
                next_vram = now + self.vram_interval
            self._stop.wait(self.interval)

    def stop(self):
        self._stop.set()
        self._thread.join()
        secs = time.monotonic() - self._t0
        threads1 = read_threads(self.pid)
        ticks1 = read_proc_ticks(self.pid)
        if (threads1 is None or self._threads0 is None or ticks1 is None
                or self._ticks0 is None or not self._samples):
            self.valid = False
        per = {}
        if self.valid:
            for name, t in threads1.items():
                d = t - self._threads0.get(name, 0)
                if d > 0:
                    per[name] = round(cpu_pct(d, secs), 2)
        hyp1 = read_proc_ticks(self.hypr_pid) if self.hypr_pid else None
        smp = self._samples
        med = lambda k: statistics.median([x[k] for x in smp]) if smp else None
        return {
            "valid": self.valid,
            "seconds": round(secs, 2),
            "rss_mb": round(med("rss_kb") / 1024, 1) if smp else None,
            "rss_mb_end": round(smp[-1]["rss_kb"] / 1024, 1) if smp else None,
            "pss_mb": round(med("pss_kb") / 1024, 1) if smp else None,
            "vram_mib": summarize(self._vram)["median"],
            "hypr_vram_mib": summarize(self._hvram)["median"],
            "cpu_pct": round(cpu_pct(ticks1 - self._ticks0, secs), 2)
            if self.valid else None,
            "cpu_threads": per,
            "hypr_cpu_pct": round(cpu_pct(hyp1 - self._hyp0, secs), 2)
            if hyp1 is not None and self._hyp0 is not None else None,
            "threads": smp[-1]["threads"] if smp else None,
            "fds": smp[-1]["fds"] if smp else None,
            "ctxsw_per_s": round((smp[-1]["ctxsw"] - smp[0]["ctxsw"]) / secs, 1)
            if len(smp) > 1 and secs > 0 else None,
        }


# --- driver -----------------------------------------------------------------
SHELL_PATH = "/usr/share/omarchy/shell"
OUTSIDE_Y = 1250      # enter the dock from above so hover-enter effects fire
MIN_DWELL = 0.6       # seconds per item while sweeping; above the default tooltip delay

SCENARIOS = [         # (name, seconds, description)
    ("S0", 30, "idle, pointer away from the dock"),
    ("S1", 30, "pointer sweeps across every item and back"),
    ("S2", 15, "tooltip of an app with >= 2 windows (window previews)"),
    ("S3", 15, "settings panel open"),
    ("S4", 30, "idle again after S1-S3 (leak check)"),
    ("S6", 15, "urgent window present, pointer away"),
]
EVENT_SWITCHES = 20


def to_screen(items, layer):
    out = []
    for it in items:
        it = dict(it)
        it["cx"] = layer["x"] + it["x"] + it["w"] // 2
        it["cy"] = layer["y"] + it["y"] + it["h"] // 2
        out.append(it)
    return out


def sweep_path(items):
    pts = [(it["cx"], it["cy"]) for it in sorted(items, key=lambda i: (i["cx"], i["cy"]))]
    return pts + pts[-2:0:-1] if len(pts) > 1 else pts


def pick_targets(items):
    multi = next((i for i in items if i["kind"] == "app" and i.get("windows", 0) >= 2), None)
    urgent = next((i for i in items if i.get("urgent")), None)
    return {"multi": multi, "urgent": urgent}


def hover_dwell(config_path):
    """Seconds to rest on each item so its tooltip opens (tooltipDelay + margin)."""
    try:
        with open(config_path) as f:
            delay = json.load(f).get("tooltipDelay")
    except (OSError, ValueError, AttributeError):
        delay = None
    if not isinstance(delay, (int, float)) or isinstance(delay, bool):
        return MIN_DWELL
    return max(MIN_DWELL, delay / 1000 + 0.15)


def prepare_items(desktop, wait=0.5, tries=3):
    """Reveal the dock and read item geometry once its slide-in is over.
    itemGeometry reports nothing while the dock is hidden."""
    for _ in range(tries):
        desktop.ipc("reveal")
        time.sleep(wait)
        items = desktop.items()
        if items:
            return items
    return []


def full_state_error(desktop, expect_dock):
    """None when the omadock layer matches the expected plugin state."""
    mapped = desktop.layer() is not None
    if expect_dock and not mapped:
        return "omadock layer not mapped after enabling the plugin"
    if not expect_dock and mapped:
        return "omadock layer still mapped after disabling the plugin"
    return None


def pick_shell_pid(pgrep_output):
    """The Omarchy shell's pid from `pgrep -a`; other quickshell instances
    (a different config) must not be measured."""
    for line in pgrep_output.splitlines():
        pid, _, cmd = line.partition(" ")
        if f"-p {SHELL_PATH}" in cmd and pid.isdigit():
            return int(pid)
    return None


def first_free_workspace(used_ids):
    used = {int(i) for i in used_ids}
    n = 1
    while n in used:
        n += 1
    return str(n)


def _run(cmd, timeout=10):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.stdout


class Desktop:
    """Everything that touches the live desktop. Pointer moves only."""

    def ipc(self, fn, *args):
        return _run(["qs", "-p", SHELL_PATH, "ipc", "call", "omadock", fn, *args]).strip()

    def hypr_json(self, *args):
        return json.loads(_run(["hyprctl", *args, "-j"]) or "null")

    def cursor(self):
        c = self.hypr_json("cursorpos")
        return int(c["x"]), int(c["y"])

    def move(self, x, y):
        _run(["hyprctl", "dispatch", f"hl.dsp.cursor.move({{x={int(x)}, y={int(y)}}})"])

    def layer(self):
        for mon in (self.hypr_json("layers") or {}).values():
            for layers in mon.get("levels", {}).values():
                for l in layers:
                    if l.get("namespace") == "omadock":
                        return l
        return None

    def items(self):
        layer = self.layer()
        if layer is None:
            return []
        try:
            raw = json.loads(self.ipc("itemGeometry") or "[]")
        except json.JSONDecodeError:
            return []
        return to_screen(raw, layer)

    def quickshell_pid(self):
        return pick_shell_pid(_run(["pgrep", "-a", "-x", "quickshell"]))

    def hyprland_pid(self):
        out = _run(["pgrep", "-x", "Hyprland"]).split()
        return int(out[0]) if out else None

    def active_workspace(self):
        return str(self.hypr_json("activeworkspace")["name"])

    def focus_workspace(self, name):
        safe = str(name).replace("\\", "\\\\").replace('"', '\\"')
        _run(["hyprctl", "dispatch", f'hl.dsp.focus({{ workspace = "{safe}" }})'])

    def free_workspace(self):
        return first_free_workspace([w["id"] for w in self.hypr_json("workspaces")])


def measure(desktop, seconds, action=None):
    """One run: sample for `seconds` while `action(deadline)` drives the desktop."""
    s = Sampler(desktop.quickshell_pid(), desktop.hyprland_pid())
    s.start()
    deadline = time.monotonic() + seconds
    if action:
        action(deadline)
    remaining = deadline - time.monotonic()
    if remaining > 0:
        time.sleep(remaining)
    return s.stop()


def run_scenarios(desktop, repeat, events, log):
    items = prepare_items(desktop)
    targets = pick_targets(items)
    dwell = hover_dwell(CONFIG)
    away = (desktop.layer() or {"x": 0, "w": 400})
    away_xy = (away["x"] + away["w"] // 2, OUTSIDE_Y // 2)
    results = {}

    def park():
        desktop.move(*away_xy)

    def sweep(deadline):
        path = sweep_path(prepare_items(desktop))
        if not path:
            return
        desktop.move(path[0][0], OUTSIDE_Y)
        while time.monotonic() < deadline:
            for x, y in path:
                if time.monotonic() >= deadline:
                    break
                desktop.move(x, y)
                time.sleep(dwell)

    def hover_multi(deadline):
        fresh = pick_targets(prepare_items(desktop))["multi"]
        t = fresh or targets["multi"]
        desktop.move(t["cx"], OUTSIDE_Y)
        time.sleep(0.2)
        desktop.move(t["cx"], t["cy"])

    def settings(deadline):
        desktop.ipc("openSettings")

    plan = [
        ("S0", None, None),
        ("S1", sweep, None if items else "no dock items found"),
        ("S2", hover_multi, None if targets["multi"] else "no app with >= 2 windows"),
        ("S3", settings, None),
        ("S4", None, None),
        ("S6", None, None if targets["urgent"] else "no urgent window"),
    ]
    durations = {name: secs for name, secs, _ in SCENARIOS}
    for name, action, skip in plan:
        if skip:
            log(f"{name}: skipped ({skip})")
            results[name] = {"runs": [], "summary": {}, "skipped": skip}
            continue
        runs = []
        for i in range(repeat):
            park()
            time.sleep(2)
            log(f"{name} run {i + 1}/{repeat} ({durations[name]} s)")
            runs.append(measure(desktop, durations[name], action))
            if name == "S3":
                desktop.ipc("closeSettings")
            park()
        results[name] = {"runs": runs, "summary": summarize_runs(runs), "skipped": None}
    if events:
        results["S5"] = run_events(desktop, repeat, log)
    return results


NUMERIC = ["rss_mb", "rss_mb_end", "pss_mb", "vram_mib", "hypr_vram_mib", "cpu_pct",
           "hypr_cpu_pct", "threads", "fds", "ctxsw_per_s"]


def summarize_runs(runs):
    good = [r for r in runs if r.get("valid")]
    return {k: summarize([r.get(k) for r in good]) for k in NUMERIC}


def run_events(desktop, repeat, log):
    home = desktop.active_workspace()
    other = desktop.free_workspace()
    runs = []
    try:
        for i in range(repeat):
            log(f"S5 run {i + 1}/{repeat} ({EVENT_SWITCHES} switches {home} <-> {other})")

            def flip(deadline):
                for n in range(EVENT_SWITCHES):
                    desktop.focus_workspace(other if n % 2 == 0 else home)
                    time.sleep(0.5)
                desktop.focus_workspace(home)

            runs.append(measure(desktop, EVENT_SWITCHES * 0.5 + 2, flip))
    finally:
        desktop.focus_workspace(home)
    return {"runs": runs, "summary": summarize_runs(runs), "skipped": None}
# --- report / CLI -----------------------------------------------------------

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG = os.path.expanduser("~/.config/omarchy/omadock.json")
SHELL_JSON = os.path.expanduser("~/.config/omarchy/shell.json")
SETTLE = 20          # seconds after a shell restart before measuring
# Results go outside the plugin directory: any file written inside it makes
# Quickshell reload the dock (and a soak writes every minute).
DEFAULT_OUT = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "omadock-bench")


def result_path(out_dir, host, when):
    return os.path.join(out_dir, time.strftime("%Y-%m-%d-%H%M", when) + f"-{host}.json")


def dock_cost(disabled, enabled):
    out = {}
    for k in NUMERIC:
        a, b = disabled.get(k), enabled.get(k)
        out[k] = round(b - a, 2) if a is not None and b is not None else None
    return out


def _sh(cmd):
    try:
        return _run(cmd).strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def conditions(desktop):
    cpu = next((l.split(":", 1)[1].strip() for l in open("/proc/cpuinfo")
                if l.startswith("model name")), "")
    mem_kb = _status_value(open("/proc/meminfo").read(), "MemTotal")
    pid = desktop.quickshell_pid()
    try:
        cfg = hashlib.sha256(open(CONFIG, "rb").read()).hexdigest()[:16]
    except OSError:
        cfg = None
    monitors = desktop.hypr_json("monitors") or []
    items = desktop.items()
    started = None
    if pid:
        boot = time.time() - float(open("/proc/uptime").read().split()[0])
        start_ticks = int(open(f"/proc/{pid}/stat").read().rpartition(")")[2].split()[19])
        started = round(time.time() - (boot + start_ticks / CLK_TCK))
    return {
        "host": socket.gethostname(),
        "cpu": cpu,
        "cores": os.cpu_count(),
        "ram_gb": round(mem_kb / 1024 / 1024, 1),
        "gpu": _sh(["nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"]),
        "kernel": os.uname().release,
        "packages": _sh(["pacman", "-Q", "omarchy", "quickshell", "hyprland", "qt6-base"]).splitlines(),
        "dock_commit": _sh(["git", "-C", REPO, "rev-parse", "--short", "HEAD"]),
        "dock_dirty": bool(_sh(["git", "-C", REPO, "status", "--porcelain", "--untracked-files=no"])),
        "config_sha256": cfg,
        "items": len(items),
        "items_by_kind": {k: sum(1 for i in items if i["kind"] == k) for k in {i["kind"] for i in items}},
        "windows": len(desktop.hypr_json("clients") or []),
        "monitors": [f'{m["name"]} {m["width"]}x{m["height"]}@{m["refreshRate"]:.0f} scale {m["scale"]}'
                     for m in monitors],
        "dock_layer": desktop.layer(),
        "quickshell_uptime_s": started,
        "loadavg": os.getloadavg(),
    }


def wait_quiet(log, limit=1.5, timeout=30):
    end = time.monotonic() + timeout
    while os.getloadavg()[0] > limit and time.monotonic() < end:
        time.sleep(2)
    load = os.getloadavg()[0]
    if load > limit:
        log(f"warning: load average {load:.2f} stays above {limit}; results may be noisy")
    return load


def restart_shell(desktop, log):
    _run(["omarchy", "restart", "shell"], timeout=60)
    for _ in range(60):
        if desktop.quickshell_pid():
            break
        time.sleep(1)
    log(f"shell restarted, settling {SETTLE} s")
    time.sleep(SETTLE)


def run_full(desktop, log):
    backup = open(SHELL_JSON, "rb").read()
    result = {}
    try:
        log("full: disabling omadock")
        _run(["omarchy", "plugin", "disable", "omadock"], timeout=30)
        restart_shell(desktop, log)
        result["error"] = full_state_error(desktop, False)
        result["disabled"] = measure(desktop, 30)
    finally:
        log("full: enabling omadock")
        _run(["omarchy", "plugin", "enable", "omadock"], timeout=30)
        with open(SHELL_JSON, "wb") as f:
            f.write(backup)
        restart_shell(desktop, log)
    result["error"] = result["error"] or full_state_error(desktop, True)
    result["enabled"] = measure(desktop, 30)
    result["dock_cost"] = None if result["error"] else dock_cost(result["disabled"], result["enabled"])
    if result["error"]:
        log(f"full: invalid, {result['error']}")
    return result


def print_summary(report):
    print(f'\n## Benchmark {report["started"]} ({report["conditions"]["dock_commit"]}'
          f'{" dirty" if report["conditions"]["dock_dirty"] else ""})\n')
    print("| scenario | cpu % | hypr cpu % | rss MB | vram MiB | fds | ctxsw/s |")
    print("|---|---|---|---|---|---|---|")
    for name, sc in report["scenarios"].items():
        if sc["skipped"]:
            print(f"| {name} | skipped: {sc['skipped']} | | | | | |")
            continue
        s = sc["summary"]
        cell = lambda k: "–" if s[k]["median"] is None else f'{s[k]["median"]:g}'
        print(f"| {name} | {cell('cpu_pct')} | {cell('hypr_cpu_pct')} | {cell('rss_mb')} | "
              f"{cell('vram_mib')} | {cell('fds')} | {cell('ctxsw_per_s')} |")
    if report.get("full"):
        c = report["full"]["dock_cost"]
        if c is None:
            print(f'\nDock cost: invalid ({report["full"]["error"]})')
            return
        print(f'\nDock cost (enabled - disabled): vram {c["vram_mib"]} MiB, '
              f'rss {c["rss_mb"]} MB, cpu {c["cpu_pct"]} %')


def cmd_run(args):
    log = lambda m: print(f"[bench] {m}", file=sys.stderr, flush=True)
    desktop = Desktop()
    if not desktop.quickshell_pid() or desktop.layer() is None:
        log("quickshell or the omadock layer is missing; run tests/smoke-test.sh")
        return 1
    if args.full and not args.yes:
        answer = input("--full restarts the shell 2x (bar and dock vanish briefly). Continue? [y/N] ")
        if answer.strip().lower() != "y":
            return 1
    cursor = desktop.cursor()
    report = {"schema": 1, "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
              "args": vars(args) | {"func": None}, "full": None}
    try:
        report["load_before"] = wait_quiet(log)
        prepare_items(desktop)
        report["conditions"] = conditions(desktop)
        report["scenarios"] = run_scenarios(desktop, args.repeat, args.events, log)
        if args.full:
            report["full"] = run_full(desktop, log)
    finally:
        desktop.ipc("closeSettings")
        desktop.move(*cursor)
    os.makedirs(args.out, exist_ok=True)
    path = result_path(args.out, report["conditions"]["host"], time.localtime())
    with open(path, "w") as f:
        json.dump(report, f, indent=1)
    print_summary(report)
    shown = os.path.relpath(path, REPO) if path.startswith(REPO + os.sep) else path
    print(f"\nSaved {shown}", flush=True)
    smoke = subprocess.run(["bash", os.path.join(REPO, "tests/smoke-test.sh")])
    return smoke.returncode


COMPARED_CONDITIONS = ["cpu", "gpu", "packages", "config_sha256", "monitors"]


def compare_reports(a, b):
    warnings = [f"conditions differ: {k}"
                for k in COMPARED_CONDITIONS
                if a["conditions"].get(k) != b["conditions"].get(k)]
    rows = []
    for name, sa in a["scenarios"].items():
        sb = b["scenarios"].get(name)
        if not sb or sa["skipped"] or sb["skipped"]:
            continue
        for k in NUMERIC:
            ma, mb = sa["summary"].get(k, {}), sb["summary"].get(k, {})
            va, vb = ma.get("median"), mb.get("median")
            if va is None or vb is None:
                continue
            diff = vb - va
            spread = max(ma["max"] - ma["min"], mb["max"] - mb["min"])
            rows.append({"scenario": name, "metric": k, "a": va, "b": vb,
                         "diff": round(diff, 3),
                         "pct": round(100 * diff / va, 1) if va else None,
                         "noise": abs(diff) <= spread})
    return rows, warnings


def cmd_compare(args):
    a, b = (json.load(open(p)) for p in (args.a, args.b))
    rows, warnings = compare_reports(a, b)
    for w in warnings:
        print(f"warning: {w}")
    print(f'\n## {a["conditions"]["dock_commit"]} → {b["conditions"]["dock_commit"]}\n')
    print("| scenario | metric | A | B | Δ | Δ % | |")
    print("|---|---|---|---|---|---|---|")
    for r in rows:
        pct = "–" if r["pct"] is None else f'{r["pct"]:+g} %'
        print(f'| {r["scenario"]} | {r["metric"]} | {r["a"]:g} | {r["b"]:g} | '
              f'{r["diff"]:+g} | {pct} | {"noise" if r["noise"] else ""} |')
    return 0


# --- soak ---------------------------------------------------------------------

def slope_per_hour(xs, ys):
    """Least-squares slope of ys over xs (seconds), per hour; None if undefined."""
    pts = [(x, y) for x, y in zip(xs, ys) if x is not None and y is not None]
    if len(pts) < 2:
        return None
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    den = sum((p[0] - mx) ** 2 for p in pts)
    if den == 0:
        return None
    return sum((p[0] - mx) * (p[1] - my) for p in pts) / den * 3600


SOAK_METRICS = ["rss_mb", "pss_mb", "vram_mib", "fds", "threads", "hypr_vram_mib"]


def soak_summary(samples):
    """Trend per metric for each run of samples with the same shell pid
    (a shell restart starts a new segment)."""
    segments, current = [], []
    for s in samples:
        if current and s.get("pid") != current[-1].get("pid"):
            segments.append(current)
            current = []
        current.append(s)
    if current:
        segments.append(current)
    out = []
    for seg in segments:
        xs = [s["t"] for s in seg]
        row = {"pid": seg[0].get("pid"), "samples": len(seg),
               "hours": round((xs[-1] - xs[0]) / 3600, 2)}
        for k in SOAK_METRICS:
            ys = [s.get(k) for s in seg]
            known = [y for y in ys if y is not None]
            row[k + "_start"] = known[0] if known else None
            row[k + "_end"] = known[-1] if known else None
            slope = slope_per_hour(xs, ys)
            row[k + "_per_h"] = round(slope, 3) if slope is not None else None
        out.append(row)
    return {"segments": out}


def cmd_soak(args):
    log = lambda m: print(f"[soak] {m}", file=sys.stderr, flush=True)
    desktop = Desktop()
    os.makedirs(args.out, exist_ok=True)
    host = socket.gethostname()
    path = os.path.join(args.out, time.strftime("soak-%Y-%m-%d-%H%M", time.localtime())
                        + f"-{host}-{args.label}.json")
    report = {"schema": 1, "kind": "soak", "label": args.label,
              "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
              "interval_s": args.interval, "conditions": conditions(desktop), "samples": []}
    t0 = time.monotonic()
    end = t0 + args.minutes * 60
    log(f"sampling every {args.interval} s for {args.minutes} min into {path}")
    try:
        while time.monotonic() < end:
            pid = desktop.quickshell_pid()
            hyp = desktop.hyprland_pid()
            sample = {"t": round(time.monotonic() - t0, 1), "wall": time.strftime("%H:%M:%S"), "pid": pid}
            proc = read_proc_sample(pid) if pid else None
            if proc:
                vram = read_vram()
                sample.update({"rss_mb": round(proc["rss_kb"] / 1024, 1), "pss_mb": round(proc["pss_kb"] / 1024, 1),
                               "threads": proc["threads"], "fds": proc["fds"],
                               "vram_mib": vram.get(pid), "hypr_vram_mib": vram.get(hyp) if hyp else None,
                               "ticks": read_proc_ticks(pid), "hypr_ticks": read_proc_ticks(hyp) if hyp else None})
            report["samples"].append(sample)
            report["summary"] = soak_summary([s for s in report["samples"] if "rss_mb" in s])
            with open(path, "w") as f:      # rewritten each time: an interrupted soak keeps its data
                json.dump(report, f, indent=1)
            time.sleep(max(0, min(args.interval, end - time.monotonic())))
    except KeyboardInterrupt:
        log("interrupted; samples so far are saved")
    for seg in report.get("summary", {}).get("segments", []):
        print(f"segment pid {seg['pid']}: {seg['hours']} h, {seg['samples']} samples; "
              f"rss {seg['rss_mb_start']} -> {seg['rss_mb_end']} MB ({seg['rss_mb_per_h']} MB/h), "
              f"vram {seg['vram_mib_start']} -> {seg['vram_mib_end']} MiB ({seg['vram_mib_per_h']} MiB/h), "
              f"fds {seg['fds_start']} -> {seg['fds_end']}")
    print(f"Saved {path}")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="bench.py", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="measure the live dock")
    r.add_argument("--full", action="store_true", help="also measure plugin disabled vs enabled (restarts the shell)")
    r.add_argument("--events", action="store_true", help="also switch workspaces (S5)")
    r.add_argument("--repeat", type=int, default=3)
    r.add_argument("--yes", action="store_true", help="do not ask before restarting the shell")
    r.add_argument("--out", default=DEFAULT_OUT)
    r.set_defaults(func=cmd_run)
    c = sub.add_parser("compare", help="compare two result files")
    c.add_argument("a")
    c.add_argument("b")
    c.set_defaults(func=cmd_compare)
    k = sub.add_parser("soak", help="sample the shell over a long time without touching the desktop")
    k.add_argument("--minutes", type=float, default=120)
    k.add_argument("--interval", type=float, default=60)
    k.add_argument("--label", default="on", help="e.g. on / off: whether the plugin is enabled")
    k.add_argument("--out", default=DEFAULT_OUT)
    k.set_defaults(func=cmd_soak)
    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
