--[[
    c3r callout: TRAFFIC DISPUTE.

    Two drivers have stopped at the roadside, shouting. The report is the same every time, and the card is too: each driver,
    and their cars (three units can take one each). What's really going on is one of five stories (which driver's which is
    picked per call):
      fault    one cut the other off and got brake-checked: two egos and some paint
      weapon   one pulled a pistol or a bat on the other, and it's back in the car: the other only says so out of earshot
      claim    a crash for cash: the "victim" braked on purpose, for the third time this year
      drunk    one's drunk, and the other chased them down to stop them, with a bat on the seat
      stolen   one's driving the other's stolen car, and may run
    One car always has a dashcam, so the truth can always be found. Leave them shouting for 90 s and it comes to blows.
    It's dealt with when everyone arrested has been taken in and both drivers have been dealt with, or both have been heard
    and every unit has left.

    Points per location: walk them out in game with /c3rplace roadrage (it writes the location in below).
]]

local DRIVER_Q = {
    { id = 'c_what', label = 'What happened?', stress = true, press = true },
    { id = 'c_other', label = 'What did the other driver do?', stress = true, press = true },
    { id = 'c_weapon', label = 'Did anyone have a weapon?', stress = true, press = true },
    { id = 'c_whose', label = 'Whose car is this?', press = true },
}
local CALLED = { first = 'One of the drivers', second = 'One of the drivers' }
local SCRAP_AFTER, SCRAP_FOR = 90, 60 -- s on scene with nobody spoken to; s of it before one goes down

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
    c:objective('first', 'Talk to the first driver', { hint = 'Get them away from the other one. Follow me does it.', blip = 'first' })
    c:objective('second', 'Talk to the second driver', { hint = 'Get them away from the other one. Follow me does it.', blip = 'second' })
    c:objective('cars', 'Check the vehicles', { hint = 'Damage, and what can be seen inside.', blip = { 'first_car', 'second_car' } })
    c:objective('breakup', 'Break it up', { hidden = true, who = 'all', blip = { 'first', 'second' }, hint = 'Press E beside them, or the PA with your gun out. If they will not stop, the taser will.' })
    c:objective('gunman', 'Stop them', { hidden = true, who = 'all', blip = 'first', hint = 'Take cover. They give up if they have to.' })
    c:objective('medic', 'Call paramedics', { hidden = true, who = 'all', hint = 'Radio for an ambulance.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'first', 'second' }, who = 'all', blip = { 'first', 'second' } })
end

-- Done when: each driver's been asked what happened, or can't be; both cars have been looked at.
local function wire(c)
    local looked = {}
    c:on('act', function(who, action, arg)
        if action == 'ask' and arg == 'c_what' and (who == 'first' or who == 'second') then c:done(who) end
    end)
    c:on('inspect', function(clue)
        if clue ~= 'first_car' and clue ~= 'second_car' then return end
        looked[clue] = true
        if looked.first_car and looked.second_car then c:done('cars') end
    end)
    c:on('dead', function(who) if who == 'first' or who == 'second' then c:done(who) end end)
end

-- Someone's hurt: the ending waits for them, and the card says so.
local function hurt(c, key)
    local list = c:get('hurts') or {}
    list[key] = true
    c:set('hurts', list)
    c:reveal('medic')
    local blips = {}
    for who in pairs(list) do blips[#blips + 1] = who end
    c:blip('medic', blips)
end

-- Left shouting: `SCRAP_AFTER` s after a unit arrives, if nobody's spoken to either, they go for each other. An order stops
-- them half the time, the taser every time, and after `SCRAP_FOR` s one goes down.
local function scrap(c)
    local clock, running, spoken, fighting, ordered, stopped, left = 0, false, false, false, false, false, SCRAP_FOR
    local function stop(line)
        if stopped or not fighting then return end
        stopped, fighting = true, false
        c:done('breakup')
        c:task('first', 'surrender')
        c:task('second', 'surrender')
        if line then c:say('first', line) end
        c:note('The fight was broken up')
    end
    local function beaten(key)
        local h = c:health(key)
        return h and h > 100 and h < 120
    end
    c:on('arrive', function() running = true end)
    c:on('contact', function(who) if who == 'first' or who == 'second' then spoken = true end end)
    c:on('hail', function(who)
        if not fighting or ordered or (who ~= 'first' and who ~= 'second') then return end
        ordered = true
        if math.random() < .5 then stop("Alright! Alright! I'm done!")
        else c:say(who, "I'm not finished with this idiot!") end
    end)
    c:on('stunned', function(who)
        if fighting and (who == 'first' or who == 'second') then
            c:set('tased', true)
            stop("Okay! Okay! I'm done!")
        end
    end)
    c:on('dead', function(who)
        if who ~= 'first' and who ~= 'second' then return end
        stop()
        stopped = true -- (not one to fight now, even if it hadn't started)
    end)
    c:on('tick', function()
        local here = c:near('first', 120.0) or c:near('second', 120.0) -- (it goes on when someone's there to see it)
        if fighting then
            if here then left = left - 1 end
            local hit = beaten('first') and 'first' or beaten('second') and 'second'
            if left > 0 and not hit then return end
            hit = hit or 'second'
            stop()
            c:collapse(hit)
            c:patient(hit)
            hurt(c, hit)
            c:dispatch('One of them is down. Paramedics needed at the scene.')
            return
        end
        if not running or not here or spoken or stopped or c:get('drawn') ~= nil then return end -- (drawn: someone's been through that already)
        clock = clock + 1
        if clock < SCRAP_AFTER then return end
        fighting = true
        c:set('scrapped', true)
        c:reveal('breakup')
        c:task('first', 'brawl', 'second')
        c:task('second', 'brawl', 'first')
    end)
end

-- Armed, with a real weapon: they give up once hurt, half the time when told to, or after 45-120 s with units near.
-- -> start()
local function fight(c, key, gun)
    local fighting, left = false, 0
    local function give_up(line)
        fighting = false
        local o = c:who(key)
        o.ran, o.gave_up = true, true
        c:set('drawn', false)
        c:done('gunman')
        c:say(key, line)
        c:task(key, 'surrender')
    end
    local function start()
        fighting, left = true, math.random(45, 120)
        c:set('drawn', true)
        c:reveal('gunman')
        c:blip('gunman', key)
        c:note('The driver went for the weapon')
        c:task(key, 'shoot')
    end
    c:on('fired', function(who)
        if who ~= key or not gun then return end -- (not a bat)
        c:dispatch('Shots fired! All units, shots fired!')
    end)
    c:on('stunned', function(who)
        if who == key and fighting then
            c:set('tased', true)
            give_up("Okay! Okay! I'm done!")
        end
    end)
    c:on('tick', function()
        if not fighting then return end
        local health = c:health(key)
        left = c:near(key, 45.0) and left - 1 or left
        if health and health > 100 and health < 150 then give_up("Okay! Okay, I'm hurt! I'm done!")
        elseif left <= 0 then give_up("That's it! I'm done! It's down!") end
    end)
    c:on('hail', function(who)
        if who == key and fighting and math.random() < 0.5 then give_up("Alright! Alright! It's down!") end
    end)
    c:on('dead', function(who)
        if who ~= key then return end
        fighting = false
        c:set('drawn', false)
        c:done('gunman')
    end)
    return start
end

--[[ It's over when everyone arrested has been taken in, whoever's hurt has been seen to and both drivers have been dealt with;
     or both have been heard and every unit has left. ends(out) -> the MDT summary; out[first | second] = 'arrested' | 'released' |
     'cited' | 'warning' | 'fled' | 'dead' | 'pronounced' | 'hospital'; out.left = true. ]]
local function resolve(c, ends)
    local out, taken, away_for, done = {}, {}, 0, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local LET_GO = { released = true, cited = true, warning = true, fled = true, pronounced = true, hospital = true, treated = true, dead = true }
    local SEEN = { hospital = true, treated = true, pronounced = true, fled = true }
    local function dealt(who) return taken[who] or LET_GO[out[who]] end
    local function reached() -- (gone, arrested or down without a word: nothing left to ask them)
        for _, k in ipairs({ 'first', 'second' }) do if dealt(k) then c:done(k) end end
    end
    local function all_seen()
        for who in pairs(c:get('hurts') or {}) do
            if not (SEEN[out[who]] or taken[who]) then return false end
        end
        return true
    end
    local function check()
        reached()
        if done or waiting() then return end
        if not ((dealt('first') and dealt('second') and all_seen()) or out.left) then return end
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
        if all_seen() then c:done('medic') end
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if out[who] == 'dead' then seen_to(who, 'pronounced') end -- (the coroner's been)
        if (who == 'first' or who == 'second') and not LET_GO[out[who]] and not taken[who] then
            seen_to(who, (c:get('hurts') or {})[who] and 'hospital' or 'fled') -- (hurt: an ambulance the call didn't hear about)
        end
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if not CALLED[who] then return end
        hurt(c, who)
        c:dispatch(('%s is down. Paramedics needed at the scene.'):format(CALLED[who]))
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' then seen_to(who, 'pronounced')
        elseif what == 'hospital' or what == 'treated' then seen_to(who, what) end
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or SEEN[out[who]] and out[who] ~= 'fled' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
    end)
    c:on('tick', function() -- (either driver in either order: one place to look)
        check()
        local here = c:near(nil, 80.0) or c:near('first', 80.0) or c:near('second', 80.0) or c:talking()
        if c:is_done('first') and c:is_done('second') and not waiting() and not here then
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
    local s, how = c:name(who), out[who]
    if how == 'arrested' then return (' %s was arrested.'):format(s) end
    if how == 'cited' or how == 'warning' then return (' %s was given a %s.'):format(s, how == 'cited' and 'ticket' or 'warning') end
    if how == 'released' then return (' %s was spoken to and let go.'):format(s) end
    if how == 'fled' then return (' %s got away.'):format(s) end
    if how == 'hospital' then return (' %s was taken to hospital.'):format(s) end
    if how == 'treated' then return (' %s was seen by paramedics at the scene.'):format(s) end
    if how == 'dead' or how == 'pronounced' then return (' %s died at the scene.'):format(s) end
    return ''
end

-- What the summary says. `what`, then both drivers, then what came of it.
local function report(c, out, what)
    local text = what .. part(c, out, 'first') .. part(c, out, 'second')
    if c:get('tased') then text = text .. ' A taser was used.'
    elseif c:get('scrapped') then text = text .. ' It came to blows before officers stepped in.' end
    if c:get('dash_seen') then text = text .. ' Recorded: the dashcam.' end
    return text
end

local CARS = {
    { model = 'premier', make = 'Declasse', name = 'Premier', color = 'Silver', paint = 4 },
    { model = 'fugitive', make = 'Cheval', name = 'Fugitive', color = 'Black', paint = 0 },
    { model = 'stanier', make = 'Vapid', name = 'Stanier', color = 'White', paint = 111 },
    { model = 'tailgater', make = 'Obey', name = 'Tailgater', color = 'Dark blue', paint = 62 },
}

-- The two drivers and their cars. `bad` (which of first / second) is who the story's about; which is which is picked per
-- call. spec = { bad = { person }, good = { person }, bad_car = what it shows, good_car = what it shows, stolen? }
local function drivers(c, spec)
    local bad = math.random() < .5 and 'first' or 'second'
    local good = bad == 'first' and 'second' or 'first'
    c:set('bad', bad)
    c:set('good', good)
    local a = math.random(#CARS)
    local b = a % #CARS + 1
    for _, key in ipairs({ 'first', 'second' }) do
        local p = key == bad and spec.bad or spec.good
        local lines = p.lines
        lines.where = lines.where or { "I was going home. Before this." }
        c:person(key, { at = key, label = 'Driver', male = true, age = p.age or { 25, 55 }, secret = p.secret or 'nervous', demeanor = p.demeanor or 'rude',
            items = p.items or {}, weapon = p.weapon, scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = DRIVER_Q, lines = lines })
        local car = CARS[key == 'first' and a or b]
        local name = ('%s %s'):format(car.color, car.name)
        c:vehicle(key .. '_car', { at = key .. '_car', model = car.model, make = car.make, name = car.name, color = car.color, paint = car.paint, locked = false,
            damage = key == (spec.dent == 'bad' and bad or spec.dent == 'good' and good) and 'front' or nil,
            owner = not spec.stolen and key or key == bad and good or nil, -- (the stolen one's the other driver's; his own's a rental)
            stolen = spec.stolen and key == bad or nil, label = name })
        c:clue(key .. '_car', { on = key .. '_car', label = name, text = key == bad and spec.bad_car or spec.good_car })
    end
    c:on('inspect', function(clue)
        if clue == good .. '_car' then c:set('dash_seen', true) end
        if clue == bad .. '_car' then c:set('stash_seen', true) end
    end)
    return bad, good
end

-- A line only said out of the other one's earshot: `truth`, or `front` with them listening.
local function aside(c, front, truth)
    return function()
        return c:apart('first', 'second') and truth or front
    end
end

Callout({
    id = 'roadrage',
    name = 'Traffic dispute',
    voice = 'call_roadrage', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        'Passing driver reports two cars stopped at the roadside and the drivers shouting at each other.',
        'Caller says two drivers have pulled over and it looks like it is getting physical.',
        "Traffic dispute at the roadside. Caller didn't stop.",
    },
    -- The points each location needs, in the order /c3rplace roadrage walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it).
    points = {
        { 'first', 'The first driver, on foot at the roadside.' },
        { 'first_car', 'Their car, pulled over. Sit in a car parked there.', 'car' },
        { 'second', 'The second driver, 3 to 5 m from the first: they can reach each other.' },
        { 'second_car', 'Their car, pulled over close by. Sit in a car parked there.', 'car' },
    },
    -- Add more with /c3rplace roadrage in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Grove St', at = vector3(-61.79, -1842.18, 26.63), points = {
            first = vector4(-61.79, -1842.18, 26.63, 297.5),
            first_car = vector4(-62.54, -1840.41, 26.50, 142.0),
            second = vector4(-58.50, -1843.00, 26.60, 117.0),
            second_car = vector4(-57.00, -1846.50, 26.50, 142.0),
        } },
    },

    stories = {
        -- ── Two egos. ────────────────────────────────────────────────────────────────────────────────────────────
        fault = {
            weight = 3,
            setup = function(c)
                drivers(c, {
                    bad = { lines = {
                        c_what = { "He pulled out on me! No signal, nothing. So I got in front of him and showed him how it feels." },
                        c_other = { "He's a maniac. I braked, alright? I'm allowed to brake." },
                        c_weapon = { "What? No. It's not that serious." },
                        c_whose = { "Mine. Look at the state of it." },
                    } },
                    good = { lines = {
                        c_what = { "I changed lane, and he slammed his brakes on right in front of me. On purpose!" },
                        c_other = cracks(2, { "He's a lunatic. Ask anyone." },
                            { { "...Alright, I might have cut him off. I didn't see him. That's no reason to do that.", set = { c_admit = 'yes' } } },
                            { "I said. I didn't see him." }),
                        c_weapon = { "No. It's just shouting. So far." },
                        c_whose = { "Mine. I've had it ten years." },
                    } },
                    bad_car = 'A scrape along the side, with the other car\'s paint in it. Nothing inside worth noting.',
                    good_car = 'A dashcam on the windscreen. It shows this car pulling out with no signal, and the other one braking hard in front of it, twice. Neither comes out of it well.',
                })
                card(c)
                wire(c)
                scrap(c)
                resolve(c, function(out) return report(c, out, 'A roadside dispute: both drivers at fault.') end)
            end,
        },

        -- ── A weapon. ────────────────────────────────────────────────────────────────────────────────────────────
        weapon = {
            weight = 3,
            setup = function(c)
                local gun = math.random() < .5
                local item = gun and 'a black pistol' or 'a baseball bat'
                local bad = drivers(c, {
                    bad = { weapon = gun and 'WEAPON_PISTOL' or 'WEAPON_BAT', secret = 'warrant', demeanor = 'rude', lines = {
                        c_what = { "He's the one who started it. I got out to talk. That's all." },
                        c_other = cracks(3, { "He's lying. He's scared of his own shadow." },
                            { { "...I showed it to him, alright? Just so he'd back off. It went straight back in the car.", set = { c_admit = 'yes' } } },
                            { "I said. It went straight back." }),
                        c_weapon = { "What weapon? Me? Search me. Go on." },
                        c_whose = { "Mine. You don't need to look in it." },
                        weapons = { "Search me. Go on. You won't find anything on me." },
                    } },
                    good = { secret = 'clean', demeanor = 'nervous', lines = {
                        c_what = aside(c, { "It's nothing. A misunderstanding. I just want to go." },
                            { ("He had %s. I swear. He pointed it right at me, then he put it back in his car."):format(item) }),
                        c_other = aside(c, { "Ask him. I don't want any trouble." },
                            { { ("He had %s! He put it back in the car, I saw him!"):format(item), set = { c_told = 'yes' } } }),
                        c_weapon = aside(c, { "No. I don't know. Can I go?" },
                            { { ("Yes. He had %s. It's in his car."):format(item), set = { c_told = 'yes' } } }),
                        c_whose = { "Mine. Please can I go?" },
                    } },
                    bad_car = ("Down beside the driver's seat, not quite hidden: %s."):format(item),
                    good_car = ("A dashcam on the windscreen. It shows the other driver walk up to this car and raise %s at the window."):format(item),
                })
                card(c)
                wire(c)
                local start = fight(c, bad, gun)
                local reacted = false
                c:on('inspect', function(clue)
                    if clue ~= bad .. '_car' or reacted then return end
                    reacted = true
                    local o = c:who(bad)
                    if o and not o.cuffed and not c:talking(bad) and not c:get('scrapped') and not (c:get('hurts') or {})[bad]
                        and (c:health(bad) or 0) > 100 and math.random() < 0.15 then start() end
                end)
                scrap(c)
                resolve(c, function(out)
                    local text = report(c, out, 'A driver threatened another with a weapon.')
                    if out[bad] ~= 'arrested' then text = text .. (c:get('stash_seen') and ' The weapon was found.' or ' The weapon was never found.') end
                    return text
                end)
            end,
        },

        -- ── A crash for cash. ────────────────────────────────────────────────────────────────────────────────────
        claim = {
            weight = 2,
            setup = function(c)
                local bad = drivers(c, {
                    dent = 'good',
                    bad = { demeanor = 'polite', lines = {
                        c_what = { "He ran into the back of me at the lights. Straight in. My neck's killing me. I'll need his insurance details, officer." },
                        c_other = cracks(3, { "He wasn't looking. I have a witness, somewhere. It's a clear case." },
                            { { "...Okay. I braked. It's insurance. Nobody gets hurt.", set = { c_admit = 'yes' } } },
                            { "I told you. Nobody gets hurt." }),
                        c_weapon = { "Of course not. I'm the victim here." },
                        c_whose = { "Mine. It's had some bad luck this year." },
                    } },
                    good = { demeanor = 'nervous', lines = {
                        c_what = { "He just stopped. For no reason. There wasn't even a light. I couldn't stop in time." },
                        c_other = { "He was out of the car before I'd put the handbrake on. With his phone. He already had a form." },
                        c_weapon = { "No. No, nothing like that." },
                        c_whose = { "Mine. I've got a dashcam, if that helps. I don't know how they work." },
                    } },
                    bad_car = 'The rear bumper is scuffed, on top of older dents, and a claim form is on the seat, already filled in.',
                    good_car = 'A dashcam on the windscreen. It shows the car ahead braking hard on a clear road, with nothing in front of it.',
                })
                card(c)
                wire(c)
                local said = false
                c:on('act', function(who, action)
                    if who ~= bad or action ~= 'licence' or said then return end
                    said = true
                    local text = ('Dispatch: %s has made three rear-end insurance claims this year.'):format(c:name(bad))
                    c:dispatch(text)
                    c:note(text)
                end)
                scrap(c)
                resolve(c, function(out) return report(c, out, 'A staged crash for an insurance claim.') end)
            end,
        },

        -- ── A drunk, and whoever stopped them. ───────────────────────────────────────────────────────────────────
        drunk = {
            weight = 2,
            setup = function(c)
                drivers(c, {
                    dent = 'bad',
                    bad = { secret = 'drunk', demeanor = 'chatty', lines = {
                        why = { "Why? I was driving. Home. Slowly." },
                        drink = { "Two beers. It's fine. I was driving fine." },
                        howmuch = { "Two. Three. I'm a good driver." },
                        c_what = { "This guy ran me off the road! I was fine. I'm fine. Just going home. Nice and slow." },
                        c_other = { "He's crazy. He was behind me for miles, flashing his lights." },
                        c_weapon = { "He's got a bat! Look in his car! I saw it!" },
                        c_whose = { "Mine. Yours? No. Mine." },
                    } },
                    good = { secret = 'clean', demeanor = 'nervous', items = {}, lines = {
                        c_what = { "He was all over the road. I followed him for miles. There was a school crossing back there. So I got in front and stopped him." },
                        c_other = { "Smell him. Go on. I called it in. I couldn't just let him go on." },
                        c_weapon = cracks(2, { "No. I don't... no." },
                            { { "There's a bat on my seat. It's for work. I had it in my hand when I got out. I was scared.", set = { c_admit = 'yes' } } },
                            { "I told you. It's for work." }),
                        c_whose = { "Mine." },
                    } },
                    bad_car = 'Open cans in the footwell, and it smells like a bar. The front corner has fresh damage from something else entirely.',
                    good_car = 'A dashcam on the windscreen. It shows the other car weaving for miles, then this one overtaking and pulling across it. A baseball bat is on the passenger seat.',
                })
                card(c)
                wire(c)
                scrap(c)
                resolve(c, function(out) return report(c, out, 'A drunk driver, stopped by another driver.') end)
            end,
        },

        -- ── Their own stolen car. ────────────────────────────────────────────────────────────────────────────────
        stolen = {
            weight = 2,
            setup = function(c)
                local bad = drivers(c, {
                    stolen = true,
                    dent = 'good',
                    bad = { age = { 19, 32 }, secret = 'nervous', demeanor = 'rude', lines = {
                        c_what = { "He rammed me! He's crazy! I was just driving!" },
                        c_other = { "I don't know him. He's making it up." },
                        c_weapon = { "No. What? No." },
                        c_whose = cracks(2, { "Mine. It's mine. I've got the papers at home." },
                            { { "...A friend's. He lent it to me. Sort of.", set = { c_admit = 'yes' } } },
                            { "I told you. A friend's." }),
                    } },
                    good = { secret = 'clean', demeanor = 'rude', lines = {
                        c_what = { "That's my car! MY car! It went from outside my work on Tuesday, and there it is, with him driving it! So I went after it." },
                        c_other = { "Ask him what's in the glovebox. Go on. There's a photo of my kids in there." },
                        c_weapon = { "No. I didn't need one. I've got a bumper." },
                        c_whose = { "That one. I mean this one's the rental. That one's mine. Run the plate." },
                    } },
                    bad_car = 'The ignition is torn out and hot-wired. In the glovebox: a photo of two children.',
                    good_car = 'A rental, with a dashcam on the windscreen. It shows the car ahead spotted in traffic, followed and forced to the kerb.',
                })
                card(c)
                wire(c)
                local spoken, bolting = false, false
                c:on('contact', function(who)
                    if who ~= bad or spoken then return end
                    spoken = true
                    bolting = not c:who(bad).gave_up and math.random() < 0.4
                end)
                c:on('tick', function()
                    if not bolting then return end
                    bolting = false
                    if c:talking(bad) then c:task(bad, 'flee') end
                end)
                scrap(c)
                resolve(c, function(out) return report(c, out, "A stolen car, stopped by its owner.") end)
            end,
        },
    },
})
