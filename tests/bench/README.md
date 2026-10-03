# OmaDock benchmark

Measures what the dock costs in CPU, RAM and VRAM on the live desktop, in
fixed scenarios, and compares runs. Python stdlib only; needs a running
Omarchy shell (not run in CI).

## Run

    python3 tests/bench/bench.py run                 # quick: S0-S4, S6, ~4 min
    python3 tests/bench/bench.py run --events        # + S5 workspace switching
    python3 tests/bench/bench.py run --full          # + dock on/off (restarts the shell 2x)
    python3 tests/bench/bench.py compare A.json B.json
    python3 tests/bench/bench.py soak --minutes 120 --interval 60 --label on

Results land in `~/.local/state/omadock-bench/` (`--out` to change it; keep
it outside the plugin directory, where every write reloads the dock).

## What it does to your desktop

- Moves the pointer (never clicks or types) and puts it back.
- Opens and closes the settings panel through IPC.
- `--events` switches to an empty workspace and back 20 times per run.
- `--full` disables the plugin, restarts the shell, measures, re-enables
  it, restores `shell.json` and restarts again. Ctrl-C is safe: the plugin
  is always re-enabled.
- Do not use the computer while it runs; input changes the numbers.

## Scenarios

| # | what | seconds |
|---|---|---|
| S0 | idle, pointer away from the dock | 30 |
| S1 | pointer sweeps across every item and back, resting past the tooltip delay | 30 |
| S2 | tooltip of an app with >= 2 windows (window previews) | 15 |
| S3 | settings panel open | 15 |
| S4 | idle after S1-S3; compare with S0 for leaks | 30 |
| S5 | `--events`: 20 workspace switches | ~12 |
| S6 | an urgent window exists (skipped if none) | 15 |

Each runs `--repeat` times (default 3); the report keeps every run plus
median/min/max.

## Metrics

All for the `quickshell` process, which also hosts the Omarchy bar,
background and notifications. Only `--full` isolates the dock itself.

- `cpu_pct`: CPU of the whole process over the window, 100 = one core,
  including threads that exited meanwhile. `cpu_threads` splits it by
  thread name (live threads only); `quickshell` (main thread) does QML and
  rendering.
- `hypr_cpu_pct`: Hyprland's CPU in the same window. It pays for
  compositing and blurring the dock surface.
- `rss_mb`, `pss_mb`: resident / proportional memory (median of samples);
  `rss_mb_end` is the last sample.
- `vram_mib`, `hypr_vram_mib`: from `nvidia-smi -q -x` (NVIDIA only).
- `fds`, `threads`: should not grow between S0 and S4.
- `ctxsw_per_s`: context switches per second summed over all threads, a
  wake-up proxy; at idle it should be low and flat.

## Conditions recorded with each run

CPU, cores, RAM, GPU and driver, kernel, `omarchy`/`quickshell`/
`hyprland`/`qt6-base` versions, dock commit and dirty flag, sha256 of
`omadock.json`, item count by kind, window count, monitors, dock layer
geometry, quickshell uptime, load average. `compare` warns when the
hardware, versions, config or monitors differ.

## Caveats

- Numbers from different machines or configs are not comparable.
- Freshly restarted shells use less RAM than ones that ran for hours;
  check `quickshell_uptime_s` before comparing RSS.
- VRAM is reported by the driver and is freed lazily; compare medians.
- `hypr_cpu_pct` includes Hyprland serving the script's own `hyprctl`
  calls (a few per second in S1).
- The pointer is parked in the middle of the screen between runs; with
  focus-follows-mouse this can move keyboard focus to the window there.
- `--full` checks that the dock layer really disappears and comes back;
  otherwise the dock cost is reported as invalid.

## Soak

`soak` only watches: it never moves the pointer or touches the shell, so
keep working normally. Every interval it records the shell's RSS, PSS,
VRAM, threads and fds (and Hyprland's VRAM and CPU ticks) and rewrites
`soak-<date>-<host>-<label>.json` in the output directory, so an interrupted run
keeps its data. A shell restart (new pid) starts a new segment; each
segment gets a least-squares trend per metric (MB per hour). Run it once
with the plugin enabled (`--label on`) and once disabled (`--label off`,
after `omarchy plugin disable omadock`) to see whether a slow growth
comes from the dock or from the shell itself.

## Unit tests

    python3 -m unittest tests/unit/test_bench.py -v
