-- Core/ReadyToBuy.lua
-- Generated list section. Ready to Buy groups Midnight vendor collectables by seller.
-- Each vendor row is what one spend can buy. The scan is time-sliced and is not part
-- of list layout.

TaskTracker = TaskTracker or {}

local SLOT_MIN, SLOT_MAX, SLOT_DEFAULT = 1, 20, 5
local GROUPS_PER_TICK = 40
local GROUPS_PER_CURRENCY = 400
local POOL_CAP = 300
local PARENT_WALK = 8
local SCAN_DEBOUNCE = 1.5

-- ATT expansionID. Midnight is 12. Older expansions stay off until turned on
-- in Options → Generative tasks → Expansions.
TaskTracker.READY_TO_BUY_EXPANSIONS = {
    { key = "midnight", label = "Midnight", attExpansionID = 12 },
    { key = "tww", label = "The War Within", attExpansionID = 11 },
    { key = "dragonflight", label = "Dragonflight", attExpansionID = 10 },
    { key = "shadowlands", label = "Shadowlands", attExpansionID = 9 },
    { key = "bfa", label = "Battle for Azeroth", attExpansionID = 8 },
    { key = "legion", label = "Legion", attExpansionID = 7 },
    { key = "draenor", label = "Warlords of Draenor", attExpansionID = 6 },
    { key = "pandaria", label = "Mists of Pandaria", attExpansionID = 5 },
    { key = "cataclysm", label = "Cataclysm", attExpansionID = 4 },
    { key = "wrath", label = "Wrath of the Lich King", attExpansionID = 3 },
    { key = "tbc", label = "The Burning Crusade", attExpansionID = 2 },
    { key = "classic", label = "Classic", attExpansionID = 1 },
}

local KIND_LABEL = {
    mount = "Mount",
    pet = "Pet",
    toy = "Toy",
    appearance = "Appearance",
    housing = "Housing",
    recipe = "Recipe",
    other = "Item",
}

local KIND_KEYS = { "mount", "pet", "toy", "appearance", "housing", "recipe", "other" }
local REP_REQ = { renown = true, friendship = true, journey = true }

local pool = {}
local poolReady = false
local scanning = false
local scanQueued = false
local scanTimer = nil
local sessionSkip = {}

local function db()
    return TaskTrackerDB
end

local function charKey()
    local k = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if type(k) ~= "string" or k == "" or k == "_pending" then return nil end
    return k
end

local function readyEnabled()
    local d = db()
    if not d or d.readyToBuyEnabled == nil then return true end
    return d.readyToBuyEnabled and true or false
end

function TaskTracker.IsReadyToBuyEnabled()
    return readyEnabled()
end

local function kindEnabled(kind)
    local d = db()
    local kinds = d and d.readyToBuyKinds
    if type(kinds) ~= "table" or kinds[kind] == nil then return true end
    return kinds[kind] and true or false
end

function TaskTracker.IsReadyToBuyKindEnabled(kind)
    return kindEnabled(kind)
end

local function slotCount()
    local d = db()
    local n = math.floor(tonumber(d and d.readyToBuyCount) or SLOT_DEFAULT)
    if n < SLOT_MIN then n = SLOT_MIN end
    if n > SLOT_MAX then n = SLOT_MAX end
    return n
end

local function ignoredList()
    local d = db()
    if not d then return {} end
    if type(d.readyToBuyIgnoredCurrencies) ~= "table" then
        d.readyToBuyIgnoredCurrencies = {}
    end
    return d.readyToBuyIgnoredCurrencies
end

local function currencyIgnored(currencyId)
    currencyId = tonumber(currencyId)
    if not currencyId then return false end
    local list = ignoredList()
    for i = 1, #list do
        if tonumber(list[i]) == currencyId then return true end
    end
    return false
end

local function reqUsesIgnoredCurrency(reqs)
    if type(reqs) ~= "table" then return false end
    for i = 1, #reqs do
        local r = reqs[i]
        if type(r) == "table" and tostring(r.type or "") == "currency" and currencyIgnored(r.currencyId) then
            return true
        end
    end
    return false
end

local function expansionByKey(key)
    local list = TaskTracker.READY_TO_BUY_EXPANSIONS
    for i = 1, #list do
        if list[i].key == key then return list[i] end
    end
    for i = 1, #list do
        if list[i].key == "midnight" then return list[i] end
    end
    return list[#list]
end

function TaskTracker.GetReadyToBuyExpansion()
    local d = db()
    local key = d and d.readyToBuyExpansion
    local exp = expansionByKey(key)
    return exp and exp.key or "midnight"
end

function TaskTracker.ReadyToBuyExpansionLabel(key)
    local exp = expansionByKey(key or TaskTracker.GetReadyToBuyExpansion())
    return (exp and exp.label) or "Midnight"
end

function TaskTracker.IsReadyToBuyExpansionEnabled(key)
    local exp = expansionByKey(key)
    if not exp or exp.key ~= key then return false end
    local d = db()
    local map = d and d.readyToBuyExpansions
    if type(map) ~= "table" then
        return key == ((d and d.readyToBuyExpansion) or "midnight")
    end
    return map[key] and true or false
end

function TaskTracker.ReadyToBuyEnabledExpansionSets()
    local ids, keys = {}, {}
    local list = TaskTracker.READY_TO_BUY_EXPANSIONS
    local any = false
    for i = 1, #list do
        local row = list[i]
        if TaskTracker.IsReadyToBuyExpansionEnabled(row.key) then
            ids[row.attExpansionID] = true
            keys[row.key] = true
            any = true
        end
    end
    return ids, keys, any
end

function TaskTracker.IsGeneratedTaskId(nodeID)
    if type(nodeID) ~= "string" then return false end
    local prefix = nodeID:sub(1, 4)
    return prefix == "rtb:" or prefix == "wqh:"
end

local function attOn()
    if TaskTracker.IsAttDataEnabled and not TaskTracker.IsAttDataEnabled() then return false end
    if TaskTracker.IsAllTheThingsLoaded and not TaskTracker.IsAllTheThingsLoaded() then return false end
    return TaskTracker.AttSearchField ~= nil
end

local function attField(group, key)
    if type(group) ~= "table" then return nil end
    local ok, v = pcall(function() return group[key] end)
    if ok then return v end
    return nil
end

local function attParent(group)
    local p = attField(group, "parent")
    if type(p) == "table" then return p end
    return nil
end

local function plain(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|", "")
    s = s:match("^%s*(.-)%s*$")
    if not s or s == "" then return nil end
    return s
end

local function slashSafe(s)
    s = plain(s) or "Here"
    s = s:gsub("[\r\n]", " ")
    if #s > 60 then s = s:sub(1, 60) end
    return s
end

local function numberListHas(list, id)
    if type(list) ~= "table" or not id then return false end
    for i = 1, #list do
        if tonumber(list[i]) == id then return true end
    end
    return false
end

local function walkLimited(group, depth)
    local steps = { group }
    local g = group
    local n = 0
    while n < depth do
        g = attParent(g)
        if not g then break end
        n = n + 1
        steps[#steps + 1] = g
    end
    return steps
end

-- AllTheThings patch tag. 120100 is Midnight (12); 10205 is patch 1.2.5 (Classic).
local function expansionFromAwp(group)
    local awp = tonumber(attField(group, "awp"))
    if not awp or awp <= 0 then return nil end
    local id = math.floor(awp / 10000)
    if id > 0 then return id end
end

-- expansionID or e wins when a parent has one. Zone maps often only have awp.
local function expansionIdOf(group)
    local steps = walkLimited(group, PARENT_WALK)
    for i = 1, #steps do
        local id = tonumber(attField(steps[i], "expansionID")) or tonumber(attField(steps[i], "e"))
        if id and id > 0 then return id end
    end
    for i = 1, #steps do
        local id = expansionFromAwp(steps[i])
        if id then return id end
    end
    return nil
end

-- 0 means "looked up, not an ensemble". A positive id is the transmog set.
local transmogSetByItem = {}

local function transmogSetId(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return nil end
    local cached = transmogSetByItem[itemId]
    if cached ~= nil then
        if cached > 0 then return cached end
        return nil
    end
    if TaskTracker.ItemRecordCached and not TaskTracker.ItemRecordCached(itemId) then
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
    transmogSetByItem[itemId] = setID
    if setID > 0 then return setID end
end

-- 0 = not a collectable. Filled once per item, during the scan, only when AllTheThings
-- did not already name a kind. Companion pets have no speciesID.
local clientKindByItem = {}

local function clientCollectableKind(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return nil end
    local cached = clientKindByItem[itemId]
    if cached ~= nil then
        if cached == 0 then return nil end
        return cached
    end
    local kind = 0
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local ok, mountId = pcall(C_MountJournal.GetMountFromItem, itemId)
        if ok and tonumber(mountId) and tonumber(mountId) > 0 then kind = "mount" end
    end
    if kind == 0 and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local ok, name = pcall(C_PetJournal.GetPetInfoByItemID, itemId)
        if ok and type(name) == "string" and name ~= "" then
            if not (issecretvalue and issecretvalue(name)) then kind = "pet" end
        end
    end
    if kind == 0 and C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem then
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemId, false)
        if ok and type(info) == "table" then
            local id = tonumber(info.entryID) or tonumber(info.recordID) or tonumber(info.decorID)
            if id and id > 0 then kind = "housing" end
        end
    end
    clientKindByItem[itemId] = kind
    return kind ~= 0 and kind or nil
end

local function kindOf(group)
    if tonumber(attField(group, "mountID")) then return "mount" end
    if tonumber(attField(group, "speciesID")) or tonumber(attField(group, "speciesId")) then return "pet" end
    if tonumber(attField(group, "toyID")) then return "toy" end
    if tonumber(attField(group, "decorID")) or tonumber(attField(group, "decorId")) then return "housing" end
    if attField(group, "type") == "decorID" then return "housing" end
    if tonumber(attField(group, "recipeID")) or tonumber(attField(group, "recipeId")) then return "recipe" end
    if tonumber(attField(group, "sourceID")) then return "appearance" end
    if tonumber(attField(group, "illusionID")) then return "appearance" end
    if attField(group, "type") == "ensembleID" or tonumber(attField(group, "tmogSetID")) then return "appearance" end
    if tonumber(attField(group, "titleID")) then return "other" end
    local itemId = tonumber(attField(group, "itemID")) or tonumber(attField(group, "itemId"))
    if itemId and transmogSetId(itemId) then return "appearance" end
    if itemId then return clientCollectableKind(itemId) end
    return nil
end

local function markedUnobtainable(group)
    local steps = walkLimited(group, 1)
    for i = 1, #steps do
        local u = attField(steps[i], "u")
        if u ~= nil and u ~= false and u ~= 0 then return true end
    end
    return false
end

local function classOk(group)
    local _, _, classID = UnitClass("player")
    classID = tonumber(classID)
    local steps = walkLimited(group, 1)
    for i = 1, #steps do
        local c = attField(steps[i], "c")
        if type(c) == "number" then
            if classID ~= c then return false end
        elseif type(c) == "table" and #c > 0 then
            if not numberListHas(c, classID) then return false end
        end
    end
    return true
end

local function raceOk(group)
    local _, _, raceID = UnitRace("player")
    raceID = tonumber(raceID)
    local steps = walkLimited(group, 1)
    for i = 1, #steps do
        local races = attField(steps[i], "races")
        if type(races) ~= "table" then
            local legacy = attField(steps[i], "r")
            if type(legacy) == "table" then races = legacy end
        end
        if type(races) == "table" and #races > 0 and not numberListHas(races, raceID) then
            return false
        end
    end
    return true
end

local function factionOk(group)
    local faction = UnitFactionGroup("player")
    local want = (faction == "Alliance" and 1) or (faction == "Horde" and 2) or nil
    local steps = walkLimited(group, 1)
    for i = 1, #steps do
        local r = tonumber(attField(steps[i], "r")) or tonumber(attField(steps[i], "factionID"))
        if r == 1 or r == 2 then
            if not want or r ~= want then return false end
        end
    end
    return true
end

local function levelOk(group)
    local lvl = UnitLevel("player") or 1
    local steps = walkLimited(group, 1)
    for i = 1, #steps do
        local need = tonumber(attField(steps[i], "lvl")) or tonumber(attField(steps[i], "minlvl"))
        if need and need > lvl then return false end
    end
    return true
end

local function questsOk(group)
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return true end
    local steps = walkLimited(group, 1)
    for s = 1, #steps do
        local sq = attField(steps[s], "sourceQuests")
        if type(sq) == "table" then
            for i = 1, #sq do
                local q = tonumber(sq[i])
                if q and q > 0 then
                    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, q)
                    if not ok or not done then return false end
                end
            end
        end
    end
    return true
end

local function accessOk(group)
    if markedUnobtainable(group) then return false end
    if not classOk(group) then return false end
    if not raceOk(group) then return false end
    if not factionOk(group) then return false end
    if not levelOk(group) then return false end
    if not questsOk(group) then return false end
    return true
end

local function costReqsFrom(group)
    local cost = attField(group, "cost")
    if type(cost) ~= "table" or not TaskTracker.AttCostTupleToReq then return nil end
    local reqs = {}
    for i = 1, #cost do
        local tuple = cost[i]
        if type(tuple) == "table" then
            local req = TaskTracker.AttCostTupleToReq(tuple)
            if req then
                reqs[#reqs + 1] = req
            elseif tuple[1] ~= nil then
                return nil
            end
        end
    end
    if #reqs == 0 then return nil end
    return reqs
end

local function appendRep(reqs, group)
    if not group or not TaskTracker.AttMinRepToReq then return end
    local req = TaskTracker.AttMinRepToReq(attField(group, "minReputation"))
    if req then reqs[#reqs + 1] = req end
end

local function hasRepReq(reqs)
    for i = 1, #reqs do
        if REP_REQ[tostring(reqs[i].type or ""):lower()] then return true end
    end
    return false
end

-- Local rank only when AllTheThings did not already record one.
local function appendLocalGate(reqs, itemId)
    if hasRepReq(reqs) then return end
    local gates = TaskTracker.READY_TO_BUY_GATES
    local gate = gates and gates[itemId]
    if type(gate) ~= "table" then return end
    local fid = tonumber(gate.factionId)
    local min = tonumber(gate.min)
    if not fid or fid <= 0 or not min or min <= 0 then return end
    local req = TaskTracker.AttMinRepToReq and TaskTracker.AttMinRepToReq({ fid, min })
    if req then
        if type(gate.label) == "string" and gate.label ~= "" then req.label = gate.label end
        reqs[#reqs + 1] = req
        return
    end
    reqs[#reqs + 1] = {
        type = "journey",
        factionId = fid,
        min = math.floor(min),
        label = gate.label,
    }
end

local function reqIsMet(req)
    local line = TaskTracker.DescribePurchaseReq and TaskTracker.DescribePurchaseReq(req)
    return line and line.met == true
end

-- Currency or gold must be the price. A collectable that costs only gold qualifies.
-- Item tokens on that same price must also be in hand. Reputation may be unmet.
local function priceKind(reqs)
    local hasCur, hasGold = false, false
    if type(reqs) ~= "table" then return false, false end
    for i = 1, #reqs do
        local t = tostring(reqs[i].type or ""):lower()
        if t == "currency" then hasCur = true
        elseif t == "gold" then hasGold = true
        end
    end
    return hasCur, hasGold
end

local function affordableReqs(reqs)
    local hasCur, hasGold = priceKind(reqs)
    if not hasCur and not hasGold then return nil end
    if reqUsesIgnoredCurrency(reqs) then return nil end
    local costOk, repOk = true, true
    for i = 1, #reqs do
        local met = reqIsMet(reqs[i])
        if REP_REQ[tostring(reqs[i].type or ""):lower()] then
            if not met then repOk = false end
        elseif not met then
            costOk = false
        end
    end
    if not costOk then return nil end
    return reqs, repOk
end

local function metCostReqs(group, itemId)
    local reqs = costReqsFrom(group)
    if not reqs then
        reqs = costReqsFrom(attParent(group))
    end
    if not reqs then return nil end
    appendRep(reqs, group)
    appendRep(reqs, attParent(group))
    appendLocalGate(reqs, itemId)
    return affordableReqs(reqs)
end

local function isGoldOnlyGroup(group)
    local reqs = costReqsFrom(group)
    if not reqs then return false end
    local hasCur, hasGold = priceKind(reqs)
    return hasGold and not hasCur
end

local nameWait = {}

local function usableItemName(name, itemId)
    if type(name) ~= "string" or name == "" then return nil end
    if issecretvalue and issecretvalue(name) then return nil end
    if itemId and name == ("Item " .. tostring(itemId)) then return nil end
    return name
end

local function clientItemName(itemId)
    if C_Item and C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, itemId)
        if ok then
            local n = usableItemName(name, itemId)
            if n then return n end
        end
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, name = pcall(C_Item.GetItemInfo, itemId)
        if ok then
            local n = usableItemName(name, itemId)
            if n then return n end
        end
    elseif GetItemInfo then
        local ok, name = pcall(GetItemInfo, itemId)
        if ok then
            local n = usableItemName(name, itemId)
            if n then return n end
        end
    end
end

local function catalogDecorName(itemId, decorId)
    if not C_HousingCatalog then return nil end
    if itemId and C_HousingCatalog.GetCatalogEntryInfoByItem then
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemId, false)
        if ok and type(info) == "table" then
            local n = usableItemName(info.name, itemId)
            if n then return n end
        end
    end
    decorId = tonumber(decorId)
    if decorId and decorId > 0 and C_HousingCatalog.GetCatalogEntryInfoByRecordID then
        local decorType = (Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor) or 1
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByRecordID, decorType, decorId, false)
        if ok and type(info) == "table" then
            local n = usableItemName(info.name, itemId)
            if n then return n end
        end
    end
end

local function itemDisplayName(itemId, group, decorId)
    local name = clientItemName(itemId)
    if name then return name end
    if not decorId and group then
        decorId = tonumber(attField(group, "decorID")) or tonumber(attField(group, "decorId"))
    end
    name = catalogDecorName(itemId, decorId)
    if name then return name end
    if group then
        name = usableItemName(plain(attField(group, "name")) or plain(attField(group, "text")), itemId)
        if name then
            if TaskTracker.ItemRecordCached and not TaskTracker.ItemRecordCached(itemId) then
                if C_Item and C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, itemId)
                end
                nameWait[itemId] = true
            end
            return name
        end
    end
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemId)
    end
    nameWait[itemId] = true
    return "Item " .. tostring(itemId)
end

local function ensureItemName(rec)
    if type(rec) ~= "table" then return nil end
    local itemId = rec.itemId
    local kept = usableItemName(rec.name, itemId)
    if kept then return kept end
    local name = clientItemName(itemId) or catalogDecorName(itemId, rec.decorId)
    if name then
        rec.name = name
        nameWait[itemId] = nil
        return name
    end
    if not nameWait[itemId] and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemId)
    end
    nameWait[itemId] = true
    return rec.name
end

local function groupMapID(group)
    local id = tonumber(attField(group, "mapID") or attField(group, "uiMapID"))
    if id and id > 0 then return id end
    local maps = attField(group, "maps")
    if type(maps) == "table" then
        local m = tonumber(maps[1])
        if m and m > 0 then return m end
    end
end

local function coordTriple(coord, fallbackMap)
    if type(coord) ~= "table" then return nil end
    local x = tonumber(coord[1])
    if x == nil then x = tonumber(coord.x) end
    local y = tonumber(coord[2])
    if y == nil then y = tonumber(coord.y) end
    local mapID = tonumber(coord[3] or coord.mapID or coord.uiMapID) or tonumber(fallbackMap)
    if not x or not y or not mapID or mapID <= 0 then return nil end
    return x, y, mapID
end

-- ATT uses {x,y,map}, {x,y} plus a parent map, or coords keyed by map id.
local function readPoint(group, fallbackMap)
    local mapHere = groupMapID(group) or fallbackMap
    local hitX, hitY, hitMap = coordTriple(attField(group, "coord"), mapHere)
    if hitX then return hitX, hitY, hitMap end
    local coords = attField(group, "coords")
    if type(coords) ~= "table" then return nil end
    if type(coords[1]) == "table" then
        return coordTriple(coords[1], mapHere)
    end
    if tonumber(coords[1]) ~= nil and tonumber(coords[2]) ~= nil then
        return coordTriple(coords, mapHere)
    end
    local ok, x, y, mapID = pcall(function()
        for mapKey, points in pairs(coords) do
            if type(points) == "table" then
                local keyMap = tonumber(mapKey) or mapHere
                local px, py, pm
                if type(points[1]) == "table" then
                    px, py, pm = coordTriple(points[1], keyMap)
                else
                    px, py, pm = coordTriple(points, keyMap)
                end
                if px then return px, py, pm end
            end
        end
    end)
    if ok then return x, y, mapID end
end

local function waypointFor(group, fallbackName)
    local steps = walkLimited(group, PARENT_WALK)
    local chainMap
    for i = 1, #steps do
        chainMap = chainMap or groupMapID(steps[i])
    end
    local x, y, mapID, name
    for i = 1, #steps do
        if not x then
            x, y, mapID = readPoint(steps[i], chainMap)
        end
        if not mapID then
            mapID = groupMapID(steps[i])
        end
        if not name then
            local n = plain(attField(steps[i], "name")) or plain(attField(steps[i], "text"))
            if n and n ~= fallbackName then name = n end
        end
    end
    if not x or not y or not mapID then return nil, name end
    if math.abs(x) <= 1 and math.abs(y) <= 1 then
        x, y = x * 100, y * 100
    end
    local label = slashSafe(name or fallbackName)
    local cmd = string.format("/way #%d %.2f %.2f %s", mapID, x, y, label)
    return cmd, name
end

local function nearestNpc(group)
    local steps = walkLimited(group, PARENT_WALK)
    for i = 1, #steps do
        local id = tonumber(attField(steps[i], "npcID")) or tonumber(attField(steps[i], "creatureID"))
        if id and id > 0 then
            local name = plain(attField(steps[i], "name")) or plain(attField(steps[i], "text"))
            return id, name
        end
    end
end

local mountJournalPrimed = false

local function flagIsTrue(v)
    if v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return v == true
end

-- GetMountInfoByID reports every mount uncollected until this has run once.
local function primeMountJournal()
    if mountJournalPrimed then return end
    mountJournalPrimed = true
    if C_MountJournal and C_MountJournal.GetMountIDs then
        pcall(C_MountJournal.GetMountIDs)
    end
end

local function mountCollected(mountId)
    mountId = tonumber(mountId)
    if not mountId or mountId <= 0 then return false end
    if not (C_MountJournal and C_MountJournal.GetMountInfoByID) then return false end
    primeMountJournal()
    local ok, collected = pcall(function()
        return select(11, C_MountJournal.GetMountInfoByID(mountId))
    end)
    return ok and flagIsTrue(collected)
end

-- Ensembles the tooltip marks "Already known". IsSetCollected is not the client call
-- that flag uses. One answer per set id, cleared at the start of each scan.
local setOwnedCache = {}

local function transmogSetOwned(setID)
    setID = tonumber(setID)
    if not setID or setID <= 0 or not C_TransmogSets then return false end
    local cached = setOwnedCache[setID]
    if cached ~= nil then return cached end
    local owned = false
    if C_TransmogSets.GetSetInfo then
        local ok, info = pcall(C_TransmogSets.GetSetInfo, setID)
        if ok and type(info) == "table" and flagIsTrue(info.collected) then
            owned = true
        end
    end
    if not owned and C_TransmogSets.GetSetPrimaryAppearances then
        local ok, apps = pcall(C_TransmogSets.GetSetPrimaryAppearances, setID)
        if ok and type(apps) == "table" and #apps > 0 then
            local all = true
            for i = 1, #apps do
                local row = apps[i]
                if type(row) ~= "table" or not flagIsTrue(row.collected) then
                    all = false
                    break
                end
            end
            if all then owned = true end
        end
    end
    if not owned and C_TransmogSets.IsSetCollected then
        local ok, known = pcall(C_TransmogSets.IsSetCollected, setID)
        if ok and flagIsTrue(known) then owned = true end
    end
    if not owned and C_TransmogSets.GetSetSourceCounts then
        local ok, got, total = pcall(C_TransmogSets.GetSetSourceCounts, setID)
        if ok and not (issecretvalue and (issecretvalue(got) or issecretvalue(total))) then
            got, total = tonumber(got), tonumber(total)
            if got and total and total > 0 and got >= total then owned = true end
        end
    end
    if not owned and C_Transmog and C_Transmog.GetAllSetAppearancesByID
        and C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
        local ok, rows = pcall(C_Transmog.GetAllSetAppearancesByID, setID)
        if ok and type(rows) == "table" and #rows > 0 then
            local all = true
            for i = 1, #rows do
                local sourceID = type(rows[i]) == "table" and tonumber(rows[i].itemModifiedAppearanceID) or nil
                local has = false
                if sourceID and sourceID > 0 then
                    local okHas, known = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
                    has = okHas and known == true
                end
                if not has then
                    all = false
                    break
                end
            end
            if all then owned = true end
        end
    end
    setOwnedCache[setID] = owned
    return owned
end

local function clearTransmogSetOwnedCache()
    for k in pairs(setOwnedCache) do
        setOwnedCache[k] = nil
    end
end

local function spellIdKnown(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return false end
    if IsPlayerSpell then
        local okSpell, known = pcall(IsPlayerSpell, spellID)
        if okSpell and flagIsTrue(known) then return true end
    end
    if IsSpellKnown then
        local okSpell, known = pcall(IsSpellKnown, spellID)
        if okSpell and flagIsTrue(known) then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        local okSpell, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellID, bank, true)
        if okSpell and flagIsTrue(known) then return true end
    end
    return false
end

-- Same signal as the item tooltip line "Already known".
local function itemSpellKnown(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 or not (C_Item and C_Item.GetItemSpell) then return false end
    local ok, spellName, spellID = pcall(C_Item.GetItemSpell, itemId)
    if not ok then return false end
    spellID = tonumber(spellID)
    if (not spellID or spellID <= 0) and type(spellName) == "number" then
        spellID = spellName
    end
    return spellIdKnown(spellID)
end

local function firstDecorCount(a, b)
    local v = a
    if v == nil then v = b end
    if v == nil then return 0 end
    if issecretvalue and issecretvalue(v) then return nil end
    return tonumber(v) or 0
end

-- One copy in storage, placed in a house, or waiting to be redeemed counts as owned.
local function decorInfoOwned(info)
    if type(info) ~= "table" then return false end
    local stored = firstDecorCount(info.totalNumStored, info.numStored)
    local placed = firstDecorCount(info.totalNumPlaced, info.numPlaced)
    local redeem = firstDecorCount(info.remainingRedeemable, nil)
    if stored == nil or placed == nil or redeem == nil then return false end
    return (stored + placed + redeem) >= 1
end

local function housingOwned(itemId, decorId)
    if not C_HousingCatalog then return false end
    local decorType = 1
    if Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor then
        decorType = Enum.HousingCatalogEntryType.Decor
    end
    if itemId and C_HousingCatalog.GetCatalogEntryInfoByItem then
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemId, true)
        if ok and decorInfoOwned(info) then return true end
    end
    decorId = tonumber(decorId)
    if decorId and decorId > 0 and C_HousingCatalog.GetCatalogEntryInfoByRecordID then
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByRecordID, decorType, decorId, true)
        if ok and decorInfoOwned(info) then return true end
    end
    return false
end

local speciesByItem = {}

local function petSpeciesFromItem(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return nil end
    local cached = speciesByItem[itemId]
    if cached ~= nil then
        if cached > 0 then return cached end
        return nil
    end
    local species = 0
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local packed = { pcall(C_PetJournal.GetPetInfoByItemID, itemId) }
        if packed[1] == true then
            -- Current client: name, then 12 fields, speciesID last (packed[14] after pcall ok).
            species = tonumber(packed[14]) or 0
            if species <= 0 then
                local older = tonumber(packed[2])
                if older and older > 0 then species = older end
            end
        end
    end
    speciesByItem[itemId] = species
    return species > 0 and species or nil
end

local function petCollected(speciesId)
    speciesId = tonumber(speciesId)
    if not speciesId or speciesId <= 0 or not (C_PetJournal and C_PetJournal.GetNumCollectedInfo) then
        return false
    end
    local ok, num = pcall(C_PetJournal.GetNumCollectedInfo, speciesId)
    if not ok or (issecretvalue and issecretvalue(num)) then return false end
    return type(num) == "number" and num > 0
end

-- FindPetIDByName returns a species even when you do not own it. A pet GUID means collected.
local function petOwnedByName(name)
    if type(name) ~= "string" then return false end
    name = name:match("^%s*(.-)%s*$") or ""
    name = name:gsub("^Pet:%s*", "")
    if name == "" or not (C_PetJournal and C_PetJournal.FindPetIDByName) then return false end
    local ok, _, petGUID = pcall(C_PetJournal.FindPetIDByName, name)
    if not ok or type(petGUID) ~= "string" or petGUID == "" then return false end
    if issecretvalue and issecretvalue(petGUID) then return false end
    return true
end

local function isOwned(rec)
    if type(rec) ~= "table" then return false end
    if rec.kind == "toy" then
        if not PlayerHasToy then return false end
        local ok, has = pcall(PlayerHasToy, rec.itemId)
        return ok and flagIsTrue(has)
    end
    if rec.kind == "mount" then
        if mountCollected(rec.mountId) then return true end
        if C_MountJournal and C_MountJournal.GetMountFromItem then
            local ok, fromItem = pcall(C_MountJournal.GetMountFromItem, rec.itemId)
            if ok and mountCollected(fromItem) then return true end
        end
        local spellId = tonumber(rec.spellId)
        if spellId and C_MountJournal and C_MountJournal.GetMountFromSpell then
            local ok, fromSpell = pcall(C_MountJournal.GetMountFromSpell, spellId)
            if ok and mountCollected(fromSpell) then return true end
        end
        if itemSpellKnown(rec.itemId) then return true end
        return false
    end
    if rec.kind == "pet" then
        local species = tonumber(rec.speciesId) or petSpeciesFromItem(rec.itemId)
        if petCollected(species) then return true end
        if petOwnedByName(rec.name) then return true end
        if itemSpellKnown(rec.itemId) then return true end
        return false
    end
    if rec.kind == "appearance" then
        local setID = tonumber(rec.tmogSetId) or transmogSetId(rec.itemId)
        if transmogSetOwned(setID) then return true end
        local illusionId = tonumber(rec.illusionId)
        if illusionId and illusionId > 0 and C_TransmogCollection and C_TransmogCollection.GetIllusionInfo then
            local ok, info = pcall(C_TransmogCollection.GetIllusionInfo, illusionId)
            if ok and type(info) == "table" and flagIsTrue(info.isCollected) then return true end
        end
        if itemSpellKnown(rec.itemId) then return true end
        local sid = tonumber(rec.sourceId)
        if sid and sid > 0 and C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
            local ok, has = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sid)
            if ok and has == true then return true end
        end
        if C_TransmogCollection and C_TransmogCollection.PlayerHasTransmog then
            local ok, has = pcall(C_TransmogCollection.PlayerHasTransmog, rec.itemId)
            if ok and has == true then return true end
        end
        if spellIdKnown(rec.spellId) then return true end
        if TaskTracker.ItemTooltipSaysAlreadyKnown and TaskTracker.ItemTooltipSaysAlreadyKnown(rec.itemId) then
            return true
        end
        return false
    end
    if rec.kind == "housing" then
        return housingOwned(rec.itemId, rec.decorId)
    end
    if rec.kind == "recipe" then
        local sid = tonumber(rec.recipeId) or tonumber(rec.spellId)
        if sid and sid > 0 and IsPlayerSpell then
            local ok, known = pcall(IsPlayerSpell, sid)
            if ok and flagIsTrue(known) then return true end
        end
        if itemSpellKnown(rec.itemId) then return true end
        return false
    end
    if rec.kind == "other" then
        local titleId = tonumber(rec.titleId)
        if titleId and titleId > 0 and IsTitleKnown then
            local ok, known = pcall(IsTitleKnown, titleId)
            if ok and flagIsTrue(known) then return true end
        end
        if itemSpellKnown(rec.itemId) then return true end
    end
    return false
end

local function shortReqText(req)
    local line = TaskTracker.DescribePurchaseReq and TaskTracker.DescribePurchaseReq(req)
    if not line or type(line.text) ~= "string" then return nil, false end
    local cut = line.text:match("^(.-)%s%s+%(")
    local text = (cut and cut ~= "") and cut or line.text
    return text, line.met == true
end

local function subtitleFor(rec, mode)
    local parts = {}
    local reqs = rec.reqs
    if type(reqs) == "table" then
        for i = 1, #reqs do
            local req = reqs[i]
            local text, met = shortReqText(req)
            if text and text ~= "" then
                local kind = tostring(req and req.type or ""):lower()
                if mode == "short" and not REP_REQ[kind] then
                    met = false
                end
                if TaskTracker.WrapColor then
                    text = TaskTracker.WrapColor(text, met and "complete" or "danger")
                end
                parts[#parts + 1] = text
            end
        end
    end
    local line = table.concat(parts, " · ")
    line = tostring(line or ""):gsub("[\r\n]+", " "):gsub("%s+", " ")
    line = line:match("^%s*(.-)%s*$") or ""
    return line
end

local function poolSize(src)
    local n = 0
    for _ in pairs(src) do n = n + 1 end
    return n
end

local function considerGroup(group, enabledIds, into)
    if type(group) ~= "table" then return end
    local itemId = tonumber(attField(group, "itemID")) or tonumber(attField(group, "itemId"))
    if not itemId or itemId <= 0 then return end
    local existing = into[itemId]
    if existing and not existing.registrySeed then return end
    local kind = kindOf(group)
    if not kind or not kindEnabled(kind) then return end
    if not existing and poolSize(into) >= POOL_CAP then return end
    -- Only expansions turned on in Options. A row with neither expansionID nor awp is not included.
    local foundExp = expansionIdOf(group)
    if not foundExp or not enabledIds[foundExp] then return end
    if not accessOk(group) then return end
    local reqs, repOk = metCostReqs(group, itemId)
    if not reqs then return end
    local name = itemDisplayName(itemId, group)
    local npcId, npcName = nearestNpc(group)
    local way, wayName = waypointFor(group, name)
    local vendorName = npcName or wayName or "Vendor"
    local vendorKey = npcId and ("npc:" .. tostring(npcId)) or ("name:" .. vendorName:lower())
    local skip = sessionSkip[charKey() or ""]
    if skip and skip[vendorKey] then return end
    local rec = {
        itemId = itemId,
        name = name,
        kind = kind,
        reqs = reqs,
        repLocked = not repOk,
        way = way,
        vendor = vendorName,
        vendorKey = vendorKey,
        mountId = tonumber(attField(group, "mountID")),
        spellId = tonumber(attField(group, "spellID")) or tonumber(attField(group, "spellId")),
        speciesId = tonumber(attField(group, "speciesID")) or tonumber(attField(group, "speciesId")),
        sourceId = tonumber(attField(group, "sourceID")),
        decorId = tonumber(attField(group, "decorID")) or tonumber(attField(group, "decorId")),
        recipeId = tonumber(attField(group, "recipeID")) or tonumber(attField(group, "recipeId")),
        tmogSetId = tonumber(attField(group, "tmogSetID"))
            or (attField(group, "type") == "ensembleID" and transmogSetId(itemId))
            or (transmogSetByItem[itemId] and transmogSetByItem[itemId] > 0 and transmogSetByItem[itemId])
            or nil,
        illusionId = tonumber(attField(group, "illusionID")),
        titleId = tonumber(attField(group, "titleID")),
    }
    if isOwned(rec) then return end
    into[itemId] = rec
end

-- Registry rows we already priced (currency or gold). Fills vendors AllTheThings
-- did not return. An AllTheThings group for the same item replaces this later.
local registryBuyRows

local function wayFromRegistry(re)
    local buttons = re.defaultCommandButtons
    if type(buttons) ~= "table" then return nil end
    for i = 1, #buttons do
        local cmd = buttons[i] and buttons[i].command
        if type(cmd) == "string" and cmd:find("/way", 1, true) == 1 then
            return cmd
        end
    end
end

local function vendorFromWay(cmd)
    if type(cmd) ~= "string" then return nil end
    local name = cmd:match("^/way%s+#%d+%s+[%d%.]+%s+[%d%.]+%s+(.+)$")
    if not name then return nil end
    name = name:match("^%s*(.-)%s*$")
    if not name or name == "" then return nil end
    return name
end

local function registryBuyList()
    if registryBuyRows then return registryBuyRows end
    registryBuyRows = {}
    local list = TaskTracker.Registry
    if type(list) ~= "table" then return registryBuyRows end
    for i = 1, #list do
        local re = list[i]
        local itemId = type(re) == "table" and tonumber(re.itemId) or nil
        local kind = type(re) == "table" and re.collectableKind or nil
        local reqs = type(re) == "table" and re.purchaseReqs or nil
        if itemId and itemId > 0 and KIND_LABEL[kind] and type(reqs) == "table" then
            local hasCur, hasGold = priceKind(reqs)
            if hasCur or hasGold then
                local way = wayFromRegistry(re)
                registryBuyRows[#registryBuyRows + 1] = {
                    itemId = itemId,
                    kind = kind,
                    label = re.label,
                    expansion = re.expansion,
                    reqs = reqs,
                    way = way,
                    vendor = vendorFromWay(way),
                    mountId = tonumber(re.mountId),
                    speciesId = tonumber(re.petSpeciesId),
                }
            end
        end
    end
    return registryBuyRows
end

local function copyReqList(src)
    local out = {}
    for i = 1, #src do
        local req = src[i]
        if type(req) == "table" then
            local copy = {}
            for k, v in pairs(req) do
                copy[k] = v
            end
            out[#out + 1] = copy
        end
    end
    return out
end

local function seedRegistryBuys(enabledKeys, currencyIds, into)
    local want = {}
    for i = 1, #currencyIds do
        want[currencyIds[i]] = true
    end
    local rows = registryBuyList()
    for i = 1, #rows do
        if poolSize(into) >= POOL_CAP then return end
        local reg = rows[i]
        if not into[reg.itemId]
            and enabledKeys[reg.expansion]
            and kindEnabled(reg.kind)
        then
            local hasCur, hasGold = priceKind(reg.reqs)
            local held = hasGold and not hasCur
            if not held and hasCur then
                for j = 1, #reg.reqs do
                    local req = reg.reqs[j]
                    if type(req) == "table"
                        and tostring(req.type or ""):lower() == "currency"
                        and want[tonumber(req.currencyId)]
                    then
                        held = true
                        break
                    end
                end
            end
            if held then
                local reqs = copyReqList(reg.reqs)
                appendLocalGate(reqs, reg.itemId)
                local affordable, repOk = affordableReqs(reqs)
                if affordable then
                    local vendorName = reg.vendor or "Vendor"
                    local vendorKey = "name:" .. vendorName:lower()
                    local skip = sessionSkip[charKey() or ""]
                    if not (skip and skip[vendorKey]) then
                        local rec = {
                            itemId = reg.itemId,
                            name = itemDisplayName(reg.itemId) or reg.label,
                            kind = reg.kind,
                            reqs = affordable,
                            repLocked = not repOk,
                            way = reg.way,
                            vendor = vendorName,
                            vendorKey = vendorKey,
                            mountId = reg.mountId,
                            speciesId = reg.speciesId,
                            registrySeed = true,
                        }
                        if not isOwned(rec) then
                            into[reg.itemId] = rec
                        end
                    end
                end
            end
        end
    end
end

local function enqueueGoldSiblings(group, list, seenParents)
    local parent = attParent(group)
    if not parent or seenParents[parent] then return end
    seenParents[parent] = true
    local kids = attField(parent, "g")
    if type(kids) ~= "table" then return end
    local n = 0
    local function add(child)
        n = n + 1
        if n > 80 then return true end
        if type(child) == "table" and isGoldOnlyGroup(child) then
            list[#list + 1] = child
        end
    end
    if #kids > 0 then
        for i = 1, #kids do
            if add(kids[i]) then return end
        end
        return
    end
    for _, child in pairs(kids) do
        if add(child) then return end
    end
end

local function collectCurrencyGroups(currencyId)
    local out, seen = {}, {}
    local function addResults(results)
        if type(results) ~= "table" then return end
        local n = 0
        for _, group in pairs(results) do
            n = n + 1
            if n > GROUPS_PER_CURRENCY then break end
            if type(group) == "table" then
                local selfCid = tonumber(attField(group, "currencyID")) or tonumber(attField(group, "currencyId"))
                local itemId = tonumber(attField(group, "itemID")) or tonumber(attField(group, "itemId"))
                if itemId and itemId > 0 and not seen[itemId] and selfCid ~= currencyId then
                    seen[itemId] = true
                    out[#out + 1] = group
                end
            end
        end
    end
    local results = TaskTracker.AttSearchField("currencyIDAsCost", currencyId)
    addResults(results)
    if #out == 0 then
        local currGroups = TaskTracker.AttSearchField("currencyID", currencyId)
        if type(currGroups) == "table" then
            local n = 0
            for _, g in pairs(currGroups) do
                n = n + 1
                if n > 8 then break end
                if type(g) == "table" then
                    addResults(attField(g, "costCollectibles"))
                end
            end
        end
    end
    return out
end

local function currencyListRow(index)
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, index)
    if ok and type(info) == "table" then return info end
    return nil
end

local function heldCurrencies()
    local out, seen = {}, {}
    local function add(id, qty)
        id = tonumber(id)
        if not id or id <= 0 or seen[id] then return end
        if qty == nil and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
            if ok and type(info) == "table" then qty = info.quantity end
        end
        if (tonumber(qty) or 0) <= 0 then return end
        seen[id] = true
        out[#out + 1] = id
    end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo then
        local okN, n = pcall(C_CurrencyInfo.GetCurrencyListSize)
        if okN and type(n) == "number" then
            for i = 1, n do
                local info = currencyListRow(i)
                if info and not info.isHeader then
                    add(info.currencyID or info.currencyId, info.quantity)
                end
            end
        end
    end
    -- Registry ids still count when that currency header is collapsed in the currency panel.
    if TaskTracker.Registry then
        for i = 1, #TaskTracker.Registry do
            local re = TaskTracker.Registry[i]
            if type(re) == "table" then
                add(re.currencyId)
                local reqs = re.purchaseReqs
                if type(reqs) == "table" then
                    for j = 1, #reqs do
                        local req = reqs[j]
                        if type(req) == "table" and tostring(req.type or "") == "currency" then
                            add(req.currencyId)
                        end
                    end
                end
            end
        end
    end
    return out
end

local function skipSet()
    local key = charKey() or ""
    local set = sessionSkip[key]
    if not set then
        set = {}
        sessionSkip[key] = set
    end
    return set
end

local function refreshList()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

local nameTimer
local nameFrame = CreateFrame("Frame")
nameFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
nameFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
nameFrame:SetScript("OnEvent", function(_, _, itemId, success)
    itemId = tonumber(itemId)
    if not itemId then return end
    if success == false then
        nameWait[itemId] = nil
        return
    end
    if transmogSetByItem[itemId] == 0 then
        transmogSetByItem[itemId] = nil
    end
    if TaskTracker.ClearItemTooltipKnownCache then
        TaskTracker.ClearItemTooltipKnownCache(itemId)
    end
    local waiting = nameWait[itemId]
    local rec = pool[itemId]
    if not waiting and not rec then return end
    if not rec then
        nameWait[itemId] = nil
        return
    end
    local name = clientItemName(itemId) or catalogDecorName(itemId, rec.decorId)
    local cached = TaskTracker.ItemRecordCached and TaskTracker.ItemRecordCached(itemId)
    if not name and not cached then return end
    nameWait[itemId] = nil
    if name then rec.name = name end
    if nameTimer then return end
    nameTimer = C_Timer.NewTimer(0.25, function()
        nameTimer = nil
        refreshList()
    end)
end)

local function finishScan(built)
    scanning = false
    pool = built or {}
    poolReady = true
    refreshList()
    if scanQueued then
        scanQueued = false
        TaskTracker.RequestReadyToBuyScan()
    end
end

local function startScanNow()
    if not readyEnabled() then
        scanning = false
        scanQueued = false
        return
    end
    if scanning then
        scanQueued = true
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        C_Timer.After(2, function()
            if TaskTracker.RequestReadyToBuyScan then TaskTracker.RequestReadyToBuyScan() end
        end)
        return
    end
    if not charKey() then return end
    if not attOn() then
        scanning = false
        pool = {}
        poolReady = true
        refreshList()
        return
    end
    local enabledIds, enabledKeys, anyExp = TaskTracker.ReadyToBuyEnabledExpansionSets()
    if not anyExp then
        scanning = false
        pool = {}
        poolReady = true
        refreshList()
        return
    end
    local rawCurrencies = heldCurrencies()
    local currencies = {}
    for i = 1, #rawCurrencies do
        if not currencyIgnored(rawCurrencies[i]) then
            currencies[#currencies + 1] = rawCurrencies[i]
        end
    end
    scanning = true
    clearTransmogSetOwnedCache()
    local built = {}
    local seenParents = {}
    local ci, groups, gi = 1, nil, 1
    local seeded = false
    local function tick()
        if not scanning then return end
        if not seeded then
            seeded = true
            seedRegistryBuys(enabledKeys, currencies, built)
        end
        local budget = GROUPS_PER_TICK
        local searches = 0
        while budget > 0 and poolSize(built) < POOL_CAP do
            if not groups or gi > #groups then
                if ci > #currencies or searches >= 8 then break end
                searches = searches + 1
                groups = collectCurrencyGroups(currencies[ci])
                ci = ci + 1
                gi = 1
            end
            while budget > 0 and groups and gi <= #groups and poolSize(built) < POOL_CAP do
                local group = groups[gi]
                pcall(considerGroup, group, enabledIds, built)
                enqueueGoldSiblings(group, groups, seenParents)
                gi = gi + 1
                budget = budget - 1
            end
            if not groups or gi > #groups then
                groups = nil
            else
                break
            end
        end
        local currenciesDone = ci > #currencies and not groups
        if poolSize(built) >= POOL_CAP or currenciesDone then
            finishScan(built)
        else
            C_Timer.After(0, tick)
        end
    end
    C_Timer.After(0, tick)
end

function TaskTracker.RequestReadyToBuyScan(immediate)
    if not readyEnabled() then
        if scanTimer then
            scanTimer:Cancel()
            scanTimer = nil
        end
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

function TaskTracker.SetReadyToBuyExpansionEnabled(key, on)
    local exp = expansionByKey(key)
    if not exp or exp.key ~= key then return end
    local d = db()
    if not d then return end
    if type(d.readyToBuyExpansions) ~= "table" then
        d.readyToBuyExpansions = { midnight = true }
    end
    on = not not on
    if (d.readyToBuyExpansions[key] and true or false) == on then return end
    d.readyToBuyExpansions[key] = on
    pool = {}
    poolReady = false
    TaskTracker.RequestReadyToBuyScan(true)
    refreshList()
end

function TaskTracker.SetReadyToBuyExpansion(key)
    local exp = expansionByKey(key)
    if not exp then return end
    local d = db()
    if not d then return end
    if d.readyToBuyExpansion == exp.key then return end
    d.readyToBuyExpansion = exp.key
    pool = {}
    poolReady = false
    TaskTracker.RequestReadyToBuyScan()
    refreshList()
end

function TaskTracker.GetReadyToBuyCount()
    return slotCount()
end

function TaskTracker.SetReadyToBuyCount(n)
    local d = db()
    if not d then return end
    n = math.floor(tonumber(n) or SLOT_DEFAULT)
    if n < SLOT_MIN then n = SLOT_MIN end
    if n > SLOT_MAX then n = SLOT_MAX end
    d.readyToBuyCount = n
end

function TaskTracker.GetReadyToBuySpendOrder()
    local d = db()
    if d and d.readyToBuySpendOrder == "low" then return "low" end
    return "high"
end

function TaskTracker.SetReadyToBuySpendOrder(order)
    local d = db()
    if not d then return end
    order = (order == "low") and "low" or "high"
    if d.readyToBuySpendOrder == order then return end
    d.readyToBuySpendOrder = order
    refreshList()
end

function TaskTracker.SetReadyToBuyKind(kind, on)
    local known = false
    for i = 1, #KIND_KEYS do
        if KIND_KEYS[i] == kind then known = true break end
    end
    if not known then return end
    local d = db()
    if not d then return end
    if type(d.readyToBuyKinds) ~= "table" then d.readyToBuyKinds = {} end
    on = not not on
    if kindEnabled(kind) == on then
        d.readyToBuyKinds[kind] = on
        return
    end
    d.readyToBuyKinds[kind] = on
    pool = {}
    poolReady = false
    TaskTracker.RequestReadyToBuyScan(true)
    refreshList()
end

function TaskTracker.SetReadyToBuyEnabled(on)
    local d = db()
    if not d then return end
    on = not not on
    if readyEnabled() == on then
        d.readyToBuyEnabled = on
        return
    end
    d.readyToBuyEnabled = on
    if not on then
        if scanTimer then
            scanTimer:Cancel()
            scanTimer = nil
        end
        scanning = false
        scanQueued = false
    end
    refreshList()
    if on then
        TaskTracker.RequestReadyToBuyScan(true)
    end
end

local function currencyDisplayName(currencyId)
    currencyId = tonumber(currencyId)
    if currencyId and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyId)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    return "Currency " .. tostring(currencyId or "?")
end

function TaskTracker.GetReadyToBuyCurrencyName(currencyId)
    return currencyDisplayName(currencyId)
end

local function currencyIdFromLink(text)
    if type(text) ~= "string" then return nil end
    local id = text:match("|Hcurrency:(%d+)") or text:match("currency:(%d+)")
    return tonumber(id)
end

function TaskTracker.FindReadyToBuyCurrencies(query)
    query = tostring(query or "")
    query = query:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H[^|]*|h", ""):gsub("|h", "")
    query = query:gsub("[%[%]]", "")
    query = query:match("^%s*(.-)%s*$") or ""
    if query == "" then return {} end
    local linked = currencyIdFromLink(query)
    if linked then
        return { { id = linked, name = currencyDisplayName(linked) } }
    end
    local q = query:lower()
    local exact, partial, seen = {}, {}, {}
    local function consider(id, name)
        id = tonumber(id)
        if not id or id <= 0 or seen[id] or currencyIgnored(id) then return end
        name = (type(name) == "string" and name ~= "") and name or currencyDisplayName(id)
        local ln = tostring(name):lower()
        if ln:find("^currency ", 1, false) and not ln:find(q, 1, true) then return end
        if ln == q then
            seen[id] = true
            exact[#exact + 1] = { id = id, name = name }
        elseif ln:find(q, 1, true) then
            seen[id] = true
            partial[#partial + 1] = { id = id, name = name }
        end
    end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then
        local okN, n = pcall(C_CurrencyInfo.GetCurrencyListSize)
        if okN and type(n) == "number" then
            for i = 1, n do
                local info = currencyListRow(i)
                if info and not info.isHeader then
                    local id = info.currencyID or info.currencyId
                    if not id and C_CurrencyInfo.GetCurrencyListLink then
                        local okL, link = pcall(C_CurrencyInfo.GetCurrencyListLink, i)
                        if okL then id = currencyIdFromLink(link) end
                    end
                    consider(id, info.name)
                end
            end
        end
    end
    local numeric = tonumber(query)
    if numeric then consider(numeric, currencyDisplayName(numeric)) end
    if TaskTracker.Registry then
        for i = 1, #TaskTracker.Registry do
            local re = TaskTracker.Registry[i]
            if type(re) == "table" then
                consider(re.currencyId)
                local reqs = re.purchaseReqs
                if type(reqs) == "table" then
                    for j = 1, #reqs do
                        local req = reqs[j]
                        if type(req) == "table" and tostring(req.type or "") == "currency" then
                            consider(req.currencyId)
                        end
                    end
                end
            end
        end
    end
    local out = (#exact > 0) and exact or partial
    table.sort(out, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

function TaskTracker.GetReadyToBuyIgnoredCurrencyIds()
    local list = ignoredList()
    local out = {}
    for i = 1, #list do
        local id = tonumber(list[i])
        if id and id > 0 then out[#out + 1] = id end
    end
    return out
end

function TaskTracker.GetReadyToBuyHeldCurrencies()
    local ids = heldCurrencies()
    local out = {}
    for i = 1, #ids do
        if not currencyIgnored(ids[i]) then
            out[#out + 1] = { id = ids[i], name = currencyDisplayName(ids[i]) }
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

function TaskTracker.AddReadyToBuyIgnoredCurrency(currencyId)
    currencyId = tonumber(currencyId)
    if not currencyId or currencyId <= 0 or currencyIgnored(currencyId) then return end
    local list = ignoredList()
    list[#list + 1] = currencyId
    for itemId, rec in pairs(pool) do
        if reqUsesIgnoredCurrency(rec.reqs) then
            pool[itemId] = nil
        end
    end
    refreshList()
end

function TaskTracker.RemoveReadyToBuyIgnoredCurrency(currencyId)
    currencyId = tonumber(currencyId)
    if not currencyId then return end
    local list = ignoredList()
    local nextList = {}
    local removed = false
    for i = 1, #list do
        local id = tonumber(list[i])
        if id ~= currencyId then
            if id then nextList[#nextList + 1] = id end
        else
            removed = true
        end
    end
    if not removed then return end
    local d = db()
    if d then d.readyToBuyIgnoredCurrencies = nextList end
    TaskTracker.RequestReadyToBuyScan(true)
end

function TaskTracker.RefreshReadyToBuyList()
    TaskTracker.RequestReadyToBuyScan(true)
end

function TaskTracker.DismissReadyToBuyVendor(vendorKey)
    if type(vendorKey) ~= "string" or vendorKey == "" then return end
    skipSet()[vendorKey] = true
    for itemId, rec in pairs(pool) do
        if rec.vendorKey == vendorKey then pool[itemId] = nil end
    end
    refreshList()
end

function TaskTracker.DismissGeneratedTask(nodeID)
    if type(nodeID) == "string" and nodeID:sub(1, 4) == "wqh:" then
        if TaskTracker.DismissWorldQuest then
            return TaskTracker.DismissWorldQuest(nodeID)
        end
        return true
    end
    if not TaskTracker.IsGeneratedTaskId(nodeID) then return false end
    local vendorKey = type(nodeID) == "string" and nodeID:match("^rtb:vendor:(.+)$")
    if vendorKey then
        TaskTracker.DismissReadyToBuyVendor(vendorKey)
        return true
    end
    local itemId = tonumber(type(nodeID) == "string" and nodeID:match("^rtb:(%d+)$") or nil)
    if not itemId then return true end
    local rec = pool[itemId]
    if rec and rec.vendorKey then
        TaskTracker.DismissReadyToBuyVendor(rec.vendorKey)
        return true
    end
    pool[itemId] = nil
    refreshList()
    return true
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

local function mapIdFromWay(cmd)
    if type(cmd) ~= "string" then return nil end
    return tonumber(cmd:match("^/way%s+#(%d+)"))
end

local function zoneForWay(cmd)
    local mapId = mapIdFromWay(cmd)
    if not mapId or not TaskTracker.ListZoneKeyForMapId then return nil end
    return TaskTracker.ListZoneKeyForMapId(mapId)
end

local function taskNode(rec, mode, listZone)
    local prefix = KIND_LABEL[rec.kind] or "Item"
    ensureItemName(rec)
    local buttons = {}
    local help = "This is in the spend for this vendor. Right-click to hide the vendor until you reload."
    if mode == "locked" then
        help = "You do not meet the reputation for this yet, so it is not part of the spend. Right-click to hide the vendor until you reload."
    elseif mode == "short" then
        help = "The earlier items in this spend already use that currency. Right-click to hide the vendor until you reload."
    end
    if rec.way then
        buttons[1] = {
            label = "Way",
            command = rec.way,
            icon = TaskTracker.WAY_COMMAND_ATLAS or "TaxiNode_Neutral",
            pinned = true,
        }
        help = help .. " The map pin uses AllTheThings' vendor waypoint."
    end
    local sub = subtitleFor(rec, mode)
    return {
        id = "rtb:" .. tostring(rec.itemId),
        type = "task",
        name = prefix .. ": " .. (rec.name or "Item"),
        done = false,
        reset = "none",
        taskMax = 1,
        taskCount = 0,
        note = "",
        commandButtons = buttons,
        accountWide = true,
        generatedTask = true,
        generatedSubtitle = sub,
        generatedHelp = help,
        readyToBuyItemId = rec.itemId,
        readyToBuyReqs = rec.reqs,
        readyToBuyVendor = rec.vendorKey,
        listZone = listZone,
    }
end

local function viewGroup(key, name, children, extra)
    local expanded = not (extra and extra.readyToBuyVendor)
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

local lastCurrencyQty = {}
local lastGold = 0

local function publicNumber(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return tonumber(v)
end

local function commaAmt(n)
    n = math.floor(tonumber(n) or 0)
    if BreakUpLargeNumbers then
        local ok, s = pcall(BreakUpLargeNumbers, n)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return tostring(n)
end

local function largestCurrencyCost(rec)
    local best = 0
    local reqs = rec and rec.reqs
    if type(reqs) ~= "table" then return 0 end
    for i = 1, #reqs do
        local r = reqs[i]
        if type(r) == "table" and tostring(r.type or "") == "currency" then
            local amt = tonumber(r.amount) or 0
            if amt > best then best = amt end
        end
    end
    return best
end

local function walletHas(wallet, req)
    local kind = tostring(req.type or ""):lower()
    if kind == "currency" then
        local id = tonumber(req.currencyId)
        local need = math.floor(tonumber(req.amount) or 0)
        if not id or need < 0 then return false end
        if wallet.currency[id] == nil then
            local qty = lastCurrencyQty[id] or 0
            if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
                if ok and type(info) == "table" then
                    local n = publicNumber(info.quantity)
                    if n then
                        qty = n
                        lastCurrencyQty[id] = n
                    end
                end
            end
            wallet.currency[id] = qty
        end
        return wallet.currency[id] >= need
    elseif kind == "gold" then
        local need = math.floor(tonumber(req.amount) or 0)
        if wallet.gold == nil then
            wallet.gold = lastGold
            if GetMoney then
                local ok, copper = pcall(GetMoney)
                if ok then
                    local copperN = publicNumber(copper)
                    if copperN then
                        wallet.gold = math.floor(copperN / 10000)
                        lastGold = wallet.gold
                    end
                end
            end
        end
        return wallet.gold >= need
    elseif kind == "item" then
        local id = tonumber(req.itemId)
        local need = math.max(1, math.floor(tonumber(req.amount) or 1))
        if not id then return false end
        if wallet.item[id] == nil then
            wallet.item[id] = 0
            wallet.item[id] = TaskTracker.ItemCount and TaskTracker.ItemCount(id, true) or 0
        end
        return wallet.item[id] >= need
    end
    return true
end

local function canSpend(rec, wallet)
    local reqs = rec.reqs
    if type(reqs) ~= "table" then return false end
    for i = 1, #reqs do
        local kind = tostring(reqs[i].type or ""):lower()
        if not REP_REQ[kind] and not walletHas(wallet, reqs[i]) then return false end
    end
    return true
end

local function takeSpend(rec, wallet, spent, goldSpent)
    local reqs = rec.reqs
    if type(reqs) ~= "table" then return end
    for i = 1, #reqs do
        local req = reqs[i]
        local kind = tostring(req.type or ""):lower()
        if kind == "currency" then
            local id = tonumber(req.currencyId)
            local need = math.floor(tonumber(req.amount) or 0)
            if id and need > 0 then
                wallet.currency[id] = (wallet.currency[id] or 0) - need
                spent[id] = (spent[id] or 0) + need
            end
        elseif kind == "gold" then
            local need = math.floor(tonumber(req.amount) or 0)
            wallet.gold = (wallet.gold or 0) - need
            goldSpent.n = goldSpent.n + need
        elseif kind == "item" then
            local id = tonumber(req.itemId)
            local need = math.max(1, math.floor(tonumber(req.amount) or 1))
            if id then wallet.item[id] = (wallet.item[id] or 0) - need end
        end
    end
end

-- One line per faction: current standing out of that reputation's maximum.
local function repLabels(items)
    local seen, out = {}, {}
    for i = 1, #items do
        local reqs = items[i].reqs
        if type(reqs) == "table" then
            for j = 1, #reqs do
                local req = reqs[j]
                local kind = tostring(req.type or ""):lower()
                if REP_REQ[kind] then
                    local fid = tonumber(req.factionId) or 0
                    if fid > 0 and not seen[fid] then
                        seen[fid] = true
                        local text = TaskTracker.FactionStandingLine and TaskTracker.FactionStandingLine(fid, req.label, kind)
                        if text then out[#out + 1] = text end
                    end
                end
            end
        end
    end
    table.sort(out)
    return out
end

local function spendSummary(bought, spent, goldSpent, items)
    local parts = { tostring(#bought) }
    local bits = {}
    for id, amt in pairs(spent) do
        bits[#bits + 1] = { name = currencyDisplayName(id), amt = amt }
    end
    table.sort(bits, function(a, b) return a.name < b.name end)
    for i = 1, #bits do
        parts[#parts + 1] = commaAmt(bits[i].amt) .. " " .. bits[i].name
    end
    if goldSpent.n > 0 then
        parts[#parts + 1] = commaAmt(goldSpent.n) .. " Gold"
    end
    local gates = repLabels(items)
    if #gates > 0 then
        parts[#parts + 1] = table.concat(gates, ", ")
    end
    return table.concat(parts, " · ")
end

local function vendorRows()
    local by = {}
    local order = {}
    local skip = skipSet()
    for _, rec in pairs(pool) do
        local key = rec.vendorKey
        if key and not skip[key] and not isOwned(rec) then
            local bucket = by[key]
            if not bucket then
                bucket = { key = key, name = rec.vendor or "Vendor", items = {} }
                by[key] = bucket
                order[#order + 1] = bucket
            end
            if rec.vendor and rec.vendor ~= "" then bucket.name = rec.vendor end
            if not bucket.listZone and rec.way then
                bucket.listZone = zoneForWay(rec.way)
            end
            bucket.items[#bucket.items + 1] = rec
        end
    end
    local high = TaskTracker.GetReadyToBuySpendOrder() ~= "low"
    local vendors = {}
    for i = 1, #order do
        local bucket = order[i]
        table.sort(bucket.items, function(a, b)
            local ca, cb = largestCurrencyCost(a), largestCurrencyCost(b)
            if ca ~= cb then
                if high then return ca > cb end
                return ca < cb
            end
            return tostring(a.name or "") < tostring(b.name or "")
        end)
        local wallet = { currency = {}, gold = nil, item = {} }
        local spent, goldSpent = {}, { n = 0 }
        local bought, locked, short = {}, {}, {}
        for j = 1, #bucket.items do
            local rec = bucket.items[j]
            if rec.repLocked then
                locked[#locked + 1] = rec
            elseif canSpend(rec, wallet) then
                takeSpend(rec, wallet, spent, goldSpent)
                bought[#bought + 1] = rec
            else
                short[#short + 1] = rec
            end
        end
        if #bought > 0 then
            bucket.bought = bought
            bucket.locked = locked
            bucket.short = short
            bucket.summary = spendSummary(bought, spent, goldSpent, bucket.items)
            vendors[#vendors + 1] = bucket
        end
    end
    local here = TaskTracker.GetPlayerListZone and TaskTracker.GetPlayerListZone()
    table.sort(vendors, function(a, b)
        local ah = here and a.listZone == here
        local bh = here and b.listZone == here
        if ah ~= bh then return ah and true or false end
        return tostring(a.name) < tostring(b.name)
    end)
    return vendors
end

local function readyChildren()
    if not poolReady and not scanning then
        TaskTracker.RequestReadyToBuyScan()
    end
    if not attOn() then
        if TaskTracker.IsAllTheThingsLoaded and not TaskTracker.IsAllTheThingsLoaded() then
            return { statusNode("rtb:noatt", "Install AllTheThings to fill this list.") }
        end
        return { statusNode("rtb:attoff", "AllTheThings data is turned off in Options.") }
    end
    if not poolReady or scanning then
        return { statusNode("rtb:wait", "Looking up things you can buy…") }
    end
    local vendors = vendorRows()
    if #vendors == 0 then
        return { statusNode("rtb:empty", "Nothing to buy in your selected expansions.") }
    end
    local children = {}
    for i = 1, #vendors do
        local vendor = vendors[i]
        local items = {}
        for j = 1, #vendor.bought do
            items[#items + 1] = taskNode(vendor.bought[j], "buy", vendor.listZone)
        end
        for j = 1, #vendor.short do
            items[#items + 1] = taskNode(vendor.short[j], "short", vendor.listZone)
        end
        for j = 1, #vendor.locked do
            items[#items + 1] = taskNode(vendor.locked[j], "locked", vendor.listZone)
        end
        children[#children + 1] = viewGroup("gen:ready:" .. vendor.key, vendor.name, items, {
            readyToBuyVendor = vendor.key,
            readyToBuySummary = vendor.summary,
            listZone = vendor.listZone,
        })
    end
    return children, #vendors
end

function TaskTracker.AppendGeneratedTaskGroups(children)
    if TaskTracker.editMode then return children end
    if type(children) ~= "table" then children = {} end
    local groups = {}
    if readyEnabled() then
        local kids, vendorCount = readyChildren()
        local headerExtra = { readyToBuyHeader = true }
        if vendorCount and vendorCount > 0 then
            headerExtra.readyToBuySummary = tostring(vendorCount)
        end
        groups[#groups + 1] = viewGroup("gen:ready", "Ready to Buy Tasks", kids, headerExtra)
    end
    if TaskTracker.BuildWorldQuestHuntGroup then
        local hunt = TaskTracker.BuildWorldQuestHuntGroup()
        if hunt then groups[#groups + 1] = hunt end
    end
    if #groups == 0 then return children end
    local out = {}
    for i = 1, #children do out[i] = children[i] end
    out[#out + 1] = viewGroup("gen", "Generated Tasks", groups)
    return out
end
