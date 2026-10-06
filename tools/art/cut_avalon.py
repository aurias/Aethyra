#!/usr/bin/env python3
"""Cut Leonard Pabin's Whispers of Avalon sheets into the pieces the game uses.

Source sheets live in art/whispers-of-avalon/source (as published on
OpenGameArt); output goes to game/assets/avalon. Coordinates are pixels in
the source sheets, which are laid out on a 32 px grid. Re-run after changing
the table; the output is committed so the game builds without Pillow.
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "art", "whispers-of-avalon", "source")
OUT = os.path.join(ROOT, "game", "assets", "avalon")

GROUND = "ground_tiles.png"
CLIFF = "Cliff_tileset_0.png"
OBJECTS = "object-%20layer_1.png"
TREES = "treesv6_0_0.psd"

# name: (sheet, (x0, y0, x1, y1), note)
PIECES = {
    "grass": (GROUND, (32, 64, 96, 128), "2x2 repeating grass"),
    "sand": (GROUND, (32, 160, 128, 256), "3x3 repeating sand"),
    "sand_edges": (GROUND, (192, 128, 288, 224), "3x3 sand-in-grass border, centre empty"),
    "cobble": (GROUND, (32, 288, 96, 352), "2x2 cobbles"),
    "water_edges": (GROUND, (384, 256, 480, 352), "3x3 pond border, centre empty"),
    "plateau": (CLIFF, (32, 0, 224, 224), "6x7 raised-ground template"),
    "stairs": (CLIFF, (320, 128, 416, 224), "3x3 stairs cut into a south face"),
    "bush_big": (OBJECTS, (64, 0, 192, 128), "bush cluster"),
    "bush": (OBJECTS, (192, 0, 288, 96), "bush"),
    "bush_small": (OBJECTS, (160, 64, 224, 128), "small bush"),
    "rock_pale": (OBJECTS, (288, 32, 320, 64), "pale rock"),
    "barrel": (OBJECTS, (320, 16, 352, 64), "barrel (after Crush)"),
    "flowers": (OBJECTS, (352, 32, 384, 64), "flowers"),
    "flower": (OBJECTS, (384, 32, 416, 64), "flower"),
    "rock": (OBJECTS, (288, 64, 320, 96), "rock"),
    "rock_tall": (OBJECTS, (320, 64, 352, 96), "tall rock"),
    "rock_wide": (OBJECTS, (352, 64, 384, 96), "wide rock"),
    "rock_mossy": (OBJECTS, (384, 64, 416, 96), "mossy rock"),
    "tree_round": (TREES, (0, 24, 128, 192), "round tree"),
    "tree_bright": (TREES, (128, 24, 254, 192), "bright tree"),
    "tree_old": (TREES, (254, 24, 410, 192), "old tree"),
    "stump": (TREES, (410, 24, 500, 192), "stump"),
    "tree_dead": (TREES, (500, 24, 672, 192), "dead tree"),
}


# Pieces whose box overlaps a neighbouring sprite: keep only the largest
# connected (non-transparent) part.
SINGLE = {"bush", "bush_big", "bush_small"}


def largest_part(im):
    w, h = im.size
    alpha = im.getchannel("A").load()
    seen = [[False] * w for _ in range(h)]
    best = []
    for y0 in range(h):
        for x0 in range(w):
            if seen[y0][x0] or alpha[x0, y0] == 0:
                continue
            part, todo = [], [(x0, y0)]
            seen[y0][x0] = True
            while todo:
                x, y = todo.pop()
                part.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and alpha[nx, ny] > 0:
                        seen[ny][nx] = True
                        todo.append((nx, ny))
            if len(part) > len(best):
                best = part
    out = Image.new("RGBA", im.size)
    src, dst = im.load(), out.load()
    for x, y in best:
        dst[x, y] = src[x, y]
    return out


def open_sheet(name):
    im = Image.open(os.path.join(SRC, name))
    if name.endswith(".psd"):
        im.seek(1)          # the "Trees" layer; shadows are a separate layer
        im.load()
    return im.convert("RGBA")


def main():
    os.makedirs(OUT, exist_ok=True)
    sheets = {}
    manifest = {}
    for name, (sheet, box, note) in sorted(PIECES.items()):
        if sheet not in sheets:
            sheets[sheet] = open_sheet(sheet)
        piece = sheets[sheet].crop(box)
        if name in SINGLE:
            piece = largest_part(piece)
        piece.save(os.path.join(OUT, name + ".png"))
        manifest[name] = {"sheet": sheet, "box": list(box), "size": list(piece.size),
                          "note": note}
    # Open water: the pond border has no plain water cell, so tile the
    # water half of its top edge.
    edge = sheets[GROUND].crop((416, 272, 448, 288))
    water = Image.new("RGBA", (32, 32))
    water.paste(edge, (0, 0))
    water.paste(edge, (0, 16))
    water.save(os.path.join(OUT, "water.png"))
    manifest["water"] = {"sheet": GROUND, "box": [416, 272, 448, 288], "size": [32, 32],
                         "note": "open water: the pond edge's water half, tiled twice"}
    with open(os.path.join(OUT, "pieces.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print("wrote %d pieces to %s" % (len(manifest), OUT))


if __name__ == "__main__":
    sys.exit(main())
