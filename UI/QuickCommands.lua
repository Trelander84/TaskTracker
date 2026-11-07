-- UI/QuickCommands.lua
-- Horizontal flyout to the left of the list note icon: [x][run][run]… — same insecure macro
-- buttons as the note window, no title bar.

TaskTracker = TaskTracker or {}

local DEFAULT_ICON_FILE = 134400
-- Match list-row command icons (~80% of row height). Fallback if List.lua is not loaded.
local H_PAD             = 1
local V_PAD             = 1
local SLOT_GAP          = 2
local CLOSE_SZ          = 16

local function flyoutMacroBtnSize()
    if TaskTracker.GetListCommandIconSize then
        return TaskTracker.GetListCommandIconSize()
    end
    return 18
end

local trimCmd = TaskTracker.Trim

local function setFileIconTexture(tex, fileId, command)
    if TaskTracker.ApplyCommandIconToTexture then
        TaskTracker.ApplyCommandIconToTexture(tex, fileId, command)
        return
    end
    if not tex then return end
    local n = tonumber(fileId) or DEFAULT_ICON_FILE
    tex:SetTexture(n)
    tex:Show()
end

--- Count command slots with non-empty macro text (hot path: no table allocation).
function TaskTracker.CountRunnableCommandButtons(node)
    if not node or not node.commandButtons then return 0 end
    local n = 0
    for _, b in ipairs(node.commandButtons) do
        if b and trimCmd(b.command) ~= "" then
            n = n + 1
        end
    end
    return n
end

--- First runnable command: macro text, icon file id, label, runMode ("line" or nil).
function TaskTracker.GetFirstRunnableCommand(node)
    if not node or not node.commandButtons then return nil end
    for _, b in ipairs(node.commandButtons) do
        if b then
            local t = trimCmd(b.command)
            if t ~= "" then
                local lbl = b.label and trimCmd(tostring(b.label)) or ""
                local mode = b.runMode == "line" and "line" or nil
                return t, b.icon, lbl, mode
            end
        end
    end
end

function TaskTracker.SetCommandButtonFileIcon(btn, fileId, command)
    if not btn or not btn.icon then return end
    if TaskTracker.ApplyCommandIconToTexture then
        TaskTracker.ApplyCommandIconToTexture(btn.icon, fileId, command)
        return
    end
    if btn.SetIconAtlas then
        btn:SetIconAtlas(nil)
    end
    local n = tonumber(fileId) or DEFAULT_ICON_FILE
    btn.icon:SetTexture(n)
    btn.icon:Show()
end

--- Command slots on `node` that have non-empty macro text (same rows the note window can run).
function TaskTracker.GetRunnableCommandButtons(node)
    local out = {}
    if not node or not node.commandButtons then return out end
    for i, b in ipairs(node.commandButtons) do
        if b then
            local t = trimCmd(b.command)
            if t ~= "" then
                local lbl = b.label and trimCmd(tostring(b.label)) or ""
                local mode = b.runMode == "line" and "line" or nil
                out[#out + 1] = { slot = i, icon = b.icon, command = t, label = lbl, runMode = mode }
            end
        end
    end
    return out
end

local function ensureQuickCmdDismissLayer()
    if TaskTracker._quickCmdDismissLayer then
        return TaskTracker._quickCmdDismissLayer
    end
    -- Full-screen layer below the flyout: closes flyout on any click outside it, then propagates
    -- so the rest of the addon (and world) still receives the click.
    local d = CreateFrame("Frame", "TaskTrackerQuickCmdDismiss", UIParent)
    d:SetAllPoints()
    d:SetFrameStrata("DIALOG")
    d:SetFrameLevel(109)
    -- IMPORTANT: this is a fullscreen frame; keep mouse disabled unless the flyout is open.
    d:EnableMouse(false)
    if d.SetPropagateMouseClicks then
        pcall(function()
            d:SetPropagateMouseClicks(true)
        end)
    end
    -- Only use left-click to dismiss. Right-click is reserved for camera look in the 3D world and
    -- should never be intercepted by an invisible UI layer.
    d:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local fly = TaskTracker.quickCommandsFrame
        -- Flyout is above this layer; only skip the list opener so its click still toggles.
        local anchor = fly and fly._anchorBtn
        if anchor and anchor:IsShown() and MouseIsOver(anchor) then
            return
        end
        TaskTracker.HideQuickCommandsPanel()
    end)
    d:Hide()
    TaskTracker._quickCmdDismissLayer = d
    return d
end

function TaskTracker.EnsureQuickCommandsPanel()
    if TaskTracker.quickCommandsFrame then
        return TaskTracker.quickCommandsFrame
    end

    local host = CreateFrame("Frame", "TaskTrackerQuickCmdFlyout", UIParent)
    host:SetFrameStrata("DIALOG")
    host:SetFrameLevel(110)
    host:SetClampedToScreen(true)
    host:Hide()
    host:EnableMouse(true)

    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    TaskTracker.SetColor(bg, "headerBg")
    TaskTracker.MakeBorder(host, "border")
    TaskTracker.MakeEdge(host, "TOP", "accent", 1)

    local closeBtn = TaskTracker.MakeIconButton(host, CLOSE_SZ, CLOSE_SZ, TaskTracker.ChromeIconOpt())
    closeBtn:SetChromeIcon("close")
    closeBtn:SetScript("OnClick", function()
        TaskTracker.HideQuickCommandsPanel()
    end)

    host._cmdRunSlots = {}
    host.closeBtn    = closeBtn

    function host:AnchorNear(anchorBtn)
        if not anchorBtn or not anchorBtn.IsShown then return end
        self:ClearAllPoints()
        self:SetPoint("RIGHT", anchorBtn, "LEFT", -4, 0)
        self:SetPoint("TOP", anchorBtn, "TOP", 0, 0)
    end

    function host:Refresh(node)
        if not node then return end
        local cmds = TaskTracker.GetRunnableCommandButtons(node)
        if #cmds < 2 then
            TaskTracker.HideQuickCommandsPanel()
            return
        end

        local slots   = self._cmdRunSlots
        local closeB  = self.closeBtn
        local prev    = closeB
        local btnSize = flyoutMacroBtnSize()
        local closeSz = math.min(CLOSE_SZ, btnSize)

        closeB:SetSize(closeSz, closeSz)
        if TaskTracker.SizeIconButton then
            TaskTracker.SizeIconButton(closeB, closeSz, closeSz, TaskTracker.ChromeIconOpt())
        end
        closeB:ClearAllPoints()
        closeB:SetPoint("LEFT", self, "LEFT", H_PAD, 0)
        closeB:SetPoint("TOP", self, "TOP", 0, -V_PAD - (btnSize - closeSz) / 2)

        for i = 1, math.max(#slots, #cmds) do
            local slot = slots[i]
            if i > #cmds then
                if slot then slot:Hide() end
            else
                local c = cmds[i]
                if not slot then
                    slot = CreateFrame("Frame", nil, self)
                    slot:SetSize(btnSize, btnSize)
                    local nid = node.id or "x"
                    local runBtn = TaskTracker.MakeSecureMacroIconButton(slot, btnSize, btnSize, nid, (c.slot or i) + 900, {
                        secureNamespace = "quickcmd",
                        unnamedSecure     = true,
                        insecureMacro     = true,
                        iconFill          = true,
                        iconMargin        = 1,
                    })
                    runBtn:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
                    TaskTracker.SetSecureMacroButtonAttributes(runBtn, "")
                    slot.runBtn = runBtn
                    slots[i]  = slot
                else
                    slot:SetSize(btnSize, btnSize)
                    if TaskTracker.SizeIconButton then
                        TaskTracker.SizeIconButton(slot.runBtn, btnSize, btnSize, { iconFill = true, iconMargin = 1 })
                    elseif slot.runBtn then
                        slot.runBtn:SetSize(btnSize, btnSize)
                    end
                end
                slot:Show()
                setFileIconTexture(slot.runBtn.icon, c.icon, c.command)
                if TaskTracker.ApplyCommandRunMode then
                    TaskTracker.ApplyCommandRunMode(slot.runBtn, c.command, c.runMode)
                else
                    TaskTracker.SetSecureMacroButtonAttributes(slot.runBtn, c.command)
                end
                local runBtn = slot.runBtn
                runBtn._ttTipTitle = (c.label and c.label ~= "") and c.label or "Command"
                runBtn._ttTipBody = c.command or ""
                runBtn._ttTipRun = c.runMode == "line" and "Click to run each line (out of combat)." or "Click to run (out of combat)."
                runBtn:SetScript("OnEnter", function(self)
                    TaskTracker.BeginTooltipBesideList(self)
                    GameTooltip:SetText(self._ttTipTitle or "Command", 1, 1, 1)
                    if self._ttTipBody and self._ttTipBody ~= "" then
                        GameTooltip:AddLine(self._ttTipBody, 0.82, 0.82, 0.82, true)
                    end
                    if self._ttTipRun then
                        GameTooltip:AddLine(self._ttTipRun, 0.85, 0.85, 0.85, true)
                    end
                    TaskTracker.FinishTooltipBesideList()
                end)
                slot.runBtn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
                slot:ClearAllPoints()
                slot:SetPoint("LEFT", prev, "RIGHT", SLOT_GAP, 0)
                slot:SetPoint("TOP", self, "TOP", 0, -V_PAD)
                prev = slot
            end
        end

        local n      = #cmds
        local innerW = closeSz + n * btnSize + n * SLOT_GAP
        local w      = H_PAD * 2 + innerW
        local h      = btnSize + V_PAD * 2
        self:SetSize(w, h)
    end

    TaskTracker.quickCommandsFrame = host
    return host
end

function TaskTracker.HideQuickCommandsPanel()
    local d = TaskTracker._quickCmdDismissLayer
    if d then
        d:Hide()
        if d.EnableMouse then d:EnableMouse(false) end
    end
    local f = TaskTracker.quickCommandsFrame
    if not f or not f:IsShown() then return end
    f:Hide()
    f.boundNodeId = nil
    f._anchorBtn  = nil
end

function TaskTracker.ValidateQuickCommandsPanel()
    local f = TaskTracker.quickCommandsFrame
    if not f or not f:IsShown() or not f.boundNodeId then return end
    local node = TaskTracker.FindNode and TaskTracker.FindNode(f.boundNodeId)
    if not node or (node.type ~= "task" and node.type ~= "registryEntry") then
        TaskTracker.HideQuickCommandsPanel()
        return
    end
    f:Refresh(node)
    if not f:IsShown() then return end
    local anchor = f._anchorBtn
    if anchor and anchor.IsShown and anchor:IsShown() then
        f:AnchorNear(anchor)
    else
        TaskTracker.HideQuickCommandsPanel()
    end
end

function TaskTracker.ToggleQuickCommandsPanel(node, anchorBtn)
    if not node or not anchorBtn then return end
    if node.type ~= "task" and node.type ~= "registryEntry" then return end

    local f = TaskTracker.EnsureQuickCommandsPanel()
    -- Close first so a second click on the list command icon always dismisses (even if #cmds check would fail).
    if f:IsShown() and (f._anchorBtn == anchorBtn or f.boundNodeId == node.id) then
        TaskTracker.HideQuickCommandsPanel()
        return
    end

    if #TaskTracker.GetRunnableCommandButtons(node) < 2 then return end

    f.boundNodeId = node.id
    f._anchorBtn  = anchorBtn
    f:Refresh(node)
    f:AnchorNear(anchorBtn)
    local scrim = ensureQuickCmdDismissLayer()
    scrim:SetFrameStrata("DIALOG")
    scrim:SetFrameLevel(109)
    scrim:Show()
    if scrim.EnableMouse then scrim:EnableMouse(true) end
    f:SetToplevel(true)
    f:Show()
    f:Raise()
end

-- ─────────────────────────────────────
-- Peek window: command icons in a row along the bottom of the note box.
-- ─────────────────────────────────────

local PEEK_INLINE_BTN = 18
local PEEK_INLINE_GAP = 2

function TaskTracker.ApplyPeekCmdButtonAlpha(peekFrame)
    if not peekFrame then return end
    local hovered = peekFrame._peekHover == true
    local cmdOp = TaskTracker.GetNotePeekCmdOpacity and TaskTracker.GetNotePeekCmdOpacity(hovered) or 1
    -- × uses the same setting as command icons but never below 10% so it stays usable.
    local closeA = math.max(0.1, cmdOp)
    if peekFrame.peekCloseBtn then
        peekFrame.peekCloseBtn:SetAlpha(closeA)
    end
    if peekFrame.peekEditBtn then
        peekFrame.peekEditBtn:SetAlpha(closeA)
    end
    local rail = peekFrame.peekCmdRail
    if not rail or not rail._slots then return end
    for _, slot in ipairs(rail._slots) do
        if slot and slot:IsShown() and slot.runBtn then
            slot:SetAlpha(cmdOp)
        end
    end
end

function TaskTracker.RefreshPeekInlineCommands(peekFrame)
    if not peekFrame or not peekFrame.peekCmdRail then return end
    local rail = peekFrame.peekCmdRail
    if not rail._slots then
        rail._slots = {}
    end
    local slots = rail._slots

    local node = TaskTracker.FindNode and TaskTracker.FindNode(peekFrame.boundTaskId)
    local cmds = (node and TaskTracker.GetRunnableCommandButtons(node)) or {}

    if #cmds == 0 then
        for i = 1, #slots do
            if slots[i] then
                slots[i]:Hide()
            end
        end
        rail:Hide()
        return
    end

    rail:Show()
    local nid = (node and node.id) or "x"
    local prev

    for i = 1, math.max(#slots, #cmds) do
        local slot = slots[i]
        if i > #cmds then
            if slot then
                slot:Hide()
            end
        else
            local c = cmds[i]
            if not slot then
                slot = CreateFrame("Frame", nil, rail)
                slot:SetSize(PEEK_INLINE_BTN, PEEK_INLINE_BTN)
                local runBtn = TaskTracker.MakeSecureMacroIconButton(slot, PEEK_INLINE_BTN, PEEK_INLINE_BTN, nid, (c.slot or i) + 600, {
                    secureNamespace = "peekcmd",
                    unnamedSecure   = true,
                    insecureMacro   = true,
                    iconFill         = true,
                    iconMargin       = 1,
                })
                runBtn:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
                TaskTracker.SetSecureMacroButtonAttributes(runBtn, "")
                slot.runBtn = runBtn
                slots[i]  = slot
            end
            slot:Show()
            setFileIconTexture(slot.runBtn.icon, c.icon, c.command)
            if TaskTracker.ApplyCommandRunMode then
                TaskTracker.ApplyCommandRunMode(slot.runBtn, c.command, c.runMode)
            else
                TaskTracker.SetSecureMacroButtonAttributes(slot.runBtn, c.command)
            end
            local runBtn = slot.runBtn
            runBtn._ttTipTitle = (c.label and c.label ~= "") and c.label or "Command"
            runBtn._ttTipBody = c.command or ""
            runBtn._ttTipRun = c.runMode == "line" and "Click to run each line (out of combat)." or "Click to run (out of combat)."
            runBtn:SetScript("OnEnter", function(self)
                if peekFrame._setPeekHover then peekFrame._setPeekHover(true) end
                TaskTracker.BeginTooltipBesideList(self)
                GameTooltip:SetText(self._ttTipTitle or "Command", 1, 1, 1)
                if self._ttTipBody and self._ttTipBody ~= "" then
                    GameTooltip:AddLine(self._ttTipBody, 0.82, 0.82, 0.82, true)
                end
                if self._ttTipRun then
                    GameTooltip:AddLine(self._ttTipRun, 0.85, 0.85, 0.85, true)
                end
                TaskTracker.FinishTooltipBesideList()
            end)
            slot.runBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
                if peekFrame._queuePeekHover then peekFrame._queuePeekHover() end
            end)

            slot:ClearAllPoints()
            if not prev then
                slot:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 2, 2)
            else
                slot:SetPoint("LEFT", prev, "RIGHT", PEEK_INLINE_GAP, 0)
            end
            prev = slot
        end
    end

    local n = #cmds
    local w = 4 + n * PEEK_INLINE_BTN + math.max(0, n - 1) * PEEK_INLINE_GAP
    rail:SetSize(math.max(22, w), PEEK_INLINE_BTN + 4)
    TaskTracker.ApplyPeekCmdButtonAlpha(peekFrame)
end

function TaskTracker.RefreshPeekInlineCommandsIfShown()
    local list = TaskTracker.notePeekWindows
    if not list then
        local pk = TaskTracker.notePeekWindow
        if pk and pk:IsShown() and pk._requestPeekLayout then
            pk._requestPeekLayout()
        end
        return
    end
    for i = 1, #list do
        local pk = list[i]
        if pk and pk:IsShown() and pk._requestPeekLayout then
            pk._requestPeekLayout()
        end
    end
end
