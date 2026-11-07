-- Core/Share.lua
-- Import / export serialized groups and tasks (share between accounts)

TaskTracker = TaskTracker or {}

TaskTracker.SHARE_MAGIC = "TASKTRACKER_SHARE_V1"
TaskTracker.SHARE_MAGIC_V1 = TaskTracker.SHARE_MAGIC
TaskTracker.SHARE_MAGIC_V2 = "TASKTRACKER_SHARE_V2:"
TaskTracker.SHARE_VERSION = 1

local MAGIC_V1 = TaskTracker.SHARE_MAGIC_V1
local MAGIC_V2 = TaskTracker.SHARE_MAGIC_V2

local trim = TaskTracker.Trim

--- Deep copy plain tables; skip id, _tt* cache keys, and registry rows.
local function deepcopy_table(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local c = {}
    seen[t] = c
    for k, v in pairs(t) do
        if type(k) == "string" and k:sub(1, 4) == "_tt" then
            -- skip runtime cache
        elseif type(v) == "table" then
            c[k] = deepcopy_table(v, seen)
        else
            c[k] = v
        end
    end
    return c
end

local function copy_export_node(n)
    if type(n) ~= "table" then return nil end
    if n.type == "registryEntry" then return nil end
    if n.type ~= "group" and n.type ~= "task" then return nil end
    local o = {}
    for k, v in pairs(n) do
        if type(k) ~= "string" then
            -- skip
        elseif k:sub(1, 4) == "_tt" or k == "id"
            or k == "liveShareId" or k == "liveShareRole" or k == "liveShareTo"
            or k == "liveShareOwner" or k == "liveShareRev" or k == "liveShareRealm"
            or k == "liveShareReceivedAt" or k == "liveShareCharKey"
            or k == "liveShareByChar"
            or k == "liveShareSelfAdded" or k == "liveSharePeerAdded"
            or k == "liveShareSentCount" or k == "liveShareCountEpoch"
            or k == "liveShareAddGen" or k == "liveSharePersonal"
            or k == "liveSharePeriod" or k == "shareWeek"
            or k == "shareSelfAdded" or k == "shareCountEpoch" then
            -- skip
        elseif k == "children" and n.type == "group" and type(v) == "table" then
            o.children = {}
            for _, ch in ipairs(v) do
                local cc = copy_export_node(ch)
                if cc then
                    table.insert(o.children, cc)
                end
            end
        elseif type(v) == "table" then
            o[k] = deepcopy_table(v)
        else
            o[k] = v
        end
    end
    return o
end

local function normalize_exported_task(n)
    if type(n) ~= "table" or n.type ~= "task" then return end
    n.done = false
    n.taskCount = 0
    n.doneOverride = nil
    n.taskUserValue = nil
    n.liveShareTwoWay = nil
    n.liveShareCharKey = nil
    n.liveShareByChar = nil
    n.liveShareSelfAdded = nil
    n.liveSharePeerAdded = nil
    n.liveShareSentCount = nil
    n.liveShareCountEpoch = nil
    n.shareSelfAdded = nil
    n.shareCountEpoch = nil
    n.liveSharePeriod = nil
    n.shareWeek = nil
    if type(n.advanced) == "table" then
        n.advanced.questPeriodBaseline = nil
        n.advanced.questPeriodTurnIns = nil
        n.advanced.questPeriodRepeatCounts = nil
        n.advanced.questPeriodBaselineFrozen = nil
    end
    if type(n.subtext) == "table" then
        n.subtext.lifetimeKills = nil
        n.subtext.goldPeriodCopper = nil
    end
    if type(n.extraGoals) == "table" then
        for i = 1, #n.extraGoals do
            local g = n.extraGoals[i]
            if type(g) == "table" then
                g.done = false
                g.taskCount = 0
                g.doneOverride = nil
                g.taskUserValue = nil
                if type(g.advanced) == "table" then
                    g.advanced.goldAutoCopper = nil
                    g.advanced.itemAutoCount = nil
                    g.advanced.weekStartAchTotal = nil
                    g.advanced.weekStartRepValue = nil
                    g.advanced.questWeekStartComplete = nil
                    g.advanced.questPeriodCredited = nil
                    g.advanced.questPeriodOrphanCredits = nil
                    g.advanced.questPeriodBaseline = nil
                    g.advanced.questPeriodTurnIns = nil
                    g.advanced.questPeriodRepeatCounts = nil
                    g.advanced.questPeriodBaselineFrozen = nil
                    g.advanced.mobAutoCount = nil
                    g.advanced.collectableInit = nil
                    g.advanced.collectableAutoCount = nil
                    g.advanced.collectableFishAttempts = nil
                    g.advanced.collectableCredited = nil
                end
            end
        end
    end
end

local function normalize_exported_tree(n)
    if type(n) ~= "table" then return end
    if n.type == "task" then
        normalize_exported_task(n)
    elseif n.type == "group" and n.children then
        for _, ch in ipairs(n.children) do
            normalize_exported_tree(ch)
        end
    end
end

local LUA_KEYWORD = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
    ["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["if"] = true,
    ["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
    ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
    ["while"] = true,
}

local function key_needs_brackets(k)
    if type(k) ~= "string" then return true end
    if LUA_KEYWORD[k] then return true end
    if not string.match(k, "^[%a_][%w_]*$") then return true end
    return false
end

local function serialize_value(val, depth)
    depth = (depth or 0) + 1
    if depth > 120 then
        error("serialize depth")
    end
    local ty = type(val)
    if ty == "nil" then
        return "nil"
    elseif ty == "number" then
        if val ~= val or val == math.huge or val == -math.huge then
            error("non-finite number")
        end
        return tostring(val)
    elseif ty == "boolean" then
        return val and "true" or "false"
    elseif ty == "string" then
        return string.format("%q", val)
    elseif ty == "table" then
        local keys = {}
        for k in pairs(val) do
            table.insert(keys, k)
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        local parts = { "{" }
        for _, k in ipairs(keys) do
            local v = val[k]
            local ks
            if type(k) == "number" and k == math.floor(k) and k >= 1 and k <= 2147483647 then
                ks = string.format("[%d]", k)
            elseif type(k) == "string" and not key_needs_brackets(k) then
                ks = k
            else
                ks = "[" .. serialize_value(k, depth) .. "]"
            end
            parts[#parts + 1] = ks .. "=" .. serialize_value(v, depth) .. ","
        end
        parts[#parts + 1] = "}"
        return table.concat(parts)
    end
    error("unsupported type: " .. ty)
end

local function validate_plain_value(v, depth)
    depth = (depth or 0) + 1
    if depth > 120 then return false end
    local ty = type(v)
    if ty == "table" then
        for k, ch in pairs(v) do
            local tk = type(k)
            if tk == "function" or tk == "userdata" or tk == "thread" then return false end
            if not validate_plain_value(ch, depth) then return false end
        end
        return true
    end
    if ty == "function" or ty == "userdata" or ty == "thread" then return false end
    return true
end

local function load_share_chunk(body)
    body = trim(body)
    if body == "" then return nil, "Empty data." end
    local chunk = "return " .. body
    local fn, err
    if loadstring then
        fn, err = loadstring(chunk, "@TaskTrackerShare")
    else
        fn, err = load(chunk, "@TaskTrackerShare", "t", {})
    end
    if not fn then return nil, err or "Could not parse export." end
    if setfenv then
        setfenv(fn, {})
    end
    local ok, data = pcall(fn)
    if not ok then return nil, data or "Could not read export." end
    if type(data) ~= "table" then return nil, "Invalid export format." end
    if not validate_plain_value(data, 0) then return nil, "Invalid export data." end
    return data, nil
end

local function encoding_util_available()
    local EU = C_EncodingUtil
    return EU and EU.CompressString and EU.DecompressString and EU.EncodeBase64 and EU.DecodeBase64
        and Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate ~= nil
end

local function compress_plain_export(plain)
    if not encoding_util_available() or type(plain) ~= "string" or plain == "" then
        return nil
    end
    local EU = C_EncodingUtil
    local method = Enum.CompressionMethod.Deflate
    local level
    if Enum.CompressionLevel then
        level = Enum.CompressionLevel.OptimizeForSize or Enum.CompressionLevel.Default
    end
    local ok, compressed
    if level ~= nil then
        ok, compressed = pcall(EU.CompressString, plain, method, level)
    else
        ok, compressed = pcall(EU.CompressString, plain, method)
    end
    if not ok or not compressed or compressed == "" then
        return nil
    end
    local ok2, b64 = pcall(EU.EncodeBase64, compressed)
    if not ok2 or type(b64) ~= "string" or b64 == "" then
        return nil
    end
    return MAGIC_V2 .. b64
end

local function decompress_to_plain_export(blob)
    if not encoding_util_available() or type(blob) ~= "string" or blob == "" then
        return nil, "Compressed format is not supported on this client."
    end
    blob = string.gsub(blob, "%s+", "")
    local EU = C_EncodingUtil
    local ok, bin = pcall(EU.DecodeBase64, blob)
    if not ok or type(bin) ~= "string" or bin == "" then
        return nil, "Could not decode export (base64)."
    end
    local ok2, plain = pcall(EU.DecompressString, bin, Enum.CompressionMethod.Deflate)
    if not ok2 or type(plain) ~= "string" or plain == "" then
        return nil, "Could not decompress export."
    end
    return plain, nil
end

function TaskTracker.DecodeShareExportString(text)
    if not text or text == "" then return nil, "Nothing to import." end
    text = trim(text)
    if TaskTracker.IsProfileExportString and TaskTracker.IsProfileExportString(text) then
        local chev = TaskTracker.RightChevronMarkup and TaskTracker.RightChevronMarkup(11) or ">"
        return nil, "That export is a profile. Import it under Options " .. chev .. " Profiles."
    end
    local v2i = string.find(text, MAGIC_V2, 1, true)
    if v2i then
        local b64 = trim(string.sub(text, v2i + #MAGIC_V2))
        local plain, err = decompress_to_plain_export(b64)
        if not plain then return nil, err end
        return load_share_chunk(plain)
    end
    local v1i = string.find(text, MAGIC_V1, 1, true)
    if not v1i then return nil, "Missing Task Tracker export header." end
    text = trim(string.sub(text, v1i + #MAGIC_V1))
    if string.sub(text, 1, 1) == "\n" then
        text = trim(string.sub(text, 2))
    end
    return load_share_chunk(text)
end

function TaskTracker.EncodeShareEnvelope(kind, payload)
    if kind ~= "task" and kind ~= "group" then return nil end
    if type(payload) ~= "table" then return nil end
    local env = { v = TaskTracker.SHARE_VERSION, kind = kind, payload = payload }
    local ok, plain = pcall(function()
        return serialize_value(env, 0)
    end)
    if not ok or type(plain) ~= "string" then return nil end
    local packed = compress_plain_export(plain)
    if packed then return packed end
    return MAGIC_V1 .. "\n" .. plain
end

local PROFILE_MAGIC = "TASKTRACKER_PROFILE_V1:"

function TaskTracker.EncodeProfileExport(payload)
    if type(payload) ~= "table" then return nil end
    local ok, plain = pcall(function()
        return serialize_value(payload, 0)
    end)
    if not ok or type(plain) ~= "string" then return nil end
    local packed = compress_plain_export(plain)
    if type(packed) == "string" and packed:sub(1, #MAGIC_V2) == MAGIC_V2 then
        return PROFILE_MAGIC .. packed:sub(#MAGIC_V2 + 1)
    end
    return PROFILE_MAGIC .. "\n" .. plain
end

function TaskTracker.DecodeProfileExportString(text)
    if not text or text == "" then return nil, "Nothing to import." end
    text = trim(text)
    if string.find(text, MAGIC_V1, 1, true) or string.find(text, MAGIC_V2, 1, true) then
        return nil, "That export is a task or group. Import it from the task."
    end
    local at = string.find(text, PROFILE_MAGIC, 1, true)
    if not at then
        return nil, "Missing Task Tracker profile header."
    end
    local rest = trim(string.sub(text, at + #PROFILE_MAGIC))
    local plain, err
    if rest:sub(1, 1) == "{" then
        plain = rest
    else
        plain, err = decompress_to_plain_export(rest)
        if not plain then return nil, err end
    end
    local data, loadErr = load_share_chunk(plain)
    if not data then return nil, loadErr end
    if data.kind ~= "profile" then
        return nil, "That export is not a profile."
    end
    return data, nil
end

--- Task export that keeps counts. Paste-share still uses ExportNodeToString, which clears progress.
function TaskTracker.ExportLiveShareTaskString(node)
    if not node or node.type ~= "task" then return nil end
    local p = copy_export_node(node)
    if not p then return nil end
    if node.liveShareTwoWay == true then
        p.shareSelfAdded = tonumber(node.liveShareSelfAdded) or 0
        p.shareCountEpoch = tonumber(node.liveShareCountEpoch) or 0
    end
    if node.reset == "weekly" and TaskTracker.GetResetTimes then
        local _, week = TaskTracker.GetResetTimes()
        week = tonumber(week)
        if week and week > 0 then
            p.shareWeek = week
        end
    end
    return TaskTracker.EncodeShareEnvelope("task", p)
end

function TaskTracker.DecodeLiveShareTaskString(text)
    local data, err = TaskTracker.DecodeShareExportString(text)
    if not data then return nil, err end
    if tonumber(data.v) ~= TaskTracker.SHARE_VERSION then
        return nil, "Unsupported export version."
    end
    local pl = data.payload
    if data.kind ~= "task" or type(pl) ~= "table" or pl.type ~= "task" or type(pl.name) ~= "string" then
        return nil, "Not a task."
    end
    if TaskTracker.DeepCopy then
        return TaskTracker.DeepCopy(pl)
    end
    return pl
end

function TaskTracker.PackShareValue(val)
    local ok, plain = pcall(function()
        return serialize_value(val, 0)
    end)
    if not ok or type(plain) ~= "string" or plain == "" then return nil end
    local packed = compress_plain_export(plain)
    if packed then return packed end
    return MAGIC_V1 .. "\n" .. plain
end

function TaskTracker.UnpackShareValue(text)
    return TaskTracker.DecodeShareExportString(text)
end

function TaskTracker.ExportNodeToString(node)
    if not node or type(node) ~= "table" then return nil end
    if node.type == "task" then
        local p = copy_export_node(node)
        if not p then return nil end
        normalize_exported_task(p)
        return TaskTracker.EncodeShareEnvelope("task", p)
    elseif node.type == "group" then
        local p = copy_export_node(node)
        if not p then return nil end
        normalize_exported_tree(p)
        return TaskTracker.EncodeShareEnvelope("group", p)
    end
    return nil
end

local function assign_new_ids(n)
    if type(n) ~= "table" then return end
    n.id = TaskTracker.GenerateUUID and TaskTracker.GenerateUUID() or tostring(GetTime() or 0)
    if n.type == "group" and n.children then
        for _, ch in ipairs(n.children) do
            assign_new_ids(ch)
        end
    end
end

local function finalize_imported_subtree(n)
    if type(n) ~= "table" then return end
    if n.type == "task" then
        if TaskTracker.IsTaskAccountWide and TaskTracker.IsTaskAccountWide(n) then
            n.ownerCharKey = nil
        elseif TaskTracker.EnsureTaskOwnerCharKey and TaskTracker.GetCharProgressKey then
            n.ownerCharKey = nil
            TaskTracker.EnsureTaskOwnerCharKey(n, TaskTracker.GetCharProgressKey())
        end
        if TaskTracker.SyncAdvancedTask then
            TaskTracker.SyncAdvancedTask(n)
        end
        if n.advanced and n.advanced.type == "collectable" and TaskTracker.UpdateCollectableFromQuestFlags then
            TaskTracker.UpdateCollectableFromQuestFlags(n)
        end
    elseif n.type == "group" and n.children then
        for _, ch in ipairs(n.children) do
            finalize_imported_subtree(ch)
        end
    end
end

local function validate_payload_shape(kind, pl)
    if type(pl) ~= "table" then return false end
    if kind == "task" then
        return pl.type == "task" and type(pl.name) == "string"
    elseif kind == "group" then
        return pl.type == "group" and type(pl.name) == "string" and type(pl.children) == "table"
    end
    return false
end

--- Returns inflated node (task or group tree), or nil and error string.
function TaskTracker.InflateShareEnvelope(data)
    if type(data) ~= "table" then return nil, "Invalid data." end
    if tonumber(data.v) ~= TaskTracker.SHARE_VERSION then
        return nil, "Unsupported export version."
    end
    local kind = data.kind
    if kind ~= "task" and kind ~= "group" then
        return nil, "Unknown export kind."
    end
    local pl = data.payload
    if not validate_payload_shape(kind, pl) then
        return nil, "Malformed task or group in export."
    end
    local root = deepcopy_table(pl)
    assign_new_ids(root)
    normalize_exported_tree(root)
    finalize_imported_subtree(root)
    return root, nil
end

--- Insert `newNode` as last child of parentID (root or group id).
function TaskTracker.InsertNodeAsLastChild(parentID, newNode)
    local parent = TaskTracker.FindNode(parentID)
    if not parent or (parent.type ~= "group" and parent.type ~= "root") then return false end
    parent.children = parent.children or {}
    table.insert(parent.children, newNode)
    if TaskTracker.InvalidateAdvancedTaskIndex then TaskTracker.InvalidateAdvancedTaskIndex() end
    if TaskTracker.RefreshCombatLogKillRegistration then TaskTracker.RefreshCombatLogKillRegistration() end
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
    return true
end

--- Insert `newNode` immediately after an existing sibling in the tree.
function TaskTracker.InsertNodeAfterSibling(newNode, afterSiblingId)
    if not newNode or not afterSiblingId then return false end
    local _, p, i = TaskTracker.FindNode(afterSiblingId)
    if not p or not i then return false end
    p.children = p.children or {}
    table.insert(p.children, i + 1, newNode)
    if TaskTracker.InvalidateAdvancedTaskIndex then TaskTracker.InvalidateAdvancedTaskIndex() end
    if TaskTracker.RefreshCombatLogKillRegistration then TaskTracker.RefreshCombatLogKillRegistration() end
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
    return true
end
