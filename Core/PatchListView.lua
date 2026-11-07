-- Core/PatchListView.lua
-- Display-time regroup of Midnight patch modules (saved tree stays mode A).
-- Modes: "patch" (A), "patch_zone" (B), "zone" (C).

TaskTracker = TaskTracker or {}

local VALID_MODES = { patch = true, patch_zone = true, zone = true }

local MODULE_KEY_ZONE = {
    patch_12_1_0_coiled_isle = "coiled_isle",
    patch_12_1_0_vaults      = "vaults",
}

local function patchRootKeys()
    return TaskTracker.MIDNIGHT_PATCH_ROOT_KEYS or {
        patch_12_1_5 = true,
        patch_12_1_0 = true,
        patch_12_0_5 = true,
        patch_12_0_0 = true,
    }
end

local function patchRootOrder()
    return TaskTracker.MIDNIGHT_PATCH_ROOT_ORDER or { "patch_12_1_5", "patch_12_1_0", "patch_12_0_5", "patch_12_0_0" }
end

local function zoneOrder()
    return TaskTracker.ListZoneOrder or { "midnight", "instanced", "coiled_isle", "vaults", "harandar", "quelthalas", "zulaman", "voidstorm" }
end

local function zoneLabel(zoneKey)
    local z = TaskTracker.ListZones and TaskTracker.ListZones[zoneKey]
    return (z and z.label) or zoneKey
end

local function categoryOrder()
    return TaskTracker.CollectionCategoryOrder or { "toys", "mounts", "pets", "currency", "reputations" }
end

local function categoryLabel(cat)
    local labels = TaskTracker.CollectionCategoryLabels
    return (labels and labels[cat]) or cat
end

local function patchLabel(patchKey)
    if patchKey == "patch_12_1_5" then return "Patch 12.1.5" end
    if patchKey == "patch_12_1_0" then return "Patch 12.1.0" end
    if patchKey == "patch_12_0_5" then return "Patch 12.0.5" end
    if patchKey == "patch_12_0_0" then return "Patch 12.0.0" end
    return patchKey
end

function TaskTracker.GetPatchListGroupMode()
    local db = TaskTrackerDB
    local m = db and db.patchListGroupMode
    if VALID_MODES[m] then return m end
    return "patch"
end

function TaskTracker.SetPatchListGroupMode(mode)
    if not VALID_MODES[mode] then return end
    local db = TaskTrackerDB
    if not db then return end
    if db.patchListGroupMode == mode then return end
    db.patchListGroupMode = mode
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
    if TaskTracker.RefreshOptionsModulesList then
        TaskTracker.RefreshOptionsModulesList()
    end
    if TaskTracker.SyncPatchListGroupModeButtons then
        TaskTracker.SyncPatchListGroupModeButtons()
    end
end

function TaskTracker.IsPatchListViewGroup(node)
    return node and node.type == "group" and (node.isPatchListView or node.viewGroupKey) and true or false
end

function TaskTracker.IsPatchListReorderLocked(node)
    if not node then return false end
    if node.liveShareRole == "receiver" or node.liveShareRole == "owner" then return false end
    if node.generatedSection or node.generatedTask then return true end
    if TaskTracker.IsPatchListViewGroup(node) then return true end
    if node.type == "registryEntry" then
        return TaskTracker.GetRegistryListZone(node.registryEntryId) ~= nil
    end
    if node.collectionFarmId then
        local entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[node.collectionFarmId]
        -- Profession rows stay movable. Collection farms stay locked to their group.
        if not (entry and entry.expansion == "professions") then
            return true
        end
    end
    local k = node.moduleGroupKey
    if type(k) == "string" and (k:find("patch_12_", 1, true) or k:find("collections", 1, true)) then
        return true
    end
    return false
end

function TaskTracker.SetGroupExpanded(node, expanded)
    if not node then return end
    local newExp = expanded and true or false
    node.expanded = newExp
    if node.backingNode then
        node.backingNode.expanded = newExp
    end
    if node.viewGroupKey and not node.backingNode then
        local db = TaskTrackerDB
        if db then
            if type(db.patchListViewExpanded) ~= "table" then
                db.patchListViewExpanded = {}
            end
            db.patchListViewExpanded[node.viewGroupKey] = newExp
        end
    end
end

function TaskTracker.ToggleGroupExpanded(node)
    if not node then return end
    TaskTracker.SetGroupExpanded(node, not node.expanded)
end

--- Walk the displayed list tree (virtual patch/zone groups included).
--- callback(groupNode, depth) — depth 0 is a top-level header (Midnight, Power, …).
local function walkListViewGroups(callback)
    local db = TaskTrackerDB
    if not db or not db.tree or not callback then return end
    local view = (TaskTracker.GetListViewRoot and TaskTracker.GetListViewRoot(db.tree)) or db.tree
    local function walk(node, depth)
        if not node then return end
        if node.type == "group" then
            callback(node, depth)
            if node.children then
                for i = 1, #node.children do
                    walk(node.children[i], depth + 1)
                end
            end
            return
        end
        local nextDepth = (node.type == "root") and 0 or depth
        if node.children then
            for i = 1, #node.children do
                walk(node.children[i], nextDepth)
            end
        end
    end
    walk(view, 0)
end

--- Deepest group that is expanded along a fully open ancestor path (−1 if everything is collapsed).
local function maxOpenGroupDepth()
    local maxD = -1
    local function walk(node, depth, ancestorsOpen)
        if not node then return end
        if node.type == "group" then
            if not ancestorsOpen then return end
            if node.expanded then
                if depth > maxD then maxD = depth end
                if node.children then
                    for i = 1, #node.children do
                        walk(node.children[i], depth + 1, true)
                    end
                end
            end
            return
        end
        local nextDepth = (node.type == "root") and 0 or depth
        if node.children then
            for i = 1, #node.children do
                walk(node.children[i], nextDepth, ancestorsOpen)
            end
        end
    end
    local db = TaskTrackerDB
    if not db or not db.tree then return -1 end
    local view = (TaskTracker.GetListViewRoot and TaskTracker.GetListViewRoot(db.tree)) or db.tree
    walk(view, 0, true)
    return maxD
end

--- action: "collapse_all" | "expand_all" | "collapse_one" | "expand_one"
--- Collapse/expand one level uses the furthest currently open nest: expand fills every
--- branch down to that depth + 1; collapse closes only the groups at that furthest depth.
function TaskTracker.ApplyListGroupExpand(action)
    if action == "collapse_all" then
        walkListViewGroups(function(node)
            TaskTracker.SetGroupExpanded(node, false)
        end)
    elseif action == "expand_all" then
        walkListViewGroups(function(node)
            TaskTracker.SetGroupExpanded(node, true)
        end)
    elseif action == "expand_one" then
        local target = maxOpenGroupDepth() + 1
        walkListViewGroups(function(node, depth)
            if depth <= target then
                TaskTracker.SetGroupExpanded(node, true)
            end
        end)
    elseif action == "collapse_one" then
        local maxD = maxOpenGroupDepth()
        if maxD < 0 then return end
        local db = TaskTrackerDB
        if not db or not db.tree then return end
        local view = (TaskTracker.GetListViewRoot and TaskTracker.GetListViewRoot(db.tree)) or db.tree
        local function walk(node, depth, ancestorsOpen)
            if not node then return end
            if node.type == "group" then
                if ancestorsOpen and depth == maxD then
                    TaskTracker.SetGroupExpanded(node, false)
                    return
                end
                local childOpen = ancestorsOpen and node.expanded
                if node.children then
                    for i = 1, #node.children do
                        walk(node.children[i], depth + 1, childOpen)
                    end
                end
                return
            end
            local nextDepth = (node.type == "root") and 0 or depth
            if node.children then
                for i = 1, #node.children do
                    walk(node.children[i], nextDepth, ancestorsOpen)
                end
            end
        end
        walk(view, 0, true)
    else
        return
    end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshListNow then
        TaskTracker.RefreshListNow()
    elseif TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

local function viewExpanded(viewGroupKey, backingNode)
    if backingNode then
        return backingNode.expanded ~= false
    end
    local db = TaskTrackerDB
    if db and type(db.patchListViewExpanded) == "table" and db.patchListViewExpanded[viewGroupKey] ~= nil then
        return db.patchListViewExpanded[viewGroupKey] and true or false
    end
    return true
end

local function NewViewGroup(viewGroupKey, name, children, opts)
    opts = opts or {}
    local backing = opts.backingNode
    return {
        id = backing and backing.id or ("view:" .. viewGroupKey),
        type = "group",
        name = name,
        expanded = viewExpanded(viewGroupKey, backing),
        children = children or {},
        viewGroupKey = viewGroupKey,
        backingNode = backing,
        moduleGroupKey = opts.moduleGroupKey,
        headerBgKey = opts.headerBgKey,
        listZone = opts.listZone,
        isPatchListView = true,
    }
end

local function findGroupByModuleKey(node, key, out)
    if not node then return end
    if node.type == "group" and node.moduleGroupKey == key then
        out[#out + 1] = node
    end
    if node.children then
        for i = 1, #node.children do
            findGroupByModuleKey(node.children[i], key, out)
        end
    end
end

local function firstGroupByKey(roots, key)
    local found = {}
    for i = 1, #(roots or {}) do
        findGroupByModuleKey(roots[i], key, found)
        if found[1] then return found[1] end
    end
    return nil
end

local function registryForNode(node)
    if not node or not TaskTracker.RegistryByID then return nil end
    if node.type == "registryEntry" then
        return TaskTracker.RegistryByID[node.registryEntryId]
    end
    if node.type == "task" and node.collectionFarmId then
        return TaskTracker.RegistryByID[node.collectionFarmId]
    end
    return nil
end

-- ─────────────────────────────────────
-- Current zone (title-bar menu + Options)
-- ─────────────────────────────────────

local MAP_ID_TO_ZONE

local function mapIdToZone()
    if MAP_ID_TO_ZONE then return MAP_ID_TO_ZONE end
    MAP_ID_TO_ZONE = {}
    local zones = TaskTracker.ListZones or {}
    for key, info in pairs(zones) do
        local ids = info and info.mapIds
        if type(ids) == "table" then
            for i = 1, #ids do
                local id = tonumber(ids[i])
                if id and id > 0 then
                    MAP_ID_TO_ZONE[id] = key
                end
            end
        end
    end
    return MAP_ID_TO_ZONE
end

local function mapIdPublic(id)
    if id == nil then return nil end
    if issecretvalue and issecretvalue(id) then return nil end
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    return id
end

local mapZoneCache = {}

--- ListZones key for a uiMap, walked up to a known map. Nil away from those zones.
function TaskTracker.ListZoneKeyForMapId(mapId)
    mapId = mapIdPublic(mapId)
    if not mapId then return nil end
    local cached = mapZoneCache[mapId]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local index = mapIdToZone()
    local start = mapId
    local guard = 0
    local zone
    while mapId and guard < 12 do
        zone = index[mapId]
        if zone then break end
        if not C_Map or not C_Map.GetMapInfo then break end
        local okInfo, info = pcall(C_Map.GetMapInfo, mapId)
        if not okInfo or type(info) ~= "table" then break end
        local parent = mapIdPublic(info.parentMapID)
        if not parent or parent == mapId then break end
        mapId = parent
        guard = guard + 1
    end
    mapZoneCache[start] = zone or false
    return zone
end

--- uiMap the player is standing on, walked up to a ListZones root. Nil away from those zones.
function TaskTracker.ResolvePlayerListZone()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local ok, mapId = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok then return nil end
    return TaskTracker.ListZoneKeyForMapId(mapId)
end

function TaskTracker.GetPlayerListZone()
    if not TaskTracker._playerListZoneDirty and TaskTracker._playerListZoneValue ~= nil then
        if TaskTracker._playerListZoneValue == false then return nil end
        return TaskTracker._playerListZoneValue
    end
    local zone = TaskTracker.ResolvePlayerListZone()
    TaskTracker._playerListZoneDirty = false
    TaskTracker._playerListZoneValue = zone or false
    return zone
end

function TaskTracker.GetPlayerListZoneLabel()
    local zone = TaskTracker.GetPlayerListZone()
    if not zone then return nil end
    return zoneLabel(zone)
end

function TaskTracker.NotePlayerListZoneChanged()
    local prev = TaskTracker._playerListZoneValue
    TaskTracker._playerListZoneDirty = true
    local now = TaskTracker.GetPlayerListZone()
    local nowKey = now or false
    if prev ~= nil and prev == nowKey then return end
    if TaskTracker.SyncCurrentZoneMenuRow then
        TaskTracker.SyncCurrentZoneMenuRow()
    end
    local panel = TaskTracker.panel
    if not panel or not panel.IsShown or not panel:IsShown() then return end
    if TaskTrackerDB and TaskTrackerDB.minimized then return end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

local zoneWatch = CreateFrame("Frame")
zoneWatch:RegisterEvent("ZONE_CHANGED")
zoneWatch:RegisterEvent("ZONE_CHANGED_INDOORS")
zoneWatch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneWatch:SetScript("OnEvent", function()
    if TaskTracker.NotePlayerListZoneChanged then
        TaskTracker.NotePlayerListZoneChanged()
    end
end)

function TaskTracker.GetZoneListFilterLabel()
    local m = TaskTracker.GetZoneListFilterMode()
    if m == "zone" then return "Zone Only" end
    if m == "zone_plus" then return "Zone + Global" end
    return "Focus"
end

function TaskTracker.ZoneHereUsesColor()
    return not (TaskTrackerDB and TaskTrackerDB.zoneHereColor == false)
end

function TaskTracker.ZoneHereUsesUnderline()
    return TaskTrackerDB and TaskTrackerDB.zoneHereUnderline == true
end

function TaskTracker.GetZoneListFilterMode()
    local db = TaskTrackerDB
    local m = db and db.zoneListFilter
    if m == "zone" or m == "zone_plus" or m == "focus" then return m end
    return "focus"
end

function TaskTracker.ZoneFilterIncludeParent()
    return TaskTrackerDB and TaskTrackerDB.zoneFilterIncludeParent == true
end

function TaskTracker.ZoneFilterIncludeChild()
    return TaskTrackerDB and TaskTrackerDB.zoneFilterIncludeChild == true
end

function TaskTracker.IsZoneListFilterActive()
    if TaskTracker.GetZoneListFilterMode() == "focus" then return false end
    return TaskTrackerDB and TaskTrackerDB.zoneListFilterOn == true
end

--- listZone stamped on a view group, a coiled/vaults module key, or the registry row.
function TaskTracker.NodeListZone(node)
    if not node then return nil end
    if type(node.listZone) == "string" and node.listZone ~= "" then
        return node.listZone
    end
    local key = node.moduleGroupKey
    if key and MODULE_KEY_ZONE[key] then
        return MODULE_KEY_ZONE[key]
    end
    local entry = registryForNode(node)
    if entry and type(entry.listZone) == "string" and entry.listZone ~= "" then
        return entry.listZone
    end
    return nil
end

function TaskTracker.IsHereZoneNode(node)
    local here = TaskTracker.GetPlayerListZone()
    if not here then return false end
    return TaskTracker.NodeListZone(node) == here
end

--- leafZone matches the zone the player is in, plus ancestors and/or descendants when those Options are on.
function TaskTracker.ListZoneMatchesPlayerFilter(leafZone)
    local player = TaskTracker.GetPlayerListZone()
    if not player or not leafZone then return false end
    if leafZone == player then return true end
    if TaskTracker.ZoneFilterIncludeParent()
        and TaskTracker.IsListZoneUnder
        and TaskTracker.IsListZoneUnder(player, leafZone) then
        return true
    end
    if TaskTracker.ZoneFilterIncludeChild()
        and TaskTracker.IsListZoneUnder
        and TaskTracker.IsListZoneUnder(leafZone, player) then
        return true
    end
    return false
end

local function refreshAfterZoneFilter()
    if TaskTracker.SyncCurrentZoneMenuRow then
        TaskTracker.SyncCurrentZoneMenuRow()
    end
    if TaskTracker.SyncZoneListFilterButtons then
        TaskTracker.SyncZoneListFilterButtons()
    end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshListNow then
        TaskTracker.RefreshListNow()
    elseif TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

function TaskTracker.SetZoneListFilterMode(mode)
    if mode ~= "focus" and mode ~= "zone" and mode ~= "zone_plus" then return end
    local db = TaskTrackerDB
    if not db then return end
    local changed = db.zoneListFilter ~= mode or db.zoneListFilterOn
    db.zoneListFilter = mode
    db.zoneListFilterOn = false
    if changed then
        refreshAfterZoneFilter()
    else
        if TaskTracker.SyncZoneListFilterButtons then
            TaskTracker.SyncZoneListFilterButtons()
        end
    end
end

function TaskTracker.SetZoneFilterIncludeParent(on)
    local db = TaskTrackerDB
    if not db then return end
    local nextOn = on and true or false
    if db.zoneFilterIncludeParent == nextOn then return end
    db.zoneFilterIncludeParent = nextOn
    if TaskTracker.IsZoneListFilterActive() then
        refreshAfterZoneFilter()
    elseif TaskTracker.SyncZoneListFilterButtons then
        TaskTracker.SyncZoneListFilterButtons()
    end
end

function TaskTracker.SetZoneFilterIncludeChild(on)
    local db = TaskTrackerDB
    if not db then return end
    local nextOn = on and true or false
    if db.zoneFilterIncludeChild == nextOn then return end
    db.zoneFilterIncludeChild = nextOn
    if TaskTracker.IsZoneListFilterActive() then
        refreshAfterZoneFilter()
    elseif TaskTracker.SyncZoneListFilterButtons then
        TaskTracker.SyncZoneListFilterButtons()
    end
end

function TaskTracker.IsHiddenByZoneFilter(node)
    local show = TaskTracker._zoneFilterShow
    if not show or not node then return false end
    return not show[node]
end

local function listKindIsCollectionsGroup(node)
    if not node or node.type ~= "group" then return false end
    local k = node.moduleGroupKey
    if type(k) == "string" and k:find("collections", 1, true) then return true end
    if node.name == "Collections" and node.isPatchListView then return true end
    return false
end

local function listKindIsCustomGroup(node)
    return node
        and node.type == "group"
        and not node.moduleGroupKey
        and not node.welcomeGroup
        and not node.generatedSection
        and not node.isPatchListView
        and not node.readyToBuyVendor
end

local function listKindIsCustomTask(node)
    return node
        and node.type == "task"
        and not node.collectionFarmId
        and not node.welcomeTask
        and not node.generatedTask
        and not node.registryEntryId
end

local function listKindRegistryEntry(node)
    if not node or not TaskTracker.RegistryByID then return nil end
    if node.type == "registryEntry" then
        return TaskTracker.RegistryByID[node.registryEntryId]
    end
    if node.type == "task" and node.collectionFarmId then
        return TaskTracker.RegistryByID[node.collectionFarmId]
    end
end

local function listKindIsCollectionsLeaf(node)
    local entry = listKindRegistryEntry(node)
    if not entry or not TaskTracker.IsCollectionsModuleEntry then return false end
    return TaskTracker.IsCollectionsModuleEntry(entry) == true
end

local function listKindIsModuleLeaf(node)
    if not node or node.generatedTask or node.welcomeTask then return false end
    if node.type == "registryEntry" then
        return not listKindIsCollectionsLeaf(node)
    end
    if node.type == "task" and node.collectionFarmId then
        return not listKindIsCollectionsLeaf(node)
    end
    return false
end

function TaskTracker.ListKindFilterHidden(kind)
    local db = TaskTrackerDB
    if not db then return false end
    if kind == "collections" then return db.listHideCollections == true end
    if kind == "custom" then return db.listHideCustom == true end
    if kind == "modules" then return db.listHideModules == true end
    return false
end

function TaskTracker.IsHiddenByListKindFilter(node)
    local hide = TaskTracker._listKindHide
    if not hide or not node then return false end
    return hide[node] == true
end

--- One pass over the list view. Nil when every set is shown, so the list walk stays a flag check.
function TaskTracker.BuildListKindFilter(root)
    local db = TaskTrackerDB
    local hideCollections = db and db.listHideCollections == true
    local hideCustom = db and db.listHideCustom == true
    local hideModules = db and db.listHideModules == true
    if not hideCollections and not hideCustom and not hideModules then
        TaskTracker._listKindHide = nil
        return
    end
    local hide = {}
    TaskTracker._listKindHide = hide
    local function walk(node)
        if not node then return false end
        if listKindIsCollectionsGroup(node) then
            if hideCollections then
                hide[node] = true
                return false
            end
            return true
        end
        if listKindIsCustomGroup(node) then
            if hideCustom then
                hide[node] = true
                return false
            end
            return true
        end
        if node.type == "group" or node.type == "root" then
            local any = false
            local kids = node.children
            if kids then
                for i = 1, #kids do
                    if walk(kids[i]) then
                        any = true
                    end
                end
            end
            if node.type == "group" and not any then
                hide[node] = true
                return false
            end
            return any
        end
        if listKindIsCollectionsLeaf(node) then
            if hideCollections then
                hide[node] = true
                return false
            end
            return true
        end
        if listKindIsCustomTask(node) then
            if hideCustom then
                hide[node] = true
                return false
            end
            return true
        end
        if listKindIsModuleLeaf(node) then
            if hideModules then
                hide[node] = true
                return false
            end
            return true
        end
        return true
    end
    walk(root)
end

function TaskTracker.ToggleListKindFilter(kind)
    local db = TaskTrackerDB
    if not db then return end
    if kind == "collections" then
        db.listHideCollections = not (db.listHideCollections == true)
    elseif kind == "custom" then
        db.listHideCustom = not (db.listHideCustom == true)
    elseif kind == "modules" then
        db.listHideModules = not (db.listHideModules == true)
    else
        return
    end
    if TaskTracker.SyncListKindMenuRows then
        TaskTracker.SyncListKindMenuRows()
    end
    refreshAfterZoneFilter()
end

function TaskTracker.BuildZoneFilterVisibility(root)
    if not TaskTracker.IsZoneListFilterActive() then
        TaskTracker._zoneFilterShow = nil
        return
    end
    local show = {}
    TaskTracker._zoneFilterShow = show
    local plus = TaskTracker.GetZoneListFilterMode() == "zone_plus"
    local function leafShown(node, underPower)
        if node.type == "task" then
            if TaskTracker.IsCollectionFarmTaskListed and not TaskTracker.IsCollectionFarmTaskListed(node) then
                return false
            end
            if TaskTracker.IsTaskVisibleForCurrentChar and not TaskTracker.IsTaskVisibleForCurrentChar(node) then
                return false
            end
        elseif node.type == "registryEntry" then
            if TaskTracker.IsRegistryRowTrackedForList
                and not TaskTracker.IsRegistryRowTrackedForList(node.registryEntryId, underPower) then
                return false
            end
        else
            return false
        end
        -- Ready to Buy rows carry listZone for the Current zone tint. The filter still treats them as unzoned.
        if node.generatedTask then
            return plus
        end
        local zone = TaskTracker.NodeListZone(node)
        if not zone then
            return plus
        end
        return TaskTracker.ListZoneMatchesPlayerFilter(zone)
    end
    local function walk(node, underPower)
        if not node then return false end
        underPower = underPower or false
        if node.type == "group" or node.type == "root" then
            local nextUnder = underPower or node.moduleGroupKey == "power"
            local any = false
            if node.children then
                for i = 1, #node.children do
                    if walk(node.children[i], nextUnder) then
                        any = true
                    end
                end
            end
            if any then
                show[node] = true
            end
            return any
        end
        if leafShown(node, underPower) then
            show[node] = true
            return true
        end
        return false
    end
    walk(root, false)
end

local function subtreeHasExactZone(node, zone)
    if not node or not zone then return false end
    if node.type == "task" or node.type == "registryEntry" then
        return TaskTracker.NodeListZone(node) == zone
    end
    if TaskTracker.NodeListZone(node) == zone then return true end
    if node.children then
        for i = 1, #node.children do
            if subtreeHasExactZone(node.children[i], zone) then return true end
        end
    end
    return false
end

--- Collapse every group, then open the path to the zone you are in.
--- Child zone headers open only when Include subzone is on.
local function focusExpandWalk(node, zone, insideTarget)
    if not node then return end
    if node.generatedSection then return end
    if node.type ~= "group" and node.type ~= "root" then return end
    local z = TaskTracker.NodeListZone(node)
    local isTarget = z == zone
    if node.type == "group" then
        if insideTarget and not isTarget then
            local openChild = TaskTracker.ZoneFilterIncludeChild()
                and z and z ~= zone
                and TaskTracker.IsListZoneUnder
                and TaskTracker.IsListZoneUnder(z, zone)
            TaskTracker.SetGroupExpanded(node, openChild and true or false)
            if openChild and node.children then
                for i = 1, #node.children do
                    focusExpandWalk(node.children[i], zone, true)
                end
            end
            return
        end
        if isTarget or subtreeHasExactZone(node, zone) then
            TaskTracker.SetGroupExpanded(node, true)
            local childInside = insideTarget or isTarget
            if node.children then
                for i = 1, #node.children do
                    focusExpandWalk(node.children[i], zone, childInside)
                end
            end
        else
            TaskTracker.SetGroupExpanded(node, false)
        end
        return
    end
    if node.children then
        for i = 1, #node.children do
            focusExpandWalk(node.children[i], zone, false)
        end
    end
end

function TaskTracker.FocusCurrentListZone()
    local zone = TaskTracker.GetPlayerListZone()
    if not zone then
        print("|cff00ff00TaskTracker|r No tasks for this zone.")
        return
    end
    local db = TaskTrackerDB
    if not db or not db.tree then return end
    local view = (TaskTracker.GetListViewRoot and TaskTracker.GetListViewRoot(db.tree)) or db.tree
    local function collapseView(node)
        if not node then return end
        if node.type == "group" then
            TaskTracker.SetGroupExpanded(node, false)
        end
        if node.children then
            for i = 1, #node.children do
                collapseView(node.children[i])
            end
        end
    end
    collapseView(view)
    focusExpandWalk(view, zone, false)
    refreshAfterZoneFilter()
end

function TaskTracker.ApplyCurrentZoneMenu()
    local mode = TaskTracker.GetZoneListFilterMode()
    if mode == "focus" then
        TaskTracker.FocusCurrentListZone()
        return
    end
    local zone = TaskTracker.GetPlayerListZone()
    if not zone then
        print("|cff00ff00TaskTracker|r No tasks for this zone.")
        return
    end
    local db = TaskTrackerDB
    if not db then return end
    db.zoneListFilterOn = not db.zoneListFilterOn
    refreshAfterZoneFilter()
end

local function walkGather(node, zoneHint, patchHint, leaves, leftoverGroups)
    if not node then return end
    if node.type == "group" then
        local key = node.moduleGroupKey
        local nextZone, nextPatch = zoneHint, patchHint
        if key and patchRootKeys()[key] then
            nextPatch = key
        end
        if key and MODULE_KEY_ZONE[key] then
            nextZone = MODULE_KEY_ZONE[key]
        end
        -- Player-made group under a patch: keep intact rather than flattening.
        if not key and nextPatch then
            leftoverGroups[#leftoverGroups + 1] = { patch = nextPatch, node = node }
            return
        end
        if node.children then
            for i = 1, #node.children do
                walkGather(node.children[i], nextZone, nextPatch, leaves, leftoverGroups)
            end
        end
        return
    end
    if node.type ~= "task" and node.type ~= "registryEntry" then return end
    local entry = registryForNode(node)
    local zone = (entry and entry.listZone) or zoneHint or "midnight"
    local patch = patchHint
    if entry and TaskTracker.GetMidnightPatchKeyFromSubsection then
        patch = TaskTracker.GetMidnightPatchKeyFromSubsection(entry.subsection) or patch
    end
    local collCat
    if entry and TaskTracker.GetCollectionCategoryKey then
        collCat = TaskTracker.GetCollectionCategoryKey(entry.subsection)
    end
    leaves[#leaves + 1] = {
        node = node,
        zone = zone,
        patch = patch,
        collCat = collCat,
    }
end

local function gatherFromPatch(patchNode)
    local leaves, leftoverGroups = {}, {}
    if not patchNode then return leaves, leftoverGroups end
    local patchKey = patchNode.moduleGroupKey
    walkGather(patchNode, nil, patchKey, leaves, leftoverGroups)
    return leaves, leftoverGroups
end

local function buildCollectionsGroup(viewPrefix, collByCat)
    local cats = {}
    local order = categoryOrder()
    for i = 1, #order do
        local cat = order[i]
        local list = collByCat[cat]
        if list and #list > 0 then
            local subKey = TaskTracker.MIDNIGHT_COLLECTION_SUBSECTIONS
                and TaskTracker.MIDNIGHT_COLLECTION_SUBSECTIONS[cat]
            cats[#cats + 1] = NewViewGroup(
                viewPrefix .. ":" .. cat,
                categoryLabel(cat),
                list,
                {
                    moduleGroupKey = subKey,
                    headerBgKey = "headerBg3",
                }
            )
        end
    end
    if #cats == 0 then return nil end
    return NewViewGroup(viewPrefix, "Collections", cats, {
        moduleGroupKey = "patch_12_1_0_collections",
        headerBgKey = "headerBg3",
    })
end

local function buildZoneGroup(viewKey, zoneKey, activities, collByCat, backingRoots, nestedZoneGroups)
    local children = {}
    for i = 1, #(activities or {}) do
        children[#children + 1] = activities[i]
    end
    local coll = buildCollectionsGroup(viewKey .. ":coll", collByCat)
    if coll then
        children[#children + 1] = coll
    end
    for i = 1, #(nestedZoneGroups or {}) do
        children[#children + 1] = nestedZoneGroups[i]
    end
    if #children == 0 then return nil end
    local zoneModKey
    if zoneKey == "coiled_isle" then
        zoneModKey = "patch_12_1_0_coiled_isle"
    elseif zoneKey == "vaults" then
        zoneModKey = "patch_12_1_0_vaults"
    end
    local backing = zoneModKey and firstGroupByKey(backingRoots, zoneModKey) or nil
    return NewViewGroup(viewKey, zoneLabel(zoneKey), children, {
        backingNode = backing,
        moduleGroupKey = zoneModKey,
        listZone = zoneKey,
    })
end

local function splitLeavesByZone(leaves)
    local byZone = {}
    for i = 1, #leaves do
        local L = leaves[i]
        local z = L.zone or "midnight"
        local bucket = byZone[z]
        if not bucket then
            bucket = { activities = {}, coll = {} }
            byZone[z] = bucket
        end
        if L.collCat then
            local catList = bucket.coll[L.collCat]
            if not catList then
                catList = {}
                bucket.coll[L.collCat] = catList
            end
            catList[#catList + 1] = L.node
        else
            bucket.activities[#bucket.activities + 1] = L.node
        end
    end
    return byZone
end

local function childZoneKeys(parentKey)
    if TaskTracker.GetListZoneChildKeys then
        return TaskTracker.GetListZoneChildKeys(parentKey)
    end
    return {}
end

local function zoneBucketHasContent(z, byZone)
    local bucket = byZone[z]
    if bucket then
        if #(bucket.activities or {}) > 0 then return true end
        for _, list in pairs(bucket.coll or {}) do
            if list and #list > 0 then return true end
        end
    end
    local kids = childZoneKeys(z)
    for i = 1, #kids do
        if zoneBucketHasContent(kids[i], byZone) then return true end
    end
    return false
end

local function buildZoneTree(z, viewPrefix, byZone, backingRoots)
    local bucket = byZone[z] or { activities = {}, coll = {} }
    local nested = {}
    local kids = childZoneKeys(z)
    for i = 1, #kids do
        if zoneBucketHasContent(kids[i], byZone) then
            local g = buildZoneTree(kids[i], viewPrefix, byZone, backingRoots)
            if g then nested[#nested + 1] = g end
        end
    end
    return buildZoneGroup(viewPrefix .. ":" .. z, z, bucket.activities, bucket.coll, backingRoots, nested)
end

local function zoneGroupsFromLeaves(leaves, viewPrefix, backingRoots)
    local byZone = splitLeavesByZone(leaves)
    local groups = {}
    local order = zoneOrder()
    for i = 1, #order do
        local z = order[i]
        local parent = TaskTracker.GetListZoneParent and TaskTracker.GetListZoneParent(z)
        if not parent and zoneBucketHasContent(z, byZone) then
            local g = buildZoneTree(z, viewPrefix, byZone, backingRoots)
            if g then
                groups[#groups + 1] = g
            end
        end
    end
    return groups
end

local function leftoversForPatch(leftoverGroups, patchKey)
    local out = {}
    for i = 1, #leftoverGroups do
        local L = leftoverGroups[i]
        if L.patch == patchKey then
            out[#out + 1] = L.node
        end
    end
    return out
end

local function midnightExpansionName()
    return (TaskTracker.ExpansionLabels and TaskTracker.ExpansionLabels.midnight) or "Midnight"
end

local function wrapInMidnightExpansion(children)
    if type(children) ~= "table" or #children == 0 then return {} end
    return {
        NewViewGroup("exp:midnight", midnightExpansionName(), children, {}),
    }
end

function TaskTracker.BuildPatchListViewChildren(rootChildren, mode)
    if type(rootChildren) ~= "table" then return rootChildren end
    mode = mode or TaskTracker.GetPatchListGroupMode()

    local keys = patchRootKeys()
    local byKey = {}
    local firstPatchIndex
    for i = 1, #rootChildren do
        local ch = rootChildren[i]
        local k = ch and ch.moduleGroupKey
        if k and keys[k] then
            byKey[k] = ch
            if not firstPatchIndex then firstPatchIndex = i end
        end
    end
    if not firstPatchIndex then
        return rootChildren
    end

    local order = patchRootOrder()
    local allLeaves, allLeftovers = {}, {}
    if mode ~= "patch" then
        for i = 1, #order do
            local pnode = byKey[order[i]]
            if pnode then
                local leaves, leftovers = gatherFromPatch(pnode)
                for j = 1, #leaves do
                    allLeaves[#allLeaves + 1] = leaves[j]
                end
                for j = 1, #leftovers do
                    allLeftovers[#allLeftovers + 1] = leftovers[j]
                end
            end
        end
    end

    local injected
    if mode == "patch" then
        injected = {}
        for i = 1, #order do
            local pnode = byKey[order[i]]
            if pnode then
                injected[#injected + 1] = pnode
            end
        end
        injected = wrapInMidnightExpansion(injected)
    elseif mode == "zone" then
        local zones = zoneGroupsFromLeaves(allLeaves, "zone", rootChildren)
        for i = 1, #allLeftovers do
            zones[#zones + 1] = allLeftovers[i].node
        end
        injected = wrapInMidnightExpansion(zones)
    else
        injected = {}
        for i = 1, #order do
            local patchKey = order[i]
            local pnode = byKey[patchKey]
            if pnode then
                local patchLeaves = {}
                for j = 1, #allLeaves do
                    if allLeaves[j].patch == patchKey then
                        patchLeaves[#patchLeaves + 1] = allLeaves[j]
                    end
                end
                local zones = zoneGroupsFromLeaves(patchLeaves, "patch:" .. patchKey, { pnode })
                local left = leftoversForPatch(allLeftovers, patchKey)
                for j = 1, #left do
                    zones[#zones + 1] = left[j]
                end
                if #zones > 0 then
                    injected[#injected + 1] = NewViewGroup("patch:" .. patchKey, pnode.name or patchLabel(patchKey), zones, {
                        backingNode = pnode,
                        moduleGroupKey = patchKey,
                    })
                end
            end
        end
        injected = wrapInMidnightExpansion(injected)
    end

    local out, skipped = {}, {}
    for i = 1, #rootChildren do
        local ch = rootChildren[i]
        local k = ch and ch.moduleGroupKey
        if k and keys[k] then
            if not skipped[1] then
                for j = 1, #injected do
                    out[#out + 1] = injected[j]
                end
                skipped[1] = true
            end
        else
            out[#out + 1] = ch
        end
    end
    return out
end

function TaskTracker.GetListViewRoot(tree)
    if not tree then return tree end
    local children = TaskTracker.BuildPatchListViewChildren(tree.children)
    if TaskTracker.AppendGeneratedTaskGroups then
        children = TaskTracker.AppendGeneratedTaskGroups(children)
    end
    return {
        id = tree.id,
        type = "root",
        children = children,
        expanded = tree.expanded,
    }
end

-- ─────────────────────────────────────
-- Modules tab grouping (same A/B/C)
-- ─────────────────────────────────────

local function midnightRegistryEntries()
    local out = {}
    if not TaskTracker.Registry then return out end
    for i = 1, #TaskTracker.Registry do
        local e = TaskTracker.Registry[i]
        if e.expansion == "midnight" then
            if TaskTracker.IsRegistryRequireOwnedLocked
                and TaskTracker.IsRegistryRequireOwnedLocked(e) then
                -- Hidden until the named collectable is owned (e.g. Du'gal dailies).
            else
                out[#out + 1] = e
            end
        end
    end
    return out
end

function TaskTracker.GetMidnightModuleLayout(mode)
    mode = mode or TaskTracker.GetPatchListGroupMode()
    local entries = midnightRegistryEntries()
    local function patchOf(e)
        return TaskTracker.GetMidnightPatchKeyFromSubsection and TaskTracker.GetMidnightPatchKeyFromSubsection(e.subsection)
    end
    local function zoneOf(e)
        return e.listZone or "midnight"
    end
    local function catOf(e)
        return TaskTracker.GetCollectionCategoryKey and TaskTracker.GetCollectionCategoryKey(e.subsection)
    end

    local function addToZoneBucket(buckets, e)
        local z = zoneOf(e)
        local b = buckets[z]
        if not b then
            b = { zoneKey = z, activities = {}, collections = {} }
            buckets[z] = b
        end
        local cat = catOf(e)
        if cat then
            local list = b.collections[cat]
            if not list then
                list = {}
                b.collections[cat] = list
            end
            list[#list + 1] = e
        else
            b.activities[#b.activities + 1] = e
        end
    end

    local function nestZoneList(flat)
        local byKey = {}
        for i = 1, #flat do
            local z = flat[i]
            z.subzones = z.subzones or {}
            byKey[z.zoneKey] = z
        end
        local order = zoneOrder()
        for i = 1, #order do
            local k = order[i]
            local b = byKey[k]
            if b then
                local parent = TaskTracker.GetListZoneParent and TaskTracker.GetListZoneParent(k)
                if parent and not byKey[parent] then
                    byKey[parent] = { zoneKey = parent, activities = {}, collections = {}, subzones = {} }
                end
            end
        end
        for i = 1, #order do
            local k = order[i]
            local b = byKey[k]
            if b then
                local parent = TaskTracker.GetListZoneParent and TaskTracker.GetListZoneParent(k)
                if parent and byKey[parent] then
                    local pb = byKey[parent]
                    pb.subzones = pb.subzones or {}
                    pb.subzones[#pb.subzones + 1] = b
                end
            end
        end
        local out = {}
        for i = 1, #order do
            local k = order[i]
            local b = byKey[k]
            if b and not (TaskTracker.GetListZoneParent and TaskTracker.GetListZoneParent(k)) then
                out[#out + 1] = b
            end
        end
        return out
    end

    local function zoneListFromBuckets(buckets)
        local flat = {}
        local order = zoneOrder()
        for i = 1, #order do
            local b = buckets[order[i]]
            if b then
                flat[#flat + 1] = b
            end
        end
        return nestZoneList(flat)
    end

    if mode == "zone" then
        local buckets = {}
        for i = 1, #entries do
            addToZoneBucket(buckets, entries[i])
        end
        return { kind = "zone", zones = zoneListFromBuckets(buckets) }
    end

    if mode == "patch_zone" then
        local byPatch = {}
        for i = 1, #entries do
            local e = entries[i]
            local pk = patchOf(e) or "_other"
            local buckets = byPatch[pk]
            if not buckets then
                buckets = {}
                byPatch[pk] = buckets
            end
            addToZoneBucket(buckets, e)
        end
        local patches = {}
        local order = patchRootOrder()
        for i = 1, #order do
            local pk = order[i]
            if byPatch[pk] then
                patches[#patches + 1] = {
                    patchKey = pk,
                    label = patchLabel(pk),
                    zones = zoneListFromBuckets(byPatch[pk]),
                }
            end
        end
        return { kind = "patch_zone", patches = patches }
    end

    return { kind = "patch" }
end

local function entryMatchesZoneFilter(entry, zoneKey, patchKey, collectionsOnly, activitiesOnly, collectionCategory, includeChildZones)
    if not entry or entry.expansion ~= "midnight" then return false end
    if zoneKey then
        local ez = entry.listZone or "midnight"
        if includeChildZones then
            if not (TaskTracker.IsListZoneUnder and TaskTracker.IsListZoneUnder(ez, zoneKey)) then
                return false
            end
        elseif ez ~= zoneKey then
            return false
        end
    end
    if patchKey then
        local pk = TaskTracker.GetMidnightPatchKeyFromSubsection and TaskTracker.GetMidnightPatchKeyFromSubsection(entry.subsection)
        if pk ~= patchKey then return false end
    end
    local cat = TaskTracker.GetCollectionCategoryKey and TaskTracker.GetCollectionCategoryKey(entry.subsection)
    if collectionsOnly and not cat then return false end
    if activitiesOnly and cat then return false end
    if collectionCategory and cat ~= collectionCategory then return false end
    return true
end

function TaskTracker.AreAllRegistryEntriesEnabledForListZone(zoneKey, patchKey, opt)
    opt = opt or {}
    if not TaskTracker.Registry then return true end
    for i = 1, #TaskTracker.Registry do
        local e = TaskTracker.Registry[i]
        if entryMatchesZoneFilter(e, zoneKey, patchKey, opt.collectionsOnly, opt.activitiesOnly, opt.collectionCategory, opt.includeChildZones) then
            if TaskTracker.IsRegistryRequireOwnedLocked
                and TaskTracker.IsRegistryRequireOwnedLocked(e) then
                -- Hidden until the named collectable is owned.
            elseif not TaskTracker.IsEntryEnabled(e.id) then
                return false
            end
        end
    end
    return true
end

function TaskTracker.SetAllRegistryEntriesForListZone(zoneKey, patchKey, on, opt)
    opt = opt or {}
    if not TaskTracker.Registry then return end
    for i = 1, #TaskTracker.Registry do
        local e = TaskTracker.Registry[i]
        if entryMatchesZoneFilter(e, zoneKey, patchKey, opt.collectionsOnly, opt.activitiesOnly, opt.collectionCategory, opt.includeChildZones) then
            if TaskTracker.IsRegistryRequireOwnedLocked
                and TaskTracker.IsRegistryRequireOwnedLocked(e) then
                -- skip locked
            elseif TaskTracker.SetCharRegistryVisEnabled then
                TaskTracker.SetCharRegistryVisEnabled(e.id, "enabled", on and true or false)
                if not on and TaskTracker.SetCollectionsShowCollectedOverride
                    and TaskTracker.IsCollectionsModuleEntry and TaskTracker.IsCollectionsModuleEntry(e) then
                    TaskTracker.SetCollectionsShowCollectedOverride(e.id, false)
                end
            end
        end
    end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    if TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end
