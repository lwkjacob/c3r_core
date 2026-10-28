-- Conversations. One model serves texts, group texts, social DMs, anonymous channels and
-- match chats: a channel has members and messages. What differs is the member key:
--   texts and match chats   the phone number
--   social DMs, Shade       '<app>:<username>' (the account, so it follows the login, not the phone)

Messages = {}

--- Deliver a UI message to whoever is behind a member key right now.
local function push(member, msg)
    local app, user = member:match('^(%a+):(.+)$')
    if not app then return Phone.push(member, msg) end
    for src, number in pairs(Phone.online()) do
        if Social.user(number, app) == user then Phone.push(src, msg) end
    end
end
Messages.push = push

local function membersOf(ch)
    local out = {}
    for i, r in ipairs(MySQL.query.await('SELECT member FROM lwk_phone_members WHERE channel = ?', { ch })) do out[i] = r.member end
    return out
end

local function has(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

function Messages.create(kind, list, name)
    local ch = MySQL.insert.await('INSERT INTO lwk_phone_channels (kind, name, size, updated) VALUES (?, ?, ?, ?)', { kind, name, #list, Phone.now() })
    for _, m in ipairs(list) do MySQL.prepare.await('INSERT IGNORE INTO lwk_phone_members (channel, member) VALUES (?, ?)', { ch, m }) end
    return ch
end

--- The two-person channel between a and b, created on first use.
function Messages.pair(kind, a, b)
    return MySQL.scalar.await([[SELECT c.id FROM lwk_phone_channels c
        JOIN lwk_phone_members x ON x.channel = c.id AND x.member = ?
        JOIN lwk_phone_members y ON y.channel = c.id AND y.member = ?
        WHERE c.kind = ? AND c.size = 2 LIMIT 1]], { a, b, kind }) or Messages.create(kind, { a, b })
end

--- Store a message and mark it unread for everyone else. Returns it in the shape the UI uses.
function Messages.add(ch, sender, body)
    local now = Phone.now()
    local id = MySQL.insert.await('INSERT INTO lwk_phone_msgs (channel, sender, body, created) VALUES (?, ?, ?, ?)', { ch, sender, json.encode(body), now })
    MySQL.update.await('UPDATE lwk_phone_channels SET updated = ? WHERE id = ?', { now, ch })
    MySQL.update.await('UPDATE lwk_phone_members SET unread = unread + 1 WHERE channel = ? AND member <> ?', { ch, sender })
    body.id, body.time, body.from = id, now, sender
    return body
end

--- Every channel of `kind` that `member` is in, most recent first, with members and the last messages.
function Messages.list(kind, member, perChannel)
    local chans = MySQL.query.await([[SELECT c.id, c.name, c.size, m.unread, m.cleared FROM lwk_phone_members m
        JOIN lwk_phone_channels c ON c.id = m.channel
        WHERE m.member = ? AND c.kind = ? ORDER BY c.updated DESC LIMIT 40]], { member, kind })
    if #chans == 0 then return chans end

    local ids, byId = {}, {}
    for i, c in ipairs(chans) do
        ids[i], byId[c.id] = c.id, c
        c.members, c.msgs = {}, {}
    end
    local marks = Util.marks(#ids)
    for _, r in ipairs(MySQL.query.await(('SELECT channel, member FROM lwk_phone_members WHERE channel IN (%s)'):format(marks), ids)) do
        table.insert(byId[r.channel].members, r.member)
    end
    for _, r in ipairs(MySQL.query.await(([[SELECT id, channel, sender, body, created FROM (
            SELECT m.*, ROW_NUMBER() OVER (PARTITION BY channel ORDER BY id DESC) AS rn
            FROM lwk_phone_msgs m WHERE channel IN (%s)
        ) x WHERE rn <= %d ORDER BY id]]):format(marks, perChannel or 60), ids)) do
        -- Not the ones this member deleted (see msg.leave).
        if r.id > (byId[r.channel].cleared or 0) then
            local msg = json.decode(r.body) or {}
            msg.id, msg.time = r.id, r.created
            if r.sender == member then msg.me = true else msg.from = r.sender end
            table.insert(byId[r.channel].msgs, msg)
        end
    end
    -- A deleted conversation stays away until something new arrives in it.
    local out = {}
    for _, c in ipairs(chans) do
        if (c.cleared or 0) == 0 or #c.msgs > 0 then out[#out + 1] = c end
    end
    return out
end

-- Texts -----------------------------------------------------------------------------------

--- The Messages app's conversation list for a phone.
function Messages.chats(number)
    local out = {}
    for i, c in ipairs(Messages.list('sms', number)) do
        local others = {}
        for _, m in ipairs(c.members) do
            if m ~= number then others[#others + 1] = m end
        end
        out[i] = { id = c.id, ch = c.id, numbers = others, name = c.name, msgs = c.msgs, unread = c.unread }
    end
    return out
end

--- A text channel `number` belongs to, as (kind row, member list), or nil.
local function own(ch, number, kind)
    ch = Util.int(ch, 1, 2147483647)
    local row = ch and MySQL.single.await('SELECT id, name, size FROM lwk_phone_channels WHERE id = ? AND kind = ?', { ch, kind })
    if not row then return nil end
    local list = membersOf(ch)
    if not has(list, number) then return nil end
    return row, list
end

--- Send a text from `number`. Used by the UI and by the SendMessage export.
function Messages.text(src, number, to, chId, body)
    local row, list
    if chId then
        row, list = own(chId, number, 'sms')
        if not row then return nil, L('err_generic') end
    else
        local numbers, seen = {}, { [number] = true }
        for i = 1, math.min(type(to) == 'table' and #to or 0, 9) do
            local n = Util.number(to[i])
            if n and not seen[n] then
                seen[n] = true
                numbers[#numbers + 1] = n
            end
        end
        if #numbers == 0 then return nil, L('err_number') end
        local ch
        if #numbers == 1 then
            ch = Messages.pair('sms', number, numbers[1])
        else
            numbers[#numbers + 1] = number
            ch = Messages.create('sms', numbers)
        end
        row, list = own(ch, number, 'sms')
    end

    if body.money then
        if #list ~= 2 or not src then return nil, L('err_generic') end
        local ok, err = Wallet.transfer(src, number, list[1] == number and list[2] or list[1], body.money)
        if not ok then return nil, err end
    end

    local msg = Messages.add(row.id, number, body)
    for _, m in ipairs(list) do
        if m ~= number then Phone.push(m, { action = 'msg', ch = row.id, members = list, name = row.name, msg = msg }) end
    end
    return { ch = row.id, id = msg.id, time = msg.time }
end

RPC['msg.send'] = function(src, number, data)
    local body = Util.body(data.body)
    if not body then return Phone.fail(L('err_generic')) end
    if Phone.flags(number).airplane then return Phone.fail(L('err_airplane')) end
    local sent, err = Messages.text(src, number, data.to, data.ch, body)
    if not sent then return Phone.fail(err) end
    return Phone.ok(sent)
end

RPC['msg.read'] = function(_, number, data)
    MySQL.update.await('UPDATE lwk_phone_members SET unread = 0 WHERE channel = ? AND member = ?', { Util.int(data.ch, 1, 2147483647) or 0, number })
    return Phone.ok()
end

--- Delete a conversation from this phone; the other side keeps their copy.
RPC['msg.leave'] = function(_, number, data)
    local row = own(data.ch, number, 'sms')
    if not row then return Phone.fail(L('err_generic')) end
    if row.size == 2 then
        -- Between two people it is only hidden, with what was said so far. Leaving for real would mean the
        -- other person's next text reaches nobody: they still see the conversation and write into it.
        local last = MySQL.scalar.await('SELECT MAX(id) FROM lwk_phone_msgs WHERE channel = ?', { row.id }) or 0
        MySQL.update.await('UPDATE lwk_phone_members SET cleared = ?, unread = 0 WHERE channel = ? AND member = ?', { last, row.id, number })
        return Phone.ok()
    end
    MySQL.update.await('DELETE FROM lwk_phone_members WHERE channel = ? AND member = ?', { row.id, number })
    MySQL.update.await('UPDATE lwk_phone_channels SET size = size - 1 WHERE id = ?', { row.id })
    return Phone.ok()
end

RPC['msg.name'] = function(_, number, data)
    local row = own(data.ch, number, 'sms')
    local name = Util.text(data.name, 1, 40)
    if not row or row.size < 3 or not name then return Phone.fail(L('err_generic')) end
    MySQL.update.await('UPDATE lwk_phone_channels SET name = ? WHERE id = ?', { name, row.id })
    return Phone.ok()
end

RPC['msg.add'] = function(_, number, data)
    local row, list = own(data.ch, number, 'sms')
    local who = Util.number(data.number)
    if not row or row.size < 3 or #list >= 10 or not who or has(list, who) then return Phone.fail(L('err_generic')) end
    MySQL.prepare.await('INSERT IGNORE INTO lwk_phone_members (channel, member) VALUES (?, ?)', { row.id, who })
    MySQL.update.await('UPDATE lwk_phone_channels SET size = size + 1 WHERE id = ?', { row.id })
    return Phone.ok()
end

-- Social DMs (Flock, Lumen) ------------------------------------------------------------------

local DM_APPS = { flock = true, lumen = true }

--- Threads for the DM screen: { { id, user, msgs } }.
function Messages.dms(app, username)
    local me, out = app .. ':' .. username, {}
    for i, c in ipairs(Messages.list('dm:' .. app, me)) do
        local other = c.members[1] == me and c.members[2] or c.members[1]
        out[i] = { id = c.id, user = (other or me):sub(#app + 2), msgs = c.msgs }
    end
    return out
end

RPC['dm.send'] = function(_, number, data)
    local app = data.app
    local me = DM_APPS[app] and Social.user(number, app)
    local to, body = Util.username(data.to), Util.body(data.body)
    if not me then return Phone.fail(L('err_login')) end
    if not to or to == me or not body or body.money or not Social.exists(app, to) then return Phone.fail(L('err_generic')) end
    local ch = Messages.pair('dm:' .. app, app .. ':' .. me, app .. ':' .. to)
    local msg = Messages.add(ch, app .. ':' .. me, body)
    push(app .. ':' .. to, { action = 'dm', app = app, user = me, msg = msg })
    return Phone.ok({ id = msg.id, time = msg.time })
end

-- Shade: anonymous channels anyone can join by name ---------------------------------------------

local function alias(member) return member:sub(7) end   -- strips 'shade:'

Apps.shade = function(_, number)
    local me = Social.user(number, 'shade')
    if not me then return { shade = { alias = '', channels = {} } } end
    local channels = {}
    for i, c in ipairs(Messages.list('shade', 'shade:' .. me)) do
        for _, m in ipairs(c.msgs) do
            if m.from then m.from = alias(m.from) end
        end
        channels[i] = { id = c.id, name = c.name, members = c.size, msgs = c.msgs }
    end
    return { shade = { alias = me, channels = channels } }
end

RPC['shade.join'] = function(_, number, data)
    local me = Social.user(number, 'shade')
    local name = type(data.name) == 'string' and data.name:lower():match('^[a-z0-9_-]+$')
    if not me then return Phone.fail(L('err_login')) end
    if not name or #name < 2 or #name > 24 then return Phone.fail(L('err_generic')) end
    local ch = MySQL.scalar.await("SELECT id FROM lwk_phone_channels WHERE kind = 'shade' AND name = ?", { name })
        or MySQL.insert.await("INSERT INTO lwk_phone_channels (kind, name, size, updated) VALUES ('shade', ?, 0, ?)", { name, Phone.now() })
    if MySQL.update.await('INSERT IGNORE INTO lwk_phone_members (channel, member) VALUES (?, ?)', { ch, 'shade:' .. me }) > 0 then
        MySQL.update.await('UPDATE lwk_phone_channels SET size = size + 1 WHERE id = ?', { ch })
    end
    return Phone.ok({ id = ch })
end

RPC['shade.leave'] = function(_, number, data)
    local me = Social.user(number, 'shade')
    local row = me and own(data.ch, 'shade:' .. me, 'shade')
    if not row then return Phone.fail(L('err_generic')) end
    MySQL.update.await('DELETE FROM lwk_phone_members WHERE channel = ? AND member = ?', { row.id, 'shade:' .. me })
    MySQL.update.await('UPDATE lwk_phone_channels SET size = size - 1 WHERE id = ?', { row.id })
    return Phone.ok()
end

RPC['shade.send'] = function(_, number, data)
    local me = Social.user(number, 'shade')
    local text = Util.text(data.text, 1, 500)
    if not me then return Phone.fail(L('err_login')) end
    local row, list
    if text then row, list = own(data.ch, 'shade:' .. me, 'shade') end
    if not row then return Phone.fail(L('err_generic')) end
    local msg = Messages.add(row.id, 'shade:' .. me, { text = text })
    msg.from = me
    -- ponytail: one pass over online phones per member. Index sessions by account if channels get large.
    for _, m in ipairs(list) do
        if m ~= 'shade:' .. me then push(m, { action = 'shade', ch = row.id, msg = msg }) end
    end
    return Phone.ok({ id = msg.id, time = msg.time })
end
