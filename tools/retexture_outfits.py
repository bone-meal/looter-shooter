# Purpose: developer-time re-texture of the rigged outfits (polish1 item 7). The CC0 pack's two outfit materials
# (MI_Peasant, MI_Ranger) are smooth painted colour with soft folds, which reads as plastic in the realistic light.
# This bakes real material detail into new 2048 maps on the SAME UV layout: every texel is sorted into cloth, leather
# or metal by the pack's own roughness / metal map (smoothed so a garment part stays one material), then woven threads
# (cloth), grain and creases (leather) or brushing (metal) are added to the normal map, the colour (thread shading,
# mottling, folds darkened from the normal map's curvature, wear on raised spots) and the roughness. Every colourway
# of a material (the pack's second colours and our wasteland ones) gets the same detail.
# Output: assets/models/outfits/retex/T_<Name>_BaseColor.jpg (one per colourway), T_<Material>_Normal.png,
# T_<Material>_ORM.png, assets/cc0/textures/garment_weave/ (fine weave for the sewn pieces), and tools/shots/retex_compare.jpg (old | new crops). Names go in data/characters.json retexture.
# Run: python3 tools/retexture_outfits.py
# Dependencies: numpy, pillow; assets/cc0/packs/modular_character_outfits_fantasy_standard/.
import os

import numpy as np
from PIL import Image

PACK = "assets/cc0/packs/modular_character_outfits_fantasy_standard/"
OUT = "assets/models/outfits/retex/"
SIZE = 2048
MATERIALS = {
    # material: (pack folder of its maps, roughness at which leather turns to cloth, colourways: name -> albedo file)
    "Peasant": ("exports_gltf_godot_unreal_outfits/T_Peasant", 0.905, {
        "Peasant": PACK + "exports_gltf_godot_unreal_outfits/T_Peasant_BaseColor.png",
        "Peasant_2": PACK + "textures_peasant/T_Peasant_2_BaseColor.png",
        "Peasant_Wasteland": "assets/models/outfits/peasant_wasteland_albedo.png"}),
    "Ranger": ("exports_gltf_godot_unreal_outfits/T_Ranger", 0.93, {
        "Ranger": PACK + "exports_gltf_godot_unreal_outfits/T_Ranger_BaseColor.png",
        "Ranger_3": PACK + "textures_ranger/T_Ranger_3_BaseColor.png",
        "Ranger_Wasteland": "assets/models/outfits/ranger_wasteland_albedo.png"}),
}


def load(path, mode="RGB"):
    im = Image.open(path).convert(mode)
    if im.size != (SIZE, SIZE):
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0


def blur(a, radius):
    # gaussian blur in frequency space (the map wraps at its edges, which only touches padding)
    f = np.fft.fftfreq(a.shape[0])
    g = np.exp(-2 * (np.pi * radius) ** 2 * (f[:, None] ** 2 + f[None, :] ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def noise(seed, falloff, stretch=(1.0, 1.0), n=None):
    # tileable filtered noise, unit deviation
    n = n or SIZE
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(n)[:, None] * stretch[0]
    fx = np.fft.fftfreq(n)[None, :] * stretch[1]
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    spec = (rng.normal(size=(n, n)) + 1j * rng.normal(size=(n, n))) / r ** falloff
    spec[0, 0] = 0
    f = np.real(np.fft.ifft2(spec))
    return (f - f.mean()) / (f.std() + 1e-9)


def weave(period=4.0):
    # plain weave: threads alternate over / under; each thread a rounded ridge, slubs vary its thickness
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    slub_x = 1.0 + 0.25 * noise(21, 1.6, (1.0, 0.05))
    slub_y = 1.0 + 0.25 * noise(22, 1.6, (0.05, 1.0))
    warp = (0.5 + 0.5 * np.cos(2 * np.pi * x / period)) * slub_y  # threads running down
    weft = (0.5 + 0.5 * np.cos(2 * np.pi * y / period)) * slub_x  # threads running across
    over = ((np.floor(x / period) + np.floor(y / period)) % 2).astype(np.float32)
    h = over * (0.75 * warp + 0.25 * weft) + (1 - over) * (0.75 * weft + 0.25 * warp)
    fuzz = noise(23, 0.4) * 0.08
    return (h - h.mean()) / (h.std() + 1e-9) + fuzz


def leather():
    pores = -np.abs(noise(31, 1.1))  # small pits
    creases = -np.abs(noise(32, 1.9)) * 0.9  # long soft creases
    fine = noise(33, 0.6) * 0.25
    h = pores + creases + fine
    return (h - h.mean()) / (h.std() + 1e-9)


def brushed():
    h = noise(41, 1.2, (1.0, 0.02)) + noise(42, 0.8) * 0.15
    return (h - h.mean()) / (h.std() + 1e-9)


def normal_from(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    return dx, dy


def garment(folder="assets/cc0/textures/garment_weave/"):
    # (the sewn wear pieces: aprons, tabards, skirts, robes) a fine plain weave tile for data/surfaces.json fx_garment:
    # 128 threads a repeat (the hessian sacking they wore before showed as a coarse grid on clothes)
    global SIZE
    keep, SIZE = SIZE, 1024
    h = weave(8.0)
    SIZE = keep
    os.makedirs(folder, exist_ok=True)
    grey = np.clip(0.5 + 0.06 * h, 0, 1)  # grain: averages one half (the material doubles it)
    Image.fromarray((np.dstack([grey] * 3) * 255).astype(np.uint8)).save(folder + "garment_weave_grain_1k.jpg", quality=92)
    Image.fromarray((np.dstack([grey] * 3) * 255).astype(np.uint8)).save(folder + "garment_weave_diff_1k.jpg", quality=92)
    dx, dy = normal_from(h, 0.18)
    n = np.dstack([-dx, dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(folder + "garment_weave_nor_1k.jpg", quality=95)
    arm = np.dstack([np.clip(1.0 - 0.08 * np.clip(-h, 0, 2), 0, 1), np.full_like(h, 0.95), np.zeros_like(h)])
    Image.fromarray((arm * 255).astype(np.uint8)).save(folder + "garment_weave_arm_1k.jpg", quality=92)


def main():
    garment()
    os.makedirs(OUT, exist_ok=True)
    os.makedirs("tools/shots", exist_ok=True)
    cloth_h, leather_h, metal_h = weave(), leather(), brushed()
    mottle = noise(51, 1.8)
    wear_n = noise(52, 1.4)
    compare = []
    for name, (stem, cut, colourways) in MATERIALS.items():
        base_n = load(PACK + stem + "_Normal.png")
        orm = load(PACK + stem + "_ORM.png")
        rough = blur(orm[..., 1], 7)
        metal = smoothstep(0.35, 0.65, blur(orm[..., 2], 3))
        cloth = smoothstep(cut - 0.015, cut + 0.015, rough) * (1 - metal)
        hide = (1 - cloth) * (1 - metal)
        # the detail height of each texel, by what it is made of
        h = cloth * cloth_h + hide * leather_h + metal * metal_h
        dx, dy = normal_from(cloth * cloth_h, 0.15)
        lx, ly = normal_from(hide * leather_h, 0.16)
        mx, my = normal_from(metal * metal_h, 0.08)
        nx = base_n[..., 0] * 2 - 1
        ny = base_n[..., 1] * 2 - 1
        nz = base_n[..., 2] * 2 - 1
        # folds: where the pack's normal map bends inward (curvature) the cloth sits in shadow
        curv = (np.roll(nx, -2, 1) - np.roll(nx, 2, 1)) - (np.roll(ny, -2, 0) - np.roll(ny, 2, 0))
        curv = blur(np.clip(curv * 0.5 + 0.5, 0, 1), 2) * 2 - 1
        nx2, ny2 = nx - (dx + lx + mx), ny + (dy + ly + my)  # detail laid over the folds (whiteout blend)
        length = np.sqrt(nx2 ** 2 + ny2 ** 2 + nz ** 2) + 1e-9
        new_n = np.dstack([nx2 / length, ny2 / length, nz / length]) * 0.5 + 0.5
        Image.fromarray((np.clip(new_n, 0, 1) * 255).astype(np.uint8)).save(OUT + "T_%s_Normal.png" % name, optimize=True)
        # roughness: cloth dull and even, leather keeps a sheen that varies with the grain, metal brushed and worn
        new_r = orm[..., 1] * cloth + np.clip(orm[..., 1] - 0.06 + 0.05 * leather_h, 0.45, 1.0) * hide + np.clip(orm[..., 1] + 0.08 * metal_h, 0.2, 0.9) * metal
        new_r = np.where(cloth > 0.5, np.maximum(new_r, 0.9), new_r)
        ao = orm[..., 0] * (1 - 0.18 * np.clip(-curv, 0, 1)) * (1 - 0.06 * cloth * np.clip(-cloth_h, 0, 2))
        new_orm = np.dstack([ao, new_r, orm[..., 2]])
        Image.fromarray((np.clip(new_orm, 0, 1) * 255).astype(np.uint8)).save(OUT + "T_%s_ORM.png" % name, optimize=True)
        shade = (1.0 + cloth * 0.05 * cloth_h + hide * (0.06 * leather_h + 0.05 * mottle) + metal * 0.04 * metal_h)
        shade *= 1.0 - 0.22 * np.clip(-curv, 0, 1)  # folds
        shade *= 1.0 + 0.10 * hide * np.clip(curv, 0, 1) * smoothstep(0.3, 1.5, wear_n)  # leather worn pale on raised spots
        for colour, path in colourways.items():
            albedo = load(path)
            grime = 1.0 - 0.05 * smoothstep(0.5, 2.0, mottle)[..., None]  # a little lived-in dirt
            new_a = np.clip(albedo * shade[..., None] * grime, 0, 1)
            Image.fromarray((new_a * 255).astype(np.uint8)).save(OUT + "T_%s_BaseColor.jpg" % colour, quality=92)
            if colour == name:
                crop = (slice(900, 1156), slice(900, 1156))
                compare.append(np.concatenate([albedo[crop], new_a[crop]], axis=1))
        print("RETEX %s: cloth %.0f %%, leather %.0f %%, metal %.0f %%" % (name, cloth.mean() * 100, hide.mean() * 100, metal.mean() * 100))
    sheet = np.concatenate(compare, axis=0)
    Image.fromarray((sheet * 255).astype(np.uint8)).resize((1024, 1024), Image.NEAREST).save("tools/shots/retex_compare.jpg", quality=90)
    print("RETEX_DONE")


main()
