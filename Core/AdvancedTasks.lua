-- Core/AdvancedTasks.lua
-- Automated progress for user-defined advanced tasks (gold, achievements, items, quests, reputation)

TaskTracker = TaskTracker or {}

--- Bags plus the flags the caller passes. 12.1.5 removed the GetItemCount global.
function TaskTracker.ItemCount(itemId, includeBank, includeUses, includeReagentBank)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return 0 end
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, itemId, includeBank, includeUses, includeReagentBank)
        if ok then return tonumber(n) or 0 end
    end
    if GetItemCount then
        local ok, n = pcall(GetItemCount, itemId, includeBank, includeUses, includeReagentBank)
        if ok then return tonumber(n) or 0 end
    end
    return 0
end

TaskTracker._advancedRuntime = TaskTracker._advancedRuntime or {}
TaskTracker._advancedLastMoney = TaskTracker._advancedLastMoney or nil
TaskTracker._advancedMobKill = TaskTracker._advancedMobKill or {
    pending = {}, -- [destGUID] = true
    fallback = {
        pending = {}, -- [guid] = true (seen as target while in combat)
    },
    loot = {
        seen = {}, -- [corpseGUID] = true (avoid double-counting on repeated LOOT_READY)
    },
    collectableKillSeen = {}, -- [guid] = true (farm collectables; loot + kill dedup)
}

local RUNTIME = TaskTracker._advancedRuntime
local runtimeFor
local MOBKILL = TaskTracker._advancedMobKill
MOBKILL.collectableKillSeen = MOBKILL.collectableKillSeen or {} -- [guid] = true (loot + kill dedup)

local trim = TaskTracker.Trim

local function taskVisibleForAutomation(node)
    if not node or node.type ~= "task" then return false end
    if TaskTracker.TaskProgressIsLocked and TaskTracker.TaskProgressIsLocked(node) and node.liveShareTwoWay ~= true then
        return false
    end
    if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then
        return false
    end
    return true
end

--- Standing goal: Paragon (not a WoW `reaction` tier; classic bar tiers are 4–8).
TaskTracker.REP_STANDING_PARAGON = 9

function TaskTracker.IsAdvancedTask(node)
    return node and node.type == "task" and type(node.advanced) == "table" and node.advanced.type ~= nil
end

function TaskTracker.TaskHasExtraGoals(node)
    return node and type(node.extraGoals) == "table" and #node.extraGoals > 0
end

--- First advanced blob of `kind` on the task. The second return is the node or the extra-goal record that holds the count.
function TaskTracker.FirstAdvancedOfType(node, kind)
    if not node or not kind then return nil end
    local a = node.advanced
    if type(a) == "table" and a.type == kind then
        return a, node
    end
    local extras = node.extraGoals
    if type(extras) ~= "table" then return nil end
    for i = 1, #extras do
        local g = extras[i]
        local ga = g and g.advanced
        if type(ga) == "table" and ga.type == kind then
            return ga, g
        end
    end
end

--- Open this task's achievement in the default achievement window. No-op when the task has none.
function TaskTracker.OpenTaskAchievement(node)
    local adv = TaskTracker.FirstAdvancedOfType(node, "achievement")
    local raw = adv and adv.achievementId
    if raw == nil or (issecretvalue and issecretvalue(raw)) then return false end
    local id = tonumber(raw)
    if not id or id <= 0 then return false end
    if OpenAchievementFrameToAchievement then
        OpenAchievementFrameToAchievement(id)
        return true
    end
    if AchievementFrame_LoadUI then
        AchievementFrame_LoadUI()
    end
    if AchievementFrame_SelectAchievement then
        if (not AchievementFrame or not AchievementFrame:IsShown()) and AchievementFrame_ToggleAchievementFrame then
            AchievementFrame_ToggleAchievementFrame()
        end
        AchievementFrame_SelectAchievement(id)
        return true
    end
    return false
end

local function goalRecordCount(rec)
    local c = rec.taskUserValue
    if type(c) ~= "number" then
        c = rec.taskCount or 0
    end
    return c, rec.taskMax or 1
end

--- One goal (the task itself, or an extraGoals entry). Does not apply the task's All / Any rule.
function TaskTracker.GoalRecordIsDone(node, rec)
    if not rec then return false end
    if rec.doneOverride == "complete" then return true end
    if rec.doneOverride == "incomplete" then return false end
    local adv = rec.advanced
    if node and type(adv) == "table" and adv.type == "collectable" and TaskTracker.IsCollectableTaskJournalOwned then
        local saved = node.advanced
        node.advanced = adv
        local owned = TaskTracker.IsCollectableTaskJournalOwned(node)
        node.advanced = saved
        if owned then return true end
    end
    local c, m = goalRecordCount(rec)
    if m <= 1 then
        return rec.done and true or false
    end
    return c >= m
end

--- 1 is the task's own goal. 2+ is extraGoals[index - 1]. The first goal that is not finished, or 1 when all are.
function TaskTracker.FirstUnfinishedGoalIndex(node)
    if not TaskTracker.TaskHasExtraGoals(node) then return 1 end
    if not TaskTracker.GoalRecordIsDone(node, node) then return 1 end
    local extras = node.extraGoals
    for i = 1, #extras do
        if not TaskTracker.GoalRecordIsDone(node, extras[i]) then
            return i + 1
        end
    end
    return 1
end

function TaskTracker.GoalSlotRecord(node, index)
    if not node or index == 1 or index == nil then return node end
    local extras = node.extraGoals
    return extras and extras[index - 1] or nil
end

--- Point the task's goal fields at an extra goal for one call, then put them back.
--- Do not refresh the list inside `fn`.
function TaskTracker.WithGoalSlot(node, goalIndex, fn)
    local extras = node and node.extraGoals
    local goal = extras and extras[goalIndex]
    if not goal then
        return fn(node)
    end
    local saved = {
        advanced = node.advanced,
        taskMax = node.taskMax,
        taskCount = node.taskCount,
        taskUserValue = node.taskUserValue,
        done = node.done,
        doneOverride = node.doneOverride,
    }
    node.advanced = goal.advanced
    node.taskMax = goal.taskMax or 1
    node.taskCount = goal.taskCount or 0
    node.taskUserValue = goal.taskUserValue
    node.done = goal.done and true or false
    node.doneOverride = goal.doneOverride
    local prevKey = TaskTracker._ttGoalSlotKey
    TaskTracker._ttGoalSlotKey = tostring(node.id or "") .. ":" .. tostring(goalIndex)
    local ok, err = pcall(fn, node)
    goal.advanced = node.advanced
    goal.taskMax = node.taskMax
    goal.taskCount = node.taskCount
    goal.taskUserValue = node.taskUserValue
    goal.done = node.done and true or false
    goal.doneOverride = node.doneOverride
    node.advanced = saved.advanced
    node.taskMax = saved.taskMax
    node.taskCount = saved.taskCount
    node.taskUserValue = saved.taskUserValue
    node.done = saved.done
    node.doneOverride = saved.doneOverride
    TaskTracker._ttGoalSlotKey = prevKey
    if not ok then
        error(err)
    end
end

local ADV_INDEX_KINDS = { gold = true, achievement = true, item = true, quest = true, reputation = true, mob_kill = true, collectable = true }
local ADV_INDEX_EMPTY = {}

function TaskTracker.InvalidateAdvancedTaskIndex()
    TaskTracker._ttAdvIndex = nil
end

local function indexCollectableSets(idx, a)
    if not a or not TaskTracker.GetCollectableEntry then return end
    local ent = TaskTracker.GetCollectableEntry(a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
    local npcIds = TaskTracker.CollectableEntryNpcIds and TaskTracker.CollectableEntryNpcIds(ent)
    if npcIds then
        idx.anyCollectableNpc = true
        for _, id in ipairs(npcIds) do
            local n = tonumber(id)
            if n and n > 0 then
                idx.collectableNpcSet[n] = true
            end
        end
    end
    local objIds = TaskTracker.CollectableEntryLootObjectIds and TaskTracker.CollectableEntryLootObjectIds(ent)
    if objIds then
        idx.anyCollectableLootObj = true
        for _, id in ipairs(objIds) do
            local n = tonumber(id)
            if n and n > 0 then
                idx.collectableLootObjSet[n] = true
            end
        end
    end
end

function TaskTracker.RebuildAdvancedTaskIndex()
    local idx = {
        gold = {},
        achievement = {},
        item = {},
        quest = {},
        reputation = {},
        mob_kill = {},
        collectable = {},
        collectableNpcSet = {},
        collectableLootObjSet = {},
        anyCollectableNpc = false,
        anyCollectableLootObj = false,
        extra = {
            gold = {},
            achievement = {},
            item = {},
            quest = {},
            reputation = {},
            mob_kill = {},
            collectable = {},
        },
    }
    idx.subtextGold = {}
    idx.subtextLifetime = {}
    if TaskTracker.WalkTree then
        TaskTracker.WalkTree(function(node)
            if node.type ~= "task" then return end
            local sub = node.subtext
            if type(sub) == "table" then
                if sub.type == "gold" and sub.useTask ~= true then
                    idx.subtextGold[#idx.subtextGold + 1] = node
                end
                if sub.type == "mob_kill" and sub.showLifetime == true then
                    idx.subtextLifetime[#idx.subtextLifetime + 1] = node
                end
            end
            if TaskTracker.IsAdvancedTask(node) then
                local t = node.advanced.type
                local list = idx[t]
                if list then
                    list[#list + 1] = node
                end
                if t == "collectable" and TaskTracker.GetCollectableEntry then
                    local a = node.advanced
                    indexCollectableSets(idx, a)
                end
            end
            local extras = node.extraGoals
            if type(extras) == "table" then
                local nExtra = #extras
                if nExtra > 3 then nExtra = 3 end
                for gi = 1, nExtra do
                    local g = extras[gi]
                    local ga = g and g.advanced
                    local gt = type(ga) == "table" and ga.type
                    local list = gt and idx.extra[gt]
                    if list then
                        list[#list + 1] = { node = node, goalIndex = gi }
                        if gt == "collectable" then
                            indexCollectableSets(idx, ga)
                        end
                    end
                end
            end
        end)
    end
    TaskTracker._ttAdvIndex = idx
end

local function advNodes(kind)
    if not TaskTracker._ttAdvIndex then
        TaskTracker.RebuildAdvancedTaskIndex()
    end
    local idx = TaskTracker._ttAdvIndex
    if not idx then return ADV_INDEX_EMPTY end
    return idx[kind] or ADV_INDEX_EMPTY
end

local function eachAdvNode(kind, fn)
    for _, node in ipairs(advNodes(kind)) do
        fn(node)
    end
    local idx = TaskTracker._ttAdvIndex
    local extras = idx and idx.extra and idx.extra[kind]
    if not extras then return end
    for i = 1, #extras do
        local slot = extras[i]
        TaskTracker.WithGoalSlot(slot.node, slot.goalIndex, function()
            fn(slot.node)
        end)
    end
end

local function anyExtraAdv(kind, pred)
    local idx = TaskTracker._ttAdvIndex
    if not idx then return false end
    local extras = idx.extra and idx.extra[kind]
    if not extras then return false end
    for i = 1, #extras do
        local slot = extras[i]
        local hit = false
        TaskTracker.WithGoalSlot(slot.node, slot.goalIndex, function()
            hit = pred(slot.node) and true or false
        end)
        if hit then return true end
    end
    return false
end

function TaskTracker.AdvancedUsesManualLock(node)
    return TaskTracker.IsAdvancedTask(node) and node.taskUserValue ~= nil
end

function TaskTracker.ClearAdvancedManualLock(nodeID)
    local node = TaskTracker.FindNode(nodeID)
    if not node or node.type ~= "task" then return end
    if TaskTracker.RefuseLockedTaskProgress and TaskTracker.RefuseLockedTaskProgress(node) then return end
    node.taskUserValue = nil
    node.doneOverride = nil
    if TaskTracker.IsAdvancedTask(node) and node.advanced.type == "collectable" then
        TaskTracker.UpdateCollectableFromQuestFlags(node)
    end
    TaskTracker.SyncAdvancedTask(node)
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

local function goalDisplayedCount(rec)
    local maxCount = rec.taskMax or 1
    local shown = rec.taskUserValue
    if type(shown) ~= "number" then
        if maxCount <= 1 then
            return rec.done and 1 or 0
        end
        shown = rec.taskCount or 0
    end
    shown = math.floor(shown + 0.00001)
    if shown < 0 then shown = 0 end
    if maxCount <= 1 then
        return shown >= 1 and 1 or 0
    end
    return shown
end

local function goalTracksItself(node, rec, index)
    if index == 1 then
        return TaskTracker.IsAdvancedTask(node) and true or false
    end
    local adv = rec and rec.advanced
    return type(adv) == "table" and adv.type ~= nil
end

--- Shortcut: switch this task between a manual count and following the game.
--- The number on the row stays. The next game update still moves an automatic row.
function TaskTracker.ToggleTaskProgressMode(node)
    if not node or node.type ~= "task" then return end
    if TaskTracker.RefuseLockedTaskProgress and TaskTracker.RefuseLockedTaskProgress(node) then return end
    local index = 1
    if TaskTracker.TaskHasExtraGoals(node) then
        index = TaskTracker.FirstUnfinishedGoalIndex(node)
    end
    local rec = TaskTracker.GoalSlotRecord(node, index)
    if not rec or not goalTracksItself(node, rec, index) then return end
    local shown = goalDisplayedCount(rec)
    local maxCount = rec.taskMax or 1
    if rec.taskUserValue ~= nil then
        rec.taskUserValue = nil
        rec.taskCount = shown
        if maxCount <= 1 then
            rec.done = shown >= 1
        end
    else
        rec.taskUserValue = shown
        if maxCount <= 1 then
            rec.taskCount = shown
            rec.done = shown >= 1
        end
    end
    if TaskTracker.NotifyTaskProgressChanged then
        TaskTracker.NotifyTaskProgressChanged(node)
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

--- Effective reset schedule for advanced automation (gold option); tasks still use node.reset for DB resets unless overridden.
function TaskTracker.GetAdvancedEffectiveReset(node)
    if not TaskTracker.IsAdvancedTask(node) then return node and node.reset or "none" end
    local a = node.advanced
    if a.type == "gold" then
        if a.goldResetSource == "override" and a.resetOverride then
            return a.resetOverride
        end
        return node.reset or "none"
    end
    return node.reset or "none"
end

function TaskTracker.AdvancedOnPeriodReset(node, needDaily, needWeekly)
    if needWeekly and node and type(node.subtext) == "table"
        and node.subtext.type == "achievement" and node.subtext.achievementTrackMode == "weekly" then
        node.subtext.achievementWeekStart = nil
    end
    if node and type(node.subtext) == "table" and node.subtext.type == "gold" and node.subtext.useTask ~= true then
        local er = node.reset or "none"
        if (needDaily and er == "daily") or (needWeekly and er == "weekly") then
            node.subtext.goldPeriodCopper = 0
        end
    end
    local function resetSlot()
        if not TaskTracker.IsAdvancedTask(node) then return end
        local a = node.advanced

        -- Gold: optional reset schedule independent of node.reset when overriding.
        if a.type == "gold" then
            local er = TaskTracker.GetAdvancedEffectiveReset(node)
            if (needDaily and er == "daily") or (needWeekly and er == "weekly") then
                a.goldAutoCopper = 0
                node.taskCount = 0
                node.done = false
                node.taskUserValue = nil
                node.doneOverride = nil
            end
        end

        -- Anchors / snapshots for other types follow the task's node.reset (weekly/daily).
        local periodHit = (needDaily and (node.reset == "daily"))
            or (needWeekly and (node.reset == "weekly"))
        if not periodHit then return end

        if a.type == "achievement" then
            a.weekStartAchTotal = nil
        elseif a.type == "reputation" and a.repGoalType == "weekly_gain" then
            a.weekStartRepValue = nil
        elseif a.type == "item" then
            a.itemAutoCount = 0
            local rt = runtimeFor(node.id)
            if rt and (a.itemTrackMode or "earned") == "earned" then
                rt.itemsInitialized = nil
                rt.lastItemTotals = nil
                rt.currenciesInitialized = nil
                rt.lastCurrencyTotals = nil
            end
        elseif a.type == "quest" then
            local ids = a.questIds
            local rst = node.reset or "none"
            local pool = type(ids) == "table" and #ids > 1 and rst ~= "none" and rst ~= "temporary"
            a.questWeekStartComplete = nil
            a.questPeriodCredited = nil
            a.questPeriodOrphanCredits = nil
            a.questPeriodTurnIns = nil
            a.questPeriodRepeatCounts = nil
            a.questPeriodBaselineFrozen = nil
            a.questPeriodSeen = nil
            if pool and node.collectionFarmId and node.liveShareRole ~= "receiver" then
                a.questPeriodBaseline = {}
                a.questPeriodBaselineAtReset = true
            else
                a.questPeriodBaseline = nil
                a.questPeriodBaselineAtReset = nil
            end
        elseif a.type == "mob_kill" then
            a.mobAutoCount = 0
            node.taskCount = 0
            node.done = false
            node.taskUserValue = nil
            node.doneOverride = nil
        elseif a.type == "mplus_hint" then
            node.taskCount = 0
            node.done = false
            node.taskUserValue = nil
            node.doneOverride = nil
        elseif a.type == "collectable" then
            a.collectableInit = nil
            a.collectableCredited = nil
            a.collectableAutoCount = 0
            a.collectableFishAttempts = 0
            local rt = runtimeFor(node.id)
            if rt then
                rt.itemsInitialized = nil
                rt.lastItemTotals = nil
            end
        end
    end
    resetSlot()
    local extras = node and node.extraGoals
    if type(extras) == "table" then
        local nExtra = #extras
        if nExtra > 3 then nExtra = 3 end
        for i = 1, nExtra do
            if extras[i] and type(extras[i].advanced) == "table" then
                TaskTracker.WithGoalSlot(node, i, resetSlot)
            end
        end
    end
end

function TaskTracker.FormatGoldAmountForDisplay(amountGold)
    local n = math.floor(tonumber(amountGold) or 0)
    if n < 0 then n = 0 end
    local s = tostring(n)
    while true do
        local k
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

function TaskTracker.GetAdvancedTaskSubtitle(node)
    if node and type(node.generatedSubtitle) == "string" and node.generatedSubtitle ~= "" then
        return node.generatedSubtitle
    end
    if TaskTracker.FormatTaskSubtext and not (TaskTrackerDB and TaskTrackerDB.subtextInTooltip) then
        local chosen = TaskTracker.FormatTaskSubtext(node)
        if type(chosen) == "string" and chosen ~= "" then
            return chosen
        end
    end
    if node and node.collectionFarmId == "s1_weekly_abundance" and TaskTracker.AbundanceShardLine then
        local text = TaskTracker.AbundanceShardLine()
        if type(text) == "string" and text ~= "" then
            return text
        end
    end
    if TaskTracker.IsAdvancedTask(node) and node.advanced.type == "mplus_hint" then
        local k = node.advanced.mplusHintKind
        if k == "end_dungeon" and TaskTracker.GetMPlusEndDungeonSubtitle then
            return TaskTracker.GetMPlusEndDungeonSubtitle()
        elseif k == "vault" and TaskTracker.GetMPlusVaultHintSubtitle then
            return TaskTracker.GetMPlusVaultHintSubtitle()
        end
        return nil
    end
    if not TaskTracker.IsAdvancedTask(node) or node.advanced.type ~= "reputation" then
        return nil
    end
    local a = node.advanced
    if a.repGoalType == "standing" then
        return nil
    end
    local fd = TaskTracker.GetAdvancedFactionData(a.repFactionId, a.repFactionName)
    if not fd or not fd.name then return nil end
    if fd.isMajorFaction and fd.renownLevel then
        return string.format("%s — Renown %s", fd.name, tostring(fd.renownLevel))
    end
    if fd.isParagon and fd.paragonCycleValue ~= nil then
        local th = tonumber(fd.paragonThreshold) or 10000
        local n = tonumber(fd.paragonCycleCount) or 0
        if n > 0 then
            return string.format("%s — Paragon %s/%s (+%s)", fd.name, tostring(fd.paragonCycleValue), tostring(th), tostring(n))
        end
        return string.format("%s — Paragon %s/%s", fd.name, tostring(fd.paragonCycleValue), tostring(th))
    end
    local val = fd.currentStanding or fd.currentRep or 0
    local react = fd.reaction or 0
    local standingLabel = _G["FACTION_STANDING_LABEL" .. react] or ("Tier " .. tostring(react))
    return string.format("%s — %s (%s)", fd.name, standingLabel, tostring(val))
end

local RARITY_DROP_TTL = 4
local rarityDropCache = { at = 0, byId = {} }

local function rarityItemMatchesId(item, itemId)
    if type(item) ~= "table" then return false end
    if tonumber(item.itemId) == itemId or tonumber(item.itemId2) == itemId then
        return true
    end
    local collected = item.collectedItemId
    if type(collected) == "table" then
        for _, id in pairs(collected) do
            if tonumber(id) == itemId then return true end
        end
        return false
    end
    return tonumber(collected) == itemId
end

local function rarityScanTable(tbl, itemId)
    if type(tbl) ~= "table" then return nil end
    for _, item in pairs(tbl) do
        if rarityItemMatchesId(item, itemId) then return item end
    end
    return nil
end

--- Rarity indexes live rows in Rarity.items[itemId]. Profile groups store those
--- rows directly (groups.mounts[name]), not under a nested items table.
local function rarityItemById(itemId)
    local R = _G.Rarity
    if not R then return nil end
    local indexed = R.items and R.items[itemId]
    if type(indexed) == "table" then return indexed end
    local groups = R.db and R.db.profile and R.db.profile.groups
    if type(groups) ~= "table" then return nil end
    for _, group in pairs(groups) do
        if type(group) == "table" then
            local found = rarityScanTable(group, itemId) or rarityScanTable(group.items, itemId)
            if found then return found end
        end
    end
    return nil
end

local function rarityDropLine(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return nil end
    local now = GetTime and GetTime() or 0
    if (now - rarityDropCache.at) >= RARITY_DROP_TTL then
        if wipe then wipe(rarityDropCache.byId) else rarityDropCache.byId = {} end
        rarityDropCache.at = now
    end
    local cached = rarityDropCache.byId[itemId]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local item = rarityItemById(itemId)
    local line = false
    if type(item) == "table" then
        local attempts = tonumber(item.attempts) or 0
        if item.lastAttempts ~= nil then
            attempts = attempts - (tonumber(item.lastAttempts) or 0)
        end
        if attempts < 0 then attempts = 0 end
        local oneIn = tonumber(item.chance)
        local fmt = TaskTracker.FormatGoldAmountForDisplay
        local collection = item.collectedItemId ~= nil and item.itemId == nil
        if collection and oneIn and oneIn >= 1 then
            line = string.format("%s/%s", fmt(attempts), fmt(math.floor(oneIn)))
        elseif oneIn and oneIn >= 1 then
            line = string.format("%s attempts, 1 in %s", fmt(attempts), fmt(math.floor(oneIn)))
        elseif attempts > 0 then
            line = string.format("%s attempts", fmt(attempts))
        end
    end
    rarityDropCache.byId[itemId] = line
    if line == false then return nil end
    return line
end

local function commaCount(n)
    return TaskTracker.FormatGoldAmountForDisplay(math.floor(tonumber(n) or 0))
end

local function subtextFactionLine(s)
    local mode = s.repDisplay or "paragon"
    local fd = TaskTracker.GetAdvancedFactionData(s.repFactionId, s.repFactionName)
    if not fd or not fd.name then return nil end
    if mode == "renown" then
        local lvl = tonumber(fd.renownLevel)
        if not lvl then return nil end
        local cap = tonumber(fd.renownMaxLevel)
        if cap and cap > 0 then
            return string.format("%s — Renown %s/%s", fd.name, commaCount(lvl), commaCount(cap))
        end
        return string.format("%s — Renown %s", fd.name, commaCount(lvl))
    end
    if mode == "standing" then
        if (tonumber(s.repFactionId) or 0) == 2838 and TaskTracker.AqirEnclaveReputationBar then
            local cur, cap = TaskTracker.AqirEnclaveReputationBar()
            local rank = fd.friendshipRank or "Exalted"
            return string.format("%s %s/%s", rank, commaCount(cur), commaCount(cap))
        end
        if fd.friendshipStanding ~= nil then
            local total = fd.friendshipStanding
            local bottom = tonumber(fd.friendshipThreshold) or 0
            local nxt = tonumber(fd.friendshipNext)
            local rank = fd.friendshipRank or "Standing"
            if nxt and nxt > bottom then
                -- `standing` is the lifetime total when it sits on or above the
                -- rank floor. Below that floor it is progress inside the rank.
                local into = (total < bottom) and total or (total - bottom)
                if into < 0 then into = 0 end
                return string.format("%s %s/%s", rank, commaCount(into), commaCount(nxt - bottom))
            end
            local cap = tonumber(fd.friendshipMax) or total
            return string.format("%s %s/%s", rank, commaCount(total), commaCount(cap))
        end
        local val = fd.currentStanding or fd.currentRep or 0
        local react = fd.reaction or 0
        local standingLabel = _G["FACTION_STANDING_LABEL" .. react] or ("Tier " .. tostring(react))
        return string.format("%s — %s (%s)", fd.name, standingLabel, commaCount(val))
    end
    if not fd.isParagon or fd.paragonCycleValue == nil then
        return fd.name .. " — not Paragon yet"
    end
    local th = tonumber(fd.paragonThreshold) or 10000
    if th < 1 then th = 10000 end
    local cur = tonumber(fd.paragonCycleValue) or 0
    if fd.paragonHasRewardPending then
        cur = th
    end
    return string.format("%s — %s/%s", fd.name, commaCount(cur), commaCount(th))
end

local function subtextMobIds(node, s)
    if s.useTask == true then
        local mobAdv = TaskTracker.FirstAdvancedOfType(node, "mob_kill")
        if mobAdv then return mobAdv.mobIds end
        local collAdv = TaskTracker.FirstAdvancedOfType(node, "collectable")
        if collAdv and TaskTracker.GetCollectableEntry then
            local ent = TaskTracker.GetCollectableEntry(
                collAdv.collectableExpansion,
                collAdv.collectableCategory,
                collAdv.collectableEntryId)
            local ids = TaskTracker.CollectableEntryNpcIds and TaskTracker.CollectableEntryNpcIds(ent)
            if ids then return ids end
        end
    end
    return s.mobIds
end

local function subtextDropItemId(node, s)
    local itemId = tonumber(s.dropItemId)
    local collAdv = s.useTask == true and TaskTracker.FirstAdvancedOfType(node, "collectable") or nil
    if (not itemId or itemId <= 0) and collAdv then
        local ent = TaskTracker.GetCollectableEntry
            and TaskTracker.GetCollectableEntry(collAdv.collectableExpansion, collAdv.collectableCategory, collAdv.collectableEntryId)
        itemId = tonumber(ent and ent.itemId)
    end
    if itemId and itemId > 0 then return itemId end
    return nil
end

--- Rarity's attempt count is the lifetime total. When that record is loaded, skip our kill counter.
local function subtextRarityLine(node, s)
    if s.showDrop ~= true then return nil end
    local itemId = subtextDropItemId(node, s)
    if not itemId then return nil end
    return rarityDropLine(itemId)
end

local function subtextKillLine(node, s)
    local parts = {}
    local rarityLine = subtextRarityLine(node, s)
    if s.showLifetime == true and not rarityLine then
        local farmAdv, farmHolder = nil, nil
        if s.useTask == true then
            farmAdv, farmHolder = TaskTracker.FirstAdvancedOfType(node, "collectable")
        end
        local n = tonumber(s.lifetimeKills) or 0
        if farmAdv then
            n = tonumber(farmAdv.collectableAutoCount)
            if n == nil then
                n = tonumber((farmHolder or node).taskCount) or 0
            end
        end
        parts[#parts + 1] = commaCount(n) .. " kills"
    end
    if rarityLine then
        parts[#parts + 1] = rarityLine
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " - ")
end

local function subtextCollectableLine(node, s)
    local exp, cat, eid = s.collectableExpansion, s.collectableCategory, s.collectableEntryId
    local collAdv, collHolder = nil, nil
    if s.useTask == true then
        collAdv, collHolder = TaskTracker.FirstAdvancedOfType(node, "collectable")
    end
    if collAdv then
        exp, cat, eid = collAdv.collectableExpansion, collAdv.collectableCategory, collAdv.collectableEntryId
    end
    local ent = TaskTracker.GetCollectableEntry and TaskTracker.GetCollectableEntry(exp, cat, eid)
    local owned = false
    if ent and TaskTracker.IsCatalogCollectableOwned then
        owned = TaskTracker.IsCatalogCollectableOwned(ent, cat) == true
    end
    if owned then return "Owned" end
    if collAdv then
        local holder = collHolder or node
        local cur = math.max(0, tonumber(holder.taskCount) or 0)
        local cap = math.max(1, tonumber(holder.taskMax) or 1)
        if cap > 1 then
            return commaCount(cur) .. "/" .. commaCount(cap)
        end
    end
    if ent then return "Not owned" end
    return nil
end

local function subtextItemLine(node, s)
    local kind = s.itemKind or "item"
    local ids = s.itemIds
    if s.useTask == true then
        local itemAdv = TaskTracker.FirstAdvancedOfType(node, "item")
        if itemAdv then
            kind = itemAdv.itemKind or "item"
            ids = itemAdv.itemIds
        end
    end
    if type(ids) ~= "table" or #ids == 0 then return nil end
    local total = 0
    if kind == "currency" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        for _, id in ipairs(ids) do
            local cid = tonumber(id)
            if cid and cid > 0 then
                local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, cid)
                if ok and type(info) == "table" then
                    total = total + (tonumber(info.quantity) or 0)
                end
            end
        end
    else
        for _, id in ipairs(ids) do
            local iid = tonumber(id)
            if iid and iid > 0 then
                total = total + TaskTracker.ItemCount(iid, true, false, true)
            end
        end
    end
    if s.itemAttTotal == true then
        local need, any = 0, false
        if kind == "currency" and TaskTracker.AttCurrencyRequiredTotal then
            for _, id in ipairs(ids) do
                local n = TaskTracker.AttCurrencyRequiredTotal(tonumber(id))
                if type(n) == "number" then
                    any = true
                    need = need + n
                end
            end
        end
        if any then
            return commaCount(total) .. "/" .. commaCount(need)
        end
        return commaCount(total) .. "/—"
    end
    local goal = tonumber(s.itemGoal)
    if goal and goal > 0 then
        return commaCount(total) .. "/" .. commaCount(goal)
    end
    return commaCount(total)
end

local function subtextQuestLine(node, s)
    local ids = s.questIds
    local questAdv = nil
    if s.useTask == true then
        questAdv = TaskTracker.FirstAdvancedOfType(node, "quest")
        if questAdv then ids = questAdv.questIds end
    end
    if type(ids) ~= "table" or #ids == 0 then return nil end
    local base = questAdv and questAdv.questPeriodBaseline
    local usePeriod = type(base) == "table"
    local credited = usePeriod and questAdv.questPeriodCredited or nil
    local turns = usePeriod and questAdv.questPeriodTurnIns or nil
    local done, n = 0, 0
    for _, qid in ipairs(ids) do
        qid = tonumber(qid)
        if qid and qid > 0 then
            n = n + 1
            local key = tostring(qid)
            if usePeriod then
                if (type(credited) == "table" and credited[key])
                    or (type(turns) == "table" and turns[key]) then
                    done = done + 1
                end
            elseif C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
                local ok, flagged = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
                if ok and flagged then done = done + 1 end
            end
        end
    end
    if n == 0 then return nil end
    return commaCount(done) .. "/" .. commaCount(n)
end

local function subtextAchievementChecklist(achId)
    if not GetAchievementNumCriteria or not GetAchievementCriteriaInfo then return nil, nil end
    local okN, num = pcall(GetAchievementNumCriteria, achId)
    num = okN and tonumber(num) or 0
    if not num or num <= 0 then return nil, nil end
    local got = 0
    for i = 1, num do
        local okC, _, _, critDone = pcall(GetAchievementCriteriaInfo, achId, i)
        if okC and critDone then got = got + 1 end
    end
    return got, num
end

local achievementNameCache = {}

local function achievementDisplayName(achId)
    local cached = achievementNameCache[achId]
    if cached ~= nil then return cached end
    if not GetAchievementInfo then return nil end
    local ok, a, b = pcall(GetAchievementInfo, achId)
    local name
    if ok then
        if type(a) == "table" then
            name = a.name
        elseif type(b) == "string" then
            name = b
        elseif type(a) == "string" then
            name = a
        end
    end
    if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then
        return nil
    end
    achievementNameCache[achId] = name
    return name
end

local function withAchievementName(achId, body)
    if type(body) ~= "string" or body == "" then return nil end
    local name = achievementDisplayName(achId)
    if not name then return body end
    return name .. " - " .. body
end

local function subtextAchievementLine(node, s)
    local achId = tonumber(s.achievementId)
    local critIdx = tonumber(s.achievementCriteriaIndex) or 0
    if s.useTask == true then
        local achAdv = TaskTracker.FirstAdvancedOfType(node, "achievement")
        if achAdv then
            achId = tonumber(achAdv.achievementId)
            critIdx = tonumber(achAdv.achievementCriteriaIndex) or 0
        end
    end
    if not achId or achId <= 0 or not GetAchievementInfo then return nil end
    local mode = s.achievementTrackMode == "weekly" and "weekly" or "game"
    local raw, cap
    if critIdx >= 1 and TaskTracker.GetAchievementCriterionCurMax then
        local cur, mx = TaskTracker.GetAchievementCriterionCurMax(achId, critIdx)
        raw = tonumber(cur) or 0
        cap = tonumber(mx) or 0
    else
        raw, cap = subtextAchievementChecklist(achId)
    end
    if mode == "weekly" then
        if type(raw) ~= "number" then return nil end
        if s.achievementWeekStart == nil then
            s.achievementWeekStart = raw
        end
        local gained = math.max(0, raw - (tonumber(s.achievementWeekStart) or 0))
        local goal = tonumber(s.achievementGoal)
        if goal and goal > 0 then
            return withAchievementName(achId, commaCount(gained) .. "/" .. commaCount(goal))
        end
        return withAchievementName(achId, commaCount(gained))
    end
    if type(raw) == "number" and type(cap) == "number" and cap > 0 then
        return withAchievementName(achId, commaCount(raw) .. "/" .. commaCount(cap))
    end
    local ok, _, _, _, completed, _, _, _, _, _, _, _, _, wasEarnedByMe = pcall(GetAchievementInfo, achId)
    if ok and (completed or wasEarnedByMe) then
        return withAchievementName(achId, "Earned")
    end
    return withAchievementName(achId, "Not earned")
end

local function subtextGoldLine(node, s)
    if s.useTask == true then
        local goldAdv, goldHolder = TaskTracker.FirstAdvancedOfType(node, "gold")
        if goldAdv then
            return commaCount((goldHolder or node).taskCount) .. "g this period"
        end
    end
    local copper = math.max(0, tonumber(s.goldPeriodCopper) or 0)
    return commaCount(math.floor(copper / 10000)) .. "g this period"
end

--- Shard of Dundun (currency 3376). Abundance needs 8. The weekly quest adds 2, so 6 held is enough.
--- Returns "x+2/8 Shard of Dundun" and true when x >= 6. A secret quantity is a dash and not ready.
function TaskTracker.AbundanceShardLine()
    local qty
    local name = "Shard of Dundun"
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, 3376)
        if ok and type(info) == "table" then
            local n = info.name
            if type(n) == "string" and n ~= "" and not (issecretvalue and issecretvalue(n)) then
                name = n
            end
            local q = info.quantity
            if not (issecretvalue and issecretvalue(q)) then
                q = tonumber(q)
                if q then
                    if q < 0 then q = 0 end
                    qty = math.floor(q)
                end
            end
        end
    end
    local count = qty and tostring(qty) or "—"
    return count .. "+2/8 " .. name, qty ~= nil and qty >= 6
end

function TaskTracker.FormatTaskSubtext(node)
    local s = node and node.subtext
    if type(s) ~= "table" or type(s.type) ~= "string" or s.type == "" or s.type == "none" then
        return nil
    end
    if s.type == "reputation" then return subtextFactionLine(s) end
    if s.type == "mob_kill" then return subtextKillLine(node, s) end
    if s.type == "collectable" then return subtextCollectableLine(node, s) end
    if s.type == "item" then return subtextItemLine(node, s) end
    if s.type == "quest" then return subtextQuestLine(node, s) end
    if s.type == "achievement" then return subtextAchievementLine(node, s) end
    if s.type == "gold" then return subtextGoldLine(node, s) end
    return nil
end

function TaskTracker.SubtextMobIds(node)
    local s = node and node.subtext
    if type(s) ~= "table" then return nil end
    return subtextMobIds(node, s)
end

--- Normalize faction text for matching (handles "X Tribe", "The X", spacing).
local function normalizeFactionSearchName(s)
    s = trim(s or ""):lower()
    s = s:gsub("^the%s+", ""):gsub("%s+tribe$", ""):gsub("%s+", " ")
    return s
end

--- True if user-typed name is exact, substring, or one small typo from the game name (e.g. "Armani" vs "Amani").
local function factionNameCloseEnough(userInput, gameFactionName)
    if not userInput or not gameFactionName then return false end
    local u, f = normalizeFactionSearchName(userInput), normalizeFactionSearchName(gameFactionName)
    if u == "" or f == "" or #u < 3 or #f < 3 then return false end
    if u == f then return true end
    if f:find(u, 1, true) or u:find(f, 1, true) then return true end
    if math.abs(#u - #f) <= 1 then
        if #u == #f then
            local diff = 0
            for i = 1, #u do
                if u:byte(i) ~= f:byte(i) then diff = diff + 1 end
            end
            return diff <= 1
        end
        local short, long = (#u < #f) and u or f, (#u < #f) and f or u
        for skip = 1, #long do
            if long:sub(1, skip - 1) .. long:sub(skip + 1) == short then
                return true
            end
        end
    end
    return false
end

-- GetFactionDataByIndex scans the full faction list; subtitle + sync can call this often during list paints.
local FACTION_DATA_CACHE = {}
local FACTION_DATA_TTL = 2.5

function TaskTracker.InvalidateAdvancedFactionDataCache()
    wipe(FACTION_DATA_CACHE)
end

function TaskTracker.GetAdvancedFactionData(factionId, factionNameFallback)
    local fnKey = trim(factionNameFallback or ""):lower()
    local cacheKey = ("%s\31%s"):format(tostring(tonumber(factionId) or 0), fnKey)
    local now = GetTime()
    local slot = FACTION_DATA_CACHE[cacheKey]
    if slot and (now - slot.t) < FACTION_DATA_TTL then
        if slot.v == false then return nil end
        return slot.v
    end
    local function store(v)
        FACTION_DATA_CACHE[cacheKey] = { v = (v == nil) and false or v, t = GetTime() }
        return v
    end

    local function secret(v)
        return issecretvalue and issecretvalue(v)
    end
    local function publicNumber(v)
        if v == nil or secret(v) then return nil end
        return tonumber(v)
    end
    -- A header flag that is secret must not be compared. Treating it as a header
    -- drops the row. The Labyrinth faction is only on the major-faction API.
    local function blocksAsHeader(fd)
        if not fd then return true end
        if secret(fd.isHeader) then return false end
        return fd.isHeader == true
    end

    local function mapFd(fd)
        if not fd or blocksAsHeader(fd) then return nil end
        local val = publicNumber(fd.currentStanding)
        if val == nil then val = publicNumber(fd.currentRep) or 0 end
        local name = fd.name
        if secret(name) or type(name) ~= "string" then name = nil end
        return {
            name              = name,
            currentStanding   = val,
            currentRep        = val,
            reaction          = publicNumber(fd.reaction),
            factionID         = publicNumber(fd.factionID),
            nextReactionThreshold = publicNumber(fd.nextReactionThreshold),
            currentReactionThreshold = publicNumber(fd.currentReactionThreshold),
        }
    end

    local function tryAttachMajorFactionInfo(out, id)
        if not out or not id or id <= 0 then return out end
        if not C_MajorFactions or not C_MajorFactions.GetMajorFactionData then return out end
        local ok, mfd = pcall(C_MajorFactions.GetMajorFactionData, id)
        if not ok or type(mfd) ~= "table" then return out end
        if secret(mfd.renownLevel) or mfd.renownLevel == nil then return out end
        out.isMajorFaction = true
        out.renownLevel = tonumber(mfd.renownLevel) or 0
        out.renownMaxLevel = tonumber(mfd.maxLevel or mfd.maxRenownLevel or mfd.maxRenownLevelAvailable) or nil
        out.renownReputationEarned = tonumber(mfd.renownReputationEarned or mfd.renownReputation) or nil
        out.renownLevelThreshold = tonumber(mfd.renownLevelThreshold or mfd.renownLevelMaxValue) or nil
        if type(mfd.name) == "string" and mfd.name ~= "" then
            out.name = mfd.name
        end
        return out
    end

    local function tryAttachFriendshipInfo(out, id)
        if not out or not id or id <= 0 then return out end
        if not C_GossipInfo or not C_GossipInfo.GetFriendshipReputation then return out end
        local ok, a, b, c, d, e, f, g, h, i = pcall(C_GossipInfo.GetFriendshipReputation, id)
        if not ok or a == nil then return out end
        local info = a
        if type(a) ~= "table" then
            info = {
                friendshipFactionID = a,
                standing = b,
                maxRep = c,
                reaction = g,
                reactionThreshold = h,
                nextThreshold = i,
            }
            if type(d) == "string" then info.name = d end
            if type(e) == "string" then info.text = e end
        end
        local fid = publicNumber(info.friendshipFactionID)
        if not fid or fid <= 0 then return out end
        local standing = publicNumber(info.standing)
        if standing == nil then return out end
        out.friendshipStanding = standing
        out.friendshipThreshold = publicNumber(info.reactionThreshold)
        out.friendshipNext = publicNumber(info.nextThreshold)
        out.friendshipMax = publicNumber(info.maxRep)
        local rank = info.reaction
        if type(rank) == "string" and rank ~= "" and not secret(rank) then
            out.friendshipRank = rank
        end
        return out
    end

    local function tryAttachParagonInfo(out, id)
        if not out or not id or id <= 0 then return out end
        if not C_Reputation or not C_Reputation.IsFactionParagon or not C_Reputation.GetFactionParagonInfo then
            return out
        end
        local okP, isParagon = pcall(C_Reputation.IsFactionParagon, id)
        if not okP or not isParagon then return out end
        local okI, currentValue, threshold, rewardQuestID, hasRewardPending = pcall(C_Reputation.GetFactionParagonInfo, id)
        if not okI then return out end
        out.isParagon = true
        local total = tonumber(currentValue) or 0
        local th = tonumber(threshold) or 10000
        if th < 1 then th = 10000 end
        out.paragonValue = total
        out.paragonThreshold = th
        out.paragonCycleCount = math.floor(total / th)
        out.paragonCycleValue = total % th
        out.paragonRewardQuestID = tonumber(rewardQuestID) or nil
        out.paragonHasRewardPending = hasRewardPending == true
        return out
    end

    local function storeMajorShell(id)
        id = tonumber(id)
        if not id or id <= 0 then return nil end
        local m = {
            factionID = id,
            currentStanding = 0,
            currentRep = 0,
            reaction = 0,
        }
        tryAttachMajorFactionInfo(m, id)
        if not m.isMajorFaction then return nil end
        tryAttachParagonInfo(m, id)
        return store(m)
    end

    if C_Reputation and C_Reputation.GetFactionDataByID and factionId and factionId > 0 then
        local ok, fd = pcall(C_Reputation.GetFactionDataByID, factionId)
        if ok then
            local m = mapFd(fd)
            if m then
                tryAttachMajorFactionInfo(m, tonumber(m.factionID) or tonumber(factionId))
                tryAttachFriendshipInfo(m, tonumber(m.factionID) or tonumber(factionId))
                tryAttachParagonInfo(m, tonumber(m.factionID) or tonumber(factionId))
                return store(m)
            end
        end
        -- Classic reputation row is missing or a header. Renown still lives on
        -- C_MajorFactions (Labyrinth of Kindo'jan, faction 2836).
        local major = storeMajorShell(factionId)
        if major then return major end
    end
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        local okNum, num = pcall(C_Reputation.GetNumFactions)
        if okNum and num then
            local bestFuzzy
            for i = 1, num do
                local ok, fd = pcall(C_Reputation.GetFactionDataByIndex, i)
                if ok and fd and not blocksAsHeader(fd) and publicNumber(fd.factionID) then
                    if factionId and factionId > 0 and fd.factionID == factionId then
                        local m = mapFd(fd)
                        if m then
                            tryAttachMajorFactionInfo(m, tonumber(m.factionID) or tonumber(factionId))
                            tryAttachFriendshipInfo(m, tonumber(m.factionID) or tonumber(factionId))
                            tryAttachParagonInfo(m, tonumber(m.factionID) or tonumber(factionId))
                            return store(m)
                        end
                    elseif factionNameFallback and fd.name then
                        if fd.name:lower() == factionNameFallback:lower() then
                            local m = mapFd(fd)
                            if m then
                                tryAttachMajorFactionInfo(m, tonumber(m.factionID) or tonumber(factionId))
                                tryAttachFriendshipInfo(m, tonumber(m.factionID) or tonumber(factionId))
                                tryAttachParagonInfo(m, tonumber(m.factionID) or tonumber(factionId))
                                return store(m)
                            end
                        elseif factionNameCloseEnough(factionNameFallback, fd.name) then
                            bestFuzzy = bestFuzzy or fd
                        end
                    end
                end
            end
            if bestFuzzy then
                local m = mapFd(bestFuzzy)
                if m then
                    tryAttachMajorFactionInfo(m, tonumber(m.factionID))
                    tryAttachFriendshipInfo(m, tonumber(m.factionID))
                    tryAttachParagonInfo(m, tonumber(m.factionID))
                end
                return store(m)
            end
        end
    end
    return storeMajorShell(factionId)
end

--- Bottom of each classic reaction tier (rep points at which that standing begins). Used when the goal is several tiers away.
local STANDING_MIN_REP_CLASSIC = {
    [1] = -42000,
    [2] = -6000,
    [3] = -3000,
    [4] = 0,
    [5] = 3000,
    [6] = 9000,
    [7] = 21000,
    [8] = 42000,
}

--- Reputation total required to first reach `targetReaction` (classic bar, non-Paragon).
local function classicStandingGoalThreshold(fd, targetReaction)
    targetReaction = math.floor(tonumber(targetReaction) or 0)
    if targetReaction <= 0 or targetReaction == TaskTracker.REP_STANDING_PARAGON then
        return nil
    end
    local react = math.floor(tonumber(fd.reaction) or 0)
    if react + 1 == targetReaction then
        local nxt = tonumber(fd.nextReactionThreshold)
        if nxt then return nxt end
    end
    return STANDING_MIN_REP_CLASSIC[targetReaction]
end

local function getFactionWeeklyProgressValue(fd)
    if not fd then return 0 end
    if fd.isMajorFaction then
        -- Renown "rep" resets each level; make it monotonic with a large multiplier.
        local lvl = tonumber(fd.renownLevel) or 0
        -- At max renown, earned may stop updating; if the faction is Paragon, use the Paragon counter.
        local earned = tonumber(fd.renownReputationEarned)
        if (earned == nil or earned == 0) and fd.isParagon and fd.paragonValue ~= nil then
            earned = tonumber(fd.paragonValue) or 0
        end
        earned = tonumber(earned) or 0
        return lvl * 1000000 + earned
    end
    if fd.isParagon and fd.paragonValue ~= nil then
        -- Paragon factions cap at Exalted; use Paragon value as the monotonic progress source.
        return tonumber(fd.paragonValue) or 0
    end
    return tonumber(fd.currentStanding or fd.currentRep) or 0
end

-- The stored cursor is renown level * 1,000,000 plus reputation inside the rank.
-- Subtracting those cursors counts each rank-up as 1,000,000. A finished rank is
-- renownLevelThreshold (2100 for the Labyrinth), plus whatever is already in the new rank.
local function majorFactionWeeklyGain(startValue, curValue, threshold)
    startValue = tonumber(startValue) or 0
    curValue = tonumber(curValue) or 0
    threshold = tonumber(threshold)
    if not threshold or threshold < 1 or threshold >= 1000000 then
        return math.max(0, curValue - startValue)
    end
    if startValue < 1000000 and curValue < 1000000 then
        return math.max(0, curValue - startValue)
    end
    local sLvl = math.floor(startValue / 1000000)
    local cLvl = math.floor(curValue / 1000000)
    local sEarned = startValue - sLvl * 1000000
    local cEarned = curValue - cLvl * 1000000
    if cLvl < sLvl then return 0 end
    if cLvl == sLvl then
        return math.max(0, cEarned - sEarned)
    end
    return math.max(0, (cLvl - sLvl) * threshold - sEarned + cEarned)
end

local function formatFactionValidationMessage(inputText, goalType, standingTarget)
    if not inputText or trim(inputText) == "" then
        return "Enter a faction ID, shift-click a faction link, or type the faction name."
    end
    local fid, fname = TaskTracker.ParseFactionIdFromText(inputText)
    local fd = TaskTracker.GetAdvancedFactionData(fid, fname)
    if not fd or not fd.name then
        local idText = fid and tostring(fid) or "(none)"
        local nmText = (fname and fname ~= "") and fname or "(none)"
        return string.format("|cffff4444Not found|r\nFaction ID: %s\nName: %s\n\nTry shift-clicking the faction from the reputation UI, or use the numeric ID.", idText, nmText)
    end
    local header = string.format("|cff00ff00Valid|r — %s (ID %s)", fd.name, tostring(fd.factionID or fid or 0))
    if goalType == "standing" then
        local tgt = tonumber(standingTarget) or 0
        if fd.isMajorFaction then
            if tgt == TaskTracker.REP_STANDING_PARAGON then
                return header .. "\n\n|cffff4444Paragon|r — Use Renown level for major factions, not Paragon standing."
            end
            if tgt <= 0 then
                return header .. "\n\n|cffff4444Standing target invalid|r — For Renown factions, set a Renown level (e.g. 10)."
            end
            return header .. string.format("\n\nStanding: Renown\nCurrent: %s\nTarget: %s", tostring(fd.renownLevel or "?"), tostring(tgt))
        end
        if tgt == TaskTracker.REP_STANDING_PARAGON then
            local th = tonumber(fd.paragonThreshold) or 10000
            if fd.isParagon and (fd.paragonCycleValue ~= nil or fd.paragonValue ~= nil) then
                local cur = tonumber(fd.paragonCycleValue)
                if cur == nil then
                    cur = (tonumber(fd.paragonValue) or 0) % th
                end
                local n = tonumber(fd.paragonCycleCount)
                if n == nil then
                    n = math.floor((tonumber(fd.paragonValue) or 0) / th)
                end
                return header .. string.format("\n\nStanding: Paragon\nProgress: %s / %s (one reward cycle)\nCaches earned: %s", tostring(cur), tostring(th), tostring(n))
            end
            return header .. string.format("\n\nStanding: Paragon\nCurrent: not in Paragon yet\nWhen active, progress is rep toward the next cache (~%s).", tostring(th))
        end
        local lbl = _G["FACTION_STANDING_LABEL" .. tostring(tgt)] or ("Tier " .. tostring(tgt))
        return header .. string.format("\n\nStanding: Classic\nCurrent: %s\nTarget: %s", _G["FACTION_STANDING_LABEL" .. tostring(fd.reaction or 0)] or tostring(fd.reaction or 0), lbl)
    end
    if fd.isMajorFaction then
        return header .. string.format("\n\nThis faction uses Renown (current Renown %s).", tostring(fd.renownLevel or "?"))
    end
    local react = fd.reaction or 0
    local standingLabel = _G["FACTION_STANDING_LABEL" .. react] or ("Tier " .. tostring(react))
    local val = fd.currentStanding or fd.currentRep or 0
    return header .. string.format("\n\nCurrent: %s (%s)", standingLabel, tostring(val))
end

function TaskTracker.BuildFactionInputValidationMessage(text, goalType, standingTarget)
    return formatFactionValidationMessage(text, goalType, standingTarget)
end

function TaskTracker.ParseAchievementIdFromText(text)
    if not text or text == "" then return nil end
    local id = text:match("|Hachievement:(%d+)")
    if id then return tonumber(id) end
    id = text:match("^%s*(%d+)%s*$")
    return tonumber(id)
end

function TaskTracker.ParseFactionIdFromText(text)
    if not text or text == "" then return nil, nil end
    local id = text:match("|Hfaction:(%d+)") or text:match("|Hreputation:(%d+)")
    if id then return tonumber(id), nil end
    id = text:match("^%s*(%d+)%s*$")
    if id then return tonumber(id), nil end
    return nil, trim(text)
end

--- Split comma-separated quest tokens into numeric IDs vs plain name strings (exact match when resolving).
function TaskTracker.ParseQuestListFromText(text)
    local ids, names = {}, {}
    local seen = {}
    if not text or trim(text) == "" then return ids, names end
    for part in text:gmatch("[^,]+") do
        local token = trim(part)
        if token ~= "" then
            local linkId = token:match("|Hquest:(%d+)")
            if not linkId then
                linkId = token:match("|Hquestline:(%d+)")
            end
            local num = tonumber(linkId) or tonumber(token:match("^%s*(%d+)%s*$"))
            if num and num > 0 then
                num = math.floor(num)
                if not seen[num] then
                    seen[num] = true
                    ids[#ids + 1] = num
                end
            else
                names[#names + 1] = token
            end
        end
    end
    return ids, names
end

--- Strip |c…|r and trim; used when matching typed/pasted titles to the quest log.
function TaskTracker.StripQuestTitleDecorations(s)
    if not s then return "" end
    s = tostring(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return trim(s)
end

local function questTitlesMatch(logTitle, wanted)
    local a = TaskTracker.StripQuestTitleDecorations(logTitle or "")
    local b = TaskTracker.StripQuestTitleDecorations(wanted or "")
    if a == "" or b == "" then return false end
    if a == b then return true end
    local la, lb = strlower(a), strlower(b)
    return la == lb
end

--- Resolve a quest title to an id: retail quest log scan + legacy APIs. Names only match quests present in the log (or supertracked) unless GetQuestIDForQuestName exists.
function TaskTracker.ResolveQuestNameToId(name)
    name = trim(name or "")
    if name == "" then return nil end
    local plain = TaskTracker.StripQuestTitleDecorations(name)

    if C_QuestLog and C_QuestLog.GetQuestIDForQuestName then
        for _, candidate in ipairs({ name, plain }) do
            local ok, qid = pcall(C_QuestLog.GetQuestIDForQuestName, candidate)
            if ok and type(qid) == "number" and qid > 0 then
                return qid
            end
        end
    end

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
        if okN and type(n) == "number" and n > 0 then
            for i = 1, n do
                local okI, info = pcall(C_QuestLog.GetInfo, i)
                if okI and info and not info.isHeader and info.questID and info.title then
                    if questTitlesMatch(info.title, plain) then
                        return tonumber(info.questID)
                    end
                end
            end
        end
    end

    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local okS, sid = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        if okS and type(sid) == "number" and sid > 0 then
            local okT, t = pcall(C_QuestLog.GetTitleForQuestID, sid)
            if okT and type(t) == "string" and questTitlesMatch(t, plain) then
                return sid
            end
        end
    end

    if GetNumQuestLogEntries and GetQuestLogTitle then
        local okN, n = pcall(GetNumQuestLogEntries)
        if okN and type(n) == "number" then
            for i = 1, n do
                local okT, title, _, _, isHeader, _, _, _, questID = pcall(GetQuestLogTitle, i)
                if okT and not isHeader and questID and questTitlesMatch(title, plain) then
                    return tonumber(questID)
                end
            end
        end
    end
    return nil
end

--- Merge numeric ids and resolvable names into a unique id list; `unresolved` keeps names still unknown.
function TaskTracker.MergeQuestIdsFromTokens(ids, nameTokens)
    local seen, out = {}, {}
    for _, id in ipairs(ids or {}) do
        id = tonumber(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    local unresolved = {}
    for _, nm in ipairs(nameTokens or {}) do
        local qid = TaskTracker.ResolveQuestNameToId(nm)
        if qid and not seen[qid] then
            seen[qid] = true
            out[#out + 1] = qid
        else
            unresolved[#unresolved + 1] = nm
        end
    end
    return out, unresolved
end

--- Resolve quest ID to title for UI validation (retail C_QuestLog).
local function getQuestTitleForValidation(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then return nil, "invalid" end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and type(t) == "string" and t ~= "" then
            return t, "ok"
        end
    end
    if HaveQuestData then
        local okH, has = pcall(HaveQuestData, questID)
        if okH and has == false then
            return nil, "not_loaded"
        end
    end
    return nil, "invalid"
end

local function formatQuestTokenValidationLine(token)
    local linkId = token:match("|Hquest:(%d+)")
    if not linkId then
        linkId = token:match("|Hquestline:(%d+)")
    end
    local num = tonumber(linkId) or tonumber(token:match("^%s*(%d+)%s*$"))
    if num and num > 0 then
        num = math.floor(num)
        local title, status = getQuestTitleForValidation(num)
        if status == "ok" then
            return string.format("|cff00ff00Valid|r — Quest ID |cff00ccff%d|r\n%s", num, title)
        elseif status == "not_loaded" then
            return string.format(
                "|cffffff00Pending|r — Quest ID |cff00ccff%d|r\nQuest data is not loaded yet; try again in a moment.",
                num
            )
        else
            return string.format("|cffff4444Not found|r — No quest for ID |cff00ccff%d|r.", num)
        end
    end
    local qid = TaskTracker.ResolveQuestNameToId(token)
    if qid then
        local title, status = getQuestTitleForValidation(qid)
        if status == "ok" then
            return string.format(
                "|cff00ff00Valid|r — Quest ID |cff00ccff%d|r\n%s\n|cffffffff(resolved from name)|r",
                qid,
                title
            )
        elseif status == "not_loaded" then
            return string.format(
                "|cffffff00Pending|r — Quest ID |cff00ccff%d|r (name matched)\nData not loaded yet; try again shortly.",
                qid
            )
        else
            return string.format(
                "|cffff4444Not found|r — Name matched ID |cff00ccff%d|r but no title (invalid or unavailable).",
                qid
            )
        end
    end
    return string.format(
        "|cffff4444Invalid|r — Could not resolve: %s\n|cffffffffUse the quest ID, shift-click a link into the box, or put the quest in your quest log and try again.|r",
        token
    )
end

--- Human-readable report for comma-separated quest tokens (IDs, links, exact names). For StaticPopup / UI.
function TaskTracker.BuildQuestInputValidationMessage(text)
    if not text or trim(text) == "" then
        return "Enter a quest ID, shift-click quest link, or exact quest name (comma-separated for several)."
    end
    local lines = {}
    for part in text:gmatch("[^,]+") do
        local tok = trim(part)
        if tok ~= "" then
            lines[#lines + 1] = formatQuestTokenValidationLine(tok)
        end
    end
    if #lines == 0 then
        return "Enter a quest ID, shift-click quest link, or exact quest name (comma-separated for several)."
    end
    return table.concat(lines, "\n\n")
end

function TaskTracker.ParseItemIdListFromText(text)
    local ids = {}
    local seen = {}
    if not text or trim(text) == "" then return ids end
    for part in text:gmatch("[^,]+") do
        local token = trim(part)
        if token ~= "" then
            local linkId = token:match("|Hitem:(%d+)")
            local num = tonumber(token)
            if linkId then
                num = tonumber(linkId)
            elseif not num then
                num = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(token)
                if not num and C_Item and C_Item.GetItemInfo then
                    local ok, a, b = pcall(C_Item.GetItemInfo, token)
                    if ok then
                        if type(a) == "table" and a.itemID then
                            num = a.itemID
                        elseif type(a) == "number" then
                            num = a
                        elseif type(b) == "number" then
                            num = b
                        end
                    end
                end
                if not num and GetItemInfo then
                    local ok, info = pcall(function()
                        return { GetItemInfo(token) }
                    end)
                    if ok and info and type(info) == "table" then
                        num = tonumber(info[17]) or tonumber(info[10])
                    end
                end
            end
            num = tonumber(num)
            if num and num > 0 and not seen[num] then
                seen[num] = true
                ids[#ids + 1] = num
            end
        end
    end
    return ids
end

function TaskTracker.ParseCurrencyIdListFromText(text)
    local ids = {}
    local seen = {}
    if not text or trim(text) == "" then return ids end
    for part in text:gmatch("[^,]+") do
        local token = trim(part)
        if token ~= "" then
            local linkId = token:match("|Hcurrency:(%d+)")
                or token:match("|Hconduitcurrency:(%d+)")
                or token:match("|Hcapcurrency:(%d+)")
            local num = tonumber(linkId) or tonumber(token:match("^%s*(%d+)%s*$"))
            num = tonumber(num)
            if num and num > 0 and not seen[num] then
                seen[num] = true
                ids[#ids + 1] = num
            end
        end
    end
    return ids
end

function TaskTracker.ParseMobIdListFromText(text)
    local ids = {}
    local seen = {}
    if not text or trim(text) == "" then return ids end
    for part in text:gmatch("[^,]+") do
        local token = trim(part)
        if token ~= "" then
            local num = tonumber(token:match("^%s*(%d+)%s*$"))
            num = tonumber(num)
            if num and num > 0 and not seen[num] then
                seen[num] = true
                ids[#ids + 1] = math.floor(num)
            end
        end
    end
    return ids
end

local function parseCommaList(text)
    local out = {}
    if not text or trim(text) == "" then return out end
    for part in tostring(text):gmatch("[^,]+") do
        local token = trim(part)
        if token ~= "" then out[#out + 1] = token end
    end
    return out
end

function TaskTracker.ParseBossNameListFromText(text)
    local out, seen = {}, {}
    for _, token in ipairs(parseCommaList(text)) do
        local k = token:lower()
        if not seen[k] then
            seen[k] = true
            out[#out + 1] = token
        end
    end
    return out
end

-- Dungeon journal names. Built once, in short steps, the first time Boss mode is used.
-- A partial name counts when it sits inside the journal or encounter name (3 letters or more).
local BOSS_JOURNAL_DIFFS = { 1, 2, 23, 24, 8, 14, 15, 16, 17, 3, 4, 5, 6, 7, 9 }
local bossJournal = {
    ready = false,
    started = false,
    failed = false,
    instances = {},
    seenId = {},
    tier = 1,
    numTiers = 0,
    pass = 1,
    index = 1,
}

local function plainJournalName(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    if type(v) ~= "string" then return nil end
    v = trim(v)
    if v == "" then return nil end
    return v
end

local function foldJournalName(v)
    local s = plainJournalName(v)
    if not s then return "" end
    return s:lower()
end

--- Exact match, or a partial of at least 3 letters contained in the full name.
function TaskTracker.BossJournalNameMatches(query, fullName)
    local q = foldJournalName(query)
    local full = foldJournalName(fullName)
    if q == "" or full == "" then return false end
    if q == full then return true end
    if #q < 3 then return false end
    return full:find(q, 1, true) ~= nil
end

local function journalUiOpen()
    return EncounterJournal and EncounterJournal.IsShown and EncounterJournal:IsShown()
end

local function saveJournalSelection()
    if EJ_GetCurrentTier then
        local ok, tier = pcall(EJ_GetCurrentTier)
        if ok then bossJournal.savedTier = tier end
    end
    if EJ_GetDifficulty then
        local ok, diff = pcall(EJ_GetDifficulty)
        if ok then bossJournal.savedDiff = diff end
    end
    if EJ_GetInstanceInfo then
        local ok, id = pcall(function()
            local _, _, _, _, _, _, _, _, _, instanceID = EJ_GetInstanceInfo()
            return instanceID
        end)
        if ok then bossJournal.savedInstance = id end
    end
end

local function restoreJournalSelection()
    if bossJournal.savedTier and EJ_SelectTier then
        pcall(EJ_SelectTier, bossJournal.savedTier)
    end
    if bossJournal.savedInstance and EJ_SelectInstance then
        pcall(EJ_SelectInstance, bossJournal.savedInstance)
    end
    if bossJournal.savedDiff and EJ_SetDifficulty then
        pcall(EJ_SetDifficulty, bossJournal.savedDiff)
    end
end

local function readInstanceBosses(journalID)
    local seen, list = {}, {}
    local function addCurrent()
        local i = 1
        while i <= 40 do
            local ok, name = pcall(EJ_GetEncounterInfoByIndex, i)
            if not ok then break end
            name = plainJournalName(name)
            if not name then break end
            local fold = name:lower()
            if not seen[fold] then
                seen[fold] = true
                list[#list + 1] = name
            end
            i = i + 1
        end
    end
    pcall(EJ_SelectInstance, journalID)
    local anyDiff = false
    if EJ_IsValidInstanceDifficulty and EJ_SetDifficulty then
        for d = 1, #BOSS_JOURNAL_DIFFS do
            local diff = BOSS_JOURNAL_DIFFS[d]
            local ok, valid = pcall(EJ_IsValidInstanceDifficulty, diff)
            if ok and valid then
                anyDiff = true
                pcall(EJ_SetDifficulty, diff)
                pcall(EJ_SelectInstance, journalID)
                addCurrent()
            end
        end
    end
    if not anyDiff then
        addCurrent()
    end
    return list
end

local function finishBossJournal()
    restoreJournalSelection()
    bossJournal.ready = true
    bossJournal.started = false
end

local function stepBossJournal()
    if bossJournal.ready then return end
    if journalUiOpen() then
        restoreJournalSelection()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.75, stepBossJournal)
        end
        return
    end
    if bossJournal.tier > bossJournal.numTiers then
        finishBossJournal()
        return
    end
    local isRaid = bossJournal.pass == 2
    local pastEnd = bossJournal.index > 80
    if not pastEnd and EJ_SelectTier then
        pcall(EJ_SelectTier, bossJournal.tier)
    end
    local ok, id, name = false, nil, nil
    if not pastEnd then
        ok, id, name = pcall(EJ_GetInstanceByIndex, bossJournal.index, isRaid)
    end
    name = ok and plainJournalName(name) or nil
    id = ok and tonumber(id) or nil
    if not id or not name then
        if bossJournal.pass == 1 then
            bossJournal.pass = 2
            bossJournal.index = 1
        else
            bossJournal.tier = bossJournal.tier + 1
            bossJournal.pass = 1
            bossJournal.index = 1
        end
    else
        bossJournal.index = bossJournal.index + 1
        if not bossJournal.seenId[id] then
            bossJournal.seenId[id] = true
            bossJournal.instances[#bossJournal.instances + 1] = {
                id = id,
                name = name,
                fold = name:lower(),
                bosses = readInstanceBosses(id),
            }
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, stepBossJournal)
    else
        finishBossJournal()
    end
end

function TaskTracker.StartBossJournalIndex()
    if bossJournal.ready or bossJournal.started then return end
    if not EJ_GetNumTiers or not EJ_GetInstanceByIndex or not EJ_GetEncounterInfoByIndex or not EJ_SelectInstance then
        bossJournal.ready = true
        bossJournal.failed = true
        return
    end
    bossJournal.started = true
    bossJournal.instances = {}
    bossJournal.seenId = {}
    bossJournal.tier = 1
    bossJournal.pass = 1
    bossJournal.index = 1
    local ok, n = pcall(EJ_GetNumTiers)
    bossJournal.numTiers = (ok and tonumber(n)) or 0
    if bossJournal.numTiers < 1 then
        bossJournal.ready = true
        bossJournal.failed = true
        bossJournal.started = false
        return
    end
    saveJournalSelection()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, stepBossJournal)
    else
        finishBossJournal()
    end
end

function TaskTracker.BossJournalIndexState()
    if bossJournal.failed then return "failed" end
    if bossJournal.ready then return "ready" end
    if bossJournal.started then return "loading" end
    return "idle"
end

local function sortJournalHits(hits, query)
    local q = foldJournalName(query)
    table.sort(hits, function(a, b)
        local ap = q ~= "" and a.fold:sub(1, #q) == q
        local bp = q ~= "" and b.fold:sub(1, #q) == q
        if ap ~= bp then return ap end
        if #a.name ~= #b.name then return #a.name < #b.name end
        return a.fold < b.fold
    end)
end

function TaskTracker.SuggestBossInstances(query, limit)
    TaskTracker.StartBossJournalIndex()
    limit = limit or 8
    local q = foldJournalName(query)
    if #q < 2 then return {}, TaskTracker.BossJournalIndexState() end
    local hits = {}
    local instances = bossJournal.instances
    for i = 1, #instances do
        local inst = instances[i]
        if TaskTracker.BossJournalNameMatches(query, inst.name) or (#q >= 2 and inst.fold:find(q, 1, true)) then
            hits[#hits + 1] = inst
        end
    end
    sortJournalHits(hits, query)
    local out, seen = {}, {}
    for i = 1, #hits do
        if not seen[hits[i].fold] then
            seen[hits[i].fold] = true
            out[#out + 1] = hits[i].name
            if #out >= limit then break end
        end
    end
    return out, TaskTracker.BossJournalIndexState()
end

local function instancesForBossQuery(instanceText)
    local q = trim(instanceText or "")
    if q == "" then return bossJournal.instances end
    local hits = {}
    for i = 1, #bossJournal.instances do
        local inst = bossJournal.instances[i]
        if TaskTracker.BossJournalNameMatches(q, inst.name) then
            hits[#hits + 1] = inst
        end
    end
    return hits
end

function TaskTracker.SuggestBossNames(instanceText, bossQuery, limit)
    TaskTracker.StartBossJournalIndex()
    limit = limit or 8
    local q = foldJournalName(bossQuery)
    if #q < 2 then return {}, TaskTracker.BossJournalIndexState() end
    local scope = instancesForBossQuery(instanceText)
    local showInstance = trim(instanceText or "") == "" or #scope ~= 1
    local hits = {}
    for i = 1, #scope do
        local inst = scope[i]
        local bosses = inst.bosses
        for b = 1, #bosses do
            local boss = bosses[b]
            if TaskTracker.BossJournalNameMatches(bossQuery, boss) or (#q >= 2 and boss:lower():find(q, 1, true)) then
                hits[#hits + 1] = { name = boss, fold = boss:lower(), instance = inst.name }
            end
        end
    end
    sortJournalHits(hits, bossQuery)
    local out, seen = {}, {}
    for i = 1, #hits do
        local hit = hits[i]
        local key = hit.fold .. "\0" .. hit.instance:lower()
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = {
                boss = hit.name,
                instance = hit.instance,
                label = showInstance and (hit.name .. " - " .. hit.instance) or hit.name,
            }
            if #out >= limit then break end
        end
    end
    return out, TaskTracker.BossJournalIndexState()
end

function TaskTracker.BuildBossEncounterInputValidationMessage(instanceText, bossNamesText)
    local inst = trim(instanceText or "")
    local names = TaskTracker.ParseBossNameListFromText(bossNamesText or "")
    if #names == 0 then
        return "Enter a boss name. A partial name is enough."
    end
    TaskTracker.StartBossJournalIndex()
    local state = TaskTracker.BossJournalIndexState()
    local lines = { "|cff00ff00Boss check|r" }
    if inst ~= "" then
        lines[#lines + 1] = "Instance: " .. inst
    else
        lines[#lines + 1] = "Instance: any"
    end
    if state == "failed" then
        lines[#lines + 1] = "The dungeon journal is not available."
    elseif state ~= "ready" and #bossJournal.instances == 0 then
        lines[#lines + 1] = "The dungeon journal is still loading. Check again in a moment."
        return table.concat(lines, "\n")
    end
    local scope = instancesForBossQuery(inst)
    if inst ~= "" and state == "ready" and #scope == 0 then
        lines[#lines + 1] = inst .. " does not match an instance in the dungeon journal."
    end
    for n = 1, #names do
        local token = names[n]
        local found = {}
        local seen = {}
        for i = 1, #scope do
            local entry = scope[i]
            local bosses = entry.bosses
            for b = 1, #bosses do
                if TaskTracker.BossJournalNameMatches(token, bosses[b]) then
                    local key = bosses[b]:lower() .. "\0" .. entry.fold
                    if not seen[key] then
                        seen[key] = true
                        found[#found + 1] = bosses[b] .. " in " .. entry.name
                    end
                end
            end
        end
        if #found == 0 then
            if state ~= "ready" then
                lines[#lines + 1] = token .. " is not in the journal yet. It is still loading."
            else
                lines[#lines + 1] = "|cffff4444" .. token .. " does not match a boss" .. (inst ~= "" and (" in " .. inst) or "") .. ".|r"
            end
        elseif #found == 1 then
            lines[#lines + 1] = "|cff00ff00" .. token .. " matches " .. found[1] .. ". It will count.|r"
        else
            lines[#lines + 1] = "|cffffff00" .. token .. " matches more than one boss. A kill of any of them counts.|r"
            local cap = math.min(6, #found)
            for f = 1, cap do
                lines[#lines + 1] = "- " .. found[f]
            end
            if #found > cap then
                lines[#lines + 1] = "- and " .. tostring(#found - cap) .. " more"
            end
        end
    end
    local last = MOBKILL and MOBKILL.bossLast
    if last and plainJournalName(last.name) then
        lines[#lines + 1] = "Last boss killed this session: " .. last.name .. (plainJournalName(last.inst) and (" in " .. last.inst) or "") .. "."
    end
    return table.concat(lines, "\n")
end

function TaskTracker.BuildMobIdInputValidationMessage(text)
    if not text or trim(text) == "" then
        return "Enter one or more NPC IDs (comma-separated)."
    end
    local ids = TaskTracker.ParseMobIdListFromText(text)
    if #ids == 0 then
        return "|cffff4444Invalid|r — No NPC IDs found. Use numeric IDs (comma-separated)."
    end
    local lines = {
        "|cffffff00Note|r — Blizzard does not provide a reliable API to validate NPC IDs or resolve names from IDs in all cases.\n"
            .. "This check only verifies that your input is a list of numeric NPC IDs.\n",
    }
    for _, id in ipairs(ids) do
        lines[#lines + 1] = string.format("|cff00ff00Valid|r — NPC ID |cff00ccff%d|r", id)
    end
    return table.concat(lines, "\n")
end

local function sumCurrencyCounts(currencyIds, spendableOnly)
    local s = 0
    if not currencyIds or not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return 0 end
    for _, cid in ipairs(currencyIds) do
        cid = tonumber(cid)
        if cid and cid > 0 then
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, cid)
            if ok and info then
                local q = tonumber(info.quantity) or 0
                if not spendableOnly then
                    local te = tonumber(info.totalEarned)
                    if te and te > q then
                        q = te
                    end
                end
                s = s + q
            end
        end
    end
    return s
end

local function formatItemOrCurrencyValidationMessage(text, kind)
    kind = (kind == "currency") and "currency" or "item"
    if not text or trim(text) == "" then
        return kind == "currency"
            and "Enter a currency ID or shift-click a currency link (comma-separated)."
            or "Enter an item ID, name, or shift-click an item link (comma-separated)."
    end
    local ids = (kind == "currency")
        and TaskTracker.ParseCurrencyIdListFromText(text)
        or TaskTracker.ParseItemIdListFromText(text)
    if #ids == 0 then
        return "|cffff4444Invalid|r — No IDs found. Use IDs/links (comma-separated)."
    end
    local lines = {}
    if kind == "currency" then
        for _, cid in ipairs(ids) do
            local name = nil
            if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, cid)
                if ok and info and info.name then
                    name = info.name
                end
            end
            if name then
                lines[#lines + 1] = string.format("|cff00ff00Valid|r — Currency ID |cff00ccff%d|r\n%s", cid, name)
            else
                lines[#lines + 1] = string.format("|cffffff00Pending|r — Currency ID |cff00ccff%d|r\nName not loaded yet; open currency UI or wait a moment.", cid)
            end
        end
    else
        for _, iid in ipairs(ids) do
            local name = nil
            if GetItemInfo then
                local ok, n = pcall(GetItemInfo, iid)
                if ok and type(n) == "string" and n ~= "" then
                    name = n
                end
            end
            if name then
                lines[#lines + 1] = string.format("|cff00ff00Valid|r — Item ID |cff00ccff%d|r\n%s", iid, name)
            else
                lines[#lines + 1] = string.format("|cffffff00Pending|r — Item ID |cff00ccff%d|r\nItem info not loaded yet; try again after it caches.", iid)
            end
        end
    end
    return table.concat(lines, "\n\n")
end

function TaskTracker.BuildItemInputValidationMessage(text, kind)
    return formatItemOrCurrencyValidationMessage(text, kind)
end

--- Currency-linked criteria (type 12) often report 0 from GetAchievementCriteriaInfo; read live totals from C_CurrencyInfo.
local function getCurrencyProgressForCriteria(assetID)
    local id = tonumber(assetID)
    if not id or not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    if not ok or not info then return nil end
    local q = tonumber(info.quantity) or 0
    local te = tonumber(info.totalEarned)
    if te and te > q then
        q = te
    end
    return q
end

--- How many criteria are complete vs total (for "Base achievement" tracking: e.g. 16/32).
local function getAchievementCriteriaCompletionCounts(achId)
    achId = tonumber(achId)
    if not achId then return 0, 0 end
    local n = GetAchievementNumCriteria(achId) or 0
    if n == 0 then
        local okN, n2 = pcall(GetAchievementNumCriteria, achId, true)
        if okN and type(n2) == "number" and n2 > n then
            n = n2
        end
    end
    if n <= 0 then
        if GetAchievementInfo then
            -- id, name, points, completed, month, day, year, ...
            local ok, _i, _n, _p, completed = pcall(GetAchievementInfo, achId)
            if ok then
                return (completed and 1 or 0), 1
            end
        end
        return 0, 0
    end
    local done = 0
    for i = 1, n do
        local completed
        for _, hidden in ipairs({ true, false }) do
            local ok, _, _, comp = pcall(GetAchievementCriteriaInfo, achId, i, hidden)
            if ok and comp ~= nil then
                completed = comp
                break
            end
        end
        if completed == true then
            done = done + 1
        end
    end
    return done, n
end

--- Current / cap / completed for one criterion index (numeric bars, currency, items, or boolean).
local function getAchievementCriterionCurMax(achId, i)
    achId = tonumber(achId)
    i = tonumber(i)
    if not achId or not i or i < 1 then return 0, 1, false end
    local critString, critType, completed, quantity, reqQuantity, charName, flags, assetID, quantityString
    local got = false
    for _, hidden in ipairs({ true, false }) do
        local ok, cs, ct, comp, qty, rq, cn, fl, aid, qstr =
            pcall(GetAchievementCriteriaInfo, achId, i, hidden)
        if ok then
            critString, critType, completed, quantity, reqQuantity, charName, flags, assetID, quantityString =
                cs, ct, comp, qty, rq, cn, fl, aid, qstr
            got = true
            break
        end
    end
    if not got then return 0, 1, false end

    critType = tonumber(critType) or 0
    local q = tonumber(quantity) or 0
    local req = tonumber(reqQuantity) or 0
    local asset = tonumber(assetID)

    if critType == 12 and asset then
        local cq = getCurrencyProgressForCriteria(asset)
        if cq ~= nil then
            q = cq
        end
    elseif (critType == 36 or critType == 57) and asset then
        q = TaskTracker.ItemCount(asset, true, false, true)
    end

    if q == 0 and type(quantityString) == "string" and quantityString ~= "" then
        local compact = quantityString:gsub(",", ""):match("%d+")
        if compact then
            q = tonumber(compact) or q
        end
    end

    local done = completed == true
    if req > 0 then
        return math.min(q, req), req, done
    end
    return (done and 1 or 0), 1, done
end

function TaskTracker.GetAchievementCriterionCurMax(achId, criteriaIndex)
    return getAchievementCriterionCurMax(achId, criteriaIndex)
end

local function getAchievementCriteriaProgress(achId, i)
    achId = tonumber(achId)
    i = tonumber(i)
    if not achId or not i or i < 1 then return 0 end
    local critString, critType, completed, quantity, reqQuantity, charName, flags, assetID, quantityString
    local got = false
    for _, hidden in ipairs({ true, false }) do
        local ok, cs, ct, comp, qty, rq, cn, fl, aid, qstr =
            pcall(GetAchievementCriteriaInfo, achId, i, hidden)
        if ok then
            critString, critType, completed, quantity, reqQuantity, charName, flags, assetID, quantityString =
                cs, ct, comp, qty, rq, cn, fl, aid, qstr
            got = true
            break
        end
    end
    if not got then return 0 end

    critType = tonumber(critType) or 0
    local q = tonumber(quantity) or 0
    local req = tonumber(reqQuantity) or 0
    local asset = tonumber(assetID)

    if critType == 12 and asset then
        local cq = getCurrencyProgressForCriteria(asset)
        if cq ~= nil then
            q = cq
        end
    elseif (critType == 36 or critType == 57) and asset then
        q = TaskTracker.ItemCount(asset, true, false, true)
    end

    if q == 0 and type(quantityString) == "string" and quantityString ~= "" then
        local compact = quantityString:gsub(",", ""):match("%d+")
        if compact then
            q = tonumber(compact) or q
        end
    end

    if req > 0 then
        return math.min(q, req)
    end
    return q
end

local function getAchievementNumericProgress(achId, criteriaIndex)
    achId = tonumber(achId)
    if not achId then return 0 end
    local ci0 = tonumber(criteriaIndex)
    if ci0 == 0 then
        return select(1, getAchievementCriteriaCompletionCounts(achId))
    end
    local n = GetAchievementNumCriteria(achId) or 0
    if n == 0 then
        local okN, n2 = pcall(GetAchievementNumCriteria, achId, true)
        if okN and type(n2) == "number" and n2 > n then
            n = n2
        end
    end
    local ci = tonumber(criteriaIndex)
    if ci and ci >= 1 and ci <= n then
        return getAchievementCriteriaProgress(achId, ci)
    end
    local sum = 0
    for i = 1, n do
        sum = sum + getAchievementCriteriaProgress(achId, i)
    end
    return sum
end

function TaskTracker.BuildAchievementInputValidationMessage(text)
    local id = TaskTracker.ParseAchievementIdFromText(text)
    if not id or id <= 0 then
        return "Enter an achievement ID or shift-click an achievement link."
    end
    local name
    if GetAchievementInfo then
        local ok, a, b = pcall(GetAchievementInfo, id)
        if ok then
            if type(a) == "table" and a.name then
                name = a.name
            elseif type(a) == "string" then
                name = a
            elseif type(b) == "string" then
                name = b
            end
        end
    end
    if not name or name == "" then
        return string.format("|cffff4444Not found|r — No achievement for ID |cff00ccff%d|r.", id)
    end
    local n = GetAchievementNumCriteria and (GetAchievementNumCriteria(id) or 0) or 0
    return string.format("|cff00ff00Valid|r — Achievement ID |cff00ccff%d|r\n%s\n\nCriteria: %s", id, name, tostring(n))
end

local function sumItemCounts(itemIds)
    local s = 0
    if not itemIds then return 0 end
    for _, itemId in ipairs(itemIds) do
        s = s + TaskTracker.ItemCount(itemId, true, false, true)
    end
    return s
end

function runtimeFor(nodeId)
    local key = TaskTracker._ttGoalSlotKey or nodeId
    local r = RUNTIME[key]
    if not r then
        r = {}
        RUNTIME[key] = r
    end
    return r
end

--- Live automation tally for advanced item/currency tasks (`advanced.itemAutoCount`).
--- Always updated from inventory/currency APIs (including while a manual count lock is held).
--- `node.taskCount` / `node.done` mirror automation only when `taskUserValue` is nil (same as registry quest_count vs userValue).
local function applyAdvancedItemCurrencyProgress(node, a, rt, total)
    local mode = a.itemTrackMode or "earned"
    local mirror = (node.taskUserValue == nil)
    if mode == "total" then
        local t = math.max(0, tonumber(total) or 0)
        local stored = math.max(0, tonumber(a.itemAutoCount) or 0)
        -- Currency APIs can briefly report 0 right after PLAYER_ENTERING_WORLD; don't wipe saved progress.
        if t == 0 and stored > 0 and mirror and TaskTracker._progressSyncGraceUntil
            and GetTime() < TaskTracker._progressSyncGraceUntil then
            return
        end
        a.itemAutoCount = t
        if mirror then
            node.taskCount = a.itemAutoCount
            node.done = (node.taskCount or 0) >= (node.taskMax or 1)
        end
        return
    end
    if (a.itemKind or "item") == "currency" then
        if not rt.currenciesInitialized then
            rt.lastCurrencyTotals = total
            rt.currenciesInitialized = true
            if mirror then
                if a.itemAutoCount == nil then a.itemAutoCount = 0 end
                node.taskCount = math.max(0, tonumber(a.itemAutoCount) or 0)
                node.done = (node.taskCount or 0) >= (node.taskMax or 1)
            end
            return
        end
        local prev = rt.lastCurrencyTotals or 0
        local d = total - prev
        rt.lastCurrencyTotals = total
        if d > 0 then
            a.itemAutoCount = math.max(0, (tonumber(a.itemAutoCount) or 0) + d)
        end
    else
        if not rt.itemsInitialized then
            rt.lastItemTotals = total
            rt.itemsInitialized = true
            if mirror then
                if a.itemAutoCount == nil then a.itemAutoCount = 0 end
                node.taskCount = math.max(0, tonumber(a.itemAutoCount) or 0)
                node.done = (node.taskCount or 0) >= (node.taskMax or 1)
            end
            return
        end
        local prev = rt.lastItemTotals or 0
        local d = total - prev
        rt.lastItemTotals = total
        if d > 0 then
            a.itemAutoCount = math.max(0, (tonumber(a.itemAutoCount) or 0) + d)
        end
    end
    if a.itemAutoCount == nil then
        a.itemAutoCount = mirror and math.max(0, tonumber(node.taskCount) or 0) or 0
    end
    if mirror then
        node.taskCount = math.max(0, tonumber(a.itemAutoCount) or 0)
        node.done = (node.taskCount or 0) >= (node.taskMax or 1)
    end
end

local function collectableFarmItemIdFromAdv(a)
    if type(a) ~= "table" then return nil end
    local n = tonumber(a.collectableFarmItemId)
    if n and n > 0 then return math.floor(n) end
    if TaskTracker.GetCollectableEntry and TaskTracker.CollectableEntryFarmItemId then
        local ent = TaskTracker.GetCollectableEntry(a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
        return TaskTracker.CollectableEntryFarmItemId(ent)
    end
    return nil
end

--- Weekly earned bag-item count for catalog farms (`farmItemId` / `collectableFarmItemId`).
local function applyCollectableFarmItemProgress(node, a)
    local itemId = collectableFarmItemIdFromAdv(a)
    if not itemId then return end
    local total = TaskTracker.ItemCount(itemId, true, false, true)
    local rt = runtimeFor(node.id)
    local mirror = (node.taskUserValue == nil)
    if not rt.itemsInitialized then
        rt.lastItemTotals = total
        rt.itemsInitialized = true
        if mirror and a.collectableAutoCount == nil then
            a.collectableAutoCount = 0
        end
        return
    end
    local prev = rt.lastItemTotals or 0
    local d = total - prev
    rt.lastItemTotals = total
    if d > 0 then
        a.collectableAutoCount = math.max(0, (tonumber(a.collectableAutoCount) or 0) + d)
    end
end

function TaskTracker.InitAdvancedMoneyBaseline()
    TaskTracker._advancedLastMoney = GetMoney()
end

function TaskTracker.OnPlayerMoney()
    local now = GetMoney()
    local prev = TaskTracker._advancedLastMoney
    TaskTracker._advancedLastMoney = now
    if prev == nil then return end
    local delta = now - prev
    if delta == 0 then return end
    local needPaint = false
    eachAdvNode("gold", function(node)
        if taskVisibleForAutomation(node) and node.advanced and node.taskUserValue == nil then
            local mode = node.advanced.goldMode or "net"
            local add = 0
            if mode == "gross" then
                if delta > 0 then add = delta end
            else
                add = delta
            end
            if add ~= 0 then
                local a = node.advanced
                local acc = tonumber(a.goldAutoCopper)
                if acc == nil or math.floor(acc / 10000) ~= (node.taskCount or 0) then
                    acc = (node.taskCount or 0) * 10000
                end
                acc = math.max(0, acc + add)
                a.goldAutoCopper = acc
                node.taskCount = math.floor(acc / 10000)
                node.done = node.taskCount >= (node.taskMax or 1)
                needPaint = true
            end
        end
    end)
    local goldSubs = advNodes("subtextGold")
    if goldSubs and #goldSubs > 0 and delta ~= 0 then
        for _, node in ipairs(goldSubs) do
            if taskVisibleForAutomation(node) and type(node.subtext) == "table" then
                node.subtext.goldPeriodCopper = math.max(0, (tonumber(node.subtext.goldPeriodCopper) or 0) + delta)
                needPaint = true
                if TaskTracker.PersistOneCharTaskProgress then
                    TaskTracker.PersistOneCharTaskProgress(node)
                end
            end
        end
    end
    if needPaint then
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then TaskTracker.RefreshList() end
    end
end

function TaskTracker.OnAdvancedBagUpdate()
    local needPaint = false
    eachAdvNode("item", function(node)
        local a = node.advanced
        if taskVisibleForAutomation(node) and a and (a.itemKind or "item") == "item" then
            local ids = a.itemIds or {}
            if #ids > 0 then
                local rt = runtimeFor(node.id)
                local total = sumItemCounts(ids)
                local tc0, dn0 = node.taskCount, node.done
                local ac0 = a.itemAutoCount
                applyAdvancedItemCurrencyProgress(node, a, rt, total)
                if tc0 ~= node.taskCount or dn0 ~= node.done or ac0 ~= a.itemAutoCount then
                    needPaint = true
                end
            end
        end
    end)
    eachAdvNode("collectable", function(node)
        local a = node.advanced
        if taskVisibleForAutomation(node) and a and collectableFarmItemIdFromAdv(a) then
            local tc0, dn0 = node.taskCount, node.done
            local ac0 = a.collectableAutoCount
            applyCollectableFarmItemProgress(node, a)
            if TaskTracker.SyncAdvancedTask then
                TaskTracker.SyncAdvancedTask(node)
            end
            if tc0 ~= node.taskCount or dn0 ~= node.done or ac0 ~= a.collectableAutoCount then
                needPaint = true
            end
        end
    end)
    -- Registry sync runs after this; it only repaints when registry rows change. Advanced
    -- item progress lives on tree nodes, so we must refresh when those counts move.
    if needPaint then
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then
            TaskTracker.RefreshList()
        end
    end
end

function TaskTracker.OnAdvancedCurrencyUpdate()
    local needPaint = false
    eachAdvNode("item", function(node)
        local a = node.advanced
        if taskVisibleForAutomation(node) and a and (a.itemKind or "item") == "currency" then
            local ids = a.itemIds or {}
            if #ids > 0 then
                local rt = runtimeFor(node.id)
                local total = sumCurrencyCounts(ids, (a.itemTrackMode or "earned") == "total")
                local tc0, dn0 = node.taskCount, node.done
                local ac0 = a.itemAutoCount
                applyAdvancedItemCurrencyProgress(node, a, rt, total)
                if tc0 ~= node.taskCount or dn0 ~= node.done or ac0 ~= a.itemAutoCount then
                    needPaint = true
                end
            end
        end
    end)
    if needPaint then
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then
            TaskTracker.RefreshList()
        end
    end
end

local function syncAchievement(node, a)
        local achId = tonumber(a.achievementId)
        if not achId then return end
        local critIdx = tonumber(a.achievementCriteriaIndex)
        if critIdx == nil then
            critIdx = 0
        end
        if critIdx == 0 then
            local doneN, totalN = getAchievementCriteriaCompletionCounts(achId)
            if totalN <= 0 then
                if GetAchievementInfo then
                    local ok, _i, _n, _p, completed = pcall(GetAchievementInfo, achId)
                    if ok then
                        node.taskCount = completed and 1 or 0
                        node.taskMax = 1
                        node.done = completed and true or false
                        return
                    end
                end
                node.taskCount = 0
                node.taskMax = 1
                node.done = false
            else
                node.taskCount = doneN
                node.taskMax = totalN
                node.done = (node.taskCount or 0) >= (node.taskMax or 1)
            end
            return
        end
        if a.achievementMirrorGameTotals then
            local cur, cap, achDone = getAchievementCriterionCurMax(achId, critIdx)
            if cap < 1 then cap = 1 end
            node.taskCount = cur
            node.taskMax = cap
            node.done = achDone or ((cur >= cap) and cap > 0)
            return
        end
        local raw = getAchievementNumericProgress(achId, critIdx)
        if a.weekStartAchTotal == nil then
            a.weekStartAchTotal = raw
        end
        local w = math.max(0, raw - (a.weekStartAchTotal or 0))
        node.taskCount = w
        local achDone = false
        if critIdx >= 1 then
            local cur, cap, done = getAchievementCriterionCurMax(achId, critIdx)
            achDone = done == true or (tonumber(cap) or 0) > 0 and (tonumber(cur) or 0) >= cap
        end
        node.done = achDone or (node.taskCount or 0) >= (node.taskMax or 1)
end

local function syncItem(node, a)
        local ids = a.itemIds or {}
        if #ids == 0 then return end
        -- Catch-up knowledge: the row shows what is left and finishes at 0.
        if a.itemTrackMode == "remaining" then
            local cid = tonumber(ids[1])
            local rem = TaskTracker.GetProfessionCatchupRemaining and TaskTracker.GetProfessionCatchupRemaining(cid)
            if rem == nil then return end
            rem = math.max(0, math.floor(rem))
            node.taskCount = rem
            node.done = rem <= 0
            return
        end
        local total
        if (a.itemKind or "item") == "currency" then
            total = sumCurrencyCounts(ids, (a.itemTrackMode or "earned") == "total")
        else
            total = sumItemCounts(ids)
        end
        local rt = runtimeFor(node.id)
        applyAdvancedItemCurrencyProgress(node, a, rt, total)
end

local function syncReputation(node, a)
        -- Faction 2838 is friendship. Rank 5 finishes the 5000 bar.
        -- standing/maxRep can still be the classic 42000 bar (5115/42000).
        if node.collectionFarmId == "p1215_aqir_enclave" and TaskTracker.AqirEnclaveReputationBar then
            local cur, cap = TaskTracker.AqirEnclaveReputationBar()
            cap = math.max(1, tonumber(cap) or 5000)
            cur = tonumber(cur) or 0
            if cur < 0 then cur = 0 end
            if cur > cap then cur = cap end
            node.taskMax = cap
            node.taskCount = cur
            node.done = cur >= cap
            return
        end
        local goal = a.repGoalType or "weekly_gain"
        if goal == "friendship" and TaskTracker.GetRegistryReputationStanding then
            local target = math.max(1, tonumber(a.repStandingTarget) or 1)
            local cur = TaskTracker.GetRegistryReputationStanding({
                factionId = a.repFactionId,
                repKind = "friendship",
                max = target,
            })
            cur = tonumber(cur) or 0
            node.taskMax = target
            node.taskCount = math.min(math.max(0, cur), target)
            node.done = cur >= target
            return
        end
        local fd = TaskTracker.GetAdvancedFactionData(a.repFactionId, a.repFactionName)
        if not fd then return end
        if (tonumber(a.repFactionId) or 0) == 0 and fd.factionID then
            a.repFactionId = fd.factionID
        end
        if goal == "weekly_gain" then
            local classic = a.repClassic == true
            local points = tonumber(fd.friendshipStanding)
            if points ~= nil then
                local bottom = tonumber(fd.friendshipThreshold) or 0
                if points < bottom then
                    points = bottom + points
                end
            end
            local cur = points
            if points == nil then
                cur = classic and (tonumber(fd.currentStanding or fd.currentRep) or 0) or getFactionWeeklyProgressValue(fd)
            end
            -- A stored Renown cursor (level * 1,000,000) is not friendship points or a classic standing.
            if (points ~= nil or classic) and (tonumber(a.weekStartRepValue) or 0) >= 1000000 then
                a.weekStartRepValue = nil
            end
            -- First sight of the Labyrinth row. Baseline at the start of this rank so
            -- renown already earned (1960/2100 on the live bar) is this week's progress.
            if node.collectionFarmId == "p1215_labyrinth_renown" and node.labyrinthRankBaseline ~= true and fd.isMajorFaction then
                local lvl = tonumber(fd.renownLevel) or 0
                a.weekStartRepValue = lvl * 1000000
                node.labyrinthRankBaseline = true
            end
            if a.weekStartRepValue == nil then
                -- A higher goal must not throw away progress already on the row.
                -- Rebuild the baseline from that count when the snapshot is gone.
                local shown = tonumber(node.taskCount) or 0
                if (points ~= nil or classic) and shown > 0 and cur and cur >= shown then
                    a.weekStartRepValue = cur - shown
                else
                    a.weekStartRepValue = cur
                end
            end
            local w
            if points == nil and not classic and fd.isMajorFaction then
                local threshold = tonumber(fd.renownLevelThreshold)
                if not threshold or threshold < 1 then
                    local goal = tonumber(node.taskMax)
                    if goal and goal >= 1 and goal < 1000000 then threshold = goal end
                end
                w = majorFactionWeeklyGain(a.weekStartRepValue, cur, threshold)
            else
                w = math.max(0, cur - (a.weekStartRepValue or 0))
            end
            node.taskCount = w
            node.done = (node.taskCount or 0) >= (node.taskMax or 1)
        elseif goal == "standing" then
            local target = tonumber(a.repStandingTarget) or 6
            if fd.isMajorFaction then
                local cap = math.max(1, target)
                node.taskMax = cap
                local curRenown = tonumber(fd.renownLevel) or 0
                node.taskCount = math.min(math.max(0, curRenown), cap)
                node.done = curRenown >= target
            elseif target == TaskTracker.REP_STANDING_PARAGON then
                local cap = tonumber(a.repParagonTarget) or tonumber(fd.paragonThreshold) or 10000
                if cap < 1 then cap = 1 end
                if fd.isParagon then
                    node.taskMax = cap
                    if fd.paragonHasRewardPending then
                        node.taskCount = cap
                    else
                        local cur = tonumber(fd.paragonCycleValue)
                        if cur == nil then
                            -- Backward compat if a cached fd lacks cycle fields.
                            cur = (tonumber(fd.paragonValue) or 0) % (tonumber(fd.paragonThreshold) or 10000)
                        end
                        node.taskCount = math.min(cur or 0, cap)
                    end
                    node.done = ((node.taskCount or 0) >= cap)
                else
                    node.taskMax = 1
                    node.taskCount = 0
                    node.done = false
                end
            else
                local cur = tonumber(fd.currentStanding or fd.currentRep) or 0
                local react = tonumber(fd.reaction) or 0
                if react >= target then
                    node.done = true
                    node.taskMax = math.max(1, cur)
                    node.taskCount = cur
                else
                    local goalRep = classicStandingGoalThreshold(fd, target)
                    if goalRep and goalRep > 0 and cur >= 0 then
                        if cur >= goalRep then
                            node.done = true
                            node.taskMax = math.max(1, cur, goalRep)
                            node.taskCount = node.taskMax
                        else
                            node.taskMax = math.max(1, goalRep)
                            node.taskCount = math.max(0, cur)
                            node.done = false
                        end
                    else
                        node.taskMax = 1
                        node.taskCount = (react >= target) and 1 or 0
                        node.done = react >= target
                    end
                end
            end
        elseif goal == "value" then
            -- Value targets are only meaningful for classic reputation bars.
            local cur = fd.currentStanding or 0
            local cap = tonumber(a.repValueTarget) or (node.taskMax or 1)
            node.taskMax = cap
            node.taskCount = math.max(0, cur)
            node.done = cur >= cap
        end
end

local function syncGold(node, a)
        local cap = node.taskMax or 1
        if (node.taskCount or 0) < 0 then node.taskCount = 0 end
        node.done = (node.taskCount or 0) >= cap
end

local function questRepeatExtra(a, key)
    local reps = a and a.questPeriodRepeatCounts
    if type(reps) ~= "table" then return 0 end
    local n = math.floor(tonumber(reps[key]) or 0)
    if n < 0 then return 0 end
    return n
end

local function questFlag(qid)
    -- Turn-in only. Objective completion / ReadyForTurnIn does not count.
    qid = tonumber(qid)
    if not qid or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        return false, false
    end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
    if not ok or done == nil then return false, false end
    if issecretvalue and issecretvalue(done) then return false, false end
    return true, done and true or false
end

local function syncQuest(node, a)
        local merged, still = TaskTracker.MergeQuestIdsFromTokens(a.questIds or {}, a.questNames or {})
        a.questIds = merged
        if still and #still > 0 then
            a.questNames = still
        else
            a.questNames = nil
        end
        local cap = node.taskMax or 1
        if cap < 1 then cap = 1 end
        local rst = node.reset or "none"
        -- Several quests on a daily or weekly task. A flag that never clears means
        -- the quest was finished sometime, not this period. The first look this
        -- period stores those, and they do not count. One that becomes flagged
        -- later, or a turn-in this period, does. Another turn-in of that same
        -- quest still adds one, up to the goal.
        local periodPool = rst ~= "none" and rst ~= "temporary" and #merged > 1
        -- Profession weeklies copy the old registry baseline once. Snapshotting
        -- before that copy hides a quest that was already turned in this week.
        if periodPool and node.collectionFarmId and not node.professionProgressSeeded then
            local profEntry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[node.collectionFarmId]
            if profEntry and profEntry.expansion == "professions" then
                return
            end
        end
        local cur = 0
        local flaggedNow, seenNow, sawFlag
        if periodPool then
            flaggedNow = {}
            seenNow = {}
            sawFlag = false
            for _, qid in ipairs(merged) do
                local ok, done = questFlag(qid)
                if ok then
                    sawFlag = true
                    local key = tostring(qid)
                    seenNow[key] = true
                    if done then
                        flaggedNow[key] = true
                        cur = cur + 1
                    end
                end
            end
        else
            for _, qid in ipairs(merged) do
                local ok, done = questFlag(qid)
                if ok and done then
                    cur = cur + 1
                end
            end
        end
        if rst == "none" or rst == "temporary" then
            node.taskCount = cur
        elseif not periodPool then
            -- One quest id: latch it when the flag first turns on. The flag can clear
            -- overnight on a daily quest while this task stays weekly.
            if type(a.questPeriodCredited) ~= "table" then
                a.questPeriodCredited = {}
                a.questWeekStartComplete = cur
                local saved = math.max(0, tonumber(node.taskCount) or 0)
                if saved > 0 then
                    local creditedNow = 0
                    for _, qid in ipairs(merged) do
                        local ok, done = questFlag(qid)
                        if ok and done then
                            a.questPeriodCredited[tostring(qid)] = true
                            creditedNow = creditedNow + 1
                        end
                    end
                    if saved > creditedNow then
                        a.questPeriodOrphanCredits = saved - creditedNow
                    end
                end
            end
            for _, qid in ipairs(merged) do
                local ok, done = questFlag(qid)
                if ok and done then
                    a.questPeriodCredited[tostring(qid)] = true
                end
            end
            local count = math.max(0, tonumber(a.questPeriodOrphanCredits) or 0)
            local turnIns = a.questPeriodTurnIns
            for _, qid in ipairs(merged) do
                local key = tostring(qid)
                if a.questPeriodCredited[key] or (type(turnIns) == "table" and turnIns[key]) then
                    count = count + 1
                end
                count = count + questRepeatExtra(a, key)
            end
            node.taskCount = math.min(count, cap)
        else
            if type(a.questPeriodCredited) ~= "table" then
                a.questPeriodCredited = {}
                a.questWeekStartComplete = cur
                local saved = math.max(0, tonumber(node.taskCount) or 0)
                if saved > 0 then
                    a.questPeriodOrphanCredits = saved
                end
            end
            local professionRow = node.collectionFarmId and node.liveShareRole ~= "receiver"
            if professionRow and a.questPeriodBaselineAtReset == true and type(a.questPeriodBaseline) == "table" and a.questPeriodBaselineFrozen ~= true and sawFlag then
                -- The first look this period can see zero quests done. Freeze that, including
                -- an empty look. Waiting until a quest is flagged stores this week's loot as
                -- the baseline, and the count then stays 0.
                local start = tonumber(a.questWeekStartComplete) or 0
                if start == 0 and next(a.questPeriodBaseline) then
                    local move = {}
                    for key in pairs(a.questPeriodBaseline) do
                        move[#move + 1] = key
                    end
                    for i = 1, #move do
                        local key = move[i]
                        if flaggedNow[key] then
                            a.questPeriodCredited[key] = true
                        end
                        a.questPeriodBaseline[key] = nil
                    end
                elseif not next(a.questPeriodBaseline) then
                    for key in pairs(flaggedNow) do
                        a.questPeriodBaseline[key] = true
                    end
                end
                a.questPeriodBaselineFrozen = true
            elseif not professionRow and type(a.questPeriodBaseline) ~= "table" then
                if sawFlag then
                    local base = {}
                    for key in pairs(flaggedNow) do
                        base[key] = true
                    end
                    a.questPeriodBaseline = base
                    local turns = a.questPeriodTurnIns
                    for key in pairs(a.questPeriodCredited) do
                        if base[key] and not (type(turns) == "table" and turns[key]) then
                            a.questPeriodCredited[key] = nil
                        end
                    end
                    local start = tonumber(a.questWeekStartComplete)
                    if not start then start = cur end
                    local extra = cur - start
                    if extra > 0 then
                        local prev = math.max(0, tonumber(a.questPeriodOrphanCredits) or 0)
                        if extra > prev then
                            a.questPeriodOrphanCredits = extra
                        end
                    end
                end
            elseif type(a.questPeriodBaseline) == "table" then
                for _, qid in ipairs(merged) do
                    local key = tostring(qid)
                    if a.questPeriodBaseline[key] and seenNow[key] and not flaggedNow[key] then
                        a.questPeriodBaseline[key] = nil
                    end
                end
            end
            if professionRow and a.questPeriodBaselineAtReset ~= true and type(a.questPeriodBaseline) == "table" and sawFlag then
                for key in pairs(a.questPeriodBaseline) do
                    if flaggedNow[key] then
                        a.questPeriodCredited[key] = true
                    end
                end
                a.questPeriodBaseline = nil
                a.questPeriodBaselineAtReset = true
            end
            local base = type(a.questPeriodBaseline) == "table" and a.questPeriodBaseline or nil
            if base or professionRow then
                for _, qid in ipairs(merged) do
                    local key = tostring(qid)
                    if flaggedNow and flaggedNow[key] and (not base or not base[key]) then
                        a.questPeriodCredited[key] = true
                    end
                end
                if type(a.questPeriodTurnIns) == "table" then
                    for _, qid in ipairs(merged) do
                        local key = tostring(qid)
                        if a.questPeriodTurnIns[key] then
                            a.questPeriodCredited[key] = true
                        end
                    end
                end
            end
            local count = math.max(0, tonumber(a.questPeriodOrphanCredits) or 0)
            local turnIns = a.questPeriodTurnIns
            for _, qid in ipairs(merged) do
                local key = tostring(qid)
                if a.questPeriodCredited[key] or (type(turnIns) == "table" and turnIns[key]) then
                    count = count + 1
                end
                count = count + questRepeatExtra(a, key)
            end
            node.taskCount = math.min(count, cap)
        end
        node.done = (node.taskCount or 0) >= cap
end

local function syncMobKill(node, a)
        a.mobKillMode = a.mobKillMode or "world" -- world | loot | boss
        if type(a.mobAutoCount) ~= "number" then
            a.mobAutoCount = tonumber(a.mobAutoCount) or 0
        end
        if type(a.mobIds) == "table" then
            for i = 1, #a.mobIds do
                local v = tonumber(a.mobIds[i])
                a.mobIds[i] = (v and v > 0) and math.floor(v) or nil
            end
        end
        if a.mobKillMode == "boss" then
            a.bossInstanceName = trim(a.bossInstanceName or "")
            if type(a.bossNames) == "string" then
                a.bossNames = TaskTracker.ParseBossNameListFromText(a.bossNames)
            end
            if type(a.bossNames) ~= "table" then
                a.bossNames = {}
            end
        end
        if node.taskUserValue == nil and node.doneOverride == nil then
            node.taskCount = math.max(0, tonumber(a.mobAutoCount) or 0)
        else
            node.taskCount = math.max(0, tonumber(node.taskCount) or 0)
        end
        node.taskMax = math.max(1, tonumber(node.taskMax) or 1)
        node.done = (node.taskCount or 0) >= (node.taskMax or 1)
end

local function syncCollectable(node, a)
        applyCollectableFarmItemProgress(node, a)
        local cap = math.max(1, tonumber(node.taskMax) or 1)
        node.taskMax = cap
        local owned = TaskTracker.IsCollectableTaskJournalOwned and TaskTracker.IsCollectableTaskJournalOwned(node)
        if node.taskUserValue == nil and node.doneOverride == nil then
            local q = math.max(0, tonumber(a.collectableAutoCount) or 0)
            local f = math.max(0, tonumber(a.collectableFishAttempts) or 0)
            node.taskCount = q + f
        else
            node.taskCount = math.max(0, tonumber(node.taskCount) or 0)
        end
        if owned and node.doneOverride ~= "incomplete" then
            node.done = true
        else
            node.done = (node.taskCount or 0) >= cap
        end
end

local SYNC_BY_TYPE = {
    achievement = syncAchievement,
    item        = syncItem,
    reputation  = syncReputation,
    gold        = syncGold,
    quest       = syncQuest,
    mob_kill    = syncMobKill,
    collectable = syncCollectable,
    mplus_hint  = function() end,
}

function TaskTracker.SyncAdvancedTask(node)
    if TaskTracker.TaskProgressIsLocked and TaskTracker.TaskProgressIsLocked(node) then return end
    if not TaskTracker.IsAdvancedTask(node) then return end
    if node.taskUserValue ~= nil or node.doneOverride ~= nil then
        return
    end
    local fn = SYNC_BY_TYPE[node.advanced.type]
    if not fn then return end
    local twoWay = TaskTracker.TwoWayShareCounts and TaskTracker.TwoWayShareCounts(node)
    local sharedBefore = twoWay and TaskTracker.PushTwoWayPersonalCount and TaskTracker.PushTwoWayPersonalCount(node) or nil
    fn(node, node.advanced)
    if sharedBefore and TaskTracker.PopTwoWayPersonalCount then
        TaskTracker.PopTwoWayPersonalCount(node, sharedBefore)
    end
end

local function collectableQuestFlaggedDone(qid)
    qid = tonumber(qid)
    if not qid or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return false end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
    return ok and done == true
end

local function collectableQuestSyncGraceActive()
    return TaskTracker._progressSyncGraceUntil and GetTime() < TaskTracker._progressSyncGraceUntil
end

--- Quest tally in `advanced.collectableAutoCount`; fishing in `advanced.collectableFishAttempts`.
--- `node.taskCount` is their sum when not manually locked.
function TaskTracker.UpdateCollectableFromQuestFlags(node)
    if TaskTracker.TaskProgressIsLocked and TaskTracker.TaskProgressIsLocked(node) then return end
    if not TaskTracker.IsAdvancedTask(node) or node.advanced.type ~= "collectable" then return end
    if not TaskTracker.GetCollectableQuestIdsForNodeAdvanced then return end
    local twoWay = TaskTracker.TwoWayShareCounts and TaskTracker.TwoWayShareCounts(node)
    local sharedBefore = twoWay and TaskTracker.PushTwoWayPersonalCount and TaskTracker.PushTwoWayPersonalCount(node) or nil
    local a = node.advanced
    local ids = TaskTracker.GetCollectableQuestIdsForNodeAdvanced(a)

    if type(a.collectableCredited) ~= "table" then
        a.collectableCredited = {}
    end

    if #ids > 0 then
        if not a.collectableInit then
            local creditedNow = 0
            for _, qid in ipairs(ids) do
                if collectableQuestFlaggedDone(qid) then
                    a.collectableCredited[tostring(qid)] = true
                    creditedNow = creditedNow + 1
                end
            end
            a.collectableInit = true
            if a.collectableAutoCount == nil then
                local tp = math.max(0, tonumber(node.taskCount) or 0)
                local fp = math.max(0, tonumber(a.collectableFishAttempts) or 0)
                local fromDisplay = math.max(0, tp - fp)
                a.collectableAutoCount = math.max(fromDisplay, creditedNow)
            end
        else
            if a.collectableAutoCount == nil then
                local tp = math.max(0, tonumber(node.taskCount) or 0)
                local fp = math.max(0, tonumber(a.collectableFishAttempts) or 0)
                a.collectableAutoCount = math.max(0, tp - fp)
            end
            for _, qid in ipairs(ids) do
                local key = tostring(qid)
                if collectableQuestFlaggedDone(qid) then
                    if not a.collectableCredited[key] then
                        a.collectableCredited[key] = true
                        a.collectableAutoCount = math.max(0, (tonumber(a.collectableAutoCount) or 0) + 1)
                    end
                elseif not (collectableQuestSyncGraceActive() and a.collectableCredited[key]) then
                    a.collectableCredited[key] = nil
                end
            end
        end
    else
        if a.collectableAutoCount == nil then
            a.collectableAutoCount = 0
        end
        if not a.collectableInit then
            a.collectableInit = true
        end
    end

    local questPart = math.max(0, tonumber(a.collectableAutoCount) or 0)
    local fishPart = math.max(0, tonumber(a.collectableFishAttempts) or 0)
    local auto = questPart + fishPart
    local cap = math.max(1, tonumber(node.taskMax) or 1)
    local owned = TaskTracker.IsCollectableTaskJournalOwned and TaskTracker.IsCollectableTaskJournalOwned(node)
    if node.taskUserValue == nil and node.doneOverride == nil then
        node.taskCount = auto
        node.done = owned or auto >= cap
    else
        node.done = owned or (math.max(0, tonumber(node.taskCount) or 0)) >= cap
        if node.doneOverride == "incomplete" then
            node.done = false
        end
    end
    if sharedBefore and TaskTracker.PopTwoWayPersonalCount then
        TaskTracker.PopTwoWayPersonalCount(node, sharedBefore)
    end
end

-- Mob kill automation (combat log / target / nameplates / loot sources) hits protected or unreliable
-- APIs inside dungeons, raids, and similar instances; skip it there. Boss-kill tasks use ENCOUNTER_END instead.
local mobKillInstanceCache = { at = 0, blocked = false }

function TaskTracker.InvalidateMobKillInstanceCache()
    mobKillInstanceCache.at = 0
    mobKillInstanceCache.blocked = false
end

local function isMobKillAutomationBlockedByInstance()
    local now = (GetTime and GetTime()) or 0
    if (now - mobKillInstanceCache.at) < 0.75 then
        return mobKillInstanceCache.blocked
    end
    mobKillInstanceCache.at = now
    mobKillInstanceCache.blocked = false
    if not GetInstanceInfo then return false end
    local ok, instanceType = pcall(function()
        return select(2, GetInstanceInfo())
    end)
    if not ok or type(instanceType) ~= "string" then return false end
    if instanceType == "party" or instanceType == "raid" or instanceType == "scenario"
        or instanceType == "arena" or instanceType == "pvp" then
        mobKillInstanceCache.blocked = true
    end
    return mobKillInstanceCache.blocked
end

-- Midnight: UnitGUID / combat-log destGUIDs can be secret strings while tainted.
-- strsplit, tostring, and table keys all error on them.
local function isSecretValue(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function publicString(v)
    if v == nil or isSecretValue(v) then return nil end
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

local function unitGuidPublic(unit)
    if not unit or not UnitGUID or isSecretValue(unit) then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return nil end
    return publicString(guid)
end

local function npcIdFromGuid(guid)
    -- Retail GUID format: Creature-0-...-<npcID>-<spawnUID>
    guid = publicString(guid)
    if not guid then return nil end
    local ok, unitType, npcId = pcall(function()
        local ut, _, _, _, _, id = strsplit("-", guid)
        return ut, id
    end)
    if not ok then return nil end
    if unitType ~= "Creature" and unitType ~= "Vehicle" and unitType ~= "Pet" then
        return nil
    end
    npcId = tonumber(npcId)
    if npcId and npcId > 0 then return npcId end
    return nil
end

local function lootObjectIdFromGuid(guid)
    -- GameObject-0-...-<objectID>-<spawnUID>
    guid = publicString(guid)
    if not guid then return nil end
    local ok, unitType, objId = pcall(function()
        local ut, _, _, _, _, id = strsplit("-", guid)
        return ut, id
    end)
    if not ok then return nil end
    if unitType ~= "GameObject" then return nil end
    objId = tonumber(objId)
    if objId and objId > 0 then return objId end
    return nil
end

local function mobDebugEnabled()
    return TaskTrackerDB and TaskTrackerDB.debugMobKill == true
end

local function mobDebugPrint(msg)
    if not mobDebugEnabled() then return end
    print("|cffffaa00TT Mob|r " .. tostring(msg))
end

local function anyMobKillTasks()
    for _, node in ipairs(advNodes("mob_kill")) do
        if taskVisibleForAutomation(node) then return true end
    end
    if anyExtraAdv("mob_kill", taskVisibleForAutomation) then return true end
    return false
end

local function anyCollectableNpcFarmTasks()
    if not TaskTracker._ttAdvIndex then
        TaskTracker.RebuildAdvancedTaskIndex()
    end
    local idx = TaskTracker._ttAdvIndex
    return idx and idx.anyCollectableNpc == true
end

local function anyCollectableLootFarmTasks()
    if not TaskTracker._ttAdvIndex then
        TaskTracker.RebuildAdvancedTaskIndex()
    end
    local idx = TaskTracker._ttAdvIndex
    return idx and (idx.anyCollectableNpc == true or idx.anyCollectableLootObj == true)
end

local function collectableFarmWantsNpc(npcId)
    npcId = tonumber(npcId)
    if not npcId or npcId <= 0 then return false end
    if not TaskTracker._ttAdvIndex then
        TaskTracker.RebuildAdvancedTaskIndex()
    end
    local idx = TaskTracker._ttAdvIndex
    local set = idx and idx.collectableNpcSet
    return set and set[npcId] == true
end

local function collectableFarmWantsLootObj(objectId)
    objectId = tonumber(objectId)
    if not objectId or objectId <= 0 then return false end
    if not TaskTracker._ttAdvIndex then
        TaskTracker.RebuildAdvancedTaskIndex()
    end
    local idx = TaskTracker._ttAdvIndex
    local set = idx and idx.collectableLootObjSet
    return set and set[objectId] == true
end

--- Credit catalog npcIds / lootObjectIds farms. Dedupes by source GUID.
local function incrementCollectableLootFarms(npcId, objectId, guid)
    local wantNpc = collectableFarmWantsNpc(npcId)
    local wantObj = collectableFarmWantsLootObj(objectId)
    if not wantNpc and not wantObj then return false end
    guid = publicString(guid)
    if guid then
        if MOBKILL.collectableKillSeen[guid] or (MOBKILL.loot and MOBKILL.loot.seen and MOBKILL.loot.seen[guid]) then
            return false
        end
    end
    local changed = false
    eachAdvNode("collectable", function(node)
        if taskVisibleForAutomation(node) and node.taskUserValue == nil then
            local a = node.advanced
            local ent = TaskTracker.GetCollectableEntry
                and TaskTracker.GetCollectableEntry(a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
            local match = false
            if wantNpc and TaskTracker.CollectableEntryMatchesNpc and TaskTracker.CollectableEntryMatchesNpc(ent, npcId) then
                match = true
            elseif wantObj and TaskTracker.CollectableEntryMatchesLootObject and TaskTracker.CollectableEntryMatchesLootObject(ent, objectId) then
                match = true
            end
            if match then
                a.collectableAutoCount = math.max(0, tonumber(a.collectableAutoCount) or 0) + 1
                if TaskTracker.SyncAdvancedTask then
                    TaskTracker.SyncAdvancedTask(node)
                end
                changed = true
            end
        end
    end)
    if changed and guid then
        MOBKILL.collectableKillSeen[guid] = true
        if MOBKILL.loot and MOBKILL.loot.seen then
            MOBKILL.loot.seen[guid] = true
        end
    end
    return changed
end

local function incrementCollectableNpcFarms(npcId, guid)
    return incrementCollectableLootFarms(npcId, nil, guid)
end

local function incrementMobKillTasks(npcId, mode, guid)
    if not npcId then return false end
    local changed = false
    if TaskTracker.TryCompleteRegistryKillTrack and TaskTracker.TryCompleteRegistryKillTrack(npcId) then
        changed = true
    end
    eachAdvNode("mob_kill", function(node)
        if taskVisibleForAutomation(node) then
            local a = node.advanced
            if a and (not mode or (a.mobKillMode or "world") == mode) then
                local ids = a.mobIds or {}
                local match = false
                for _, id in ipairs(ids) do
                    if (tonumber(id) or 0) == npcId then
                        match = true
                        break
                    end
                end
                if match then
                    local previous = tonumber(node.taskCount) or 0
                    a.mobAutoCount = math.max(0, tonumber(a.mobAutoCount) or 0) + 1
                    if node.taskUserValue == nil and node.doneOverride == nil then
                        if TaskTracker.TwoWayShareCounts and TaskTracker.TwoWayShareCounts(node) then
                            node.taskCount = previous + 1
                            node.liveSharePersonal = a.mobAutoCount
                        else
                            node.taskCount = a.mobAutoCount
                        end
                    end
                    node.done = (math.max(0, tonumber(node.taskCount) or 0)) >= (node.taskMax or 1)
                    changed = true
                end
            end
        end
    end)
    local lifeSubs = advNodes("subtextLifetime")
    if lifeSubs then
        for _, node in ipairs(lifeSubs) do
            if taskVisibleForAutomation(node) and type(node.subtext) == "table" then
                local ids = TaskTracker.SubtextMobIds(node)
                local match = false
                if type(ids) == "table" then
                    for _, id in ipairs(ids) do
                        if (tonumber(id) or 0) == npcId then
                            match = true
                            break
                        end
                    end
                end
                if match then
                    local adv = node.advanced
                    local sub = node.subtext
                    local usesFarm = sub.useTask == true and adv and adv.type == "collectable"
                    -- Rarity already stores attempts. Do not read or add lifetimeKills while that line is available.
                    if not usesFarm and not subtextRarityLine(node, sub) then
                        node.subtext.lifetimeKills = math.max(0, tonumber(node.subtext.lifetimeKills) or 0) + 1
                        changed = true
                        if TaskTracker.PersistOneCharTaskProgress then
                            TaskTracker.PersistOneCharTaskProgress(node)
                        end
                    end
                end
            end
        end
    end
    if incrementCollectableNpcFarms(npcId, guid) then
        changed = true
    end
    return changed
end

function TaskTracker.OnAdvancedRegenEnabled()
    -- Optional safety: clear pending cache when leaving combat to avoid stale GUIDs.
    if MOBKILL and MOBKILL.pending then
        wipe(MOBKILL.pending)
    end
    if MOBKILL and MOBKILL.fallback and MOBKILL.fallback.pending then
        wipe(MOBKILL.fallback.pending)
    end
    if MOBKILL and MOBKILL.collectableKillSeen then
        wipe(MOBKILL.collectableKillSeen)
    end
end

function TaskTracker.OnAdvancedRegenDisabled()
    -- If the player already had a target before entering combat, PLAYER_TARGET_CHANGED won't fire.
    -- Capture the current target as a pending candidate immediately on entering combat.
    if TaskTracker.OnAdvancedTargetChanged then
        TaskTracker.OnAdvancedTargetChanged()
    end
end

local function mobKillTasksMatchMode(mode)
    for _, node in ipairs(advNodes("mob_kill")) do
        if taskVisibleForAutomation(node) and ((node.advanced.mobKillMode or "world") == mode) then
            return true
        end
    end
    return anyExtraAdv("mob_kill", function(node)
        return taskVisibleForAutomation(node) and ((node.advanced.mobKillMode or "world") == mode)
    end)
end

-- Fallback path when COMBAT_LOG_EVENT_UNFILTERED cannot be registered (taint/protection).
-- This is less reliable than combat-log tracking: it counts a kill when a unit you targeted while
-- in combat is later removed from nameplates as dead.
function TaskTracker.OnAdvancedTargetChanged()
    local wantCol = anyCollectableNpcFarmTasks()
    if not mobKillTasksMatchMode("world") and not wantCol then return end
    if isMobKillAutomationBlockedByInstance() and not wantCol then return end
    if not UnitGUID or not UnitExists then return end
    if not UnitExists("target") then return end
    if not UnitCanAttack or not UnitCanAttack("player", "target") then return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("target") then return end
    if UnitAffectingCombat and not UnitAffectingCombat("player") then return end
    local guid = unitGuidPublic("target")
    if not guid then return end
    MOBKILL.fallback.pending[guid] = true
    if mobDebugEnabled() then
        local npc = npcIdFromGuid(guid)
        mobDebugPrint(("FB pending target guid=%s npc=%s"):format(tostring(guid), tostring(npc)))
    end
end

-- Midnight: UnitHealth on nameplates can be a secret number; `hp <= 0` errors while tainted.
local function unitHealthLooksDead(token)
    if not token or not UnitHealth then return false end
    local okH, hp = pcall(UnitHealth, token)
    if not okH then return false end
    if issecretvalue and issecretvalue(hp) then return false end
    local okC, deadHp = pcall(function()
        return type(hp) == "number" and hp <= 0
    end)
    return okC and deadHp == true
end

function TaskTracker.OnAdvancedNameplateRemoved(unitToken)
    if not unitToken or isSecretValue(unitToken) then return end
    local guid = unitGuidPublic(unitToken)
    if not guid then return end

    -- Registry NPC kills (e.g. Nullaeus in a delve) are allowed in instances; custom
    -- world-kill tasks are not. Only count when the plate is actually dead.
    local npcId = npcIdFromGuid(guid)
    if npcId and TaskTracker.NpcToRegistry and TaskTracker.NpcToRegistry[npcId] then
        local dead = nil
        if UnitIsDeadOrGhost then
            local okD, vD = pcall(UnitIsDeadOrGhost, unitToken)
            if okD then dead = (vD == true) end
        end
        if dead == false and unitHealthLooksDead(unitToken) then
            dead = true
        end
        if dead == true then
            if TaskTracker.TryCompleteRegistryKillTrack and TaskTracker.TryCompleteRegistryKillTrack(npcId) then
                -- Refresh is done inside TryCompleteRegistryKillTrack.
            end
        end
    end

    -- O(1) pending-GUID check before any tree/index walk.
    if MOBKILL.fallback.pending[guid] ~= true then return end
    local wantWorld = mobKillTasksMatchMode("world")
    local wantCol = anyCollectableNpcFarmTasks()
    if not wantWorld and not wantCol then return end
    local instBlocked = isMobKillAutomationBlockedByInstance()
    if instBlocked and not wantCol then return end
    if mobDebugEnabled() then
        mobDebugPrint(("FB nameplate removed unit=%s guid=%s"):format(tostring(unitToken), tostring(guid)))
    end

    -- NAME_PLATE_UNIT_REMOVED often fires when the unit becomes unqueryable, so strict
    -- UnitIsDeadOrGhost gating can prevent all counts. Prefer a permissive count here.
    -- We still try a "dead" check if possible, but do not require it.
    local dead = nil
    if UnitIsDeadOrGhost then
        local okD, vD = pcall(UnitIsDeadOrGhost, unitToken)
        if okD then dead = (vD == true) end
    end
    if dead == false and unitHealthLooksDead(unitToken) then
        dead = true
    end
    MOBKILL.fallback.pending[guid] = nil
    npcId = npcId or npcIdFromGuid(guid)
    if mobDebugEnabled() then
        mobDebugPrint(("FB removed (dead=%s) guid=%s npc=%s"):format(tostring(dead), tostring(guid), tostring(npcId)))
    end
    local changed = false
    if npcId then
        if wantWorld and not instBlocked then
            changed = incrementMobKillTasks(npcId, "world", guid)
        elseif wantCol then
            changed = incrementCollectableNpcFarms(npcId, guid)
        end
    end
    if changed then
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then TaskTracker.RefreshList() end
    end
end

-- Loot-based kill counting: count when loot window contains a corpse source matching NPC id.
local function processLootSources()
    local wantCustom = mobKillTasksMatchMode("loot")
    local wantCol = anyCollectableLootFarmTasks()
    local wantRegNpc = TaskTracker.NpcToRegistry and next(TaskTracker.NpcToRegistry) ~= nil
    local wantRegObj = TaskTracker.LootObjectToRegistry and next(TaskTracker.LootObjectToRegistry) ~= nil
    local wantReg = wantRegNpc or wantRegObj
    if not wantCustom and not wantReg and not wantCol then return end
    local instBlocked = isMobKillAutomationBlockedByInstance()
    if instBlocked and not wantReg and not wantCol then return end
    if not GetNumLootItems or not GetLootSourceInfo then return end
    local n = 0
    pcall(function() n = GetNumLootItems() or 0 end)
    if n <= 0 then return end
    local counted = false
    for slot = 1, n do
        -- GetLootSourceInfo returns a flat guid1, quantity1, guid2, quantity2, ... list
        -- (no leading count), so walk the pcall results two at a time from the first guid.
        local packed = { pcall(GetLootSourceInfo, slot) }
        if packed[1] then
            for i = 2, #packed - 1, 2 do
                local guid = publicString(packed[i])
                if guid and not MOBKILL.loot.seen[guid] then
                    local npcId = npcIdFromGuid(guid)
                    local objId = lootObjectIdFromGuid(guid)
                    local countedThis = false
                    if wantReg and (npcId or objId) and TaskTracker.TryCompleteRegistryKillTrack then
                        if TaskTracker.TryCompleteRegistryKillTrack(npcId, nil, objId) then
                            countedThis = true
                        end
                    end
                    if npcId then
                        if wantCustom and not instBlocked then
                            if incrementMobKillTasks(npcId, nil, guid) then
                                countedThis = true
                            end
                        elseif wantCol then
                            if incrementCollectableLootFarms(npcId, objId, guid) then
                                countedThis = true
                            end
                        end
                    elseif wantCol and objId then
                        if incrementCollectableLootFarms(nil, objId, guid) then
                            countedThis = true
                        end
                    end
                    if countedThis then
                        counted = true
                        MOBKILL.loot.seen[guid] = true
                        if mobDebugEnabled() then
                            mobDebugPrint(("LOOT counted guid=%s npc=%s obj=%s"):format(
                                tostring(guid), tostring(npcId), tostring(objId)))
                        end
                    end
                end
            end
        end
    end
    if counted then
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then TaskTracker.RefreshList() end
    end
end

function TaskTracker.OnAdvancedLootEvent(_eventName)
    processLootSources()
end

-- Boss/encounter counting: partial instance and boss names, from the kill event.
local function getInstanceName()
    if not GetInstanceInfo then return nil end
    local ok, name = pcall(function()
        return (GetInstanceInfo())
    end)
    if not ok then return nil end
    return name
end

function TaskTracker.OnAdvancedEncounterEnd(encounterID, encounterName, _difficultyID, _groupSize, success)
    -- Retail can pass success as 1 or true.
    if success ~= true and tonumber(success) ~= 1 then return end
    local enm = tostring(encounterName or "")
    if TaskTracker.TryCompleteRegistryKillTrack then
        TaskTracker.TryCompleteRegistryKillTrack(nil, enm)
    end
    if not mobKillTasksMatchMode("boss") then return end
    local inst = getInstanceName() or ""
    local eid = tonumber(encounterID)
    MOBKILL.bossLast = { inst = inst, name = enm, id = eid }
    local changed = false
    eachAdvNode("mob_kill", function(node)
        local a = node.advanced
        if taskVisibleForAutomation(node) and a and (a.mobKillMode or "world") == "boss"
            and node.taskUserValue == nil and node.doneOverride == nil then
            local wantInst = trim(a.bossInstanceName or "")
            local instOk = wantInst == "" or (TaskTracker.BossJournalNameMatches and TaskTracker.BossJournalNameMatches(wantInst, inst))
            if instOk then
                local names = a.bossNames or {}
                local match = false
                for _, nm in ipairs(names) do
                    if TaskTracker.BossJournalNameMatches and TaskTracker.BossJournalNameMatches(nm, enm) then
                        match = true
                        break
                    end
                end
                if match then
                    node.taskCount = math.max(0, (tonumber(node.taskCount) or 0) + 1)
                    node.done = (node.taskCount or 0) >= (node.taskMax or 1)
                    changed = true
                    if mobDebugEnabled() then
                        mobDebugPrint(("BOSS counted inst=%s boss=%s eid=%s"):format(tostring(inst), tostring(enm), tostring(eid)))
                    end
                end
            end
        end
    end)
    if changed then
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then TaskTracker.RefreshList() end
    end
end

function TaskTracker.OnAdvancedCombatLogEvent()
    local ts, subEvent, _, srcGUID, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if not subEvent then return end
    srcGUID = publicString(srcGUID)
    destGUID = publicString(destGUID)
    if not destGUID then return end
    local wantMk = anyMobKillTasks()
    local wantCol = anyCollectableNpcFarmTasks()
    if not mobDebugEnabled() and not wantMk and not wantCol then return end

    local instBlocked = isMobKillAutomationBlockedByInstance()
    if instBlocked and not wantCol then return end

    -- Debug: prove combat log delivery (even without any mob_kill tasks).
    if mobDebugEnabled() then
        MOBKILL._dbg = MOBKILL._dbg or { last = 0 }
        local now = GetTime and GetTime() or 0
        -- Throttle generic kill prints so chat isn't spammed.
        if (subEvent == "PARTY_KILL" or subEvent == "UNIT_DIED") and (now - (MOBKILL._dbg.last or 0)) > 0.15 then
            MOBKILL._dbg.last = now
            local npcId = npcIdFromGuid(destGUID)
            mobDebugPrint(("%s dest=%s npc=%s"):format(tostring(subEvent), tostring(destGUID), tostring(npcId)))
        end
    end

    if not wantMk and not wantCol then
        return
    end

    -- Mark pending when we can confidently say the kill belongs to us/our party.
    if subEvent == "PARTY_KILL" then
        -- PARTY_KILL is already a "someone in your group got the kill" signal; count it directly.
        -- We still mark pending so a later UNIT_DIED can also count if needed, but we prefer to
        -- increment here because UNIT_DIED can be unreliable in some edge cases (phasing/range).
        MOBKILL.pending[destGUID] = true
        local npcId = npcIdFromGuid(destGUID)
        mobDebugPrint(("PARTY_KILL dest=%s npc=%s"):format(tostring(destGUID), tostring(npcId)))
        local changed = false
        if npcId then
            if not instBlocked then
                changed = incrementMobKillTasks(npcId, "world", destGUID)
            else
                changed = incrementCollectableNpcFarms(npcId, destGUID)
            end
        end
        if changed then
            mobDebugPrint(("INCREMENT (PARTY_KILL) npc=%s"):format(tostring(npcId)))
            if TaskTracker.MarkListDirtyFromProgressChange then
                TaskTracker.MarkListDirtyFromProgressChange()
            end
            if TaskTracker.RefreshList then TaskTracker.RefreshList() end
        end
        return
    end

    -- Optional: mark pending when we personally damaged the unit (helps when PARTY_KILL isn't fired).
    if subEvent == "SWING_DAMAGE" or subEvent == "RANGE_DAMAGE" or subEvent == "SPELL_DAMAGE"
        or subEvent == "SPELL_PERIODIC_DAMAGE" or subEvent == "ENVIRONMENTAL_DAMAGE" then
        if srcGUID and (srcGUID == unitGuidPublic("player") or srcGUID == unitGuidPublic("pet")) then
            MOBKILL.pending[destGUID] = true
            local npcId = npcIdFromGuid(destGUID)
            mobDebugPrint(("DAMAGE %s src=me dest=%s npc=%s"):format(tostring(subEvent), tostring(destGUID), tostring(npcId)))
        end
        return
    end

    -- Increment only on the death signal (UNIT_DIED is a combat-log subevent).
    if subEvent == "UNIT_DIED" then
        local npcId = npcIdFromGuid(destGUID)
        mobDebugPrint(("UNIT_DIED dest=%s npc=%s pending=%s"):format(tostring(destGUID), tostring(npcId), tostring(MOBKILL.pending[destGUID] and true or false)))
        if not MOBKILL.pending[destGUID] then
            return
        end
        MOBKILL.pending[destGUID] = nil
        local changed = false
        if npcId then
            if not instBlocked then
                changed = incrementMobKillTasks(npcId, "world", destGUID)
            else
                changed = incrementCollectableNpcFarms(npcId, destGUID)
            end
        end
        if changed then
            mobDebugPrint(("INCREMENT (UNIT_DIED) npc=%s"):format(tostring(npcId)))
            if TaskTracker.MarkListDirtyFromProgressChange then
                TaskTracker.MarkListDirtyFromProgressChange()
            end
            if TaskTracker.RefreshList then TaskTracker.RefreshList() end
        end
        return
    end
end

--- Clear checkbox-only overrides and manual count locks when they match automated progress (cyan bar).
function TaskTracker.TryNormalizeTaskOverrideAndLock(node)
    if not node or node.type ~= "task" then return end
    local tm = node.taskMax or 1
    if tm <= 1 then return end

    if TaskTracker.IsAdvancedTask(node) and node.taskUserValue ~= nil then
        local locked = node.taskUserValue
        local dov = node.doneOverride
        local advType = node.advanced.type
        if advType == "item" or advType == "collectable" then
            local synced = TaskTracker.GetTaskAutomatedCount(node)
            if locked == synced then
                node.taskUserValue = nil
                node.taskCount = synced
                if dov == "complete" and synced >= tm then
                    node.doneOverride = nil
                elseif dov == "incomplete" and synced < tm then
                    node.doneOverride = nil
                else
                    node.doneOverride = dov
                end
            end
            return
        end
        node.taskUserValue = nil
        node.doneOverride = nil
        TaskTracker.SyncAdvancedTask(node)
        local synced = node.taskCount
        if locked == synced then
            node.taskUserValue = nil
            node.taskCount = synced
            if dov == "complete" and synced >= tm then
                node.doneOverride = nil
            elseif dov == "incomplete" and synced < tm then
                node.doneOverride = nil
            else
                node.doneOverride = dov
            end
        else
            node.taskUserValue = locked
            node.taskCount = synced
            node.doneOverride = dov
        end
        return
    end

    if TaskTracker.IsAdvancedTask(node) and node.doneOverride ~= nil then
        local dov = node.doneOverride
        node.doneOverride = nil
        if node.advanced.type == "collectable" then
            TaskTracker.UpdateCollectableFromQuestFlags(node)
        end
        TaskTracker.SyncAdvancedTask(node)
        local synced = node.taskCount
        if dov == "complete" and synced >= tm then
            node.doneOverride = nil
        elseif dov == "incomplete" and synced < tm then
            node.doneOverride = nil
        else
            node.doneOverride = dov
        end
        return
    end

    local c = node.taskCount or 0
    if node.doneOverride == "complete" and c >= tm then
        node.doneOverride = nil
    elseif node.doneOverride == "incomplete" and c < tm then
        node.doneOverride = nil
    end
end

function TaskTracker.SyncAllAdvancedTasks()
    if not IsPlayerInWorld() then return end
    if not TaskTracker._activeCharProgressKey then
        local n = TaskTracker._ttSyncWaitN or 0
        if n < 30 and C_Timer and C_Timer.After and not TaskTracker._ttSyncWaitChar then
            TaskTracker._ttSyncWaitN = n + 1
            TaskTracker._ttSyncWaitChar = true
            C_Timer.After(1, function()
                TaskTracker._ttSyncWaitChar = nil
                TaskTracker.SyncAllAdvancedTasks()
            end)
        end
        return
    end
    TaskTracker._ttSyncWaitN = nil
    for kind in pairs(ADV_INDEX_KINDS) do
        eachAdvNode(kind, function(node)
            if TaskTracker.TaskProgressIsLocked and TaskTracker.TaskProgressIsLocked(node) then return end
            if taskVisibleForAutomation(node) then
                TaskTracker.TryNormalizeTaskOverrideAndLock(node)
                if node.advanced and node.advanced.type == "collectable" then
                    TaskTracker.UpdateCollectableFromQuestFlags(node)
                end
                TaskTracker.SyncAdvancedTask(node)
            end
        end)
    end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

--- Journal/toy-box ownership for advanced collectable tasks. Uses existing collection events (no extra registers).
function TaskTracker.SyncCollectableTasksFromJournal()
    if not IsPlayerInWorld() then return false end
    local changed = false
    local wasDone = {}
    for _, node in ipairs(advNodes("collectable")) do
        if taskVisibleForAutomation(node) then
            wasDone[node] = node.done and true or false
        end
    end
    local idx = TaskTracker._ttAdvIndex
    local extras = idx and idx.extra and idx.extra.collectable
    if extras then
        for i = 1, #extras do
            local node = extras[i].node
            if wasDone[node] == nil and taskVisibleForAutomation(node) and TaskTracker.IsTaskEffectivelyDone then
                wasDone[node] = TaskTracker.IsTaskEffectivelyDone(node) and true or false
            end
        end
    end
    eachAdvNode("collectable", function(node)
        if not taskVisibleForAutomation(node) then return end
        TaskTracker.UpdateCollectableFromQuestFlags(node)
        TaskTracker.SyncAdvancedTask(node)
    end)
    for node, was in pairs(wasDone) do
        local now
        if node.advanced and node.advanced.type == "collectable" and not TaskTracker.TaskHasExtraGoals(node) then
            now = TaskTracker.IsTaskEffectivelyDone and TaskTracker.IsTaskEffectivelyDone(node)
        else
            now = TaskTracker.IsTaskEffectivelyDone and TaskTracker.IsTaskEffectivelyDone(node)
        end
        if (now and true or false) ~= was then
            changed = true
        end
    end
    return changed
end

function TaskTracker.OnAchievementOrCriteriaEvent()
    -- CRITERIA_UPDATE can be extremely chatty. Debounce and only repaint if tracked achievement tasks changed.
    TaskTracker._ttAdvAch = TaskTracker._ttAdvAch or {}
    local st = TaskTracker._ttAdvAch

    local function sig(node)
        if not node then return "" end
        -- Include fields that affect list display/behavior.
        return table.concat({
            tostring(node.taskCount or 0),
            tostring(node.taskMax or 1),
            tostring(node.done and 1 or 0),
            tostring(node.doneOverride or ""),
            tostring(node.taskUserValue or ""),
        }, "\31")
    end

    local function execute()
        st.timer = nil
        if not IsPlayerInWorld() then return end

        local anyChanged = false
        eachAdvNode("achievement", function(node)
            if taskVisibleForAutomation(node) then
                local before = sig(node)
                TaskTracker.TryNormalizeTaskOverrideAndLock(node)
                TaskTracker.SyncAdvancedTask(node)
                if before ~= sig(node) then
                    anyChanged = true
                end
            end
        end)

        if anyChanged and TaskTracker.RefreshList then
            if TaskTracker.MarkListDirtyFromProgressChange then
                TaskTracker.MarkListDirtyFromProgressChange()
            end
            TaskTracker.RefreshList()
        end
    end

    if st.timer then
        st.timer:Cancel()
        st.timer = nil
    end
    st.timer = C_Timer.NewTimer(0.35, execute)
end

function TaskTracker.OnFactionReputationEvent()
    TaskTracker.InvalidateAdvancedFactionDataCache()
    TaskTracker._ttAdvRep = TaskTracker._ttAdvRep or {}
    local st = TaskTracker._ttAdvRep

    local function sig(node)
        if not node then return "" end
        return table.concat({
            tostring(node.taskCount or 0),
            tostring(node.taskMax or 1),
            tostring(node.done and 1 or 0),
            tostring(node.doneOverride or ""),
            tostring(node.taskUserValue or ""),
        }, "\31")
    end

    local function execute()
        st.timer = nil
        local anyChanged = false
        eachAdvNode("reputation", function(node)
            if taskVisibleForAutomation(node) then
                local before = sig(node)
                TaskTracker.TryNormalizeTaskOverrideAndLock(node)
                TaskTracker.SyncAdvancedTask(node)
                if before ~= sig(node) then
                    anyChanged = true
                end
            end
        end)
        if TaskTracker.CheckRegistryProgress then
            if TaskTracker.CheckRegistryProgress() ~= false then
                anyChanged = true
            end
        end
        if anyChanged then
            if TaskTracker.MarkListDirtyFromProgressChange then
                TaskTracker.MarkListDirtyFromProgressChange()
            end
            if TaskTracker.RefreshList then TaskTracker.RefreshList() end
        end
    end

    if st.timer then
        st.timer:Cancel()
        st.timer = nil
    end
    st.timer = C_Timer.NewTimer(0.25, execute)
end

--- A listed quest was turned in. A daily or weekly task counts that turn-in.
--- The first one this period counts once. A later turn-in of that same quest
--- adds another, up to the goal. An older flag that never cleared does not.
function TaskTracker.NoteAdvancedQuestTurnIn(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then return end
    local key = tostring(questID)
    eachAdvNode("quest", function(node)
        if TaskTracker.TaskProgressIsLocked and TaskTracker.TaskProgressIsLocked(node) then return end
        if not taskVisibleForAutomation(node) then return end
        local rst = node.reset or "none"
        if rst == "none" or rst == "temporary" then return end
        local a = node.advanced
        local ids = a and a.questIds
        if type(ids) ~= "table" or #ids < 1 then return end
        local hit = false
        for i = 1, #ids do
            if tonumber(ids[i]) == questID then
                hit = true
                break
            end
        end
        if not hit then return end
        local cap = tonumber(node.taskMax) or 1
        if cap < 1 then cap = 1 end
        local turned = type(a.questPeriodTurnIns) == "table" and a.questPeriodTurnIns[key]
        local reps = questRepeatExtra(a, key)
        -- A pool already counted this id from a flag this period. This turn-in is another finish.
        -- One quest id latches a stuck flag, so that credit is not an earlier turn-in.
        local poolCredit = #ids > 1 and type(a.questPeriodCredited) == "table" and a.questPeriodCredited[key]
        if turned or reps > 0 or poolCredit then
            if type(a.questPeriodRepeatCounts) ~= "table" then
                a.questPeriodRepeatCounts = {}
            end
            local n = reps + 1
            if n > cap then n = cap end
            a.questPeriodRepeatCounts[key] = n
        else
            if type(a.questPeriodTurnIns) ~= "table" then
                a.questPeriodTurnIns = {}
            end
            a.questPeriodTurnIns[key] = true
        end
    end)
end

function TaskTracker.OnAdvancedQuestProgress()
    if not IsPlayerInWorld() then return end
    local function taskProgressSig(n)
        return table.concat({
            tostring(n.taskCount or 0),
            tostring(n.done and 1 or 0),
            tostring(n.doneOverride or ""),
            tostring(n.taskUserValue or ""),
        }, "\31")
    end

    local anyChanged = false
    local function syncKind(kind, fromQuestFlags)
        eachAdvNode(kind, function(node)
            if TaskTracker.TaskProgressIsLocked and TaskTracker.TaskProgressIsLocked(node) then return end
            if taskVisibleForAutomation(node) then
                local before = taskProgressSig(node)
                TaskTracker.TryNormalizeTaskOverrideAndLock(node)
                if fromQuestFlags then
                    TaskTracker.UpdateCollectableFromQuestFlags(node)
                end
                TaskTracker.SyncAdvancedTask(node)
                if before ~= taskProgressSig(node) then
                    anyChanged = true
                end
            end
        end)
    end
    syncKind("quest", false)
    syncKind("collectable", true)

    if not anyChanged then return end
    if TaskTracker.MarkListDirtyFromProgressChange then
        TaskTracker.MarkListDirtyFromProgressChange()
    end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

--- List progress column for advanced gold (whole gold units).
function TaskTracker.FormatAdvancedCountDisplay(node, done, total)
    if TaskTracker.IsAdvancedTask(node) and node.advanced.itemTrackMode == "remaining" then
        local n = node.taskUserValue
        if type(n) ~= "number" then
            n = node.taskCount or 0
        end
        n = math.max(0, math.floor(tonumber(n) or 0))
        if n <= 0 then
            return TaskTracker.WrapColor("0", "complete")
        end
        return TaskTracker.WrapColor(tostring(n), "textPrimary")
    end
    if TaskTracker.IsAdvancedTask(node) and node.advanced.type == "gold" then
        local d, t = tonumber(done) or 0, tonumber(total) or 0
        if t <= 0 then
            return TaskTracker.CountText(0, 0)
        elseif d >= t then
            return TaskTracker.WrapColor(TaskTracker.FormatGoldAmountForDisplay(d) .. " / "
                .. TaskTracker.FormatGoldAmountForDisplay(t) .. " g", "complete")
        else
            return TaskTracker.WrapColor(TaskTracker.FormatGoldAmountForDisplay(d), "textPrimary")
                .. TaskTracker.WrapColor(" / " .. TaskTracker.FormatGoldAmountForDisplay(t) .. " g", "textSecondary")
        end
    end
    return TaskTracker.CountText(done, total)
end

--- Count line for a task with extra goals. Nil when the task has one goal.
function TaskTracker.FormatTaskGoalSummary(node)
    if not TaskTracker.TaskHasExtraGoals(node) then return nil end
    local joiner = node.goalMode == "any" and " or " or " and "
    local function piece(rec)
        local c = rec.taskUserValue
        if type(c) ~= "number" then c = rec.taskCount or 0 end
        local m = rec.taskMax or 1
        local view = rec
        if rec ~= node then
            view = {
                type = "task",
                id = node.id,
                advanced = rec.advanced,
                taskMax = m,
                taskCount = rec.taskCount,
                taskUserValue = rec.taskUserValue,
            }
        end
        if TaskTracker.FormatAdvancedCountDisplay then
            return TaskTracker.FormatAdvancedCountDisplay(view, c, m)
        end
        return TaskTracker.CountText(c, m)
    end
    local parts = { piece(node) }
    for i = 1, #node.extraGoals do
        parts[#parts + 1] = piece(node.extraGoals[i])
    end
    return table.concat(parts, joiner)
end
