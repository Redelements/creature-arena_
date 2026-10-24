"""Master-palette shading for the 2D painters (Barkley's and Gillbert's rigs).

Those generators project a 3D rig per view but paint flat 2D shapes (capsules, discs,
polygons) one layer per part. This module gives those shapes the look splat3d.shade
gives its splats, from the same five-step ramps (tools/palette.py):

  - a height field per shape (each pixel's distance to the shape's edge, rounded off
    like a tube of the shape's local thickness), so its normals bend toward the edges;
  - the splat3d key light (top left) and its thresholds: a small highlight, light and
    base on the lit side, a hard terminator, one dark step for the core shadow;
  - a one-pixel rim light (one step up) on the shadowed edge facing away from the light,
    only where the core shadow is at least two pixels deep, so thin twigs keep theirs;
  - a cleanup pass: a lone pixel whose tone no neighbour shares takes the majority's;
  - outlines in each material's own ink (palette.ink_for), never pure black;
  - seams: where one layer's outline falls on a layer behind it, it is drawn in the
    behind piece's deep step, one step lighter than the silhouette line (`stack`).

Usage, in a generator:
    import shade2d
    M = shade2d.Materials({"bark": ("rust", 1), "moss": "moss", "eye": P.flat("blue", 3)})
    img = M.shade(img, "bark")      # any filled shape -> ramp-shaded, tagged "bark"
    M.groove(img, det)              # detail lines: one ramp step darker where they fall
    img = M.outline(img)            # each material's ink, 1 px outside the shape
    out = M.stack(layers)           # back to front, seams in the deep step

Material specs are anything splat3d.material_ramp takes (a ramp name, (name, shift),
five colours). Each layer carries its material ids and outline ring in `img.info`
("mat", "ring"), so keep using the same Image object (alpha_composite and ImageDraw
work in place) or copy the info with `keep(new, old)`.
"""
import numpy as np
from PIL import Image

import palette as P
from splat3d import LIGHT, LUM_HIGH, LUM_LIGHT, LUM_SHADOW, RIM_SIDE, material_ramp

MAX_DIST = 14       # distance-to-edge cap (pixels); nothing here is thicker than 28 px


def _luma(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def _shifted(a, dx, dy, fill):
    """The value at (x + dx, y + dy), brought to (x, y); `fill` past the edge."""
    out = np.full_like(a, fill)
    h, w = a.shape[:2]
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    out[ys0:ys1, xs0:xs1] = a[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
    return out


N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def keep(new, old):
    """Copy a layer's material tags onto a new Image made from it."""
    for k in ("mat", "ring"):
        if k in old.info:
            new.info[k] = old.info[k].copy()
    return new


def tags(img):
    a = np.array(img)
    h, w = a.shape[:2]
    mat = img.info.get("mat")
    ring = img.info.get("ring")
    if mat is None or mat.shape != (h, w):
        mat = np.zeros((h, w), np.int16)
    if ring is None or ring.shape != (h, w):
        ring = np.zeros((h, w), bool)
    return a, mat, ring


def height(m):
    """A height field over a mask: each pixel's distance to the edge, rounded like a
    tube as thick as the shape is there (z = sqrt(d * (2R - d)))."""
    d = np.zeros(m.shape, np.float32)
    cur = m.copy()
    for _ in range(MAX_DIST):
        if not cur.any():
            break
        d += cur
        nxt = cur.copy()
        for dx, dy in N4:
            nxt &= _shifted(cur, dx, dy, False)
        cur = nxt
    # local half-thickness: the deepest distance nearby
    r = d.copy()
    for _ in range(3):
        g = r.copy()
        for dx, dy in N4 + ((1, 1), (-1, -1), (1, -1), (-1, 1)):
            g = np.maximum(g, _shifted(r, dx, dy, 0.0))
        r = np.where(m, g, 0.0)
    dd = np.maximum(d - 0.5, 0.0)
    rr = np.maximum(r, 1.0)
    z = np.sqrt(np.maximum(0.0, dd * (2.0 * rr - dd)))
    z[~m] = 0.0
    # soften the stair steps of the distance field a little
    s = z.copy()
    for dx, dy in N4:
        s += _shifted(z, dx, dy, 0.0)
    z = np.where(m, s / 5.0, 0.0)
    return z


def despeckle(level, mat, filled, passes=2):
    """A lone pixel whose tone none of its same-material neighbours share takes the
    tone most of them have (splat3d's cleanup)."""
    for _ in range(passes):
        same = np.zeros(level.shape, np.int8)
        votes = np.zeros(level.shape + (5,), np.int8)
        for dx, dy in N4:
            nl = _shifted(level, dx, dy, -1)
            nm = _shifted(mat, dx, dy, 0)
            ok = filled & (nm == mat)
            same += (ok & (nl == level)).astype(np.int8)
            for k in range(5):
                votes[..., k] += (ok & (nl == k)).astype(np.int8)
        best = votes.argmax(axis=2).astype(np.int8)
        lone = filled & (same == 0) & (votes.max(axis=2) >= 2)
        if not lone.any():
            break
        level = np.where(lone, best, level)
    return level


class Materials:
    def __init__(self, mat):
        self.names = list(mat)
        self.id = {n: i + 1 for i, n in enumerate(self.names)}
        self.ramp = {n: [tuple(c[:3]) for c in material_ramp(s)] for n, s in mat.items()}
        self.ink = {}
        self.seam = {}
        for n, r5 in self.ramp.items():
            ink = tuple(P.ink_for(r5))
            self.ink[n] = ink
            # one step lighter than the outline: the deep step, unless that's darker
            self.seam[n] = next((c for c in r5[:2] if _luma(c) > _luma(ink) + 6), ink)
        k = len(self.names) + 1
        self.lut = np.zeros((k, 5, 3), np.uint8)
        self.ink_lut = np.zeros((k, 3), np.uint8)
        self.seam_lut = np.zeros((k, 3), np.uint8)
        for n, i in self.id.items():
            self.lut[i] = self.ramp[n]
            self.ink_lut[i] = self.ink[n]
            self.seam_lut[i] = self.seam[n]
        self.ink_lut[0] = P.INKS["ink"]

    def col(self, name, step=2):
        """One colour of a material's ramp (0 deep .. 4 highlight), RGBA."""
        return tuple(self.ramp[name][step]) + (255,)

    # -- shading
    def shade(self, img, name, labels=None, rim=True):
        """Ramp-shade every filled pixel of `img` as one rounded shape. `labels` (an
        (H, W) array of material names' ids) colours parts of it from other ramps
        (Gillbert's ring bands) while the light still reads the whole shape."""
        a = np.array(img)
        m = a[:, :, 3] > 0
        mat = np.zeros(m.shape, np.int16)
        mat[m] = self.id[name]
        if labels is not None:
            mat = np.where(m & (labels > 0), labels, mat).astype(np.int16)
        level = self.levels(m, mat, rim)
        out = np.zeros_like(a)
        out[m, :3] = self.lut[mat[m], level[m]]
        out[m, 3] = 255
        res = Image.fromarray(out)
        res.info["mat"] = mat
        res.info["ring"] = np.zeros(m.shape, bool)
        return res

    def levels(self, m, mat, rim=True):
        z = height(m)
        gx = (_shifted(z, 1, 0, 0.0) - _shifted(z, -1, 0, 0.0)) * 0.5
        gy = (_shifted(z, 0, 1, 0.0) - _shifted(z, 0, -1, 0.0)) * 0.5
        n = np.stack([-gx, -gy, np.ones_like(z)], axis=2)
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        light = np.array(LIGHT, np.float32)
        light /= np.linalg.norm(light)
        lum = n @ light
        level = np.full(m.shape, 2, np.int8)
        level[lum > LUM_LIGHT] = 3
        level[lum > LUM_HIGH] = 4
        level[lum < LUM_SHADOW] = 1
        level = despeckle(level, mat, m)
        if rim:
            edge = np.zeros_like(m)
            for dx, dy in ((1, 0), (1, 1), (0, 1)):
                edge |= m & ~_shifted(m, dx, dy, False)
            away = (n[:, :, 0] * -light[0] + n[:, :, 1] * -light[1]) > RIM_SIDE
            # only where the core shadow runs at least two pixels in from the edge
            inner = np.zeros_like(m)
            for dx, dy in ((-1, 0), (-1, -1), (0, -1)):
                inner |= _shifted(m, dx, dy, False) & (_shifted(level, dx, dy, 9) <= 1)
            lift = edge & away & (level <= 1) & inner
            level[lift] += 1
        level[~m] = 0
        return level

    def groove(self, img, det, k=-1):
        """Detail lines (grain, scales, rays) drawn in any colour on `det`: where they
        fall on the shape, its pixels move `k` steps along their own ramp (so a groove
        is one step darker in the light and in the shadow alike)."""
        d = np.array(det)[:, :, 3] > 0
        self._step(img, d, k)
        return img

    def _step(self, img, where, k):
        a, mat, _ring = tags(img)
        where = where & (a[:, :, 3] > 0) & (mat > 0)
        if not where.any():
            return img
        ys, xs = np.nonzero(where)
        ids = mat[ys, xs]
        cols = a[ys, xs, :3].astype(np.int16)
        r = self.lut[ids].astype(np.int16)                    # (n, 5, 3)
        hit = np.all(r == cols[:, None, :], axis=2)           # (n, 5)
        ok = hit.any(axis=1)
        lvl = hit.argmax(axis=1)
        new = np.clip(lvl + k, 0, 4)
        a[ys[ok], xs[ok], :3] = self.lut[ids[ok], new[ok]]
        out = Image.fromarray(a)
        img.paste(out)
        return img

    def darken(self, img, k=-1):
        """The whole layer one ramp step darker (the far arm or leg)."""
        a, mat, _ring = tags(img)
        self._step(img, a[:, :, 3] > 0, k)
        return img

    def paint(self, img, mask, name, step):
        """Fill `mask` with one step of a material's ramp and tag it."""
        a, mat, ring = tags(img)
        a[mask, :3] = self.ramp[name][step]
        a[mask, 3] = 255
        mat = mat.copy()
        mat[mask] = self.id[name]
        out = Image.fromarray(a)
        out.info["mat"] = mat
        out.info["ring"] = ring & ~mask
        return out

    # -- lines
    def outline(self, img, force=None):
        """A 1 px line outside the shape in the ink of the material beside it."""
        a, mat, ring = tags(img)
        m = a[:, :, 3] > 0
        new_ring = np.zeros_like(m)
        rmat = np.zeros_like(mat)
        for dx, dy in N4:
            nf = _shifted(m, dx, dy, False)
            nm = _shifted(mat, dx, dy, 0)
            rmat = np.where(nf & ~m & (rmat == 0), nm, rmat)
            new_ring |= nf & ~m
        if force is not None:
            a[new_ring, :3] = force[:3]
        else:
            a[new_ring, :3] = self.ink_lut[rmat[new_ring]]
        a[new_ring, 3] = 255
        out = Image.fromarray(a)
        out.info["mat"] = mat
        out.info["ring"] = ring | new_ring
        return out

    def stack(self, layers, size=None):
        """Composite layers back to front. Where a layer's outline lands on a piece
        already drawn, it becomes that piece's seam colour (its deep step)."""
        if size is None:
            size = layers[0].size
        w, h = size
        canvas = np.zeros((h, w, 4), np.uint8)
        cmat = np.zeros((h, w), np.int16)
        cring = np.zeros((h, w), bool)
        for lay in layers:
            a, mat, ring = tags(lay)
            la = a[:, :, 3] > 0
            ring = ring & la
            under = ring & (canvas[:, :, 3] > 0) & ~cring & (cmat > 0)
            if under.any():
                a = a.copy()
                a[under, :3] = self.seam_lut[cmat[under]]
            alpha = a[:, :, 3:4].astype(np.float32) / 255.0
            canvas[:, :, :3] = (a[:, :, :3] * alpha + canvas[:, :, :3] * (1 - alpha)).astype(np.uint8)
            canvas[:, :, 3] = np.maximum(canvas[:, :, 3], a[:, :, 3])
            cmat = np.where(la, np.where(ring, 0, mat), cmat)
            cring = np.where(la, ring, cring)
        out = Image.fromarray(canvas)
        out.info["mat"] = cmat
        out.info["ring"] = cring
        return out
