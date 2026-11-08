"""Projected rigid-part poses for Cairn's cut-out renderer.

Uses gen_cairn's existing keyed poses, including its glove/foot corrections.
Coordinates are sheet pixels; angles are clockwise in screen coordinates. Compare
each part with reference_pose(view) to move approved artwork without rescaling it.
Positive depth is toward the camera: paint smaller depths first. ``near`` and
``far`` name physical rig limbs (+lat and -lat), not screen left and right.

This module does not render artwork or alter gameplay/timelines. Run --check to
validate all views and compare glove locations against the geometric generator.
"""
from dataclasses import dataclass
import math
from typing import Dict, Tuple

import numpy as np
import gen_cairn as G


VIEWS = ("side", "down", "up", "down_side", "up_side")
ALIASES = {"front": "down", "back": "up", "front_34": "down_side", "back_34": "up_side"}
ROWS = G.ROWS


@dataclass(frozen=True)
class PartPose:
    center: Tuple[float, float]
    angle_degrees: float
    depth: float
    start: Tuple[float, float]
    end: Tuple[float, float]
    world_center: Tuple[float, float, float]
    # World-space facing angle useful when choosing another painted head view.
    yaw_degrees: float = 0.0


@dataclass(frozen=True)
class HeadArtwork:
    source_view: str
    mirror: bool
    heading_degrees: float


def view_name(view):
    view = ALIASES.get(view, view)
    if view not in VIEWS:
        raise ValueError("Unknown Cairn view: " + str(view))
    return view


def frame_spec(view):
    view = view_name(view)
    return dict(G.SIDE if view == "side" else G.VIEWS[view])


def frame_counts():
    return {name: len(poses) for name, poses in ROWS}


def _project(points, view):
    # Cam.P uses global canvas offsets, but subtracting them means callers need
    # not mutate splat3d's currently configured frame. Use Cairn's own scale and
    # near zone explicitly so another renderer's configuration cannot leak in.
    cam = G.S.Cam(view)
    cam.near = 14.0 * G.DENSITY
    xy = cam.P(np.atleast_2d(points) * G.DENSITY)
    xy -= np.array([G.S.OX, G.S.OY])
    return xy + np.array(frame_spec(view)["origin"])


def projected_parts(pose, view) -> Dict[str, PartPose]:
    """Return rigid part pivots for one existing gen_cairn.Pose."""
    view = view_name(view)
    rig = G.Rig(pose, view)
    cam = G.S.Cam(view)
    result = {}

    def part(name, center, axis, start=None, end=None, forward=None):
        center = np.asarray(center, dtype=float)
        axis = np.asarray(axis, dtype=float)
        if start is None:
            start = center - axis / 2
        if end is None:
            end = center + axis / 2
        projected = _project([center, center + axis, start, end], view)
        delta = projected[1] - projected[0]
        angle = math.degrees(math.atan2(delta[1], delta[0]))
        yaw = 0.0 if forward is None else math.degrees(math.atan2(forward[0], forward[2]))
        result[name] = PartPose(tuple(projected[0]), angle,
                                float(center @ cam.cam) * G.DENSITY,
                                tuple(projected[2]), tuple(projected[3]),
                                tuple(center), yaw)

    for i, (name, _mat, _up, _radii) in enumerate(G.STONES):
        c = rig.on_stone(i, (0, 0, 0))[0]
        part(name, c, rig.stone_dir(i, (0, 1, 0))[0],
             forward=rig.stone_dir(i, (0, 0, 1))[0])

    for side, s, fist in (("near", 1.0, pose.near), ("far", -1.0, pose.far)):
        shoulder = rig.on_stone(G.CHEST, (s * 10.4, 1.8, 0))[0]
        if fist is None:
            glove = rig.on_stone(G.CHEST, (s * 5, 3.5, 9))[0]
        else:
            f = np.array([fist[0] * G.FIST_SPREAD, fist[1] - G.FIST_DROP, fist[2]])
            glove = rig.world(f + rig.move)[0]
        control = (shoulder + glove) / 2 + rig.stack_dir((s * 2.6, -3, -1.4))[0]
        q = lambda t: G._bez(shoulder, control, glove, t)
        upper, fore = q(.36), q(.66)
        part(side + "_shoulder", shoulder, rig.stone_dir(G.CHEST, (0, 1, 0))[0])
        part(side + "_upperarm", upper, q(.41) - q(.31), shoulder, q(.5))
        part(side + "_forearm", fore, q(.71) - q(.61), q(.5), glove)
        part(side + "_glove", glove, glove - fore, fore, glove)

    for side, s, foot in (("near", 1.0, pose.fn), ("far", -1.0, pose.ff)):
        if foot is None:
            center = rig.stack((s * 4.6, 2.0 - pose.lift, s * 2))[0]
            foot_axis = rig.stack_dir((0, 0, 1))[0]
            ankle = center + rig.stack_dir((0, 1.8, -.6))[0]
        else:
            f = np.asarray(foot) * (G.FOOT_SPREAD, 1, 1)
            center = rig.world(f + np.array([0, 0, pose.fwd]))[0]
            foot_axis = rig.world((0, 0, 1))[0] - rig.world((0, 0, 0))[0]
            ankle = center + rig.world((0, 1.8, -.6))[0] - rig.world((0, 0, 0))[0]
        hip = rig.on_stone(G.BASE, (s * 4.8, -1.5, .3))[0]
        control = (hip + ankle) / 2 + rig.stack_dir((s, 0, 1.4))[0]
        q = lambda t: G._bez(hip, control, ankle, t)
        # The geometric rig has three leg pebbles. A two-piece painted leg can
        # ignore knee, using thigh/shin endpoints to bridge the center joint.
        part(side + "_thigh", q(.2), q(.25) - q(.15), hip, q(.5))
        part(side + "_knee", q(.5), q(.55) - q(.45), q(.35), q(.65))
        part(side + "_shin", q(.8), q(.85) - q(.75), q(.5), ankle)
        part(side + "_foot", center, foot_axis)
    return result


def pose_frame(view, row, frame):
    """row accepts a sheet row index or its exact gen_cairn name."""
    if isinstance(row, str):
        poses = dict(ROWS)[row]
    else:
        if not 0 <= row < len(ROWS):
            raise IndexError(row)
        poses = ROWS[row][1]
    if not 0 <= frame < len(poses):
        raise IndexError(frame)
    return projected_parts(poses[frame], view)


def pose_metadata(row, frame):
    """Expression/turn keys for alternate painted heads and cloth overlap."""
    poses = dict(ROWS)[row] if isinstance(row, str) else ROWS[row][1]
    pose = poses[frame]
    return {key: getattr(pose, key) for key in
            ("yaw", "roll", "fall", "lean", "eyes", "mouth", "brow", "tail", "tail_up", "tail_amp")}


def _heading_artwork(heading):
    """Eight facing octants represented by five right-facing sources."""
    heading %= 360.0
    octant = int(math.floor((heading + 22.5) / 45.0)) % 8
    source, mirror = (("down", False), ("down_side", False),
                      ("side", False), ("up_side", False),
                      ("up", False), ("up_side", True),
                      ("side", True), ("down_side", True))[octant]
    return HeadArtwork(source, mirror, heading)


def head_artwork(view, row, frame):
    """Choose an existing head painting for full-turn fidgets/body yaw.

    Keep the destination view's head position and angle delta for tilt/fall.
    Use this source view's head pixels and its authored-pivot calibration offset
    (art center minus reference_pose(source_view)['head'].center). On a mirror,
    flip the pixels, negate that offset's x, and change the local pivot x to
    width - 1 - pivot_x. Rotate the resulting offset by the destination head's
    screen-clockwise angle delta before adding the current destination pivot.

    Logical yaw keys are intentional here: deriving yaw from the projected head
    normal would incorrectly switch to its back as the head falls during KO.
    Remove the idle head's own yaw so every approved idle source stays itself.
    """
    view = view_name(view)
    poses = dict(ROWS)[row] if isinstance(row, str) else ROWS[row][1]
    pose = poses[frame]
    rest = ROWS[0][1][0]
    base = {"down": 0.0, "down_side": 45.0, "side": 90.0,
            "up_side": 135.0, "up": 180.0}[view]
    delta = pose.yaw + pose.tilt[G.HEAD][2] - rest.yaw - rest.tilt[G.HEAD][2]
    return _heading_artwork(base + delta)


def reference_pose(view):
    return pose_frame(view, "idle", 0)


def relative_pose(view, row, frame):
    """Return (translation, clockwise angle delta, depth) per rigid part.

    No scaling is supplied: Cairn's stones must stay rigid. Draw each cropped
    part about its authored pivot, translated by this delta from idle frame 0.
    """
    ref, cur = reference_pose(view), pose_frame(view, row, frame)
    return {name: ((p.center[0] - ref[name].center[0], p.center[1] - ref[name].center[1]),
                   (p.angle_degrees - ref[name].angle_degrees + 180) % 360 - 180, p.depth)
            for name, p in cur.items()}


def artwork_transform(reference, current, artwork_center):
    """Return (target art center, PIL rotation angle) preserving rigid offsets.

    Merely adding rig translations leaves an artwork pivot's calibration offset
    upright during knockout. Rotate that offset along with the stone instead.
    Pillow rotate is counterclockwise, opposite to our screen-space angle.
    No resize/scale is needed or permitted for rigid stone artwork.
    """
    delta = (current.angle_degrees - reference.angle_degrees + 180) % 360 - 180
    radians = math.radians(delta)
    c, s = math.cos(radians), math.sin(radians)
    offset = np.asarray(artwork_center) - np.asarray(reference.center)
    offset = np.array([[c, -s], [s, c]]) @ offset
    return tuple(np.asarray(current.center) + offset), -delta


def check():
    """Check every transform and independently capture build()'s glove pivots."""
    checked = 0
    for view in VIEWS:
        expected = set(reference_pose(view))
        assert len(expected) == 20
        for row, poses in ROWS:
            for i, pose in enumerate(poses):
                parts = pose_frame(view, row, i)
                assert set(parts) == expected
                for p in parts.values():
                    assert np.isfinite([*p.center, p.angle_degrees, p.depth, *p.start, *p.end]).all()
                checked += 1
        for row, index in (("idle", 0), ("jab", 3), ("ko", 2)):
            captured = {}
            original = G._glove
            def capture(fw, direction, sign):
                captured["near" if sign > 0 else "far"] = np.array(fw)
                return []
            try:
                G._glove = capture
                G.build(dict(ROWS)[row][index], view)
            finally:
                G._glove = original
            adapted = pose_frame(view, row, index)
            for side, center in captured.items():
                assert np.allclose(center, adapted[side + "_glove"].world_center)
                assert np.allclose(_project(center, view)[0], adapted[side + "_glove"].center)
    for view in VIEWS:
        for delta, angle, _depth in relative_pose(view, "idle", 0).values():
            assert delta == (0.0, 0.0) and angle == 0.0
        idle_head = head_artwork(view, "idle", 0)
        assert idle_head.source_view == view and not idle_head.mirror
    expected_head_views = ["down", "down_side", "side", "up_side", "up", "up_side", "side", "down_side"]
    for octant, expected in enumerate(expected_head_views):
        choice = _heading_artwork(45 * octant)
        assert choice.source_view == expected and choice.mirror == (octant > 4)
        assert _heading_artwork(45 * octant + 360) == choice
    fidget_sources = {(head_artwork("side", "idle_alt", i).source_view,
                       head_artwork("side", "idle_alt", i).mirror)
                      for i in range(frame_counts()["idle_alt"])}
    assert len(fidget_sources) >= 4, fidget_sources
    print("Cairn cut-out poses: %d frames; finite transforms, idle identity, glove pivots match." % checked)


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["--check"]:
        check()
    else:
        print(frame_counts())
