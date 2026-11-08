"""Acceptance checks for Cairn cut-out assets and all authored animation frames.

Run: python tools/test_cairn_cutout.py
These checks cannot judge anatomy or animation feel; inspect the proof GIFs too.
"""
import json
from pathlib import Path
import unittest

import numpy as np
from PIL import Image

import cairn_cutout_pose as poses
import cairn_cutout_parts as parts
import gen_cairn_cutout as renderer
import palette


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/sprites/source/cairn_cutout"
SOURCES = {"side": "side", "down": "front", "up": "back",
           "down_side": "front_34", "up_side": "back_34"}
ANCHORS = {"side": (92,168), "down": (96,156), "up": (96,168),
           "down_side": (88,160), "up_side": (88,168)}


def opaque_colors(image):
    pixels = np.array(image)
    return {tuple(map(int, rgb)) for rgb in pixels[pixels[:,:,3] > 0, :3]}


class CairnCutoutTests(unittest.TestCase):
    def test_existing_animation_contract(self):
        sprite = json.loads((ROOT/"data/creatures/cairn.json").read_text())["sprite"]
        expected = {name: value[2] for name,value in sprite["anims"].items()}
        self.assertEqual(poses.frame_counts(), expected)
        self.assertEqual(sum(expected.values()) * len(SOURCES), 650)
        for view, anchor in ANCHORS.items():
            with self.subTest(view=view):
                spec = poses.frame_spec(view)
                self.assertEqual((spec["w"],spec["h"]),(192,192))
                self.assertEqual(tuple(spec["origin"]), anchor)

    def test_approved_sources_have_game_ready_pixels(self):
        allowed = {tuple(c) for c in palette.ALL}
        for view, name in SOURCES.items():
            with self.subTest(view=view):
                image = Image.open(SOURCE/(name+".png")).convert("RGBA")
                self.assertEqual(image.size,(192,192))
                self.assertEqual(set(np.unique(np.array(image)[:,:,3])),{0,255})
                bounds = image.getbbox()
                self.assertEqual(bounds[3]-bounds[1],110)
                self.assertEqual(bounds[3]-1,ANCHORS[view][1])
                self.assertTrue(opaque_colors(image) <= allowed)

    def test_parts_and_reference_transform(self):
        allowed = {tuple(c) for c in palette.ALL}
        for view in SOURCES:
            reference = poses.reference_pose(view)
            for name,part in parts.load_parts(view).items():
                with self.subTest(view=view,part=name):
                    self.assertIn(name,reference)
                    im = part["image"]
                    self.assertEqual(im.mode,"RGBA")
                    self.assertIsNotNone(im.getbbox())
                    # alpha 254 marks a completed (fill) pixel; the renderer makes it 255
                    self.assertTrue(set(np.unique(np.array(im)[:,:,3])) <= {0,254,255})
                    self.assertTrue(opaque_colors(im) <= allowed)
                    target,angle = poses.artwork_transform(reference[name],reference[name],part["center"])
                    self.assertTrue(np.allclose(target,part["center"]))
                    self.assertEqual(angle,0)
                    self.assertTrue(np.isfinite(part["pivot"]).all())

    def test_rigid_offset_follows_quarter_turn(self):
        from dataclasses import replace
        reference = poses.reference_pose("side")["head"]
        current = replace(reference,center=(100.,80.),angle_degrees=reference.angle_degrees+90.)
        target,angle = poses.artwork_transform(reference,current,
                                              (reference.center[0]+5,reference.center[1]))
        self.assertTrue(np.allclose(target,(100.,85.)))
        self.assertEqual(angle,-90.)

    def test_idle_reference_preserves_approved_pixels(self):
        for view, filename in SOURCES.items():
            with self.subTest(view=view):
                source=np.array(Image.open(SOURCE/(filename+".png")).convert("RGBA"))
                image,_=renderer.render(view,"idle",0)
                rendered=np.array(image)
                # RGB in fully transparent pixels has no visible meaning.
                source[source[:,:,3]==0]=0
                rendered[rendered[:,:,3]==0]=0
                changed=np.any(source!=rendered,axis=2)
                self.assertEqual(int(changed.sum()),0)

    def test_every_frame_fits_and_retains_palette(self):
        allowed = {tuple(c) for c in palette.ALL}
        failures=[]
        sprite = json.loads((ROOT/"data/creatures/cairn.json").read_text())["sprite"]
        side_only = sprite.get("side_only", [])
        for view in SOURCES:
            for row,count in poses.frame_counts().items():
                if row not in renderer.READY_ROWS:continue
                if view != "side" and row in side_only:continue   # never drawn in that view
                for index in range(count):
                    image,trace=renderer.render(view,row,index)
                    label=f"{view}/{row}/{index}"
                    if image.size!=(192,192):failures.append(label+" wrong canvas")
                    pixels=np.array(image)
                    if not set(np.unique(pixels[:,:,3])) <= {0,255}:failures.append(label+" soft alpha")
                    if not opaque_colors(image)<=allowed:failures.append(label+" off-palette")
                    if image.getbbox() is None:failures.append(label+" empty frame")
                    for name,transform in trace.items():
                        b=transform.get("bounds")
                        if b and (b[0]<1 or b[1]<1 or b[2]>191 or b[3]>191):
                            failures.append(f"{label}/{name}: exceeds margin {b}")
        self.assertEqual(len(failures),0,"\n".join(failures[:40])+f"\nTotal failures: {len(failures)}")


if __name__ == "__main__":
    unittest.main()
