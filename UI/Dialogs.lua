-- UI/Dialogs.lua
-- Task dialog and Group dialog using theme system

TaskTracker = TaskTracker or {}

local function openTaskShareImportExport(dialog)
    TaskTracker.OpenShareImportExportDialog({
        title = "Share task",
        hint = "Export fills the box (Ctrl+C). Newer clients save a short compressed line; plain TASKTRACKER_SHARE_V1 text still works. Paste and Import adds a copy next to this task or at the end of the group (when adding). Progress resets.",
        focusExportSelect = dialog._shareExportNode ~= nil,
        getExportText = function()
            if dialog._shareExportNode then
                return TaskTracker.ExportNodeToString(dialog._shareExportNode)
            end
        end,
        onImport = function(kind, node)
            local ctx = dialog._shareImportCtx
            if not ctx then return "Dialog not ready." end
            if kind ~= "task" then
                return "This window only imports tasks. Use the group window for a group export."
            end
            if ctx.mode == "add" then
                if not ctx.parentGroupId then return "No parent group." end
                if not TaskTracker.InsertNodeAsLastChild(ctx.parentGroupId, node) then
                    return "Could not insert task."
                end
            elseif ctx.mode == "edit" then
                if not ctx.refNodeId then return "No task reference." end
                if not TaskTracker.InsertNodeAfterSibling(node, ctx.refNodeId) then
                    return "Could not insert task."
                end
            else
                return "Unknown import context."
            end
            return nil
        end,
    })
end

local function attachTaskDialogShareMailbox(dialog)
    local helpBtn = TaskTracker.AttachHelpButton(dialog.titleBar, dialog.CloseButton, "newTask")
    local shareBtn = TaskTracker.MakeIconButton(dialog.titleBar, 20, 20, TaskTracker.ChromeIconOpt())
    shareBtn:SetPoint("RIGHT", helpBtn, "LEFT", -3, 0)
    TaskTracker.SetShareMailboxIcon(shareBtn)
    shareBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Import / export", 1, 1, 1)
        GameTooltip:AddLine("Copy or paste a task definition to share with another account. Progress is not included.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    shareBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    shareBtn:SetScript("OnClick", function()
        openTaskShareImportExport(dialog)
    end)
end

local function openGroupShareImportExport(dialog)
    TaskTracker.OpenShareImportExportDialog({
        title = "Share group",
        hint = "Exports are compressed to one line when supported; plain text exports from older builds still import. Use Fill export when editing a group, or paste and Import.",
        focusExportSelect = dialog._shareExportNode ~= nil,
        getExportText = function()
            if dialog._shareExportNode then
                return TaskTracker.ExportNodeToString(dialog._shareExportNode)
            end
        end,
        onImport = function(kind, node)
            local ctx = dialog._shareImportCtx
            if not ctx then return "Dialog not ready." end
            if kind == "group" then
                if ctx.mode == "new" then
                    if ctx.afterSiblingId then
                        if not TaskTracker.InsertNodeAfterSibling(node, ctx.afterSiblingId) then
                            return "Could not insert group."
                        end
                    else
                        if not TaskTracker.InsertNodeAsLastChild(ctx.parentId, node) then
                            return "Could not insert group."
                        end
                    end
                elseif ctx.mode == "edit" then
                    if not ctx.groupNodeId then return "No group reference." end
                    if not TaskTracker.InsertNodeAfterSibling(node, ctx.groupNodeId) then
                        return "Could not insert group."
                    end
                else
                    return "Unknown import context."
                end
                return nil
            elseif kind == "task" then
                if ctx.mode == "edit" and ctx.groupNodeId then
                    if not TaskTracker.InsertNodeAsLastChild(ctx.groupNodeId, node) then
                        return "Could not insert task into group."
                    end
                    return nil
                elseif ctx.mode == "new" then
                    local parent = TaskTracker.FindNode(ctx.parentId)
                    if parent and parent.type == "group" then
                        if not TaskTracker.InsertNodeAsLastChild(ctx.parentId, node) then
                            return "Could not insert task."
                        end
                        return nil
                    end
                    return "Import a group from this screen, or open Add task under a group to import a task."
                end
            end
            return "Unsupported export."
        end,
    })
end

local function attachGroupDialogShareMailbox(dialog)
    local helpBtn = TaskTracker.AttachHelpButton(dialog.titleBar, dialog.CloseButton, "newGroup")
    local shareBtn = TaskTracker.MakeIconButton(dialog.titleBar, 20, 20, TaskTracker.ChromeIconOpt())
    shareBtn:SetPoint("RIGHT", helpBtn, "LEFT", -3, 0)
    TaskTracker.SetShareMailboxIcon(shareBtn)
    shareBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Import / export", 1, 1, 1)
        GameTooltip:AddLine("Copy or paste a group (and its tasks) to share with another account. Registry rows are not included.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    shareBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    shareBtn:SetScript("OnClick", function()
        openGroupShareImportExport(dialog)
    end)
end

-- ─────────────────────────────────────
-- Shared dialog builder
-- ─────────────────────────────────────
local function MakeDialog(frameName, width, height)
    local t      = TaskTracker.GetTheme()
    local dialog = TaskTracker.MakePanel(frameName, UIParent, width, height)
    if TaskTracker.AnchorFrameNearScreenTop then
        TaskTracker.AnchorFrameNearScreenTop(dialog, 0, 0.12)
    else
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    dialog:SetFrameStrata("DIALOG")
    dialog:Hide()

    dialog.CloseButton:SetScript("OnClick", function() dialog:Hide() end)

    return dialog, dialog.Content, t
end

local dialogLabelColor = "textSecondary"

local function MakeLabel(parent, text, anchorFrame, anchorPoint, xOff, yOff, colorKey)
    local t   = TaskTracker.GetTheme()
    local lbl = TaskTracker.CreateFontString(parent, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", anchorFrame, anchorPoint or "BOTTOMLEFT", xOff or 0, yOff or -8)
    TaskTracker.SetTextColor(lbl, colorKey or dialogLabelColor)
    lbl:SetText(text)
    return lbl
end

local function MakeInput(parent, name, width, anchorFrame)
    local input
    if TaskTracker.MakeEditBox then
        input = TaskTracker.MakeEditBox(parent, name, width or 240, 20)
    else
        local t = TaskTracker.GetTheme()
        input = CreateFrame("EditBox", name, parent)
        input:SetSize(width or 240, 20)
        input:SetAutoFocus(false)
        input:SetFontObject(t.fontNormal or "GameFontNormalSmall")
        TaskTracker.ClearFontShadow(input)
        input:SetTextInsets(6, 6, 0, 0)
        input:SetMaxLetters(60)
        local bg = input:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        TaskTracker.SetColor(bg, "inputBg")
        TaskTracker.MakeBorder(input, "border")
    end
    input:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -6)

    if TaskTracker.RegisterLinkableEditBox then
        TaskTracker.RegisterLinkableEditBox(input)
    end

    return input
end

local function pinAdvPanelToContainer(panel, advContainer)
    if not panel or not advContainer then return end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", advContainer, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", advContainer, "BOTTOMRIGHT", 0, 0)
end

-- ─────────────────────────────────────
-- Progress editor (Shift-click on x/x): tracked + automated counts
-- ─────────────────────────────────────
local progressEditDialog

local function ensureProgressEditDialog()
    if progressEditDialog then
        return progressEditDialog
    end
    local d, content, t = MakeDialog("TaskTrackerProgressEdit", 400, 248)
    d:EnableMouse(true)
    content:EnableMouse(true)

    local barW = t.taskAutomationBarWidth or 3
    local fontSmall = t.fontNormal or "GameFontNormalSmall"

    local function makeRow(parent, anchorFrame, gapY, barColorKey, labelText)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(368, 46)
        row:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, gapY or -10)
        local bar = row:CreateTexture(nil, "ARTWORK")
        bar:SetSize(barW, 22)
        bar:SetPoint("LEFT", row, "LEFT", 0, 6)
        TaskTracker.SetColor(bar, barColorKey)
        local lab = TaskTracker.CreateFontString(row, nil, "OVERLAY", fontSmall)
        lab:SetPoint("TOPLEFT", bar, "TOPRIGHT", 10, 0)
        lab:SetWidth(240)
        lab:SetJustifyH("LEFT")
        TaskTracker.SetTextColor(lab, "textSecondary")
        lab:SetText(labelText)
        local eb
        if TaskTracker.MakeEditBox then
            eb = TaskTracker.MakeEditBox(row, nil, 96, 22)
        else
            eb = CreateFrame("EditBox", nil, row)
            eb:SetSize(96, 22)
            eb:SetAutoFocus(false)
            eb:SetFontObject(fontSmall)
            TaskTracker.ClearFontShadow(eb)
            eb:SetTextInsets(6, 6, 0, 0)
            eb:SetMaxLetters(12)
            local bgb = eb:CreateTexture(nil, "BACKGROUND")
            bgb:SetAllPoints()
            TaskTracker.SetColor(bgb, "inputBg")
            TaskTracker.MakeBorder(eb, "border")
        end
        eb:SetNumeric(true)
        eb:SetPoint("TOPLEFT", lab, "BOTTOMLEFT", 0, -4)
        row.bar, row.label, row.edit = bar, lab, eb
        return row
    end

    local hintFs = TaskTracker.CreateFontString(content, nil, "OVERLAY", fontSmall)
    hintFs:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -10)
    hintFs:SetWidth(370)
    hintFs:SetJustifyH("LEFT")
    TaskTracker.SetTextColor(hintFs, "textSecondary")

    local rowTracked = makeRow(content, hintFs, -12, "taskBarManual", "Tracked (what you see in the list)")
    local rowAuto = makeRow(content, rowTracked, -12, "taskBarAutomated", "Automated (game / sync tally)")

    local lockHost = CreateFrame("Frame", nil, content)
    lockHost:SetSize(368, 44)
    lockHost:SetPoint("TOPLEFT", rowAuto, "BOTTOMLEFT", 0, -10)
    lockHost:Hide()
    local lockLbl = TaskTracker.CreateFontString(lockHost, nil, "OVERLAY", fontSmall)
    lockLbl:SetPoint("TOPLEFT", lockHost, "TOPLEFT", 0, 0)
    lockLbl:SetJustifyH("LEFT")
    TaskTracker.SetTextColor(lockLbl, "textAccent")
    lockLbl:SetText("List count:")
    local lockBtn = TaskTracker.MakeButton(lockHost, "Locked", 110, 22)
    lockBtn:SetPoint("TOPLEFT", lockLbl, "BOTTOMLEFT", 0, -6)
    local autoLockBtn = TaskTracker.MakeButton(lockHost, "Automatic", 110, 22)
    autoLockBtn:SetPoint("LEFT", lockBtn, "RIGHT", 4, 0)
    local function tipLock(btn, title, body)
        btn:SetScript("OnEnter", function()
            if TaskTracker.ShowTipBesideFrame then
                TaskTracker.ShowTipBesideFrame(d, title, body)
            end
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    tipLock(lockBtn, "Locked", "The list keeps the tracked number.")
    tipLock(autoLockBtn, "Automatic", "The list follows the game tally.")
    local function paintLock()
        TaskTracker.SetExclusiveButtonActive({
            locked = lockBtn,
            auto = autoLockBtn,
        }, d._ttLockOn and "locked" or "auto")
    end
    lockBtn:SetScript("OnClick", function()
        d._ttLockOn = true
        paintLock()
    end)
    autoLockBtn:SetScript("OnClick", function()
        d._ttLockOn = false
        paintLock()
    end)

    local btnRow = CreateFrame("Frame", nil, content)
    btnRow:SetSize(368, 28)
    btnRow:SetPoint("TOPLEFT", rowAuto, "BOTTOMLEFT", 0, -14)
    local setBtn = TaskTracker.MakeButton(btnRow, "Set", 120, 24)
    setBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
    local cancelBtn = TaskTracker.MakeButton(btnRow, "Cancel", 120, 24)
    cancelBtn:SetPoint("LEFT", setBtn, "RIGHT", 10, 0)

    local function parseEb(eb)
        local txt = eb and eb:GetText() or ""
        txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
        return tonumber(txt)
    end

    local function applyClose()
        d._ttPopState = nil
        d:Hide()
    end

    local function applyAccept()
        local st = d._ttPopState
        if not st or type(st.onAccept) ~= "function" then
            applyClose()
            return
        end
        local tv = parseEb(rowTracked.edit)
        local av = parseEb(rowAuto.edit)
        if tv == nil or av == nil then
            return
        end
        tv = math.floor(tv + 0.00001)
        av = math.floor(av + 0.00001)
        local mx = tonumber(st.max) or 0
        if tv < 0 then tv = 0 end
        if av < 0 then av = 0 end
        if not st.allowOverMax and mx > 0 and tv > mx then tv = mx end
        if not st.allowOverMax and mx > 0 and av > mx then av = mx end
        local locked = nil
        if d._ttShowLock then
            locked = d._ttLockOn and true or false
        end
        st.onAccept(tv, av, locked)
        applyClose()
    end

    setBtn:SetScript("OnClick", applyAccept)
    cancelBtn:SetScript("OnClick", applyClose)
    d.CloseButton:SetScript("OnClick", applyClose)

    local function onEnter(self)
        applyAccept()
    end
    rowTracked.edit:SetScript("OnEnterPressed", onEnter)
    rowAuto.edit:SetScript("OnEnterPressed", onEnter)
    rowTracked.edit:SetScript("OnEscapePressed", applyClose)
    rowAuto.edit:SetScript("OnEscapePressed", applyClose)

    d:SetScript("OnHide", function()
        if rowTracked.edit.ClearFocus then rowTracked.edit:ClearFocus() end
        if rowAuto.edit.ClearFocus then rowAuto.edit:ClearFocus() end
    end)

    local function layoutLock(show)
        d._ttShowLock = show and true or false
        btnRow:ClearAllPoints()
        if show then
            lockHost:Show()
            paintLock()
            btnRow:SetPoint("TOPLEFT", lockHost, "BOTTOMLEFT", 0, -14)
            d:SetHeight(304)
        else
            lockHost:Hide()
            btnRow:SetPoint("TOPLEFT", rowAuto, "BOTTOMLEFT", 0, -14)
            d:SetHeight(248)
        end
    end
    d._ttLayoutLock = layoutLock
    d._ttRowT = rowTracked
    d._ttRowA = rowAuto
    d._ttHintFs = hintFs
    d:Hide()
    progressEditDialog = d
    return d
end

function TaskTracker.ShowSetCountPopup(opts)
    if type(opts) ~= "table" then return end
    local title = opts.title or "Set progress"
    local cur = tonumber(opts.cur) or 0
    local autoCur = opts.autoCur
    if autoCur == nil then autoCur = cur end
    autoCur = tonumber(autoCur) or 0
    local max = tonumber(opts.max) or 0
    local onAccept = opts.onAccept
    if type(onAccept) ~= "function" then return end
    local allowOverMax = opts.allowOverMax and true or false

    local d = ensureProgressEditDialog()
    d.TitleText:SetText(title)
    local hint
    if max > 0 then
        hint = allowOverMax
            and ("Goal " .. tostring(max) .. ". Tracked and automated may exceed the goal for this task type.")
            or ("Goal " .. tostring(max) .. ". Both fields clamp to 0-" .. tostring(max) .. ".")
    else
        hint = "Enter non-negative numbers."
    end
    d._ttHintFs:SetText(hint)
    d._ttPopState = {
        max = max,
        allowOverMax = allowOverMax,
        onAccept = onAccept,
    }
    local showLock, locked = false, false
    if opts.node and TaskTracker.ProgressEditLockState then
        showLock, locked = TaskTracker.ProgressEditLockState(opts.node, opts.slot)
    end
    d._ttLockOn = locked and true or false
    if d._ttLayoutLock then
        d._ttLayoutLock(showLock)
    end

    local rT, rA = d._ttRowT, d._ttRowA
    rT.edit:SetText(tostring(cur))
    rA.edit:SetText(tostring(autoCur))
    rT.edit:SetAutoFocus(true)
    rT.edit:HighlightText()
    d:Show()
    rT.edit:SetFocus()
end

--- Achievement advanced-task controls (separate function: WoW Lua limits locals per function).
local function CreateTaskDialogAchievementUi(advContainer)
    local state = { criteriaSel = nil, critTrackMode = "weekly" }

    local optAch = CreateFrame("Frame", nil, advContainer)
    optAch:SetPoint("TOPLEFT", advContainer, "TOPLEFT", 0, 0)
    optAch:SetPoint("BOTTOMRIGHT", advContainer, "BOTTOMRIGHT", 0, 0)
    optAch:Hide()
    local achLbl = MakeLabel(optAch, "Achievement (id or shift-click link):", optAch, "TOPLEFT", 0, 0)
    local achIdInput = MakeInput(optAch, "TTAchId", 234, achLbl)
    achIdInput:SetMaxLetters(200)
    local achCheckBtn = TaskTracker.MakeIconButton(optAch, 20, 20, { normalBgKey = "headerBg", hoverBgKey = "accentBg" })
    achCheckBtn:SetPoint("LEFT", achIdInput, "RIGHT", 6, 0)
    achCheckBtn:SetIconAtlas(TaskTracker.FirstValidAtlas("Tracker-Check", "common-icon-checkmark", "common-icon-check"), true)

    local achWeekLbl, achWeekInput
    local achCritTrackLbl, achCritTrackWeeklyBtn, achCritTrackGameBtn

    local ACH_CRIT_ROW_H = 18
    local ACH_CRIT_ROW_GAP = 2
    local ACH_CRIT_MENU_MAX_ROWS = 8
    local ACH_CRIT_BASE_LABEL = "Base achievement (all criteria)"

    local achCriteriaLbl = MakeLabel(optAch, "Goal (criteria):", achIdInput, "BOTTOMLEFT", 0, -8)
    achCriteriaLbl:Hide()
    local achCriteriaBtn = TaskTracker.MakeButton(optAch, "Select goal…", 260, 20)
    TaskTracker.AttachDropdownArrow(achCriteriaBtn)
    achCriteriaBtn:SetPoint("TOPLEFT", achCriteriaLbl, "BOTTOMLEFT", 0, -6)
    achCriteriaBtn:SetScript("OnEnter", nil)
    achCriteriaBtn:SetScript("OnLeave", nil)
    achCriteriaBtn:Hide()

    local achCriteriaMenu = CreateFrame("Frame", nil, optAch)
    if TaskTracker.RegisterOpenDropdown then TaskTracker.RegisterOpenDropdown(achCriteriaMenu) end
    achCriteriaMenu:SetSize(260, 120)
    achCriteriaMenu:SetPoint("TOPLEFT", achCriteriaBtn, "BOTTOMLEFT", 0, -2)
    achCriteriaMenu:SetFrameLevel((achCriteriaBtn:GetFrameLevel() or 0) + 20)
    TaskTracker.MakeBorder(achCriteriaMenu, "border")
    local achCriteriaMenuBg = achCriteriaMenu:CreateTexture(nil, "BACKGROUND")
    achCriteriaMenuBg:SetAllPoints()
    TaskTracker.SetColor(achCriteriaMenuBg, "inputBg")
    achCriteriaMenu:EnableMouse(true)
    achCriteriaMenu:Hide()

    local achCriteriaScroll = CreateFrame("ScrollFrame", nil, achCriteriaMenu)
    achCriteriaScroll:SetPoint("TOPLEFT", achCriteriaMenu, "TOPLEFT", 4, -4)
    achCriteriaScroll:SetPoint("BOTTOMRIGHT", achCriteriaMenu, "BOTTOMRIGHT", -8, 4)
    local achCriteriaScrollChild = CreateFrame("Frame", nil, achCriteriaScroll)
    achCriteriaScroll:SetScrollChild(achCriteriaScrollChild)
    TaskTracker.MakeScrollBar(achCriteriaScroll, achCriteriaMenu)

    local achCriteriaRows = {}

    local function clearAchCriteriaRows()
        for _, r in pairs(achCriteriaRows) do
            r:Hide()
            r:SetParent(nil)
        end
        wipe(achCriteriaRows)
    end

    local function refreshAchCriteriaRowStyles()
        for idx, row in pairs(achCriteriaRows) do
            TaskTracker.SetButtonActive(row, state.criteriaSel == idx)
        end
    end

    achCritTrackLbl = MakeLabel(optAch, "Progress mode:", achCriteriaBtn, "BOTTOMLEFT", 0, -10)
    achCritTrackLbl:Hide()
    achCritTrackWeeklyBtn = TaskTracker.MakeButton(optAch, "Weekly target", 124, 20)
    achCritTrackGameBtn = TaskTracker.MakeButton(optAch, "In-game bar", 124, 20)
    achCritTrackWeeklyBtn:SetPoint("TOPLEFT", achCritTrackLbl, "BOTTOMLEFT", 0, -6)
    achCritTrackGameBtn:SetPoint("LEFT", achCritTrackWeeklyBtn, "RIGHT", 4, 0)
    for _, b in ipairs({ achCritTrackWeeklyBtn, achCritTrackGameBtn }) do
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
        b:Hide()
    end

    achWeekLbl = MakeLabel(optAch, "Weekly goal (points):", achCritTrackWeeklyBtn, "BOTTOMLEFT", 0, -10)
    achWeekLbl:Hide()
    achWeekInput = MakeInput(optAch, "TTAchWeek", 80, achWeekLbl)
    achWeekInput:SetMaxLetters(6)
    achWeekInput:SetText("100")
    achWeekInput:Hide()

    local function refreshAchCritTrackBtnStyles()
        TaskTracker.SetExclusiveButtonActive({
            weekly = achCritTrackWeeklyBtn,
            game = achCritTrackGameBtn,
        }, state.critTrackMode)
    end

    local function syncAchWeekFieldsForCriteriaMode()
        if not achWeekLbl or not achWeekInput then return end
        local isBase = ((tonumber(state.criteriaSel) or 0) == 0)
        if isBase then
            achCritTrackLbl:Hide()
            achCritTrackWeeklyBtn:Hide()
            achCritTrackGameBtn:Hide()
            achWeekLbl:Hide()
            achWeekInput:Hide()
        else
            achCritTrackLbl:Show()
            achCritTrackWeeklyBtn:Show()
            achCritTrackGameBtn:Show()
            if state.critTrackMode == "game" then
                achWeekLbl:Hide()
                achWeekInput:Hide()
            else
                achWeekLbl:Show()
                achWeekInput:Show()
            end
        end
        refreshAchCritTrackBtnStyles()
    end

    achCritTrackWeeklyBtn:SetScript("OnClick", function()
        state.critTrackMode = "weekly"
        syncAchWeekFieldsForCriteriaMode()
    end)
    achCritTrackGameBtn:SetScript("OnClick", function()
        state.critTrackMode = "game"
        syncAchWeekFieldsForCriteriaMode()
    end)
    refreshAchCritTrackBtnStyles()

    local function buildAchievementCriteriaList(achId, preferredCriteriaIndex)
        clearAchCriteriaRows()
        achCriteriaMenu:Hide()
        achCriteriaScroll:SetVerticalScroll(0)
        if not achId or not GetAchievementNumCriteria then
            achCriteriaLbl:Hide()
            achCriteriaBtn:Hide()
            syncAchWeekFieldsForCriteriaMode()
            return
        end
        local n = GetAchievementNumCriteria(achId) or 0
        if n <= 0 then
            achCriteriaLbl:Hide()
            achCriteriaBtn:Hide()
            syncAchWeekFieldsForCriteriaMode()
            return
        end
        achCriteriaLbl:Show()
        achCriteriaBtn:Show()

        local rowCount = n + 1
        local contentH = 8 + rowCount * ACH_CRIT_ROW_H + math.max(0, rowCount - 1) * ACH_CRIT_ROW_GAP
        local viewCapH = 8 + ACH_CRIT_MENU_MAX_ROWS * ACH_CRIT_ROW_H + math.max(0, ACH_CRIT_MENU_MAX_ROWS - 1) * ACH_CRIT_ROW_GAP
        local menuH = math.min(viewCapH, contentH)
        achCriteriaMenu:SetHeight(menuH)
        achCriteriaScrollChild:SetSize(244, math.max(contentH, menuH))

        local nextCritRowPos = 0
        local function addRow(idx, critLabel)
            local y = -4 - nextCritRowPos * (ACH_CRIT_ROW_H + ACH_CRIT_ROW_GAP)
            nextCritRowPos = nextCritRowPos + 1
            local row = TaskTracker.MakeButton(achCriteriaScrollChild, critLabel, 236, ACH_CRIT_ROW_H)
            row:SetPoint("TOPLEFT", achCriteriaScrollChild, "TOPLEFT", 4, y)
            row:SetScript("OnEnter", function()
                TaskTracker.SetColor(row.bg, "accentBg")
                TaskTracker.SetTextColor(row.label, "textAccent")
            end)
            row:SetScript("OnLeave", function()
                refreshAchCriteriaRowStyles()
            end)
            row:SetScript("OnClick", function()
                state.criteriaSel = idx
                achCriteriaBtn:SetLabel(critLabel)
                achCriteriaMenu:Hide()
                refreshAchCriteriaRowStyles()
                syncAchWeekFieldsForCriteriaMode()
            end)
            achCriteriaRows[idx] = row
        end

        addRow(0, ACH_CRIT_BASE_LABEL)
        for i = 1, n do
            local critString
            for _, hidden in ipairs({ true, false }) do
                local ok, cs = pcall(GetAchievementCriteriaInfo, achId, i, hidden)
                if ok and type(cs) == "string" and cs ~= "" then
                    critString = cs
                    break
                end
            end
            critString = critString or ("Criteria " .. tostring(i))
            addRow(i, critString)
        end

        local want = preferredCriteriaIndex
        if want ~= nil and achCriteriaRows[want] then
            state.criteriaSel = want
        else
            state.criteriaSel = 0
        end
        local selRow = achCriteriaRows[state.criteriaSel]
        achCriteriaBtn:SetLabel((selRow and selRow.label and selRow.label:GetText()) or ACH_CRIT_BASE_LABEL)
        refreshAchCriteriaRowStyles()
        syncAchWeekFieldsForCriteriaMode()
        if achCriteriaScroll.UpdateScrollBar then
            achCriteriaScroll:UpdateScrollBar()
        end
    end

    achCriteriaBtn:SetScript("OnClick", function()
        if achCriteriaMenu:IsShown() then
            achCriteriaMenu:Hide()
        else
            achCriteriaMenu:Show()
            achCriteriaMenu:Raise()
            if achCriteriaScroll.UpdateScrollBar then
                achCriteriaScroll:UpdateScrollBar()
            end
        end
    end)

    achCheckBtn:SetScript("OnClick", function()
        local msg = TaskTracker.BuildAchievementInputValidationMessage(achIdInput:GetText())
        StaticPopupDialogs["TASKTRACKER_ACH_VALIDATE"] = {
            text         = msg,
            button1      = "OK",
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("TASKTRACKER_ACH_VALIDATE")
        local id = TaskTracker.ParseAchievementIdFromText(achIdInput:GetText())
        if id and id > 0 then
            buildAchievementCriteriaList(id)
        else
            clearAchCriteriaRows()
            achCriteriaMenu:Hide()
            achCriteriaLbl:Hide()
            achCriteriaBtn:Hide()
            state.criteriaSel = nil
            syncAchWeekFieldsForCriteriaMode()
        end
    end)

    local function resetForm()
        achIdInput:SetText("")
        achWeekInput:SetText("100")
        state.critTrackMode = "weekly"
        state.criteriaSel = nil
        clearAchCriteriaRows()
        achCriteriaScroll:SetVerticalScroll(0)
        achCriteriaMenu:Hide()
        achCriteriaLbl:Hide()
        achCriteriaBtn:Hide()
        refreshAchCritTrackBtnStyles()
        syncAchWeekFieldsForCriteriaMode()
    end

    local function loadFromNode(node, a)
        state.critTrackMode = (a.achievementMirrorGameTotals == true) and "game" or "weekly"
        achIdInput:SetText(tostring(a.achievementId or ""))
        achWeekInput:SetText(tostring(node.taskMax or 1))
        local critPick = tonumber(a.achievementCriteriaIndex)
        if critPick == nil then critPick = 0 end
        local id = tonumber(a.achievementId)
        if id and id > 0 then
            buildAchievementCriteriaList(id, critPick)
        end
    end

    local function collect(adv)
        adv.achievementId = TaskTracker.ParseAchievementIdFromText(achIdInput:GetText()) or 0
        adv.achievementCriteriaIndex = tonumber(state.criteriaSel) or 0
        local critIx = adv.achievementCriteriaIndex
        local mirror = critIx ~= 0 and state.critTrackMode == "game"
        local tm = 1
        if critIx == 0 then
            adv.achievementMirrorGameTotals = nil
            local aid = tonumber(adv.achievementId)
            local nc = (aid and GetAchievementNumCriteria(aid)) or 0
            tm = math.max(1, nc)
        elseif mirror then
            adv.achievementMirrorGameTotals = true
            local aid = tonumber(adv.achievementId)
            if aid and critIx >= 1 and TaskTracker.GetAchievementCriterionCurMax then
                local _, mx = TaskTracker.GetAchievementCriterionCurMax(aid, critIx)
                tm = math.max(1, tonumber(mx) or 1)
            else
                tm = 1
            end
        else
            adv.achievementMirrorGameTotals = false
            tm = tonumber(achWeekInput:GetText()) or 1
            if tm < 1 then tm = 1 end
        end
        return tm
    end

    return {
        optAch = optAch,
        achIdInput = achIdInput,
        achWeekInput = achWeekInput,
        state = state,
        buildCriteriaList = buildAchievementCriteriaList,
        syncWeekFields = syncAchWeekFieldsForCriteriaMode,
        resetForm = resetForm,
        loadFromNode = loadFromNode,
        collect = collect,
    }
end

local function CreateTaskDialogGoldUi(advContainer)
    local state = {
        goldModeSel = "net",
        goldResetSource = "inherit",
        goldResetOverride = "none",
    }

    local optGold = CreateFrame("Frame", nil, advContainer)
    pinAdvPanelToContainer(optGold, advContainer)
    optGold:Hide()
    local gGoalLbl = MakeLabel(optGold, "Goal (gold):", optGold, "TOPLEFT", 0, 0)
    local goldGoalInput = MakeInput(optGold, "TTGoldGoal", 100, gGoalLbl)
    goldGoalInput:SetMaxLetters(12)
    goldGoalInput:SetText("1000")
    local gModeLbl = MakeLabel(optGold, "Tracking:", goldGoalInput, "BOTTOMLEFT", 0, -10)
    local goldNetBtn = TaskTracker.MakeButton(optGold, "Net gain", 118, 20)
    local goldGrossBtn = TaskTracker.MakeButton(optGold, "Gross earned", 118, 20)
    goldNetBtn:SetPoint("TOPLEFT", gModeLbl, "BOTTOMLEFT", 0, -6)
    goldGrossBtn:SetPoint("LEFT", goldNetBtn, "RIGHT", 4, 0)
    goldNetBtn:SetScript("OnEnter", nil)
    goldNetBtn:SetScript("OnLeave", nil)
    goldGrossBtn:SetScript("OnEnter", nil)
    goldGrossBtn:SetScript("OnLeave", nil)
    local function updateGoldModeBtns()
        TaskTracker.SetExclusiveButtonActive({ net = goldNetBtn, gross = goldGrossBtn }, state.goldModeSel)
    end
    goldNetBtn:SetScript("OnClick", function() state.goldModeSel = "net" updateGoldModeBtns() end)
    goldGrossBtn:SetScript("OnClick", function() state.goldModeSel = "gross" updateGoldModeBtns() end)
    updateGoldModeBtns()
    local gResLbl = MakeLabel(optGold, "Gold counter reset:", goldNetBtn, "BOTTOMLEFT", 0, -10)
    local goldInheritBtn = TaskTracker.MakeButton(optGold, "Inherit task reset", 124, 20)
    local goldOverrideBtn = TaskTracker.MakeButton(optGold, "Override…", 124, 20)
    goldInheritBtn:SetPoint("TOPLEFT", gResLbl, "BOTTOMLEFT", 0, -6)
    goldOverrideBtn:SetPoint("LEFT", goldInheritBtn, "RIGHT", 4, 0)
    goldInheritBtn:SetScript("OnEnter", nil)
    goldInheritBtn:SetScript("OnLeave", nil)
    goldOverrideBtn:SetScript("OnEnter", nil)
    goldOverrideBtn:SetScript("OnLeave", nil)
    local goldOvNone = TaskTracker.MakeButton(optGold, "None", 58, 18)
    local goldOvDaily = TaskTracker.MakeButton(optGold, "Daily", 58, 18)
    local goldOvWeekly = TaskTracker.MakeButton(optGold, "Weekly", 58, 18)
    goldOvNone:SetPoint("TOPLEFT", goldInheritBtn, "BOTTOMLEFT", 0, -6)
    goldOvDaily:SetPoint("LEFT", goldOvNone, "RIGHT", 4, 0)
    goldOvWeekly:SetPoint("LEFT", goldOvDaily, "RIGHT", 4, 0)
    for _, b in ipairs({ goldOvNone, goldOvDaily, goldOvWeekly }) do
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
    end
    local function updateGoldResetSourceBtns()
        TaskTracker.SetExclusiveButtonActive({
            inherit = goldInheritBtn,
            override = goldOverrideBtn,
        }, state.goldResetSource)
        if state.goldResetSource == "inherit" then
            goldOvNone:Hide()
            goldOvDaily:Hide()
            goldOvWeekly:Hide()
        else
            goldOvNone:Show()
            goldOvDaily:Show()
            goldOvWeekly:Show()
            TaskTracker.SetExclusiveButtonActive({
                none = goldOvNone,
                daily = goldOvDaily,
                weekly = goldOvWeekly,
            }, state.goldResetOverride, { idleTextKey = "textSecondary" })
        end
    end
    goldInheritBtn:SetScript("OnClick", function()
        state.goldResetSource = "inherit"
        updateGoldResetSourceBtns()
    end)
    goldOverrideBtn:SetScript("OnClick", function()
        state.goldResetSource = "override"
        updateGoldResetSourceBtns()
    end)
    goldOvNone:SetScript("OnClick", function() state.goldResetOverride = "none" updateGoldResetSourceBtns() end)
    goldOvDaily:SetScript("OnClick", function() state.goldResetOverride = "daily" updateGoldResetSourceBtns() end)
    goldOvWeekly:SetScript("OnClick", function() state.goldResetOverride = "weekly" updateGoldResetSourceBtns() end)
    updateGoldResetSourceBtns()

    local function resetForm()
        state.goldModeSel = "net"
        state.goldResetSource = "inherit"
        state.goldResetOverride = "none"
        goldGoalInput:SetText("1000")
        updateGoldModeBtns()
        updateGoldResetSourceBtns()
    end

    local function loadFromNode(node, a)
        goldGoalInput:SetText(tostring(node.taskMax or 1))
        state.goldModeSel = a.goldMode or "net"
        state.goldResetSource = a.goldResetSource or "inherit"
        state.goldResetOverride = a.resetOverride or "none"
        updateGoldModeBtns()
        updateGoldResetSourceBtns()
    end

    local function collect(adv)
        local tm = tonumber(goldGoalInput:GetText()) or 1
        if tm < 1 then tm = 1 end
        adv.goldMode = state.goldModeSel
        adv.goldResetSource = state.goldResetSource
        adv.resetOverride = state.goldResetOverride
        return tm
    end

    return {
        panel = optGold,
        goldGoalInput = goldGoalInput,
        state = state,
        resetForm = resetForm,
        loadFromNode = loadFromNode,
        collect = collect,
        refresh = function()
            updateGoldModeBtns()
            updateGoldResetSourceBtns()
        end,
    }
end

local function CreateTaskDialogItemUi(advContainer)
    local t = TaskTracker.GetTheme()
    local state = {
        itemModeSel = "earned",
        itemKindSel = "item",
    }

    local optItem = CreateFrame("Frame", nil, advContainer)
    pinAdvPanelToContainer(optItem, advContainer)
    optItem:Hide()
    local itTokLbl = MakeLabel(optItem, "Items (names, ids, links; comma-separated):", optItem, "TOPLEFT", 0, 0)
    local itemsInput = CreateFrame("EditBox", "TTItemsInput", optItem, "InputBoxTemplate")
    itemsInput:SetSize(234, 36)
    itemsInput:SetPoint("TOPLEFT", itTokLbl, "BOTTOMLEFT", 0, -6)
    itemsInput:SetMultiLine(true)
    itemsInput:SetMaxLetters(500)
    itemsInput:SetAutoFocus(false)
    itemsInput:SetFontObject(t.fontNormal or "GameFontHighlightSmall")
    TaskTracker.ClearFontShadow(itemsInput)
    local itBg = itemsInput:CreateTexture(nil, "BACKGROUND")
    itBg:SetAllPoints()
    TaskTracker.SetColor(itBg, "inputBg")
    if TaskTracker.RegisterLinkableEditBox then
        TaskTracker.RegisterLinkableEditBox(itemsInput)
    end

    local itemCheckBtn = TaskTracker.MakeIconButton(optItem, 20, 20, { normalBgKey = "headerBg", hoverBgKey = "accentBg" })
    itemCheckBtn:SetPoint("LEFT", itemsInput, "RIGHT", 6, 0)
    itemCheckBtn:SetIconAtlas(TaskTracker.FirstValidAtlas("Tracker-Check", "common-icon-checkmark", "common-icon-check"), true)

    local itKindLbl = MakeLabel(optItem, "Input type:", itemsInput, "BOTTOMLEFT", 0, -10)
    local itemKindItemBtn = TaskTracker.MakeButton(optItem, "Items", 124, 20)
    local itemKindCurBtn  = TaskTracker.MakeButton(optItem, "Currency", 124, 20)
    itemKindItemBtn:SetPoint("TOPLEFT", itKindLbl, "BOTTOMLEFT", 0, -6)
    itemKindCurBtn:SetPoint("LEFT", itemKindItemBtn, "RIGHT", 4, 0)
    for _, b in ipairs({ itemKindItemBtn, itemKindCurBtn }) do
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
    end

    local function updateItemKindBtns()
        TaskTracker.SetExclusiveButtonActive({ item = itemKindItemBtn, currency = itemKindCurBtn }, state.itemKindSel)
        if state.itemKindSel == "currency" then
            itTokLbl:SetText("Currency (ids or links; comma-separated):")
        else
            itTokLbl:SetText("Items (names, ids, links; comma-separated):")
        end
    end
    itemKindItemBtn:SetScript("OnClick", function() state.itemKindSel = "item" updateItemKindBtns() end)
    itemKindCurBtn:SetScript("OnClick", function() state.itemKindSel = "currency" updateItemKindBtns() end)
    updateItemKindBtns()
    local itModeLbl = MakeLabel(optItem, "Tracking:", itemKindItemBtn, "BOTTOMLEFT", 0, -10)
    local itemEarnedBtn = TaskTracker.MakeButton(optItem, "Items earned", 124, 20)
    local itemTotalBtn = TaskTracker.MakeButton(optItem, "Current total", 124, 20)
    itemEarnedBtn:SetPoint("TOPLEFT", itModeLbl, "BOTTOMLEFT", 0, -6)
    itemTotalBtn:SetPoint("LEFT", itemEarnedBtn, "RIGHT", 4, 0)
    for _, b in ipairs({ itemEarnedBtn, itemTotalBtn }) do
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
    end
    local itemLeftBtn = TaskTracker.MakeButton(optItem, "Catch-up left", 252, 20)
    itemLeftBtn:SetPoint("TOPLEFT", itemEarnedBtn, "BOTTOMLEFT", 0, -4)
    itemLeftBtn:SetScript("OnEnter", nil)
    itemLeftBtn:SetScript("OnLeave", nil)
    local itGoalLbl = MakeLabel(optItem, "Goal count:", itemLeftBtn, "BOTTOMLEFT", 0, -10)
    local itemGoalInput = MakeInput(optItem, "TTItemGoal", 80, itGoalLbl)
    local function updateItemModeBtns()
        TaskTracker.SetExclusiveButtonActive({
            total = itemTotalBtn,
            earned = itemEarnedBtn,
            remaining = itemLeftBtn,
        }, state.itemModeSel)
        if state.itemModeSel == "remaining" then
            itGoalLbl:SetText("Finishes at 0. Goal is not used.")
            itemGoalInput:Hide()
        else
            itGoalLbl:SetText("Goal count:")
            itemGoalInput:Show()
        end
    end
    itemEarnedBtn:SetScript("OnClick", function() state.itemModeSel = "earned" updateItemModeBtns() end)
    itemTotalBtn:SetScript("OnClick", function() state.itemModeSel = "total" updateItemModeBtns() end)
    itemLeftBtn:SetScript("OnClick", function() state.itemModeSel = "remaining" updateItemModeBtns() end)
    updateItemModeBtns()
    itemCheckBtn:SetScript("OnClick", function()
        local msg = TaskTracker.BuildItemInputValidationMessage(itemsInput:GetText(), state.itemKindSel)
        StaticPopupDialogs["TASKTRACKER_ITEM_VALIDATE"] = {
            text         = msg,
            button1      = "OK",
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("TASKTRACKER_ITEM_VALIDATE")
    end)
    itemGoalInput:SetMaxLetters(8)
    itemGoalInput:SetText("10")

    local function resetForm()
        state.itemModeSel = "earned"
        state.itemKindSel = "item"
        itemsInput:SetText("")
        itemGoalInput:SetText("10")
        updateItemKindBtns()
        updateItemModeBtns()
    end

    local function loadFromNode(node, a)
        local parts = {}
        for _, id in ipairs(a.itemIds or {}) do
            parts[#parts + 1] = tostring(id)
        end
        itemsInput:SetText(table.concat(parts, ", "))
        state.itemKindSel = a.itemKind or "item"
        state.itemModeSel = a.itemTrackMode or "earned"
        itemGoalInput:SetText(tostring(node.taskMax or 1))
        updateItemKindBtns()
        updateItemModeBtns()
    end

    local function collect(adv)
        adv.itemKind = state.itemKindSel
        if state.itemKindSel == "currency" then
            adv.itemIds = TaskTracker.ParseCurrencyIdListFromText(itemsInput:GetText())
        else
            adv.itemIds = TaskTracker.ParseItemIdListFromText(itemsInput:GetText())
        end
        adv.itemTrackMode = state.itemModeSel
        local tm = tonumber(itemGoalInput:GetText()) or 1
        if tm < 1 then tm = 1 end
        return tm
    end

    return {
        panel = optItem,
        itemsInput = itemsInput,
        itemGoalInput = itemGoalInput,
        state = state,
        resetForm = resetForm,
        loadFromNode = loadFromNode,
        collect = collect,
        refresh = function()
            updateItemKindBtns()
            updateItemModeBtns()
        end,
    }
end

local function CreateTaskDialogQuestUi(advContainer)
    local t = TaskTracker.GetTheme()
    local optQuest = CreateFrame("Frame", nil, advContainer)
    pinAdvPanelToContainer(optQuest, advContainer)
    optQuest:Hide()
    local qTokLbl = MakeLabel(optQuest, "Quest IDs or exact names (comma-separated):", optQuest, "TOPLEFT", 0, 0)

    local questsBox = CreateFrame("Frame", nil, optQuest)
    questsBox:SetSize(234, 36)
    questsBox:SetPoint("TOPLEFT", qTokLbl, "BOTTOMLEFT", 0, -6)
    local qBoxBg = questsBox:CreateTexture(nil, "BACKGROUND")
    qBoxBg:SetAllPoints()
    TaskTracker.SetColor(qBoxBg, "inputBg")
    TaskTracker.MakeBorder(questsBox, "border")

    local questsInput = CreateFrame("EditBox", "TTQuestsInput", questsBox)
    questsInput:SetAllPoints()
    questsInput:SetMultiLine(true)
    questsInput:SetMaxLetters(500)
    questsInput:SetAutoFocus(false)
    questsInput:SetFontObject(t.fontNormal or "GameFontHighlightSmall")
    TaskTracker.ClearFontShadow(questsInput)
    questsInput:SetTextInsets(6, 6, 4, 4)
    if TaskTracker.RegisterLinkableEditBox then
        TaskTracker.RegisterLinkableEditBox(questsInput)
    end

    local questCheckBtn = TaskTracker.MakeIconButton(optQuest, 20, 20, { normalBgKey = "headerBg", hoverBgKey = "accentBg" })
    questCheckBtn:SetPoint("LEFT", questsBox, "RIGHT", 6, 0)
    questCheckBtn:SetIconAtlas(TaskTracker.FirstValidAtlas("Tracker-Check", "common-icon-checkmark", "common-icon-check"), true)
    questCheckBtn:SetScript("OnClick", function()
        local msg = TaskTracker.BuildQuestInputValidationMessage(questsInput:GetText())
        StaticPopupDialogs["TASKTRACKER_QUEST_VALIDATE"] = {
            text         = msg,
            button1      = "OK",
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("TASKTRACKER_QUEST_VALIDATE")
    end)

    local qGoalLbl = MakeLabel(optQuest, "How many must be completed:", questsBox, "BOTTOMLEFT", 0, -18)
    local questGoalInput = MakeInput(optQuest, "TTQuestGoal", 80, qGoalLbl)
    questGoalInput:SetMaxLetters(8)
    questGoalInput:SetText("1")

    local function resetForm()
        questsInput:SetText("")
        questGoalInput:SetText("1")
    end

    local function loadFromNode(node, a)
        local parts = {}
        for _, id in ipairs(a.questIds or {}) do
            parts[#parts + 1] = tostring(id)
        end
        for _, nm in ipairs(a.questNames or {}) do
            parts[#parts + 1] = nm
        end
        questsInput:SetText(table.concat(parts, ", "))
        questGoalInput:SetText(tostring(node.taskMax or 1))
    end

    local function collect(adv)
        local ids, nameTok = TaskTracker.ParseQuestListFromText(questsInput:GetText())
        local merged, still = TaskTracker.MergeQuestIdsFromTokens(ids, nameTok)
        adv.questIds = merged
        adv.questNames = (still and #still > 0) and still or nil
        local tm = tonumber(questGoalInput:GetText()) or 1
        if tm < 1 then tm = 1 end
        if tm > 999 then tm = 999 end
        return tm
    end

    return {
        panel = optQuest,
        questsInput = questsInput,
        questGoalInput = questGoalInput,
        resetForm = resetForm,
        loadFromNode = loadFromNode,
        collect = collect,
    }
end

local function CreateTaskDialogReputationUi(advContainer)
    local state = {
        repGoalSel = "weekly_gain",
        repStandingSel = 6,
        repStandingIsRenown = false,
        repTrack = nil,
    }

    local optRep = CreateFrame("Frame", nil, advContainer)
    pinAdvPanelToContainer(optRep, advContainer)
    optRep:Hide()
    local repFacLbl = MakeLabel(optRep, "Faction (id, name, or link):", optRep, "TOPLEFT", 0, 0)
    local factionInput = MakeInput(optRep, "TTFaction", 234, repFacLbl)
    factionInput:SetMaxLetters(120)

    local repCheckBtn = TaskTracker.MakeIconButton(optRep, 20, 20, { normalBgKey = "headerBg", hoverBgKey = "accentBg" })
    repCheckBtn:SetPoint("LEFT", factionInput, "RIGHT", 6, 0)
    repCheckBtn:SetIconAtlas(TaskTracker.FirstValidAtlas("Tracker-Check", "common-icon-checkmark", "common-icon-check"), true)
    local repGoalLbl = MakeLabel(optRep, "Goal type:", factionInput, "BOTTOMLEFT", 0, -8)
    local repWkBtn = TaskTracker.MakeButton(optRep, "Weekly gain", 82, 20)
    local repStBtn = TaskTracker.MakeButton(optRep, "Standing", 82, 20)
    local repValBtn = TaskTracker.MakeButton(optRep, "Value", 82, 20)
    repWkBtn:SetPoint("TOPLEFT", repGoalLbl, "BOTTOMLEFT", 0, -6)
    repStBtn:SetPoint("LEFT", repWkBtn, "RIGHT", 4, 0)
    repValBtn:SetPoint("LEFT", repStBtn, "RIGHT", 4, 0)
    for _, b in ipairs({ repWkBtn, repStBtn, repValBtn }) do
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
    end
    local repWeeklyLbl = MakeLabel(optRep, "Rep per week:", repWkBtn, "BOTTOMLEFT", 0, -10)
    local repWeeklyInput = MakeInput(optRep, "TTRepWk", 80, repWeeklyLbl)
    repWeeklyInput:SetMaxLetters(8)
    repWeeklyInput:SetText("1000")
    local repStandLbl = MakeLabel(optRep, "Target standing:", repWkBtn, "BOTTOMLEFT", 0, -10)
    repStandLbl:Hide()

    local repRenownLbl = MakeLabel(optRep, "Target renown level:", repWkBtn, "BOTTOMLEFT", 0, -10)
    repRenownLbl:Hide()
    local repRenownInput = MakeInput(optRep, "TTRepRenown", 80, repRenownLbl)
    repRenownInput:SetMaxLetters(3)
    repRenownInput:SetText("10")
    repRenownInput:Hide()

    local repParagonCapLbl = MakeLabel(optRep, "Paragon rep goal:", repRenownLbl, "BOTTOMLEFT", 0, -10)
    repParagonCapLbl:Hide()
    local repParagonCapInput = MakeInput(optRep, "TTRepParagonCap", 72, repParagonCapLbl)
    repParagonCapInput:SetMaxLetters(8)
    repParagonCapInput:SetText("")
    repParagonCapInput:Hide()

    local standBtns = {}
    local standOpts = {
        { v = 4, t = "Neutral" },
        { v = 5, t = "Friendly" },
        { v = 6, t = "Honored" },
        { v = 7, t = "Revered" },
        { v = 8, t = "Exalted" },
        { v = TaskTracker.REP_STANDING_PARAGON, t = "Paragon" },
    }
    local applyStandingUiForFaction
    local function refreshStandingBtnStyles()
        TaskTracker.SetExclusiveButtonActive(standBtns, function(btn)
            return btn.standingVal == state.repStandingSel
        end)
        if state.repGoalSel == "standing" then
            applyStandingUiForFaction()
        end
    end
    local prevS = nil
    for _, so in ipairs(standOpts) do
        local sb = TaskTracker.MakeButton(optRep, so.t, 45, 18)
        if not prevS then
            sb:SetPoint("TOPLEFT", repStandLbl, "BOTTOMLEFT", 0, -4)
        else
            sb:SetPoint("LEFT", prevS, "RIGHT", 2, 0)
        end
        sb:SetScript("OnEnter", nil)
        sb:SetScript("OnLeave", nil)
        sb.standingVal = so.v
        sb:SetScript("OnClick", function()
            state.repTrack = nil
            state.repStandingSel = sb.standingVal
            refreshStandingBtnStyles()
        end)
        standBtns[#standBtns + 1] = sb
        prevS = sb
    end
    for _, b2 in ipairs(standBtns) do
        b2:Hide()
    end

    local function syncStandingModeFromFactionInput()
        state.repStandingIsRenown = false
        local fid, fname = TaskTracker.ParseFactionIdFromText(factionInput:GetText())
        local fd = TaskTracker.GetAdvancedFactionData(fid, fname)
        if fd and fd.isMajorFaction then
            state.repStandingIsRenown = true
        end
    end

    applyStandingUiForFaction = function()
        if state.repGoalSel ~= "standing" then return end
        if state.repTrack == "friendship" then
            repParagonCapLbl:Hide()
            repParagonCapInput:Hide()
            repStandLbl:Hide()
            for _, b2 in ipairs(standBtns) do b2:Hide() end
            repRenownLbl:SetText("Target friendship rank:")
            repRenownLbl:Show()
            repRenownInput:Show()
            return
        end
        repRenownLbl:SetText("Target renown level:")
        syncStandingModeFromFactionInput()
        repParagonCapLbl:Hide()
        repParagonCapInput:Hide()
        if state.repStandingIsRenown then
            repStandLbl:Hide()
            for _, b2 in ipairs(standBtns) do b2:Hide() end
            repRenownLbl:Show()
            repRenownInput:Show()
        else
            repRenownLbl:Hide()
            repRenownInput:Hide()
            repStandLbl:Show()
            for _, b2 in ipairs(standBtns) do b2:Show() end
            if state.repStandingSel == TaskTracker.REP_STANDING_PARAGON then
                repParagonCapLbl:ClearAllPoints()
                repParagonCapLbl:SetPoint("TOPLEFT", standBtns[1], "BOTTOMLEFT", 0, -8)
                repParagonCapInput:ClearAllPoints()
                repParagonCapInput:SetPoint("LEFT", repParagonCapLbl, "RIGHT", 6, 0)
                repParagonCapLbl:Show()
                repParagonCapInput:Show()
            end
        end
    end

    factionInput:HookScript("OnEditFocusLost", function()
        applyStandingUiForFaction()
    end)
    factionInput:HookScript("OnTextChanged", function(_, isUser)
        if isUser then
            applyStandingUiForFaction()
        end
    end)
    local repValueLbl = MakeLabel(optRep, "Target reputation value:", repWkBtn, "BOTTOMLEFT", 0, -10)
    repValueLbl:Hide()
    local repValueInput = MakeInput(optRep, "TTRepVal", 100, repValueLbl)
    repValueInput:SetMaxLetters(12)
    repValueInput:SetText("42000")
    repValueInput:Hide()
    local function updateRepGoalBtns()
        TaskTracker.SetExclusiveButtonActive({
            weekly_gain = repWkBtn,
            standing = repStBtn,
            value = repValBtn,
        }, state.repGoalSel)
        if state.repGoalSel == "weekly_gain" then
            repWeeklyLbl:Show()
            repWeeklyInput:Show()
            repStandLbl:Hide()
            for _, b2 in ipairs(standBtns) do b2:Hide() end
            repRenownLbl:Hide()
            repRenownInput:Hide()
            repValueLbl:Hide()
            repValueInput:Hide()
        elseif state.repGoalSel == "standing" then
            repWeeklyLbl:Hide()
            repWeeklyInput:Hide()
            applyStandingUiForFaction()
            repValueLbl:Hide()
            repValueInput:Hide()
        else
            repWeeklyLbl:Hide()
            repWeeklyInput:Hide()
            repStandLbl:Hide()
            for _, b2 in ipairs(standBtns) do b2:Hide() end
            repRenownLbl:Hide()
            repRenownInput:Hide()
            repValueLbl:Show()
            repValueInput:Show()
        end
    end
    repWkBtn:SetScript("OnClick", function()
        state.repTrack = nil
        state.repGoalSel = "weekly_gain"
        updateRepGoalBtns()
    end)
    repStBtn:SetScript("OnClick", function()
        state.repGoalSel = "standing"
        updateRepGoalBtns()
        refreshStandingBtnStyles()
    end)
    repValBtn:SetScript("OnClick", function()
        state.repTrack = nil
        state.repGoalSel = "value"
        updateRepGoalBtns()
    end)
    updateRepGoalBtns()
    refreshStandingBtnStyles()

    repCheckBtn:SetScript("OnClick", function()
        local standingTarget = state.repStandingSel
        syncStandingModeFromFactionInput()
        if state.repGoalSel == "standing" and state.repStandingIsRenown then
            standingTarget = tonumber(repRenownInput:GetText()) or state.repStandingSel
        end
        local msg = TaskTracker.BuildFactionInputValidationMessage(factionInput:GetText(), state.repGoalSel, standingTarget)
        StaticPopupDialogs["TASKTRACKER_REP_VALIDATE"] = {
            text         = msg,
            button1      = "OK",
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("TASKTRACKER_REP_VALIDATE")
    end)

    local function resetForm()
        state.repGoalSel = "weekly_gain"
        state.repStandingSel = 6
        state.repStandingIsRenown = false
        state.repTrack = nil
        factionInput:SetText("")
        repWeeklyInput:SetText("1000")
        repValueInput:SetText("42000")
        repRenownInput:SetText("10")
        repParagonCapInput:SetText("")
        updateRepGoalBtns()
        refreshStandingBtnStyles()
    end

    local function loadFromNode(node, a)
        if (a.repFactionId or 0) > 0 then
            factionInput:SetText(tostring(a.repFactionId))
        else
            factionInput:SetText(a.repFactionName or "")
        end
        state.repTrack = nil
        state.repGoalSel = a.repGoalType or "weekly_gain"
        if a.repGoalType == "friendship" then
            state.repGoalSel = "standing"
            state.repTrack = "friendship"
            state.repStandingSel = tonumber(a.repStandingTarget) or 5
            repRenownInput:SetText(tostring(state.repStandingSel))
        elseif state.repGoalSel == "weekly_gain" then
            repWeeklyInput:SetText(tostring(node.taskMax or 1))
        elseif state.repGoalSel == "standing" then
            state.repStandingSel = tonumber(a.repStandingTarget) or 6
            repRenownInput:SetText(tostring(state.repStandingSel))
            if state.repStandingSel == TaskTracker.REP_STANDING_PARAGON and (a.repParagonTarget or 0) > 0 then
                repParagonCapInput:SetText(tostring(a.repParagonTarget))
            else
                repParagonCapInput:SetText("")
            end
        else
            repValueInput:SetText(tostring(a.repValueTarget or node.taskMax or 42000))
        end
        updateRepGoalBtns()
        refreshStandingBtnStyles()
        applyStandingUiForFaction()
    end

    local function collect(adv)
        local fid, fname = TaskTracker.ParseFactionIdFromText(factionInput:GetText())
        adv.repFactionId = fid or 0
        adv.repFactionName = fname or ""
        adv.repGoalType = state.repGoalSel
        local tm = 1
        if state.repTrack == "friendship" and state.repGoalSel == "standing" then
            adv.repGoalType = "friendship"
            local rank = tonumber(repRenownInput:GetText()) or state.repStandingSel or 1
            if rank < 1 then rank = 1 end
            adv.repStandingTarget = rank
            adv.repParagonTarget = nil
            return 1
        end
        if state.repGoalSel == "weekly_gain" then
            tm = tonumber(repWeeklyInput:GetText()) or 1
            if tm < 1 then tm = 1 end
        elseif state.repGoalSel == "standing" then
            tm = 1
            syncStandingModeFromFactionInput()
            if state.repStandingIsRenown then
                adv.repStandingTarget = tonumber(repRenownInput:GetText()) or state.repStandingSel
                adv.repParagonTarget = nil
            else
                adv.repStandingTarget = state.repStandingSel
                if state.repStandingSel == TaskTracker.REP_STANDING_PARAGON then
                    local cap = tonumber(repParagonCapInput:GetText())
                    adv.repParagonTarget = (cap and cap > 0) and cap or nil
                else
                    adv.repParagonTarget = nil
                end
            end
        else
            tm = tonumber(repValueInput:GetText()) or 1
            if tm < 1 then tm = 1 end
            adv.repValueTarget = tm
        end
        return tm
    end

    return {
        panel = optRep,
        factionInput = factionInput,
        repWeeklyInput = repWeeklyInput,
        repValueInput = repValueInput,
        repRenownInput = repRenownInput,
        repParagonCapInput = repParagonCapInput,
        state = state,
        resetForm = resetForm,
        loadFromNode = loadFromNode,
        collect = collect,
        refresh = function()
            updateRepGoalBtns()
            refreshStandingBtnStyles()
            applyStandingUiForFaction()
        end,
    }
end

local function CreateTaskDialogMobKillUi(advContainer, hooks)
    hooks = hooks or {}
    local t = TaskTracker.GetTheme()
    local state = { mobKillModeSel = "world" }

    local optMobKill = CreateFrame("Frame", nil, advContainer)
    pinAdvPanelToContainer(optMobKill, advContainer)
    optMobKill:Hide()
    local mkModeLbl = MakeLabel(optMobKill, "Tracking mode:", optMobKill, "TOPLEFT", 0, 0)
    local mkModeWorldBtn = TaskTracker.MakeButton(optMobKill, "World mob", 82, 20)
    local mkModeLootBtn  = TaskTracker.MakeButton(optMobKill, "By loot", 82, 20)
    local mkModeBossBtn  = TaskTracker.MakeButton(optMobKill, "Boss", 82, 20)
    mkModeWorldBtn:SetPoint("TOPLEFT", mkModeLbl, "BOTTOMLEFT", 0, -6)
    mkModeLootBtn:SetPoint("LEFT", mkModeWorldBtn, "RIGHT", 4, 0)
    mkModeBossBtn:SetPoint("LEFT", mkModeLootBtn, "RIGHT", 4, 0)
    for _, b in ipairs({ mkModeWorldBtn, mkModeLootBtn, mkModeBossBtn }) do
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
    end

    local mkLimit = MakeLabel(optMobKill, "Note: World mobs require enemy nameplates and targeting once.", mkModeWorldBtn, "BOTTOMLEFT", 0, -8)
    local mkLbl = MakeLabel(optMobKill, "Mob NPC IDs (comma-separated):", mkLimit, "BOTTOMLEFT", 0, -10)

    local mobBox = CreateFrame("Frame", nil, optMobKill)
    mobBox:SetSize(234, 36)
    mobBox:SetPoint("TOPLEFT", mkLbl, "BOTTOMLEFT", 0, -6)
    local mkBoxBg = mobBox:CreateTexture(nil, "BACKGROUND")
    mkBoxBg:SetAllPoints()
    TaskTracker.SetColor(mkBoxBg, "inputBg")
    TaskTracker.MakeBorder(mobBox, "border")

    local mobIdsInput = CreateFrame("EditBox", "TTMobIdsInput", mobBox)
    mobIdsInput:SetAllPoints()
    mobIdsInput:SetMultiLine(true)
    mobIdsInput:SetMaxLetters(500)
    mobIdsInput:SetAutoFocus(false)
    mobIdsInput:SetFontObject(t.fontNormal or "GameFontHighlightSmall")
    TaskTracker.ClearFontShadow(mobIdsInput)
    mobIdsInput:SetTextInsets(6, 6, 4, 4)

    local bossInstInput, bossNamesInput

    local mkCheckBtn = TaskTracker.MakeIconButton(optMobKill, 20, 20, { normalBgKey = "headerBg", hoverBgKey = "accentBg" })
    mkCheckBtn:SetPoint("LEFT", mobBox, "RIGHT", 6, 0)
    mkCheckBtn:SetIconAtlas(TaskTracker.FirstValidAtlas("Tracker-Check", "common-icon-checkmark", "common-icon-check"), true)
    mkCheckBtn:SetScript("OnClick", function()
        local msg
        if state.mobKillModeSel == "boss" then
            msg = TaskTracker.BuildBossEncounterInputValidationMessage(
                (bossInstInput and bossInstInput.GetText and bossInstInput:GetText()) or "",
                (bossNamesInput and bossNamesInput.GetText and bossNamesInput:GetText()) or ""
            )
        else
            msg = TaskTracker.BuildMobIdInputValidationMessage(mobIdsInput:GetText())
        end
        StaticPopupDialogs["TASKTRACKER_MOB_VALIDATE"] = {
            text         = msg,
            button1      = "OK",
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("TASKTRACKER_MOB_VALIDATE")
    end)

    local mkGoalLbl = MakeLabel(optMobKill, "How many must be killed:", mobBox, "BOTTOMLEFT", 0, -18)
    local mobKillGoalInput = MakeInput(optMobKill, "TTMobKillGoal", 80, mkGoalLbl)
    mobKillGoalInput:SetMaxLetters(8)
    mobKillGoalInput:SetText("1")

    local bossInstLbl = MakeLabel(optMobKill, "Instance name (optional):", mkLimit, "BOTTOMLEFT", 0, -10)
    bossInstInput = MakeInput(optMobKill, "TTBossInstance", 234, bossInstLbl)
    bossInstInput:SetMaxLetters(120)
    local bossNamesLbl = MakeLabel(optMobKill, "Boss name(s) (comma-separated):", bossInstInput, "BOTTOMLEFT", 0, -10)
    bossNamesInput = MakeInput(optMobKill, "TTBossNames", 234, bossNamesLbl)
    bossNamesInput:SetMaxLetters(240)

    local function tokenSpan(text, pos)
        text = text or ""
        pos = tonumber(pos) or #text
        if pos < 0 then pos = 0 end
        if pos > #text then pos = #text end
        local lastComma, search = 0, 1
        while true do
            local comma = text:find(",", search, true)
            if not comma or comma > pos then break end
            lastComma = comma
            search = comma + 1
        end
        local nextComma = text:find(",", pos + 1, true)
        local rawStart = lastComma + 1
        local rawEnd = nextComma and (nextComma - 1) or #text
        local chunk = text:sub(rawStart, rawEnd)
        local lead = chunk:match("^(%s*)") or ""
        local trail = chunk:match("(%s*)$") or ""
        local a = rawStart + #lead
        local b = rawEnd - #trail
        if b < a - 1 then b = a - 1 end
        return text:sub(a, b), a, b
    end

    local function makeSuggestMenu()
        local menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(500)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:Hide()
        local bg = menu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        TaskTracker.SetColor(bg, "headerBg2")
        TaskTracker.MakeBorder(menu, "border")
        menu.rows = {}
        for i = 1, 8 do
            local row = CreateFrame("Button", nil, menu)
            row:SetHeight(20)
            local fs = TaskTracker.CreateFontString(row, nil, "OVERLAY", t.fontNormal or "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", 6, 0)
            fs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            TaskTracker.SetTextColor(fs, "textPrimary")
            row.label = fs
            row:SetScript("OnEnter", function()
                TaskTracker.SetTextColor(fs, "textAccent")
            end)
            row:SetScript("OnLeave", function()
                TaskTracker.SetTextColor(fs, "textPrimary")
            end)
            menu.rows[i] = row
        end
        return menu
    end

    local instMenu = makeSuggestMenu()
    local bossMenu = makeSuggestMenu()

    local function hideSuggestMenus()
        instMenu:Hide()
        bossMenu:Hide()
    end

    local function showSuggestMenu(menu, editBox, labels, onPick, loading)
        local n = loading and 1 or #labels
        if n < 1 then
            menu:Hide()
            return
        end
        local width = math.max(editBox:GetWidth() or 234, 220)
        local rowH = 20
        for i = 1, 8 do
            local row = menu.rows[i]
            if i <= n then
                local text = loading and "Reading the dungeon journal..." or labels[i]
                row.label:SetText(text)
                row:SetScript("OnClick", nil)
                if not loading then
                    row:SetScript("OnClick", function()
                        onPick(i)
                        menu:Hide()
                    end)
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * rowH)
                row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * rowH)
                row:Show()
                if row.label.GetStringWidth then
                    width = math.max(width, math.ceil((row.label:GetStringWidth() or 0) + 16))
                end
            else
                row:Hide()
            end
        end
        if width > 420 then width = 420 end
        menu:SetSize(width, 8 + n * rowH)
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -2)
        menu:Show()
        menu:Raise()
    end

    local function refreshInstSuggest(userInput)
        if not userInput or state.mobKillModeSel ~= "boss" then
            instMenu:Hide()
            return
        end
        local names, journalState = TaskTracker.SuggestBossInstances(bossInstInput:GetText() or "", 8)
        if names and #names > 0 then
            showSuggestMenu(instMenu, bossInstInput, names, function(i)
                bossInstInput:SetText(names[i] or "")
                bossInstInput:SetCursorPosition(#(names[i] or ""))
            end, false)
        elseif journalState == "loading" and #(bossInstInput:GetText() or "") >= 2 then
            showSuggestMenu(instMenu, bossInstInput, nil, nil, true)
        else
            instMenu:Hide()
        end
    end

    local function refreshBossSuggest(userInput)
        if not userInput or state.mobKillModeSel ~= "boss" then
            bossMenu:Hide()
            return
        end
        local text = bossNamesInput:GetText() or ""
        local token = tokenSpan(text, bossNamesInput:GetCursorPosition())
        local hits, journalState = TaskTracker.SuggestBossNames(bossInstInput:GetText() or "", token, 8)
        if hits and #hits > 0 then
            local labels = {}
            for i = 1, #hits do
                labels[i] = hits[i].label
            end
            showSuggestMenu(bossMenu, bossNamesInput, labels, function(i)
                local hit = hits[i]
                if not hit then return end
                local cur = bossNamesInput:GetText() or ""
                local _, a, b = tokenSpan(cur, bossNamesInput:GetCursorPosition())
                local replaced = cur:sub(1, a - 1) .. hit.boss .. cur:sub(b + 1)
                bossNamesInput:SetText(replaced)
                if bossNamesInput.SetCursorPosition then
                    bossNamesInput:SetCursorPosition((a - 1) + #hit.boss)
                end
                local typedInst = bossInstInput:GetText() or ""
                if typedInst == "" or not (TaskTracker.BossJournalNameMatches and TaskTracker.BossJournalNameMatches(typedInst, hit.instance)) then
                    bossInstInput:SetText(hit.instance or "")
                end
            end, false)
        elseif journalState == "loading" and #token >= 2 then
            showSuggestMenu(bossMenu, bossNamesInput, nil, nil, true)
        else
            bossMenu:Hide()
        end
    end

    bossInstInput:HookScript("OnTextChanged", function(_, userInput)
        refreshInstSuggest(userInput)
    end)
    bossNamesInput:HookScript("OnTextChanged", function(_, userInput)
        refreshBossSuggest(userInput)
    end)
    local function hideSuggestSoon(menu)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, function()
                if menu:IsShown() and not menu:IsMouseOver() then
                    menu:Hide()
                end
            end)
        else
            menu:Hide()
        end
    end
    bossInstInput:HookScript("OnEditFocusLost", function()
        hideSuggestSoon(instMenu)
    end)
    bossNamesInput:HookScript("OnEditFocusLost", function()
        hideSuggestSoon(bossMenu)
    end)
    bossInstInput:HookScript("OnEscapePressed", function(self)
        instMenu:Hide()
        self:ClearFocus()
    end)
    bossNamesInput:HookScript("OnEscapePressed", function(self)
        bossMenu:Hide()
        self:ClearFocus()
    end)
    optMobKill:HookScript("OnHide", hideSuggestMenus)
    mkCheckBtn:HookScript("OnClick", hideSuggestMenus)

    local function syncMobKillModeUi()
        TaskTracker.SetExclusiveButtonActive({
            world = mkModeWorldBtn,
            loot = mkModeLootBtn,
            boss = mkModeBossBtn,
        }, state.mobKillModeSel)

        if state.mobKillModeSel == "boss" then
            if TaskTracker.StartBossJournalIndex then
                TaskTracker.StartBossJournalIndex()
            end
            mkLimit:SetText("Note: Boss mode counts a successful boss kill. Type part of a name for suggestions.")
            mkLbl:Hide()
            mobBox:Hide()
            mkCheckBtn:Show()
            bossInstLbl:Show()
            bossInstInput:Show()
            bossNamesLbl:Show()
            bossNamesInput:Show()
            mkCheckBtn:ClearAllPoints()
            mkCheckBtn:SetPoint("LEFT", bossNamesInput, "RIGHT", 6, 0)
            mkGoalLbl:ClearAllPoints()
            mkGoalLbl:SetPoint("TOPLEFT", bossNamesInput, "BOTTOMLEFT", 0, -10)
            mobKillGoalInput:ClearAllPoints()
            mobKillGoalInput:SetPoint("TOPLEFT", mkGoalLbl, "BOTTOMLEFT", 0, -6)
        else
            hideSuggestMenus()
            mkLbl:Show()
            mobBox:Show()
            mkCheckBtn:Show()
            mkCheckBtn:ClearAllPoints()
            mkCheckBtn:SetPoint("LEFT", mobBox, "RIGHT", 6, 0)
            bossInstLbl:Hide()
            bossInstInput:Hide()
            bossNamesLbl:Hide()
            bossNamesInput:Hide()
            if state.mobKillModeSel == "loot" then
                mkLimit:SetText("Note: Loot mode counts when you open loot on matching NPCs.")
            else
                mkLimit:SetText("Note: World mobs require enemy nameplates and targeting once.")
            end
            mkGoalLbl:ClearAllPoints()
            mkGoalLbl:SetPoint("TOPLEFT", mobBox, "BOTTOMLEFT", 0, -18)
            mobKillGoalInput:ClearAllPoints()
            mobKillGoalInput:SetPoint("TOPLEFT", mkGoalLbl, "BOTTOMLEFT", 0, -6)
        end

        if hooks.getTaskKind and hooks.getTaskKind() == "mob_kill" and hooks.requestHeight then
            hooks.requestHeight()
        end
    end
    mkModeWorldBtn:SetScript("OnClick", function() state.mobKillModeSel = "world" syncMobKillModeUi() end)
    mkModeLootBtn:SetScript("OnClick", function() state.mobKillModeSel = "loot" syncMobKillModeUi() end)
    mkModeBossBtn:SetScript("OnClick", function() state.mobKillModeSel = "boss" syncMobKillModeUi() end)
    syncMobKillModeUi()

    local function resetForm()
        state.mobKillModeSel = "world"
        mobIdsInput:SetText("")
        mobKillGoalInput:SetText("1")
        bossInstInput:SetText("")
        bossNamesInput:SetText("")
        syncMobKillModeUi()
    end

    local function loadFromNode(node, a)
        local parts = {}
        for _, id in ipairs(a.mobIds or {}) do
            parts[#parts + 1] = tostring(id)
        end
        mobIdsInput:SetText(table.concat(parts, ", "))
        mobKillGoalInput:SetText(tostring(node.taskMax or 1))
        state.mobKillModeSel = a.mobKillMode or "world"
        bossInstInput:SetText(tostring(a.bossInstanceName or ""))
        local bn = a.bossNames
        if type(bn) == "table" then
            bossNamesInput:SetText(table.concat(bn, ", "))
        else
            bossNamesInput:SetText(tostring(bn or ""))
        end
        syncMobKillModeUi()
    end

    local function collect(adv)
        adv.mobKillMode = state.mobKillModeSel
        if state.mobKillModeSel == "boss" then
            adv.bossInstanceName = bossInstInput:GetText() or ""
            adv.bossNames = bossNamesInput:GetText() or ""
            adv.mobIds = {}
        else
            adv.mobIds = TaskTracker.ParseMobIdListFromText(mobIdsInput:GetText())
            adv.bossInstanceName = ""
            adv.bossNames = ""
        end
        local tm = tonumber(mobKillGoalInput:GetText()) or 1
        if tm < 1 then tm = 1 end
        if tm > 99999 then tm = 99999 end
        return tm
    end

    return {
        panel = optMobKill,
        mobIdsInput = mobIdsInput,
        mobKillGoalInput = mobKillGoalInput,
        bossInstInput = bossInstInput,
        bossNamesInput = bossNamesInput,
        state = state,
        resetForm = resetForm,
        loadFromNode = loadFromNode,
        collect = collect,
        syncModeUi = syncMobKillModeUi,
    }
end

local function CreateTaskDialogCollectableUi(advContainer)
    local t = TaskTracker.GetTheme()
    local state = {
        collectExpSel = "midnight",
        collectCatSel = "mount",
        collEntrySelId = nil,
    }

    local optCollectable = CreateFrame("Frame", nil, advContainer)
    pinAdvPanelToContainer(optCollectable, advContainer)
    optCollectable:Hide()

    local rebuildCollEntryMenu

    local collExpLbl = TaskTracker.CreateFontString(optCollectable, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    collExpLbl:SetPoint("TOPLEFT", optCollectable, "TOPLEFT", 0, 0)
    TaskTracker.SetTextColor(collExpLbl, "textSecondary")
    collExpLbl:SetText("Expansion:")
    local collCatLbl = TaskTracker.CreateFontString(optCollectable, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    collCatLbl:SetPoint("TOPLEFT", optCollectable, "TOPLEFT", 156, 0)
    TaskTracker.SetTextColor(collCatLbl, "textSecondary")
    collCatLbl:SetText("Category:")

    local collExpDdBtn = TaskTracker.MakeButton(optCollectable, "Midnight", 136, 20)
    TaskTracker.AttachDropdownArrow(collExpDdBtn)
    collExpDdBtn:SetPoint("TOPLEFT", collExpLbl, "BOTTOMLEFT", 0, -4)
    collExpDdBtn:SetScript("OnEnter", nil)
    collExpDdBtn:SetScript("OnLeave", nil)
    local collCatDdBtn = TaskTracker.MakeButton(optCollectable, "Mounts", 136, 20)
    TaskTracker.AttachDropdownArrow(collCatDdBtn)
    collCatDdBtn:SetPoint("TOPLEFT", collCatLbl, "BOTTOMLEFT", 0, -4)
    collCatDdBtn:SetScript("OnEnter", nil)
    collCatDdBtn:SetScript("OnLeave", nil)

    local collExpMenu = CreateFrame("Frame", nil, optCollectable)
    if TaskTracker.RegisterOpenDropdown then TaskTracker.RegisterOpenDropdown(collExpMenu) end
    collExpMenu:SetFrameStrata("DIALOG")
    collExpMenu:SetFrameLevel((collExpDdBtn:GetFrameLevel() or 0) + 35)
    collExpMenu:SetSize(140, 80)
    collExpMenu:SetPoint("TOPLEFT", collExpDdBtn, "BOTTOMLEFT", 0, -2)
    collExpMenu:Hide()
    TaskTracker.MakeBorder(collExpMenu, "border")
    local collExpMenuBg = collExpMenu:CreateTexture(nil, "BACKGROUND")
    collExpMenuBg:SetAllPoints()
    TaskTracker.SetColor(collExpMenuBg, "inputBg")
    collExpMenu:EnableMouse(true)

    local collCatMenu = CreateFrame("Frame", nil, optCollectable)
    if TaskTracker.RegisterOpenDropdown then TaskTracker.RegisterOpenDropdown(collCatMenu) end
    collCatMenu:SetFrameStrata("DIALOG")
    collCatMenu:SetFrameLevel((collCatDdBtn:GetFrameLevel() or 0) + 35)
    collCatMenu:SetSize(140, 100)
    collCatMenu:SetPoint("TOPLEFT", collCatDdBtn, "BOTTOMLEFT", 0, -2)
    collCatMenu:Hide()
    TaskTracker.MakeBorder(collCatMenu, "border")
    local collCatMenuBg = collCatMenu:CreateTexture(nil, "BACKGROUND")
    collCatMenuBg:SetAllPoints()
    TaskTracker.SetColor(collCatMenuBg, "inputBg")
    collCatMenu:EnableMouse(true)

    local function closeCollExpCatMenus()
        collExpMenu:Hide()
        collCatMenu:Hide()
    end

    local function syncCollExpDdLabel()
        local nm = state.collectExpSel
        local list = TaskTracker.GetCollectableExpansionList and TaskTracker.GetCollectableExpansionList() or {}
        for _, ex in ipairs(list) do
            if ex and ex.id == state.collectExpSel then
                nm = ex.label or ex.id
                break
            end
        end
        collExpDdBtn:SetLabel(nm)
    end

    local function syncCollCatDdLabel()
        local nm = state.collectCatSel
        local cats = TaskTracker.GetCollectableCategories and TaskTracker.GetCollectableCategories() or {}
        for _, c in ipairs(cats) do
            if c and c.id == state.collectCatSel then
                nm = c.label or c.id
                break
            end
        end
        collCatDdBtn:SetLabel(nm)
    end

    local collPickLbl = MakeLabel(optCollectable, "Collectable:", collExpDdBtn, "BOTTOMLEFT", 0, -12)
    local collHideMini = TaskTracker.MakeButton(optCollectable, "Off", 34, 16)
    collHideMini:SetPoint("TOP", collPickLbl, "TOP", 0, 0)
    collHideMini:SetPoint("RIGHT", optCollectable, "RIGHT", -2, 0)
    collHideMini:SetScript("OnEnter", nil)
    collHideMini:SetScript("OnLeave", nil)
    local collHideLbl = TaskTracker.CreateFontString(optCollectable, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    collHideLbl:SetPoint("TOP", collPickLbl, "TOP", 0, 0)
    collHideLbl:SetPoint("RIGHT", collHideMini, "LEFT", -6, 0)
    TaskTracker.SetTextColor(collHideLbl, "textSecondary")
    collHideLbl:SetText("Hide collected:")
    if collHideMini.label then
        collHideMini.label:SetFontObject("GameFontDisableSmall")
        TaskTracker.ClearFontShadow(collHideMini.label)
    end

    local function syncCollHidePickMini()
        if not TaskTrackerDB then return end
        local on = TaskTracker.GetCollectablesHideOwnedInPicker and TaskTracker.GetCollectablesHideOwnedInPicker()
        collHideMini:SetLabel(on and "On" or "Off")
        TaskTracker.SetButtonActive(collHideMini, on)
    end

    collHideMini:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        TaskTrackerDB.collectablesHideOwnedInPicker = not TaskTracker.GetCollectablesHideOwnedInPicker()
        syncCollHidePickMini()
        rebuildCollEntryMenu(state.collEntrySelId)
    end)

    local collPickBtn = TaskTracker.MakeButton(optCollectable, "Select…", 260, 20)
    TaskTracker.AttachDropdownArrow(collPickBtn)
    collPickBtn:SetPoint("TOPLEFT", collPickLbl, "BOTTOMLEFT", 0, -6)
    collPickBtn:SetScript("OnEnter", nil)
    collPickBtn:SetScript("OnLeave", nil)

    local COLL_MENU_ROW_H = 18
    local COLL_MENU_GAP = 2
    local COLL_MENU_MAX_ROWS = 6
    local collEntryMenu = CreateFrame("Frame", nil, optCollectable)
    if TaskTracker.RegisterOpenDropdown then TaskTracker.RegisterOpenDropdown(collEntryMenu) end
    collEntryMenu:SetSize(260, 120)
    collEntryMenu:SetPoint("TOPLEFT", collPickBtn, "BOTTOMLEFT", 0, -2)
    collEntryMenu:SetFrameLevel((collPickBtn:GetFrameLevel() or 0) + 20)
    TaskTracker.MakeBorder(collEntryMenu, "border")
    local collEntryMenuBg = collEntryMenu:CreateTexture(nil, "BACKGROUND")
    collEntryMenuBg:SetAllPoints()
    TaskTracker.SetColor(collEntryMenuBg, "inputBg")
    collEntryMenu:EnableMouse(true)
    collEntryMenu:Hide()

    local collEntryScroll = CreateFrame("ScrollFrame", nil, collEntryMenu)
    collEntryScroll:SetPoint("TOPLEFT", collEntryMenu, "TOPLEFT", 4, -4)
    collEntryScroll:SetPoint("BOTTOMRIGHT", collEntryMenu, "BOTTOMRIGHT", -8, 4)
    local collEntryScrollChild = CreateFrame("Frame", nil, collEntryScroll)
    collEntryScroll:SetScrollChild(collEntryScrollChild)
    TaskTracker.MakeScrollBar(collEntryScroll, collEntryMenu)

    local collEntryRows = {}
    local function clearCollEntryRows()
        for _, r in pairs(collEntryRows) do
            r:Hide()
            r:SetParent(nil)
        end
        wipe(collEntryRows)
    end

    local function refreshCollEntryRowStyles()
        for id, row in pairs(collEntryRows) do
            TaskTracker.SetButtonActive(row, state.collEntrySelId == id)
        end
    end

    local collHowToLbl = MakeLabel(optCollectable, "How to obtain:", collPickBtn, "BOTTOMLEFT", 0, -10)
    local collHowToFs = TaskTracker.CreateFontString(optCollectable, nil, "OVERLAY", t.fontNormal or "GameFontHighlightSmall")
    collHowToFs:SetPoint("TOPLEFT", collHowToLbl, "BOTTOMLEFT", 0, -4)
    collHowToFs:SetWidth(268)
    collHowToFs:SetJustifyH("LEFT")
    collHowToFs:SetJustifyV("TOP")
    collHowToFs:SetWordWrap(true)
    collHowToFs:SetTextColor(0.85, 0.85, 0.85, 1)

    local collGoalLbl = MakeLabel(optCollectable, "Goal count:", collHowToFs, "BOTTOMLEFT", 0, -8)
    local collGoalInput = MakeInput(optCollectable, "TTCollGoal", 80, collGoalLbl)
    collGoalInput:SetMaxLetters(8)
    collGoalInput:SetText("30")

    local function syncCollHowTo()
        local ent = TaskTracker.GetCollectableEntry
            and TaskTracker.GetCollectableEntry(state.collectExpSel, state.collectCatSel, state.collEntrySelId)
        if ent and type(ent.howTo) == "string" and ent.howTo ~= "" then
            collHowToFs:SetText(ent.howTo)
        elseif ent and TaskTracker.CollectableEntryHasFishingRules and TaskTracker.CollectableEntryHasFishingRules(ent) then
            collHowToFs:SetText("This collectable uses automated fishing attempt counting in-game (see how-to once you pick it from the catalog).")
        elseif ent and TaskTracker.CollectableEntryIsManualOnly and TaskTracker.CollectableEntryIsManualOnly(ent) then
            collHowToFs:SetText("Manual-only collectable: progress is not read from the game—use the task row in the list to increment/decrement after you add this task.")
        else
            collHowToFs:SetText("Select a collectable. Progress increases when linked daily rare bonus quests complete in-game.")
        end
        collHowToFs:SetHeight(56)
        collGoalLbl:ClearAllPoints()
        collGoalLbl:SetPoint("TOPLEFT", collHowToFs, "BOTTOMLEFT", 0, -8)
        collGoalInput:ClearAllPoints()
        collGoalInput:SetPoint("TOPLEFT", collGoalLbl, "BOTTOMLEFT", 0, -6)
    end

    local function applyCatalogGoalDefault()
        local ent = TaskTracker.GetCollectableEntry
            and TaskTracker.GetCollectableEntry(state.collectExpSel, state.collectCatSel, state.collEntrySelId)
        if not ent then return end
        local g = tonumber(ent.defaultGoal)
        if g and g >= 1 then
            collGoalInput:SetText(tostring(math.floor(g)))
            return
        end
        local farmish = ent.farm == true
            or (type(ent.questIds) == "table" and #ent.questIds > 0)
            or (TaskTracker.CollectableEntryHasFishingRules and TaskTracker.CollectableEntryHasFishingRules(ent))
            or (TaskTracker.CollectableEntryIsManualOnly and TaskTracker.CollectableEntryIsManualOnly(ent))
        collGoalInput:SetText(farmish and "30" or "1")
    end

    local collExpMenuRows = {}
    local collCatMenuRows = {}

    local function buildCollExpMenu()
        for _, r in ipairs(collExpMenuRows) do
            r:Hide()
            r:SetParent(nil)
        end
        wipe(collExpMenuRows)
        local list = TaskTracker.GetCollectableExpansionList and TaskTracker.GetCollectableExpansionList() or {}
        collExpMenu:SetSize(138, math.max(8, #list * 22 + 8))
        for i, ex in ipairs(list) do
            if ex and ex.id then
                local cap = ex.id
                local row = TaskTracker.MakeButton(collExpMenu, ex.label or cap, 128, 20)
                row:SetPoint("TOPLEFT", collExpMenu, "TOPLEFT", 5, -4 - (i - 1) * 22)
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)
                row:SetScript("OnClick", function()
                    state.collectExpSel = cap
                    state.collEntrySelId = nil
                    closeCollExpCatMenus()
                    syncCollExpDdLabel()
                    rebuildCollEntryMenu()
                    syncCollHowTo()
                    applyCatalogGoalDefault()
                end)
                collExpMenuRows[#collExpMenuRows + 1] = row
            end
        end
    end

    local function buildCollCatMenu()
        for _, r in ipairs(collCatMenuRows) do
            r:Hide()
            r:SetParent(nil)
        end
        wipe(collCatMenuRows)
        local cats = TaskTracker.GetCollectableCategories and TaskTracker.GetCollectableCategories() or {}
        collCatMenu:SetSize(138, math.max(8, #cats * 22 + 8))
        for i, c in ipairs(cats) do
            if c and c.id then
                local cap = c.id
                local row = TaskTracker.MakeButton(collCatMenu, c.label or cap, 128, 20)
                row:SetPoint("TOPLEFT", collCatMenu, "TOPLEFT", 5, -4 - (i - 1) * 22)
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)
                row:SetScript("OnClick", function()
                    state.collectCatSel = cap
                    state.collEntrySelId = nil
                    closeCollExpCatMenus()
                    syncCollCatDdLabel()
                    rebuildCollEntryMenu()
                    syncCollHowTo()
                    applyCatalogGoalDefault()
                end)
                collCatMenuRows[#collCatMenuRows + 1] = row
            end
        end
    end

    rebuildCollEntryMenu = function(preferEntryId)
        clearCollEntryRows()
        collEntryMenu:Hide()
        closeCollExpCatMenus()
        collEntryScroll:SetVerticalScroll(0)
        local entries = (TaskTracker.GetCollectableEntriesForPicker and TaskTracker.GetCollectableEntriesForPicker(state.collectExpSel, state.collectCatSel))
            or (TaskTracker.GetCollectableEntries and TaskTracker.GetCollectableEntries(state.collectExpSel, state.collectCatSel))
            or {}
        if #entries == 0 then
            collPickBtn:SetLabel("(none in catalog)")
            state.collEntrySelId = nil
            syncCollHowTo()
            if collEntryScroll.UpdateScrollBar then
                collEntryScroll:UpdateScrollBar()
            end
            return
        end
        local rowCount = #entries
        local contentH = 8 + rowCount * COLL_MENU_ROW_H + math.max(0, rowCount - 1) * COLL_MENU_GAP
        local viewCapH = 8 + COLL_MENU_MAX_ROWS * COLL_MENU_ROW_H + math.max(0, COLL_MENU_MAX_ROWS - 1) * COLL_MENU_GAP
        local menuH = math.min(viewCapH, contentH)
        collEntryMenu:SetHeight(menuH)
        local menuInnerW = math.max(160, (collEntryMenu:GetWidth() or 260) - 16)
        collEntryScrollChild:SetSize(menuInnerW, math.max(contentH, menuH))

        local y = -4
        local rowBtnW = math.max(120, menuInnerW - 8)
        for i, ent in ipairs(entries) do
            if ent and ent.id and ent.label then
                local row = TaskTracker.MakeButton(collEntryScrollChild, ent.label, rowBtnW, COLL_MENU_ROW_H)
                row:SetPoint("TOPLEFT", collEntryScrollChild, "TOPLEFT", 4, y)
                y = y - (COLL_MENU_ROW_H + COLL_MENU_GAP)
                row:SetScript("OnEnter", function()
                    TaskTracker.SetColor(row.bg, "accentBg")
                    TaskTracker.SetTextColor(row.label, "textAccent")
                end)
                row:SetScript("OnLeave", function()
                    refreshCollEntryRowStyles()
                end)
                row:SetScript("OnClick", function()
                    state.collEntrySelId = ent.id
                    collPickBtn:SetLabel(ent.label)
                    collEntryMenu:Hide()
                    refreshCollEntryRowStyles()
                    syncCollHowTo()
                    applyCatalogGoalDefault()
                    if state.onEntryPicked then state.onEntryPicked() end
                end)
                collEntryRows[ent.id] = row
            end
        end
        if preferEntryId and collEntryRows[preferEntryId] then
            state.collEntrySelId = preferEntryId
        elseif not state.collEntrySelId or not collEntryRows[state.collEntrySelId] then
            state.collEntrySelId = entries[1] and entries[1].id or nil
        end
        local entSel = TaskTracker.GetCollectableEntry(state.collectExpSel, state.collectCatSel, state.collEntrySelId)
        collPickBtn:SetLabel((entSel and entSel.label) or "Select…")
        refreshCollEntryRowStyles()
        syncCollHowTo()
        if collEntryScroll.UpdateScrollBar then
            collEntryScroll:UpdateScrollBar()
        end
    end

    collPickBtn:SetScript("OnClick", function()
        if collEntryMenu:IsShown() then
            collEntryMenu:Hide()
        else
            closeCollExpCatMenus()
            rebuildCollEntryMenu(state.collEntrySelId)
            collEntryMenu:Show()
            collEntryMenu:Raise()
            if collEntryScroll.UpdateScrollBar then
                collEntryScroll:UpdateScrollBar()
            end
        end
    end)

    collExpDdBtn:SetScript("OnClick", function()
        if collExpMenu:IsShown() then
            collExpMenu:Hide()
        else
            closeCollExpCatMenus()
            buildCollExpMenu()
            collExpMenu:Show()
            collExpMenu:Raise()
        end
    end)

    collCatDdBtn:SetScript("OnClick", function()
        if collCatMenu:IsShown() then
            collCatMenu:Hide()
        else
            closeCollExpCatMenus()
            buildCollCatMenu()
            collCatMenu:Show()
            collCatMenu:Raise()
        end
    end)

    buildCollExpMenu()
    buildCollCatMenu()

    local function syncCollectableControlWidths()
        local w = optCollectable:GetWidth() or 300
        local pw = math.max(200, math.floor(w - 12))
        collPickBtn:SetSize(pw, 20)
        collEntryMenu:SetWidth(pw)
        collHowToFs:SetWidth(math.max(200, w - 12))
    end

    local function resetForm()
        state.collectExpSel = "midnight"
        state.collectCatSel = "mount"
        state.collEntrySelId = nil
        syncCollExpDdLabel()
        syncCollCatDdLabel()
        syncCollHidePickMini()
        rebuildCollEntryMenu()
        collGoalInput:SetText("30")
        applyCatalogGoalDefault()
        syncCollectableControlWidths()
    end
    resetForm()

    local function loadFromNode(node, a)
        state.collectExpSel = a.collectableExpansion or "midnight"
        state.collectCatSel = a.collectableCategory or "mount"
        state.collEntrySelId = a.collectableEntryId or nil
        local expList = TaskTracker.GetCollectableExpansionList and TaskTracker.GetCollectableExpansionList() or {}
        local expOk = false
        for _, ex in ipairs(expList) do
            if ex and ex.id == state.collectExpSel then
                expOk = true
                break
            end
        end
        if not expOk and expList[1] and expList[1].id then
            state.collectExpSel = expList[1].id
        end
        syncCollExpDdLabel()
        syncCollCatDdLabel()
        syncCollHidePickMini()
        rebuildCollEntryMenu(state.collEntrySelId)
        collGoalInput:SetText(tostring(node.taskMax or 1))
        syncCollHowTo()
    end

    local function collect(adv)
        adv.collectableExpansion = state.collectExpSel
        adv.collectableCategory = state.collectCatSel
        adv.collectableEntryId = state.collEntrySelId or ""
        adv.collectableQuestIds = {}
        local ent = TaskTracker.GetCollectableEntry
            and TaskTracker.GetCollectableEntry(state.collectExpSel, state.collectCatSel, state.collEntrySelId)
        if ent and type(ent.questIds) == "table" then
            for _, q in ipairs(ent.questIds) do
                local n = tonumber(q)
                if n and n > 0 then
                    adv.collectableQuestIds[#adv.collectableQuestIds + 1] = n
                end
            end
        end
        local tm = tonumber(collGoalInput:GetText()) or 1
        if tm < 1 then tm = 1 end
        if tm > 99999999 then tm = 99999999 end
        return tm
    end

    local function onShow()
        syncCollectableControlWidths()
        syncCollHidePickMini()
        syncCollHowTo()
    end

    return {
        panel = optCollectable,
        collGoalInput = collGoalInput,
        entryMenu = collEntryMenu,
        state = state,
        resetForm = resetForm,
        loadFromNode = loadFromNode,
        collect = collect,
        closeMenus = closeCollExpCatMenus,
        syncLayout = syncCollectableControlWidths,
        onShow = onShow,
    }
end

-- ─────────────────────────────────────
-- Second line (display only; not the task goal)
-- ─────────────────────────────────────
local function CreateTaskDialogSubtextUi(content, hooks)
    hooks = hooks or {}
    local fieldW = hooks.fieldWidth or 260
    local boxW = fieldW
    local colGap = 4
    local halfW = math.floor((boxW - colGap) / 2)
    local thirdW = math.floor((boxW - colGap * 2) / 3)
    local kind = "none"
    local locked = false
    local useTask = false
    local showLifetime = true
    local showDrop = false
    local repDisplay = "paragon"
    local itemKind = "item"
    local itemAttTotal = false
    local LABELS = {
        none = "None",
        reputation = "Reputation",
        mob_kill = "Mob Kills",
        collectable = "Collectable",
        item = "Items",
        quest = "Quest",
        achievement = "Achievement",
        gold = "Gold",
    }
    local ORDER = { "none", "reputation", "mob_kill", "collectable", "item", "quest", "achievement", "gold" }
    local EXTRA = {
        none = 0,
        reputation = 80,
        mob_kill = 200,
        collectable = 84,
        item = 188,
        quest = 84,
        achievement = 180,
        gold = 52,
    }

    local host = CreateFrame("Frame", nil, content)
    host:SetHeight(50)
    local label = MakeLabel(host, "Second line:", host, "TOPLEFT", 0, 0)
    local drop = TaskTracker.MakeButton(host, LABELS.none, fieldW - 32, 22)
    TaskTracker.AttachDropdownArrow(drop)
    drop:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    drop:SetScript("OnEnter", nil)
    drop:SetScript("OnLeave", nil)
    local removeBtn = TaskTracker.MakeButton(host, "x", 28, 22)
    removeBtn:SetPoint("LEFT", drop, "RIGHT", 4, 0)
    removeBtn:SetScript("OnEnter", nil)
    removeBtn:SetScript("OnLeave", nil)

    local menu = CreateFrame("Frame", nil, host)
    if TaskTracker.RegisterOpenDropdown then TaskTracker.RegisterOpenDropdown(menu) end
    menu:SetSize(fieldW - 32, #ORDER * 24 + 8)
    menu:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -2)
    menu:SetFrameLevel((host:GetFrameLevel() or 0) + 30)
    TaskTracker.MakeBorder(menu, "border")
    local menuBg = menu:CreateTexture(nil, "BACKGROUND")
    menuBg:SetAllPoints()
    TaskTracker.SetColor(menuBg, "inputBg")
    menu:EnableMouse(true)
    menu:Hide()

    local opt = CreateFrame("Frame", nil, host)
    opt:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -6)
    opt:SetPoint("TOPRIGHT", drop, "BOTTOMRIGHT", 0, -6)
    opt:SetHeight(240)
    opt:Hide()

    local repLbl = MakeLabel(opt, "Faction (id, name, or link):", opt, "TOPLEFT", 0, 0)
    local repInput = MakeInput(opt, "TTSubRep", fieldW, repLbl)
    repInput:SetMaxLetters(120)
    local repPar = TaskTracker.MakeButton(opt, "Paragon", thirdW, 22)
    local repRen = TaskTracker.MakeButton(opt, "Renown", thirdW, 22)
    local repSta = TaskTracker.MakeButton(opt, "Standing", thirdW, 22)
    repPar:SetPoint("TOPLEFT", repInput, "BOTTOMLEFT", 0, -6)
    repRen:SetPoint("LEFT", repPar, "RIGHT", 4, 0)
    repSta:SetPoint("LEFT", repRen, "RIGHT", 4, 0)

    local mobCopy = TaskTracker.MakeIconButton(opt, 22, 22, { normalBgKey = "headerBg", hoverBgKey = "accentBg" })
    local mobCopyLbl = TaskTracker.MakeButton(opt, "Same mobs as this task", boxW - 26, 22)
    mobCopyLbl:SetPoint("LEFT", mobCopy, "RIGHT", 4, 0)
    local mobHint = MakeLabel(opt, "This collectable isn't tracked by mob kills.", mobCopy, "BOTTOMLEFT", 0, -4)
    mobHint:SetWidth(fieldW)
    mobHint:SetWordWrap(true)
    mobHint:SetJustifyH("LEFT")
    local mobLbl = MakeLabel(opt, "Mob ids:", opt, "TOPLEFT", 0, 0)
    local mobInput = MakeInput(opt, "TTSubMob", fieldW, mobLbl)
    mobInput:SetMaxLetters(500)
    local mobLife = TaskTracker.MakeButton(opt, "Lifetime kills", halfW, 22)
    local mobDrop = TaskTracker.MakeButton(opt, "Rarity Drop Rate", halfW, 22)
    local dropLbl = MakeLabel(opt, "Item id for the drop:", mobLife, "BOTTOMLEFT", 0, -8)
    local dropInput = MakeInput(opt, "TTSubDrop", boxW, dropLbl)
    dropInput:SetMaxLetters(10)

    local collThis = TaskTracker.MakeButton(opt, "This collectable", boxW, 22)
    collThis:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, 0)
    local collLbl = MakeLabel(opt, "Item id:", collThis, "BOTTOMLEFT", 0, -8)
    local collInput = MakeInput(opt, "TTSubColl", boxW, collLbl)
    collInput:SetMaxLetters(10)

    local itemThis = TaskTracker.MakeButton(opt, "This task's items", boxW, 22)
    itemThis:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, 0)
    local itemIdsLbl = MakeLabel(opt, "Ids:", itemThis, "BOTTOMLEFT", 0, -8)
    local itemInput = MakeInput(opt, "TTSubItem", boxW, itemIdsLbl)
    itemInput:SetMaxLetters(180)
    local itemBtn = TaskTracker.MakeButton(opt, "Items", halfW, 22)
    local curBtn = TaskTracker.MakeButton(opt, "Currency", halfW, 22)
    itemBtn:SetPoint("TOPLEFT", itemInput, "BOTTOMLEFT", 0, -6)
    curBtn:SetPoint("LEFT", itemBtn, "RIGHT", colGap, 0)
    local itemGoalLbl = MakeLabel(opt, "Goal (optional):", itemBtn, "BOTTOMLEFT", 0, -8)
    local itemGoalInput = MakeInput(opt, "TTSubItemGoal", boxW, itemGoalLbl)
    itemGoalInput:SetMaxLetters(8)
    itemGoalInput:SetNumeric(true)
    local itemAtt = TaskTracker.MakeButton(opt, "AllTheThings total", boxW, 22)
    itemAtt:SetPoint("TOPLEFT", itemGoalInput, "BOTTOMLEFT", 0, -6)

    local questThis = TaskTracker.MakeButton(opt, "This task's quests", boxW, 22)
    questThis:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, 0)
    local questLbl = MakeLabel(opt, "Quest ids:", questThis, "BOTTOMLEFT", 0, -8)
    local questInput = MakeInput(opt, "TTSubQuest", fieldW, questLbl)
    questInput:SetMaxLetters(180)

    local achThis = TaskTracker.MakeButton(opt, "This achievement", boxW, 22)
    achThis:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, 0)
    local achLbl = MakeLabel(opt, "Achievement id:", achThis, "BOTTOMLEFT", 0, -8)
    local achInput = MakeInput(opt, "TTSubAch", boxW, achLbl)
    achInput:SetMaxLetters(10)
    local achMode = "game"
    local achModeLbl = MakeLabel(opt, "Progress mode:", achInput, "BOTTOMLEFT", 0, -8)
    local achWeekBtn = TaskTracker.MakeButton(opt, "Weekly target", halfW, 22)
    local achGameBtn = TaskTracker.MakeButton(opt, "In-game bar", halfW, 22)
    achWeekBtn:SetPoint("TOPLEFT", achModeLbl, "BOTTOMLEFT", 0, -4)
    achGameBtn:SetPoint("LEFT", achWeekBtn, "RIGHT", colGap, 0)
    local achGoalLbl = MakeLabel(opt, "Weekly goal:", achWeekBtn, "BOTTOMLEFT", 0, -8)
    local achGoalInput = MakeInput(opt, "TTSubAchGoal", boxW, achGoalLbl)
    achGoalInput:SetMaxLetters(6)
    achGoalInput:SetNumeric(true)

    local goldHint = MakeLabel(opt, "Gold you earn until this task resets.", opt, "TOPLEFT", 0, 0)
    local goldThis = TaskTracker.MakeButton(opt, "This task's gold", boxW, 22)
    goldThis:SetPoint("TOPLEFT", goldHint, "BOTTOMLEFT", 0, -6)

    local function paintToggles()
        TaskTracker.SetExclusiveButtonActive({
            paragon = repPar, renown = repRen, standing = repSta,
        }, repDisplay)
        if useTask then
            mobCopy:SetIconAtlas(TaskTracker.FirstValidAtlas("Tracker-Check", "common-icon-checkmark", "common-icon-check"), true)
        else
            mobCopy:SetIconAtlas(nil)
        end
        TaskTracker.SetButtonActive(mobCopyLbl, useTask)
        TaskTracker.SetButtonActive(mobLife, showLifetime)
        TaskTracker.SetButtonActive(mobDrop, showDrop)
        TaskTracker.SetButtonActive(collThis, useTask)
        TaskTracker.SetButtonActive(itemThis, useTask)
        TaskTracker.SetButtonActive(questThis, useTask)
        TaskTracker.SetButtonActive(achThis, useTask)
        TaskTracker.SetExclusiveButtonActive({ weekly = achWeekBtn, game = achGameBtn }, achMode)
        TaskTracker.SetButtonActive(goldThis, useTask)
        TaskTracker.SetExclusiveButtonActive({ item = itemBtn, currency = curBtn }, itemKind)
        TaskTracker.SetButtonActive(itemAtt, itemAttTotal)
    end

    local function taskKindNow()
        return hooks.getTaskKind and hooks.getTaskKind() or "basic"
    end

    local function mainMobIdText()
        local src = hooks.getMobIdText and hooks.getMobIdText() or ""
        if type(src) ~= "string" then return "" end
        return src
    end

    local function collectableItemText()
        local id = tonumber(hooks.getCollectableItemId and hooks.getCollectableItemId())
        if id and id > 0 then return tostring(math.floor(id)) end
        return ""
    end

    local function layoutMobButtons()
        local src = mainMobIdText()
        local tk = taskKindNow()
        local offerCopy = tk == "collectable" or src ~= ""
        local noMobList = tk == "collectable" and src == ""
        if offerCopy then
            mobCopy:Show()
            mobCopyLbl:Show()
            mobCopy:ClearAllPoints()
            mobCopy:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, 0)
            mobLbl:ClearAllPoints()
            if noMobList then
                mobHint:Show()
                mobLbl:SetPoint("TOPLEFT", mobHint, "BOTTOMLEFT", 0, -8)
            else
                mobHint:Hide()
                mobLbl:SetPoint("TOPLEFT", mobCopy, "BOTTOMLEFT", 0, -8)
            end
        else
            mobCopy:Hide()
            mobCopyLbl:Hide()
            mobHint:Hide()
            useTask = false
            mobLbl:ClearAllPoints()
            mobLbl:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, 0)
        end
        if useTask and src ~= "" then
            mobInput:SetText(src)
            mobInput:Disable()
        elseif useTask and tk == "collectable" then
            mobInput:SetText("")
            mobInput:Disable()
        else
            mobInput:Enable()
        end
        local itemText = collectableItemText()
        if useTask and tk == "collectable" and itemText ~= "" then
            dropInput:SetText(itemText)
            dropInput:Disable()
        else
            dropInput:Enable()
        end
        mobLife:ClearAllPoints()
        mobLife:SetWidth(halfW)
        mobLife:SetPoint("TOPLEFT", mobInput, "BOTTOMLEFT", 0, -6)
        mobDrop:ClearAllPoints()
        mobDrop:SetWidth(halfW)
        mobDrop:SetPoint("LEFT", mobLife, "RIGHT", colGap, 0)
        dropLbl:ClearAllPoints()
        dropLbl:SetPoint("TOPLEFT", mobLife, "BOTTOMLEFT", 0, -8)
    end

    local function showRows()
        repLbl:Hide(); repInput:Hide(); repPar:Hide(); repRen:Hide(); repSta:Hide()
        mobLbl:Hide(); mobInput:Hide(); mobCopy:Hide(); mobCopyLbl:Hide(); mobHint:Hide(); mobLife:Hide(); mobDrop:Hide()
        dropLbl:Hide(); dropInput:Hide()
        collThis:Hide(); collLbl:Hide(); collInput:Hide()
        itemThis:Hide(); itemIdsLbl:Hide(); itemInput:Hide(); itemBtn:Hide(); curBtn:Hide()
        itemGoalLbl:Hide(); itemGoalInput:Hide(); itemAtt:Hide()
        questThis:Hide(); questLbl:Hide(); questInput:Hide()
        achThis:Hide(); achLbl:Hide(); achInput:Hide()
        achModeLbl:Hide(); achWeekBtn:Hide(); achGameBtn:Hide(); achGoalLbl:Hide(); achGoalInput:Hide()
        goldHint:Hide(); goldThis:Hide()
        local tk = taskKindNow()
        if kind == "none" then
            opt:Hide()
        else
            opt:Show()
        end
        if kind == "reputation" then
            repLbl:Show(); repInput:Show(); repPar:Show(); repRen:Show(); repSta:Show()
        elseif kind == "mob_kill" then
            mobLife:Show(); mobDrop:Show()
            mobLbl:Show(); mobInput:Show()
            layoutMobButtons()
            if showDrop then
                dropLbl:Show(); dropInput:Show()
            end
        elseif kind == "collectable" then
            if tk == "collectable" then collThis:Show() else useTask = false end
            if not useTask then
                collLbl:ClearAllPoints()
                if collThis:IsShown() then
                    collLbl:SetPoint("TOPLEFT", collThis, "BOTTOMLEFT", 0, -8)
                else
                    collLbl:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, 0)
                end
                collLbl:Show(); collInput:Show()
            end
        elseif kind == "item" then
            if tk == "item" then itemThis:Show() else useTask = false end
            local goalAnchor = opt
            if not useTask then
                itemIdsLbl:ClearAllPoints()
                if itemThis:IsShown() then
                    itemIdsLbl:SetPoint("TOPLEFT", itemThis, "BOTTOMLEFT", 0, -8)
                    goalAnchor = itemThis
                else
                    itemIdsLbl:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, 0)
                end
                itemIdsLbl:Show(); itemInput:Show(); itemBtn:Show(); curBtn:Show()
                goalAnchor = itemBtn
            elseif itemThis:IsShown() then
                goalAnchor = itemThis
            end
            itemGoalLbl:ClearAllPoints()
            itemGoalLbl:SetPoint("TOPLEFT", goalAnchor, "BOTTOMLEFT", 0, -8)
            itemGoalLbl:Show()
            itemGoalInput:Show()
            itemAtt:Show()
        elseif kind == "quest" then
            if tk == "quest" then questThis:Show() else useTask = false end
            if not useTask then
                questLbl:ClearAllPoints()
                if questThis:IsShown() then
                    questLbl:SetPoint("TOPLEFT", questThis, "BOTTOMLEFT", 0, -8)
                else
                    questLbl:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, 0)
                end
                questLbl:Show(); questInput:Show()
            end
        elseif kind == "achievement" then
            if tk == "achievement" then achThis:Show() else useTask = false end
            local modeAnchor = opt
            if not useTask then
                achLbl:ClearAllPoints()
                if achThis:IsShown() then
                    achLbl:SetPoint("TOPLEFT", achThis, "BOTTOMLEFT", 0, -8)
                else
                    achLbl:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, 0)
                end
                achLbl:Show(); achInput:Show()
                modeAnchor = achInput
            elseif achThis:IsShown() then
                modeAnchor = achThis
            end
            achModeLbl:ClearAllPoints()
            achModeLbl:SetPoint("TOPLEFT", modeAnchor, "BOTTOMLEFT", 0, -8)
            achModeLbl:Show()
            achWeekBtn:Show()
            achGameBtn:Show()
            if achMode == "weekly" then
                achGoalLbl:Show()
                achGoalInput:Show()
            end
        elseif kind == "gold" then
            goldHint:Show()
            if tk == "gold" then goldThis:Show() else useTask = false end
        end
        paintToggles()
        drop:SetLabel(LABELS[kind] or LABELS.none)
        TaskTracker.SetButtonActive(drop, kind ~= "none")
    end

    local function bump()
        showRows()
        if hooks.requestHeight then hooks.requestHeight() end
    end

    local menuRows = {}
    for i, k in ipairs(ORDER) do
        local row = TaskTracker.MakeButton(menu, LABELS[k], fieldW - 40, 22)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 24)
        row:SetScript("OnClick", function()
            kind = k
            if k == "mob_kill" then
                showLifetime = true
                if taskKindNow() == "collectable" or mainMobIdText() ~= "" then
                    useTask = true
                end
            end
            if k == "gold" and taskKindNow() == "gold" then useTask = true end
            if k == "collectable" and taskKindNow() == "collectable" then useTask = true end
            menu:Hide()
            bump()
        end)
        menuRows[k] = row
    end

    drop:SetScript("OnClick", function()
        if locked then return end
        if menu:IsShown() then menu:Hide() else menu:Show(); menu:Raise() end
    end)
    local function setRep(mode)
        repDisplay = mode
        paintToggles()
    end
    repPar:SetScript("OnClick", function() setRep("paragon") end)
    repRen:SetScript("OnClick", function() setRep("renown") end)
    repSta:SetScript("OnClick", function() setRep("standing") end)
    local function toggleMobCopy()
        if useTask then
            useTask = false
        else
            local src = mainMobIdText()
            if src == "" then return end
            mobInput:SetText(src)
            useTask = true
        end
        bump()
    end
    mobCopy:SetScript("OnClick", toggleMobCopy)
    mobCopyLbl:SetScript("OnClick", toggleMobCopy)
    mobLife:SetScript("OnClick", function() showLifetime = not showLifetime; paintToggles() end)
    mobDrop:SetScript("OnClick", function() showDrop = not showDrop; bump() end)
    collThis:SetScript("OnClick", function() useTask = not useTask; bump() end)
    itemThis:SetScript("OnClick", function() useTask = not useTask; bump() end)
    questThis:SetScript("OnClick", function() useTask = not useTask; bump() end)
    achThis:SetScript("OnClick", function() useTask = not useTask; bump() end)
    achWeekBtn:SetScript("OnClick", function() achMode = "weekly"; bump() end)
    achGameBtn:SetScript("OnClick", function() achMode = "game"; bump() end)
    goldThis:SetScript("OnClick", function() useTask = not useTask; bump() end)
    itemBtn:SetScript("OnClick", function() itemKind = "item"; paintToggles() end)
    curBtn:SetScript("OnClick", function() itemKind = "currency"; paintToggles() end)
    itemAtt:SetScript("OnClick", function() itemAttTotal = not itemAttTotal; paintToggles() end)

    local function idsToText(list)
        if type(list) ~= "table" then return "" end
        local parts = {}
        for _, id in ipairs(list) do
            parts[#parts + 1] = tostring(id)
        end
        return table.concat(parts, " ")
    end

    return {
        host = host,
        isLocked = function() return locked end,
        isSet = function() return kind ~= "none" end,
        setLocked = function(v)
            locked = v and true or false
            if locked then
                menu:Hide()
                host:Hide()
            end
        end,
        blockHeight = function()
            if locked then return 0 end
            return 50 + (EXTRA[kind] or 0)
        end,
        hideMenu = function() menu:Hide() end,
        menu = menu,
        drop = drop,
        removeBtn = removeBtn,
        reset = function(keepHidden)
            kind = "none"
            locked = false
            useTask = false
            showLifetime = true
            showDrop = false
            repDisplay = "paragon"
            itemKind = "item"
            itemAttTotal = false
            achMode = "game"
            repInput:SetText("")
            mobInput:SetText("")
            dropInput:SetText("")
            collInput:SetText("")
            itemInput:SetText("")
            itemGoalInput:SetText("")
            questInput:SetText("")
            achInput:SetText("")
            achGoalInput:SetText("")
            if not keepHidden then host:Show() end
            showRows()
        end,
        load = function(node)
            local s = node and node.subtext
            kind = "none"
            useTask = false
            showLifetime = true
            showDrop = false
            repDisplay = "paragon"
            itemKind = "item"
            itemAttTotal = false
            achMode = "game"
            repInput:SetText("")
            mobInput:SetText("")
            dropInput:SetText("")
            collInput:SetText("")
            itemInput:SetText("")
            itemGoalInput:SetText("")
            questInput:SetText("")
            achInput:SetText("")
            achGoalInput:SetText("")
            if type(s) == "table" and LABELS[s.type] then
                kind = s.type
                useTask = s.useTask == true
                if s.type == "reputation" then
                    repDisplay = s.repDisplay or "paragon"
                    if (tonumber(s.repFactionId) or 0) > 0 then
                        repInput:SetText(tostring(s.repFactionId))
                    else
                        repInput:SetText(s.repFactionName or "")
                    end
                elseif s.type == "mob_kill" then
                    showLifetime = s.showLifetime ~= false
                    showDrop = s.showDrop == true
                    mobInput:SetText(idsToText(s.mobIds))
                    if (tonumber(s.dropItemId) or 0) > 0 then
                        dropInput:SetText(tostring(s.dropItemId))
                    end
                elseif s.type == "collectable" then
                    if (tonumber(s.itemId) or 0) > 0 then
                        collInput:SetText(tostring(s.itemId))
                    end
                elseif s.type == "item" then
                    itemKind = s.itemKind or "item"
                    itemAttTotal = s.itemAttTotal == true
                    itemInput:SetText(idsToText(s.itemIds))
                    if (tonumber(s.itemGoal) or 0) > 0 then
                        itemGoalInput:SetText(tostring(math.floor(s.itemGoal)))
                    end
                elseif s.type == "quest" then
                    questInput:SetText(idsToText(s.questIds))
                elseif s.type == "achievement" then
                    achMode = (s.achievementTrackMode == "weekly") and "weekly" or "game"
                    if (tonumber(s.achievementId) or 0) > 0 then
                        achInput:SetText(tostring(s.achievementId))
                    end
                    if (tonumber(s.achievementGoal) or 0) > 0 then
                        achGoalInput:SetText(tostring(math.floor(s.achievementGoal)))
                    end
                end
            end
            if kind == "mob_kill" and not useTask and taskKindNow() == "collectable" and mobInput:GetText() == "" then
                useTask = true
            end
            if not locked then host:Show() end
            showRows()
        end,
        collect = function(prev)
            if locked or kind == "none" then return nil end
            local s = { type = kind }
            if type(prev) == "table" and prev.type == kind then
                if prev.lifetimeKills ~= nil then s.lifetimeKills = prev.lifetimeKills end
                if prev.goldPeriodCopper ~= nil then s.goldPeriodCopper = prev.goldPeriodCopper end
            end
            if useTask then s.useTask = true end
            if kind == "reputation" then
                local fid, fname = TaskTracker.ParseFactionIdFromText(repInput:GetText())
                s.repFactionId = fid or 0
                s.repFactionName = fname or ""
                s.repDisplay = repDisplay
            elseif kind == "mob_kill" then
                s.showLifetime = showLifetime == true
                s.showDrop = showDrop == true
                if not useTask then
                    s.mobIds = TaskTracker.ParseMobIdListFromText(mobInput:GetText())
                end
                local dropId = tonumber(dropInput:GetText())
                if dropId and dropId > 0 then s.dropItemId = math.floor(dropId) end
            elseif kind == "collectable" then
                if not useTask then
                    local itemId = tonumber(collInput:GetText())
                    if itemId and itemId > 0 then
                        s.itemId = math.floor(itemId)
                        local spec = TaskTracker.FindCollectableSpecByItemId and TaskTracker.FindCollectableSpecByItemId(itemId)
                        if spec then
                            s.collectableExpansion = spec.expansion
                            s.collectableCategory = spec.category
                            s.collectableEntryId = spec.entryId
                        end
                    end
                end
            elseif kind == "item" then
                s.itemKind = itemKind
                if not useTask then
                    if itemKind == "currency" then
                        s.itemIds = TaskTracker.ParseCurrencyIdListFromText(itemInput:GetText())
                    else
                        s.itemIds = TaskTracker.ParseItemIdListFromText(itemInput:GetText())
                    end
                end
                local goal = tonumber(itemGoalInput:GetText())
                if goal and goal > 0 then
                    s.itemGoal = math.floor(goal)
                end
                if itemAttTotal then s.itemAttTotal = true end
            elseif kind == "quest" then
                if not useTask then
                    local ids = TaskTracker.ParseQuestListFromText(questInput:GetText())
                    s.questIds = ids
                end
            elseif kind == "achievement" then
                if not useTask then
                    local id = TaskTracker.ParseAchievementIdFromText(achInput:GetText())
                    s.achievementId = id or tonumber(achInput:GetText()) or 0
                end
                s.achievementTrackMode = (achMode == "weekly") and "weekly" or "game"
                if achMode == "weekly" then
                    local goal = tonumber(achGoalInput:GetText())
                    if goal and goal > 0 then
                        s.achievementGoal = math.floor(goal)
                    end
                end
            end
            return s
        end,
        refresh = function()
            showRows()
        end,
    }
end

-- Hide / Keep for completed tasks. Built once with the task window.
-- Stored on the dialog so CreateTaskDialog does not take more locals.
function TaskTracker.AttachTaskKeepShownToggle(dialog, rightCol, anchorBtn, innerW, btnW)
    local lbl = MakeLabel(rightCol, "When completed tasks are hidden:", anchorBtn, "BOTTOMLEFT", 0, -10)
    lbl:SetWidth(innerW)
    lbl:SetWordWrap(true)
    local hideBtn = TaskTracker.MakeButton(rightCol, "Hide", btnW, 22)
    hideBtn:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -6)
    local keepBtn = TaskTracker.MakeButton(rightCol, "Keep", btnW, 22)
    keepBtn:SetPoint("LEFT", hideBtn, "RIGHT", 4, 0)
    local function paint()
        TaskTracker.SetExclusiveButtonActive({
            hide = hideBtn,
            keep = keepBtn,
        }, dialog._keepShown and "keep" or "hide")
    end
    local function tipBtn(btn, title, body)
        btn:SetScript("OnEnter", function()
            if TaskTracker.ShowTipBesideFrame then
                TaskTracker.ShowTipBesideFrame(dialog, title, body)
            end
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    tipBtn(hideBtn, "Hide", "This task leaves the list with the other completed tasks.")
    tipBtn(keepBtn, "Keep", "This task stays on the list when completed tasks are hidden.")
    hideBtn:SetScript("OnClick", function()
        dialog._keepShown = false
        paint()
    end)
    keepBtn:SetScript("OnClick", function()
        dialog._keepShown = true
        paint()
    end)
    dialog._keepShown = false
    dialog._setKeepShown = function(on)
        dialog._keepShown = on == true
        paint()
    end
    paint()
end

-- ─────────────────────────────────────
-- Task Dialog
-- ─────────────────────────────────────
function TaskTracker.CreateTaskDialog()
    dialogLabelColor = "textAccent"
    -- Height tuned in setDialogHeight(). Left column is the task settings (grey, like Options).
    -- Right column is the task itself, on the panel background.
    local DIALOG_W = 520
    local OPT_W = 176
    local OPT_PAD = 8
    local OPT_INNER = OPT_W - OPT_PAD * 2
    local TASK_PAD = 10
    local FIELD_W = (DIALOG_W - 2) - OPT_W - 1 - TASK_PAD * 2
    local dialog, content, t = MakeDialog("TaskTrackerTaskDialog", DIALOG_W, 480)

    local function tip(btn, title, body)
        if not btn then return end
        btn:SetScript("OnEnter", function()
            if TaskTracker.ShowTipBesideFrame then
                TaskTracker.ShowTipBesideFrame(dialog, title, body)
            end
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Task kind: basic counter task vs automated advanced types (single picker for easier extension).
    local taskKind = "basic" -- "basic" | "gold" | "achievement" | "item" | "quest" | "reputation" | "mob_kill" | "collectable"
    local TASK_KIND_LABELS = {
        basic         = "Basic Task",
        gold          = "Gold",
        achievement   = "Achievement",
        item          = "Items",
        quest         = "Quest",
        reputation    = "Reputation",
        mob_kill      = "Mob Kills",
        collectable   = "Collectable",
    }
    local TASK_KIND_ORDER = { "basic", "gold", "achievement", "item", "quest", "reputation", "mob_kill", "collectable" }

    local nameLabel = MakeLabel(content, "Task Name:", content, "TOPLEFT", 10, -8)
    local nameInput = MakeInput(content, "TaskTrackerDialogInput", FIELD_W, nameLabel)
    local typeLabel = MakeLabel(content, "Task type:", content, "TOPLEFT", 10, -80)
    local typeDropBtn = TaskTracker.MakeButton(content, TASK_KIND_LABELS.basic, FIELD_W, 22)
    TaskTracker.AttachDropdownArrow(typeDropBtn)
    typeDropBtn:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -6)
    typeDropBtn:SetScript("OnEnter", nil)
    typeDropBtn:SetScript("OnLeave", nil)

    local typeMenu = CreateFrame("Frame", nil, content)
    if TaskTracker.RegisterOpenDropdown then TaskTracker.RegisterOpenDropdown(typeMenu) end
    typeMenu:SetSize(FIELD_W, #TASK_KIND_ORDER * 24 + 8)
    typeMenu:SetPoint("TOPLEFT", typeDropBtn, "BOTTOMLEFT", 0, -2)
    typeMenu:SetFrameLevel((dialog:GetFrameLevel() or 0) + 40)
    TaskTracker.MakeBorder(typeMenu, "border")
    local typeMenuBg = typeMenu:CreateTexture(nil, "BACKGROUND")
    typeMenuBg:SetAllPoints()
    TaskTracker.SetColor(typeMenuBg, "inputBg")
    typeMenu:EnableMouse(true)
    typeMenu:Hide()

    local applyTaskKind -- set after advanced panels + sync exist
    local collectAdvancedAndMax
    local typeMenuRows = {}

    local function refreshTypeMenuRowStyles()
        TaskTracker.SetExclusiveButtonActive(typeMenuRows, taskKind)
    end

    -- Keep false (MakeInput default): SetAutoFocus(true) reclaims focus when the frame is shown and
    -- blocks game keybinds after the user clicks elsewhere. OpenAdd/OpenEdit call SetFocus once.

    local rightCol = CreateFrame("Frame", nil, content)
    rightCol:SetWidth(OPT_W)
    local optBg = rightCol:CreateTexture(nil, "BACKGROUND")
    optBg:SetAllPoints()
    TaskTracker.SetColor(optBg, "headerBg2")
    local optSep = rightCol:CreateTexture(nil, "ARTWORK")
    optSep:SetWidth(1)
    optSep:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
    optSep:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
    TaskTracker.SetColor(optSep, "border")
    local resetLabel = MakeLabel(rightCol, "Reset Schedule:", rightCol, "TOPLEFT", OPT_PAD, -10)
    resetLabel:SetWidth(OPT_INNER)
    resetLabel:SetJustifyH("CENTER")

    local selectedReset = "none"
    local resetBtns     = {}
    local resetOptions  = { "none", "daily", "weekly", "temporary" }
    local resetNames    = { none = "None", daily = "Daily", weekly = "Weekly", temporary = "Temporary" }
    local RESET_VALID   = { none = true, daily = true, weekly = true, temporary = true }
    local RESET_GAP     = 4
    local RESET_BTN_W   = math.floor((OPT_INNER - RESET_GAP) / 2)

    local function UpdateResetButtons()
        TaskTracker.SetExclusiveButtonActive(resetBtns, selectedReset)
    end

    local prevBtn = nil
    for _, opt in ipairs(resetOptions) do
        local btn = TaskTracker.MakeButton(rightCol, resetNames[opt], RESET_BTN_W, 22)
        if opt == "none" then
            btn:SetPoint("TOPLEFT", resetLabel, "BOTTOMLEFT", 0, -6)
        elseif opt == "daily" then
            btn:SetPoint("LEFT", resetBtns.none, "RIGHT", RESET_GAP, 0)
        elseif opt == "weekly" then
            btn:SetPoint("TOPLEFT", resetBtns.none, "BOTTOMLEFT", 0, -4)
        else
            btn:SetPoint("LEFT", resetBtns.weekly, "RIGHT", RESET_GAP, 0)
        end
        btn:SetScript("OnEnter", nil)
        btn:SetScript("OnLeave", nil)
        local capturedOpt = opt
        btn:SetScript("OnClick", function()
            selectedReset = capturedOpt
            UpdateResetButtons()
        end)
        if opt == "none" then
            tip(btn, "None", "This task does not reset.")
        elseif opt == "daily" then
            tip(btn, "Daily", "Clears when your daily reset runs.")
        elseif opt == "weekly" then
            tip(btn, "Weekly", "Clears when your weekly reset runs.")
        else
            tip(btn, "Temporary", "Deletes this task when it finishes.")
        end
        resetBtns[opt] = btn
        prevBtn = btn
    end
    UpdateResetButtons()

    local taskScopeAccount = false
    local taskShowOnOtherChars = false
    local scopeLbl = MakeLabel(rightCol, "Progress scope:", resetBtns.weekly, "BOTTOMLEFT", 0, -10)
    scopeLbl:SetWidth(OPT_INNER)
    scopeLbl:SetWordWrap(true)
    local scopeCharBtn = TaskTracker.MakeButton(rightCol, "Character", RESET_BTN_W, 22)
    scopeCharBtn:SetPoint("TOPLEFT", scopeLbl, "BOTTOMLEFT", 0, -6)
    tip(scopeCharBtn, "Character", "Progress stays on this character.")
    local scopeAcctBtn = TaskTracker.MakeButton(rightCol, "Account", RESET_BTN_W, 22)
    scopeAcctBtn:SetPoint("LEFT", scopeCharBtn, "RIGHT", 4, 0)
    tip(scopeAcctBtn, "Account", "Progress is shared by your account.")
    local altLbl = MakeLabel(rightCol, "On other characters:", scopeCharBtn, "BOTTOMLEFT", 0, -10)
    altLbl:SetWidth(OPT_INNER)
    altLbl:SetWordWrap(true)
    local altHiddenBtn = TaskTracker.MakeButton(rightCol, "Hidden", RESET_BTN_W, 22)
    altHiddenBtn:SetPoint("TOPLEFT", altLbl, "BOTTOMLEFT", 0, -6)
    tip(altHiddenBtn, "Hidden", "Other characters do not see this task.")
    local altShownBtn = TaskTracker.MakeButton(rightCol, "Shown", RESET_BTN_W, 22)
    altShownBtn:SetPoint("LEFT", altHiddenBtn, "RIGHT", 4, 0)
    tip(altShownBtn, "Shown", "Other characters can see this task.")
    local function updateAltVisibilityBtns()
        TaskTracker.SetExclusiveButtonActive({
            hidden = altHiddenBtn,
            shown = altShownBtn,
        }, taskShowOnOtherChars and "shown" or "hidden")
    end
    altHiddenBtn:SetScript("OnClick", function()
        taskShowOnOtherChars = false
        updateAltVisibilityBtns()
    end)
    altShownBtn:SetScript("OnClick", function()
        taskShowOnOtherChars = true
        updateAltVisibilityBtns()
    end)
    updateAltVisibilityBtns()
    local rollupGoalLbl = MakeLabel(rightCol, "Count toward parent group goals:", scopeCharBtn, "BOTTOMLEFT", 0, -10)
    rollupGoalLbl:SetWidth(OPT_INNER)
    rollupGoalLbl:SetWordWrap(true)
    local setDialogHeight -- forward declaration; defined after advanced panels
    local function syncCharScopeUi()
        TaskTracker.SetExclusiveButtonActive({
            char = scopeCharBtn,
            account = scopeAcctBtn,
        }, taskScopeAccount and "account" or "char")
        if taskScopeAccount then
            altLbl:Hide()
            altHiddenBtn:Hide()
            altShownBtn:Hide()
            rollupGoalLbl:ClearAllPoints()
            rollupGoalLbl:SetPoint("TOPLEFT", scopeCharBtn, "BOTTOMLEFT", 0, -10)
        else
            altLbl:Show()
            altHiddenBtn:Show()
            altShownBtn:Show()
            updateAltVisibilityBtns()
            rollupGoalLbl:ClearAllPoints()
            rollupGoalLbl:SetPoint("TOPLEFT", altHiddenBtn, "BOTTOMLEFT", 0, -10)
        end
        if setDialogHeight then setDialogHeight() end
    end
    scopeCharBtn:SetScript("OnClick", function()
        taskScopeAccount = false
        syncCharScopeUi()
    end)
    scopeAcctBtn:SetScript("OnClick", function()
        taskScopeAccount = true
        syncCharScopeUi()
    end)
    syncCharScopeUi()

    local TASK_DIALOG_FOOTER_H = 44
    local footer = CreateFrame("Frame", nil, content)
    footer:SetHeight(TASK_DIALOG_FOOTER_H)
    footer:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    footer:SetFrameLevel((content:GetFrameLevel() or 0) + 30)
    TaskTracker.MakeEdge(footer, "TOP", "border")
    rightCol:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    rightCol:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 0)

    local taskCol = CreateFrame("Frame", nil, content)
    taskCol:SetPoint("TOPLEFT", rightCol, "TOPRIGHT", 1, 0)
    taskCol:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
    nameLabel:SetParent(taskCol)
    nameLabel:ClearAllPoints()
    nameLabel:SetPoint("TOPLEFT", taskCol, "TOPLEFT", TASK_PAD, -10)
    nameInput:SetParent(taskCol)
    nameInput:ClearAllPoints()
    nameInput:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -6)
    nameInput:SetWidth(FIELD_W)
    TaskTracker.AttachTaskDialogSideIcons(dialog, rightCol, nameInput, t)
    nameInput:HookScript("OnTextChanged", function(self)
        local w = TaskTracker.noteWindow
        local name = self:GetText()
        if not name or name == "" then name = "New task" end
        if w and w.boundNode and w.boundNode._ttNoteDraft then
            w.boundNode.name = name
        end
        if w and w.boundTaskId then
            w._peekTitle = name
            if TaskTracker.SetNotePeekTitle then
                TaskTracker.SetNotePeekTitle(w.boundTaskId, name)
            end
        end
        if not w or not w:IsShown() or w.anchorHost ~= dialog or not w.TitleText then return end
        w.TitleText:SetText("Notes — " .. name)
    end)
    dialog:HookScript("OnHide", function()
        local w = TaskTracker.noteWindow
        dialog._noteDraft = nil
        if not w or w.anchorHost ~= dialog then return end
        if w:IsShown() and w.FlushNoteToNode then
            w:FlushNoteToNode()
        end
        w.anchorHost = nil
        if TaskTracker.HideNoteWindow then
            TaskTracker.HideNoteWindow()
        end
    end)

    local leftScroll = CreateFrame("ScrollFrame", nil, taskCol)
    leftScroll:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", 0, -8)
    leftScroll:SetPoint("BOTTOMRIGHT", taskCol, "BOTTOMRIGHT", -TASK_PAD, 8)
    leftScroll:EnableMouseWheel(true)
    local leftChild = CreateFrame("Frame", nil, leftScroll)
    leftChild:SetWidth(FIELD_W)
    leftChild:SetHeight(40)
    leftScroll:SetScrollChild(leftChild)
    leftScroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local maxS = 0
        if child then
            maxS = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
        end
        local nextS = (self:GetVerticalScroll() or 0) - delta * 28
        if nextS < 0 then nextS = 0 end
        if nextS > maxS then nextS = maxS end
        self:SetVerticalScroll(nextS)
    end)

    local excludeFromRollupGoals = false
    local rollupIncBtn = TaskTracker.MakeButton(rightCol, "Include", RESET_BTN_W, 22)
    rollupIncBtn:SetPoint("TOPLEFT", rollupGoalLbl, "BOTTOMLEFT", 0, -6)
    tip(rollupIncBtn, "Include", "This count adds into the parent group.")
    local rollupExcBtn = TaskTracker.MakeButton(rightCol, "Exclude", RESET_BTN_W, 22)
    rollupExcBtn:SetPoint("LEFT", rollupIncBtn, "RIGHT", 4, 0)
    tip(rollupExcBtn, "Exclude", "Tracked here, but left out of the parent total.")
    local function updateRollupGoalBtns()
        TaskTracker.SetExclusiveButtonActive({
            include = rollupIncBtn,
            exclude = rollupExcBtn,
        }, excludeFromRollupGoals and "exclude" or "include")
    end
    rollupIncBtn:SetScript("OnClick", function()
        excludeFromRollupGoals = false
        updateRollupGoalBtns()
    end)
    rollupExcBtn:SetScript("OnClick", function()
        excludeFromRollupGoals = true
        updateRollupGoalBtns()
    end)
    updateRollupGoalBtns()
    TaskTracker.AttachTaskKeepShownToggle(dialog, rightCol, rollupIncBtn, OPT_INNER, RESET_BTN_W)

    local goalMode = "all"
    local goals = {}
    local openGoal = 1
    local showSecondLine = false
    local commitOpenGoal
    local MAX_GOALS = 4
    local finishFont = TaskTracker.GetTheme().fontNormal or "GameFontNormalSmall"
    local finishHit = CreateFrame("Button", nil, leftChild)
    finishHit:SetHeight(18)
    local finishPrefix = TaskTracker.CreateFontString(finishHit, nil, "OVERLAY", finishFont)
    local finishLink = TaskTracker.CreateFontString(finishHit, nil, "OVERLAY", finishFont)
    local finishSuffix = TaskTracker.CreateFontString(finishHit, nil, "OVERLAY", finishFont)
    finishSuffix:SetPoint("TOPRIGHT", finishHit, "TOPRIGHT", 0, 0)
    finishLink:SetPoint("TOPRIGHT", finishSuffix, "TOPLEFT", 0, 0)
    finishPrefix:SetPoint("TOPRIGHT", finishLink, "TOPLEFT", 0, 0)
    TaskTracker.SetTextColor(finishPrefix, "textAccent")
    TaskTracker.SetTextColor(finishLink, "textAccent")
    TaskTracker.SetTextColor(finishSuffix, "textAccent")
    local finishDots = {}
    local function paintFinishDots()
        local w = finishLink:GetStringWidth() or 0
        if w < 1 then w = (#(finishLink:GetText() or "") ) * 5 end
        local x = 0
        local i = 1
        while x + 2 <= w do
            local dot = finishDots[i]
            if not dot then
                dot = finishHit:CreateTexture(nil, "OVERLAY")
                dot:SetSize(2, 1)
                TaskTracker.SetColor(dot, "textAccent")
                finishDots[i] = dot
            end
            dot:ClearAllPoints()
            dot:SetPoint("TOPLEFT", finishLink, "BOTTOMLEFT", x, 0)
            dot:Show()
            x = x + 4
            i = i + 1
        end
        for j = i, #finishDots do
            finishDots[j]:Hide()
        end
    end
    local function updateFinishBtns()
        local link, suffix, title, body
        if goalMode == "any" then
            link, suffix = "any goal", " is met"
            title, body = "Any goal", "One goal is enough. Click to switch."
        else
            link, suffix = "all goals", " are met"
            title, body = "All goals", "Every goal has to be finished. Click to switch."
        end
        finishPrefix:SetText("Completes when ")
        finishLink:SetText(link)
        finishSuffix:SetText(suffix)
        local w = (finishPrefix:GetStringWidth() or 0) + (finishLink:GetStringWidth() or 0) + (finishSuffix:GetStringWidth() or 0)
        if w < 8 then w = 160 end
        finishHit:SetWidth(w)
        paintFinishDots()
        finishHit:SetScript("OnEnter", function()
            if TaskTracker.ShowTipBesideFrame then
                TaskTracker.ShowTipBesideFrame(dialog, title, body)
            end
        end)
        finishHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    finishHit:SetScript("OnClick", function()
        goalMode = (goalMode == "any") and "all" or "any"
        updateFinishBtns()
    end)
    updateFinishBtns()
    finishHit:Hide()
    local function syncFinishRow()
        if goals and #goals > 1 then
            updateFinishBtns()
            finishHit:Show()
        else
            finishHit:Hide()
        end
    end

    local countLabel = MakeLabel(leftChild, "How many to complete:", leftChild, "TOPLEFT", 0, 0)
    local countInput = MakeInput(leftChild, "TaskTrackerDialogCountInput", 80, countLabel)
    countInput:SetMaxLetters(10)
    countInput:SetText("1")

    local countMinus = TaskTracker.MakeIconButton(leftChild, 21, 16, TaskTracker.ChromeIconOpt())
    local countPlus  = TaskTracker.MakeIconButton(leftChild, 21, 16, TaskTracker.ChromeIconOpt())
    countMinus:SetChromeIcon("minus")
    countPlus:SetChromeIcon("plus")
    countInput:ClearAllPoints()
    countMinus:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", 0, -8)
    countInput:SetPoint("LEFT", countMinus, "RIGHT", 4, 0)
    countPlus:SetPoint("LEFT", countInput, "RIGHT", 4, 0)
    local function bumpBasicCount(delta)
        local n = tonumber(countInput:GetText()) or 1
        n = math.floor(n + delta)
        if n < 1 then n = 1 end
        if n > 99 then n = 99 end
        countInput:SetText(tostring(n))
    end
    countMinus:SetScript("OnClick", function() bumpBasicCount(-1) end)
    countPlus:SetScript("OnClick", function() bumpBasicCount(1) end)

    local selectedAdvType  = "gold"

    local advContainer = CreateFrame("Frame", nil, leftChild)
    advContainer:Hide()
    local subtextUi

    local function layoutAdvContainer()
    end

    local goldUi = CreateTaskDialogGoldUi(advContainer)
    local achUi = CreateTaskDialogAchievementUi(advContainer)
    local itemUi = CreateTaskDialogItemUi(advContainer)
    local questUi = CreateTaskDialogQuestUi(advContainer)
    local repUi = CreateTaskDialogReputationUi(advContainer)
    local mkUi = CreateTaskDialogMobKillUi(advContainer, {
        getTaskKind = function() return taskKind end,
        requestHeight = function()
            if setDialogHeight then setDialogHeight() end
        end,
    })
    local collUi = CreateTaskDialogCollectableUi(advContainer)
    subtextUi = CreateTaskDialogSubtextUi(content, {
        fieldWidth = FIELD_W,
        getTaskKind = function() return taskKind end,
        requestHeight = function()
            if setDialogHeight then setDialogHeight() end
        end,
        getMobIdText = function()
            if taskKind == "mob_kill" and mkUi.state.mobKillModeSel ~= "boss" then
                return mkUi.mobIdsInput:GetText() or ""
            end
            if taskKind == "collectable" and TaskTracker.GetCollectableEntry then
                local st = collUi.state
                local ent = TaskTracker.GetCollectableEntry(st.collectExpSel, st.collectCatSel, st.collEntrySelId)
                local ids = TaskTracker.CollectableEntryNpcIds and TaskTracker.CollectableEntryNpcIds(ent)
                if type(ids) == "table" and #ids > 0 then
                    local parts = {}
                    for _, id in ipairs(ids) do
                        parts[#parts + 1] = tostring(id)
                    end
                    return table.concat(parts, ", ")
                end
            end
            if commitOpenGoal then commitOpenGoal() end
            for gi = 1, #goals do
                local g = goals[gi]
                local ga = g and g.advanced
                if type(ga) == "table" and ga.type == "mob_kill" and (ga.mobKillMode or "world") ~= "boss" then
                    local ids = ga.mobIds
                    if type(ids) == "table" and #ids > 0 then
                        local parts = {}
                        for _, id in ipairs(ids) do
                            parts[#parts + 1] = tostring(id)
                        end
                        return table.concat(parts, ", ")
                    end
                end
                if type(ga) == "table" and ga.type == "collectable" and TaskTracker.GetCollectableEntry then
                    local ent = TaskTracker.GetCollectableEntry(ga.collectableExpansion, ga.collectableCategory, ga.collectableEntryId)
                    local ids = TaskTracker.CollectableEntryNpcIds and TaskTracker.CollectableEntryNpcIds(ent)
                    if type(ids) == "table" and #ids > 0 then
                        local parts = {}
                        for _, id in ipairs(ids) do
                            parts[#parts + 1] = tostring(id)
                        end
                        return table.concat(parts, ", ")
                    end
                end
            end
            return ""
        end,
        getCollectableItemId = function()
            if taskKind ~= "collectable" or not TaskTracker.GetCollectableEntry then return nil end
            local st = collUi.state
            local ent = TaskTracker.GetCollectableEntry(st.collectExpSel, st.collectCatSel, st.collEntrySelId)
            return ent and tonumber(ent.itemId) or nil
        end,
    })
    if subtextUi and subtextUi.removeBtn then
        tip(subtextUi.removeBtn, "Remove", "Remove the second line.")
        subtextUi.removeBtn:SetScript("OnClick", function()
            showSecondLine = false
            subtextUi.hideMenu()
            subtextUi.reset(true)
            if setDialogHeight then setDialogHeight() end
        end)
    end
    collUi.state.onEntryPicked = function()
        if subtextUi then subtextUi.refresh() end
    end

    local syncPanels
    syncPanels = function()
        goldUi.panel:Hide()
        achUi.optAch:Hide()
        itemUi.panel:Hide()
        questUi.panel:Hide()
        repUi.panel:Hide()
        mkUi.panel:Hide()
        collUi.panel:Hide()
        if selectedAdvType == "gold" then
            goldUi.panel:Show()
        elseif selectedAdvType == "achievement" then
            achUi.optAch:Show()
        elseif selectedAdvType == "item" then
            itemUi.panel:Show()
        elseif selectedAdvType == "quest" then
            questUi.panel:Show()
        elseif selectedAdvType == "reputation" then
            repUi.panel:Show()
        elseif selectedAdvType == "mob_kill" then
            mkUi.panel:Show()
        elseif selectedAdvType == "collectable" then
            collUi.panel:Show()
            collUi.onShow()
        end
    end

    local function applyCollectableDialogLayout()
        dialog:SetWidth(DIALOG_W)
        if collUi.syncLayout then collUi.syncLayout() end
    end

    typeLabel:SetParent(leftChild)
    typeLabel:Hide()
    typeDropBtn:SetParent(leftChild)
    typeDropBtn:ClearAllPoints()
    typeDropBtn:SetWidth(FIELD_W)
    if subtextUi and subtextUi.host then
        subtextUi.host:SetParent(leftChild)
    end
    if subtextUi and subtextUi.menu then
        subtextUi.menu:SetParent(dialog)
        if subtextUi.drop then
            subtextUi.menu:ClearAllPoints()
            subtextUi.menu:SetPoint("TOPLEFT", subtextUi.drop, "BOTTOMLEFT", 0, -2)
        end
        subtextUi.menu:SetFrameStrata("DIALOG")
        subtextUi.menu:SetFrameLevel((dialog:GetFrameLevel() or 0) + 80)
    end
    typeMenu:SetParent(dialog)
    typeMenu:ClearAllPoints()
    typeMenu:SetPoint("TOPLEFT", typeDropBtn, "BOTTOMLEFT", 0, -2)
    typeMenu:SetFrameStrata("DIALOG")
    typeMenu:SetFrameLevel((dialog:GetFrameLevel() or 0) + 80)

    local ADV_OPEN_H = {
        gold = 248, achievement = 280, item = 268, quest = 200,
        reputation = 280, mob_kill = 260, collectable = 360,
    }
    local function advOpenHeight()
        if taskKind == "basic" then return 0 end
        local h = ADV_OPEN_H[taskKind] or 260
        if taskKind == "mob_kill" and mkUi.state.mobKillModeSel == "boss" then
            h = h + 56
        end
        return h
    end

    local GOAL_LBL_W = 52
    local goalRows = {}
    for i = 1, MAX_GOALS do
        local row = CreateFrame("Frame", nil, leftChild)
        row:SetHeight(22)
        local lbl = MakeLabel(row, "Goal " .. i, row, "LEFT", 0, 0)
        lbl:SetWidth(GOAL_LBL_W)
        local btn = TaskTracker.MakeButton(row, "Basic Task x1", FIELD_W - GOAL_LBL_W - 4, 22)
        btn:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        local rm = TaskTracker.MakeButton(row, "x", 28, 22)
        rm:SetPoint("LEFT", btn, "RIGHT", 4, 0)
        tip(rm, "Remove", "Remove this goal.")
        row.lbl = lbl
        row.btn = btn
        row.rm = rm
        goalRows[i] = row
    end
    local addGoalBtn = TaskTracker.MakeButton(leftChild, "Add Additional Goal", FIELD_W, 22)
    tip(addGoalBtn, "Add Additional Goal", "Adds another goal on this task. Up to four.")
    local secondLineBtn = TaskTracker.MakeButton(leftChild, "Add Secondary Data", FIELD_W, 22)
    tip(secondLineBtn, "Add Secondary Data", "Adds a second line under the task name.")

    local ADV_KEEP = {
        goldAutoCopper = true, itemAutoCount = true, weekStartAchTotal = true,
        weekStartRepValue = true, questWeekStartComplete = true, questPeriodCredited = true,
        questPeriodOrphanCredits = true, questPeriodBaseline = true, questPeriodTurnIns = true,
        questPeriodRepeatCounts = true, questPeriodBaselineFrozen = true,
        mobAutoCount = true, collectableInit = true,
        collectableAutoCount = true, collectableFishAttempts = true, collectableCredited = true,
    }

    local function blankGoal()
        return { kind = "basic", taskMax = 1, taskCount = 0, done = false }
    end

    local function goalSummary(g, live)
        local kind = (live and taskKind) or (g and g.kind) or "basic"
        local label = TASK_KIND_LABELS[kind] or "Goal"
        local n = g and g.taskMax or 1
        if live and kind == "basic" then
            n = tonumber(countInput:GetText()) or n
        end
        n = tostring(n)
        if kind == "gold" then n = n .. "g" end
        return label .. " x" .. n
    end
    countInput:SetScript("OnTextChanged", function()
        local row = goalRows[openGoal]
        local g = goals[openGoal]
        if row and g and taskKind == "basic" then
            row.btn:SetLabel(goalSummary(g, true))
        end
    end)

    local loadGoal
    local layoutLeft

    commitOpenGoal = function()
        local g = goals[openGoal]
        if not g then return end
        local adv, tm = collectAdvancedAndMax()
        g.kind = taskKind
        g.taskMax = tm
        if taskKind == "basic" then
            g.advanced = nil
        else
            if type(g.advanced) == "table" and adv and g.advanced.type == adv.type then
                for k in pairs(ADV_KEEP) do
                    if g.advanced[k] ~= nil and adv[k] == nil then
                        adv[k] = g.advanced[k]
                    end
                end
                -- A new reputation form does not carry the classic/friendship flag.
                -- Keep it when the faction did not change, so a higher weekly goal
                -- still reads the same bar.
                if g.advanced.repClassic == true
                    and (tonumber(adv.repFactionId) or 0) > 0
                    and (tonumber(adv.repFactionId) or 0) == (tonumber(g.advanced.repFactionId) or 0) then
                    adv.repClassic = true
                end
            end
            g.advanced = adv
        end
    end

    local function removeGoal(index)
        if #goals <= 1 then return end
        commitOpenGoal()
        table.remove(goals, index)
        if openGoal > index then
            openGoal = openGoal - 1
        elseif openGoal == index and openGoal > #goals then
            openGoal = #goals
        end
        if openGoal < 1 then openGoal = 1 end
        loadGoal(openGoal, true)
    end

    for i = 1, MAX_GOALS do
        local cap = i
        goalRows[i].btn:SetScript("OnClick", function()
            if cap == openGoal then return end
            commitOpenGoal()
            loadGoal(cap, true)
        end)
        goalRows[i].rm:SetScript("OnClick", function()
            removeGoal(cap)
        end)
    end

    addGoalBtn:SetScript("OnClick", function()
        if #goals >= MAX_GOALS or dialog._mplusHintReadonly then return end
        commitOpenGoal()
        goals[#goals + 1] = blankGoal()
        loadGoal(#goals, true)
    end)
    secondLineBtn:SetScript("OnClick", function()
        if dialog._mplusHintReadonly or (subtextUi and subtextUi.isLocked()) then return end
        showSecondLine = true
        if setDialogHeight then setDialogHeight() end
    end)

    local function layoutRightActions()
        -- Label rows plus the buttons under them. Used so the window clears the footer.
        local labelH = 14
        local h = labelH + 6 + 22 + 4 + 22
        h = h + 10 + labelH + 6 + 22
        if not taskScopeAccount then
            h = h + 10 + labelH + 6 + 22
        end
        h = h + 10 + (labelH * 2) + 6 + 22
        h = h + 10 + (labelH * 2) + 6 + 22
        -- Notes and Popout sit on the bottom of this column.
        return h + 16 + 48
    end

    layoutLeft = function()
        local y = 0
        local placedEditor = false
        syncFinishRow()
        if finishHit:IsShown() then
            finishHit:ClearAllPoints()
            finishHit:SetPoint("TOPRIGHT", leftChild, "TOPRIGHT", 0, 0)
            y = 22
        end
        for i = 1, MAX_GOALS do
            local row = goalRows[i]
            if i <= #goals then
                row.lbl:SetText("Goal " .. i)
                row.btn:SetLabel(goalSummary(goals[i], false))
                TaskTracker.SetButtonActive(row.btn, false)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", leftChild, "TOPLEFT", 0, -y)
                row:SetWidth(FIELD_W)
                row:SetHeight(22)
                local xPad = (#goals > 1) and 32 or 0
                local slotW = FIELD_W - GOAL_LBL_W - 4 - xPad
                if #goals > 1 then
                    row.rm:Show()
                else
                    row.rm:Hide()
                end
                row:Show()
                y = y + 22
                if i == openGoal then
                    y = y + 14
                    placedEditor = true
                    row.btn:Hide()
                    typeLabel:Hide()
                    typeDropBtn:SetParent(row)
                    typeDropBtn:ClearAllPoints()
                    typeDropBtn:SetPoint("LEFT", row.lbl, "RIGHT", 4, 0)
                    typeDropBtn:SetSize(slotW, 22)
                    typeDropBtn:Show()
                    if #goals > 1 then
                        row.rm:ClearAllPoints()
                        row.rm:SetPoint("LEFT", typeDropBtn, "RIGHT", 4, 0)
                    end
                    if taskKind == "basic" then
                        countLabel:ClearAllPoints()
                        countLabel:SetPoint("TOPLEFT", leftChild, "TOPLEFT", 0, -y)
                        countLabel:Show()
                        countInput:Show()
                        countMinus:Show()
                        countPlus:Show()
                        advContainer:Hide()
                        y = y + 56
                    else
                        countLabel:Hide()
                        countInput:Hide()
                        countMinus:Hide()
                        countPlus:Hide()
                        advContainer:Show()
                        advContainer:ClearAllPoints()
                        advContainer:SetPoint("TOPLEFT", leftChild, "TOPLEFT", 0, -y)
                        advContainer:SetWidth(FIELD_W)
                        advContainer:SetHeight(advOpenHeight())
                        y = y + advOpenHeight() + 4
                    end
                else
                    y = y + 4
                    row.btn:Show()
                    row.btn:ClearAllPoints()
                    row.btn:SetPoint("LEFT", row.lbl, "RIGHT", 4, 0)
                    row.btn:SetSize(slotW, 22)
                    if #goals > 1 then
                        row.rm:ClearAllPoints()
                        row.rm:SetPoint("LEFT", row.btn, "RIGHT", 4, 0)
                    end
                end
            else
                row:Hide()
            end
        end
        if not placedEditor then
            typeLabel:Hide()
            typeDropBtn:Hide()
            countLabel:Hide()
            countInput:Hide()
            countMinus:Hide()
            countPlus:Hide()
            advContainer:Hide()
        end
        local rightH = layoutRightActions()
        local showAdd = (not dialog._mplusHintReadonly) and #goals < MAX_GOALS
        if showAdd then
            y = y + 8
            addGoalBtn:ClearAllPoints()
            addGoalBtn:SetPoint("TOPLEFT", leftChild, "TOPLEFT", 0, -y)
            addGoalBtn:SetWidth(FIELD_W)
            addGoalBtn:SetHeight(22)
            addGoalBtn:Show()
            y = y + 22
        else
            addGoalBtn:Hide()
        end
        local subH = 0
        if showSecondLine and subtextUi and not subtextUi.isLocked() then
            subH = subtextUi.blockHeight()
        end
        if subtextUi and subtextUi.host then
            if subH > 0 then
                subtextUi.host:Show()
                subtextUi.host:ClearAllPoints()
                subtextUi.host:SetPoint("TOPLEFT", leftChild, "TOPLEFT", 0, -(y + 8))
                subtextUi.host:SetWidth(FIELD_W)
                subtextUi.host:SetHeight(subH)
                y = y + subH + 16
            else
                subtextUi.host:Hide()
            end
        end
        local showSecond = (not showSecondLine) and not dialog._mplusHintReadonly and not (subtextUi and subtextUi.isLocked())
        if showSecond then
            y = y + 8
            secondLineBtn:ClearAllPoints()
            secondLineBtn:SetPoint("TOPLEFT", leftChild, "TOPLEFT", 0, -y)
            secondLineBtn:SetWidth(FIELD_W)
            secondLineBtn:SetHeight(22)
            secondLineBtn:Show()
            y = y + 22
        else
            secondLineBtn:Hide()
        end
        leftChild:SetHeight(math.max(40, y))
        return y, rightH
    end

    setDialogHeight = function()
        dialog:SetWidth(DIALOG_W)
        local leftH, rightH = layoutLeft()
        local screen = (GetScreenHeight and GetScreenHeight()) or 900
        local maxH = screen - 80
        local h = 160 + math.max(leftH, rightH or 0)
        if h < 380 then h = 380 end
        if h > maxH then h = maxH end
        dialog:SetHeight(h)
        local view = leftScroll:GetHeight() or 0
        if view > 1 and leftH <= view + 1 then
            leftScroll:SetVerticalScroll(0)
        end
    end

    local function syncTaskKindUi()
        typeDropBtn:SetLabel(TASK_KIND_LABELS[taskKind] or TASK_KIND_LABELS.basic)
        TaskTracker.SetButtonActive(typeDropBtn, taskKind ~= "basic")
        applyCollectableDialogLayout()
        if taskKind == "basic" then
            countLabel:Show()
            countInput:Show()
            countMinus:Show()
            countPlus:Show()
            advContainer:Hide()
        else
            countLabel:Hide()
            countInput:Hide()
            countMinus:Hide()
            countPlus:Hide()
            selectedAdvType = taskKind
            advContainer:Show()
            syncPanels()
        end
        if subtextUi then subtextUi.refresh() end
        setDialogHeight()
    end

    local function setDefaultLinkTargetForTaskKind(kind)
        if not TaskTracker.SetDefaultLinkInsertEditBox then return end
        if kind == "achievement" then
            TaskTracker.SetDefaultLinkInsertEditBox(achUi.achIdInput)
        elseif kind == "item" then
            TaskTracker.SetDefaultLinkInsertEditBox(itemUi.itemsInput)
        elseif kind == "quest" then
            TaskTracker.SetDefaultLinkInsertEditBox(questUi.questsInput)
        elseif kind == "reputation" then
            TaskTracker.SetDefaultLinkInsertEditBox(repUi.factionInput)
        elseif kind == "mob_kill" then
            TaskTracker.SetDefaultLinkInsertEditBox(mkUi.mobIdsInput)
        end
    end

    applyTaskKind = function(kind, keepScope)
        taskKind = kind
        typeMenu:Hide()
        if kind ~= "basic" then
            selectedAdvType = kind
        end
        syncTaskKindUi()
        if kind ~= "basic" then
            setDefaultLinkTargetForTaskKind(kind)
        end
        refreshTypeMenuRowStyles()
        if dialog._taskDialogIsAdd and not keepScope then
            if kind ~= "basic" then
                dialog.SetReset("weekly")
                taskScopeAccount = true
                syncCharScopeUi()
            else
                dialog.SetReset("none")
                taskScopeAccount = false
                taskShowOnOtherChars = false
                syncCharScopeUi()
            end
        end
    end

    loadGoal = function(index, keepScope)
        local g = goals[index]
        if not g then return end
        openGoal = index
        applyTaskKind(g.kind or "basic", keepScope)
        if not g.advanced or g.kind == "basic" then
            countInput:SetText(tostring(g.taskMax or 1))
        else
            local fake = { taskMax = g.taskMax or 1, taskCount = g.taskCount or 0, advanced = g.advanced }
            local a = g.advanced
            if a.type == "gold" then
                goldUi.loadFromNode(fake, a)
            elseif a.type == "achievement" then
                achUi.loadFromNode(fake, a)
            elseif a.type == "item" then
                itemUi.loadFromNode(fake, a)
            elseif a.type == "quest" then
                questUi.loadFromNode(fake, a)
            elseif a.type == "reputation" then
                repUi.loadFromNode(fake, a)
            elseif a.type == "mob_kill" then
                mkUi.loadFromNode(fake, a)
            elseif a.type == "collectable" then
                collUi.loadFromNode(fake, a)
            end
            if goldUi.refresh then goldUi.refresh() end
            if itemUi.refresh then itemUi.refresh() end
            if repUi.refresh then repUi.refresh() end
            syncPanels()
        end
        updateFinishBtns()
        if setDialogHeight then setDialogHeight() end
    end

    for i, kind in ipairs(TASK_KIND_ORDER) do
        local row = TaskTracker.MakeButton(typeMenu, TASK_KIND_LABELS[kind], FIELD_W - 8, 22)
        row:SetPoint("TOPLEFT", typeMenu, "TOPLEFT", 4, -4 - (i - 1) * 24)
        local cap = kind
        row:SetScript("OnClick", function()
            applyTaskKind(cap)
        end)
        row:SetScript("OnEnter", function()
            TaskTracker.SetColor(row.bg, "accentBg")
            TaskTracker.SetTextColor(row.label, "textAccent")
        end)
        row:SetScript("OnLeave", function()
            refreshTypeMenuRowStyles()
        end)
        typeMenuRows[kind] = row
    end
    refreshTypeMenuRowStyles()

    typeDropBtn:SetScript("OnClick", function()
        if typeMenu:IsShown() then
            typeMenu:Hide()
        else
            typeMenu:Show()
            typeMenu:Raise()
        end
    end)

    local function resetAdvancedFormFields()
        selectedAdvType = "gold"
        goldUi.resetForm()
        achUi.resetForm()
        itemUi.resetForm()
        questUi.resetForm()
        repUi.resetForm()
        mkUi.resetForm()
        collUi.resetForm()
        if subtextUi then subtextUi.reset() end
        excludeFromRollupGoals = false
        taskScopeAccount = false
        taskShowOnOtherChars = false
        if dialog._setKeepShown then dialog._setKeepShown(false) end
        syncCharScopeUi()
        updateRollupGoalBtns()
        syncPanels()
    end

    local cancelBtn = TaskTracker.MakeButton(footer, "Cancel", 80, 22)
    cancelBtn:SetPoint("LEFT", footer, "LEFT", 10, 0)
    cancelBtn:SetScript("OnEnter", nil)
    cancelBtn:SetScript("OnLeave", nil)
    cancelBtn:SetScript("OnClick", function() dialog:Hide() end)

    local deleteBtn = TaskTracker.MakeButton(footer, "Delete", 80, 22)
    deleteBtn:SetPoint("CENTER", footer, "CENTER", 0, 0)
    TaskTracker.SetColor(deleteBtn.bg, "danger")
    TaskTracker.SetTextColor(deleteBtn.label, "textPrimary")
    deleteBtn:SetScript("OnEnter", nil)
    deleteBtn:SetScript("OnLeave", nil)
    deleteBtn:Hide()

    local confirmBtn = TaskTracker.MakeButton(footer, "Add Task", 80, 22)
    confirmBtn:SetPoint("RIGHT", footer, "RIGHT", -10, 0)
    TaskTracker.SetColor(confirmBtn.bg, "accentBg")
    TaskTracker.SetTextColor(confirmBtn.label, "textAccent")
    confirmBtn:SetScript("OnEnter", nil)
    confirmBtn:SetScript("OnLeave", nil)

    dialog.nameInput   = nameInput
    dialog.countInput  = countInput
    dialog.confirmBtn  = confirmBtn
    dialog.deleteBtn   = deleteBtn
    dialog.GetReset   = function() return selectedReset end
    dialog.SetReset   = function(val)
        selectedReset = (RESET_VALID[val] and val) or "none"
        UpdateResetButtons()
    end

    collectAdvancedAndMax = function()
        if taskKind == "basic" then
            local tm = tonumber(countInput:GetText()) or 1
            if tm < 1 then tm = 1 end
            if tm > 99 then tm = 99 end
            return nil, tm
        end
        local tm = 1
        local adv = { type = selectedAdvType }
        if selectedAdvType == "gold" then
            tm = goldUi.collect(adv)
        elseif selectedAdvType == "achievement" then
            tm = achUi.collect(adv)
        elseif selectedAdvType == "item" then
            tm = itemUi.collect(adv)
        elseif selectedAdvType == "quest" then
            tm = questUi.collect(adv)
        elseif selectedAdvType == "reputation" then
            tm = repUi.collect(adv)
        elseif selectedAdvType == "mob_kill" then
            tm = mkUi.collect(adv)
        elseif selectedAdvType == "collectable" then
            tm = collUi.collect(adv)
        end
        return adv, tm
    end

    local function copyAdv(a)
        if type(a) ~= "table" then return nil end
        local o = {}
        for k, v in pairs(a) do
            if type(v) == "table" then
                local inner = {}
                for k2, v2 in pairs(v) do
                    inner[k2] = v2
                end
                o[k] = inner
            else
                o[k] = v
            end
        end
        return o
    end

    local function goalFromNodeFields(kind, taskMax, taskCount, taskUserValue, done, doneOverride, advanced)
        return {
            kind = kind or "basic",
            taskMax = tonumber(taskMax) or 1,
            taskCount = tonumber(taskCount) or 0,
            taskUserValue = taskUserValue,
            done = done and true or false,
            doneOverride = doneOverride,
            advanced = copyAdv(advanced),
        }
    end

    local function goalIsInvalid(g)
        local adv = g and g.advanced
        if type(adv) ~= "table" then return false end
        if adv.type == "quest" then
            local nId = #(adv.questIds or {})
            local nNm = adv.questNames and #adv.questNames or 0
            return nId == 0 and nNm == 0
        elseif adv.type == "mob_kill" then
            local mode = adv.mobKillMode or "world"
            if mode == "boss" then
                local bn = adv.bossNames
                if type(bn) == "string" then
                    bn = TaskTracker.ParseBossNameListFromText(bn)
                end
                return not bn or #bn == 0
            end
            return #(adv.mobIds or {}) == 0
        elseif adv.type == "collectable" then
            if not adv.collectableEntryId or adv.collectableEntryId == "" then return true end
            if TaskTracker.CollectableAdvHasProgressSource and not TaskTracker.CollectableAdvHasProgressSource(adv) then
                return true
            end
        end
        return false
    end

    local function writeExtraGoals(node)
        if not node then return end
        if #goals <= 1 then
            node.extraGoals = nil
            node.goalMode = nil
            return
        end
        local extras = {}
        for i = 2, #goals do
            local g = goals[i]
            extras[#extras + 1] = {
                taskMax = g.taskMax or 1,
                taskCount = g.taskCount or 0,
                taskUserValue = g.taskUserValue,
                done = g.done and true or false,
                doneOverride = g.doneOverride,
                advanced = g.advanced,
            }
        end
        node.extraGoals = extras
        node.goalMode = goalMode == "any" and "any" or "all"
    end

    dialog.OpenAdd = function(parentGroupID)
        local parent = TaskTracker.FindNode and TaskTracker.FindNode(parentGroupID)
        if parent and TaskTracker.ModuleSectionBlocksNewTask and TaskTracker.ModuleSectionBlocksNewTask(parent) then
            return
        end
        dialog._taskDialogIsAdd = true
        dialog._editNodeId = nil
        dialog._mplusHintReadonly = nil
        dialog._shareExportNode = nil
        dialog._shareImportCtx = { mode = "add", parentGroupId = parentGroupID }
        typeMenu:Hide()
        if subtextUi then subtextUi.hideMenu() end
        dialog.TitleText:SetText("Add Task")
        nameInput:SetText("")
        countInput:SetText("1")
        countInput:SetMaxLetters(10)
        dialog.SetReset("none")
        goals = { blankGoal() }
        openGoal = 1
        goalMode = "all"
        dialog._noteDraft = {
            type = "task",
            id = "__tt_task_dialog_draft",
            _ttNoteDraft = true,
            note = "",
            commandButtons = {},
        }
        showSecondLine = false
        updateFinishBtns()
        resetAdvancedFormFields()
        applyTaskKind("basic")
        nameInput:SetFocus()
        deleteBtn:Hide()
        confirmBtn:SetLabel("Add Task")
        confirmBtn:SetScript("OnClick", function()
            local name = nameInput:GetText()
            if not name or name == "" then return end
            commitOpenGoal()
            for gi = 1, #goals do
                if goalIsInvalid(goals[gi]) then return end
            end
            local primary = goals[1]
            local adv = primary.advanced
            local tm = primary.taskMax or 1
            if adv and adv.type == "quest" then
                local nId = #(adv.questIds or {})
                local nNm = adv.questNames and #adv.questNames or 0
                if nId == 0 and nNm == 0 then return end
            end
            if adv and adv.type == "mob_kill" then
                local mode = adv.mobKillMode or "world"
                if mode == "boss" then
                    local bn = adv.bossNames
                    if type(bn) == "string" then
                        bn = TaskTracker.ParseBossNameListFromText(bn)
                    end
                    if not bn or #bn == 0 then return end
                else
                    if #(adv.mobIds or {}) == 0 then return end
                end
            end
            if adv and adv.type == "collectable" then
                if not adv.collectableEntryId or adv.collectableEntryId == "" then return end
                if not TaskTracker.CollectableAdvHasProgressSource or not TaskTracker.CollectableAdvHasProgressSource(adv) then return end
            end
            if primary.kind == "basic" then
                countInput:SetText(tostring(tm))
            end
            local newNode = TaskTracker.AddTaskToGroup(parentGroupID, name, selectedReset, tm, adv, excludeFromRollupGoals, taskScopeAccount, taskShowOnOtherChars)
            if newNode then
                if dialog._keepShown then newNode.alwaysShow = true end
                if primary.taskCount then newNode.taskCount = primary.taskCount end
                writeExtraGoals(newNode)
            end
            if newNode and subtextUi then
                newNode.subtext = subtextUi.collect(nil)
                newNode.subtextBuiltinStamp = "user"
            end
            if TaskTracker.InvalidateAdvancedTaskIndex then
                TaskTracker.InvalidateAdvancedTaskIndex()
            end
            if not taskScopeAccount and TaskTracker.PersistActiveCharTaskProgress then
                TaskTracker.PersistActiveCharTaskProgress()
            end
            if newNode and dialog._noteDraft then
                local w = TaskTracker.noteWindow
                if w and w.boundNode == dialog._noteDraft and w.FlushNoteToNode then
                    w:FlushNoteToNode()
                end
                local draft = dialog._noteDraft
                local wrote = false
                if type(draft.note) == "string" and draft.note ~= "" then
                    newNode.note = draft.note
                    wrote = true
                end
                if type(draft.commandButtons) == "table" and #draft.commandButtons > 0 then
                    if type(newNode.commandButtons) ~= "table" then
                        newNode.commandButtons = {}
                    end
                    for ci = 1, #draft.commandButtons do
                        newNode.commandButtons[#newNode.commandButtons + 1] = draft.commandButtons[ci]
                    end
                    wrote = true
                end
                if wrote then
                    if TaskTracker.MarkListPaintDirty then TaskTracker.MarkListPaintDirty() end
                    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
                end
            end
            dialog:Hide()
        end)
        dialog:Show()
    end

    dialog.OpenEdit = function(node)
        if node and node.liveShareRole == "receiver" and TaskTracker.OpenReceivedTaskDialog then
            if dialog:IsShown() then dialog:Hide() end
            TaskTracker.OpenReceivedTaskDialog(node)
            return
        end
        dialog._taskDialogIsAdd = false
        dialog._noteDraft = nil
        dialog._editNodeId = node and node.id or nil
        dialog._shareExportNode = node
        dialog._shareImportCtx = { mode = "edit", refNodeId = node.id }
        typeMenu:Hide()
        if subtextUi then subtextUi.hideMenu() end
        dialog.TitleText:SetText("Edit Task")
        dialog._mplusHintReadonly = nil
        goals = {}
        local primaryKind = (node.advanced and node.advanced.type) or "basic"
        if primaryKind == "mplus_hint" then primaryKind = "basic" end
        goals[1] = goalFromNodeFields(primaryKind, node.taskMax, node.taskCount, node.taskUserValue, node.done, node.doneOverride, node.advanced)
        if type(node.extraGoals) == "table" then
            for i = 1, math.min(3, #node.extraGoals) do
                local g = node.extraGoals[i]
                local kind = (g.advanced and g.advanced.type) or "basic"
                goals[#goals + 1] = goalFromNodeFields(kind, g.taskMax, g.taskCount, g.taskUserValue, g.done, g.doneOverride, g.advanced)
            end
        end
        openGoal = 1
        goalMode = node.goalMode == "any" and "any" or "all"
        updateFinishBtns()
        nameInput:SetText(node.name)
        countInput:SetText(tostring(node.taskMax or 1))
        dialog.SetReset(node.reset or "none")
        resetAdvancedFormFields()
        if subtextUi then
            subtextUi.setLocked(node.advanced and node.advanced.type == "mplus_hint")
        end
        if node.advanced and node.advanced.type == "mplus_hint" then
            dialog._mplusHintReadonly = true
            applyTaskKind("basic")
        elseif node.advanced and node.advanced.type then
            applyTaskKind(node.advanced.type)
            local a = node.advanced
            if a.type == "gold" then
                goldUi.loadFromNode(node, a)
            elseif a.type == "achievement" then
                achUi.loadFromNode(node, a)
            elseif a.type == "item" then
                itemUi.loadFromNode(node, a)
            elseif a.type == "quest" then
                questUi.loadFromNode(node, a)
            elseif a.type == "reputation" then
                repUi.loadFromNode(node, a)
            elseif a.type == "mob_kill" then
                mkUi.loadFromNode(node, a)
            elseif a.type == "collectable" then
                collUi.loadFromNode(node, a)
            end
            if goldUi.refresh then goldUi.refresh() end
            if itemUi.refresh then itemUi.refresh() end
            if repUi.refresh then repUi.refresh() end
            syncPanels()
        else
            applyTaskKind("basic")
            countInput:SetText(tostring(node.taskMax or 1))
        end
        excludeFromRollupGoals = node.excludeFromRollup == true
        taskScopeAccount = node.accountWide == true
        taskShowOnOtherChars = node.showOnOtherCharacters == true
        if dialog._setKeepShown then dialog._setKeepShown(node.alwaysShow == true) end
        syncCharScopeUi()
        updateRollupGoalBtns()
        if subtextUi and not subtextUi.isLocked() then
            subtextUi.load(node)
            showSecondLine = subtextUi.isSet()
        else
            showSecondLine = false
        end
        if setDialogHeight then setDialogHeight() end
        nameInput:SetFocus()
        confirmBtn:SetLabel("Save")
        confirmBtn:SetScript("OnClick", function()
            local shareLocked = TaskTracker.TaskProgressIsLocked and TaskTracker.TaskProgressIsLocked(node)
            local shareSnap = (shareLocked and TaskTracker.SnapshotTaskProgress) and TaskTracker.SnapshotTaskProgress(node) or nil
            if dialog._mplusHintReadonly and node.advanced and node.advanced.type == "mplus_hint" then
                local name = nameInput:GetText()
                if name and name ~= "" then node.name = name end
                node.reset = selectedReset
                local wasAw = node.accountWide == true
                if TaskTracker.MigrateTaskScopeOnEdit then
                    TaskTracker.MigrateTaskScopeOnEdit(node, wasAw, taskScopeAccount)
                end
                if TaskTracker.ApplyTaskScopeFieldsToNode then
                    TaskTracker.ApplyTaskScopeFieldsToNode(node, taskScopeAccount, taskShowOnOtherChars)
                end
                if dialog._keepShown then
                    node.alwaysShow = true
                else
                    node.alwaysShow = nil
                end
                if not taskScopeAccount and TaskTracker.PersistActiveCharTaskProgress then
                    TaskTracker.PersistActiveCharTaskProgress()
                end
                if not shareLocked and node.liveShareRole == "owner" and TaskTracker.SendLiveShareTask then
                    local shareErr = TaskTracker.SendLiveShareTask(node)
                    if type(shareErr) == "string" and shareErr ~= "" then
                        print("|cff00ff00TaskTracker|r " .. shareErr)
                    end
                end
                dialog._mplusHintReadonly = nil
                dialog:Hide()
                if TaskTrackerDB and (TaskTrackerDB.hideCompleted or (TaskTracker.GetTaskLabelOverflowMode and TaskTracker.GetTaskLabelOverflowMode() == "grow")) then
                    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
                else
                    if TaskTracker.MarkListPaintDirty then TaskTracker.MarkListPaintDirty() end
                end
                if TaskTracker.RefreshList then TaskTracker.RefreshList() end
                return
            end
            local name = nameInput:GetText()
            if not name or name == "" then return end
            commitOpenGoal()
            for gi = 1, #goals do
                if goalIsInvalid(goals[gi]) then return end
            end
            local oldRollupExcluded = node.excludeFromRollup == true
            local wasAccountWide = node.accountWide == true
            local primary = goals[1]
            local adv = primary.advanced
            local tm = primary.taskMax or 1
            if adv and adv.type == "collectable" and node.advanced and node.advanced.type == "collectable" then
                local oa = node.advanced
                if (oa.collectableEntryId or "") == (adv.collectableEntryId or "")
                    and (oa.collectableExpansion or "") == (adv.collectableExpansion or "")
                    and (oa.collectableCategory or "") == (adv.collectableCategory or "") then
                    adv.collectableInit = oa.collectableInit
                    adv.collectableCredited = oa.collectableCredited
                    adv.collectableAutoCount = oa.collectableAutoCount
                    adv.collectableFishAttempts = oa.collectableFishAttempts
                end
            end
            if adv and adv.type == "quest" then
                local nId = #(adv.questIds or {})
                local nNm = adv.questNames and #adv.questNames or 0
                if nId == 0 and nNm == 0 then return end
            end
            if adv and adv.type == "mob_kill" then
                local mode = adv.mobKillMode or "world"
                if mode == "boss" then
                    local bn = adv.bossNames
                    if type(bn) == "string" then
                        bn = TaskTracker.ParseBossNameListFromText(bn)
                    end
                    if not bn or #bn == 0 then return end
                else
                    if #(adv.mobIds or {}) == 0 then return end
                end
            end
            if adv and adv.type == "collectable" then
                if not adv.collectableEntryId or adv.collectableEntryId == "" then return end
                if not TaskTracker.CollectableAdvHasProgressSource or not TaskTracker.CollectableAdvHasProgressSource(adv) then return end
            end
            local oldMax = node.taskMax or 1
            if not adv then
                node.advanced = nil
                node.taskUserValue = nil
            else
                node.advanced = adv
            end
            node.taskMax = tm
            node.doneOverride = nil
            -- Checking the box on a finished count stores that number. The list
            -- shows it instead of live progress. Raising the goal past it means
            -- the row should follow the game again. The weekly baseline stays.
            if adv and type(node.taskUserValue) == "number" and tm > oldMax and node.taskUserValue < tm then
                node.taskUserValue = nil
            end
            writeExtraGoals(node)
            if tm <= 1 then
                node.taskCount = node.done and 1 or 0
            else
                local c = node.taskCount or 0
                if c < 0 then c = 0 end
                node.taskCount = c
            end
            node.done = ((node.taskCount or 0) >= tm)
            node.name = name
            node.reset = selectedReset
            if excludeFromRollupGoals then
                node.excludeFromRollup = true
            else
                node.excludeFromRollup = nil
            end
            if dialog._keepShown then
                node.alwaysShow = true
            else
                node.alwaysShow = nil
            end
            if TaskTracker.MigrateTaskScopeOnEdit then
                TaskTracker.MigrateTaskScopeOnEdit(node, wasAccountWide, taskScopeAccount)
            end
            if TaskTracker.ApplyTaskScopeFieldsToNode then
                TaskTracker.ApplyTaskScopeFieldsToNode(node, taskScopeAccount, taskShowOnOtherChars)
            end
            if not shareLocked and node.advanced and node.advanced.type == "collectable" and TaskTracker.UpdateCollectableFromQuestFlags then
                TaskTracker.UpdateCollectableFromQuestFlags(node)
            end
            if not shareLocked and TaskTracker.SyncAdvancedTask then
                TaskTracker.SyncAdvancedTask(node)
                if TaskTracker.WithGoalSlot and type(node.extraGoals) == "table" then
                    for gi = 1, #node.extraGoals do
                        if node.extraGoals[gi] and node.extraGoals[gi].advanced then
                            TaskTracker.WithGoalSlot(node, gi, function()
                                TaskTracker.SyncAdvancedTask(node)
                            end)
                        end
                    end
                end
            end
            if subtextUi then
                node.subtext = subtextUi.collect(node.subtext)
                node.subtextBuiltinStamp = "user"
            end
            if TaskTracker.InvalidateAdvancedTaskIndex then
                TaskTracker.InvalidateAdvancedTaskIndex()
            end
            if not taskScopeAccount and TaskTracker.PersistActiveCharTaskProgress then
                TaskTracker.PersistActiveCharTaskProgress()
            end
            if shareLocked and shareSnap and TaskTracker.ApplyTaskProgressSnapshot then
                TaskTracker._ttLiveShareApplying = true
                TaskTracker.ApplyTaskProgressSnapshot(node, shareSnap)
                if not taskScopeAccount and TaskTracker.PersistOneCharTaskProgress then
                    TaskTracker.PersistOneCharTaskProgress(node)
                end
                TaskTracker._ttLiveShareApplying = nil
            elseif node.liveShareRole == "owner" and TaskTracker.SendLiveShareTask then
                local shareErr = TaskTracker.SendLiveShareTask(node)
                if type(shareErr) == "string" and shareErr ~= "" then
                    print("|cff00ff00TaskTracker|r " .. shareErr)
                end
            end
            dialog:Hide()
            local rollupChanged = oldRollupExcluded ~= (node.excludeFromRollup == true)
            if TaskTrackerDB and (TaskTrackerDB.hideCompleted or (TaskTracker.GetTaskLabelOverflowMode and TaskTracker.GetTaskLabelOverflowMode() == "grow") or rollupChanged) then
                if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
            else
                if TaskTracker.MarkListPaintDirty then TaskTracker.MarkListPaintDirty() end
            end
            if TaskTracker.RefreshList then TaskTracker.RefreshList() end
        end)
        deleteBtn:Show()
        deleteBtn:SetScript("OnClick", function()
            StaticPopupDialogs["TASKTRACKER_DEL_TASK"] = {
                text    = "Delete task '"..node.name.."'?",
                button1 = "Delete",
                button2 = "Cancel",
                OnAccept = function()
                    TaskTracker.RemoveNode(node.id)
                    dialog:Hide()
                end,
                timeout       = 0,
                whileDead     = true,
                hideOnEscape  = true,
            }
            StaticPopup_Show("TASKTRACKER_DEL_TASK")
        end)
        dialog:Show()
    end

    attachTaskDialogShareMailbox(dialog)

    local taskDialogEditBoxes = {
        nameInput, countInput,
        goldUi.goldGoalInput,
        achUi.achIdInput, achUi.achWeekInput,
        itemUi.itemsInput, itemUi.itemGoalInput,
        questUi.questsInput, questUi.questGoalInput,
        repUi.factionInput, repUi.repWeeklyInput, repUi.repValueInput, repUi.repRenownInput, repUi.repParagonCapInput,
        mkUi.mobIdsInput, mkUi.mobKillGoalInput, mkUi.bossInstInput, mkUi.bossNamesInput,
        collUi.collGoalInput,
    }

    local function isTaskDialogEditBox(f)
        if not f then return false end
        for _, eb in ipairs(taskDialogEditBoxes) do
            if eb == f then return true end
        end
        return false
    end

    local function clearTaskDialogEditFocusUnlessClickingField(_, button)
        -- Never interfere with right-click drag (mouselook) or other mouse buttons.
        if button and button ~= "LeftButton" then return end
        if not dialog:IsShown() then return end
        local f = _G.GetMouseFocus and _G.GetMouseFocus() or nil
        if isTaskDialogEditBox(f) then return end
        for _, eb in ipairs(taskDialogEditBoxes) do
            if eb and eb.ClearFocus then
                eb:ClearFocus()
            end
        end
    end

    dialog:HookScript("OnHide", function()
        GameTooltip:Hide()
        dialog._mplusHintReadonly = nil
        typeMenu:Hide()
        collUi.closeMenus()
        if collUi.entryMenu then collUi.entryMenu:Hide() end
        for _, eb in ipairs(taskDialogEditBoxes) do
            if eb and eb.HasFocus and eb:HasFocus() and eb.ClearFocus then
                eb:ClearFocus()
            end
        end
        local hp = TaskTracker.helpPopup
        if hp and hp:IsShown() and hp.currentKey == "newTask" then
            hp:Hide()
        end
    end)

    -- IMPORTANT: do not hook WorldFrame/UIParent mouse events.
    -- We only clear focus when clicking inside the dialog itself.
    dialog:HookScript("OnMouseDown", clearTaskDialogEditFocusUnlessClickingField)
    if dialog.Content then
        dialog.Content:HookScript("OnMouseDown", clearTaskDialogEditFocusUnlessClickingField)
    end
    dialog:HookScript("OnHide", function(self)
        self._editNodeId = nil
    end)

    setDialogHeight()

    dialogLabelColor = "textSecondary"
    return dialog
end

-- ─────────────────────────────────────
-- Group Dialog
-- ─────────────────────────────────────
function TaskTracker.CreateGroupDialog()
    local dialog, content, t = MakeDialog("TaskTrackerGroupDialog", 280, 176)

    local nameLabel = MakeLabel(content, "Group Name:", content, "TOPLEFT", 10, -10)
    local nameInput = MakeInput(content, "TaskTrackerGroupInput", 240, nameLabel)
    nameInput:SetAutoFocus(true)
    nameInput:SetMaxLetters(40)

    local errText = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontTiny or t.fontNormal or "GameFontNormalSmall")
    errText:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 10, 40)
    errText:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -10, 40)
    errText:SetHeight(32)
    errText:SetJustifyH("LEFT")
    errText:SetJustifyV("TOP")
    errText:SetWordWrap(true)
    TaskTracker.SetTextColor(errText, "danger")
    errText:SetText("")

    local function showNameError(text)
        errText:SetText(text or "")
    end

    local function parentForNewGroup(parentID, afterSiblingID)
        if afterSiblingID and TaskTracker.FindNode then
            local _, parent = TaskTracker.FindNode(afterSiblingID)
            if parent then return parent end
        end
        if parentID and TaskTracker.FindNode then
            return TaskTracker.FindNode(parentID)
        end
    end

    nameInput:HookScript("OnTextChanged", function(self, userInput)
        if userInput then showNameError("") end
    end)

    local cancelBtn = TaskTracker.MakeButton(content, "Cancel", 80, 22)
    cancelBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 10, 10)
    cancelBtn:SetScript("OnClick", function() dialog:Hide() end)

    local deleteBtn = TaskTracker.MakeButton(content, "Delete", 80, 22)
    deleteBtn:SetPoint("BOTTOM", content, "BOTTOM", 0, 10)
    TaskTracker.SetColor(deleteBtn.bg, "danger")
    TaskTracker.SetTextColor(deleteBtn.label, "textPrimary")
    deleteBtn:Hide()

    local confirmBtn = TaskTracker.MakeButton(content, "Create", 80, 22)
    confirmBtn:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -10, 10)
    TaskTracker.SetColor(confirmBtn.bg, "accentBg")
    TaskTracker.SetTextColor(confirmBtn.label, "textAccent")

    dialog.nameInput = nameInput

    -- Let keybinds work: clicking off the input clears focus.
    local function clearFocusIfBackgroundClick(_, button)
        if button and button ~= "LeftButton" then return end
        local f = _G.GetMouseFocus and _G.GetMouseFocus() or nil
        if f and f.GetObjectType and f:GetObjectType() == "EditBox" then
            return
        end
        if nameInput and nameInput.ClearFocus then
            nameInput:ClearFocus()
        end
    end
    dialog:HookScript("OnMouseDown", clearFocusIfBackgroundClick)
    if dialog.Content then
        dialog.Content:HookScript("OnMouseDown", clearFocusIfBackgroundClick)
    end

    dialog.OpenNew = function(parentID, afterSiblingID)
        dialog._shareExportNode = nil
        dialog._shareImportCtx = { mode = "new", parentId = parentID, afterSiblingId = afterSiblingID }
        dialog.TitleText:SetText("New Group")
        nameInput:SetText("")
        showNameError("")
        nameInput:SetFocus()
        deleteBtn:Hide()
        confirmBtn:SetLabel("Create")
        confirmBtn:SetScript("OnClick", function()
            local name = nameInput:GetText()
            if not name or name == "" then return end
            local parent = parentForNewGroup(parentID, afterSiblingID)
            local reserved = TaskTracker.GroupNameReservedReason and TaskTracker.GroupNameReservedReason(name, parent, nil)
            if reserved then
                showNameError(reserved)
                return
            end
            if afterSiblingID then
                TaskTracker.InsertGroupAfter(afterSiblingID, name)
            else
                TaskTracker.AddChild(parentID, TaskTracker.NewGroupNode(name))
            end
            dialog:Hide()
        end)
        dialog:Show()
    end

    dialog.OpenEdit = function(node)
        dialog._shareExportNode = node
        dialog._shareImportCtx = { mode = "edit", groupNodeId = node.id }
        dialog.TitleText:SetText("Edit Group")
        nameInput:SetText(node.name)
        showNameError("")
        nameInput:SetFocus()
        confirmBtn:SetLabel("Save")
        confirmBtn:SetScript("OnClick", function()
            local name = nameInput:GetText()
            if not name or name == "" then return end
            local _, parent = TaskTracker.FindNode(node.id)
            local reserved = TaskTracker.GroupNameReservedReason and TaskTracker.GroupNameReservedReason(name, parent, node)
            if reserved then
                showNameError(reserved)
                return
            end
            node.name = name
            dialog:Hide()
            if TaskTracker.MarkListPaintDirty then TaskTracker.MarkListPaintDirty() end
            if TaskTracker.RefreshList then TaskTracker.RefreshList() end
        end)
        if TaskTracker.IsProtectedModuleGroup(node) then
            deleteBtn:Hide()
        else
            deleteBtn:Show()
        end
        deleteBtn:SetScript("OnClick", function()
            StaticPopupDialogs["TASKTRACKER_DEL_GROUP"] = {
                text    = "Delete group '"..node.name.."' and all its contents?",
                button1 = "Delete",
                button2 = "Cancel",
                OnAccept = function()
                    TaskTracker.RemoveNode(node.id)
                    dialog:Hide()
                end,
                timeout       = 0,
                whileDead     = true,
                hideOnEscape  = true,
            }
            StaticPopup_Show("TASKTRACKER_DEL_GROUP")
        end)
        dialog:Show()
    end

    attachGroupDialogShareMailbox(dialog)
    dialog:HookScript("OnHide", function()
        local hp = TaskTracker.helpPopup
        if hp and hp:IsShown() and hp.currentKey == "newGroup" then
            hp:Hide()
        end
    end)

    return dialog
end

-- ─────────────────────────────────────
-- Notes + command buttons (task node)
-- ─────────────────────────────────────

local DEFAULT_ICON_FILE = 134400

local trim = TaskTracker.Trim
local NOTE_EMPTY_TEXT = "Write a note here."
local COMMAND_BLANK_LABEL = "Command"

local function noteTextForPeek(raw)
    local s = raw or ""
    if trim(s) == "" then return NOTE_EMPTY_TEXT end
    return s
end

local function peekTitleFor(node)
    local title = (TaskTracker.GetNodeLabel and node and TaskTracker.GetNodeLabel(node)) or (node and node.name) or ""
    if title == "" then title = "Note" end
    return title
end

local function eachNotePeek(fn)
    local list = TaskTracker.notePeekWindows
    if not list then return end
    for i = 1, #list do
        fn(list[i])
    end
end

function TaskTracker.SetNotePeekTitle(taskId, title)
    if not taskId then return end
    if not title or title == "" then title = "Note" end
    eachNotePeek(function(pk)
        if not pk:IsShown() or pk.boundTaskId ~= taskId then return end
        pk.peekTitle = title
        if pk.peekName then
            pk.peekName:SetText(title)
            TaskTracker.SetTextColor(pk.peekName, "textAccent")
        end
        if pk._requestPeekLayout then pk._requestPeekLayout() end
    end)
end

local function GetMacroIconFileIdList()
    if TaskTracker._macroIconFileIdList then
        return TaskTracker._macroIconFileIdList
    end
    local raw = {}
    pcall(function()
        if GetMacroIcons then GetMacroIcons(raw) end
        if GetLooseMacroIcons then GetLooseMacroIcons(raw) end
    end)
    local out = {}
    local seen = {}
    local function addId(id)
        id = tonumber(id)
        if not id or id <= 0 or seen[id] then return end
        seen[id] = true
        table.insert(out, id)
    end
    for _, v in ipairs(raw) do
        local id = tonumber(v)
        if id then
            addId(id)
        elseif type(v) == "string" and C_Texture and C_Texture.GetFileIDFromPath then
            local p = v
            if not string.find(v, "\\") then
                p = "INTERFACE\\ICONS\\" .. v
            end
            local fid = C_Texture.GetFileIDFromPath(p)
            if fid then addId(fid) end
        end
    end
    for _, fid in ipairs({
        134400, 136243, 136240, 136241, 136242, 237371, 132089, 135939,
        136172, 136076, 135805, 136223, 237587, 4648206,
    }) do
        addId(fid)
    end
    TaskTracker._macroIconFileIdList = out
    return out
end

--- Self-contained icon grid (Blizzard macro icon tables); no external addon.
function TaskTracker.OpenBuiltinIconPicker(_ownerFrame, currentFileId, onPick, commandText)
    if type(onPick) ~= "function" then return end
    local ids = GetMacroIconFileIdList()
    local maxIcons = math.max(1, math.min(#ids, 420))
    local picker = TaskTracker._ttBuiltinIconPicker
    if not picker then
        local PW, PH = 340, 360
        picker = TaskTracker.MakePanel("TaskTrackerBuiltinIconPicker", UIParent, PW, PH)
        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:SetFrameLevel(120)
        picker:Hide()
        picker:SetMovable(true)
        picker:RegisterForDrag()
        picker:SetScript("OnDragStart", nil)
        picker:SetScript("OnDragStop", nil)
        local tb = picker.titleBar
        tb:EnableMouse(true)
        tb:RegisterForDrag("LeftButton")
        tb:SetScript("OnDragStart", function() picker:StartMoving() end)
        tb:SetScript("OnDragStop", function() picker:StopMovingOrSizing() end)
        picker.TitleText:SetText("Choose icon")
        picker.CloseButton:SetScript("OnClick", function()
            picker._onPick = nil
            picker:Hide()
        end)

        local useBtn = CreateFrame("Button", nil, picker.Content)
        useBtn:SetHeight(28)
        useBtn:SetPoint("TOPLEFT", picker.Content, "TOPLEFT", 6, -4)
        useBtn:SetPoint("TOPRIGHT", picker.Content, "TOPRIGHT", -6, -4)
        TaskTracker.MakeBorder(useBtn, "border")
        local useBg = useBtn:CreateTexture(nil, "BACKGROUND")
        useBg:SetAllPoints()
        TaskTracker.SetColor(useBg, "headerBg")
        useBtn.bg = useBg
        local useIcon = useBtn:CreateTexture(nil, "ARTWORK")
        useIcon:SetSize(22, 22)
        useIcon:SetPoint("LEFT", useBtn, "LEFT", 4, 0)
        local useLabel = TaskTracker.CreateFontString(useBtn, nil, "OVERLAY", "GameFontNormalSmall")
        useLabel:SetPoint("LEFT", useIcon, "RIGHT", 6, 0)
        useLabel:SetPoint("RIGHT", useBtn, "RIGHT", -6, 0)
        useLabel:SetJustifyH("LEFT")
        useLabel:SetText("Use command")
        TaskTracker.SetTextColor(useLabel, "textPrimary")
        picker._useBtn = useBtn
        picker._useIcon = useIcon
        picker._useLabel = useLabel
        useBtn:EnableMouse(true)
        useBtn:SetFrameLevel((picker.Content:GetFrameLevel() or 0) + 20)
        useBtn:SetScript("OnClick", function()
            local file = picker._commandIcon
            if not file and picker._commandText then
                if TaskTracker.IconFileFromShowtooltip then
                    file = TaskTracker.IconFileFromShowtooltip(picker._commandText)
                end
                if not file and TaskTracker.IconFileFromSlashCommand then
                    file = TaskTracker.IconFileFromSlashCommand(picker._commandText)
                end
                picker._commandIcon = file
            end
            if not file or not picker._onPick then return end
            picker._onPick(file)
            picker._onPick = nil
            picker:Hide()
        end)
        useBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Use command", 1, 1, 1)
            local tip = picker._commandTip or "Takes the picture from a /use or /cast line."
            GameTooltip:AddLine(tip, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
            TaskTracker.SetColor(useBg, "rowHover")
        end)
        useBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
            TaskTracker.SetColor(useBg, "headerBg")
        end)

        local gridHost = CreateFrame("Frame", nil, picker.Content)
        gridHost:SetPoint("TOPLEFT", picker.Content, "TOPLEFT", 0, -36)
        gridHost:SetPoint("BOTTOMRIGHT", picker.Content, "BOTTOMRIGHT", 0, 0)
        local sc = CreateFrame("ScrollFrame", nil, gridHost)
        sc:SetPoint("TOPLEFT", gridHost, "TOPLEFT", 6, -2)
        sc:SetPoint("BOTTOMRIGHT", gridHost, "BOTTOMRIGHT", -10, 8)
        local child = CreateFrame("Frame", nil, sc)
        sc:SetScrollChild(child)
        TaskTracker.MakeScrollBar(sc, gridHost)

        local CELL, GAP, COLS = 30, 4, 8
        picker._iconScroll = sc
        picker._iconChild = child
        picker._iconCellSize = CELL
        picker._iconGap = GAP
        picker._iconCols = COLS

        picker._iconButtons = {}
        function picker:LayoutIconGrid(n)
            local CELL2, GAP2, COLS2 = self._iconCellSize, self._iconGap, self._iconCols
            local rows = math.max(1, math.ceil(n / COLS2))
            local w = COLS2 * (CELL2 + GAP2) + GAP2
            local h = rows * (CELL2 + GAP2) + GAP2
            self._iconChild:SetSize(math.max(40, w), math.max(40, h))
            for i = 1, n do
                local btn = self._iconButtons[i]
                if not btn then
                    btn = CreateFrame("Button", nil, self._iconChild)
                    btn:SetSize(CELL2, CELL2)
                    local tex = btn:CreateTexture(nil, "ARTWORK")
                    tex:SetAllPoints()
                    btn.iconTex = tex
                    TaskTracker.MakeBorder(btn, "border")
                    self._iconButtons[i] = btn
                end
                local col = (i - 1) % COLS2
                local row = math.floor((i - 1) / COLS2)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", self._iconChild, "TOPLEFT",
                    GAP2 + col * (CELL2 + GAP2), -GAP2 - row * (CELL2 + GAP2))
                btn:Show()
            end
            for j = n + 1, #self._iconButtons do
                self._iconButtons[j]:Hide()
            end
            local isc = self._iconScroll
            if isc and isc.UpdateScrollBar then
                isc:UpdateScrollBar()
            end
        end

        function picker:ApplyCommandOption(commandText, probeMacro)
            commandText = type(commandText) == "string" and commandText or ""
            self._commandText = commandText
            local file
            if probeMacro and TaskTracker.IconFileFromShowtooltip then
                file = TaskTracker.IconFileFromShowtooltip(commandText)
            end
            if not file and TaskTracker.IconFileFromSlashCommand then
                file = TaskTracker.IconFileFromSlashCommand(commandText)
            end
            self._commandIcon = file
            if file then
                self._useIcon:SetTexture(file)
                self._useIcon:SetVertexColor(1, 1, 1, 1)
                self._useLabel:SetAlpha(1)
                self._commandTip = "Uses #showtooltip, the same check as a macro."
            else
                self._useIcon:SetTexture(TaskTracker.DEFAULT_COMMAND_ICON or 134400)
                self._useIcon:SetVertexColor(1, 1, 1, 0.35)
                self._useLabel:SetAlpha(0.45)
                local trimmed = TaskTracker.Trim and TaskTracker.Trim(commandText) or commandText
                if trimmed == "" then
                    self._commandTip = "Type a /use or /cast line first."
                else
                    self._commandTip = "No item or spell icon in this command yet."
                end
            end
        end

        picker:SetScript("OnHide", function(self)
            self._onPick = nil
            if TaskTracker.RefreshOpenIconPickerCommand then
                TaskTracker.RefreshOpenIconPickerCommand = nil
            end
        end)

        TaskTracker._ttBuiltinIconPicker = picker
    end

    picker._onPick = onPick
    picker._commandIcon = nil
    if picker.ApplyCommandOption then
        picker:ApplyCommandOption(commandText, true)
    end
    TaskTracker.RefreshOpenIconPickerCommand = function()
        if not picker:IsShown() or picker._commandIcon or not picker.ApplyCommandOption then return end
        picker:ApplyCommandOption(picker._commandText, false)
    end
    picker:LayoutIconGrid(maxIcons)
    for i = 1, maxIcons do
        local fid = ids[i]
        local btn = picker._iconButtons[i]
        if not btn then break end
        btn.iconTex:SetTexture(fid)
        btn:SetScript("OnClick", function()
            if picker._onPick then
                picker._onPick(fid)
            end
            picker._onPick = nil
            picker:Hide()
        end)
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText(tostring(fid), 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if picker._iconScroll then
        picker._iconScroll:SetVerticalScroll(0)
    end
    picker:ClearAllPoints()
    if TaskTracker.AnchorFrameNearScreenTop then
        TaskTracker.AnchorFrameNearScreenTop(picker, 0, 0.12)
    else
        picker:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    picker:SetToplevel(true)
    picker:Show()
    picker:Raise()
end

local function SetFileIconTexture(tex, fileId, command)
    if TaskTracker.ApplyCommandIconToTexture then
        TaskTracker.ApplyCommandIconToTexture(tex, fileId, command)
        return
    end
    if not tex then return end
    local n = tonumber(fileId) or DEFAULT_ICON_FILE
    tex:SetTexture(n)
    tex:Show()
end

function TaskTracker.AttachTaskDialogSideIcons(dialog, rightCol, nameInput, t)
    if not dialog or not rightCol then return end
    local function currentNoteNode()
        if dialog._taskDialogIsAdd then
            if type(dialog._noteDraft) ~= "table" then
                dialog._noteDraft = {
                    type = "task",
                    id = "__tt_task_dialog_draft",
                    _ttNoteDraft = true,
                    note = "",
                    commandButtons = {},
                }
            end
            local name = nameInput and nameInput.GetText and nameInput:GetText()
            if not name or name == "" then name = "New task" end
            dialog._noteDraft.name = name
            return dialog._noteDraft
        end
        return dialog._editNodeId and TaskTracker.FindNode and TaskTracker.FindNode(dialog._editNodeId)
    end
    local function tip(btn, title, body)
        if not btn then return end
        btn:SetScript("OnEnter", function()
            if TaskTracker.ShowTipBesideFrame then
                TaskTracker.ShowTipBesideFrame(dialog, title, body)
            end
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    local function labeledSideIcon(parent, text)
        local host = CreateFrame("Frame", nil, parent)
        host:SetSize(64, 40)
        local lbl = TaskTracker.CreateFontString(host, nil, "OVERLAY", (t and t.fontNormal) or "GameFontNormalSmall")
        lbl:SetPoint("TOP", host, "TOP", 0, 0)
        lbl:SetJustifyH("CENTER")
        lbl:SetWordWrap(false)
        lbl:SetText(text)
        TaskTracker.SetTextColor(lbl, "textAccent")
        host.lbl = lbl
        local btn = TaskTracker.MakeIconButton(host, 22, 22, TaskTracker.ChromeIconOpt())
        btn:SetPoint("TOP", lbl, "BOTTOM", 0, -2)
        host.btn = btn
        return host
    end
    local sideIconBar = CreateFrame("Frame", nil, rightCol)
    sideIconBar:SetHeight(40)
    sideIconBar:SetPoint("BOTTOMLEFT", rightCol, "BOTTOMLEFT", 8, 8)
    sideIconBar:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", -8, 8)
    local notesHost = labeledSideIcon(sideIconBar, "Notes")
    local dataHost = labeledSideIcon(sideIconBar, "Edit data")
    local popHost = labeledSideIcon(sideIconBar, "Popout")
    local syncHost = labeledSideIcon(sideIconBar, "Sync")
    local function placeSideIcons()
        local editing = not dialog._taskDialogIsAdd and dialog._editNodeId
        local hosts
        local syncOn = editing and TaskTracker.IsLiveShareEnabled and TaskTracker.IsLiveShareEnabled()
        if editing and syncOn then
            dataHost:Show()
            syncHost:Show()
            hosts = { dataHost, notesHost, popHost, syncHost }
        elseif editing then
            dataHost:Show()
            syncHost:Hide()
            hosts = { dataHost, notesHost, popHost }
        else
            dataHost:Hide()
            syncHost:Hide()
            hosts = { notesHost, popHost }
        end
        local barW = sideIconBar:GetWidth()
        if not barW or barW < 40 then barW = 160 end
        local gap = 2
        local widths = {}
        local total = 0
        for i = 1, #hosts do
            local lbl = hosts[i].lbl
            local w = 0
            if lbl and lbl.GetStringWidth then
                w = math.ceil((lbl:GetStringWidth() or 0) + 4)
            end
            if w < 28 then
                local text = lbl and lbl.GetText and lbl:GetText() or ""
                if text == "Edit data" then w = 62
                elseif text == "Popout" then w = 44
                elseif text == "Notes" then w = 36
                else w = 32 end
            end
            widths[i] = w
            total = total + w
        end
        local gaps = gap * math.max(0, #hosts - 1)
        if total + gaps > barW and total > 0 then
            local scale = (barW - gaps) / total
            total = 0
            for i = 1, #widths do
                widths[i] = math.max(24, math.floor(widths[i] * scale))
                total = total + widths[i]
            end
        end
        local extra = barW - total - gaps
        if extra < 0 then extra = 0 end
        local x = math.floor(extra / 2)
        for i = 1, #hosts do
            hosts[i]:Show()
            hosts[i]:ClearAllPoints()
            hosts[i]:SetSize(widths[i], 40)
            if hosts[i].lbl then
                hosts[i].lbl:SetWidth(widths[i])
            end
            hosts[i]:SetPoint("LEFT", sideIconBar, "LEFT", x, 0)
            x = x + widths[i] + gap
        end
    end
    dialog._syncEditDataIcon = placeSideIcons
    dialog:HookScript("OnShow", placeSideIcons)
    placeSideIcons()
    dialog._noteBtn = notesHost.btn
    dialog._noteBtn:SetChromeIcon("note")
    tip(dialog._noteBtn, "Notes", "Opens notes to the right of this window.")
    dialog._noteBtn:SetScript("OnClick", function()
        local node = currentNoteNode()
        if not node or not TaskTracker.OpenNoteWindow then return end
        TaskTracker.OpenNoteWindow(node, dialog)
    end)
    dialog._popoutBtn = popHost.btn
    TaskTracker.ApplyNotePopoutIcon(dialog._popoutBtn)
    tip(dialog._popoutBtn, "Popout", "Opens a movable copy of this note over the game world.")
    dialog._popoutBtn:SetScript("OnClick", function()
        local node = currentNoteNode()
        local w = TaskTracker.noteWindow
        if not node or not w or not TaskTracker.OpenNotePeekWindow then return end
        if not (w:IsShown() and w.boundTaskId == node.id) then
            if w:IsShown() and w.boundTaskId and w.boundTaskId ~= node.id and w.FlushNoteToNode then
                w:FlushNoteToNode()
            end
            w.boundTaskId = node.id
            w.boundNode = node
            if w.PopulateFromNode then w:PopulateFromNode(node) end
        end
        TaskTracker.OpenNotePeekWindow()
    end)
    dialog._dataBtn = dataHost.btn
    dialog._dataBtn:SetChromeIcon("edit")
    tip(dialog._dataBtn, "Edit data", "Set progress.")
    dialog._dataBtn:SetScript("OnClick", function()
        if dialog._taskDialogIsAdd then return end
        local node = dialog._editNodeId and TaskTracker.FindNode and TaskTracker.FindNode(dialog._editNodeId)
        if node and TaskTracker.OpenProgressEditForNode then
            TaskTracker.OpenProgressEditForNode(node)
        end
    end)
    dialog._syncBtn = syncHost.btn
    if dialog._syncBtn.SetIconAtlas then
        pcall(dialog._syncBtn.SetIconAtlas, dialog._syncBtn, "UI-RefreshButton")
    end
    tip(dialog._syncBtn, "Sync", "Send this task to a character on another account. They can move it. The count follows yours.")
    dialog._syncBtn:SetScript("OnClick", function()
        if dialog._taskDialogIsAdd then return end
        local node = dialog._editNodeId and TaskTracker.FindNode and TaskTracker.FindNode(dialog._editNodeId)
        if node and TaskTracker.OpenLiveShareDialog then
            TaskTracker.OpenLiveShareDialog(node)
        end
    end)
end

function TaskTracker.ApplyNotePopoutIcon(btn)
    if not btn or not btn.SetIconAtlas then return end
    local atlas = "legionmission-EncounterAbilityBorder"
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        btn:SetIconAtlas(atlas, false)
    elseif btn.SetChromeIcon then
        btn:SetChromeIcon("search")
    end
end

function TaskTracker.UpdateNoteWindowAnchor()
    local w = TaskTracker.noteWindow
    if not w or not w:IsShown() then return end
    local host = w.anchorHost
    if host and host.IsShown and host:IsShown() then
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", host, "TOPRIGHT", 8, 0)
        return
    end
    w.anchorHost = nil
    local p = TaskTracker.panel
    if not p or not p:IsShown() then return end
    local side = (TaskTrackerDB and TaskTrackerDB.notePanelSide) or "right"
    w:ClearAllPoints()
    if side == "left" then
        w:SetPoint("TOPRIGHT", p, "TOPLEFT", -8, 0)
    else
        w:SetPoint("TOPLEFT", p, "TOPRIGHT", 8, 0)
    end
end

function TaskTracker.HideNoteWindow()
    local w = TaskTracker.noteWindow
    if not w or not w:IsShown() then return end
    if w._noteSaveDebounce then
        w._noteSaveDebounce:Cancel()
        w._noteSaveDebounce = nil
    end
    if w.FlushNoteToNode then w:FlushNoteToNode() end
    w:Hide()
    w.boundTaskId = nil
end

function TaskTracker.ValidateNoteWindow()
    local w = TaskTracker.noteWindow
    if not w or not w:IsShown() or not w.boundTaskId then return end
    if w.boundNode and w.boundNode._ttNoteDraft then
        if w.anchorHost and w.anchorHost.IsShown and w.anchorHost:IsShown() then
            TaskTracker.UpdateNoteWindowAnchor()
            return
        end
        TaskTracker.HideNoteWindow()
        return
    end
    local node = TaskTracker.FindNode and TaskTracker.FindNode(w.boundTaskId)
    if not node or (node.type ~= "task" and node.type ~= "registryEntry") then
        TaskTracker.HideNoteWindow()
    else
        w.boundNode = node
        TaskTracker.UpdateNoteWindowAnchor()
    end
end

function TaskTracker.OpenNoteWindow(node, anchorHost)
    if not node or (node.type ~= "task" and node.type ~= "registryEntry") then return end
    local w = TaskTracker.noteWindow
    if not w then return end
    if w:IsShown() and w.boundTaskId == node.id then
        if anchorHost and w.anchorHost ~= anchorHost then
            w.anchorHost = anchorHost
            TaskTracker.UpdateNoteWindowAnchor()
            w:SetToplevel(true)
            w:Raise()
            return
        end
        if not anchorHost and w.anchorHost then
            w.anchorHost = nil
            TaskTracker.UpdateNoteWindowAnchor()
            return
        end
        TaskTracker.HideNoteWindow()
        return
    end
    if w._noteSaveDebounce then
        w._noteSaveDebounce:Cancel()
        w._noteSaveDebounce = nil
    end
    if w.boundTaskId and w.boundTaskId ~= node.id and w.FlushNoteToNode then
        w:FlushNoteToNode()
    end
    w.boundTaskId = node.id
    w.boundNode = node
    w.anchorHost = anchorHost
    if w.PopulateFromNode then w:PopulateFromNode(node) end
    TaskTracker.HideQuickCommandsPanel()
    local title = (TaskTracker.GetNodeLabel and TaskTracker.GetNodeLabel(node)) or (node.name or "Row")
    w._peekTitle = title
    w.TitleText:SetText("Notes — " .. title)
    TaskTracker.UpdateNoteWindowAnchor()
    w:SetToplevel(true)
    w:Show()
    w:Raise()
    if w.noteEdit then
        C_Timer.After(0, function()
            if w:IsShown() and w.boundTaskId == node.id and w.noteEdit then
                w.noteEdit:SetFocus()
            end
        end)
    end
end

function TaskTracker.HideCommandEditor()
    local ed = TaskTracker._ttCommandEditor
    if ed and ed:IsShown() then ed:Hide() end
end

--- Movable multiline editor for one command button. Closing it saves.
function TaskTracker.OpenCommandEditor(text, onSave)
    if type(onSave) ~= "function" then return end
    local ed = TaskTracker._ttCommandEditor
    if not ed then
        local EW, EH = 420, 300
        ed = TaskTracker.MakePanel("TaskTrackerCommandEditor", UIParent, EW, EH)
        ed:SetFrameStrata("FULLSCREEN_DIALOG")
        ed:SetFrameLevel(130)
        ed:Hide()
        ed:SetMovable(true)
        ed:RegisterForDrag()
        ed:SetScript("OnDragStart", nil)
        ed:SetScript("OnDragStop", nil)
        local tb = ed.titleBar
        tb:EnableMouse(true)
        tb:RegisterForDrag("LeftButton")
        tb:SetScript("OnDragStart", function() ed:StartMoving() end)
        tb:SetScript("OnDragStop", function() ed:StopMovingOrSizing() end)
        ed.TitleText:SetText("Command")
        ed.CloseButton:SetScript("OnClick", function() ed:Hide() end)

        local hint = TaskTracker.CreateFontString(ed.Content, nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", ed.Content, "TOPLEFT", 10, -8)
        hint:SetPoint("TOPRIGHT", ed.Content, "TOPRIGHT", -10, -8)
        hint:SetHeight(32)
        hint:SetJustifyH("LEFT")
        hint:SetJustifyV("TOP")
        if hint.SetWordWrap then hint:SetWordWrap(true) end
        hint:SetText("One slash command per line. Lines runs each line on its own, so a waypoint list fits. Full runs the whole box as one macro.")
        TaskTracker.SetTextColor(hint, "textSecondary")

        local box = CreateFrame("EditBox", nil, ed.Content)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject("GameFontHighlightSmall")
        TaskTracker.ClearFontShadow(box)
        box:SetTextInsets(6, 6, 6, 6)
        box:SetMaxLetters(TaskTracker.COMMAND_TEXT_CAP or 4000)
        box:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
        box:SetPoint("BOTTOMRIGHT", ed.Content, "BOTTOMRIGHT", -10, 10)
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        TaskTracker.SetColor(bg, "inputBg")
        TaskTracker.MakeBorder(box, "border")
        ed._edit = box
        ed:SetScript("OnHide", function(self)
            local fn = self._onSave
            self._onSave = nil
            if not fn then return end
            local body = self._edit:GetText() or ""
            if TaskTracker.ClampCommandText then
                body = TaskTracker.ClampCommandText(body)
            end
            fn(body)
        end)
        TaskTracker._ttCommandEditor = ed
    end
    if ed:IsShown() then
        ed:Hide()
    end
    ed._onSave = onSave
    ed._edit:SetText(type(text) == "string" and text or "")
    ed:ClearAllPoints()
    ed:SetPoint("CENTER", UIParent, "CENTER", 40, 40)
    ed:SetToplevel(true)
    ed:Show()
    ed:Raise()
    ed._edit:SetFocus()
end

function TaskTracker.CreateNoteWindow()
    local NOTE_W, NOTE_H = 520, 400
    local pinCap = TaskTracker.MAX_PINNED_COMMANDS or 3
    local t = TaskTracker.GetTheme()
    local frame = TaskTracker.MakePanel("TaskTrackerNoteWindow", UIParent, NOTE_W, NOTE_H)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(80)
    frame:Hide()

    frame:SetMovable(true)
    frame:RegisterForDrag()
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)

    local titleBar = frame.titleBar
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        TaskTracker.UpdateNoteWindowAnchor()
    end)

    frame.CloseButton:SetScript("OnClick", function()
        TaskTracker.HideNoteWindow()
    end)

    local helpBtn = TaskTracker.AttachHelpButton(frame.titleBar, frame.CloseButton, "notes")

    local peekBtn = TaskTracker.MakeIconButton(frame.titleBar, 20, 20, TaskTracker.ChromeIconOpt())
    peekBtn:SetPoint("RIGHT", helpBtn, "LEFT", -3, 0)
    if TaskTracker.ApplyNotePopoutIcon then
        TaskTracker.ApplyNotePopoutIcon(peekBtn)
    else
        peekBtn:SetChromeIcon("search")
    end
    peekBtn:SetScript("OnClick", function()
        if TaskTracker.OpenNotePeekWindow then
            TaskTracker.OpenNotePeekWindow()
        end
    end)
    peekBtn:SetScript("OnEnter", function(self)
        TaskTracker.SetColor(self.bg, "accentBg")
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Popout", 1, 1, 1)
        local peekTip = "Open a movable copy of this note over the game world. It stays open if you close Notes or the tracker. Close it with x. Background and text opacity are in Options, then Style."
        if TaskTracker.WithPathArrows then peekTip = TaskTracker.WithPathArrows(peekTip, 12) end
        GameTooltip:AddLine(peekTip, 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    peekBtn:SetScript("OnLeave", function(self)
        TaskTracker.SetColor(self.bg, "headerBg")
        GameTooltip:Hide()
    end)

    local content = frame.Content
    local pad = 10
    local CMD_W = 176
    local CMD_PAD = 8
    local CMD_BTN_H = 22

    -- Commands sit on the left, same grey column as task settings.
    local cmdCol = CreateFrame("Frame", nil, frame)
    cmdCol:SetWidth(CMD_W)
    cmdCol:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    cmdCol:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    local cmdBg = cmdCol:CreateTexture(nil, "BACKGROUND")
    cmdBg:SetAllPoints()
    TaskTracker.SetColor(cmdBg, "headerBg2")
    local cmdSep = cmdCol:CreateTexture(nil, "ARTWORK")
    cmdSep:SetWidth(1)
    cmdSep:SetPoint("TOPRIGHT", cmdCol, "TOPRIGHT", 0, 0)
    cmdSep:SetPoint("BOTTOMRIGHT", cmdCol, "BOTTOMRIGHT", 0, 0)
    TaskTracker.SetColor(cmdSep, "border")

    local notesLbl = MakeLabel(content, "Notes", content, "TOPLEFT", CMD_W + pad, -10, "textAccent")

    -- Notes: plain multiline EditBox (no ScrollFrame — keeps caret, clicks, selection reliable). The
    -- holder and window height grow with the text instead of scrolling.
    local noteHolder = CreateFrame("Frame", "TaskTrackerNoteHolder", content)
    noteHolder:SetPoint("TOPLEFT", notesLbl, "BOTTOMLEFT", 0, -6)
    noteHolder:SetPoint("RIGHT", content, "RIGHT", -pad, 0)
    local initialNoteBodyH = NOTE_H - (t.titleHeight or 28) - 10 - 16 - 6 - 10
    noteHolder:SetHeight(math.max(100, initialNoteBodyH))
    -- Clip the note so the EditBox cannot paint or steal hits over the command column on the left.
    noteHolder:SetClipsChildren(true)
    noteHolder:EnableMouse(false)

    local noteEdit = CreateFrame("EditBox", "TaskTrackerNoteEdit", noteHolder)
    noteEdit:SetMultiLine(true)
    pcall(function()
        noteEdit:SetSplitFullWords(false)
    end)
    noteEdit:SetFontObject(t.fontNormal or "GameFontHighlightSmall")
    TaskTracker.ClearFontShadow(noteEdit)
    for _, region in ipairs({ noteEdit:GetRegions() }) do
        if region.GetWordWrap and region.SetWordWrap then
            region:SetWordWrap(true)
        end
    end
    local tc = t.textPrimary
    if tc then
        noteEdit:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
    else
        noteEdit:SetTextColor(0.92, 0.92, 0.96, 1)
    end
    if noteEdit.SetShadowOffset then
        noteEdit:SetShadowOffset(0, 0)
    end
    noteEdit:SetAutoFocus(false)
    noteEdit:SetMaxLetters(4000)
    noteEdit:SetTextInsets(6, 6, 6, 6)
    noteEdit:EnableMouse(true)
    noteEdit:EnableKeyboard(true)
    local noteBg = noteEdit:CreateTexture(nil, "BACKGROUND")
    noteBg:SetAllPoints()
    TaskTracker.SetColor(noteBg, "inputBg")
    TaskTracker.MakeBorder(noteEdit, "border")
    if noteEdit.SetBlinkSpeed then
        noteEdit:SetBlinkSpeed(0.12)
    end

    local function noteLineHeight()
        return (select(2, noteEdit:GetFont()) or 12) + 2
    end

    local function applyNoteGeometry()
        local ew = math.max(40, (noteHolder:GetWidth() or 0) - 4)
        noteEdit:ClearAllPoints()
        noteEdit:SetPoint("TOPLEFT", noteHolder, "TOPLEFT", 2, -2)
        noteEdit:SetWidth(ew)
    end

    local syncNoteWindowHeight

    noteHolder:SetScript("OnSizeChanged", function()
        applyNoteGeometry()
        if syncNoteWindowHeight then
            syncNoteWindowHeight()
        end
    end)
    applyNoteGeometry()

    local function scheduleSaveNote()
        if frame._noteSaveDebounce then
            frame._noteSaveDebounce:Cancel()
            frame._noteSaveDebounce = nil
        end
        frame._noteSaveDebounce = C_Timer.NewTimer(0.35, function()
            frame._noteSaveDebounce = nil
            frame:FlushNoteToNode()
        end)
    end

    local noteHint = noteEdit:CreateFontString(nil, "OVERLAY", t.fontNormal or "GameFontHighlightSmall")
    noteHint:SetPoint("TOPLEFT", noteEdit, "TOPLEFT", 6, -6)
    noteHint:SetPoint("RIGHT", noteEdit, "RIGHT", -6, 0)
    noteHint:SetJustifyH("LEFT")
    noteHint:SetJustifyV("TOP")
    noteHint:SetText(NOTE_EMPTY_TEXT)
    TaskTracker.SetTextColor(noteHint, "textSecondary")
    if noteHint.SetWordWrap then noteHint:SetWordWrap(true) end
    local function refreshNoteHint()
        local s = noteEdit:GetText() or ""
        if trim(s) == "" and not noteEdit:HasFocus() then
            noteHint:Show()
        else
            noteHint:Hide()
        end
    end
    noteEdit:SetScript("OnTextChanged", function(_, isUser)
        if isUser then
            scheduleSaveNote()
        end
        refreshNoteHint()
        if syncNoteWindowHeight then
            syncNoteWindowHeight()
        end
        if TaskTracker.SyncNotePeekFromMain then
            TaskTracker.SyncNotePeekFromMain()
        end
    end)
    noteEdit:SetScript("OnEditFocusGained", function()
        noteHint:Hide()
    end)
    noteEdit:SetScript("OnEditFocusLost", function()
        refreshNoteHint()
    end)
    frame._refreshNoteHint = refreshNoteHint

    if TaskTracker.RegisterLinkableEditBox then
        TaskTracker.RegisterLinkableEditBox(noteEdit)
    end

    function frame:FlushNoteToNode()
        local node = self.boundNode
        if not node or (node.type ~= "task" and node.type ~= "registryEntry") then return end
        node.note = noteEdit:GetText() or ""
    end

    -- Parent to the command column. That column is raised above content so the list stays visible.
    local cmdScroll = CreateFrame("ScrollFrame", "TaskTrackerNoteCmdScroll", cmdCol)
    cmdScroll:SetPoint("TOPLEFT", cmdCol, "TOPLEFT", CMD_PAD, -CMD_PAD)
    cmdScroll:SetPoint("BOTTOMRIGHT", cmdCol, "BOTTOMRIGHT", -CMD_PAD, CMD_PAD + CMD_BTN_H + 6)
    cmdScroll:EnableMouse(true)

    local cmdChild = CreateFrame("Frame", nil, cmdScroll)
    cmdScroll:SetScrollChild(cmdChild)

    TaskTracker.MakeScrollBar(cmdScroll, cmdScroll)
    cmdChild:Raise()

    local cmdRows = {}

    local function rebuildCmdLayout()
        local rowW = math.max(40, (cmdScroll:GetWidth() or 0) - 18)
        local y = 0
        for _, row in ipairs(cmdRows) do
            if row:IsShown() then
                row:SetWidth(rowW)
                if row.lblEdit then row.lblEdit:SetWidth(math.max(40, rowW - 42)) end
                if row.cmdEdit then row.cmdEdit:SetWidth(math.max(40, rowW - 22)) end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", cmdChild, "TOPLEFT", 0, -y)
                y = y + row:GetHeight() + 4
            end
        end
        cmdChild:SetSize(math.max(40, cmdScroll:GetWidth() - 14), math.max(y, 1))
        if cmdScroll.UpdateScrollBar then cmdScroll.UpdateScrollBar() end
        cmdChild:Raise()
    end

    syncNoteWindowHeight = function()
        applyNoteGeometry()
        local titleH = t.titleHeight or 28
        local minInner = NOTE_H - titleH - 2
        local innerMax = 1100
        local function pack()
            if not frame then return end
            local eh = noteEdit:GetHeight() or 0
            if eh < 20 then
                local lines = math.max(2, noteEdit.GetNumLines and noteEdit:GetNumLines() or 2)
                eh = lines * noteLineHeight() + 16
            end
            local labelH = 14
            if notesLbl.GetStringHeight then
                local lh = notesLbl:GetStringHeight()
                if lh and lh > 8 then labelH = lh end
            end
            local head = 10 + labelH + 6
            local rawHolder = math.max(80, eh + 4)
            local rawInner = head + rawHolder + 10
            local inner = math.max(minInner, rawInner)
            inner = math.min(inner, innerMax)
            local holderBudget = inner - head - 10
            local holderH = math.max(80, math.min(rawHolder, holderBudget))
            noteHolder:SetHeight(holderH)
            frame:SetHeight(titleH + 2 + inner)
            rebuildCmdLayout()
            if cmdScroll.UpdateScrollBar then
                cmdScroll.UpdateScrollBar()
            end
            if TaskTracker.UpdateNoteWindowAnchor then
                TaskTracker.UpdateNoteWindowAnchor()
            end
        end
        pack()
        C_Timer.After(0, pack)
    end

    local function commandFullOf(row)
        if not row then return "" end
        return row._commandFull or ""
    end

    local function showCommandPreview(row, text)
        if not row or not row.cmdEdit then return end
        text = TaskTracker.ClampCommandText and TaskTracker.ClampCommandText(text) or (text or "")
        row._commandFull = text
        local preview = TaskTracker.CommandPreviewText and TaskTracker.CommandPreviewText(text) or text
        row._commandPreview = preview
        if row.cmdEdit:GetText() ~= preview then
            row.cmdEdit:SetText(preview)
        end
    end

    local function paintRunMode(row)
        if not row or not row.modeBtn then return end
        row.modeBtn:SetLabel(row._runMode == "line" and "Lines" or "Full")
    end

    local paintCommandTip

    local function refreshCommandRunners()
        if TaskTracker.MarkListPaintDirty then TaskTracker.MarkListPaintDirty() end
        if TaskTracker.RefreshList then TaskTracker.RefreshList() end
        if TaskTracker.RefreshPeekInlineCommandsIfShown then
            TaskTracker.RefreshPeekInlineCommandsIfShown()
        end
        if TaskTracker.ValidateQuickCommandsPanel then
            TaskTracker.ValidateQuickCommandsPanel()
        end
    end

    local function ghostRowStillBlank(row)
        if not row or not row._ghost then return false end
        local label = trim(row.lblEdit:GetText() or "")
        local command = trim(commandFullOf(row))
        local icon = row._ghostIcon or DEFAULT_ICON_FILE
        return (label == "" or label == COMMAND_BLANK_LABEL) and command == "" and not row._ghostPinned and icon == DEFAULT_ICON_FILE
    end

    local function promoteGhostRow(row)
        local node = frame.boundNode
        if not row or not row._ghost or not node then return nil end
        if type(node.commandButtons) ~= "table" then node.commandButtons = {} end
        local label = trim(row.lblEdit:GetText() or "")
        local b = {
            label = label,
            command = TaskTracker.ClampCommandText and TaskTracker.ClampCommandText(commandFullOf(row)) or trim(commandFullOf(row)),
            icon = row._ghostIcon or DEFAULT_ICON_FILE,
            pinned = row._ghostPinned and true or false,
            runMode = row._runMode == "line" and "line" or nil,
        }
        node.commandButtons[row.idx] = b
        row._ghost = false
        return b
    end

    local function ensureCommandSlot(i)
        local row = cmdRows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, cmdChild)
        row:SetSize(math.max(120, cmdScroll:GetWidth() - 18), 84)
        row.idx = i

        local runBtn = TaskTracker.MakeIconButton(row, 36, 36, {
            iconFill   = true,
            iconMargin = 1,
        })
        runBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

        local pinBtn, delBtn
        local function paintPinBtn(pinned)
            pinBtn._ttPinned = not not pinned
            local atlas = pinned and "Waypoint-MapPin-Tracked" or "Waypoint-MapPin-Untracked"
            if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
                pinBtn:SetIconAtlas(atlas, false)
            else
                pinBtn:SetChromeIcon("mark")
            end
            if pinned then
                TaskTracker.SetColor(pinBtn.bg, "accentBg")
            else
                pinBtn.bg:SetColorTexture(0, 0, 0, 0)
            end
        end
        row.paintPin = paintPinBtn

        pinBtn = TaskTracker.MakeIconButton(row, 18, 18, TaskTracker.ChromeIconOpt())
        delBtn = TaskTracker.MakeIconButton(row, 18, 18, TaskTracker.ChromeIconOpt())
        delBtn:SetChromeIcon("close")
        delBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        pinBtn:SetPoint("TOPRIGHT", delBtn, "TOPLEFT", -2, 0)
        paintPinBtn(false)
        pinBtn:SetScript("OnClick", function()
            local node = frame.boundNode
            if not node then return end
            if row._ghost then
                row._ghostPinned = true
                if not promoteGhostRow(row) then return end
                frame:PopulateFromNode(node)
                if TaskTracker.MarkListPaintDirty then TaskTracker.MarkListPaintDirty() end
                if TaskTracker.RefreshList then TaskTracker.RefreshList() end
                return
            end
            if not node.commandButtons then return end
            local list = node.commandButtons
            local b = list[row.idx]
            if not b then return end
            if b.pinned then
                b.pinned = false
            else
                local n = 0
                for _, x in ipairs(list) do
                    if x.pinned then n = n + 1 end
                end
                if n >= pinCap then
                    for j, x in ipairs(list) do
                        if x.pinned and j ~= row.idx then
                            x.pinned = false
                            break
                        end
                    end
                end
                b.pinned = true
            end
            frame:PopulateFromNode(node)
            if TaskTracker.MarkListPaintDirty then TaskTracker.MarkListPaintDirty() end
            if TaskTracker.RefreshList then TaskTracker.RefreshList() end
        end)

        runBtn:SetScript("OnClick", function()
            local node = frame.boundNode
            if not node then return end
            local startIcon = DEFAULT_ICON_FILE
            if row._ghost then
                startIcon = row._ghostIcon or DEFAULT_ICON_FILE
            else
                local b = node.commandButtons and node.commandButtons[row.idx]
                if not b then return end
                startIcon = tonumber(b.icon) or DEFAULT_ICON_FILE
            end
            local commandText = commandFullOf(row)
            if commandText == "" and row.cmdEdit then
                commandText = row.cmdEdit:GetText() or ""
            end
            TaskTracker.OpenBuiltinIconPicker(frame, startIcon, function(fileId)
                if not fileId then return end
                if row._ghost then
                    row._ghostIcon = tonumber(fileId) or DEFAULT_ICON_FILE
                    if not promoteGhostRow(row) then return end
                else
                    local b = node.commandButtons and node.commandButtons[row.idx]
                    if not b then return end
                    b.icon = tonumber(fileId) or DEFAULT_ICON_FILE
                end
                SetFileIconTexture(runBtn.icon, tonumber(fileId) or DEFAULT_ICON_FILE)
                if TaskTracker.MarkListPaintDirty then TaskTracker.MarkListPaintDirty() end
                if TaskTracker.RefreshList then TaskTracker.RefreshList() end
            end, commandText)
        end)

        delBtn:SetScript("OnClick", function()
            local node = frame.boundNode
            if not node then return end
            if row._ghost then
                row._ghostIcon = DEFAULT_ICON_FILE
                row._ghostPinned = false
                row._runMode = nil
                showCommandPreview(row, "")
                row.lblEdit:SetText("")
                SetFileIconTexture(runBtn.icon, DEFAULT_ICON_FILE)
                paintPinBtn(false)
                paintRunMode(row)
                return
            end
            if not node.commandButtons then return end
            if TaskTracker.HideCommandEditor then TaskTracker.HideCommandEditor() end
            table.remove(node.commandButtons, row.idx)
            frame:PopulateFromNode(node)
            if TaskTracker.MarkListPaintDirty then TaskTracker.MarkListPaintDirty() end
            if TaskTracker.RefreshList then TaskTracker.RefreshList() end
        end)

        local titleLbl = MakeLabel(row, "Title", runBtn, "TOPRIGHT", 6, 0, "textAccent")
        titleLbl:ClearAllPoints()
        titleLbl:SetPoint("TOPLEFT", runBtn, "TOPRIGHT", 6, 0)
        local lblEdit = TaskTracker.MakeEditBox(row, nil, math.max(40, row:GetWidth() - 42), 18)
        lblEdit:SetPoint("BOTTOMLEFT", runBtn, "BOTTOMRIGHT", 6, 0)
        lblEdit:SetMaxLetters(32)
        lblEdit:SetScript("OnEditFocusLost", function()
            local node = frame.boundNode
            if not node then return end
            if row._ghost then
                if ghostRowStillBlank(row) then
                    row.lblEdit:SetText("")
                    return
                end
                promoteGhostRow(row)
                return
            end
            if not node.commandButtons then return end
            local b = node.commandButtons[row.idx]
            if b then b.label = trim(lblEdit:GetText()) end
        end)

        local cmdHead = CreateFrame("Frame", nil, row)
        cmdHead:SetHeight(16)
        cmdHead:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -40)
        cmdHead:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -40)
        local modeBtn = TaskTracker.MakeButton(cmdHead, "Full", 52, 16)
        modeBtn:SetPoint("RIGHT", cmdHead, "RIGHT", 0, 0)
        local cmdLbl = MakeLabel(cmdHead, "Command", cmdHead, "LEFT", 0, 0, "textAccent")
        cmdLbl:ClearAllPoints()
        cmdLbl:SetPoint("LEFT", cmdHead, "LEFT", 0, 0)
        cmdLbl:SetPoint("RIGHT", modeBtn, "LEFT", -4, 0)
        modeBtn:SetScript("OnClick", function()
            local node = frame.boundNode
            if not node then return end
            if row._runMode == "line" then
                row._runMode = nil
            else
                row._runMode = "line"
            end
            paintRunMode(row)
            if row._ghost then return end
            local b = node.commandButtons and node.commandButtons[row.idx]
            if not b then return end
            b.runMode = row._runMode
            refreshCommandRunners()
        end)
        modeBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if row._runMode == "line" then
                GameTooltip:SetText("Lines", 1, 1, 1)
                GameTooltip:AddLine("Line by line. Each line runs as its own command, so a waypoint list fits.", 0.85, 0.85, 0.85, true)
            else
                GameTooltip:SetText("Full", 1, 1, 1)
                GameTooltip:AddLine("Full. The whole command runs as one macro.", 0.85, 0.85, 0.85, true)
            end
            GameTooltip:Show()
        end)
        modeBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

        local cmdEdit = TaskTracker.MakeEditBox(row, nil, math.max(40, row:GetWidth() - 22), 18)
        cmdEdit:SetPoint("TOPLEFT", cmdHead, "BOTTOMLEFT", 0, -2)
        cmdEdit:SetMaxLetters(TaskTracker.COMMAND_TEXT_CAP or 4000)
        cmdEdit:SetScript("OnEditFocusLost", function()
            local node = frame.boundNode
            if not node then return end
            local typed = cmdEdit:GetText() or ""
            local full
            if typed == (row._commandPreview or "") then
                full = row._commandFull or ""
            else
                full = TaskTracker.ClampCommandText and TaskTracker.ClampCommandText(typed) or typed
            end
            showCommandPreview(row, full)
            if row._ghost then
                if ghostRowStillBlank(row) then
                    showCommandPreview(row, "")
                    return
                end
                promoteGhostRow(row)
                refreshCommandRunners()
                return
            end
            local b = node.commandButtons and node.commandButtons[row.idx]
            if b and b.command ~= commandFullOf(row) then
                b.command = commandFullOf(row)
                refreshCommandRunners()
            end
        end)
        local expandBtn = TaskTracker.MakeIconButton(row, 16, 16, TaskTracker.ChromeIconOpt())
        expandBtn:SetChromeIcon("expand")
        expandBtn:SetPoint("LEFT", cmdEdit, "RIGHT", 2, 0)
        expandBtn:SetScript("OnClick", function()
            local node = frame.boundNode
            if not node then return end
            local current = commandFullOf(row)
            local btn = (not row._ghost) and node.commandButtons and node.commandButtons[row.idx] or nil
            TaskTracker.OpenCommandEditor(current, function(newText)
                showCommandPreview(row, newText)
                if btn then
                    btn.command = commandFullOf(row)
                    if frame.boundNode and frame.boundNode.commandButtons
                        and frame.boundNode.commandButtons[row.idx] == btn then
                        paintCommandTip(row, btn.label, btn.command)
                    end
                    refreshCommandRunners()
                    return
                end
                if row._ghost and not ghostRowStillBlank(row) then
                    if promoteGhostRow(row) then
                        frame:PopulateFromNode(node)
                    end
                    refreshCommandRunners()
                end
            end)
        end)
        expandBtn:SetScript("OnEnter", function(self)
            TaskTracker.SetColor(self.bg, "accentBg")
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Larger editor", 1, 1, 1)
            GameTooltip:AddLine("Paste several lines here. The box keeps the first line.", 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        expandBtn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            self.bg:SetColorTexture(0, 0, 0, 0)
        end)

        runBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Icon", 1, 1, 1)
            GameTooltip:AddLine("Choose an icon for this command.", 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        runBtn:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row.runBtn = runBtn
        row.pinBtn = pinBtn
        row.delBtn = delBtn
        pinBtn:SetScript("OnEnter", function(self)
            TaskTracker.SetColor(self.bg, "accentBg")
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._ttPinned and "Pinned" or "Pin", 1, 1, 1)
            GameTooltip:AddLine("Show this command on the task row.", 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        pinBtn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            paintPinBtn(self._ttPinned)
        end)
        delBtn:SetScript("OnEnter", function(self)
            TaskTracker.SetColor(self.bg, "accentBg")
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Remove", 1, 1, 1)
            GameTooltip:AddLine("Remove this command.", 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        delBtn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            self.bg:SetColorTexture(0, 0, 0, 0)
        end)

        row.lblEdit = lblEdit
        row.cmdEdit = cmdEdit
        row.modeBtn = modeBtn
        row.expandBtn = expandBtn
        row._commandFull = ""
        row._commandPreview = ""
        paintRunMode(row)
        cmdRows[i] = row
        return row
    end

    paintCommandTip = function(row, label, command)
        row.cmdEdit:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row.cmdEdit, "ANCHOR_RIGHT")
            GameTooltip:SetText(label or COMMAND_BLANK_LABEL, 1, 1, 1)
            if command and command ~= "" then
                GameTooltip:AddLine(command, 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end)
        row.cmdEdit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local function showBlankCommandRow()
        local row = ensureCommandSlot(1)
        row._ghost = true
        row._ghostIcon = DEFAULT_ICON_FILE
        row._ghostPinned = false
        row._runMode = nil
        row:Show()
        SetFileIconTexture(row.runBtn.icon, DEFAULT_ICON_FILE)
        row.lblEdit:SetText("")
        showCommandPreview(row, "")
        if row.paintPin then row.paintPin(false) end
        paintRunMode(row)
        paintCommandTip(row, COMMAND_BLANK_LABEL, "")
        for i = 2, #cmdRows do
            cmdRows[i]:Hide()
            cmdRows[i]._ghost = false
        end
    end

    function frame:PopulateFromNode(node)
        self.boundNode = node
        noteEdit:SetText(node.note or "")
        if frame._refreshNoteHint then frame._refreshNoteHint() end
        local list = node.commandButtons or {}
        if #list == 0 then
            showBlankCommandRow()
        else
            for i = 1, #list do
                local b = list[i]
                local row = ensureCommandSlot(i)
                row._ghost = false
                row._runMode = b.runMode == "line" and "line" or nil
                row:Show()
                SetFileIconTexture(row.runBtn.icon, b.icon, b.command)
                row.lblEdit:SetText(b.label or "")
                showCommandPreview(row, b.command or "")
                if row.paintPin then row.paintPin(b.pinned) end
                paintRunMode(row)
                -- Tooltip on cmd edit (run icon is InsecureActionButtonTemplate; keep tips off the click target).
                paintCommandTip(row, b.label, b.command)
            end
            for i = #list + 1, #cmdRows do
                cmdRows[i]:Hide()
                cmdRows[i]._ghost = false
            end
        end
        rebuildCmdLayout()
        syncNoteWindowHeight()
    end

    local addCmdBtn = TaskTracker.MakeButton(cmdCol, "Add command", CMD_W - CMD_PAD * 2, CMD_BTN_H)
    addCmdBtn:SetPoint("BOTTOMLEFT", cmdCol, "BOTTOMLEFT", CMD_PAD, CMD_PAD)
    TaskTracker.SetColor(addCmdBtn.bg, "accentBg")
    TaskTracker.SetTextColor(addCmdBtn.label, "textAccent")
    addCmdBtn:SetScript("OnClick", function()
        local node = frame.boundNode
        if not node then return end
        if type(node.commandButtons) ~= "table" then node.commandButtons = {} end
        table.insert(node.commandButtons, {
            label = "",
            command = "",
            icon = DEFAULT_ICON_FILE,
            pinned = false,
        })
        frame:PopulateFromNode(node)
    end)

    frame:SetScript("OnHide", function()
        if TaskTracker.HideCommandEditor then TaskTracker.HideCommandEditor() end
        local hp = TaskTracker.helpPopup
        if hp and hp:IsShown() and hp.currentKey == "notes" then
            hp:Hide()
        end
        if frame._noteSaveDebounce then
            frame._noteSaveDebounce:Cancel()
            frame._noteSaveDebounce = nil
        end
        frame:FlushNoteToNode()
        frame.boundNode = nil
    end)

    frame:SetToplevel(true)
    -- Keep body above panel chrome textures (bg/border) on the root frame.
    content:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    content:Raise()
    cmdCol:SetFrameLevel((frame:GetFrameLevel() or 0) + 25)
    cmdCol:Raise()
    cmdScroll:SetFrameLevel((cmdCol:GetFrameLevel() or 0) + 2)
    addCmdBtn:SetFrameLevel((cmdCol:GetFrameLevel() or 0) + 4)
    frame.titleBar:SetFrameLevel((frame:GetFrameLevel() or 0) + 40)
    frame.titleBar:Raise()
    if frame.bg and frame.bg.Lower then
        frame.bg:Lower()
    end

    frame.noteEdit = noteEdit
    frame.noteCmdScroll = cmdScroll
    noteHolder:SetFrameLevel((content:GetFrameLevel() or 0) + 1)
    addCmdBtn:Raise()

    syncNoteWindowHeight()

    frame:SetScript("OnShow", function()
        syncNoteWindowHeight()
    end)

    return frame
end

function TaskTracker.HideNotePeekWindow()
    eachNotePeek(function(w)
        if w:IsShown() then w:Hide() end
    end)
end

local function applyOnePeekOpacity(w)
    if not w then return end
    local t = TaskTracker.GetTheme()
    local hovered = w._peekHover == true
    local ab = TaskTracker.GetNotePeekBgOpacity and TaskTracker.GetNotePeekBgOpacity(hovered) or 0.85
    local at = TaskTracker.GetNotePeekTextOpacity and TaskTracker.GetNotePeekTextOpacity(hovered) or 1
    if w.peekBg and t and t.inputBg then
        local c = t.inputBg
        w.peekBg:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * ab)
    end
    if w.peekName and t and t.textAccent then
        local nc = t.textAccent
        w.peekName:SetTextColor(nc[1], nc[2], nc[3], (nc[4] or 1) * at)
    end
    if w.peekEdit and t and t.textPrimary then
        local tc = t.textPrimary
        w.peekEdit:SetTextColor(tc[1], tc[2], tc[3], (tc[4] or 1) * at)
    end
    if TaskTracker.ApplyPeekCmdButtonAlpha then
        TaskTracker.ApplyPeekCmdButtonAlpha(w)
    end
end

function TaskTracker.ApplyNotePeekOpacity(only)
    if only then
        applyOnePeekOpacity(only)
        return
    end
    if not TaskTracker.notePeekWindows then
        applyOnePeekOpacity(TaskTracker.notePeekWindow)
        return
    end
    eachNotePeek(applyOnePeekOpacity)
end

function TaskTracker.SyncNotePeekFromMain()
    local nw = TaskTracker.noteWindow
    if not nw or not nw.boundTaskId or not nw.noteEdit then return end
    local text = noteTextForPeek(nw.noteEdit:GetText())
    local title = nw._peekTitle
    if not title or title == "" then title = peekTitleFor(nw.boundNode) end
    eachNotePeek(function(pk)
        if not pk:IsShown() or pk.boundTaskId ~= nw.boundTaskId or not pk.peekEdit then return end
        pk.peekTitle = title
        if pk.peekName then pk.peekName:SetText(title) end
        pk.peekEdit:SetText(text)
        applyOnePeekOpacity(pk)
        if pk._requestPeekLayout then pk._requestPeekLayout() end
    end)
end

local function savePeekPoint(frame)
    if not frame or not frame:IsShown() or not frame.boundTaskId or not TaskTrackerDB then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if not point or x == nil or y == nil then return end
    if type(TaskTrackerDB.notePeekPoints) ~= "table" then
        TaskTrackerDB.notePeekPoints = {}
    end
    TaskTrackerDB.notePeekPoints[frame.boundTaskId] = {
        point = point,
        relPoint = relPoint or point,
        x = x,
        y = y,
    }
end

local function restorePeekPoint(frame, taskId)
    local map = TaskTrackerDB and TaskTrackerDB.notePeekPoints
    local pos = type(map) == "table" and taskId and map[taskId]
    if type(pos) ~= "table" or not pos.point or pos.x == nil or pos.y == nil then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    return true
end

local function rememberPeekOpen(taskId, open)
    if not taskId or taskId == "__tt_task_dialog_draft" or not TaskTrackerDB then return end
    local list = TaskTrackerDB.notePeekOpen
    if type(list) ~= "table" then
        list = {}
        TaskTrackerDB.notePeekOpen = list
    end
    for i = #list, 1, -1 do
        if list[i] == taskId then
            table.remove(list, i)
        end
    end
    if open then
        list[#list + 1] = taskId
    end
end

local function acquireNotePeek(taskId)
    local list = TaskTracker.notePeekWindows or {}
    TaskTracker.notePeekWindows = list
    local reuse
    for i = 1, #list do
        local w = list[i]
        if w:IsShown() and w.boundTaskId == taskId then
            return w, true
        end
        if not w:IsShown() and not reuse then
            reuse = w
        end
    end
    if reuse then return reuse, false end
    return TaskTracker.CreateNotePeekWindow(), false
end

function TaskTracker.OpenNotePeekWindow()
    local nw = TaskTracker.noteWindow
    if not nw or not nw.boundNode or not nw.noteEdit then return end
    local taskId = nw.boundTaskId
    local pk, already = acquireNotePeek(taskId)
    if not pk then return end
    if already then
        rememberPeekOpen(taskId, false)
        pk:Hide()
        return
    end
    local title = nw._peekTitle
    if not title or title == "" then title = peekTitleFor(nw.boundNode) end
    pk.boundTaskId = taskId
    pk.peekTitle = title
    if pk.peekName then
        pk.peekName:SetText(title)
        TaskTracker.SetTextColor(pk.peekName, "textAccent")
    end
    pk.peekEdit:SetText(noteTextForPeek(nw.noteEdit:GetText()))
    applyOnePeekOpacity(pk)
    local n = 0
    eachNotePeek(function(w)
        if w:IsShown() then n = n + 1 end
    end)
    if not restorePeekPoint(pk, taskId) then
        pk:ClearAllPoints()
        pk:SetPoint("CENTER", UIParent, "CENTER", 28 * n, 40 - 24 * n)
    end
    pk:SetFrameStrata("DIALOG")
    pk:SetFrameLevel((nw:GetFrameLevel() or 80) + 15 + n)
    pk:Show()
    pk:Raise()
    rememberPeekOpen(taskId, true)
    savePeekPoint(pk)
    if pk._requestPeekLayout then
        pk._requestPeekLayout()
    end
end

function TaskTracker.ShowSavedNotePeek(taskId)
    if not taskId or taskId == "__tt_task_dialog_draft" then return end
    local node = TaskTracker.FindNode and TaskTracker.FindNode(taskId)
    if not node then
        -- The login profile may not be on yet. Keep the id and try again.
        if TaskTracker._activeCharProgressKey then
            rememberPeekOpen(taskId, false)
        end
        return
    end
    local pk, already = acquireNotePeek(taskId)
    if not pk then return end
    if already then
        pk:Raise()
        return
    end
    pk.boundTaskId = taskId
    pk.peekTitle = peekTitleFor(node)
    if pk.peekName then
        pk.peekName:SetText(pk.peekTitle)
        TaskTracker.SetTextColor(pk.peekName, "textAccent")
    end
    if pk.peekEdit then
        pk.peekEdit:SetText(noteTextForPeek(node.note))
    end
    applyOnePeekOpacity(pk)
    if not restorePeekPoint(pk, taskId) then
        pk:ClearAllPoints()
        pk:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    pk:SetFrameStrata("DIALOG")
    pk:Show()
    pk:Raise()
    rememberPeekOpen(taskId, true)
    if pk._requestPeekLayout then
        pk._requestPeekLayout()
    end
end

function TaskTracker.RestoreOpenNotePeeks()
    local ids = TaskTrackerDB and TaskTrackerDB.notePeekOpen
    if type(ids) ~= "table" then return end
    local copy = {}
    for i = 1, #ids do
        copy[i] = ids[i]
    end
    for i = 1, #copy do
        TaskTracker.ShowSavedNotePeek(copy[i])
    end
end

--- Login's entering-world event fires before that event is registered.
--- Open the saved popouts once the character profile is on and the player is in the world.
function TaskTracker.ScheduleRestoreOpenNotePeeks()
    if TaskTracker._ttPeeksRestored then return end
    if IsPlayerInWorld and not IsPlayerInWorld() then return end
    if not TaskTracker._activeCharProgressKey then return end
    TaskTracker._ttPeeksRestored = true
    local function go()
        if TaskTracker.RestoreOpenNotePeeks then
            TaskTracker.RestoreOpenNotePeeks()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, go)
    else
        go()
    end
end

function TaskTracker.RememberShownNotePeeks()
    eachNotePeek(function(w)
        if w:IsShown() and w.boundTaskId then
            rememberPeekOpen(w.boundTaskId, true)
            savePeekPoint(w)
        end
    end)
end

function TaskTracker.CreateNotePeekWindow()
    local MAX_EDIT_H   = 380
    local MIN_EDIT_H   = 72
    local MIN_PEEK_INNER = 40
    local MAX_PEEK_INNER = 540
    local HOLDER_PAD = 12
    local INSET_L, INSET_R = 8, 12
    local t = TaskTracker.GetTheme()

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(280, 200)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(95)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()

    local measureFS = TaskTracker.CreateFontString(frame, nil, "ARTWORK")
    measureFS:Hide()
    measureFS:SetJustifyH("LEFT")
    if measureFS.SetWordWrap then
        measureFS:SetWordWrap(false)
    end

    local textHolder = CreateFrame("Frame", nil, frame)
    textHolder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    textHolder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    local peekCmdRail = CreateFrame("Frame", nil, frame)
    peekCmdRail:SetFrameLevel((frame:GetFrameLevel() or 0) + 22)
    peekCmdRail:EnableMouse(true)
    peekCmdRail:Hide()
    frame.peekCmdRail = peekCmdRail

    local peekEdit = CreateFrame("EditBox", nil, textHolder)
    peekEdit:SetMultiLine(true)
    pcall(function()
        peekEdit:SetSplitFullWords(false)
    end)
    peekEdit:SetFontObject(t.fontNormal or "GameFontHighlightSmall")
    TaskTracker.ClearFontShadow(peekEdit)
    for _, region in ipairs({ peekEdit:GetRegions() }) do
        if region.GetWordWrap and region.SetWordWrap then
            region:SetWordWrap(true)
        end
    end
    if peekEdit.SetShadowOffset then
        peekEdit:SetShadowOffset(0, 0)
    end
    peekEdit:SetEnabled(false)
    peekEdit:EnableMouse(true)
    peekEdit:SetMaxLetters(4000)
    peekEdit:SetTextInsets(INSET_L, INSET_R, 22, 8)
    local peekBg = peekEdit:CreateTexture(nil, "BACKGROUND")
    peekBg:SetAllPoints()
    frame.peekBg = peekBg

    local TITLE_BTNS = 18 + 2 + 18 + 8
    local nameLbl = peekEdit:CreateFontString(nil, "OVERLAY", t.fontNormal or "GameFontHighlightSmall")
    TaskTracker.ClearFontShadow(nameLbl)
    nameLbl:SetPoint("TOPLEFT", peekEdit, "TOPLEFT", INSET_L, -4)
    nameLbl:SetJustifyH("LEFT")
    nameLbl:SetText("Note")
    TaskTracker.SetTextColor(nameLbl, "textAccent")
    if nameLbl.SetWordWrap then nameLbl:SetWordWrap(false) end
    frame.peekName = nameLbl

    local closeBtn = TaskTracker.MakeIconButton(peekEdit, 18, 18, TaskTracker.ChromeIconOpt())
    closeBtn:SetChromeIcon("close")
    closeBtn:SetPoint("TOPRIGHT", peekEdit, "TOPRIGHT", -4, -3)
    closeBtn:SetFrameLevel((peekEdit:GetFrameLevel() or 0) + 8)
    closeBtn:SetScript("OnClick", function()
        rememberPeekOpen(frame.boundTaskId, false)
        frame:Hide()
    end)
    closeBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Close", 1, 1, 1)
        GameTooltip:Show()
    end)
    closeBtn:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame.peekCloseBtn = closeBtn

    local editBtn = TaskTracker.MakeIconButton(peekEdit, 18, 18, TaskTracker.ChromeIconOpt())
    editBtn:SetChromeIcon("edit")
    editBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    editBtn:SetFrameLevel((peekEdit:GetFrameLevel() or 0) + 8)
    editBtn:SetScript("OnClick", function()
        local id = frame.boundTaskId
        local node = id and TaskTracker.FindNode and TaskTracker.FindNode(id)
        if not node and TaskTracker.noteWindow and TaskTracker.noteWindow.boundTaskId == id then
            node = TaskTracker.noteWindow.boundNode
        end
        if node and TaskTracker.OpenNoteWindow then
            TaskTracker.OpenNoteWindow(node)
        end
    end)
    editBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Edit", 1, 1, 1)
        GameTooltip:AddLine("Opens notes.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    editBtn:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame.peekEditBtn = editBtn

    local function startMove()
        frame:StartMoving()
    end
    local function stopMove()
        frame:StopMovingOrSizing()
        savePeekPoint(frame)
    end
    textHolder:RegisterForDrag("LeftButton")
    textHolder:SetScript("OnDragStart", startMove)
    textHolder:SetScript("OnDragStop", stopMove)
    peekEdit:RegisterForDrag("LeftButton")
    peekEdit:SetScript("OnDragStart", startMove)
    peekEdit:SetScript("OnDragStop", stopMove)

    local function lineHeight()
        return (select(2, peekEdit:GetFont()) or 12) + 2
    end

    local function measureMaxLineInner()
        local text = (peekEdit:GetText() or ""):gsub("\r", "")
        if peekEdit.GetFontObject then
            local fo = peekEdit:GetFontObject()
            if fo then
                measureFS:SetFontObject(fo)
                TaskTracker.ClearFontShadow(measureFS)
            end
        end
        if not measureFS:GetFont() then
            local fp, sz, fl = peekEdit:GetFont()
            if fp and sz then
                measureFS:SetFont(fp, sz, fl or "")
                TaskTracker.ClearFontShadow(measureFS)
            end
        end
        local maxw = 24
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            local disp = (line ~= "") and line or " "
            measureFS:SetText(disp)
            local w = measureFS:GetStringWidth() or 0
            if w > maxw then
                maxw = w
            end
        end
        return math.min(MAX_PEEK_INNER, math.max(MIN_PEEK_INNER, math.ceil(maxw)))
    end

    local function doPeekLayout()
        if not textHolder:IsVisible() then return end

        if TaskTracker.RefreshPeekInlineCommands then
            TaskTracker.RefreshPeekInlineCommands(frame)
        end

        local node = TaskTracker.FindNode and TaskTracker.FindNode(frame.boundTaskId)
        local cmds = (node and TaskTracker.GetRunnableCommandButtons and TaskTracker.GetRunnableCommandButtons(node)) or {}
        local nCmd   = #cmds

        local shownName = frame.peekTitle
        if not shownName or shownName == "" then
            shownName = (node and node.name and node.name ~= "" and node.name) or "Note"
        end
        if frame.peekName then
            frame.peekName:SetText(shownName)
            TaskTracker.SetTextColor(frame.peekName, "textAccent")
        end

        local innerMeasured = measureMaxLineInner()
        if frame.peekName and shownName ~= "" then
            measureFS:SetText(shownName)
            local nameW = math.ceil(measureFS:GetStringWidth() or 0) + TITLE_BTNS
            if nameW > innerMeasured then
                innerMeasured = math.min(MAX_PEEK_INNER, nameW)
            end
        end
        local editW = innerMeasured + INSET_L + INSET_R
        if nCmd > 0 and frame.peekCmdRail and frame.peekCmdRail:IsShown() then
            local railW = (frame.peekCmdRail:GetWidth() or 0) + INSET_L + INSET_R
            if railW > editW then
                editW = railW
            end
        end
        local textHolderW = editW + HOLDER_PAD
        local frameW = textHolderW
        if frame.peekName then
            frame.peekName:SetWidth(math.max(40, editW - INSET_L - INSET_R - TITLE_BTNS))
        end

        peekEdit:SetWidth(math.max(40, editW))
        peekEdit:ClearAllPoints()
        peekEdit:SetPoint("TOPLEFT", textHolder, "TOPLEFT", 6, -6)

        local lines = math.max(1, peekEdit.GetNumLines and peekEdit:GetNumLines() or 1)
        local lh = lineHeight()
        local cmdPad = 0
        if nCmd > 0 and frame.peekCmdRail and frame.peekCmdRail:IsShown() then
            cmdPad = (frame.peekCmdRail:GetHeight() or 22) + 4
        end
        peekEdit:SetTextInsets(INSET_L, INSET_R, 24, 8 + cmdPad)
        local wantH = math.min(MAX_EDIT_H, math.max(MIN_EDIT_H, lines * lh + 26 + cmdPad))

        textHolder:ClearAllPoints()
        textHolder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        textHolder:SetSize(textHolderW, wantH + 12)
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("TOPRIGHT", peekEdit, "TOPRIGHT", -4, -3)
        if frame.peekEditBtn then
            frame.peekEditBtn:ClearAllPoints()
            frame.peekEditBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
        end

        local sig = tostring(math.floor(frameW + 0.5)) .. ":" .. tostring(math.floor(wantH + 0.5)) .. ":" .. tostring(nCmd)
        if frame._peekLayoutSig == sig then
            if nCmd > 0 and frame.peekCmdRail then
                frame.peekCmdRail:ClearAllPoints()
                frame.peekCmdRail:SetPoint("BOTTOMLEFT", peekEdit, "BOTTOMLEFT", 6, 4)
            end
            applyOnePeekOpacity(frame)
            return
        end
        frame._peekLayoutSig = sig

        frame:SetWidth(frameW)
        peekEdit:SetHeight(wantH)
        frame:SetHeight(wantH + 12)

        if peekEdit.GetVerticalScrollRange and peekEdit.SetVerticalScroll then
            local ms = math.max(0, peekEdit:GetVerticalScrollRange() or 0)
            if ms > 0 then
                peekEdit:SetVerticalScroll(math.min(ms, peekEdit:GetVerticalScroll() or 0))
            end
        end

        if nCmd > 0 and frame.peekCmdRail then
            frame.peekCmdRail:ClearAllPoints()
            frame.peekCmdRail:SetPoint("BOTTOMLEFT", peekEdit, "BOTTOMLEFT", 6, 4)
        end
        applyOnePeekOpacity(frame)
    end

    local function requestPeekLayout()
        if frame._peekLayoutTimer then
            frame._peekLayoutTimer:Cancel()
            frame._peekLayoutTimer = nil
        end
        frame._peekLayoutTimer = C_Timer.NewTimer(0.02, function()
            frame._peekLayoutTimer = nil
            if frame:IsShown() then
                doPeekLayout()
            end
        end)
    end
    frame._requestPeekLayout = requestPeekLayout

    local function peekWheelScroll(_, delta)
        if not peekEdit.GetVerticalScrollRange or not peekEdit.SetVerticalScroll then return end
        local ms = math.max(0, peekEdit:GetVerticalScrollRange() or 0)
        if ms <= 0 then return end
        local step = 30
        local cur  = peekEdit:GetVerticalScroll() or 0
        peekEdit:SetVerticalScroll(math.max(0, math.min(ms, cur - delta * step)))
    end
    peekEdit:EnableMouseWheel(true)
    peekEdit:SetScript("OnMouseWheel", peekWheelScroll)
    textHolder:EnableMouseWheel(true)
    textHolder:SetScript("OnMouseWheel", peekWheelScroll)

    peekEdit:SetScript("OnTextChanged", function()
        requestPeekLayout()
    end)

    frame:SetToplevel(true)
    textHolder:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
    textHolder:Raise()
    peekCmdRail:Raise()
    closeBtn:Raise()
    editBtn:Raise()

    frame.peekEdit = peekEdit

    local function pointerOverPeek()
        if frame:IsMouseOver() then return true end
        local rail = frame.peekCmdRail
        if rail and rail:IsShown() and rail:IsMouseOver() then return true end
        if closeBtn:IsMouseOver() then return true end
        if editBtn:IsMouseOver() then return true end
        return false
    end
    local function setPeekHover(over)
        over = over and true or false
        if frame._peekHover == over then return end
        frame._peekHover = over
        applyOnePeekOpacity(frame)
    end
    local function queuePeekHover()
        if frame._peekHoverTimer then
            frame._peekHoverTimer:Cancel()
        end
        frame._peekHoverTimer = C_Timer.NewTimer(0, function()
            frame._peekHoverTimer = nil
            if frame:IsShown() then
                setPeekHover(pointerOverPeek())
            end
        end)
    end
    frame._setPeekHover = setPeekHover
    frame._queuePeekHover = queuePeekHover
    local function hookHover(widget)
        if not widget or not widget.HookScript then return end
        widget:HookScript("OnEnter", function() setPeekHover(true) end)
        widget:HookScript("OnLeave", queuePeekHover)
    end
    hookHover(frame)
    hookHover(textHolder)
    hookHover(peekEdit)
    hookHover(closeBtn)
    hookHover(editBtn)
    hookHover(peekCmdRail)

    TaskTracker.notePeekWindows = TaskTracker.notePeekWindows or {}
    TaskTracker.notePeekWindows[#TaskTracker.notePeekWindows + 1] = frame
    if not TaskTracker.notePeekWindow then
        TaskTracker.notePeekWindow = frame
    end

    frame:SetScript("OnShow", function()
        frame._peekLayoutSig = nil
        frame._peekHover = false
        TaskTracker.ApplyNotePeekOpacity(frame)
        queuePeekHover()
        requestPeekLayout()
    end)

    return frame
end