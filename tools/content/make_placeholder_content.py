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


def sheet(pixel_for_frame):
    """A 3x4 sheet in the character layout from pixel(col, row, fx, fy)."""
    def pixel(x, y):
        return pixel_for_frame(x // FRAME, y // FRAME, x % FRAME, y % FRAME)
    return png(FRAME * FRAMES_PER_DIRECTION, FRAME * len(DIRECTIONS), pixel)


def hopper_pixel(col, row, fx, fy):
    """Gust Hopper: a pale, long-eared meadow critter that bobs as it hops."""
    lift = (0, 4, 1)[col]
    cx, cy = 32, 50 - lift
    direction = DIRECTIONS[row]
    if (fx - cx) ** 2 / 100 + (fy - cy) ** 2 / 49 <= 1:
        eye = {'down': (cx, cy - 2), 'up': None,
               'left': (cx - 6, cy - 3), 'right': (cx + 6, cy - 3)}[direction]
        if eye and abs(fx - eye[0]) <= 1 and abs(fy - eye[1]) <= 1:
            return (40, 50, 40, 255)
        return (214, 200, 160, 255)
    for ear_x in (cx - 4, cx + 4):
        if abs(fx - ear_x) <= 1 and cy - 16 <= fy < cy - 5:
            return (190, 170, 130, 255)
    if fy == 58 and abs(fx - cx) <= 9 and lift:
        return (80, 110, 70, 120)   # shadow while airborne
    return (0, 0, 0, 0)


def plant_pixel(kind):
    def pixel(col, row, fx, fy):
        cx = 32
        if kind == 'grass':
            for i, (bx, h) in enumerate(((-7, 18), (-3, 24), (1, 20), (5, 26),
                                         (9, 16))):
                lean = (60 - fy) // 6 * (1 if i % 2 else -1)
                if abs(fx - (cx + bx + lean)) <= 1 and 60 - h <= fy < 60:
                    return (96 + i * 12, 170 + i * 6, 80, 255)
        elif kind == 'herb':
            if (fx - cx) ** 2 + (fy - 50) ** 2 <= 110:
                if (fx * 7 + fy * 5) % 23 == 0:
                    return (245, 245, 230, 255)   # tiny white flowers
                return (70, 140, 80, 255)
        elif kind == 'flower':
            if abs(fx - cx) <= 1 and 42 <= fy < 60:
                return (90, 150, 80, 255)
            if (fx - cx) ** 2 + (fy - 38) ** 2 <= 36:
                if (fx - cx) ** 2 + (fy - 38) ** 2 <= 4:
                    return (240, 220, 120, 255)
                return (190, 160, 230, 255)
        return (0, 0, 0, 0)
    return pixel


def static_sprite_xml(image):
    """Plants look the same from every side and in every state."""
    lines = ['<?xml version="1.0"?>', '<sprite>',
             ' <imageset name="base" src="%s" width="%d" height="%d"/>'
             % (image, FRAME, FRAME)]
    for action in ('stand', 'walk', 'attack', 'dead', 'hurt'):
        lines.append(' <action name="%s" imageset="base">' % action)
        for direction in DIRECTIONS:
            lines.append('  <animation direction="%s"><frame index="0"/>'
                         '</animation>' % direction)
        lines.append(' </action>')
    lines.append('</sprite>')
    return '\n'.join(lines) + '\n'


def write_creatures(data):
    sprites = os.path.join(data, 'graphics', 'sprites')
    actions = ['stand', 'walk', 'attack', 'dead', 'hurt']
    with open(os.path.join(sprites, 'gust-hopper.png'), 'wb') as f:
        f.write(sheet(hopper_pixel))
    with open(os.path.join(sprites, 'gust-hopper.xml'), 'w') as f:
        f.write(sprite_xml('graphics/sprites/gust-hopper.png', actions))
    for kind in ('grass', 'herb', 'flower'):
        name = 'plant-' + kind
        with open(os.path.join(sprites, name + '.png'), 'wb') as f:
            f.write(sheet(plant_pixel(kind)))
        with open(os.path.join(sprites, name + '.xml'), 'w') as f:
            f.write(static_sprite_xml('graphics/sprites/%s.png' % name))


ITEM_ICONS = {
    'breeze-reed': lambda x, y: (
        (150, 190, 120, 255) if abs(x - 16 - (y - 16) // 6) <= 1 and 4 <= y < 30
        else (220, 210, 170, 255) if abs(x - 20) + abs(y - 8) <= 3
        else None),
    # Thicker, darker, banded: the provisional test grade.
    'tempered-reed': lambda x, y: (
        (200, 170, 90, 255) if abs(x - 16 - (y - 16) // 6) <= 2 and 4 <= y < 30
        and y % 6 == 0
        else (110, 150, 90, 255) if abs(x - 16 - (y - 16) // 6) <= 2
        and 4 <= y < 30
        else (220, 230, 200, 255) if abs(x - 21) + abs(y - 7) <= 3
        else None),
    'grass-fiber': lambda x, y: (
        (140, 180, 100, 255) if 6 <= y < 28 and (x - y // 4) % 5 == 0
        and 8 <= x < 26 else
        (170, 140, 90, 255) if 15 <= y < 18 and 8 <= x < 26 else None),
    'meadow-herb': lambda x, y: (
        (70, 150, 80, 255) if (x - 16) ** 2 / 64 + (y - 14) ** 2 / 25 <= 1
        else (60, 110, 60, 255) if x == 16 and 14 <= y < 28 else None),
    'windflower-petal': lambda x, y: (
        (190, 160, 230, 255) if (x - 16) ** 2 / 81 + (y - 16) ** 2 / 36 <= 1
        else None),
    'hopper-feather': lambda x, y: (
        (230, 225, 210, 255) if abs(y - (30 - x)) <= 2 and 6 <= x < 26
        else None),
    'gale-tonic': lambda x, y: (
        (150, 220, 190, 255) if (x - 16) ** 2 + (y - 20) ** 2 <= 49
        else (200, 220, 230, 255) if abs(x - 16) <= 2 and 6 <= y < 14
        else (140, 100, 60, 255) if abs(x - 16) <= 3 and 4 <= y < 6
        else None),
}


def write_items_art(data):
    items = os.path.join(data, 'graphics', 'items')
    os.makedirs(items, exist_ok=True)
    for name, draw in ITEM_ICONS.items():
        def pixel(x, y, draw=draw):
            colour = draw(x, y)
            return colour if colour else (0, 0, 0, 0)
        with open(os.path.join(items, name + '.png'), 'wb') as f:
            f.write(png(32, 32, pixel))


# --- Skill effects -----------------------------------------------------------

def write_effects(data):
    particles = os.path.join(data, 'graphics', 'particles')
    os.makedirs(particles, exist_ok=True)

    def soft_dot(colour, radius):
        size = radius * 2 + 1
        def pixel(x, y):
            d = ((x - radius) ** 2 + (y - radius) ** 2) ** 0.5
            alpha = max(0, int(255 * (1 - d / (radius + 0.5))))
            return colour + (alpha,)
        return png(size, size, pixel)

    with open(os.path.join(particles, 'wind-puff.png'), 'wb') as f:
        f.write(soft_dot((235, 250, 245), 4))
    with open(os.path.join(particles, 'leaf.png'), 'wb') as f:
        f.write(soft_dot((120, 190, 90), 2))

    def effect(image, count, power, lifetime, angle=(0, 360), z=16,
               vertical=(0, 30)):
        return ('<?xml version="1.0"?>\n<effect>\n'
                ' <particle position-z="%d" lifetime="6">\n'
                '  <emitter>\n'
                '   <property name="image" value="graphics/particles/%s"/>\n'
                '   <property name="output" value="%d"/>\n'
                '   <property name="horizontal-angle" min="%d" max="%d"/>\n'
                '   <property name="vertical-angle" min="%d" max="%d"/>\n'
                '   <property name="power" min="%g" max="%g"/>\n'
                '   <property name="gravity" value="0"/>\n'
                '   <property name="lifetime" min="%d" max="%d"/>\n'
                '   <property name="fade-out" value="20"/>\n'
                '  </emitter>\n'
                ' </particle>\n</effect>\n'
                % (z, image, count, angle[0], angle[1], vertical[0],
                   vertical[1], power[0], power[1], lifetime[0], lifetime[1]))

    files = {
        # A short trail of puffs where the dash ends.
        'gale-dash.particle.xml': effect('wind-puff.png', 6, (0.3, 0.8),
                                         (30, 50)),
        # A wide ring of wind rushing outward.
        'gale-gust.particle.xml': effect('wind-puff.png', 14, (2.5, 3.5),
                                         (25, 40), vertical=(0, 5)),
        # Cut leaves scattering.
        'gale-scythe.particle.xml': effect('leaf.png', 10, (1.0, 2.0),
                                           (30, 60), z=8),
    }
    for name, text in files.items():
        with open(os.path.join(particles, name), 'w') as f:
            f.write(text)


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
       effect="Gale vessel: holds 20 energy, safe current 4. Select it as supply in the inventory."/>
 <item id="706" image="tempered-reed.png" name="Tempered Reed (test grade)"
       type="generic" weight="2"
       description="A provisional better-grade reed for comparison tests."
       effect="Gale vessel: holds 40 energy, safe current 9."/>
 <item id="702" image="grass-fiber.png" name="Grass Fiber" type="generic"
       weight="1" description="Tough meadow grass, cut clean by the wind."/>
 <item id="703" image="meadow-herb.png" name="Meadow Herb" type="usable"
       weight="1" description="A bitter terrace herb." effect="Heals 20 HP"/>
 <item id="704" image="windflower-petal.png" name="Windflower Petal"
       type="usable" weight="1" description="It trembles even in still air."
       effect="Restores 20 Gale energy"/>
 <item id="705" image="hopper-feather.png" name="Hopper Feather"
       type="generic" weight="1" description="Shed by a Gust Hopper."/>
 <item id="710" image="gale-tonic.png" name="Gale Tonic" type="usable"
       weight="2" description="Brewed by the Windkeeper from herbs and petals."
       effect="Heals 60 HP and restores 60 Gale energy"/>
</items>
""",
        'monsters.xml': """<?xml version="1.0"?>
<!-- Ids are server monster ids minus 1002, as the client expects. -->
<monsters>
 <monster id="8" name="Gust Hopper" targetCursor="small">
  <sprite>gust-hopper.xml</sprite>
 </monster>
 <monster id="99" name="Meadow Grass" targetCursor="small">
  <sprite>plant-grass.xml</sprite>
 </monster>
 <monster id="100" name="Wild Herb" targetCursor="small">
  <sprite>plant-herb.xml</sprite>
 </monster>
 <monster id="101" name="Windflower" targetCursor="small">
  <sprite>plant-flower.xml</sprite>
 </monster>
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
<!-- Ids match the effect numbers the server sends for hue skills. -->
<being-effects>
 <effect id="900" particle="graphics/particles/gale-dash.particle.xml"/>
 <effect id="901" particle="graphics/particles/gale-gust.particle.xml"/>
 <effect id="902" particle="graphics/particles/gale-scythe.particle.xml"/>
</being-effects>
""",
    }
    for name, text in files.items():
        with open(os.path.join(data, name), 'w') as f:
            f.write(text)


def main():
    data = os.path.join(ROOT, 'data')
    write_sprites(data)
    write_creatures(data)
    write_items_art(data)
    write_effects(data)
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
