#pragma once
//    terrain.hpp - Aethyra gameplay elevation and aerial transitions
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

// Gameplay elevation is separate from graphics. Each map may ship
// data/<map>.elev (written by tools/tmx2wlk.py from the client map): a
// level per cell, cliff faces ('C') and stair cells ('S'). The exporter
// guarantees walkable cells on different levels only meet at stairs, so
// ordinary walking and pathfinding (which only read walkability) never
// change level elsewhere. Every other movement - Dash, featherfall,
// upward jumps and forced falls - goes through this module, and so does
// the client's landing preview (src/eathena/terrain.cpp), which applies
// the same rules to the same data.

#include "fwd.hpp"

#include <cstdint>

#include "../strings/fwd.hpp"


namespace tmwa
{
namespace map
{
enum class LeapResult : uint8_t
{
    OK,
    NOT_AT_EDGE,    // no cliff face in front
    TOO_FAR,        // the cliff band is wider than the reach
    NO_LANDING,     // nothing to stand on beyond the cliff
    OBSTRUCTED,     // a diagonal corner is blocked
    WRONG_WAY,      // the landing is above (featherfall) / below (jump)
    TOO_HIGH,       // more levels than allowed
};

struct Leap
{
    LeapResult result = LeapResult::NOT_AT_EDGE;
    int x = 0, y = 0;       // landing
    int span = 0;           // cliff cells crossed
    int levels = 0;         // levels gained (+) or lost (-)
};

/// Read data/<map>.elev for a loaded map; a map without one is flat.
bool terrain_load(map_local *m);

bool terrain_flat(Borrowed<map_local> m);
int terrain_level(Borrowed<map_local> m, int x, int y);
bool terrain_cliff(Borrowed<map_local> m, int x, int y);
bool terrain_stair(Borrowed<map_local> m, int x, int y);

/// Whether beings on these two cells share a level (a stair joins both
/// of its neighbours' levels). Attacks need this.
bool terrain_same_level(Borrowed<map_local> m, int x1, int y1, int x2, int y2);

/// One ground step from (x, y) by (dx, dy): the target is walkable, on a
/// compatible level, and a diagonal step does not cut a blocked corner.
bool terrain_ground_step(Borrowed<map_local> m, int x, int y, int dx, int dy);

/// Cross the cliff face in front of (x, y) along (dx, dy). dir is -1 to
/// go down (featherfall, falls), +1 to go up (jump). max_levels bounds the
/// height change, max_span the cliff cells crossed. Landing occupancy is
/// the caller's to check.
Leap terrain_leap(Borrowed<map_local> m, int x, int y, int dx, int dy,
        int dir, int max_levels, int max_span);
} // namespace map
} // namespace tmwa
