-- Core/TaskTracker.lua
-- Bootstrap file: addon load, events, slash commands
-- This file ties everything together

TaskTracker = TaskTracker or {}

-- ─────────────────────────────────────
-- Event handler
-- ─────────────────────────────────────
-- Some setups are treating Frame:RegisterEvent() as protected and throwing ADDON_ACTION_FORBIDDEN
-- during early load. To avoid spamming errors and "poisoning" the addon, we do a late, conservative
-- registration pass (out of combat, in-world) with exponential backoff.
local frame = CreateFrame("Frame")
--- Used by UI/DebugPanel.lua (e.g. UNIT_SPELLCAST_SENT registration line for fish debug).
TaskTracker._ttCoreBootstrapFrame = frame
local clFrame = CreateFrame("Frame") -- dedicated combat-log listener (some UIs refuse CLUE on the main frame)

frame._ttLegacyHandlers = frame._ttLegacyHandlers or {}
frame._ttEventsRegistered = frame._ttEventsRegistered or false
frame._ttCombatLogRegistered = frame._ttCombatLogRegistered or false

local CORE_EVENTS = {
    "ADDON_LOADED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LOGOUT",
    "BAG_UPDATE",
    "QUEST_TURNED_IN",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "PLAYER_MONEY",
    "ACHIEVEMENT_EARNED",
    "CRITERIA_UPDATE",
    "UPDATE_FACTION",
    "CURRENCY_DISPLAY_UPDATE",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    -- Fallback kill detection (does not require combat log registration)
    "PLAYER_TARGET_CHANGED",
    "NAME_PLATE_UNIT_REMOVED",
    -- Loot + encounters (no combat log required)
    "LOOT_READY",
    "LOOT_OPENED",
    "ENCOUNTER_END",
    "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_LEVEL_UP",
    "WEEKLY_REWARDS_UPDATE",
    "UPDATE_INSTANCE_INFO",
    "UNIT_SPELLCAST_SENT",
    "NEW_MOUNT_ADDED",
    "NEW_PET_ADDED",
    "NEW_TOY_ADDED",
    "TOYS_UPDATED",
    "COMPANION_LEARNED",
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
    "CHAT_MSG_ADDON",
}

local function canSafelyRegisterEvents()
    if InCombatLockdown and InCombatLockdown() then return false end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return false end
    if IsPlayerInWorld and not IsPlayerInWorld() then return false end
    return true
end

-- COMBAT_LOG_EVENT_UNFILTERED stays off the main frame. Some UIs treat RegisterEvent /
-- UnregisterEvent as protected (ADDON_ACTION_FORBIDDEN). Only unregister when we actually
-- registered, and never in combat.
local function tryUnregisterCombatLogOnly()
    if not clFrame._ttRegistered and not frame._ttCombatLogRegistered then
        clFrame._ttUnregisterWhenSafe = nil
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        clFrame._ttUnregisterWhenSafe = true
        return
    end
    local registered = clFrame._ttRegistered == true
    if clFrame.IsEventRegistered then
        local ok, v = pcall(function()
            return clFrame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")
        end)
        if ok then
            registered = v == true
        end
    end
    if registered and clFrame.UnregisterEvent then
        pcall(function()
            clFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end)
    end
    clFrame._ttRegistered = false
    frame._ttCombatLogRegistered = false
    clFrame._ttUnregisterWhenSafe = nil
end

local function tryRegisterCombatLogOnly()
    if clFrame._ttRegistered then return true end
    if clFrame._ttForbidden then return false end
    if not canSafelyRegisterEvents() then return false end
    local ok = pcall(function()
        clFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end)
    local registered = false
    if ok and clFrame.IsEventRegistered then
        local ok2, v = pcall(function()
            return clFrame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")
        end)
        registered = ok2 and v == true
    elseif ok then
        registered = true
    end
    if registered then
        clFrame._ttRegistered = true
        frame._ttCombatLogRegistered = true
        return true
    end
    clFrame._ttForbidden = true
    return false
end

function TaskTracker.RefreshCombatLogKillRegistration()
    local want = TaskTrackerDB and TaskTrackerDB.combatLogKillTracking == true
    if want then
        clFrame._ttUnregisterWhenSafe = nil
        tryRegisterCombatLogOnly()
    elseif clFrame._ttRegistered or frame._ttCombatLogRegistered or clFrame._ttUnregisterWhenSafe then
        tryUnregisterCombatLogOnly()
    end
    return clFrame._ttRegistered == true
end

function TaskTracker.ToggleCombatLogKillTracking()
    TaskTrackerDB = TaskTrackerDB or {}
    TaskTrackerDB.combatLogKillTracking = not (TaskTrackerDB.combatLogKillTracking == true)
    clFrame._ttForbidden = nil
    local on = TaskTrackerDB.combatLogKillTracking == true
    local ok = TaskTracker.RefreshCombatLogKillRegistration()
    if on and ok then
        print("|cff00ff00TaskTracker|r Combat-log kill tracking: ON (registered). World-mode kill tasks use the combat log; nameplate fallback still runs.")
    elseif on and not ok then
        print("|cff00ff00TaskTracker|r Combat-log kill tracking: wanted ON, but RegisterEvent failed. World-mode kills stay on the nameplate fallback. Another addon/UI may be blocking COMBAT_LOG_EVENT_UNFILTERED.")
    else
        print("|cff00ff00TaskTracker|r Combat-log kill tracking: OFF. World-mode kills use target + nameplate removal.")
    end
    if TaskTracker.RefreshDebugPanelIfShown then
        TaskTracker.RefreshDebugPanelIfShown()
    end
    return on
end

local function TryRegisterCoreEventsLater(delay)
    delay = tonumber(delay) or 0.5
    if delay < 0.25 then delay = 0.25 end
    if delay > 30 then delay = 30 end
    if frame._ttEventsRegistered then return end
    C_Timer.After(delay, function()
        if frame._ttEventsRegistered then return end
        frame._ttEventReg = frame._ttEventReg or { attempts = 0, lastDelay = 0, lastOk = nil, lastAt = 0 }
        frame._ttEventReg.attempts = (frame._ttEventReg.attempts or 0) + 1
        frame._ttEventReg.lastDelay = delay
        frame._ttEventReg.lastAt = (GetTime and GetTime()) or 0
        if not canSafelyRegisterEvents() then
            frame._ttEventReg.lastOk = false
            TryRegisterCoreEventsLater(math.min(30, delay * 1.6))
            return
        end
        -- Attempt to register everything best-effort. Some events may fail to stick in a tainted UI;
        -- keep the ones that succeed and retry the failures with backoff.
        local anyFailed = false
        for _, ev in ipairs(CORE_EVENTS) do
            frame._ttLegacyHandlers[ev] = frame._ttLegacyHandlers[ev] or true
            local already = false
            if frame.IsEventRegistered then
                local ok0, v0 = pcall(function() return frame:IsEventRegistered(ev) end)
                already = ok0 and v0 == true
            end
            local ok = true
            if not already then
                ok = pcall(function()
                    frame:RegisterEvent(ev)
                end)
            end
            local registered = already
            if not registered and ok and frame.IsEventRegistered then
                local ok2, v = pcall(function() return frame:IsEventRegistered(ev) end)
                registered = ok2 and v == true
            elseif not registered and ok and not frame.IsEventRegistered then
                registered = true
            end

            frame._ttEventReg.byEvent = frame._ttEventReg.byEvent or {}
            frame._ttEventReg.byEvent[ev] = registered and true or false

            if not ok or not registered then
                anyFailed = true
            end
        end
        if anyFailed then
            frame._ttEventReg.lastOk = false
            TryRegisterCoreEventsLater(math.min(30, delay * 1.8 + 0.6))
            return
        end
        frame._ttEventsRegistered = true
        frame._ttEventReg.lastOk = true
        -- The login entering-world event already fired. Enter now if the name
        -- was missing when the addon loaded, so this character's profile is applied.
        if not TaskTracker._activeCharProgressKey and TaskTracker.OnCharacterEnter then
            TaskTracker.OnCharacterEnter(true)
        end
        if TaskTracker.ScheduleRestoreOpenNotePeeks then
            TaskTracker.ScheduleRestoreOpenNotePeeks()
        end
        if TaskTracker.ScheduleLiveShareLogin then
            TaskTracker.ScheduleLiveShareLogin()
        end
    end)
end

local function RefreshSourceEnabled()
    local db = TaskTrackerDB
    return db and db.debugRefreshSource == true
end

local function NoteRefreshSource(source)
    if not RefreshSourceEnabled() then return end
    TaskTracker._ttRefreshSource = TaskTracker._ttRefreshSource or { counts = {} }
    local st = TaskTracker._ttRefreshSource
    st.last = source
    st.lastAt = GetTime and GetTime() or 0
    st.counts[source] = (st.counts[source] or 0) + 1
end

local function SyncRegistryAndList(source)
    if not IsPlayerInWorld() then return end
    local changed = true
    if TaskTracker.CheckRegistryProgress then
        changed = TaskTracker.CheckRegistryProgress() ~= false
    end
    if TaskTracker.SyncCollectableTasksFromJournal then
        if TaskTracker.SyncCollectableTasksFromJournal() then
            changed = true
        end
    end
    if TaskTracker.SweepCompletedTemporaryTasks and TaskTracker.SweepCompletedTemporaryTasks() then
        changed = true
        if TaskTracker.MarkListLayoutDirty then
            TaskTracker.MarkListLayoutDirty()
        end
    end
    if TaskTracker.RefreshList then
        if changed then
            if TaskTracker.MarkListDirtyFromProgressChange then
                TaskTracker.MarkListDirtyFromProgressChange()
            end
            NoteRefreshSource(source or "SyncRegistryAndList")
            TaskTracker.RefreshList()
        end
    end
end

--- Quest completion data is often empty until after the world is available; refresh again later.
local pewDeferredTimers = {}

local function CancelPewDeferredWork()
    for i = 1, #pewDeferredTimers do
        local t = pewDeferredTimers[i]
        if t and t.Cancel then
            t:Cancel()
        end
    end
    wipe(pewDeferredTimers)
end

local function AfterPew(delay, fn)
    pewDeferredTimers[#pewDeferredTimers + 1] = C_Timer.NewTimer(delay, fn)
end

local function ScheduleRegistrySync(delay)
    delay = delay or 0.35
    AfterPew(delay, function()
        SyncRegistryAndList("ScheduleRegistrySync(" .. tostring(delay) .. ")")
    end)
end

local function OnEvent(event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == "TaskTracker" then
        -- Defer registration; do NOT call RegisterEvent in the load path.
        TryRegisterCoreEventsLater(1.0)

        -- Initialize database
        TaskTracker.InitDB()

        if TaskTracker.OnCharacterEnter then
            TaskTracker.OnCharacterEnter()
        end

        -- Check and apply resets (after per-character progress is loaded)
        TaskTracker.CheckResets()

        -- Build the UI
        TaskTracker.CreateMainPanel()

        -- Optional broker + minimap icon (LibDataBroker/LibDBIcon).
        if TaskTracker.InitBroker then
            TaskTracker.InitBroker()
        end

        -- Restore panel state (list refresh is scheduled from CreateMainPanel once in-world)
        if TaskTrackerDB.wasShown then
            TaskTracker.panel:Show()
            if TaskTrackerDB.minimized then
                TaskTracker.SetMinimized(true)
            end
        end

        -- Do not schedule SyncRegistryAndList from ADDON_LOADED: timers can fire while the loading bar
        -- is still active. All sync is scheduled from PLAYER_ENTERING_WORLD instead.

        print("|cff00ff00TaskTracker|r loaded! Type /tt to open.")

        -- Safety: ensure no fullscreen keybind-capture overlay is left open.
        if TaskTracker.HideKeybindCapture then
            TaskTracker.HideKeybindCapture()
        elseif _G.TaskTrackerKeybindCapture and _G.TaskTrackerKeybindCapture.Hide then
            _G.TaskTrackerKeybindCapture:Hide()
        end

        -- Safety: ensure no fullscreen quick-command dismiss layer is left open.
        if _G.TaskTrackerQuickCmdDismiss and _G.TaskTrackerQuickCmdDismiss.Hide then
            _G.TaskTrackerQuickCmdDismiss:Hide()
            if _G.TaskTrackerQuickCmdDismiss.EnableMouse then
                _G.TaskTrackerQuickCmdDismiss:EnableMouse(false)
            end
        end

        -- NOTE: Do not auto-mutate unrelated UI frames here. (Debug commands below can help identify blockers.)

        -- UPDATE_UI_WIDGET is extremely chatty; only listen when the registry reads widget progress.
        local anyWidget = false
        for _, reg in ipairs(TaskTracker.Registry or {}) do
            if reg.widgetId then
                anyWidget = true
                break
            end
        end
        if anyWidget then
            frame:RegisterEvent("UPDATE_UI_WIDGET")
        end

    elseif event == "ADDON_LOADED" and arg1 == "AllTheThings" then
        if TaskTracker.RequestReadyToBuyScan then
            TaskTracker.RequestReadyToBuyScan(true)
        end

    elseif event == "CHAT_MSG_ADDON" then
        if TaskTracker.OnLiveShareAddonMessage then
            local message, channel, sender = ...
            TaskTracker.OnLiveShareAddonMessage(arg1, message, channel, sender)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isReloadingUi = ...
        local firstPewThisSession = not frame._ttPewSeen
        frame._ttPewSeen = true
        -- Core event registration is deferred ~1s; the first PEW this frame sees is treated as
        -- login/reload even if isInitialLogin was already consumed.
        local isLoginOrReload = firstPewThisSession or (arg1 == true) or (isReloadingUi == true)
        CancelPewDeferredWork()
        TaskTracker._progressSyncGraceUntil = GetTime() + 4
        if firstPewThisSession then
            -- Keep the load lock until this re-apply; UIParent's size is real now.
            TaskTracker._ttPosSaveLocked = true
            if TaskTracker.ScheduleRestorePanelPosition then
                TaskTracker.ScheduleRestorePanelPosition()
            elseif TaskTracker.RestorePanelPosition then
                TaskTracker.RestorePanelPosition()
            end
            if TaskTracker.ScheduleRestoreOpenNotePeeks then
                TaskTracker.ScheduleRestoreOpenNotePeeks()
            elseif TaskTracker.RestoreOpenNotePeeks then
                C_Timer.After(0, TaskTracker.RestoreOpenNotePeeks)
            end
        end
        if TaskTracker.OnCharacterEnter then
            TaskTracker.OnCharacterEnter()
        end
        if TaskTracker.ScheduleLiveShareLogin then
            TaskTracker.ScheduleLiveShareLogin()
        elseif TaskTracker.RegisterLiveSharePrefix then
            TaskTracker.RegisterLiveSharePrefix()
        end
        if TaskTracker.InvalidateFishingMidnightLcaCache then
            TaskTracker.InvalidateFishingMidnightLcaCache()
        end
        if TaskTracker.InvalidateMobKillInstanceCache then
            TaskTracker.InvalidateMobKillInstanceCache()
        end
        if TaskTracker.RefreshCombatLogKillRegistration then
            TaskTracker.RefreshCombatLogKillRegistration()
        end
        if TaskTracker.SyncLearnedProfessionsOnEnterWorld then
            TaskTracker.SyncLearnedProfessionsOnEnterWorld()
        end
        if isLoginOrReload and TaskTracker.RequestReadyToBuyScan then
            AfterPew(2.0, function()
                TaskTracker.RequestReadyToBuyScan(true)
            end)
        end
        if isLoginOrReload and TaskTracker.RequestWorldQuestHuntScan then
            AfterPew(2.0, function()
                TaskTracker.RequestWorldQuestHuntScan(true)
            end)
        end
        -- Safety: ensure no fullscreen keybind-capture overlay is left open.
        if TaskTracker.HideKeybindCapture then
            TaskTracker.HideKeybindCapture()
        elseif _G.TaskTrackerKeybindCapture and _G.TaskTrackerKeybindCapture.Hide then
            _G.TaskTrackerKeybindCapture:Hide()
        end
        -- Safety: ensure no fullscreen quick-command dismiss layer is left open.
        if _G.TaskTrackerQuickCmdDismiss and _G.TaskTrackerQuickCmdDismiss.Hide then
            _G.TaskTrackerQuickCmdDismiss:Hide()
            if _G.TaskTrackerQuickCmdDismiss.EnableMouse then
                _G.TaskTrackerQuickCmdDismiss:EnableMouse(false)
            end
        end
        -- NOTE: Do not auto-mutate unrelated UI frames here. (Debug commands below can help identify blockers.)
        if TaskTracker.InitAdvancedMoneyBaseline then
            TaskTracker.InitAdvancedMoneyBaseline()
        end
        if isLoginOrReload then
            if TaskTracker.SyncAllAdvancedTasks then
                -- Same window as weekly rewards / achievements: not immediately on first PEW tick
                AfterPew(1.0, TaskTracker.SyncAllAdvancedTasks)
            end
            AfterPew(1.5, function()
                if TaskTracker.RequestRaidLockouts then
                    TaskTracker.RequestRaidLockouts()
                end
            end)
            ScheduleRegistrySync(1.0)
            ScheduleRegistrySync(2.5)
            ScheduleRegistrySync(5.0)

            -- Daily/weekly task resets (see Core/ResetSchedule.lua, Options → General).
            AfterPew(0.5, function()
                if TaskTracker.CheckResets then
                    TaskTracker.CheckResets()
                end
                if TaskTracker.MarkListDirtyFromProgressChange then
                    TaskTracker.MarkListDirtyFromProgressChange()
                end
                if TaskTracker.RefreshList then
                    TaskTracker.RefreshList()
                end
            end)
        else
            -- Zone / instance change: one debounced registry sync instead of the login triple.
            AfterPew(0.5, function()
                if TaskTracker.RequestRaidLockouts then
                    TaskTracker.RequestRaidLockouts()
                end
                SyncRegistryAndList("PLAYER_ENTERING_WORLD(zone)")
                if TaskTracker.RequestWorldQuestHuntScan then
                    TaskTracker.RequestWorldQuestHuntScan()
                end
            end)
        end

    elseif event == "PLAYER_LOGOUT" then
        if TaskTracker.OnCharacterLeave then
            TaskTracker.OnCharacterLeave()
        end
        if TaskTracker.RememberShownNotePeeks then
            TaskTracker.RememberShownNotePeeks()
        end
        if TaskTracker.SaveActiveProfile then
            TaskTracker.SaveActiveProfile()
        end
        local nw = TaskTracker.noteWindow
        if nw and nw.FlushNoteToNode then
            if nw._noteSaveDebounce then
                nw._noteSaveDebounce:Cancel()
                nw._noteSaveDebounce = nil
            end
            nw:FlushNoteToNode()
        end

    elseif event == "UPDATE_UI_WIDGET" then
        if frame._ttWidgetDebounce then
            frame._ttWidgetDebounce:Cancel()
        end
        frame._ttWidgetDebounce = C_Timer.NewTimer(0.35, function()
            frame._ttWidgetDebounce = nil
            SyncRegistryAndList("UPDATE_UI_WIDGET(debounced)")
        end)

    elseif event == "BAG_UPDATE" then
        if frame._ttBagDebounce then
            frame._ttBagDebounce:Cancel()
        end
        frame._ttBagDebounce = C_Timer.NewTimer(0.15, function()
            frame._ttBagDebounce = nil
            if TaskTracker.OnAdvancedBagUpdate then
                TaskTracker.OnAdvancedBagUpdate()
            end
            SyncRegistryAndList("BAG_UPDATE(debounced)")
        end)

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if frame._ttEquipDebounce then
            frame._ttEquipDebounce:Cancel()
        end
        frame._ttEquipDebounce = C_Timer.NewTimer(0.35, function()
            frame._ttEquipDebounce = nil
            if TaskTracker.InvalidateLowestEquippedItemLevel then
                TaskTracker.InvalidateLowestEquippedItemLevel()
            end
            if TaskTracker.MarkListLayoutDirty then
                TaskTracker.MarkListLayoutDirty()
            end
            if TaskTracker.RefreshList then
                TaskTracker.RefreshList()
            end
        end)

    elseif event == "PLAYER_LEVEL_UP" then
        if TaskTracker.MarkListLayoutDirty then
            TaskTracker.MarkListLayoutDirty()
        end
        if TaskTracker.RefreshList then
            TaskTracker.RefreshList()
        end

    elseif event == "UPDATE_INSTANCE_INFO" then
        if TaskTracker.InvalidateRaidLockoutCache then
            TaskTracker.InvalidateRaidLockoutCache()
        end
        ScheduleRegistrySync(0.1)

    elseif event == "WEEKLY_REWARDS_UPDATE" then
        if TaskTracker.InvalidateVaultIlvlCache then
            TaskTracker.InvalidateVaultIlvlCache()
        end
        if TaskTracker.CheckResets then
            TaskTracker.CheckResets()
        end
        if TaskTracker.MarkListDirtyFromProgressChange then
            TaskTracker.MarkListDirtyFromProgressChange()
        end
        if TaskTracker.RefreshList then
            TaskTracker.RefreshList()
        end

    elseif event == "QUEST_TURNED_IN" then
        local turnedIn = tonumber(arg1)
        TaskTracker.OnQuestTurnedIn(turnedIn)
        if TaskTracker.NoteAdvancedQuestTurnIn then
            TaskTracker.NoteAdvancedQuestTurnIn(turnedIn)
        end
        C_Timer.After(0.15, function()
            if TaskTracker.OnFactionReputationEvent then
                TaskTracker.OnFactionReputationEvent()
            end
            if TaskTracker.OnAchievementOrCriteriaEvent then
                TaskTracker.OnAchievementOrCriteriaEvent()
            end
            if TaskTracker.OnAdvancedQuestProgress then
                TaskTracker.OnAdvancedQuestProgress()
            end
        end)
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
        if frame._ttQuestDebounce then
            frame._ttQuestDebounce:Cancel()
        end
        frame._ttQuestDebounce = C_Timer.NewTimer(0.25, function()
            frame._ttQuestDebounce = nil
            if TaskTracker.OnAdvancedQuestProgress then
                TaskTracker.OnAdvancedQuestProgress()
            end
            SyncRegistryAndList("QUEST_UPDATE(debounced)")
        end)

    elseif event == "PLAYER_MONEY" then
        if TaskTracker.OnPlayerMoney then
            TaskTracker.OnPlayerMoney()
        end
        if TaskTracker.RequestCharWalletSnapshot then
            TaskTracker.RequestCharWalletSnapshot()
        end

    elseif event == "ACHIEVEMENT_EARNED" or event == "CRITERIA_UPDATE" then
        if TaskTracker.OnAchievementOrCriteriaEvent then
            TaskTracker.OnAchievementOrCriteriaEvent()
        end

    elseif event == "UPDATE_FACTION" then
        if TaskTracker.OnFactionReputationEvent then
            TaskTracker.OnFactionReputationEvent()
        end
        if TaskTracker.RequestCharWalletSnapshot then
            TaskTracker.RequestCharWalletSnapshot()
        end
        if TaskTracker.RequestReadyToBuyScan then
            TaskTracker.RequestReadyToBuyScan()
        end

    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        if frame._ttCurrencyDebounce then
            frame._ttCurrencyDebounce:Cancel()
        end
        frame._ttCurrencyDebounce = C_Timer.NewTimer(0.15, function()
            frame._ttCurrencyDebounce = nil
            if TaskTracker.OnAdvancedCurrencyUpdate then
                TaskTracker.OnAdvancedCurrencyUpdate()
            end
            if TaskTracker.RequestCharWalletSnapshot then
                TaskTracker.RequestCharWalletSnapshot()
            end
            if TaskTracker.OnAchievementOrCriteriaEvent then
                TaskTracker.OnAchievementOrCriteriaEvent()
            end
            if TaskTracker.RequestReadyToBuyScan then
                TaskTracker.RequestReadyToBuyScan()
            end
            SyncRegistryAndList("CURRENCY_DISPLAY_UPDATE(debounced)")
        end)

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Lowest-level debug: prove the event fires at all.
        if TaskTrackerDB and TaskTrackerDB.debugMobKill == true then
            frame._ttMobDbg = frame._ttMobDbg or { last = 0 }
            local now = GetTime and GetTime() or 0
            if (now - (frame._ttMobDbg.last or 0)) > 0.75 then
                frame._ttMobDbg.last = now
                local _, subEvent = CombatLogGetCurrentEventInfo()
                print("|cffffaa00TT Mob|r CL subEvent=" .. tostring(subEvent))
            end
        end
        if TaskTracker.OnAdvancedCombatLogEvent then
            TaskTracker.OnAdvancedCombatLogEvent()
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        if TaskTrackerDB and TaskTrackerDB.debugMobKill == true then
            print("|cffffaa00TT Mob|r ENTER COMBAT (PLAYER_REGEN_DISABLED)")
        end
        if TaskTracker.OnAdvancedRegenDisabled then
            TaskTracker.OnAdvancedRegenDisabled()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if TaskTracker.OnAdvancedRegenEnabled then
            TaskTracker.OnAdvancedRegenEnabled()
        end
        if TaskTracker.RefreshCombatLogKillRegistration then
            TaskTracker.RefreshCombatLogKillRegistration()
        end
        if TaskTracker._ttRaidInfoPending and TaskTracker.RequestRaidLockouts then
            TaskTracker.RequestRaidLockouts()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if TaskTracker.OnAdvancedTargetChanged then
            TaskTracker.OnAdvancedTargetChanged()
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if TaskTracker.OnAdvancedNameplateRemoved then
            TaskTracker.OnAdvancedNameplateRemoved(arg1)
        end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        if TaskTracker.OnAdvancedLootEvent then
            TaskTracker.OnAdvancedLootEvent(event)
        end
    elseif event == "ENCOUNTER_END" then
        if TaskTracker.OnAdvancedEncounterEnd then
            TaskTracker.OnAdvancedEncounterEnd(arg1, ...)
        end
        if TaskTracker.RequestRaidLockouts then
            C_Timer.After(1.5, TaskTracker.RequestRaidLockouts)
        end

    elseif event == "UNIT_SPELLCAST_SENT" then
        -- unit is arg1; ... is castGUID, spellID (do not unpack ... as unit, spellId — that mis-binds).
        if TaskTracker.ProcessPlayerFishingCast then
            TaskTracker.ProcessPlayerFishingCast(arg1, ...)
        end
    elseif event == "NEW_MOUNT_ADDED" or event == "NEW_PET_ADDED" or event == "NEW_TOY_ADDED"
        or event == "TOYS_UPDATED" or event == "COMPANION_LEARNED"
        or event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
        ScheduleRegistrySync(0.2)
        if TaskTracker.ClearCurrencySpendOwnedCache then
            TaskTracker.ClearCurrencySpendOwnedCache()
        end
        if event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" and TaskTracker.RequestCharWalletSnapshot then
            TaskTracker.RequestCharWalletSnapshot()
        end
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    -- Single dispatcher.
    OnEvent(event, ...)
end)

clFrame:SetScript("OnEvent", function(self, event, ...)
    -- Forward combat log to the same handler.
    OnEvent(event, ...)
end)

-- Bootstrap: try to register only ADDON_LOADED (if this is forbidden too, the UI is in a very bad state).
pcall(function()
    frame:RegisterEvent("ADDON_LOADED")
end)

-- Kick off event registration is done from ADDON_LOADED.

-- ─────────────────────────────────────
-- Debug helpers (also used by UI/DebugPanel.lua)
-- ─────────────────────────────────────

--- Same chat output as |cff00ff00/tt mobdebug status|r.
function TaskTracker.PrintMobDebugStatus()
    TaskTrackerDB = TaskTrackerDB or {}
    local st = frame and frame._ttEventReg or nil
    local reg = frame and frame._ttEventsRegistered == true
    local function isRegOn(f, ev)
        if not f or not f.IsEventRegistered then return "?" end
        local ok, v = pcall(function() return f:IsEventRegistered(ev) end)
        if not ok then return "?" end
        return v and "yes" or "no"
    end
    print("|cff00ff00TaskTracker|r Mob debug is " .. ((TaskTrackerDB.debugMobKill == true) and "ON" or "OFF"))
    if st then
        print("|cff00ff00TaskTracker|r Event registration: "
            .. (reg and "REGISTERED" or "NOT registered")
            .. " | attempts=" .. tostring(st.attempts or 0)
            .. " lastOk=" .. tostring(st.lastOk)
            .. " lastDelay=" .. tostring(st.lastDelay)
        )
    else
        print("|cff00ff00TaskTracker|r Event registration: " .. (reg and "REGISTERED" or "NOT registered") .. " (no attempts yet)")
    end
    local by = st and st.byEvent or nil
    local function byEv(ev)
        if not by then return "?" end
        if by[ev] == true then return "yes" end
        if by[ev] == false then return "no" end
        return "?"
    end
    print("|cff00ff00TaskTracker|r Registered? CLUE=" .. isRegOn(clFrame, "COMBAT_LOG_EVENT_UNFILTERED")
        .. " (wanted=" .. ((TaskTrackerDB and TaskTrackerDB.combatLogKillTracking == true) and "yes" or "no")
        .. (clFrame._ttForbidden and ", register-failed" or "") .. ")"
        .. " regenOff=" .. isRegOn(frame, "PLAYER_REGEN_DISABLED") .. " (attempt=" .. byEv("PLAYER_REGEN_DISABLED") .. ")"
        .. " regenOn=" .. isRegOn(frame, "PLAYER_REGEN_ENABLED") .. " (attempt=" .. byEv("PLAYER_REGEN_ENABLED") .. ")")
    print("|cff00ff00TaskTracker|r Combat log: off unless you enable it with /tt mobdebug cl (some UIs block COMBAT_LOG_EVENT_UNFILTERED). World-mode kills always have a nameplate fallback.")
end

function TaskTracker.PrintMobDebugCombatLogHelp()
    TaskTracker.ToggleCombatLogKillTracking()
end

function TaskTracker.RetryCoreEventRegistration()
    TryRegisterCoreEventsLater(0.25)
end

-- ─────────────────────────────────────
-- Slash commands
-- ─────────────────────────────────────
SLASH_TASKTRACKER1 = "/tt"
--- Called from Bindings.xml (key bind UI → Game Menu → Key Bindings → Other).
function TaskTracker.RunBindingToggle()
    if TaskTracker.TogglePanel then
        TaskTracker.TogglePanel()
    end
end

SlashCmdList["TASKTRACKER"] = function(msg)
    local cmd = msg and msg:lower():trim() or ""
    if cmd == "reset" or cmd == "resetdb" then
        print("|cff00ff00TaskTracker|r Resetting saved variables (TaskTrackerDB) and reloading UI…")
        TaskTrackerDB = nil
        if ReloadUI then
            ReloadUI()
        end
        return
    end
    if cmd == "resetpos" or cmd == "resetui" then
        if TaskTrackerDB then
            TaskTrackerDB.position = nil
            TaskTrackerDB.wasShown = false
            TaskTrackerDB.minimized = false
        end
        print("|cff00ff00TaskTracker|r Reset UI position/state and reloading…")
        if ReloadUI then
            ReloadUI()
        end
        return
    end
    if cmd == "minimap" or cmd == "mm" then
        if TaskTracker.ToggleMinimapIcon then
            TaskTracker.ToggleMinimapIcon()
        end
        return
    end
    if cmd == "options" or cmd == "opt" then
        local opts = TaskTracker.optionsPanel
        if opts then
            if opts:IsShown() then opts:Hide() else opts:Show() end
        end
        return
    end
    if cmd == "wqrep" or cmd:match("^wqrep%s") or cmd:match("^wqrep%d") then
        local questID = tonumber(msg:match("(%d+)"))
        if TaskTracker.DumpWorldQuestRewards then
            TaskTracker.DumpWorldQuestRewards(questID)
        end
        return
    end
    if cmd == "debug" then
        if TaskTracker.ToggleDebugPanel then
            TaskTracker.ToggleDebugPanel()
        end
        return
    end
    if cmd == "mobdebug status" or cmd == "mobdebugstatus" or cmd == "mobstatus" then
        TaskTracker.PrintMobDebugStatus()
        return
    end
    if cmd == "mobdebug cl" or cmd == "mobdebugcl" or cmd == "mobcl"
        or cmd == "mobdebug c1" or cmd == "mobdebugc1" or cmd == "mobc1"
        or cmd == "cl" or cmd == "c1" then
        TaskTracker.ToggleCombatLogKillTracking()
        return
    end
    if cmd == "mobdebug retry" or cmd == "mobdebugretry" or cmd == "mobretry" then
        TaskTracker.RetryCoreEventRegistration()
        print("|cff00ff00TaskTracker|r Retrying event registration…")
        return
    end
    if cmd == "fishdebug" then
        TaskTrackerDB = TaskTrackerDB or {}
        TaskTrackerDB.debugFishSpell = not (TaskTrackerDB.debugFishSpell == true)
        local sentReg = "?"
        if frame and frame.IsEventRegistered then
            local ok, v = pcall(function()
                return frame:IsEventRegistered("UNIT_SPELLCAST_SENT")
            end)
            if ok then
                sentReg = v and "yes" or "no"
            end
        end
        print("|cff00ff00TaskTracker|r Fishing spell debug: " .. (TaskTrackerDB.debugFishSpell and "ON" or "OFF")
            .. " | UNIT_SPELLCAST_SENT registered=" .. sentReg
            .. " — cast Fishing once; next SENT logs spellId, mapId, pool hint (even if spell is not whitelisted).")
        if TaskTracker.RefreshDebugPanelIfShown then
            TaskTracker.RefreshDebugPanelIfShown()
        end
        return
    end
    if cmd == "mobdebug" then
        TaskTrackerDB = TaskTrackerDB or {}
        TaskTrackerDB.debugMobKill = not (TaskTrackerDB.debugMobKill == true)
        print("|cff00ff00TaskTracker|r Mob kill debug: " .. (TaskTrackerDB.debugMobKill and "ON" or "OFF"))
        if TaskTracker.RefreshDebugPanelIfShown then
            TaskTracker.RefreshDebugPanelIfShown()
        end
        return
    end
    TaskTracker.TogglePanel()
end