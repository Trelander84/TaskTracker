-- UI/Share.lua
-- Import / export popup (serialized groups and tasks)

TaskTracker = TaskTracker or {}

local trim = TaskTracker.Trim

function TaskTracker.OpenShareImportExportDialog(opts)
    if type(opts) ~= "table" then return end
    TaskTracker.EnsureShareImportExportDialog()
    local f = TaskTracker._shareImportExportDialog
    f._opts = opts
    f.TitleText:SetText(opts.title or "Import / export")
    local hint = opts.hint
    if f._hintFs then
        if hint and hint ~= "" then
            f._hintFs:SetText(hint)
            f._hintFs:Show()
        else
            f._hintFs:SetText("")
            f._hintFs:Hide()
        end
    end
    if f._reflowShareLayout then
        f:_reflowShareLayout()
    end
    local exportText = ""
    if type(opts.getExportText) == "function" then
        local ok, s = pcall(opts.getExportText)
        if ok and type(s) == "string" then
            exportText = s
        end
    end
    f._edit:SetText(exportText)
    if f._applyShareEditColor then
        f:_applyShareEditColor()
    end
    if f._refreshBtn then
        f._refreshBtn:SetShown(type(opts.getExportText) == "function")
    end
    f._status:SetText("")
    f._status:Hide()
    f:ClearAllPoints()
    if TaskTracker.AnchorFrameNearScreenTop then
        TaskTracker.AnchorFrameNearScreenTop(f, 0, 0.1)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    f:Show()
    f:Raise()
    if f._fitShareEdit then
        f:_fitShareEdit()
    end
    f._edit:SetFocus()
    if exportText ~= "" and opts.focusExportSelect then
        f._edit:HighlightText()
    end
    if f._setShareEditFocused then
        f:_setShareEditFocused(true)
    end
end

function TaskTracker.EnsureShareImportExportDialog()
    local f = TaskTracker._shareImportExportDialog
    if f then return f end

    local dialog = TaskTracker.MakePanel("TaskTrackerShareDialog", UIParent, 440, 400)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(270)
    dialog:Hide()
    dialog:SetClampedToScreen(true)

    local content = dialog.Content
    local t = TaskTracker.GetTheme()

    local hintFs = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    hintFs:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -8)
    hintFs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -8)
    hintFs:SetJustifyH("LEFT")
    hintFs:SetJustifyV("TOP")
    hintFs:SetWordWrap(true)
    TaskTracker.SetTextColor(hintFs, "textSecondary")
    dialog._hintFs = hintFs

    local importBtn = TaskTracker.MakeButton(content, "Import", 100, 24)
    importBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 10, 10)

    local closeBtn = TaskTracker.MakeButton(content, "Close", 80, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -10, 10)
    closeBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)

    local refreshBtn = TaskTracker.MakeButton(content, "Fill export", 100, 24)
    refreshBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)

    local status = TaskTracker.CreateFontString(content, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    status:SetPoint("BOTTOMLEFT", importBtn, "TOPLEFT", 0, 8)
    status:SetPoint("BOTTOMRIGHT", closeBtn, "TOPRIGHT", 0, 8)
    status:SetJustifyH("LEFT")
    status:SetHeight(40)
    status:SetWordWrap(true)
    TaskTracker.SetTextColor(status, "danger")
    dialog._status = status

    local mid = CreateFrame("Frame", nil, content)
    mid:EnableMouse(true)
    mid:SetClipsChildren(true)
    mid:SetPoint("TOPLEFT", hintFs, "BOTTOMLEFT", 0, -8)
    mid:SetPoint("TOPRIGHT", hintFs, "BOTTOMRIGHT", 0, -8)
    mid:SetPoint("BOTTOMLEFT", status, "TOPLEFT", 0, -6)
    mid:SetPoint("BOTTOMRIGHT", status, "TOPRIGHT", 0, -6)
    local midBg = mid:CreateTexture(nil, "BACKGROUND")
    midBg:SetAllPoints()
    TaskTracker.SetColor(midBg, "inputBg")
    TaskTracker.MakeBorder(mid, "border")
    dialog._mid = mid

    local scroll = CreateFrame("ScrollFrame", nil, mid)
    scroll:SetPoint("TOPLEFT", mid, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", mid, "BOTTOMRIGHT", -8, 4)
    TaskTracker.MakeScrollBar(scroll, mid)
    dialog._scroll = scroll

    local ring = CreateFrame("Frame", nil, mid)
    ring:SetPoint("TOPLEFT", scroll, "TOPLEFT", -1, 1)
    ring:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 1, -1)
    ring:EnableMouse(false)
    local focusEdges = {}
    for _, edge in ipairs({ "LEFT", "RIGHT", "TOP", "BOTTOM" }) do
        local tex = TaskTracker.MakeEdge(ring, edge, "accent", 2)
        tex:Hide()
        focusEdges[#focusEdges + 1] = tex
    end
    function dialog:_setShareEditFocused(on)
        for i = 1, #focusEdges do
            focusEdges[i]:SetShown(on and true or false)
        end
    end

    local eb = CreateFrame("EditBox", "TaskTrackerShareEdit", scroll)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(120000)
    eb:SetFontObject(t.fontNormal or "GameFontNormalSmall")
    TaskTracker.ClearFontShadow(eb)
    eb:SetTextInsets(6, 6, 6, 6)
    eb:SetAutoFocus(false)
    eb:EnableMouse(true)
    eb:EnableKeyboard(true)
    if eb.SetBlinkSpeed then
        eb:SetBlinkSpeed(0.12)
    end
    pcall(function() eb:SetSplitFullWords(false) end)
    function dialog:_applyShareEditColor()
        local theme = TaskTracker.GetTheme and TaskTracker.GetTheme()
        local c = theme and theme.textPrimary
        if c then
            eb:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        else
            eb:SetTextColor(1, 1, 1, 1)
        end
    end
    dialog:_applyShareEditColor()
    eb:SetScript("OnEscapePressed", function()
        dialog:Hide()
    end)
    eb:SetScript("OnEditFocusGained", function()
        dialog:_applyShareEditColor()
        dialog:_setShareEditFocused(true)
    end)
    eb:SetScript("OnEditFocusLost", function()
        dialog:_setShareEditFocused(false)
    end)
    mid:SetScript("OnMouseDown", function()
        eb:SetFocus()
    end)
    scroll:SetScrollChild(eb)
    dialog._edit = eb

    local measure = mid:CreateFontString(nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    measure:Hide()
    measure:SetWordWrap(true)
    measure:SetJustifyH("LEFT")
    measure:SetNonSpaceWrap(true)
    TaskTracker.ClearFontShadow(measure)
    dialog._measure = measure

    local fitting = false
    function dialog:_fitShareEdit()
        if fitting then return end
        local sc = self._scroll
        local edit = self._edit
        local fs = self._measure
        if not sc or not edit or not fs then return end
        local w = sc:GetWidth()
        if not w or w < 20 then return end
        fitting = true
        local prev = sc:GetVerticalScroll() or 0
        local inner = math.max(20, w - 12)
        edit:SetWidth(w)
        fs:SetWidth(inner)
        fs:SetText(edit:GetText() or "")
        local textH = fs:GetStringHeight() or 0
        local viewH = sc:GetHeight() or 0
        edit:SetHeight(math.max(viewH, textH + 16))
        local maxScroll = math.max(0, (edit:GetHeight() or 0) - viewH)
        if prev > maxScroll then prev = maxScroll end
        sc:SetVerticalScroll(prev)
        if sc.UpdateScrollBar then
            sc:UpdateScrollBar()
        end
        fitting = false
    end

    eb:SetScript("OnTextChanged", function()
        dialog:_fitShareEdit()
    end)
    local followCaret = true
    eb:SetScript("OnCursorChanged", function(self, _, y, _, h)
        if not followCaret then return end
        local pos = self:GetCursorPosition()
        if pos == self._ttCaret then return end
        self._ttCaret = pos
        local view = scroll:GetHeight() or 0
        if view <= 0 then return end
        local cur = scroll:GetVerticalScroll() or 0
        local cursor = -(y or 0)
        local line = h or 0
        if cursor < cur then
            scroll:SetVerticalScroll(math.max(0, cursor))
        elseif cursor + line > cur + view then
            local range = scroll:GetVerticalScrollRange() or 0
            scroll:SetVerticalScroll(math.min(range, cursor + line - view))
        end
    end)
    eb:EnableMouseWheel(true)
    eb:SetScript("OnMouseWheel", function(_, delta)
        followCaret = false
        local wheel = scroll:GetScript("OnMouseWheel")
        if wheel then
            wheel(scroll, delta)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                followCaret = true
            end)
        else
            followCaret = true
        end
    end)
    scroll:HookScript("OnSizeChanged", function()
        dialog:_fitShareEdit()
    end)

    function dialog:_reflowShareLayout()
        self._mid:ClearAllPoints()
        if self._hintFs and self._hintFs:IsShown() then
            self._mid:SetPoint("TOPLEFT", self._hintFs, "BOTTOMLEFT", 0, -8)
            self._mid:SetPoint("TOPRIGHT", self._hintFs, "BOTTOMRIGHT", 0, -8)
        else
            self._mid:SetPoint("TOPLEFT", self.Content, "TOPLEFT", 10, -8)
            self._mid:SetPoint("TOPRIGHT", self.Content, "TOPRIGHT", -10, -8)
        end
        self._mid:SetPoint("BOTTOMLEFT", self._status, "TOPLEFT", 0, -6)
        self._mid:SetPoint("BOTTOMRIGHT", self._status, "TOPRIGHT", 0, -6)
        if self._fitShareEdit then
            self:_fitShareEdit()
        end
    end

    local function setError(msg)
        if msg and msg ~= "" then
            status:SetText(msg)
            status:Show()
        else
            status:SetText("")
            status:Hide()
        end
    end

    importBtn:SetScript("OnClick", function()
        setError("")
        local opts = dialog._opts
        if not opts then return end
        local text = trim(eb:GetText())
        if type(opts.importText) == "function" then
            local ok, result = pcall(opts.importText, text)
            if not ok then
                setError(result or "Import failed.")
                return
            end
            if type(result) == "string" and result ~= "" then
                setError(result)
                return
            end
            dialog:Hide()
            return
        end
        if type(opts.onImport) ~= "function" then return end
        local data, err = TaskTracker.DecodeShareExportString(text)
        if not data then
            setError(err or "Could not read export.")
            return
        end
        local root, err2 = TaskTracker.InflateShareEnvelope(data)
        if not root then
            setError(err2 or "Invalid export.")
            return
        end
        local ok, err3 = pcall(opts.onImport, root.type, root, data)
        if not ok then
            setError(err3 or "Import failed.")
            return
        end
        if err3 and err3 ~= "" then
            setError(err3)
            return
        end
        dialog:Hide()
    end)

    refreshBtn:SetScript("OnClick", function()
        setError("")
        local opts = dialog._opts
        if not opts or type(opts.getExportText) ~= "function" then return end
        local ok, s = pcall(opts.getExportText)
        if ok and type(s) == "string" and s ~= "" then
            eb:SetText(s)
            eb:SetFocus()
            eb:HighlightText()
        end
    end)
    dialog._refreshBtn = refreshBtn

    dialog:_reflowShareLayout()

    TaskTracker._shareImportExportDialog = dialog
    dialog:SetScale(TaskTracker.GetUIScalePercent and TaskTracker.GetUIScalePercent() / 100 or 1)
    return dialog
end
