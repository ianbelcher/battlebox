#!/usr/bin/env python3
"""Cut the 30 "Little People in Voxel" characters into rigged body parts.

The shipped art is a single MagicaVoxel file (``little_people_in_voxel_v2.zip``,
gitignored beside this tool) holding 30 models. Exported whole they are one
static mesh each, so they can't animate. Luckily all 30 share one construction:

    z 0..hips   two leg columns with a gap between them
    z hips..13  torso, with arms sitting outside the legs' x range
    z 14..top   head (hats, hair and brims included)

So we slice each model into Body / ArmL / ArmR / LegL / LegR, mesh each part
into its own OBJ, and let ``player.gd``'s existing ``_swing_limb`` drive them.
Parts share one 256x1 palette texture, exactly like a MagicaVoxel OBJ export.

Coordinates: MagicaVoxel is Z-up with the face at low y; Godot is Y-up with
the character facing -Z. ``(vx, vy, vz) -> (-x, z, y)`` keeps the handedness
and lands the face on -Z. Output is in VOXEL units with the feet at y=0 and
the body centred on x/z, so ``avatar_factory.gd`` picks the display scale.

Usage:  python3 tools/rig_people.py [--vox FILE] [--out DIR]
"""

import argparse
import os
import struct
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
WORLD = os.path.dirname(HERE)
DEFAULT_ZIP = os.path.join(WORLD, "little_people_in_voxel_v2.zip")
DEFAULT_OUT = os.path.join(WORLD, "game", "assets", "models", "people")

## Head starts here in every one of the 30 models (verified: the layer at
## z=14 is a 2x2 neck in 24 of them, and the head's underside in the rest).
NECK_Z = 14
## Arms live below the head; above this is hat brim, not shoulder.
ARM_TOP_Z = 13
PORTRAIT = 64


# ----------------------------------------------------------------- vox
def read_vox(data):
    """Return (models, palette). Each model is {'size': (x,y,z), 'vox': {}}."""
    assert data[:4] == b"VOX ", "not a MagicaVoxel file"
    chunks = []

    def walk(pos, end):
        while pos < end:
            cid = data[pos:pos + 4].decode("ascii")
            n, m = struct.unpack("<II", data[pos + 4:pos + 12])
            pos += 12
            chunks.append((cid, data[pos:pos + n]))
            pos += n
            if m:
                walk(pos, pos + m)
                pos += m
        return pos

    walk(20, 20 + struct.unpack("<I", data[16:20])[0])

    models, size, palette = [], None, None
    for cid, c in chunks:
        if cid == "SIZE":
            size = struct.unpack("<III", c[:12])
        elif cid == "XYZI":
            n = struct.unpack("<I", c[:4])[0]
            vox = {}
            for i in range(n):
                x, y, z, ci = c[4 + i * 4:8 + i * 4]
                vox[(x, y, z)] = ci
            models.append({"size": size, "vox": vox})
        elif cid == "RGBA":
            # MagicaVoxel writes palette entry i at index i-1.
            rgba = [tuple(c[i * 4:i * 4 + 4]) for i in range(256)]
            palette = [(0, 0, 0, 0)] + rgba[:255]
    return models, palette


# ------------------------------------------------------------ splitting
def split_parts(model):
    """Classify every voxel into body / arm-l / arm-r / leg-l / leg-r."""
    vox = model["vox"]
    sz = model["size"][2]

    feet = [x for (x, _y, z) in vox if z == 0]
    leg_lo, leg_hi = min(feet), max(feet)
    # Hips: the first layer where the gap between the two leg columns closes.
    hips = sz
    for z in range(sz):
        filled = set(x for (x, _y, zz) in vox if zz == z and leg_lo <= x <= leg_hi)
        if all(x in filled for x in range(leg_lo, leg_hi + 1)):
            hips = z
            break
    mid = (leg_lo + leg_hi + 1) / 2.0

    parts = {k: {} for k in ("body", "arm-l", "arm-r", "leg-l", "leg-r")}
    for (x, y, z), ci in vox.items():
        if z <= ARM_TOP_Z and not (leg_lo <= x <= leg_hi):
            key = "arm"
        elif z < hips and z < NECK_Z:
            key = "leg"
        else:
            key = "body"
        if key == "body":
            parts["body"][(x, y, z)] = ci
        else:
            # Godot mirrors x, so the character's LEFT is high vox-x.
            parts["%s-%s" % (key, "l" if x >= mid else "r")][(x, y, z)] = ci
    return parts, (leg_lo, leg_hi, hips)


# --------------------------------------------------------------- meshing
# Face directions in VOXEL space: (axis, step). Culling is done per part so
# every part stays a closed solid — a swinging arm must not show a hole.
FACES = [(0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1)]


def greedy_quads(voxels):
    """Face-cull then greedily merge coplanar same-colour faces into quads.

    Yields (axis, step, slice_index, u0, v0, u1, v1, colour_index) where u/v
    are the two axes other than ``axis``, in ascending order.
    """
    for axis, step in FACES:
        u_axis, v_axis = [a for a in (0, 1, 2) if a != axis]
        # Group exposed faces by slice.
        slices = {}
        for pos, ci in voxels.items():
            nb = list(pos)
            nb[axis] += step
            if tuple(nb) in voxels:
                continue
            slices.setdefault(pos[axis], {})[(pos[u_axis], pos[v_axis])] = ci
        for s, mask in sorted(slices.items()):
            done = set()
            for (u, v) in sorted(mask):
                if (u, v) in done:
                    continue
                ci = mask[(u, v)]
                # Grow along u, then along v as a full row.
                w = 1
                while mask.get((u + w, v)) == ci and (u + w, v) not in done:
                    w += 1
                h = 1
                while True:
                    row = [(u + i, v + h) for i in range(w)]
                    if any(mask.get(p) != ci or p in done for p in row):
                        break
                    h += 1
                for i in range(w):
                    for j in range(h):
                        done.add((u + i, v + j))
                yield (axis, step, s, u, v, u + w, v + h, ci)


def to_godot(vx, vy, vz, origin):
    """Voxel corner -> Godot-space vertex, in voxel units."""
    ox, oy = origin
    return (-(vx - ox), vz, (vy - oy))


## Voxel-space face normals mapped through to_godot()'s linear part.
GODOT_NORMAL = {(0, 1): (-1, 0, 0), (0, -1): (1, 0, 0),
                (1, 1): (0, 0, 1), (1, -1): (0, 0, -1),
                (2, 1): (0, 1, 0), (2, -1): (0, -1, 0)}


def part_obj(name, voxels, origin):
    """Wavefront OBJ text for one body part."""
    lines = ["# generated by tools/rig_people.py — do not edit",
             "mtllib people.mtl", "o %s" % name, "usemtl palette"]
    verts, uvs, faces = [], [], []
    vcache, tcache = {}, {}
    normals = list(GODOT_NORMAL.values())

    def vid(p):
        if p not in vcache:
            verts.append(p)
            vcache[p] = len(verts)
        return vcache[p]

    def tid(ci):
        if ci not in tcache:
            uvs.append((ci + 0.5) / 256.0)
            tcache[ci] = len(uvs)
        return tcache[ci]

    for axis, step, s, u0, v0, u1, v1, ci in greedy_quads(voxels):
        u_axis, v_axis = [a for a in (0, 1, 2) if a != axis]
        plane = s + (1 if step > 0 else 0)
        corners = []
        for (u, v) in ((u0, v0), (u1, v0), (u1, v1), (u0, v1)):
            c = [0, 0, 0]
            c[axis] = plane
            c[u_axis] = u
            c[v_axis] = v
            corners.append(to_godot(c[0], c[1], c[2], origin))
        # Wind every quad the same way round its outward normal rather than
        # reasoning per axis: cross the first two edges and flip if it points
        # inwards. Godot treats counter-clockwise-from-outside as the front.
        n = GODOT_NORMAL[(axis, step)]
        a = [corners[1][k] - corners[0][k] for k in range(3)]
        b = [corners[2][k] - corners[0][k] for k in range(3)]
        cross = (a[1] * b[2] - a[2] * b[1],
                 a[2] * b[0] - a[0] * b[2],
                 a[0] * b[1] - a[1] * b[0])
        if sum(cross[k] * n[k] for k in range(3)) < 0:
            corners.reverse()
        t = tid(ci)
        nid = normals.index(n) + 1
        faces.append([(vid(c), t, nid) for c in corners])

    for p in verts:
        lines.append("v %g %g %g" % p)
    for u in uvs:
        lines.append("vt %.7f 0.5" % u)
    for n in normals:
        lines.append("vn %d %d %d" % n)
    for f in faces:
        lines.append("f " + " ".join("%d/%d/%d" % vtn for vtn in f))
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------------- png
def write_png(path, width, height, rows):
    """rows: list of rows, each a list of (r,g,b,a) tuples."""
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in rows)

    def chunk(tag, body):
        c = tag + body
        return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)


def portrait(model, palette):
    """Front-on pixel render of a character, letterboxed into 64x64."""
    sx, sy, sz = model["size"]
    vox = model["vox"]
    scale = max(1, min(PORTRAIT // sx, PORTRAIT // sz))
    w, h = sx * scale, sz * scale
    pad_x, pad_y = (PORTRAIT - w) // 2, (PORTRAIT - h) // 2
    blank = (0, 0, 0, 0)
    rows = []
    for py in range(PORTRAIT):
        row = []
        for px in range(PORTRAIT):
            gx, gy = px - pad_x, py - pad_y
            if not (0 <= gx < w and 0 <= gy < h):
                row.append(blank)
                continue
            # Mirror x to match the in-game view, and flip z (png is top-down).
            vx = sx - 1 - gx // scale
            vz = sz - 1 - gy // scale
            hit = next((vox[(vx, y, vz)] for y in range(sy)
                        if (vx, y, vz) in vox), None)
            row.append(blank if hit is None else palette[hit])
        rows.append(row)
    return rows


IMPORT_MESH = """[remap]

importer="wavefront_obj"
importer_version=1
type="Mesh"

[deps]

source_file="res://assets/models/people/%s"

[params]

generate_tangents=true
generate_lods=true
generate_shadow_mesh=true
generate_lightmap_uv2=false
generate_lightmap_uv2_texel_size=0.2
scale_mesh=Vector3(1, 1, 1)
offset_mesh=Vector3(0, 0, 0)
force_disable_mesh_compression=false
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vox", default=DEFAULT_ZIP)
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    if args.vox.endswith(".zip"):
        with zipfile.ZipFile(args.vox) as zf:
            name = next(n for n in zf.namelist() if n.endswith(".vox"))
            data = zf.read(name)
    else:
        data = open(args.vox, "rb").read()

    models, palette = read_vox(data)
    print("%d models, palette %d" % (len(models), len(palette)))
    os.makedirs(args.out, exist_ok=True)

    write_png(os.path.join(args.out, "people-palette.png"), 256, 1, [palette])
    with open(os.path.join(args.out, "people.mtl"), "w") as fh:
        fh.write("# generated by tools/rig_people.py\n\n"
                 "newmtl palette\nillum 1\n"
                 "Ka 0.000 0.000 0.000\nKd 1.000 1.000 1.000\n"
                 "Ks 0.000 0.000 0.000\nmap_Kd people-palette.png\n")

    for i, model in enumerate(models):
        sx, sy, _sz = model["size"]
        origin = (sx / 2.0, sy / 2.0)
        parts, (lo, hi, hips) = split_parts(model)
        counts = {k: len(v) for k, v in parts.items()}
        if min(counts[k] for k in ("arm-l", "arm-r", "leg-l", "leg-r")) == 0:
            print("  !! Character-%d missing a limb: %s" % (i, counts))
        for key, voxels in parts.items():
            if not voxels:
                continue
            fname = "Character-%d-%s.obj" % (i, key)
            with open(os.path.join(args.out, fname), "w") as fh:
                fh.write(part_obj(key, voxels, origin))
            imp = os.path.join(args.out, fname + ".import")
            if not os.path.exists(imp):
                with open(imp, "w") as fh:
                    fh.write(IMPORT_MESH % fname)
        write_png(os.path.join(args.out, "Character-%d.png" % i),
                  PORTRAIT, PORTRAIT, portrait(model, palette))
        print("  Character-%-2d legs x%d..%d hips z%d  %s"
              % (i, lo, hi, hips, counts))


if __name__ == "__main__":
    sys.exit(main())
