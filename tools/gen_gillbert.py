#!/usr/bin/env python3
"""Gillbert sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_gillbert.py
Requires Pillow and numpy.

Writes assets/sprites/gillbert.png (128x128 frames, 8 columns, the side view),
gillbert_down.png and gillbert_up.png (96x144 frames: facing the camera, and facing
away), plus labelled previews in docs/.

Like Barkley's, the rig is posed once in 3D and projected into each view. A point is
(lat, up, fwd): lat toward his right side, up off the floor, fwd the way he faces.

  - The body is a tube along a bendable spine (curl it into a U, arch it, wiggle it
    side to side, roll it onto its side), drawn as a run of projected cross-sections.
  - Around his neck sits the red-and-white life ring, split into the half behind him
    and the half in front so the body passes through it.
  - Fins (dorsal, anal, pelvic, pectoral, a forked tail), an orange eye on each side,
    barbel whiskers, and the fishing line tangled round his body.
  - The rod that caught him is a separate rigid piece on the end of the line. It has
    its own position and spin in every pose, which is how it tumbles along behind him
    when he flops across the floor.

This is a recreation for the soft launch; when the artist delivers final sprites in
the same layout they drop in with no code changes.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "gillbert.png")
PREVIEW = os.path.join(ROOT, "docs", "gillbert_preview.png")

COLS = 8
SIDE = {"w": 128, "h": 128, "origin": (70, 112)}
VIEWS = {
    "down": {"w": 96, "h": 144, "origin": (48, 92)},
    "up": {"w": 96, "h": 144, "origin": (48, 76)},
}

# Palette, sampled from the character sheet.
C = {
    "outline": (22, 26, 18, 255),
    "body": (181, 230, 29, 255),
    "body_l": (214, 246, 96, 255),
    "body_d": (134, 184, 22, 255),
    "belly": (220, 240, 120, 255),
    "scale": (96, 136, 20, 255),
    "fin": (18, 92, 39, 255),
    "fin_l": (40, 132, 60, 255),
    "fin_d": (10, 62, 26, 255),
    "red": (237, 28, 36, 255),
    "red_l": (255, 96, 96, 255),
    "red_d": (168, 14, 24, 255),
    "white": (246, 246, 246, 255),
    "white_l": (255, 255, 255, 255),
    "white_d": (196, 200, 206, 255),
    "strap": (119, 67, 66, 255),
    "rod": (119, 67, 66, 255),
    "rod_l": (156, 98, 92, 255),
    "rod_d": (84, 46, 46, 255),
    "handle": (136, 0, 21, 255),
    "handle_l": (186, 40, 52, 255),
    "handle_d": (96, 0, 14, 255),
    "reel": (127, 127, 127, 255),
    "reel_l": (184, 184, 184, 255),
    "reel_d": (88, 88, 88, 255),
    "line": (150, 150, 150, 255),
    "eye": (255, 127, 39, 255),
    "eye_d": (206, 84, 16, 255),
    "pupil": (14, 10, 8, 255),
    "mouth": (70, 90, 20, 255),
}

# ------------------------------------------------------------------ image helpers

W = H = 128
OX, OY = SIDE["origin"]


def layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def _mask(img):
    return np.array(img)[:, :, 3] > 0


def _shift(m, dx, dy):
    h, w = m.shape
    p = np.zeros((h + 8, w + 8), bool)
    p[4:-4, 4:-4] = m
    return p[4 + dy:4 + dy + h, 4 + dx:4 + dx + w]


def shade(img, base, light, dark):
    """Recolors a filled shape: lit from the top left, shadowed on the bottom right."""
    a = np.array(img)
    m = a[:, :, 3] > 0
    out = np.zeros_like(a)
    out[m] = C[base]
    dk = m & (~_shift(m, 1, 1) | ~_shift(m, 0, 2) | ~_shift(m, 1, 2))
    out[dk] = C[dark]
    hl = m & (~_shift(m, -1, -1) | ~_shift(m, 0, -1)) & ~dk
    out[hl] = C[light]
    return Image.fromarray(out)


def outline(img, color="outline"):
    a = np.array(img)
    m = a[:, :, 3] > 0
    ring = (_shift(m, 1, 0) | _shift(m, -1, 0) | _shift(m, 0, 1) | _shift(m, 0, -1)) & ~m
    a[ring] = C[color]
    return Image.fromarray(a)


def clip_to(detail, shape):
    d = np.array(detail)
    d[~_mask(shape)] = 0
    return Image.fromarray(d)


def disc(d, c, r, col):
    d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=C[col])


def capsule(d, p0, p1, r0, r1, col):
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / ln, dx / ln
    d.polygon([(p0[0] + nx * r0, p0[1] + ny * r0), (p1[0] + nx * r1, p1[1] + ny * r1),
               (p1[0] - nx * r1, p1[1] - ny * r1), (p0[0] - nx * r0, p0[1] - ny * r0)], fill=C[col])
    disc(d, p0, r0, col)
    disc(d, p1, r1, col)


# ------------------------------------------------------------------ 3D

def v_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_mul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def v_len(a):
    return math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2)


def v_norm(a):
    ln = v_len(a) or 1.0
    return v_mul(a, 1.0 / ln)


def v_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def v_lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def rot_lat(p, deg):
    """Pitch about the lateral axis (positive tips the front up)."""
    a = math.radians(deg)
    lat, up, fwd = p
    return (lat, up * math.cos(a) + fwd * math.sin(a), -up * math.sin(a) + fwd * math.cos(a))


def rot_fwd(p, deg):
    """Roll about the forward axis (positive rolls his back toward his right)."""
    a = math.radians(deg)
    lat, up, fwd = p
    return (lat * math.cos(a) + up * math.sin(a), -lat * math.sin(a) + up * math.cos(a), fwd)


def rot_up(p, deg):
    """Turn about the vertical axis (positive turns his nose toward his left)."""
    a = math.radians(deg)
    lat, up, fwd = p
    return (lat * math.cos(a) - fwd * math.sin(a), up, lat * math.sin(a) + fwd * math.cos(a))


class Cam:
    """Barkley's projection (tools/gen_barkley.py): a cheated 3/4 side view with forward
    one to one, and up/down views where reach is one to one on the floor. A fish is flat
    side-on, so his sideways axis is sheared less than Barkley's arm span."""
    PSI = math.radians(60)
    LAT_X = 0.45
    LAT_Y = 0.15
    FWD_Y = 0.06

    def __init__(self, view):
        self.view = view
        if view == "side":
            self.cam = (math.cos(self.PSI), 0.0, math.sin(self.PSI))
        elif view == "down":
            self.cam = (0.0, 0.0, 1.0)
        else:
            self.cam = (0.0, 0.0, -1.0)

    @staticmethod
    def depth_y(f):
        # Barkley's flattening, but across a fish's whole length (he lies along the
        # depth axis in these views), so his body stays inside the life ring.
        k, near = 0.35, 20.0
        a = abs(f)
        g = a * k if a <= near else near * k + (a - near)
        return math.copysign(g, f)

    def P(self, p):
        lat, up, fwd = p
        if self.view == "side":
            return (OX + fwd - lat * self.LAT_X, OY - up + lat * self.LAT_Y + fwd * self.FWD_Y)
        if self.view == "down":
            return (OX - lat, OY - up + self.depth_y(fwd))
        return (OX + lat, OY - up - self.depth_y(fwd))

    def depth(self, p):
        return v_dot(p, self.cam)


# ------------------------------------------------------------------ pose

LENGTH = 36.0  # head tip to the root of the tail fin
CENTER_UP = 8.5  # spine height when he rests on his belly
RING_U = 0.1  # where the life ring sits along the body (1 = nose, -1 = tail)
RING_R, RING_T = 12.0, 2.7  # well wider than his body, so it reads as worn round his neck


def half_height(u):
    """Body half-height along the spine, u = 1 at the nose, -1 at the tail."""
    pts = [(-1.0, 2.2), (-0.75, 2.8), (-0.4, 5.2), (0.0, 6.6), (0.35, 6.8), (0.7, 6.0), (0.9, 4.6), (1.0, 2.8)]
    for (u0, h0), (u1, h1) in zip(pts, pts[1:]):
        if u0 <= u <= u1:
            return h0 + (h1 - h0) * (u - u0) / (u1 - u0)
    return pts[-1][1]


class Pose:
    def __init__(self, **kw):
        self.lift = kw.get("lift", 0.0)          # whole body off the floor
        self.shift = kw.get("shift", 0.0)        # whole body forward
        self.pitch = kw.get("pitch", 0.0)        # nose up (+) / down (-), degrees
        self.yaw = kw.get("yaw", 0.0)            # whole turn about the vertical, degrees
        self.roll = kw.get("roll", 0.0)          # rolled onto his side, degrees
        self.curl = kw.get("curl", 0.0)          # + U shape (nose and tail up), - arched
        self.wiggle = kw.get("wiggle", 0.0)      # side-to-side S through the tail
        self.squash = kw.get("squash", 1.0)      # flattening on a slap
        self.stretch = kw.get("stretch", 1.0)    # longer on a dash
        self.face = kw.get("face", "calm")       # calm | shout | hurt | ko
        self.gill = kw.get("gill", 0.0)          # gill cover flared open
        self.fins = kw.get("fins", 1.0)          # fin spread (0 tucked .. 1.4 splayed)
        # The rod: centre (lat, up, fwd), its pitch (0 = level, butt behind) and turn.
        self.rod = kw.get("rod", ((3.0, 1.5, -38.0), -6.0, 18.0))  # None: thrown, off in flight
        self.sag = kw.get("sag", 1.0)            # how much the line hangs (0 = taut)


class Fish:
    """A pose as 3D points: the spine, its cross-section frames, the ring and the rod."""

    def __init__(self, pose):
        self.p = pose
        # A pose that tips the nose up would push the tail through the floor: lift him
        # just enough to keep his lowest point on it.
        self._lift_extra = 0.0
        low = min(self.surface(-1.0 + k / 10.0, 180)[1] for k in range(21))
        c, t, upv, _s = self.frame(-1.0)
        for tip in (v_add(c, v_add(v_mul(t, -13.0), v_mul(upv, 10.0))), v_add(c, v_add(v_mul(t, -13.5), v_mul(upv, -9.5)))):
            low = min(low, tip[1])
        if low < 0.0:
            self._lift_extra = -low

    def world(self, q):
        """Body space to world: roll, pitch, turn and lift, about the body's centre."""
        p = self.p
        q = v_sub(q, (0.0, CENTER_UP, 0.0))
        q = rot_fwd(q, p.roll)
        q = rot_lat(q, p.pitch)
        q = rot_up(q, p.yaw)
        return v_add(q, (0.0, CENTER_UP + p.lift + getattr(self, "_lift_extra", 0.0), p.shift))

    def wdir(self, v):
        p = self.p
        return rot_up(rot_lat(rot_fwd(v, p.roll), p.pitch), p.yaw)

    def spine_local(self, u):
        p = self.p
        x = u * LENGTH * 0.5 * p.stretch
        y = CENTER_UP + p.curl * 6.0 * (u * u - 0.33)
        z = p.wiggle * 4.5 * math.sin(math.pi * (u + 1.0) * 0.75) * max(0.0, 0.6 - u)
        return (z, y, x)

    def frame(self, u):
        """(centre, along, up, side) in world space at u."""
        a = self.spine_local(min(1.0, u + 0.02))
        b = self.spine_local(max(-1.0, u - 0.02))
        t = v_norm(v_sub(a, b))
        side = v_norm(v_cross((0.0, 1.0, 0.0), t))  # toward his right (+lat) for t = +fwd
        side = (-side[0], -side[1], -side[2])
        side = v_norm(v_cross(t, (0.0, 1.0, 0.0))) if v_len(side) < 0.5 else side
        upv = v_norm(v_cross(side, t))
        if upv[1] < 0:
            upv = v_mul(upv, -1.0)
        c = self.spine_local(u)
        return self.world(c), self.wdir(t), self.wdir(upv), self.wdir(v_norm(v_cross(t, upv)))

    def surface(self, u, ang, out=0.0):
        """A point on the body surface; ang 0 = top, 90 = his right side, 180 = belly."""
        c, _t, upv, side = self.frame(u)
        hh = half_height(u) * self.p.squash + out
        hw = hh * 0.62 / max(0.6, self.p.squash) + out * 0.5
        a = math.radians(ang)
        return v_add(c, v_add(v_mul(upv, math.cos(a) * hh), v_mul(side, math.sin(a) * hw)))

    def normal(self, u, ang):
        _c, _t, upv, side = self.frame(u)
        a = math.radians(ang)
        return v_norm(v_add(v_mul(upv, math.cos(a)), v_mul(side, math.sin(a))))

    def rod_points(self):
        (c, pitch, yaw) = self.p.rod
        half = 18.0
        d = rot_up(rot_lat((0.0, 0.0, 1.0), pitch), yaw)
        butt = v_add(c, v_mul(d, -half))
        tip = v_add(c, v_mul(d, half))
        return butt, tip, d


# ------------------------------------------------------------------ painter

class Painter:
    def __init__(self, pose, view):
        self.p = pose
        self.f = Fish(pose)
        self.cam = Cam(view)
        self.view = view

    def P(self, q):
        return self.cam.P(q)

    def D(self, q):
        return self.cam.depth(q)

    def facing(self, n):
        return self.cam.depth(n)

    # -- body
    def body(self):
        img = layer()
        d = ImageDraw.Draw(img)
        n = 44
        for k in range(n + 1):
            u = -1.0 + 2.0 * k / n
            pts = [self.P(self.f.surface(u, a)) for a in range(0, 360, 20)]
            d.polygon(pts, fill=C["body"])
        img = shade(img, "body", "body_l", "body_d")
        det = layer()
        dd = ImageDraw.Draw(det)
        # pale belly
        for k in range(n + 1):
            u = -0.9 + 1.75 * k / n
            for a in (150, 180, 210):
                if self.facing(self.f.normal(u, a)) > -0.2:
                    q = self.P(self.f.surface(u, a, out=-0.6))
                    dd.point((round(q[0]), round(q[1])), fill=C["belly"])
        # scale chevrons along the flank facing us
        for side in (90, -90):
            if self.facing(self.f.normal(0.0, side)) < 0.15:
                continue
            for u in (0.15, -0.05, -0.25, -0.45):
                for a0 in (side - 40, side + 25):
                    tip = self.P(self.f.surface(u, a0 + (8 if side > 0 else -8)))
                    a = self.P(self.f.surface(u + 0.07, a0 - 12))
                    b = self.P(self.f.surface(u + 0.07, a0 + 28))
                    dd.line([a, tip, b], fill=C["scale"])
            # gill line, just behind the head
            g0 = self.P(self.f.surface(0.62 - self.p.gill * 0.05, side - 50))
            g1 = self.P(self.f.surface(0.58 - self.p.gill * 0.05, side + 35))
            dd.line([g0, g1], fill=C["outline"])
            if self.p.gill > 0.3:
                dd.line([(g0[0] - 1, g0[1]), (g1[0] - 1, g1[1])], fill=C["red_d"])
        # the line tangled round his body (front half of each loop)
        for u0, tilt in ((0.12, 25), (-0.18, -20)):
            pts = []
            for a in range(0, 361, 15):
                q = self.f.surface(u0 + math.sin(math.radians(a)) * 0.06 * (tilt / 25.0), a, out=0.4)
                if self.facing(self.f.normal(u0, a)) > 0.0:
                    pts.append(self.P(q))
                elif len(pts) > 1:
                    dd.line(pts, fill=C["line"])
                    pts = []
                else:
                    pts = []
            if len(pts) > 1:
                dd.line(pts, fill=C["line"])
        img.alpha_composite(clip_to(det, img))
        img = outline(img)
        self._face(img)
        return img

    def _face(self, img):
        dd = ImageDraw.Draw(img)
        o = C["outline"]
        f = self.p.face
        for side in (78, -78):
            # head-on, his bulging eyes still show at the sides of his head
            if self.facing(self.f.normal(0.7, side)) < (0.1 if self.view == "side" else -0.35):
                continue
            e = self.P(self.f.surface(0.72, side - (14 if side > 0 else -14)))
            x, y = round(e[0]), round(e[1])
            if f == "ko":
                dd.line([(x - 1, y - 1), (x + 1, y + 1)], fill=o)
                dd.line([(x - 1, y + 1), (x + 1, y - 1)], fill=o)
            elif f == "hurt":
                dd.line([(x - 1, y), (x + 1, y)], fill=o)
                dd.point((x, y - 1), fill=C["eye"])
            else:
                # the sheet's big orange eye, looking the way he faces
                look = self.P(v_add(self.f.surface(0.72, side), v_mul(self.f.frame(0.72)[1], 3.0)))
                lx = 1 if look[0] > e[0] + 0.5 else (-1 if look[0] < e[0] - 0.5 else 0)
                dd.ellipse([x - 2, y - 2, x + 2, y + 2], fill=o)
                dd.ellipse([x - 1, y - 1, x + 1, y + 1], fill=C["eye"])
                dd.point((x - 1, y + 1), fill=C["eye_d"])
                dd.point((x + lx, y), fill=C["pupil"])
                if f == "shout":
                    dd.point((x + lx, y - 1), fill=C["pupil"])
        # mouth along the snout, open when shouting
        if self.facing(self.f.normal(0.95, 90)) > -0.6 or self.view != "side":
            m0 = self.P(self.f.surface(0.99, 150))
            m1 = self.P(self.f.surface(0.84, 140))
            dd.line([m0, m1], fill=o)
            if f in ("shout", "hurt"):
                m2 = self.P(self.f.surface(0.9, 175, out=1.2))
                dd.line([m0, m2, m1], fill=C["mouth"])

    def barbels(self):
        """Two long whiskers off the end of the snout, as on the sheet."""
        img = layer()
        d = ImageDraw.Draw(img)
        c, t, upv, side = self.f.frame(0.98)
        for s in (1.0, -1.0):
            base = v_add(c, v_mul(side, s * 1.2))
            mid = v_add(base, v_add(v_mul(t, 5.0), v_add(v_mul(upv, 1.5), v_mul(side, s * 2.0))))
            tip = v_add(mid, v_add(v_mul(t, 5.0), v_add(v_mul(upv, -1.0 + s * 1.5), v_mul(side, s * 2.0))))
            d.line([self.P(base), self.P(mid), self.P(tip)], fill=C["outline"], width=1)
        return img

    # -- fins
    def _fin_poly(self, pts3, base="fin", light="fin_l", dark="fin_d"):
        img = layer()
        ImageDraw.Draw(img).polygon([self.P(q) for q in pts3], fill=C[base])
        img = shade(img, base, light, dark)
        det = layer()
        dd = ImageDraw.Draw(det)
        # rays: lines from the base toward the edge
        n = len(pts3)
        for k in range(1, n - 1):
            dd.line([self.P(pts3[0]), self.P(pts3[k])], fill=C[dark])
        img.alpha_composite(clip_to(det, img))
        return outline(img)

    def tail(self):
        c, t, upv, side = self.f.frame(-1.0)
        p = self.p
        flick = p.wiggle * 4.0
        spread = 10.0 * p.fins ** 0.5
        back = v_mul(t, -1.0)
        base_top = v_add(c, v_mul(upv, 2.3))
        base_bot = v_add(c, v_mul(upv, -2.3))
        top = v_add(c, v_add(v_mul(back, 13.0), v_add(v_mul(upv, spread), v_mul(side, flick))))
        notch = v_add(c, v_add(v_mul(back, 8.0), v_mul(side, flick * 0.7)))
        bot = v_add(c, v_add(v_mul(back, 13.5), v_add(v_mul(upv, -spread * 0.95), v_mul(side, flick))))
        return self._fin_poly([c, base_top, top, notch, bot, base_bot])

    def dorsal(self):
        p = self.p
        pts = [self.f.surface(0.05, 0, out=-0.5)]
        for u in (0.05, -0.1, -0.25, -0.42):
            pts.append(self.f.surface(u, 0, out=-0.5))
        up = 7.0 * p.fins
        _c, t, upv, _s = self.f.frame(-0.3)
        pts.append(v_add(self.f.surface(-0.5, 0), v_add(v_mul(upv, up * 0.6), v_mul(t, -3.0))))
        pts.append(v_add(self.f.surface(-0.2, 0), v_mul(upv, up)))
        pts.append(v_add(self.f.surface(0.0, 0), v_mul(upv, up * 0.7)))
        return self._fin_poly(pts)

    def anal(self):
        p = self.p
        _c, t, upv, _s = self.f.frame(-0.5)
        a = self.f.surface(-0.3, 180, out=-0.5)
        b = self.f.surface(-0.65, 180, out=-0.5)
        tip = v_add(self.f.surface(-0.55, 180), v_add(v_mul(upv, -6.0 * p.fins), v_mul(t, -3.0)))
        mid = v_add(self.f.surface(-0.4, 180), v_mul(upv, -5.0 * p.fins))
        return self._fin_poly([a, mid, tip, b])

    def pelvic(self):
        p = self.p
        _c, t, upv, _s = self.f.frame(0.1)
        a = self.f.surface(0.2, 180, out=-0.5)
        b = self.f.surface(0.0, 180, out=-0.5)
        tip = v_add(self.f.surface(0.0, 180), v_add(v_mul(upv, -4.0 * p.fins), v_mul(t, -2.0)))
        return self._fin_poly([a, tip, b])

    def pectoral(self, side):
        p = self.p
        _c, t, upv, sv = self.f.frame(0.5)
        root = self.f.surface(0.52, side * 120, out=-0.3)
        sgn = 1.0 if side > 0 else -1.0
        tip = v_add(root, v_add(v_mul(t, -5.0), v_add(v_mul(sv, sgn * 3.5 * p.fins), v_mul(upv, -2.0))))
        mid = v_add(root, v_add(v_mul(t, -3.0), v_add(v_mul(sv, sgn * 1.5), v_mul(upv, -3.5))))
        return self._fin_poly([root, tip, mid])

    # -- life ring
    def ring(self):
        """Two layers: the half of the ring behind the body and the half in front."""
        c, t, upv, side = self.f.frame(RING_U)
        cd = self.D(c)
        halves = [layer(), layer()]
        draws = [ImageDraw.Draw(h) for h in halves]
        pts = []
        for a in range(0, 360, 5):
            r = math.radians(a)
            q = v_add(c, v_add(v_mul(upv, math.cos(r) * RING_R), v_mul(side, math.sin(r) * RING_R * 0.92)))
            seg = ((a + 45) // 90) % 2  # quarters: white on top and bottom, red at the sides
            col = "white" if seg == 0 else "red"
            if (a % 90) in (40, 45, 50):
                col = "strap"
            front = 1 if self.D(q) >= cd else 0
            pts.append((front, q, col))
        # Seen side-on (and whenever a turn or roll puts it edge-on) the ring would shrink
        # to a thin band across his flank. Draw it as an oval at least this wide instead,
        # so in every pose it reads as the ring he wears round his neck, as on the sheet.
        cx = self.P(c)[0]
        half_w = max(abs(self.P(q)[0] - cx) for _f, q, _c in pts)
        want = RING_R * (0.6 if self.view == "side" else 0.0)
        k = max(1.0, want / max(half_w, 0.5))
        for front, q, col in pts:
            x, y = self.P(q)
            disc(draws[front], (cx + (x - cx) * k, y), RING_T, col)
        out = []
        for k, h in enumerate(halves):
            if not _mask(h).any():
                out.append(None)
                continue
            # shade each colour band separately, keeping its colour
            a = np.array(h)
            res = np.zeros_like(a)
            for base, li, dk in (("white", "white_l", "white_d"), ("red", "red_l", "red_d"),
                                 ("strap", "rod_l", "rod_d")):
                m = np.all(a[:, :, :3] == C[base][:3], axis=2) & (a[:, :, 3] > 0)
                if not m.any():
                    continue
                sub = np.zeros_like(a)
                sub[m] = C[base]
                sh = np.array(shade(Image.fromarray(sub), base, li, dk))
                res[m] = sh[m]
            out.append(outline(Image.fromarray(res)))
        return out, cd

    # -- rod and line
    def rod(self):
        butt, tip, dvec = self.f.rod_points()
        img = layer()
        d = ImageDraw.Draw(img)
        pb, pt = self.P(butt), self.P(tip)
        capsule(d, pb, pt, 1.6, 0.8, "rod")
        h1 = v_add(butt, v_mul(dvec, 8.0))
        capsule(d, pb, self.P(h1), 2.1, 1.8, "handle")
        img = shade(img, "rod", "rod_l", "rod_d")
        # recolour the handle end
        a = np.array(img)
        hm = layer()
        capsule(ImageDraw.Draw(hm), pb, self.P(h1), 2.1, 1.8, "handle")
        hm = shade(hm, "handle", "handle_l", "handle_d")
        hma = np.array(hm)
        m = hma[:, :, 3] > 0
        a[m] = hma[m]
        img = Image.fromarray(a)
        dd = ImageDraw.Draw(img)
        # line guides: small white loops along the rod
        for k in (0.45, 0.6, 0.75, 0.9):
            q = self.P(v_add(butt, v_mul(dvec, 36.0 * k)))
            dd.point((round(q[0]), round(q[1]) - 1), fill=C["white"])
        img = outline(img)
        # the reel: a grey disc beside the handle
        r = self.P(v_add(v_add(butt, v_mul(dvec, 9.5)), (0.0, 2.2, 0.0)))
        reel = layer()
        disc(ImageDraw.Draw(reel), r, 2.6, "reel")
        reel = outline(shade(reel, "reel", "reel_l", "reel_d"))
        img.alpha_composite(reel)
        return img, self.D(v_lerp(butt, tip, 0.5))

    def line(self):
        """The fishing line from his mouth to the rod's tip, hanging slack."""
        _b, tip, _d = self.f.rod_points()
        mouth = self.f.surface(0.95, 160)
        mid = v_lerp(mouth, tip, 0.5)
        sag = 6.0 * self.p.sag
        mid = (mid[0], mid[1] - sag, mid[2])
        img = layer()
        pts = []
        for k in range(21):
            t = k / 20.0
            q = v_add(v_add(v_mul(mouth, (1 - t) ** 2), v_mul(mid, 2 * t * (1 - t))), v_mul(tip, t * t))
            q = (q[0], max(0.3, q[1]), q[2])
            pts.append(self.P(q))
        ImageDraw.Draw(img).line(pts, fill=C["line"], width=1)
        return img

    # -- assemble
    def _part_mask(self, u0, u1):
        """Where the body samples between u0 and u1 land, grown by its outline."""
        img = layer()
        d = ImageDraw.Draw(img)
        n = 44
        for k in range(n + 1):
            u = -1.0 + 2.0 * k / n
            if u0 - 1e-6 <= u <= u1 + 1e-6:
                d.polygon([self.P(self.f.surface(u, a)) for a in range(0, 360, 20)], fill=C["body"])
        m = _mask(img)
        return m | _shift(m, 1, 0) | _shift(m, -1, 0) | _shift(m, 0, 1) | _shift(m, 0, -1)

    def render(self):
        parts = []  # (depth, order, image)
        body_d = self.D(self.f.frame(0.0)[0])
        if self.p.rod is not None:
            parts.append((body_d - 30.0, 0, self.line()))
            rod, rod_d = self.rod()
            parts.append((rod_d, 1, rod))
        tail = self.tail()
        parts.append((self.D(self.f.frame(-1.0)[0]) - 0.5, 2, tail))
        for fin in (self.dorsal(), self.anal(), self.pelvic()):
            parts.append((body_d - 0.3, 3, fin))
        for s in (90, -90):
            pec = self.pectoral(s)
            front = self.facing(self.f.normal(0.5, s)) > 0
            parts.append((body_d + (0.4 if front else -0.4), 5 if front else 2, pec))
        rings, ring_d = self.ring()
        body = self.body()
        if self.view == "side":
            # He wears it: the ring's far half goes behind his body and its near half
            # crosses in front, and it is much bigger than he is thick, so it shows above
            # his back and below his belly, as on the sheet. The halves are pinned to the
            # body's depth, not the ring's own, so a turn can't slip either one out of sight.
            if rings[0] is not None:
                parts.append((body_d - 0.05, 3, rings[0]))
            parts.append((body_d, 4, body))
            if rings[1] is not None:
                parts.append((body_d + 0.05, 6, rings[1]))
        else:
            # Seen head-on or from behind, he passes through the ring: the end of him
            # nearer the camera goes over it, the far end under it, so he is always in it.
            whole = [r for r in rings if r is not None]
            ring_img = layer()
            for r in whole:
                ring_img.alpha_composite(r)
            front = self._part_mask(RING_U, 1.0)
            a = np.array(body)
            head = a.copy()
            head[~front] = 0
            rest = a.copy()
            rest[front] = 0
            head_d = self.D(self.f.frame(0.6)[0])
            tail_d = self.D(self.f.frame(-0.4)[0])
            parts.append((tail_d, 4, Image.fromarray(rest)))
            parts.append((ring_d, 6, ring_img))
            parts.append((head_d, 4, Image.fromarray(head)))
            body_d = head_d  # the barbels come off the snout
        parts.append((body_d + 0.1, 7, self.barbels()))
        img = layer()
        for _d, _o, lay in sorted(parts, key=lambda t: (t[0], t[1])):
            img.alpha_composite(lay)
        return img


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


def rod_at(lat, up, fwd, pitch, yaw=18.0):
    return ((lat, up, fwd), pitch, yaw)


REST_ROD = rod_at(2.0, 1.5, -34.0, -4.0, 6.0)


def idle():
    """Lying on his belly, gills working, tail flicking; a little twitch hop now and then."""
    return [
        P(curl=0.25, wiggle=0.2, gill=0.0, rod=REST_ROD),
        P(curl=0.35, wiggle=-0.3, gill=0.8, rod=REST_ROD),
        P(curl=-0.2, lift=2.5, wiggle=0.5, gill=0.4, pitch=4, rod=REST_ROD, face="shout"),
        P(curl=0.3, wiggle=-0.1, gill=0.9, rod=REST_ROD),
    ]


def run():
    """Flopping across the floor: curl, spring, arch in the air, slap down, bounce. The rod
    tumbles end over end behind him on the line."""
    keys = [
        # curl, lift, pitch, wiggle, squash, face
        (0.3, 0.0, 0, 0.2, 1.0, "calm"),
        (1.1, 0.0, -4, 0.0, 0.92, "calm"),
        (-0.6, 6.0, 12, -0.4, 1.0, "shout"),
        (-0.9, 10.0, 4, 0.6, 1.0, "shout"),
        (0.2, 7.0, -12, -0.5, 1.0, "calm"),
        (0.7, 0.0, -2, 0.3, 0.8, "shout"),
        (-0.3, 3.0, 6, -0.6, 1.0, "calm"),
        (0.45, 0.0, 0, 0.3, 0.95, "calm"),
    ]
    out = []
    for k, (curl, lift, pitch, wig, sq, face) in enumerate(keys):
        ang = -k * 55.0  # rod tumbling end over end
        bounce = abs(math.sin(math.radians(k * 67.0))) * 9.0
        rod = rod_at(4.0 + math.sin(k) * 2.0, 4.0 + bounce, -32.0 - 2.0 * math.cos(k * 0.8), ang,
                     18.0 + 25.0 * math.sin(k * 1.3))
        out.append(P(curl=curl, lift=lift, pitch=pitch, wiggle=wig, squash=sq, face=face, rod=rod,
                     sag=0.4 + 0.3 * (k % 2), fins=1.1 if lift > 0 else 0.9, gill=0.5 * (k % 2)))
    return out


def jab():
    """Light 1, Snout Jab: rear back, then bonk forward with the nose."""
    return [
        P(curl=0.5, pitch=10, shift=-3, rod=REST_ROD, face="calm"),
        P(curl=-0.3, pitch=-6, shift=8, lift=2, stretch=1.08, rod=REST_ROD, face="shout"),
        P(curl=-0.2, pitch=-4, shift=7, lift=1, stretch=1.05, rod=REST_ROD, face="shout"),
        P(curl=0.3, rod=REST_ROD),
    ]


def whip():
    """Light 2, Tail Whip: a half turn on the belly so the tail lashes across in front."""
    return [
        P(curl=0.6, yaw=-25, wiggle=0.8, rod=REST_ROD, face="calm"),
        P(curl=0.2, yaw=120, wiggle=-1.2, lift=2, rod=REST_ROD, face="shout"),
        P(curl=0.2, yaw=165, wiggle=-0.8, lift=1, rod=REST_ROD, face="shout"),
        P(curl=0.3, yaw=20, wiggle=0.3, rod=REST_ROD),
    ]


def flail():
    """Light 3, Rod Flail: a jerk of the head swings the rod up over him on its line and
    down onto whoever is in front."""
    return [
        P(curl=0.4, pitch=8, rod=REST_ROD, face="calm"),
        P(curl=-0.4, pitch=20, rod=rod_at(2, 18, -22, 70), sag=0.0, face="shout"),
        P(curl=-0.6, pitch=24, lift=2, rod=rod_at(1, 34, 0, 160), sag=0.0, face="shout"),
        P(curl=0.3, pitch=-14, rod=rod_at(1, 8, 25, 200, 0), sag=0.0, face="shout"),
        P(curl=0.3, pitch=-8, rod=rod_at(1, 2.5, 23, 182, 0), sag=0.3),
        P(curl=0.3, pitch=0, rod=rod_at(2, 12, -16, 40), sag=0.4),
    ]


def splash():
    """Heavy, Splash Zone: curl up with the tail high, then slap the floor flat."""
    return [
        P(curl=1.3, pitch=-6, fins=1.2, rod=REST_ROD, face="calm", gill=0.6),
        P(curl=1.5, pitch=-8, fins=1.3, rod=REST_ROD, face="shout", gill=1.0),
        P(curl=1.0, pitch=-24, lift=6, fins=1.3, rod=REST_ROD, face="shout"),
        P(curl=-0.5, pitch=2, squash=0.78, fins=1.4, rod=REST_ROD, face="shout"),
        P(curl=-0.3, pitch=0, squash=0.85, fins=1.3, rod=REST_ROD, face="shout"),
        P(curl=0.3, rod=REST_ROD),
    ]


def flopdash():
    """Skill 1, Flop Dash: a coiled crouch, then a long skidding belly-flop forward."""
    trail = rod_at(5, 6, -44, 30, 30)
    return [
        P(curl=1.2, pitch=6, rod=REST_ROD, face="calm"),
        P(curl=-0.4, pitch=-6, lift=5, stretch=1.15, wiggle=0.6, fins=1.3, rod=trail, sag=0.0, face="shout"),
        P(curl=-0.2, pitch=-3, lift=2, stretch=1.15, wiggle=-0.6, fins=1.2, rod=rod_at(4, 3, -46, -40, 0),
          sag=0.0, face="shout"),
        P(curl=0.4, squash=0.9, rod=rod_at(3, 1.5, -40, -8)),
    ]


def cast():
    """Skill 2, Cast Line: whip the head back, fling the rod out on its line, and get
    hauled in after it."""
    return [
        P(curl=0.5, pitch=14, rod=rod_at(2, 12, -26, 60), sag=0.2, face="calm"),
        P(curl=-0.5, pitch=26, lift=2, rod=rod_at(0, 30, -6, 150), sag=0.0, face="shout"),
        # thrown: the rod leaves him, spinning off on its line (the game draws it in flight)
        P(curl=-0.2, pitch=-10, rod=rod_at(0, 18, 30, 200, 0), sag=0.0, face="shout"),
        P(curl=-0.1, pitch=-6, rod=None, face="shout", fins=1.2),
        # hooked: hauled in nose first, stretched out, fins swept back, tail trailing
        P(curl=-0.5, pitch=-5, lift=3, stretch=1.15, wiggle=0.5, fins=0.7, rod=None, face="shout", gill=1.0),
        P(curl=0.3, rod=None, face="calm"),
    ]


def leap():
    """Surge, The One That Got Away: crouch, spring straight up out of reach, then come
    down belly first in a huge splash. (The game lifts him off the screen; these frames
    are the poses.)"""
    hang = rod_at(1, 6, -10, 70, 0)
    return [
        P(curl=1.5, pitch=-4, fins=1.2, rod=REST_ROD, face="calm", gill=0.8),
        P(curl=-0.6, pitch=60, lift=6, stretch=1.1, fins=1.3, rod=rod_at(2, 6, -20, 40), sag=0.0, face="shout"),
        P(curl=-0.4, pitch=78, lift=8, wiggle=0.5, fins=1.4, rod=rod_at(1, 8, -16, 60, 0), sag=0.0, face="shout"),
        P(curl=-0.9, pitch=-8, lift=4, fins=1.4, rod=hang, sag=0.0, face="shout"),
        P(curl=-0.5, squash=0.72, fins=1.45, rod=rod_at(3, 4, -24, 30), face="shout"),
        P(curl=0.4, rod=rod_at(3, 1.5, -34, -4)),
    ]


def dodge():
    """A flip: he rolls right over sideways in a hop."""
    return [
        P(curl=0.9, roll=0, lift=1, rod=REST_ROD, face="calm"),
        P(curl=-0.3, roll=120, lift=7, fins=0.7, rod=rod_at(3, 4, -36, -20), face="hurt"),
        P(curl=-0.3, roll=240, lift=6, fins=0.7, rod=rod_at(3, 3, -36, -30), face="hurt"),
        P(curl=0.3, roll=360, rod=REST_ROD),
    ]


def hurt():
    return [
        P(curl=-0.9, pitch=10, lift=2, fins=1.3, rod=REST_ROD, face="hurt", gill=1.0),
        P(curl=0.8, roll=55, rod=REST_ROD, face="hurt"),
    ]


def guard():
    """Curled up behind the life ring, fins tucked."""
    g = dict(curl=1.6, pitch=6, fins=0.6, rod=REST_ROD, gill=0.0)
    return [
        P(face="calm", **g),
        P(face="hurt", squash=0.92, **{k: v for k, v in g.items()}),
    ]


def ko():
    """One last flop, then he lies on his side, the rod clattering down across him."""
    return [
        P(curl=-0.8, pitch=14, lift=5, rod=rod_at(3, 10, -26, 50), face="hurt"),
        P(curl=1.0, roll=60, lift=2, rod=rod_at(3, 12, -12, 120), face="ko"),
        P(curl=0.3, roll=88, rod=rod_at(-2, 6, -4, 170), face="ko", fins=0.8),
        P(curl=0.2, roll=90, squash=0.95, rod=rod_at(-3, 2.0, -2, 178, 10), face="ko", fins=0.7),
    ]


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("jab", jab()),
    ("whip", whip()),
    ("flail", flail()),
    ("splash", splash()),
    ("flopdash", flopdash()),
    ("cast", cast()),
    ("leap", leap()),
    ("dodge", dodge()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("ko", ko()),
]
# Up and down sheets: every row but the knockout, which falls over sideways in any view.
VIEW_ROWS = ROWS[:-1]


def render(pose, view):
    return Painter(pose, view).render()


def sheet(view, rows, fw, fh, origin):
    global W, H, OX, OY
    W, H = fw, fh
    OX, OY = origin
    out = Image.new("RGBA", (fw * COLS, fh * len(rows)), (0, 0, 0, 0))
    for r, (_name, poses) in enumerate(rows):
        for c, pose in enumerate(poses):
            out.alpha_composite(render(pose, view), (c * fw, r * fh))
    return out


def preview(sh, rows, fw, fh, origin, scale, path):
    label_w = 70
    prev = Image.new("RGBA", (label_w + sh.width * scale, sh.height * scale), (70, 58, 46, 255))
    big = sh.resize((sh.width * scale, sh.height * scale), Image.NEAREST)
    prev.alpha_composite(big, (label_w, 0))
    d = ImageDraw.Draw(prev)
    for r, (name, poses) in enumerate(rows):
        d.text((6, r * fh * scale + 8), "%d %s" % (r, name), fill=(240, 230, 210, 255))
        d.line([(label_w, r * fh * scale), (prev.width, r * fh * scale)], fill=(50, 40, 32, 255))
        for c in range(len(poses)):
            ox = label_w + (c * fw + origin[0]) * scale
            oy = (r * fh + origin[1]) * scale
            d.line([(ox - 6, oy), (ox + 6, oy)], fill=(30, 24, 20, 255))
    prev.save(path)
    print("wrote", os.path.relpath(path, ROOT))


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    side = sheet("side", ROWS, SIDE["w"], SIDE["h"], SIDE["origin"])
    side.save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT), side.size)
    preview(side, ROWS, SIDE["w"], SIDE["h"], SIDE["origin"], 3, PREVIEW)
    views = {}
    for view, spec in VIEWS.items():
        sh = sheet(view, VIEW_ROWS, spec["w"], spec["h"], spec["origin"])
        path = OUT.replace(".png", "_%s.png" % view)
        sh.save(path)
        print("wrote", os.path.relpath(path, ROOT), sh.size)
        views[view] = sh
    s = 2
    label_w = 70
    fw, fh = VIEWS["down"]["w"], VIEWS["down"]["h"]
    prev = Image.new("RGBA", (label_w + fw * COLS * 2 * s, fh * len(VIEW_ROWS) * s), (70, 58, 46, 255))
    d = ImageDraw.Draw(prev)
    for k, view in enumerate(("down", "up")):
        big = views[view].resize((views[view].width * s, views[view].height * s), Image.NEAREST)
        prev.alpha_composite(big, (label_w + k * fw * COLS * s, 0))
        d.text((label_w + k * fw * COLS * s + 6, 4), "facing " + view, fill=(255, 210, 120, 255))
    for r, (name, _poses) in enumerate(VIEW_ROWS):
        d.text((6, r * fh * s + 20), "%d %s" % (r, name), fill=(240, 230, 210, 255))
        d.line([(label_w, r * fh * s), (prev.width, r * fh * s)], fill=(50, 40, 32, 255))
    vp = PREVIEW.replace("_preview", "_views_preview")
    prev.save(vp)
    print("wrote", os.path.relpath(vp, ROOT))


if __name__ == "__main__":
    main()
