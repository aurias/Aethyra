/*
 *  Aethyra
 *
 *  This file is part of Aethyra.
 *
 *  Aethyra is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  any later version.
 *
 *  Aethyra is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with Aethyra; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include <cstdlib>
#include <string>
#include <vector>

#include "terrain.h"

#include "../core/map/map.h"

namespace
{
    Map *cachedMap = NULL;
    std::string cachedSource;
    std::vector<char> cells;   // one character per cell, as in the map

    const std::vector<char> &grid(Map *map)
    {
        const std::string source = map ? map->getProperty("elevation") : "";
        if (map != cachedMap || source != cachedSource)
        {
            cachedMap = map;
            cachedSource = source;
            cells.clear();
            for (std::string::size_type i = 0; i < source.size(); i++)
                if (source[i] != ',')
                    cells.push_back(source[i]);
            if (!map || (int) cells.size() != map->getWidth() * map->getHeight())
                cells.clear();
        }
        return cells;
    }

    bool inside(Map *map, int x, int y)
    {
        return x >= 0 && y >= 0 && x < map->getWidth() && y < map->getHeight();
    }

    char cell(Map *map, int x, int y)
    {
        const std::vector<char> &g = grid(map);
        if (g.empty() || !inside(map, x, y))
            return '0';
        return g[x + y * map->getWidth()];
    }

    bool walkable(Map *map, int x, int y)
    {
        return inside(map, x, y) && !map->tileCollides(x, y);
    }

    bool obstacle(Map *map, int x, int y)
    {
        return !inside(map, x, y) ||
               (!walkable(map, x, y) && !Terrain::cliff(map, x, y));
    }
}

bool Terrain::flat(Map *map)
{
    return grid(map).empty();
}

int Terrain::level(Map *map, int x, int y)
{
    const char c = cell(map, x, y);
    return (c >= '0' && c <= '9') ? c - '0' : 0;
}

bool Terrain::cliff(Map *map, int x, int y)
{
    return cell(map, x, y) == 'C';
}

bool Terrain::stair(Map *map, int x, int y)
{
    return cell(map, x, y) == 'S';
}

Terrain::Leap Terrain::leap(Map *map, int x, int y, int dx, int dy, int dir,
                            int maxLevels, int maxSpan)
{
    Leap leap = { NOT_AT_EDGE, 0, 0, 0, 0 };
    if (!map || flat(map) || (!dx && !dy) || stair(map, x, y))
        return leap;
    const int from = level(map, x, y);
    int cx = x, cy = y;
    while (true)
    {
        const int nx = cx + dx, ny = cy + dy;
        if (dx && dy && (obstacle(map, cx + dx, cy) || obstacle(map, cx, cy + dy)))
        {
            leap.result = leap.span ? OBSTRUCTED : NOT_AT_EDGE;
            return leap;
        }
        cx = nx;
        cy = ny;
        if (!cliff(map, cx, cy))
            break;
        if (++leap.span > 16)
        {
            leap.result = TOO_FAR;
            return leap;
        }
    }
    if (!leap.span)
        return leap;
    leap.x = cx;
    leap.y = cy;
    const bool landable = walkable(map, cx, cy) && !stair(map, cx, cy);
    leap.levels = level(map, cx, cy) - from;
    if (landable && leap.levels * dir <= 0)
        leap.result = WRONG_WAY;
    else if (leap.span > maxSpan)
        leap.result = TOO_FAR;
    else if (!landable)
        leap.result = NO_LANDING;
    else if (std::abs(leap.levels) > maxLevels)
        leap.result = TOO_HIGH;
    else
        leap.result = OK;
    return leap;
}
