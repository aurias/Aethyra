#include "hue_db.hpp"
//    hue_db.cpp - Aethyra hue definitions and balance data
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

#include <algorithm>
#include <set>

#include "../strings/astring.hpp"
#include "../strings/xstring.hpp"

#include "../io/cxxstdio.hpp"
#include "../io/extract.hpp"
#include "../io/read.hpp"

#include "../mmo/config_parse.hpp"

#include "itemdb.hpp"

#include "../poison.hpp"


namespace tmwa
{
namespace map
{
HueBalance hue_balance;

namespace
{
std::map<int, std::vector<HueSkillRank>> skills;
std::map<int, HueVesselDef> vessels;
std::map<int, HueGrant> origins;
std::vector<HueGrant> profiles;
struct Region { RString map; Hue hue; int pct; };
std::vector<Region> regions;

const ZString HUE_NAMES[] =
{
    "gale"_s, "tide"_s, "ember"_s, "terra"_s,
    "verdant"_s, "aura"_s, "decay"_s, "void"_s,
};

bool kind_from_name(XString name, HueActionKind *out)
{
    if (name == "dash"_s) *out = HueActionKind::DASH;
    else if (name == "gust"_s) *out = HueActionKind::GUST;
    else if (name == "scythe"_s) *out = HueActionKind::SCYTHE;
    else if (name == "flow"_s) *out = HueActionKind::FLOW;
    else return false;
    return true;
}

/// Call fn for every non-comment line; stops and fails on the first bad one.
template<class F>
bool each_line(ZString dir, ZString file, F fn)
{
    AString path = STRPRINTF("%s/%s"_fmt, dir, file);
    io::ReadFile in(path);
    if (!in.is_open())
    {
        PRINTF("hue_db: cannot read %s\n"_fmt, path);
        return false;
    }
    AString line;
    int n = 0;
    while (in.getline(line))
    {
        n++;
        XString text = line.rstrip();
        if (is_comment(text))
            continue;
        if (!fn(text))
        {
            PRINTF("hue_db: %s line %d is invalid:\n  %s\n"_fmt, path, n, line);
            return false;
        }
    }
    return true;
}

/// "1:1,2:1" -> {(1, 1), (2, 1)}
bool parse_skill_list(XString text, std::vector<std::pair<int, int>> *out)
{
    std::vector<XString> entries;
    if (!extract(text, vrec<','>(&entries)))
        return false;
    for (XString entry : entries)
    {
        int id, rank;
        if (!extract(entry, record<':'>(&id, &rank)))
            return false;
        if (!hue_skill_rank(id, rank))
            return false;
        out->push_back({id, rank});
    }
    return true;
}

bool read_balance(ZString dir)
{
    HueBalance b;
    bool ok = each_line(dir, "balance.conf"_s, [&b](XString line)
    {
        XString key, value;
        if (!extract(line, record<':'>(&key, &value)))
            return false;
        value = value.lstrip();
        if (key == "mastery_row"_s)
        {
            HueMasteryRow r;
            if (!extract(value, record<' '>(&r.mastery, &r.capacity, &r.regen,
                            &r.current, &r.allowance, &r.flow_pct)))
                return false;
            if (!b.rows.empty() && r.mastery <= b.rows.back().mastery)
                return false;
            b.rows.push_back(r);
            return true;
        }
        struct { ZString name; int *field; } ints[] =
        {
            {"balance_version"_s, &b.version},
            {"activation_ceiling"_s, &b.activation_ceiling},
            {"regen_interval_ms"_s, &b.regen_interval_ms},
            {"mastery_xp_per_level"_s, &b.mastery_xp_per_level},
            {"skill_points_per_level"_s, &b.skill_points_per_level},
            {"award_window_ms"_s, &b.award_window_ms},
            {"award_decay_pct"_s, &b.award_decay_pct},
            {"award_floor_pct"_s, &b.award_floor_pct},
            {"overload_max_ratio_pct"_s, &b.overload_max_ratio_pct},
            {"destroy_base_pct"_s, &b.destroy_base_pct},
            {"destroy_slope_pct"_s, &b.destroy_slope_pct},
            {"destroy_mastery_pct"_s, &b.destroy_mastery_pct},
            {"success_base_pct"_s, &b.success_base_pct},
            {"success_slope_pct"_s, &b.success_slope_pct},
            {"success_mastery_pct"_s, &b.success_mastery_pct},
            {"overload_wear"_s, &b.overload_wear},
        };
        for (auto& f : ints)
            if (key == f.name)
                return extract(value, f.field);
        return false;
    });
    if (!ok)
        return false;
    if (b.rows.empty() || b.rows.front().mastery > 1 || !b.version
            || b.regen_interval_ms < 100 || b.mastery_xp_per_level < 1
            || b.overload_max_ratio_pct < 100)
    {
        PRINTF("hue_db: balance.conf needs balance_version, a mastery_row "
                "for mastery 1 and sane intervals\n"_fmt);
        return false;
    }
    hue_balance = std::move(b);
    return true;
}

bool read_skills(ZString dir)
{
    skills.clear();
    bool ok = each_line(dir, "skills.txt"_s, [](XString line)
    {
        HueSkillRank s;
        XString hue, kind;
        if (!extract(line, record<'|'>(&s.id, &s.rank, &s.name, &hue, &kind,
                        &s.energy, &s.current, &s.exec_ms, &s.cooldown_ms,
                        &s.req_level, &s.req_mastery, &s.req_prof,
                        &s.prof_cap, &s.p1, &s.p2, &s.p3, &s.prof_award,
                        &s.mastery_award, &s.exp_award, &s.description)))
            return false;
        if (!hue_from_name(hue, &s.hue) || !kind_from_name(kind, &s.kind))
            return false;
        if (s.id <= 0 || s.id >= MAX_HUE_SKILL_ID || s.name.size() > 23
                || s.description.size() > 79 || s.energy < 0
                || s.current < 0 || s.energy > 0xffff || s.current > 0xffff)
            return false;
        // Usable actions draw energy at some current; perks draw nothing.
        if ((s.kind == HueActionKind::FLOW) != (s.current == 0))
            return false;
        if (s.kind != HueActionKind::FLOW && s.energy == 0)
            return false;
        auto& ranks = skills[s.id];
        if (s.rank != int(ranks.size()) + 1)
            return false;   // ranks must be listed 1, 2, 3...
        if (!ranks.empty() && (ranks[0].kind != s.kind || ranks[0].hue != s.hue))
            return false;
        ranks.push_back(std::move(s));
        return true;
    });
    return ok && !skills.empty();
}

bool read_vessels(ZString dir)
{
    vessels.clear();
    return each_line(dir, "vessels.txt"_s, [](XString line)
    {
        HueVesselDef v;
        int item;
        XString hue;
        if (!extract(line, record<'|'>(&item, &hue, &v.grade, &v.capacity,
                        &v.safe_current, &v.max_condition, &v.initial_charge,
                        &v.label)))
            return false;
        v.item = wrap<ItemNameId>(item);
        if (!hue_from_name(hue, &v.hue) || itemdb_exists(v.item).is_none())
            return false;
        if (v.capacity <= 0 || v.safe_current <= 0 || v.max_condition <= 0
                || v.initial_charge < 0 || v.initial_charge > v.capacity
                || v.capacity > 4000000)
            return false;
        return vessels.insert({item, std::move(v)}).second;
    });
}

bool read_grant(XString line, HueGrant *g, int *id, bool profile)
{
    XString hue, list;
    bool ok = profile
        ? extract(line, record<'|'>(&g->name, &hue, &g->mastery,
                    &g->mastery_cap, &list, &g->skill_points, &g->level))
        : extract(line, record<'|'>(id, &g->name, &hue, &g->mastery,
                    &g->mastery_cap, &list, &g->skill_points));
    return ok && hue_from_name(hue, &g->hue)
        && 1 <= g->mastery && g->mastery <= g->mastery_cap
        && g->mastery_cap <= 50 && parse_skill_list(list, &g->skills);
}

bool read_origins(ZString dir)
{
    origins.clear();
    profiles.clear();
    bool ok = each_line(dir, "origins.txt"_s, [](XString line)
    {
        HueGrant g;
        int id;
        return read_grant(line, &g, &id, false) && id > 0 && id < 256
            && origins.insert({id, std::move(g)}).second;
    });
    ok = ok && each_line(dir, "profiles.txt"_s, [](XString line)
    {
        HueGrant g;
        int id;
        if (!read_grant(line, &g, &id, true))
            return false;
        profiles.push_back(std::move(g));
        return true;
    });
    // Character creation has no homeland choice yet; origin 1 is the default.
    return ok && hue_origin(1);
}

bool read_regions(ZString dir)
{
    regions.clear();
    return each_line(dir, "regions.txt"_s, [](XString line)
    {
        Region r;
        XString hue;
        if (!extract(line, record<'|'>(&r.map, &hue, &r.pct)))
            return false;
        if (!hue_from_name(hue, &r.hue) || r.pct < 0 || r.pct > 1000)
            return false;
        regions.push_back(std::move(r));
        return true;
    });
}
} // anonymous namespace

ZString hue_name(Hue hue)
{
    if (hue >= Hue::COUNT)
        return "unknown"_s;
    return HUE_NAMES[static_cast<int>(hue)];
}

bool hue_from_name(XString name, Hue *out)
{
    for (int i = 0; i < static_cast<int>(Hue::COUNT); ++i)
    {
        if (name == HUE_NAMES[i])
        {
            *out = static_cast<Hue>(i);
            return true;
        }
    }
    return false;
}

const HueSkillRank *hue_skill_rank(int id, int rank)
{
    auto it = skills.find(id);
    if (it == skills.end() || rank < 1 || rank > int(it->second.size()))
        return nullptr;
    return &it->second[rank - 1];
}

int hue_skill_max_rank(int id)
{
    auto it = skills.find(id);
    return it == skills.end() ? 0 : int(it->second.size());
}

const std::map<int, std::vector<HueSkillRank>>& hue_all_skills()
{
    return skills;
}

const HueVesselDef *hue_vessel(ItemNameId item)
{
    auto it = vessels.find(unwrap<ItemNameId>(item));
    return it == vessels.end() ? nullptr : &it->second;
}

const std::map<int, HueVesselDef>& hue_all_vessels()
{
    return vessels;
}

const HueGrant *hue_origin(int id)
{
    auto it = origins.find(id);
    return it == origins.end() ? nullptr : &it->second;
}

const HueGrant *hue_profile(XString name)
{
    for (const HueGrant& g : profiles)
        if (g.name == name)
            return &g;
    return nullptr;
}

const HueMasteryRow& hue_mastery_row(int mastery)
{
    const HueMasteryRow *row = &hue_balance.rows.front();
    for (const HueMasteryRow& r : hue_balance.rows)
        if (r.mastery <= mastery)
            row = &r;
    return *row;
}

int hue_region_pct(XString map, Hue hue)
{
    for (const Region& r : regions)
        if (r.hue == hue && r.map == map)
            return r.pct;
    return hue == Hue::GALE ? 100 : 0;
}

bool hue_readdb(ZString dir)
{
    // Skills before origins (grants name skills); items are already loaded.
    bool ok = read_balance(dir) && read_skills(dir) && read_vessels(dir)
        && read_origins(dir) && read_regions(dir);
    if (ok)
        PRINTF("hue_db: balance v%d, %zu skills, %zu vessels, %zu origins, "
                "%zu profiles\n"_fmt, hue_balance.version, skills.size(),
                vessels.size(), origins.size(), profiles.size());
    return ok;
}
} // namespace map
} // namespace tmwa
