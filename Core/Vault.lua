-- Core/Vault.lua
-- Great Vault reward row formatting (ilvl columns)

TaskTracker = TaskTracker or {}

-- Great Vault APIs are expensive; list rebuilds call this per vault row every refresh.
local vaultIlvlLineCache = {} -- [kind] = { text = string, a, b, c = slot strings, t = number }
local VAULT_ILVL_CACHE_TTL = 45
-- Vault data can be briefly unavailable (e.g. before the first WEEKLY_REWARDS_UPDATE after
-- login). Retry those soon instead of showing dashes for the full TTL.
local VAULT_ILVL_MISS_TTL = 2

function TaskTracker.InvalidateVaultIlvlCache()
    wipe(vaultIlvlLineCache)
end

local vaultInvFrame = CreateFrame("Frame")
vaultInvFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
vaultInvFrame:SetScript("OnEvent", function()
    TaskTracker.InvalidateVaultIlvlCache()
end)

local function vaultThresholdEnum(kind)
    local e = Enum and Enum.WeeklyRewardChestThresholdType
    if not e then return nil end
    if kind == "raid" then
        return e.Raid
    elseif kind == "dungeon" then
        -- Great Vault "Dungeons" row uses Activities (same as Blizzard_WeeklyRewards / landing page UIs).
        return e.Activities
    elseif kind == "world" then
        return e.World or e.Activities
    end
    return nil
end

local function sortByVaultIndex(a, b)
    return (a.index or 0) < (b.index or 0)
end

--- Resolve ilvl for one weekly-reward activity (handles empty links and upgrade preview).
local function activityIlvlString(activity, thresholdEnum)
    local dash = "-"
    if not activity or not activity.id then return dash end
    if not C_WeeklyRewards or not C_Item or not C_Item.GetDetailedItemLevelInfo then
        return dash
    end

    local link, upgradeLink
    if C_WeeklyRewards.GetExampleRewardItemHyperlinks then
        link, upgradeLink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
    end

    if type(link) == "string" and link ~= "" then
        local ilvl = C_Item.GetDetailedItemLevelInfo(link)
        if ilvl and ilvl > 0 then return tostring(ilvl) end
    end

    if type(upgradeLink) == "string" and upgradeLink ~= "" then
        local ilvl = C_Item.GetDetailedItemLevelInfo(upgradeLink)
        if ilvl and ilvl > 0 then return tostring(ilvl) end
    end

    local e = Enum and Enum.WeeklyRewardChestThresholdType
    if e and thresholdEnum and thresholdEnum ~= e.Raid
        and C_WeeklyRewards.GetNextActivitiesIncrease
        and activity.activityTierID ~= nil and activity.level ~= nil then
        local hasData, _, _, nextItemLevel = C_WeeklyRewards.GetNextActivitiesIncrease(
            activity.activityTierID, activity.level)
        if hasData and nextItemLevel and nextItemLevel > 0 then
            return tostring(nextItemLevel)
        end
    end

    return dash
end

local function emptyVaultSlotInfo()
    return { ilvl = "-", progress = 0, threshold = 0, unlocked = false }
end

--- Three Great Vault slots: preview ilvl plus run progress (same GetActivities pass as the ilvl row).
function TaskTracker.GetVaultSlotInfos(kind)
    -- C_WeeklyRewards during initial login (before PLAYER_ENTERING_WORLD) can hard-freeze the client.
    if not IsPlayerInWorld() then
        return emptyVaultSlotInfo(), emptyVaultSlotInfo(), emptyVaultSlotInfo()
    end
    if not C_WeeklyRewards or not C_WeeklyRewards.GetActivities then
        return emptyVaultSlotInfo(), emptyVaultSlotInfo(), emptyVaultSlotInfo()
    end
    local enumType = vaultThresholdEnum(kind)
    if not enumType then
        return emptyVaultSlotInfo(), emptyVaultSlotInfo(), emptyVaultSlotInfo()
    end
    local acts = C_WeeklyRewards.GetActivities(enumType)
    if not acts or #acts == 0 then
        return emptyVaultSlotInfo(), emptyVaultSlotInfo(), emptyVaultSlotInfo()
    end
    local sorted = {}
    for i, a in ipairs(acts) do
        sorted[i] = a
    end
    table.sort(sorted, sortByVaultIndex)

    local function infoAt(i)
        local a = sorted[i]
        if not a then return emptyVaultSlotInfo() end
        local progress = tonumber(a.progress) or 0
        local threshold = tonumber(a.threshold) or 0
        return {
            ilvl = activityIlvlString(a, enumType),
            progress = progress,
            threshold = threshold,
            unlocked = threshold > 0 and progress >= threshold,
        }
    end

    return infoAt(1), infoAt(2), infoAt(3)
end

--- Returns three strings for the first three vault reward tiers (or "-" if unknown).
function TaskTracker.GetVaultSlotIlvls(kind)
    local a, b, c = TaskTracker.GetVaultSlotInfos(kind)
    return a.ilvl, b.ilvl, c.ilvl
end

--- Cache slot for `kind`, refreshed from the game only when the TTL has expired.
--- `GetVaultSlotIlvls` scans C_WeeklyRewards activities and queries item levels, and the
--- M+ hint path calls it several times per registry-sync tick, so every reader goes
--- through here rather than populating only when the vault row happens to be painted.
local function ensureVaultIlvlSlot(kind)
    local now = GetTime()
    local slot = vaultIlvlLineCache[kind]
    if slot then
        local resolved = slot.a ~= nil and slot.b ~= nil and slot.c ~= nil
        if (now - slot.t) <= (resolved and VAULT_ILVL_CACHE_TTL or VAULT_ILVL_MISS_TTL) then
            return slot
        end
    end
    local i1, i2, i3 = TaskTracker.GetVaultSlotInfos(kind)
    slot = {
        a = i1.ilvl,
        b = i2.ilvl,
        c = i3.ilvl,
        infos = { i1, i2, i3 },
        text = string.format("%s / %s / %s", i1.ilvl or "-", i2.ilvl or "-", i3.ilvl or "-"),
        t = now,
    }
    vaultIlvlLineCache[kind] = slot
    return slot
end

--- Same ilvl triple the vault row displays (avoids M+ hints reading "-" while the vault row shows cached numbers).
function TaskTracker.GetVaultSlotIlvlsCached(kind)
    local slot = ensureVaultIlvlSlot(kind)
    return slot.a, slot.b, slot.c
end

--- Cached { ilvl, progress, threshold, unlocked } for the first three slots of `kind`.
function TaskTracker.GetVaultSlotInfosCached(kind)
    local slot = ensureVaultIlvlSlot(kind)
    return slot.infos
end

--- Single line for display: "ilvl / ilvl / ilvl" (spaces around slashes).
function TaskTracker.FormatVaultIlvlRow(kind)
    return ensureVaultIlvlSlot(kind).text
end

-- Season raid lockouts. Boss rows use killed/total. Vault rows use how many raid
-- vault slots those kills fill (2 / 4 / 6 bosses this season). One scan is shared.
local RAID_LOCKOUT_TTL = 2
local raidLockoutCache
local RAID_VAULT_THRESHOLDS_FALLBACK = { 2, 4, 6 }

local function raidSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function raidPublicNum(v)
    if v == nil or raidSecret(v) then return nil end
    local n = tonumber(v)
    if n and n >= 0 then
        return math.floor(n + 0.5)
    end
end

function TaskTracker.InvalidateRaidLockoutCache()
    raidLockoutCache = nil
end

--- Ask the server for saved instances. Safe to call again; skipped in combat.
function TaskTracker.RequestRaidLockouts()
    if not IsPlayerInWorld() then return end
    if InCombatLockdown and InCombatLockdown() then
        TaskTracker._ttRaidInfoPending = true
        return
    end
    TaskTracker._ttRaidInfoPending = nil
    if RequestRaidInfo then
        RequestRaidInfo()
    end
end

local function raidNameHas(name, needle)
    if raidSecret(name) or type(name) ~= "string" then return false end
    if type(needle) ~= "string" or needle == "" then return false end
    return name:lower():find(needle:lower(), 1, true) ~= nil
end

local function killedOnLockout(index, encounterProgress, numEncounters)
    local killed = raidPublicNum(encounterProgress)
    if killed ~= nil then return killed end
    if not GetSavedInstanceEncounterInfo or not numEncounters or numEncounters < 1 then
        return 0
    end
    killed = 0
    for e = 1, numEncounters do
        local a, _, c = GetSavedInstanceEncounterInfo(index, e)
        local dead = (type(a) == "boolean" and a) or c
        if dead and not raidSecret(dead) then
            killed = killed + 1
        end
    end
    return killed
end

local function ensureRaidLockouts()
    if not IsPlayerInWorld() then return nil end
    local now = GetTime()
    if raidLockoutCache and (now - raidLockoutCache.t) <= RAID_LOCKOUT_TTL then
        return raidLockoutCache
    end
    local list = {}
    if GetNumSavedInstances and GetSavedInstanceInfo then
        local n = raidPublicNum(GetNumSavedInstances()) or 0
        for i = 1, n do
            local name, _, _, difficultyId, _, _, _, isRaid, _, _, numEncounters, encounterProgress =
                GetSavedInstanceInfo(i)
            if not raidSecret(name) and not raidSecret(difficultyId) and (isRaid == true or isRaid == 1) then
                local diff = raidPublicNum(difficultyId)
                local total = raidPublicNum(numEncounters)
                if diff and total and total > 0 and type(name) == "string" then
                    list[#list + 1] = {
                        name = name,
                        diff = diff,
                        killed = killedOnLockout(i, encounterProgress, total),
                        total = total,
                    }
                end
            end
        end
    end
    raidLockoutCache = { t = now, list = list }
    return raidLockoutCache
end

--- Great Vault raid slot thresholds (bosses required). Falls back to 2, 4, 6.
function TaskTracker.RaidVaultThresholds()
    local infos = TaskTracker.GetVaultSlotInfosCached and TaskTracker.GetVaultSlotInfosCached("raid")
    local th = {}
    if infos then
        for i = 1, 3 do
            local n = infos[i] and raidPublicNum(infos[i].threshold)
            if n and n > 0 then
                th[#th + 1] = n
            end
        end
    end
    if #th < 1 then
        return RAID_VAULT_THRESHOLDS_FALLBACK
    end
    return th
end

local function lockoutFor(entry)
    local cache = ensureRaidLockouts()
    if not cache or not entry then return nil end
    local diff = raidPublicNum(entry.raidDifficulty)
    if not diff then return nil end
    for i = 1, #cache.list do
        local row = cache.list[i]
        if row.diff == diff and raidNameHas(row.name, entry.raidInstanceName) then
            return row
        end
    end
end

--- killed, total for a boss row, or slots filled, slot count for a vault row.
--- Also writes entry.max so the list cap matches this week's raid.
function TaskTracker.RaidRowProgress(entry)
    if not entry or not entry.raidTrack then return nil end
    local row = lockoutFor(entry)
    local killed = row and row.killed or 0
    if entry.raidTrack == "vault" then
        local th = TaskTracker.RaidVaultThresholds()
        local slots = 0
        for i = 1, #th do
            if killed >= th[i] then
                slots = slots + 1
            end
        end
        entry.max = #th
        return slots, #th
    end
    local total = (row and row.total) or raidPublicNum(entry.raidBossCount) or raidPublicNum(entry.max) or 1
    if total < 1 then total = 1 end
    if killed > total then killed = total end
    entry.max = total
    return killed, total
end
