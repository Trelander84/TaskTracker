-- Core/Power.lua
-- Power module: reward hints, shared weekly caps, overview UI.
-- Season loot lives in Data/PowerSeason.lua; ApplyPowerSeasonToRegistry stamps it onto registry rows.

TaskTracker = TaskTracker or {}

local trim = TaskTracker.Trim

local function copySeasonSlot(src)
    if type(src) ~= "table" then return nil end
    return {
        expectedIlvl = src.expectedIlvl,
        expectedIlvlLow = src.expectedIlvlLow,
        currencyId = src.currencyId,
        itemId = src.itemId,
        label = src.label,
        otherReward = src.otherReward,
        iconAtlas = src.iconAtlas,
    }
end

--- Source minLevel applies to every slot from that source. 1 or missing means no requirement.
local function positiveIlvl(v)
    local n = tonumber(v)
    if n and n > 0 then
        return math.floor(n + 0.5)
    end
    return nil
end

local function levelRequirement(v)
    local n = tonumber(v)
    if n and n > 1 then
        return math.floor(n + 0.5)
    end
    return nil
end

local function stampSourceLevel(slot, src)
    if not slot or type(src) ~= "table" then return end
    slot.minLevel = levelRequirement(src.minLevel)
end

local function slotsFromSeasonSource(src, pools)
    if type(src) ~= "table" then return {} end
    local pattern = src.pattern
    local slots = {}
    if pattern == "pinnacle_then_surplus" then
        local pin = copySeasonSlot(src.pinnacle)
        if pin then
            pin.pinnacle = true
            pin.priority = src.priority
            if type(src.pool) == "string" and src.pool ~= "" then
                pin.shareKey = src.pool
                local pool = pools and pools[src.pool]
                local cap = pool and tonumber(pool.weeklyCap)
                if cap and cap > 0 then
                    pin.weeklyCap = math.floor(cap)
                end
            end
            stampSourceLevel(pin, src)
            slots[#slots + 1] = pin
        end
        local surplus = copySeasonSlot(src.surplus)
        if surplus then
            stampSourceLevel(surplus, src)
            -- Leftover crests/mats are not an upgrade once the pinnacle chest ilvl no longer applies.
            if surplus.expectedIlvl == nil and pin and pin.expectedIlvl then
                surplus.expectedIlvl = pin.expectedIlvl
            end
            slots[#slots + 1] = surplus
        end
    elseif pattern == "first_hunt_then_crest" then
        local hunt = copySeasonSlot(src.firstHunt)
        if hunt then
            hunt.oncePerWeeklyPeriod = true
            local untilCount = tonumber(src.firstHunt and src.firstHunt.untilCount)
            hunt.oncePerWeeklyCount = (untilCount and untilCount > 0) and math.floor(untilCount) or 1
            stampSourceLevel(hunt, src)
            slots[#slots + 1] = hunt
        end
        local crest = copySeasonSlot(src.crest)
        if crest then
            stampSourceLevel(crest, src)
            slots[#slots + 1] = crest
        end
    elseif pattern == "gear_then_crest" then
        local gear = copySeasonSlot(src.slot)
        if gear then
            stampSourceLevel(gear, src)
            slots[#slots + 1] = gear
        end
        local crest = copySeasonSlot(src.crest)
        if crest then
            stampSourceLevel(crest, src)
            -- Keep the crest's own ilvl. Copying the gear gate would hide the backup with the gear.
            slots[#slots + 1] = crest
        end
    else
        -- standalone (and unknown patterns with a slot table)
        local slot = copySeasonSlot(src.slot)
        if slot then
            stampSourceLevel(slot, src)
            slots[#slots + 1] = slot
        end
    end
    return slots
end

--- Stamp this season's loot onto registry rows. Call once after Registry + PowerSeason load.
function TaskTracker.ApplyPowerSeasonToRegistry()
    local season = TaskTracker.PowerSeason
    local sources = season and season.sources
    if type(sources) ~= "table" then return end
    local pools = season.pools
    local byId = TaskTracker.RegistryByID
    if not byId then return end
    for entryId, src in pairs(sources) do
        local entry = byId[entryId]
        if entry and type(src) == "table" then
            entry._ttPowerSlots = nil
            entry.powerRewards = slotsFromSeasonSource(src, pools)
            if src.sortOrder ~= nil then
                entry.powerSortOrder = src.sortOrder
            end
        end
    end
    if TaskTracker.InvalidatePowerShareCapCache then
        TaskTracker.InvalidatePowerShareCapCache()
    end
    if TaskTracker.InvalidatePowerShareWinnersCache then
        TaskTracker.InvalidatePowerShareWinnersCache()
    end
end

--- Build ordered reward slots from `entry.powerRewards` or legacy single-slot fields.
function TaskTracker.NormalizePowerRewardSlots(entry)
    if not entry then return {} end
    if entry._ttPowerSlots then
        return entry._ttPowerSlots
    end
    local slots = {}
    if type(entry.powerRewards) == "table" then
        for i, s in ipairs(entry.powerRewards) do
            if type(s) == "table" then
                local ilvl = positiveIlvl(s.expectedIlvl or s.powerExpectedIlvl)
                local ilvlLow = positiveIlvl(s.expectedIlvlLow)
                if ilvlLow and ilvl and ilvlLow >= ilvl then
                    ilvlLow = nil
                end
                local cur = tonumber(s.currencyId or s.powerRewardCurrencyId)
                local iid = tonumber(s.itemId or s.powerRewardItemId)
                local sk = s.shareKey
                local cap = tonumber(s.weeklyCap)
                if sk and (cap == nil or cap < 1) then
                    cap = 1
                end
                slots[#slots + 1] = {
                    expectedIlvl = ilvl,
                    expectedIlvlLow = ilvlLow,
                    currencyId = (cur and cur > 0) and math.floor(cur + 0.5) or nil,
                    itemId = (iid and iid > 0) and math.floor(iid + 0.5) or nil,
                    label = trim(s.label or s.powerRewardLabel),
                    otherReward = trim(s.otherReward or s.powerOtherReward),
                    iconAtlas = (type(s.iconAtlas) == "string" and s.iconAtlas ~= "") and s.iconAtlas or nil,
                    shareKey = (type(sk) == "string" and sk ~= "") and sk or nil,
                    weeklyCap = cap,
                    priority = tonumber(s.priority) or (1000 + i),
                    oncePerWeeklyPeriod = s.oncePerWeeklyPeriod == true,
                    oncePerWeeklyCount = tonumber(s.oncePerWeeklyCount),
                    pinnacle = s.pinnacle == true,
                    minLevel = levelRequirement(s.minLevel),
                }
            end
        end
    end
    if #slots == 0 then
        local ilvl = positiveIlvl(entry.powerExpectedIlvl)
        local ilvlLow = positiveIlvl(entry.powerExpectedIlvlLow)
        if ilvlLow and ilvl and ilvlLow >= ilvl then
            ilvlLow = nil
        end
        local cur = tonumber(entry.powerRewardCurrencyId)
        local iid = tonumber(entry.powerRewardItemId)
        local sk = entry.powerShareKey
        local cap = tonumber(entry.powerWeeklyCap)
        if type(sk) == "string" and sk ~= "" and (cap == nil or cap < 1) then
            cap = 1
        end
        if (ilvl and ilvl > 0)
            or (cur and cur > 0)
            or (iid and iid > 0)
            or (entry.powerOtherReward and tostring(entry.powerOtherReward):match("%S"))
            or (entry.powerRewardLabel and tostring(entry.powerRewardLabel):match("%S"))
            or (type(sk) == "string" and sk ~= "") then
            slots[1] = {
                expectedIlvl = ilvl,
                expectedIlvlLow = ilvlLow,
                currencyId = (cur and cur > 0) and math.floor(cur + 0.5) or nil,
                itemId = (iid and iid > 0) and math.floor(iid + 0.5) or nil,
                label = trim(entry.powerRewardLabel),
                otherReward = trim(entry.powerOtherReward),
                iconAtlas = (type(entry.powerIconAtlas) == "string" and entry.powerIconAtlas ~= "") and entry.powerIconAtlas or nil,
                shareKey = (type(sk) == "string" and sk ~= "") and sk or nil,
                weeklyCap = cap,
                priority = tonumber(entry.powerSharePriority) or 1000,
                minLevel = levelRequirement(entry.powerMinLevel),
            }
        end
    end
    entry._ttPowerSlots = slots
    return slots
end

local function slotHasContent(slot)
    if not slot then return false end
    if type(slot.expectedIlvl) == "number" and slot.expectedIlvl > 0 then return true end
    if type(slot.otherReward) == "string" and slot.otherReward:match("%S") then return true end
    if type(slot.currencyId) == "number" and slot.currencyId > 0 then return true end
    if type(slot.itemId) == "number" and slot.itemId > 0 then return true end
    if type(slot.label) == "string" and slot.label:match("%S") then return true end
    return false
end

function TaskTracker.EntryDefinesPowerReward(entry)
    if not entry then return false end
    local slots = TaskTracker.NormalizePowerRewardSlots(entry)
    for i = 1, #slots do
        if slotHasContent(slots[i]) then return true end
    end
    return false
end

function TaskTracker.GetEntriesForPowerModule()
    local entries = {}
    local seen = {}
    for _, entry in ipairs(TaskTracker.Registry or {}) do
        if TaskTracker.EntryDefinesPowerReward(entry) then
            table.insert(entries, entry)
            seen[entry.id] = true
        end
    end
    for _, entry in ipairs(TaskTracker.Registry or {}) do
        if entry.powerModuleListing and entry.expansion == "power" and not seen[entry.id] then
            table.insert(entries, entry)
            seen[entry.id] = true
        end
    end
    table.sort(entries, function(a, b)
        local oa = tonumber(a.powerSortOrder)
        local ob = tonumber(b.powerSortOrder)
        if oa and ob and oa ~= ob then return oa < ob end
        if oa and not ob then return true end
        if ob and not oa then return false end
        return (a.label or ""):lower() < (b.label or ""):lower()
    end)
    return entries
end

-- Armor / jewelry / weapons. Skip shirt (4) and tabard (19). Empty off-hand (2H) is skipped.
local POWER_GEAR_INV_SLOTS = {
    1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
}
local LOWEST_EQUIP_CACHE_TTL = 30
local LOWEST_EQUIP_MISS_TTL = 2
local lowestEquippedIlvlCache -- { ilvl = number|nil, t = GetTime(), miss = bool }

function TaskTracker.InvalidateLowestEquippedItemLevel()
    lowestEquippedIlvlCache = nil
end

local function inventoryLinkItemLevel(link)
    if type(link) ~= "string" or link == "" then return nil end
    local fn = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if not fn then return nil end
    local ok, ilvl = pcall(fn, link)
    if not ok then return nil end
    local n = tonumber(ilvl)
    if n and n > 0 then return math.floor(n + 0.5) end
    return nil
end

local function averageEquippedOrOverallItemLevel()
    if not GetAverageItemLevel then return nil end
    local ok, overall, equipped = pcall(GetAverageItemLevel)
    if not ok then return nil end
    local n = tonumber(equipped)
    if not n or n <= 0 then
        n = tonumber(overall)
    end
    if n and n > 0 then
        return math.floor(n + 0.5)
    end
    return nil
end

--- Lowest item level among worn gear slots (not average). Average only if no slot has loaded yet.
function TaskTracker.GetPlayerEquippedItemLevel()
    if IsPlayerInWorld and not IsPlayerInWorld() then return nil end
    local now = GetTime()
    local c = lowestEquippedIlvlCache
    if c then
        local ttl = c.miss and LOWEST_EQUIP_MISS_TTL or LOWEST_EQUIP_CACHE_TTL
        if (now - c.t) <= ttl then
            return c.ilvl
        end
    end
    local lowest
    for i = 1, #POWER_GEAR_INV_SLOTS do
        local ok, link = pcall(GetInventoryItemLink, "player", POWER_GEAR_INV_SLOTS[i])
        if ok then
            local n = inventoryLinkItemLevel(link)
            if n and (not lowest or n < lowest) then
                lowest = n
            end
        end
    end
    if lowest then
        lowestEquippedIlvlCache = { ilvl = lowest, t = now, miss = false }
        return lowest
    end
    local avg = averageEquippedOrOverallItemLevel()
    lowestEquippedIlvlCache = { ilvl = avg, t = now, miss = true }
    return avg
end

function TaskTracker.GetPowerProgressItemLevel()
    local db = TaskTrackerDB
    if db and db.powerDetailsIlvlOverride then
        local s = tostring(db.powerDetailsIlvlOverride):match("^%s*(.-)%s*$")
        if s and s ~= "" then
            local n = tonumber(s)
            if n and n > 0 then
                return math.floor(n + 0.5)
            end
        end
    end
    return TaskTracker.GetPlayerEquippedItemLevel()
end

function TaskTracker.PowerRewardSlotPassesIlvl(slot)
    if not slot or type(slot.expectedIlvl) ~= "number" or slot.expectedIlvl <= 0 then
        return true
    end
    local eq = TaskTracker.GetPowerProgressItemLevel()
    if not eq then return true end
    return eq < slot.expectedIlvl
end

--- "292-302" when the slot has a low and a high. The high is expectedIlvl, which is also the gate.
function TaskTracker.FormatPowerSlotIlvl(slot)
    if not slot then return "" end
    local hi = slot.expectedIlvl
    local lo = slot.expectedIlvlLow
    if type(hi) == "number" and hi > 0 and type(lo) == "number" and lo > 0 and lo < hi then
        return string.format("%d-%d", lo, hi)
    end
    if type(hi) == "number" and hi > 0 then
        return tostring(hi)
    end
    return ""
end

--- True when this character may use the slot. No minLevel, or level not known yet, counts as a pass.
function TaskTracker.PowerRewardSlotPassesLevel(slot)
    local need = slot and slot.minLevel
    if type(need) ~= "number" or need <= 1 then
        return true
    end
    if not UnitLevel then return true end
    local ok, lvl = pcall(UnitLevel, "player")
    if not ok or lvl == nil then return true end
    if issecretvalue and issecretvalue(lvl) then return true end
    lvl = tonumber(lvl)
    if not lvl or lvl < 1 then return true end
    return lvl >= need
end

local powerShareCapCache = {}

function TaskTracker.GetPowerShareWeeklyCap(shareKey)
    if not shareKey or shareKey == "" then return 1 end
    local cached = powerShareCapCache[shareKey]
    if cached ~= nil then return cached end
    local cap = 1
    local season = TaskTracker.PowerSeason
    local pool = season and season.pools and season.pools[shareKey]
    local poolCap = pool and tonumber(pool.weeklyCap)
    if poolCap and poolCap > 0 then
        cap = math.floor(poolCap)
        powerShareCapCache[shareKey] = cap
        return cap
    end
    for _, entry in ipairs(TaskTracker.Registry or {}) do
        local slots = TaskTracker.NormalizePowerRewardSlots(entry)
        for i = 1, #slots do
            local s = slots[i]
            if s.shareKey == shareKey and type(s.weeklyCap) == "number" and s.weeklyCap > cap then
                cap = s.weeklyCap
            end
        end
    end
    powerShareCapCache[shareKey] = cap
    return cap
end

function TaskTracker.InvalidatePowerShareCapCache()
    wipe(powerShareCapCache)
end

function TaskTracker.InvalidatePowerShareWinnersCache()
    TaskTracker._ttPowerShareWinners = nil
end

local function buildPowerShareWinners()
    local map = {}
    local naturally = TaskTracker.RegistryEntryNaturallyCompleteForRewards
    for _, entry in ipairs(TaskTracker.Registry or {}) do
        local slots = TaskTracker.NormalizePowerRewardSlots(entry)
        local shareSlot
        for i = 1, #slots do
            local s = slots[i]
            if s.shareKey and slotHasContent(s) then
                shareSlot = s
                break
            end
        end
        if shareSlot and TaskTracker.PowerRewardSlotPassesIlvl(shareSlot)
            and TaskTracker.PowerRewardSlotPassesLevel(shareSlot) then
            local sk = shareSlot.shareKey
            local st = TaskTrackerDB and TaskTrackerDB.registryState and TaskTrackerDB.registryState[entry.id]
            local pri = shareSlot.priority or 1000
            local per = TaskTracker.RegistryEntryUsesPowerSharePerCompletionClaims
                and TaskTracker.RegistryEntryUsesPowerSharePerCompletionClaims(entry)
            if per then
                local times = st and st.powerShareClaimTimes
                if type(times) == "table" and #times > 0 then
                    map[sk] = map[sk] or {}
                    for i = 1, #times do
                        local t = times[i]
                        if type(t) == "number" and t > 0 then
                            -- Micro-offset preserves sort order for same-second claims from one row.
                            table.insert(map[sk], { id = entry.id, t = t + i * 1e-6, pri = pri })
                        end
                    end
                end
            elseif naturally and naturally(entry) then
                -- Only rows with a recorded claim time consume the weekly pool. Otherwise
                -- IsQuestFlaggedCompleted can stay true for one-off / wrong quest ids and
                -- would phantom-fill the cap (e.g. showing surplus on rows you have not finished).
                local t = st and st.powerShareClaimAt
                if type(t) == "number" and t > 0 then
                    map[sk] = map[sk] or {}
                    table.insert(map[sk], { id = entry.id, t = t, pri = pri })
                end
            end
        end
    end
    for sk, list in pairs(map) do
        table.sort(list, function(a, b)
            if a.t ~= b.t then return a.t < b.t end
            if a.pri ~= b.pri then return a.pri < b.pri end
            return (a.id or "") < (b.id or "")
        end)
        local cap = TaskTracker.GetPowerShareWeeklyCap(sk)
        while #list > cap do
            table.remove(list)
        end
        for i = 1, #list do
            list[i] = list[i].id
        end
    end
    return map
end

function TaskTracker.GetPowerShareWinnersMap()
    if not TaskTracker._ttPowerShareWinners then
        TaskTracker._ttPowerShareWinners = buildPowerShareWinners()
    end
    return TaskTracker._ttPowerShareWinners
end

function TaskTracker.EntryMayUsePowerShareSlot(entry, slot)
    if not entry or not slot or not slot.shareKey then return true end
    local sk = slot.shareKey
    local cap = TaskTracker.GetPowerShareWeeklyCap(sk)
    if cap < 1 then cap = 1 end
    local winners = TaskTracker.GetPowerShareWinnersMap()[sk] or {}
    -- Rows that already claimed a seat still show this slot after the cap is full.
    -- Everyone else falls through to surplus (or hides) once #winners >= cap.
    for i = 1, #winners do
        if winners[i] == entry.id then
            return true
        end
    end
    return #winners < cap
end

function TaskTracker.GetEffectivePowerRewardSlot(entry)
    if not entry then return nil end
    local slots = TaskTracker.NormalizePowerRewardSlots(entry)
    for i = 1, #slots do
        local s = slots[i]
        if not slotHasContent(s) then
            -- skip empty placeholders
        elseif s.oncePerWeeklyPeriod and entry.reset == "weekly" and entry.type == "quest_count"
            and TaskTracker.GetRegistryQuestCountFromGame then
            local st = TaskTrackerDB and TaskTrackerDB.registryState and TaskTrackerDB.registryState[entry.id]
            local n = TaskTracker.GetRegistryQuestCountFromGame(entry, st)
            local usedUp = tonumber(s.oncePerWeeklyCount) or 1
            if usedUp < 1 then usedUp = 1 end
            if type(n) == "number" and n >= usedUp then
                -- Chest slots apply for the first N hunts this week; further hunts are crest-only.
            elseif TaskTracker.PowerRewardSlotPassesIlvl(s) and TaskTracker.PowerRewardSlotPassesLevel(s)
                and TaskTracker.EntryMayUsePowerShareSlot(entry, s) then
                return s, i
            end
        elseif TaskTracker.PowerRewardSlotPassesIlvl(s) and TaskTracker.PowerRewardSlotPassesLevel(s)
            and TaskTracker.EntryMayUsePowerShareSlot(entry, s) then
            return s, i
        end
    end
    return nil
end

--- Omit from the Power task group when no reward slot applies (level, ilvl, pool, once-per-week, etc.).
--- The same row stays visible under its home expansion; see IsRegistryRowTrackedForList(..., true).
function TaskTracker.RegistryEntryHiddenByPowerIlvl(entry)
    if not entry or not TaskTracker.EntryDefinesPowerReward(entry) then return false end
    local slot = TaskTracker.GetEffectivePowerRewardSlot(entry)
    return slot == nil
end

function TaskTracker.IsRegistryRowTrackedForList(registryEntryId, underPowerSubtree)
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if entry and entry.professionKey and TaskTracker.ProfessionRegistryEntryVisible then
        if not TaskTracker.ProfessionRegistryEntryVisible(entry) then
            return false
        end
    end
    if underPowerSubtree then
        if not TaskTracker.IsPowerListEntryEnabled(registryEntryId) then return false end
    else
        if not TaskTracker.IsEntryEnabled(registryEntryId) then return false end
    end
    if entry and TaskTracker.IsRegistryRequireOwnedLocked
        and TaskTracker.IsRegistryRequireOwnedLocked(entry) then
        return false
    end
    if not underPowerSubtree and entry and TaskTracker.IsCollectionsModuleRowHidden
        and TaskTracker.IsCollectionsModuleRowHidden(entry) then
        return false
    end
    -- Level and ilvl gating apply only under the Power list mirror; same rows stay visible in their
    -- home expansion (Midnight, etc.) so progress is not hidden from the main tree.
    if underPowerSubtree and entry and TaskTracker.RegistryEntryHiddenByPowerIlvl(entry) then
        return false
    end
    return true
end

function TaskTracker.GetPowerRewardDisplayLabelForSlot(slot)
    if not slot then return nil end
    if slot.label and slot.label:match("%S") then return slot.label end
    if slot.otherReward and slot.otherReward:match("%S") then return slot.otherReward end
    if type(slot.currencyId) == "number" and slot.currencyId > 0 and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, slot.currencyId)
        if ok and info and info.name and info.name ~= "" then return info.name end
    end
    if type(slot.itemId) == "number" and slot.itemId > 0 and C_Item and C_Item.GetItemInfo then
        local ok, a = pcall(C_Item.GetItemInfo, slot.itemId)
        if ok and type(a) == "table" and a.itemName and a.itemName ~= "" then return a.itemName end
        if ok and type(a) == "string" and a ~= "" then return a end
    end
    return nil
end

function TaskTracker.RegistryEntryPowerMattersNow(entry)
    if not entry or not TaskTracker.EntryDefinesPowerReward(entry) then return false end
    local slot = TaskTracker.GetEffectivePowerRewardSlot(entry)
    if not slot then return false end
    local hasIlvl = type(slot.expectedIlvl) == "number" and slot.expectedIlvl > 0
    if hasIlvl then
        local eq = TaskTracker.GetPowerProgressItemLevel()
        if not eq then return true end
        return eq < slot.expectedIlvl
    end
    local hasOther = type(slot.otherReward) == "string" and slot.otherReward:match("%S")
    local hasCurOrItem = (type(slot.currencyId) == "number" and slot.currencyId > 0)
        or (type(slot.itemId) == "number" and slot.itemId > 0)
    local hasLbl = type(slot.label) == "string" and slot.label:match("%S")
    return hasOther or hasCurOrItem or hasLbl
end

function TaskTracker.PowerSlotIconAtlas(slot)
    if not slot or type(slot.iconAtlas) ~= "string" or slot.iconAtlas == "" then return nil end
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(slot.iconAtlas) then
        return slot.iconAtlas
    end
    return nil
end

function TaskTracker.GetPowerRewardIconFileIdForSlot(slot)
    if not slot then return nil end
    if type(slot.currencyId) == "number" and slot.currencyId > 0 and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, slot.currencyId)
        if ok and info and info.iconFileID and info.iconFileID > 0 then
            return info.iconFileID
        end
    end
    if type(slot.itemId) == "number" and slot.itemId > 0 and C_Item and C_Item.GetItemIconByID then
        local ok, fid = pcall(C_Item.GetItemIconByID, slot.itemId)
        if ok and type(fid) == "number" and fid > 0 then return fid end
    end
    return nil
end

function TaskTracker.GetPowerRewardIconFileId(entry)
    local slot = TaskTracker.GetEffectivePowerRewardSlot(entry)
    return TaskTracker.GetPowerRewardIconFileIdForSlot(slot)
end

function TaskTracker.PowerRewardRowShouldShowPowerColumn(entry)
    if not entry or not TaskTracker.EntryDefinesPowerReward(entry) then return false end
    local slot = TaskTracker.GetEffectivePowerRewardSlot(entry)
    if not slot then return false end
    if TaskTracker.GetPowerRewardIconFileIdForSlot(slot) then return true end
    if type(slot.expectedIlvl) == "number" and slot.expectedIlvl > 0 then return true end
    return false
end

function TaskTracker.AnchorPowerRewardTooltip(anchor, entry)
    if not anchor or not entry then return end
    local slot = TaskTracker.GetEffectivePowerRewardSlot(entry)
    if not slot then return end
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if type(slot.currencyId) == "number" and slot.currencyId > 0 then
        local ok = pcall(function()
            if GameTooltip.SetCurrencyByID then
                GameTooltip:SetCurrencyByID(slot.currencyId)
            elseif GameTooltip.SetCurrencyToken and C_CurrencyInfo.GetCurrencyLink then
                local ok2, link = pcall(C_CurrencyInfo.GetCurrencyLink, slot.currencyId)
                if ok2 and link then
                    GameTooltip:SetHyperlink(link)
                end
            end
        end)
        if ok then
            GameTooltip:Show()
            return
        end
    end
    if type(slot.itemId) == "number" and slot.itemId > 0 then
        local ok = pcall(function()
            if GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(slot.itemId)
            end
        end)
        if ok then
            GameTooltip:Show()
            return
        end
    end
    GameTooltip:SetText("Reward", 1, 1, 1)
    local lbl = TaskTracker.GetPowerRewardDisplayLabelForSlot(slot)
    if lbl then
        GameTooltip:AddLine(lbl, 1, 1, 1, true)
    end
    local ilvlTxt = TaskTracker.FormatPowerSlotIlvl(slot)
    if ilvlTxt ~= "" then
        GameTooltip:AddLine("Item level " .. ilvlTxt, 0.85, 0.9, 1, false)
    end
    if slot.shareKey then
        GameTooltip:AddLine(string.format("Shared pool: %s (weekly cap %d)", slot.shareKey, TaskTracker.GetPowerShareWeeklyCap(slot.shareKey)), 0.7, 0.85, 1, true)
    end
    if slot.pinnacle then
        GameTooltip:AddLine("Pinnacle reward (shared weekly limit with other pinnacle rows).", 0.85, 0.75, 1, true)
    end
    if slot.oncePerWeeklyPeriod then
        local n = tonumber(slot.oncePerWeeklyCount) or 1
        GameTooltip:AddLine(string.format("Shown until %d hunt(s) this week; after that, crest rewards apply.", n), 0.75, 0.82, 0.9, true)
    end
    GameTooltip:Show()
end

local powerOverviewFrame

local function hidePowerOverview()
    if powerOverviewFrame then
        powerOverviewFrame:Hide()
    end
end

local function liveComparisonIlvlText()
    local n = TaskTracker.GetPlayerEquippedItemLevel()
    return n and tostring(n) or ""
end

local function applyPowerIlvlOverrideFromEditBox(edit)
    local db = TaskTrackerDB
    if not db or not edit then return end
    local s = edit:GetText() or ""
    s = s:match("^%s*(.-)%s*$") or ""
    local typed = tonumber(s)
    local live = TaskTracker.GetPlayerEquippedItemLevel()
    -- Blank, or the current lowest equipped piece: follow gear, do not freeze an override.
    if s == "" or (typed and live and typed == live) then
        db.powerDetailsIlvlOverride = nil
        if live then
            edit:SetText(tostring(live))
        end
    else
        db.powerDetailsIlvlOverride = s
    end
end

-- Power overview: fixed-column spreadsheet (horizontal + vertical scroll).
local POWER_OVERVIEW_COL_W = {
    22,  -- 1 icon
    22,  -- 2 active check
    28,  -- 3 slot #
    156, -- 4 module
    44,  -- 5 power (still applies)
    68,  -- 6 item id
    52,  -- 7 currency
    56,  -- 8 ilvl (room for a low-high band)
    40,  -- 9 level requirement
    152, -- 10 label
    100, -- 11 other
    32,  -- 12 pinnacle
    132, -- 13 pool
}
local POWER_OVERVIEW_HEADERS = {
    "", "Act", "#", "Module", "Power", "Item", "Curr", "ilvl", "Level", "Label", "Other", "Pin", "Pool",
}
-- Compact columns: header + value centered. Names/labels stay left.
local POWER_OVERVIEW_CENTER = {
    [1] = true, [2] = true, [3] = true, [5] = true,
    [6] = true, [7] = true, [8] = true, [9] = true, [12] = true,
}

local function powerOverviewJustify(colIndex)
    return POWER_OVERVIEW_CENTER[colIndex] and "CENTER" or "LEFT"
end

local function powerOverviewTableWidth()
    local w = 0
    for i = 1, #POWER_OVERVIEW_COL_W do
        w = w + POWER_OVERVIEW_COL_W[i]
    end
    return w
end

local function powerOverviewColLeft(colIndex)
    local x = 0
    for i = 1, colIndex - 1 do
        x = x + POWER_OVERVIEW_COL_W[i]
    end
    return x
end

local function powerOverviewEllipsize(s, maxLen)
    if not s or s == "" then return "" end
    s = tostring(s)
    if #s <= maxLen then return s end
    return s:sub(1, math.max(0, maxLen - 1)) .. "…"
end

local function powerOverviewAddCell(row, colIndex, text, fontKey, justify)
    local cw = POWER_OVERVIEW_COL_W[colIndex]
    local x = powerOverviewColLeft(colIndex)
    local t = TaskTracker.GetTheme and TaskTracker.GetTheme() or {}
    local fo = (fontKey == "header") and (t.fontNormal or "GameFontNormalSmall")
        or (t.fontNormal or "GameFontNormalSmall")
    local fs = TaskTracker.CreateFontString(row, nil, "OVERLAY", fo)
    fs:SetSize(math.max(4, cw - 4), 14)
    fs:SetPoint("LEFT", row, "LEFT", x + 2, 0)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetMaxLines(1)
    fs:SetNonSpaceWrap(false)
    fs:SetText(text or "")
    if TaskTracker.SetTextColor then
        TaskTracker.SetTextColor(fs, fontKey == "header" and "textSecondary" or "textPrimary")
    end
    return fs
end

local POWER_OVERVIEW_MIN_W, POWER_OVERVIEW_MIN_H = 480, 280
local POWER_OVERVIEW_DEFAULT_W, POWER_OVERVIEW_DEFAULT_H = 780, 520

local function powerOverviewScreenMax()
    return math.floor(UIParent:GetWidth() - 24), math.floor(UIParent:GetHeight() - 24)
end

local function powerOverviewSyncViewport()
    local p = powerOverviewFrame
    if not p or not p._scroll then return end
    local sf = p._scroll
    local maxH = 0
    if sf.GetHorizontalScrollRange then
        local ok, r = pcall(function() return sf:GetHorizontalScrollRange() end)
        if ok and type(r) == "number" then maxH = r end
    end
    if sf.GetHorizontalScroll and sf.SetHorizontalScroll then
        local cur = sf:GetHorizontalScroll() or 0
        if cur > maxH then
            sf:SetHorizontalScroll(maxH)
        end
    end
    if sf.UpdateScrollBar then
        sf.UpdateScrollBar()
    end
end

local function powerOverviewRefreshList()
    local p = powerOverviewFrame
    if not p or not p._child then return end
    TaskTracker.InvalidatePowerShareWinnersCache()
    local child = p._child
    for _, r in ipairs(p._rows) do
        if r then r:Hide() end
    end
    wipe(p._rows)

    local tableW = powerOverviewTableWidth()
    child:SetWidth(tableW)

    local rowH = 16
    local headerH = 20
    local y = 0
    local winnersMap = TaskTracker.GetPowerShareWinnersMap and TaskTracker.GetPowerShareWinnersMap() or {}

    -- Header row
    do
        local hdr = CreateFrame("Frame", nil, child)
        hdr:SetSize(tableW, headerH)
        hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        y = y + headerH + 2
        local bg = hdr:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if TaskTracker.SetColor then
            TaskTracker.SetColor(bg, "headerBg2")
        end
        for c = 1, #POWER_OVERVIEW_HEADERS do
            powerOverviewAddCell(hdr, c, POWER_OVERVIEW_HEADERS[c], "header", powerOverviewJustify(c))
        end
        p._rows[#p._rows + 1] = hdr
    end

    local rowStripe = 0
    for _, entry in ipairs(TaskTracker.GetEntriesForPowerModule()) do
        local slots = TaskTracker.NormalizePowerRewardSlots(entry)
        local _, effIdx = TaskTracker.GetEffectivePowerRewardSlot(entry)
        local mattersStr = TaskTracker.RegistryEntryPowerMattersNow(entry) and "yes" or "no"

        if #slots == 0 then
            local row = CreateFrame("Frame", nil, child)
            row:SetSize(tableW, rowH)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            y = y + rowH
            rowStripe = rowStripe + 1
            if rowStripe % 2 == 0 then
                local z = row:CreateTexture(nil, "BACKGROUND")
                z:SetAllPoints()
                if TaskTracker.SetColor then TaskTracker.SetColor(z, "headerBg") end
                z:SetAlpha(0.35)
            end
            for c = 1, #POWER_OVERVIEW_HEADERS do
                local txt = "—"
                if c == 4 then txt = powerOverviewEllipsize(entry.label or entry.id, 22)
                elseif c == 5 then txt = mattersStr
                elseif c == 10 then txt = "(no slots)" end
                powerOverviewAddCell(row, c, txt, "row", powerOverviewJustify(c))
            end
            p._rows[#p._rows + 1] = row
        else
            for i = 1, #slots do
                local slot = slots[i]
                local row = CreateFrame("Frame", nil, child)
                row:SetSize(tableW, rowH)
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
                y = y + rowH
                rowStripe = rowStripe + 1
                if rowStripe % 2 == 0 then
                    local z = row:CreateTexture(nil, "BACKGROUND")
                    z:SetAllPoints()
                    if TaskTracker.SetColor then TaskTracker.SetColor(z, "headerBg") end
                    z:SetAlpha(0.35)
                end

                -- Icon (this slot): difficulty atlas, else the item or currency icon.
                local fid = TaskTracker.GetPowerRewardIconFileIdForSlot(slot)
                local atlas = TaskTracker.PowerSlotIconAtlas(slot)
                local icon = row:CreateTexture(nil, "OVERLAY")
                icon:SetSize(16, 16)
                icon:SetPoint("LEFT", row, "LEFT", powerOverviewColLeft(1) + 3, 0)
                if atlas then
                    icon:SetAtlas(atlas, false)
                    icon:SetAlpha(1)
                elseif fid then
                    icon:SetTexture(fid)
                    icon:SetAlpha(1)
                else
                    icon:SetTexture(nil)
                    icon:SetAlpha(0.08)
                end
                local hit = CreateFrame("Button", nil, row)
                hit:SetSize(18, 18)
                hit:SetPoint("CENTER", icon, "CENTER", 0, 0)
                hit:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    GameTooltip:SetText(entry.label or entry.id, 1, 1, 1)
                    GameTooltip:AddLine(string.format("Slot %d", i), 0.8, 0.8, 0.8, false)
                    if slot.label and slot.label ~= "" then
                        GameTooltip:AddLine(slot.label, 1, 1, 1, true)
                    end
                    if slot.itemId then
                        GameTooltip:AddLine("Item " .. tostring(slot.itemId), 0.85, 0.9, 1, false)
                    end
                    if slot.otherReward and slot.otherReward ~= "" then
                        GameTooltip:AddLine(slot.otherReward, 0.75, 0.85, 1, true)
                    end
                    GameTooltip:Show()
                end)
                hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

                -- Active column: check on the slot that applies. The old arrow glyph draws as a box.
                if effIdx and i == effIdx then
                    local mark = row:CreateTexture(nil, "OVERLAY")
                    mark:SetSize(14, 14)
                    mark:SetPoint("LEFT", row, "LEFT", powerOverviewColLeft(2) + 4, 0)
                    local check = TaskTracker.FirstValidAtlas(
                        "groupfinder-icon-greencheckmark", "common-icon-checkmark", "common-icon-check")
                    if check and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(check) then
                        mark:SetAtlas(check, false)
                    else
                        mark:Hide()
                    end
                end

                powerOverviewAddCell(row, 3, tostring(i), "row", powerOverviewJustify(3))
                powerOverviewAddCell(row, 4, powerOverviewEllipsize(entry.label or entry.id, 36), "row", powerOverviewJustify(4))
                powerOverviewAddCell(row, 5, mattersStr, "row", powerOverviewJustify(5))
                powerOverviewAddCell(row, 6, slot.itemId and tostring(slot.itemId) or "—", "row", powerOverviewJustify(6))
                powerOverviewAddCell(row, 7, slot.currencyId and tostring(slot.currencyId) or "—", "row", powerOverviewJustify(7))
                local ilvlCell = TaskTracker.FormatPowerSlotIlvl(slot)
                powerOverviewAddCell(row, 8, ilvlCell ~= "" and ilvlCell or "—", "row", powerOverviewJustify(8))
                powerOverviewAddCell(row, 9, slot.minLevel and tostring(slot.minLevel) or "—", "row", powerOverviewJustify(9))
                powerOverviewAddCell(row, 10, powerOverviewEllipsize(slot.label or "", 26), "row", powerOverviewJustify(10))
                powerOverviewAddCell(row, 11, powerOverviewEllipsize(slot.otherReward or "", 18), "row", powerOverviewJustify(11))
                powerOverviewAddCell(row, 12, slot.pinnacle and "Y" or "—", "row", powerOverviewJustify(12))
                local poolTxt = "—"
                if slot.shareKey then
                    local cap = TaskTracker.GetPowerShareWeeklyCap(slot.shareKey)
                    local used = (winnersMap[slot.shareKey] and #winnersMap[slot.shareKey]) or 0
                    poolTxt = string.format("%s %d/%d", powerOverviewEllipsize(slot.shareKey, 14), used, cap)
                end
                if slot.oncePerWeeklyPeriod then
                    local n = tonumber(slot.oncePerWeeklyCount) or 1
                    poolTxt = (poolTxt ~= "—" and (poolTxt .. " · ") or "")
                        .. ((n == 1) and "1st hunt" or (tostring(n) .. " hunts"))
                end
                powerOverviewAddCell(row, 13, poolTxt, "row", powerOverviewJustify(13))

                p._rows[#p._rows + 1] = row
            end
        end
    end

    child:SetHeight(math.max(40, y + 8))
    powerOverviewSyncViewport()
end

function TaskTracker.OpenPowerModuleOverview()
    local t = TaskTracker.GetTheme and TaskTracker.GetTheme() or {}
    if not powerOverviewFrame then
        local db0 = TaskTrackerDB
        local maxW, maxH = powerOverviewScreenMax()
        local w = (db0 and db0.powerDetailsPanelWidth) or POWER_OVERVIEW_DEFAULT_W
        local h = (db0 and db0.powerDetailsPanelHeight) or POWER_OVERVIEW_DEFAULT_H
        w = math.max(POWER_OVERVIEW_MIN_W, math.min(w, maxW))
        h = math.max(POWER_OVERVIEW_MIN_H, math.min(h, maxH))
        local p = TaskTracker.MakePanel and TaskTracker.MakePanel("TaskTrackerPowerOverview", UIParent, w, h)
        if not p then return end
        powerOverviewFrame = p
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:SetFrameLevel(500)
        p:SetClampedToScreen(true)
        p:SetMovable(true)
        p:SetResizable(true)
        p:SetResizeBounds(POWER_OVERVIEW_MIN_W, POWER_OVERVIEW_MIN_H, maxW, maxH)
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 40)

        if p.TitleText then
            p.TitleText:SetText("Power — reward hints")
        end
        if p.CloseButton then
            p.CloseButton:SetScript("OnClick", function()
                hidePowerOverview()
            end)
        end

        local closeLbl = TaskTracker.MakeButton and TaskTracker.MakeButton(p.titleBar, "Close", 52, 20)
        if closeLbl then
            closeLbl:SetPoint("RIGHT", p.CloseButton, "LEFT", -4, 0)
            closeLbl:SetScript("OnClick", function()
                hidePowerOverview()
            end)
        end

        local content = p.Content
        local ilvlRow = CreateFrame("Frame", nil, content)
        ilvlRow:SetHeight(26)
        ilvlRow:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -6)
        ilvlRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -6)

        local ilvlHint = TaskTracker.CreateFontString(ilvlRow, nil, "OVERLAY", t.fontNormal or "GameFontNormalSmall")
        ilvlHint:SetPoint("LEFT", ilvlRow, "LEFT", 0, 0)
        ilvlHint:SetText("ilvl for comparisons (lowest equipped slot):")
        if TaskTracker.SetTextColor then
            TaskTracker.SetTextColor(ilvlHint, "textSecondary")
        end

        local ilvlEdit
        if TaskTracker.MakeEditBox then
            ilvlEdit = TaskTracker.MakeEditBox(ilvlRow, nil, 56, 22)
        else
            ilvlEdit = CreateFrame("EditBox", nil, ilvlRow)
            ilvlEdit:SetSize(56, 22)
            ilvlEdit:SetFontObject(t.fontNormal or "GameFontHighlightSmall")
            TaskTracker.ClearFontShadow(ilvlEdit)
            ilvlEdit:SetAutoFocus(false)
        end
        ilvlEdit:SetNumeric(true)
        ilvlEdit:SetMaxLetters(4)
        ilvlEdit:SetPoint("LEFT", ilvlHint, "RIGHT", 8, 0)
        ilvlEdit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        ilvlEdit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        ilvlEdit:SetScript("OnEditFocusLost", function(self)
            applyPowerIlvlOverrideFromEditBox(self)
            if TaskTracker.MarkListLayoutDirty then
                TaskTracker.MarkListLayoutDirty()
            end
            if TaskTracker.RefreshList then
                TaskTracker.RefreshList()
            end
            powerOverviewRefreshList()
        end)
        p._ilvlEdit = ilvlEdit

        local gutter = (TaskTracker.GetScrollGutter and TaskTracker.GetScrollGutter()) or 8
        local gridHost = CreateFrame("Frame", nil, content)
        gridHost:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -36)
        gridHost:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, 4)
        gridHost:EnableMouse(true)

        local scroll = CreateFrame("ScrollFrame", nil, gridHost)
        scroll:SetPoint("TOPLEFT", gridHost, "TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", gridHost, "BOTTOMRIGHT", -gutter, gutter)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(powerOverviewTableWidth())
        child:SetHeight(1)
        scroll:SetScrollChild(child)
        if TaskTracker.MakeScrollBar then
            TaskTracker.MakeScrollBar(scroll, gridHost, { bottom = gutter })
        end
        if TaskTracker.MakeHorizontalScrollBar then
            TaskTracker.MakeHorizontalScrollBar(scroll, gridHost, { right = gutter })
        end
        p._scroll = scroll
        p._child = child
        p._rows = {}

        -- Bottom-right L-grip (same as main panel / Options)
        local GRIP_SIZE, LINE_THICK, LINE_LEN = 18, 2, 11
        local grip = CreateFrame("Button", nil, p)
        grip:SetSize(GRIP_SIZE, GRIP_SIZE)
        grip:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1, 1)
        grip:SetFrameLevel(p:GetFrameLevel() + 25)

        local lineV = grip:CreateTexture(nil, "ARTWORK")
        lineV:SetSize(LINE_THICK, LINE_LEN)
        lineV:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1)
        if TaskTracker.SetColor then TaskTracker.SetColor(lineV, "accent") end
        lineV:SetAlpha(0.55)

        local lineH = grip:CreateTexture(nil, "ARTWORK")
        lineH:SetSize(LINE_LEN, LINE_THICK)
        lineH:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1)
        if TaskTracker.SetColor then TaskTracker.SetColor(lineH, "accent") end
        lineH:SetAlpha(0.55)

        local function SetGripLineAlpha(a)
            lineV:SetAlpha(a)
            lineH:SetAlpha(a)
        end

        local function EndPowerOverviewResize()
            p:StopMovingOrSizing()
            grip:SetScript("OnUpdate", nil)
            powerOverviewSyncViewport()
        end

        grip:SetScript("OnEnter", function() SetGripLineAlpha(0.9) end)
        grip:SetScript("OnLeave", function() SetGripLineAlpha(0.55) end)
        grip:SetScript("OnHide", function()
            p:StopMovingOrSizing()
            grip:SetScript("OnUpdate", nil)
        end)
        grip:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                p:StartSizing("BOTTOMRIGHT")
                self:SetScript("OnUpdate", function()
                    if not IsMouseButtonDown("LeftButton") then
                        EndPowerOverviewResize()
                    end
                end)
            end
        end)
        grip:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                EndPowerOverviewResize()
            end
        end)

        p:SetScript("OnSizeChanged", function(self)
            if self.TitleText then
                self.TitleText:SetWidth(math.max(80, (self:GetWidth() or 0) * 0.45))
            end
            local db = TaskTrackerDB
            if db then
                db.powerDetailsPanelWidth  = math.floor(self:GetWidth() + 0.5)
                db.powerDetailsPanelHeight = math.floor(self:GetHeight() + 0.5)
            end
            powerOverviewSyncViewport()
        end)

        p:SetScript("OnShow", function(self)
            local mw, mh = powerOverviewScreenMax()
            self:SetResizeBounds(POWER_OVERVIEW_MIN_W, POWER_OVERVIEW_MIN_H, mw, mh)
            if self:GetWidth() > mw or self:GetHeight() > mh then
                self:SetSize(math.min(self:GetWidth(), mw), math.min(self:GetHeight(), mh))
            end
        end)
    end

    local p = powerOverviewFrame
    local db = TaskTrackerDB
    if p._ilvlEdit then
        local s = db and db.powerDetailsIlvlOverride
        if s and tostring(s):match("%S") then
            p._ilvlEdit:SetText(tostring(s))
        else
            p._ilvlEdit:SetText(liveComparisonIlvlText())
        end
    end

    powerOverviewRefreshList()
    p:Show()
    p:Raise()
end

TaskTracker.ApplyPowerSeasonToRegistry()
