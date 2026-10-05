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

#ifndef HUEWINDOW_H
#define HUEWINDOW_H

#include <guichan/listmodel.hpp>
#include <guichan/selectionlistener.hpp>

#include "../../bindings/guichan/widgets/window.h"

class Button;
class Label;
class ListBox;
class RichTextBox;
class ScrollArea;

/**
 * Character and Hues: origin, level and skill points, each hue's access,
 * mastery, capacity, regeneration, channel, flow and allowance, and the
 * selected vessel supply. Values come from the server; nothing is
 * calculated here beyond formatting.
 */
class HueWindow : public Window
{
    public:
        HueWindow();

        void logic();
        void fontChanged();

    private:
        void refresh();

        RichTextBox *mText;
        ScrollArea *mScroll;
        unsigned int mRevision;
};

/** Lists every hue skill the server defines. */
class HueSkillListModel : public gcn::ListModel
{
    public:
        int getNumberOfElements();
        std::string getElementAt(int i);
        int skillAt(int i);
};

/**
 * Hue skills: learned and locked skills, their rank, proficiency and
 * cap, what each rank demands and does, and what the next rank needs.
 * Learning or upgrading is a request the server may refuse with a reason.
 */
class HueSkillWindow : public Window, public gcn::SelectionListener
{
    public:
        HueSkillWindow();
        ~HueSkillWindow();

        void action(const gcn::ActionEvent &event);
        void valueChanged(const gcn::SelectionEvent &event);
        void logic();
        void fontChanged();

    private:
        void refresh();

        HueSkillListModel *mModel;
        ListBox *mList;
        ScrollArea *mListScroll;
        RichTextBox *mText;
        ScrollArea *mTextScroll;
        Label *mPointsLabel;
        Button *mLearnButton;
        Button *mUseButton;
        unsigned int mRevision;
};

extern HueWindow *hueWindow;
extern HueSkillWindow *hueSkillWindow;

#endif
