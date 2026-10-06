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

#ifndef TERRAIN_H
#define TERRAIN_H

class Map;

/**
 * Gameplay elevation from the map's "elevation" property, and the same
 * leap rule the server applies (server/src/map/terrain.cpp). The client
 * uses it only to preview landings; the server decides.
 */
namespace Terrain
{
    enum Result { OK, NOT_AT_EDGE, TOO_FAR, NO_LANDING, OBSTRUCTED,
                  WRONG_WAY, TOO_HIGH };

    struct Leap
    {
        Result result;
        int x, y, span, levels;
    };

    bool flat(Map *map);
    int level(Map *map, int x, int y);
    bool cliff(Map *map, int x, int y);
    bool stair(Map *map, int x, int y);

    /** dir -1 goes down (featherfall), +1 up (jump). */
    Leap leap(Map *map, int x, int y, int dx, int dy, int dir,
              int maxLevels, int maxSpan);
}

#endif
