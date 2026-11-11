# Purpose: developer-time script (numpy only, no Blender). Sews new skinned clothes pieces from the Quaternius CC0
# outfit models' own surfaces, so the same two outfits become many (round 4, item 28). Recipes: data/wear.json.
# A SHELL copies chosen faces of the clothes and pushes them out a few millimetres (gloves, belt, bracers, vest,
# breastplate, scarf): it keeps those faces' bone weights, so it moves exactly like the clothes under it. A SHEET is
# a new panel hung round the body (apron, skirt, cloak): its outline follows the body's own silhouette row by row,
# its bone weights come from the nearest spot of the clothes and are stiffened towards one bone further down.
# Output: assets/models/outfits/wear/<piece>_<base>_<body>.gltf + .bin on the SAME skeleton as the outfit (nodes and
# skin copied), one surface per material kind (cloth, leather, metal ...: the fantasy props' materials, colours per
# corner as tools/blender/fantasy_kit.py `real` stores them). game/rigged_body.gd adopts them onto a character.
# Run: python3 tools/tailor.py   (from the project folder)
import json
import math
import os
import struct

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
PACK = os.path.join(ROOT, "assets/cc0/packs/modular_character_outfits_fantasy_standard/exports_gltf_godot_unreal_outfits/")
OUT = os.path.join(ROOT, "assets/models/outfits/wear/")
RULES = os.path.join(ROOT, "data/wear.json")
BASES = {"peasant": {"female": "Female_Peasant", "male": "Male_Peasant"}, "ranger": {"female": "Female_Ranger", "male": "Male_Ranger"}}
ARM = ("clavicle", "upperarm", "lowerarm", "hand", "index", "middle", "ring", "pinky", "thumb")
NEXT = {"upperarm": "lowerarm", "lowerarm": "hand", "thigh": "calf", "calf": "foot"}
TYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def real(rgb):
    """The same sum as tools/blender/fantasy_kit.py `real`: a colour chosen by eye, calmed and screen-encoded."""
    lin = [max(v, 0.0) ** 2.2 for v in rgb]
    lum = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
    return tuple(((lum + (v - lum) * 0.7) * 0.62) ** (1 / 2.2) for v in lin)


def base_name(bone):
    """A bone's plain name: left and right together, every joint of a finger (and its tip) under the finger's name."""
    if bone.split("_")[0] in ("index", "middle", "ring", "pinky", "thumb"):
        return bone.split("_")[0]
    return bone[:-2] if bone.endswith(("_l", "_r")) else bone


class Donor:
    """One outfit model: every corner of its clothes with its bones, and where each bone is at rest."""

    def __init__(self, name):
        self.name = name
        self.gltf = json.load(open(PACK + name + ".gltf"))
        self.blob = open(PACK + self.gltf["buffers"][0]["uri"], "rb").read()
        g = self.gltf
        skin = g["skins"][0]
        self.bones = [g["nodes"][j]["name"] for j in skin["joints"]]
        binds = self.read(skin["inverseBindMatrices"]).reshape(-1, 4, 4)
        self.rest = {}
        for i, bone in enumerate(self.bones):  # stored column by column: its transpose is the usual matrix
            self.rest[bone] = np.linalg.inv(binds[i].T.astype(np.float64))[:3, 3]
        pos, nrm, joints, weights, tris = [], [], [], [], []
        start = 0
        for node in g["nodes"]:
            if "mesh" not in node:
                continue
            for prim in g["meshes"][node["mesh"]]["primitives"]:
                a = prim["attributes"]
                p = self.read(a["POSITION"])
                pos.append(p)
                nrm.append(self.read(a["NORMAL"]))
                joints.append(self.read(a["JOINTS_0"]).astype(np.int64))
                w = self.read(a["WEIGHTS_0"]).astype(np.float64)
                weights.append(w / np.maximum(w.sum(axis=1, keepdims=True), 1e-9))
                tris.append(self.read(prim["indices"]).astype(np.int64).reshape(-1, 3) + start)
                start += len(p)
        self.pos = np.concatenate(pos).astype(np.float64)
        self.nrm = np.concatenate(nrm).astype(np.float64)
        self.joints = np.concatenate(joints)
        self.weights = np.concatenate(weights)
        self.tris = np.concatenate(tris)
        lead = self.joints[np.arange(len(self.pos)), self.weights.argmax(axis=1)]
        self.lead = np.array([self.bones[j] for j in lead])  # the bone each corner follows most
        self.lead_base = np.array([base_name(b) for b in self.lead])
        self.arm = np.isin(self.lead_base, ARM)
        self.middle = self.rest["pelvis"][[0, 2]]

    def read(self, index):
        acc = self.gltf["accessors"][index]
        view = self.gltf["bufferViews"][acc["bufferView"]]
        kind = TYPES[acc["componentType"]]
        width = WIDTH[acc["type"]]
        offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        step = view.get("byteStride", 0)
        size = np.dtype(kind).itemsize * width
        if step and step != size:
            rows = [np.frombuffer(self.blob, kind, width, offset + i * step) for i in range(acc["count"])]
            out = np.array(rows)
        else:
            out = np.frombuffer(self.blob, kind, acc["count"] * width, offset).reshape(acc["count"], width)
        if acc.get("normalized"):
            out = out.astype(np.float64) / np.iinfo(kind).max
        return out if width > 1 else out.reshape(-1)

    def height(self, spec):
        """[bone, metres above it] -> a height in the model."""
        bone = spec[0] if spec[0] in self.rest else spec[0] + "_l"
        return float(self.rest[bone][1]) + float(spec[1])


def shell(d, spec):
    """Faces of the clothes that follow the named bones (optionally within a band of heights or a stretch along a
    limb), pushed out along their normals."""
    keep = np.ones(len(d.pos), bool)
    if "bones" in spec:
        keep &= np.isin(d.lead_base, spec["bones"])
    if "band" in spec:
        keep &= (d.pos[:, 1] >= d.height(spec["band"][0])) & (d.pos[:, 1] <= d.height(spec["band"][1]))
    if spec.get("no_arms"):
        keep &= ~d.arm
    if "along" in spec:  # only part of the way along each limb bone: 0 = its own joint, 1 = the next joint
        part = np.zeros(len(d.pos))
        for bone in set(d.lead[keep]):
            stem = base_name(bone)
            if stem not in NEXT:
                continue
            a = d.rest[bone]
            b = d.rest[NEXT[stem] + bone[-2:]]
            mine = d.lead == bone
            part[mine] = (d.pos[mine] - a) @ (b - a) / float((b - a) @ (b - a))
        keep &= (part >= spec["along"][0]) & (part <= spec["along"][1])
    if "front" in spec:  # only what faces forward (1) or backward (-1)
        keep &= d.nrm[:, 2] * spec["front"] > 0.15
    faces = d.tris[keep[d.tris].all(axis=1)]
    used = np.unique(faces)
    remap = -np.ones(len(d.pos), np.int64)
    remap[used] = np.arange(len(used))
    pos = d.pos[used] + d.nrm[used] * float(spec.get("grow", 0.005))
    uv = np.stack([pos[:, 0] + pos[:, 2], pos[:, 1]], axis=1) * 5.0  # a fine weave: the cloth's picture repeats every 20 cm
    return {"pos": pos, "nrm": d.nrm[used], "uv": uv, "joints": d.joints[used], "weights": d.weights[used], "tris": remap[faces]}


def sheet(d, spec):
    """A panel hung round the body between two heights and two bearings (degrees, 0 = straight ahead, 90 = the
    body's left): each row stands just outside the body's outline there and never hangs inwards."""
    top, bottom = d.height(spec["top"]), d.height(spec["bottom"])
    a0, a1 = [math.radians(v) for v in spec["arc"]]
    rows = max(2, int(round((top - bottom) / 0.07)) + 1)
    cols = max(2, int(round(abs(a1 - a0) / math.radians(12))) + 1)
    whole = abs(a1 - a0) >= math.radians(359)
    body = ~d.arm if not spec.get("with_arms") else np.ones(len(d.pos), bool)
    rel = d.pos[:, [0, 2]] - d.middle
    bearing = np.arctan2(rel[:, 0], rel[:, 1])
    reach = np.hypot(rel[:, 0], rel[:, 1])
    angles = np.linspace(a0, a1, cols)
    radius = np.zeros((rows, cols))
    for r in range(rows):
        y = top + (bottom - top) * r / (rows - 1)
        near = body & (np.abs(d.pos[:, 1] - y) < 0.05)
        for k, angle in enumerate(angles):
            off = np.abs((bearing - angle + math.pi) % (2 * math.pi) - math.pi)
            hit = near & (off < math.radians(22))
            radius[r, k] = reach[hit].max() if hit.any() else 0.0
        for _again in range(2):  # no dents between the legs or under the arms
            side = np.roll(radius[r], 1), np.roll(radius[r], -1)
            if not whole:
                side[0][0], side[1][-1] = radius[r, 0], radius[r, -1]
            radius[r] = np.maximum(radius[r], (side[0] + side[1]) / 2)
        grow = float(spec.get("fit", 0.006)) + (float(spec.get("loose", 0.02)) - float(spec.get("fit", 0.006))) * min(1.0, r / 3.0)
        radius[r] += grow
        if r > 0:  # cloth hangs: below a wider place it comes back in only by `taper` a row (0 = never), and it flares a little
            radius[r] = np.maximum(radius[r], radius[r - 1] + float(spec.get("flare", 0.004)) - float(spec.get("taper", 0.0)))
    pos = np.zeros((rows, cols, 3))
    for r in range(rows):
        y = top + (bottom - top) * r / (rows - 1)
        pos[r, :, 0] = d.middle[0] + np.sin(angles) * radius[r]
        pos[r, :, 1] = y
        pos[r, :, 2] = d.middle[1] + np.cos(angles) * radius[r]
    flat = pos.reshape(-1, 3)
    donors = np.where(body)[0]
    joints = np.zeros((len(flat), 4), np.int64)
    weights = np.zeros((len(flat), 4))
    stiff_bone = d.bones.index(spec.get("stiff_bone", "pelvis"))
    for i, p in enumerate(flat):
        row = i // cols
        nearest = donors[np.argmin(((d.pos[donors] - p) ** 2).sum(axis=1))]
        share = {}
        for j, w in zip(d.joints[nearest], d.weights[nearest]):
            share[int(j)] = share.get(int(j), 0.0) + float(w)
        hold = float(spec.get("stiff", 0.45)) * min(1.0, row / max(1.0, rows * 0.4))
        share = {j: w * (1.0 - hold) for j, w in share.items()}
        share[stiff_bone] = share.get(stiff_bone, 0.0) + hold
        best = sorted(share.items(), key=lambda e: -e[1])[:4]
        total = sum(w for _j, w in best)
        for k, (j, w) in enumerate(best):
            joints[i, k], weights[i, k] = j, w / total
    out_dir = flat - np.array([d.middle[0], 0.0, d.middle[1]])
    out_dir[:, 1] = 0.0
    nrm = out_dir / np.maximum(np.linalg.norm(out_dir, axis=1, keepdims=True), 1e-9)
    tris = []
    for r in range(rows - 1):
        for k in range(cols - 1):
            a, b, c, e = r * cols + k, r * cols + k + 1, (r + 1) * cols + k, (r + 1) * cols + k + 1
            tris += [(a, c, b), (b, c, e)]
    tris = np.array(tris)
    if (np.cross(flat[tris[0, 1]] - flat[tris[0, 0]], flat[tris[0, 2]] - flat[tris[0, 0]]) @ nrm[tris[0, 0]]) < 0:
        tris = tris[:, ::-1]
    uv = np.stack([np.tile(angles, rows) * 0.3, flat[:, 1]], axis=1) * 5.0
    inner = flat - nrm * 0.006  # a lining, so the cloth is seen from behind as well
    count = len(flat)
    return {"pos": np.concatenate([flat, inner]), "nrm": np.concatenate([nrm, -nrm]), "uv": np.concatenate([uv, uv]),
        "joints": np.concatenate([joints, joints]), "weights": np.concatenate([weights, weights]), "tris": np.concatenate([tris, tris[:, ::-1] + count])}


def write(d, name, parts):
    """One file on the donor's own skeleton: `parts` = [(kind, colour, mesh arrays)], a surface for each."""
    g = d.gltf
    out = {"asset": g["asset"], "scene": g.get("scene", 0), "scenes": g["scenes"], "nodes": [dict(n) for n in g["nodes"]], "skins": [dict(g["skins"][0])],
        "materials": [], "meshes": [{"name": name, "primitives": []}], "accessors": [], "bufferViews": [], "buffers": []}
    blob = bytearray()

    def add(data, kind, shape, target=None, bounds=False):
        data = np.ascontiguousarray(data, dtype=kind)
        while len(blob) % 4:
            blob.append(0)
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": data.nbytes}
        if target:
            view["target"] = target
        blob.extend(data.tobytes())
        out["bufferViews"].append(view)
        acc = {"bufferView": len(out["bufferViews"]) - 1, "componentType": {np.float32: 5126, np.uint16: 5123, np.uint32: 5125}[kind], "count": len(data), "type": shape}
        if bounds:
            acc["min"], acc["max"] = [float(v) for v in data.min(axis=0)], [float(v) for v in data.max(axis=0)]
        out["accessors"].append(acc)
        return len(out["accessors"]) - 1

    out["skins"][0]["inverseBindMatrices"] = add(d.read(g["skins"][0]["inverseBindMatrices"]).reshape(-1, 16), np.float32, "MAT4")
    for node in out["nodes"]:  # the donor's own clothes are not part of this file
        node.pop("mesh", None)
        node.pop("skin", None)
    for kind, color, mesh in parts:
        if len(mesh["tris"]) == 0:
            continue
        shade = np.clip((mesh["pos"][:, 1:2] - mesh["pos"][:, 1].min()) / 0.25, 0.0, 1.0) * 0.14 + 0.86  # a darker hem
        colors = np.concatenate([np.array(real(color))[None, :] * shade, np.ones((len(mesh["pos"]), 1))], axis=1)
        attributes = {"POSITION": add(mesh["pos"], np.float32, "VEC3", 34962, True), "NORMAL": add(mesh["nrm"], np.float32, "VEC3", 34962),
            "TEXCOORD_0": add(mesh["uv"], np.float32, "VEC2", 34962), "COLOR_0": add(colors, np.float32, "VEC4", 34962),
            "JOINTS_0": add(mesh["joints"], np.uint16, "VEC4", 34962), "WEIGHTS_0": add(mesh["weights"], np.float32, "VEC4", 34962)}
        out["materials"].append({"name": kind, "doubleSided": True, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.9}})
        out["meshes"][0]["primitives"].append({"attributes": attributes, "indices": add(mesh["tris"].reshape(-1), np.uint32, "SCALAR", 34963), "material": len(out["materials"]) - 1})
    holder = next(i for i, n in enumerate(g["nodes"]) if "mesh" in n)
    out["nodes"][holder].update({"name": name, "mesh": 0, "skin": 0})
    out["buffers"].append({"byteLength": len(blob), "uri": name + ".bin"})
    os.makedirs(OUT, exist_ok=True)
    open(OUT + name + ".bin", "wb").write(bytes(blob))
    json.dump(out, open(OUT + name + ".gltf", "w"))
    return sum(len(mesh["tris"]) for _k, _c, mesh in parts)


def main():
    rules = json.load(open(RULES))
    for base, models in BASES.items():
        for body, model in models.items():
            d = Donor(model)
            if body == "female" and base == "peasant":
                print("heights (female settler):", {b: round(float(d.rest[b][1]), 2) for b in ("Head", "neck_01", "spine_03", "spine_02", "spine_01", "pelvis", "calf_l", "foot_l")}, "tallest corner", round(float(d.pos[:, 1].max()), 2))
            for piece, recipe in rules["pieces"].items():
                if "bases" in recipe and base not in recipe["bases"]:
                    continue
                parts = []
                for part in recipe["parts"]:
                    mesh = shell(d, part["shell"]) if "shell" in part else sheet(d, part["sheet"])
                    parts.append((part["kind"], part["color"], mesh))
                count = write(d, "%s_%s_%s" % (piece, base, body), parts)
                print("%s_%s_%s: %d triangles" % (piece, base, body, count))


if __name__ == "__main__":
    main()
