--[[
    c3r callout: STALKING.

    A woman has stopped somewhere public and called it in: the same man has turned up everywhere she's been today. The
    report is the same every time, and the card is too: talk to her, check her car, find him (three units can take one
    each). What's really going on is one of five stories:
      ex         her ex can't let it go: a note on her car, and a protective order that comes up when he's ID'd
      stranger   she's never seen him before: a tracker on her car and a notebook of her day; he may have a knife
      home       he left when she called: the note on her car says where he's gone, and he's waiting at her house
      hired      he's a licensed private investigator on her divorce: no crime, and someone has to explain it to her
      reversal   she's the one doing the following: the order is against her, and the tracker is on his car
    He keeps moving: a unit gets close and he drives off to the next spot, unless they've reached him first. He can be
    pulled over on the way. It's dealt with when everyone arrested has been taken in, the one it's about is dead, let go
    or gets away, or she's been heard and every unit has left.

    Points per location: walk them out in game with /c3rplace stalking (it writes the location in below).
]]

local CALLER_Q = {
    { id = 'c_what', label = "What's been going on?" },
    { id = 'c_where', label = 'Where has he followed you today?' },
    { id = 'c_know', label = 'Do you know him?', stress = true },
    { id = 'c_car', label = "What's he driving?" },
    { id = 'c_now', label = 'Where is he now?' },
    { id = 'c_photo', label = 'Did you get a picture of him?' },
    { id = 'c_note', label = 'Who wrote that note on your car?', needs = { c_note = true }, stress = true },
    { id = 'c_tracker', label = 'Who has had access to your car?', needs = { c_tracker = true } },
    { id = 'c_home', label = 'Is that your address on the note?', needs = { c_addr = true }, stress = true },
    { id = 'c_print', label = 'What are these printouts in your car?', needs = { c_print = true }, stress = true, press = true },
    { id = 'c_order', label = 'There is an order on file against you.', needs = { c_order = true }, stress = true, press = true },
    { id = 'c_told', label = 'He is a private investigator. Your husband hired him.', needs = { c_pi = true }, stress = true },
}
local HIM_Q = {
    { id = 'c_here', label = 'What are you doing here?', stress = true },
    { id = 'c_her', label = 'Do you know the woman who called us?', stress = true, press = true },
    { id = 'c_day', label = 'Where have you been today?', stress = true, press = true },
    { id = 'c_left', label = 'Why did you drive off when you saw us?', needs = { c_moved = true }, stress = true, press = true },
    { id = 'c_job', label = 'Who are you working for?', needs = { c_work = true } },
}

local PLACES = 'The gym this morning. The coffee place at lunch. Then the mall. Every time I look up, he is there.'
local CALLED = { caller = 'the caller', him = 'the man' }

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
    c:objective('caller', 'Talk to the caller', { hint = 'She has stopped here and is waiting for you.', blip = 'caller' })
    c:objective('her_car', 'Check her car', { hint = 'Anything left on it, or under it.', blip = 'her_car' })
    c:objective('find', "Find the man she's describing", { hint = 'Ask her what he drives.' })
    c:objective('his_car', 'Check his car', { hidden = true, blip = 'his_car', hint = 'From the outside: what can you see?' })
    c:objective('home', 'Check her home', { hidden = true, blip = 'him', hint = 'The note says that is where he went.' })
    c:objective('explain', 'Tell the caller what is going on', { hidden = true, blip = 'caller', hint = 'She needs to hear it from you.' })
    c:objective('knife', 'Stop him: he has a knife', { hidden = true, who = 'all', blip = 'him', hint = 'Keep your distance. He gives up if he has to.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'caller' }, who = 'all' })
end

-- Done when: she's said what's been going on, her car's been looked at, he's been reached. Reaching him opens his car.
local function wire(c)
    c:on('act', function(who, action, arg)
        if who == 'caller' and action == 'ask' and arg == 'c_what' then c:done('caller') end
    end)
    c:on('fact', function(_, fact) if fact == 'c_car' and not c:get('gone') then c:blip('find', 'his_car') end end)
    c:on('inspect', function(clue)
        if clue == 'note' then c:set('note_seen', true) c:done('her_car') end
        if clue == 'stash' then c:set('stash_seen', true) c:done('his_car') end
    end)
    c:on('contact', function(who)
        if who ~= 'him' then return end
        c:done('find')
        c:reveal('his_car')
        c:reveal('stash')
        c:blip('decide', 'him') -- (not before: the map would give away where he is)
    end)
    c:on('dead', function(who)
        if who == 'caller' then c:done('caller') c:done('explain') end
    end)
end

-- Gives her a fact the officer found out elsewhere, so the question it opens is there the next time she's spoken to.
local function tell_her(c, fact)
    local o = c:who('caller')
    if not o then return end
    o.facts[fact] = 'yes'
    c:questions('caller')
end

-- Seen a unit coming, he's off to the next spot in `stops` (points that aren't at this location are passed over), until
-- someone reaches him. Each time: once he's got out, the next unit close enough moves him on.
-- ponytail: shot dead at the wheel, paramedics can't reach him (they don't take people in cars): the coroner or leaving
-- ends it. Reached on foot in the moment he sits down, the stop is a foot stop on a seated man. Neither sticks the call.
local function keeps_moving(c, stops)
    local i, moving, reached, first = 1, false, false, true
    c:on('contact', function(who) if who == 'him' then reached, moving = true, false c:set('moving', false) end end)
    c:on('parked', function(who) if who == 'him' then moving = false c:set('moving', false) end end)
    c:on('tick', function()
        local o = c:who('him')
        if reached or moving or not stops[i] or not o or o.cuffed or c:get('drawn') or c:get('dead_him') then return end
        if not c:near('him', first and 45.0 or 30.0) then return end
        while stops[i] and c:task('him', 'drive', { car = 'his_car', to = stops[i] }) == false do i = i + 1 end
        if not stops[i] then return end
        i, moving = i + 1, true
        c:set('moving', true)
        o.facts.c_moved = 'yes'
        if first and c:near('caller', 30.0) then c:say('caller', "That's him! That's the car! He's leaving!") end
        first = false
    end)
end

-- Spoken to for the first time, on foot, `odds` he bolts (the stop's chase). Not at the wheel: the stop's pulling him
-- over. Not once he's given up.
local function may_bolt(c, odds)
    local spoken, bolting = false, false
    c:on('contact', function(who)
        if who ~= 'him' or spoken then return end
        spoken = true
        local o = c:who('him')
        bolting = o.role ~= 'driver' and not o.gave_up and math.random() < odds
    end)
    c:on('tick', function() -- (a moment after the stop's taken hold of him, or the stop's first order overrides it)
        if not bolting then return end
        bolting = false
        if c:talking() then c:task('him', 'flee') end
    end)
end

-- On foot, a unit within 6 m: 15% he pulls the knife. Then he gives up once he's hurt, half the time when told to, or
-- after 45-120 s with units still near.
local function may_draw(c)
    local reacted, fighting, left = false, false, 0
    local function surrender(line)
        fighting = false
        local o = c:who('him')
        o.ran, o.gave_up = true, true -- (he's done: going for the cuffs won't send him running now)
        c:set('drawn', false)
        c:done('knife')
        c:blip('decide', 'him')
        c:say('him', line)
        c:task('him', 'surrender')
    end
    c:on('tick', function()
        local o = c:who('him')
        if not o or o.cuffed or c:get('dead_him') then return end
        if not reacted and not c:get('moving') and c:near('him', 6.0) and not c:talking() then
            reacted = true
            if math.random() < 0.15 then
                fighting, left = true, math.random(45, 120)
                c:set('drawn', true)
                c:reveal('knife')
                c:note('The suspect drew a knife')
                c:task('him', 'shoot')
            end
        end
        if not fighting then return end
        local health = c:health('him')
        left = c:near('him', 45.0) and left - 1 or left
        if health and health > 100 and health < 150 then surrender("Okay! Okay! I'm hurt, I'm done! Don't!")
        elseif left <= 0 then surrender("Alright! I'm dropping it! It's on the ground!") end
    end)
    c:on('hail', function(who)
        if who == 'him' and fighting and math.random() < 0.5 then surrender("Alright! Alright! I'm dropping it!") end
    end)
    c:on('contact', function(who) if who == 'him' then reacted = true end end)
end

--[[ It's over when everyone arrested has been taken in, or the one it's about (culprit) has been let go, got away or been
     seen to, with nobody left to take in, or she's been heard, he's been found and every unit has left (until he's found,
     a unit far off is out looking for him). ready(): neither of those is over until this says so (she's still to be
     told). Anyone hurt badly enough to die is a casualty: the card says to call paramedics.
     ends(out) -> the MDT summary; out = { [person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' |
     'pronounced' | 'hospital', left = true }. ]]
local function resolve(c, culprit, ends, ready)
    local out, taken, away_for, done, medic = {}, {}, 0, false, {}
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function let_go(v) return v == 'released' or v == 'cited' or v == 'warning' or v == 'fled' or v == 'pronounced' or v == 'hospital' end
    local function check()
        if done or waiting() then return end
        if not (next(taken) or ((let_go(out[culprit]) or out.left) and (not ready or ready()))) then return end
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
        if who == 'him' then c:set('dead_him', true) c:set('drawn', false) c:done('knife') end
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if who == culprit then -- (it's plain what happened: nothing left to work out, only seeing to them)
            for _, id in ipairs({ 'caller', 'her_car', 'find', 'his_car', 'home', 'explain', 'knife', 'decide' }) do c:done(id) end
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
        local here = c:near(nil, 80.0) or c:near('him', 80.0) or c:near('caller', 80.0) or c:talking()
        if c:is_done('caller') and c:is_done('find') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then out.left = true check() end
        else
            away_for = 0
        end
    end)
end

-- Her, and her car with what's on it (`clue`: the text of the first look). Her lines are added to the ones every story
-- shares.
local function her(c, lines, clue, spec)
    lines.c_where = lines.c_where or { PLACES }
    lines.c_car = lines.c_car or function()
        local plate = c:plate('his_car') or ''
        return { { ("A dark blue Karin Intruder. I got the end of the plate: %s."):format(plate:sub(-3)), set = { c_car = 'seen' } } }
    end
    lines.where = lines.where or { "Nowhere. I don't want to go anywhere until this is sorted out." }
    spec = spec or {}
    c:person('caller', { at = 'caller', label = 'Caller', male = false, age = { 26, 44 }, secret = spec.secret or 'clean', demeanor = 'nervous',
        warrant = spec.warrant, home = spec.home, items = spec.items, scene = 'WORLD_HUMAN_STAND_MOBILE', questions = CALLER_Q, lines = lines })
    c:vehicle('her_car', { at = 'her_car', model = 'premier', make = 'Declasse', name = 'Premier', color = 'White', paint = 111,
        owner = 'caller', label = 'Her car' })
    c:clue('note', { on = 'her_car', label = 'Her car', text = clue })
end

-- Him, and his car with what can be seen in it (`stash`). at / car_at: where they are, if not the usual spot.
local function man(c, spec, lines, stash)
    lines.where = lines.where or { "Nowhere in particular." }
    c:person('him', { at = spec.at or 'him', label = 'Man', male = true, age = spec.age or { 28, 46 }, secret = spec.secret or 'nervous',
        demeanor = spec.demeanor or 'nervous', warrant = spec.warrant, items = spec.items or {}, weapon = spec.weapon,
        scene = 'WORLD_HUMAN_SMOKING', questions = HIM_Q, lines = lines })
    c:vehicle('his_car', { at = spec.car_at or 'his_car', model = 'intruder', make = 'Karin', name = 'Intruder', color = 'Dark blue', paint = 62,
        owner = 'him', locked = false, label = 'His car' })
    c:clue('stash', { on = 'his_car', label = 'His car', hidden = true, text = stash })
end

local function denial(admit)
    return cracks(3, { "Her? No. I don't know who that is.", "I've never spoken to her. What is this?" },
        { { admit, set = { c_admit = 'yes' } } }, { "I said what I said." })
end

local function on_record(c, who, parts)
    local o, list = c:who(who), {}
    if c:get('note_seen') and parts.note then list[#list + 1] = parts.note end
    if c:get('stash_seen') and parts.stash then list[#list + 1] = parts.stash end
    if o and o.facts.found and parts.found then list[#list + 1] = parts.found end
    if o and o.facts.c_admit then list[#list + 1] = 'the admission' end
    return list[1] and (' Recorded: ' .. table.concat(list, ', ') .. '.') or ''
end

-- What the summary says about whoever it's about.
local function told(c, who, out, what, parts)
    local s = c:name(who)
    local how = out[who]
    if how == 'arrested' then return ('%s: %s arrested.'):format(what, s) .. on_record(c, who, parts) end
    if how == 'dead' or how == 'pronounced' then return ('%s: %s died at the scene.'):format(what, s) .. on_record(c, who, parts) end
    if how == 'hospital' then return ('%s: %s was taken to hospital.'):format(what, s) .. on_record(c, who, parts) end
    if how == 'fled' then return ('%s: %s ran and got away.'):format(what, s) end
    if how == 'cited' or how == 'warning' then
        return ('%s: %s was given a %s and let go.'):format(what, s, how == 'cited' and 'ticket' or 'warning')
    end
    if how then return ('%s: %s was spoken to and let go.'):format(what, s) end
    return ('%s: %s was not arrested.'):format(what, s)
end

-- The name check: the first time they're ID'd, dispatch has something to say.
local function on_file(c, who, text, fact)
    local said = false
    c:on('act', function(k, action)
        if k ~= who or action ~= 'licence' or said then return end
        said = true
        c:dispatch(text:format(c:name(who)))
        c:note(text:format(c:name(who)))
        if fact then tell_her(c, fact) end
    end)
end

local STOPS = { 'next', 'last' }

Callout({
    id = 'stalking',
    name = 'Stalking',
    voice = 'call_stalking', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        "Caller says a man has been following her all day, from place to place. She's scared to go home.",
        'Female caller reports the same car behind her at three different locations today.',
        "Caller believes she's being followed. She has stopped in a public place and is waiting for officers.",
    },
    -- The points each location needs, in the order /c3rplace stalking walks you through them. The first is where the call
    -- is (units are on scene within Config.Callouts.arrive m of it).
    -- Skip the optional ones with Z in /c3rplace: without next and last he stays put, without home the home story
    -- doesn't play there.
    points = {
        { 'caller', 'The caller, standing somewhere public beside where her car is parked.' },
        { 'her_car', 'Her car, parked close to her. Sit in a car parked there.', 'car' },
        { 'his_car', "His car, up the street where he can watch her. Sit in a car parked there.", 'car' },
        { 'him', 'Him, on foot beside that car, watching her.' },
        { 'next', 'The next place he parks when he moves off, a street or so away. Sit in a car parked there.', 'car', optional = true },
        { 'last', 'The last place he parks. Sit in a car parked there.', 'car', optional = true },
        { 'home', 'Her home: him waiting in the yard or at the door.', optional = true },
        { 'home_car', 'His car, parked near her home. Sit in a car parked there.', 'car', optional = true },
    },
    -- Add more with /c3rplace stalking in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Senora Way', at = vector3(2371.09, 2536.77, 46.67), streets = { next = 'Senora Fwy' }, points = {
            caller = vector4(2371.09, 2536.77, 46.67, 220.3),
            her_car = vector4(2371.49, 2540.76, 46.26, 355.3),
            his_car = vector4(2391.00, 2575.83, 46.02, 12.8),
            him = vector4(2390.78, 2572.33, 46.58, 162.4),
            next = vector4(2315.85, 2615.06, 46.34, 168.5),
        } },
        { street = 'Nikola Pl', at = vector3(1350.55, -556.45, 74.25), streets = { next = 'East Mirror Dr', last = 'Utopia Gardens' }, points = {
            caller = vector4(1350.55, -556.45, 74.25, 171.9),
            her_car = vector4(1352.86, -554.52, 73.71, 334.1),
            his_car = vector4(1321.94, -552.55, 71.84, 70.8),
            him = vector4(1325.14, -552.70, 72.58, 261.1),
            next = vector4(1257.74, -584.52, 68.50, 191.6),
            last = vector4(1368.72, -749.06, 66.64, 231.8),
            home = vector4(1347.78, -548.36, 73.87, 338.6),
            home_car = vector4(1342.19, -560.35, 73.45, 69.3),
        } },
        { street = 'Procopio Dr', at = vector3(-207.50, 6412.03, 31.57), points = {
            caller = vector4(-207.50, 6412.03, 31.57, 17.5),
            her_car = vector4(-207.44, 6409.23, 31.27, 217.9),
            his_car = vector4(-204.92, 6456.41, 30.75, 249.4),
            him = vector4(-204.50, 6457.68, 31.15, 245.9),
            next = vector4(-150.98, 6489.88, 29.32, 344.2),
            last = vector4(-77.07, 6600.60, 29.20, 60.8),
            home = vector4(-221.82, 6403.79, 31.39, 204.6),
            home_car = vector4(-226.94, 6402.68, 30.90, 303.9),
        } },
    },

    stories = {
        -- ── Her ex. ──────────────────────────────────────────────────────────────────────────────────────────────
        ex = {
            weight = 3,
            setup = function(c)
                her(c, {
                    c_what = { "My ex. It has to be, but I can't get close enough to be sure. Everywhere I go today, that car is there. I've got a court order and he doesn't care." },
                    c_know = { "We were together three years. I ended it in the spring. I got a protective order after he came to my work." },
                    c_now = { "He was up the street a minute ago. He won't be far." },
                    c_photo = { "I tried. My hands were shaking. It's just a blur of a car." },
                    c_note = { "That's his writing. I'd know it anywhere." },
                }, 'A folded note under the wiper: "YOU CAN\'T IGNORE ME FOREVER. I JUST WANT TO TALK."')
                man(c, { items = { 'Photos of the caller, printed, taken today', 'Receipts from the gym, a coffee shop and the mall, all today' } }, {
                    c_here = { "Getting some air. Is that a crime now?" },
                    c_her = denial("...Fine. It's her. I just want her to talk to me. That's all I want."),
                    c_day = { "Here and there. Errands." },
                    c_left = { "I had somewhere to be. You can't stop a man driving his own car." },
                    explain = { "They're just photos. We were together. I'm allowed to keep photos." },
                }, 'Through the window: a stack of photos of her on the passenger seat, and a bunch of flowers gone limp in the footwell.')
                card(c)
                wire(c)
                c:on('inspect', function(clue) if clue == 'note' then tell_her(c, 'c_note') end end)
                on_file(c, 'him', 'Dispatch: %s is the subject of an active protective order. The protected party is your caller.')
                keeps_moving(c, STOPS)
                may_bolt(c, 0.2)
                resolve(c, 'him', function(out)
                    return told(c, 'him', out, "Stalking, breach of a protective order", { note = 'the note', stash = 'the photos in his car', found = 'the photos and receipts on him' })
                end)
            end,
        },

        -- ── A stranger, and he's got a knife. ────────────────────────────────────────────────────────────────────
        stranger = {
            weight = 2,
            setup = function(c)
                her(c, {
                    c_what = { "There's a man who keeps turning up. I've never seen him before today. He doesn't come over, he just stands there and looks at me." },
                    c_know = { "No. I've never seen him in my life. That's what scares me. How does he know where I'm going?" },
                    c_now = { "Up the street, I think. I don't want to look." },
                    c_photo = { "I got one at the mall. He's just a shape by a pillar. It's nothing." },
                    c_tracker = { "Nobody. Just me. A what? There's a what on my car?" },
                }, 'Under the rear arch, stuck on with a magnet: a GPS tracker, its battery still warm. No note.')
                man(c, { weapon = 'WEAPON_KNIFE', items = { 'A notebook: her whole day, written out by the hour', 'Kitchen knife in a sock' } }, {
                    c_here = { "Waiting. Just waiting." },
                    c_her = denial("She looked at me. A month ago, at the gym. She knows what she did."),
                    c_day = { "I go where I go." },
                    c_left = { "You were in the way." },
                    explain = { "It's so I don't forget. She needs someone to keep track of her. The knife's for me." },
                }, 'Through the window: binoculars on the dash and a folder with her first name on it. A printed map of the mall is taped inside.')
                card(c)
                wire(c)
                c:on('inspect', function(clue) if clue == 'note' then tell_her(c, 'c_tracker') end end)
                keeps_moving(c, STOPS)
                may_bolt(c, 0.2)
                may_draw(c)
                resolve(c, 'him', function(out)
                    return told(c, 'him', out, 'Stalking', { note = 'the tracker on her car', stash = 'what was in his car', found = 'the notebook and the knife' })
                end)
            end,
        },

        -- ── He's gone to her house. ──────────────────────────────────────────────────────────────────────────────
        home = {
            weight = 2,
            needs = { 'home', 'home_car' },
            setup = function(c)
                c:set('gone', true) -- (nothing up the street to mark)
                her(c, {
                    c_what = { "He's been behind me all day. Then I called you, and I looked up, and he'd gone. Why would he just go?" },
                    c_know = { "I think so. A man from my old building. He used to hold the elevator and ask where I was going." },
                    c_car = function()
                        local plate = c:plate('his_car') or ''
                        return { { ("A dark blue Karin Intruder. I got the end of the plate: %s. It's gone now."):format(plate:sub(-3)), set = { c_car = 'seen' } } }
                    end,
                    c_now = { "I don't know. He drove off the moment I got my phone out." },
                    c_photo = { "No. I didn't think of it." },
                    c_note = { "That's what it says? Home? He knows where I live?" },
                    c_home = function(o)
                        return { ("That's my house. %s. Oh God. Please. There's nobody there."):format(o.person.address or 'That address') }
                    end,
                }, 'A folded note under the wiper: "SEE YOU AT HOME." Her address is written underneath.', { home = 'home' })
                man(c, { at = 'home', car_at = 'home_car', secret = 'warrant', demeanor = 'polite',
                    items = { 'Roll of duct tape', 'Cable ties', "A key on a tag with her address" } }, {
                    c_here = { "I'm a friend. She asked me to wait for her." },
                    c_her = denial("I only wanted to see the inside. Just the once. I was going to wait for her."),
                    c_day = { "Running errands for her. She knows." },
                    where = { "Nowhere. I'm waiting for someone." },
                    explain = { "I was going to fix something in the house. For her. She gave me that key." },
                }, 'Through the window: an empty sports bag on the seat, and a bedroom window of her house circled on a printed photo.')
                card(c)
                wire(c)
                c:on('inspect', function(clue)
                    if clue ~= 'note' then return end
                    tell_her(c, 'c_note')
                    tell_her(c, 'c_addr')
                    c:reveal('home')
                    c:blip('find', 'him')
                    c:dispatch("Units: the note on her car says he's gone to her home. Check the address.")
                end)
                c:on('contact', function(who) if who == 'him' then c:reveal('home') c:done('home') end end)
                may_bolt(c, 0.2)
                resolve(c, 'him', function(out)
                    return told(c, 'him', out, "Stalking, found at the caller's home", { note = 'the note', stash = 'what was in his car', found = 'the tape, cable ties and her key' })
                end)
            end,
        },

        -- ── He's a private investigator. ─────────────────────────────────────────────────────────────────────────
        hired = {
            weight = 2,
            setup = function(c)
                her(c, {
                    c_what = { "A man in a blue car. He never comes near me. He's always a little way back, and I think he's writing things down." },
                    c_know = { "No. I don't think so. My husband and I are separating. It's been a horrible few months, I'm not sleeping." },
                    c_now = { "Up the street. He parks where he can see me." },
                    c_photo = { "I tried. He put his head down." },
                    c_told = { { "My husband? He paid someone to follow me around? ...I thought I was going to die today. He can do that? That's legal?", set = { c_explained = 'yes' } } },
                }, 'Nothing. Locked, no marks, nothing on it or under it.')
                man(c, { secret = 'clean', demeanor = 'polite', age = { 40, 56 },
                    items = { 'Private investigator licence, valid', 'A signed case file from a divorce lawyer' } }, {
                    c_here = { { "Working. I'd rather not say more out on the street, officer.", set = { c_work = 'yes' } } },
                    c_her = { { "I do. She doesn't know me. That's rather the point of the job.", set = { c_work = 'yes' } } },
                    c_day = { "I've a log, if you'd like it. Every stop, with times." },
                    c_left = { { "I'd been made. When the police arrive, I move on and keep my distance. That's how it's done.", set = { c_work = 'yes' } } },
                    explain = { { "That's my licence and my case file. All in order. Call the number on it, if you'd like.", set = { c_work = 'yes' } } },
                    c_job = { { "I'm a licensed private investigator. A divorce case: the husband's lawyer retained me. Here's my card. It's all above board.", set = { c_pi = 'yes' } } },
                }, "Through the window: a camera with a long lens, a clipboard log in neat handwriting and an agency permit on the dash.")
                card(c)
                wire(c)
                local function known()
                    tell_her(c, 'c_pi')
                    c:reveal('explain')
                end
                c:on('fact', function(_, fact)
                    if fact == 'c_pi' then known() elseif fact == 'c_explained' then c:done('explain') end
                end)
                c:on('contact_ended', function(who, outcome, src) -- (let go without asking: his card's all the officer has, and she still has to hear it)
                    if who ~= 'him' or outcome == 'cancelled' or c:who('caller').facts.c_pi then return end
                    c:tell(src, 'His card', 'Licensed private investigator, retained by her husband\'s divorce lawyer.')
                    known()
                end)
                keeps_moving(c, STOPS)
                resolve(c, 'him', function(out)
                    local s = c:name('him')
                    local about = c:who('caller').facts.c_explained and ' The caller was told.' or ''
                    if out.him == 'dead' or out.him == 'pronounced' then
                        return ('Stalking report: %s, a licensed private investigator on a divorce case, died at the scene.'):format(s) .. about
                    elseif out.him == 'hospital' then
                        return ('Stalking report: %s, a licensed private investigator on a divorce case, was taken to hospital.'):format(s) .. about
                    elseif out.him == 'arrested' then
                        return ('Stalking report: %s, a licensed private investigator on a divorce case, was arrested. Nothing on record supports a crime.'):format(s) .. about
                    end
                    return ('Stalking report, no crime: %s is a licensed private investigator on a divorce case, retained by her husband\'s lawyer.'):format(s) .. about
                end, function() return c:is_done('explain') end)
            end,
        },

        -- ── She's the one doing the following. ───────────────────────────────────────────────────────────────────
        reversal = {
            weight = 2,
            setup = function(c)
                her(c, {
                    c_what = { "That man. He has been following me. He's always where I am. His gym, his work, the coffee place. It's not a coincidence." },
                    c_where = { "His gym this morning. The coffee place by his office. Then outside his... the mall. I mean the mall." },
                    c_know = { "We've met. It doesn't matter how. He knows what he's doing." },
                    c_car = function()
                        local plate = c:plate('his_car') or ''
                        return { { ("A dark blue Karin Intruder. %s. Do you want the address it's registered to? I can give you that too."):format(plate), set = { c_car = 'seen' } } }
                    end,
                    c_now = { "Up there. I've been keeping an eye on him. You need to go and talk to him. Find out where he's going tonight." },
                    c_photo = { "I've got lots. Do you want them? They're all on my phone." },
                    c_print = cracks(2, { "That's for the police. For you. Evidence.", "It's just so I know where he'll be. So I can stay away." },
                        { { "...He won't answer me. I just want him to answer me.", set = { c_admit = 'yes' } } },
                        { "I told you. He won't answer me." }),
                    c_order = cracks(2, { "That's a mistake. His lawyer did that.", "It doesn't mean anything. It's a piece of paper." },
                        { { "He was mine. Three years. You can't just stop that with a piece of paper.", set = { c_admit = 'yes' } } },
                        { "I told you. He can't just stop." }),
                    explain = { "I need to know where he is. That's not a crime. He won't answer me." },
                }, "On the passenger seat, in plain view: a printed copy of a man's work rota, photos of a dark blue Intruder and a map with his gym marked on it.",
                { secret = 'warrant', warrant = 'Violation of a protective order', items = { 'Phone with a tracking app open: one tracker, moving', 'Printed copy of his work rota' } })
                man(c, { secret = 'clean' }, {
                    c_here = { "Trying to get away from her. Is she here? Is that her car? Please tell me you're here for her." },
                    c_her = { { "She's the reason I've got a court order. I've got it in the car. She has been behind me all day. I moved twice.", set = { c_court = 'yes' } } },
                    c_day = { "The gym. Work. The mall. She was at all of them. I've stopped going home the same way." },
                    c_left = { "I saw her car. Every time I see that car, I go." },
                }, "Stuck under the rear bumper with a magnet: a GPS tracker. He doesn't seem to know it's there. On the seat, a court order in a plastic sleeve.")
                card(c)
                wire(c)
                c:on('inspect', function(clue)
                    if clue == 'note' then tell_her(c, 'c_print') end
                    if clue == 'stash' then tell_her(c, 'c_order') end
                end)
                c:on('fact', function(_, fact) if fact == 'c_court' then tell_her(c, 'c_order') end end)
                on_file(c, 'caller', 'Dispatch: your caller is the subject of an active protective order, and there is a warrant for violating it.', 'c_order')
                keeps_moving(c, STOPS)
                c:on('contact', function(who) if who == 'him' then c:blip('decide', 'caller') end end)
                resolve(c, 'caller', function(out)
                    local text = told(c, 'caller', out, 'Stalking, the caller was the one following him', { note = 'the printouts in her car', stash = 'the tracker on his car', found = 'her phone and printouts' })
                    if out.him == 'arrested' then text = text .. (' %s, the protected party, was arrested as well.'):format(c:name('him')) end
                    return text
                end)
            end,
        },
    },
})
