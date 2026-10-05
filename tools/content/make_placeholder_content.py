#!/usr/bin/env python3
"""Generate the placeholder content used to bring up the server and client.

Everything here is deliberately plain stand-in art so the game can run end
to end before real assets exist:

- flat-coloured 32px tiles standing in for Len's Whispers of Avalon
  grassland tileset (tile indices are stable, so the map can be re-skinned
  by swapping the tileset image);
- a simple directional figure for player bodies and NPCs;
- the client's XML databases (items, monsters, NPCs, skills, colours,
  emotes, effects) with only the entries the test world uses.

Outputs go under data/ (relative to the repository root). Run
server/tools/tmx2wlk.py afterwards to produce the server's walk map.
"""

import base64
import gzip
import os
import struct
import sys
import zlib

TILE = 32
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# Placeholder tileset, one row. Index order is part of the map format.
GRASS, GRASS_ALT, CLIFF, PLATEAU, WATER, STAIRS, FLOWERS, PATH = range(8)
TILE_COLOURS = [
    (126, 176, 96),    # grass
    (110, 162, 84),    # darker grass tuft
    (138, 112, 82),    # cliff face (warm earth)
    (150, 196, 112),   # upper terrace grass
    (92, 148, 186),    # water
    (176, 150, 112),   # stairs
    (126, 176, 96),    # grass with flowers (dots drawn below)
    (196, 176, 132),   # dirt path
]


def png(width, height, pixel):
    """Encode an RGBA image; pixel(x, y) returns an (r, g, b, a) tuple."""
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend(pixel(x, y))

    def chunk(kind, data):
        body = kind + data
        return (struct.pack('>I', len(data)) + body
                + struct.pack('>I', zlib.crc32(body) & 0xffffffff))

    header = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
            + chunk(b'IDAT', zlib.compress(bytes(rows), 9))
            + chunk(b'IEND', b''))


def tileset_pixel(x, y):
    index, tx, ty = x // TILE, x % TILE, y % TILE
    r, g, b = TILE_COLOURS[index]
    edge = tx == 0 or ty == 0 or tx == TILE - 1 or ty == TILE - 1
    if index == CLIFF and ty % 8 == 0:
        r, g, b = r - 24, g - 24, b - 24          # strata lines
    elif index == STAIRS and ty % 8 < 2:
        r, g, b = r - 40, g - 40, b - 40          # step shadows
    elif index == WATER and (tx + 2 * ty) % 16 == 0:
        r, g, b = 160, 200, 230                   # ripples
    elif index == FLOWERS and (tx * 7 + ty * 13) % 37 == 0:
        r, g, b = 236, 228, 140                   # small flowers
    elif index in (GRASS, GRASS_ALT, PLATEAU) and (tx * 5 + ty * 3) % 23 == 0:
        r, g, b = r - 18, g - 10, b - 18          # grass texture
    if edge and index in (CLIFF, STAIRS):
        r, g, b = r - 12, g - 12, b - 12
    return (max(r, 0), max(g, 0), max(b, 0), 255)


def collision_pixel(x, y):
    # Tile 0 is walkable (transparent), tile 1 blocks movement.
    return (0, 0, 0, 0) if x < TILE else (220, 40, 40, 140)


def build_layers(width, height):
    ground = [[GRASS] * width for _ in range(height)]
    blocked = [[False] * width for _ in range(height)]

    # Upper terrace in the north, with a cliff edge along its south side.
    terrace_bottom = 9
    for y in range(terrace_bottom):
        for x in range(width):
            ground[y][x] = PLATEAU
    for x in range(width):
        ground[terrace_bottom][x] = CLIFF
        ground[terrace_bottom + 1][x] = CLIFF
        blocked[terrace_bottom][x] = True
        blocked[terrace_bottom + 1][x] = True

    # The ordinary stair route between the terrace and the meadow.
    for y in (terrace_bottom, terrace_bottom + 1):
        for x in (8, 9):
            ground[y][x] = STAIRS
            blocked[y][x] = False

    # Pond in the south-east.
    for y in range(18, 25):
        for x in range(28, 36):
            if (x - 31.5) ** 2 / 16 + (y - 21) ** 2 / 9 <= 1:
                ground[y][x] = WATER
                blocked[y][x] = True

    # Path from the stairs down to the settlement clearing.
    for y in range(terrace_bottom + 2, 22):
        ground[y][8] = PATH
        ground[y][9] = PATH
    for x in range(9, 20):
        ground[21][x] = PATH

    # Scatter some texture deterministically.
    for y in range(height):
        for x in range(width):
            if ground[y][x] == GRASS:
                h = (x * 73 + y * 151) % 17
                if h == 0:
                    ground[y][x] = FLOWERS
                elif h < 3:
                    ground[y][x] = GRASS_ALT

    # Map border is solid.
    for x in range(width):
        blocked[0][x] = blocked[height - 1][x] = True
    for y in range(height):
        blocked[y][0] = blocked[y][width - 1] = True

    return ground, blocked


def encode_layer(cells, first_gid):
    data = bytearray()
    for row in cells:
        for value in row:
            gid = 0 if value is None else first_gid + value
            data.extend(struct.pack('<I', gid))
    # The client only understands gzip-compressed base64 layer data.
    return base64.b64encode(gzip.compress(bytes(data), mtime=0)).decode()


def write_tmx(path, width, height, ground, blocked):
    collision = [[1 if b else 0 for b in row] for row in blocked]
    fringe = [[None] * width for _ in range(height)]
    tileset_gid, collision_gid = 1, 1 + len(TILE_COLOURS)

    def layer(name, cells, gid):
        return ('  <layer name="%s" width="%d" height="%d">\n'
                '   <data encoding="base64" compression="gzip">%s</data>\n'
                '  </layer>\n') % (name, width, height, encode_layer(cells, gid))

    with open(path, 'w') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write('<map version="1.0" orientation="orthogonal" width="%d" '
                'height="%d" tilewidth="%d" tileheight="%d">\n'
                % (width, height, TILE, TILE))
        f.write(' <properties>\n'
                '  <property name="name" value="Windswept Meadow (test)"/>\n'
                ' </properties>\n')
        f.write(' <tileset firstgid="%d" name="placeholder-gale" '
                'tilewidth="%d" tileheight="%d">\n'
                '  <image source="../graphics/tiles/placeholder-gale.png" '
                'width="%d" height="%d"/>\n </tileset>\n'
                % (tileset_gid, TILE, TILE, TILE * len(TILE_COLOURS), TILE))
        f.write(' <tileset firstgid="%d" name="collision" '
                'tilewidth="%d" tileheight="%d">\n'
                '  <image source="../graphics/tiles/collision.png" '
                'width="%d" height="%d"/>\n </tileset>\n'
                % (collision_gid, TILE, TILE, TILE * 2, TILE))
        f.write(layer('ground', ground, tileset_gid))
        f.write(layer('fringe', fringe, tileset_gid))
        f.write(layer('collision', collision, collision_gid))
        f.write('</map>\n')


# --- Placeholder characters -------------------------------------------------

FRAME = 64
DIRECTIONS = ['down', 'left', 'up', 'right']   # one sheet row each
FRAMES_PER_DIRECTION = 3                        # stand, walk A, walk B


def figure_pixel(body, accent):
    """A small figure: head, body, legs and a mark showing its facing."""
    def pixel(x, y):
        row, col = y // FRAME, x // FRAME
        fx, fy = x % FRAME, y % FRAME
        direction = DIRECTIONS[row]
        step = (0, -3, 3)[col]
        cx = 32
        # legs alternate when walking
        if 50 <= fy < 62:
            for leg_x, swing in ((cx - 6, step), (cx + 6, -step)):
                if abs(fx - leg_x) <= 2 and fy < 62 + min(swing, 0):
                    return (70, 60, 52, 255)
        # body
        if 34 <= fy < 52 and abs(fx - cx) <= 9 - (fy - 34) // 6:
            return body + (255,)
        # head
        if (fx - cx) ** 2 + (fy - 26) ** 2 <= 64:
            mark = {'down': (cx, 28), 'up': None,
                    'left': (cx - 5, 26), 'right': (cx + 5, 26)}[direction]
            if mark and abs(fx - mark[0]) <= 1 and abs(fy - mark[1]) <= 1:
                return accent + (255,)
            return (236, 200, 168, 255)
        return (0, 0, 0, 0)
    return pixel


def sprite_xml(image, actions):
    lines = ['<?xml version="1.0"?>',
             '<sprite>',
             ' <imageset name="base" src="%s" width="%d" height="%d"/>'
             % (image, FRAME, FRAME)]
    for action in actions:
        lines.append(' <action name="%s" imageset="base">' % action)
        for row, direction in enumerate(DIRECTIONS):
            first = row * FRAMES_PER_DIRECTION
            lines.append('  <animation direction="%s">' % direction)
            if action == 'walk':
                lines.append('   <frame index="%d" delay="120"/>' % (first + 1))
                lines.append('   <frame index="%d" delay="120"/>' % first)
                lines.append('   <frame index="%d" delay="120"/>' % (first + 2))
                lines.append('   <frame index="%d" delay="120"/>' % first)
            else:
                lines.append('   <frame index="%d"/>' % first)
            lines.append('  </animation>')
        lines.append(' </action>')
    lines.append('</sprite>')
    return '\n'.join(lines) + '\n'


def write_sprites(data):
    sprites = os.path.join(data, 'graphics', 'sprites')
    os.makedirs(sprites, exist_ok=True)
    actions = ['stand', 'walk', 'attack', 'sit', 'dead', 'hurt']
    sheet_w = FRAME * FRAMES_PER_DIRECTION
    sheet_h = FRAME * len(DIRECTIONS)
    for name, body, accent in (
            ('placeholder-player', (120, 150, 190), (40, 40, 60)),
            ('placeholder-npc', (110, 170, 150), (40, 60, 40)),
            ('error', (220, 40, 200), (0, 0, 0))):
        with open(os.path.join(sprites, name + '.png'), 'wb') as f:
            f.write(png(sheet_w, sheet_h, figure_pixel(body, accent)))
        with open(os.path.join(sprites, name + '.xml'), 'w') as f:
            f.write(sprite_xml('graphics/sprites/%s.png' % name, actions))


def write_items_art(data):
    items = os.path.join(data, 'graphics', 'items')
    os.makedirs(items, exist_ok=True)

    def reed(x, y):
        if abs(x - 16 - (y - 16) // 6) <= 1 and 4 <= y < 30:
            return (150, 190, 120, 255)
        if abs(x - 20) + abs(y - 8) <= 3:
            return (220, 210, 170, 255)
        return (0, 0, 0, 0)
    with open(os.path.join(items, 'breeze-reed.png'), 'wb') as f:
        f.write(png(32, 32, reed))


# --- Client databases --------------------------------------------------------

def write_databases(data):
    files = {
        'items.xml': """<?xml version="1.0"?>
<!-- Placeholder item database. Negative ids are character bodies/hair. -->
<items>
 <item id="-100" type="other" name="body">
  <sprite gender="male">placeholder-player.xml</sprite>
  <sprite gender="female">placeholder-player.xml</sprite>
 </item>
 <item id="701" image="breeze-reed.png" name="Breeze Reed" type="generic"
       weight="1" description="A hollow meadow reed. Wind lingers inside it."
       effect="Natural Gale vessel (placeholder)"/>
</items>
""",
        'monsters.xml': """<?xml version="1.0"?>
<monsters>
</monsters>
""",
        'npcs.xml': """<?xml version="1.0"?>
<npcs>
 <npc id="105">
  <sprite>placeholder-npc.xml</sprite>
 </npc>
</npcs>
""",
        'skills.xml': """<?xml version="1.0"?>
<skills>
 <skill id="1" name="Basic" fixed="1"/>
</skills>
""",
        'colors.xml': """<?xml version="1.0"?>
<colors>
 <color id="0" dye="#4a3a2a"/>
</colors>
""",
        'emotes.xml': """<?xml version="1.0"?>
<emotes>
</emotes>
""",
        'effects.xml': """<?xml version="1.0"?>
<being-effects>
</being-effects>
""",
    }
    for name, text in files.items():
        with open(os.path.join(data, name), 'w') as f:
            f.write(text)


def main():
    data = os.path.join(ROOT, 'data')
    write_sprites(data)
    write_items_art(data)
    write_databases(data)

    width, height = 40, 30
    tiles_dir = os.path.join(ROOT, 'data', 'graphics', 'tiles')
    maps_dir = os.path.join(ROOT, 'data', 'maps')
    os.makedirs(tiles_dir, exist_ok=True)
    os.makedirs(maps_dir, exist_ok=True)

    with open(os.path.join(tiles_dir, 'placeholder-gale.png'), 'wb') as f:
        f.write(png(TILE * len(TILE_COLOURS), TILE, tileset_pixel))
    with open(os.path.join(tiles_dir, 'collision.png'), 'wb') as f:
        f.write(png(TILE * 2, TILE, collision_pixel))

    ground, blocked = build_layers(width, height)
    write_tmx(os.path.join(maps_dir, 'gale-1.tmx'), width, height,
              ground, blocked)
    return 0


if __name__ == '__main__':
    sys.exit(main())
