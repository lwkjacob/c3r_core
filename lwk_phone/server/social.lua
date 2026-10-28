-- Social apps: accounts and logins, posts, reactions, follows, live streams, mail and matches.
-- Flock, Lumen, Loop, Shade and Mail use accounts with a username and password, so a player can
-- hold several, stay anonymous, and sign in on any phone. A session ties a phone to an account.
-- Adverts and Market post under the phone number instead.

Social = {}

local LOGIN = { flock = true, lumen = true, loop = true, shade = true, mail = true }
local FEEDS = { flock = true, lumen = true, loop = true }
local sess = {}    -- number -> { app = username }
local lives = {}   -- lumen username -> { viewers = { username = true } }

function Social.sessions(number)
    local map = {}
    for _, r in ipairs(MySQL.query.await('SELECT app, username FROM lwk_phone_sessions WHERE phone = ?', { number })) do map[r.app] = r.username end
    sess[number] = map
    return map
end

function Social.user(number, app) return sess[number] and sess[number][app] end

function Social.exists(app, username)
    return MySQL.scalar.await('SELECT 1 FROM lwk_phone_accounts WHERE app = ? AND username = ?', { app, username }) ~= nil
end

--- Tell every phone showing `app` to reload it.
function Social.refresh(app)
    for src in pairs(Phone.online()) do Phone.push(src, { action = 'refresh', app = app }) end
end

local function signIn(number, app, username)
    MySQL.prepare.await('REPLACE INTO lwk_phone_sessions (phone, app, username) VALUES (?, ?, ?)', { number, app, username })
    sess[number] = sess[number] or {}
    sess[number][app] = username
    return Phone.ok({ username = username })
end

AddEventHandler('lwk_phone:dropped', function(_, number)
    local me = Social.user(number, 'lumen')
    if me and lives[me] then
        lives[me] = nil
        Social.refresh('lumen')
    end
    sess[number] = nil
end)

-- Accounts -------------------------------------------------------------------------------------

RPC['account.signup'] = function(_, number, data)
    local app, username, password = data.app, Util.username(data.username), Util.text(data.password, 4, 64)
    if not LOGIN[app] then return Phone.fail(L('err_generic')) end
    if not username then return Phone.fail(L('err_username')) end
    if not password then return Phone.fail(L('err_password')) end
    if Social.exists(app, username) then return Phone.fail(L('err_taken')) end
    MySQL.insert.await('INSERT INTO lwk_phone_accounts (app, username, password, profile, created) VALUES (?, ?, ?, ?, ?)',
        { app, username, GetPasswordHash(password), json.encode({ name = Util.text(data.name, 1, 32) or username, bio = '' }), Phone.now() })
    return signIn(number, app, username)
end

RPC['account.login'] = function(_, number, data)
    local app, username = data.app, Util.username(data.username)
    local hash = LOGIN[app] and username and MySQL.scalar.await('SELECT password FROM lwk_phone_accounts WHERE app = ? AND username = ?', { app, username })
    if not hash or type(data.password) ~= 'string' or not VerifyPasswordHash(data.password, hash) then return Phone.fail(L('err_login_wrong')) end
    return signIn(number, app, username)
end

RPC['account.logout'] = function(_, number, data)
    MySQL.update.await('DELETE FROM lwk_phone_sessions WHERE phone = ? AND app = ?', { number, tostring(data.app) })
    if sess[number] then sess[number][data.app] = nil end
    return Phone.ok()
end

RPC['profile.set'] = function(_, number, data)
    local me = FEEDS[data.app] and Social.user(number, data.app)
    if not me then return Phone.fail(L('err_login')) end
    local raw = MySQL.scalar.await('SELECT profile FROM lwk_phone_accounts WHERE app = ? AND username = ?', { data.app, me })
    local p = raw and json.decode(raw) or {}
    p.bio = Util.text(data.bio, 0, 160) or p.bio
    p.name = Util.text(data.name, 1, 32) or p.name
    MySQL.update.await('UPDATE lwk_phone_accounts SET profile = ? WHERE app = ? AND username = ?', { json.encode(p), data.app, me })
    return Phone.ok()
end

RPC['follow'] = function(_, number, data)
    local me, who = FEEDS[data.app] and Social.user(number, data.app), Util.username(data.user)
    if not me then return Phone.fail(L('err_login')) end
    if not who or who == me then return Phone.fail(L('err_generic')) end
    if data.on then
        MySQL.prepare.await('INSERT IGNORE INTO lwk_phone_follows (app, follower, followee) VALUES (?, ?, ?)', { data.app, me, who })
    else
        MySQL.update.await('DELETE FROM lwk_phone_follows WHERE app = ? AND follower = ? AND followee = ?', { data.app, me, who })
    end
    return Phone.ok()
end

--- The `users` slice: profile, follower counts and whether the viewer follows them, for each name.
local function users(app, viewer, names)
    local list = {}
    for name in pairs(names) do list[#list + 1] = name end
    if #list == 0 then return {} end
    local marks, out = Util.marks(#list), {}
    for _, r in ipairs(MySQL.query.await(('SELECT username, profile FROM lwk_phone_accounts WHERE app = ? AND username IN (%s)'):format(marks), { app, table.unpack(list) })) do
        local p = json.decode(r.profile or '{}') or {}
        out[r.username] = { name = p.name or r.username, bio = p.bio or '', verified = p.verified == true or nil, followers = 0, following = 0 }
    end
    for _, r in ipairs(MySQL.query.await(('SELECT followee, COUNT(*) AS n FROM lwk_phone_follows WHERE app = ? AND followee IN (%s) GROUP BY followee'):format(marks), { app, table.unpack(list) })) do
        if out[r.followee] then out[r.followee].followers = r.n end
    end
    for _, r in ipairs(MySQL.query.await(('SELECT follower, COUNT(*) AS n FROM lwk_phone_follows WHERE app = ? AND follower IN (%s) GROUP BY follower'):format(marks), { app, table.unpack(list) })) do
        if out[r.follower] then out[r.follower].following = r.n end
    end
    for _, r in ipairs(MySQL.query.await('SELECT followee FROM lwk_phone_follows WHERE app = ? AND follower = ?', { app, viewer })) do
        if out[r.followee] then out[r.followee].followed = true end
    end
    -- A post whose author was deleted still needs a name to show.
    for name in pairs(names) do out[name] = out[name] or { name = name, bio = '', followers = 0, following = 0 } end
    return out
end

-- Posts ------------------------------------------------------------------------------------------

--- Top-level posts of `kind`, newest first, with replies, counts and the viewer's own reactions.
--- Returns the posts and the set of usernames that appear in them.
local function feed(app, kind, viewer, since)
    -- `since` is not put in the query. With it, a feed holding fewer than 60 fresh posts (yesterday's stories,
    -- say) has the database read every older one in search of more: 6 ms at 4,000 stories, and growing. Posts
    -- are numbered in the order they are made, so the newest 60 are taken by number and the old ones dropped here.
    local rows = MySQL.query.await('SELECT id, username, body, created FROM lwk_phone_posts WHERE app = ? AND kind = ? AND parent IS NULL ORDER BY id DESC LIMIT 60',
        { app, kind })
    local names, posts, byId, ids = { [viewer] = true }, {}, {}, {}
    for _, r in ipairs(rows) do
        if r.created >= (since or 0) then
            local p = json.decode(r.body) or {}
            p.id, p.user, p.time = r.id, r.username, r.created
            p.likes, p.reposts, p.shares, p.replies = 0, 0, 0, {}
            posts[#posts + 1], byId[r.id], ids[#ids + 1], names[r.username] = p, p, r.id, true
        end
    end
    if #ids > 0 then
        local marks = Util.marks(#ids)
        -- Asked for by app and kind as well as by parent, so that the `feed` index finds them: by parent alone
        -- the database reads the whole table (30 ms at 100,000 posts). A reply is always in its parent's app,
        -- and these are the only two kinds there are (see post.create).
        for _, r in ipairs(MySQL.query.await(("SELECT parent, username, body FROM lwk_phone_posts WHERE app = ? AND kind IN ('post', 'story') AND parent IN (%s) ORDER BY id"):format(marks),
            { app, table.unpack(ids) })) do
            local body = json.decode(r.body) or {}
            table.insert(byId[r.parent].replies, { user = r.username, text = body.text or '' })
            names[r.username] = true
        end
        local args = { viewer, table.unpack(ids) }
        for _, r in ipairs(MySQL.query.await(('SELECT post, kind, COUNT(*) AS n, MAX(username = ?) AS mine FROM lwk_phone_reactions WHERE post IN (%s) GROUP BY post, kind'):format(marks), args)) do
            local p, mine = byId[r.post], r.mine == 1 or r.mine == true
            if r.kind == 'like' then p.likes, p.liked = r.n, mine or nil end
            if r.kind == 'repost' then p.reposts, p.reposted = r.n, mine or nil end
            if r.kind == 'save' then p.saved = mine or nil end
        end
        -- Who liked the viewer's own posts, for their activity list.
        local own = {}
        for _, p in ipairs(posts) do
            if p.user == viewer then own[#own + 1] = p.id end
        end
        if #own > 0 then
            for _, r in ipairs(MySQL.query.await(("SELECT post, username FROM lwk_phone_reactions WHERE kind = 'like' AND username <> ? AND post IN (%s) LIMIT 200"):format(Util.marks(#own)), { viewer, table.unpack(own) })) do
                local p = byId[r.post]
                p.likers = p.likers or {}
                p.likers[#p.likers + 1] = r.username
                names[r.username] = true
            end
        end
    end
    for _, p in ipairs(posts) do p.comments = p.replies end
    return posts, names
end

local function trends()
    local counts, order = {}, {}
    for _, r in ipairs(MySQL.query.await("SELECT body FROM lwk_phone_posts WHERE app = 'flock' ORDER BY id DESC LIMIT 200")) do
        for _, tag in ipairs(Util.hashtags((json.decode(r.body) or {}).text)) do
            if not counts[tag] then
                counts[tag] = 0
                order[#order + 1] = tag
            end
            counts[tag] = counts[tag] + 1
        end
    end
    table.sort(order, function(a, b) return counts[a] > counts[b] end)
    local out = {}
    for i = 1, math.min(5, #order) do out[i] = { order[i], tostring(counts[order[i]]) } end
    return out
end

Apps.flock = function(_, number)
    local me = Social.user(number, 'flock')
    if not me then return {} end
    local posts, names = feed('flock', 'post', me)
    local dms = Messages.dms('flock', me)
    for _, t in ipairs(dms) do names[t.user] = true end
    return { flock = posts, users = users('flock', me, names), trends = trends(), dms = { flock = dms } }
end

Apps.lumen = function(_, number)
    local me = Social.user(number, 'lumen')
    if not me then return {} end
    local posts, names = feed('lumen', 'post', me)
    local dms = Messages.dms('lumen', me)
    for _, t in ipairs(dms) do names[t.user] = true end

    -- Stories: the last 24 hours, grouped by author. Anyone live right now goes first.
    local stories, byUser = {}, {}
    for user in pairs(lives) do
        if user ~= me then
            stories[#stories + 1] = { user = user, seeds = {}, seen = false, live = true }
            names[user] = true
        end
    end
    for _, s in ipairs((feed('lumen', 'story', me, Phone.now() - 86400000))) do
        if not byUser[s.user] then
            byUser[s.user] = { user = s.user, seeds = {}, seen = false }
            stories[#stories + 1] = byUser[s.user]
            names[s.user] = true
        end
        table.insert(byUser[s.user].seeds, 1, s.seed)
    end
    return { lumen = posts, stories = stories, users = users('lumen', me, names), dms = { lumen = dms } }
end

Apps.loop = function(_, number)
    local me = Social.user(number, 'loop')
    if not me then return {} end
    local posts, names = feed('loop', 'post', me)
    return { loop = posts, users = users('loop', me, names) }
end

local function listings(app, number)
    local out = {}
    for i, p in ipairs((feed(app, 'post', number))) do
        out[i] = { id = p.id, title = p.title, body = p.body, number = p.user, time = p.time, price = p.price, seed = p.seed, mine = p.user == number or nil }
    end
    return out
end
Apps.adverts = function(_, number) return { adverts = listings('adverts', number) } end
Apps.market = function(_, number) return { market = listings('market', number) } end

--- What each app lets into a post body. Anything else the client sends is dropped.
local function postBody(app, kind, d, reply)
    if reply then
        local text = Util.text(d.text, 1, 280)
        return text and { text = text }
    end
    if app == 'flock' then
        local text = Util.text(d.text, 1, 280)
        return text and { text = text, pic = Util.url(d.pic) }
    elseif app == 'lumen' then
        local seed = Util.url(d.seed)
        return seed and { seed = seed, caption = kind == 'post' and Util.text(d.caption, 0, 300) or nil }
    elseif app == 'loop' then
        local seed = Util.url(d.seed)
        return seed and { seed = seed, src = Util.url(d.src), caption = Util.text(d.caption, 0, 200) or '', sound = Util.text(d.sound, 0, 80) or '' }
    elseif app == 'adverts' or app == 'market' then
        local title, body = Util.text(d.title, 1, 60), Util.text(d.body, 0, 400)
        local price = app == 'market' and Util.int(d.price, 1, 1000000000) or nil
        if not title or (app == 'market' and not price) then return nil end
        return { title = title, body = body or '', price = price, seed = Util.url(d.seed) }
    end
end

RPC['post.create'] = function(_, number, data)
    local app = data.app
    local author = FEEDS[app] and Social.user(number, app) or ((app == 'adverts' or app == 'market') and number)
    if not author then return Phone.fail(L('err_login')) end
    local parent = Util.int(data.parent, 1, 2147483647)
    if parent and not MySQL.scalar.await('SELECT 1 FROM lwk_phone_posts WHERE id = ? AND app = ? AND parent IS NULL', { parent, app }) then parent = nil end
    local kind = (app == 'lumen' and data.kind == 'story') and 'story' or 'post'
    local body = postBody(app, kind, type(data.body) == 'table' and data.body or {}, parent ~= nil)
    if not body then return Phone.fail(L('err_generic')) end
    local now = Phone.now()
    local id = MySQL.insert.await('INSERT INTO lwk_phone_posts (app, kind, username, body, parent, created) VALUES (?, ?, ?, ?, ?, ?)',
        { app, kind, author, json.encode(body), parent, now })
    if not parent then
        Social.refresh(app)
        Phone.log(('**%s** post by %s: %s'):format(app, author, body.text or body.caption or body.title or ''))
    end
    return Phone.ok({ id = id, time = now })
end

RPC['post.delete'] = function(src, number, data)
    local row = MySQL.single.await('SELECT id, app, username FROM lwk_phone_posts WHERE id = ?', { Util.int(data.id, 1, 2147483647) or 0 })
    if not row then return Phone.ok() end
    -- Signed by an account in the feed apps and by a phone number in Adverts and Market. Checked by
    -- which kind it is: a long phone number can read exactly like somebody's username.
    local author
    if FEEDS[row.app] then author = Social.user(number, row.app) else author = number end
    if row.username ~= author and not Bridge.isAdmin(src) then return Phone.fail(L('err_generic')) end
    MySQL.update.await('DELETE FROM lwk_phone_posts WHERE id = ? OR parent = ?', { row.id, row.id })
    MySQL.update.await('DELETE FROM lwk_phone_reactions WHERE post = ?', { row.id })
    Social.refresh(row.app)
    return Phone.ok()
end

local REACTIONS = { like = true, repost = true, save = true }

RPC['post.react'] = function(_, number, data)
    local id = Util.int(data.id, 1, 2147483647) or 0
    local app = MySQL.scalar.await('SELECT app FROM lwk_phone_posts WHERE id = ?', { id })
    local me = app and Social.user(number, app)
    if not me or not REACTIONS[data.kind] then return Phone.fail(L('err_login')) end
    if data.on then
        MySQL.prepare.await('INSERT IGNORE INTO lwk_phone_reactions (post, username, kind) VALUES (?, ?, ?)', { id, me, data.kind })
    else
        MySQL.update.await('DELETE FROM lwk_phone_reactions WHERE post = ? AND username = ? AND kind = ?', { id, me, data.kind })
    end
    return Phone.ok()
end

-- Live streams (Lumen) ---------------------------------------------------------------------------
-- The host's phone sends video straight to each viewer over WebRTC; the server only knows who is
-- live and who is watching, and relays the handshake and the chat. Peers are addressed by account
-- name, so nobody learns anyone's phone number.

local function audience(host, msg)
    local live = lives[host]
    if not live then return end
    Messages.push('lumen:' .. host, msg)
    for viewer in pairs(live.viewers) do Messages.push('lumen:' .. viewer, msg) end
end

RPC['live.start'] = function(_, number)
    local me = Social.user(number, 'lumen')
    if not me then return Phone.fail(L('err_login')) end
    lives[me] = { viewers = {} }
    Social.refresh('lumen')
    return Phone.ok()
end

RPC['live.stop'] = function(_, number)
    local me = Social.user(number, 'lumen')
    if me and lives[me] then
        audience(me, { action = 'live', event = 'ended', host = me })
        lives[me] = nil
        Social.refresh('lumen')
    end
    return Phone.ok()
end

RPC['live.join'] = function(_, number, data)
    local me, host = Social.user(number, 'lumen'), Util.username(data.host)
    local live = host and lives[host]
    if not me or not live or host == me then return Phone.fail(L('err_generic')) end
    live.viewers[me] = data.leave ~= true or nil
    local n = 0
    for _ in pairs(live.viewers) do n = n + 1 end
    if not data.leave then Messages.push('lumen:' .. host, { action = 'live', event = 'viewer', host = host, user = me }) end
    audience(host, { action = 'live', event = 'count', host = host, n = n })
    return Phone.ok()
end

RPC['live.say'] = function(_, number, data)
    local me, host, text = Social.user(number, 'lumen'), Util.username(data.host), Util.text(data.text, 1, 120)
    if not me or not host or not text or not lives[host] then return Phone.fail(L('err_generic')) end
    audience(host, { action = 'live', event = 'say', host = host, user = me, text = text })
    return Phone.ok()
end

--- Where a WebRTC handshake message for 'lumen:<user>' should go, or nil if the two are not in a stream together.
function Social.livePeer(number, to)
    local me, other = Social.user(number, 'lumen'), to:match('^lumen:(.+)$')
    if not me or not other then return nil end
    local a, b = lives[me], lives[other]
    if (a and a.viewers[other]) or (b and b.viewers[me]) then return 'lumen:' .. other, 'lumen:' .. me end
end

-- Mail ---------------------------------------------------------------------------------------------

local function address(user) return user .. '@' .. Config.mailDomain end

Apps.mail = function(_, number)
    local me = Social.user(number, 'mail')
    if not me then return {} end
    local addr, out = address(me), {}
    for i, r in ipairs(MySQL.query.await('SELECT * FROM lwk_phone_mail WHERE recipient = ? OR sender = ? ORDER BY id DESC LIMIT 80', { addr, addr })) do
        local sent = r.sender == addr
        local other = sent and r.recipient or r.sender
        out[i] = { id = r.id, from = other, addr = other, subject = r.subject, body = r.body, time = r.created,
            read = sent or r.seen == 1 or r.seen == true or nil, sent = sent or nil }
    end
    return { mail = out }
end

--- Deliver an email. `from` is any address or display name; `to` must be an existing account's address.
function Social.mail(from, to, subject, body)
    local user = type(to) == 'string' and to:lower():match('^([a-z0-9_]+)@' .. Config.mailDomain:gsub('%p', '%%%0') .. '$')
    if not user or not Social.exists('mail', user) then return false end
    local id = MySQL.insert.await('INSERT INTO lwk_phone_mail (sender, recipient, subject, body, created) VALUES (?, ?, ?, ?, ?)',
        { from, address(user), subject, body, Phone.now() })
    Messages.push('mail:' .. user, { action = 'refresh', app = 'mail' })
    Messages.push('mail:' .. user, { action = 'notify', app = 'mail', title = from, body = subject })
    return id
end

RPC['mail.send'] = function(_, number, data)
    local me = Social.user(number, 'mail')
    if not me then return Phone.fail(L('err_login')) end
    local subject, body = Util.text(data.subject, 0, 120) or '', Util.text(data.body, 0, 4000) or ''
    local id = Social.mail(address(me), data.to, subject, body)
    if not id then return Phone.fail(L('err_no_address')) end
    return Phone.ok({ id = id })
end

RPC['mail.read'] = function(_, number, data)
    local me = Social.user(number, 'mail')
    if me then MySQL.update.await('UPDATE lwk_phone_mail SET seen = 1 WHERE id = ? AND recipient = ?', { Util.int(data.id, 1, 2147483647) or 0, address(me) }) end
    return Phone.ok()
end

-- ponytail: deleting removes the email for both sides. Add per-side flags if that ever matters.
RPC['mail.delete'] = function(_, number, data)
    local me = Social.user(number, 'mail')
    if me then MySQL.update.await('DELETE FROM lwk_phone_mail WHERE id = ? AND (recipient = ? OR sender = ?)', { Util.int(data.id, 1, 2147483647) or 0, address(me), address(me) }) end
    return Phone.ok()
end

-- Ember: swipe, match, chat ------------------------------------------------------------------------
-- A profile is an account with a generated name and no password, so matches and chats are addressed
-- by that name rather than by phone number.

local function emberProfile(username)
    local raw = MySQL.scalar.await("SELECT profile FROM lwk_phone_accounts WHERE app = 'ember' AND username = ?", { username })
    return raw and json.decode(raw) or nil
end

local function card(i, username, p)
    local seeds = type(p.seeds) == 'table' and #p.seeds > 0 and p.seeds or { #(p.name or '') * 7 + 3 }
    return { id = i, key = username, name = p.name or '?', age = p.age or 18, bio = p.bio or '', job = p.job or '', dist = 1, seeds = seeds, seed = seeds[1] }
end

Apps.ember = function(_, number)
    local me = Social.user(number, 'ember')
    local mine = me and emberProfile(me)
    if not mine then return { ember = {}, matches = {}, emberProfile = false } end

    local deck = {}
    for i, r in ipairs(MySQL.query.await([[SELECT a.username, a.profile FROM lwk_phone_accounts a
        WHERE a.app = 'ember' AND a.username <> ? AND NOT EXISTS (
            SELECT 1 FROM lwk_phone_follows f WHERE f.app IN ('ember', 'ember_no') AND f.follower = ? AND f.followee = a.username
        ) ORDER BY a.created DESC LIMIT 25]], { me, me })) do
        deck[i] = card(i, r.username, json.decode(r.profile) or {})
    end

    local chats = {}
    for _, c in ipairs(Messages.list('ember', 'ember:' .. me)) do
        local other = c.members[1] == 'ember:' .. me and c.members[2] or c.members[1]
        if other then chats[other:sub(7)] = c.msgs end
    end
    local matches = {}
    for i, r in ipairs(MySQL.query.await([[SELECT a.username, a.profile FROM lwk_phone_follows f
        JOIN lwk_phone_follows g ON g.app = 'ember' AND g.follower = f.followee AND g.followee = f.follower
        JOIN lwk_phone_accounts a ON a.app = 'ember' AND a.username = f.followee
        WHERE f.app = 'ember' AND f.follower = ?]], { me })) do
        local m = card(100 + i, r.username, json.decode(r.profile) or {})
        m.msgs = chats[r.username] or {}
        matches[i] = m
    end
    return { ember = deck, matches = matches, emberProfile = mine }
end

RPC['ember.profile'] = function(_, number, data)
    local name, age = Util.text(data.name, 1, 24), Util.int(data.age, 18, 99)
    if not name or not age then return Phone.fail(L('err_generic')) end
    local seeds = {}
    for i = 1, math.min(type(data.seeds) == 'table' and #data.seeds or 0, 4) do seeds[#seeds + 1] = Util.url(data.seeds[i]) end
    local profile = json.encode({ name = name, age = age, bio = Util.text(data.bio, 0, 160) or '', job = Util.text(data.job, 0, 24) or '', seeds = seeds })
    local me = Social.user(number, 'ember')
    if me then
        MySQL.update.await("UPDATE lwk_phone_accounts SET profile = ? WHERE app = 'ember' AND username = ?", { profile, me })
        return Phone.ok()
    end
    me = 'e' .. math.random(100000000, 999999999)
    MySQL.insert.await("INSERT INTO lwk_phone_accounts (app, username, profile, created) VALUES ('ember', ?, ?, ?)", { me, profile, Phone.now() })
    return signIn(number, 'ember', me)
end

RPC['ember.delete'] = function(_, number)
    local me = Social.user(number, 'ember')
    if not me then return Phone.ok() end
    MySQL.update.await("DELETE FROM lwk_phone_accounts WHERE app = 'ember' AND username = ?", { me })
    MySQL.update.await("DELETE FROM lwk_phone_follows WHERE app IN ('ember', 'ember_no') AND (follower = ? OR followee = ?)", { me, me })
    MySQL.update.await("DELETE FROM lwk_phone_sessions WHERE app = 'ember' AND username = ?", { me })
    sess[number].ember = nil
    return Phone.ok()
end

local function matched(a, b)
    return MySQL.scalar.await("SELECT COUNT(*) FROM lwk_phone_follows WHERE app = 'ember' AND ((follower = ? AND followee = ?) OR (follower = ? AND followee = ?))", { a, b, b, a }) == 2
end

RPC['ember.swipe'] = function(_, number, data)
    local me, who = Social.user(number, 'ember'), type(data.key) == 'string' and data.key:match('^e%d+$')
    if not me or not who or who == me or not Social.exists('ember', who) then return Phone.fail(L('err_generic')) end
    MySQL.prepare.await('INSERT IGNORE INTO lwk_phone_follows (app, follower, followee) VALUES (?, ?, ?)', { data.like and 'ember' or 'ember_no', me, who })
    if data.like and matched(me, who) then
        Messages.push('ember:' .. who, { action = 'refresh', app = 'ember' })
        Messages.push('ember:' .. who, { action = 'notify', app = 'ember', title = 'Ember', body = L('ember_match') })
        return Phone.ok({ match = true })
    end
    return Phone.ok({ match = false })
end

RPC['ember.send'] = function(_, number, data)
    local me, who, text = Social.user(number, 'ember'), type(data.key) == 'string' and data.key:match('^e%d+$'), Util.text(data.text, 1, 500)
    if not me or not who or not text or not matched(me, who) then return Phone.fail(L('err_generic')) end
    local msg = Messages.add(Messages.pair('ember', 'ember:' .. me, 'ember:' .. who), 'ember:' .. me, { text = text })
    Messages.push('ember:' .. who, { action = 'ember', key = me, msg = msg })
    return Phone.ok({ id = msg.id, time = msg.time })
end
