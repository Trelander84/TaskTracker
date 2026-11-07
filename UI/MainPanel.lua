-- UI/MainPanel.lua
-- Main panel creation using the theme system
-- No Blizzard frame templates used

TaskTracker = TaskTracker or {}

local DEFAULT_PANEL_WIDTH  = 280
local DEFAULT_PANEL_HEIGHT = 400

TaskTracker.PANEL_WIDTH  = DEFAULT_PANEL_WIDTH
TaskTracker.PANEL_HEIGHT = DEFAULT_PANEL_HEIGHT
TaskTracker.rowFrames    = {}

local function HideTrackerHelpIfOpen()
    local hp = TaskTracker.helpPopup
    if hp and hp:IsShown() and (hp.currentKey == "tracker_main" or hp.currentKey == "tracker_edit") then
        hp:Hide()
    end
end

-- Title bar chrome icons (white PNGs, tinted with textPrimary).
local ICON_EYE_SHOW = "eye"
local ICON_EYE_HIDE = "eye-off"
local ICON_OPTIONS  = "gear"
local ICON_EDIT     = "edit"
local ICON_EXPAND   = "expand"

--- Clear edit / reorder state when the panel is hidden (close, reload UI, etc.)
function TaskTracker.ExitEditModeOnHide()
    TaskTracker.editMode = false
    TaskTracker._ttInsertHighlightParentId = nil
    TaskTracker.reorderPickUpNodeId = nil
    if TaskTracker.CancelReorderDrag then
        TaskTracker.CancelReorderDrag()
    end
    if TaskTracker.HideNoteWindow then
        TaskTracker.HideNoteWindow()
    end
    TaskTracker.HideQuickCommandsPanel()
    if TaskTracker.HideListExpandMenu then
        TaskTracker.HideListExpandMenu()
    end
    if TaskTracker.lockBtn then
        TaskTracker.SyncTitleBarIcons()
    end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
end

function TaskTracker.SyncTitleBarIcons()
    if TaskTracker.eyeBtn and TaskTracker.eyeBtn.SetChromeIcon then
        local hid = TaskTrackerDB and TaskTrackerDB.hideCompleted
        TaskTracker.eyeBtn:SetChromeIcon(hid and ICON_EYE_HIDE or ICON_EYE_SHOW)
    end
    if TaskTracker.lockBtn and TaskTracker.lockBtn.SetChromeIcon then
        TaskTracker.lockBtn:SetChromeIcon(ICON_EDIT)
        if TaskTracker.editMode then
            TaskTracker.SetColor(TaskTracker.lockBtn.bg, "accentBg")
        else
            if TaskTracker.lockBtn.bg then
                TaskTracker.lockBtn.bg:SetColorTexture(0, 0, 0, 0)
            end
        end
    end
end

-- ─────────────────────────────────────
-- Minimize / expand
-- ─────────────────────────────────────
function TaskTracker.SetMinimized(state)
    TaskTrackerDB.minimized = state
    local panel       = TaskTracker.panel
    local scrollFrame = TaskTracker.scrollFrame
    local minimizeBtn = TaskTracker.minimizeBtn
    local t           = TaskTracker.GetTheme()

    -- Snapshot the real on-screen top before the height change. SavePanelPosition
    -- refuses a hidden frame and the load lock, so the temporary TOP spawn cannot
    -- overwrite the saved spot.
    if TaskTracker.SavePanelPosition then
        TaskTracker.SavePanelPosition(panel)
    end

    if state then
        scrollFrame:Hide()
        if TaskTracker.HideNoteWindow then
            TaskTracker.HideNoteWindow()
        end
        TaskTracker.HideQuickCommandsPanel()
        if TaskTracker.HideListExpandMenu then
            TaskTracker.HideListExpandMenu()
        end
        HideTrackerHelpIfOpen()
        if TaskTracker.scrollBarTrack then
            TaskTracker.scrollBarTrack:Hide()
        end
        panel:SetHeight(t.titleHeight or 28)
        minimizeBtn:SetChromeIcon("minus")
        if TaskTracker.resizeGrip then
            TaskTracker.resizeGrip:Hide()
        end
    else
        scrollFrame:Show()
        if TaskTracker.scrollBarTrack then
            TaskTracker.scrollBarTrack:Show()
        end
        panel:SetHeight(TaskTracker.PANEL_HEIGHT or DEFAULT_PANEL_HEIGHT)
        minimizeBtn:SetChromeIcon("plus")
        if TaskTracker.resizeGrip then
            TaskTracker.resizeGrip:Show()
        end
        TaskTracker.RefreshList()
    end

    if TaskTracker.RestorePanelPosition then
        TaskTracker.RestorePanelPosition(panel)
    end
end

-- ─────────────────────────────────────
-- Toggle panel
-- ─────────────────────────────────────
function TaskTracker.TogglePanel()
    local panel = TaskTracker.panel
    if panel:IsShown() then
        HideTrackerHelpIfOpen()
        panel:Hide()
        TaskTrackerDB.wasShown = false
    else
        panel:Show()
        TaskTrackerDB.wasShown = true
        if TaskTrackerDB.minimized then
            TaskTracker.SetMinimized(true)
        else
            TaskTracker.RefreshList()
        end
    end
end

-- ─────────────────────────────────────
-- Title bar buttons
-- ─────────────────────────────────────
local function BuildTitleButtons(panel, titleBar)
    local t = TaskTracker.GetTheme()

    local function attachTitleTooltip(btn, title, sub)
        if not btn then return end
        local oEnter, oLeave = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
        btn:SetScript("OnEnter", function(self)
            if oEnter then oEnter(self) end
            TaskTracker.BeginTooltipBesideList(self)
            GameTooltip:SetText(title, 1, 1, 1)
            if sub and sub ~= "" then
                GameTooltip:AddLine(sub, 0.85, 0.85, 0.85, true)
            end
            TaskTracker.FinishTooltipBesideList()
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            if oLeave then oLeave(self) end
        end)
    end

    -- Close button (already on panel from MakePanel)
    panel.CloseButton:SetScript("OnClick", function()
        HideTrackerHelpIfOpen()
        panel:Hide()
        TaskTrackerDB.wasShown = false
    end)

    -- Minimize button
    local minimizeBtn = TaskTracker.MakeIconButton(titleBar, 20, 20, TaskTracker.ChromeIconOpt())
    minimizeBtn:SetPoint("RIGHT", panel.CloseButton, "LEFT", -3, 0)
    minimizeBtn:SetChromeIcon("plus")
    minimizeBtn:SetScript("OnClick", function()
        TaskTracker.SetMinimized(not TaskTrackerDB.minimized)
    end)
    TaskTracker.minimizeBtn = minimizeBtn

    -- List expand / collapse (hover menu)
    local collapseBtn = TaskTracker.MakeIconButton(titleBar, 20, 20, TaskTracker.ChromeIconOpt())
    collapseBtn:SetPoint("RIGHT", minimizeBtn, "LEFT", -3, 0)
    collapseBtn:SetChromeIcon(ICON_EXPAND)
    TaskTracker.listExpandBtn = collapseBtn

    local expandMenu = CreateFrame("Frame", nil, titleBar)
    expandMenu:SetFrameStrata("DIALOG")
    expandMenu:SetFrameLevel((collapseBtn:GetFrameLevel() or 0) + 20)
    local menuW, rowH, rowGap, pad, sepH = 188, 22, 2, 5, 8
    local kindItems = {
        { key = "modules",     label = "Modules" },
        { key = "collections", label = "Collections" },
        { key = "custom",      label = "Custom" },
    }
    local items = {
        { key = "collapse_all", label = "Collapse all" },
        { key = "expand_all",   label = "Expand all" },
        { key = "collapse_one", label = "Collapse 1 level" },
        { key = "expand_one",   label = "Expand 1 level" },
    }
    local kindBlock = #kindItems * (rowH + rowGap)
    expandMenu:SetSize(menuW, pad * 2 + rowH + rowGap + kindBlock + sepH + #items * (rowH + rowGap) - rowGap)
    expandMenu:SetPoint("TOP", collapseBtn, "BOTTOM", 0, 1)
    expandMenu:EnableMouse(true)
    expandMenu:SetClampedToScreen(true)
    expandMenu:Hide()
    local menuBg = expandMenu:CreateTexture(nil, "BACKGROUND")
    menuBg:SetAllPoints()
    TaskTracker.SetColor(menuBg, "headerBg2")
    TaskTracker.MakeBorder(expandMenu, "border")
    TaskTracker.listExpandMenu = expandMenu

    function TaskTracker.HideListExpandMenu()
        if TaskTracker.listExpandMenu then
            TaskTracker.listExpandMenu:Hide()
        end
        if TaskTracker._ttListExpandHideTimer then
            TaskTracker._ttListExpandHideTimer:Cancel()
            TaskTracker._ttListExpandHideTimer = nil
        end
    end

    local function expandMenuHasMouse()
        return (collapseBtn:IsMouseOver() and true) or (expandMenu:IsShown() and expandMenu:IsMouseOver())
    end

    local function showExpandMenu()
        if TaskTracker._ttListExpandHideTimer then
            TaskTracker._ttListExpandHideTimer:Cancel()
            TaskTracker._ttListExpandHideTimer = nil
        end
        expandMenu:Show()
        expandMenu:Raise()
        if TaskTracker.SyncCurrentZoneMenuRow then
            TaskTracker.SyncCurrentZoneMenuRow()
        end
        if TaskTracker.SyncListKindMenuRows then
            TaskTracker.SyncListKindMenuRows()
        end
    end

    local function scheduleHideExpandMenu()
        if TaskTracker._ttListExpandHideTimer then
            TaskTracker._ttListExpandHideTimer:Cancel()
        end
        TaskTracker._ttListExpandHideTimer = C_Timer.NewTimer(0.12, function()
            TaskTracker._ttListExpandHideTimer = nil
            if not expandMenuHasMouse() then
                expandMenu:Hide()
            end
        end)
    end

    local function styleMenuLabel(row)
        if not row.label then return end
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.label:SetJustifyH("LEFT")
        if row.label.SetWordWrap then
            row.label:SetWordWrap(false)
        end
    end

    local function wireMenuRow(row)
        row:SetScript("OnEnter", function(self)
            showExpandMenu()
            TaskTracker.SetColor(self.bg, "accentBg")
            if self.label then
                TaskTracker.SetTextColor(self.label, "textAccent")
            end
        end)
        row:SetScript("OnLeave", function(self)
            if self._ttActive then
                TaskTracker.SetColor(self.bg, "accentBg")
                if self.label then
                    TaskTracker.SetTextColor(self.label, "textAccent")
                end
            else
                TaskTracker.SetColor(self.bg, self._ttIdleBgKey or "headerBg")
                if self.label then
                    TaskTracker.SetTextColor(self.label, self._ttIdleTextKey or "textPrimary")
                end
            end
            scheduleHideExpandMenu()
        end)
    end

    local zoneRow = TaskTracker.MakeButton(expandMenu, "Current zone", menuW - pad * 2, rowH)
    zoneRow:SetPoint("TOPLEFT", expandMenu, "TOPLEFT", pad, -pad)
    styleMenuLabel(zoneRow)
    zoneRow:SetScript("OnClick", function()
        if TaskTracker.ApplyCurrentZoneMenu then
            TaskTracker.ApplyCurrentZoneMenu()
        end
    end)
    wireMenuRow(zoneRow)
    TaskTracker.currentZoneMenuRow = zoneRow

    local kindTips = {
        collections = {
            "Collections",
            "Hides the Collections headers and everything under them.",
        },
        custom = {
            "Custom",
            "Hides groups and tasks you added.",
        },
        modules = {
            "Modules",
            "Hides Power, Seasonal, Professions, and patch activities. Collections has its own row.",
        },
    }
    local zoneSepY = pad + rowH + 3
    local zoneSep = expandMenu:CreateTexture(nil, "ARTWORK")
    zoneSep:SetHeight(2)
    zoneSep:SetPoint("TOPLEFT", expandMenu, "TOPLEFT", pad, -zoneSepY)
    zoneSep:SetPoint("TOPRIGHT", expandMenu, "TOPRIGHT", -pad, -zoneSepY)
    TaskTracker.SetColor(zoneSep, "accent")

    local kindRows = {}
    local kindTop = pad + rowH + sepH
    for i, it in ipairs(kindItems) do
        local row = TaskTracker.MakeButton(expandMenu, "Hide " .. it.label, menuW - pad * 2, rowH)
        row._ttKindName = it.label
        row:SetPoint("TOPLEFT", expandMenu, "TOPLEFT", pad, -(kindTop + (i - 1) * (rowH + rowGap)))
        styleMenuLabel(row)
        local tip = kindTips[it.key]
        row:SetScript("OnClick", function()
            if TaskTracker.ToggleListKindFilter then
                TaskTracker.ToggleListKindFilter(it.key)
            end
        end)
        row:SetScript("OnEnter", function(self)
            showExpandMenu()
            TaskTracker.SetColor(self.bg, "accentBg")
            if self.label then
                TaskTracker.SetTextColor(self.label, "textAccent")
            end
            if tip and TaskTracker.BeginTooltipBesideList then
                TaskTracker.BeginTooltipBesideList(self)
                GameTooltip:SetText(tip[1], 1, 1, 1)
                GameTooltip:AddLine(tip[2], 0.85, 0.85, 0.85, true)
                TaskTracker.FinishTooltipBesideList()
            end
        end)
        row:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            if self._ttActive then
                TaskTracker.SetColor(self.bg, "accentBg")
                if self.label then
                    TaskTracker.SetTextColor(self.label, "textAccent")
                end
            else
                TaskTracker.SetColor(self.bg, self._ttIdleBgKey or "headerBg")
                if self.label then
                    TaskTracker.SetTextColor(self.label, self._ttIdleTextKey or "textPrimary")
                end
            end
            scheduleHideExpandMenu()
        end)
        kindRows[it.key] = row
    end
    TaskTracker.listKindMenuRows = kindRows

    function TaskTracker.SyncListKindMenuRows()
        local rows = TaskTracker.listKindMenuRows
        if not rows then return end
        for key, row in pairs(rows) do
            local hidden = TaskTracker.ListKindFilterHidden and TaskTracker.ListKindFilterHidden(key)
            local name = row._ttKindName or key
            row:SetLabel((hidden and "Show " or "Hide ") .. name)
            TaskTracker.SetButtonActive(row, hidden and true or false)
        end
    end
    TaskTracker.SyncListKindMenuRows()

    local sepY = kindTop + kindBlock - rowGap + 3
    expandMenu:SetHeight(kindTop + kindBlock - rowGap + sepH + #items * (rowH + rowGap) - rowGap + pad)
    local sep = expandMenu:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(2)
    sep:SetPoint("TOPLEFT", expandMenu, "TOPLEFT", pad, -sepY)
    sep:SetPoint("TOPRIGHT", expandMenu, "TOPRIGHT", -pad, -sepY)
    TaskTracker.SetColor(sep, "accent")

    function TaskTracker.SyncCurrentZoneMenuRow()
        local row = TaskTracker.currentZoneMenuRow
        if not row then return end
        local label = (TaskTracker.GetZoneListFilterLabel and TaskTracker.GetZoneListFilterLabel()) or "Focus"
        row:SetLabel(label)
        local on = TaskTracker.IsZoneListFilterActive and TaskTracker.IsZoneListFilterActive()
        TaskTracker.SetButtonActive(row, on and true or false)
    end
    TaskTracker.SyncCurrentZoneMenuRow()

    local belowTop = sepY + sepH
    for i, it in ipairs(items) do
        local row = TaskTracker.MakeButton(expandMenu, it.label, menuW - pad * 2, rowH)
        row:SetPoint("TOPLEFT", expandMenu, "TOPLEFT", pad, -belowTop - (i - 1) * (rowH + rowGap))
        styleMenuLabel(row)
        row:SetScript("OnClick", function()
            if TaskTracker.ApplyListGroupExpand then
                TaskTracker.ApplyListGroupExpand(it.key)
            end
        end)
        wireMenuRow(row)
    end

    local collapseEnter = collapseBtn:GetScript("OnEnter")
    local collapseLeave = collapseBtn:GetScript("OnLeave")
    collapseBtn:SetScript("OnEnter", function(self)
        if collapseEnter then collapseEnter(self) end
        showExpandMenu()
    end)
    collapseBtn:SetScript("OnLeave", function(self)
        if collapseLeave then collapseLeave(self) end
        scheduleHideExpandMenu()
    end)
    collapseBtn:SetScript("OnClick", function()
        showExpandMenu()
    end)
    expandMenu:SetScript("OnEnter", showExpandMenu)
    expandMenu:SetScript("OnLeave", scheduleHideExpandMenu)

    -- Eye — LFG-style open vs covered (hide completed)
    local eyeBtn = TaskTracker.MakeIconButton(titleBar, 20, 20, TaskTracker.ChromeIconOpt())
    eyeBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -3, 0)
    eyeBtn:SetScript("OnClick", function()
        TaskTrackerDB.hideCompleted = not TaskTrackerDB.hideCompleted
        if TaskTracker.MarkListLayoutDirty then
            TaskTracker.MarkListLayoutDirty()
        end
        TaskTracker.RefreshList()
    end)
    TaskTracker.eyeBtn = eyeBtn

    -- Lock / edit
    TaskTracker.editMode = false
    local lockBtn
    lockBtn = TaskTracker.MakeIconButton(titleBar, 20, 20, TaskTracker.ChromeIconOpt({
        onLeave = function(b)
            if TaskTracker.editMode then
                TaskTracker.SetColor(b.bg, "accentBg")
            elseif b.bg then
                b.bg:SetColorTexture(0, 0, 0, 0)
            end
        end,
    }))
    lockBtn:SetPoint("RIGHT", eyeBtn, "LEFT", -3, 0)
    lockBtn:SetChromeIcon(ICON_EDIT)
    lockBtn:SetScript("OnClick", function()
        TaskTracker.editMode = not TaskTracker.editMode
        if not TaskTracker.editMode then
            TaskTracker._ttInsertHighlightParentId = nil
            TaskTracker.reorderPickUpNodeId = nil
            if TaskTracker.CancelReorderDrag then
                TaskTracker.CancelReorderDrag()
            end
            if TaskTracker.HideNoteWindow then
                TaskTracker.HideNoteWindow()
            end
            TaskTracker.HideQuickCommandsPanel()
        end
        if TaskTracker.MarkListLayoutDirty then
            TaskTracker.MarkListLayoutDirty()
        end
        -- A deferred refresh can leave the normal list on screen, which already
        -- omitted empty groups. Rebuild now so edit mode shows them.
        if TaskTracker.RefreshListNow then
            TaskTracker.RefreshListNow()
        else
            TaskTracker.RefreshList()
        end
        local hp = TaskTracker.helpPopup
        if hp and hp:IsShown() and (hp.currentKey == "tracker_main" or hp.currentKey == "tracker_edit") then
            TaskTracker.ToggleHelpScreen(TaskTracker.editMode and "tracker_edit" or "tracker_main")
        end
    end)
    TaskTracker.lockBtn = lockBtn

    -- Options — gear
    local optionsBtn = TaskTracker.MakeIconButton(titleBar, 20, 20, TaskTracker.ChromeIconOpt())
    optionsBtn:SetChromeIcon(ICON_OPTIONS)
    optionsBtn:SetPoint("RIGHT", lockBtn, "LEFT", -3, 0)
    optionsBtn:SetScript("OnClick", function()
        local opts = TaskTracker.optionsPanel
        if opts:IsShown() then
            opts:Hide()
        else
            opts:ClearAllPoints()
            if TaskTracker.AnchorFrameNearScreenTop then
                TaskTracker.AnchorFrameNearScreenTop(opts, 0, 0.12)
            else
                opts:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
            end
            opts:Show()
        end
    end)
    TaskTracker.optionsBtn = optionsBtn

    local syncAllBtn = TaskTracker.MakeIconButton(titleBar, 20, 20, TaskTracker.ChromeIconOpt())
    syncAllBtn:SetPoint("RIGHT", optionsBtn, "LEFT", -3, 0)
    if syncAllBtn.SetIconAtlas then
        syncAllBtn:SetIconAtlas("UI-RefreshButton", false)
    end
    syncAllBtn:SetScript("OnClick", function()
        if TaskTracker._ttForceShareBusy then return end
        TaskTracker._ttForceShareBusy = true
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                TaskTracker._ttForceShareBusy = nil
            end)
        else
            TaskTracker._ttForceShareBusy = nil
        end
        if TaskTracker.ForceLiveShareAll then
            TaskTracker.ForceLiveShareAll()
        end
    end)
    TaskTracker.syncAllBtn = syncAllBtn

    local helpBtn = TaskTracker.MakeIconButton(titleBar, 20, 20, TaskTracker.ChromeIconOpt())
    helpBtn:SetPoint("RIGHT", syncAllBtn, "LEFT", -3, 0)
    helpBtn:SetChromeIcon("help")
    helpBtn:SetScript("OnClick", function()
        local key = TaskTracker.editMode and "tracker_edit" or "tracker_main"
        TaskTracker.ToggleHelpScreen(key)
    end)
    TaskTracker.helpBtn = helpBtn

    attachTitleTooltip(panel.CloseButton, "Close", "Hide the tracker until you open it again.")
    attachTitleTooltip(minimizeBtn, "Minimize", "Collapse or expand the task list; the title bar stays visible.")
    -- Collapse button uses a hover menu instead of a tooltip.
    attachTitleTooltip(eyeBtn, "Completed tasks", "Toggle showing finished rows. When the eye looks covered, completed tasks are hidden.")
    attachTitleTooltip(lockBtn, "Edit mode", "Reorder rows, add groups and tasks. List organization, under Options, General, List, is Pick and place or Drag and drop. Pick and place: tap =, then a gold line. Drag and drop: drag =. Each task shows the edit icon left of =: click to edit, Alt-click to delete.")
    attachTitleTooltip(optionsBtn, "Settings", "Theme, header and task font size, task tooltips, note panel side, and more.")
    attachTitleTooltip(syncAllBtn, "Sync all", "Send every shared task again. Tasks you sent go out with your current count. Tasks someone sent you ask them for a fresh copy. You both need to be online.")
    attachTitleTooltip(helpBtn, "Help", "Tips for the tracker or for Edit mode, depending on what is active.")

    -- Eye/edit icons need an initial atlas; list refresh also calls this, but a refresh error would leave them blank.
    TaskTracker.SyncTitleBarIcons()

    TaskTracker.ApplyTitleBarMetrics()
    if TaskTracker.ApplyLiveShareToolbarButton then
        TaskTracker.ApplyLiveShareToolbarButton()
    end
end

function TaskTracker.ApplyLiveShareToolbarButton()
    local btn = TaskTracker.syncAllBtn
    local help = TaskTracker.helpBtn
    local options = TaskTracker.optionsBtn
    if not btn or not help or not options then return end
    local show = TaskTracker.IsLiveShareSyncAllButtonEnabled and TaskTracker.IsLiveShareSyncAllButtonEnabled()
    btn:ClearAllPoints()
    help:ClearAllPoints()
    if show then
        btn:SetPoint("RIGHT", options, "LEFT", -3, 0)
        help:SetPoint("RIGHT", btn, "LEFT", -3, 0)
        btn:Show()
    else
        btn:Hide()
        help:SetPoint("RIGHT", options, "LEFT", -3, 0)
    end
    if TaskTracker.ApplyTitleBarMetrics then
        TaskTracker.ApplyTitleBarMetrics()
    end
end

function TaskTracker.ApplyTitleBarMetrics()
    local panel = TaskTracker.panel
    if not panel or not panel.titleBar then return end
    local text = panel.TitleText
    if text and text.GetFont then
        local px = TaskTracker.GetTitleFontSize and TaskTracker.GetTitleFontSize() or 14
        text._ttLayoutFace = "bold"
        if TaskTracker.ApplyLayoutFont then
            TaskTracker.ApplyLayoutFont(text, px, "bold")
        end
    end
    local sz = TaskTracker.GetTitleIconSize and TaskTracker.GetTitleIconSize() or 20
    local glyph = math.max(8, sz - 2)
    local icons = {
        panel.CloseButton,
        TaskTracker.minimizeBtn,
        TaskTracker.listExpandBtn,
        TaskTracker.eyeBtn,
        TaskTracker.lockBtn,
        TaskTracker.optionsBtn,
        TaskTracker.helpBtn,
        TaskTracker.syncAllBtn,
    }
    for i = 1, #icons do
        local btn = icons[i]
        if btn then
            btn:SetSize(sz, sz)
            if btn.icon then
                btn.icon:SetSize(glyph, glyph)
            end
        end
    end
    if text then
        local t = TaskTracker.GetTheme and TaskTracker.GetTheme()
        local shown = 0
        for i = 1, #icons do
            if icons[i] and icons[i]:IsShown() then
                shown = shown + 1
            end
        end
        if shown < 1 then shown = 1 end
        local btnStack = shown * sz + (shown - 1) * 3 + 4
        local pad = (t and t.padding) or 8
        text:SetWidth(math.max(48, (TaskTracker.PANEL_WIDTH or 280) - btnStack - pad - 6))
    end
end

-- ─────────────────────────────────────
-- Build scroll area
-- ─────────────────────────────────────
local function BuildScrollArea(panel)
    if TaskTracker.ResetListVirtualization then
        TaskTracker.ResetListVirtualization()
    end
    -- Plain ScrollFrame, no Blizzard template
    local scrollFrame = CreateFrame("ScrollFrame", "TaskTrackerScroll", panel.Content)
    scrollFrame:SetPoint("TOPLEFT",     panel.Content, "TOPLEFT",     0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel.Content, "BOTTOMRIGHT", 0, 0)

    local scrollChild = CreateFrame("Frame", "TaskTrackerScrollChild", scrollFrame)
    local rowW = (TaskTracker.PANEL_WIDTH or DEFAULT_PANEL_WIDTH) - TaskTracker.GetScrollGutter()
    scrollChild:SetSize(rowW, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Custom scrollbar overlaid on the right edge of the content area
    TaskTracker.scrollBarTrack = TaskTracker.MakeScrollBar(scrollFrame, panel.Content)

    TaskTracker.scrollFrame = scrollFrame
    TaskTracker.scrollChild = scrollChild

    -- Virtualized list paint: repaint visible rows on scroll changes.
    -- Do not SetVerticalScroll here (OnVerticalScroll already ran for that offset).
    scrollFrame:SetScript("OnVerticalScroll", function(self)
        if self.UpdateScrollBar then
            self.UpdateScrollBar()
        end
        if TaskTracker.OnListScroll then
            TaskTracker.OnListScroll()
        end
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function(self)
        if self.UpdateScrollBar then
            self.UpdateScrollBar()
        end
        if TaskTracker.OnListScroll then
            TaskTracker.OnListScroll()
        end
    end)
end

function TaskTracker.ApplyEditModeLayout()
    local panel = TaskTracker.panel
    if not panel or not panel.Content then return end
    local scroll = TaskTracker.scrollFrame
    if not scroll then return end

    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", panel.Content, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel.Content, "BOTTOMRIGHT", 0, 0)

    if scroll.UpdateScrollBar then
        scroll.UpdateScrollBar()
    end
end

-- ─────────────────────────────────────
-- First list build after login: wait for PLAYER_ENTERING_WORLD, then defer again — IsPlayerInWorld()
-- can be true and C_WeeklyRewards / quest data can still hard-freeze the loading bar if queried too soon.
-- ─────────────────────────────────────
local LOGIN_LIST_REFRESH_DELAY = 0.9
local RELOAD_LIST_REFRESH_DELAY = 0.12

function TaskTracker.ScheduleRefreshListWhenInWorld()
    local function cancelListRefreshTimer()
        if TaskTracker._ttListRefreshTimer then
            TaskTracker._ttListRefreshTimer:Cancel()
            TaskTracker._ttListRefreshTimer = nil
        end
    end

    local function fireRefresh()
        cancelListRefreshTimer()
        if not IsPlayerInWorld() then return end
        if TaskTracker.RefreshLearnedProfessionsTree then
            TaskTracker.RefreshLearnedProfessionsTree()
            return
        end
        if TaskTracker.RefreshList then
            TaskTracker.RefreshList()
        end
    end

    local function armRefresh(afterSeconds)
        cancelListRefreshTimer()
        TaskTracker._ttListRefreshTimer = C_Timer.NewTimer(afterSeconds, function()
            TaskTracker._ttListRefreshTimer = nil
            fireRefresh()
        end)
    end

    if IsPlayerInWorld() then
        -- /reload (or very late addon load): short deferral only
        armRefresh(RELOAD_LIST_REFRESH_DELAY)
        return
    end

    local wait = CreateFrame("Frame")
    wait:RegisterEvent("PLAYER_ENTERING_WORLD")
    wait:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        armRefresh(LOGIN_LIST_REFRESH_DELAY)
    end)
end

-- ─────────────────────────────────────
-- Create main panel
-- ─────────────────────────────────────
-- ─────────────────────────────────────
-- Position: pin the visual top-left in screen pixels.
-- GetLeft/GetTop are in the frame's effective scale. SetPoint offsets are not,
-- and a UI scale other than 100% makes one SetPoint miss. The miss grows with
-- distance from the bottom of the screen, so a drop near the top lands lower.
-- SetClampedToScreen uses that same bad top and shoves the frame down. The list
-- stays unclamped and NudgePanelOnScreen keeps it on the screen instead.
-- ─────────────────────────────────────
local function EdgesInParentSpace(panel)
    local left, top = panel:GetLeft(), panel:GetTop()
    if not left or not top then return nil, nil end
    local es = panel.GetEffectiveScale and panel:GetEffectiveScale() or 1
    local ps = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if es and ps and es > 0 and ps > 0 then
        left = left * es / ps
        top = top * es / ps
    end
    return left, top
end

function TaskTracker.SavePanelPosition(panel)
    panel = panel or TaskTracker.panel
    if not panel or not TaskTrackerDB then return end
    -- Login/reload holds this until the post-world re-apply. A hidden or
    -- not-yet-laid-out frame still reports the temporary TOP spawn.
    if TaskTracker._ttPosSaveLocked then return end
    if not panel:IsShown() then return end
    local left, top = EdgesInParentSpace(panel)
    if not left or not top then return end
    TaskTrackerDB.position = {
        point         = "TOPLEFT",
        relativePoint = "BOTTOMLEFT",
        x             = left,
        y             = top,
        space         = "parent",
    }
end

function TaskTracker.RestorePanelPosition(panel)
    panel = panel or TaskTracker.panel
    if not panel or not TaskTrackerDB then return end
    local pos = TaskTrackerDB.position
    if not pos or pos.x == nil or pos.y == nil then return end
    local left, top = pos.x, pos.y
    -- 12.1.0.1 and earlier: TOPLEFT of UIParent, y = GetTop() - UIParent:GetHeight()
    if (pos.relativePoint or "TOPLEFT") == "TOPLEFT" then
        top = pos.y + (UIParent:GetHeight() or 0)
    elseif pos.space ~= "parent" then
        -- Older BOTTOMLEFT saves stored raw GetTop. At a non-100 UI scale that
        -- value sits above the screen and clamp pins the panel to the top.
        local scale = panel.GetScale and panel:GetScale() or 1
        local ph = UIParent:GetHeight() or 0
        if scale and scale > 0 and math.abs(scale - 1) > 0.001 and ph > 200 and top > ph then
            left = left * scale
            top = top * scale
            pos.x, pos.y, pos.space = left, top, "parent"
        end
    end
    local ps = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not ps or ps <= 0 then ps = 1 end
    TaskTracker.PinPanelScreenTopLeft(panel, left * ps, top * ps)
    if TaskTracker.NudgePanelOnScreen then
        TaskTracker.NudgePanelOnScreen(panel)
    end
end

local function ScreenTopLeft(panel)
    local left, top = panel:GetLeft(), panel:GetTop()
    if not left or not top then return nil, nil end
    local es = panel.GetEffectiveScale and panel:GetEffectiveScale() or 1
    if not es or es <= 0 then es = 1 end
    return left * es, top * es
end

--- Put the visual top-left on these screen pixels. SetPoint on a scaled frame
--- misses by a factor of the scale, so repeat until the measured corner matches.
function TaskTracker.PinPanelScreenTopLeft(panel, screenLeft, screenTop)
    if not panel or not screenLeft or not screenTop or not UIParent then return end
    if panel.SetClampedToScreen then
        panel:SetClampedToScreen(false)
    end
    local ps = UIParent:GetEffectiveScale() or 1
    if ps <= 0 then ps = 1 end
    local function step(arg, target, got)
        local err = target - got
        if got * target > 0 and math.abs(got) > 1 and math.abs(target) > 1 then
            return arg * target / got
        end
        return arg + err
    end
    local sl, st = screenLeft, screenTop
    for _ = 1, 4 do
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sl / ps, st / ps)
        local gotL, gotT = ScreenTopLeft(panel)
        if not gotL or not gotT then return end
        if math.abs(screenLeft - gotL) < 0.5 and math.abs(screenTop - gotT) < 0.5 then return end
        sl = step(sl, screenLeft, gotL)
        st = step(st, screenTop, gotT)
    end
end

--- Shift only as far as needed so the panel stays on screen. Top-left stays put when it fits.
function TaskTracker.NudgePanelOnScreen(panel)
    if not panel or not UIParent then return end
    local sl, st = ScreenTopLeft(panel)
    if not sl or not st then return end
    local es = panel:GetEffectiveScale() or 1
    local ps = UIParent:GetEffectiveScale() or 1
    local w = (panel:GetWidth() or 0) * es
    local h = (panel:GetHeight() or 0) * es
    local pw = (UIParent:GetWidth() or 0) * ps
    local ph = (UIParent:GetHeight() or 0) * ps
    local nl, nt = sl, st
    if nl < 0 then nl = 0 end
    if nt > ph then nt = ph end
    if w < pw and nl + w > pw then nl = pw - w end
    if h < ph and nt - h < 0 then nt = h end
    if math.abs(nl - sl) > 1 or math.abs(nt - st) > 1 then
        TaskTracker.PinPanelScreenTopLeft(panel, nl, nt)
    end
end

function TaskTracker.ScheduleRestorePanelPosition()
    local panel = TaskTracker.panel
    if panel then
        TaskTracker.RestorePanelPosition(panel)
    end
    if TaskTracker._ttPosRestoreTimer then
        TaskTracker._ttPosRestoreTimer:Cancel()
        TaskTracker._ttPosRestoreTimer = nil
    end
    TaskTracker._ttPosRestoreTimer = C_Timer.NewTimer(0, function()
        TaskTracker._ttPosRestoreTimer = nil
        local p = TaskTracker.panel
        if not p then return end
        TaskTracker.RestorePanelPosition(p)
        if IsPlayerInWorld() then
            TaskTracker._ttPosSaveLocked = nil
        end
    end)
end

function TaskTracker.CreateMainPanel()
    -- Hold position writes until the screen is real. The temporary TOP anchor
    -- otherwise gets stored and the next load opens at the top.
    TaskTracker._ttPosSaveLocked = true
    local db = TaskTrackerDB
    local w  = (db and db.panelWidth) or DEFAULT_PANEL_WIDTH
    local h  = (db and db.panelHeight) or DEFAULT_PANEL_HEIGHT
    TaskTracker.PANEL_WIDTH  = w
    TaskTracker.PANEL_HEIGHT = h

    local panel = TaskTracker.MakePanel("TaskTrackerPanel", UIParent, w, h)
    TaskTracker.panel = panel
    if panel.SetClampedToScreen then
        panel:SetClampedToScreen(false)
    end
    -- New frames start shown at an unset/default point. Hide before layout so a
    -- theme rebuild cannot flash or save the spawn position.
    panel:Hide()

    -- Temporary default; saved position is applied after scale (scale origin is bottom-left).
    panel:SetPoint("TOP", UIParent, "TOP", 0, -100)

    -- Move by dragging the title bar only (not the list body)
    panel:RegisterForDrag()
    panel:SetScript("OnDragStart", nil)
    panel:SetScript("OnDragStop", nil)

    panel:SetResizable(true)
    panel:SetResizeBounds(200, 220, 900, 900)

    local titleBar = panel.titleBar
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")

    local dragWatch = CreateFrame("Frame", nil, panel)
    dragWatch:Hide()
    local function FinishPanelDrag()
        if not panel._ttDragManual then return end
        local ox, oy = panel._ttDragOX, panel._ttDragOY
        panel._ttDragManual = nil
        dragWatch:Hide()
        dragWatch:SetScript("OnUpdate", nil)
        if ox and oy then
            local x, y = GetCursorPosition()
            if x and y then
                TaskTracker.PinPanelScreenTopLeft(panel, x - ox, y - oy)
            end
        end
        if TaskTracker.NudgePanelOnScreen then
            TaskTracker.NudgePanelOnScreen(panel)
        end
        TaskTracker.SavePanelPosition(panel)
        if TaskTracker.UpdateNoteWindowAnchor then
            TaskTracker.UpdateNoteWindowAnchor()
        end
    end
    titleBar:SetScript("OnDragStart", function()
        TaskTracker._ttPosSaveLocked = nil
        if panel.SetClampedToScreen then
            panel:SetClampedToScreen(false)
        end
        local cx, cy = GetCursorPosition()
        local sl, st = ScreenTopLeft(panel)
        if not sl or not st or not cx or not cy then
            panel._ttDragManual = nil
            panel:StartMoving()
            return
        end
        panel._ttDragOX = cx - sl
        panel._ttDragOY = cy - st
        panel._ttDragManual = true
        dragWatch:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then
                FinishPanelDrag()
                return
            end
            local x, y = GetCursorPosition()
            TaskTracker.PinPanelScreenTopLeft(panel, x - panel._ttDragOX, y - panel._ttDragOY)
        end)
        dragWatch:Show()
    end)
    titleBar:SetScript("OnDragStop", function()
        if panel._ttDragManual then
            FinishPanelDrag()
        else
            panel:StopMovingOrSizing()
            TaskTracker.SavePanelPosition(panel)
            if TaskTracker.UpdateNoteWindowAnchor then
                TaskTracker.UpdateNoteWindowAnchor()
            end
        end
    end)

    local function CancelPanelResizeRefreshTimer()
        if TaskTracker._panelResizeRefreshTimer then
            TaskTracker._panelResizeRefreshTimer:Cancel()
            TaskTracker._panelResizeRefreshTimer = nil
        end
    end

    local function SchedulePanelListRefresh()
        if not TaskTrackerDB or TaskTrackerDB.minimized then return end
        CancelPanelResizeRefreshTimer()
        TaskTracker._panelResizeRefreshTimer = C_Timer.NewTimer(0.1, function()
            TaskTracker._panelResizeRefreshTimer = nil
            if TaskTracker.RefreshList then
                TaskTracker.RefreshList()
            end
        end)
    end

    panel:SetScript("OnSizeChanged", function(self)
        if not TaskTrackerDB or TaskTrackerDB.minimized then return end
        local nw = math.floor(self:GetWidth() + 0.5)
        local nh = math.floor(self:GetHeight() + 0.5)
        TaskTrackerDB.panelWidth  = nw
        TaskTrackerDB.panelHeight = nh
        TaskTracker.PANEL_WIDTH     = nw
        TaskTracker.PANEL_HEIGHT    = nh
        if TaskTracker.scrollChild then
            TaskTracker.scrollChild:SetWidth(math.max(40, nw - TaskTracker.GetScrollGutter()))
        end
        if TaskTracker.UpdateNoteWindowAnchor then
            TaskTracker.UpdateNoteWindowAnchor()
        end
        if TaskTracker.MarkListLayoutDirty then
            TaskTracker.MarkListLayoutDirty()
        end
        SchedulePanelListRefresh()
    end)

    -- Bottom-right resize corner (L-shaped lines; hit box a bit larger than the art)
    local GRIP_SIZE  = 18
    local LINE_THICK = 2
    local LINE_LEN   = 11

    local grip = CreateFrame("Button", nil, panel)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(panel:GetFrameLevel() + 25)

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

    local resizing = false
    local function EndResizeSizing()
        if not resizing then
            grip:SetScript("OnUpdate", nil)
            return
        end
        resizing = false
        panel:StopMovingOrSizing()
        grip:SetScript("OnUpdate", nil)
        CancelPanelResizeRefreshTimer()
        if TaskTracker.NudgePanelOnScreen then
            TaskTracker.NudgePanelOnScreen(panel)
        end
        TaskTracker.SavePanelPosition(panel)
        if TaskTrackerDB and not TaskTrackerDB.minimized and TaskTracker.RefreshList then
            TaskTracker.RefreshList()
        end
        if TaskTracker.scrollFrame and TaskTracker.scrollFrame.UpdateScrollBar then
            TaskTracker.scrollFrame.UpdateScrollBar()
        end
    end

    grip:SetScript("OnEnter", function()
        SetGripLineAlpha(0.9)
    end)
    grip:SetScript("OnLeave", function()
        SetGripLineAlpha(0.55)
    end)
    grip:SetScript("OnHide", function()
        EndResizeSizing()
    end)
    -- StartSizing keeps capture; OnMouseUp often never fires on this small button once
    -- the cursor has moved, so poll until the left button is released.
    grip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and TaskTrackerDB and not TaskTrackerDB.minimized then
            TaskTracker._ttPosSaveLocked = nil
            resizing = true
            panel:StartSizing("BOTTOMRIGHT")
            self:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then
                    EndResizeSizing()
                end
            end)
        end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            EndResizeSizing()
        end
    end)

    TaskTracker.resizeGrip = grip
    if TaskTrackerDB.minimized then
        grip:Hide()
    end

    panel:Hide()
    panel.TitleText:SetText("Task Tracker")

    BuildTitleButtons(panel, panel.titleBar)
    BuildScrollArea(panel)

    local prevOnHide = panel:GetScript("OnHide")
    panel:SetScript("OnHide", function(self)
        TaskTracker.ExitEditModeOnHide()
        HideTrackerHelpIfOpen()
        if TaskTracker.HideNoteWindow then
            TaskTracker.HideNoteWindow()
        end
        TaskTracker.HideQuickCommandsPanel()
        if TaskTracker.HideListExpandMenu then
            TaskTracker.HideListExpandMenu()
        end
        if prevOnHide then
            prevOnHide(self)
        end
    end)
    local prevOnShow = panel:GetScript("OnShow")
    panel:SetScript("OnShow", function(self)
        if TaskTracker.ScheduleRestorePanelPosition then
            TaskTracker.ScheduleRestorePanelPosition()
        elseif TaskTracker.RestorePanelPosition then
            TaskTracker.RestorePanelPosition(self)
        end
        if prevOnShow then
            prevOnShow(self)
        end
    end)

    -- Dialogs
    TaskTracker.taskDialog  = TaskTracker.CreateTaskDialog()
    TaskTracker.groupDialog = TaskTracker.CreateGroupDialog()
    TaskTracker.noteWindow     = TaskTracker.CreateNoteWindow()
    TaskTracker.notePeekWindow = TaskTracker.CreateNotePeekWindow()

    -- Options panel
    TaskTracker.optionsPanel = TaskTracker.CreateOptionsPanel(panel)

    TaskTracker.ScheduleRefreshListWhenInWorld()
    TaskTracker.ApplyUIScale()
    if TaskTrackerDB.minimized then
        TaskTracker.SetMinimized(true)
    end
end
