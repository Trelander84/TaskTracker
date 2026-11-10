-- UI/Help.lua
-- Shared help popups for major input screens
--
-- Inline icons are chrome glyphs. The token is expanded when the help opens so the
-- color matches the current theme (atlas escapes cannot be recolored).

TaskTracker = TaskTracker or {}

local ICON_HELP   = "help"
local ICON_GEAR   = "gear"
local ICON_EYE    = "eye"
local ICON_EDIT   = "edit"
local ICON_EXPAND = "expand"
local ICON_NOTE   = "note"
local ICON_CMD    = "arrow"
local function pathArrow(px)
    return string.format("{{ttarrow:%d}}", px or 12)
end
local ICON_MAIL   = "mail"

--- Placeholder expanded by expandChromeIcons when the help body is shown.
local function ia(name, w, h)
    w = w or 18
    h = h or 18
    return string.format("{{tticon:%s:%d:%d}}", name, w, h)
end

local function expandChromeIcons(body)
    if type(body) ~= "string" or not TaskTracker.ChromeIconMarkup then
        return body
    end
    body = (body:gsub("{{tticon:([%w%-]+):(%d+):(%d+)}}", function(name, w, h)
        return TaskTracker.ChromeIconMarkup(name, tonumber(w), tonumber(h))
    end))
    body = (body:gsub("{{ttarrow:(%d+)}}", function(px)
        if TaskTracker.RightChevronMarkup then
            return TaskTracker.RightChevronMarkup(tonumber(px))
        end
        return ">"
    end))
    if TaskTracker.WithPathArrows then
        body = TaskTracker.WithPathArrows(body, 12)
    end
    return body
end

local HELP = {
    tracker_main = {
        title = "Task Tracker",
        body = (
            ia(ICON_GEAR) .. " — Settings: color theme, spacing (Compact, Comfy, or Spacious), text size, where the Notes panel docks, popout opacity, Characters (alts, tooltip lines), and more. Custom keeps your own spacing. Its copy button can start from one of those three. Bar to checkbox is the space between the colored bar and the checkbox. Options Panel, above Title bar, sizes this window on its own. The sliders under Title bar stay on the task list. Popout, at the bottom of Style, follows Compact, Comfy, and Spacious. Change those sliders on Custom.\n\n"
            .. ia(ICON_EYE) .. " — Show or hide completed tasks. When the eye looks \"covered,\" completed rows are hidden.\n\n"
            .. ia(ICON_EDIT) .. " — Edit mode on or off (uses the same accent as the title when on). In Edit mode you can reorder and add rows; tap "
            .. ia(ICON_HELP, 16, 16) .. " (left of the gear) while Edit is on for those steps.\n\n"
            .. ia(ICON_NOTE, 16, 16) .. " — Notes for this task. Click opens the Notes window beside the tracker. Shift-click opens the popout. Alt-click opens Notes. Shortcuts can change that click, and the Ctrl, Alt, and Shift clicks. The icon shows when the row has note text, or when you set the list note icon to always show (in Settings). Edit mode uses that same rule.\n\n"
            .. ia(ICON_CMD, 16, 16) .. " — Quick commands: one command shows that icon on the row — click to run it (out of combat). Two or more commands open a flyout. Add and edit commands in the Notes window.\n\n"
            .. "Delves — The header shows Delve-O-Bot 7001's icon. Click it to call a ride to a random Bountiful Delve. That needs the toy, and it only works out of combat.\n\n"
            .. "Row clicks (when Edit mode is off)\n"
            .. "• Left / Right click on a row — Adjust the progress count (+1 / −1).\n"
            .. "  Option: Settings " .. pathArrow(12) .. " General " .. pathArrow(12) .. " Row click can require Shift to adjust (helps prevent accidental clicks).\n"
            .. "• Alt-left-click the #/# on the right — Open the task window.\n"
            .. "• Ctrl-left-click an achievement task — Open it in the achievement window. The tooltip says that under the character list, with a left-click icon next to Ctrl. Other rows say Nothing. Alt-left on the count says Edit task. Shortcut, in General, starts on. Turn it off to hide those lines.\n"
            .. "• Shortcuts — Settings " .. pathArrow(12) .. " Shortcuts. It sets clicks on the task name, the count, and Notes. Those sections start folded. Open one, then open Left, Right, or Middle. Each of those holds Normal, Ctrl, Alt, and Shift. Normal is a click with no extra key. A plain left click counts up. A plain right click counts down. Shift does not, until you set it. Custom runs a command you type. Manual / automatic, under Task management, switches a task that tracks itself between keeping the number you set and following the game. The count stays where it is until the game updates that task. Delete task, under Task management, asks before it removes the task. The switch to the right of a command shows that click in the task tooltip. On the task name, a plain left click and a plain right click start on. Those lines show the click icon only. Alt-left on the task name and the count starts on. A task special that is not Nothing starts on. The rest start off.\n\n"
            .. "Settings " .. pathArrow(12) .. " General (and the top of Modules) can group patch tasks as Default, Patch > zone, or Zones. Hover each option for the nest (Midnight is always the expansion header; rotating weeklies sit under Expansion Activities).\n\n"
            .. "New modules, in that same General section, starts off. A module added in a later update stays off until you turn it on under Modules. Turn New modules on if you want those added to the list. Hover a row in General for what that setting does. Empty groups, in List, defaults to off. A group you made with nothing in it stays off the list. Completed shows it when Show completed is on. Always shows it either way. Edit mode still shows it, so you can add a task or another group. Help tooltips starts on. Turn it off to hide those hover notes. Shortcut, in that same section, starts on. Turn it off to hide the shortcut lines at the bottom of a task tooltip. Task tooltip is separate, and it still covers the list.\n\n"
            .. "Title bar — Drag to move the window.\n\n"
            .. ia(ICON_EXPAND) .. " — Collapse or expand groups. Hover for Focus, Zone Only, or Zone + Global (Options → General → Current Zone Filter). A line, then Hide Modules, Hide Collections, and Hide Custom. Everything starts on the list. Click a row to hide that set, and the label switches to Show. Collections is the Collections headers. Custom is groups and tasks you added. Modules is the rest, such as Power, Seasonal, Professions, and patch activities. Another line, then Collapse all, Expand all, Collapse 1 level, and Expand 1 level. Include parent and Include subzone add the zone above or below you, such as the Vaults and The Coiled Isle. Color zone tints the zone you are standing in. Fade puts that color behind the right side of the row, thinning toward the left, instead of filling the row. One-level steps move the deepest open groups one nest up or down. The menu stays open so you can click more than once; move the mouse away to close it.\n\n"
            .. "+ / − — Collapse or expand the list (the title bar stays so you can open it again).\n\n"
            .. "Bottom-right corner — Drag the small L-shaped lines to resize when the list is open."
        ),
    },
    tracker_edit = {
        title = "Edit mode",
        body = (
            "Moving a row\n"
            .. "• Options " .. pathArrow(12) .. " General " .. pathArrow(12) .. " List " .. pathArrow(12) .. " List organization chooses how.\n"
            .. "• Pick and place: tap = to pick the row up. The lines between rows turn gold. Tap a gold line to drop it there. Tap = again to cancel.\n"
            .. "• Drag and drop: drag = to a gap. The row fades, and a copy of it follows the cursor. One line turns gold under the copy. Let go to drop the row. Let go anywhere else and the row stays where it was.\n\n"
            .. "• Each task row shows " .. ia(ICON_EDIT, 16, 16) .. " (same as Edit mode in the title): click to edit the task, Alt-click to delete it (with confirmation).\n\n"
            .. "• In the Add / Edit task or group windows, " .. ia(ICON_MAIL, 16, 16) .. " to the left of "
            .. ia(ICON_HELP, 16, 16) .. " opens import/export: copy definitions as text for another account or paste a shared export.\n\n"
            .. "Adding when nothing is picked up\n"
            .. "• Each insert line is split: the left half adds a new group; the right half adds a task under the group above (not on the empty top-level list). That header lights up, and the tooltip names the section. Dragging a row onto a gap does the same.\n"
            .. "• Official sections, such as Midnight, don't take new tasks. Add the task under a group you made. Toggle off on that header turns off every row in the section.\n\n"
            .. "Built-in Midnight rows stay grouped that way and cannot be reordered (your own groups still can).\n\n"
            .. "When you are done, turn Edit off with " .. ia(ICON_EDIT) .. " again.\n\n"
            .. "The bottom add bar includes " .. ia(ICON_MAIL, 16, 16)
            .. " — paste a **group** export to append it to your top-level list (use the task/group windows for task export)."
        ),
    },
    newTask = {
        title = "New / edit task",
        body = (
            [[• Task type — Basic Task is a normal checklist with a target count and reset schedule. Other types replace the count row with their own options (gold, achievement, items, quests, reputation) and use game data for progress when possible.

• Task name — What appears in your list. Notes and Popout sit at the bottom of the settings column, on one row. Notes opens to the right of this window. Popout opens a movable copy. On a new task, the note is saved when you add the task. On an existing task, that row is Edit data, Notes, and Popout. Sync joins that row after you turn it on under Options, Advanced. It defaults to off. While it is off, no one can send you a new task. Sync sends the task to a character on another account. Type their name and server. They can move it. The count follows yours. On a per-character task, each character on your account can send their own copy. Logging an alt does not change a copy already sent. A module row someone sent you stays on your list if you have that row turned off. They can't check it off, unless you turn on They can add to the count. Then they can raise the count, and that syncs back. They still can't lower it. If you both add to the count at the same time, both adds count. A weekly task someone sent you keeps this week's count. Logging in on another day this week does not open it again. It clears on the following week. Both of you need to be online for a send to land. Stop sharing removes the task from their list too. Sync all, under that Sync section, defaults to off. Turn it on to put the button on the tracker title bar. One click sends every shared task again. You can show the task owner's name on the task or in the tooltip. It defaults to on, with the name on the task. When you share a task, that same spot says who you sent it to. Tooltip moves the name onto the row hover. None hides it. Edit on a task someone sent you opens a small window. It shows who sent it and when. Delete removes it. The full editor stays closed. On a task that tracks itself, Locked keeps the number you set. Automatic follows the game. Shortcuts has Manual / automatic for that switch. The count stays where it is until the game updates that task.

• Reset schedule — None, Daily, Weekly, or Temporary. Daily/Weekly reset progress on that clock (gold tracking can optionally override its own reset). Temporary deletes the task from your list when it completes — useful for one-shot farms such as toys, mounts, or achievements (shown as [T] on the list). New advanced tasks default to Weekly and account-wide progress; you can change either. The clock used for daily/weekly periods is set under Settings → General → Daily / weekly reset (Auto matches this realm; US/EU presets; or Custom).

• Count toward parent group goals — Include (default) rolls the task into each ancestor group header’s done/total leaf counts. Exclude keeps the task visible for tracking but omits it from those roll-ups (and from summed group progress).

• When completed tasks are hidden — Hide (default) takes this task off the list with the others. Keep leaves it up.

• Quest type — Enter comma-separated quest IDs, shift-click quest links, or exact quest titles, and set how many from that list must be flagged complete in-game. Titles resolve when the client API or your open quest log matches the text exactly.

• Boss kills — In Boss mode, type part of an instance or boss name. Suggestions come from the dungeon journal. Gordoth counts as Lava Guard Gordoth. The check button says which boss that is before you kill it. The kill still has to finish successfully.

• How many to complete — Shown for Basic Task only; use − / + or type a number (1–99).

• Second line, Items — Goal is a number you type. AllTheThings total shows how many you are holding against the total AllTheThings still needs for collectables you do not have. That needs AllTheThings. Corrosive Coins, Voidlight Marl, and Remnant of Anguish use it.

• Second line, Achievement — Weekly target is what you gain this week toward a goal you type. In-game bar is the achievement's own total. The line starts with the achievement name. Ki'clak shows A Stack of Snacks - 4/5. Emerald Skyfang uses a weekly goal of 10. Ki'clak uses a weekly goal of 2. Both keep the in-game bar on this line.

Add Task / Save — Applies your changes. Cancel — Close without saving. On an existing task, Delete asks for confirmation first.]]

            .. "\n\n"
            .. ia(ICON_MAIL, 16, 16) .. " — To the left of " .. ia(ICON_HELP, 16, 16)
            .. " on this window: import or export the task as text for another account (progress is not included)."
        ),
    },
    newGroup = {
        title = "New / edit group",
        body = (
            [[• Group name — Shown on the collapsible header in your tracker.

• Create — Adds the group where you opened this from the list.

• Cancel — Close without saving.

When editing: Save renames the group. Delete removes the group and everything inside it (you will be asked to confirm). Module groups (Power, Seasonal Activities, patch groups, etc.) cannot be deleted—use Options → Modules to hide them. Custom groups you create can use most names and can always be deleted, even if the name matches a module group. A second group named Professions is refused, and so is a profession name placed under Professions. The window stays open and tells you to pick another name.]]

            .. "\n\n"
            .. ia(ICON_MAIL, 16, 16) .. " — To the left of " .. ia(ICON_HELP, 16, 16)
            .. " on this window: import or export the group and its tasks as text (registry rows are not included; progress is not included)."
        ),
    },
    notes = {
        title = "Notes & commands",
        body = (
            "• Notes — Free text for this task, under the Notes title. It saves as you type. An empty note shows \"Write a note here.\" That line is not saved, and the list icon stays off until you type. The window grows taller as the note gets longer so everything stays visible (no separate scroll inside the note).\n\n"
            .. "• Commands — The grey column on the left. A blank command row is there when the task has none. It is not saved until you change it. Add command is at the bottom of that column.\n\n"
            .. "• Title sits beside the icon. The name box is under Title, still to the right of the icon. Command is the slash command, under the icon. Click the icon to choose a new one. Use command, at the top of that window, uses the same #showtooltip check as a macro. A /cast or /use line can supply the picture. Pin and close sit on the right, level with Title. Pin shows the command on the task row. Close removes it.\n\n"
            .. "• Larger editor — The expand icon at the right of the command box opens a bigger box. Paste several lines there. The small box shows the first line.\n\n"
            .. "• Full or Lines — Sits on the right of Command. Full runs the whole command as one macro. Lines runs each line on its own, so a list of waypoints fits. Both run out of combat.\n\n"
            .. ia(ICON_CMD, 16, 16) .. " — On the main list, one command shows that icon on the row (click to run). Two or more commands open a flyout (out of combat).\n\n"
            .. "• Close (×) or opening Notes on another task keeps what you wrote for this task.\n\n"
            .. "• Popout — Opens a movable read-only copy of the note. The task name sits inside the note, above the text. Width follows the longest line, up to a cap. Close and edit sit on the title line, at the right. The hammer opens Notes. Commands sit along the bottom of the note. You can keep more than one popout open. Closing one leaves the others up. Each popout reopens where you left it after a reload or when you log in again. It stays open when you close Notes or hide the tracker. Style, then Popout, has Normal and Mouse Over. Those sliders follow Compact, Comfy, and Spacious. Change them on Custom. Close stays at least 10% so you can still find it.\n\n"
            .. "• Drag the title bar to move; the panel snaps beside the tracker based on your settings."
        ),
    },
}

local function helpBodyForKey(key)
    local h = HELP[key] or HELP.tracker_main
    return h.title, expandChromeIcons(h.body)
end

function TaskTracker.RefreshOpenHelp()
    local dialog = TaskTracker.helpPopup
    if not dialog or not dialog:IsShown() or not dialog._bodyFs then return end
    local title, body = helpBodyForKey(dialog.currentKey)
    if dialog.TitleText then
        dialog.TitleText:SetText("Help — " .. title)
    end
    dialog._bodyFs:SetText(body)
    if dialog.ReflowHelpBody then
        dialog:ReflowHelpBody()
    end
end

function TaskTracker.EnsureHelpPopup()
    local f = TaskTracker.helpPopup
    if f then return f end

    local w, h = 360, 288
    local dialog = TaskTracker.MakePanel("TaskTrackerHelpPopup", UIParent, w, h)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(260)
    dialog:SetClampedToScreen(true)
    if TaskTracker.AnchorFrameNearScreenTop then
        TaskTracker.AnchorFrameNearScreenTop(dialog, 0, 0.12)
    else
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    dialog:Hide()

    dialog:SetScript("OnDragStart", nil)
    dialog:SetScript("OnDragStop", nil)
    dialog:RegisterForDrag()

    local titleBar = dialog.titleBar
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        dialog:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        dialog:StopMovingOrSizing()
    end)

    dialog.CloseButton:SetScript("OnClick", function()
        dialog:Hide()
    end)

    local content = dialog.Content
    local pad = 8
    local _, sc, child = TaskTracker.MakeScrollPane(content, {
        useParent = true,
        left = pad,
        top = pad,
        right = pad,
        bottom = pad,
        pane = false,
    })

    local t = TaskTracker.GetTheme()
    local fs = TaskTracker.CreateFontString(child, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    TaskTracker.SetTextColor(fs, "textSecondary")
    dialog._bodyFs = fs
    dialog._scroll = sc
    dialog._child = child

    function dialog:ReflowHelpBody()
        local sw = (sc:GetWidth() or w - pad * 2) - 14
        if sw < 80 then sw = 80 end
        fs:SetWidth(sw)
        local textH = fs:GetStringHeight() or 40
        child:SetSize(math.max(sw, 40), math.max(textH + 12, 8))
        if sc.UpdateScrollBar then
            sc:UpdateScrollBar()
        end
        sc:SetVerticalScroll(0)
    end

    sc:SetScript("OnSizeChanged", function()
        if dialog:IsShown() then
            dialog:ReflowHelpBody()
        end
    end)

    dialog:SetScript("OnShow", function(self)
        self:ReflowHelpBody()
    end)

    TaskTracker.helpPopup = dialog
    dialog:SetScale(TaskTracker.GetUIScalePercent() / 100)
    return dialog
end

--- Show or hide the help window. Pass the same key again while open to close.
function TaskTracker.ToggleHelpScreen(key)
    if not key then key = "tracker_main" end
    local dialog = TaskTracker.EnsureHelpPopup()
    if dialog:IsShown() and dialog.currentKey == key then
        dialog:Hide()
        return
    end
    dialog.currentKey = key
    local title, body = helpBodyForKey(key)
    dialog.TitleText:SetText("Help — " .. title)
    dialog._bodyFs:SetText(body)
    dialog:ClearAllPoints()
    if TaskTracker.AnchorFrameNearScreenTop then
        TaskTracker.AnchorFrameNearScreenTop(dialog, 0, 0.12)
    else
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    dialog:Show()
    dialog:Raise()
    dialog:ReflowHelpBody()
    C_Timer.After(0, function()
        if dialog:IsShown() then
            dialog:ReflowHelpBody()
        end
    end)
end

--- Optional key function for screens whose help context is dynamic.
function TaskTracker.AttachHelpButton(titleBar, closeBtn, keyOrFn)
    if not titleBar or not closeBtn then return end
    local helpBtn = TaskTracker.MakeIconButton(titleBar, 20, 20, TaskTracker.ChromeIconOpt())
    helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
    helpBtn:SetChromeIcon(ICON_HELP)
    helpBtn:SetScript("OnClick", function()
        local key = keyOrFn
        if type(keyOrFn) == "function" then
            key = keyOrFn()
        end
        TaskTracker.ToggleHelpScreen(key)
    end)
    return helpBtn
end
