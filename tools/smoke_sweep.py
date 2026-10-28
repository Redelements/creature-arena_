"""Headless smoke sweep: every mode on every arena, grepping the output for script errors.

    python -I tools/smoke_sweep.py --godot G --root . --appdata DIR [--out FILE] [--frames 600] [--jobs 3]
                                   [--modes 0-55] [--arenas stadium,quarry,floodgate,greenhouse] [--mutators on|off]

The four `--arena` ids are the map choices; Caravan and Capture the Flag play their own maps
whatever is passed, so the default covers every map. Every run has all four hazard mutators on.
About four minutes for the 216 runs at three at a time (Windows, this PC).

Skips mode 20 (online) and 47 (a replay needs a file). Each run gets its own APPDATA subdir so
runs in parallel never share user://. Exit code 1 if any run printed SCRIPT ERROR, Parse Error,
Failed to load, or exited non-zero / timed out.
"""
import argparse, os, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

BAD = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load|ERROR: .*(Invalid|Nonexistent|out of bounds|null instance)", re.I)
SKIP = {20, 47}

def parse_modes(s):
    out = []
    for part in s.split(","):
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return [m for m in out if m not in SKIP]

def run_one(godot, root, appdata, mode, arena, frames, mutators, idx):
    env = dict(os.environ)
    sub = os.path.join(appdata, "sweep%d" % (idx % 64))
    os.makedirs(sub, exist_ok=True)
    env["APPDATA"] = sub
    cmd = [godot, "--headless", "--fixed-fps", "60", "--path", root, "--",
           "--mode=%d" % mode, "--arena=%s" % arena, "--level=1", "--seed=%d" % (1000 + idx),
           "--quit-after=%d" % frames]
    if mutators:
        cmd.append("--mutators=tidal_wave,meteor_shower,rolling_boulder,fault_line")
    t0 = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=240, env=env, errors="replace")
        out = (p.stdout or "") + (p.stderr or "")
        code = p.returncode
    except subprocess.TimeoutExpired as e:
        out = ((e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")) + "\nTIMEOUT"
        code = -999
    bad = [l for l in out.splitlines() if BAD.search(l)]
    return mode, arena, code, time.time() - t0, bad, out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", required=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("--appdata", required=True)
    ap.add_argument("--out", default="")
    ap.add_argument("--frames", type=int, default=600)
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--modes", default="0-55")
    ap.add_argument("--arenas", default="")
    ap.add_argument("--mutators", default="on")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    arenas = a.arenas.split(",") if a.arenas else ["stadium", "quarry", "floodgate", "greenhouse"]
    modes = parse_modes(a.modes)
    jobs = [(m, ar) for m in modes for ar in arenas]
    print("sweep: %d modes x %d arenas = %d runs, %d at a time" % (len(modes), len(arenas), len(jobs), a.jobs), flush=True)
    results = []
    failed = 0
    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = [ex.submit(run_one, a.godot, root, a.appdata, m, ar, a.frames, a.mutators == "on", i)
                for i, (m, ar) in enumerate(jobs)]
        for f in futs:
            mode, arena, code, dt, bad, out = f.result()
            ok = code == 0 and not bad
            if not ok:
                failed += 1
            line = "%s mode %2d %-14s exit %4d %5.1fs" % ("ok  " if ok else "FAIL", mode, arena, code, dt)
            print(line, flush=True)
            for b in bad[:5]:
                print("     " + b.strip()[:200], flush=True)
            results.append((line, bad, out if not ok else ""))
    summary = "sweep: %d runs, %d failed" % (len(jobs), failed)
    print(summary, flush=True)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(summary + "\n")
            for line, bad, out in results:
                fh.write(line + "\n")
                for b in bad:
                    fh.write("     " + b.strip() + "\n")
                if out:
                    fh.write("----- output -----\n" + out[-6000:] + "\n------------------\n")
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
