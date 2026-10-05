#pragma once
//    hue_db.hpp - Aethyra hue definitions and balance data
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

// Static definitions read from world/db/hue: skills (one entry per rank),
// natural vessels, origins, developer profiles, regional concentration and
// the balance table. Runtime state lives in CharData::hue (saved) and in
// map_session_data (per session); see hue.hpp.

#include "fwd.hpp"

#include <cstdint>

#include <map>
#include <vector>

#include "../strings/rstring.hpp"
#include "../strings/zstring.hpp"

#include "../mmo/ids.hpp"


namespace tmwa
{
namespace map
{
/// The defined hues, in save order.
enum class Hue : uint8_t
{
    GALE, TIDE, EMBER, TERRA, VERDANT, AURA, DECAY, VOID_,
    COUNT
};

/// What a skill does when used. New kinds need code; new numbers are data.
enum class HueActionKind : uint8_t
{
    NONE = 0,
    DASH = 1,       // move the user along a line
    GUST = 2,       // displace enemies in front, no damage
    SCYTHE = 3,     // harvest vegetation in front
    FLOW = 10,      // permanent perk: more safe current from vessels
};

/// Skill ids must stay below this (they index per-session arrays).
constexpr int MAX_HUE_SKILL_ID = 32;

struct HueSkillRank
{
    int id = 0, rank = 0;
    RString name;
    Hue hue = Hue::GALE;
    HueActionKind kind = HueActionKind::NONE;
    int energy = 0, current = 0;
    int exec_ms = 0, cooldown_ms = 0;
    int req_level = 0, req_mastery = 0, req_prof = 0, prof_cap = 0;
    int p1 = 0, p2 = 0, p3 = 0;
    int prof_award = 0, mastery_award = 0, exp_award = 0;
    RString description;
};

struct HueVesselDef
{
    ItemNameId item;
    Hue hue = Hue::GALE;
    int grade = 1;
    int capacity = 0;       // energy per unit
    int safe_current = 0;   // per stack, whatever its size
    int max_condition = 0;
    int initial_charge = 0; // energy per unit when first obtained
    RString label;
};

struct HueGrant
{
    RString name;
    Hue hue = Hue::GALE;
    int mastery = 1, mastery_cap = 10;
    std::vector<std::pair<int, int>> skills;    // id, rank
    int skill_points = 0;
    int level = 0;          // profiles only
};

struct HueMasteryRow
{
    int mastery = 0, capacity = 0, regen = 0, current = 0, allowance = 0,
        flow_pct = 0;
};

struct HueBalance
{
    int version = 0;
    std::vector<HueMasteryRow> rows;
    int activation_ceiling = 3;
    int regen_interval_ms = 1000;
    int mastery_xp_per_level = 20;
    int skill_points_per_level = 1;
    int award_window_ms = 60000, award_decay_pct = 15, award_floor_pct = 25;
    int overload_max_ratio_pct = 300;
    int destroy_base_pct = 35, destroy_slope_pct = 50, destroy_mastery_pct = 1;
    int success_base_pct = 90, success_slope_pct = 30, success_mastery_pct = 1;
    int overload_wear = 40;
};

extern HueBalance hue_balance;

/// Read every definition file in dir (the hue_db key of tmwa-map.conf).
bool hue_readdb(ZString dir);

ZString hue_name(Hue hue);
bool hue_from_name(XString name, Hue *out);

/// Definition of skill id at rank (1-based), or nullptr.
const HueSkillRank *hue_skill_rank(int id, int rank);
int hue_skill_max_rank(int id);
const std::map<int, std::vector<HueSkillRank>>& hue_all_skills();

const HueVesselDef *hue_vessel(ItemNameId item);
const std::map<int, HueVesselDef>& hue_all_vessels();

const HueGrant *hue_origin(int id);
const HueGrant *hue_profile(XString name);

/// Capability row for a mastery value (the highest row not above it).
const HueMasteryRow& hue_mastery_row(int mastery);

/// Percent of normal regeneration for hue on the named map.
int hue_region_pct(XString map, Hue hue);
} // namespace map
} // namespace tmwa
