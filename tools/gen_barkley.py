#!/usr/bin/env python3
"""Barkley sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_barkley.py
Requires Pillow and numpy.

Writes assets/sprites/barkley.png (96x96 frames, 8 columns, the side view),
barkley_down.png and barkley_up.png (128x160 frames: facing the camera, and facing
away), plus labelled previews in docs/.

Unlike Craglash's rig (a side-view puppet with a separate front/back pass), Barkley
is posed once in 3D and projected into each view: a point is (lat, up, fwd), with
lat toward his right hand, up off the floor and fwd the way he faces. That keeps
every view in step, including Timber Twister, where the whole tree turns on its
roots, and it keeps the art honest to the hitboxes: forward reach in the pose is
forward reach on screen (in the side view, foreshortened a little by the 3/4 turn).

Parts (each shaded and outlined on its own layer, then sorted by depth):
  - a trunk that forks into two leg-trunks with splayed roots for feet
  - two long branch arms ending in twig fingers, with leaf sprouts
  - a face on the trunk (small blue eyes, a long nose) and a mossy green beard
  - the log lying across the top of his head, rings on its end, one leaf on top

This is a recreation for the soft launch; when the artist delivers final sprites in
the same layout they drop in with no code changes.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "barkley.png")
PREVIEW = os.path.join(ROOT, "docs", "barkley_preview.png")

COLS = 8
SIDE = {"w": 96, "h": 96, "origin": (40, 90)}
VIEWS = {
    "down": {"w": 128, "h": 160, "origin": (64, 112)},
    "up": {"w": 128, "h": 160, "origin": (64, 124)},
}

# Palette, sampled from the character sheet.
C = {
    "outline": (30, 16, 16, 255),
    "bark": (181, 102, 100, 255),
    "bark_l": (206, 136, 128, 255),
    "bark_d": (146, 78, 78, 255),
    "bark_dd": (119, 67, 66, 255),
    "grain": (122, 64, 64, 255),
    "wood": (128, 72, 70, 255),
    "wood_l": (160, 98, 92, 255),
    "wood_d": (98, 55, 54, 255),
    "ring": (214, 170, 140, 255),
    "ring_l": (232, 196, 164, 255),
    "ring_d": (150, 96, 80, 255),
    "moss": (26, 112, 48, 255),
    "moss_l": (52, 160, 76, 255),
    "moss_d": (14, 74, 32, 255),
    "leaf": (40, 180, 80, 255),
    "leaf_l": (150, 220, 170, 255),
    "leaf_d": (22, 120, 52, 255),
    "eye": (60, 70, 200, 255),
    "eye_hi": (170, 190, 255, 255),
    "mouth": (70, 30, 32, 255),
    "glow": (170, 255, 120, 255),
}

# ------------------------------------------------------------------ image helpers

W = H = 96
OX, OY = SIDE["origin"]


def layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def _mask(img):
    return np.array(img)[:, :, 3] > 0


def _shift(m, dx, dy):
    """Mask value at (x + dx, y + dy), False outside."""
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


def darken(img, k):
    a = np.array(img)
    m = a[:, :, 3] > 0
    a[m, :3] = (a[m, :3] * k).astype(np.uint8)
    return Image.fromarray(a)


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


def polyline(d, pts, radii, col):
    for i in range(len(pts) - 1):
        capsule(d, pts[i], pts[i + 1], radii[i], radii[i + 1], col)


def draw_pinecone(img, at):
    """A small pinecone: a brown oval with rows of darker scales."""
    x, y = round(at[0]), round(at[1])
    d = ImageDraw.Draw(img)
    d.ellipse([x - 3, y - 4, x + 3, y + 4], fill=C["outline"])
    d.ellipse([x - 2, y - 3, x + 2, y + 3], fill=(150, 96, 52, 255))
    for yy in (-2, 0, 2):
        d.line([(x - 2, yy + y), (x, yy + y + 1), (x + 2, yy + y)], fill=(96, 56, 30, 255))
    d.point((x - 1, y - 2), fill=(196, 140, 84, 255))


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


def v_lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def ik3(root, target, l1, l2, pole):
    """Two-bone joint between root and target, bending toward `pole` (a direction)."""
    d = v_sub(target, root)
    dist = max(0.01, v_len(d))
    u = v_mul(d, 1.0 / dist)
    if dist >= l1 + l2 - 0.01:
        return v_add(root, v_mul(u, l1 * dist / (l1 + l2)))
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    pp = v_sub(pole, v_mul(u, v_dot(pole, u)))
    if v_len(pp) < 1e-4:
        pp = (0.0, -1.0, 0.0)
    pp = v_norm(pp)
    return v_add(v_add(root, v_mul(u, a)), v_mul(pp, h))


class Cam:
    """Projects (lat, up, fwd) into a view.

    Side view: a cheated 3/4 view. Forward maps straight to screen right, one pixel per
    pixel, so reach on screen matches reach in the simulation; the sideways axis is
    drawn as if he were turned PSI toward the camera, so his arm span and the log across
    his head still read. Depth (what covers what, which features show) uses that turn.
    """
    PSI = math.radians(60)
    LAT_X = 0.75  # how far a point toward his right shifts left on screen
    LAT_Y = 0.22  # ... and down (nearer the camera)
    FWD_Y = 0.06

    def __init__(self, view):
        self.view = view
        # A round cross-section drawn with the side view's shear comes out this much wider.
        self.r_scale = math.sqrt(1.0 + self.LAT_X ** 2) if view == "side" else 1.0
        if view == "side":
            self.cam = (math.cos(self.PSI), 0.0, math.sin(self.PSI))
        elif view == "down":
            self.cam = (0.0, 0.0, 1.0)
        else:
            self.cam = (0.0, 0.0, -1.0)

    def P(self, p):
        lat, up, fwd = p
        if self.view == "side":
            x = fwd - lat * self.LAT_X
            y = -up + lat * self.LAT_Y + fwd * self.FWD_Y
            return (OX + x, OY + y)
        if self.view == "down":
            return (OX - lat, OY - up + self.depth_y(fwd))
        return (OX + lat, OY - up - self.depth_y(fwd))

    @staticmethod
    def depth_y(f):
        """Up/down views: how far down the screen a point `f` toward the camera sits.

        Reach is one to one, as on the floor (so a strike lands where its hitbox is),
        but the body's own roundness is flattened: otherwise the face, on the front of
        the trunk, would slide down under the arms and beard.
        """
        k, near = 0.35, 8.0
        a = abs(f)
        g = a * k if a <= near else near * k + (a - near)
        return math.copysign(g, f)

    def depth(self, p):
        return v_dot(p, self.cam)


# ------------------------------------------------------------------ pose

TRUNK_H = 34.0  # fork to the top of the head
FD = TRUNK_H - 30.0  # face features are written for a 30 px trunk; this lifts them
SHOULDER_UP = 18.0
UPPER, FORE = 17.0, 17.0  # branch arm bones
THIGH, SHIN = 10.4, 10.4  # leg trunks


class Pose:
    def __init__(self, **kw):
        self.hip = kw.get("hip", (21.0, 0.0))        # fork height and forward offset
        self.lean = kw.get("lean", 0.0)               # trunk pitch, + forward (degrees)
        self.roll = kw.get("roll", 0.0)               # trunk tilt toward his right (degrees)
        self.yaw = kw.get("yaw", 0.0)                 # whole body turn (degrees, + toward his left)
        self.tip = kw.get("tip", 0.0)                 # whole body pitch about the feet (+ forward)
        self.feet = kw.get("feet", [(-8, 0, -1), (8, 0, 1)])  # left, right (lat, up, fwd)
        self.hands = kw.get("hands", [(-9, -14, -3), (9, -14, 2)])  # from each shoulder
        self.poles = kw.get("poles", [None, None])    # elbow bend hints
        self.face = kw.get("face", "calm")
        self.glow = kw.get("glow", 0.0)               # leaves and moss lit up (Surge)
        self.bend = kw.get("bend", 0.0)               # extra pitch of the head end (+ forward)
        self.fingers = kw.get("fingers", ["open", "open"])  # "open" | "claw" | "fist"
        self.lying = kw.get("lying", False)
        self.roots_up = kw.get("roots_up", False)     # KO: the root feet tear free
        self.shift = kw.get("shift", 0.0)              # slide the whole body forward (KO: room to fall)
        self.hold = kw.get("hold", -1)                # a hand holding a pinecone (Pinecone Bomb)


def _rot_lat(p, deg):
    """Pitch about the lateral axis (positive tips the top forward)."""
    a = math.radians(deg)
    lat, up, fwd = p
    return (lat, up * math.cos(a) - fwd * math.sin(a), up * math.sin(a) + fwd * math.cos(a))


def _rot_fwd(p, deg):
    """Roll about the forward axis (positive tilts the top toward his right)."""
    a = math.radians(deg)
    lat, up, fwd = p
    return (lat * math.cos(a) + up * math.sin(a), -lat * math.sin(a) + up * math.cos(a), fwd)


def _rot_up(p, deg):
    """Turn about the vertical axis (positive turns his front toward his left)."""
    a = math.radians(deg)
    lat, up, fwd = p
    return (lat * math.cos(a) - fwd * math.sin(a), up, lat * math.sin(a) + fwd * math.cos(a))


class Body:
    """A pose turned into 3D points: where every joint is, before projection."""

    def __init__(self, pose):
        self.p = pose
        self.hip = (0.0, pose.hip[0], pose.hip[1])

    def world(self, q):
        """Applies the whole-body tip and turn to a point already in body space."""
        q = _rot_lat(q, self.p.tip)
        q = (q[0], q[1], q[2] + self.p.shift)
        return _rot_up(q, self.p.yaw)

    def T(self, v):
        """Trunk-local (lat, up from the fork, fwd) to body space, with lean and roll."""
        q = v
        if self.p.bend and v[1] > 14 + FD:
            q = v_add(_rot_lat(v_sub(v, (0, 14 + FD, 0)), self.p.bend), (0, 14 + FD, 0))
        q = _rot_lat(q, self.p.lean)
        q = _rot_fwd(q, self.p.roll)
        return v_add(self.hip, q)

    def trunk_axis(self):
        return [self.T((0, k * TRUNK_H / 6, 0)) for k in range(7)]

    TRUNK_R = [6.3, 6.3, 5.9, 5.5, 5.4, 5.8, 6.3]  # fork to head: narrowest at the neck

    def trunk_r(self, k):
        k = max(0.0, min(6.0, k))
        i = min(5, int(k))
        return self.TRUNK_R[i] + (self.TRUNK_R[i + 1] - self.TRUNK_R[i]) * (k - i)

    def shoulder(self, i):
        return self.T((-5.4 if i == 0 else 5.4, SHOULDER_UP, -0.5))

    def hand(self, i):
        sh = self.shoulder(i)
        return v_add(sh, self.p.hands[i])

    def elbow(self, i):
        out = -1.0 if i == 0 else 1.0
        pole = self.p.poles[i] or (out * 1.0, -0.6, -0.5)
        return ik3(self.shoulder(i), self.hand(i), UPPER, FORE, pole)

    def leg(self, i):
        out = -1.0 if i == 0 else 1.0
        hip = v_add(self.hip, (out * 3.4, 2.5, 0.0))
        foot = self.p.feet[i]
        ankle = v_add(foot, (0.0, 3.0, 0.0))
        knee = ik3(hip, ankle, THIGH, SHIN, (out * 0.3, 0.0, 1.0))
        return hip, knee, ankle, foot

    def face_point(self, theta, up_local, out=0.0):
        """A point on the trunk's surface: theta degrees around from the front (+ = his right)."""
        r = self.trunk_r(up_local / TRUNK_H * 6) + out
        a = math.radians(theta)
        return self.T((r * math.sin(a), up_local, r * math.cos(a)))

    def face_normal(self, theta):
        a = math.radians(theta)
        n = (math.sin(a), 0.0, math.cos(a))
        n = _rot_lat(n, self.p.lean)
        n = _rot_fwd(n, self.p.roll)
        return n


# ------------------------------------------------------------------ parts

class Painter:
    def __init__(self, pose, view):
        self.b = Body(pose)
        self.p = pose
        self.cam = Cam(view)
        self.view = view

    def P(self, q):
        return self.cam.P(self.b.world(q))

    def D(self, q):
        return self.cam.depth(self.b.world(q))

    def facing(self, n):
        """How much a body-space direction points at the camera (-1..1)."""
        return self.cam.depth(_rot_up(_rot_lat(n, self.p.tip), self.p.yaw))

    # -- legs and roots
    def leg(self, i):
        hip, knee, ankle, foot = self.b.leg(i)
        img = layer()
        d = ImageDraw.Draw(img)
        polyline(d, [self.P(hip), self.P(knee), self.P(ankle)], [5.0, 3.9, 4.1], "bark")
        # the flare where the trunk meets the ground
        disc(d, self.P(v_add(ankle, (0, -1.4, 0))), 4.6, "bark")
        img = shade(img, "bark", "bark_l", "bark_d")
        det = layer()
        dd = ImageDraw.Draw(det)
        a, b = self.P(hip), self.P(ankle)
        for off in (-2, 1):
            n = (b[1] - a[1], -(b[0] - a[0]))
            ln = math.hypot(*n) or 1.0
            n = (n[0] / ln * off, n[1] / ln * off)
            dd.line([(a[0] + n[0], a[1] + n[1] + 2), (b[0] + n[0], b[1] + n[1] - 1)], fill=C["grain"])
        img.alpha_composite(clip_to(det, img))
        img = outline(img)
        if self.facing((-1.0 if i == 0 else 1.0, 0, 0)) < -0.3:
            img = darken(img, 0.84)
        return img

    def roots(self, i):
        """Root toes fanned out on the floor around the foot."""
        _hip, _knee, ankle, foot = self.b.leg(i)
        out = -1.0 if i == 0 else 1.0
        img = layer()
        d = ImageDraw.Draw(img)
        base = (foot[0], 0.5, foot[2])
        if self.p.roots_up:
            base = v_add(ankle, (0, -2, 0))
        for k, (ang, ln) in enumerate([(-80, 8.0), (-45, 10.0), (-12, 11.5), (20, 10.5), (55, 9.0), (95, 7.0),
                                       (160, 6.0)]):
            a = math.radians(ang)
            dx, dz = math.sin(a) * out, math.cos(a)
            if self.p.roots_up:
                tip = v_add(base, (dx * ln * 0.7, -ln * 0.6, dz * ln * 0.7))
                mid = v_add(base, (dx * ln * 0.4, -ln * 0.2, dz * ln * 0.4))
            else:
                tip = (base[0] + dx * ln, 0.0, base[2] + dz * ln)
                mid = (base[0] + dx * ln * 0.55 + dz * 0.8, 0.6, base[2] + dz * ln * 0.55 - dx * 0.8)
            polyline(d, [self.P(base), self.P(mid), self.P(tip)], [2.6, 1.4, 0.5], "bark")
        img = shade(img, "bark", "bark_l", "bark_dd")
        return outline(img)

    # -- trunk, face and beard
    def _leg_shape(self, d, i):
        hip, knee, ankle, _foot = self.b.leg(i)
        polyline(d, [self.P(hip), self.P(knee), self.P(ankle)], [5.0, 3.9, 4.1], "bark")
        disc(d, self.P(v_add(ankle, (0, -1.4, 0))), 4.6, "bark")

    def trunk(self):
        """Trunk and both legs as one silhouette, so the trunk forks smoothly into legs."""
        img = layer()
        d = ImageDraw.Draw(img)
        for i in (0, 1):
            self._leg_shape(d, i)
        axis = [self.b.T((0, 2.0, 0))] + self.b.trunk_axis()[1:]
        pts = [self.P(q) for q in axis]
        polyline(d, pts, [self.b.trunk_r(k) * self.cam.r_scale for k in range(7)], "bark")
        # stubby side twigs and dangling root hairs, as on the sheet
        for (lat, up, fwd, dl, du) in [(6.0, 9.0, 1.0, 3.5, -3.0), (-6.0, 13.0, 0.5, -3.0, 2.5)]:
            a = self.b.T((lat, up, fwd))
            b = self.b.T((lat + dl, up + du, fwd))
            capsule(d, self.P(a), self.P(b), 1.4, 0.8, "bark")
        img = shade(img, "bark", "bark_l", "bark_d")
        det = layer()
        dd = ImageDraw.Draw(det)
        # grain down each leg, and a crease where the nearer leg passes over the other
        near = max((0, 1), key=lambda i: self.D(self.b.leg(i)[2]))
        for i in (0, 1):
            hip, knee, ankle, _f = self.b.leg(i)
            a, b = self.P(v_add(hip, (0, -3, 0))), self.P(ankle)
            n = (b[1] - a[1], -(b[0] - a[0]))
            ln = math.hypot(*n) or 1.0
            for off in (-2, 1):
                o = (n[0] / ln * off, n[1] / ln * off)
                dd.line([(a[0] + o[0], a[1] + o[1]), (b[0] + o[0], b[1] + o[1] - 1)], fill=C["grain"])
        nl = layer()
        self._leg_shape(ImageDraw.Draw(nl), near)
        m = _mask(nl)
        ring = (_shift(m, 1, 0) | _shift(m, -1, 0) | _shift(m, 0, 1)) & ~m
        fork_y = self.P(self.b.hip)[1] - 1
        ys = np.arange(m.shape[0])[:, None] >= fork_y
        da = np.array(det)
        da[ring & ys] = C["bark_dd"]
        det = Image.fromarray(da)
        # bark grain: wavy lines running up the trunk, following its turn
        for theta in (-75, -50, -25, 0, 25, 50, 75, 110, 150, 200, 250):
            n = self.facing(self.b.face_normal(theta))
            if n < 0.05:
                continue
            line = []
            for k in range(0, 11):
                up = 1.5 + k * 3.2
                if 16.5 + FD < up < 27.5 + FD and abs(theta) < 50 and self.p.face != "back":
                    continue  # leave the face clean
                wob = math.sin(k * 1.7 + theta) * 6
                line.append(self.P(self.b.face_point(theta + wob, up, out=-0.5)))
            if len(line) > 1:
                dd.line(line, fill=C["grain"])
        # chevrons where the trunk splits, as on the sheet
        if self.facing(self.b.face_normal(0)) > 0.0:
            for th in (-30, 30):
                a = self.P(self.b.face_point(th * 0.4, 2.0 + FD))
                b = self.P(self.b.face_point(th, 5.0 + FD))
                dd.line([a, b], fill=C["bark_dd"])
        self._face(dd)
        self._nose(img)
        if self.p.glow > 0:
            for th, up in ((-40, 6), (30, 13), (-10, 3), (60, 18)):
                if self.facing(self.b.face_normal(th)) > 0:
                    dd.point(self.P(self.b.face_point(th, up)), fill=C["glow"])
        img.alpha_composite(clip_to(det, img))
        return outline(img)

    def _face(self, dd):
        f = self.p.face
        o = C["outline"]
        for th in (-26, 26):
            if self.facing(self.b.face_normal(th)) < -0.02:
                continue
            e = self.P(self.b.face_point(th, 25.0 + FD))
            e = (round(e[0]), round(e[1]))
            if f == "ko":
                dd.line([(e[0] - 1, e[1] - 1), (e[0] + 1, e[1] + 1)], fill=o)
                dd.line([(e[0] - 1, e[1] + 1), (e[0] + 1, e[1] - 1)], fill=o)
            elif f in ("hurt", "grit"):
                dd.line([(e[0] - 1, e[1]), (e[0] + 1, e[1])], fill=o)
            else:
                dd.line([(e[0] - 1, e[1] - 1), (e[0] + 1, e[1] - 1)], fill=o)
                dd.point(e, fill=C["eye"])
                dd.point((e[0] - 1 if th > 0 else e[0] + 1, e[1]), fill=C["bark_dd"])
                if f == "shout":
                    dd.point((e[0], e[1] + 1), fill=C["eye"])
            # heavy old brow lines
            b0 = self.P(self.b.face_point(th * 1.35, 27.3 + FD))
            b1 = self.P(self.b.face_point(th * 0.55, (26.6 if f != "shout" else 27.6) + FD))
            dd.line([b0, b1], fill=C["bark_dd"])
        # wrinkles around the eyes
        for th in (-38, 38):
            if self.facing(self.b.face_normal(th)) > 0.1:
                a = self.P(self.b.face_point(th, 23.0 + FD))
                b = self.P(self.b.face_point(th * 1.2, 21.5 + FD))
                dd.line([a, b], fill=C["grain"])
        if f in ("shout", "hurt") and self.facing(self.b.face_normal(0)) > 0.0:
            m = self.P(self.b.face_point(0, 18.0 + FD))
            dd.rectangle([m[0] - 1, m[1] - 1, m[0] + 1, m[1] + 1], fill=C["mouth"])

    def _nose(self, img):
        """A long wooden nose sticking out of the face (drawn last, over the trunk)."""
        if self.facing(self.b.face_normal(0)) < -0.3:
            return
        root_hi = self.P(self.b.face_point(0, 25.5 + FD, out=-0.5))
        root_l = self.P(self.b.face_point(-14, 21.2 + FD, out=-0.2))
        root_r = self.P(self.b.face_point(14, 21.2 + FD, out=-0.2))
        tip = self.P(self.b.face_point(0, 21.0 + FD, out=5.5))
        lay = layer()
        d = ImageDraw.Draw(lay)
        d.polygon([root_hi, root_l, tip, root_r], fill=C["bark"])
        lay = outline(shade(lay, "bark", "bark_l", "bark_dd"))
        img.alpha_composite(lay)

    def beard(self):
        """The moss beard: a scribbly clump hanging under the nose."""
        img = layer()
        d = ImageDraw.Draw(img)
        blobs = [(-62, 16.6, 1.7), (-36, 17.6, 1.9), (-12, 17.9, 1.9), (12, 17.9, 1.9), (36, 17.6, 1.9),
                 (62, 16.6, 1.7), (-50, 14.6, 1.8), (-24, 14.8, 2.1), (0, 15.0, 2.1), (24, 14.8, 2.1),
                 (50, 14.6, 1.8), (-34, 12.4, 1.6), (-10, 12.2, 1.9), (14, 12.4, 1.8), (36, 12.6, 1.4),
                 (2, 10.2, 1.4)]
        drawn = 0
        for th, up, r in blobs:
            up += FD - 2.2
            if self.facing(self.b.face_normal(th)) < -0.15:
                continue
            disc(d, self.P(self.b.face_point(th, up, out=0.8)), r, "moss")
            drawn += 1
        if drawn == 0:
            return None
        img = shade(img, "moss", "moss_l", "moss_d")
        det = layer()
        dd = ImageDraw.Draw(det)
        # scribbled curls of lighter moss
        for th, up in ((-30, 15 + FD), (-5, 14 + FD), (20, 16 + FD), (5, 10 + FD), (-18, 12 + FD), (34, 13 + FD)):
            if self.facing(self.b.face_normal(th)) < 0:
                continue
            c = self.P(self.b.face_point(th, up, out=1.6))
            dd.point((round(c[0]), round(c[1])), fill=C["glow"] if self.p.glow > 0.5 else C["moss_l"])
            dd.point((round(c[0]) + 1, round(c[1]) + 1), fill=C["moss_d"])
        img.alpha_composite(clip_to(det, img))
        return outline(img)

    # -- branch arms
    def arm_points(self, i):
        sh, el, hd = self.b.shoulder(i), self.b.elbow(i), self.b.hand(i)
        # a slight kink in each bone, like a real branch
        out = -1.0 if i == 0 else 1.0
        k1 = v_add(v_lerp(sh, el, 0.55), (out * 0.8, 0.8, 0.0))
        k2 = v_add(v_lerp(el, hd, 0.5), (0.0, -0.8, 0.0))
        pts = [sh, k1, el, k2, hd]
        return pts

    def arm(self, i):
        pts = self.arm_points(i)
        cut = None
        # a hand plunged into the ground stops at the surface (Root Eruption)
        for k in range(1, len(pts)):
            if pts[k][1] < 0.0 <= pts[k - 1][1]:
                t = pts[k - 1][1] / (pts[k - 1][1] - pts[k][1])
                pts = pts[:k] + [v_lerp(pts[k - 1], pts[k], t)]
                cut = pts[-1]
                break
        img = layer()
        d = ImageDraw.Draw(img)
        radii = [2.7, 2.2, 2.0, 1.7, 1.4][:len(pts)]
        polyline(d, [self.P(q) for q in pts], radii, "wood")
        hd = pts[-1]
        if cut is None:
            self._fingers(d, i, pts)
        # side twigs with leaves
        twigs = []
        for k, (t, du, dl) in enumerate(((0.45, 3.5, 1.5), (0.78, -3.0, 1.0))):
            seg = int(t * (len(pts) - 1))
            a = v_lerp(pts[seg], pts[min(seg + 1, len(pts) - 1)], t * (len(pts) - 1) - seg)
            b = v_add(a, (dl * (-1 if i == 0 else 1), du, 0.5))
            capsule(d, self.P(a), self.P(b), 1.0, 0.6, "wood")
            twigs.append(b)
        img = shade(img, "wood", "wood_l", "wood_d")
        det = layer()
        dd = ImageDraw.Draw(det)
        p2 = [self.P(q) for q in pts]
        for k in range(len(p2) - 1):
            a, b = p2[k], p2[k + 1]
            dd.line([(a[0], a[1] + 1), (b[0], b[1] + 1)], fill=C["wood_d"])
        img.alpha_composite(clip_to(det, img))
        img = outline(img)
        lv = ImageDraw.Draw(img)
        for b in twigs:
            q = self.P(b)
            self._leaf(lv, q)
        if self.p.hold == i and cut is None:
            draw_pinecone(img, self.P(v_add(hd, (0, 1.5, 0))))
        if cut is not None:
            g = self.P((cut[0], 0.0, cut[2]))
            lv.ellipse([g[0] - 4, g[1] - 1, g[0] + 4, g[1] + 2], fill=C["outline"])
            lv.ellipse([g[0] - 3, g[1] - 1, g[0] + 3, g[1] + 1], fill=C["bark_dd"])
        if self.facing((-1.0 if i == 0 else 1.0, 0, 0)) < -0.3:
            img = darken(img, 0.86)
        return img

    def _fingers(self, d, i, pts):
        hd = pts[-1]
        u = v_norm(v_sub(hd, pts[-2]))
        style = self.p.fingers[i]
        side = (-u[2], 0.0, u[0]) if abs(u[1]) < 0.9 else (1.0, 0.0, 0.0)
        up = (0.0, 1.0, 0.0)
        if style == "fist":
            disc(d, self.P(hd), 2.6, "wood")
            return
        spread = 0.9 if style == "open" else 0.45
        curl = 0.0 if style == "open" else 0.6
        for k, (s, w) in enumerate(((-1.0, 0.0), (0.0, 0.0), (1.0, 0.0), (0.0, 1.0))):
            if k == 3:  # thumb
                dirv = v_norm(v_add(v_mul(u, 0.5), v_mul(up, 0.9)))
                ln = 4.5
            else:
                dirv = v_norm(v_add(u, v_add(v_mul(side, s * spread), v_mul(up, -0.25 * abs(s)))))
                ln = 7.5 if k == 1 else 6.5
            mid = v_add(hd, v_mul(dirv, ln * 0.55))
            tip = v_add(mid, v_mul(v_norm(v_add(dirv, v_mul(up, -curl))), ln * 0.5))
            polyline(d, [self.P(hd), self.P(mid), self.P(tip)], [1.1, 0.8, 0.4], "wood")

    def _leaf(self, dd, q):
        x, y = round(q[0]), round(q[1])
        dd.rectangle([x - 1, y - 2, x + 1, y], fill=C["outline"])
        dd.point((x, y - 3), fill=C["outline"])
        dd.point((x - 2, y - 1), fill=C["outline"])
        dd.point((x, y - 2), fill=C["leaf"])
        dd.point((x - 1, y - 1), fill=C["leaf"])
        dd.point((x, y - 1), fill=C["glow"] if self.p.glow > 0.5 else C["leaf_l"])

    # -- the log on his head
    def log(self):
        top = self.b.T((0.0, TRUNK_H + 3.2, 0.3))
        ax = v_sub(self.b.T((1.0, TRUNK_H + 3.2, 0.3)), self.b.T((0.0, TRUNK_H + 3.2, 0.3)))
        ax = v_norm(ax)
        # the drawing's log sits off-centre: it sticks out further over his left side
        e0 = v_add(top, v_mul(ax, -17.0))
        e1 = v_add(top, v_mul(ax, 12.0))
        R = 4.4
        p0, p1 = self.P(e0), self.P(e1)
        img = layer()
        d = ImageDraw.Draw(img)
        capsule(d, p0, p1, R, R, "wood")
        img = shade(img, "wood", "wood_l", "wood_d")
        det = layer()
        dd = ImageDraw.Draw(det)
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        for off, a0, a1 in ((-1.8, 0.1, 0.8), (0.6, 0.25, 0.95), (2.2, 0.05, 0.55)):
            dd.line([(p0[0] + dx * a0 + nx * off, p0[1] + dy * a0 + ny * off),
                     (p0[0] + dx * a1 + nx * off, p0[1] + dy * a1 + ny * off)], fill=C["wood_d"])
        img.alpha_composite(clip_to(det, img))
        # the cut end with its rings faces whichever way is toward the camera
        ends = [(e0, -1.0), (e1, 1.0)]
        end, sgn = max(ends, key=lambda t: self.facing(v_mul(ax, t[1])))
        face_amt = self.facing(v_mul(ax, sgn))
        if face_amt > 0.15:
            c = self.P(end)
            rx = max(1.6, R * min(1.0, face_amt * 1.3))
            cd = ImageDraw.Draw(img)
            # an ellipse squashed along the log's screen direction
            ang = math.degrees(math.atan2(dy, dx))
            cap = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
            cdd = ImageDraw.Draw(cap)
            cdd.ellipse([20 - rx, 20 - R, 20 + rx, 20 + R], fill=C["ring"])
            if rx > 2.5:
                cdd.ellipse([20 - rx * 0.55, 20 - R * 0.55, 20 + rx * 0.55, 20 + R * 0.55], outline=C["ring_d"])
                cdd.point((20, 20), fill=C["ring_d"])
            cap = cap.rotate(-ang, resample=Image.NEAREST, center=(20, 20))
            img.alpha_composite(cap, (round(c[0]) - 20, round(c[1]) - 20))
            del cd
        img = outline(img)
        # the leaf sprouting from the top of the log
        mid = self.P(v_add(v_lerp(e0, e1, 0.42), self.b.T((0, 5.6, 0)) if False else (0, 0, 0)))
        lv = ImageDraw.Draw(img)
        sx, sy = round(mid[0]), round(mid[1] - R)
        lv.line([(sx, sy), (sx, sy - 2)], fill=C["outline"])
        lv.ellipse([sx - 2, sy - 7, sx + 2, sy - 2], fill=C["outline"])
        lv.ellipse([sx - 1, sy - 6, sx + 1, sy - 3], fill=C["leaf"])
        lv.point((sx, sy - 5), fill=C["glow"] if self.p.glow > 0.5 else C["leaf_l"])
        return img

    # -- assemble
    def render(self):
        parts = []  # (depth, order, image)
        hipd = self.D(self.b.hip)
        for i in (0, 1):
            hip, knee, ankle, foot = self.b.leg(i)
        trunk_d = self.D(self.b.T((0, 15, 0)))
        for i in (0, 1):
            hip, knee, ankle, foot = self.b.leg(i)
            dep = trunk_d - 3.0 + self.D(v_lerp(hip, foot, 0.5)) * 0.05
            parts.append((dep, 0, self.roots(i)))
        parts.append((trunk_d, 2, self.trunk()))
        bd = self.facing(self.b.face_normal(0))
        beard = self.beard()
        if beard is not None:
            parts.append((trunk_d + (2.5 if bd > -0.3 else -8.0), 6, beard))
        for i in (0, 1):
            pts = self.arm_points(i)
            sh_d = self.D(pts[0])
            reach = self.D(pts[-1]) - sh_d
            dep = sh_d + (reach * 0.7 + 1.0 if reach > 3 else 0.0)
            parts.append((dep, 4, self.arm(i)))
        parts.append((trunk_d + 6.0, 5, self.log()))  # it sits on top of the head
        img = layer()
        for _d, _o, lay in sorted(parts, key=lambda t: (t[0], t[1])):
            img.alpha_composite(lay)
        return img


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


def idle():
    """The sheet's pose: one arm hanging low, the other raised in a curl. A slow sway."""
    out = []
    for k in range(4):
        s = [0, 1, 1, 0][k]
        out.append(P(hip=(21 - s * 0.6, 0), lean=2 + s,
                     hands=[(-12, -15 + s, -5), (13 + s * 0.5, 4 + s, 5)],
                     poles=[(-1, -0.4, -0.3), (1, -1.0, 0.2)],
                     feet=[(-9, 0, -2), (9, 0, 2)]))
    return out


def run():
    """A lumbering stride: root feet planted and dragged, arms swinging like boughs."""
    out = []
    for k in range(6):
        ph = k / 6 * 2 * math.pi
        fz = 7 * math.cos(ph)
        lift_r = max(0.0, math.sin(ph)) * 3
        lift_l = max(0.0, -math.sin(ph)) * 3
        bob = abs(math.sin(ph)) * 1.2
        sw = 6 * math.cos(ph)
        out.append(P(hip=(21 - bob, 1), lean=8, roll=2 * math.cos(ph),
                     feet=[(-6, lift_l, -fz), (6, lift_r, fz)],
                     hands=[(-8, -15, 2 + sw), (8, -15, 2 - sw)],
                     face="calm"))
    return out


def twig():
    """Light 1, Twig Swipe: the right arm whips across in front."""
    return [
        P(lean=-4, yaw=10, hands=[(-11, -13, -4), (10, 8, -6)], poles=[None, (1, 0.3, -1)], face="grit"),
        P(lean=8, yaw=-14, hands=[(-11, -13, -4), (-2, -12, 26)], poles=[None, (1, 0.6, 0)], face="shout",
          feet=[(-7, 0, -3), (7, 0, 4)]),
        P(lean=10, yaw=-22, hands=[(-11, -13, -4), (-10, -13, 20)], poles=[None, (1, 0.6, 0)], face="shout",
          feet=[(-7, 0, -3), (7, 0, 4)]),
        P(lean=4, yaw=-6, hands=[(-11, -14, -4), (6, -12, 8)], face="calm"),
    ]


def bough():
    """Light 2, Bough Swing: the left arm swings back around the other way."""
    return [
        P(lean=-2, yaw=-18, hands=[(-12, 6, -8), (8, -14, 4)], poles=[(-1, 0.3, -1), None], face="grit"),
        P(lean=8, yaw=16, hands=[(4, -12, 26), (8, -14, -2)], poles=[(-1, 0.6, 0), None], face="shout",
          feet=[(-7, 0, -3), (7, 0, 4)]),
        P(lean=10, yaw=22, hands=[(12, -13, 18), (8, -15, -2)], poles=[(-1, 0.6, 0), None], face="shout",
          feet=[(-7, 0, -3), (7, 0, 4)]),
        P(lean=4, yaw=6, hands=[(-7, -14, 6), (8, -14, 2)], face="calm"),
    ]


def logdrop():
    """Light 3, Log Drop: rear back, then tip the whole top forward and bonk with the log."""
    return [
        P(lean=-14, hip=(22, -1), hands=[(-10, 4, -6), (10, 4, -6)], poles=[(-1, 0.4, -1), (1, 0.4, -1)],
          face="grit"),
        P(lean=38, bend=18, hip=(19, 2), hands=[(-10, -12, 10), (10, -12, 10)], face="shout",
          feet=[(-7, 0, -3), (7, 0, 5)]),
        P(lean=44, bend=22, hip=(18, 2), hands=[(-11, -12, 12), (11, -12, 12)], face="shout",
          feet=[(-7, 0, -3), (7, 0, 5)]),
        P(lean=12, hip=(20, 1), hands=[(-11, -14, 0), (11, -14, 2)], face="calm"),
    ]


SPIN_HANDS = [(-27, -2, 2), (27, -2, -2)]


def twister():
    """Heavy, Timber Twister: coil, then spin on the roots with both arms flung out."""
    out = [
        P(yaw=40, lean=-4, hands=[(-8, -10, 8), (6, -10, -10)], fingers=["fist", "fist"], face="grit"),
        P(yaw=55, lean=-6, hands=[(-7, -9, 10), (5, -9, -11)], fingers=["fist", "fist"], face="grit", hip=(20, 0)),
    ]
    for k, yaw in enumerate((0, -90, -180, -270)):
        out.append(P(yaw=yaw, lean=4, hands=SPIN_HANDS, face="shout", poles=[(0, 1, 0), (0, 1, 0)],
                     feet=[(-7, 0, 0), (7, 0, 0)]))
    out.append(P(yaw=-20, lean=6, hands=[(-24, -6, 6), (24, -6, 4)], face="shout", poles=[(0, 1, 0), (0, 1, 0)]))
    out.append(P(yaw=0, lean=3, hands=[(-12, -14, -2), (12, -14, 2)], face="calm"))
    return out


def grab():
    """Skill 1, Branch Grab: the right arm shoots out long, snags, and reels back in."""
    def far(ext, face="shout", hand_up=-15):
        return P(lean=10, yaw=-10, hands=[(-11, -12, -6), (-3, hand_up, ext)], poles=[None, (1, 0.5, 0)],
                 face=face, feet=[(-7, 0, -4), (7, 0, 4)], fingers=["open", "claw"])
    return [
        P(lean=-8, yaw=20, hands=[(-10, -12, 2), (6, 2, -14)], poles=[None, (1, 0.2, -1)], face="grit"),
        far(16, "grit", -6),
        far(33),
        far(35),
        P(lean=4, yaw=-6, hands=[(-11, -12, -4), (-3, -12, 18)], fingers=["open", "fist"], face="grit",
          poles=[None, (1, 0.4, 0)]),
        P(lean=0, hands=[(-11, -14, -3), (9, -12, 4)], face="calm"),
    ]


def pinecone():
    """Skill 2, Pinecone Bomb: reach up overhead and lob it in an arc."""
    return [
        P(lean=-6, hands=[(-11, -12, -2), (4, 4, -6)], fingers=["open", "fist"], face="grit", hold=1),
        P(lean=-14, hands=[(-11, -10, -2), (-1, 12, -10)], fingers=["open", "fist"], face="grit",
          poles=[None, (1, -0.2, -1)], hold=1),
        P(lean=10, hands=[(-11, -12, -2), (0, 10, 14)], fingers=["open", "open"], face="shout", hold=1,
          poles=[None, (1, 0.2, -0.5)], feet=[(-7, 0, -3), (7, 0, 3)]),
        P(lean=12, hands=[(-11, -12, -2), (0, -4, 18)], fingers=["open", "open"], face="shout",
          feet=[(-7, 0, -3), (7, 0, 3)]),
        P(lean=3, hands=[(-11, -14, -3), (9, -13, 4)], face="calm"),
    ]


def eruption():
    """Surge, Root Eruption: raise both arms high, then plunge them into the ground."""
    return [
        P(lean=-6, hands=[(-14, 6, -2), (14, 6, -2)], poles=[(-1, -0.2, -0.5), (1, -0.2, -0.5)], face="shout",
          glow=0.3),
        P(lean=-10, hip=(22, -1), hands=[(-8, 14, -3), (8, 14, -3)], poles=[(-1, 0, -1), (1, 0, -1)], face="shout",
          glow=1.0),
        P(lean=-12, hip=(23, -1), hands=[(-6, 15, -4), (6, 15, -4)], poles=[(-1, 0, -1), (1, 0, -1)], face="shout",
          glow=1.0),
        P(lean=34, hip=(15, 2), hands=[(-9, -24, 12), (9, -24, 12)], poles=[(-1, 0.4, -0.5), (1, 0.4, -0.5)],
          face="shout", glow=1.0, feet=[(-8, 0, -2), (8, 0, -2)]),
        P(lean=30, hip=(15, 2), hands=[(-10, -25, 11), (10, -25, 11)], poles=[(-1, 0.4, -0.5), (1, 0.4, -0.5)],
          face="grit", glow=0.6, feet=[(-8, 0, -2), (8, 0, -2)]),
        P(lean=6, hands=[(-12, -13, 0), (12, -13, 0)], face="calm"),
    ]


def dodge():
    """A crouch-and-lurch: the trunk bows low under the swing."""
    return [
        P(lean=26, hip=(17, 0), hands=[(-8, -10, 6), (8, -10, 6)], face="grit"),
        P(lean=40, hip=(14, 1), bend=12, hands=[(-7, -8, 8), (7, -8, 8)], face="grit",
          feet=[(-6, 0, -6), (6, 2, 4)]),
        P(lean=40, hip=(14, 1), bend=12, hands=[(-7, -8, 8), (7, -8, 8)], face="grit",
          feet=[(-6, 2, -2), (6, 0, 7)]),
        P(lean=10, hip=(20, 0), hands=[(-11, -13, -1), (11, -13, 1)], face="calm"),
    ]


def hurt():
    return [
        P(lean=-16, hip=(21, -1), hands=[(-13, -4, -8), (12, 0, -6)], face="hurt"),
        P(lean=22, hip=(18, 1), roll=6, hands=[(-9, -14, 4), (8, -15, 6)], face="hurt"),
    ]


def guard():
    g = dict(lean=6, hip=(20, 0), fingers=["fist", "fist"], face="grit")
    return [
        P(hands=[(5, -2, 10), (-5, -6, 10)], poles=[(-1, -0.4, 0.4), (1, -0.4, 0.4)], **g),
        P(hands=[(5, -3, 9), (-5, -7, 9)], poles=[(-1, -0.4, 0.4), (1, -0.4, 0.4)], **{**g, "lean": 2,
                                                                                        "face": "hurt"}),
    ]


def ko():
    """Timber! He topples over backward like a felled tree and his roots tear free."""
    return [
        P(lean=-14, hands=[(-14, 2, -6), (14, 4, -6)], face="hurt"),
        P(tip=-35, lean=-6, hands=[(-14, 6, -4), (13, 8, -4)], face="ko", feet=[(-6, 0, -1), (6, 1, 1)], shift=6),
        P(tip=-70, lean=-4, hands=[(-15, 4, -2), (14, 6, -2)], face="ko", roots_up=True, shift=16),
        P(tip=-88, shift=24, hip=(20, 1), hands=[(-16, -2, 2), (15, -1, 2)], face="ko", roots_up=True),
    ]


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("twig", twig()),
    ("bough", bough()),
    ("logdrop", logdrop()),
    ("twister", twister()),
    ("grab", grab()),
    ("pinecone", pinecone()),
    ("eruption", eruption()),
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


def preview(sh, rows, fw, fh, origin, scale, path, title=None):
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
    if title:
        d.text((label_w + 6, 2), title, fill=(255, 210, 120, 255))
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
    # 2x preview: each animation's frames facing down, then facing up.
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
