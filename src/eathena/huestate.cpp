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

#include "huestate.h"

#include "net/messageout.h"
#include "net/protocol.h"

#include "structs/inventory.h"
#include "structs/item.h"

#include "../core/map/sprite/localplayer.h"

#include "../core/utils/gettext.h"
#include "../core/utils/stringutils.h"

namespace
{
    Hue::State theState;
    unsigned int nextRequest = 0;

    std::string skillName(int id)
    {
        const Hue::SkillRank *r = Hue::rank(id, 1);
        return r ? r->name : strprintf(_("Skill %d"), id);
    }

    std::string itemLabel(int item, int amount)
    {
        const Hue::Vessel *v = Hue::vessel(item);
        std::string label = v ? v->label : strprintf(_("item %d"), item);
        return amount == 1 ? label
                           : strprintf(_("%s stack (x%d)"), label.c_str(), amount);
    }
}

Hue::State &Hue::state()
{
    return theState;
}

void Hue::clear()
{
    unsigned int revision = theState.revision;
    theState = State();
    theState.revision = revision + 1;
    nextRequest = 0;
}

void Hue::touch()
{
    theState.revision++;
}

const char *Hue::name(int hue)
{
    static const char *names[] = {
        N_("Gale"), N_("Tide"), N_("Ember"), N_("Terra"),
        N_("Verdant"), N_("Aura"), N_("Decay"), N_("Void")
    };
    return (hue >= 0 && hue < COUNT) ? _(names[hue]) : "?";
}

const Hue::SkillRank *Hue::rank(int id, int r)
{
    std::map<int, std::vector<SkillRank> >::const_iterator it =
        theState.skills.find(id);
    if (it == theState.skills.end() || r < 1 || r > (int) it->second.size())
        return NULL;
    return &it->second[r - 1];
}

int Hue::learnedRank(int id)
{
    std::map<int, Learned>::const_iterator it = theState.learned.find(id);
    return it == theState.learned.end() ? 0 : it->second.rank;
}

const Hue::Vessel *Hue::vessel(int item)
{
    std::map<int, Vessel>::const_iterator it = theState.vessels.find(item);
    return it == theState.vessels.end() ? NULL : &it->second;
}

const Hue::Combo *Hue::combo(int base, int modifier)
{
    for (size_t i = 0; i < theState.combos.size(); i++)
        if (theState.combos[i].base == base &&
            theState.combos[i].modifier == modifier)
            return &theState.combos[i];
    return NULL;
}

const Hue::Lot *Hue::lotAt(int index)
{
    std::map<int, Lot>::const_iterator it = theState.lots.find(index);
    if (it == theState.lots.end() || !player_node)
        return NULL;
    // Only while the slot still holds that vessel.
    Item *item = player_node->getInventory()->getItem(index);
    if (!item || item->getId() != it->second.item || item->getQuantity() <= 0)
        return NULL;
    return &it->second;
}

int Hue::lotEnergy(const Lot &lot, int amount)
{
    return (int) ((long long) lot.charge * amount / 1000);
}

std::string Hue::describe(const Result &r)
{
    const std::string skill = skillName(r.skill);
    const SkillRank *def = rank(r.skill, std::max(learnedRank(r.skill), 1));
    const char *hue = name(def ? def->hue : GALE);

    switch (r.outcome)
    {
        case LEARNED:
            return strprintf(_("You learned %s rank %d."), skill.c_str(),
                             r.detail);
        case SUPPLY:
            return r.detail
                ? strprintf(_("Vessel stack selected as supply #%d."), r.detail)
                : std::string(_("Vessel stack removed from your supply."));
        case SUCCEEDED:
        case FAILED:
        {
            std::string text;
            if (r.modifier)
            {
                const SkillRank *mod = rank(r.modifier,
                                            std::max(learnedRank(r.modifier), 1));
                const std::string modName = skillName(r.modifier);
                text = strprintf(_("%s + %s %s: %d %s and %d %s energy."),
                                 skill.c_str(), modName.c_str(),
                                 r.outcome == FAILED ? _("fizzled")
                                                     : _("together"),
                                 r.personalSpent + r.vesselSpent, hue,
                                 r.modifierPersonal + r.modifierVessel,
                                 name(mod ? mod->hue : GALE));
                if (r.outcome == SUCCEEDED && r.modifierDetail)
                    text += " " + strprintf(_("%d set alight."),
                                            r.modifierDetail);
            }
            else if (r.outcome == FAILED)
                text = strprintf(_("%s fizzled under the overload; %d %s "
                                   "energy was spent."), skill.c_str(),
                                 r.personalSpent + r.vesselSpent, hue);
            else if (r.vesselSpent)
                text = strprintf(_("%s drew %d %s energy: %d your own, %d "
                                   "from vessels."), skill.c_str(),
                                 r.personalSpent + r.vesselSpent, hue,
                                 r.personalSpent, r.vesselSpent);
            for (size_t i = 0; i < r.vessels.size(); i++)
            {
                const VesselOutcome &v = r.vessels[i];
                const std::string what = itemLabel(v.item, v.amount);
                if (v.fate == DESTROYED)
                    text += " " + strprintf(_("Your %s disintegrated at %d%% "
                                              "load."), what.c_str(), v.loadPct);
                else if (v.fate == STRAINED)
                    text += " " + strprintf(_("Your %s strained at %d%% load "
                                              "and wore down."), what.c_str(),
                                            v.loadPct);
            }
            return text;
        }
        default:
            break;
    }

    switch (r.reason)
    {
        case UNKNOWN_SKILL:
            return _("That skill does not exist.");
        case NOT_LEARNED:
            return strprintf(_("You have not learned %s."), skill.c_str());
        case NO_ACCESS:
            return strprintf(_("You cannot manipulate %s yet."), hue);
        case DEAD:
            return _("You cannot do that now.");
        case COOLDOWN:
            return strprintf(_("%s is still recovering (%.1f s)."),
                             skill.c_str(), r.detail / 1000.0);
        case ALLOWANCE:
            return strprintf(_("%s cannot start: your %s allowance is held "
                               "by %s."), skill.c_str(), hue,
                             skillName(r.detail).c_str());
        case CEILING:
            return strprintf(_("%s cannot start: you are already "
                               "sustaining all you can."), skill.c_str());
        case BLOCKED:
            return strprintf(_("%s: there is no room to move that way."),
                             skill.c_str());
        case NO_ENERGY:
            return strprintf(_("%s needs %d %s energy; you can draw on %d."),
                             skill.c_str(), r.energy, hue, r.detail);
        case CURRENT_LIMITED:
            return strprintf(_("%s needs %d current; you can deliver %d "
                               "safely. Select a vessel stack in your "
                               "inventory or train your mastery."),
                             skill.c_str(), r.current, r.detail);
        case OVERLOAD_RISK:
            return strprintf(_("%s would push your vessels to %d%% load and "
                               "they may disintegrate. Hold Shift and use it "
                               "again to risk it."), skill.c_str(), r.detail);
        case OVERLOAD_LIMIT:
            return strprintf(_("%s would need %d%% load from your vessels: "
                               "far beyond what they can take."),
                             skill.c_str(), r.detail);
        case PERMANENT:
            return strprintf(_("%s is permanent; it is always in effect."),
                             skill.c_str());
        case NO_POINTS:
            return _("You have no skill points left. You gain one per "
                     "character level.");
        case NEEDS_LEVEL:
            return strprintf(_("That needs character level %d."), r.detail);
        case NEEDS_MASTERY:
            return strprintf(_("That needs %s mastery %d."), hue, r.detail);
        case NEEDS_PROFICIENCY:
            return strprintf(_("That needs %d proficiency with %s: use it "
                               "to good effect."), r.detail, skill.c_str());
        case MAX_RANK:
            return strprintf(_("%s is already at its highest rank."),
                             skill.c_str());
        case NOT_A_VESSEL:
            return _("That item cannot supply hue energy.");
        case SUPPLY_FULL:
            return strprintf(_("You can draw on at most %d vessel stacks."),
                             r.detail);
        case NOT_AT_EDGE:
            return strprintf(_("%s: face a cliff edge first."), skill.c_str());
        case TOO_FAR:
            return strprintf(_("%s: that cliff is %d cells across, too wide "
                               "for you yet."), skill.c_str(), r.detail);
        case NO_LANDING:
            return strprintf(_("%s: there is nowhere to land beyond that "
                               "cliff."), skill.c_str());
        case OBSTRUCTED:
            return strprintf(_("%s: something is in the way at the corner."),
                             skill.c_str());
        case WRONG_WAY:
            return r.detail == 1
                ? strprintf(_("%s: that ledge is above you - jump instead."),
                            skill.c_str())
                : strprintf(_("%s: that ledge is below you - featherfall "
                              "instead."), skill.c_str());
        case TOO_HIGH:
            return strprintf(_("%s: that is %d levels, more than you can "
                               "manage yet."), skill.c_str(), r.detail);
        case LANDING_OCCUPIED:
            return strprintf(_("%s: someone is standing where you would "
                               "land."), skill.c_str());
        case NO_TARGET:
            return strprintf(_("%s: no enemy in reach (%d tiles, on your "
                               "level)."), skill.c_str(), r.detail);
        case INCOMPATIBLE:
            return strprintf(_("%s cannot be combined with %s."),
                             skillName(r.detail).c_str(), skill.c_str());
        default:
            return strprintf(_("The server refused that (reason %d)."),
                             r.reason);
    }
}

void Hue::useSkill(int id, bool acceptRisk)
{
    if (!player_node)
        return;
    // A primed modifier rides along when it combines with this skill.
    int modifier = 0;
    if (theState.primed && combo(id, theState.primed))
    {
        modifier = theState.primed;
        theState.primed = 0;
        touch();
    }
    // Targeted skills aim at the selected monster, if any.
    int target = 0;
    Being *being = player_node->getTarget();
    if (being && being->getType() == Being::MONSTER)
        target = being->getId();

    MessageOut outMsg(CMSG_AETHYRA_HUE_ACTION);
    outMsg.writeInt16(id);
    outMsg.writeInt8(player_node->getDirection());
    outMsg.writeInt8(acceptRisk ? 1 : 0);
    outMsg.writeInt32(++nextRequest);
    outMsg.writeInt32(target);
    outMsg.writeInt16(modifier);
}

void Hue::togglePrimed(int modifier)
{
    theState.primed = theState.primed == modifier ? 0 : modifier;
    touch();
}

void Hue::learn(int id)
{
    MessageOut outMsg(CMSG_AETHYRA_LEARN_SKILL);
    outMsg.writeInt16(id);
}

void Hue::selectSupply(int index, bool on)
{
    MessageOut outMsg(CMSG_AETHYRA_SELECT_SUPPLY);
    outMsg.writeInt16(index + INVENTORY_OFFSET);
    outMsg.writeInt8(on ? 1 : 0);
}
