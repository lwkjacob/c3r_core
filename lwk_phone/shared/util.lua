-- Pure helpers shared by client and server. No natives in here: tests/util_spec.lua loads
-- this file in a plain Lua VM.

Util = {}

--- Canonical phone number, the form used as an id everywhere: digits only, and seven
--- digits read 555-0142. Returns nil for anything that is not a number.
function Util.number(input)
    if type(input) == 'number' then input = ('%.0f'):format(input) end
    if type(input) ~= 'string' then return nil end
    local digits = input:gsub('%D', '')
    if #digits < 3 or #digits > 11 then return nil end
    if #digits == 7 then return digits:sub(1, 3) .. '-' .. digits:sub(4) end
    return digits
end

--- A fresh number from the configured prefixes. `rand(n)` returns 1..n (math.random by default).
function Util.randomNumber(prefixes, digits, rand)
    rand = rand or math.random
    local out = prefixes[rand(#prefixes)]
    for _ = 1, digits do out = out .. tostring(rand(10) - 1) end
    return Util.number(out)
end

--- Trimmed string of min..max characters, or nil.
function Util.text(v, min, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('^%s+', ''):gsub('%s+$', '')
    if #v < min or #v > max then return nil end
    return v
end

--- Whole number in min..max, or nil. Accepts numeric strings.
function Util.int(v, min, max)
    v = tonumber(v)
    if not v or v ~= v or v % 1 ~= 0 or v < min or v > max then return nil end
    return math.floor(v)
end

--- Lower-case account name: letters, digits and underscore, 3-20 long. Or nil.
function Util.username(v)
    if type(v) ~= 'string' then return nil end
    v = v:lower()
    if not v:match('^[a-z0-9_]+$') or #v < 3 or #v > 20 then return nil end
    return v
end

--- The hosts pictures, video and audio may come from (the server sets this from Config.upload.hosts).
--- Empty means any host. A name also covers its subdomains: 'fivemanage.com' allows r2.fivemanage.com.
Util.hosts = {}

--- An https link we are willing to store and show, or nil.
function Util.url(v)
    if type(v) ~= 'string' or #v > 400 then return nil end
    local host = v:match('^https://([%w%.%-]+)/[%w%-%._~:/%?#%[%]@!%$&\'%(%)%*%+,;=%%]*$')
    if not host then return nil end
    if #Util.hosts == 0 then return v end
    host = host:lower()
    for _, allowed in ipairs(Util.hosts) do
        if host == allowed or host:sub(-#allowed - 1) == '.' .. allowed then return v end
    end
    return nil
end

--- The parts of a chat message the server keeps. Unknown fields are dropped, known ones
--- are type- and size-checked. Returns nil when nothing usable is left.
function Util.body(v)
    if type(v) ~= 'table' then return nil end
    local out = {
        text  = Util.text(v.text, 1, 1000),
        pic   = Util.url(v.pic),
        audio = Util.url(v.audio),
        loc   = Util.text(v.loc, 1, 64),
        voice = Util.int(v.voice, 1, 600),
        money = Util.int(v.money, 1, 100000000),
    }
    if out.loc then
        out.x, out.y = tonumber(v.x), tonumber(v.y)
        if not out.x or not out.y or out.x ~= out.x or out.y ~= out.y then out.x, out.y = nil, nil end
    end
    if next(out) == nil then return nil end
    return out
end

--- Hashtags in a post, lower-cased and de-duplicated: "#LSTraffic again #lstraffic" -> { '#lstraffic' }.
function Util.hashtags(text)
    local seen, out = {}, {}
    for tag in (text or ''):gmatch('#([%w_]+)') do
        tag = '#' .. tag:lower()
        if not seen[tag] then
            seen[tag] = true
            out[#out + 1] = tag
        end
    end
    return out
end

--- Token bucket: `capacity` actions at once, refilled at `perSecond`. Returns a function
--- that takes the current time in seconds and answers whether one more action is allowed.
function Util.bucket(capacity, perSecond)
    local tokens, last = capacity, nil
    return function(now)
        if last then tokens = math.min(capacity, tokens + (now - last) * perSecond) end
        last = now
        if tokens < 1 then return false end
        tokens = tokens - 1
        return true
    end
end

--- Is version `a` newer than `b`? Compares the numbers in each, so 'v1.10.0' is newer than '1.9.2'.
function Util.newer(a, b)
    local x, y = {}, {}
    for n in tostring(a):gmatch('%d+') do x[#x + 1] = tonumber(n) end
    for n in tostring(b):gmatch('%d+') do y[#y + 1] = tonumber(n) end
    for i = 1, math.max(#x, #y) do
        if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) > (y[i] or 0) end
    end
    return false
end

--- JSON text as a table. Anything that is not an object or a list (bad JSON, nothing at all) is an empty
--- table; a value that is a table already is handed straight back.
function Util.decode(v)
    if type(v) == 'table' then return v end
    local ok, t = pcall(json.decode, v or '')
    return ok and type(t) == 'table' and t or {}
end

--- '?,?,?' for an IN (...) clause.
function Util.marks(n)
    return ('?,'):rep(n):sub(1, -2)
end

-- Exports, and LB Phone compatibility ------------------------------------------------------------

--- Register an export under this resource's name and under 'lb-phone', so scripts and apps written
--- for LB Phone find it where they look (see client/compat.lua).
function Export(name, fn)
    exports(name, fn)
    AddEventHandler(('__cfx_export_lb-phone_%s'):format(name), function(setCB) setCB(fn) end)
end

--- LB exports with no counterpart here: they answer nil, and say so once each in the console.
function Util.stubs(names)
    for _, name in ipairs(names) do
        local told = false
        AddEventHandler(('__cfx_export_lb-phone_%s'):format(name), function(setCB)
            setCB(function()
                if not told then print(("[lwk_phone] an LB Phone app called exports['lb-phone']:%s, which this phone does not have"):format(name)) end
                told = true
            end)
        end)
    end
end

--- This phone's saved settings in the shape LB Phone hands to apps.
function Util.appSettings(s)
    return {
        airplaneMode = s.airplane == true, streamerMode = s.streamer == true, doNotDisturb = s.dnd == true,
        display = { theme = s.dark == false and 'light' or 'dark', size = s.size or 1, brightness = s.brightness or 1 },
        sound = { volume = s.volume or 0.5, silent = s.silent == true, ringtone = s.ringtone, texttone = s.texttone },
        time = { twelveHourClock = s.clock24 ~= true },
        phone = { showCallerId = s.hideCallerId ~= true },
        security = { pinCode = (s.passcode or '') ~= '', faceId = s.faceId == true },
        wallpaper = { background = s.wallpaper },
    }
end
