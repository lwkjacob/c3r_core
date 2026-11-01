--[[
    c3r callout: ARMED ROBBERY.

    Someone with a gun has robbed a store. The report is the same every time, and the card is too: the clerk and the
    CCTV (two units can take one each). What's really going on is one of five stories:
      gunman    a man with a real pistol hit the clerk, took the till and is hiding nearby
      crew      the same, but a driver is waiting in a stolen car around the corner
      inside    he never left: he's in the back room
      replica   a desperate first-timer with a fake gun: the same scare, until a search shows what it is
      active    it's still happening: he has the gun on the clerk, and when units pull up he goes to the window and fires
    Anyone with a real gun may draw when a unit gets close, or bolt when spoken to. Hurt, or after a while with units
    still on him, he gives up. It's dealt with when everyone arrested has been taken in, the one it's about is dead, let
    go or gets away, or the clerk's been heard and every unit has left.

    Points per location: walk them out in game with /c3rplace armed (it writes the location in below).
]]

local CLERK_Q = {
    { id = 'c_what', label = 'What happened?' },
    { id = 'c_amount', label = 'How much did they take?' },
    { id = 'c_weapon', label = 'What kind of gun was it?' },
    { id = 'c_way', label = 'Where did they go?' },
    { id = 'c_car', label = 'Did you see a car?' },
    { id = 'c_look', label = 'What did they look like?' },
}
local FOUND_Q = { -- anyone found around the store
    { id = 'c_where', label = 'Where were you ten minutes ago?', stress = true },
    { id = 'c_store', label = 'Were you in the store just now?', stress = true, press = true },
    { id = 'c_proof', label = 'Can anyone back that up?', needs = { c_alibi = true } },
}
local CORNERED_Q = { -- found in the back of the store: no point asking if he's been in it
    { id = 'c_back', label = 'What are you doing back here?', stress = true, press = true },
    { id = 'c_money', label = 'Where is the money?', stress = true },
    { id = 'c_alone', label = 'Is anyone else back here?', stress = true },
}
local DRIVER_Q = {
    { id = 'c_wait', label = 'What are you doing here?', stress = true },
    { id = 'c_mate', label = 'Who are you waiting for?', stress = true, press = true },
    { id = 'c_stolen', label = 'Whose car is this?', needs = { c_ran = true }, stress = true, press = true },
}

local LOOK = 'a_m_y_skater_01' -- (the robber looks the same in every story: no telling which it is)
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
    c:objective('clerk', 'Talk to the clerk', { hint = 'They made the call.', blip = 'clerk' })
    c:objective('cctv', 'Check the CCTV', { hint = 'Behind the counter.', blip = 'cctv' })
    c:objective('search', 'Search the area they went', { hidden = true, blip = 'dropped',
        hint = 'He may still have the gun. Whoever you find: check before you cuff them.' })
    c:objective('car', 'Find the getaway car', { hidden = true, blip = 'car', hint = 'Round the corner, with someone at it.' })
    c:objective('back', 'Check the back room', { hidden = true, blip = 'suspect', hint = 'Nobody saw him leave.' })
    c:objective('gunman', 'Stop the gunman', { hidden = true, who = 'all', blip = 'suspect', hint = 'Take cover. He gives up if he has to.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'clerk' }, who = 'all' })
end

-- Done when: the clerk's said what happened, the CCTV's been looked at. A clerk who can't be asked any more (dead) is
-- done too, so the card can't stick. Where they went opens the search.
local function wire(c)
    local warned = false
    local function armed_warning()
        if warned then return end
        warned = true
        c:dispatch('All units: the suspect is armed with a handgun. Use caution.')
    end
    c:on('act', function(who, action, arg)
        if action ~= 'ask' then return end
        if who == 'clerk' and arg == 'c_what' then c:done('clerk') end
        if who == 'clerk' and arg == 'c_weapon' then armed_warning() end
    end)
    -- (no search where he never left: 'stays' in the story)
    local function search() if not c:get('stays') then c:reveal('search') end end
    c:on('fact', function(_, fact) if fact == 'c_way' then search() end end)
    c:on('inspect', function(clue)
        if clue == 'cctv' then c:set('cctv_seen', true) c:done('cctv') armed_warning() search() end
        if clue == 'dropped' then search() end
    end)
    c:on('contact', function(who)
        if who ~= 'suspect' then return end
        search()
        c:done('search')
        c:blip('decide', 'suspect') -- (not before: the map would give away where he is)
    end)
    c:on('dead', function(who) if who == 'clerk' then c:done('clerk') end end)
end

--[[ A real gun. On the first unit within `close` m: 15% he draws. If spoken to first: 35% he bolts (the stop's chase).
     Shooting, he gives up once he's hurt, half the time when told to (E beside him, or the PA with a gun on him), or
     after 45-120 s with units still near. from = a point to fire from. -> open_fire(from), surrender(line) ]]
local function dangerous(c, key, close)
    local reacted, spoken, bolting, fighting, left = false, false, false, false, 0
    local function surrender(line)
        fighting = false
        local o = c:who(key)
        o.ran, o.gave_up = true, true -- (he's done: going for the cuffs won't send him running now)
        c:done('gunman')
        c:blip('decide', key) -- (he's given up where he stands: the map shows where that is)
        c:say(key, line)
        c:task(key, 'surrender')
    end
    local function open_fire(from)
        fighting, left = true, math.random(45, 120)
        c:task(key, 'shoot', from)
    end
    c:on('fired', function(who) -- (his first real shot: until then, nobody knows)
        if who ~= key then return end
        c:reveal('gunman')
        c:dispatch('Shots fired! All units, shots fired!')
        c:note('Shots fired by the suspect')
    end)
    c:on('tick', function()
        local o = c:who(key)
        if not o or o.cuffed or c:get('dead_' .. key) then return end
        if bolting then -- (a moment after the stop's taken hold of him, or the stop's first order overrides it)
            bolting = false
            if c:talking() then c:task(key, 'flee') end
        end
        if not reacted and c:near(key, close or 18.0) and not c:talking() then
            reacted = true
            if not c:get('no_draw') and math.random() < 0.15 then open_fire() end
        end
        if not fighting then return end
        local health = c:health(key)
        left = c:near(key, 45.0) and left - 1 or left -- (his clock only runs with someone in pistol range)
        if health and health > 100 and health < 150 then surrender("Okay! Okay, I'm hit! I'm done! Don't shoot!")
        elseif left <= 0 then surrender("I'm out! That's it! I'm done, don't shoot! My hands are up!") end
    end)
    c:on('hail', function(who)
        if who == key and fighting and math.random() < 0.5 then surrender("Alright! Alright! I'm putting it down!") end
    end)
    c:on('contact', function(who)
        if who ~= key then return end
        reacted = true -- (spoken to first: he won't draw on them later)
        if spoken then return end
        spoken = true
        bolting = not c:get('no_draw') and math.random() < 0.35
    end)
    c:on('dead', function(who) if who == key then c:set('dead_' .. key, true) fighting = false c:done('gunman') end end)
    return open_fire, surrender
end

local CALLED = { suspect = 'the suspect', clerk = 'the clerk', driver = 'the driver' }

--[[ It's over when everyone arrested has been taken in, or the one it's about (culprit) has been let go, got away or been
     seen to, with nobody left to take in, or the clerk's been heard and every unit has left. Anyone shot is a casualty:
     the card says to call paramedics, and it goes on until they've pronounced them or taken them, or the coroner has
     (out = 'dead' until then). ends(out) -> the MDT summary; out = { [person] = 'arrested' | 'released' | 'cited' |
     'warning' | 'fled' | 'dead' | 'pronounced' | 'hospital', left = true }. ]]
local function resolve(c, culprit, ends)
    local out, taken, away_for, done, medic = {}, {}, 0, false, {}
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function let_go(v) return v == 'released' or v == 'cited' or v == 'warning' or v == 'fled' or v == 'pronounced' or v == 'hospital' end
    local function check()
        if done or waiting() then return end
        if not (next(taken) or (culprit and let_go(out[culprit])) or out.left) then return end
        done = true
        c:done('decide')
        local text, also, more = ends(out), {}, {}
        for k, v in pairs(out) do
            if k ~= 'left' and not text:find(c:name(k), 1, true) then
                if v == 'arrested' then also[#also + 1] = c:name(k)
                elseif v == 'hospital' then more[#more + 1] = (' %s was taken to hospital.'):format(c:name(k))
                elseif v == 'dead' or v == 'pronounced' then -- (CPR can have brought them back)
                    if (c:health(k) or 0) <= 100 then more[#more + 1] = (' %s died at the scene.'):format(c:name(k)) end
                elseif v == 'cited' then more[#more + 1] = (' %s was given a ticket.'):format(c:name(k))
                elseif v == 'warning' then more[#more + 1] = (' %s was given a warning.'):format(c:name(k)) end
            end
        end
        table.sort(also)
        table.sort(more)
        c:finish(text .. (also[1] and (' Also arrested: ' .. table.concat(also, ', ') .. '.') or '') .. table.concat(more))
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
        check()
    end)
    c:on('custody', function(who) taken[who] = true check() end)
    local function seen_to(who, how)
        out[who] = how
        c:done('medic:' .. who)
        check()
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true check() end
        if out[who] == 'dead' then seen_to(who, 'pronounced') end -- (the coroner's been)
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if who == culprit then -- (it's plain what happened: nothing left to work out, only seeing to him)
            for _, id in ipairs({ 'clerk', 'cctv', 'search', 'car', 'back', 'gunman', 'decide' }) do c:done(id) end
        end
        if medic[who] then return end
        medic[who] = true
        c:objective('medic:' .. who, ('Call paramedics for %s'):format(CALLED[who] or who), { who = 'all', blip = who,
            hint = 'Radio for an ambulance. If they pronounce them, the coroner can take them.' })
        c:dispatch(('%s is down. Paramedics needed at the scene.'):format(CALLED[who] or who))
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' then seen_to(who, 'pronounced')
        elseif what == 'hospital' or what == 'treated' then seen_to(who, 'hospital') end
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or out[who] == 'pronounced' or out[who] == 'hospital' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        check() -- (walked off from them, 'cancelled': nothing decided)
    end)
    c:on('tick', function()
        local here = c:near(nil, 80.0) or c:near('suspect', 80.0) or c:near('driver', 80.0) or c:talking()
        if c:is_done('clerk') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then out.left = true check() end
        else
            away_for = 0
        end
    end)
end

local function clerk(c, lines)
    lines.where = lines.where or { "Here. Behind this counter. All night." }
    c:person('clerk', { at = 'clerk', label = 'Clerk', male = true, model = 'mp_m_shopkeep_01', secret = 'clean', demeanor = 'nervous',
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = CLERK_Q, lines = lines })
end

-- The robber: `at` is where he is, the items what a search finds.
local function robber(c, at, secret, items, lines, weapon, age, questions)
    lines.where = lines.where or { "Nowhere. Just hanging around." }
    c:person('suspect', { at = at, label = 'Man', male = true, model = LOOK, age = age or { 22, 34 }, secret = secret, demeanor = 'nervous',
        scene = 'WORLD_HUMAN_SMOKING', questions = questions or FOUND_Q, items = items, weapon = weapon, lines = lines })
end

local function denial(admit)
    return cracks(3, { "What store? I don't even go in there.", "No. Why would I be in a store?" },
        { { admit, set = { c_admit = 'yes' } } }, { "I told you. I'm not saying it again." })
end

local function on_record(c, parts)
    local o, list = c:who('suspect'), {}
    if o and o.facts.found then list[#list + 1] = parts.found end
    if o and o.facts.c_admit then list[#list + 1] = 'his admission' end
    if c:get('cctv_seen') then list[#list + 1] = 'the CCTV' end
    return list[1] and (' Recorded: ' .. table.concat(list, ', ') .. '.') or ''
end

-- What the summary says about the robber, whichever story it was.
local function robbed(c, out, what, parts)
    local s = c:name('suspect')
    local how = out.suspect
    if how == 'arrested' then return ('%s: %s arrested.'):format(what, s) .. on_record(c, parts) end
    if how == 'dead' or how == 'pronounced' then return ('%s: the suspect, %s, was shot and died at the scene.'):format(what, s) .. on_record(c, parts) end
    if how == 'hospital' then return ('%s: the suspect, %s, was shot and taken to hospital.'):format(what, s) .. on_record(c, parts) end
    if how == 'fled' then return ('%s: the suspect, %s, ran and got away.'):format(what, s) end
    if how == 'cited' or how == 'warning' then
        return ('%s: %s was given a %s and let go.'):format(what, s, how == 'cited' and 'ticket' or 'warning')
    end
    if how then return ('%s: %s was spoken to and let go.'):format(what, s) end
    return ('%s: the suspect was not arrested.'):format(what)
end

Callout({
    id = 'armed',
    name = 'Armed robbery',
    voice = 'call_armed', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    weight = 1,
    enabled = true,
    reports = {
        'Clerk reports an armed robbery. Caller says the suspect had a gun.',
        'Armed robbery at a store. Suspect location unknown.',
        'Panic alarm at a store. Caller says a man with a gun took the till.',
    },
    -- The points each location needs, in the order /c3rplace armed walks you through them. The first is where the call
    -- is (units are on scene within Config.Callouts.arrive m of it).
    -- Only the clerk has to be placed. Skip the rest with Z in /c3rplace: anyone not placed isn't there, and each story
    -- plays only where its `needs` were placed (no window, no shootout).
    points = {
        { 'clerk', 'The clerk, behind the counter.' },
        { 'holdup', 'In front of the counter, facing the clerk: where a robber stands holding them up.', optional = true },
        { 'window', 'Inside, at a front window or the doorway, facing out: where he fires from.', optional = true },
        { 'backroom', 'Inside, out of sight: the stockroom or the back of the store.', optional = true },
        { 'cctv', 'The CCTV screen behind the counter: what the officer looks at.', optional = true },
        { 'dropped', 'Something dropped on the way: on the ground between the store and where he hides.', optional = true },
        { 'suspect', 'Where he hides: an alley or behind a building, a street or two away.', optional = true },
        { 'car', 'A getaway car, round the corner from the store. Sit in a car parked there.', 'car', optional = true },
        { 'driver', 'The getaway driver, on foot beside that car.', optional = true },
    },
    -- Add more with /c3rplace armed in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Davis Ave', at = vector3(-47.19, -1758.55, 29.42), points = {
            clerk = vector4(-47.19, -1758.55, 29.42, 28.4),
            holdup = vector4(-48.52, -1757.61, 29.42, 233.5),
            window = vector4(-50.97, -1756.65, 29.42, 105.5),
            backroom = vector4(-41.55, -1749.17, 29.42, 158.8),
            cctv = vector4(-45.50, -1757.04, 29.42, 264.3),
            dropped = vector4(-44.70, -1761.29, 29.47, 306.4),
            suspect = vector4(-12.51, -1777.60, 28.64, 257.8),
            car = vector4(-14.39, -1788.43, 27.43, 140.3),
            driver = vector4(-13.73, -1790.12, 27.89, 155.8),
        } },
        { street = 'Palomino Ave', at = vector3(-706.07, -914.56, 19.22), streets = { dropped = 'Ginger St', suspect = 'Ginger St' }, points = {
            clerk = vector4(-706.07, -914.56, 19.22, 89.5),
            holdup = vector4(-707.41, -914.72, 19.22, 277.4),
            window = vector4(-710.37, -915.20, 19.22, 147.6),
            backroom = vector4(-708.64, -907.31, 19.22, 39.4),
            cctv = vector4(-705.75, -912.14, 19.22, 273.7),
            dropped = vector4(-729.06, -905.31, 20.08, 265.9),
            suspect = vector4(-717.47, -887.44, 23.79, 11.8),
            car = vector4(-703.41, -871.71, 23.03, 267.6),
            driver = vector4(-703.76, -869.85, 23.49, 29.3),
        } },
        { street = 'West Mirror Drive', at = vector3(1164.93, -323.68, 69.21), streets = { backroom = 'Mirror Park Blvd', cctv = 'Mirror Park Blvd' }, points = {
            clerk = vector4(1164.93, -323.68, 69.21, 75.1),
            holdup = vector4(1161.75, -324.09, 69.21, 266.5),
            window = vector4(1160.75, -325.22, 69.21, 156.5),
            backroom = vector4(1159.65, -316.67, 69.21, 293.6),
            cctv = vector4(1164.75, -320.84, 69.21, 242.1),
            dropped = vector4(1150.24, -330.75, 68.87, 62.3),
            suspect = vector4(1131.69, -317.71, 67.09, 102.7),
            car = vector4(1108.25, -330.02, 66.61, 209.2),
            driver = vector4(1109.79, -329.10, 67.08, 223.7),
        } },
        { street = 'Niland Ave', at = vector3(1959.26, 3741.31, 32.34), streets = { holdup = 'Alhambra Dr', window = 'Alhambra Dr', backroom = 'Alhambra Dr', dropped = 'Alhambra Dr', suspect = 'Zancudo Ave', car = 'Alhambra Dr', driver = 'Alhambra Dr' }, points = {
            clerk = vector4(1959.26, 3741.31, 32.34, 288.9),
            holdup = vector4(1961.53, 3741.93, 32.34, 89.5),
            window = vector4(1967.18, 3743.02, 32.34, 220.5),
            backroom = vector4(1963.11, 3748.55, 32.36, 51.0),
            cctv = vector4(1958.62, 3742.27, 32.34, 119.2),
            dropped = vector4(1978.85, 3745.79, 32.17, 9.8),
            suspect = vector4(1986.90, 3786.02, 32.27, 55.0),
            car = vector4(2009.48, 3773.46, 31.68, 296.8),
            driver = vector4(2008.06, 3774.45, 32.18, 318.3),
        } },
    },

    stories = {
        -- ── A real gun, and he's hiding nearby. ──────────────────────────────────────────────────────────────────
        gunman = {
            weight = 3,
            needs = { 'suspect' },
            setup = function(c)
                clerk(c, {
                    c_what = { "He waited till it was empty, then put a gun in my face. I went too slow, so he hit me with it. Look at my head." },
                    c_amount = { 'Everything in the till. Five hundred and sixty, about. Still in the bank bands.' },
                    c_weapon = { 'A pistol. Black. A real one, I felt it. He had it the whole time.' },
                    c_way = { { 'Out the door and off that way. Running.', set = { c_way = 'pointed' } } },
                    c_car = { "No. He was on foot, as far as I saw." },
                    c_look = { 'Skinny. Hood up, and a bandana over his face. All I saw were his eyes.' },
                })
                robber(c, 'suspect', math.random() < .5 and 'warrant' or 'drugs',
                    { '$560 in cash, still in bank bands', 'Pistol, loaded, black' }, {
                        c_where = { { "Around. Just walking. Is that illegal?", set = { c_alibi = 'none' } },
                                    { "Here. I've been here all night.", set = { c_alibi = 'here' } } },
                        c_store = denial("...Alright. I needed the money. I never meant to hit him."),
                        c_proof = { "Back it up? No. I was on my own." },
                    }, PISTOL)
                c:clue('cctv', { at = 'cctv', label = 'CCTV',
                    text = 'A few minutes before the call: a skinny man, hood up and a bandana over his face, waits for the store to empty, pulls a black pistol and strikes the clerk across the head. He takes the till and runs out.' })
                c:clue('dropped', { at = 'dropped', label = 'Something dropped', prop = 'prop_cs_bandana',
                    text = 'A dark bandana on the ground, dropped in a hurry. Like the one in the description.' })
                card(c)
                wire(c)
                dangerous(c, 'suspect')
                resolve(c, 'suspect', function(out)
                    return robbed(c, out, 'Armed robbery', { found = 'the cash and the pistol' })
                end)
            end,
        },

        -- ── Two of them: a driver is waiting in a stolen car. ────────────────────────────────────────────────────
        crew = {
            weight = 3,
            needs = { 'suspect', 'car', 'driver' },
            setup = function(c)
                clerk(c, {
                    c_what = { "One guy, with a gun. He kept looking at the door like he had to be somewhere. Hit me when I dropped the bag." },
                    c_amount = { 'Seven hundred and twenty. The till and the box under it.' },
                    c_weapon = { 'A pistol. Black. I am not an expert. It was very close.' },
                    c_way = { { 'Out the door, round the corner. Not running, walking fast. Like he knew where he was going.', set = { c_way = 'pointed' } } },
                    c_car = function()
                        local plate = c:plate('car') or ''
                        return { { ("A Declasse Asea, silver. It sat out there twenty minutes before he came in, then went round the corner. I got the end of the plate: %s."):format(plate:sub(-3)), set = { c_car = 'seen' } } }
                    end,
                    c_look = { 'Thin. Hood up, something over his face.' },
                })
                c:vehicle('car', { at = 'car', model = 'asea', make = 'Declasse', name = 'Asea', color = 'Silver', paint = 4,
                    stolen = true, locked = false, label = 'Getaway car' })
                robber(c, 'suspect', 'warrant', { '$720 in cash, in a bag', 'Pistol, loaded, black' }, {
                    c_where = { { "Around. Why?", set = { c_alibi = 'none' } } },
                    c_store = denial("...Yeah. It was his idea. He said it'd be easy."),
                    c_proof = { "No." },
                }, PISTOL)
                c:person('driver', { at = 'driver', label = 'Man', male = true, secret = 'nervous', demeanor = 'nervous', age = { 19, 27 },
                    scene = 'WORLD_HUMAN_SMOKING', questions = DRIVER_Q, items = {}, pockets = { 'Car keys on a bare ring: no fob' }, lines = {
                        c_wait = { { "Just waiting. For a friend. Is that a crime?", set = { c_ran = 'yes' } } },
                        c_mate = cracks(2, { "A friend. He'll be back in a minute. Why?" },
                            { { "...I only drive. Okay? I only drive. I didn't know he was bringing a gun.", set = { c_admit = 'yes' } } },
                            { "I told you. I only drive." }),
                        c_stolen = { "A mate's. I just borrowed it. Why, what's he said?" },
                        where = { "Nowhere. Just here." },
                    } })
                c:clue('cctv', { at = 'cctv', label = 'CCTV',
                    text = 'A few minutes before the call: a thin man, hood up and his face covered, points a black pistol at the clerk, strikes him and fills a bag. Twice he looks out at the street, like someone is waiting for him.' })
                c:clue('dropped', { at = 'dropped', label = 'Something dropped', prop = 'prop_cs_bandana',
                    text = 'A dark bandana on the ground, dropped in a hurry. Like the one in the description.' })
                card(c)
                wire(c)
                c:on('fact', function(_, fact) if fact == 'c_car' then c:reveal('car') end end)
                c:on('inspect', function(clue) if clue == 'cctv' then c:reveal('car') end end)
                c:on('contact', function(who) if who == 'driver' then c:set('car_found', true) c:reveal('car') c:done('car') end end)
                dangerous(c, 'suspect')
                resolve(c, 'suspect', function(out)
                    local text = robbed(c, out, 'Armed robbery', { found = 'the cash and the pistol' })
                    if out.driver == 'arrested' then return text .. (' The getaway driver, %s, was arrested.'):format(c:name('driver')) end
                    if not c:get('car_found') then return text .. ' The getaway car was not found.' end
                    return text
                end)
            end,
        },

        -- ── He never left. ───────────────────────────────────────────────────────────────────────────────────────
        inside = {
            weight = 2,
            needs = { 'backroom' },
            setup = function(c)
                c:set('stays', true)
                c:set('no_draw', true) -- (his own standoff, below)
                clerk(c, {
                    c_what = { "He had a gun on me. He took the money and said if I moved he'd come back. I don't know where he went. I had my eyes shut." },
                    c_amount = { 'Four hundred and something. I do not care about the money.' },
                    c_weapon = { 'A pistol. Black. I did not look at it for long.' },
                    c_way = { { "I told you, I had my eyes shut. I heard him go past me, towards the back. I never heard the door.", set = { c_nobody = 'yes' } } },
                    c_car = { "No. Nothing's pulled up or left." },
                    c_look = { 'Hood up. His face was covered.' },
                })
                robber(c, 'backroom', 'warrant', { '$430 in cash, still in bank bands', 'Pistol, loaded, black' }, {
                    c_back = cracks(2, { "I got lost. What do you want me to say?", "Nothing. Waiting." },
                        { { "There's no back door. I thought you'd all go and look outside. It nearly worked.", set = { c_admit = 'yes' } } },
                        { "I told you. There's no back door. That's it." }),
                    c_money = { "Jacket. Four hundred and thirty. Wasn't even worth it." },
                    c_alone = { "It's just me. Nobody's coming." },
                    where = { "Nowhere, obviously." },
                }, PISTOL, nil, CORNERED_Q)
                c:clue('cctv', { at = 'cctv', label = 'CCTV',
                    text = 'A man, hood up and his face covered, holds a black pistol on the clerk and empties the till. Then he walks past the counter, towards the back of the store. He does not come back.' })
                c:clue('dropped', { at = 'dropped', label = 'Something dropped', prop = 'ng_proc_sodacan_01a',
                    text = 'An empty soda can, flattened, been there a while. Litter.' })
                card(c)
                wire(c)
                local function back() c:reveal('back') end
                c:on('fact', function(_, fact) if fact == 'c_nobody' then back() end end)
                c:on('inspect', function(clue) if clue == 'cctv' then back() end end)
                c:on('contact', function(who) if who == 'suspect' then back() c:done('back') end end)
                local open_fire, give_up = dangerous(c, 'suspect')
                -- He waits back there with the gun out. Cornered (a gun on him, told to drop it, or someone on top of
                -- him), it's one or the other, once.
                local settled = false
                local function cornered()
                    if settled then return end
                    settled = true
                    back()
                    c:done('back')
                    if math.random() < 0.35 then open_fire() else give_up("Okay! Okay, I'm putting it down! Don't shoot!") end
                end
                c:on('build', function() c:task('suspect', 'hold') end)
                c:on('aimed', function(who) if who == 'suspect' then cornered() end end)
                c:on('hail', function(who) if who == 'suspect' then cornered() end end)
                c:on('tick', function() if not settled and c:near('suspect', 4.0) then cornered() end end)
                resolve(c, 'suspect', function(out)
                    return robbed(c, out, 'Armed robbery', { found = 'the cash and the pistol' })
                end)
            end,
        },

        -- ── The gun's a fake. ────────────────────────────────────────────────────────────────────────────────────
        replica = {
            weight = 2,
            needs = { 'suspect' },
            setup = function(c)
                c:set('no_draw', true)
                clerk(c, {
                    c_what = { "He pointed a gun at me and his hand was shaking. He said sorry. He actually said sorry. Then he took the till." },
                    c_amount = { 'Two hundred and ninety. It was a quiet night.' },
                    c_weapon = { "A pistol, I think. Black. It looked a bit... light? I wasn't going to find out." },
                    c_way = { { 'That way. Running. Not very fast.', set = { c_way = 'pointed' } } },
                    c_car = { "No. He was on foot." },
                    c_look = { 'Hood up, a scarf over his face. Not young. Older than you would think.' },
                })
                robber(c, 'suspect', 'nervous', { '$290 in cash, still in bank bands', 'Replica pistol: plastic, the orange tip painted black' }, {
                    c_where = { { "Walking. I needed some air.", set = { c_alibi = 'none' } } },
                    c_store = cracks(2, { "Please. I... no. No." },
                        { { "It isn't real. The gun. It's plastic. I lost my job and the rent's due. I'm so sorry.", set = { c_admit = 'yes' } } },
                        { "I've told you. It isn't real. I'm sorry." }),
                    c_proof = { "No. There's nobody." },
                }, nil, { 36, 45 })
                c:clue('cctv', { at = 'cctv', label = 'CCTV',
                    text = 'A man with a scarf over his face points a black pistol at the clerk. His hand is shaking. The clerk fills a bag; the man says something and leaves. Hard to tell from the footage, but the gun does not look heavy.' })
                c:clue('dropped', { at = 'dropped', label = 'Something dropped', prop = 'prop_cs_bandana',
                    text = 'A dark scarf on the ground, dropped in a hurry. Like the one in the description.' })
                card(c)
                wire(c)
                dangerous(c, 'suspect')
                resolve(c, 'suspect', function(out)
                    return robbed(c, out, 'Robbery with an imitation firearm', { found = 'the cash and the replica' })
                end)
            end,
        },

        -- ── It's still going on, and he's not giving up the store. ───────────────────────────────────────────────
        active = {
            weight = 2,
            needs = { 'holdup', 'window' },
            setup = function(c)
                c:set('no_draw', true) -- (he doesn't need telling: he opens fire when units pull up)
                c:set('stays', true)
                clerk(c, {
                    c_what = { "He had the gun on me the whole time. Then he saw your lights and went for the window. I got down and stayed down." },
                    c_amount = { "He didn't even get the till open. Don't worry about the money." },
                    c_weapon = { 'A pistol. You heard it. Everyone heard it.' },
                    c_way = { "He didn't go anywhere. That's the problem." },
                    c_car = { "No. Just him." },
                    c_look = { 'Hood up. Something over his face.' },
                })
                robber(c, 'holdup', 'warrant', { 'Pistol, black, nearly empty', '$35 in his own wallet' }, {
                    c_where = { { "You know where I was.", set = { c_alibi = 'none' } } },
                    c_store = denial("...Yeah. Obviously. You watched me."),
                    c_proof = { "No." },
                }, PISTOL)
                c:clue('cctv', { at = 'cctv', label = 'CCTV',
                    text = 'A man, hood up and his face covered, holds a black pistol on the clerk for several minutes. When patrol lights show in the window he runs to the front and opens fire.' })
                c:clue('dropped', { at = 'dropped', label = 'Something dropped', prop = 'ng_proc_sodacan_01a',
                    text = 'An empty soda can, flattened, been there a while. Litter.' })
                card(c)
                wire(c)
                local open_fire = dangerous(c, 'suspect')
                local started = false
                c:on('build', function()
                    c:task('suspect', 'aim', 'clerk')
                    c:task('clerk', 'surrender')
                end)
                c:on('tick', function()
                    if started or not c:near('suspect', 40.0) then return end -- (a pistol's range: he can reach them)
                    started = true
                    open_fire('window')
                    c:task('clerk', 'scene') -- (he's got someone else to worry about)
                end)
                resolve(c, 'suspect', function(out)
                    return robbed(c, out, 'Armed robbery in progress', { found = 'the pistol' })
                end)
            end,
        },
    },
})
