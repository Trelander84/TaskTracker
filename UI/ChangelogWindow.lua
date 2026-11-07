-- Changelog window opened from the version number on Options.

TaskTracker = TaskTracker or {}

local FOOTER_H = 18

local function addonVersionText()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, v = pcall(C_AddOns.GetAddOnMetadata, "TaskTracker", "Version")
        if ok and type(v) == "string" and v ~= "" then return v end
    end
    if GetAddOnMetadata then
        local v = GetAddOnMetadata("TaskTracker", "Version")
        if type(v) == "string" and v ~= "" then return v end
    end
    local notes = TaskTracker.WHATS_NEW
    local first = notes and notes[1]
    return (first and first.version) or ""
end

local function changelogLine(text)
    -- The game font has no glyph for →, so a raw arrow draws as an empty box.
    -- Use the help arrow (CovenantSanctum-Renown-DoubleArrow-Depressed, flipped right).
    if TaskTracker.WithPathArrows then
        return TaskTracker.WithPathArrows(text or "", 12)
    end
    return text or ""
end

local function plainChangelog(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("%*%*", ""))
end

local PAD_L = 16
local MARK_W = 14
local NEST = 18

local function parseChangelog(text)
    local rows = {}
    text = plainChangelog(text or "")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local trimmed = line:match("^%s*(.-)%s*$") or ""
        if trimmed ~= "" then
            local spaces, body = line:match("^(%s*)•%s*(.*)$")
            if body then
                local level = (spaces and #spaces >= 2) and 1 or 0
                rows[#rows + 1] = { kind = "bullet", level = level, text = body }
            elseif trimmed == "New features" or trimmed == "Adjusted features" or trimmed == "Bug fixes" then
                rows[#rows + 1] = { kind = "section", text = trimmed }
            else
                rows[#rows + 1] = { kind = "feature", text = trimmed }
            end
        end
    end
    return rows
end

local function takeRow(win, child, font)
    win.rowCount = (win.rowCount or 0) + 1
    local row = win.rows[win.rowCount]
    if not row then
        row = {}
        row.mark = TaskTracker.CreateFontString(child, nil, "OVERLAY", font)
        row.mark:SetJustifyH("LEFT")
        row.mark:SetJustifyV("TOP")
        row.text = TaskTracker.CreateFontString(child, nil, "OVERLAY", font)
        row.text:SetJustifyH("LEFT")
        row.text:SetJustifyV("TOP")
        if row.text.SetWordWrap then row.text:SetWordWrap(true) end
        if row.text.SetIndentedWordWrap then row.text:SetIndentedWordWrap(true) end
        win.rows[win.rowCount] = row
    end
    row.mark:Show()
    row.text:Show()
    return row
end

local function layoutChangelog(win)
    local notes = TaskTracker.WHATS_NEW or {}
    local child = win.scrollChild
    local scroll = win.scrollFrame
    local theme = TaskTracker.GetTheme and TaskTracker.GetTheme() or {}
    local bodyFont = theme.fontNormal or "GameFontNormalSmall"
    local headFont = theme.fontBold or "GameFontNormal"
    local viewW = scroll:GetWidth() or 0
    if viewW < 40 and win.Content then
        viewW = (win.Content:GetWidth() or 0) - 16
    end
    viewW = math.max(220, viewW)
    child:SetWidth(viewW)
    local textRight = math.max(160, viewW - 8)
    win.rows = win.rows or {}
    win.rowCount = 0
    local y = 8
    for i = 1, #notes do
        local note = notes[i]
        local head = takeRow(win, child, headFont)
        head.mark:Hide()
        head.text:SetFontObject(headFont)
        head.text:ClearAllPoints()
        head.text:SetPoint("TOPLEFT", child, "TOPLEFT", PAD_L, -y)
        head.text:SetWidth(textRight - PAD_L)
        head.text:SetText(note.version or "")
        TaskTracker.SetTextColor(head.text, "textAccent")
        y = y + math.max(16, head.text:GetStringHeight() or 0) + 6
        local parsed = parseChangelog(note.text)
        for r = 1, #parsed do
            local item = parsed[r]
            if item.kind == "section" then
                if r > 1 then
                    y = y + 8
                end
                local sec = takeRow(win, child, headFont)
                sec.mark:Hide()
                sec.text:SetFontObject(headFont)
                sec.text:ClearAllPoints()
                sec.text:SetPoint("TOPLEFT", child, "TOPLEFT", PAD_L, -y)
                sec.text:SetWidth(textRight - PAD_L)
                sec.text:SetText(changelogLine(item.text))
                TaskTracker.SetTextColor(sec.text, "textSecondary")
                y = y + math.max(14, sec.text:GetStringHeight() or 0) + 4
            elseif item.kind == "feature" then
                if r > 1 then
                    y = y + 6
                end
                local feat = takeRow(win, child, headFont)
                feat.mark:Hide()
                feat.text:SetFontObject(headFont)
                feat.text:ClearAllPoints()
                feat.text:SetPoint("TOPLEFT", child, "TOPLEFT", PAD_L, -y)
                feat.text:SetWidth(textRight - PAD_L)
                feat.text:SetText(changelogLine(item.text))
                TaskTracker.SetTextColor(feat.text, "textPrimary")
                y = y + math.max(14, feat.text:GetStringHeight() or 0) + 2
            else
                local level = item.level or 0
                local x = PAD_L + level * NEST
                local row = takeRow(win, child, bodyFont)
                row.mark:SetFontObject(bodyFont)
                row.mark:ClearAllPoints()
                row.mark:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
                row.mark:SetText("-")
                TaskTracker.SetTextColor(row.mark, "textSecondary")
                local textX = x + MARK_W
                row.text:SetFontObject(bodyFont)
                row.text:ClearAllPoints()
                row.text:SetPoint("TOPLEFT", child, "TOPLEFT", textX, -y)
                row.text:SetWidth(math.max(80, textRight - textX))
                row.text:SetText(changelogLine(item.text or ""))
                TaskTracker.SetTextColor(row.text, "textPrimary")
                y = y + math.max(14, row.text:GetStringHeight() or 0) + 4
            end
        end
        y = y + 12
    end
    for i = win.rowCount + 1, #win.rows do
        win.rows[i].mark:Hide()
        win.rows[i].text:Hide()
    end
    child:SetHeight(math.max(20, y))
    win._layoutW = viewW
    if scroll.UpdateScrollChildRect then
        scroll:UpdateScrollChildRect()
    end
    if scroll.UpdateScrollBar then
        scroll:UpdateScrollBar()
    end
end

local function revealChangelog(win)
    layoutChangelog(win)
    local scroll = win.scrollFrame
    local child = win.scrollChild
    if scroll and child then
        scroll:SetScrollChild(child)
        if scroll.UpdateScrollChildRect then
            scroll:UpdateScrollChildRect()
        end
        scroll:SetVerticalScroll(0)
    end
    win._painted = true
end

local function markChangelogSeen()
    if not TaskTrackerDB then return end
    TaskTrackerDB.changelogSeen = addonVersionText()
    if TaskTracker.RefreshChangelogDot then
        TaskTracker.RefreshChangelogDot()
    end
end

function TaskTracker.ToggleChangelogWindow()
    local win = TaskTracker.changelogWindow
    if win and win:IsShown() then
        win:Hide()
        return
    end
    if not win then
        win = TaskTracker.MakePanel("TaskTrackerChangelog", UIParent, 560, 520)
        win:EnableMouse(true)
        if win.SetPropagateMouseClicks then
            win:SetPropagateMouseClicks(false)
        end
        if win.Content then
            win.Content:EnableMouse(true)
        end
        win:SetFrameStrata("DIALOG")
        win:SetFrameLevel(280)
        win:SetClampedToScreen(true)
        if TaskTracker.AnchorFrameNearScreenTop then
            TaskTracker.AnchorFrameNearScreenTop(win, 36, 0.08)
        else
            win:SetPoint("CENTER", UIParent, "CENTER", 40, 40)
        end
        win.TitleText:SetText("Changelog")
        win.CloseButton:SetScript("OnClick", function() win:Hide() end)
        local name = win:GetName()
        if name then
            tinsert(UISpecialFrames, name)
        end
        local _, scroll, child = TaskTracker.MakeScrollPane(win.Content, { useParent = true, pane = false, left = 4, right = 4, top = 6, bottom = 8 })
        scroll:EnableMouse(true)
        win.scrollFrame = scroll
        win.scrollChild = child
        win:SetScript("OnShow", function(self)
            C_Timer.After(0, function()
                if self:IsShown() then
                    revealChangelog(self)
                end
            end)
        end)
        scroll:HookScript("OnSizeChanged", function(self)
            if not win._painted or not win:IsShown() then return end
            local w = self:GetWidth() or 0
            if w < 40 then return end
            if win._layoutW and math.abs(w - win._layoutW) < 2 then return end
            layoutChangelog(win)
        end)
        win:SetAlpha(1)
        TaskTracker.changelogWindow = win
    end
    win:SetAlpha(1)
    if not win._booted then
        win._booted = true
        revealChangelog(win)
    end
    win:Show()
    markChangelogSeen()
end

function TaskTracker.ChangelogUnseen()
    local ver = addonVersionText()
    if ver == "" then return false end
    local seen = TaskTrackerDB and TaskTrackerDB.changelogSeen
    return seen ~= ver
end

function TaskTracker.RefreshChangelogDot()
    local dots = TaskTracker._changelogDots
    if not dots then return end
    local show = TaskTracker.ChangelogUnseen()
    for i = #dots, 1, -1 do
        local dot = dots[i]
        if not dot or not dot.SetShown then
            table.remove(dots, i)
        else
            dot:SetShown(show)
        end
    end
end

function TaskTracker.AttachOptionsVersion(opts)
    if not opts or not opts.Content then return end
    local titleH = 28
    if TaskTracker.GetTheme then
        local t = TaskTracker.GetTheme()
        titleH = (t and t.titleHeight) or 28
    end
    opts.Content:ClearAllPoints()
    opts.Content:SetPoint("TOPLEFT", opts, "TOPLEFT", 1, -titleH)
    opts.Content:SetPoint("BOTTOMRIGHT", opts, "BOTTOMRIGHT", -1, FOOTER_H)

    local btn = CreateFrame("Button", nil, opts)
    btn:SetHeight(14)
    btn:SetPoint("BOTTOMLEFT", opts, "BOTTOMLEFT", 10, 3)
    btn:SetFrameLevel(opts:GetFrameLevel() + 30)
    local font = "GameFontNormalSmall"
    if TaskTracker.GetTheme then
        local t = TaskTracker.GetTheme()
        font = (t and t.fontNormal) or font
    end
    local label = TaskTracker.CreateFontString(btn, nil, "OVERLAY", font)
    label:SetPoint("LEFT", btn, "LEFT", 0, 0)
    label:SetJustifyH("LEFT")
    TaskTracker.SetTextColor(label, "textSecondary")
    local ver = addonVersionText()
    label:SetText(ver)
    local textW = label:GetStringWidth() or 0
    if textW < 8 then
        textW = #ver * 7
    end
    local dot = TaskTracker.CreateFontString(btn, nil, "OVERLAY", font)
    dot:SetPoint("LEFT", label, "RIGHT", 3, 0)
    dot:SetText("•")
    dot:SetTextColor(0.95, 0.2, 0.16, 1)
    dot:SetShown(TaskTracker.ChangelogUnseen())
    TaskTracker._changelogDots = TaskTracker._changelogDots or {}
    TaskTracker._changelogDots[#TaskTracker._changelogDots + 1] = dot
    btn:SetWidth(textW + 16)
    btn:SetScript("OnEnter", function()
        TaskTracker.SetTextColor(label, "textAccent")
    end)
    btn:SetScript("OnLeave", function()
        TaskTracker.SetTextColor(label, "textSecondary")
    end)
    btn:SetScript("OnClick", function()
        TaskTracker.ToggleChangelogWindow()
    end)
end
