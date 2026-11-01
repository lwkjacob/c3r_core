--[[
    c3r callout: SHOTS HEARD.

    Someone heard bangs. The report is the same every time, and the card is too: the caller, a neighbour, and searching the
    area (three units can take one each). What it really was is one of six stories:
      fireworks  teenagers behind the houses; real rockets go up, and they may run
      backfire   an old car and its owner; it bangs in front of you, and nobody's in trouble
      drunk      a man firing into the air at a party, usually glad to hand it over
      driveby    someone's been shot, and the shooter's car is still close: they drive off when you get near, and if you put
                 the lights on them, they floor it
      homeowner  a homeowner shot a burglar and is standing over them with the gun. Talk it down: a gun on them doesn't help
      accident   a gun cleaned at a kitchen table, and a shot through the wall into next door
    It's dealt with when whoever's arrested has been taken in, whoever's hurt has been seen to, and whoever's responsible has
    been let go or got away, or the caller's been heard, the source found and every unit has left.

    Points per location: walk them out in game with /c3rplace shots (it writes the location in below).
]]

local CALLER_Q = {
    { id = 'c_what', label = 'What did you hear?' },
    { id = 'c_way', label = 'Which way did it come from?' },
    { id = 'c_many', label = 'How many bangs?' },
    { id = 'c_see', label = 'Did you see anything?' },
}
local NEIGHBOUR_Q = {
    { id = 'c_saw', label = 'Did you see what happened?', stress = true, press = true },
    { id = 'c_know', label = 'Do you know who is around here?' },
    { id = 'c_car', label = 'Did you see a car?', needs = { c_source = true }, stress = true },
}
local SUBJECT_Q = {
    { id = 'c_here', label = "What's been going on here?", stress = true },
    { id = 'c_bang', label = 'We had a report of gunshots.', stress = true, press = true },
    { id = 'c_gun', label = 'Is there a gun here?', stress = true, press = true },
    { id = 'c_left', label = 'Why did you drive off when you saw us?', needs = { c_moved = true }, stress = true, press = true },
}
local CALLED = { subject = 'The suspect', hurt = 'The injured person' }
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
    c:objective('caller', 'Talk to the caller', { hint = 'On their doorstep.', blip = 'caller' })
    c:objective('neighbour', 'Talk to the neighbour', { hint = 'They saw or heard more.', blip = 'neighbour' })
    c:objective('search', 'Search the area', { hint = 'Ask which way it came from.' })
    c:objective('source', "Find who's responsible", { hidden = true, hint = 'What you found should say where to look.' })
    c:objective('medic', 'Get paramedics for the injured person', { hidden = true, who = 'all', blip = 'hurt', hint = 'Radio for an ambulance.' })
    c:objective('medic2', 'Call paramedics for the suspect', { hidden = true, who = 'all', blip = 'subject', hint = 'Radio for an ambulance.' })
    c:objective('standoff', 'Get the gun off them', { hidden = true, who = 'all', blip = 'subject', hint = 'Press E beside them, or use the PA. Keep your gun down if you can.' })
    c:objective('gunman', 'Stop the gunman', { hidden = true, who = 'all', blip = 'subject', hint = 'Take cover. They give up if they have to.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'source' }, who = 'all' })
end

-- Done when: the caller's said what they heard, the neighbour what they saw, the spot's been found, the source reached.
local function wire(c)
    c:on('act', function(who, action, arg)
        if action ~= 'ask' then return end
        if who == 'caller' and arg == 'c_what' then c:done('caller') end
    end)
    c:on('fact', function(_, fact)
        if fact == 'c_way' then c:blip('search', 'spot') end
        if fact == 'c_source' then
            c:done('neighbour')
            c:reveal('source')
            c:blip('source', c:get('car_first') and 'their_car' or 'subject')
        end
    end)
    c:on('inspect', function(clue)
        if clue == 'spot' then
            c:done('search')
            c:reveal('source')
            c:blip('source', c:get('car_first') and 'their_car' or 'subject')
            if c:who('hurt') then c:reveal('medic') end
        end
        if clue == 'their_car' then c:set('car_seen', true) end
    end)
    c:on('contact', function(who)
        if who ~= 'subject' then return end
        c:reveal('source')
        c:done('source')
        c:done('search')
        c:reveal('their_car')
        c:blip('decide', 'subject')
        if c:who('hurt') then c:reveal('medic') end -- (the search is off the card now: don't lose them)
    end)
    c:on('dead', function(who)
        if who == 'caller' then c:done('caller') end
        if who == 'neighbour' then c:done('neighbour') end
    end)
    c:on('tick', function() if c:who('hurt') and c:near('hurt', 15.0) then c:reveal('medic') end end)
end

-- They're fighting, until hurt, told to stop half the time (if `talked` isn't set: then always), or 45-120 s with units
-- near. -> start(from), give_up(line)
local function fight(c, talked)
    local fighting, left = false, 0
    local function give_up(line)
        fighting = false
        local o = c:who('subject')
        o.ran, o.gave_up = true, true
        c:done('gunman')
        c:done('standoff')
        c:reveal('source')
        c:done('source')
        c:blip('decide', 'subject')
        c:say('subject', line)
        c:task('subject', 'surrender')
    end
    local function start()
        fighting, left = true, math.random(45, 120)
        c:task('subject', 'shoot')
    end
    c:on('fired', function(who)
        if who ~= 'subject' then return end
        c:reveal('gunman')
        c:dispatch('Shots fired! All units, shots fired!')
        c:note('The suspect fired at officers')
    end)
    c:on('tick', function()
        if not fighting then return end
        local health = c:health('subject')
        left = c:near('subject', 45.0) and left - 1 or left
        if health and health > 100 and health < 150 then give_up("Okay! Okay, I'm hit! I'm done!")
        elseif left <= 0 then give_up("That's it! I'm done, don't shoot! It's down!") end
    end)
    c:on('hail', function(who)
        if who == 'subject' and (talked or fighting) and (talked or math.random() < 0.5) then give_up(talked or "Alright! Alright! I'm putting it down!") end
    end)
    c:on('dead', function(who) if who == 'subject' then fighting = false end end)
    return start, give_up
end

-- A unit within `m` m, on foot or not, and nobody's spoken to them yet: `odds` they open up.
local function may_fire(c, start, m, odds)
    local reacted = false
    c:on('contact', function(who) if who == 'subject' then reacted = true end end)
    c:on('tick', function()
        local o = c:who('subject')
        if reacted or not o or o.cuffed or c:get('dead_subject') or c:get('moving') or not c:near('subject', m) or c:talking() then return end
        reacted = true
        if math.random() < odds then start() end
    end)
end

-- Spoken to for the first time, on foot: `odds` they bolt.
local function may_bolt(c, odds)
    local spoken, bolting = false, false
    c:on('contact', function(who)
        if who ~= 'subject' or spoken then return end
        spoken = true
        local o = c:who('subject')
        bolting = o.role ~= 'driver' and not o.gave_up and math.random() < odds
    end)
    c:on('tick', function()
        if not bolting then return end
        bolting = false
        if c:talking('subject') then c:task('subject', 'flee') end
    end)
end

-- A unit close: they're off to the next parking spot (if there is one), until someone reaches them.
local function drives_off(c)
    local moved, reached = false, false
    c:on('contact', function(who) if who == 'subject' then reached = true c:set('moving', false) end end)
    c:on('parked', function(who) if who == 'subject' then c:set('moving', false) end end)
    c:on('tick', function()
        local o = c:who('subject')
        if moved or reached or not o or o.cuffed or c:get('dead_subject') or not c:near('subject', 45.0) then return end
        moved = true
        if c:task('subject', 'drive', { car = 'their_car', to = 'next' }) == false then return end
        c:set('moving', true)
        o.facts.c_moved = 'yes'
    end)
end

--[[ It's over when everyone arrested has been taken in, whoever's hurt has been seen to, and the one responsible has been
     dealt with; or the caller's been heard, the source found and every unit has left. ends(out) -> the MDT summary; out.subject
     and out.hurt = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' | 'pronounced' | 'hospital'; out.left = true. ]]
local function resolve(c, ends)
    local out, taken, away_for, done = {}, {}, 0, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local LET_GO = { released = true, cited = true, warning = true, fled = true, pronounced = true, hospital = true }
    local function check()
        if done or waiting() then return end
        local dealt = taken.subject or LET_GO[out.subject]
        local seen = not c:who('hurt') or out.hurt == 'hospital' or out.hurt == 'pronounced'
        if not ((dealt and seen) or out.left) then return end
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
        if who == 'hurt' then c:done('medic') end
        if who == 'subject' then c:done('medic2') end
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if out[who] == 'dead' then seen_to(who, 'pronounced') end -- (the coroner's been)
        if who == 'hurt' and not out.hurt then seen_to(who, 'hospital') end -- (an ambulance the call didn't hear about)
        if who == 'subject' and not out.subject then out.subject = 'fled' end
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if who ~= 'subject' and who ~= 'hurt' then return end
        if who == 'subject' then
            c:set('dead_subject', true)
            for _, id in ipairs({ 'search', 'source', 'standoff', 'gunman', 'decide' }) do c:done(id) end
            c:reveal('medic2')
        else
            c:reveal('medic')
        end
        c:dispatch(('%s is down. Paramedics needed at the scene.'):format(CALLED[who]))
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' then seen_to(who, 'pronounced')
        elseif what == 'hospital' or what == 'treated' then seen_to(who, 'hospital') end
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or out[who] == 'pronounced' or out[who] == 'hospital' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        if who == 'subject' and LET_GO[out[who]] then c:done('decide') end
    end)
    c:on('tick', function() -- (the hurt and the responsible are dealt with in either order: one place to look)
        check()
        local here = c:near(nil, 80.0) or c:near('subject', 80.0) or c:near('hurt', 80.0) or c:talking()
        if c:is_done('caller') and c:is_done('source') and not waiting() and not here then
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

-- What the summary says: what it was, then the one responsible, then whoever was hurt.
local function report(c, out, what)
    local s = c:name('subject')
    local how = out.subject
    local text = what
    if how == 'arrested' then text = text .. (' %s was arrested.'):format(s)
    elseif how == 'cited' or how == 'warning' then text = text .. (' %s was given a %s.'):format(s, how == 'cited' and 'ticket' or 'warning')
    elseif how == 'released' then text = text .. (' %s was spoken to and let go.'):format(s)
    elseif how == 'fled' then text = text .. (' %s got away.'):format(s)
    elseif how == 'dead' or how == 'pronounced' then text = text .. (' %s died at the scene.'):format(s)
    elseif how == 'hospital' then text = text .. (' %s was taken to hospital.'):format(s)
    elseif c:is_done('source') then text = text .. (' %s was spoken to.'):format(s)
    else text = text .. ' Nobody was found responsible.' end
    if c:who('hurt') then
        local name = c:name('hurt')
        if out.hurt == 'hospital' then text = text .. (' %s was taken to hospital.'):format(name)
        elseif out.hurt == 'dead' or out.hurt == 'pronounced' then text = text .. (' %s died at the scene.'):format(name)
        else text = text .. (' %s was left at the scene.'):format(name) end
    end
    local o, list = c:who('subject'), {}
    if o and o.facts.found then list[#list + 1] = 'what was found on them' end
    if o and o.facts.c_admit then list[#list + 1] = 'the admission' end
    if c:get('car_seen') then list[#list + 1] = 'what was in the vehicle' end
    if how == 'arrested' and list[1] then text = text .. ' Recorded: ' .. table.concat(list, ', ') .. '.' end
    return text
end

-- The two who heard it, and what's on the ground.
local function witnesses(c, caller, neighbour, spot)
    c:person('caller', { at = 'caller', label = 'Caller', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = CALLER_Q, lines = caller })
    c:person('neighbour', { at = 'neighbour', label = 'Neighbour', scene = 'WORLD_HUMAN_SMOKING', questions = NEIGHBOUR_Q, lines = neighbour })
    spot.at, spot.label = 'spot', spot.label or 'Something on the ground'
    c:clue('spot', spot)
end

-- Whoever's responsible. spec: the person (spec.car: their car, and what it tells you, spec.stash)
local function subject(c, spec, lines)
    lines.where = lines.where or { "Nowhere. I've been here." }
    c:person('subject', { at = 'subject', label = spec.label or 'Person', male = spec.male, age = spec.age, secret = spec.secret or 'nervous', demeanor = spec.demeanor or 'nervous',
        items = spec.items or {}, weapon = spec.weapon, runs = spec.runs, model = spec.model, scene = spec.scene or 'WORLD_HUMAN_STAND_IMPATIENT', questions = SUBJECT_Q, lines = lines })
    if spec.car then
        spec.car.at, spec.car.owner, spec.car.label, spec.car.locked = 'their_car', 'subject', 'Their vehicle', false
        c:vehicle('their_car', spec.car)
        if spec.stash then c:clue('their_car', { on = 'their_car', label = 'Their vehicle', hidden = true, text = spec.stash }) end
    end
end

local function injured(c, label, male)
    c:person('hurt', { at = 'hurt', label = label, male = male, secret = 'clean', injured = true })
end

Callout({
    id = 'shots',
    name = 'Shots heard',
    voice = 'call_shots', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        "Caller heard what sounded like gunshots nearby. They can't say where from.",
        'Several loud bangs in the area. Caller thinks it was shots.',
        "Loud pops, then nothing. Caller doesn't want to go and look.",
    },
    -- The points each location needs, in the order /c3rplace shots walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it).
    -- Skip the optional ones with Z in /c3rplace: without `hurt`, nobody's been shot there; without `next`, nobody drives off.
    points = {
        { 'caller', 'The caller, on their doorstep.' },
        { 'neighbour', 'A neighbour, out on the street or a yard close by.' },
        { 'spot', 'Where it happened: on the ground, a little way off.' },
        { 'subject', 'Whoever did it: in a back yard, an alley or by a parked car, near that spot.' },
        { 'their_car', 'A vehicle parked beside them. Sit in a car parked there.', 'car' },
        { 'next', 'Where the vehicle goes if it drives off, a street or so away. Sit in a car parked there.', 'car', optional = true },
        { 'hurt', 'Someone hurt: on the ground, about 3 m from whoever did it.', optional = true },
    },
    -- Add more with /c3rplace shots in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Grove St', at = vector3(79.79, -1948.23, 21.17), points = {
            caller = vector4(79.79, -1948.23, 21.17, 281.2),
            neighbour = vector4(81.45, -1934.32, 20.75, 264.5),
            spot = vector4(83.80, -1969.53, 20.75, 148.4),
            subject = vector4(85.58, -1972.90, 20.81, 28.6),
            their_car = vector4(89.33, -1967.45, 20.34, 323.0),
            hurt = vector4(85.68, -1967.23, 20.75, 313.8),
        } },
        { street = 'Nikola Ave', at = vector3(975.98, -579.67, 59.64), streets = { next = 'West Mirror Drive' }, points = {
            caller = vector4(975.98, -579.67, 59.64, 32.6),
            neighbour = vector4(967.07, -580.25, 58.90, 12.8),
            spot = vector4(965.65, -545.65, 59.43, 40.1),
            subject = vector4(972.33, -542.72, 59.41, 130.4),
            their_car = vector4(974.61, -554.51, 58.70, 124.9),
            next = vector4(901.27, -578.97, 56.87, 62.0),
            hurt = vector4(968.14, -545.22, 59.37, 113.2),
        } },
        { street = 'Niland Ave', at = vector3(1915.68, 3824.27, 32.44), streets = { subject = 'Zancudo Ave', their_car = 'Zancudo Ave', next = 'Zancudo Ave' }, points = {
            caller = vector4(1915.68, 3824.27, 32.44, 112.3),
            neighbour = vector4(1917.67, 3820.51, 32.26, 183.2),
            spot = vector4(1928.82, 3797.06, 32.13, 240.1),
            subject = vector4(1938.86, 3794.83, 32.04, 94.2),
            their_car = vector4(1938.83, 3792.14, 31.69, 131.6),
            next = vector4(1818.95, 3713.86, 33.23, 120.6),
        } },
    },

    stories = {
        -- ── Fireworks. ───────────────────────────────────────────────────────────────────────────────────────────
        fireworks = {
            weight = 3,
            setup = function(c)
                witnesses(c, {
                    c_what = { "Bang, bang, bang. Then a kind of whistle. Then more. It went on for ages." },
                    c_way = { { "Behind the houses, that way.", set = { c_way = 'pointed' } } },
                    c_many = { "A lot. Ten? It keeps starting up again." },
                    c_see = { "I'm not going out there to look, am I?" },
                }, {
                    c_saw = { { "Kids. It's those kids again, with their rockets. Round the back.", set = { c_source = 'yes' } } },
                    c_know = { "A few of them live on this street. They mean no harm, but my dog's under the bed." },
                    c_car = { "No. They walk everywhere." },
                }, { prop = 'ind_prop_firework_01', label = 'Burnt tubes', text = 'Burnt cardboard tubes and a scorched patch on the ground. It smells of gunpowder, but these are fireworks.' })
                subject(c, { age = { 15, 18 }, secret = 'clean', demeanor = 'rude', scene = 'WORLD_HUMAN_SMOKING', items = { 'Box of fireworks, half empty' } }, {
                    c_here = { "Nothing. Just hanging out." },
                    c_bang = cracks(2, { "Gunshots? Nah, we didn't hear anything." },
                        { { "Alright, it was us. It's only fireworks. It's not hurting anyone.", set = { c_admit = 'yes' } } },
                        { "I told you. It was fireworks." }),
                    c_gun = { "A gun? No! What? No!" },
                    c_left = { "We didn't drive anywhere. I'm sixteen." },
                    explain = { "They're fireworks. You can buy them anywhere. Nobody got hurt." },
                })
                card(c)
                wire(c)
                local next_at, clock, reached = 0, 0, false
                c:on('contact', function(who) if who == 'subject' then reached = true end end)
                c:on('tick', function()
                    clock = clock + 1
                    if reached or clock < next_at or c:get('dead_subject') or not c:near('subject', 200.0) then return end
                    next_at = clock + 35
                    c:bang('WEAPON_FIREWORK', 'subject', 2)
                end)
                may_bolt(c, 0.3)
                resolve(c, function(out) return report(c, out, 'Reported gunshots were fireworks.') end)
            end,
        },

        -- ── An old car. ──────────────────────────────────────────────────────────────────────────────────────────
        backfire = {
            weight = 2,
            setup = function(c)
                witnesses(c, {
                    c_what = { "One big bang. Then another a minute later. I thought somebody was being shot." },
                    c_way = { { "Down the road that way, I think.", set = { c_way = 'pointed' } } },
                    c_many = { "Two? Three? Spread out. Which is strange." },
                    c_see = { "No. I closed the curtains." },
                }, {
                    c_saw = { { "I saw a bloke round that old car of his. He didn't look worried.", set = { c_source = 'yes' } } },
                    c_know = { "He's always fixing that old thing." },
                    c_car = { "Only that wreck of his. It's been there all week." },
                }, { label = 'A dark patch', text = 'Oil on the road, and a smell of burnt petrol. No casings, no blood. Nothing here.' })
                subject(c, { male = true, age = { 40, 66 }, secret = 'clean', demeanor = 'chatty',
                    car = { model = 'emperor2', make = 'Albany', name = 'Emperor', color = 'Rust', paint = 0 } }, {
                    c_here = { "Trying to get her to run right. Timing's out. Listen to that." },
                    c_bang = { { "Gunshots? Ha! Oh, I'm sorry. That's this thing. Hear it? She backfires something awful.", set = { c_admit = 'yes' } } },
                    c_gun = { "Only a spanner, officer." },
                    c_left = { "Drive off? She won't get past the corner." },
                })
                card(c)
                wire(c)
                local next_at, clock = 0, 0
                c:on('tick', function()
                    clock = clock + 1
                    local o = c:who('subject')
                    if clock < next_at or (o and o.facts.c_admit) or not c:near('subject', 120.0) then return end
                    next_at = clock + 30
                    c:bang(PISTOL, 'their_car', 1)
                end)
                resolve(c, function(out) return report(c, out, 'Reported gunshots were a car backfiring.') end)
            end,
        },

        -- ── A drunk with a gun. ──────────────────────────────────────────────────────────────────────────────────
        drunk = {
            weight = 2,
            setup = function(c)
                witnesses(c, {
                    c_what = { "Shots. I know shots. And someone cheering. Cheering!" },
                    c_way = { { "That way, the back yards.", set = { c_way = 'pointed' } } },
                    c_many = { "Four or five. Into the air, I hope." },
                    c_see = { "No. Somebody's having a good time, by the sound of it." },
                }, {
                    c_saw = { { "Some guy in his yard, waving a pistol around. Thinks it's funny.", set = { c_source = 'yes' } } },
                    c_know = { "It's his birthday. He's been drinking since lunch." },
                    c_car = { "No. They're all parked up. Nobody's fit to drive." },
                }, { prop = 'prop_sgun_casing', label = 'Casings', text = 'Pistol casings on the ground, still warm, and beer cans. Whoever did this was celebrating.' })
                subject(c, { male = true, age = { 28, 50 }, secret = 'drunk', demeanor = 'chatty', weapon = PISTOL, scene = 'WORLD_HUMAN_DRINKING',
                    items = { 'Pistol, loaded, black' } }, {
                    c_here = { "It's my birthday! Have a drink! ...You can't, can you?" },
                    c_bang = cracks(2, { "Gunshots? What gunshots? Must be next door." },
                        { { "Alright, alright. Into the air. Nobody got hurt. It's my birthday.", set = { c_admit = 'yes' } } },
                        { "Into the air. I told you." }),
                    c_gun = { "It's legal! I think. It's in my belt. Take it, take it, I don't care." },
                    c_left = { "I'm not driving, officer. Look at me." },
                    explain = { "It's mine. It's a birthday. You've never fired one in the air? ...Alright. That was stupid." },
                })
                card(c)
                wire(c)
                local start = fight(c)
                may_fire(c, start, 12.0, 0.12)
                local banged = false
                c:on('tick', function()
                    if banged or not c:near('subject', 200.0) then return end
                    banged = true
                    c:bang(PISTOL, 'subject', 3)
                end)
                resolve(c, function(out) return report(c, out, 'Reckless discharge of a firearm at a party.') end)
            end,
        },

        -- ── A drive-by. ──────────────────────────────────────────────────────────────────────────────────────────
        driveby = {
            weight = 3,
            needs = { 'hurt' },
            setup = function(c)
                c:set('car_first', true)
                witnesses(c, {
                    c_what = { "Shots. Fast ones. Then a car, and someone yelling." },
                    c_way = { { "Over there. Please be careful.", set = { c_way = 'pointed' } } },
                    c_many = { "Five or six. Very fast." },
                    c_see = { "No, I got on the floor." },
                }, {
                    c_saw = cracks(2, { "I didn't see anything. I don't want any trouble." },
                        { { "...It was a car. He leaned out and shot the guy. It's still round here. Please don't say it was me.", set = { c_source = 'yes', c_admit = 'yes' } } },
                        { "I told you what I saw. Please." }),
                    c_know = { "I keep to myself on this street. You should too." },
                    c_car = function()
                        local plate = c:plate('their_car') or ''
                        return { ("A red Vapid Buccaneer. Loud. I got the end of the plate: %s."):format(plate:sub(-3)) }
                    end,
                }, { prop = 'prop_sgun_casing', label = 'Casings', text = 'Pistol casings on the road, a line of them, and blood going off towards the pavement.' })
                injured(c, 'Injured person', true)
                subject(c, { male = true, age = { 21, 34 }, secret = 'warrant', demeanor = 'rude', weapon = PISTOL, runs = true, items = { 'Pistol, recently fired', 'A wrap of cash' },
                    car = { model = 'buccaneer', make = 'Vapid', name = 'Buccaneer', color = 'Red', paint = 27 },
                    stash = 'Casings in the footwell, the same make as the ones on the road, and the passenger window is down.' }, {
                    c_here = { "Nothing. Waiting for a friend." },
                    c_bang = cracks(3, { "I didn't hear anything." },
                        { { "He had it coming. You don't know what he did.", set = { c_admit = 'yes' } } },
                        { "I'm not saying it again." }),
                    c_gun = { "Search me. Get a warrant. I don't care." },
                    c_left = { "You people make me nervous." },
                    explain = { "I found it. I'm not saying anything else. Get me a lawyer." },
                })
                card(c)
                wire(c)
                local start = fight(c)
                drives_off(c)
                may_fire(c, start, 6.0, 0.15)
                may_bolt(c, 0.25)
                resolve(c, function(out) return report(c, out, 'Drive-by shooting.') end)
            end,
        },

        -- ── A homeowner, and a burglar. ──────────────────────────────────────────────────────────────────────────
        homeowner = {
            weight = 2,
            needs = { 'hurt' },
            setup = function(c)
                witnesses(c, {
                    c_what = { "One shot. Maybe two. Then a man screaming, and someone shouting 'stay down'." },
                    c_way = { { "Next door but one, round the back.", set = { c_way = 'pointed' } } },
                    c_many = { "Two." },
                    c_see = { "No. I'm not looking." },
                }, {
                    c_saw = { { "He's got someone on the ground in his yard. He's got a gun. He's not moving.", set = { c_source = 'yes' } } },
                    c_know = { "He's lived there thirty years. They've been broken into twice this year." },
                    c_car = { "There was a van parked up earlier, gone now." },
                }, { prop = 'prop_ing_crowbar', label = 'A crowbar', text = 'A crowbar under a forced window, and glass on the ground. Someone came in this way. Blood goes off across the yard.' })
                injured(c, 'Injured person', true)
                subject(c, { male = true, age = { 55, 74 }, secret = 'clean', demeanor = 'nervous', weapon = PISTOL, items = { 'Pistol, one fired' } }, {
                    c_here = { "He came in the window. I told him to stop. It was my house! It's my house!" },
                    c_bang = { { "I shot him. Yes. One shot. I don't know if I should have.", set = { c_admit = 'yes' } } },
                    c_gun = { "You've got it. Take it. I never want to see it again." },
                    c_left = { "I've not left this yard." },
                    explain = { "It's mine. I keep it by the bed. I've had it thirty years and never fired it at anything but paper." },
                })
                card(c)
                wire(c)
                local start, give_up = fight(c, "Okay. Okay. It's down. I'm putting it down. He came in my house.")
                -- A gun on him: a warning. Still on him 15 s later (long enough to use the PA, which needs it), or put back on him
                -- after that: it may go wrong, once.
                local clock, warned_at, settled = 0, nil, false
                c:on('build', function() c:task('subject', 'hold') end)
                c:on('tick', function()
                    clock = clock + 1
                    if c:near('subject', 25.0) then c:reveal('standoff') end
                    local health = c:health('subject')
                    if not settled and not c:is_done('standoff') and health and health > 100 and health < 150 then
                        settled = true
                        give_up("Okay! Okay! It's down! Don't shoot!")
                    end
                end)
                c:on('aimed', function(who)
                    if who ~= 'subject' or settled or c:is_done('standoff') then return end
                    c:reveal('standoff')
                    if not warned_at then
                        warned_at = clock
                        return c:say('subject', "Don't point that at me! He's the one who broke in!")
                    end
                    if clock - warned_at < 15 then return end
                    settled = true
                    if math.random() < 0.3 then
                        start()
                    else
                        give_up("All right! All right! Don't shoot me! It's down!")
                    end
                end)
                local said = false
                c:on('tick', function()
                    if said or not c:near('hurt', 8.0) or (c:health('hurt') or 0) <= 100 then return end
                    said = true
                    c:say('hurt', "He shot me in the back! I was leaving! I was going!")
                end)
                resolve(c, function(out)
                    local text = report(c, out, 'A homeowner shot an intruder.')
                    if out.subject == 'arrested' then return text .. ' Officers did not treat it as self-defence.' end
                    if out.subject == 'released' or out.subject == 'warning' or out.subject == 'cited' then return text .. ' Officers treated it as self-defence.' end
                    return text
                end)
            end,
        },

        -- ── An accident. ─────────────────────────────────────────────────────────────────────────────────────────
        accident = {
            weight = 2,
            needs = { 'hurt' },
            setup = function(c)
                witnesses(c, {
                    c_what = { "One bang. Just one. And then someone crying." },
                    c_way = { { "The flats, I think. That way.", set = { c_way = 'pointed' } } },
                    c_many = { "One." },
                    c_see = { "No. It was the crying that made me call." },
                }, {
                    c_saw = { { "He came out white as a sheet, saying he'd done something terrible. He's round the back.", set = { c_source = 'yes' } } },
                    c_know = { "Nice man. Old army. Keeps himself to himself." },
                    c_car = { "No. Nobody's left." },
                }, { label = 'A hole in the wall', text = 'A neat hole through the wall, at chest height, and a pistol cleaning kit left open on the step. Someone on the other side of that wall may be hurt.' })
                injured(c, 'Injured person', false)
                subject(c, { male = true, age = { 45, 68 }, secret = 'clean', demeanor = 'nervous', items = { 'Pistol, the slide still locked back' } }, {
                    c_here = { "I was cleaning it. I thought it was empty. I always check. I always check." },
                    c_bang = { { "It was me. It went through the wall. Is she alive? Please. Is she alive?", set = { c_admit = 'yes' } } },
                    c_gun = { "In my belt. I can't look at it." },
                    c_left = { "I haven't gone anywhere." },
                    explain = { "It's mine. I've had it since the army. I checked it. I swear I checked it." },
                })
                card(c)
                wire(c)
                resolve(c, function(out) return report(c, out, 'Accidental discharge through a wall into the next flat.') end)
            end,
        },
    },
})
