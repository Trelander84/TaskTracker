-- Core/Profiles.lua
-- Named profiles. Each character picks one. The live TaskTrackerDB keys stay the
-- working copy of the loaded profile. A snapshot is written on switch, character
-- change, and logout. Progress stays outside the profile.

TaskTracker = TaskTracker or {}

local DEFAULT_NAME = "Default"
local PROFILE_MAGIC = "TASKTRACKER_PROFILE_V1:"
-- Not a name a player can type. Kept out of the profile list.
local FRESH_PROFILE_KEY = "New install\031"
local FRESH_PROFILE_LABEL = "New install"

-- New options belong in this list. Keys that are not listed stay on this
-- computer (window, minimap, debug) or on the character (progress, wallet).
local PROFILE_SETTING_KEYS = {
    "hideCompleted",
    "showEmptyGroups",
    "showRowTooltips",
    "showHelpTooltips",
    "showShortcutHints",
    "subtextInTooltip",
    "requireShiftRowAdjustClicks",
    "rowShortcuts",
    "editReorderMode",
    "patchListGroupMode",
    "patchListViewExpanded",
    "zoneListFilter",
    "zoneListFilterOn",
    "zoneFilterIncludeParent",
    "zoneFilterIncludeChild",
    "listHideCollections",
    "listHideCustom",
    "listHideModules",
    "enableNewModules",
    "knownModuleIds",
    "zoneHereColor",
    "zoneHereUnderline",
    "attDataEnabled",
    "notePanelSide",
    "alwaysShowNoteIcon",
    "notePeekBgOpacityPercent",
    "notePeekTextOpacityPercent",
    "notePeekCmdOpacityPercent",
    "notePeekHoverBgOpacityPercent",
    "notePeekHoverTextOpacityPercent",
    "notePeekHoverCmdOpacityPercent",
    "collectablesHideOwnedInPicker",
    "liveShareEnabled",
    "liveShareOwnerName",
    "liveShareSyncAllButton",
    "charTooltipAlwaysCurrencyTotal",
    "charTooltipAlwaysHighestRep",
    "resetSchedulePreset",
    "resetCustomDailyHour",
    "resetCustomDailyMinute",
    "resetCustomDailyTZ",
    "resetCustomWeeklyHour",
    "resetCustomWeeklyMinute",
    "resetCustomWeeklyWday",
    "resetCustomWeeklyTZ",
    "indentSize",
    "scrollGutter",
    "listPadLeft",
    "listPadRight",
    "listPadTop",
    "listPadBottom",
    "spacingGroupHeader",
    "spacingGroupSection",
    "spacingBetweenTasks",
    "extraHeaderHeight",
    "extraTaskHeight",
    "cmdIconPercent",
    "rowIconPercent",
    "checkboxPercent",
    "labelToIconGap",
    "headerTitleGap",
    "fontPercent",
    "headerFontSize",
    "taskFontSize",
    "titleFontSize",
    "titleIconSize",
    "layoutPreset",
    "layoutPresetDefRev",
    "layoutFont",
    "fontShadow",
    "layoutCustom",
    "headerHeight",
    "rowHeight",
    "titleHeight",
    "titleMargin",
    "accentBarWidth",
    "automationBarWidth",
    "borderWidth",
    "buttonHeight",
    "optionsFontSize",
    "optionsRowHeight",
    "optionsBorderWidth",
    "optionsTitleFontSize",
    "optionsTitleIconSize",
    "optionsTitleHeight",
    "optionsTitleMargin",
    "optionsPanelStyleMigrated",
    "checkGap",
    "taskLabelOverflow",
    "uiScalePercent",
    "theme",
    "colorThemeRenameVer",
    "iconSet",
    "customThemes",
    "customThemeSeq",
    "readyToBuyEnabled",
    "readyToBuyZoneOnly",
    "readyToBuySpendOrder",
    "readyToBuyCount",
    "readyToBuyExpansions",
    "readyToBuyPicks",
    "readyToBuyKinds",
    "readyToBuyIgnoredCurrencies",
    "worldQuestHuntEnabled",
    "worldQuestHuntGold",
    "worldQuestHuntMinGold",
    "worldQuestHuntCollectables",
    "worldQuestHuntCurrency",
    "worldQuestHuntCurrencyText",
    "worldQuestHuntReputation",
    "worldQuestHuntReputationText",
    "worldQuestHuntHideEmpty",
    "worldQuestHuntShowCompleted",
    "worldQuestHuntExpansions",
}

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

local function db()
    return TaskTrackerDB
end

local function copyPlain(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local c = {}
    seen[v] = c
    for k, val in pairs(v) do
        if type(k) == "string" and k:sub(1, 4) == "_tt" then
            -- runtime cache
        elseif type(val) == "function" then
            -- skip
        elseif type(val) == "table" then
            c[k] = copyPlain(val, seen)
        else
            c[k] = val
        end
    end
    return c
end

local function scrubCopiedTask(node)
    node.done = false
    node.taskCount = 0
    node.taskUserValue = nil
    node.doneOverride = nil
    if type(node.advanced) == "table" then
        for i = 1, #ADV_STATE_KEYS do
            node.advanced[ADV_STATE_KEYS[i]] = nil
        end
    end
    if type(node.subtext) == "table" then
        node.subtext.lifetimeKills = nil
        node.subtext.goldPeriodCopper = nil
        node.subtext.achievementWeekStart = nil
    end
end

local function copyTreeNode(node, seen)
    if type(node) ~= "table" then return nil end
    if node.generatedTask or node.generatedSection or node.readyToBuyVendor then
        return nil
    end
    seen = seen or {}
    if seen[node] then return seen[node] end
    local c = {}
    seen[node] = c
    for k, v in pairs(node) do
        if type(k) == "string" and k:sub(1, 4) == "_tt" then
            -- runtime cache
        elseif type(v) == "function" then
            -- skip
        elseif k == "children" and type(v) == "table" then
            local kids = {}
            for i = 1, #v do
                local cc = copyTreeNode(v[i], seen)
                if cc then
                    kids[#kids + 1] = cc
                end
            end
            c.children = kids
        elseif type(v) == "table" then
            c[k] = copyPlain(v, seen)
        else
            c[k] = v
        end
    end
    if c.type == "task" then
        scrubCopiedTask(c)
    end
    return c
end

local function walkNodes(node, fn)
    if type(node) ~= "table" then return end
    fn(node)
    local kids = node.children
    if type(kids) ~= "table" then return end
    for i = 1, #kids do
        walkNodes(kids[i], fn)
    end
end

local function isUserTask(node)
    return node.type == "task"
        and not node.collectionFarmId
        and not node.welcomeTask
        and not node.generatedTask
        and not node.registryEntryId
end

local function isUserGroup(node)
    return node.type == "group"
        and not node.moduleGroupKey
        and not node.welcomeGroup
        and not node.generatedSection
        and not node.isPatchListView
end

local function reidentifyUserNodes(tree)
    walkNodes(tree, function(node)
        if isUserTask(node) or isUserGroup(node) then
            node.id = TaskTracker.GenerateUUID and TaskTracker.GenerateUUID() or tostring(time() or 0)
        end
    end)
end

local function restampImportedOwners(tree, charKey)
    walkNodes(tree, function(node)
        if not isUserTask(node) then return end
        if node.accountWide == true then
            node.ownerCharKey = nil
            return
        end
        node.ownerCharKey = charKey
    end)
end

local function captureSettings(source)
    local s = {}
    for i = 1, #PROFILE_SETTING_KEYS do
        local k = PROFILE_SETTING_KEYS[i]
        local v = source[k]
        if type(v) == "table" then
            s[k] = copyPlain(v)
        else
            s[k] = v
        end
    end
    return s
end

local function applySettings(target, settings)
    settings = settings or {}
    for i = 1, #PROFILE_SETTING_KEYS do
        local k = PROFILE_SETTING_KEYS[i]
        local v = settings[k]
        if type(v) == "table" then
            target[k] = copyPlain(v)
        else
            target[k] = v
        end
    end
end

local function copyVisibility(bucket)
    local out = {}
    if type(bucket) ~= "table" then return out end
    for id, row in pairs(bucket) do
        if type(id) == "string" and type(row) == "table" then
            local c = {}
            if row.enabled == false then c.enabled = false end
            if row.powerListEnabled == false then c.powerListEnabled = false end
            if row.showCollected == true then c.showCollected = true end
            if next(c) then
                out[id] = c
            end
        end
    end
    return out
end

local function visibilitySignature(vis)
    local parts = {}
    for id, row in pairs(vis) do
        local bits = {}
        if row.enabled == false then bits[#bits + 1] = "e" end
        if row.powerListEnabled == false then bits[#bits + 1] = "p" end
        if row.showCollected == true then bits[#bits + 1] = "s" end
        if #bits > 0 then
            parts[#parts + 1] = id .. "=" .. table.concat(bits, "")
        end
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function visibilityFromRegistryState(state)
    local vis = {}
    if type(state) ~= "table" then return vis end
    for id, st in pairs(state) do
        if type(id) == "string" and type(st) == "table" then
            local row = {}
            if st.enabled == false then row.enabled = false end
            if st.powerListEnabled == false then row.powerListEnabled = false end
            if next(row) then
                vis[id] = row
            end
        end
    end
    return vis
end

local function starterVisibility()
    local vis = {}
    if not TaskTracker.IsStarterRegistryEntry or type(TaskTracker.Registry) ~= "table" then
        return vis
    end
    for i = 1, #TaskTracker.Registry do
        local entry = TaskTracker.Registry[i]
        if entry and entry.id then
            local row = {}
            if not TaskTracker.IsStarterRegistryEntry(entry) then
                row.enabled = false
            end
            row.powerListEnabled = false
            vis[entry.id] = row
        end
    end
    return vis
end

local function defaultSettings()
    return {
        hideCompleted = false,
        showEmptyGroups = "off",
        showRowTooltips = true,
        showHelpTooltips = true,
        showShortcutHints = true,
        subtextInTooltip = false,
        requireShiftRowAdjustClicks = true,
        editReorderMode = "pick",
        patchListGroupMode = "patch",
        patchListViewExpanded = {},
        zoneListFilter = "focus",
        zoneListFilterOn = false,
        zoneFilterIncludeParent = false,
        zoneFilterIncludeChild = false,
        listHideCollections = false,
        listHideCustom = false,
        listHideModules = false,
        enableNewModules = false,
        zoneHereColor = true,
        zoneHereUnderline = false,
        attDataEnabled = true,
        notePanelSide = "right",
        alwaysShowNoteIcon = false,
        notePeekBgOpacityPercent = 85,
        notePeekTextOpacityPercent = 100,
        notePeekCmdOpacityPercent = 100,
        notePeekHoverBgOpacityPercent = 85,
        notePeekHoverTextOpacityPercent = 100,
        notePeekHoverCmdOpacityPercent = 100,
        collectablesHideOwnedInPicker = true,
        liveShareEnabled = false,
        liveShareOwnerName = "task",
        liveShareSyncAllButton = false,
        charTooltipAlwaysCurrencyTotal = true,
        charTooltipAlwaysHighestRep = true,
        resetSchedulePreset = "server",
        resetCustomDailyHour = 8,
        resetCustomDailyMinute = 0,
        resetCustomDailyTZ = "Pacific",
        resetCustomWeeklyHour = 10,
        resetCustomWeeklyMinute = 0,
        resetCustomWeeklyWday = 3,
        resetCustomWeeklyTZ = "Eastern",
        indentSize = 4,
        scrollGutter = 3,
        listPadLeft = 0,
        listPadRight = 8,
        listPadTop = 0,
        listPadBottom = 0,
        spacingGroupHeader = 0,
        spacingGroupSection = 0,
        spacingBetweenTasks = 0,
        extraHeaderHeight = 0,
        extraTaskHeight = 0,
        layoutPreset = "compact",
        layoutPresetDefRev = 4,
        layoutFont = "friz",
        fontShadow = false,
        headerHeight = 16,
        rowHeight = 15,
        titleHeight = 20,
        titleMargin = 6,
        accentBarWidth = 2,
        automationBarWidth = 3,
        borderWidth = 1,
        buttonHeight = 18,
        checkGap = 4,
        cmdIconPercent = 60,
        rowIconPercent = 60,
        checkboxPercent = 70,
        labelToIconGap = 2,
        headerTitleGap = 4,
        headerFontSize = 11,
        taskFontSize = 10,
        titleFontSize = 14,
        titleIconSize = 16,
        fontPercent = 100,
        taskLabelOverflow = "ellipsis",
        uiScalePercent = 100,
        theme = "gilded",
        colorThemeRenameVer = 1,
        iconSet = "classic",
        customThemes = {},
        customThemeSeq = 0,
        readyToBuyEnabled = false,
        readyToBuyZoneOnly = false,
        readyToBuySpendOrder = "high",
        readyToBuyCount = 5,
        readyToBuyExpansions = { midnight = true },
        readyToBuyPicks = {},
        readyToBuyKinds = {},
        readyToBuyIgnoredCurrencies = {},
        worldQuestHuntEnabled = false,
        worldQuestHuntGold = true,
        worldQuestHuntMinGold = 500,
        worldQuestHuntCollectables = true,
        worldQuestHuntCurrency = false,
        worldQuestHuntCurrencyText = "",
        worldQuestHuntReputation = false,
        worldQuestHuntReputationText = "",
        worldQuestHuntHideEmpty = true,
        worldQuestHuntShowCompleted = false,
        worldQuestHuntExpansions = { midnight = true },
    }
end

local function cleanName(name)
    name = TaskTracker.Trim and TaskTracker.Trim(name or "") or tostring(name or "")
    name = name:gsub("%s+", " ")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if #name > 40 then
        name = name:sub(1, 40):gsub("%s+$", "")
    end
    if name == "" then return nil end
    return name
end

local profileBlobIsHidden

local function ensureStore()
    local d = db()
    if not d then return nil end
    if type(d.profiles) ~= "table" then d.profiles = {} end
    if type(d.profileOrder) ~= "table" then d.profileOrder = {} end
    if type(d.charProfile) ~= "table" then d.charProfile = {} end
    if type(d.accountTaskProgress) ~= "table" then d.accountTaskProgress = {} end
    if type(d.moduleVisibility) ~= "table" then d.moduleVisibility = {} end
    local seen = {}
    local order = {}
    local function remember(name)
        if type(name) ~= "string" or seen[name] or not d.profiles[name] then return end
        if profileBlobIsHidden(name) then return end
        seen[name] = true
        order[#order + 1] = name
    end
    for i = 1, #d.profileOrder do
        remember(d.profileOrder[i])
    end
    for name in pairs(d.profiles) do
        remember(name)
    end
    d.profileOrder = order
    return d
end

local function clampVer(ver, maxV)
    ver = tonumber(ver) or 0
    if ver < 0 then ver = 0 end
    maxV = maxV or 1
    if ver > maxV then ver = maxV end
    return ver
end

local function accountProgressRoot()
    local d = ensureStore()
    return d and d.accountTaskProgress
end

function profileBlobIsHidden(name)
    local d = db()
    local blob = d and type(name) == "string" and d.profiles and d.profiles[name]
    return type(blob) == "table" and blob.hidden == true
end

function TaskTracker.HiddenProfileIsLoaded()
    local d = db()
    return profileBlobIsHidden(d and d.loadedProfile)
end

function TaskTracker.IsHiddenProfile(name)
    return profileBlobIsHidden(name)
end

function TaskTracker.FreshInstallProfileLabel()
    return FRESH_PROFILE_LABEL
end

function TaskTracker.PersistAccountTaskProgress()
    if TaskTracker.HiddenProfileIsLoaded() then return end
    local store = accountProgressRoot()
    if not store or not TaskTracker.WalkTree or not TaskTracker.SnapshotTaskProgress then return end
    TaskTracker.WalkTree(function(node)
        if not TaskTracker.IsTaskAccountWide(node) or not node.id then return end
        local snap = TaskTracker.SnapshotTaskProgress(node)
        if type(node.subtext) == "table" and node.subtext.achievementWeekStart ~= nil then
            snap = snap or {}
            snap.achievementWeekStart = node.subtext.achievementWeekStart
        end
        if snap then
            store[node.id] = snap
        end
    end)
end

function TaskTracker.ApplyAccountTaskProgress()
    if TaskTracker.HiddenProfileIsLoaded() then return end
    local d = db()
    local store = d and d.accountTaskProgress
    if type(store) ~= "table" or not TaskTracker.WalkTree then return end
    TaskTracker.WalkTree(function(node)
        if not TaskTracker.IsTaskAccountWide(node) or not node.id then return end
        local snap = store[node.id]
        if type(snap) == "table" and TaskTracker.ApplyTaskProgressSnapshot then
            TaskTracker.ApplyTaskProgressSnapshot(node, snap)
            if snap.achievementWeekStart ~= nil and type(node.subtext) == "table" then
                node.subtext.achievementWeekStart = snap.achievementWeekStart
            end
        elseif TaskTracker.ClearTaskProgressOnNode then
            TaskTracker.ClearTaskProgressOnNode(node)
        end
    end)
end

local function captureProfileFromLive(source)
    local tree = copyTreeNode(source.tree)
    return {
        settings = captureSettings(source),
        moduleVisibility = copyVisibility(source.moduleVisibility),
        tree = tree,
        treeSchemaVer = source.treeSchemaVer,
        builtInNotesToTooltipVer = source.builtInNotesToTooltipVer,
    }
end

function TaskTracker.SaveActiveProfile()
    local d = ensureStore()
    if not d then return end
    local name = d.loadedProfile
    if type(name) ~= "string" or not d.profiles[name] then return end
    if TaskTracker.PersistAccountTaskProgress then
        TaskTracker.PersistAccountTaskProgress()
    end
    local prev = d.profiles[name]
    local blob = captureProfileFromLive(d)
    if type(prev) == "table" and prev.hidden then
        blob.hidden = true
    end
    d.profiles[name] = blob
end

local function refreshProfileUI()
    local d = db()
    if not d then return end
    if TaskTracker.LoadCustomThemes then
        TaskTracker.LoadCustomThemes()
    end
    if TaskTracker.InvalidateResetTimesCache then
        TaskTracker.InvalidateResetTimesCache()
    end
    if TaskTracker.RefreshCombatLogKillRegistration then
        TaskTracker.RefreshCombatLogKillRegistration()
    end
    -- The first character enter runs before the panel exists. Apply the theme
    -- so the panel that gets created next uses this profile. If the window is
    -- already open, rebuild it after this click finishes.
    if not TaskTracker.panel then
        if TaskTracker.ApplyTheme then
            TaskTracker.ApplyTheme()
        end
        return
    end
    local theme = d.theme or "gilded"
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not TaskTrackerDB then return end
            if TaskTracker.SetTheme then
                TaskTracker.SetTheme(theme)
            elseif TaskTracker.RefreshAll then
                TaskTracker.RefreshAll()
            elseif TaskTracker.RefreshList then
                TaskTracker.RefreshList()
            end
            if TaskTracker.RequestWorldQuestHuntScan then
                TaskTracker.RequestWorldQuestHuntScan()
            end
            if TaskTracker.RefreshReadyToBuyList then
                TaskTracker.RefreshReadyToBuyList()
            end
        end)
    elseif TaskTracker.SetTheme then
        TaskTracker.SetTheme(theme)
    end
end

local function loadProfile(name, opts)
    local d = ensureStore()
    if not d or not d.profiles[name] then return false, "That profile is missing." end
    opts = opts or {}
    local src = d.profiles[name]
    if TaskTracker.MigrateColorThemeKeys then
        TaskTracker.MigrateColorThemeKeys()
    end
    applySettings(d, src.settings)
    d.moduleVisibility = copyVisibility(src.moduleVisibility)
    d.tree = copyTreeNode(src.tree) or (TaskTracker.BuildDefaultTree and TaskTracker.BuildDefaultTree()) or { id = "root", type = "root", children = {} }
    if TaskTracker.InvalidateLiveShareIndex then
        TaskTracker.InvalidateLiveShareIndex()
    end
    d.treeSchemaVer = clampVer(src.treeSchemaVer, TaskTracker.TREE_SCHEMA_VER or 1)
    d.builtInNotesToTooltipVer = clampVer(src.builtInNotesToTooltipVer, TaskTracker.BUILT_IN_NOTES_TO_TOOLTIP_VER or 1)
    if TaskTracker.RepairLoadedTree then
        TaskTracker.RepairLoadedTree()
    end
    if TaskTracker.ApplyNewModuleDefaults then
        TaskTracker.ApplyNewModuleDefaults()
    end
    if opts.reidentify then
        reidentifyUserNodes(d.tree)
    end
    if opts.restampOwners then
        local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
        restampImportedOwners(d.tree, key)
    end
    d.loadedProfile = name
    if TaskTracker.ApplyAccountTaskProgress then
        TaskTracker.ApplyAccountTaskProgress()
    end
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if key and TaskTracker.LoadCharTaskProgress then
        TaskTracker.LoadCharTaskProgress(key)
    end
    if opts.reidentify or opts.restampOwners then
        TaskTracker.SaveActiveProfile()
    end
    if not opts.skipUi and TaskTracker.SyncAllAdvancedTasks then
        TaskTracker.SyncAllAdvancedTasks()
    end
    if not opts.skipUi and not profileBlobIsHidden(name) and TaskTracker.CheckResets then
        TaskTracker.CheckResets()
    end
    if TaskTracker.MigrateLayoutPreset then
        TaskTracker.MigrateLayoutPreset()
    end
    if TaskTracker.ApplyStoredLayoutPreset then
        TaskTracker.ApplyStoredLayoutPreset()
    end
    if TaskTracker.MigrateOptionsPanelStyle then
        TaskTracker.MigrateOptionsPanelStyle()
    end
    if not opts.skipUi then
        refreshProfileUI()
        local dlg = TaskTracker.taskDialog
        if dlg and dlg._syncEditDataIcon then
            dlg._syncEditDataIcon()
        end
    end
    return true
end

local function uniqueName(base, profiles)
    base = cleanName(base) or "Profile"
    if not profiles[base] then return base end
    local i = 2
    while profiles[base .. " " .. tostring(i)] do
        i = i + 1
        if i > 200 then break end
    end
    return base .. " " .. tostring(i)
end

local function eachKnownChar(d, fn)
    local seen = {}
    local function add(key)
        if type(key) ~= "string" or key == "" or key == "_pending" or seen[key] then return end
        seen[key] = true
        fn(key)
    end
    if type(d.charRegistryVisibility) == "table" then
        for key in pairs(d.charRegistryVisibility) do add(key) end
    end
    if type(d.charMeta) == "table" then
        for key in pairs(d.charMeta) do add(key) end
    end
    if type(d.charTaskProgress) == "table" then
        for key in pairs(d.charTaskProgress) do add(key) end
    end
end

function TaskTracker.MigrateProfiles()
    local d = ensureStore()
    if not d then return end
    if d.profileStoreVer == 1 and next(d.profiles) then
        return
    end
    if TaskTracker.PersistAccountTaskProgress then
        TaskTracker.PersistAccountTaskProgress()
    end

    local sigCounts = {}
    local sigVis = {}
    local sigChars = {}
    local anyChar = false
    eachKnownChar(d, function(key)
        anyChar = true
        local bucket = d.charRegistryVisibility and d.charRegistryVisibility[key]
        local vis = copyVisibility(bucket)
        local sig = visibilitySignature(vis)
        sigCounts[sig] = (sigCounts[sig] or 0) + 1
        sigVis[sig] = vis
        local list = sigChars[sig]
        if not list then
            list = {}
            sigChars[sig] = list
        end
        list[#list + 1] = key
    end)

    local defaultVis
    if not anyChar then
        defaultVis = visibilityFromRegistryState(d.registryState)
    else
        local bestSig, bestN
        for sig, n in pairs(sigCounts) do
            local take = false
            if not bestSig then
                take = true
            elseif n > bestN then
                take = true
            elseif n == bestN then
                if sig == "" and bestSig ~= "" then
                    take = true
                elseif bestSig ~= "" and sig ~= "" and sig < bestSig then
                    take = true
                end
            end
            if take then
                bestSig = sig
                bestN = n
            end
        end
        defaultVis = sigVis[bestSig] or {}
    end

    local base = captureProfileFromLive(d)
    base.moduleVisibility = copyVisibility(defaultVis)
    d.profiles = {}
    d.profileOrder = {}
    d.charProfile = {}
    d.profiles[DEFAULT_NAME] = base
    d.profileOrder[1] = DEFAULT_NAME

    if anyChar then
        local defaultSig = visibilitySignature(defaultVis)
        for sig, chars in pairs(sigChars) do
            local profileName = DEFAULT_NAME
            if sig ~= defaultSig then
                table.sort(chars)
                local label = chars[1]
                if TaskTracker.GetCharDisplayName then
                    label = TaskTracker.GetCharDisplayName(chars[1]) or label
                end
                profileName = uniqueName(label, d.profiles)
                local blob = captureProfileFromLive(d)
                blob.moduleVisibility = copyVisibility(sigVis[sig])
                d.profiles[profileName] = blob
                d.profileOrder[#d.profileOrder + 1] = profileName
            end
            for i = 1, #chars do
                d.charProfile[chars[i]] = profileName
            end
        end
    end

    d.moduleVisibility = copyVisibility(defaultVis)
    d.loadedProfile = DEFAULT_NAME
    d.profileStoreVer = 1
end

function TaskTracker.GetProfileNames()
    local d = ensureStore()
    if not d then return {} end
    local names = {}
    for i = 1, #d.profileOrder do
        names[i] = d.profileOrder[i]
    end
    return names
end

function TaskTracker.GetLoadedProfileName()
    local d = db()
    local name = d and d.loadedProfile
    if type(name) == "string" and d.profiles and d.profiles[name] then
        return name
    end
    return nil
end

function TaskTracker.ProfileNameForCharacter(charKey)
    local d = ensureStore()
    if not d then return nil end
    local name = charKey and d.charProfile[charKey]
    if type(name) == "string" and d.profiles[name] then
        return name
    end
    if d.profiles[DEFAULT_NAME] then return DEFAULT_NAME end
    return d.profileOrder[1]
end

local function assignCharacter(charKey, name)
    local d = ensureStore()
    if not d or not charKey or not d.profiles[name] then return end
    d.charProfile[charKey] = name
end

function TaskTracker.ActivateProfileForCharacter(charKey)
    local d = ensureStore()
    if not d or not charKey or not next(d.profiles) then return end
    local desired = TaskTracker.ProfileNameForCharacter(charKey)
    if not desired then return end
    assignCharacter(charKey, desired)
    local loaded = d.loadedProfile
    if type(loaded) ~= "string" or not d.profiles[loaded] then
        loadProfile(desired, { skipUi = not TaskTracker.panel })
        if not TaskTracker.panel then
            refreshProfileUI()
        end
        return
    end
    if loaded == desired then
        return
    end
    TaskTracker.SaveActiveProfile()
    loadProfile(desired, { skipUi = not TaskTracker.panel })
    if not TaskTracker.panel then
        refreshProfileUI()
    end
end

local function requireLiveProfile()
    local d = ensureStore()
    if not d then return nil, "Task Tracker is still loading." end
    if type(d.loadedProfile) ~= "string" or not d.profiles[d.loadedProfile] then
        return nil, "Log in on a character before changing profiles."
    end
    return d
end

function TaskTracker.SelectProfileForCurrentCharacter(name)
    name = cleanName(name)
    local d, err = requireLiveProfile()
    if not d then return false, err end
    if not name or not d.profiles[name] then return false, "That profile is missing." end
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if not key then return false, "Log in on a character before changing profiles." end
    assignCharacter(key, name)
    if d.loadedProfile == name then
        return true
    end
    TaskTracker.SaveActiveProfile()
    return loadProfile(name)
end

local function installFreshAs(name)
    local d = ensureStore()
    local settings = defaultSettings()
    local tree = TaskTracker.BuildDefaultTree and TaskTracker.BuildDefaultTree()
    applySettings(d, settings)
    d.moduleVisibility = starterVisibility()
    d.tree = tree or { id = "root", type = "root", children = {} }
    d.treeSchemaVer = 0
    d.builtInNotesToTooltipVer = 0
    if TaskTracker.RepairLoadedTree then
        TaskTracker.RepairLoadedTree()
    end
    if TaskTracker.ApplyNewModuleDefaults then
        TaskTracker.ApplyNewModuleDefaults()
    end
    d.profiles[name] = captureProfileFromLive(d)
    d.loadedProfile = name
    local listed = false
    for i = 1, #d.profileOrder do
        if d.profileOrder[i] == name then
            listed = true
            break
        end
    end
    if not listed then
        d.profileOrder[#d.profileOrder + 1] = name
    end
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if key then
        assignCharacter(key, name)
        if TaskTracker.LoadCharTaskProgress then
            TaskTracker.LoadCharTaskProgress(key)
        end
    end
    if TaskTracker.ApplyAccountTaskProgress then
        TaskTracker.ApplyAccountTaskProgress()
    end
    if TaskTracker.SyncAllAdvancedTasks then
        TaskTracker.SyncAllAdvancedTasks()
    end
    refreshProfileUI()
    return true
end

function TaskTracker.CreateProfile(name)
    name = cleanName(name)
    if not name then return false, "Enter a name." end
    local d, err = requireLiveProfile()
    if not d then return false, err end
    if d.profiles[name] then return false, "That name is already in use." end
    TaskTracker.SaveActiveProfile()
    return installFreshAs(name)
end

function TaskTracker.CopyLoadedProfile(name)
    name = cleanName(name)
    if not name then return false, "Enter a name." end
    local d, err = requireLiveProfile()
    if not d then return false, err end
    if d.profiles[name] then return false, "That name is already in use." end
    TaskTracker.SaveActiveProfile()
    local srcName = d.loadedProfile
    local blob = copyPlain(d.profiles[srcName])
    if type(blob) == "table" then
        blob.hidden = nil
    end
    d.profiles[name] = blob
    d.profileOrder[#d.profileOrder + 1] = name
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if key then
        assignCharacter(key, name)
    end
    return loadProfile(name, { reidentify = true })
end

function TaskTracker.RenameProfile(oldName, newName)
    oldName = cleanName(oldName)
    newName = cleanName(newName)
    if not newName then return false, "Enter a name." end
    local d, err = requireLiveProfile()
    if not d then return false, err end
    if not oldName or not d.profiles[oldName] then return false, "That profile is missing." end
    if profileBlobIsHidden(oldName) then return false, "Switch back before renaming that profile." end
    if newName == oldName then return true end
    if d.profiles[newName] then return false, "That name is already in use." end
    if d.loadedProfile == oldName then
        TaskTracker.SaveActiveProfile()
    end
    d.profiles[newName] = d.profiles[oldName]
    d.profiles[oldName] = nil
    for i = 1, #d.profileOrder do
        if d.profileOrder[i] == oldName then
            d.profileOrder[i] = newName
        end
    end
    for key, assigned in pairs(d.charProfile) do
        if assigned == oldName then
            d.charProfile[key] = newName
        end
    end
    if d.loadedProfile == oldName then
        d.loadedProfile = newName
    end
    return true
end

function TaskTracker.DeleteProfile(name)
    name = cleanName(name)
    local d, err = requireLiveProfile()
    if not d then return false, err end
    if not name or not d.profiles[name] then return false, "That profile is missing." end
    if profileBlobIsHidden(name) then return false, "Switch back before deleting that profile." end
    if #d.profileOrder <= 1 then return false, "That's the only profile." end
    local fallback
    for i = 1, #d.profileOrder do
        local candidate = d.profileOrder[i]
        if candidate ~= name and d.profiles[candidate] then
            if candidate == DEFAULT_NAME then
                fallback = candidate
                break
            end
            if not fallback then
                fallback = candidate
            end
        end
    end
    if not fallback then return false, "That's the only profile." end
    if d.loadedProfile == name then
        TaskTracker.SaveActiveProfile()
    end
    d.profiles[name] = nil
    local order = {}
    for i = 1, #d.profileOrder do
        if d.profileOrder[i] ~= name then
            order[#order + 1] = d.profileOrder[i]
        end
    end
    d.profileOrder = order
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    for charKey, assigned in pairs(d.charProfile) do
        if assigned == name then
            d.charProfile[charKey] = fallback
        end
    end
    if d.loadedProfile == name then
        if key then
            assignCharacter(key, fallback)
        end
        return loadProfile(fallback)
    end
    return true
end

function TaskTracker.ExportProfileByName(name)
    local d, err = requireLiveProfile()
    if not d then return nil, err end
    name = cleanName(name)
    if not name or not d.profiles[name] or profileBlobIsHidden(name) then
        return nil, "That profile is missing."
    end
    if name == d.loadedProfile then
        TaskTracker.SaveActiveProfile()
    end
    local src = d.profiles[name]
    if not src then return nil, "That profile is missing." end
    local payload = {
        v = 1,
        kind = "profile",
        name = name,
        settings = copyPlain(src.settings),
        moduleVisibility = copyVisibility(src.moduleVisibility),
        tree = copyTreeNode(src.tree),
        treeSchemaVer = src.treeSchemaVer,
        builtInNotesToTooltipVer = src.builtInNotesToTooltipVer,
    }
    if not TaskTracker.EncodeProfileExport then
        return nil, "Could not write that profile."
    end
    local text = TaskTracker.EncodeProfileExport(payload)
    if type(text) ~= "string" or text == "" then
        return nil, "Could not write that profile."
    end
    if #text > 120000 then
        return nil, "This profile is too large to copy."
    end
    return text
end

function TaskTracker.ExportLoadedProfile()
    local d, err = requireLiveProfile()
    if not d then return nil, err end
    return TaskTracker.ExportProfileByName(d.loadedProfile)
end

function TaskTracker.ImportProfileFromText(text, nameOverride)
    local d, err = requireLiveProfile()
    if not d then return false, err end
    if not TaskTracker.DecodeProfileExportString then
        return false, "Could not read that profile."
    end
    local payload, decodeErr = TaskTracker.DecodeProfileExportString(text)
    if not payload then
        return false, decodeErr or "Could not read that profile."
    end
    if payload.kind ~= "profile" or type(payload.settings) ~= "table" or type(payload.tree) ~= "table" then
        return false, "Could not read that profile."
    end
    local name = cleanName(nameOverride) or cleanName(payload.name) or "Imported"
    name = uniqueName(name, d.profiles)
    TaskTracker.SaveActiveProfile()
    d.profiles[name] = {
        settings = copyPlain(payload.settings),
        moduleVisibility = copyVisibility(payload.moduleVisibility),
        tree = copyTreeNode(payload.tree),
        treeSchemaVer = payload.treeSchemaVer,
        builtInNotesToTooltipVer = payload.builtInNotesToTooltipVer,
    }
    d.profileOrder[#d.profileOrder + 1] = name
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if key then
        assignCharacter(key, name)
    end
    return loadProfile(name, { reidentify = true, restampOwners = true })
end

function TaskTracker.IsProfileExportString(text)
    return type(text) == "string" and string.find(text, PROFILE_MAGIC, 1, true) ~= nil
end

local function firstListedProfile(d)
    for i = 1, #d.profileOrder do
        local name = d.profileOrder[i]
        if d.profiles[name] and not profileBlobIsHidden(name) then
            return name
        end
    end
    return nil
end

local function freshReturnMap(d)
    if type(d.debugFreshReturn) ~= "table" then
        d.debugFreshReturn = {}
    end
    return d.debugFreshReturn
end

local function freshInstallBlob()
    return {
        hidden = true,
        settings = defaultSettings(),
        moduleVisibility = starterVisibility(),
        tree = (TaskTracker.BuildDefaultTree and TaskTracker.BuildDefaultTree())
            or { id = "root", type = "root", children = {} },
        treeSchemaVer = 0,
        builtInNotesToTooltipVer = 0,
    }
end

function TaskTracker.FreshInstallReturnLabel()
    local d = db()
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    local map = d and d.debugFreshReturn
    if type(map) ~= "table" or not key then return nil end
    local name = map[key]
    if type(name) ~= "string" or not d.profiles or not d.profiles[name] or profileBlobIsHidden(name) then
        return nil
    end
    return name
end

function TaskTracker.ToggleFreshInstallProfile()
    local d, err = requireLiveProfile()
    if not d then
        print("|cff00ff00TaskTracker|r " .. (err or "Task Tracker is still loading."))
        return
    end
    local key = TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
    if not key then
        print("|cff00ff00TaskTracker|r Log in on a character first.")
        return
    end
    if profileBlobIsHidden(d.loadedProfile) then
        local back = freshReturnMap(d)[key]
        if type(back) ~= "string" or not d.profiles[back] or profileBlobIsHidden(back) then
            back = firstListedProfile(d)
        end
        if not back then
            print("|cff00ff00TaskTracker|r There is no profile to switch back to.")
            return
        end
        freshReturnMap(d)[key] = nil
        assignCharacter(key, back)
        local ok, loadErr = loadProfile(back)
        if not ok then
            print("|cff00ff00TaskTracker|r " .. (loadErr or "Could not switch back."))
            return
        end
        print("|cff00ff00TaskTracker|r Switched back to " .. back .. ".")
    else
        if not (TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady())
            or not TaskTracker.IsStarterRegistryEntry then
            print("|cff00ff00TaskTracker|r Quest catalog is not loaded yet. Try again after /reload.")
            return
        end
        TaskTracker.SaveActiveProfile()
        freshReturnMap(d)[key] = d.loadedProfile
        d.profiles[FRESH_PROFILE_KEY] = freshInstallBlob()
        assignCharacter(key, FRESH_PROFILE_KEY)
        local ok, loadErr = loadProfile(FRESH_PROFILE_KEY)
        if not ok then
            print("|cff00ff00TaskTracker|r " .. (loadErr or "Could not open the new install."))
            return
        end
        print("|cff00ff00TaskTracker|r This character is on a hidden new-install profile. /tt debug switches back.")
    end
    if TaskTracker.RefreshDebugPanelIfShown then
        TaskTracker.RefreshDebugPanelIfShown()
    end
    if TaskTracker.RefreshProfileMenuIfShown then
        TaskTracker.RefreshProfileMenuIfShown()
    end
end
