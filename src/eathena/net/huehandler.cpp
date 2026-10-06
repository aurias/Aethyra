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

#include "huehandler.h"
#include "messagein.h"
#include "protocol.h"

#include "../huestate.h"

#include "../gui/chat.h"

#include "../../core/log.h"

#include "../../core/map/sprite/localplayer.h"

HueHandler::HueHandler()
{
    static const Uint16 _messages[] = {
        SMSG_AETHYRA_HUE_RESULT,
        SMSG_AETHYRA_HUE_STATE,
        SMSG_AETHYRA_HUE_SKILLS,
        SMSG_AETHYRA_ITEM_LOT,
        SMSG_AETHYRA_HUE_DEFINITIONS,
        0
    };
    handledMessages = _messages;
}

void HueHandler::handleMessage(MessageIn *msg)
{
    Hue::State &st = Hue::state();

    switch (msg->getId())
    {
        case SMSG_AETHYRA_HUE_DEFINITIONS:
        {
            msg->readInt16();  // length
            const int count = (msg->getLength() - 4) / 136;
            st.skills.clear();
            st.vessels.clear();
            st.combos.clear();
            for (int i = 0; i < count; i++)
            {
                const int kind = msg->readInt8();
                const int rank = msg->readInt8();
                const int id = msg->readInt16();
                const int hue = msg->readInt8();
                const int action = msg->readInt8();
                const int maxRank = msg->readInt8();
                msg->readInt8();  // unused
                const std::string name = msg->readString(24);
                int p[12];
                for (int k = 0; k < 12; k++)
                    p[k] = msg->readInt16() & 0xffff;
                const std::string description = msg->readString(80);
                if (kind == 0)
                {
                    Hue::SkillRank r;
                    r.id = id; r.rank = rank; r.hue = hue; r.action = action;
                    r.maxRank = maxRank; r.name = name;
                    r.description = description;
                    r.energy = p[0]; r.current = p[1];
                    r.execMs = p[2]; r.cooldownMs = p[3];
                    r.reqLevel = p[4]; r.reqMastery = p[5];
                    r.reqProficiency = p[6]; r.proficiencyCap = p[7];
                    r.p1 = p[8]; r.p2 = p[9]; r.p3 = p[10];
                    std::vector<Hue::SkillRank> &ranks = st.skills[id];
                    if ((int) ranks.size() < rank)
                        ranks.resize(rank);
                    ranks[rank - 1] = r;
                }
                else if (kind == 2)
                {
                    Hue::Combo c;
                    c.base = id; c.modifier = p[0]; c.effectPct = p[1];
                    c.energyPct = p[2]; c.currentPct = p[3];
                    c.description = description;
                    st.combos.push_back(c);
                }
                else if (kind == 1)
                {
                    Hue::Vessel v;
                    v.item = id; v.hue = hue; v.label = description;
                    v.capacity = p[0]; v.safeCurrent = p[1];
                    v.maxCondition = p[2]; v.grade = p[3];
                    v.initialCharge = p[4];
                    st.vessels[id] = v;
                }
            }
            break;
        }

        case SMSG_AETHYRA_HUE_STATE:
        {
            msg->readInt16();  // length
            st.origin = msg->readInt8();
            st.version = msg->readInt8();
            st.skillPoints = (Sint16) msg->readInt16();
            st.ceiling = msg->readInt8();
            st.active = msg->readInt8();
            st.balance = msg->readInt16();
            for (int i = 0; i < Hue::COUNT; i++)
                st.records[i] = Hue::Record();
            const int count = (msg->getLength() - 12) / 30;
            for (int i = 0; i < count; i++)
            {
                const int hue = msg->readInt8();
                Hue::Record r;
                r.access = msg->readInt8() != 0;
                r.mastery = msg->readInt8();
                r.masteryCap = msg->readInt8();
                r.masteryXp = msg->readInt32();
                r.masteryNext = msg->readInt32();
                r.energy = msg->readInt32();
                r.capacity = msg->readInt32();
                r.regen = msg->readInt16();
                r.regenPct = msg->readInt16();
                r.current = msg->readInt16();
                r.flowPct = msg->readInt16();
                r.allowance = msg->readInt8();
                r.allowanceUsed = msg->readInt8();
                if (hue >= 0 && hue < Hue::COUNT)
                    st.records[hue] = r;
            }
            break;
        }

        case SMSG_AETHYRA_HUE_SKILLS:
        {
            msg->readInt16();  // length
            st.learned.clear();
            const int count = (msg->getLength() - 4) / 7;
            for (int i = 0; i < count; i++)
            {
                const int id = msg->readInt16();
                Hue::Learned l;
                l.rank = msg->readInt8();
                l.proficiency = msg->readInt32();
                st.learned[id] = l;
            }
            break;
        }

        case SMSG_AETHYRA_ITEM_LOT:
        {
            const int index = msg->readInt16() - INVENTORY_OFFSET;
            Hue::Lot lot;
            lot.item = msg->readInt16();
            lot.charge = msg->readInt32();
            lot.condition = msg->readInt16();
            lot.supply = msg->readInt8();
            st.lots[index] = lot;
            break;
        }

        case SMSG_AETHYRA_HUE_RESULT:
        {
            msg->readInt16();  // length
            Hue::Result r;
            r.request = msg->readInt32();
            r.skill = msg->readInt16();
            r.outcome = msg->readInt8();
            r.reason = msg->readInt8();
            r.energy = msg->readInt16();
            r.current = msg->readInt16();
            r.channel = msg->readInt16();
            r.personalSpent = msg->readInt16();
            r.vesselSpent = msg->readInt16();
            r.detail = msg->readInt16();
            r.modifier = msg->readInt16();
            r.modifierPersonal = msg->readInt16();
            r.modifierVessel = msg->readInt16();
            r.modifierDetail = msg->readInt16();
            const int count = (msg->getLength() - 32) / 11;
            for (int i = 0; i < count; i++)
            {
                Hue::VesselOutcome v;
                v.index = msg->readInt16() - INVENTORY_OFFSET;
                v.item = msg->readInt16();
                v.amount = msg->readInt16();
                v.spent = msg->readInt16();
                v.fate = msg->readInt8();
                v.loadPct = msg->readInt16();
                r.vessels.push_back(v);
            }
            const std::string text = Hue::describe(r);
            logger->log("Hue result: skill %d outcome %d reason %d detail %d",
                        r.skill, r.outcome, r.reason, r.detail);
            if (!text.empty())
            {
                if (chatWindow)
                    chatWindow->chatLog(text, BY_SERVER);
                // Refusals and losses also show above the character.
                if (player_node && (r.outcome == Hue::REJECTED ||
                                    r.outcome == Hue::FAILED ||
                                    !r.vessels.empty()))
                    player_node->setSpeech(text, 4000);
            }
            break;
        }
    }
    Hue::touch();
}
