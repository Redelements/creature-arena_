"""Measure frame pacing on an Android device (the AYN Odin 3) over adb.

    python tools/odin_perf.py --label ctf4v4-gl
    python tools/odin_perf.py --label ctf4v4-vk --renderer mobile
    python tools/odin_perf.py --label duel-gl --mode 6 --frames 7200
    python tools/odin_perf.py --label soak --frames 72000          (10 minutes at 120 fps)
    python tools/odin_perf.py --label mine --play                   (you play; press Home to end)

Each run bakes the game's flags into the Android preset (`command_line/extra_args`),
exports a release APK (debug templates run GDScript slower), installs it, plays the fight
to `--quit-after`, and reads the `--perf` report from logcat (a release APK isn't
debuggable, so `run-as` can't read user://perf.txt). The report goes to
build/perf/<label>.txt. export_presets.cfg and project.godot are put back afterwards,
whatever happens. `--renderer gl` builds with gl_compatibility instead of Vulkan (Mobile).
`--play` builds a normal game with only --perf: play it on the device, then press Home; the
report is written when the app goes to the background, and SCREEN keeps only the fights
(menus run at 60). The first run after an install also compiles Vulkan shaders: one hitch
of ~40 ms that a second run doesn't have. Judge by the SCREEN lines (SurfaceFlinger's presents), not the CPU-side PERF frame times.

Needs: Godot at GODOT (or the default path below), adb at ADB, the device's own refresh
setting at 120 (Settings > Display, or `adb shell settings put system peak_refresh_rate
120` and `min_refresh_rate 120`): nothing in the game can override it.
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


def adb(*args, check=True):
    return subprocess.run([ADB, *args], capture_output=True, text=True, check=check).stdout


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
    out = adb("shell", f"dumpsys SurfaceFlinger --latency '{layer}'", check=False).split()
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


def swap(path, pattern, repl):
    text = open(path, encoding="utf-8").read()
    new, n = re.subn(pattern, repl, text, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"{path}: no line matching {pattern}")
    open(path, "w", encoding="utf-8", newline="\n").write(new)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True)
    ap.add_argument("--mode", type=int, default=53, help="53 = Capture the Flag 4v4, the worst case")
    ap.add_argument("--level", type=int, default=1, help="CPU level: 1 = Normal (no Rage runs)")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--fps", type=int, default=120)
    ap.add_argument("--frames", type=int, default=4800, help="--quit-after: 40 s at 120 fps")
    ap.add_argument("--renderer", choices=["gl", "mobile"], default="mobile", help="mobile = Vulkan, the default")
    ap.add_argument("--extra", default="", help="more game flags, e.g. --cpu-threads=off")
    ap.add_argument("--no-export", action="store_true", help="reuse the last APK")
    ap.add_argument("--export-only", action="store_true", help="build the APK, no device needed")
    ap.add_argument("--play", action="store_true",
        help="a normal build (only --perf): you play; it records the screen until the app goes to the background (Home)")
    ap.add_argument("--minutes", type=float, default=20.0, help="--play: stop after this long at most")
    a = ap.parse_args()

    if not a.export_only and "device" not in adb("get-state", check=False):
        sys.exit("no device: plug the Odin in and allow USB debugging")
    peak = "" if a.export_only else adb("shell", "settings", "get", "system", "peak_refresh_rate").strip()
    if not a.export_only and a.fps > 60 and peak not in ("120", "120.0", "144", "144.0"):
        print(f"warning: the device's peak_refresh_rate is {peak}: it will hold apps to 60")

    flags = "-- --perf" if a.play else f"-- --mode={a.mode} --level={a.level} --seed={a.seed} --perf --fight-fps={a.fps} --quit-after={a.frames} {a.extra}".strip()
    presets = os.path.join(ROOT, "export_presets.cfg")
    project = os.path.join(ROOT, "project.godot")
    backups = {p: p + ".perfbak" for p in (presets, project)}
    if not a.no_export:
        for p, b in backups.items():
            shutil.copyfile(p, b)
        try:
            swap(presets, r'^command_line/extra_args=".*"$', f'command_line/extra_args="{flags}"')
            method = "mobile" if a.renderer == "mobile" else "gl_compatibility"
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
        if a.export_only:
            print("exported", APK)
            return
        installed = adb("install", "-r", APK, check=False)
        if "Success" not in installed:
            # a CI or debug APK signed with another key: replace it
            adb("uninstall", PACKAGE, check=False)
            if "Success" not in adb("install", APK, check=False):
                sys.exit("install failed")

    adb("shell", "am", "force-stop", PACKAGE)
    adb("logcat", "-c")
    if a.play:
        print("Play now. Press Home on the device when you're done (the game reports when it goes to the background).", flush=True)
    adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")
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
    log = adb("logcat", "-d", "-s", "godot:I", check=False)
    perf = [l.split("godot", 1)[-1].lstrip(" :") for l in log.splitlines() if "PERF" in l]
    if not perf:
        sys.exit("no PERF lines in logcat (did it crash? `adb logcat -d -s godot`)")
    temp = adb("shell", "cat", "/sys/class/thermal/thermal_zone0/temp", check=False).strip()
    head = [f"run {a.label}: {flags}", f"renderer {a.renderer}, device peak_refresh_rate {peak}, zone0 temp at end {temp}",
        f"took {time.time() - start:.0f} s"]
    perf += screen_report(seen, period, fights_only=a.play)
    out = os.path.join(ROOT, "build", "perf", a.label + ".txt")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write("\n".join(head + perf) + "\n")
    for l in head + [l for l in perf if l.startswith("PERF fps") or l.startswith("PERF frame") or l.startswith("SCREEN") or "game ms" in l or "render" in l]:
        print(l)
    print("full report:", out)


if __name__ == "__main__":
    main()
