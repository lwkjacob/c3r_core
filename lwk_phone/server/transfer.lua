-- Transfer: bringing a player's old phone across, once, when they set this one up.
--
-- config/bridge/transfer.lua reads the old phone. This file decides who gets what and writes it:
--   - The number carries over by itself (see allocate in server/main.lua), whatever the player chooses.
--   - Contacts, notes and photos are private to one phone, so they are simply added to it.
--   - A conversation or a call belongs to two people. It is brought over whole the first time either of
--     them transfers, and remembered in lwk_phone_imported so the other does not bring it over again.
-- A phone is asked once: its answer is kept under the phone's `transfer` key.

local found = {}   -- number -> what transfer.check gathered, kept for transfer.run

local function link(v) return type(v) == 'string' and #v <= 400 and v:match('^https://[%w%.%-]+/%S+$') and v or nil end

local PICTURES = { png = true, jpg = true, jpeg = true, webp = true, gif = true }

--- A text that is nothing but a link to a picture, on a host this server allows media from.
local function picture(text)
    return Util.url(text) ~= nil and PICTURES[(text:lower():match('%.(%a+)$')) or ''] == true
end

--- Everything the old phone holds for the character with this phone, or nil when there is nothing to bring.
local function gather(src, number)
    local reader, name = Transfer.source()
    if not reader or Phone.get(number, 'transfer') then return nil end
    local id = Bridge.identifier(src)
    local old = Transfer.old(id)
    -- Only the phone that carries the old number takes the old phone's contents.
    if not old or Util.number(old) ~= number then return nil end
    local ok, data = pcall(function()
        local who = Transfer.owner(id)   -- contacts, notes and photos are kept under this; texts and calls under the number
        return {
            source = name, label = reader.label, old = old,
            contacts = reader.contacts(who), notes = reader.notes(who), photos = reader.photos(who),
            threads = reader.threads(who, old), calls = reader.calls(who, old),
        }
    end)
    if not ok then
        print(('^1[lwk_phone] reading the old %s phone failed: %s^0'):format(name, data))
        return nil
    end
    if #data.contacts + #data.notes + #data.photos + #data.threads + #data.calls == 0 then return nil end
    return data
end

--- Has this already been brought over (by the other person in it)? Claims it if not.
local function claim(source, ref)
    return MySQL.update.await('INSERT IGNORE INTO lwk_phone_imported (source, ref) VALUES (?, ?)', { source, ref }) > 0
end

local function thread(source, t)
    local members, seen = {}, {}
    for _, raw in ipairs(t.members) do
        local n = Util.number(raw)
        if n and not seen[n] then
            seen[n] = true
            members[#members + 1] = n
        end
    end
    if #members < 2 or #t.msgs == 0 or not claim(source, 't:' .. t.key) then return end
    local ch = #members == 2 and Messages.pair('sms', members[1], members[2]) or Messages.create('sms', members, Util.text(t.name, 1, 40))
    local last = 0
    for _, m in ipairs(t.msgs) do
        local from, text = Util.number(m.from), Util.text(m.text, 1, 1000)
        if from and text then
            local body = picture(text) and { pic = text } or { text = text }
            -- (1000.0, not 1000: the test VM's whole numbers are 32-bit, and a time in milliseconds does not fit one.)
            local at = m.at * 1000.0
            last = math.max(last, at)
            MySQL.insert.await('INSERT INTO lwk_phone_msgs (channel, sender, body, created) VALUES (?, ?, ?, ?)', { ch, from, json.encode(body), at })
        end
    end
    if last > 0 then MySQL.update.await('UPDATE lwk_phone_channels SET updated = ? WHERE id = ?', { last, ch }) end
end

local function call(source, c)
    local caller, callee = Util.number(c.caller), Util.number(c.callee)
    if not caller or not callee or not claim(source, c.key) then return end
    MySQL.insert.await('INSERT INTO lwk_phone_calls (caller, callee, video, hidden, answered, duration, created) VALUES (?, ?, 0, ?, ?, ?, ?)',
        { caller, callee, c.hidden and 1 or 0, c.answered and 1 or 0, c.duration or 0, c.at * 1000.0 })
end

--- Add to one of the phone's own lists, newest first, keeping it within what the phone may store.
local function add(number, key, items, cap)
    if #items == 0 then return nil end
    local list = Phone.get(number, key) or {}
    for _, item in ipairs(list) do items[#items + 1] = item end
    while #items > 1 and #json.encode(items) > cap do table.remove(items) end
    Phone.set(number, key, items)
    return items
end

--- Is there an old phone to bring across? Answers what was found, so setup can offer it.
RPC['transfer.check'] = function(src, number)
    local data = gather(src, number)
    found[number] = data
    if not data then return Phone.ok({ found = false }) end
    return Phone.ok({ found = true, from = data.label, counts = {
        contacts = #data.contacts, threads = #data.threads, calls = #data.calls, photos = #data.photos, notes = #data.notes,
    } })
end

--- Bring it across. Answers the lists that changed, for the phone to show at once.
RPC['transfer.run'] = function(src, number)
    local data = found[number] or gather(src, number)
    found[number] = nil
    if not data then return Phone.fail(L('err_generic')) end
    -- Marked first: a transfer that fails halfway is not offered again and run on top of itself.
    Phone.set(number, 'transfer', 'done')

    local stamp, contacts, notes, photos, known = Phone.now() * 1000, {}, {}, {}, {}
    for i, c in ipairs(data.contacts) do
        local n = Util.number(c.number)
        if n and not known[n] then
            known[n] = true
            contacts[#contacts + 1] = { id = stamp + i, name = Util.text(c.name, 1, 64) or n, number = n }
        end
    end
    for i, n in ipairs(data.notes) do
        notes[#notes + 1] = { id = stamp + 10000 + i, title = Util.text(n.title, 1, 120) or '', body = Util.text(n.body, 0, 4000) or '', time = Phone.now() }
    end
    for i, url in ipairs(data.photos) do
        if link(url) then photos[#photos + 1] = { id = stamp + 20000 + i, seed = url, time = Phone.now() - i * 1000 } end
    end
    for _, t in ipairs(data.threads) do thread(data.source, t) end
    for _, c in ipairs(data.calls) do call(data.source, c) end

    Phone.log(('**transfer** %s brought %d contacts, %d conversations, %d photos from %s'):format(number, #contacts, #data.threads, #photos, data.label))
    return Phone.ok({
        contacts = add(number, 'contacts', contacts, 80000), notes = add(number, 'notes', notes, 80000), photos = add(number, 'photos', photos, 160000),
        chats = Messages.chats(number), calls = Calls.log(number),
    })
end

--- "Start fresh": the number stays, the rest is left behind, and setup does not ask again.
RPC['transfer.skip'] = function(_, number)
    found[number] = nil
    Phone.set(number, 'transfer', 'skipped')
    return Phone.ok()
end

AddEventHandler('lwk_phone:dropped', function(_, number) found[number] = nil end)
