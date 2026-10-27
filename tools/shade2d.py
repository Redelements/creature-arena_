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

Normal sheets (docs/SPRITES.md "Normal sheets"): `shade` also keeps the shading's normal
in `img.info["nrm"]`, and `stack` composites them with the layers into `info["nrm"]`,
`info["fill"]` (the pixels a shaded shape filled; outlines, seams and anything painted
outside the shape face the camera) and `info["piece"]` (which layer, for the smoothing);
`normal_map(img)` packs a finished frame's for splat3d.finish_frame. A layer whose tags got
lost (an Image rebuilt without `keep`) lights flat, as if it faced the camera.

Density (`configure(density=2)`, the 2x sheets of docs/pixellab-spec.md, `"ppu": 2`): a
painter keeps drawing in 1x pixel coordinates through `Draw`, which paints on a layer
`density` times the size: every fill, stroke, dot and painted leaf doubles in size (a dot is
a 2x2 block, a line 2 px wide), and the shading counts its pixel lengths through `px()`
(the distance cap, the thickness window, the smoothing, the cleanup, the rim light's
width) as splat3d does, so the bands fall on the same parts of a shape, twice as wide. The
outline and the seams stay one pixel. `configure` also sets splat3d's density, which the
normal sheets' blur reads (`normal_map`). At density 1 everything draws as before, byte for
byte. `RIM` (False) and `LUM_HIGH` (high) are the "bold" look's switches, as in splat3d.
"""
import numpy as np
from PIL import Image, ImageDraw

import palette as P
from splat3d import LIGHT, LUM_HIGH, LUM_LIGHT, LUM_SHADOW, RIM_SIDE, material_ramp

MAX_DIST = 14       # distance-to-edge cap (1x pixels); nothing here is thicker than 28 px
DENSITY = 1         # art pixels per 1x pixel (configure(density=...)); 2 for 2x sheets
RIM = True          # the rim light on the shadowed far edge (the bold look turns it off)


def configure(density=1):
    """Draw at `density` (1 or 2) art pixels per 1x pixel: `Draw` scales the painter's
    1x coordinates, the shading's pixel lengths go through `px`, and splat3d (the sheet
    writer, the normal sheets' blur) gets the same density."""
    global DENSITY
    if int(density) not in (1, 2):
        raise ValueError("density: 1 or 2 art pixels per 1x pixel, not %r" % (density,))
    DENSITY = int(density)
    import splat3d
    splat3d.DENSITY = DENSITY


def px(v):
    """A length counted in 1x pixels at the configured density (splat3d.px)."""
    return v * DENSITY


def to_px(v):
    """A 1x coordinate as an art-pixel coordinate: the centre of the block its 1x pixel
    covers (at density 1, the coordinate itself)."""
    if DENSITY == 1:
        return v
    return v * DENSITY + (DENSITY - 1) / 2.0


def snap(v):
    """round() on the art-pixel grid, in 1x units: a dot placed at a rounded spot moves in
    half-pixel steps at density 2 (at density 1, round(v))."""
    if DENSITY == 1:
        return round(v)
    return round(v * DENSITY) / DENSITY


class Draw:
    """ImageDraw in 1x pixel coordinates on a layer DENSITY times the size. A point is the
    block its 1x pixel covers, a box ([x0, y0, x1, y1], ellipse or rectangle) covers the
    blocks of its corner pixels, polygon and line vertices land on their blocks' centres,
    and a line is `width` 1x pixels wide. At density 1 it is ImageDraw, call for call."""

    def __init__(self, img):
        self.d = ImageDraw.Draw(img)
        self.k = DENSITY

    def _xy(self, pts):
        if len(pts) and not isinstance(pts[0], (tuple, list)):
            pts = list(zip(pts[0::2], pts[1::2]))
        return [(to_px(x), to_px(y)) for x, y in pts]

    def _box(self, box):
        if len(box) == 2:
            (x0, y0), (x1, y1) = box
        else:
            x0, y0, x1, y1 = box
        k = self.k
        return [x0 * k, y0 * k, x1 * k + k - 1, y1 * k + k - 1]

    def ellipse(self, box, fill=None, outline=None, width=1):
        if self.k == 1:
            return self.d.ellipse(box, fill=fill, outline=outline, width=width)
        return self.d.ellipse(self._box(box), fill=fill, outline=outline, width=width * self.k)

    def rectangle(self, box, fill=None, outline=None, width=1):
        if self.k == 1:
            return self.d.rectangle(box, fill=fill, outline=outline, width=width)
        return self.d.rectangle(self._box(box), fill=fill, outline=outline, width=width * self.k)

    def polygon(self, pts, fill=None, outline=None):
        if self.k == 1:
            return self.d.polygon(pts, fill=fill, outline=outline)
        return self.d.polygon(self._xy(pts), fill=fill, outline=outline)

    def line(self, pts, fill=None, width=1):
        if self.k == 1:
            return self.d.line(pts, fill=fill, width=width)
        return self.d.line(self._xy(pts), fill=fill, width=width * self.k)

    def point(self, xy, fill=None):
        if self.k == 1:
            return self.d.point(xy, fill=fill)
        x, y = xy
        k = self.k
        return self.d.rectangle([x * k, y * k, x * k + k - 1, y * k + k - 1], fill=fill)


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
    for k in ("mat", "ring", "nrm", "fill", "piece"):
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
    for _ in range(px(MAX_DIST)):
        if not cur.any():
            break
        d += cur
        nxt = cur.copy()
        for dx, dy in N4:
            nxt &= _shifted(cur, dx, dy, False)
        cur = nxt
    # local half-thickness: the deepest distance nearby (within 3 1x pixels)
    r = d.copy()
    for _ in range(px(3)):
        g = r.copy()
        for dx, dy in N4 + ((1, 1), (-1, -1), (1, -1), (-1, 1)):
            g = np.maximum(g, _shifted(r, dx, dy, 0.0))
        r = np.where(m, g, 0.0)
    dd = np.maximum(d - 0.5, 0.0)
    rr = np.maximum(r, 1.0)
    z = np.sqrt(np.maximum(0.0, dd * (2.0 * rr - dd)))
    z[~m] = 0.0
    # soften the stair steps of the distance field a little (a pass per 1x pixel)
    for _ in range(px(1)):
        s = z.copy()
        for dx, dy in N4:
            s += _shifted(z, dx, dy, 0.0)
        z = np.where(m, s / 5.0, 0.0)
    return z


def despeckle(level, mat, filled, passes=None):
    """A lone pixel whose tone none of its same-material neighbours share takes the
    tone most of them have (splat3d's cleanup: two passes per 1x pixel)."""
    for _ in range(px(2) if passes is None else passes):
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
        res.info["nrm"] = self._nrm
        return res

    def levels(self, m, mat, rim=True):
        z = height(m)
        gx = (_shifted(z, 1, 0, 0.0) - _shifted(z, -1, 0, 0.0)) * 0.5
        gy = (_shifted(z, 0, 1, 0.0) - _shifted(z, 0, -1, 0.0)) * 0.5
        n = np.stack([-gx, -gy, np.ones_like(z)], axis=2)
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        self._nrm = n  # the shading's normal (x right, y down, z toward us), for normal sheets
        light = np.array(LIGHT, np.float32)
        light /= np.linalg.norm(light)
        lum = n @ light
        level = np.full(m.shape, 2, np.int8)
        level[lum > LUM_LIGHT] = 3
        level[lum > LUM_HIGH] = 4
        level[lum < LUM_SHADOW] = 1
        level = despeckle(level, mat, m)
        if rim and RIM:
            edge = np.zeros_like(m)
            for k in range(1, DENSITY + 1):   # as wide as one 1x pixel
                for dx, dy in ((k, 0), (k, k), (0, k)):
                    edge |= m & ~_shifted(m, dx, dy, False)
            away = (n[:, :, 0] * -light[0] + n[:, :, 1] * -light[1]) > RIM_SIDE
            # only where the core shadow runs at least two (1x) pixels in from the edge
            inner = np.zeros_like(m)
            k = DENSITY
            for dx, dy in ((-k, 0), (-k, -k), (0, -k)):
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
        keep(out, img)
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
        keep(out, img)
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
        cnrm = np.zeros((h, w, 3), np.float32)
        cnrm[..., 2] = 1.0
        cfill = np.zeros((h, w), bool)
        cpiece = np.zeros((h, w), np.int64)
        for li, lay in enumerate(layers):
            lnrm, lfill, lpiece = _normal_tags(lay)
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
            cnrm = np.where(la[..., None], lnrm, cnrm)
            cfill = np.where(la, lfill & ~under, cfill)
            cpiece = np.where(la, (li + 1) * 4096 + lpiece, cpiece)
        out = Image.fromarray(canvas)
        out.info["mat"] = cmat
        out.info["ring"] = cring
        out.info["nrm"] = cnrm
        out.info["fill"] = cfill
        out.info["piece"] = cpiece
        return out


def _normal_tags(img):
    """A layer's normals, the pixels they hold for, and its pieces (a stacked layer keeps
    its own): a shaded layer's normal where its shape is (not its outline ring), facing the
    camera everywhere else."""
    a, mat, ring = tags(img)
    h, w = a.shape[:2]
    nrm = img.info.get("nrm")
    if nrm is None or nrm.shape[:2] != (h, w):
        nrm = np.zeros((h, w, 3), np.float32)
        nrm[..., 2] = 1.0
        return nrm, np.zeros((h, w), bool), np.zeros((h, w), np.int64)
    fill = img.info.get("fill")
    if fill is None or fill.shape != (h, w):
        fill = (mat > 0) & ~ring
    piece = img.info.get("piece")
    if piece is None or piece.shape != (h, w):
        piece = np.zeros((h, w), np.int64)
    fill = fill & (a[:, :, 3] > 0)
    return nrm, fill, piece


def normal_map(img):
    """A finished (stacked) frame's normal sheet RGBA for splat3d.finish_frame(normals=...)."""
    import splat3d
    a = np.array(img)
    nrm, fill, piece = _normal_tags(img)
    return splat3d.pack_normals(nrm.astype(float), piece, fill, a[:, :, 3])
