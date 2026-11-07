-- Core/Engine.lua
-- Registry engine: quest checking, progress calculation, override logic
-- All progress is calculated recursively from the tree

TaskTracker = TaskTracker or {}

local function IsPowerModuleGroup(node)
    return node and node.type == "group" and node.moduleGroupKey == "power"
end

function TaskTracker.RegistryRowIsDisplayOnly(entry)
    return entry and entry.type == "vault_row"
end

--- Weekly registry rows that list multiple possible quest ids (rotating weeklies, etc.):
--- IsQuestFlaggedCompleted can stay true for ids not offered this week. Each character
--- remembers the ids already flagged the first time that character is seen this period
--- (`GetCharWeeklyQuestDelta`). A stuck flag does not count. A turn-in this period does,
--- including another finish of an id that was already flagged. The quest can be done on every alt.
function TaskTracker.RegistryEntryUsesWeeklyQuestDelta(entry)
    if not entry or entry.reset ~= "weekly" or not entry.quests then return false end
    local n = entry._ttQuestCount
    if n == nil then
        n = 0
        for _ in pairs(entry.quests) do
            n = n + 1
        end
    end
    return n > 1
end

--- Weekly quest_complete: remember first completion this period; ignore later quest-flag clears (tracking quests, etc.).
function TaskTracker.RegistryEntryLatchesWeeklyQuestComplete(entry)
    return entry and entry.type == "quest_complete" and entry.reset == "weekly" and entry.latchWeeklyQuestComplete == true
end

function TaskTracker.RegistryEntryAnyQuestFlaggedComplete(entry)
    if not entry or not entry.quests or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        return false
    end
    for qid in pairs(entry.quests) do
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
        if ok and done then
            return true
        end
    end
    return false
end

function TaskTracker.GetRegistryQuestSetCompletedCount(entry)
    if not entry or not entry.quests or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        return 0
    end
    local c = 0
    for qid in pairs(entry.quests) do
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
        if ok and done then
            c = c + 1
        end
    end
    return c
end

--- Journal/toy-box ownership for collectable_owned registry rows (does not change the 12.0 catalog).
function TaskTracker.IsRegistryCollectableOwned(entry)
    if type(entry) ~= "table" then return false end
    local kind = tostring(entry.collectableKind or ""):lower()
    if TaskTracker.IsCatalogCollectableOwned
        and TaskTracker.IsCatalogCollectableOwned(entry, kind) == true then
        return true
    end
    if TaskTracker.RegistryEntryAnyQuestFlaggedComplete
        and TaskTracker.RegistryEntryAnyQuestFlaggedComplete(entry) then
        return true
    end
    return false
end

--- True when a row has requireOwnedRegistryId and that collectable is not owned yet.
function TaskTracker.IsRegistryRequireOwnedLocked(entry)
    if type(entry) ~= "table" or not entry.requireOwnedRegistryId then return false end
    local need = TaskTracker.RegistryByID and TaskTracker.RegistryByID[entry.requireOwnedRegistryId]
    return not TaskTracker.IsRegistryCollectableOwned(need)
end

function TaskTracker.IsCollectionsModuleEntry(entry)
    if type(entry) ~= "table" then return false end
    local sub = tostring(entry.subsection or "")
    return sub:find("_collections_", 1, true) ~= nil
end

--- Toy/mount/pet journaled, or reputation at max rank, under Collections.
function TaskTracker.IsCollectionsModuleEntryComplete(entry)
    if not TaskTracker.IsCollectionsModuleEntry(entry) then return false end
    if entry.type == "collectable_owned" then
        if TaskTracker.IsRegistryCollectableOwned(entry) == true then return true end
        local aid = tonumber(entry.achievementId)
        if aid and aid > 0 and GetAchievementInfo then
            local ok, _, _, _, completed = pcall(GetAchievementInfo, aid)
            if ok and completed then return true end
        end
        return false
    end
    if entry.type == "reputation_standing" and TaskTracker.GetRegistryReputationStanding then
        local cur, max = TaskTracker.GetRegistryReputationStanding(entry)
        max = tonumber(max) or 0
        cur = tonumber(cur) or 0
        return max > 0 and cur >= max
    end
    return false
end

--- Collected Collections rows stay off the list unless the player overrides in Modules.
function TaskTracker.IsCollectionsModuleRowHidden(entry)
    if not TaskTracker.IsCollectionsModuleEntryComplete(entry) then return false end
    if TaskTracker.IsCollectionsShowCollectedOverride and TaskTracker.IsCollectionsShowCollectedOverride(entry.id) then
        return false
    end
    return true
end

--- Friendship ranks: API table uses currentLevel/maxLevel (not currentRank/maxRank).
local function friendshipRanksForFaction(factionId)
    local fid = tonumber(factionId)
    if not fid or fid <= 0 then return 0, 0 end
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local okFr, fr = pcall(C_GossipInfo.GetFriendshipReputation, fid)
        if okFr and type(fr) == "table" then
            local nested = tonumber(fr.friendshipFactionID)
            if nested and nested > 0 then fid = nested end
        end
    end
    if not (C_GossipInfo and C_GossipInfo.GetFriendshipReputationRanks) then
        return 0, 0
    end
    local ok, a, b = pcall(C_GossipInfo.GetFriendshipReputationRanks, fid)
    if not ok then return 0, 0 end
    local cur, max = 0, 0
    if type(a) == "table" then
        cur = tonumber(a.currentLevel) or tonumber(a.currentRank) or 0
        max = tonumber(a.maxLevel) or tonumber(a.maxRank) or 0
    else
        cur = tonumber(a) or 0
        max = tonumber(b) or 0
    end
    return cur, max
end

--- Aqir Research Enclave (faction 2838) is friendship, not the 42000 classic bar.
--- Rank 5 is Exalted. The bar finishes at 5000 even if standing/maxRep still report the full bar.
function TaskTracker.AqirEnclaveReputationBar()
    local cap = 5000
    local curRank, maxRank = friendshipRanksForFaction(2838)
    if maxRank > 0 and curRank >= maxRank then
        return cap, cap
    end
    local standing = 0
    if TaskTracker.GetAdvancedFactionData then
        local fd = TaskTracker.GetAdvancedFactionData(2838)
        if fd then
            standing = tonumber(fd.friendshipStanding)
            if standing == nil then
                standing = tonumber(fd.currentStanding or fd.currentRep) or 0
            else
                local bottom = tonumber(fd.friendshipThreshold) or 0
                if standing < bottom then
                    standing = bottom + standing
                end
            end
        end
    end
    standing = math.floor(tonumber(standing) or 0)
    if standing < 0 then standing = 0 end
    if maxRank > 0 and curRank < maxRank and standing >= cap then
        standing = cap - 1
    elseif standing > cap then
        standing = cap
    end
    return standing, cap
end

--- Current / cap for reputation_standing rows. Renown uses major-faction level; friendship uses ranks.
function TaskTracker.GetRegistryReputationStanding(entry)
    local max = math.max(1, math.floor(tonumber(entry and entry.max) or 1))
    local fid = tonumber(entry and entry.factionId)
    if not fid or fid <= 0 then return 0, max end
    if fid == 2838 and TaskTracker.AqirEnclaveReputationBar then
        return TaskTracker.AqirEnclaveReputationBar()
    end
    local kind = tostring(entry.repKind or "standing"):lower()
    local cur = 0
    if kind == "classic" then
        if TaskTracker.GetAdvancedFactionData then
            local fd = TaskTracker.GetAdvancedFactionData(fid)
            if fd and fd.friendshipStanding ~= nil then
                cur = fd.friendshipStanding
                local cap = tonumber(fd.friendshipMax)
                if cap and cap > 0 then max = cap end
            else
                cur = tonumber(fd and (fd.currentStanding or fd.currentRep)) or 0
            end
        end
        max = math.max(1, math.floor(max))
    elseif kind == "renown" then
        if TaskTracker.GetAdvancedFactionData then
            local fd = TaskTracker.GetAdvancedFactionData(fid)
            if fd then
                cur = tonumber(fd.renownLevel) or 0
                local rm = tonumber(fd.renownMaxLevel)
                if rm and rm > 0 then max = rm end
            end
        end
        if cur == 0 and C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel then
            local ok, lvl = pcall(C_MajorFactions.GetCurrentRenownLevel, fid)
            if ok then cur = tonumber(lvl) or 0 end
        end
        if max < 1 then max = math.max(1, tonumber(entry.max) or 20) end
    elseif kind == "friendship" then
        local rcur, rmax = friendshipRanksForFaction(fid)
        cur = rcur
        if rmax and rmax > 0 then max = rmax end
    else
        if TaskTracker.GetAdvancedFactionData then
            local fd = TaskTracker.GetAdvancedFactionData(fid)
            cur = tonumber(fd and fd.reaction) or 0
        end
    end
    cur = math.floor(cur)
    if cur < 0 then cur = 0 end
    if cur > max then cur = max end
    return cur, max
end

local function fmtPurchaseAmt(n)
    n = math.floor(tonumber(n) or 0)
    if n < 0 then n = 0 end
    if BreakUpLargeNumbers then
        local ok, s = pcall(BreakUpLargeNumbers, n)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return tostring(n)
end

local function currencyNameAndQty(currencyId)
    local name, qty = nil, 0
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyId)
        if ok and type(info) == "table" then
            if type(info.name) == "string" and info.name ~= "" then name = info.name end
            qty = tonumber(info.quantity) or 0
        end
    end
    return name or ("Currency " .. tostring(currencyId)), qty
end

local function factionDisplayName(factionId, fallback)
    if TaskTracker.GetAdvancedFactionData then
        local fd = TaskTracker.GetAdvancedFactionData(factionId)
        if fd and type(fd.name) == "string" and fd.name ~= "" then return fd.name end
    end
    return fallback or ("Faction " .. tostring(factionId))
end

local function friendshipRank(factionId)
    return friendshipRanksForFaction(factionId)
end

local function itemNameAndCount(itemId)
    local name
    if C_Item and C_Item.GetItemNameByID then
        local ok, n = pcall(C_Item.GetItemNameByID, itemId)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    if not name and GetItemInfo then
        local ok, n = pcall(GetItemInfo, itemId)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    local count = TaskTracker.ItemCount and TaskTracker.ItemCount(itemId, true) or 0
    return name or ("Item " .. tostring(itemId)), count
end

local KIND_LABEL = {
    mount = "Mount",
    pet = "Pet",
    toy = "Toy",
    item = "Item",
    appearance = "Appearance",
    housing = "Housing",
    recipe = "Recipe",
}

local SPEND_NAME_MAX = 22

local function truncateSpendName(s, maxChars)
    maxChars = maxChars or SPEND_NAME_MAX
    if type(s) ~= "string" or s == "" then return "" end
    local n, i, len = 0, 1, #s
    while i <= len do
        local c = s:byte(i)
        local charLen = 1
        if c and c >= 240 then
            charLen = 4
        elseif c and c >= 224 then
            charLen = 3
        elseif c and c >= 192 then
            charLen = 2
        end
        n = n + 1
        if n > maxChars then
            return s:sub(1, i - 1) .. "…"
        end
        i = i + charLen
    end
    return s
end

local function isPlaceholderItemName(s, itemId)
    if type(s) ~= "string" or s == "" then return true end
    local trimmed = s:match("^%s*(.-)%s*$") or s
    if trimmed:match("^%d+$") then return true end
    if itemId and (trimmed == tostring(itemId) or trimmed == ("Item " .. tostring(itemId))) then
        return true
    end
    return false
end

local function requestItemName(itemId)
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemId)
    end
end

local function liveItemName(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return nil end
    if C_Item and C_Item.GetItemNameByID then
        local ok, n = pcall(C_Item.GetItemNameByID, itemId)
        if ok and type(n) == "string" and not isPlaceholderItemName(n, itemId) then return n end
    end
    if GetItemInfo then
        local ok, n = pcall(GetItemInfo, itemId)
        if ok and type(n) == "string" and not isPlaceholderItemName(n, itemId) then return n end
    end
    return nil
end

--- Live name + mount/pet/toy when the client knows the item. Requests load if the name is not ready.
local function liveCollectableNameAndKind(itemId, hintKind)
    itemId = tonumber(itemId)
    local kind = hintKind
    if not itemId or itemId <= 0 then return nil, kind end
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local ok, toyItemId, toyName = pcall(C_ToyBox.GetToyInfo, itemId)
        if ok and tonumber(toyItemId) and type(toyName) == "string" and not isPlaceholderItemName(toyName, itemId) then
            return toyName, "toy"
        end
    end
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local ok, mid = pcall(C_MountJournal.GetMountFromItem, itemId)
        if ok and mid and mid > 0 and C_MountJournal.GetMountInfoByID then
            local ok2, mname = pcall(C_MountJournal.GetMountInfoByID, mid)
            if ok2 and type(mname) == "string" and mname ~= "" then
                return mname, "mount"
            end
        end
    end
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local packed = { pcall(C_PetJournal.GetPetInfoByItemID, itemId) }
        if packed[1] == true then
            local pname = packed[2]
            if type(pname) == "string" and not isPlaceholderItemName(pname, itemId) then
                return pname, "pet"
            end
        end
    end
    local name = liveItemName(itemId)
    if name then return name, kind or "item" end
    requestItemName(itemId)
    return nil, kind
end

function TaskTracker.IsAttDataEnabled()
    return not TaskTrackerDB or TaskTrackerDB.attDataEnabled ~= false
end

function TaskTracker.IsAllTheThingsLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "AllTheThings")
        if ok and loaded then return true end
    end
    if IsAddOnLoaded then
        local ok, loaded = pcall(IsAddOnLoaded, "AllTheThings")
        if ok and loaded then return true end
    end
    return type(_G.ATTC) == "table" or type(_G.AllTheThings) == "table"
end

-- Journey ranks that are neither friendship nor a major faction. Nil means the
-- client did not report a rank; callers fail closed instead of treating that as 0.
local function readJourneyRank(factionId)
    factionId = tonumber(factionId)
    if not factionId or factionId <= 0 then return nil end
    local cur, max = friendshipRanksForFaction(factionId)
    if max and max > 0 then return tonumber(cur) or 0 end
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local ok, data = pcall(C_MajorFactions.GetMajorFactionData, factionId)
        if ok and type(data) == "table" and data.renownLevel ~= nil then
            if issecretvalue and issecretvalue(data.renownLevel) then return nil end
            local lvl = tonumber(data.renownLevel)
            if lvl then return lvl end
        end
    end
    if C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel then
        local ok, lvl = pcall(C_MajorFactions.GetCurrentRenownLevel, factionId)
        if ok and lvl ~= nil and not (issecretvalue and issecretvalue(lvl)) then
            lvl = tonumber(lvl)
            if lvl then return lvl end
        end
    end
    return nil
end

local function publicRankNumber(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return tonumber(v)
end

-- Current renown and the faction cap. Nil when the client does not report that number.
local function renownProgress(factionId)
    local cur, max, name
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local ok, data = pcall(C_MajorFactions.GetMajorFactionData, factionId)
        if ok and type(data) == "table" then
            if type(data.name) == "string" and data.name ~= "" then name = data.name end
            cur = publicRankNumber(data.renownLevel)
            max = publicRankNumber(data.maxRenownLevel or data.maxRenownLevelAvailable)
        end
    end
    if (not max or max <= 0) and C_MajorFactions and C_MajorFactions.GetRenownLevels then
        local ok, levels = pcall(C_MajorFactions.GetRenownLevels, factionId)
        if ok and type(levels) == "table" then
            local cap = 0
            for i = 1, #levels do
                local row = levels[i]
                local lvl = type(row) == "table" and publicRankNumber(row.level) or nil
                if lvl and lvl > cap then cap = lvl end
            end
            if cap <= 0 then cap = #levels end
            if cap > 0 then max = cap end
        end
    end
    if cur == nil and C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel then
        local ok, lvl = pcall(C_MajorFactions.GetCurrentRenownLevel, factionId)
        if ok then cur = publicRankNumber(lvl) end
    end
    return cur, max, name
end

--- One standing line for a vendor row: "Preyhunter's Journey, Renown 3/10".
function TaskTracker.FactionStandingLine(factionId, label, reqType)
    factionId = tonumber(factionId)
    if not factionId or factionId <= 0 then return nil end
    local name = label
    if type(name) ~= "string" or name == "" then
        name = factionDisplayName(factionId, nil)
    end
    local kind = tostring(reqType or ""):lower()
    if kind == "friendship" then
        local cur, max = friendshipRanksForFaction(factionId)
        cur = publicRankNumber(cur)
        max = publicRankNumber(max)
        if cur and max and max > 0 then
            return string.format("%s, Rank %d/%d", name, cur, max)
        end
    end
    local cur, max, apiName = renownProgress(factionId)
    if (type(label) ~= "string" or label == "") and apiName then name = apiName end
    if cur and max and max > 0 then
        return string.format("%s, Renown %d/%d", name, cur, max)
    end
    if cur then
        return string.format("%s, Renown %d", name, cur)
    end
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local function evaluatePurchaseReq(req)
    if type(req) ~= "table" then return nil end
    local kind = tostring(req.type or ""):lower()
    if kind == "renown" then
        local need = math.max(1, math.floor(tonumber(req.min) or 1))
        local fake = { factionId = req.factionId, repKind = "renown", max = need }
        local cur = select(1, TaskTracker.GetRegistryReputationStanding(fake))
        cur = tonumber(cur) or 0
        local fac = factionDisplayName(req.factionId, req.label)
        return {
            text = string.format("Renown %s — %s  (%s/%s)", fmtPurchaseAmt(need), fac, fmtPurchaseAmt(cur), fmtPurchaseAmt(need)),
            met = cur >= need,
        }
    elseif kind == "friendship" then
        local need = math.max(1, math.floor(tonumber(req.min) or 1))
        local cur = friendshipRank(req.factionId)
        local fac = factionDisplayName(req.factionId, req.label)
        local rank = req.rankName
        if type(rank) ~= "string" or rank == "" then
            rank = "Rank " .. tostring(need)
        end
        return {
            text = string.format("%s — %s  (%s/%s)", rank, fac, fmtPurchaseAmt(cur), fmtPurchaseAmt(need)),
            met = cur >= need,
        }
    elseif kind == "journey" then
        local need = math.max(1, math.floor(tonumber(req.min) or 1))
        local cur = readJourneyRank(req.factionId)
        local fac = req.label
        if type(fac) ~= "string" or fac == "" then
            fac = factionDisplayName(req.factionId, nil)
        end
        if cur == nil then
            return {
                text = string.format("%s %s", fac, fmtPurchaseAmt(need)),
                met = false,
            }
        end
        return {
            text = string.format("%s %s  (%s/%s)", fac, fmtPurchaseAmt(need), fmtPurchaseAmt(cur), fmtPurchaseAmt(need)),
            met = cur >= need,
        }
    elseif kind == "currency" then
        local cid = tonumber(req.currencyId)
        local need = math.max(0, math.floor(tonumber(req.amount) or 0))
        if not cid or cid <= 0 then return nil end
        local name, qty = currencyNameAndQty(cid)
        return {
            text = string.format("%s %s  (%s/%s)", fmtPurchaseAmt(need), name, fmtPurchaseAmt(qty), fmtPurchaseAmt(need)),
            met = qty >= need,
        }
    elseif kind == "gold" then
        local need = math.max(0, math.floor(tonumber(req.amount) or 0))
        local have = 0
        if GetMoney then
            local ok, copper = pcall(GetMoney)
            if ok then have = math.floor((tonumber(copper) or 0) / 10000) end
        end
        return {
            text = string.format("%s Gold  (%s/%s)", fmtPurchaseAmt(need), fmtPurchaseAmt(have), fmtPurchaseAmt(need)),
            met = have >= need,
        }
    elseif kind == "item" then
        local iid = tonumber(req.itemId)
        local need = math.max(1, math.floor(tonumber(req.amount) or 1))
        if not iid or iid <= 0 then return nil end
        local name, have = itemNameAndCount(iid)
        return {
            text = string.format("%sx %s  (%s/%s)", fmtPurchaseAmt(need), name, fmtPurchaseAmt(have), fmtPurchaseAmt(need)),
            met = have >= need,
        }
    elseif kind == "spend" then
        local cid = tonumber(req.currencyId)
        local need = math.max(0, math.floor(tonumber(req.amount) or 0))
        if not cid or cid <= 0 or need <= 0 then return nil end
        local hint = tostring(req.collectableKind or ""):lower()
        if hint == "" or hint == "currency" then hint = nil end
        local name, resolvedKind = liveCollectableNameAndKind(req.itemId, hint)
        if isPlaceholderItemName(name, req.itemId) then name = nil end
        if not name and not isPlaceholderItemName(req.label, req.itemId) then
            name = req.label
        end
        if not name then return nil end
        resolvedKind = resolvedKind or hint
        local typeBit = KIND_LABEL[resolvedKind] or "Item"
        local _, qty = currencyNameAndQty(cid)
        local owned = false
        if req.registryId and TaskTracker.IsRegistryCollectableOwned and TaskTracker.RegistryByID then
            local re = TaskTracker.RegistryByID[req.registryId]
            if re then
                local okOwn, isOwn = pcall(TaskTracker.IsRegistryCollectableOwned, re)
                owned = okOwn and isOwn and true or false
            end
        elseif req.itemId and TaskTracker.IsCatalogCollectableOwned and resolvedKind then
            local okOwn, isOwn = pcall(TaskTracker.IsCatalogCollectableOwned, {
                itemId = req.itemId,
                collectableKind = resolvedKind,
                label = name,
            }, resolvedKind)
            owned = okOwn and isOwn and true or false
        end
        return {
            text = string.format("%s  %s  %s", fmtPurchaseAmt(need), typeBit, truncateSpendName(name)),
            met = owned or qty >= need,
            wrap = false,
        }
    end
    return nil
end

local function purchaseReqsFromTable(ent)
    if type(ent) == "table" and type(ent.purchaseReqs) == "table" and #ent.purchaseReqs > 0 then
        return ent.purchaseReqs
    end
    return nil
end

local purchaseReqsByItemId

local function reqsForItemId(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 or not TaskTracker.Registry then return nil end
    if not purchaseReqsByItemId then
        purchaseReqsByItemId = {}
        for i = 1, #TaskTracker.Registry do
            local re = TaskTracker.Registry[i]
            local reqs = purchaseReqsFromTable(re)
            local iid = re and tonumber(re.itemId)
            if reqs and iid and iid > 0 then
                purchaseReqsByItemId[iid] = reqs
            end
        end
    end
    return purchaseReqsByItemId[itemId]
end

local function okPurchaseItemId(v)
    v = tonumber(v)
    if v and v > 0 then return v end
    return nil
end

local function resolvePurchaseItemId(entry, node)
    local iid = okPurchaseItemId(entry and entry.itemId)
    if iid then return iid end
    if not node then return nil end
    if TaskTracker.RegistryByID then
        if node.collectionFarmId then
            local re = TaskTracker.RegistryByID[node.collectionFarmId]
            iid = okPurchaseItemId(re and re.itemId)
            if iid then return iid end
        end
        if node.registryEntryId then
            local re = TaskTracker.RegistryByID[node.registryEntryId]
            iid = okPurchaseItemId(re and re.itemId)
            if iid then return iid end
        end
    end
    if node.type == "task" and node.advanced and node.advanced.type == "collectable"
        and TaskTracker.GetCollectableEntry then
        local a = node.advanced
        local ent = TaskTracker.GetCollectableEntry(
            a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
        iid = okPurchaseItemId(ent and ent.itemId)
        if iid then return iid end
    end
    return nil
end

local function resolvePurchaseCurrencyId(entry, node)
    local cid = okPurchaseItemId(entry and entry.currencyId)
    if cid then return cid end
    if not node then return nil end
    if TaskTracker.RegistryByID then
        if node.collectionFarmId then
            local re = TaskTracker.RegistryByID[node.collectionFarmId]
            cid = okPurchaseItemId(re and re.currencyId)
            if cid then return cid end
        end
        if node.registryEntryId then
            local re = TaskTracker.RegistryByID[node.registryEntryId]
            cid = okPurchaseItemId(re and re.currencyId)
            if cid then return cid end
        end
    end
    local a = node.advanced
    if type(a) == "table" then
        if a.type == "item" and tostring(a.itemKind or "") == "currency" then
            cid = okPurchaseItemId(a.itemIds and a.itemIds[1])
            if cid then return cid end
        end
        if a.type == "collectable" and TaskTracker.GetCollectableEntry then
            local ent = TaskTracker.GetCollectableEntry(
                a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
            cid = okPurchaseItemId(ent and ent.currencyId)
            if cid then return cid end
        end
    end
    return nil
end

local function purchaseReqKey(req)
    if type(req) ~= "table" then return nil end
    local kind = tostring(req.type or ""):lower()
    if kind == "currency" then
        local id = tonumber(req.currencyId)
        if id then return "c:" .. id end
    elseif kind == "item" then
        local id = tonumber(req.itemId)
        if id then return "i:" .. id end
    elseif kind == "gold" then
        return "g"
    elseif kind == "renown" then
        return "r:" .. tostring(tonumber(req.factionId) or 0)
    elseif kind == "friendship" then
        return "f:" .. tostring(tonumber(req.factionId) or 0)
    elseif kind == "spend" then
        local id = tonumber(req.itemId)
        if id then return "s:" .. id end
        if type(req.label) == "string" and req.label ~= "" then return "s:" .. req.label end
    end
    return kind ~= "" and kind or nil
end

local function mergePurchaseReqs(primary, extra)
    if not extra or #extra == 0 then return primary end
    if not primary or #primary == 0 then return extra end
    local out, seen = {}, {}
    for i = 1, #primary do
        local r = primary[i]
        local k = purchaseReqKey(r)
        out[#out + 1] = r
        if k then seen[k] = true end
    end
    for i = 1, #extra do
        local r = extra[i]
        local k = purchaseReqKey(r)
        if not k or not seen[k] then
            if k then seen[k] = true end
            out[#out + 1] = r
        end
    end
    return out
end

-- Optional AllTheThings vendor costs. Unstable API; pcall + cache; hover-only.
-- Item hover stays short. The currency "Full list" total walks the cost index once.
local ATT_GROUP_CAP = 32
local ATT_SPEND_SCAN_CAP = 2000
local ATT_PARENT_DEPTH = 2
local attReqCache = {}

local function getAttAddon()
    local app = _G.ATTC
    if type(app) ~= "table" then app = _G.AllTheThings end
    if type(app) ~= "table" then return nil end
    return app
end

local function attSearchField(app, field, id)
    local fn = app.GetRawField
    if type(fn) ~= "function" then fn = app.SearchForField end
    if type(fn) ~= "function" then return nil end
    local ok, results = pcall(fn, field, id)
    if not ok or (results ~= nil and type(results) ~= "table") then
        ok, results = pcall(fn, app, field, id)
    end
    if not ok then return nil end
    if results == nil then return {} end
    if type(results) ~= "table" then return nil end
    return results
end

local function attCostTupleToReq(tuple)
    if type(tuple) ~= "table" then return nil end
    local kind = tuple[1]
    if type(kind) == "string" then kind = kind:lower() end
    if kind == "c" or kind == "currency" then
        local id = tonumber(tuple[2])
        local amt = math.floor(tonumber(tuple[3]) or 0)
        if id and id > 0 and amt > 0 then
            return { type = "currency", currencyId = id, amount = amt }
        end
    elseif kind == "i" or kind == "item" then
        local id = tonumber(tuple[2])
        local amt = math.floor(tonumber(tuple[3]) or 1)
        if amt < 1 then amt = 1 end
        if id and id > 0 then
            return { type = "item", itemId = id, amount = amt }
        end
    elseif kind == "g" or kind == "gold" then
        local copper = tonumber(tuple[2])
        if not copper or copper <= 0 then copper = tonumber(tuple[3]) end
        if not copper or copper <= 0 then return nil end
        local gold = math.floor(copper / 10000)
        if gold < 1 then return nil end
        return { type = "gold", amount = gold }
    end
    return nil
end

local function attMinRepToReq(minRep)
    if type(minRep) ~= "table" then return nil end
    local fid = tonumber(minRep[1] or minRep.factionID or minRep.factionId)
    local standing = tonumber(minRep[2] or minRep.standing)
    if not fid or fid <= 0 or not standing or standing <= 0 then return nil end
    standing = math.floor(standing)
    local _, rmax = friendshipRanksForFaction(fid)
    if rmax and rmax > 0 then
        return { type = "friendship", factionId = fid, min = standing }
    end
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local ok, data = pcall(C_MajorFactions.GetMajorFactionData, fid)
        if ok and type(data) == "table" then
            return { type = "renown", factionId = fid, min = standing }
        end
    end
    return nil
end

local function ingestAttReq(into, seen, req)
    local key = purchaseReqKey(req)
    if not key then
        into[#into + 1] = req
        return
    end
    local idx = seen[key]
    if not idx then
        into[#into + 1] = req
        seen[key] = #into
        return
    end
    local prev = into[idx]
    local prevAmt = tonumber(prev.amount or prev.min) or 0
    local newAmt = tonumber(req.amount or req.min) or 0
    if newAmt > 0 and (prevAmt <= 0 or newAmt < prevAmt) then
        into[idx] = req
    end
end

local function harvestAttGroup(group, into, seen, parentLeft)
    if type(group) ~= "table" then return end
    local okCost, cost = pcall(function() return group.cost end)
    if okCost and type(cost) == "table" then
        for i = 1, #cost do
            local req = attCostTupleToReq(cost[i])
            if req then ingestAttReq(into, seen, req) end
        end
    end
    local okRep, minRep = pcall(function() return group.minReputation end)
    if okRep then
        local req = attMinRepToReq(minRep)
        if req then ingestAttReq(into, seen, req) end
    end
    if parentLeft and parentLeft > 0 then
        local okP, parent = pcall(function() return group.parent end)
        if okP and type(parent) == "table" then
            harvestAttGroup(parent, into, seen, parentLeft - 1)
        end
    end
end

local function attPurchaseReqsForItemId(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return nil end
    local cached = attReqCache[itemId]
    if cached == false then return nil end
    if type(cached) == "table" then return cached end
    local app = getAttAddon()
    if not app then return nil end
    local results = attSearchField(app, "itemID", itemId)
    if results == nil then return nil end
    local into, seen = {}, {}
    local n = 0
    for _, group in pairs(results) do
        n = n + 1
        if n > ATT_GROUP_CAP then break end
        if type(group) == "table" then
            harvestAttGroup(group, into, seen, ATT_PARENT_DEPTH)
        end
    end
    if #into == 0 then
        attReqCache[itemId] = false
        return nil
    end
    attReqCache[itemId] = into
    return into
end

local ATT_SPEND_LINE_CAP = 5
local spendsByCurrencyId
local attSpendCache = {}

local function registrySpendsForCurrency(currencyId)
    currencyId = tonumber(currencyId)
    if not currencyId or currencyId <= 0 or not TaskTracker.Registry then return nil end
    if not spendsByCurrencyId then
        spendsByCurrencyId = {}
        for i = 1, #TaskTracker.Registry do
            local re = TaskTracker.Registry[i]
            local reqs = purchaseReqsFromTable(re)
            if reqs then
                for j = 1, #reqs do
                    local req = reqs[j]
                    if type(req) == "table" and tostring(req.type or ""):lower() == "currency" then
                        local cid = tonumber(req.currencyId)
                        local amt = math.floor(tonumber(req.amount) or 0)
                        if cid and cid > 0 and amt > 0 then
                            local list = spendsByCurrencyId[cid]
                            if not list then
                                list = {}
                                spendsByCurrencyId[cid] = list
                            end
                            list[#list + 1] = {
                                type = "spend",
                                currencyId = cid,
                                amount = amt,
                                itemId = tonumber(re.itemId),
                                label = re.label,
                                collectableKind = re.collectableKind,
                                registryId = re.id,
                            }
                        end
                    end
                end
            end
        end
    end
    return spendsByCurrencyId[currencyId]
end

local function attGroupField(group, key)
    local ok, v = pcall(function() return group[key] end)
    if ok then return v end
    return nil
end

local function attCostAmountForCurrency(group, currencyId)
    local cost = attGroupField(group, "cost")
    if type(cost) ~= "table" then return nil end
    local amt
    for i = 1, #cost do
        local t = cost[i]
        if type(t) == "table" then
            local kind = t[1]
            if type(kind) == "string" then kind = kind:lower() end
            if (kind == "c" or kind == "currency") and tonumber(t[2]) == currencyId then
                local n = math.floor(tonumber(t[3]) or 0)
                if n > 0 and (not amt or n < amt) then amt = n end
            end
        end
    end
    return amt
end

local function attNumField(group, a, b)
    local n = tonumber(attGroupField(group, a))
    if n and n > 0 then return n end
    if b then
        n = tonumber(attGroupField(group, b))
        if n and n > 0 then return n end
    end
end

local function attCollectableKind(group)
    if attNumField(group, "mountID") then return "mount" end
    if attNumField(group, "speciesID", "speciesId") then return "pet" end
    if attNumField(group, "toyID") then return "toy" end
    if attNumField(group, "decorID", "decorId") or attGroupField(group, "type") == "decorID" then
        return "housing"
    end
    if attNumField(group, "recipeID", "recipeId") then return "recipe" end
    if attNumField(group, "sourceID") or attNumField(group, "illusionID") then return "appearance" end
    if attGroupField(group, "type") == "ensembleID" or attNumField(group, "tmogSetID") then
        return "appearance"
    end
    if attNumField(group, "titleID") then return "other" end
    return nil
end

local function attGroupUnobtainable(group)
    local u = attGroupField(group, "u")
    if u == nil or u == false or u == 0 then return false end
    if issecretvalue and issecretvalue(u) then return false end
    return true
end

local function attGroupSpendReq(group, currencyId)
    if type(group) ~= "table" then return nil end
    if attGroupUnobtainable(group) then return nil end
    local selfCid = tonumber(attGroupField(group, "currencyID")) or tonumber(attGroupField(group, "currencyId"))
    if selfCid and selfCid == currencyId then return nil end
    local amt = attCostAmountForCurrency(group, currencyId)
    if not amt then return nil end
    local itemId = tonumber(attGroupField(group, "itemID")) or tonumber(attGroupField(group, "itemId"))
    if not itemId or itemId <= 0 then return nil end
    return {
        type = "spend",
        currencyId = currencyId,
        amount = amt,
        itemId = itemId,
        collectableKind = attCollectableKind(group),
        mountId = attNumField(group, "mountID"),
        speciesId = attNumField(group, "speciesID", "speciesId"),
        sourceId = attNumField(group, "sourceID"),
        decorId = attNumField(group, "decorID", "decorId"),
        recipeId = attNumField(group, "recipeID", "recipeId"),
        spellId = attNumField(group, "spellID", "spellId"),
        tmogSetId = attNumField(group, "tmogSetID"),
        illusionId = attNumField(group, "illusionID"),
        titleId = attNumField(group, "titleID"),
    }
end

local function attTakeSpendGroups(results, currencyId, into, seen, cap)
    if type(results) ~= "table" then return end
    cap = cap or ATT_SPEND_SCAN_CAP
    local n = 0
    for _, group in pairs(results) do
        n = n + 1
        if n > cap then break end
        local req = attGroupSpendReq(group, currencyId)
        if req then ingestAttReq(into, seen, req) end
    end
end

local function attSpendsForCurrency(currencyId)
    currencyId = tonumber(currencyId)
    if not currencyId or currencyId <= 0 then return nil end
    local cached = attSpendCache[currencyId]
    if type(cached) == "table" then return cached end
    local app = getAttAddon()
    if not app then return nil end
    local into, seen = {}, {}
    attTakeSpendGroups(attSearchField(app, "currencyIDAsCost", currencyId), currencyId, into, seen)
    if #into == 0 then
        local currGroups = attSearchField(app, "currencyID", currencyId)
        if type(currGroups) == "table" then
            local n = 0
            for _, g in pairs(currGroups) do
                n = n + 1
                if n > ATT_SPEND_SCAN_CAP then break end
                attTakeSpendGroups(attGroupField(g, "costCollectibles"), currencyId, into, seen, ATT_SPEND_SCAN_CAP)
            end
        end
    end
    if #into == 0 then return nil end
    attSpendCache[currencyId] = into
    return into
end

local function copyReqList(src)
    if not src then return nil end
    local t = {}
    for i = 1, #src do t[i] = src[i] end
    return t
end

local function sortSpendReqs(reqs)
    if not reqs or #reqs < 2 then return reqs end
    table.sort(reqs, function(a, b)
        return (tonumber(a.amount) or 0) > (tonumber(b.amount) or 0)
    end)
    return reqs
end

-- Owned flags for the currency total. Cleared when that currency's count changes,
-- or when a collectable is learned.
local spendOwnedByItem = {}
local spendOwnedQty = {}

local attNeedByCurrency = {}

function TaskTracker.ClearCurrencySpendOwnedCache()
    wipe(spendOwnedByItem)
    wipe(attNeedByCurrency)
end

local function spendFlagTrue(v)
    if v == nil or v == false then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return v == true
end

local function spendQuietNumber(v)
    if v == nil then return 0 end
    if issecretvalue and issecretvalue(v) then return nil end
    return tonumber(v) or 0
end

local spendMountPrimed = false
local function spendPrimeMounts()
    if spendMountPrimed then return end
    spendMountPrimed = true
    if C_MountJournal and C_MountJournal.GetMountIDs then
        pcall(C_MountJournal.GetMountIDs)
    end
end

local function spendSpellKnown(spellID)
    if spellID == nil or (issecretvalue and issecretvalue(spellID)) then return false end
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return false end
    if IsPlayerSpell then
        local okSpell, known = pcall(IsPlayerSpell, spellID)
        if okSpell and spendFlagTrue(known) then return true end
    end
    if IsSpellKnown then
        local okSpell, known = pcall(IsSpellKnown, spellID)
        if okSpell and spendFlagTrue(known) then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        local okSpell, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellID, bank, true)
        if okSpell and spendFlagTrue(known) then return true end
    end
    return false
end

-- The red "Already known" line on an item tooltip. Ensemble learn spells are not
-- IsPlayerSpell after you use them, and a small set may not report collected.
local itemKnownTipCache = {}

function TaskTracker.ItemRecordCached(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return false end
    if C_Item and C_Item.IsItemDataCachedByID then
        local ok, cached = pcall(C_Item.IsItemDataCachedByID, itemId)
        if ok then return cached == true end
    end
    return false
end

function TaskTracker.ClearItemTooltipKnownCache(itemId)
    itemId = tonumber(itemId)
    if itemId then
        itemKnownTipCache[itemId] = nil
        return
    end
    if wipe then wipe(itemKnownTipCache) else itemKnownTipCache = {} end
end

--- known, ready. A not-yet-cached item is not stored, so the next check can retry.
function TaskTracker.ItemTooltipSaysAlreadyKnown(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return false, true end
    local cached = itemKnownTipCache[itemId]
    if cached ~= nil then return cached, true end
    local phrase = ITEM_SPELL_KNOWN
    if type(phrase) ~= "string" or phrase == "" or (issecretvalue and issecretvalue(phrase)) then
        return false, true
    end
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false, true end
    if not TaskTracker.ItemRecordCached(itemId) then
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemId)
        end
        return false, false
    end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemId)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines == 0 then
        return false, false
    end
    local known = false
    for i = 1, #data.lines do
        local row = data.lines[i]
        local text = type(row) == "table" and row.leftText or nil
        if type(text) == "string" and text ~= "" and not (issecretvalue and issecretvalue(text)) then
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            text = text:match("^%s*(.-)%s*$") or text
            if text == phrase then
                known = true
                break
            end
        end
    end
    itemKnownTipCache[itemId] = known
    return known, true
end

-- Journal isCollected can be secret, which is not a yes. The summon spell is
-- known once the mount is learned, same as the item tooltip's "Already known".
local function spendMountCollected(mountId)
    mountId = tonumber(mountId)
    if not mountId or mountId <= 0 or not (C_MountJournal and C_MountJournal.GetMountInfoByID) then
        return false
    end
    spendPrimeMounts()
    local ok, _, spellID, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountId)
    if not ok then return false end
    if spendFlagTrue(isCollected) then return true end
    return spendSpellKnown(spellID)
end

local function spendItemSpellKnown(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 or not (C_Item and C_Item.GetItemSpell) then return false end
    local ok, spellName, spellID = pcall(C_Item.GetItemSpell, itemId)
    if not ok then return false end
    spellID = tonumber(spellID)
    if (not spellID or spellID <= 0) and type(spellName) == "number" then
        spellID = spellName
    end
    return spendSpellKnown(spellID)
end

-- -1 not a pet, 0 pet with no species yet, >0 species id.
local spendSpeciesByItem = {}
local function spendSpeciesFromItem(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return nil, false end
    local cached = spendSpeciesByItem[itemId]
    if cached == -1 then return nil, false end
    if cached == 0 then return nil, true end
    if cached ~= nil and cached > 0 then return cached, true end
    local species, isPet = 0, false
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local packed = { pcall(C_PetJournal.GetPetInfoByItemID, itemId) }
        if packed[1] == true then
            if type(packed[2]) == "string" and packed[2] ~= "" then
                isPet = true
                species = tonumber(packed[14]) or 0
            else
                local older = tonumber(packed[2])
                if older and older > 0 then
                    isPet = true
                    species = older
                end
            end
        end
    end
    spendSpeciesByItem[itemId] = isPet and species or -1
    return species > 0 and species or nil, isPet
end

local function spendPetCollected(itemId, speciesId)
    speciesId = tonumber(speciesId)
    if not speciesId or speciesId <= 0 then
        local species, isPet = spendSpeciesFromItem(itemId)
        if not isPet then return false end
        speciesId = species
    end
    if not speciesId or speciesId <= 0 or not (C_PetJournal and C_PetJournal.GetNumCollectedInfo) then
        return false
    end
    local ok, num = pcall(C_PetJournal.GetNumCollectedInfo, speciesId)
    if not ok or (issecretvalue and issecretvalue(num)) then return false end
    return type(num) == "number" and num > 0
end

local spendSetByItem = {}
local function spendTransmogSetId(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return nil end
    local cached = spendSetByItem[itemId]
    if cached ~= nil then
        if cached > 0 then return cached end
        return nil
    end
    if not TaskTracker.ItemRecordCached(itemId) then
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemId)
        end
        return nil
    end
    local setID = 0
    if C_Item and C_Item.GetItemLearnTransmogSet then
        local ok, id = pcall(C_Item.GetItemLearnTransmogSet, itemId)
        if ok and id ~= nil and not (issecretvalue and issecretvalue(id)) then
            setID = tonumber(id) or 0
        end
    end
    spendSetByItem[itemId] = setID
    return setID > 0 and setID or nil
end

local function spendSetCollected(setID)
    setID = tonumber(setID)
    if not setID or setID <= 0 or not C_TransmogSets then return false end
    if C_TransmogSets.GetSetInfo then
        local ok, info = pcall(C_TransmogSets.GetSetInfo, setID)
        if ok and type(info) == "table" and spendFlagTrue(info.collected) then return true end
    end
    if C_TransmogSets.GetSetPrimaryAppearances then
        local ok, apps = pcall(C_TransmogSets.GetSetPrimaryAppearances, setID)
        if ok and type(apps) == "table" and #apps > 0 then
            local all = true
            for i = 1, #apps do
                local row = apps[i]
                if type(row) ~= "table" or not spendFlagTrue(row.collected) then
                    all = false
                    break
                end
            end
            if all then return true end
        end
    end
    if C_TransmogSets.IsSetCollected then
        local ok, known = pcall(C_TransmogSets.IsSetCollected, setID)
        if ok and spendFlagTrue(known) then return true end
    end
    if C_TransmogSets.GetSetSourceCounts then
        local ok, got, total = pcall(C_TransmogSets.GetSetSourceCounts, setID)
        if ok and not (issecretvalue and (issecretvalue(got) or issecretvalue(total))) then
            got, total = tonumber(got), tonumber(total)
            if got and total and total > 0 and got >= total then return true end
        end
    end
    if C_Transmog and C_Transmog.GetAllSetAppearancesByID
        and C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
        local ok, rows = pcall(C_Transmog.GetAllSetAppearancesByID, setID)
        if ok and type(rows) == "table" and #rows > 0 then
            for i = 1, #rows do
                local sourceID = type(rows[i]) == "table" and tonumber(rows[i].itemModifiedAppearanceID) or nil
                if not sourceID or sourceID <= 0 then return false end
                local okHas, known = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
                if not (okHas and known == true) then return false end
            end
            return true
        end
    end
    return false
end

local function spendHousingOwned(itemId, decorId)
    if not C_HousingCatalog then return false end
    local function countsOwned(info)
        if type(info) ~= "table" then return false end
        local stored = spendQuietNumber(info.totalNumStored)
        if stored == nil then stored = spendQuietNumber(info.numStored) end
        local placed = spendQuietNumber(info.totalNumPlaced)
        if placed == nil then placed = spendQuietNumber(info.numPlaced) end
        local redeem = spendQuietNumber(info.remainingRedeemable)
        if stored == nil or placed == nil or redeem == nil then return false end
        return (stored + placed + redeem) >= 1
    end
    if itemId and C_HousingCatalog.GetCatalogEntryInfoByItem then
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemId, true)
        if ok and countsOwned(info) then return true end
    end
    decorId = tonumber(decorId)
    if decorId and decorId > 0 and C_HousingCatalog.GetCatalogEntryInfoByRecordID then
        local decorType = 1
        if Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor then
            decorType = Enum.HousingCatalogEntryType.Decor
        end
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByRecordID, decorType, decorId, true)
        if ok and countsOwned(info) then return true end
    end
    return false
end

local function ensureSpendKind(req)
    local kind = tostring(req.collectableKind or ""):lower()
    if kind ~= "" and kind ~= "item" and kind ~= "currency" then return kind end
    if req._kindChecked then return nil end
    req._kindChecked = true
    local itemId = tonumber(req.itemId)
    if not itemId or itemId <= 0 then return nil end
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local ok, toyItemId, toyName = pcall(C_ToyBox.GetToyInfo, itemId)
        if ok and tonumber(toyItemId) and type(toyName) == "string" and toyName ~= "" then
            req.collectableKind = "toy"
            return "toy"
        end
    end
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local ok, mid = pcall(C_MountJournal.GetMountFromItem, itemId)
        if ok and tonumber(mid) and mid > 0 then
            req.mountId = req.mountId or mid
            req.collectableKind = "mount"
            return "mount"
        end
    end
    local species, isPet = spendSpeciesFromItem(itemId)
    if isPet then
        req.speciesId = req.speciesId or species
        req.collectableKind = "pet"
        return "pet"
    end
    if spendTransmogSetId(itemId) then
        req.collectableKind = "appearance"
        return "appearance"
    end
    if C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem then
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemId, false)
        if ok and type(info) == "table" then
            local id = tonumber(info.entryID) or tonumber(info.recordID) or tonumber(info.decorID)
            if id and id > 0 then
                req.decorId = req.decorId or id
                req.collectableKind = "housing"
                return "housing"
            end
        end
    end
    return nil
end

local function spendItemOwned(req)
    local itemId = tonumber(req.itemId)
    if not itemId or itemId <= 0 then return false end
    local cached = spendOwnedByItem[itemId]
    if cached ~= nil then return cached end
    local owned = false
    local cacheResult = true
    if req.registryId and TaskTracker.RegistryByID and TaskTracker.IsRegistryCollectableOwned then
        local re = TaskTracker.RegistryByID[req.registryId]
        if re then
            local ok, isOwn = pcall(TaskTracker.IsRegistryCollectableOwned, re)
            owned = ok and isOwn and true or false
        end
    end
    local kind = tostring(req.collectableKind or ""):lower()
    if not owned and kind == "toy" and PlayerHasToy then
        local ok, has = pcall(PlayerHasToy, itemId)
        if ok and spendFlagTrue(has) then owned = true end
    elseif not owned and kind == "mount" then
        local sawMount = (tonumber(req.mountId) or 0) > 0
        if sawMount and spendMountCollected(req.mountId) then
            owned = true
        end
        if not owned and C_MountJournal and C_MountJournal.GetMountFromItem then
            local ok, mid = pcall(C_MountJournal.GetMountFromItem, itemId)
            if ok and mid ~= nil and not (issecretvalue and issecretvalue(mid)) then
                mid = tonumber(mid)
            else
                mid = nil
            end
            if mid and mid > 0 then
                sawMount = true
                if spendMountCollected(mid) then owned = true end
            end
        end
        if not owned then
            local spellId = tonumber(req.spellId)
            if spellId and spellId > 0 and C_MountJournal and C_MountJournal.GetMountFromSpell then
                local ok, fromSpell = pcall(C_MountJournal.GetMountFromSpell, spellId)
                if ok and fromSpell ~= nil and not (issecretvalue and issecretvalue(fromSpell)) then
                    fromSpell = tonumber(fromSpell)
                else
                    fromSpell = nil
                end
                if fromSpell and fromSpell > 0 then
                    sawMount = true
                    if spendMountCollected(fromSpell) then owned = true end
                end
            end
        end
        if not owned and spendItemSpellKnown(itemId) then
            owned = true
            sawMount = true
        end
        if not owned and not sawMount then
            requestItemName(itemId)
            cacheResult = false
        end
    elseif not owned and kind == "pet" then
        owned = spendPetCollected(itemId, req.speciesId)
    elseif not owned and kind == "appearance" then
        local setID = tonumber(req.tmogSetId) or spendTransmogSetId(itemId)
        if setID then
            owned = spendSetCollected(setID) or spendItemSpellKnown(itemId)
        else
            local sid = tonumber(req.sourceId)
            if sid and sid > 0 and C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
                local ok, has = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sid)
                if ok and has == true then owned = true end
            end
            local illusionId = tonumber(req.illusionId)
            if not owned and illusionId and illusionId > 0 and C_TransmogCollection and C_TransmogCollection.GetIllusionInfo then
                local ok, info = pcall(C_TransmogCollection.GetIllusionInfo, illusionId)
                if ok and type(info) == "table" and spendFlagTrue(info.isCollected) then owned = true end
            end
            if not owned and C_TransmogCollection and C_TransmogCollection.PlayerHasTransmog then
                local ok, has = pcall(C_TransmogCollection.PlayerHasTransmog, itemId)
                if ok and has == true then owned = true end
            end
            if not owned then owned = spendItemSpellKnown(itemId) end
        end
        if not owned and TaskTracker.ItemTooltipSaysAlreadyKnown then
            local known, ready = TaskTracker.ItemTooltipSaysAlreadyKnown(itemId)
            if known then owned = true end
            if not ready then cacheResult = false end
        end
    elseif not owned and kind == "housing" then
        owned = spendHousingOwned(itemId, req.decorId)
    elseif not owned and kind == "recipe" then
        local sid = tonumber(req.recipeId) or tonumber(req.spellId)
        if sid and sid > 0 and IsPlayerSpell then
            local ok, known = pcall(IsPlayerSpell, sid)
            if ok and spendFlagTrue(known) then owned = true end
        end
        if not owned then owned = spendItemSpellKnown(itemId) end
    elseif not owned and kind == "other" then
        local titleId = tonumber(req.titleId)
        if titleId and titleId > 0 and IsTitleKnown then
            local ok, known = pcall(IsTitleKnown, titleId)
            if ok and spendFlagTrue(known) then owned = true end
        end
        if not owned then owned = spendItemSpellKnown(itemId) end
    end
    if cacheResult then
        spendOwnedByItem[itemId] = owned and true or false
    end
    return owned and true or false
end

local function spendCountsTowardNeed(req)
    if type(req) ~= "table" then return false end
    if not ensureSpendKind(req) then return false end
    if spendItemOwned(req) then return false end
    return true
end

--- Sum of AllTheThings costs still owed for collectables that use this currency.
--- Nil when AllTheThings is off or has no list yet. A miss is remembered for a few seconds
--- so list layout does not rescan; a real total stays until the wallet changes or a collectable is learned.
function TaskTracker.AttCurrencyRequiredTotal(currencyId)
    currencyId = tonumber(currencyId)
    if not currencyId or currencyId <= 0 then return nil end
    if TaskTrackerDB and TaskTrackerDB.attDataEnabled == false then return nil end
    if not (TaskTracker.IsAllTheThingsLoaded and TaskTracker.IsAllTheThingsLoaded()) then return nil end
    local _, have = currencyNameAndQty(currencyId)
    if spendOwnedQty[currencyId] ~= have then
        wipe(spendOwnedByItem)
        spendOwnedQty[currencyId] = have
        attNeedByCurrency[currencyId] = nil
    end
    local now = GetTime and GetTime() or 0
    local cached = attNeedByCurrency[currencyId]
    if cached and cached.have == have then
        if cached.need ~= false then return cached.need end
        if (now - (cached.at or 0)) < 10 then return nil end
    end
    local spends = attSpendsForCurrency(currencyId)
    if not spends then
        attNeedByCurrency[currencyId] = { need = false, at = now, have = have }
        return nil
    end
    local needAll = 0
    for i = 1, #spends do
        local req = spends[i]
        if spendCountsTowardNeed(req) then
            needAll = needAll + math.max(0, math.floor(tonumber(req.amount) or 0))
        end
    end
    attNeedByCurrency[currencyId] = { need = needAll, at = now, have = have }
    return needAll
end

local function evaluateReqList(reqs, header)
    if not reqs then return nil end
    local out = {}
    for i = 1, #reqs do
        local line = evaluatePurchaseReq(reqs[i])
        if line then out[#out + 1] = line end
    end
    if #out == 0 then return nil end
    if header then out.header = header end
    return out
end

local function evaluateCurrencySpendList(full, currencyId)
    if not full or #full == 0 then return nil end
    local _, have = currencyNameAndQty(currencyId)
    if spendOwnedQty[currencyId] ~= have then
        wipe(spendOwnedByItem)
        spendOwnedQty[currencyId] = have
    end
    local remaining = {}
    local needAll = 0
    for i = 1, #full do
        local req = full[i]
        if spendCountsTowardNeed(req) then
            local amt = math.max(0, math.floor(tonumber(req.amount) or 0))
            if amt > 0 then
                needAll = needAll + amt
                remaining[#remaining + 1] = req
            end
        end
    end
    sortSpendReqs(remaining)
    local out = {
        header = "Can buy",
        {
            text = string.format("Full list  %s/%s", fmtPurchaseAmt(have), fmtPurchaseAmt(needAll)),
            met = have >= needAll,
            wrap = false,
        },
    }
    local shown, i = 0, 1
    while shown < ATT_SPEND_LINE_CAP and i <= #remaining do
        local line = evaluatePurchaseReq(remaining[i])
        if line then
            shown = shown + 1
            out[#out + 1] = line
        end
        i = i + 1
    end
    local skipped = #remaining - i + 1
    if skipped < 0 then skipped = 0 end
    if skipped > 0 then
        out[#out + 1] = {
            text = string.format("+%d more", skipped),
            met = have >= needAll,
            wrap = false,
        }
    end
    return out
end

function TaskTracker.AttSearchField(field, id)
    local app = getAttAddon()
    if not app then return nil end
    return attSearchField(app, field, id)
end

function TaskTracker.AttCostTupleToReq(tuple)
    return attCostTupleToReq(tuple)
end

function TaskTracker.AttMinRepToReq(minRep)
    return attMinRepToReq(minRep)
end

--- True when every requirement evaluates and is met. Unknown requirement types fail closed.
function TaskTracker.PurchaseRequirementsMet(reqs)
    if type(reqs) ~= "table" or #reqs == 0 then return false end
    for i = 1, #reqs do
        local line = evaluatePurchaseReq(reqs[i])
        if not line or line.met ~= true then return false end
    end
    return true
end

function TaskTracker.DescribePurchaseReq(req)
    return evaluatePurchaseReq(req)
end

--- Vendor costs for hover: { { text, met }, ... } or nil. Hover-only.
--- Currency wallets use header "Can buy" (what the currency purchases).
function TaskTracker.GetPurchaseRequirementTooltipLines(entry, node)
    if node and type(node.readyToBuyReqs) == "table" and #node.readyToBuyReqs > 0 then
        return evaluateReqList(node.readyToBuyReqs)
    end
    local attOn = TaskTracker.IsAttDataEnabled and TaskTracker.IsAttDataEnabled()
    local cid = resolvePurchaseCurrencyId(entry, node)
    local iid = resolvePurchaseItemId(entry, node)
    if cid and not iid then
        local spends = copyReqList(registrySpendsForCurrency(cid))
        if attOn then
            spends = mergePurchaseReqs(spends, attSpendsForCurrency(cid))
        end
        return evaluateCurrencySpendList(spends, cid)
    end

    local reqs = purchaseReqsFromTable(entry)
    if not reqs and entry then
        reqs = reqsForItemId(entry.itemId)
    end
    if not reqs and node then
        if node.collectionFarmId and TaskTracker.RegistryByID then
            reqs = purchaseReqsFromTable(TaskTracker.RegistryByID[node.collectionFarmId])
        end
        if not reqs and node.registryEntryId and TaskTracker.RegistryByID then
            reqs = purchaseReqsFromTable(TaskTracker.RegistryByID[node.registryEntryId])
        end
        if not reqs and node.type == "task" and node.advanced and node.advanced.type == "collectable"
            and TaskTracker.GetCollectableEntry then
            local ent = TaskTracker.GetCollectableEntry(
                node.advanced.collectableExpansion,
                node.advanced.collectableCategory,
                node.advanced.collectableEntryId)
            reqs = purchaseReqsFromTable(ent) or reqsForItemId(ent and ent.itemId)
        end
    end
    if attOn then
        local attReqs = attPurchaseReqsForItemId(iid)
        if attReqs then
            reqs = mergePurchaseReqs(reqs, attReqs)
        end
    end
    return evaluateReqList(reqs)
end

-- itemAbsentMeansUsed: "had the item, then it was gone" is per character.
-- The old boolean lived on account-wide registryState, so one character using the
-- map marked every alt complete. Do not copy that boolean onto the current character.
local function trackItemHadForCurrentChar(state)
    if not state then return false end
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if not key then return false end
    local byChar = state.trackItemHadByChar
    return type(byChar) == "table" and byChar[key] == true
end

local function markTrackItemHadForCurrentChar(state)
    if not state then return end
    state.trackItemHadThisPeriod = nil
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if not key then return end
    if type(state.trackItemHadByChar) ~= "table" then
        state.trackItemHadByChar = {}
    end
    state.trackItemHadByChar[key] = true
end

-- ─────────────────────────────────────
-- Check current quest completion state
-- Called on login to sync with server
-- ─────────────────────────────────────
function TaskTracker.CheckRegistryProgress()
    local db = TaskTrackerDB
    if not db or not db.registryState then return false end
    if not IsPlayerInWorld() then return false end
    if not (TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady()) then
        return false
    end

    if TaskTracker.ApplyCharRegistryOverrides then
        TaskTracker.ApplyCharRegistryOverrides()
    end

    local anyChanged = false

    for _, entry in ipairs(TaskTracker.Registry) do
        local state = db.registryState[entry.id]
        if state then
            local prevValue = state.value
            local prevTrackHad = (entry.itemAbsentMeansUsed or entry.trackItemLatch) and trackItemHadForCurrentChar(state) or nil

            if entry.type == "mplus_hint_row" and TaskTracker.MPlusRegistryHintIsAutoMaxed then
                -- Drive 0/1 from cap state when not manually locked (manualOnly otherwise skips game sync).
                if state.userValue == nil then
                    local maxed = TaskTracker.MPlusRegistryHintIsAutoMaxed(entry)
                    state.value = maxed and 1 or 0
                end
            elseif entry.manualOnly or TaskTracker.RegistryRowIsDisplayOnly(entry) then
                -- manualOnly: user / saved value only. vault_row: display-only.
            elseif entry.type == "quest_count" and entry.raidTrack and TaskTracker.GetRegistryQuestCountFromGame then
                -- Boss kills and vault slots come from the lockout, not a manual 0/1.
                local cur = TaskTracker.GetRegistryQuestCountFromGame(entry, state)
                if cur ~= nil then
                    state.value = cur
                    state.userValue = nil
                end
            elseif state.userValue ~= nil and (entry.type == "quest_count" or entry.type == "quest_complete"
                or entry.type == "collectable_owned" or entry.type == "reputation_standing") then
                -- manual count lock (quest_count / reputation) or 0/1 lock from row clicks
            elseif entry.widgetId and entry.type == "quest_count" and TaskTracker.GetRegistryWidgetProgressCounts then
                local cur = select(1, TaskTracker.GetRegistryWidgetProgressCounts(entry.widgetId))
                if cur ~= nil then
                    local cap = entry.max or 999
                    state.value = math.max(0, math.min(cur, cap))
                end
            elseif entry.type == "quest_count" and entry.trackItemId then
                local n = TaskTracker.ItemCount(entry.trackItemId, true, false, true)
                local cap = entry.max or 1
                if entry.itemAbsentMeansUsed then
                    -- "No item" alone is ambiguous (never obtained vs consumed). Only treat as
                    -- "used" if this character held the item at least once since the last reset.
                    state.trackItemHadThisPeriod = nil
                    if n > 0 then
                        markTrackItemHadForCurrentChar(state)
                        state.value = 0
                    else
                        state.value = trackItemHadForCurrentChar(state) and cap or 0
                    end
                elseif entry.trackItemLatch then
                    if n > 0 then
                        markTrackItemHadForCurrentChar(state)
                    end
                    state.value = trackItemHadForCurrentChar(state) and cap or 0
                else
                    state.value = math.max(0, math.min(n, cap))
                end
            elseif entry.type == "quest_count" then
                local cap = entry.max or 999
                if TaskTracker.RegistryEntryUsesWeeklyQuestDelta(entry) then
                    local delta = TaskTracker.GetCharWeeklyQuestDelta and TaskTracker.GetCharWeeklyQuestDelta(entry) or 0
                    state.value = math.min(delta, cap)
                else
                    -- At cap, quest completion flags cannot reduce until reset; skip large quest scans.
                    if entry.quests and (state.value or 0) >= cap then
                        state.value = cap
                    else
                        local count = 0
                        if entry.quests then
                            for qid in pairs(entry.quests) do
                                if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                                    count = count + 1
                                end
                            end
                        end
                        state.value = math.min(count, cap)
                    end
                end
            elseif entry.type == "profession_catchup" then
                local rem = TaskTracker.GetProfessionCatchupRemaining
                    and TaskTracker.GetProfessionCatchupRemaining(entry.catchupCurrencyId)
                if rem ~= nil then
                    state.value = rem
                end
            elseif entry.type == "quest_complete" then
                if TaskTracker.RegistryEntryUsesWeeklyQuestDelta(entry) then
                    local delta = TaskTracker.GetCharWeeklyQuestDelta and TaskTracker.GetCharWeeklyQuestDelta(entry) or 0
                    state.value = (delta >= 1) and 1 or 0
                else
                    if TaskTracker.RegistryEntryLatchesWeeklyQuestComplete(entry)
                        and TaskTracker.RegistryEntryAnyQuestFlaggedComplete(entry) then
                        state.weeklyQuestCompleteLatched = true
                    end
                    state.value = TaskTracker.GetRegistryQuestCompleteFromGame(entry, state) or 0
                end
            elseif entry.type == "collectable_owned" then
                state.value = TaskTracker.IsRegistryCollectableOwned(entry) and 1 or 0
            elseif entry.type == "reputation_standing" then
                local cur = select(1, TaskTracker.GetRegistryReputationStanding(entry))
                state.value = cur
            end

            local trackHadNow = (entry.itemAbsentMeansUsed or entry.trackItemLatch) and trackItemHadForCurrentChar(state) or nil
            if prevValue ~= state.value or prevTrackHad ~= trackHadNow then
                anyChanged = true
            end
            if TaskTracker.TryNormalizeRegistryEntryState then
                TaskTracker.TryNormalizeRegistryEntryState(entry.id)
            end
            if TaskTracker.EnsureRegistryPowerShareClaimTimes and TaskTracker.EnsureRegistryPowerShareClaimTimes(entry, state) then
                anyChanged = true
            end
            -- Shared power pool: one legacy stamp for quest_complete / single-cap quest_count rows.
            -- Multi-cap quest_count + shareKey (e.g. Special Assignment) uses powerShareClaimTimes instead.
            if not TaskTracker.RegistryEntryUsesPowerSharePerCompletionClaims(entry) then
                if TaskTracker.RegistryEntryNaturallyCompleteForRewards(entry)
                    and not state.powerShareClaimAt and GetServerTime then
                    state.powerShareClaimAt = GetServerTime()
                    anyChanged = true
                    if TaskTracker.InvalidatePowerShareWinnersCache then
                        TaskTracker.InvalidatePowerShareWinnersCache()
                    end
                end
            end
        end
    end

    if TaskTracker.SnapshotCharRegistryProgress then
        TaskTracker.SnapshotCharRegistryProgress()
    end

    return anyChanged
end

-- ─────────────────────────────────────
-- Handle a quest being turned in live
-- ─────────────────────────────────────
function TaskTracker.OnQuestTurnedIn(questID)
    if TaskTracker.NoteRegistryWeeklyQuestTurnIn then
        TaskTracker.NoteRegistryWeeklyQuestTurnIn(questID)
    end
    local db = TaskTrackerDB
    if not db or not db.registryState then return end

    local entries = TaskTracker.QuestToEntry[questID]
    if not entries then return end

    local anyChanged = false
    local inv = false
    for i = 1, #entries do
        local entry = entries[i]
        if entry then
            local state = db.registryState[entry.id]
            if state then
                anyChanged = true
                if entry.type == "quest_count" then
                    if state.value < entry.max then
                        state.value = state.value + 1
                    end
                elseif entry.type == "quest_complete" then
                    if TaskTracker.RegistryEntryLatchesWeeklyQuestComplete(entry) then
                        state.weeklyQuestCompleteLatched = true
                    end
                    state.value = 1
                end

                if TaskTracker.EnsureRegistryPowerShareClaimTimes and TaskTracker.EnsureRegistryPowerShareClaimTimes(entry, state) then
                    inv = true
                end
                if entry.type == "quest_complete"
                    or not TaskTracker.RegistryEntryUsesPowerSharePerCompletionClaims(entry) then
                    if not state.powerShareClaimAt and GetServerTime then
                        state.powerShareClaimAt = GetServerTime()
                        inv = true
                    end
                end

                state.override = nil
                state.userValue = nil
                state.checkboxDoneOverride = nil
                if TaskTracker.PersistCharRegistryOverride then
                    TaskTracker.PersistCharRegistryOverride(entry.id)
                end
            end
        end
    end
    if not anyChanged then return end

    if inv and TaskTracker.InvalidatePowerShareWinnersCache then
        TaskTracker.InvalidatePowerShareWinnersCache()
    end

    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

--- Complete weekly quest_complete rows that track an NPC id, encounter name, and/or loot object.
--- Returns true if any row changed.
function TaskTracker.TryCompleteRegistryKillTrack(npcId, encounterName, lootObjectId)
    local db = TaskTrackerDB
    if not db or not db.registryState then return false end

    local lists
    local function mergeLists(extra)
        if not extra or #extra == 0 then return end
        if not lists then
            lists = extra
            return
        end
        local merged = {}
        for i = 1, #lists do merged[i] = lists[i] end
        for i = 1, #extra do merged[#merged + 1] = extra[i] end
        lists = merged
    end
    npcId = tonumber(npcId)
    if npcId and TaskTracker.NpcToRegistry then
        mergeLists(TaskTracker.NpcToRegistry[npcId])
    end
    if type(encounterName) == "string" and encounterName ~= "" and TaskTracker.EncounterNameToRegistry then
        mergeLists(TaskTracker.EncounterNameToRegistry[string.lower(encounterName)])
    end
    lootObjectId = tonumber(lootObjectId)
    if lootObjectId and TaskTracker.LootObjectToRegistry then
        mergeLists(TaskTracker.LootObjectToRegistry[lootObjectId])
    end
    if not lists or #lists == 0 then return false end

    local anyChanged = false
    local inv = false
    local seen = {}
    for i = 1, #lists do
        local entry = lists[i]
        if entry and entry.type == "quest_complete" and not seen[entry.id] then
            seen[entry.id] = true
            local state = db.registryState[entry.id]
            if state then
                if TaskTracker.RegistryEntryLatchesWeeklyQuestComplete(entry) then
                    state.weeklyQuestCompleteLatched = true
                end
                if (tonumber(state.value) or 0) < 1 then
                    state.value = 1
                    anyChanged = true
                end
                if TaskTracker.EnsureRegistryPowerShareClaimTimes and TaskTracker.EnsureRegistryPowerShareClaimTimes(entry, state) then
                    inv = true
                end
                if not TaskTracker.RegistryEntryUsesPowerSharePerCompletionClaims
                    or not TaskTracker.RegistryEntryUsesPowerSharePerCompletionClaims(entry) then
                    if not state.powerShareClaimAt and GetServerTime then
                        state.powerShareClaimAt = GetServerTime()
                        inv = true
                    end
                end
                state.override = nil
                state.userValue = nil
                state.checkboxDoneOverride = nil
                if TaskTracker.PersistCharRegistryOverride then
                    TaskTracker.PersistCharRegistryOverride(entry.id)
                end
            end
        end
    end
    if not anyChanged then return false end

    if inv and TaskTracker.InvalidatePowerShareWinnersCache then
        TaskTracker.InvalidatePowerShareWinnersCache()
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
    return true
end

--- Drop manual checkbox / count locks when they match automated (game) progress — restores cyan bar.
function TaskTracker.TryNormalizeRegistryEntryState(registryEntryId)
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry or TaskTracker.RegistryRowIsDisplayOnly(entry) then return end
    local db = TaskTrackerDB
    local state = db and db.registryState and db.registryState[entry.id]
    if not state then return end

    local function saveOverride()
        if TaskTracker.PersistCharRegistryOverride then
            TaskTracker.PersistCharRegistryOverride(registryEntryId)
        end
    end

    if entry.type == "quest_complete" or entry.type == "mplus_hint_row" or entry.type == "collectable_owned" then
        local dispCur
        if state.userValue ~= nil and type(state.userValue) == "number" then
            dispCur = math.max(0, math.min(1, state.userValue))
        else
            dispCur = state.value or 0
            if dispCur < 0 then dispCur = 0 end
            if dispCur > 1 then dispCur = 1 end
        end
        local naturalDone = dispCur >= 1
        local cov = state.checkboxDoneOverride
        if state.override == true then cov = "complete" end
        if state.override == false then cov = "incomplete" end
        if cov == "complete" and naturalDone then
            state.checkboxDoneOverride = nil
            state.override = nil
        elseif cov == "incomplete" and not naturalDone then
            state.checkboxDoneOverride = nil
            state.override = nil
        end
        if entry.type == "quest_complete" then
            local gameCur = TaskTracker.GetRegistryQuestCompleteFromGame(entry, state)
            if state.userValue ~= nil and state.userValue == gameCur then
                state.userValue = nil
                state.value = gameCur
            end
        elseif entry.type == "collectable_owned" then
            local gameCur = TaskTracker.IsRegistryCollectableOwned(entry) and 1 or 0
            if state.userValue ~= nil and state.userValue == gameCur then
                state.userValue = nil
                state.value = gameCur
            end
        end
        saveOverride()
        return
    end

    if entry.type == "quest_count" or entry.type == "reputation_standing" then
        local max = entry.max or 1
        if entry.type == "reputation_standing" then
            local _, cap = TaskTracker.GetRegistryReputationStanding(entry)
            max = cap or max
        end
        local cur
        if state.userValue ~= nil and type(state.userValue) == "number" then
            cur = math.max(0, math.min(max, state.userValue))
        else
            cur = math.max(0, math.min(max, state.value or 0))
        end
        local naturalDone = cur >= max
        local cov = state.checkboxDoneOverride
        if cov == "complete" and naturalDone then
            state.checkboxDoneOverride = nil
        elseif cov == "incomplete" and not naturalDone then
            state.checkboxDoneOverride = nil
        end
        if not entry.manualOnly then
            local gameN
            if entry.type == "reputation_standing" then
                gameN = select(1, TaskTracker.GetRegistryReputationStanding(entry))
            else
                gameN = TaskTracker.GetRegistryQuestCountFromGame(entry, state)
            end
            if gameN ~= nil and state.userValue ~= nil and state.userValue == gameN then
                state.userValue = nil
            end
        end
    end
    saveOverride()
end

-- ─────────────────────────────────────
-- Get progress for a registry entry node
-- Returns: current, max, isDone, isOverridden
-- ─────────────────────────────────────
--- Binary quest row: 1 if any linked quest is flagged complete, else 0.
--- For multi-id weekly rows (`RegistryEntryUsesWeeklyQuestDelta`), pass `state` so progress
--- uses new completions since the weekly baseline (see CheckRegistryProgress).
function TaskTracker.GetRegistryQuestCompleteFromGame(entry, state)
    if not entry or entry.type ~= "quest_complete" then return 0 end
    if TaskTracker.RegistryEntryUsesWeeklyQuestDelta(entry) then
        local delta = TaskTracker.GetCharWeeklyQuestDelta and TaskTracker.GetCharWeeklyQuestDelta(entry) or 0
        return (delta >= 1) and 1 or 0
    end
    if TaskTracker.RegistryEntryLatchesWeeklyQuestComplete(entry) and state and state.weeklyQuestCompleteLatched then
        return 1
    end
    if not entry.quests or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return 0 end
    for qid in pairs(entry.quests) do
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
        if ok and done then return 1 end
    end
    return 0
end

--- Quest completion count for a quest_count registry entry (ignores userValue / override).
function TaskTracker.GetRegistryQuestCountFromGame(entry, state)
    if not entry or entry.type ~= "quest_count" then return 0 end
    if entry.raidTrack and TaskTracker.RaidRowProgress then
        local cur = TaskTracker.RaidRowProgress(entry)
        if cur == nil then return nil end
        return cur
    end
    local max = entry.max or 1
    if entry.widgetId and TaskTracker.GetRegistryWidgetProgressCounts then
        local cur = select(1, TaskTracker.GetRegistryWidgetProgressCounts(entry.widgetId))
        if cur ~= nil then
            return math.max(0, math.min(cur, max))
        end
        return nil
    end
    if entry.trackItemId then
        local n = TaskTracker.ItemCount(entry.trackItemId, true, false, true)
        local st = TaskTrackerDB and TaskTrackerDB.registryState and TaskTrackerDB.registryState[entry.id]
        if entry.itemAbsentMeansUsed then
            if n > 0 then
                return 0
            end
            if trackItemHadForCurrentChar(st) then
                return max
            end
            return 0
        end
        if entry.trackItemLatch then
            if n > 0 then
                markTrackItemHadForCurrentChar(st)
            end
            if trackItemHadForCurrentChar(st) then
                return max
            end
            return 0
        end
        return math.max(0, math.min(n, max))
    end
    local quests = entry.quests or {}
    if TaskTracker.RegistryEntryUsesWeeklyQuestDelta(entry) then
        local delta = TaskTracker.GetCharWeeklyQuestDelta and TaskTracker.GetCharWeeklyQuestDelta(entry) or 0
        return math.min(delta, max)
    end
    local c = 0
    for qid in pairs(quests) do
        if C_QuestLog.IsQuestFlaggedCompleted(qid) then
            c = c + 1
            if c >= max then
                return max
            end
        end
    end
    return math.min(c, max)
end

--- Weekly quest_count with max>1 and a shareKey reward: each natural completion consumes one weekly pool slot.
function TaskTracker.RegistryEntryUsesPowerSharePerCompletionClaims(entry)
    if not entry or entry.type ~= "quest_count" then return false end
    local cap = tonumber(entry.max) or 1
    if cap <= 1 then return false end
    if not TaskTracker.NormalizePowerRewardSlots then return false end
    local slots = TaskTracker.NormalizePowerRewardSlots(entry)
    for i = 1, #slots do
        local sk = slots[i].shareKey
        if type(sk) == "string" and sk ~= "" then
            return true
        end
    end
    return false
end

--- Grow/shrink registryState.powerShareClaimTimes to match synced progress (one claim time per completion).
function TaskTracker.EnsureRegistryPowerShareClaimTimes(entry, state)
    if not entry or not state or not GetServerTime then return false end
    if not TaskTracker.RegistryEntryUsesPowerSharePerCompletionClaims(entry) then return false end
    if state.userValue ~= nil then return false end
    local cap = math.max(1, tonumber(entry.max) or 1)
    local n = math.max(0, math.min(tonumber(state.value) or 0, cap))
    if type(state.powerShareClaimTimes) ~= "table" then
        state.powerShareClaimTimes = {}
    end
    local times = state.powerShareClaimTimes
    local changed = false
    -- Backfill: older logic only stamped powerShareClaimAt at max; split so the pool sees one slot per completion.
    if n > 0 and #times == 0 and type(state.powerShareClaimAt) == "number" and state.powerShareClaimAt > 0 then
        for i = 1, n do
            times[i] = state.powerShareClaimAt + (i - 1) * 0.001
        end
        changed = true
    end
    while #times < n do
        times[#times + 1] = GetServerTime()
        changed = true
    end
    while #times > n do
        table.remove(times)
        changed = true
    end
    if changed and TaskTracker.InvalidatePowerShareWinnersCache then
        TaskTracker.InvalidatePowerShareWinnersCache()
    end
    return changed
end

--- True when game progress (not checkbox override) satisfies the row for reward / share purposes.
function TaskTracker.RegistryEntryNaturallyCompleteForRewards(entry)
    if not entry or TaskTracker.RegistryRowIsDisplayOnly(entry) then return false end
    local state = TaskTrackerDB and TaskTrackerDB.registryState and TaskTrackerDB.registryState[entry.id]
    if entry.type == "quest_complete" then
        return (TaskTracker.GetRegistryQuestCompleteFromGame(entry, state) or 0) >= 1
    end
    if entry.type == "quest_count" then
        local max = entry.max or 1
        local n = TaskTracker.GetRegistryQuestCountFromGame(entry, state)
        if n == nil then return false end
        return n >= max
    end
    return false
end

--- Clear manual override and manual count lock; resync from quests.
function TaskTracker.ClearRegistryEntryManual(registryEntryId)
    local db    = TaskTrackerDB
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry or TaskTracker.RegistryRowIsDisplayOnly(entry) then return end
    local state = db.registryState and db.registryState[entry.id]
    if not state then return end
    state.override  = nil
    state.userValue = nil
    state.checkboxDoneOverride = nil
    -- Persist before resync. CheckRegistryProgress copies the character lock back onto this row.
    if TaskTracker.PersistCharRegistryOverride then
        TaskTracker.PersistCharRegistryOverride(registryEntryId)
    end
    TaskTracker.CheckRegistryProgress()
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

function TaskTracker.GetRegistryEntryProgress(registryEntryId)
    local db    = TaskTrackerDB
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry then return 0, 1, false, false end

    local state = db.registryState[entry.id]
    if not state then return 0, 1, false, false end

    local max = entry.max or 1

    if entry.type == "profession_catchup" then
        local rem = math.max(0, math.floor(tonumber(state.value) or 0))
        local isDone = rem <= 0
        return rem, 1, isDone, false
    end

    -- quest_complete: game state.value, or row-click manual 0/1 in userValue; strip = checkbox only.
    if entry.type == "quest_complete" or entry.type == "mplus_hint_row" or entry.type == "collectable_owned" then
        local cur
        if state.userValue ~= nil and type(state.userValue) == "number" then
            cur = math.max(0, math.min(1, state.userValue))
        else
            cur = state.value or 0
            if cur < 0 then cur = 0 end
            if cur > 1 then cur = 1 end
            if entry.type == "mplus_hint_row" and TaskTracker.MPlusRegistryHintIsAutoMaxed
                and TaskTracker.MPlusRegistryHintIsAutoMaxed(entry) then
                cur = 1
            end
        end
        local qmax = 1
        local naturalDone = cur >= 1
        local cov = state.checkboxDoneOverride
        if state.override == true then cov = "complete" end
        if state.override == false then cov = "incomplete" end
        local isDone, rowOverride
        if cov == "complete" then
            isDone = true
            rowOverride = true
        elseif cov == "incomplete" then
            isDone = false
            rowOverride = true
        else
            isDone = naturalDone
            rowOverride = false
        end
        local fourth = rowOverride or (state.userValue ~= nil)
        return cur, qmax, isDone, fourth
    end

    if TaskTracker.RegistryRowIsDisplayOnly(entry) then
        return 0, 1, false, false
    end

    -- quest_count / reputation_standing: checkbox alone may mark done/incomplete without changing progress.
    if entry.type == "quest_count" or entry.type == "reputation_standing" then
        if entry.type == "reputation_standing" then
            local _, cap = TaskTracker.GetRegistryReputationStanding(entry)
            max = cap or max
        elseif entry.raidTrack and TaskTracker.RaidRowProgress then
            local _, cap = TaskTracker.RaidRowProgress(entry)
            if cap and cap > 0 then max = cap end
        end
        local cur
        if state.userValue ~= nil and type(state.userValue) == "number" then
            cur = math.max(0, math.min(max, state.userValue))
        else
            cur = math.max(0, math.min(max, state.value or 0))
        end
        local naturalDone = cur >= max
        local isDone
        local rowOverride = false
        if state.checkboxDoneOverride == "complete" then
            isDone = true
            rowOverride = true
        elseif state.checkboxDoneOverride == "incomplete" then
            isDone = false
            rowOverride = true
        else
            isDone = naturalDone
        end
        local fourth = rowOverride or (state.userValue ~= nil)
        return cur, max, isDone, fourth
    end

    return 0, max, false, false
end

--- Stored automation progress (`registryState.value`), before any manual count lock (`userValue`).
function TaskTracker.GetRegistryEntryAutomatedValue(registryEntryId)
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry then return 0 end
    local state = TaskTrackerDB and TaskTrackerDB.registryState and TaskTrackerDB.registryState[entry.id]
    if not state then return 0 end
    if entry.type == "quest_complete" or entry.type == "mplus_hint_row" or entry.type == "collectable_owned" then
        local v = tonumber(state.value) or 0
        if v < 0 then v = 0 end
        if v > 1 then v = 1 end
        return v
    end
    if entry.type == "quest_count" or entry.type == "reputation_standing" then
        local max = entry.max or 1
        if entry.type == "reputation_standing" then
            local _, cap = TaskTracker.GetRegistryReputationStanding(entry)
            max = cap or max
        end
        local v = tonumber(state.value) or 0
        return math.max(0, math.min(max, v))
    end
    if entry.type == "profession_catchup" then
        return math.max(0, math.floor(tonumber(state.value) or 0))
    end
    return 0
end

--- Progress popup: tracked is the manual count, automated is the sync tally.
--- On a weekly quest pool, the tally is how many count this week. Editing it moves the baseline
--- so the next sync keeps that number. A different tracked number stays a manual lock.
function TaskTracker.ApplyRegistryProgressFromPopup(registryEntryId, tracked, automated, initTracked, initAutomated)
    local entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[registryEntryId]
    if not entry or TaskTracker.RegistryRowIsDisplayOnly(entry) then return end
    local db = TaskTrackerDB
    local state = db and db.registryState and db.registryState[entry.id]
    if not state then return end

    local cap = entry.max or 1
    if entry.type == "quest_complete" or entry.type == "mplus_hint_row" or entry.type == "collectable_owned" then
        cap = 1
    elseif entry.type == "reputation_standing" and TaskTracker.GetRegistryReputationStanding then
        local _, rcap = TaskTracker.GetRegistryReputationStanding(entry)
        cap = rcap or cap
    end
    local function clampCount(n)
        n = math.floor((tonumber(n) or 0) + 0.00001)
        if n < 0 then n = 0 end
        if cap > 0 and n > cap then n = cap end
        return n
    end

    local tr = clampCount(tracked)
    local au = clampCount(automated)
    local trChanged = tr ~= clampCount(initTracked)
    local auChanged = au ~= clampCount(initAutomated)
    local followTally = (auChanged and not trChanged) or (tr == au)

    if entry.type == "quest_count" and TaskTracker.RegistryEntryUsesWeeklyQuestDelta(entry) then
        local flagged = TaskTracker.GetRegistryQuestSetCompletedCount(entry)
        local tally = au
        if tally > flagged then tally = flagged end
        if TaskTracker.SetCharWeeklyQuestDelta then
            TaskTracker.SetCharWeeklyQuestDelta(entry, tally)
        end
        state.value = tally
        state.override = nil
        state.checkboxDoneOverride = nil
        if followTally then
            state.userValue = nil
        else
            state.userValue = tr
        end
        if TaskTracker.PersistCharRegistryOverride then
            TaskTracker.PersistCharRegistryOverride(registryEntryId)
        end
        if followTally and TaskTracker.EnsureRegistryPowerShareClaimTimes then
            TaskTracker.EnsureRegistryPowerShareClaimTimes(entry, state)
        end
        TaskTracker.CheckRegistryProgress()
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then
            TaskTracker.RefreshList()
        end
        return
    end

    if followTally then
        state.value = au
        state.userValue = nil
        state.override = nil
        state.checkboxDoneOverride = nil
        if TaskTracker.PersistCharRegistryOverride then
            TaskTracker.PersistCharRegistryOverride(registryEntryId)
        end
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then
            TaskTracker.RefreshList()
        end
        return
    end

    if TaskTracker.SetRegistryAutomatedValue then
        TaskTracker.SetRegistryAutomatedValue(registryEntryId, au)
    end
    if TaskTracker.SetRegistryUserValue then
        TaskTracker.SetRegistryUserValue(registryEntryId, tr)
    end
end

--- Set stored automation (`state.value`) without changing `userValue`. Clamped to the row cap.
function TaskTracker.SetRegistryAutomatedValue(registryEntryId, value)
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry or TaskTracker.RegistryRowIsDisplayOnly(entry) then return end
    if entry.type ~= "quest_count" and entry.type ~= "quest_complete" and entry.type ~= "mplus_hint_row"
        and entry.type ~= "collectable_owned" and entry.type ~= "reputation_standing" then
        return
    end
    local db = TaskTrackerDB
    local state = db and db.registryState and db.registryState[entry.id]
    if not state then return end

    local v = tonumber(value)
    if v == nil then return end
    v = math.floor(v + 0.00001)
    local cap = (entry.type == "quest_complete" or entry.type == "mplus_hint_row" or entry.type == "collectable_owned")
        and 1 or (entry.max or 1)
    if entry.type == "reputation_standing" then
        local _, rcap = TaskTracker.GetRegistryReputationStanding(entry)
        cap = rcap or cap
    end
    if v < 0 then v = 0 end
    if v > cap then v = cap end

    state.value = v
    if TaskTracker.EnsureRegistryPowerShareClaimTimes then
        TaskTracker.EnsureRegistryPowerShareClaimTimes(entry, state)
    end
    if TaskTracker.TryNormalizeRegistryEntryState then
        TaskTracker.TryNormalizeRegistryEntryState(registryEntryId)
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

function TaskTracker.IsTaskEffectivelyDone(node)
    if not node or node.type ~= "task" then return false end
    if TaskTracker.IsAdvancedTask(node) and node.advanced.type == "mplus_hint"
        and TaskTracker.MPlusHintIsAutoInactive and TaskTracker.MPlusHintIsAutoInactive(node) then
        return true
    end
    if TaskTracker.TaskHasExtraGoals and TaskTracker.TaskHasExtraGoals(node) and TaskTracker.GoalRecordIsDone then
        if node.doneOverride == "complete" then return true end
        if node.doneOverride == "incomplete" then return false end
        local mode = node.goalMode == "any" and "any" or "all"
        local primaryDone = TaskTracker.GoalRecordIsDone(node, node)
        if mode == "any" then
            if primaryDone then return true end
            for i = 1, #node.extraGoals do
                if TaskTracker.GoalRecordIsDone(node, node.extraGoals[i]) then
                    return true
                end
            end
            return false
        end
        if not primaryDone then return false end
        for i = 1, #node.extraGoals do
            if not TaskTracker.GoalRecordIsDone(node, node.extraGoals[i]) then
                return false
            end
        end
        return true
    end
    if node.doneOverride ~= "incomplete"
        and TaskTracker.IsCollectableTaskJournalOwned and TaskTracker.IsCollectableTaskJournalOwned(node) then
        return true
    end
    local tm = node.taskMax or 1
    if tm <= 1 then
        return node.done and true or false
    end
    local c = node.taskUserValue
    if type(c) ~= "number" then
        c = node.taskCount or 0
    end
    if node.doneOverride == "complete" then
        return true
    elseif node.doneOverride == "incomplete" then
        return false
    end
    return c >= tm
end

--- Yellow bar: manual (non-advanced) custom tasks, or advanced tasks after any override.
--- Cyan bar: advanced tasks still following automation only.
function TaskTracker.TaskRowShowsManualAutomationBar(node)
    if not node or node.type ~= "task" then return true end
    if node.generatedTask then return false end
    local function slotManual(rec)
        local adv = rec and rec.advanced
        local automated = type(adv) == "table" and adv.type ~= nil
        if not automated then return true end
        if rec.taskUserValue ~= nil then return true end
        if rec.doneOverride ~= nil then return true end
        return false
    end
    if slotManual(node) then return true end
    if TaskTracker.TaskHasExtraGoals and TaskTracker.TaskHasExtraGoals(node) then
        for i = 1, #node.extraGoals do
            if slotManual(node.extraGoals[i]) then return true end
        end
    end
    return false
end

--- Yellow when registry row is user-touched; cyan when driven only by game data.
function TaskTracker.RegistryRowShowsManualAutomationBar(registryEntryId)
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry or TaskTracker.RegistryRowIsDisplayOnly(entry) then return false end
    local state = TaskTrackerDB and TaskTrackerDB.registryState and TaskTrackerDB.registryState[entry.id]
    if not state then return false end
    if state.override ~= nil then return true end
    if state.checkboxDoneOverride ~= nil then return true end
    if (entry.type == "quest_count" or entry.type == "reputation_standing") and state.userValue ~= nil then return true end
    if (entry.type == "quest_complete" or entry.type == "mplus_hint_row" or entry.type == "collectable_owned")
        and state.userValue ~= nil then return true end
    return false
end

--- Checkbox right-click: force incomplete / off (tasks).
function TaskTracker.TaskCheckboxTurnOff(nodeID)
    if TaskTracker.DismissGeneratedTask and TaskTracker.DismissGeneratedTask(nodeID) then
        return
    end
    local node = TaskTracker.FindNode(nodeID)
    if not node or node.type ~= "task" then return end
    if TaskTracker.RefuseLockedTaskProgress and TaskTracker.RefuseLockedTaskProgress(node) then return end
    local tm = node.taskMax or 1
    if TaskTracker.TaskHasExtraGoals and TaskTracker.TaskHasExtraGoals(node) then
        node.doneOverride = "incomplete"
    elseif tm <= 1 then
        node.done = false
        node.taskCount = 0
        if TaskTracker.IsAdvancedTask(node) then
            node.taskUserValue = 0
        end
    else
        node.doneOverride = "incomplete"
        if TaskTracker.IsAdvancedTask(node) then
            local c = node.taskUserValue
            if type(c) ~= "number" then c = node.taskCount or 0 end
            node.taskUserValue = c
        end
    end
    if TaskTracker.TryNormalizeTaskOverrideAndLock then
        TaskTracker.TryNormalizeTaskOverrideAndLock(node)
    end
    if TaskTracker.NotifyTaskProgressChanged then
        TaskTracker.NotifyTaskProgressChanged(node)
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

--- Registry strip: left toggles done/incomplete; right only turns off (incomplete).
function TaskTracker.ToggleRegistryCheckboxDone(registryEntryId)
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry or TaskTracker.RegistryRowIsDisplayOnly(entry) then return end
    local db = TaskTrackerDB
    local state = db and db.registryState and db.registryState[entry.id]
    if not state then return end
    local _, _, isDone = TaskTracker.GetRegistryEntryProgress(registryEntryId)

    if entry.type == "quest_complete" or entry.type == "mplus_hint_row" or entry.type == "collectable_owned" then
        state.override = nil
        if isDone then
            state.checkboxDoneOverride = "incomplete"
        else
            state.checkboxDoneOverride = "complete"
        end
    elseif entry.type == "quest_count" or entry.type == "reputation_standing" then
        if isDone then
            state.checkboxDoneOverride = "incomplete"
        else
            state.checkboxDoneOverride = "complete"
        end
    else
        return
    end
    TaskTracker.TryNormalizeRegistryEntryState(registryEntryId)
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

function TaskTracker.RegistryCheckboxTurnOff(registryEntryId)
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry or TaskTracker.RegistryRowIsDisplayOnly(entry) then return end
    local db = TaskTrackerDB
    local state = db and db.registryState and db.registryState[entry.id]
    if not state then return end
    local _, _, isDone = TaskTracker.GetRegistryEntryProgress(registryEntryId)
    if not isDone then return end

    if entry.type == "quest_complete" or entry.type == "mplus_hint_row" or entry.type == "collectable_owned" then
        state.override = nil
        state.checkboxDoneOverride = "incomplete"
    elseif entry.type == "quest_count" or entry.type == "reputation_standing" then
        state.checkboxDoneOverride = "incomplete"
    else
        return
    end
    TaskTracker.TryNormalizeRegistryEntryState(registryEntryId)
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

--- When true, the task still lists and tracks progress but does not count toward parent group roll-ups
--- (header x/y leaf totals) or summed group progress.
function TaskTracker.TaskExcludedFromGroupRollup(node)
    return node and node.type == "task" and node.excludeFromRollup == true
end

--- Left-side eye. Off unless the player turns it on. A finished row stays listed
--- when completed tasks are hidden.
function TaskTracker.NodeKeepsShownWhenComplete(node)
    return type(node) == "table" and node.alwaysShow == true
end

-- ─────────────────────────────────────
-- Get progress for any node recursively
-- Returns: doneParts, totalParts, isDone
-- ─────────────────────────────────────
function TaskTracker.GetNodeProgress(node, underPowerSubtree)
    if not node then return 0, 0, false end
    underPowerSubtree = underPowerSubtree or false

    if node.type == "task" then
        if TaskTracker.IsCollectionFarmTaskListed and not TaskTracker.IsCollectionFarmTaskListed(node) then
            return 0, 0, false
        end
        if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then
            return 0, 0, false
        end
        local db = TaskTrackerDB
        local effDone = TaskTracker.IsTaskEffectivelyDone(node)
        if db and db.hideCompleted and effDone and node.alwaysShow ~= true then
            return 0, 0, false
        end
        local tMax = node.taskMax or 1
        if TaskTracker.TaskHasExtraGoals and TaskTracker.TaskHasExtraGoals(node) then
            local c = node.taskUserValue
            if type(c) ~= "number" then
                c = node.taskCount or 0
            end
            if tMax <= 1 then
                c = node.done and 1 or 0
                tMax = 1
            end
            return c, tMax, effDone, false
        end
        if tMax > 1 then
            local c = node.taskUserValue
            if type(c) ~= "number" then
                c = node.taskCount or 0
            end
            return c, tMax, effDone, false
        end
        if type(node.taskUserValue) == "number" then
            local c = node.taskUserValue >= 1 and 1 or 0
            return c, 1, effDone, false
        end
        return (effDone and 1 or 0), 1, effDone, false

    elseif node.type == "registryEntry" then
        if not TaskTracker.IsRegistryRowTrackedForList(node.registryEntryId, underPowerSubtree) then
            return 0, 0, false
        end
        local entry = TaskTracker.RegistryByID[node.registryEntryId]
        if entry and TaskTracker.RegistryRowIsDisplayOnly(entry) then
            return 0, 0, false
        end
        local cur, max, isDone = TaskTracker.GetRegistryEntryProgress(node.registryEntryId)
        return cur, max, isDone

    elseif node.type == "group" or node.type == "root" then
        if node.type == "group" and TaskTracker.ProfessionModuleSubgroupVisible
            and not TaskTracker.ProfessionModuleSubgroupVisible(node) then
            return 0, 0, false
        end
        local nextUnder = underPowerSubtree or IsPowerModuleGroup(node)
        local totalDone, totalMax = 0, 0
        if node.children then
            for _, child in ipairs(node.children) do
                if not TaskTracker.TaskExcludedFromGroupRollup(child) then
                    local d, m = TaskTracker.GetNodeProgress(child, nextUnder)
                    totalDone = totalDone + d
                    totalMax  = totalMax  + m
                end
            end
        end
        return totalDone, totalMax, totalMax > 0 and totalDone >= totalMax
    end

    return 0, 0, false
end

-- ─────────────────────────────────────
-- Leaf progress for any node recursively
-- Returns: doneLeaves, totalLeaves — each task/registry leaf counts as 1 done or 0,
-- total is the number of leaves (not summed internal objective counts).
-- Disabled/vault registry rows contribute 0/0 (same as list rows).
-- ─────────────────────────────────────
local function leafCacheSlot(node)
    local cache = TaskTracker._ttLeafCache
    local gen = TaskTracker._ttLeafGen
    if not cache or not gen or not node or not node.id then return nil end
    local s = cache[node.id]
    if s and s.gen == gen then return s end
    return nil
end

function TaskTracker.GetNodeLeafProgress(node, underPowerSubtree)
    if not node then return 0, 0 end
    underPowerSubtree = underPowerSubtree or false

    local slot = leafCacheSlot(node)
    if slot then
        return slot.done, slot.total
    end

    if node.type == "task" then
        if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
            return 0, 0
        end
        if TaskTracker.IsCollectionFarmTaskListed and not TaskTracker.IsCollectionFarmTaskListed(node) then
            return 0, 0
        end
        if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then
            return 0, 0
        end
        if TaskTracker.TaskExcludedFromGroupRollup(node) then
            return 0, 0
        end
        local effDone = TaskTracker.IsTaskEffectivelyDone(node)
        return (effDone and 1 or 0), 1

    elseif node.type == "registryEntry" then
        if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
            return 0, 0
        end
        if not TaskTracker.IsRegistryRowTrackedForList(node.registryEntryId, underPowerSubtree) then
            return 0, 0
        end
        local entry = TaskTracker.RegistryByID[node.registryEntryId]
        if entry and TaskTracker.RegistryRowIsDisplayOnly(entry) then
            return 0, 0
        end
        local _, _, isDone = TaskTracker.GetRegistryEntryProgress(node.registryEntryId)
        return (isDone and 1 or 0), 1

    elseif node.type == "group" or node.type == "root" then
        if node.type == "group" and TaskTracker.ProfessionModuleSubgroupVisible
            and not TaskTracker.ProfessionModuleSubgroupVisible(node) then
            return 0, 0
        end
        if node.type == "group" and TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
            return 0, 0
        end
        local nextUnder = underPowerSubtree or IsPowerModuleGroup(node)
        local done, total = 0, 0
        if node.children then
            for _, child in ipairs(node.children) do
                local d, t = TaskTracker.GetNodeLeafProgress(child, nextUnder)
                done = done + d
                total = total + t
            end
        end
        return done, total
    end

    return 0, 0
end

--- Under hide-completed, a group is normally pruned when rollup leaves are all done.
--- Still render the subtree when it contains (a) an incomplete task excluded from rollup counts,
--- or (b) a tracked Great Vault preview row (display-only; never part of rollup x/y).
--- Prefer `GroupHideCompletedHasSubtreeHoldouts` after `BuildLeafProgressCache`.
local function GroupHideCompletedHoldoutsWalkUncached(node, underPowerSubtree)
    if not node then return false end
    underPowerSubtree = underPowerSubtree or false
    if node.type == "task" then
        if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
            return false
        end
        if TaskTracker.IsCollectionFarmTaskListed and not TaskTracker.IsCollectionFarmTaskListed(node) then
            return false
        end
        if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then
            return false
        end
        if node.alwaysShow == true and TaskTracker.IsTaskEffectivelyDone(node) then
            return true
        end
        return TaskTracker.TaskExcludedFromGroupRollup(node) and not TaskTracker.IsTaskEffectivelyDone(node)
    elseif node.type == "registryEntry" then
        if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
            return false
        end
        if not TaskTracker.IsRegistryRowTrackedForList(node.registryEntryId, underPowerSubtree) then
            return false
        end
        local entry = TaskTracker.RegistryByID[node.registryEntryId]
        if entry and TaskTracker.RegistryRowIsDisplayOnly(entry) then
            return true
        end
        if node.alwaysShow == true and entry then
            local _, _, isDone = TaskTracker.GetRegistryEntryProgress(node.registryEntryId)
            if isDone then return true end
        end
        return false
    elseif node.type == "group" or node.type == "root" then
        if node.type == "group" and TaskTracker.ProfessionModuleSubgroupVisible
            and not TaskTracker.ProfessionModuleSubgroupVisible(node) then
            return false
        end
        if node.type == "group" and TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
            return false
        end
        local nextUnder = underPowerSubtree or IsPowerModuleGroup(node)
        if node.children then
            for _, ch in ipairs(node.children) do
                if GroupHideCompletedHoldoutsWalkUncached(ch, nextUnder) then
                    return true
                end
            end
        end
    end
    return false
end

function TaskTracker.GroupHideCompletedHasSubtreeHoldouts(node, underPowerSubtree)
    if not node then return false end
    local slot = leafCacheSlot(node)
    if slot then
        return slot.hideHoldout == true
    end
    return GroupHideCompletedHoldoutsWalkUncached(node, underPowerSubtree or false)
end

-- ─────────────────────────────────────
-- Leaf progress cache (single pass)
-- Runtime side table keyed by node id — never written onto SavedVariables nodes.
-- ─────────────────────────────────────
function TaskTracker.BuildLeafProgressCache(root)
    if not root then return 0, 0 end

    TaskTracker._ttLeafGen = (TaskTracker._ttLeafGen or 0) + 1
    local gen = TaskTracker._ttLeafGen
    local cache = TaskTracker._ttLeafCache
    if not cache then
        cache = {}
        TaskTracker._ttLeafCache = cache
    else
        wipe(cache)
    end

    local function stamp(node, done, total, hold)
        if not node or not node.id then return done, total end
        cache[node.id] = {
            gen = gen,
            done = done,
            total = total,
            hideHoldout = hold and true or false,
        }
        return done, total
    end

    local function walk(node, underPowerSubtree)
        underPowerSubtree = underPowerSubtree or false
        if not node then return 0, 0 end

        if node.type == "task" then
            if TaskTracker.IsHiddenByZoneFilter and TaskTracker.IsHiddenByZoneFilter(node) then
                return stamp(node, 0, 0, false)
            end
            if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
                return stamp(node, 0, 0, false)
            end
            if TaskTracker.IsCollectionFarmTaskListed and not TaskTracker.IsCollectionFarmTaskListed(node) then
                return stamp(node, 0, 0, false)
            end
            if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then
                return stamp(node, 0, 0, false)
            end
            if TaskTracker.TaskExcludedFromGroupRollup(node) then
                local excludedDone = TaskTracker.IsTaskEffectivelyDone(node)
                local hold = (not excludedDone) or (node.alwaysShow == true and excludedDone)
                return stamp(node, 0, 0, hold)
            end
            local effDone = TaskTracker.IsTaskEffectivelyDone(node)
            return stamp(node, (effDone and 1 or 0), 1, node.alwaysShow == true and effDone)

        elseif node.type == "registryEntry" then
            if TaskTracker.IsHiddenByZoneFilter and TaskTracker.IsHiddenByZoneFilter(node) then
                return stamp(node, 0, 0, false)
            end
            if TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
                return stamp(node, 0, 0, false)
            end
            if not TaskTracker.IsRegistryRowTrackedForList(node.registryEntryId, underPowerSubtree) then
                return stamp(node, 0, 0, false)
            end
            local entry = TaskTracker.RegistryByID[node.registryEntryId]
            if entry and TaskTracker.RegistryRowIsDisplayOnly(entry) then
                return stamp(node, 0, 0, true)
            end
            local _, _, isDone = TaskTracker.GetRegistryEntryProgress(node.registryEntryId)
            return stamp(node, (isDone and 1 or 0), 1, node.alwaysShow == true and isDone)

        elseif node.type == "group" or node.type == "root" then
            -- Same skip as GetNodeLeafProgress and the list. An unlearned profession
            -- group stays in the tree, but it is not on the list, so it is not in the header.
            if node.type == "group" and TaskTracker.ProfessionModuleSubgroupVisible
                and not TaskTracker.ProfessionModuleSubgroupVisible(node) then
                return stamp(node, 0, 0, false)
            end
            if node.type == "group" and TaskTracker.IsHiddenByListKindFilter and TaskTracker.IsHiddenByListKindFilter(node) then
                return stamp(node, 0, 0, false)
            end
            local nextUnder = underPowerSubtree or IsPowerModuleGroup(node)
            local done, total = 0, 0
            local holdAny = false
            if node.children then
                for _, child in ipairs(node.children) do
                    local d, t = walk(child, nextUnder)
                    done = done + d
                    total = total + t
                    local cs = child.id and cache[child.id]
                    if cs and cs.hideHoldout then
                        holdAny = true
                    end
                end
            end
            return stamp(node, done, total, holdAny)
        end

        return stamp(node, 0, 0, false)
    end

    return walk(root, false)
end

-- ─────────────────────────────────────
-- Toggle manual override on a registry entry node
-- Cycles: none -> opposite of game state -> none
-- ─────────────────────────────────────
function TaskTracker.ToggleRegistryOverride(registryEntryId)
    local db    = TaskTrackerDB
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry then return end
    if TaskTracker.RegistryRowIsDisplayOnly(entry) then return end
    if entry.type == "quest_count" or entry.type == "reputation_standing" then return end

    local state = db.registryState[entry.id]
    if not state then return end

    local _, _, isDone, isOverridden = TaskTracker.GetRegistryEntryProgress(registryEntryId)

    state.override = nil
    if not isOverridden then
        if isDone then
            state.checkboxDoneOverride = "incomplete"
        else
            state.checkboxDoneOverride = "complete"
        end
    else
        state.checkboxDoneOverride = nil
    end

    TaskTracker.TryNormalizeRegistryEntryState(registryEntryId)
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

-- ─────────────────────────────────────
-- Toggle a task node done state
-- ─────────────────────────────────────
function TaskTracker.ToggleTaskDone(nodeID)
    local node = TaskTracker.FindNode(nodeID)
    if not node or node.type ~= "task" then return end
    if TaskTracker.RefuseLockedTaskProgress and TaskTracker.RefuseLockedTaskProgress(node) then return end
    if (node.taskMax or 1) > 1 then
        return
    end
    node.done = not node.done
    node.taskCount = node.done and 1 or 0
    if TaskTracker.IsAdvancedTask(node) then
        node.taskUserValue = node.taskCount
    end
    if TaskTracker.NotifyTaskProgressChanged then
        TaskTracker.NotifyTaskProgressChanged(node)
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

--- Checkbox only: single-count toggles done/count; multi-count toggles completion without changing the counter.
function TaskTracker.ToggleTaskCheckboxDone(nodeID)
    if TaskTracker.IsGeneratedTaskId and TaskTracker.IsGeneratedTaskId(nodeID) then
        return
    end
    local node = TaskTracker.FindNode(nodeID)
    if not node or node.type ~= "task" then return end
    if TaskTracker.RefuseLockedTaskProgress and TaskTracker.RefuseLockedTaskProgress(node) then return end
    local tm = node.taskMax or 1
    if tm <= 1 and not (TaskTracker.TaskHasExtraGoals and TaskTracker.TaskHasExtraGoals(node)) then
        TaskTracker.ToggleTaskDone(nodeID)
        return
    end
    local c = node.taskUserValue
    if type(c) ~= "number" then
        c = node.taskCount or 0
    end
    if TaskTracker.IsTaskEffectivelyDone(node) then
        node.doneOverride = "incomplete"
    else
        node.doneOverride = "complete"
    end
    if TaskTracker.IsAdvancedTask(node) then
        node.taskUserValue = c
    end
    if TaskTracker.TryNormalizeTaskOverrideAndLock then
        TaskTracker.TryNormalizeTaskOverrideAndLock(node)
    end
    if TaskTracker.NotifyTaskProgressChanged then
        TaskTracker.NotifyTaskProgressChanged(node)
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

local function adjustGoalRecord(node, rec, delta)
    local m = rec.taskMax or 1
    local adv = rec.advanced
    local isAdv = type(adv) == "table" and adv.type ~= nil
    if m <= 1 then
        local c = (rec.done and 1 or 0) + delta
        if c < 0 then c = 0 end
        if c > 1 then c = 1 end
        rec.taskCount = c
        rec.done = (c >= 1)
        if isAdv then rec.taskUserValue = rec.taskCount end
    else
        local base = rec.taskUserValue
        if type(base) ~= "number" then base = rec.taskCount or 0 end
        local c = base + delta
        if c < 0 then c = 0 end
        if not (isAdv and m > 1) and c > m then c = m end
        if isAdv and m > 1 then
            rec.taskUserValue = c
        else
            rec.taskCount = c
            rec.done = c >= m
        end
    end
    if not isAdv then rec.taskUserValue = nil end
end

function TaskTracker.AdjustTaskCount(nodeID, delta)
    local node = TaskTracker.FindNode(nodeID)
    if not node or node.type ~= "task" then return end
    if TaskTracker.RefuseLockedTaskProgress and TaskTracker.RefuseLockedTaskProgress(node, delta) then return end
    if TaskTracker.TaskHasExtraGoals and TaskTracker.TaskHasExtraGoals(node)
        and TaskTracker.FirstUnfinishedGoalIndex then
        local idx = TaskTracker.FirstUnfinishedGoalIndex(node)
        if idx > 1 then
            local rec = node.extraGoals[idx - 1]
            if rec then
                adjustGoalRecord(node, rec, delta)
                if TaskTracker.NotifyTaskProgressChanged then
                    TaskTracker.NotifyTaskProgressChanged(node)
                end
                if TaskTracker.MarkListDirtyFromProgressChange then
                    TaskTracker.MarkListDirtyFromProgressChange()
                end
                if TaskTracker.RefreshList then TaskTracker.RefreshList() end
            end
            return
        end
    end
    local m = node.taskMax or 1
    if m <= 1 then
        local c = (node.done and 1 or 0) + delta
        if c < 0 then c = 0 end
        if c > 1 then c = 1 end
        node.taskCount = c
        node.done = (c >= 1)
    else
        local base = node.taskUserValue
        if type(base) ~= "number" then
            base = node.taskCount or 0
        end
        local c = base + delta
        if c < 0 then c = 0 end
        if not (TaskTracker.IsAdvancedTask(node) and m > 1) and c > m then
            c = m
        end
        if TaskTracker.IsAdvancedTask(node) and m > 1 then
            node.taskUserValue = c
        else
            node.taskCount = c
        end
    end
    if TaskTracker.IsAdvancedTask(node) then
        if m <= 1 then
            node.taskUserValue = node.taskCount
        end
    else
        node.taskUserValue = nil
    end
    if TaskTracker.TryNormalizeTaskOverrideAndLock then
        TaskTracker.TryNormalizeTaskOverrideAndLock(node)
    end
    if TaskTracker.NotifyTaskProgressChanged then
        TaskTracker.NotifyTaskProgressChanged(node)
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

--- Live automation tally for list rows: item/currency `itemAutoCount` when present, else `taskCount`.
function TaskTracker.GetTaskAutomatedCount(node)
    if not node or node.type ~= "task" then return 0 end
    if TaskTracker.IsAdvancedTask(node) and node.advanced then
        local a = node.advanced
        if a.type == "item" then
            local ac = tonumber(a.itemAutoCount)
            if ac ~= nil then
                return math.max(0, math.floor(ac + 0.00001))
            end
        elseif a.type == "collectable" then
            local q = math.max(0, tonumber(a.collectableAutoCount) or 0)
            local f = math.max(0, tonumber(a.collectableFishAttempts) or 0)
            return math.max(0, math.floor(q + f + 0.00001))
        end
    end
    return math.max(0, math.floor((node.taskCount or 0) + 0.00001))
end

--- Apply tracked + automated values from the shift-click progress popup.
--- `initTracked` / `initAutomated` are the values shown when the dialog opened (automation-only edits).
function TaskTracker.GoalSlotProgress(node, index)
    local rec = (index and index > 1) and node.extraGoals and node.extraGoals[index - 1] or node
    if not rec then return 0, 1, 0 end
    local c = rec.taskUserValue
    if type(c) ~= "number" then c = rec.taskCount or 0 end
    local m = rec.taskMax or 1
    local auto = c
    local adv = rec.advanced
    if type(adv) == "table" and adv.type == "item" and tonumber(adv.itemAutoCount) then
        auto = math.max(0, math.floor(tonumber(adv.itemAutoCount) + 0.00001))
    elseif type(adv) == "table" and adv.type == "collectable" then
        local q = math.max(0, tonumber(adv.collectableAutoCount) or 0)
        local f = math.max(0, tonumber(adv.collectableFishAttempts) or 0)
        auto = math.max(0, math.floor(q + f + 0.00001))
    end
    return c, m, auto
end

--- True when this task or extra-goal slot can lock its list count. Second return is whether it is locked now.
function TaskTracker.ProgressEditLockState(node, slotIndex)
    if not node or node.type ~= "task" then return false, false end
    slotIndex = tonumber(slotIndex) or 1
    local rec = node
    if slotIndex > 1 then
        rec = node.extraGoals and node.extraGoals[slotIndex - 1]
        if type(rec) ~= "table" then return false, false end
    end
    local adv = rec.advanced
    local isAdv = type(adv) == "table" and adv.type ~= nil
    if slotIndex == 1 then
        isAdv = TaskTracker.IsAdvancedTask(node) and true or false
    end
    if not isAdv then return false, false end
    return true, rec.taskUserValue ~= nil
end

--- Same progress editor as Shift-left-click on a task or registry count.
function TaskTracker.OpenProgressEditForNode(node)
    if not node or not TaskTracker.ShowSetCountPopup then return end
    if node.type == "task" and TaskTracker.RefuseLockedTaskProgress and TaskTracker.RefuseLockedTaskProgress(node) then
        return
    end
    if node.type == "registryEntry" then
        local rid = node.registryEntryId
        if not rid then return end
        local cur, max = 0, 0
        if TaskTracker.GetRegistryEntryProgress then
            cur, max = TaskTracker.GetRegistryEntryProgress(rid)
        end
        cur = tonumber(cur) or 0
        max = tonumber(max) or 0
        local autoC = (TaskTracker.GetRegistryEntryAutomatedValue and TaskTracker.GetRegistryEntryAutomatedValue(rid)) or cur
        local entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[rid]
        local label = (entry and entry.label) or node.name or "Entry"
        TaskTracker.ShowSetCountPopup({
            title = label .. " progress",
            cur = cur,
            autoCur = autoC,
            max = max,
            onAccept = function(tr, au)
                if TaskTracker.ApplyRegistryProgressFromPopup then
                    TaskTracker.ApplyRegistryProgressFromPopup(rid, tr, au, cur, autoC)
                end
            end,
        })
        return
    end
    if node.type ~= "task" or not node.id then return end
    local progDone, progMax = 0, 1
    if TaskTracker.GetNodeProgress then
        progDone, progMax = TaskTracker.GetNodeProgress(node)
    end
    local slot, cur, max, autoC = 1, progDone, progMax,
        (TaskTracker.GetTaskAutomatedCount and TaskTracker.GetTaskAutomatedCount(node)) or progDone
    local allowOver = TaskTracker.IsAdvancedTask(node) and (progMax or 1) > 1
    if TaskTracker.TaskHasExtraGoals and TaskTracker.TaskHasExtraGoals(node)
        and TaskTracker.FirstUnfinishedGoalIndex and TaskTracker.GoalSlotProgress then
        slot = TaskTracker.FirstUnfinishedGoalIndex(node)
        cur, max, autoC = TaskTracker.GoalSlotProgress(node, slot)
        local rec = slot > 1 and node.extraGoals and node.extraGoals[slot - 1] or node
        local adv = rec and rec.advanced
        allowOver = type(adv) == "table" and adv.type ~= nil and (max or 1) > 1
    end
    local id = node.id
    TaskTracker.ShowSetCountPopup({
        title = (node.name or "Task") .. " progress",
        cur = cur,
        autoCur = autoC,
        max = max,
        allowOverMax = allowOver,
        node = node,
        slot = slot,
        onAccept = function(tr, au, locked)
            if TaskTracker.ApplyTaskProgressFromPopup then
                TaskTracker.ApplyTaskProgressFromPopup(id, tr, au, cur, autoC, slot, locked)
            end
        end,
    })
end

function TaskTracker.ApplyTaskProgressFromPopup(nodeID, tracked, automated, initTracked, initAutomated, slotIndex, locked)
    local node = TaskTracker.FindNode(nodeID)
    if not node or node.type ~= "task" then return end
    if TaskTracker.RefuseLockedTaskProgress and TaskTracker.RefuseLockedTaskProgress(node) then return end
    slotIndex = tonumber(slotIndex)
    if slotIndex and slotIndex > 1 and node.extraGoals and node.extraGoals[slotIndex - 1] then
        local rec = node.extraGoals[slotIndex - 1]
        local gm = rec.taskMax or 1
        local tr = tonumber(tracked)
        local au = tonumber(automated)
        if tr == nil or au == nil then return end
        tr = math.floor(tr + 0.00001)
        au = math.floor(au + 0.00001)
        if tr < 0 then tr = 0 end
        if au < 0 then au = 0 end
        local adv = rec.advanced
        local isAdv = type(adv) == "table" and adv.type ~= nil
        local allowOver = isAdv and gm > 1
        if not allowOver then
            if gm > 0 and tr > gm then tr = gm end
            if gm > 0 and au > gm then au = gm end
        end
        if isAdv and gm > 1 then
            if adv.type == "item" then
                adv.itemAutoCount = au
            elseif adv.type == "collectable" then
                adv.collectableInit = true
                local fp = math.max(0, tonumber(adv.collectableFishAttempts) or 0)
                adv.collectableAutoCount = math.max(0, au - fp)
            end
            if locked == true then
                rec.taskUserValue = tr
            elseif locked == false then
                rec.taskUserValue = nil
                rec.taskCount = au
            else
                local initTr = tonumber(initTracked)
                local initAu = tonumber(initAutomated)
                local trChanged = initTr == nil or tr ~= math.floor(initTr + 0.00001)
                local auChanged = initAu == nil or au ~= math.floor(initAu + 0.00001)
                if (auChanged and not trChanged) or tr == au then
                    rec.taskUserValue = nil
                    rec.taskCount = au
                else
                    rec.taskUserValue = tr
                end
            end
            rec.doneOverride = nil
            rec.done = (rec.taskCount or 0) >= gm
        else
            rec.taskCount = au
            if gm <= 1 then
                rec.done = tr >= 1
                rec.taskCount = tr
            else
                rec.taskCount = tr
                rec.done = tr >= gm
            end
            if locked == true then
                rec.taskUserValue = tr
                rec.doneOverride = nil
            elseif locked == false then
                rec.taskUserValue = nil
                rec.doneOverride = nil
            elseif not isAdv then
                rec.taskUserValue = nil
            end
        end
        if TaskTracker.NotifyTaskProgressChanged then
            TaskTracker.NotifyTaskProgressChanged(node)
        end
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then TaskTracker.RefreshList() end
        return
    end
    local m = node.taskMax or 1
    local tr = tonumber(tracked)
    local au = tonumber(automated)
    if tr == nil or au == nil then return end
    tr = math.floor(tr + 0.00001)
    au = math.floor(au + 0.00001)
    if tr < 0 then tr = 0 end
    if au < 0 then au = 0 end
    local allowOver = TaskTracker.IsAdvancedTask(node) and m > 1
    if not allowOver then
        if m > 0 and tr > m then tr = m end
        if m > 0 and au > m then au = m end
    end

    if TaskTracker.IsAdvancedTask(node) and m > 1 then
        local adv = node.advanced
        if adv and adv.type == "item" then
            adv.itemAutoCount = au
        elseif adv and adv.type == "collectable" then
            adv.collectableInit = true
            local fp = math.max(0, tonumber(adv.collectableFishAttempts) or 0)
            adv.collectableAutoCount = math.max(0, au - fp)
        end
        if locked == true then
            node.taskUserValue = tr
        elseif locked == false then
            node.taskUserValue = nil
            node.taskCount = au
        else
            local initTr = tonumber(initTracked)
            local initAu = tonumber(initAutomated)
            local trChanged = initTr == nil or tr ~= math.floor(initTr + 0.00001)
            local auChanged = initAu == nil or au ~= math.floor(initAu + 0.00001)
            if (auChanged and not trChanged) or tr == au then
                node.taskUserValue = nil
                node.taskCount = au
            else
                node.taskUserValue = tr
            end
        end
        node.doneOverride = nil
        node.done = TaskTracker.IsTaskEffectivelyDone(node)
        if adv and adv.type == "collectable" and TaskTracker.UpdateCollectableFromQuestFlags then
            TaskTracker.UpdateCollectableFromQuestFlags(node)
        end
        if locked == false and TaskTracker.SyncAdvancedTask then
            TaskTracker.SyncAdvancedTask(node)
        end
    else
        TaskTracker.SetTaskAutomatedCount(nodeID, au)
        TaskTracker.SetTaskCount(nodeID, tr)
        if locked == false and TaskTracker.IsAdvancedTask(node) then
            node.taskUserValue = nil
            node.doneOverride = nil
            if node.advanced and node.advanced.type == "collectable" and TaskTracker.UpdateCollectableFromQuestFlags then
                TaskTracker.UpdateCollectableFromQuestFlags(node)
            end
            if TaskTracker.SyncAdvancedTask then
                TaskTracker.SyncAdvancedTask(node)
            end
            if TaskTracker.RefreshList then
                TaskTracker.RefreshList()
            end
        elseif locked == true and TaskTracker.IsAdvancedTask(node) then
            node.taskUserValue = tr
            if TaskTracker.RefreshList then
                TaskTracker.RefreshList()
            end
        end
        return
    end

    if TaskTracker.NotifyTaskProgressChanged then
        TaskTracker.NotifyTaskProgressChanged(node)
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

--- Set automation storage (`taskCount`, and `itemAutoCount` for advanced item rows). Does not change manual `taskUserValue`.
function TaskTracker.SetTaskAutomatedCount(nodeID, value)
    local node = TaskTracker.FindNode(nodeID)
    if not node or node.type ~= "task" then return end
    if TaskTracker.RefuseLockedTaskProgress and TaskTracker.RefuseLockedTaskProgress(node) then return end
    local m = node.taskMax or 1
    local v = tonumber(value)
    if v == nil then return end
    v = math.floor(v + 0.00001)
    if v < 0 then v = 0 end
    if not (TaskTracker.IsAdvancedTask(node) and m > 1) and v > m then
        v = m
    end

    if TaskTracker.IsAdvancedTask(node) and node.advanced and node.advanced.type == "item" and m > 1 then
        node.advanced.itemAutoCount = v
        if node.taskUserValue == nil then
            node.taskCount = v
            node.done = (v >= m)
        end
    elseif m <= 1 then
        node.taskCount = v
        node.done = (v >= 1)
    else
        node.taskCount = v
        if node.taskUserValue == nil then
            node.done = (v >= m)
        end
    end

    if TaskTracker.TryNormalizeTaskOverrideAndLock then
        TaskTracker.TryNormalizeTaskOverrideAndLock(node)
    end
    if TaskTracker.NotifyTaskProgressChanged then
        TaskTracker.NotifyTaskProgressChanged(node)
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

--- Set a task's progress count directly (clamped). For advanced multi-count tasks, sets manual `taskUserValue` only (automation stays separate).
function TaskTracker.SetTaskCount(nodeID, value)
    local node = TaskTracker.FindNode(nodeID)
    if not node or node.type ~= "task" then return end
    if TaskTracker.RefuseLockedTaskProgress and TaskTracker.RefuseLockedTaskProgress(node) then return end
    local m = node.taskMax or 1
    local v = tonumber(value)
    if v == nil then return end
    v = math.floor(v + 0.00001)
    if v < 0 then v = 0 end
    if not (TaskTracker.IsAdvancedTask(node) and m > 1) and v > m then
        v = m
    end

    if m <= 1 then
        node.taskCount = v
        node.done = (v >= 1)
    else
        if TaskTracker.IsAdvancedTask(node) then
            node.taskUserValue = v
        else
            node.taskCount = v
        end
    end

    if TaskTracker.IsAdvancedTask(node) then
        if m <= 1 then
            node.taskUserValue = v
        end
    else
        node.taskUserValue = nil
    end

    if TaskTracker.TryNormalizeTaskOverrideAndLock then
        TaskTracker.TryNormalizeTaskOverrideAndLock(node)
    end
    if TaskTracker.NotifyTaskProgressChanged then
        TaskTracker.NotifyTaskProgressChanged(node)
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

--- Left = +1, right = −1 for module rows: quest_count adjusts manual count; quest_complete sets override toward done / not done.
function TaskTracker.ApplyRegistryRowClick(registryEntryId, delta)
    delta = tonumber(delta) or 0
    if delta == 0 then return end
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry or TaskTracker.RegistryRowIsDisplayOnly(entry) then return end
    if entry.type == "profession_catchup" then return end

    if entry.type == "quest_count" or entry.type == "reputation_standing" then
        local db = TaskTrackerDB
        local state = db.registryState and db.registryState[entry.id]
        if not state then return end
        local max = entry.max or 1
        if entry.type == "reputation_standing" then
            local _, cap = TaskTracker.GetRegistryReputationStanding(entry)
            max = cap or max
        end
        local base = state.userValue
        if base == nil then base = state.value or 0 end
        base = math.max(0, math.min(max, base))
        if delta > 0 and base >= max then return end
        if delta < 0 and base <= 0 then return end
        TaskTracker.AdjustRegistryUserValue(registryEntryId, delta)
        return
    end

    if entry.type == "quest_complete" or entry.type == "mplus_hint_row" or entry.type == "collectable_owned" then
        local db = TaskTrackerDB
        local state = db.registryState and db.registryState[entry.id]
        if not state then return end
        local cap = 1
        local base = state.userValue
        if base == nil then
            base = state.value or 0
        end
        base = math.max(0, math.min(cap, base))
        if delta > 0 and base >= cap then return end
        if delta < 0 and base <= 0 then return end
        local nv = base + delta
        if nv < 0 then nv = 0 end
        if nv > cap then nv = cap end
        state.userValue = nv
        state.override = nil
        state.checkboxDoneOverride = nil
        if entry.type == "quest_complete" then
            local gameCur = TaskTracker.GetRegistryQuestCompleteFromGame(entry, state)
            if state.userValue ~= nil and gameCur == state.userValue then
                state.userValue = nil
                state.value = gameCur
            end
        elseif entry.type == "collectable_owned" then
            local gameCur = TaskTracker.IsRegistryCollectableOwned(entry) and 1 or 0
            if state.userValue ~= nil and gameCur == state.userValue then
                state.userValue = nil
                state.value = gameCur
            end
        end
        TaskTracker.TryNormalizeRegistryEntryState(registryEntryId)
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then
            TaskTracker.RefreshList()
        end
        return
    end

    if delta > 0 then
        TaskTracker.ToggleRegistryOverride(registryEntryId)
    end
end

function TaskTracker.AdjustRegistryUserValue(registryEntryId, delta)
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry or (entry.type ~= "quest_count" and entry.type ~= "reputation_standing") then return end
    local db    = TaskTrackerDB
    local state = db.registryState and db.registryState[entry.id]
    if not state then return end
    local max   = entry.max or 1
    if entry.type == "reputation_standing" then
        local _, cap = TaskTracker.GetRegistryReputationStanding(entry)
        max = cap or max
    end
    local base  = state.userValue
    if base == nil then
        base = state.value or 0
    end
    local nv = base + delta
    if nv < 0 then nv = 0 end
    if nv > max then nv = max end
    state.userValue = nv
    state.override  = nil
    state.checkboxDoneOverride = nil
    if not entry.manualOnly then
        local gameN
        if entry.type == "reputation_standing" then
            gameN = select(1, TaskTracker.GetRegistryReputationStanding(entry))
        else
            gameN = TaskTracker.GetRegistryQuestCountFromGame(entry, state)
        end
        if gameN ~= nil and nv == gameN then
            state.userValue = nil
            if TaskTracker.PersistCharRegistryOverride then
                TaskTracker.PersistCharRegistryOverride(registryEntryId)
            end
            TaskTracker.CheckRegistryProgress()
        end
    end
    TaskTracker.TryNormalizeRegistryEntryState(registryEntryId)
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

--- Set a registry entry's manual userValue directly (clamped).
--- For quest_count: sets manual count lock; for quest_complete: sets manual 0/1 completion.
function TaskTracker.SetRegistryUserValue(registryEntryId, value)
    local entry = TaskTracker.RegistryByID[registryEntryId]
    if not entry or TaskTracker.RegistryRowIsDisplayOnly(entry) then return end
    local db    = TaskTrackerDB
    local state = db.registryState and db.registryState[entry.id]
    if not state then return end

    local v = tonumber(value)
    if v == nil then return end
    v = math.floor(v + 0.00001)

    local cap = (entry.type == "quest_complete" or entry.type == "mplus_hint_row" or entry.type == "collectable_owned")
        and 1 or (entry.max or 1)
    if entry.type == "reputation_standing" then
        local _, rcap = TaskTracker.GetRegistryReputationStanding(entry)
        cap = rcap or cap
    end
    if v < 0 then v = 0 end
    if v > cap then v = cap end

    if entry.type ~= "quest_count" and entry.type ~= "quest_complete" and entry.type ~= "mplus_hint_row"
        and entry.type ~= "collectable_owned" and entry.type ~= "reputation_standing" then
        return
    end

    state.userValue = v
    state.override  = nil
    state.checkboxDoneOverride = nil

    if entry.type == "quest_count" and not entry.manualOnly then
        local gameN = TaskTracker.GetRegistryQuestCountFromGame(entry, state)
        if gameN ~= nil and v == gameN then
            state.userValue = nil
            if TaskTracker.PersistCharRegistryOverride then
                TaskTracker.PersistCharRegistryOverride(registryEntryId)
            end
            TaskTracker.CheckRegistryProgress()
        end
    elseif entry.type == "quest_complete" then
        local gameCur = TaskTracker.GetRegistryQuestCompleteFromGame(entry, state)
        if gameCur ~= nil and v == gameCur then
            state.userValue = nil
            state.value = gameCur
        end
    elseif entry.type == "collectable_owned" then
        local gameCur = TaskTracker.IsRegistryCollectableOwned(entry) and 1 or 0
        if v == gameCur then
            state.userValue = nil
            state.value = gameCur
        end
    elseif entry.type == "reputation_standing" then
        local gameN = select(1, TaskTracker.GetRegistryReputationStanding(entry))
        if gameN ~= nil and v == gameN then
            state.userValue = nil
            if TaskTracker.PersistCharRegistryOverride then
                TaskTracker.PersistCharRegistryOverride(registryEntryId)
            end
            TaskTracker.CheckRegistryProgress()
        end
    end

    TaskTracker.TryNormalizeRegistryEntryState(registryEntryId)
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

function TaskTracker.DisableAllRegistryUnderGroup(groupNode)
    if not groupNode then return end
    local powerGroup = IsPowerModuleGroup(groupNode)
    local function visit(n)
        if n.type == "registryEntry" then
            if powerGroup then
                TaskTracker.SetCharRegistryVisEnabled(n.registryEntryId, "powerListEnabled", false)
            else
                TaskTracker.SetCharRegistryVisEnabled(n.registryEntryId, "enabled", false)
            end
        elseif n.type == "task" and n.collectionFarmId then
            TaskTracker.SetCharRegistryVisEnabled(n.collectionFarmId, "enabled", false)
        elseif n.children then
            for _, c in ipairs(n.children) do
                visit(c)
            end
        end
    end
    visit(groupNode)
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

-- ─────────────────────────────────────
-- Toggle a registry entry enabled state
-- Called from options panel
-- ─────────────────────────────────────
function TaskTracker.SetEntryEnabled(entryID, enabled)
    if not TaskTracker.RegistryByID or not TaskTracker.RegistryByID[entryID] then return end
    local wasOn = TaskTracker.IsEntryEnabled(entryID) ~= false
    local turningOn = enabled ~= false
    if TaskTracker.SetCharRegistryVisEnabled then
        TaskTracker.SetCharRegistryVisEnabled(entryID, "enabled", turningOn)
    end
    if turningOn and not wasOn and TaskTracker.ResetBuiltinTaskToSeed then
        TaskTracker.ResetBuiltinTaskToSeed(entryID)
    end
    if TaskTracker.SyncMPlusDungeonGuidesPackTree then
        TaskTracker.SyncMPlusDungeonGuidesPackTree()
    end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

-- ─────────────────────────────────────
-- Check if a registry entry is enabled
-- ─────────────────────────────────────
function TaskTracker.IsEntryEnabled(entryID)
    if TaskTracker.GetCharRegistryVisEnabled then
        return TaskTracker.GetCharRegistryVisEnabled(entryID, "enabled")
    end
    return true
end

--- Seeded Collections farm tasks: listed when the Modules toggle is on.
function TaskTracker.IsCollectionFarmTaskListed(node)
    if not node or node.type ~= "task" then return true end
    -- A share is their copy of the row, not this account's module switch.
    if node.liveShareRole == "receiver" then return true end
    local rid = node.collectionFarmId
    if type(rid) ~= "string" or rid == "" then return true end
    if TaskTracker.IsEntryEnabled(rid) == false then return false end
    local entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[rid]
    if entry and TaskTracker.IsCollectionsModuleRowHidden and TaskTracker.IsCollectionsModuleRowHidden(entry) then
        return false
    end
    return true
end

--- Visibility in the Power tree group (separate from Modules / home expansion toggles).
function TaskTracker.IsPowerListEntryEnabled(entryID)
    if TaskTracker.GetCharRegistryVisEnabled then
        return TaskTracker.GetCharRegistryVisEnabled(entryID, "powerListEnabled")
    end
    return true
end

function TaskTracker.SetPowerListEntryEnabled(entryID, enabled)
    if not TaskTracker.RegistryByID or not TaskTracker.RegistryByID[entryID] then return end
    if TaskTracker.SetCharRegistryVisEnabled then
        TaskTracker.SetCharRegistryVisEnabled(entryID, "powerListEnabled", enabled ~= false)
    end
    if TaskTracker.SyncMPlusDungeonGuidesPackTree then
        TaskTracker.SyncMPlusDungeonGuidesPackTree()
    end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

-- ─────────────────────────────────────
-- Bulk enable/disable (Options → Modules section buttons)
-- ─────────────────────────────────────
function TaskTracker.AreAllRegistryEntriesEnabledForExpansion(expansionKey)
    if expansionKey == "power" then
        for _, entry in ipairs(TaskTracker.GetEntriesForPowerModule()) do
            if entry.hideFromPowerOptions then
                -- Controlled elsewhere; not shown in Modules → Power grid.
            elseif not TaskTracker.IsPowerListEntryEnabled(entry.id) then
                return false
            end
        end
        return true
    end
    for _, entry in ipairs(TaskTracker.Registry or {}) do
        if entry.expansion == expansionKey then
            if expansionKey == "professions" and TaskTracker.ProfessionRegistryEntryVisible
                and not TaskTracker.ProfessionRegistryEntryVisible(entry) then
                -- Unlearned profession rows are omitted from the module UI.
            elseif TaskTracker.IsRegistryRequireOwnedLocked
                and TaskTracker.IsRegistryRequireOwnedLocked(entry) then
                -- Hidden until the named collectable is owned.
            elseif not TaskTracker.IsEntryEnabled(entry.id) then
                return false
            end
        end
    end
    return true
end

function TaskTracker.SetAllRegistryEntriesForExpansion(expansionKey, enabled)
    local on = enabled ~= false
    if expansionKey == "power" then
        for _, entry in ipairs(TaskTracker.GetEntriesForPowerModule()) do
            if not entry.hideFromPowerOptions then
                TaskTracker.SetCharRegistryVisEnabled(entry.id, "powerListEnabled", on)
            end
        end
    else
        for _, entry in ipairs(TaskTracker.Registry or {}) do
            if entry.expansion == expansionKey then
                if expansionKey == "professions" and TaskTracker.ProfessionRegistryEntryVisible
                    and not TaskTracker.ProfessionRegistryEntryVisible(entry) then
                    -- skip unlearned
                elseif TaskTracker.IsRegistryRequireOwnedLocked
                    and TaskTracker.IsRegistryRequireOwnedLocked(entry) then
                    -- skip locked
                else
                    TaskTracker.SetCharRegistryVisEnabled(entry.id, "enabled", on)
                    if not on and TaskTracker.SetCollectionsShowCollectedOverride
                        and TaskTracker.IsCollectionsModuleEntry and TaskTracker.IsCollectionsModuleEntry(entry) then
                        TaskTracker.SetCollectionsShowCollectedOverride(entry.id, false)
                    end
                end
            end
        end
    end
    if TaskTracker.SyncMPlusDungeonGuidesPackTree then
        TaskTracker.SyncMPlusDungeonGuidesPackTree()
    end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

local PATCH_1210_ACTIVITY_SUBS = {
    patch_12_1_0_coiled_isle = true,
    patch_12_1_0_vaults = true,
}
local PATCH_1215_ACTIVITY_SUBS = {
    patch_12_1_5_aqir = true,
}

local function registrySubsectionMatches(entrySub, subsectionKey)
    entrySub = entrySub or "_default"
    if entrySub == subsectionKey then return true end
    -- Patch 12.1.0 header Enable all covers The Coiled Isle + Vaults (not Collections).
    if subsectionKey == "patch_12_1_0" and PATCH_1210_ACTIVITY_SUBS[entrySub] then
        return true
    end
    if subsectionKey == "patch_12_1_5" and PATCH_1215_ACTIVITY_SUBS[entrySub] then
        return true
    end
    return false
end

function TaskTracker.AreAllRegistryEntriesEnabledForSubsection(expansionKey, subsectionKey)
    -- Power's grid is the reward mirror (Midnight, Seasonal, and so on), not expansion == "power".
    if expansionKey == "power" then
        local entries = TaskTracker.GetEntriesForPowerModule and TaskTracker.GetEntriesForPowerModule() or {}
        for _, entry in ipairs(entries) do
            if not entry.hideFromPowerOptions
                and registrySubsectionMatches(entry.subsection, subsectionKey)
                and not TaskTracker.IsPowerListEntryEnabled(entry.id) then
                return false
            end
        end
        return true
    end
    for _, entry in ipairs(TaskTracker.Registry or {}) do
        if entry.expansion == expansionKey and registrySubsectionMatches(entry.subsection, subsectionKey) then
            if expansionKey == "professions" and TaskTracker.ProfessionRegistryEntryVisible
                and not TaskTracker.ProfessionRegistryEntryVisible(entry) then
                -- Unlearned profession subsection rows.
            elseif TaskTracker.IsRegistryRequireOwnedLocked
                and TaskTracker.IsRegistryRequireOwnedLocked(entry) then
                -- Hidden until the named collectable is owned.
            elseif not TaskTracker.IsEntryEnabled(entry.id) then
                return false
            end
        end
    end
    return true
end

function TaskTracker.SetAllRegistryEntriesForSubsection(expansionKey, subsectionKey, enabled)
    local on = enabled ~= false
    if expansionKey == "power" then
        local entries = TaskTracker.GetEntriesForPowerModule and TaskTracker.GetEntriesForPowerModule() or {}
        for _, entry in ipairs(entries) do
            if not entry.hideFromPowerOptions
                and registrySubsectionMatches(entry.subsection, subsectionKey) then
                TaskTracker.SetCharRegistryVisEnabled(entry.id, "powerListEnabled", on)
            end
        end
    else
        for _, entry in ipairs(TaskTracker.Registry or {}) do
            if entry.expansion == expansionKey
                and registrySubsectionMatches(entry.subsection, subsectionKey) then
                if expansionKey == "professions" and TaskTracker.ProfessionRegistryEntryVisible
                    and not TaskTracker.ProfessionRegistryEntryVisible(entry) then
                    -- skip unlearned
                elseif TaskTracker.IsRegistryRequireOwnedLocked
                    and TaskTracker.IsRegistryRequireOwnedLocked(entry) then
                    -- skip locked
                else
                    TaskTracker.SetCharRegistryVisEnabled(entry.id, "enabled", on)
                    if not on and TaskTracker.SetCollectionsShowCollectedOverride
                        and TaskTracker.IsCollectionsModuleEntry and TaskTracker.IsCollectionsModuleEntry(entry) then
                        TaskTracker.SetCollectionsShowCollectedOverride(entry.id, false)
                    end
                end
            end
        end
    end
    if TaskTracker.SyncMPlusDungeonGuidesPackTree then
        TaskTracker.SyncMPlusDungeonGuidesPackTree()
    end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

-- ─────────────────────────────────────
-- Get reset tag string for a node
-- ─────────────────────────────────────
function TaskTracker.GetNodeResetTag(node)
    if node.type == "task" then
        local tag = ""
        local account = TaskTracker.IsTaskAccountWide and TaskTracker.IsTaskAccountWide(node)
        if node.reset == "daily" then
            tag = account and " |cffaaaaaa[AD]|r" or " |cffaaaaaa[D]|r"
        elseif node.reset == "weekly" then
            tag = account and " |cffaaaaaa[AW]|r" or " |cffaaaaaa[W]|r"
        elseif node.reset == "temporary" then
            tag = " |cffaaaaaa[T]|r"
        end
        if TaskTracker.GetLiveShareOwnerNameTag then
            tag = tag .. TaskTracker.GetLiveShareOwnerNameTag(node)
        end
        return tag
    elseif node.type == "registryEntry" then
        local entry = TaskTracker.RegistryByID[node.registryEntryId]
        if entry then
            if entry.reset == "daily"  then return " |cffaaaaaa[D]|r" end
            if entry.reset == "weekly" then return " |cffaaaaaa[W]|r" end
        end
    end
    return ""
end

-- ─────────────────────────────────────
-- Get display label for a node
-- ─────────────────────────────────────
function TaskTracker.GetNodeLabel(node)
    if node.type == "task" then
        local name = node.name or ""
        if node.welcomeIcon and TaskTracker.ChromeIconMarkup then
            return TaskTracker.ChromeIconMarkup(node.welcomeIcon, 14, 14) .. " " .. name
        end
        return name
    elseif node.type == "registryEntry" then
        local entry = TaskTracker.RegistryByID[node.registryEntryId]
        return entry and entry.label or "Unknown"
    elseif node.type == "group" then
        return node.name
    end
    return "Unknown"
end

-- ─────────────────────────────────────
-- Tooltip copy: where row data comes from
-- ─────────────────────────────────────

local function sortedQuestIdList(entry)
    local ids = {}
    for qid in pairs(entry.quests or {}) do
        ids[#ids + 1] = qid
    end
    table.sort(ids)
    return ids
end

local MAX_ACTIVE_QUEST_TIP = 8

local function questLogIndex(qid)
    if not C_QuestLog or not C_QuestLog.GetLogIndexForQuestID then return nil end
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, qid)
    if ok and type(idx) == "number" and idx > 0 then return idx end
    return nil
end

local function questTitleForLogId(qid, logIdx)
    if C_QuestLog and C_QuestLog.GetInfo and logIdx then
        local ok, info = pcall(C_QuestLog.GetInfo, logIdx)
        if ok and type(info) == "table" and type(info.title) == "string" and info.title ~= "" then
            return info.title
        end
    end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, qid)
        if ok and type(t) == "string" and t ~= "" then return t end
    end
    return "Quest " .. tostring(qid)
end

--- Quests this row tracks that are currently in the player's log (accepted).
--- @return table|nil list of { id, name }
function TaskTracker.GetActiveTrackedQuests(entry, node)
    local ids
    if entry then
        ids = entry._ttQuestIds
        if (not ids or #ids == 0) and entry.quests then
            ids = sortedQuestIdList(entry)
        end
    end
    if (not ids or #ids == 0) and node then
        if (not entry) and node.type == "registryEntry" and TaskTracker.RegistryByID then
            local e = TaskTracker.RegistryByID[node.registryEntryId]
            if e then return TaskTracker.GetActiveTrackedQuests(e, nil) end
        end
        if node.type == "task" and node.advanced and node.advanced.type == "quest" then
            ids = node.advanced.questIds
        end
    end
    if type(ids) ~= "table" or #ids == 0 then return nil end

    local out
    for i = 1, #ids do
        local qid = tonumber(ids[i])
        if qid and qid > 0 then
            local idx = questLogIndex(qid)
            if idx then
                out = out or {}
                out[#out + 1] = { id = qid, name = questTitleForLogId(qid, idx) }
                if #out >= MAX_ACTIVE_QUEST_TIP then break end
            end
        end
    end
    return out
end

function TaskTracker.GetTaskDataSourceTooltipLines(node)
    if not node or node.type ~= "task" then return {} end
    local lines = {}
    if TaskTracker.IsAdvancedTask(node) then
        local t = node.advanced.type
        if t ~= "collectable" then
            lines[1] = "Advanced task: progress is read from the game when possible; left/right on the row adjusts the count and locks manual progress."
                .. " (Option: you can require Shift for row increments.)"
            lines[2] = "The checkbox toggles complete without changing the count. Ctrl-left-click on the row clears the lock and resyncs."
            if t == "gold" then
                lines[3] = "Gold tracking: " .. (node.advanced.goldMode == "gross" and "gross earned (positive money changes only)" or "net gain (all money changes).")
                lines[4] = "Gold reset schedule: " .. (node.advanced.goldResetSource == "override" and tostring(node.advanced.resetOverride or "none") or "inherits the task reset field") .. "."
            elseif t == "achievement" then
                local aid = tonumber(node.advanced.achievementId) or 0
                if (tonumber(node.advanced.achievementCriteriaIndex) or 0) == 0 then
                    lines[3] = string.format("Achievement id |cff00ccff%d|r — tracks completed criteria vs. total (same as in-game progress).", aid)
                elseif node.advanced.achievementMirrorGameTotals then
                    lines[3] = string.format("Achievement id |cff00ccff%d|r — mirrors the in-game bar (current / total) for the chosen criterion.", aid)
                else
                    lines[3] = string.format("Achievement id |cff00ccff%d|r — weekly progress vs. in-game numeric criteria.", aid)
                end
            elseif t == "item" then
                lines[3] = "Item collection: " .. (node.advanced.itemTrackMode == "total" and "current bag total" or "items earned (bag deltas)") .. "."
            elseif t == "quest" then
                lines[3] = "Quest list: counts how many listed quests are flagged complete in-game; goal is how many must be done. With a daily/weekly reset, only new completions since the period started count."
            elseif t == "reputation" then
                lines[3] = "Reputation: reacts to faction updates. Standing goals use the progress bar only (no subtitle). Other goal types may show a subtitle (Renown, Paragon, or classic rep details)."
            end
        else
            lines[1] = "Collectable: the row shows farm progress vs your goal (for example 0/30). Each qualifying rare kill adds +1. It also completes when you learn the item."
            lines[2] = "Left/right on the row adjusts the count. Ctrl-left-click clears a manual lock. Parent groups add this same count into their totals."
        end
    else
        lines[1] = "This is a custom task stored in Task Tracker (not read from the game automatically)."
    end
    if TaskTracker.TaskHasExtraGoals and TaskTracker.TaskHasExtraGoals(node) then
        if node.goalMode == "any" then
            lines[#lines + 1] = "Finish when: any one goal."
        else
            lines[#lines + 1] = "Finish when: every goal."
        end
        if TaskTracker.FormatTaskGoalSummary then
            local summary = TaskTracker.FormatTaskGoalSummary(node)
            if summary then
                lines[#lines + 1] = summary
            end
        end
        lines[#lines + 1] = "Left/right on the count changes the first goal that is not finished."
    end
    if node.excludeFromRollup then
        lines[#lines + 1] = "Excluded from parent group goal counts (tracking only)."
    end
    if node.reset == "daily" then
        lines[#lines + 1] = "Reset: daily (see Options → General: daily / weekly reset schedule)."
    elseif node.reset == "weekly" then
        lines[#lines + 1] = "Reset: weekly (see Options → General: daily / weekly reset schedule)."
    elseif node.reset == "temporary" then
        lines[#lines + 1] = "Reset: temporary — this task is removed from your list when it completes."
    else
        lines[#lines + 1] = "Reset: none — it stays until you change it."
    end
    if node.liveShareRole == "receiver" and type(node.liveShareOwner) == "string" and node.liveShareOwner ~= "" then
        if node.liveShareTwoWay == true then
            lines[#lines + 1] = "Synced from " .. node.liveShareOwner .. ". You can move it, and you can add to the count. You can't lower it."
        else
            lines[#lines + 1] = "Synced from " .. node.liveShareOwner .. ". You can move it. Progress follows them."
        end
    elseif node.liveShareRole == "owner" and type(node.liveShareTo) == "string" and node.liveShareTo ~= "" then
        if node.liveShareTwoWay == true then
            lines[#lines + 1] = "Synced to " .. node.liveShareTo .. ". They can add to the count, and it syncs back to you."
        else
            lines[#lines + 1] = "Synced to " .. node.liveShareTo .. ". Their count follows yours."
        end
    end
    if TaskTracker.IsTaskAccountWide and TaskTracker.IsTaskAccountWide(node) then
        lines[#lines + 1] = "Progress: account-wide (shared across characters on this account)."
    else
        lines[#lines + 1] = "Progress: per character."
        if node.showOnOtherCharacters == true then
            lines[#lines + 1] = "Visible on all characters (each character has its own progress)."
        else
            lines[#lines + 1] = "Hidden on other characters (only the creator sees this row)."
        end
    end
    if TaskTracker.IsAdvancedTask(node) then
        -- covered above
    elseif (node.taskMax or 1) > 1 then
        lines[#lines + 1] = "Left/right on the row adjusts the count. The checkbox toggles complete without changing the count."
            .. " (Option: you can require Shift for row increments.)"
    else
        lines[#lines + 1] = "Left/right on the row adjusts progress. The checkbox toggles done."
            .. " (Option: you can require Shift for row increments.)"
    end
    return lines
end

function TaskTracker.GetRegistryDataSourceTooltipLines(entry)
    if not entry then return {} end
    local lines = {}

    if entry.type == "vault_row" then
        lines[1] = "Shows the three Great Vault reward item levels for this row (Raid, Dungeon, or World), matching what you see in the Weekly Rewards / Great Vault UI for the current week."
        lines[2] = "If you have not unlocked a slot yet, that position shows a dash until the game provides a reward preview."
        return lines
    end

    if entry.raidTrack == "bosses" then
        lines[1] = "Counts bosses killed this week on this difficulty. The row finishes when every boss is dead."
        return lines
    end
    if entry.raidTrack == "vault" then
        lines[1] = "Counts Great Vault raid slots for this difficulty. The row finishes when the vault is full. That takes 6 bosses."
        return lines
    end

    if entry.type == "mplus_hint_row" then
        lines[1] = "Uses the current season M+ reward table. End-of-dungeon and dungeon vault both compare to your lowest equipped item (or the Details ilvl). Empty vault slots are not treated as 0. If all three dungeon slots are already filled, the weakest filled slot is used when it is higher than your gear."
        if not entry.mplusHintKind then
            lines[1] = "Check this off yourself. Power uses the item level on this row. The gear line hides once your lowest piece reaches it. A crest line stays until that crest is outgeared too."
            if entry.id == "seasonal_dungeon_normal" then
                lines[2] = "Needs level 80."
            else
                lines[2] = "Needs level 90."
            end
            return lines
        end
        lines[2] = "Enable under Modules → Seasonal Activities → Dungeons. The subtitle updates from the game; use 0/1 and the checkbox like other manual weekly rows."
        return lines
    end

    if entry.type == "profession_catchup" then
        lines[1] = string.format(
            "Remaining catch-up knowledge from currency id |cff00ccff%d|r (maxQuantity − totalEarned), matching the Midnight profession weekly macros.",
            tonumber(entry.catchupCurrencyId) or 0)
        lines[2] = "The row is complete when no catch-up remains. Only professions you have learned appear under Modules → Professions."
        return lines
    end

    if entry.type == "collectable_owned" then
        local kind = tostring(entry.collectableKind or "item")
        local idBit = tonumber(entry.itemId) or tonumber(entry.mountId) or tonumber(entry.petSpeciesId) or 0
        lines[1] = string.format(
            "Complete when this %s is in your collection (item/journal id |cff00ccff%d|r).",
            kind, idBit)
        local qids = sortedQuestIdList(entry)
        if #qids > 0 then
            lines[1] = lines[1] .. string.format(" Also complete if quest |cff00ccff%s|r is flagged done.", table.concat(qids, ", "))
        end
        lines[2] = "This is owned-or-not tracking, not a farm counter. Left/right still lets you override; Ctrl-left-click clears a lock."
        return lines
    end

    if entry.type == "reputation_standing" then
        local fid = tonumber(entry.factionId) or 0
        if entry.repKind == "classic" then
            lines[1] = string.format(
                "Reputation with faction |cff00ccff%d|r. Weekly gain toward |cff00ccff%d|r. Neutral through Exalted.",
                fid, tonumber(entry.weeklyGain) or tonumber(entry.max) or 500)
        elseif fid == 2838 then
            lines[1] = "Friendship with the Aqir Research Enclave. The bar finishes at 5000."
        elseif entry.repKind == "renown" then
            lines[1] = string.format(
                "Renown with faction |cff00ccff%d|r. The bar is current level vs |cff00ccff%d|r.",
                fid, tonumber(entry.max) or 20)
        elseif entry.repKind == "friendship" then
            lines[1] = string.format(
                "Friendship ranks with faction |cff00ccff%d|r. Complete at max rank (|cff00ccff%d|r).",
                fid, tonumber(entry.max) or 5)
        else
            lines[1] = string.format("Reputation standing with faction |cff00ccff%d|r.", fid)
        end
        lines[2] = "Progress updates from the reputation UI. Left/right can override; Ctrl-left-click clears a lock."
        return lines
    end

    if entry.widgetId and entry.type == "quest_count" then
        lines[1] = string.format(
            "Progress is read from WoW’s Delves UI widget #%s (same counter as the Gilded Stash bar / tooltip, e.g. stashes looted).",
            tostring(entry.widgetId))
        lines[2] = "If you are not in Delves content, the widget may be hidden and the count can stay at the last value or zero until it updates."
        return lines
    end

    if entry.type == "quest_complete" then
        if entry.trackNpcIds or entry.trackEncounterName or entry.trackLootObjectIds then
            local bits = {}
            if entry.trackEncounterName then
                bits[#bits + 1] = string.format("ENCOUNTER_END name |cff00ccff%s|r", tostring(entry.trackEncounterName))
            end
            if entry.trackNpcIds then
                local ids = {}
                for i = 1, #entry.trackNpcIds do
                    ids[i] = tostring(entry.trackNpcIds[i])
                end
                bits[#bits + 1] = "NPC id " .. table.concat(ids, ", ")
            end
            if entry.trackLootObjectIds then
                local ids = {}
                for i = 1, #entry.trackLootObjectIds do
                    ids[i] = tostring(entry.trackLootObjectIds[i])
                end
                bits[#bits + 1] = "loot object " .. table.concat(ids, ", ")
            end
            lines[1] = "Synced from the kill or cache loot, not the quest log: " .. table.concat(bits, "; ") .. "."
            lines[2] = "Weekly latch: after the first complete this week, the row stays done until your weekly reset."
            return lines
        end
        local ids = sortedQuestIdList(entry)
        if #ids == 0 then
            lines[1] = "Quest completion — no quest id configured in the registry."
            return lines
        end
        local preview = {}
        local nShow = math.min(12, #ids)
        for i = 1, nShow do
            preview[i] = tostring(ids[i])
        end
        local idStr = table.concat(preview, ", ")
        if #ids > nShow then
            idStr = idStr .. ", …"
        end
        lines[1] = string.format(
            "Synced from the quest log: complete when |cff00ccffany|r of these quests is flagged completed: %s.",
            idStr)
        if entry.latchWeeklyQuestComplete and entry.reset == "weekly" then
            lines[2] = "Weekly latch: after the first flag-complete this week, the row stays done until your weekly reset even if the quest flag drops later."
        elseif #ids > 1 and entry.reset == "weekly" then
            lines[2] = "Weekly pool: only |cff00ccffnew|r completions since the first sync after your weekly reset count—stale flags for other ids in the pool are ignored."
        end
        return lines
    end

    if entry.type == "quest_count" then
        if entry.trackItemId then
            lines[1] = string.format(
                "Item id |cff00ccff%d|r — presence checked in bags, bank, and reagent bank.",
                entry.trackItemId)
            if entry.itemAbsentMeansUsed then
                lines[2] = "Marked complete when count hits zero only after this character held at least one copy since your weekly reset. Each character has their own latch, so another character using the item does not complete this row."
            else
                lines[2] = "Progress is how many copies you currently hold, capped by max."
            end
            lines[3] = "You can still override with left/right-click on the row; Ctrl-left-click the row to clear a manual lock."
            return lines
        end
        if entry.manualOnly then
            lines[1] = "Manual weekly counter: use left-click / right-click on the row to adjust. It is not synced from the quest log."
            lines[2] = string.format("Cap: %d per week (resets with your weekly schedule in Options → General).", entry.max or 0)
            return lines
        end
        local ids = sortedQuestIdList(entry)
        if #ids == 0 then
            lines[1] = "Quest count — no quest IDs listed in the registry."
            return lines
        end
        local preview = {}
        local nShow = math.min(10, #ids)
        for i = 1, nShow do
            preview[i] = tostring(ids[i])
        end
        local idStr = table.concat(preview, ", ")
        if #ids > nShow then
            idStr = idStr .. ", …"
        end
        lines[1] = string.format(
            "Synced from the quest log: counts how many of these quests are flagged complete (cap %d). Quest ids: %s.",
            entry.max or #ids,
            idStr)
        lines[2] = "Each id is checked the same way as a single-quest row (quest log completion flag)."
        if #ids > 1 and entry.reset == "weekly" then
            lines[3] = "Weekly pool: progress is |cff00ccffnew|r completions since the first sync after reset, so ids still flagged from older weeks do not fill the bar."
        end
        return lines
    end

    lines[1] = "Tracked module entry."
    return lines
end