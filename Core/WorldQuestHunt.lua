-- Core/WorldQuestHunt.lua
-- Generated list section. World Quests groups world quests that are up right now.
-- Gold, missing collectables, a typed currency, and a typed reputation are separate
-- groups. The map walk and reward preload are time-sliced and are not part of list layout.

TaskTracker = TaskTracker or {}

local MAPS_PER_TICK = 8
local PRELOAD_PER_TICK = 3
local PRELOAD_GAP = 0.1
local SCAN_DEBOUNCE = 1.5
local RESCAN_SEC = 60
local REFRESH_DEBOUNCE = 0.25
local REWARD_TIMEOUT = 2
local RETRY_MAX = 3
local RECHECK_DEBOUNCE = 0.5

local FILTER_DEFAULT = {
    gold = true,
    collectables = true,
    currency = false,
    reputation = false,
}

local FILTER_FIELD = {
    gold = "worldQuestHuntGold",
    collectables = "worldQuestHuntCollectables",
    currency = "worldQuestHuntCurrency",
    reputation = "worldQuestHuntReputation",
}

local KIND_RANK = { mount = 1, pet = 2, toy = 3, appearance = 4 }
local KIND_LABEL = {
    mount = "Mount",
    pet = "Pet",
    toy = "Toy",
    appearance = "Appearance",
}

local cache = {}
local active = {}
local skip = {}
local itemCache = {}
local itemWait = {}

local passReady = false
local scanning = false
local scanQueued = false
local scanTimer = nil
local rescanTimer = nil
local refreshTimer = nil
local recheckTimer = nil

local phase = nil
local mapList = {}
local mapIndex = 1
local seen = {}
local preloadQueue = {}
local preloadHead = 1
local inflight = {}
local retry = {}

local function db()
    return TaskTrackerDB
end

local function publicNumber(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return tonumber(v)
end

local function plain(s)
    if type(s) ~= "string" then return nil end
    if issecretvalue and issecretvalue(s) then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|", "")
    s = s:match("^%s*(.-)%s*$")
    if not s or s == "" then return nil end
    return s
end

local function commaAmt(n)
    n = math.floor(tonumber(n) or 0)
    if BreakUpLargeNumbers then
        local ok, s = pcall(BreakUpLargeNumbers, n)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return tostring(n)
end

local function huntEnabled()
    local d = db()
    if not d or d.worldQuestHuntEnabled == nil then return true end
    return d.worldQuestHuntEnabled and true or false
end

function TaskTracker.IsWorldQuestHuntEnabled()
    return huntEnabled()
end

local function filterOn(key)
    local field = FILTER_FIELD[key]
    if not field then return false end
    local d = db()
    local v = d and d[field]
    if v == nil then return FILTER_DEFAULT[key] and true or false end
    return v and true or false
end

function TaskTracker.IsWorldQuestHuntFilterEnabled(key)
    return filterOn(key)
end

local function queryText(field)
    local d = db()
    local s = d and d[field]
    if type(s) ~= "string" then return nil end
    s = s:match("^%s*(.-)%s*$") or ""
    if s == "" then return nil end
    return s:lower()
end

function TaskTracker.GetWorldQuestHuntMinGold()
    local d = db()
    local n = d and tonumber(d.worldQuestHuntMinGold)
    if not n or n < 0 then return 500 end
    if n > 9999999 then return 9999999 end
    return math.floor(n)
end

function TaskTracker.GetWorldQuestHuntCurrencyText()
    local d = db()
    if not d or type(d.worldQuestHuntCurrencyText) ~= "string" then return "" end
    return d.worldQuestHuntCurrencyText
end

function TaskTracker.GetWorldQuestHuntReputationText()
    local d = db()
    if not d or type(d.worldQuestHuntReputationText) ~= "string" then return "" end
    return d.worldQuestHuntReputationText
end

local function expansionKnown(key)
    local list = TaskTracker.READY_TO_BUY_EXPANSIONS
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        local row = list[i]
        if row.key == key and (tonumber(row.attExpansionID) or 0) >= 7 then
            return true
        end
    end
    return false
end

function TaskTracker.IsWorldQuestHuntExpansionEnabled(key)
    if not expansionKnown(key) then return false end
    local d = db()
    local map = d and d.worldQuestHuntExpansions
    if type(map) ~= "table" then
        return key == "midnight"
    end
    return map[key] and true or false
end

function TaskTracker.WorldQuestHuntExpansionRows()
    local list = TaskTracker.READY_TO_BUY_EXPANSIONS or {}
    local out = {}
    for i = 1, #list do
        local row = list[i]
        if (tonumber(row.attExpansionID) or 0) >= 7 then
            out[#out + 1] = row
        end
    end
    return out
end

local function refreshList()
    if refreshTimer then return end
    refreshTimer = C_Timer.NewTimer(REFRESH_DEBOUNCE, function()
        refreshTimer = nil
        if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
        if TaskTracker.RefreshList then TaskTracker.RefreshList() end
    end)
end

local function cancelRescan()
    if rescanTimer then
        rescanTimer:Cancel()
        rescanTimer = nil
    end
end

local function scheduleRescan()
    cancelRescan()
    if not huntEnabled() then return end
    rescanTimer = C_Timer.NewTimer(RESCAN_SEC, function()
        rescanTimer = nil
        if TaskTracker.RequestWorldQuestHuntScan then
            TaskTracker.RequestWorldQuestHuntScan()
        end
    end)
end

local function nameMatch(name, query)
    if not query or type(name) ~= "string" then return false end
    if issecretvalue and issecretvalue(name) then return false end
    return name:lower():find(query, 1, true) ~= nil
end

local function currencyName(currencyId)
    currencyId = tonumber(currencyId)
    if not currencyId then return nil end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyId)
        if ok and type(info) == "table" then
            return plain(info.name)
        end
    end
    return nil
end

local function factionName(factionId)
    factionId = tonumber(factionId)
    if not factionId or factionId <= 0 then return nil end
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, info = pcall(C_Reputation.GetFactionDataByID, factionId)
        if ok and type(info) == "table" then
            local name = plain(info.name)
            if name then return name end
        end
    end
    if GetFactionInfoByID then
        local ok, name = pcall(GetFactionInfoByID, factionId)
        if ok then
            local text = plain(name)
            if text then return text end
        end
    end
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local ok, info = pcall(C_MajorFactions.GetMajorFactionData, factionId)
        if ok and type(info) == "table" then
            local text = plain(info.name)
            if text then return text end
        end
    end
    return nil
end

local function itemName(itemID, fallback)
    if C_Item and C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, itemID)
        local n = plain(ok and name)
        if n then return n end
    end
    if GetItemInfo then
        local ok, name = pcall(GetItemInfo, itemID)
        local n = plain(ok and name)
        if n then return n end
    end
    return fallback
end

local function questDone(qid)
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return false end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
    if not ok or done == nil then return false end
    if issecretvalue and issecretvalue(done) then return false end
    return done and true or false
end

local function hideEmptyGroups()
    local d = db()
    if not d or d.worldQuestHuntHideEmpty == nil then return true end
    return d.worldQuestHuntHideEmpty and true or false
end

local function showCompletedQuests()
    local d = db()
    return d and d.worldQuestHuntShowCompleted == true
end

--- Remember that this character has finished a world quest, so another character's tooltip can say so.
local function noteCharWorldQuestDone(qid)
    if issecretvalue and issecretvalue(qid) then return end
    qid = tonumber(qid)
    if not qid or not questDone(qid) then return end
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if not key then return end
    local d = db()
    if not d then return end
    if type(d.charWorldQuestDone) ~= "table" then d.charWorldQuestDone = {} end
    local bucket = d.charWorldQuestDone[key]
    if type(bucket) ~= "table" then
        bucket = {}
        d.charWorldQuestDone[key] = bucket
    end
    if bucket[qid] then return end
    bucket[qid] = true
end

local function isWorldQuest(qid)
    if not C_QuestLog or not C_QuestLog.IsWorldQuest then return true end
    local ok, yes = pcall(C_QuestLog.IsWorldQuest, qid)
    if not ok or yes == nil then return true end
    if issecretvalue and issecretvalue(yes) then return true end
    return yes and true or false
end

local function questTitle(qid)
    if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
        local ok, title = pcall(C_TaskQuest.GetQuestInfoByQuestID, qid)
        local name = plain(ok and title)
        if name then return name end
    end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, qid)
        local name = plain(ok and title)
        if name then return name end
    end
    return nil
end

local function questsOnMap(mapID)
    if not C_TaskQuest then return nil end
    if C_TaskQuest.GetQuestsOnMap then
        local ok, list = pcall(C_TaskQuest.GetQuestsOnMap, mapID)
        if ok and type(list) == "table" then return list end
    end
    if C_TaskQuest.GetQuestsForPlayerByMapID then
        local ok, list = pcall(C_TaskQuest.GetQuestsForPlayerByMapID, mapID)
        if ok and type(list) == "table" then return list end
    end
    return nil
end

local function poiQuestID(poi)
    if type(poi) == "number" then return publicNumber(poi) end
    if type(poi) ~= "table" then return nil end
    return publicNumber(poi.questID) or publicNumber(poi.questId)
end

local function pinXY(poi)
    if type(poi) ~= "table" then return nil, nil end
    local x = publicNumber(poi.x)
    local y = publicNumber(poi.y)
    if not x or not y then return nil, nil end
    if math.abs(x) <= 1 and math.abs(y) <= 1 then
        x = x * 100
        y = y * 100
    end
    if x == 0 and y == 0 then return nil, nil end
    return x, y
end

local function addCurrency(out, id, amount, name)
    id = publicNumber(id)
    amount = publicNumber(amount) or 0
    if not id or id <= 0 or amount <= 0 then return end
    name = plain(name) or currencyName(id)
    if not name then return end
    for i = 1, #out do
        if out[i].id == id then
            if amount > out[i].amount then out[i].amount = amount end
            return
        end
    end
    out[#out + 1] = { id = id, name = name, amount = amount }
end

local function questCurrencies(qid)
    local out = {}
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardCurrencies then
        local ok, list = pcall(C_QuestInfoSystem.GetQuestRewardCurrencies, qid)
        if ok and type(list) == "table" then
            for i = 1, #list do
                local row = list[i]
                if type(row) == "table" then
                    addCurrency(out, row.currencyID or row.currencyId, row.totalRewardAmount or row.quantity or row.displayedAmount, row.name)
                end
            end
        end
    end
    if #out == 0 and GetNumQuestLogRewardCurrencies and GetQuestLogRewardCurrencyInfo then
        local okN, n = pcall(GetNumQuestLogRewardCurrencies, qid)
        n = publicNumber(okN and n) or 0
        for i = 1, n do
            local ok, a, b, c, d = pcall(GetQuestLogRewardCurrencyInfo, i, qid)
            if ok then
                if type(a) == "table" then
                    addCurrency(out, a.currencyID or a.currencyId, a.totalRewardAmount or a.quantity, a.name)
                elseif type(a) == "string" then
                    addCurrency(out, d, c, a)
                else
                    addCurrency(out, a, c, nil)
                end
            end
        end
    end
    return out
end

local function addFaction(out, name, amount, factionId)
    amount = publicNumber(amount) or 0
    if amount <= 0 then return false end
    factionId = publicNumber(factionId)
    name = plain(name)
    if not name and factionId then name = factionName(factionId) end
    if not name then return false end
    for i = 1, #out do
        if out[i].name == name then
            if amount > out[i].amount then out[i].amount = amount end
            return true
        end
    end
    out[#out + 1] = { id = factionId or 0, name = name, amount = amount }
    return true
end

local function consumeFactionList(out, list)
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local row = list[i]
        if type(row) == "table" then
            addFaction(
                out,
                row.name or row.factionName,
                row.rewardAmount or row.amount or row.barValue,
                row.factionID or row.factionId
            )
        end
    end
end

local function readIndexedFactions(qid, out)
    if not GetQuestLogRewardFactionInfo then return end
    local n = 4
    if GetNumQuestLogRewardFactions then
        local okN, count = pcall(GetNumQuestLogRewardFactions, qid)
        local c = publicNumber(okN and count)
        if c and c > n then n = c end
    end
    if n > 8 then n = 8 end
    for i = 1, n do
        local ok, a, b, c = pcall(GetQuestLogRewardFactionInfo, i, qid)
        if not ok or a == nil or a == false then break end
        local before = #out
        if type(a) == "string" then
            addFaction(out, a, b, c)
        elseif type(a) == "number" and type(b) == "string" then
            addFaction(out, b, c, a)
        elseif type(a) == "table" then
            addFaction(out, a.name or a.factionName, a.rewardAmount or a.amount, a.factionID or a.factionId)
        else
            break
        end
        if #out == before and (a == nil or a == "") then break end
    end
end

local renownFactionIds

local function renownFactionIdList()
    if renownFactionIds then return renownFactionIds end
    renownFactionIds = {}
    local seenIds = {}
    local function add(id)
        id = publicNumber(id)
        if not id or id <= 0 or seenIds[id] then return end
        seenIds[id] = true
        renownFactionIds[#renownFactionIds + 1] = id
    end
    if C_MajorFactions and C_MajorFactions.GetMajorFactionIDs then
        local ok, ids = pcall(C_MajorFactions.GetMajorFactionIDs)
        if ok and type(ids) == "table" then
            for i = 1, #ids do add(ids[i]) end
        end
    end
    -- Zul'jarra's Forces is a renown track and is not always in the major-faction list.
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        local okN, n = pcall(C_Reputation.GetNumFactions)
        n = publicNumber(okN and n) or 0
        for i = 1, n do
            local ok, info = pcall(C_Reputation.GetFactionDataByIndex, i)
            if ok and type(info) == "table" then
                local renown = info.renownLevel
                local major = info.isMajorFaction
                local secret = issecretvalue and (issecretvalue(renown) or issecretvalue(major))
                if not secret and (renown ~= nil or major) then
                    add(info.factionID or info.factionId)
                end
            end
        end
    end
    return renownFactionIds
end

local function factionFromCurrency(currencyId)
    if not C_CurrencyInfo or not C_CurrencyInfo.GetFactionGrantedByCurrency then return nil end
    currencyId = publicNumber(currencyId)
    if not currencyId or currencyId <= 0 then return nil end
    local ok, factionId = pcall(C_CurrencyInfo.GetFactionGrantedByCurrency, currencyId)
    factionId = publicNumber(ok and factionId)
    if factionId and factionId > 0 then return factionId end
    return nil
end

local function taskQuestFaction(qid)
    if not C_TaskQuest or not C_TaskQuest.GetQuestInfoByQuestID then return nil end
    local ok, _, factionId = pcall(C_TaskQuest.GetQuestInfoByQuestID, qid)
    if not ok then return nil end
    factionId = publicNumber(factionId)
    if factionId and factionId > 0 then return factionId end
    return nil
end

local function favorAmount(qid)
    if not C_QuestInfoSystem or not C_QuestInfoSystem.GetQuestLogRewardFavor then return 0 end
    local ok, amount = pcall(C_QuestInfoSystem.GetQuestLogRewardFavor, qid)
    return publicNumber(ok and amount) or 0
end

-- Midnight renown is Favor, not a classic reputation line. The amount has no faction
-- on it, so the name comes from a currency that converts into that faction, then from
-- which major faction the quest awards, then from the world quest's own faction.
local function addRenown(qid, out, currencies)
    local named = false
    if type(currencies) == "table" then
        for i = 1, #currencies do
            local row = currencies[i]
            local factionId = factionFromCurrency(row.id)
            if factionId and addFaction(out, nil, row.amount, factionId) then
                named = true
            end
        end
    end
    local amount = favorAmount(qid)
    if amount <= 0 then return end
    if C_QuestLog and C_QuestLog.DoesQuestAwardReputationWithFaction then
        local ids = renownFactionIdList()
        for i = 1, #ids do
            local ok, awards = pcall(C_QuestLog.DoesQuestAwardReputationWithFaction, qid, ids[i])
            if ok and awards and not (issecretvalue and issecretvalue(awards)) then
                if addFaction(out, nil, amount, ids[i]) then named = true end
            end
        end
    end
    if not named then
        addFaction(out, nil, amount, taskQuestFaction(qid))
    end
end

-- Midnight world quests award 75 reputation to the faction that offers them.
-- That amount is not in the reward data, so it is used only when nothing else was found.
local MIDNIGHT_WQ_REP = 75

local function addMidnightFactionOwner(qid, out, expansion)
    if expansion ~= "midnight" or #out > 0 then return end
    addFaction(out, nil, MIDNIGHT_WQ_REP, taskQuestFaction(qid))
end

local function questFactions(qid, currencies, expansion)
    local out = {}
    if C_QuestLog and C_QuestLog.GetQuestLogMajorFactionReputationRewards then
        local ok, list = pcall(C_QuestLog.GetQuestLogMajorFactionReputationRewards, qid)
        if ok then consumeFactionList(out, list) end
    end
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardReputations then
        local ok, list = pcall(C_QuestInfoSystem.GetQuestRewardReputations, qid)
        if ok then consumeFactionList(out, list) end
    end
    if C_QuestLog and C_QuestLog.GetQuestRewardReputation then
        local ok, list = pcall(C_QuestLog.GetQuestRewardReputation, qid)
        if ok then consumeFactionList(out, list) end
    end
    readIndexedFactions(qid, out)
    addRenown(qid, out, currencies)
    addMidnightFactionOwner(qid, out, expansion)
    return out
end

local function questMoney(qid)
    if GetQuestLogRewardMoney then
        local ok, copper = pcall(GetQuestLogRewardMoney, qid)
        local n = publicNumber(ok and copper)
        if n and n > 0 then return n end
    end
    if C_QuestLog and C_QuestLog.GetQuestRewardMoney then
        local ok, copper = pcall(C_QuestLog.GetQuestRewardMoney, qid)
        local n = publicNumber(ok and copper)
        if n and n > 0 then return n end
    end
    return 0
end

local function questItems(qid)
    local out = {}
    local n = 0
    if GetNumQuestLogRewards then
        local ok, count = pcall(GetNumQuestLogRewards, qid)
        n = publicNumber(ok and count) or 0
    end
    if n <= 0 or not GetQuestLogRewardInfo then return out end
    for i = 1, n do
        local ok, a, b, c, d, e, itemID = pcall(GetQuestLogRewardInfo, i, qid)
        if ok then
            local id, name
            if type(a) == "table" then
                id = publicNumber(a.itemID or a.itemId)
                name = plain(a.itemName or a.name)
            else
                id = publicNumber(itemID)
                name = plain(a)
            end
            if id and id > 0 then
                out[#out + 1] = { id = id, name = name }
            end
        end
    end
    return out
end

local function itemDataReady(itemID)
    if C_Item and C_Item.IsItemDataCachedByID then
        local ok, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
        if ok then return cached and true or false end
    end
    if GetItemInfo then
        local ok, name = pcall(GetItemInfo, itemID)
        return ok and type(name) == "string" and name ~= ""
    end
    return true
end

local function requestItem(itemID)
    if itemWait[itemID] then return end
    itemWait[itemID] = true
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

local function tryPet(itemID)
    if not C_PetJournal or not C_PetJournal.GetPetInfoByItemID then return nil end
    local ok, speciesID = pcall(C_PetJournal.GetPetInfoByItemID, itemID)
    if not ok then return nil end
    speciesID = publicNumber(speciesID)
    if not speciesID or speciesID <= 0 then return nil end
    local missing = true
    if C_PetJournal.GetNumCollectedInfo then
        local okN, num = pcall(C_PetJournal.GetNumCollectedInfo, speciesID)
        if okN and issecretvalue and issecretvalue(num) then
            missing = false
        else
            local n = publicNumber(okN and num)
            if n and n > 0 then missing = false end
        end
    end
    return { missing = missing, kind = "pet", name = itemName(itemID) or "Pet" }
end

local function tryMount(itemID)
    if not C_MountJournal or not C_MountJournal.GetMountFromItem then return nil end
    local ok, mountID = pcall(C_MountJournal.GetMountFromItem, itemID)
    if not ok then return nil end
    mountID = publicNumber(mountID)
    if not mountID or mountID <= 0 then return nil end
    local missing = true
    local mountName
    if C_MountJournal.GetMountInfoByID then
        local okI, a, _, _, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountID)
        if okI then
            if type(a) == "table" then
                local owned = a.isCollected
                if issecretvalue and issecretvalue(owned) then
                    missing = false
                elseif owned then
                    missing = false
                end
                mountName = plain(a.name)
            else
                mountName = plain(a)
                if issecretvalue and issecretvalue(isCollected) then
                    missing = false
                elseif isCollected then
                    missing = false
                end
            end
        end
    end
    return { missing = missing, kind = "mount", name = mountName or itemName(itemID) or "Mount" }
end

local function tryToy(itemID)
    if not C_ToyBox or not C_ToyBox.GetToyInfo then return nil end
    local ok, toyItemID, toyName = pcall(C_ToyBox.GetToyInfo, itemID)
    if not ok or publicNumber(toyItemID) ~= itemID then return nil end
    local has = false
    if PlayerHasToy then
        local okH, owned = pcall(PlayerHasToy, itemID)
        if okH and issecretvalue and issecretvalue(owned) then
            has = true
        else
            has = okH and owned and true or false
        end
    end
    return { missing = not has, kind = "toy", name = plain(toyName) or itemName(itemID) or "Toy" }
end

local function tryAppearance(itemID)
    if not C_TransmogCollection or not C_TransmogCollection.GetItemInfo then return nil end
    local ok, _, sourceID = pcall(C_TransmogCollection.GetItemInfo, itemID)
    if not ok then return nil end
    sourceID = publicNumber(sourceID)
    if not sourceID or sourceID <= 0 then return nil end
    local has = false
    if C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
        local okH, owned = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
        if okH and issecretvalue and issecretvalue(owned) then
            has = true
        else
            has = okH and owned and true or false
        end
    end
    local can = true
    if C_TransmogCollection.PlayerCanCollectSource then
        local okC, allowed = pcall(C_TransmogCollection.PlayerCanCollectSource, sourceID)
        if okC and issecretvalue and issecretvalue(allowed) then
            can = false
        elseif okC then
            can = allowed and true or false
        end
    end
    if not can then return { missing = false } end
    return { missing = not has, kind = "appearance", name = itemName(itemID) or "Appearance" }
end

local function classifyItem(itemID)
    local cached = itemCache[itemID]
    if cached then return cached end
    local pet = tryPet(itemID)
    if pet then
        itemCache[itemID] = pet
        return pet
    end
    local mount = tryMount(itemID)
    if mount then
        itemCache[itemID] = mount
        return mount
    end
    local toy = tryToy(itemID)
    if toy then
        itemCache[itemID] = toy
        return toy
    end
    if not itemDataReady(itemID) then
        requestItem(itemID)
        return nil
    end
    local appearance = tryAppearance(itemID)
    if appearance then
        itemCache[itemID] = appearance
        return appearance
    end
    local none = { missing = false }
    itemCache[itemID] = none
    return none
end

local function classifyQuest(rec)
    rec.missing = {}
    rec.itemsPending = false
    if not filterOn("collectables") then
        return
    end
    local items = rec.items
    if type(items) ~= "table" then return end
    for i = 1, #items do
        local row = classifyItem(items[i].id)
        if row == nil then
            rec.itemsPending = true
        elseif row.missing and row.kind then
            rec.missing[#rec.missing + 1] = { kind = row.kind, name = row.name or items[i].name or "Item" }
        end
    end
end

local function classifyAll()
    if not filterOn("collectables") then return end
    for _, rec in pairs(cache) do
        if rec.rewardsReady then classifyQuest(rec) end
    end
end

local function readRewards(qid)
    local rec = cache[qid]
    if not rec then return end
    rec.gold = questMoney(qid)
    rec.currencies = questCurrencies(qid)
    rec.factions = questFactions(qid, rec.currencies, rec.expansion)
    rec.items = questItems(qid)
    rec.rewardsReady = true
    local title = questTitle(qid)
    if title then rec.title = title end
    retry[qid] = nil
    inflight[qid] = nil
    classifyQuest(rec)
end

local function preloadIdle()
    for _, t in pairs(inflight) do
        if t then return false end
    end
    return true
end

local function finishPass()
    phase = nil
    scanning = false
    passReady = true
    scheduleRescan()
    refreshList()
    if scanQueued then
        scanQueued = false
        if TaskTracker.RequestWorldQuestHuntScan then
            TaskTracker.RequestWorldQuestHuntScan(true)
        end
    end
end

local function notePoi(poi, mapID, fallback, expansion)
    local qid = poiQuestID(poi)
    if not qid or skip[qid] then return end
    if not isWorldQuest(qid) then return end
    if questDone(qid) then
        noteCharWorldQuestDone(qid)
        if not showCompletedQuests() then return end
    end
    local x, y
    local pinMap = mapID
    if type(poi) == "table" then
        x, y = pinXY(poi)
        pinMap = publicNumber(poi.mapID) or mapID
    end
    local prev = seen[qid]
    if not prev or (x and not prev.x) then
        seen[qid] = {
            mapID = pinMap,
            x = x,
            y = y,
            zoneFallback = fallback,
            expansion = expansion,
        }
    end
end

local function ingestMap(entry)
    local list = questsOnMap(entry.id)
    if type(list) ~= "table" then return end
    if #list > 0 then
        for i = 1, #list do
            notePoi(list[i], entry.id, entry.name, entry.expansion)
        end
        return
    end
    for _, poi in pairs(list) do
        notePoi(poi, entry.id, entry.name, entry.expansion)
    end
end

local function finishMaps()
    local nextActive = {}
    for qid, pin in pairs(seen) do
        nextActive[qid] = true
        local rec = cache[qid]
        if not rec then
            rec = { questID = qid }
            cache[qid] = rec
        end
        rec.mapID = pin.mapID
        rec.x = pin.x
        rec.y = pin.y
        rec.zoneFallback = pin.zoneFallback
        if pin.expansion then rec.expansion = pin.expansion end
        if not rec.title then rec.title = questTitle(qid) end
    end
    local drop = {}
    for qid in pairs(cache) do
        if not nextActive[qid] then
            -- Keep a quest this character just finished so the row can stay for alt tooltips.
            if showCompletedQuests() and questDone(qid) then
                noteCharWorldQuestDone(qid)
                nextActive[qid] = true
            else
                drop[#drop + 1] = qid
            end
        end
    end
    for i = 1, #drop do
        cache[drop[i]] = nil
        inflight[drop[i]] = nil
    end
    active = nextActive
    seen = {}
    preloadQueue = {}
    preloadHead = 1
    for qid, rec in pairs(cache) do
        if not rec.rewardsReady then
            preloadQueue[#preloadQueue + 1] = qid
        elseif filterOn("collectables") and rec.itemsPending then
            classifyQuest(rec)
        end
    end
end

local function sendPreloads()
    if not C_TaskQuest or not C_TaskQuest.RequestPreloadRewardData then
        for qid in pairs(cache) do
            if not cache[qid].rewardsReady then readRewards(qid) end
        end
        return 0
    end
    local sent = 0
    local now = GetTime and GetTime() or 0
    local timed = {}
    for qid, started in pairs(inflight) do
        if started and now - started >= REWARD_TIMEOUT then
            timed[#timed + 1] = qid
        end
    end
    for i = 1, #timed do
        local qid = timed[i]
        local n = (retry[qid] or 0) + 1
        retry[qid] = n
        inflight[qid] = nil
        if n <= RETRY_MAX then
            preloadQueue[#preloadQueue + 1] = qid
        else
            readRewards(qid)
        end
    end
    while sent < PRELOAD_PER_TICK and preloadHead <= #preloadQueue do
        local qid = preloadQueue[preloadHead]
        preloadHead = preloadHead + 1
        local rec = cache[qid]
        if rec and not rec.rewardsReady and not inflight[qid] and active[qid] then
            pcall(C_TaskQuest.RequestPreloadRewardData, qid)
            inflight[qid] = now
            sent = sent + 1
        end
    end
    return sent
end

local function step()
    if not scanning then return end
    if not huntEnabled() then
        scanning = false
        phase = nil
        return
    end
    if phase == "maps" then
        local budget = MAPS_PER_TICK
        while budget > 0 and mapIndex <= #mapList do
            ingestMap(mapList[mapIndex])
            mapIndex = mapIndex + 1
            budget = budget - 1
        end
        if mapIndex <= #mapList then
            C_Timer.After(0, step)
            return
        end
        finishMaps()
        phase = "preload"
    end
    if phase == "preload" then
        sendPreloads()
        local queued = preloadHead <= #preloadQueue
        if queued or not preloadIdle() then
            C_Timer.After(PRELOAD_GAP, step)
            return
        end
    end
    finishPass()
end

-- Currency and reputation are typed names, so those hunts search every expansion.
local function wideScan()
    return filterOn("currency") or filterOn("reputation")
end

local function buildMapList()
    local out = {}
    local maps = TaskTracker.WORLD_QUEST_MAPS
    if type(maps) ~= "table" then return out end
    local wide = wideScan()
    local rows = TaskTracker.WorldQuestHuntExpansionRows()
    for i = 1, #rows do
        local key = rows[i].key
        if wide or TaskTracker.IsWorldQuestHuntExpansionEnabled(key) then
            local zones = maps[key]
            if type(zones) == "table" then
                for j = 1, #zones do
                    local zone = zones[j]
                    if type(zone) == "table" and zone.id then
                        out[#out + 1] = {
                            id = zone.id,
                            name = zone.name,
                            expansion = key,
                        }
                    end
                end
            end
        end
    end
    return out
end

local function anyExpansion()
    local rows = TaskTracker.WorldQuestHuntExpansionRows()
    for i = 1, #rows do
        if TaskTracker.IsWorldQuestHuntExpansionEnabled(rows[i].key) then
            return true
        end
    end
    return false
end

local function startScanNow()
    if not huntEnabled() then
        scanning = false
        scanQueued = false
        phase = nil
        cancelRescan()
        return
    end
    if scanning then
        scanQueued = true
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        C_Timer.After(2, function()
            if TaskTracker.RequestWorldQuestHuntScan then
                TaskTracker.RequestWorldQuestHuntScan()
            end
        end)
        return
    end
    mapList = buildMapList()
    if #mapList == 0 then
        cache = {}
        active = {}
        scanning = false
        passReady = true
        cancelRescan()
        refreshList()
        return
    end
    mapIndex = 1
    seen = {}
    phase = "maps"
    scanning = true
    cancelRescan()
    C_Timer.After(0, step)
end

function TaskTracker.RequestWorldQuestHuntScan(immediate)
    if not huntEnabled() then
        if scanTimer then
            scanTimer:Cancel()
            scanTimer = nil
        end
        cancelRescan()
        return
    end
    if immediate then
        if scanTimer then
            scanTimer:Cancel()
            scanTimer = nil
        end
        startScanNow()
        return
    end
    if scanTimer then return end
    scanTimer = C_Timer.NewTimer(SCAN_DEBOUNCE, function()
        scanTimer = nil
        startScanNow()
    end)
end

function TaskTracker.SetWorldQuestHuntEnabled(on)
    local d = db()
    if not d then return end
    on = not not on
    if huntEnabled() == on then
        d.worldQuestHuntEnabled = on
        return
    end
    d.worldQuestHuntEnabled = on
    if not on then
        if scanTimer then
            scanTimer:Cancel()
            scanTimer = nil
        end
        cancelRescan()
        scanning = false
        scanQueued = false
        phase = nil
    end
    refreshList()
    if on then
        TaskTracker.RequestWorldQuestHuntScan(true)
    end
end

function TaskTracker.SetWorldQuestHuntMinGold(amount)
    local d = db()
    if not d then return end
    amount = tonumber(amount)
    if not amount or amount < 0 then amount = 0 end
    if amount > 9999999 then amount = 9999999 end
    amount = math.floor(amount)
    if d.worldQuestHuntMinGold == amount then return end
    d.worldQuestHuntMinGold = amount
    refreshList()
end

function TaskTracker.SetWorldQuestHuntFilter(key, on)
    local field = FILTER_FIELD[key]
    if not field then return end
    local d = db()
    if not d then return end
    on = not not on
    if filterOn(key) == on then
        d[field] = on
        return
    end
    d[field] = on
    if key == "collectables" and on then
        classifyAll()
    end
    if key == "currency" or key == "reputation" then
        TaskTracker.RequestWorldQuestHuntScan(true)
    end
    refreshList()
end

function TaskTracker.SetWorldQuestHuntHideEmpty(on)
    local d = db()
    if not d then return end
    d.worldQuestHuntHideEmpty = not not on
    refreshList()
end

function TaskTracker.SetWorldQuestHuntShowCompleted(on)
    local d = db()
    if not d then return end
    on = not not on
    if showCompletedQuests() == on then
        d.worldQuestHuntShowCompleted = on
        return
    end
    d.worldQuestHuntShowCompleted = on
    refreshList()
    if on then TaskTracker.RequestWorldQuestHuntScan(true) end
end

function TaskTracker.WorldQuestHuntShowsCompleted()
    return showCompletedQuests()
end

--- Finished world quests stay on the list when that option is on, even if Hide completed is on.
function TaskTracker.WorldQuestRowIgnoresHideCompleted(node)
    if not showCompletedQuests() then return false end
    if not node or type(node.id) ~= "string" then return false end
    return node.id:sub(1, 4) == "wqh:" or node.id:sub(1, 7) == "gen:wq"
end

function TaskTracker.WorldQuestCharStatus(charKey, node)
    if not node or type(node.id) ~= "string" then return nil end
    local qid = tonumber(node.id:match("^wqh:[^:]+:(%d+)$"))
    if not qid then return nil end
    local active = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if charKey == active then
        return questDone(qid) and "Done" or "Up"
    end
    local d = db()
    local snap = d and d.charWorldQuestDone and d.charWorldQuestDone[charKey]
    if snap and snap[qid] then return "Done" end
    return "—"
end

local function setQuery(field, text)
    local d = db()
    if not d then return end
    if type(text) ~= "string" then text = "" end
    if #text > 60 then text = text:sub(1, 60) end
    if d[field] == text then return end
    d[field] = text
    refreshList()
end

function TaskTracker.SetWorldQuestHuntCurrencyText(text)
    setQuery("worldQuestHuntCurrencyText", text)
end

function TaskTracker.SetWorldQuestHuntReputationText(text)
    setQuery("worldQuestHuntReputationText", text)
end

function TaskTracker.SetWorldQuestHuntExpansionEnabled(key, on)
    if not expansionKnown(key) then return end
    local d = db()
    if not d then return end
    if type(d.worldQuestHuntExpansions) ~= "table" then
        d.worldQuestHuntExpansions = { midnight = true }
    end
    on = not not on
    if (d.worldQuestHuntExpansions[key] and true or false) == on then return end
    d.worldQuestHuntExpansions[key] = on
    TaskTracker.RequestWorldQuestHuntScan(true)
    refreshList()
end

function TaskTracker.DismissWorldQuest(nodeID)
    local qid = tonumber(type(nodeID) == "string" and nodeID:match("^wqh:%a+:(%d+)$") or nil)
    if not qid then return true end
    skip[qid] = true
    refreshList()
    return true
end

local function onRewardData(qid, success)
    qid = tonumber(qid)
    if not qid or not cache[qid] then return end
    if success == false then
        local n = (retry[qid] or 0) + 1
        retry[qid] = n
        inflight[qid] = nil
        if n <= RETRY_MAX and scanning then
            preloadQueue[#preloadQueue + 1] = qid
            return
        end
    end
    readRewards(qid)
    refreshList()
end

local function questsUsingItem(itemID, fn)
    for _, rec in pairs(cache) do
        local items = rec.items
        if rec.rewardsReady and type(items) == "table" then
            for i = 1, #items do
                if items[i].id == itemID then
                    fn(rec)
                    break
                end
            end
        end
    end
end

local function onItemData(itemID, success)
    itemID = tonumber(itemID)
    if not itemID or not itemWait[itemID] then return end
    itemWait[itemID] = nil
    if success == false then
        itemCache[itemID] = { missing = false }
    else
        itemCache[itemID] = nil
    end
    if not filterOn("collectables") then return end
    questsUsingItem(itemID, classifyQuest)
    if itemWait[itemID] then
        itemWait[itemID] = nil
        itemCache[itemID] = { missing = false }
        questsUsingItem(itemID, classifyQuest)
    end
    refreshList()
end

local function dropQuest(qid)
    qid = tonumber(qid)
    if not qid or not cache[qid] then return end
    cache[qid] = nil
    active[qid] = nil
    inflight[qid] = nil
    refreshList()
end

local function scheduleRecheck()
    if not filterOn("collectables") then return end
    if recheckTimer then return end
    recheckTimer = C_Timer.NewTimer(RECHECK_DEBOUNCE, function()
        recheckTimer = nil
        for itemID, row in pairs(itemCache) do
            if row and row.missing then itemCache[itemID] = nil end
        end
        for _, rec in pairs(cache) do
            if rec.rewardsReady and type(rec.missing) == "table" and #rec.missing > 0 then
                classifyQuest(rec)
            end
        end
        refreshList()
    end)
end

local huntFrame = CreateFrame("Frame")
huntFrame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
huntFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
huntFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
huntFrame:RegisterEvent("QUEST_TURNED_IN")
huntFrame:RegisterEvent("QUEST_REMOVED")
huntFrame:RegisterEvent("NEW_PET_ADDED")
huntFrame:RegisterEvent("NEW_MOUNT_ADDED")
huntFrame:RegisterEvent("NEW_TOY_ADDED")
huntFrame:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
huntFrame:SetScript("OnEvent", function(_, event, a, b)
    if event == "QUEST_DATA_LOAD_RESULT" then
        onRewardData(a, b)
    elseif event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
        onItemData(a, b)
    elseif event == "QUEST_TURNED_IN" then
        noteCharWorldQuestDone(a)
        if not showCompletedQuests() then dropQuest(a) else refreshList() end
    elseif event == "QUEST_REMOVED" then
        if not (showCompletedQuests() and questDone(a)) then dropQuest(a) end
    else
        scheduleRecheck()
    end
end)

local function zoneName(rec)
    local mapID = rec and rec.mapID
    if mapID and C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and type(info) == "table" then
            local name = plain(info.name)
            if name then return name end
        end
    end
    return rec and rec.zoneFallback or ""
end

local function coinTexture(copper)
    -- One argument. A font height here comes back as the words "gold" and "silver".
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        local ok, s = pcall(C_CurrencyInfo.GetCoinTextureString, copper)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    if GetCoinTextureString then
        local ok, s = pcall(GetCoinTextureString, copper)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
end

local function goldText(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return nil end
    local icons = coinTexture(copper)
    if icons then return icons end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    if gold > 0 and silver > 0 then
        return commaAmt(gold) .. " gold " .. tostring(silver) .. " silver"
    end
    if gold > 0 then return commaAmt(gold) .. " gold" end
    return tostring(silver) .. " silver"
end

local function zoneLabel(rec)
    local name = zoneName(rec)
    if not name or name == "" then return "Unknown zone" end
    return name
end

local function zoneGroupKey(name)
    local s = name:lower():gsub("[^%w]+", "_")
    s = s:gsub("^_+", ""):gsub("_+$", "")
    if s == "" then return "unknown" end
    return s
end

local function matchedRows(list, query)
    if type(list) ~= "table" or not query then return nil end
    local best, parts = 0, {}
    for i = 1, #list do
        local row = list[i]
        if nameMatch(row.name, query) then
            parts[#parts + 1] = commaAmt(row.amount) .. " " .. row.name
            if row.amount > best then best = row.amount end
        end
    end
    if #parts == 0 then return nil end
    return best, table.concat(parts, ", ")
end

local function collectableText(rec)
    local list = rec.missing
    if type(list) ~= "table" or #list == 0 then return nil end
    table.sort(list, function(a, b)
        return (KIND_RANK[a.kind] or 9) < (KIND_RANK[b.kind] or 9)
    end)
    local first = list[1]
    local label = (KIND_LABEL[first.kind] or "Item") .. ": " .. (first.name or "Item")
    if #list > 1 then
        label = label .. " +" .. tostring(#list - 1)
    end
    return label
end

local function consider(rec)
    if not rec or not rec.rewardsReady or not active[rec.questID] then return false end
    if skip[rec.questID] then return false end
    if questDone(rec.questID) then
        noteCharWorldQuestDone(rec.questID)
        if not showCompletedQuests() then return false end
    end
    return true
end

local function itemsPending()
    if not filterOn("collectables") then return false end
    for _, rec in pairs(cache) do
        if rec.itemsPending then return true end
    end
    return false
end

local function viewGroup(key, name, children, extra)
    local expanded = true
    local d = db()
    if d and type(d.patchListViewExpanded) == "table" and d.patchListViewExpanded[key] ~= nil then
        expanded = d.patchListViewExpanded[key] and true or false
    end
    local node = {
        id = "view:" .. key,
        type = "group",
        name = name,
        expanded = expanded,
        children = children or {},
        viewGroupKey = key,
        isPatchListView = true,
        generatedSection = true,
    }
    if extra then
        for k, v in pairs(extra) do node[k] = v end
    end
    return node
end

local function summaryExtra(text)
    if type(text) ~= "string" or text == "" then return nil end
    return { readyToBuySummary = text }
end

local function statusNode(id, name)
    return {
        id = id,
        type = "task",
        name = name,
        done = false,
        reset = "none",
        taskMax = 1,
        taskCount = 0,
        note = "",
        commandButtons = {},
        accountWide = true,
        excludeFromRollup = true,
        generatedTask = true,
        generatedStatus = true,
        generatedHelp = name,
    }
end

local function taskNode(rec, bucket, subtitle)
    local buttons = {}
    local help = "Right-click to hide this world quest until you reload."
    local title = rec.title or "World Quest"
    if rec.mapID and rec.x and rec.y then
        local label = title:gsub("/", " ")
        if #label > 40 then label = label:sub(1, 40) end
        buttons[1] = {
            label = "Way",
            command = string.format("/way #%d %.2f %.2f %s", rec.mapID, rec.x, rec.y, label),
            icon = TaskTracker.WAY_COMMAND_ATLAS or "TaxiNode_Neutral",
            pinned = true,
        }
        help = help .. " The map pin sets a TomTom waypoint."
    end
    local listZone = nil
    if TaskTracker.ListZoneKeyForMapId then
        listZone = TaskTracker.ListZoneKeyForMapId(rec.mapID)
    end
    return {
        id = "wqh:" .. bucket .. ":" .. tostring(rec.questID),
        type = "task",
        name = title,
        done = false,
        reset = "none",
        taskMax = 1,
        taskCount = 0,
        note = "",
        commandButtons = buttons,
        accountWide = true,
        excludeFromRollup = true,
        generatedTask = true,
        done = questDone(rec.questID) and true or false,
        generatedSubtitle = subtitle,
        generatedHelp = help,
        listZone = listZone,
    }
end

local function byTitle(a, b)
    return (a.title or "") < (b.title or "")
end

local function inSelectedExpansion(rec)
    if not rec or not rec.expansion then return true end
    return TaskTracker.IsWorldQuestHuntExpansionEnabled(rec.expansion)
end

local function goldQuests()
    local rows = {}
    local minCopper = TaskTracker.GetWorldQuestHuntMinGold() * 10000
    if minCopper < 1 then minCopper = 1 end
    for _, rec in pairs(cache) do
        if consider(rec) and inSelectedExpansion(rec) and (rec.gold or 0) >= minCopper then
            rows[#rows + 1] = rec
        end
    end
    table.sort(rows, function(a, b)
        if a.gold ~= b.gold then return a.gold > b.gold end
        return byTitle(a, b)
    end)
    return rows
end

local function collectableQuests()
    local rows = {}
    for _, rec in pairs(cache) do
        if consider(rec) and inSelectedExpansion(rec) and type(rec.missing) == "table" and #rec.missing > 0 then
            rows[#rows + 1] = rec
        end
    end
    table.sort(rows, function(a, b)
        local za, zb = zoneName(a), zoneName(b)
        if za ~= zb then return za < zb end
        return byTitle(a, b)
    end)
    return rows
end

local function textQuests(field, listKey)
    local query = queryText(field)
    if not query then return nil end
    local rows = {}
    for _, rec in pairs(cache) do
        if consider(rec) then
            local amount, text = matchedRows(rec[listKey], query)
            if amount then
                rows[#rows + 1] = { rec = rec, amount = amount, text = text }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return byTitle(a.rec, b.rec)
    end)
    return rows
end

local function fillQuests(bucket, rows, subtitleFor, emptyText, stillLooking)
    if #rows == 0 then
        if not passReady or stillLooking then
            return { statusNode("wqh:status:" .. bucket, "Looking up world quests…") }
        end
        if hideEmptyGroups() then return nil end
        return { statusNode("wqh:status:" .. bucket, emptyText) }
    end
    local buckets, order = {}, {}
    for i = 1, #rows do
        local row = rows[i]
        local rec = row.rec or row
        local name = zoneLabel(rec)
        local slot = buckets[name]
        if not slot then
            slot = { name = name, rows = {} }
            buckets[name] = slot
            order[#order + 1] = slot
        end
        slot.rows[#slot.rows + 1] = row
    end
    table.sort(order, function(a, b) return a.name < b.name end)
    local groups = {}
    for i = 1, #order do
        local slot = order[i]
        local nodes = {}
        for j = 1, #slot.rows do
            local row = slot.rows[j]
            local rec = row.rec or row
            nodes[#nodes + 1] = taskNode(rec, bucket, subtitleFor(row))
        end
        groups[#groups + 1] = viewGroup(bucket .. ":z:" .. zoneGroupKey(slot.name), slot.name, nodes)
    end
    return groups
end

local function goldHeader(rows)
    local copper = 0
    for i = 1, #rows do
        copper = copper + (rows[i].gold or 0)
    end
    local gold = math.floor(copper / 10000)
    if gold > 0 then return commaAmt(gold) .. " gold" end
    return goldText(copper)
end

local function collectableHeader(rows)
    local n = 0
    for i = 1, #rows do
        local missing = rows[i].missing
        if type(missing) == "table" then n = n + #missing end
    end
    if n <= 0 then return nil end
    return tostring(n)
end

local function rewardHeader(rows, listKey, query)
    local totals, order = {}, {}
    for i = 1, #rows do
        local list = rows[i].rec and rows[i].rec[listKey]
        if type(list) == "table" and query then
            for j = 1, #list do
                local row = list[j]
                if nameMatch(row.name, query) then
                    local name = row.name
                    if not totals[name] then
                        totals[name] = 0
                        order[#order + 1] = name
                    end
                    totals[name] = totals[name] + (row.amount or 0)
                end
            end
        end
    end
    if #order == 0 then return nil end
    local parts = {}
    for i = 1, #order do
        parts[#parts + 1] = commaAmt(totals[order[i]]) .. " " .. order[i]
    end
    return table.concat(parts, " · ")
end

function TaskTracker.BuildWorldQuestHuntGroup()
    if not huntEnabled() then return nil end
    if TaskTracker.editMode then return nil end
    if not passReady and not scanning then
        TaskTracker.RequestWorldQuestHuntScan()
    end
    if not anyExpansion() and not wideScan() then
        return viewGroup("gen:wq", "World Quests", {
            statusNode("wqh:status:exp", "Turn on an expansion under World Quests."),
        })
    end
    local groups = {}
    local huntsOn = false
    local function addHunt(id, name, kids, extra)
        if not kids or #kids == 0 then return end
        groups[#groups + 1] = viewGroup(id, name, kids, extra)
    end
    if filterOn("gold") then
        huntsOn = true
        local rows = goldQuests()
        local minGold = TaskTracker.GetWorldQuestHuntMinGold and TaskTracker.GetWorldQuestHuntMinGold() or 0
        local emptyGold = "No gold world quests in your selected expansions."
        if minGold > 0 then
            emptyGold = "No gold world quests of " .. minGold .. " gold or more in your selected expansions."
        end
        addHunt("gen:wq:gold", "Gold", fillQuests("gold", rows, function(rec)
            return goldText(rec.gold) or "Gold"
        end, emptyGold), summaryExtra(#rows > 0 and goldHeader(rows) or nil))
    end
    if filterOn("collectables") then
        huntsOn = true
        local rows = collectableQuests()
        local looking = itemsPending() and #rows == 0
        addHunt("gen:wq:col", "Collectables", fillQuests("col", rows, function(rec)
            return collectableText(rec) or "Collectable"
        end, "No missing collectables on world quests right now.", looking), summaryExtra(collectableHeader(rows)))
    end
    if filterOn("currency") and queryText("worldQuestHuntCurrencyText") then
        huntsOn = true
        local rows = textQuests("worldQuestHuntCurrencyText", "currencies") or {}
        addHunt("gen:wq:cur", "Currency", fillQuests("cur", rows, function(row)
            return row.text
        end, "No world quests reward that currency."), summaryExtra(rewardHeader(rows, "currencies", queryText("worldQuestHuntCurrencyText"))))
    end
    if filterOn("reputation") and queryText("worldQuestHuntReputationText") then
        huntsOn = true
        local rows = textQuests("worldQuestHuntReputationText", "factions") or {}
        addHunt("gen:wq:rep", "Reputation", fillQuests("rep", rows, function(row)
            return row.text
        end, "No world quests reward that reputation."), summaryExtra(rewardHeader(rows, "factions", queryText("worldQuestHuntReputationText"))))
    end
    if #groups == 0 then
        if hideEmptyGroups() and passReady and huntsOn then return nil end
        return viewGroup("gen:wq", "World Quests", {
            statusNode("wqh:status:pick", "Turn on a hunt under World Quests."),
        })
    end
    return viewGroup("gen:wq", "World Quests", groups)
end

-- /tt wqrep [questID]
-- Prints the reward fields and tooltip lines for world quests on the current map.
-- One quest id prints just that quest. Rewards are requested first, then printed.
local DUMP_MAX = 8

local function dumpText(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    local kind = type(v)
    if kind == "string" then
        local s = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        s = s:gsub("|", "/")
        if s == "" then return "\"\"" end
        return s
    end
    if kind == "number" or kind == "boolean" then return tostring(v) end
    if kind == "table" then return "table" end
    return kind
end

local function dumpSay(text)
    print("|cff00ff00TaskTracker|r " .. text)
end

local function dumpPairs(prefix, value)
    if value == nil then
        dumpSay(prefix .. " nil")
        return
    end
    if issecretvalue and issecretvalue(value) then
        dumpSay(prefix .. " <secret>")
        return
    end
    if type(value) ~= "table" then
        dumpSay(prefix .. " " .. dumpText(value))
        return
    end
    if #value > 0 then
        dumpSay(prefix .. " count=" .. #value)
        local n = #value
        if n > 6 then n = 6 end
        for i = 1, n do
            dumpPairs(prefix .. "[" .. i .. "]", value[i])
        end
        return
    end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    if #keys == 0 then
        dumpSay(prefix .. " {}")
        return
    end
    local parts = {}
    for i = 1, #keys do
        local key = keys[i]
        parts[#parts + 1] = key .. "=" .. dumpText(value[key])
    end
    dumpSay(prefix .. " " .. table.concat(parts, " "))
end

local function dumpCall(label, fn, ...)
    if type(fn) ~= "function" then
        dumpSay(label .. " (missing)")
        return nil
    end
    local packed = { pcall(fn, ...) }
    if not packed[1] then
        dumpSay(label .. " error " .. dumpText(packed[2]))
        return nil
    end
    local last = 1
    for i = 2, 8 do
        if packed[i] ~= nil then last = i end
    end
    if last == 1 then
        dumpSay(label .. " nil")
        return nil
    end
    for i = 2, last do
        local tag = label
        if last > 2 then tag = label .. " ret" .. (i - 1) end
        dumpPairs(tag, packed[i])
    end
    return packed[2]
end

local function dumpTooltip(qid)
    local lines = {}
    local function addLine(text)
        text = dumpText(text)
        if text ~= "nil" and text ~= "\"\"" then
            lines[#lines + 1] = text
        end
    end
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, "quest:" .. qid)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for i = 1, #data.lines do
                local row = data.lines[i]
                if type(row) == "table" then addLine(row.leftText) end
            end
        end
    end
    if #lines == 0 then
        local tip = _G.TaskTrackerWQDumpTip
        if not tip then
            tip = CreateFrame("GameTooltip", "TaskTrackerWQDumpTip", nil, "GameTooltipTemplate")
        end
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:ClearLines()
        local ok = pcall(tip.SetHyperlink, tip, "quest:" .. qid)
        if ok and tip.NumLines then
            local n = tip:NumLines() or 0
            for i = 1, n do
                local left = _G["TaskTrackerWQDumpTipTextLeft" .. i]
                if left and left.GetText then addLine(left:GetText()) end
            end
        end
        tip:Hide()
    end
    if #lines == 0 then
        dumpSay("tooltip (empty)")
        return
    end
    local n = #lines
    if n > 16 then n = 16 end
    for i = 1, n do
        dumpSay("tip " .. lines[i])
    end
end

local function dumpOne(qid)
    qid = tonumber(qid)
    if not qid then return end
    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        pcall(C_TaskQuest.RequestPreloadRewardData, qid)
    end
    local title = questTitle(qid) or "?"
    dumpSay("--- " .. qid .. " " .. title)
    local rec = cache[qid]
    if rec then
        dumpSay("cached factions=" .. #(rec.factions or {}) .. " currencies=" .. #(rec.currencies or {}) .. " gold=" .. dumpText(rec.gold))
        if type(rec.factions) == "table" then
            for i = 1, #rec.factions do
                local row = rec.factions[i]
                dumpSay("cached rep " .. dumpText(row.name) .. " " .. dumpText(row.amount) .. " id=" .. dumpText(row.id))
            end
        end
    else
        dumpSay("cached (not in the hunt yet)")
    end
    dumpCall("taskInfo", C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID, qid)
    dumpCall("favor", C_QuestInfoSystem and C_QuestInfoSystem.GetQuestLogRewardFavor, qid, false)
    dumpCall("favorCap", C_QuestInfoSystem and C_QuestInfoSystem.GetQuestLogRewardFavor, qid, true)
    dumpCall("majorRep", C_QuestLog and C_QuestLog.GetQuestLogMajorFactionReputationRewards, qid)
    dumpCall("rewardRep", C_QuestLog and C_QuestLog.GetQuestRewardReputation, qid)
    dumpCall("infoRep", C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardReputations, qid)
    local currencies = dumpCall("currencies", C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardCurrencies, qid)
    if type(currencies) == "table" and C_CurrencyInfo and C_CurrencyInfo.GetFactionGrantedByCurrency then
        for i = 1, #currencies do
            local row = currencies[i]
            if type(row) == "table" then
                local id = row.currencyID or row.currencyId
                if id then
                    dumpCall("currencyFaction " .. dumpText(id), C_CurrencyInfo.GetFactionGrantedByCurrency, id)
                end
            end
        end
    end
    if GetNumQuestLogRewardFactions then
        dumpCall("numFactions", GetNumQuestLogRewardFactions, qid)
    end
    if GetQuestLogRewardFactionInfo then
        for i = 1, 4 do
            dumpCall("factionInfo " .. i, GetQuestLogRewardFactionInfo, i, qid)
        end
    end
    dumpTooltip(qid)
end

function TaskTracker.DumpWorldQuestRewards(questID)
    questID = tonumber(questID)
    local ids = {}
    if questID then
        ids[1] = questID
    else
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        mapID = tonumber(mapID)
        local mapName = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        mapName = type(mapName) == "table" and mapName.name or "?"
        dumpSay("World quest rep dump. Map " .. tostring(mapID) .. " " .. dumpText(mapName) .. ". Stand in the zone, or /tt wqrep questID.")
        local list = mapID and questsOnMap(mapID)
        if type(list) == "table" then
            if #list > 0 then
                for i = 1, #list do
                    local id = poiQuestID(list[i])
                    if id then ids[#ids + 1] = id end
                end
            else
                for _, poi in pairs(list) do
                    local id = poiQuestID(poi)
                    if id then ids[#ids + 1] = id end
                end
            end
        end
    end
    if #ids == 0 then
        dumpSay("No world quests on this map.")
        return
    end
    local n = #ids
    if n > DUMP_MAX then n = DUMP_MAX end
    for i = 1, n do
        if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
            pcall(C_TaskQuest.RequestPreloadRewardData, ids[i])
        end
    end
    C_Timer.After(1.2, function()
        dumpSay("Printing " .. n .. " of " .. #ids .. ".")
        for i = 1, n do
            dumpOne(ids[i])
        end
    end)
end
