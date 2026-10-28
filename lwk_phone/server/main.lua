-- Entry point: which phone each player is holding, the request dispatcher, and per-phone storage.
--
-- A phone is its number. Every table is keyed by number, never by player, so on unique-phone
-- servers the data follows the item. The UI reaches the server through one callback:
--   lwk_phone:rpc (name, data) -> RPC[name](src, number, data) -> { ok = true, ... } | { ok = false, error }
-- and the server reaches the UI with Phone.push(src or number, { action = ..., ... }).

Phone = {}
RPC = {}    -- name -> function(src, number, data) returning a result table
Apps = {}   -- app id -> function(src, number) returning the slices that app shows

local equipped = {}   -- src -> number
local byNumber = {}   -- number -> src
local buckets  = {}   -- src -> rate limiter for requests in general
local slow     = {}   -- src -> { request name -> its own, stricter limiter }
local busy     = {}   -- number -> true while one of that phone's requests is running
local flags    = {}   -- number -> { airplane, dnd, hideCallerId } (from the saved settings)

Util.hosts = Config.upload.hosts or {}

-- Requests that cost the server real work, or that land on someone else's screen, have a limit of
-- their own on top of the general one: { how many at once, how many more per second }.
local LIMITS = {
    load               = { 10, 1 },
    ['account.login']  = { 8, 0.1 },    -- checking a password is slow on purpose; this is also the guessing rate
    ['account.signup'] = { 6, 0.05 },   -- room to set up every social app on a new phone in one go
    ['post.create']    = { 5, 0.2 },    -- every phone showing that app reloads it
    ['upload']         = { 6, 0.5 },    -- each one is a file on the server owner's storage
    ['call.start']     = { 4, 0.25 },
    ['mail.send']      = { 5, 0.2 },
    ['company.text']   = { 3, 0.2 },
    ['wallet.request'] = { 3, 0.1 },
    ['share.send']     = { 5, 0.5 },
    ['transfer.check'] = { 4, 0.05 },   -- each one reads through another phone's tables
    ['transfer.run']   = { 2, 0.02 },
}

local function allowed(src, name)
    local now = GetGameTimer() / 1000
    buckets[src] = buckets[src] or Util.bucket(30, 6)
    if not buckets[src](now) then return false end
    local limit = LIMITS[name]
    if not limit then return true end
    slow[src] = slow[src] or {}
    slow[src][name] = slow[src][name] or Util.bucket(limit[1], limit[2])
    return slow[src][name](now)
end

function Phone.now() return os.time() * 1000 end

--- The token for the upload host, from config/keys.lua or the convar. '' when there is none.
function Phone.uploadToken()
    return Keys.fivemanage ~= '' and Keys.fivemanage or GetConvar('lwk_phone_fivemanage', '')
end
function Phone.number(src) return equipped[src] end
function Phone.source(number) return byNumber[number] end
function Phone.flags(number) return flags[number] or {} end
function Phone.online() return equipped end

function Phone.ok(t)
    t = t or {}
    t.ok = true
    return t
end

function Phone.fail(message)
    return { ok = false, error = message }
end

--- Send a message to a phone's UI. `target` is a player source or a phone number.
function Phone.push(target, msg)
    local src = type(target) == 'number' and target or byNumber[target]
    if src then TriggerClientEvent('lwk_phone:nui', src, msg) end
    return src ~= nil
end

--- Replace slices of the UI's state: Phone.patch(src, { wallet = {...} }).
function Phone.patch(target, slices)
    return Phone.push(target, { action = 'patch', data = slices })
end

--- A notification on the phone (banner, lock screen, Notification Center).
function Phone.notify(target, app, title, body)
    return Phone.push(target, { action = 'notify', app = app, title = title, body = body })
end

function Phone.log(text)
    local url = Keys.webhook ~= '' and Keys.webhook or GetConvar('lwk_phone_webhook', '')
    if url == '' then return end
    -- allowed_mentions: the text holds what players typed, and must not be able to ping @everyone.
    PerformHttpRequest(url, function() end, 'POST',
        json.encode({ username = 'Phone', content = text:sub(1, 1900), allowed_mentions = { parse = {} } }),
        { ['Content-Type'] = 'application/json' })
end

-- Storage --------------------------------------------------------------------------------
-- The UI owns the shape of its private data; the server stores each slice as the JSON text
-- it was sent and hands it back untouched. Keys and their size limits (bytes):

local SAVE = {
    contacts = 80000, notes = 80000, alarms = 8000, memos = 40000, photos = 160000, settings = 4000,
    apps = 2000, dock = 400, seenCalls = 40, setup = 10, playlists = 20000, worldClocks = 2000,
}

--- Decoded value of a key, or nil. Server-owned keys (wallet history, crypto) use this too.
function Phone.get(number, k)
    local raw = MySQL.scalar.await('SELECT v FROM lwk_phone_data WHERE phone = ? AND k = ?', { number, k })
    return raw and json.decode(raw) or nil
end

function Phone.set(number, k, value)
    MySQL.prepare.await('REPLACE INTO lwk_phone_data (phone, k, v) VALUES (?, ?, ?)', { number, k, json.encode(value) })
end

local function readFlags(number, raw)
    local ok, s = pcall(json.decode, raw or 'null')
    s = ok and type(s) == 'table' and s or {}
    flags[number] = { airplane = s.airplane == true, dnd = s.dnd == true, hideCallerId = s.hideCallerId == true }
end

RPC['save'] = function(_, number, data)
    local cap = SAVE[data.k]
    if not cap or type(data.v) ~= 'string' or #data.v > cap then return Phone.fail(L('err_too_big')) end
    if not pcall(json.decode, data.v) then return Phone.fail(L('err_generic')) end
    MySQL.prepare.await('REPLACE INTO lwk_phone_data (phone, k, v) VALUES (?, ?, ?)', { number, data.k, data.v })
    if data.k == 'settings' then readFlags(number, data.v) end
    return Phone.ok()
end

-- Which phone? -------------------------------------------------------------------------------

local function allocate(owner, name)
    -- Coming from another phone, a character keeps the number they had there (config/bridge/transfer.lua)...
    local old = Util.number(Transfer.old(owner))
    if old and not MySQL.scalar.await('SELECT 1 FROM lwk_phone_phones WHERE number = ?', { old }) then
        MySQL.insert.await('INSERT INTO lwk_phone_phones (number, owner, name) VALUES (?, ?, ?)', { old, owner, name })
        return old
    end
    for _ = 1, 40 do
        local number = Util.randomNumber(Config.numbers.prefixes, Config.numbers.digits)
        -- ...and nobody new is given a number that is waiting for its old owner.
        if not Transfer.reserved(number) and not MySQL.scalar.await('SELECT 1 FROM lwk_phone_phones WHERE number = ?', { number }) then
            MySQL.insert.await('INSERT INTO lwk_phone_phones (number, owner, name) VALUES (?, ?, ?)', { number, owner, name })
            return number
        end
    end
    error('no free phone numbers left: add prefixes or digits in Config.numbers')
end

--- The number of the phone `src` should be holding, or nil plus a reason.
--- `slot` is the inventory slot of the item just used, when there is one.
local function resolve(src, slot)
    local owner = Bridge.identifier(src)
    if not owner then return nil, 'not_ready' end
    local name = Bridge.name(src)

    if Inv.unique then
        local phones = Inv.phones(src)
        if #phones == 0 then return nil, 'no_phone' end
        local pick = phones[1]
        for _, p in ipairs(phones) do
            -- The item just used wins; otherwise keep whichever phone is already in hand.
            if slot and p.slot == slot then pick = p break end
            if not slot and p.number and p.number == equipped[src] then pick = p end
        end
        if not pick.number then
            pick.number = allocate(owner, name)
            if not Inv.stamp(src, pick.slot, pick.number, name) then return nil, 'no_phone' end
        end
        return pick.number
    end

    if Inv.required and #Inv.phones(src) == 0 then return nil, 'no_phone' end
    return MySQL.scalar.await('SELECT number FROM lwk_phone_phones WHERE owner = ? LIMIT 1', { owner }) or allocate(owner, name)
end

function Phone.drop(src)
    local number = equipped[src]
    if not number then return end
    TriggerEvent('lwk_phone:dropped', src, number)
    equipped[src], byNumber[number] = nil, nil
end

--- What the UI needs when a phone comes up: identity, saved data, conversations, config.
local function init(src, number)
    local kv, voicemail = {}, nil
    for _, row in ipairs(MySQL.query.await('SELECT k, v FROM lwk_phone_data WHERE phone = ?', { number })) do
        if SAVE[row.k] then kv[row.k] = row.v end
        -- Kept by the server (see server/calls.lua): the phone cannot write this one.
        if row.k == 'voicemail' then voicemail = json.decode(row.v) end
    end
    readFlags(number, kv.settings)

    local hidden = {}
    if not Bridge.has.money then hidden[#hidden + 1] = 'wallet' hidden[#hidden + 1] = 'crypto' end
    if not Bridge.has.vehicles then hidden[#hidden + 1] = 'garage' end
    if not Bridge.has.jobs then hidden[#hidden + 1] = 'services' end
    if Housing.kind() == 'none' then hidden[#hidden + 1] = 'home' end
    if #Config.music == 0 then hidden[#hidden + 1] = 'music' end
    if Bridge.has.money and not Config.crypto.enabled then hidden[#hidden + 1] = 'crypto' end

    local token = Phone.uploadToken()
    return {
        number = number,
        name = MySQL.scalar.await('SELECT name FROM lwk_phone_phones WHERE number = ?', { number }) or Bridge.name(src),
        kv = kv,
        chats = Messages.chats(number),
        calls = Calls.log(number),
        voicemail = voicemail or {},
        accounts = Social.sessions(number),
        hidden = hidden,
        locale = { ui = Locale.ui(), intl = Locale.intl() },
        config = {
            map = Config.map, places = Config.places, songs = Config.music, rtc = Config.rtc,
            upload = token ~= '', mailDomain = Config.mailDomain, licence = Config.licence, garage = Config.garage,
            unique = Inv.unique, admin = Bridge.isAdmin(src),
        },
    }
end

lib.callback.register('lwk_phone:load', function(src, slot)
    DB.wait()
    if not allowed(src, 'load') or not Bridge.ready(src) then return { error = 'not_ready' } end
    local number, reason = resolve(src, tonumber(slot))
    if not number then return { error = reason } end

    -- The same phone cannot be up on two players (duplicated items): the newer holder wins.
    local other = byNumber[number]
    if other and other ~= src then
        Phone.push(other, { action = 'unload' })
        Phone.drop(other)
    end
    if equipped[src] and equipped[src] ~= number then Phone.drop(src) end
    equipped[src], byNumber[number] = number, src

    MySQL.prepare.await('INSERT INTO lwk_phone_last (owner, number) VALUES (?, ?) ON DUPLICATE KEY UPDATE number = VALUES(number)',
        { Bridge.identifier(src), number })
    return init(src, number)
end)

--- Still holding the phone that is up? Checked before every request on unique-phone servers.
local function stillHeld(src, number)
    if not Inv.required then return true end
    for _, p in ipairs(Inv.phones(src)) do
        if not Inv.unique or p.number == number then return true end
    end
    return false
end

lib.callback.register('lwk_phone:rpc', function(src, name, data)
    local number = equipped[src]
    local fn = type(name) == 'string' and RPC[name]
    if not number or not fn then return Phone.fail(L('err_generic')) end

    if not allowed(src, name) then return Phone.fail(L('err_slow_down')) end
    if not stillHeld(src, number) then
        Phone.push(src, { action = 'unload' })
        Phone.drop(src)
        return Phone.fail(L('err_no_phone'))
    end

    -- Never the account requests: they carry passwords.
    if Config.debug then print(('[lwk_phone] %s %s %s'):format(number, name, name:find('^account%.') and '...' or json.encode(data))) end

    -- One request per phone at a time. A handler reads, waits for the database, then writes; two of
    -- them interleaved could sell the same coins twice or call the same vehicle out twice.
    -- (An upload waits on another server and touches nothing of the phone's, so it does not queue.)
    local queued = name ~= 'upload'
    if queued then
        while busy[number] do Wait(0) end
        busy[number] = true
    end
    local ok, result = pcall(fn, src, number, type(data) == 'table' and data or {})
    if queued then busy[number] = nil end
    if not ok then
        print(('^1[lwk_phone] %s failed: %s^0'):format(name, result))
        return Phone.fail(L('err_generic'))
    end
    return result or Phone.ok()
end)

--- Data for one app, fetched when it opens.
RPC['appData'] = function(src, number, data)
    local fn = Apps[data.app]
    return Phone.ok({ data = fn and fn(src, number) or {} })
end

RegisterNetEvent('lwk_phone:unload', function() Phone.drop(source) end)

AddEventHandler('playerDropped', function()
    Phone.drop(source)
    buckets[source], slow[source] = nil, nil
end)

Inv.onUse(function(src, slot)
    TriggerClientEvent('lwk_phone:use', src, slot)
end)

