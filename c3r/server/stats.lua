--[[
    c3r — server: what each officer has done, all-time, by licence. Counted as it happens (Stats.add), not from
    reports, and kept in memory until the next write: every 60 s and on a resource stop. Writes are `+ n`, so they
    can't overwrite each other; a crash loses a minute at most, and a write that fails is tried again next time.
]]

Stats = {}

local Pending = {} -- [license] = { name, [column] = n }: not written yet
local OnDuty = {}  -- [src] = { license, name, since }: time so far not in Pending

local function who(src)
    local o = OnDuty[src]
    if o then return o.license, o.name end
    local name = tostring(GetPlayerName(src) or 'Officer'):gsub('%c', '')
    local id = GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'license')
    return id or ('player:' .. name), name
end

local function add(license, name, stat, n)
    local p = Pending[license] or {}
    Pending[license], p.name = p, name
    p[stat] = (p[stat] or 0) + n
end

-- Who an officer is, to credit them later even if they've left by then.
function Stats.officer(src)
    local license, name = who(src)
    return { src = src, license = license, name = name }
end

function Stats.credit(officer, stat)
    add(officer.license, officer.name, stat, 1)
    TriggerEvent('c3r:stat', officer.src, stat, 1)
end

function Stats.add(src, stat) Stats.credit(Stats.officer(src), stat) end

local function clock(o, now)
    if now > o.since then
        add(o.license, o.name, 'seconds', now - o.since)
        o.since = now
    end
end

-- wait: waits on SQL, so a failed write is kept for next time and a read straight after sees it (in a thread).
-- Without, it can run anywhere, a resource stopping too.
local function flush(wait)
    local now = os.time()
    for _, o in pairs(OnDuty) do clock(o, now) end
    local batch = Pending
    Pending = {}
    for license, p in pairs(batch) do
        local ok, err = pcall(Db.addStats, license, p, now, wait)
        if not ok then
            print('[c3r] could not save officer stats: ' .. tostring(err))
            for stat, n in pairs(p) do if stat ~= 'name' then add(license, p.name, stat, n) end end
        end
    end
end

local function tick()
    SetTimeout(60000, function()
        CreateThread(function()
            flush(true)
            tick()
        end)
    end)
end
tick()

-- (After the stop and the call have ended: this file loads last, so what they count still knows who this is.)
AddEventHandler('c3r:duty', function(src, on)
    if on then
        local license, name = who(src)
        OnDuty[src] = { license = license, name = name, since = os.time() }
    elseif OnDuty[src] then
        clock(OnDuty[src], os.time())
        OnDuty[src] = nil
    end
end)

AddEventHandler('c3r:calloutEnded', function(src, completed)
    if completed then Stats.add(src, 'callouts') end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then flush() end
end)

-- A row as it goes out: never the licence.
local function public(row, me)
    local out = { name = row.name, you = row.license == me or nil }
    for _, stat in ipairs(Db.STATS) do out[stat] = tonumber(row[stat]) or 0 end
    return out
end

local function answer(cb, fn)
    CreateThread(function()
        local ok, r = pcall(fn)
        if not ok then print('[c3r] ' .. tostring(r)) end
        cb(ok and r or nil) -- always answer: an MDT screen is waiting on this
    end)
end

-- cb(totals | nil). officer = their server id, or their licence.
exports('getOfficerStats', function(officer, cb)
    answer(cb, function()
        flush(true)
        local license = type(officer) == 'string' and officer or (who(tonumber(officer)))
        local row = Db.officer(license)
        return row and public(row)
    end)
end)

-- cb({ totals, ... }), most time on duty first. src, if given, has their own row marked (you = true).
exports('getStatsBoard', function(src, cb)
    answer(cb, function()
        flush(true)
        local me = tonumber(src) and (who(tonumber(src)))
        local out = {}
        for _, row in ipairs(Db.officers()) do out[#out + 1] = public(row, me) end
        return out
    end)
end)

-- A leading = + - @ would be a formula in a spreadsheet, and a player picks their own name.
local function cell(v)
    v = tostring(v)
    if v:match('^[=+%-@\t\r]') then v = "'" .. v end
    return '"' .. v:gsub('"', '""') .. '"'
end

-- Console: stats.csv in the c3r folder.
RegisterCommand('c3rstats', function(source)
    if source ~= 0 then return end
    CreateThread(function()
        flush(true)
        local lines = { 'name,' .. table.concat(Db.STATS, ',') }
        local rows = Db.officers()
        for _, row in ipairs(rows) do
            local line = { cell(row.name) }
            for _, stat in ipairs(Db.STATS) do line[#line + 1] = tostring(tonumber(row[stat]) or 0) end
            lines[#lines + 1] = table.concat(line, ',')
        end
        local saved = SaveResourceFile(GetCurrentResourceName(), 'stats.csv', table.concat(lines, '\n') .. '\n', -1)
        print(saved and ('[c3r] %d officers written to stats.csv'):format(#rows) or '[c3r] could not write stats.csv')
    end)
end, true)
