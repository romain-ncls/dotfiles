#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""The world's cost, measured as the lock screen runs it (tools/bench.qml), on a headless
Weston with the GL renderer: the real GPU, but nothing shown on the desk.

    tools/bench.py [--at [YYYY-MM-DDT]HH:MM | --offset S] [--seconds N] [--only SCREEN] [--near-hz HZ]
                   [--greeter] [--fader] [--busy-anim] [--idle S] [--hide-at S] [--show-at S]
                   [--pause-at S] [--resume-at S] [--jump-at S --jump S] [--trace-ticks SCREEN]
                   [--trace-frames SCREEN[,SCREEN...]] [--no-system-plugins] [--profile] [--baseline]
                   [--log FILE]

Prints a JSON summary: when each screen first drew, revealed its world (a scene that waits for
its images: how many it still waited for, how far apart the screens were, the sheets it drew
without) and had all its images in (ms after launch), and how many times its images changed
state on the way (each change shows something popping in, at most one counted per 50 ms); then
over the run, which starts once every screen is in: the scene's clock and the screens Hornet is
on at its start, CPU time of the process (% of one core), frames drawn and scene ticks per
second per window, the process's GPU time (ms per second, from its DRM clients' render engine
time), GPU and peak memory, and every second's CPU and frames; last, the first ten different
warnings Qt and the QML printed. --hide-at, --show-at, --pause-at, --resume-at and --jump-at
(seconds into the run) also split the run into phases; after a pause, when each screen first drew
the moment it resumed at (held, ms after the resume), the frames it drew before of the moment it
paused at (stale), how far behind the clock it then was (behind), and over the next second the
frames it drew without a sheet (lacking) and the sheets they lacked (missing). gpu_busy_pct, the
GPU's busy share from the render engine's RC6 residency, is noisy: the desktop's own drawing is in
it too (--baseline first measures it without the bench).

As kscreenlocker_greet runs it: the QML disk cache off, the system's Qt plugins on the path
(kimageformats, for QOI images; --no-system-plugins leaves them out). --near-hz sets the scenes'
AmbientNearHz (30 otherwise, as by default). --greeter makes each scene only after holding the
GUI thread a moment, as the greeter makes the lock screen first; --fader draws each screen through
the lock screen's WallpaperFader; --busy-anim keeps an animation running in the process, as a
panel animating does in plasmashell. --idle lets Weston go idle (outputs off, no more frame
callbacks) after S seconds without input. --trace-ticks logs every tick and frame of one screen
and sums up the time between ticks. --trace-frames gives, for each of those screens, its ticks a
second and a table of what on it changes by frames (the 15 fps grass, the Bell Beast, the floor
bells, Hornet, the small life) and the particles: how often each changed (per_s) against how
often it should have (due_per_s), the frames it skipped, those it held half a frame or more too
long (doubled), the ticks that drew it otherwise than the exact time says (stale), and how late
after its time each change was drawn (late_ms). --profile logs the render loop's timings and GPU
timestamps for each frame (render-thread and GPU time per frame). That logging costs CPU, as the
traces do: leave them out for CPU and frame rate figures. One bench at a time (a lock file),
under a memory cap.
"""
import argparse
import datetime
import fcntl
import json
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
SOCKET = "silksong-bench"
RC6 = Path("/sys/class/drm/card1/gt/gt0/rc6_residency_ms")
SYSTEM_QT = Path("/run/current-system/sw/lib/qt-6")

LINE = re.compile(r"^qml: ([A-Z_]+) (.*)$")
RENDERLOOP = re.compile(r"^qt\.scenegraph\.time\.renderloop: \[window (0x[0-9a-f]+)\]\[(?:render thread [^\]]*|gui thread)\] (.*)$")
MARKS = ("RUN_START", "SECOND", "HIDE", "SHOW", "PAUSE", "RESUME", "JUMP", "RUN_END")
TOKENS = ("WINDOW", "FIRST_FRAME", "FRAME", "TICK", "REVEAL", "RESUMED", "LOAD", "READY", "TIMEOUT", "TICKS",
          "FRAME_TRACE") + MARKS
# What the bench's surroundings print on every run, not the scene: no Adwaita icon theme, and
# with --fader the Plasma theme's old metadata, KWindowSystem finding no platform outside Plasma
# and Kirigami registering its types by relative URL. Any other line that is not the bench's own
# is a warning.
NOISE = re.compile(r"^(kf\.iconthemes: Icon theme \".*\" not found\."
                   r"|kf\.(svg|plasma\.core): The theme \".*\" uses the legacy metadata\.desktop\..*"
                   r"|kf\.windowsystem: Could not find any platform plugin"
                   r"|qmlRegisterType requires absolute URLs\.)$")


def nix_path(attr):
    out = subprocess.run(["nix", "build", "--no-link", "--print-out-paths", attr],
                         check=True, capture_output=True, text=True).stdout.split()
    return Path(out[0])


def rc6():
    try:
        return int(RC6.read_text())
    except OSError:
        return None


def cpu_seconds(pid):
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")


def peak_rss_mb(pid):
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        if line.startswith("VmHWM:"):
            return int(line.split()[1]) / 1024
    return None


def drm_clients(pid):
    """The fdinfo of each of the process's DRM clients (a client can be open on several fds)."""
    seen = {}
    for fd in Path(f"/proc/{pid}/fdinfo").iterdir():
        try:
            info = fd.read_text()
        except OSError:
            continue
        if client := re.search(r"^drm-client-id:\s*(\d+)", info, re.M):
            seen.setdefault(client.group(1), info)
    return seen.values()


def gpu_memory_mb(pid):
    total, clients = 0, drm_clients(pid)
    for info in clients:
        for m in re.finditer(r"^drm-total-[\w-]+:\s*(\d+)\s*(KiB|MiB)?", info, re.M):
            total += int(m.group(1)) * {"KiB": 1024, "MiB": 1024 * 1024}.get(m.group(2), 1) / (1024 * 1024)
    return round(total, 1) if clients else None


def gpu_render_ns(pid):
    """GPU time the process's clients have spent on the render engine, in ns."""
    total = None
    for info in drm_clients(pid):
        if m := re.search(r"^drm-engine-render:\s*(\d+)", info, re.M):
            total = (total or 0) + int(m.group(1))
    return total


def busy(start, end, wall):
    if start is None or end is None or wall <= 0:
        return None
    return round(100 * (1 - (end - start) / (wall * 1000)), 1)


def span(a, b):
    """CPU, GPU and frame rates between two samples of the run."""
    wall = b["wall"] - a["wall"]
    out = {"seconds": round(wall, 2), "cpu_pct": round(100 * (b["cpu"] - a["cpu"]) / wall, 1)}
    if a["gpu"] is not None and b["gpu"] is not None:
        out["gpu_client_ms_s"] = round((b["gpu"] - a["gpu"]) / 1e6 / wall, 1)
    out["fps"] = {k: round((v - a["frames"].get(k, 0)) / wall, 1) for k, v in b["frames"].items()}
    return out


def spread(values, digits=2):
    values = sorted(values)
    return {"mean": round(statistics.mean(values), digits), "median": round(statistics.median(values), digits),
            "p5": round(values[int(len(values) * 0.05)], digits), "p95": round(values[int(len(values) * 0.95)], digits),
            "max": round(values[-1], digits), "n": len(values)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--at", help="moment to run at, HH:MM today or YYYY-MM-DDTHH:MM (her day is the date's)")
    ap.add_argument("--offset", type=float, default=0.0, help="seconds added to the wall clock")
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--only", help="only this screen's window")
    ap.add_argument("--near-hz", type=int, help="the scenes' AmbientNearHz")
    ap.add_argument("--greeter", action="store_true", help="make each scene after the lock screen, as the greeter does")
    ap.add_argument("--fader", action="store_true", help="draw through the lock screen's WallpaperFader")
    ap.add_argument("--busy-anim", action="store_true", help="keep an animation running in the process")
    ap.add_argument("--idle", type=int, default=0, help="seconds without input before Weston goes idle")
    ap.add_argument("--hide-at", type=float, help="hide every scene, seconds into the run")
    ap.add_argument("--show-at", type=float, help="show them again")
    ap.add_argument("--pause-at", type=float, help="pause every scene, seconds into the run")
    ap.add_argument("--resume-at", type=float, help="resume them")
    ap.add_argument("--jump-at", type=float, help="move the wall clock, seconds into the run")
    ap.add_argument("--jump", type=float, help="by this many seconds")
    ap.add_argument("--trace-ticks", metavar="SCREEN", help="log every tick and frame of this screen")
    ap.add_argument("--trace-frames", metavar="SCREENS", help="what these screens show at each tick (comma-separated)")
    ap.add_argument("--no-system-plugins", action="store_true", help="only Qt's own image formats")
    ap.add_argument("--profile", action="store_true", help="log render-thread and GPU time per frame")
    ap.add_argument("--baseline", action="store_true", help="first measure the GPU without the bench")
    ap.add_argument("--log", help="keep the raw log here")
    a = ap.parse_args()

    lock = open(RUNTIME / "silksong-bench.flock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)

    weston = nix_path("nixpkgs#weston")
    qml = nix_path("nixpkgs#qt6.qtdeclarative") / "bin/qml"
    wayland = nix_path("nixpkgs#qt6.qtwayland") / "lib/qt-6/plugins"

    compositor = subprocess.Popen(
        [weston / "bin/weston", "--backend=headless", "--renderer=gl", "--width=5760", "--height=1200",
         f"--socket={SOCKET}", f"--idle-time={a.idle}", "--no-config"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            if (RUNTIME / SOCKET).exists():
                break
            time.sleep(0.05)
        time.sleep(0.5)

        baseline = None
        if a.baseline:
            r0, w0 = rc6(), time.monotonic()
            time.sleep(a.seconds)
            baseline = busy(r0, rc6(), time.monotonic() - w0)

        # The moment to show, worked out only now, so that a run which waited for the lock (or
        # for the baseline) still starts at --at.
        offset = a.offset
        if a.at:
            now = datetime.datetime.now()
            if "T" in a.at:
                at = datetime.datetime.fromisoformat(a.at)
            else:
                h, m = map(int, a.at.split(":"))
                at = now.replace(hour=h, minute=m, second=0, microsecond=0)
            offset = (at - now).total_seconds()

        plugins = [wayland] if a.no_system_plugins else [wayland, SYSTEM_QT / "plugins"]
        env = dict(os.environ, QT_QPA_PLATFORM="wayland", WAYLAND_DISPLAY=SOCKET,
                   QT_PLUGIN_PATH=":".join(map(str, plugins)), QML_DISABLE_DISK_CACHE="1",
                   QT_FORCE_STDERR_LOGGING="1", QT_MESSAGE_PATTERN="%{if-category}%{category}: %{endif}%{message}")
        if a.no_system_plugins:
            # nixpkgs' Qt also looks for plugins beside each directory on PATH.
            env["PATH"] = str(qml.parent)
        if a.fader:
            env["QML_IMPORT_PATH"] = str(SYSTEM_QT / "qml")
        if a.profile:
            env.update(QSG_RHI_PROFILE="1", QT_LOGGING_RULES="qt.scenegraph.time.renderloop=true")
        options = {"--only": a.only, "--near-hz": a.near_hz, "--hide-at": a.hide_at, "--show-at": a.show_at,
                   "--pause-at": a.pause_at, "--resume-at": a.resume_at, "--jump-at": a.jump_at, "--jump": a.jump,
                   "--trace-ticks": a.trace_ticks, "--trace-frames": a.trace_frames}
        t0 = int(time.time() * 1000)
        cmd = [str(qml), str(HERE / "bench.qml"), "--", "--t0", str(t0), "--offset", str(offset), "--seconds", str(a.seconds)]
        cmd += [str(x) for k, v in options.items() if v is not None for x in (k, v)]
        cmd += [f for f, on in (("--greeter", a.greeter), ("--fader", a.fader), ("--busy-anim", a.busy_anim)) if on]
        proc = subprocess.Popen(cmd, env=env, stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, text=True)

        result = {"offset": round(offset), "seconds": a.seconds}
        if baseline is not None:
            result["gpu_busy_baseline_pct"] = baseline
        loads, ready, first, reveal, revealed, resumed, windows, memory = {}, {}, {}, {}, {}, {}, {}, {}
        samples, ticks, frames_traced = [], [], []
        renders, polish, gpu_frames = [], [], {}
        log = []
        ended = False
        for line in proc.stderr:
            log.append(line)
            # Only what comes between RUN_START and RUN_END is the run's: the windows go on drawing,
            # and the render loop on logging, until the process is gone.
            in_run = bool(samples) and not ended
            if m := LINE.match(line):
                what, rest = m.groups()
                fields = rest.split(" ", 2)
                if what == "LOAD":
                    done, total = map(int, fields[2].split("/"))
                    loads.setdefault(fields[0], []).append((int(fields[1]), done, total))
                elif what in ("READY", "TIMEOUT"):
                    ready[fields[0]] = int(fields[1]) if what == "READY" else None
                elif what == "FIRST_FRAME":
                    first[fields[0]] = int(fields[1])
                elif what == "REVEAL":
                    reveal[fields[0]] = int(fields[1])
                    revealed[fields[0]] = json.loads(fields[2])
                elif what == "RESUMED":
                    resumed[fields[0]] = json.loads(fields[2])
                elif what == "WINDOW" and (w := re.search(r"\((0x[0-9a-f]+)\)", rest)):
                    windows[w.group(1)] = fields[0]
                elif what in MARKS and not ended:
                    ms, data = rest.split(" ", 1)
                    sample = {"mark": what, "ms": int(ms), "wall": time.monotonic(), "cpu": cpu_seconds(proc.pid),
                              "gpu": gpu_render_ns(proc.pid), "rc6": rc6(), "frames": {}}
                    if what == "RUN_START":
                        result.update(("run_" + k, v) for k, v in json.loads(data).items())
                    else:
                        sample["frames"] = json.loads(data)
                    if what == "RUN_END":
                        ended = True
                        memory = {"peak_rss_mb": round(peak_rss_mb(proc.pid), 1), "gpu_memory_mb": gpu_memory_mb(proc.pid)}
                    samples.append(sample)
                elif what == "TICKS":
                    result["ticks"] = json.loads(rest)
                elif what == "FRAME_TRACE":
                    result.setdefault("frame_trace", {})[fields[0]] = json.loads(rest.split(" ", 1)[1])
                elif what == "TICK" and in_run:
                    ticks.append(float(fields[2]))
                elif what == "FRAME" and in_run:
                    frames_traced.append(int(fields[1]))
            elif in_run and (m := RENDERLOOP.match(line)):
                window, message = m.groups()
                if r := re.match(r"syncAndRender: frame rendered in (\d+)ms, sync=(\d+), render=(\d+), swap=(\d+)", message):
                    renders.append(tuple(map(int, r.groups())))
                elif r := re.match(r"Frame prepared, polish=(\d+) ms", message):
                    polish.append(int(r.group(1)))
                elif r := re.match(r"syncAndRender: last retrieved GPU frame time was ([\d.]+) ms", message):
                    gpu_frames.setdefault(windows.get(window, window), []).append(float(r.group(1)))
        proc.wait(timeout=30)
        if a.log:
            Path(a.log).write_text("".join(log))

        result["first_frame_ms"] = first
        if reveal:
            result["reveal_ms"] = reveal
            result["reveal_spread_ms"] = max(reveal.values()) - min(reveal.values())
            result["reveal_pending"] = {k: v["pending"] for k, v in revealed.items()}
            result["reveal_missing"] = {k: v["missing"] for k, v in revealed.items() if v["missing"]}
        result["ready_ms"] = ready
        if resumed:
            result["resumed"] = resumed
        result["load_steps"] = {s: len(v) for s, v in loads.items()}
        result["images"] = {s: v[-1][2] for s, v in loads.items()}
        start = next((s for s in samples if s["mark"] == "RUN_START"), None)
        end = next((s for s in samples if s["mark"] == "RUN_END"), None)
        if start and end:
            whole = span(start, end)
            result["cpu_pct"] = whole["cpu_pct"]
            result["gpu_client_ms_s"] = whole.get("gpu_client_ms_s")
            result["gpu_busy_pct"] = busy(start["rc6"], end["rc6"], whole["seconds"])
            result["fps"] = whole["fps"]
            if "ticks" in result:
                result["ticks_per_s"] = {k: round(v / whole["seconds"], 1) for k, v in result.pop("ticks").items()}
            result.update(memory)
            # The last second ends with the run, at the same moment.
            seconds = [s for s in samples if s["mark"] in ("RUN_START", "SECOND", "RUN_END")]
            pairs = [(p, q) for p, q in zip(seconds, seconds[1:]) if q["wall"] - p["wall"] > 0.2]
            result["timeline"] = [{"t": t, **span(p, q)} for t, (p, q) in enumerate(pairs, 1)]
            events = [s for s in samples if s["mark"] != "SECOND"]
            if len(events) > 2:
                result["phases"] = [{"from": p["mark"], "to": q["mark"], **span(p, q)} for p, q in zip(events, events[1:])]
        if ticks:
            gaps = [1000 * (q - p) for p, q in zip(ticks, ticks[1:]) if 0 <= q - p < 1]
            result["tick_trace"] = {"screen": a.trace_ticks, "ticks": len(ticks), "frames": len(frames_traced)}
            if gaps:
                result["tick_trace"]["interval_ms"] = spread(gaps)
        if "frame_trace" in result:
            result["frame_trace"] = result.pop("frame_trace")  # after the rest
        if renders:
            total = sorted(r[0] for r in renders)
            result["render_thread_ms"] = {"mean": round(statistics.mean(total), 2), "p95": total[int(len(total) * 0.95)],
                                          "render_mean": round(statistics.mean(r[2] for r in renders), 2),
                                          "swap_mean": round(statistics.mean(r[3] for r in renders), 2), "frames": len(renders)}
        if polish:
            result["polish_ms_mean"] = round(statistics.mean(polish), 2)
        if gpu_frames:
            result["gpu_frame_ms"] = {k: spread(v, 3) for k, v in gpu_frames.items()}
        errors = [l.strip() for l in log if l.strip() and not NOISE.match(l) and not RENDERLOOP.match(l)
                  and not ((m := LINE.match(l)) and m.group(1) in TOKENS)]
        if errors:
            result["warnings"] = list(dict.fromkeys(errors))[:10]
        print("{\n" + ",\n".join(f" {json.dumps(k)}: {json.dumps(v)}" for k, v in result.items()) + "\n}")
    finally:
        compositor.terminate()
        compositor.wait(timeout=10)


if __name__ == "__main__":
    sys.exit(main())
