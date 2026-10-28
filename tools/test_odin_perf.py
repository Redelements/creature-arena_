"""Tests for tools/odin_perf.py that need no device: the arguments, the no-device message,
and the reports from canned logcat, dumpsys and SurfaceFlinger text.

    python -I -m unittest discover -s tools -p "test_*.py"
"""
import unittest

import odin_perf as op

LOGCAT_VRAM = """\
--------- beginning of main
10-28 12:00:01.000  4242  4260 I godot   : Ready 4 Rambles
10-28 12:00:11.000  4242  4260 I godot   : VRAM frame 600, lighting high: textures 350.1 MB, video 372.5 MB; fighter sheets: 25 colour 143.0 MB, 25 normal 35.7 MB, 25 emissive 35.7 MB
10-28 12:00:12.000  4242  4260 I godot   : PERF setup: vsync on
"""

LOGCAT_VRAM_LOW = """\
10-28 12:05:11.000  4300  4310 I godot   : VRAM frame 600, lighting low: textures 346.2 MB, video 360.5 MB; fighter sheets: 25 colour 143.0 MB, 25 normal 35.7 MB, 25 emissive 35.7 MB
"""

THERMALSERVICE = """\
IsStatusOverride: false
ThermalEventListeners:
\tcallbacks: 1
Thermal Status: 1
Cached temperatures:
\tTemperature{mValue=30.0, mType=2, mName=battery, mStatus=0}
HAL Ready: true
HAL connection:
\tThermalHAL 2.0 connected: yes
Current temperatures from HAL:
\tTemperature{mValue=41.5, mType=0, mName=cpu-0-0-usr, mStatus=0}
\tTemperature{mValue=44.25, mType=0, mName=cpu-1-2-usr, mStatus=1}
\tTemperature{mValue=33.1, mType=2, mName=battery, mStatus=0}
\tTemperature{mValue=36.0, mType=3, mName=skin-msm-therm, mStatus=0}

Current cooling devices from HAL:
\tCoolingDevice{mValue=0, mType=2, mName=cpu-cluster0}
"""

SYS_THERMAL = """\
aoss0-usr 38000
cpu-0-0-usr 40200
cpu-1-3-usr 45700
battery 31000
"""


class FakeAdb:
    """Stands in for op.adb: the reply of the first key the command line starts with."""
    def __init__(self, replies):
        self.replies = replies
        self.calls = []

    def __call__(self, *args, check=True):
        self.calls.append(args)
        line = " ".join(args)
        for key, out in self.replies.items():
            if line.startswith(key):

                if isinstance(out, Exception):
                    raise out
                return out
        return ""


class ArgsTest(unittest.TestCase):
    def test_vram(self):
        a = op.parse_args(["--vram"])
        self.assertTrue(a.vram)
        self.assertEqual(a.label, "vram")
        self.assertEqual(a.renderer, "mobile")

    def test_soak_minutes(self):
        a = op.parse_args(["--soak", "--minutes=10"])
        self.assertTrue(a.soak)
        self.assertEqual(a.minutes, 10.0)
        self.assertEqual(a.label, "soak")
        self.assertEqual(a.fps, 120)
        self.assertEqual(op.parse_args(["--soak"]).minutes, 10.0, "ten minutes by default")
        self.assertEqual(op.parse_args(["--play"]).minutes, 20.0, "--play keeps its 20")

    def test_old_runs_keep_working(self):
        a = op.parse_args(["--label", "ctf4v4-vk", "--renderer", "mobile"])
        self.assertEqual(a.label, "ctf4v4-vk")
        self.assertIn("--mode=53 --level=1 --seed=7 --perf --fight-fps=120 --quit-after=4800", op.run_flags(a))

    def test_modes_exclude_each_other(self):
        with self.assertRaises(SystemExit):
            op.parse_args(["--vram", "--soak"])
        with self.assertRaises(SystemExit):
            op.parse_args(["--soak", "--minutes=0"])
        with self.assertRaises(SystemExit):
            op.parse_args(["--vram", "--no-export"])

    def test_flags(self):
        self.assertEqual(op.vram_flags("low"),
            "-- --mode=53 --level=1 --seed=7 --cpu-vs-cpu --lighting=low --print-vram=600 --quit-after=660")
        f = op.soak_flags(120)
        for want in ("--mode=53", "--level=1", "--cpu-vs-cpu", "--perf", "--fight-fps=120", "--rematch-after="):
            self.assertIn(want, f)
        self.assertNotIn("--quit-after", f, "the script ends the soak (Home), not a frame count")


class DeviceTest(unittest.TestCase):
    def setUp(self):
        self.real = op.adb

    def tearDown(self):
        op.adb = self.real

    def test_no_device_stops_with_a_message(self):
        op.adb = FakeAdb({"get-state": ""})
        with self.assertRaises(SystemExit) as e:
            op.need_device()
        self.assertIn("no device: plug the Odin in", str(e.exception))

    def test_unauthorized_device_too(self):
        op.adb = FakeAdb({"get-state": "unauthorized\n"})
        with self.assertRaises(SystemExit) as e:
            op.need_device()
        self.assertIn("unauthorized", str(e.exception))

    def test_no_adb(self):
        op.adb = FakeAdb({"get-state": FileNotFoundError()})
        with self.assertRaises(SystemExit) as e:
            op.need_device()
        self.assertIn("adb not found", str(e.exception))

    def test_main_never_exports_without_a_device(self):
        op.adb = FakeAdb({"get-state": ""})
        exported = []
        real_export = op.export_apk
        op.export_apk = lambda *a: exported.append(a)
        try:
            for argv in (["--vram"], ["--soak", "--minutes=10"]):
                with self.assertRaises(SystemExit):
                    op.main(argv)
        finally:
            op.export_apk = real_export
        self.assertEqual(exported, [], "the device check comes before the export")

    def test_a_device_passes(self):
        op.adb = FakeAdb({"get-state": "device\n"})
        op.need_device()

    def test_thermal_sample_falls_back_to_sysfs(self):
        op.adb = FakeAdb({"shell dumpsys thermalservice": "Can't find service: thermalservice\n",
            "shell for z": SYS_THERMAL})
        got = op.thermal_sample()
        self.assertAlmostEqual(got["temps"]["cpu-1-3-usr"], 45.7)
        self.assertIsNone(got["status"])


class ReportTest(unittest.TestCase):
    def test_parse_vram(self):
        rows = op.parse_vram(LOGCAT_VRAM + LOGCAT_VRAM_LOW)
        self.assertEqual([r["lighting"] for r in rows], ["high", "low"])
        self.assertEqual(rows[0]["frame"], 600)
        self.assertAlmostEqual(rows[0]["textures"], 350.1)
        self.assertAlmostEqual(rows[1]["video"], 360.5)
        self.assertEqual(rows[0]["sheets"]["colour"], (25, 143.0))
        self.assertEqual(rows[0]["sheets"]["emissive"], (25, 35.7))

    def test_vram_table(self):
        lines = op.vram_table(op.parse_vram(LOGCAT_VRAM + LOGCAT_VRAM_LOW))
        self.assertEqual(lines[0], "| Lighting | Textures MB | Video MB | colour sheets (MB) | normal sheets (MB) | emissive sheets (MB) |")
        self.assertEqual(lines[1], "|---|---|---|---|---|---|")
        self.assertEqual(lines[2], "| high | 350.1 | 372.5 | 25 (143.0) | 25 (35.7) | 25 (35.7) |")
        self.assertEqual(lines[3], "| low | 346.2 | 360.5 | 25 (143.0) | 25 (35.7) | 25 (35.7) |")
        self.assertIn("no lines found", op.vram_table([])[0])

    def test_parse_thermalservice(self):
        got = op.parse_thermal(THERMALSERVICE)
        self.assertEqual(got["status"], 1)
        self.assertEqual(got["temps"], {"cpu-0-0-usr": 41.5, "cpu-1-2-usr": 44.25, "battery": 33.1, "skin-msm-therm": 36.0},
            "the HAL's current temperatures, not the cached ones")

    def test_parse_sysfs(self):
        got = op.parse_thermal(SYS_THERMAL)
        self.assertEqual(got["temps"]["battery"], 31.0)
        self.assertEqual(got["temps"]["aoss0-usr"], 38.0)

    def test_thermal_report(self):
        lines = op.thermal_report([(0.0, op.parse_thermal(THERMALSERVICE)), (95.0, op.parse_thermal(SYS_THERMAL))])
        self.assertEqual(lines[0], "THERMAL  0:00 status 1 (light), CPU 44.2 C, battery 33.1 C, hottest cpu-1-2-usr 44.2 C")
        self.assertEqual(lines[1], "THERMAL  1:35 status -, CPU 45.7 C, battery 31.0 C, hottest cpu-1-3-usr 45.7 C")
        self.assertEqual(op.thermal_report([]), ["THERMAL no readings"])

    def test_godot_lines(self):
        self.assertEqual(op.godot_lines(LOGCAT_VRAM, "PERF"), ["PERF setup: vsync on"])

    def test_latency_and_screen_report(self):
        # 121.7 Hz: 8.22 ms a refresh. Ten seconds of presents, one held three refreshes at 5 s.
        per = 8216900
        text = [str(per)]
        t = 10**12
        for i in range(1300):
            t += per * (3 if i == 600 else 1)
            text.append("%d %d %d" % (t - 18 * 10**6, t, t - 2 * 10**6))
        seen = {}
        period = op.parse_latency("\n".join(text), seen)
        self.assertEqual(period, per)
        self.assertEqual(len(seen), 1300)
        rep = op.screen_report(seen, period)
        self.assertTrue(rep[0].startswith("SCREEN (SurfaceFlinger presents, refresh 8.22 ms"), rep[0])
        self.assertIn("frames held past one refresh: 1 ", rep[2])
        self.assertIn("3: 1", rep[3])
        self.assertIn("p50 18.0", rep[4])
        self.assertRegex(rep[5], r"long gaps .*: \d+\.\ds 25$")
        self.assertIn("not enough presents", op.screen_report({}, per)[0])


if __name__ == "__main__":
    unittest.main()
