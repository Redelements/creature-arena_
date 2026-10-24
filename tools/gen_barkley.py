#!/usr/bin/env python3
"""Barkley sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_barkley.py
Requires Pillow and numpy.

Writes assets/sprites/barkley.png (96x96 frames, 12 columns, the side view),
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
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "barkley.png")
PREVIEW = os.path.join(ROOT, "docs", "barkley_preview.png")

COLS = 12
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
        # The animation pass (docs/anim_preview/barkley_motion_plan.md): secondary motion that
        # draws nothing different at its defaults, so ROWS render as they always did.
        self.leaf = kw.get("leaf", 0.0)               # the leaf on his log leans this many px sideways
        self.twig = kw.get("twig", 0.0)               # the arms' side twigs lift (+) or trail (-) this many px


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
            du += self.p.twig
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
        lx = sx + round(self.p.leaf)  # the leaf's lean (animation pass); 0 draws the original
        lv.line([(sx, sy), (lx, sy - 2)], fill=C["outline"])
        lv.ellipse([lx - 2, sy - 7, lx + 2, sy - 2], fill=C["outline"])
        lv.ellipse([lx - 1, sy - 6, lx + 1, sy - 3], fill=C["leaf"])
        lv.point((lx, sy - 5), fill=C["glow"] if self.p.glow > 0.5 else C["leaf_l"])
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


# ------------------------------------------------------------------ the animation pass
# Barkley's motion pass (docs/anim_preview/barkley_motion_plan.md): every ability redrawn,
# 12 columns. He is wood, so the trunk never squashes; weight is timing (slow rises, fast
# falls, long holds) and the boughs, twigs and the log's leaf lag the trunk. ROWS below are
# these poses (the old 8-column rows are gone); `python3 tools/gen_barkley.py anim` previews
# them against the sheets at OLD_REF, and NEW_AT is what barkley.json carries.

import copy  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import splat3d as S  # noqa: E402  (only its animation tools: tween, cycle, lag, lag_at)

# hands are arcs (they swing on curves); `hold` is an index, never blended
tw = S.tweener(arc_fields=("hands",), snap=("hold",))
U8 = S.EASE_8


def Q(**kw):
    return Pose(**kw)


def mirror(p):
    """The same pose from his other side (the left arm leads)."""
    m = copy.copy(p)
    m.hands = [(-p.hands[1][0], p.hands[1][1], p.hands[1][2]), (-p.hands[0][0], p.hands[0][1], p.hands[0][2])]
    m.feet = [(-p.feet[1][0], p.feet[1][1], p.feet[1][2]), (-p.feet[0][0], p.feet[0][1], p.feet[0][2])]
    pl = [None if q is None else (-q[0], q[1], q[2]) for q in p.poles]
    m.poles = [pl[1], pl[0]]
    m.fingers = [p.fingers[1], p.fingers[0]]
    m.yaw, m.roll = -p.yaw, -p.roll
    m.hold = {-1: -1, 0: 1, 1: 0}[p.hold]
    return m


def idle_new():
    """8 frames, 10 ticks each (80: slower than anyone). The trunk sways on eased spacing and
    sinks a little at the bottom of the breath; the raised bough drifts 2 frames behind the
    trunk, the log's leaf 3; the arm twigs 2. One slow blink."""
    a = Q(hip=(21.0, 0), lean=1.0, roll=-1.2, hands=[(-12, -15, -5), (13, 4, 5)],
          poles=[(-1, -0.4, -0.3), (1, -1.0, 0.2)], feet=[(-9, 0, -2), (9, 0, 2)])
    b = Q(hip=(20.3, 0), lean=4.2, roll=1.2, hands=[(-12.5, -15.5, -4.5), (13.5, 6.0, 6)],
          poles=[(-1, -0.4, -0.3), (1, -1.0, 0.2)], feet=[(-9, 0, -2), (9, 0, 2)])
    fr = S.cycle((a, b), U8, tw)
    S.lag(fr, ("hands", "poles"), 2)
    sway = [2.0 * u - 1.0 for u in U8]
    for i, p in enumerate(fr):
        p.leaf = 1.4 * sway[(i - 3) % 8]
        p.twig = 1.2 * sway[(i - 2) % 8]
    fr[6].face = "grit"  # the blink
    return fr


# The lumber, one foot's 12-frame cycle (the other foot is 6 frames later). Stance frames 0-6
# slide the foot back evenly (fwd 8 -> -8: the planted foot rides the ground); then a slow lift
# (7, 8), a fast swing through (9), the reach (10, 11) and a hard plant (0).
FOOT_FWD = [8.0, 5.33, 2.67, 0.0, -2.67, -5.33, -8.0, -8.0, -6.5, -1.5, 5.0, 8.2]
FOOT_UP = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 2.6, 3.4, 2.4, 0.8]
# the trunk over each step (6 frames): falls hard onto the plant, settles for 2, rises slowly
HIP_DY = [-0.9, -1.5, -1.0, -0.3, 0.4, 0.5]
LEAN_DY = [2.0, 1.4, 0.6, -0.4, -1.0, -0.2]


def run_new():
    out = []
    for i in range(12):
        k = i % 6
        fr_, fl_ = FOOT_FWD[i % 12], FOOT_FWD[(i + 6) % 12]
        up_r, up_l = FOOT_UP[i % 12], FOOT_UP[(i + 6) % 12]
        c = math.cos(math.pi * i / 6)             # +1 when the right foot is furthest forward
        out.append(Q(hip=(21 + HIP_DY[k], 1), lean=8 + LEAN_DY[k], roll=2.0 * c,
                     feet=[(-6, up_l, fl_), (6, up_r, fr_)],
                     hands=[(-8, -15, 2 + 6 * c), (8, -15, 2 - 6 * c)],
                     poles=[(-1, -0.6 + 0.9 * max(0.0, c), -0.5), (1, -0.6 + 0.9 * max(0.0, -c), -0.5)]))
    # the boughs swing 2 frames behind the trunk, bending at the top of the swing; twigs 3
    S.lag(out, ("hands", "poles"), 2)
    for i, p in enumerate(out):
        p.twig = 1.6 * math.cos(math.pi * (i - 3) / 6)
        p.leaf = HIP_DY[(i - 3) % 6]
    return out


# ---- the light string. The frame data is short (Twig Swipe starts up in 4 ticks), so the
# anticipation is quick and the weight is in the hold on the hit and the long follow-through.

def twig_new():
    """Twig Swipe, 8 frames. Timeline (anim_at): 0 -> t0, 1 -> t2 (coil), 2 -> t4 (one fast
    frame), 3 -> t5 (the hit, held 3), 4 -> t8, 5 -> t10, 6 -> t12, 7 -> t14."""
    fw = dict(feet=[(-7, 0, -3), (7, 0, 4)])
    fr = [
        Q(lean=-1, yaw=4, hip=(21.3, 0), hands=[(-11, -14, -4), (10, 2, -3)], poles=[None, (1, 0.3, -1)], face="grit"),
        Q(lean=-5, yaw=14, hip=(21.6, 0), hands=[(-11, -13, -4), (11, 9, -8)], poles=[None, (1, 0.4, -1)],
          face="grit", fingers=["open", "claw"]),
        Q(lean=4, yaw=-3, hip=(20.4, 0), hands=[(-11, -13, -4), (5, -3, 14)], poles=[None, (1, 0.6, -0.5)],
          face="shout", feet=[(-7, 0, -2), (7, 0, 2)]),
        Q(lean=8, yaw=-14, hip=(19.8, 0), hands=[(-11, -13, -4), (-2, -12, 26)], poles=[None, (1, 0.6, 0)],
          face="shout", **fw),
        Q(lean=10, yaw=-22, hip=(19.8, 0), hands=[(-11, -13, -4), (-10, -13, 21)], poles=[None, (1, 0.9, 0)],
          face="shout", **fw),
        Q(lean=10, yaw=-24, hip=(20, 0), hands=[(-11, -14, -4), (-15, -12, 13)], poles=[None, (1, 1.2, 0)],
          face="shout", **fw),
        Q(lean=7, yaw=-14, hip=(20.4, 0), hands=[(-11, -14, -4), (-6, -13, 6)], poles=[None, (1, 0.8, 0)],
          face="calm", feet=[(-7.5, 0, -2.5), (7.5, 0, 3)]),
        Q(lean=4, yaw=-5, hip=(20.8, 0), hands=[(-11, -14, -4), (6, -12, 7)], face="calm"),
    ]
    S.lag_at(fr, "twig", {0: 0.0, 3: -2.0, 4: -3.0, 5: -1.5, 6: 1.6, 7: 0.0})   # twigs trail the bough
    S.lag_at(fr, "leaf", {0: 0.0, 3: -1.0, 4: -2.0, 5: -1.0, 6: 1.0, 7: 0.0})
    return fr


def bough_new():
    """Bough Swing (the heavier second light, from his other side), 8 frames. Timeline: 0 -> t0,
    1 -> t2, 2 -> t4 (the coil, held), 3 -> t6 (fast), 4 -> t7 (the hit, held 3), 5 -> t10,
    6 -> t13, 7 -> t16. A deeper coil and a wider arc than the Twig Swipe."""
    fw = dict(feet=[(-7, 0, -3), (7, 0, 4)])
    k = [
        Q(lean=-1, yaw=6, hip=(21.4, 0), hands=[(-11, -14, -4), (10, 0, -4)], poles=[None, (1, 0.3, -1)], face="grit"),
        Q(lean=-3, yaw=14, hip=(21.8, 0), hands=[(-11, -13, -4), (12, 7, -9)], poles=[None, (1, 0.4, -1)], face="grit",
          fingers=["open", "claw"]),
        Q(lean=-4, yaw=20, hip=(22, -0.5), hands=[(-11, -12, -4), (13, 10, -10)], poles=[None, (1, 0.5, -1)],
          face="grit", fingers=["open", "claw"], roll=2),
        Q(lean=5, yaw=-4, hip=(20.2, 0), hands=[(-11, -13, -4), (6, -2, 15)], poles=[None, (1, 0.7, -0.5)],
          face="shout", feet=[(-7, 0, -2), (7, 0, 3)]),
        Q(lean=9, yaw=-17, hip=(19.6, 0), hands=[(-11, -13, -4), (-4, -12, 27)], poles=[None, (1, 0.6, 0)],
          face="shout", **fw),
        Q(lean=11, yaw=-26, hip=(19.8, 0), hands=[(-11, -14, -4), (-16, -13, 17)], poles=[None, (1, 1.1, 0)],
          face="shout", **fw),
        Q(lean=8, yaw=-17, hip=(20.4, 0), hands=[(-11, -14, -4), (-10, -13, 7)], poles=[None, (1, 0.9, 0)],
          face="calm", feet=[(-7.5, 0, -2.5), (7.5, 0, 3)]),
        Q(lean=4, yaw=-6, hip=(20.8, 0), hands=[(-11, -14, -4), (4, -13, 6)], face="calm"),
    ]
    # his left arm leads, so the whole swing is the Twig Swipe's mirror image
    fr = [mirror(p) for p in k]
    S.lag_at(fr, "twig", {0: 0.0, 3: -1.0, 4: -3.0, 5: -3.5, 6: 1.5, 7: 0.0})
    S.lag_at(fr, "leaf", {0: 0.0, 4: 2.0, 5: 2.5, 6: -1.0, 7: 0.0})
    return fr


def logdrop_new():
    """Log Drop (light 3, and Timber Drop's tag-in), 8 frames. Timeline: 0 -> t0, 1 -> t3, 2 -> t6
    (rearing back, held), 3 -> t8 (the tip, fast), 4 -> t10 (the log lands, held 3), 5 -> t13
    (held 5: the ender's long hold), 6 -> t18, 7 -> t24. The trunk stops a frame before the
    log does (`bend` arrives a frame after `lean`)."""
    up = dict(hands=[(-10, 5, -7), (10, 5, -7)], poles=[(-1, 0.4, -1), (1, 0.4, -1)])
    fr = [
        Q(lean=-4, hip=(21.5, 0), hands=[(-10, -4, -4), (10, -4, -4)], poles=[(-1, 0.2, -1), (1, 0.2, -1)], face="grit"),
        Q(lean=-12, hip=(22, -1), face="grit", **up),
        Q(lean=-17, hip=(22.6, -1.5), face="grit", hands=[(-10, 7, -9), (10, 7, -9)],
          poles=[(-1, 0.5, -1), (1, 0.5, -1)]),
        Q(lean=34, bend=8, hip=(19.5, 1), hands=[(-10, -7, 4), (10, -7, 4)], face="shout", feet=[(-7, 0, -3), (7, 0, 4)]),
        Q(lean=43, bend=24, hip=(18, 2), hands=[(-11, -12, 12), (11, -12, 12)], face="shout",
          feet=[(-7, 0, -3), (7, 0, 5)]),
        Q(lean=42, bend=21, hip=(18, 2), hands=[(-11, -12, 12), (11, -12, 12)], face="shout",
          feet=[(-7, 0, -3), (7, 0, 5)]),
        Q(lean=28, bend=9, hip=(19.2, 1.5), hands=[(-11, -13, 6), (11, -13, 7)], face="calm", feet=[(-7, 0, -3), (7, 0, 4)]),
        Q(lean=13, bend=2, hip=(20.3, 1), hands=[(-11, -14, 1), (11, -14, 3)], face="calm"),
    ]
    S.lag_at(fr, "leaf", {0: 0.0, 2: 1.0, 3: -2.0, 4: -3.0, 5: 2.0, 6: -1.0, 7: 0.0})
    S.lag_at(fr, "twig", {0: 0.0, 2: 2.0, 3: -3.0, 4: -3.0, 5: 1.5, 6: 0.0})
    return fr


# ---- Timber Twister: 2 charge frames (a trembling crank back), 8 spin frames (45 degrees
# apiece, the boughs trailing the trunk by a frame), 2 to unwind.

def twister_new():
    crank = dict(lean=-5, hands=[(-8, -10, 8), (6, -10, -10)], fingers=["fist", "fist"], face="grit")
    fr = [
        Q(yaw=44, hip=(20.4, 0), **crank),
        Q(yaw=58, hip=(20.0, 0), **{**crank, "lean": -7, "hands": [(-7, -9, 10), (5, -9, -12)]}),
    ]
    yaws = [18, -27, -72, -117, -162, -207, -252, -297]
    for k, yw in enumerate(yaws):
        trail = 7.0 if k < 7 else 5.0
        spread = 22 + 5 * min(k, 3) / 3.0                    # the boughs fling out as the spin builds
        fr.append(Q(yaw=yw, lean=4, hip=(20.6, 0),
                    hands=[(-spread, -2 + k * 0.2, -trail), (spread, -2 + k * 0.2, trail)],
                    poles=[(-0.4, 1, 0.8), (0.4, 1, -0.8)], feet=[(-7, 0, 0), (7, 0, 0)], face="shout",
                    fingers=["open", "open"], twig=-2.0, leaf=-2.0 if k < 4 else 2.0))
    # the unwind: the boughs overshoot ahead of him, then settle
    fr.append(Q(yaw=-322, lean=6, hip=(20.2, 0), hands=[(-24, -4, 7), (24, -4, -5)], poles=[(0, 1, 0), (0, 1, 0)],
                feet=[(-7, 0, 0), (7, 0, 0)], face="shout", twig=2.0, leaf=2.0))
    fr.append(Q(yaw=-350, lean=3, hip=(20.7, 0), hands=[(-13, -13, -1), (13, -13, 2)], face="calm", twig=0.0, leaf=0.0))
    return fr


# ---- Branch Grab, Pinecone Bomb, Root Eruption

def grab_new():
    """Branch Grab, 12 frames. Timeline: 0 -> t0 (the cocked arm, held through the red windup),
    1 -> t2, 2 -> t5, 3 -> t8, 4 -> t10, 5 -> t11 (full reach, open), 6 -> t14 (the claw closes,
    held), then the reel 7 -> t17, 8 -> t20, 9 -> t23, 10 -> t27, 11 -> t31."""
    def far(ext, lean=10, up=-14, fing="open", face="shout", yaw=-10, pole=(1, 0.5, 0)):
        return Q(lean=lean, yaw=yaw, hands=[(-11, -12, -6), (-3, up, ext)], poles=[None, pole], face=face,
                 feet=[(-7, 0, -4), (7, 0, 4)], fingers=["open", fing], hip=(20, 0))
    fr = [
        Q(lean=-8, yaw=20, hip=(21.6, 0), hands=[(-10, -12, 2), (6, 2, -14)], poles=[None, (1, 0.2, -1)], face="grit",
          fingers=["open", "claw"]),
        Q(lean=-12, yaw=27, hip=(22, -0.5), hands=[(-10, -12, 3), (7, 5, -18)], poles=[None, (1, 0.3, -1)], face="grit",
          fingers=["open", "claw"]),
        far(8, lean=3, up=-4, fing="claw", face="grit", yaw=6, pole=(1, 0.4, -0.6)),
        far(24, lean=8, up=-11, fing="claw", yaw=-4),
        far(33, up=-14, fing="claw"),
        far(36, up=-15, fing="open"),
        far(35, up=-15, fing="fist"),
        Q(lean=6, yaw=-6, hip=(20, 0), hands=[(-11, -12, -4), (-3, -13, 27)], fingers=["open", "fist"], face="grit",
          poles=[None, (1, 0.5, 0)], feet=[(-7, 0, -4), (7, 0, 4)]),
        Q(lean=2, yaw=-3, hip=(20.4, 0), hands=[(-11, -12, -4), (-3, -12, 19)], fingers=["open", "fist"], face="grit",
          poles=[None, (1, 0.8, 0)]),
        Q(lean=1, hip=(20.6, 0), hands=[(-11, -13, -3), (3, -12, 10)], fingers=["open", "open"], face="calm"),
        Q(lean=2, hip=(20.8, 0), hands=[(-11, -14, -3), (8, -12, 5)], face="calm"),
        Q(lean=1, hip=(21, 0), hands=[(-11, -14, -3), (9, -13, 4)], face="calm"),
    ]
    S.lag_at(fr, "twig", {0: 0.0, 2: -1.5, 3: -3.0, 4: -3.0, 6: -1.0, 7: 1.5, 9: 0.0})
    S.lag_at(fr, "leaf", {0: 0.0, 2: 1.0, 3: -1.0, 5: -2.0, 7: 1.5, 9: 0.0})
    return fr


def pinecone_new():
    """Pinecone Bomb, 12 frames. 0-3: the held charge loop (anim_charge [0, 4, 6]: the cone
    overhead, the arm trembling, the trunk leaning back). Then 4 -> t0 (the pull back), 5 -> t3,
    6 -> t7 (the cone still in the hand, fast), 7 -> t10 (the release, held 3: the cone leaves
    at tick 10), 8 -> t13, 9 -> t17, 10 -> t22, 11 -> t28."""
    def hold_(lean, rise, back, **kw):
        return Q(lean=lean, hands=[(-11, -12, -2), (-1, rise, back)], fingers=["open", "fist"], face="grit", hold=1,
                 poles=[None, (1, -0.2, -1)], **kw)
    fr = [hold_(-10, 12.0, -10.0, hip=(21.6, 0)), hold_(-12, 13.0, -9.5, hip=(21.9, 0)),
          hold_(-14, 14.0, -10.5, hip=(22.2, -0.5)), hold_(-12, 12.8, -10, hip=(21.9, 0))]
    fr += [
        Q(lean=-17, hip=(22.5, -1), hands=[(-11, -10, -3), (-2, 14, -15)], fingers=["open", "fist"], face="grit",
          poles=[None, (1, -0.2, -1)], hold=1),
        Q(lean=-4, hip=(21, 0), hands=[(-11, -12, -2), (0, 13, -3)], fingers=["open", "fist"], face="grit", hold=1,
          poles=[None, (1, 0.1, -0.8)], feet=[(-7.5, 0, -2), (7.5, 0, 2)]),
        Q(lean=9, hip=(20, 0), hands=[(-11, -12, -2), (0, 10, 14)], fingers=["open", "open"], face="shout", hold=1,
          poles=[None, (1, 0.2, -0.5)], feet=[(-7, 0, -3), (7, 0, 3)]),
        Q(lean=13, hip=(19.8, 0), hands=[(-11, -12, -2), (0, 2, 22)], fingers=["open", "open"], face="shout",
          poles=[None, (1, 0.3, 0)], feet=[(-7, 0, -3), (7, 0, 4)]),
        Q(lean=12, hip=(20, 0), hands=[(-11, -12, -2), (0, -5, 21)], fingers=["open", "open"], face="shout",
          feet=[(-7, 0, -3), (7, 0, 4)]),
        Q(lean=8, hip=(20.4, 0), hands=[(-11, -13, -2), (2, -11, 13)], fingers=["open", "open"], face="calm"),
        Q(lean=4, hip=(20.8, 0), hands=[(-11, -14, -3), (7, -13, 8)], face="calm"),
        Q(lean=2, hip=(21, 0), hands=[(-11, -14, -3), (9, -13, 4)], face="calm"),
    ]
    S.lag_at(fr, "twig", {0: 0.0, 4: 1.5, 6: -2.0, 7: -3.0, 8: -1.5, 9: 1.0, 10: 0.0})
    S.lag_at(fr, "leaf", {0: 0.0, 4: 1.0, 6: -1.5, 7: -2.0, 8: 1.5, 9: -0.5, 10: 0.0})
    return fr


def eruption_new():
    """Root Eruption, 12 frames. Timeline: 0 -> t0, 1 -> t3, 2 -> t6, 3 -> t9 (the gather, arms
    high, glowing: the cut-in), 4 -> t12 (held: the last stretch), 5 -> t15 (the plunge, one fast
    frame), 6 -> t16 (the strike into the floor, held 7: rings at 17 and 23), 7 -> t23 (ring 2,
    the trunk recoils), 8 -> t29 (ring 3, the boughs flung up, held 7), 9 -> t36, 10 -> t44,
    11 -> t52."""
    def arms(lean, hip, hands, glow, face="shout", poles=None, **kw):
        return Q(lean=lean, hip=hip, hands=hands, glow=glow, face=face, poles=poles or [(-1, 0, -1), (1, 0, -1)], **kw)
    fr = [
        arms(-4, (21.4, 0), [(-13, 0, -1), (13, 0, -1)], 0.3, poles=[(-1, -0.2, -0.5), (1, -0.2, -0.5)]),
        arms(-7, (21.8, -0.5), [(-14, 6, -2), (14, 6, -2)], 0.5, poles=[(-1, -0.2, -0.5), (1, -0.2, -0.5)]),
        arms(-10, (22.3, -1), [(-9, 13, -3), (9, 13, -3)], 0.8),
        arms(-12, (23, -1), [(-6, 15, -4), (6, 15, -4)], 1.0),
        arms(-14, (23.5, -1.5), [(-5, 16.5, -5), (5, 16.5, -5)], 1.0),
        arms(16, (18.5, 1), [(-8, -6, 8), (8, -6, 8)], 1.0, poles=[(-1, 0.4, -0.5), (1, 0.4, -0.5)],
             feet=[(-8, 0, -2), (8, 0, -2)]),
        arms(34, (15, 2), [(-9, -24, 12), (9, -24, 12)], 1.0, poles=[(-1, 0.4, -0.5), (1, 0.4, -0.5)],
             feet=[(-8, 0, -2), (8, 0, -2)]),
        arms(25, (16.5, 2), [(-11, -18, 10), (11, -18, 10)], 0.9, poles=[(-1, 0.4, -0.5), (1, 0.4, -0.5)],
             feet=[(-8, 0, -2), (8, 0, -2)]),
        arms(8, (19.5, 1), [(-16, 5, 3), (16, 5, 3)], 1.0, poles=[(-1, 0.5, 0), (1, 0.5, 0)],
             feet=[(-8, 0, -2), (8, 0, -2)]),
        arms(5, (20.2, 0.5), [(-13, -5, 1), (13, -5, 1)], 0.6, face="grit"),
        arms(4, (20.6, 0), [(-12, -12, 0), (12, -12, 0)], 0.25, face="calm", poles=None),
        arms(2, (21, 0), [(-12, -13, 0), (12, -13, 0)], 0.0, face="calm", poles=None),
    ]
    S.lag_at(fr, "twig", {0: 0.0, 2: 1.5, 4: 2.5, 5: -3.0, 6: -2.0, 7: -1.0, 8: 3.0, 9: 1.0, 10: 0.0})
    S.lag_at(fr, "leaf", {0: 0.0, 2: 1.0, 4: 1.5, 5: -2.5, 6: -1.5, 7: 0.5, 8: 3.0, 9: -1.0, 10: 0.0})
    return fr


def dodge_new():
    """The crouch-and-lurch, 8 frames spread evenly over its 19 ticks (the view picks the
    frame by `state_t * 8 / 19`): the gather, the bow, two lurching steps low under the swing
    (the invulnerable ticks 2-12 are frames 1-5), the rise."""
    h = dict(hands=[(-7, -8, 8), (7, -8, 8)])
    return [
        Q(lean=18, hip=(18.5, 0), hands=[(-8, -10, 4), (8, -10, 4)], face="grit", feet=[(-7, 0, -2), (7, 0, 2)]),
        Q(lean=34, hip=(15.5, 1), bend=6, face="grit", feet=[(-6, 0, -4), (6, 1.5, 2)], **h),
        Q(lean=41, hip=(14, 1), bend=12, face="grit", feet=[(-6, 0, -6), (6, 2.5, 5)], **h),
        Q(lean=41, hip=(13.8, 1), bend=12, face="grit", feet=[(-6, 2.5, -1), (6, 0, 7)], **h),
        Q(lean=40, hip=(14, 1), bend=11, face="grit", feet=[(-6, 0, 3), (6, 1.5, 5)], **h),
        Q(lean=30, hip=(15.8, 0.5), bend=6, face="grit", feet=[(-6.5, 0, 2), (6.5, 0, 3)], **h),
        Q(lean=17, hip=(18.5, 0), bend=2, hands=[(-10, -12, 1), (10, -12, 1)], face="calm"),
        Q(lean=8, hip=(20.2, 0), hands=[(-11, -13, -1), (11, -13, 1)], face="calm"),
    ]


def victory_new():
    """Arms thrown up like boughs, the trunk stretching tall; frame 0 gathers, 1 to 5 loop (the
    boughs sway, leaves and twigs rustling a beat behind), 6 and 7 hold the proud stance."""
    up = dict(poles=[(-1, 1, 0), (1, 1, 0)], face="shout", fingers=["open", "open"], feet=[(-9, 0, -1), (9, 0, 1)])
    fr = [
        Q(lean=10, hip=(19.5, 0), hands=[(-10, -9, 3), (10, -9, 3)], face="grit", feet=[(-8, 0, -1), (8, 0, 1)]),
        Q(lean=-2, hip=(21.6, 0), roll=-3, hands=[(-12, 19, 0), (14, 22, 1)], **up),
        Q(lean=-5, hip=(22, 0), roll=0, hands=[(-14, 22, -1), (12, 19, 0)], **up),
        Q(lean=-3, hip=(21.8, 0), roll=3, hands=[(-15, 20, 1), (11, 22, -1)], **up),
        Q(lean=-5, hip=(22, 0), roll=0, hands=[(-12, 22, 0), (14, 19, 1)], **up),
        Q(lean=-3, hip=(21.7, 0), roll=-3, hands=[(-11, 20, -1), (15, 21, 0)], **up),
        Q(lean=4, hip=(20.4, 0), hands=[(-11, -2, 2), (11, -2, 2)], poles=[(-1, 0.5, 0), (1, 0.5, 0)], face="calm"),
        Q(lean=2, hip=(20.8, 0), hands=[(-12, 2, 1), (12, 2, 1)], poles=[(-1, 0.8, 0), (1, 0.8, 0)], face="calm"),
    ]
    S.lag_at(fr, "twig", {0: 0.0, 1: 2.0, 2: 3.0, 3: 2.0, 4: 3.0, 5: 2.0, 6: -1.0, 7: 0.0})
    S.lag_at(fr, "leaf", {0: 0.0, 1: -1.0, 2: 2.0, 3: -2.0, 4: 2.0, 5: -2.0, 6: 1.0, 7: 0.0})
    return fr


def idle_alt_new():
    """A creak: the trunk leans toward the foe with a groan, one arm shakes a leaf loose and
    the leaf falls away, he straightens."""
    base = dict(feet=[(-9, 0, -2), (9, 0, 2)], hands=[(-12, -15, -5), (13, 4, 5)],
                poles=[(-1, -0.4, -0.3), (1, -1.0, 0.2)])
    fr = [
        Q(hip=(21.0, 0), lean=1.0, **base),
        Q(hip=(20.6, 0), lean=5.0, yaw=-8, **base),
        Q(hip=(20.2, 0), lean=9.0, yaw=-16, roll=-2, **base, face="grit"),
        Q(hip=(20.2, 0), lean=9.0, yaw=-16, roll=1, **{**base, "hands": [(-12, -15, -5), (13, 8, 6)]}, face="grit"),
        Q(hip=(20.2, 0), lean=8.0, yaw=-16, roll=-1, **{**base, "hands": [(-12, -15, -5), (13, 6, 4)]}, face="grit"),
        Q(hip=(20.4, 0), lean=8.0, yaw=-14, roll=1, **{**base, "hands": [(-12, -15, -5), (13, 8, 6)]}),
        Q(hip=(20.8, 0), lean=4.0, yaw=-6, **base),
        Q(hip=(21.0, 0), lean=1.5, **base),
    ]
    S.lag_at(fr, "leaf", {0: 0.0, 2: 1.0, 3: -3.0, 4: 3.0, 5: -2.0, 6: 1.0, 7: 0.0})
    S.lag_at(fr, "twig", {0: 0.0, 2: 1.0, 3: 3.0, 4: -2.0, 5: 2.0, 6: 0.0})
    return fr


ROWS = [
    ("idle", idle_new()),
    ("run", run_new()),
    ("twig", twig_new()),
    ("bough", bough_new()),
    ("logdrop", logdrop_new()),
    ("twister", twister_new()),
    ("grab", grab_new()),
    ("pinecone", pinecone_new()),
    ("eruption", eruption_new()),
    ("dodge", dodge_new()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("victory", victory_new()),
    ("idle_alt", idle_alt_new()),
    ("ko", ko()),
]
# Up and down sheets: every row but the knockout, which falls over sideways in any view.
VIEW_ROWS = ROWS[:-1]
ANIM_COLS = 12


# The timelines the JSON gets after approval (anim_at: [tick, frame], each from its tick on).
# Every startup, active, recovery and windup stays; only the frames move. Hits land at
# startup + 1 (the lights, Timber Drop, the lob's release) or at the listed `at` ticks.
NEW_AT = {
    "light_1": [[0, 0], [2, 1], [4, 2], [5, 3], [8, 4], [10, 5], [12, 6], [14, 7]],
    "light_2": [[0, 0], [2, 1], [4, 2], [6, 3], [7, 4], [10, 5], [13, 6], [16, 7]],
    "light_3": [[0, 0], [3, 1], [6, 2], [8, 3], [10, 4], [13, 5], [18, 6], [24, 7]],
    "tag_in": [[0, 0], [2, 1], [5, 2], [7, 3], [9, 4], [13, 5], [18, 6], [24, 7]],
    "heavy": [[0, 1], [2, 2], [4, 3], [6, 4], [7, 5], [8, 6], [9, 7], [10, 8], [11, 9], [12, 2], [13, 3], [14, 4],
              [15, 5], [16, 6], [17, 7], [18, 8], [19, 9], [20, 2], [22, 10], [28, 11]],
    "skill_1": [[0, 0], [2, 1], [5, 2], [8, 3], [10, 4], [11, 5], [14, 6], [17, 7], [20, 8], [23, 9], [27, 10], [31, 11]],
    "skill_2": [[0, 4], [3, 5], [7, 6], [10, 7], [13, 8], [17, 9], [22, 10], [28, 11]],
    "surge": [[0, 0], [3, 1], [6, 2], [9, 3], [12, 4], [15, 5], [16, 6], [23, 7], [29, 8], [36, 9], [44, 10], [52, 11]],
}
NEW_CHARGE = {"heavy": [0, 2, 6], "skill_2": [0, 4, 6]}   # frames looped while the charge is held
NEW_CUT_IN = [8, 3]                                       # the Surge cut-in: the arms-high gather
# The dodge's own timeline (dodge.anim_at, a view-only key read by CreatureView._pick): the bow
# (frames 1 and 2, ticks 2 to 7) is held while the invulnerable ticks 2 to 12 run.
NEW_DODGE_AT = [[0, 0], [2, 1], [5, 2], [8, 3], [11, 4], [13, 5], [15, 6], [17, 7]]
MOVE_ANIM = {"light_1": "twig", "light_2": "bough", "light_3": "logdrop", "tag_in": "logdrop", "heavy": "twister",
             "skill_1": "grab", "skill_2": "pinecone", "surge": "eruption"}
ANIM_COUNT = {name: len(poses) for name, poses in ROWS}
for _mid, _at in NEW_AT.items():  # a typo here would put a blank frame in the game
    _n = ANIM_COUNT[MOVE_ANIM[_mid]]
    assert all(0 <= f < _n for _t, f in _at), (_mid, _at)
    assert [t for t, _f in _at] == sorted(t for t, _f in _at), _mid
assert NEW_CUT_IN[1] < ANIM_COUNT["eruption"]
for _mid, (_first, _count, _each) in NEW_CHARGE.items():
    assert _first + _count <= ANIM_COUNT[MOVE_ANIM[_mid]], _mid
assert all(len(poses) <= ANIM_COLS for _n, poses in ROWS)


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_barkley.py anim` renders preview GIFs into docs/anim_preview/, and
# `python3 tools/anim_preview.py --check barkley` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at), which only touch
# pose attributes; this generator's renderer is its own.
ANIM_CYCLES = {"idle": 80, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks), as barkley.json has them


def frame_spec(view):
    return SIDE if view == "side" else VIEWS[view]


def render_frame(pose, view):
    """One frame on its own, with the frame size and origin set as sheet() sets them."""
    global W, H, OX, OY
    sp = frame_spec(view)
    W, H = sp["w"], sp["h"]
    OX, OY = sp["origin"]
    return render(pose, view)

OLD_REF = os.environ.get("BARKLEY_OLD_REF", "fce60cc")  # main before the pass: the "current" frames


def _old_default(n, su, active, length):
    """The frame the view picks today for a move with no anim_at (creature_view.gd
    `_attack_frame`, the last branch): windup frames, the strike, the follow-through."""
    first_at = su + 1
    wind = max(1, n - 3)
    out = []
    for t in range(length + 1):
        if t < first_at:
            out.append(min(wind - 1, t * wind // max(1, first_at)))
        elif t < first_at + active:
            out.append(n - 3)
        else:
            rec_start = first_at + active
            out.append(n - 2 if t - rec_start < max(1, length - rec_start) // 2 else n - 1)
    return out


def _clips():
    import anim_preview as A
    old = A.creature_json("barkley", OLD_REF)
    mv = old["moves"]
    old_idle, new_idle = (10, 4), (10, 8)

    def length(m):
        return A.move_length(m)

    def old_frames(mid):
        m = mv[mid]
        if "anim_at" in m:
            return A.timed(m["anim_at"], length(m))
        return _old_default(int(old["sprite"]["anims"][m["anim"]][2]), int(m["startup"]), int(m["active"]), length(m))

    def clip(mid, marks=(), pre=0, charge=None, charge_ticks=0):
        m = mv[mid]
        anim = MOVE_ANIM[mid]
        o = old_frames(mid)
        n = A.timed(NEW_AT[mid], length(m))
        old_t = [(anim, o[0])] * pre + [(anim, f) for f in o] + A.idle_tail(30, *old_idle)
        new_t = [(anim, n[0])] * pre + [(anim, f) for f in n] + A.idle_tail(30, *new_idle)
        if charge:
            old_t = A.charge_ticks(anim, 0, 2, 6, charge_ticks) + old_t
            new_t = A.charge_ticks(anim, *charge, charge_ticks) + new_t
        return ({"old": old_t, "new": new_t}, list(marks))

    def hits(mid, pre=0, name=None):
        m = mv[mid]
        return [(pre + a, pre + b, "hit (%s)" % (name or m["name"])) for a, b in A._hits(m)]

    def dodge():
        d = old["dodge"]
        fr = int(d["frames"])
        o = [("dodge", t * 4 // fr) for t in range(fr)]
        nw = [("dodge", f) for f in A.timed(NEW_DODGE_AT, fr - 1)]
        return ({"old": o + A.idle_tail(30, *old_idle), "new": nw + A.idle_tail(30, *new_idle)},
                [(d["iframes_start"], d["iframes_end"], "invulnerable")])

    ch = 24
    return {
        "idle": ({"old": A.loop_ticks("idle", 10, 4, 160), "new": A.loop_ticks("idle", 10, 8, 160)}, []),
        "run": ({"old": A.loop_ticks("run", 4, 6, 48), "new": A.loop_ticks("run", 2, 12, 48)}, []),
        "twig": clip("light_1", hits("light_1") + [(8, 16, "cancel from 8")]),
        "bough": clip("light_2", hits("light_2") + [(9, 19, "cancel from 9")]),
        "logdrop": clip("light_3", hits("light_3")),
        "logdrop_tag_in": clip("tag_in", hits("tag_in")),
        "twister": clip("heavy", [(0, ch, "held charge")] + hits("heavy", ch, "Twister"),
                        charge=NEW_CHARGE["heavy"], charge_ticks=ch),
        "grab": clip("skill_1", [(0, 8, "windup (red tell)")] + hits("skill_1", 8), pre=8),
        "pinecone": clip("skill_2", [(0, ch, "held charge"), (ch + 10, ch + 13, "pinecone leaves")], charge=NEW_CHARGE["skill_2"],
                         charge_ticks=ch),
        "eruption": clip("surge", hits("surge", 0, "ring")),
        "dodge": dodge(),
    }


CLIPS = _clips
ANIM_CONTACT = ["idle", "run", "twig", "bough", "logdrop", "twister", "grab", "pinecone", "eruption", "dodge"]


def inspect(rows, picks, path):
    """Frames side by side in all three views, 3x: picks like idle:0 run:2."""
    tiles = []
    for pick in picks:
        name, f = pick.split(":")
        poses = dict(rows)[name]
        for view in ("side", "down", "up"):
            img = render_frame(poses[int(f)], view)
            bg = Image.new("RGBA", img.size, (70, 58, 46, 255))
            bg.alpha_composite(img)
            ImageDraw.Draw(bg).text((2, 2), "%s %s" % (pick, view), fill=(255, 220, 140, 255))
            tiles.append(bg.resize((img.width * 3, img.height * 3), Image.NEAREST))
    cw = max(t.width for t in tiles)
    ch_ = max(t.height for t in tiles)
    out = Image.new("RGBA", (cw * 3, ch_ * ((len(tiles) + 2) // 3)), (40, 32, 26, 255))
    for k, t in enumerate(tiles):
        out.alpha_composite(t, ((k % 3) * cw, (k // 3) * ch_))
    out.save(path)
    print("wrote", path)


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
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        # python3 tools/gen_barkley.py inspect idle:0 run:2
        inspect(ROWS, sys.argv[2:], os.environ.get("INSPECT_OUT", os.path.join(ROOT, "barkley_inspect.png")))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        main()
