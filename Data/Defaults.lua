-- Data/Defaults.lua
-- Key Bindings UI labels (Bindings.xml) plus a small name list used by the gated
-- character-scope migration in Core/CharProgress.lua. BuildDefaultTree does not
-- seed the task list from this table.

TaskTracker = TaskTracker or {}

function TaskTracker.Trim(s)
    if not s then return "" end
    return tostring(s):match("^%s*(.-)%s*$") or ""
end

--- True when Data/Registry.lua finished building the catalog. Prune/sync must not
--- treat a missing catalog as "every registry id was deleted from the game".
function TaskTracker.IsRegistryCatalogReady()
    local reg = TaskTracker.Registry
    local byId = TaskTracker.RegistryByID
    return type(reg) == "table" and #reg > 0 and type(byId) == "table" and next(byId) ~= nil
end

-- Built-in TomTom /way command buttons use this atlas (map pin). Command `icon` may be
-- a texture file id (number) or an atlas name (string).
TaskTracker.WAY_COMMAND_ATLAS = "TaxiNode_Neutral"
TaskTracker.DEFAULT_COMMAND_ICON = 134400

function TaskTracker.IsWaySlashCommand(command)
    local s = TaskTracker.Trim(command):lower()
    return s:find("^/way%s") ~= nil or s == "/way"
end

local function publicFileId(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    local n = tonumber(v)
    if n and n > 0 then return math.floor(n) end
    return nil
end

local function ensureItemIconWatch()
    if TaskTracker._ttItemIconWatch then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function(_, _, itemId)
        local want = TaskTracker._ttItemIconWant
        if issecretvalue and issecretvalue(itemId) then
            if TaskTracker.RefreshOpenIconPickerCommand then
                TaskTracker.RefreshOpenIconPickerCommand()
            end
            return
        end
        itemId = tonumber(itemId)
        if want and itemId and want[itemId] then
            want[itemId] = nil
            if TaskTracker.MarkListPaintDirty then TaskTracker.MarkListPaintDirty() end
            if TaskTracker.RefreshList then TaskTracker.RefreshList() end
        end
        if TaskTracker.RefreshOpenIconPickerCommand then
            TaskTracker.RefreshOpenIconPickerCommand()
        end
    end)
    TaskTracker._ttItemIconWatch = f
    TaskTracker._ttItemIconWant = TaskTracker._ttItemIconWant or {}
end

--- File id for a `/use item:123` command, once the client knows the item. Otherwise nil.
function TaskTracker.ItemIconFileFromCommand(command)
    local id = tonumber(tostring(command or ""):match("[Ii]tem:(%d+)"))
    if not id or id <= 0 then return nil end
    if issecretvalue and issecretvalue(id) then return nil end
    local file
    if C_Item and C_Item.GetItemIconByID then
        local ok, v = pcall(C_Item.GetItemIconByID, id)
        if ok then file = v end
    end
    if (type(file) ~= "number" or file <= 0) and GetItemIcon then
        local ok, v = pcall(GetItemIcon, id)
        if ok then file = v end
    end
    local fileId = publicFileId(file)
    if fileId then return fileId end
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
        ensureItemIconWatch()
        TaskTracker._ttItemIconWant[id] = true
    end
    return nil
end

local SLASH_ICON_KIND = {
    cast = "spell",
    castsequence = "spell",
    castrandom = "spell",
    use = "item",
    userandom = "item",
    equip = "item",
    equipslot = "item",
}

local function slashAction(line)
    line = TaskTracker.Trim(line or "")
    if line == "" or line:sub(1, 1) == "#" then return nil end
    local cmd, rest = line:match("^/([%a]+)%s*(.*)$")
    if not cmd then return nil end
    cmd = cmd:lower()
    local kind = SLASH_ICON_KIND[cmd]
    if not kind then return nil end
    rest = rest or ""
    if cmd == "castsequence" then
        rest = rest:gsub("^reset=%S+%s*", "")
        rest = rest:match("^[^,;]+") or rest
    elseif cmd == "castrandom" or cmd == "userandom" then
        rest = rest:match("^[^,;]+") or rest
    elseif cmd == "equipslot" then
        rest = rest:gsub("^%d+%s*", "")
    end
    rest = rest:gsub("%b[]", " ")
    rest = rest:match("^[^;]+") or rest
    rest = TaskTracker.Trim(rest:gsub("%s*%b()%s*$", ""))
    if rest == "" then return nil end
    return kind, rest
end

local function spellIconFile(token)
    if token == nil or (issecretvalue and issecretvalue(token)) then return nil end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, token)
    if not ok or type(info) ~= "table" then return nil end
    return publicFileId(info.iconID) or publicFileId(info.originalIconID)
end

-- Name lookup is case-sensitive and only sees the spellbook. Cache one walk so /cast bladestorm still hits Bladestorm.
local spellNameIconCache
local function spellIconFromBook(wantLower)
    if spellNameIconCache and spellNameIconCache[wantLower] then
        return spellNameIconCache[wantLower]
    end
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo) then
        return nil
    end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local okN, nLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if not okN or type(nLines) ~= "number" or nLines < 1 then return nil end
    local cache = spellNameIconCache or {}
    spellNameIconCache = cache
    for i = 1, nLines do
        local okL, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
        if okL and type(line) == "table" then
            local offset = tonumber(line.itemIndexOffset) or 0
            local num = tonumber(line.numSpellBookItems) or 0
            for j = offset + 1, offset + num do
                local okI, info = pcall(C_SpellBook.GetSpellBookItemInfo, j, bank)
                if okI and type(info) == "table" then
                    local spellName = info.name
                    if type(spellName) ~= "string" or spellName == "" then
                        local id = info.spellID or info.actionID
                        if id and not (issecretvalue and issecretvalue(id)) and C_Spell and C_Spell.GetSpellName then
                            local okS, n = pcall(C_Spell.GetSpellName, id)
                            if okS and type(n) == "string" then spellName = n end
                        end
                    end
                    if type(spellName) == "string" and spellName ~= "" then
                        local file = publicFileId(info.iconID)
                        if not file then
                            local id = info.spellID or info.actionID
                            if id and not (issecretvalue and issecretvalue(id)) then
                                file = spellIconFile(id)
                            end
                        end
                        if file then cache[spellName:lower()] = file end
                    end
                end
            end
        end
    end
    return cache[wantLower]
end

local function spellIconByName(name)
    if not name or name == "" then return nil end
    local file = spellIconFile(name)
    if file then return file end
    local titled = name:gsub("(%a)([%w']*)", function(a, rest)
        return a:upper() .. rest:lower()
    end)
    if titled ~= name then
        file = spellIconFile(titled)
        if file then return file end
    end
    return spellIconFromBook(name:lower())
end

local function itemIconByName(name)
    if not name or name == "" then return nil end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, itemID, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, name)
        if ok then
            local file = publicFileId(icon)
            if file then return file end
            local id = publicFileId(itemID)
            if id and TaskTracker.ItemIconFileFromCommand then
                return TaskTracker.ItemIconFileFromCommand("/use item:" .. id)
            end
        end
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, info = pcall(C_Item.GetItemInfo, name)
        if ok and type(info) == "table" then
            local file = publicFileId(info.iconFileID or info.icon)
            if file then return file end
        end
    end
    if GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, texture = pcall(GetItemInfo, name)
        if ok then
            local file = publicFileId(texture)
            if file then return file end
        end
    end
    ensureItemIconWatch()
    return nil
end

local function plainSlashName(token)
    local s = tostring(token or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("|H[^|]-|h", "")
    s = s:gsub("[%[%]]", "")
    s = TaskTracker.Trim(s)
    if s:match("^[Ii]tem:%d+$") or s:match("^[Ss]pell:%d+$") or tonumber(s) then
        return ""
    end
    return s
end

local function iconForSlashAction(kind, token)
    local itemId = tonumber(token:match("|Hitem:(%d+)")) or tonumber(token:match("[Ii]tem:(%d+)"))
    local spellId = tonumber(token:match("|Hspell:(%d+)")) or tonumber(token:match("[Ss]pell:(%d+)"))
    local bare = tonumber(token)
    local name = plainSlashName(token)
    if kind == "spell" then
        if spellId then return spellIconFile(spellId) end
        if itemId and TaskTracker.ItemIconFileFromCommand then
            return TaskTracker.ItemIconFileFromCommand("/use item:" .. itemId)
        end
        if bare and bare > 19 then
            local file = spellIconFile(bare)
            if file then return file end
        end
        local file = spellIconByName(name)
        if file then return file end
        return itemIconByName(name)
    end
    if itemId and TaskTracker.ItemIconFileFromCommand then
        return TaskTracker.ItemIconFileFromCommand("/use item:" .. itemId)
    end
    if spellId then return spellIconFile(spellId) end
    if bare and bare >= 1 and bare <= 19 and GetInventoryItemID then
        local ok, id = pcall(GetInventoryItemID, "player", bare)
        if ok then
            id = publicFileId(id)
            if id and TaskTracker.ItemIconFileFromCommand then
                local file = TaskTracker.ItemIconFileFromCommand("/use item:" .. id)
                if file then return file end
            end
        end
    end
    local file = itemIconByName(name)
    if file then return file end
    if bare then
        file = spellIconFile(bare)
        if file then return file end
        if TaskTracker.ItemIconFileFromCommand then
            return TaskTracker.ItemIconFileFromCommand("/use item:" .. bare)
        end
    end
    return spellIconByName(name)
end

local SHOWTOOLTIP_PROBE = "TTIconProbeX"

local function iconFromMacroSpell(a, c)
    if a == nil or (issecretvalue and issecretvalue(a)) then return nil end
    if type(a) == "number" then
        local file = spellIconFile(a)
        if file then return file end
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, tex = pcall(C_Spell.GetSpellTexture, a)
            if ok then return publicFileId(tex) end
        end
        return nil
    end
    if type(c) == "number" and not (issecretvalue and issecretvalue(c)) then
        local file = spellIconFile(c)
        if file then return file end
    end
    if type(a) == "string" then
        return spellIconByName(a)
    end
    return nil
end

--- Same icon a macro would show. Prepends #showtooltip when the text has none,
--- asks the macro engine, then deletes the probe macro.
function TaskTracker.IconFileFromShowtooltip(text)
    if type(text) ~= "string" then return nil end
    text = TaskTracker.Trim(text)
    if text == "" then return nil end
    if InCombatLockdown and InCombatLockdown() then return nil end
    if not (CreateMacro and GetMacroIndexByName and GetMacroSpell and DeleteMacro) then
        return nil
    end
    local body = text
    if not body:lower():find("#show", 1, true) then
        body = "#showtooltip\n" .. body
    end
    if #body > 255 then
        body = body:sub(1, 255)
    end
    local file
    pcall(function()
        local idx = GetMacroIndexByName(SHOWTOOLTIP_PROBE)
        if not idx or idx == 0 then
            local globalCount, charCount = 120, 18
            if GetNumMacros then
                globalCount, charCount = GetNumMacros()
            end
            local created
            if (tonumber(charCount) or 18) < 18 then
                created = CreateMacro(SHOWTOOLTIP_PROBE, "INV_MISC_QUESTIONMARK", body, true)
            elseif (tonumber(globalCount) or 120) < 120 then
                created = CreateMacro(SHOWTOOLTIP_PROBE, "INV_MISC_QUESTIONMARK", body, false)
            end
            idx = (type(created) == "number" and created > 0) and created or GetMacroIndexByName(SHOWTOOLTIP_PROBE)
        elseif EditMacro then
            EditMacro(idx, SHOWTOOLTIP_PROBE, "INV_MISC_QUESTIONMARK", body)
        end
        if not idx or idx == 0 then return end
        local a, _, c = GetMacroSpell(idx)
        file = iconFromMacroSpell(a, c)
        if not file and GetMacroItem then
            local itemName, itemLink = GetMacroItem(idx)
            local id = type(itemLink) == "string" and tonumber(itemLink:match("item:(%d+)"))
            if id and TaskTracker.ItemIconFileFromCommand then
                file = TaskTracker.ItemIconFileFromCommand("/use item:" .. id)
            elseif type(itemName) == "string" and itemName ~= "" then
                file = itemIconByName(itemName)
            end
        end
    end)
    if GetMacroIndexByName(SHOWTOOLTIP_PROBE) ~= 0 then
        pcall(DeleteMacro, SHOWTOOLTIP_PROBE)
    end
    return file
end

--- File id from the first /cast, /use, /equip, or similar line. Nil when the client has no icon yet.
function TaskTracker.IconFileFromSlashCommand(text)
    if type(text) ~= "string" or text == "" then return nil end
    for line in text:gmatch("[^\r\n]+") do
        local kind, token = slashAction(line)
        if kind and token then
            local file = iconForSlashAction(kind, token)
            if file then return file end
        end
    end
    return nil
end

--- Keep atlas names; coerce numbers; default /way buttons to WAY_COMMAND_ATLAS.
function TaskTracker.NormalizeCommandIcon(icon, command)
    if type(icon) == "string" then
        local s = TaskTracker.Trim(icon)
        if s ~= "" then return s end
        icon = nil
    else
        local n = tonumber(icon)
        if n then icon = n end
    end
    local fallback = TaskTracker.DEFAULT_COMMAND_ICON or 134400
    if (icon == nil or icon == fallback) and TaskTracker.IsWaySlashCommand(command) then
        return TaskTracker.WAY_COMMAND_ATLAS or "TaxiNode_Neutral"
    end
    return icon or fallback
end

function TaskTracker.DeepCopy(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local c = {}
    seen[t] = c
    for k, v in pairs(t) do
        if type(v) == "table" then
            c[k] = TaskTracker.DeepCopy(v, seen)
        else
            c[k] = v
        end
    end
    return c
end

-- Key Bindings UI labels (Bindings.xml → TASKTRACKER_TOGGLE). Do not list Bindings.xml in .toc — client loads it from the addon folder.
BINDING_HEADER_TASKTRACKER = "Task Tracker"
BINDING_NAME_TASKTRACKER_TOGGLE = "Toggle Task Tracker window"

TaskTracker.Defaults = {
    daily = {
        { name = "World Quests" },
        { name = "Dungeon Daily" },
        { name = "Profession Daily" },
    },
    weekly = {
        { name = "Raid" },
        { name = "Mythic+" },
        -- Once per account per week (warband / shared reward).
        { name = "Great Vault", accountWide = true },
        { name = "World Boss" },
    },
}