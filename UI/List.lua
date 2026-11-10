-- UI/List.lua
-- Recursive tree renderer using theme system

TaskTracker = TaskTracker or {}

local BASE_CAT_HEIGHT    = 26
local BASE_ROW_HEIGHT    = 22
local BASE_INSERT_HEIGHT = 10
local function automationCheckGap()
    if TaskTracker.GetCheckGap then return TaskTracker.GetCheckGap() end
    return 4
end

local NOTE_ROW_ICON = "note"
-- Command flyout (left of note). Opens to the left.
local CMD_FLYOUT_ICON = "arrow"
-- Same glyph as the title bar Edit mode button (UI/MainPanel.lua).
local ROW_EDIT_ICON = "edit"

--- Abundance's shard line turns green at 6. A task second line the player added keeps the normal color.
local function abundanceSubtitleColor(node, subtitle)
    if not node or node.collectionFarmId ~= "s1_weekly_abundance" or not TaskTracker.AbundanceShardLine then
        return "textSecondary"
    end
    local text, ready = TaskTracker.AbundanceShardLine()
    if subtitle ~= text then return "textSecondary" end
    return ready and "complete" or "textSecondary"
end

local function taskProgressText(node, progDone, progMax)
    if TaskTracker.FormatTaskGoalSummary then
        local summary = TaskTracker.FormatTaskGoalSummary(node)
        if summary then return summary end
    end
    if TaskTracker.FormatAdvancedCountDisplay and TaskTracker.IsAdvancedTask(node) then
        return TaskTracker.FormatAdvancedCountDisplay(node, progDone, progMax)
    end
    return TaskTracker.CountText(progDone, progMax)
end

--- Square, borderless edit glyphs. A tall boxed button sat on the second line and stretched the X.
local function editChromeSize(lineH)
    local h = tonumber(lineH) or BASE_ROW_HEIGHT
    local sz = 16
    if h < 22 then
        sz = math.max(12, h - 6)
    end
    return sz
end

local function sizeEditChrome(btn, size)
    if not btn or not size then return end
    if TaskTracker.SizeIconButton then
        TaskTracker.SizeIconButton(btn, size, size, TaskTracker.ChromeIconOpt())
    else
        btn:SetSize(size, size)
    end
end

local function makeBareEditButton(parent, size)
    local btn = TaskTracker.MakeIconButton(parent, size, size, TaskTracker.ChromeIconOpt())
    btn:SetFrameLevel(20)
    return btn
end

local function makeEqualsButton(parent, size)
    local btn = makeBareEditButton(parent, size)
    if btn.icon then btn.icon:Hide() end
    if btn.label then
        btn.label:SetText("=")
        btn.label:SetJustifyH("CENTER")
        btn.label:SetJustifyV("MIDDLE")
        TaskTracker.SetTextColor(btn.label, "textPrimary")
        btn.label:Show()
    end
    return btn
end

local function makeHammerButton(parent, size)
    local btn = makeBareEditButton(parent, size)
    btn:SetChromeIcon(ROW_EDIT_ICON)
    return btn
end

--- `y` is the same center offset as the title (placeListLine). A TOP anchor
--- sat the icons on a different line than the name.
local function anchorGlyphOnTitleLine(btn, row, y, x)
    if not btn then return end
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", row, "RIGHT", x, y or 0)
end

local function pinFontWidth(fs)
    if not fs then return end
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    -- A just-shown font string often reports 0. Writing that back collapses the
    -- count, the next refresh expands it, and the title and icons shift forever.
    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or 0
    if not w or w < 2 then
        w = fs.GetStringWidth and fs:GetStringWidth() or 0
    end
    if not w or w < 2 then return end
    w = math.ceil(w)
    if fs._ttPinW == w then return end
    fs._ttPinW = w
    fs:SetWidth(w)
end

local function placeEditTaskChrome(row, baseRh, y)
    if not row then return end
    local sz = editChromeSize(baseRh)
    local pad = TaskTracker.GetListPadRight()
    local pick = row._ttPickBtn
    local edit = row._ttEditBtn
    if pick then
        sizeEditChrome(pick, sz)
        anchorGlyphOnTitleLine(pick, row, y, -pad)
    end
    if edit then
        sizeEditChrome(edit, sz)
        anchorGlyphOnTitleLine(edit, row, y, -(pad + sz + 4))
    end
    pinFontWidth(row._ttProgStr)
end

--- Truncate mode sets max lines to 1. That cap sticks on reused rows and blocks wrapping.
local function enableListWrap(fs)
    if not fs then return end
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    if fs.SetMaxLines then fs:SetMaxLines(0) end
end

local function noteTextTrimmedEmpty(node)
    local s = node and node.note
    if s == nil or s == "" then return true end
    return (tostring(s):match("^%s*(.-)%s*$") or "") == ""
end

--- Hide the list note icon unless the row has note text, or Settings is set to always show it.
--- Edit mode uses the same rule. Notes are opened from the task window.
local function shouldShowRowNoteIcon(node)
    if node and node.generatedTask then return false end
    if TaskTrackerDB and TaskTrackerDB.alwaysShowNoteIcon then return true end
    return not noteTextTrimmedEmpty(node)
end

local function hereColorOn()
    if TaskTracker.ZoneHereUsesColor then
        return TaskTracker.ZoneHereUsesColor()
    end
    return true
end

local function hereFillInsteadOfLine()
    return hereColorOn() and not (TaskTracker.ZoneHereUsesUnderline and TaskTracker.ZoneHereUsesUnderline())
end

local function ListGroupHeaderBgKey(node, level)
    if hereFillInsteadOfLine() and node and TaskTracker.IsHereZoneNode and TaskTracker.IsHereZoneNode(node) then
        return "headerBgHere"
    end
    if node and node.headerBgKey then
        return node.headerBgKey
    end
    local key = node and node.moduleGroupKey
    if type(key) == "string" and key:find("collections", 1, true) then
        return "headerBg3"
    end
    return (level == 0) and "headerBg" or "headerBg2"
end

local function RowStripeKey(node, index)
    if hereFillInsteadOfLine() and node and TaskTracker.IsHereZoneNode and TaskTracker.IsHereZoneNode(node) then
        return "headerBgHere"
    end
    return (index % 2 == 0) and "rowEven" or "rowOdd"
end

local function applyHereFade(frame, node)
    if not frame then return end
    local show = hereColorOn() and node and TaskTracker.IsHereZoneNode and TaskTracker.IsHereZoneNode(node)
        and not hereFillInsteadOfLine()
    local fade = frame._ttHereFade
    if not show then
        if fade then fade:Hide() end
        return
    end
    if not fade then
        fade = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        frame._ttHereFade = fade
    end
    local w = frame:GetWidth() or 0
    if w < 8 then w = 8 end
    fade:ClearAllPoints()
    fade:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    fade:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    fade:SetWidth(math.max(16, math.floor(w * 0.30 + 0.5)))
    local c = (TaskTracker.GetTheme and TaskTracker.GetTheme() or {}).headerBgHere or { 1, 1, 1, 1 }
    fade:SetColorTexture(1, 1, 1, 1)
    if fade.SetGradient and CreateColor then
        fade:SetGradient("HORIZONTAL",
            CreateColor(c[1] or 1, c[2] or 1, c[3] or 1, 0),
            CreateColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1))
    end
    fade:Show()
end

local function applyRowStripe(row, index, node)
    if row and row._ttBg then
        TaskTracker.SetColor(row._ttBg, RowStripeKey(node or row._ttNode, index))
    end
    applyHereFade(row, node or (row and row._ttNode))
end

local function questInLog(qid)
    if not C_QuestLog or not C_QuestLog.GetLogIndexForQuestID then return false end
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, qid)
    return ok and type(idx) == "number" and idx > 0
end

local function questReadyForTurnIn(qid)
    if not C_QuestLog or not C_QuestLog.ReadyForTurnIn then return false end
    local ok, ready = pcall(C_QuestLog.ReadyForTurnIn, qid)
    return ok and ready == true
end

local function questFlaggedComplete(qid)
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return false end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
    return ok and done == true
end

local function questStateAtlasForQuestIds(ids)
    local anyNotPickedUp, anyInLog, anyTurnIn = false, false, false
    for _, qid in ipairs(ids or {}) do
        qid = tonumber(qid)
        if qid and qid > 0 and not questFlaggedComplete(qid) then
            if questReadyForTurnIn(qid) then
                anyTurnIn = true
            elseif questInLog(qid) then
                anyInLog = true
            else
                anyNotPickedUp = true
            end
        end
    end
    if anyTurnIn then
        return "Quest-Campaign-TurnIn"
    elseif anyInLog then
        return "Quest-Campaign-Available"
    elseif anyNotPickedUp then
        return "Quest-Campaign-Available-Trivial"
    end
    return nil
end

local QUEST_STATE_TTL = 0.75
local function CachedQuestStateAtlas(key, computeFn)
    if not key then return computeFn and computeFn() or nil end
    local now = (GetTime and GetTime()) or 0
    TaskTracker._ttQuestStateAtlasCache = TaskTracker._ttQuestStateAtlasCache or {}
    local slot = TaskTracker._ttQuestStateAtlasCache[key]
    if slot and (now - (slot.t or 0)) <= QUEST_STATE_TTL then
        return slot.v
    end
    local v = computeFn and computeFn() or nil
    TaskTracker._ttQuestStateAtlasCache[key] = { v = v, t = now }
    return v
end

--- First model row whose bottom is at or below yMin (rows are stored in y order).
local function listModelFirstVisibleIndex(model, yMin)
    local lo, hi = 1, #model
    local ans = #model + 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local r = model[mid]
        if (r.y + r.h) >= yMin then
            ans = mid
            hi = mid - 1
        else
            lo = mid + 1
        end
    end
    return ans
end

local ShowBesideTip

local NOTE_BTN_TIP = "Click to open notes and edit slash commands. Shift-click opens the popout."

local function openListNote(node, button)
    if not node then return end
    if TaskTracker.RunRowShortcut and TaskTracker.RunRowShortcut("notes", node, button) then
        return
    end
    if TaskTracker.OpenNoteWindow then
        TaskTracker.OpenNoteWindow(node)
    end
end

local function noteButtonTip()
    if TaskTracker.NotesButtonTip then return TaskTracker.NotesButtonTip() end
    return NOTE_BTN_TIP
end

local function wireNoteButtonOpensNotesOnly(noteBtn, node)
    noteBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    noteBtn:SetScript("OnClick", function(_, button)
        openListNote(node, button)
    end)
    noteBtn:SetScript("OnEnter", function()
        ShowBesideTip(noteBtn, "Notes", noteButtonTip())
    end)
    noteBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local PROG_TO_NOTE_GAP = 6
local NOTE_TO_CMD_GAP  = 4
local LABEL_TO_CMD_GAP = 6
-- Same min width for task and registry progress so Way/note icons share a column.
local PROG_HOST_MIN_W  = 36
local PROG_HOST_MAX_W  = 120

local function ListLayoutEpoch()
    return TaskTracker._ttListLayoutEpoch or 0
end

local function listRowIconSize(rh)
    local pct = 90
    if TaskTracker.GetListRowIconPercent then
        pct = TaskTracker.GetListRowIconPercent()
    end
    local row = rh or BASE_ROW_HEIGHT
    local sz = math.floor(row * pct / 100 + 0.5)
    if sz < 8 then sz = 8 end
    if sz > row then sz = row end
    return sz
end

local function listRowCmdIconSize(rh)
    return listRowIconSize(rh)
end

local function taskFontPx()
    return (TaskTracker.GetTaskFontSize and TaskTracker.GetTaskFontSize()) or 11
end

--- One-line text and the icon strip share this offset. Two-line rows are centered
--- on 0, so a downward nudge left the one-line name and the icons sitting low.
local LIST_OPTICAL_DROP = 0

--- How far above the row center the title sits when a second line is under it.
local function twoLineTitleLift(subPx)
    return math.floor(((tonumber(subPx) or taskFontPx()) + 2) / 2)
end

--- One point plus a width. A second point (LEFT and RIGHT) stretches the line and
--- drops the y offset, which is why the nudge never showed up.
--- `width` is the space before the icon rail, including Title to icons.
local function placeListLine(fs, row, x, y, width)
    if not fs then return end
    fs:ClearAllPoints()
    fs:SetWidth(math.max(40, width or 40))
    fs:SetPoint("LEFT", row, "LEFT", x, y)
    fs:SetJustifyV("MIDDLE")
end

--- Pixels the name may use before the icon rail. The rail always holds a command
--- slot and a note slot, and it sits left of the count. Title to icons is the
--- last gap, so the slider moves the cutoff.
local function listTextWidthBeforeIcons(row, rowWidth, textLeft, progFrame)
    local pad = TaskTracker.GetListPadRight and TaskTracker.GetListPadRight() or 0
    local rail = row and (row._ttIconRail or (row._ttCmdCol and row._ttCmdCol:GetParent()))
    local railW = (rail and rail.GetWidth and rail:GetWidth()) or 0
    if not railW or railW < 4 then
        local noteSz = (row and (row._ttNoteIconSz or row._ttIconSz)) or 16
        local cmdSz = (row and (row._ttCmdIconSz or noteSz)) or noteSz
        railW = cmdSz + NOTE_TO_CMD_GAP + noteSz
    end
    local railGap = PROG_TO_NOTE_GAP
    if rail and rail.GetNumPoints and rail:GetNumPoints() >= 1 then
        local _, _, _, xOff = rail:GetPoint(1)
        if type(xOff) == "number" and xOff < 0 then
            railGap = math.floor(-xOff + 0.5)
        end
    end
    local progW = 0
    if progFrame and progFrame.IsShown and progFrame:IsShown() then
        progW = (progFrame.GetWidth and progFrame:GetWidth()) or 0
    end
    local gap = LABEL_TO_CMD_GAP
    if TaskTracker.GetLabelToIconGap then
        gap = TaskTracker.GetLabelToIconGap()
    end
    local inset = pad + progW + railGap + railW + gap
    return math.max(40, (rowWidth or 0) - (textLeft or 0) - inset)
end

--- Glyph only. No fill and no border, so the percent is the picture you see.
local LIST_ROW_ICON_OPT = {
    noBorder = true,
    iconFill = true,
    iconMargin = 0,
    hoverBgKey = "rowHover",
}

local function listLabelToIconGap()
    if TaskTracker.GetLabelToIconGap then
        return TaskTracker.GetLabelToIconGap()
    end
    return LABEL_TO_CMD_GAP
end

local function listHeaderTitleGap()
    if TaskTracker.GetHeaderTitleGap then
        return TaskTracker.GetHeaderTitleGap()
    end
    return 6
end

local function checkboxIconSize(rh)
    local pct = 85
    if TaskTracker.GetListCheckboxPercent then
        pct = TaskTracker.GetListCheckboxPercent()
    end
    local row = rh or BASE_ROW_HEIGHT
    local maxSz = math.max(8, row - 2)
    local sz = math.floor(row * pct / 100 + 0.5)
    if sz < 8 then sz = 8 end
    if sz > maxSz then sz = maxSz end
    return sz
end

local function sizeCheckboxIcon(box, rh)
    if not box then return end
    local sz = checkboxIconSize(rh)
    box:SetSize(sz, sz)
end

--- Width of the title column from the row width. Live GetWidth() is 0 right after a
--- pooled frame is shown, then the real width next refresh, so ellipsis and row
--- height were flipping every update.
local function editLabelWidth(rowWidth, baseRh, withHammer)
    local padL = TaskTracker.GetListPadLeft and TaskTracker.GetListPadLeft() or 4
    local padR = TaskTracker.GetListPadRight and TaskTracker.GetListPadRight() or 4
    local t = TaskTracker.GetTheme and TaskTracker.GetTheme()
    local barW = (t and t.taskAutomationBarWidth) or 3
    local strip = barW + automationCheckGap() + checkboxIconSize(baseRh) + 6
    local noteSz = listRowIconSize(baseRh)
    local cmdSz = listRowCmdIconSize(baseRh)
    local rail = cmdSz + NOTE_TO_CMD_GAP + noteSz
    local glyphs = editChromeSize(baseRh)
    if withHammer then
        glyphs = glyphs + 4 + editChromeSize(baseRh)
    end
    local countReserve = 72
    return math.max(40, (rowWidth or 0) - padL - strip - listLabelToIconGap() - rail - PROG_TO_NOTE_GAP - countReserve - 6 - glyphs - padR)
end

local function getMeasureFs(key, fontObject)
    TaskTracker._ttListMeasure = TaskTracker._ttListMeasure or {}
    local m = TaskTracker._ttListMeasure
    local fs = m[key]
    if fs and fs.GetParent and fs:GetParent() then
        if fontObject and fs.SetFontObject then
            fs:SetFontObject(fontObject)
            TaskTracker.ClearFontShadow(fs)
        end
        return fs
    end
    fs = TaskTracker.CreateFontString(UIParent, nil, "ARTWORK", fontObject or "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -8000, 8000)
    fs:Hide()
    fs:SetJustifyH("LEFT")
    m[key] = fs
    return fs
end

local function measureWrapHeight(fontObject, text, width, justifyV)
    local fs = getMeasureFs(tostring(fontObject or "GameFontNormalSmall") .. (justifyV or ""), fontObject or "GameFontNormalSmall")
    if TaskTracker.ApplyExplicitFontSize then
        TaskTracker.ApplyExplicitFontSize(fs, "task")
    end
    fs:SetJustifyV(justifyV or "TOP")
    enableListWrap(fs)
    fs:SetWidth(math.max(1, width or 1))
    fs:SetText(text or "")
    local _, fh = fs:GetFont()
    local minH = (type(fh) == "number" and fh > 0) and fh or 10
    local h = fs:GetStringHeight() or 0
    if h < minH then h = minH end
    return h
end

local function makeCheckboxIcon(row, rh)
    local sz = checkboxIconSize(rh)
    local f = CreateFrame("Frame", nil, row)
    f:SetSize(sz, sz)

    local bg = f:CreateTexture(nil, "OVERLAY")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")

    f._ttBg = bg
    return f
end

local function completedRowStays(node)
    if node and node.alwaysShow == true then return true end
    if TaskTracker.WorldQuestRowIgnoresHideCompleted and TaskTracker.WorldQuestRowIgnoresHideCompleted(node) then
        return true
    end
    return false
end

local function setCheckboxIconState(box, done, overridden)
    if not box then return end
    if box._ttBg then
        if overridden then
            TaskTracker.SetColor(box._ttBg, "taskBarManual")
        elseif done then
            TaskTracker.SetColor(box._ttBg, "complete")
        else
            TaskTracker.SetColor(box._ttBg, "textSecondary")
            box._ttBg:SetAlpha(0.75)
        end
        if overridden or done then
            box._ttBg:SetAlpha(1)
        end
    end
end

--- Fixed [cmd][note] slots in one rail right of `progFrame` (L→R: cmd | note | prog).
--- Single parent + LEFT/RIGHT children avoids layout where a lone command drifts into the note slot.
local function makeListIconColumnShell(row, rh, progFrame, gapProgToNote)
    local noteSz = listRowIconSize(rh)
    local cmdSz = listRowCmdIconSize(rh)
    local gap = gapProgToNote or PROG_TO_NOTE_GAP
    local railW = cmdSz + NOTE_TO_CMD_GAP + noteSz
    local rail = CreateFrame("Frame", nil, row)
    rail:SetSize(railW, rh)
    rail:SetPoint("RIGHT", progFrame, "LEFT", -gap, 0)
    rail:EnableMouse(true)
    row._ttIconRail = rail

    local cmdCol = CreateFrame("Frame", nil, rail)
    cmdCol:SetSize(cmdSz, rh)
    cmdCol:SetPoint("LEFT", rail, "LEFT", 0, 0)

    local noteCol = CreateFrame("Frame", nil, rail)
    noteCol:SetSize(noteSz, rh)
    noteCol:SetPoint("RIGHT", rail, "RIGHT", 0, 0)

    row._ttCmdCol, row._ttNoteCol = cmdCol, noteCol
    row._ttIconSz, row._ttNoteIconSz, row._ttCmdIconSz = noteSz, noteSz, cmdSz

    return cmdCol, noteCol, noteSz
end

local function sizeListIconColumnShell(row, rh)
    if not row then return listRowIconSize(rh) end
    local noteSz = listRowIconSize(rh)
    local cmdSz = listRowCmdIconSize(rh)
    local rail = row._ttIconRail or (row._ttCmdCol and row._ttCmdCol:GetParent())
    if rail then
        rail:SetSize(cmdSz + NOTE_TO_CMD_GAP + noteSz, rh)
        row._ttIconRail = rail
    end
    if row._ttCmdCol then row._ttCmdCol:SetSize(cmdSz, rh) end
    if row._ttNoteCol then row._ttNoteCol:SetSize(noteSz, rh) end
    if row._ttNoteBtn and TaskTracker.SizeIconButton then
        TaskTracker.SizeIconButton(row._ttNoteBtn, noteSz, noteSz, LIST_ROW_ICON_OPT)
    end
    row._ttIconSz, row._ttNoteIconSz, row._ttCmdIconSz = noteSz, noteSz, cmdSz
    return noteSz
end

local function raiseListIconRail(row)
    local rail = row and (row._ttIconRail or (row._ttCmdCol and row._ttCmdCol:GetParent()))
    if not rail then return nil end
    rail:EnableMouse(true)
    local base = (row:GetFrameLevel() or 0) + 10
    rail:SetFrameLevel(base)
    if row._ttNoteBtn then row._ttNoteBtn:SetFrameLevel(base + 2) end
    if row._ttCmdBtn then row._ttCmdBtn:SetFrameLevel(base + 2) end
    if row._ttCmdRunBtn then row._ttCmdRunBtn:SetFrameLevel(base + 2) end
    return rail
end

--- Label hitbox stops at the cmd/note rail so those buttons stay clickable.
local function anchorRowHitLeftOfIconRail(hit, row, topLeftX)
    if not hit or not row then return end
    hit:ClearAllPoints()
    hit:SetPoint("TOPLEFT", row, "TOPLEFT", topLeftX or 0, 0)
    hit:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    local rail = raiseListIconRail(row)
    if rail then
        hit:SetPoint("RIGHT", rail, "LEFT", -2, 0)
    elseif row._ttProgHost then
        hit:SetPoint("RIGHT", row._ttProgHost, "LEFT", -2, 0)
    elseif row._ttProgressHost then
        hit:SetPoint("RIGHT", row._ttProgressHost, "LEFT", -2, 0)
    else
        local rPad = TaskTracker.GetListPadRight and TaskTracker.GetListPadRight() or 0
        hit:SetPoint("RIGHT", row, "RIGHT", -rPad, 0)
    end
    hit:SetFrameLevel((row:GetFrameLevel() or 0) + 1)
end

local function maybePlaceNoteIconButton(noteCol, sz, node)
    if not shouldShowRowNoteIcon(node) then return end
    local noteBtn = TaskTracker.MakeIconButton(noteCol, sz, sz, LIST_ROW_ICON_OPT)
    noteBtn:SetFrameLevel(21)
    noteBtn:SetPoint("CENTER", noteCol, "CENTER", 0, 0)
    noteBtn:SetChromeIcon(NOTE_ROW_ICON)
    wireNoteButtonOpensNotesOnly(noteBtn, node)
end

local function rowFromCmdCol(cmdCol)
    local rail = cmdCol and cmdCol:GetParent()
    return rail and rail:GetParent()
end

local function ensureRowCommandButtons(row, cmdCol, sz)
    if not row or not cmdCol then return end
    local cmdSz = (TaskTracker.GetListCommandIconSize and TaskTracker.GetListCommandIconSize())
        or listRowCmdIconSize(BASE_ROW_HEIGHT)
    if not row._ttCmdBtn then
        local opener = TaskTracker.MakeIconButton(cmdCol, cmdSz, cmdSz, LIST_ROW_ICON_OPT)
        opener:SetFrameLevel(21)
        opener:SetPoint("CENTER", cmdCol, "CENTER", 0, 0)
        if opener.icon then
            pcall(function() opener.icon:SetTexture(nil) end)
        end
        opener:SetChromeIcon(CMD_FLYOUT_ICON)
        opener:SetScript("OnClick", function(self)
            local rf = self:GetParent() and self:GetParent():GetParent() and self:GetParent():GetParent():GetParent()
            local n = rf and rf._ttNode
            if n then TaskTracker.ToggleQuickCommandsPanel(n, self) end
        end)
        opener:SetScript("OnEnter", function(self)
            local rf = self:GetParent() and self:GetParent():GetParent() and self:GetParent():GetParent():GetParent()
            local n = rf and rf._ttRunnableCmdCount or 0
            ShowBesideTip(self, "Run commands (" .. tostring(n) .. ")", "Click: flyout to the left (out of combat). Use the note icon to edit.")
        end)
        opener:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row._ttCmdBtn = opener
    elseif TaskTracker.SizeIconButton then
        TaskTracker.SizeIconButton(row._ttCmdBtn, cmdSz, cmdSz, LIST_ROW_ICON_OPT)
    else
        row._ttCmdBtn:SetSize(cmdSz, cmdSz)
    end
    if not row._ttCmdRunBtn and TaskTracker.MakeSecureMacroIconButton then
        local runBtn = TaskTracker.MakeSecureMacroIconButton(cmdCol, cmdSz, cmdSz, "list", 1, {
            secureNamespace = "listcmd",
            unnamedSecure   = true,
            insecureMacro   = true,
            iconFill        = true,
            iconMargin      = 0,
            noBorder        = true,
            hoverBgKey      = "rowHover",
        })
        runBtn:SetFrameLevel(21)
        runBtn:SetPoint("CENTER", cmdCol, "CENTER", 0, 0)
        runBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        runBtn:Hide()
        row._ttCmdRunBtn = runBtn
    elseif row._ttCmdRunBtn then
        if TaskTracker.SizeIconButton then
            TaskTracker.SizeIconButton(row._ttCmdRunBtn, cmdSz, cmdSz, LIST_ROW_ICON_OPT)
        else
            row._ttCmdRunBtn:SetSize(cmdSz, cmdSz)
        end
    end
end

--- One runnable command: show that icon and run it. Two or more: flyout arrow.
local function applyRowCommandButtons(row, node, cmdCount)
    if not row then return end
    local n = tonumber(cmdCount) or 0
    row._ttRunnableCmdCount = n
    local fly = row._ttCmdBtn
    local run = row._ttCmdRunBtn
    if n < 1 then
        if fly then fly:Hide() end
        if run then
            run:Hide()
            if TaskTracker.ApplyCommandRunMode then
                TaskTracker.ApplyCommandRunMode(run, "", nil)
            elseif TaskTracker.SetSecureMacroButtonAttributes then
                TaskTracker.SetSecureMacroButtonAttributes(run, "")
            end
        end
        return
    end
    if n == 1 and run then
        if fly then fly:Hide() end
        local cmd, icon, label, runMode
        if TaskTracker.GetFirstRunnableCommand then
            cmd, icon, label, runMode = TaskTracker.GetFirstRunnableCommand(node)
        end
        if TaskTracker.ApplyCommandRunMode then
            TaskTracker.ApplyCommandRunMode(run, cmd or "", runMode)
        elseif TaskTracker.SetSecureMacroButtonAttributes then
            TaskTracker.SetSecureMacroButtonAttributes(run, cmd or "")
        end
        if TaskTracker.SetCommandButtonFileIcon then
            TaskTracker.SetCommandButtonFileIcon(run, icon, cmd)
        end
        local tipTitle = (type(label) == "string" and label ~= "") and label or "Command"
        local tipBody = cmd or ""
        local tipRun = runMode == "line" and "Click to run each line (out of combat)." or "Click to run (out of combat)."
        run:SetScript("OnEnter", function(self)
            ShowBesideTip(self, tipTitle, tipBody, tipRun)
        end)
        run:Show()
        return
    end
    if run then
        run:Hide()
        if TaskTracker.ApplyCommandRunMode then
            TaskTracker.ApplyCommandRunMode(run, "", nil)
        elseif TaskTracker.SetSecureMacroButtonAttributes then
            TaskTracker.SetSecureMacroButtonAttributes(run, "")
        end
    end
    if fly then
        if fly.icon then
            pcall(function() fly.icon:SetTexture(nil) end)
        end
        fly:SetChromeIcon(CMD_FLYOUT_ICON)
        fly:Show()
    end
end

--- Icons stay on the row center. The title and second line are shifted around that center.
local function titleLineIconLift(_)
    return 0
end

local function placeRowCommandIcons(row, lift)
    if not row then return end
    lift = math.floor(tonumber(lift) or 0)
    if row._ttCmdLift == lift then return end
    local function pin(btn)
        if not btn then return true end
        if InCombatLockdown and InCombatLockdown() and btn.IsProtected and btn:IsProtected() then
            return false
        end
        local parent = btn:GetParent()
        if not parent then return true end
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", parent, "CENTER", 0, lift)
        return true
    end
    if pin(row._ttCmdBtn) and pin(row._ttCmdRunBtn) and pin(row._ttNoteBtn) then
        row._ttCmdLift = lift
    end
end

local function maybePlaceCommandFlyoutButton(cmdCol, sz, node, runnableCmds)
    if not runnableCmds or #runnableCmds == 0 then return end
    local row = rowFromCmdCol(cmdCol)
    ensureRowCommandButtons(row, cmdCol, sz)
    applyRowCommandButtons(row, node, #runnableCmds)
end

local function CatHeight()
    if TaskTracker.GetHeaderHeight then
        return TaskTracker.GetHeaderHeight()
    end
    return BASE_CAT_HEIGHT
end

local function placeGroupHeaderTitles(header)
    if not header then return end
    local t = TaskTracker.GetTheme and TaskTracker.GetTheme()
    local left = ((t and t.accentBarWidth) or 3) + TaskTracker.GetListPadLeft()
    if header._ttArrow then
        header._ttArrow:ClearAllPoints()
        header._ttArrow:SetPoint("LEFT", header, "LEFT", left, 0)
        if header._ttArrow.SetSize then
            local px = TaskTracker.GetHeaderFontSize and TaskTracker.GetHeaderFontSize() or 12
            header._ttArrow:SetSize(px, px)
        end
    end
    if header._ttLabel and header._ttArrow then
        header._ttLabel:ClearAllPoints()
        header._ttLabel:SetPoint("LEFT", header._ttArrow, "RIGHT", listHeaderTitleGap(), 0)
    end
end

local function refreshRowIconLayout(row, rh)
    local sz = sizeListIconColumnShell(row, rh)
    if row._ttCmdCol then
        ensureRowCommandButtons(row, row._ttCmdCol, sz)
    end
    return sz
end

local function RowHeight()
    if TaskTracker.GetTaskRowHeight then
        return TaskTracker.GetTaskRowHeight()
    end
    return BASE_ROW_HEIGHT
end

function TaskTracker.GetListCommandIconSize()
    return listRowCmdIconSize(RowHeight())
end

local function InsertHeight()
    return math.max(6, BASE_INSERT_HEIGHT)
end

local function IsEditMode()
    return TaskTracker.editMode == true
end

function TaskTracker.EditReorderUsesDrag()
    return TaskTrackerDB and TaskTrackerDB.editReorderMode == "drag"
end

local function readyToBuyZoneOnlyOn()
    return TaskTrackerDB and TaskTrackerDB.readyToBuyZoneOnly and true or false
end

local function syncReadyToBuyHeader(frame, node)
    if not frame then return end
    local show = node and node.readyToBuyHeader and not IsEditMode()
    local eye = frame._ttRtbZoneEye
    if show and not eye and TaskTracker.MakeIconButton then
        eye = TaskTracker.MakeIconButton(frame, 22, 22, TaskTracker.ChromeIconOpt())
        if eye.SetPropagateMouseClicks then
            eye:SetPropagateMouseClicks(false)
        end
        eye:SetScript("OnClick", function()
            if not TaskTrackerDB then return end
            TaskTrackerDB.readyToBuyZoneOnly = not TaskTrackerDB.readyToBuyZoneOnly
            if TaskTracker.MarkListLayoutDirty then
                TaskTracker.MarkListLayoutDirty()
            end
            if TaskTracker.RefreshListNow then
                TaskTracker.RefreshListNow()
            elseif TaskTracker.RefreshList then
                TaskTracker.RefreshList()
            end
        end)
        eye:SetScript("OnEnter", function(self)
            TaskTracker.SetColor(self.bg, "accentBg")
            ShowBesideTip(self, "Current zone", "When the eye looks covered, vendors outside the zone you are standing in are hidden.")
        end)
        eye:SetScript("OnLeave", function(self)
            if self.bg then self.bg:SetColorTexture(0, 0, 0, 0) end
            GameTooltip:Hide()
        end)
        frame._ttRtbZoneEye = eye
    end
    local btn = frame._ttRtbRefresh
    if show and not btn and TaskTracker.MakeIconButton then
        btn = TaskTracker.MakeIconButton(frame, 22, 22, TaskTracker.ChromeIconOpt())
        local painted = false
        if btn.SetIconAtlas then
            painted = pcall(btn.SetIconAtlas, btn, "UI-RefreshButton") and true or false
        end
        if not painted and btn.label then
            btn.label:SetText("↻")
            btn.label:Show()
            TaskTracker.SetTextColor(btn.label, "textPrimary")
        end
        if btn.SetPropagateMouseClicks then
            btn:SetPropagateMouseClicks(false)
        end
        btn:SetScript("OnClick", function()
            if TaskTracker.RefreshReadyToBuyList then
                TaskTracker.RefreshReadyToBuyList()
            end
        end)
        btn:SetScript("OnEnter", function(self)
            TaskTracker.SetColor(self.bg, "accentBg")
            ShowBesideTip(self, "Scan again", "Look up vendors you can buy from again.")
        end)
        btn:SetScript("OnLeave", function(self)
            if self.bg then self.bg:SetColorTexture(0, 0, 0, 0) end
            GameTooltip:Hide()
        end)
        frame._ttRtbRefresh = btn
    end
    if eye and eye.SetChromeIcon then
        eye:SetChromeIcon(readyToBuyZoneOnlyOn() and "eye-off" or "eye")
    end
    if not btn and not eye then return end
    if not show then
        if btn then btn:Hide() end
        if eye then eye:Hide() end
        return
    end
    local side = math.max(16, CatHeight() - 4)
    local function sizeBtn(b)
        if not b then return end
        if TaskTracker.SizeIconButton then
            TaskTracker.SizeIconButton(b, side, side, TaskTracker.ChromeIconOpt())
        else
            b:SetSize(side, side)
        end
        b:SetFrameLevel((frame:GetFrameLevel() or 1) + 8)
        b:Show()
    end
    sizeBtn(btn)
    sizeBtn(eye)
    local pad = TaskTracker.GetListPadRight()
    if btn then
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
    end
    if eye then
        eye:ClearAllPoints()
        if btn then
            eye:SetPoint("RIGHT", btn, "LEFT", -4, 0)
        else
            eye:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
        end
    end
    local countAnchor = eye or btn
    if frame._ttCountTxt and countAnchor then
        frame._ttCountTxt:ClearAllPoints()
        frame._ttCountTxt:SetPoint("RIGHT", countAnchor, "LEFT", -6, 0)
    end
    if frame._ttLabel and frame._ttCountTxt then
        frame._ttLabel:SetPoint("RIGHT", frame._ttCountTxt, "LEFT", -8, 0)
        frame._ttLabel:SetWordWrap(false)
        frame._ttLabel:SetJustifyH("LEFT")
    end
end

-- ─────────────────────────────────────
-- List row labels: ellipsis when narrow (measure with shared FontString)
-- ─────────────────────────────────────
local ELLIPSIS_CHAR = "…"

local function GetListLabelMeasureFS()
    local fs = TaskTracker._ttListLabelMeasureFS
    if fs and fs.GetParent and fs:GetParent() then
        return fs
    end
    TaskTracker._ttListLabelMeasureFS = nil
    -- Parent to UIParent so panel teardown / RefreshAll never leaves a dead FontString in _ttListLabelMeasureFS.
    fs = TaskTracker.CreateFontString(UIParent, nil, "ARTWORK")
    fs:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -8000, 8000)
    fs:Hide()
    TaskTracker._ttListLabelMeasureFS = fs
    return fs
end

local function SyncListLabelMeasureFont(measureFs, displayFs)
    if not measureFs or not displayFs then return end
    measureFs._ttLayoutFace = displayFs._ttLayoutFace
    if TaskTracker.ApplyExplicitFontSize then
        TaskTracker.ApplyExplicitFontSize(measureFs, displayFs._ttFontRole)
    end
end

local function MeasureListLabelWidth(measureFs, text)
    if not measureFs then return 0 end
    local ok, w = pcall(function()
        measureFs:SetText(text or "")
        if measureFs.GetUnboundedStringWidth then
            return measureFs:GetUnboundedStringWidth() or 0
        end
        return measureFs:GetStringWidth() or 0
    end)
    if ok and type(w) == "number" then return w end
    return 0
end

local function Utf8LenChars(s)
    if not s or s == "" then return 0 end
    if utf8 and utf8.len then
        local ok, n = pcall(utf8.len, s)
        if ok and type(n) == "number" then return n end
    end
    if strlenutf8 then return strlenutf8(s) end
    return #s
end

local function Utf8PrefixChars(s, n)
    if not s or n <= 0 then return "" end
    if utf8 and utf8.offset then
        -- Start of character (n+1) is the byte after a prefix of n characters (i defaults to 1 in Lua 5.3+).
        local ok, endByte = pcall(utf8.offset, s, n + 1, 1)
        if (not ok or endByte == nil) and utf8.offset then
            ok, endByte = pcall(utf8.offset, s, n + 1)
        end
        if ok and type(endByte) == "number" and endByte > 1 then
            return string.sub(s, 1, endByte - 1)
        end
        if ok and endByte == nil then
            return s
        end
    end
    return string.sub(s, 1, n)
end

local function ListLabelColored(plain, colorKey, resetTag)
    plain = plain or ""
    resetTag = resetTag or ""
    return TaskTracker.WrapColor(plain, colorKey) .. resetTag
end

--- WoW uses | for hyperlinks (|Hachievement:…|h…|h|r), colors, textures, etc. Character-wise truncation splits tokens and shows raw IDs.
local function PlainHasWoWTextEscape(s)
    return s and s:find("|", 1, true) ~= nil
end

--- A hidden measure line often counts |Tpath|t as the raw path, not the icon.
--- 16px is the coin icon. Guessing from the text plus that keeps the tag intact.
local MEDIA_ICON_PX = 16

local function InlineMediaCount(s)
    if not s or s == "" then return 0 end
    local n = 0
    for _ in s:gmatch("|T.-|t") do n = n + 1 end
    for _ in s:gmatch("|A.-|a") do n = n + 1 end
    return n
end

local function GuessInlineMediaWidth(measureFs, text)
    local n = InlineMediaCount(text)
    if n == 0 then
        return MeasureListLabelWidth(measureFs, text)
    end
    local stripped = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return MeasureListLabelWidth(measureFs, stripped) + n * MEDIA_ICON_PX
end

--- Shorten only after a finished |t or |a. A cut inside |TInterface\...|t draws the path as text.
local function FitInlineMediaLabel(measureFs, plain, maxW)
    if GuessInlineMediaWidth(measureFs, plain) <= maxW then
        return plain
    end
    local cuts = {}
    local i = 1
    while #cuts < 24 do
        local _, tEnd = plain:find("|t", i, true)
        local _, aEnd = plain:find("|a", i, true)
        local pos = tEnd
        if aEnd and (not pos or aEnd < pos) then pos = aEnd end
        if not pos then break end
        cuts[#cuts + 1] = pos
        i = pos + 1
    end
    for c = #cuts, 1, -1 do
        local body = plain:sub(1, cuts[c])
        if body ~= plain then
            local withEll = body .. ELLIPSIS_CHAR
            if GuessInlineMediaWidth(measureFs, withEll) <= maxW then
                return withEll
            end
        end
        if GuessInlineMediaWidth(measureFs, body) <= maxW then
            return body
        end
    end
    local leadEnd = plain:find("|T", 1, true)
    local atlasAt = plain:find("|A", 1, true)
    if atlasAt and (not leadEnd or atlasAt < leadEnd) then leadEnd = atlasAt end
    local lead = leadEnd and plain:sub(1, leadEnd - 1) or plain
    lead = lead:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if lead == "" then return ELLIPSIS_CHAR end
    if MeasureListLabelWidth(measureFs, lead) <= maxW then return lead end
    local lo, hi = 0, Utf8LenChars(lead)
    local best = 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local cand = Utf8PrefixChars(lead, mid) .. ELLIPSIS_CHAR
        if MeasureListLabelWidth(measureFs, cand) <= maxW then
            best = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    if best <= 0 then return ELLIPSIS_CHAR end
    return Utf8PrefixChars(lead, best) .. ELLIPSIS_CHAR
end

local function ApplyEllipsisColoredListLabel(displayFs, plain, colorKey, resetTag, maxW)
    if not displayFs then return end
    plain = plain or ""
    resetTag = resetTag or ""
    local full = ListLabelColored(plain, colorKey, resetTag)
    if displayFs.SetWordWrap then displayFs:SetWordWrap(false) end
    if displayFs.SetMaxLines then displayFs:SetMaxLines(1) end

    local okApply = pcall(function()
        local measureFs = GetListLabelMeasureFS()
        SyncListLabelMeasureFont(measureFs, displayFs)

        if not maxW or maxW < 8 then
            displayFs:SetText(ListLabelColored(ELLIPSIS_CHAR, colorKey, resetTag))
            return
        end

        if MeasureListLabelWidth(measureFs, full) <= maxW then
            displayFs:SetText(full)
            return
        end

        if PlainHasWoWTextEscape(plain) or PlainHasWoWTextEscape(resetTag) then
            displayFs:SetText(full)
            return
        end

        local lo, hi = 0, Utf8LenChars(plain)
        local best = 0
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            local cand = ListLabelColored(Utf8PrefixChars(plain, mid) .. ELLIPSIS_CHAR, colorKey, resetTag)
            if MeasureListLabelWidth(measureFs, cand) <= maxW then
                best = mid
                lo = mid + 1
            else
                hi = mid - 1
            end
        end

        if best <= 0 then
            displayFs:SetText(ListLabelColored(ELLIPSIS_CHAR, colorKey, resetTag))
        else
            displayFs:SetText(ListLabelColored(Utf8PrefixChars(plain, best) .. ELLIPSIS_CHAR, colorKey, resetTag))
        end
    end)

    if not okApply then
        displayFs:SetText(full)
    end
end

local function ApplyEllipsisPlainListLabel(displayFs, plain, maxW)
    if not displayFs then return end
    plain = plain or ""
    if displayFs.SetWordWrap then displayFs:SetWordWrap(false) end
    if displayFs.SetMaxLines then displayFs:SetMaxLines(1) end

    local okApply = pcall(function()
        local measureFs = GetListLabelMeasureFS()
        SyncListLabelMeasureFont(measureFs, displayFs)

        if not maxW or maxW < 8 then
            displayFs:SetText(ELLIPSIS_CHAR)
            return
        end

        -- Coin rows are |T tags. Character truncation opens the tag and the path shows as text.
        -- SetMaxLines(1) does the same cut on the client, so leave this line unclipped by ellipsis.
        if plain:find("|T", 1, true) or plain:find("|A", 1, true) then
            if displayFs.SetMaxLines then displayFs:SetMaxLines(0) end
            displayFs:SetText(FitInlineMediaLabel(measureFs, plain, maxW))
            return
        end

        if MeasureListLabelWidth(measureFs, plain) <= maxW then
            displayFs:SetText(plain)
            return
        end

        if PlainHasWoWTextEscape(plain) then
            local sep = " · "
            local parts = {}
            local startAt = 1
            while true do
                local a, b = plain:find(sep, startAt, true)
                if not a then
                    parts[#parts + 1] = plain:sub(startAt)
                    break
                end
                parts[#parts + 1] = plain:sub(startAt, a - 1)
                startAt = b + 1
            end
            local function joinParts(n)
                local t = {}
                for i = 1, n do t[i] = parts[i] end
                return table.concat(t, sep)
            end
            local n = #parts
            while n > 1 and MeasureListLabelWidth(measureFs, joinParts(n)) > maxW do
                n = n - 1
            end
            local body = joinParts(n)
            if n < #parts then
                local withEll = body .. sep .. ELLIPSIS_CHAR
                if MeasureListLabelWidth(measureFs, withEll) <= maxW then
                    displayFs:SetText(withEll)
                    return
                end
            end
            if MeasureListLabelWidth(measureFs, body) <= maxW then
                displayFs:SetText(body)
                return
            end
            local vis = (parts[1] or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local hex = (parts[1] or ""):match("|cff(%x%x%x%x%x%x)")
            local function recolor(text)
                if not hex then return text end
                return "|cff" .. hex .. text .. "|r"
            end
            local lo, hi = 0, Utf8LenChars(vis)
            local best = 0
            while lo <= hi do
                local mid = math.floor((lo + hi) / 2)
                local cand = recolor(Utf8PrefixChars(vis, mid) .. ELLIPSIS_CHAR)
                if MeasureListLabelWidth(measureFs, cand) <= maxW then
                    best = mid
                    lo = mid + 1
                else
                    hi = mid - 1
                end
            end
            if best <= 0 then
                displayFs:SetText(recolor(ELLIPSIS_CHAR))
            else
                displayFs:SetText(recolor(Utf8PrefixChars(vis, best) .. ELLIPSIS_CHAR))
            end
            return
        end

        local lo, hi = 0, Utf8LenChars(plain)
        local best = 0
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            local cand = Utf8PrefixChars(plain, mid) .. ELLIPSIS_CHAR
            if MeasureListLabelWidth(measureFs, cand) <= maxW then
                best = mid
                lo = mid + 1
            else
                hi = mid - 1
            end
        end

        if best <= 0 then
            displayFs:SetText(ELLIPSIS_CHAR)
        else
            displayFs:SetText(Utf8PrefixChars(plain, best) .. ELLIPSIS_CHAR)
        end
    end)

    if not okApply then
        if plain:find("|T", 1, true) or plain:find("|A", 1, true) then
            if displayFs.SetMaxLines then displayFs:SetMaxLines(0) end
        end
        displayFs:SetText(plain)
    end
end

--- One LEFT point plus a width, same as browse mode. A RIGHT point as well
--- drops the y offset, so the second line falls onto the next row.
--- Defined after the ellipsis helpers: a local function above them would call nil.
local function placeEditTaskTexts(row, taskName, opts)
    if not row or not taskName or not opts then return end
    local useGrow = opts.useGrow
    local subtitle = opts.subtitle
    local hasSub = subtitle and subtitle ~= ""
    local yTitle = 0
    if not useGrow and hasSub then
        yTitle = twoLineTitleLift(opts.subLineH)
    end
    if row._ttLeftStrip then
        row._ttLeftStrip:ClearAllPoints()
        if useGrow then
            row._ttLeftStrip:SetPoint("TOPLEFT", row, "TOPLEFT", opts.leftPad or 0, 0)
        else
            row._ttLeftStrip:SetPoint("LEFT", row, "LEFT", opts.leftPad or 0, yTitle)
        end
    end
    placeEditTaskChrome(row, opts.baseRh, yTitle)
    local labelW = opts.labelW or 40
    local textLeft = opts.textLeft or 0
    if useGrow then
        taskName:ClearAllPoints()
        taskName:SetWidth(labelW)
        taskName:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, 0)
        taskName:SetJustifyV("TOP")
        enableListWrap(taskName)
        taskName:SetText(opts.fullTitle or "")
    else
        placeListLine(taskName, row, textLeft, yTitle, labelW)
        taskName:SetWordWrap(false)
        if taskName.SetMaxLines then taskName:SetMaxLines(1) end
        ApplyEllipsisColoredListLabel(taskName, opts.titlePlain, opts.titleColorKey, opts.resetTag, labelW)
    end
    local subFs = row._ttSubtitle
    if hasSub then
        if not subFs then
            subFs = TaskTracker.CreateScaledListFontString(row, "OVERLAY", "GameFontDisableSmall")
            TaskTracker.SetTextColor(subFs, "textSecondary")
            subFs:SetJustifyH("LEFT")
            row._ttSubtitle = subFs
        end
        if opts.subColor then
            TaskTracker.SetTextColor(subFs, opts.subColor)
        end
        subFs:Show()
        if useGrow then
            enableListWrap(subFs)
            subFs:ClearAllPoints()
            subFs:SetPoint("TOPLEFT", taskName, "BOTTOMLEFT", 0, -2)
            subFs:SetWidth(labelW)
            subFs:SetJustifyV("TOP")
            subFs:SetText(subtitle)
        else
            local subPx = tonumber(opts.subLineH) or taskFontPx()
            if subPx < 10 then subPx = math.max(10, taskFontPx()) end
            local ySub = yTitle - math.floor((taskFontPx() + 2 + subPx) / 2)
            placeListLine(subFs, row, textLeft, ySub, labelW)
            subFs:SetWordWrap(false)
            if subFs.SetMaxLines then subFs:SetMaxLines(1) end
            ApplyEllipsisPlainListLabel(subFs, subtitle, labelW)
        end
    elseif subFs then
        subFs:Hide()
        subFs:SetText("")
    end
end

-- Edit mode: pick "=" then click an insert line to move (see MainPanel edit hint).
function TaskTracker.ToggleReorderPickUp(nodeId)
    if TaskTracker.reorderPickUpNodeId == nodeId then
        TaskTracker.reorderPickUpNodeId = nil
    else
        TaskTracker.reorderPickUpNodeId = nodeId
    end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

function ShowBesideTip(anchor, title, ...)
    TaskTracker.BeginTooltipBesideList(anchor)
    GameTooltip:SetText(title, 1, 1, 1)
    local n = select("#", ...)
    for i = 1, n do
        local line = select(i, ...)
        if line and line ~= "" then
            GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true)
        end
    end
    TaskTracker.FinishTooltipBesideList()
end

local function ShowInsertLineTooltip(anchor, title, body)
    ShowBesideTip(anchor, title, body)
end

local function groupDisplayName(node)
    if not node or node.type ~= "group" then return nil end
    local name = node.name
    if node.moduleGroupKey == "professions" and TaskTracker.GetProfessionsGroupDisplayName then
        name = TaskTracker.GetProfessionsGroupDisplayName(node.name) or name
    end
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

local function insertTargetPhrase(parentID, kind)
    local node = parentID and TaskTracker.FindNode and TaskTracker.FindNode(parentID)
    local name = groupDisplayName(node)
    if kind == "task" then
        if not name then
            return "Tasks can only be added inside a group. Use a line under an expanded group header."
        end
        if TaskTracker.ModuleSectionBlocksNewTask and TaskTracker.ModuleSectionBlocksNewTask(node) then
            return "Official sections, such as Midnight, don't take new tasks. Add the task under a group you made."
        end
        return "This adds a task to " .. name .. "."
    end
    if kind == "group" then
        if name then
            return "This adds a group to " .. name .. "."
        end
        return "This adds a group to the list."
    end
    if name then
        return "This places the row in " .. name .. "."
    end
    return "This places the row at the top level."
end

local function paintHeaderTarget(header, on)
    if not header or not header._ttTargetGlow then return end
    if not on then
        header._ttTargetGlow:Hide()
        return
    end
    local t = TaskTracker.GetTheme and TaskTracker.GetTheme() or {}
    local c = t.textAccent or { 0, 0.74, 0.83, 1 }
    header._ttTargetGlow:SetColorTexture(c[1] or 0, c[2] or 0.74, c[3] or 0.83, 0.40)
    header._ttTargetGlow:Show()
end

local function setInsertTargetHighlight(parentID)
    local node = parentID and TaskTracker.FindNode and TaskTracker.FindNode(parentID)
    if not groupDisplayName(node) then
        parentID = nil
    end
    if TaskTracker._ttInsertHighlightParentId == parentID then return end
    local headers = TaskTracker._ttEditHeaders
    local prev = TaskTracker._ttInsertHighlightParentId
    TaskTracker._ttInsertHighlightParentId = parentID
    if headers and prev and headers[prev] then
        paintHeaderTarget(headers[prev], false)
    end
    if headers and parentID and headers[parentID] then
        paintHeaderTarget(headers[parentID], true)
    end
end

local function leaveInsertTarget(zone)
    if zone and TaskTracker._ttReorderDragZone == zone then return end
    setInsertTargetHighlight(nil)
    GameTooltip:Hide()
end

local function SetInsertLineColor(line, hover)
    local t = TaskTracker.GetTheme()
    local c
    if TaskTracker.reorderPickUpNodeId then
        if t.insertLinePickUp then
            c = hover and (t.insertHoverPickUp or t.insertLinePickUp) or t.insertLinePickUp
        else
            c = hover and t.insertHover or t.insertLine
        end
    else
        c = hover and t.insertHover or t.insertLine
    end
    if c and line then
        line:SetColorTexture(c[1], c[2], c[3], c[4] or 0.5)
    end
end

--- Split insert row: left adds a group, right adds a task (only when `parentID` is a group).
local function SyncSplitInsertLineAdds(zone, w, ih)
    local t = TaskTracker.GetTheme()
    local parentID = zone._ttParentID
    local siblingID = zone._ttSiblingID
    local parentNode = TaskTracker.FindNode(parentID)
    local canAddTask = parentNode and parentNode.type == "group"
        and not (TaskTracker.ModuleSectionBlocksNewTask and TaskTracker.ModuleSectionBlocksNewTask(parentNode))
    zone._ttCanAddTask = canAddTask and true or false
    local half = math.max(1, math.floor(w / 2))

    if not zone._ttSplitBuilt then
        local lineLeft = zone:CreateTexture(nil, "ARTWORK")
        lineLeft:SetHeight(2)
        lineLeft:SetPoint("LEFT", zone, "LEFT", 4, 0)
        lineLeft:SetPoint("RIGHT", zone, "CENTER", -1, 0)
        zone._ttLineLeft = lineLeft

        local lineRight = zone:CreateTexture(nil, "ARTWORK")
        lineRight:SetHeight(2)
        lineRight:SetPoint("LEFT", zone, "CENTER", 1, 0)
        lineRight:SetPoint("RIGHT", zone, "RIGHT", -4, 0)
        zone._ttLineRight = lineRight

        local leftHit = CreateFrame("Button", nil, zone)
        leftHit:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, 0)
        zone._ttLeftHit = leftHit

        local rightHit = CreateFrame("Button", nil, zone)
        zone._ttRightHit = rightHit

        zone._ttSplitBuilt = true
    end

    local lineLeft, lineRight = zone._ttLineLeft, zone._ttLineRight
    local leftHit, rightHit = zone._ttLeftHit, zone._ttRightHit
    leftHit:SetSize(half, ih)
    rightHit:SetSize(math.max(1, w - half), ih)
    rightHit:ClearAllPoints()
    rightHit:SetPoint("TOPLEFT", zone, "TOPLEFT", half, 0)

    local function paintSplit(leftHover, rightHover)
        if zone._ttDragHot then
            local hot = t.insertLinePickUp or t.insertHover or t.insertLine
            if hot and lineLeft then
                lineLeft:SetColorTexture(hot[1], hot[2], hot[3], hot[4] or 0.85)
            end
            if hot and lineRight then
                lineRight:SetColorTexture(hot[1], hot[2], hot[3], hot[4] or 0.85)
            end
            return
        end
        local lg, lh = t.insertSplitGroupLine, t.insertSplitGroupHover
        if lg and lineLeft then
            local c = (leftHover and lh) or lg
            lineLeft:SetColorTexture(c[1], c[2], c[3], c[4] or 0.65)
        end
        local tg, th = t.insertSplitTaskLine, t.insertSplitTaskHover
        local dis = t.insertSplitTaskDisabled
        if zone._ttCanAddTask and tg and lineRight then
            local c = (rightHover and th) or tg
            lineRight:SetColorTexture(c[1], c[2], c[3], c[4] or 0.65)
        elseif dis and lineRight then
            lineRight:SetColorTexture(dis[1], dis[2], dis[3], dis[4] or 0.35)
        end
    end
    paintSplit(false, false)

    leftHit:SetScript("OnEnter", function()
        paintSplit(true, false)
        if TaskTracker._ttReorderDragId then return end
        setInsertTargetHighlight(zone._ttParentID)
        ShowInsertLineTooltip(leftHit, "Add group", insertTargetPhrase(zone._ttParentID, "group"))
    end)
    leftHit:SetScript("OnLeave", function()
        paintSplit(false, false)
        leaveInsertTarget(zone)
    end)
    leftHit:SetScript("OnClick", function()
        TaskTracker.groupDialog.OpenNew(zone._ttParentID, zone._ttSiblingID)
    end)

    rightHit:SetScript("OnEnter", function()
        if zone._ttCanAddTask then
            paintSplit(false, true)
        end
        if TaskTracker._ttReorderDragId then return end
        setInsertTargetHighlight(zone._ttParentID)
        ShowInsertLineTooltip(rightHit, "Add task", insertTargetPhrase(zone._ttParentID, "task"))
    end)
    rightHit:SetScript("OnLeave", function()
        paintSplit(false, false)
        leaveInsertTarget(zone)
    end)
    if zone._ttCanAddTask then
        rightHit:SetScript("OnClick", function()
            TaskTracker.taskDialog.OpenAdd(zone._ttParentID)
        end)
    else
        rightHit:SetScript("OnClick", function() end)
    end
end

local function WirePickUpButton(btn, node)
    btn._ttPickNode = node
    local locked = TaskTracker.IsPatchListReorderLocked and TaskTracker.IsPatchListReorderLocked(node)
    if locked then
        btn:Hide()
        return
    end
    btn:Show()
    local function syncStyle()
        local n = btn._ttPickNode
        if n and TaskTracker.reorderPickUpNodeId == n.id then
            TaskTracker.SetColor(btn.bg, "accentBg")
            TaskTracker.SetTextColor(btn.label, "textAccent")
        else
            TaskTracker.SetColor(btn.bg, "headerBg")
            TaskTracker.SetTextColor(btn.label, "textSecondary")
        end
    end
    syncStyle()
    btn:SetScript("OnEnter", function()
        TaskTracker.SetColor(btn.bg, "accentBg")
        TaskTracker.SetTextColor(btn.label, "textAccent")
        if TaskTracker.EditReorderUsesDrag() then
            ShowBesideTip(btn, "Move row", "Drag to a gap. A copy of the row follows the cursor.")
        else
            ShowBesideTip(btn, "Move row", "Click to pick up, then click a gold line.")
        end
    end)
    btn:SetScript("OnLeave", function()
        syncStyle()
        GameTooltip:Hide()
    end)
    if btn.RegisterForDrag then
        btn:RegisterForDrag("LeftButton")
    end
    btn:SetScript("OnDragStart", function(self)
        if not TaskTracker.EditReorderUsesDrag() then return end
        local n = self._ttPickNode
        if n and TaskTracker.IsPatchListReorderLocked and TaskTracker.IsPatchListReorderLocked(n) then
            return
        end
        if n and TaskTracker.BeginReorderDrag then
            TaskTracker.BeginReorderDrag(n.id)
        end
    end)
    btn:SetScript("OnClick", function(self)
        if TaskTracker.EditReorderUsesDrag() then return end
        local n = self._ttPickNode
        if n and TaskTracker.IsPatchListReorderLocked and TaskTracker.IsPatchListReorderLocked(n) then
            return
        end
        if n then
            TaskTracker.ToggleReorderPickUp(n.id)
        end
    end)
end

-- A section with no tasks and no registry rows. Empty folders inside it still count as empty.
local function subtreeHasTaskOrRegistry(n)
    if not n then return false end
    if n.type == "task" or n.type == "registryEntry" then return true end
    local kids = n.children
    if type(kids) ~= "table" then return false end
    for i = 1, #kids do
        if subtreeHasTaskOrRegistry(kids[i]) then return true end
    end
    return false
end

-- Pure registry module groups: omit the header when every leaf is off in Modules,
-- unlisted (Collected), or a hidden collection farm.
-- Power also hides when level or ilvl leaves no row to show.
-- Empty groups (Options, List): off hides a group you made, completed shows it
-- while Show completed is on, always shows it. Edit mode still shows it.
local function emptyUserGroupStays()
    if IsEditMode() then return true end
    local mode = TaskTrackerDB and TaskTrackerDB.showEmptyGroups
    if mode == "always" then return true end
    if mode == "completed" then
        return not (TaskTrackerDB and TaskTrackerDB.hideCompleted)
    end
    return false
end

-- A fully empty section hides on the normal list unless Empty groups says to show it.
-- It stays visible while editing.
local function ModuleGroupFullyDisabled(node)
    if not node or node.type ~= "group" then
        return false
    end
    if not subtreeHasTaskOrRegistry(node) then
        -- A built-in section with nothing in it stays hidden. A group you made
        -- follows Empty groups, and stays on the list while editing.
        if node.moduleGroupKey then return true end
        return not emptyUserGroupStays()
    end
    local powerMode = node.moduleGroupKey == "power"
    if not node.children or #node.children == 0 then
        return powerMode
    end
    local function allRegistryLeavesDisabled(n)
        if n.type == "registryEntry" then
            if powerMode then
                if TaskTracker.IsRegistryRowTrackedForList then
                    return not TaskTracker.IsRegistryRowTrackedForList(n.registryEntryId, true)
                end
                return not TaskTracker.IsPowerListEntryEnabled(n.registryEntryId)
            end
            if TaskTracker.IsRegistryRowTrackedForList then
                return not TaskTracker.IsRegistryRowTrackedForList(n.registryEntryId, false)
            end
            return not TaskTracker.IsEntryEnabled(n.registryEntryId)
        elseif n.type == "task" and n.collectionFarmId then
            return TaskTracker.IsCollectionFarmTaskListed and not TaskTracker.IsCollectionFarmTaskListed(n)
        elseif n.type == "group" and n.children then
            if TaskTracker.ProfessionModuleSubgroupVisible
                and not TaskTracker.ProfessionModuleSubgroupVisible(n) then
                return true
            end
            if #n.children == 0 then return true end
            for _, ch in ipairs(n.children) do
                if not allRegistryLeavesDisabled(ch) then return false end
            end
            return true
        end
        return false
    end
    for _, ch in ipairs(node.children) do
        if not allRegistryLeavesDisabled(ch) then return false end
    end
    return true
end

local function GetIndent(level)
    local db = TaskTrackerDB
    local n = (db and tonumber(db.indentSize)) or 12
    n = math.max(4, math.min(20, math.floor(n)))
    return level * n
end

-- ─────────────────────────────────────
-- Frame pools (browse + edit). Unused rows parent to a hidden holder so
-- panel teardown / theme RefreshAll cannot leave them stuck on a dead scrollChild.
-- ─────────────────────────────────────
local function GetListPoolHolder()
    local h = TaskTracker._ttListPoolHolder
    if h and h.GetParent and h:GetParent() then
        return h
    end
    h = CreateFrame("Frame", "TaskTrackerListPoolHolder", UIParent)
    h:Hide()
    h:SetSize(1, 1)
    h:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -8000, 8000)
    TaskTracker._ttListPoolHolder = h
    return h
end

local function HidePooledFrame(frame)
    if not frame then return end
    -- Bind* skips SetPoint when _ttBk matches. Release always ClearAllPoints, so the
    -- cache must die here or expand/collapse reuses a shown frame with no anchors.
    frame._ttBk = nil
    frame:SetAlpha(1)
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(GetListPoolHolder())
end

local function AcquirePooledFrame(kind, frameType, parent)
    TaskTracker._ttEditRowPools = TaskTracker._ttEditRowPools or {}
    local pool = TaskTracker._ttEditRowPools[kind]
    if pool and #pool > 0 then
        local f = table.remove(pool)
        f:SetParent(parent)
        f:ClearAllPoints()
        f:Show()
        return f, true
    end
    local f = CreateFrame(frameType or "Frame", nil, parent)
    f._ttKind = kind
    return f, false
end

local function ReleasePooledFrame(frame)
    if not frame then return end
    local kind = frame._ttKind
    HidePooledFrame(frame)
    if not kind then return end
    TaskTracker._ttEditRowPools = TaskTracker._ttEditRowPools or {}
    TaskTracker._ttEditRowPools[kind] = TaskTracker._ttEditRowPools[kind] or {}
    table.insert(TaskTracker._ttEditRowPools[kind], frame)
end

local function dumpPooledFrameList(list)
    if type(list) ~= "table" then return end
    for i = 1, #list do
        HidePooledFrame(list[i])
    end
    wipe(list)
end

--- Drop all pooled list frames so the next paint creates them on the current scrollChild.
--- Call before theme rebuilds (RefreshAll) and when the scroll area is recreated.
function TaskTracker.ResetListVirtualization()
    local active = TaskTracker._ttListActive
    if active then
        for _, slot in pairs(active) do
            if slot and slot.frame then
                HidePooledFrame(slot.frame)
            end
        end
        wipe(active)
    end

    local pools = TaskTracker._ttListPools
    if pools then
        for _, list in pairs(pools) do
            dumpPooledFrameList(list)
        end
        wipe(pools)
    end

    if TaskTracker.rowFrames then
        for _, f in ipairs(TaskTracker.rowFrames) do
            HidePooledFrame(f)
        end
        TaskTracker.rowFrames = nil
    end

    local editPools = TaskTracker._ttEditRowPools
    if editPools then
        for _, list in pairs(editPools) do
            dumpPooledFrameList(list)
        end
        wipe(editPools)
    end

    TaskTracker._ttListModel = nil
    TaskTracker._ttListModelHeight = 0
    TaskTracker._ttListDirtyLayout = true
    TaskTracker._ttListDirtyPaint = true
    TaskTracker._ttPaintVisibleList = nil
end

-- ─────────────────────────────────────
-- Insert zone
-- ─────────────────────────────────────
local function AllowEditInsert(parent, siblingNode)
    if parent and parent.generatedSection then return false end
    if siblingNode and (siblingNode.generatedSection or siblingNode.generatedTask) then return false end
    if TaskTracker.GetPatchListGroupMode and TaskTracker.GetPatchListGroupMode() ~= "patch" then
        if parent and TaskTracker.IsPatchListViewGroup and TaskTracker.IsPatchListViewGroup(parent) then
            return false
        end
        if siblingNode and TaskTracker.IsPatchListReorderLocked and TaskTracker.IsPatchListReorderLocked(siblingNode) then
            return false
        end
    end
    return true
end

local function reorderDropOk(pick, zone)
    if not pick or not zone then return false end
    local moving = TaskTracker.FindNode and TaskTracker.FindNode(pick)
    local dest = TaskTracker.FindNode and TaskTracker.FindNode(zone._ttParentID)
    if moving and TaskTracker.TaskMoveIntoSectionBlocked and TaskTracker.TaskMoveIntoSectionBlocked(moving, dest) then
        return false
    end
    local sid, pid = zone._ttSiblingID, zone._ttParentID
    if sid then
        if sid == pick then return false end
        if TaskTracker.NodeIsUnderAncestor and TaskTracker.NodeIsUnderAncestor(sid, pick) then
            return false
        end
        return true
    end
    if pid then
        if TaskTracker.NodeIsUnderAncestor and TaskTracker.NodeIsUnderAncestor(pid, pick) then
            return false
        end
        return true
    end
    return false
end

local function applyReorderDrop(pick, zone)
    if not reorderDropOk(pick, zone) then return end
    local sid, pid = zone._ttSiblingID, zone._ttParentID
    if sid then
        TaskTracker.MoveNodeAfter(pick, sid)
    elseif pid then
        TaskTracker.MoveNodeToGroupStart(pick, pid)
    end
end

local function frameScreenRect(frame)
    if not frame or not frame.GetLeft then return nil end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return nil end
    local es = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if not es or es <= 0 then es = 1 end
    local w = (frame:GetWidth() or 0) * es
    local h = (frame:GetHeight() or 0) * es
    return left * es, top * es, left * es + w, top * es - h
end

local reorderDragWatch

local function setReorderDragHover(zone)
    local prev = TaskTracker._ttReorderDragZone
    if prev == zone then return end
    if prev and prev._ttLineLeft then
        prev._ttDragHot = nil
        SyncSplitInsertLineAdds(prev, prev:GetWidth() or 1, prev:GetHeight() or InsertHeight())
    end
    TaskTracker._ttReorderDragZone = zone
    if zone and zone._ttLineLeft then
        zone._ttDragHot = true
        SyncSplitInsertLineAdds(zone, zone:GetWidth() or 1, zone:GetHeight() or InsertHeight())
    end
    setInsertTargetHighlight(zone and zone._ttParentID)
    if zone then
        ShowInsertLineTooltip(zone, "Move here", insertTargetPhrase(zone._ttParentID, "move"))
    else
        GameTooltip:Hide()
    end
end

local reorderGhost

local function restoreReorderDim()
    local list = TaskTracker._ttReorderDimmed
    TaskTracker._ttReorderDimmed = nil
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local frame = list[i]
        if frame and frame.SetAlpha then
            frame:SetAlpha(1)
        end
    end
end

local function hideReorderGhost()
    if reorderGhost then
        reorderGhost:Hide()
    end
end

local function placeReorderGhost()
    local g = reorderGhost
    if not g or not g:IsShown() then return end
    local cx, cy = GetCursorPosition()
    if not cx or not cy then return end
    local ps = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not ps or ps <= 0 then ps = 1 end
    local left = cx - (g._ttOX or 0)
    local top = cy + (g._ttOY or 0)
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / ps, top / ps)
end

local function frameInDraggedSection(frame, pick)
    local node = frame._ttNode
    if node and node.id then
        if node.id == pick then return true end
        if TaskTracker.NodeIsUnderAncestor and TaskTracker.NodeIsUnderAncestor(node.id, pick) then
            return true
        end
    end
    local pid = frame._ttParentID
    if pid and pid == pick then return true end
    if pid and TaskTracker.NodeIsUnderAncestor and TaskTracker.NodeIsUnderAncestor(pid, pick) then
        return true
    end
    return false
end

local function showReorderGhost(pick)
    local rows = TaskTracker.rowFrames
    local dimmed = {}
    local minL, maxR, maxT, minB
    local ref
    if type(rows) == "table" then
        for i = 1, #rows do
            local frame = rows[i]
            if frame and frameInDraggedSection(frame, pick) then
                frame:SetAlpha(0.35)
                dimmed[#dimmed + 1] = frame
                if frame._ttNode then
                    local l, t, r, b = frameScreenRect(frame)
                    if l then
                        ref = ref or frame
                        if not minL or l < minL then minL = l end
                        if not maxR or r > maxR then maxR = r end
                        if not maxT or t > maxT then maxT = t end
                        if not minB or b < minB then minB = b end
                    end
                end
            end
        end
    end
    TaskTracker._ttReorderDimmed = dimmed
    if not minL or not ref then
        hideReorderGhost()
        return
    end
    if not reorderGhost then
        local g = CreateFrame("Frame", nil, UIParent)
        g:SetFrameStrata("TOOLTIP")
        g:EnableMouse(false)
        local bg = g:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        g._ttBg = bg
        if TaskTracker.MakeBorder then
            TaskTracker.MakeBorder(g, "border")
        end
        if TaskTracker.MakeAccentBar then
            TaskTracker.MakeAccentBar(g, "accent")
        end
        local label = TaskTracker.CreateFontString(g, nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", g, "TOPLEFT", 12, -6)
        label:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -8, 6)
        label:SetJustifyH("LEFT")
        label:SetJustifyV("MIDDLE")
        if label.SetWordWrap then label:SetWordWrap(true) end
        g._ttLabel = label
        reorderGhost = g
    end
    local g = reorderGhost
    local es = ref.GetEffectiveScale and ref:GetEffectiveScale() or 1
    local ps = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not es or es <= 0 then es = 1 end
    if not ps or ps <= 0 then ps = 1 end
    g:SetScale(es / ps)
    local w = (maxR - minL) / es
    local h = (maxT - minB) / es
    if w < 80 then w = 80 end
    if h < 20 then h = 20 end
    if h > 140 then h = 140 end
    g:SetSize(w, h)
    local node = TaskTracker.FindNode and TaskTracker.FindNode(pick)
    local name = (node and node.name) or "Row"
    g._ttLabel:SetText(name)
    if TaskTracker.SetColor then
        TaskTracker.SetColor(g._ttBg, "headerBg2")
    end
    if TaskTracker.SetTextColor then
        TaskTracker.SetTextColor(g._ttLabel, "textPrimary")
    end
    g:SetAlpha(0.92)
    local cx, cy = GetCursorPosition()
    g._ttOX = (cx or minL) - minL
    g._ttOY = maxT - (cy or maxT)
    g:Show()
    placeReorderGhost()
end

function TaskTracker.CancelReorderDrag()
    TaskTracker._ttReorderDragId = nil
    setReorderDragHover(nil)
    restoreReorderDim()
    hideReorderGhost()
    if reorderDragWatch then
        reorderDragWatch:Hide()
    end
end

function TaskTracker.FinishReorderDrag()
    local pick = TaskTracker._ttReorderDragId
    local zone = TaskTracker._ttReorderDragZone
    local ok = reorderDropOk(pick, zone)
    TaskTracker.CancelReorderDrag()
    if ok then
        applyReorderDrop(pick, zone)
    end
end

function TaskTracker.UpdateReorderDrag(elapsed)
    local pick = TaskTracker._ttReorderDragId
    if not pick or not IsMouseButtonDown("LeftButton") then
        TaskTracker.FinishReorderDrag()
        return
    end
    elapsed = tonumber(elapsed) or 0
    local cx, cy = GetCursorPosition()
    local sf = TaskTracker.scrollFrame
    local sl, st, sr, sb = frameScreenRect(sf)
    if sf and sl and cx and cy then
        local edge = 28
        local speed = 280 * elapsed
        local cur = sf.GetVerticalScroll and sf:GetVerticalScroll() or 0
        local maxS = sf.GetVerticalScrollRange and sf:GetVerticalScrollRange() or 0
        local delta = 0
        if cy > st - edge then
            delta = -speed
        elseif cy < sb + edge then
            delta = speed
        end
        if delta ~= 0 and sf.SetVerticalScroll then
            local nextS = cur + delta
            if nextS < 0 then nextS = 0 end
            if nextS > maxS then nextS = maxS end
            if nextS ~= cur then
                sf:SetVerticalScroll(nextS)
            end
        end
    end
    local best, bestDist
    local zones = TaskTracker._ttEditInsertZones
    if cx and cy and type(zones) == "table" and (not sl or (cy <= st + 8 and cy >= sb - 8)) then
        for i = 1, #zones do
            local zone = zones[i]
            if reorderDropOk(pick, zone) then
                local zl, zt, zr, zb = frameScreenRect(zone)
                if zl and cx >= zl - 12 and cx <= zr + 12 then
                    local mid = (zt + zb) * 0.5
                    local dist = math.abs(cy - mid)
                    if not bestDist or dist < bestDist then
                        best, bestDist = zone, dist
                    end
                end
            end
        end
    end
    if bestDist and bestDist > 80 then
        best = nil
    end
    setReorderDragHover(best)
    placeReorderGhost()
end

function TaskTracker.BeginReorderDrag(nodeId)
    if not nodeId or not TaskTracker.EditReorderUsesDrag() then return end
    TaskTracker.reorderPickUpNodeId = nil
    TaskTracker._ttReorderDragId = nodeId
    setReorderDragHover(nil)
    showReorderGhost(nodeId)
    TaskTracker.UpdateReorderDrag(0)
    if not TaskTracker._ttReorderDragId then return end
    if not reorderDragWatch then
        reorderDragWatch = CreateFrame("Frame", nil, UIParent)
        reorderDragWatch:Hide()
        reorderDragWatch:SetScript("OnUpdate", function(_, elapsed)
            TaskTracker.UpdateReorderDrag(elapsed)
        end)
    end
    reorderDragWatch:Show()
end

local function RenderInsertZone(scrollChild, rowFrames, rowW, yOff, siblingID, parentID, level)
    if not IsEditMode() then return yOff end

    local indent = GetIndent(level)
    local ih     = InsertHeight()
    local w      = rowW - indent
    local kind   = TaskTracker.reorderPickUpNodeId and "editInsertDrop" or "editInsertSplit"
    local zone   = AcquirePooledFrame(kind, "Frame", scrollChild)
    zone:SetSize(w, ih)
    zone:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", indent, -yOff)
    zone._ttSiblingID = siblingID
    zone._ttParentID = parentID
    zone._ttDragHot = nil
    TaskTracker._ttEditInsertZones = TaskTracker._ttEditInsertZones or {}
    TaskTracker._ttEditInsertZones[#TaskTracker._ttEditInsertZones + 1] = zone

    if kind == "editInsertDrop" then
        if not zone._ttDropBuilt then
            local line = zone:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("LEFT", zone, "LEFT", 4, 0)
            line:SetPoint("RIGHT", zone, "RIGHT", -4, 0)
            zone._ttLine = line
            local dropBtn = CreateFrame("Button", nil, zone)
            dropBtn:SetAllPoints(zone)
            zone._ttDropBtn = dropBtn
            zone._ttDropBuilt = true
        end
        SetInsertLineColor(zone._ttLine, false)
        zone._ttDropBtn:SetScript("OnEnter", function()
            SetInsertLineColor(zone._ttLine, true)
            setInsertTargetHighlight(zone._ttParentID)
            ShowInsertLineTooltip(zone._ttDropBtn, "Move here", insertTargetPhrase(zone._ttParentID, "move"))
        end)
        zone._ttDropBtn:SetScript("OnLeave", function()
            SetInsertLineColor(zone._ttLine, false)
            leaveInsertTarget(zone)
        end)
        zone._ttDropBtn:SetScript("OnClick", function()
            local pick = TaskTracker.reorderPickUpNodeId
            if pick then
                TaskTracker.reorderPickUpNodeId = nil
                applyReorderDrop(pick, zone)
            end
        end)
    else
        SyncSplitInsertLineAdds(zone, w, ih)
    end

    table.insert(rowFrames, zone)
    return yOff + ih
end

-- ─────────────────────────────────────
-- Render group header
-- ─────────────────────────────────────
local function RenderGroupHeader(scrollChild, rowFrames, node, parent, index, rowW, yOff, level, underPowerForCounts)
    local indent    = GetIndent(level)
    local width     = rowW - indent
    local t         = TaskTracker.GetTheme()

    local catH = CatHeight()
    local header = AcquirePooledFrame("editGroupHeader", "Button", scrollChild)
    header:SetSize(width, catH)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", indent, -yOff)

    if not header._ttEditBuilt then
        local bg = header:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        header._ttBg = bg

        local glow = header:CreateTexture(nil, "BORDER")
        glow:SetAllPoints()
        glow:Hide()
        header._ttTargetGlow = glow

        TaskTracker.MakeEdge(header, "BOTTOM", "border")
        TaskTracker.MakeAccentBar(header)

        local arrow = header:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(12, 12)
        arrow:SetPoint("LEFT", header, "LEFT", (t.accentBarWidth or 3) + TaskTracker.GetListPadLeft(), 0)
        header._ttArrow = arrow

        local lbl = TaskTracker.CreateScaledListFontString(header, "OVERLAY", t.fontBold or "GameFontNormal", "header")
        lbl:SetPoint("LEFT", arrow, "RIGHT", listHeaderTitleGap(), 0)
        TaskTracker.SetTextColor(lbl, "textHeader")
        header._ttLabel = lbl

        local countTxt = TaskTracker.CreateScaledListFontString(header, "OVERLAY", t.fontNormal or "GameFontNormalSmall", "header")
        header._ttCountTxt = countTxt

        local glyph = editChromeSize(catH)
        local pickBtn = makeEqualsButton(header, glyph)
        header._ttPickBtn = pickBtn
        countTxt:SetPoint("RIGHT", pickBtn, "LEFT", -6, 0)

        local bulkOffBtn = makeBareEditButton(header, glyph)
        bulkOffBtn:SetChromeIcon("close")
        bulkOffBtn:SetPoint("RIGHT", countTxt, "LEFT", -4, 0)
        header._ttBulkOffBtn = bulkOffBtn

        local editBtn = makeHammerButton(header, glyph)
        editBtn:SetPoint("RIGHT", countTxt, "LEFT", -4, 0)
        header._ttEditBtn = editBtn
        do
            local oEnter = editBtn:GetScript("OnEnter")
            local oLeave = editBtn:GetScript("OnLeave")
            editBtn:SetScript("OnEnter", function(self)
                if oEnter then oEnter(self) end
                ShowBesideTip(editBtn, "Edit group", "Left-click to open the group editor.")
            end)
            editBtn:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                if oLeave then oLeave(self) end
            end)
        end

        if header.SetClipsChildren then header:SetClipsChildren(true) end
        header._ttEditBuilt = true
    end

    placeGroupHeaderTitles(header)
    if TaskTracker.ApplyAccentBarWidth then
        TaskTracker.ApplyAccentBarWidth(header)
    end

    TaskTracker.SetColor(header._ttBg, ListGroupHeaderBgKey(node, level))
    TaskTracker._ttEditHeaders = TaskTracker._ttEditHeaders or {}
    TaskTracker._ttEditHeaders[node.id] = header
    paintHeaderTarget(header, TaskTracker._ttInsertHighlightParentId == node.id)
    applyHereFade(header, node)
    TaskTracker.ApplyTwistIcon(header._ttArrow, node.expanded)
    local groupTitle = node.name
    if node.moduleGroupKey == "professions" and TaskTracker.GetProfessionsGroupDisplayName then
        groupTitle = TaskTracker.GetProfessionsGroupDisplayName(node.name)
    end
    header._ttLabel:SetText(groupTitle)

    local leafDone, leafTotal = 0, 0
    if TaskTracker.GetNodeLeafProgress then
        leafDone, leafTotal = TaskTracker.GetNodeLeafProgress(node, underPowerForCounts)
    end
    header._ttCountTxt:SetText(TaskTracker.CountText(leafDone, leafTotal))
    pinFontWidth(header._ttCountTxt)

    local glyph = editChromeSize(catH)
    sizeEditChrome(header._ttPickBtn, glyph)
    sizeEditChrome(header._ttBulkOffBtn, glyph)
    sizeEditChrome(header._ttEditBtn, glyph)
    header._ttPickBtn:ClearAllPoints()
    header._ttPickBtn:SetPoint("RIGHT", header, "RIGHT", -TaskTracker.GetListPadRight(), 0)
    WirePickUpButton(header._ttPickBtn, node)

    if TaskTracker.IsProtectedModuleGroup(node) then
        header._ttBulkOffBtn:Show()
        header._ttEditBtn:Hide()
        header._ttBulkOffBtn:SetScript("OnEnter", function(self)
            TaskTracker.SetColor(header._ttBulkOffBtn.bg, "danger")
            ShowBesideTip(self, "Toggle off", "Turns off every row in this section.")
        end)
        header._ttBulkOffBtn:SetScript("OnLeave", function()
            if header._ttBulkOffBtn.bg then
                header._ttBulkOffBtn.bg:SetColorTexture(0, 0, 0, 0)
            end
            GameTooltip:Hide()
        end)
        header._ttBulkOffBtn:SetScript("OnClick", function()
            TaskTracker.DisableAllRegistryUnderGroup(header._ttNode)
        end)
    else
        header._ttBulkOffBtn:Hide()
        header._ttEditBtn:Show()
        header._ttEditBtn:SetScript("OnClick", function()
            TaskTracker.groupDialog.OpenEdit(header._ttNode)
        end)
    end

    local titleStop = header._ttEditBtn
    if header._ttBulkOffBtn and header._ttBulkOffBtn:IsShown() then
        titleStop = header._ttBulkOffBtn
    end
    if header._ttLabel and titleStop then
        header._ttLabel:SetPoint("RIGHT", titleStop, "LEFT", -6, 0)
        header._ttLabel:SetWordWrap(false)
        header._ttLabel:SetJustifyH("LEFT")
        if header._ttLabel.SetMaxLines then header._ttLabel:SetMaxLines(1) end
    end

    header:SetScript("OnClick", function(self)
        local n = self._ttNode
        if not n then return end
        if TaskTracker.ToggleGroupExpanded then
            TaskTracker.ToggleGroupExpanded(n)
        else
            n.expanded = not n.expanded
        end
        if TaskTracker.MarkListLayoutDirty then
            TaskTracker.MarkListLayoutDirty()
        end
        if TaskTracker.RefreshListNow then
            TaskTracker.RefreshListNow()
        else
            TaskTracker.RefreshList()
        end
    end)

    header._ttKind = "editGroupHeader"
    header._ttNode = node

    table.insert(rowFrames, header)
    return yOff + catH + TaskTracker.GetSpacingGroupHeader()
end

local function generatedClickConsumed(node, button, nodeId)
    if not (node and node.generatedTask) then return false end
    if button == "RightButton" then
        if node.readyToBuyVendor and TaskTracker.DismissReadyToBuyVendor then
            TaskTracker.DismissReadyToBuyVendor(node.readyToBuyVendor)
        elseif TaskTracker.DismissGeneratedTask then
            TaskTracker.DismissGeneratedTask(nodeId or node.id)
        end
    end
    return true
end

--- Modifier clicks come from Shortcuts. A plain click still adjusts the count.
local function taskShortcutClick(where, node, button, nodeId)
    if generatedClickConsumed(node, button, nodeId) then return end
    if TaskTracker.RunRowShortcut and TaskTracker.RunRowShortcut(where, node, button) then
        return
    end
    if IsEditMode() then return end
    local id = nodeId or (node and node.id)
    if not id or not TaskTracker.AdjustTaskCount then return end
    local requireShift = (TaskTrackerDB and TaskTrackerDB.requireShiftRowAdjustClicks ~= false) and true or false
    if where == "progress" then
        if requireShift then return end
    elseif requireShift and not IsShiftKeyDown() then
        return
    end
    if button == "RightButton" then
        TaskTracker.AdjustTaskCount(id, -1)
    elseif button == "LeftButton" then
        TaskTracker.AdjustTaskCount(id, 1)
    end
end

-- Rebind a pooled edit-mode task row (widgets already exist from the first build).
local function BindPooledEditTaskRow(row, rowFrames, node, capturedID, index, width, yOff, rh, baseRh, useGrow, subtitle, subLineH, nameLift, labelW)
    local progDone, progMax, progIsDone = TaskTracker.GetNodeProgress(node)
    local leftPad = TaskTracker.GetListPadLeft()
    local manualBar = TaskTracker.TaskRowShowsManualAutomationBar(node)
    if row._ttBar then
        TaskTracker.SetColor(row._ttBar, manualBar and "taskBarManual" or "taskBarAutomated")
    end
    if row._ttCheck then
        sizeCheckboxIcon(row._ttCheck, baseRh)
        setCheckboxIconState(row._ttCheck, progIsDone, false)
    end
    if row._ttBg then
        TaskTracker.SetColor(row._ttBg, RowStripeKey(node, index))
        applyHereFade(row, node)
    end

    local resetTag = TaskTracker.GetNodeResetTag(node)
    local titlePlain = (TaskTracker.GetTaskListTitlePlain and TaskTracker.GetTaskListTitlePlain(node))
        or (node.name or "")
    local titleColorKey = TaskTracker.IsTaskEffectivelyDone(node) and "complete" or "textTask"
    if row._ttProgStr then
        row._ttProgStr:SetText(taskProgressText(node, progDone, progMax))
    end

    if row._ttPickBtn then
        WirePickUpButton(row._ttPickBtn, node)
    end
    if row._ttEditBtn then
        local chromeEnter = row._ttEditBtn._ttChromeEnter
        local chromeLeave = row._ttEditBtn._ttChromeLeave
        row._ttEditBtn:SetScript("OnEnter", function(self)
            if chromeEnter then chromeEnter(self) end
            if node.liveShareRole == "receiver" then
                ShowBesideTip(self, "Synced task", "Left-click to see who sent this.", "Alt-click to permanently delete this task.")
            else
                ShowBesideTip(self, "Edit task", "Left-click to open the task editor.", "Alt-click to permanently delete this task.")
            end
        end)
        row._ttEditBtn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            if chromeLeave then chromeLeave(self) end
        end)
        row._ttEditBtn:SetScript("OnClick", function()
            if IsAltKeyDown() then
                StaticPopupDialogs["TASKTRACKER_DEL_TASK_ROW"] = {
                    text    = "Permanently delete '" .. (node.name or "task") .. "'?",
                    button1 = "Delete",
                    button2 = "Cancel",
                    OnAccept = function()
                        TaskTracker.RemoveNode(node.id)
                        if TaskTracker.RefreshList then TaskTracker.RefreshList() end
                    end,
                    timeout      = 0,
                    whileDead    = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("TASKTRACKER_DEL_TASK_ROW")
            elseif TaskTracker.taskDialog then
                TaskTracker.taskDialog.OpenEdit(node)
            end
        end)
    end

    local runnableCount = TaskTracker.CountRunnableCommandButtons and TaskTracker.CountRunnableCommandButtons(node) or 0
    refreshRowIconLayout(row, baseRh)
    applyRowCommandButtons(row, node, runnableCount)
    placeRowCommandIcons(row, titleLineIconLift(subtitle and subtitle ~= ""))
    if row._ttNoteBtn then
        row._ttNoteBtn:SetShown(shouldShowRowNoteIcon(node))
        if row._ttNoteBtn:IsShown() then
            wireNoteButtonOpensNotesOnly(row._ttNoteBtn, node)
        end
    end

    local fullTitle = ListLabelColored(titlePlain, titleColorKey, resetTag)
    local taskName = row._ttTaskName
    if taskName then
        local t = TaskTracker.GetTheme and TaskTracker.GetTheme()
        local barW = (t and t.taskAutomationBarWidth) or 3
        local textLeft = leftPad + barW + automationCheckGap() + checkboxIconSize(baseRh) + 6
        placeEditTaskTexts(row, taskName, {
            useGrow = useGrow,
            subtitle = subtitle,
            subColor = abundanceSubtitleColor(node, subtitle),
            subLineH = subLineH,
            labelW = labelW or math.max(40, width - 160),
            textLeft = textLeft,
            leftPad = leftPad,
            baseRh = baseRh,
            fullTitle = fullTitle,
            titlePlain = titlePlain,
            titleColorKey = titleColorKey,
            resetTag = resetTag,
        })
        if useGrow then
            row:SetHeight(rh)
        end
    end

    local rowHit = row._ttRowHit
    if rowHit then
        local stripW = (row._ttLeftStrip and row._ttLeftStrip:GetWidth()) or 0
        anchorRowHitLeftOfIconRail(rowHit, row, leftPad + stripW + 6)
        rowHit:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        rowHit:SetScript("OnClick", function(_, button)
            taskShortcutClick("taskName", node, button, capturedID)
        end)
        if row._ttProgHit then
            row._ttProgHit:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
            row._ttProgHit:SetScript("OnClick", function(_, button)
                taskShortcutClick("progress", node, button, capturedID)
            end)
        end
        if TaskTracker.RegisterListRowTooltip then
            TaskTracker.RegisterListRowTooltip(rowHit, nil, node)
        end
    end

    row._ttKind = "editTask"
    row._ttNode = node
    table.insert(rowFrames, row)
    return yOff + rh + TaskTracker.GetSpacingBetweenTasks()
end

-- ─────────────────────────────────────
-- Render task row
-- ─────────────────────────────────────
local function RenderTaskRow(scrollChild, rowFrames, node, parent, index, rowW, yOff, level)
    local db     = TaskTrackerDB
    local indent = GetIndent(level)
    local width  = rowW - indent
    local t      = TaskTracker.GetTheme()

    if TaskTracker.IsCollectionFarmTaskListed and not TaskTracker.IsCollectionFarmTaskListed(node) then
        return yOff
    end
    if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then
        return yOff
    end
    if db.hideCompleted and TaskTracker.IsTaskEffectivelyDone(node) and not completedRowStays(node) then
        return yOff
    end

    local baseRh   = RowHeight()
    local useGrow  = TaskTracker.GetTaskLabelOverflowMode and TaskTracker.GetTaskLabelOverflowMode() == "grow"
    local subtitle = TaskTracker.GetAdvancedTaskSubtitle and TaskTracker.GetAdvancedTaskSubtitle(node)
    local subLineH = subtitle and (TaskTracker.GetTaskFontSize and TaskTracker.GetTaskFontSize() or 11) or 0
    local nameLift = (subtitle and not useGrow) and 5 or 0
    local labelW = editLabelWidth(width, baseRh, true)
    local titlePlainEarly = (TaskTracker.GetTaskListTitlePlain and TaskTracker.GetTaskListTitlePlain(node)) or (node.name or "")
    local titleColorEarly = TaskTracker.IsTaskEffectivelyDone(node) and "complete" or "textTask"
    local fullTitleEarly = ListLabelColored(titlePlainEarly, titleColorEarly, TaskTracker.GetNodeResetTag(node))

    -- Height comes from the offscreen measure, not the row's own font string.
    -- That string still has the previous task's size on the frame we just showed.
    local rh
    if useGrow then
        local fontObj = t.fontNormal or "GameFontNormalSmall"
        local titleH = measureWrapHeight(fontObj, fullTitleEarly, labelW, "TOP")
        local subH = 0
        if subtitle and subtitle ~= "" then
            if node.generatedTask then
                subH = subLineH
            else
                subH = measureWrapHeight("GameFontDisableSmall", subtitle, labelW, "TOP")
            end
        end
        rh = math.max(baseRh, titleH + (subH > 0 and (2 + subH) or 0) + 4)
    else
        rh = baseRh + ((subtitle and subtitle ~= "") and subLineH or 0)
    end

    local row = AcquirePooledFrame("editTask", "Frame", scrollChild)
    row:SetSize(width, rh)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", indent, -yOff)
    row._ttNodeId = node.id
    local capturedID = node.id

    if row._ttEditBuilt then
        return BindPooledEditTaskRow(row, rowFrames, node, capturedID, index, width, yOff, rh, baseRh, useGrow, subtitle, subLineH, nameLift, labelW)
    end

    local rowHit = CreateFrame("Button", nil, row)
    rowHit:EnableMouse(true)
    rowHit:SetFrameLevel(1)

    row._ttBg = TaskTracker.MakeRowBg(row, index)
    TaskTracker.SetColor(row._ttBg, RowStripeKey(node, index))
    applyHereFade(row, node)
    TaskTracker.MakeEdge(row, "BOTTOM", "border")

    local progDone, progMax, progIsDone = TaskTracker.GetNodeProgress(node)

    local leftPad = TaskTracker.GetListPadLeft()
    local barW    = t.taskAutomationBarWidth or 3
    local barH    = math.max(12, baseRh - 6)

    -- Fixed-height strip: checkbox + bar never grow when the title wraps.
    local leftStrip = CreateFrame("Frame", nil, row)
    if useGrow then
        leftStrip:SetPoint("TOPLEFT", row, "TOPLEFT", leftPad, -nameLift)
    else
        leftStrip:SetPoint("LEFT", row, "LEFT", leftPad, nameLift)
    end

    local bar = leftStrip:CreateTexture(nil, "OVERLAY")
    bar:SetWidth(barW)
    bar:SetHeight(barH)
    if useGrow then
        bar:SetPoint("TOPLEFT", leftStrip, "TOPLEFT", 0, math.max(0, math.floor((baseRh - barH) / 2 + 0.5)))
    else
        bar:SetPoint("LEFT", leftStrip, "LEFT", 0, 0)
    end
    local manualBar = TaskTracker.TaskRowShowsManualAutomationBar(node)
    TaskTracker.SetColor(bar, manualBar and "taskBarManual" or "taskBarAutomated")

    local check = makeCheckboxIcon(leftStrip, baseRh)
    check:SetPoint("LEFT", bar, "RIGHT", automationCheckGap(), 0)
    setCheckboxIconState(check, progIsDone, false)

    local stripW = barW + automationCheckGap() + check:GetWidth()
    leftStrip:SetSize(stripW, baseRh)

    local stripHit = CreateFrame("Button", nil, leftStrip)
    stripHit:SetFrameLevel(15)
    stripHit:SetAllPoints(leftStrip)
    stripHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    stripHit:SetScript("OnClick", function(_, button)
        if IsEditMode() then return end
        if button == "RightButton" then
            TaskTracker.TaskCheckboxTurnOff(capturedID)
        else
            TaskTracker.ToggleTaskCheckboxDone(capturedID)
        end
    end)
    if TaskTracker.RegisterListRowTooltip then
        TaskTracker.RegisterListRowTooltip(stripHit, nil, node)
    end

    local questStateIcon
    local questStateIconW = 0
    if TaskTracker.IsAdvancedTask and TaskTracker.IsAdvancedTask(node)
        and node.advanced and node.advanced.type == "quest"
        and not TaskTracker.IsTaskEffectivelyDone(node) then
        local atlas = questStateAtlasForQuestIds((node.advanced and node.advanced.questIds) or {})
        if atlas then
            questStateIcon = row:CreateTexture(nil, "OVERLAY")
            local sz = math.floor(baseRh * 0.42 + 0.5)
            sz = math.max(12, math.min(sz, 16))
            questStateIcon:SetSize(sz, sz)
            if useGrow then
                questStateIcon:SetPoint("TOPLEFT", leftStrip, "TOPRIGHT", 6, math.floor((baseRh - sz) / 2 + 0.5))
            else
                questStateIcon:SetPoint("LEFT", leftStrip, "RIGHT", 6, 0)
            end
            questStateIcon:SetAtlas(atlas, false)
            questStateIcon:Show()
            questStateIconW = sz + 4
        end
    end

    local taskName = TaskTracker.CreateScaledListFontString(row, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    taskName:SetJustifyH("LEFT")
    taskName:SetJustifyV(useGrow and "TOP" or "MIDDLE")
    if useGrow then
        local textColLeft = leftPad + stripW + 6 + ((questStateIconW > 0) and questStateIconW or 0)
        taskName:SetPoint("TOPLEFT", row, "TOPLEFT", textColLeft, -nameLift)
    else
        if questStateIconW > 0 and questStateIcon then
            taskName:SetPoint("LEFT", questStateIcon, "RIGHT", 4, 0)
        else
            taskName:SetPoint("LEFT", leftStrip, "RIGHT", 6, 0)
        end
    end

    local resetTag = TaskTracker.GetNodeResetTag(node)
    local titlePlain = (TaskTracker.GetTaskListTitlePlain and TaskTracker.GetTaskListTitlePlain(node))
        or (node.name or "")
    local titleColorKey = "textTask"
    if TaskTracker.IsTaskEffectivelyDone(node) then
        titleColorKey = "complete"
    end

    -- The second line is created in placeEditTaskTexts. A second font string
    -- here stayed on screen after that helper stored its own, so a reused row
    -- kept the previous task's subtitle (collapse does not rebuild the frame).

    local useProg = true
    local progStr = TaskTracker.CreateScaledListFontString(row, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    progStr:SetJustifyH("RIGHT")
    progStr:SetJustifyV(useGrow and "TOP" or "MIDDLE")
    if useProg then
        progStr:SetText(taskProgressText(node, progDone, progMax))
    else
        progStr:SetText("")
    end

    local runnableCmds = TaskTracker.GetRunnableCommandButtons(node)

    if IsEditMode() then
        local pickBtn = makeEqualsButton(row, editChromeSize(baseRh))
        WirePickUpButton(pickBtn, node)
        row._ttPickBtn = pickBtn

        local editTaskBtn = makeHammerButton(row, editChromeSize(baseRh))
        do
            local oEnter = editTaskBtn:GetScript("OnEnter")
            local oLeave = editTaskBtn:GetScript("OnLeave")
            editTaskBtn._ttChromeEnter = oEnter
            editTaskBtn._ttChromeLeave = oLeave
            editTaskBtn:SetScript("OnEnter", function(self)
                if oEnter then oEnter(self) end
                if node.liveShareRole == "receiver" then
                    ShowBesideTip(editTaskBtn, "Synced task", "Left-click to see who sent this.", "Alt-click to permanently delete this task.")
                else
                    ShowBesideTip(editTaskBtn, "Edit task", "Left-click to open the task editor.", "Alt-click to permanently delete this task.")
                end
            end)
            editTaskBtn:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                if oLeave then oLeave(self) end
            end)
        end
        editTaskBtn:SetScript("OnClick", function()
            if IsAltKeyDown() then
                StaticPopupDialogs["TASKTRACKER_DEL_TASK_ROW"] = {
                    text    = "Permanently delete '" .. (node.name or "task") .. "'?",
                    button1 = "Delete",
                    button2 = "Cancel",
                    OnAccept = function()
                        TaskTracker.RemoveNode(node.id)
                        if TaskTracker.RefreshList then TaskTracker.RefreshList() end
                    end,
                    timeout      = 0,
                    whileDead    = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("TASKTRACKER_DEL_TASK_ROW")
            elseif TaskTracker.taskDialog then
                TaskTracker.taskDialog.OpenEdit(node)
            end
        end)
        row._ttEditBtn = editTaskBtn
        placeEditTaskChrome(row, baseRh)

        -- Order (L→R): … | cmd | note | counts | edit | =
        progStr:SetPoint("RIGHT", editTaskBtn, "LEFT", -6, 0)
        pinFontWidth(progStr)
        if not useProg then
            progStr:SetText("")
            progStr:SetWidth(0)
        end

        local cmdCol, noteCol, sz = makeListIconColumnShell(row, baseRh, progStr, PROG_TO_NOTE_GAP)
        maybePlaceNoteIconButton(noteCol, sz, node)
        maybePlaceCommandFlyoutButton(cmdCol, sz, node, runnableCmds)
        if useGrow then
            taskName:SetPoint("TOPRIGHT", cmdCol, "TOPLEFT", -listLabelToIconGap(), -nameLift)
        else
            taskName:SetPoint("RIGHT", cmdCol, "LEFT", -listLabelToIconGap(), 0)
        end
    else
        local rPad = TaskTracker.GetListPadRight()
        local progHost = CreateFrame("Frame", nil, row)
        progHost:SetHeight(baseRh)
        if useGrow then
            progHost:SetPoint("TOPRIGHT", row, "TOPRIGHT", -rPad, 0)
        else
            progHost:SetPoint("RIGHT", row, "RIGHT", -rPad, 0)
        end
        progStr:ClearAllPoints()
        progStr:SetPoint("RIGHT", progHost, "RIGHT", 0, 0)
        progStr:SetJustifyH("RIGHT")
        progStr:SetJustifyV("MIDDLE")
        if not useProg then
            progStr:SetText("")
            progHost:SetWidth(2)
        else
            progStr:SetText(taskProgressText(node, progDone, progMax))
            local pw = (progStr.GetStringWidth and progStr:GetStringWidth() or 24) + 10
            progHost:SetWidth(math.min(math.max(pw, PROG_HOST_MIN_W), math.max(PROG_HOST_MAX_W, width * 0.38)))
        end

        local cmdCol, noteCol, sz = makeListIconColumnShell(row, baseRh, progHost, PROG_TO_NOTE_GAP)
        maybePlaceNoteIconButton(noteCol, sz, node)
        maybePlaceCommandFlyoutButton(cmdCol, sz, node, runnableCmds)
        if useGrow then
            taskName:SetPoint("TOPRIGHT", cmdCol, "TOPLEFT", -listLabelToIconGap(), -nameLift)
        else
            taskName:SetPoint("RIGHT", cmdCol, "LEFT", -listLabelToIconGap(), 0)
        end

        -- Modifier clicks use Shortcuts. A plain click still adjusts when Shift is not required.
        local progHit = CreateFrame("Button", nil, progHost)
        progHit:SetFrameLevel(50)
        progHit:EnableMouse(true)
        progHit:SetAllPoints(progHost)
        progHit:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        progHit:SetScript("OnClick", function(_, button)
            taskShortcutClick("progress", node, button, capturedID)
        end)
        row._ttProgHit = progHit
    end

    local fullTitle = ListLabelColored(titlePlain, titleColorKey, resetTag)
    placeRowCommandIcons(row, titleLineIconLift(subtitle and subtitle ~= ""))

    local textLeft = leftPad + (stripW or 0) + 6 + (questStateIconW or 0)
    placeEditTaskTexts(row, taskName, {
        useGrow = useGrow,
        subtitle = subtitle,
        subColor = abundanceSubtitleColor(node, subtitle),
        subLineH = subLineH,
        labelW = labelW,
        textLeft = textLeft,
        leftPad = leftPad,
        baseRh = baseRh,
        fullTitle = fullTitle,
        titlePlain = titlePlain,
        titleColorKey = titleColorKey,
        resetTag = resetTag,
    })
    if useGrow then
        row:SetHeight(rh)
    end

    rowHit:ClearAllPoints()
    anchorRowHitLeftOfIconRail(rowHit, row, leftPad + stripW + 6)
    rowHit:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    rowHit:SetScript("OnClick", function(_, button)
        taskShortcutClick("taskName", node, button, capturedID)
    end)
    rowHit:Lower()

    if TaskTracker.RegisterListRowTooltip then
        TaskTracker.RegisterListRowTooltip(rowHit, nil, node)
    end

    -- Cache pointers so we can update progress/checkboxes cheaply and reuse the frame.
    row._ttKind = "editTask"
    row._ttEditBuilt = true
    row._ttNode = node
    row._ttCheck = check
    row._ttProgStr = progStr
    row._ttBar = bar
    row._ttTaskName = taskName
    row._ttRowHit = rowHit
    row._ttLeftStrip = leftStrip

    table.insert(rowFrames, row)
    return yOff + rh + TaskTracker.GetSpacingBetweenTasks()
end

-- Great Vault: one compact line "269 / 259 / 246", right-aligned like other progress columns.
local function CreateVaultIlvlHolder(row, entry, t, rh)
    local holder = CreateFrame("Frame", nil, row)
    holder:SetHeight(rh)
    local fs = TaskTracker.CreateScaledListFontString(holder, "OVERLAY", t.fontNormal or "GameFontHighlightSmall")
    fs:SetJustifyH("RIGHT")
    fs:SetJustifyV("MIDDLE")
    TaskTracker.SetTextColor(fs, "textPrimary")
    local text = TaskTracker.FormatVaultIlvlRow(entry.vaultKind)
    if text == "- / - / -" and C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
        local ok, has = pcall(C_WeeklyRewards.HasAvailableRewards)
        if ok and has then
            text = "Collect Vault"
        end
    end
    fs:SetText(text)
    fs:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    local w = (fs.GetStringWidth and fs:GetStringWidth() or 80) + 10
    w = math.min(math.max(w, 36), 120)
    holder:SetWidth(w)
    holder._ttFs = fs
    return holder
end

local function CreateProfessionCatchupHolder(row, entry, t, rh)
    local holder = CreateFrame("Frame", nil, row)
    holder:SetHeight(rh)
    local fs = TaskTracker.CreateScaledListFontString(holder, "OVERLAY", t.fontNormal or "GameFontHighlightSmall")
    fs:SetJustifyH("RIGHT")
    fs:SetJustifyV("MIDDLE")
    TaskTracker.SetTextColor(fs, "textPrimary")
    local text = TaskTracker.FormatProfessionCatchupRow and TaskTracker.FormatProfessionCatchupRow(entry) or "-"
    fs:SetText(text)
    fs:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    local w = (fs.GetStringWidth and fs:GetStringWidth() or 40) + 10
    w = math.min(math.max(w, 28), 80)
    holder:SetWidth(w)
    holder._ttFs = fs
    return holder
end

--- Second line for a registry row. Mythic+ hints, and Abundance's Shard of Dundun count.
--- Returns text, colorKey.
local function registryRowSubtitle(entry)
    if entry and entry.type == "mplus_hint_row" and TaskTracker.GetMPlusRegistryRowSubtitle then
        return TaskTracker.GetMPlusRegistryRowSubtitle(entry) or "", "textSecondary"
    end
    if entry and entry.id == "s1_weekly_abundance" and TaskTracker.AbundanceShardLine then
        local text, ready = TaskTracker.AbundanceShardLine()
        return text or "", (ready and "complete" or "textSecondary")
    end
    return "", "textSecondary"
end

--- Edit mode reuses the registry row frame. The second line has to be rewritten
--- every time, or the previous row's text stays (Shard of Dundun on the first task).
local function syncEditRegistrySubtitle(row, entryLabel, text, colorKey, labelW, useGrow)
    if not row then return end
    local subFs = row._ttSubtitle
    if not text or text == "" then
        if subFs then
            subFs:Hide()
            subFs:SetText("")
        end
        return
    end
    if not subFs then
        subFs = TaskTracker.CreateScaledListFontString(row, "OVERLAY", "GameFontDisableSmall")
        subFs:SetJustifyH("LEFT")
        row._ttSubtitle = subFs
    end
    TaskTracker.SetTextColor(subFs, colorKey or "textSecondary")
    subFs:ClearAllPoints()
    subFs:SetWidth(math.max(40, labelW or 40))
    subFs:SetJustifyV("TOP")
    if entryLabel then
        subFs:SetPoint("TOPLEFT", entryLabel, "BOTTOMLEFT", 0, -2)
    end
    if useGrow then
        enableListWrap(subFs)
        subFs:SetText(text)
    else
        subFs:SetWordWrap(false)
        if subFs.SetMaxLines then subFs:SetMaxLines(1) end
        ApplyEllipsisPlainListLabel(subFs, text, labelW)
    end
    subFs:Show()
end

-- ─────────────────────────────────────
-- Render registry entry row
-- ─────────────────────────────────────
local function RenderRegistryRow(scrollChild, rowFrames, node, parent, index, rowW, yOff, level, underPowerSubtree)
    local db     = TaskTrackerDB
    local indent = GetIndent(level)
    local width  = rowW - indent
    local t      = TaskTracker.GetTheme()

    if not TaskTracker.IsRegistryRowTrackedForList(node.registryEntryId, underPowerSubtree) then return yOff end

    local entry = TaskTracker.RegistryByID[node.registryEntryId]
    local isVault = entry and entry.type == "vault_row"
    local isCatchup = entry and entry.type == "profession_catchup"
    local isMplusHint = entry and entry.type == "mplus_hint_row"
    local isDisplayOnly = isVault

    local cur, max, isDone, isOverridden = TaskTracker.GetRegistryEntryProgress(node.registryEntryId)
    local st = entry and db.registryState and db.registryState[entry.id]
    local userCountLock = st and st.userValue ~= nil and entry.type == "quest_count"
    local useOverrideColor = (isOverridden or userCountLock) and not isDisplayOnly
    if not isDisplayOnly and db.hideCompleted and isDone and not completedRowStays(node) then return yOff end

    local baseRh = RowHeight()
    local useGrow = TaskTracker.GetTaskLabelOverflowMode and TaskTracker.GetTaskLabelOverflowMode() == "grow"
    local mplusSubtitle, subColor = registryRowSubtitle(entry)
    local subLineH = (mplusSubtitle ~= "" and not useGrow) and (TaskTracker.GetTaskFontSize and TaskTracker.GetTaskFontSize() or 11) or 0
    local nameLift = 0
    local nameLiftGrow = (mplusSubtitle ~= "" and useGrow) and 5 or 0
    local regLabelW = editLabelWidth(width, baseRh, false)
    local rh
    if useGrow then
        local entryColorKeyEarly = "textRegistry"
        if useOverrideColor then
            entryColorKeyEarly = "override"
        elseif isDone and not isDisplayOnly then
            entryColorKeyEarly = "complete"
        end
        local fullEarly = ListLabelColored(TaskTracker.GetNodeLabel(node) or "", entryColorKeyEarly, TaskTracker.GetNodeResetTag(node))
        local labelH = measureWrapHeight(t.fontNormal or "GameFontNormalSmall", fullEarly, regLabelW, "TOP")
        local subH = 0
        if mplusSubtitle ~= "" then
            subH = measureWrapHeight("GameFontDisableSmall", mplusSubtitle, regLabelW, "TOP")
        end
        rh = math.max(baseRh, labelH + 4 + (subH > 0 and (2 + subH) or 0))
    else
        rh = baseRh + ((mplusSubtitle ~= "" and not useGrow) and (subLineH + 2) or 0)
    end
    local leftPad = TaskTracker.GetListPadLeft()

    local regKind = "editRegistry"
    if isVault then
        regKind = "editRegistryVault"
    elseif isCatchup then
        regKind = "editRegistryCatchup"
    end
    local row = AcquirePooledFrame(regKind, "Frame", scrollChild)
    row:SetSize(width, rh)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", indent, -yOff)
    row._ttNodeId = node.id

    if row._ttEditBuilt then
        row._ttNode = node
        row._ttRegistryEntryId = node.registryEntryId
        if row._ttBg then
            TaskTracker.SetColor(row._ttBg, RowStripeKey(node, index))
            applyHereFade(row, node)
        end
        if row._ttCheck then
            setCheckboxIconState(row._ttCheck, isDone, isOverridden or userCountLock)
        end
        if row._ttBar then
            TaskTracker.SetColor(row._ttBar, TaskTracker.RegistryRowShowsManualAutomationBar(node.registryEntryId) and "taskBarManual" or "taskBarAutomated")
        end
        local resetTag = TaskTracker.GetNodeResetTag(node)
        local label = TaskTracker.GetNodeLabel(node)
        local entryColorKey = "textRegistry"
        if useOverrideColor then
            entryColorKey = "override"
        elseif isDone and not isDisplayOnly then
            entryColorKey = "complete"
        end
        if row._ttEntryLabel then
            if not useGrow then
                ApplyEllipsisColoredListLabel(row._ttEntryLabel, label or "", entryColorKey, resetTag, regLabelW)
            else
                enableListWrap(row._ttEntryLabel)
                row._ttEntryLabel:SetText(ListLabelColored(label or "", entryColorKey, resetTag))
            end
        end
        syncEditRegistrySubtitle(row, row._ttEntryLabel, mplusSubtitle, subColor, regLabelW, useGrow)
        if row._ttProgress then
            if useOverrideColor then
                row._ttProgress:SetText(TaskTracker.WrapColor(tostring(cur).."/"..tostring(max), "override"))
            else
                row._ttProgress:SetText(TaskTracker.CountText(cur, max))
            end
        end
        if row._ttVaultHolder and row._ttVaultHolder._ttFs and entry and entry.vaultKind then
            local text = TaskTracker.FormatVaultIlvlRow(entry.vaultKind)
            if text == "- / - / -" and C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
                local ok, has = pcall(C_WeeklyRewards.HasAvailableRewards)
                if ok and has then
                    text = "Collect Vault"
                end
            end
            row._ttVaultHolder._ttFs:SetText(text)
        end
        if row._ttCatchupHolder and row._ttCatchupHolder._ttFs then
            local text = TaskTracker.FormatProfessionCatchupRow and TaskTracker.FormatProfessionCatchupRow(entry) or "-"
            row._ttCatchupHolder._ttFs:SetText(text)
        end
        if row._ttPickBtn then
            WirePickUpButton(row._ttPickBtn, node)
            local sz = editChromeSize(baseRh)
            sizeEditChrome(row._ttPickBtn, sz)
            anchorGlyphOnTitleLine(row._ttPickBtn, row, 0, -TaskTracker.GetListPadRight())
        end
        if row._ttRowHit and entry and TaskTracker.RegisterListRowTooltip then
            TaskTracker.RegisterListRowTooltip(row._ttRowHit, entry, node)
        end
        table.insert(rowFrames, row)
        return yOff + rh
    end

    local rowHit = CreateFrame("Button", nil, row)
    rowHit:EnableMouse(true)
    rowHit:SetFrameLevel(1)

    row._ttBg = TaskTracker.MakeRowBg(row, index)
    TaskTracker.SetColor(row._ttBg, RowStripeKey(node, index))
    applyHereFade(row, node)
    TaskTracker.MakeEdge(row, "BOTTOM", "border")

    -- Checkbox + automation bar (vault = special: no bar, no box — display-only row)
    local check
    local stripW = 0
    local leftStrip
    if not isDisplayOnly then
        local barW = t.taskAutomationBarWidth or 3
        local barH = math.max(12, baseRh - 6)

        leftStrip = CreateFrame("Frame", nil, row)
        if useGrow then
            leftStrip:SetPoint("TOPLEFT", row, "TOPLEFT", leftPad, -nameLiftGrow)
        else
            leftStrip:SetPoint("LEFT", row, "LEFT", leftPad, nameLift)
        end

        local bar = leftStrip:CreateTexture(nil, "OVERLAY")
        bar:SetWidth(barW)
        bar:SetHeight(barH)
        if useGrow then
            bar:SetPoint("TOPLEFT", leftStrip, "TOPLEFT", 0, math.max(0, math.floor((baseRh - barH) / 2 + 0.5)))
        else
            bar:SetPoint("LEFT", leftStrip, "LEFT", 0, 0)
        end
        TaskTracker.SetColor(bar, TaskTracker.RegistryRowShowsManualAutomationBar(node.registryEntryId) and "taskBarManual" or "taskBarAutomated")
        row._ttBar = bar

        check = makeCheckboxIcon(leftStrip, baseRh)
        check:SetPoint("LEFT", bar, "RIGHT", automationCheckGap(), 0)
        setCheckboxIconState(check, isDone, isOverridden or userCountLock)

        stripW = barW + automationCheckGap() + check:GetWidth()
        leftStrip:SetSize(stripW, baseRh)

        local stripHit = CreateFrame("Button", nil, leftStrip)
        stripHit:SetFrameLevel(15)
        stripHit:SetAllPoints(leftStrip)
        stripHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        stripHit:SetScript("OnClick", function(_, button)
            if IsEditMode() then return end
            local rid = node.registryEntryId
            if button == "RightButton" then
                TaskTracker.RegistryCheckboxTurnOff(rid)
            else
                TaskTracker.ToggleRegistryCheckboxDone(rid)
            end
        end)
        if TaskTracker.RegisterListRowTooltip then
            TaskTracker.RegisterListRowTooltip(stripHit, entry, node)
        end
    end

    local subFs

    -- Label (with optional quest-state icon for quest-tracking entries)
    local resetTag   = TaskTracker.GetNodeResetTag(node)
    local label      = TaskTracker.GetNodeLabel(node)
    local entryLabel = TaskTracker.CreateScaledListFontString(row, "OVERLAY", t.fontNormal or "GameFontNormalSmall")

    local questStateIcon
    local questStateIconW = 0
    if entry and check and leftStrip and not isDisplayOnly and not isDone
        and ((entry._ttQuestCount or 0) > 0 or (entry.quests and next(entry.quests) ~= nil)) then
        local ids = entry._ttQuestIds
        if not ids then
            ids = {}
            for qid in pairs(entry.quests or {}) do
                ids[#ids + 1] = qid
            end
        end
        local atlas = questStateAtlasForQuestIds(ids)
        if atlas then
            questStateIcon = row:CreateTexture(nil, "OVERLAY")
            local sz = math.floor(baseRh * 0.42 + 0.5)
            sz = math.max(12, math.min(sz, 16))
            questStateIcon:SetSize(sz, sz)
            if useGrow then
                questStateIcon:SetPoint("TOPLEFT", leftStrip, "TOPRIGHT", 6, math.floor((baseRh - sz) / 2 + 0.5))
            else
                questStateIcon:SetPoint("LEFT", leftStrip, "RIGHT", 6, 0)
            end
            questStateIcon:SetAtlas(atlas, false)
            questStateIcon:Show()
            questStateIconW = sz + 4
        end
    end

    local textColLeft = leftPad + stripW + 6 + ((questStateIconW > 0) and questStateIconW or 0)
    if check then
        if useGrow then
            entryLabel:SetPoint("TOPLEFT", row, "TOPLEFT", textColLeft, -nameLiftGrow)
            entryLabel:SetJustifyV("TOP")
        else
            entryLabel:SetPoint("LEFT", questStateIcon or leftStrip, "RIGHT", (questStateIcon and 4) or 6, 0)
            entryLabel:SetJustifyV((mplusSubtitle ~= "") and "TOP" or "MIDDLE")
        end
    else
        entryLabel:SetPoint("LEFT", row, "LEFT", leftPad, 0)
        entryLabel:SetJustifyV("MIDDLE")
    end
    entryLabel:SetJustifyH("LEFT")

    local entryPlain = label or ""
    local entryColorKey = "textRegistry"
    if useOverrideColor then
        entryColorKey = "override"
    elseif isDone and not isDisplayOnly then
        entryColorKey = "complete"
    end

    local runnableCmds = TaskTracker.GetRunnableCommandButtons(node)

    local pad   = TaskTracker.GetListPadRight()

    local progress
    local progressHost
    local vaultHolder
    local catchupHolder
    if isVault and entry.vaultKind then
        vaultHolder = CreateVaultIlvlHolder(row, entry, t, baseRh)
    elseif isCatchup then
        catchupHolder = CreateProfessionCatchupHolder(row, entry, t, baseRh)
    else
        progressHost = CreateFrame("Frame", nil, row)
        progressHost:SetHeight(baseRh)
        progress = TaskTracker.CreateScaledListFontString(progressHost, "OVERLAY", t.fontNormal or "GameFontHighlightSmall")
        progress:SetJustifyH("RIGHT")
        progress:SetJustifyV("MIDDLE")
        if useOverrideColor then
            progress:SetText(TaskTracker.WrapColor(tostring(cur).."/"..tostring(max), "override"))
        else
            progress:SetText(TaskTracker.CountText(cur, max))
        end
        progress:SetPoint("RIGHT", progressHost, "RIGHT", 0, 0)
        local phw = (progress.GetStringWidth and progress:GetStringWidth() or 40) + 10
        progressHost:SetWidth(math.min(math.max(phw, PROG_HOST_MIN_W), PROG_HOST_MAX_W))

        -- Clickable progress: shift-left opens set-number popup; (optionally) left/right adjust by 1.
        local progressHit = CreateFrame("Button", nil, progressHost)
        progressHit:SetFrameLevel(50)
        progressHit:EnableMouse(true)
        progressHit:SetAllPoints(progressHost)
        progressHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        progressHit:SetScript("OnClick", function(_, button)
            if IsEditMode() then return end
            local requireShift = (TaskTrackerDB and TaskTrackerDB.requireShiftRowAdjustClicks ~= false) and true or false
            if button == "LeftButton" and IsShiftKeyDown() and TaskTracker.ShowSetCountPopup then
                local autoC = (TaskTracker.GetRegistryEntryAutomatedValue and TaskTracker.GetRegistryEntryAutomatedValue(node.registryEntryId)) or cur
                local initTr, initAu = cur, autoC
                TaskTracker.ShowSetCountPopup({
                    title = (entry and entry.label or "Entry") .. " progress",
                    cur = cur,
                    autoCur = autoC,
                    max = max,
                    onAccept = function(tr, au)
                        if TaskTracker.ApplyRegistryProgressFromPopup then
                            TaskTracker.ApplyRegistryProgressFromPopup(node.registryEntryId, tr, au, initTr, initAu)
                        end
                    end,
                })
                return
            end
            if button == "RightButton" then
                TaskTracker.ApplyRegistryRowClick(node.registryEntryId, -1)
                return
            end
            if requireShift and not IsShiftKeyDown() then return end
            TaskTracker.ApplyRegistryRowClick(node.registryEntryId, 1)
        end)
    end

    local registryEntryLabelRight = nil -- cmdCol for entryLabel RIGHT anchor (M+ subtitle relayout)
    local pickBtn
    local ax = -pad
    if IsEditMode() then
        local sz = editChromeSize(baseRh)
        pickBtn = makeEqualsButton(row, sz)
        WirePickUpButton(pickBtn, node)
        row._ttPickBtn = pickBtn
        anchorGlyphOnTitleLine(pickBtn, row, 0, -pad)
        ax = -(pad + sz + 6)
    end

    local metricHolder = vaultHolder or catchupHolder
    if metricHolder then
        if IsEditMode() and pickBtn then
            metricHolder:SetPoint("RIGHT", pickBtn, "LEFT", -6, 0)
            local cmdCol, noteCol, sz = makeListIconColumnShell(row, baseRh, metricHolder, 8)
            maybePlaceNoteIconButton(noteCol, sz, node)
            maybePlaceCommandFlyoutButton(cmdCol, sz, node, runnableCmds)
            if useGrow then
                entryLabel:SetPoint("RIGHT", cmdCol, "LEFT", -8, 0)
            else
                entryLabel:SetPoint("RIGHT", cmdCol, "LEFT", -8, 0)
            end
            registryEntryLabelRight = cmdCol
        else
            metricHolder:SetPoint("RIGHT", row, "RIGHT", ax, 0)
            local cmdCol, noteCol, sz = makeListIconColumnShell(row, baseRh, metricHolder, 8)
            maybePlaceNoteIconButton(noteCol, sz, node)
            maybePlaceCommandFlyoutButton(cmdCol, sz, node, runnableCmds)
            entryLabel:SetPoint("RIGHT", cmdCol, "LEFT", -8, 0)
            registryEntryLabelRight = cmdCol
        end
    else
        if IsEditMode() and pickBtn then
            progressHost:SetPoint("RIGHT", pickBtn, "LEFT", -6, 0)
        else
            if useGrow then
                progressHost:SetPoint("TOPRIGHT", row, "TOPRIGHT", ax, 0)
            else
                progressHost:SetPoint("RIGHT", row, "RIGHT", ax, 0)
            end
        end

        local cmdCol, noteCol, sz = makeListIconColumnShell(row, baseRh, progressHost, PROG_TO_NOTE_GAP)
        maybePlaceNoteIconButton(noteCol, sz, node)
        maybePlaceCommandFlyoutButton(cmdCol, sz, node, runnableCmds)

        if useGrow then
            entryLabel:SetPoint("TOPRIGHT", cmdCol, "TOPLEFT", -8, 0)
        else
            entryLabel:SetPoint("RIGHT", cmdCol, "LEFT", -8, 0)
        end
        registryEntryLabelRight = cmdCol
    end

    local fullEntryLabel = ListLabelColored(entryPlain, entryColorKey, resetTag)
    if check and useGrow and not isDisplayOnly then
        enableListWrap(entryLabel)
        entryLabel:SetText(fullEntryLabel)
        if mplusSubtitle ~= "" then
            subFs = TaskTracker.CreateScaledListFontString(row, "OVERLAY", "GameFontDisableSmall")
            TaskTracker.SetTextColor(subFs, subColor or "textSecondary")
            subFs:SetJustifyH("LEFT")
            subFs:SetJustifyV("TOP")
            enableListWrap(subFs)
            subFs:SetPoint("TOPLEFT", entryLabel, "BOTTOMLEFT", 0, -2)
            subFs:SetWidth(regLabelW)
            subFs:SetText(mplusSubtitle)
        end
        row:SetHeight(rh)
    else
        ApplyEllipsisColoredListLabel(entryLabel, entryPlain, entryColorKey, resetTag, regLabelW)
        if mplusSubtitle ~= "" then
            subFs = TaskTracker.CreateScaledListFontString(row, "OVERLAY", "GameFontDisableSmall")
            TaskTracker.SetTextColor(subFs, subColor or "textSecondary")
            subFs:SetJustifyH("LEFT")
            subFs:SetJustifyV("TOP")
            subFs:SetWordWrap(false)
            if subFs.SetMaxLines then subFs:SetMaxLines(1) end
            subFs:SetPoint("TOPLEFT", entryLabel, "BOTTOMLEFT", 0, -2)
            subFs:SetWidth(regLabelW)
            ApplyEllipsisPlainListLabel(subFs, mplusSubtitle, regLabelW)
        end
    end

    -- M+ hint rows: title/subtitle stay anchored to the row; strip aligns to vertical center of text block
    -- (not to row center — avoids moving label with strip).
    if leftStrip and mplusSubtitle ~= "" then
        local topPad = useGrow and nameLiftGrow or 2
        if not useGrow then
            entryLabel:ClearAllPoints()
            -- Width, not a second RIGHT point. A second point drops the Y offset
            -- and the second line draws on another row.
            entryLabel:SetWidth(regLabelW)
            entryLabel:SetPoint("TOPLEFT", row, "TOPLEFT", textColLeft, -topPad)
            entryLabel:SetJustifyV("TOP")
            entryLabel:SetJustifyH("LEFT")
            local ew = entryLabel:GetWidth()
            if not ew or ew < 2 then
                ew = math.max(48, width - 100)
            end
            ApplyEllipsisColoredListLabel(entryLabel, entryPlain, entryColorKey, resetTag, ew)
            if subFs then
                subFs:ClearAllPoints()
                subFs:SetPoint("TOPLEFT", entryLabel, "BOTTOMLEFT", 0, -2)
                local cap = math.floor(width * 0.62 + 0.5)
                local labelW = math.max(40, math.min(cap, ew))
                subFs:SetWidth(labelW)
                ApplyEllipsisPlainListLabel(subFs, mplusSubtitle, labelW)
            end
        end
        local th = entryLabel:GetStringHeight() or 0
        local sh = (subFs and subFs:IsShown() and (subFs:GetStringHeight() or 0)) or 0
        local blockH = th + (sh > 0 and (2 + sh) or 0)
        local blockCenter = topPad + blockH / 2
        local inset = math.max(0, math.floor(blockCenter - baseRh / 2 + 0.5))
        leftStrip:ClearAllPoints()
        leftStrip:SetPoint("TOPLEFT", row, "TOPLEFT", leftPad, -inset)
    elseif isMplusHint and leftStrip then
        leftStrip:ClearAllPoints()
        if useGrow then
            leftStrip:SetPoint("TOPLEFT", row, "TOPLEFT", leftPad, -nameLiftGrow)
        else
            leftStrip:SetPoint("LEFT", row, "LEFT", leftPad, 0)
        end
    end

    if isDisplayOnly then
        anchorRowHitLeftOfIconRail(rowHit, row, leftPad)
        rowHit:RegisterForClicks("LeftButtonUp")
        rowHit:SetScript("OnClick", function() end)
    elseif check then
        local leftPad = TaskTracker.GetListPadLeft()
        local bw = t.taskAutomationBarWidth or 3
        local sw = bw + automationCheckGap() + check:GetWidth() + 6
        anchorRowHitLeftOfIconRail(rowHit, row, leftPad + sw)
        rowHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        rowHit:SetScript("OnClick", function(_, button)
            local requireShift = (TaskTrackerDB and TaskTrackerDB.requireShiftRowAdjustClicks ~= false) and true or false
            if button == "LeftButton" and IsControlKeyDown() and TaskTracker.ClearRegistryEntryManual then
                TaskTracker.ClearRegistryEntryManual(node.registryEntryId)
                return
            end
            if button == "RightButton" then
                TaskTracker.ApplyRegistryRowClick(node.registryEntryId, -1)
                return
            end
            if requireShift and not IsShiftKeyDown() then return end
            TaskTracker.ApplyRegistryRowClick(node.registryEntryId, 1)
        end)
    else
        anchorRowHitLeftOfIconRail(rowHit, row, leftPad)
        rowHit:RegisterForClicks("LeftButtonUp")
        rowHit:SetScript("OnClick", function() end)
    end
    rowHit:Lower()

    if entry and TaskTracker.RegisterListRowTooltip then
        TaskTracker.RegisterListRowTooltip(rowHit, entry, node)
    end

    -- Cache pointers so we can update counts/checkboxes cheaply and reuse the frame.
    row._ttKind = regKind
    row._ttEditBuilt = true
    row._ttNode = node
    row._ttRegistryEntryId = node.registryEntryId
    row._ttCheck = check
    row._ttProgress = progress
    row._ttVaultHolder = vaultHolder
    row._ttCatchupHolder = catchupHolder
    row._ttEntryLabel = entryLabel
    row._ttSubtitle = subFs
    row._ttRowHit = rowHit

    table.insert(rowFrames, row)
    return yOff + rh
end

-- ─────────────────────────────────────
-- Recursive node renderer
-- ─────────────────────────────────────
local function RenderNode(scrollChild, rowFrames, node, parent, index, rowW, yOff, level, underPowerSubtree)
    underPowerSubtree = underPowerSubtree or false
    if node.type == "root" then
        if node.children then
            for i, child in ipairs(node.children) do
                local y0 = yOff
                yOff = RenderNode(scrollChild, rowFrames, child, node, i, rowW, yOff, level, underPowerSubtree)
                if IsEditMode() and yOff > y0 and AllowEditInsert(node, child) then
                    yOff = RenderInsertZone(scrollChild, rowFrames, rowW, yOff, child.id, node.id, level)
                end
            end
        end

    elseif node.type == "group" then
        if TaskTracker.IsHiddenByZoneFilter and TaskTracker.IsHiddenByZoneFilter(node) then
            return yOff
        end
        if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
            return yOff
        end
        if ModuleGroupFullyDisabled(node) then
            return yOff
        end
        if TaskTracker.ProfessionModuleSubgroupVisible
            and not TaskTracker.ProfessionModuleSubgroupVisible(node) then
            return yOff
        end

        local childUnderPower = underPowerSubtree or (node.moduleGroupKey == "power")

        -- Hide completed: omit the whole group (header + subtree) when every countable leaf is done.
        local dbHc = TaskTrackerDB
        if dbHc and dbHc.hideCompleted and TaskTracker.GetNodeLeafProgress
            and not (TaskTracker.WorldQuestRowIgnoresHideCompleted and TaskTracker.WorldQuestRowIgnoresHideCompleted(node)) then
            local leafDone, leafTotal = TaskTracker.GetNodeLeafProgress(node, childUnderPower)
            if leafTotal > 0 and leafDone >= leafTotal then
                if not (TaskTracker.GroupHideCompletedHasSubtreeHoldouts
                    and TaskTracker.GroupHideCompletedHasSubtreeHoldouts(node, childUnderPower)) then
                    return yOff
                end
            end
        end

        yOff = RenderGroupHeader(scrollChild, rowFrames, node, parent, index, rowW, yOff, level, childUnderPower)

        if node.expanded and node.children then
            for i, child in ipairs(node.children) do
                local y0 = yOff
                yOff = RenderNode(scrollChild, rowFrames, child, node, i, rowW, yOff, level + 1, childUnderPower)
                if IsEditMode() and yOff > y0 and AllowEditInsert(node, child) then
                    yOff = RenderInsertZone(scrollChild, rowFrames, rowW, yOff, child.id, node.id, level + 1)
                end
            end
            if #node.children == 0 and IsEditMode() and AllowEditInsert(node, nil) then
                yOff = RenderInsertZone(scrollChild, rowFrames, rowW, yOff, nil, node.id, level + 1)
            end
        end

        yOff = yOff + TaskTracker.GetSpacingGroupSection()

    elseif node.type == "task" then
        if TaskTracker.IsHiddenByZoneFilter and TaskTracker.IsHiddenByZoneFilter(node) then
            return yOff
        end
        if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
            return yOff
        end
        if TaskTracker.IsCollectionFarmTaskListed and not TaskTracker.IsCollectionFarmTaskListed(node) then
            return yOff
        end
        if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then
            return yOff
        end
        yOff = RenderTaskRow(scrollChild, rowFrames, node, parent, index, rowW, yOff, level)

    elseif node.type == "registryEntry" then
        if TaskTracker.IsHiddenByZoneFilter and TaskTracker.IsHiddenByZoneFilter(node) then
            return yOff
        end
        if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
            return yOff
        end
        yOff = RenderRegistryRow(scrollChild, rowFrames, node, parent, index, rowW, yOff, level, underPowerSubtree)
    end

    return yOff
end

-- ─────────────────────────────────────
-- RefreshList
-- ─────────────────────────────────────

-- ─────────────────────────────────────
-- Perf instrumentation (dev-only; gated by DB flag)
-- ─────────────────────────────────────
local function NowMs()
    if debugprofilestop then
        return debugprofilestop()
    end
    local t = (GetTime and GetTime()) or 0
    return t * 1000
end

local function PerfEnabled()
    local db = TaskTrackerDB
    return db and db.debugPerf == true
end

local function PerfStore(slotKey, dtMs)
    if not PerfEnabled() then return end
    TaskTracker._ttPerf = TaskTracker._ttPerf or {}
    local p = TaskTracker._ttPerf
    p[slotKey] = dtMs
    p.t = NowMs()
end

--- True when the scrollable task list is on-screen (not hidden / minimized).
local function ShouldPaintTaskList()
    local p = TaskTracker.panel
    if not p or not p:IsShown() then return false end
    if TaskTrackerDB and TaskTrackerDB.minimized then return false end
    return true
end

-- Browse-mode list helpers (file scope so RefreshListExecute does not recreate them).
local function ClearVirtualizedFrames()
    local active = TaskTracker._ttListActive
    if not active then return end
    local pools = TaskTracker._ttListPools or {}
    for _, slot in pairs(active) do
        local f = slot and slot.frame
        if f then
            HidePooledFrame(f)
            local kind = f._ttKind
            if kind then
                pools[kind] = pools[kind] or {}
                table.insert(pools[kind], f)
            end
        end
    end
    wipe(active)
    TaskTracker._ttListPools = pools
    TaskTracker._ttPaintVisibleList = nil
end

local function ClearLegacyRows()
    local prevRows = TaskTracker.rowFrames
    if prevRows then
        -- Release last-to-first. The pool is a stack, so the next paint pops the same
        -- frame back onto the same row. Forward release swapped frames every refresh,
        -- and each frame still reported the previous row's width, so text and icons jumped.
        for i = #prevRows, 1, -1 do
            ReleasePooledFrame(prevRows[i])
        end
        TaskTracker.rowFrames = nil
    end
    -- A paint that errors after Show and before insert leaves that frame on the
    -- scroll child. It is not in rowFrames, so the next list draws on top of it.
    local scrollChild = TaskTracker.scrollChild
    if not scrollChild or not scrollChild.GetChildren then return end
    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        local kind = child and child._ttKind
        if type(kind) == "string" and kind:sub(1, 4) == "edit" and child.IsShown and child:IsShown() then
            ReleasePooledFrame(child)
        end
    end
end

local function poolAcquire(kind)
    local pools = TaskTracker._ttListPools
    pools[kind] = pools[kind] or {}
    local p = pools[kind]
    local f = table.remove(p)
    if f then
        f:SetParent(TaskTracker.scrollChild)
        f:ClearAllPoints()
    end
    return f
end

local function poolRelease(frame)
    if not frame then return end
    local kind = frame._ttKind
    HidePooledFrame(frame)
    if not kind then
        return
    end
    local pools = TaskTracker._ttListPools
    pools[kind] = pools[kind] or {}
    table.insert(pools[kind], frame)
end

local function clearAllActiveVirtualFrames()
    local active = TaskTracker._ttListActive
    if not active then return end
    for _, slot in pairs(active) do
        if slot and slot.frame then
            poolRelease(slot.frame)
        end
    end
    wipe(active)
end

local function AttachDynamicRowTooltip(frame, getEntry, getNode)
    if not frame then return end
    frame:SetScript("OnEnter", function(self)
        if TaskTrackerDB and TaskTrackerDB.showRowTooltips == false then return end
        self._ttRowActive = true
        self._ttDebugDown = TaskTracker.RowDebugIdsEnabled and TaskTracker.RowDebugIdsEnabled() and IsControlKeyDown and IsControlKeyDown()
        if TaskTracker.RefreshListRowTooltip then
            TaskTracker.RefreshListRowTooltip(self, getEntry and getEntry() or nil, getNode and getNode() or nil)
        end
        self:SetScript("OnUpdate", function(f)
            if not f._ttRowActive or (TaskTrackerDB and TaskTrackerDB.showRowTooltips == false) then return end
            if TaskTracker.RowDebugIdsEnabled and TaskTracker.RowDebugIdsEnabled() then
                local a = IsControlKeyDown and IsControlKeyDown()
                if a ~= f._ttDebugDown then
                    f._ttDebugDown = a
                    if TaskTracker.RefreshListRowTooltip then
                        TaskTracker.RefreshListRowTooltip(f, getEntry and getEntry() or nil, getNode and getNode() or nil)
                    end
                    return
                end
            elseif f._ttDebugDown then
                f._ttDebugDown = false
                if TaskTracker.RefreshListRowTooltip then
                    TaskTracker.RefreshListRowTooltip(f, getEntry and getEntry() or nil, getNode and getNode() or nil)
                end
                return
            end
            if TaskTracker.PlaceListRowTooltipBesideList then
                TaskTracker.PlaceListRowTooltipBesideList()
            end
        end)
    end)
    frame:SetScript("OnLeave", function(self)
        self._ttRowActive = nil
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)
end

local function BuildRenderModel(tree, rowW)
    local t0 = NowMs()
    local rows = {}
    local y = TaskTracker.GetListPadTop and TaskTracker.GetListPadTop() or 0
    local dbLocal = TaskTrackerDB
    local useGrow = TaskTracker.GetTaskLabelOverflowMode and TaskTracker.GetTaskLabelOverflowMode() == "grow"

    local function push(kind, node, level, frameH, advanceH, extra)
        rows[#rows + 1] = {
            kind = kind,
            node = node,
            id = node and node.id,
            level = level or 0,
            y = y,
            h = frameH or 0,      -- actual frame height (hitbox)
            adv = advanceH or 0,  -- y-advance including spacing
            extra = extra,
        }
        y = y + (advanceH or frameH or 0)
    end

    local function measureTaskHeight(node, width)
        local baseRh = RowHeight()
        local subtitle = TaskTracker.GetAdvancedTaskSubtitle and TaskTracker.GetAdvancedTaskSubtitle(node)
        local subLineH = subtitle and (TaskTracker.GetTaskFontSize and TaskTracker.GetTaskFontSize() or 11) or 0
        local nameLift = (subtitle and not useGrow) and 5 or 0
        if not useGrow then
            local subPx = (subtitle and subtitle ~= "") and subLineH or 0
            return baseRh + subPx, subPx
        end

        local resetTag = TaskTracker.GetNodeResetTag(node)
        local titlePlain = (TaskTracker.GetTaskListTitlePlain and TaskTracker.GetTaskListTitlePlain(node))
            or (node.name or "")
        local titleColorKey = TaskTracker.IsTaskEffectivelyDone(node) and "complete" or "textTask"
        local fullTitle = ListLabelColored(titlePlain, titleColorKey, resetTag)
        local titleH = measureWrapHeight(TaskTracker.GetTheme().fontNormal or "GameFontNormalSmall", fullTitle, width, "TOP")

        local subH = 0
        if subtitle then
            if node.generatedTask then
                subH = subLineH
            else
                subH = measureWrapHeight("GameFontDisableSmall", subtitle, width, "TOP")
            end
        end
        return math.max(baseRh, nameLift + titleH + (subH > 0 and (2 + subH) or 0) + 4), subH
    end

    local function measureRegistryHeight(node, width, fullLabel, subText)
        local baseRh = RowHeight()
        if subText == nil then subText = "" end
        local subLineH = 0
        if subText ~= "" then
            subLineH = (TaskTracker.GetTaskFontSize and TaskTracker.GetTaskFontSize() or 11)
        end
        if not useGrow then
            return baseRh + ((subLineH > 0) and (subLineH + 2) or 0)
        end
        local labelH = measureWrapHeight(TaskTracker.GetTheme().fontNormal or "GameFontNormalSmall", fullLabel, width, "TOP")
        local subH = 0
        if subText ~= "" then
            subH = measureWrapHeight("GameFontDisableSmall", subText, width, "TOP")
        end
        return math.max(baseRh, labelH + 4 + (subH > 0 and (2 + subH) or 0))
    end

    local function walk(n, level, index, underPw)
        underPw = underPw or false
        if n.type == "root" then
            if n.children then
                for i, ch in ipairs(n.children) do
                    walk(ch, level, i, underPw)
                end
            end
            return
        end
        if n.type == "group" then
            if n.readyToBuyVendor and readyToBuyZoneOnlyOn() then
                if not (TaskTracker.IsHereZoneNode and TaskTracker.IsHereZoneNode(n)) then
                    return
                end
            end
            if TaskTracker.IsHiddenByZoneFilter and TaskTracker.IsHiddenByZoneFilter(n) then return end
            if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(n) then return end
            if ModuleGroupFullyDisabled(n) then return end
            if TaskTracker.ProfessionModuleSubgroupVisible
                and not TaskTracker.ProfessionModuleSubgroupVisible(n) then
                return
            end
            local childUnder = underPw or (n.moduleGroupKey == "power")
            if dbLocal and dbLocal.hideCompleted and TaskTracker.GetNodeLeafProgress
                and not (TaskTracker.WorldQuestRowIgnoresHideCompleted and TaskTracker.WorldQuestRowIgnoresHideCompleted(n)) then
                local leafDone, leafTotal = TaskTracker.GetNodeLeafProgress(n, childUnder)
                if leafTotal > 0 and leafDone >= leafTotal then
                    if not (TaskTracker.GroupHideCompletedHasSubtreeHoldouts
                        and TaskTracker.GroupHideCompletedHasSubtreeHoldouts(n, childUnder)) then
                        return
                    end
                end
            end
            local catH = CatHeight()
            push("groupHeader", n, level, catH, catH + TaskTracker.GetSpacingGroupHeader(), { index = index, underPower = childUnder })
            if n.expanded and n.children then
                for i, ch in ipairs(n.children) do
                    walk(ch, level + 1, i, childUnder)
                end
            end
            y = y + TaskTracker.GetSpacingGroupSection()
            return
        end
        if n.type == "task" then
            if TaskTracker.IsHiddenByZoneFilter and TaskTracker.IsHiddenByZoneFilter(n) then return end
            if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(n) then return end
            if TaskTracker.IsCollectionFarmTaskListed and not TaskTracker.IsCollectionFarmTaskListed(n) then
                return
            end
            if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(n) then
                return
            end
            if dbLocal and dbLocal.hideCompleted and TaskTracker.IsTaskEffectivelyDone(n) and not completedRowStays(n) then
                return
            end
            local indent = GetIndent(level)
            local w = rowW - indent
            local subtitle = TaskTracker.GetAdvancedTaskSubtitle and TaskTracker.GetAdvancedTaskSubtitle(n)
            local resetTag = TaskTracker.GetNodeResetTag(n)
            local titlePlain = (TaskTracker.GetTaskListTitlePlain and TaskTracker.GetTaskListTitlePlain(n))
                or (n.name or "")
            local titleColorKey = TaskTracker.IsTaskEffectivelyDone(n) and "complete" or "textTask"
            local fullTitle = ListLabelColored(titlePlain, titleColorKey, resetTag)
            local rh, subPx = measureTaskHeight(n, math.max(40, w - 120))
            push("task", n, level, rh, rh + TaskTracker.GetSpacingBetweenTasks(), {
                index = index,
                subtitle = subtitle,
                subPx = subPx,
                resetTag = resetTag,
                titlePlain = titlePlain,
                titleColorKey = titleColorKey,
                fullTitle = fullTitle,
            })
            return
        end
        if n.type == "registryEntry" then
            if TaskTracker.IsHiddenByZoneFilter and TaskTracker.IsHiddenByZoneFilter(n) then return end
            if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(n) then return end
            if not TaskTracker.IsRegistryRowTrackedForList(n.registryEntryId, underPw) then return end
            local entry = TaskTracker.RegistryByID[n.registryEntryId]
            local isVault = entry and entry.type == "vault_row"
            local isCatchup = entry and entry.type == "profession_catchup"
            local isMplusHint = entry and entry.type == "mplus_hint_row"
            local isDisplayOnly = isVault
            local cur, max, isDone, isOverridden = TaskTracker.GetRegistryEntryProgress(n.registryEntryId)
            local st = entry and dbLocal and dbLocal.registryState and dbLocal.registryState[entry.id]
            local userCountLock = st and st.userValue ~= nil and entry and entry.type == "quest_count"
            local useOverrideColor = (isOverridden or userCountLock) and not isDisplayOnly
            if (not isDisplayOnly) and dbLocal and dbLocal.hideCompleted and isDone and not completedRowStays(n) then return end
            local resetTag = TaskTracker.GetNodeResetTag(n)
            local label = TaskTracker.GetNodeLabel(n) or ""
            local entryColorKey = "textRegistry"
            if useOverrideColor then
                entryColorKey = "override"
            elseif isDone and not isDisplayOnly then
                entryColorKey = "complete"
            end
            local full = ListLabelColored(label, entryColorKey, resetTag)
            local indent = GetIndent(level)
            local w = rowW - indent
            local mplusSubtitle, subColor = registryRowSubtitle(entry)
            local rh = measureRegistryHeight(n, math.max(40, w - 120), full, mplusSubtitle)
            push("registry", n, level, rh, rh, {
                index = index,
                isVault = isVault,
                isMplusHint = isMplusHint,
                isDisplayOnly = isDisplayOnly,
                resetTag = resetTag,
                labelPlain = label,
                labelColorKey = entryColorKey,
                fullLabel = full,
                mplusSubtitle = mplusSubtitle,
                subColor = subColor,
            })
            return
        end
    end

    walk(tree, 0, 1, false)
    PerfStore("layoutMs", NowMs() - t0)
    local bottom = TaskTracker.GetListPadBottom and TaskTracker.GetListPadBottom() or 0
    return rows, y + bottom
end

local function EnsureGroupHeaderFrame()
    local f = poolAcquire("groupHeader")
    if f then return f end
    local t = TaskTracker.GetTheme()
    local header = CreateFrame("Button", nil, TaskTracker.scrollChild)
    header._ttKind = "groupHeader"

    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    header._ttBg = bg

    TaskTracker.MakeEdge(header, "BOTTOM", "border")
    TaskTracker.MakeAccentBar(header)

    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("LEFT", header, "LEFT", (t.accentBarWidth or 3) + TaskTracker.GetListPadLeft(), 0)
    header._ttArrow = arrow

    local lbl = TaskTracker.CreateScaledListFontString(header, "OVERLAY", t.fontBold or "GameFontNormal", "header")
    lbl:SetPoint("LEFT", arrow, "RIGHT", listHeaderTitleGap(), 0)
    TaskTracker.SetTextColor(lbl, "textHeader")
    header._ttLabel = lbl

    local countTxt = TaskTracker.CreateScaledListFontString(header, "OVERLAY", t.fontNormal or "GameFontNormalSmall", "header")
    countTxt:SetPoint("RIGHT", header, "RIGHT", -TaskTracker.GetListPadRight(), 0)
    header._ttCountTxt = countTxt
    if header.SetClipsChildren then header:SetClipsChildren(true) end
    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    header:SetScript("OnClick", function(self, button)
        local node = self._ttNode
        if not node then return end
        if button == "RightButton" and node.readyToBuyVendor and TaskTracker.DismissReadyToBuyVendor then
            TaskTracker.DismissReadyToBuyVendor(node.readyToBuyVendor)
            return
        end
        if TaskTracker.ToggleGroupExpanded then
            TaskTracker.ToggleGroupExpanded(node)
        else
            node.expanded = not node.expanded
        end
        if TaskTracker.MarkListLayoutDirty then
            TaskTracker.MarkListLayoutDirty()
        end
        if TaskTracker.RefreshListNow then
            TaskTracker.RefreshListNow()
        else
            TaskTracker.RefreshList()
        end
    end)
    return header
end

-- Toy item 230850. Icon comes from the client item record so it stays the toy's picture.
local DELVE_BOT_TOY_ID = 230850
local delveBotButtons = {}

local function delveBotIconSize()
    return listRowCmdIconSize(RowHeight())
end

local function delveBotIconFile()
    local id
    if C_Item and C_Item.GetItemIconByID then
        local ok, v = pcall(C_Item.GetItemIconByID, DELVE_BOT_TOY_ID)
        if ok then id = v end
    end
    if (type(id) ~= "number" or id <= 0) and GetItemIcon then
        local ok, v = pcall(GetItemIcon, DELVE_BOT_TOY_ID)
        if ok then id = v end
    end
    if type(id) == "number" and id > 0 and not (issecretvalue and issecretvalue(id)) then
        return id
    end
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, DELVE_BOT_TOY_ID)
    end
    return nil
end

local function applyDelveBotCooldown(btn)
    if not btn or not btn.cooldown or not btn.cooldown.SetCooldown then return end
    if not (C_Item and C_Item.GetItemCooldown) then return end
    local ok, start, duration = pcall(C_Item.GetItemCooldown, DELVE_BOT_TOY_ID)
    if not ok then return end
    if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then return end
    start = tonumber(start) or 0
    duration = tonumber(duration) or 0
    btn.cooldown:SetCooldown(start, duration)
end

local function refreshShownDelveBotButtons(iconOnly)
    local icon = iconOnly and delveBotIconFile() or nil
    for i = 1, #delveBotButtons do
        local btn = delveBotButtons[i]
        if btn then
            if icon and TaskTracker.SetCommandButtonFileIcon then
                TaskTracker.SetCommandButtonFileIcon(btn, icon)
            end
            if not iconOnly and btn:IsShown() then
                applyDelveBotCooldown(btn)
            end
        end
    end
end

local function ensureDelveBotCooldownWatcher()
    if TaskTracker._ttDelveBotCdFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    f:SetScript("OnEvent", function(_, event, itemId)
        if event == "ITEM_DATA_LOAD_RESULT" then
            if itemId ~= DELVE_BOT_TOY_ID then return end
            refreshShownDelveBotButtons(true)
            return
        end
        local panel = TaskTracker.panel
        if not panel or not panel:IsShown() then return end
        refreshShownDelveBotButtons(false)
    end)
    TaskTracker._ttDelveBotCdFrame = f
end

local function setDelveBotToyAttribute(btn)
    if not btn or not btn.SetAttribute then return end
    if InCombatLockdown and InCombatLockdown() and btn.IsProtected and btn:IsProtected() then
        return
    end
    pcall(function()
        btn:SetAttribute("type", "toy")
        btn:SetAttribute("toy", DELVE_BOT_TOY_ID)
    end)
end

local function ensureDelveBotButton(header)
    if header._ttDelveBotBtn then return header._ttDelveBotBtn end
    if not TaskTracker.MakeSecureMacroIconButton then return nil end
    local sz = delveBotIconSize()
    local btn = TaskTracker.MakeSecureMacroIconButton(header, sz, sz, "delvebot", 1, {
        unnamedSecure = true,
        insecureMacro = true,
        iconFill = true,
        iconMargin = 1,
        noBorder = true,
        hoverBgKey = "rowHover",
    })
    btn:SetFrameLevel((header:GetFrameLevel() or 0) + 6)
    btn:Hide()
    setDelveBotToyAttribute(btn)
    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn.icon or btn)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    btn.cooldown = cd
    local icon = delveBotIconFile()
    if icon and TaskTracker.SetCommandButtonFileIcon then
        TaskTracker.SetCommandButtonFileIcon(btn, icon)
    end
    btn:SetScript("OnEnter", function(self)
        local owned = PlayerHasToy and PlayerHasToy(DELVE_BOT_TOY_ID)
        local limit = owned and "Out of combat." or "You don't have this toy yet."
        ShowBesideTip(self, "Delve-O-Bot 7001", "Calls a ride to a random Bountiful Delve.", limit)
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:SetScript("PostClick", function(self)
        applyDelveBotCooldown(self)
    end)
    delveBotButtons[#delveBotButtons + 1] = btn
    ensureDelveBotCooldownWatcher()
    header._ttDelveBotBtn = btn
    return btn
end

--- Show the toy button on the Delves header. Returns the button when it is shown.
--- Position matches a row command icon: left of the count, past the note slot.
local function placeDelveBotButton(header, show)
    local btn = header._ttDelveBotBtn
    if show then
        btn = btn or ensureDelveBotButton(header)
    end
    if not btn then return nil end
    if not show then
        btn:Hide()
        return nil
    end
    local sz = delveBotIconSize()
    if TaskTracker.SizeIconButton then
        TaskTracker.SizeIconButton(btn, sz, sz, LIST_ROW_ICON_OPT)
    else
        btn:SetSize(sz, sz)
    end
    if btn.cooldown and btn.icon then
        btn.cooldown:SetAllPoints(btn.icon)
    end
    setDelveBotToyAttribute(btn)
    local icon = delveBotIconFile()
    if icon and TaskTracker.SetCommandButtonFileIcon then
        TaskTracker.SetCommandButtonFileIcon(btn, icon)
    end
    applyDelveBotCooldown(btn)
    btn:Show()
    return btn
end

--- Same column as a waypoint button: count host, then the note slot, then this icon.
local function pinDelveBotWithWaypointColumn(header, countFs)
    local btn = header and header._ttDelveBotBtn
    if not btn or not btn:IsShown() or not countFs then return end
    local locked = InCombatLockdown and InCombatLockdown() and btn.IsProtected and btn:IsProtected()
    if locked then return end
    local pad = TaskTracker.GetListPadRight and TaskTracker.GetListPadRight() or 0
    local textW = (countFs.GetWidth and countFs:GetWidth()) or 0
    local hostW = math.min(math.max((tonumber(textW) or 0) + 10, PROG_HOST_MIN_W), PROG_HOST_MAX_W)
    local noteSz = listRowIconSize(RowHeight())
    local inset = pad + hostW + 8 + noteSz + NOTE_TO_CMD_GAP
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", header, "RIGHT", -inset, 0)
end

local function BindGroupHeader(frame, node, level, rowW, yOff, extra)
    if frame:GetParent() ~= TaskTracker.scrollChild then
        frame:SetParent(TaskTracker.scrollChild)
        frame._ttBk = nil
    end
    local indent = GetIndent(level)
    local width = rowW - indent
    local catH = CatHeight()
    local leafDone, leafTotal = 0, 0
    if extra and type(extra.powerLeafTotal) == "number" then
        leafDone = tonumber(extra.powerLeafDone) or 0
        leafTotal = extra.powerLeafTotal
    elseif TaskTracker.GetNodeLeafProgress then
        local up = extra and extra.underPower
        leafDone, leafTotal = TaskTracker.GetNodeLeafProgress(node, up)
    end
    local nid = (node and node.id) or 0
    local exp = node and node.expanded and true or false
    local nm = (node and node.name) or ""
    local displayName = nm
    if node and node.moduleGroupKey == "professions" and TaskTracker.GetProfessionsGroupDisplayName then
        displayName = TaskTracker.GetProfessionsGroupDisplayName(nm)
    end
    local summary = node and node.readyToBuySummary or ""
    local zoneOnly = node and node.readyToBuyHeader and readyToBuyZoneOnlyOn() and true or false
    if zoneOnly and node and type(node.children) == "table" then
        local shown = 0
        for i = 1, #node.children do
            local ch = node.children[i]
            if ch and ch.readyToBuyVendor and TaskTracker.IsHereZoneNode and TaskTracker.IsHereZoneNode(ch) then
                shown = shown + 1
            end
        end
        summary = tostring(shown)
    end
    local k = frame._ttBk
    if k
        and k.nid == nid
        and k.level == level
        and k.width == width
        and k.yOff == yOff
        and k.catH == catH
        and k.epoch == ListLayoutEpoch()
        and k.exp == exp
        and k.displayName == displayName
        and k.summary == summary
        and k.zoneOnly == zoneOnly
        and k.leafDone == leafDone
        and k.leafTotal == leafTotal
    then
        frame._ttNode = node
        if frame._ttBg then
            TaskTracker.SetColor(frame._ttBg, ListGroupHeaderBgKey(node, level))
            applyHereFade(frame, node)
        end
        frame:Show()
        return
    end
    if not k then
        k = {}
        frame._ttBk = k
    end
    k.nid, k.level, k.width, k.yOff = nid, level, width, yOff
    k.catH, k.epoch = catH, ListLayoutEpoch()
    k.exp, k.displayName, k.leafDone, k.leafTotal = exp, displayName, leafDone, leafTotal
    k.summary = summary
    k.zoneOnly = zoneOnly

    frame:SetSize(width, catH)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", TaskTracker.scrollChild, "TOPLEFT", indent, -yOff)
    frame._ttNode = node
    placeGroupHeaderTitles(frame)
    if TaskTracker.ApplyAccentBarWidth then
        TaskTracker.ApplyAccentBarWidth(frame)
    end
    local delveBtn = placeDelveBotButton(frame, node and node.moduleGroupKey == "seasonal_delves")
    if frame._ttCountTxt then
        frame._ttCountTxt:ClearAllPoints()
        frame._ttCountTxt:SetPoint("RIGHT", frame, "RIGHT", -TaskTracker.GetListPadRight(), 0)
    end
    TaskTracker.SetColor(frame._ttBg, ListGroupHeaderBgKey(node, level))
    applyHereFade(frame, node)
    TaskTracker.ApplyTwistIcon(frame._ttArrow, exp)
    frame._ttLabel:SetText(displayName)
    if summary ~= "" then
        frame._ttCountTxt:SetText(TaskTracker.WrapColor(summary, "textSecondary"))
        frame._ttCountTxt:SetWordWrap(false)
        frame._ttCountTxt:SetJustifyH("RIGHT")
        if frame._ttCountTxt.SetMaxLines then frame._ttCountTxt:SetMaxLines(1) end
        local textW = frame._ttCountTxt.GetUnboundedStringWidth and frame._ttCountTxt:GetUnboundedStringWidth()
            or frame._ttCountTxt:GetStringWidth()
        local maxW = math.max(80, (width or 0) - 120)
        frame._ttCountTxt:SetWidth(math.max(1, math.min(textW or maxW, maxW)))
        local labelStop = (delveBtn and delveBtn:IsShown()) and delveBtn or frame._ttCountTxt
        local labelGap = (delveBtn and delveBtn:IsShown()) and -listLabelToIconGap() or -8
        frame._ttLabel:SetPoint("RIGHT", labelStop, "LEFT", labelGap, 0)
        frame._ttLabel:SetWordWrap(false)
        frame._ttLabel:SetJustifyH("LEFT")
    else
        frame._ttCountTxt:SetText(TaskTracker.CountText(leafDone, leafTotal))
        local textW = frame._ttCountTxt.GetUnboundedStringWidth and frame._ttCountTxt:GetUnboundedStringWidth()
            or frame._ttCountTxt:GetStringWidth()
        frame._ttCountTxt:SetWidth(math.max(1, textW or 1))
        if delveBtn and delveBtn:IsShown() and frame._ttLabel then
            frame._ttLabel:SetPoint("RIGHT", delveBtn, "LEFT", -listLabelToIconGap(), 0)
            frame._ttLabel:SetWordWrap(false)
            frame._ttLabel:SetJustifyH("LEFT")
            if frame._ttLabel.SetMaxLines then frame._ttLabel:SetMaxLines(1) end
        end
    end
    pinDelveBotWithWaypointColumn(frame, frame._ttCountTxt)
    syncReadyToBuyHeader(frame, node)
    frame:Show()
end

local function EnsureTaskFrame()
    local f = poolAcquire("task")
    if f then return f end
    local row = CreateFrame("Frame", nil, TaskTracker.scrollChild)
    row._ttKind = "task"

    row._ttHit = CreateFrame("Button", nil, row)
    row._ttHit:EnableMouse(true)
    row._ttHit:SetFrameLevel(1)

    -- Background/edge
    row._ttBg = TaskTracker.MakeRowBg(row, 1)
    TaskTracker.MakeEdge(row, "BOTTOM", "border")

    local t = TaskTracker.GetTheme()
    local baseRh = RowHeight()

    local leftStrip = CreateFrame("Frame", nil, row)
    row._ttLeftStrip = leftStrip

    local bar = leftStrip:CreateTexture(nil, "OVERLAY")
    bar:SetWidth(t.taskAutomationBarWidth or 3)
    row._ttBar = bar

    local check = makeCheckboxIcon(leftStrip, baseRh)
    check:SetPoint("LEFT", bar, "RIGHT", automationCheckGap(), 0)
    row._ttCheck = check

    local stripHit = CreateFrame("Button", nil, leftStrip)
    stripHit:SetFrameLevel(15)
    stripHit:SetAllPoints(leftStrip)
    stripHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    stripHit:SetScript("OnClick", function(self, button)
        local rowFrame = self:GetParent() and self:GetParent():GetParent()
        local nodeId = rowFrame and rowFrame._ttNodeId
        if not nodeId or IsEditMode() then return end
        if button == "RightButton" then
            TaskTracker.TaskCheckboxTurnOff(nodeId)
        else
            TaskTracker.ToggleTaskCheckboxDone(nodeId)
        end
    end)
    row._ttStripHit = stripHit

    row._ttQuestStateIcon = row:CreateTexture(nil, "OVERLAY")
    row._ttQuestStateIcon:Hide()

    local taskName = TaskTracker.CreateScaledListFontString(row, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    taskName:SetJustifyH("LEFT")
    row._ttTaskName = taskName

    local subFs = TaskTracker.CreateScaledListFontString(row, "OVERLAY", "GameFontDisableSmall")
    TaskTracker.SetTextColor(subFs, "textSecondary")
    subFs:SetJustifyH("LEFT")
    subFs:SetJustifyV("TOP")
    subFs:Hide()
    row._ttSubtitle = subFs

    local progHost = CreateFrame("Frame", nil, row)
    progHost:SetHeight(baseRh)
    row._ttProgHost = progHost

    local progStr = TaskTracker.CreateScaledListFontString(progHost, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    progStr:SetJustifyH("RIGHT")
    progStr:SetJustifyV("MIDDLE")
    progStr:SetPoint("RIGHT", progHost, "RIGHT", 0, 0)
    row._ttProgStr = progStr

    local progHit = CreateFrame("Button", nil, progHost)
    progHit:SetFrameLevel(50)
    progHit:EnableMouse(true)
    progHit:SetAllPoints(progHost)
    progHit:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    progHit:SetScript("OnClick", function(self, button)
        local rf = self:GetParent() and self:GetParent():GetParent()
        local node = rf and rf._ttNode
        taskShortcutClick("progress", node, button, rf and rf._ttNodeId)
    end)
    row._ttProgHit = progHit

    local cmdCol, noteCol, sz = makeListIconColumnShell(row, baseRh, progHost, PROG_TO_NOTE_GAP)
    row._ttCmdCol, row._ttNoteCol, row._ttIconSz = cmdCol, noteCol, sz

    local noteBtn = TaskTracker.MakeIconButton(noteCol, sz, sz, LIST_ROW_ICON_OPT)
    noteBtn:SetFrameLevel(21)
    noteBtn:SetPoint("CENTER", noteCol, "CENTER", 0, 0)
    noteBtn:SetChromeIcon(NOTE_ROW_ICON)
    noteBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    noteBtn:SetScript("OnClick", function(self, button)
        local rf = self:GetParent() and self:GetParent():GetParent() and self:GetParent():GetParent():GetParent()
        openListNote(rf and rf._ttNode, button)
    end)
    noteBtn:SetScript("OnEnter", function()
        ShowBesideTip(noteBtn, "Notes", noteButtonTip())
    end)
    noteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row._ttNoteBtn = noteBtn

    ensureRowCommandButtons(row, cmdCol, sz)

    row._ttHit:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    row._ttHit:SetScript("OnClick", function(self, button)
        local rf = self:GetParent()
        taskShortcutClick("taskName", rf and rf._ttNode, button, rf and rf._ttNodeId)
    end)
    row._ttHit:Lower()

    AttachDynamicRowTooltip(row._ttStripHit, nil, function() return row._ttNode end)
    AttachDynamicRowTooltip(row._ttHit, nil, function() return row._ttNode end)
    AttachDynamicRowTooltip(row._ttProgHit, nil, function() return row._ttNode end)
    return row
end

local function BindTaskRow(row, node, level, index, rowW, yOff, height, extra)
    if row:GetParent() ~= TaskTracker.scrollChild then
        row:SetParent(TaskTracker.scrollChild)
        row._ttBk = nil
    end
    local t = TaskTracker.GetTheme()
    local indent = GetIndent(level)
    local width = rowW - indent
    row._ttNode = node
    row._ttNodeId = node and node.id

    local baseRh = RowHeight()
    local useGrow = TaskTracker.GetTaskLabelOverflowMode and TaskTracker.GetTaskLabelOverflowMode() == "grow"

    -- Early-return signature: if nothing relevant changed, skip all anchor churn.
    local progDone, progMax, progIsDone = TaskTracker.GetNodeProgress(node)
    local manualBar = TaskTracker.TaskRowShowsManualAutomationBar(node)
    local cmdCount = TaskTracker.CountRunnableCommandButtons(node)
    local showCmd = cmdCount > 0
    local showNote = shouldShowRowNoteIcon(node)
    local resetTag = (extra and extra.resetTag) or TaskTracker.GetNodeResetTag(node)
    local titlePlain = (extra and extra.titlePlain)
        or (TaskTracker.GetTaskListTitlePlain and TaskTracker.GetTaskListTitlePlain(node))
        or (node.name or "")
    -- Always recompute color from current state. extra.titleColorKey can be stale on paint-only
    -- refreshes (override / manual-lock toggling does not always rebuild the layout model).
    local titleColorKey = TaskTracker.IsTaskEffectivelyDone(node) and "complete" or "textTask"
    local subtitle = (extra and extra.subtitle)
        or (TaskTracker.GetAdvancedTaskSubtitle and TaskTracker.GetAdvancedTaskSubtitle(node))
    local subColor = abundanceSubtitleColor(node, subtitle)
    local desiredQuestAtlas = ""
    if TaskTracker.IsAdvancedTask and TaskTracker.IsAdvancedTask(node)
        and node.advanced and node.advanced.type == "quest"
        and not TaskTracker.IsTaskEffectivelyDone(node) then
        desiredQuestAtlas = CachedQuestStateAtlas("task:" .. tostring(node.id or 0), function()
            return questStateAtlasForQuestIds((node.advanced and node.advanced.questIds) or {})
        end) or ""
    end

    local nid = (node and node.id) or 0
    local k = row._ttBk
    if k
        and k.nid == nid
        and k.level == level
        and k.indent == indent
        and k.width == width
        and k.height == height
        and k.yOff == yOff
        and k.useGrow == useGrow
        and k.progDone == progDone
        and k.progMax == progMax
        and k.progIsDone == progIsDone
        and k.manualBar == manualBar
        and k.cmdCount == cmdCount
        and k.showNote == showNote
        and k.resetTag == resetTag
        and k.titlePlain == titlePlain
        and k.titleColorKey == titleColorKey
        and k.subtitle == subtitle
        and k.subColor == subColor
        and k.questAtlas == desiredQuestAtlas
        and k.index == index
        and k.epoch == ListLayoutEpoch()
    then
        raiseListIconRail(row)
        row._ttProgDone, row._ttProgMax = progDone, progMax
        applyRowCommandButtons(row, node, cmdCount)
        placeRowCommandIcons(row, titleLineIconLift(subtitle and subtitle ~= ""))
        applyRowStripe(row, index, node)
        row:Show()
        return
    end

    applyRowStripe(row, index, node)
    row:SetSize(width, height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", TaskTracker.scrollChild, "TOPLEFT", indent, -yOff)
    -- Show before SetText. A font string set while its row is hidden does not
    -- draw until the next size change, so the second line flashes in and out.
    row:Show()

    -- Left strip placement
    local leftPad = TaskTracker.GetListPadLeft()
    row._ttLeftStrip:ClearAllPoints()
    row._ttLeftStrip:SetPoint("LEFT", row, "LEFT", leftPad, LIST_OPTICAL_DROP)

    row._ttProgDone, row._ttProgMax = progDone, progMax

    local barW = t.taskAutomationBarWidth or 3
    local barH = math.max(12, baseRh - 6)
    row._ttBar:SetWidth(barW)
    row._ttBar:SetHeight(barH)
    row._ttBar:ClearAllPoints()
    row._ttBar:SetPoint("LEFT", row._ttLeftStrip, "LEFT", 0, 0)
    TaskTracker.SetColor(row._ttBar, manualBar and "taskBarManual" or "taskBarAutomated")
    sizeCheckboxIcon(row._ttCheck, baseRh)
    row._ttCheck:ClearAllPoints()
    row._ttCheck:SetPoint("LEFT", row._ttBar, "RIGHT", automationCheckGap(), 0)
    setCheckboxIconState(row._ttCheck, progIsDone, false)
    local stripW = barW + automationCheckGap() + row._ttCheck:GetWidth()
    row._ttLeftStrip:SetSize(stripW, baseRh)

    -- Quest state icon (advanced quest task — log / turn-in hints; not used for collectables)
    local questStateIconW = 0
    if desiredQuestAtlas ~= "" then
        local sz = math.floor(baseRh * 0.42 + 0.5)
        sz = math.max(12, math.min(sz, 16))
        row._ttQuestStateIcon:SetSize(sz, sz)
        row._ttQuestStateIcon:ClearAllPoints()
        row._ttQuestStateIcon:SetPoint("LEFT", row._ttLeftStrip, "RIGHT", 6, 0)
        row._ttQuestStateIcon:SetAtlas(desiredQuestAtlas, false)
        row._ttQuestStateIcon:Show()
        questStateIconW = sz + 4
    else
        row._ttQuestStateIcon:Hide()
    end

    -- Progress host + text
    row._ttProgHost:ClearAllPoints()
    row._ttProgHost:SetPoint("RIGHT", row, "RIGHT", -TaskTracker.GetListPadRight(), LIST_OPTICAL_DROP)
    local progText
    progText = taskProgressText(node, progDone, progMax)
    if node and node.generatedTask then
        progText = ""
        row._ttLeftStrip:Hide()
    else
        row._ttLeftStrip:Show()
    end
    if row._ttLastProgText ~= progText then
        row._ttLastProgText = progText
        row._ttProgStr:SetText(progText)
        local pw = (row._ttProgStr.GetStringWidth and row._ttProgStr:GetStringWidth() or 24) + 10
        row._ttProgHost:SetWidth(math.min(math.max(pw, PROG_HOST_MIN_W), math.max(PROG_HOST_MAX_W, width * 0.38)))
    end

    -- Command/note icons
    refreshRowIconLayout(row, baseRh)
    applyRowCommandButtons(row, node, cmdCount)
    placeRowCommandIcons(row, titleLineIconLift(subtitle and subtitle ~= ""))
    row._ttNoteBtn:SetShown(showNote)

    -- Label + subtitle. Width comes from the row, not GetWidth(): a font string
    -- just re-anchored often reports 0, which drops the second line.
    local subLineH = subtitle and (TaskTracker.GetTaskFontSize and TaskTracker.GetTaskFontSize() or 11) or 0
    local yNudge = 0
    if subtitle and subtitle ~= "" then
        yNudge = math.floor((subLineH + 2) / 2)
    end
    local textLeft = leftPad + stripW + 6 + ((questStateIconW > 0) and questStateIconW or 0)
    local labelW = listTextWidthBeforeIcons(row, width, textLeft, row._ttProgHost)

    -- Recompute fullTitle from current titleColorKey; the cached extra.fullTitle can carry a
    -- stale color (paint-only refreshes do not rebuild the layout model).
    local fullTitle = ListLabelColored(titlePlain, titleColorKey, resetTag)
    row._ttTaskName:ClearAllPoints()
    -- One-line names sit high; two-line names sit low unless the title is lifted
    -- above center and the second line is tucked under it.
    local yLine = (yNudge > 0) and yNudge or LIST_OPTICAL_DROP
    placeListLine(row._ttTaskName, row, textLeft, yLine, labelW)

    local function showSubtitle(fs)
        fs:Show()
        TaskTracker.SetTextColor(fs, subColor or "textSecondary")
        local subPx = (extra and tonumber(extra.subPx)) or subLineH
        if subPx < 10 then subPx = math.max(10, subLineH) end
        fs:SetWordWrap(useGrow and true or false)
        if fs.SetMaxLines then fs:SetMaxLines(useGrow and 0 or 1) end
        fs:ClearAllPoints()
        -- Same vertical center as the title, one gap below it. Pinning the
        -- second line to the bottom of a tall row left the name sitting low.
        local ySub = yNudge - math.floor((taskFontPx() + 2 + subPx) / 2)
        placeListLine(fs, row, textLeft, ySub, labelW)
    end

    local hasSub = subtitle and subtitle ~= ""
    if useGrow and not hasSub then
        enableListWrap(row._ttTaskName)
        if row._ttTaskName:GetText() ~= fullTitle then
            row._ttTaskName:SetText(fullTitle)
        end
        row._ttSubtitle:Hide()
        row._ttSubtitle:SetText("")
    else
        row._ttTaskName:SetWordWrap(false)
        if row._ttTaskName.SetMaxLines then row._ttTaskName:SetMaxLines(1) end
        if row._ttEllipPlain ~= titlePlain or row._ttEllipColor ~= titleColorKey or row._ttEllipReset ~= resetTag or row._ttEllipTw ~= labelW then
            row._ttEllipPlain, row._ttEllipColor, row._ttEllipReset = titlePlain, titleColorKey, resetTag
            row._ttEllipTw = labelW
            ApplyEllipsisColoredListLabel(row._ttTaskName, titlePlain, titleColorKey, resetTag, labelW)
        end
        if hasSub then
            showSubtitle(row._ttSubtitle)
            row._ttSubtitle:SetWordWrap(false)
            if row._ttSubtitle.SetMaxLines then row._ttSubtitle:SetMaxLines(1) end
            row._ttSubEllip, row._ttSubEllipW = subtitle, labelW
            ApplyEllipsisPlainListLabel(row._ttSubtitle, subtitle, labelW)
        else
            row._ttSubtitle:Hide()
            row._ttSubtitle:SetText("")
        end
    end

    -- Hitbox excludes left strip and cmd/note rail
    local sw = (t.taskAutomationBarWidth or 3) + automationCheckGap() + row._ttCheck:GetWidth() + 6
    anchorRowHitLeftOfIconRail(row._ttHit, row, leftPad + sw)

    k = row._ttBk
    if not k then
        k = {}
        row._ttBk = k
    end
    k.nid, k.level, k.indent, k.width, k.height, k.yOff = nid, level, indent, width, height, yOff
    k.useGrow, k.progDone, k.progMax, k.progIsDone = useGrow, progDone, progMax, progIsDone
    k.manualBar, k.cmdCount, k.showNote = manualBar, cmdCount, showNote
    k.resetTag, k.titlePlain, k.titleColorKey, k.subtitle, k.questAtlas = resetTag, titlePlain, titleColorKey, subtitle, desiredQuestAtlas
    k.subColor = subColor
    k.index = index
    k.epoch = ListLayoutEpoch()

    row:Show()
end

local function EnsureRegistryFrame()
    local f = poolAcquire("registry")
    if f then return f end
    local row = CreateFrame("Frame", nil, TaskTracker.scrollChild)
    row._ttKind = "registry"
    row._ttHit = CreateFrame("Button", nil, row)
    row._ttHit:EnableMouse(true)
    row._ttHit:SetFrameLevel(1)

    row._ttBg = TaskTracker.MakeRowBg(row, 1)
    TaskTracker.MakeEdge(row, "BOTTOM", "border")

    local t = TaskTracker.GetTheme()
    local baseRh = RowHeight()

    row._ttLeftStrip = CreateFrame("Frame", nil, row)
    row._ttBar = row._ttLeftStrip:CreateTexture(nil, "OVERLAY")
    row._ttBar:SetWidth(t.taskAutomationBarWidth or 3)
    row._ttCheck = makeCheckboxIcon(row._ttLeftStrip, baseRh)
    row._ttCheck:SetPoint("LEFT", row._ttBar, "RIGHT", automationCheckGap(), 0)

    local stripHit = CreateFrame("Button", nil, row._ttLeftStrip)
    stripHit:SetFrameLevel(15)
    stripHit:SetAllPoints(row._ttLeftStrip)
    stripHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    stripHit:SetScript("OnClick", function(self, button)
        if IsEditMode() then return end
        local rf = self:GetParent() and self:GetParent():GetParent()
        local rid = rf and rf._ttRegistryEntryId
        if not rid then return end
        if button == "RightButton" then
            TaskTracker.RegistryCheckboxTurnOff(rid)
        else
            TaskTracker.ToggleRegistryCheckboxDone(rid)
        end
    end)
    row._ttStripHit = stripHit

    row._ttQuestStateIcon = row:CreateTexture(nil, "OVERLAY")
    row._ttQuestStateIcon:Hide()

    row._ttPowerRewardHit = CreateFrame("Button", nil, row)
    row._ttPowerRewardHit:SetFrameLevel(12)
    row._ttPowerRewardHit:Hide()
    row._ttPowerRewardIcon = row._ttPowerRewardHit:CreateTexture(nil, "ARTWORK")
    row._ttPowerRewardIcon:SetAllPoints()
    row._ttPowerRewardIlvl = TaskTracker.CreateScaledListFontString(row, "OVERLAY", t.fontNormal or "GameFontHighlightSmall")
    row._ttPowerRewardIlvl:Hide()

    row._ttEntryLabel = TaskTracker.CreateScaledListFontString(row, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    row._ttEntryLabel:SetJustifyH("LEFT")

    row._ttRegistrySub = TaskTracker.CreateScaledListFontString(row, "OVERLAY", "GameFontDisableSmall")
    TaskTracker.SetTextColor(row._ttRegistrySub, "textSecondary")
    row._ttRegistrySub:SetJustifyH("LEFT")
    row._ttRegistrySub:SetJustifyV("TOP")
    row._ttRegistrySub:Hide()

    row._ttProgressHost = CreateFrame("Frame", nil, row)
    row._ttProgressHost:SetHeight(baseRh)
    row._ttProgress = TaskTracker.CreateScaledListFontString(row._ttProgressHost, "OVERLAY", t.fontNormal or "GameFontHighlightSmall")
    row._ttProgress:SetJustifyH("RIGHT")
    row._ttProgress:SetJustifyV("MIDDLE")
    row._ttProgress:SetPoint("RIGHT", row._ttProgressHost, "RIGHT", 0, 0)

    local progressHit = CreateFrame("Button", nil, row._ttProgressHost)
    progressHit:SetFrameLevel(50)
    progressHit:EnableMouse(true)
    progressHit:SetAllPoints(row._ttProgressHost)
    progressHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    progressHit:SetScript("OnClick", function(self, button)
        if IsEditMode() then return end
        local requireShift = (TaskTrackerDB and TaskTrackerDB.requireShiftRowAdjustClicks ~= false) and true or false
        local rf = self:GetParent() and self:GetParent():GetParent()
        local rid = rf and rf._ttRegistryEntryId
        if not rid then return end
        if button == "LeftButton" and IsShiftKeyDown() and TaskTracker.ShowSetCountPopup then
            local autoC = (TaskTracker.GetRegistryEntryAutomatedValue and TaskTracker.GetRegistryEntryAutomatedValue(rid)) or (rf._ttCur or 0)
            local initTr, initAu = rf._ttCur or 0, autoC
            TaskTracker.ShowSetCountPopup({
                title = ((rf._ttRegistryEntry and rf._ttRegistryEntry.label) or "Entry") .. " progress",
                cur = initTr,
                autoCur = autoC,
                max = rf._ttMax or 0,
                onAccept = function(tr, au)
                    if TaskTracker.ApplyRegistryProgressFromPopup then
                        TaskTracker.ApplyRegistryProgressFromPopup(rid, tr, au, initTr, initAu)
                    end
                end,
            })
            return
        end
        if button == "RightButton" then
            TaskTracker.ApplyRegistryRowClick(rid, -1)
            return
        end
        if requireShift and not IsShiftKeyDown() then return end
        TaskTracker.ApplyRegistryRowClick(rid, 1)
    end)
    row._ttProgressHit = progressHit

    row._ttVaultHolder = CreateFrame("Frame", nil, row)
    row._ttVaultHolder:SetHeight(baseRh)
    row._ttVaultFs = TaskTracker.CreateScaledListFontString(row._ttVaultHolder, "OVERLAY", t.fontNormal or "GameFontHighlightSmall")
    row._ttVaultFs:SetJustifyH("RIGHT")
    row._ttVaultFs:SetJustifyV("MIDDLE")
    TaskTracker.SetTextColor(row._ttVaultFs, "textPrimary")
    row._ttVaultFs:SetPoint("RIGHT", row._ttVaultHolder, "RIGHT", 0, 0)

    local cmdCol, noteCol, sz = makeListIconColumnShell(row, baseRh, row._ttProgressHost, PROG_TO_NOTE_GAP)
    row._ttCmdCol, row._ttNoteCol, row._ttIconSz = cmdCol, noteCol, sz

    row._ttNoteBtn = TaskTracker.MakeIconButton(noteCol, sz, sz, LIST_ROW_ICON_OPT)
    row._ttNoteBtn:SetFrameLevel(21)
    row._ttNoteBtn:SetPoint("CENTER", noteCol, "CENTER", 0, 0)
    row._ttNoteBtn:SetChromeIcon(NOTE_ROW_ICON)
    row._ttNoteBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    row._ttNoteBtn:SetScript("OnClick", function(self, button)
        local rf = self:GetParent() and self:GetParent():GetParent() and self:GetParent():GetParent():GetParent()
        openListNote(rf and rf._ttNode, button)
    end)
    row._ttNoteBtn:SetScript("OnEnter", function()
        ShowBesideTip(row._ttNoteBtn, "Notes", noteButtonTip())
    end)
    row._ttNoteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ensureRowCommandButtons(row, cmdCol, sz)

    row._ttHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row._ttHit:SetScript("OnClick", function(self, button)
        if IsEditMode() then return end
        local rf = self:GetParent()
        local rid = rf and rf._ttRegistryEntryId
        if not rid then return end
        local d = (button == "RightButton") and -1 or 1
        TaskTracker.ApplyRegistryRowClick(rid, d)
    end)
    row._ttHit:Lower()
    AttachDynamicRowTooltip(row._ttHit, function() return row._ttRegistryEntry end, function() return row._ttNode end)
    AttachDynamicRowTooltip(row._ttStripHit, function() return row._ttRegistryEntry end, function() return row._ttNode end)
    AttachDynamicRowTooltip(row._ttProgressHit, function() return row._ttRegistryEntry end, function() return row._ttNode end)
    return row
end

local function BindRegistryRow(row, node, level, index, rowW, yOff, height, extra)
    if row:GetParent() ~= TaskTracker.scrollChild then
        row:SetParent(TaskTracker.scrollChild)
        row._ttBk = nil
    end
    local dbLocal = TaskTrackerDB
    local indent = GetIndent(level)
    local width = rowW - indent
    row._ttNode = node
    row._ttRegistryEntryId = node.registryEntryId

    local entry = TaskTracker.RegistryByID[node.registryEntryId]
    local isVault = entry and entry.type == "vault_row"
    local isCatchup = entry and entry.type == "profession_catchup"
    local isMplusHint = entry and entry.type == "mplus_hint_row"
    local isDisplayOnly = isVault
    local cur, max, isDone, isOverridden = TaskTracker.GetRegistryEntryProgress(node.registryEntryId)
    local st = entry and dbLocal and dbLocal.registryState and dbLocal.registryState[entry.id]
    local userCountLock = st and st.userValue ~= nil and entry and entry.type == "quest_count"
    local useOverrideColor = (isOverridden or userCountLock) and not isDisplayOnly
    row._ttRegistryEntry = entry
    row._ttCur, row._ttMax = cur, max

    local cmdCount = TaskTracker.CountRunnableCommandButtons(node)
    local showCmd = cmdCount > 0
    local showNote = shouldShowRowNoteIcon(node)
    local resetTag = (extra and extra.resetTag) or TaskTracker.GetNodeResetTag(node)
    local labelPlain = (extra and extra.labelPlain) or (TaskTracker.GetNodeLabel(node) or "")
    -- Always recompute color from current state. The cached extra.labelColorKey can be stale on
    -- paint-only refreshes (e.g. toggling override / clearing manual lock without a model rebuild).
    local entryColorKey
    if useOverrideColor then
        entryColorKey = "override"
    elseif isDone and not isDisplayOnly then
        entryColorKey = "complete"
    else
        entryColorKey = "textRegistry"
    end
    local desiredQuestAtlas = ""
    if entry and not isDisplayOnly and not isDone
        and ((entry._ttQuestCount or 0) > 0 or (entry.quests and next(entry.quests) ~= nil)) then
        local ids = entry._ttQuestIds
        if not ids then
            ids = {}
            for qid in pairs(entry.quests or {}) do
                ids[#ids + 1] = qid
            end
        end
        desiredQuestAtlas = CachedQuestStateAtlas("reg:" .. tostring(entry.id or ""), function()
            return questStateAtlasForQuestIds(ids)
        end) or ""
    end
    local vaultText = (isVault and entry and entry.vaultKind and TaskTracker.FormatVaultIlvlRow(entry.vaultKind))
        or (isCatchup and entry and TaskTracker.FormatProfessionCatchupRow and TaskTracker.FormatProfessionCatchupRow(entry))
        or ""
    local mplusSubtitle, subColor
    if extra and extra.mplusSubtitle ~= nil then
        mplusSubtitle = extra.mplusSubtitle
        subColor = extra.subColor or "textSecondary"
    else
        mplusSubtitle, subColor = registryRowSubtitle(entry)
    end
    local powIconId, powIlvlStr, powEffIdx = 0, "", 0
    if entry and TaskTracker.PowerRewardRowShouldShowPowerColumn and TaskTracker.PowerRewardRowShouldShowPowerColumn(entry) then
        local es, ei = TaskTracker.GetEffectivePowerRewardSlot(entry)
        if es then
            powEffIdx = ei or 0
            powIconId = (TaskTracker.PowerSlotIconAtlas and TaskTracker.PowerSlotIconAtlas(es))
                or TaskTracker.GetPowerRewardIconFileIdForSlot(es) or 0
            if TaskTracker.FormatPowerSlotIlvl then
                powIlvlStr = TaskTracker.FormatPowerSlotIlvl(es)
            elseif type(es.expectedIlvl) == "number" and es.expectedIlvl > 0 then
                powIlvlStr = tostring(es.expectedIlvl)
            end
        end
    end

    local nid = (node and node.id) or 0
    local k = row._ttBk
    if k
        and k.nid == nid
        and k.level == level
        and k.indent == indent
        and k.width == width
        and k.height == height
        and k.yOff == yOff
        and k.isVault == isVault
        and k.isCatchup == isCatchup
        and k.isMplusHint == isMplusHint
        and k.cur == cur
        and k.max == max
        and k.isDone == isDone
        and k.useOverrideColor == useOverrideColor
        and k.cmdCount == cmdCount
        and k.showNote == showNote
        and k.resetTag == resetTag
        and k.labelPlain == labelPlain
        and k.entryColorKey == entryColorKey
        and k.questAtlas == desiredQuestAtlas
        and k.vaultText == vaultText
        and k.mplusSubtitle == mplusSubtitle
        and k.subColor == subColor
        and k.powIconId == powIconId
        and k.powIlvlStr == powIlvlStr
        and k.powEffIdx == powEffIdx
        and k.index == index
        and k.epoch == ListLayoutEpoch()
    then
        raiseListIconRail(row)
        applyRowCommandButtons(row, node, cmdCount)
        placeRowCommandIcons(row, titleLineIconLift(mplusSubtitle ~= ""))
        applyRowStripe(row, index, node)
        row:Show()
        return
    end

    applyRowStripe(row, index, node)
    row:SetSize(width, height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", TaskTracker.scrollChild, "TOPLEFT", indent, -yOff)

    -- label
    local label = labelPlain
    -- Recompute full label from current entryColorKey; the cached extra.fullLabel can carry a
    -- stale color (paint-only refreshes do not rebuild the layout model).
    local full = ListLabelColored(labelPlain, entryColorKey, resetTag)

    local t = TaskTracker.GetTheme()
    local baseRh = RowHeight()
    local useGrow = TaskTracker.GetTaskLabelOverflowMode and TaskTracker.GetTaskLabelOverflowMode() == "grow"
    local leftPad = TaskTracker.GetListPadLeft()
    local subPx = (mplusSubtitle ~= "" and taskFontPx()) or 0
    local yTitle = (subPx > 0) and twoLineTitleLift(subPx) or 0

    -- Left strip stays on the row center. The title shifts up when a second line is showing.
    if isDisplayOnly then
        row._ttLeftStrip:Hide()
    else
        row._ttLeftStrip:Show()
        row._ttLeftStrip:ClearAllPoints()
        row._ttLeftStrip:SetPoint("LEFT", row, "LEFT", leftPad, LIST_OPTICAL_DROP)
        local barW = t.taskAutomationBarWidth or 3
        local barH = math.max(12, baseRh - 6)
        row._ttBar:SetWidth(barW)
        row._ttBar:SetHeight(barH)
        row._ttBar:ClearAllPoints()
        row._ttBar:SetPoint("LEFT", row._ttLeftStrip, "LEFT", 0, 0)
        TaskTracker.SetColor(row._ttBar, TaskTracker.RegistryRowShowsManualAutomationBar(node.registryEntryId) and "taskBarManual" or "taskBarAutomated")
        sizeCheckboxIcon(row._ttCheck, baseRh)
        row._ttCheck:ClearAllPoints()
        row._ttCheck:SetPoint("LEFT", row._ttBar, "RIGHT", automationCheckGap(), 0)
        setCheckboxIconState(row._ttCheck, isDone, isOverridden or userCountLock)
        local stripW = barW + automationCheckGap() + row._ttCheck:GetWidth()
        row._ttLeftStrip:SetSize(stripW, baseRh)
    end

    -- Quest-state icon for quest-tracking registry entries
    local questStateIconW = 0
    if desiredQuestAtlas ~= "" then
        local sz = math.floor(baseRh * 0.42 + 0.5)
        sz = math.max(12, math.min(sz, 16))
        row._ttQuestStateIcon:SetSize(sz, sz)
        row._ttQuestStateIcon:ClearAllPoints()
        if not isDisplayOnly and row._ttLeftStrip:IsShown() then
            row._ttQuestStateIcon:SetPoint("LEFT", row._ttLeftStrip, "RIGHT", 6, 0)
        else
            row._ttQuestStateIcon:SetPoint("LEFT", row, "LEFT", leftPad, 0)
        end
        row._ttQuestStateIcon:SetAtlas(desiredQuestAtlas, false)
        row._ttQuestStateIcon:Show()
        questStateIconW = sz + 4
    else
        row._ttQuestStateIcon:Hide()
    end

    local powerRewardW = 0
    row._ttPowerRewardHit:Hide()
    row._ttPowerRewardIlvl:Hide()
    if entry and TaskTracker.PowerRewardRowShouldShowPowerColumn and TaskTracker.PowerRewardRowShouldShowPowerColumn(entry) then
        local effSlot = TaskTracker.GetEffectivePowerRewardSlot(entry)
        if effSlot then
            local psz = math.floor(baseRh * 0.42 + 0.5)
            psz = math.max(14, math.min(psz, 18))
            local atlas = TaskTracker.PowerSlotIconAtlas and TaskTracker.PowerSlotIconAtlas(effSlot)
            local fid = TaskTracker.GetPowerRewardIconFileIdForSlot(effSlot)
            if atlas then
                row._ttPowerRewardIcon:SetAtlas(atlas, false)
                row._ttPowerRewardIcon:SetVertexColor(1, 1, 1, 1)
            elseif fid then
                row._ttPowerRewardIcon:SetTexture(fid)
                row._ttPowerRewardIcon:SetVertexColor(1, 1, 1, 1)
            else
                row._ttPowerRewardIcon:SetTexture(nil)
            end
            row._ttPowerRewardHit:SetSize(psz, psz)
            row._ttPowerRewardHit:ClearAllPoints()
            if row._ttQuestStateIcon:IsShown() then
                row._ttPowerRewardHit:SetPoint("LEFT", row._ttQuestStateIcon, "RIGHT", 4, 0)
            elseif not isDisplayOnly and row._ttLeftStrip:IsShown() then
                row._ttPowerRewardHit:SetPoint("LEFT", row._ttLeftStrip, "RIGHT", 6, 0)
            else
                row._ttPowerRewardHit:SetPoint("LEFT", row, "LEFT", leftPad, 0)
            end
            row._ttPowerRewardHit:SetScript("OnEnter", function()
                TaskTracker.AnchorPowerRewardTooltip(row._ttPowerRewardHit, entry)
            end)
            row._ttPowerRewardHit:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            row._ttPowerRewardHit:Show()

            local ilvlTxt = ""
            if TaskTracker.FormatPowerSlotIlvl then
                ilvlTxt = TaskTracker.FormatPowerSlotIlvl(effSlot)
            elseif type(effSlot.expectedIlvl) == "number" and effSlot.expectedIlvl > 0 then
                ilvlTxt = tostring(effSlot.expectedIlvl)
            end
            row._ttPowerRewardIlvl:SetText(ilvlTxt)
            if TaskTracker.SetTextColor then
                TaskTracker.SetTextColor(row._ttPowerRewardIlvl, "accent")
            end
            row._ttPowerRewardIlvl:ClearAllPoints()
            if ilvlTxt ~= "" then
                row._ttPowerRewardIlvl:Show()
            else
                row._ttPowerRewardIlvl:Hide()
            end

            local iw = 0
            if ilvlTxt ~= "" and row._ttPowerRewardIlvl.GetStringWidth then
                iw = row._ttPowerRewardIlvl:GetStringWidth() + 3
            end
            if atlas or fid then
                row._ttPowerRewardIlvl:SetPoint("LEFT", row._ttPowerRewardHit, "RIGHT", 2, 0)
                powerRewardW = psz + 2 + iw
            else
                row._ttPowerRewardHit:SetWidth(math.max(1, iw))
                row._ttPowerRewardIlvl:SetPoint("LEFT", row._ttPowerRewardHit, "LEFT", 0, 0)
                powerRewardW = math.max(1, iw)
            end
        end
    end

    -- Right-side progress / vault holder
    local pad = TaskTracker.GetListPadRight()
    row._ttProgressHost:ClearAllPoints()
    row._ttVaultHolder:ClearAllPoints()
    if (isVault and entry and entry.vaultKind) or isCatchup then
        row._ttProgressHost:Hide()
        row._ttVaultHolder:Show()
        local text
        if isVault and entry and entry.vaultKind then
            text = TaskTracker.FormatVaultIlvlRow(entry.vaultKind)
            if text == "- / - / -" and C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
                local ok, has = pcall(C_WeeklyRewards.HasAvailableRewards)
                if ok and has then
                    text = "Collect Vault"
                end
            end
        else
            text = (TaskTracker.FormatProfessionCatchupRow and TaskTracker.FormatProfessionCatchupRow(entry)) or "-"
        end
        row._ttVaultFs:SetText(text)
        local w = (row._ttVaultFs.GetStringWidth and row._ttVaultFs:GetStringWidth() or 80) + 10
        if isCatchup then
            w = math.min(math.max(w, 28), 80)
        else
            w = math.min(math.max(w, 36), 120)
        end
        row._ttVaultHolder:SetWidth(w)
        row._ttVaultHolder:SetPoint("RIGHT", row, "RIGHT", -pad, 0)
        if isVault then
            row._ttHit:SetScript("OnClick", function() end)
        end
    else
        row._ttVaultHolder:Hide()
        row._ttProgressHost:Show()
        row._ttHit:SetScript("OnClick", function(self, button)
            if IsEditMode() then return end
            local requireShift = (TaskTrackerDB and TaskTrackerDB.requireShiftRowAdjustClicks ~= false) and true or false
            local rf = self:GetParent()
            local rid = rf and rf._ttRegistryEntryId
            if not rid then return end
            if button == "LeftButton" and IsControlKeyDown() and TaskTracker.ClearRegistryEntryManual then
                TaskTracker.ClearRegistryEntryManual(rid)
                return
            end
            if button == "RightButton" then
                TaskTracker.ApplyRegistryRowClick(rid, -1)
                return
            end
            if requireShift and not IsShiftKeyDown() then return end
            TaskTracker.ApplyRegistryRowClick(rid, 1)
        end)
        if useOverrideColor then
            row._ttProgress:SetText(TaskTracker.WrapColor(tostring(cur) .. "/" .. tostring(max), "override"))
        else
            row._ttProgress:SetText(TaskTracker.CountText(cur, max))
        end
        local phw = (row._ttProgress.GetStringWidth and row._ttProgress:GetStringWidth() or 40) + 10
        row._ttProgressHost:SetWidth(math.min(math.max(phw, PROG_HOST_MIN_W), PROG_HOST_MAX_W))
        row._ttProgressHost:SetPoint("RIGHT", row, "RIGHT", -pad, LIST_OPTICAL_DROP)
    end

    -- cmd/note icons
    refreshRowIconLayout(row, baseRh)
    applyRowCommandButtons(row, node, cmdCount)
    placeRowCommandIcons(row, titleLineIconLift(mplusSubtitle ~= ""))
    row._ttNoteBtn:SetShown(showNote)

    -- Label placement
    local stripW = 0
    if not isDisplayOnly and row._ttLeftStrip:IsShown() then
        local barW = t.taskAutomationBarWidth or 3
        stripW = barW + automationCheckGap() + row._ttCheck:GetWidth()
    end
    local textColLeft = leftPad + stripW + 6 + ((questStateIconW > 0) and questStateIconW or 0) + powerRewardW
    local rightAnchor = ((isVault or isCatchup) and row._ttVaultHolder:IsShown()) and row._ttVaultHolder or row._ttProgressHost
    local rail = row._ttCmdCol and row._ttCmdCol:GetParent()
    if rail then
        rail:ClearAllPoints()
        rail:SetPoint("RIGHT", rightAnchor, "LEFT", -8, 0)
    end
    local labelW = listTextWidthBeforeIcons(row, width, textColLeft, rightAnchor)
    row._ttEntryLabel:ClearAllPoints()
    row._ttEntryLabel:SetJustifyH("LEFT")
    local yLine = (yTitle > 0) and yTitle or LIST_OPTICAL_DROP
    placeListLine(row._ttEntryLabel, row, textColLeft, yLine, labelW)

    local hasSub = mplusSubtitle ~= ""
    if useGrow and not isVault and not isCatchup and not hasSub then
        enableListWrap(row._ttEntryLabel)
        row._ttEntryLabel:SetText(full)
    else
        row._ttEntryLabel:SetWordWrap(false)
        if row._ttEntryLabel.SetMaxLines then row._ttEntryLabel:SetMaxLines(1) end
        ApplyEllipsisColoredListLabel(row._ttEntryLabel, label, entryColorKey, resetTag, labelW)
    end

    if row._ttRegistrySub then
        if mplusSubtitle ~= "" then
            row._ttRegistrySub:Show()
            TaskTracker.SetTextColor(row._ttRegistrySub, subColor or "textSecondary")
            local ySub = yTitle - math.floor((taskFontPx() + 2 + subPx) / 2)
            placeListLine(row._ttRegistrySub, row, textColLeft, ySub, labelW)
            row._ttRegistrySub:SetWordWrap(false)
            if row._ttRegistrySub.SetMaxLines then row._ttRegistrySub:SetMaxLines(1) end
            ApplyEllipsisPlainListLabel(row._ttRegistrySub, mplusSubtitle, labelW)
        else
            row._ttRegistrySub:Hide()
            row._ttRegistrySub:SetText("")
        end
    end

    -- Hitbox region: never cover cmd/note icons
    if isVault then
        anchorRowHitLeftOfIconRail(row._ttHit, row, leftPad)
        row._ttHit:RegisterForClicks("LeftButtonUp")
    elseif isCatchup and row._ttLeftStrip:IsShown() then
        local bw = t.taskAutomationBarWidth or 3
        local sw = bw + automationCheckGap() + row._ttCheck:GetWidth() + 6
        anchorRowHitLeftOfIconRail(row._ttHit, row, leftPad + sw)
        row._ttHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    elseif not isVault and row._ttLeftStrip:IsShown() then
        local bw = t.taskAutomationBarWidth or 3
        local sw = bw + automationCheckGap() + row._ttCheck:GetWidth() + 6
        anchorRowHitLeftOfIconRail(row._ttHit, row, leftPad + sw)
        row._ttHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    else
        anchorRowHitLeftOfIconRail(row._ttHit, row, leftPad)
        row._ttHit:RegisterForClicks("LeftButtonUp")
    end

    k = row._ttBk
    if not k then
        k = {}
        row._ttBk = k
    end
    k.nid, k.level, k.indent, k.width, k.height, k.yOff = nid, level, indent, width, height, yOff
    k.isVault, k.isCatchup, k.isMplusHint = isVault, isCatchup, isMplusHint
    k.cur, k.max, k.isDone, k.useOverrideColor = cur, max, isDone, useOverrideColor
    k.cmdCount, k.showNote = cmdCount, showNote
    k.resetTag, k.labelPlain, k.entryColorKey = resetTag, labelPlain, entryColorKey
    k.questAtlas, k.vaultText, k.mplusSubtitle = desiredQuestAtlas, vaultText, mplusSubtitle
    k.subColor = subColor
    k.powIconId, k.powIlvlStr, k.powEffIdx = powIconId, powIlvlStr, powEffIdx
    k.index = index
    k.epoch = ListLayoutEpoch()

    row:Show()
end

local function PaintVisible()
    local t0 = NowMs()
    local model = TaskTracker._ttListModel
    if not model then return end
    local sf = TaskTracker.scrollFrame
    local viewH = (sf and sf.GetHeight and sf:GetHeight()) or 0
    local scrollY = (sf and sf.GetVerticalScroll and sf:GetVerticalScroll()) or 0
    local pad = 80
    local yMin = math.max(0, scrollY - pad)
    local yMax = scrollY + viewH + pad

    local rowW = (TaskTracker.PANEL_WIDTH - TaskTracker.GetScrollGutter())

    -- Mark all active frames unused, then re-mark used ones.
    local active = TaskTracker._ttListActive
    for _, slot in pairs(active) do
        slot.used = false
    end

    local n = #model
    local i = listModelFirstVisibleIndex(model, yMin)
    while i <= n do
        local r = model[i]
        if r.y > yMax then break end
        local slot = active[i]
        if not slot then
            slot = { used = true, frame = nil }
            active[i] = slot
        end
        slot.used = true
        local f = slot.frame
        -- If this slot previously held a different row kind, discard it. Expand/collapse
        -- changes model ordering, so index slots can map to different node kinds.
        if f and f._ttKind and f._ttKind ~= r.kind then
            poolRelease(f)
            f = nil
            slot.frame = nil
        end
        if not f then
            if r.kind == "groupHeader" then
                f = EnsureGroupHeaderFrame()
            elseif r.kind == "task" then
                f = EnsureTaskFrame()
            elseif r.kind == "registry" then
                f = EnsureRegistryFrame()
            end
            slot.frame = f
        end
        if f then
            f._ttKind = r.kind
            if r.kind == "groupHeader" then
                BindGroupHeader(f, r.node, r.level, rowW, r.y, r.extra)
            elseif r.kind == "task" then
                BindTaskRow(f, r.node, r.level, (r.extra and r.extra.index) or 1, rowW, r.y, r.h, r.extra)
            elseif r.kind == "registry" then
                BindRegistryRow(f, r.node, r.level, (r.extra and r.extra.index) or 1, rowW, r.y, r.h, r.extra)
            end
        end
        i = i + 1
    end

    -- Release frames that are no longer visible
    for i, slot in pairs(active) do
        if not slot.used and slot.frame then
            poolRelease(slot.frame)
            active[i] = nil
        end
    end
    PerfStore("paintMs", NowMs() - t0)
end

--- Full tree rebuild (expensive). Call via TaskTracker.RefreshList so paints coalesce and skip when invisible.
local function RefreshListExecute()
    local scrollChild = TaskTracker.scrollChild
    local db          = TaskTrackerDB
    local PANEL_WIDTH = TaskTracker.PANEL_WIDTH

    if not scrollChild or not db or not db.tree then return end
    if not IsPlayerInWorld() then return end

    if TaskTracker.SweepCompletedTemporaryTasks then
        TaskTracker.SweepCompletedTemporaryTasks()
    end

    if TaskTracker.InvalidatePowerShareWinnersCache then
        TaskTracker.InvalidatePowerShareWinnersCache()
    end
    if TaskTracker.RefreshListFontSizes then
        TaskTracker.RefreshListFontSizes()
    end

    -- Precompute leaf progress once per refresh. This is used by group header counts
    -- and hide-completed pruning, and avoids repeated recursive subtree walks.
    local viewTree = (TaskTracker.GetListViewRoot and TaskTracker.GetListViewRoot(db.tree)) or db.tree
    if TaskTracker.BuildZoneFilterVisibility then
        TaskTracker.BuildZoneFilterVisibility(viewTree)
    end
    if TaskTracker.BuildListKindFilter then
        TaskTracker.BuildListKindFilter(viewTree)
    end
    if TaskTracker.BuildLeafProgressCache then
        TaskTracker.BuildLeafProgressCache(viewTree)
    end

    -- Edit mode is structurally complex (insert zones, reorder pick-up). Keep legacy renderer for
    -- correctness. Browse mode (common case) uses pooled + virtualized rendering below.
    if IsEditMode() then
        TaskTracker._ttEditInsertZones = {}
        TaskTracker._ttEditHeaders = {}
        -- Ensure virtualized browse-mode frames are not left visible underneath.
        ClearVirtualizedFrames()
        ClearLegacyRows()
        TaskTracker.rowFrames = {}

        local rowFrames = TaskTracker.rowFrames
        local rowW      = PANEL_WIDTH - TaskTracker.GetScrollGutter()
        local yOff      = TaskTracker.GetListPadTop and TaskTracker.GetListPadTop() or 0

        yOff = RenderNode(scrollChild, rowFrames, viewTree, nil, 1, rowW, yOff, 0, false)

        -- Bottom add strip: split left = group, right = task (top-level list has no task side)
        if IsEditMode() then
            local t       = TaskTracker.GetTheme()
            local newCatH = CatHeight()
            local strip   = AcquirePooledFrame("editBottomStrip", "Frame", scrollChild)
            strip:SetSize(rowW, newCatH)
            strip:ClearAllPoints()
            strip:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOff)

            local w    = rowW
            local half = math.max(1, math.floor(w / 2))

            if not strip._ttEditBuilt then
                TaskTracker.MakeBorder(strip, "border")

                local bgL = strip:CreateTexture(nil, "BACKGROUND")
                strip._ttBgL = bgL
                local bgR = strip:CreateTexture(nil, "BACKGROUND")
                strip._ttBgR = bgR

                local leftHit = CreateFrame("Button", nil, strip)
                leftHit:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
                strip._ttLeftHit = leftHit

                local rightHit = CreateFrame("Button", nil, strip)
                strip._ttRightHit = rightHit

                local mailStripBtn = TaskTracker.MakeIconButton(strip, 18, 18, TaskTracker.ChromeIconOpt())
                mailStripBtn:SetFrameLevel((strip:GetFrameLevel() or 0) + 4)
                mailStripBtn:SetPoint("RIGHT", strip, "RIGHT", -2, 0)
                TaskTracker.SetShareMailboxIcon(mailStripBtn)
                mailStripBtn:SetScript("OnEnter", function(self)
                    ShowBesideTip(self, "Import / export", "Opens the share window: paste a group export to append it to your top-level list. For tasks, use the mailbox on Add or Edit task (under a group).")
                end)
                mailStripBtn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
                mailStripBtn:SetScript("OnClick", function()
                    TaskTracker.OpenShareImportExportDialog({
                        title = "Share (list)",
                        hint = "Paste a group export below and click Import to append it to the end of your top-level list.",
                        getExportText = nil,
                        focusExportSelect = false,
                        onImport = function(kind, node)
                            if kind ~= "group" then
                                return "From here, only a group export can be imported. Use the mailbox on Add or Edit task for tasks."
                            end
                            if not TaskTracker.InsertNodeAsLastChild("root", node) then
                                return "Could not append group."
                            end
                            return nil
                        end,
                    })
                end)

                local div = strip:CreateTexture(nil, "OVERLAY")
                div:SetWidth(1)
                div:SetPoint("TOP", strip, "TOP", 0, -2)
                div:SetPoint("BOTTOM", strip, "BOTTOM", 0, 2)
                TaskTracker.SetColor(div, "border")
                strip._ttEditBuilt = true
            end

            strip._ttBgL:ClearAllPoints()
            strip._ttBgL:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
            strip._ttBgL:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -(w - half), 0)
            strip._ttBgR:ClearAllPoints()
            strip._ttBgR:SetPoint("TOPLEFT", strip, "TOPLEFT", half, 0)
            strip._ttBgR:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)

            local bgL, bgR = strip._ttBgL, strip._ttBgR
            local function paintBottom(leftHover, rightHover)
                local lg, lh = t.insertSplitGroupLine, t.insertSplitGroupHover
                local tg, th = t.insertSplitTaskLine, t.insertSplitTaskHover
                if lg and bgL then
                    local c = (leftHover and lh) or lg
                    bgL:SetColorTexture(c[1], c[2], c[3], (leftHover and 0.38) or 0.22)
                end
                if tg and bgR then
                    local c = (rightHover and th) or tg
                    bgR:SetColorTexture(c[1], c[2], c[3], (rightHover and 0.30) or 0.15)
                end
            end
            paintBottom(false, false)

            local leftHit = strip._ttLeftHit
            leftHit:SetSize(half, newCatH)
            leftHit:SetScript("OnEnter", function()
                paintBottom(true, false)
                ShowInsertLineTooltip(leftHit, "Add group", "This adds a group to the list.")
            end)
            leftHit:SetScript("OnLeave", function()
                paintBottom(false, false)
                GameTooltip:Hide()
            end)
            leftHit:SetScript("OnClick", function()
                TaskTracker.groupDialog.OpenNew("root")
            end)

            local rightHit = strip._ttRightHit
            rightHit:SetSize(math.max(1, w - half), newCatH)
            rightHit:ClearAllPoints()
            rightHit:SetPoint("TOPLEFT", strip, "TOPLEFT", half, 0)
            rightHit:SetScript("OnEnter", function()
                paintBottom(false, true)
                ShowInsertLineTooltip(rightHit, "Add task", "Tasks can only be added inside a group. Use the split line under an expanded group.")
            end)
            rightHit:SetScript("OnLeave", function()
                paintBottom(false, false)
                GameTooltip:Hide()
            end)
            rightHit:SetScript("OnClick", function() end)

            table.insert(rowFrames, strip)
            yOff = yOff + newCatH + TaskTracker.GetSpacingGroupSection()
        end

        yOff = yOff + (TaskTracker.GetListPadBottom and TaskTracker.GetListPadBottom() or 0)
        scrollChild:SetSize(rowW, yOff)
        local sf = TaskTracker.scrollFrame
        if sf and sf.UpdateScrollBar then
            sf.UpdateScrollBar()
        end
        if TaskTracker.ApplyEditModeLayout then
            TaskTracker.ApplyEditModeLayout()
        end
        if TaskTracker.SyncTitleBarIcons then
            TaskTracker.SyncTitleBarIcons()
        end
        if TaskTracker.ValidateNoteWindow then
            TaskTracker.ValidateNoteWindow()
        end
        TaskTracker.ValidateQuickCommandsPanel()
        if TaskTracker.RefreshPeekInlineCommandsIfShown then
            TaskTracker.RefreshPeekInlineCommandsIfShown()
        end
        TaskTracker._ttRefreshListLast = GetTime and GetTime() or nil
        return
    end

    -- ─────────────────────────────────────
    -- Browse mode renderer (pooled + virtualized)
    -- ─────────────────────────────────────
    -- Leaving edit mode: remove any legacy frames.
    ClearLegacyRows()
    TaskTracker._ttListPools = TaskTracker._ttListPools or {}
    TaskTracker._ttListActive = TaskTracker._ttListActive or {}
    TaskTracker._ttListModel = TaskTracker._ttListModel or nil
    TaskTracker._ttListModelHeight = TaskTracker._ttListModelHeight or 0
    TaskTracker._ttListDirtyLayout = (TaskTracker._ttListDirtyLayout ~= false) and true or false
    TaskTracker._ttListDirtyPaint = (TaskTracker._ttListDirtyPaint ~= false) and true or false

    -- Expose for scroll-driven repaint without rebuilding layout.
    TaskTracker._ttPaintVisibleList = PaintVisible

    local rowW = PANEL_WIDTH - TaskTracker.GetScrollGutter()
    if TaskTracker._ttListDirtyLayout or not TaskTracker._ttListModel then
        -- Model order changes on expand/collapse; drop index-based frame slots so we don't
        -- accidentally reuse an old frame for a different node/kind at the same index.
        clearAllActiveVirtualFrames()
        local model, totalH = BuildRenderModel(viewTree, rowW)
        TaskTracker._ttListModel = model
        TaskTracker._ttListModelHeight = totalH
        scrollChild:SetSize(rowW, totalH)
        local sf = TaskTracker.scrollFrame
        if sf and sf.UpdateScrollBar then
            sf.UpdateScrollBar()
        end
        TaskTracker._ttListDirtyLayout = false
        TaskTracker._ttListDirtyPaint = true
    end
    if TaskTracker._ttListDirtyPaint then
        if TaskTracker.SyncTitleBarIcons then
            TaskTracker.SyncTitleBarIcons()
        end
        if TaskTracker.ValidateNoteWindow then
            TaskTracker.ValidateNoteWindow()
        end
        TaskTracker.ValidateQuickCommandsPanel()
        if TaskTracker.RefreshPeekInlineCommandsIfShown then
            TaskTracker.RefreshPeekInlineCommandsIfShown()
        end
        PaintVisible()
        TaskTracker._ttListDirtyPaint = false
    else
        -- Still repaint on scroll/viewport changes.
        PaintVisible()
    end

    -- Track when we last did a full rebuild so callers that spam RefreshList()
    -- (bag/quest/widget churn) can be throttled without losing correctness.
    TaskTracker._ttRefreshListLast = GetTime and GetTime() or nil

    if PerfEnabled() then
        local p = TaskTracker._ttPerf or {}
        local now = NowMs()
        p._lastPrint = p._lastPrint or 0
        if (now - p._lastPrint) > 2000 then
            p._lastPrint = now
            local lm = tonumber(p.layoutMs) or 0
            local pm = tonumber(p.paintMs) or 0
            local src = TaskTracker._ttRefreshSource and TaskTracker._ttRefreshSource.last
            if src and src ~= "" then
                print(string.format("|cff00ff00TaskTracker|r perf: layout %.2fms, paint %.2fms (%s)", lm, pm, tostring(src)))
            else
                print(string.format("|cff00ff00TaskTracker|r perf: layout %.2fms, paint %.2fms", lm, pm))
            end
        end
    end
end

-- Called by the scroll frame to repaint visible rows only.
function TaskTracker.OnListScroll()
    if not TaskTracker._ttListModel or not ShouldPaintTaskList() then return end
    if IsEditMode() then return end
    local paint = TaskTracker._ttPaintVisibleList
    if paint then paint() end
end

-- Dirty-flag helpers so callers can choose layout vs paint.
function TaskTracker.MarkListPaintDirty()
    TaskTracker._ttListDirtyPaint = true
end

function TaskTracker.MarkListLayoutDirty()
    TaskTracker._ttListDirtyLayout = true
    TaskTracker._ttListDirtyPaint = true
    TaskTracker._ttListLayoutEpoch = (TaskTracker._ttListLayoutEpoch or 0) + 1
end

--- Use this for progress-only changes where layout is usually stable.
--- Falls back to layout-dirty when hide-completed or grow-wrapping could change row visibility/height.
function TaskTracker.MarkListDirtyFromProgressChange()
    local db = TaskTrackerDB
    local useGrow = TaskTracker.GetTaskLabelOverflowMode and TaskTracker.GetTaskLabelOverflowMode() == "grow"
    if (db and db.hideCompleted) or useGrow then
        TaskTracker.MarkListLayoutDirty()
    else
        TaskTracker.MarkListPaintDirty()
    end
end

--- Bypass coalescing (same-frame deferral). Use sparingly; most callers should use RefreshList().
function TaskTracker.RefreshListNow()
    if not TaskTracker.scrollChild or not TaskTrackerDB or not TaskTrackerDB.tree then return end
    if not IsPlayerInWorld() then return end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker._ttRefreshListCoalesce then
        TaskTracker._ttRefreshListCoalesce:Cancel()
        TaskTracker._ttRefreshListCoalesce = nil
    end
    TaskTracker._ttRefreshListNextAt = nil
    if ShouldPaintTaskList() then
        RefreshListExecute()
    end
end

function TaskTracker.RefreshList()
    if TaskTracker.QueueLiveShareScan then
        TaskTracker.QueueLiveShareScan()
    end
    local scrollChild = TaskTracker.scrollChild
    local db          = TaskTrackerDB
    if not scrollChild or not db or not db.tree then return end
    if not IsPlayerInWorld() then return end
    if not ShouldPaintTaskList() then
        return
    end

    -- Default to paint-only dirtiness unless a caller explicitly marked layout dirty.
    if TaskTracker.MarkListDirtyFromProgressChange and not TaskTracker._ttListDirtyLayout and not TaskTracker._ttListDirtyPaint then
        TaskTracker.MarkListDirtyFromProgressChange()
    end

    -- Throttle full rebuilds: at most ~10Hz, but avoid cancel/reschedule churn.
    -- Continuous event spam used to repeatedly cancel and push the timer out, which
    -- can delay paints indefinitely and then hitch when the spam stops.
    local MIN_INTERVAL = 0.10
    local now = (GetTime and GetTime()) or 0
    local last = TaskTracker._ttRefreshListLast or 0

    local desiredAt = now
    if now > 0 and last > 0 then
        local floorAt = last + MIN_INTERVAL
        if desiredAt < floorAt then desiredAt = floorAt end
    end

    local nextAt = TaskTracker._ttRefreshListNextAt
    if nextAt and nextAt > 0 then
        -- Already scheduled at (or before) the desired time; keep it.
        if nextAt <= desiredAt then
            return
        end
    end

    if TaskTracker._ttRefreshListCoalesce then
        TaskTracker._ttRefreshListCoalesce:Cancel()
        TaskTracker._ttRefreshListCoalesce = nil
    end

    local delay = 0
    if desiredAt > now then delay = desiredAt - now end
    TaskTracker._ttRefreshListNextAt = desiredAt
    TaskTracker._ttRefreshListCoalesce = C_Timer.NewTimer(delay, function()
        TaskTracker._ttRefreshListCoalesce = nil
        TaskTracker._ttRefreshListNextAt = nil
        if not ShouldPaintTaskList() then return end
        RefreshListExecute()
    end)
end