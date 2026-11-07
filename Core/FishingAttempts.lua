-- Core/FishingAttempts.lua
-- Auto-increment Collectable tasks for catalog entries with fishingOpenWaterMapIds / fishingCountMidnightPools.
-- Counts on UNIT_SPELLCAST_SENT for the player (unit is event arg1; spellId is 3rd vararg: target, castGUID, spellID).
-- fishingOpenWaterMapIds = uiMap **roots** (e.g. Voidstorm 2405): open water counts if player map equals a root
-- or has that root in its parent chain (subzones included without listing each id).

TaskTracker = TaskTracker or {}

--- Known Fishing spell IDs (retail varies by rank / book). /tt fishdebug logs spellId on each SENT.
local FISHING_SPELL_WHITELIST = {
    [7620] = true,   -- classic book
    [7731] = true,
    [7732] = true,
    [18248] = true,
    [33095] = true,
    [51294] = true,
    [88868] = true,
    [131474] = true, -- common retail
    [131476] = true,
    [330092] = true,
    [330093] = true,
    [330094] = true,
    [330095] = true,
    [377612] = true,
    [377613] = true,
    [377615] = true,
}

local lastFishingCountAt = 0

--- Spells confirmed not "Fishing" via C_Spell (avoids repeated API work on combat spam).
local fishSpellNegativeHit = {}
local fishSpellNegativeCount = 0
local FISH_SPELL_NEGATIVE_MAX = 400

local function fishSpellNegativeRemember(spellId)
    fishSpellNegativeHit[spellId] = true
    fishSpellNegativeCount = fishSpellNegativeCount + 1
    if fishSpellNegativeCount >= FISH_SPELL_NEGATIVE_MAX then
        fishSpellNegativeHit = {}
        fishSpellNegativeCount = 0
    end
end

--- One-shot: catalog defines at least one fishing-capable collectable (no tree walk).
local catalogMightHaveFishingRules

local function ensureCatalogMightHaveFishingRules()
    if catalogMightHaveFishingRules ~= nil then
        return catalogMightHaveFishingRules
    end
    catalogMightHaveFishingRules = false
    local exps = TaskTracker.GetCollectableExpansionList and TaskTracker.GetCollectableExpansionList() or {}
    local cats = TaskTracker.GetCollectableCategories and TaskTracker.GetCollectableCategories() or {}
    for _, ex in ipairs(exps) do
        if ex and ex.id then
            for _, c in ipairs(cats) do
                if c and c.id then
                    local list = TaskTracker.GetCollectableEntries and TaskTracker.GetCollectableEntries(ex.id, c.id) or {}
                    for _, ent in ipairs(list) do
                        if TaskTracker.CollectableEntryHasFishingRules(ent) then
                            catalogMightHaveFishingRules = true
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

--- After editing `CollectableCatalog` fishing fields at runtime (without `/reload`); clears the cached catalog gate.
function TaskTracker.InvalidateFishingCatalogMightCache()
    catalogMightHaveFishingRules = nil
end

--- All uiMap ids from `mapId` up the parent chain (inclusive). Built once per fishing hit.
local function buildMapAncestorSet(mapId)
    local set = {}
    mapId = tonumber(mapId)
    local m = mapId
    for _ = 1, 48 do
        if not m or m <= 0 then break end
        set[m] = true
        if not C_Map or not C_Map.GetMapInfo then break end
        local ok, info = pcall(C_Map.GetMapInfo, m)
        if not ok or type(info) ~= "table" then break end
        m = tonumber(info.parentMapID)
    end
    return set
end

--- Lowest map id (walking up from `startId`) that lies on every seed's ancestor chain (LCA of all seeds).
local function mapLcaOfSeeds(seedIds)
    if type(seedIds) ~= "table" or #seedIds == 0 then return nil end
    if not C_Map or not C_Map.GetMapInfo then return nil end

    local function chainList(startId)
        local out = {}
        local m = tonumber(startId)
        for _ = 1, 48 do
            if not m or m <= 0 then break end
            out[#out + 1] = m
            local ok, info = pcall(C_Map.GetMapInfo, m)
            if not ok or type(info) ~= "table" then break end
            m = tonumber(info.parentMapID)
        end
        return out
    end

    local chains = {}
    for _, sid in ipairs(seedIds) do
        chains[#chains + 1] = chainList(sid)
    end
    if #chains == 0 then return nil end

    for _, candidate in ipairs(chains[1]) do
        local inAll = true
        for i = 2, #chains do
            local found = false
            for _, id in ipairs(chains[i]) do
                if id == candidate then
                    found = true
                    break
                end
            end
            if not found then
                inAll = false
                break
            end
        end
        if inAll then
            return candidate
        end
    end
    return nil
end

--- uiMap roots from a catalog entry (`fishingOpenWaterMapIds`).
local function fishingOpenWaterRootsFromEntry(ent)
    local out = {}
    if ent and type(ent.fishingOpenWaterMapIds) == "table" then
        for _, id in ipairs(ent.fishingOpenWaterMapIds) do
            local n = tonumber(id)
            if n and n > 0 then
                out[#out + 1] = n
            end
        end
    end
    return out
end

--- [entryId] = LCA uiMapID or false (cached). Used for pool rule: map must lie under this ancestor.
local lcaByEntryId = {}

local function poolAncestorForEntry(ent)
    if not ent or ent.id == nil or ent.id == "" then return nil end
    local key = tostring(ent.id)
    if lcaByEntryId[key] ~= nil then
        local v = lcaByEntryId[key]
        return (v ~= false) and v or nil
    end
    local seeds = fishingOpenWaterRootsFromEntry(ent)
    if #seeds == 0 then
        lcaByEntryId[key] = false
        return nil
    end
    local lca = mapLcaOfSeeds(seeds)
    lcaByEntryId[key] = lca or false
    return lca
end

function TaskTracker.InvalidateFishingMidnightLcaCache()
    lcaByEntryId = {}
    fishSpellNegativeHit = {}
    fishSpellNegativeCount = 0
end

local function guidLooksLikeGameObject(guid)
    return type(guid) == "string" and strsub(guid, 1, 11) == "GameObject-"
end

local function playerMapUnderAnyOpenWaterRootFromSet(ancestorSet, ent)
    for _, rootId in ipairs(fishingOpenWaterRootsFromEntry(ent)) do
        local r = tonumber(rootId)
        if r and r > 0 and ancestorSet[r] then
            return true
        end
    end
    return false
end

local function isFishingSpell(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then return false end
    if FISHING_SPELL_WHITELIST[spellId] then return true end
    if fishSpellNegativeHit[spellId] then return false end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
        if not ok then return false end
        if type(info) ~= "table" or not info.name then
            -- Spell book not ready yet — do not negative-cache empty lookups.
            return false
        end
        local n = strlower(tostring(info.name))
        if n == "fishing" then return true end
    end
    fishSpellNegativeRemember(spellId)
    return false
end

local function spellDebugName(spellId)
    spellId = tonumber(spellId)
    if not spellId then return "" end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
        if ok and type(info) == "table" and info.name then
            return tostring(info.name)
        end
    end
    return ""
end

local function openWaterSetFromEntry(ent)
    local s = {}
    local ow = ent and ent.fishingOpenWaterMapIds
    if type(ow) == "table" then
        for _, id in ipairs(ow) do
            local n = tonumber(id)
            if n and n > 0 then s[n] = true end
        end
    end
    return s
end

--- Per catalog entry: open water = under any `fishingOpenWaterMapIds` root, not a pool cast; pool = GO hint + under LCA of those roots.
--- `ancestorSet` from `buildMapAncestorSet(mapId)` (one build per cast).
local function classifyFishingAttemptForEntry(ent, poolHintGameObject, ancestorSet)
    if not ent or not ancestorSet then return nil end

    if playerMapUnderAnyOpenWaterRootFromSet(ancestorSet, ent) and not poolHintGameObject then
        return "open_water"
    end

    if poolHintGameObject and ent.fishingCountMidnightPools == true then
        local anc = poolAncestorForEntry(ent)
        if anc and ancestorSet[anc] then
            return "midnight_pool"
        end
    end

    return nil
end

local function shouldIncrementEntryForKind(ent, kind)
    if kind == "open_water" then
        local ow = openWaterSetFromEntry(ent)
        return next(ow) ~= nil
    end
    if kind == "midnight_pool" then
        return ent.fishingCountMidnightPools == true
    end
    return false
end

local function collectableNodeShouldCountFish(node, kind)
    if not node or node.type ~= "task" or not TaskTracker.IsAdvancedTask(node) then return false end
    if node.advanced.type ~= "collectable" then return false end
    if node.taskUserValue ~= nil or node.doneOverride ~= nil then return false end

    local a = node.advanced
    local ent = TaskTracker.GetCollectableEntry
        and TaskTracker.GetCollectableEntry(a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
    if not TaskTracker.CollectableEntryHasFishingRules(ent) then return false end
    if not shouldIncrementEntryForKind(ent, kind) then return false end

    local cat = tostring(a.collectableCategory or "mount"):lower()
    if TaskTracker.IsCatalogCollectableOwned and TaskTracker.IsCatalogCollectableOwned(ent, cat) then
        return false
    end

    local cap = math.max(1, tonumber(node.taskMax) or 1)
    local questPart = math.max(0, tonumber(a.collectableAutoCount) or 0)
    local fishPart = math.max(0, tonumber(a.collectableFishAttempts) or 0)
    if questPart + fishPart >= cap then return false end

    return true
end

function TaskTracker.ApplyFishingForCast(mapId, poolHintGO)
    if not IsPlayerInWorld() then return end

    mapId = tonumber(mapId)
    if not mapId or mapId <= 0 then return end

    local ancestorSet = buildMapAncestorSet(mapId)
    local kindByEntryKey = {}

    local any = false
    TaskTracker.WalkTree(function(node)
        if node.type ~= "task" or not TaskTracker.IsAdvancedTask(node) then return end
        if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then return end
        if node.advanced.type ~= "collectable" then return end

        local a = node.advanced
        local ent = TaskTracker.GetCollectableEntry
            and TaskTracker.GetCollectableEntry(a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
        if not TaskTracker.CollectableEntryHasFishingRules(ent) then return end

        local eKey = tostring(a.collectableExpansion or "")
            .. "\31" .. tostring(a.collectableCategory or "")
            .. "\31" .. tostring(a.collectableEntryId or "")
        local cachedKind = kindByEntryKey[eKey]
        local kind
        if cachedKind == nil then
            kind = classifyFishingAttemptForEntry(ent, poolHintGO, ancestorSet)
            kindByEntryKey[eKey] = (kind ~= nil) and kind or false
        elseif cachedKind == false then
            kind = nil
        else
            kind = cachedKind
        end
        if not kind then return end

        if not collectableNodeShouldCountFish(node, kind) then return end

        a.collectableFishAttempts = math.max(0, math.floor(tonumber(a.collectableFishAttempts) or 0)) + 1
        any = true
        if TaskTracker.UpdateCollectableFromQuestFlags then
            TaskTracker.UpdateCollectableFromQuestFlags(node)
        end
        if TaskTracker.SyncAdvancedTask then
            TaskTracker.SyncAdvancedTask(node)
        end
    end)

    if any then
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then
            TaskTracker.RefreshList()
        end
    end
end

--- unit = event arg1. Payload is **target, castGUID, spellID** (wiki: UNIT_SPELLCAST_SENT); spellId is the 3rd vararg.
function TaskTracker.ProcessPlayerFishingCast(unit, ...)
    if unit ~= "player" then return end
    local spellId = tonumber(select(3, ...)) or tonumber(select(2, ...)) or tonumber(select(1, ...))
    if not spellId or spellId <= 0 then
        if TaskTrackerDB and TaskTrackerDB.debugFishSpell == true then
            print("|cff00ff00TaskTracker|r fishdebug SENT could not parse spellId; n="
                .. tostring(select("#", ...)) .. " args="
                .. tostring(select(1, ...)) .. " | " .. tostring(select(2, ...)) .. " | " .. tostring(select(3, ...)))
        end
        return
    end

    local debugOn = TaskTrackerDB and TaskTrackerDB.debugFishSpell == true
    if not debugOn and not ensureCatalogMightHaveFishingRules() then
        return
    end

    local isFish = isFishingSpell(spellId)

    if debugOn then
        local okDbg, mapDbg = pcall(function()
            return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        end)
        local poolDbg = guidLooksLikeGameObject(UnitGUID and UnitGUID("mouseover") or nil)
        print("|cff00ff00TaskTracker|r fishdebug SENT spellId=" .. tostring(spellId)
            .. " name=\"" .. spellDebugName(spellId) .. "\""
            .. " recognizedFishing=" .. tostring(isFish)
            .. " mapId=" .. tostring(okDbg and mapDbg or "?")
            .. " poolHintGO=" .. tostring(poolDbg))
    end

    if not isFish then return end

    local now = GetTime and GetTime() or 0
    if (now - lastFishingCountAt) < 0.45 then return end
    lastFishingCountAt = now

    local poolHintGO = guidLooksLikeGameObject(UnitGUID and UnitGUID("mouseover") or nil)

    if not C_Map or not C_Map.GetBestMapForUnit then return end
    local okm, mapId = pcall(C_Map.GetBestMapForUnit, "player")
    if not okm then return end
    mapId = tonumber(mapId)
    if not mapId or mapId <= 0 then return end

    TaskTracker.ApplyFishingForCast(mapId, poolHintGO)
end
