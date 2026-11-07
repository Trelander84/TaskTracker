-- Core/Widgets.lua
-- In-game UI widget reads (e.g. Delves Gilded Stash counter)

TaskTracker = TaskTracker or {}

local function tryStatusBarProgress(widgetId)
    if not C_UIWidgetManager or not widgetId then return nil, nil end
    local fns = {}
    if C_UIWidgetManager.GetStatusBarVisualizationInfo then
        fns[#fns + 1] = C_UIWidgetManager.GetStatusBarVisualizationInfo
    end
    if C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo then
        fns[#fns + 1] = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo
    end
    for i = 1, #fns do
        local ok, info = pcall(fns[i], widgetId)
        if ok and info then
            local bv  = info.barValue
            local bmx = info.barMax
            if bv ~= nil and bmx ~= nil and tonumber(bmx) and tonumber(bmx) > 0 then
                return tonumber(bv), tonumber(bmx)
            end
        end
    end
    return nil, nil
end

local function trySpellTooltipFraction(widgetId)
    if not C_UIWidgetManager or not C_UIWidgetManager.GetSpellDisplayVisualizationInfo then
        return nil, nil
    end
    local ok, info = pcall(C_UIWidgetManager.GetSpellDisplayVisualizationInfo, widgetId)
    if not ok or not info or not info.spellInfo or type(info.spellInfo.tooltip) ~= "string" then
        return nil, nil
    end
    local tip = info.spellInfo.tooltip
    local cur, mx = string.match(tip, "(%d+)%s*/%s*(%d+)")
    if not cur then
        cur, mx = string.match(tip, "(%d+)%s+of%s+(%d+)")
    end
    if cur and mx then
        return tonumber(cur), tonumber(mx)
    end
    return nil, nil
end

--- Current and reported max from a numbered UI widget (status bar first, then spell tooltip text).
function TaskTracker.GetRegistryWidgetProgressCounts(widgetId)
    if not widgetId then return nil, nil end
    if not IsPlayerInWorld() then return nil, nil end
    local cur, mx = tryStatusBarProgress(widgetId)
    if cur == nil then
        cur, mx = trySpellTooltipFraction(widgetId)
    end
    return cur, mx
end
