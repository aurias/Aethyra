#include "hue.hpp"
//    hue.cpp - Aethyra hue skills
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

// Gale starter skills for the first playable demo. Gale energy is the
// character's SP pool; the numbers below are first-pass tuning, not design
// decisions.

#include "../compat/nullpo.hpp"

#include "../net/timer.hpp"

#include "clif.hpp"
#include "map.hpp"
#include "mob.hpp"
#include "pc.hpp"

#include "../poison.hpp"


namespace tmwa
{
namespace map
{
namespace
{
struct SkillInfo
{
    int energy;
    interval_t cooldown;
    int effect;     // client effects.xml id
};

SkillInfo skill_info(HueSkill skill)
{
    switch (skill)
    {
    case HueSkill::DASH:        return {12, 1200_ms, 900};
    case HueSkill::GUST:        return {15, 1500_ms, 901};
    case HueSkill::WIND_SCYTHE: return {4, 500_ms, 902};
    }
    return {0, interval_t::zero(), 0};
}

constexpr int DASH_RANGE = 6;
constexpr int GUST_RADIUS = 3;
constexpr int GUST_PUSH = 4;
constexpr interval_t GUST_STAGGER = 1500_ms;
constexpr int SCYTHE_RADIUS = 2;

int sign(int v)
{
    return (v > 0) - (v < 0);
}

bool can_stand(Borrowed<map_local> m, int x, int y)
{
    return 0 <= x && x < m->xs && 0 <= y && y < m->ys
        && !bool(read_gatp(m, x, y) & MapCell::UNWALKABLE);
}

/// Furthest standable tile up to range steps from (x, y) along (dx, dy).
/// Returns the number of steps taken.
int travel(Borrowed<map_local> m, int& x, int& y, int dx, int dy, int range)
{
    int steps = 0;
    while (steps < range && (dx || dy) && can_stand(m, x + dx, y + dy))
    {
        x += dx;
        y += dy;
        steps++;
    }
    return steps;
}

void place(dumb_ptr<block_list> bl, int x, int y)
{
    map_delblock(bl);
    bl->bl_x = x;
    bl->bl_y = y;
    map_addblock(bl);
}

bool is_vegetation(dumb_ptr<mob_data> md)
{
    int cls = unwrap<Species>(md->mob_class);
    return VEGETATION_FIRST <= cls && cls <= VEGETATION_LAST;
}

/// Whether (x, y) is in front of (or right next to) a being at (px, py)
/// facing (dx, dy), within radius.
bool in_front(int px, int py, int dx, int dy, int x, int y, int radius)
{
    int rx = x - px, ry = y - py;
    if (std::max(std::abs(rx), std::abs(ry)) > radius)
        return false;
    if (std::max(std::abs(rx), std::abs(ry)) <= 1)
        return true;
    return rx * dx + ry * dy > 0;
}

bool dash(dumb_ptr<map_session_data> sd, int dx, int dy)
{
    int x = sd->bl_x, y = sd->bl_y;
    if (!travel(sd->bl_m, x, y, dx, dy, DASH_RANGE))
        return false;
    pc_stop_walking(sd, 0);
    place(sd, x, y);
    sd->to_x = x;
    sd->to_y = y;
    clif_aethyra_slide(sd, 0);
    return true;
}

void gust_push(dumb_ptr<block_list> bl, dumb_ptr<map_session_data> sd,
        int dx, int dy, tick_t tick, int *pushed)
{
    dumb_ptr<mob_data> md = bl->is_mob();
    if (!md || md->hp <= 0 || is_vegetation(md))
        return;
    if (!in_front(sd->bl_x, sd->bl_y, dx, dy, md->bl_x, md->bl_y, GUST_RADIUS))
        return;

    // Away from the caster; straight ahead if standing on the same tile.
    int px = sign(md->bl_x - sd->bl_x), py = sign(md->bl_y - sd->bl_y);
    if (!px && !py)
    {
        px = dx;
        py = dy;
    }
    int x = md->bl_x, y = md->bl_y;
    travel(md->bl_m, x, y, px, py, GUST_PUSH);

    mob_stop_walking(md, 0);
    md->canmove_tick = tick + GUST_STAGGER;
    md->attackabletime = tick + GUST_STAGGER;
    if (x != md->bl_x || y != md->bl_y)
    {
        place(md, x, y);
        md->to_x = x;
        md->to_y = y;
        clif_aethyra_slide(md, 1);
    }
    (*pushed)++;
}

void scythe_cut(dumb_ptr<block_list> bl, dumb_ptr<map_session_data> sd,
        int dx, int dy, int *cut)
{
    dumb_ptr<mob_data> md = bl->is_mob();
    if (!md || md->hp <= 0 || !is_vegetation(md))
        return;
    if (!in_front(sd->bl_x, sd->bl_y, dx, dy, md->bl_x, md->bl_y, SCYTHE_RADIUS))
        return;
    // Killing the plant drops its harvest like any other monster drop.
    mob_damage(sd, md, md->hp, 0);
    (*cut)++;
}
} // anonymous namespace

int hue_gale_max_energy(int base_level)
{
    return 60 + 4 * base_level;
}

void hue_use_skill(dumb_ptr<map_session_data> sd, HueSkill skill, DIR dir)
{
    nullpo_retv(sd);

    SkillInfo info = skill_info(skill);
    if (!info.effect || pc_isdead(sd))
        return;

    int index = static_cast<int>(skill);
    tick_t tick = gettick();
    if (tick < sd->hue_ready[index])
        return;
    if (sd->status.sp < info.energy)
    {
        clif_displaymessage(sd->sess, "Not enough Gale energy."_s);
        return;
    }

    pc_setdir(sd, dir);
    int dx = dirx[dir], dy = diry[dir];
    int x0 = sd->bl_x, y0 = sd->bl_y;

    bool used = false;
    switch (skill)
    {
    case HueSkill::DASH:
        used = dash(sd, dx, dy);
        break;
    case HueSkill::GUST:
    {
        int pushed = 0;
        map_foreachinarea(std::bind(gust_push, std::placeholders::_1, sd,
                    dx, dy, tick, &pushed),
                sd->bl_m,
                x0 - GUST_RADIUS, y0 - GUST_RADIUS,
                x0 + GUST_RADIUS, y0 + GUST_RADIUS,
                BL::MOB);
        used = true;    // a gust into empty air still costs energy
        break;
    }
    case HueSkill::WIND_SCYTHE:
    {
        int cut = 0;
        map_foreachinarea(std::bind(scythe_cut, std::placeholders::_1, sd,
                    dx, dy, &cut),
                sd->bl_m,
                x0 - SCYTHE_RADIUS, y0 - SCYTHE_RADIUS,
                x0 + SCYTHE_RADIUS, y0 + SCYTHE_RADIUS,
                BL::MOB);
        used = true;
        break;
    }
    }

    if (!used)
        return;

    sd->hue_ready[index] = tick + info.cooldown;
    pc_heal(sd, 0, -info.energy);
    clif_specialeffect(sd, info.effect, 0);
}
} // namespace map
} // namespace tmwa
