-- UI/LiveShare.lua
-- Sync window: send one task to a character on another account.

TaskTracker = TaskTracker or {}

function TaskTracker.OpenLiveShareDialog(node)
    if not node or node.type ~= "task" then return end
    TaskTracker.EnsureLiveShareDialog()
    local f = TaskTracker._liveShareDialog
    f._nodeId = node.id
    f:ClearAllPoints()
    if TaskTracker.AnchorFrameNearScreenTop then
        TaskTracker.AnchorFrameNearScreenTop(f, 0, 0.12)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    f:Show()
    f:Raise()
    if f.Refresh then f:Refresh() end
end

function TaskTracker.EnsureLiveShareDialog()
    local existing = TaskTracker._liveShareDialog
    if existing then return existing end

    local dialog = TaskTracker.MakePanel("TaskTrackerLiveShareDialog", UIParent, 360, 292)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(280)
    dialog:Hide()
    dialog:SetClampedToScreen(true)
    dialog.TitleText:SetText("Sync")

    local content = dialog.Content
    local t = TaskTracker.GetTheme()

    local hint = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -10)
    hint:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, -10)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    hint:SetWordWrap(true)
    hint:SetText("Type their character name and server. Both of you need to be online for a send to land. They can move the task. The count follows yours, unless you let them add to it.")
    TaskTracker.SetTextColor(hint, "textSecondary")

    local nameLbl = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    nameLbl:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
    nameLbl:SetText("Character")
    TaskTracker.SetTextColor(nameLbl, "textSecondary")

    local nameBox = TaskTracker.MakeEditBox(content, "TaskTrackerLiveShareName", 160, 22)
    nameBox:SetPoint("TOPLEFT", nameLbl, "BOTTOMLEFT", 0, -4)
    nameBox:SetMaxLetters(24)

    local realmLbl = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    realmLbl:SetPoint("TOPLEFT", nameBox, "TOPRIGHT", 12, 18)
    realmLbl:SetText("Server")
    TaskTracker.SetTextColor(realmLbl, "textSecondary")

    local realmBox = TaskTracker.MakeEditBox(content, "TaskTrackerLiveShareRealm", 150, 22)
    realmBox:SetPoint("TOPLEFT", nameBox, "TOPRIGHT", 12, 0)
    realmBox:SetMaxLetters(48)

    local status = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    status:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -10)
    status:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, 0)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")
    status:SetWordWrap(true)
    status:SetHeight(36)

    local twoWayBtn = TaskTracker.MakeQuietToggle(content, "They can add to the count")
    twoWayBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 12, 44)
    twoWayBtn:SetWidth(336)
    TaskTracker.SetTextColor(status, "textSecondary")

    local sendBtn = TaskTracker.MakeButton(content, "Send", 80, 24)
    sendBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 12, 12)

    local stopBtn = TaskTracker.MakeButton(content, "Stop sharing", 120, 24)
    stopBtn:SetPoint("LEFT", sendBtn, "RIGHT", 8, 0)

    local closeBtn = TaskTracker.MakeButton(content, "Close", 80, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -12, 12)
    closeBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)

    local function setStatus(text, danger)
        status:SetText(text or "")
        TaskTracker.SetTextColor(status, danger and "danger" or "textSecondary")
    end

    local function currentNode()
        if not dialog._nodeId or not TaskTracker.FindNode then return nil end
        return TaskTracker.FindNode(dialog._nodeId)
    end

    local function whoLine(info)
        local name = info.name or ""
        local realm = info.realm or ""
        if name ~= "" and realm ~= "" then
            return name .. " on " .. realm
        end
        if info.who and info.who ~= "" then return info.who end
        return "them"
    end

    function dialog:Refresh()
        local node = currentNode()
        if node and TaskTracker.ProjectLiveShareNode then
            TaskTracker.ProjectLiveShareNode(node)
        end
        local info = TaskTracker.LiveShareStatus and TaskTracker.LiveShareStatus(node) or { mode = "none" }
        if info.mode == "receiver" then
            nameBox:SetText(info.name or "")
            realmBox:SetText(info.realm or "")
            nameBox:EnableKeyboard(false)
            realmBox:EnableKeyboard(false)
            sendBtn:Hide()
            stopBtn:Hide()
            twoWayBtn:Hide()
            if info.twoWay then
                setStatus("This count is shared with " .. whoLine(info) .. ". You can add to it, and that syncs back. You can't lower it.", false)
            else
                setStatus("This count follows " .. whoLine(info) .. ". You can move the task. You can't change the count.", false)
            end
            return
        end
        nameBox:EnableKeyboard(true)
        realmBox:EnableKeyboard(true)
        sendBtn:Show()
        twoWayBtn:Show()
        twoWayBtn:SetOn(info.twoWay and true or false)
        if info.mode == "owner" then
            nameBox:SetText(info.name or "")
            realmBox:SetText(info.realm or "")
            stopBtn:Show()
            local charStatus = TaskTracker.LiveShareCharStatus and TaskTracker.LiveShareCharStatus(node)
            if type(charStatus) == "string" and charStatus ~= "" then
                setStatus(charStatus, false)
            elseif info.twoWay then
                setStatus("Shared with " .. whoLine(info) .. ". They can add to the count, and it syncs back to you.", false)
            else
                setStatus("Shared with " .. whoLine(info) .. ". They get updates while you're both online.", false)
            end
        else
            nameBox:SetText("")
            realmBox:SetText("")
            stopBtn:Hide()
            twoWayBtn:SetOn(node and node.liveShareTwoWay == true)
            if node and TaskTracker.LiveShareHasOtherCharShares and TaskTracker.LiveShareHasOtherCharShares(node) then
                setStatus("This sends your count. Other characters on this account send their own.", false)
            else
                setStatus("", false)
            end
        end
    end

    twoWayBtn:SetScript("OnClick", function()
        local node = currentNode()
        if not node or node.liveShareRole == "receiver" then return end
        if node.liveShareTwoWay == true then
            node.liveShareTwoWay = nil
        else
            node.liveShareTwoWay = true
        end
        if node.liveShareRole == "owner" and TaskTracker.SendLiveShareTask then
            local err = TaskTracker.SendLiveShareTask(node)
            if type(err) == "string" and err ~= "" then
                setStatus(err, true)
                dialog:Refresh()
                return
            end
        end
        dialog:Refresh()
    end)

    sendBtn:SetScript("OnClick", function()
        local node = currentNode()
        if not node or not TaskTracker.BeginLiveShare then return end
        local err = TaskTracker.BeginLiveShare(node, nameBox:GetText(), realmBox:GetText())
        if err then
            setStatus(err, true)
            return
        end
        dialog:Refresh()
    end)

    stopBtn:SetScript("OnClick", function()
        local node = currentNode()
        if not node or not TaskTracker.StopLiveShare then return end
        TaskTracker.StopLiveShare(node)
        nameBox:SetText("")
        realmBox:SetText("")
        dialog:Refresh()
        setStatus("Stopped sharing. It was removed from their list.", false)
    end)

    nameBox:SetScript("OnTabPressed", function()
        realmBox:SetFocus()
    end)
    realmBox:SetScript("OnTabPressed", function()
        nameBox:SetFocus()
    end)
    nameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        realmBox:SetFocus()
    end)
    realmBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        sendBtn:Click()
    end)

    dialog:SetScript("OnShow", function(self)
        if self.Refresh then self:Refresh() end
        local info = TaskTracker.LiveShareStatus and TaskTracker.LiveShareStatus(currentNode()) or { mode = "none" }
        if info.mode ~= "receiver" then
            nameBox:SetFocus()
        end
    end)

    TaskTracker._liveShareDialog = dialog
    return dialog
end

local function formatReceivedAt(ts)
    ts = tonumber(ts)
    if not ts or ts <= 0 then return "Not recorded" end
    if date then
        return date("%b %d, %Y %H:%M", ts)
    end
    return tostring(ts)
end

local function receivedWho(node)
    local info = TaskTracker.LiveShareStatus and TaskTracker.LiveShareStatus(node) or {}
    local name = info.name or ""
    local realm = info.realm or ""
    if name ~= "" and realm ~= "" then
        return name .. " on " .. realm
    end
    if name ~= "" then return name end
    if type(node.liveShareOwner) == "string" and node.liveShareOwner ~= "" then
        return node.liveShareOwner
    end
    return "Unknown"
end

function TaskTracker.OpenReceivedTaskDialog(node)
    if not node or node.type ~= "task" or node.liveShareRole ~= "receiver" then return end
    TaskTracker.EnsureReceivedTaskDialog()
    local f = TaskTracker._receivedTaskDialog
    f._nodeId = node.id
    f:ClearAllPoints()
    if TaskTracker.AnchorFrameNearScreenTop then
        TaskTracker.AnchorFrameNearScreenTop(f, 0, 0.12)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    f:Show()
    f:Raise()
    if f.Refresh then f:Refresh() end
end

function TaskTracker.EnsureReceivedTaskDialog()
    local existing = TaskTracker._receivedTaskDialog
    if existing then return existing end

    local dialog = TaskTracker.MakePanel("TaskTrackerReceivedTaskDialog", UIParent, 340, 176)
    dialog:SetFrameStrata("DIALOG")
    dialog:Hide()
    dialog:SetClampedToScreen(true)
    dialog.TitleText:ClearAllPoints()
    dialog.TitleText:SetPoint("LEFT", dialog.titleBar, "LEFT", 8, 0)
    dialog.TitleText:SetWidth(290)
    dialog.TitleText:SetJustifyH("LEFT")
    if dialog.TitleText.SetWordWrap then dialog.TitleText:SetWordWrap(false) end

    local content = dialog.Content
    local t = TaskTracker.GetTheme()

    local fromLbl = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    fromLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -12)
    fromLbl:SetText("From")
    TaskTracker.SetTextColor(fromLbl, "textSecondary")

    local fromVal = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontNormal or "GameFontNormal")
    fromVal:SetPoint("TOPLEFT", fromLbl, "BOTTOMLEFT", 0, -2)
    fromVal:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    fromVal:SetJustifyH("LEFT")
    fromVal:SetWordWrap(false)
    TaskTracker.SetTextColor(fromVal, "textPrimary")

    local whenLbl = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    whenLbl:SetPoint("TOPLEFT", fromVal, "BOTTOMLEFT", 0, -12)
    whenLbl:SetText("Received")
    TaskTracker.SetTextColor(whenLbl, "textSecondary")

    local whenVal = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontNormal or "GameFontNormal")
    whenVal:SetPoint("TOPLEFT", whenLbl, "BOTTOMLEFT", 0, -2)
    whenVal:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    whenVal:SetJustifyH("LEFT")
    whenVal:SetWordWrap(false)
    TaskTracker.SetTextColor(whenVal, "textPrimary")

    local deleteBtn = TaskTracker.MakeButton(content, "Delete", 80, 22)
    deleteBtn:SetPoint("BOTTOM", content, "BOTTOM", 0, 12)
    TaskTracker.SetColor(deleteBtn.bg, "danger")
    TaskTracker.SetTextColor(deleteBtn.label, "textPrimary")
    deleteBtn:SetScript("OnEnter", nil)
    deleteBtn:SetScript("OnLeave", nil)

    local function currentNode()
        if not dialog._nodeId or not TaskTracker.FindNode then return nil end
        return TaskTracker.FindNode(dialog._nodeId)
    end

    function dialog:Refresh()
        local node = currentNode()
        if not node or node.liveShareRole ~= "receiver" then
            dialog:Hide()
            return
        end
        dialog.TitleText:SetText(node.name or "Synced task")
        fromVal:SetText(receivedWho(node))
        whenVal:SetText(formatReceivedAt(node.liveShareReceivedAt))
    end

    deleteBtn:SetScript("OnClick", function()
        local node = currentNode()
        if not node then
            dialog:Hide()
            return
        end
        local title = node.name or "task"
        StaticPopupDialogs["TASKTRACKER_DEL_TASK"] = {
            text    = "Delete task '" .. title .. "'?",
            button1 = "Delete",
            button2 = "Cancel",
            OnAccept = function()
                if TaskTracker.RemoveNode then
                    TaskTracker.RemoveNode(node.id)
                end
                dialog:Hide()
                if TaskTracker.RefreshList then TaskTracker.RefreshList() end
            end,
            timeout       = 0,
            whileDead     = true,
            hideOnEscape  = true,
        }
        local popup = StaticPopup_Show("TASKTRACKER_DEL_TASK")
        if popup then popup:Raise() end
    end)

    dialog:SetScript("OnShow", function(self)
        if self.Refresh then self:Refresh() end
    end)

    TaskTracker._receivedTaskDialog = dialog
    return dialog
end
