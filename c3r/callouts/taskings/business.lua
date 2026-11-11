--[[
    c3r special tasking: BUSINESS CHECK. Asked for on the radio ("requesting a business check"), never put out.

    A route of at least 6 businesses in one area (each location is a route). At each: the manager, the business licence,
    the liquor licence where they serve alcohol, the fire exits. Most pass; some don't (an expired licence, no liquor
    licence, a blocked fire exit), and the manager gets a ticket or a warning. The card is the same every time: the next
    business on the route. What's really going on is one of two stories:
      routine  0-2 businesses on the route have something wrong
      robbery  0-1 do, and at one business (never the first) an armed robbery is under way as you pull up: the robber
               has the clerk at gunpoint. Talked down, he gives up; or he runs, or opens fire. Then the route goes on
    It's over when every business has been checked and the robbery (if any) is dealt with. One MDT line per business.

    Points per location: walk them out in game with /c3rplace business (it writes the location in below). Name the
    businesses by hand in the location afterwards (a /c3rplace over that location replaces them):
        names = { biz1 = { "Rob's Liquor", 'liquor' }, biz2 = { 'Bean Machine', 'food' }, ... }
    kinds: 'liquor', 'bar', 'food' (serve alcohol: the liquor licence is asked), 'store', 'garage', 'shop'.
    Unnamed: "the business on <street>", a shop.
]]

local MAX = 8 -- (biz7 and biz8 are optional: a longer route)
local ALCOHOL = { liquor = true, bar = true, food = true }
local COUNTER = { liquor = true, store = true } -- (a shopkeeper behind the counter)

local ROBBER_Q = {
    { id = 'c_why', label = 'Why did you do it?', stress = true },
    { id = 'c_alone', label = 'Is anyone else with you?', stress = true },
}

-- Business i on this route: its name and kind, or nil if this location's route is shorter.
local function business(c, i)
    if not c:point('biz' .. i) then return nil end
    local l = c:label('biz' .. i)
    if type(l) == 'table' then return tostring(l[1] or l.name or ('Business ' .. i)), tostring(l[2] or l.kind or 'shop') end
    if type(l) == 'string' then return l, 'shop' end
    return ('the business on %s'):format(c:street('biz' .. i)), 'shop'
end

local function cap(s) return (s:gsub('^%l', string.upper)) end

-- The questions for a business of this kind.
local function questions(kind)
    local q = { { id = 'c_licence', label = 'Can I see your business licence?' } }
    if ALCOHOL[kind] then q[#q + 1] = { id = 'c_alcohol', label = 'And your liquor licence?' } end
    q[#q + 1] = { id = 'c_exits', label = 'Where are your fire exits?' }
    q[#q + 1] = { id = 'c_trouble', label = 'Any trouble lately?' }
    return q
end

local TROUBLE = {
    "Kids hanging round outside at night. Nothing we can't handle.",
    "Shoplifters, now and then. We've got the cameras.",
    "Quiet, thank God. Long may it last.",
    "Someone keyed my car out front last week. Didn't report it. What's the point?",
}

-- Each business's manager, what's wrong there (bad: 'licence' | 'alcohol' | 'exit' | nil) and the card line.
local function manager(c, i, name, kind, bad)
    local function line(ok, wrong, fact)
        if bad == fact then return { { wrong, set = { c_bad = fact } } } end
        return { ok }
    end
    c:person('mgr' .. i, { at = 'biz' .. i, label = 'Manager', model = COUNTER[kind] and 'mp_m_shopkeep_01' or nil, male = COUNTER[kind] or nil,
        secret = 'clean', demeanor = bad and 'nervous' or (math.random() < .5 and 'polite' or 'chatty'),
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = questions(kind), lines = {
            c_licence = line("On the wall behind the counter. Renewed in January, see the stamp.",
                "It's... the renewal's in the post. It ran out last month. I've been meaning to chase it.", 'licence'),
            c_alcohol = line("Framed, by the door. Same as every year.",
                "We applied. They're slow. We can still serve while it goes through, can't we?", 'alcohol'),
            c_exits = line("Out the back, past the stockroom. Kept clear. You can try the bar if you like.",
                "Out the back. There might be a few boxes in front of it. We had a delivery this morning.", 'exit'),
            c_trouble = { TROUBLE[math.random(#TROUBLE)] },
        } })
    c:clue('exit' .. i, { at = 'exit' .. i, label = ('Fire exit: %s'):format(name),
        text = bad == 'exit' and 'Stacked crates of stock against the push bar. The door opens a hand-width. Nobody is getting out this way.'
            or 'The push bar works, the way out is clear and the sign is lit.' })
    c:objective('b' .. i, ('Check %s'):format(name), { hint = 'Talk to the manager: the licences and the fire exits.', blip = 'mgr' .. i })
    c:objective('v' .. i, ('Deal with %s: ticket or warn the manager'):format(name), { hidden = true, who = 'all', blip = 'mgr' .. i,
        hint = 'Write them a ticket, give them a warning, or let them off.' })
end

-- The route: n businesses, what's wrong where, and the robbery (at business `robbed`, if any). -> the route's list
local function route(c, faults, robbed)
    local list = {}
    for i = 1, MAX do
        local name, kind = business(c, i)
        if name then list[#list + 1] = { i = i, name = name, kind = kind } end
    end
    local pool = {}
    for _, b in ipairs(list) do if b.i ~= robbed then pool[#pool + 1] = b end end
    for _ = 1, math.min(faults, #pool) do
        local b = table.remove(pool, math.random(#pool))
        local kinds = { 'licence', 'exit' }
        if ALCOHOL[b.kind] then kinds[#kinds + 1] = 'alcohol' end
        b.bad = kinds[math.random(#kinds)]
    end
    for _, b in ipairs(list) do manager(c, b.i, b.name, b.kind, b.bad) end
    c:set('route', list)
    return list
end

local RESULT = { licence = 'an expired business licence', alcohol = 'no liquor licence', exit = 'a blocked fire exit' }

--[[ Each business: checked once every question it has has been asked (the fire exit looked at counts for that one).
     Nothing wrong: done then. Something wrong: done once the officer's dealt with the manager (a ticket, a warning, let
     off). Over when every business is done and the robbery (if any) is dealt with, nobody's waiting to be taken in, and
     anyone hurt has been seen to. The robbed business (robbed) is checked by stopping the robbery. ]]
local function wire(c, list, robbery_done, robbed)
    local by, asked, result, out, taken, medic, over = {}, {}, {}, {}, {}, {}, false
    for _, b in ipairs(list) do by['mgr' .. b.i], asked[b.i] = b, {} end
    local function record(b, text)
        if result[b.i] then return end
        result[b.i] = text
        c:done('b' .. b.i)
        c:done('v' .. b.i)
        c:note(('Business check: %s, %s: %s.'):format(cap(b.name), c:street('biz' .. b.i), text))
    end
    local function checked(b)
        local a = asked[b.i]
        return a.c_licence and a.c_exits and (a.c_alcohol or not ALCOHOL[b.kind])
    end
    local function found(b) local o = c:who('mgr' .. b.i) return o and o.facts.c_bad end
    local heading_to
    local function next_stop() -- (the waypoint: the first business on the route not done yet)
        for _, b in ipairs(list) do
            if not c:is_done('b' .. b.i) then
                if heading_to ~= b.i then heading_to = b.i c:waypoint('biz' .. b.i) end
                return
            end
        end
    end
    local function check()
        if over then return end
        next_stop()
        if not robbery_done() then return end
        if robbed then c:done('b' .. robbed) next_stop() end
        for _, b in ipairs(list) do if not result[b.i] and b.i ~= robbed then return end end
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return end end
        for _, pending in pairs(medic) do if pending then return end end
        over = true
        local parts = {}
        for _, b in ipairs(list) do
            if b.i ~= robbed then parts[#parts + 1] = ('%s (%s): %s.'):format(cap(b.name), c:street('biz' .. b.i), result[b.i]) end
        end
        c:finish(('Business checks around %s: %d businesses checked. %s%s'):format(c:street(), #list, table.concat(parts, ' '),
            c:get('robbery_text') or ''))
    end
    c:set('check', check)
    c:on('act', function(who, action, arg)
        local b = by[who]
        if action == 'cuff' and c:who(who) and c:who(who).cuffed then
            out[who] = 'arrested'
            c:custody(who)
            if b then record(b, 'the manager was arrested') end
        elseif action == 'uncuff' and out[who] == 'arrested' then
            out[who] = nil
            c:hide('custody:' .. who)
        end
        if not b or result[b.i] then return check() end
        if action == 'ask' then asked[b.i][arg] = true end
        if checked(b) then
            if found(b) then c:reveal('v' .. b.i)
            else record(b, 'passed') end
        end
        if found(b) and (action == 'cite' or action == 'warn') then
            record(b, ('%s, %s'):format(RESULT[found(b)], action == 'cite' and 'ticket issued' or 'warning given'))
        end
        check()
    end)
    c:on('inspect', function(clue)
        local i = tonumber(clue:match('^exit(%d+)$') or '')
        local b = i and by['mgr' .. i]
        if not b or result[b.i] then return end
        asked[b.i].c_exits = true -- (seen for themselves)
        if b.bad == 'exit' and c:who('mgr' .. i) then
            c:who('mgr' .. i).facts.c_bad = 'exit'
            c:questions('mgr' .. i)
        end
        if checked(b) then if found(b) then c:reveal('v' .. b.i) else record(b, 'passed') end end
        check()
    end)
    c:on('contact_ended', function(who, outcome)
        local b = by[who]
        if not b or result[b.i] or not found(b) or not checked(b) then return check() end
        if outcome == 'released' then record(b, ('%s, let off with words of advice'):format(RESULT[found(b)])) end
        check()
    end)
    c:on('custody', function(who) taken[who] = true check() end)
    c:on('gone', function(who) if out[who] == 'arrested' then taken[who] = true end check() end)
    local function hurt(who)
        if medic[who] ~= nil then return end
        medic[who] = true
        c:objective('medic:' .. who, ('Call paramedics for the %s'):format(who == 'robber' and 'robber' or 'manager'),
            { who = 'all', blip = who, hint = 'Radio for an ambulance. If they pronounce them, the coroner can take them.' })
        c:dispatch('Someone is down at the business. Paramedics needed.')
    end
    c:on('dead', function(who)
        out[who] = 'dead'
        c:hide('custody:' .. who)
        if by[who] then record(by[who], 'the manager was shot and killed') end
        hurt(who)
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' or what == 'hospital' or what == 'treated' then
            medic[who] = false
            c:done('medic:' .. who)
            if what == 'hospital' and out[who] == 'arrested' then taken[who] = true end
        end
        check()
    end)
    c:on('tick', check)
end

-- The robbery at business k: brought when a unit's within 150 m of it, holding the clerk at gunpoint. Told to drop it:
-- half the time he does, a fifth of the time he runs. A minute of units close and he opens fire; then he gives up once
-- hurt, or after 45-90 s. Run off and not caught: gone once nobody's within 200 m for 30 s. -> robbery_done()
local function robbery(c, k)
    local b
    for _, x in ipairs(c:get('route')) do if x.i == k then b = x end end
    local p = c:point('biz' .. k)
    local h = math.rad(p.w)
    local at = vector4(p.x - math.sin(h) * 1.8, p.y + math.cos(h) * 1.8, p.z, (p.w + 180.0) % 360.0) -- (facing the counter)
    local clerk = 'mgr' .. k
    c:set('robbed', k)
    c:person('robber', { at = at, later = true, label = 'Robber', male = true, age = { 19, 35 }, secret = 'drugs', demeanor = 'rude',
        weapon = 'WEAPON_PISTOL', items = { 'Pistol', 'Cash from the till, in a carrier bag' }, scene = 'WORLD_HUMAN_STAND_IMPATIENT',
        questions = ROBBER_Q, lines = {
            c_why = { "I owe people. You don't know these people.", "Rent. Food. Pick one." },
            c_alone = { "Just me. Just me, I swear." },
        } })
    c:objective('rob', ('Stop the robbery at %s'):format(b.name), { hidden = true, who = 'all', blip = 'robber',
        hint = 'He has the clerk at gunpoint. Tell him to drop it.' })
    local stage, left, away, how, idle = nil, 0, 0, nil, 0
    local function over(text)
        if how then return end
        how = text
        c:done('rob')
        c:set('robbery_text', (' %s: an armed robbery was under way on arrival; %s.'):format(cap(b.name), text))
        if c:who(clerk) and not c:who(clerk).cuffed then c:task(clerk, 'scene') end
        local res = c:get('check')
        if res then res() end
    end
    local function surrender(line)
        if stage == 'down' or stage == 'ran' then return end
        stage = 'down'
        c:who('robber').ran, c:who('robber').gave_up = true, true
        c:say('robber', line)
        c:task('robber', 'surrender')
    end
    c:on('hail', function(who)
        if who ~= 'robber' or (stage ~= 'hold' and stage ~= 'shoot') then return end
        local r = math.random()
        if r < .5 then surrender("Okay! Okay! Don't shoot! It's down!")
        elseif r < .7 then
            stage = 'ran'
            c:say('robber', 'No way! No way!')
            c:task('robber', 'flee')
        else c:say('robber', 'Back off or he gets it!') end
    end)
    c:on('custody', function(who) if who == 'robber' then over('the robber was arrested') end end)
    c:on('dead', function(who) if who == 'robber' then stage = 'dead' end end)
    c:on('aid', function(who, what)
        if who ~= 'robber' then return end
        if what == 'pronounced' then over('the robber died at the scene')
        elseif what == 'hospital' and c:who('robber').cuffed then over('the robber was arrested and taken to hospital') end
    end)
    c:on('gone', function(who)
        if who ~= 'robber' then return end
        if c:who('robber') and c:who('robber').cuffed then over('the robber was arrested')
        elseif stage == 'dead' then over('the robber died at the scene')
        else over('the robber got away') end
    end)
    c:on('contact_ended', function(who, outcome)
        if who == 'robber' and outcome == 'fled' then stage = 'ran' end
        if who == 'robber' and (outcome == 'released' or outcome == 'cited' or outcome == 'warning') then
            over('the robber was let go')
            c:task('robber', 'wander')
        end
    end)
    c:on('tick', function()
        if how or stage == 'dead' then return end
        if not stage then
            if c:near(clerk, 150.0) then stage = 'coming' c:bring('robber') end
            return
        end
        if stage == 'coming' then
            if not (c:health('robber') and c:health(clerk)) then return end -- (both made)
            stage, left = 'hold', 60
            c:task('robber', 'hold', clerk)
            c:task(clerk, 'surrender')
            c:reveal('rob')
            return
        end
        if stage == 'hold' or stage == 'shoot' then
            if not c:get('seen') and c:near('robber', 40.0) then
                c:set('seen', true)
                c:note(('Armed robbery in progress at %s'):format(b.name))
                c:dispatch(('All units: armed robbery in progress at %s, %s. Suspect has the clerk at gunpoint.'):format(b.name, c:street('biz' .. k)))
            end
            local health = c:health('robber')
            if health and health > 100 and health < 150 then return surrender("I'm hit! I'm hit! I give up!") end
            if c:near('robber', 30.0) then left = left - 1 end
            if left <= 0 then
                if stage == 'hold' then stage, left = 'shoot', math.random(45, 90) c:task('robber', 'shoot')
                else surrender("Enough! Enough! I'm putting it down!") end
            end
        elseif stage == 'down' then -- (given up, then left alone: a minute with nobody near and he runs for it)
            local o = c:who('robber')
            idle = (o and not o.cuffed and not c:talking('robber') and not c:near('robber', 30.0)) and idle + 1 or 0
            if idle >= 60 then stage = 'ran' c:task('robber', 'flee') end
        elseif stage == 'ran' and not c:talking('robber') then
            away = c:near('robber', 200.0) and 0 or away + 1
            if away >= 30 then c:remove('robber') end
        end
    end)
    return function() return how ~= nil end
end

local function names(...) return { ... } end

Callout({
    id = 'business',
    name = 'Business check',
    tasking = 'business', -- (a special tasking: asked for on the radio, never put out by dispatch)
    voice = 'call_business', -- (dispatch's line: lwk_control/tools/make_voice.py)
    alert = 'Special tasking',
    priority = 3,
    weight = 1,
    max_minutes = 40,
    enabled = true,
    reports = {
        'Routine business checks on the route: licences on display, liquor licences, fire exits clear.',
        'Business compliance checks requested in the area. Speak to each manager, check their paperwork and exits.',
        'Licensing has asked for a round of business checks. Visit each one on the route and report back.',
    },
    -- The points each location needs, in the order /c3rplace business walks you through them: each business on the
    -- route, then its fire exit. The first is the first business. Keep the route in one area of the city: about 3
    -- minutes a business, driving included.
    points = (function()
        local p = {}
        for i = 1, MAX do
            p[#p + 1] = { 'biz' .. i, ('Business %d on the route: its manager, inside behind the counter or by the door.'):format(i), optional = i > 6 or nil }
            p[#p + 1] = { 'exit' .. i, ('Business %d: outside its fire exit, at the back or the side (Z if there is none to reach).'):format(i), optional = true }
        end
        return p
    end)(),
    -- Add more with /c3rplace business in game (it writes them here). This one is a rough placeholder, across the city.
    locations = {
        { street = 'Davis Ave', at = vector3(-47.16, -1758.51, 29.42), streets = { biz2 = 'Strawberry Ave', biz3 = 'Palomino Ave',
            biz4 = 'Eclipse Blvd', biz5 = 'Clinton Ave', biz6 = 'West Mirror Drive' },
            names = { biz1 = names('the Davis Ave store', 'store'), biz2 = names('the club on Strawberry', 'bar'),
                biz3 = names('the Palomino Ave store', 'store'), biz4 = names('the bar on Eclipse', 'bar'),
                biz5 = names('the Clinton Ave store', 'liquor'), biz6 = names('the Mirror Park store', 'store') }, points = {
            biz1 = vector4(-47.16, -1758.51, 29.42, 82.3),
            biz2 = vector4(127.55, -1299.73, 29.23, 210.0),
            biz3 = vector4(-706.07, -914.66, 19.20, 105.4),
            biz4 = vector4(-557.04, 274.30, 83.02, 175.0),
            biz5 = vector4(373.00, 328.24, 103.57, 238.5),
            biz6 = vector4(1164.85, -323.25, 69.21, 122.0),
        } },
    },

    stories = {
        -- ── Nothing but paperwork. ───────────────────────────────────────────────────────────────────────────────
        routine = {
            weight = 3,
            setup = function(c)
                local list = route(c, math.random(0, 2))
                wire(c, list, function() return true end)
            end,
        },

        -- ── An armed robbery under way at one of them. ───────────────────────────────────────────────────────────
        robbery = {
            weight = 1,
            needs = { 'biz2' },
            setup = function(c)
                local can = {}
                for i = 2, MAX do if c:point('biz' .. i) then can[#can + 1] = i end end
                local k = can[math.random(#can)]
                local list = route(c, math.random(0, 1), k)
                wire(c, list, robbery(c, k), k)
            end,
        },
    },
})
