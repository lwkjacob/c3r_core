--[[
    c3r callout: CARS SPEEDING.

    Loud engines and a crowd in the street: a street race. The report is the same every time, and the card is too: stop a racer,
    talk to someone from the crowd, check what they left behind (three units can take one each). When the first unit's close
    it all goes at once: the drivers floor it, each their own way, and the crowd scatters. One unit can only chase one car.
    What's really going on is one of four stories:
      weekend  ordinary street racing, and a driver who'll give up the others if pressed
      stolen   one of the cars is stolen, on its way out of the country
      crash    one of the cars has already hit a spectator, and that driver's running
      betting  the race is cover for an illegal book, and the organiser's walking off with the bag
    Whoever isn't caught gets clean away, and the report says who. It's dealt with when the racers and the organiser are
    dealt with or gone, the crowd's been heard and anyone hurt has been seen to, or the crowd's been heard and every unit left.

    Points per location: walk them out in game with /c3rplace racing (it writes the location in below).
]]

local WITNESS_Q = {
    { id = 'c_what', label = 'What was going on here?' },
    { id = 'c_saw', label = 'Who runs this?', stress = true, press = true },
    { id = 'c_cars', label = 'Which car should I be looking for?', stress = true },
}
local RACER_Q = {
    { id = 'c_race', label = 'Were you racing?', stress = true, press = true },
    { id = 'c_others', label = 'Who else was out there?', stress = true, press = true },
    { id = 'c_car', label = 'Whose car is this?', stress = true, press = true },
}
local BOSS_Q = {
    { id = 'c_race', label = 'Do you know anything about this race?', stress = true, press = true },
    { id = 'c_bag', label = "What's in the bag?", stress = true, press = true },
}
local CARS = {
    { model = 'jester', make = 'Dinka', name = 'Jester' },
    { model = 'comet2', make = 'Pfister', name = 'Comet' },
    { model = 'elegy2', make = 'Annis', name = 'Elegy' },
    { model = 'sultan', make = 'Karin', name = 'Sultan' },
    { model = 'feltzer2', make = 'Benefactor', name = 'Feltzer' },
    { model = 'rapidgt', make = 'Dewbauchee', name = 'Rapid GT' },
    { model = 'banshee', make = 'Bravado', name = 'Banshee' },
}
local PAINTS = { { 'Black', 0 }, { 'Red', 27 }, { 'Dark blue', 62 }, { 'White', 111 } }
local KEYS = { 'racer1', 'racer2', 'racer3' }
local CLOSE = 60.0 -- m from the line: it all goes
local AWAY = 400.0 -- m from every unit: got away

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
    c:objective('racer', 'Stop one of the racers', { blip = { 'car1', 'car2', 'car3' }, hint = 'Pick one. You cannot catch them all.' })
    c:objective('crowd', 'Talk to someone from the crowd', { blip = 'witness', hint = 'Someone will be slow to run.' })
    c:objective('line', 'Check what they left behind', { blip = 'line', hint = 'Where it all started.' })
    c:objective('boss', 'Find the organiser', { hidden = true, who = 'all', blip = 'boss', hint = 'Walking away, with a bag.' })
    c:objective('medic', 'Call paramedics', { hidden = true, who = 'all', blip = 'hurt', hint = 'Radio for an ambulance.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'crowd' }, who = 'all' })
end

-- Done when: a racer's been stopped (or none can be), someone's said what was going on, the line's been looked at. Reaching
-- a racer opens their car.
local function wire(c)
    c:on('act', function(who, action, arg)
        if who == 'witness' and action == 'ask' and arg == 'c_what' then c:done('crowd') end
    end)
    c:on('inspect', function(clue) if clue == 'line' then c:set('line_seen', true) c:done('line') end end)
    c:on('contact', function(who)
        for i, key in ipairs(KEYS) do
            if who == key then
                c:done('racer')
                c:reveal('stash' .. i)
            end
        end
    end)
    c:on('dead', function(who) if who == 'witness' then c:done('crowd') end end)
    c:on('gone', function(who) if who == 'witness' then c:done('crowd') end end)
    c:on('custody', function(who) if who == 'witness' then c:done('crowd') end end)
    c:on('build', function() c:set('built', true) end)
end

-- It all goes at once, the first unit that's close: every driver floors it, whichever way the road takes them, and keeps
-- going (a car that isn't there yet: as soon as it is). Stopped and let go of, they carry on. Whoever gets clear of every
-- unit is gone from the world.
local function scatter(c)
    local gone_off, told, clear = false, {}, {}
    c:on('tick', function()
        if not c:get('built') then return end
        if not gone_off and c:near(nil, CLOSE) then
            gone_off = true
            c:note('The race broke up as units arrived')
            for _, key in ipairs({ 'crowd1', 'crowd2' }) do
                if c:who(key) then c:task(key, 'flee') end
            end
            if c:who('boss') and c:get('boss_runs') then c:task('boss', 'wander') end
        end
        for i, key in ipairs(KEYS) do
            local o = c:who(key)
            if gone_off and o and not told[key] and not o.cuffed then
                if c:talking(key) then told[key] = true -- (reached: the stop has them)
                elseif c:task(key, 'drive', { car = 'car' .. i, fast = true }) ~= false then told[key], clear[key] = true, true end
            end
            if clear[key] and o and not c:talking(key) and not o.cuffed and not c:near(key, AWAY) and not c:get('dead_' .. key) then
                clear[key] = nil
                c:remove(key, 'car' .. i)
            end
        end
    end)
    c:on('contact_ended', function(who, outcome)
        for _, key in ipairs(KEYS) do
            if who == key and outcome == 'fled' then clear[key] = true end
            if who == key and outcome == 'cancelled' then told[key] = nil end -- (walked off from: back to running)
        end
    end)
    c:on('dead', function(who) c:set('dead_' .. who, true) end)
end

--[[ It's over when the crowd's been heard, nobody's waiting to be taken in, anyone hurt has been seen to, and every racer (and
     the organiser, once they're wanted) has been dealt with or got away; or the crowd's been heard and every unit has left.
     ends(out) -> the MDT summary; out[person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' | 'pronounced' |
     'hospital' | 'treated'; out.left = true. ]]
local function resolve(c, ends)
    local out, taken, away_for, done, down = {}, {}, 0, false, {}
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local LET_GO = { released = true, cited = true, warning = true, fled = true, pronounced = true, hospital = true, treated = true, dead = true }
    local function dealt(who) return not c:who(who) or taken[who] or LET_GO[out[who]] end
    local function all_racers()
        for _, key in ipairs(KEYS) do if not dealt(key) then return false end end
        return true
    end
    local function check()
        if done or not c:get('built') then return end -- (before the scene's made, nobody's there to be dealt with)
        if all_racers() then c:done('racer') end -- (nobody left to stop)
        if waiting() then return end
        local hurt = c:who('hurt')
        local seen = not hurt or taken.hurt or LET_GO[out.hurt]
        local boss = not c:get('boss_wanted') or dealt('boss')
        if not ((all_racers() and boss and seen and c:is_done('crowd')) or out.left) then return end
        done = true
        c:done('decide')
        c:finish(ends(out))
    end
    c:on('act', function(who, action)
        local o = c:who(who)
        if action == 'cuff' and o and o.cuffed then
            out[who] = 'arrested'
            c:custody(who)
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
        c:hide('custody:' .. who)
        down[who] = nil
        if not next(down) then c:done('medic') end
    end
    c:on('build', function() down.hurt = c:who('hurt') and true or nil end)
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if out[who] == 'dead' then seen_to(who, 'pronounced') end -- (the coroner's been)
        if not out[who] then seen_to(who, who == 'hurt' and 'hospital' or 'fled') end -- (away clean, or an ambulance the call didn't hear about)
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if who == 'hurt' or who == 'racer1' or who == 'racer2' or who == 'racer3' or who == 'boss' then
            down[who] = true
            local blips = {}
            for k in pairs(down) do blips[#blips + 1] = k end
            c:reveal('medic')
            c:blip('medic', blips)
            c:dispatch('Someone is down. Paramedics needed at the scene.')
        end
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' then seen_to(who, 'pronounced')
        elseif what == 'hospital' or what == 'treated' then seen_to(who, what) end
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or out[who] == 'pronounced' or out[who] == 'hospital' or out[who] == 'treated' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
    end)
    c:on('tick', function() -- (racers go in any order, and while the crowd's being talked to: one place to look)
        check()
        local here = c:near(nil, 80.0) or c:talking()
        for _, key in ipairs(KEYS) do here = here or (not dealt(key) and c:near(key, 100.0)) end
        here = here or (c:get('boss_wanted') and not dealt('boss') and c:near('boss', 100.0)) -- (going after them)
        if c:is_done('crowd') and not waiting() and not here then
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

local function part(c, out, who)
    if not c:who(who) then return '' end
    local s, how = c:name(who), out[who]
    if how == 'arrested' then return (' %s was arrested.'):format(s) end
    if how == 'cited' or how == 'warning' then return (' %s was given a %s.'):format(s, how == 'cited' and 'ticket' or 'warning') end
    if how == 'released' then return (' %s was spoken to and let go.'):format(s) end
    if how == 'hospital' then return (' %s was taken to hospital.'):format(s) end
    if how == 'treated' then return (' %s was seen by paramedics at the scene.'):format(s) end
    if how == 'dead' or how == 'pronounced' then return (' %s died at the scene.'):format(s) end
    return ''
end

-- The summary: what it was, who was caught, and who got away, named if a driver gave them up.
local function report(c, out, what)
    local text, away, named, told = what, 0, {}, false
    for _, key in ipairs(KEYS) do
        local o = c:who(key)
        if o then
            text = text .. part(c, out, key)
            if out[key] == 'fled' then
                away = away + 1
                if not o.facts.c_named then named[#named + 1] = ('%s, plate %s'):format(c:name(key), c:plate('car' .. key:sub(-1)) or '?') end
            end
            told = told or o.facts.c_named
        end
    end
    text = text .. part(c, out, 'boss')
    if c:get('line_seen') then text = text .. ' The start line was recorded.' end
    if away > 0 then
        text = text .. (' %d driver%s got away.'):format(away, away == 1 and '' or 's')
        if told and named[1] then text = text .. ' Identified by a driver: ' .. table.concat(named, '; ') .. '.' end
    end
    return text
end

-- The racers, 2 or 3 by what's placed: their cars, and what each one's car shows once they've been reached.
-- lines(i) -> their lines; opts = { stolen = i, stash = { [i] = text }, dent = i }
local function racers(c, lines, opts)
    opts = opts or {}
    local first, paint = math.random(#CARS), math.random(#PAINTS)
    for i, key in ipairs(KEYS) do
        local car, colour = CARS[(first + i - 2) % #CARS + 1], PAINTS[(paint + i - 2) % #PAINTS + 1]
        c:set('car' .. i, ('%s %s'):format(colour[1], car.name))
        local l = lines(i)
        l.where = l.where or { "Nowhere. Just out for a drive." }
        c:person(key, { at = 'car' .. i, label = 'Driver', male = true, age = { 19, 34 }, secret = 'nervous', demeanor = 'rude', runs = true, bail = 0.3, items = {},
            seated = 'car' .. i, questions = RACER_Q, lines = l })
        c:vehicle('car' .. i, { at = 'car' .. i, model = car.model, make = car.make, name = car.name, color = colour[1], paint = colour[2],
            owner = opts.stolen ~= i and key or nil, stolen = opts.stolen == i or nil, damage = opts.dent == i and 'front' or nil, locked = false, label = 'A racer' })
        c:clue('stash' .. i, { on = 'car' .. i, label = 'Their car', hidden = true,
            text = (opts.stash and opts.stash[i]) or 'Racing seats, a stripped interior and a roll cage. Tyres worn to the bars. Built for one thing.' })
    end
end

local function crowd(c, lines, line_text)
    lines.where = lines.where or { "I was just watching. I'm going home." }
    c:person('witness', { at = 'witness', label = 'Spectator', secret = 'clean', demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = WITNESS_Q, lines = lines })
    c:person('crowd1', { at = 'crowd1', label = 'Spectator', secret = 'clean', scene = 'WORLD_HUMAN_SMOKING' })
    c:person('crowd2', { at = 'crowd2', label = 'Spectator', secret = 'clean', scene = 'WORLD_HUMAN_DRINKING' })
    c:clue('line', { at = 'line', label = 'The start line', text = line_text })
end

local RACE_LINE = { "I was in the lead. Nobody catches me." }

Callout({
    id = 'racing',
    name = 'Cars speeding',
    voice = 'call_racing', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        'Caller reports loud engines and a crowd gathering in the street.',
        'Multiple cars speeding and a large group of people blocking the road.',
        'Noise complaint. Caller says cars have been tearing up and down for an hour.',
    },
    -- The points each location needs, in the order /c3rplace racing walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it): it all goes when one's within 60 m of it.
    -- Skip the optional ones with Z in /c3rplace: no third car and driver, no crowd, no organiser, or nobody hurt there.
    points = {
        { 'line', 'The start line, in the road.' },
        { 'car1', 'The first car, at the line, with room around it. Sit in a car parked there.', 'car' },
        { 'car2', 'The second car, at the line, a clear car width from the first. Sit in a car parked there.', 'car' },
        { 'car3', 'A third car, at the line, clear of the others. Sit in a car parked there.', 'car', optional = true },
        { 'witness', 'A spectator who will not get away: at the side of the road.' },
        { 'crowd1', 'A spectator who runs.', optional = true },
        { 'crowd2', 'Another spectator who runs.', optional = true },
        { 'boss', 'The organiser, in the crowd.', optional = true },
        { 'hurt', 'Someone hit: on the ground near the line.', optional = true },
    },
    -- Add more with /c3rplace racing in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Davis Ave', at = vector3(301.19, -1528.52, 29.25), streets = { run1 = 'Capital Blvd', run2 = 'Capital Blvd' }, points = {
            line = vector4(301.19, -1528.52, 29.25, 297.7),
            car1 = vector4(295.25, -1528.28, 28.93, 298.9),
            run1 = vector4(576.56, -1439.41, 29.30, 270.9),
            car2 = vector4(297.85, -1531.54, 28.86, 296.3),
            run2 = vector4(576.69, -1445.07, 29.19, 268.3),
            witness = vector4(308.22, -1541.35, 29.32, 20.9),
            crowd2 = vector4(310.54, -1539.89, 29.30, 10.5),
            boss = vector4(311.35, -1539.36, 29.29, 27.8),
            hurt = vector4(309.40, -1528.02, 29.20, 236.0),
        } },
    },

    stories = {
        -- ── Weekend racers. ──────────────────────────────────────────────────────────────────────────────────────
        weekend = {
            weight = 3,
            setup = function(c)
                crowd(c, {
                    c_what = { "Racing. Every Friday. I just come to watch." },
                    c_saw = { "Nobody runs it. Somebody posts a time, everybody turns up." },
                    c_cars = function() return { ("The %s's the fast one. He never loses."):format(c:get('car1') or 'first one') } end,
                }, 'Spray paint across the road, a start line and a lap count, and burnt rubber going off both ways. A phone left on the kerb shows tonight\'s meet time.')
                racers(c, function()
                    local pressed = 0
                    return {
                        c_race = cracks(2, { "Racing? I was driving home." },
                            { { "...Yeah. Alright. So what? It's the only thing I'm good at.", set = { c_admit = 'yes' } } },
                            { "I told you. I raced." }),
                        c_others = function(o)
                            if o.facts.c_named then return { "I said. It's on the chat." } end
                            pressed = pressed + 1
                            if pressed < 2 then return { "I don't know anyone." } end
                            return { { "...Fine. You'll get them anyway. It's all on the group chat.", set = { c_named = 'yes' } } }
                        end,
                        c_car = { "Mine. Every bolt." },
                    }
                end)
                card(c)
                wire(c)
                scatter(c)
                resolve(c, function(out) return report(c, out, 'A street race, broken up by officers.') end)
            end,
        },

        -- ── A stolen one. ────────────────────────────────────────────────────────────────────────────────────────
        stolen = {
            weight = 2,
            setup = function(c)
                local bad = math.random(1, 2)
                crowd(c, {
                    c_what = { "Racing. There's a guy here tonight I haven't seen before." },
                    c_saw = { "Nobody runs it. But nobody knew that one guy." },
                    c_cars = function() return { ("The %s. Nobody knows who he is, and he drives like it isn't his."):format(c:get('car' .. bad) or 'new one') } end,
                }, 'Spray paint across the road, a start line and burnt rubber. A shipping label on the kerb, for a container out of the docks.')
                racers(c, function(i)
                    if i ~= bad then
                        return {
                            c_race = cracks(2, { "I was driving home." },
                                { { "...Alright. It's only a race. Nobody got hurt.", set = { c_admit = 'yes' } } },
                                { "I told you." }),
                            c_others = { "Ask about the new guy. Nobody knows him." },
                            c_car = { "Mine." },
                        }
                    end
                    return {
                        c_race = { "Race? No. I had a delivery to make." },
                        c_others = { "I don't know any of these people." },
                        c_car = cracks(2, { "A friend's. He lent it to me." },
                            { { "...It's going in a container tonight. It's not mine. Alright?", set = { c_admit = 'yes' } } },
                            { "I told you. It isn't mine." }),
                    }
                end, { stolen = bad, stash = { [bad] = 'The ignition is torn out and hot-wired, and the VIN plate has been filed off. A shipping label is on the seat.' } })
                card(c)
                wire(c)
                scatter(c)
                resolve(c, function(out)
                    local key = 'racer' .. bad
                    local text = report(c, out, 'A street race, with a stolen car in it.')
                    if out[key] == 'fled' or not out[key] then text = text .. ' The stolen car was not recovered.' end
                    return text
                end)
            end,
        },

        -- ── A spectator's been hit. ──────────────────────────────────────────────────────────────────────────────
        crash = {
            weight = 2,
            needs = { 'hurt' },
            setup = function(c)
                local bad = math.random(1, 2)
                crowd(c, {
                    c_what = { "One of them lost it at the start and hit someone. Then they all just kept going." },
                    c_saw = { "Nobody runs it. Nobody's going to help them, either." },
                    c_cars = function() return { ("The %s. He hit them and drove off. The front's all smashed up."):format(c:get('car' .. bad) or 'one with the smashed front') } end,
                }, 'Skid marks, broken headlight glass and blood at the edge of the road. Someone was hit here.')
                c:person('hurt', { at = 'hurt', label = 'Injured person', secret = 'clean', injured = true })
                racers(c, function(i)
                    if i ~= bad then
                        return {
                            c_race = cracks(2, { "I was driving home." },
                                { { "...Yeah. It wasn't me that hit them. Check my car.", set = { c_admit = 'yes' } } },
                                { "I said. It wasn't me." }),
                            c_others = { "Ask him with the smashed front. Is that person okay?" },
                            c_car = { "Mine. Look at it. Not a mark." },
                        }
                    end
                    return {
                        c_race = cracks(3, { "I don't know what you're talking about." },
                            { { "...They stepped out. I swear they stepped out. I didn't stop. I couldn't stop.", set = { c_admit = 'yes' } } },
                            { "I told you. I couldn't stop." }),
                        c_others = { "I didn't see anything." },
                        c_car = { "Mine. I hit a post." },
                    }
                end, { dent = bad, stash = { [bad] = 'The front end is crushed, with a smear of blood on the bonnet and cloth caught in the grille.' } })
                card(c)
                wire(c)
                c:on('tick', function() if c:near('hurt', 40.0) then c:reveal('medic') end end)
                scatter(c)
                resolve(c, function(out)
                    return report(c, out, 'A street race in which a spectator was hit.') .. part(c, out, 'hurt')
                end)
            end,
        },

        -- ── A betting ring. ──────────────────────────────────────────────────────────────────────────────────────
        betting = {
            weight = 2,
            needs = { 'boss' },
            setup = function(c)
                c:set('boss_runs', true)
                crowd(c, {
                    c_what = { "Racing. Everyone bets. That's why they come." },
                    c_saw = cracks(2, { "Nobody. I don't know. I was just watching." },
                        { { "...The one with the bag. They walked off the moment you pulled up. All the money's in it.", set = { c_boss = 'yes', c_admit = 'yes' } } },
                        { "I told you. The one with the bag." }),
                    c_cars = { "Doesn't matter which. Find the bag." },
                }, 'Spray paint across the road, a start line, and betting slips blowing along the kerb. Odds on two cars, in the same hand.')
                racers(c, function()
                    return {
                        c_race = cracks(2, { "I was driving home." },
                            { { "...They pay me to race. That's it. I don't touch the money.", set = { c_admit = 'yes' } } },
                            { "I told you." }),
                        c_others = { "Ask whoever's holding the bag." },
                        c_car = { "Mine." },
                    }
                end)
                c:person('boss', { at = 'boss', label = 'Spectator', age = { 30, 55 }, secret = 'nervous', demeanor = 'polite', items = { '$11,400 in a sports bag', 'A book of betting slips' },
                    scene = 'WORLD_HUMAN_STAND_MOBILE', questions = BOSS_Q, lines = {
                        c_race = { "A race? How exciting. I'm just out for a walk." },
                        c_bag = cracks(3, { "Gym things." },
                            { { "...Everyone here's an adult. They can bet on what they like.", set = { c_admit = 'yes' } } },
                            { "I said what I said." }),
                        where = { "Home. If that's alright." },
                    } })
                card(c)
                wire(c)
                local function wanted()
                    c:set('boss_wanted', true)
                    c:reveal('boss')
                end
                c:on('fact', function(_, fact) if fact == 'c_boss' then wanted() end end)
                c:on('inspect', function(clue) if clue == 'line' then wanted() end end)
                c:on('contact', function(who) if who == 'boss' then wanted() c:done('boss') end end)
                scatter(c)
                resolve(c, function(out) return report(c, out, 'A street race run as cover for illegal betting.') end)
            end,
        },
    },
})
