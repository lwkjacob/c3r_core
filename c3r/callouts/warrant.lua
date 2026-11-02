--[[
    c3r callout: ARREST WARRANT.

    A warrant needs serving at the subject's address. The report is the same every time, and the card is too: the door,
    the neighbour and the property (three units can take one each). As a unit gets close, dispatch has the name, the
    reason and the car, and the subject goes on the call's MDT incident. They're someone real where it can be: anyone on
    file with an active warrant, such as the driver who got away last week. What's really going on is one of four stories:
      home      they're hiding round the back, and the resident says they moved out. May run; now and then armed
      work      they're on shift and don't know: the resident, the neighbour and a rota all say where
      tipped    the same opening, but the resident phones them: they drive off, for a chase or to where they stop
      recalled  the warrant was recalled and the system hasn't caught up: they have the receipt, at home or at work
    Cuffed, the warrant's served (stops.lua). Let go or got away, it stands, and comes up at the next stop. It's dealt with
    when they've been taken in, let go, got away or seen to, or every unit has left: once reached, or with their
    workplace still unknown. On the way to work or after their car, a unit far off is out looking.

    Points per location: walk them out in game with /c3rplace warrant (it writes the location in below).
]]

local RESIDENT_Q = {
    { id = 'c_lives', label = 'Who lives here?' },
    { id = 'c_seen', label = 'When did you last see them?', stress = true },
    { id = 'c_where', label = 'Where are they now?', stress = true, press = true },
    { id = 'c_warm', label = 'Their car is here, and the hood is warm.', needs = { c_warm = true }, stress = true, press = true },
    { id = 'c_told', label = 'The neighbour saw them here today.', needs = { c_told = true }, stress = true, press = true },
    { id = 'c_called', label = 'Who did you call when we pulled up?', needs = { c_phone = true }, stress = true, press = true },
}
local NEIGHBOUR_Q = {
    { id = 'c_today', label = 'Have you seen your neighbour today?' },
    { id = 'c_job', label = 'Do you know where they work?' },
    { id = 'c_else', label = 'Anything else going on over there?' },
}
local BOSS_Q = {
    { id = 'c_there', label = 'Where are they right now?', press = true },
    { id = 'c_like', label = 'What are they like?' },
}
local SUBJECT_Q = {
    { id = 'c_warrant', label = 'There is a warrant out for you.', stress = true },
    { id = 'c_why', label = "Why haven't you dealt with it?", stress = true },
    { id = 'c_hid', label = 'Why were you hiding back here?', needs = { c_hid = true }, stress = true },
    { id = 'c_warned', label = 'Who told you we were coming?', needs = { c_warned = true }, stress = true, press = true },
    { id = 'c_receipt', label = 'Let me see that receipt.', needs = { c_receipt = true } },
}

-- The car on file: picked per call. Spawn names, makes and names as in hitrun.lua (checked against the game's list).
local CARS = {
    { model = 'asea', make = 'Declasse', name = 'Asea' },
    { model = 'premier', make = 'Declasse', name = 'Premier' },
    { model = 'stanier', make = 'Vapid', name = 'Stanier' },
    { model = 'emperor', make = 'Albany', name = 'Emperor' },
    { model = 'intruder', make = 'Karin', name = 'Intruder' },
}
local PAINTS = { { 'Black', 0 }, { 'Silver', 4 }, { 'Red', 27 }, { 'Dark blue', 62 }, { 'White', 111 } }

local CALLED = { subject = 'the subject', resident = 'the resident', neighbour = 'the neighbour', boss = 'the manager' }

-- Denies it until pressed `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

-- Lines about the subject, who can come off the records as anyone: {he} {He} {him} {his} {name} {reason}, filled in as
-- they're said. Every line in the table goes through it.
local function about(c, lines)
    local function fill(s)
        local p = c:who('subject').person
        local male = p.gender == 'Male'
        return (s:gsub('{(%a+)}', { he = male and 'he' or 'she', He = male and 'He' or 'She', him = male and 'him' or 'her',
            his = male and 'his' or 'her', name = p.first, reason = (c:get('reason') or 'that'):lower() }))
    end
    local out = {}
    for k, v in pairs(lines) do
        out[k] = function(o)
            local said = {}
            for i, l in ipairs(type(v) == 'function' and v(o) or v) do
                said[i] = type(l) == 'table' and { fill(l[1]), set = l.set } or fill(l)
            end
            return said
        end
    end
    return out
end

local function card(c)
    c:objective('door', 'Knock at the address on file', { hint = 'Dispatch has the name. Find out who is home.', blip = 'resident' })
    c:objective('neighbour', 'Speak to the neighbour', { hint = 'They see who comes and goes.', blip = 'neighbour' })
    c:objective('yard', 'Look around the property', { hint = 'Anything that says who has been here.', blip = 'yard' })
    c:objective('car', 'Check their car', { hidden = true, blip = 'car', hint = 'The plate is on the MDT incident.' })
    c:objective('back', 'Check round the back', { hidden = true, blip = 'subject', hint = 'Someone was here a minute ago.' })
    c:objective('work', 'Go to their workplace', { hidden = true, blip = 'boss', hint = 'Marked on your map. Ask for them there.' })
    c:objective('stop', 'Stop their car', { hidden = true, who = 'all', blip = 'car', hint = 'They know you are coming.' })
    c:objective('armed', 'Stop them: they are armed', { hidden = true, who = 'all', blip = 'subject', hint = 'Take cover. They give up if they have to.' })
    c:objective('papers', 'Check their paperwork', { hidden = true, blip = 'subject', hint = 'Ask to see it. Dispatch can check it with the court.' })
    c:objective('decide', 'Serve the warrant: arrest them, or let them go', { after = { 'door' }, who = 'all' })
end

-- Gives someone a fact the officer found out elsewhere, so the question it opens is there the next time they're spoken to.
local function tell(c, who, fact)
    local o = c:who(who)
    if not o then return end
    o.facts[fact] = 'yes'
    c:questions(who)
end

-- Done when: the door's answered, the neighbour's been asked, the property's been looked at, the car's been looked at,
-- they've been reached. Dispatch has the details as a unit gets close. A place of work comes from the resident, the
-- neighbour or the rota in the yard; round the back from the yard or the resident.
local function wire(c)
    local function workplace()
        if c:get('at') ~= 'work' or c:get('known') then return end
        c:set('known', true)
        c:reveal('work')
        c:reveal('car')
        c:reveal('hood')
        c:dispatch('Place of work on file for the subject. Marking it on your map.')
        c:note('Place of work found for the subject')
    end
    c:on('build', function()
        local s = c:who('subject').person
        c:set('reason', s.warrant)
        local text = ('Warrant subject: %s %s, born %s. Wanted for: %s. On file at %s. Vehicle: %s, plate %s.'):format(s.first, s.last,
            s.dob or 'unknown', s.warrant or 'unknown', s.address or 'no fixed address', c:get('car_text'), c:plate('car') or 'unknown')
        c:dispatch(text)
        c:note(text)
        c:file('subject')
    end)
    c:on('contact', function(who)
        if who == 'resident' then
            c:done('door')
            if c:get('at') == 'home' then c:reveal('car') c:reveal('hood') end
        elseif who == 'boss' then
            c:done('work')
        elseif who == 'subject' then
            c:set('met', true)
            c:done('stop')
            c:done('back')
            c:done('work')
            c:blip('decide', 'subject')
        end
    end)
    c:on('act', function(who, action, arg)
        if who == 'neighbour' and action == 'ask' and arg == 'c_today' then c:done('neighbour') end
    end)
    c:on('fact', function(_, fact)
        if fact == 'c_work' then workplace() end
        if fact == 'c_admit' or fact == 'c_home' then
            if c:get('at') == 'home' then c:reveal('back') end
        end
        if fact == 'c_saw' then tell(c, 'resident', 'c_told') end
        if fact == 'c_phone' then tell(c, 'resident', 'c_phone') end
    end)
    c:on('inspect', function(clue)
        if clue == 'yard' then
            c:done('yard')
            if c:get('at') == 'home' then c:reveal('back') else workplace() end
        end
        if clue == 'hood' then
            c:done('car')
            if c:get('hiding') then tell(c, 'resident', 'c_warm') end
        end
    end)
    c:on('dead', function(who)
        if who == 'resident' then c:done('door') end
        if who == 'neighbour' then c:done('neighbour') end
    end)
end

-- Spoken to for the first time, `odds` they bolt (the stop's chase).
local function may_run(c, odds)
    local spoken, bolting = false, false
    c:on('contact', function(who)
        if who ~= 'subject' or spoken then return end
        spoken = true
        local o = c:who('subject')
        bolting = o.role ~= 'driver' and not o.gave_up and math.random() < odds
        if not bolting then o.ran, o.gave_up = true, true end -- (the odds are these: going for the cuffs won't send them running)
    end)
    c:on('tick', function() -- (a moment after the stop's taken hold of them, or the stop's first order overrides it)
        if not bolting then return end
        bolting = false
        if c:talking('subject') then c:task('subject', 'flee') end
    end)
end

-- A unit within 8 m before anyone's spoken to them: half the time they draw. Then they give up once they're hurt, half
-- the time when told to, or after 45-120 s with units still near.
local function cornered(c)
    local reacted, fighting, left = false, false, 0
    local function surrender(line)
        fighting = false
        local o = c:who('subject')
        o.ran, o.gave_up = true, true -- (done: going for the cuffs won't send them running now)
        c:done('armed')
        c:blip('decide', 'subject')
        c:say('subject', line)
        c:task('subject', 'surrender')
    end
    c:on('fired', function(who)
        if who ~= 'subject' then return end
        c:reveal('armed')
        c:dispatch('Shots fired! All units, shots fired!')
        c:note('Shots fired by the subject')
    end)
    c:on('tick', function()
        local o = c:who('subject')
        if not o or o.cuffed or c:get('dead_subject') then return end
        if not reacted and c:near('subject', 8.0) and not c:talking() then
            reacted = true
            if math.random() < 0.5 then
                fighting, left = true, math.random(45, 120)
                c:task('subject', 'shoot')
            end
        end
        if not fighting then return end
        local health = c:health('subject')
        left = c:near('subject', 45.0) and left - 1 or left
        if health and health > 100 and health < 150 then surrender("Okay! Okay, I'm hit! I'm done! Don't shoot!")
        elseif left <= 0 then surrender("Alright! I'm done! It's on the ground, don't shoot!") end
    end)
    c:on('hail', function(who)
        if who == 'subject' and fighting and math.random() < 0.5 then surrender("Alright! Alright! I'm putting it down!") end
    end)
    c:on('contact', function(who) if who == 'subject' then reacted = true end end)
    c:on('dead', function(who) if who == 'subject' then c:set('dead_subject', true) fighting = false c:done('armed') end end)
end

-- What the MDT says happened. out = { [person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' |
-- 'pronounced' | 'hospital', left = true }.
local function summary(c, out)
    local s, reason, how = c:name('subject'), c:get('reason') or 'unknown', out.subject
    local head = ('Arrest warrant for %s:'):format(reason)
    local o, r = c:who('subject'), c:who('resident')
    local also = r and r.facts.c_admit and c:get('covered') or ''
    if how == 'arrested' then
        local where = c:get('at') == 'home' and 'at home' or c:get('moved') and 'after leaving work' or 'at work'
        if c:get('recalled') then return ('%s recalled by the court. %s was arrested %s all the same. Nothing on record supports it.'):format(head, s, where) end
        local said = o and o.facts.c_receipt and ' They said it had been recalled: not checked.' or ''
        return ('%s served. %s arrested %s.'):format(head, s, where) .. said .. also
    end
    if how == 'dead' or how == 'pronounced' then return ('%s not served. %s died at the scene.'):format(head, s) .. also end
    if how == 'hospital' then return ('%s not served. %s was taken to hospital.'):format(head, s) .. also end
    if c:get('recalled') then return ('%s recalled by the court, and the record cleared. %s was let go.'):format(head, s) end
    local stands = ' The warrant stands.'
    if how == 'fled' then return ('%s not served. %s ran and got away.'):format(head, s) .. stands .. also end
    if how == 'cited' then return ('%s not served. %s was given a ticket and a court date.'):format(head, s) .. stands .. also end
    if how == 'warning' then return ('%s not served. %s was given a warning.'):format(head, s) .. stands .. also end
    if how == 'released' or c:get('met') then return ('%s not served. %s was spoken to and let go.'):format(head, s) .. stands .. also end
    return ('%s not served. %s was not found.'):format(head, s) .. stands .. also
end

--[[ It's over when the subject has been taken in, let go, got away or seen to, with nobody left to take in, or every unit
     has left: once they've been reached, or with no workplace known (with one known, a unit far off is on its way there,
     and after a moving car, too). Anyone shot is a casualty: the card says to call paramedics. ]]
local function resolve(c)
    local out, taken, away_for, done, medic = {}, {}, 0, false, {}
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function let_go(v) return v == 'released' or v == 'cited' or v == 'warning' or v == 'fled' or v == 'pronounced' or v == 'hospital' end
    local function check()
        if done or waiting() then return end
        if not (taken.subject or let_go(out.subject) or out.left) then return end
        done = true
        c:done('decide')
        local text, also, more = summary(c, out), {}, {}
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
            if who == 'subject' then c:done('decide') end
        elseif action == 'uncuff' and out[who] == 'arrested' then
            out[who] = nil
            c:hide('custody:' .. who)
            -- (served at the cuffs if the contact ended there: walking free, it goes back on)
            if who == 'subject' and not o.person.warrant and not c:get('recalled') then c:warrant('subject', c:get('reason')) end
        elseif who ~= 'subject' and (action == 'cite' or action == 'warn') and out[who] ~= 'arrested' then
            out[who] = action == 'cite' and 'cited' or 'warning'
        end
        check() -- (the subject's ticket counts when the contact ends: they can still be cuffed until then)
    end)
    c:on('custody', function(who) taken[who] = true check() end)
    local function seen_to(who, how)
        out[who] = how
        c:done('medic:' .. who)
        check()
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true check() end
        if out[who] == 'dead' then seen_to(who, 'pronounced')
        elseif who == 'subject' and not out.subject then out.subject = 'fled' check() end -- (deleted by the game: gone)
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if who == 'subject' then -- (nothing left to work out, only seeing to them)
            for _, id in ipairs({ 'door', 'neighbour', 'yard', 'car', 'back', 'work', 'stop', 'armed', 'papers', 'decide' }) do c:done(id) end
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
        local here = c:near(nil, 120.0) or c:near('subject', 80.0) or c:near('boss', 80.0) or c:talking() -- (120: their car's about)
        local looking = c:get('moving') or ((c:get('known') or c:get('moved')) and not c:get('met'))
        if c:is_done('door') and not waiting() and not here and not looking then
            away_for = away_for + 1
            if away_for >= 15 then out.left = true check() end
        else
            away_for = 0
        end
    end)
end

--[[ Who's there in every story. o = { at = 'home' | 'work', spec (the subject's own), resident, neighbour, subject, boss
     (lines, through about()), yard and hood (what a look finds) }. The subject comes first: the household takes their
     surname. ]]
local function stage(c, o)
    local car, paint = CARS[math.random(#CARS)], PAINTS[math.random(#PAINTS)]
    local home = o.at == 'home'
    c:set('at', o.at)
    c:set('car_text', ('%s %s %s'):format(paint[1]:lower(), car.make, car.name))
    local spec = o.spec or {}
    spec.at, spec.label, spec.home, spec.family = home and 'back' or 'work', 'Subject', true, true
    spec.demeanor, spec.secret, spec.questions = spec.demeanor or 'nervous', 'warrant', SUBJECT_Q
    spec.age = { 22, 58 }
    spec.scene = home and 'WORLD_HUMAN_SMOKING' or 'WORLD_HUMAN_CLIPBOARD' -- UNVERIFIED (no other callout uses CLIPBOARD)
    o.subject.where = o.subject.where or { 'Nowhere. Not now.' }
    spec.lines = about(c, o.subject)
    c:person('subject', spec)
    c:person('resident', { at = 'door', label = 'Resident', home = true, family = true, secret = 'clean', demeanor = o.demeanor or 'nervous',
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = RESIDENT_Q, lines = about(c, o.resident) })
    c:person('neighbour', { at = 'neighbour', label = 'Neighbour', age = { 60, 82 }, secret = 'clean', demeanor = 'chatty',
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = NEIGHBOUR_Q, lines = about(c, o.neighbour) })
    if o.boss then
        c:person('boss', { at = 'boss', label = 'Manager', age = { 45, 65 }, secret = 'clean', demeanor = 'polite',
            scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = BOSS_Q, lines = about(c, o.boss) })
    end
    c:vehicle('car', { at = home and 'drive' or 'work_car', model = car.model, make = car.make, name = car.name,
        color = paint[1], paint = paint[2], owner = 'subject', locked = false, label = 'Their car' })
    c:clue('yard', { at = 'yard', label = 'The property', prop = 'prop_cardbordbox_02a', text = o.yard })
    c:clue('hood', { on = 'car', label = 'Their car', hidden = true, text = o.hood })
    card(c)
    wire(c)
end

local WORK_YARD = 'Nobody out here. A bare patch on the drive where a car usually sits, and a work rota pinned inside the porch: on shift all day today.'
local WORK_HOOD = 'Parked in a staff bay, cold to the touch. A lunch box on the seat and work boots in the footwell.'

Callout({
    id = 'warrant',
    name = 'Arrest warrant',
    voice = 'call_warrant', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        "Warrants asks for a unit to serve an outstanding arrest warrant at the subject's home address.",
        'Arrest warrant to serve. The subject was last known at this address.',
        'Active warrant with no recent contact. Attend the address on file and locate the subject.',
    },
    -- The points each location needs, in the order /c3rplace warrant walks you through them. The first is where the call
    -- is (units are on scene within Config.Callouts.arrive m of it). The workplace can be anywhere: it's made when a unit
    -- gets near.
    points = {
        { 'door', 'Whoever answers: at the front door of the house.' },
        { 'neighbour', 'The neighbour, on their doorstep or at the fence next door.' },
        { 'yard', 'Something to look at round the property: on the ground by the house.' },
        { 'drive', 'Their car, on the drive or outside the house. Sit in a car parked there.', 'car' },
        { 'back', 'Someone keeping out of sight: behind the house, by the back fence.' },
        { 'work', 'The subject at work: where they stand on the job, a shop, garage or site.' },
        { 'boss', 'Their manager, at the way in to the workplace.' },
        { 'work_car', 'Their car, in a staff space at the workplace. Sit in a car parked there.', 'car' },
        { 'hideout', 'Where they drive if they run: a quiet car park well away from both. Sit in a car parked there.', 'car' },
    },
    -- Add more with /c3rplace warrant in game (it writes them here). This one is a rough placeholder.
    locations = {
        { street = 'Paleto Blvd', at = vector3(-105.16, 6529.10, 30.17), points = {
            door = vector4(-105.16, 6529.10, 30.17, 30.2),
            neighbour = vector4(-129.26, 6550.46, 29.52, 241.0),
            yard = vector4(-98.27, 6540.20, 29.81, 135.1),
            drive = vector4(-73.23, 6603.38, 29.03, 97.9),
            back = vector4(-111.54, 6533.10, 29.81, 357.8),
            work = vector4(-207.50, 6412.03, 31.57, 17.5),
            boss = vector4(-221.82, 6403.79, 31.39, 204.6),
            work_car = vector4(-207.44, 6409.23, 31.27, 217.9),
            hideout = vector4(-354.40, 6263.55, 31.28, 137.0),
        } },
        { street = 'West Mirror Drive', at = vector3(967.27, -451.76, 62.79), streets = { work = 'Mirror Park Blvd', boss = 'Mirror Park Blvd', hideout = 'Bridge St' }, points = {
            door = vector4(967.27, -451.76, 62.79, 203.3),
            neighbour = vector4(1000.45, -440.02, 64.14, 193.3),
            yard = vector4(971.37, -459.46, 62.49, 136.1),
            drive = vector4(975.98, -453.19, 62.13, 40.5),
            back = vector4(962.83, -445.37, 62.60, 322.4),
            work = vector4(1159.38, -319.94, 69.21, 332.0),
            boss = vector4(1164.73, -318.02, 69.21, 126.6),
            work_car = vector4(1154.04, -331.93, 68.44, 4.4),
            hideout = vector4(1139.75, -413.32, 66.71, 222.0),
        } },
    },

    stories = {
        -- ── They're round the back. ────────────────────────────────────────────────────────────────────────────
        home = {
            weight = 4,
            setup = function(c)
                local armed = math.random() < 0.2
                local where = cracks(3, { "I told you, {he} doesn't live here any more.", "I don't know where {he} is. Is that a crime?" },
                    { { armed and "...{He}'s round the back. {He} heard you pull up. And {he} took the gun from the closet. Please, don't hurt {him}."
                        or "...{He}'s round the back. {He} heard you pull up. Please, don't hurt {him}.", set = { c_admit = 'yes' } } },
                    { "I told you. Round the back." })
                c:set('hiding', true)
                c:set('covered', ' The resident admitted covering for them.')
                stage(c, { at = 'home',
                    spec = { wanted = true, facts = { c_hid = 'yes' }, weapon = armed and 'WEAPON_PISTOL' or nil,
                        items = armed and { 'Pistol, loaded' } or {} },
                    subject = {
                        c_warrant = { "For {reason}. Yeah, I know. I wasn't going to open the door to you, was I?" },
                        c_why = { "You don't deal with it. You just hope it goes away.", 'Because I knew how this ends.' },
                        c_hid = { 'What would you do? I heard the car.' },
                    },
                    resident = {
                        c_lives = { "Just me now. {name} moved out weeks ago." },
                        c_seen = { "Weeks. A month, maybe. I don't keep track." },
                        c_where = where, c_warm = where, c_told = where,
                    },
                    neighbour = {
                        c_today = { { "An hour ago. Came back with shopping and went straight in.", set = { c_saw = 'yes' } } },
                        c_job = { "Not lately. {He} packed in the job, I think." },
                        c_else = { "{He}'s been keeping {his} head down. Curtains shut all week." },
                    },
                    yard = 'The back door is ajar. On the step, a cigarette still burning in a saucer, and a plate of food going cold.',
                    hood = 'The hood is warm and the engine is ticking as it cools. Shopping bags on the back seat.',
                })
                may_run(c, 0.3)
                if armed then
                    cornered(c)
                    c:on('fact', function(_, fact)
                        if fact ~= 'c_admit' then return end
                        c:dispatch('All units: the resident says the subject is armed with a handgun. Use caution.')
                        c:note('The resident said the subject took a handgun')
                    end)
                end
                resolve(c)
            end,
        },

        -- ── They're on shift, and don't know. ──────────────────────────────────────────────────────────────────
        work = {
            weight = 3,
            setup = function(c)
                stage(c, { at = 'work', spec = { wanted = true, demeanor = 'polite' },
                    subject = {
                        c_warrant = { "For {reason}? Here? In front of everyone? ...Okay. Okay, I know about it. I thought I had longer." },
                        c_why = { "I've been working every hour there is. I kept meaning to.", "I needed this job. I thought it could wait." },
                    },
                    resident = {
                        c_lives = { "Me and {name}. Why, what's happened?" },
                        c_seen = { "This morning. {He} left for work at the usual time." },
                        c_where = { { "At work. {He}'s on shift all day. What is this about?", set = { c_work = 'yes' } } },
                    },
                    neighbour = {
                        c_today = { "Went off early, same as always. Car's gone." },
                        c_job = { { "{He}'s on shift most days. Works hard, I'll say that.", set = { c_work = 'yes' } } },
                        c_else = { "No. Quiet people. Nothing to tell." },
                    },
                    boss = {
                        c_there = { "Over there, on shift. Is {he} in some kind of trouble?" },
                        c_like = { "Best worker I've got. Never late. Do you have to do this here?" },
                    },
                    yard = WORK_YARD, hood = WORK_HOOD,
                })
                may_run(c, 0.15)
                resolve(c)
            end,
        },

        -- ── The resident phones them. ──────────────────────────────────────────────────────────────────────────
        tipped = {
            weight = 2,
            setup = function(c)
                local called = cracks(2, { "My sister. Is that allowed?", "I don't have to tell you who I call." },
                    { { "...I told {him}. Alright? {He} deserved to know you were coming.", set = { c_admit = 'yes' } } },
                    { "I told you. I called {him}." })
                c:set('covered', ' The resident admitted warning them.')
                stage(c, { at = 'work', spec = { wanted = true, runs = true, bail = 0.4 },
                    subject = {
                        c_warrant = { "For {reason}. I know. I'm not stupid." },
                        c_why = { "Because I knew this is what it'd look like." },
                        c_warned = { "Nobody told me anything.", "...Leave them out of it." },
                    },
                    resident = {
                        c_lives = { "Me and {name}. Why, what's happened?" },
                        c_seen = { "This morning. {He} left for work at the usual time." },
                        c_where = { { "At work. {He}'s on shift all day. What is this about?", set = { c_work = 'yes' } } },
                        c_called = called,
                    },
                    neighbour = {
                        c_today = { "Went off early, same as always. Car's gone." },
                        c_job = { { "{He}'s on shift most days. Works hard, I'll say that.", set = { c_work = 'yes' } } },
                        c_else = { { "Only that the moment your car pulled up, there was someone at the window with a phone.", set = { c_phone = 'yes' } } },
                    },
                    boss = {
                        c_there = function()
                            if c:get('moved') then return { "You just missed {him}. Took a phone call, went white and walked straight out to the car." } end
                            return { "Over there. {He}'s been jumpy since a phone call." }
                        end,
                        c_like = { "Best worker I've got. Never late. What's going on?" },
                    },
                    yard = WORK_YARD, hood = WORK_HOOD,
                })
                -- the door shut, or the workplace named: the phone call. Then they go, as soon as they're in the world
                -- (they're made when a unit gets near), unless someone's reached them first.
                local phoned, left = false, 0
                local function ring()
                    if phoned or c:get('met') then return end
                    phoned = true
                    tell(c, 'subject', 'c_warned')
                end
                c:on('contact_ended', function(who) if who == 'resident' then ring() end end)
                c:on('fact', function(_, fact) if fact == 'c_work' then ring() end end)
                c:on('tick', function()
                    if not phoned or c:get('moved') or c:get('met') or (c:health('subject') or 200) <= 100 then return end
                    left = left + 1
                    if left < 10 or c:task('subject', 'drive', { car = 'car', to = 'hideout', fast = true }) == false then return end
                    c:set('moved', true)
                    c:set('moving', true)
                    c:done('car')
                    c:reveal('stop')
                    c:dispatch('Their manager just called it in: the subject took a phone call and drove off. Marking the car on your map.')
                    c:note('The subject left work in their car')
                end)
                c:on('contact', function(who) if who == 'subject' then c:set('moving', false) end end)
                c:on('parked', function(who)
                    if who ~= 'subject' then return end
                    c:set('moving', false)
                    c:blip('stop', 'subject')
                end)
                resolve(c)
            end,
        },

        -- ── The warrant's already been recalled. ───────────────────────────────────────────────────────────────
        recalled = {
            weight = 2,
            setup = function(c)
                local home = math.random() < 0.5
                local paid = { { "That's done with. I paid it last Monday. I've got the receipt right here.", set = { c_receipt = 'yes' } } }
                stage(c, { at = home and 'home' or 'work', demeanor = 'polite',
                    -- (never someone off the records: a warrant they got for running from an officer can't be recalled)
                    spec = { demeanor = 'polite', warrant = math.random() < 0.5 and 'Failure to appear' or 'Unpaid citations',
                        items = { 'Court receipt: paid in full, warrant recalled, stamped last Monday' } },
                    subject = {
                        c_warrant = paid,
                        c_why = paid,
                        c_receipt = { { 'Here. Stamped and signed. Call it in, I can wait.', set = { c_checked = 'yes' } } },
                    },
                    resident = {
                        c_lives = { "Me and {name}. Is this about that court thing?" },
                        c_seen = home and { "Just now. {He}'s out back." } or { "This morning. {He} left for work at the usual time." },
                        c_where = home and { { "Out back. Go through. {He} told me that was all sorted.", set = { c_home = 'yes' } } }
                            or { { "At work. {He} told me that was all sorted. What is this about?", set = { c_work = 'yes' } } },
                    },
                    neighbour = {
                        c_today = home and { "This morning, hanging the washing out." } or { "Went off early, same as always. Car's gone." },
                        c_job = home and { "Days off this week, I think." } or { { "{He}'s on shift most days. Works hard, I'll say that.", set = { c_work = 'yes' } } },
                        c_else = { "No. Quiet people. Nothing to tell." },
                    },
                    boss = not home and {
                        c_there = { "Over there, on shift. {He} said this might happen. Some mix-up at the court." },
                        c_like = { "Best worker I've got. Never late." },
                    } or nil,
                    yard = home and 'Tidy. Washing on the line, the back door open, and a radio playing round the back of the house.' or WORK_YARD,
                    hood = home and 'Clean and cold. An envelope from the county court on the passenger seat, already opened.' or WORK_HOOD,
                })
                c:on('build', function()
                    local o = c:who('subject')
                    o.truth.id = 'hands' -- (nothing to hide: their own name)
                    o.ran, o.gave_up = true, true -- (and no reason to run from the cuffs)
                end)
                c:on('fact', function(_, fact)
                    if fact == 'c_receipt' then c:reveal('papers') end
                    if fact == 'c_checked' and not c:get('recalled') then
                        c:done('papers')
                        c:set('recalled', true)
                        c:warrant('subject', nil)
                        local text = 'Court clerk confirms: that warrant was recalled last Monday, and the system had not caught up. It is off the record now.'
                        c:dispatch(text)
                        c:note(text)
                    end
                end)
                resolve(c)
            end,
        },
    },
})
