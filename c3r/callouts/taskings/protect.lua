--[[
    c3r special tasking: PROTECTION DETAIL. Asked for on the radio ("requesting a protection detail"), never put out.

    Someone has had a credible threat after an incident (a witness in his trial, an assault, a report to police): sit on
    their house until you're stood down, about 20 minutes. The card is the same every time: talk to the resident, sit on
    the house. They name him and his car; his car is the only one like it that ever turns up. What happens is one of four
    stories:
      quiet   nothing. He never comes (1 in 8)
      drive   he drives past slowly, twice, then pulls up and walks to the door with a pistol. Stop him on a pass, or at
              the door: told to drop it, he may; left, he opens fire
      walk    he comes on foot. Stopped on the way: denial that cracks, a knife in his jacket. Not stopped: he goes for the
              resident at the door
      watch   he's parked up the street, watching. Walked up to, he talks, or pulls away (a chase, or he's gone)
    Whatever the story, quiet things happen too (two of: the neighbour comes over, a parcel's delivered, a car drives
    past twice), clear of when he comes. The car that drives past is never his kind of car.
    It's over when he's been taken in, or at about 20 minutes once nothing's going on: dispatch stands you down. A name
    check shows the protective order. Leaving early is "stood down early" on the MDT.

    Points per location: walk them out in game with /c3rplace protect (it writes the location in below).
]]

local RES_Q = {
    { id = 'c_who', label = "Who's threatening you?" },
    { id = 'c_what', label = 'What happened?' },
    { id = 'c_car', label = 'What does he drive?', needs = { c_named = true } },
    { id = 'c_seen', label = 'When did you last see him?', needs = { c_named = true } },
    { id = 'c_ok', label = 'Are you alright?' },
}
local HIM_Q = {
    { id = 'c_here', label = 'What are you doing here?', stress = true, press = true },
    { id = 'c_house', label = 'You know who lives at that house.', stress = true, press = true },
    { id = 'c_order', label = 'There is an order against you coming here.', needs = { c_order = true }, stress = true },
}
local NEIGHBOUR_Q = {
    { id = 'c_live', label = 'Do you live round here?' },
    { id = 'c_seen', label = 'Seen anyone hanging about?' },
}
local COURIER_Q = { { id = 'c_drop', label = 'What are you delivering?' } }
local PASSER_Q = { { id = 'c_why', label = 'You came past this house twice. Why?' } }

-- Why they're under threat: one per call, whatever the story.
local WHY = {
    { what = "I'm a witness. I saw him stab a man outside a bar, and the trial is next month. Since he got bail the messages haven't stopped. He says I won't make it to court.",
      short = 'a witness in his trial' },
    { what = "He hit me. Last month. I pressed charges, and now he calls from different numbers saying he'll finish what he started.",
      short = 'after an assault' },
    { what = "I reported him for dealing out of the house across the road. Someone told him it was me. Now there are notes coming through my door.",
      short = 'after reporting him to police' },
}

-- His car (one per call). The car that drives past for no reason is never one of these.
local CARS = {
    { model = 'buccaneer', make = 'Albany', name = 'Buccaneer', color = 'Red', paint = 27 },
    { model = 'fugitive', make = 'Cheval', name = 'Fugitive', color = 'Black', paint = 0 },
    { model = 'tailgater', make = 'Obey', name = 'Tailgater', color = 'Dark blue', paint = 62 },
    { model = 'sultan', make = 'Karin', name = 'Sultan', color = 'Red', paint = 27 },
}
local PASSER_CAR = { model = 'asea', make = 'Declasse', name = 'Asea', color = 'Silver', paint = 4 }

local function car_words(v) return ('%s %s %s'):format(v.color:lower(), v.make, v.name) end

-- Denies it until pressed `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

-- Something every unit on scene notices (a card on their screen).
local function tell(c, text)
    for src in pairs(c:get('units') or {}) do c:tell(src, 'You notice', text) end
end

-- Seconds since the first unit got there (nil before): the tasking's clock.
local function clock(c, secs)
    if not c:get('t0') and c:get('arrived') then c:set('t0', secs) end
    return c:get('t0') and secs - c:get('t0')
end

-- The resident, and who he is (later = true: made when his story brings him). Every story.
local function base(c, seen)
    local car, why = CARS[math.random(#CARS)], WHY[math.random(#WHY)]
    c:set('car', car)
    c:set('why', why)
    c:set('units', {})
    c:person('resident', { at = 'resident', label = 'Resident', home = true, secret = 'clean', demeanor = 'nervous',
        scene = 'WORLD_HUMAN_STAND_MOBILE', questions = RES_Q, lines = {
            c_who = function() return { { ("%s. He knows I called you. That's why you're here, isn't it?"):format(c:name('him')), set = { c_named = 'yes' } } } end,
            c_what = { why.what },
            c_car = { ("A %s. You'll know it when you see it. He never goes anywhere without it."):format(car_words(car)) },
            c_seen = seen,
            c_ok = { "Not really. I keep going to the window. Every car that goes past, I think it's him." },
        } })
end

-- Him. spec: at, seated, items, weapon, runs, lines.
local function him(c, spec)
    local car = c:get('car')
    c:person('him', { at = spec.at, later = true, label = 'Man', male = true, age = { 26, 50 }, secret = 'nervous', demeanor = 'rude',
        weapon = spec.weapon, items = spec.items or {}, seated = spec.seated, runs = spec.runs, scene = 'WORLD_HUMAN_SMOKING',
        questions = HIM_Q, lines = spec.lines })
    if spec.seated then
        c:vehicle('his_car', { at = spec.at, later = true, model = car.model, make = car.make, name = car.name, color = car.color,
            paint = car.paint, owner = 'him', locked = false, label = 'His car' })
    end
end

local function card(c)
    c:objective('resident', 'Talk to the resident', { hint = 'On the doorstep. Find out who you are watching for.', blip = 'resident' })
    c:objective('sit', "Sit on the house until you're stood down", { who = 'all', hint = 'Park where you can see the door and the road.' })
    c:objective('threat', 'Deal with the man who made the threats', { hidden = true, who = 'all', blip = 'him' })
    c:objective('armed', 'Stop him: he has a gun', { hidden = true, who = 'all', blip = 'him', hint = 'Tell him to drop it. Keep the resident behind you.' })
    c:objective('fight', 'Break up the fight at the door', { hidden = true, who = 'all', blip = 'him', hint = 'Tell them to stop, or the taser.' })
end

local function wire(c)
    c:on('arrive', function(src) c:get('units')[src] = true c:set('arrived', true) end)
    c:on('leave', function(src) c:get('units')[src] = nil end)
    c:on('build', function() c:file('him') end) -- (who to watch for, on the MDT from the start)
    c:on('act', function(who, action, arg)
        if who == 'resident' and action == 'ask' and arg == 'c_who' then c:done('resident') end
        if who == 'him' and action == 'licence' and not c:get('order_said') then -- (the name check)
            c:set('order_said', true)
            local text = ('Dispatch: %s is the subject of an active protective order. The protected party is at the address you are sitting on.'):format(c:name('him'))
            c:dispatch(text)
            c:note(text)
            c:who('him').facts.c_order = 'yes'
            c:questions('him')
        end
    end)
    c:on('contact', function(who) if who == 'him' then c:reveal('threat') c:set('stopped', true) end end)
    c:on('plate', function(v)
        if v == 'his_car' then
            c:reveal('threat')
            c:note(('The %s comes back to %s.'):format(car_words(c:get('car')), c:name('him')))
        end
    end)
    c:on('dead', function(who) if who == 'resident' then c:done('resident') end end)
end

-- ─── the quiet things ──────────────────────────────────────────────────────────

-- Times (s after the first unit got there) for n quiet things, apart from each other and clear of when he comes (T).
local function slots(T, n)
    local out = {}
    for _ = 1, 80 do
        if #out >= n then break end
        local t = math.random(60, 1050)
        local ok = not T or t < T - 150 or t > T + 360
        for _, u in ipairs(out) do if math.abs(u - t) < 150 then ok = false end end
        if ok then out[#out + 1] = t end
    end
    return out
end

-- The neighbour wanders over to the officer, says hello, and goes home.
local function neighbour(c, at)
    c:person('neighbour', { at = 'neighbour', later = true, label = 'Neighbour', secret = 'clean', demeanor = 'chatty',
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = NEIGHBOUR_Q, lines = {
            c_live = { "Next door. Twelve years. Is this about the trouble? I heard something." },
            c_seen = function()
                if c:get('watching') then return { "Now you mention it, there's a car up the street. Someone's been sat in it with the engine off since I put the bins out." } end
                return { "No. Quiet street. That's why we moved here." }
            end,
        } })
    local stage, said = nil, 0
    return function(t, now)
        if not c:who('neighbour') then return end -- (no neighbour point at this location)
        if not stage and t >= at then stage = 'out' c:bring('neighbour') end
        if stage == 'out' and c:distance('neighbour', 'neighbour') then stage = 'coming' c:task('neighbour', 'go', 'house') end
        if stage == 'coming' and (c:distance('neighbour', 'house') or 99) < 5 then
            stage, said = 'here', now
            c:say('neighbour', "Evening, officer. Everything alright? I saw you sat out here.")
        end
        if stage == 'here' and now - said > 90 and not c:talking('neighbour') then stage = 'home' c:task('neighbour', 'go', 'neighbour') end
    end
end

-- A delivery: walks up to the door from round the corner, leaves a parcel, walks off and is gone.
local function courier(c, at)
    c:person('courier', { at = 'kerb', later = true, label = 'Delivery driver', male = false, secret = 'clean',
        demeanor = 'polite', questions = COURIER_Q, lines = {
            c_drop = { "Parcel for this address. Just a box. I've got forty more today, officer." },
        } })
    c:clue('parcel', { at = 'door', label = 'A parcel', hidden = true,
        text = 'A small box addressed to the resident, from an online shop. Taped shut, light. Nothing odd about it.' })
    local stage = nil
    return function(t)
        if not stage and t >= at then stage = 'out' c:bring('courier') end
        if stage == 'out' and c:distance('courier', 'kerb') then stage = 'coming' c:task('courier', 'go', 'door') end
        if stage == 'coming' and (c:distance('courier', 'door') or 99) < 3 then
            stage = 'going'
            c:reveal('parcel')
            c:say('courier', 'Parcel! Left it on the step!')
            c:task('courier', 'go', 'to')
        end
        if stage == 'going' and not c:near('courier', 60.0) and not c:talking('courier') then
            stage = 'gone'
            c:remove('courier')
        end
    end
end

-- A car (never his kind) drives past slowly, turns round out of sight and comes back past, then it's gone.
local function passer(c, at)
    c:person('passer', { at = 'from', later = true, label = 'Driver', seated = 'passer_car', secret = 'clean', demeanor = 'polite',
        questions = PASSER_Q, lines = {
            c_why = { ("I'm looking for number %d. The numbers on this street make no sense. Is that a crime?"):format(math.random(10, 99)) },
        } })
    c:vehicle('passer_car', { at = 'from', later = true, model = PASSER_CAR.model, make = PASSER_CAR.make, name = PASSER_CAR.name,
        color = PASSER_CAR.color, paint = PASSER_CAR.paint, owner = 'passer', locked = false, label = 'A car' })
    local legs, i, moving, told, wait, stopped = { 'to', 'from' }, 1, false, false, 0, false
    c:on('parked', function(who) if who == 'passer' then moving, i, wait = false, i + 1, math.random(30, 60) end end)
    c:on('contact', function(who) if who == 'passer' then stopped = true end end)
    c:on('contact_ended', function(who, outcome) if who == 'passer' and outcome ~= 'cancelled' then c:task('passer', 'wander') end end)
    local brought = false
    return function(t)
        if stopped or i > #legs + 1 then return end
        if not brought then
            if t < at then return end
            brought = true
            c:bring('passer')
            c:bring('passer_car')
        end
        if moving then
            if not told and c:near('passer', 50.0) then told = true tell(c, ('A %s rolls past the house, slowly.'):format(car_words(PASSER_CAR))) end
            return
        end
        if wait > 0 then wait = wait - 1 return end
        if i > #legs then -- (back where it came from, out of sight: gone)
            if not c:near('passer', 80.0) then i = i + 1 c:remove('passer', 'passer_car') end
            return
        end
        if c:task('passer', 'drive', { car = 'passer_car', to = legs[i] }) ~= false then moving, told = true, false end
    end
end

-- Two of the three, at quiet times. -> a tick function
local function quiet_things(c, T)
    local kinds = { neighbour, courier, passer }
    table.remove(kinds, math.random(#kinds))
    local at = slots(T, 2)
    local runs = {}
    for n, kind in ipairs(kinds) do runs[n] = kind(c, at[n] or 99999) end
    local now = 0
    return function(t) now = now + 1 for _, run in ipairs(runs) do run(t, now) end end
end

-- ─── how it ends ────────────────────────────────────────────────────────────────

--[[ He's dealt with when he's taken in, let go (he leaves), gets away or dies and has been seen to. Taken in: over at
     once. Otherwise it's over at the stand-down (19-21 minutes in), once nothing's going on: nobody to take in, nobody
     hurt waiting, and him not still out there. how = how he came (' in a red Albany Buccaneer').
     Spoken to and walked off from (not in cuffs): a minute with nobody near and he leaves. Still out there 3 minutes
     after the stand-down and nobody with him: he leaves. Either way it's "left before he was dealt with". ]]
local function resolve(c, how)
    local out, taken, medic, done, idle = {}, {}, {}, false, 0
    local sit = math.random(1140, 1260)
    local function active() -- (he's come, and isn't dealt with yet)
        return c:get('brought') and not (taken.him or out.him == 'released' or out.him == 'cited' or out.him == 'warning'
            or out.him == 'fled' or out.him == 'pronounced' or out.him == 'hospital' or out.him == 'left')
    end
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        for _, pending in pairs(medic) do if pending then return true end end
        return false
    end
    local function summary(minutes)
        local why, name = c:get('why'), c:name('him')
        local text = ('Protection detail at %s for %s (%s).'):format(c:street(), c:name('resident'), why.short)
        local v, found = out.him, c:who('him') and c:who('him').facts.found
        local carrying = found and (' He was carrying: %s.'):format(table.concat(c:get('items') or {}, ', ')) or ''
        if not c:get('brought') then
            text = text .. (' Sat on the house for %d minutes. No sign of %s. Stood down.'):format(minutes, name)
        elseif v == 'arrested' then text = text .. (' %s came to the house%s and was arrested.%s'):format(name, how, carrying)
        elseif v == 'fled' then text = text .. (' %s came to the house%s and got away. A warrant has been issued.'):format(name, how)
        elseif v == 'pronounced' or v == 'dead' then text = text .. (' %s came to the house%s and died at the scene.'):format(name, how)
        elseif v == 'hospital' then text = text .. (' %s came to the house%s and was taken to hospital.%s'):format(name, how, carrying)
        elseif v == 'left' then text = text .. (' %s came to the house%s and left before he was dealt with.'):format(name, how)
        elseif v then text = text .. (' %s came to the house%s, was spoken to and let go.'):format(name, how)
        else text = text .. (' %s came to the house%s and was not dealt with.'):format(name, how) end
        if out.resident == 'hospital' then text = text .. (' %s was hurt and taken to hospital.'):format(c:name('resident')) end
        if out.resident == 'pronounced' then text = text .. (' %s died at the scene.'):format(c:name('resident')) end
        return text
    end
    local function finish(t)
        if done then return end
        done = true
        c:done('threat') c:done('sit')
        c:finish(summary(math.floor((t or sit) / 60)))
    end
    local function check(t)
        if done or waiting() then return end
        if taken.him then return finish(t) end
        if t and t >= sit and not active() then
            c:dispatch(('Thank you, you are relieved at %s. Stand down.'):format(c:street()))
            finish(t)
        end
    end
    local function let_go(how_)
        out.him = how_
        c:done('threat') c:done('armed') c:done('fight')
        c:set('dealt', true)
    end
    c:on('act', function(who, action)
        local o = c:who(who)
        if action == 'cuff' and o and o.cuffed then
            out[who] = 'arrested'
            c:custody(who)
            if who == 'him' then c:done('threat') c:done('armed') c:done('fight') c:set('dealt', true) end
        elseif action == 'uncuff' and out[who] == 'arrested' then
            out[who] = nil
            c:hide('custody:' .. who)
        end
    end)
    c:on('custody', function(who) taken[who] = true check() end)
    c:on('contact_ended', function(who, outcome)
        if who ~= 'him' or out.him == 'arrested' or out.him == 'dead' then return end
        if outcome == 'fled' then
            let_go('fled')
            c:warrant('him', 'Threats to kill; fled from officers at a protected address')
        elseif outcome == 'released' or outcome == 'cited' or outcome == 'warning' then
            let_go(outcome)
            c:task('him', 'wander') -- (sent on his way)
        end
    end)
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true
        elseif out[who] == 'dead' then out[who] = 'pronounced' medic[who] = false c:done('medic:' .. who) -- (the coroner's been)
        elseif who == 'him' and not out.him then -- (got clean away)
            let_go('fled')
            c:warrant('him', 'Threats to kill at a protected address')
        end
    end)
    local function hurt(who)
        if medic[who] ~= nil then return end
        medic[who] = true
        c:objective('medic:' .. who, ('Call paramedics for %s'):format(who == 'him' and 'him' or 'the resident'), { who = 'all', blip = who,
            hint = 'Radio for an ambulance. If they pronounce them, the coroner can take them.' })
        c:dispatch(('%s is down at the protected address. Paramedics needed.'):format(who == 'him' and 'The suspect' or 'The resident'))
    end
    c:set('hurt', hurt)
    c:on('dead', function(who)
        out[who] = 'dead'
        c:hide('custody:' .. who)
        if who == 'him' then c:done('threat') c:done('armed') c:done('fight') c:set('dealt', true) end
        hurt(who)
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' then out[who], medic[who] = 'pronounced', false
        elseif what == 'hospital' or what == 'treated' then
            if out[who] ~= 'arrested' or who == 'resident' then out[who] = 'hospital' end
            medic[who] = false
            if who == 'him' and out.him == 'arrested' then taken.him = true end -- (under arrest, to hospital: in custody there)
        end
        if medic[who] == false then c:done('medic:' .. who) end
    end)
    c:on('tick', function(secs)
        local t = clock(c, secs)
        local o = c:who('him')
        local p_free = active() and o and not o.cuffed and not out.him and not c:talking('him') and c:health('him')
            and (c:health('him') or 0) > 100 and not c:get('fighting_him')
        if p_free and (c:get('stopped') or (t and t >= sit + 180)) then
            idle = c:near('him', 30.0) and 0 or idle + 1
            if idle >= 60 or (t and t >= sit + 180 and not c:near('him', 30.0)) then
                let_go('left')
                c:task('him', 'wander')
                c:note(('%s left before he was dealt with'):format(c:name('him')))
            end
        else
            idle = 0
        end
        check(t)
    end)
end

-- ─── him, by story ──────────────────────────────────────────────────────────────

-- Armed at the door: hold the resident at gunpoint; 15 s without being talked down and he opens fire. He gives up half
-- the time he's told to, once he's hurt, or after 45-120 s with units near.
local function armed(c)
    local stage, left = nil, 0
    local function surrender(line)
        if stage == 'over' then return end
        stage = 'over'
        local o = c:who('him')
        o.ran, o.gave_up = true, true
        c:set('fighting_him', false)
        c:done('armed')
        c:say('him', line)
        c:task('him', 'surrender')
    end
    c:on('hail', function(who)
        if who ~= 'him' or (stage ~= 'hold' and stage ~= 'shoot') then return end
        if math.random() < 0.5 then surrender("Alright! Alright! It's down!") else c:say('him', 'Back off! This is between me and them!') end
    end)
    c:on('dead', function(who) if who == 'him' then stage = 'over' end end)
    return function()
        if stage == 'over' then return end
        if not stage then
            stage, left = 'hold', 15
            c:reveal('threat')
            c:reveal('armed')
            c:note(('%s drew a pistol at the front door'):format(c:name('him')))
            c:say('him', "You think they can keep you safe? Look at me!")
            c:task('him', 'hold', 'resident')
            c:set('fighting_him', true)
            return
        end
        local health = c:health('him')
        if health and health > 100 and health < 150 then return surrender("Okay! I'm hit! I'm done!") end
        left = left - 1
        if stage == 'hold' and left <= 0 then
            stage, left = 'shoot', math.random(45, 120)
            c:task('him', 'shoot')
        elseif stage == 'shoot' and left <= 0 and c:near('him', 45.0) then
            surrender("Enough! I'm dropping it! Don't shoot!")
        end
    end
end

-- On foot at the door, not stopped: he goes for the resident. Told to stop, half the time they do (once); the taser
-- does; left 60 s with someone watching and the resident is hurt.
local function attack(c)
    local stage, ordered, left = nil, false, 60
    local function stop(line)
        if stage == 'over' then return end
        stage = 'over'
        c:set('fighting_him', false)
        c:done('fight')
        c:task('him', 'surrender')
        if c:who('resident') then c:task('resident', 'scene') end
        if line then c:say('him', line) end
        c:note('The attack at the door was broken up')
    end
    c:on('hail', function(who)
        if stage ~= 'fight' or ordered or (who ~= 'him' and who ~= 'resident') then return end
        ordered = true
        if math.random() < .5 then stop("Alright! I'm done! I'm done!") else c:say('him', "Stay out of it!") end
    end)
    c:on('stunned', function(who) if who == 'him' and stage == 'fight' then stop("Argh! Okay! Okay!") end end)
    c:on('dead', function(who) if who == 'him' or who == 'resident' then stop() end end)
    return function()
        if stage == 'over' then return end
        if not stage then
            stage = 'fight'
            c:reveal('threat')
            c:reveal('fight')
            c:note(('%s attacked the resident at the front door'):format(c:name('him')))
            c:task('him', 'brawl', 'resident')
            c:task('resident', 'brawl', 'him')
            c:set('fighting_him', true)
            c:say('resident', 'Get off me! Help! HELP!')
            return
        end
        if c:near('him', 120.0) then left = left - 1 end
        if left <= 0 then
            stop()
            c:collapse('resident', 'Conscious, dazed. A cut over the eye, bruising to the face and ribs.')
            c:get('hurt')('resident')
        end
    end
end

-- The tick for whichever story brings him: brought at T s after the first unit got there. (stage) -> function(t)
local function comes(c, T, run)
    local quiet = quiet_things(c, T)
    c:on('tick', function(secs)
        local t = clock(c, secs)
        if not t then return end
        quiet(t)
        if T and t >= T and not c:get('dealt') then
            if not c:get('brought') then c:set('brought', true) c:set('t_brought', t) end
            run(t)
        end
    end)
end

local DRIVE_LINES = {
    c_here = cracks(3, { "Driving. Is that illegal now?", "Just passing through. Free country." },
        { { "...Fine. I wanted them to see me. I wanted them to know I'm not going anywhere.", set = { c_admit = 'yes' } } },
        { "I told you what I'm doing." }),
    c_house = { "Never seen it before in my life.", "What house? I'm driving down a road." },
    c_order = { "That's a piece of paper. A judge who's never met me." },
}

Callout({
    id = 'protect',
    name = 'Protection detail',
    tasking = 'protection', -- (a special tasking: asked for on the radio, never put out by dispatch)
    voice = 'call_protect', -- (dispatch's line: lwk_control/tools/make_voice.py)
    alert = 'Special tasking',
    priority = 2,
    weight = 1,
    max_minutes = 40,
    enabled = true,
    reports = {
        'Resident has received credible threats after an incident. Sit on the address until stood down.',
        'Protection detail requested for a resident under threat. Watch the house and the road until relieved.',
        'Credible threat against a resident at this address. Park up, keep eyes on the house, wait to be stood down.',
    },
    -- The points each location needs, in the order /c3rplace protect walks you through them. The first is the scene.
    -- from and to are on the same road as the house, either side of it, so a car driving from one to the other goes past.
    points = {
        { 'house', 'The road outside the house, where a unit would park to sit on it.' },
        { 'resident', 'The resident, on the doorstep.' },
        { 'door', 'The front door, where someone walking up would stop.' },
        { 'from', 'Down the road one way, 150-250 m off and out of sight of the house. Sit in a car pointing at the house.', 'car' },
        { 'to', 'Down the road the other way, as far and out of sight. Sit in a car pointing back at the house.', 'car' },
        { 'kerb', 'Where a car pulls up outside the house, at the kerb a few metres from the door.' },
        { 'approach', 'Round a corner on foot, 80-150 m off and out of sight: where someone walking to the house starts.' },
        { 'watch', 'Parked up the street with a view of the door, 40-100 m off. Sit in a car parked there.', 'car' },
        { 'neighbour', "Next door's front yard.", optional = true },
    },
    -- Add more with /c3rplace protect in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Grove St', at = vector3(118.13, -1945.35, 20.69), points = {
            house = vector4(118.13, -1945.35, 20.69, 84.6),
            resident = vector4(106.35, -1953.22, 20.72, 330.2),
            door = vector4(105.60, -1951.90, 20.72, 330.2),
            from = vector4(205.00, -1880.00, 24.20, 140.0),
            to = vector4(40.00, -2010.00, 18.00, 320.0),
            kerb = vector4(112.40, -1947.80, 20.60, 140.0),
            approach = vector4(160.00, -1990.00, 18.40, 45.0),
            watch = vector4(140.50, -1925.60, 21.00, 140.0),
            neighbour = vector4(118.13, -1945.35, 20.69, 84.6),
        } },
    },

    stories = {
        -- ── Nothing happens. ─────────────────────────────────────────────────────────────────────────────────────
        quiet = {
            weight = 1,
            setup = function(c)
                base(c, { "Not since the day it happened. But he knows where I live. That's what I can't stop thinking about." })
                him(c, { at = 'approach', lines = {} })
                card(c)
                wire(c)
                comes(c, nil)
                resolve(c, '')
            end,
        },

        -- ── He drives past, twice, then comes to the door with a gun. ────────────────────────────────────────────
        drive = {
            weight = 3,
            setup = function(c)
                base(c, { "He drove past last night. Slowly. Twice. He wanted me to see him." })
                local items = { 'Pistol, loaded, in his waistband', "A printout of the resident's address" }
                c:set('items', items)
                him(c, { at = 'to', seated = 'his_car', weapon = 'WEAPON_PISTOL', items = items, runs = math.random() < .35, lines = DRIVE_LINES })
                card(c)
                wire(c)
                local legs, i, moving, told, wait, stage, door = { 'from', 'to', 'kerb' }, 1, false, false, 0, 'drive', armed(c)
                c:on('parked', function(who)
                    if who ~= 'him' or c:get('stopped') then return end
                    moving = false
                    if legs[i] == 'kerb' then
                        stage = 'walk'
                        c:task('him', 'go', 'door')
                    else
                        i, wait = i + 1, math.random(30, 70)
                    end
                end)
                comes(c, math.random(300, 840), function()
                    if c:get('stopped') then return end -- (pulled over, or walked up to: the stop has him)
                    if stage == 'walk' then
                        if (c:distance('him', 'door') or 99) < 4 then stage = 'door' end
                        return
                    end
                    if stage == 'door' then return door() end
                    if moving then
                        if not told and c:near('him', 50.0) then
                            told = true
                            c:reveal('threat')
                            tell(c, legs[i] == 'kerb' and ('A %s pulls up outside the house.'):format(car_words(c:get('car')))
                                or ('A %s rolls past the house, slowly.'):format(car_words(c:get('car'))))
                        end
                        return
                    end
                    if wait > 0 then wait = wait - 1 return end
                    c:bring('him')
                    c:bring('his_car')
                    if c:task('him', 'drive', { car = 'his_car', to = legs[i] }) ~= false then moving, told = true, false end
                end)
                resolve(c, (' in a %s'):format(car_words(c:get('car'))))
            end,
        },

        -- ── He walks up to the door. ─────────────────────────────────────────────────────────────────────────────
        walk = {
            weight = 2,
            setup = function(c)
                base(c, { "This morning. He was across the road when I took the bins out. Just stood there. Then he walked off." })
                local items = { 'Kitchen knife, inside his jacket' }
                c:set('items', items)
                him(c, { at = 'approach', items = items, lines = {
                    c_here = cracks(3, { "Walking. People walk.", "Visiting a friend. Down the road." },
                        { { "...I was going to talk to them. That's all. Just talk.", set = { c_admit = 'yes' } } },
                        { "I said. I wanted to talk." }),
                    c_house = { "Maybe I do. So what?", "Everyone knows everyone round here." },
                    c_order = { "I wasn't going to touch them. I just wanted them to hear me out." },
                } })
                card(c)
                wire(c)
                local stage, told, door = 'out', false, attack(c)
                comes(c, math.random(300, 900), function()
                    if c:get('stopped') then return end
                    if stage == 'out' then
                        c:bring('him')
                        if c:distance('him', 'approach') then stage = 'walking' c:task('him', 'go', 'door') end
                        return
                    end
                    if stage == 'walking' then
                        if not told and c:near('him', 50.0) then
                            told = true
                            c:reveal('threat')
                            tell(c, 'A man on foot is coming up the street, straight for the house.')
                        end
                        if (c:distance('him', 'door') or 99) < 3 then stage = 'door' end
                        return
                    end
                    door()
                end)
                resolve(c, ' on foot')
            end,
        },

        -- ── He's parked up the street, watching. ─────────────────────────────────────────────────────────────────
        watch = {
            weight = 2,
            setup = function(c)
                base(c, { "I don't know. I keep thinking I see his car. Maybe I'm going mad." })
                local items = { 'Photos of the house and the resident, taken from a car', 'Pistol, under the seat' }
                c:set('items', items)
                him(c, { at = 'watch', seated = 'his_car', weapon = 'WEAPON_PISTOL', items = items, runs = math.random() < .5, lines = {
                    c_here = cracks(3, { "Sitting in my car. Waiting for a friend.", "Having a coffee. Is that a crime?" },
                        { { "...I just needed to see them. To see they're alright. That's all.", set = { c_admit = 'yes' } } },
                        { "I told you why." }),
                    c_house = { "Which house? There's a lot of houses.", "Never been here before." },
                    c_order = { "I'm not near them. I'm sat in my own car, on a public road." },
                } })
                c:clue('photos', { on = 'his_car', label = 'His car',
                    text = 'Through the window: photos of the house and of the resident on the passenger seat, a flask of coffee, and wrappers. Someone has been here a while.' })
                card(c)
                wire(c)
                local stage, away = 'out', 0
                comes(c, math.random(120, 600), function()
                    if stage == 'out' then
                        c:set('watching', true)
                        c:bring('him')
                        c:bring('his_car')
                        if c:distance('him', 'watch') then stage = 'sat' end
                        return
                    end
                    if c:get('stopped') then return end
                    if stage == 'sat' then
                        if c:near('him', 35.0) then c:reveal('threat') end
                        if c:near('him', 20.0) and not c:talking('him') then
                            stage = 'seen'
                            if math.random() < .5 and c:task('him', 'drive', { car = 'his_car', fast = true }) ~= false then
                                stage = 'off'
                                c:reveal('threat')
                                tell(c, ('The %s up the street pulls away, fast.'):format(car_words(c:get('car'))))
                                c:note(('%s drove off at speed when approached'):format(c:name('him')))
                            end
                        end
                    elseif stage == 'off' then -- (not caught: once nobody's within 250 m for 30 s, he's gone)
                        away = c:near('him', 250.0) and 0 or away + 1
                        if away >= 30 then stage = 'gone' c:remove('him', 'his_car') end
                    end
                end)
                resolve(c, ' and sat watching it from a car up the street')
            end,
        },
    },
})
