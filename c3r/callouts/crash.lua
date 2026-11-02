--[[
    c3r callout: VEHICLE COLLISION.

    A collision, and nobody on the phone could say how bad. The report is the same every time, and the card is too: the
    caller, the drivers and the cars (three units can take one each). What it really is, is one of four stories:
      bump     a small rear-end, nobody hurt, and the one behind was on their phone. Settled, both drive off
      sugar    they look drunk and blow 0.00: a diabetic low at the wheel, and they get worse until someone sees it
      swap     the partner says she drove. He did, drunk, and she only says so out of his earshot
      pileup   a van into stopped traffic: people hurt and one bleeding, a clock on them, a fuel leak, the road to clear
    It's dealt with when whoever's responsible has been dealt with, everyone hurt has been seen to, the road's clear and
    traffic's moving again; or the caller's been heard and every unit has left.

    Points per location: walk them out in game with /c3rplace crash (it writes the location in below).
]]

-- Spawn names, makes and names as hitrun.lua's and hazard.lua's, checked against the game's vehicle list; paint ids
-- against docs.fivem.net's vehicle colours.
local CARS = {
    { model = 'asea', make = 'Declasse', name = 'Asea' },
    { model = 'premier', make = 'Declasse', name = 'Premier' },
    { model = 'stanier', make = 'Vapid', name = 'Stanier' },
    { model = 'emperor', make = 'Albany', name = 'Emperor' },
    { model = 'tailgater', make = 'Obey', name = 'Tailgater' },
    { model = 'fugitive', make = 'Cheval', name = 'Fugitive' },
    { model = 'intruder', make = 'Karin', name = 'Intruder' },
}
local PAINTS = { { 'Black', 0 }, { 'Silver', 4 }, { 'Red', 27 }, { 'Dark blue', 62 }, { 'White', 111 } }

local CALLER_Q = {
    { id = 'c_what', label = 'What did you see?' },
    { id = 'c_driver', label = 'Did you see who was driving?' },
    { id = 'c_hurt', label = 'Is anyone hurt?' },
}
local DRIVER_Q = {
    { id = 'c_what', label = 'What happened?', stress = true, press = true },
    { id = 'c_driving', label = 'Were you driving?', stress = true, press = true },
    { id = 'c_fault', label = 'Whose fault was it?', stress = true, press = true },
    { id = 'c_drink', label = 'Have you had anything to drink?', stress = true, press = true },
    { id = 'c_phone', label = 'Were you looking at your phone?', needs = { c_phone = true }, stress = true, press = true },
    { id = 'c_tired', label = 'When did you last sleep?', needs = { c_tired = true }, stress = true, press = true },
}
local SICK_AFTER = 240 -- s from the first unit arriving until the diabetic collapses
local BLEEDS_FOR = 300 -- s from the first unit arriving until the one bleeding dies, unless someone holds the wound
local OUT_OF_SIGHT = 60 -- s a driver gets to drive out of sight of the units, before they're removed anyway
local TOWS = 2 -- (in the pile-up: a tow is two minutes, one truck at a time; the rest the game tidies after the call)
local LOW = 'Conscious, just. Sweating, cold, pulse racing, no sense in what they say. No smell of drink. Blood sugar, not injury: they need paramedics.'
local CRITICAL = 'Barely conscious, breathing fast and shallow, and bleeding hard from the thigh. Apply pressure, now.'
local HURT = 'Awake and in pain. A broken arm, maybe ribs. Bleeding a little. They need paramedics, but they will keep.'

-- Denies it until pressed `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

local function card(c, medic)
    c:objective('caller', 'Talk to the caller', { hint = 'They stopped to help.', blip = 'caller' })
    c:objective('drivers', 'Talk to the drivers', { hint = 'Keep them apart if they do not agree.', blip = { 'first', 'second' } })
    c:objective('cars', 'Check the vehicles', { hint = 'Damage, and what can be seen inside.', blip = { 'first_car', 'second_car' } })
    c:objective('who', 'Find out who was really driving', { hidden = true, who = 'all', blip = 'third', hint = 'Talk to them out of each other\'s earshot.' })
    c:objective('ill', "Find out what's wrong with them", { hidden = true, who = 'all', blip = 'first', hint = 'Breath test them, search them, and check their car.' })
    c:objective('medic', medic or 'Get the hurt to hospital', { hidden = true, who = 'all', hint = 'First aid: E beside them. Radio for an ambulance: paramedics see to anyone hurt near where you called.' })
    c:objective('hold', 'Hold traffic', { hidden = true, who = 'all', hint = 'Radio it: "hold traffic".' })
    c:objective('fire', 'Call the fire department', { hidden = true, blip = 'first_car', hint = 'By radio, or G. Keep everyone clear of the fuel.' })
    c:objective('crew', 'Call the DOT crew', { hidden = true, blip = 'debris', hint = 'By radio, or G. It takes a crew to clear this road.' })
    c:objective('tow', 'Get the cars towed', { hidden = true, hint = 'Stand beside one: by radio, or G. One truck at a time.' })
    c:objective('release', 'Release traffic', { hidden = true, who = 'all', hint = 'The road is clear. Radio it: "release traffic".' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'drivers' }, who = 'all' })
end

-- Someone's hurt: the ending waits for them, and the card says so. An ambulance takes them, down or not.
local function hurt(c, key)
    local list = c:get('hurts') or {}
    list[key] = true
    c:set('hurts', list)
    c:patient(key)
    local blips = {}
    for who in pairs(list) do blips[#blips + 1] = who end
    c:blip('medic', blips)
    c:reveal('medic')
end

-- Gives them a fact from elsewhere, and shows the officer talking to them what it opens.
local function learns(c, who, fact)
    local o = c:who(who)
    if o then
        o.facts[fact] = 'yes'
        c:questions(who)
    end
end

--[[ Done when: the caller's said what they saw, each driver's been asked what happened (o.drivers) or can't be, both cars
     have been looked at. A unit close to anyone down (o.hurts) puts them on the card; a look at a wreck (o.wrecks) puts the
     tow on it. -> heard(key), for someone who can't be asked any more. ]]
local function wire(c, o)
    local asked, looked, wreck, said, seen = {}, {}, {}, false, false
    local hurts = {}
    for _, key in ipairs(o.hurts or {}) do hurts[key] = true end
    c:set('hurts', hurts)
    c:blip('drivers', o.drivers)
    for _, key in ipairs(o.wrecks or {}) do wreck[key] = true end
    if o.wrecks then c:blip('tow', o.wrecks) end
    local function heard(key)
        asked[key] = true
        for _, k in ipairs(o.drivers) do if not asked[k] then return end end
        c:done('drivers')
    end
    c:on('act', function(who, action, arg)
        if action ~= 'ask' or arg ~= 'c_what' then return end
        if who == 'caller' then c:done('caller') else heard(who) end
    end)
    local function checked(key)
        if key ~= 'first_car' and key ~= 'second_car' then return end
        looked[key] = true
        if looked.first_car and looked.second_car then c:done('cars') end
    end
    c:on('inspect', function(clue)
        if wreck[clue] then c:reveal('tow') end
        checked(clue)
    end)
    c:on('towed', checked) -- (gone before anyone looked, and its clue with it)
    c:on('dead', function(who) if who == 'caller' then c:done('caller') else heard(who) end end)
    c:on('gone', function(who) if who == 'caller' then c:done('caller') else heard(who) end end)
    c:on('tick', function()
        if not said and c:near('caller', 30.0) then
            said = true
            c:say('caller', 'Over here! I saw it happen!')
        end
        if seen then return end
        for _, key in ipairs(o.hurts or {}) do
            if c:near(key, 15.0) then
                seen = true
                for _, k in ipairs(o.hurts) do hurt(c, k) end
                if o.seen then o.seen() end
            end
        end
    end)
    return heard
end

--[[ It's over when everyone in o.must has been dealt with (taken in, a ticket or a warning, let go, got away, or seen to by
     paramedics), everyone hurt has been seen to, enough of o.wrecks have gone (o.tows of them, or all), the jobs in o.jobs
     are done, nobody's holding traffic, and everyone in o.drive has driven off in their own car; or the caller's been heard
     and every unit has left. o.drive = { [person] = car key }: they go once let go, or when there's nothing else left to
     do. o.ends(out, care) -> the MDT summary; out = { [person] = 'arrested' |
     'released' | 'cited' | 'warning' | 'fled', left = true }; care = { [person] = 'hospital' | 'treated' | 'pronounced' |
     'removed' | 'taken' }. ]]
local function resolve(c, o)
    local out, taken, care, died, off, left = {}, {}, {}, {}, {}, {}
    local road_left, wrecks, away_for, done, was_held = 0, {}, 0, false, false
    for _, key in ipairs(o.wrecks or {}) do wrecks[key] = true end
    road_left = o.tows or (o.wrecks and #o.wrecks) or 0
    local LET_GO = { released = true, cited = true, warning = true, fled = true }
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function dealt(k) return taken[k] or LET_GO[out[k]] or care[k] end
    local function all(test)
        for _, key in ipairs(o.must) do if not test(key) then return false end end
        return true
    end
    local function clear()
        if road_left > 0 then return false end
        for _, id in ipairs(o.jobs or {}) do if not c:is_done(id) then return false end end
        return true
    end
    -- What the summary adds: anyone else dealt with, and how everyone hurt came out of it.
    local function report()
        local text, more, hurts = o.ends(out, care), {}, {}
        for k, v in pairs(out) do
            if k ~= 'left' and not text:find(c:name(k), 1, true) then
                if v == 'arrested' then more[#more + 1] = (' %s was arrested.'):format(c:name(k))
                elseif v == 'fled' then more[#more + 1] = (' %s ran and got away.'):format(c:name(k))
                elseif v == 'cited' then more[#more + 1] = (' %s was given a ticket.'):format(c:name(k))
                elseif v == 'warning' then more[#more + 1] = (' %s was given a warning.'):format(c:name(k)) end
            end
        end
        local HOW = { hospital = '%s was taken to hospital.', treated = '%s was treated by paramedics at the scene.',
            pronounced = '%s died at the scene.', removed = '%s was removed from the scene.' }
        for k in pairs(c:get('hurts') or {}) do
            local how = care[k] or 'none'
            if how ~= 'taken' then hurts[#hurts + 1] = ' ' .. (HOW[how] or '%s was not seen by paramedics.'):format(c:name(k)) end
        end
        table.sort(more)
        table.sort(hurts)
        return text .. table.concat(more) .. table.concat(hurts)
    end
    local function let_drive(who)
        local car = o.drive and o.drive[who]
        if not car or left[who] then return end -- ponytail: an arrested driver's car stays put; the game tidies it after the call
        off[who] = 0 -- (stopped again at the car, they set off again)
        c:task(who, 'drive', { car = car })
    end
    -- Driving off: gone for good once they're out of sight, or a minute on. Wandering, they'd go round the block for ever.
    local function drive_away()
        for who, secs in pairs(off) do
            if not left[who] and not c:talking(who) then
                off[who] = secs + 1
                if secs >= OUT_OF_SIGHT or (secs >= 5 and not c:near(who, 80.0)) then
                    left[who] = true
                    c:remove(who, o.drive[who])
                end
            end
        end
    end
    local function check()
        if done or waiting() then return end
        if not out.left then
            local seen_to = true
            for k in pairs(c:get('hurts') or {}) do seen_to = seen_to and care[k] ~= nil end
            if seen_to and next(c:get('hurts') or {}) then c:done('medic') end -- (the diabetic isn't on the list until someone sees it)
            local settled = all(dealt)
            if settled then c:done('decide') end
            -- (a ticket doesn't end the talking: they only drive off once it does)
            if not (settled and seen_to and clear()) or c:held() or c:talking() then return end
            local gone = true
            for who in pairs(o.drive or {}) do -- (nothing else to do: anyone not let go yet goes now, and it ends when they have)
                if not (left[who] or care[who] or out[who] == 'arrested' or out[who] == 'fled') then
                    gone = false
                    if not off[who] then let_drive(who) end
                end
            end
            if not gone then return end
        end
        done = true
        c:done('decide')
        for who in pairs(off) do if not left[who] then c:remove(who, o.drive[who]) end end
        c:finish(report())
    end
    c:on('act', function(who, action)
        local p = c:who(who)
        if action == 'cuff' and p and p.cuffed then
            out[who] = 'arrested'
            c:custody(who)
        elseif action == 'uncuff' and out[who] == 'arrested' then
            out[who] = nil
            c:hide('custody:' .. who)
        elseif (action == 'cite' or action == 'warn') and out[who] ~= 'arrested' then
            out[who] = action == 'cite' and 'cited' or 'warning'
        end
    end)
    c:on('custody', function(who)
        taken[who] = true
        care[who] = care[who] or 'taken'
    end)
    c:on('aid', function(who, what)
        if what == 'hospital' or what == 'treated' or what == 'pronounced' then
            care[who] = what
            if out[who] == 'arrested' and what ~= 'treated' then
                taken[who] = true
                c:hide('custody:' .. who)
            end
        end
    end)
    c:on('dead', function(who) died[who] = true end)
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if not care[who] then care[who] = died[who] and 'pronounced' or 'removed' end
    end)
    c:on('contact_ended', function(who, outcome)
        if outcome == 'fled' then
            out[who] = 'fled'
            care[who] = care[who] or 'taken' -- (out of reach: nobody can see to them now)
            return
        end
        if (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        if LET_GO[out[who]] then let_drive(who) end
    end)
    c:on('towed', function(key)
        if not wrecks[key] then return end
        wrecks[key] = nil
        road_left = road_left - 1
        if road_left <= 0 then c:done('tow') end
    end)
    c:on('tick', function() -- (the road clearing and the people being dealt with come in either order: one place to look)
        drive_away()
        was_held = was_held or c:held()
        if clear() and was_held then
            if c:held() then c:reveal('release') else c:done('release') end
        end
        check()
        local here = c:near(nil, 80.0) or c:talking()
        if c:is_done('caller') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then
                out.left = true
                check()
            end
        else
            away_for = 0
        end
    end)
end

-- What it says on the MDT about them: 'an admission'...
local function recorded(list)
    return list[1] and (' Recorded: ' .. table.concat(list, ', ') .. '.') or ''
end

-- What happened to the one it's about, when it isn't an arrest.
local function other_end(c, who, v, role)
    local n = c:name(who)
    if v == 'fled' then return ('%s, %s, ran and got away.'):format(n, role) end
    if v == 'cited' then return ('%s, %s, was given a ticket.'):format(n, role) end
    if v == 'warning' then return ('%s, %s, was given a warning.'):format(n, role) end
    if v == 'released' then return ('%s, %s, was spoken to and let go.'):format(n, role) end
end

local function caller(c, lines)
    c:person('caller', { at = 'caller', label = 'Caller', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = CALLER_Q, lines = lines })
end

-- A car in the crash, picked per call. The doors are open to whoever has to drive it away.
local function car(c, key, damage, owner, label)
    local m, paint = CARS[math.random(#CARS)], PAINTS[math.random(#PAINTS)]
    c:vehicle(key, { at = key, model = m.model, make = m.make, name = m.name, color = paint[1], paint = paint[2],
        owner = owner, locked = false, damage = damage, label = label })
end

Callout({
    id = 'crash',
    name = 'Vehicle collision',
    voice = 'call_crash', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        'Caller reports a collision. Vehicles stopped in the road.',
        'Passing motorist reports an accident. Could not say how bad.',
        'Caller heard a bang and says cars are blocking the lane.',
    },
    -- The points each location needs, in the order /c3rplace crash walks you through them ('car': sit in a car). The first is
    -- where the call is (units are on scene within Config.Callouts.arrive m of it). Pick a straight stretch of road: the
    -- same two cars are a bump in one story and a wreck in another, so put them nose to tail, a car's length apart.
    points = {
        { 'scene', 'The middle of the crash: stand in the lane, between where the two cars will be.' },
        { 'first_car', 'The car behind, stopped in the lane, nose towards the other car. Sit in a car parked there.', 'car' },
        { 'second_car', 'The car in front, stopped in the lane. Sit in a car parked there.', 'car' },
        { 'first', 'The driver of the car behind: beside it, on the side away from traffic. They may be lying here hurt.' },
        { 'second', 'The driver of the car in front: beside it, on the side away from traffic. They may be lying here hurt.' },
        { 'caller', 'The motorist who called: on the pavement or the verge, close by.' },
        { 'third', 'Someone else in it: on foot, a few metres from the cars, clear of traffic.' },
        { 'third_car', 'A van that ploughed into the back of it all: behind the first car, at an angle. Sit in a car parked there. Without this point the pile-up never comes up here.', 'car', optional = true },
        { 'fourth_car', 'One more car caught up in it: slewed across the road or the verge. Sit in a car parked there.', 'car', optional = true },
    },
    -- Add more with /c3rplace crash in game (it writes them here). This one is a rough placeholder.
    locations = {
        { street = 'Route 68', at = vector3(662.04, 2716.97, 41.36), points = {
            scene = vector4(662.04, 2716.97, 41.36, 69.0),
            first_car = vector4(665.31, 2715.73, 41.20, 69.0),
            second_car = vector4(658.77, 2718.21, 41.20, 69.0),
            first = vector4(667.08, 2720.40, 41.40, 200.0),
            second = vector4(660.54, 2722.90, 41.40, 200.0),
            caller = vector4(653.98, 2727.83, 42.00, 256.7),
            third = vector4(671.07, 2721.03, 41.40, 200.0),
            third_car = vector4(670.46, 2713.78, 41.20, 80.0),
        } },
        { street = 'Senora Fwy', at = vector3(1591.95, 6417.94, 25.56), points = {
            scene = vector4(1591.95, 6417.94, 25.56, 84.9),
            first_car = vector4(1596.98, 6418.50, 25.45, 90.9),
            second_car = vector4(1592.59, 6419.16, 25.16, 47.8),
            first = vector4(1599.62, 6416.18, 26.10, 213.4),
            second = vector4(1589.92, 6420.44, 25.39, 127.5),
            caller = vector4(1601.64, 6421.77, 26.03, 167.3),
            third = vector4(1607.44, 6420.64, 26.42, 109.4),
            third_car = vector4(1596.29, 6416.20, 25.48, 30.0),
            fourth_car = vector4(1581.23, 6414.88, 24.72, 107.6),
        } },
        { street = 'Hawick Ave', at = vector3(-76.88, -108.43, 57.87), streets = { first_car = 'Las Lagunas Blvd', first = 'Las Lagunas Blvd' }, points = {
            scene = vector4(-76.88, -108.43, 57.87, 218.7),
            first_car = vector4(-80.11, -104.98, 57.47, 188.7),
            second_car = vector4(-80.88, -109.34, 57.47, 137.0),
            first = vector4(-78.46, -102.57, 57.87, 320.7),
            second = vector4(-81.73, -112.94, 57.89, 182.0),
            caller = vector4(-60.37, -94.15, 57.76, 129.5),
            third = vector4(-57.63, -93.71, 57.80, 101.6),
            third_car = vector4(-76.69, -106.38, 57.46, 110.1),
            fourth_car = vector4(-101.86, -122.02, 57.30, 117.8),
        } },
    },

    stories = {
        -- ── A small rear-end, and the one behind was on their phone. ─────────────────────────────────────────────
        bump = {
            weight = 4,
            setup = function(c)
                caller(c, {
                    c_what = { "The one behind ran into the back of the other one. Not hard. They've been going at it about whose fault it is ever since." },
                    c_driver = { { "The one behind? Looking down the whole way up to the lights, I'd bet a phone.", set = { c_tip = 'yes' } } },
                    c_hurt = { 'No. Only their pride.' },
                })
                c:person('first', { at = 'first', label = 'First driver', secret = math.random() < .3 and 'suspended' or 'clean', demeanor = 'rude',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = DRIVER_Q, lines = {
                        c_what = { 'They stopped dead. For nothing. I barely touched them.', "It's a scratch. Can we get on with this?" },
                        c_driving = { 'Yes. Obviously.' },
                        c_fault = cracks(3, { 'Theirs. Who brakes like that?', 'Not mine. Ask anyone.' },
                            { { "...Alright, I wasn't watching. A second, that's all. I looked down.", set = { c_admit = 'yes' } } },
                            { "I said. I looked down." }),
                        c_drink = { 'At this time of day? No.' },
                        c_phone = cracks(2, { 'My phone? It was in the holder.', "It's on the floor because of the crash." },
                            { { '...I was answering a message. It was one word.', set = { c_admit = 'yes' } } },
                            { 'One word. I said.' }),
                    } })
                c:person('second', { at = 'second', label = 'Second driver', secret = 'clean', demeanor = 'polite',
                    scene = 'WORLD_HUMAN_STAND_MOBILE', questions = DRIVER_Q, lines = {
                        c_what = { 'I was stopped at the lights. Then bang. My neck is fine, I think, but look at my bumper.' },
                        c_driving = { 'Yes, that one is mine. The one in front.' },
                        c_fault = { "I was stationary. So, not mine? I've already called my insurance." },
                        c_drink = { 'No. Nothing.' },
                    } })
                car(c, 'first_car', 'dent', 'first', 'The car behind')
                car(c, 'second_car', 'rear', 'second', 'The car in front')
                c:clue('first_car', { on = 'first_car', label = 'The car behind',
                    text = 'A cracked bumper and a bent plate, nothing worse. In the footwell: a phone, its screen still lit on a half-typed message.' })
                c:clue('second_car', { on = 'second_car', label = 'The car in front',
                    text = 'A scuff across the rear bumper and a split light. It will drive.' })
                card(c)
                wire(c, { drivers = { 'first', 'second' } })
                local phone = false
                c:on('fact', function(_, fact) if fact == 'c_tip' then learns(c, 'first', 'c_phone') end end)
                c:on('inspect', function(clue)
                    if clue ~= 'first_car' then return end
                    phone = true
                    learns(c, 'first', 'c_phone')
                end)
                resolve(c, { must = { 'first' }, drive = { first = 'first_car', second = 'second_car' },
                    ends = function(out)
                        local on = {}
                        if phone then on[#on + 1] = 'the phone in the footwell' end
                        if c:who('first').facts.c_admit then on[#on + 1] = 'an admission' end
                        if out.first == 'arrested' then
                            return ('Minor collision, nobody hurt: %s, the driver behind, was arrested.'):format(c:name('first')) .. recorded(on)
                        end
                        local e = other_end(c, 'first', out.first, 'the driver behind')
                        return 'Minor collision, nobody hurt. ' .. (e and (e .. recorded(on)) or 'The drivers were left to swap details.')
                    end })
            end,
        },

        -- ── Not drink: a diabetic low, at the wheel. ─────────────────────────────────────────────────────────────
        sugar = {
            weight = 2,
            setup = function(c)
                caller(c, {
                    c_what = { "It just rolled into the back of the other one. Walking pace. Never braked. The driver got out and asked what day it was." },
                    c_driver = { 'The older one, there. They are not right. Drunk at this hour, if you ask me.' },
                    c_hurt = { "I don't think so. But that one doesn't look well." },
                })
                c:person('first', { at = 'first', label = 'First driver', age = { 55, 75 }, secret = 'clean', demeanor = 'nervous',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = DRIVER_Q, pockets = { 'Medical card: type 1 diabetic' }, lines = {
                        c_what = { 'The shop. I was... the shop was...', "Did I... is it Tuesday? Who's that?", 'So tired. Can I sit?' },
                        c_driving = { 'Was I? I think... yes. Was it me?' },
                        c_fault = { "Sorry. I'm sorry. What did I do?" },
                        c_drink = { "Drink? Yes. Could I have some... some juice? Is there juice?", 'No. No drink. I had the... I forget.' },
                    } })
                c:person('second', { at = 'second', label = 'Second driver', secret = 'clean', demeanor = 'polite',
                    scene = 'WORLD_HUMAN_STAND_MOBILE', questions = DRIVER_Q, lines = {
                        c_what = { 'I was stopped, and they just rolled into me. Eyes open. Not a touch of the brakes. Then they got out and apologised to my car.' },
                        c_driving = { 'Yes, the one in front.' },
                        c_fault = { "Theirs, I suppose, but I'm not angry. Something's wrong with them." },
                        c_drink = { 'No. Nothing.' },
                    } })
                car(c, 'first_car', 'dent', 'first', 'The car behind')
                car(c, 'second_car', 'rear', 'second', 'The car in front')
                c:clue('first_car', { on = 'first_car', label = 'The car behind',
                    text = 'A small dent in the front, and the engine stalled in gear. In the console: a glucose meter, an insulin pen, and an empty packet of glucose tablets.' })
                c:clue('second_car', { on = 'second_car', label = 'The car in front',
                    text = 'A scuff across the rear bumper. It will drive.' })
                card(c, 'Get the sick driver an ambulance')
                local heard = wire(c, { drivers = { 'first', 'second' }, wrecks = { 'first_car' } })
                local left, running, over, known, blew = SICK_AFTER, false, false, false, false
                local function knows(src)
                    if known then return end
                    known = true
                    c:note('A diabetic emergency: not drink')
                    c:done('ill')
                    c:done('decide') -- (nothing to decide: they're a patient now)
                    hurt(c, 'first')
                    if src then c:tell(src, 'Diabetic', 'Their blood sugar has crashed. It is not drink. They need paramedics, and the sooner the better.') end
                end
                c:on('arrive', function() running = true end)
                c:on('inspect', function(clue, src) if clue == 'first_car' then knows(src) end end)
                c:on('act', function(who, action, arg, src)
                    if who ~= 'first' then return end
                    if action == 'ask' and arg == 'c_what' then c:reveal('ill') end
                    if action == 'frisk' then knows(src) end -- (their medical card: in `pockets`, so it isn't contraband)
                    if action ~= 'breath' then return end
                    blew = true
                    c:reveal('ill')
                    if not known then c:tell(src, 'Breath test', 'Nothing on it. Whatever is wrong with them, it is not drink. Search them, and check their car.') end
                end)
                c:on('aid', function(who, what) if who == 'first' and (what == 'hospital' or what == 'treated') then over = true end end)
                c:on('custody', function(who) if who == 'first' then over = true end end)
                c:on('gone', function(who) if who == 'first' then over = true end end)
                c:on('tick', function()
                    if not running or over then return end
                    left = left - 1
                    if left > 0 then return end
                    over = true
                    c:note('The first driver collapsed at the scene')
                    -- ponytail: someone in cuffs can't drop (keep_up leaves them to the officer), so they only say so
                    if c:who('first').cuffed then c:say('first', "I can't... feel my hands...")
                    else
                        c:collapse('first', LOW)
                        c:dispatch('Your first driver has gone down. Paramedics needed at the scene.')
                    end
                    heard('first')
                    knows()
                end)
                resolve(c, { must = { 'first' }, drive = { second = 'second_car' }, wrecks = { 'first_car' },
                    ends = function(out)
                        local n, test = c:name('first'), blew and ' The breath test was clean.' or ''
                        if out.first == 'arrested' then
                            return ('Minor collision: %s was arrested.%s %s'):format(n, test, known and 'It was a diabetic emergency, not drink.' or '')
                        end
                        local e = other_end(c, 'first', out.first, 'the driver behind')
                        if e then return 'Minor collision. ' .. e .. test end
                        return ('Minor collision: %s, in a diabetic emergency at the wheel. No charges.'):format(n)
                    end })
            end,
        },

        -- ── She says she drove. He did. ──────────────────────────────────────────────────────────────────────────
        swap = {
            weight = 3,
            setup = function(c)
                local asked, pressed = 0, 0
                caller(c, {
                    c_what = { "They came round the bend way too fast and went straight into the other car. That one's still on the ground. I didn't dare move them." },
                    c_driver = { { "Him. The big guy. He got out of the driver's side, and then the two of them were talking, heads together.", set = { c_saw = 'yes' } } },
                    c_hurt = { "The one on the ground, yes. Please hurry." },
                })
                c:person('first', { at = 'first', label = 'Woman', male = false, secret = 'clean', demeanor = 'nervous',
                    scene = 'WORLD_HUMAN_STAND_MOBILE', questions = DRIVER_Q, lines = {
                        c_what = { 'I was driving. We came round the bend and they were just there. I braked.' },
                        c_driving = function(o)
                            if o.facts.c_swap then return { 'I told you. It was him. Please.' } end
                            if not c:apart('first', 'third') then return { 'Yes. Me. Why does everyone keep asking that?' } end
                            asked = asked + 1
                            if asked < 2 then return { 'I said I was. Look, it was me.' } end
                            return { { "...It wasn't me. He'd been drinking. He said he'd lose his job, so we swapped before anyone came. Don't tell him I told you.", set = { c_swap = 'yes' } } }
                        end,
                        c_fault = { 'Mine. I was driving.' },
                        c_drink = { "No. Nothing. Not me." },
                    } })
                c:person('third', { at = 'third', label = 'Man', male = true, age = { 28, 50 }, secret = 'drunk', demeanor = 'rude',
                    scene = 'WORLD_HUMAN_SMOKING', questions = DRIVER_Q, lines = {
                        c_what = { 'Ask her. She was driving. I was in the passenger seat.' },
                        c_driving = function(o)
                            if o.facts.c_admit then return { 'I said. It was me.' } end
                            if not (c:get('seat') or c:who('first').facts.c_swap) then return { "No. Passenger. Why would I lie?" } end
                            pressed = pressed + 1
                            if pressed < 2 then return { "Who told you that? I was the passenger." } end
                            return { { "...Fine. It was me. I'd only had a couple. She didn't have to say anything.", set = { c_admit = 'yes' } } }
                        end,
                        c_fault = { "The other car. It was stopped on a bend. Who does that?" },
                        c_drink = { "A couple. That's why she drove. Obviously." },
                    } })
                c:person('second', { at = 'second', label = 'Other driver', secret = 'clean', injured = true, vitals = HURT })
                car(c, 'first_car', 'front', 'third', 'The car behind')
                car(c, 'second_car', 'side', 'second', 'The car in front')
                c:clue('first_car', { on = 'first_car', label = 'The car behind',
                    text = "The front end caved in. The driver's seat is pushed right back and the mirror set high: whoever drove this is tall. Blood on the driver's airbag, and a half-empty bottle under the seat." })
                c:clue('second_car', { on = 'second_car', label = 'The car in front',
                    text = 'Hit hard in the side, the door pushed in. The glass is across the seat. This one is going nowhere.' })
                card(c)
                wire(c, { drivers = { 'first', 'third' }, hurts = { 'second' }, wrecks = { 'first_car', 'second_car' } })
                local blew = false
                local function doubt()
                    c:set('seat', true)
                    c:reveal('who')
                end
                local function truth()
                    doubt()
                    c:done('who')
                end
                c:on('inspect', function(clue) if clue == 'first_car' then doubt() end end)
                c:on('fact', function(_, fact)
                    if fact == 'c_saw' then doubt() end
                    if fact == 'c_swap' or fact == 'c_admit' then truth() end
                end)
                c:on('act', function(who, action)
                    if who == 'third' and action == 'breath' and (tonumber(c:who('third').truth.bac) or 0) >= Config.Tests.bac_limit then blew = true end
                end)
                resolve(c, { must = { 'first', 'third' }, wrecks = { 'first_car', 'second_car' },
                    ends = function(out)
                        local a, b = c:name('third'), c:name('first')
                        local known = c:who('first').facts.c_swap or c:who('third').facts.c_admit
                        if out.third == 'arrested' and known then
                            local on = {}
                            if c:get('seat') then on[#on + 1] = 'the seat and the airbag' end
                            if blew then on[#on + 1] = 'a breath test over the limit' end
                            if c:who('third').facts.c_admit then on[#on + 1] = 'an admission' end
                            if c:who('first').facts.c_swap then on[#on + 1] = "the passenger's statement" end
                            return ('Two-car collision: %s, who was driving and had said he was the passenger, was arrested.'):format(a) .. recorded(on)
                        end
                        if known then
                            return 'Two-car collision. ' .. (other_end(c, 'third', out.third, 'who was really driving') or ('%s was really driving.'):format(a))
                        end
                        if out.first == 'arrested' then return ('Two-car collision: %s, who said she was driving, was arrested.'):format(b) end
                        return 'Two-car collision. ' .. (other_end(c, 'first', out.first, 'who said she was driving') or ('%s said she was driving.'):format(b))
                    end })
            end,
        },

        -- ── A van into stopped traffic. ──────────────────────────────────────────────────────────────────────────
        pileup = {
            weight = 2,
            needs = { 'third_car' },
            setup = function(c)
                local phone = math.random() < .5
                caller(c, {
                    c_what = { "It was the van. The traffic had stopped, and it never slowed. It never even tried to. It just went through them." },
                    c_driver = { "The van? That one, sat over there. I don't think he knows where he is." },
                    c_hurt = { "Yes! At least two! One of them isn't moving! There's fuel, I can smell it!" },
                })
                c:person('third', { at = 'third', label = 'Van driver', male = true, age = { 25, 55 }, secret = 'clean', demeanor = 'nervous',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = DRIVER_Q, lines = {
                        c_what = { "I don't know. They were just there. They were all just there.", 'Is everyone... are they okay?' },
                        c_driving = { 'The van. Yes. That was me.' },
                        c_fault = cracks(3, { 'They stopped. Everyone just stopped.', "I don't know! There was no time!" },
                            { { phone and "...I looked down. I looked down for a second. Oh God. What have I done?"
                                or "...I shut my eyes. Only for a second. I've been up since yesterday. Oh God.", set = { c_admit = 'yes' } } },
                            { 'I said. It was me. Oh God.' }),
                        c_drink = { 'No. Nothing. Test me.' },
                        c_phone = { { '...It was a video. I only looked down for a second. Oh God.', set = { c_admit = 'yes' } } },
                        c_tired = { { "Yesterday morning. I have to make the drop or they don't pay. I shut my eyes, that's all.", set = { c_admit = 'yes' } } },
                    } })
                c:person('first', { at = 'first', label = 'Hurt driver', secret = 'clean', injured = true, vitals = HURT })
                c:person('second', { at = 'second', label = 'Hurt driver', secret = 'clean', injured = true, vitals = CRITICAL })
                car(c, 'first_car', 'wreck', 'first', 'A wreck')
                car(c, 'second_car', 'wreck', 'second', 'A wreck')
                c:vehicle('third_car', { at = 'third_car', model = 'burrito3', make = 'Declasse', name = 'Burrito', color = 'White', paint = 111,
                    owner = 'third', locked = false, damage = 'front', label = 'The van' })
                car(c, 'fourth_car', 'side', nil, 'A car')
                c:clue('first_car', { on = 'first_car', label = 'A wreck',
                    text = 'Crushed from behind and pushed into the car ahead. Fuel is running out from under it, down towards the kerb, and the engine is still ticking. This wants a fire crew before anything else does.' })
                c:clue('second_car', { on = 'second_car', label = 'A wreck',
                    text = 'The back end folded up to the rear seats, and blood on the door where someone pulled themselves out.' })
                c:clue('third_car', { on = 'third_car', label = 'The van',
                    text = phone and "No skid marks behind it at all. In the cab: a phone wedged in the dash, a video still playing."
                        or "No skid marks behind it at all. In the cab: energy drink cans, and a logbook showing fourteen hours at the wheel and no break." })
                c:clue('debris', { at = 'scene', label = 'The road', prop = 'imp_prop_impexp_front_bumper_01a',
                    scatter = { model = 'v_ind_cs_hubcap', count = 6, radius = 6.0 },
                    text = 'Glass, oil and bits of car across both lanes. This will need a crew to clear.' })
                card(c)
                wire(c, { drivers = { 'third' }, hurts = { 'first', 'second' }, wrecks = { 'first_car', 'second_car', 'third_car', 'fourth_car' },
                    seen = function()
                        if c:held() ~= nil then c:reveal('hold') end -- (nil: no lwk_control to hold it with)
                        c:reveal('crew')
                        c:reveal('tow')
                    end })
                local left, running, stopped, evidence = BLEEDS_FOR, false, false, false
                c:on('arrive', function() running = true end)
                c:on('aid', function(who, what)
                    if who == 'second' and (what == 'pressure' or what == 'hospital' or what == 'treated') then stopped = true end
                end)
                c:on('dead', function(who)
                    if who ~= 'second' then return end
                    stopped = true
                    c:note('One of the casualties has died')
                    c:dispatch('Paramedics advise they have lost one.')
                end)
                c:on('towed', function(key) if key == 'first_car' then c:reveal('fire') end end) -- (nobody looked: the leak's still in the road)
                c:on('inspect', function(clue)
                    if clue == 'first_car' then c:reveal('fire') end
                    if clue == 'third_car' then
                        evidence = true
                        learns(c, 'third', phone and 'c_phone' or 'c_tired')
                    end
                end)
                c:on('service', function(kind)
                    if kind == 'fire' then
                        c:reveal('fire')
                        c:done('fire')
                        c:note('Fire crew made the fuel leak safe')
                    elseif kind == 'dot' then
                        c:clear('debris')
                        c:done('crew')
                        c:done('hold')
                        c:note('DOT crew cleared the road')
                    end
                end)
                c:on('tick', function()
                    if c:held() then c:done('hold') end
                    if not running or stopped then return end
                    left = left - 1
                    if left == 60 then c:dispatch('Paramedics advise one of them does not have long. Keep pressure on that wound.') end
                    if left <= 0 then
                        c:die('second')
                        left = 5 -- (again, if that game didn't get it: `dead` stops the clock)
                    end
                end)
                resolve(c, { must = { 'third' }, wrecks = { 'first_car', 'second_car', 'third_car', 'fourth_car' }, tows = TOWS, jobs = { 'fire', 'crew' },
                    ends = function(out)
                        local on = {}
                        if evidence then on[#on + 1] = phone and 'the phone in the cab' or 'the logbook' end
                        if c:who('third').facts.c_admit then on[#on + 1] = 'an admission' end
                        local road = out.left and ' The road was not cleared.' or ' The road was cleared.'
                        if out.third == 'arrested' then
                            return ('Multi-vehicle collision: %s, driving the van, was arrested.'):format(c:name('third')) .. recorded(on) .. road
                        end
                        local e = other_end(c, 'third', out.third, 'driving the van')
                        return 'Multi-vehicle collision. ' .. (e and (e .. recorded(on)) or 'The van driver was not dealt with.') .. road
                    end })
            end,
        },
    },
})
