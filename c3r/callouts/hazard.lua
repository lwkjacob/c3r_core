--[[
    c3r callout: OBJECT IN THE ROADWAY.

    Something's in the road and a driver has stopped. The report is the same every time, and the card is too: the caller,
    what's in the road, and where it came from (three units can take one each). What it is decides the job. One of six:
      bumper     off a car in a small crash, and the driver carried on: drag it off the road, find the car
      load       off a van with bad straps: drag it off the road, find the van
      spill      nails, off a contractor's pickup: hold traffic, call the DOT crew, release traffic
      scam       nails again, but a tow driver put them there and is parked up the road for the business
      deer       a dead deer: call animal control
      trap       dragged there on purpose on a quiet road, and whoever did it is waiting with a gun
    It's dealt with when the road's clear (and traffic's moving again) and whoever's responsible has been dealt with, or
    the caller's been heard and every unit has left.

    Points per location: walk them out in game with /c3rplace hazard (it writes the location in below).
]]

local CALLER_Q = {
    { id = 'c_what', label = 'What happened?' },
    { id = 'c_saw', label = 'Did you see where it came from?' },
    { id = 'c_long', label = 'How long has it been there?' },
    { id = 'c_hurt', label = 'Are you hurt? Is your car okay?' },
}
local DRIVER_Q = {
    { id = 'c_here', label = 'What are you doing here?', stress = true },
    { id = 'c_yours', label = 'That in the road back there. Is it yours?', stress = true, press = true },
    { id = 'c_fast', label = 'How did you get here so fast?', needs = { c_fast = true }, stress = true, press = true },
}
local CALLED = { caller = 'the caller', driver = 'the driver' }
local PISTOL = 'WEAPON_PISTOL'

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
    c:objective('caller', 'Talk to the caller', { hint = 'Stopped at the roadside.', blip = 'caller' })
    c:objective('hazard', "Check what's in the road", { hint = 'Watch the traffic, and your tyres.', blip = 'hazard' })
    c:objective('source', 'Find out where it came from', { hint = 'Ask the caller what they saw.' })
    c:objective('drag', 'Drag it off the road', { hidden = true, blip = 'hazard', hint = 'E picks it up, E lets it go. Off the road, onto the verge or the pavement.' })
    c:objective('hold', 'Hold traffic', { hidden = true, who = 'all', blip = 'hazard', hint = 'Radio it: "hold traffic".' })
    c:objective('crew', 'Call the DOT crew', { hidden = true, blip = 'hazard', hint = 'By radio, or G.' })
    c:objective('release', 'Release traffic', { hidden = true, who = 'all', hint = 'The road is clear. Radio it: "release traffic".' })
    c:objective('animal', 'Call animal control', { hidden = true, blip = 'hazard', hint = 'By radio, or G.' })
    c:objective('van', 'Check their vehicle', { hidden = true, blip = 'their_car', hint = 'What does it tell you?' })
    c:objective('gunman', 'Stop the gunman', { hidden = true, who = 'all', blip = 'driver', hint = 'Take cover. He gives up if he has to.' })
    c:objective('medic', 'Call paramedics', { hidden = true, who = 'all', blip = 'driver', hint = 'Radio for an ambulance.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'source' }, who = 'all' })
end

-- Done when: the caller's said what happened, the hazard's been looked at, the one responsible has been reached. What the
-- caller saw puts them on the map; reaching them opens their vehicle.
local function wire(c)
    c:on('act', function(who, action, arg)
        if who == 'caller' and action == 'ask' and arg == 'c_what' then c:done('caller') end
    end)
    c:on('fact', function(_, fact) if fact == 'c_saw' then c:blip('source', 'driver') end end)
    c:on('inspect', function(clue)
        if clue == 'hazard' then c:done('hazard') end
        if clue == 'their_car' then c:set('van_seen', true) c:done('van') end
    end)
    c:on('contact', function(who)
        if who ~= 'driver' then return end
        c:done('source')
        c:reveal('van')
        c:reveal('their_car')
        c:blip('decide', 'driver')
    end)
    c:on('dead', function(who) if who == 'caller' then c:done('caller') end end)
end

-- The job: drag it clear.
local function drag_job(c)
    c:on('inspect', function(clue) if clue == 'hazard' then c:reveal('drag') end end)
    c:on('dragged', function(key, clear, src)
        if key ~= 'hazard' then return end
        if not clear then return c:tell(src, 'Not clear yet', 'That is still in the way. Get it right off the road, onto the verge or the pavement.') end
        c:clear('hazard', true)
        c:done('drag')
        c:set('clear', true)
    end)
end

-- The job: hold traffic, the crew sweeps it (called before traffic's held: they still clean it). Releasing traffic is
-- resolve's, for every story.
local function sweep_job(c)
    local swept = false
    c:on('inspect', function(clue)
        if clue ~= 'hazard' then return end
        c:reveal('crew')
        if c:held() ~= nil then c:reveal('hold') end -- (nil: no lwk_control to hold it with)
    end)
    c:on('service', function(kind)
        if kind ~= 'dot' or swept then return end
        swept = true
        c:clear('hazard')
        c:done('hazard')
        c:done('crew')
        c:done('hold')
        c:note('DOT crew cleared the road')
        c:set('clear', true)
    end)
    c:on('tick', function() if not swept and c:held() then c:done('hold') end end)
end

-- The robber on the trap. A unit close by, he opens fire, or (30%) gives up on the spot. Then he gives up when hurt, half
-- the time when told to, or after 45-120 s with units near.
local function waiting(c)
    local reacted, fighting, left = false, false, 0
    local function surrender(line)
        fighting = false
        local o = c:who('driver')
        o.ran, o.gave_up = true, true
        c:done('gunman')
        c:done('source')
        c:reveal('van')
        c:reveal('their_car')
        c:blip('decide', 'driver')
        c:say('driver', line)
        c:task('driver', 'surrender')
    end
    c:on('fired', function(who)
        if who ~= 'driver' then return end
        c:reveal('gunman')
        c:dispatch('Shots fired! All units, shots fired!')
        c:note('Shots fired by the suspect')
    end)
    c:on('tick', function()
        local o = c:who('driver')
        if not o or o.cuffed or c:get('dead_driver') then return end
        if not reacted and c:near('driver', 30.0) and not c:talking() then
            reacted = true
            if math.random() < 0.3 then
                surrender("Alright! Alright, don't shoot! It was just the one job!")
            else
                fighting, left = true, math.random(45, 120)
                c:task('driver', 'shoot')
            end
        end
        if not fighting then return end
        local health = c:health('driver')
        left = c:near('driver', 45.0) and left - 1 or left
        if health and health > 100 and health < 150 then surrender("Okay! Okay, I'm hit! I'm done!")
        elseif left <= 0 then surrender("That's it! I'm out! I'm done, don't shoot!") end
    end)
    c:on('hail', function(who)
        if who == 'driver' and fighting and math.random() < 0.5 then surrender("Alright! I'm putting it down!") end
    end)
    c:on('contact', function(who) if who == 'driver' then reacted = true end end)
end

--[[ It's over when the road's clear with traffic moving again, and whoever's arrested has been taken in, or the driver's been
     let go, got away or been seen to; or, with nobody to deal with (no driver: the deer), the road's clear; or the caller's
     been heard, the source found and every unit has left (until it's found, a unit far off may be walking to it). ends(out) -> the MDT summary; out.driver = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' |
     'pronounced' | 'hospital'; out.left = true. ]]
local function resolve(c, ends)
    local out, taken, away_for, done = {}, {}, 0, false
    local function waiting_on()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local LET_GO = { released = true, cited = true, warning = true, fled = true, pronounced = true, hospital = true }
    local function check()
        if done or waiting_on() then return end
        local dealt = taken.driver or LET_GO[out.driver] or not c:who('driver')
        if not ((dealt and c:get('clear') and not c:held()) or out.left) then return end
        done = true
        c:done('decide')
        c:finish(ends(out))
    end
    c:on('act', function(who, action)
        local o = c:who(who)
        if action == 'cuff' and o and o.cuffed then
            out[who] = 'arrested'
            c:custody(who)
            c:done('decide')
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
        if who == 'driver' then c:done('medic') end
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if out[who] == 'dead' then seen_to(who, 'pronounced') end -- (the coroner's been)
    end)
    c:on('dead', function(who)
        if who ~= 'driver' then return end
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        c:set('dead_driver', true)
        for _, id in ipairs({ 'source', 'gunman', 'van', 'decide' }) do c:done(id) end
        c:reveal('medic')
        c:dispatch('The suspect is down. Paramedics needed at the scene.')
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' then seen_to(who, 'pronounced')
        elseif what == 'hospital' or what == 'treated' then seen_to(who, 'hospital') end
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or out[who] == 'pronounced' or out[who] == 'hospital' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        if who == 'driver' and LET_GO[out[who]] then c:done('decide') end
    end)
    c:on('tick', function() -- (the road clearing and the driver being dealt with come in either order: one place to look)
        if c:get('clear') then
            if c:held() then c:reveal('release') else c:done('release') end
        end
        check()
        local here = c:near(nil, 80.0) or c:near('driver', 80.0) or c:talking()
        if c:is_done('caller') and c:is_done('source') and not waiting_on() and not here then
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

-- What the summary says: the road, then the driver. c = the call, what = what it was.
local function report(c, out, what)
    local s = c:who('driver') and c:name('driver')
    local how = out.driver
    local text = what .. (c:get('clear') and ' The road was cleared.' or ' The road was not cleared.')
    if not s then return text end
    if how == 'arrested' then text = text .. (' %s was arrested.'):format(s)
    elseif how == 'cited' or how == 'warning' then text = text .. (' %s was given a %s.'):format(s, how == 'cited' and 'ticket' or 'warning')
    elseif how == 'released' then text = text .. (' %s was spoken to and let go.'):format(s)
    elseif how == 'fled' then text = text .. (' %s ran and got away.'):format(s)
    elseif how == 'dead' or how == 'pronounced' then text = text .. (' %s died at the scene.'):format(s)
    elseif how == 'hospital' then text = text .. (' %s was taken to hospital.'):format(s)
    else text = text .. ' Nobody was found responsible.' end
    local o = c:who('driver')
    if how == 'arrested' and o.facts.c_admit then text = text .. ' Recorded: the admission.' end
    if how == 'arrested' and c:get('van_seen') then text = text .. ' Recorded: what was in the vehicle.' end
    return text
end

local function caller(c, lines)
    lines.where = lines.where or { "Nowhere now, am I? Look at this." }
    c:person('caller', { at = 'caller', label = 'Caller', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = CALLER_Q, lines = lines })
    c:vehicle('caller_car', { at = 'caller_car', model = 'asea', make = 'Declasse', name = 'Asea', color = 'Silver', paint = 4, owner = 'caller', label = 'Their car' })
end

-- Whoever's responsible, and their vehicle with what it tells you.
local function driver(c, spec, car, lines, stash)
    lines.where = lines.where or { "Nowhere in particular." }
    c:person('driver', { at = 'driver', label = 'Driver', male = spec.male, age = spec.age, secret = spec.secret or 'nervous', demeanor = spec.demeanor or 'nervous',
        items = spec.items or {}, weapon = spec.weapon, scene = 'WORLD_HUMAN_SMOKING', questions = DRIVER_Q, lines = lines })
    car.at, car.owner, car.label = 'their_car', 'driver', 'Their vehicle'
    c:vehicle('their_car', car)
    c:clue('their_car', { on = 'their_car', label = 'Their vehicle', hidden = true, text = stash })
end

-- A thing to drag: which one's picked per call.
local THINGS = {
    { 'imp_prop_impexp_front_bumper_01a', 'A car bumper', 'A whole front bumper, snapped off, in the middle of the lane.' },
    { 'prop_rub_tyre_01', 'A tyre', 'A truck tyre lying flat in the lane, with road dirt still wet on it.' },
    { 'prop_homeless_matress_01', 'A mattress', 'A mattress, flat in the lane, with a length of cut rope still tied round it.' },
}

local NAILS = { model = 'ng_proc_brkbottle_02a', count = 8, radius = 4.0 } -- (the game has no nails: small sharp scrap reads the same)

Callout({
    id = 'hazard',
    name = 'Object in the roadway',
    voice = 'call_hazard', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 3,
    weight = 1,
    enabled = true,
    reports = {
        'Caller reports something in the road. Cars are swerving around it.',
        "Debris in the lane. Caller says someone's going to get hurt.",
        'Driver has pulled over after hitting something in the road.',
    },
    -- The points each location needs, in the order /c3rplace hazard walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it), and it has to be on the road, with somewhere off it close by.
    points = {
        { 'hazard', 'What is in the road: stand in the lane.' },
        { 'caller', 'The driver who called: at the roadside, close by.' },
        { 'caller_car', 'Their car, pulled over. Sit in a car parked there.', 'car' },
        { 'their_car', 'Where it came from: a vehicle parked up the road. Sit in a car parked there.', 'car' },
        { 'driver', 'Whoever is with that vehicle: on foot beside it. On the quiet stories, they are hiding out of sight here.' },
    },
    -- Add more with /c3rplace hazard in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Los Santos Freeway', at = vector3(696.61, -128.63, 51.82), streets = { caller = 'Bridge St', caller_car = 'Bridge St' }, points = {
            hazard = vector4(696.61, -128.63, 51.82, 140.0),
            caller = vector4(690.84, -116.61, 52.55, 178.6),
            caller_car = vector4(689.03, -120.72, 51.78, 154.4),
            their_car = vector4(648.46, -203.22, 44.54, 146.6),
            driver = vector4(650.79, -200.83, 45.17, 297.0),
        } },
        { street = 'Meteor St', at = vector3(518.79, 87.11, 96.40), streets = { their_car = 'Vinewood Blvd', driver = 'Vinewood Blvd' }, points = {
            hazard = vector4(518.79, 87.11, 96.40, 88.4),
            caller = vector4(531.31, 109.82, 96.33, 79.8),
            caller_car = vector4(533.18, 116.18, 96.19, 341.2),
            their_car = vector4(461.21, 115.05, 98.18, 69.7),
            driver = vector4(463.62, 112.93, 98.43, 244.0),
        } },
        { street = 'Senora Fwy', at = vector3(2930.43, 3754.44, 52.65), points = {
            hazard = vector4(2930.43, 3754.44, 52.65, 11.9),
            caller = vector4(2938.15, 3770.10, 52.65, 119.2),
            caller_car = vector4(2939.82, 3773.74, 52.23, 347.3),
            their_car = vector4(2951.80, 3938.68, 51.49, 7.8),
            driver = vector4(2950.74, 3935.54, 51.91, 201.4),
        } },
        { street = 'Panorama Dr', at = vector3(1701.18, 3509.10, 36.47), points = {
            hazard = vector4(1701.18, 3509.10, 36.47, 0.7),
            caller = vector4(1697.99, 3523.87, 36.19, 158.9),
            caller_car = vector4(1695.20, 3527.56, 35.63, 23.9),
            their_car = vector4(1664.21, 3581.10, 35.02, 32.7),
            driver = vector4(1665.78, 3576.97, 35.42, 195.7),
        } },
        { street = 'Great Ocean Hwy', at = vector3(1080.23, 6482.76, 21.04), points = {
            hazard = vector4(1080.23, 6482.76, 21.04, 108.8),
            caller = vector4(1065.69, 6500.54, 21.04, 221.7),
            caller_car = vector4(1062.81, 6502.03, 20.61, 91.4),
            their_car = vector4(1192.86, 6476.41, 20.57, 273.0),
            driver = vector4(1189.03, 6477.90, 20.99, 71.0),
        } },
    },

    stories = {
        -- ── Off a car, in a small crash. ─────────────────────────────────────────────────────────────────────────
        bumper = {
            weight = 3,
            setup = function(c)
                caller(c, {
                    c_what = { "I came round the bend and there it was. I went over the edge of it. Cars are going round it." },
                    c_saw = { { "There's a car stopped up the road with its front end smashed in. I'd bet it came off that.", set = { c_saw = 'yes' } } },
                    c_long = { "Ten minutes? It wasn't here when I came the other way." },
                    c_hurt = { "I'm fine. The car's fine, I think." },
                })
                c:clue('hazard', { at = 'hazard', label = 'A car bumper', prop = THINGS[1][1], drag = true, text = THINGS[1][3] })
                driver(c, { secret = math.random() < .3 and 'suspended' or 'nervous' },
                    { model = 'tailgater', make = 'Obey', name = 'Tailgater', color = 'Black', paint = 0, damage = 'front', locked = false }, {
                        c_here = { "I hit a post. Bent the whole front. I was just looking at it." },
                        c_yours = cracks(2, { "What's in the road? I don't know." },
                            { { "...Yeah. Probably. I was going to go back for it, I just wanted to get off the road.", set = { c_admit = 'yes' } } },
                            { "Yeah. It's mine. I said." }),
                    }, 'The front end is smashed in, and the bumper is gone. Fresh paint on the wing, the same as what is in the road.')
                card(c)
                wire(c)
                drag_job(c)
                resolve(c, function(out) return report(c, out, 'A car bumper in the road, from a minor crash.') end)
            end,
        },

        -- ── Off a van. ───────────────────────────────────────────────────────────────────────────────────────────
        load = {
            weight = 2,
            setup = function(c)
                local thing = THINGS[math.random(2, #THINGS)]
                caller(c, {
                    c_what = { "It was just there, in the lane. I nearly went into it. Somebody's going to have an accident." },
                    c_saw = { { "A van went past a minute before. Stuff on the roof, tied on badly. It's stopped up the road, I saw its lights.", set = { c_saw = 'yes' } } },
                    c_long = { "A few minutes. Not long." },
                    c_hurt = { "No. It was close, though." },
                })
                c:clue('hazard', { at = 'hazard', label = thing[2], prop = thing[1], drag = true, text = thing[3] })
                driver(c, { secret = 'clean', demeanor = 'polite' },
                    { model = 'burrito3', make = 'Declasse', name = 'Burrito', color = 'White', paint = 111, locked = false }, {
                        c_here = { "Moving my brother's stuff. Just checking the load. Is something wrong?" },
                        c_yours = { { "In the road? Oh no. Oh, I'm so sorry. I tied that on myself.", set = { c_admit = 'yes' } } },
                    }, 'The roof rack: one strap flapping loose, its knot pulled through. There is clearly something missing.')
                card(c)
                wire(c)
                drag_job(c)
                resolve(c, function(out) return report(c, out, 'Debris in the road, lost from an unsecured load.') end)
            end,
        },

        -- ── A spilled box of nails. ──────────────────────────────────────────────────────────────────────────────
        spill = {
            weight = 3,
            setup = function(c)
                caller(c, {
                    c_what = { "I heard this crunching, and then the tyre went. There are nails all over the lane. Hundreds of them." },
                    c_saw = { { "There's a pickup stopped up the road. The guy's walking round the back of it looking sick.", set = { c_saw = 'yes' } } },
                    c_long = { "Just now. I can't be the first to hit it." },
                    c_hurt = { "I'm fine. The tyre isn't." },
                })
                c:clue('hazard', { at = 'hazard', label = 'Nails', prop = 'prop_cardbordbox_02a', scatter = NAILS, spikes = 6.0,
                    text = 'A split carton, and roofing nails across the whole lane. Nobody can drive through this, and they are too many to pick up by hand.' })
                driver(c, { secret = 'clean', demeanor = 'polite', age = { 30, 55 } },
                    { model = 'sadler', make = 'Vapid', name = 'Sadler', color = 'White', paint = 111, locked = false }, {
                        c_here = { "My tailgate dropped. I've got a load of site materials on. I was about to walk back." },
                        c_yours = { { "The nails? Yes. God, yes. The whole carton went. I'm so sorry. I'll pay for the tyres.", set = { c_admit = 'yes' } } },
                    }, 'A work pickup with the tailgate hanging on a broken latch, and a stack of cartons. There is a gap where one fell out.')
                card(c)
                wire(c)
                sweep_job(c)
                resolve(c, function(out) return report(c, out, 'Nails across the road, spilled from an unsecured load.') end)
            end,
        },

        -- ── Nails, put there on purpose. ─────────────────────────────────────────────────────────────────────────
        scam = {
            weight = 2,
            setup = function(c)
                caller(c, {
                    c_what = { "I heard this crunching, and then the tyre went. There are nails all over the lane. And that tow truck was here before I'd even stopped." },
                    c_saw = { { "There's a tow truck up the road. Offered me a price before I'd got out of the car. Second time this month on this road, a friend told me.", set = { c_saw = 'yes' } } },
                    c_long = { "Just now. He must've been waiting." },
                    c_hurt = { "I'm fine. He wants two hundred for a tyre." },
                })
                c:clue('hazard', { at = 'hazard', label = 'Nails', prop = 'prop_cardbordbox_02a', scatter = NAILS, spikes = 6.0,
                    text = 'Roofing nails across the whole lane, spread evenly, side to side. It looks less like a spill than like someone walked it. They are too many to pick up by hand.' })
                driver(c, { secret = 'nervous', demeanor = 'rude', age = { 30, 55 } },
                    { model = 'towtruck2', make = 'Vapid', name = 'Tow truck', color = 'White', paint = 111, locked = false }, {
                        c_here = { { "Working. Somebody's got a flat, somebody needs a tow. Is that a problem?", set = { c_fast = 'yes' } } },
                        c_yours = cracks(3, { "Mine? I tow cars, I don't throw nails.", "Prove it." },
                            { { "...Business has been slow. It's only tyres. Nobody got hurt.", set = { c_admit = 'yes' } } },
                            { "I said. It's only tyres." }),
                        c_fast = { "I got lucky. I was passing." },
                    }, 'In the cab: an open carton of the same roofing nails, half empty, and a card reader with five tyre jobs on this road this month.')
                card(c)
                wire(c)
                sweep_job(c)
                resolve(c, function(out) return report(c, out, 'Nails across the road, scattered on purpose by a tow driver after the business.') end)
            end,
        },

        -- ── A dead deer. ─────────────────────────────────────────────────────────────────────────────────────────
        deer = {
            weight = 2,
            setup = function(c)
                caller(c, {
                    c_what = { "It came out of nowhere. I didn't even touch the brakes. I think it's dead." },
                    c_saw = { "Out of the trees. There was no time." },
                    c_long = { "Just now. It's me that hit it." },
                    c_hurt = { "I'm alright. The bonnet's dented. Poor thing." },
                })
                c:clue('hazard', { at = 'hazard', label = 'What is in the road', text = 'A dead deer, across the lane. Too heavy to drag. This is a job for animal control.' })
                c:person('deer', { at = 'hazard', label = 'Deer', male = true, model = 'a_c_deer', dead = true })
                card(c)
                wire(c)
                c:on('inspect', function(clue)
                    if clue ~= 'hazard' then return end
                    c:done('source')
                    c:done('decide') -- (there's nobody to deal with)
                    c:reveal('animal')
                end)
                c:on('gone', function(who)
                    if who ~= 'deer' then return end
                    c:done('animal')
                    c:set('clear', true)
                end)
                resolve(c, function(out) return report(c, out, 'A dead deer in the road, hit by the caller. Taken by animal control.') end)
            end,
        },

        -- ── Put there, by someone waiting. ───────────────────────────────────────────────────────────────────────
        trap = {
            weight = 2,
            setup = function(c)
                local thing = THINGS[math.random(#THINGS)]
                caller(c, {
                    c_what = { "It's right across the lane. On a road like this. I stopped to move it and I heard someone in the trees, so I got back in the car." },
                    c_saw = { { "Nobody. But there's a car tucked in up there with its lights off, and there's nowhere to go up there.", set = { c_saw = 'yes' } } },
                    c_long = { "It wasn't here at lunchtime. Somebody put it here." },
                    c_hurt = { "No. I got lucky, I think." },
                })
                c:clue('hazard', { at = 'hazard', label = thing[2], prop = thing[1], drag = true, text = thing[3] .. ' There are drag marks on the road. It did not fall here. Someone put it here.' })
                driver(c, { secret = 'warrant', male = true, age = { 24, 40 }, weapon = PISTOL, demeanor = 'rude', items = { 'Pistol, loaded, black', 'Three wallets, none of them his' } },
                    { model = 'emperor', make = 'Albany', name = 'Emperor', color = 'Black', paint = 0, locked = false }, {
                        c_here = { "Nothing. I broke down." },
                        c_yours = cracks(2, { "Never seen it." },
                            { { "...Nobody stops for a guy on the side of the road. They stop for that.", set = { c_admit = 'yes' } } },
                            { "I told you how it works." }),
                    }, 'A ski mask on the seat, a bag of phones, and the plate is held on with one screw.')
                card(c)
                wire(c)
                drag_job(c)
                waiting(c)
                resolve(c, function(out) return report(c, out, 'A roadblock set on purpose to rob whoever stopped.') end)
            end,
        },
    },
})
