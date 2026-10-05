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
    send_vpacket<0x0219, 24, 11>(s, head, repeat);
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

void gust_push(dumb_ptr<block_list> bl, dumb_ptr<map_session_data> sd,
        int dx, int dy, const HueSkillRank *def, tick_t tick, int *pushed)
{
    dumb_ptr<mob_data> md = bl->is_mob();
    if (!md || md->hp <= 0 || is_vegetation(md))
        return;
    if (!in_front(sd->bl_x, sd->bl_y, dx, dy, md->bl_x, md->bl_y, def->p1))
        return;

    // Away from the caster; straight ahead if standing on the same tile.
    int px = sign(md->bl_x - sd->bl_x), py = sign(md->bl_y - sd->bl_y);
    if (!px && !py)
    {
        px = dx;
        py = dy;
    }
    int x = md->bl_x, y = md->bl_y;
    travel(md->bl_m, x, y, px, py, def->p2);

    interval_t stagger = std::chrono::milliseconds(def->p3);
    mob_stop_walking(md, 0);
    md->canmove_tick = tick + stagger;
    md->attackabletime = tick + stagger;
    if (x != md->bl_x || y != md->bl_y)
    {
        place(md, x, y);
        md->to_x = x;
        md->to_y = y;
        clif_aethyra_slide(md, 1);
        (*pushed)++;
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

void do_init_hue()
{
    interval_t every = std::chrono::milliseconds(hue_balance.regen_interval_ms);
    Timer(gettick() + every, regen_timer, every).detach();
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
} // anonymous namespace

void hue_action(dumb_ptr<map_session_data> sd, int skill, DIR dir,
        uint8_t flags, uint32_t request)
{
    nullpo_retv(sd);
    if (request && request <= sd->hue.last_request)
        return;     // a repeated request: already resolved once
    if (request)
        sd->hue.last_request = request;

    ResultInfo res;
    res.request = request;
    res.skill = skill;

    // 1. Validate. Nothing is spent on any rejection below.
    if (!hue_skill_max_rank(skill))
        return reject(sd, res, HueReason::UNKNOWN_SKILL, 0);
    int rank = learned_rank(sd, skill);
    const HueSkillRank *def = hue_skill_rank(skill, rank);
    if (!def)
        return reject(sd, res, HueReason::NOT_LEARNED, 0);
    res.energy = def->energy;
    res.current = def->current;
    if (def->kind == HueActionKind::FLOW)
        return reject(sd, res, HueReason::PERMANENT, 0);
    HueRecord& h = record_of(sd, def->hue);
    if (!h.access)
        return reject(sd, res, HueReason::NO_ACCESS, 0);
    if (pc_isdead(sd))
        return reject(sd, res, HueReason::DEAD, 0);

    tick_t tick = gettick();
    if (tick < sd->hue.ready[skill])
        return reject(sd, res, HueReason::COOLDOWN,
                (sd->hue.ready[skill] - tick).count());
    prune_activations(sd, tick);
    const HueMasteryRow& row = hue_mastery_row(h.mastery);
    res.channel = row.current;
    if (active_count(sd, def->hue) >= row.allowance)
    {
        int holder = 0;
        for (const auto& a : sd->hue.active)
            if (a.hue == static_cast<uint8_t>(def->hue))
                holder = a.skill;
        return reject(sd, res, HueReason::ALLOWANCE, holder);
    }
    if (int(sd->hue.active.size()) >= hue_balance.activation_ceiling)
        return reject(sd, res, HueReason::CEILING, sd->hue.active.back().skill);

    int dx = dirx[dir], dy = diry[dir];
    int dash_x = sd->bl_x, dash_y = sd->bl_y, dash_steps = 0;
    if (def->kind == HueActionKind::DASH)
    {
        dash_steps = travel(sd->bl_m, dash_x, dash_y, dx, dy, def->p1);
        if (!dash_steps)
        {
            pc_setdir(sd, dir);
            return reject(sd, res, HueReason::BLOCKED, 0);
        }
    }

    // 2. Plan the supply: own reserve first, then selected stacks in order.
    const int E = def->energy, I = def->current;
    std::vector<Source> sources;
    {
        Source own;
        own.available = h.energy;
        own.safe = row.current;
        own.current = std::min<int64_t>({I, row.current, own.available * I / E});
        sources.push_back(own);
    }
    int flow = flow_pct(sd, def->hue);
    int remaining = I - sources[0].current;
    for (int k = 0; k < MAX_HUE_SUPPLY; ++k)
    {
        int16_t slot = sd->status.hue.supply[k];
        if (!slot)
            continue;
        IOff0 i = IOff0::from(slot - 1);
        const HueVesselDef *v = vessel_at(sd, i);
        if (!v || v->hue != def->hue)
            continue;
        Source src;
        src.index = i;
        src.vessel = v;
        src.available = lot_energy(sd->status.inventory[i]);
        src.safe = v->safe_current * (100 + flow) / 100;
        src.current = std::min<int64_t>({remaining, src.safe, src.available * I / E});
        remaining -= src.current;
        sources.push_back(src);
    }

    // 3. Energy, then current.
    int64_t total = 0;
    for (const Source& src : sources)
        total += src.available;
    if (total < E)
        return reject(sd, res, HueReason::NO_ENERGY, int(std::min<int64_t>(total, 0xffff)));

    int safe_channel = 0;
    for (const Source& src : sources)
        safe_channel += src.safe;
    res.channel = safe_channel;

    bool risky = false;
    int worst = 0;
    if (remaining > 0)
    {
        // Only by pushing vessel stacks past their safe current.
        for (size_t k = 1; k < sources.size() && remaining > 0; ++k)
        {
            Source& src = sources[k];
            int room = int(std::min<int64_t>(src.available * I / E, 0xffff)) - src.current;
            int extra = std::max(0, std::min(remaining, room));
            src.current += extra;
            remaining -= extra;
        }
        if (remaining > 0)
            return reject(sd, res, HueReason::CURRENT_LIMITED, safe_channel);
        for (size_t k = 1; k < sources.size(); ++k)
            if (sources[k].current > sources[k].safe)
                worst = std::max(worst, sources[k].current * 100 / sources[k].safe);
        if (worst > hue_balance.overload_max_ratio_pct)
            return reject(sd, res, HueReason::OVERLOAD_LIMIT, worst);
        if (!(flags & HUE_ACCEPT_RISK))
            return reject(sd, res, HueReason::OVERLOAD_RISK, worst);
        risky = true;
    }

    // Energy drawn follows each source's share of the current; rounding
    // leftovers go to whichever sources still hold energy.
    int drawn = 0;
    for (Source& src : sources)
    {
        src.energy = src.current * E / I;
        drawn += src.energy;
    }
    for (Source& src : sources)
    {
        int extra = int(std::min<int64_t>(E - drawn, src.available - src.energy));
        if (extra > 0)
        {
            src.energy += extra;
            drawn += extra;
        }
    }

    // 4. Roll. Success and stack survival are separate outcomes.
    bool success = true;
    std::vector<bool> destroyed(sources.size(), false);
    if (risky)
    {
        int m = h.mastery;
        int p_success = clamp(hue_balance.success_base_pct
                - hue_balance.success_slope_pct * (worst - 100) / 100
                + hue_balance.success_mastery_pct * m, 2, 100);
        success = sd->hue.forced >= 0 ? bool(sd->hue.forced & 1)
            : roll(sd, p_success);
        for (size_t k = 1; k < sources.size(); ++k)
        {
            const Source& src = sources[k];
            if (src.current <= src.safe)
                continue;
            int load = src.current * 100 / src.safe;
            int p_destroy = clamp(hue_balance.destroy_base_pct
                    + hue_balance.destroy_slope_pct * (load - 100) / 100
                    - hue_balance.destroy_mastery_pct * m, 0, 98);
            destroyed[k] = sd->hue.forced >= 0 ? bool(sd->hue.forced & 2)
                : roll(sd, p_destroy);
            debug(sd, STRPRINTF("[hue] stack %d load %d%%: destroy chance %d%% -> %s"_fmt,
                        src.index.index, load, p_destroy,
                        destroyed[k] ? "destroyed"_s : "survives"_s));
        }
        debug(sd, STRPRINTF("[hue] worst load %d%%: success chance %d%% -> %s%s"_fmt,
                    worst, p_success, success ? "success"_s : "failure"_s,
                    sd->hue.forced >= 0 ? " (forced)"_s : ""_s));
    }

    // 5. Commit.
    pc_setdir(sd, dir);
    int units = 0;
    if (success)
    {
        switch (def->kind)
        {
        case HueActionKind::DASH:
            pc_stop_walking(sd, 0);
            place(sd, dash_x, dash_y);
            sd->to_x = dash_x;
            sd->to_y = dash_y;
            clif_aethyra_slide(sd, 0);
            units = std::max(0, dash_steps - 2);
            break;
        case HueActionKind::GUST:
        {
            int x0 = sd->bl_x, y0 = sd->bl_y, r = def->p1;
            map_foreachinarea(std::bind(gust_push, std::placeholders::_1, sd,
                        dx, dy, def, tick, &units),
                    sd->bl_m, x0 - r, y0 - r, x0 + r, y0 + r, BL::MOB);
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
        default:
            break;
        }
        clif_specialeffect(sd, effect_of(def->kind), 0);
    }

    h.energy -= sources[0].energy;
    res.personal_spent = sources[0].energy;
    std::vector<VesselReport> reports;
    for (size_t k = 1; k < sources.size(); ++k)
    {
        Source& src = sources[k];
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
        res.vessel_spent += src.energy;
        // Every unit of the stack shares the draw.
        uint32_t per_unit = uint32_t((int64_t(src.energy) * 1000 + item.amount - 1)
                / item.amount);
        item.hue_charge -= std::min(item.hue_charge, per_unit);
        if (src.current > src.safe && !destroyed[k])
        {
            int wear = std::max(1, hue_balance.overload_wear * (rep.load_pct - 100) / 100);
            rep.fate = VesselFate::STRAINED;
            if (item.condition <= wear)
                destroyed[k] = true;
            else
                item.condition -= wear;
        }
        if (destroyed[k])
        {
            // The whole participating stack disintegrates; what it still
            // held is lost with it. Other stacks are untouched.
            rep.fate = VesselFate::DESTROYED;
            pc_delitem(sd, src.index, item.amount, 0);
        }
        else
            hue_send_lot(sd, src.index);
        reports.push_back(rep);
    }

    sd->hue.active.push_back({tick + std::chrono::milliseconds(def->exec_ms),
            static_cast<uint16_t>(skill), static_cast<uint8_t>(def->hue)});
    sd->hue.ready[skill] = tick + std::chrono::milliseconds(def->cooldown_ms);

    if (success)
        award(sd, def, units, tick);

    res.outcome = success ? HueOutcome::SUCCEEDED : HueOutcome::FAILED;
    res.reason = success ? HueReason::OK : HueReason::OVERLOAD_FAILED;
    res.detail = units;
    send_result(sd, res, reports);
    send_state(sd);
    if (success && units)
        send_skills(sd);

    debug(sd, STRPRINTF("[hue] %s r%d: demand %d energy at %d current; own %d "
                "(channel %d), vessels %d; flow +%d%%"_fmt,
                def->name, def->rank, E, I, sources[0].energy, row.current,
                res.vessel_spent, flow));
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
