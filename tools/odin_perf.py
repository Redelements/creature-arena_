"""Measure frame pacing on an Android device (the AYN Odin 3) over adb.

    python tools/odin_perf.py --label ctf4v4-gl
    python tools/odin_perf.py --label ctf4v4-vk --renderer mobile
    python tools/odin_perf.py --label duel-gl --mode 6 --frames 7200
    python tools/odin_perf.py --label mine --play                   (you play; press Home to end)
    python tools/odin_perf.py --vram                                (texture memory, Lighting High and Low)
    python tools/odin_perf.py --soak --minutes=10                   (heat soak: 10 minutes of 4v4 CTF at 120)

Each run bakes the game's flags into the Android preset (`command_line/extra_args`),
exports a release APK (debug templates run GDScript slower), installs it, plays the fight
to `--quit-after`, and reads the `--perf` report from logcat (a release APK isn't
debuggable, so `run-as` can't read user://perf.txt). The report goes to
build/perf/<label>.txt. export_presets.cfg and project.godot are put back afterwards,
whatever happens. `--renderer gl` builds with gl_compatibility instead of Vulkan (Mobile).
`--play` builds a normal game with only --perf: play it on the device, then press Home; the
report is written when the app goes to the background, and SCREEN keeps only the fights
(menus run at 60). The first run after an install also compiles Vulkan shaders: one hitch
of ~40 ms that a second run doesn't have (the game's shader warm-up, ShaderWarmup, now does
that on the title instead; `--extra=--no-warmup` for the A/B). Judge by the SCREEN lines
(SurfaceFlinger's presents), not the CPU-side PERF frame times.

`--vram` builds one APK per Lighting tier (High, Low), each a CPU-vs-CPU 4v4 CTF that prints
`VRAM ...` at frame 600 (`--print-vram`, CreatureView.sheet_report) and quits, and prints the
two lines as a table (build/perf/vram.txt).

`--soak --minutes=10` builds a CPU-vs-CPU 4v4 CTF at a 120 cap that rematches by itself
(`--rematch-after`, so it fights the whole time instead of sitting on the results screen),
runs it for the minutes given while reading SurfaceFlinger as --play does and the device's
thermal state every 30 s (`dumpsys thermalservice`, else /sys/class/thermal; read only),
then sends it to the background (Home), which writes the report. It prints the SCREEN lines
(fights only: 1% and 0.1% lows, long gaps) and the temperatures over time (build/perf/soak.txt).

Needs: Godot at GODOT (or the default path below), adb at ADB, a device plugged in with USB
debugging allowed (each mode but --export-only stops with a message when `adb get-state`
finds none), and the device's own refresh setting at 120 (Settings > Display, or `adb shell
settings put system peak_refresh_rate 120` and `min_refresh_rate 120`): nothing in the game
can override it. Tests for the parsing and reports: `python -I -m unittest discover -s tools
-p "test_*.py"` (no device needed).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", r"C:/Users/Kevin/dev/godot/Godot_v4.7.2-stable_win64_console.exe")
ADB = os.environ.get("ADB", r"C:/Users/Kevin/dev/android-sdk/platform-tools/adb.exe")
PACKAGE = "io.github.redelements.creaturearena"
APK = os.path.join(ROOT, "build", "android", "perf.apk")
KEYSTORE = os.path.join(os.environ.get("APPDATA", ""), "Godot", "keystores", "debug.keystore")
VRAM_FRAME = 600  # --vram: 10 s into the fight at the mobile default of 60 fps
THERMAL_EVERY = 30.0  # --soak: seconds between thermal readings
REMATCH_AFTER = 180  # --soak: frames on the results screen before the next fight


def adb(*args, check=True):
    return subprocess.run([ADB, *args], capture_output=True, text=True, check=check).stdout


def need_device():
    """Stops with a clear message unless adb sees a device."""
    try:
        state = adb("get-state", check=False).strip()
    except FileNotFoundError:
        sys.exit(f"adb not found at {ADB} (set ADB): install the Android platform-tools")
    if state != "device":
        sys.exit("no device: plug the Odin in and allow USB debugging (adb get-state: %s)" % (state or "nothing"))


def game_layer():
    """The game's SurfaceView layer in SurfaceFlinger, or "" before it exists."""
    for line in adb("shell", "dumpsys", "SurfaceFlinger", "--list", check=False).splitlines():
        m = re.search(r"(SurfaceView\[%s/[^\]]*\]\(BLAST\)#\d+)" % re.escape(PACKAGE), line)
        if m:
            return m.group(1)
    return ""


def presents(layer, seen):
    """Adds the layer's latest present times (ns; SurfaceFlinger keeps about 128) to `seen`.
    Returns the refresh period in ns."""
    return parse_latency(adb("shell", f"dumpsys SurfaceFlinger --latency '{layer}'", check=False), seen)


def parse_latency(text, seen):
    """`dumpsys SurfaceFlinger --latency` output: the period, then rows of three times (ns):
    the app's desired present, the actual present, and the frame ready."""
    out = text.split()
    if not out:
        return 0
    for i in range(1, len(out) - 2, 3):
        t = int(out[i + 1])
        if 0 < t < 2**62:
            seen[t] = (t - int(out[i])) / 1e6  # queued -> shown, ms
    return int(out[0])


def screen_report(times, period, skip_s=3.0, fights_only=False):
    """What the screen showed: present-to-present intervals (the first `skip_s` seconds of
    the fight left out: loading, first draws)."""
    lag = sorted(times[x] for x in times)
    t = sorted(times)
    if len(t) < 200 or period <= 0:
        return ["SCREEN not enough presents (%d)" % len(t)]
    t0 = t[0]
    t = [x for x in t if x - t[0] > skip_s * 1e9][:-1]  # the last frame waits on the quit (the report)
    iv = [(b - a) / 1e6 for a, b in zip(t, t[1:])]
    per = period / 1e6
    if fights_only:
        # Menus run at 60 fps (two refreshes a frame): keep only frames inside a stretch of
        # 120 where most frames took one refresh, i.e. the fights.
        one = [1 if v < per * 1.5 else 0 for v in iv]
        keep = []
        for i in range(len(iv)):
            lo, hi = max(0, i - 60), min(len(iv), i + 60)
            if sum(one[lo:hi]) >= 0.75 * (hi - lo):
                keep.append(i)
        iv = [iv[i] for i in keep]
        if len(iv) < 200:
            return ["SCREEN no fight found in the presents (%d frames)" % len(iv)]
    skipped = sum(max(0, round(v / per) - 1) for v in iv)
    late = sum(1 for v in iv if v > per * 1.5)
    total = sum(iv)
    slow = sorted(iv, reverse=True)
    low = lambda share: max(1, int(len(slow) * share)) * 1000.0 / sum(slow[:max(1, int(len(slow) * share))])
    worst, j, span = float("inf"), 0, 0.0
    for i, v in enumerate(iv):
        span += v
        while span - iv[j] >= 1000.0:
            span -= iv[j]
            j += 1
        if span >= 1000.0:
            worst = min(worst, (i - j + 1) * 1000.0 / span)
    gaps = {}
    for v in iv:
        k = round(v / per)
        gaps[k] = gaps.get(k, 0) + 1
    return [
        "SCREEN (SurfaceFlinger presents, refresh %.2f ms, %d frames over %.1f s)" % (per, len(iv), total / 1000.0),
        "SCREEN shown fps avg %.1f, 1%% low %.1f, 0.1%% low %.1f, slowest second %.1f" % (len(iv) * 1000.0 / total, low(0.01), low(0.001), worst),
        "SCREEN frames held past one refresh: %d (%.2f%%, %.2f a second), refreshes skipped %d" % (late, 100.0 * late / len(iv), late * 1000.0 / total, skipped),
        "SCREEN refreshes per frame: " + ", ".join("%d: %d" % (k, gaps[k]) for k in sorted(gaps)),
        "SCREEN queued to shown ms: p50 %.1f, p99 %.1f (the frame queue's lag)" % (lag[len(lag) // 2], lag[int(len(lag) * 0.99)]),
        "SCREEN long gaps (s from the first frame shown, ms): " + (", ".join("%.1fs %.0f" % ((b - t0) / 1e9, (b - a) / 1e6)
            for a, b in zip(t, t[1:]) if (b - a) / 1e6 > per * (2.5 if fights_only else 1.5)) or "none"),
        "SCREEN last frame at %.1fs" % ((t[-1] - t0) / 1e9),
    ]


def godot_lines(log, word):
    """The game's own lines in `adb logcat -s godot:I` output that contain `word`."""
    return [l.split("godot", 1)[-1].lstrip(" :") for l in log.splitlines() if word in l]


VRAM_RE = re.compile(r"VRAM frame (\d+), lighting (\w+): textures ([\d.]+) MB, video ([\d.]+) MB; (.*)")


def parse_vram(log):
    """The `VRAM frame N, lighting T: textures X MB, video Y MB; fighter sheets: ...` lines
    (main.gd `_capture`, CreatureView.sheet_report) as dicts."""
    rows = []
    for line in godot_lines(log, "VRAM frame"):
        m = VRAM_RE.search(line)
        if not m:
            continue
        sheets = {kind: (int(n), float(mb)) for n, kind, mb in re.findall(r"(\d+) (\w+) ([\d.]+) MB", m.group(5))}
        rows.append({"frame": int(m.group(1)), "lighting": m.group(2), "textures": float(m.group(3)),
            "video": float(m.group(4)), "sheets": sheets})
    return rows


def vram_table(rows):
    """A Markdown table of `parse_vram` rows (one per Lighting tier)."""
    if not rows:
        return ["VRAM no lines found (did the run reach frame %d? `adb logcat -d -s godot`)" % VRAM_FRAME]
    kinds = []
    for r in rows:
        for k in r["sheets"]:
            if k not in kinds:
                kinds.append(k)
    head = "| Lighting | Textures MB | Video MB | " + " | ".join("%s sheets (MB)" % k for k in kinds) + " |"
    out = [head, "|" + "---|" * (3 + len(kinds))]
    for r in rows:
        cells = ["%d (%.1f)" % r["sheets"][k] if k in r["sheets"] else "-" for k in kinds]
        out.append("| %s | %.1f | %.1f | %s |" % (r["lighting"], r["textures"], r["video"], " | ".join(cells)))
    return out


def parse_thermal(text):
    """The device's temperatures, read only: `dumpsys thermalservice` ({"status": N, "temps":
    {name: C}} from "Thermal Status" and the "Current temperatures from HAL" Temperature{...}
    entries), or the `type temp` lines of /sys/class/thermal (millidegrees)."""
    status = None
    m = re.search(r"Thermal Status:\s*(\d+)", text)
    if m:
        status = int(m.group(1))
    temps = {}
    hal = text.split("Current temperatures from HAL:", 1)
    if len(hal) == 2:
        for v, name in re.findall(r"Temperature\{mValue=([-\d.]+), mType=-?\d+, mName=([^,]+),", hal[1].split("\n\n")[0]):
            temps[name] = float(v)
    if not temps:
        for name, v in re.findall(r"^(\S+)\s+(-?\d+)\s*$", text, re.M):
            c = int(v) / 1000.0 if abs(int(v)) > 200 else float(v)
            if -40.0 < c < 150.0:
                temps[name] = max(c, temps.get(name, -999.0))
    return {"status": status, "temps": temps}


STATUS_NAMES = ["none", "light", "moderate", "severe", "critical", "emergency", "shutdown"]


def thermal_sample():
    text = adb("shell", "dumpsys", "thermalservice", check=False)
    got = parse_thermal(text)
    if not got["temps"]:
        zones = adb("shell", "for z in /sys/class/thermal/thermal_zone*; do echo $(cat $z/type) $(cat $z/temp); done", check=False)
        got["temps"] = parse_thermal(zones)["temps"]
    return got


def thermal_report(samples):
    """One line a reading: [(seconds since start, parse_thermal dict)]: the status, the hottest
    CPU-ish zone, the battery and the hottest of all."""
    if not samples:
        return ["THERMAL no readings"]
    out = []
    for t, s in samples:
        temps = s["temps"]
        cpu = [v for k, v in temps.items() if re.search(r"cpu|soc|tsens|big|little|prime", k, re.I)]
        bat = [v for k, v in temps.items() if re.search(r"batt", k, re.I)]
        hot = max(temps.items(), key=lambda kv: kv[1]) if temps else ("-", float("nan"))
        st = s["status"]
        out.append("THERMAL %2d:%02d status %s, CPU %s, battery %s, hottest %s %.1f C" % (int(t) // 60, int(t) % 60,
            "-" if st is None else "%d (%s)" % (st, STATUS_NAMES[st] if 0 <= st < len(STATUS_NAMES) else "?"),
            "%.1f C" % max(cpu) if cpu else "-", "%.1f C" % max(bat) if bat else "-", hot[0], hot[1]))
    return out


def vram_flags(tier):
    return f"-- --mode=53 --level=1 --seed=7 --cpu-vs-cpu --lighting={tier} --print-vram={VRAM_FRAME} --quit-after={VRAM_FRAME + 60}"


def soak_flags(fps):
    return f"-- --mode=53 --level=1 --seed=7 --cpu-vs-cpu --perf --fight-fps={fps} --rematch-after={REMATCH_AFTER}"


def run_flags(a):
    """The flags of a plain run (or --play)."""
    if a.play:
        return "-- --perf"
    return f"-- --mode={a.mode} --level={a.level} --seed={a.seed} --perf --fight-fps={a.fps} --quit-after={a.frames} {a.extra}".strip()


def swap(path, pattern, repl):
    text = open(path, encoding="utf-8").read()
    new, n = re.subn(pattern, repl, text, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"{path}: no line matching {pattern}")
    open(path, "w", encoding="utf-8", newline="\n").write(new)


def export_apk(flags, renderer):
    """Bakes `flags` into the Android preset, exports a release APK, puts the files back."""
    presets = os.path.join(ROOT, "export_presets.cfg")
    project = os.path.join(ROOT, "project.godot")
    backups = {p: p + ".perfbak" for p in (presets, project)}
    for p, b in backups.items():
        shutil.copyfile(p, b)
    try:
        swap(presets, r'^command_line/extra_args=".*"$', f'command_line/extra_args="{flags}"')
        method = "mobile" if renderer == "mobile" else "gl_compatibility"
        swap(project, r'^renderer/rendering_method\.mobile=".*"$', f'renderer/rendering_method.mobile="{method}"')
        os.makedirs(os.path.dirname(APK), exist_ok=True)
        env = dict(os.environ,
            GODOT_ANDROID_KEYSTORE_RELEASE_PATH=KEYSTORE,
            GODOT_ANDROID_KEYSTORE_RELEASE_USER="androiddebugkey",
            GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="android")
        r = subprocess.run([GODOT, "--headless", "--path", ROOT, "--export-release", "Android", APK],
            capture_output=True, text=True, env=env)
        if not os.path.exists(APK) or r.returncode != 0:
            sys.exit("export failed:\n" + r.stdout[-3000:] + r.stderr[-3000:])
    finally:
        for p, b in backups.items():
            shutil.move(b, p)


def install():
    installed = adb("install", "-r", APK, check=False)
    if "Success" not in installed:
        # a CI or debug APK signed with another key: replace it
        adb("uninstall", PACKAGE, check=False)
        if "Success" not in adb("install", APK, check=False):
            sys.exit("install failed")


def launch():
    adb("shell", "am", "force-stop", PACKAGE)
    adb("logcat", "-c")
    adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")


def write_report(label, lines):
    out = os.path.join(ROOT, "build", "perf", label + ".txt")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    return out


def parse_args(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", default="", help="the report's name (default: run, vram or soak)")
    ap.add_argument("--mode", type=int, default=53, help="53 = Capture the Flag 4v4, the worst case")
    ap.add_argument("--level", type=int, default=1, help="CPU level: 1 = Normal (no Rage runs)")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--fps", type=int, default=120)
    ap.add_argument("--frames", type=int, default=4800, help="--quit-after: 40 s at 120 fps")
    ap.add_argument("--renderer", choices=["gl", "mobile"], default="mobile", help="mobile = Vulkan, the default")
    ap.add_argument("--extra", default="", help="more game flags, e.g. --cpu-threads=off")
    ap.add_argument("--no-export", action="store_true", help="reuse the last APK")
    ap.add_argument("--export-only", action="store_true", help="build the APK, no device needed")
    which = ap.add_mutually_exclusive_group()
    which.add_argument("--play", action="store_true",
        help="a normal build (only --perf): you play; it records the screen until the app goes to the background (Home)")
    which.add_argument("--vram", action="store_true",
        help="texture memory in a 4v4 CTF at Lighting High and Low (--print-vram), as a table")
    which.add_argument("--soak", action="store_true",
        help="a heat soak: CPU-vs-CPU 4v4 CTF at --fps for --minutes, with the screen report and temperatures")
    ap.add_argument("--minutes", type=float, default=None,
        help="--play: stop after this long at most (default 20); --soak: how long to run (default 10)")
    a = ap.parse_args(argv)
    if a.minutes is None:
        a.minutes = 10.0 if a.soak else 20.0
    if a.minutes <= 0:
        ap.error("--minutes must be more than 0")
    if a.vram and a.no_export:
        ap.error("--vram builds one APK per Lighting tier: --no-export doesn't apply")
    if not a.label:
        a.label = "vram" if a.vram else ("soak" if a.soak else "run")
    return a


def run_vram(a):
    rows, head = [], []
    for tier in ("high", "low"):
        flags = vram_flags(tier) + (" " + a.extra if a.extra else "")
        print(f"VRAM run, Lighting {tier}: exporting", flush=True)
        export_apk(flags, a.renderer)
        install()
        launch()
        start = time.time()
        time.sleep(3)
        while adb("shell", "pidof", PACKAGE, check=False).strip() and time.time() - start < 180:
            time.sleep(2)
        found = parse_vram(adb("logcat", "-d", "-s", "godot:I", check=False))
        if not found:
            print(f"warning: no VRAM line at Lighting {tier} (`adb logcat -d -s godot`)")
        rows += found
        head.append(f"run {tier}: {flags}")
    lines = head + [""] + vram_table(rows)
    out = write_report(a.label, lines)
    print("\n".join(vram_table(rows)))
    print("full report:", out)


def run_soak(a, peak):
    flags = soak_flags(a.fps) + (" " + a.extra if a.extra else "")
    if not a.no_export:
        export_apk(flags, a.renderer)
        install()
    launch()
    start = time.time()
    limit = a.minutes * 60
    layer, seen, period, temps, next_temp = "", {}, 0, [], 0.0
    print(f"Soak: {a.minutes:g} minutes of CPU-vs-CPU 4v4 CTF at {a.fps} fps. Leave the device alone.", flush=True)
    time.sleep(3)
    while time.time() - start < limit:
        if not adb("shell", "pidof", PACKAGE, check=False).strip():
            print("the game stopped before the time was up (crash? `adb logcat -d -s godot`)")
            break
        if time.time() - start >= next_temp:
            temps.append((time.time() - start, thermal_sample()))
            print(thermal_report(temps[-1:])[0], flush=True)
            next_temp += THERMAL_EVERY
        # SurfaceFlinger keeps ~128 presents (about a second at 120 Hz): read often.
        layer = layer or game_layer()
        if layer:
            period = presents(layer, seen) or period
        time.sleep(0.5)
    temps.append((time.time() - start, thermal_sample()))
    adb("shell", "input", "keyevent", "KEYCODE_HOME")  # the game reports when it goes to the background
    time.sleep(5)
    perf = godot_lines(adb("logcat", "-d", "-s", "godot:I", check=False), "PERF")
    adb("shell", "am", "force-stop", PACKAGE)
    screen = screen_report(seen, period, fights_only=True)
    head = [f"run {a.label}: {flags}", f"renderer {a.renderer}, device peak_refresh_rate {peak}",
        f"took {time.time() - start:.0f} s"]
    lines = head + screen + thermal_report(temps) + (perf or ["PERF no lines in logcat"])
    out = write_report(a.label, lines)
    for l in head + screen + thermal_report(temps):
        print(l)
    print("full report:", out)


def main(argv=None):
    a = parse_args(argv)
    if a.export_only:
        export_apk(vram_flags("high") if a.vram else soak_flags(a.fps) if a.soak else run_flags(a), a.renderer)
        print("exported", APK)
        return
    need_device()
    peak = adb("shell", "settings", "get", "system", "peak_refresh_rate", check=False).strip()
    if a.fps > 60 and not a.vram and peak not in ("120", "120.0", "144", "144.0"):
        print(f"warning: the device's peak_refresh_rate is {peak}: it will hold apps to 60")
    if a.vram:
        return run_vram(a)
    if a.soak:
        return run_soak(a, peak)

    flags = run_flags(a)
    if not a.no_export:
        export_apk(flags, a.renderer)
        install()
    launch()
    if a.play:
        print("Play now. Press Home on the device when you're done (the game reports when it goes to the background).", flush=True)
    start = time.time()
    limit = a.minutes * 60 if a.play else 60 + a.frames / max(30, a.fps) * 2
    layer, seen, period = "", {}, 0
    time.sleep(3)
    while adb("shell", "pidof", PACKAGE, check=False).strip() and time.time() - start < limit:
        if a.play and "PERF fps" in adb("logcat", "-d", "-s", "godot:I", check=False):
            break  # it went to the background and reported
        # SurfaceFlinger keeps ~128 presents (about a second at 120 Hz): read often.
        layer = layer or game_layer()
        if layer:
            period = presents(layer, seen) or period
        time.sleep(0.5)
    perf = godot_lines(adb("logcat", "-d", "-s", "godot:I", check=False), "PERF")
    if not perf:
        sys.exit("no PERF lines in logcat (did it crash? `adb logcat -d -s godot`)")
    temp = adb("shell", "cat", "/sys/class/thermal/thermal_zone0/temp", check=False).strip()
    head = [f"run {a.label}: {flags}", f"renderer {a.renderer}, device peak_refresh_rate {peak}, zone0 temp at end {temp}",
        f"took {time.time() - start:.0f} s"]
    perf += screen_report(seen, period, fights_only=a.play)
    out = write_report(a.label, head + perf)
    for l in head + [l for l in perf if l.startswith("PERF fps") or l.startswith("PERF frame") or l.startswith("PERF first")
            or l.startswith("SCREEN") or "game ms" in l or "render" in l or "warmup" in l]:
        print(l)
    print("full report:", out)


if __name__ == "__main__":
    main()
