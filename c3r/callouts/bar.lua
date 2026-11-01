--[[
    c3r callout: DISTURBANCE AT A BAR.

    Staff want police outside a bar. The report is the same every time, and the card is too: the bouncer, whoever's outside,
    and the CCTV (three units can take one each). What's really going on is one of five stories:
      drunk    thrown out and won't go: arrest, a ticket, a warning, or a taxi home
      spiked   looks drunk, but someone drugged their drink: paramedics, and the man on the CCTV may still be around
      bouncer  the bouncer went too far: the friendly one at the door is the one the CCTV shows
      wallet   one says the other took it: maybe they did, maybe it was left on the bar
      brawl    two people really fighting as you pull up: order them to stop, half the time they do, or the taser does
    It's dealt with when everyone arrested has been taken in, whoever's hurt has been seen to and the one it's about has been
    let go or got away, or the bouncer's been heard, they've been reached and every unit has left.

    Points per location: walk them out in game with /c3rplace bar (it writes the location in below).
]]

local BOUNCER_Q = {
    { id = 'c_what', label = "What's the problem?" },
    { id = 'c_who', label = 'Do you know them?' },
    { id = 'c_long', label = 'How long has this been going on?' },
    { id = 'c_tape', label = 'The CCTV shows you hitting him.', needs = { c_tape = true }, stress = true, press = true },
}
local SUBJECT_Q = {
    { id = 'c_here', label = "What's going on tonight?", stress = true },
    { id = 'c_drink', label = 'How much have you had to drink?', stress = true },
    { id = 'c_them', label = 'What happened with the other person?', stress = true, press = true },
    { id = 'c_cab', label = 'Do you want me to call you a cab?', needs = { c_ride = true } },
}
local OTHER_Q = {
    { id = 'c_saw', label = 'What happened here?', stress = true, press = true },
    { id = 'c_know', label = 'How do you know them?' },
}
local SPIKER_Q = {
    { id = 'c_bar', label = 'Were you in the bar tonight?', stress = true, press = true },
}
local CALLED = { subject = 'The customer', other = 'The other person', bouncer = 'The bouncer' }

-- Denies it until pressed `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

local function card(c)
    c:objective('bouncer', 'Talk to the bouncer', { hint = 'On the door.', blip = 'bouncer' })
    c:objective('outside', "Deal with who's outside", { blip = 'subject', hint = 'Out in front of the bar.' })
    c:objective('cctv', 'Check the CCTV', { hint = 'By the door.', blip = 'cctv' })
    c:objective('breakup', 'Break it up', { hidden = true, who = 'all', blip = { 'subject', 'other' }, hint = 'Press E beside them, or the PA with your gun out. If they will not stop, the taser will.' })
    c:objective('medic', 'Call paramedics', { hidden = true, who = 'all', hint = 'Radio for an ambulance.' })
    c:objective('taxi', 'Call a taxi', { hidden = true, who = 'all', blip = 'subject', hint = 'By radio, or G.' })
    c:objective('spiker', 'Find the man on the CCTV', { hidden = true, who = 'all', blip = 'spiker', hint = 'He may still be around.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'outside' }, who = 'all' })
end

-- Done when: the bouncer's said what the problem is, the CCTV's been looked at, they've been reached.
local function wire(c)
    c:on('act', function(who, action, arg)
        if who == 'bouncer' and action == 'ask' and arg == 'c_what' then c:done('bouncer') end
    end)
    c:on('inspect', function(clue) if clue == 'cctv' then c:set('cctv_seen', true) c:done('cctv') end end)
    c:on('contact', function(who)
        if who ~= 'subject' and who ~= 'other' then return end
        c:done('outside')
        c:blip('decide', 'subject')
    end)
    c:on('dead', function(who) if who == 'bouncer' then c:done('bouncer') end end)
end

-- Someone's hurt: the ending waits for them. shown: the card says so, and paramedics can take them.
local function hurt(c, key, shown)
    local list = c:get('hurts') or {}
    list[key] = true
    c:set('hurts', list)
    if not shown then return end
    c:patient(key)
    c:reveal('medic')
    local blips = {}
    for who in pairs(list) do blips[#blips + 1] = who end
    c:blip('medic', blips)
end

--[[ It's over when everyone arrested has been taken in, everyone hurt has been seen to, and the one it's about has been let
     go or got away; or the bouncer's been heard, the one outside reached and every unit has left.
     opts.ready() (false: being let go doesn't count yet: there's more to find out, or a taxi to wait for), opts.also() (a key:
     someone else who has to be dealt with too).
     ends(out) -> the MDT summary; out[person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' | 'pronounced' |
     'hospital' | 'treated' | 'home'; out.left = true. -> gone_with(how): the one it's about has left with someone ]]
local function resolve(c, culprit, ends, opts)
    opts = opts or {}
    local out, taken, away_for, done = {}, {}, 0, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local LET_GO = { released = true, cited = true, warning = true, fled = true, pronounced = true, hospital = true, treated = true, home = true }
    local SEEN = { hospital = true, treated = true, pronounced = true, fled = true, home = true }
    local function all_seen()
        for who in pairs(c:get('hurts') or {}) do
            if not (SEEN[out[who]] or taken[who]) then return false end
        end
        return true
    end
    local function check()
        if done or waiting() then return end
        local dealt = taken[culprit] or (LET_GO[out[culprit]] and (not opts.ready or opts.ready()))
        local also = opts.also and opts.also()
        if also and not (taken[also] or LET_GO[out[also]]) then dealt = false end
        if not ((dealt and all_seen()) or out.left) then return end
        done = true
        c:done('decide')
        c:finish(ends(out))
    end
    c:on('act', function(who, action)
        local o = c:who(who)
        if action == 'cuff' and o and o.cuffed then
            out[who] = 'arrested'
            c:custody(who)
            if who == culprit then c:done('decide') end
        elseif action == 'uncuff' and out[who] == 'arrested' then
            out[who] = nil
            c:hide('custody:' .. who)
        elseif (action == 'cite' or action == 'warn') and out[who] ~= 'arrested' then
            out[who] = action == 'cite' and 'cited' or 'warning'
        end
    end)
    c:on('custody', function(who) taken[who] = true end)
    local function seen_to(who, how)
        out[who] = how
        if all_seen() then c:done('medic') end
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if out[who] == 'dead' then seen_to(who, 'pronounced') end -- (the coroner's been)
        if (c:get('hurts') or {})[who] and not out[who] then seen_to(who, 'hospital') end -- (an ambulance the call didn't hear about)
        if who == culprit and not out[who] then out[who] = 'fled' end
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if not CALLED[who] then return end
        c:done('breakup')
        c:done('outside')
        hurt(c, who, true)
        c:dispatch(('%s is down. Paramedics needed at the scene.'):format(CALLED[who]))
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' or what == 'hospital' or what == 'treated' then seen_to(who, what) end
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or out[who] == 'pronounced' or out[who] == 'hospital' or out[who] == 'treated' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        if who == culprit and LET_GO[out[who]] and (not opts.ready or opts.ready()) then c:done('decide') end
    end)
    c:on('tick', function() -- (the hurt and the responsible are dealt with in either order: one place to look)
        check()
        local here = c:near(nil, 80.0) or c:near('subject', 80.0) or c:talking()
        if c:is_done('bouncer') and c:is_done('outside') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then
                out.left = true
                check()
            end
        else
            away_for = 0
        end
    end)
    return function(how) -- (not someone arrested or dead in the meantime)
        if out[culprit] == 'arrested' or out[culprit] == 'dead' then return end
        out[culprit] = how
        check()
    end
end

-- One person's part in the summary.
local function part(c, out, who)
    local s, how = c:name(who), out[who]
    if how == 'arrested' then return (' %s was arrested.'):format(s) end
    if how == 'cited' or how == 'warning' then return (' %s was given a %s.'):format(s, how == 'cited' and 'ticket' or 'warning') end
    if how == 'released' then return (' %s was spoken to and let go.'):format(s) end
    if how == 'fled' then return (' %s got away.'):format(s) end
    if how == 'home' then return (' %s went home in a taxi.'):format(s) end
    if how == 'hospital' then return (' %s went with paramedics.'):format(s) end
    if how == 'treated' then return (' %s was seen by paramedics at the scene.'):format(s) end
    if how == 'dead' or how == 'pronounced' then return (' %s died at the scene.'):format(s) end
    return ''
end

-- The people every story has. bouncer_lines: what they say; the CCTV's text. `culprit`: the bouncer story's own.
local function staff(c, lines, cctv)
    c:person('bouncer', { at = 'bouncer', label = 'Bouncer', male = true, model = 's_m_m_bouncer_01', age = { 28, 48 }, secret = 'clean', demeanor = 'polite',
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = BOUNCER_Q, lines = lines })
    c:clue('cctv', { at = 'cctv', label = 'CCTV', text = cctv })
    for i, scene in ipairs({ 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_DRINKING', 'WORLD_HUMAN_STAND_MOBILE' }) do -- (watching: they're no part of it)
        c:person('crowd' .. i, { at = 'crowd' .. i, label = 'Customer', secret = 'clean', scene = scene })
    end
end

local function outside(c, spec, lines)
    lines.where = lines.where or { "Nowhere. I'm just... here." }
    c:person('subject', { at = 'subject', label = 'Customer', male = spec.male, age = spec.age or { 22, 45 }, secret = spec.secret or 'clean', demeanor = spec.demeanor or 'rude',
        items = spec.items or {}, flags = spec.flags, injured = spec.injured, scene = spec.scene or 'WORLD_HUMAN_STAND_IMPATIENT', questions = SUBJECT_Q, lines = lines })
end

local function second(c, spec, lines)
    lines.where = lines.where or { "I'm not going anywhere." }
    c:person('other', { at = 'other', label = spec.label or 'Customer', male = spec.male, age = spec.age or { 22, 45 }, secret = spec.secret or 'clean', demeanor = spec.demeanor or 'nervous',
        items = spec.items or {}, scene = 'WORLD_HUMAN_STAND_MOBILE', questions = spec.questions or OTHER_Q, lines = lines })
end

Callout({
    id = 'bar',
    name = 'Disturbance at a bar',
    voice = 'call_bar', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        'Bar staff report a disturbance outside. Someone needs moving on.',
        "Caller says there's trouble outside the bar and it's getting out of hand.",
        'Customer causing a problem at a bar. Staff want police.',
    },
    -- The points each location needs, in the order /c3rplace bar walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it).
    -- Skip the optional ones with Z in /c3rplace: without a crowd nobody's watching; without `spiker` he's gone.
    points = {
        { 'bouncer', 'The bouncer, on the door.' },
        { 'subject', 'A customer outside, on the pavement a little way from the door.' },
        { 'other', 'A second customer, 3 to 5 m from the first: they can reach each other.' },
        { 'cctv', 'The CCTV: a spot on the wall by the door.' },
        { 'crowd1', 'Someone watching, out of the way.', optional = true },
        { 'crowd2', 'Someone else watching.', optional = true },
        { 'crowd3', 'Someone else watching.', optional = true },
        { 'spiker', 'The man from the bar: down the road, or by a car, 30 to 80 m off.', optional = true },
    },
    -- Add more with /c3rplace bar in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Panorama Dr', at = vector3(1991.75, 3053.24, 47.21), streets = { spiker = 'Route 68' }, points = {
            bouncer = vector4(1991.75, 3053.24, 47.21, 340.4),
            subject = vector4(1994.67, 3056.63, 47.06, 79.0),
            other = vector4(1993.45, 3057.77, 47.06, 185.8),
            cctv = vector4(1989.55, 3054.60, 47.22, 316.4),
            crowd1 = vector4(2003.22, 3052.53, 47.21, 26.8),
            crowd2 = vector4(2001.74, 3051.48, 47.21, 20.3),
            crowd3 = vector4(2002.47, 3052.04, 47.21, 20.1),
            spiker = vector4(1974.99, 3023.60, 47.06, 48.0),
        } },
        { street = 'Paleto Blvd', at = vector3(-301.52, 6254.26, 31.53), points = {
            bouncer = vector4(-301.52, 6254.26, 31.53, 240.4),
            subject = vector4(-293.78, 6250.79, 31.33, 184.1),
            other = vector4(-293.50, 6248.63, 31.30, 342.3),
            cctv = vector4(-298.80, 6257.56, 31.50, 50.3),
            crowd1 = vector4(-293.37, 6259.66, 31.49, 143.4),
            crowd2 = vector4(-294.22, 6259.49, 31.49, 167.0),
            spiker = vector4(-299.28, 6283.32, 31.49, 265.5),
        } },
        { street = 'Eclipse Blvd', at = vector3(-557.04, 274.30, 83.02), streets = { cctv = 'Milton Rd', crowd1 = 'Milton Rd', crowd2 = 'Milton Rd', crowd3 = 'Milton Rd', spiker = 'Milton Rd' }, points = {
            bouncer = vector4(-557.04, 274.30, 83.02, 193.5),
            subject = vector4(-553.53, 270.84, 82.97, 243.5),
            other = vector4(-552.45, 270.10, 82.96, 72.6),
            cctv = vector4(-554.53, 274.02, 83.01, 350.2),
            crowd1 = vector4(-549.42, 275.33, 83.00, 148.9),
            crowd2 = vector4(-548.82, 274.76, 82.99, 152.2),
            crowd3 = vector4(-548.17, 273.79, 82.97, 128.2),
            spiker = vector4(-554.37, 294.46, 83.08, 48.4),
        } },
    },

    stories = {
        -- ── A drunk. ─────────────────────────────────────────────────────────────────────────────────────────────
        drunk = {
            weight = 3,
            setup = function(c)
                staff(c, {
                    c_what = { "Cut off an hour ago. Then he tried to climb back in through the fire door. He won't go, and he's scaring the customers." },
                    c_who = { "Never seen him before tonight. He's had enough for all of us." },
                    c_long = { "An hour. It's getting louder." },
                }, 'A man at the bar, swaying, being refused a drink. He knocks over a stool, argues with staff and is walked out, slowly. Nobody hits anybody.')
                outside(c, { male = true, secret = 'drunk', demeanor = 'chatty' }, {
                    c_here = { { "I'm fine. I'm absolutely fine. I just want one more. One. That guy's a... he's a nice guy, actually.", set = { c_ride = 'yes' } } },
                    c_drink = { { "Two beers. Two. Maybe the... six. It's my friend's... I don't know how I'm getting home.", set = { c_ride = 'yes' } } },
                    c_them = { "What other person? There's a lot of people." },
                    c_cab = { { "A cab? You'd do that? You're a good cop. You're the best cop.", set = { c_cabbed = 'yes' } } },
                })
                second(c, { label = 'Customer' }, {
                    c_saw = { "He just won't leave. He's not hurting anyone. He tried to hug me." },
                    c_know = { "I don't. I just wanted a smoke." },
                })
                card(c)
                wire(c)
                local gone_with = resolve(c, 'subject', function(out)
                    return 'Drunk and disorderly outside a bar.' .. part(c, out, 'subject')
                end, { ready = function() return not c:get('cab') end }) -- (offered a cab: it's the cab that ends it)
                c:on('fact', function(_, fact)
                    if fact ~= 'c_cabbed' then return end
                    c:set('cab', true)
                    c:fare('subject')
                    c:reveal('taxi')
                end)
                c:on('act', function(who, action)
                    if who ~= 'subject' or action ~= 'cuff' or not c:who('subject').cuffed or not c:get('cab') then return end
                    c:set('cab', false) -- (changed their mind: no cab now)
                    c:fare('subject', true)
                    c:done('taxi')
                end)
                c:on('service', function(kind)
                    if kind ~= 'taxi' then return end
                    c:done('taxi')
                    c:set('cab', false)
                    gone_with('home')
                end)
            end,
        },

        -- ── Their drink was spiked. ──────────────────────────────────────────────────────────────────────────────
        spiked = {
            weight = 2,
            setup = function(c)
                staff(c, {
                    c_what = { "She's all over the place. I put her out for her own good. Her friend says she's only had one." },
                    c_who = { "No. First time here. She came in fine." },
                    c_long = { "Twenty minutes? She went downhill fast." },
                }, 'Two women at a table, one drink each. One goes to the bathroom. A man leans over and passes his hand across her glass, then walks out. Twenty minutes later she can hardly stand.')
                outside(c, { male = false, age = { 21, 34 }, secret = 'drugs', demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_MOBILE', flags = {} }, {
                    drugsuse = { "No. I don't do that. I don't... why can't I feel my hands?" },
                    eyes = { "No. Nothing. I've had one drink." },
                    meds = { "No. Nothing." },
                    c_here = { "Can't... I don't feel right. Everything's slow." },
                    c_drink = { { "One. I only had one. I swear. I don't feel... this isn't...", set = { c_one = 'yes' } } },
                    c_them = { "She's my friend. Where is she? Is she here?" },
                })
                second(c, { male = false, age = { 21, 34 } }, {
                    c_saw = { { "She's had ONE drink. One! I was with her. Somebody's put something in it. Look at her!", set = { c_one = 'yes' } } },
                    c_know = { "She's my best friend. Please, she needs a doctor." },
                })
                c:person('spiker', { at = 'spiker', label = 'Man', male = true, age = { 30, 48 }, secret = 'nervous', demeanor = 'polite', items = { 'Small unlabelled bottle of clear liquid' },
                    scene = 'WORLD_HUMAN_SMOKING', questions = SPIKER_Q, lines = {
                        c_bar = cracks(2, { "Bar? No. I've been out here all night." },
                            { { "...It was a joke. It wears off. I was only going to help her home.", set = { c_admit = 'yes' } } },
                            { "I told you. It was a joke." }),
                        where = { "Waiting for someone." },
                    } })
                card(c)
                wire(c)
                c:on('build', function() -- (it's what's in her, and it's nothing she'd run from)
                    local o = c:who('subject')
                    o.swab, o.ran = 'Benzodiazepines', true
                end)
                local told = false
                local function needs_help()
                    if told then return end
                    told = true
                    hurt(c, 'subject', true)
                    c:dispatch('This does not look like drink. Get paramedics to the customer.')
                end
                c:on('fact', function(_, fact) if fact == 'c_one' then needs_help() end end)
                c:on('act', function(who, action) if who == 'subject' and (action == 'breath' or action == 'drugs') then needs_help() end end)
                c:on('inspect', function(clue)
                    if clue ~= 'cctv' then return end
                    needs_help()
                    c:reveal('spiker')
                    if c:who('spiker') then c:set('wanted', true) end
                end)
                c:on('contact', function(who) if who == 'spiker' then c:reveal('spiker') c:done('spiker') end end)
                resolve(c, 'subject', function(out)
                    local text = 'Reported as a drunk customer: her drink had been spiked.' .. part(c, out, 'subject')
                    local o = c:who('spiker')
                    if o and out.spiker == 'arrested' then return text .. part(c, out, 'spiker') end
                    return text .. ' The man who did it was not arrested.'
                end, { also = function() return c:get('wanted') and 'spiker' or nil end }) -- (seen on the CCTV: go and get him)
            end,
        },

        -- ── The bouncer did it. ──────────────────────────────────────────────────────────────────────────────────
        bouncer = {
            weight = 2,
            setup = function(c)
                staff(c, {
                    c_what = { "He was kicking off, so I walked him out. He tripped on the step. They do that, when they've had a few." },
                    c_who = { "Trouble. That's who. Ask anyone." },
                    c_long = { "Ten minutes. He'll be fine." },
                    c_tape = cracks(2, { "That's him coming at me. You can't see it from that angle." },
                        { { "...Alright. I lost it. Third time this week somebody's got in my face.", set = { c_admit = 'yes' } } },
                        { "I told you. I lost it." }),
                }, 'The bouncer has a customer by the collar, throws him down the step and hits him twice on the ground, then looks up at the camera.')
                outside(c, { male = true, injured = true, demeanor = 'nervous' }, {
                    c_here = { "He threw me out. Then he... my head. Is it bad?" },
                    c_drink = { "Two. I only came back for my coat." },
                    c_them = { "The bouncer. I didn't do anything. I asked for my coat." },
                })
                second(c, {}, {
                    c_saw = cracks(2, { "I don't want trouble. I drink here." },
                        { { "He fell. After the bouncer threw him. And then he hit him, on the ground. Twice.", set = { c_admit = 'yes' } } },
                        { "I told you what I saw." }),
                    c_know = { "I've seen him here. Harmless. He only asked for his coat." },
                })
                card(c)
                wire(c)
                local proof = false
                c:on('build', function() hurt(c, 'subject') end) -- (on the card once a unit's there: the ending waits regardless)
                c:on('tick', function()
                    if not (c:near('subject', 15.0) or c:near('other', 15.0)) then return end
                    c:done('outside')
                    hurt(c, 'subject', true)
                end)
                local function evidence()
                    proof = true
                    c:blip('decide', 'bouncer')
                    local o = c:who('bouncer')
                    if o then
                        o.facts.c_tape = 'yes'
                        c:questions('bouncer')
                    end
                end
                c:on('inspect', function(clue) if clue == 'cctv' then evidence() end end)
                c:on('fact', function(who, fact) if who == 'other' and fact == 'c_admit' then evidence() end end)
                resolve(c, 'bouncer', function(out)
                    local text = 'Assault by a bouncer outside a bar.' .. part(c, out, 'subject') .. part(c, out, 'bouncer')
                    if c:get('cctv_seen') and out.bouncer == 'arrested' then text = text .. ' Recorded: the CCTV.' end
                    return text
                end, { ready = function() return proof end }) -- (telling him he's free to go before you know what he did isn't an ending)
            end,
        },

        -- ── A wallet. ────────────────────────────────────────────────────────────────────────────────────────────
        wallet = {
            weight = 2,
            setup = function(c)
                local took = math.random() < .5
                staff(c, {
                    c_what = { "That one says the other took his wallet. They've been going at it for ten minutes. I want them both gone." },
                    c_who = { "Regulars, the pair of them. Usually." },
                    c_long = { "Ten minutes. Long enough." },
                }, took and 'One man takes a wallet from the other\'s jacket on the back of a chair and puts it in his own pocket. It is clear enough.'
                    or 'One man pays, leaves his wallet on the bar and walks away. Staff put it under the counter. Nobody else goes near it.')
                outside(c, { male = true, secret = took and 'nervous' or 'clean', items = took and { "Wallet with someone else's ID in it" } or {} }, {
                    c_here = { "He's calling me a thief! In front of everyone!" },
                    c_drink = { "A few. That's not the point." },
                    c_them = took and cracks(3, { "I never touched it." },
                        { { "...It was just sitting there. I was going to give it back.", set = { c_admit = 'yes' } } },
                        { "I told you. I was going to give it back." })
                        or { "He's lost his wallet, so it's me? Search me. Go on." },
                    explain = { "...That's not mine. I found it. I was going to hand it in." },
                })
                second(c, { label = 'Customer', male = true, demeanor = 'rude' }, {
                    c_saw = { "He took my wallet! Right off my chair! Search him!" },
                    c_know = { "We drink together. I thought I knew him." },
                })
                card(c)
                wire(c)
                resolve(c, 'subject', function(out)
                    local what = took and 'A stolen wallet outside a bar.' or 'A wallet reported stolen outside a bar: it had been left on the bar.'
                    return what .. part(c, out, 'subject') .. part(c, out, 'other')
                end)
            end,
        },

        -- ── A fight. ─────────────────────────────────────────────────────────────────────────────────────────────
        brawl = {
            weight = 3,
            setup = function(c)
                local first = math.random() < .5
                staff(c, {
                    c_what = { "Those two have been going at it since last orders. I told them to take it outside. I didn't mean do this." },
                    c_who = { "Friends, about an hour ago." },
                    c_long = { "A few minutes. It's not stopping." },
                }, first and 'The man in the first seat turns round and punches the other one without a word. Everything after that is both of them.'
                    or 'The second man stands up, says something and shoves the first one off his stool. Everything after that is both of them.')
                outside(c, { male = true, secret = 'drunk', demeanor = 'rude' }, {
                    c_here = { "He started it! Did you see him? He started it!" },
                    c_drink = { "Enough. So what?" },
                    c_them = first and cracks(2, { "He called me a liar. Ask anyone." },
                        { { "...I hit him first. Alright? I'd do it again.", set = { c_admit = 'yes' } } },
                        { "I said. I hit him first." })
                        or { "He put me on the floor! What was I supposed to do?" },
                })
                second(c, { male = true, secret = 'drunk', demeanor = 'rude' }, {
                    c_saw = not first and cracks(2, { "He swung at me! You've got cameras, go and look!" },
                        { { "...Alright. I shoved him. He had it coming.", set = { c_admit = 'yes' } } },
                        { "I said. I shoved him." })
                        or { "He swung at me! You've got cameras, go and look!" },
                    c_know = { "Twenty years. Twenty years, and now this." },
                })
                card(c)
                wire(c)
                local stopped, ordered, left = false, false, 90
                local function stop(line)
                    if stopped then return end
                    stopped = true
                    c:done('breakup')
                    c:done('outside')
                    if c:who('subject') then c:task('subject', 'surrender') end
                    if c:who('other') then c:task('other', 'surrender') end
                    if line then c:say('subject', line) end
                    c:note('The fight was broken up')
                end
                local function order()
                    if stopped or ordered then return end
                    ordered = true
                    if math.random() < .5 then stop("Alright! Alright! I'm done!")
                    else c:say('subject', "I'm not finished with him!") end
                end
                c:on('build', function()
                    c:task('subject', 'brawl', 'other')
                    c:task('other', 'brawl', 'subject')
                end)
                c:on('tick', function() if c:near('subject', 60.0) then c:reveal('breakup') end end)
                c:on('hail', function(who) if who == 'subject' or who == 'other' then order() end end)
                c:on('stunned', function(who)
                    if who == 'subject' or who == 'other' then
                        c:set('tased', true)
                        stop("Okay! Okay! I'm done!")
                    end
                end)
                c:on('dead', function(who) if who == 'subject' or who == 'other' then stop() end end)
                local function beaten(key) -- (a ped just made reads 0: not beaten, not there yet)
                    local h = c:health(key)
                    return h and h > 100 and h < 120
                end
                c:on('tick', function()
                    if stopped then return end
                    if c:near('subject', 120.0) then left = left - 1 end -- (it's going on when someone's there to see it)
                    local hit = beaten('other') and 'other' or beaten('subject') and 'subject'
                    if left > 0 and not hit then return end
                    hit = hit or 'other'
                    stop()
                    c:collapse(hit)
                    hurt(c, hit, true)
                    c:dispatch('One of them is down. Paramedics needed at the scene.')
                end)
                resolve(c, 'subject', function(out)
                    local text = 'A fight outside a bar.' .. part(c, out, 'subject') .. part(c, out, 'other')
                    if c:get('tased') then text = text .. ' A taser was used to stop it.' end
                    if c:get('cctv_seen') then text = text .. (' The CCTV shows %s threw the first punch.'):format(c:name(first and 'subject' or 'other')) end
                    return text
                end)
            end,
        },
    },
})
