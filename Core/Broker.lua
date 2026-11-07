-- Core/Broker.lua
-- LibDataBroker (optional) + LibDBIcon minimap button (optional)

TaskTracker = TaskTracker or {}

local ADDON_NAME = "TaskTracker"
local ICON_PATH = "Interface\\AddOns\\TaskTracker\\Media\\TTIcon2.png"

local function HaveLib(name)
    if type(LibStub) == "function" then
        return LibStub(name, true)
    end
    if type(LibStub) == "table" and LibStub.GetLibrary then
        return LibStub:GetLibrary(name, true)
    end
    return nil
end

function TaskTracker.SetMinimapIconHidden(hidden)
    local db = TaskTrackerDB
    if not db then return end
    if type(db.minimap) ~= "table" then db.minimap = {} end
    db.minimap.hide = hidden and true or false

    local icon = TaskTracker._ttDbIcon
    if icon and icon.Hide and icon.Show then
        if db.minimap.hide then
            icon:Hide(ADDON_NAME)
        else
            icon:Show(ADDON_NAME)
        end
    end
end

function TaskTracker.ToggleMinimapIcon()
    local db = TaskTrackerDB
    if not db then return end
    TaskTracker.SetMinimapIconHidden(not (db.minimap and db.minimap.hide))
end

function TaskTracker.InitBroker()
    -- LibDataBroker-1.1 is optional; do nothing if missing.
    local ldb = HaveLib("LibDataBroker-1.1")
    if not ldb then return end

    -- Create or reuse the LDB object.
    if not TaskTracker._ttLdbObject then
        TaskTracker._ttLdbObject = ldb:NewDataObject(ADDON_NAME, {
            type = "launcher",
            text = "Task Tracker",
            icon = ICON_PATH,
        })
    end

    local obj = TaskTracker._ttLdbObject

    obj.OnClick = function(_, button)
        if button == "LeftButton" then
            if TaskTracker.TogglePanel then
                TaskTracker.TogglePanel()
            end
            return
        end

        if button == "RightButton" then
            -- Simple default: right-click toggles the minimap icon itself.
            TaskTracker.ToggleMinimapIcon()
        end
    end

    obj.OnTooltipShow = function(tooltip)
        if not tooltip then return end
        tooltip:AddLine("Task Tracker", 1, 1, 1)
        tooltip:AddLine("Left-click: toggle tracker", 0.85, 0.85, 0.85)
        tooltip:AddLine("Right-click: show/hide minimap icon", 0.85, 0.85, 0.85)
    end

    -- Minimap icon (LibDBIcon-1.0) is optional as well.
    local dbIcon = HaveLib("LibDBIcon-1.0")
    if not dbIcon then return end
    TaskTracker._ttDbIcon = dbIcon

    if not TaskTrackerDB then return end
    if type(TaskTrackerDB.minimap) ~= "table" then TaskTrackerDB.minimap = {} end
    if TaskTrackerDB.minimap.hide == nil then TaskTrackerDB.minimap.hide = false end

    -- Register once; on reload, LibDBIcon will ignore duplicates, but we guard anyway.
    if not TaskTracker._ttDbIconRegistered then
        dbIcon:Register(ADDON_NAME, obj, TaskTrackerDB.minimap)
        TaskTracker._ttDbIconRegistered = true
    end
end

