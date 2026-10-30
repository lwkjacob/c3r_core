--[[
    c3r callout: HIT AND RUN.

    Someone's been hit by a car that didn't stop. What really happened is one of three stories, and the card, the people
    on scene and the questions are the same for all of them: the victim (first aid, then paramedics), the witness and
    the road (three units can take one each). What the witness saw of the car and its plate, and what it left on the
    road, gets a match from dispatch: then the car, and whoever was driving it.
      drunk     the owner drove home drunk: the car's outside his house with its front end smashed, and he's at the door
      stolen    the car was stolen this morning and dumped round the corner, hot-wired; whoever was driving it is hiding
                close by
      back      the driver panicked and drove home, and walks back to the scene three or four minutes in. The witness:
                the victim stepped out between parked cars, he never had a chance
    It's dealt with when the victim has been seen to by paramedics and the driver has been dealt with (taken in, given a
    ticket or a warning, let go, or got away), or the witness has been heard and every unit has left.

    Points per location: walk them out in game with /c3rplace hitrun (it writes the location in below).
]]

-- The car that hit them: picked per call. Spawn names, makes and names checked against the game's vehicle list;
-- paint ids against docs.fivem.net's vehicle colours.
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

local WITNESS_Q = {
    { id = 'c_saw', label = 'What did you see?' },
    { id = 'c_car', label = 'What was the car like?' },
    { id = 'c_plate', label = 'Did you get the plate?' },
    { id = 'c_driver', label = 'Did you see the driver?' },
    { id = 'c_way', label = 'Which way did it go?' },
}
-- whoever's found: the owner at home, the one who ran from the car, the man who came back
local DRIVER_Q = {
    { id = 'c_where', label = 'Where were you twenty minutes ago?', stress = true },
    { id = 'c_damage', label = 'How did the front of the car get smashed?', needs = { c_seen_car = true }, stress = true },
    { id = 'c_hit', label = 'Did you hit someone with a car tonight?', stress = true, press = true },
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

-- 4KQ -> "4, K, Q"
local function spell(s) return (s:gsub('(.)', '%1, ')):sub(1, -3) end

-- The witness's account of the car: the same questions in every story, what they saw is the story's. c_colour and
-- c_partial are what dispatch needs for a match.
local function witness(c, car, paint, lines)
    lines.c_car = { { ('%s %s %s. %s, definitely. The front end will be wrecked, the noise it made.'):format(
        paint[1]:match('^[AEIOU]') and 'An' or 'A', paint[1]:lower(), car.make .. ' ' .. car.name, paint[1]), set = { c_colour = paint[1] } } }
    lines.c_plate = function()
        local first = (c:plate('car') or '???'):sub(1, 3)
        return { { ("It started %s... That's all I got before it was gone."):format(spell(first)), set = { c_partial = first } } }
    end
    c:person('witness', { at = 'witness', label = 'Witness', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = WITNESS_Q, lines = lines })
end

local function victim(c, male)
    c:person('victim', { at = 'victim', label = 'Victim', male = male, secret = 'clean', injured = true })
end

local function car_of(c, car, paint, spec)
    spec.at, spec.model, spec.make, spec.name, spec.color, spec.paint = 'car', car.model, car.make, car.name, paint[1], paint[2]
    spec.label, spec.damage = 'The car', 'front'
    c:vehicle('car', spec)
end

-- What it left on the road: the colour and the make, for the match.
local function debris(c, car, paint)
    c:clue('debris', { at = 'debris', label = 'The road', prop = 'v_ind_cs_hubcap',
        text = ('Broken headlight glass across the road, skid marks that stop short, and a hubcap with %s paint scraped onto the rim. A %s badge on it.')
            :format(paint[1]:lower(), car.make) })
end

local function card(c, o)
    c:objective('victim', 'Check on the victim', { hint = 'First aid: E beside them.', blip = 'victim' })
    c:objective('witness', 'Talk to the witness', { hint = 'Ask about the car, and the plate.', blip = 'witness' })
    c:objective('road', 'Search the road', { hint = 'Where it hit them: anything the car left behind.', blip = 'debris' })
    c:objective('hospital', 'Get the victim to hospital', { after = { 'victim' }, blip = 'victim',
        hint = 'Call an ambulance from beside them (the medical wheel): paramedics see to anyone hurt near where you called.' })
    c:objective('car', o.car, { hidden = true, blip = 'car', hint = o.car_hint })
    c:objective('driver', o.driver, { hidden = true, blip = o.who, hint = o.driver_hint })
    c:objective('decide', 'Deal with the driver: arrest, ticket or warn, or let them go', { hidden = true, who = 'all', blip = o.who })
end

-- Done when: the victim's seen to (first aid) and taken by paramedics, the witness says what they saw, the road's been
-- searched, the car's been looked at. Talking to whoever was driving finds them.
local function wire(c, who)
    c:on('act', function(key, action, arg)
        if key == 'witness' and action == 'ask' and arg == 'c_saw' then c:done('witness') end
    end)
    c:on('inspect', function(clue)
        if clue == 'debris' then c:done('road') end
        if clue == 'car' then
            c:done('car')
            local d = c:who(who)
            if d then d.facts.c_seen_car = true c:questions(who) end -- (now there's something to put to them)
        end
    end)
    c:on('aid', function(key, what)
        if key ~= 'victim' then return end
        c:done('victim')
        if what == 'hospital' or what == 'treated' then c:done('hospital') end
    end)
    c:on('gone', function(key) if key == 'victim' then c:done('victim') c:done('hospital') end end)
    c:on('contact', function(key)
        if key ~= who then return end
        c:reveal('driver')
        c:done('driver')
        c:reveal('decide')
    end)
    local said = false -- (heard as the first unit gets close)
    c:on('tick', function()
        if said or not c:near('witness', 30.0) then return end
        said = true
        c:say('witness', "Over here! Quick, they're hurt bad!")
    end)
end

-- Dispatch runs the partial plate once they have it and the colour (from the witness, or the paint on the road):
-- then(text) with the match, the car on the map.
local function match(c, car, paint, tail)
    local said = false
    local function try()
        if said or not (c:get('colour') and c:get('partial')) then return end
        said = true
        local o = c:owner('car') or {}
        local text = ('Ran that partial with the colour: a %s %s %s, plate %s, registered to %s %s, %s.'):format(paint[1]:lower(),
            car.make, car.name, c:plate('car') or 'unknown', o.first or 'unknown', o.last or '', o.address or 'no fixed address') .. tail
        c:dispatch(text)
        c:note('Vehicle match: ' .. text)
        c:reveal('car')
    end
    c:on('fact', function(_, fact)
        if fact == 'c_colour' then c:set('colour', true) end
        if fact == 'c_partial' then c:set('partial', true) end
        try()
    end)
    c:on('inspect', function(clue) if clue == 'debris' then c:set('colour', true) try() end end)
end

--[[ It's over when the victim has been seen to by paramedics and the driver (culprit) dealt with: taken in, given a
     ticket or a warning, let go, or got away. Or the witness has been heard and every unit has left the scene and the
     driver with nobody mid-conversation. ends(out) -> the MDT summary (anyone else arrested, ticketed or warned, and
     what happened to the victim, is added); out = { [person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled',
     left = true }. ]]
local function resolve(c, culprit, ends)
    local out, taken, care, away_for, done = {}, {}, nil, 0, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function let_go(v) return v == 'released' or v == 'cited' or v == 'warning' or v == 'fled' end
    local function check()
        if done or waiting() then return end
        if not (out.left or ((taken[culprit] or let_go(out[culprit])) and c:is_done('hospital'))) then return end
        done = true
        c:done('decide')
        local text, also, more = ends(out), {}, {}
        for k, v in pairs(out) do
            if k ~= 'left' and not text:find(c:name(k), 1, true) then
                if v == 'arrested' then also[#also + 1] = c:name(k)
                elseif v == 'cited' then more[#more + 1] = (' %s was given a ticket.'):format(c:name(k))
                elseif v == 'warning' then more[#more + 1] = (' %s was given a warning.'):format(c:name(k)) end
            end
        end
        table.sort(also)
        table.sort(more)
        local v = c:name('victim')
        local hurt = care == 'hospital' and (' %s was taken to hospital.'):format(v)
            or care == 'treated' and (' %s was treated by paramedics at the scene.'):format(v)
            or care == 'removed' and (' %s was removed from the scene.'):format(v)
            or (' %s was not seen by paramedics.'):format(v)
        c:finish(text .. (also[1] and (' Also arrested: ' .. table.concat(also, ', ') .. '.') or '') .. table.concat(more) .. hurt)
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
        elseif (action == 'cite' or action == 'warn') and out[who] ~= 'arrested' then -- (a ticket or a warning: that's them dealt with)
            out[who] = action == 'cite' and 'cited' or 'warning'
        end
        check()
    end)
    c:on('aid', function(who, what)
        if who == 'victim' and (what == 'hospital' or what == 'treated') then care = care or what end
        check()
    end)
    c:on('custody', function(who) taken[who] = true check() end)
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if who == 'victim' then care = care or 'removed' end -- (deleted without paramedics saying so: the coroner, or the game)
        check()
    end)
    c:on('contact_ended', function(who, outcome)
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        check() -- (walked off from them, 'cancelled': nothing decided)
    end)
    c:on('tick', function()
        local here = c:near(nil, 80.0) or c:near(culprit, 80.0) or c:talking()
        if c:is_done('witness') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then out.left = true check() end
        else
            away_for = 0
        end
    end)
end

-- What it says on the MDT about them, as found: 'the witness's partial plate', 'his admission'...
local function recorded(c, who, extra)
    local on = {}
    if c:who('witness').facts.c_partial then on[#on + 1] = "the witness's partial plate" end
    if c:is_done('road') then on[#on + 1] = 'the paint and glass on the road' end
    if c:is_done('car') then on[#on + 1] = 'the damage to the car' end
    for _, x in ipairs(extra or {}) do on[#on + 1] = x end
    if c:who(who).facts.c_admit then on[#on + 1] = 'an admission' end
    return on[1] and (' Recorded: ' .. table.concat(on, ', ') .. '.') or ''
end

-- What happened to the one it's about, when it isn't an arrest.
local function other_end(c, who, v, role)
    local n = c:name(who)
    if v == 'fled' then return ('%s, %s, ran and got away.'):format(n, role) end
    if v == 'cited' then return ('%s, %s, was given a ticket.'):format(n, role) end
    if v == 'warning' then return ('%s, %s, was given a warning.'):format(n, role) end
    if v == 'released' then return ('%s, %s, was spoken to and let go.'):format(n, role) end
end

Callout({
    id = 'hitrun',
    name = 'Hit and run',
    priority = 1,
    weight = 1,
    reports = {
        'Pedestrian struck by a vehicle. The vehicle did not stop.',
        "Caller says someone's been hit by a car and the driver drove off.",
        'Hit and run: a pedestrian is down in the road. Vehicle left the scene.',
    },
    -- The points each location needs, in the order /c3rplace hitrun walks you through them ('car': sit in a car).
    -- The first is where the call is (units are on scene within Config.Callouts.arrive m of it). Keep the car, the
    -- driver and the hiding place within about 250 m of the victim: they're made when a unit gets near them.
    points = {
        { 'victim', 'The person who was hit: on the ground in the road, or at the kerb.' },
        { 'witness', 'A witness who saw it, on the pavement nearby.' },
        { 'debris', 'Where the car hit them: broken glass and a hubcap on the road.' },
        { 'car', "The car, a street or two away, pulled up outside a house (in most stories, the driver's). Sit in a car parked there.", 'car' },
        { 'driver', 'The driver, at the door of that house.' },
        { 'hiding', 'Where someone who dumped the car would hide: an alley or a yard near it.' },
    },
    -- Add more with /c3rplace hitrun in game (it writes them here). This one is a rough placeholder.
    locations = {
        { street = 'Route 68', at = vector3(669.69, 2714.07, 40.76), points = {
            victim = vector4(669.69, 2714.07, 40.76, 150.9),
            witness = vector4(653.98, 2727.83, 42.00, 256.7),
            debris = vector4(662.04, 2716.97, 41.36, 189.3),
            car = vector4(537.77, 2660.91, 42.18, 196.9),
            driver = vector4(537.47, 2657.87, 42.38, 87.8),
            hiding = vector4(553.10, 2667.98, 46.95, 165.3),
        } },
        { street = 'Procopio Dr', at = vector3(-299.10, 6344.55, 31.22), streets = { witness = 'Paleto Blvd', car = 'Duluoz Ave', driver = 'Duluoz Ave', hiding = 'Duluoz Ave' }, points = {
            victim = vector4(-299.10, 6344.55, 31.22, 54.6),
            witness = vector4(-281.06, 6350.83, 32.60, 66.9),
            debris = vector4(-303.09, 6347.19, 30.86, 140.5),
            car = vector4(-354.40, 6263.55, 31.28, 137.0),
            driver = vector4(-356.35, 6266.09, 31.48, 1.8),
            hiding = vector4(-326.85, 6279.59, 31.94, 43.5),
        } },
        { street = 'Grove St', at = vector3(-71.81, -1782.74, 28.19), streets = { witness = 'Davis Ave' }, points = {
            victim = vector4(-71.81, -1782.74, 28.19, 155.7),
            witness = vector4(-48.03, -1761.61, 29.44, 145.7),
            debris = vector4(-71.56, -1786.14, 28.03, 227.9),
            car = vector4(-62.54, -1840.41, 26.50, 142.0),
            driver = vector4(-61.79, -1842.18, 26.63, 297.5),
            hiding = vector4(-70.37, -1816.19, 37.88, 209.0),
        } },
        { street = 'West Mirror Drive', at = vector3(939.20, -486.62, 60.28), points = {
            victim = vector4(939.20, -486.62, 60.28, 126.5),
            witness = vector4(923.90, -481.56, 60.70, 208.6),
            debris = vector4(934.49, -492.57, 59.84, 156.6),
            car = vector4(887.56, -553.01, 57.65, 297.8),
            driver = vector4(890.96, -548.03, 58.16, 110.8),
            hiding = vector4(903.65, -535.54, 58.14, 283.2),
        } },
    },

    stories = {
        -- ── He drove home drunk. ───────────────────────────────────────────────────────────────────────────────
        drunk = {
            weight = 3,
            setup = function(c)
                local car, paint = CARS[math.random(#CARS)], PAINTS[math.random(#PAINTS)]
                local male = math.random() < .5
                local them = male and 'him' or 'her'
                victim(c, male)
                witness(c, car, paint, {
                    c_saw = { ("It came round the corner way too fast, all over the road. Hit %s and kept going. It didn't even brake."):format(them) },
                    c_driver = { 'A man, on his own. The way he was driving, I would say he was drunk.' },
                    c_way = { "That way. Slower after, weaving. Like he was trying to look normal." },
                })
                c:person('driver', { at = 'driver', label = 'Man', male = true, home = 'driver', secret = 'drunk', demeanor = 'rude',
                    scene = 'WORLD_HUMAN_SMOKING', questions = DRIVER_Q, lines = {
                        c_where = { "Here. Home. All night.", "Out. Then home. What's it to you?" },
                        c_damage = { "Somebody must have hit it while it was parked. I just found it like that.",
                                     "It was like that this morning. Kids, probably." },
                        c_hit = cracks(3, { "Hit someone? I've been home all night!", "No. No way. Not me." },
                            { { ("...I thought it was a bin. I swear I thought it was a bin. Is %s dead? Oh God."):format(them), set = { c_admit = 'yes' } } },
                            { "I told you. I thought it was a bin." }),
                        where = { "Nowhere. I live here." },
                        live = { 'Right here. This is my house.' },
                        address = function() return { ('This house. %s.'):format(c:who('driver').person.address) } end,
                    } })
                car_of(c, car, paint, { owner = 'driver', locked = true })
                debris(c, car, paint)
                c:clue('car', { on = 'car', label = 'The car', hidden = true,
                    text = 'The front end caved in on one side, a headlight smashed, the bonnet still warm. On the passenger seat: a bottle of vodka, a third left in it.' })
                card(c, { car = 'Check the registered address', car_hint = 'Dispatch has it: marked on your map.',
                    driver = 'Talk to the owner', driver_hint = 'At the door of the house the car is outside.', who = 'driver' })
                wire(c, 'driver')
                match(c, car, paint, ' Marking the address on your map.')
                c:on('inspect', function(clue) if clue == 'car' then c:reveal('driver') end end)
                local blew = false
                c:on('act', function(who, action)
                    local o = c:who(who)
                    if who == 'driver' and action == 'breath' and (tonumber(o.truth.bac) or 0) >= Config.Tests.bac_limit then blew = true end
                end)
                resolve(c, 'driver', function(out)
                    if out.driver == 'arrested' then
                        return ('Hit and run: %s, the driver, arrested.'):format(c:name('driver'))
                            .. recorded(c, 'driver', blew and { 'a breath test over the limit' } or nil)
                    end
                    return other_end(c, 'driver', out.driver, 'the driver') or 'Hit and run: the driver was not found.'
                end)
            end,
        },

        -- ── Stolen this morning; dumped round the corner. ──────────────────────────────────────────────────────
        stolen = {
            weight = 2,
            setup = function(c)
                local car, paint = CARS[math.random(#CARS)], PAINTS[math.random(#PAINTS)]
                local male = math.random() < .5
                local them, they = male and 'him' or 'her', male and 'He' or 'She'
                victim(c, male)
                witness(c, car, paint, {
                    c_saw = { ("It came flying down the road and hit %s. Didn't slow down at all. Then it was gone."):format(them) },
                    c_driver = { "Young, I think. Hood up. Driving like it wasn't their car." },
                    c_way = { 'That way, fast. Round the corner.' },
                })
                c:person('runner', { at = 'hiding', label = 'Man', male = true, age = { 18, 26 },
                    secret = math.random() < .5 and 'warrant' or 'drugs', demeanor = 'nervous', scene = 'WORLD_HUMAN_SMOKING',
                    questions = DRIVER_Q, items = { 'Flathead screwdriver, its tip chewed up', 'Thin gloves, still warm' }, lines = {
                        c_where = { 'Walking. Just walking.', "Around. Is that a crime now?" },
                        c_damage = { "What car? I don't have a car." },
                        c_hit = cracks(3, { "I don't even drive.", 'I walked here. Look at me. Walking.' },
                            { { ("...%s came out of nowhere. I panicked. It's not even my car. I just had to get away from it."):format(they),
                                set = { c_admit = 'yes' } } },
                            { "I said. I panicked. It's not my car." }),
                        where = { 'Nowhere. Just walking.' },
                    } })
                car_of(c, car, paint, { stolen = true, locked = false })
                debris(c, car, paint)
                c:clue('car', { on = 'car', label = 'The car', hidden = true,
                    text = "Front end smashed, the driver's door left open. The ignition's been prised apart, wires hanging out: hot-wired. Scuffs on the kerb where someone jumped out and ran." })
                card(c, { car = 'Find the abandoned car', car_hint = 'Reported a couple of streets away: marked on your map.',
                    driver = 'Find whoever dumped it', driver_hint = "They ran from the car. They can't be far.", who = 'runner' })
                wire(c, 'runner')
                match(c, car, paint, " It was reported stolen this morning. And a caller's just reported one like it abandoned a couple of streets from you, door open. Marking it on your map.")
                c:on('inspect', function(clue) if clue == 'car' then c:reveal('driver') end end)
                resolve(c, 'runner', function(out)
                    if out.runner == 'arrested' then
                        return ('Hit and run in a stolen car: %s arrested.'):format(c:name('runner'))
                            .. recorded(c, 'runner', c:who('runner').facts.found and { 'the screwdriver on him' } or nil)
                    end
                    return other_end(c, 'runner', out.runner, 'who drove the stolen car') or 'Hit and run in a stolen car: the driver was not found.'
                end)
            end,
        },

        -- ── He panicked, and came back. ────────────────────────────────────────────────────────────────────────
        back = {
            weight = 2,
            setup = function(c)
                local car, paint = CARS[math.random(#CARS)], PAINTS[math.random(#PAINTS)]
                local male = math.random() < .5
                local them, they = male and 'him' or 'her', male and 'he' or 'she'
                victim(c, male)
                witness(c, car, paint, {
                    c_saw = { { ("%s stepped out between those parked cars, right in front of it. The driver didn't stand a chance. He braked, but... then he just drove off. Panicked, I think.")
                        :format(male and 'He' or 'She'), set = { c_stepped = 'yes' } } },
                    c_driver = { "An older man. I saw his face as he went past. He looked terrified." },
                    c_way = { 'That way. Slowly. Like he was in shock.' },
                })
                c:person('driver', { at = 'driver', label = 'Man', male = true, home = 'driver', age = { 45, 70 }, secret = 'clean',
                    demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = DRIVER_Q, lines = {
                        c_where = { { 'I was driving home. I hit someone. That was me. I came back.', set = { c_admit = 'yes' } } },
                        c_damage = { ("I hit %s. %s just stepped out. I came back as soon as I could think straight."):format(them, they) },
                        c_hit = { { ("Yes. Yes, it was me. %s stepped out from between the cars and I couldn't stop. I panicked. I drove home and just sat there. Then I walked back. Is %s alive?")
                            :format(male and 'He' or 'She', they), set = { c_admit = 'yes' } } },
                        where = { "Back there. To the... I came back. I'm not going anywhere." },
                    } })
                car_of(c, car, paint, { owner = 'driver', locked = false })
                debris(c, car, paint)
                c:clue('car', { on = 'car', label = 'The car', hidden = true,
                    text = 'Front end dented, one headlight broken, the engine still ticking as it cools. Parked crooked, the keys still in the ignition.' })
                card(c, { car = 'Check the registered address', car_hint = 'Dispatch has it: marked on your map.',
                    driver = 'Talk to the driver', driver_hint = 'He came back to the scene.', who = 'driver' })
                wire(c, 'driver')
                match(c, car, paint, ' Marking the address on your map.')
                c:on('inspect', function(clue) if clue == 'car' then c:reveal('driver') end end)
                -- three or four minutes after the first unit's there, he walks back (unless he's been found first)
                local on_scene, at, met, walking, here = nil, math.random(180, 240), false, false, false
                c:on('arrive', function() on_scene = on_scene or 0 end)
                c:on('contact', function(who) if who == 'driver' then met = true end end)
                c:on('tick', function()
                    if on_scene then on_scene = on_scene + 1 end
                    if not walking and not met and on_scene and on_scene >= at then
                        walking = true
                        c:task('driver', 'go', 'witness')
                    end
                    if walking and not here and c:who('driver') and not c:apart('driver', 'witness') then
                        here = true
                        c:say('driver', ("Is %s alive? I didn't see %s. I swear I didn't see %s!"):format(they, them, them))
                        c:say('witness', "That's him. That's the driver.")
                        c:reveal('driver')
                    end
                end)
                resolve(c, 'driver', function(out)
                    local d = c:name('driver')
                    local stepped = c:who('witness').facts.c_stepped and ' The witness: the victim stepped out between parked cars.' or ''
                    if out.driver == 'arrested' then
                        return ('Hit and run: %s, the driver, %s and was arrested.'):format(d, here and 'came back to the scene' or walking and 'was stopped on his way back to the scene' or 'was found at home')
                            .. recorded(c, 'driver') .. stepped
                    end
                    local e = other_end(c, 'driver', out.driver, 'the driver')
                    return e and (e .. stepped) or 'Hit and run: the driver was not dealt with.'
                end)
            end,
        },
    },
})
