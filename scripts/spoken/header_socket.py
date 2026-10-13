"""Draws Spoken's header sockets: the ring round a speaker's face in the DialogueUI look, after
DialogueUI's quest-parchment socket but standing alone, with no line leaving it.

    py -3 scripts/spoken/header_socket.py

Writes addons/Spoken/Textures/HeaderSocketBrown.tga and HeaderSocketDark.tga (128x128 RGBA),
for DialogueUI's Brown and Dark themes. The ring's outer edge is at radius 62 of 64; the face's
opening at about 64% of that. Seeded, so a run gives the same files."""
import math
import pathlib
import random

from PIL import Image

SIZE, SUPER = 128, 4
# In DialogueUI's art's pixels: the ring's outer radius, which maps to OUTER here.
ART_RADIUS, OUTER = 42.5, 62
OUT = pathlib.Path(__file__).resolve().parents[2] / "addons" / "Spoken" / "Textures"


def noise(seed, cells):
    """Smooth value noise over the unit square, `cells` across."""
    rnd = random.Random(seed)
    grid = [[rnd.random() for _ in range(cells + 2)] for _ in range(cells + 2)]

    def at(u, v):
        x, y = u * cells, v * cells
        i, j = int(x), int(y)
        fx, fy = x - i, y - j
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = grid[j][i] + (grid[j][i + 1] - grid[j][i]) * fx
        b = grid[j + 1][i] + (grid[j + 1][i + 1] - grid[j + 1][i]) * fx
        return a + (b - a) * fy
    return at


def brown(d, worn, speck):
    """Colour at `d` art pixels in from the outer edge: worn dark edge, tan band, light rim, then
    the shadow falling into the opening."""
    edge = 2.5 + worn * 1.6
    if d < edge:
        return (115, 74, 42, 250) if speck < 0.8 else (162, 118, 77, 254)
    if d < 8.5:
        if d < 5.5 and speck > 0.66:
            return (138, 96, 60, 254)
        return (205, 163, 114, 255)
    if d < 10.5:
        return (212, 183, 150, 240)
    return (66, 40, 19, int(245 * math.exp(-((d - 10.5) / 6) ** 2)))


def dark(d, worn, speck):
    if d < 0.8:
        return (0, 0, 0, 245)
    if d < 3.5 + worn * 0.8:
        return (50, 50, 50, 255) if speck < 0.75 else (34, 34, 34, 255)
    if d < 8.8:
        return (0, 0, 0, 255)
    if d < 10.5:
        return (72, 72, 72, 235)
    return (0, 0, 0, int(146 * math.exp(-((d - 10.5) / 5.5) ** 2)))


def draw(paint, seed):
    big = SIZE * SUPER
    centre = big / 2
    scale = OUTER * SUPER / ART_RADIUS
    worn_at, speck_at, rim_at = noise(seed, 9), noise(seed + 1, 40), noise(seed + 2, 14)
    im = Image.new("RGBA", (big, big))
    px = im.load()
    for y in range(big):
        for x in range(big):
            dx, dy = x + 0.5 - centre, y + 0.5 - centre
            r = math.hypot(dx, dy) / scale
            u, v = x / big, y / big
            # A worn, slightly uneven outer edge.
            radius = ART_RADIUS - 0.9 * rim_at(u, v)
            d = radius - r
            if d < 0 or d > 24:
                continue
            px[x, y] = paint(d, worn_at(u, v), speck_at(u, v))
    return im.resize((SIZE, SIZE), Image.LANCZOS)


if __name__ == "__main__":
    for name, paint in (("Brown", brown), ("Dark", dark)):
        path = OUT / ("HeaderSocket%s.tga" % name)
        draw(paint, 7).save(path)
        print(path)
