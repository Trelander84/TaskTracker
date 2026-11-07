-- Core/LinkInsert.lua
-- Allow Shift-click item/currency/quest links to insert into TaskTracker edit boxes.

TaskTracker = TaskTracker or {}

TaskTracker._ttLinkEditBoxes = TaskTracker._ttLinkEditBoxes or {}

function TaskTracker.RegisterLinkableEditBox(editBox)
    if not editBox then return end
    TaskTracker._ttLinkEditBoxes[editBox] = true

    -- Track last-focused TT edit box.
    local prev = editBox:GetScript("OnEditFocusGained")
    editBox:SetScript("OnEditFocusGained", function(self, ...)
        TaskTracker._ttActiveLinkEditBox = self
        if prev then
            pcall(prev, self, ...)
        end
    end)
end

--- Optional: when opening a task kind (quest, item, …), set this so shift-click works without clicking the field first.
function TaskTracker.SetDefaultLinkInsertEditBox(editBox)
    if editBox and TaskTracker._ttLinkEditBoxes and TaskTracker._ttLinkEditBoxes[editBox] then
        TaskTracker._ttActiveLinkEditBox = editBox
    end
end

local function blizzardChatEditHasFocus()
    if not ChatFrameUtil or not ChatFrameUtil.GetActiveWindow then
        return false
    end
    local w = ChatFrameUtil.GetActiveWindow()
    if not w or not w.editBox then
        return false
    end
    return w.editBox:IsVisible() and w.editBox:HasFocus()
end

local function tryInsertLinkIntoTaskTracker(text)
    local eb = TaskTracker._ttActiveLinkEditBox
    if not eb or not TaskTracker._ttLinkEditBoxes or TaskTracker._ttLinkEditBoxes[eb] ~= true then
        return false
    end
    if not eb.IsShown or not eb:IsShown() or not eb.Insert then
        return false
    end
    -- Don't steal links from the chat box when it's focused (same idea as AceGUI / ChatIM).
    if blizzardChatEditHasFocus() and (not eb.HasFocus or not eb:HasFocus()) then
        return false
    end
    eb:Insert(text)
    if eb.SetFocus then
        eb:SetFocus()
    end
    return true
end

function TaskTracker.EnsureLinkInsertHooks()
    if type(ChatEdit_InsertLink) == "function" and not TaskTracker._ttChatEditInsertLinkWrapped then
        TaskTracker._ttChatEditInsertLinkWrapped = true
        local orig = ChatEdit_InsertLink
        ChatEdit_InsertLink = function(text, ...)
            if text and tryInsertLinkIntoTaskTracker(text) then
                return true
            end
            return orig(text, ...)
        end
    end

    -- Retail routes many shift-clicks here instead of ChatEdit_InsertLink.
    if ChatFrameUtil and type(ChatFrameUtil.InsertLink) == "function" and not TaskTracker._ttChatFrameUtilInsertLinkWrapped then
        TaskTracker._ttChatFrameUtilInsertLinkWrapped = true
        local orig = ChatFrameUtil.InsertLink
        ChatFrameUtil.InsertLink = function(link, ...)
            if link and tryInsertLinkIntoTaskTracker(link) then
                return
            end
            return orig(link, ...)
        end
    end
end

TaskTracker.EnsureLinkInsertHooks()
C_Timer.After(0, TaskTracker.EnsureLinkInsertHooks)
C_Timer.After(1, TaskTracker.EnsureLinkInsertHooks)

