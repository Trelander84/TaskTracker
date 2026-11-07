-- Core/Professions.lua
-- Player profession detection and catch-up knowledge display (Midnight profession module).

TaskTracker = TaskTracker or {}

local learnedCache = nil
local learnedCacheAt = 0
local LEARNED_CACHE_TTL = 30
local sessionProfApiReady = false

local function normalizeProfessionName(name)
    if type(name) ~= "string" then return nil end
    return name:lower():gsub("%s+", "")
end

local function catalogKeyFromProfessionName(name)
    local n = normalizeProfessionName(name)
    if not n or not TaskTracker.ProfessionCatalog then return nil end
    for key, def in pairs(TaskTracker.ProfessionCatalog) do
        if normalizeProfessionName(def.label) == n then
            return key
        end
    end
    return nil
end

local function addProfessionNameToSet(set, name)
    local key = catalogKeyFromProfessionName(name)
    if key then set[key] = true end
end

local function charLearnedProfRoot()
    local db = TaskTrackerDB
    if not db then return nil end
    if type(db.charLearnedProfessions) ~= "table" then
        db.charLearnedProfessions = {}
    end
    return db.charLearnedProfessions
end

local function setsEqual(a, b)
    if not a or not b then return false end
    for k in pairs(a) do
        if not b[k] then return false end
    end
    for k in pairs(b) do
        if not a[k] then return false end
    end
    return true
end

local MAX_PRIMARY_PROFESSIONS = 2

local function countSet(set)
    local n = 0
    for _ in pairs(set or {}) do
        n = n + 1
    end
    return n
end

local function loadSavedLearnedSet(charKey)
    if not charKey then return nil end
    local root = charLearnedProfRoot()
    local entry = root and root[charKey]
    if type(entry) ~= "table" then return nil end
    local set = {}
    for _, key in ipairs(entry) do
        if type(key) == "string" and key ~= "" then
            set[key] = true
        end
    end
    if not next(set) then
        for key, v in pairs(entry) do
            if type(key) == "string" and key ~= "" and v == true then
                set[key] = true
            end
        end
    end
    if not next(set) then return nil end
    if countSet(set) > MAX_PRIMARY_PROFESSIONS then
        return nil
    end
    return set
end

function TaskTracker.SaveLearnedProfessionsForChar(charKey, set)
    if not charKey or type(set) ~= "table" then return end
    if countSet(set) > MAX_PRIMARY_PROFESSIONS then return end
    if not next(set) then
        local existing = loadSavedLearnedSet(charKey)
        if existing and next(existing) then
            return
        end
    end
    local root = charLearnedProfRoot()
    if not root then return end
    local keys = {}
    for key in pairs(set) do
        if type(key) == "string" and key ~= "" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    root[charKey] = keys
end

local function scanLearnedFromClassicAPI()
    local set = {}
    if GetProfessions and GetProfessionInfo then
        local p1, p2 = GetProfessions()
        for _, idx in ipairs({ p1, p2 }) do
            if idx then
                local ok, name, _, _, _, _, _, _, _, _, skillLineName = pcall(GetProfessionInfo, idx)
                if ok then
                    addProfessionNameToSet(set, name)
                    addProfessionNameToSet(set, skillLineName)
                end
            end
        end
    end
    return set
end

local function tradeSkillLineLooksLearned(info)
    if type(info) ~= "table" then return false end
    if info.learned == false then return false end
    if info.learned == true then return true end
    return (tonumber(info.skillLevel) or 0) > 0
end

local function scanLearnedFromTradeSkillUI()
    local set = {}
    if not C_TradeSkillUI or not C_TradeSkillUI.GetAllProfessionTradeSkillLines then
        return set
    end
    local ok, lines = pcall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if not ok or type(lines) ~= "table" then return set end
    for _, lineID in ipairs(lines) do
        local ok2, info = pcall(function()
            if C_TradeSkillUI.GetProfessionInfoBySkillLine then
                return C_TradeSkillUI.GetProfessionInfoBySkillLine(lineID)
            end
            if C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                return C_TradeSkillUI.GetProfessionInfoBySkillLineID(lineID)
            end
        end)
        if ok2 and tradeSkillLineLooksLearned(info) then
            addProfessionNameToSet(set, info.professionName)
            addProfessionNameToSet(set, info.parentProfessionName)
            addProfessionNameToSet(set, info.profession)
        end
    end
    return set
end

local function scanLearnedFromAPI(includeTradeSkillUI)
    local set = scanLearnedFromClassicAPI()
    if includeTradeSkillUI then
        local tsSet = scanLearnedFromTradeSkillUI()
        for key in pairs(tsSet) do
            set[key] = true
        end
    end
    if countSet(set) > MAX_PRIMARY_PROFESSIONS then
        set = scanLearnedFromClassicAPI()
    end
    return set
end

function TaskTracker.InvalidateLearnedProfessionsCache()
    learnedCache = nil
    learnedCacheAt = 0
end

function TaskTracker.GetLearnedProfessionKeys()
    local now = (GetTime and GetTime()) or 0
    if learnedCache and (now - learnedCacheAt) < LEARNED_CACHE_TTL then
        return learnedCache
    end

    local apiSet = scanLearnedFromAPI(false)
    local charKey = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    local savedSet = loadSavedLearnedSet(charKey)
    local effective

    if next(apiSet) then
        sessionProfApiReady = true
        effective = apiSet
        if charKey and (not savedSet or not setsEqual(apiSet, savedSet)) then
            TaskTracker.SaveLearnedProfessionsForChar(charKey, apiSet)
        end
    elseif savedSet then
        effective = savedSet
    elseif sessionProfApiReady then
        effective = apiSet
        if charKey and not savedSet then
            TaskTracker.SaveLearnedProfessionsForChar(charKey, apiSet)
        end
    else
        effective = apiSet
    end

    learnedCache = effective
    learnedCacheAt = now
    return effective
end

function TaskTracker.IsProfessionLearned(professionKey)
    if not professionKey then return false end
    local learned = TaskTracker.GetLearnedProfessionKeys()
    return learned[professionKey] == true
end

--- Saved row for this character in charLearnedProfessions (even an empty list after opening the profession UI).
function TaskTracker.CharHasProfessionHistory(charKey)
    charKey = charKey or (TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey())
    if not charKey then return false end
    local root = charLearnedProfRoot()
    return root and root[charKey] ~= nil
end

--- True when this character has never opened the profession UI (saved on TRADE_SKILL_LIST_UPDATE).
function TaskTracker.ShouldShowProfessionsOpenHint()
    local charKey = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if not charKey then return false end
    if TaskTracker.CharHasProfessionHistory(charKey) then return false end
    local learned = TaskTracker.GetLearnedProfessionKeys()
    for _ in pairs(learned) do
        return false
    end
    return true
end

function TaskTracker.GetProfessionsGroupDisplayName(baseName)
    local name = baseName or "Professions"
    if TaskTracker.ShouldShowProfessionsOpenHint() then
        return name .. " (Open a Profession to load)"
    end
    return name
end

function TaskTracker.ProfessionRegistryEntryVisible(entry)
    if not entry or not entry.professionKey then return true end
    return TaskTracker.IsProfessionLearned(entry.professionKey)
end

local function professionCatalogKeyForGroup(node)
    if not node or node.type ~= "group" then return nil end
    local pkey = node.moduleGroupKey and node.moduleGroupKey:match("^profession_(.+)$")
    if pkey then return pkey end
    if not node.name or not TaskTracker.ProfessionCatalog then return nil end
    for key, def in pairs(TaskTracker.ProfessionCatalog) do
        if def.label == node.name then
            return key
        end
    end
    return nil
end

--- Built-in profession subsection (Alchemy, Mining, …) under the Professions group.
function TaskTracker.ProfessionModuleSubgroupVisible(node)
    if not node or node.type ~= "group" then return true end
    local pkey = professionCatalogKeyForGroup(node)
    if not pkey then return true end
    return TaskTracker.IsProfessionLearned(pkey)
end

function TaskTracker.GetProfessionCatchupRemaining(currencyId)
    currencyId = tonumber(currencyId)
    if not currencyId or not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then
        return nil
    end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyId)
    if not ok or type(info) ~= "table" then return nil end
    local maxQ, earned = info.maxQuantity, info.totalEarned
    if issecretvalue and (issecretvalue(maxQ) or issecretvalue(earned)) then
        return nil
    end
    maxQ = tonumber(maxQ) or 0
    earned = tonumber(earned) or 0
    return math.max(0, maxQ - earned)
end

function TaskTracker.FormatProfessionCatchupRow(entry)
    if not entry or entry.type ~= "profession_catchup" then return "-" end
    local rem = TaskTracker.GetProfessionCatchupRemaining(entry.catchupCurrencyId)
    if rem == nil then return "-" end
    if rem <= 0 then return "0" end
    return tostring(rem)
end

local function pruneCorruptSavedProfessions(charKey)
    if not charKey then return end
    local root = charLearnedProfRoot()
    local entry = root and root[charKey]
    if type(entry) ~= "table" then return end
    local set = {}
    for _, key in ipairs(entry) do
        if type(key) == "string" and key ~= "" then
            set[key] = true
        end
    end
    if countSet(set) <= MAX_PRIMARY_PROFESSIONS then return end
    local classic = scanLearnedFromClassicAPI()
    if next(classic) then
        TaskTracker.SaveLearnedProfessionsForChar(charKey, classic)
    else
        root[charKey] = nil
    end
end

local function applyLearnedProfessionsTreeSync(resetSession)
    if resetSession then
        sessionProfApiReady = false
    end
    local charKey = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    pruneCorruptSavedProfessions(charKey)
    TaskTracker.InvalidateLearnedProfessionsCache()
    local hadLearned = TaskTracker._ttHadAnyLearnedProfession
    local learned = TaskTracker.GetLearnedProfessionKeys()
    local any = false
    for _ in pairs(learned) do any = true break end
    TaskTracker._ttHadAnyLearnedProfession = any
    if TaskTrackerDB and TaskTrackerDB.tree and TaskTracker.EnsureProfessionsGroupInTree then
        TaskTracker.EnsureProfessionsGroupInTree(TaskTrackerDB.tree)
    end
    local showHint = TaskTracker.ShouldShowProfessionsOpenHint and TaskTracker.ShouldShowProfessionsOpenHint()
    if TaskTracker._ttProfessionsOpenHintShown ~= showHint then
        TaskTracker._ttProfessionsOpenHintShown = showHint
        if TaskTracker.MarkListPaintDirty then
            TaskTracker.MarkListPaintDirty()
        end
    end
    if (hadLearned == nil or any ~= hadLearned) and TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
end

function TaskTracker.RefreshLearnedProfessionsTree()
    applyLearnedProfessionsTreeSync(false)
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

function TaskTracker.SyncLearnedProfessionsOnEnterWorld()
    applyLearnedProfessionsTreeSync(true)
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

local function scheduleLearnedProfessionSyncRetries()
    TaskTracker._ttProfRetryTimers = TaskTracker._ttProfRetryTimers or {}
    local timers = TaskTracker._ttProfRetryTimers
    for i = 1, #timers do
        local t = timers[i]
        if t and t.Cancel then t:Cancel() end
    end
    wipe(timers)
    for _, delay in ipairs({ 0.75, 2.0 }) do
        timers[#timers + 1] = C_Timer.NewTimer(delay, function()
            if not IsPlayerInWorld or not IsPlayerInWorld() then return end
            if TaskTracker.RefreshLearnedProfessionsTree then
                TaskTracker.RefreshLearnedProfessionsTree()
            end
        end)
    end
end

function TaskTracker.PersistLearnedProfessionsForCurrentChar()
    local charKey = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if not charKey then return end
    local set = learnedCache
    if not set then
        TaskTracker.InvalidateLearnedProfessionsCache()
        set = TaskTracker.GetLearnedProfessionKeys()
    end
    if set then
        TaskTracker.SaveLearnedProfessionsForChar(charKey, set)
    end
end

function TaskTracker.OnTradeSkillListUpdate()
    TaskTracker.InvalidateLearnedProfessionsCache()
    local charKey = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    local apiSet = scanLearnedFromAPI(true)
    if countSet(apiSet) > MAX_PRIMARY_PROFESSIONS then
        apiSet = scanLearnedFromClassicAPI()
    end
    if charKey and next(apiSet) then
        TaskTracker.SaveLearnedProfessionsForChar(charKey, apiSet)
    end
    applyLearnedProfessionsTreeSync(false)
    -- Record first profession UI open for the hint, without clearing saved professions.
    local charKey = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if charKey and TaskTracker.CharHasProfessionHistory and not TaskTracker.CharHasProfessionHistory(charKey) then
        local set = TaskTracker.GetLearnedProfessionKeys() or {}
        TaskTracker.SaveLearnedProfessionsForChar(charKey, set)
        TaskTracker.InvalidateLearnedProfessionsCache()
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    ev:RegisterEvent("PLAYER_LOGOUT")
    -- Core TaskTracker.lua defers PLAYER_ENTERING_WORLD registration (~1s) and can miss the
    -- first login tick; listen here so saved professions populate before the profession UI opens.
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_LOGOUT" then
            if TaskTracker.PersistLearnedProfessionsForCurrentChar then
                TaskTracker.PersistLearnedProfessionsForCurrentChar()
            end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            local isInitialLogin, isReloadingUi = ...
            local firstPew = not self._ttPewSeen
            self._ttPewSeen = true
            C_Timer.After(0, function()
                if TaskTracker.SyncLearnedProfessionsOnEnterWorld then
                    TaskTracker.SyncLearnedProfessionsOnEnterWorld()
                end
            end)
            if firstPew or isInitialLogin or isReloadingUi then
                scheduleLearnedProfessionSyncRetries()
            end
            return
        end
        if self._ttProfDebounce then
            self._ttProfDebounce:Cancel()
        end
        self._ttProfDebounce = C_Timer.NewTimer(0.5, function()
            self._ttProfDebounce = nil
            if TaskTracker.OnTradeSkillListUpdate then
                TaskTracker.OnTradeSkillListUpdate()
            end
        end)
    end)
end
