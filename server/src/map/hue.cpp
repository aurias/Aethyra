#include "hue.hpp"
//    hue.cpp - Aethyra hue rules: character hue state, vessels and actions
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

// The server owns every hue rule: what a character knows, the energy it
// holds, which supplies an action draws on, the overload rolls, item loss
// and progression. Definitions and tuning come from world/db/hue (see
// hue_db.cpp); nothing here hard-codes a cost.
//
// An action resolves in five steps (framework section 5.3):
//   1. validate: learned skill, hue access, cooldown, activation allowance,
//      target; nothing is spent when this fails;
//   2. plan the supply: the character's own reserve first (up to the
//      current it can channel), then the selected vessel stacks in order,
//      each up to its safe current;
//   3. check energy, then current; when only overloading a vessel stack
//      could deliver the current, the player must accept the risk;
//   4. roll (server-side) for the action's success and, per overloaded
//      stack, its destruction;
//   5. commit spending, wear, destruction, effects and awards together,
//      then tell the client the outcome.

#include <algorithm>

#include "../compat/nullpo.hpp"

#include "../strings/astring.hpp"
#include "../strings/vstring.hpp"

#include "../io/cxxstdio.hpp"

#include "../net/timer.hpp"

#include "../proto2/map-user.hpp"

#include "../wire/packets.hpp"

#include "clif.hpp"
#include "itemdb.hpp"
#include "map.hpp"
#include "mob.hpp"
#include "pc.hpp"
#include "terrain.hpp"

#include "../poison.hpp"


namespace tmwa
{
namespace map
{
namespace
{
constexpr int HUE_COUNT = static_cast<int>(Hue::COUNT);

// --------------------------------------------------------------------------
// State access

HueRecord& record_of(dumb_ptr<map_session_data> sd, Hue hue)
{
    return sd->status.hue.hues[static_cast<int>(hue)];
}

HueSkillRecord *skill_record(dumb_ptr<map_session_data> sd, int id)
{
    for (HueSkillRecord& sk : sd->status.hue.skills)
        if (sk.id == id)
            return &sk;
    return nullptr;
}

int learned_rank(dumb_ptr<map_session_data> sd, int id)
{
    HueSkillRecord *sk = skill_record(sd, id);
    return sk ? sk->rank : 0;
}

int capacity_of(const HueRecord& r)
{
    return r.access ? hue_mastery_row(r.mastery).capacity : 0;
}

/// Flow bonus for a hue: the mastery row plus learned flow perks.
int flow_pct(dumb_ptr<map_session_data> sd, Hue hue)
{
    int pct = hue_mastery_row(record_of(sd, hue).mastery).flow_pct;
    for (const HueSkillRecord& sk : sd->status.hue.skills)
    {
        const HueSkillRank *def = hue_skill_rank(sk.id, sk.rank);
        if (def && def->kind == HueActionKind::FLOW && def->hue == hue)
            pct += def->p1;
    }
    return pct;
}

uint32_t mastery_next(int mastery)
{
    return uint32_t(std::max(mastery, 1)) * hue_balance.mastery_xp_per_level;
}

int region_pct(dumb_ptr<map_session_data> sd, Hue hue)
{
    return hue_region_pct(sd->bl_m->name_, hue);
}

void prune_activations(dumb_ptr<map_session_data> sd, tick_t tick)
{
    auto& active = sd->hue.active;
    active.erase(std::remove_if(active.begin(), active.end(),
                [tick](const HueSession::Activation& a) { return a.until <= tick; }),
            active.end());
}

int active_count(dumb_ptr<map_session_data> sd, Hue hue)
{
    int n = 0;
    for (const auto& a : sd->hue.active)
        if (a.hue == static_cast<uint8_t>(hue))
            n++;
    return n;
}

/// xorshift32: fast, deterministic once seeded by the developer fixture.
uint32_t next_random(dumb_ptr<map_session_data> sd)
{
    uint32_t x = sd->hue.rng;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    sd->hue.rng = x;
    return x;
}

bool roll(dumb_ptr<map_session_data> sd, int pct)
{
    return int(next_random(sd) % 100) < pct;
}

int clamp(int v, int lo, int hi)
{
    return std::max(lo, std::min(v, hi));
}

void debug(dumb_ptr<map_session_data> sd, XString text)
{
    if (sd->hue.debug)
        clif_displaymessage(sd->sess, text);
}

// --------------------------------------------------------------------------
// Vessel lots

/// Inventory slot holding an initialised vessel stack of the given hue.
const HueVesselDef *vessel_at(dumb_ptr<map_session_data> sd, IOff0 i)
{
    if (!i.ok())
        return nullptr;
    const Item& item = sd->status.inventory[i];
    if (!item.nameid || item.amount <= 0 || !(item.lot_flags & LOT_INITIALISED))
        return nullptr;
    return hue_vessel(item.nameid);
}

/// Energy a stack holds, in whole units.
int64_t lot_energy(const Item& item)
{
    return int64_t(item.hue_charge) * item.amount / 1000;
}

int supply_order(dumb_ptr<map_session_data> sd, IOff0 i)
{
    for (int k = 0; k < MAX_HUE_SUPPLY; ++k)
        if (sd->status.hue.supply[k] == i.index + 1)
            return k + 1;
    return 0;
}

void remove_supply(dumb_ptr<map_session_data> sd, IOff0 i)
{
    auto& supply = sd->status.hue.supply;
    int out = 0;
    for (int k = 0; k < MAX_HUE_SUPPLY; ++k)
        if (supply[k] && supply[k] != i.index + 1)
            supply[out++] = supply[k];
    while (out < MAX_HUE_SUPPLY)
        supply[out++] = 0;
}

// --------------------------------------------------------------------------
// Packets

void send_state(dumb_ptr<map_session_data> sd)
{
    Session *s = sd->sess;
    if (!s)
        return;
    const HueState& st = sd->status.hue;
    Packet_Head<0x021a> head;
    head.origin = st.origin;
    head.version = st.version;
    head.skill_points = st.skill_points;
    head.ceiling = hue_balance.activation_ceiling;
    head.active = sd->hue.active.size();
    head.balance_version = hue_balance.version;
    std::vector<Packet_Repeat<0x021a>> repeat;
    for (int i = 0; i < HUE_COUNT; ++i)
    {
        const HueRecord& r = st.hues[i];
        if (!r.access)
            continue;
        Hue hue = static_cast<Hue>(i);
        const HueMasteryRow& row = hue_mastery_row(r.mastery);
        Packet_Repeat<0x021a> info;
        info.hue = i;
        info.access = r.access;
        info.mastery = r.mastery;
        info.mastery_cap = r.mastery_cap;
        info.mastery_xp = r.mastery_xp;
        info.mastery_next = mastery_next(r.mastery);
        info.energy = r.energy;
        info.capacity = row.capacity;
        info.regen = row.regen;
        info.regen_pct = region_pct(sd, hue);
        info.current = row.current;
        info.flow_pct = flow_pct(sd, hue);
        info.allowance = row.allowance;
        info.allowance_used = active_count(sd, hue);
        repeat.push_back(info);
    }
    send_vpacket<0x021a, 12, 30>(s, head, repeat);
}

void send_skills(dumb_ptr<map_session_data> sd)
{
    Session *s = sd->sess;
    if (!s)
        return;
    Packet_Head<0x021b> head;
    std::vector<Packet_Repeat<0x021b>> repeat;
    for (const HueSkillRecord& sk : sd->status.hue.skills)
    {
        if (!sk.id)
            continue;
        Packet_Repeat<0x021b> info;
        info.id = sk.id;
        info.rank = sk.rank;
        info.proficiency = sk.proficiency;
        repeat.push_back(info);
    }
    send_vpacket<0x021b, 4, 7>(s, head, repeat);
}

void send_definitions(dumb_ptr<map_session_data> sd)
{
    Session *s = sd->sess;
    if (!s)
        return;
    Packet_Head<0x021f> head;
    std::vector<Packet_Repeat<0x021f>> repeat;
    for (const auto& pair : hue_all_skills())
    {
        for (const HueSkillRank& d : pair.second)
        {
            Packet_Repeat<0x021f> info;
            info.kind = 0;
            info.rank = d.rank;
            info.id = d.id;
            info.hue = static_cast<uint8_t>(d.hue);
            info.action = static_cast<uint8_t>(d.kind);
            info.max_rank = pair.second.size();
            info.name = VString<23>(d.name);
            info.p0 = d.energy;
            info.p1 = d.current;
            info.p2 = d.exec_ms;
            info.p3 = d.cooldown_ms;
            info.p4 = d.req_level;
            info.p5 = d.req_mastery;
            info.p6 = d.req_prof;
            info.p7 = std::min(d.prof_cap, 0xffff);
            info.p8 = d.p1;
            info.p9 = d.p2;
            info.p10 = d.p3;
            info.description = VString<79>(d.description);
            repeat.push_back(info);
        }
    }
    for (const auto& pair : hue_all_vessels())
    {
        const HueVesselDef& v = pair.second;
        Packet_Repeat<0x021f> info;
        info.kind = 1;
        info.id = pair.first;
        info.hue = static_cast<uint8_t>(v.hue);
        info.name = VString<23>(v.label.xislice_h(
                    v.label.begin() + std::min<size_t>(v.label.size(), 23)));
        info.p0 = std::min(v.capacity, 0xffff);
        info.p1 = v.safe_current;
        info.p2 = v.max_condition;
        info.p3 = v.grade;
        info.p4 = std::min(v.initial_charge, 0xffff);
        info.description = VString<79>(v.label.xislice_h(
                    v.label.begin() + std::min<size_t>(v.label.size(), 79)));
        repeat.push_back(info);
    }
    for (const HueCombo& c : hue_all_combos())
    {
        Packet_Repeat<0x021f> info;
        info.kind = 2;
        info.id = c.base;
        info.p0 = c.modifier;
        info.p1 = c.effect_pct;
        info.p2 = c.energy_pct;
        info.p3 = c.current_pct;
        info.action = static_cast<uint8_t>(c.effect);
        info.description = VString<79>(c.description);
        repeat.push_back(info);
    }
    send_vpacket<0x021f, 4, 136>(s, head, repeat);
}

struct ResultInfo
{
    uint32_t request = 0;
    int skill = 0;
    HueOutcome outcome = HueOutcome::REJECTED;
    HueReason reason = HueReason::OK;
    int energy = 0, current = 0, channel = 0;
    int personal_spent = 0, vessel_spent = 0;
    int detail = 0;
    int modifier = 0, modifier_personal = 0, modifier_vessel = 0;
    int modifier_detail = 0;
};

struct VesselReport
{
    IOff0 index;
    ItemNameId nameid;
    int amount, spent;
    VesselFate fate;
    int load_pct;
};

void send_result(dumb_ptr<map_session_data> sd, const ResultInfo& r,
        const std::vector<VesselReport>& vessels)
{
    Session *s = sd->sess;
    if (!s)
        return;
    Packet_Head<0x0219> head;
    head.request = r.request;
    head.skill = r.skill;
    head.outcome = static_cast<uint8_t>(r.outcome);
    head.reason = static_cast<uint8_t>(r.reason);
    head.energy = clamp(r.energy, 0, 0xffff);
    head.current = clamp(r.current, 0, 0xffff);
    head.channel = clamp(r.channel, 0, 0xffff);
    head.personal_spent = clamp(r.personal_spent, 0, 0xffff);
    head.vessel_spent = clamp(r.vessel_spent, 0, 0xffff);
    head.detail = clamp(r.detail, 0, 0xffff);
    head.modifier = r.modifier;
    head.modifier_personal = clamp(r.modifier_personal, 0, 0xffff);
    head.modifier_vessel = clamp(r.modifier_vessel, 0, 0xffff);
    head.modifier_detail = clamp(r.modifier_detail, 0, 0xffff);
    std::vector<Packet_Repeat<0x0219>> repeat;
    for (const VesselReport& v : vessels)
    {
        Packet_Repeat<0x0219> info;
        info.ioff2 = v.index.shift();
        info.name_id = v.nameid;
        info.amount = v.amount;
        info.spent = clamp(v.spent, 0, 0xffff);
        info.fate = static_cast<uint8_t>(v.fate);
        info.load_pct = clamp(v.load_pct, 0, 0xffff);
        repeat.push_back(info);
    }
    send_vpacket<0x0219, 32, 11>(s, head, repeat);
}

void reject(dumb_ptr<map_session_data> sd, ResultInfo r, HueReason reason,
        int detail)
{
    r.outcome = HueOutcome::REJECTED;
    r.reason = reason;
    r.detail = detail;
    send_result(sd, r, {});
}

// --------------------------------------------------------------------------
// Movement and effects (unchanged demo behaviour, parameters from data)

int sign(int v)
{
    return (v > 0) - (v < 0);
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

/// Whether a being other than self stands on (x, y).
bool occupied(Borrowed<map_local> m, int x, int y, dumb_ptr<block_list> self)
{
    bool found = false;
    map_foreachinarea([&found, self](dumb_ptr<block_list> bl)
            {
                if (bl == self)
                    return;
                if (dumb_ptr<mob_data> md = bl->is_mob())
                {
                    // One can land among plants.
                    if (md->hp > 0 && !is_vegetation(md))
                        found = true;
                }
                else if (bl->bl_type == BL::PC || bl->bl_type == BL::NPC)
                    found = true;
            },
            m, x, y, x, y, BL::NUL);
    return found;
}

/// Furthest point up to range ground steps from (x, y) along (dx, dy).
/// Returns the number of steps taken.
int ground_travel(Borrowed<map_local> m, int& x, int& y, int dx, int dy,
        int range)
{
    int steps = 0;
    while (steps < range && (dx || dy) && terrain_ground_step(m, x, y, dx, dy))
    {
        x += dx;
        y += dy;
        steps++;
    }
    return steps;
}

struct GustHit
{
    BlockId id;
    bool fell;
};

void gust_push(dumb_ptr<block_list> bl, dumb_ptr<map_session_data> sd,
        int dx, int dy, const HueSkillRank *def, tick_t tick,
        std::vector<GustHit> *hits)
{
    dumb_ptr<mob_data> md = bl->is_mob();
    if (!md || md->hp <= 0 || is_vegetation(md))
        return;
    if (!in_front(sd->bl_x, sd->bl_y, dx, dy, md->bl_x, md->bl_y, def->p1))
        return;
    // Wind does not blow through a cliff: only beings on the caster's level.
    if (!terrain_same_level(sd->bl_m, sd->bl_x, sd->bl_y, md->bl_x, md->bl_y))
        return;

    // Away from the caster; straight ahead if standing on the same tile.
    int px = sign(md->bl_x - sd->bl_x), py = sign(md->bl_y - sd->bl_y);
    if (!px && !py)
    {
        px = dx;
        py = dy;
    }
    int x = md->bl_x, y = md->bl_y;
    int pushed = ground_travel(md->bl_m, x, y, px, py, def->p2);
    bool fell = false;
    if (pushed < def->p2)
    {
        // Blown against a ledge with push to spare: over it, if a free
        // landing lies below within reach. Otherwise it stops at the edge.
        Leap leap = terrain_leap(md->bl_m, x, y, px, py, -1,
                hue_balance.ledge_fall_max_levels,
                hue_balance.ledge_fall_max_span);
        if (leap.result == LeapResult::OK
                && !occupied(md->bl_m, leap.x, leap.y, md))
        {
            x = leap.x;
            y = leap.y;
            fell = true;
        }
    }

    interval_t stagger = std::chrono::milliseconds(def->p3
            + (fell ? hue_balance.fall_stagger_ms : 0));
    mob_stop_walking(md, 0);
    md->canmove_tick = tick + stagger;
    md->attackabletime = tick + stagger;
    if (x != md->bl_x || y != md->bl_y)
    {
        place(md, x, y);
        md->to_x = x;
        md->to_y = y;
        clif_aethyra_slide(md, fell ? 4 : 1);
        hits->push_back({md->bl_id, fell});
        // Gust itself never harms; a fall may, if the policy says so.
        if (fell && hue_balance.fall_damage_pct > 0)
        {
            int damage = md->stats[mob_stat::MAX_HP] * hue_balance.fall_damage_pct / 100;
            if (damage > 0)
            {
                clif_damage(md, md, tick, interval_t::zero(), interval_t::zero(),
                        damage, 0, DamageType::NORMAL);
                mob_damage(nullptr, md, damage, 0);
            }
        }
    }
}

void scythe_cut(dumb_ptr<block_list> bl, dumb_ptr<map_session_data> sd,
        int dx, int dy, int radius, int *cut)
{
    dumb_ptr<mob_data> md = bl->is_mob();
    if (!md || md->hp <= 0 || !is_vegetation(md))
        return;
    if (!in_front(sd->bl_x, sd->bl_y, dx, dy, md->bl_x, md->bl_y, radius))
        return;
    // Killing the plant drops its harvest like any other monster drop.
    mob_damage(sd, md, md->hp, 0);
    (*cut)++;
}

int effect_of(HueActionKind kind)
{
    switch (kind)
    {
    case HueActionKind::DASH: return 900;
    case HueActionKind::GUST: return 901;
    case HueActionKind::SCYTHE: return 902;
    case HueActionKind::FEATHERFALL: return 906;
    case HueActionKind::JUMP: return 907;
    case HueActionKind::SPARK: return 903;
    default: return 0;
    }
}

// --------------------------------------------------------------------------
// Awards

/// Percent of a full award for another award of this skill now.
int award_pct(dumb_ptr<map_session_data> sd, int skill, tick_t tick)
{
    auto& recent = sd->hue.awards[skill];
    interval_t window = std::chrono::milliseconds(hue_balance.award_window_ms);
    recent.erase(std::remove_if(recent.begin(), recent.end(),
                [tick, window](tick_t t) { return t + window <= tick; }),
            recent.end());
    int pct = std::max(hue_balance.award_floor_pct,
            100 - hue_balance.award_decay_pct * int(recent.size()));
    recent.push_back(tick);
    return pct;
}

void add_mastery_xp(dumb_ptr<map_session_data> sd, Hue hue, int xp)
{
    HueRecord& r = record_of(sd, hue);
    r.mastery_xp += xp;
    while (r.mastery < r.mastery_cap && r.mastery_xp >= mastery_next(r.mastery))
    {
        r.mastery_xp -= mastery_next(r.mastery);
        r.mastery++;
        clif_displaymessage(sd->sess, STRPRINTF(
                    "Your %s mastery rose to %d."_fmt, hue_name(hue), r.mastery));
    }
    // At the cap, progress stops short of the next level until the cap rises.
    if (r.mastery >= r.mastery_cap)
        r.mastery_xp = std::min(r.mastery_xp, mastery_next(r.mastery) - 1);
    // Capacity may have grown; energy never exceeds it.
    r.energy = std::min(r.energy, capacity_of(r));
}

/// Award proficiency, mastery progress and character experience for an
/// action that resolved with a meaningful result (units of it).
void award(dumb_ptr<map_session_data> sd, const HueSkillRank *def, int units,
        tick_t tick)
{
    if (units <= 0)
        return;
    int pct = award_pct(sd, def->id, tick);
    HueSkillRecord *sk = skill_record(sd, def->id);
    if (sk && def->prof_award)
        sk->proficiency = std::min<uint32_t>(def->prof_cap,
                sk->proficiency + def->prof_award * units);
    if (def->mastery_award)
        add_mastery_xp(sd, def->hue, def->mastery_award * units * pct / 100);
    if (def->exp_award)
        pc_gainexp_reason(sd, def->exp_award * units * pct / 100, 0,
                PC_GAINEXP_REASON::SCRIPT);
}

void apply_grant(dumb_ptr<map_session_data> sd, const HueGrant& g)
{
    HueState& st = sd->status.hue;
    for (HueRecord& r : st.hues)
        r = HueRecord{};
    for (HueSkillRecord& sk : st.skills)
        sk = HueSkillRecord{};
    HueRecord& r = record_of(sd, g.hue);
    r.access = 1;
    r.mastery = g.mastery;
    r.mastery_cap = g.mastery_cap;
    r.energy = capacity_of(r);
    int k = 0;
    for (const auto& pair : g.skills)
    {
        st.skills[k].id = pair.first;
        st.skills[k].rank = pair.second;
        // A granted rank counts as practised up to what it required.
        const HueSkillRank *def = hue_skill_rank(pair.first, pair.second);
        st.skills[k].proficiency = def ? def->req_prof : 0;
        k++;
    }
    st.skill_points = g.skill_points;
}
} // anonymous namespace

// --------------------------------------------------------------------------
// Lots

void hue_init_lot(Item *item)
{
    if (item->lot_flags & LOT_INITIALISED)
        return;
    const HueVesselDef *v = hue_vessel(item->nameid);
    if (!v)
        return;
    // Provisional policy: vessels arrive precharged (recharge undecided).
    item->hue_charge = v->initial_charge * 1000;
    item->condition = v->max_condition;
    item->lot_flags |= LOT_INITIALISED;
}

bool hue_same_lot(const Item& a, const Item& b)
{
    return a.hue_charge == b.hue_charge && a.condition == b.condition
        && a.lot_flags == b.lot_flags;
}

void hue_slot_changed(dumb_ptr<map_session_data> sd, IOff0 index)
{
    if (!vessel_at(sd, index) && supply_order(sd, index))
        remove_supply(sd, index);
}

void hue_send_lot(dumb_ptr<map_session_data> sd, IOff0 index)
{
    Session *s = sd->sess;
    if (!s || !vessel_at(sd, index))
        return;
    const Item& item = sd->status.inventory[index];
    Packet_Fixed<0x021c> fixed;
    fixed.ioff2 = index.shift();
    fixed.name_id = item.nameid;
    fixed.charge = item.hue_charge;
    fixed.condition = item.condition;
    fixed.supply = supply_order(sd, index);
    send_fpacket<0x021c, 13>(s, fixed);
}

// --------------------------------------------------------------------------
// Login, levels, regeneration

void hue_login(dumb_ptr<map_session_data> sd)
{
    nullpo_retv(sd);
    HueState& st = sd->status.hue;
    if (st.version == 0)
    {
        // origin 0: saved before hue state existed; otherwise a new
        // character whose origin the char server recorded.
        bool legacy = st.origin == 0;
        int origin = legacy ? 1 : st.origin;
        const HueGrant *g = hue_origin(origin);
        if (!g)
            g = hue_origin(origin = 1);
        int old_sp = sd->status.sp;
        apply_grant(sd, *g);
        st.origin = origin;
        st.points_level = 1;
        if (legacy)
        {
            // The demo kept Gale energy in SP.
            HueRecord& r = record_of(sd, g->hue);
            r.energy = clamp(old_sp, 0, capacity_of(r));
        }
        st.version = HUE_STATE_VERSION;
        PRINTF("hue: %s character '%s' (origin %d, Gale energy %d)\n"_fmt,
                legacy ? "migrated"_s : "initialised"_s,
                sd->status_key.name, origin, record_of(sd, g->hue).energy);
    }

    // Repair anything definitions no longer allow.
    for (HueSkillRecord& sk : st.skills)
    {
        if (sk.id && !hue_skill_max_rank(sk.id))
            PRINTF("hue: '%s' knows undefined skill %d (kept)\n"_fmt,
                    sd->status_key.name, sk.id);
        else if (sk.id)
            sk.rank = std::min<int>(sk.rank, hue_skill_max_rank(sk.id));
    }
    for (HueRecord& r : st.hues)
        r.energy = clamp(r.energy, 0, capacity_of(r));

    // Stacks from before vessel lots arrive precharged, like new harvests.
    for (IOff0 i : IOff0::iter())
        if (sd->status.inventory[i].nameid)
            hue_init_lot(&sd->status.inventory[i]);
    for (int k = 0; k < MAX_HUE_SUPPLY; ++k)
    {
        int16_t slot = st.supply[k];
        if (slot && (slot > MAX_INVENTORY || !vessel_at(sd, IOff0::from(slot - 1))))
            st.supply[k] = 0;
    }
    remove_supply(sd, IOff0::from(MAX_INVENTORY));   // compact

    hue_level_points(sd);
}

void hue_send_all(dumb_ptr<map_session_data> sd)
{
    nullpo_retv(sd);
    send_definitions(sd);
    send_state(sd);
    send_skills(sd);
    for (IOff0 i : IOff0::iter())
        hue_send_lot(sd, i);
}

void hue_level_points(dumb_ptr<map_session_data> sd)
{
    nullpo_retv(sd);
    HueState& st = sd->status.hue;
    if (!st.version)
        return;
    bool changed = false;
    while (st.points_level < sd->status.base_level && st.points_level < 255)
    {
        st.points_level++;
        st.skill_points += hue_balance.skill_points_per_level;
        changed = true;
    }
    if (changed && sd->state.auth)
        send_state(sd);
}

namespace
{
void regen_one(dumb_ptr<map_session_data> sd)
{
    if (!sd->state.auth || pc_isdead(sd) || !sd->status.hue.version)
        return;
    bool changed = false;
    for (int i = 0; i < HUE_COUNT; ++i)
    {
        HueRecord& r = sd->status.hue.hues[i];
        if (!r.access)
            continue;
        int cap = capacity_of(r);
        int gain = hue_mastery_row(r.mastery).regen
            * region_pct(sd, static_cast<Hue>(i)) / 100;
        int energy = clamp(r.energy + gain, 0, std::max(cap, r.energy));
        if (energy != r.energy)
        {
            r.energy = std::min(energy, cap);
            changed = true;
        }
    }
    // Activations also expire on this clock.
    size_t before = sd->hue.active.size();
    prune_activations(sd, gettick());
    if (changed || before != sd->hue.active.size())
        send_state(sd);
}

void regen_timer(TimerData *, tick_t)
{
    clif_foreachclient(regen_one);
}
} // anonymous namespace

namespace
{
void burn_timer(TimerData *, tick_t tick);
} // anonymous namespace

void do_init_hue()
{
    interval_t every = std::chrono::milliseconds(hue_balance.regen_interval_ms);
    Timer(gettick() + every, regen_timer, every).detach();
    interval_t burn = std::chrono::milliseconds(std::max(hue_balance.burn_tick_ms, 100));
    Timer(gettick() + burn, burn_timer, burn).detach();
}

int hue_restore(dumb_ptr<map_session_data> sd, Hue hue, int amount)
{
    nullpo_retz(sd);
    HueRecord& r = record_of(sd, hue);
    if (!r.access || amount <= 0)
        return 0;
    int before = r.energy;
    r.energy = std::min(r.energy + amount, capacity_of(r));
    send_state(sd);
    return r.energy - before;
}

// --------------------------------------------------------------------------
// Actions

namespace
{
struct Source
{
    IOff0 index;            // ok() only for vessels
    const HueVesselDef *vessel = nullptr;
    int64_t available = 0;  // energy units
    int safe = 0;           // safe current (vessels: after flow bonus)
    int current = 0;        // current this source delivers
    int energy = 0;         // energy this source supplies
};

/// One hue's share of an action: the base skill, or a live modifier.
struct Part
{
    int skill = 0;
    const HueSkillRank *def = nullptr;
    Hue hue = Hue::GALE;
    int E = 0, I = 0;               // demand
    std::vector<Source> sources;    // [0] is the personal reserve
    int safe_channel = 0;
    int worst = 0;                  // worst vessel load, percent
    bool risky = false;
    std::vector<bool> destroyed;
    int personal_spent = 0, vessel_spent = 0;
};

/// Steps 1 (hue, cooldown, allowance) and 2-3 (supply, energy, current)
/// for one part. Returns OK or why it cannot go ahead; detail explains.
HueReason plan_part(dumb_ptr<map_session_data> sd, Part& part, tick_t tick,
        int activations_before, uint8_t flags, int *detail)
{
    const HueSkillRank *def = part.def;
    HueRecord& h = record_of(sd, part.hue);
    if (!h.access)
        return HueReason::NO_ACCESS;
    if (tick < sd->hue.ready[part.skill])
    {
        *detail = (sd->hue.ready[part.skill] - tick).count();
        return HueReason::COOLDOWN;
    }
    const HueMasteryRow& row = hue_mastery_row(h.mastery);
    if (active_count(sd, part.hue) >= row.allowance)
    {
        for (const auto& a : sd->hue.active)
            if (a.hue == static_cast<uint8_t>(part.hue))
                *detail = a.skill;
        return HueReason::ALLOWANCE;
    }
    if (activations_before >= hue_balance.activation_ceiling)
    {
        *detail = sd->hue.active.empty() ? part.skill : sd->hue.active.back().skill;
        return HueReason::CEILING;
    }

    // Own reserve first, then the selected stacks of this hue in order.
    const int E = part.E, I = part.I;
    {
        Source own;
        own.available = h.energy;
        own.safe = row.current;
        own.current = std::min<int64_t>({I, row.current, own.available * I / std::max(E, 1)});
        part.sources.push_back(own);
    }
    int flow = flow_pct(sd, part.hue);
    int remaining = I - part.sources[0].current;
    for (int k = 0; k < MAX_HUE_SUPPLY; ++k)
    {
        int16_t slot = sd->status.hue.supply[k];
        if (!slot)
            continue;
        IOff0 i = IOff0::from(slot - 1);
        const HueVesselDef *v = vessel_at(sd, i);
        if (!v || v->hue != part.hue)
            continue;
        Source src;
        src.index = i;
        src.vessel = v;
        src.available = lot_energy(sd->status.inventory[i]);
        src.safe = v->safe_current * (100 + flow) / 100;
        src.current = std::min<int64_t>({remaining, src.safe,
                src.available * I / std::max(E, 1)});
        remaining -= src.current;
        part.sources.push_back(src);
    }

    int64_t total = 0;
    for (const Source& src : part.sources)
        total += src.available;
    if (total < E)
    {
        *detail = int(std::min<int64_t>(total, 0xffff));
        return HueReason::NO_ENERGY;
    }
    for (const Source& src : part.sources)
        part.safe_channel += src.safe;

    if (remaining > 0)
    {
        // Only by pushing vessel stacks past their safe current.
        for (size_t k = 1; k < part.sources.size() && remaining > 0; ++k)
        {
            Source& src = part.sources[k];
            int room = int(std::min<int64_t>(src.available * I / std::max(E, 1), 0xffff))
                - src.current;
            int extra = std::max(0, std::min(remaining, room));
            src.current += extra;
            remaining -= extra;
        }
        if (remaining > 0)
        {
            *detail = part.safe_channel;
            return HueReason::CURRENT_LIMITED;
        }
        for (size_t k = 1; k < part.sources.size(); ++k)
            if (part.sources[k].current > part.sources[k].safe)
                part.worst = std::max(part.worst,
                        part.sources[k].current * 100 / part.sources[k].safe);
        if (part.worst > hue_balance.overload_max_ratio_pct)
        {
            *detail = part.worst;
            return HueReason::OVERLOAD_LIMIT;
        }
        if (!(flags & HUE_ACCEPT_RISK))
        {
            *detail = part.worst;
            return HueReason::OVERLOAD_RISK;
        }
        part.risky = true;
    }

    // Energy follows each source's share of the current; rounding
    // leftovers go to whichever sources still hold energy.
    int drawn = 0;
    for (Source& src : part.sources)
    {
        src.energy = I ? src.current * E / I : 0;
        drawn += src.energy;
    }
    for (Source& src : part.sources)
    {
        int extra = int(std::min<int64_t>(E - drawn, src.available - src.energy));
        if (extra > 0)
        {
            src.energy += extra;
            drawn += extra;
        }
    }
    part.destroyed.assign(part.sources.size(), false);
    return HueReason::OK;
}

/// Step 4 for one part: roll success and each overloaded stack's fate.
bool roll_part(dumb_ptr<map_session_data> sd, Part& part)
{
    if (!part.risky)
        return true;
    int m = record_of(sd, part.hue).mastery;
    int p_success = clamp(hue_balance.success_base_pct
            - hue_balance.success_slope_pct * (part.worst - 100) / 100
            + hue_balance.success_mastery_pct * m, 2, 100);
    bool success = sd->hue.forced >= 0 ? bool(sd->hue.forced & 1)
        : roll(sd, p_success);
    for (size_t k = 1; k < part.sources.size(); ++k)
    {
        const Source& src = part.sources[k];
        if (src.current <= src.safe)
            continue;
        int load = src.current * 100 / src.safe;
        int p_destroy = clamp(hue_balance.destroy_base_pct
                + hue_balance.destroy_slope_pct * (load - 100) / 100
                - hue_balance.destroy_mastery_pct * m, 0, 98);
        part.destroyed[k] = sd->hue.forced >= 0 ? bool(sd->hue.forced & 2)
            : roll(sd, p_destroy);
        debug(sd, STRPRINTF("[hue] stack %d load %d%%: destroy chance %d%% -> %s"_fmt,
                    src.index.index, load, p_destroy,
                    part.destroyed[k] ? "destroyed"_s : "survives"_s));
    }
    debug(sd, STRPRINTF("[hue] %s worst load %d%%: success chance %d%% -> %s%s"_fmt,
                part.def->name, part.worst, p_success,
                success ? "success"_s : "failure"_s,
                sd->hue.forced >= 0 ? " (forced)"_s : ""_s));
    return success;
}

/// Step 5 for one part's supply: spend, wear and destroy.
void commit_part(dumb_ptr<map_session_data> sd, Part& part,
        std::vector<VesselReport> *reports)
{
    HueRecord& h = record_of(sd, part.hue);
    h.energy -= part.sources[0].energy;
    part.personal_spent = part.sources[0].energy;
    for (size_t k = 1; k < part.sources.size(); ++k)
    {
        Source& src = part.sources[k];
        if (!src.current && !src.energy)
            continue;
        Item& item = sd->status.inventory[src.index];
        VesselReport rep;
        rep.index = src.index;
        rep.nameid = item.nameid;
        rep.amount = item.amount;
        rep.spent = src.energy;
        rep.load_pct = src.current * 100 / src.safe;
        rep.fate = VesselFate::SAFE;
        part.vessel_spent += src.energy;
        // Every unit of the stack shares the draw.
        uint32_t per_unit = uint32_t((int64_t(src.energy) * 1000 + item.amount - 1)
                / item.amount);
        item.hue_charge -= std::min(item.hue_charge, per_unit);
        if (src.current > src.safe && !part.destroyed[k])
        {
            int wear = std::max(1, hue_balance.overload_wear * (rep.load_pct - 100) / 100);
            rep.fate = VesselFate::STRAINED;
            if (item.condition <= wear)
                part.destroyed[k] = true;
            else
                item.condition -= wear;
        }
        if (part.destroyed[k])
        {
            // The whole participating stack disintegrates; what it still
            // held is lost with it. Other stacks are untouched.
            rep.fate = VesselFate::DESTROYED;
            pc_delitem(sd, src.index, item.amount, 0);
        }
        else
            hue_send_lot(sd, src.index);
        reports->push_back(rep);
    }
}

HueReason leap_reason(LeapResult r)
{
    switch (r)
    {
    case LeapResult::NOT_AT_EDGE: return HueReason::NOT_AT_EDGE;
    case LeapResult::TOO_FAR: return HueReason::TOO_FAR;
    case LeapResult::NO_LANDING: return HueReason::NO_LANDING;
    case LeapResult::OBSTRUCTED: return HueReason::OBSTRUCTED;
    case LeapResult::WRONG_WAY: return HueReason::WRONG_WAY;
    case LeapResult::TOO_HIGH: return HueReason::TOO_HIGH;
    default: return HueReason::OK;
    }
}

bool spark_target_ok(dumb_ptr<map_session_data> sd, dumb_ptr<mob_data> md,
        int range)
{
    if (!md || md->hp <= 0 || is_vegetation(md) || md->bl_m != sd->bl_m)
        return false;
    int dist = std::max(std::abs(md->bl_x - sd->bl_x),
            std::abs(md->bl_y - sd->bl_y));
    return dist <= range && terrain_same_level(sd->bl_m, sd->bl_x, sd->bl_y,
            md->bl_x, md->bl_y);
}

/// The player's selected target, or else the nearest enemy in front.
dumb_ptr<mob_data> spark_target(dumb_ptr<map_session_data> sd,
        BlockId target, int dx, int dy, int range)
{
    if (target)
    {
        dumb_ptr<block_list> bl = map_id2bl(target);
        dumb_ptr<mob_data> md = bl ? bl->is_mob() : nullptr;
        return spark_target_ok(sd, md, range) ? md : nullptr;
    }
    dumb_ptr<mob_data> best;
    int best_dist = range + 1;
    map_foreachinarea([&](dumb_ptr<block_list> bl)
            {
                dumb_ptr<mob_data> md = bl->is_mob();
                if (!spark_target_ok(sd, md, range)
                        || !in_front(sd->bl_x, sd->bl_y, dx, dy,
                            md->bl_x, md->bl_y, range))
                    return;
                int dist = std::max(std::abs(md->bl_x - sd->bl_x),
                        std::abs(md->bl_y - sd->bl_y));
                if (dist < best_dist)
                {
                    best = md;
                    best_dist = dist;
                }
            },
            sd->bl_m, sd->bl_x - range, sd->bl_y - range,
            sd->bl_x + range, sd->bl_y + range, BL::MOB);
    return best;
}

// Burning enemies. A new burn on a burning enemy restarts it.
struct Burn
{
    BlockId mob, owner;
    int ticks, damage;
};
std::vector<Burn> burns;

/// Fire damage, and a chance to set the enemy burning. Returns whether
/// it now burns.
bool ignite(dumb_ptr<map_session_data> sd, dumb_ptr<mob_data> md, int damage,
        int burn_pct, tick_t tick)
{
    BlockId id = md->bl_id;
    clif_specialeffect(md, 903, 0);
    if (damage > 0)
    {
        clif_damage(sd, md, tick, interval_t::zero(), interval_t::zero(),
                damage, 0, DamageType::NORMAL);
        mob_damage(sd, md, damage, 0);
    }
    // mob_damage may have killed it.
    dumb_ptr<block_list> bl = map_id2bl(id);
    if (!bl || !bl->is_mob() || bl->is_mob()->hp <= 0)
        return false;
    if (!roll(sd, burn_pct))
        return false;
    for (Burn& b : burns)
    {
        if (b.mob == id)
        {
            b.ticks = hue_balance.burn_ticks;
            b.owner = sd->bl_id;
            return true;
        }
    }
    burns.push_back({id, sd->bl_id, hue_balance.burn_ticks,
            hue_balance.burn_tick_damage});
    return true;
}

void burn_timer(TimerData *, tick_t tick)
{
    std::vector<Burn> still;
    for (Burn b : burns)
    {
        dumb_ptr<block_list> bl = map_id2bl(b.mob);
        dumb_ptr<mob_data> md = bl ? bl->is_mob() : nullptr;
        if (!md || md->hp <= 0)
            continue;
        dumb_ptr<map_session_data> owner = map_id2sd(b.owner);
        clif_specialeffect(md, 904, 0);
        clif_damage(owner ? dumb_ptr<block_list>(owner) : dumb_ptr<block_list>(md),
                md, tick, interval_t::zero(), interval_t::zero(), b.damage, 0,
                DamageType::NORMAL);
        mob_damage(owner, md, b.damage, 0);
        if (--b.ticks > 0)
            still.push_back(b);
    }
    burns = std::move(still);
}
} // anonymous namespace

void hue_action(dumb_ptr<map_session_data> sd, int skill, DIR dir,
        uint8_t flags, uint32_t request, BlockId target, int modifier)
{
    nullpo_retv(sd);
    if (request && request <= sd->hue.last_request)
        return;     // a repeated request: already resolved once
    if (request)
        sd->hue.last_request = request;

    ResultInfo res;
    res.request = request;
    res.skill = skill;
    res.modifier = modifier;

    // 1. Validate. Nothing is spent on any rejection below.
    if (!hue_skill_max_rank(skill))
        return reject(sd, res, HueReason::UNKNOWN_SKILL, 0);
    const HueSkillRank *def = hue_skill_rank(skill, learned_rank(sd, skill));
    if (!def)
        return reject(sd, res, HueReason::NOT_LEARNED, 0);
    res.energy = def->energy;
    res.current = def->current;
    if (def->kind == HueActionKind::FLOW)
        return reject(sd, res, HueReason::PERMANENT, 0);
    if (pc_isdead(sd))
        return reject(sd, res, HueReason::DEAD, 0);

    std::vector<Part> parts(1);
    parts[0].skill = skill;
    parts[0].def = def;
    parts[0].hue = def->hue;
    parts[0].E = def->energy;
    parts[0].I = def->current;

    const HueCombo *combo = nullptr;
    if (modifier)
    {
        combo = hue_combo(skill, modifier);
        if (!combo)
            return reject(sd, res, HueReason::INCOMPATIBLE, modifier);
        const HueSkillRank *mod = hue_skill_rank(modifier,
                learned_rank(sd, modifier));
        if (!mod)
        {
            res.skill = modifier;
            return reject(sd, res, HueReason::NOT_LEARNED, 0);
        }
        Part part;
        part.skill = modifier;
        part.def = mod;
        part.hue = mod->hue;
        part.E = mod->energy * combo->energy_pct / 100;
        part.I = std::max(1, mod->current * combo->current_pct / 100);
        parts.push_back(part);
    }

    tick_t tick = gettick();
    prune_activations(sd, tick);
    for (size_t k = 0; k < parts.size(); ++k)
    {
        int detail = 0;
        HueReason why = plan_part(sd, parts[k], tick,
                int(sd->hue.active.size() + k), flags, &detail);
        if (why != HueReason::OK)
        {
            // Name the part that is short: the modifier's own hue may be.
            res.skill = parts[k].skill;
            res.energy = parts[k].E;
            res.current = parts[k].I;
            res.channel = parts[k].safe_channel
                ? parts[k].safe_channel
                : hue_mastery_row(record_of(sd, parts[k].hue).mastery).current;
            return reject(sd, res, why, detail);
        }
    }
    res.channel = parts[0].safe_channel;

    // Targets and landings, also before anything is spent.
    int dx = dirx[dir], dy = diry[dir];
    int to_x = sd->bl_x, to_y = sd->bl_y, steps = 0;
    dumb_ptr<mob_data> spark;
    switch (def->kind)
    {
    case HueActionKind::DASH:
        steps = ground_travel(sd->bl_m, to_x, to_y, dx, dy, def->p1);
        if (!steps)
        {
            pc_setdir(sd, dir);
            return reject(sd, res, HueReason::BLOCKED, 0);
        }
        break;
    case HueActionKind::FEATHERFALL:
    case HueActionKind::JUMP:
    {
        int way = def->kind == HueActionKind::JUMP ? 1 : -1;
        Leap leap = terrain_leap(sd->bl_m, sd->bl_x, sd->bl_y, dx, dy, way,
                def->p1, def->p2);
        pc_setdir(sd, dir);
        if (leap.result != LeapResult::OK)
        {
            int detail = leap.result == LeapResult::TOO_HIGH ? std::abs(leap.levels)
                : leap.result == LeapResult::TOO_FAR ? leap.span
                : leap.result == LeapResult::WRONG_WAY ? (leap.levels > 0 ? 1 : 2)
                : 0;
            return reject(sd, res, leap_reason(leap.result), detail);
        }
        if (occupied(sd->bl_m, leap.x, leap.y, sd))
            return reject(sd, res, HueReason::LANDING_OCCUPIED, 0);
        to_x = leap.x;
        to_y = leap.y;
        break;
    }
    case HueActionKind::SPARK:
        spark = spark_target(sd, target, dx, dy, def->p1);
        if (!spark)
            return reject(sd, res, HueReason::NO_TARGET, def->p1);
        break;
    default:
        break;
    }

    // 4. Roll each part. Any part failing makes the whole action fizzle.
    bool success = true;
    for (Part& part : parts)
        success = roll_part(sd, part) && success;

    // 5. Commit: effects, then spending, wear and destruction.
    if (def->kind == HueActionKind::SPARK)
    {
        int dxs = sign(spark->bl_x - sd->bl_x), dys = sign(spark->bl_y - sd->bl_y);
        if (dxs || dys)
            dir = (dxs > 0) ? (dys > 0 ? DIR::SE : dys < 0 ? DIR::NE : DIR::E)
                : (dxs < 0) ? (dys > 0 ? DIR::SW : dys < 0 ? DIR::NW : DIR::W)
                : (dys > 0 ? DIR::S : DIR::N);
    }
    pc_setdir(sd, dir);
    int units = 0, mod_units = 0;
    if (success)
    {
        switch (def->kind)
        {
        case HueActionKind::DASH:
        case HueActionKind::FEATHERFALL:
        case HueActionKind::JUMP:
            pc_stop_walking(sd, 0);
            place(sd, to_x, to_y);
            sd->to_x = to_x;
            sd->to_y = to_y;
            clif_aethyra_slide(sd, def->kind == HueActionKind::DASH ? 0
                    : def->kind == HueActionKind::FEATHERFALL ? 2 : 3);
            units = def->kind == HueActionKind::DASH ? std::max(0, steps - 2) : 1;
            break;
        case HueActionKind::GUST:
        {
            std::vector<GustHit> hits;
            int x0 = sd->bl_x, y0 = sd->bl_y, r = def->p1;
            map_foreachinarea(std::bind(gust_push, std::placeholders::_1, sd,
                        dx, dy, def, tick, &hits),
                    sd->bl_m, x0 - r, y0 - r, x0 + r, y0 + r, BL::MOB);
            units = hits.size();
            if (combo && combo->effect == HueComboEffect::IGNITE)
            {
                // The gust carries the spark: everyone it moved is hit.
                const HueSkillRank *mod = parts[1].def;
                for (const GustHit& hit : hits)
                {
                    dumb_ptr<block_list> bl = map_id2bl(hit.id);
                    if (bl && bl->is_mob() && bl->is_mob()->hp > 0)
                    {
                        ignite(sd, bl->is_mob(), mod->p2 * combo->effect_pct / 100,
                                mod->p3, tick);
                        mod_units++;
                    }
                }
            }
            break;
        }
        case HueActionKind::SCYTHE:
        {
            int x0 = sd->bl_x, y0 = sd->bl_y, r = def->p1;
            map_foreachinarea(std::bind(scythe_cut, std::placeholders::_1, sd,
                        dx, dy, r, &units),
                    sd->bl_m, x0 - r, y0 - r, x0 + r, y0 + r, BL::MOB);
            break;
        }
        case HueActionKind::SPARK:
            ignite(sd, spark, def->p2, def->p3, tick);
            units = 1;
            break;
        default:
            break;
        }
        clif_specialeffect(sd, effect_of(def->kind), 0);
    }

    std::vector<VesselReport> reports;
    for (Part& part : parts)
    {
        commit_part(sd, part, &reports);
        sd->hue.active.push_back({tick + std::chrono::milliseconds(part.def->exec_ms),
                static_cast<uint16_t>(part.skill), static_cast<uint8_t>(part.hue)});
        sd->hue.ready[part.skill] = tick
            + std::chrono::milliseconds(part.def->cooldown_ms);
    }

    if (success)
    {
        award(sd, def, units, tick);
        if (parts.size() > 1)
            award(sd, parts[1].def, mod_units, tick);
    }

    res.outcome = success ? HueOutcome::SUCCEEDED : HueOutcome::FAILED;
    res.reason = success ? HueReason::OK : HueReason::OVERLOAD_FAILED;
    res.detail = units;
    res.personal_spent = parts[0].personal_spent;
    res.vessel_spent = parts[0].vessel_spent;
    if (parts.size() > 1)
    {
        res.modifier_personal = parts[1].personal_spent;
        res.modifier_vessel = parts[1].vessel_spent;
        res.modifier_detail = mod_units;
    }
    send_result(sd, res, reports);
    send_state(sd);
    if (success && (units || mod_units))
        send_skills(sd);

    AString extra;
    if (parts.size() > 1)
        extra = STRPRINTF("; + %s: %d own, %d vessels"_fmt, parts[1].def->name,
                parts[1].personal_spent, parts[1].vessel_spent);
    debug(sd, STRPRINTF("[hue] %s r%d: demand %d energy at %d current; own %d, "
                "vessels %d%s"_fmt, def->name, def->rank, parts[0].E,
                parts[0].I, parts[0].personal_spent, parts[0].vessel_spent,
                extra));
}

bool hue_grant_access(dumb_ptr<map_session_data> sd, Hue hue)
{
    HueRecord& r = record_of(sd, hue);
    if (r.access)
        return false;
    r.access = 1;
    r.mastery = 1;
    r.mastery_cap = 10;
    r.mastery_xp = 0;
    r.energy = capacity_of(r);
    send_state(sd);
    return true;
}

bool hue_grant_skill(dumb_ptr<map_session_data> sd, int skill, int rank)
{
    if (!hue_skill_rank(skill, rank))
        return false;
    HueSkillRecord *sk = skill_record(sd, skill);
    if (!sk)
    {
        for (HueSkillRecord& empty : sd->status.hue.skills)
        {
            if (!empty.id)
            {
                sk = &empty;
                break;
            }
        }
        if (!sk)
            return false;
        sk->id = skill;
        sk->rank = 0;
        sk->proficiency = 0;
    }
    if (sk->rank >= rank)
        return false;
    sk->rank = rank;
    const HueSkillRank *def = hue_skill_rank(skill, rank);
    sk->proficiency = std::max<uint32_t>(sk->proficiency, def->req_prof);
    send_skills(sd);
    return true;
}

void hue_learn(dumb_ptr<map_session_data> sd, int skill)
{
    nullpo_retv(sd);
    ResultInfo res;
    res.skill = skill;
    if (!hue_skill_max_rank(skill))
        return reject(sd, res, HueReason::UNKNOWN_SKILL, 0);
    int rank = learned_rank(sd, skill);
    const HueSkillRank *next = hue_skill_rank(skill, rank + 1);
    if (!next)
        return reject(sd, res, HueReason::MAX_RANK, rank);
    HueRecord& h = record_of(sd, next->hue);
    HueSkillRecord *sk = skill_record(sd, skill);
    if (!h.access)
        return reject(sd, res, HueReason::NO_ACCESS, 0);
    if (sd->status.hue.skill_points < 1)
        return reject(sd, res, HueReason::NO_POINTS, 0);
    if (sd->status.base_level < next->req_level)
        return reject(sd, res, HueReason::NEEDS_LEVEL, next->req_level);
    if (h.mastery < next->req_mastery)
        return reject(sd, res, HueReason::NEEDS_MASTERY, next->req_mastery);
    if (int(sk ? sk->proficiency : 0) < next->req_prof)
        return reject(sd, res, HueReason::NEEDS_PROFICIENCY, next->req_prof);
    if (!sk)
    {
        for (HueSkillRecord& empty : sd->status.hue.skills)
        {
            if (!empty.id)
            {
                sk = &empty;
                break;
            }
        }
        if (!sk)
            return reject(sd, res, HueReason::MAX_RANK, rank);
        sk->id = skill;
        sk->rank = 0;
        sk->proficiency = 0;
    }
    sd->status.hue.skill_points--;
    sk->rank++;
    res.outcome = HueOutcome::LEARNED;
    res.detail = sk->rank;
    send_result(sd, res, {});
    send_state(sd);
    send_skills(sd);
}

void hue_select_supply(dumb_ptr<map_session_data> sd, IOff0 index, bool on)
{
    nullpo_retv(sd);
    ResultInfo res;
    if (!vessel_at(sd, index))
        return reject(sd, res, HueReason::NOT_A_VESSEL, 0);
    auto& supply = sd->status.hue.supply;
    if (on && !supply_order(sd, index))
    {
        int k = 0;
        while (k < MAX_HUE_SUPPLY && supply[k])
            k++;
        if (k == MAX_HUE_SUPPLY)
            return reject(sd, res, HueReason::SUPPLY_FULL, MAX_HUE_SUPPLY);
        supply[k] = index.index + 1;
    }
    else if (!on)
        remove_supply(sd, index);
    res.outcome = HueOutcome::SUPPLY;
    res.detail = supply_order(sd, index);
    send_result(sd, res, {});
    // Orders of the others may have shifted.
    for (int k = 0; k < MAX_HUE_SUPPLY; ++k)
        if (supply[k])
            hue_send_lot(sd, IOff0::from(supply[k] - 1));
    hue_send_lot(sd, index);
}

// --------------------------------------------------------------------------
// Developer fixtures

bool hue_apply_profile(dumb_ptr<map_session_data> sd, XString name)
{
    const HueGrant *g = hue_profile(name);
    if (!g)
        return false;
    apply_grant(sd, *g);
    sd->status.hue.version = HUE_STATE_VERSION;
    sd->status.hue.points_level = std::max<int>(g->level, 1);
    for (int k = 0; k < MAX_HUE_SUPPLY; ++k)
        sd->status.hue.supply[k] = 0;
    sd->hue.active.clear();
    sd->hue.ready = {};
    if (g->level && sd->status.base_level < g->level)
    {
        sd->status.base_level = g->level;
        pc_calcstatus(sd, 0);
        clif_updatestatus(sd, SP::BASELEVEL);
    }
    hue_send_all(sd);
    return true;
}

void hue_force_outcome(dumb_ptr<map_session_data> sd, int outcome)
{
    sd->hue.forced = outcome < 0 ? -1 : (outcome & 3);
}

void hue_seed(dumb_ptr<map_session_data> sd, uint32_t seed)
{
    sd->hue.rng = seed ? seed : 0x2545f491;
}

void hue_set_energy(dumb_ptr<map_session_data> sd, Hue hue, int energy)
{
    HueRecord& r = record_of(sd, hue);
    r.energy = clamp(energy, 0, capacity_of(r));
    send_state(sd);
}

void hue_set_mastery(dumb_ptr<map_session_data> sd, Hue hue, int mastery)
{
    HueRecord& r = record_of(sd, hue);
    if (!r.access)
    {
        r.access = 1;
        r.mastery_cap = std::max<int>(r.mastery_cap, 10);
    }
    r.mastery_cap = std::max(int(r.mastery_cap), clamp(mastery, 1, 50));
    r.mastery = clamp(mastery, 1, r.mastery_cap);
    r.mastery_xp = 0;
    r.energy = std::min(r.energy, capacity_of(r));
    send_state(sd);
}

void hue_set_points(dumb_ptr<map_session_data> sd, int points)
{
    sd->status.hue.skill_points = clamp(points, 0, 999);
    send_state(sd);
}

bool hue_set_proficiency(dumb_ptr<map_session_data> sd, int skill, int value)
{
    HueSkillRecord *sk = skill_record(sd, skill);
    const HueSkillRank *def = sk ? hue_skill_rank(skill, sk->rank) : nullptr;
    if (!def)
        return false;
    sk->proficiency = clamp(value, 0, def->prof_cap);
    send_skills(sd);
    return true;
}

void hue_charge_vessels(dumb_ptr<map_session_data> sd, int per_unit)
{
    for (IOff0 i : IOff0::iter())
    {
        const HueVesselDef *v = vessel_at(sd, i);
        if (!v)
            continue;
        Item& item = sd->status.inventory[i];
        int units = per_unit < 0 ? v->capacity : std::min(per_unit, v->capacity);
        item.hue_charge = units * 1000;
        hue_send_lot(sd, i);
    }
}

void hue_toggle_debug(dumb_ptr<map_session_data> sd)
{
    sd->hue.debug = !sd->hue.debug;
    clif_displaymessage(sd->sess, sd->hue.debug
            ? "Hue diagnostics on."_s : "Hue diagnostics off."_s);
}

void hue_describe(dumb_ptr<map_session_data> sd)
{
    const HueState& st = sd->status.hue;
    clif_displaymessage(sd->sess, STRPRINTF(
                "Hue state v%d, origin %d, %d skill points (granted to level %d), "
                "balance v%d, forced %d"_fmt,
                st.version, st.origin, st.skill_points, st.points_level,
                hue_balance.version, sd->hue.forced));
    for (int i = 0; i < HUE_COUNT; ++i)
    {
        const HueRecord& r = st.hues[i];
        if (!r.access)
            continue;
        const HueMasteryRow& row = hue_mastery_row(r.mastery);
        clif_displaymessage(sd->sess, STRPRINTF(
                    "%s: mastery %d/%d (%u/%u), energy %d/%d, channel %d, "
                    "allowance %d, flow +%d%%"_fmt,
                    hue_name(static_cast<Hue>(i)), r.mastery, r.mastery_cap,
                    r.mastery_xp, mastery_next(r.mastery), r.energy,
                    row.capacity, row.current, row.allowance,
                    flow_pct(sd, static_cast<Hue>(i))));
    }
    for (const HueSkillRecord& sk : st.skills)
        if (sk.id)
            clif_displaymessage(sd->sess, STRPRINTF(
                        "skill %d rank %d proficiency %u"_fmt,
                        sk.id, sk.rank, sk.proficiency));
    for (int k = 0; k < MAX_HUE_SUPPLY; ++k)
    {
        if (!st.supply[k])
            continue;
        const Item& item = sd->status.inventory[IOff0::from(st.supply[k] - 1)];
        clif_displaymessage(sd->sess, STRPRINTF(
                    "supply %d: slot %d item %d x%d, %u.%03u per unit, condition %d"_fmt,
                    k + 1, st.supply[k] - 1, item.nameid, item.amount,
                    item.hue_charge / 1000, item.hue_charge % 1000, item.condition));
    }
}
} // namespace map
} // namespace tmwa
