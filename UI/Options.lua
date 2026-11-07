-- UI/Options.lua
-- Options panel: left nav (scroll), right section (General, Characters, Style, Modules, Shortcuts, Generative tasks, Advanced, Profiles)

TaskTracker = TaskTracker or {}

local OPTS_WIDTH  = 1160
local OPTS_HEIGHT = 680
local NAV_PAD     = 8
local HDR_HEIGHT  = 26

local function OptRow()
    if TaskTracker.GetOptionsRowHeight then
        return TaskTracker.GetOptionsRowHeight()
    end
    return 28
end

--- Matches Bindings.xml → TaskTracker.RunBindingToggle
local TASKTRACKER_BINDING_CMD = "TASKTRACKER_TOGGLE"

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LMETA = true, RMETA = true,
}

local function RefreshListLayout()
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

local function currentPatchListGroupMode()
    if TaskTracker.GetPatchListGroupMode then
        return TaskTracker.GetPatchListGroupMode()
    end
    return "patch"
end

local function helpTipsHidden()
    return TaskTrackerDB and TaskTrackerDB.showHelpTooltips == false
end

local function attachButtonTip(btn, title, body)
    if not btn then return end
    local oEnter, oLeave = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
    btn:SetScript("OnEnter", function(self)
        if oEnter then oEnter(self) end
        if helpTipsHidden() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if body and body ~= "" then
            GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if oLeave then oLeave(self) end
    end)
end

local function attachRegionTip(region, title, body)
    if not region then return end
    local function showTip(self)
        if helpTipsHidden() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if body and body ~= "" then
            GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end
    local function hideTip()
        GameTooltip:Hide()
    end
    -- FontStrings do not take mouse scripts. A button follows the label after layout.
    if region.GetObjectType and region:GetObjectType() == "FontString" then
        local parent = region.GetParent and region:GetParent()
        if not parent then return end
        local hit = CreateFrame("Button", nil, parent)
        hit:SetScript("OnEnter", showTip)
        hit:SetScript("OnLeave", hideTip)
        region._ttHit = hit
        return
    end
    if region.EnableMouse then region:EnableMouse(true) end
    if region.SetScript then
        region:SetScript("OnEnter", showTip)
        region:SetScript("OnLeave", hideTip)
    end
end

function TaskTracker.SyncPatchListGroupModeButtons()
    local mode = currentPatchListGroupMode()
    local maps = TaskTracker._ttPatchListModeButtonMaps
    if type(maps) ~= "table" then return end
    for i = 1, #maps do
        local seg = maps[i]
        if seg and seg.SetActive then
            seg:SetActive(mode)
        end
    end
end

--- Exclusive Default / Patch > zone / Zones bar. Returns the segment host for anchoring.
local function MakePatchListGroupModeButtons(parent)
    local maps = TaskTracker._ttPatchListModeButtonMaps
    if type(maps) ~= "table" then
        maps = {}
        TaskTracker._ttPatchListModeButtonMaps = maps
    end
    local seg = TaskTracker.MakeQuietSegments(parent, {
        { key = "patch", label = "Default" },
        { key = "patch_zone", label = "Patch > zone" },
        { key = "zone", label = "Zones" },
    })
    maps[#maps + 1] = seg
    local function apply(key)
        if TaskTracker.SetPatchListGroupMode then
            TaskTracker.SetPatchListGroupMode(key)
        end
    end
    seg.buttons.patch:SetScript("OnClick", function() apply("patch") end)
    seg.buttons.patch_zone:SetScript("OnClick", function() apply("patch_zone") end)
    seg.buttons.zone:SetScript("OnClick", function() apply("zone") end)
    attachButtonTip(seg.buttons.patch, "Default",
        "Midnight > Patch > Zone. Collections stay with each patch, not split into zones.")
    attachButtonTip(seg.buttons.patch_zone, "Patch > zone",
        "Midnight > Patch > Zone. Collections are split into each zone.")
    attachButtonTip(seg.buttons.zone, "Zones",
        "Midnight > Zone. Collections are split into each zone. Ignores which patch added the task.")
    seg:SetActive(currentPatchListGroupMode())
    return seg
end

local function BuildBindingStringFromKey(key)
    if not key or key == "UNKNOWN" then return nil end
    if MODIFIER_KEYS[key] then return nil end
    local prefix = ""
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    return prefix .. key
end

local function MouseButtonToBindingToken(button)
    if button == "LeftButton" then return "BUTTON1" end
    if button == "RightButton" then return "BUTTON2" end
    if button == "MiddleButton" then return "BUTTON3" end
    if button == "Button4" then return "BUTTON4" end
    if button == "Button5" then return "BUTTON5" end
    return nil
end

--- Clear every key WoW has assigned to this command (can be more than one; SetBinding(new, cmd) adds, not replaces).
local function ClearTaskTrackerBindingKeysNoSave()
    local cmd = TASKTRACKER_BINDING_CMD
    for i = 1, GetNumBindings() do
        local t = { GetBinding(i) }
        if t[1] == cmd then
            for k = 3, #t do
                local keyToken = t[k]
                if keyToken and keyToken ~= "" then
                    pcall(SetBinding, keyToken, nil)
                end
            end
        end
    end
end

local function ClearTaskTrackerBindingKeys()
    ClearTaskTrackerBindingKeysNoSave()
    pcall(SaveBindings, GetCurrentBindingSet())
end

local function ApplyTaskTrackerBinding(bindingKey)
    if not bindingKey or bindingKey == "" then return false end
    ClearTaskTrackerBindingKeysNoSave()
    local ok = SetBinding(bindingKey, TASKTRACKER_BINDING_CMD)
    if ok then
        pcall(SaveBindings, GetCurrentBindingSet())
    end
    return ok
end

--- Tokens bound to our command (same source as Key Bindings UI; supports more than one slot per command).
local function GetTaskTrackerBindingKeyTokens()
    local cmd = TASKTRACKER_BINDING_CMD
    local keys = {}
    for i = 1, GetNumBindings() do
        local t = { GetBinding(i) }
        if t[1] == cmd then
            for k = 3, #t do
                local keyToken = t[k]
                if keyToken and keyToken ~= "" then
                    keys[#keys + 1] = keyToken
                end
            end
        end
    end
    if #keys > 0 then
        return keys
    end
    return nil
end

local keybindCaptureRoot

local function HideKeybindCapture()
    if keybindCaptureRoot then
        keybindCaptureRoot:Hide()
        keybindCaptureRoot:ClearFocus()
    end
end
TaskTracker.HideKeybindCapture = HideKeybindCapture

local function EnsureKeybindCapture(onApplied)
    if keybindCaptureRoot then
        keybindCaptureRoot._onApplied = onApplied
        return keybindCaptureRoot
    end
    -- Single fullscreen EditBox (mouse ON): if mouse were disabled on a child, clicks passed
    -- through to the Button behind and cleared keyboard focus — keys stopped working.
    local cap = CreateFrame("EditBox", "TaskTrackerKeybindCapture", UIParent)
    cap:SetFrameStrata("FULLSCREEN_DIALOG")
    cap:SetFrameLevel(2000)
    cap:SetAllPoints(UIParent)
    cap:SetAutoFocus(false)
    cap:EnableKeyboard(true)
    cap:EnableMouse(true)
    cap:EnableMouseWheel(true)
    cap:SetMultiLine(false)
    cap:SetText("")
    cap:SetTextColor(0, 0, 0, 0)
    if cap.SetPropagateKeyboardInput then
        cap:SetPropagateKeyboardInput(false)
    end

    local tint = cap:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints()
    tint:SetColorTexture(0.05, 0.05, 0.08, 0.72)

    local txt = TaskTracker.CreateFontString(cap, nil, "OVERLAY", "GameFontNormalHuge")
    txt:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    txt:SetText("Press a key, mouse button, or wheel…")
    local sub = TaskTracker.CreateFontString(cap, nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("TOP", txt, "BOTTOM", 0, -12)
    sub:SetText("|cffaaaaaaEscape|r — cancel")

    local function finishApplied()
        HideKeybindCapture()
        local fn = cap._onApplied
        if fn then fn() end
    end

    cap:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText("")
        end
    end)

    cap:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            HideKeybindCapture()
            return
        end
        local bind = BuildBindingStringFromKey(key)
        if bind then
            ApplyTaskTrackerBinding(bind)
            finishApplied()
        end
    end)

    cap:SetScript("OnEscapePressed", function()
        HideKeybindCapture()
    end)

    cap:SetScript("OnMouseDown", function(self, button)
        local tok = MouseButtonToBindingToken(button)
        if not tok then return end
        local bind = BuildBindingStringFromKey(tok)
        if bind then
            ApplyTaskTrackerBinding(bind)
            finishApplied()
        end
    end)

    cap:SetScript("OnMouseWheel", function(self, delta)
        local tok = (delta > 0) and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
        local bind = BuildBindingStringFromKey(tok)
        if bind then
            ApplyTaskTrackerBinding(bind)
            finishApplied()
        end
    end)

    cap._onApplied = onApplied
    cap:Hide()
    keybindCaptureRoot = cap

    -- Safety: if it ever gets shown unexpectedly, don't let it keep blocking clicks.
    cap:SetScript("OnHide", function(self)
        self:ClearFocus()
        if self.EnableMouse then self:EnableMouse(false) end
        if self.EnableMouseWheel then self:EnableMouseWheel(false) end
    end)
    cap:SetScript("OnShow", function(self)
        if self.EnableMouse then self:EnableMouse(true) end
        if self.EnableMouseWheel then self:EnableMouseWheel(true) end
        C_Timer.After(15, function()
            if self and self.IsShown and self:IsShown() then
                HideKeybindCapture()
            end
        end)
    end)

    return cap
end

local function ShowKeybindCapture(onApplied)
    local cap = EnsureKeybindCapture(onApplied)
    cap._onApplied = onApplied
    cap:Show()
    cap:SetFocus()
    C_Timer.After(0, function()
        if cap:IsShown() then
            cap:SetFocus()
        end
    end)
end

-- ─────────────────────────────────────
-- General (right-hand section)
-- ─────────────────────────────────────
local function BuildDisplayPanel(parent)
    local t = TaskTracker.GetTheme()
    local font = t.fontNormal or "GameFontNormalSmall"

    local content, scrollFrame, scrollChild, pane = TaskTracker.MakeScrollPane(parent, { childWidth = 400 })
    TaskTracker.optionsGeneralScrollBar = content.scrollBarTrack

    local PAD = 16
    local GAP = 8
    local ROW = OptRow()

    local function paintTimeEdit(box)
        local c = TaskTracker.GetTheme().textPrimary
        if c and box.SetTextColor then
            box:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
    end

    local function makeBlurb(text)
        local fs = TaskTracker.CreateFontString(pane, nil, "OVERLAY", font)
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        TaskTracker.SetTextColor(fs, "textSecondary")
        fs:SetText(text)
        return fs
    end

    local function labeledBar(labelText, seg, tipTitle, tipBody)
        local host = CreateFrame("Frame", nil, pane)
        host:SetHeight(ROW)
        local lab = TaskTracker.CreateFontString(host, nil, "OVERLAY", font)
        lab:SetPoint("LEFT", host, "LEFT", 0, 0)
        lab:SetJustifyH("LEFT")
        lab:SetJustifyV("MIDDLE")
        if lab.SetWordWrap then lab:SetWordWrap(false) end
        lab:SetText(labelText)
        TaskTracker.SetTextColor(lab, "textPrimary")
        if tipTitle then
            local hit = CreateFrame("Button", nil, host)
            hit:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            hit:SetPoint("BOTTOMRIGHT", seg, "BOTTOMLEFT", -8, 0)
            attachRegionTip(hit, tipTitle, tipBody)
        end
        seg:SetParent(host)
        seg:ClearAllPoints()
        seg:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        lab:SetPoint("RIGHT", seg, "LEFT", -8, 0)
        host.seg = seg
        function host:Layout(w)
            w = math.max(160, math.floor(w or 160))
            host:SetWidth(w)
            local segW = w - 168
            if segW < 96 then segW = math.max(72, math.floor(w * 0.58)) end
            seg:Layout(segW)
        end
        return host
    end

    local secDisplay = TaskTracker.MakeQuietSection(pane)
    secDisplay:SetText("General")
    local secList = TaskTracker.MakeQuietSection(pane)
    secList:SetText("List")
    local secReset = TaskTracker.MakeQuietSection(pane)
    secReset:SetText("Daily / weekly reset")
    local secWindow = TaskTracker.MakeQuietSection(pane)
    secWindow:SetText("Window")
    local secAddons = TaskTracker.MakeQuietSection(pane)
    secAddons:SetText("Connected addons")

    local togCompleted = TaskTracker.MakeQuietToggle(pane, "Show completed")
    local togTooltip = TaskTracker.MakeQuietToggle(pane, "Task tooltip")
    local togHelpTips = TaskTracker.MakeQuietToggle(pane, "Help tooltips")
    local togShortcut = TaskTracker.MakeQuietToggle(pane, "Shortcut")
    local togNewModules = TaskTracker.MakeQuietToggle(pane, "New modules")
    local valRowClick = TaskTracker.MakeQuietValue(pane, "Row click")
    valRowClick:SetWellWidth(88)
    local valOrganize = TaskTracker.MakeQuietValue(pane, "List organization")
    valOrganize:SetWellWidth(148)

    local segNote = TaskTracker.MakeQuietSegments(pane, {
        { key = "left", label = "Left" },
        { key = "right", label = "Right" },
    })
    local noteHost = labeledBar("Note panel", segNote, "Note panel",
        "Which side of the tracker the Notes window opens on. Hover Left or Right.")

    local togSubtextTip = TaskTracker.MakeQuietToggle(pane, "Second line in tooltip")
    local valNoteIcon = TaskTracker.MakeQuietValue(pane, "List note icon")
    valNoteIcon:SetWellWidth(110)

    local groupSeg = MakePatchListGroupModeButtons(pane)
    local groupHost = labeledBar("Patch grouping", groupSeg, "Patch grouping",
        "How Midnight headers are nested. Hover an option for that layout.")

    local groupBlurb = makeBlurb("Hover a grouping option for how Midnight headers are nested.")

    local segZone = TaskTracker.MakeQuietSegments(pane, {
        { key = "focus", label = "Focus" },
        { key = "zone", label = "Zone Only" },
        { key = "zone_plus", label = "Zone + Global" },
    })
    local zoneHost = labeledBar("Current Zone Filter", segZone, "Current Zone Filter",
        "Which tasks stay up for the zone you are in. Hover an option for that filter.")

    local togColor = TaskTracker.MakeQuietToggle(pane, "Color zone")
    local togUnderline = TaskTracker.MakeQuietToggle(pane, "Fade")
    local togParent = TaskTracker.MakeQuietToggle(pane, "Include parent")
    local togChild = TaskTracker.MakeQuietToggle(pane, "Include subzone")
    local zoneBlurb = makeBlurb("Color zone tints the zone you are standing in. Fade puts that color behind the right side of the row and lets it thin out toward the left. Both Include buttons can be on.")

    local resetBlurb = makeBlurb(
        "Auto matches this realm using Blizzard's reset timers (handles daylight saving). "
        .. "US follows 8:00 Pacific daily and Tuesday 10:00 Eastern weekly. "
        .. "EU follows 08:00 CET daily and Wednesday 05:00 CET weekly. "
        .. "Custom sets your own hour, minute, weekday, and zone (Pacific, Eastern, CET, or UTC)."
    )

    local segPreset = TaskTracker.MakeQuietSegments(pane, {
        { key = "server", label = "Auto" },
        { key = "us", label = "US" },
        { key = "eu", label = "EU" },
        { key = "custom", label = "Custom" },
    })
    local presetHost = labeledBar("Preset", segPreset, "Preset",
        "Which clock daily and weekly tasks use. Hover an option for that schedule.")

    local resetCustomHost = CreateFrame("Frame", nil, pane)
    resetCustomHost:SetHeight(132)

    local dLbl = TaskTracker.CreateFontString(resetCustomHost, nil, "OVERLAY", font)
    TaskTracker.SetTextColor(dLbl, "textSecondary")
    dLbl:SetText("Custom daily")

    local dhEdit = TaskTracker.MakeEditBox(resetCustomHost, nil, 36, 22)
    dhEdit:SetNumeric(true)
    dhEdit:SetMaxLetters(2)
    paintTimeEdit(dhEdit)
    local dColon = TaskTracker.CreateFontString(resetCustomHost, nil, "OVERLAY", "GameFontHighlightSmall")
    dColon:SetText(":")
    local dmiEdit = TaskTracker.MakeEditBox(resetCustomHost, nil, 36, 22)
    dmiEdit:SetNumeric(true)
    dmiEdit:SetMaxLetters(2)
    paintTimeEdit(dmiEdit)
    dColon:SetPoint("LEFT", dhEdit, "RIGHT", 4, 0)
    dmiEdit:SetPoint("LEFT", dColon, "RIGHT", 4, 0)

    local dTzSeg = TaskTracker.MakeQuietSegments(resetCustomHost, {
        { key = "Pacific", label = "Pacific" },
        { key = "Eastern", label = "Eastern" },
        { key = "CET", label = "CET" },
        { key = "UTC", label = "UTC" },
    })

    local wLbl = TaskTracker.CreateFontString(resetCustomHost, nil, "OVERLAY", font)
    TaskTracker.SetTextColor(wLbl, "textSecondary")
    wLbl:SetText("Custom weekly")

    local wdayShort = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
    local wdayFull = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
    local wdayItems = {}
    for wday = 1, 7 do
        wdayItems[wday] = { key = wday, label = wdayShort[wday] }
    end
    local wdaySeg = TaskTracker.MakeQuietSegments(resetCustomHost, wdayItems)

    local whEdit = TaskTracker.MakeEditBox(resetCustomHost, nil, 36, 22)
    whEdit:SetNumeric(true)
    whEdit:SetMaxLetters(2)
    paintTimeEdit(whEdit)
    local wColon = TaskTracker.CreateFontString(resetCustomHost, nil, "OVERLAY", "GameFontHighlightSmall")
    wColon:SetText(":")
    local wmiEdit = TaskTracker.MakeEditBox(resetCustomHost, nil, 36, 22)
    wmiEdit:SetNumeric(true)
    wmiEdit:SetMaxLetters(2)
    paintTimeEdit(wmiEdit)
    wColon:SetPoint("LEFT", whEdit, "RIGHT", 4, 0)
    wmiEdit:SetPoint("LEFT", wColon, "RIGHT", 4, 0)

    local wTzSeg = TaskTracker.MakeQuietSegments(resetCustomHost, {
        { key = "Pacific", label = "Pacific" },
        { key = "Eastern", label = "Eastern" },
        { key = "CET", label = "CET" },
        { key = "UTC", label = "UTC" },
    })

    local valBind = TaskTracker.MakeQuietValue(pane, "Toggle window")
    local bindSetBtn = TaskTracker.MakeQuietAction(pane, "Set key...", 88, ROW)
    local bindClearBtn = TaskTracker.MakeQuietAction(pane, "Clear", 64, ROW)
    local pathArrow = (TaskTracker.RightChevronMarkup and TaskTracker.RightChevronMarkup(12)) or ">"
    local bindHint = makeBlurb("Also listed under Escape " .. pathArrow .. " Key Bindings " .. pathArrow .. " Other. Click Set key... (or the binding field), then press the desired key, mouse button, or wheel.")

    local togAtt = TaskTracker.MakeQuietToggle(pane, "AllTheThings")
    local attHelpBtn = TaskTracker.MakeQuietAction(pane, "?", 28, ROW)
    local attStatus = makeBlurb("")

    local ATT_TIP_TITLE = "AllTheThings"
    local ATT_TIP_BODY = "When AllTheThings is loaded, hovering a vendor collectable can show extra costs (currency, gold, items) from that addon, and hovering a currency can list more items it buys. Ready to Buy, under Generated Tasks, uses the same data to suggest vendor collectables you can purchase right now. Turn this off to hide that extra data and leave Ready to Buy empty. If AllTheThings is not installed, Task Tracker still shows the vendor prices we ship — install AllTheThings to unlock the rest."

    local function UpdateHideBtn()
        local hiding = TaskTrackerDB and TaskTrackerDB.hideCompleted
        togCompleted:SetOn(not hiding)
    end

    togCompleted:SetScript("OnClick", function()
        if TaskTrackerDB then
            TaskTrackerDB.hideCompleted = not TaskTrackerDB.hideCompleted
            if TaskTracker.MarkListLayoutDirty then
                TaskTracker.MarkListLayoutDirty()
            end
            UpdateHideBtn()
            RefreshListLayout()
        end
    end)

    local function UpdateTipBtn()
        local off = TaskTrackerDB and TaskTrackerDB.showRowTooltips == false
        togTooltip:SetOn(not off)
    end

    togTooltip:SetScript("OnClick", function()
        if TaskTrackerDB then
            TaskTrackerDB.showRowTooltips = not (TaskTrackerDB.showRowTooltips ~= false)
            UpdateTipBtn()
        end
    end)

    local function UpdateHelpTipsBtn()
        togHelpTips:SetOn(not (TaskTrackerDB and TaskTrackerDB.showHelpTooltips == false))
    end

    togHelpTips:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.showHelpTooltips = (TaskTrackerDB.showHelpTooltips == false)
        UpdateHelpTipsBtn()
        if TaskTrackerDB.showHelpTooltips == false and GameTooltip then
            GameTooltip:Hide()
        end
    end)

    local function UpdateShortcutBtn()
        togShortcut:SetOn(not (TaskTrackerDB and TaskTrackerDB.showShortcutHints == false))
    end

    togShortcut:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.showShortcutHints = (TaskTrackerDB.showShortcutHints == false)
        UpdateShortcutBtn()
    end)

    local function UpdateNewModulesBtn()
        togNewModules:SetOn(TaskTrackerDB and TaskTrackerDB.enableNewModules == true)
    end

    togNewModules:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.enableNewModules = not (TaskTrackerDB.enableNewModules == true)
        UpdateNewModulesBtn()
    end)

    local function UpdateSubtextTipBtn()
        togSubtextTip:SetOn(TaskTrackerDB and TaskTrackerDB.subtextInTooltip == true)
    end

    togSubtextTip:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.subtextInTooltip = not (TaskTrackerDB.subtextInTooltip == true)
        UpdateSubtextTipBtn()
        if TaskTracker.MarkListLayoutDirty then
            TaskTracker.MarkListLayoutDirty()
        end
        RefreshListLayout()
    end)

    local function UpdateShiftClicksBtn()
        local shift = (TaskTrackerDB and TaskTrackerDB.requireShiftRowAdjustClicks ~= false)
        valRowClick:SetValue(shift and "Shift" or "Normal")
    end

    valRowClick:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.requireShiftRowAdjustClicks = not (TaskTrackerDB.requireShiftRowAdjustClicks ~= false)
        UpdateShiftClicksBtn()
    end)

    local function UpdateOrganizeBtn()
        local drag = TaskTrackerDB and TaskTrackerDB.editReorderMode == "drag"
        valOrganize:SetValue(drag and "Drag and drop" or "Pick and place")
    end

    valOrganize:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        if TaskTrackerDB.editReorderMode == "drag" then
            TaskTrackerDB.editReorderMode = "pick"
        else
            TaskTrackerDB.editReorderMode = "drag"
        end
        TaskTracker.reorderPickUpNodeId = nil
        if TaskTracker.CancelReorderDrag then
            TaskTracker.CancelReorderDrag()
        end
        UpdateOrganizeBtn()
        if TaskTracker.MarkListLayoutDirty then
            TaskTracker.MarkListLayoutDirty()
        end
        RefreshListLayout()
    end)

    local function SyncNoteSideButtons()
        local side = (TaskTrackerDB and TaskTrackerDB.notePanelSide) or "right"
        segNote:SetActive(side)
    end

    segNote.buttons.left:SetScript("OnClick", function()
        if TaskTrackerDB then
            TaskTrackerDB.notePanelSide = "left"
            SyncNoteSideButtons()
            if TaskTracker.UpdateNoteWindowAnchor then TaskTracker.UpdateNoteWindowAnchor() end
        end
    end)
    segNote.buttons.right:SetScript("OnClick", function()
        if TaskTrackerDB then
            TaskTrackerDB.notePanelSide = "right"
            SyncNoteSideButtons()
            if TaskTracker.UpdateNoteWindowAnchor then TaskTracker.UpdateNoteWindowAnchor() end
        end
    end)
    attachButtonTip(segNote.buttons.left, "Left",
        "The Notes window opens on the left of the tracker.")
    attachButtonTip(segNote.buttons.right, "Right",
        "The Notes window opens on the right of the tracker.")

    local function UpdateNoteIconBtn()
        local always = TaskTrackerDB and TaskTrackerDB.alwaysShowNoteIcon
        valNoteIcon:SetValue(always and "Always" or "When note")
    end

    valNoteIcon:SetScript("OnClick", function()
        if TaskTrackerDB then
            TaskTrackerDB.alwaysShowNoteIcon = not TaskTrackerDB.alwaysShowNoteIcon
            UpdateNoteIconBtn()
            RefreshListLayout()
        end
    end)

    local function SyncZoneFilterButtons()
        local mode = TaskTracker.GetZoneListFilterMode and TaskTracker.GetZoneListFilterMode() or "focus"
        segZone:SetActive(mode)
        togColor:SetOn(TaskTracker.ZoneHereUsesColor and TaskTracker.ZoneHereUsesColor())
        togParent:SetOn(TaskTracker.ZoneFilterIncludeParent and TaskTracker.ZoneFilterIncludeParent())
        togChild:SetOn(TaskTracker.ZoneFilterIncludeChild and TaskTracker.ZoneFilterIncludeChild())
        togUnderline:SetOn(TaskTracker.ZoneHereUsesUnderline and TaskTracker.ZoneHereUsesUnderline())
    end
    TaskTracker.SyncZoneListFilterButtons = SyncZoneFilterButtons

    segZone.buttons.focus:SetScript("OnClick", function()
        if TaskTracker.SetZoneListFilterMode then
            TaskTracker.SetZoneListFilterMode("focus")
        end
    end)
    segZone.buttons.zone:SetScript("OnClick", function()
        if TaskTracker.SetZoneListFilterMode then
            TaskTracker.SetZoneListFilterMode("zone")
        end
    end)
    segZone.buttons.zone_plus:SetScript("OnClick", function()
        if TaskTracker.SetZoneListFilterMode then
            TaskTracker.SetZoneListFilterMode("zone_plus")
        end
    end)
    togParent:SetScript("OnClick", function()
        if TaskTracker.SetZoneFilterIncludeParent then
            local on = TaskTracker.ZoneFilterIncludeParent and TaskTracker.ZoneFilterIncludeParent()
            TaskTracker.SetZoneFilterIncludeParent(not on)
        end
    end)
    togChild:SetScript("OnClick", function()
        if TaskTracker.SetZoneFilterIncludeChild then
            local on = TaskTracker.ZoneFilterIncludeChild and TaskTracker.ZoneFilterIncludeChild()
            TaskTracker.SetZoneFilterIncludeChild(not on)
        end
    end)
    togColor:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.zoneHereColor = not (TaskTracker.ZoneHereUsesColor and TaskTracker.ZoneHereUsesColor())
        togColor:SetOn(TaskTrackerDB.zoneHereColor)
        RefreshListLayout()
    end)
    togUnderline:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.zoneHereUnderline = not TaskTracker.ZoneHereUsesUnderline()
        togUnderline:SetOn(TaskTrackerDB.zoneHereUnderline)
        RefreshListLayout()
    end)
    attachButtonTip(segZone.buttons.focus, "Focus",
        "Collapse other groups and open the zone you are standing in. Nothing is removed from the list. In Default grouping, shared Collections headers open with their other rows still visible.")
    attachButtonTip(segZone.buttons.zone, "Zone Only",
        "Hide every task that is not for the zone you are in. Power, professions, and your own tasks hide too. Click the filter again for the full list.")
    attachButtonTip(segZone.buttons.zone_plus, "Zone + Global",
        "Hide other zones, and keep Power, professions, seasonal, and your own tasks. Click the filter again for the full list.")
    attachButtonTip(togColor, "Color zone",
        "Tint the zone you are standing in with the Current zone color. Off leaves those rows the same as the rest of the list. Fade changes how that tint is drawn.")
    attachButtonTip(togUnderline, "Fade",
        "With Color zone on, put that color behind the right side of the row. It fades out about a third of the way toward the left, instead of filling the whole row.")
    attachButtonTip(togParent, "Include parent",
        "In a nested zone such as the Vaults, also show the parent zone (The Coiled Isle). Off shows only the zone you are standing in.")
    attachButtonTip(togChild, "Include subzone",
        "On a parent zone such as The Coiled Isle, also show nested zones (the Vaults). Off leaves those headers collapsed and, for Zone Only, hidden.")
    attachButtonTip(togCompleted, "Show completed",
        "On leaves finished tasks on the list. Off takes them off. A task set to Keep stays up either way.")
    attachButtonTip(togTooltip, "Task tooltip",
        "On shows details when you hover a task, including its note. Off skips that tooltip.")
    attachButtonTip(togHelpTips, "Help tooltips",
        "On shows these hover notes in Settings. Off hides them. Task tooltips on the list stay. That switch is Task tooltip.")
    attachButtonTip(togShortcut, "Shortcut",
        "On shows shortcut lines at the bottom of a task tooltip. Off hides them. The task tooltip itself stays. That switch is Task tooltip.")
    attachButtonTip(togNewModules, "New modules",
        "On adds modules from a later update to the list. Off leaves them turned off under Modules until you enable one. Modules you already have stay as they are. Turning this on does not add ones that were already left off.")
    attachButtonTip(valRowClick, "Row click",
        "Shift means you hold Shift to change a count or check a box. Normal lets a plain click do it. Shift avoids changing a row by accident. Click to switch.")
    attachButtonTip(valOrganize, "List organization",
        "Pick and place: in Edit mode, click a row, then click the gap where it should go. Drag and drop: hold the row and move it. Click to switch.")
    attachButtonTip(togSubtextTip, "Second line in tooltip",
        "On moves the second line into the task tooltip and takes it off the row. Off leaves that line on the row.")
    attachButtonTip(valNoteIcon, "List note icon",
        "When note shows the icon only on a task that has a note. Always shows it on every task. Click to switch.")
    attachButtonTip(valBind, "Toggle window",
        "The key that opens and closes the tracker. Click this, or Set key, then press a key, mouse button, or the wheel. The same bind is under the game's Key Bindings, Other.")
    attachButtonTip(bindSetBtn, "Set key",
        "Click, then press the key, mouse button, or wheel that should open and close the tracker.")
    attachButtonTip(bindClearBtn, "Clear",
        "Remove the key that opens and closes the tracker.")
    attachRegionTip(dLbl, "Custom daily",
        "Hour and minute for the daily reset when Preset is Custom. Then pick the time zone.")
    attachRegionTip(wLbl, "Custom weekly",
        "Weekday, hour, and minute for the weekly reset when Preset is Custom. Then pick the time zone.")

    local function CommitResetScheduleChange()
        if TaskTracker.InvalidateResetTimesCache then
            TaskTracker.InvalidateResetTimesCache()
        end
        if TaskTracker.CheckResets then
            TaskTracker.CheckResets()
        end
        RefreshListLayout()
    end

    local function SyncPresetButtons()
        local p = (TaskTrackerDB and TaskTrackerDB.resetSchedulePreset) or "server"
        segPreset:SetActive(p)
    end

    local function bindTz(seg, keyName, kind)
        local zoneTip = {
            Pacific = kind .. " reset uses Pacific time.",
            Eastern = kind .. " reset uses Eastern time.",
            CET = kind .. " reset uses Central European Time.",
            UTC = kind .. " reset uses UTC.",
        }
        for name, btn in pairs(seg.buttons) do
            btn:SetScript("OnClick", function()
                if not TaskTrackerDB then return end
                TaskTrackerDB[keyName] = name
                seg:SetActive(name)
                CommitResetScheduleChange()
            end)
            attachButtonTip(btn, name, zoneTip[name] or (kind .. " reset uses this time zone."))
        end
    end
    bindTz(dTzSeg, "resetCustomDailyTZ", "Daily")
    bindTz(wTzSeg, "resetCustomWeeklyTZ", "Weekly")

    for wday, btn in pairs(wdaySeg.buttons) do
        btn:SetScript("OnClick", function()
            if not TaskTrackerDB then return end
            TaskTrackerDB.resetCustomWeeklyWday = wday
            wdaySeg:SetActive(wday)
            CommitResetScheduleChange()
        end)
        attachButtonTip(btn, wdayFull[wday] or "Weekday",
            "Weekly tasks reset on this day when Preset is Custom.")
    end

    local function SyncDailyTzButtons()
        local cur = (TaskTrackerDB and TaskTrackerDB.resetCustomDailyTZ) or "Pacific"
        dTzSeg:SetActive(cur)
    end

    local function SyncWeeklyTzButtons()
        local cur = (TaskTrackerDB and TaskTrackerDB.resetCustomWeeklyTZ) or "Eastern"
        wTzSeg:SetActive(cur)
    end

    local function SyncWdayButtons()
        local cur = math.max(1, math.min(7, math.floor(tonumber(TaskTrackerDB and TaskTrackerDB.resetCustomWeeklyWday) or 3)))
        wdaySeg:SetActive(cur)
    end

    local function SyncCustomEdits()
        if not TaskTrackerDB then return end
        dhEdit:SetText(tostring(math.max(0, math.min(23, math.floor(tonumber(TaskTrackerDB.resetCustomDailyHour) or 8)))))
        dmiEdit:SetText(string.format("%02d", math.max(0, math.min(59, math.floor(tonumber(TaskTrackerDB.resetCustomDailyMinute) or 0)))))
        whEdit:SetText(tostring(math.max(0, math.min(23, math.floor(tonumber(TaskTrackerDB.resetCustomWeeklyHour) or 10)))))
        wmiEdit:SetText(string.format("%02d", math.max(0, math.min(59, math.floor(tonumber(TaskTrackerDB.resetCustomWeeklyMinute) or 0)))))
    end

    local function commitDailyHM()
        if not TaskTrackerDB then return end
        local h = math.max(0, math.min(23, math.floor(tonumber(dhEdit:GetText()) or 0)))
        local mi = math.max(0, math.min(59, math.floor(tonumber(dmiEdit:GetText()) or 0)))
        TaskTrackerDB.resetCustomDailyHour = h
        TaskTrackerDB.resetCustomDailyMinute = mi
        SyncCustomEdits()
        CommitResetScheduleChange()
    end

    local function commitWeeklyHM()
        if not TaskTrackerDB then return end
        local h = math.max(0, math.min(23, math.floor(tonumber(whEdit:GetText()) or 0)))
        local mi = math.max(0, math.min(59, math.floor(tonumber(wmiEdit:GetText()) or 0)))
        TaskTrackerDB.resetCustomWeeklyHour = h
        TaskTrackerDB.resetCustomWeeklyMinute = mi
        SyncCustomEdits()
        CommitResetScheduleChange()
    end

    dhEdit:SetScript("OnEnterPressed", function(self) commitDailyHM() self:ClearFocus() end)
    dhEdit:SetScript("OnEditFocusLost", function() commitDailyHM() end)
    dmiEdit:SetScript("OnEnterPressed", function(self) commitDailyHM() self:ClearFocus() end)
    dmiEdit:SetScript("OnEditFocusLost", function() commitDailyHM() end)
    whEdit:SetScript("OnEnterPressed", function(self) commitWeeklyHM() self:ClearFocus() end)
    whEdit:SetScript("OnEditFocusLost", function() commitWeeklyHM() end)
    wmiEdit:SetScript("OnEnterPressed", function(self) commitWeeklyHM() self:ClearFocus() end)
    wmiEdit:SetScript("OnEditFocusLost", function() commitWeeklyHM() end)

    local function textBlockHeight(fs, width)
        fs:SetWidth(width)
        local h = fs:GetStringHeight() or 0
        if h < 12 then
            local text = fs:GetText() or ""
            local per = math.max(24, math.floor(width / 6.2))
            h = math.max(1, math.ceil(#text / per)) * 14
        end
        return h
    end

    local function layoutCustom(hostW)
        local y = 0
        local function timeRow(editH, editM, tz, wide)
            editH:ClearAllPoints()
            editH:SetPoint("TOPLEFT", resetCustomHost, "TOPLEFT", 0, -y)
            if wide then
                tz:ClearAllPoints()
                tz:SetPoint("LEFT", editM, "RIGHT", 12, 0)
                tz:Layout(math.max(180, hostW - 110))
                y = y + ROW
            else
                y = y + ROW + 6
                tz:ClearAllPoints()
                tz:SetPoint("TOPLEFT", resetCustomHost, "TOPLEFT", 0, -y)
                tz:Layout(hostW)
                y = y + ROW
            end
        end
        local wide = hostW >= 460
        dLbl:ClearAllPoints()
        dLbl:SetPoint("TOPLEFT", resetCustomHost, "TOPLEFT", 0, -y)
        if dLbl._ttHit then
            dLbl._ttHit:ClearAllPoints()
            dLbl._ttHit:SetPoint("TOPLEFT", dLbl, "TOPLEFT", 0, 0)
            dLbl._ttHit:SetSize(math.max(40, dLbl:GetStringWidth() or 80), 16)
        end
        y = y + 18
        timeRow(dhEdit, dmiEdit, dTzSeg, wide)
        y = y + 10
        wLbl:ClearAllPoints()
        wLbl:SetPoint("TOPLEFT", resetCustomHost, "TOPLEFT", 0, -y)
        if wLbl._ttHit then
            wLbl._ttHit:ClearAllPoints()
            wLbl._ttHit:SetPoint("TOPLEFT", wLbl, "TOPLEFT", 0, 0)
            wLbl._ttHit:SetSize(math.max(40, wLbl:GetStringWidth() or 80), 16)
        end
        y = y + 18
        wdaySeg:ClearAllPoints()
        wdaySeg:SetPoint("TOPLEFT", resetCustomHost, "TOPLEFT", 0, -y)
        wdaySeg:Layout(hostW)
        y = y + ROW + 8
        timeRow(whEdit, wmiEdit, wTzSeg, wide)
        return y
    end

    local function RefreshKeybindDisplayBtn()
        local tokens = GetTaskTrackerBindingKeyTokens()
        if not tokens then
            valBind:SetValue("Not bound")
        else
            local parts = {}
            for _, tok in ipairs(tokens) do
                parts[#parts + 1] = GetBindingText(tok, "KEY_", true) or tok
            end
            valBind:SetValue(table.concat(parts, ", "))
        end
    end

    local function OpenKeybindCapture()
        C_Timer.After(0, function()
            ShowKeybindCapture(RefreshKeybindDisplayBtn)
        end)
    end

    valBind:SetScript("OnClick", OpenKeybindCapture)
    bindSetBtn:SetScript("OnClick", OpenKeybindCapture)
    bindClearBtn:SetScript("OnClick", function()
        ClearTaskTrackerBindingKeys()
        RefreshKeybindDisplayBtn()
    end)

    local function UpdateAttBtn()
        local on = not TaskTrackerDB or TaskTrackerDB.attDataEnabled ~= false
        local loaded = TaskTracker.IsAllTheThingsLoaded and TaskTracker.IsAllTheThingsLoaded()
        togAtt:SetOn(on)
        if loaded then
            attStatus:SetText(on
                and "Loaded. Extra vendor costs show on hover."
                or "Loaded. Extra vendor costs are hidden.")
        else
            attStatus:SetText("Not installed. Extra vendor costs need AllTheThings.")
        end
    end

    togAtt:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.attDataEnabled = not (TaskTrackerDB.attDataEnabled ~= false)
        UpdateAttBtn()
        if TaskTracker.RequestReadyToBuyScan then
            TaskTracker.RequestReadyToBuyScan(true)
        end
    end)
    attachButtonTip(togAtt, ATT_TIP_TITLE, ATT_TIP_BODY)
    attachButtonTip(attHelpBtn, ATT_TIP_TITLE, ATT_TIP_BODY)

    local RebuildLayout
    local function applyPreset(presetKey)
        if not TaskTrackerDB then return end
        TaskTrackerDB.resetSchedulePreset = presetKey
        SyncPresetButtons()
        if RebuildLayout then RebuildLayout() end
        CommitResetScheduleChange()
    end

    segPreset.buttons.server:SetScript("OnClick", function() applyPreset("server") end)
    segPreset.buttons.us:SetScript("OnClick", function() applyPreset("us") end)
    segPreset.buttons.eu:SetScript("OnClick", function() applyPreset("eu") end)
    segPreset.buttons.custom:SetScript("OnClick", function() applyPreset("custom") end)
    attachButtonTip(segPreset.buttons.server, "Auto",
        "Uses this realm's reset. Daylight saving follows the game's timers.")
    attachButtonTip(segPreset.buttons.us, "US",
        "Daily at 8:00 Pacific. Weekly on Tuesday at 10:00 Eastern.")
    attachButtonTip(segPreset.buttons.eu, "EU",
        "Daily at 08:00 CET. Weekly on Wednesday at 05:00 CET.")
    attachButtonTip(segPreset.buttons.custom, "Custom",
        "Set your own hour, minute, weekday, and time zone.")

    local function placeBox(widget, x, y, w)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -y)
        widget:SetWidth(w)
        if widget.Layout then widget:Layout(w) end
    end

    local function placeBlurb(fs, y, width)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -y)
        return y + textBlockHeight(fs, width) + GAP
    end

    RebuildLayout = function()
        local sw = scrollFrame:GetWidth()
        if sw < 80 then sw = 400 end
        sw = math.max(280, sw - 16)
        local inner = math.max(200, sw - PAD * 2)
        local two = inner >= 520
        local colW = two and math.floor((inner - GAP) / 2) or inner
        local y = 8

        local function rowPair(a, b)
            placeBox(a, PAD, y, colW)
            if two then
                placeBox(b, PAD + colW + GAP, y, colW)
                y = y + ROW + GAP
            else
                y = y + ROW + GAP
                placeBox(b, PAD, y, inner)
                y = y + ROW + GAP
            end
        end

        y = secDisplay:Place(pane, PAD, y, inner)
        rowPair(togCompleted, togTooltip)
        rowPair(togShortcut, togHelpTips)
        rowPair(togNewModules, valRowClick)
        placeBox(noteHost, PAD, y, inner)
        y = y + ROW + GAP
        y = y + 4

        y = secList:Place(pane, PAD, y, inner)
        placeBox(valOrganize, PAD, y, inner)
        valOrganize:SetWellWidth(148)
        y = y + ROW + GAP
        placeBox(togSubtextTip, PAD, y, inner)
        y = y + ROW + GAP
        placeBox(valNoteIcon, PAD, y, inner)
        valNoteIcon:SetWellWidth(120)
        y = y + ROW + GAP
        placeBox(groupHost, PAD, y, inner)
        y = y + ROW + 4
        y = placeBlurb(groupBlurb, y, inner)
        placeBox(zoneHost, PAD, y, inner)
        y = y + ROW + GAP
        rowPair(togColor, togParent)
        rowPair(togUnderline, togChild)
        y = placeBlurb(zoneBlurb, y, inner)
        y = y + 4

        y = secReset:Place(pane, PAD, y, inner)
        y = placeBlurb(resetBlurb, y, inner)
        placeBox(presetHost, PAD, y, inner)
        y = y + ROW + GAP

        local custom = TaskTrackerDB and TaskTrackerDB.resetSchedulePreset == "custom"
        if custom then
            resetCustomHost:Show()
            resetCustomHost:ClearAllPoints()
            resetCustomHost:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -y)
            resetCustomHost:SetWidth(inner)
            local ch = layoutCustom(inner)
            resetCustomHost:SetHeight(ch)
            y = y + ch + GAP
        else
            resetCustomHost:Hide()
        end

        y = y + 4
        y = secWindow:Place(pane, PAD, y, inner)
        local clearW, setW = 64, 88
        local valueW = inner - clearW - setW - GAP * 2
        bindSetBtn:ClearAllPoints()
        bindClearBtn:ClearAllPoints()
        if valueW >= 160 then
            placeBox(valBind, PAD, y, valueW)
            valBind:SetWellWidth(math.max(100, math.floor(valueW * 0.46)))
            bindSetBtn:SetPoint("LEFT", valBind, "RIGHT", GAP, 0)
            bindClearBtn:SetPoint("LEFT", bindSetBtn, "RIGHT", GAP, 0)
            y = y + ROW + 4
        else
            placeBox(valBind, PAD, y, inner)
            valBind:SetWellWidth(math.max(100, math.floor(inner * 0.42)))
            y = y + ROW + GAP
            bindSetBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -y)
            bindClearBtn:SetPoint("LEFT", bindSetBtn, "RIGHT", GAP, 0)
            y = y + ROW + 4
        end
        y = placeBlurb(bindHint, y, inner)

        y = y + 4
        y = secAddons:Place(pane, PAD, y, inner)
        local attW = math.max(160, inner - 28 - GAP)
        placeBox(togAtt, PAD, y, attW)
        attHelpBtn:ClearAllPoints()
        attHelpBtn:SetPoint("LEFT", togAtt, "RIGHT", GAP, 0)
        y = y + ROW + 4
        y = placeBlurb(attStatus, y, inner)

        local h = y + 16
        pane:SetSize(sw, h)
        scrollChild:SetSize(sw, h)
        if scrollFrame.UpdateScrollBar then
            scrollFrame.UpdateScrollBar()
        end
    end

    local function SyncResetSchedulePanel()
        SyncPresetButtons()
        SyncCustomEdits()
        SyncDailyTzButtons()
        SyncWeeklyTzButtons()
        SyncWdayButtons()
        RebuildLayout()
    end

    UpdateHideBtn()
    UpdateTipBtn()
    UpdateHelpTipsBtn()
    UpdateShortcutBtn()
    UpdateNewModulesBtn()
    UpdateSubtextTipBtn()
    UpdateShiftClicksBtn()
    UpdateOrganizeBtn()
    SyncNoteSideButtons()
    UpdateNoteIconBtn()
    SyncZoneFilterButtons()
    RefreshKeybindDisplayBtn()
    UpdateAttBtn()
    SyncResetSchedulePanel()

    content.scrollFrame = scrollFrame
    content.RebuildLayout = RebuildLayout
    content.SyncNoteSideButtons = SyncNoteSideButtons
    content.SyncNoteIconBtn = UpdateNoteIconBtn
    content.SyncResetSchedulePanel = SyncResetSchedulePanel

    content.OnShow = function()
        UpdateHideBtn()
        UpdateTipBtn()
        UpdateHelpTipsBtn()
    UpdateShortcutBtn()
        UpdateNewModulesBtn()
        UpdateSubtextTipBtn()
        UpdateShiftClicksBtn()
        UpdateOrganizeBtn()
        RefreshKeybindDisplayBtn()
        UpdateNoteIconBtn()
        UpdateAttBtn()
        if TaskTracker.SyncZoneListFilterButtons then
            TaskTracker.SyncZoneListFilterButtons()
        end
        if content.SyncNoteSideButtons then
            content.SyncNoteSideButtons()
        end
        SyncResetSchedulePanel()
    end

    return content
end

-- ─────────────────────────────────────
-- Style tab: Style, Sizes, List, Headers, Tasks
-- ─────────────────────────────────────
local function BuildListLayoutPanel(parent)
    local t = TaskTracker.GetTheme()
    local themeOrder = TaskTracker.GetThemeOrder and TaskTracker.GetThemeOrder()
        or TaskTracker.THEME_ORDER or { "dark", "parchment" }

    local PAD = 16
    local COL_GAP = 12
    local ROW_H = OptRow()
    local ROW_GAP = 8
    local ROW_STRIDE = ROW_H + ROW_GAP

    local content, scrollFrame, scrollChild, pane = TaskTracker.MakeScrollPane(parent, { childWidth = 400 })
    TaskTracker.optionsLayoutScrollBar = content.scrollBarTrack

    local yBuild = 10

    local function sectionHeader(titleText)
        local title = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontBold or "GameFontNormal")
        title:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yBuild)
        TaskTracker.SetTextColor(title, "textAccent")
        title:SetText(titleText)
        yBuild = yBuild + 20
        local sep = pane:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT",  pane, "TOPLEFT",  PAD, -yBuild)
        sep:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -PAD, -yBuild)
        TaskTracker.SetColor(sep, "border")
        yBuild = yBuild + 8
        return { title = title, sep = sep }
    end

    local function placeSectionHeader(h, yRef)
        local titleH, block = 16, 24
        if TaskTracker.OptionsSectionLead then
            titleH, block = TaskTracker.OptionsSectionLead()
        end
        h.title:ClearAllPoints()
        h.title:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yRef)
        h.title:SetHeight(titleH)
        h.sep:ClearAllPoints()
        h.sep:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -(yRef + titleH))
        h.sep:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -PAD, -(yRef + titleH))
        return yRef + block
    end

    -- ─── Style (theme) ───
    local hdrOptionsPanel = sectionHeader("Options Panel")
    local hdrTitleBar = sectionHeader("Title bar")
    local hdrStyle = sectionHeader("Style")

    local themeDdLabel = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    themeDdLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yBuild)
    TaskTracker.SetTextColor(themeDdLabel, "textPrimary")
    themeDdLabel:SetText("Color theme")
    themeDdLabel:SetJustifyV("MIDDLE")
    yBuild = yBuild + 20

    local themeItems = {}
    for _, key in ipairs(themeOrder) do
        local th = TaskTracker.Themes[key]
        themeItems[#themeItems + 1] = { key = key, label = (th and th.name) or key }
    end
    local themeDrop = TaskTracker.MakeDropdown(pane, {
        width = 200,
        buttonHeight = ROW_H,
        rowHeight = ROW_H,
        rowGap = 2,
        items = themeItems,
        disableHover = true,
        quiet = true,
        menuBgKey = "headerBg2",
        getSelected = function()
            return (TaskTrackerDB and TaskTrackerDB.theme) or "dark"
        end,
        selectedLabel = function(key)
            local th = TaskTracker.Themes[key]
            return (th and th.name) or key
        end,
        onSelect = function(key)
            TaskTracker.SetTheme(key)
        end,
    })
    local themeDdBtn = themeDrop.button
    local themeMenu = themeDrop.menu
    local themeMenuOpts = themeDrop.rows
    local SyncThemeDropdownLabel = themeDrop.refresh
    themeDdBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yBuild)

    local customizeBtn = TaskTracker.MakeQuietAction(pane, "Customize\226\128\166", 108, ROW_H)
    customizeBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -(yBuild + 28))
    customizeBtn:SetScript("OnClick", function()
        if TaskTracker.OpenThemeEditor then
            TaskTracker.OpenThemeEditor()
        end
    end)
    customizeBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(customizeBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Customize theme", 1, 1, 1)
        GameTooltip:AddLine("Opens an editor for a custom copy. Built-in themes are never changed. This edits colors only. Spacing stays on Compact, Comfy, Spacious, or Custom. If you are already on a custom theme, this edits that copy.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    customizeBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if customizeBtn.bg then TaskTracker.SetColor(customizeBtn.bg, "inputBg") end
    end)

    local deleteThemeBtn = TaskTracker.MakeQuietAction(pane, "Delete custom", 120, ROW_H)
    deleteThemeBtn:SetPoint("LEFT", customizeBtn, "RIGHT", 8, 0)
    local function SyncThemeActionButtons()
        local key = (TaskTrackerDB and TaskTrackerDB.theme) or "dark"
        if TaskTracker.IsCustomTheme and TaskTracker.IsCustomTheme(key) then
            deleteThemeBtn:Show()
        else
            deleteThemeBtn:Hide()
        end
    end
    deleteThemeBtn:SetScript("OnClick", function()
        local key = (TaskTrackerDB and TaskTrackerDB.theme) or "dark"
        if not (TaskTracker.IsCustomTheme and TaskTracker.IsCustomTheme(key)) then return end
        local th = TaskTracker.Themes[key]
        StaticPopupDialogs["TASKTRACKER_DELETE_CUSTOM_THEME"] = {
            text = "Delete custom theme \"%s\"?\nBuilt-in themes are not affected.",
            button1 = YES,
            button2 = NO,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            OnAccept = function()
                TaskTracker.DeleteCustomTheme(key)
            end,
        }
        StaticPopup_Show("TASKTRACKER_DELETE_CUSTOM_THEME", (th and th.name) or "Custom")
    end)
    SyncThemeActionButtons()

    yBuild = yBuild + 56

    local narrowLabel = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    narrowLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yBuild)
    TaskTracker.SetTextColor(narrowLabel, "textPrimary")
    narrowLabel:SetText("Narrow titles")
    narrowLabel:SetJustifyV("MIDDLE")
    yBuild = yBuild + 20

    local overflowSeg = TaskTracker.MakeQuietSegments(pane, {
        { key = "ellipsis", label = "Truncate" },
        { key = "grow", label = "Wrap lines" },
    })
    overflowSeg:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yBuild)

    local function paintOverflowModeButtons()
        local mode = TaskTracker.GetTaskLabelOverflowMode and TaskTracker.GetTaskLabelOverflowMode() or "ellipsis"
        overflowSeg:SetActive(mode)
    end

    overflowSeg.buttons.ellipsis:SetScript("OnClick", function()
        if TaskTrackerDB then TaskTrackerDB.taskLabelOverflow = "ellipsis" end
        paintOverflowModeButtons()
        RefreshListLayout()
    end)
    overflowSeg.buttons.grow:SetScript("OnClick", function()
        if TaskTrackerDB then TaskTrackerDB.taskLabelOverflow = "grow" end
        paintOverflowModeButtons()
        RefreshListLayout()
    end)
    paintOverflowModeButtons()

    yBuild = yBuild + 32

    -- ─── Icons (Classic game icons first, tintable white set second) ───
    local ICON_PREVIEW = { "gear", "eye", "edit", "note", "mail" }
    local hdrIcons = sectionHeader("Icons")
    local iconChoices = {}

    local function paintIconChoices()
        local active = TaskTracker.GetIconSet and TaskTracker.GetIconSet() or "classic"
        for key, btn in pairs(iconChoices) do
            TaskTracker.SetColor(btn.bg, (key == active) and "accentBg" or "headerBg")
            if btn.icons then
                for i, tex in ipairs(btn.icons) do
                    TaskTracker.ApplyChromeIcon(tex, ICON_PREVIEW[i], key)
                end
            end
        end
    end

    local function makeIconChoice(key, label)
        local btn = CreateFrame("Button", nil, pane)
        btn:SetSize(220, ROW_H)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        btn.bg = bg
        TaskTracker.MakeBorder(btn, "border")
        local lab = TaskTracker.CreateFontString(btn, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
        lab:SetPoint("LEFT", btn, "LEFT", 10, 0)
        lab:SetText(label)
        TaskTracker.SetTextColor(lab, "textPrimary")
        local icons = {}
        for i, name in ipairs(ICON_PREVIEW) do
            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetSize(16, 16)
            tex:SetPoint("LEFT", lab, "RIGHT", 10 + (i - 1) * 20, 0)
            TaskTracker.ApplyChromeIcon(tex, name, key)
            icons[i] = tex
        end
        btn.icons = icons
        btn:SetScript("OnClick", function()
            if TaskTrackerDB then TaskTrackerDB.iconSet = key end
            paintIconChoices()
            if TaskTracker.RefreshChromeIcons then
                TaskTracker.RefreshChromeIcons()
            end
        end)
        iconChoices[key] = btn
        return btn
    end

    local classicChoice = makeIconChoice("classic", "Classic")
    local tintChoice = makeIconChoice("tintable", "Tintable")
    classicChoice:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yBuild)
    tintChoice:SetPoint("LEFT", classicChoice, "RIGHT", 8, 0)
    paintIconChoices()
    yBuild = yBuild + ROW_H + 8

    -- ─── Sizes (list font + whole UI) ───
    local hdrSizes = sectionHeader("Sizes")

    local uiRow
    yBuild, uiRow = TaskTracker.MakeQuietSlider(pane, {
        x = PAD, y = yBuild, label = "Whole UI (%)",
        getVal = TaskTracker.GetUIScalePercent,
        setVal = function(n) TaskTrackerDB.uiScalePercent = n end,
        min = 60, max = 140, step = 5,
        rowStride = ROW_STRIDE,
        onCommit = function()
            if TaskTracker.ApplyUIScale then TaskTracker.ApplyUIScale() end
        end,
    })
    local SyncUIScaleEditFromDB = uiRow.sync

    local hdrList = sectionHeader("List")
    local hdrHeaders = sectionHeader("Headers")
    local hdrTasks = sectionHeader("Tasks")

    local titleBarRows, listIntRows, headerIntRows, taskIntRows, chromeRows = {}, {}, {}, {}, {}
    local optionsPanelRows = {}
    local allLayoutIntRows = {}
    local applyPresetVisuals

    local spacingLabel = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    TaskTracker.SetTextColor(spacingLabel, "textPrimary")
    spacingLabel:SetText("Spacing")
    spacingLabel:SetJustifyV("MIDDLE")

    local densitySeg = TaskTracker.MakeQuietSegments(pane, {
        { key = "compact", label = "Compact" },
        { key = "comfy", label = "Comfy" },
        { key = "spacious", label = "Spacious" },
        { key = "custom", label = "Custom" },
    })
    local function pickPreset(key)
        if TaskTracker.GetLayoutPreset and TaskTracker.GetLayoutPreset() == key then return end
        if TaskTracker.ApplyLayoutPreset then
            TaskTracker.ApplyLayoutPreset(key)
        end
    end
    densitySeg.buttons.compact:SetScript("OnClick", function() pickPreset("compact") end)
    densitySeg.buttons.comfy:SetScript("OnClick", function() pickPreset("comfy") end)
    densitySeg.buttons.spacious:SetScript("OnClick", function() pickPreset("spacious") end)
    densitySeg.buttons.custom:SetScript("OnClick", function() pickPreset("custom") end)

    local copyBtn = TaskTracker.MakeIconButton(pane, 22, ROW_H)
    copyBtn:SetChromeIcon("copy")
    copyBtn:SetScript("OnEnter", function()
        if copyBtn.bg then TaskTracker.SetColor(copyBtn.bg, "accentBg") end
        GameTooltip:SetOwner(copyBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Copy from", 1, 1, 1)
        GameTooltip:AddLine("Copies Compact, Comfy, or Spacious into Custom.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    copyBtn:SetScript("OnLeave", function()
        if copyBtn.bg then TaskTracker.SetColor(copyBtn.bg, "headerBg") end
        GameTooltip:Hide()
    end)
    local copyDrop = TaskTracker.MakeDropdown(pane, {
        width = 140,
        buttonHeight = 22,
        rowHeight = 24,
        rowGap = 2,
        items = {
            { key = "compact", label = "Compact" },
            { key = "comfy", label = "Comfy" },
            { key = "spacious", label = "Spacious" },
        },
        disableHover = true,
        quiet = true,
        menuBgKey = "headerBg2",
        getSelected = function() return nil end,
        onSelect = function(key)
            if TaskTracker.CopyLayoutFromPreset then
                TaskTracker.CopyLayoutFromPreset(key)
            end
        end,
    })
    copyDrop.button:Hide()
    local copyMenu = copyDrop.menu
    copyBtn:SetScript("OnClick", function()
        if copyMenu:IsShown() then
            copyMenu:Hide()
            return
        end
        copyMenu:ClearAllPoints()
        copyMenu:SetPoint("TOPRIGHT", copyBtn, "BOTTOMRIGHT", 0, -2)
        copyMenu:Show()
        copyMenu:Raise()
    end)

    local fontLabel = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    TaskTracker.SetTextColor(fontLabel, "textPrimary")
    fontLabel:SetText("Font")
    fontLabel:SetJustifyV("MIDDLE")
    local fontItems = TaskTracker.GetLayoutFontChoices and TaskTracker.GetLayoutFontChoices() or {}
    local fontDrop = TaskTracker.MakeDropdown(pane, {
        width = 200,
        buttonHeight = ROW_H,
        rowHeight = ROW_H,
        rowGap = 2,
        items = fontItems,
        disableHover = true,
        quiet = true,
        menuBgKey = "headerBg2",
        getSelected = function()
            if TaskTracker.GetLayoutFontKey then return TaskTracker.GetLayoutFontKey() end
            return "friz"
        end,
        selectedLabel = function(key)
            for i = 1, #fontItems do
                if fontItems[i].key == key then return fontItems[i].label end
            end
            return key
        end,
        onSelect = function(key)
            if not (TaskTracker.GetLayoutPreset and TaskTracker.GetLayoutPreset() == "custom") then
                if SyncFontDropdownLabel then SyncFontDropdownLabel() end
                return
            end
            local db = TaskTrackerDB
            if not db or db.layoutFont == key then return end
            db.layoutFont = key
            if TaskTracker.SaveLayoutCustom then TaskTracker.SaveLayoutCustom() end
            if TaskTracker.RefreshAll then TaskTracker.RefreshAll() end
        end,
    })
    local fontDdBtn = fontDrop.button
    local fontMenu = fontDrop.menu
    local fontMenuOpts = fontDrop.rows
    local SyncFontDropdownLabel = fontDrop.refresh

    local fontShadowToggle = TaskTracker.MakeQuietToggle(pane, "Drop shadow")
    fontShadowToggle:SetScript("OnClick", function()
        if not (TaskTracker.GetLayoutPreset and TaskTracker.GetLayoutPreset() == "custom") then
            fontShadowToggle:SetOn(TaskTracker.GetLayoutFontShadow and TaskTracker.GetLayoutFontShadow())
            return
        end
        local db = TaskTrackerDB
        if not db then return end
        db.fontShadow = not (db.fontShadow == true)
        fontShadowToggle:SetOn(db.fontShadow)
        if TaskTracker.SaveLayoutCustom then TaskTracker.SaveLayoutCustom() end
        if TaskTracker.RefreshAll then TaskTracker.RefreshAll() end
    end)
    fontShadowToggle:SetScript("OnEnter", function()
        GameTooltip:SetOwner(fontShadowToggle, "ANCHOR_RIGHT")
        GameTooltip:SetText("Drop shadow", 1, 1, 1)
        GameTooltip:AddLine("Draws a dark edge around the letters. Off leaves the font plain.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    fontShadowToggle:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    fontShadowToggle:SetOn(TaskTracker.GetLayoutFontShadow and TaskTracker.GetLayoutFontShadow())

    local function addLayoutIntRow(bucket, yOff, labelText, getVal, setVal, minV, maxV, step, getBounds, onCommit)
        local row
        local function onCustom()
            return TaskTracker.GetLayoutPreset and TaskTracker.GetLayoutPreset() == "custom"
        end
        local function setWrapped(n)
            if not onCustom() then return end
            local prev = getVal and getVal() or nil
            if setVal then setVal(n) end
            if prev ~= n and TaskTracker.SaveLayoutCustom then
                TaskTracker.SaveLayoutCustom()
            end
        end
        local function commit(n)
            if not onCustom() then
                if row and row.sync then row.sync() end
                return
            end
            if onCommit then
                onCommit(n)
            else
                RefreshListLayout()
            end
        end
        local nextY
        nextY, row = TaskTracker.MakeQuietSlider(pane, {
            x = PAD, y = yOff, label = (labelText or ""):gsub(":%s*$", ""),
            getVal = getVal, setVal = setWrapped,
            min = minV, max = maxV, step = step or 1,
            getBounds = getBounds,
            rowStride = ROW_STRIDE,
            onCommit = commit,
        })
        table.insert(bucket, row)
        table.insert(allLayoutIntRows, row)
        return nextY, row
    end

    local function commitTitleBar()
        if TaskTracker.ApplyTitleBarMetrics then
            TaskTracker.ApplyTitleBarMetrics()
        end
    end
    local function commitChrome()
        if TaskTracker.RefreshAll then TaskTracker.RefreshAll() end
    end
    local function commitOptionsPanel()
        if TaskTracker.RefreshAll then TaskTracker.RefreshAll() end
    end
    local function addOptionsRow(labelText, getVal, setVal, minV, maxV)
        local _, row = TaskTracker.MakeQuietSlider(pane, {
            x = PAD, y = yBuild, label = labelText,
            getVal = getVal,
            setVal = function(n)
                if TaskTrackerDB and setVal then setVal(n) end
            end,
            min = minV, max = maxV, step = 1,
            rowStride = ROW_STRIDE,
            onCommit = commitOptionsPanel,
        })
        optionsPanelRows[#optionsPanelRows + 1] = row
        yBuild = yBuild + ROW_STRIDE
    end
    addOptionsRow("Font (px)",
        TaskTracker.GetOptionsFontSize,
        function(n) TaskTrackerDB.optionsFontSize = n end,
        8, 24)
    addOptionsRow("Rows (px)",
        TaskTracker.GetOptionsRowHeight,
        function(n) TaskTrackerDB.optionsRowHeight = n end,
        20, 40)
    addOptionsRow("Border (px)",
        TaskTracker.GetOptionsBorderWidth,
        function(n) TaskTrackerDB.optionsBorderWidth = n end,
        1, 3)
    addOptionsRow("Text (px)",
        TaskTracker.GetOptionsTitleFontSize,
        function(n) TaskTrackerDB.optionsTitleFontSize = n end,
        8, 24)
    addOptionsRow("Icons (px)",
        TaskTracker.GetOptionsTitleIconSize,
        function(n) TaskTrackerDB.optionsTitleIconSize = n end,
        12, 28)
    addOptionsRow("Height (px)",
        TaskTracker.GetOptionsTitleHeight,
        function(n) TaskTrackerDB.optionsTitleHeight = n end,
        20, 40)
    addOptionsRow("Margin (px)",
        TaskTracker.GetOptionsTitleMargin,
        function(n) TaskTrackerDB.optionsTitleMargin = n end,
        0, 16)

    yBuild = addLayoutIntRow(chromeRows, yBuild, "Border (px):",
        TaskTracker.GetBorderWidth,
        function(n) TaskTrackerDB.borderWidth = n end,
        1, 3, 1, nil, commitChrome)
    yBuild = addLayoutIntRow(chromeRows, yBuild, "Buttons (px):",
        TaskTracker.GetButtonHeight,
        function(n) TaskTrackerDB.buttonHeight = n end,
        16, 28, 1, nil, commitChrome)
    yBuild = addLayoutIntRow(titleBarRows, yBuild, "Text (px):",
        TaskTracker.GetTitleFontSize,
        function(n) TaskTrackerDB.titleFontSize = n end,
        8, 24, 1, nil, commitTitleBar)
    yBuild = addLayoutIntRow(titleBarRows, yBuild, "Icons (px):",
        TaskTracker.GetTitleIconSize,
        function(n) TaskTrackerDB.titleIconSize = n end,
        12, 28, 1, nil, commitTitleBar)
    yBuild = addLayoutIntRow(titleBarRows, yBuild, "Height (px):",
        TaskTracker.GetTitleBarHeight,
        function(n) TaskTrackerDB.titleHeight = n end,
        20, 40, 1, nil, commitChrome)
    yBuild = addLayoutIntRow(titleBarRows, yBuild, "Margin (px):",
        TaskTracker.GetTitleMargin,
        function(n) TaskTrackerDB.titleMargin = n end,
        0, 16, 1, nil, commitChrome)
    yBuild = addLayoutIntRow(listIntRows, yBuild, "Left padding (px):",
        TaskTracker.GetListPadLeft,
        function(n) TaskTrackerDB.listPadLeft = n end,
        0, 16, 1)
    yBuild = addLayoutIntRow(listIntRows, yBuild, "Right padding (px):",
        TaskTracker.GetListPadRight,
        function(n) TaskTrackerDB.listPadRight = n end,
        0, 12, 1)
    yBuild = addLayoutIntRow(listIntRows, yBuild, "Top padding (px):",
        TaskTracker.GetListPadTop,
        function(n) TaskTrackerDB.listPadTop = n end,
        0, 8, 1)
    yBuild = addLayoutIntRow(listIntRows, yBuild, "Bottom padding (px):",
        TaskTracker.GetListPadBottom,
        function(n) TaskTrackerDB.listPadBottom = n end,
        0, 8, 1)
    yBuild = addLayoutIntRow(listIntRows, yBuild, "Scroll gutter (px):",
        TaskTracker.GetScrollGutter,
        function(n) TaskTrackerDB.scrollGutter = n end,
        0, 12, 1)
    yBuild = addLayoutIntRow(listIntRows, yBuild, "Nest indent (px):",
        function()
            local n = (TaskTrackerDB and tonumber(TaskTrackerDB.indentSize)) or 12
            return math.max(4, math.min(20, math.floor(n)))
        end,
        function(n) TaskTrackerDB.indentSize = n end,
        4, 20, 2)

    yBuild = addLayoutIntRow(headerIntRows, yBuild, "Font (px):",
        TaskTracker.GetHeaderFontSize,
        function(n) TaskTrackerDB.headerFontSize = n end,
        8, 24, 1)
    yBuild = addLayoutIntRow(headerIntRows, yBuild, "Height (px):",
        TaskTracker.GetHeaderHeight,
        function(n) TaskTrackerDB.headerHeight = n end,
        16, 40, 1)
    yBuild = addLayoutIntRow(headerIntRows, yBuild, "Color bar (px):",
        TaskTracker.GetAccentBarWidth,
        function(n) TaskTrackerDB.accentBarWidth = n end,
        1, 6, 1)
    yBuild = addLayoutIntRow(headerIntRows, yBuild, "Title inset (px):",
        TaskTracker.GetHeaderTitleGap,
        function(n) TaskTrackerDB.headerTitleGap = n end,
        0, 12, 1)
    yBuild = addLayoutIntRow(headerIntRows, yBuild, "Gap after header (px):",
        TaskTracker.GetSpacingGroupHeader,
        function(n) TaskTrackerDB.spacingGroupHeader = n end,
        0, 4, 1)
    yBuild = addLayoutIntRow(headerIntRows, yBuild, "Gap after group (px):",
        TaskTracker.GetSpacingGroupSection,
        function(n) TaskTrackerDB.spacingGroupSection = n end,
        0, 8, 1)

    yBuild = addLayoutIntRow(taskIntRows, yBuild, "Font (px):",
        TaskTracker.GetTaskFontSize,
        function(n) TaskTrackerDB.taskFontSize = n end,
        8, 24, 1)
    yBuild = addLayoutIntRow(taskIntRows, yBuild, "Height (px):",
        TaskTracker.GetTaskRowHeight,
        function(n) TaskTrackerDB.rowHeight = n end,
        14, 36, 1)
    yBuild = addLayoutIntRow(taskIntRows, yBuild, "Color bar (px):",
        TaskTracker.GetAutomationBarWidth,
        function(n) TaskTrackerDB.automationBarWidth = n end,
        1, 6, 1)
    yBuild = addLayoutIntRow(taskIntRows, yBuild, "Bar to checkbox (px):",
        TaskTracker.GetCheckGap,
        function(n) TaskTrackerDB.checkGap = n end,
        0, 8, 1)
    yBuild = addLayoutIntRow(taskIntRows, yBuild, "Gap between rows (px):",
        TaskTracker.GetSpacingBetweenTasks,
        function(n) TaskTrackerDB.spacingBetweenTasks = n end,
        0, 8, 1)
    yBuild = addLayoutIntRow(taskIntRows, yBuild, "Checkboxes (%):",
        TaskTracker.GetListCheckboxPercent,
        function(n) TaskTrackerDB.checkboxPercent = n end,
        50, 120, 5)
    yBuild = addLayoutIntRow(taskIntRows, yBuild, "Icons (%):",
        TaskTracker.GetListRowIconPercent,
        function(n)
            TaskTrackerDB.rowIconPercent = n
            TaskTrackerDB.cmdIconPercent = n
        end,
        60, 100, 5)
    yBuild = addLayoutIntRow(taskIntRows, yBuild, "Title to icons (px):",
        TaskTracker.GetLabelToIconGap,
        function(n) TaskTrackerDB.labelToIconGap = n end,
        0, 12, 1)

    yBuild = yBuild + 4

    local hdrNotes = sectionHeader("Popout")
    local peekNormalRows = {}
    local peekHoverRows = {}

    local noteHint = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    noteHint:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yBuild)
    noteHint:SetWidth(520)
    noteHint:SetJustifyH("LEFT")
    if noteHint.SetWordWrap then noteHint:SetWordWrap(true) end
    TaskTracker.SetTextColor(noteHint, "textSecondary")
    noteHint:SetText("Sliders adjust opacity.")

    local peekNormalLbl = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    peekNormalLbl:SetText("Normal")
    peekNormalLbl:SetJustifyH("LEFT")
    TaskTracker.SetTextColor(peekNormalLbl, "textAccent")
    local peekHoverLbl = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    peekHoverLbl:SetText("Mouse Over")
    peekHoverLbl:SetJustifyH("LEFT")
    TaskTracker.SetTextColor(peekHoverLbl, "textAccent")

    local function peekIsCustom()
        return TaskTracker.GetLayoutPreset and TaskTracker.GetLayoutPreset() == "custom"
    end

    local function applyPeekOpacity()
        if TaskTracker.ApplyNotePeekOpacity then
            TaskTracker.ApplyNotePeekOpacity()
        end
    end

    local function addPeekSlider(bucket, label, getVal, setVal)
        local row
        local _, made = TaskTracker.MakeQuietSlider(pane, {
            x = PAD, y = 0, label = label,
            getVal = getVal,
            setVal = function(n)
                if not peekIsCustom() then return end
                setVal(n)
                if TaskTracker.SaveLayoutCustom then TaskTracker.SaveLayoutCustom() end
            end,
            min = 0, max = 100, step = 5,
            rowStride = ROW_STRIDE,
            onCommit = function()
                if not peekIsCustom() then
                    if row and row.sync then row.sync() end
                    return
                end
                applyPeekOpacity()
            end,
        })
        row = made
        bucket[#bucket + 1] = row
        allLayoutIntRows[#allLayoutIntRows + 1] = row
    end

    local function peekSliderPercent(key, fallback, hoverOf)
        local n = TaskTrackerDB and tonumber(TaskTrackerDB[key])
        if n == nil and hoverOf and TaskTrackerDB then
            n = tonumber(TaskTrackerDB[hoverOf])
        end
        if not n then n = fallback end
        return math.max(0, math.min(100, math.floor(n + 0.5)))
    end

    addPeekSlider(peekNormalRows, "Background (%)", function()
        return peekSliderPercent("notePeekBgOpacityPercent", 85)
    end, function(n) TaskTrackerDB.notePeekBgOpacityPercent = n end)

    addPeekSlider(peekNormalRows, "Text (%)", function()
        return peekSliderPercent("notePeekTextOpacityPercent", 100)
    end, function(n) TaskTrackerDB.notePeekTextOpacityPercent = n end)

    addPeekSlider(peekNormalRows, "Close and commands (%)", function()
        return peekSliderPercent("notePeekCmdOpacityPercent", 100)
    end, function(n) TaskTrackerDB.notePeekCmdOpacityPercent = n end)

    addPeekSlider(peekHoverRows, "Background (%)", function()
        return peekSliderPercent("notePeekHoverBgOpacityPercent", 85, "notePeekBgOpacityPercent")
    end, function(n) TaskTrackerDB.notePeekHoverBgOpacityPercent = n end)

    addPeekSlider(peekHoverRows, "Text (%)", function()
        return peekSliderPercent("notePeekHoverTextOpacityPercent", 100, "notePeekTextOpacityPercent")
    end, function(n) TaskTrackerDB.notePeekHoverTextOpacityPercent = n end)

    addPeekSlider(peekHoverRows, "Close and commands (%)", function()
        return peekSliderPercent("notePeekHoverCmdOpacityPercent", 100, "notePeekCmdOpacityPercent")
    end, function(n) TaskTrackerDB.notePeekHoverCmdOpacityPercent = n end)

    local function layoutSliderRows(y0, innerW, bucket)
        local n = #bucket
        if n < 1 then return y0 end
        local cols = (innerW >= 640 and n > 1) and 2 or 1
        local colW = math.floor((innerW - (cols - 1) * COL_GAP) / cols)
        local rows = math.ceil(n / cols)
        for i, row in ipairs(bucket) do
            local col = (i - 1) % cols
            local r = math.floor((i - 1) / cols)
            local x = PAD + col * (colW + COL_GAP)
            local y = y0 + r * ROW_STRIDE
            local host = row.host or row.well
            host:ClearAllPoints()
            host:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -y)
            if host.Layout then
                host:Layout(colW)
            else
                host:SetWidth(colW)
            end
        end
        return y0 + rows * ROW_H + math.max(0, rows - 1) * ROW_GAP
    end

    local function RebuildLayout()
        local sw = scrollFrame:GetWidth()
        if sw < 80 then sw = 400 end
        sw = math.max(280, sw - 16)
        local innerW = sw - 2 * PAD

        local yCur = 10

        yCur = placeSectionHeader(hdrStyle, yCur)

        local labelW = math.min(150, math.floor(innerW * 0.38))
        local dropW = math.max(140, innerW - labelW - 12)
        themeDdLabel:ClearAllPoints()
        themeDdLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yCur)
        themeDdLabel:SetSize(labelW, ROW_H)
        themeDdBtn:ClearAllPoints()
        themeDdBtn:SetSize(dropW, ROW_H)
        themeDdBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD + labelW + 12, -yCur)
        yCur = yCur + ROW_H + ROW_GAP

        customizeBtn:ClearAllPoints()
        customizeBtn:SetSize(120, ROW_H)
        customizeBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yCur)
        deleteThemeBtn:ClearAllPoints()
        deleteThemeBtn:SetSize(120, ROW_H)
        deleteThemeBtn:SetPoint("LEFT", customizeBtn, "RIGHT", 8, 0)
        yCur = yCur + ROW_H + ROW_GAP

        narrowLabel:ClearAllPoints()
        narrowLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yCur)
        narrowLabel:SetSize(labelW, ROW_H)
        overflowSeg:ClearAllPoints()
        overflowSeg:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD + labelW + 12, -yCur)
        overflowSeg:Layout(dropW)
        yCur = yCur + ROW_H + 12

        yCur = placeSectionHeader(hdrIcons, yCur)
        local choiceW = math.max(160, math.floor((innerW - 8) / 2))
        classicChoice:ClearAllPoints()
        classicChoice:SetSize(choiceW, ROW_H)
        classicChoice:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yCur)
        tintChoice:ClearAllPoints()
        tintChoice:SetSize(choiceW, ROW_H)
        tintChoice:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD + choiceW + 8, -yCur)
        paintIconChoices()
        yCur = yCur + ROW_H + 12

        yCur = placeSectionHeader(hdrSizes, yCur)
        yCur = layoutSliderRows(yCur, innerW, { uiRow })
        yCur = yCur + 12

        local copyW = 22
        spacingLabel:ClearAllPoints()
        spacingLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yCur)
        spacingLabel:SetSize(labelW, ROW_H)
        densitySeg:ClearAllPoints()
        densitySeg:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD + labelW + 12, -yCur)
        densitySeg:Layout(math.max(120, dropW - copyW - 4))
        copyBtn:ClearAllPoints()
        copyBtn:SetSize(copyW, ROW_H)
        copyBtn:SetPoint("LEFT", densitySeg, "RIGHT", 4, 0)
        yCur = yCur + ROW_H + ROW_GAP

        fontLabel:ClearAllPoints()
        fontLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yCur)
        fontLabel:SetSize(labelW, ROW_H)
        local shadowW = 132
        local fontW = math.max(100, dropW - shadowW - 8)
        fontDdBtn:ClearAllPoints()
        fontDdBtn:SetSize(fontW, ROW_H)
        fontDdBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD + labelW + 12, -yCur)
        fontShadowToggle:ClearAllPoints()
        fontShadowToggle:SetSize(shadowW, ROW_H)
        fontShadowToggle:SetPoint("LEFT", fontDdBtn, "RIGHT", 8, 0)
        fontShadowToggle:SetOn(TaskTracker.GetLayoutFontShadow and TaskTracker.GetLayoutFontShadow())
        yCur = yCur + ROW_H + 12

        yCur = placeSectionHeader(hdrOptionsPanel, yCur)
        yCur = layoutSliderRows(yCur, innerW, optionsPanelRows)
        yCur = yCur + 12

        yCur = placeSectionHeader(hdrTitleBar, yCur)
        yCur = layoutSliderRows(yCur, innerW, titleBarRows)
        yCur = yCur + 12

        yCur = placeSectionHeader(hdrList, yCur)
        yCur = layoutSliderRows(yCur, innerW, chromeRows)
        yCur = yCur + 12
        yCur = layoutSliderRows(yCur, innerW, listIntRows)
        yCur = yCur + 12

        yCur = placeSectionHeader(hdrHeaders, yCur)
        yCur = layoutSliderRows(yCur, innerW, headerIntRows)
        yCur = yCur + 12

        yCur = placeSectionHeader(hdrTasks, yCur)
        yCur = layoutSliderRows(yCur, innerW, taskIntRows)
        yCur = yCur + 12

        yCur = placeSectionHeader(hdrNotes, yCur)
        noteHint:ClearAllPoints()
        noteHint:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yCur)
        noteHint:SetWidth(innerW)
        local hintH = 16
        if noteHint.GetStringHeight then
            local measured = noteHint:GetStringHeight()
            if measured and measured > 8 then hintH = measured end
        end
        yCur = yCur + hintH + 8

        local function stackPeek(rows, x, y, w)
            for i = 1, #rows do
                local host = rows[i].host or rows[i].well
                host:ClearAllPoints()
                host:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -y)
                if host.Layout then
                    host:Layout(w)
                else
                    host:SetWidth(w)
                end
                y = y + ROW_STRIDE
            end
            return y
        end
        local labelH = 18
        local widePeek = innerW >= 640
        if widePeek then
            local colW = math.floor((innerW - COL_GAP) / 2)
            local xR = PAD + colW + COL_GAP
            peekNormalLbl:ClearAllPoints()
            peekNormalLbl:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yCur)
            peekNormalLbl:SetSize(colW, labelH)
            peekHoverLbl:ClearAllPoints()
            peekHoverLbl:SetPoint("TOPLEFT", pane, "TOPLEFT", xR, -yCur)
            peekHoverLbl:SetSize(colW, labelH)
            local yL = stackPeek(peekNormalRows, PAD, yCur + labelH + 4, colW)
            local yR = stackPeek(peekHoverRows, xR, yCur + labelH + 4, colW)
            yCur = math.max(yL, yR)
        else
            peekNormalLbl:ClearAllPoints()
            peekNormalLbl:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yCur)
            peekNormalLbl:SetSize(innerW, labelH)
            yCur = stackPeek(peekNormalRows, PAD, yCur + labelH + 4, innerW)
            yCur = yCur + 4
            peekHoverLbl:ClearAllPoints()
            peekHoverLbl:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -yCur)
            peekHoverLbl:SetSize(innerW, labelH)
            yCur = stackPeek(peekHoverRows, PAD, yCur + labelH + 4, innerW)
        end
        yCur = yCur + 8

        local h = yCur + 14
        pane:SetSize(sw, h)
        scrollChild:SetSize(sw, h)
        local tw = themeDdBtn:GetWidth()
        themeMenu:SetWidth(tw)
        themeMenu:SetHeight(#themeOrder * (ROW_H + 2) + 8)
        local innerWMenu = math.max(80, tw - 10)
        for _, ob in ipairs(themeMenuOpts) do
            if ob then ob:SetWidth(innerWMenu) end
        end
        local fw = fontDdBtn:GetWidth()
        fontMenu:SetWidth(fw)
        fontMenu:SetHeight(math.max(32, #fontItems * (ROW_H + 2) + 8))
        local fontInner = math.max(80, fw - 10)
        for _, ob in ipairs(fontMenuOpts) do
            if ob then ob:SetWidth(fontInner) end
        end
        if applyPresetVisuals then applyPresetVisuals() end
        if scrollFrame.UpdateScrollBar then
            scrollFrame.UpdateScrollBar()
        end
    end

    content.scrollFrame = scrollFrame
    content.RebuildLayout = RebuildLayout

    local function SyncPeekOpacityFromDB()
        for i = 1, #peekNormalRows do
            if peekNormalRows[i].sync then peekNormalRows[i].sync() end
        end
        for i = 1, #peekHoverRows do
            if peekHoverRows[i].sync then peekHoverRows[i].sync() end
        end
    end

    applyPresetVisuals = function()
        local preset = TaskTracker.GetLayoutPreset and TaskTracker.GetLayoutPreset() or "custom"
        local custom = preset == "custom"
        densitySeg:SetActive(preset)
        for i = 1, #allLayoutIntRows do
            local row = allLayoutIntRows[i]
            if row.host and row.host.SetMuted then
                row.host:SetMuted(not custom)
            end
        end
        TaskTracker.SetTextColor(fontLabel, custom and "textPrimary" or "textDim")
        if SyncFontDropdownLabel then SyncFontDropdownLabel() end
        if fontDdBtn then
            fontDdBtn:EnableMouse(custom)
            if fontDdBtn.label then
                TaskTracker.SetTextColor(fontDdBtn.label, custom and "textPrimary" or "textDim")
            end
        end
        if fontShadowToggle then
            fontShadowToggle:EnableMouse(custom)
            fontShadowToggle:SetOn(TaskTracker.GetLayoutFontShadow and TaskTracker.GetLayoutFontShadow())
            if fontShadowToggle.label then
                TaskTracker.SetTextColor(fontShadowToggle.label, custom and "textPrimary" or "textDim")
            end
        end
        if not custom and fontMenu:IsShown() then
            fontMenu:Hide()
        end
        local peekKey = custom and "textAccent" or "textDim"
        if peekNormalLbl then TaskTracker.SetTextColor(peekNormalLbl, peekKey) end
        if peekHoverLbl then TaskTracker.SetTextColor(peekHoverLbl, peekKey) end
    end
    TaskTracker.RefreshLayoutPresetControls = applyPresetVisuals

    content.OnShow = function()
        SyncUIScaleEditFromDB()
        for _, row in ipairs(allLayoutIntRows) do
            if row.sync then row.sync() end
        end
        for i = 1, #optionsPanelRows do
            if optionsPanelRows[i].sync then optionsPanelRows[i].sync() end
        end
        SyncPeekOpacityFromDB()
        SyncThemeDropdownLabel()
        SyncThemeActionButtons()
        themeMenu:Hide()
        fontMenu:Hide()
        copyMenu:Hide()
        if applyPresetVisuals then applyPresetVisuals() end
        RebuildLayout()
    end

    SyncThemeDropdownLabel()
    RebuildLayout()

    content:SetScript("OnHide", function()
        themeMenu:Hide()
        fontMenu:Hide()
        copyMenu:Hide()
        if TaskTracker.HideKeybindCapture then
            TaskTracker.HideKeybindCapture()
        end
    end)

    return content
end


-- ─────────────────────────────────────
-- Advanced (Sync)
-- ─────────────────────────────────────
local function BuildAdvancedTasksPanel(parent)
    local t  = TaskTracker.GetTheme()

    local content, scrollFrame, scrollChild, pane = TaskTracker.MakeScrollPane(parent, { childWidth = 400 })
    TaskTracker.optionsAdvancedScrollBar = content.scrollBarTrack

    local y = 10

    local advTitle = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    advTitle:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
    TaskTracker.SetTextColor(advTitle, "textAccent")
    advTitle:SetText("Advanced")
    y = y + 20

    local advSep = pane:CreateTexture(nil, "ARTWORK")
    advSep:SetHeight(1)
    advSep:SetPoint("TOPLEFT",  pane, "TOPLEFT",  10, -y)
    advSep:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -10, -y)
    TaskTracker.SetColor(advSep, "border")
    y = y + 8

    local intro = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    intro:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
    intro:SetWidth(520)
    intro:SetJustifyH("LEFT")
    intro:SetJustifyV("TOP")
    if intro.SetWordWrap then intro:SetWordWrap(true) end
    TaskTracker.SetTextColor(intro, "textSecondary")
    intro:SetText("These options are more complex. They can need extra setup, or more steps to use.")
    y = y + 32

    local syncTitle = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    syncTitle:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
    TaskTracker.SetTextColor(syncTitle, "textAccent")
    syncTitle:SetText("Sync")
    y = y + 20

    local syncSep = pane:CreateTexture(nil, "ARTWORK")
    syncSep:SetHeight(1)
    syncSep:SetPoint("TOPLEFT",  pane, "TOPLEFT",  10, -y)
    syncSep:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -10, -y)
    TaskTracker.SetColor(syncSep, "border")
    y = y + 8

    local syncHint = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    syncHint:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
    syncHint:SetWidth(520)
    syncHint:SetJustifyH("LEFT")
    syncHint:SetJustifyV("TOP")
    if syncHint.SetWordWrap then syncHint:SetWordWrap(true) end
    TaskTracker.SetTextColor(syncHint, "textSecondary")
    syncHint:SetText("Send a saved task to a character on another account. They can move it. The count follows yours, and they can't check it off. An update goes out when you log in and when the count changes. Both of you need to be online for that send to land. This starts off. While it is off, the Sync button stays hidden, and no one can send you a new task. A task already shared still follows the owner.")

    local syncBtn = TaskTracker.MakeQuietToggle(pane, "Sync")
    syncBtn:SetWidth(360)

    local function UpdateSyncBtn()
        local on = TaskTracker.IsLiveShareEnabled and TaskTracker.IsLiveShareEnabled()
        syncBtn:SetOn(on and true or false)
    end

    syncBtn:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.liveShareEnabled = not (TaskTracker.IsLiveShareEnabled and TaskTracker.IsLiveShareEnabled())
        UpdateSyncBtn()
        local dlg = TaskTracker.taskDialog
        if dlg and dlg._syncEditDataIcon then
            dlg._syncEditDataIcon()
        end
    end)
    UpdateSyncBtn()

    local syncAllBtn = TaskTracker.MakeQuietToggle(pane, "Sync all button")
    syncAllBtn:SetWidth(360)

    local function UpdateSyncAllBtn()
        local on = TaskTracker.IsLiveShareSyncAllButtonEnabled and TaskTracker.IsLiveShareSyncAllButtonEnabled()
        syncAllBtn:SetOn(on and true or false)
    end

    syncAllBtn:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.liveShareSyncAllButton = not (TaskTracker.IsLiveShareSyncAllButtonEnabled and TaskTracker.IsLiveShareSyncAllButtonEnabled())
        UpdateSyncAllBtn()
        if TaskTracker.ApplyLiveShareToolbarButton then
            TaskTracker.ApplyLiveShareToolbarButton()
        end
    end)
    attachButtonTip(syncAllBtn, "Sync all button",
        "For a share that has fallen behind. Defaults to off. Turn it on and Sync all sits on the tracker title bar. One click sends every shared task again. You both need to be online.")
    UpdateSyncAllBtn()

    local ownerLabel = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    TaskTracker.SetTextColor(ownerLabel, "textPrimary")
    ownerLabel:SetText("Owner name")
    ownerLabel:SetJustifyH("LEFT")
    ownerLabel:SetJustifyV("MIDDLE")

    local ownerDrop = TaskTracker.MakeDropdown(pane, {
        width = 160,
        buttonHeight = OptRow(),
        rowHeight = OptRow(),
        rowGap = 2,
        items = {
            { key = "task", label = "In task" },
            { key = "tooltip", label = "Tooltip" },
            { key = "none", label = "None" },
        },
        disableHover = true,
        quiet = true,
        menuBgKey = "headerBg2",
        getSelected = function()
            if TaskTracker.GetLiveShareOwnerNameMode then
                return TaskTracker.GetLiveShareOwnerNameMode()
            end
            return "task"
        end,
        selectedLabel = function(key)
            if key == "tooltip" then return "Tooltip" end
            if key == "none" then return "None" end
            return "In task"
        end,
        onSelect = function(key)
            if not TaskTrackerDB then return end
            if key ~= "tooltip" and key ~= "none" then key = "task" end
            if TaskTrackerDB.liveShareOwnerName == key then return end
            TaskTrackerDB.liveShareOwnerName = key
            if TaskTracker.MarkListLayoutDirty then
                TaskTracker.MarkListLayoutDirty()
            end
            if TaskTracker.RefreshList then
                TaskTracker.RefreshList()
            end
        end,
    })
    attachButtonTip(ownerDrop.button, "Owner name",
        "You can show the task owner's name on the task or in the tooltip. It defaults to on, with the name on the task. When you share a task, that same spot says who you sent it to. Tooltip moves the name onto the row hover. None hides it.")

    local function blockHeight(fs, width)
        fs:SetWidth(width)
        if fs.SetHeight then fs:SetHeight(0) end
        local h = fs.GetStringHeight and fs:GetStringHeight() or 0
        local text = fs:GetText() or ""
        local per = math.max(24, math.floor(width / 6.2))
        local est = math.max(1, math.ceil(#text / per)) * 14
        if not h or h < 12 or h > est + 14 then
            h = est
        end
        fs:SetHeight(math.ceil(h))
        return math.ceil(h)
    end

    local function RebuildLayout()
        local sw = scrollFrame:GetWidth()
        if sw < 80 then sw = 400 end
        sw = math.max(280, sw - 16)
        local hintW = math.max(200, sw - 20)
        local y = 38
        intro:ClearAllPoints()
        intro:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
        y = y + blockHeight(intro, hintW) + 12
        syncTitle:ClearAllPoints()
        syncTitle:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
        y = y + 20
        syncSep:ClearAllPoints()
        syncSep:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
        syncSep:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -10, -y)
        y = y + 8
        syncHint:ClearAllPoints()
        syncHint:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
        y = y + blockHeight(syncHint, hintW) + 8
        syncBtn:ClearAllPoints()
        syncBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
        syncBtn:SetWidth(hintW)
        local rowH = OptRow()
        y = y + rowH + 8
        syncAllBtn:ClearAllPoints()
        syncAllBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
        syncAllBtn:SetWidth(hintW)
        y = y + rowH + 8
        ownerLabel:ClearAllPoints()
        ownerLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -y)
        ownerLabel:SetSize(math.max(80, hintW - 168), rowH)
        ownerDrop.button:ClearAllPoints()
        ownerDrop.button:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -10, -y)
        ownerDrop.button:SetWidth(160)
        local h = y + rowH + 16
        pane:SetSize(sw, h)
        scrollChild:SetSize(sw, h)
        if scrollFrame.UpdateScrollBar then
            scrollFrame.UpdateScrollBar()
        end
    end

    content.scrollFrame = scrollFrame
    content.RebuildLayout = RebuildLayout

    content.OnShow = function()
        UpdateSyncBtn()
        UpdateSyncAllBtn()
        if ownerDrop.refresh then ownerDrop.refresh() end
        RebuildLayout()
    end

    content:SetScript("OnHide", function()
        ownerDrop.menu:Hide()
    end)

    RebuildLayout()

    return content
end

-- ─────────────────────────────────────
-- Modules: expansion → subsection grid (wide panel)
-- ─────────────────────────────────────
local MODULE_SUB_INDENT   = 16
local MODULE_GRID_GAP     = 10
local MODULE_ROW_H        = 26
local MODULE_TOGGLE_W     = 38
local MODULE_TOGGLE_H     = 18
local MODULE_RESET_W      = 22
local MODULE_MIN_LABEL_W  = 90
local MODULE_MAX_COLS     = 8
local SUBSECTION_HDR_H    = 24

local MIDNIGHT_SUB_ORDER = { "patch_12_1_5", "patch_12_1_0", "patch_12_0_5", "patch_12_0_0" }
local POWER_SUB_ORDER    = { "patch_12_1_5", "patch_12_1_0", "patch_12_0_5", "patch_12_0_0" }
local MIDNIGHT_COLLECTIONS_SUBS = {
    "patch_12_1_0_collections_toys",
    "patch_12_1_0_collections_mounts",
    "patch_12_1_0_collections_pets",
    "patch_12_1_0_collections_currency",
    "patch_12_1_0_collections_reputations",
}
local MIDNIGHT_COLLECTIONS_1200_SUBS = {
    "patch_12_0_0_collections_mounts",
    "patch_12_0_0_collections_pets",
    "patch_12_0_0_collections_currency",
}
local MIDNIGHT_COLLECTIONS_1215_SUBS = {
    "patch_12_1_5_collections_reputations",
}
local MIDNIGHT_COLLECTIONS_UNDER_PATCH = {
    patch_12_1_5 = { headerKey = "patch_12_1_5_collections", subs = MIDNIGHT_COLLECTIONS_1215_SUBS },
    patch_12_1_0 = { headerKey = "patch_12_1_0_collections", subs = MIDNIGHT_COLLECTIONS_SUBS },
    patch_12_0_0 = { headerKey = "patch_12_0_0_collections", subs = MIDNIGHT_COLLECTIONS_1200_SUBS },
}
local SEASONAL_SUB_ORDER = { "general", "vault", "delves", "mplus", "raid" }
local PROFESSIONS_SUB_ORDER = { "_shared" }
for _, k in ipairs(TaskTracker.ProfessionCatalogOrder or {}) do
    PROFESSIONS_SUB_ORDER[#PROFESSIONS_SUB_ORDER + 1] = k
end
local MODULE_SUB_LABELS  = {
    patch_12_0_0       = "Patch 12.0.0",
    patch_12_0_5       = "Patch 12.0.5",
    patch_12_1_5       = "Patch 12.1.5",
    patch_12_1_5_aqir                 = "Aqir Invasions",
    patch_12_1_5_collections          = "Collections",
    patch_12_1_5_collections_reputations = "Reputations",
    patch_12_1_0       = "Patch 12.1.0",
    patch_12_1_0_coiled_isle              = "The Coiled Isle",
    patch_12_1_0_vaults                   = "Vaults of Atal'Utek",
    patch_12_0_0_collections              = "Collections",
    patch_12_0_0_collections_mounts       = "Mounts",
    patch_12_0_0_collections_pets         = "Pets",
    patch_12_0_0_collections_currency     = "Currency",
    patch_12_1_0_collections              = "Collections",
    patch_12_1_0_collections_toys         = "Toys",
    patch_12_1_0_collections_mounts       = "Mounts",
    patch_12_1_0_collections_pets         = "Pets",
    patch_12_1_0_collections_currency     = "Currency",
    patch_12_1_0_collections_reputations  = "Reputations",
    general            = "General",
    delves             = "Delves",
    vault              = "Vault Status",
    mplus              = "Dungeons",
    raid               = "Raids",
    _shared            = "Shared",
    _default           = "Other",
}

local function professionSubsectionLabel(subKey)
    if subKey == "_shared" then
        return MODULE_SUB_LABELS._shared or "Shared"
    end
    local def = TaskTracker.ProfessionCatalog and TaskTracker.ProfessionCatalog[subKey]
    return (def and def.label) or subKey
end

local function groupRegistryBySubsection(entries, collapsePatch1210)
    local groups = {}
    for _, e in ipairs(entries) do
        local sk = e.subsection or "_default"
        if collapsePatch1210 and (sk == "patch_12_1_0_coiled_isle" or sk == "patch_12_1_0_vaults") then
            sk = "patch_12_1_0"
        end
        if collapsePatch1210 and sk == "patch_12_1_5_aqir" then
            sk = "patch_12_1_5"
        end
        groups[sk] = groups[sk] or {}
        table.insert(groups[sk], e)
    end
    return groups
end

local function subsectionKeysForExpansion(expKey, groups)
    if expKey == "power" then
        local out, seen = {}, {}
        for _, k in ipairs(POWER_SUB_ORDER) do
            if groups[k] and #groups[k] > 0 then
                table.insert(out, k)
                seen[k] = true
            end
        end
        for k, list in pairs(groups) do
            if not seen[k] and k ~= "_default" and #list > 0 then
                table.insert(out, k)
            end
        end
        if groups._default and #groups._default > 0 then
            table.insert(out, "_default")
        end
        return out
    end
    if expKey == "midnight" then
        local out, seen = {}, {}
        for _, k in ipairs(MIDNIGHT_SUB_ORDER) do
            if k == "patch_12_1_5" or k == "patch_12_1_0" or (groups[k] and #groups[k] > 0) then
                table.insert(out, k)
                seen[k] = true
            end
        end
        for k, list in pairs(groups) do
            if not seen[k] and k ~= "_default" and #list > 0
                and k ~= "patch_12_1_0_coiled_isle"
                and k ~= "patch_12_1_0_vaults"
                and k ~= "patch_12_1_5_aqir"
                and not (type(k) == "string" and k:find("_collections_", 1, true)) then
                table.insert(out, k)
            end
        end
        if groups._default and #groups._default > 0 then
            table.insert(out, "_default")
        end
        return out
    end
    if expKey == "seasonal" then
        local out, seen = {}, {}
        for _, k in ipairs(SEASONAL_SUB_ORDER) do
            if groups[k] and #groups[k] > 0 then
                table.insert(out, k)
                seen[k] = true
            end
        end
        for k, list in pairs(groups) do
            if not seen[k] and k ~= "_default" and #list > 0 then
                table.insert(out, k)
            end
        end
        if groups._default and #groups._default > 0 then
            table.insert(out, "_default")
        end
        return out
    end
    if expKey == "professions" then
        local out = {}
        for _, k in ipairs(PROFESSIONS_SUB_ORDER) do
            if groups[k] and #groups[k] > 0 then
                table.insert(out, k)
            end
        end
        return out
    end
    local keys = {}
    for k in pairs(groups) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

local function moduleSubExpandKey(expKey, subKey)
    return expKey .. "_" .. subKey
end

local function moduleMinCellW()
    return 4 + MODULE_TOGGLE_W + 6 + MODULE_MIN_LABEL_W + MODULE_RESET_W
end

local function moduleGridCols(innerW, n)
    if not n or n < 1 then return 1 end
    local minCell = moduleMinCellW()
    local cols = math.floor((innerW + MODULE_GRID_GAP) / (minCell + MODULE_GRID_GAP))
    if cols < 1 then cols = 1 end
    if cols > MODULE_MAX_COLS then cols = MODULE_MAX_COLS end
    if cols > n then cols = n end
    return cols
end

local function moduleLabelColW(cellW)
    return math.max(20, cellW - 4 - MODULE_TOGGLE_W - 6 - MODULE_RESET_W)
end

local function BuildAutoTrackedTab(parent)
    local content, scrollFrame, scrollChild = TaskTracker.MakeScrollPane(parent, { childWidth = 800, pane = false })
    TaskTracker.optionsScrollBarTrack = content.scrollBarTrack

    local expHeaderPool, subHeaderPool, cellPool = {}, {}, {}
    local expUsed, subUsed, cellUsed = 0, 0, 0
    local autoListDirty = true

    local tMode = TaskTracker.GetTheme()
    local modeBar = CreateFrame("Frame", nil, scrollChild)
    local modeLbl = TaskTracker.CreateFontString(modeBar, nil, "OVERLAY", tMode.fontNormal or "GameFontNormalSmall")
    modeLbl:SetPoint("LEFT", modeBar, "LEFT", 8, 0)
    TaskTracker.SetTextColor(modeLbl, "textSecondary")
    modeLbl:SetText("Patch list grouping:")
    local modeBtn1 = MakePatchListGroupModeButtons(modeBar)
    modeBtn1:SetPoint("LEFT", modeLbl, "RIGHT", 10, 0)

    local measureFS
    local function measureTwoLineLabel(text, width)
        if width < 8 then return 12 end
        if not measureFS then
            local tm = TaskTracker.GetTheme()
            measureFS = TaskTracker.CreateFontString(scrollChild, nil, "OVERLAY", tm.fontNormal or "GameFontNormalSmall")
            measureFS:Hide()
            if measureFS.SetWordWrap then measureFS:SetWordWrap(true) end
            if measureFS.SetNonSpaceWrap then measureFS:SetNonSpaceWrap(true) end
            if measureFS.SetMaxLines then measureFS:SetMaxLines(2) end
        end
        measureFS:SetWidth(width)
        measureFS:SetText(text or "")
        local h = measureFS:GetStringHeight() or 12
        if h < 12 then h = 12 end
        if h > 32 then h = 32 end
        return math.ceil(h)
    end

    local function hidePoolTail(pool, used)
        for i = used + 1, #pool do
            pool[i]:Hide()
        end
    end

    local function acquireExpHeader()
        expUsed = expUsed + 1
        local f = expHeaderPool[expUsed]
        if f then
            f:SetParent(scrollChild)
            f:ClearAllPoints()
            f:Show()
            return f
        end
        local t = TaskTracker.GetTheme()
        f = CreateFrame("Button", nil, scrollChild)
        local expBg = f:CreateTexture(nil, "BACKGROUND")
        expBg:SetAllPoints()
        f._ttBg = expBg
        TaskTracker.MakeEdge(f, "BOTTOM", "border")
        TaskTracker.MakeAccentBar(f)
        local expArrow = f:CreateTexture(nil, "OVERLAY")
        expArrow:SetSize(12, 12)
        expArrow:SetPoint("LEFT", f, "LEFT", (t.accentBarWidth or 3) + 8, 0)
        f._ttArrow = expArrow
        local expLbl = TaskTracker.CreateFontString(f, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
        expLbl:SetPoint("LEFT", expArrow, "RIGHT", 6, 0)
        expLbl:SetJustifyH("LEFT")
        f._ttLbl = expLbl
        local expBulk = TaskTracker.MakeQuietAction(f, "Enable all", 96, 22)
        expBulk:SetScript("OnEnter", nil)
        expBulk:SetScript("OnLeave", nil)
        expBulk:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        f._ttBulk = expBulk
        local detBtn = TaskTracker.MakeQuietAction(f, "Details", 64, 22)
        detBtn:SetPoint("RIGHT", expBulk, "LEFT", -6, 0)
        detBtn:SetScript("OnEnter", nil)
        detBtn:SetScript("OnLeave", nil)
        detBtn:SetScript("OnClick", function()
            if TaskTracker.OpenPowerModuleOverview then
                TaskTracker.OpenPowerModuleOverview()
            end
        end)
        f._ttDetails = detBtn
        expHeaderPool[expUsed] = f
        return f
    end

    local function acquireSubHeader()
        subUsed = subUsed + 1
        local f = subHeaderPool[subUsed]
        if f then
            f:SetParent(scrollChild)
            f:ClearAllPoints()
            f:Show()
            return f
        end
        local t = TaskTracker.GetTheme()
        f = CreateFrame("Button", nil, scrollChild)
        local subBg = f:CreateTexture(nil, "BACKGROUND")
        subBg:SetAllPoints()
        f._ttBg = subBg
        TaskTracker.MakeEdge(f, "BOTTOM", "border")
        local subArrow = f:CreateTexture(nil, "OVERLAY")
        subArrow:SetSize(12, 12)
        subArrow:SetPoint("LEFT", f, "LEFT", 8, 0)
        f._ttArrow = subArrow
        local subLbl = TaskTracker.CreateFontString(f, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
        subLbl:SetPoint("LEFT", subArrow, "RIGHT", 6, 0)
        subLbl:SetJustifyH("LEFT")
        f._ttLbl = subLbl
        local subBulk = TaskTracker.MakeQuietAction(f, "Enable all", 96, 22)
        subBulk:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        subBulk:SetScript("OnEnter", nil)
        subBulk:SetScript("OnLeave", nil)
        f._ttBulk = subBulk
        subHeaderPool[subUsed] = f
        return f
    end

    local function acquireRegistryCell()
        cellUsed = cellUsed + 1
        local row = cellPool[cellUsed]
        if row then
            row:SetParent(scrollChild)
            row:ClearAllPoints()
            row:Show()
            return row
        end
        local t = TaskTracker.GetTheme()
        row = CreateFrame("Frame", nil, scrollChild)
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        row._ttBg = rowBg
        TaskTracker.MakeEdge(row, "BOTTOM", "border")
        local toggleBtn = TaskTracker.MakeButton(row, "OFF", MODULE_TOGGLE_W, MODULE_TOGGLE_H)
        toggleBtn:SetPoint("LEFT", row, "LEFT", 4, 0)
        toggleBtn:SetScript("OnEnter", nil)
        toggleBtn:SetScript("OnLeave", nil)
        row._ttToggle = toggleBtn
        local entryLbl = TaskTracker.CreateFontString(row, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
        entryLbl:SetPoint("LEFT", toggleBtn, "RIGHT", 6, 0)
        entryLbl:SetPoint("RIGHT", row, "RIGHT", -28, 0)
        entryLbl:SetJustifyH("LEFT")
        entryLbl:SetJustifyV("MIDDLE")
        if entryLbl.SetWordWrap then entryLbl:SetWordWrap(true) end
        if entryLbl.SetNonSpaceWrap then entryLbl:SetNonSpaceWrap(true) end
        if entryLbl.SetMaxLines then entryLbl:SetMaxLines(2) end
        row._ttLbl = entryLbl
        local resetTag = TaskTracker.CreateFontString(row, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
        resetTag:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row._ttReset = resetTag
        cellPool[cellUsed] = row
        return row
    end

    local function bindRegistryCell(row, yFromTop, x, cellW, cellH, entry, expansionKeyForToggle)
        local isPowerOpts = expansionKeyForToggle == "power"
        local enabled
        if isPowerOpts then
            enabled = TaskTracker.IsPowerListEntryEnabled(entry.id)
        else
            enabled = TaskTracker.IsEntryEnabled(entry.id)
        end

        row:SetSize(cellW, cellH or MODULE_ROW_H)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, -yFromTop)
        TaskTracker.SetColor(row._ttBg, "rowOdd")

        local toggleBtn = row._ttToggle
        toggleBtn:SetSize(MODULE_TOGGLE_W, MODULE_TOGGLE_H)
        local complete = TaskTracker.IsCollectionsModuleEntryComplete
            and TaskTracker.IsCollectionsModuleEntryComplete(entry)
        local showCollected = complete and TaskTracker.IsCollectionsShowCollectedOverride
            and TaskTracker.IsCollectionsShowCollectedOverride(entry.id)
        local listed = enabled and (not complete or showCollected)
        if complete and not showCollected then
            TaskTracker.PaintQuietSwitch(toggleBtn, false, "Have")
        else
            TaskTracker.PaintQuietSwitch(toggleBtn, listed)
        end
        local capturedEntry = entry
        local capturedExpToggle = expansionKeyForToggle
        toggleBtn:SetScript("OnClick", function()
            if capturedExpToggle == "power" then
                local cur = TaskTracker.IsPowerListEntryEnabled(capturedEntry.id)
                TaskTracker.SetPowerListEntryEnabled(capturedEntry.id, not cur)
            elseif TaskTracker.IsCollectionsModuleEntryComplete
                and TaskTracker.IsCollectionsModuleEntryComplete(capturedEntry) then
                local curShow = TaskTracker.IsCollectionsShowCollectedOverride
                    and TaskTracker.IsCollectionsShowCollectedOverride(capturedEntry.id)
                if TaskTracker.SetCollectionsShowCollectedOverride then
                    TaskTracker.SetCollectionsShowCollectedOverride(capturedEntry.id, not curShow)
                end
                if not curShow then
                    TaskTracker.SetEntryEnabled(capturedEntry.id, true)
                else
                    if TaskTracker.MarkListLayoutDirty then
                        TaskTracker.MarkListLayoutDirty()
                    end
                    if TaskTracker.RefreshList then
                        TaskTracker.RefreshList()
                    end
                end
            else
                local cur = TaskTracker.IsEntryEnabled(capturedEntry.id)
                TaskTracker.SetEntryEnabled(capturedEntry.id, not cur)
            end
            content.Rebuild()
        end)

        row._ttLbl:SetText(entry.label or "")
        if listed then
            TaskTracker.SetTextColor(row._ttLbl, "textPrimary")
        else
            TaskTracker.SetTextColor(row._ttLbl, "textDim")
        end
        if entry.reset == "daily" then
            row._ttReset:SetText(TaskTracker.WrapColor("[D]", "textSecondary"))
        elseif entry.reset == "weekly" then
            row._ttReset:SetText(TaskTracker.WrapColor("[W]", "textSecondary"))
        else
            row._ttReset:SetText("")
        end
    end

    local function RebuildAutoList()
        if not content:IsShown() then
            autoListDirty = true
            return
        end

        local db = TaskTrackerDB
        if not db then return end
        expUsed, subUsed, cellUsed = 0, 0, 0

        local yOff = 0
        local sw   = scrollFrame:GetWidth()
        if sw < 80 then sw = OPTS_WIDTH end
        local rowW = math.floor(sw - 16)

        modeBar:ClearAllPoints()
        modeBar:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        modeBar:SetSize(rowW, 36)
        modeBar:Show()
        if modeBtn1 and modeBtn1.Layout then
            local lw = modeLbl:GetStringWidth() or 140
            modeBtn1:Layout(math.max(220, rowW - lw - 28))
        end
        yOff = 42

        for _, expKey in ipairs(TaskTracker.ExpansionOrder) do
            local expEntries = TaskTracker.GetEntriesForExpansion(expKey)
            if expKey == "power" then
                local filtered = {}
                for _, e in ipairs(expEntries) do
                    if not e.hideFromPowerOptions then
                        filtered[#filtered + 1] = e
                    end
                end
                expEntries = filtered
            end
            if #expEntries > 0 then
                local expLabel    = TaskTracker.ExpansionLabels[expKey] or expKey
                local expExpanded = db.optionsExpanded[expKey]
                if expExpanded == nil then expExpanded = true end

                local expHeader = acquireExpHeader()
                expHeader:SetSize(rowW, HDR_HEIGHT)
                expHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOff)
                TaskTracker.SetColor(expHeader._ttBg, "headerBg")
                TaskTracker.ApplyTwistIcon(expHeader._ttArrow, expExpanded)
                TaskTracker.SetTextColor(expHeader._ttLbl, "textHeader")
                expHeader._ttLbl:SetText(expLabel)

                local expAllOn = TaskTracker.AreAllRegistryEntriesEnabledForExpansion(expKey)
                local expBulk = expHeader._ttBulk
                expBulk:SetLabel(expAllOn and "Disable all" or "Enable all")
                local detBtn = expHeader._ttDetails
                if expKey == "power" and TaskTracker.OpenPowerModuleOverview then
                    detBtn:Show()
                    expHeader._ttLbl:SetPoint("RIGHT", detBtn, "LEFT", -8, 0)
                else
                    detBtn:Hide()
                    expHeader._ttLbl:SetPoint("RIGHT", expBulk, "LEFT", -8, 0)
                end

                local capturedExpKey = expKey
                expBulk:SetScript("OnClick", function()
                    local on = TaskTracker.AreAllRegistryEntriesEnabledForExpansion(capturedExpKey)
                    TaskTracker.SetAllRegistryEntriesForExpansion(capturedExpKey, not on)
                    content.Rebuild()
                end)

                expHeader:SetScript("OnClick", function()
                    db.optionsExpanded[capturedExpKey] = not db.optionsExpanded[capturedExpKey]
                    RebuildAutoList()
                end)

                yOff = yOff + HDR_HEIGHT + 2

                if expExpanded then
                    local bySub = groupRegistryBySubsection(expEntries, expKey == "power")
                    local subKeys = subsectionKeysForExpansion(expKey, bySub)

                    local function renderSubBlock(subKey, list, indent, bgKey, allowEmpty, opt)
                        opt = opt or {}
                        list = list or {}
                        if #list == 0 and not allowEmpty then return false end
                        local expandK = opt.expandKey or moduleSubExpandKey(expKey, subKey)
                        local showSubHeader = (subKey ~= "_default")
                        local subExpanded = true
                        if showSubHeader then
                            subExpanded = db.optionsExpanded[expandK]
                            if subExpanded == nil then subExpanded = true end

                            local subHeader = acquireSubHeader()
                            subHeader:SetSize(rowW - indent, SUBSECTION_HDR_H)
                            subHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", indent, -yOff)
                            TaskTracker.SetColor(subHeader._ttBg, bgKey or "headerBg2")
                            TaskTracker.ApplyTwistIcon(subHeader._ttArrow, subExpanded)
                            TaskTracker.SetTextColor(subHeader._ttLbl, "textHeader")
                            subHeader._ttLbl:SetText(
                                opt.label
                                or (expKey == "professions" and professionSubsectionLabel(subKey))
                                or MODULE_SUB_LABELS[subKey]
                                or subKey)

                            local subAllOn
                            if opt.getAllOn then
                                subAllOn = opt.getAllOn()
                            else
                                subAllOn = TaskTracker.AreAllRegistryEntriesEnabledForSubsection(expKey, subKey)
                            end
                            local subBulk = subHeader._ttBulk
                            subBulk:SetLabel(subAllOn and "Disable all" or "Enable all")
                            subHeader._ttLbl:SetPoint("RIGHT", subBulk, "LEFT", -8, 0)

                            local capturedExpandK = expandK
                            subHeader:SetScript("OnClick", function()
                                local cur = db.optionsExpanded[capturedExpandK]
                                db.optionsExpanded[capturedExpandK] = not cur
                                RebuildAutoList()
                            end)

                            local capturedOpt = opt
                            local capturedSubKey = subKey
                            subBulk:SetScript("OnClick", function()
                                if capturedOpt.setAll then
                                    local on = capturedOpt.getAllOn and capturedOpt.getAllOn() or false
                                    capturedOpt.setAll(not on)
                                else
                                    local on = TaskTracker.AreAllRegistryEntriesEnabledForSubsection(capturedExpKey, capturedSubKey)
                                    TaskTracker.SetAllRegistryEntriesForSubsection(capturedExpKey, capturedSubKey, not on)
                                end
                                content.Rebuild()
                            end)

                            yOff = yOff + SUBSECTION_HDR_H + 2
                        end

                        if subExpanded then
                            local innerW = rowW - indent - MODULE_SUB_INDENT
                            if innerW < 80 then innerW = 80 end
                            local n      = #list
                            local cols   = moduleGridCols(innerW, n)
                            local cellW  = math.floor((innerW - (cols - 1) * MODULE_GRID_GAP) / cols)
                            if cellW < 1 then cellW = 1 end
                            local labelW = moduleLabelColW(cellW)
                            local rowHs, rowY = {}, {}
                            local nRows = (n > 0) and math.ceil(n / cols) or 0
                            for idx = 1, n do
                                local row0 = math.floor((idx - 1) / cols)
                                local lh = measureTwoLineLabel(list[idx] and list[idx].label, labelW)
                                local ch = math.max(MODULE_ROW_H, MODULE_TOGGLE_H + 8, lh + 8)
                                if not rowHs[row0] or ch > rowHs[row0] then
                                    rowHs[row0] = ch
                                end
                            end
                            local acc = 0
                            for r = 0, nRows - 1 do
                                rowY[r] = acc
                                acc = acc + (rowHs[r] or MODULE_ROW_H) + 6
                            end
                            local baseY  = yOff
                            local cellX  = indent

                            for idx = 1, n do
                                local entry = list[idx]
                                local col0  = (idx - 1) % cols
                                local row0  = math.floor((idx - 1) / cols)
                                local x     = cellX + col0 * (cellW + MODULE_GRID_GAP)
                                local cellY = baseY + (rowY[row0] or 0)
                                bindRegistryCell(
                                    acquireRegistryCell(), cellY, x, cellW, rowHs[row0] or MODULE_ROW_H, entry, expKey)
                            end

                            yOff = baseY + acc
                        end

                        yOff = yOff + 6
                        return subExpanded
                    end

                    local function renderCollectionsUnderPatch(patchKey)
                        if expKey ~= "midnight" then return end
                        local cfg = MIDNIGHT_COLLECTIONS_UNDER_PATCH[patchKey]
                        if not cfg then return end
                        local subs = cfg.subs
                        local any = false
                        for i = 1, #subs do
                            local sk = subs[i]
                            local list = bySub[sk]
                            if list and #list > 0 then
                                any = true
                                break
                            end
                        end
                        if not any then return end

                        local collIndent = MODULE_SUB_INDENT * 2
                        local expandK = moduleSubExpandKey(expKey, cfg.headerKey)
                        local collExpanded = db.optionsExpanded[expandK]
                        if collExpanded == nil then collExpanded = true end

                        local collHeader = acquireSubHeader()
                        collHeader:SetSize(rowW - collIndent, SUBSECTION_HDR_H)
                        collHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", collIndent, -yOff)
                        TaskTracker.SetColor(collHeader._ttBg, "headerBg3")
                        TaskTracker.ApplyTwistIcon(collHeader._ttArrow, collExpanded)
                        TaskTracker.SetTextColor(collHeader._ttLbl, "textHeader")
                        collHeader._ttLbl:SetText(MODULE_SUB_LABELS[cfg.headerKey] or "Collections")

                        local allOn = true
                        for i = 1, #subs do
                            local sk = subs[i]
                            if bySub[sk] and #bySub[sk] > 0
                                and not TaskTracker.AreAllRegistryEntriesEnabledForSubsection(expKey, sk) then
                                allOn = false
                                break
                            end
                        end
                        local collBulk = collHeader._ttBulk
                        collBulk:SetLabel(allOn and "Disable all" or "Enable all")
                        collHeader._ttLbl:SetPoint("RIGHT", collBulk, "LEFT", -8, 0)
                        collHeader:SetScript("OnClick", function()
                            local cur = db.optionsExpanded[expandK]
                            db.optionsExpanded[expandK] = not cur
                            RebuildAutoList()
                        end)
                        collBulk:SetScript("OnClick", function()
                            local on = true
                            for i = 1, #subs do
                                local sk = subs[i]
                                if bySub[sk] and #bySub[sk] > 0
                                    and not TaskTracker.AreAllRegistryEntriesEnabledForSubsection(capturedExpKey, sk) then
                                    on = false
                                    break
                                end
                            end
                            for i = 1, #subs do
                                TaskTracker.SetAllRegistryEntriesForSubsection(
                                    capturedExpKey, subs[i], not on)
                            end
                            content.Rebuild()
                        end)

                        yOff = yOff + SUBSECTION_HDR_H + 2
                        if collExpanded then
                            local catIndent = MODULE_SUB_INDENT * 3
                            for i = 1, #subs do
                                local sk = subs[i]
                                renderSubBlock(sk, bySub[sk], catIndent, "headerBg3")
                            end
                        end
                        yOff = yOff + 6
                    end

                    local function listZoneLabel(zoneKey)
                        local z = TaskTracker.ListZones and TaskTracker.ListZones[zoneKey]
                        return (z and z.label) or zoneKey
                    end

                    local function renderListZoneBlock(zone, patchKey, indent)
                        local zoneKey = zone.zoneKey
                        local expandK = "listzone_" .. tostring(patchKey or "all") .. "_" .. zoneKey
                        local hasKids = zone.subzones and #zone.subzones > 0
                        local childOpt = hasKids and { includeChildZones = true } or nil
                        local zoneOpt = {
                            label = listZoneLabel(zoneKey),
                            expandKey = expandK,
                            getAllOn = function()
                                return TaskTracker.AreAllRegistryEntriesEnabledForListZone(zoneKey, patchKey, childOpt)
                            end,
                            setAll = function(on)
                                TaskTracker.SetAllRegistryEntriesForListZone(zoneKey, patchKey, on, childOpt)
                            end,
                        }
                        local expanded = renderSubBlock("listzone_" .. zoneKey, zone.activities, indent, "headerBg2", true, zoneOpt)
                        if not expanded then return end

                        local catOrder = TaskTracker.CollectionCategoryOrder or {}
                        local hasColl = false
                        for i = 1, #catOrder do
                            local list = zone.collections and zone.collections[catOrder[i]]
                            if list and #list > 0 then
                                hasColl = true
                                break
                            end
                        end
                        if hasColl then
                            local collIndent = indent + MODULE_SUB_INDENT
                            local collExpandK = expandK .. "_collections"
                            local collOpt = {
                                label = "Collections",
                                expandKey = collExpandK,
                                getAllOn = function()
                                    return TaskTracker.AreAllRegistryEntriesEnabledForListZone(zoneKey, patchKey, { collectionsOnly = true })
                                end,
                                setAll = function(on)
                                    TaskTracker.SetAllRegistryEntriesForListZone(zoneKey, patchKey, on, { collectionsOnly = true })
                                end,
                            }
                            local collExpanded = renderSubBlock(collExpandK, {}, collIndent, "headerBg3", true, collOpt)
                            if collExpanded then
                                local catIndent = collIndent + MODULE_SUB_INDENT
                                local labels = TaskTracker.CollectionCategoryLabels or {}
                                for i = 1, #catOrder do
                                    local cat = catOrder[i]
                                    local list = zone.collections and zone.collections[cat]
                                    if list and #list > 0 then
                                        renderSubBlock("listzone_cat_" .. cat, list, catIndent, "headerBg3", false, {
                                            label = labels[cat] or cat,
                                            expandKey = expandK .. "_cat_" .. cat,
                                            getAllOn = function()
                                                return TaskTracker.AreAllRegistryEntriesEnabledForListZone(
                                                    zoneKey, patchKey, { collectionCategory = cat })
                                            end,
                                            setAll = function(on)
                                                TaskTracker.SetAllRegistryEntriesForListZone(
                                                    zoneKey, patchKey, on, { collectionCategory = cat })
                                            end,
                                        })
                                    end
                                end
                            end
                        end

                        for zi = 1, #(zone.subzones or {}) do
                            renderListZoneBlock(zone.subzones[zi], patchKey, indent + MODULE_SUB_INDENT)
                        end
                    end

                    local midnightMode = (expKey == "midnight") and currentPatchListGroupMode() or "patch"
                    if midnightMode ~= "patch" and TaskTracker.GetMidnightModuleLayout then
                        local layout = TaskTracker.GetMidnightModuleLayout(midnightMode)
                        if layout.kind == "zone" then
                            for zi = 1, #(layout.zones or {}) do
                                renderListZoneBlock(layout.zones[zi], nil, MODULE_SUB_INDENT)
                            end
                        elseif layout.kind == "patch_zone" then
                            for pi = 1, #(layout.patches or {}) do
                                local patch = layout.patches[pi]
                                local patchOpt = {
                                    label = patch.label,
                                    expandKey = moduleSubExpandKey(expKey, patch.patchKey .. "_view"),
                                    getAllOn = function()
                                        return TaskTracker.AreAllRegistryEntriesEnabledForListZone(
                                            nil, patch.patchKey, { activitiesOnly = true })
                                    end,
                                    setAll = function(on)
                                        TaskTracker.SetAllRegistryEntriesForListZone(
                                            nil, patch.patchKey, on, { activitiesOnly = true })
                                    end,
                                }
                                local expanded = renderSubBlock(patch.patchKey, {}, MODULE_SUB_INDENT, "headerBg2", true, patchOpt)
                                if expanded then
                                    for zi = 1, #(patch.zones or {}) do
                                        renderListZoneBlock(patch.zones[zi], patch.patchKey, MODULE_SUB_INDENT * 2)
                                    end
                                end
                            end
                        end
                    else
                        for _, subKey in ipairs(subKeys) do
                            local list = bySub[subKey] or {}
                            local allowEmpty = (expKey == "midnight" and (subKey == "patch_12_1_5" or subKey == "patch_12_1_0"))
                            if #list > 0 or allowEmpty then
                                local expanded = renderSubBlock(subKey, list, MODULE_SUB_INDENT, "headerBg2", allowEmpty)
                                if expanded then
                                    if expKey == "midnight" and subKey == "patch_12_1_5" then
                                        renderSubBlock(
                                            "patch_12_1_5_aqir",
                                            bySub.patch_12_1_5_aqir,
                                            MODULE_SUB_INDENT * 2,
                                            "headerBg2")
                                    end
                                    if expKey == "midnight" and subKey == "patch_12_1_0" then
                                        local vaultsList = bySub.patch_12_1_0_vaults
                                        local coiledAllow = vaultsList and #vaultsList > 0
                                        local coiledExp = renderSubBlock(
                                            "patch_12_1_0_coiled_isle",
                                            bySub.patch_12_1_0_coiled_isle,
                                            MODULE_SUB_INDENT * 2,
                                            "headerBg2",
                                            coiledAllow)
                                        if coiledExp then
                                            renderSubBlock(
                                                "patch_12_1_0_vaults",
                                                vaultsList,
                                                MODULE_SUB_INDENT * 3,
                                                "headerBg2")
                                        end
                                    end
                                    renderCollectionsUnderPatch(subKey)
                                end
                            end
                        end
                    end
                end

                yOff = yOff + 4
            end
        end

        hidePoolTail(expHeaderPool, expUsed)
        hidePoolTail(subHeaderPool, subUsed)
        hidePoolTail(cellPool, cellUsed)

        scrollChild:SetSize(rowW, math.max(1, yOff))

        if scrollFrame.UpdateScrollBar then
            scrollFrame.UpdateScrollBar()
        end
        autoListDirty = false
    end

    content.Rebuild = RebuildAutoList
    TaskTracker.RefreshOptionsModulesList = function()
        if content.Rebuild then
            content.Rebuild()
        end
    end
    content.OnShow = function()
        if autoListDirty then
            RebuildAutoList()
        end
    end

    return content
end

-- ─────────────────────────────────────
-- Characters (roster, last seen, tooltip opt-in)
-- ─────────────────────────────────────
local function BuildCharactersPanel(parent)
    local t = TaskTracker.GetTheme()

    local content, scrollFrame, scrollChild, pane = TaskTracker.MakeScrollPane(parent, { childWidth = 400 })
    TaskTracker.optionsCharactersScrollBar = content.scrollBarTrack

    local title = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    title:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -10)
    TaskTracker.SetTextColor(title, "textAccent")
    title:SetText("Characters")

    local sep = pane:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -30)
    sep:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -10, -30)
    TaskTracker.SetColor(sep, "border")

    local currencyTotalBtn = TaskTracker.MakeQuietToggle(pane, "Currency total")
    currencyTotalBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -42)
    currencyTotalBtn:SetWidth(240)
    local highestRepBtn = TaskTracker.MakeQuietToggle(pane, "Highest reputation")
    highestRepBtn:SetPoint("LEFT", currencyTotalBtn, "RIGHT", 16, 0)
    highestRepBtn:SetWidth(240)

    local function UpdateAlwaysBtns()
        local db = TaskTrackerDB
        local totOn = not db or db.charTooltipAlwaysCurrencyTotal ~= false
        currencyTotalBtn:SetOn(totOn)
        local hiOn = not db or db.charTooltipAlwaysHighestRep ~= false
        highestRepBtn:SetOn(hiOn)
    end

    currencyTotalBtn:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.charTooltipAlwaysCurrencyTotal = not (TaskTrackerDB.charTooltipAlwaysCurrencyTotal ~= false)
        UpdateAlwaysBtns()
    end)
    highestRepBtn:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.charTooltipAlwaysHighestRep = not (TaskTrackerDB.charTooltipAlwaysHighestRep ~= false)
        UpdateAlwaysBtns()
    end)
    UpdateAlwaysBtns()

    local hint = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -72)
    hint:SetJustifyH("LEFT")
    if hint.SetWordWrap then hint:SetWordWrap(true) end
    TaskTracker.SetTextColor(hint, "textSecondary")
    hint:SetText("Alts appear after they log in with Task Tracker. Currency total adds an account sum on currency/gold hovers even if no character has Tooltip on. Highest reputation names the top standing on reputation hovers even if that alt’s Tooltip is off. Warband reputations (Zul’jarra’s Forces, Captain Tokka) are shared — every character shows the same rank. Remove drops that character’s stored progress from this list; log in on them again to add them back.")

    local empty = TaskTracker.CreateFontString(pane, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    empty:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -150)
    empty:SetJustifyH("LEFT")
    TaskTracker.SetTextColor(empty, "textSecondary")
    empty:SetText("No characters yet.")
    empty:Hide()

    local rows = {}
    local ROW_H = 58
    local listTop = 178
    local RebuildList, RebuildLayout

    local function ensureRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, pane)
        row:SetHeight(ROW_H)

        local nameFS = TaskTracker.CreateFontString(row, nil, "OVERLAY", t.fontBold or "GameFontNormal")
        nameFS:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        nameFS:SetJustifyH("LEFT")
        row.nameFS = nameFS

        local tipBtn = TaskTracker.MakeQuietToggle(row, "Tooltip")
        tipBtn:SetSize(120, 28)
        tipBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 2)
        row.tipBtn = tipBtn

        local removeBtn = TaskTracker.MakeQuietAction(row, "Remove", 72, 28)
        removeBtn:SetPoint("RIGHT", tipBtn, "LEFT", -8, 0)
        row.removeBtn = removeBtn

        local detailFS = TaskTracker.CreateFontString(row, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
        detailFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -6)
        detailFS:SetPoint("RIGHT", removeBtn, "LEFT", -8, 0)
        detailFS:SetJustifyH("LEFT")
        TaskTracker.SetTextColor(detailFS, "textSecondary")
        row.detailFS = detailFS

        local rule = row:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        TaskTracker.SetColor(rule, "border")
        rule:SetAlpha(0.45)
        row.rule = rule

        rows[i] = row
        return row
    end

    local function bindRow(row, charKey)
        row.charKey = charKey
        local name = TaskTracker.GetCharDisplayName and TaskTracker.GetCharDisplayName(charKey) or charKey
        local current = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
        if charKey == current then
            name = name .. "  (this character)"
        end
        row.nameFS:SetText(name)
        local r, g, b = 1, 1, 1
        if TaskTracker.GetCharClassColor then
            r, g, b = TaskTracker.GetCharClassColor(charKey)
        end
        row.nameFS:SetTextColor(r, g, b)

        local realm = TaskTracker.GetCharDisplayRealm and TaskTracker.GetCharDisplayRealm(charKey) or ""
        local seen = TaskTracker.FormatCharLastSeen and TaskTracker.FormatCharLastSeen(charKey) or "never"
        local done, total = 0, 0
        if TaskTracker.GetCharTaskCounts then
            done, total = TaskTracker.GetCharTaskCounts(charKey)
        end
        local detail = seen .. "  ·  " .. tostring(done) .. "/" .. tostring(total) .. " tasks"
        if realm ~= "" then
            detail = realm .. "  ·  " .. detail
        end
        row.detailFS:SetText(detail)

        local on = TaskTracker.IsCharTooltipEnabled and TaskTracker.IsCharTooltipEnabled(charKey)
        row.tipBtn:SetOn(on)

        row.tipBtn:SetScript("OnClick", function()
            local nextOn = not (TaskTracker.IsCharTooltipEnabled and TaskTracker.IsCharTooltipEnabled(charKey))
            if TaskTracker.SetCharTooltipEnabled then
                TaskTracker.SetCharTooltipEnabled(charKey, nextOn)
            end
            bindRow(row, charKey)
        end)

        local isCurrent = charKey == current
        if isCurrent then
            row.removeBtn:Hide()
            row.detailFS:SetPoint("RIGHT", row.tipBtn, "LEFT", -8, 0)
        else
            row.removeBtn:Show()
            row.detailFS:SetPoint("RIGHT", row.removeBtn, "LEFT", -8, 0)
            row.removeBtn:SetScript("OnClick", function()
                local label = TaskTracker.GetCharDisplayName and TaskTracker.GetCharDisplayName(charKey) or charKey
                StaticPopupDialogs["TASKTRACKER_FORGET_CHARACTER"] = {
                    text = "Remove stored data for %s?\nThey leave this list until you log in on them again. Task names stay; only that character’s progress, module toggles, and tooltip data are cleared.",
                    button1 = YES,
                    button2 = NO,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    OnAccept = function()
                        if TaskTracker.ForgetCharacterData then
                            TaskTracker.ForgetCharacterData(charKey)
                        end
                        RebuildList()
                        RebuildLayout()
                    end,
                }
                StaticPopup_Show("TASKTRACKER_FORGET_CHARACTER", label)
            end)
        end
    end

    RebuildList = function()
        local chars = TaskTracker.GetTrackedCharacters and TaskTracker.GetTrackedCharacters() or {}
        local n = #chars
        empty:SetShown(n == 0)
        for i = 1, math.max(n, #rows) do
            local row = rows[i]
            if i <= n then
                row = ensureRow(i)
                bindRow(row, chars[i])
                row:Show()
            elseif row then
                row:Hide()
            end
        end
    end

    RebuildLayout = function()
        local sw = scrollFrame:GetWidth()
        if sw < 80 then sw = 400 end
        sw = math.max(280, sw - 16)
        hint:SetWidth(math.max(200, sw - 20))
        empty:SetWidth(math.max(200, sw - 20))
        local inner = math.max(200, sw - 20)
        local gap = 12
        local half = math.max(120, math.floor((inner - gap) / 2))
        currencyTotalBtn:SetWidth(half)
        highestRepBtn:ClearAllPoints()
        highestRepBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", 10 + half + gap, -42)
        highestRepBtn:SetWidth(math.max(120, inner - half - gap))
        local chars = TaskTracker.GetTrackedCharacters and TaskTracker.GetTrackedCharacters() or {}
        for i = 1, #chars do
            local row = rows[i]
            if row then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -(listTop + (i - 1) * ROW_H))
                row:SetWidth(inner)
                row.nameFS:SetWidth(math.max(80, inner - 204))
            end
        end
        local h = listTop + math.max(#chars, 1) * ROW_H + 24
        pane:SetSize(sw, h)
        scrollChild:SetSize(sw, h)
        if scrollFrame.UpdateScrollBar then
            scrollFrame.UpdateScrollBar()
        end
    end

    content.scrollFrame = scrollFrame
    content.RebuildLayout = RebuildLayout
    content.OnShow = function()
        UpdateAlwaysBtns()
        RebuildList()
        RebuildLayout()
    end

    RebuildList()
    RebuildLayout()
    return content
end

local function OpenSkipCurrencyPopup(onAdded)
    local pop = TaskTracker._ttRtbCurrencyPopup
    if not pop then
        pop = TaskTracker.MakePanel("TaskTrackerSkipCurrency", UIParent, 380, 168)
        pop:SetFrameStrata("FULLSCREEN_DIALOG")
        pop:SetFrameLevel(100)
        pop:EnableMouse(true)
        pop:SetClampedToScreen(true)
        pop:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        pop:Hide()
        pop.TitleText:SetText("Skip a currency")
        pop.CloseButton:SetScript("OnClick", function() pop:Hide() end)
        if pop:GetName() then tinsert(UISpecialFrames, pop:GetName()) end

        local hint = TaskTracker.CreateFontString(pop.Content, nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", pop.Content, "TOPLEFT", 16, -12)
        hint:SetPoint("TOPRIGHT", pop.Content, "TOPRIGHT", -16, -12)
        hint:SetJustifyH("LEFT")
        if hint.SetWordWrap then hint:SetWordWrap(true) end
        TaskTracker.SetTextColor(hint, "textSecondary")
        hint:SetText("Shift-click a currency, or type its name and press Enter.")

        local edit = TaskTracker.MakeEditBox(pop.Content, nil, 340, 28)
        edit:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
        edit:SetPoint("TOPRIGHT", hint, "BOTTOMRIGHT", 0, -10)
        edit:SetMaxLetters(80)
        pop._edit = edit
        TaskTracker._ttRtbCurrencyEdit = edit

        local status = TaskTracker.CreateFontString(pop.Content, nil, "OVERLAY", "GameFontNormalSmall")
        status:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -8)
        status:SetPoint("TOPRIGHT", edit, "BOTTOMRIGHT", 0, -8)
        status:SetJustifyH("LEFT")
        if status.SetWordWrap then status:SetWordWrap(true) end
        TaskTracker.SetTextColor(status, "textSecondary")
        pop._status = status

        local matchHost = CreateFrame("Frame", nil, pop.Content)
        matchHost:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -8)
        matchHost:SetPoint("TOPRIGHT", status, "BOTTOMRIGHT", 0, -8)
        pop._matches = matchHost
        pop._matchBtns = {}

        local function setStatus(text)
            status:SetText(text or "")
        end
        local function hideMatches()
            for i = 1, #pop._matchBtns do pop._matchBtns[i]:Hide() end
            matchHost:SetHeight(1)
            pop:SetHeight(168)
        end
        local function commitId(id, name)
            if not id then return end
            local ids = TaskTracker.GetReadyToBuyIgnoredCurrencyIds and TaskTracker.GetReadyToBuyIgnoredCurrencyIds() or {}
            for i = 1, #ids do
                if ids[i] == id then
                    setStatus((name or "That currency") .. " is already on the list.")
                    edit:SetText("")
                    hideMatches()
                    return
                end
            end
            if TaskTracker.AddReadyToBuyIgnoredCurrency then
                TaskTracker.AddReadyToBuyIgnoredCurrency(id)
            end
            edit:SetText("")
            hideMatches()
            setStatus("Added " .. (name or "currency") .. ".")
            if pop._onAdded then pop._onAdded() end
        end
        local function showMatches(list)
            hideMatches()
            local n = math.min(#list, 8)
            if n < 1 then
                setStatus("No currency by that name. Shift-click it from your currency list.")
                return
            end
            if #list == 1 then
                commitId(list[1].id, list[1].name)
                return
            end
            setStatus((#list > n) and "A few matches. Keep typing to narrow them, or pick one." or "Pick one.")
            for i = 1, n do
                local btn = pop._matchBtns[i]
                if not btn then
                    btn = TaskTracker.MakeQuietAction(matchHost, "", 340, 28)
                    pop._matchBtns[i] = btn
                end
                local entry = list[i]
                btn:SetLabel(entry.name)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", matchHost, "TOPLEFT", 0, -((i - 1) * 32))
                btn:SetPoint("TOPRIGHT", matchHost, "TOPRIGHT", 0, -((i - 1) * 32))
                btn:SetScript("OnClick", function()
                    commitId(entry.id, entry.name)
                end)
                btn:Show()
            end
            matchHost:SetHeight(n * 32)
            pop:SetHeight(168 + n * 32)
        end
        local function submit()
            local text = edit:GetText() or ""
            local id = text:match("|Hcurrency:(%d+)") or text:match("currency:(%d+)")
            if id and TaskTracker.GetReadyToBuyCurrencyName then
                commitId(tonumber(id), TaskTracker.GetReadyToBuyCurrencyName(tonumber(id)))
                return
            end
            local list = TaskTracker.FindReadyToBuyCurrencies and TaskTracker.FindReadyToBuyCurrencies(text) or {}
            showMatches(list)
        end
        edit:SetScript("OnEnterPressed", function(self)
            submit()
            self:ClearFocus()
        end)
        edit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            pop:Hide()
        end)
        edit:SetScript("OnTextChanged", function(self, user)
            if not user then return end
            local text = self:GetText() or ""
            if text:find("|Hcurrency:", 1, true) or text:find("currency:", 1, true) then
                submit()
            end
        end)
        pop:SetScript("OnShow", function()
            hideMatches()
            setStatus("")
            edit:SetText("")
            edit:SetFocus()
        end)
        pop._commitId = commitId
        if not TaskTracker._ttRtbCurrencyLinkHook and hooksecurefunc then
            TaskTracker._ttRtbCurrencyLinkHook = true
            pcall(hooksecurefunc, "ChatEdit_InsertLink", function(link)
                local frame = TaskTracker._ttRtbCurrencyPopup
                if not frame or not frame:IsShown() then return end
                if type(link) ~= "string" or not link:find("currency:", 1, true) then return end
                local id = tonumber(link:match("|Hcurrency:(%d+)") or link:match("currency:(%d+)"))
                if id and frame._commitId then
                    frame._commitId(id, TaskTracker.GetReadyToBuyCurrencyName and TaskTracker.GetReadyToBuyCurrencyName(id))
                end
            end)
        end
        TaskTracker._ttRtbCurrencyPopup = pop
    end
    if not pop:GetPoint() then
        pop:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    pop._onAdded = onAdded
    pop:Show()
    pop:Raise()
end

local function BuildGenerativeTasksPanel(parent)
    local t = TaskTracker.GetTheme()
    local font = t.fontNormal or "GameFontNormalSmall"
    local content, scrollFrame, scrollChild, pane = TaskTracker.MakeScrollPane(parent, { childWidth = 400 })
    TaskTracker.optionsGenerativeScrollBar = content.scrollBarTrack

    local PAD = 16
    local GAP = 8
    local ROW = OptRow()
    local HDR = OptRow()
    local EXPAND_KEY = "generative_ready"

    local header = CreateFrame("Button", nil, pane)
    header:SetHeight(HDR)
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    TaskTracker.SetColor(headerBg, "headerBg2")
    TaskTracker.MakeEdge(header, "BOTTOM", "border")
    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("LEFT", header, "LEFT", 8, 0)
    local tog = TaskTracker.MakeButton(header, "", 38, 18)
    tog:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    tog:SetFrameLevel(header:GetFrameLevel() + 5)
    tog:SetScript("OnEnter", nil)
    tog:SetScript("OnLeave", nil)
    if tog.SetPropagateMouseClicks then tog:SetPropagateMouseClicks(false) end
    local hdrLbl = TaskTracker.CreateFontString(header, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    hdrLbl:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
    hdrLbl:SetPoint("RIGHT", tog, "LEFT", -8, 0)
    hdrLbl:SetJustifyH("LEFT")
    hdrLbl:SetJustifyV("MIDDLE")
    if hdrLbl.SetWordWrap then hdrLbl:SetWordWrap(false) end
    hdrLbl:SetText("Ready to Buy")

    local body = CreateFrame("Frame", nil, pane)

    local function textH(fs, width)
        fs:SetWidth(width)
        local h = fs:GetStringHeight() or 0
        if h < 12 then
            local text = fs:GetText() or ""
            local per = math.max(24, math.floor(width / 6.2))
            h = math.max(1, math.ceil(#text / per)) * 14
        end
        return h
    end

    local blurb = TaskTracker.CreateFontString(body, nil, "OVERLAY", font)
    blurb:SetJustifyH("LEFT")
    if blurb.SetWordWrap then blurb:SetWordWrap(true) end
    TaskTracker.SetTextColor(blurb, "textSecondary")
    blurb:SetText("One row per vendor you can buy from. The number is how many this spend can buy, and the currencies are what that spend uses. The same coins are not counted twice. Reputation you do not meet stays on the row and is not counted. Uses AllTheThings (General).")

    local spendRow = CreateFrame("Frame", nil, body)
    spendRow:SetHeight(ROW)
    local spendSeg = TaskTracker.MakeQuietSegments(spendRow, {
        { key = "high", label = "High to low" },
        { key = "low", label = "Low to high" },
    })
    spendSeg:SetPoint("TOPRIGHT", spendRow, "TOPRIGHT", 0, 0)
    local spendLab = TaskTracker.CreateFontString(spendRow, nil, "OVERLAY", font)
    spendLab:SetPoint("LEFT", spendRow, "LEFT", 0, 0)
    spendLab:SetPoint("RIGHT", spendSeg, "LEFT", -8, 0)
    spendLab:SetJustifyH("LEFT")
    spendLab:SetJustifyV("MIDDLE")
    if spendLab.SetWordWrap then spendLab:SetWordWrap(false) end
    spendLab:SetText("Spend")
    TaskTracker.SetTextColor(spendLab, "textPrimary")
    local function syncSpend()
        local order = (TaskTracker.GetReadyToBuySpendOrder and TaskTracker.GetReadyToBuySpendOrder()) or "high"
        spendSeg:SetActive(order)
    end
    for key, btn in pairs(spendSeg.buttons) do
        btn:SetScript("OnClick", function()
            if TaskTracker.SetReadyToBuySpendOrder then
                TaskTracker.SetReadyToBuySpendOrder(key)
            end
            spendSeg:SetActive(key)
        end)
    end
    syncSpend()

    local function makeFold(labelText, expandKey, defaultOpen)
        local btn = CreateFrame("Button", nil, body)
        btn:SetHeight(22)
        local arrowFs = btn:CreateTexture(nil, "OVERLAY")
        arrowFs:SetSize(12, 12)
        arrowFs:SetPoint("LEFT", btn, "LEFT", 0, 0)
        local lab = TaskTracker.CreateFontString(btn, nil, "OVERLAY", t.fontBold or "GameFontNormal")
        lab:SetPoint("LEFT", arrowFs, "RIGHT", 6, 0)
        lab:SetJustifyH("LEFT")
        lab:SetJustifyV("MIDDLE")
        lab:SetText(labelText)
        TaskTracker.SetTextColor(lab, "textAccent")
        local rule = btn:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -18)
        rule:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -18)
        TaskTracker.SetColor(rule, "border")
        btn.arrow = arrowFs
        function btn:IsOpen()
            local db = TaskTrackerDB
            if not db or type(db.optionsExpanded) ~= "table" then return defaultOpen end
            local v = db.optionsExpanded[expandKey]
            if v == nil then return defaultOpen end
            return v and true or false
        end
        btn:SetScript("OnClick", function()
            if not TaskTrackerDB then return end
            if type(TaskTrackerDB.optionsExpanded) ~= "table" then
                TaskTrackerDB.optionsExpanded = {}
            end
            TaskTrackerDB.optionsExpanded[expandKey] = not btn:IsOpen()
            if content.RebuildLayout then content.RebuildLayout() end
        end)
        return btn
    end

    local showFold = makeFold("Show", "generative_ready_show", true)
    local KIND_ROWS = {
        { key = "mount", label = "Mounts" },
        { key = "pet", label = "Pets" },
        { key = "toy", label = "Toys" },
        { key = "appearance", label = "Appearances" },
        { key = "housing", label = "Housing" },
        { key = "recipe", label = "Recipes" },
        { key = "other", label = "Other" },
    }
    local kindToggles = {}
    for i = 1, #KIND_ROWS do
        local spec = KIND_ROWS[i]
        local kindTog = TaskTracker.MakeQuietToggle(body, spec.label)
        kindTog.kindKey = spec.key
        kindTog:SetScript("OnClick", function(self)
            local on = not (TaskTracker.IsReadyToBuyKindEnabled and TaskTracker.IsReadyToBuyKindEnabled(self.kindKey))
            if TaskTracker.SetReadyToBuyKind then
                TaskTracker.SetReadyToBuyKind(self.kindKey, on)
            end
            self:SetOn(on)
        end)
        kindToggles[i] = kindTog
    end

    local expFold = makeFold("Expansions", "generative_ready_exp", false)
    local expToggles = {}
    local expRows = (TaskTracker.READY_TO_BUY_EXPANSIONS) or { { key = "midnight", label = "Midnight" } }
    for i = 1, #expRows do
        local spec = expRows[i]
        local expTog = TaskTracker.MakeQuietToggle(body, spec.label)
        expTog.expKey = spec.key
        expTog:SetScript("OnClick", function(self)
            local on = not (TaskTracker.IsReadyToBuyExpansionEnabled and TaskTracker.IsReadyToBuyExpansionEnabled(self.expKey))
            if TaskTracker.SetReadyToBuyExpansionEnabled then
                TaskTracker.SetReadyToBuyExpansionEnabled(self.expKey, on)
            end
            self:SetOn(on)
        end)
        expToggles[i] = expTog
    end

    local skipSec = TaskTracker.MakeQuietSection(body)
    skipSec:SetText("Currencies to skip")
    local skipHint = TaskTracker.CreateFontString(body, nil, "OVERLAY", font)
    skipHint:SetJustifyH("LEFT")
    if skipHint.SetWordWrap then skipHint:SetWordWrap(true) end
    TaskTracker.SetTextColor(skipHint, "textSecondary")
    skipHint:SetText("Suggestions will not spend these. Shift-click a currency, or type its name.")

    local addBtn = TaskTracker.MakeQuietAction(body, "Add currency", 140, ROW)

    local ignoreHost = CreateFrame("Frame", nil, body)
    local ignoreRows = {}
    local emptyFs = TaskTracker.CreateFontString(ignoreHost, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    emptyFs:SetPoint("TOPLEFT", ignoreHost, "TOPLEFT", 0, 0)
    TaskTracker.SetTextColor(emptyFs, "textSecondary")
    emptyFs:SetText("None yet.")

    local function hideMenus() end

    addBtn:SetScript("OnClick", function()
        OpenSkipCurrencyPopup(function()
            if content.RebuildLayout then content.RebuildLayout() end
        end)
    end)
    attachButtonTip(addBtn, "Add currency", "Shift-click a currency, or type its name. Ready to Buy will not spend it.")

    local function paintIgnored(rowW)
        local ids = (TaskTracker.GetReadyToBuyIgnoredCurrencyIds and TaskTracker.GetReadyToBuyIgnoredCurrencyIds()) or {}
        local rowH = ROW
        emptyFs:SetShown(#ids == 0)
        for i = 1, #ids do
            local row = ignoreRows[i]
            if not row then
                row = CreateFrame("Frame", nil, ignoreHost)
                row:SetHeight(rowH)
                local nameFs = TaskTracker.CreateFontString(row, nil, "OVERLAY", font)
                local rem = TaskTracker.MakeQuietAction(row, "Remove", 72, ROW)
                rem:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                nameFs:SetPoint("LEFT", row, "LEFT", 0, 0)
                nameFs:SetPoint("RIGHT", rem, "LEFT", -8, 0)
                nameFs:SetJustifyH("LEFT")
                nameFs:SetJustifyV("MIDDLE")
                if nameFs.SetWordWrap then nameFs:SetWordWrap(false) end
                TaskTracker.SetTextColor(nameFs, "textPrimary")
                row.nameFs = nameFs
                row.rem = rem
                ignoreRows[i] = row
            end
            local id = ids[i]
            local name = (TaskTracker.GetReadyToBuyCurrencyName and TaskTracker.GetReadyToBuyCurrencyName(id)) or tostring(id)
            row.nameFs:SetText(name)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", ignoreHost, "TOPLEFT", 0, -((i - 1) * (ROW + GAP)))
            row:SetPoint("TOPRIGHT", ignoreHost, "TOPRIGHT", 0, -((i - 1) * (ROW + GAP)))
            row.rem:SetScript("OnClick", function()
                hideMenus()
                if TaskTracker.RemoveReadyToBuyIgnoredCurrency then
                    TaskTracker.RemoveReadyToBuyIgnoredCurrency(id)
                end
                if content.RebuildLayout then content.RebuildLayout() end
            end)
            row:Show()
        end
        for i = #ids + 1, #ignoreRows do
            ignoreRows[i]:Hide()
        end
        local h = (#ids == 0) and 18 or (#ids * (ROW + GAP) - GAP)
        ignoreHost:SetHeight(h)
        return h
    end

    local function sectionExpanded()
        local db = TaskTrackerDB
        if not db or type(db.optionsExpanded) ~= "table" then return true end
        local v = db.optionsExpanded[EXPAND_KEY]
        if v == nil then return true end
        return v and true or false
    end

    local function place(widget, x, y, w)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y)
        if w and widget.SetWidth then widget:SetWidth(w) end
        if widget.Layout then widget:Layout(w) end
        widget:Show()
    end

    local function labelWidth(tog)
        local lab = tog.label
        local sw = 0
        if lab then
            if lab.SetWordWrap then lab:SetWordWrap(false) end
            if lab.SetMaxLines then lab:SetMaxLines(1) end
            if lab.GetUnboundedStringWidth then
                sw = lab:GetUnboundedStringWidth() or 0
            elseif lab.GetStringWidth then
                sw = lab:GetStringWidth() or 0
            end
        end
        if sw < 8 then
            sw = #(lab and lab:GetText() or "") * 8
        end
        return sw
    end

    -- One width for every switch in the group, so the tracks line up.
    -- Columns drop when the window cannot fit another chip that wide.
    local function placeFlow(list, y, inner)
        local n = #list
        if n < 1 then return y end
        local gapX = 16
        local widest = 0
        for i = 1, n do
            widest = math.max(widest, labelWidth(list[i]))
        end
        local minW = math.ceil(widest + 36 + 16)
        local cols = 1
        if minW <= inner then
            cols = math.min(n, math.floor((inner + gapX) / (minW + gapX)))
            if cols < 1 then cols = 1 end
        end
        local w = math.floor((inner - gapX * (cols - 1)) / cols)
        if w < 1 then w = inner end
        local rowGap = 4
        for i = 1, n do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            place(list[i], PAD + col * (w + gapX), y + row * (ROW + rowGap), w)
        end
        local rows = math.ceil(n / cols)
        return y + rows * ROW + (rows - 1) * rowGap
    end

    local function placeOn(parent, widget, x, y, w)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        if w and widget.SetWidth then widget:SetWidth(w) end
        if widget.Layout then widget:Layout(w) end
        widget:Show()
    end

    local function placeFlowOn(parent, list, y, inner)
        local n = #list
        if n < 1 then return y end
        local gapX = 16
        local widest = 0
        for i = 1, n do
            widest = math.max(widest, labelWidth(list[i]))
        end
        local minW = math.ceil(widest + 36 + 16)
        local cols = 1
        if minW <= inner then
            cols = math.min(n, math.floor((inner + gapX) / (minW + gapX)))
            if cols < 1 then cols = 1 end
        end
        local w = math.floor((inner - gapX * (cols - 1)) / cols)
        if w < 1 then w = inner end
        local rowGap = 4
        for i = 1, n do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            placeOn(parent, list[i], PAD + col * (w + gapX), y + row * (ROW + rowGap), w)
        end
        local rows = math.ceil(n / cols)
        return y + rows * ROW + (rows - 1) * rowGap
    end

    local function hideFlow(list)
        for i = 1, #list do
            list[i]:Hide()
        end
    end

    local WQ_KEY = "generative_wq"
    local wqHeader = CreateFrame("Button", nil, pane)
    wqHeader:SetHeight(HDR)
    local wqHeaderBg = wqHeader:CreateTexture(nil, "BACKGROUND")
    wqHeaderBg:SetAllPoints()
    TaskTracker.SetColor(wqHeaderBg, "headerBg2")
    TaskTracker.MakeEdge(wqHeader, "BOTTOM", "border")
    local wqArrow = wqHeader:CreateTexture(nil, "OVERLAY")
    wqArrow:SetSize(12, 12)
    wqArrow:SetPoint("LEFT", wqHeader, "LEFT", 8, 0)
    local wqTog = TaskTracker.MakeButton(wqHeader, "", 38, 18)
    wqTog:SetPoint("RIGHT", wqHeader, "RIGHT", -8, 0)
    wqTog:SetFrameLevel(wqHeader:GetFrameLevel() + 5)
    wqTog:SetScript("OnEnter", nil)
    wqTog:SetScript("OnLeave", nil)
    if wqTog.SetPropagateMouseClicks then wqTog:SetPropagateMouseClicks(false) end
    local wqLbl = TaskTracker.CreateFontString(wqHeader, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    wqLbl:SetPoint("LEFT", wqArrow, "RIGHT", 6, 0)
    wqLbl:SetPoint("RIGHT", wqTog, "LEFT", -8, 0)
    wqLbl:SetJustifyH("LEFT")
    wqLbl:SetJustifyV("MIDDLE")
    if wqLbl.SetWordWrap then wqLbl:SetWordWrap(false) end
    wqLbl:SetText("World Quests")

    local wqBody = CreateFrame("Frame", nil, pane)
    local wqBlurb = TaskTracker.CreateFontString(wqBody, nil, "OVERLAY", font)
    wqBlurb:SetJustifyH("LEFT")
    if wqBlurb.SetWordWrap then wqBlurb:SetWordWrap(true) end
    TaskTracker.SetTextColor(wqBlurb, "textSecondary")
    wqBlurb:SetText("World quests that are up right now, grouped by zone. Gold and missing collectables use the expansions you turn on. A currency name and a reputation name search every expansion back to Legion. Reputation includes renown.")

    local function wqOpen(key, defaultOpen)
        local saved = TaskTrackerDB
        if not saved or type(saved.optionsExpanded) ~= "table" then return defaultOpen end
        local v = saved.optionsExpanded[key]
        if v == nil then return defaultOpen end
        return v and true or false
    end

    local function wqFold(labelText, expandKey, defaultOpen)
        local btn = CreateFrame("Button", nil, wqBody)
        btn:SetHeight(22)
        local arrowFs = btn:CreateTexture(nil, "OVERLAY")
        arrowFs:SetSize(12, 12)
        arrowFs:SetPoint("LEFT", btn, "LEFT", 0, 0)
        local lab = TaskTracker.CreateFontString(btn, nil, "OVERLAY", t.fontBold or "GameFontNormal")
        lab:SetPoint("LEFT", arrowFs, "RIGHT", 6, 0)
        lab:SetJustifyH("LEFT")
        lab:SetJustifyV("MIDDLE")
        lab:SetText(labelText)
        TaskTracker.SetTextColor(lab, "textAccent")
        local rule = btn:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -18)
        rule:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -18)
        TaskTracker.SetColor(rule, "border")
        btn.arrow = arrowFs
        function btn:IsOpen()
            return wqOpen(expandKey, defaultOpen)
        end
        btn:SetScript("OnClick", function()
            if not TaskTrackerDB then return end
            if type(TaskTrackerDB.optionsExpanded) ~= "table" then
                TaskTrackerDB.optionsExpanded = {}
            end
            TaskTrackerDB.optionsExpanded[expandKey] = not btn:IsOpen()
            if content.RebuildLayout then content.RebuildLayout() end
        end)
        return btn
    end

    local wqShowFold = wqFold("Show", "generative_wq_show", true)
    local wqSimple = {}
    local simpleSpecs = {
        { key = "gold", label = "Gold" },
        { key = "collectables", label = "Collectables" },
    }
    for i = 1, #simpleSpecs do
        local spec = simpleSpecs[i]
        local kindTog = TaskTracker.MakeQuietToggle(wqBody, spec.label)
        kindTog.filterKey = spec.key
        kindTog:SetScript("OnClick", function(self)
            local on = not (TaskTracker.IsWorldQuestHuntFilterEnabled and TaskTracker.IsWorldQuestHuntFilterEnabled(self.filterKey))
            if TaskTracker.SetWorldQuestHuntFilter then
                TaskTracker.SetWorldQuestHuntFilter(self.filterKey, on)
            end
            self:SetOn(on)
        end)
        wqSimple[i] = kindTog
    end

    local function makeQueryRow(filterKey, labelText, hintText)
        local rowTog = TaskTracker.MakeQuietToggle(wqBody, labelText)
        rowTog.filterKey = filterKey
        rowTog:SetScript("OnClick", function(self)
            local on = not (TaskTracker.IsWorldQuestHuntFilterEnabled and TaskTracker.IsWorldQuestHuntFilterEnabled(self.filterKey))
            if TaskTracker.SetWorldQuestHuntFilter then
                TaskTracker.SetWorldQuestHuntFilter(self.filterKey, on)
            end
            self:SetOn(on)
            if content.RebuildLayout then content.RebuildLayout() end
        end)
        local hint = TaskTracker.CreateFontString(wqBody, nil, "OVERLAY", font)
        hint:SetJustifyH("LEFT")
        if hint.SetWordWrap then hint:SetWordWrap(true) end
        TaskTracker.SetTextColor(hint, "textSecondary")
        hint:SetText(hintText)
        local box = TaskTracker.MakeEditBox(wqBody, nil, 200, 22)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        local timer
        box:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            if timer then timer:Cancel() end
            timer = C_Timer.NewTimer(0.3, function()
                timer = nil
                if filterKey == "currency" and TaskTracker.SetWorldQuestHuntCurrencyText then
                    TaskTracker.SetWorldQuestHuntCurrencyText(self:GetText() or "")
                elseif filterKey == "reputation" and TaskTracker.SetWorldQuestHuntReputationText then
                    TaskTracker.SetWorldQuestHuntReputationText(self:GetText() or "")
                end
            end)
        end)
        function box:SyncQuery()
            if self:HasFocus() then return end
            local text = ""
            if filterKey == "currency" and TaskTracker.GetWorldQuestHuntCurrencyText then
                text = TaskTracker.GetWorldQuestHuntCurrencyText()
            elseif filterKey == "reputation" and TaskTracker.GetWorldQuestHuntReputationText then
                text = TaskTracker.GetWorldQuestHuntReputationText()
            end
            if self:GetText() ~= text then self:SetText(text) end
        end
        return rowTog, hint, box
    end

    local wqCurTog, wqCurHint, wqCurBox = makeQueryRow("currency", "Currency", "Type part of the currency name.")
    local wqMinLbl = TaskTracker.CreateFontString(wqBody, nil, "OVERLAY", font)
    wqMinLbl:SetJustifyH("RIGHT")
    wqMinLbl:SetJustifyV("MIDDLE")
    TaskTracker.SetTextColor(wqMinLbl, "textSecondary")
    wqMinLbl:SetText("Min gold")
    local wqMinBox = TaskTracker.MakeEditBox(wqBody, nil, 64, 22)
    wqMinBox:SetNumeric(true)
    wqMinBox:SetMaxLetters(7)
    wqMinBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    wqMinBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local wqMinTimer
    local function commitMinGold(self)
        local raw = self:GetText() or ""
        local n = tonumber(raw)
        if raw == "" or not n then n = 0 end
        if TaskTracker.SetWorldQuestHuntMinGold then
            TaskTracker.SetWorldQuestHuntMinGold(n)
        end
    end
    wqMinBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        if wqMinTimer then wqMinTimer:Cancel() end
        wqMinTimer = C_Timer.NewTimer(0.3, function()
            wqMinTimer = nil
            commitMinGold(self)
        end)
    end)
    wqMinBox:SetScript("OnEditFocusLost", function(self)
        if wqMinTimer then
            wqMinTimer:Cancel()
            wqMinTimer = nil
        end
        commitMinGold(self)
        self:SyncMin()
    end)
    function wqMinBox:SyncMin()
        if self:HasFocus() then return end
        local n = 500
        if TaskTracker.GetWorldQuestHuntMinGold then
            n = TaskTracker.GetWorldQuestHuntMinGold()
        end
        local text = tostring(n)
        if self:GetText() ~= text then self:SetText(text) end
    end
    attachRegionTip(wqMinBox, "Min gold", "Gold world quests under this amount stay off the list. It starts at 500. Clear the box to show every gold quest.")
    local wqRepTog, wqRepHint, wqRepBox = makeQueryRow("reputation", "Reputation", "Type part of the reputation name. Midnight counts as 75 with the faction that offers the quest.")

    local function wqHint(text)
        local hint = TaskTracker.CreateFontString(wqBody, nil, "OVERLAY", font)
        hint:SetJustifyH("LEFT")
        if hint.SetWordWrap then hint:SetWordWrap(true) end
        TaskTracker.SetTextColor(hint, "textSecondary")
        hint:SetText(text)
        return hint
    end

    local wqHideEmpty = TaskTracker.MakeQuietToggle(wqBody, "Hide empty groups")
    wqHideEmpty:SetScript("OnClick", function(self)
        local on = not (TaskTrackerDB and TaskTrackerDB.worldQuestHuntHideEmpty ~= false)
        if TaskTracker.SetWorldQuestHuntHideEmpty then
            TaskTracker.SetWorldQuestHuntHideEmpty(on)
        elseif TaskTrackerDB then
            TaskTrackerDB.worldQuestHuntHideEmpty = on
        end
        self:SetOn(on)
    end)
    local wqHideEmptyHint = wqHint("A hunt with nothing up is left off the list. World Quests hides when every hunt is empty.")

    local wqShowDone = TaskTracker.MakeQuietToggle(wqBody, "Show completed quests")
    wqShowDone:SetScript("OnClick", function(self)
        local on = not (TaskTrackerDB and TaskTrackerDB.worldQuestHuntShowCompleted == true)
        if TaskTracker.SetWorldQuestHuntShowCompleted then
            TaskTracker.SetWorldQuestHuntShowCompleted(on)
        elseif TaskTrackerDB then
            TaskTrackerDB.worldQuestHuntShowCompleted = on
        end
        self:SetOn(on)
    end)
    local wqShowDoneHint = wqHint("Finished world quests stay on the list so you can check your other characters.")

    local wqExpFold = wqFold("Expansions", "generative_wq_exp", false)
    local wqExpToggles = {}
    local wqExpRows = (TaskTracker.WorldQuestHuntExpansionRows and TaskTracker.WorldQuestHuntExpansionRows()) or {}
    for i = 1, #wqExpRows do
        local spec = wqExpRows[i]
        local expTog = TaskTracker.MakeQuietToggle(wqBody, spec.label)
        expTog.expKey = spec.key
        expTog:SetScript("OnClick", function(self)
            local on = not (TaskTracker.IsWorldQuestHuntExpansionEnabled and TaskTracker.IsWorldQuestHuntExpansionEnabled(self.expKey))
            if TaskTracker.SetWorldQuestHuntExpansionEnabled then
                TaskTracker.SetWorldQuestHuntExpansionEnabled(self.expKey, on)
            end
            self:SetOn(on)
        end)
        wqExpToggles[i] = expTog
    end

    local function wqSectionOpen()
        return wqOpen(WQ_KEY, true)
    end

    local function layoutWorldQuests(sw, y)
        local on = not TaskTracker.IsWorldQuestHuntEnabled or TaskTracker.IsWorldQuestHuntEnabled()
        local open = wqSectionOpen()
        TaskTracker.ApplyTwistIcon(wqArrow, open)
        TaskTracker.SetTextColor(wqLbl, on and "textHeader" or "textDim")
        TaskTracker.PaintQuietSwitch(wqTog, on)
        wqHeader:ClearAllPoints()
        wqHeader:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -y)
        wqHeader:SetSize(sw, HDR)
        if not open then
            wqBody:Hide()
            return y + HDR + 12
        end
        wqBody:Show()
        local inner = math.max(200, sw - PAD * 2)
        local by = 4
        wqBlurb:ClearAllPoints()
        wqBlurb:SetPoint("TOPLEFT", wqBody, "TOPLEFT", PAD, -by)
        by = by + textH(wqBlurb, inner) + GAP
        placeOn(wqBody, wqShowFold, PAD, by, inner)
        TaskTracker.ApplyTwistIcon(wqShowFold.arrow, wqShowFold:IsOpen())
        by = by + 22 + 4
        if wqShowFold:IsOpen() then
            for i = 1, #wqSimple do
                local row = wqSimple[i]
                local onFilter = not TaskTracker.IsWorldQuestHuntFilterEnabled or TaskTracker.IsWorldQuestHuntFilterEnabled(row.filterKey)
                row:SetOn(onFilter)
            end
            by = placeFlowOn(wqBody, wqSimple, by, inner) + GAP
            local function placeQuery(tog, hint, box)
                local onFilter = TaskTracker.IsWorldQuestHuntFilterEnabled and TaskTracker.IsWorldQuestHuntFilterEnabled(tog.filterKey)
                tog:SetOn(onFilter and true or false)
                placeOn(wqBody, tog, PAD, by, inner)
                by = by + ROW + 4
                if onFilter then
                    hint:Show()
                    box:Show()
                    box:SyncQuery()
                    hint:ClearAllPoints()
                    hint:SetPoint("TOPLEFT", wqBody, "TOPLEFT", PAD, -by)
                    by = by + textH(hint, inner) + 4
                    placeOn(wqBody, box, PAD, by, inner)
                    by = by + 22 + GAP
                else
                    hint:Hide()
                    box:Hide()
                end
            end
            local function placeCurrencyRow()
                local onFilter = TaskTracker.IsWorldQuestHuntFilterEnabled and TaskTracker.IsWorldQuestHuntFilterEnabled(wqCurTog.filterKey)
                wqCurTog:SetOn(onFilter and true or false)
                local boxW, labW, gap = 64, 58, 10
                local togW = inner - boxW - labW - gap * 2
                if togW < 140 then togW = 140 end
                placeOn(wqBody, wqCurTog, PAD, by, togW)
                local mid = math.max(0, math.floor((ROW - 22) / 2))
                placeOn(wqBody, wqMinLbl, PAD + togW + gap, by + mid, labW)
                wqMinLbl:SetHeight(22)
                placeOn(wqBody, wqMinBox, PAD + togW + gap + labW, by + mid, boxW)
                wqMinBox:SyncMin()
                by = by + ROW + 4
                if onFilter then
                    wqCurHint:Show()
                    wqCurBox:Show()
                    wqCurBox:SyncQuery()
                    wqCurHint:ClearAllPoints()
                    wqCurHint:SetPoint("TOPLEFT", wqBody, "TOPLEFT", PAD, -by)
                    by = by + textH(wqCurHint, inner) + 4
                    placeOn(wqBody, wqCurBox, PAD, by, inner)
                    by = by + 22 + GAP
                else
                    wqCurHint:Hide()
                    wqCurBox:Hide()
                end
            end
            placeCurrencyRow()
            placeQuery(wqRepTog, wqRepHint, wqRepBox)
            local hideEmptyOn = not TaskTrackerDB or TaskTrackerDB.worldQuestHuntHideEmpty ~= false
            wqHideEmpty:SetOn(hideEmptyOn)
            placeOn(wqBody, wqHideEmpty, PAD, by, inner)
            by = by + ROW + 4
            wqHideEmptyHint:Show()
            wqHideEmptyHint:ClearAllPoints()
            wqHideEmptyHint:SetPoint("TOPLEFT", wqBody, "TOPLEFT", PAD, -by)
            by = by + textH(wqHideEmptyHint, inner) + GAP
            local showDoneOn = TaskTrackerDB and TaskTrackerDB.worldQuestHuntShowCompleted == true
            wqShowDone:SetOn(showDoneOn and true or false)
            placeOn(wqBody, wqShowDone, PAD, by, inner)
            by = by + ROW + 4
            wqShowDoneHint:Show()
            wqShowDoneHint:ClearAllPoints()
            wqShowDoneHint:SetPoint("TOPLEFT", wqBody, "TOPLEFT", PAD, -by)
            by = by + textH(wqShowDoneHint, inner) + GAP
        else
            hideFlow(wqSimple)
            wqCurTog:Hide()
            wqCurHint:Hide()
            wqCurBox:Hide()
            wqMinLbl:Hide()
            wqMinBox:Hide()
            wqRepTog:Hide()
            wqRepHint:Hide()
            wqRepBox:Hide()
            wqHideEmpty:Hide()
            wqHideEmptyHint:Hide()
            wqShowDone:Hide()
            wqShowDoneHint:Hide()
        end
        placeOn(wqBody, wqExpFold, PAD, by, inner)
        TaskTracker.ApplyTwistIcon(wqExpFold.arrow, wqExpFold:IsOpen())
        by = by + 22 + 4
        if wqExpFold:IsOpen() then
            for i = 1, #wqExpToggles do
                local expTog = wqExpToggles[i]
                local onExp = TaskTracker.IsWorldQuestHuntExpansionEnabled and TaskTracker.IsWorldQuestHuntExpansionEnabled(expTog.expKey)
                expTog:SetOn(onExp and true or false)
            end
            by = placeFlowOn(wqBody, wqExpToggles, by, inner) + GAP
        else
            hideFlow(wqExpToggles)
        end
        wqBody:ClearAllPoints()
        wqBody:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -(y + HDR + 2))
        wqBody:SetSize(sw, by + 8)
        return y + HDR + 2 + by + 16
    end

    local function RebuildLayout()
        hideMenus()
        local sw = scrollFrame:GetWidth()
        if sw < 80 then sw = 400 end
        sw = math.max(280, sw - 16)
        local on = not TaskTracker.IsReadyToBuyEnabled or TaskTracker.IsReadyToBuyEnabled()
        local open = sectionExpanded()
        TaskTracker.ApplyTwistIcon(arrow, open)
        TaskTracker.SetTextColor(hdrLbl, on and "textHeader" or "textDim")
        TaskTracker.PaintQuietSwitch(tog, on)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -8)
        header:SetSize(sw, HDR)

        local h
        if not open then
            body:Hide()
            h = 8 + HDR + 12
        else
            body:Show()
            local inner = math.max(200, sw - PAD * 2)
            local by = 4
            blurb:ClearAllPoints()
            blurb:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -by)
            by = by + textH(blurb, inner) + GAP
            place(spendRow, PAD, by, inner)
            local segW = math.min(240, math.max(160, math.floor(inner * 0.55)))
            spendSeg:Layout(segW)
            syncSpend()
            by = by + ROW + GAP + 4
            place(showFold, PAD, by, inner)
            TaskTracker.ApplyTwistIcon(showFold.arrow, showFold:IsOpen())
            by = by + 22 + 4
            if showFold:IsOpen() then
                for i = 1, #kindToggles do
                    local kindTog = kindToggles[i]
                    local onKind = not TaskTracker.IsReadyToBuyKindEnabled or TaskTracker.IsReadyToBuyKindEnabled(kindTog.kindKey)
                    kindTog:SetOn(onKind)
                end
                by = placeFlow(kindToggles, by, inner) + GAP
            else
                hideFlow(kindToggles)
            end
            place(expFold, PAD, by, inner)
            TaskTracker.ApplyTwistIcon(expFold.arrow, expFold:IsOpen())
            by = by + 22 + 4
            if expFold:IsOpen() then
                for i = 1, #expToggles do
                    local expTog = expToggles[i]
                    local onExp = TaskTracker.IsReadyToBuyExpansionEnabled and TaskTracker.IsReadyToBuyExpansionEnabled(expTog.expKey)
                    expTog:SetOn(onExp)
                end
                by = placeFlow(expToggles, by, inner) + GAP
            else
                hideFlow(expToggles)
            end
            by = by + 4
            by = skipSec:Place(body, PAD, by, inner)
            skipHint:ClearAllPoints()
            skipHint:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -by)
            by = by + textH(skipHint, inner) + GAP
            addBtn:ClearAllPoints()
            addBtn:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -by)
            by = by + ROW + GAP
            local listH = paintIgnored(inner)
            ignoreHost:ClearAllPoints()
            ignoreHost:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -by)
            ignoreHost:SetPoint("TOPRIGHT", body, "TOPLEFT", PAD + inner, -by)
            by = by + listH
            body:ClearAllPoints()
            body:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -(8 + HDR + 2))
            body:SetSize(sw, by + 8)
            h = 8 + HDR + 2 + by + 16
        end
        h = layoutWorldQuests(sw, h)
        pane:SetSize(sw, h)
        scrollChild:SetSize(sw, h)
        if scrollFrame.UpdateScrollBar then
            scrollFrame.UpdateScrollBar()
        end
    end

    header:SetScript("OnClick", function()
        if tog:IsMouseOver() then return end
        if not TaskTrackerDB then return end
        if type(TaskTrackerDB.optionsExpanded) ~= "table" then
            TaskTrackerDB.optionsExpanded = {}
        end
        TaskTrackerDB.optionsExpanded[EXPAND_KEY] = not sectionExpanded()
        RebuildLayout()
    end)
    tog:SetScript("OnClick", function()
        local enabled = TaskTracker.IsReadyToBuyEnabled and TaskTracker.IsReadyToBuyEnabled()
        if TaskTracker.SetReadyToBuyEnabled then
            TaskTracker.SetReadyToBuyEnabled(not enabled)
        end
        RebuildLayout()
    end)
    attachButtonTip(tog, "Ready to Buy", "Turn this list on or off. Settings stay here either way.")

    wqHeader:SetScript("OnClick", function()
        if wqTog:IsMouseOver() then return end
        if not TaskTrackerDB then return end
        if type(TaskTrackerDB.optionsExpanded) ~= "table" then
            TaskTrackerDB.optionsExpanded = {}
        end
        TaskTrackerDB.optionsExpanded[WQ_KEY] = not wqSectionOpen()
        RebuildLayout()
    end)
    wqTog:SetScript("OnClick", function()
        local enabled = TaskTracker.IsWorldQuestHuntEnabled and TaskTracker.IsWorldQuestHuntEnabled()
        if TaskTracker.SetWorldQuestHuntEnabled then
            TaskTracker.SetWorldQuestHuntEnabled(not enabled)
        end
        RebuildLayout()
    end)
    attachButtonTip(wqTog, "World Quests", "Turn this list on or off. Settings stay here either way.")

    content.scrollFrame = scrollFrame
    content.RebuildLayout = RebuildLayout
    TaskTracker.RefreshGenerativeTasksPanel = function()
        if content:IsShown() then
            RebuildLayout()
        end
    end
    content.OnShow = function()
        RebuildLayout()
    end
    content:SetScript("OnHide", function()
        hideMenus()
        if TaskTracker._ttRtbCurrencyPopup then TaskTracker._ttRtbCurrencyPopup:Hide() end
        if wqCurBox then wqCurBox:ClearFocus() end
        if wqRepBox then wqRepBox:ClearFocus() end
    end)
    content.OnHide = function()
        hideMenus()
        if TaskTracker._ttRtbCurrencyPopup then TaskTracker._ttRtbCurrencyPopup:Hide() end
    end

    RebuildLayout()
    return content
end

-- ─────────────────────────────────────
-- Profiles (right-hand section)
-- ─────────────────────────────────────
local function BuildProfilesPanel(parent)
    local t = TaskTracker.GetTheme()
    local font = t.fontNormal or "GameFontNormalSmall"
    local content, scrollFrame, scrollChild, pane = TaskTracker.MakeScrollPane(parent, { childWidth = 400 })

    local PAD = 16
    local GAP = 8
    local ROW = OptRow()

    local function makeBlurb(text)
        local fs = TaskTracker.CreateFontString(pane, nil, "OVERLAY", font)
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        TaskTracker.SetTextColor(fs, "textSecondary")
        fs:SetText(text)
        return fs
    end

    local function textBlockHeight(fs, width)
        fs:SetWidth(width)
        return math.max(14, fs:GetStringHeight() or 14)
    end

    local sec = TaskTracker.MakeQuietSection(pane)
    sec:SetText("Profiles")
    local secShare = TaskTracker.MakeQuietSection(pane)
    secShare:SetText("Import and export")

    local blurb = makeBlurb("This character uses this profile. General options, style, modules, generated tasks, and your own tasks come from it. Other characters on the same profile share those. Checks and counts stay on each character.")
    local shareBlurb = makeBlurb("Pick a profile to export. This character stays on its own. Import adds a profile for this character. Progress is not included.")

    local hideMenus = {}
    local function hideAllMenus()
        for i = 1, #hideMenus do
            hideMenus[i]()
        end
    end

    local function paintDropFace(btn, hover)
        if hover then
            TaskTracker.PaintQuietHover(btn.bg, btn.label)
        else
            if btn.bg then TaskTracker.SetColor(btn.bg, "headerBg2") end
            if btn.label then TaskTracker.SetTextColor(btn.label, "textPrimary") end
        end
    end

    local function makeProfileMenu(btn, onPick, getSelected)
        if TaskTracker.AttachDropdownArrow then
            TaskTracker.AttachDropdownArrow(btn)
        end
        local menu = CreateFrame("Frame", nil, parent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(400)
        menu:Hide()
        menu:SetClampedToScreen(true)
        if TaskTracker.RegisterOpenDropdown then
            TaskTracker.RegisterOpenDropdown(menu)
        end
        local menuBg = menu:CreateTexture(nil, "BACKGROUND")
        menuBg:SetAllPoints()
        TaskTracker.SetColor(menuBg, "headerBg2")
        TaskTracker.MakeBorder(menu, "border")
        local menuRows = {}

        local function hide()
            menu:Hide()
        end

        local function rebuild()
            local names = TaskTracker.GetProfileNames and TaskTracker.GetProfileNames() or {}
            local rowH = 24
            local width = math.max(160, btn:GetWidth() - 8)
            for i = 1, #names do
                local name = names[i]
                local row = menuRows[i]
                if not row then
                    row = TaskTracker.MakeQuietAction(menu, name, width, rowH)
                    menuRows[i] = row
                end
                row:SetWidth(width)
                row:SetLabel(name)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * (rowH + 2))
                row:Show()
                local function paintRow(hover)
                    local picked = getSelected and getSelected() == name
                    if hover and not picked then
                        TaskTracker.PaintQuietHover(row.bg, row.label)
                        return
                    end
                    TaskTracker.PaintQuietChoice(row.bg, row.label, picked)
                    if not picked and row.bg then
                        TaskTracker.SetColor(row.bg, "headerBg2")
                    end
                end
                paintRow(false)
                row:SetScript("OnEnter", function() paintRow(true) end)
                row:SetScript("OnLeave", function() paintRow(false) end)
                row:SetScript("OnClick", function()
                    hideAllMenus()
                    onPick(name)
                end)
            end
            for i = #names + 1, #menuRows do
                menuRows[i]:Hide()
            end
            local n = math.max(1, #names)
            menu:SetSize(width + 8, n * (rowH + 2) + 6)
        end

        btn:SetScript("OnClick", function()
            local wasShown = menu:IsShown()
            hideAllMenus()
            if wasShown then return end
            rebuild()
            menu:ClearAllPoints()
            menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            menu:Show()
        end)

        hideMenus[#hideMenus + 1] = hide
        return hide
    end

    local dropBtn = TaskTracker.MakeQuietAction(pane, "Default", 240, ROW)
    local exportDrop = TaskTracker.MakeQuietAction(pane, "Default", 240, ROW)
    paintDropFace(dropBtn, false)
    paintDropFace(exportDrop, false)
    dropBtn:SetScript("OnEnter", function() paintDropFace(dropBtn, true) end)
    dropBtn:SetScript("OnLeave", function() paintDropFace(dropBtn, false) end)
    exportDrop:SetScript("OnEnter", function() paintDropFace(exportDrop, true) end)
    exportDrop:SetScript("OnLeave", function() paintDropFace(exportDrop, false) end)

    local status = TaskTracker.CreateFontString(pane, nil, "OVERLAY", font)
    status:SetJustifyH("LEFT")
    if status.SetWordWrap then status:SetWordWrap(true) end
    TaskTracker.SetTextColor(status, "danger")
    status:SetText("")

    local function setStatus(msg)
        status:SetText(msg or "")
    end

    local function currentName()
        local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
        local name = key and TaskTracker.ProfileNameForCharacter and TaskTracker.ProfileNameForCharacter(key)
        if not name and TaskTracker.GetLoadedProfileName then
            name = TaskTracker.GetLoadedProfileName()
        end
        return name or "Default"
    end

    local function profileLabel(name)
        if TaskTracker.IsHiddenProfile and TaskTracker.IsHiddenProfile(name) then
            return (TaskTracker.FreshInstallProfileLabel and TaskTracker.FreshInstallProfileLabel()) or "New install"
        end
        return name or "Default"
    end

    local function hiddenNow()
        return TaskTracker.IsHiddenProfile and TaskTracker.IsHiddenProfile(currentName())
    end

    local exportName

    local function syncDrop()
        local current = currentName()
        dropBtn:SetLabel(profileLabel(current))
        local names = TaskTracker.GetProfileNames and TaskTracker.GetProfileNames() or {}
        local found = false
        if exportName and not (TaskTracker.IsHiddenProfile and TaskTracker.IsHiddenProfile(exportName)) then
            for i = 1, #names do
                if names[i] == exportName then
                    found = true
                    break
                end
            end
        end
        if not found then
            if hiddenNow() then
                exportName = names[1]
            else
                exportName = current
            end
        end
        exportDrop:SetLabel(profileLabel(exportName or names[1] or "Default"))
    end

    local function hideMenu()
        hideAllMenus()
    end

    makeProfileMenu(dropBtn, function(name)
        local ok, err = TaskTracker.SelectProfileForCurrentCharacter(name)
        if not ok then
            setStatus(err or "Could not change the profile.")
        else
            setStatus("")
        end
        if content:IsShown() then
            syncDrop()
        end
    end, currentName)
    makeProfileMenu(exportDrop, function(name)
        exportName = name
        exportDrop:SetLabel(name)
        setStatus("")
    end, function() return exportName end)

    local function editBoxOf(dialog)
        if dialog.editBox then return dialog.editBox end
        if dialog.GetEditBox then return dialog:GetEditBox() end
        return nil
    end

    local function promptName(text, defaultText, onAccept)
        hideMenu()
        StaticPopupDialogs["TASKTRACKER_PROFILE_NAME"] = {
            text = text,
            button1 = "OK",
            button2 = "Cancel",
            hasEditBox = true,
            maxLetters = 40,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnShow = function(self)
                local edit = editBoxOf(self)
                if not edit then return end
                edit:SetText(defaultText or "")
                edit:HighlightText()
                edit:SetFocus()
            end,
            OnAccept = function(self)
                local edit = editBoxOf(self)
                onAccept(edit and edit:GetText() or "")
            end,
            EditBoxOnEnterPressed = function(self)
                local parent = self:GetParent()
                if parent and parent.button1 then
                    parent.button1:Click()
                end
            end,
        }
        StaticPopup_Show("TASKTRACKER_PROFILE_NAME")
    end

    local function afterChange(ok, err)
        if ok then
            setStatus("")
        else
            setStatus(err or "Could not change the profile.")
        end
        if content:IsShown() then
            syncDrop()
        end
    end

    local newBtn = TaskTracker.MakeQuietAction(pane, "New", 72, ROW)
    local copyBtn = TaskTracker.MakeQuietAction(pane, "Copy", 72, ROW)
    local renameBtn = TaskTracker.MakeQuietAction(pane, "Rename", 80, ROW)
    local deleteBtn = TaskTracker.MakeQuietAction(pane, "Delete", 72, ROW)
    local exportBtn = TaskTracker.MakeQuietAction(pane, "Export", 80, ROW)
    local importBtn = TaskTracker.MakeQuietAction(pane, "Import", 80, ROW)

    newBtn:SetScript("OnClick", function()
        promptName("Name the new profile. It starts from the default list.", "", function(entered)
            afterChange(TaskTracker.CreateProfile(entered))
        end)
    end)
    copyBtn:SetScript("OnClick", function()
        local suggested = profileLabel(currentName()) .. " copy"
        if #suggested > 40 then suggested = suggested:sub(1, 40) end
        promptName("Name the copy. Tasks are copied. Checks and counts stay on the original.", suggested, function(entered)
            afterChange(TaskTracker.CopyLoadedProfile(entered))
        end)
    end)
    renameBtn:SetScript("OnClick", function()
        local now = currentName()
        if hiddenNow() then
            setStatus("Switch back before renaming.")
            return
        end
        promptName("Rename this profile.", now, function(entered)
            afterChange(TaskTracker.RenameProfile(now, entered))
        end)
    end)
    deleteBtn:SetScript("OnClick", function()
        hideMenu()
        local now = currentName()
        if hiddenNow() then
            setStatus("Switch back before deleting.")
            return
        end
        StaticPopupDialogs["TASKTRACKER_PROFILE_DELETE"] = {
            text = "Delete " .. now .. "? Characters using it will switch to another profile.",
            button1 = "Delete",
            button2 = "Cancel",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function()
                afterChange(TaskTracker.DeleteProfile(now))
            end,
        }
        StaticPopup_Show("TASKTRACKER_PROFILE_DELETE")
    end)
    exportBtn:SetScript("OnClick", function()
        hideMenu()
        TaskTracker.OpenShareImportExportDialog({
            title = "Export profile",
            hint = "This text is the profile, not your progress. A friend imports it under Options "
                .. (TaskTracker.RightChevronMarkup and TaskTracker.RightChevronMarkup(11) or ">")
                .. " Profiles.",
            focusExportSelect = true,
            profileImport = true,
            getExportText = function()
                local text, err = TaskTracker.ExportProfileByName(exportName or currentName())
                if not text then
                    setStatus(err or "Could not write that profile.")
                    return ""
                end
                setStatus("")
                return text
            end,
            importText = function(text)
                local ok, err = TaskTracker.ImportProfileFromText(text)
                if not ok then
                    return err or "Could not read that profile."
                end
                if content:IsShown() then
                    setStatus("")
                    syncDrop()
                end
                return nil
            end,
        })
    end)
    importBtn:SetScript("OnClick", function()
        hideMenu()
        TaskTracker.OpenShareImportExportDialog({
            title = "Import profile",
            hint = "Paste a profile here. It is added for this character. Checks and counts are not included.",
            profileImport = true,
            importText = function(text)
                local ok, err = TaskTracker.ImportProfileFromText(text)
                if not ok then
                    return err or "Could not read that profile."
                end
                if content:IsShown() then
                    setStatus("")
                    syncDrop()
                end
                return nil
            end,
        })
    end)

    local function placeBox(widget, x, y, w)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -y)
        widget:SetWidth(w)
    end

    local function placeBlurb(fs, y, width)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -y)
        return y + textBlockHeight(fs, width) + GAP
    end

    local function RebuildLayout()
        local sw = scrollFrame:GetWidth()
        if sw < 80 then sw = 400 end
        sw = math.max(280, sw - 16)
        local inner = math.max(200, sw - PAD * 2)
        local function placeButtons(buttons, yStart)
            local x = PAD
            local rowTop = yStart
            for i = 1, #buttons do
                local b = buttons[i]
                local w = b:GetWidth()
                if x > PAD and (x + w) > (PAD + inner) then
                    rowTop = rowTop + ROW + GAP
                    x = PAD
                end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -rowTop)
                x = x + w + GAP
            end
            return rowTop + ROW + GAP
        end

        local y = 8
        y = sec:Place(pane, PAD, y, inner)
        y = placeBlurb(blurb, y, inner)
        placeBox(dropBtn, PAD, y, math.min(280, inner))
        y = y + ROW + GAP
        y = placeButtons({ newBtn, copyBtn, renameBtn, deleteBtn }, y)
        y = y + 8
        y = secShare:Place(pane, PAD, y, inner)
        y = placeBlurb(shareBlurb, y, inner)
        placeBox(exportDrop, PAD, y, math.min(280, inner))
        y = y + ROW + GAP
        y = placeButtons({ exportBtn, importBtn }, y)
        status:ClearAllPoints()
        status:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -y)
        status:SetWidth(inner)
        y = y + 36
        local h = y + 16
        pane:SetSize(sw, h)
        scrollChild:SetSize(sw, h)
        if scrollFrame.UpdateScrollBar then
            scrollFrame.UpdateScrollBar()
        end
    end

    content.OnShow = function()
        syncDrop()
        RebuildLayout()
    end
    TaskTracker.RefreshProfileMenuIfShown = function()
        if content:IsShown() then
            syncDrop()
        end
    end
    content:SetScript("OnHide", function()
        hideMenu()
    end)
    content.RebuildLayout = RebuildLayout
    syncDrop()
    RebuildLayout()
    return content
end

-- ─────────────────────────────────────
-- Create options panel
-- ─────────────────────────────────────
function TaskTracker.CreateOptionsPanel(mainPanel)
    TaskTracker._ttPatchListModeButtonMaps = {}
    local db = TaskTrackerDB
    local maxW = math.floor(UIParent:GetWidth() - 24)
    local maxH = math.floor(UIParent:GetHeight() - 24)
    local ow = (db and db.optionsPanelWidth) or OPTS_WIDTH
    local oh = (db and db.optionsPanelHeight) or OPTS_HEIGHT
    ow = math.max(520, math.min(ow, maxW))
    oh = math.max(360, math.min(oh, maxH))

    local opts = TaskTracker.MakePanel("TaskTrackerOptions", UIParent, ow, oh, {
        optionsChrome = true,
        titleHeight = TaskTracker.GetOptionsTitleHeight and TaskTracker.GetOptionsTitleHeight(),
        titleMargin = TaskTracker.GetOptionsTitleMargin and TaskTracker.GetOptionsTitleMargin(),
        titleFontSize = TaskTracker.GetOptionsTitleFontSize and TaskTracker.GetOptionsTitleFontSize(),
        titleIconSize = TaskTracker.GetOptionsTitleIconSize and TaskTracker.GetOptionsTitleIconSize(),
    })
    if TaskTracker.AnchorFrameNearScreenTop then
        TaskTracker.AnchorFrameNearScreenTop(opts, 0, 0.12)
    else
        opts:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    opts:SetFrameStrata("DIALOG")
    opts:SetFrameLevel(250)
    opts:Hide()
    opts:SetResizable(true)
    opts:SetResizeBounds(520, 360, maxW, maxH)
    opts:SetClampedToScreen(true)

    opts.TitleText:SetText("Options")
    opts.CloseButton:SetScript("OnClick", function() opts:Hide() end)

    local optsName = opts:GetName()
    if optsName then
        tinsert(UISpecialFrames, optsName)
    end

    local function NavColumnWidth()
        local w = opts:GetWidth()
        if w < 80 then w = OPTS_WIDTH end
        return math.min(220, math.max(156, math.floor(w * 0.2)))
    end

    local contentArea = CreateFrame("Frame", nil, opts.Content)
    contentArea:SetPoint("TOPLEFT",     opts.Content, "TOPLEFT",     0, 0)
    contentArea:SetPoint("BOTTOMRIGHT", opts.Content, "BOTTOMRIGHT", 0, 0)

    local navHost = CreateFrame("Frame", nil, contentArea)
    navHost:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
    navHost:SetPoint("BOTTOMLEFT", contentArea, "BOTTOMLEFT", 0, 0)

    local navHostBg = navHost:CreateTexture(nil, "BACKGROUND")
    navHostBg:SetAllPoints()
    TaskTracker.SetColor(navHostBg, "headerBg2")

    local _, navScroll, navChild = TaskTracker.MakeScrollPane(navHost, { useParent = true, pane = false })
    TaskTracker.optionsNavScrollBar = navHost.scrollBarTrack

    local navSep = navHost:CreateTexture(nil, "ARTWORK")
    navSep:SetWidth(1)
    navSep:SetPoint("TOPRIGHT", navHost, "TOPRIGHT", 0, 0)
    navSep:SetPoint("BOTTOMRIGHT", navHost, "BOTTOMRIGHT", 0, 0)
    TaskTracker.SetColor(navSep, "border")

    local detailHost = CreateFrame("Frame", nil, contentArea)
    detailHost:SetPoint("TOPLEFT", navHost, "TOPRIGHT", 1, 0)
    detailHost:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)

    local displayPanel = BuildDisplayPanel(detailHost)
    displayPanel:SetAllPoints()
    displayPanel:Hide()

    local charactersPanel = BuildCharactersPanel(detailHost)
    charactersPanel:SetAllPoints()
    charactersPanel:Hide()

    local layoutPanel = BuildListLayoutPanel(detailHost)
    layoutPanel:SetAllPoints()
    layoutPanel:Hide()

    local advancedTasksPanel = BuildAdvancedTasksPanel(detailHost)
    advancedTasksPanel:SetAllPoints()
    advancedTasksPanel:Hide()

    local modulesPanel = BuildAutoTrackedTab(detailHost)
    modulesPanel:SetAllPoints()
    modulesPanel:Hide()

    local shortcutsPanel = TaskTracker.BuildShortcutsPanel(detailHost)
    shortcutsPanel:SetAllPoints()
    shortcutsPanel:Hide()

    local generativePanel = BuildGenerativeTasksPanel(detailHost)
    generativePanel:SetAllPoints()
    generativePanel:Hide()

    local profilesPanel = BuildProfilesPanel(detailHost)
    profilesPanel:SetAllPoints()
    profilesPanel:Hide()

    local navLabels = { "General", "Characters", "Style", "Modules", "Shortcuts", "Generative tasks", "Advanced", "Profiles" }
    local navKeys   = { "general", "characters", "style", "modules", "shortcuts", "generative", "advanced", "profiles" }
    local navButtons = {}
    local detailPanels = { displayPanel, charactersPanel, layoutPanel, modulesPanel, shortcutsPanel, generativePanel, advancedTasksPanel, profilesPanel }
    local selectedNav = 1
    local navKeyIndex = {}
    for i, k in ipairs(navKeys) do
        navKeyIndex[k] = i
    end

    local function ApplyNavSelectionVisual(i)
        local btn = navButtons[i]
        if not btn or not btn.SetSelected then return end
        btn:SetSelected(i == selectedNav)
    end

    local navRowGap = 4

    local function RelayoutNav()
        local nw = NavColumnWidth()
        navHost:SetWidth(nw)
        local bw = math.max(72, nw - NAV_PAD * 2)
        for _, btn in ipairs(navButtons) do
            btn:SetWidth(bw)
        end
        local navRowH = OptRow()
        local nh = #navLabels * (navRowH + navRowGap) + NAV_PAD * 2
        navChild:SetSize(math.max(bw + NAV_PAD * 2, nw), nh)
        if navScroll.UpdateScrollBar then
            navScroll.UpdateScrollBar()
        end
    end

    local function SelectNavSection(index)
        if index < 1 or index > #detailPanels then return end
        selectedNav = index
        local key = navKeys[index]
        TaskTracker.optionsSelectedNav = key
        if TaskTrackerDB then
            TaskTrackerDB.optionsNavKey = key
        end
        for i = 1, #navButtons do
            ApplyNavSelectionVisual(i)
        end
        for i, pan in ipairs(detailPanels) do
            if i == index then
                pan:Show()
                if pan.OnShow then pan.OnShow() end
            else
                pan:Hide()
            end
        end
    end

    for i, label in ipairs(navLabels) do
        local navRowH = OptRow()
        local btn = TaskTracker.MakeQuietNavButton(navChild, label, 160, navRowH)
        btn:SetPoint("TOPLEFT", navChild, "TOPLEFT", NAV_PAD, -NAV_PAD - (i - 1) * (navRowH + navRowGap))
        navButtons[i] = btn
        local idx = i
        btn:SetScript("OnEnter", function()
            if selectedNav ~= idx then
                TaskTracker.SetTextColor(btn.label, "textPrimary")
            end
        end)
        btn:SetScript("OnLeave", function()
            ApplyNavSelectionVisual(idx)
        end)
        btn:SetScript("OnClick", function()
            SelectNavSection(idx)
        end)
    end

    local savedNav = (TaskTrackerDB and TaskTrackerDB.optionsNavKey) or TaskTracker.optionsSelectedNav
    SelectNavSection(navKeyIndex[savedNav] or 1)
    RelayoutNav()

    -- Bottom-right resize grip (same idea as main Task Tracker panel)
    local GRIP_SIZE  = 18
    local LINE_THICK = 2
    local LINE_LEN   = 11

    local grip = CreateFrame("Button", nil, opts)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", opts, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(opts:GetFrameLevel() + 25)

    local lineV = grip:CreateTexture(nil, "ARTWORK")
    lineV:SetSize(LINE_THICK, LINE_LEN)
    lineV:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1)
    TaskTracker.SetColor(lineV, "accent")
    lineV:SetAlpha(0.55)

    local lineH = grip:CreateTexture(nil, "ARTWORK")
    lineH:SetSize(LINE_LEN, LINE_THICK)
    lineH:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1)
    TaskTracker.SetColor(lineH, "accent")
    lineH:SetAlpha(0.55)

    local function SetGripLineAlpha(a)
        lineV:SetAlpha(a)
        lineH:SetAlpha(a)
    end

    local function CancelOptsResizeTimer()
        if TaskTracker._optsResizeTimer then
            TaskTracker._optsResizeTimer:Cancel()
            TaskTracker._optsResizeTimer = nil
        end
    end

    local function ApplyOptsLayoutFromResize()
        RelayoutNav()
        if modulesPanel.Rebuild then
            modulesPanel.Rebuild()
        end
        if displayPanel.RebuildLayout then
            displayPanel.RebuildLayout()
        end
        if charactersPanel.RebuildLayout then
            charactersPanel.RebuildLayout()
        end
        if layoutPanel.RebuildLayout then
            layoutPanel.RebuildLayout()
        end
        if shortcutsPanel.RebuildLayout then
            shortcutsPanel.RebuildLayout()
        end
        if advancedTasksPanel.RebuildLayout then
            advancedTasksPanel.RebuildLayout()
        end
        if generativePanel.RebuildLayout then
            generativePanel.RebuildLayout()
        end
        if profilesPanel.RebuildLayout then
            profilesPanel.RebuildLayout()
        end
    end

    local function ScheduleOptsRelayout()
        CancelOptsResizeTimer()
        TaskTracker._optsResizeTimer = C_Timer.NewTimer(0.1, function()
            TaskTracker._optsResizeTimer = nil
            ApplyOptsLayoutFromResize()
        end)
    end

    local function EndOptsResize()
        opts:StopMovingOrSizing()
        grip:SetScript("OnUpdate", nil)
        CancelOptsResizeTimer()
        ApplyOptsLayoutFromResize()
    end

    grip:SetScript("OnEnter", function() SetGripLineAlpha(0.9) end)
    grip:SetScript("OnLeave", function() SetGripLineAlpha(0.55) end)
    grip:SetScript("OnHide", function()
        opts:StopMovingOrSizing()
        grip:SetScript("OnUpdate", nil)
        CancelOptsResizeTimer()
    end)

    grip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            opts:StartSizing("BOTTOMRIGHT")
            self:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then
                    EndOptsResize()
                end
            end)
        end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            EndOptsResize()
        end
    end)

    opts:SetScript("OnSizeChanged", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.optionsPanelWidth  = math.floor(opts:GetWidth() + 0.5)
        TaskTrackerDB.optionsPanelHeight = math.floor(opts:GetHeight() + 0.5)
        ScheduleOptsRelayout()
    end)

    opts:SetScript("OnShow", function()
        local mw = math.floor(UIParent:GetWidth() - 24)
        local mh = math.floor(UIParent:GetHeight() - 24)
        opts:SetResizeBounds(520, 360, mw, mh)
        if opts:GetWidth() > mw or opts:GetHeight() > mh then
            opts:SetSize(math.min(opts:GetWidth(), mw), math.min(opts:GetHeight(), mh))
        end
        RelayoutNav()
        for _, pan in ipairs(detailPanels) do
            if pan:IsShown() and pan.OnShow then pan.OnShow() end
        end
        if modulesPanel.Rebuild then
            modulesPanel.Rebuild()
        end
        if displayPanel.RebuildLayout then
            displayPanel.RebuildLayout()
        end
        if layoutPanel.RebuildLayout then
            layoutPanel.RebuildLayout()
        end
        if shortcutsPanel.RebuildLayout then
            shortcutsPanel.RebuildLayout()
        end
        if advancedTasksPanel.RebuildLayout then
            advancedTasksPanel.RebuildLayout()
        end
        if generativePanel.RebuildLayout then
            generativePanel.RebuildLayout()
        end
        if profilesPanel.RebuildLayout then
            profilesPanel.RebuildLayout()
        end
    end)

    opts:SetScript("OnHide", function()
        if TaskTracker.HideKeybindCapture then
            TaskTracker.HideKeybindCapture()
        end
    end)

    if TaskTracker.AttachOptionsVersion then
        TaskTracker.AttachOptionsVersion(opts)
    end

    function opts:GetSectionScroll()
        local pan = detailPanels[selectedNav]
        local sf = pan and pan.scrollFrame
        if sf and sf.GetVerticalScroll then
            return sf:GetVerticalScroll() or 0
        end
        return 0
    end

    function opts:SetSectionScroll(y)
        local pan = detailPanels[selectedNav]
        local sf = pan and pan.scrollFrame
        if not sf or not sf.SetVerticalScroll then return end
        y = tonumber(y) or 0
        local function apply()
            if not sf.SetVerticalScroll then return end
            local child = sf.GetScrollChild and sf:GetScrollChild()
            local maxS = 0
            if child then
                maxS = math.max(0, (child:GetHeight() or 0) - (sf:GetHeight() or 0))
            end
            sf:SetVerticalScroll(math.max(0, math.min(maxS, y)))
            if sf.UpdateScrollBar then sf.UpdateScrollBar() end
        end
        apply()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, apply)
        end
    end

    return opts
end