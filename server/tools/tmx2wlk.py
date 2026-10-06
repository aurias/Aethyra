#!/usr/bin/env python3
"""Convert a client Tiled map (.tmx) into the server's walk map (.wlk).

The .wlk format is what map_readmap() loads: a little-endian u16 width and
u16 height, followed by one MapCell byte per tile in row-major order.
Bit 0x01 marks the tile unwalkable.

Walkability comes from the map's layer whose name starts with "collision",
using the same rule as the client's MapReader: a tile blocks movement when
it holds any tile of the collision tileset other than its first tile.

Gameplay elevation comes from the map property "elevation": one row per
map row, rows joined by ',', one character per cell: a digit is the cell's
level, 'C' a cliff face (crossed only by featherfall, jumps and falls) and
'S' a stair cell joining neighbouring levels. It is written unchanged to
OUT_DIR/<map>.elev, one row per line, after checking that client and
server agree: cliff faces are unwalkable, and walkable neighbours on
different levels only meet at stairs (so ordinary walking and
pathfinding can never change level elsewhere).

Usage:
    tmx2wlk.py MAP.tmx OUT_DIR

Writes OUT_DIR/<map>.wlk (and .elev) and keeps OUT_DIR/resnametable.txt
in step.
"""

import base64
import gzip
import os
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

UNWALKABLE = 0x01


def layer_gids(layer, width, height):
    data = layer.find('data')
    encoding = data.get('encoding')
    compression = data.get('compression')
    if encoding == 'base64':
        raw = base64.b64decode(data.text.strip())
        if compression == 'gzip':
            raw = gzip.decompress(raw)
        elif compression == 'zlib':
            raw = zlib.decompress(raw)
        elif compression:
            raise ValueError('unsupported compression: %s' % compression)
        return list(struct.unpack('<%dI' % (width * height), raw))
    if encoding == 'csv':
        return [int(v) for v in data.text.replace('\n', '').split(',')]
    if encoding is None:
        return [int(t.get('gid', 0)) for t in data.findall('tile')]
    raise ValueError('unsupported encoding: %s' % encoding)


def read_elevation(root, width, height, tmx_path):
    props = root.find('properties')
    value = None
    if props is not None:
        for p in props.findall('property'):
            if p.get('name') == 'elevation':
                value = p.get('value')
    if value is None:
        return None
    rows = value.split(',')
    if len(rows) != height or any(len(r) != width for r in rows):
        raise ValueError('%s: elevation must be %d rows of %d cells'
                         % (tmx_path, height, width))
    for r in rows:
        for c in r:
            if not (c.isdigit() or c in 'CS'):
                raise ValueError('%s: bad elevation cell %r' % (tmx_path, c))
    return rows


def check_elevation(rows, cells, width, height, tmx_path):
    errors = []

    def walkable(x, y):
        return not cells[x + y * width] & UNWALKABLE

    for y in range(height):
        for x in range(width):
            c = rows[y][x]
            if c == 'C' and walkable(x, y):
                errors.append('(%d, %d) is a walkable cliff face' % (x, y))
            if c == 'S' and not walkable(x, y):
                errors.append('(%d, %d) is a blocked stair' % (x, y))
            if c in 'CS' or not walkable(x, y):
                continue
            for dx, dy in ((1, 0), (0, 1), (1, 1), (1, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < width and 0 <= ny < height):
                    continue
                n = rows[ny][nx]
                if n in 'CS' or not walkable(nx, ny):
                    continue
                if n != c:
                    errors.append('(%d, %d) level %s meets (%d, %d) level %s '
                                  'without stairs' % (x, y, c, nx, ny, n))
    if errors:
        raise ValueError('%s: elevation disagrees with walkability:\n  %s'
                         % (tmx_path, '\n  '.join(errors[:20])))


def convert(tmx_path, out_dir):
    root = ET.parse(tmx_path).getroot()
    width, height = int(root.get('width')), int(root.get('height'))

    # Tilesets sorted by firstgid, so a gid belongs to the last one at or below it.
    firstgids = sorted(int(ts.get('firstgid')) for ts in root.findall('tileset'))

    collision = [l for l in root.findall('layer')
                 if l.get('name', '').lower().startswith('collision')]
    if len(collision) != 1:
        raise ValueError('%s: expected exactly one collision layer, found %d'
                         % (tmx_path, len(collision)))

    cells = bytearray(width * height)
    for i, gid in enumerate(layer_gids(collision[0], width, height)):
        gid &= 0x1fffffff  # strip Tiled's flip flags
        if gid == 0:
            continue
        first = max(f for f in firstgids if f <= gid)
        if gid != first:
            cells[i] |= UNWALKABLE

    name = os.path.splitext(os.path.basename(tmx_path))[0]
    elevation = read_elevation(root, width, height, tmx_path)
    if elevation:
        check_elevation(elevation, cells, width, height, tmx_path)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, name + '.wlk'), 'wb') as f:
        f.write(struct.pack('<HH', width, height))
        f.write(cells)
    elev_path = os.path.join(out_dir, name + '.elev')
    if elevation:
        with open(elev_path, 'w') as f:
            f.write('\n'.join(elevation) + '\n')
    elif os.path.exists(elev_path):
        os.remove(elev_path)

    # resnametable maps a map name to its walk map file, relative to data/
    table = os.path.join(out_dir, 'resnametable.txt')
    entries = {}
    if os.path.exists(table):
        with open(table) as f:
            for line in f:
                parts = line.strip().split('#')
                if len(parts) >= 2 and parts[0]:
                    entries[parts[0]] = parts[1]
    entries[name] = name + '.wlk'
    with open(table, 'w') as f:
        for key in sorted(entries):
            f.write('%s#%s#\n' % (key, entries[key]))
    return name


def main(argv):
    if len(argv) != 3:
        sys.stderr.write(__doc__)
        return 2
    print('wrote %s.wlk' % convert(argv[1], argv[2]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
