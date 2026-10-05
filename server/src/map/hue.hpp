#pragma once
//    hue.hpp - Aethyra hue skills
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

#include "fwd.hpp"

#include <cstdint>

#include "../generic/dumb_ptr.hpp"

#include "../mmo/clif.t.hpp"


namespace tmwa
{
namespace map
{
/// Gale starter skills. Values are the skill ids of CMSG_AETHYRA_USE_SKILL.
enum class HueSkill : uint8_t
{
    DASH = 1,
    GUST = 2,
    WIND_SCYTHE = 3,
};

/// Monster classes in this range are vegetation: they cannot move or
/// attack, and only Wind Scythe harvests them.
constexpr int VEGETATION_FIRST = 1100;
constexpr int VEGETATION_LAST = 1199;

/// Gale energy (the SP pool) for a character of this level.
int hue_gale_max_energy(int base_level);

/// Use a skill facing dir. Ignores the request (with no feedback beyond a
/// failed-skill message) when the skill is cooling down or energy is short.
void hue_use_skill(dumb_ptr<map_session_data> sd, HueSkill skill, DIR dir);
} // namespace map
} // namespace tmwa
