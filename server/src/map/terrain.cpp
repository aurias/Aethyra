#include "terrain.hpp"
//    terrain.cpp - Aethyra gameplay elevation and aerial transitions
//
//    This file is part of Aethyra, derived from The Mana World (Athena server)
//
//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.
//
//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.
//
//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include <cstdlib>

#include "../strings/astring.hpp"
#include "../strings/xstring.hpp"

#include "../io/cxxstdio.hpp"
#include "../io/read.hpp"

#include "map.hpp"

#include "../poison.hpp"


namespace tmwa
{
namespace map
{
namespace
{
constexpr uint8_t LEVEL_MASK = 0x0f;
constexpr uint8_t CLIFF = 0x40;
constexpr uint8_t STAIR = 0x80;

bool inside(Borrowed<map_local> m, int x, int y)
{
    return 0 <= x && x < m->xs && 0 <= y && y < m->ys;
}

uint8_t cell(Borrowed<map_local> m, int x, int y)
{
    if (m->terrain.empty() || !inside(m, x, y))
        return 0;
    return m->terrain[x + y * m->xs];
}

bool walkable(Borrowed<map_local> m, int x, int y)
{
    return inside(m, x, y) && !bool(read_gatp(m, x, y) & MapCell::UNWALKABLE);
}

/// Blocked and not a cliff face: trees, water, walls.
bool obstacle(Borrowed<map_local> m, int x, int y)
{
    return !inside(m, x, y) || (!walkable(m, x, y) && !terrain_cliff(m, x, y));
}
} // anonymous namespace

bool terrain_load(map_local *m)
{
    m->terrain.clear();
    AString path = STRPRINTF("data/%s.elev"_fmt, m->name_);
    io::ReadFile in(path);
    if (!in.is_open())
        return true;    // flat map
    std::vector<uint8_t> t(size_t(m->xs) * m->ys);
    AString line;
    int y = 0;
    while (in.getline(line) && y < m->ys)
    {
        XString row = line.rstrip();
        if (int(row.size()) != m->xs)
        {
            PRINTF("terrain: %s row %d has %zu cells, map is %d wide\n"_fmt,
                    path, y, row.size(), m->xs);
            return false;
        }
        for (int x = 0; x < m->xs; ++x)
        {
            char c = row[x];
            uint8_t v;
            if (c == 'C')
                v = CLIFF;
            else if (c == 'S')
                v = STAIR;
            else if ('0' <= c && c <= '9')
                v = c - '0';
            else
            {
                PRINTF("terrain: %s has a bad cell '%c'\n"_fmt, path, c);
                return false;
            }
            t[x + y * m->xs] = v;
        }
        y++;
    }
    if (y != m->ys)
    {
        PRINTF("terrain: %s has %d rows, map has %d\n"_fmt, path, y, m->ys);
        return false;
    }
    m->terrain = std::move(t);
    return true;
}

bool terrain_flat(Borrowed<map_local> m)
{
    return m->terrain.empty();
}

int terrain_level(Borrowed<map_local> m, int x, int y)
{
    return cell(m, x, y) & LEVEL_MASK;
}

bool terrain_cliff(Borrowed<map_local> m, int x, int y)
{
    return cell(m, x, y) & CLIFF;
}

bool terrain_stair(Borrowed<map_local> m, int x, int y)
{
    return cell(m, x, y) & STAIR;
}

bool terrain_same_level(Borrowed<map_local> m, int x1, int y1, int x2, int y2)
{
    if (terrain_flat(m) || terrain_stair(m, x1, y1) || terrain_stair(m, x2, y2))
        return true;
    return terrain_level(m, x1, y1) == terrain_level(m, x2, y2);
}

bool terrain_ground_step(Borrowed<map_local> m, int x, int y, int dx, int dy)
{
    int nx = x + dx, ny = y + dy;
    if (!walkable(m, nx, ny) || !terrain_same_level(m, x, y, nx, ny))
        return false;
    // A diagonal step may not slip between two blocked corners' edges.
    if (dx && dy && (!walkable(m, x + dx, y) || !walkable(m, x, y + dy)))
        return false;
    return true;
}

Leap terrain_leap(Borrowed<map_local> m, int x, int y, int dx, int dy,
        int dir, int max_levels, int max_span)
{
    Leap leap;
    if (terrain_flat(m) || (!dx && !dy) || terrain_stair(m, x, y))
        return leap;    // NOT_AT_EDGE
    int from = terrain_level(m, x, y);
    int cx = x, cy = y;
    while (true)
    {
        int nx = cx + dx, ny = cy + dy;
        // Diagonal moves may not pass a solid obstacle's corner.
        if (dx && dy && (obstacle(m, cx + dx, cy) || obstacle(m, cx, cy + dy)))
        {
            leap.result = leap.span ? LeapResult::OBSTRUCTED
                                    : LeapResult::NOT_AT_EDGE;
            return leap;
        }
        if (!terrain_cliff(m, nx, ny))
        {
            cx = nx;
            cy = ny;
            break;
        }
        leap.span++;
        if (leap.span > 16)
        {
            leap.result = LeapResult::TOO_FAR;
            return leap;
        }
        cx = nx;
        cy = ny;
    }
    if (!leap.span)
        return leap;    // NOT_AT_EDGE
    leap.x = cx;
    leap.y = cy;
    bool landable = walkable(m, cx, cy) && !terrain_stair(m, cx, cy);
    leap.levels = terrain_level(m, cx, cy) - from;
    // A ledge the other way is the other move's, however wide it is.
    if (landable && leap.levels * dir <= 0)
    {
        leap.result = LeapResult::WRONG_WAY;
        return leap;
    }
    if (leap.span > max_span)
    {
        leap.result = LeapResult::TOO_FAR;
        return leap;
    }
    if (!landable)
    {
        leap.result = LeapResult::NO_LANDING;
        return leap;
    }
    if (std::abs(leap.levels) > max_levels)
    {
        leap.result = LeapResult::TOO_HIGH;
        return leap;
    }
    leap.result = LeapResult::OK;
    return leap;
}
} // namespace map
} // namespace tmwa
