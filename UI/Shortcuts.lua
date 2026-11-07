-- UI/Shortcuts.lua
-- Ctrl / Alt / Shift clicks on the task name, the #/# count, and the Notes icon.
-- Missing saved keys use the defaults, so existing profiles keep today's clicks.

TaskTracker = TaskTracker or {}

local ACTION_LABEL = {
    none = "Nothing",
    taskSpecial = "Task special",
    openAchievement = "Open achievement",
    editTask = "Edit task",
    countUp = "Count up",
    countDown = "Count down",
    toggleProgressMode = "Manual / automatic",
    deleteTask = "Delete task",
    openPopout = "Open popout",
    editNotes = "Edit notes",
    custom = "Custom",
}

local TASK_MANAGEMENT = {
    label = "Task management",
    children = {
        { key = "editTask", label = "Edit task" },
        { key = "deleteTask", label = "Delete task" },
        { key = "countUp", label = "Count up" },
        { key = "countDown", label = "Count down" },
        { key = "toggleProgressMode", label = "Manual / automatic" },
    },
}

local NOTES_GROUP = {
    label = "Notes",
    children = {
        { key = "editNotes", label = "Edit notes" },
        { key = "openPopout", label = "Open popout" },
    },
}

local function commandMenu(includeSpecial)
    local specialKids = {
        { key = "openAchievement", label = "Open achievement" },
    }
    if includeSpecial then
        table.insert(specialKids, 1, { key = "taskSpecial", label = "Task special" })
    end
    local special = { label = "Task special", children = specialKids }
    return {
        { key = "none", label = "Nothing" },
        TASK_MANAGEMENT,
        special,
        NOTES_GROUP,
        { key = "custom", label = "Custom" },
    }
end

local TASK_CLICK_DEFAULTS = {
    ["normal-left"] = "countUp",
    ["normal-right"] = "countDown",
    ["ctrl-left"] = "taskSpecial",
    ["alt-left"] = "editTask",
    ["alt-right"] = "editTask",
    ["alt-middle"] = "editTask",
}

local DEFAULT_ACTION = {
    taskName = TASK_CLICK_DEFAULTS,
    progress = TASK_CLICK_DEFAULTS,
    notes = {
        ["shift-left"] = "openPopout",
        ["alt-left"] = "editNotes",
    },
}

local GROUPS = {
    { where = "taskName", title = "Task name", special = true },
    { where = "progress", title = "#/#", special = true },
    { where = "notes", title = "Notes", special = false },
}

local MOD_ORDER = { "normal", "ctrl", "alt", "shift" }
local MOD_LABEL = { normal = "Normal", ctrl = "Ctrl", alt = "Alt", shift = "Shift" }
local BTN_ORDER = { "left", "right", "middle" }
local BTN_LABEL = { left = "Left", right = "Right", middle = "Middle" }

local TYPE_ORDER = {
    { key = "basic", label = "Basic Task" },
    { key = "gold", label = "Gold" },
    { key = "achievement", label = "Achievement" },
    { key = "item", label = "Items" },
    { key = "quest", label = "Quest" },
    { key = "reputation", label = "Reputation" },
    { key = "mob_kill", label = "Mob Kills" },
    { key = "collectable", label = "Collectable" },
}

local TIP_PHRASE = {
    openPopout = "opens the popout",
    editTask = "opens the task window",
    openAchievement = "opens the achievement",
    countUp = "adds one",
    countDown = "subtracts one",
    toggleProgressMode = "switches manual and automatic",
    deleteTask = "asks to delete the task",
    custom = "runs your command",
}

local function knownAction(action)
    return type(action) == "string" and ACTION_LABEL[action] ~= nil
end

local function savedSlot(where, key)
    local db = TaskTrackerDB
    local all = db and db.rowShortcuts
    if type(all) ~= "table" then return nil end
    local group = all[where]
    if type(group) ~= "table" then return nil end
    local slot = group[key]
    if type(slot) ~= "table" or not knownAction(slot.action) then return nil end
    if slot.action == "taskSpecial" and where == "notes" then return nil end
    return slot
end

local function legacyNormalAction(where, buttonKey)
    if where == "notes" then return "editNotes" end
    if buttonKey == "right" then return "countDown" end
    if buttonKey == "left" then return "countUp" end
    return "none"
end

local function normalKeyButton(key)
    if type(key) ~= "string" then return nil end
    if key:sub(1, 7) ~= "normal-" then return nil end
    return key:sub(8)
end

local function effective(where, key)
    local saved = savedSlot(where, key)
    if saved then return saved.action, saved end
    local plain = normalKeyButton(key)
    if plain then return legacyNormalAction(where, plain), nil end
    local defaults = DEFAULT_ACTION[where]
    local action = defaults and defaults[key] or "none"
    return action, nil
end

local function typeChoice(saved, kind)
    local types = saved and saved.types
    local row = types and types[kind]
    if type(row) == "table" and knownAction(row.action) and row.action ~= "taskSpecial" then
        return row.action, row.command
    end
    if kind == "achievement" then return "openAchievement", nil end
    return "none", nil
end

local function taskKind(node)
    local adv = node and node.advanced
    if type(adv) == "table" and type(adv.type) == "string" and adv.type ~= "" then
        return adv.type
    end
    return "basic"
end

--- Resolved action and command for one modifier and button. Task special picks the task's type.
function TaskTracker.ResolveRowShortcut(where, node, mod, buttonKey)
    local action, saved = effective(where, mod .. "-" .. buttonKey)
    if action ~= "taskSpecial" then
        return action, saved and saved.command
    end
    local kind = taskKind(node)
    local typeAction, typeCommand = typeChoice(saved, kind)
    if typeAction == "none" and kind ~= "achievement"
        and node and TaskTracker.FirstAdvancedOfType
        and TaskTracker.FirstAdvancedOfType(node, "achievement") then
        local achAction, achCommand = typeChoice(saved, "achievement")
        if achAction ~= "none" then
            return achAction, achCommand
        end
    end
    return typeAction, typeCommand
end

local function cloneSlot(saved, action)
    local slot = { action = action }
    if type(saved) == "table" then
        if type(saved.command) == "string" and saved.command ~= "" then
            slot.command = saved.command
        end
        if saved.tip ~= nil then slot.tip = saved.tip and true or false end
        if type(saved.types) == "table" then
            local types = {}
            for kind, row in pairs(saved.types) do
                if type(kind) == "string" and type(row) == "table" and knownAction(row.action)
                    and row.action ~= "taskSpecial" then
                    local copy = { action = row.action }
                    if type(row.command) == "string" and row.command ~= "" then
                        copy.command = row.command
                    end
                    if row.tip ~= nil then copy.tip = row.tip and true or false end
                    types[kind] = copy
                end
            end
            if next(types) then slot.types = types end
        end
    end
    return slot
end

local function defaultOuterTip(where, key)
    if where == "taskName" and (key == "normal-left" or key == "normal-right") then
        return true
    end
    if (where == "taskName" or where == "progress") and (key == "ctrl-left" or key == "alt-left") then
        return true
    end
    return false
end

local function outerTipOn(where, key)
    local saved = savedSlot(where, key)
    if type(saved) == "table" and saved.tip ~= nil then
        return saved.tip and true or false
    end
    return defaultOuterTip(where, key)
end

local function typeTipOn(saved, kind)
    local types = saved and saved.types
    local row = types and types[kind]
    if type(row) == "table" and row.tip ~= nil then
        return row.tip and true or false
    end
    return kind == "achievement"
end

local function slotIsDefault(where, key, slot)
    local plain = normalKeyButton(key)
    local expect
    if plain then
        expect = legacyNormalAction(where, plain)
    else
        local defaults = DEFAULT_ACTION[where]
        expect = defaults and defaults[key] or "none"
    end
    if slot.action ~= expect then return false end
    if type(slot.command) == "string" and slot.command ~= "" then return false end
    if slot.tip ~= nil and (slot.tip and true or false) ~= defaultOuterTip(where, key) then
        return false
    end
    if slot.action ~= "taskSpecial" then return true end
    if type(slot.types) ~= "table" then return true end
    for kind, row in pairs(slot.types) do
        if type(row) == "table" then
            local typeExpect = (kind == "achievement") and "openAchievement" or "none"
            if row.action ~= typeExpect then return false end
            if type(row.command) == "string" and row.command ~= "" then return false end
            if row.tip ~= nil and (row.tip and true or false) ~= (kind == "achievement") then
                return false
            end
        end
    end
    return true
end

local function pruneShortcuts(where)
    local db = TaskTrackerDB
    if not db or type(db.rowShortcuts) ~= "table" then return end
    local group = db.rowShortcuts[where]
    if type(group) == "table" and not next(group) then
        db.rowShortcuts[where] = nil
    end
    if not next(db.rowShortcuts) then
        db.rowShortcuts = nil
    end
end

local function storeSlot(where, key, slot)
    if not TaskTrackerDB then return end
    if slotIsDefault(where, key, slot) then
        local all = TaskTrackerDB.rowShortcuts
        if type(all) == "table" and type(all[where]) == "table" then
            all[where][key] = nil
            pruneShortcuts(where)
        end
        return
    end
    if type(TaskTrackerDB.rowShortcuts) ~= "table" then
        TaskTrackerDB.rowShortcuts = {}
    end
    if type(TaskTrackerDB.rowShortcuts[where]) ~= "table" then
        TaskTrackerDB.rowShortcuts[where] = {}
    end
    TaskTrackerDB.rowShortcuts[where][key] = slot
end

local function setOuterAction(where, key, action)
    if not knownAction(action) then return end
    if action == "taskSpecial" and where == "notes" then return end
    local _, saved = effective(where, key)
    local slot = cloneSlot(saved, action)
    if action ~= "custom" then slot.command = nil end
    if action ~= "taskSpecial" then slot.types = nil end
    storeSlot(where, key, slot)
end

local function setTypeAction(where, key, kind, action, command)
    if not knownAction(action) or action == "taskSpecial" then return end
    local outer = effective(where, key)
    if outer ~= "taskSpecial" then return end
    local _, saved = effective(where, key)
    local slot = cloneSlot(saved, "taskSpecial")
    slot.types = slot.types or {}
    local row = { action = action }
    if action == "custom" and type(command) == "string" and command ~= "" then
        row.command = command
    end
    local prev = slot.types[kind]
    if type(prev) == "table" and prev.tip ~= nil then
        row.tip = prev.tip and true or false
    end
    local expect = (kind == "achievement") and "openAchievement" or "none"
    local tipExpect = kind == "achievement"
    local tipDefault = row.tip == nil or (row.tip and true or false) == tipExpect
    if row.action == expect and not row.command and tipDefault then
        slot.types[kind] = nil
    else
        if tipDefault then row.tip = nil end
        slot.types[kind] = row
    end
    if not next(slot.types) then slot.types = nil end
    storeSlot(where, key, slot)
end

local function setCustomCommand(where, key, kind, text)
    if TaskTracker.ClampCommandText then
        text = TaskTracker.ClampCommandText(text or "")
    else
        text = type(text) == "string" and text or ""
    end
    if kind then
        setTypeAction(where, key, kind, "custom", text)
        return
    end
    local _, saved = effective(where, key)
    local slot = { action = "custom" }
    if text ~= "" then slot.command = text end
    if type(saved) == "table" and saved.tip ~= nil then
        slot.tip = saved.tip and true or false
    end
    storeSlot(where, key, slot)
end

local function setTip(where, key, kind, on)
    on = on and true or false
    if kind then
        if effective(where, key) ~= "taskSpecial" then return end
        local _, saved = effective(where, key)
        local slot = cloneSlot(saved, "taskSpecial")
        slot.types = slot.types or {}
        local action, command = typeChoice(saved, kind)
        local row = slot.types[kind]
        if type(row) ~= "table" then
            row = { action = action }
            if action == "custom" and type(command) == "string" and command ~= "" then
                row.command = command
            end
        else
            row = {
                action = row.action,
                command = row.command,
            }
            if type(row.command) ~= "string" or row.command == "" then
                row.command = nil
            end
        end
        local tipExpect = kind == "achievement"
        if on == tipExpect then
            row.tip = nil
        else
            row.tip = on
        end
        local expect = (kind == "achievement") and "openAchievement" or "none"
        if row.action == expect and not row.command and row.tip == nil then
            slot.types[kind] = nil
        else
            slot.types[kind] = row
        end
        if not next(slot.types) then slot.types = nil end
        storeSlot(where, key, slot)
        return
    end
    local action, saved = effective(where, key)
    local slot = cloneSlot(saved, action)
    if on == defaultOuterTip(where, key) then
        slot.tip = nil
    else
        slot.tip = on
    end
    storeSlot(where, key, slot)
end

--- Same confirm as Delete on the task window. The task is removed only after Delete.
function TaskTracker.ConfirmDeleteTask(node)
    if not node or node.type ~= "task" or not node.id then return end
    local nodeId = node.id
    local title = node.name or "task"
    StaticPopupDialogs["TASKTRACKER_DEL_TASK"] = {
        text = "Delete task '" .. title .. "'?",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function()
            if TaskTracker.RemoveNode then
                TaskTracker.RemoveNode(nodeId)
            end
            local editor = TaskTracker.taskDialog
            if editor and editor.IsShown and editor:IsShown() and editor._editNodeId == nodeId and editor.Hide then
                editor:Hide()
            end
            local received = TaskTracker._receivedTaskDialog
            if received and received.IsShown and received:IsShown() and received._nodeId == nodeId and received.Hide then
                received:Hide()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("TASKTRACKER_DEL_TASK")
end

--- One line is one macro. Several lines each run on their own. Nothing runs in combat.
function TaskTracker.RunShortcutCommand(text)
    if InCombatLockdown and InCombatLockdown() then return end
    if not TaskTracker.RunSlashLines then return end
    if TaskTracker.ClampCommandText then
        text = TaskTracker.ClampCommandText(text or "")
    end
    if type(text) ~= "string" or text == "" then return end
    TaskTracker.RunSlashLines(text)
end

local function performShortcut(action, node, command)
    if action == "none" or action == nil or action == "taskSpecial" then return end
    if action == "countUp" or action == "countDown" then
        if TaskTracker.editMode then return end
        local id = node and node.id
        if id and TaskTracker.AdjustTaskCount then
            TaskTracker.AdjustTaskCount(id, action == "countUp" and 1 or -1)
        end
        return
    end
    if action == "toggleProgressMode" then
        if TaskTracker.editMode then return end
        if TaskTracker.ToggleTaskProgressMode then
            TaskTracker.ToggleTaskProgressMode(node)
        end
        return
    end
    if action == "deleteTask" then
        if node and node.type == "task" and node.id and TaskTracker.ConfirmDeleteTask then
            TaskTracker.ConfirmDeleteTask(node)
        end
        return
    end
    if action == "openAchievement" then
        if TaskTracker.OpenTaskAchievement then
            TaskTracker.OpenTaskAchievement(node)
        end
        return
    end
    if action == "editTask" then
        if node and node.type == "task" and TaskTracker.taskDialog and TaskTracker.taskDialog.OpenEdit then
            TaskTracker.taskDialog.OpenEdit(node)
        end
        return
    end
    if action == "openPopout" then
        if node and node.id and TaskTracker.ShowSavedNotePeek then
            TaskTracker.ShowSavedNotePeek(node.id)
        end
        return
    end
    if action == "editNotes" then
        if node and TaskTracker.OpenNoteWindow then
            TaskTracker.OpenNoteWindow(node)
        end
        return
    end
    if action == "custom" then
        TaskTracker.RunShortcutCommand(command)
    end
end

local function heldModifier()
    if (IsAltKeyDown and IsAltKeyDown())
        or (IsLeftAltKeyDown and IsLeftAltKeyDown())
        or (IsRightAltKeyDown and IsRightAltKeyDown()) then
        return "alt"
    end
    if IsControlKeyDown and IsControlKeyDown() then return "ctrl" end
    if IsShiftKeyDown and IsShiftKeyDown() then return "shift" end
    return nil
end

local function buttonName(button)
    if button == "RightButton" then return "right" end
    if button == "MiddleButton" then return "middle" end
    return "left"
end

--- True when Shortcuts handled the click. A plain click with no saved Normal row keeps the old behavior.
function TaskTracker.RunRowShortcut(where, node, button)
    local buttonKey = buttonName(button)
    local mod = heldModifier()
    if not mod then
        if where == "notes" and not savedSlot(where, "normal-" .. buttonKey) then
            return false
        end
        mod = "normal"
    end
    local action, command = TaskTracker.ResolveRowShortcut(where, node, mod, buttonKey)
    performShortcut(action, node, command)
    return true
end

function TaskTracker.NotesButtonTip()
    local bits = { "Click opens Notes." }
    local plainLeft = savedSlot("notes", "normal-left")
    if plainLeft and plainLeft.action ~= "editNotes" then
        local phrase = TIP_PHRASE[plainLeft.action]
        if phrase then
            bits[1] = "Click " .. phrase .. "."
        else
            bits[1] = "Click does nothing."
        end
    end
    for i = 1, #MOD_ORDER do
        local mod = MOD_ORDER[i]
        for j = 1, #BTN_ORDER do
            local btn = BTN_ORDER[j]
            if mod == "normal" and not savedSlot("notes", "normal-" .. btn) then
                -- A plain click still opens Notes until that row is changed.
            else
            local action = TaskTracker.ResolveRowShortcut("notes", nil, mod, btn)
            local phrase = TIP_PHRASE[action]
            if phrase and outerTipOn("notes", mod .. "-" .. btn) then
                bits[#bits + 1] = MOD_LABEL[mod] .. "-" .. btn .. " " .. phrase .. "."
            end
            end
        end
    end
    return table.concat(bits, " ")
end

local function clickMark(which)
    if which == "middle" then return "middle" end
    local atlas = (which == "right") and "housing-hotkey-icon-rightclick" or "housing-hotkey-icon-leftclick"
    if CreateAtlasMarkup then
        return CreateAtlasMarkup(atlas, 14, 14)
    end
    return "|A:" .. atlas .. ":14:14|a"
end

local function tipKind(node, saved)
    local kind = taskKind(node)
    local typeAction = typeChoice(saved, kind)
    if typeAction == "none" and kind ~= "achievement"
        and node and TaskTracker.FirstAdvancedOfType
        and TaskTracker.FirstAdvancedOfType(node, "achievement") then
        local achAction = typeChoice(saved, "achievement")
        if achAction ~= "none" then return "achievement" end
    end
    return kind
end

local function shortcutDisplay(action, command)
    if action == "custom" then
        local preview = TaskTracker.CommandPreviewText and TaskTracker.CommandPreviewText(command or "") or ""
        if preview ~= "" then return preview end
    end
    return ACTION_LABEL[action] or "Nothing"
end

local function tooltipLabel(where, node, mod, btn)
    local key = mod .. "-" .. btn
    if not outerTipOn(where, key) then return nil end
    local action, saved = effective(where, key)
    if action == "taskSpecial" then
        if not typeTipOn(saved, tipKind(node, saved)) then return nil end
    end
    local resolved, command = TaskTracker.ResolveRowShortcut(where, node, mod, btn)
    if resolved == nil or resolved == "none" then return nil end
    return shortcutDisplay(resolved, command)
end

function TaskTracker.AppendRowShortcutTooltipLines(node)
    if TaskTrackerDB and TaskTrackerDB.showShortcutHints == false then return end
    if not GameTooltip or not GameTooltip.AddLine then return end
    local lines = {}
    local function add(prefix, which, label)
        local mark = clickMark(which)
        if prefix and prefix ~= "" then
            lines[#lines + 1] = prefix .. " " .. mark .. " : " .. label
        else
            lines[#lines + 1] = mark .. " : " .. label
        end
    end
    local function modWord(mod)
        if mod == "normal" then return "" end
        return MOD_LABEL[mod]
    end
    -- Module rows keep their own name and count clicks, so those lines stay off this list.
    if node and node.type == "task" then
        for i = 1, #MOD_ORDER do
            local mod = MOD_ORDER[i]
            for j = 1, #BTN_ORDER do
                local btn = BTN_ORDER[j]
                local nameLabel = tooltipLabel("taskName", node, mod, btn)
                local progLabel = tooltipLabel("progress", node, mod, btn)
                local word = modWord(mod)
                if nameLabel and nameLabel == progLabel then
                    add(word, btn, nameLabel)
                else
                    if nameLabel then
                        local prefix = word
                        if progLabel then
                            prefix = (word == "") and "Name" or ("Name " .. word)
                        end
                        add(prefix, btn, nameLabel)
                    end
                    if progLabel then
                        local prefix = word
                        if nameLabel then
                            prefix = (word == "") and "#/#" or ("#/# " .. word)
                        end
                        add(prefix, btn, progLabel)
                    end
                end
            end
        end
    else
        local label = tooltipLabel("taskName", node, "ctrl", "left")
        if label then add("Ctrl", "left", label) end
    end
    for i = 1, #MOD_ORDER do
        local mod = MOD_ORDER[i]
        for j = 1, #BTN_ORDER do
            local btn = BTN_ORDER[j]
            local label = tooltipLabel("notes", node, mod, btn)
            if label then
                local word = modWord(mod)
                add((word == "") and "Notes" or ("Notes " .. word), btn, label)
            end
        end
    end
    if #lines == 0 then return end
    GameTooltip:AddLine(" ", 1, 1, 1, false)
    for i = 1, #lines do
        GameTooltip:AddLine(lines[i], 0.65, 0.65, 0.65, false)
    end
end

-- ─────────────────────────────────────
-- Options page
-- ─────────────────────────────────────

local function rowHeight()
    local h = TaskTracker.GetOptionsRowHeight and TaskTracker.GetOptionsRowHeight() or 28
    if h < 22 then h = 22 end
    return h
end

local function makeCommandBox(parent, onSave)
    local t = TaskTracker.GetTheme and TaskTracker.GetTheme()
    local box = CreateFrame("EditBox", nil, parent)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(TaskTracker.COMMAND_TEXT_CAP or 4000)
    box:SetFontObject((t and t.fontNormal) or "GameFontNormalSmall")
    if TaskTracker.ApplyOptionsFont then
        TaskTracker.ApplyOptionsFont(box, "body")
    elseif TaskTracker.ClearFontShadow then
        TaskTracker.ClearFontShadow(box)
    end
    box:SetTextInsets(6, 6, 4, 4)
    box:SetJustifyH("LEFT")
    box:SetJustifyV("TOP")
    local c = t and t.textPrimary
    if c then box:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    TaskTracker.SetColor(bg, "headerBg2")
    TaskTracker.MakeBorder(box, "border")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function(self)
        local text = self:GetText() or ""
        if TaskTracker.ClampCommandText then
            text = TaskTracker.ClampCommandText(text)
            if self:GetText() ~= text then self:SetText(text) end
        end
        onSave(text)
    end)
    box:Hide()
    return box
end

local function sizeDrop(drop, width, height)
    if not drop or not drop.button then return end
    drop.button:SetSize(width, height)
    if drop.menu then drop.menu:SetWidth(width) end
    local inner = math.max(40, width - 10)
    local rows = drop.rows
    if rows then
        for i = 1, #rows do
            if rows[i] then rows[i]:SetWidth(inner) end
        end
    end
    local flyouts = drop.flyouts
    if flyouts then
        for i = 1, #flyouts do
            local fly = flyouts[i]
            fly:SetWidth(width)
            local flyRows = fly.rows
            if flyRows then
                for j = 1, #flyRows do
                    if flyRows[j] then flyRows[j]:SetWidth(inner) end
                end
            end
        end
    end
end

local function hideMenus(ui)
    local rows = ui.rows
    for i = 1, #rows do
        local row = rows[i]
        if row.drop and row.drop.menu then row.drop.menu:Hide() end
        local types = row.types
        if types then
            for t = 1, #types do
                if types[t].drop and types[t].drop.menu then
                    types[t].drop.menu:Hide()
                end
            end
        end
    end
end

local function syncEdit(edit, text)
    if not edit or edit:HasFocus() then return end
    edit:SetText(text or "")
end

local TIP_W = 36

local function makeTipSwitch(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(TIP_W, 16)
    local trackBg = btn:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    TaskTracker.MakeBorder(btn, "border")
    local thumb = btn:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(14, 12)
    function btn:SetOn(isOn)
        btn._ttOn = not not isOn
        if btn._ttOn then
            TaskTracker.SetColor(trackBg, "accent")
            TaskTracker.SetColor(thumb, "bg")
            thumb:ClearAllPoints()
            thumb:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        else
            TaskTracker.SetColor(trackBg, "inputBg")
            TaskTracker.SetColor(thumb, "textPrimary")
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", btn, "LEFT", 2, 0)
        end
    end
    function btn:GetOn()
        return btn._ttOn and true or false
    end
    btn:SetOn(false)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Tooltip", 1, 1, 1)
        GameTooltip:AddLine("Shows this click on the task tooltip.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:Hide()
    return btn
end

local function placeTip(tip, button, on)
    if not tip or not button then return end
    tip:ClearAllPoints()
    tip:SetPoint("LEFT", button, "RIGHT", 8, 0)
    tip:SetOn(on and true or false)
    tip:Show()
end

local function ensureTypeRows(ui, row)
    if row.types then return end
    local made = {}
    for i = 1, #TYPE_ORDER do
        local spec = TYPE_ORDER[i]
        local kind = spec.key
        local where = row.where
        local key = row.key
        local lab = TaskTracker.CreateFontString(ui.pane, nil, "OVERLAY", ui.font)
        lab:SetJustifyH("LEFT")
        lab:SetJustifyV("MIDDLE")
        lab:SetText(spec.label)
        TaskTracker.SetTextColor(lab, "textPrimary")
        lab:Hide()
        local drop = TaskTracker.MakeDropdown(ui.pane, {
            width = 200,
            buttonHeight = 22,
            rowHeight = 22,
            rowGap = 2,
            items = commandMenu(false),
            disableHover = true,
            quiet = true,
            choiceBgKey = "headerBg2",
            menuBgKey = "headerBg2",
            menuParent = ui.content,
            getSelected = function()
                local _, saved = effective(where, key)
                return typeChoice(saved, kind)
            end,
            selectedLabel = function(action)
                return ACTION_LABEL[action] or "Nothing"
            end,
            onSelect = function(action)
                local keep
                if action == "custom" then
                    local _, saved = effective(where, key)
                    local _, cmd = typeChoice(saved, kind)
                    keep = cmd
                end
                setTypeAction(where, key, kind, action, keep)
                if ui.rebuild then ui.rebuild() end
            end,
        })
        drop.button:Hide()
        local tip = makeTipSwitch(ui.pane)
        tip:SetScript("OnClick", function(self)
            local nextOn = not self:GetOn()
            setTip(where, key, kind, nextOn)
            self:SetOn(nextOn)
        end)
        local edit = makeCommandBox(ui.pane, function(text)
            if effective(where, key) ~= "taskSpecial" then return end
            local _, saved = effective(where, key)
            if typeChoice(saved, kind) ~= "custom" then return end
            setCustomCommand(where, key, kind, text)
        end)
        made[i] = { kind = kind, label = lab, drop = drop, edit = edit, tip = tip }
    end
    row.types = made
end

local function placeEdit(edit, pane, x, y, width)
    edit:ClearAllPoints()
    edit:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -y)
    edit:SetSize(width, 48)
    edit:Show()
end

local function hideCombo(row)
    if not row then return end
    if row.label then row.label:Hide() end
    if row.drop and row.drop.button then row.drop.button:Hide() end
    if row.drop and row.drop.menu then row.drop.menu:Hide() end
    if row.edit then row.edit:Hide() end
    if row.tip then row.tip:Hide() end
    local types = row.types
    if not types then return end
    for i = 1, #types do
        local typeRow = types[i]
        typeRow.label:Hide()
        if typeRow.drop and typeRow.drop.button then typeRow.drop.button:Hide() end
        if typeRow.drop and typeRow.drop.menu then typeRow.drop.menu:Hide() end
        if typeRow.edit then typeRow.edit:Hide() end
        if typeRow.tip then typeRow.tip:Hide() end
    end
end

local function foldOpen(key)
    local map = TaskTrackerDB and TaskTrackerDB.optionsExpanded
    if type(map) ~= "table" then return false end
    return map[key] and true or false
end

local function placeHeader(header, pane, x, y, w, h, open, bgKey)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -y)
    header:SetSize(w, h)
    header:Show()
    if header._ttBg then TaskTracker.SetColor(header._ttBg, bgKey) end
    if TaskTracker.ApplyTwistIcon then
        TaskTracker.ApplyTwistIcon(header._ttArrow, open)
    end
    return y + h + 2
end

local function placeCombo(ui, row, x, y, width, rh, gap)
    local labelW = math.min(120, math.floor(width * 0.32))
    local dropW = math.max(100, width - labelW - 12 - TIP_W - 8)
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", ui.pane, "TOPLEFT", x, -y)
    row.label:SetSize(labelW, rh)
    row.label:Show()
    sizeDrop(row.drop, dropW, rh)
    row.drop.button:ClearAllPoints()
    row.drop.button:SetPoint("TOPLEFT", ui.pane, "TOPLEFT", x + labelW + 12, -y)
    row.drop.button:Show()
    if row.drop.refresh then row.drop.refresh() end
    placeTip(row.tip, row.drop.button, outerTipOn(row.where, row.key))
    y = y + rh + gap
    local action, saved = effective(row.where, row.key)
    if action == "custom" then
        syncEdit(row.edit, saved and saved.command or "")
        placeEdit(row.edit, ui.pane, x + labelW + 12, y, dropW)
        y = y + 48 + gap
    else
        row.edit:Hide()
    end
    if action == "taskSpecial" and row.special then
        ensureTypeRows(ui, row)
        local types = row.types
        local indent = x + 16
        local typeW = math.max(80, width - 16)
        local typeLabelW = math.min(140, math.floor(typeW * 0.36))
        local typeDropW = math.max(100, typeW - typeLabelW - 12 - TIP_W - 8)
        for i = 1, #types do
            local typeRow = types[i]
            typeRow.label:ClearAllPoints()
            typeRow.label:SetPoint("TOPLEFT", ui.pane, "TOPLEFT", indent, -y)
            typeRow.label:SetSize(typeLabelW, rh)
            typeRow.label:Show()
            sizeDrop(typeRow.drop, typeDropW, rh)
            typeRow.drop.button:ClearAllPoints()
            typeRow.drop.button:SetPoint("TOPLEFT", ui.pane, "TOPLEFT", indent + typeLabelW + 12, -y)
            typeRow.drop.button:Show()
            if typeRow.drop.refresh then typeRow.drop.refresh() end
            placeTip(typeRow.tip, typeRow.drop.button, typeTipOn(saved, typeRow.kind))
            y = y + rh + gap
            local typeAction, typeCommand = typeChoice(saved, typeRow.kind)
            if typeAction == "custom" then
                syncEdit(typeRow.edit, typeCommand or "")
                placeEdit(typeRow.edit, ui.pane, indent + typeLabelW + 12, y, typeDropW)
                y = y + 48 + gap
            else
                typeRow.edit:Hide()
            end
        end
    elseif row.types then
        for i = 1, #row.types do
            local typeRow = row.types[i]
            typeRow.label:Hide()
            typeRow.drop.button:Hide()
            if typeRow.drop.menu then typeRow.drop.menu:Hide() end
            typeRow.edit:Hide()
            if typeRow.tip then typeRow.tip:Hide() end
        end
    end
    return y
end

local function makeTwistHeader(parent, label, top)
    local t = TaskTracker.GetTheme and TaskTracker.GetTheme()
    local btn = CreateFrame("Button", nil, parent)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    btn._ttBg = bg
    TaskTracker.SetColor(bg, top and "headerBg" or "headerBg2")
    TaskTracker.MakeEdge(btn, "BOTTOM", "border")
    local arrowX = 8
    if top and TaskTracker.MakeAccentBar then
        TaskTracker.MakeAccentBar(btn)
        arrowX = ((t and t.accentBarWidth) or 3) + 8
    end
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("LEFT", btn, "LEFT", arrowX, 0)
    btn._ttArrow = arrow
    if TaskTracker.ApplyTwistIcon then
        TaskTracker.ApplyTwistIcon(arrow, false)
    end
    local lab = TaskTracker.CreateFontString(btn, nil, "OVERLAY", (t and t.fontNormal) or "GameFontNormalSmall")
    lab:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
    lab:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    lab:SetJustifyH("LEFT")
    lab:SetJustifyV("MIDDLE")
    lab:SetText(label)
    TaskTracker.SetTextColor(lab, "textHeader")
    return btn
end

local function bindFold(ui, btn, key)
    btn:SetScript("OnClick", function()
        if not TaskTrackerDB then return end
        if type(TaskTrackerDB.optionsExpanded) ~= "table" then
            TaskTrackerDB.optionsExpanded = {}
        end
        local cur = TaskTrackerDB.optionsExpanded[key] and true or false
        TaskTrackerDB.optionsExpanded[key] = not cur
        if ui.rebuild then ui.rebuild() end
    end)
end

local function layoutShortcuts(ui)
    local keep = 0
    if ui.scroll and ui.scroll.GetVerticalScroll then
        keep = ui.scroll:GetVerticalScroll() or 0
    end
    hideMenus(ui)
    local sw = ui.scroll and ui.scroll:GetWidth() or 400
    if sw < 80 then sw = 400 end
    sw = math.max(280, sw - 16)
    local pad = 16
    local inner = sw - pad * 2
    local rh = rowHeight()
    local gap = 6
    local y = 10

    ui.hint:ClearAllPoints()
    ui.hint:SetPoint("TOPLEFT", ui.pane, "TOPLEFT", pad, -y)
    ui.hint:SetWidth(inner)
    local hintH = 28
    if ui.hint.GetStringHeight then
        local measured = ui.hint:GetStringHeight()
        if measured and measured > 8 then hintH = measured end
    end
    y = y + hintH + 12

    local sections = ui.sections or {}
    for s = 1, #sections do
        local section = sections[s]
        local groupOpen = foldOpen(section.expandKey)
        y = placeHeader(section.header, ui.pane, 0, y, sw, 26, groupOpen, "headerBg")
        local mods = section.mods
        for m = 1, #mods do
            local block = mods[m]
            if not groupOpen then
                block.header:Hide()
                for r = 1, #block.rows do
                    hideCombo(block.rows[r])
                end
            else
                local modOpen = foldOpen(block.expandKey)
                y = placeHeader(block.header, ui.pane, 12, y, sw - 12, 22, modOpen, "headerBg2")
                for r = 1, #block.rows do
                    local row = block.rows[r]
                    if not modOpen then
                        hideCombo(row)
                    else
                        y = placeCombo(ui, row, 28, y, sw - 36, rh, gap)
                    end
                end
            end
        end
        y = y + 6
    end

    local h = y + 16
    ui.pane:SetSize(sw, h)
    ui.child:SetSize(sw, h)
    local view = ui.scroll:GetHeight() or 0
    local maxS = math.max(0, h - view)
    if keep < 0 then keep = 0 end
    if keep > maxS then keep = maxS end
    ui.scroll:SetVerticalScroll(keep)
    if ui.scroll.UpdateScrollBar then
        ui.scroll.UpdateScrollBar()
    end
end

local function addComboRow(ui, where, key, special, labelText)
    local lab = TaskTracker.CreateFontString(ui.pane, nil, "OVERLAY", ui.font)
    lab:SetJustifyH("LEFT")
    lab:SetJustifyV("MIDDLE")
    lab:SetText(labelText)
    TaskTracker.SetTextColor(lab, "textPrimary")
    local items = commandMenu(special)
    local drop = TaskTracker.MakeDropdown(ui.pane, {
        width = 200,
        buttonHeight = 22,
        rowHeight = 22,
        rowGap = 2,
        items = items,
        disableHover = true,
        quiet = true,
        choiceBgKey = "headerBg2",
        menuBgKey = "headerBg2",
        menuParent = ui.content,
        getSelected = function()
            return effective(where, key)
        end,
        selectedLabel = function(action)
            return ACTION_LABEL[action] or "Nothing"
        end,
        onSelect = function(action)
            setOuterAction(where, key, action)
            if ui.rebuild then ui.rebuild() end
        end,
    })
    local edit = makeCommandBox(ui.pane, function(text)
        if effective(where, key) ~= "custom" then return end
        setCustomCommand(where, key, nil, text)
    end)
    local tip = makeTipSwitch(ui.pane)
    tip:SetScript("OnClick", function(self)
        local nextOn = not self:GetOn()
        setTip(where, key, nil, nextOn)
        self:SetOn(nextOn)
    end)
    ui.rows[#ui.rows + 1] = {
        where = where,
        key = key,
        special = special,
        label = lab,
        drop = drop,
        edit = edit,
        tip = tip,
    }
end

function TaskTracker.BuildShortcutsPanel(parent)
    local ui = {}
    ui.content, ui.scroll, ui.child, ui.pane = TaskTracker.MakeScrollPane(parent, { childWidth = 400 })
    local t = TaskTracker.GetTheme and TaskTracker.GetTheme()
    ui.font = (t and t.fontNormal) or "GameFontNormalSmall"
    ui.rows = {}

    ui.hint = TaskTracker.CreateFontString(ui.pane, nil, "OVERLAY", ui.font)
    ui.hint:SetJustifyH("LEFT")
    if ui.hint.SetWordWrap then ui.hint:SetWordWrap(true) end
    TaskTracker.SetTextColor(ui.hint, "textSecondary")
    ui.hint:SetText("Open a section, then Left, Right, or Middle. Normal is a click with no extra key. If you hold two keys, Alt wins, then Ctrl, then Shift.")

    ui.sections = {}
    for g = 1, #GROUPS do
        local group = GROUPS[g]
        local header = makeTwistHeader(ui.pane, group.title, true)
        local expandKey = "shortcuts_" .. group.where
        bindFold(ui, header, expandKey)
        local blocks = {}
        for b = 1, #BTN_ORDER do
            local btn = BTN_ORDER[b]
            local btnHeader = makeTwistHeader(ui.pane, BTN_LABEL[btn], false)
            local btnKey = expandKey .. "_" .. btn
            bindFold(ui, btnHeader, btnKey)
            local rows = {}
            for m = 1, #MOD_ORDER do
                local mod = MOD_ORDER[m]
                local clickKey = mod .. "-" .. btn
                addComboRow(ui, group.where, clickKey, group.special, MOD_LABEL[mod])
                rows[#rows + 1] = ui.rows[#ui.rows]
            end
            blocks[#blocks + 1] = {
                expandKey = btnKey,
                header = btnHeader,
                rows = rows,
            }
        end
        ui.sections[#ui.sections + 1] = {
            header = header,
            expandKey = expandKey,
            mods = blocks,
        }
    end

    ui.rebuild = function()
        layoutShortcuts(ui)
    end
    ui.content.scrollFrame = ui.scroll
    ui.content.RebuildLayout = ui.rebuild
    ui.content.OnShow = function()
        ui.rebuild()
    end
    if ui.scroll and ui.scroll.HookScript then
        ui.scroll:HookScript("OnVerticalScroll", function()
            hideMenus(ui)
        end)
    end
    ui.rebuild()
    return ui.content
end
