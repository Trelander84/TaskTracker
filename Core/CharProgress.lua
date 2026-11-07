-- Core/CharProgress.lua
-- Per-character progress for user tasks (account-wide tasks keep progress on the node).

TaskTracker = TaskTracker or {}

function TaskTracker.SanitizeCollectableRitualKills(adv)
    if type(adv) ~= "table" then return end
    local r = tonumber(adv.collectableRitualKills)
    if r == nil then return end
    r = math.max(0, math.floor(r))
    if r > 0 then
        adv.collectableAutoCount = math.max(0, tonumber(adv.collectableAutoCount) or 0) + r
    end
    adv.collectableRitualKills = nil
end

local PENDING_CHAR_KEY = "_pending"

local TASK_FIELDS = { "done", "taskCount", "taskUserValue", "doneOverride" }

local ADV_STATE_KEYS = {
    "goldAutoCopper",
    "itemAutoCount",
    "weekStartAchTotal",
    "weekStartRepValue",
    "questWeekStartComplete",
    "questPeriodCredited",
    "questPeriodOrphanCredits",
    "questPeriodBaseline",
    "questPeriodTurnIns",
    "questPeriodRepeatCounts",
    "questPeriodBaselineFrozen",
    "mobAutoCount",
    "collectableInit",
    "collectableAutoCount",
    "collectableFishAttempts",
    "collectableRitualKills",
}

function TaskTracker.IsTaskAccountWide(node)
    return node and node.type == "task" and node.accountWide == true
end

local function shouldPersistCharTaskProgress(node, charKey)
    if not node or node.type ~= "task" or TaskTracker.IsTaskAccountWide(node) or not node.id then
        return false
    end
    if node.showOnOtherCharacters == true then return true end
    local owner = node.ownerCharKey
    return owner == charKey or not owner or owner == ""
end

--- Apply progress scope + alt visibility from the task dialog.
function TaskTracker.ApplyTaskScopeFieldsToNode(node, accountWide, showOnOtherCharacters)
    if not node or node.type ~= "task" then return end
    if accountWide then
        node.accountWide = true
        node.showOnOtherCharacters = nil
        node.ownerCharKey = nil
        return
    end
    node.accountWide = nil
    if showOnOtherCharacters == true then
        node.showOnOtherCharacters = true
    else
        node.showOnOtherCharacters = nil
    end
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if key then
        TaskTracker.EnsureTaskOwnerCharKey(node, key)
    end
end

function TaskTracker.EnsureTaskOwnerCharKey(node, charKey)
    if not node or node.type ~= "task" or TaskTracker.IsTaskAccountWide(node) then return end
    if type(charKey) ~= "string" or charKey == "" then return end
    if type(node.ownerCharKey) == "string" and node.ownerCharKey ~= "" then return end
    node.ownerCharKey = charKey
end

local function computeCharProgressKey()
    local name, realm = UnitFullName("player")
    -- A secret name cannot be a table key. Treat it as not ready and try again.
    if name and issecretvalue and issecretvalue(name) then return nil end
    if realm and issecretvalue and issecretvalue(realm) then return nil end
    if type(name) ~= "string" or name == "" or type(realm) ~= "string" or realm == "" then
        return nil
    end
    return realm .. "::" .. name
end

function TaskTracker.GetCharProgressKey()
    local cached = TaskTracker._activeCharProgressKey
    if cached and cached ~= "" then
        return cached
    end
    return computeCharProgressKey()
end

local function charProgressRoot()
    local db = TaskTrackerDB
    if not db then return nil end
    if type(db.charTaskProgress) ~= "table" then
        db.charTaskProgress = {}
    end
    return db.charTaskProgress
end

local function charBucket(charKey)
    local root = charProgressRoot()
    if not root or not charKey then return nil end
    if type(root[charKey]) ~= "table" then
        root[charKey] = {}
    end
    return root[charKey]
end

local function charBucketExisting(charKey)
    local db = TaskTrackerDB
    local root = db and db.charTaskProgress
    if type(root) ~= "table" or not charKey then return nil end
    local b = root[charKey]
    if type(b) == "table" then return b end
    return nil
end

local function stampBucketSeen(bucket)
    if type(bucket) ~= "table" then return end
    if GetServerTime then
        bucket._lastSeen = GetServerTime()
    end
end

local function taskNodesById()
    local map = {}
    if not TaskTracker.WalkTree then return map end
    TaskTracker.WalkTree(function(node)
        if node.type == "task" and node.id then
            map[node.id] = node
        end
    end)
    return map
end

local function periodMatches(node, kind)
    if not node or node.type ~= "task" or TaskTracker.IsTaskAccountWide(node) then
        return false
    end
    if node.reset == kind then return true end
    if type(node.advanced) == "table" and node.advanced.type == "gold" and TaskTracker.GetAdvancedEffectiveReset then
        return TaskTracker.GetAdvancedEffectiveReset(node) == kind
    end
    return false
end

-- Same decision as LiveShareHoldsWeeklyReset, without writing the shared node.
local function snapshotHoldsWeekly(node, weeklyReset)
    if not node or node.liveShareRole ~= "receiver" or node.reset ~= "weekly" then
        return false
    end
    weeklyReset = tonumber(weeklyReset)
    if not weeklyReset or weeklyReset <= 0 then return false end
    local stamped = tonumber(node.liveSharePeriod)
    return not stamped or stamped >= weeklyReset
end

local function clearSnapPeriod(snap, node)
    if type(snap) ~= "table" then return end
    snap.done = false
    snap.taskCount = 0
    snap.taskUserValue = nil
    snap.doneOverride = nil
    if type(node.subtext) == "table" and node.subtext.type == "gold" and node.subtext.useTask ~= true then
        snap.subtextGoldCopper = 0
    end
    local at = type(node.advanced) == "table" and node.advanced.type or nil
    local a = snap.advanced
    if type(a) == "table" and at then
        if at == "gold" then
            a.goldAutoCopper = 0
        elseif at == "achievement" then
            a.weekStartAchTotal = nil
        elseif at == "reputation" then
            a.weekStartRepValue = nil
        elseif at == "item" then
            a.itemAutoCount = 0
        elseif at == "quest" then
            a.questWeekStartComplete = nil
            a.questPeriodCredited = nil
            a.questPeriodOrphanCredits = nil
            a.questPeriodTurnIns = nil
            a.questPeriodRepeatCounts = nil
            a.questPeriodBaseline = nil
            a.questPeriodBaselineFrozen = nil
        elseif at == "mob_kill" then
            a.mobAutoCount = 0
        elseif at == "collectable" then
            a.collectableInit = nil
            a.collectableCredited = nil
            a.collectableAutoCount = 0
            a.collectableFishAttempts = 0
        end
        if not next(a) then snap.advanced = nil end
    end
    if type(snap.extraGoals) == "table" and type(node.extraGoals) == "table" then
        for i, gs in ipairs(snap.extraGoals) do
            local g = node.extraGoals[i]
            if type(gs) == "table" and type(g) == "table" then
                clearSnapPeriod(gs, { type = "task", advanced = g.advanced, reset = node.reset })
            end
        end
    end
end

local function snapWasOpen(snap)
    if type(snap) ~= "table" then return false end
    if snap.done then return true end
    if (tonumber(snap.taskCount) or 0) > 0 then return true end
    if snap.taskUserValue ~= nil or snap.doneOverride ~= nil then return true end
    local a = snap.advanced
    if type(a) == "table" and type(a.questPeriodCredited) == "table" and next(a.questPeriodCredited) then
        return true
    end
    return false
end

--- Clear saved per-character progress for a daily or weekly reset.
--- onlyCharKey limits the walk to one character (a later login that missed the reset).
--- questOnly limits a first-time catch-up to quest tasks, which the game can fill back in.
function TaskTracker.ResetStoredCharTaskPeriod(kind, periodStamp, reason, onlyCharKey, questOnly)
    local root = charProgressRoot()
    if not root or (kind ~= "weekly" and kind ~= "daily") then return end
    local nodes = taskNodesById()
    for charKey, bucket in pairs(root) do
        if charKey ~= PENDING_CHAR_KEY and type(bucket) == "table" and (not onlyCharKey or charKey == onlyCharKey) then
            for tid, snap in pairs(bucket) do
                if type(tid) == "string" and tid:sub(1, 1) ~= "_" and type(snap) == "table" then
                    local node = nodes[tid]
                    local hold = kind == "weekly" and snapshotHoldsWeekly(node, periodStamp)
                    local questTask = type(node) == "table" and type(node.advanced) == "table" and node.advanced.type == "quest"
                    if node and not hold and periodMatches(node, kind) and (not questOnly or questTask) and snapWasOpen(snap) then
                        clearSnapPeriod(snap, node)
                    end
                end
            end
            if kind == "weekly" then
                bucket._weekReset = periodStamp
            else
                bucket._dayReset = periodStamp
            end
        end
    end
end

function TaskTracker.CatchUpCharTaskPeriod(charKey)
    if not charKey or not TaskTracker.GetResetTimes then return end
    local bucket = charBucketExisting(charKey)
    if not bucket then return end
    local dailyReset, weeklyReset = TaskTracker.GetResetTimes()
    if tonumber(bucket._weekReset) ~= tonumber(weeklyReset) then
        local first = bucket._weekReset == nil
        TaskTracker.ResetStoredCharTaskPeriod("weekly", weeklyReset, "load", charKey, first)
    end
    if tonumber(bucket._dayReset) ~= tonumber(dailyReset) then
        local first = bucket._dayReset == nil
        TaskTracker.ResetStoredCharTaskPeriod("daily", dailyReset, "load", charKey, first)
    end
end

local function taskHasAnyCharProgress(taskId)
    local db = TaskTrackerDB
    local root = db and db.charTaskProgress
    if type(root) ~= "table" or not taskId then return false end
    for ck, bucket in pairs(root) do
        if ck ~= PENDING_CHAR_KEY and type(bucket) == "table" and type(bucket[taskId]) == "table" then
            return true
        end
    end
    return false
end

--- Character-scoped tasks: visible on all characters when `showOnOtherCharacters`, else owner only.
--- Pure: does not stamp owner or create SavedVariables buckets (see OnCharacterEnter).
function TaskTracker.IsTaskVisibleForChar(node, charKey)
    if not node or node.type ~= "task" then return true end
    if TaskTracker.IsTaskAccountWide(node) then return true end
    if node.showOnOtherCharacters == true then return true end
    if not charKey then return false end
    local owner = node.ownerCharKey
    if type(owner) == "string" and owner ~= "" then
        return owner == charKey
    end
    local bucket = charBucketExisting(charKey)
    if bucket and node.id and type(bucket[node.id]) == "table" then
        return true
    end
    if node.id and not taskHasAnyCharProgress(node.id) then
        return true
    end
    return false
end

function TaskTracker.IsTaskVisibleForCurrentChar(node)
    return TaskTracker.IsTaskVisibleForChar(node, TaskTracker.GetCharProgressKey())
end

local function snapshotAdvancedState(adv)
    if type(adv) ~= "table" then return nil end
    local st = {}
    for _, k in ipairs(ADV_STATE_KEYS) do
        local v = adv[k]
        if v ~= nil then
            if (k == "collectableCredited" or k == "questPeriodCredited" or k == "questPeriodBaseline" or k == "questPeriodTurnIns" or k == "questPeriodRepeatCounts") and type(v) == "table" then
                st[k] = TaskTracker.DeepCopy(v)
            else
                st[k] = v
            end
        end
    end
    if next(st) == nil then return nil end
    return st
end

local function applyAdvancedState(adv, st)
    if type(adv) ~= "table" or type(st) ~= "table" then return end
    for _, k in ipairs(ADV_STATE_KEYS) do
        local v = st[k]
        if v == nil then
            adv[k] = nil
        elseif (k == "collectableCredited" or k == "questPeriodCredited" or k == "questPeriodBaseline" or k == "questPeriodTurnIns" or k == "questPeriodRepeatCounts") and type(v) == "table" then
            adv[k] = TaskTracker.DeepCopy(v)
        else
            adv[k] = v
        end
    end
    if TaskTracker.SanitizeCollectableRitualKills then
        TaskTracker.SanitizeCollectableRitualKills(adv)
    end
end

function TaskTracker.SnapshotTaskProgress(node)
    if not node or node.type ~= "task" then return nil end
    local snap = {}
    for _, k in ipairs(TASK_FIELDS) do
        snap[k] = node[k]
    end
    if type(node.advanced) == "table" then
        local ast = snapshotAdvancedState(node.advanced)
        if ast then snap.advanced = ast end
    end
    if type(node.subtext) == "table" then
        if node.subtext.lifetimeKills ~= nil then
            snap.subtextLifetimeKills = node.subtext.lifetimeKills
        end
        if node.subtext.goldPeriodCopper ~= nil then
            snap.subtextGoldCopper = node.subtext.goldPeriodCopper
        end
    end
    if type(node.extraGoals) == "table" and #node.extraGoals > 0 then
        local eg = {}
        for i, g in ipairs(node.extraGoals) do
            local gs = {}
            for _, k in ipairs(TASK_FIELDS) do
                gs[k] = g[k]
            end
            if type(g.advanced) == "table" then
                local ast = snapshotAdvancedState(g.advanced)
                if ast then gs.advanced = ast end
            end
            eg[i] = gs
        end
        snap.extraGoals = eg
    end
    return snap
end

--- Stamp creator ownership and an empty progress snapshot so character tasks survive /reload.
function TaskTracker.EnsureNewTaskCharOwnership(node)
    if not node or node.type ~= "task" or TaskTracker.IsTaskAccountWide(node) then return end
    local key = TaskTracker.GetCharProgressKey()
    if not key then return end
    TaskTracker.EnsureTaskOwnerCharKey(node, key)
    local bucket = charBucket(key)
    if bucket and node.id and bucket[node.id] == nil then
        bucket[node.id] = TaskTracker.SnapshotTaskProgress(node)
    end
end

local function snapHasProgress(snap)
    if type(snap) ~= "table" then return false end
    if snap.done then return true end
    if (tonumber(snap.taskCount) or 0) > 0 then return true end
    if snap.taskUserValue ~= nil then return true end
    if snap.doneOverride ~= nil then return true end
    if type(snap.advanced) == "table" and next(snap.advanced) ~= nil then return true end
    if type(snap.extraGoals) == "table" then
        for i = 1, #snap.extraGoals do
            if snapHasProgress(snap.extraGoals[i]) then return true end
        end
    end
    return false
end

function TaskTracker.ClearTaskProgressOnNode(node)
    if not node or node.type ~= "task" then return end
    node.done = false
    node.taskCount = 0
    node.taskUserValue = nil
    node.doneOverride = nil
    if type(node.advanced) == "table" then
        applyAdvancedState(node.advanced, {})
        for _, k in ipairs(ADV_STATE_KEYS) do
            node.advanced[k] = nil
        end
    end
    if TaskTracker._advancedRuntime and node.id then
        TaskTracker._advancedRuntime[node.id] = nil
        for i = 1, 3 do
            TaskTracker._advancedRuntime[tostring(node.id) .. ":" .. tostring(i)] = nil
        end
    end
    if type(node.extraGoals) == "table" then
        for _, g in ipairs(node.extraGoals) do
            g.done = false
            g.taskCount = 0
            g.taskUserValue = nil
            g.doneOverride = nil
            if type(g.advanced) == "table" then
                applyAdvancedState(g.advanced, {})
                for _, k in ipairs(ADV_STATE_KEYS) do
                    g.advanced[k] = nil
                end
            end
        end
    end
    if type(node.subtext) == "table" then
        node.subtext.lifetimeKills = 0
        node.subtext.goldPeriodCopper = 0
    end
end

function TaskTracker.ApplyTaskProgressSnapshot(node, snap)
    if not node or node.type ~= "task" then return end
    TaskTracker.ClearTaskProgressOnNode(node)
    if type(snap) ~= "table" then return end
    for _, k in ipairs(TASK_FIELDS) do
        if snap[k] ~= nil then
            node[k] = snap[k]
        end
    end
    if type(node.advanced) == "table" and type(snap.advanced) == "table" then
        applyAdvancedState(node.advanced, snap.advanced)
    end
    if type(node.subtext) == "table" then
        if snap.subtextLifetimeKills ~= nil then
            node.subtext.lifetimeKills = snap.subtextLifetimeKills
        end
        if snap.subtextGoldCopper ~= nil then
            node.subtext.goldPeriodCopper = snap.subtextGoldCopper
        end
    end
    if type(node.extraGoals) == "table" and type(snap.extraGoals) == "table" then
        for i, g in ipairs(node.extraGoals) do
            local gs = snap.extraGoals[i]
            if type(gs) == "table" then
                for _, k in ipairs(TASK_FIELDS) do
                    if gs[k] ~= nil then g[k] = gs[k] end
                end
                if type(g.advanced) == "table" and type(gs.advanced) == "table" then
                    applyAdvancedState(g.advanced, gs.advanced)
                end
            end
        end
    end
end

function TaskTracker.PersistCharTaskProgress(charKey)
    if TaskTracker.HiddenProfileIsLoaded and TaskTracker.HiddenProfileIsLoaded() then return end
    if not charKey then return end
    local bucket = charBucket(charKey)
    if not bucket or not TaskTracker.WalkTree then return end
    TaskTracker.WalkTree(function(node)
        if shouldPersistCharTaskProgress(node, charKey) then
            TaskTracker.EnsureTaskOwnerCharKey(node, charKey)
            bucket[node.id] = TaskTracker.SnapshotTaskProgress(node)
        end
    end)
    stampBucketSeen(bucket)
    if TaskTracker.SnapshotCharWallet then
        TaskTracker.SnapshotCharWallet(charKey)
    end
end

function TaskTracker.PersistOneCharTaskProgress(node)
    if TaskTracker.HiddenProfileIsLoaded and TaskTracker.HiddenProfileIsLoaded() then return end
    local charKey = TaskTracker.GetCharProgressKey()
    if not charKey or not shouldPersistCharTaskProgress(node, charKey) then return end
    local bucket = charBucket(charKey)
    if not bucket or not node.id then return end
    TaskTracker.EnsureTaskOwnerCharKey(node, charKey)
    bucket[node.id] = TaskTracker.SnapshotTaskProgress(node)
    stampBucketSeen(bucket)
end

function TaskTracker.ClearCharScopedProgressFromNodes()
    if not TaskTracker.WalkTree then return end
    TaskTracker.WalkTree(function(node)
        if node.type == "task" and not TaskTracker.IsTaskAccountWide(node) then
            TaskTracker.ClearTaskProgressOnNode(node)
        end
    end)
end

function TaskTracker.RestoreHeldShareCount(node)
    if not node or node.liveShareRole ~= "receiver" then return false end
    local sent = tonumber(node.liveShareSentCount)
    local cur = tonumber(node.taskCount) or 0
    if not sent or sent <= 0 or sent <= cur then return false end
    local rst = node.reset or "none"
    if rst == "weekly" then
        if not TaskTracker.GetResetTimes then return false end
        local _, week = TaskTracker.GetResetTimes()
        week = tonumber(week)
        local stamped = tonumber(node.liveSharePeriod)
        if not week or week <= 0 or not stamped or stamped < week then return false end
    elseif rst ~= "none" then
        return false
    end
    node.taskCount = sent
    local max = tonumber(node.taskMax)
    if max and max > 0 and sent >= max then
        node.done = true
    end
    return true
end

function TaskTracker.LoadCharTaskProgress(charKey)
    if TaskTracker.HiddenProfileIsLoaded and TaskTracker.HiddenProfileIsLoaded() then return end
    if not charKey or not TaskTracker.WalkTree then return end
    local root = charProgressRoot()
    local bucket = charBucket(charKey)
    local pending = root and root[PENDING_CHAR_KEY]
    TaskTracker.CatchUpCharTaskPeriod(charKey)

    TaskTracker.WalkTree(function(node)
        if node.type ~= "task" or TaskTracker.IsTaskAccountWide(node) or not node.id then
            return
        end
        local snap = bucket[node.id]
        if not snap and pending and type(pending[node.id]) == "table" then
            snap = pending[node.id]
            bucket[node.id] = TaskTracker.DeepCopy(snap)
            TaskTracker.EnsureTaskOwnerCharKey(node, charKey)
        end
        if snap and (not node.ownerCharKey or node.ownerCharKey == "") then
            TaskTracker.EnsureTaskOwnerCharKey(node, charKey)
        end
        if not snap and TaskTracker.SnapshotTaskProgress then
            local onNode = TaskTracker.SnapshotTaskProgress(node)
            -- The saved node is whoever played last. Adopt it only when no character has a snapshot yet.
            if snapHasProgress(onNode) and not taskHasAnyCharProgress(node.id) then
                bucket[node.id] = onNode
                snap = onNode
            end
        end
        if type(snap) == "table" then
            TaskTracker.ApplyTaskProgressSnapshot(node, snap)
        else
            TaskTracker.ClearTaskProgressOnNode(node)
            if not node.ownerCharKey or node.ownerCharKey == "" then
                TaskTracker.EnsureTaskOwnerCharKey(node, charKey)
            end
            bucket[node.id] = TaskTracker.SnapshotTaskProgress(node)
        end
        if TaskTracker.RestoreHeldShareCount(node) then
            bucket[node.id] = TaskTracker.SnapshotTaskProgress(node)
        end
    end)

    if pending then
        root[PENDING_CHAR_KEY] = nil
    end
    TaskTracker._ttCharProgressLoaded = true
end

function TaskTracker.PersistActiveCharTaskProgress()
    local key = TaskTracker._activeCharProgressKey
    if key then
        TaskTracker.PersistCharTaskProgress(key)
    end
end

local function collectTaskIdsFromNode(node, into)
    if not node then return end
    if node.type == "task" and node.id then
        into[node.id] = true
    end
    for _, ch in ipairs(node.children or {}) do
        collectTaskIdsFromNode(ch, into)
    end
end

function TaskTracker.PruneCharProgressForRemovedNode(node)
    local ids = {}
    collectTaskIdsFromNode(node, ids)
    if not next(ids) then return end
    local db = TaskTrackerDB
    local root = db and db.charTaskProgress
    if type(root) ~= "table" then return end
    for _, bucket in pairs(root) do
        if type(bucket) == "table" then
            for tid in pairs(ids) do
                bucket[tid] = nil
            end
        end
    end
end

function TaskTracker.PruneOrphanedCharProgress()
    if TaskTracker.HiddenProfileIsLoaded and TaskTracker.HiddenProfileIsLoaded() then return end
    if not TaskTracker.WalkTree then return end
    local db = TaskTrackerDB
    local root = db and db.charTaskProgress
    if type(root) ~= "table" then return end
    local live = {}
    TaskTracker.WalkTree(function(node)
        if node.type == "task" and node.id then
            live[node.id] = true
        end
    end)
    for _, bucket in pairs(root) do
        if type(bucket) == "table" then
            for tid, snap in pairs(bucket) do
                if tid ~= "_lastSeen" and type(snap) == "table" and not live[tid] then
                    bucket[tid] = nil
                end
            end
        end
    end
end

--- Persist character-scoped task progress after a count/checkbox change (account-wide stays on the node).
function TaskTracker.NotifyTaskProgressChanged(node)
    if not node or node.type ~= "task" or TaskTracker.IsTaskAccountWide(node) then
        return
    end
    if TaskTracker.PersistOneCharTaskProgress then
        TaskTracker.PersistOneCharTaskProgress(node)
    end
end

-- ─────────────────────────────────────
-- Module and Power list on/off live on the loaded profile (moduleVisibility).
-- Progress stays account-wide in registryState. charRegistryVisibility is only
-- the pre-profile map used by MigrateProfiles.
-- ─────────────────────────────────────
local function charRegistryVisibilityRoot()
    local db = TaskTrackerDB
    if not db then return nil end
    if type(db.charRegistryVisibility) ~= "table" then
        db.charRegistryVisibility = {}
    end
    return db.charRegistryVisibility
end

local function charRegistryVisibilityBucket(charKey)
    local root = charRegistryVisibilityRoot()
    if not root or not charKey then return nil end
    if type(root[charKey]) ~= "table" then
        root[charKey] = {}
    end
    return root[charKey]
end

--- Seed this character's module toggles from legacy account-wide registryState on first login.
function TaskTracker.EnsureCharRegistryVisibility(charKey)
    if not charKey then return end
    local root = charRegistryVisibilityRoot()
    if not root or type(root[charKey]) == "table" then return end

    local bucket = {}
    local db = TaskTrackerDB
    if db and db.registryState and TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady() then
        for _, entry in ipairs(TaskTracker.Registry) do
            local st = db.registryState[entry.id]
            if st then
                local row = {}
                if st.enabled == false then
                    row.enabled = false
                end
                if st.powerListEnabled == false then
                    row.powerListEnabled = false
                end
                if next(row) then
                    bucket[entry.id] = row
                end
            end
        end
    end
    root[charKey] = bucket
end

local function moduleVisibilityRoot()
    local db = TaskTrackerDB
    if not db then return nil end
    if type(db.moduleVisibility) ~= "table" then
        db.moduleVisibility = {}
    end
    return db.moduleVisibility
end

--- field: "enabled" (home expansion / Modules) or "powerListEnabled" (Power list mirror).
function TaskTracker.GetCharRegistryVisEnabled(entryID, field)
    local vis = moduleVisibilityRoot()
    local row = vis and vis[entryID]
    if row and row[field] == false then
        return false
    end
    return true
end

--- Record registry ids this profile has already seen. A later id follows enableNewModules.
--- The first pass only records what is already installed, so current rows stay put.
function TaskTracker.ApplyNewModuleDefaults()
    local db = TaskTrackerDB
    if not db then return end
    if not (TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady()) then return end
    local registry = TaskTracker.Registry
    if type(registry) ~= "table" then return end
    if db.enableNewModules == nil then
        db.enableNewModules = false
    end
    local known = db.knownModuleIds
    local first = type(known) ~= "table"
    if first then
        known = {}
        db.knownModuleIds = known
    end
    local live = {}
    local turnOff = (not first) and db.enableNewModules ~= true
    for i = 1, #registry do
        local entry = registry[i]
        local id = entry and entry.id
        if type(id) == "string" and id ~= "" then
            live[id] = true
            if not known[id] then
                known[id] = true
                if turnOff and TaskTracker.SetCharRegistryVisEnabled then
                    TaskTracker.SetCharRegistryVisEnabled(id, "enabled", false)
                    TaskTracker.SetCharRegistryVisEnabled(id, "powerListEnabled", false)
                end
            end
        end
    end
    for id in pairs(known) do
        if not live[id] then
            known[id] = nil
        end
    end
end

function TaskTracker.SetCharRegistryVisEnabled(entryID, field, enabled)
    if not entryID or not field then return end
    local bucket = moduleVisibilityRoot()
    if not bucket then return end

    if enabled then
        local row = bucket[entryID]
        if row then
            row[field] = nil
            -- nil means on. false is an explicit off for the other list, so keep the row.
            if row.enabled ~= false and row.powerListEnabled ~= false and not row.showCollected then
                bucket[entryID] = nil
            end
        end
    else
        if not bucket[entryID] then
            bucket[entryID] = {}
        end
        bucket[entryID][field] = false
    end
end

function TaskTracker.IsCollectionsShowCollectedOverride(entryID)
    if not entryID then return false end
    local vis = moduleVisibilityRoot()
    local row = vis and vis[entryID]
    return row and row.showCollected == true
end

function TaskTracker.SetCollectionsShowCollectedOverride(entryID, on)
    if not entryID then return end
    local bucket = moduleVisibilityRoot()
    if not bucket then return end
    if on then
        if not bucket[entryID] then
            bucket[entryID] = {}
        end
        bucket[entryID].showCollected = true
    else
        local row = bucket[entryID]
        if row then
            row.showCollected = nil
            if row.enabled ~= false and row.powerListEnabled ~= false then
                bucket[entryID] = nil
            end
        end
    end
end

--- One-shot for the old debug preview. That overlay is a hidden profile now.
local function restoreGroupExpanded(tree, flags)
    if not tree or type(flags) ~= "table" or not TaskTracker.WalkTree then return end
    TaskTracker.WalkTree(function(node)
        if node.type == "group" and node.id and flags[node.id] ~= nil then
            node.expanded = flags[node.id]
        end
    end, tree)
end

local function restoreStaleNewUserPreview()
    local db = TaskTrackerDB
    local snap = db and db.debugNewUserPreview
    if type(snap) ~= "table" or type(snap.charKey) ~= "string" or snap.charKey == "" then
        return
    end
    local vis = snap.visibility
    if type(vis) == "table" and TaskTracker.DeepCopy then
        db.moduleVisibility = TaskTracker.DeepCopy(vis)
    else
        db.moduleVisibility = {}
    end
    db.debugNewUserPreview = nil
    if snap.addedWelcomeGroup and TaskTracker.RemoveNode then
        TaskTracker.RemoveNode("welcome_tasks", { skipRefresh = true })
    end
    restoreGroupExpanded(db.tree, snap.expanded)
    if type(snap.patchListViewExpanded) == "table" and TaskTracker.DeepCopy then
        db.patchListViewExpanded = TaskTracker.DeepCopy(snap.patchListViewExpanded)
    end
    db.readyToBuyEnabled = snap.readyToBuyEnabled ~= false
    db.worldQuestHuntEnabled = snap.worldQuestHuntEnabled ~= false
    if snap.iconSet == "classic" or snap.iconSet == "tintable" then
        db.iconSet = snap.iconSet
    end
    if type(snap.theme) == "string" and snap.theme ~= "" then
        db.theme = snap.theme
    end
    if TaskTracker.ApplyTheme then
        TaskTracker.ApplyTheme()
    end
    if TaskTracker.SaveActiveProfile then
        TaskTracker.SaveActiveProfile()
    end
    print("|cff00ff00TaskTracker|r The new-install preview is off. Your profile is back.")
end

local charEnterRetries = 0

function TaskTracker.OnCharacterEnter(allowRetry)
    local key = computeCharProgressKey()
    if not key then
        -- ADDON_LOADED is often before the name exists, and that call does not retry.
        -- The in-world call retries, because a secret name cannot be stored yet.
        if allowRetry and charEnterRetries < 20 and C_Timer and C_Timer.After then
            charEnterRetries = charEnterRetries + 1
            C_Timer.After(0.5, function()
                TaskTracker.OnCharacterEnter(true)
            end)
        end
        return
    end
    charEnterRetries = 0
    local prev = TaskTracker._activeCharProgressKey
    local charChanged = prev and prev ~= key
    if charChanged then
        TaskTracker.PersistCharTaskProgress(prev)
    end
    TaskTracker._activeCharProgressKey = key
    if TaskTracker.ActivateProfileForCharacter then
        TaskTracker.ActivateProfileForCharacter(key)
    end
    restoreStaleNewUserPreview()
    TaskTracker.EnsureCharRegistryVisibility(key)
    if charChanged then
        TaskTracker.ClearCharScopedProgressFromNodes()
        TaskTracker.LoadCharTaskProgress(key)
    elseif not prev then
        TaskTracker.LoadCharTaskProgress(key)
    end
    TaskTracker._activeCharProgressKey = key
    if TaskTracker.StampCharMetaIdentity then
        TaskTracker.StampCharMetaIdentity(key)
    end
    if TaskTracker.SnapshotCharWallet then
        TaskTracker.SnapshotCharWallet(key)
    end
    if TaskTracker.RequestCharWalletSnapshot then
        TaskTracker.RequestCharWalletSnapshot()
    end
    if TaskTracker.WalkTree then
        TaskTracker.WalkTree(function(node)
            if node.type ~= "task" or TaskTracker.IsTaskAccountWide(node) then return end
            if type(node.ownerCharKey) == "string" and node.ownerCharKey ~= "" then return end
            local bucket = charBucketExisting(key)
            if bucket and node.id and type(bucket[node.id]) == "table" then
                TaskTracker.EnsureTaskOwnerCharKey(node, key)
            elseif node.id and not taskHasAnyCharProgress(node.id) then
                TaskTracker.EnsureTaskOwnerCharKey(node, key)
            end
        end)
    end
    if TaskTracker.PruneOrphanedCharProgress then
        TaskTracker.PruneOrphanedCharProgress()
    end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.ScheduleLiveShareLogin then
        TaskTracker.ScheduleLiveShareLogin()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
    if TaskTracker.ScheduleRestoreOpenNotePeeks then
        TaskTracker.ScheduleRestoreOpenNotePeeks()
    end
end

function TaskTracker.OnCharacterLeave()
    if TaskTracker.StashLiveSharesOnLeave then
        TaskTracker.StashLiveSharesOnLeave()
    end
    local key = TaskTracker._activeCharProgressKey or TaskTracker.GetCharProgressKey()
    if key then
        if TaskTracker.SnapshotCharRegistryProgress then
            TaskTracker.SnapshotCharRegistryProgress(key)
        end
        TaskTracker.PersistCharTaskProgress(key)
    end
    TaskTracker.ClearCharScopedProgressFromNodes()
    TaskTracker._activeCharProgressKey = nil
    TaskTracker._ttCharProgressLoaded = nil
end

--- Default account-wide flag for a user task. Module show/hide follows the profile.
function TaskTracker.InferDefaultTaskAccountWide(node)
    if not node or node.type ~= "task" then return false end
    if node.accountWide == true then return true end
    if node.accountWide == false then return false end
    if node.reset ~= "weekly" then return false end
    local names = TaskTracker.DefaultAccountWideWeeklyNames
    if type(names) ~= "table" then return false end
    local n = (node.name or ""):lower()
    for _, nm in ipairs(names) do
        if type(nm) == "string" and nm:lower() == n then
            return true
        end
    end
    return false
end

local function buildDefaultAccountWideNameList()
    local out = {}
    local seen = {}
    local defs = TaskTracker.Defaults
    if type(defs) ~= "table" then return out end
    for _, listKey in ipairs({ "daily", "weekly" }) do
        local list = defs[listKey]
        if type(list) == "table" then
            for _, entry in ipairs(list) do
                if type(entry) == "table" and entry.accountWide == true and type(entry.name) == "string" then
                    local nm = entry.name
                    if not seen[nm] then
                        seen[nm] = true
                        out[#out + 1] = nm
                    end
                end
            end
        end
    end
    if type(defs.accountWeekly) == "table" then
        for _, entry in ipairs(defs.accountWeekly) do
            local nm = type(entry) == "table" and entry.name or entry
            if type(nm) == "string" and not seen[nm] then
                seen[nm] = true
                out[#out + 1] = nm
            end
        end
    end
    return out
end

--- One-time migration: default scope flags; move char-scoped progress off nodes into _pending.
function TaskTracker.MigrateTaskScopeDefaults()
    local db = TaskTrackerDB
    if not db then return end
    local VER = 1
    if (db.taskScopeMigrationVer or 0) >= VER then return end

    TaskTracker.DefaultAccountWideWeeklyNames = TaskTracker.DefaultAccountWideWeeklyNames
        or buildDefaultAccountWideNameList()

    local pending = charBucket(PENDING_CHAR_KEY)
    TaskTracker.WalkTree(function(node)
        if node.type ~= "task" then return end
        local aw = TaskTracker.InferDefaultTaskAccountWide(node)
        if aw then
            node.accountWide = true
            node.showOnOtherCharacters = nil
        else
            node.accountWide = nil
            node.showOnOtherCharacters = nil
            node.ownerCharKey = nil
            if node.id then
                local snap = TaskTracker.SnapshotTaskProgress(node)
                if snapHasProgress(snap) then
                    pending[node.id] = snap
                end
                TaskTracker.ClearTaskProgressOnNode(node)
            end
        end
    end)

    db.taskScopeMigrationVer = VER
    if TaskTracker.MigrateTaskOwnerCharKeys then
        TaskTracker.MigrateTaskOwnerCharKeys()
    end
end

--- Assign ownerCharKey from per-character progress buckets (post–scope migration).
function TaskTracker.MigrateTaskOwnerCharKeys()
    local db = TaskTrackerDB
    if not db then return end
    local VER = 1
    if (db.taskOwnerMigrationVer or 0) >= VER then return end
    local root = charProgressRoot()
    if not root or not TaskTracker.WalkTree then
        db.taskOwnerMigrationVer = VER
        return
    end

    local ownerByTaskId = {}
    for charKey, bucket in pairs(root) do
        if charKey ~= PENDING_CHAR_KEY and type(bucket) == "table" then
            for taskId, snap in pairs(bucket) do
                if type(taskId) == "string" and type(snap) == "table" and snapHasProgress(snap) then
                    if not ownerByTaskId[taskId] then
                        ownerByTaskId[taskId] = charKey
                    end
                end
            end
        end
    end

    TaskTracker.WalkTree(function(node)
        if node.type ~= "task" or TaskTracker.IsTaskAccountWide(node) or not node.id then return end
        if type(node.ownerCharKey) == "string" and node.ownerCharKey ~= "" then return end
        local owner = ownerByTaskId[node.id]
        if owner then
            node.ownerCharKey = owner
        end
    end)

    db.taskOwnerMigrationVer = VER
end

function TaskTracker.MigrateTaskScopeOnEdit(node, wasAccountWide, nowAccountWide)
    if not node or node.type ~= "task" then return end
    if wasAccountWide == nowAccountWide then
        if nowAccountWide then
            node.accountWide = true
        else
            node.accountWide = nil
        end
        return
    end
    if wasAccountWide and not nowAccountWide then
        local key = TaskTracker.GetCharProgressKey()
        if key and node.id then
            charBucket(key)[node.id] = TaskTracker.SnapshotTaskProgress(node)
            node.ownerCharKey = key
        end
        node.accountWide = nil
    elseif not wasAccountWide and nowAccountWide then
        local merged = TaskTracker.SnapshotTaskProgress(node)
        local key = TaskTracker.GetCharProgressKey()
        if key and node.id then
            local bucket = charBucket(key)
            local snap = bucket and bucket[node.id]
            if type(snap) == "table" and snapHasProgress(snap) then
                merged = snap
            end
            if bucket then bucket[node.id] = nil end
        end
        if type(merged) == "table" and snapHasProgress(merged) then
            TaskTracker.ApplyTaskProgressSnapshot(node, merged)
        end
        node.accountWide = true
        node.showOnOtherCharacters = nil
        node.ownerCharKey = nil
    end
end

-- ─────────────────────────────────────
-- Character roster / wallet snapshots (Options → Characters, task tooltip alts)
-- ─────────────────────────────────────
local WALLET_THROTTLE = 2

local function charMetaRoot()
    local db = TaskTrackerDB
    if not db then return nil end
    if type(db.charMeta) ~= "table" then
        db.charMeta = {}
    end
    return db.charMeta
end

local function charMetaBucket(charKey)
    local root = charMetaRoot()
    if not root or not charKey or charKey == PENDING_CHAR_KEY then return nil end
    if type(root[charKey]) ~= "table" then
        root[charKey] = {}
    end
    return root[charKey]
end

local function charMetaExisting(charKey)
    local root = TaskTrackerDB and TaskTrackerDB.charMeta
    if type(root) ~= "table" or not charKey then return nil end
    local b = root[charKey]
    if type(b) == "table" then return b end
    return nil
end

local function splitCharKey(charKey)
    if type(charKey) ~= "string" or charKey == "" then
        return nil, nil
    end
    local realm, name = charKey:match("^(.-)::(.+)$")
    if name then
        return realm, name
    end
    return nil, charKey
end

function TaskTracker.ParseCharProgressKey(charKey)
    return splitCharKey(charKey)
end

function TaskTracker.GetCharDisplayName(charKey)
    local meta = charMetaExisting(charKey)
    if meta and type(meta.name) == "string" and meta.name ~= "" then
        return meta.name
    end
    local _, name = splitCharKey(charKey)
    return name or charKey or "?"
end

function TaskTracker.GetCharDisplayRealm(charKey)
    local meta = charMetaExisting(charKey)
    if meta and type(meta.realm) == "string" and meta.realm ~= "" then
        return meta.realm
    end
    local realm = splitCharKey(charKey)
    return realm or ""
end

function TaskTracker.GetCharClassColor(charKey)
    local meta = charMetaExisting(charKey)
    local classFile = meta and meta.classFile
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if type(c) == "table" then
        return c.r or 1, c.g or 1, c.b or 1
    end
    return 1, 1, 1
end

function TaskTracker.StampCharMetaIdentity(charKey)
    charKey = charKey or TaskTracker.GetCharProgressKey()
    local meta = charMetaBucket(charKey)
    if not meta then return end
    local name, realm = UnitFullName("player")
    if type(name) == "string" and name ~= "" then
        meta.name = name
    end
    if type(realm) == "string" and realm ~= "" then
        meta.realm = realm
    end
    local _, classFile = UnitClass("player")
    if type(classFile) == "string" and classFile ~= "" then
        meta.classFile = classFile
    end
    if GetServerTime then
        meta.lastSeen = GetServerTime()
    end
end

function TaskTracker.IsCharTooltipEnabled(charKey)
    local meta = charMetaExisting(charKey)
    return meta and meta.tooltipEnabled == true
end

function TaskTracker.SetCharTooltipEnabled(charKey, on)
    local meta = charMetaBucket(charKey)
    if not meta then return end
    if on then
        meta.tooltipEnabled = true
    else
        meta.tooltipEnabled = nil
    end
end

local function addPositiveId(set, id)
    id = tonumber(id)
    if id and id > 0 then
        set[id] = true
    end
end

local function harvestRequirementIds(req, currencies, factions)
    if type(req) ~= "table" then return end
    addPositiveId(currencies, req.currencyId)
    addPositiveId(factions, req.factionId)
    if type(req.requirements) == "table" then
        for _, nested in ipairs(req.requirements) do
            harvestRequirementIds(nested, currencies, factions)
        end
    end
end

local function collectTrackedWalletIds()
    local currencies, factions = {}, {}
    if TaskTracker.WalkTree then
        TaskTracker.WalkTree(function(node)
            if not node or node.type ~= "task" then return end
            local a = node.advanced
            if type(a) == "table" then
                if a.type == "item" and (a.itemKind or "item") == "currency" then
                    for _, id in ipairs(a.itemIds or {}) do
                        addPositiveId(currencies, id)
                    end
                elseif a.type == "reputation" then
                    addPositiveId(factions, a.repFactionId)
                elseif a.type == "collectable" and TaskTracker.GetCollectableEntry then
                    local ent = TaskTracker.GetCollectableEntry(
                        a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
                    if ent then
                        addPositiveId(currencies, ent.currencyId)
                        addPositiveId(factions, ent.factionId)
                    end
                end
            end
        end)
    end
    if type(TaskTracker.Registry) == "table" then
        for _, e in ipairs(TaskTracker.Registry) do
            if type(e) == "table" then
                addPositiveId(currencies, e.currencyId)
                addPositiveId(currencies, e.catchupCurrencyId)
                addPositiveId(factions, e.factionId)
                if type(e.requirements) == "table" then
                    for _, req in ipairs(e.requirements) do
                        harvestRequirementIds(req, currencies, factions)
                    end
                end
            end
        end
    end
    return currencies, factions
end

local function liveCurrencyQty(currencyId)
    currencyId = tonumber(currencyId)
    if not currencyId or currencyId <= 0 then return nil end
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyId)
    if not ok or type(info) ~= "table" then return nil end
    return math.max(0, tonumber(info.quantity) or 0)
end

local function mapGet(map, id)
    if type(map) ~= "table" or id == nil then return nil end
    local v = map[id]
    if v ~= nil then return v end
    return map[tostring(id)]
end

local function registryRepEntryForFaction(factionId)
    factionId = tonumber(factionId)
    if not factionId or factionId <= 0 or type(TaskTracker.Registry) ~= "table" then
        return nil
    end
    for _, e in ipairs(TaskTracker.Registry) do
        if type(e) == "table" and e.type == "reputation_standing"
            and tonumber(e.factionId) == factionId then
            return e
        end
    end
    return nil
end

local function enrichRepSnapshot(factionId, snap)
    snap = type(snap) == "table" and snap or {}
    local re = registryRepEntryForFaction(factionId)
    if re then
        if re.warband then
            snap.warband = true
        end
        if TaskTracker.GetRegistryReputationStanding then
            local cur, cap = TaskTracker.GetRegistryReputationStanding(re)
            local kind = tostring(re.repKind or ""):lower()
            if kind == "renown" then
                snap.renownLevel = tonumber(cur) or snap.renownLevel
                snap.renownMaxLevel = tonumber(cap) or snap.renownMaxLevel
            elseif kind == "friendship" then
                snap.friendshipRank = tonumber(cur) or 0
                snap.friendshipMax = tonumber(cap) or snap.friendshipMax
            end
        end
    end
    return snap
end

local function isWarbandFaction(factionId)
    local re = registryRepEntryForFaction(factionId)
    if re and re.warband then return true end
    return false
end

local function compactRepSnapshot(fd)
    if type(fd) ~= "table" then return nil end
    local snap = {
        name = fd.name,
        reaction = fd.reaction,
        currentStanding = fd.currentStanding or fd.currentRep,
        currentReactionThreshold = fd.currentReactionThreshold,
        nextReactionThreshold = fd.nextReactionThreshold,
        isMajorFaction = fd.isMajorFaction or nil,
        renownLevel = fd.renownLevel,
        renownReputationEarned = fd.renownReputationEarned,
        isParagon = fd.isParagon or nil,
        paragonValue = fd.paragonValue,
        paragonThreshold = fd.paragonThreshold,
        paragonCycleValue = fd.paragonCycleValue,
        paragonHasRewardPending = fd.paragonHasRewardPending or nil,
    }
    if snap.name == nil and snap.currentStanding == nil and snap.renownLevel == nil
        and snap.reaction == nil and not snap.isParagon then
        return nil
    end
    return snap
end

local function inProgressSyncGrace()
    return TaskTracker._progressSyncGraceUntil and GetTime and GetTime() < TaskTracker._progressSyncGraceUntil
end

function TaskTracker.SnapshotCharWallet(charKey)
    charKey = charKey or TaskTracker.GetCharProgressKey()
    local active = TaskTracker.GetCharProgressKey()
    if not charKey or charKey ~= active then return end
    local meta = charMetaBucket(charKey)
    if not meta then return end
    TaskTracker.StampCharMetaIdentity(charKey)

    if GetMoney then
        local ok, copper = pcall(GetMoney)
        if ok then
            local n = tonumber(copper) or 0
            if not (n == 0 and (tonumber(meta.gold) or 0) > 0 and inProgressSyncGrace()) then
                meta.gold = math.max(0, math.floor(n))
            end
        end
    end

    local currencies, factions = collectTrackedWalletIds()
    local curMap = type(meta.currencies) == "table" and meta.currencies or {}
    local nextCur = {}
    for id in pairs(currencies) do
        local qty = liveCurrencyQty(id)
        local prev = tonumber(mapGet(curMap, id))
        if qty == nil then
            nextCur[id] = prev
        elseif qty == 0 and (prev or 0) > 0 and inProgressSyncGrace() then
            nextCur[id] = prev
        else
            nextCur[id] = qty
        end
    end
    meta.currencies = nextCur

    local repMap = type(meta.reputations) == "table" and meta.reputations or {}
    local nextRep = {}
    for id in pairs(factions) do
        local fd = TaskTracker.GetAdvancedFactionData and TaskTracker.GetAdvancedFactionData(id)
        local snap = enrichRepSnapshot(id, compactRepSnapshot(fd) or {})
        if snap.name ~= nil or snap.currentStanding ~= nil or snap.renownLevel ~= nil
            or snap.reaction ~= nil or snap.isParagon or snap.friendshipRank ~= nil
            or snap.warband then
            nextRep[id] = snap
        else
            nextRep[id] = mapGet(repMap, id)
        end
    end
    meta.reputations = nextRep
end

function TaskTracker.RequestCharWalletSnapshot()
    if TaskTracker._charWalletSnapTimer then
        return
    end
    local delay = WALLET_THROTTLE
    if C_Timer and C_Timer.NewTimer then
        TaskTracker._charWalletSnapTimer = C_Timer.NewTimer(delay, function()
            TaskTracker._charWalletSnapTimer = nil
            if TaskTracker.SnapshotCharWallet then
                TaskTracker.SnapshotCharWallet()
            end
        end)
    else
        if TaskTracker.SnapshotCharWallet then
            TaskTracker.SnapshotCharWallet()
        end
    end
end

local function gatherCharKeys()
    local seen = {}
    local function add(root)
        if type(root) ~= "table" then return end
        for k in pairs(root) do
            if type(k) == "string" and k ~= "" and k ~= PENDING_CHAR_KEY then
                seen[k] = true
            end
        end
    end
    local db = TaskTrackerDB
    if db then
        add(db.charTaskProgress)
        add(db.charRegistryVisibility)
        add(db.charLearnedProfessions)
        add(db.charMeta)
    end
    return seen
end

function TaskTracker.GetTrackedCharacters()
    local seen = gatherCharKeys()
    local list = {}
    for k in pairs(seen) do
        list[#list + 1] = k
    end
    local current = TaskTracker.GetCharProgressKey()
    table.sort(list, function(a, b)
        if a == current then return true end
        if b == current then return false end
        local ra, na = splitCharKey(a)
        local rb, nb = splitCharKey(b)
        ra, rb = ra or "", rb or ""
        na, nb = na or a, nb or b
        if ra ~= rb then return ra < rb end
        return na < nb
    end)
    return list
end

--- Drop stored progress / visibility / professions / tooltip data for an alt.
--- Does not change the task tree. Logging in on that character creates a fresh bucket.
--- Refuses the currently logged-in character (they would be re-stamped immediately).
function TaskTracker.ForgetCharacterData(charKey)
    if type(charKey) ~= "string" or charKey == "" or charKey == PENDING_CHAR_KEY then
        return false
    end
    local current = TaskTracker.GetCharProgressKey()
    if current and charKey == current then
        return false
    end
    local db = TaskTrackerDB
    if not db then return false end
    if type(db.charTaskProgress) == "table" then
        db.charTaskProgress[charKey] = nil
    end
    if type(db.charRegistryVisibility) == "table" then
        db.charRegistryVisibility[charKey] = nil
    end
    if type(db.charLearnedProfessions) == "table" then
        db.charLearnedProfessions[charKey] = nil
    end
    if type(db.charMeta) == "table" then
        db.charMeta[charKey] = nil
    end
    if type(db.charRegistryProgress) == "table" then
        db.charRegistryProgress[charKey] = nil
    end
    return true
end

local function isUserTaskNode(node)
    if not node or node.type ~= "task" then return false end
    if node.registryId or node.collectionFarmId then return false end
    return true
end

local function nodeProgressSource(node, charKey)
    if not node then return nil end
    if TaskTracker.IsTaskAccountWide(node) then
        return node
    end
    local bucket = charBucketExisting(charKey)
    local snap = bucket and node.id and bucket[node.id]
    if type(snap) == "table" then
        return snap
    end
    if charKey and charKey == TaskTracker.GetCharProgressKey() then
        return node
    end
    return nil
end

local function progressIsDone(node, src)
    if type(src) ~= "table" then return false end
    if src.doneOverride == true then return true end
    if src.doneOverride == false then return false end
    if src.done then return true end
    local max = tonumber(node and node.taskMax) or 1
    if max < 1 then max = 1 end
    return (tonumber(src.taskCount) or 0) >= max
end

function TaskTracker.GetCharTaskCounts(charKey)
    local done, total = 0, 0
    if not charKey or not TaskTracker.WalkTree then
        return done, total
    end
    TaskTracker.WalkTree(function(node)
        if not isUserTaskNode(node) then return end
        if not TaskTracker.IsTaskVisibleForChar(node, charKey) then return end
        total = total + 1
        if progressIsDone(node, nodeProgressSource(node, charKey)) then
            done = done + 1
        end
    end)
    return done, total
end

function TaskTracker.GetCharLastSeen(charKey)
    local meta = charMetaExisting(charKey)
    local ts = meta and tonumber(meta.lastSeen)
    if ts and ts > 0 then return ts end
    local bucket = charBucketExisting(charKey)
    ts = bucket and tonumber(bucket._lastSeen)
    if ts and ts > 0 then return ts end
    return nil
end

function TaskTracker.FormatCharLastSeen(charKey)
    local ts = TaskTracker.GetCharLastSeen(charKey)
    if not ts then return "never" end
    if date then
        return date("%b %d, %Y %H:%M", ts)
    end
    return tostring(ts)
end

local function formatQty(n)
    n = math.floor(tonumber(n) or 0)
    if n < 0 then n = 0 end
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(n)
    end
    if TaskTracker.FormatGoldAmountForDisplay then
        return TaskTracker.FormatGoldAmountForDisplay(n)
    end
    return tostring(n)
end

function TaskTracker.GetCharGoldCopper(charKey)
    if not charKey then return 0 end
    if charKey == TaskTracker.GetCharProgressKey() and GetMoney then
        local ok, copper = pcall(GetMoney)
        if ok then
            return math.max(0, math.floor(tonumber(copper) or 0))
        end
    end
    local meta = charMetaExisting(charKey)
    return math.max(0, math.floor(tonumber(meta and meta.gold) or 0))
end

function TaskTracker.GetCharCurrencyQuantity(charKey, currencyId)
    currencyId = tonumber(currencyId)
    if not charKey or not currencyId or currencyId <= 0 then return 0 end
    if charKey == TaskTracker.GetCharProgressKey() then
        local live = liveCurrencyQty(currencyId)
        if live ~= nil then return live end
    end
    local meta = charMetaExisting(charKey)
    local map = meta and meta.currencies
    return math.max(0, math.floor(tonumber(mapGet(map, currencyId)) or 0))
end

function TaskTracker.SumCharCurrency(currencyId)
    currencyId = tonumber(currencyId)
    if not currencyId or currencyId <= 0 then return 0 end
    local total = 0
    for _, key in ipairs(TaskTracker.GetTrackedCharacters()) do
        total = total + TaskTracker.GetCharCurrencyQuantity(key, currencyId)
    end
    return total
end

function TaskTracker.SumCharGoldCopper()
    local total = 0
    for _, key in ipairs(TaskTracker.GetTrackedCharacters()) do
        total = total + TaskTracker.GetCharGoldCopper(key)
    end
    return total
end

function TaskTracker.GetCharReputationSnapshot(charKey, factionId)
    factionId = tonumber(factionId)
    if not charKey or not factionId or factionId <= 0 then return nil end
    local liveForAll = isWarbandFaction(factionId) or charKey == TaskTracker.GetCharProgressKey()
    if liveForAll and TaskTracker.GetAdvancedFactionData then
        local fd = TaskTracker.GetAdvancedFactionData(factionId)
        local live = enrichRepSnapshot(factionId, compactRepSnapshot(fd) or {})
        if live.renownLevel ~= nil or live.friendshipRank ~= nil or live.currentStanding ~= nil
            or live.reaction ~= nil or live.isParagon or live.name then
            return live
        end
    end
    local meta = charMetaExisting(charKey)
    local map = meta and meta.reputations
    local snap = mapGet(map, factionId)
    if type(snap) == "table" then return snap end
    return nil
end

local function repCompareScore(snap)
    if type(snap) ~= "table" then return nil end
    if snap.friendshipRank ~= nil then
        return 1.5e12 + (tonumber(snap.friendshipRank) or 0)
    end
    if snap.isMajorFaction or snap.renownLevel ~= nil then
        return 2e12
            + (tonumber(snap.renownLevel) or 0) * 1e6
            + (tonumber(snap.renownReputationEarned) or 0)
    end
    if snap.isParagon then
        return 1e12 + (tonumber(snap.paragonValue) or 0)
    end
    local v = tonumber(snap.currentStanding or snap.currentRep)
    if v == nil then return nil end
    return v
end

function TaskTracker.GetHighestRepCharacter(factionId)
    factionId = tonumber(factionId)
    if not factionId or factionId <= 0 then return nil end
    local bestKey, bestScore
    for _, key in ipairs(TaskTracker.GetTrackedCharacters()) do
        local score = repCompareScore(TaskTracker.GetCharReputationSnapshot(key, factionId))
        if score ~= nil and (bestScore == nil or score > bestScore) then
            bestScore = score
            bestKey = key
        end
    end
    return bestKey
end

function TaskTracker.FormatCharReputationAmount(snap)
    if type(snap) ~= "table" then return "—" end
    if snap.friendshipRank ~= nil then
        local cur = tonumber(snap.friendshipRank) or 0
        local cap = tonumber(snap.friendshipMax)
        if cap and cap > 0 then
            return string.format("Rank %s/%s", formatQty(cur), formatQty(cap))
        end
        return "Rank " .. formatQty(cur)
    end
    if snap.isMajorFaction or snap.renownLevel ~= nil then
        return "Renown " .. tostring(tonumber(snap.renownLevel) or 0)
    end
    if snap.isParagon then
        local cur = tonumber(snap.paragonCycleValue)
        if cur == nil then
            local th = tonumber(snap.paragonThreshold) or 10000
            if th < 1 then th = 10000 end
            cur = (tonumber(snap.paragonValue) or 0) % th
        end
        local th = tonumber(snap.paragonThreshold) or 10000
        return string.format("Paragon %s/%s", formatQty(cur), formatQty(th))
    end
    local react = tonumber(snap.reaction) or 0
    local standing = _G["FACTION_STANDING_LABEL" .. react] or ("Tier " .. tostring(react))
    local val = tonumber(snap.currentStanding or snap.currentRep)
    if val ~= nil then
        return string.format("%s %s", standing, formatQty(val))
    end
    return standing
end

local function registryEntryForRow(entry, node)
    if type(entry) == "table" then return entry end
    local rid = node and (node.registryEntryId or node.registryId or node.collectionFarmId)
    if rid and TaskTracker.RegistryByID then
        return TaskTracker.RegistryByID[rid]
    end
    return nil
end

function TaskTracker.GetRowTrackedCurrencyId(entry, node)
    if node and type(node.advanced) == "table" then
        local a = node.advanced
        if a.type == "item" and (a.itemKind or "item") == "currency" then
            local id = a.itemIds and tonumber(a.itemIds[1])
            if id and id > 0 then return id end
        end
        if a.type == "collectable" and TaskTracker.GetCollectableEntry then
            local ent = TaskTracker.GetCollectableEntry(
                a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
            local id = ent and tonumber(ent.currencyId)
            if id and id > 0 then return id end
        end
    end
    local re = registryEntryForRow(entry, node)
    if re then
        local id = tonumber(re.currencyId)
        if id and id > 0 then return id end
        id = tonumber(re.catchupCurrencyId)
        if id and id > 0 then return id end
    end
    return nil
end

function TaskTracker.GetRowTrackedFactionId(entry, node)
    if node and type(node.advanced) == "table" then
        local a = node.advanced
        if a.type == "reputation" then
            local id = tonumber(a.repFactionId)
            if id and id > 0 then return id end
        end
        if a.type == "collectable" and TaskTracker.GetCollectableEntry then
            local ent = TaskTracker.GetCollectableEntry(
                a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
            local id = ent and tonumber(ent.factionId)
            if id and id > 0 then return id end
        end
    end
    local re = registryEntryForRow(entry, node)
    if re then
        local id = tonumber(re.factionId)
        if id and id > 0 then return id end
    end
    return nil
end

function TaskTracker.RowTracksGold(node)
    return node and type(node.advanced) == "table" and node.advanced.type == "gold"
end

local function charRegistryProgressRoot()
    local db = TaskTrackerDB
    if not db then return nil end
    if type(db.charRegistryProgress) ~= "table" then
        db.charRegistryProgress = {}
    end
    return db.charRegistryProgress
end

local function registryPeriodStamp(entry)
    if not entry or (entry.reset ~= "daily" and entry.reset ~= "weekly") then
        return 0
    end
    if not TaskTracker.GetResetTimes then return 0 end
    local daily, weekly = TaskTracker.GetResetTimes()
    if entry.reset == "daily" then return daily or 0 end
    return weekly or 0
end

--- Multi-quest weekly rows remember, per character, which quest ids were already
--- flagged the first time we saw that character this period. A later new id is
--- that character's completion. The old account-wide count treated whoever
--- logged in first as the baseline for everyone else.
local function charWeeklyQuestDeltaRow(entry, create)
    if not entry or not entry.id then return nil end
    local charKey = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if not charKey then return nil end
    local root = charRegistryProgressRoot()
    if not root then return nil end
    local bucket = root[charKey]
    if type(bucket) ~= "table" then
        if not create then return nil end
        bucket = {}
        root[charKey] = bucket
    end
    local row = bucket[entry.id]
    if type(row) ~= "table" then
        if not create then return nil end
        row = {}
        bucket[entry.id] = row
    end
    local period = registryPeriodStamp(entry)
    if row.qper ~= period then
        row.qbase = nil
        row.qcredit = nil
        row.qextra = nil
        row.qturns = nil
        row.qpending = nil
        row.qper = period
    end
    return row, period
end

--- qextra, plus one per newly flagged id, plus later turn-ins of an id this period.
--- qpending is a turn-in the flag credit has not covered yet.
local function weeklyQuestTurnTotal(row)
    local n = tonumber(row.qextra) or 0
    if type(row.qcredit) == "table" then
        for _ in pairs(row.qcredit) do
            n = n + 1
        end
    end
    if type(row.qturns) == "table" then
        for _, v in pairs(row.qturns) do
            local t = math.floor(tonumber(v) or 0)
            if t > 0 then n = n + t end
        end
    end
    if type(row.qpending) == "table" then
        local credit = type(row.qcredit) == "table" and row.qcredit or nil
        for key in pairs(row.qpending) do
            if not credit or not credit[key] then
                n = n + 1
            end
        end
    end
    return n
end

local function registryQuestFlagged(qid, saw)
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return false end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
    if ok and saw then saw.ok = true end
    return ok and done == true
end

function TaskTracker.GetCharWeeklyQuestDelta(entry)
    if not entry or not entry.quests then return 0 end
    local row = charWeeklyQuestDeltaRow(entry, true)
    if not row then return 0 end
    local saw = { ok = false }
    if type(row.qbase) ~= "table" then
        local base = {}
        for qid in pairs(entry.quests) do
            if registryQuestFlagged(qid, saw) then
                base[tostring(qid)] = true
            end
        end
        if not saw.ok then return 0 end
        row.qbase = base
        row.qcredit = {}
        local keep = 0
        if row.p == row.qper then
            keep = tonumber(row.v) or 0
            if row.d == 1 and keep < 1 then keep = 1 end
        end
        local cap = tonumber(entry.max) or 1
        if entry.type == "quest_complete" or cap < 1 then cap = 1 end
        if keep > cap then keep = cap end
        if keep < 0 then keep = 0 end
        row.qextra = keep
    end
    if type(row.qcredit) ~= "table" then row.qcredit = {} end
    for qid in pairs(entry.quests) do
        if registryQuestFlagged(qid, saw) then
            local key = tostring(qid)
            if not row.qbase[key] then
                row.qcredit[key] = true
            end
        end
    end
    if type(row.qpending) == "table" and type(row.qcredit) == "table" then
        for key in pairs(row.qpending) do
            if row.qcredit[key] then
                row.qpending[key] = nil
            end
        end
    end
    if not saw.ok and not next(row.qbase) and not next(row.qcredit)
        and type(row.qturns) ~= "table" and type(row.qpending) ~= "table" then
        return tonumber(row.qextra) or 0
    end
    return weeklyQuestTurnTotal(row)
end

local function professionOverrideFromRegistryRow(row)
    if type(row) ~= "table" then return nil end
    local dov = row.cov
    if dov ~= "complete" and dov ~= "incomplete" then
        if row.ov == true then
            dov = "complete"
        elseif row.ov == false then
            dov = "incomplete"
        else
            dov = nil
        end
    end
    return dov
end

--- One-time copy of this week's profession progress onto the new editable task.
--- Multi-quest weeklies keep the registry baseline so a quest already turned in stays done.
function TaskTracker.SeedProfessionTaskFromRegistry(task, entry)
    if not task or task.type ~= "task" or not task.id or not entry or not entry.id then return end
    if task.professionProgressSeeded then return end
    if entry.type == "profession_catchup" then
        task.professionProgressSeeded = true
        return
    end
    if entry.type ~= "quest_complete" and entry.type ~= "quest_count" then
        task.professionProgressSeeded = true
        return
    end

    local period = registryPeriodStamp(entry)
    local usesDelta = TaskTracker.RegistryEntryUsesWeeklyQuestDelta
        and TaskTracker.RegistryEntryUsesWeeklyQuestDelta(entry)
    local active = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    local db = TaskTrackerDB

    local function snapFromRow(row, count, userValue, dov, autoCount)
        if type(row) ~= "table" and (tonumber(count) or 0) <= 0 and userValue == nil and dov == nil then
            return nil
        end
        count = tonumber(count) or 0
        if count < 0 then count = 0 end
        local cap = tonumber(entry.max) or 1
        if entry.type == "quest_complete" or cap < 1 then cap = 1 end
        local snap = {
            taskCount = count,
            done = count >= cap or dov == "complete",
            taskUserValue = userValue,
            doneOverride = dov,
        }
        if usesDelta and type(row) == "table" and type(row.qbase) == "table"
            and (tonumber(row.qper) or 0) == period then
            local credited = TaskTracker.DeepCopy(row.qcredit) or {}
            local nCred = 0
            for _ in pairs(credited) do nCred = nCred + 1 end
            local extra = tonumber(row.qextra) or 0
            local auto = tonumber(autoCount)
            if auto and auto > extra + nCred then
                extra = auto - nCred
            end
            snap.advanced = {
                questPeriodBaseline = TaskTracker.DeepCopy(row.qbase),
                questPeriodCredited = credited,
                questPeriodOrphanCredits = extra,
            }
        end
        return snap
    end

    local function writeSnap(charKey, snap, ontoNode)
        if not snap or not charKey then return end
        local dest = charBucket(charKey)
        if dest and dest[task.id] == nil then
            dest[task.id] = snap
        end
        if ontoNode and charKey == active then
            TaskTracker.ApplyTaskProgressSnapshot(task, snap)
        end
    end

    local activeReady = false
    if active and db and db.registryState and db.registryState[entry.id] then
        local st = db.registryState[entry.id]
        if usesDelta and TaskTracker.GetCharWeeklyQuestDelta then
            TaskTracker.GetCharWeeklyQuestDelta(entry)
        end
        local row = charWeeklyQuestDeltaRow(entry, false)
        local auto = tonumber(st.value) or 0
        local count = tonumber(st.userValue)
        if count == nil then count = auto end
        local dov = professionOverrideFromRegistryRow({
            cov = st.checkboxDoneOverride,
            ov = st.override,
        })
        local snap = snapFromRow(row, count, st.userValue, dov, auto)
        local baseReady = (not usesDelta) or (snap and snap.advanced)
        -- A multi-quest weekly with no baseline yet has to wait. Marking it ready
        -- would snapshot every quest that is already flagged and hide this week's turn-in.
        local nothingToKeep = (not usesDelta) and auto <= 0 and st.userValue == nil and dov == nil
        if baseReady or nothingToKeep then
            writeSnap(active, snap, true)
            activeReady = true
        else
            local cap = tonumber(entry.max) or 1
            if entry.type == "quest_complete" or cap < 1 then cap = 1 end
            task.taskCount = math.max(0, count)
            task.done = task.taskCount >= cap or dov == "complete"
        end
    elseif active then
        activeReady = true
    end

    local root = db and db.charRegistryProgress
    if type(root) == "table" then
        for charKey, bucket in pairs(root) do
            if charKey ~= active and type(bucket) == "table" and type(bucket[entry.id]) == "table" then
                local row = bucket[entry.id]
                if (entry.reset ~= "daily" and entry.reset ~= "weekly") or (tonumber(row.p) or 0) == period then
                    local dov = professionOverrideFromRegistryRow(row)
                    local shown = row.uv
                    if shown == nil then shown = row.v end
                    writeSnap(charKey, snapFromRow(row, shown, row.uv, dov, row.v), false)
                end
            end
        end
    end

    if activeReady then
        task.professionProgressSeeded = true
    end
end

--- Progress popup: this character's weekly tally becomes extra credit, and the
--- quests already flagged are the new baseline so the next sync holds that number.
function TaskTracker.SetCharWeeklyQuestDelta(entry, tally)
    if not entry or not entry.quests then return end
    local row = charWeeklyQuestDeltaRow(entry, true)
    if not row then return end
    tally = math.floor(tonumber(tally) or 0)
    if tally < 0 then tally = 0 end
    local saw = { ok = false }
    local base = {}
    for qid in pairs(entry.quests) do
        if registryQuestFlagged(qid, saw) then
            base[tostring(qid)] = true
        end
    end
    if not saw.ok then return end
    row.qbase = base
    row.qcredit = {}
    row.qturns = nil
    row.qpending = nil
    row.qextra = tally
end

--- A quest on a weekly multi-id row was turned in. The first new flag still counts
--- once. A later turn-in, or a turn-in of an id already in the baseline, adds one.
--- qpending waits one scan so that first flag is not counted twice.
function TaskTracker.NoteRegistryWeeklyQuestTurnIn(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then return end
    local entries = TaskTracker.QuestToEntry and TaskTracker.QuestToEntry[questID]
    if not entries then return end
    local key = tostring(questID)
    for i = 1, #entries do
        local entry = entries[i]
        if TaskTracker.RegistryEntryUsesWeeklyQuestDelta
            and TaskTracker.RegistryEntryUsesWeeklyQuestDelta(entry) then
            local row = charWeeklyQuestDeltaRow(entry, true)
            if row then
                local inBase = type(row.qbase) == "table" and row.qbase[key]
                local inCredit = type(row.qcredit) == "table" and row.qcredit[key] and not inBase
                local turns = 0
                if type(row.qturns) == "table" then
                    turns = math.floor(tonumber(row.qturns[key]) or 0)
                    if turns < 0 then turns = 0 end
                end
                local pending = type(row.qpending) == "table" and row.qpending[key]
                local function addTurn()
                    if type(row.qturns) ~= "table" then row.qturns = {} end
                    local cap = tonumber(entry.max) or 1
                    if cap < 1 then cap = 1 end
                    local n = math.floor(tonumber(row.qturns[key]) or 0) + 1
                    if n > cap then n = cap end
                    row.qturns[key] = n
                end
                if pending and not inCredit then
                    if type(row.qpending) == "table" then row.qpending[key] = nil end
                    addTurn()
                    addTurn()
                elseif inBase or inCredit or turns > 0 then
                    if pending and type(row.qpending) == "table" then row.qpending[key] = nil end
                    addTurn()
                else
                    if type(row.qpending) ~= "table" then row.qpending = {} end
                    row.qpending[key] = true
                end
            end
        end
    end
end

local function formatRegistryTooltipStatus(entry, cur, max, isDone)
    if entry and entry.type == "profession_catchup" then
        return formatQty(cur)
    end
    max = tonumber(max) or 1
    if max < 1 then max = 1 end
    cur = tonumber(cur) or 0
    if max > 1 then
        return string.format("%s/%s", formatQty(cur), formatQty(max))
    end
    return isDone and "Done" or "Incomplete"
end

--- Last registry progress seen on this character. The logged-in character is read live.
function TaskTracker.SnapshotCharRegistryProgress(charKey)
    charKey = charKey or (TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey())
    local active = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if not charKey or not active or charKey ~= active then return end
    if not TaskTracker.Registry or not TaskTracker.GetRegistryEntryProgress then return end
    local root = charRegistryProgressRoot()
    if not root then return end
    local bucket = root[charKey]
    if type(bucket) ~= "table" then
        bucket = {}
        root[charKey] = bucket
    end
    for i = 1, #TaskTracker.Registry do
        local entry = TaskTracker.Registry[i]
        if entry and entry.id
            and not (TaskTracker.RegistryRowIsDisplayOnly and TaskTracker.RegistryRowIsDisplayOnly(entry)) then
            local cur, max, isDone = TaskTracker.GetRegistryEntryProgress(entry.id)
            local period = registryPeriodStamp(entry)
            local doneFlag = isDone and 1 or 0
            local state = TaskTrackerDB.registryState and TaskTrackerDB.registryState[entry.id]
            local uv = state and state.userValue or nil
            local cov = state and state.checkboxDoneOverride or nil
            local ov = state and state.override or nil
            local prev = bucket[entry.id]
            if type(prev) ~= "table" then
                prev = {}
                bucket[entry.id] = prev
            end
            if prev.v ~= cur or prev.m ~= max or prev.d ~= doneFlag or prev.p ~= period
                or prev.uv ~= uv or prev.cov ~= cov or prev.ov ~= ov then
                prev.v, prev.m, prev.d, prev.p = cur, max, doneFlag, period
                prev.uv, prev.cov, prev.ov = uv, cov, ov
            end
        end
    end
end

function TaskTracker.GetCharRegistryTooltipStatus(charKey, entry)
    if not entry or not entry.id then return nil end
    if TaskTracker.RegistryRowIsDisplayOnly and TaskTracker.RegistryRowIsDisplayOnly(entry) then
        return nil
    end
    local active = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if charKey and charKey == active and TaskTracker.GetRegistryEntryProgress then
        local cur, max, isDone = TaskTracker.GetRegistryEntryProgress(entry.id)
        return formatRegistryTooltipStatus(entry, cur, max, isDone)
    end
    local db = TaskTrackerDB
    local bucket = db and db.charRegistryProgress and db.charRegistryProgress[charKey]
    local snap = bucket and bucket[entry.id]
    if type(snap) ~= "table" then return "—" end
    if (entry.reset == "daily" or entry.reset == "weekly") and (tonumber(snap.p) or 0) ~= registryPeriodStamp(entry) then
        return "—"
    end
    return formatRegistryTooltipStatus(entry, snap.v, snap.m, snap.d == 1)
end

--- Manual check / count lock for built-in rows. registryState is account-wide; these fields are not.
function TaskTracker.ApplyCharRegistryOverrides(charKey)
    charKey = charKey or (TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey())
    local db = TaskTrackerDB
    if not charKey or not db or not db.registryState or not TaskTracker.Registry then return end
    local bucket = db.charRegistryProgress and db.charRegistryProgress[charKey]
    for i = 1, #TaskTracker.Registry do
        local entry = TaskTracker.Registry[i]
        local state = entry and db.registryState[entry.id]
        if state and not (TaskTracker.RegistryRowIsDisplayOnly and TaskTracker.RegistryRowIsDisplayOnly(entry)) then
            local row = bucket and bucket[entry.id]
            if type(row) == "table" then
                state.userValue = row.uv
                state.checkboxDoneOverride = row.cov
                state.override = row.ov
            else
                state.userValue = nil
                state.checkboxDoneOverride = nil
                state.override = nil
            end
        end
    end
end

function TaskTracker.PersistCharRegistryOverride(entryId)
    local charKey = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    local db = TaskTrackerDB
    if not charKey or not entryId or not db or not db.registryState then return end
    local state = db.registryState[entryId]
    if not state then return end
    local root = charRegistryProgressRoot()
    if not root then return end
    if type(root[charKey]) ~= "table" then
        root[charKey] = {}
    end
    local row = root[charKey][entryId]
    if type(row) ~= "table" then
        row = {}
        root[charKey][entryId] = row
    end
    row.uv = state.userValue
    row.cov = state.checkboxDoneOverride
    row.ov = state.override
end

function TaskTracker.ClearCharRegistryOverridesForReset(resetKind)
    local db = TaskTrackerDB
    local root = db and db.charRegistryProgress
    if type(root) ~= "table" or not TaskTracker.Registry or not resetKind then return end
    for i = 1, #TaskTracker.Registry do
        local entry = TaskTracker.Registry[i]
        if entry and entry.reset == resetKind then
            for _, bucket in pairs(root) do
                local row = type(bucket) == "table" and bucket[entry.id]
                if type(row) == "table" then
                    row.uv, row.cov, row.ov = nil, nil, nil
                    row.qbase, row.qcredit, row.qextra, row.qturns, row.qpending, row.qper = nil, nil, nil, nil, nil, nil
                end
            end
        end
    end
end

local function registryEntryForTooltip(entry, node)
    if entry and entry.id and TaskTracker.RegistryByID and TaskTracker.RegistryByID[entry.id] then
        return TaskTracker.RegistryByID[entry.id]
    end
    local id = node and (node.registryEntryId or node.registryId)
    if id and TaskTracker.RegistryByID then
        return TaskTracker.RegistryByID[id]
    end
    return nil
end

local function formatTaskStatusForChar(node, charKey)
    local src = nodeProgressSource(node, charKey)
    if type(src) ~= "table" then
        return "—"
    end
    local max = tonumber(node and node.taskMax) or 1
    if max < 1 then max = 1 end
    local cur = tonumber(src.taskCount) or 0
    if max > 1 then
        return string.format("%s/%s", formatQty(cur), formatQty(max))
    end
    return progressIsDone(node, src) and "Done" or "Incomplete"
end

function TaskTracker.FormatCharTooltipStatus(charKey, entry, node)
    if TaskTracker.WorldQuestCharStatus then
        local wq = TaskTracker.WorldQuestCharStatus(charKey, node)
        if wq then return wq end
    end
    if TaskTracker.RowTracksGold(node) then
        local gold = math.floor(TaskTracker.GetCharGoldCopper(charKey) / 10000)
        local s = TaskTracker.FormatGoldAmountForDisplay and TaskTracker.FormatGoldAmountForDisplay(gold) or tostring(gold)
        return s .. " g"
    end
    local cid = TaskTracker.GetRowTrackedCurrencyId(entry, node)
    if cid then
        return formatQty(TaskTracker.GetCharCurrencyQuantity(charKey, cid))
    end
    local fid = TaskTracker.GetRowTrackedFactionId(entry, node)
    if fid then
        return TaskTracker.FormatCharReputationAmount(TaskTracker.GetCharReputationSnapshot(charKey, fid))
    end
    local reg = registryEntryForTooltip(entry, node)
    if reg then
        local status = TaskTracker.GetCharRegistryTooltipStatus(charKey, reg)
        if status then return status end
    end
    return formatTaskStatusForChar(node, charKey)
end

function TaskTracker.AppendCharacterTooltipLines(entry, node)
    if node and node.type ~= "task" and node.type ~= "registryEntry" then return end
    if not GameTooltip or not GameTooltip.AddDoubleLine then return end

    local isGold = TaskTracker.RowTracksGold(node)
    local currencyId = TaskTracker.GetRowTrackedCurrencyId(entry, node)
    local factionId = TaskTracker.GetRowTrackedFactionId(entry, node)

    local opted = {}
    for _, key in ipairs(TaskTracker.GetTrackedCharacters()) do
        if TaskTracker.IsCharTooltipEnabled(key) then
            opted[#opted + 1] = key
        end
    end

    local db = TaskTrackerDB
    local alwaysTotal = not db or db.charTooltipAlwaysCurrencyTotal ~= false
    local alwaysHighest = not db or db.charTooltipAlwaysHighestRep ~= false
    local showTotal = (isGold or currencyId) and (alwaysTotal or #opted > 0)

    local highest
    if factionId and alwaysHighest then
        highest = TaskTracker.GetHighestRepCharacter(factionId)
    end

    if #opted == 0 and not showTotal and not highest then
        return
    end

    GameTooltip:AddLine(" ", 1, 1, 1, false)
    GameTooltip:AddLine("Characters", 0.75, 0.88, 1, false)

    if showTotal then
        local totalText
        if isGold then
            local gold = math.floor(TaskTracker.SumCharGoldCopper() / 10000)
            local s = TaskTracker.FormatGoldAmountForDisplay and TaskTracker.FormatGoldAmountForDisplay(gold) or tostring(gold)
            totalText = s .. " g"
        else
            totalText = formatQty(TaskTracker.SumCharCurrency(currencyId))
        end
        GameTooltip:AddDoubleLine("Total", totalText, 0.85, 0.85, 0.85, 1, 1, 1)
    end

    local listed = {}
    local function addCharLine(charKey)
        if not charKey or listed[charKey] then return end
        listed[charKey] = true
        local name = TaskTracker.GetCharDisplayName(charKey)
        local r, g, b = TaskTracker.GetCharClassColor(charKey)
        local status = TaskTracker.FormatCharTooltipStatus(charKey, entry, node)
        GameTooltip:AddDoubleLine(name, status, r, g, b, 1, 1, 1)
    end

    if highest then
        addCharLine(highest)
    end
    for i = 1, #opted do
        addCharLine(opted[i])
    end
end
