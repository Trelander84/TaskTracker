-- Core/ResetSchedule.lua
-- Daily / weekly period boundaries for TaskTracker resets.
-- Preset "server" uses Blizzard C_DateAndTime (matches the connected realm, DST-aware).
-- US / EU presets use the wall-clock schedules documented in Options.
-- "custom" uses stored hour/minute + timezone (Pacific, Eastern, CET, or UTC).

TaskTracker = TaskTracker or {}

local RESET_PRESETS = {
    server = true,
    us     = true,
    eu     = true,
    custom = true,
}

local TZ_KEYS = {
    Pacific = true,
    Eastern = true,
    CET     = true,
    UTC     = true,
}

-- Cached GetResetTimes (seconds-level; invalidated from Options when the schedule changes).
local cacheAt, cacheDaily, cacheWeekly

function TaskTracker.InvalidateResetTimesCache()
    cacheAt, cacheDaily, cacheWeekly = nil, nil, nil
end

-- ── US / EU DST (post-2007 US rules; EU last-Sunday Mar/Oct at 01:00 UTC) ──

local function isLeapYear(y)
    if y % 400 == 0 then return true end
    if y % 100 == 0 then return false end
    return y % 4 == 0
end

local function daysInMonth(y, m)
    if m == 2 then return isLeapYear(y) and 29 or 28 end
    local t = { 31, 0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    return t[m]
end

-- Days from 1970-01-01 (civil calendar, UTC date) — Howard Hinnant algorithm.
local function days_from_civil(y, m, d)
    if m <= 2 then
        y = y - 1
        m = m + 12
    end
    local era = math.floor((y >= 0 and y or y - 399) / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m - 3) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function ymdHmsToUnixUTC(y, m, d, hour, min, sec)
    return days_from_civil(y, m, d) * 86400 + hour * 3600 + min * 60 + sec
end

local function utcWeekdaySun1(utc)
    return date("!*t", utc).wday
end

local function nthSundayOfMonth(y, mon, n)
    local count = 0
    for d = 1, daysInMonth(y, mon) do
        local tnoon = ymdHmsToUnixUTC(y, mon, d, 12, 0, 0)
        if utcWeekdaySun1(tnoon) == 1 then
            count = count + 1
            if count == n then return d end
        end
    end
    return nil
end

local function lastSundayOfMonth(y, mon)
    for d = daysInMonth(y, mon), 1, -1 do
        local tnoon = ymdHmsToUnixUTC(y, mon, d, 12, 0, 0)
        if utcWeekdaySun1(tnoon) == 1 then return d end
    end
    return nil
end

local function usSpringUtc(y)
    local d = nthSundayOfMonth(y, 3, 2)
    if not d then return 0 end
    -- 02:00 Eastern standard → 07:00 UTC
    return ymdHmsToUnixUTC(y, 3, d, 7, 0, 0)
end

local function usFallUtc(y)
    local d = nthSundayOfMonth(y, 11, 1)
    if not d then return 0 end
    -- 02:00 Eastern daylight → 06:00 UTC
    return ymdHmsToUnixUTC(y, 11, d, 6, 0, 0)
end

local function easternOffsetSec(utc)
    local d = date("!*t", utc)
    local y = d.year
    local sp = usSpringUtc(y)
    local fa = usFallUtc(y)
    if utc >= sp and utc < fa then
        return -4 * 3600
    end
    return -5 * 3600
end

local function pacificOffsetSec(utc)
    return easternOffsetSec(utc) - 3 * 3600
end

local function euSpringUtc(y)
    local d = lastSundayOfMonth(y, 3)
    if not d then return 0 end
    return ymdHmsToUnixUTC(y, 3, d, 1, 0, 0)
end

local function euFallUtc(y)
    local d = lastSundayOfMonth(y, 10)
    if not d then return 0 end
    return ymdHmsToUnixUTC(y, 10, d, 1, 0, 0)
end

local function euCentralOffsetSec(utc)
    local d = date("!*t", utc)
    local y = d.year
    local sp = euSpringUtc(y)
    local fa = euFallUtc(y)
    if utc >= sp and utc < fa then
        return 2 * 3600
    end
    return 1 * 3600
end

local function utcOffsetSec()
    return 0
end

local function offsetFnForTzKey(tzKey)
    if tzKey == "Pacific" then return pacificOffsetSec end
    if tzKey == "Eastern" then return easternOffsetSec end
    if tzKey == "CET" then return euCentralOffsetSec end
    return utcOffsetSec
end

-- Add signed seconds to a UTC calendar instant (UTC ymdhms + delta); returns local civil y,m,d,wday,h,mi,s.
local function addSecondsToYmdHms(y, m, d, h, mi, s, addSec)
    s = s + addSec
    while s >= 60 do s = s - 60 mi = mi + 1 end
    while s < 0 do s = s + 60 mi = mi - 1 end
    while mi >= 60 do mi = mi - 60 h = h + 1 end
    while mi < 0 do mi = mi + 60 h = h - 1 end
    while h >= 24 do h = h - 24 d = d + 1 end
    while h < 0 do h = h + 24 d = d - 1 end
    local dim = daysInMonth(y, m)
    while d > dim do
        d = d - dim
        m = m + 1
        if m > 12 then m = 1 y = y + 1 end
        dim = daysInMonth(y, m)
    end
    while d < 1 do
        m = m - 1
        if m < 1 then m = 12 y = y - 1 end
        dim = daysInMonth(y, m)
        d = d + dim
    end
    local wday = utcWeekdaySun1(ymdHmsToUnixUTC(y, m, d, 12, 0, 0))
    return y, m, d, wday, h, mi, s
end

local function utcToLocalCivil(utc, offsetFn)
    local off = offsetFn(utc)
    local d = date("!*t", utc)
    return addSecondsToYmdHms(d.year, d.month, d.day, d.hour, d.min, d.sec, off)
end

-- Latest minute start t <= now where local civil (in offsetFn zone) matches hour/minute (second ignored).
local function findLastDailyBoundary(now, hour, minute, offsetFn)
    local start = math.floor(now / 60) * 60
    for i = 0, 4500 do
        local t = start - i * 60
        if t > now + 60 then break end
        local _, _, _, _, H, M = utcToLocalCivil(t, offsetFn)
        if H == hour and M == minute then
            return t
        end
    end
    return start - 86400
end

-- Latest minute start t <= now where local wday/H/M match (Lua wday: 1=Sun .. 7=Sat).
local function findLastWeeklyBoundary(now, targetWday, hour, minute, offsetFn)
    local start = math.floor(now / 60) * 60
    for i = 0, 13000 do
        local t = start - i * 60
        if t > now + 60 then break end
        local _, _, _, wday, H, M = utcToLocalCivil(t, offsetFn)
        if wday == targetWday and H == hour and M == minute then
            return t
        end
    end
    return start - 604800
end

local function resetTimesFromServer(now)
    local CDT = C_DateAndTime
    if not CDT or not CDT.GetSecondsUntilDailyReset or not CDT.GetSecondsUntilWeeklyReset then
        return nil
    end
    local okD, secD = pcall(CDT.GetSecondsUntilDailyReset)
    local okW, secW = pcall(CDT.GetSecondsUntilWeeklyReset)
    if not okD or not okW or type(secD) ~= "number" or type(secW) ~= "number" then
        return nil
    end
    if secD < 0 or secD > 3 * 86400 or secW < 0 or secW > 14 * 86400 then
        return nil
    end
    local nextD = now + secD
    local nextW = now + secW
    return nextD - 86400, nextW - 604800
end

local function resetTimesUSPreset(now)
    -- Daily 08:00 US Pacific; weekly Tuesday 10:00 US Eastern (Lua wday Tue = 3).
    local daily = findLastDailyBoundary(now, 8, 0, pacificOffsetSec)
    local weekly = findLastWeeklyBoundary(now, 3, 10, 0, easternOffsetSec)
    return daily, weekly
end

local function resetTimesEUPreset(now)
    -- Daily 08:00 CET/CEST; weekly Wednesday 05:00 (Lua wday Wed = 4).
    local daily = findLastDailyBoundary(now, 8, 0, euCentralOffsetSec)
    local weekly = findLastWeeklyBoundary(now, 4, 5, 0, euCentralOffsetSec)
    return daily, weekly
end

local function resetTimesCustom(now)
    local db = TaskTrackerDB
    if not db then return resetTimesUSPreset(now) end
    local dh = math.max(0, math.min(23, math.floor(tonumber(db.resetCustomDailyHour) or 8)))
    local dmi = math.max(0, math.min(59, math.floor(tonumber(db.resetCustomDailyMinute) or 0)))
    local dtz = TZ_KEYS[db.resetCustomDailyTZ] and db.resetCustomDailyTZ or "Pacific"
    local wh = math.max(0, math.min(23, math.floor(tonumber(db.resetCustomWeeklyHour) or 10)))
    local wmi = math.max(0, math.min(59, math.floor(tonumber(db.resetCustomWeeklyMinute) or 0)))
    local ww = math.max(1, math.min(7, math.floor(tonumber(db.resetCustomWeeklyWday) or 3)))
    local wtz = TZ_KEYS[db.resetCustomWeeklyTZ] and db.resetCustomWeeklyTZ or "Eastern"
    local daily = findLastDailyBoundary(now, dh, dmi, offsetFnForTzKey(dtz))
    local weekly = findLastWeeklyBoundary(now, ww, wh, wmi, offsetFnForTzKey(wtz))
    return daily, weekly
end

--- Start timestamps (unix) of the current daily and weekly periods.
function TaskTracker.GetResetTimes()
    local now = time()
    if cacheAt and (now - cacheAt) < 12 and cacheDaily and cacheWeekly then
        return cacheDaily, cacheWeekly
    end

    local db = TaskTrackerDB
    local preset = (db and db.resetSchedulePreset) or "server"
    if not RESET_PRESETS[preset] then preset = "server" end

    local daily, weekly

    if preset == "server" then
        local a, b = resetTimesFromServer(now)
        if a and b then
            daily, weekly = a, b
        else
            daily, weekly = resetTimesUSPreset(now)
        end
    elseif preset == "us" then
        daily, weekly = resetTimesUSPreset(now)
    elseif preset == "eu" then
        daily, weekly = resetTimesEUPreset(now)
    else
        daily, weekly = resetTimesCustom(now)
    end

    cacheAt, cacheDaily, cacheWeekly = now, daily, weekly
    return daily, weekly
end
