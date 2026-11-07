-- UI/Theme.lua
-- Theme manager and helper functions
-- All UI files access the active theme through TaskTracker.T
-- Switch themes with TaskTracker.SetTheme("dark"), ("nord"), ("bronzed"), ("void"),
-- ("verdant"), ("gilded"), ("tome"), ("parchment"), ("ivory"), or ("paper").

TaskTracker        = TaskTracker or {}
TaskTracker.Themes = TaskTracker.Themes or {}

-- ─────────────────────────────────────
-- Safe theme accessor
-- Always returns a valid theme table
-- ─────────────────────────────────────
local function T()
    if not TaskTracker.T then
        TaskTracker.T = TaskTracker.Themes["dark"]
    end
    return TaskTracker.T
end

--- Drop the 1px shadow that Blizzard font objects copy onto our text.
--- Does not change the shared font object, so the rest of the game UI keeps its shadow.
function TaskTracker.ClearFontShadow(fs)
    if not fs then return fs end
    if fs.SetShadowColor then
        fs:SetShadowColor(0, 0, 0, 0)
    end
    if fs.SetShadowOffset then
        fs:SetShadowOffset(0, 0)
    end
    return fs
end

function TaskTracker.FrameInOptionsChrome(frame)
    local p = frame
    for _ = 1, 12 do
        if not p then return false end
        if p._ttOptionsChrome then return true end
        if p._ttNotOptionsChrome then return false end
        p = p.GetParent and p:GetParent() or nil
    end
    return false
end

function TaskTracker.CreateFontString(parent, name, layer, inherits)
    local fs = parent:CreateFontString(name, layer, inherits)
    TaskTracker.ClearFontShadow(fs)
    if TaskTracker.FrameInOptionsChrome(parent) and TaskTracker.ApplyOptionsFont then
        local face = fs._ttOptionsFace
        if not face then
            if inherits == "GameFontNormal" or inherits == "GameFontHighlight" or inherits == "GameFontNormalLarge" then
                face = "title"
            else
                face = "body"
            end
        end
        if fs._ttOptionsLockedPx then
            TaskTracker.ApplyOptionsFont(fs, face, fs._ttOptionsLockedPx)
        else
            TaskTracker.ApplyOptionsFont(fs, face)
        end
    end
    return fs
end

--- Anchor a frame below the top of UIParent (ElvUI-style: not dead center).
--- yFrac is fraction of UIParent height from the top to inset the frame’s TOP edge (e.g. 0.12–0.15).
function TaskTracker.AnchorFrameNearScreenTop(frame, xOffset, yFrac)
    if not frame then return end
    xOffset = xOffset or 0
    yFrac = yFrac or 0.13
    local h = UIParent and UIParent:GetHeight() or 800
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", xOffset, -math.floor(h * yFrac + 0.5))
end

--- First atlas name that exists in the client; otherwise returns the first argument.
function TaskTracker.FirstValidAtlas(...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then
            return name
        end
    end
    return (select(1, ...))
end

--- `icon` is a file id, an atlas name, or an icon file name. `command` lets a
--- `/use item:` button use the client item icon when the stored name is not an atlas.
function TaskTracker.ApplyCommandIconToTexture(tex, icon, command)
    if not tex then return end
    icon = TaskTracker.NormalizeCommandIcon and TaskTracker.NormalizeCommandIcon(icon, command) or icon
    local knownAtlas = false
    if type(icon) == "string" and icon ~= "" then
        knownAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(icon) and true or false
        if not knownAtlas and TaskTracker.ItemIconFileFromCommand then
            local file = TaskTracker.ItemIconFileFromCommand(command)
            if file then icon = file end
        end
    end
    if type(icon) == "string" and icon ~= "" then
        if knownAtlas then
            local ok = pcall(function()
                tex:SetAtlas(icon, false)
            end)
            if ok then
                tex:SetVertexColor(1, 1, 1, 1)
                tex:Show()
                return
            end
        end
        -- Item icon file names are not atlases. SetTexture needs the Icons path.
        local path = icon
        if not path:find("\\", 1, true) and not path:find("/", 1, true) then
            path = "Interface\\Icons\\" .. path
        end
        local texOk, found = pcall(function()
            return tex:SetTexture(path)
        end)
        if texOk and found then
            tex:SetVertexColor(1, 1, 1, 1)
            tex:Show()
            return
        end
        icon = TaskTracker.DEFAULT_COMMAND_ICON or 134400
    end
    tex:SetTexture(tonumber(icon) or 134400)
    tex:SetVertexColor(1, 1, 1, 1)
    tex:Show()
end

-- White chrome glyphs in Media/Icons. RGB is white; the shape is the alpha.
-- SetVertexColor multiplies. A missing icon color uses accent text.
local CHROME_ICON_DIR = "Interface\\AddOns\\TaskTracker\\Media\\Icons\\"

local function chromeIconColor(src)
    if type(src) ~= "table" then return nil end
    if type(src.icon) == "table" then return src.icon end
    if type(src.textAccent) == "table" then return src.textAccent end
    return src.textPrimary
end

function TaskTracker.ChromeIconPath(name)
    return CHROME_ICON_DIR .. tostring(name or "") .. ".png"
end

function TaskTracker.TintChromeIcon(tex)
    if not tex then return end
    local theme = T()
    local c = chromeIconColor(theme)
    if c then
        tex:SetVertexColor(c[1], c[2], c[3], 1)
    end
end

-- Blizzard atlases used before the white set. `note` / `mail` / `search` try fallbacks.
local CLASSIC_ATLAS = {
    eye       = "UI-HUD-MicroMenu-Groupfinder-Mouseover",
    ["eye-off"] = "UI-HUD-MicroMenu-Groupfinder-Disabled",
    gear      = "mechagon-projects",
    edit      = "Professions-Crafting-Orders-Icon",
    expand    = "Map-Filter-Button",
    help      = "QuestArtifact",
    note      = { "poi-workorders", "newplayerchat-chatchannel-edit-icon", "QuestRepeatableTurnin" },
    arrow     = "shop-header-arrow",
    mail      = { "UI-HUD-Minimap-Mail-Up", "poi-mail" },
    search    = { "shop-games-magnifyingglass", "search", "common-search-magnifyingglass" },
    mark      = "pvptalents-selectedarrow",
    copy      = { "common-icon-copy", "Professions-Crafting-Orders-Copy" },
    plus      = "QuestLog-icon-Expand",
    minus     = "QuestLog-icon-shrink",
    close     = { "Islands-MarkedArea" },
}

function TaskTracker.GetIconSet()
    local s = TaskTrackerDB and TaskTrackerDB.iconSet
    if s == "tintable" then return "tintable" end
    return "classic"
end

function TaskTracker.ClassicAtlas(name)
    local spec = CLASSIC_ATLAS[name]
    if type(spec) == "table" then
        for i = 1, #spec do
            local atlas = spec[i]
            if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
                return atlas
            end
        end
        return nil
    end
    return spec
end

--- `mode` overrides the saved set so Style can preview both at once.
function TaskTracker.ApplyChromeIcon(tex, name, mode)
    if not tex or not name or name == "" then return end
    mode = mode or TaskTracker.GetIconSet()
    if mode == "classic" then
        local atlas = TaskTracker.ClassicAtlas(name)
        if atlas then
            local ok = pcall(function()
                tex:SetAtlas(atlas, false)
            end)
            if ok then
                tex:SetVertexColor(1, 1, 1, 1)
                tex:Show()
                return
            end
        end
    end
    tex:SetTexture(TaskTracker.ChromeIconPath(name))
    TaskTracker.TintChromeIcon(tex)
    tex:Show()
end

--- Help text. Tintable icons use |T with a 0–255 multiply. Classic uses the atlas escape.
function TaskTracker.ChromeIconMarkup(name, w, h)
    w = tonumber(w) or 18
    h = tonumber(h) or 18
    if TaskTracker.GetIconSet() == "classic" then
        local atlas = TaskTracker.ClassicAtlas(name)
        if atlas then
            return string.format("|A:%s:%d:%d|a", atlas, h, w)
        end
    end
    local theme = T()
    local c = chromeIconColor(theme) or { 1, 1, 1, 1 }
    local r = math.floor((c[1] or 1) * 255 + 0.5)
    local g = math.floor((c[2] or 1) * 255 + 0.5)
    local b = math.floor((c[3] or 1) * 255 + 0.5)
    return string.format(
        "|T%s:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t",
        TaskTracker.ChromeIconPath(name), h, w, r, g, b
    )
end

local chromeIconButtons = {}
local twistIcons = {}

function TaskTracker.TrackChromeIconButton(btn)
    if not btn then return end
    chromeIconButtons[btn] = true
end

local twistPivot
local function twistPivotPoint()
    if twistPivot ~= nil then return twistPivot end
    if CreateVector2D then
        twistPivot = CreateVector2D(0.5, 0.5)
    else
        twistPivot = false
    end
    return twistPivot
end

--- Closed points right, open points down. The file points left and keeps its padding,
--- so the mark stays a slim chevron. Cropping it into a square stretched it into a V,
--- and that crop stayed on the classic atlas after a switch.
function TaskTracker.ApplyTwistIcon(tex, expanded)
    if not tex then return end
    tex._ttTwistExpanded = expanded and true or false
    twistIcons[tex] = true
    if tex.SetRotation then
        tex:SetRotation(0)
    end
    if tex.SetTexCoord then
        tex:SetTexCoord(0, 1, 0, 1)
    end
    TaskTracker.ApplyChromeIcon(tex, "arrow")
    if not tex.SetRotation then return end
    local angle = tex._ttTwistExpanded and (math.pi / 2) or math.pi
    local pivot = twistPivotPoint()
    if pivot then
        tex:SetRotation(angle, pivot)
    else
        tex:SetRotation(angle)
    end
end

-- Inline path arrow. The atlas faces left; the tex coords are swapped so it points right.
local PATH_ARROW_ATLAS = "CovenantSanctum-Renown-DoubleArrow-Depressed"
local pathArrowBake

local function bakedPathArrow()
    if pathArrowBake then return pathArrowBake end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(PATH_ARROW_ATLAS)
    if not info or not info.file or info.leftTexCoord == nil or info.rightTexCoord == nil then
        return nil
    end
    local dim = 2048
    local function q(v)
        return math.floor((tonumber(v) or 0) * dim + 0.5)
    end
    local aw = tonumber(info.width) or 1
    local ah = tonumber(info.height) or 1
    if ah < 1 then ah = 1 end
    pathArrowBake = {
        file = info.file,
        dim = dim,
        l = q(info.rightTexCoord),
        r = q(info.leftTexCoord),
        t = q(info.topTexCoord),
        b = q(info.bottomTexCoord),
        aspect = aw / ah,
    }
    return pathArrowBake
end

--- Right-pointing double arrow for a line of text.
function TaskTracker.RightChevronMarkup(h)
    h = tonumber(h) or 12
    local bake = bakedPathArrow()
    if not bake then return ">" end
    local w = math.max(8, math.floor(h * bake.aspect + 0.5))
    return string.format(
        "|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t",
        bake.file, h, w, bake.dim, bake.dim, bake.l, bake.r, bake.t, bake.b
    )
end

--- Replace a text arrow (→) with the right-pointing double arrow.
function TaskTracker.WithPathArrows(text, h)
    if type(text) ~= "string" or not text:find("→", 1, true) then return text end
    local arrow = TaskTracker.RightChevronMarkup(h or 12)
    return (text:gsub("→", arrow))
end

--- Down chevron in the bottom right of a menu button, about 50% of the button height.
function TaskTracker.AttachDropdownArrow(btn)
    if not btn then return end
    local tex = btn._ttDropArrow
    if not tex then
        tex = btn:CreateTexture(nil, "OVERLAY")
        btn._ttDropArrow = tex
    end
    if btn._ttDropChevron then
        btn._ttDropChevron:Hide()
    end
    local h = btn:GetHeight() or 22
    if h < 8 then h = 22 end
    local size = math.max(8, math.floor(h * 0.50 + 0.5))
    tex:ClearAllPoints()
    tex:SetSize(size, size)
    tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    tex:Show()
    local label = btn.label
    if label then
        label:ClearAllPoints()
        label:SetPoint("LEFT", btn, "LEFT", 4, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", -(size + 6), 0)
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
    end
    TaskTracker.ApplyTwistIcon(tex, true)
end

function TaskTracker.RefreshChromeIcons()
    for btn in pairs(chromeIconButtons) do
        local name = btn and btn._ttChromeIcon
        if name and btn.icon then
            TaskTracker.ApplyChromeIcon(btn.icon, name)
        else
            chromeIconButtons[btn] = nil
        end
    end
    for tex in pairs(twistIcons) do
        if tex and tex.SetRotation then
            TaskTracker.ApplyTwistIcon(tex, tex._ttTwistExpanded)
        else
            twistIcons[tex] = nil
        end
    end
    if TaskTracker.SyncTitleBarIcons then
        TaskTracker.SyncTitleBarIcons()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
    if TaskTracker.RefreshOpenHelp then
        TaskTracker.RefreshOpenHelp()
    end
end

-- ─────────────────────────────────────
-- Apply theme on login
-- Called from InitDB after DB is ready
-- ─────────────────────────────────────
function TaskTracker.ApplyTheme()
    local key   = (TaskTrackerDB and TaskTrackerDB.theme) or "dark"
    local theme = TaskTracker.Themes[key] or TaskTracker.Themes["dark"]
    if TaskTracker.AttachLayoutMetrics then
        TaskTracker.AttachLayoutMetrics(theme)
    end
    TaskTracker.T = theme
end

--- One pass. Old Gilded becomes Bronzed before old Compact becomes Gilded.
local function remapColorThemeKey(key)
    if key == "gilded" then return "bronzed" end
    if key == "compact" then return "gilded" end
    return key
end

local function migrateColorThemeSettings(settings)
    if type(settings) ~= "table" then return end
    if settings.colorThemeRenameVer == 1 then return end
    if settings.theme ~= nil then
        settings.theme = remapColorThemeKey(settings.theme)
    end
    if type(settings.customThemes) == "table" then
        for _, spec in pairs(settings.customThemes) do
            if type(spec) == "table" and spec.basedOn ~= nil then
                spec.basedOn = remapColorThemeKey(spec.basedOn)
            end
        end
    end
    settings.colorThemeRenameVer = 1
end

function TaskTracker.MigrateColorThemeKeys()
    local db = TaskTrackerDB
    if not db then return end
    migrateColorThemeSettings(db)
    if type(db.profiles) == "table" then
        for _, prof in pairs(db.profiles) do
            if type(prof) == "table" then
                migrateColorThemeSettings(prof.settings)
            end
        end
    end
end

-- Options → Style dropdown order (darks, then lights). Custom themes append at runtime.
TaskTracker.THEME_ORDER = {
    "dark", "nord", "bronzed", "void", "verdant", "gilded", "tome",
    "parchment", "ivory", "paper",
}

local BUILTIN_THEME = {}
for i = 1, #TaskTracker.THEME_ORDER do
    BUILTIN_THEME[TaskTracker.THEME_ORDER[i]] = true
end

TaskTracker.THEME_HERO_KEYS = {
    "bg", "headerBg", "headerBg2", "headerBg3", "headerBgHere", "inputBg", "border",
    "accent", "textAccent", "textPrimary", "icon", "textSecondary",
    "complete", "warning", "danger",
}

local function clamp01(x)
    x = tonumber(x) or 0
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local function copyColor(c)
    if type(c) ~= "table" then
        return { 0, 0, 0, 1 }
    end
    return { clamp01(c[1]), clamp01(c[2]), clamp01(c[3]), clamp01(c[4] or 1) }
end

-- Layout lives on the spacing preset. A copied palette must not keep these.
local THEME_LAYOUT_KEYS = {
    fontNormal = true, fontBold = true, fontDim = true, fontTiny = true,
    headerHeight = true, rowHeight = true, titleHeight = true, padding = true,
    accentBarWidth = true, taskAutomationBarWidth = true, borderWidth = true,
    buttonHeight = true,
}

local function copyThemeTable(src)
    local dst = {}
    if type(src) ~= "table" then return dst end
    for k, v in pairs(src) do
        if not THEME_LAYOUT_KEYS[k] then
            if type(v) == "table" then
                dst[k] = copyColor(v)
            else
                dst[k] = v
            end
        end
    end
    dst.isCustom = nil
    return dst
end

local function lum(c)
    if type(c) ~= "table" then return 0 end
    return 0.2126 * (c[1] or 0) + 0.7152 * (c[2] or 0) + 0.0722 * (c[3] or 0)
end

local function darken(c, f)
    c = copyColor(c)
    f = f or 0.65
    return { clamp01(c[1] * f), clamp01(c[2] * f), clamp01(c[3] * f), c[4] }
end

local function applyCustomDerivatives(th)
    local acc = th.accent
    if type(acc) == "table" then
        local aBg = lum(th.bg) > 0.55 and 0.32 or 0.42
        th.accentDim = darken(acc, 0.65)
        th.accentBg = { acc[1], acc[2], acc[3], aBg }
        th.insertLine = { acc[1], acc[2], acc[3], 0.5 }
        th.insertHover = copyColor(acc)
        th.taskBarAutomated = { acc[1], acc[2], acc[3], 0.92 }
    end
    if type(th.textAccent) == "table" then
        th.textHeader = copyColor(th.textAccent)
    end
    if type(th.textPrimary) == "table" then
        th.textTask = copyColor(th.textPrimary)
        th.textRegistry = copyColor(th.textPrimary)
        th.textWarm = copyColor(th.textPrimary)
    end
    if type(th.icon) ~= "table" then
        local src = (type(th.textAccent) == "table" and th.textAccent) or th.textPrimary
        if type(src) == "table" then
            th.icon = copyColor(src)
        end
    end
    if type(th.textSecondary) == "table" then
        th.textDim = darken(th.textSecondary, 0.55)
    end
    if type(th.warning) == "table" then
        th.override = copyColor(th.warning)
        th.taskBarManual = { th.warning[1], th.warning[2], th.warning[3], 0.92 }
        th.insertLinePickUp = { th.warning[1], th.warning[2], th.warning[3], 0.75 }
        th.insertHoverPickUp = copyColor(th.warning)
    end
    if type(th.bg) == "table" then
        th.panelBg = copyColor(th.bg)
    end
    if type(th.headerBgHere) ~= "table" and type(th.accent) == "table" then
        local base = (type(th.headerBg) == "table") and th.headerBg or th.bg
        if type(base) == "table" then
            local f = 0.40
            th.headerBgHere = {
                clamp01(base[1] * (1 - f) + th.accent[1] * f),
                clamp01(base[2] * (1 - f) + th.accent[2] * f),
                clamp01(base[3] * (1 - f) + th.accent[3] * f),
                1,
            }
        end
    end
end

local function snapshotHeroColors(theme)
    local colors = {}
    local src = theme or {}
    for i = 1, #TaskTracker.THEME_HERO_KEYS do
        local key = TaskTracker.THEME_HERO_KEYS[i]
        local c = src[key]
        if key == "icon" and type(c) ~= "table" then
            c = (type(src.textAccent) == "table" and src.textAccent) or src.textPrimary
        end
        colors[key] = copyColor(c)
    end
    return colors
end

function TaskTracker.IsBuiltinThemeKey(key)
    return key and BUILTIN_THEME[key] and true or false
end

function TaskTracker.IsCustomTheme(key)
    local th = key and TaskTracker.Themes[key]
    return th and th.isCustom and true or false
end

function TaskTracker.GetBuiltinThemeKey(key)
    local seen = {}
    local k = key
    for _ = 1, 8 do
        if not k or seen[k] then break end
        seen[k] = true
        if BUILTIN_THEME[k] then return k end
        local spec = TaskTrackerDB and TaskTrackerDB.customThemes and TaskTrackerDB.customThemes[k]
        k = spec and spec.basedOn
    end
    return "dark"
end

function TaskTracker.GetThemeOrder()
    local order = {}
    for i = 1, #TaskTracker.THEME_ORDER do
        order[#order + 1] = TaskTracker.THEME_ORDER[i]
    end
    local extras = {}
    local bag = TaskTrackerDB and TaskTrackerDB.customThemes
    if type(bag) == "table" then
        for id, spec in pairs(bag) do
            if type(id) == "string" and not BUILTIN_THEME[id] and type(spec) == "table" then
                extras[#extras + 1] = { id = id, name = tostring(spec.name or id) }
            end
        end
        table.sort(extras, function(a, b)
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
        for i = 1, #extras do
            order[#order + 1] = extras[i].id
        end
    end
    return order
end

function TaskTracker.SanitizeThemeName(name)
    name = TaskTracker.Trim(name)
    name = name:gsub("[%c]", "")
    if #name > 40 then
        name = name:sub(1, 40)
    end
    if name == "" then
        name = "Custom"
    end
    return name
end

function TaskTracker.BuildCustomTheme(spec)
    if type(spec) ~= "table" then return nil end
    local basedOn = TaskTracker.GetBuiltinThemeKey(spec.basedOn or spec.key)
    local base = copyThemeTable(TaskTracker.Themes[basedOn] or TaskTracker.Themes["dark"])
    local colors = spec.colors
    if type(colors) == "table" then
        for i = 1, #TaskTracker.THEME_HERO_KEYS do
            local key = TaskTracker.THEME_HERO_KEYS[i]
            if type(colors[key]) == "table" then
                local prevA = (base[key] and base[key][4]) or 1
                local c = copyColor(colors[key])
                if colors[key][4] == nil then
                    c[4] = prevA
                end
                base[key] = c
            end
        end
    end
    applyCustomDerivatives(base)
    base.key = spec.key
    base.name = TaskTracker.SanitizeThemeName(spec.name or "Custom")
    base.basedOn = basedOn
    base.isCustom = true
    if TaskTracker.AttachLayoutMetrics then
        TaskTracker.AttachLayoutMetrics(base)
    end
    return base
end

function TaskTracker.SnapshotThemeHeroColors(theme)
    return snapshotHeroColors(theme)
end

function TaskTracker.LoadCustomThemes()
    if not TaskTrackerDB then return end
    local db = TaskTrackerDB
    if type(db.customThemes) ~= "table" then
        db.customThemes = {}
    end
    if type(db.customThemeSeq) ~= "number" then
        db.customThemeSeq = 0
    end
    local stale = {}
    for k, th in pairs(TaskTracker.Themes) do
        if th and th.isCustom then
            stale[#stale + 1] = k
        end
    end
    for i = 1, #stale do
        TaskTracker.Themes[stale[i]] = nil
    end
    for id, spec in pairs(db.customThemes) do
        if type(id) == "string" and not BUILTIN_THEME[id] and type(spec) == "table" then
            spec.key = id
            spec.basedOn = TaskTracker.GetBuiltinThemeKey(spec.basedOn)
            spec.name = TaskTracker.SanitizeThemeName(spec.name)
            TaskTracker.Themes[id] = TaskTracker.BuildCustomTheme(spec)
        end
    end
    if db.theme and not TaskTracker.Themes[db.theme] then
        db.theme = "dark"
    end
end

function TaskTracker.SaveCustomTheme(spec)
    if not TaskTrackerDB or type(spec) ~= "table" then return nil end
    local db = TaskTrackerDB
    if type(db.customThemes) ~= "table" then
        db.customThemes = {}
    end
    if type(db.customThemeSeq) ~= "number" then
        db.customThemeSeq = 0
    end
    local id = spec.key
    local isNew = type(id) ~= "string" or BUILTIN_THEME[id] or not id:find("^custom_")
    if isNew then
        local n = 0
        for _ in pairs(db.customThemes) do
            n = n + 1
        end
        if n >= 20 then
            return nil, "limit"
        end
        db.customThemeSeq = (tonumber(db.customThemeSeq) or 0) + 1
        id = "custom_" .. tostring(db.customThemeSeq)
    end
    local stored = {
        key = id,
        name = TaskTracker.SanitizeThemeName(spec.name),
        basedOn = TaskTracker.GetBuiltinThemeKey(spec.basedOn),
        colors = {},
    }
    local src = spec.colors or spec
    for i = 1, #TaskTracker.THEME_HERO_KEYS do
        local key = TaskTracker.THEME_HERO_KEYS[i]
        local c = src[key]
        if key == "icon" and type(c) ~= "table" then
            c = (type(src.textAccent) == "table" and src.textAccent) or src.textPrimary
        end
        stored.colors[key] = copyColor(c)
    end
    db.customThemes[id] = stored
    TaskTracker.Themes[id] = TaskTracker.BuildCustomTheme(stored)
    return id
end

function TaskTracker.DeleteCustomTheme(key)
    if not key or BUILTIN_THEME[key] or not TaskTrackerDB then return false end
    local spec = TaskTrackerDB.customThemes and TaskTrackerDB.customThemes[key]
    local fallback = spec and spec.basedOn or "dark"
    if TaskTrackerDB.customThemes then
        TaskTrackerDB.customThemes[key] = nil
    end
    TaskTracker.Themes[key] = nil
    if TaskTrackerDB.theme == key then
        TaskTracker.SetTheme(fallback)
    elseif TaskTracker.RefreshAll then
        TaskTracker.RefreshAll()
    end
    return true
end

function TaskTracker.ParseHexColor(s)
    s = TaskTracker.Trim(s):gsub("^#", "")
    if #s == 3 then
        local r = tonumber(s:sub(1, 1), 16)
        local g = tonumber(s:sub(2, 2), 16)
        local b = tonumber(s:sub(3, 3), 16)
        if not r or not g or not b then return nil end
        return r / 15, g / 15, b / 15
    end
    if #s == 6 then
        local r = tonumber(s:sub(1, 2), 16)
        local g = tonumber(s:sub(3, 4), 16)
        local b = tonumber(s:sub(5, 6), 16)
        if not r or not g or not b then return nil end
        return r / 255, g / 255, b / 255
    end
    return nil
end

function TaskTracker.ColorArrayToHex(c)
    c = copyColor(c)
    return string.format("%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- ─────────────────────────────────────
-- Set active theme and rebuild UI
-- ─────────────────────────────────────
function TaskTracker.SetTheme(key)
    local theme = TaskTracker.Themes[key] or TaskTracker.Themes["dark"]
    key         = theme.key or "dark"
    if TaskTracker.AttachLayoutMetrics then
        TaskTracker.AttachLayoutMetrics(theme)
    end
    TaskTracker.T = theme
    if TaskTrackerDB then
        TaskTrackerDB.theme = key
    end
    if TaskTracker.RefreshAll then
        TaskTracker.RefreshAll()
    end
end

-- ─────────────────────────────────────
-- Get active theme (public accessor)
-- ─────────────────────────────────────
function TaskTracker.GetTheme()
    return T()
end

-- ─────────────────────────────────────
-- Color helpers
-- ─────────────────────────────────────
function TaskTracker.SetColor(texture, key)
    local c = T()[key]
    if c and texture then
        texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1.0)
    end
end

function TaskTracker.SetTextColor(fontString, key)
    local c = T()[key]
    if c and fontString then
        fontString:SetTextColor(c[1], c[2], c[3], c[4] or 1.0)
    end
end

--- Import/export toolbar: minimap mail glyph, scaled to the button (not atlas native size).
function TaskTracker.SetShareMailboxIcon(btn)
    if btn and btn.SetChromeIcon then
        btn:SetChromeIcon("mail")
    end
end

function TaskTracker.ColorToHex(key)
    local c = T()[key]
    if not c then return "ffffff" end
    return string.format("%02x%02x%02x",
        math.floor(c[1] * 255),
        math.floor(c[2] * 255),
        math.floor(c[3] * 255))
end

function TaskTracker.WrapColor(text, key)
    return "|cff"..TaskTracker.ColorToHex(key)..text.."|r"
end

-- ─────────────────────────────────────
-- Spacing presets. Themes are colors. Compact / Comfy / Spacious fill these fields.
-- ─────────────────────────────────────
local listFontStrings = setmetatable({}, { __mode = "k" })
local layoutMigrating = false

local function clampFontPx(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    if n < 8 then n = 8 end
    if n > 24 then n = 24 end
    return n
end

local function fontObjectPixelSize(name, fallback)
    local obj = name and _G[name]
    if obj and obj.GetFont then
        local _, size = obj:GetFont()
        if type(size) == "number" and size > 0 and size < 80 then
            return math.floor(size + 0.5)
        end
    end
    return fallback
end

local function clampInt(v, lo, hi, fallback)
    v = tonumber(v)
    if not v then v = fallback end
    v = math.floor(v + 0.5)
    if v < lo then v = lo end
    if v > hi then v = hi end
    return v
end

-- The four roman fonts shipped with WoW. Font objects such as System, Game, and
-- Highlight all point at Friz, so picking them did not change the face.
local LAYOUT_FONT_ORDER = { "friz", "arial", "morpheus", "skurri" }

local LAYOUT_FONTS = {
    friz     = { file = "Fonts\\FRIZQT__.TTF",  label = "Friz" },
    arial    = { file = "Fonts\\ARIALN.TTF",    label = "Arial" },
    morpheus = { file = "Fonts\\MORPHEUS.TTF",  label = "Morpheus" },
    skurri   = { file = "Fonts\\SKURRI.TTF",    label = "Skurri" },
}

local LAYOUT_FONT_ALIAS = {
    system = "friz",
    game = "friz",
    highlight = "friz",
    objective = "friz",
    friends = "friz",
    quest = "morpheus",
}

local HIST_FACE_KEY = {
    SystemFont_Shadow_Small = "friz",
    GameFontNormalSmall = "friz",
    GameFontHighlightSmall = "friz",
    ObjectiveFont = "friz",
    FriendsFont_Small = "friz",
    QuestFont = "morpheus",
}

-- Compact is the tight list from the Style page. Comfy is 20% larger. Spacious is 20% larger than Comfy.
-- Zero stays zero. Other numbers round to the nearest pixel, then clamp to the slider.
local COMPACT_LAYOUT = {
    indentSize = 4,
    scrollGutter = 3,
    listPadLeft = 0,
    listPadRight = 8,
    listPadTop = 0,
    listPadBottom = 0,
    spacingGroupHeader = 0,
    spacingGroupSection = 0,
    spacingBetweenTasks = 0,
    cmdIconPercent = 60,
    rowIconPercent = 60,
    checkboxPercent = 70,
    labelToIconGap = 2,
    headerTitleGap = 4,
    titleIconSize = 16,
    checkGap = 4,
    fontShadow = false,
    headerHeight = 16,
    rowHeight = 15,
    titleHeight = 20,
    titleMargin = 6,
    accentBarWidth = 2,
    automationBarWidth = 3,
    borderWidth = 1,
    buttonHeight = 18,
    layoutFont = "friz",
    headerFontSize = 11,
    taskFontSize = 10,
    titleFontSize = 14,
    notePeekBgOpacityPercent = 85,
    notePeekTextOpacityPercent = 100,
    notePeekCmdOpacityPercent = 100,
    notePeekHoverBgOpacityPercent = 85,
    notePeekHoverTextOpacityPercent = 100,
    notePeekHoverCmdOpacityPercent = 100,
}

local LAYOUT_SCALE_LIMITS = {
    indentSize = { 4, 20 },
    scrollGutter = { 0, 12 },
    listPadLeft = { 0, 16 },
    listPadRight = { 0, 12 },
    listPadTop = { 0, 8 },
    listPadBottom = { 0, 8 },
    spacingGroupHeader = { 0, 4 },
    spacingGroupSection = { 0, 8 },
    spacingBetweenTasks = { 0, 8 },
    cmdIconPercent = { 60, 100 },
    rowIconPercent = { 60, 100 },
    checkboxPercent = { 50, 120 },
    labelToIconGap = { 0, 12 },
    headerTitleGap = { 0, 12 },
    titleIconSize = { 12, 28 },
    checkGap = { 0, 8 },
    headerHeight = { 16, 40 },
    rowHeight = { 14, 36 },
    titleHeight = { 20, 40 },
    titleMargin = { 0, 16 },
    accentBarWidth = { 1, 6 },
    automationBarWidth = { 1, 6 },
    borderWidth = { 1, 3 },
    buttonHeight = { 16, 28 },
    headerFontSize = { 8, 24 },
    taskFontSize = { 8, 24 },
    titleFontSize = { 8, 24 },
}

local function scaledLayout(mul)
    local out = {}
    for k, v in pairs(COMPACT_LAYOUT) do
        local lim = LAYOUT_SCALE_LIMITS[k]
        if lim and type(v) == "number" and v > 0 then
            local n = math.floor(v * mul + 0.5)
            if n < lim[1] then n = lim[1] end
            if n > lim[2] then n = lim[2] end
            out[k] = n
        else
            out[k] = v
        end
    end
    return out
end

local LAYOUT_SHARED = COMPACT_LAYOUT

local LAYOUT_PRESETS = {
    compact = COMPACT_LAYOUT,
    comfy = scaledLayout(1.2),
    spacious = scaledLayout(1.44),
}
-- 20pt title text and the scaled icons overflow the spacious bar. 18 fits.
LAYOUT_PRESETS.spacious.titleFontSize = 18
LAYOUT_PRESETS.spacious.titleIconSize = 18

local LAYOUT_FIELDS = {
    "indentSize", "scrollGutter", "listPadLeft", "listPadRight", "listPadTop", "listPadBottom",
    "spacingGroupHeader", "spacingGroupSection", "spacingBetweenTasks",
    "cmdIconPercent", "rowIconPercent", "checkboxPercent", "labelToIconGap", "headerTitleGap",
    "titleIconSize", "checkGap",
    "headerHeight", "rowHeight", "titleHeight", "titleMargin",
    "accentBarWidth", "automationBarWidth", "borderWidth", "buttonHeight",
    "layoutFont", "fontShadow", "headerFontSize", "taskFontSize", "titleFontSize",
    "notePeekBgOpacityPercent", "notePeekTextOpacityPercent", "notePeekCmdOpacityPercent",
    "notePeekHoverBgOpacityPercent", "notePeekHoverTextOpacityPercent", "notePeekHoverCmdOpacityPercent",
}

local function histRow(headerHeight, rowHeight, titleHeight, padding, accent, auto, border, button, normal, bold)
    return {
        headerHeight = headerHeight, rowHeight = rowHeight, titleHeight = titleHeight,
        padding = padding, accentBarWidth = accent, taskAutomationBarWidth = auto,
        borderWidth = border, buttonHeight = button,
        fontNormal = normal, fontBold = bold,
    }
end

local HIST_GAME = histRow(26, 22, 28, 8, 3, 3, 1, 20, "GameFontNormalSmall", "GameFontNormal")
local HISTORICAL_LAYOUT = {
    dark      = HIST_GAME,
    nord      = HIST_GAME,
    bronzed   = HIST_GAME,
    gilded    = histRow(22, 18, 24, 5, 2, 2, 1, 18, "SystemFont_Shadow_Small", "SystemFont_Shadow_Med1"),
    ivory     = HIST_GAME,
    parchment = HIST_GAME,
    verdant   = histRow(27, 23, 30, 9, 3, 3, 2, 21, "ObjectiveFont", "GameFontNormal"),
    void      = histRow(25, 21, 28, 7, 5, 4, 1, 20, "FriendsFont_Small", "FriendsFont_Normal"),
    tome      = histRow(30, 26, 32, 11, 4, 4, 2, 22, "QuestFont", "GameFontNormal"),
    paper     = histRow(30, 26, 32, 12, 4, 4, 2, 22, "GameFontHighlightSmall", "GameFontNormal"),
}

local function fontKeyFromFaces(normal)
    return HIST_FACE_KEY[normal] or "friz"
end

local function resolvedPreset(key)
    local src = LAYOUT_PRESETS[key]
    if not src then return nil end
    local out = {}
    for k, v in pairs(LAYOUT_SHARED) do
        out[k] = v
    end
    for k, v in pairs(src) do
        out[k] = v
    end
    if out.headerFontSize == nil then
        out.headerFontSize = clampFontPx(fontObjectPixelSize(out.sizeBold or "GameFontNormal", 14))
    end
    if out.taskFontSize == nil then
        out.taskFontSize = clampFontPx(fontObjectPixelSize(out.sizeNormal or "GameFontNormalSmall", 12))
    end
    if out.titleFontSize == nil then
        out.titleFontSize = clampFontPx(fontObjectPixelSize(out.sizeBold or "GameFontNormal", 14))
    end
    return out
end

local function sameLayout(a, b)
    for i = 1, #LAYOUT_FIELDS do
        local k = LAYOUT_FIELDS[i]
        if a[k] ~= b[k] then
            return false
        end
    end
    return true
end

local function historicalFor(themeKey)
    local th = themeKey and TaskTracker.Themes[themeKey]
    local base = themeKey
    if th and th.isCustom then
        base = th.basedOn or "dark"
    end
    return HISTORICAL_LAYOUT[base] or HISTORICAL_LAYOUT.dark
end

function TaskTracker.GetLayoutFontKey()
    local raw = TaskTrackerDB and TaskTrackerDB.layoutFont
    local key = LAYOUT_FONTS[raw] and raw or LAYOUT_FONT_ALIAS[raw] or "friz"
    if TaskTrackerDB and raw ~= key then
        TaskTrackerDB.layoutFont = key
    end
    return key
end

--- Font object for Friz. Options uses these and never reloads the file.
--- Reloading Fonts\FRIZQT__.TTF with SetFont leans the M.
function TaskTracker.GetLayoutFont(which)
    if which == "bold" then
        return "GameFontNormal"
    end
    return "GameFontNormalSmall"
end

function TaskTracker.GetLayoutFontChoices()
    local items = {}
    for i = 1, #LAYOUT_FONT_ORDER do
        local key = LAYOUT_FONT_ORDER[i]
        items[i] = { key = key, label = LAYOUT_FONTS[key].label }
    end
    return items
end

function TaskTracker.GetLayoutPreset()
    local p = TaskTrackerDB and TaskTrackerDB.layoutPreset
    if p == "compact" or p == "comfy" or p == "spacious" or p == "custom" then
        return p
    end
    return "custom"
end

function TaskTracker.ThemeFontPixelSize(which)
    if which == "header" then
        return fontObjectPixelSize(TaskTracker.GetLayoutFont("bold"), 14)
    end
    return fontObjectPixelSize(TaskTracker.GetLayoutFont("normal"), 12)
end

function TaskTracker.GetHeaderHeight()
    return clampInt(TaskTrackerDB and TaskTrackerDB.headerHeight, 16, 40, 16)
end

function TaskTracker.GetTaskRowHeight()
    return clampInt(TaskTrackerDB and TaskTrackerDB.rowHeight, 14, 36, 15)
end

function TaskTracker.GetTitleBarHeight()
    return clampInt(TaskTrackerDB and TaskTrackerDB.titleHeight, 20, 40, 20)
end

function TaskTracker.GetTitleMargin()
    return clampInt(TaskTrackerDB and TaskTrackerDB.titleMargin, 0, 16, 6)
end

function TaskTracker.GetAccentBarWidth()
    return clampInt(TaskTrackerDB and TaskTrackerDB.accentBarWidth, 1, 6, 2)
end

function TaskTracker.GetAutomationBarWidth()
    return clampInt(TaskTrackerDB and TaskTrackerDB.automationBarWidth, 1, 6, 3)
end

function TaskTracker.GetBorderWidth()
    return clampInt(TaskTrackerDB and TaskTrackerDB.borderWidth, 1, 3, 1)
end

function TaskTracker.GetButtonHeight()
    return clampInt(TaskTrackerDB and TaskTrackerDB.buttonHeight, 16, 28, 18)
end

function TaskTracker.GetOptionsFontSize()
    return clampFontPx(TaskTrackerDB and TaskTrackerDB.optionsFontSize or 10)
end

function TaskTracker.GetOptionsRowHeight()
    return clampInt(TaskTrackerDB and TaskTrackerDB.optionsRowHeight, 20, 40, 28)
end

function TaskTracker.GetOptionsBorderWidth()
    return clampInt(TaskTrackerDB and TaskTrackerDB.optionsBorderWidth, 1, 3, 1)
end

function TaskTracker.GetOptionsTitleFontSize()
    return clampFontPx(TaskTrackerDB and TaskTrackerDB.optionsTitleFontSize or 14)
end

function TaskTracker.GetOptionsTitleIconSize()
    return clampInt(TaskTrackerDB and TaskTrackerDB.optionsTitleIconSize, 12, 28, 16)
end

function TaskTracker.GetOptionsTitleHeight()
    return clampInt(TaskTrackerDB and TaskTrackerDB.optionsTitleHeight, 20, 40, 20)
end

function TaskTracker.GetOptionsTitleMargin()
    return clampInt(TaskTrackerDB and TaskTrackerDB.optionsTitleMargin, 0, 16, 6)
end

--- Section title is 2px above the body font, so the heading stays a step larger.
function TaskTracker.OptionsSectionLead()
    local px = TaskTracker.GetOptionsFontSize() + 2
    if px > 24 then px = 24 end
    local titleH = math.max(16, px + 4)
    return titleH, titleH + 8
end

--- Options text stays on the game font object. The list font file is separate.
function TaskTracker.ApplyOptionsFont(fs, face, px)
    if not fs or not fs.SetFontObject then return end
    face = (face == "title") and "title" or "body"
    local locked = px ~= nil
    if not px then
        px = TaskTracker.GetOptionsFontSize()
        if face == "title" then
            px = px + 2
            if px > 24 then px = 24 end
        end
    end
    px = clampFontPx(px)
    fs._ttOptionsFace = face
    if locked then
        fs._ttOptionsLockedPx = px
    end
    fs:SetFontObject((face == "title") and "GameFontNormal" or "GameFontNormalSmall")
    TaskTracker.ClearFontShadow(fs)
    if fs.SetFontHeight then
        fs:SetFontHeight(px)
        TaskTracker.ClearFontShadow(fs)
    end
end

local OPTIONS_STYLE_KEYS = {
    "optionsFontSize", "optionsRowHeight", "optionsBorderWidth",
    "optionsTitleFontSize", "optionsTitleIconSize", "optionsTitleHeight", "optionsTitleMargin",
    "optionsPanelStyleMigrated",
}

--- First open copies the border and title bar the options window already used.
--- After that, those sliders no longer follow the task list.
function TaskTracker.MigrateOptionsPanelStyle()
    local db = TaskTrackerDB
    if not db or db.optionsPanelStyleMigrated then return end
    db.optionsFontSize = clampFontPx(fontObjectPixelSize("GameFontNormalSmall", 10))
    db.optionsRowHeight = 28
    db.optionsBorderWidth = clampInt(db.borderWidth, 1, 3, 1)
    db.optionsTitleFontSize = clampFontPx(tonumber(db.titleFontSize) or 14)
    db.optionsTitleIconSize = clampInt(db.titleIconSize, 12, 28, 16)
    db.optionsTitleHeight = clampInt(db.titleHeight, 20, 40, 20)
    db.optionsTitleMargin = clampInt(db.titleMargin, 0, 16, 6)
    db.optionsPanelStyleMigrated = true
    local name = db.loadedProfile
    local prof = name and db.profiles and db.profiles[name]
    local settings = prof and prof.settings
    if type(settings) == "table" then
        for i = 1, #OPTIONS_STYLE_KEYS do
            local k = OPTIONS_STYLE_KEYS[i]
            settings[k] = db[k]
        end
    end
end

function TaskTracker.GetCheckGap()
    return clampInt(TaskTrackerDB and TaskTrackerDB.checkGap, 0, 8, 4)
end

function TaskTracker.GetHeaderFontSize()
    local n = TaskTrackerDB and tonumber(TaskTrackerDB.headerFontSize)
    if not n then return TaskTracker.ThemeFontPixelSize("header") end
    return clampFontPx(n)
end

function TaskTracker.GetTaskFontSize()
    local n = TaskTrackerDB and tonumber(TaskTrackerDB.taskFontSize)
    if not n then return TaskTracker.ThemeFontPixelSize("task") end
    return clampFontPx(n)
end

function TaskTracker.GetTitleFontSize()
    local n = TaskTrackerDB and tonumber(TaskTrackerDB.titleFontSize)
    if not n then return TaskTracker.ThemeFontPixelSize("header") end
    return clampFontPx(n)
end

function TaskTracker.GetTitleIconSize()
    return clampInt(TaskTrackerDB and TaskTrackerDB.titleIconSize, 12, 28, 20)
end

--- First load with no preset: keep the pixels this character already has.
--- Exact Compact or Comfy (including the old theme metrics) selects that preset.
--- Anything else, including Tome, Paper, Void, and Verdant, stays Custom.
function TaskTracker.MigrateLayoutPreset()
    local db = TaskTrackerDB
    if not db or layoutMigrating then return end
    local preset = db.layoutPreset
    if preset == "compact" or preset == "comfy" or preset == "spacious" or preset == "custom" then
        return
    end
    layoutMigrating = true

    local hist = historicalFor(db.theme)
    local fontKey = fontKeyFromFaces(hist.fontNormal, hist.fontBold)
    local headerNative = fontObjectPixelSize(hist.fontBold, 14)
    local taskNative = fontObjectPixelSize(hist.fontNormal, 12)
    local mult = 1
    if not db.listFontPxMigrated then
        local p = tonumber(db.fontPercent) or 100
        if p ~= 100 then mult = p / 100 end
    end
    local headerPx = tonumber(db.headerFontSize)
    if headerPx then
        headerPx = clampFontPx(headerPx)
    else
        headerPx = clampFontPx(headerNative * mult)
    end
    local taskPx = tonumber(db.taskFontSize)
    if taskPx then
        taskPx = clampFontPx(taskPx)
    else
        taskPx = clampFontPx(taskNative * mult)
    end
    local titlePx = tonumber(db.titleFontSize)
    if titlePx then
        titlePx = clampFontPx(titlePx)
    else
        titlePx = clampFontPx(headerNative)
    end

    local extraH = clampInt(db.extraHeaderHeight, -10, 10, 0)
    local extraR = clampInt(db.extraTaskHeight, -10, 10, 0)
    local snap = {
        indentSize = clampInt(db.indentSize, 4, 20, LAYOUT_SHARED.indentSize),
        scrollGutter = clampInt(db.scrollGutter, 0, 12, LAYOUT_SHARED.scrollGutter),
        listPadLeft = clampInt(db.listPadLeft, 0, 16, LAYOUT_SHARED.listPadLeft),
        listPadRight = clampInt(db.listPadRight, 0, 12, LAYOUT_SHARED.listPadRight),
        listPadTop = clampInt(db.listPadTop, 0, 8, LAYOUT_SHARED.listPadTop),
        listPadBottom = clampInt(db.listPadBottom, 0, 8, LAYOUT_SHARED.listPadBottom),
        spacingGroupHeader = clampInt(db.spacingGroupHeader, 0, 4, LAYOUT_SHARED.spacingGroupHeader),
        spacingGroupSection = clampInt(db.spacingGroupSection, 0, 8, LAYOUT_SHARED.spacingGroupSection),
        spacingBetweenTasks = clampInt(db.spacingBetweenTasks, 0, 8, LAYOUT_SHARED.spacingBetweenTasks),
        cmdIconPercent = clampInt(db.cmdIconPercent, 60, 100, LAYOUT_SHARED.cmdIconPercent),
        rowIconPercent = clampInt(db.rowIconPercent, 60, 100, LAYOUT_SHARED.rowIconPercent),
        checkboxPercent = clampInt(db.checkboxPercent, 50, 120, LAYOUT_SHARED.checkboxPercent),
        labelToIconGap = clampInt(db.labelToIconGap, 0, 12, LAYOUT_SHARED.labelToIconGap),
        headerTitleGap = clampInt(db.headerTitleGap, 0, 12, LAYOUT_SHARED.headerTitleGap),
        titleIconSize = clampInt(db.titleIconSize, 12, 28, LAYOUT_SHARED.titleIconSize),
        checkGap = clampInt(db.checkGap, 0, 8, LAYOUT_SHARED.checkGap),
        headerHeight = clampInt(math.floor(hist.headerHeight + 0.5) + extraH, 16, 40, 26),
        rowHeight = clampInt(math.floor(hist.rowHeight + 0.5) + extraR, 14, 36, 22),
        titleHeight = clampInt(hist.titleHeight, 20, 40, 28),
        titleMargin = clampInt(hist.padding, 0, 16, 8),
        accentBarWidth = clampInt(hist.accentBarWidth, 1, 6, 3),
        automationBarWidth = clampInt(hist.taskAutomationBarWidth, 1, 6, 3),
        borderWidth = clampInt(hist.borderWidth, 1, 3, 1),
        buttonHeight = clampInt(hist.buttonHeight, 16, 28, 20),
        layoutFont = fontKey or "friz",
        fontShadow = db.fontShadow == true,
        headerFontSize = headerPx,
        taskFontSize = taskPx,
        titleFontSize = titlePx,
        notePeekBgOpacityPercent = clampInt(db.notePeekBgOpacityPercent, 0, 100, 85),
        notePeekTextOpacityPercent = clampInt(db.notePeekTextOpacityPercent, 0, 100, 100),
        notePeekCmdOpacityPercent = clampInt(db.notePeekCmdOpacityPercent, 0, 100, 100),
        notePeekHoverBgOpacityPercent = clampInt(db.notePeekHoverBgOpacityPercent, 0, 100,
            clampInt(db.notePeekBgOpacityPercent, 0, 100, 85)),
        notePeekHoverTextOpacityPercent = clampInt(db.notePeekHoverTextOpacityPercent, 0, 100,
            clampInt(db.notePeekTextOpacityPercent, 0, 100, 100)),
        notePeekHoverCmdOpacityPercent = clampInt(db.notePeekHoverCmdOpacityPercent, 0, 100,
            clampInt(db.notePeekCmdOpacityPercent, 0, 100, 100)),
    }

    local picked = "custom"
    if fontKey and sameLayout(snap, resolvedPreset("compact")) then
        picked = "compact"
    elseif fontKey and sameLayout(snap, resolvedPreset("comfy")) then
        picked = "comfy"
    end

    for i = 1, #LAYOUT_FIELDS do
        local k = LAYOUT_FIELDS[i]
        db[k] = snap[k]
    end
    db.extraHeaderHeight = 0
    db.extraTaskHeight = 0
    db.listFontPxMigrated = true
    db.layoutPreset = picked
    if picked == "custom" then
        local saved = {}
        for i = 1, #LAYOUT_FIELDS do
            local field = LAYOUT_FIELDS[i]
            saved[field] = snap[field]
        end
        db.layoutCustom = saved
    end
    layoutMigrating = false
end

local function writeLayoutFields(db, spec)
    for i = 1, #LAYOUT_FIELDS do
        local field = LAYOUT_FIELDS[i]
        if spec[field] ~= nil then
            db[field] = spec[field]
        end
    end
end

function TaskTracker.SaveLayoutCustom()
    local db = TaskTrackerDB
    if not db then return end
    -- A Mouse Over slider left unset follows Normal. Store that number so
    -- switching away and back does not keep the other style's Mouse Over.
    local function fillPeek(hoverKey, awayKey, fallback)
        if db[hoverKey] == nil then
            local n = tonumber(db[awayKey])
            db[hoverKey] = n or fallback
        end
    end
    fillPeek("notePeekHoverBgOpacityPercent", "notePeekBgOpacityPercent", 85)
    fillPeek("notePeekHoverTextOpacityPercent", "notePeekTextOpacityPercent", 100)
    fillPeek("notePeekHoverCmdOpacityPercent", "notePeekCmdOpacityPercent", 100)
    local saved = {}
    for i = 1, #LAYOUT_FIELDS do
        local field = LAYOUT_FIELDS[i]
        saved[field] = db[field]
    end
    db.layoutCustom = saved
end

function TaskTracker.ApplyLayoutPreset(key, silent)
    local db = TaskTrackerDB
    if not db then return end
    if key == "custom" then
        if type(db.layoutCustom) == "table" then
            writeLayoutFields(db, db.layoutCustom)
        else
            TaskTracker.SaveLayoutCustom()
        end
        db.layoutPreset = "custom"
    else
        local spec = resolvedPreset(key)
        if not spec then return end
        if db.layoutPreset == "custom" then
            TaskTracker.SaveLayoutCustom()
        end
        writeLayoutFields(db, spec)
        db.extraHeaderHeight = 0
        db.extraTaskHeight = 0
        db.listFontPxMigrated = true
        db.layoutPreset = key
    end
    if TaskTracker.ApplyNotePeekOpacity then
        TaskTracker.ApplyNotePeekOpacity()
    end
    if not silent and TaskTracker.RefreshAll then
        TaskTracker.RefreshAll()
    end
end

--- Named presets pick up a new Compact / Comfy / Spacious definition once. Custom is left alone.
function TaskTracker.ApplyStoredLayoutPreset()
    local db = TaskTrackerDB
    if not db or db.layoutPresetDefRev == 4 then return end
    local p = db.layoutPreset
    if p == "compact" or p == "comfy" or p == "spacious" then
        TaskTracker.ApplyLayoutPreset(p, true)
    end
    db.layoutPresetDefRev = 4
end

--- Replace Custom with a named preset. Compact, Comfy, and Spacious stay as they are.
function TaskTracker.CopyLayoutFromPreset(key)
    local spec = resolvedPreset(key)
    local db = TaskTrackerDB
    if not spec or not db then return end
    writeLayoutFields(db, spec)
    db.extraHeaderHeight = 0
    db.extraTaskHeight = 0
    db.listFontPxMigrated = true
    db.layoutPreset = "custom"
    TaskTracker.SaveLayoutCustom()
    if TaskTracker.ApplyNotePeekOpacity then
        TaskTracker.ApplyNotePeekOpacity()
    end
    if TaskTracker.RefreshAll then
        TaskTracker.RefreshAll()
    end
end

local function layoutIndex(_, k)
    if k == "fontNormal" or k == "fontTiny" then
        return TaskTracker.GetLayoutFont("normal")
    elseif k == "fontBold" then
        return TaskTracker.GetLayoutFont("bold")
    elseif k == "fontDim" then
        return "GameFontDisable"
    elseif k == "headerHeight" then
        return TaskTracker.GetHeaderHeight()
    elseif k == "rowHeight" then
        return TaskTracker.GetTaskRowHeight()
    elseif k == "titleHeight" then
        return TaskTracker.GetTitleBarHeight()
    elseif k == "padding" then
        return TaskTracker.GetTitleMargin()
    elseif k == "accentBarWidth" then
        return TaskTracker.GetAccentBarWidth()
    elseif k == "taskAutomationBarWidth" then
        return TaskTracker.GetAutomationBarWidth()
    elseif k == "borderWidth" then
        return TaskTracker.GetBorderWidth()
    elseif k == "buttonHeight" then
        return TaskTracker.GetButtonHeight()
    end
end

local LAYOUT_META = { __index = layoutIndex }

function TaskTracker.AttachLayoutMetrics(theme)
    if type(theme) ~= "table" then return end
    for k in pairs(THEME_LAYOUT_KEYS) do
        theme[k] = nil
    end
    if getmetatable(theme) == nil then
        setmetatable(theme, LAYOUT_META)
    end
end

for _, theme in pairs(TaskTracker.Themes) do
    TaskTracker.AttachLayoutMetrics(theme)
end

function TaskTracker.GetLayoutFontShadow()
    return TaskTrackerDB and TaskTrackerDB.fontShadow == true
end

local function slugFlags(flags)
    if type(flags) ~= "string" or flags == "" then
        return "SLUG"
    end
    if not flags:find("SLUG", 1, true) then
        return flags .. ", SLUG"
    end
    return flags
end

--- One of the four WoW font files. Friz with the shadow off does not use this.
--- Drop shadow copies the game font's outline. SLUG is the same renderer Options uses.
function TaskTracker.GetLayoutFontFile()
    local font = LAYOUT_FONTS[TaskTracker.GetLayoutFontKey()] or LAYOUT_FONTS.friz
    if not TaskTracker.GetLayoutFontShadow() then
        return font.file, slugFlags("")
    end
    local flags = ""
    local obj = _G["GameFontNormalSmall"]
    if obj and obj.GetFont then
        local _, _, f = obj:GetFont()
        if type(f) == "string" and f ~= "" then flags = f end
    end
    return font.file, slugFlags(flags)
end

local function fontHeightPx(fontString)
    if not fontString or not fontString.GetFont then return nil end
    local _, h = fontString:GetFont()
    if type(h) ~= "number" or h <= 0 then return nil end
    return math.floor(h + 0.5)
end

--- Friz stays on the game font object, same draw as Options. Other faces load their file.
function TaskTracker.ApplyLayoutFont(fontString, px, faceKind)
    if not fontString or not px then return end
    faceKind = (faceKind == "bold") and "bold" or "normal"
    px = clampFontPx(px)
    if TaskTracker.GetLayoutFontKey() == "friz" and not TaskTracker.GetLayoutFontShadow() then
        fontString:SetFontObject(TaskTracker.GetLayoutFont(faceKind))
        TaskTracker.ClearFontShadow(fontString)
        if fontHeightPx(fontString) ~= px and fontString.SetFontHeight then
            fontString:SetFontHeight(px)
            TaskTracker.ClearFontShadow(fontString)
        end
        if fontHeightPx(fontString) == px then
            return
        end
    end
    local file, flags
    if faceKind == "bold" or faceKind == "normal" then
        file, flags = TaskTracker.GetLayoutFontFile()
    end
    if not file and fontString.GetFont then
        file, _, flags = fontString:GetFont()
        flags = slugFlags(flags)
    end
    if file then
        fontString:SetFont(file, px, flags or "SLUG")
        TaskTracker.ClearFontShadow(fontString)
    end
end

function TaskTracker.ApplyExplicitFontSize(fontString, role)
    if not fontString then return end
    role = (role == "header") and "header" or (fontString._ttFontRole == "header" and "header" or "task")
    fontString._ttFontRole = role
    listFontStrings[fontString] = role
    local px = (role == "header") and TaskTracker.GetHeaderFontSize() or TaskTracker.GetTaskFontSize()
    TaskTracker.ApplyLayoutFont(fontString, px, fontString._ttLayoutFace)
end

function TaskTracker.RefreshListFontSizes()
    for fs, role in pairs(listFontStrings) do
        if fs and fs.GetFont then
            TaskTracker.ApplyExplicitFontSize(fs, role)
        end
    end
end

--- FontString from a FontObject name, then the header or task pixel size.
function TaskTracker.CreateScaledListFontString(parent, layer, fontObject, role)
    local fs = TaskTracker.CreateFontString(parent, nil, layer or "OVERLAY")
    fs:SetFontObject(fontObject)
    local bold = TaskTracker.GetLayoutFont("bold")
    fs._ttLayoutFace = (fontObject == bold) and "bold" or "normal"
    TaskTracker.ClearFontShadow(fs)
    TaskTracker.ApplyExplicitFontSize(fs, role)
    return fs
end

-- ─────────────────────────────────────
-- Whole-UI scale (main panel, options, dialogs)
-- ─────────────────────────────────────
function TaskTracker.GetUIScalePercent()
    local p = (TaskTrackerDB and TaskTrackerDB.uiScalePercent) or 100
    if p < 60 then p = 60 end
    if p > 140 then p = 140 end
    return p
end

function TaskTracker.ApplyUIScale()
    local s = TaskTracker.GetUIScalePercent() / 100
    local panel = TaskTracker.panel
    -- Snapshot the on-screen top-left before SetScale. Scale grows from the
    -- bottom-left, and clamp then pins a frame that crossed the top edge.
    local screenLeft, screenTop
    if panel and panel:IsShown() and panel.GetLeft and panel:GetLeft() and panel:GetTop() then
        local es = panel:GetEffectiveScale() or 1
        if es <= 0 then es = 1 end
        screenLeft = panel:GetLeft() * es
        screenTop = panel:GetTop() * es
        if panel.SetClampedToScreen then
            panel:SetClampedToScreen(false)
        end
    end
    if panel then
        panel:SetScale(s)
    end
    if TaskTracker.helpPopup then
        TaskTracker.helpPopup:SetScale(s)
    end
    if TaskTracker.optionsPanel then
        TaskTracker.optionsPanel:SetScale(s)
    end
    if TaskTracker.taskDialog then
        TaskTracker.taskDialog:SetScale(s)
    end
    if TaskTracker.groupDialog then
        TaskTracker.groupDialog:SetScale(s)
    end
    if TaskTracker.noteWindow then
        TaskTracker.noteWindow:SetScale(s)
    end
    if TaskTracker.notePeekWindows then
        for i = 1, #TaskTracker.notePeekWindows do
            local pk = TaskTracker.notePeekWindows[i]
            if pk then pk:SetScale(s) end
        end
    elseif TaskTracker.notePeekWindow then
        TaskTracker.notePeekWindow:SetScale(s)
    end
    if TaskTracker.quickCommandsFrame then
        TaskTracker.quickCommandsFrame:SetScale(s)
    end
    if TaskTracker.debugPanel then
        TaskTracker.debugPanel:SetScale(s)
    end
    if TaskTracker.themeEditor then
        TaskTracker.themeEditor:SetScale(s)
    end
    if TaskTracker._shareImportExportDialog then
        TaskTracker._shareImportExportDialog:SetScale(s)
    end
    if screenLeft and panel and TaskTracker.PinPanelScreenTopLeft then
        TaskTracker.PinPanelScreenTopLeft(panel, screenLeft, screenTop)
        if TaskTracker.NudgePanelOnScreen then
            TaskTracker.NudgePanelOnScreen(panel)
        end
        if TaskTracker.SavePanelPosition then
            TaskTracker.SavePanelPosition(panel)
        end
        if TaskTracker._ttPosRestoreTimer then
            TaskTracker._ttPosRestoreTimer:Cancel()
            TaskTracker._ttPosRestoreTimer = nil
        end
    elseif panel and TaskTracker.ScheduleRestorePanelPosition then
        TaskTracker.ScheduleRestorePanelPosition()
    elseif panel and TaskTracker.RestorePanelPosition then
        TaskTracker.RestorePanelPosition(panel)
    end
end

-- ─────────────────────────────────────
-- Count text
-- ─────────────────────────────────────
function TaskTracker.CountText(done, total)
    if total == 0 then
        return TaskTracker.WrapColor("0/0", "textSecondary")
    elseif done >= total then
        return TaskTracker.WrapColor(done.."/"..total, "complete")
    else
        return TaskTracker.WrapColor(done, "textPrimary")
            .. TaskTracker.WrapColor("/"..total, "textSecondary")
    end
end

-- ─────────────────────────────────────
-- Texture helpers
-- ─────────────────────────────────────
function TaskTracker.MakeEdge(frame, edge, key, thickness)
    local t = T()
    if not thickness and frame and frame._ttOptionsChrome then
        thickness = TaskTracker.GetOptionsBorderWidth()
    end
    if not thickness and frame and TaskTracker.FrameInOptionsChrome(frame) then
        thickness = TaskTracker.GetOptionsBorderWidth()
    end
    thickness = thickness or t.borderWidth or 1
    local tex = frame:CreateTexture(nil, "BORDER")
    TaskTracker.SetColor(tex, key or "border")

    if edge == "LEFT" then
        tex:SetSize(thickness, 0)
        tex:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0, 0)
        tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    elseif edge == "RIGHT" then
        tex:SetSize(thickness, 0)
        tex:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0, 0)
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    elseif edge == "TOP" then
        tex:SetSize(0, thickness)
        tex:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
        tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    elseif edge == "BOTTOM" then
        tex:SetSize(0, thickness)
        tex:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    end

    return tex
end

function TaskTracker.MakeBorder(frame, key)
    TaskTracker.MakeEdge(frame, "LEFT",   key)
    TaskTracker.MakeEdge(frame, "RIGHT",  key)
    TaskTracker.MakeEdge(frame, "TOP",    key)
    TaskTracker.MakeEdge(frame, "BOTTOM", key)
end

function TaskTracker.MakeAccentBar(frame, key)
    local t = T()
    local tex = TaskTracker.MakeEdge(frame, "LEFT", key or "accent", t.accentBarWidth or 3)
    if frame then frame._ttAccentBar = tex end
    return tex
end

function TaskTracker.ApplyAccentBarWidth(frame)
    local tex = frame and frame._ttAccentBar
    if not tex or not tex.SetWidth then return end
    local w = TaskTracker.GetAccentBarWidth and TaskTracker.GetAccentBarWidth() or 3
    tex:SetWidth(w)
end

-- ─────────────────────────────────────
-- Row background
-- ─────────────────────────────────────
function TaskTracker.MakeRowBg(row, index)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        TaskTracker.SetColor(bg, "rowEven")
    else
        TaskTracker.SetColor(bg, "rowOdd")
    end
    return bg
end

-- ─────────────────────────────────────
-- Styled flat button
-- ─────────────────────────────────────
function TaskTracker.MakeButton(parent, label, width, height)
    local t   = T()
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 80, height or t.buttonHeight or 20)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    TaskTracker.SetColor(bg, "headerBg")
    btn.bg = bg

    TaskTracker.MakeBorder(btn, "border")

    local text = TaskTracker.CreateFontString(btn, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    text:SetAllPoints()
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    TaskTracker.SetTextColor(text, "textPrimary")
    text:SetText(label or "")
    btn.label = text

    btn:SetScript("OnEnter", function()
        TaskTracker.SetColor(bg, "accentBg")
        TaskTracker.SetTextColor(text, "textAccent")
    end)
    btn:SetScript("OnLeave", function()
        if btn._ttActive then
            TaskTracker.SetColor(bg, "accentBg")
            TaskTracker.SetTextColor(text, "textAccent")
        else
            TaskTracker.SetColor(bg, btn._ttIdleBgKey or "headerBg")
            TaskTracker.SetTextColor(text, btn._ttIdleTextKey or "textPrimary")
        end
    end)

    btn.SetLabel = function(self, newLabel)
        text:SetText(newLabel)
    end

    return btn
end

--- Paint a MakeButton as selected (accent) or idle.
--- opt.idleBgKey / opt.idleTextKey persist on the button for hover leave.
function TaskTracker.SetButtonActive(btn, active, opt)
    if not btn then return end
    opt = opt or {}
    if opt.idleBgKey then
        btn._ttIdleBgKey = opt.idleBgKey
    end
    if opt.idleTextKey then
        btn._ttIdleTextKey = opt.idleTextKey
    end
    btn._ttActive = not not active
    if btn._ttActive then
        if btn.bg then TaskTracker.SetColor(btn.bg, "accentBg") end
        if btn.label then TaskTracker.SetTextColor(btn.label, "textAccent") end
    else
        if btn.bg then TaskTracker.SetColor(btn.bg, btn._ttIdleBgKey or "headerBg") end
        if btn.label then TaskTracker.SetTextColor(btn.label, btn._ttIdleTextKey or "textPrimary") end
    end
end

--- Exclusive selected style. `active` is a button, a map key, or a predicate `function(btn, key)`.
function TaskTracker.SetExclusiveButtonActive(buttons, active, opt)
    if not buttons then return end
    local pred
    local at = type(active)
    if at == "function" then
        pred = active
    elseif at == "userdata" or at == "table" then
        pred = function(btn) return btn == active end
    else
        pred = function(_, key) return key == active end
    end
    for k, btn in pairs(buttons) do
        TaskTracker.SetButtonActive(btn, pred(btn, k), opt)
    end
end

-- ─────────────────────────────────────
-- Options rows: solid colors only (no textures). Selected fill is textPrimary
-- with bg-colored text so light and dark themes both stay readable.
-- ─────────────────────────────────────
local function quietRowH()
    if TaskTracker.GetOptionsRowHeight then
        return TaskTracker.GetOptionsRowHeight()
    end
    return 28
end

local function quietFont()
    local t = T()
    return t.fontNormal or "GameFontNormalSmall"
end

--- Selected chip: header lifted slightly toward the accent. Not the light text color.
function TaskTracker.PaintQuietSelected(tex, label)
    local t = T()
    local base = t.headerBg or { 0.12, 0.12, 0.12, 1 }
    local edge = t.borderLight or t.border or base
    local accent = t.accent or { 0.4, 0.4, 0.4, 1 }
    if tex then
        tex:SetColorTexture(
            base[1] * 0.55 + edge[1] * 0.25 + accent[1] * 0.20,
            base[2] * 0.55 + edge[2] * 0.25 + accent[2] * 0.20,
            base[3] * 0.55 + edge[3] * 0.25 + accent[3] * 0.20,
            1
        )
    end
    if label then
        TaskTracker.SetTextColor(label, "textPrimary")
    end
end

function TaskTracker.PaintQuietChoice(bg, label, selected)
    if selected then
        TaskTracker.PaintQuietSelected(bg, label)
    else
        if bg then TaskTracker.SetColor(bg, "inputBg") end
        if label then TaskTracker.SetTextColor(label, "textSecondary") end
    end
end

--- Cursor row. Lighter than the menu gray, short of the selected mix.
function TaskTracker.PaintQuietHover(tex, label)
    local t = T()
    local base = t.headerBg2 or t.headerBg or { 0.12, 0.12, 0.12, 1 }
    local edge = t.borderLight or t.border or base
    if tex then
        tex:SetColorTexture(
            base[1] * 0.35 + edge[1] * 0.65,
            base[2] * 0.35 + edge[2] * 0.65,
            base[3] * 0.35 + edge[3] * 0.65,
            1
        )
    end
    if label then
        TaskTracker.SetTextColor(label, "textPrimary")
    end
end

--- Section title plus a 1px rule. Place() returns the y just below the rule.
function TaskTracker.MakeQuietSection(parent)
    local title = TaskTracker.CreateFontString(parent, nil, "OVERLAY", T().fontBold or "GameFontNormal")
    TaskTracker.SetTextColor(title, "textAccent")
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    TaskTracker.SetColor(rule, "border")
    local block = { title = title, rule = rule }
    function block:SetText(text)
        title:SetText(text or "")
    end
    function block:Place(pane, x, y, width)
        local titleH, blockH = 16, 24
        if TaskTracker.OptionsSectionLead then
            titleH, blockH = TaskTracker.OptionsSectionLead()
        end
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -y)
        title:SetHeight(titleH)
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -(y + titleH))
        rule:SetPoint("TOPRIGHT", pane, "TOPLEFT", x + (width or 200), -(y + titleH))
        return y + blockH
    end
    return block
end

--- Label on the left, rectangular track and thumb on the right.
function TaskTracker.MakeQuietToggle(parent, labelText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(quietRowH())

    local track = CreateFrame("Frame", nil, btn)
    track:SetSize(36, 16)
    track:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    TaskTracker.MakeBorder(track, "border")
    btn.track = trackBg

    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(14, 12)
    btn.thumb = thumb

    local lab = TaskTracker.CreateFontString(btn, nil, "OVERLAY", quietFont())
    lab:SetPoint("LEFT", btn, "LEFT", 0, 0)
    lab:SetPoint("RIGHT", track, "LEFT", -8, 0)
    lab:SetJustifyH("LEFT")
    lab:SetJustifyV("MIDDLE")
    lab:SetText(labelText or "")
    TaskTracker.SetTextColor(lab, "textPrimary")
    btn.label = lab

    function btn:SetOn(isOn)
        btn._ttOn = not not isOn
        if btn._ttOn then
            TaskTracker.SetColor(trackBg, "accent")
            TaskTracker.SetColor(thumb, "bg")
            thumb:ClearAllPoints()
            thumb:SetPoint("RIGHT", track, "RIGHT", -2, 0)
        else
            TaskTracker.SetColor(trackBg, "inputBg")
            TaskTracker.SetColor(thumb, "textPrimary")
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", track, "LEFT", 2, 0)
        end
    end
    function btn:GetOn()
        return btn._ttOn and true or false
    end
    function btn:SetLabel(text)
        lab:SetText(text or "")
    end
    btn:SetOn(false)
    return btn
end

--- Equal-width exclusive segments. `items` is `{ { key=, label= }, ... }`.
--- host.buttons[key], host:SetActive(key), host:Layout(width).
function TaskTracker.MakeQuietSegments(parent, items)
    local host = CreateFrame("Frame", nil, parent)
    host:SetHeight(quietRowH())
    local buttons = {}
    local order = {}
    for i, it in ipairs(items or {}) do
        local btn = CreateFrame("Button", nil, host)
        btn:SetHeight(quietRowH())
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        btn.bg = bg
        TaskTracker.MakeBorder(btn, "border")
        local text = TaskTracker.CreateFontString(btn, nil, "OVERLAY", quietFont())
        text:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, 0)
        text:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 0)
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
        text:SetText(it.label or "")
        btn.label = text
        buttons[it.key] = btn
        order[i] = btn
    end
    function host:Layout(width)
        width = math.max(#order * 36, math.floor(width or 200))
        host:SetWidth(width)
        local n = #order
        if n < 1 then return end
        local gap = 2
        local segW = math.floor((width - gap * (n - 1)) / n)
        local x = 0
        for i, btn in ipairs(order) do
            local w = (i == n) and (width - x) or segW
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", host, "TOPLEFT", x, 0)
            btn:SetSize(math.max(8, w), quietRowH())
            x = x + w + gap
        end
    end
    function host:SetActive(activeKey)
        for key, btn in pairs(buttons) do
            TaskTracker.PaintQuietChoice(btn.bg, btn.label, key == activeKey)
        end
    end
    host.buttons = buttons
    host:Layout(240)
    host:SetActive(nil)
    return host
end

--- Label plus a recessed value. Click handler is the caller's.
function TaskTracker.MakeQuietValue(parent, labelText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(quietRowH())

    local well = CreateFrame("Frame", nil, btn)
    well:SetHeight(quietRowH())
    well:SetWidth(120)
    well:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    well:EnableMouse(false)
    local bg = well:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    TaskTracker.SetColor(bg, "inputBg")
    TaskTracker.MakeBorder(well, "border")
    local val = TaskTracker.CreateFontString(well, nil, "OVERLAY", quietFont())
    val:SetPoint("TOPLEFT", well, "TOPLEFT", 6, 0)
    val:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -6, 0)
    val:SetJustifyH("CENTER")
    val:SetJustifyV("MIDDLE")
    TaskTracker.SetTextColor(val, "textPrimary")
    btn.value = val

    local lab = TaskTracker.CreateFontString(btn, nil, "OVERLAY", quietFont())
    lab:SetPoint("LEFT", btn, "LEFT", 0, 0)
    lab:SetPoint("RIGHT", well, "LEFT", -8, 0)
    lab:SetJustifyH("LEFT")
    lab:SetJustifyV("MIDDLE")
    lab:SetText(labelText or "")
    TaskTracker.SetTextColor(lab, "textPrimary")
    btn.label = lab

    function btn:SetValue(text)
        val:SetText(text or "")
    end
    function btn:SetWellWidth(w)
        well:SetWidth(math.max(48, w or 120))
    end
    return btn
end

--- Label, horizontal slider, and a numeric readout. Commits when the drag ends.
--- Returns nextY, row `{ lab, host, sync }`. `host` is the whole row.
function TaskTracker.MakeQuietSlider(parent, spec)
    spec = spec or {}
    local t = T()
    local font = spec.font or t.fontNormal or "GameFontNormalSmall"
    local minV = spec.min or 0
    local maxV = spec.max or 100
    local step = spec.step or 1
    local xLeft = spec.x or 0
    local yRowTop = spec.y or 0
    local rowH = quietRowH()
    local rowStride = spec.rowStride or (rowH + 8)

    local host = CreateFrame("Frame", nil, parent)
    host:SetHeight(rowH)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", xLeft, -yRowTop)

    local lab = TaskTracker.CreateFontString(host, nil, "OVERLAY", font)
    lab:SetPoint("LEFT", host, "LEFT", 0, 0)
    lab:SetJustifyH("LEFT")
    lab:SetJustifyV("MIDDLE")
    if lab.SetWordWrap then lab:SetWordWrap(false) end
    lab:SetText(spec.label or "")
    TaskTracker.SetTextColor(lab, "textPrimary")

    local val = TaskTracker.CreateFontString(host, nil, "OVERLAY", font)
    val:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    val:SetWidth(40)
    val:SetJustifyH("RIGHT")
    val:SetJustifyV("MIDDLE")
    TaskTracker.SetTextColor(val, "textPrimary")

    local track = CreateFrame("Frame", nil, host)
    track:SetHeight(4)
    track:SetPoint("LEFT", lab, "RIGHT", 12, 0)
    track:SetPoint("RIGHT", val, "LEFT", -12, 0)
    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    TaskTracker.SetColor(trackBg, "borderLight")

    local slider = CreateFrame("Slider", nil, host)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("LEFT", track, "LEFT", 0, 0)
    slider:SetPoint("RIGHT", track, "RIGHT", 0, 0)
    slider:SetHeight(16)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    slider:EnableMouse(true)
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(10, 14)
    TaskTracker.SetColor(thumb, "accent")
    slider:SetThumbTexture(thumb)

    local guard = false
    local function bounds()
        if spec.getBounds then
            local lo, hi = spec.getBounds()
            lo = math.floor(tonumber(lo) or minV)
            hi = math.floor(tonumber(hi) or maxV)
            if hi < lo then hi = lo end
            return lo, hi
        end
        return minV, maxV
    end
    local function snap(v)
        local lo, hi = bounds()
        v = tonumber(v) or lo
        local steps = math.floor(((v - lo) / step) + 0.5)
        local n = lo + steps * step
        if n < lo then n = lo end
        if n > hi then n = hi end
        return n
    end
    local function getVal()
        if spec.getVal then return snap(spec.getVal()) end
        return minV
    end
    local function show(n)
        val:SetText(tostring(n))
    end
    local function apply(n)
        if spec.requireDB ~= false and not TaskTrackerDB then return end
        n = snap(n)
        if spec.setVal then spec.setVal(n) end
        show(n)
        if spec.onCommit then spec.onCommit(n) end
    end
    local function sync()
        local lo, hi = bounds()
        guard = true
        slider:SetMinMaxValues(lo, hi)
        local n = getVal()
        slider:SetValue(n)
        guard = false
        show(n)
    end

    slider:SetScript("OnValueChanged", function(_, value)
        if guard then return end
        show(snap(value))
    end)
    slider:SetScript("OnMouseUp", function()
        apply(slider:GetValue())
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta)
        apply(getVal() + step * (delta > 0 and 1 or -1))
        sync()
    end)

    function host:Layout(w)
        w = math.max(180, math.floor(w or 180))
        host:SetWidth(w)
        local labelW = math.min(168, math.max(96, math.floor(w * 0.40)))
        lab:SetWidth(labelW)
    end

    function host:SetMuted(muted)
        host._ttMuted = muted and true or false
        local textKey = muted and "textDim" or "textPrimary"
        TaskTracker.SetTextColor(lab, textKey)
        TaskTracker.SetTextColor(val, textKey)
        TaskTracker.SetColor(trackBg, muted and "border" or "borderLight")
        TaskTracker.SetColor(thumb, muted and "accentDim" or "accent")
        slider:EnableMouse(not muted)
        slider:EnableMouseWheel(not muted)
    end

    host:Layout(spec.width or 320)
    sync()
    return yRowTop + rowStride, {
        lab = lab, host = host, well = host, slider = slider, sync = sync,
    }
end

--- Flat action (Customize, Remove, Set key). Not a selected state.
function TaskTracker.MakeQuietAction(parent, label, width, height)
    local t = T()
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 80, height or quietRowH())
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    TaskTracker.SetColor(bg, "inputBg")
    btn.bg = bg
    TaskTracker.MakeBorder(btn, "border")
    local text = TaskTracker.CreateFontString(btn, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    text:SetAllPoints()
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetText(label or "")
    TaskTracker.SetTextColor(text, "textPrimary")
    btn.label = text
    function btn:SetLabel(newLabel)
        text:SetText(newLabel or "")
    end
    btn:SetScript("OnEnter", function()
        TaskTracker.SetColor(bg, "headerBg2")
    end)
    btn:SetScript("OnLeave", function()
        TaskTracker.SetColor(bg, "inputBg")
        TaskTracker.SetTextColor(text, "textPrimary")
    end)
    return btn
end

--- Left-nav row. Selected is a light fill; idle is text only.
function TaskTracker.MakeQuietNavButton(parent, label, width, height)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 140, height or quietRowH())
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0)
    btn.bg = bg
    local text = TaskTracker.CreateFontString(btn, nil, "OVERLAY", quietFont())
    text:SetPoint("LEFT", btn, "LEFT", 12, 0)
    text:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
    text:SetText(label or "")
    btn.label = text
    function btn:SetSelected(on)
        btn._ttOn = not not on
        if btn._ttOn then
            TaskTracker.PaintQuietSelected(bg, text)
        else
            bg:SetColorTexture(0, 0, 0, 0)
            TaskTracker.SetTextColor(text, "textSecondary")
        end
    end
    btn:SetSelected(false)
    return btn
end

--- Reuse a bordered button as a small switch. `caption` shows a word instead (e.g. Have).
function TaskTracker.PaintQuietSwitch(btn, on, caption)
    if not btn or not btn.bg then return end
    if not btn._ttSwitchThumb then
        local thumb = btn:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(12, 10)
        btn._ttSwitchThumb = thumb
    end
    local thumb = btn._ttSwitchThumb
    if caption and caption ~= "" then
        thumb:Hide()
        if btn.label then
            btn.label:Show()
            btn.label:SetText(caption)
            TaskTracker.PaintQuietChoice(btn.bg, btn.label, false)
        end
        return
    end
    if btn.label then btn.label:Hide() end
    thumb:Show()
    if on then
        TaskTracker.SetColor(btn.bg, "accent")
        TaskTracker.SetColor(thumb, "bg")
        thumb:ClearAllPoints()
        thumb:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    else
        TaskTracker.SetColor(btn.bg, "inputBg")
        TaskTracker.SetColor(thumb, "textPrimary")
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", btn, "LEFT", 2, 0)
    end
end

--- Fill-parent (or existing host) scroll frame + custom scrollbar + optional inner pane.
--- opt.useParent: use `parent` as the host instead of creating a wrapper.
--- opt.name / opt.childName, opt.childWidth (400), opt.childHeight (1)
--- opt.left / opt.top / opt.right / opt.bottom insets
--- opt.pane = false skips the inner pane
--- Returns host, scrollFrame, scrollChild, pane, track
function TaskTracker.MakeScrollPane(parent, opt)
    opt = opt or {}
    local host
    if opt.useParent then
        host = parent
    else
        host = CreateFrame("Frame", nil, parent)
        host:SetAllPoints()
    end
    local l = opt.left or 0
    local top = opt.top or 0
    local r = opt.right or 0
    local bot = opt.bottom or 0
    local scrollFrame = CreateFrame("ScrollFrame", opt.name, host)
    scrollFrame:SetPoint("TOPLEFT", host, "TOPLEFT", l, -top)
    scrollFrame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -r, bot)
    local scrollChild = CreateFrame("Frame", opt.childName, scrollFrame)
    scrollChild:SetSize(opt.childWidth or 400, opt.childHeight or 1)
    scrollFrame:SetScrollChild(scrollChild)
    local track = TaskTracker.MakeScrollBar(scrollFrame, opt.trackParent or host)
    host.scrollFrame = scrollFrame
    host.scrollChild = scrollChild
    host.scrollBarTrack = track
    local pane
    if opt.pane ~= false then
        pane = CreateFrame("Frame", nil, scrollChild)
        pane:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        host.pane = pane
    end
    return host, scrollFrame, scrollChild, pane, track
end

local openDropdownMenus = {}

--- One open list at a time. Flyouts are not registered, so a side list does not close its parent.
function TaskTracker.RegisterOpenDropdown(menu)
    if not menu or menu._ttDropReg then return end
    menu._ttDropReg = true
    openDropdownMenus[menu] = true
    local show = menu.Show
    menu.Show = function(self, ...)
        TaskTracker.CloseOtherDropdowns(self)
        return show(self, ...)
    end
end

function TaskTracker.CloseOtherDropdowns(except)
    for menu in pairs(openDropdownMenus) do
        if menu ~= except and menu.IsShown and menu:IsShown() then
            menu:Hide()
        end
    end
end

--- Simple exclusive dropdown. spec.items is `{ { key=, label= }, ... }` or a list of keys.
--- An item with `children` opens a side list. A child can have children too.
--- Returns `{ button, menu, rows, flyouts, refresh }`.
function TaskTracker.MakeDropdown(parent, spec)
    spec = spec or {}
    local width = spec.width or 200
    local btnH = spec.buttonHeight or 24
    local rowH = spec.rowHeight or 24
    local items = spec.items or {}
    local rowGap = spec.rowGap or 2
    local btn = TaskTracker.MakeButton(parent, spec.label or "", width, btnH)
    if TaskTracker.AttachDropdownArrow then
        TaskTracker.AttachDropdownArrow(btn)
    end
    if spec.quiet then
        btn._ttIdleBgKey = spec.buttonBgKey or "headerBg2"
    end
    if spec.disableHover then
        btn:SetScript("OnEnter", nil)
        btn:SetScript("OnLeave", nil)
    end
    if spec.quiet then
        btn:SetScript("OnEnter", function()
            TaskTracker.PaintQuietHover(btn.bg, btn.label)
        end)
        btn:SetScript("OnLeave", function()
            TaskTracker.SetColor(btn.bg, spec.buttonBgKey or "headerBg2")
            TaskTracker.SetTextColor(btn.label, "textPrimary")
        end)
    end
    local n = #items
    local menu = CreateFrame("Frame", nil, spec.menuParent or parent)
    menu:SetFrameStrata(spec.strata or "DIALOG")
    menu:SetFrameLevel((btn:GetFrameLevel() or 0) + (spec.levelPad or 30))
    menu:SetSize(width, n * (rowH + rowGap) + 8)
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    menu:EnableMouse(true)
    menu:Hide()
    TaskTracker.RegisterOpenDropdown(menu)
    local menuBg = menu:CreateTexture(nil, "BACKGROUND")
    menuBg:SetAllPoints()
    TaskTracker.SetColor(menuBg, spec.menuBgKey or "headerBg2")
    TaskTracker.MakeBorder(menu, "border")

    local function itemKey(it)
        if type(it) == "table" then return it.key end
        return it
    end
    local function itemLabel(it)
        if type(it) == "table" then return it.label end
        if spec.getLabel then return spec.getLabel(it) end
        return tostring(it)
    end

    local rows = {}
    local flyouts = {}
    local painted = {}

    local function hideFlyouts()
        for i = 1, #flyouts do
            flyouts[i]:Hide()
        end
    end

    local function toggleFlyout(fly)
        if not fly then return end
        local open = fly:IsShown()
        hideFlyouts()
        if not open then
            fly:Show()
            fly:Raise()
        end
    end

    local function entryHasKey(it, sel)
        if sel == nil then return false end
        if type(it) ~= "table" then return it == sel end
        if it.key == sel then return true end
        local kids = it.children
        if type(kids) ~= "table" then return false end
        for i = 1, #kids do
            if entryHasKey(kids[i], sel) then return true end
        end
        return false
    end

    local function paintEntry(row, sel)
        local it = row._ttItem
        if spec.quiet then
            local picked = entryHasKey(it, sel)
            TaskTracker.PaintQuietChoice(row.bg, row.label, picked)
            if not picked and row.bg and not row._ttHover then
                TaskTracker.SetColor(row.bg, spec.choiceBgKey or "headerBg2")
            end
            if row.label and TaskTracker.ApplyOptionsFont then
                TaskTracker.ApplyOptionsFont(row.label, "body")
            end
        else
            TaskTracker.SetButtonActive(row, entryHasKey(it, sel))
        end
    end

    local function refresh()
        local sel = spec.getSelected and spec.getSelected()
        local lab
        if spec.selectedLabel then
            lab = spec.selectedLabel(sel)
        elseif spec.getLabel and sel ~= nil then
            lab = spec.getLabel(sel)
        else
            lab = sel
        end
        if lab ~= nil then
            btn:SetLabel(lab)
        end
        if spec.quiet then
            TaskTracker.SetColor(btn.bg, spec.buttonBgKey or "headerBg2")
            TaskTracker.SetTextColor(btn.label, "textPrimary")
            if btn.label and TaskTracker.ApplyOptionsFont then
                TaskTracker.ApplyOptionsFont(btn.label, "body")
            end
        end
        for i = 1, #painted do
            paintEntry(painted[i], sel)
        end
    end

    local function addItemRow(parentMenu, it, index, rowWidth, outRows)
        local key = itemKey(it)
        local kids = type(it) == "table" and it.children
        local hasKids = type(kids) == "table" and #kids > 0
        local row = TaskTracker.MakeButton(parentMenu, itemLabel(it), math.max(40, rowWidth), rowH)
        row:SetPoint("TOPLEFT", parentMenu, "TOPLEFT", 5, -4 - (index - 1) * (rowH + rowGap))
        row._ttItem = it
        if spec.quiet then
            row:SetScript("OnEnter", function()
                row._ttHover = true
                local sel = spec.getSelected and spec.getSelected()
                if not entryHasKey(row._ttItem, sel) then
                    TaskTracker.PaintQuietHover(row.bg, row.label)
                end
            end)
            row:SetScript("OnLeave", function()
                row._ttHover = false
                local sel = spec.getSelected and spec.getSelected()
                paintEntry(row, sel)
            end)
        elseif spec.disableHover then
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
        end
        local fly
        if hasKids then
            fly = CreateFrame("Frame", nil, parentMenu)
            fly:SetFrameStrata(spec.strata or "DIALOG")
            fly:SetFrameLevel((parentMenu:GetFrameLevel() or 0) + 8)
            fly:SetSize(rowWidth + 10, #kids * (rowH + rowGap) + 8)
            fly:SetPoint("TOPLEFT", row, "TOPRIGHT", 8, 0)
            fly:SetClampedToScreen(true)
            fly:EnableMouse(true)
            fly:Hide()
            local flyBg = fly:CreateTexture(nil, "BACKGROUND")
            flyBg:SetAllPoints()
            TaskTracker.SetColor(flyBg, spec.menuBgKey or "headerBg2")
            TaskTracker.MakeBorder(fly, "border")
            fly.rows = {}
            flyouts[#flyouts + 1] = fly
            row.flyout = fly
            for c = 1, #kids do
                addItemRow(fly, kids[c], c, rowWidth, fly.rows)
            end
            local mark = row:CreateTexture(nil, "OVERLAY")
            mark:SetSize(12, 12)
            mark:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            if TaskTracker.ApplyTwistIcon then
                TaskTracker.ApplyTwistIcon(mark, false)
            end
            if key ~= nil then
                local chev = CreateFrame("Button", nil, row)
                chev:SetSize(rowH, rowH)
                chev:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                chev:SetScript("OnClick", function()
                    toggleFlyout(fly)
                end)
            end
            if row.label then
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
                row.label:SetPoint("RIGHT", row, "RIGHT", -20, 0)
                row.label:SetJustifyH("LEFT")
                row.label:SetJustifyV("MIDDLE")
            end
        end
        row:SetScript("OnClick", function()
            if hasKids and key == nil then
                toggleFlyout(fly)
                return
            end
            if key ~= nil and spec.onSelect then
                spec.onSelect(key)
            end
            menu:Hide()
            refresh()
        end)
        outRows[#outRows + 1] = row
        painted[#painted + 1] = row
    end

    local rowWidth = math.max(40, width - 10)
    for i = 1, #items do
        addItemRow(menu, items[i], i, rowWidth, rows)
    end
    menu:SetScript("OnHide", hideFlyouts)

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            hideFlyouts()
            menu:Show()
            menu:Raise()
            refresh()
        end
    end)
    refresh()
    return { button = btn, menu = menu, rows = rows, flyouts = flyouts, refresh = refresh }
end

--- Label + [-] [edit] [+] integer row. Returns nextY, row `{ lab, down, ed, up, sync }`.
function TaskTracker.MakeIntSpinnerRow(parent, spec)
    spec = spec or {}
    local t = T()
    local xLeft = spec.x or 10
    local yRowTop = spec.y or 0
    local labelToCtrl = spec.labelToCtrl or 13
    local rowStride = spec.rowStride or 39
    local step = spec.step or 1
    local minV = spec.min or 0
    local maxV = spec.max or 999
    local font = spec.font or t.fontNormal or "GameFontNormalSmall"

    local lab = TaskTracker.CreateFontString(parent, nil, "OVERLAY", font)
    lab:SetPoint("TOPLEFT", parent, "TOPLEFT", xLeft, -yRowTop)
    TaskTracker.SetTextColor(lab, spec.labelColorKey or "textSecondary")
    lab:SetText(spec.label or "")

    local ctrlH = spec.ctrlHeight or 22
    local btnW = spec.btnWidth or 22
    local editW = spec.editWidth or 44
    local yOff = yRowTop + labelToCtrl
    local well = CreateFrame("Frame", nil, parent)
    well:SetSize(btnW + editW + btnW, ctrlH)
    well:SetPoint("TOPLEFT", parent, "TOPLEFT", xLeft, -yOff)
    local wellBg = well:CreateTexture(nil, "BACKGROUND")
    wellBg:SetAllPoints()
    TaskTracker.SetColor(wellBg, "inputBg")
    TaskTracker.MakeBorder(well, "border")

    local function stepButton(iconName)
        local b = TaskTracker.MakeIconButton(well, btnW, ctrlH, TaskTracker.ChromeIconOpt())
        b:SetChromeIcon(iconName)
        return b
    end

    local down = stepButton("minus")
    down:SetPoint("LEFT", well, "LEFT", 0, 0)
    local ed = TaskTracker.MakeEditBox(parent, spec.editName, editW, ctrlH, { plain = true })
    ed:SetPoint("LEFT", down, "RIGHT", 0, 0)
    if spec.allowNegative then
        ed:SetNumeric(false)
        ed:SetMaxLetters(spec.maxLetters or 4)
    else
        ed:SetNumeric(true)
        ed:SetMaxLetters(spec.maxLetters or 3)
    end
    local up = stepButton("plus")
    up:SetPoint("LEFT", ed, "RIGHT", 0, 0)

    local function getVal()
        if spec.getVal then return spec.getVal() end
        return minV
    end
    local function apply(n)
        if spec.requireDB ~= false and not TaskTrackerDB then return end
        n = math.max(minV, math.min(maxV, math.floor((tonumber(n) or minV) + 0.5)))
        if spec.setVal then spec.setVal(n) end
        if spec.onCommit then spec.onCommit(n) end
    end
    local function sync()
        ed:SetText(tostring(getVal()))
    end
    local function commit()
        local n = tonumber(ed:GetText())
        if not n then
            sync()
            return
        end
        apply(n)
        sync()
    end

    ed:SetScript("OnEnterPressed", function(self)
        commit()
        self:ClearFocus()
    end)
    ed:SetScript("OnEscapePressed", function(self)
        sync()
        self:ClearFocus()
    end)
    ed:SetScript("OnEditFocusLost", function()
        commit()
    end)
    down:SetScript("OnClick", function()
        apply(getVal() - step)
        sync()
    end)
    up:SetScript("OnClick", function()
        apply(getVal() + step)
        sync()
    end)
    sync()
    return yRowTop + rowStride, { lab = lab, down = down, ed = ed, up = up, well = well, sync = sync }
end

-- ─────────────────────────────────────
-- Icon button chrome (shared by toolbar glyphs and secure macro buttons)
-- opt.normalBgKey / opt.hoverBgKey — theme keys for SetColor on btn.bg
-- opt.iconFill / opt.iconMargin — fill the button instead of the 70%/18px cap
-- opt.noHover — skip OnEnter/OnLeave
-- ─────────────────────────────────────
local function applyIconButtonChrome(btn, width, height, opt)
    local t = T()
    opt = opt or {}
    local normalKey = opt.normalBgKey or "headerBg"
    local hoverKey  = opt.hoverBgKey or "accentBg"

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    btn.bg = bg
    if opt.noBorder then
        bg:SetColorTexture(0, 0, 0, 0)
    else
        TaskTracker.SetColor(bg, normalKey)
        TaskTracker.MakeBorder(btn, "border")
    end

    local iw, ih
    if opt.iconFill then
        local m  = opt.iconMargin or 1
        local bw = width or 20
        local bh = height or 20
        iw = math.max(8, bw - 2 * m)
        ih = math.max(8, bh - 2 * m)
    else
        iw = math.floor(((width or 20) * 0.7) + 0.5)
        ih = math.floor(((height or 20) * 0.7) + 0.5)
        iw = math.max(10, math.min(iw, 18))
        ih = math.max(10, math.min(ih, 18))
    end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iw, ih)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.icon = icon

    local text = TaskTracker.CreateFontString(btn, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    text:SetAllPoints()
    text:SetText("")
    text:Hide()
    btn.label = text

    local function applyLeave()
        if opt.noBorder then
            bg:SetColorTexture(0, 0, 0, 0)
        else
            TaskTracker.SetColor(bg, (opt.leaveBgKey or normalKey))
        end
    end

    if not opt.noHover then
        btn:SetScript("OnEnter", function()
            TaskTracker.SetColor(bg, hoverKey)
        end)
        btn:SetScript("OnLeave", function()
            if opt.onLeave then
                opt.onLeave(btn)
            else
                applyLeave()
            end
        end)
    end

    function btn:SetIconAtlas(atlasName, useAtlasSize)
        if not icon then return end
        if atlasName and atlasName ~= "" then
            icon:SetAtlas(atlasName, useAtlasSize and true or false)
            icon:SetVertexColor(1, 1, 1, 1)
            icon:Show()
        else
            icon:SetTexture(nil)
            icon:Hide()
        end
    end

    function btn:SetChromeIcon(name)
        if not icon then return end
        btn._ttChromeIcon = name
        TaskTracker.TrackChromeIconButton(btn)
        if name and name ~= "" then
            TaskTracker.ApplyChromeIcon(icon, name)
        else
            icon:SetTexture(nil)
            icon:Hide()
        end
    end
end

function TaskTracker.ChromeIconOpt(extra)
    local opt = {
        noBorder = true,
        iconFill = true,
        iconMargin = 1,
        hoverBgKey = "accentBg",
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            opt[k] = v
        end
    end
    return opt
end

function TaskTracker.MakeIconButton(parent, width, height, opt)
    local t   = T()
    opt       = opt or {}
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 20, height or t.buttonHeight or 20)
    applyIconButtonChrome(btn, width, height, opt)
    return btn
end

--- Resize an icon button and its ARTWORK texture (same math as applyIconButtonChrome).
function TaskTracker.SizeIconButton(btn, width, height, opt)
    if not btn then return end
    opt = opt or {}
    local bw = width or 20
    local bh = height or 20
    btn:SetSize(bw, bh)
    local icon = btn.icon
    if not icon then return end
    local iw, ih
    if opt.iconFill then
        local m = opt.iconMargin or 1
        iw = math.max(8, bw - 2 * m)
        ih = math.max(8, bh - 2 * m)
    else
        iw = math.max(10, math.min(18, math.floor(bw * 0.7 + 0.5)))
        ih = math.max(10, math.min(18, math.floor(bh * 0.7 + 0.5)))
    end
    icon:SetSize(iw, ih)
end

-- ─────────────────────────────────────
-- Secure macro command buttons (/cast, /way, etc.)
-- SetAttribute must not run during combat lockdown.
-- ─────────────────────────────────────

TaskTracker._pendingSecureMacroBtns = TaskTracker._pendingSecureMacroBtns or {}

local function trimMacroText(s)
    return TaskTracker.Trim(s)
end

--- Inline macrotext must look like a macro body: slash commands need a leading "/".
--- Also enforce the same 255-char limit as normal macros (TWW secure macrotext rules).
local function normalizeInlineMacroText(s)
    s = trimMacroText(s)
    if s == "" then return s end
    if not string.match(s, "[\r\n]") then
        if s:sub(1, 1) ~= "/" and s:sub(1, 1) ~= "#" then
            s = "/" .. s
        end
        if #s > 255 then
            s = s:sub(1, 255)
        end
        return s
    end
    local parts = {}
    for line in string.gmatch(s, "[^\r\n]+") do
        local L = trimMacroText(line)
        if L ~= "" then
            if L:sub(1, 1) ~= "/" and L:sub(1, 1) ~= "#" then
                L = "/" .. L
            end
            parts[#parts + 1] = L
        end
    end
    if #parts == 0 then return "" end
    s = table.concat(parts, "\n")
    if #s > 255 then
        s = s:sub(1, 255)
    end
    return s
end

--- @param namespace string|nil  Disambiguates frames (e.g. note-window run vs list row pin) that share taskId+index.
function TaskTracker.SecureCommandButtonName(taskId, index, namespace)
    local tid = tostring(taskId or "x"):gsub("[^%w]", "_")
    if #tid > 28 then
        tid = tid:sub(1, 28)
    end
    local ns = "btn"
    if type(namespace) == "string" and namespace ~= "" then
        ns = namespace:gsub("[^%w]", "_")
        if #ns > 12 then
            ns = ns:sub(1, 12)
        end
    end
    return string.format("TaskTracker_Cmd_%s_%s_%d", ns, tid, tonumber(index) or 0)
end

function TaskTracker.FlushPendingSecureMacroButtons()
    if InCombatLockdown() then return end
    local pend = TaskTracker._pendingSecureMacroBtns
    if not pend then return end
    local keys = {}
    for btn in pairs(pend) do
        keys[#keys + 1] = btn
    end
    for _, btn in ipairs(keys) do
        if btn and btn.SetAttribute and btn._taskTrackerMacroPending ~= nil then
            local text = btn._taskTrackerMacroPending
            btn._taskTrackerMacroPending = nil
            if btn._taskTrackerLineMode then
                pcall(function()
                    btn:SetAttribute("macro", nil)
                    btn:SetAttribute("macrotext", nil)
                    btn:SetAttribute("type", nil)
                end)
            else
                pcall(function()
                    btn:SetAttribute("macro", nil)
                    btn:SetAttribute("type", "macro")
                    btn:SetAttribute("macrotext", text)
                end)
            end
        end
        pend[btn] = nil
    end
end

if not TaskTracker._secureMacroRegenFrame then
    local f = CreateFrame("Frame", nil)
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", TaskTracker.FlushPendingSecureMacroButtons)
    TaskTracker._secureMacroRegenFrame = f
end

function TaskTracker.SetSecureMacroButtonAttributes(btn, macroText)
    if not btn or not btn.SetAttribute then return end
    macroText = normalizeInlineMacroText(macroText)
    if InCombatLockdown() then
        btn._taskTrackerMacroPending = macroText
        TaskTracker._pendingSecureMacroBtns[btn] = true
        return
    end
    pcall(function()
        btn:SetAttribute("macro", nil)
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", macroText)
    end)
    btn._taskTrackerMacroPending = nil
    TaskTracker._pendingSecureMacroBtns[btn] = nil
end

TaskTracker.COMMAND_TEXT_CAP = 4000
TaskTracker.COMMAND_LINE_CAP = 40

--- Keep at most 4000 characters and 40 non-empty lines. Blank lines inside that stay.
function TaskTracker.ClampCommandText(text)
    if type(text) ~= "string" then return "" end
    text = TaskTracker.Trim(text)
    if text == "" then return "" end
    if #text > TaskTracker.COMMAND_TEXT_CAP then
        text = text:sub(1, TaskTracker.COMMAND_TEXT_CAP)
    end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local out = {}
    local kept = 0
    local cap = TaskTracker.COMMAND_LINE_CAP
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if TaskTracker.Trim(line) ~= "" then
            kept = kept + 1
            if kept > cap then break end
        end
        out[#out + 1] = line
    end
    while #out > 0 and TaskTracker.Trim(out[#out]) == "" do
        out[#out] = nil
    end
    return table.concat(out, "\n")
end

--- First line for the one-line box. Adds ... when later lines have text.
function TaskTracker.CommandPreviewText(text)
    if type(text) ~= "string" then return "" end
    local first = TaskTracker.Trim(text:match("^[^\r\n]*") or "")
    local nl = text:find("[\r\n]")
    local more = nl and TaskTracker.Trim(text:sub(nl + 1)) ~= ""
    if not more then return first end
    if first == "" then return "..." end
    return first .. "..."
end

local function bindCommandLineClick(btn)
    if not btn or btn._ttLineClick then return end
    if not btn._ttInsecure and btn.IsProtected and btn:IsProtected() then return end
    btn._ttLineClick = true
    btn:HookScript("OnClick", function(self, _, down)
        if down then return end
        local body = self._ttRunLines
        if type(body) ~= "string" or body == "" then return end
        if InCombatLockdown and InCombatLockdown() then return end
        TaskTracker.RunSlashLines(body)
    end)
end

--- One click, one short loop. Each non-empty line is its own slash command.
function TaskTracker.RunSlashLines(text)
    if InCombatLockdown and InCombatLockdown() then return end
    text = TaskTracker.ClampCommandText(text)
    if text == "" or not ChatEdit_SendText then return end
    local edit = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()
    if not edit and DEFAULT_CHAT_FRAME then
        edit = DEFAULT_CHAT_FRAME.editBox
    end
    if not edit then return end
    local old = edit:GetText()
    if issecretvalue and issecretvalue(old) then old = nil end
    local n = 0
    local cap = TaskTracker.COMMAND_LINE_CAP
    for line in string.gmatch(text, "[^\r\n]+") do
        local L = TaskTracker.Trim(line)
        if L ~= "" then
            if L:sub(1, 1) ~= "/" and L:sub(1, 1) ~= "#" then
                L = "/" .. L
            end
            if #L > 255 then L = L:sub(1, 255) end
            n = n + 1
            if n > cap then break end
            edit:SetText(L)
            ChatEdit_SendText(edit, false)
        end
    end
    if old ~= nil then
        edit:SetText(old)
    end
end

--- Full keeps one macro. Lines clears it and runs from the click hook.
function TaskTracker.ApplyCommandRunMode(btn, command, runMode)
    if not btn or not btn.SetAttribute then return end
    bindCommandLineClick(btn)
    command = type(command) == "string" and command or ""
    local lineMode = runMode == "line"
    btn._taskTrackerLineMode = lineMode or nil
    if lineMode then
        btn._ttRunLines = command
        if InCombatLockdown and InCombatLockdown() then
            btn._taskTrackerMacroPending = ""
            TaskTracker._pendingSecureMacroBtns[btn] = true
            return
        end
        pcall(function()
            btn:SetAttribute("macro", nil)
            btn:SetAttribute("macrotext", nil)
            btn:SetAttribute("type", nil)
        end)
        btn._taskTrackerMacroPending = nil
        TaskTracker._pendingSecureMacroBtns[btn] = nil
        return
    end
    btn._ttRunLines = nil
    TaskTracker.SetSecureMacroButtonAttributes(btn, command)
end

--- Icon-styled macro run button. Default: SecureActionButtonTemplate (macrotext often ignored on retail).
--- opt.insecureMacro — use InsecureActionButtonTemplate: macrotext runs out of combat only (notes / edit UI).
--- opt.unnamedSecure — if true, no global name (safe when buttons are torn down and recreated; names would collide).
--- opt.noSecureHover — if true, no OnEnter/OnLeave on the button (Lua on SecureActionButton can block macro clicks).
--- opt.iconFill — if true, size the icon texture to nearly fill the button (opt.iconMargin px inset per side; default 1).
function TaskTracker.MakeSecureMacroIconButton(parent, width, height, taskId, buttonIndex, opt)
    local t   = T()
    opt       = opt or {}
    local name
    if opt.unnamedSecure then
        name = nil
    else
        name = TaskTracker.SecureCommandButtonName(taskId, buttonIndex, opt.secureNamespace)
    end
    local btn
    if opt.insecureMacro then
        local ok, b = pcall(function()
            return CreateFrame("Button", name, parent, "InsecureActionButtonTemplate")
        end)
        if ok and b then
            btn = b
        end
    end
    if not btn then
        btn = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    end
    btn:SetSize(width or 20, height or t.buttonHeight or 20)
    applyIconButtonChrome(btn, width, height, {
        normalBgKey = opt.normalBgKey,
        hoverBgKey  = opt.hoverBgKey,
        leaveBgKey  = opt.leaveBgKey,
        onLeave     = opt.onLeave,
        iconFill    = opt.iconFill,
        iconMargin  = opt.iconMargin,
        noBorder    = opt.noBorder,
        noHover     = opt.noSecureHover and not opt.insecureMacro,
    })

    if opt.insecureMacro then
        btn._ttInsecure = true
        btn:RegisterForClicks("AnyUp", "AnyDown")
    else
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    end
    return btn
end

-- ─────────────────────────────────────
-- Styled panel (replaces BasicFrameTemplate)
-- ─────────────────────────────────────
function TaskTracker.MakePanel(name, parent, width, height, opt)
    local t     = T()
    opt         = opt or {}
    local frame = CreateFrame("Frame", name, parent)
    frame:SetSize(width, height)
    frame:SetMovable(true)
    if opt.optionsChrome then
        frame._ttOptionsChrome = true
    else
        frame._ttNotOptionsChrome = true
    end
    -- IMPORTANT: the panel body should not intercept clicks (camera look, UI interaction).
    -- Only the title bar is mouse-enabled for dragging and button clicks.
    frame:EnableMouse(false)
    frame:SetClampedToScreen(true)

    -- Background
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    TaskTracker.SetColor(bg, "bg")
    frame.bg = bg

    -- Full border
    TaskTracker.MakeBorder(frame, "border")

    -- Top accent line (2px)
    TaskTracker.MakeEdge(frame, "TOP", "accent", 2)

    local titleH = opt.titleHeight or t.titleHeight or 28
    local titlePad = opt.titleMargin or t.padding or 8
    local iconSz = opt.titleIconSize or 20

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(titleH)
    titleBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.titleBar = titleBar
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    -- Do not propagate clicks from the title bar: propagation can prevent dragging on some clients.
    if titleBar.SetPropagateMouseClicks then
        pcall(function()
            titleBar:SetPropagateMouseClicks(false)
        end)
    end

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    TaskTracker.SetColor(titleBg, "headerBg")

    TaskTracker.MakeEdge(titleBar, "BOTTOM", "border")

    -- Title text
    local titleText = TaskTracker.CreateFontString(titleBar, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    if opt.titleFontSize and TaskTracker.ApplyOptionsFont then
        TaskTracker.ApplyOptionsFont(titleText, "title", opt.titleFontSize)
    end
    titleText:SetPoint("LEFT", titleBar, "LEFT", titlePad, 0)
    titleText:SetWidth(math.max(48, width * 0.45))
    titleText:SetJustifyH("LEFT")
    TaskTracker.SetTextColor(titleText, "textAccent")
    frame.TitleText = titleText

    -- Close
    local closeBtn = TaskTracker.MakeIconButton(titleBar, iconSz, iconSz, TaskTracker.ChromeIconOpt())
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    closeBtn:SetChromeIcon("close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    frame.CloseButton = closeBtn

    -- Content area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT",     frame, "TOPLEFT",     1, -titleH)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.Content = content

    return frame
end

-- ─────────────────────────────────────
-- Styled group header
-- ─────────────────────────────────────
function TaskTracker.MakeHeader(parent, width, yOff, indent, label, expanded, accentKey, bgKey)
    local t      = T()
    local w      = width - indent
    local header = CreateFrame("Button", nil, parent)
    header:SetSize(w, t.headerHeight or 26)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", indent, -yOff)

    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    TaskTracker.SetColor(bg, bgKey or "headerBg")

    TaskTracker.MakeEdge(header, "BOTTOM", "border")
    TaskTracker.MakeAccentBar(header, accentKey or "accent")

    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("LEFT", header, "LEFT", (t.accentBarWidth or 3) + 8, 0)
    TaskTracker.ApplyTwistIcon(arrow, expanded)

    local lbl = TaskTracker.CreateFontString(header, nil, "OVERLAY", t.fontBold or "GameFontNormal")
    lbl:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
    TaskTracker.SetTextColor(lbl, "textHeader")
    lbl:SetText(label)

    local count = TaskTracker.CreateFontString(header, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
    count:SetPoint("RIGHT", header, "RIGHT", -(t.padding or 8), 0)

    header.arrow = arrow
    header.lbl   = lbl
    header.count = count
    header.bg    = bg

    return header
end

-- ─────────────────────────────────────
-- Custom scrollbar
-- Attaches a hand-built track + thumb to
-- a plain (no-template) ScrollFrame.
--
-- Usage:
--   local sf = CreateFrame("ScrollFrame", name, parent)
--   local sc = CreateFrame("Frame", nil, sf)
--   sf:SetScrollChild(sc)
--   TaskTracker.MakeScrollBar(sf, trackParent)
--
-- trackParent is the frame the track is
-- parented to (usually panel.Content).
-- The track sits flush against its RIGHT
-- edge so it doesn't consume scroll width.
-- ─────────────────────────────────────
local TRACK_W    = 4
local THUMB_MIN  = 20

function TaskTracker.MakeScrollBar(scrollFrame, trackParent, opt)
    opt = (type(opt) == "table") and opt or {}
    local bottomInset = tonumber(opt.bottom) or 0
    -- Track (background strip)
    local track = CreateFrame("Frame", nil, trackParent)
    track:SetWidth(TRACK_W)
    track:SetPoint("TOPRIGHT",    trackParent, "TOPRIGHT",    0,  0)
    track:SetPoint("BOTTOMRIGHT", trackParent, "BOTTOMRIGHT", 0, bottomInset)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    TaskTracker.SetColor(trackBg, "headerBg")

    -- Thumb (draggable button)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(TRACK_W)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    TaskTracker.SetColor(thumbTex, "accent")

    -- ── update: clamp scroll to the current range, then place the thumb ──
    local updating = false
    local function UpdateThumb()
        if updating then return end
        updating = true

        local sc       = scrollFrame:GetScrollChild()
        local frameH   = scrollFrame:GetHeight() or 0
        local contentH = sc and sc:GetHeight() or 0
        local trackH   = track:GetHeight() or 0
        local maxScroll = math.max(0, contentH - frameH)
        local cur = scrollFrame:GetVerticalScroll() or 0
        if cur < 0 or cur > maxScroll then
            scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, cur)))
            cur = scrollFrame:GetVerticalScroll() or 0
        end

        if maxScroll <= 0.5 or trackH <= THUMB_MIN then
            thumb:Hide()
            updating = false
            return
        end
        thumb:Show()

        local thumbH = math.max(THUMB_MIN, trackH * (frameH / math.max(contentH, 1)))
        if thumbH > trackH then thumbH = trackH end
        thumb:SetHeight(thumbH)

        local scrollPct = (maxScroll > 0) and math.max(0, math.min(1, cur / maxScroll)) or 0
        local maxOffset = math.max(0, trackH - thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(scrollPct * maxOffset))

        updating = false
    end

    -- ── wheel scrolling ──
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local sc       = scrollFrame:GetScrollChild()
        local frameH   = scrollFrame:GetHeight()
        local contentH = sc and sc:GetHeight() or 0
        local current  = scrollFrame:GetVerticalScroll()
        local step     = 30
        local new      = math.max(0, math.min(contentH - frameH, current - delta * step))
        scrollFrame:SetVerticalScroll(new)
        UpdateThumb()
    end)

    -- ── thumb dragging ──
    local dragStartY, dragStartScroll

    thumb:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        dragStartY      = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        dragStartScroll = scrollFrame:GetVerticalScroll()
        thumb:SetScript("OnUpdate", function()
            local curY    = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            local delta   = dragStartY - curY
            local sc      = scrollFrame:GetScrollChild()
            local frameH  = scrollFrame:GetHeight()
            local contentH = sc and sc:GetHeight() or 0
            local trackH  = track:GetHeight()
            local thumbH  = thumb:GetHeight()
            local ratio   = (contentH - frameH) / (trackH - thumbH)
            local new     = math.max(0, math.min(contentH - frameH, dragStartScroll + delta * ratio))
            scrollFrame:SetVerticalScroll(new)
            UpdateThumb()
        end)
    end)

    thumb:SetScript("OnMouseUp", function()
        thumb:SetScript("OnUpdate", nil)
    end)

    -- ── click on track to jump ──
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local _, trackTop = track:GetCenter()
        local _, curY     = GetCursorPosition()
        curY = curY / UIParent:GetEffectiveScale()
        -- convert screen Y to track-local offset from top
        local trackScreenTop = track:GetTop()
        local clickOffset    = trackScreenTop - curY
        local sc             = scrollFrame:GetScrollChild()
        local frameH         = scrollFrame:GetHeight()
        local contentH       = sc and sc:GetHeight() or 0
        local trackH         = track:GetHeight()
        local thumbH         = thumb:GetHeight()
        local ratio          = (contentH - frameH) / (trackH - thumbH)
        local new            = math.max(0, math.min(contentH - frameH, (clickOffset - thumbH / 2) * ratio))
        scrollFrame:SetVerticalScroll(new)
        UpdateThumb()
    end)

    -- Hook so later SetScript (list paint) does not drop thumb updates.
    scrollFrame:HookScript("OnVerticalScroll", function()
        UpdateThumb()
    end)
    scrollFrame:HookScript("OnScrollRangeChanged", function()
        UpdateThumb()
    end)
    scrollFrame:HookScript("OnSizeChanged", function()
        UpdateThumb()
    end)

    -- expose so callers can force a refresh
    scrollFrame.UpdateScrollBar = UpdateThumb

    UpdateThumb()
    return track
end

--- Horizontal twin of MakeScrollBar. Track sits on the BOTTOM of trackParent.
--- opt.right insets the track so it does not cover a vertical bar in the corner.
function TaskTracker.MakeHorizontalScrollBar(scrollFrame, trackParent, opt)
    opt = (type(opt) == "table") and opt or {}
    local rightInset = tonumber(opt.right) or 0

    local track = CreateFrame("Frame", nil, trackParent)
    track:SetHeight(TRACK_W)
    track:SetPoint("BOTTOMLEFT",  trackParent, "BOTTOMLEFT",  0, 0)
    track:SetPoint("BOTTOMRIGHT", trackParent, "BOTTOMRIGHT", -rightInset, 0)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    TaskTracker.SetColor(trackBg, "headerBg")

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetHeight(TRACK_W)
    thumb:SetPoint("LEFT", track, "LEFT", 0, 0)

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    TaskTracker.SetColor(thumbTex, "accent")

    local function range()
        local sc = scrollFrame:GetScrollChild()
        local frameW = scrollFrame:GetWidth() or 0
        local contentW = sc and sc:GetWidth() or 0
        return math.max(0, contentW - frameW)
    end

    local function UpdateThumb()
        local sc = scrollFrame:GetScrollChild()
        local frameW = scrollFrame:GetWidth() or 0
        local contentW = sc and sc:GetWidth() or 0
        local trackW = track:GetWidth() or 0
        if contentW <= frameW + 0.5 or trackW <= THUMB_MIN then
            thumb:Hide()
            return
        end
        thumb:Show()
        local ratio = frameW / contentW
        local thumbW = math.max(THUMB_MIN, trackW * ratio)
        thumb:SetWidth(thumbW)
        local maxScroll = contentW - frameW
        local scrollPct = 0
        if maxScroll > 0 then
            scrollPct = (scrollFrame:GetHorizontalScroll() or 0) / maxScroll
        end
        local maxOffset = trackW - thumbW
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", track, "LEFT", scrollPct * maxOffset, 0)
        thumb:SetPoint("TOP", track, "TOP", 0, 0)
        thumb:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    end

    local dragStartX, dragStartScroll
    thumb:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        dragStartX = (GetCursorPosition() or 0) / UIParent:GetEffectiveScale()
        dragStartScroll = scrollFrame:GetHorizontalScroll() or 0
        thumb:SetScript("OnUpdate", function()
            local curX = (GetCursorPosition() or 0) / UIParent:GetEffectiveScale()
            local delta = curX - dragStartX
            local trackW = track:GetWidth() or 0
            local thumbW = thumb:GetWidth() or THUMB_MIN
            local maxScroll = range()
            local denom = trackW - thumbW
            if denom <= 0 or maxScroll <= 0 then return end
            local new = math.max(0, math.min(maxScroll, dragStartScroll + delta * (maxScroll / denom)))
            scrollFrame:SetHorizontalScroll(new)
            UpdateThumb()
        end)
    end)
    thumb:SetScript("OnMouseUp", function()
        thumb:SetScript("OnUpdate", nil)
    end)

    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local curX = (select(1, GetCursorPosition()) or 0) / UIParent:GetEffectiveScale()
        local trackLeft = track:GetLeft() or 0
        local clickOffset = curX - trackLeft
        local trackW = track:GetWidth() or 0
        local thumbW = thumb:GetWidth() or THUMB_MIN
        local maxScroll = range()
        local denom = trackW - thumbW
        if denom <= 0 or maxScroll <= 0 then return end
        local new = math.max(0, math.min(maxScroll, (clickOffset - thumbW / 2) * (maxScroll / denom)))
        scrollFrame:SetHorizontalScroll(new)
        UpdateThumb()
    end)

    scrollFrame:SetScript("OnHorizontalScroll", function()
        UpdateThumb()
    end)

    local prevUpdate = scrollFrame.UpdateScrollBar
    scrollFrame.UpdateScrollBar = function()
        if prevUpdate then prevUpdate() end
        UpdateThumb()
    end
    scrollFrame.UpdateHorizontalScrollBar = UpdateThumb

    UpdateThumb()
    return track
end

-- ─────────────────────────────────────
-- Styled edit box
-- ─────────────────────────────────────
function TaskTracker.MakeEditBox(parent, name, width, height, opt)
    local t   = T()
    opt = opt or {}
    local box = CreateFrame("EditBox", name, parent)
    box:SetSize(width or 200, height or 20)
    box:SetAutoFocus(false)
    box:SetFontObject(t.fontNormal or "GameFontNormalSmall")
    TaskTracker.ClearFontShadow(box)
    box:SetTextInsets(opt.plain and 2 or 6, opt.plain and 2 or 6, 0, 0)
    box:SetMaxLetters(60)

    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if opt.plain then
        bg:SetColorTexture(0, 0, 0, 0)
        local c = t.textPrimary
        if c then
            box:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
    else
        TaskTracker.SetColor(bg, "inputBg")
        TaskTracker.MakeBorder(box, "border")
    end

    return box
end

-- ─────────────────────────────────────
-- List row tooltips: same custom GameTooltip for every row, parked beside the
-- tracker at cursor height. Item / currency lines are copied from a hidden scan
-- tooltip (keeps our chrome). Achievements use live GetAchievementInfo /
-- GetAchievementCriteriaInfo (hidden SetHyperlink shows "Retrieving data").
-- Built-in module help is hover text; the Notes field is the player's.
-- Hold Ctrl for debug IDs only when TaskTrackerDB.debugRowIds is on (debug window, default off).
-- Disabled when TaskTrackerDB.showRowTooltips == false (Options: Task tooltip).
-- ─────────────────────────────────────

local function namesMatch(a, b)
    if not a or not b or a == "" or b == "" then return false end
    return tostring(a):lower() == tostring(b):lower()
end

--- kind is "achievement" | "item" | "currency". Third return: require linked name to match the row title.
local function ResolveListRowLinkedId(entry, node)
    if node and node.readyToBuyItemId then
        local itemId = tonumber(node.readyToBuyItemId)
        if itemId and itemId > 0 then
            return "item", itemId
        end
    end
    if node and node.type == "task" and TaskTracker.IsAdvancedTask and TaskTracker.IsAdvancedTask(node) then
        local a = node.advanced
        if a and a.type == "achievement" then
            local achId = tonumber(a.achievementId)
            if achId and achId > 0 then
                return "achievement", achId
            end
        end
        if a and a.type == "item" then
            local ids = a.itemIds
            local id = ids and tonumber(ids[1])
            if id and id > 0 then
                if (a.itemKind or "item") == "currency" then
                    return "currency", id
                end
                return "item", id
            end
        end
        if a and a.type == "collectable" and TaskTracker.GetCollectableEntry then
            local ent = TaskTracker.GetCollectableEntry(a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
            local curId = ent and tonumber(ent.currencyId)
            if curId and curId > 0 then
                return "currency", curId, true
            end
            local itemId = ent and tonumber(ent.itemId)
            if itemId and itemId > 0 then
                return "item", itemId, true
            end
        end
    end
    if entry then
        local trackId = tonumber(entry.trackItemId)
        if trackId and trackId > 0 then
            return "item", trackId
        end
        if entry.type == "collectable_owned" then
            local curId = tonumber(entry.currencyId)
            if curId and curId > 0 then
                return "currency", curId
            end
            local itemId = tonumber(entry.itemId)
            if itemId and itemId > 0 then
                return "item", itemId
            end
        end
        local curId = tonumber(entry.catchupCurrencyId)
        if curId and curId > 0 then
            return "currency", curId
        end
    end
    return nil
end

local scanTip
local function GetScanTooltip()
    if scanTip then return scanTip end
    scanTip = CreateFrame("GameTooltip", "TaskTrackerScanTooltip", UIParent, "GameTooltipTemplate")
    scanTip:Hide()
    return scanTip
end

local function FillScanTooltip(kind, id)
    local tip = GetScanTooltip()
    tip:Hide()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    if kind == "item" and tip.SetItemByID then
        local ok = pcall(tip.SetItemByID, tip, id)
        return ok == true and (tip:NumLines() or 0) > 0
    end
    if kind == "currency" then
        if tip.SetCurrencyByID then
            local ok = pcall(tip.SetCurrencyByID, tip, id)
            if ok == true and (tip:NumLines() or 0) > 0 then return true end
        end
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink and tip.SetHyperlink then
            local ok, link = pcall(C_CurrencyInfo.GetCurrencyLink, id)
            if ok and type(link) == "string" and link ~= "" then
                local ok2 = pcall(tip.SetHyperlink, tip, link)
                return ok2 == true and (tip:NumLines() or 0) > 0
            end
        end
    end
    return false
end

local function CopyScanTooltipToGameTooltip()
    local n = scanTip and scanTip:NumLines() or 0
    if n < 1 then return false end
    local copied = false
    for i = 1, n do
        local left = _G["TaskTrackerScanTooltipTextLeft" .. i]
        local right = _G["TaskTrackerScanTooltipTextRight" .. i]
        local lt = left and left.GetText and left:GetText()
        local rt = right and right.GetText and right:GetText()
        local hasL = type(lt) == "string" and lt ~= ""
        local hasR = type(rt) == "string" and rt ~= ""
        if hasL or hasR then
            local lr, lg, lb = 1, 1, 1
            if left and left.GetTextColor then
                lr, lg, lb = left:GetTextColor()
            end
            if hasR then
                local rr, rg, rb = 1, 1, 1
                if right and right.GetTextColor then
                    rr, rg, rb = right:GetTextColor()
                end
                GameTooltip:AddDoubleLine(hasL and lt or " ", rt, lr, lg, lb, rr, rg, rb)
            else
                GameTooltip:AddLine(lt, lr, lg, lb, true)
            end
            copied = true
        end
    end
    return copied
end

local function ScanTooltipTitleMatches(title)
    local left = _G["TaskTrackerScanTooltipTextLeft1"]
    local t = left and left.GetText and left:GetText()
    return namesMatch(t, title)
end

local function LookupLinkedNameAndDetail(kind, id)
    if kind == "achievement" and GetAchievementInfo then
        local ok, name, desc = pcall(function()
            local _, n, _, _, _, _, _, d = GetAchievementInfo(id)
            return n, d
        end)
        if ok and type(name) == "string" and name ~= "" then
            if type(desc) ~= "string" or desc == "" then desc = nil end
            return name, desc
        end
    elseif kind == "currency" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            local desc = info.description
            if type(desc) ~= "string" or desc == "" then desc = nil end
            return info.name, desc
        end
    elseif kind == "item" then
        local name
        if C_Item and C_Item.GetItemNameByID then
            name = C_Item.GetItemNameByID(id)
        end
        if (not name or name == "") and GetItemInfo then
            name = GetItemInfo(id)
        end
        if type(name) == "string" and name ~= "" then
            return name, nil
        end
    end
    return nil
end

local function criteriaNameForAchievement(achId, i)
    if not GetAchievementCriteriaInfo then return "Criteria " .. i end
    for _, hidden in ipairs({ true, false }) do
        local ok, cs = pcall(GetAchievementCriteriaInfo, achId, i, hidden)
        if ok and type(cs) == "string" and cs ~= "" then
            return cs
        end
    end
    return "Criteria " .. i
end

--- Live achievement text + criteria (avoids hidden-tooltip "Retrieving data").
local function AppendAchievementTooltipLines(achId)
    achId = tonumber(achId)
    if not achId or achId < 1 or not GetAchievementInfo then return false end
    local ok, name, _, completed, month, day, year, description, _, _, rewardText = pcall(function()
        local _, n, p, c, mo, d, y, desc, fl, ic, rw = GetAchievementInfo(achId)
        return n, p, c, mo, d, y, desc, fl, ic, rw
    end)
    if not ok or type(name) ~= "string" or name == "" then return false end
    if name == "Retrieving data" or name == "Retrieving Data" then return false end

    GameTooltip:AddLine(name, 1, 0.82, 0, false)
    if completed then
        if type(month) == "number" and month > 0 and type(day) == "number" and type(year) == "number" then
            GameTooltip:AddLine(string.format("Completed %d/%d/%d", month, day, year), 0.25, 0.95, 0.35, false)
        else
            GameTooltip:AddLine("Completed", 0.25, 0.95, 0.35, false)
        end
    end
    if type(description) == "string" and description ~= ""
        and description ~= "Retrieving data" and description ~= "Retrieving Data" then
        GameTooltip:AddLine(description, 1, 1, 1, true)
    end

    local num = 0
    if GetAchievementNumCriteria then
        local okN, n = pcall(GetAchievementNumCriteria, achId)
        if okN then num = tonumber(n) or 0 end
    end
    local maxShow = math.min(num, 12)
    if maxShow > 0 then
        GameTooltip:AddLine(" ", 1, 1, 1, false)
        for i = 1, maxShow do
            local cur, cap, done = 0, 1, false
            if TaskTracker.GetAchievementCriterionCurMax then
                cur, cap, done = TaskTracker.GetAchievementCriterionCurMax(achId, i)
            end
            cur = tonumber(cur) or 0
            cap = tonumber(cap) or 1
            local label = criteriaNameForAchievement(achId, i)
            local right
            if cap > 1 then
                right = string.format("%d / %d", cur, cap)
            else
                right = done and "Complete" or "Incomplete"
            end
            local lr, lg, lb = 0.85, 0.85, 0.85
            local rr, rg, rb = 1, 0.82, 0
            if done then
                lr, lg, lb = 0.25, 0.95, 0.35
                rr, rg, rb = 0.25, 0.95, 0.35
            end
            GameTooltip:AddDoubleLine(label, right, lr, lg, lb, rr, rg, rb)
        end
        if num > maxShow then
            GameTooltip:AddLine(string.format("… %d more criteria", num - maxShow), 0.65, 0.65, 0.65, false)
        end
    end

    if type(rewardText) == "string" and rewardText ~= "" then
        GameTooltip:AddLine(rewardText, 1, 0.82, 0, true)
    end
    return true
end

local function SetListRowTooltipOwner(anchor)
    local panel = TaskTracker.panel
    if panel and panel.IsShown and panel:IsShown() then
        GameTooltip:SetOwner(panel, "ANCHOR_NONE")
        return
    end
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
end

local function PlaceTooltipBesideFrame(host)
    if not host or not host.GetRight or not host:IsShown() then return end
    if not GameTooltip:IsShown() then return end

    local ui = UIParent
    local uiScale = (ui and ui.GetEffectiveScale and ui:GetEffectiveScale()) or 1
    if uiScale <= 0 then uiScale = 1 end
    local _, cursorY = GetCursorPosition()
    cursorY = (cursorY or 0) / uiScale

    local pScale = (host.GetEffectiveScale and host:GetEffectiveScale()) or uiScale
    if pScale <= 0 then pScale = uiScale end
    local toUI = pScale / uiScale
    local panelLeft = (host:GetLeft() or 0) * toUI
    local panelRight = (host:GetRight() or 0) * toUI

    local tipScale = (GameTooltip.GetEffectiveScale and GameTooltip:GetEffectiveScale()) or uiScale
    if tipScale <= 0 then tipScale = uiScale end
    local tipH = (GameTooltip:GetHeight() or 0) * (tipScale / uiScale)
    local topY = cursorY + (tipH * 0.5)
    local uiTop = (ui and ui.GetTop and ui:GetTop()) or topY
    local uiBottom = (ui and ui.GetBottom and ui:GetBottom()) or 0
    if topY > uiTop then topY = uiTop end
    if (topY - tipH) < uiBottom then
        topY = uiBottom + tipH
    end

    local uiRight = (ui and ui.GetRight and ui:GetRight()) or panelRight
    local rightSpace = uiRight - panelRight
    GameTooltip:ClearAllPoints()
    if rightSpace < 240 then
        GameTooltip:SetPoint("TOPRIGHT", ui, "BOTTOMLEFT", panelLeft - 6, topY)
    else
        GameTooltip:SetPoint("TOPLEFT", ui, "BOTTOMLEFT", panelRight + 6, topY)
    end
end

local function PlaceListRowTooltipBesideList()
    PlaceTooltipBesideFrame(TaskTracker.panel)
end
TaskTracker.PlaceListRowTooltipBesideList = PlaceListRowTooltipBesideList

function TaskTracker.ShowTipBesideFrame(host, title, body)
    if not host or not host.IsShown or not host:IsShown() then return end
    GameTooltip:SetOwner(host, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    GameTooltip:SetText(title or "", 1, 1, 1)
    if type(body) == "string" and body ~= "" then
        GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true)
    end
    GameTooltip:Show()
    PlaceTooltipBesideFrame(host)
end

--- Short tips (insert lines, title bar) use the same park as a task tooltip.
function TaskTracker.BeginTooltipBesideList(anchor)
    SetListRowTooltipOwner(anchor)
    GameTooltip:ClearLines()
end

function TaskTracker.FinishTooltipBesideList()
    GameTooltip:Show()
    PlaceListRowTooltipBesideList()
end

function TaskTracker.RowDebugIdsEnabled()
    return TaskTrackerDB and TaskTrackerDB.debugRowIds == true
end

function TaskTracker.RefreshListRowTooltip(anchor, entry, node)
    if not anchor or (TaskTrackerDB and TaskTrackerDB.showRowTooltips == false) then return end
    local debugOn = TaskTracker.RowDebugIdsEnabled() and IsControlKeyDown and IsControlKeyDown()

    SetListRowTooltipOwner(anchor)
    GameTooltip:ClearLines()

    local title
    if node and node.type == "task" then
        title = node.name or "Task"
    elseif entry then
        title = entry.label or "Activity"
    else
        title = "Row"
    end

    local copiedNative = false
    local kind, id, verifyName = ResolveListRowLinkedId(entry, node)
    if kind == "achievement" and id then
        copiedNative = AppendAchievementTooltipLines(id)
    elseif kind and id and FillScanTooltip(kind, id) then
        if (not verifyName) or ScanTooltipTitleMatches(title) then
            copiedNative = CopyScanTooltipToGameTooltip()
        end
    end
    if scanTip then scanTip:Hide() end
    if not copiedNative then
        GameTooltip:AddLine(title, 1, 0.95, 0.8, false)
        if kind and id then
            local linkedName, detail = LookupLinkedNameAndDetail(kind, id)
            if linkedName and not namesMatch(linkedName, title) then
                GameTooltip:AddLine(linkedName, 1, 1, 1, true)
            end
            if detail and detail ~= "" and not namesMatch(detail, title) and not namesMatch(detail, linkedName) then
                GameTooltip:AddLine(detail, 0.85, 0.85, 0.85, true)
            end
        end
    end

    local builtIn = TaskTracker.GetBuiltInRowTooltipText and TaskTracker.GetBuiltInRowTooltipText(entry, node)
    if type(builtIn) == "string" and builtIn ~= "" then
        GameTooltip:AddLine(" ", 1, 1, 1, false)
        GameTooltip:AddLine(builtIn, 0.85, 0.85, 0.85, true)
    end

    if node and TaskTracker.GetLiveShareOwnerTooltipLine then
        local who = TaskTracker.GetLiveShareOwnerTooltipLine(node)
        if type(who) == "string" and who ~= "" then
            GameTooltip:AddLine(" ", 1, 1, 1, false)
            GameTooltip:AddLine(who, 0.75, 0.75, 0.75, false)
        end
    end

    local reqLines = TaskTracker.GetPurchaseRequirementTooltipLines
        and TaskTracker.GetPurchaseRequirementTooltipLines(entry, node)
    if reqLines and #reqLines > 0 then
        GameTooltip:AddLine(" ", 1, 1, 1, false)
        GameTooltip:AddLine(reqLines.header or "Requirements", 0.75, 0.88, 1, false)
        for i = 1, #reqLines do
            local line = reqLines[i]
            local r, g, b
            if line.met then
                r, g, b = 0.29, 0.87, 0.50
            else
                r, g, b = 0.96, 0.26, 0.21
            end
            if TaskTracker.GetTheme then
                local c = TaskTracker.GetTheme()[line.met and "complete" or "danger"]
                if type(c) == "table" then
                    r, g, b = c[1] or r, c[2] or g, c[3] or b
                end
            end
            GameTooltip:AddLine(line.text, r, g, b, line.wrap ~= false)
        end
    end

    local activeQ = TaskTracker.GetActiveTrackedQuests and TaskTracker.GetActiveTrackedQuests(entry, node)
    if activeQ and #activeQ > 0 then
        GameTooltip:AddLine(" ", 1, 1, 1, false)
        if #activeQ == 1 then
            local q = activeQ[1]
            GameTooltip:AddLine(
                string.format("Current Active Quest: %s (%d)", q.name, q.id),
                1, 0.82, 0, true)
        else
            GameTooltip:AddLine("Current Active Quest:", 1, 0.82, 0, false)
            for i = 1, #activeQ do
                local q = activeQ[i]
                GameTooltip:AddLine(string.format("%s (%d)", q.name, q.id), 1, 0.82, 0, true)
            end
        end
    end

    if TaskTrackerDB and TaskTrackerDB.subtextInTooltip and node and TaskTracker.FormatTaskSubtext then
        local sub = TaskTracker.FormatTaskSubtext(node)
        if type(sub) == "string" and sub ~= "" then
            GameTooltip:AddLine(" ", 1, 1, 1, false)
            GameTooltip:AddLine(sub, 0.75, 0.88, 1, true)
        end
    end

    if node and node.note then
        local nt = tostring(node.note):match("^%s*(.-)%s*$") or ""
        if nt ~= "" and not namesMatch(nt, builtIn) then
            GameTooltip:AddLine(" ", 1, 1, 1, false)
            GameTooltip:AddLine("Note", 0.75, 0.88, 1, false)
            GameTooltip:AddLine(nt, 0.92, 0.92, 0.92, true)
        end
    end

    if debugOn then
        local lines = entry and TaskTracker.GetRegistryDataSourceTooltipLines(entry)
            or (node and TaskTracker.GetTaskDataSourceTooltipLines(node))
        if lines and #lines > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Debug", 1, 0.82, 0, false)
            for i = 1, #lines do
                local line = lines[i]
                if TaskTracker.WithPathArrows then line = TaskTracker.WithPathArrows(line, 12) end
                GameTooltip:AddLine(line, 1, 1, 1, true)
            end
        end
    end

    if TaskTracker.AppendCharacterTooltipLines then
        TaskTracker.AppendCharacterTooltipLines(entry, node)
    end

    if TaskTracker.AppendRowShortcutTooltipLines then
        TaskTracker.AppendRowShortcutTooltipLines(node)
    end

    GameTooltip:Show()
    PlaceListRowTooltipBesideList()
end

function TaskTracker.RegisterListRowTooltip(frame, entry, node)
    if not frame then return end
    frame:SetScript("OnEnter", function(self)
        if TaskTrackerDB and TaskTrackerDB.showRowTooltips == false then return end
        self._ttRowActive = true
        self._ttDebugDown = TaskTracker.RowDebugIdsEnabled() and IsControlKeyDown and IsControlKeyDown()
        TaskTracker.RefreshListRowTooltip(self, entry, node)
        self:SetScript("OnUpdate", function(f)
            if not f._ttRowActive or (TaskTrackerDB and TaskTrackerDB.showRowTooltips == false) then return end
            if TaskTracker.RowDebugIdsEnabled() then
                local a = IsControlKeyDown and IsControlKeyDown()
                if a ~= f._ttDebugDown then
                    f._ttDebugDown = a
                    TaskTracker.RefreshListRowTooltip(f, entry, node)
                    return
                end
            elseif f._ttDebugDown then
                f._ttDebugDown = false
                TaskTracker.RefreshListRowTooltip(f, entry, node)
                return
            end
            PlaceListRowTooltipBesideList()
        end)
    end)
    frame:SetScript("OnLeave", function(self)
        self._ttRowActive = nil
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)
end

-- ─────────────────────────────────────
-- RefreshAll
-- Rebuilds the entire UI with current theme
-- ─────────────────────────────────────
function TaskTracker.RefreshAll()
    if TaskTracker.HideThemeEditor then
        TaskTracker.HideThemeEditor()
    end
    local mainShown = TaskTracker.panel and TaskTracker.panel:IsShown()
    local optsShown = TaskTracker.optionsPanel and TaskTracker.optionsPanel:IsShown()

    if TaskTracker.ResetListVirtualization then
        TaskTracker.ResetListVirtualization()
    end

    if TaskTracker.panel then
        if TaskTracker.SavePanelPosition then
            TaskTracker.SavePanelPosition(TaskTracker.panel)
        end
        TaskTracker.panel:Hide()
        TaskTracker.panel:SetParent(nil)
        TaskTracker.panel = nil
    end

    local optionsScrollY
    if TaskTracker.optionsPanel and TaskTracker.optionsPanel.GetSectionScroll then
        optionsScrollY = TaskTracker.optionsPanel:GetSectionScroll()
    end

    if TaskTracker.optionsPanel then
        TaskTracker.optionsPanel:Hide()
        TaskTracker.optionsPanel:SetParent(nil)
        TaskTracker.optionsPanel = nil
    end

    if TaskTracker.changelogWindow then
        TaskTracker.changelogWindow:Hide()
        TaskTracker.changelogWindow:SetParent(nil)
        TaskTracker.changelogWindow = nil
    end

    -- Rebuild everything (CreateMainPanel restores the saved visual top-left after scale)
    TaskTracker.CreateMainPanel()

    if mainShown and TaskTracker.panel then
        TaskTracker.panel:Show()
        TaskTracker.RefreshList()
    end

    -- Reopen options if it was open, still on the same section and the same scroll.
    if optsShown and TaskTracker.optionsPanel then
        TaskTracker.optionsPanel:Show()
        if optionsScrollY and TaskTracker.optionsPanel.SetSectionScroll then
            TaskTracker.optionsPanel:SetSectionScroll(optionsScrollY)
        end
    end

    if TaskTracker.RefreshOpenHelp then
        TaskTracker.RefreshOpenHelp()
    end
end