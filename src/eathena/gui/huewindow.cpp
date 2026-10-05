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

#include "huewindow.h"

#include "../huestate.h"

#include "../structs/inventory.h"
#include "../structs/item.h"

#include "../../bindings/guichan/layout.h"

#include "../../bindings/guichan/widgets/button.h"
#include "../../bindings/guichan/widgets/label.h"
#include "../../bindings/guichan/widgets/listbox.h"
#include "../../bindings/guichan/widgets/richtextbox.h"
#include "../../bindings/guichan/widgets/scrollarea.h"

#include "../../core/map/sprite/localplayer.h"

#include "../../core/utils/gettext.h"
#include "../../core/utils/stringutils.h"

HueWindow *hueWindow = NULL;
HueSkillWindow *hueSkillWindow = NULL;

namespace
{
    const char *originName(int origin)
    {
        // Origins are homelands; only the Gale Meadow exists so far.
        switch (origin)
        {
            case 1: return _("Gale Meadow");
            default: return _("unknown");
        }
    }

    std::string effectText(const Hue::SkillRank &r)
    {
        switch (r.action)
        {
            case Hue::ACTION_DASH:
                return strprintf(_("moves you up to %d tiles"), r.p1);
            case Hue::ACTION_GUST:
                return strprintf(_("pushes enemies within %d tiles up to %d "
                                   "tiles; they stagger %.1f s; no damage"),
                                 r.p1, r.p2, r.p3 / 1000.0);
            case Hue::ACTION_SCYTHE:
                return strprintf(_("harvests vegetation within %d tiles"),
                                 r.p1);
            case Hue::ACTION_FLOW:
                return strprintf(_("+%d%% safe current from selected "
                                   "vessels"), r.p1);
            default:
                return "";
        }
    }
}

// ---------------------------------------------------------------------------
// Character and Hues

HueWindow::HueWindow():
    Window(_("Character and Hues")),
    mRevision(0)
{
    setWindowName("Hues");
    setResizable(true);
    setCloseButton(true);
    setDefaultSize(420, 320, ImageRect::CENTER);

    mText = new RichTextBox(RichTextBox::AUTO_WRAP);
    mText->setOpaque(false);
    mScroll = new ScrollArea(mText);
    mScroll->setHorizontalScrollPolicy(gcn::ScrollArea::SHOW_NEVER);

    fontChanged();
    loadWindowState();
}

void HueWindow::fontChanged()
{
    Window::fontChanged();

    if (mWidgets.size() > 0)
        clear();

    place(0, 0, mScroll, 5, 5).setPadding(3);
    Layout &layout = getLayout();
    layout.setRowHeight(0, Layout::AUTO_SET);
    refreshLayout();
    mRevision = 0;
}

void HueWindow::logic()
{
    if (!isVisible())
        return;
    Window::logic();
    if (mRevision != Hue::state().revision)
        refresh();
}

void HueWindow::refresh()
{
    const Hue::State &st = Hue::state();
    mRevision = st.revision;
    mText->clearRows();

    mText->addRow(strprintf(_("%s, from the %s. Character level %d, "
                              "%d skill point(s) to spend."),
                            player_node ? player_node->getName().c_str() : "",
                            originName(st.origin),
                            player_node ? player_node->mLevel : 0,
                            st.skillPoints));
    mText->addRow(strprintf(_("Activations in progress: %d of at most %d at "
                              "once."), st.active, st.ceiling));

    std::string locked;
    for (int h = 0; h < Hue::COUNT; h++)
    {
        const Hue::Record &r = st.records[h];
        if (!r.access)
        {
            locked += std::string(locked.empty() ? "" : ", ") + Hue::name(h);
            continue;
        }
        mText->addRow("");
        mText->addRow(strprintf(_("%s - mastery %d (cap %d), progress "
                                  "%u/%u"), Hue::name(h), r.mastery,
                                r.masteryCap, r.masteryXp, r.masteryNext));
        mText->addRow(strprintf(_("  Energy %d/%d, regenerating %d per "
                                  "second here (%d%% of normal)."),
                                r.energy, r.capacity,
                                r.regen * r.regenPct / 100, r.regenPct));
        mText->addRow(strprintf(_("  You channel up to %d current yourself; "
                                  "vessel flow +%d%%."), r.current,
                                r.flowPct));
        mText->addRow(strprintf(_("  Allowance: %d of %d %s activation(s) "
                                  "in use."), r.allowanceUsed, r.allowance,
                                Hue::name(h)));
    }
    if (!locked.empty())
    {
        mText->addRow("");
        mText->addRow(strprintf(_("Not yet learned: %s. Each is learned at "
                                  "an altar of that hue."), locked.c_str()));
    }

    // Selected supply, in drawing order.
    mText->addRow("");
    bool any = false;
    for (int order = 1; order <= 3; order++)
    {
        for (std::map<int, Hue::Lot>::const_iterator it = st.lots.begin();
             it != st.lots.end(); ++it)
        {
            const Hue::Lot *lot = Hue::lotAt(it->first);
            const Hue::Vessel *v = lot ? Hue::vessel(lot->item) : NULL;
            Item *item = player_node
                ? player_node->getInventory()->getItem(it->first) : NULL;
            if (!lot || !v || !item || lot->supply != order)
                continue;
            const int amount = item->getQuantity();
            const int safe = v->safeCurrent *
                (100 + st.records[v->hue].flowPct) / 100;
            mText->addRow(strprintf(_("Supply #%d: %d x %s, %d/%d energy, "
                                      "safe current %d, condition %d/%d."),
                                    order, amount, v->label.c_str(),
                                    Hue::lotEnergy(*lot, amount),
                                    v->capacity * amount, safe,
                                    lot->condition, v->maxCondition));
            any = true;
        }
    }
    if (!any)
        mText->addRow(_("No vessels selected: actions draw only on your own "
                        "energy. Select vessel stacks in the inventory."));
}

// ---------------------------------------------------------------------------
// Skill list

int HueSkillListModel::getNumberOfElements()
{
    return Hue::state().skills.size();
}

int HueSkillListModel::skillAt(int i)
{
    const std::map<int, std::vector<Hue::SkillRank> > &skills =
        Hue::state().skills;
    std::map<int, std::vector<Hue::SkillRank> >::const_iterator it =
        skills.begin();
    for (; it != skills.end() && i > 0; ++it, --i)
        ;
    return it == skills.end() ? 0 : it->first;
}

std::string HueSkillListModel::getElementAt(int i)
{
    const int id = skillAt(i);
    const Hue::SkillRank *r = Hue::rank(id, 1);
    if (!r)
        return "";
    const int rank = Hue::learnedRank(id);
    return rank ? strprintf(_("%s  (rank %d/%d)"), r->name.c_str(), rank,
                            r->maxRank)
                : strprintf(_("%s  (not learned)"), r->name.c_str());
}

// ---------------------------------------------------------------------------
// Skills window

HueSkillWindow::HueSkillWindow():
    Window(_("Hue Skills")),
    mRevision(0)
{
    setWindowName("HueSkills");
    setResizable(true);
    setCloseButton(true);
    setDefaultSize(480, 300, ImageRect::CENTER);

    mModel = new HueSkillListModel;
    mList = new ListBox(mModel, "", this);
    mList->addSelectionListener(this);
    mListScroll = new ScrollArea(mList);
    mListScroll->setHorizontalScrollPolicy(gcn::ScrollArea::SHOW_NEVER);

    mText = new RichTextBox(RichTextBox::AUTO_WRAP);
    mText->setOpaque(false);
    mTextScroll = new ScrollArea(mText);
    mTextScroll->setHorizontalScrollPolicy(gcn::ScrollArea::SHOW_NEVER);

    mPointsLabel = new Label("");
    mLearnButton = new Button(_("Learn"), "learn", this);
    mUseButton = new Button(_("Use"), "use", this);

    fontChanged();
    loadWindowState();
}

HueSkillWindow::~HueSkillWindow()
{
    delete mModel;
}

void HueSkillWindow::fontChanged()
{
    Window::fontChanged();

    if (mWidgets.size() > 0)
        clear();

    place(0, 0, mListScroll, 2, 5).setPadding(3);
    place(2, 0, mTextScroll, 4, 5).setPadding(3);
    place(0, 5, mPointsLabel, 3);
    place(3, 5, mUseButton, 1);
    place(4, 5, mLearnButton, 2);
    Layout &layout = getLayout();
    layout.setRowHeight(0, Layout::AUTO_SET);
    refreshLayout();
    mRevision = 0;
}

void HueSkillWindow::logic()
{
    if (!isVisible())
        return;
    Window::logic();
    if (mRevision != Hue::state().revision)
        refresh();
}

void HueSkillWindow::valueChanged(const gcn::SelectionEvent &event)
{
    refresh();
}

void HueSkillWindow::action(const gcn::ActionEvent &event)
{
    Window::action(event);
    const int id = mModel->skillAt(mList->getSelected());
    if (!id)
        return;
    if (event.getId() == "learn")
        Hue::learn(id);
    else if (event.getId() == "use")
        Hue::useSkill(id, false);
}

void HueSkillWindow::refresh()
{
    const Hue::State &st = Hue::state();
    mRevision = st.revision;

    mPointsLabel->setCaption(strprintf(_("Skill points: %d"),
                                       st.skillPoints));
    mPointsLabel->adjustSize();

    if (mList->getSelected() < 0 && mModel->getNumberOfElements() > 0)
        mList->setSelected(0);

    mText->clearRows();
    const int id = mModel->skillAt(mList->getSelected());
    const Hue::SkillRank *first = Hue::rank(id, 1);
    if (!first)
    {
        mLearnButton->setEnabled(false);
        mUseButton->setEnabled(false);
        return;
    }

    const int rank = Hue::learnedRank(id);
    std::map<int, Hue::Learned>::const_iterator l = st.learned.find(id);
    const unsigned int proficiency = l == st.learned.end()
        ? 0 : l->second.proficiency;
    const Hue::SkillRank *cur = Hue::rank(id, rank);
    const Hue::SkillRank *next = Hue::rank(id, rank + 1);
    const Hue::Record &rec = st.records[first->hue];

    mText->addRow(strprintf(_("%s - %s"), first->name.c_str(),
                            Hue::name(first->hue)));
    if (cur)
    {
        mText->addRow(strprintf(_("Rank %d of %d. %s"), rank, first->maxRank,
                                cur->description.c_str()));
        if (cur->action == Hue::ACTION_FLOW)
            mText->addRow(strprintf(_("Permanent: %s."),
                                    effectText(*cur).c_str()));
        else
        {
            mText->addRow(strprintf(_("Proficiency %u of %d at this rank."),
                                    proficiency, cur->proficiencyCap));
            mText->addRow(strprintf(_("Each use: %d energy at %d current "
                                      "(you channel %d alone); recovers in "
                                      "%.1f s."), cur->energy, cur->current,
                                    rec.current, cur->cooldownMs / 1000.0));
            mText->addRow(strprintf(_("Effect: %s."),
                                    effectText(*cur).c_str()));
            if (cur->current > rec.current)
                mText->addRow(_("You cannot channel that much alone: select "
                                "vessels to supply the rest."));
        }
    }
    else
        mText->addRow(strprintf(_("Not learned. %s"),
                                first->description.c_str()));

    if (next)
    {
        mText->addRow("");
        mText->addRow(strprintf(_("Rank %d: %s"), next->rank,
                                next->description.c_str()));
        if (next->action != Hue::ACTION_FLOW)
            mText->addRow(strprintf(_("Demands %d energy at %d current; %s."),
                                    next->energy, next->current,
                                    effectText(*next).c_str()));
        const int level = player_node ? player_node->mLevel : 0;
        mText->addRow(strprintf(_("Needs: 1 skill point (%s), level %d (%s), "
                                  "%s mastery %d (%s), proficiency %d (%s)."),
                                st.skillPoints >= 1 ? _("have") : _("missing"),
                                next->reqLevel,
                                level >= next->reqLevel ? _("have") : _("missing"),
                                Hue::name(next->hue), next->reqMastery,
                                rec.mastery >= next->reqMastery ? _("have")
                                                                : _("missing"),
                                next->reqProficiency,
                                (int) proficiency >= next->reqProficiency
                                    ? _("have") : _("missing")));
    }
    else
        mText->addRow(_("Highest rank reached."));

    mLearnButton->setCaption(rank ? _("Upgrade") : _("Learn"));
    mLearnButton->setEnabled(next != NULL);
    mUseButton->setEnabled(cur && cur->action != Hue::ACTION_FLOW);
}
