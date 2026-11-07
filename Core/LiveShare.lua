-- Core/LiveShare.lua
-- Live task sync to one character on another account (addon whisper).
-- Both clients must be online. Offline sends wait until the next login.

TaskTracker = TaskTracker or {}

local PREFIX = "TTLive"
local MAX_BODY = 32768
local trim = TaskTracker.Trim or function(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local whisperQueue = {}
local pumpTicker
local prefixRegistered = false
local ownerNodes
local lastSentSig = {}
local scanPending = false
local partials = {}
local lastRefuseAt = 0

local function say(msg)
    print("|cff00ff00TaskTracker|r " .. msg)
end

local function normalizeRealm(realm)
    realm = trim(realm or "")
    realm = realm:gsub("[%s%-'’]", "")
    return realm
end

local function whoParts(s)
    s = (s or ""):gsub("%s+", "")
    local name, realm = s:match("^([^%-]+)%-(.+)$")
    if name and realm and realm ~= "" then
        return name:lower(), normalizeRealm(realm):lower()
    end
    return s:lower(), nil
end

--- Addon whispers on the same server sometimes arrive as Name, sometimes Name-Realm.
local function sameWho(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or a == "" or b == "" then return false end
    local n1, r1 = whoParts(a)
    local n2, r2 = whoParts(b)
    if n1 == "" or n2 == "" or n1 ~= n2 then return false end
    if r1 and r2 then return r1 == r2 end
    return true
end

local function whisperTarget(name, realm)
    name = trim(name or "")
    local realmNorm = normalizeRealm(realm)
    if name == "" or realmNorm == "" then return nil end
    return name .. "-" .. realmNorm
end

--- Whisper address. Spaces stay out of the realm ("Aerie Peak" is "AeriePeak").
--- On your own server the target is the character name alone. "Name-AeriePeak"
--- does not resolve there, so the other character never sees the message.
local function myNormalizedRealm()
    local n = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(n) == "string" and n ~= "" then return n end
    local shown = GetRealmName and GetRealmName() or ""
    return normalizeRealm(shown)
end

local function deliveryTarget(identity)
    if type(identity) ~= "string" or identity == "" then return identity end
    local name, realm = identity:match("^([^%-]+)%-(.+)$")
    if not name or not realm or realm == "" then return identity end
    local mine = myNormalizedRealm()
    if mine ~= "" and realm:lower() == mine:lower() then
        return name
    end
    return name .. "-" .. normalizeRealm(realm)
end

local function prettyRealm(normalized)
    if type(normalized) ~= "string" or normalized == "" then return "" end
    local shown = GetRealmName and GetRealmName() or ""
    if shown ~= "" and normalizeRealm(shown):lower() == normalizeRealm(normalized):lower() then
        return shown
    end
    return normalized
end

local function hiddenProfile()
    return TaskTracker.HiddenProfileIsLoaded and TaskTracker.HiddenProfileIsLoaded()
end

function TaskTracker.InvalidateLiveShareIndex()
    ownerNodes = nil
end

local function ensureOwnerNodes()
    if ownerNodes then return ownerNodes end
    ownerNodes = {}
    if not TaskTracker.WalkTree then return ownerNodes end
    TaskTracker.WalkTree(function(node)
    if node.type == "task" and ((node.liveShareRole == "owner" and type(node.liveShareTo) == "string" and node.liveShareTo ~= "")
        or (node.liveShareRole == "receiver" and node.liveShareTwoWay == true and type(node.liveShareOwner) == "string" and node.liveShareOwner ~= "")) then
            ownerNodes[#ownerNodes + 1] = node
        end
    end)
    return ownerNodes
end

function TaskTracker.TaskProgressIsLocked(node)
    return type(node) == "table" and node.type == "task" and node.liveShareRole == "receiver"
end

function TaskTracker.RefuseLockedTaskProgress(node, delta)
    if TaskTracker._ttLiveShareApplying then return false end
    if not TaskTracker.TaskProgressIsLocked(node) then return false end
    if node.liveShareTwoWay == true and type(delta) == "number" and delta > 0 then
        return false
    end
    local now = GetTime and GetTime() or 0
    if now - lastRefuseAt > 1 then
        lastRefuseAt = now
        if node.liveShareTwoWay == true then
            say("You can add to this count. You can't lower it.")
        else
            local who = node.liveShareOwner or "the other character"
            say("Progress on this task comes from " .. who .. ".")
        end
    end
    return true
end

local function charKeyMatches(name, realm)
    local n = trim(name):lower()
    local r = normalizeRealm(realm):lower()
    if n == "" or r == "" then return false end
    local function one(key)
        if not TaskTracker.ParseCharProgressKey then return false end
        local kr, kn = TaskTracker.ParseCharProgressKey(key)
        if type(kn) ~= "string" or kn == "" then return false end
        return kn:lower() == n and normalizeRealm(kr or ""):lower() == r
    end
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if key and one(key) then return true end
    local root = TaskTrackerDB and TaskTrackerDB.charTaskProgress
    if type(root) == "table" then
        for k, bucket in pairs(root) do
            if type(k) == "string" and type(bucket) == "table" and one(k) then
                return true
            end
        end
    end
    return false
end

function TaskTracker.LiveShareTargetIsThisAccount(name, realm)
    return charKeyMatches(name, realm)
end

--- Profile key liveShareEnabled. Missing or false stays off.
function TaskTracker.IsLiveShareEnabled()
    return TaskTrackerDB and TaskTrackerDB.liveShareEnabled == true
end

function TaskTracker.IsLiveShareSyncAllButtonEnabled()
    return TaskTrackerDB and TaskTrackerDB.liveShareSyncAllButton == true
end

local function currentShareCharKey()
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if type(key) == "string" and key ~= "" then return key end
    return nil
end

local function shareCharDisplayName(key)
    if type(key) ~= "string" then return "that character" end
    local name = key:match("::(.+)$")
    if type(name) == "string" and name ~= "" then return name end
    return "that character"
end

--- Per-character shares follow the character who sent them. Account-wide stays one count.
local function shareIsPerCharacter(node)
    return not (TaskTracker.IsTaskAccountWide and TaskTracker.IsTaskAccountWide(node))
end

--- Status for the Sync window. Nil when this character may send.
function TaskTracker.LiveShareCharStatus(node)
    if not node or node.type ~= "task" or node.liveShareRole ~= "owner" then return nil end
    if not shareIsPerCharacter(node) then return nil end
    local key = node.liveShareCharKey
    if type(key) ~= "string" or key == "" then
        return nil
    end
    if currentShareCharKey() == key then return nil end
    return "This count is " .. shareCharDisplayName(key) .. "'s. Log that character to update that share."
end

--- Stamp on an explicit Send. A mismatch does not retarget that character's share.
local function claimShareCharKey(node)
    if not shareIsPerCharacter(node) then return nil end
    local cur = currentShareCharKey()
    if not cur then return "Sync isn't ready for this character yet." end
    local key = node.liveShareCharKey
    if type(key) == "string" and key ~= "" and key ~= cur then
        return TaskTracker.LiveShareCharStatus(node)
    end
    node.liveShareCharKey = cur
    return nil
end

local function rememberFlatShare(node)
    if not node or not shareIsPerCharacter(node) or node.liveShareRole ~= "owner" then return end
    local key = node.liveShareCharKey
    if type(key) ~= "string" or key == "" then return end
    if type(node.liveShareId) ~= "string" or type(node.liveShareTo) ~= "string" or node.liveShareTo == "" then return end
    if type(node.liveShareByChar) ~= "table" then
        node.liveShareByChar = {}
    end
    node.liveShareByChar[key] = {
        id = node.liveShareId,
        to = node.liveShareTo,
        realm = node.liveShareRealm,
        rev = node.liveShareRev,
        twoWay = node.liveShareTwoWay == true and true or nil,
        selfAdded = node.liveShareSelfAdded,
        peerAdded = node.liveSharePeerAdded,
        sentCount = node.liveShareSentCount,
        countEpoch = node.liveShareCountEpoch,
        addGen = node.liveShareAddGen,
    }
end

local function clearFlatOwnerFields(node)
    node.liveShareId = nil
    node.liveShareRole = nil
    node.liveShareTo = nil
    node.liveShareOwner = nil
    node.liveShareRealm = nil
    node.liveShareRev = nil
    node.liveShareReceivedAt = nil
    node.liveShareTwoWay = nil
    node.liveShareCharKey = nil
    node.liveShareSelfAdded = nil
    node.liveSharePeerAdded = nil
    node.liveShareSentCount = nil
    node.liveShareCountEpoch = nil
    node.liveShareAddGen = nil
    node.liveSharePersonal = nil
end

--- The count already on the task is the shared total. Add counters start at
--- zero so that total is not sent again as a new add. Gen 1 replaces the first
--- pass, which stored the whole count as this side's adds.
local SHARE_ADD_GEN = 1

local function ensureShareCountBaseline(node)
    if not node or node.liveShareTwoWay ~= true then return end
    if node.liveShareRole ~= "owner" and node.liveShareRole ~= "receiver" then return end
    if node.liveShareAddGen ~= SHARE_ADD_GEN then
        node.liveShareSelfAdded = 0
        node.liveSharePeerAdded = 0
        node.liveShareSentCount = tonumber(node.taskCount) or 0
        node.liveSharePersonal = nil
        if node.liveShareCountEpoch == nil then node.liveShareCountEpoch = 0 end
        node.liveShareAddGen = SHARE_ADD_GEN
        return
    end
    if node.liveShareSentCount == nil then
        node.liveShareSentCount = tonumber(node.taskCount) or 0
    end
    if node.liveShareSelfAdded == nil then node.liveShareSelfAdded = 0 end
    if node.liveSharePeerAdded == nil then node.liveSharePeerAdded = 0 end
    if node.liveShareCountEpoch == nil then node.liveShareCountEpoch = 0 end
end

function TaskTracker.TwoWayShareCounts(node)
    if TaskTracker._ttLiveShareApplying then return false end
    if not node or node.liveShareTwoWay ~= true then return false end
    if node.liveShareRole ~= "owner" and node.liveShareRole ~= "receiver" then return false end
    return true
end

--- Automation writes this character's own total into taskCount. Keep the shared
--- total. A mob kill already added one. Other kinds add only the new bit.
function TaskTracker.PushTwoWayPersonalCount(node)
    if not TaskTracker.TwoWayShareCounts(node) then return nil end
    return tonumber(node.taskCount) or 0
end

function TaskTracker.PopTwoWayPersonalCount(node, sharedBefore)
    if not node or sharedBefore == nil then return end
    if not TaskTracker.TwoWayShareCounts(node) then return end
    local personal = tonumber(node.taskCount) or 0
    local kind = type(node.advanced) == "table" and node.advanced.type or nil
    if kind == "mob_kill" then
        node.taskCount = sharedBefore
    else
        local prev = node.liveSharePersonal
        if type(prev) ~= "number" then
            node.liveSharePersonal = personal
            node.taskCount = sharedBefore
        else
            local gain = personal - prev
            if gain > 0 then
                node.taskCount = sharedBefore + gain
                node.liveSharePersonal = personal
            else
                node.taskCount = sharedBefore
            end
        end
    end
    local max = tonumber(node.taskMax)
    local count = tonumber(node.taskCount) or 0
    if max and max > 0 and count >= max then
        node.done = true
    end
end

local function noteLocalShareAdds(node)
    if not node or node.liveShareTwoWay ~= true then return end
    if node.liveShareSentCount == nil then
        ensureShareCountBaseline(node)
        return
    end
    local cur = tonumber(node.taskCount) or 0
    local sent = tonumber(node.liveShareSentCount) or 0
    if cur > sent then
        node.liveShareSelfAdded = (tonumber(node.liveShareSelfAdded) or 0) + (cur - sent)
    elseif cur < sent and node.liveShareRole == "owner" then
        node.liveShareCountEpoch = (tonumber(node.liveShareCountEpoch) or 0) + 1
        node.liveShareSelfAdded = 0
        node.liveSharePeerAdded = 0
    end
    node.liveShareSentCount = cur
end

local function dropShareSlot(node, key)
    local map = node and node.liveShareByChar
    if type(map) ~= "table" or type(key) ~= "string" or key == "" then return end
    map[key] = nil
    if not next(map) then
        node.liveShareByChar = nil
    end
end

--- The node shows the logged-in character's share. Other characters keep theirs in liveShareByChar.
local function projectLiveShareNode(node, charKey)
    if not node or node.type ~= "task" or node.liveShareRole == "receiver" then return end
    if not shareIsPerCharacter(node) then return end
    local oldKey = node.liveShareCharKey
    if node.liveShareRole == "owner" and type(oldKey) == "string" and oldKey ~= "" then
        rememberFlatShare(node)
        if oldKey == charKey then return end
    end
    if type(charKey) ~= "string" or charKey == "" then return end
    local map = node.liveShareByChar
    local slot = type(map) == "table" and map[charKey] or nil
    if type(slot) == "table" and type(slot.id) == "string" and type(slot.to) == "string" and slot.to ~= "" then
        node.liveShareRole = "owner"
        node.liveShareOwner = nil
        node.liveShareReceivedAt = nil
        node.liveShareCharKey = charKey
        node.liveShareId = slot.id
        node.liveShareTo = slot.to
        node.liveShareRealm = slot.realm
        node.liveShareRev = slot.rev
        node.liveShareTwoWay = slot.twoWay == true and true or nil
        node.liveShareSelfAdded = slot.selfAdded
        node.liveSharePeerAdded = slot.peerAdded
        node.liveShareSentCount = slot.sentCount
        node.liveShareCountEpoch = slot.countEpoch
        node.liveShareAddGen = slot.addGen
        return
    end
    if node.liveShareRole == "owner" and type(oldKey) == "string" and oldKey ~= "" and oldKey ~= charKey then
        clearFlatOwnerFields(node)
    end
end

function TaskTracker.ProjectLiveShareNode(node)
    local key = currentShareCharKey() or TaskTracker._activeCharProgressKey
    projectLiveShareNode(node, key)
end

function TaskTracker.ProjectLiveSharesForCurrentChar()
    if not TaskTracker.WalkTree then return end
    local key = currentShareCharKey() or TaskTracker._activeCharProgressKey
    TaskTracker.WalkTree(function(node)
        projectLiveShareNode(node, key)
        ensureShareCountBaseline(node)
    end)
    TaskTracker.InvalidateLiveShareIndex()
end

function TaskTracker.StashLiveSharesOnLeave()
    if not TaskTracker.WalkTree then return end
    TaskTracker.WalkTree(function(node)
        if node.liveShareRole ~= "owner" or not shareIsPerCharacter(node) then return end
        if type(node.liveShareCharKey) ~= "string" or node.liveShareCharKey == "" then return end
        rememberFlatShare(node)
        clearFlatOwnerFields(node)
    end)
    TaskTracker.InvalidateLiveShareIndex()
end

function TaskTracker.LiveShareHasOtherCharShares(node)
    local map = node and node.liveShareByChar
    if type(map) ~= "table" then return false end
    local cur = currentShareCharKey() or TaskTracker._activeCharProgressKey
    for key, slot in pairs(map) do
        if key ~= cur and type(slot) == "table" and type(slot.id) == "string" then
            return true
        end
    end
    return false
end

local function ownerCanSend(node)
    if hiddenProfile() then return false end
    if not node or node.type ~= "task" then return false end
    if node.liveShareRole ~= "owner" then return false end
    if type(node.liveShareTo) ~= "string" or node.liveShareTo == "" then return false end
    if type(node.liveShareId) ~= "string" or not node.liveShareId:match("^%x%x%x%x%x%x%x%x$") then return false end
    if shareIsPerCharacter(node) then
        local key = node.liveShareCharKey
        if type(key) ~= "string" or key == "" or currentShareCharKey() ~= key then
            return false
        end
    end
    if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then
        return false
    end
    return true
end

local function progressSignature(node)
    local parts = {
        node.done and "1" or "0",
        tostring(node.taskCount or 0),
        tostring(node.taskUserValue or ""),
        tostring(node.doneOverride or ""),
        tostring(node.taskMax or ""),
    }
    local a = node.advanced
    if type(a) == "table" then
        parts[#parts + 1] = tostring(a.goldAutoCopper or "")
        parts[#parts + 1] = tostring(a.itemAutoCount or "")
        parts[#parts + 1] = tostring(a.mobAutoCount or "")
        parts[#parts + 1] = tostring(a.collectableAutoCount or "")
        parts[#parts + 1] = tostring(a.collectableFishAttempts or "")
        if type(a.questPeriodCredited) == "table" then
            local n = 0
            for _ in pairs(a.questPeriodCredited) do n = n + 1 end
            parts[#parts + 1] = "q" .. n
        end
    end
    local st = node.subtext
    if type(st) == "table" then
        parts[#parts + 1] = "s" .. tostring(st.lifetimeKills or "") .. ":" .. tostring(st.goldPeriodCopper or "")
    end
    if type(node.extraGoals) == "table" then
        for i = 1, #node.extraGoals do
            local g = node.extraGoals[i]
            if type(g) == "table" then
                parts[#parts + 1] = tostring(g.done) .. ":" .. tostring(g.taskCount or 0) .. ":" .. tostring(g.taskUserValue or "") .. ":" .. tostring(g.doneOverride or "")
                local ga = g.advanced
                if type(ga) == "table" then
                    parts[#parts + 1] = tostring(ga.mobAutoCount or "") .. ":" .. tostring(ga.itemAutoCount or "") .. ":" .. tostring(ga.collectableAutoCount or "") .. ":" .. tostring(ga.goldAutoCopper or "")
                end
            end
        end
    end
    return table.concat(parts, ",")
end

local function markSent(node)
    if node and node.liveShareId then
        lastSentSig[node.liveShareId] = progressSignature(node)
    end
end

function TaskTracker.RegisterLiveSharePrefix()
    if prefixRegistered then return true end
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then return false end
    local ok, registered = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    prefixRegistered = ok and registered ~= false
    return prefixRegistered
end

local function stopPump()
    if pumpTicker then
        pumpTicker:Cancel()
        pumpTicker = nil
    end
end

local function pumpOnce()
    if #whisperQueue == 0 then
        stopPump()
        return
    end
    local item = table.remove(whisperQueue, 1)
    if not item or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        return
    end
    TaskTracker.RegisterLiveSharePrefix()
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, "WHISPER", item.target)
end

local function ensurePump()
    if pumpTicker or #whisperQueue == 0 then return end
    if not C_Timer or not C_Timer.NewTicker then
        while #whisperQueue > 0 do
            pumpOnce()
        end
        return
    end
    pumpTicker = C_Timer.NewTicker(0.2, pumpOnce)
end

local function enqueue(target, msg)
    target = deliveryTarget(target)
    if type(target) ~= "string" or target == "" or type(msg) ~= "string" or msg == "" then return end
    if #msg > 255 then return end
    whisperQueue[#whisperQueue + 1] = { target = target, msg = msg }
    ensurePump()
end

local function enqueueBody(target, kind, shareId, rev, body)
    if type(body) ~= "string" or body == "" then return false end
    local overhead = #string.format("%s|%s|%d|%d|%d|", kind, shareId, rev, 100, 100)
    local room = 255 - overhead
    if room < 40 then return false end
    local total = math.ceil(#body / room)
    if total < 1 then total = 1 end
    if total > 200 then return false end
    local pos = 1
    for seq = 1, total do
        local header = string.format("%s|%s|%d|%d|%d|", kind, shareId, rev, seq, total)
        local take = 255 - #header
        local frag = body:sub(pos, pos + take - 1)
        pos = pos + #frag
        enqueue(target, header .. frag)
    end
    return true
end

local function nextRev(node)
    local rev = (tonumber(node.liveShareRev) or 0) + 1
    if rev > 2000000000 then rev = 1 end
    node.liveShareRev = rev
    rememberFlatShare(node)
    return rev
end

local function newShareId()
    return string.format("%08x", math.random(0, 0x7fffffff))
end

local function findByShareId(shareId)
    if not shareId or not TaskTracker.WalkTree then return nil end
    local found
    TaskTracker.WalkTree(function(node)
        if not found and node.type == "task" and node.liveShareId == shareId then
            found = node
        end
    end)
    return found
end

local function clearShareFields(node)
    if not node then return end
    node.liveShareId = nil
    node.liveShareRole = nil
    node.liveShareTo = nil
    node.liveShareOwner = nil
    node.liveShareRealm = nil
    node.liveShareRev = nil
    node.liveShareReceivedAt = nil
    node.liveShareTwoWay = nil
    node.liveShareCharKey = nil
    node.liveShareSelfAdded = nil
    node.liveSharePeerAdded = nil
    node.liveShareSentCount = nil
    node.liveShareCountEpoch = nil
    node.liveShareAddGen = nil
    node.liveSharePersonal = nil
    node.liveSharePeriod = nil
end

local function currentWeeklyReset()
    if not TaskTracker.GetResetTimes then return nil end
    local _, week = TaskTracker.GetResetTimes()
    week = tonumber(week)
    if not week or week <= 0 then return nil end
    return week
end

--- A received weekly task keeps the week it was synced for. A late login
--- must not clear a count that already belongs to this week.
function TaskTracker.LiveShareHoldsWeeklyReset(node, weeklyReset)
    if not node or node.type ~= "task" or node.liveShareRole ~= "receiver" or node.reset ~= "weekly" then
        return false
    end
    weeklyReset = tonumber(weeklyReset)
    if not weeklyReset or weeklyReset <= 0 then return false end
    local stamped = tonumber(node.liveSharePeriod)
    if not stamped or stamped >= weeklyReset then
        if not stamped then
            node.liveSharePeriod = weeklyReset
        end
        return true
    end
    return false
end

local function stampReceivedWeek(node, week)
    if not node or node.liveShareRole ~= "receiver" or node.reset ~= "weekly" then return end
    week = tonumber(week)
    if not week or week <= 0 then
        week = currentWeeklyReset()
    end
    if week then
        node.liveSharePeriod = week
    end
end

local function sendControl(target, kind, shareId)
    if type(target) ~= "string" or type(shareId) ~= "string" then return end
    enqueue(target, kind .. "|" .. shareId)
end

function TaskTracker.SendLiveShareTask(node)
    if node and node.liveShareRole == "owner" and shareIsPerCharacter(node) then
        local key = node.liveShareCharKey
        if type(key) == "string" and key ~= "" and currentShareCharKey() ~= key then
            return TaskTracker.LiveShareCharStatus(node)
        end
    end
    if not ownerCanSend(node) then return "Sync isn't set up on this task." end
    if not TaskTracker.ExportLiveShareTaskString then return "Sync isn't ready." end
    local body = TaskTracker.ExportLiveShareTaskString(node)
    if type(body) ~= "string" or body == "" then return "Could not prepare this task." end
    if #body > MAX_BODY then return "This task is too big to sync." end
    local rev = nextRev(node)
    if not enqueueBody(node.liveShareTo, "T", node.liveShareId, rev, body) then
        return "Could not send this task."
    end
    markSent(node)
    return nil
end

local function twoWayReceiverCanSend(node)
    if hiddenProfile() then return false end
    if not node or node.type ~= "task" or node.liveShareRole ~= "receiver" or node.liveShareTwoWay ~= true then
        return false
    end
    if type(node.liveShareOwner) ~= "string" or node.liveShareOwner == "" then return false end
    if type(node.liveShareId) ~= "string" or not node.liveShareId:match("^%x%x%x%x%x%x%x%x$") then return false end
    if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then
        return false
    end
    return true
end

local function sendProgress(node)
    local target
    if node and node.liveShareRole == "owner" then
        if not ownerCanSend(node) then return false end
        target = node.liveShareTo
    elseif twoWayReceiverCanSend(node) then
        target = node.liveShareOwner
    else
        return false
    end
    if not TaskTracker.SnapshotTaskProgress or not TaskTracker.PackShareValue then return false end
    noteLocalShareAdds(node)
    local snap = TaskTracker.SnapshotTaskProgress(node)
    if type(snap) ~= "table" then return false end
    if node.liveShareTwoWay == true then
        snap.shareSelfAdded = tonumber(node.liveShareSelfAdded) or 0
        snap.shareCountEpoch = tonumber(node.liveShareCountEpoch) or 0
    end
    if node.reset == "weekly" then
        local week = currentWeeklyReset()
        if week then snap.shareWeek = week end
    end
    local body = TaskTracker.PackShareValue(snap)
    if type(body) ~= "string" or body == "" or #body > MAX_BODY then return false end
    local rev = nextRev(node)
    if not enqueueBody(target, "P", node.liveShareId, rev, body) then return false end
    markSent(node)
    return true
end

--- Entering-world is registered about a second after load, after login and
--- /reload have already fired it. Arming sync only from that event left
--- _ttLiveShareReady false for the whole session, so progress never whispered
--- and the addon prefix was never registered, so incoming tasks were dropped too.
function TaskTracker.ScheduleLiveShareLogin()
    if IsPlayerInWorld and not IsPlayerInWorld() then return end
    local key = TaskTracker._activeCharProgressKey
    if not key and TaskTracker.GetCharProgressKey then
        key = TaskTracker.GetCharProgressKey()
    end
    if not key or key == "" then return end
    if TaskTracker.ProjectLiveSharesForCurrentChar then
        TaskTracker.ProjectLiveSharesForCurrentChar()
    end
    TaskTracker._ttLiveShareReady = true
    if TaskTracker.RegisterLiveSharePrefix then
        TaskTracker.RegisterLiveSharePrefix()
    end
    if TaskTracker._ttLiveShareLoginScheduled then return end
    TaskTracker._ttLiveShareLoginScheduled = true
    local function go()
        TaskTracker._ttLiveShareLoginScheduled = nil
        if IsPlayerInWorld and not IsPlayerInWorld() then
            TaskTracker.ScheduleLiveShareLogin()
            return
        end
        if TaskTracker.SendLiveShareOnLogin then
            TaskTracker.SendLiveShareOnLogin()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(2, go)
    else
        go()
    end
end

function TaskTracker.QueueLiveShareScan()
    if TaskTracker._ttLiveShareApplying then return end
    if not TaskTracker._ttLiveShareReady then
        if TaskTracker.ScheduleLiveShareLogin then
            TaskTracker.ScheduleLiveShareLogin()
        end
        if not TaskTracker._ttLiveShareReady then return end
    end
    if scanPending then return end
    local list = ensureOwnerNodes()
    if #list == 0 then return end
    scanPending = true
    if not C_Timer or not C_Timer.After then
        scanPending = false
        return
    end
    C_Timer.After(1, function()
        scanPending = false
        if TaskTracker._ttLiveShareApplying then return end
        local nodes = ensureOwnerNodes()
        for i = 1, #nodes do
            local n = nodes[i]
            if ownerCanSend(n) or twoWayReceiverCanSend(n) then
                local sig = progressSignature(n)
                if lastSentSig[n.liveShareId] ~= sig then
                    sendProgress(n)
                end
            end
        end
    end)
end

local function applyScope(node, accountWide)
    if TaskTracker.ApplyTaskScopeFieldsToNode then
        TaskTracker.ApplyTaskScopeFieldsToNode(node, accountWide and true or false, false)
    elseif accountWide then
        node.accountWide = true
        node.showOnOtherCharacters = nil
        node.ownerCharKey = nil
    else
        node.accountWide = nil
        node.showOnOtherCharacters = nil
    end
end

local function persistNode(node)
    if TaskTracker.IsTaskAccountWide and TaskTracker.IsTaskAccountWide(node) then return end
    if TaskTracker.PersistOneCharTaskProgress then
        TaskTracker.PersistOneCharTaskProgress(node)
    end
end

local function refreshAfterShare()
    if TaskTracker.InvalidateAdvancedTaskIndex then TaskTracker.InvalidateAdvancedTaskIndex() end
    if TaskTracker.MarkListDirtyFromProgressChange then TaskTracker.MarkListDirtyFromProgressChange() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

local function copyDefinition(node, payload)
    node.name = payload.name
    node.reset = payload.reset
    node.taskMax = payload.taskMax
    node.goalMode = payload.goalMode
    if payload.excludeFromRollup then
        node.excludeFromRollup = true
    else
        node.excludeFromRollup = nil
    end
    if payload.alwaysShow then
        node.alwaysShow = true
    else
        node.alwaysShow = nil
    end
    if TaskTracker.DeepCopy then
        node.advanced = TaskTracker.DeepCopy(payload.advanced)
        node.extraGoals = TaskTracker.DeepCopy(payload.extraGoals)
        node.subtext = TaskTracker.DeepCopy(payload.subtext)
    else
        node.advanced = payload.advanced
        node.extraGoals = payload.extraGoals
        node.subtext = payload.subtext
    end
    if TaskTracker.SnapshotTaskProgress and TaskTracker.ApplyTaskProgressSnapshot then
        TaskTracker.ApplyTaskProgressSnapshot(node, TaskTracker.SnapshotTaskProgress(payload))
    end
    applyScope(node, payload.accountWide == true)
    if payload.liveShareTwoWay == true then
        node.liveShareTwoWay = true
    else
        node.liveShareTwoWay = nil
    end
end

local function acceptTask(sender, shareId, rev, body)
    if hiddenProfile() then return end
    local existing = findByShareId(shareId)
    if not existing and not TaskTracker.IsLiveShareEnabled() then return end
    if not TaskTracker.DecodeLiveShareTaskString then return end
    local payload = TaskTracker.DecodeLiveShareTaskString(body)
    if type(payload) ~= "table" then return end
    rev = tonumber(rev) or 0
    TaskTracker._ttLiveShareApplying = true
    if existing then
        if existing.liveShareRole ~= "receiver" or not sameWho(existing.liveShareOwner, sender) then
            TaskTracker._ttLiveShareApplying = nil
            return
        end
        if rev < (tonumber(existing.liveShareRev) or 0) then
            TaskTracker._ttLiveShareApplying = nil
            return
        end
        copyDefinition(existing, payload)
        if existing.liveShareTwoWay == true then
            local incomingEpoch = tonumber(payload.shareCountEpoch)
            if incomingEpoch and incomingEpoch > (tonumber(existing.liveShareCountEpoch) or 0) then
                existing.liveShareCountEpoch = incomingEpoch
                existing.liveShareSelfAdded = 0
            end
            if payload.shareSelfAdded ~= nil then
                existing.liveSharePeerAdded = tonumber(payload.shareSelfAdded) or 0
            end
            existing.liveShareSentCount = tonumber(existing.taskCount) or 0
        end
        existing.liveShareRev = rev
        stampReceivedWeek(existing, payload.shareWeek)
        persistNode(existing)
        TaskTracker._ttLiveShareApplying = nil
        if TaskTracker.InvalidateLiveShareIndex then TaskTracker.InvalidateLiveShareIndex() end
        refreshAfterShare()
        return
    end
    local node = TaskTracker.DeepCopy and TaskTracker.DeepCopy(payload) or payload
    node.type = "task"
    node.id = TaskTracker.GenerateUUID and TaskTracker.GenerateUUID() or tostring(GetTime() or 0)
    node.liveShareId = shareId
    node.liveShareRole = "receiver"
    node.liveShareOwner = sender
    node.liveShareTo = nil
    node.liveShareRev = rev
    node.liveShareReceivedAt = (GetServerTime and GetServerTime()) or nil
    node.children = nil
    applyScope(node, node.accountWide == true)
    if not (TaskTracker.IsTaskAccountWide and TaskTracker.IsTaskAccountWide(node)) then
        node.ownerCharKey = nil
        if TaskTracker.EnsureTaskOwnerCharKey and TaskTracker.GetCharProgressKey then
            TaskTracker.EnsureTaskOwnerCharKey(node, TaskTracker.GetCharProgressKey())
        end
    end
    local inserted = true
    if TaskTracker.InsertNodeAsLastChild then
        inserted = TaskTracker.InsertNodeAsLastChild("root", node) and true or false
    end
    if not inserted then
        TaskTracker._ttLiveShareApplying = nil
        return
    end
    if node.liveShareTwoWay == true then
        node.liveSharePeerAdded = tonumber(node.shareSelfAdded) or 0
        node.liveShareSelfAdded = 0
        node.liveShareSentCount = tonumber(node.taskCount) or 0
        node.liveShareCountEpoch = tonumber(node.shareCountEpoch) or 0
    end
    node.shareSelfAdded = nil
    node.shareCountEpoch = nil
    stampReceivedWeek(node, node.shareWeek)
    node.shareWeek = nil
    persistNode(node)
    TaskTracker._ttLiveShareApplying = nil
    if TaskTracker.InvalidateLiveShareIndex then TaskTracker.InvalidateLiveShareIndex() end
    if node.liveShareTwoWay == true then
        say("Got \"" .. (node.name or "a task") .. "\" from " .. sender .. ". You can move it, and you can add to the count. That syncs back. You can't lower it.")
    else
        say("Got \"" .. (node.name or "a task") .. "\" from " .. sender .. ". You can move it. The count follows them.")
    end
    refreshAfterShare()
end

local function acceptProgress(sender, shareId, rev, body)
    if hiddenProfile() then return end
    local node = findByShareId(shareId)
    if not node then return end
    local fromOwner = node.liveShareRole == "receiver" and sameWho(node.liveShareOwner, sender)
    local fromReceiver = node.liveShareRole == "owner" and node.liveShareTwoWay == true and sameWho(node.liveShareTo, sender)
    if not fromOwner and not fromReceiver then return end
    if fromReceiver and shareIsPerCharacter(node) then
        local key = node.liveShareCharKey
        if type(key) ~= "string" or key == "" or currentShareCharKey() ~= key then
            return
        end
    end
    rev = tonumber(rev) or 0
    if not TaskTracker.UnpackShareValue or not TaskTracker.ApplyTaskProgressSnapshot then return end
    local snap = TaskTracker.UnpackShareValue(body)
    if type(snap) ~= "table" or snap.kind ~= nil or snap.type ~= nil then return end
    local localRev = tonumber(node.liveShareRev) or 0
    local twoWay = node.liveShareTwoWay == true
    local incomingEpoch = tonumber(snap.shareCountEpoch)
    local localEpoch = tonumber(node.liveShareCountEpoch) or 0
    local peerAdded = tonumber(snap.shareSelfAdded)
    local seen = tonumber(node.liveSharePeerAdded) or 0
    local ownerReset = twoWay and incomingEpoch and incomingEpoch > localEpoch
    local sameEpoch = incomingEpoch == nil or incomingEpoch == localEpoch
    local newAdds = twoWay and peerAdded and peerAdded > seen and not ownerReset and sameEpoch
    if rev < localRev and not newAdds and not ownerReset then return end
    TaskTracker._ttLiveShareApplying = true
    if ownerReset then
        TaskTracker.ApplyTaskProgressSnapshot(node, snap)
        node.liveShareCountEpoch = incomingEpoch
        node.liveShareSelfAdded = 0
        node.liveSharePeerAdded = peerAdded or 0
        node.liveShareSentCount = tonumber(node.taskCount) or 0
    elseif twoWay and peerAdded ~= nil and sameEpoch then
        local cur = tonumber(node.taskCount) or 0
        local sent = tonumber(node.liveShareSentCount)
        if sent ~= nil and cur > sent then
            node.liveShareSelfAdded = (tonumber(node.liveShareSelfAdded) or 0) + (cur - sent)
            node._ttShareNeedsSend = true
        end
        local merged = cur
        if newAdds then
            merged = cur + (peerAdded - seen)
            node.liveSharePeerAdded = peerAdded
        end
        node.taskCount = merged
        local max = tonumber(node.taskMax)
        if max and max > 0 then
            node.done = merged >= max and true or false
        end
        node.liveShareSentCount = merged
        if incomingEpoch then node.liveShareCountEpoch = incomingEpoch end
    else
        TaskTracker.ApplyTaskProgressSnapshot(node, snap)
        node.liveShareSentCount = tonumber(node.taskCount) or 0
    end
    if rev > localRev then
        node.liveShareRev = rev
    end
    if fromOwner then
        stampReceivedWeek(node, snap.shareWeek)
    end
    rememberFlatShare(node)
    persistNode(node)
    TaskTracker._ttLiveShareApplying = nil
    if node._ttShareNeedsSend then
        node._ttShareNeedsSend = nil
        if node.liveShareId then lastSentSig[node.liveShareId] = nil end
    else
        markSent(node)
    end
    refreshAfterShare()
end

local function acceptStop(sender, shareId)
    local node = findByShareId(shareId)
    if not node or node.liveShareRole ~= "receiver" or not sameWho(node.liveShareOwner, sender) then return end
    local title = node.name or "Task"
    local id = node.id
    local dlg = TaskTracker._receivedTaskDialog
    if dlg and dlg.IsShown and dlg:IsShown() and dlg._nodeId == id then
        dlg:Hide()
    end
    say(sender .. " stopped sharing \"" .. title .. "\". It was removed from your list.")
    if id and TaskTracker.RemoveNode then
        TaskTracker.RemoveNode(id)
    else
        clearShareFields(node)
        refreshAfterShare()
    end
    if TaskTracker.InvalidateLiveShareIndex then
        TaskTracker.InvalidateLiveShareIndex()
    end
end

local function findParkedShare(shareId)
    if not shareId or not TaskTracker.WalkTree then return nil end
    local foundNode, foundKey
    TaskTracker.WalkTree(function(node)
        if foundNode or node.type ~= "task" then return end
        local map = node.liveShareByChar
        if type(map) ~= "table" then return end
        for key, slot in pairs(map) do
            if not foundNode and type(slot) == "table" and slot.id == shareId then
                foundNode = node
                foundKey = key
            end
        end
    end)
    return foundNode, foundKey
end

local function acceptRelease(sender, shareId)
    local node = findByShareId(shareId)
    if node and node.liveShareRole == "owner" and sameWho(node.liveShareTo, sender) then
        local title = node.name or "Task"
        dropShareSlot(node, node.liveShareCharKey)
        clearShareFields(node)
        TaskTracker.InvalidateLiveShareIndex()
        lastSentSig[shareId] = nil
        say(sender .. " removed \"" .. title .. "\" from their list.")
        return
    end
    local parked, key = findParkedShare(shareId)
    if not parked or type(key) ~= "string" then return end
    local slot = parked.liveShareByChar and parked.liveShareByChar[key]
    if type(slot) ~= "table" or not sameWho(slot.to, sender) then return end
    dropShareSlot(parked, key)
    lastSentSig[shareId] = nil
end

local function handleAsk(sender, shareId)
    local node = findByShareId(shareId)
    if not node or not sameWho(node.liveShareTo, sender) then return end
    if not ownerCanSend(node) then return end
    TaskTracker.SendLiveShareTask(node)
end

local function dropStalePartials()
    local now = GetTime and GetTime() or 0
    for key, buf in pairs(partials) do
        if type(buf) ~= "table" or (now - (buf.at or 0)) > 30 then
            partials[key] = nil
        end
    end
end

local function takeBody(sender, kind, shareId, rev, seq, total, frag)
    seq = tonumber(seq)
    total = tonumber(total)
    rev = tonumber(rev)
    if not seq or not total or not rev or seq < 1 or total < 1 or seq > total or total > 200 then return nil end
    if type(frag) ~= "string" then frag = "" end
    local key = sender:lower() .. "|" .. kind .. "|" .. shareId
    local buf = partials[key]
    if not buf or buf.total ~= total or buf.rev ~= rev then
        buf = { total = total, rev = rev, parts = {}, got = 0, at = GetTime and GetTime() or 0 }
        partials[key] = buf
    end
    if not buf.parts[seq] then
        buf.parts[seq] = frag
        buf.got = buf.got + 1
    end
    if buf.got < buf.total then return nil end
    local chunks = {}
    for i = 1, buf.total do
        if not buf.parts[i] then return nil end
        chunks[i] = buf.parts[i]
    end
    partials[key] = nil
    local body = table.concat(chunks)
    if #body > MAX_BODY then return nil end
    return body, rev
end

function TaskTracker.OnLiveShareAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    if channel ~= "WHISPER" then return end
    if type(message) ~= "string" or type(sender) ~= "string" or sender == "" then return end
    if issecretvalue and (issecretvalue(message) or issecretvalue(sender)) then return end
    dropStalePartials()
    local kind, shareId, a, b, c, frag = strsplit("|", message, 6)
    if type(shareId) ~= "string" or not shareId:match("^%x%x%x%x%x%x%x%x$") then return end
    if kind == "A" then
        handleAsk(sender, shareId)
        return
    elseif kind == "X" then
        acceptStop(sender, shareId)
        return
    elseif kind == "R" then
        acceptRelease(sender, shareId)
        return
    elseif kind ~= "T" and kind ~= "P" then
        return
    end
    local body, rev = takeBody(sender, kind, shareId, a, b, c, frag)
    if not body then return end
    if kind == "T" then
        acceptTask(sender, shareId, rev, body)
    else
        acceptProgress(sender, shareId, rev, body)
    end
end

function TaskTracker.BeginLiveShare(node, name, realm)
    if not TaskTracker.IsLiveShareEnabled() then return "Turn on Sync under Options, Advanced." end
    if hiddenProfile() then return "Sync is off for this profile." end
    if not node or node.type ~= "task" then return "Save the task first." end
    TaskTracker.ProjectLiveShareNode(node)
    if node.liveShareRole == "receiver" then
        return "This count follows " .. (node.liveShareOwner or "the other character") .. "."
    end
    if node.liveShareRole == "owner" and shareIsPerCharacter(node) then
        local key = node.liveShareCharKey
        if type(key) == "string" and key ~= "" and currentShareCharKey() ~= key then
            return TaskTracker.LiveShareCharStatus(node)
        end
    end
    name = trim(name or "")
    realm = trim(realm or "")
    if name == "" or realm == "" then return "Type a character name and server." end
    if name:find("%s") then return "Type the character name on its own. The server goes in the other box." end
    if charKeyMatches(name, realm) then
        return "Characters on this account already share your list. Sync is for a different account."
    end
    local target = whisperTarget(name, realm)
    if not target then return "Type a character name and server." end
    if not TaskTracker.ExportLiveShareTaskString then return "Sync isn't ready." end
    if node.liveShareTwoWay == true and node.liveShareRole ~= "receiver" and node.liveShareAddGen ~= SHARE_ADD_GEN then
        node.liveShareSelfAdded = 0
        node.liveSharePeerAdded = 0
        node.liveShareSentCount = tonumber(node.taskCount) or 0
        node.liveSharePersonal = nil
        if node.liveShareCountEpoch == nil then node.liveShareCountEpoch = 0 end
        node.liveShareAddGen = SHARE_ADD_GEN
    end
    local body = TaskTracker.ExportLiveShareTaskString(node)
    if type(body) ~= "string" or body == "" then return "Could not prepare this task." end
    if #body > MAX_BODY then return "This task is too big to sync." end
    local charErr = claimShareCharKey(node)
    if charErr then return charErr end
    if node.liveShareRole == "owner" and type(node.liveShareTo) == "string" and node.liveShareTo ~= "" and not sameWho(node.liveShareTo, target) then
        sendControl(node.liveShareTo, "X", node.liveShareId)
        lastSentSig[node.liveShareId] = nil
    end
    node.liveShareRole = "owner"
    node.liveShareOwner = nil
    node.liveShareTo = target
    node.liveShareRealm = realm
    if type(node.liveShareId) ~= "string" or not node.liveShareId:match("^%x%x%x%x%x%x%x%x$") then
        node.liveShareId = newShareId()
    end
    TaskTracker.InvalidateLiveShareIndex()
    local rev = nextRev(node)
    if not enqueueBody(target, "T", node.liveShareId, rev, body) then
        return "Could not send this task."
    end
    markSent(node)
    return nil
end

function TaskTracker.StopLiveShare(node)
    if not node or node.type ~= "task" then return end
    TaskTracker.ProjectLiveShareNode(node)
    if node.liveShareRole == "owner" and type(node.liveShareTo) == "string" and type(node.liveShareId) == "string" then
        sendControl(node.liveShareTo, "X", node.liveShareId)
        lastSentSig[node.liveShareId] = nil
    end
    dropShareSlot(node, node.liveShareCharKey)
    clearFlatOwnerFields(node)
    TaskTracker.InvalidateLiveShareIndex()
end

function TaskTracker.NotifyLiveShareRemoved(node)
    if not node then return end
    if node.type == "task" then
        if node.liveShareRole == "receiver" then
            if type(node.liveShareOwner) == "string" and type(node.liveShareId) == "string" then
                sendControl(node.liveShareOwner, "R", node.liveShareId)
            end
        else
            if node.liveShareRole == "owner" and type(node.liveShareTo) == "string" and type(node.liveShareId) == "string" then
                sendControl(node.liveShareTo, "X", node.liveShareId)
                lastSentSig[node.liveShareId] = nil
            end
            local map = node.liveShareByChar
            if type(map) == "table" then
                for _, slot in pairs(map) do
                    if type(slot) == "table" and type(slot.to) == "string" and type(slot.id) == "string" and slot.id ~= node.liveShareId then
                        sendControl(slot.to, "X", slot.id)
                        lastSentSig[slot.id] = nil
                    end
                end
            end
        end
    end
    local children = node.children
    if type(children) == "table" then
        for i = 1, #children do
            TaskTracker.NotifyLiveShareRemoved(children[i])
        end
    end
end

local function splitTarget(target)
    if type(target) ~= "string" then return "", "" end
    local name, realm = target:match("^([^%-]+)%-(.+)$")
    return name or target, realm or ""
end

function TaskTracker.LiveShareStatus(node)
    if not node or node.type ~= "task" then
        return { mode = "none" }
    end
    if node.liveShareRole == "receiver" then
        local name, realm = splitTarget(node.liveShareOwner)
        if type(node.liveShareRealm) == "string" and node.liveShareRealm ~= "" then
            realm = node.liveShareRealm
        else
            realm = prettyRealm(realm)
        end
        return {
            mode = "receiver",
            name = name,
            realm = realm,
            who = node.liveShareOwner or "",
            twoWay = node.liveShareTwoWay == true,
        }
    end
    if node.liveShareRole == "owner" and type(node.liveShareTo) == "string" and node.liveShareTo ~= "" then
        local name, realm = splitTarget(node.liveShareTo)
        if type(node.liveShareRealm) == "string" and node.liveShareRealm ~= "" then
            realm = node.liveShareRealm
        else
            realm = prettyRealm(realm)
        end
        return {
            mode = "owner",
            name = name,
            realm = realm,
            who = node.liveShareTo,
            twoWay = node.liveShareTwoWay == true,
        }
    end
    return { mode = "none" }
end

--- Profile key liveShareOwnerName. Missing stays "task".
function TaskTracker.GetLiveShareOwnerNameMode()
    local mode = TaskTrackerDB and TaskTrackerDB.liveShareOwnerName
    if mode == "tooltip" or mode == "none" then return mode end
    return "task"
end

local function plainShareName(text)
    if type(text) ~= "string" or text == "" then return nil end
    text = text:gsub("|", "")
    if text == "" then return nil end
    return text
end

local function liveShareNameBits(node)
    local info = TaskTracker.LiveShareStatus(node)
    if not info or info.mode == "none" then return nil end
    local name = plainShareName(info.name)
    if not name then return nil end
    return info.mode, name, plainShareName(info.realm)
end

--- Gray suffix on the task title. Empty unless the mode is "task".
function TaskTracker.GetLiveShareOwnerNameTag(node)
    if TaskTracker.GetLiveShareOwnerNameMode() ~= "task" then return "" end
    local mode, name = liveShareNameBits(node)
    if not name then return "" end
    if mode == "owner" then
        return " |cffaaaaaa(to " .. name .. ")|r"
    end
    return " |cffaaaaaa(" .. name .. ")|r"
end

--- One tooltip line. Nil unless the mode is "tooltip".
function TaskTracker.GetLiveShareOwnerTooltipLine(node)
    if TaskTracker.GetLiveShareOwnerNameMode() ~= "tooltip" then return nil end
    local mode, name, realm = liveShareNameBits(node)
    if not name then return nil end
    local who = realm and (name .. " on " .. realm) or name
    if mode == "owner" then
        return "Synced to " .. who
    end
    return "Owner: " .. who
end

local function pushAllLiveShares()
    if hiddenProfile() or not TaskTracker.WalkTree then return 0 end
    local sent = 0
    TaskTracker.WalkTree(function(node)
        if node.type ~= "task" then return end
        if ownerCanSend(node) then
            local err = TaskTracker.SendLiveShareTask(node)
            if not err then
                sent = sent + 1
            elseif err == "This task is too big to sync." then
                say(err)
            end
        elseif node.liveShareRole == "receiver" and type(node.liveShareOwner) == "string" and type(node.liveShareId) == "string"
            and (not TaskTracker.IsTaskVisibleForCurrentChar or TaskTracker.IsTaskVisibleForCurrentChar(node)) then
            sendControl(node.liveShareOwner, "A", node.liveShareId)
            sent = sent + 1
        end
    end)
    return sent
end

function TaskTracker.SendLiveShareOnLogin()
    TaskTracker._ttLiveShareReady = true
    TaskTracker.RegisterLiveSharePrefix()
    TaskTracker.InvalidateLiveShareIndex()
    pushAllLiveShares()
end

function TaskTracker.ForceLiveShareAll()
    if hiddenProfile() then return end
    if TaskTracker.ProjectLiveSharesForCurrentChar then
        TaskTracker.ProjectLiveSharesForCurrentChar()
    end
    TaskTracker._ttLiveShareReady = true
    if TaskTracker.RegisterLiveSharePrefix then
        TaskTracker.RegisterLiveSharePrefix()
    end
    local sent = pushAllLiveShares()
    if sent == 0 then
        say("No shared tasks to send from this character.")
    elseif sent == 1 then
        say("Sent 1 shared task.")
    else
        say("Sent " .. sent .. " shared tasks.")
    end
end
