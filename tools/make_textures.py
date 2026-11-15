#!/usr/bin/env python3
"""Generate the seamless texture images of the material library.

Writes kitchen_cabinet_designer/textures/<key>.jpg (512x512, tileable) and
prints the average colour of each texture, used for the dialog preview
(copy the values into geometry/material_library.rb if textures change).

Requires Pillow:  pip install pillow
Run from the repository root:  python3 tools/make_textures.py
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageFilter, ImageStat

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "kitchen_cabinet_designer" / "textures"
SIZE = 512


def tile_noise(seed, cells, cells_y=None):
    """Smooth periodic value noise in [0, 1] (tiles seamlessly).

    `cells` is the lattice size along X, `cells_y` along Y (default equal);
    fewer cells along X stretch the pattern horizontally (wood grain)."""
    cells_y = cells_y or cells
    rnd = random.Random(seed)
    grid = [[rnd.random() for _ in range(cells)] for _ in range(cells_y)]
    img = Image.new("L", (SIZE, SIZE))
    px = img.load()
    step = SIZE / cells
    step_y = SIZE / cells_y
    for y in range(SIZE):
        gy = y / step_y
        y0 = int(gy) % cells_y
        y1 = (y0 + 1) % cells_y
        fy = gy - int(gy)
        fy = fy * fy * (3 - 2 * fy)
        for x in range(SIZE):
            gx = x / step
            x0 = int(gx) % cells
            x1 = (x0 + 1) % cells
            fx = gx - int(gx)
            fx = fx * fx * (3 - 2 * fx)
            top = grid[y0][x0] * (1 - fx) + grid[y0][x1] * fx
            bottom = grid[y1][x0] * (1 - fx) + grid[y1][x1] * fx
            px[x, y] = int(255 * (top * (1 - fy) + bottom * fy))
    return img


def fractal(seed, octaves=(4, 8, 16, 32), stretch=1):
    layers = [tile_noise(seed + i, max(c // stretch, 1), c) for i, c in enumerate(octaves)]
    weights = [0.5 ** i for i in range(len(layers))]
    total = sum(weights)
    out = Image.new("L", (SIZE, SIZE))
    o = out.load()
    loads = [l.load() for l in layers]
    for y in range(SIZE):
        for x in range(SIZE):
            o[x, y] = int(sum(w * l[x, y] for w, l in zip(weights, loads)) / total)
    return out


def lerp(c0, c1, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c0, c1))


def wood(seed, light, dark, rings=14, turbulence=0.9):
    """Straight-grain wood running along X (panel length)."""
    noise = fractal(seed, (4, 8, 16, 32), stretch=4).load()
    fine = tile_noise(seed + 50, 8, 128).load()
    img = Image.new("RGB", (SIZE, SIZE))
    p = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = noise[x, y] / 255.0
            v = (y / SIZE) * rings + turbulence * n
            ring = 0.5 + 0.5 * math.sin(2 * math.pi * v)
            ring = ring ** 3
            grain = (fine[x, y] / 255.0 - 0.5) * 0.25
            t = min(max(ring * 0.75 + grain + 0.1, 0.0), 1.0)
            p[x, y] = lerp(light, dark, t)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def concrete(seed):
    noise = fractal(seed, (8, 16, 32, 64)).load()
    rnd = random.Random(seed)
    img = Image.new("RGB", (SIZE, SIZE))
    p = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = noise[x, y] / 255.0 + (rnd.random() - 0.5) * 0.08
            p[x, y] = lerp((120, 120, 117), (178, 177, 172), min(max(n, 0), 1))
    return img


def marble(seed):
    noise = fractal(seed).load()
    img = Image.new("RGB", (SIZE, SIZE))
    p = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = noise[x, y] / 255.0
            v = abs(math.sin(2 * math.pi * ((x + y) / SIZE + 1.6 * n)))
            vein = (1 - v) ** 14
            p[x, y] = lerp((240, 238, 234), (150, 150, 155), vein * 0.7 + n * 0.08)
    return img.filter(ImageFilter.GaussianBlur(1.2))


TEXTURES = {
    "oak_natural": lambda: wood(11, (214, 178, 128), (160, 117, 68)),
    "oak_sonoma": lambda: wood(23, (226, 203, 164), (180, 146, 100), rings=18),
    "walnut": lambda: wood(37, (128, 88, 60), (70, 45, 30), rings=12),
    "wenge": lambda: wood(41, (88, 66, 52), (38, 28, 24), rings=22, turbulence=0.7),
    "ash_white": lambda: wood(53, (238, 233, 222), (200, 192, 178), rings=16),
    "concrete": lambda: concrete(61),
    "marble": lambda: marble(71),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for key, make in TEXTURES.items():
        image = make()
        path = OUT / f"{key}.jpg"
        image.save(path, quality=85, optimize=True)
        r, g, b = (int(v) for v in ImageStat.Stat(image).mean)
        print(f"{key}: #{r:02x}{g:02x}{b:02x}  ({path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
