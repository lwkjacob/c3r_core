-- Transfer bridge (server): reading what another phone script left behind in the database, so a
-- server that switches to this phone keeps everyone's number, contacts, conversations, call history,
-- photos and notes. The other phone does not have to be running (it should not be): only its tables
-- have to still be there. They are read and never changed.
--
-- Each phone below is a "reader" written from that phone's own table definitions:
--   NPWD      github.com/project-error/npwd, import.sql
--   GCPhone   github.com/N3MTV/gcphone, base.sql
--
-- A reader answers in one neutral shape, with phone numbers exactly as the old phone stored them:
--   detect             a table only that phone has
--   contacts(id)       { { name, number } }
--   notes(id)          { { title, body } }
--   photos(id)         { url }
--   threads(id, num)   { { key, name?, members = { number }, msgs = { { from, text, at } } } }   oldest message first
--   calls(id, num)     { { key, caller, callee, at, duration, answered, hidden } }
-- `id` is the character (citizenid / ESX identifier), `num` their old number, `at` is seconds since 1970,
-- `key` names the thread or call the same way whichever of its two sides asks, so nothing is brought over twice.
-- Only free phones are covered, by the project owner's decision: no paid phone is read here.
-- To add another free one: add a reader below. server/transfer.lua does the rest.

Transfer = {}

-- Where the framework keeps its characters. ox_core runs NPWD itself and gives it this table and these columns;
-- ND_Core's are the ones its own guide to NPWD names (ndcore.dev/addons/phone); ND_Core 1.x has its own table.
local esx, ox, nd = Bridge.framework == 'esx', Bridge.framework == 'ox', Bridge.framework == 'nd'
local nd1 = Bridge.nd1 == true
local PLAYERS = esx and 'users' or ox and 'characters' or nd1 and 'characters' or nd and 'nd_characters' or 'players'
local ID = esx and 'identifier' or ox and 'charId' or nd1 and 'character_id' or nd and 'charid' or 'citizenid'
local NUMBER = ox and 'phoneNumber' or nd and not nd1 and 'phonenumber' or 'phone_number'

local function rows(sql, params)
    local ok, res = pcall(MySQL.query.await, sql, params or {})
    return ok and res or {}
end

local function exists(name) return #rows(("SHOW TABLES LIKE '%s'"):format(name)) > 0 end
local function column(tbl, col) return #rows(("SHOW COLUMNS FROM %s LIKE '%s'"):format(tbl, col)) > 0 end

--- A timestamp the old phone stored as text or a number, in seconds or milliseconds: as seconds.
local function seconds(v)
    v = tonumber(v) or 0
    return v > 100000000000 and math.floor(v / 1000) or math.floor(v)
end

local READERS = {}

-- NPWD ---------------------------------------------------------------------------------------------

READERS.npwd = {
    label = 'NPWD',
    detect = 'npwd_phone_contacts',
    contacts = function(id)
        local out = {}
        for i, r in ipairs(rows('SELECT display, number FROM npwd_phone_contacts WHERE identifier = ?', { id })) do out[i] = { name = r.display, number = r.number } end
        return out
    end,
    notes = function(id)
        local out = {}
        for i, r in ipairs(rows('SELECT title, content FROM npwd_notes WHERE identifier = ?', { id })) do out[i] = { title = r.title, body = r.content } end
        return out
    end,
    photos = function(id)
        local out = {}
        for i, r in ipairs(rows('SELECT image FROM npwd_phone_gallery WHERE identifier = ? ORDER BY id DESC LIMIT 300', { id })) do out[i] = r.image end
        return out
    end,
    threads = function(_, num)
        local out = {}
        for _, c in ipairs(rows([[SELECT c.id, c.label, c.is_group_chat FROM npwd_messages_conversations c
            JOIN npwd_messages_participants p ON p.conversation_id = c.id WHERE p.participant = ? LIMIT 60]], { num })) do
            local members, msgs = {}, {}
            for i, p in ipairs(rows('SELECT participant FROM npwd_messages_participants WHERE conversation_id = ?', { c.id })) do members[i] = p.participant end
            -- The newest 200, then put back in the order they were sent.
            local found = rows('SELECT message, author, UNIX_TIMESTAMP(createdAt) AS at FROM npwd_messages WHERE conversation_id = ? AND visible = 1 ORDER BY id DESC LIMIT 200', { tostring(c.id) })
            for i = #found, 1, -1 do msgs[#msgs + 1] = { from = found[i].author, text = found[i].message, at = seconds(found[i].at) } end
            local group = c.is_group_chat == 1 or c.is_group_chat == true
            out[#out + 1] = { key = 'c' .. c.id, name = group and c.label ~= '' and c.label or nil, members = members, msgs = msgs }
        end
        return out
    end,
    calls = function(_, num)
        local out = {}
        for i, r in ipairs(rows('SELECT id, transmitter, receiver, is_accepted, isAnonymous, start, `end` FROM npwd_calls WHERE transmitter = ? OR receiver = ? ORDER BY id DESC LIMIT 100', { num, num })) do
            local from, to = seconds(r.start), seconds(r['end'])
            local answered = r.is_accepted == 1 or r.is_accepted == true
            out[i] = { key = 'k' .. r.id, caller = r.transmitter, callee = r.receiver, at = from, duration = answered and math.max(0, to - from) or 0,
                answered = answered, hidden = r.isAnonymous == 1 or r.isAnonymous == true }
        end
        return out
    end,
}

-- GCPhone ------------------------------------------------------------------------------------------
-- It keeps one copy of each text and each call per phone. In a text's row `receiver` is the phone
-- the row belongs to, `transmitter` is the other party, and `owner` = 1 means this phone sent it.
-- In a call's row `incoming` = 1 means the row's phone placed the call (the name is misleading).

READERS.gcphone = {
    label = 'GCPhone',
    detect = 'phone_users_contacts',
    contacts = function(id)
        local out = {}
        for i, r in ipairs(rows('SELECT display, number FROM phone_users_contacts WHERE identifier = ?', { id })) do out[i] = { name = r.display, number = r.number } end
        return out
    end,
    notes = function() return {} end,
    photos = function() return {} end,
    threads = function(_, num)
        -- Another phone uses the name phone_messages for a different table: make sure this is GCPhone's.
        if not column('phone_messages', 'transmitter') then return {} end
        local found = rows('SELECT transmitter, message, UNIX_TIMESTAMP(time) AS at, owner FROM phone_messages WHERE receiver = ? ORDER BY id DESC LIMIT 2000', { num })
        local out, by = {}, {}
        for i = #found, 1, -1 do
            local r = found[i]
            local t = by[r.transmitter]
            if not t then
                local a, b = num, r.transmitter
                if b < a then a, b = b, a end
                t = { key = 'p' .. a .. '|' .. b, members = { num, r.transmitter }, msgs = {} }
                by[r.transmitter] = t
                out[#out + 1] = t
            end
            if #t.msgs < 200 then t.msgs[#t.msgs + 1] = { from = tonumber(r.owner) == 1 and num or r.transmitter, text = r.message, at = seconds(r.at) } end
        end
        return out
    end,
    calls = function(_, num)
        if not column('phone_calls', 'incoming') then return {} end
        local out = {}
        for _, r in ipairs(rows('SELECT num, incoming, UNIX_TIMESTAMP(time) AS at, accepts FROM phone_calls WHERE owner = ? ORDER BY id DESC LIMIT 100', { num })) do
            local placed = tonumber(r.incoming) == 1
            local caller, callee, at = placed and num or r.num, placed and r.num or num, seconds(r.at)
            -- ponytail: the two phones' rows of one call are matched by its second. Written a second apart, the call
            -- shows twice in the log. Match within a few seconds if anyone ever notices.
            out[#out + 1] = { key = ('k%s|%s|%d'):format(caller, callee, at), caller = caller, callee = callee, at = at, duration = 0, answered = tonumber(r.accepts) == 1 }
        end
        return out
    end,
}

Transfer.readers = READERS

-- Which phone, and whose number ----------------------------------------------------------------------

local ORDER = { 'npwd', 'gcphone' }
local reader, name, numberSql, reserved

--- The old phone found in the database: its reader and its name, or nil. Worked out once.
function Transfer.source()
    if reader ~= nil then return reader or nil, name end
    reader = false
    local want = Config.transfer
    if want == 'none' or Bridge.framework == 'standalone' then return nil end
    for _, key in ipairs(ORDER) do
        if (want == 'auto' or want == key) and exists(READERS[key].detect) then
            reader, name = READERS[key], key
            break
        end
    end
    if not reader then return nil end

    -- Both phones add a phone_number column to the framework's player table. On QBCore, NPWD is often
    -- run through an integration that leaves the number where QBCore itself keeps it, in charinfo.
    if column(PLAYERS, NUMBER) then
        numberSql = NUMBER
    elseif not esx and not ox and not nd then
        numberSql = "JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone'))"
    else
        reader = false
        return nil
    end
    -- Every number the old phone gave out stays with its character, including the ones who have not
    -- been back yet: none of them may be handed to someone new in the meantime.
    reserved = {}
    for _, r in ipairs(rows(('SELECT %s AS number FROM %s'):format(numberSql, PLAYERS))) do
        local n = Util.number(r.number)
        if n then reserved[n] = true end
    end
    return reader, name
end

--- The number a character had on the old phone, exactly as stored there. Nil if they had none.
function Transfer.old(identifier)
    if not Transfer.source() then return nil end
    local r = rows(('SELECT %s AS number FROM %s WHERE %s = ? LIMIT 1'):format(numberSql, PLAYERS, ID), { identifier })[1]
    return r and r.number ~= '' and r.number or nil
end

--- What the old phone knew a character as. Nearly everywhere that is the character itself. On ND_Core, NPWD is set
--- up to know players by the `identifier` column (their licence), which all of a player's characters share.
function Transfer.owner(identifier)
    if not nd or nd1 then return identifier end
    local r = rows('SELECT identifier FROM nd_characters WHERE charid = ? LIMIT 1', { tonumber(identifier) })[1]
    return r and r.identifier or identifier
end

--- Is this number spoken for by someone's old phone?
function Transfer.reserved(number)
    return Transfer.source() ~= nil and reserved[number] == true
end

--- How many numbers are being kept for their owners (for the start-up report).
function Transfer.kept()
    local n = 0
    for _ in pairs(Transfer.source() and reserved or {}) do n = n + 1 end
    return n
end
