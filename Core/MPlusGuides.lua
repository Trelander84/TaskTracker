-- Core/MPlusGuides.lua
-- Mythic+ end-of-dungeon and Great Vault (dungeons) ilvl hints (Seasonal Activities → Mythic+; mirror under Power).

TaskTracker = TaskTracker or {}

--- Legacy registry / advanced-task pack id (removed from registry; still used to purge old tasks).
TaskTracker.MPLUS_LEGACY_PACK_SOURCE_ID = "seasonal_mplus_dungeon_guides"
TaskTracker.MPLUS_GUIDE_PACK_ENTRY_ID = TaskTracker.MPLUS_LEGACY_PACK_SOURCE_ID
TaskTracker.MPLUS_SEASONAL_GROUP_NAME = "Dungeons"
-- Legacy empty shell groups under Power / Seasonal.
TaskTracker.MPLUS_GUIDE_GROUP_NAME = "Mythic+ hints"

local LEGACY_PACK_GROUP_NAMES = {
    "Mythic+ Dungeons",
    "End Game Content",
}

-- Key order and reward ilvls — Midnight Season 2 (12.1).
-- EOD / dungeon vault from Wowhead, Icy Veins, and warcraft.wiki.gg (M0 from the wiki).
-- +11/+12 do not raise ilvl past +10.
local MPLUS_ROWS = {
    { key = 0,  eod = 292, vault = 302 },
    { key = 2,  eod = 295, vault = 305 },
    { key = 3,  eod = 295, vault = 305 },
    { key = 4,  eod = 298, vault = 308 },
    { key = 5,  eod = 302, vault = 308 },
    { key = 6,  eod = 305, vault = 311 },
    { key = 7,  eod = 305, vault = 315 },
    { key = 8,  eod = 308, vault = 315 },
    { key = 9,  eod = 308, vault = 315 },
    { key = 10, eod = 311, vault = 318 },
}

local function formatKey(key)
    if key == 0 then return "M0", "Mythic 0" end
    return "+" .. tostring(key), "+" .. tostring(key)
end

--- Lowest key row where end-of-dungeon ilvl is strictly greater than playerIlvl. Returns key, eodIlvl, vaultIlvl or nils.
function TaskTracker.GetMPlusFirstEndDungeonUpgrade(playerIlvl)
    local p = tonumber(playerIlvl)
    if not p or p < 0 then return nil end
    for _, row in ipairs(MPLUS_ROWS) do
        if row.eod > p then
            return row.key, row.eod, row.vault
        end
    end
    return nil
end

--- Lowest key row where Great Vault dungeon ilvl is strictly greater than slotIlvl.
function TaskTracker.GetMPlusFirstVaultUpgrade(slotIlvl)
    local s = tonumber(slotIlvl)
    if not s or s < 0 then return nil end
    for _, row in ipairs(MPLUS_ROWS) do
        if row.vault > s then
            return row.key, row.vault
        end
    end
    return nil
end

function TaskTracker.MPlusEndDungeonHintInactive()
    local ilvl = TaskTracker.GetPowerProgressItemLevel and TaskTracker.GetPowerProgressItemLevel()
    if not ilvl then return false end
    return TaskTracker.GetMPlusFirstEndDungeonUpgrade(ilvl) == nil
end

local function getDungeonVaultSlotTriple()
    if TaskTracker.GetVaultSlotIlvlsCached then
        return TaskTracker.GetVaultSlotIlvlsCached("dungeon")
    end
    return TaskTracker.GetVaultSlotIlvls("dungeon")
end

--- Numeric preview ilvls for filled dungeon vault slots (empty / "-" are skipped, not 0).
local function filledDungeonVaultIlvls()
    local a, b, c = getDungeonVaultSlotTriple()
    local filled, n = {}, 0
    for _, s in ipairs({ a, b, c }) do
        local eff = TaskTracker.VaultDungeonSlotEffectiveIlvl(s)
        if eff ~= nil then
            n = n + 1
            filled[n] = eff
        end
    end
    return filled, n
end

--- Vault hint compare: same as EOD (lowest equipped / Details override). Empty slots are
--- not treated as 0 — that recommended +0 / 302 even when gear was already higher.
--- If all three slots have a preview, also consider the weakest filled slot so a vault
--- already above your gear can complete at the +10 cap.
local function vaultHintCompareIlvl()
    local player = TaskTracker.GetPowerProgressItemLevel and TaskTracker.GetPowerProgressItemLevel()
    local filled, nFilled = filledDungeonVaultIlvls()
    if nFilled == 3 then
        local weakest = filled[1]
        for i = 2, 3 do
            if filled[i] < weakest then weakest = filled[i] end
        end
        if player then
            if weakest > player then return weakest end
            return player
        end
        return weakest
    end
    return player
end

--- Parsed preview ilvl for a vault slot string, or nil for "-" / empty / unparseable (do not treat "-" as 0 for hints).
function TaskTracker.VaultDungeonSlotEffectiveIlvl(slotString)
    if not slotString or slotString == "" or slotString == "-" then
        return nil
    end
    local n = tonumber(tostring(slotString):match("^%s*(.-)%s*$"))
    if not n or n < 0 then return nil end
    return n
end

function TaskTracker.MPlusVaultHintInactive()
    local compare = vaultHintCompareIlvl()
    if compare == nil then return false end
    return TaskTracker.GetMPlusFirstVaultUpgrade(compare) == nil
end

--- True when the vault chart has no upgrade vs the comparison ilvl (gear, or weakest filled slot when all three are filled).
function TaskTracker.MPlusVaultRegistryAutoMaxed()
    return TaskTracker.MPlusVaultHintInactive()
end

--- Registry row: treat 1/1 as reached when the hint has no further ilvl upgrades at +10 cap.
function TaskTracker.MPlusRegistryHintIsAutoMaxed(entry)
    if not entry or entry.type ~= "mplus_hint_row" then return false end
    if entry.mplusHintKind == "end_dungeon" then
        return TaskTracker.MPlusEndDungeonHintInactive and TaskTracker.MPlusEndDungeonHintInactive()
    end
    if entry.mplusHintKind == "vault" then
        return TaskTracker.MPlusVaultRegistryAutoMaxed and TaskTracker.MPlusVaultRegistryAutoMaxed()
    end
    return false
end

function TaskTracker.MPlusHintIsAutoInactive(node)
    if not node or node.type ~= "task" or not TaskTracker.IsAdvancedTask(node) then return false end
    local a = node.advanced
    if not a or a.type ~= "mplus_hint" then return false end
    if a.mplusHintKind == "end_dungeon" then
        return TaskTracker.MPlusEndDungeonHintInactive()
    elseif a.mplusHintKind == "vault" then
        return TaskTracker.MPlusVaultHintInactive()
    end
    return false
end

function TaskTracker.FormatMPlusEndDungeonTitle()
    local ilvl = TaskTracker.GetPowerProgressItemLevel and TaskTracker.GetPowerProgressItemLevel()
    if not ilvl then
        return "Run Mythic+ for end-of-dungeon gear (ilvl loading…)"
    end
    local key, targetEod = TaskTracker.GetMPlusFirstEndDungeonUpgrade(ilvl)
    if not key then
        return "Mythic+ end chest: no ilvl upgrades at +10 cap"
    end
    local short, long = formatKey(key)
    if key == 0 then
        return string.format("Run %s or higher (next end chest ilvl %s)", long, tostring(targetEod))
    end
    return string.format("Run Mythic+ at %s or higher (next end chest ilvl %s)", short, tostring(targetEod))
end

function TaskTracker.FormatMPlusVaultTitle()
    return "Mythic+ Great Vault (dungeons): fill slots / raise ilvl"
end

--- Second line under the static registry label (title + subtitle layout).
function TaskTracker.GetMPlusRegistryRowSubtitle(entry)
    if not entry or entry.type ~= "mplus_hint_row" then return nil end
    if entry.mplusHintKind == "end_dungeon" then
        return TaskTracker.GetMPlusEndDungeonSubtitle()
    elseif entry.mplusHintKind == "vault" then
        return TaskTracker.GetMPlusVaultHintSubtitle()
    end
    return nil
end

local function formatRunKeyPlus(key)
    if key == nil then return "+?" end
    if key == 0 then return "+0" end
    return "+" .. tostring(key)
end

function TaskTracker.GetMPlusVaultHintSubtitle()
    local compare = vaultHintCompareIlvl()
    if compare == nil then
        return "Run +? for ilvl ?+ (comparison ilvl loading…)"
    end
    local key, targetVault = TaskTracker.GetMPlusFirstVaultUpgrade(compare)
    if not key then
        return "No dungeon vault ilvl upgrade at +10 cap"
    end
    return string.format("Run %s for ilvl %s+", formatRunKeyPlus(key), tostring(targetVault))
end

function TaskTracker.GetMPlusEndDungeonSubtitle()
    local ilvl = TaskTracker.GetPowerProgressItemLevel and TaskTracker.GetPowerProgressItemLevel()
    if not ilvl then
        return "Run +? for ilvl ?+ (comparison ilvl loading…)"
    end
    local key, targetEod = TaskTracker.GetMPlusFirstEndDungeonUpgrade(ilvl)
    if not key then
        return "No end-chest upgrade at +10 cap"
    end
    return string.format("Run %s for ilvl %s+", formatRunKeyPlus(key), tostring(targetEod))
end

function TaskTracker.GetAdvancedTaskDisplayTitle(node)
    if not node or node.type ~= "task" or not TaskTracker.IsAdvancedTask(node) then
        return nil
    end
    local a = node.advanced
    if not a or a.type ~= "mplus_hint" then return nil end
    if a.mplusHintKind == "end_dungeon" then
        return TaskTracker.FormatMPlusEndDungeonTitle()
    elseif a.mplusHintKind == "vault" then
        return TaskTracker.FormatMPlusVaultTitle()
    end
    return nil
end

function TaskTracker.GetTaskListTitlePlain(node)
    if not node or node.type ~= "task" then return "" end
    local dyn = TaskTracker.GetAdvancedTaskDisplayTitle(node)
    if dyn and dyn ~= "" then return dyn end
    return node.name or ""
end

local function purgePackTasksEverywhere(packId)
    local ids = {}
    TaskTracker.WalkTree(function(node)
        if node.type == "task" and node.advanced and node.advanced.type == "mplus_hint"
            and node.advanced.packSource == packId then
            ids[#ids + 1] = node.id
        end
    end)
    for i = #ids, 1, -1 do
        TaskTracker.RemoveNode(ids[i])
    end
end

local function removeOneEmptyNamedGroup(root, name)
    local hit
    local function walk(n, parent, idx)
        if hit then return end
        if n.type == "group" and n.name == name and parent and (#(n.children or {}) == 0) then
            hit = { parent = parent, idx = idx }
            return
        end
        for i, ch in ipairs(n.children or {}) do
            walk(ch, n, i)
        end
    end
    walk(root, nil, nil)
    if hit then
        table.remove(hit.parent.children, hit.idx)
        return true
    end
    return false
end

local function pruneEmptyPackShellGroups(root)
    for _, name in ipairs(LEGACY_PACK_GROUP_NAMES) do
        while removeOneEmptyNamedGroup(root, name) do end
    end
    while removeOneEmptyNamedGroup(root, TaskTracker.MPLUS_GUIDE_GROUP_NAME) do end
end

function TaskTracker.SyncMPlusDungeonGuidesPackTree()
    local db = TaskTrackerDB
    if not db or not db.tree then return end
    local packId = TaskTracker.MPLUS_LEGACY_PACK_SOURCE_ID or "seasonal_mplus_dungeon_guides"
    -- Legacy: hints were advanced tasks under Power; hints are registry rows under Seasonal → Mythic+.
    purgePackTasksEverywhere(packId)
    pruneEmptyPackShellGroups(db.tree)
end
