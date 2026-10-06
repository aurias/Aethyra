#pragma once
//    hue.hpp - Aethyra hue rules: character hue state, vessels and actions
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

#include "hue_db.hpp"


namespace tmwa
{
namespace map
{
/// Version of CharData::hue written by this server. 0 means "not yet
/// initialised": a new character (origin set by the char server) or a save
/// from before hue state (origin 0), migrated at login.
constexpr uint8_t HUE_STATE_VERSION = 1;

/// Item::lot_flags bit: the vessel lot state has been initialised.
constexpr uint8_t LOT_INITIALISED = 1;

/// Monster classes in this range are vegetation: they cannot move or
/// attack, and only Wind Scythe harvests them.
constexpr int VEGETATION_FIRST = 1100;
constexpr int VEGETATION_LAST = 1199;

/// Why an action or request had the outcome it did. Shared with the client
/// (src/eathena/huestate.h), which turns them into messages.
enum class HueReason : uint8_t
{
    OK = 0,
    UNKNOWN_SKILL = 1,
    NOT_LEARNED = 2,
    NO_ACCESS = 3,
    DEAD = 4,
    COOLDOWN = 5,           // detail: milliseconds left
    ALLOWANCE = 6,          // detail: skill holding the hue's allowance
    CEILING = 7,            // detail: skill holding the last activation
    BLOCKED = 8,            // nowhere to go
    NO_ENERGY = 9,          // detail: energy available
    CURRENT_LIMITED = 10,   // detail: current available safely
    OVERLOAD_RISK = 11,     // detail: worst stack load percent; resend with
                            // the accept-risk flag to attempt it
    OVERLOAD_LIMIT = 12,    // detail: worst stack load percent (too high)
    PERMANENT = 13,         // a perk: always active, not used
    NO_POINTS = 14,
    NEEDS_LEVEL = 15,       // detail: level needed
    NEEDS_MASTERY = 16,     // detail: mastery needed
    NEEDS_PROFICIENCY = 17, // detail: proficiency needed
    MAX_RANK = 18,
    NOT_A_VESSEL = 19,
    SUPPLY_FULL = 20,
    OVERLOAD_FAILED = 21,   // the overloaded attempt fizzled
    NOT_AT_EDGE = 22,       // no cliff face in front
    TOO_FAR = 23,           // detail: cliff cells in the way
    NO_LANDING = 24,        // nothing to stand on beyond the cliff
    OBSTRUCTED = 25,        // a corner is in the way
    WRONG_WAY = 26,         // detail: 1 = the landing is above, 2 = below
    TOO_HIGH = 27,          // detail: levels it would take
    LANDING_OCCUPIED = 28,
    NO_TARGET = 29,         // detail: range
    INCOMPATIBLE = 30,      // detail: the modifier skill
};

enum class HueOutcome : uint8_t
{
    REJECTED = 0,           // nothing spent
    SUCCEEDED = 1,
    FAILED = 2,             // energy spent, no effect
    LEARNED = 3,
    SUPPLY = 4,             // supply selection changed
};

/// What happened to a vessel stack that took part in an action.
enum class VesselFate : uint8_t
{
    SAFE = 0,
    STRAINED = 1,           // overloaded, survived with wear
    DESTROYED = 2,
};

/// Request flag: the player accepts the risk of overloading vessels.
constexpr uint8_t HUE_ACCEPT_RISK = 1;

/// Called at login (pc_authok) once inventory and status are loaded:
/// migrates or initialises the hue state and sends the client its
/// definitions, state, skills and vessel lots.
void hue_login(dumb_ptr<map_session_data> sd);

/// Send definitions, state, skills and vessel lots (map loaded).
void hue_send_all(dumb_ptr<map_session_data> sd);

/// Character level rose: award skill points not yet granted for it.
void hue_level_points(dumb_ptr<map_session_data> sd);

/// Use a skill facing dir; flags are HUE_ACCEPT_RISK. request numbers
/// that were already handled are ignored. target is the being the player
/// has selected (0: none; targeted skills then pick the nearest in
/// front). modifier is a skill applied live to the base skill (0: none);
/// it must be a registered combination and pays its own way.
void hue_action(dumb_ptr<map_session_data> sd, int skill, DIR dir,
        uint8_t flags, uint32_t request, BlockId target, int modifier);

/// Learn a skill or raise it a rank.
void hue_learn(dumb_ptr<map_session_data> sd, int skill);

/// Add or remove an inventory vessel stack in the selected supply.
void hue_select_supply(dumb_ptr<map_session_data> sd, IOff0 index, bool on);

/// Give a newly added item its vessel lot state if it has none yet.
void hue_init_lot(Item *item);
/// Whether two items' lot states allow them to share a stack.
bool hue_same_lot(const Item& a, const Item& b);
/// Inventory slot index now holds a different (or no) item.
void hue_slot_changed(dumb_ptr<map_session_data> sd, IOff0 index);
/// Tell the client the lot state of a vessel stack (no-op for others).
void hue_send_lot(dumb_ptr<map_session_data> sd, IOff0 index);

/// Restore energy of a hue (item scripts); returns the amount added.
int hue_restore(dumb_ptr<map_session_data> sd, Hue hue, int amount);

/// Start the regeneration timer.
void do_init_hue();

// --- developer fixtures (GM commands only) -------------------------------

/// Grant hue access (mastery 1, homeland cap, full energy) or a skill
/// rank: developer fixtures, and teaching NPCs for skills.
bool hue_grant_access(dumb_ptr<map_session_data> sd, Hue hue);
bool hue_grant_skill(dumb_ptr<map_session_data> sd, int skill, int rank);

/// Apply a developer profile (resets the hue state). False if unknown.
bool hue_apply_profile(dumb_ptr<map_session_data> sd, XString name);
/// Force the next overload resolutions: -1 clears; otherwise bit 0 =
/// action succeeds, bit 1 = participating stacks are destroyed.
void hue_force_outcome(dumb_ptr<map_session_data> sd, int outcome);
/// Seed this character's overload rolls.
void hue_seed(dumb_ptr<map_session_data> sd, uint32_t seed);
/// Set a hue's energy (clamped to capacity) / mastery (clamped to cap).
void hue_set_energy(dumb_ptr<map_session_data> sd, Hue hue, int energy);
void hue_set_mastery(dumb_ptr<map_session_data> sd, Hue hue, int mastery);
void hue_set_points(dumb_ptr<map_session_data> sd, int points);
/// Set a learned skill's proficiency (capped by its rank). False if unknown.
bool hue_set_proficiency(dumb_ptr<map_session_data> sd, int skill, int value);
/// Refill (or set, per unit) the charge of every vessel stack carried.
void hue_charge_vessels(dumb_ptr<map_session_data> sd, int per_unit);
/// Toggle per-action diagnostics (demand, supply, rolls) in chat.
void hue_toggle_debug(dumb_ptr<map_session_data> sd);
/// One-line summary of the hue state for @hueinfo.
void hue_describe(dumb_ptr<map_session_data> sd);
} // namespace map
} // namespace tmwa
