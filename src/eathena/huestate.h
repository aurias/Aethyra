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

#ifndef HUESTATE_H
#define HUESTATE_H

#include <algorithm>
#include <map>
#include <string>
#include <vector>

/**
 * The client's copy of the character's hue state. Everything here comes
 * from the server (packets 0x0219-0x021f); the client never decides costs,
 * outcomes or progression, it only explains them.
 */
namespace Hue
{
    enum { GALE, TIDE, EMBER, TERRA, VERDANT, AURA, DECAY, VOID_, COUNT };

    /** Skill actions, as in the server's HueActionKind. */
    enum { ACTION_DASH = 1, ACTION_GUST = 2, ACTION_SCYTHE = 3,
           ACTION_FEATHERFALL = 4, ACTION_JUMP = 5, ACTION_SPARK = 6,
           ACTION_FLOW = 10 };

    /** Server reason codes (server/src/map/hue.hpp, HueReason). */
    enum Reason
    {
        OK = 0, UNKNOWN_SKILL, NOT_LEARNED, NO_ACCESS, DEAD, COOLDOWN,
        ALLOWANCE, CEILING, BLOCKED, NO_ENERGY, CURRENT_LIMITED,
        OVERLOAD_RISK, OVERLOAD_LIMIT, PERMANENT, NO_POINTS, NEEDS_LEVEL,
        NEEDS_MASTERY, NEEDS_PROFICIENCY, MAX_RANK, NOT_A_VESSEL,
        SUPPLY_FULL, OVERLOAD_FAILED, NOT_AT_EDGE, TOO_FAR, NO_LANDING,
        OBSTRUCTED, WRONG_WAY, TOO_HIGH, LANDING_OCCUPIED, NO_TARGET,
        INCOMPATIBLE
    };

    enum Outcome { REJECTED, SUCCEEDED, FAILED, LEARNED, SUPPLY };
    enum Fate { SAFE, STRAINED, DESTROYED };

    struct SkillRank
    {
        int id, rank, hue, action, maxRank;
        std::string name, description;
        int energy, current, execMs, cooldownMs;
        int reqLevel, reqMastery, reqProficiency, proficiencyCap;
        int p1, p2, p3;
    };

    struct Vessel
    {
        int item, hue, grade, capacity, safeCurrent, maxCondition,
            initialCharge;
        std::string label;
    };

    /** A legal live combination: base modified by modifier. */
    struct Combo
    {
        int base, modifier, effectPct, energyPct, currentPct;
        std::string description;
    };

    struct Record
    {
        bool access;
        int mastery, masteryCap;
        unsigned int masteryXp, masteryNext;
        int energy, capacity, regen, regenPct, current, flowPct;
        int allowance, allowanceUsed;
    };

    struct Learned
    {
        int rank;
        unsigned int proficiency;
    };

    /** A vessel stack in the inventory: every unit shares this state. */
    struct Lot
    {
        int item;
        unsigned int charge;    /**< per unit, thousandths of energy */
        int condition;
        int supply;             /**< 1-based supply order, 0 = unselected */
    };

    struct VesselOutcome
    {
        int index, item, amount, spent, fate, loadPct;
    };

    struct Result
    {
        unsigned int request;
        int skill, outcome, reason;
        int energy, current, channel, personalSpent, vesselSpent, detail;
        int modifier, modifierPersonal, modifierVessel, modifierDetail;
        std::vector<VesselOutcome> vessels;
    };

    struct State
    {
        int origin, version, skillPoints, ceiling, active, balance;
        Record records[COUNT];
        std::map<int, std::vector<SkillRank> > skills;
        std::map<int, Vessel> vessels;
        std::vector<Combo> combos;
        int primed;                     /**< modifier for the next action */
        std::map<int, Learned> learned;
        std::map<int, Lot> lots;        /**< by inventory index */
        unsigned int revision;          /**< changes whenever state does */
    };

    State &state();
    void clear();
    /** Mark the state changed (windows compare revisions to refresh). */
    void touch();

    const char *name(int hue);
    const SkillRank *rank(int id, int rank);
    int learnedRank(int id);
    const Vessel *vessel(int item);
    const Combo *combo(int base, int modifier);
    /** The lot of the item at an inventory index, if it is a vessel. */
    const Lot *lotAt(int index);

    /** Energy a lot holds in total (whole units). */
    int lotEnergy(const Lot &lot, int amount);

    /** Player-facing explanation of a result (empty: nothing to say). */
    std::string describe(const Result &result);

    // Requests. The server answers each with a result.
    /** Uses a skill on the selected target; a primed modifier is added
     *  when it combines with this skill. */
    void useSkill(int id, bool acceptRisk);
    /** Prime (or unprime) a modifier for the next compatible action. */
    void togglePrimed(int modifier);
    void learn(int id);
    void selectSupply(int index, bool on);

    /** Gale skill ids bound to the X/C/V keys. */
    enum { SKILL_DASH = 1, SKILL_GUST = 2, SKILL_WIND_SCYTHE = 3,
           SKILL_FEATHERFALL = 4, SKILL_JUMP = 5, SKILL_SPARK = 6 };
}

#endif
