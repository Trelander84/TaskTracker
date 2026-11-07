-- UI/ThemeEditor.lua
-- Duplicate a built-in (or edit an existing custom). Built-in files are never written.

TaskTracker = TaskTracker or {}

local HERO_LABELS = {
    bg            = "Window",
    headerBg      = "Headers / buttons",
    headerBg2     = "Sub-headers",
    headerBg3     = "Collections headers",
    headerBgHere  = "Current zone",
    inputBg       = "Fields",
    border        = "Borders",
    accent        = "Accent",
    textAccent    = "Accent text",
    textPrimary   = "Main text",
    icon          = "Icons",
    textSecondary = "Secondary text",
    complete      = "Complete",
    warning       = "Warning",
    danger        = "Danger",
}

local ROW_H = 26
local editor

local function hideColorPicker()
    if ColorPickerFrame and ColorPickerFrame.IsShown and ColorPickerFrame:IsShown() then
        ColorPickerFrame:Hide()
    end
end

local function paintSwatch(tex, c)
    if not tex or type(c) ~= "table" then return end
    tex:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, 1)
end

local function setDraftColor(draft, key, r, g, b)
    local prev = draft.colors[key]
    local a = (prev and prev[4]) or 1
    draft.colors[key] = { r, g, b, a }
end

local function refreshEditorPreview(frame, draft)
    if not frame or not draft then return end
    paintSwatch(frame._prevBg, draft.colors.bg)
    paintSwatch(frame._prevHeader, draft.colors.headerBg)
    paintSwatch(frame._prevAccent, draft.colors.accent)
    if frame._prevText then
        local c = draft.colors.textPrimary
        if c then
            frame._prevText:SetTextColor(c[1], c[2], c[3], 1)
        end
    end
    if frame._rows then
        for key, row in pairs(frame._rows) do
            local c = draft.colors[key]
            paintSwatch(row.swatchTex, c)
            if row.hex and not row.hex:HasFocus() then
                row.hex:SetText(TaskTracker.ColorArrayToHex(c))
            end
        end
    end
end

local function stackEditorAboveOptions(frame)
    if not frame then return end
    -- Options is DIALOG @ 250; default MakePanel level sits behind it.
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    local opts = TaskTracker.optionsPanel
    local lvl = 280
    if opts and opts.GetFrameLevel then
        lvl = math.max(lvl, (opts:GetFrameLevel() or 0) + 30)
    end
    frame:SetFrameLevel(lvl)
    frame:Raise()
end

local function stackColorPickerAboveEditor()
    if not ColorPickerFrame then return end
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    local base = 330
    if editor and editor.GetFrameLevel then
        base = math.max(base, (editor:GetFrameLevel() or 0) + 40)
    end
    ColorPickerFrame:SetFrameLevel(base)
    ColorPickerFrame:Raise()
end

local function openColorPicker(draft, key, onLive)
    local c = draft.colors[key] or { 1, 1, 1, 1 }
    local function apply(r, g, b)
        setDraftColor(draft, key, r, g, b)
        if onLive then onLive() end
    end
    local info = {
        r = c[1], g = c[2], b = c[3],
        hasOpacity = false,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            apply(r, g, b)
        end,
        cancelFunc = function(prev)
            if type(prev) == "table" then
                apply(prev.r or c[1], prev.g or c[2], prev.b or c[3])
            else
                apply(c[1], c[2], c[3])
            end
        end,
    }
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
        stackColorPickerAboveEditor()
        return
    end
    if not ColorPickerFrame then return end
    ColorPickerFrame.func = info.swatchFunc
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame.cancelFunc = info.cancelFunc
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
    ColorPickerFrame:Show()
    stackColorPickerAboveEditor()
end

function TaskTracker.HideThemeEditor()
    hideColorPicker()
    if editor then
        editor:Hide()
    end
end

local function ensureEditor()
    if editor then return editor end
    local frame = TaskTracker.MakePanel("TaskTrackerThemeEditor", UIParent, 420, 560)
    stackEditorAboveOptions(frame)
    frame:EnableMouse(true)
    frame:Hide()
    frame.TitleText:SetText("Customize theme")
    if TaskTracker.AnchorFrameNearScreenTop then
        TaskTracker.AnchorFrameNearScreenTop(frame, 180, 0.12)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 180, 40)
    end

    local content = frame.Content
    content:EnableMouse(true)

    local hint = TaskTracker.CreateFontString(content, nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -8)
    hint:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -8)
    hint:SetJustifyH("LEFT")
    if hint.SetWordWrap then hint:SetWordWrap(true) end
    TaskTracker.SetTextColor(hint, "textSecondary")
    hint:SetText("Built-in themes stay as they are. Save writes a custom copy.")
    frame._hint = hint

    local nameLbl = TaskTracker.CreateFontString(content, nil, "OVERLAY", "GameFontNormalSmall")
    nameLbl:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
    TaskTracker.SetTextColor(nameLbl, "textSecondary")
    nameLbl:SetText("Name:")
    local nameBox = TaskTracker.MakeEditBox(content, "TaskTrackerThemeName", 250, 22)
    nameBox:SetPoint("LEFT", nameLbl, "RIGHT", 8, 0)
    nameBox:SetMaxLetters(40)
    frame._nameBox = nameBox

    local basedLbl = TaskTracker.CreateFontString(content, nil, "OVERLAY", "GameFontNormalSmall")
    basedLbl:SetPoint("TOPLEFT", nameLbl, "BOTTOMLEFT", 0, -8)
    basedLbl:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    basedLbl:SetJustifyH("LEFT")
    if basedLbl.SetWordWrap then basedLbl:SetWordWrap(true) end
    TaskTracker.SetTextColor(basedLbl, "textSecondary")
    frame._basedLbl = basedLbl

    local prev = CreateFrame("Frame", nil, content)
    prev:SetPoint("TOPLEFT", basedLbl, "BOTTOMLEFT", 0, -8)
    prev:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, 0)
    prev:SetHeight(28)
    local function makePrev(xOff, w)
        local t = prev:CreateTexture(nil, "ARTWORK")
        t:SetSize(w, 22)
        t:SetPoint("LEFT", prev, "LEFT", xOff, 0)
        return t
    end
    frame._prevBg = makePrev(0, 48)
    frame._prevHeader = makePrev(52, 48)
    frame._prevAccent = makePrev(104, 48)
    local prevText = TaskTracker.CreateFontString(prev, nil, "OVERLAY", "GameFontNormal")
    prevText:SetPoint("LEFT", prev, "LEFT", 160, 0)
    prevText:SetText("Sample text")
    frame._prevText = prevText

    local listHost = CreateFrame("Frame", nil, content)
    listHost:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -8)
    listHost:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 40)
    local _, scroll, child = TaskTracker.MakeScrollPane(listHost, {
        useParent = true,
        pane = false,
        childWidth = 380,
    })
    frame._scroll = scroll
    frame._child = child

    local rows = {}
    local keys = TaskTracker.THEME_HERO_KEYS
    for i = 1, #keys do
        local key = keys[i]
        local y = -((i - 1) * ROW_H)
        local lab = TaskTracker.CreateFontString(child, nil, "OVERLAY", "GameFontNormalSmall")
        lab:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y - 4)
        lab:SetWidth(130)
        lab:SetJustifyH("LEFT")
        TaskTracker.SetTextColor(lab, "textSecondary")
        lab:SetText(HERO_LABELS[key] or key)

        local sw = CreateFrame("Button", nil, child)
        sw:SetSize(28, 18)
        sw:SetPoint("LEFT", lab, "RIGHT", 8, 0)
        local swTex = sw:CreateTexture(nil, "ARTWORK")
        swTex:SetAllPoints()
        TaskTracker.MakeBorder(sw, "border")

        local hex = TaskTracker.MakeEditBox(child, nil, 72, 20)
        hex:SetPoint("LEFT", sw, "RIGHT", 8, 0)
        hex:SetMaxLetters(7)
        hex:SetAutoFocus(false)

        rows[key] = { lab = lab, sw = sw, swatchTex = swTex, hex = hex, key = key }
    end
    child:SetHeight(#keys * ROW_H + 8)
    frame._rows = rows

    local saveBtn = TaskTracker.MakeButton(content, "Save custom", 120, 22)
    saveBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 10, 10)
    local cancelBtn = TaskTracker.MakeButton(content, "Cancel", 80, 22)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    local delBtn = TaskTracker.MakeButton(content, "Delete", 80, 22)
    delBtn:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -10, 10)
    TaskTracker.SetColor(delBtn.bg, "danger")
    frame._saveBtn = saveBtn
    frame._delBtn = delBtn

    frame.CloseButton:SetScript("OnClick", function()
        TaskTracker.HideThemeEditor()
    end)
    cancelBtn:SetScript("OnClick", function()
        TaskTracker.HideThemeEditor()
    end)
    frame:SetScript("OnHide", function()
        hideColorPicker()
    end)

    editor = frame
    TaskTracker.themeEditor = frame
    if TaskTracker.ApplyUIScale then
        TaskTracker.ApplyUIScale()
    end
    return frame
end

local function bindEditor(frame, draft)
    frame._draft = draft
    frame._nameBox:SetText(draft.name or "Custom")
    local baseTh = TaskTracker.Themes[draft.basedOn]
    local baseName = (baseTh and baseTh.name) or draft.basedOn or "Dark"
    frame._basedLbl:SetText("Based on: " .. baseName .. " — fonts, spacing, and stripes stay with this base. Original is unchanged.")
    if draft.key then
        frame._delBtn:Show()
        frame.TitleText:SetText("Edit custom theme")
    else
        frame._delBtn:Hide()
        frame.TitleText:SetText("New custom theme")
    end

    local function live()
        refreshEditorPreview(frame, draft)
    end

    for key, row in pairs(frame._rows) do
        row.sw:SetScript("OnClick", function()
            openColorPicker(draft, key, live)
        end)
        row.hex:SetScript("OnEnterPressed", function(self)
            local r, g, b = TaskTracker.ParseHexColor(self:GetText())
            if r then
                setDraftColor(draft, key, r, g, b)
            end
            live()
            self:ClearFocus()
        end)
        row.hex:SetScript("OnEscapePressed", function(self)
            live()
            self:ClearFocus()
        end)
        row.hex:SetScript("OnEditFocusLost", function(self)
            local r, g, b = TaskTracker.ParseHexColor(self:GetText())
            if r then
                setDraftColor(draft, key, r, g, b)
            end
            live()
        end)
    end

    frame._saveBtn:SetScript("OnClick", function()
        draft.name = frame._nameBox:GetText()
        local id, err = TaskTracker.SaveCustomTheme({
            key = draft.key,
            name = draft.name,
            basedOn = draft.basedOn,
            colors = draft.colors,
        })
        if not id then
            if err == "limit" then
                print("|cffff6666Task Tracker:|r At most 20 custom themes.")
            end
            return
        end
        TaskTracker.HideThemeEditor()
        TaskTracker.SetTheme(id)
    end)

    frame._delBtn:SetScript("OnClick", function()
        if not draft.key then return end
        StaticPopupDialogs["TASKTRACKER_DELETE_CUSTOM_THEME"] = {
            text = "Delete custom theme \"%s\"?\nBuilt-in themes are not affected.",
            button1 = YES,
            button2 = NO,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            OnAccept = function()
                TaskTracker.HideThemeEditor()
                TaskTracker.DeleteCustomTheme(draft.key)
            end,
        }
        StaticPopup_Show("TASKTRACKER_DELETE_CUSTOM_THEME", draft.name or "Custom")
    end)

    live()
end

--- Open the editor. Built-in → new custom on Save. Existing custom → edit that copy.
function TaskTracker.OpenThemeEditor()
    local curKey = (TaskTrackerDB and TaskTrackerDB.theme) or "dark"
    local cur = TaskTracker.Themes[curKey] or TaskTracker.GetTheme()
    local draft
    if TaskTracker.IsCustomTheme(curKey) then
        local spec = TaskTrackerDB.customThemes and TaskTrackerDB.customThemes[curKey]
        draft = {
            key = curKey,
            name = (spec and spec.name) or (cur and cur.name) or "Custom",
            basedOn = TaskTracker.GetBuiltinThemeKey((spec and spec.basedOn) or curKey),
            colors = TaskTracker.SnapshotThemeHeroColors(cur),
        }
        if spec and type(spec.colors) == "table" then
            for i = 1, #TaskTracker.THEME_HERO_KEYS do
                local key = TaskTracker.THEME_HERO_KEYS[i]
                local c = spec.colors[key]
                if type(c) == "table" then
                    draft.colors[key] = { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
                end
            end
        end
    else
        local srcKey = (cur and cur.key) or "dark"
        local srcName = (cur and cur.name) or "Dark"
        draft = {
            key = nil,
            name = srcName .. " custom",
            basedOn = TaskTracker.GetBuiltinThemeKey(srcKey),
            colors = TaskTracker.SnapshotThemeHeroColors(cur),
        }
    end
    local frame = ensureEditor()
    bindEditor(frame, draft)
    frame:Show()
    if TaskTracker.ApplyUIScale then
        TaskTracker.ApplyUIScale()
    end
    stackEditorAboveOptions(frame)
end
