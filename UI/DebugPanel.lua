-- UI/DebugPanel.lua
-- Developer toggles and one-click equivalents of /tt debug commands.

TaskTracker = TaskTracker or {}

local PANEL_W, PANEL_H = 460, 610

local function styleToggleBtn(btn, on, onText, offText)
    if on then
        btn:SetLabel(onText)
        TaskTracker.SetColor(btn.bg, "accentBg")
        TaskTracker.SetTextColor(btn.label, "textAccent")
    else
        btn:SetLabel(offText)
        TaskTracker.SetColor(btn.bg, "headerBg")
        TaskTracker.SetTextColor(btn.label, "textPrimary")
    end
end

local function rowLabel(parent, y, title, subtitle)
    local t = TaskTracker.GetTheme()
    local titleFs = TaskTracker.CreateFontString(parent, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    titleFs:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -y)
    titleFs:SetWidth(PANEL_W - 160)
    titleFs:SetJustifyH("LEFT")
    TaskTracker.SetTextColor(titleFs, "textPrimary")
    titleFs:SetText(title)

    local subFs = TaskTracker.CreateFontString(parent, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    subFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -2)
    subFs:SetWidth(PANEL_W - 160)
    subFs:SetJustifyH("LEFT")
    TaskTracker.SetTextColor(subFs, "textSecondary")
    subFs:SetText(subtitle)

    return titleFs, subFs, 36
end

function TaskTracker.EnsureDebugPanel()
    if TaskTracker.debugPanel then
        return TaskTracker.debugPanel
    end

    local panel = TaskTracker.MakePanel("TaskTrackerDebug", UIParent, PANEL_W, PANEL_H)
    if TaskTracker.AnchorFrameNearScreenTop then
        TaskTracker.AnchorFrameNearScreenTop(panel, 0, 0.14)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(260)
    panel:Hide()

    panel.TitleText:SetText("Task Tracker — Debug")
    panel.CloseButton:SetScript("OnClick", function()
        panel:Hide()
    end)

    local body = CreateFrame("Frame", nil, panel.Content)
    body:SetAllPoints()
    body:EnableMouse(true)

    local t = TaskTracker.GetTheme()
    local y = 10

    local sec = TaskTracker.CreateFontString(body, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    sec:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -y)
    TaskTracker.SetTextColor(sec, "textAccent")
    sec:SetText("Toggles")
    y = y + 22

    local sep = body:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -y)
    sep:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, -y)
    TaskTracker.SetColor(sep, "border")
    y = y + 10

    local idsBtn = TaskTracker.MakeButton(body, "Row IDs: OFF", 132, 24)
    idsBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -(y - 2))
    rowLabel(body, y, "Row debug IDs", "Hold Ctrl on a row to show IDs in the tooltip. Starts off.")
    y = y + 44
    idsBtn:SetScript("OnClick", function()
        TaskTrackerDB = TaskTrackerDB or {}
        TaskTrackerDB.debugRowIds = not (TaskTrackerDB.debugRowIds == true)
        print("|cff00ff00TaskTracker|r Row debug IDs: " .. (TaskTrackerDB.debugRowIds and "ON" or "OFF"))
        TaskTracker.RefreshDebugPanelIfShown()
    end)

    local mobBtn = TaskTracker.MakeButton(body, "Mob kill: OFF", 132, 24)
    mobBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -(y - 2))
    rowLabel(body, y, "Mob kill debug", "/tt mobdebug — extra mob/combat prints.")
    y = y + 44
    mobBtn:SetScript("OnClick", function()
        TaskTrackerDB = TaskTrackerDB or {}
        TaskTrackerDB.debugMobKill = not (TaskTrackerDB.debugMobKill == true)
        print("|cff00ff00TaskTracker|r Mob kill debug: " .. (TaskTrackerDB.debugMobKill and "ON" or "OFF"))
        TaskTracker.RefreshDebugPanelIfShown()
    end)

    local fishBtn = TaskTracker.MakeButton(body, "Fishing: OFF", 132, 24)
    fishBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -(y - 2))
    rowLabel(body, y, "Fishing spell debug", "/tt fishdebug — log spellId on each cast SENT.")
    y = y + 44
    fishBtn:SetScript("OnClick", function()
        TaskTrackerDB = TaskTrackerDB or {}
        TaskTrackerDB.debugFishSpell = not (TaskTrackerDB.debugFishSpell == true)
        local sentReg = "?"
        local fr = TaskTracker._ttCoreBootstrapFrame
        if fr and fr.IsEventRegistered then
            local ok, v = pcall(function()
                return fr:IsEventRegistered("UNIT_SPELLCAST_SENT")
            end)
            if ok then
                sentReg = v and "yes" or "no"
            end
        end
        print("|cff00ff00TaskTracker|r Fishing spell debug: " .. (TaskTrackerDB.debugFishSpell and "ON" or "OFF")
            .. " | UNIT_SPELLCAST_SENT registered=" .. sentReg
            .. " — cast Fishing once; next SENT logs spellId, mapId, pool hint (even if spell is not whitelisted).")
        TaskTracker.RefreshDebugPanelIfShown()
    end)

    local refreshBtn = TaskTracker.MakeButton(body, "Refresh src: OFF", 132, 24)
    refreshBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -(y - 2))
    rowLabel(body, y, "Refresh source logging", "Chat when the task list syncs and why (TaskTrackerDB.debugRefreshSource).")
    y = y + 44
    refreshBtn:SetScript("OnClick", function()
        TaskTrackerDB = TaskTrackerDB or {}
        TaskTrackerDB.debugRefreshSource = not (TaskTrackerDB.debugRefreshSource == true)
        print("|cff00ff00TaskTracker|r Refresh source logging: "
            .. ((TaskTrackerDB.debugRefreshSource == true) and "ON" or "OFF"))
        TaskTracker.RefreshDebugPanelIfShown()
    end)

    local perfBtn = TaskTracker.MakeButton(body, "List perf: OFF", 132, 24)
    perfBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -(y - 2))
    rowLabel(body, y, "List performance sampling", "Per-refresh timings in chat (TaskTrackerDB.debugPerf).")
    y = y + 44
    perfBtn:SetScript("OnClick", function()
        TaskTrackerDB = TaskTrackerDB or {}
        TaskTrackerDB.debugPerf = not (TaskTrackerDB.debugPerf == true)
        print("|cff00ff00TaskTracker|r List perf debug: "
            .. ((TaskTrackerDB.debugPerf == true) and "ON" or "OFF"))
        TaskTracker.RefreshDebugPanelIfShown()
    end)

    y = y + 16
    local sec2 = TaskTracker.CreateFontString(body, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    sec2:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -y)
    TaskTracker.SetTextColor(sec2, "textAccent")
    sec2:SetText("Commands (same as slash)")
    y = y + 22

    local sep2 = body:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -y)
    sep2:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, -y)
    TaskTracker.SetColor(sep2, "border")
    y = y + 10

    local statusBtn = TaskTracker.MakeButton(body, "mobdebug status", 200, 24)
    statusBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -y)
    statusBtn:SetScript("OnClick", function()
        TaskTracker.PrintMobDebugStatus()
    end)
    y = y + 30

    local retryBtn = TaskTracker.MakeButton(body, "mobdebug retry", 200, 24)
    retryBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -y)
    retryBtn:SetScript("OnClick", function()
        TaskTracker.RetryCoreEventRegistration()
        print("|cff00ff00TaskTracker|r Retrying event registration…")
    end)
    y = y + 30

    local clBtn = TaskTracker.MakeButton(body, "Combat log: OFF", 200, 24)
    clBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -y)
    clBtn:SetScript("OnClick", function()
        TaskTracker.ToggleCombatLogKillTracking()
    end)
    y = y + 40

    local sec3 = TaskTracker.CreateFontString(body, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    sec3:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -y)
    TaskTracker.SetTextColor(sec3, "textAccent")
    sec3:SetText("New install")
    y = y + 22

    local sep3 = body:CreateTexture(nil, "ARTWORK")
    sep3:SetHeight(1)
    sep3:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -y)
    sep3:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, -y)
    TaskTracker.SetColor(sep3, "border")
    y = y + 10

    local previewBtn = TaskTracker.MakeButton(body, "Open", 132, 24)
    previewBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -(y - 2))
    local previewTitle, previewSub = rowLabel(body, y, "Hidden profile",
        "This character opens a new install. Your profile is saved first. It is not in the profile list.")
    if previewSub.SetWordWrap then previewSub:SetWordWrap(true) end
    previewSub:SetWidth(PANEL_W - 180)
    y = y + 58
    previewBtn:SetScript("OnClick", function()
        if TaskTracker.ToggleFreshInstallProfile then
            TaskTracker.ToggleFreshInstallProfile()
        end
    end)

    local hint = TaskTracker.CreateFontString(body, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -y)
    hint:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -y)
    hint:SetJustifyH("LEFT")
    TaskTracker.SetTextColor(hint, "textSecondary")
    hint:SetText("Open or close this window with |cff88ff88/tt debug|r.")

    panel._debugIdsBtn = idsBtn
    panel._debugMobBtn = mobBtn
    panel._debugFishBtn = fishBtn
    panel._debugRefreshBtn = refreshBtn
    panel._debugPerfBtn = perfBtn
    panel._debugClBtn = clBtn
    panel._debugPreviewBtn = previewBtn
    panel._debugPreviewTitle = previewTitle
    panel._debugPreviewSub = previewSub

    TaskTracker.debugPanel = panel
    if TaskTracker.ApplyUIScale then
        TaskTracker.ApplyUIScale()
    end
    return panel
end

function TaskTracker.RefreshDebugPanelIfShown()
    local panel = TaskTracker.debugPanel
    if not panel or not panel:IsShown() then return end
    TaskTrackerDB = TaskTrackerDB or {}

    local idsBtn = panel._debugIdsBtn
    if idsBtn then
        styleToggleBtn(idsBtn, TaskTrackerDB.debugRowIds == true, "Row IDs: ON", "Row IDs: OFF")
    end
    local mobBtn, fishBtn = panel._debugMobBtn, panel._debugFishBtn
    local refreshBtn, perfBtn = panel._debugRefreshBtn, panel._debugPerfBtn
    if mobBtn then
        styleToggleBtn(mobBtn, TaskTrackerDB.debugMobKill == true, "Mob kill: ON", "Mob kill: OFF")
    end
    if fishBtn then
        styleToggleBtn(fishBtn, TaskTrackerDB.debugFishSpell == true, "Fishing: ON", "Fishing: OFF")
    end
    if refreshBtn then
        styleToggleBtn(refreshBtn, TaskTrackerDB.debugRefreshSource == true, "Refresh src: ON", "Refresh src: OFF")
    end
    if perfBtn then
        styleToggleBtn(perfBtn, TaskTrackerDB.debugPerf == true, "List perf: ON", "List perf: OFF")
    end
    local clBtn = panel._debugClBtn
    if clBtn then
        styleToggleBtn(clBtn, TaskTrackerDB.combatLogKillTracking == true, "Combat log: ON", "Combat log: OFF")
    end
    local previewBtn = panel._debugPreviewBtn
    if previewBtn then
        local active = TaskTracker.HiddenProfileIsLoaded and TaskTracker.HiddenProfileIsLoaded()
        local title = "Hidden profile"
        local sub = "This character opens a new install. Your profile is saved first. It is not in the profile list."
        if active then
            local back = TaskTracker.FreshInstallReturnLabel and TaskTracker.FreshInstallReturnLabel()
            title = "On the new install"
            sub = back and ("Switch back to " .. back .. ".") or "Switch back to your profile."
        end
        styleToggleBtn(previewBtn, active, "Switch back", "Open")
        if panel._debugPreviewTitle then
            panel._debugPreviewTitle:SetText(title)
        end
        if panel._debugPreviewSub then
            panel._debugPreviewSub:SetText(sub)
        end
    end
end

function TaskTracker.ToggleDebugPanel()
    local panel = TaskTracker.EnsureDebugPanel()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
        TaskTracker.RefreshDebugPanelIfShown()
    end
end
