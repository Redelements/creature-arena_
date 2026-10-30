"""Digby sheets re-rendered with the rig camera pitched down (PITCH env, default 35 deg)."""
import math, os, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import numpy as np
import splat3d as S

P_DEG = float(os.environ.get("PITCH", "35"))
SIDE_A = math.radians(18.4)


class PitchedCam(S.Cam):
    PITCH = P_DEG

    def __init__(self, view):
        self.view = view
        p = math.radians(self.PITCH)
        self.p = p
        c, s, D = math.cos(p), math.sin(p), math.sqrt(0.5)
        self.tan = math.tan(p)
        if view == "side":
            self.cam = np.array([0.5 * c, s, 0.866 * c])
            self.fl = np.array([math.cos(SIDE_A), 0.0, math.sin(SIDE_A)])
        elif view == "down":
            self.cam = np.array([0.0, s, c]); self.fl = np.array([0.0, 0.0, 1.0])
        elif view == "up":
            self.cam = np.array([0.0, s, -c]); self.fl = np.array([0.0, 0.0, -1.0])
        elif view == "down_side":
            self.cam = np.array([D * c, s, D * c]); self.fl = np.array([D, 0.0, D])
        elif view == "up_side":
            self.cam = np.array([D * c, s, -D * c]); self.fl = np.array([D, 0.0, -D])
        else:
            raise ValueError(view)

    def P(self, pts):
        lat, up, fwd = pts[:, 0], pts[:, 1], pts[:, 2]
        D = math.sqrt(0.5)
        fd = pts @ self.fl
        v = self.view
        if v == "side":
            x = S.OX + fwd - lat * self.LAT_X
        elif v == "down":
            x = S.OX - lat
        elif v == "up":
            x = S.OX + lat
        elif v == "down_side":
            x = S.OX + (fwd - lat) * D
        else:
            x = S.OX + (fwd + lat) * D
        y = S.OY - up + fd * self.tan
        return np.stack([x, y], axis=1)

    def screen_dir(self, n):
        v = self.view
        if v == "side":
            sx = n[:, 2] - n[:, 0] * self.LAT_X
        elif v == "down":
            sx = -n[:, 0]
        elif v == "up":
            sx = n[:, 0]
        elif v == "down_side":
            sx = (n[:, 2] - n[:, 0]) * math.sqrt(0.5)
        else:
            sx = (n[:, 2] + n[:, 0]) * math.sqrt(0.5)
        sy = -n[:, 1] * math.cos(self.p) + (n @ self.fl) * math.sin(self.p)
        sz = n @ self.cam
        w = np.stack([sx, sy, sz * 1.4], axis=1)
        return w / (np.linalg.norm(w, axis=1, keepdims=True) + 1e-9)


S.Cam = PitchedCam
import gen_digby as GD

OUTD = os.path.join(ROOT, "spike", "hd2d", "assets", "sprites", "pitched")
OUT = os.path.join(OUTD, "digby_2x.png")
PREVIEW = os.path.join(OUTD, "digby_2x_preview.png")

if __name__ == "__main__":
    S.write_sheets(GD.ROWS, GD.VIEW_ROWS, OUT, PREVIEW, GD.SIDE, GD.VIEWS, GD.build, normals=True)
