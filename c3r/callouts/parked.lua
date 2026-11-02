--[[
    c3r callout: PARKED VEHICLE.

    A car's been left where it shouldn't be: across a driveway, against a fire hydrant, or up on the pavement (where the
    caller was placed says which). The report and the opening card are the same every time: the caller, the car and its
    plate (three units can take one each), then getting it moved. What the car turns out to be is one of four stories:
      selfish   the owner nipped in "for five minutes", hours ago. A tow truck on its way brings them running
      feud      the neighbour did it on purpose (driveways only), and the caller has keyed the car for it
      stolen    the plate's reported stolen and the car's hot-wired. Whoever left it is still close by
      asleep    it isn't empty: a drunk at the wheel with the engine running, at the wrong house
    It's dealt with when the car has gone, by tow or by its owner, and the person it's about has been dealt with (taken in,
    given a ticket or a warning, let go, or got away) or was never found; or the caller's been heard and every unit has left.

    Telling someone their car's being towed doesn't call the truck: the officer does that, G at the car or by radio.

    Points per location: walk them out in game with /c3rplace parked (it writes the location in below).
]]

-- The car: picked per call. Spawn names, makes and names checked against the game's vehicle list; paint ids against
-- docs.fivem.net's vehicle colours.
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

-- Which of these three was placed is what the car is blocking.
local SPOTS = {
    driveway = {
        what = "Look at it. Right across my driveway. I can't get my car out, and I've got to be at work.",
        shout = "Over here, officer! I've been stuck here for ages!",
        car = 'Parked square across the driveway. Nothing is getting in or out.',
    },
    hydrant = {
        what = "It's parked right on the fire hydrant. If there's a fire on this street, they can't get to it.",
        shout = "Over here, officer! It's this one, by the hydrant!",
        car = 'Parked hard up against a fire hydrant. An engine could not hook up to it.',
    },
    pavement = {
        what = "It's up on the pavement, all of it. People are having to walk out into the road to get past.",
        shout = "Over here, officer! You can see the problem!",
        car = 'Up on the pavement and blocking all of it. People are stepping into the road to get past.',
    },
}

local CALLER_Q = {
    { id = 'c_what', label = "What's the problem?" },
    { id = 'c_long', label = 'How long has it been there?' },
    { id = 'c_saw', label = 'Did you see who left it?' },
    { id = 'c_whose', label = 'Do you know whose it is?' },
    { id = 'c_scratch', label = 'Do you know how that scratch got there?', needs = { c_scratched = true }, stress = true, press = true },
}
local OWNER_Q = {
    { id = 'c_yours', label = 'Is that your car?' },
    { id = 'c_why', label = 'Why did you leave it there?', stress = true },
    { id = 'c_hours', label = 'The caller says it has been there for hours.', needs = { c_hours = true }, stress = true, press = true },
    { id = 'c_drove', label = 'Did you drive here like this?', needs = { c_seen_drunk = true }, stress = true, press = true },
    { id = 'c_scratch', label = 'Someone has scratched your car.', needs = { c_scratched = true } },
    { id = 'c_move', label = 'I need you to move it.', press = true },
    { id = 'c_tow', label = "Leave it. I'm having it towed.", press = true },
}
local RUNNER_Q = {
    { id = 'c_here', label = 'What are you doing here?', stress = true },
    { id = 'c_car', label = 'Do you know anything about that car?', stress = true, press = true },
    { id = 'c_seen', label = 'Someone saw you get out of it.', needs = { c_seen = true }, stress = true, press = true },
}

-- Denies it until pressed `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

-- Which spot this location has. It decides what the car is blocking and where the caller stands.
local function spot_of(c)
    local p = c.inc.loc.points or {}
    local key = p.driveway and 'driveway' or p.hydrant and 'hydrant' or p.pavement and 'pavement'
    if not key then error('a parked location needs one of driveway, hydrant or pavement', 0) end
    return key, SPOTS[key]
end

local function caller(c, key, spot, lines, items)
    lines.c_what = lines.c_what or { spot.what }
    c:person('caller', { at = key, label = 'Caller', demeanor = 'chatty', scene = 'WORLD_HUMAN_STAND_IMPATIENT',
        questions = CALLER_Q, items = items, lines = lines })
end

local function the_car(c, spec, spot, text)
    local car, paint = CARS[math.random(#CARS)], PAINTS[math.random(#PAINTS)]
    spec.at, spec.model, spec.make, spec.name, spec.color, spec.paint, spec.label = 'car', car.model, car.make, car.name, paint[1], paint[2], 'The car'
    c:vehicle('car', spec)
    c:clue('car', { on = 'car', label = 'The car', text = spot.car .. ' ' .. text })
    return paint
end

local function card(c, o)
    c:objective('caller', 'Talk to the caller', { hint = 'They called it in.', blip = 'caller' })
    c:objective('car', 'Look the car over', { hint = 'E beside it.', blip = 'car' })
    c:objective('plate', 'Run the plate', { hint = 'G at the car, by radio, or on the MDT.', blip = 'car' })
    c:objective('move', 'Get the car moved', { after = { 'plate' }, who = 'all', blip = 'car',
        hint = 'Get the owner to move it, or G at the car: Request tow. Stand beside it to ask by radio.' })
    c:objective('owner', o.owner, { hidden = true, blip = o.who, hint = o.owner_hint })
    c:objective('decide', 'Deal with them: arrest, ticket or warn, or let them go', { hidden = true, who = 'all', blip = o.who })
end

-- Done when: the caller's said what's wrong, the car's been looked at, the plate's been run. Talking to whoever it's about
-- finds them. on_plate(): the plate's been run, the first time.
local function wire(c, who, spot, on_plate)
    c:on('act', function(key, action, arg)
        if key == 'caller' and action == 'ask' and arg == 'c_what' then c:done('caller') end
    end)
    c:on('dead', function(key) if key == 'caller' then c:done('caller') end end)
    c:on('inspect', function(clue) if clue == 'car' then c:done('car') end end)
    local ran = false
    c:on('plate', function(car)
        if car ~= 'car' or ran then return end
        ran = true
        c:done('plate')
        on_plate()
    end)
    c:on('contact', function(key)
        if key ~= who then return end
        c:reveal('owner')
        c:done('owner')
        c:reveal('decide')
    end)
    local said = false -- (heard as the first unit gets close)
    c:on('tick', function()
        if said or not c:near('caller', 30.0) then return end
        said = true
        c:say('caller', spot.shout)
    end)
end

-- What dispatch says when the plate's run: who it's registered to, and marks them.
local function ran_plate(c, tail)
    local o = c:owner('car') or {}
    local text = ('Plate %s comes back to %s %s, %s.'):format(c:plate('car') or 'unknown', o.first or 'unknown', o.last or '', o.address or 'no fixed address') .. tail
    c:dispatch(text)
    c:note(text)
end

--[[ It's over when the car has gone (towed, or moved far enough off its point) and whoever it's about (who) is done with:
     taken in, given a ticket or a warning, let go, or got away, or no unit is with them. Or when the caller's been heard or
     the car's gone, and every unit has left. Let go, or told to move it, they get in it and drive away, unless they've been
     told it's being towed or a truck is coming for it (or it isn't theirs to drive: stays). ends(out, gone) -> the MDT summary (anyone else arrested, ticketed
     or warned is added); out = { [person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead', left = true };
     gone = 'towed' | 'moved' | nil. ]]
local function resolve(c, who, ends, stays)
    local out, taken, away_for, done = {}, {}, 0, false
    local gone, told, driving, truck_left = nil, false, nil, 0
    local LET_GO = { released = true, cited = true, warning = true, fled = true, dead = true }
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function finished_with() return LET_GO[out[who]] or taken[who] or (not c:near(who, 40.0) and not c:get('coming')) end
    local function check()
        if done or waiting() or c:talking() then return end
        if not (out.left or (gone and finished_with())) then return end
        done = true
        c:done('decide')
        local text, also, more = ends(out, gone), {}, {}
        for k, v in pairs(out) do
            if k ~= 'left' and k ~= who then
                if v == 'arrested' then also[#also + 1] = c:name(k)
                elseif v == 'cited' then more[#more + 1] = (' %s was given a ticket.'):format(c:name(k))
                elseif v == 'warning' then more[#more + 1] = (' %s was given a warning.'):format(c:name(k)) end
            end
        end
        table.sort(also)
        table.sort(more)
        local car = gone == 'towed' and ' The car was towed to impound.' or gone == 'moved' and ' The car was moved.' or ' The car was left where it was.'
        c:finish(text .. car .. (also[1] and (' Also arrested: ' .. table.concat(also, ', ') .. '.') or '') .. table.concat(more))
    end
    local function away(how)
        if gone then return end
        gone = how
        c:done('plate')
        c:done('car')
        c:done('move')
        check()
    end
    c:on('act', function(key, action, arg)
        local o = c:who(key)
        if action == 'cuff' and o and o.cuffed then
            out[key] = 'arrested'
            c:custody(key)
            if key == who then c:done('decide') end
        elseif action == 'uncuff' and out[key] == 'arrested' then
            out[key] = nil
            c:hide('custody:' .. key)
        elseif (action == 'cite' or action == 'warn') and out[key] ~= 'arrested' then
            out[key] = action == 'cite' and 'cited' or 'warning'
        elseif action == 'ask' and key == who and type(arg) == 'string' and (arg == 'c_tow' or arg:sub(1, 4) == 'tow_') then
            told = true -- (they've been told it's being towed: they leave it for the truck)
        elseif action == 'ask' and key == who and arg == 'c_move' then
            told = false
        end
        check()
    end)
    c:on('custody', function(key) taken[key] = true check() end)
    c:on('dead', function(key)
        out[key] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. key)
        check()
    end)
    c:on('gone', function(key)
        if out[key] == 'arrested' then taken[key] = true end
        check()
    end)
    c:on('contact_ended', function(key, outcome)
        if outcome == 'fled' then out[key] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[key] ~= 'arrested' then out[key] = outcome end
        check() -- (walked off from them, 'cancelled': nothing decided)
    end)
    c:on('tow', function(car, stage)
        if car ~= 'car' then return end
        -- ponytail: one flag, so with two units' trucks out, one called off reads as none. A count if that ever matters
        c:set('truck', stage == 'coming' or nil)
        truck_left = stage == 'coming' and 150 or 0 -- (the unit that called it may drop: no word comes then)
        if stage == 'off' then told = false end
        if stage == 'coming' and driving then -- (too late: they leave it to the truck)
            driving = nil
            c:task(who, 'scene')
        end
        c:done('plate')
    end)
    c:on('towed', function(car) if car == 'car' then away('towed') end end)
    c:on('tick', function()
        local o = c:who(who)
        local out_of_it = out[who] == 'dead' or out[who] == 'fled'
        if truck_left > 0 then
            truck_left = truck_left - 1
            if truck_left == 0 then c:set('truck', nil) end
        end
        if driving and (out_of_it or c:talking(who)) then driving = nil end -- (stopped on the way: the stop has them)
        -- on their way to it, and off in it
        if not stays and not gone and not driving and not c:get('truck') and not told and not out_of_it and o and not o.cuffed and not c:talking(who)
            and (out[who] == 'released' or out[who] == 'cited' or out[who] == 'warning' or o.facts.c_moving)
            and c:task(who, 'drive', { car = 'car' }) ~= false then
            driving = 120
        end
        if driving and not gone then
            driving = driving - 1
            if c:moved('car') > 12.0 then away('moved')
            elseif driving <= 0 then -- ponytail: couldn't get to it or get it out: they just vanish with it, even in front of a unit
                c:remove(who, 'car')
                away('moved')
            end
        elseif not gone and not c:get('truck') and c:moved('car') > 12.0 then -- (an officer moved it)
            away('moved')
        end
        check()
        -- (130 m: on foot between the car and an owner 250 m away, a unit is always near one of them)
        local here = c:near(nil, 130.0) or c:near(who, 130.0) or c:talking()
        if (c:is_done('caller') or gone) and not waiting() and not c:get('truck') and not here then
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

-- A tow truck coming for it brings them out, shouting. lines: what they shout when a unit's close, and when it's too late.
local function comes_running(c, who, shout, late)
    local running, arrived = false, false
    local function run()
        if running or c:is_done('owner') then return end -- (already found: they know)
        running = true
        c:set('coming', true)
        c:reveal('owner')
        c:reveal('decide')
        c:task(who, 'go', 'car')
    end
    c:on('tow', function(car, stage) if car == 'car' and stage == 'coming' then run() end end)
    c:on('contact', function(key) if key == who then c:set('coming', nil) end end)
    c:on('towed', function(car)
        if car == 'car' and running and not c:talking(who) then c:say(who, late) end
    end)
    c:on('tick', function()
        if not running or arrived or not c:near(who, 20.0) then return end
        arrived = true
        c:set('coming', nil)
        c:say(who, shout)
    end)
end

-- What it says about the one it's about, when it isn't an arrest.
local function other_end(c, who, v, role)
    local n = c:name(who)
    if v == 'fled' then return ('%s, %s, ran and got away.'):format(n, role) end
    if v == 'cited' then return ('%s, %s, was given a ticket.'):format(n, role) end
    if v == 'warning' then return ('%s, %s, was given a warning.'):format(n, role) end
    if v == 'released' then return ('%s, %s, was spoken to and let go.'):format(n, role) end
    if v == 'dead' then return ('%s, %s, died at the scene.'):format(n, role) end
end

-- Told to move it. A truck on its way: not until it's called off.
local function move_it(c, yes)
    return function()
        if c:get('truck') then return { "There's a tow truck coming for it! Call it off and I'll move it right now." } end
        return { { yes, set = { c_moving = 'yes' } } }
    end
end

Callout({
    id = 'parked',
    name = 'Parked vehicle complaint',
    voice = 'call_parked', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 3,
    weight = 1,
    enabled = true,
    reports = {
        'Caller says a vehicle has been left blocking access and nobody has come back to it.',
        "Caller reports a car parked where it shouldn't be, and they want it moved.",
        'Vehicle causing an obstruction. Caller has asked around and nobody claims it.',
    },
    -- The points each location needs, in the order /c3rplace parked walks you through them ('car': sit in a car). The first is
    -- where the call is. Place ONE of driveway, hydrant and pavement and press Z on the other two: it's what the car is
    -- blocking. Keep the owner within about 250 m of the car.
    points = {
        { 'car', 'The car, left where it is causing the problem. Sit in a car parked there.', 'car' },
        { 'driveway', 'Blocking a driveway? The caller, standing on that driveway. If not, press Z.', optional = true },
        { 'hydrant', 'Blocking a fire hydrant? The caller, beside that hydrant. If not, press Z.', optional = true },
        { 'pavement', 'Up on the pavement? The caller, on that pavement. If not, press Z.', optional = true },
        { 'owner', 'A door or shop entrance up the street, where the owner is found.' },
    },
    -- Add more with /c3rplace parked in game (it writes them here). This one is a rough placeholder.
    locations = {
        { street = 'Nikola Pl', at = vector3(1317.71, -577.59, 72.63), points = {
            car = vector4(1317.71, -577.59, 72.63, 242.1),
            driveway = vector4(1323.43, -570.91, 73.06, 8.7),
            owner = vector4(1311.94, -566.81, 72.04, 183.0),
        } },
        { street = 'San Andreas Ave', at = vector3(361.06, -841.47, 28.73), points = {
            car = vector4(361.06, -841.47, 28.73, 91.1),
            hydrant = vector4(361.19, -835.97, 29.29, 215.3),
            owner = vector4(382.56, -833.80, 29.29, 151.3),
        } },
        { street = 'Calais Ave', at = vector3(-551.20, -1216.70, 16.74), points = {
            car = vector4(-551.20, -1216.70, 16.74, 171.8),
            pavement = vector4(-544.06, -1211.55, 17.58, 86.1),
            owner = vector4(-535.58, -1218.23, 18.46, 117.3),
        } },
        { street = 'Route 68', at = vector3(323.88, 2635.63, 44.15), points = {
            car = vector4(323.88, 2635.63, 44.15, 277.1),
            pavement = vector4(316.30, 2634.12, 44.40, 326.0),
            owner = vector4(318.92, 2621.83, 44.41, 318.4),
        } },
        { street = 'Paleto Blvd', at = vector3(-1.70, 6553.31, 31.50), points = {
            car = vector4(-1.70, 6553.31, 31.50, 343.3),
            driveway = vector4(-1.78, 6547.26, 31.64, 198.1),
            owner = vector4(-0.40, 6513.03, 31.88, 140.8),
        } },
    },

    stories = {
        -- ── "Five minutes." ────────────────────────────────────────────────────────────────────────────────────
        selfish = {
            weight = 3,
            setup = function(c)
                local key, spot = spot_of(c)
                local male = math.random() < .5
                caller(c, key, spot, {
                    c_long = { { 'Two hours. At least. I watched them leave it.', set = { c_hours = 'yes' } } },
                    c_saw = { ('Someone in a hurry. Locked it, walked off up the street, never looked back. %s'):format(male and 'A man.' or 'A woman.') },
                    c_whose = { 'No idea. Somebody from up the street, I think.' },
                })
                c:person('owner', { at = 'owner', label = 'Owner', male = male, home = 'owner', secret = math.random() < .25 and 'suspended' or 'clean',
                    demeanor = math.random() < .5 and 'rude' or 'polite', scene = 'WORLD_HUMAN_SMOKING', questions = OWNER_Q, lines = {
                        c_yours = { 'Yes. Is there a problem?' },
                        c_why = { "I only nipped in for five minutes. There's nowhere else to park round here." },
                        c_hours = cracks(2, { 'Five minutes. Ten, tops.', "Well, they're exaggerating." },
                            { { '...Alright. A bit longer than that. I lost track of time.', set = { c_admit = 'yes' } } },
                            { 'I said. I lost track of time.' }),
                        c_move = move_it(c, "Alright, alright. I'm going."),
                        c_tow = { "You're towing it? You can't do that! How much is that going to cost me?" },
                        where = { 'Nowhere. I was just on my way back to it.' },
                    } })
                the_car(c, { owner = 'owner' }, spot, 'Locked, nobody in it, and the bonnet is stone cold: it has been here a good while. A coffee cup in the holder and a work lanyard on the seat.')
                card(c, { owner = 'Find the owner', owner_hint = 'Dispatch has the address: marked on your map.', who = 'owner' })
                wire(c, 'owner', spot, function()
                    ran_plate(c, ' No answer on the phone. Marking the address on your map.')
                    c:reveal('owner')
                end)
                c:on('fact', function(_, fact)
                    if fact == 'c_hours' then
                        c:who('owner').facts.c_hours = true
                        c:questions('owner')
                    end
                end)
                comes_running(c, 'owner', "Hey! HEY! That's my car! What are you doing?", "No! No, no, no! Come back with that!")
                resolve(c, 'owner', function(out)
                    if out.owner == 'arrested' then return ('Vehicle obstruction: %s, the owner, was arrested.'):format(c:name('owner')) end
                    return other_end(c, 'owner', out.owner, 'the owner') or 'Vehicle obstruction: nothing was decided about the owner.'
                end)
            end,
        },

        -- ── A war over the fence. ──────────────────────────────────────────────────────────────────────────────
        feud = {
            weight = 2,
            needs = { 'driveway' },
            setup = function(c)
                local key, spot = spot_of(c)
                local male = math.random() < .5
                local them = male and 'him' or 'her'
                c:person('owner', { at = 'owner', label = 'Neighbour', male = male, home = 'owner', secret = 'clean', demeanor = 'rude',
                    scene = 'WORLD_HUMAN_SMOKING', questions = OWNER_Q, lines = {
                        c_yours = { "Yes. And it's staying there until they've learned something." },
                        c_why = { "It's a public road, isn't it? They put a skip on my side of the fence for a month. Let them see how it feels." },
                        c_scratch = { 'They did what? That was them! You ask them about that! Ticket THEM!' },
                        c_move = move_it(c, "Fine. FINE. I'll move it. This isn't over, tell them that."),
                        c_tow = { 'Go on then. I hope you ask them what they did to it.' },
                        where = { 'Back to my own front door. Unless that is illegal now as well.' },
                    } })
                local paint = the_car(c, { owner = 'owner' }, spot, "Locked, nobody in it. A long fresh scratch along the driver's door, wing to tail: bright metal, not a speck of rust. A key did that.")
                caller(c, key, spot, {
                    c_long = { 'Since last night. It was there when I got up.' },
                    c_saw = { { ("I don't need to see. It's %s next door. %s does it on purpose."):format(them, male and 'He' or 'She'), set = { c_feud = 'yes' } } },
                    c_whose = { { "Next door's. They've been at this for weeks. It started over the fence.", set = { c_feud = 'yes' } } },
                    c_scratch = cracks(3, { "What scratch? It could've been there for months.", "Don't look at me." },
                        { { '...Alright. I keyed it. This morning. After weeks of this, they are lucky that is all I did.', set = { c_admit = 'yes' } } },
                        { 'I told you. I keyed it.' }),
                }, { ('House keys, %s paint on one of them'):format(paint[1]:lower()) })
                card(c, { owner = 'Find the owner', owner_hint = 'Dispatch has the address: marked on your map.', who = 'owner' })
                wire(c, 'owner', spot, function()
                    ran_plate(c, ' No answer on the phone. Marking the address on your map.')
                    c:reveal('owner')
                end)
                c:on('inspect', function(clue)
                    if clue ~= 'car' then return end
                    for _, p in ipairs({ 'caller', 'owner' }) do
                        local o = c:who(p)
                        if o then
                            o.facts.c_scratched = true
                            c:questions(p)
                        end
                    end
                end)
                comes_running(c, 'owner', "Oh, you're towing MY car? Ask them what they did to it!", "Unbelievable. I'll have your badge number. And I'll have them.")
                resolve(c, 'owner', function(out)
                    local keyed = c:who('caller').facts.c_admit and (' %s admitted keying the car.'):format(c:name('caller'))
                        or c:who('caller').facts.found and " Recorded: paint on the caller's key." or ''
                    if out.owner == 'arrested' then return ('Neighbour dispute: %s, who parked across the driveway, was arrested.'):format(c:name('owner')) .. keyed end
                    return (other_end(c, 'owner', out.owner, 'who parked across the driveway on purpose') or 'Neighbour dispute: the owner of the car was not dealt with.') .. keyed
                end)
            end,
        },

        -- ── Not theirs. ────────────────────────────────────────────────────────────────────────────────────────
        stolen = {
            weight = 2,
            setup = function(c)
                local key, spot = spot_of(c)
                caller(c, key, spot, {
                    c_long = { 'Since this morning. Early.' },
                    c_saw = { { 'A young guy, hood up. Got out, looked up and down the street, and went off that way. He kept looking back at it.', set = { c_left = 'yes' } } },
                    c_whose = { 'No idea. Never seen it round here before.' },
                })
                c:person('runner', { at = 'owner', label = 'Man', male = true, age = { 18, 26 }, secret = math.random() < .5 and 'warrant' or 'drugs',
                    demeanor = 'nervous', scene = 'WORLD_HUMAN_SMOKING', questions = RUNNER_Q,
                    items = { 'Flathead screwdriver, its tip chewed up' }, lines = {
                        c_here = { 'Waiting for someone.', 'Nothing. Just standing here.' },
                        c_car = cracks(3, { 'What car?', "Never seen it. I don't even drive." },
                            { { "...It was just to get across town. I was going to leave it somewhere. I didn't think anyone would care where.", set = { c_admit = 'yes' } } },
                            { 'I said. It was just to get across town.' }),
                        c_seen = { "They've got it wrong. Everyone wears a hoodie." },
                        where = { 'Nowhere. Just waiting.' },
                    } })
                the_car(c, { stolen = true }, spot, "Locked up, but the driver's window has been forced at the top, and the ignition's been prised apart with the wires hanging out: hot-wired.")
                card(c, { owner = 'Find whoever left it', owner_hint = "They can't have gone far.", who = 'runner' })
                local function left()
                    c:reveal('owner')
                    local o = c:who('runner')
                    if o then
                        o.facts.c_seen = true
                        c:questions('runner')
                    end
                end
                wire(c, 'runner', spot, function()
                    ran_plate(c, ' That vehicle is reported stolen. The owner is at work and is not coming out for it. It needs recovering.')
                end)
                c:on('fact', function(_, fact) if fact == 'c_left' then left() end end)
                c:on('inspect', function(clue) if clue == 'car' then c:reveal('owner') end end)
                -- asked for his ID, he may bolt (a moment after, or the stop's first order overrides it)
                local bolting, asked = false, false
                c:on('act', function(who, action)
                    if who ~= 'runner' or action ~= 'licence' or asked then return end
                    asked = true
                    bolting = math.random() < .5
                end)
                c:on('tick', function()
                    if not bolting then return end
                    bolting = false
                    if c:talking('runner') and not c:who('runner').cuffed then c:task('runner', 'flee') end
                end)
                resolve(c, 'runner', function(out, gone)
                    if out.runner == 'arrested' then
                        return (gone == 'towed' and 'Stolen vehicle recovered: %s arrested.' or 'Stolen vehicle: %s arrested.'):format(c:name('runner'))
                            .. (c:who('runner').facts.c_admit and ' Recorded: an admission.' or '')
                            .. (c:who('runner').facts.found and ' Recorded: the screwdriver on him.' or '')
                    end
                    return other_end(c, 'runner', out.runner, 'who left the stolen car') or 'Stolen vehicle: whoever left it was not dealt with.'
                end, true)
            end,
        },

        -- ── Not empty after all. ───────────────────────────────────────────────────────────────────────────────
        asleep = {
            weight = 2,
            setup = function(c)
                local key, spot = spot_of(c)
                caller(c, key, spot, {
                    c_long = { 'I saw it when I got up. I think it was there all night. The engine has been running the whole time.' },
                    c_saw = { "I didn't. I haven't been near it. I banged on the roof and nothing happened, so I called you." },
                    c_whose = { 'No idea. Never seen it round here before.' },
                })
                c:person('driver', { at = 'car', seated = 'car', label = 'Driver', secret = 'drunk', demeanor = 'chatty', facts = { c_seen_drunk = true }, questions = OWNER_Q, lines = {
                    c_yours = { "'Course it's mine. 'S outside my house." },
                    c_why = { "This is my house. Is this... is this not my house?" },
                    c_drove = cracks(2, { 'I walked. No. Hang on.', "I've been here for ages. Hours." },
                        { { "...I had a few at the bar. I got home. Nearly home. Then I had a little sleep.", set = { c_admit = 'yes' } } },
                        { "I said. I nearly got home." }),
                    c_move = move_it(c, "No problem. No problem at all. Watch this."),
                    c_tow = { "Towed? But I'm home. Am I home?" },
                    where = { 'Home. Am I not there?' },
                } })
                the_car(c, { owner = 'driver', locked = false }, spot, 'The engine is running, and somebody is slumped at the wheel, chin on their chest. An empty bottle in the footwell.')
                card(c, { owner = 'Find the owner', owner_hint = 'Dispatch has no answer on the phone.', who = 'driver' })
                wire(c, 'driver', spot, function()
                    ran_plate(c, ' No answer on the phone.')
                    c:reveal('owner')
                end)
                c:on('inspect', function(clue) if clue == 'car' then c:reveal('owner') end end)
                local blew = false
                c:on('act', function(who, action)
                    local o = c:who(who)
                    if who == 'driver' and action == 'breath' and (tonumber(o.truth.bac) or 0) >= Config.Tests.bac_limit then blew = true end
                end)
                resolve(c, 'driver', function(out)
                    local test = blew and ' Recorded: a breath test over the limit.' or ''
                    if out.driver == 'arrested' then
                        return ('Vehicle obstruction: %s found at the wheel, drunk, and arrested.'):format(c:name('driver'))
                            .. (c:who('driver').facts.c_admit and ' Recorded: an admission.' or '') .. test
                    end
                    return (other_end(c, 'driver', out.driver, 'found at the wheel') or 'Vehicle obstruction: the driver was not dealt with.') .. test
                end)
            end,
        },
    },
})
