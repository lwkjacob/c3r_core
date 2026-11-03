--[[
    c3r callout: ACTIVE SHOOTER.

    The biggest call in the game. The report is the same every time, and the card is too: the witness, security, the wounded,
    the people hiding, and finding the shooter (everyone's card). What's really going on is one of four stories:
      lone    one gunman with a rifle, moving post to post as units close in
      active  still firing on full auto as units pull up, and people keep going down until someone's on him
      pair    two gunmen, never together: the second opens up once the first is stopped
      fled    he's stopped, left the rifle and sat in his car: go now, or it's a chase, or he's away
      grudge  he came for one person and has a gun on them: talk him down, a gun on him for too long can set him off
    Shots ring out until a unit's on him, and while nobody is, more people go down. He gives up if he's hurt, half the time when
    told to drop it, or after a while with units on him. The wounded bleed: pressure stops it, paramedics finish it.
    It's dealt with when every shooter is taken in, dead or gone and everyone hurt has been seen to, or the witness has been
    heard, the shooting's over and every unit has left. AI backup never fights: alone, an officer is alone.

    Points per location: walk them out in game with /c3rplace shooter (it writes the location in below).
]]

local WITNESS_Q = {
    { id = 'c_what', label = 'What happened?' },
    { id = 'c_see', label = 'What did they look like?' },
    { id = 'c_way', label = 'Which way did they go?' },
    { id = 'c_many', label = 'How many were there?' },
}
local GUARD_Q = {
    { id = 'c_start', label = 'Where did it start?' },
    { id = 'c_see', label = 'Did you see who it was?' },
    { id = 'c_know', label = 'Do you know who it is?' },
    { id = 'c_car', label = 'Did you see how they got here?' },
    { id = 'c_inside', label = 'Is anyone still in there?' },
}
local HIDE_Q = {
    { id = 'c_ok', label = 'Are you hurt?' },
    { id = 'c_saw', label = 'Did you see them?' },
}
local TARGET_Q = {
    { id = 'c_ok', label = 'Are you hurt?' },
    { id = 'c_who', label = 'Do you know him?' },
}
local SHOOTER_Q = {
    { id = 'c_alone', label = 'Is anyone else with you?', stress = true, press = true },
    { id = 'c_why', label = 'Why did you do this?', stress = true, press = true },
}
local HURT = { 'hurt1', 'hurt2', 'hurt3', 'hurt4' }
local HIDE = { 'hide1', 'hide2' }
local CROWD = { 'crowd1', 'crowd2', 'crowd3' }
local OBJ = { shooter = 'stop', shooter2 = 'second' } -- (what each one's objective is)
local RIFLE, SHOTGUN, AUTO = 'WEAPON_CARBINERIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_ASSAULTRIFLE'
local LOOK, WORK = 'a_m_y_skater_01', 's_m_y_construct_01' -- (hood up; a yellow work vest)
local COWER = { 'amb@code_human_cower@male@base', 'base' } -- UNVERIFIED that it reads as hiding (the name's in DurtyFree's dump)
local CLOSE = 45.0 -- m: he's been reached
local AWAY = 400.0 -- m from every unit: got away
local BLEED = { 360, 480 } -- s someone hit has left, from the first unit arriving
local REVIVED = 120 -- s someone brought back has left
local MORE = { 75, 150 } -- s after the scene is made: with nobody on him, someone else goes down

-- Denies it until pressed `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

-- stop = what stopping him means, where it isn't a gunfight.
local function card(c, stop)
    c:objective('witness', 'Talk to the witness', { hint = 'They saw it start.', blip = 'witness' })
    c:objective('guard', 'Talk to security', { hint = 'They know the place.', blip = 'guard' })
    c:objective('wounded', 'Reach the wounded', { hint = 'Are they safe to reach?', blip = HURT })
    c:objective('people', 'Get people out of hiding', { hint = 'They will not come out until someone tells them to.', blip = HIDE })
    c:objective('hunt', 'Find the shooter', { who = 'all', hint = 'Follow the shots. Ask which way they went.' })
    c:objective('stop', stop or 'Stop the shooter', { hidden = true, who = 'all', blip = 'shooter',
        hint = stop and 'Press E beside him, or use the PA. Keep your gun down if you can.' or 'Take cover. He gives up if he has to.' })
    c:objective('second', 'Stop the second shooter', { hidden = true, who = 'all', hint = 'There is more than one of them.' })
    c:objective('car', 'Find the car', { hidden = true, who = 'all', blip = 'car', hint = 'He drove here.' })
    c:objective('scene', 'Check where it started', { hidden = true, blip = 'start' })
    c:objective('medics', 'Get paramedics to the wounded', { hidden = true, who = 'all', blip = HURT, hint = 'Radio for an ambulance once it is safe. You may need more than one.' })
    c:objective('decide', 'Arrest the shooter', { after = { 'stop' }, who = 'all' })
end

-- Someone's hurt: the ending waits for them, and the map shows them.
local function hurt(c, key)
    local list = c:get('hurts') or {}
    list[key] = true
    c:set('hurts', list)
    local keys = {}
    for k in pairs(list) do keys[#keys + 1] = k end
    c:blip('medics', keys)
    if c:is_done('medics') then -- (it can't come back: one of their own, or the ending waits on someone the card doesn't show)
        c:objective('medic:' .. key, ('Call paramedics for %s'):format(c:name(key)), { who = 'all', blip = key, hint = 'Radio for an ambulance. If they pronounce them, the coroner can take them.' })
    end
end

-- Done when: the witness has said what happened, security where it started, someone's reached the wounded, everyone hiding
-- has been reached. The crowd runs as units get close; left alone, someone else goes down.
local function wire(c)
    local ran, spoken, more = false, {}, 1
    local function hiding_done()
        for _, key in ipairs(HIDE) do if c:who(key) and not spoken[key] then return end end
        c:done('people')
    end
    local function saw_to(who)
        spoken[who] = true
        hiding_done()
    end
    c:on('build', function()
        c:set('built', true)
        for _, key in ipairs(HURT) do if c:who(key) then hurt(c, key) end end
        hiding_done() -- (nobody hiding here)
    end)
    local warned = false
    c:on('arrive', function()
        if warned then return end
        warned = true
        c:dispatch('All units: treat this as active. Stop the shooter first, then the wounded.')
    end)
    c:on('act', function(who, action, arg)
        if action ~= 'ask' then return end
        if who == 'witness' and arg == 'c_what' then c:done('witness') end
        if who == 'guard' and arg == 'c_start' then c:done('guard') c:reveal('scene') end
    end)
    c:on('fact', function(_, fact)
        if fact == 'c_way' then c:blip('hunt', 'shooter') end
    end)
    c:on('inspect', function(clue) if clue == 'start' then c:set('start_seen', true) c:done('scene') end end)
    c:on('contact', function(who)
        for _, key in ipairs(HIDE) do if who == key then saw_to(key) end end
    end)
    c:on('contact_ended', function(who, outcome)
        for _, key in ipairs(HIDE) do
            if who == key and (outcome == 'cancelled' or outcome == 'released') then c:task(key, 'go', 'witness') end -- (out to the others)
        end
    end)
    local function lost(who)
        if who == 'witness' then c:done('witness') end
        if who == 'guard' then c:done('guard') end
        for _, key in ipairs(HIDE) do if who == key then saw_to(key) end end
    end
    c:on('dead', lost)
    c:on('gone', lost)
    local clock = 0
    c:on('tick', function()
        if not c:get('built') then return end
        clock = clock + 1
        -- (pinned down where he's still firing: they only run once he turns on the officers)
        if not ran and (c:get('pinned') and c:get('engaged') or (not c:get('pinned') and c:near(nil, 120.0))) then
            ran = true
            for _, key in ipairs(CROWD) do
                if c:who(key) and not spoken[key] then spoken[key] = true c:task(key, 'flee') end
            end
        end
        for key in pairs(c:get('hurts') or {}) do
            if c:near(key, 15.0) then
                c:done('wounded')
                c:reveal('medics')
            end
        end
        local times = c:get('more') or MORE
        if not (times[more] and clock >= times[more]) then return end
        more = more + 1
        if not c:get('rampage') or c:get('engaged') then return end
        local pool = c:get('pinned') and { 'crowd1', 'crowd2', 'crowd3', 'hide1', 'hide2' } or { 'hide1', 'hide2', 'crowd1', 'crowd2', 'crowd3' }
        for _, key in ipairs(pool) do
            if c:who(key) and not spoken[key] and not c:talking(key) and (c:health(key) or 0) > 100 then
                saw_to(key)
                c:collapse(key)
                hurt(c, key)
                c:dispatch('Caller reports another person hit. Units, get in there.')
                return
            end
        end
    end)
end

-- The wounded: the clock runs from the first unit arriving. Pressure stops it, for good; paramedics end it; CPR buys a little more.
local function bleeding(c)
    local left, steady, gone, running = {}, {}, {}, false
    c:on('arrive', function() running = true end)
    c:on('aid', function(who, what)
        if what == 'pressure' or what == 'hospital' or what == 'treated' or what == 'pronounced' then steady[who] = true end
    end)
    c:on('dead', function(who) gone[who] = true end)
    c:on('tick', function()
        if not running then return end
        for key in pairs(c:get('hurts') or {}) do
            left[key] = left[key] or math.random(BLEED[1], BLEED[2])
            if gone[key] then
                if (c:health(key) or 0) > 100 then gone[key], left[key] = nil, REVIVED end -- (CPR: back, for now)
            elseif not steady[key] then
                left[key] = left[key] - 1
                if left[key] <= 0 then
                    c:die(key)
                    left[key] = 5 -- (again, if that game didn't get it: `dead` stops the clock)
                end
            end
        end
    end)
end

--[[ One gunman, weapon out at the first of his posts, firing into the air until a unit's on him (within CLOSE, or a gun on him, or
     telling him to drop it). Then he fights from post to post (one every 30 s). He gives up if he's hurt, after 60-150 s with
     units near, or half the time when told to.
     opts = { gun, quiet (not yet: nothing until wake(), or until a unit's right on him), still (one volley, then he waits for
     the story), spray (a point: bursts at it every 4-6 s, not into the air), on (a person: he holds his gun on them), talked (a line: telling him to drop it always works), after (when he's
     stopped, however) }. -> engage(), give_up(line), wake() ]]
local function gunman(c, key, posts, opts)
    opts = opts or {}
    local obj, route = OBJ[key], {}
    for _, at in ipairs(posts) do if c.inc.loc.points[at] then route[#route + 1] = at end end
    local ready, quiet, engaged, over, aiming = false, opts.quiet, false, false, false
    local clock, volley_at, stage, move_at, left = 0, 0, 1, 0, 0
    local function stopped()
        if over then return end
        over = true
        c:set('over_' .. key, true)
        c:set('engaged', true) -- (however it happened, nobody else goes down)
        c:done('hunt')
        c:reveal('scene')
        c:done(obj)
        if opts.after then opts.after() end
    end
    local function give_up(line)
        if over then return end
        local o = c:who(key)
        o.ran, o.gave_up = true, true -- (he's done: going for the cuffs won't send him running now)
        stopped()
        c:blip('decide', key)
        c:say(key, line)
        c:task(key, 'surrender')
    end
    local function engage()
        if over or engaged then return end
        engaged, quiet, left, move_at = true, false, math.random(60, 150), clock + 30
        c:set('engaged', true)
        c:done('hunt')
        c:reveal(obj)
        c:blip(obj, key)
        c:task(key, 'shoot', route[1])
    end
    local function wake()
        if over or engaged then return end
        quiet, volley_at = false, 0
        c:reveal(obj)
        c:blip(obj, key)
    end
    c:on('build', function()
        ready = true
        c:task(key, 'hold', opts.on)
    end)
    c:on('fired', function(who)
        if who ~= key then return end
        c:dispatch('Shots fired at officers! All units, shots fired!')
        c:note('The shooter fired at officers')
    end)
    c:on('tick', function()
        if not ready or over then return end
        clock = clock + 1
        local health = c:health(key)
        if health and health > 100 and health < 150 then return give_up("Okay! Okay, I'm hit! I'm done! Don't shoot!") end
        if not engaged then
            if opts.on and not aiming and c:health(opts.on) then -- (a point further off than his is made later: then he can aim)
                aiming = true
                c:task(key, 'hold', opts.on)
            end
            if opts.still then
                if volley_at == 0 then volley_at = 1 c:bang(opts.gun or RIFLE, route[1], 3) end
            elseif c:near(key, quiet and 30.0 or CLOSE) then
                engage()
            elseif not quiet and clock >= volley_at and opts.spray then
                volley_at = clock + math.random(4, 6)
                c:task(key, 'spray', opts.spray)
            elseif not quiet and clock >= volley_at then
                volley_at = clock + math.random(15, 25)
                c:bang(opts.gun or RIFLE, route[1], 3)
            end
            return
        end
        left = c:near(key, CLOSE) and left - 1 or left -- (his clock only runs with someone in range)
        if left <= 0 then
            give_up("I'm out! That's it! I'm done, don't shoot! My hands are up!")
        elseif clock >= move_at and route[stage + 1] then
            stage, move_at = stage + 1, clock + 30
            c:task(key, 'shoot', route[stage])
        end
    end)
    c:on('aimed', function(who) if who == key and not opts.still then engage() end end)
    c:on('hail', function(who)
        if who ~= key or over then return end
        if opts.talked then return give_up(opts.talked) end
        engage()
        if math.random() < 0.5 then give_up("Alright! Alright! I'm putting it down!") end
    end)
    c:on('dead', function(who)
        if who ~= key then return end
        stopped()
        c:task(key, 'surrender') -- (paramedics can bring him back: not to carry on fighting)
    end)
    c:on('gone', function(who) if who == key then stopped() end end)
    return engage, give_up, wake
end

--[[ It's over when every shooter (`gunmen`) has been taken in, is gone or has been seen to, and everyone hurt has been seen to; or
     the witness has been heard, the shooting's over and every unit has left. Anyone who dies is a casualty too: the card
     says to call paramedics, and it goes on until they've pronounced them or taken them, or the coroner has.
     ends(out, tally) -> the MDT summary; out[person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' |
     'pronounced' | 'hospital' | 'treated'; out.left = true; tally = { hospital, treated, died }. ]]
local function resolve(c, gunmen, ends)
    local out, taken, away_for, done, hit = {}, {}, 0, false, {}
    local is_gunman = {}
    for _, key in ipairs(gunmen) do is_gunman[key] = true end
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local LET_GO = { released = true, cited = true, warning = true, fled = true, pronounced = true, hospital = true, treated = true }
    local function dealt(key) return not c:who(key) or taken[key] or LET_GO[out[key]] end
    local function all_dealt()
        for _, key in ipairs(gunmen) do if not dealt(key) then return false end end
        return true
    end
    local function tally()
        local t = { hospital = 0, treated = 0, died = 0 }
        for key in pairs(hit) do
            local how = out[key]
            if how == 'hospital' or how == 'treated' then t[how] = t[how] + 1
            elseif how == 'pronounced' or (how == 'dead' and (c:health(key) or 0) <= 100) then t.died = t.died + 1 end
        end
        return t
    end
    local function check()
        if done or not c:get('built') then return end -- (before the scene's made, nobody's there to be dealt with)
        local named = true
        for _, key in ipairs(gunmen) do named = named and (not c:who(key) or out[key] ~= nil) end
        if named then c:done('decide') end
        if waiting() then return end
        if not ((all_dealt() and not next(c:get('hurts') or {})) or out.left) then return end
        done = true
        c:done('decide')
        c:finish(ends(out, tally()))
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
        c:done('medic:' .. who)
        local list = c:get('hurts') or {}
        list[who] = nil
        local keys = {}
        for k in pairs(list) do keys[#keys + 1] = k end
        if keys[1] then c:blip('medics', keys) else c:done('medics') end
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if out[who] == 'dead' then seen_to(who, 'pronounced') end -- (the coroner's been)
        if (c:get('hurts') or {})[who] and out[who] ~= 'pronounced' then seen_to(who, 'hospital') end -- (an ambulance the call didn't hear about)
        if is_gunman[who] and not out[who] then
            out[who] = 'fled'
            c:set('over_' .. who, true)
            for _, id in ipairs({ 'hunt', 'car', OBJ[who] }) do c:done(id) end
        end
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if is_gunman[who] then
            c:set('over_' .. who, true)
            for _, id in ipairs({ 'hunt', 'car', OBJ[who] }) do c:done(id) end
        else
            hit[who] = true
        end
        hurt(c, who)
        c:reveal('medics')
        c:dispatch('Someone is down. Paramedics or the coroner needed at the scene.')
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
    c:on('tick', function() -- (the shooters and the wounded are dealt with in any order: one place to look)
        for key in pairs(c:get('hurts') or {}) do hit[key] = hit[key] or not is_gunman[key] or nil end
        check()
        local here, over = c:near(nil, 80.0) or c:talking(), true
        for key in pairs(c:get('hurts') or {}) do here = here or c:near(key, 80.0) end -- (someone's seeing to them)
        for _, key in ipairs(gunmen) do
            here = here or (not dealt(key) and c:near(key, 100.0))
            over = over and (not c:who(key) or dealt(key) or c:get('over_' .. key))
        end
        if c:is_done('witness') and over and not waiting() and not here then
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
    if how == 'fled' then return (' %s got away.'):format(s) end
    if how == 'dead' and (c:health(who) or 0) > 100 then return (' %s was shot and left at the scene.'):format(s) end -- (CPR can have brought them back)
    if how == 'dead' or how == 'pronounced' then return (' %s was shot and died at the scene.'):format(s) end
    if how == 'hospital' or how == 'treated' then return (' %s was shot and seen by paramedics.'):format(s) end
    if c:get('over_' .. who) then return (' %s gave up and was left at the scene.'):format(s) end
    return ' The shooter was not stopped.'
end

-- What the summary says: what it was, each shooter, then the wounded.
local function report(c, out, t, what)
    local text = ('%s on %s.'):format(what, c:street()) .. part(c, out, 'shooter') .. part(c, out, 'shooter2')
    local list = {}
    if t.hospital > 0 then list[#list + 1] = ('%d taken to hospital'):format(t.hospital) end
    if t.treated > 0 then list[#list + 1] = ('%d treated at the scene'):format(t.treated) end
    if t.died > 0 then list[#list + 1] = ('%d died'):format(t.died) end
    text = text .. (list[1] and (' Wounded: ' .. table.concat(list, ', ') .. '.') or ' Nobody hurt was seen to by paramedics.')
    local on = {}
    for _, key in ipairs({ 'shooter', 'shooter2' }) do
        local o = c:who(key)
        if o and o.facts.found then on[#on + 1] = ('what was found on %s'):format(c:name(key)) end
        if o and o.facts.c_admit then on[#on + 1] = ("%s's admission"):format(c:name(key)) end
    end
    if c:get('start_seen') then on[#on + 1] = 'where it started' end
    return text .. (on[1] and (' Recorded: ' .. table.concat(on, ', ') .. '.') or '')
end

-- Everyone but the shooter: who saw it, the wounded, the runners, who's hiding, and where it began.
local function people(c, witness, guard, start)
    witness.where = witness.where or { "Here. I was just here. Then everyone was running." }
    guard.where = guard.where or { "On my post. Where else?" }
    c:person('witness', { at = 'witness', label = 'Witness', age = { 19, 60 }, secret = 'clean', demeanor = 'nervous',
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = WITNESS_Q, lines = witness })
    c:person('guard', { at = 'guard', label = 'Security guard', male = true, model = 's_m_m_security_01', age = { 30, 60 }, secret = 'clean', demeanor = 'polite',
        scene = 'WORLD_HUMAN_STAND_MOBILE', questions = GUARD_Q, lines = guard })
    for _, key in ipairs(HURT) do
        c:person(key, { at = key, label = 'Wounded person', age = { 19, 64 }, secret = 'clean', injured = true })
    end
    for _, key in ipairs(CROWD) do
        c:person(key, { at = key, label = 'Person', age = { 19, 64 }, secret = 'clean', scene = 'WORLD_HUMAN_STAND_IMPATIENT' })
    end
    for _, key in ipairs(HIDE) do
        c:person(key, { at = key, label = 'Person hiding', age = { 19, 64 }, secret = 'clean', demeanor = 'nervous', scene = COWER, questions = HIDE_Q, lines = {
            c_ok = { "No. I don't think so. Is it over?" },
            c_saw = { "I just heard it. I got down and I stayed down." },
            where = { "Here. Right here, the whole time." },
        } })
    end
    start.at, start.label = 'start', start.label or 'Casings'
    c:clue('start', start)
end

-- The man himself. spec: at, model, gun (what he fires), items
local function shooter(c, key, spec, lines)
    lines.where = lines.where or { "You know where I was." }
    lines.c_why = lines.c_why or { "I'm not saying anything." }
    c:person(key, { at = spec.at, label = 'Shooter', male = true, model = spec.model or LOOK, age = { 24, 45 }, secret = 'clean', demeanor = 'rude',
        weapon = spec.gun, items = spec.items, runs = spec.runs, bail = spec.bail, seated = spec.seated,
        questions = SHOOTER_Q, lines = lines })
end

Callout({
    id = 'shooter',
    name = 'Active shooter',
    voice = 'call_shooter', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    weight = 0.5,
    enabled = true,
    reports = {
        'Multiple callers reporting shots fired and people running.',
        'Several 911 calls: gunfire and a crowd scattering. People reported down.',
        'Shots fired in a crowded area. Injured reported. No description yet.',
    },
    -- The points each location needs, in the order /c3rplace shooter walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it): the edge of it, where people have run to.
    -- Keep the wounded within 40 m of each other (paramedics work 40 m around the officer who calls them), and everything within
    -- about 250 m. Skip the optional ones with Z in /c3rplace: without post3 there's no second shooter, without target no
    -- grudge, without car nobody drives off.
    points = {
        { 'witness', 'The witness, at the edge of the scene, where people have run to.' },
        { 'guard', 'A security guard, in a doorway or at a post near the edge of the scene.' },
        { 'start', 'Where it started: on the ground, in the middle of it.' },
        { 'hurt1', 'Someone wounded, on the ground near where it started.' },
        { 'hurt2', 'Someone else wounded, within 20 m of the first.' },
        { 'hurt3', 'A third wounded person, within 20 m of the first.' },
        { 'hurt4', 'A fourth wounded person, within 30 m of the first.', optional = true },
        { 'post1', 'The shooter, 30 to 60 m past where it started, with a clear view.' },
        { 'post2', 'Where he falls back to, about 30 m from there, behind cover.' },
        { 'post3', 'A third spot, 100 m or more away, for a second shooter (or his last stand).', optional = true },
        { 'target', 'Someone held at gunpoint: 3 m from the second spot, facing it.', optional = true },
        { 'hide1', 'Someone hiding, behind cover: they stay there until told to come out.', optional = true },
        { 'hide2', 'Someone else hiding, somewhere else.', optional = true },
        { 'crowd1', 'Someone who runs when units get close.', optional = true },
        { 'crowd2', 'Someone else who runs.', optional = true },
        { 'crowd3', 'A third who runs.', optional = true },
        { 'car', "The shooter's car, within 250 m, on a road. Sit in a car parked there.", 'car', optional = true },
    },
    -- Add more with /c3rplace shooter in game (it writes them here): the college, the courthouse. This one is a rough placeholder
    locations = {
        { street = 'Legion Square', at = vector3(190.0, -880.0, 30.7), points = {
            witness = vector4(190.0, -880.0, 30.7, 180.0),
            guard = vector4(172.0, -900.0, 30.7, 200.0),
            start = vector4(195.0, -935.0, 30.7, 0.0),
            hurt1 = vector4(190.0, -938.0, 30.7, 40.0),
            hurt2 = vector4(201.0, -931.0, 30.7, 120.0),
            hurt3 = vector4(186.0, -928.0, 30.7, 260.0),
            hurt4 = vector4(206.0, -945.0, 30.7, 300.0),
            post1 = vector4(185.0, -965.0, 30.7, 340.0),
            post2 = vector4(165.0, -985.0, 30.7, 20.0),
            post3 = vector4(240.0, -985.0, 30.7, 70.0),
            target = vector4(168.0, -987.0, 30.7, 240.0),
            hide1 = vector4(215.0, -925.0, 30.7, 90.0),
            hide2 = vector4(160.0, -940.0, 30.7, 270.0),
            crowd1 = vector4(200.0, -910.0, 30.7, 0.0),
            crowd2 = vector4(180.0, -915.0, 30.7, 0.0),
            crowd3 = vector4(210.0, -900.0, 30.7, 0.0),
            car = vector4(222.0, -803.0, 30.6, 250.0),
        } },
        { street = 'Richman St', at = vector3(-1698.97, 212.91, 62.39), streets = { start = 'Picture Perfect Drive', hurt1 = 'Picture Perfect Drive', hurt2 = 'Picture Perfect Drive', hurt3 = 'Picture Perfect Drive', hurt4 = 'Picture Perfect Drive', post3 = 'North Rockford Dr', target = 'North Rockford Dr' }, points = {
            witness = vector4(-1698.97, 212.91, 62.39, 205.2),
            guard = vector4(-1722.01, 206.85, 63.96, 113.5),
            start = vector4(-1733.78, 153.58, 64.37, 346.0),
            hurt1 = vector4(-1734.76, 162.66, 64.37, 339.9),
            hurt2 = vector4(-1728.34, 165.38, 64.37, 283.2),
            hurt3 = vector4(-1724.65, 166.81, 64.37, 301.2),
            hurt4 = vector4(-1721.15, 165.38, 64.37, 189.9),
            post1 = vector4(-1789.24, 174.20, 64.41, 266.7),
            post2 = vector4(-1795.73, 152.87, 68.77, 270.7),
            post3 = vector4(-1777.37, 124.41, 68.78, 285.2),
            target = vector4(-1775.20, 121.48, 68.78, 219.9),
        } },
        { street = 'Autopia Pkwy', at = vector3(-253.71, -1844.19, 28.54), streets = { post1 = 'Davis Ave' }, points = {
            witness = vector4(-253.71, -1844.19, 28.54, 324.9),
            guard = vector4(-247.61, -1894.63, 27.76, 148.6),
            start = vector4(-256.03, -1893.84, 27.76, 79.9),
            hurt1 = vector4(-261.56, -1892.21, 27.76, 57.6),
            hurt2 = vector4(-265.55, -1892.47, 27.76, 175.3),
            hurt3 = vector4(-262.39, -1898.36, 27.76, 215.7),
            hurt4 = vector4(-259.31, -1902.73, 27.76, 191.9),
            post1 = vector4(-285.92, -1915.50, 29.95, 309.4),
            post2 = vector4(-262.53, -1934.92, 29.95, 14.1),
            post3 = vector4(-235.53, -1983.45, 29.95, 207.8),
            target = vector4(-235.05, -1988.95, 29.95, 165.8),
        } },
    },

    stories = {
        -- ── One man, moving. ─────────────────────────────────────────────────────────────────────────────────────
        lone = {
            weight = 3,
            setup = function(c)
                c:set('rampage', true)
                people(c, {
                    c_what = { "Bangs. Then everyone was running. There are people on the ground back there." },
                    c_see = { "One man. Hood up, a rifle. He wasn't in any hurry." },
                    c_way = { { "That way. He keeps moving. Listen for it.", set = { c_way = 'pointed' } } },
                    c_many = { "One. I only saw the one." },
                }, {
                    c_start = { "In the middle of it, back there. There are casings all over the ground." },
                    c_see = { "A hood and a rifle. That's all I saw." },
                    c_know = { "No. I've never seen him before." },
                    c_car = { "No. He was just there." },
                    c_inside = { "There are people hiding. They won't come out for me." },
                }, { prop = 'prop_sgun_casing', text = 'Rifle casings across the ground, all the same make. One gun.' })
                shooter(c, 'shooter', { at = 'post1', gun = RIFLE, items = { 'Rifle, nearly empty', 'Spare magazines' } }, {
                    c_alone = { "Just me." },
                })
                card(c)
                wire(c)
                bleeding(c)
                gunman(c, 'shooter', { 'post1', 'post2', 'post3' }, { gun = RIFLE })
                resolve(c, { 'shooter' }, function(out, t) return report(c, out, t, 'Active shooter') end)
            end,
        },

        -- ── Still firing. ───────────────────────────────────────────────────────────────────────────────────────
        active = {
            weight = 3,
            setup = function(c)
                c:set('rampage', true)
                c:set('pinned', true)
                c:set('more', { 10, 22, 34, 46 })
                people(c, {
                    c_what = { "He's still shooting! Can you not hear it? He's firing at anyone who moves!" },
                    c_see = { "One man. Hood up. A rifle, the kind that doesn't stop." },
                    c_way = { { "He's right there! Listen! Follow the noise!", set = { c_way = 'pointed' } } },
                    c_many = { "One. One's enough." },
                }, {
                    c_start = { "Out in the open, back there. People are lying down out there, they can't get out." },
                    c_see = { "A hood and a rifle. He just walked in and started." },
                    c_know = { "No. I've never seen him before." },
                    c_car = { "No. He was just there." },
                    c_inside = { "There are people out there pinned down. They won't move while he's firing." },
                }, { prop = 'prop_sgun_casing', scatter = { model = 'prop_sgun_casing', count = 10, radius = 3.0 },
                     text = 'Casings everywhere, more than anyone could count, all the same make. One gun, fired until it was empty, and again.' })
                shooter(c, 'shooter', { at = 'post1', gun = AUTO, items = { 'Automatic rifle', 'Spare magazines' } }, {
                    c_alone = { "Just me." },
                })
                card(c)
                wire(c)
                bleeding(c)
                c:on('build', function()
                    c:dispatch('All units: callers say he is still firing. Shooting is ongoing.')
                    for _, key in ipairs(CROWD) do c:task(key, 'surrender') end -- (pinned down, hands over their heads)
                end)
                gunman(c, 'shooter', { 'post1', 'post2', 'post3' }, { gun = AUTO, spray = 'start' })
                resolve(c, { 'shooter' }, function(out, t) return report(c, out, t, 'Active shooter, still firing as units arrived') end)
            end,
        },

        -- ── Two of them. ─────────────────────────────────────────────────────────────────────────────────────────
        pair = {
            weight = 2,
            needs = { 'post3' },
            setup = function(c)
                c:set('rampage', true)
                local heard = 0
                people(c, {
                    c_what = { "Bangs, from over there, and then more from somewhere else. I don't know. Everyone just ran." },
                    c_see = { { "A man with his hood up, with a rifle.", set = { c_seen = 'yes' } } },
                    c_way = { { "That way. Listen for it.", set = { c_way = 'pointed' } } },
                    c_many = { "I saw one. It didn't sound like one." },
                }, {
                    c_start = { "Back there. There are shells all over the ground." },
                    c_see = { { "A man in a yellow work vest, with a shotgun. I thought he was a contractor.", set = { c_seen = 'yes' } } },
                    c_know = { "No. I've never seen him before." },
                    c_car = { "No. I don't know how he got in." },
                    c_inside = { "There are people hiding. They won't come out for me." },
                }, { prop = 'prop_sgun_casing', text = 'Rifle casings here, and a few metres off, red shotgun shells. Two different guns.' })
                shooter(c, 'shooter', { at = 'post1', gun = RIFLE, items = { 'Rifle, nearly empty', 'A phone, one number in it' } }, {
                    c_alone = cracks(2, { "Just me." },
                        { { "...Keep listening. You're not done.", set = { c_admit = 'yes', c_two = 'yes' } } },
                        { "I told you. Keep listening." }),
                })
                shooter(c, 'shooter2', { at = 'post3', model = WORK, gun = SHOTGUN, items = { 'Pump shotgun', 'A phone, one number in it' } }, {
                    c_alone = { "You've got him, then. Good for you." },
                })
                card(c)
                wire(c)
                bleeding(c)
                local function second() c:reveal('second') end
                c:on('fact', function(who, fact)
                    if fact == 'c_two' then second() end
                    if fact == 'c_seen' then
                        heard = heard + 1
                        if heard >= 2 then second() end -- (two descriptions: two men)
                    end
                end)
                c:on('inspect', function(clue) if clue == 'start' then second() end end)
                local _, _, wake = gunman(c, 'shooter2', { 'post3' }, { gun = SHOTGUN, quiet = true })
                gunman(c, 'shooter', { 'post1', 'post2' }, { gun = RIFLE, after = function()
                    if c:get('over_shooter2') then return end
                    wake()
                    c:dispatch('More shots! Callers say there is a second shooter. Man in a yellow work vest. All units!')
                end })
                resolve(c, { 'shooter', 'shooter2' }, function(out, t) return report(c, out, t, 'Two active shooters') end)
            end,
        },

        -- ── He's stopped, and he's leaving. ──────────────────────────────────────────────────────────────────────
        fled = {
            weight = 2,
            needs = { 'car' },
            setup = function(c)
                people(c, {
                    c_what = { "Bangs, a lot of them. Then it just stopped. That was almost worse." },
                    c_see = { "One man, hood up. He put something down and walked away. He walked." },
                    c_way = { { "That way, towards the road. Like nothing had happened.", set = { c_way = 'pointed' } } },
                    c_many = { "One. I only saw the one." },
                }, {
                    c_start = { "Back there. He left the gun on the ground. I saw him do it." },
                    c_see = { "A hood. He walked right past me. He didn't even look." },
                    c_know = { "No. I've never seen him before." },
                    c_car = function()
                        local plate = c:plate('car') or ''
                        return { { ("He got in a dark blue Albany Primo, out on the road. I got the end of the plate: %s."):format(plate:sub(-3)), set = { c_car = 'seen' } } }
                    end,
                    c_inside = { "There are people hiding. They won't come out for me." },
                }, { prop = 'w_ar_carbinerifle', label = 'A rifle', text = 'A rifle, left on the ground, still warm, and casings all around it. Whoever had this stopped and walked away. They have a way out.' })
                c:vehicle('car', { at = 'car', model = 'primo', make = 'Albany', name = 'Primo', color = 'Dark blue', paint = 62, owner = 'shooter', locked = false, label = 'His car' })
                c:clue('stash', { on = 'car', label = 'His car', hidden = true, text = 'An empty rifle case across the back seat, and a change of clothes.' })
                shooter(c, 'shooter', { at = 'car', seated = 'car', runs = true, bail = 0.5, items = { 'Pistol, loaded' } }, {
                    c_alone = { "Get me a lawyer." },
                })
                card(c)
                wire(c)
                bleeding(c)
                local clock, arrived, driving, clear, seen = 0, nil, false, false, false
                local function found()
                    if seen then return end
                    seen = true
                    c:done('hunt')
                    c:reveal('car')
                    c:reveal('stop')
                end
                c:on('build', function() c:bang(RIFLE, 'post1', 3) end)
                c:on('arrive', function() arrived = arrived or clock end)
                c:on('fact', function(_, fact) if fact == 'c_car' then found() end end)
                c:on('inspect', function(clue) if clue == 'start' then found() end end)
                c:on('contact', function(who)
                    if who ~= 'shooter' then return end
                    found()
                    c:set('over_shooter', true)
                    c:done('car')
                    c:done('stop')
                    c:reveal('stash')
                    c:blip('decide', 'shooter')
                end)
                c:on('tick', function()
                    clock = clock + 1
                    local o = c:who('shooter')
                    if not c:get('built') or not o or o.cuffed or c:get('over_shooter') then return end
                    if not driving and (c:near('shooter', 60.0) or (arrived and clock - arrived >= 120)) then
                        if c:task('shooter', 'drive', { car = 'car', fast = true }) ~= false then
                            driving, clear = true, true
                            found()
                            c:dispatch('Caller reports a car leaving the scene at speed. Dark blue Primo.')
                        end
                    elseif clear and not c:talking('shooter') and not c:near('shooter', AWAY) then
                        clear = false
                        c:dispatch('The vehicle has been lost. BOLO is out.')
                        c:remove('shooter', 'car')
                    end
                end)
                resolve(c, { 'shooter' }, function(out, t)
                    local text = report(c, out, t, 'Active shooter, left the scene by car')
                    if out.shooter == 'fled' then text = text .. (' Last seen in a dark blue Albany Primo, plate %s.'):format(c:plate('car') or '?') end
                    return text
                end)
            end,
        },

        -- ── He came for one person. ──────────────────────────────────────────────────────────────────────────────
        grudge = {
            weight = 2,
            needs = { 'target' },
            setup = function(c)
                people(c, {
                    c_what = { "He was shouting a name. Then the shooting started. Everyone in the way just... I don't know why." },
                    c_see = { "One man, hood up. He had someone by the arm." },
                    c_way = { { "That way. He made them go with him.", set = { c_way = 'pointed' } } },
                    c_many = { "One. And whoever he's got." },
                }, {
                    c_start = { "Back there. It was over in a minute. Then he stopped." },
                    c_see = { "I know that walk. I know who that is." },
                    c_know = { { "He used to work here. They let him go last month. He came back for the one who did it.", set = { c_after = 'yes' } } },
                    c_car = { "He's got one somewhere. It doesn't matter. He's not planning on leaving." },
                    c_inside = { "There are people hiding. They won't come out for me." },
                }, { prop = 'prop_sgun_casing', text = 'A few casings, no more than that, and a staff lanyard on the ground with the photo scratched out.' })
                c:person('target', { at = 'target', label = 'Person held', age = { 34, 60 }, secret = 'clean', demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = TARGET_Q, lines = {
                    c_ok = { "No. No, he didn't... I'm not hurt." },
                    c_who = { "He worked for me. I let him go. I told him myself. I never thought..." },
                    where = { "Here. He walked me out here." },
                } })
                shooter(c, 'shooter', { at = 'post2', gun = 'WEAPON_PISTOL', items = { 'Pistol, loaded', 'A letter of dismissal, folded small' } }, {
                    c_alone = { "It was only ever about one person." },
                    c_why = cracks(2, { "Ask them." },
                        { { "They took everything I had. The rest of them were just... in the way.", set = { c_admit = 'yes' } } },
                        { "I said what I said." }),
                })
                card(c, 'Get the gun off him')
                wire(c)
                bleeding(c)
                local engage, give_up = gunman(c, 'shooter', { 'post2' }, { gun = 'WEAPON_PISTOL', still = true, on = 'target',
                    talked = "...Okay. Okay. It's down. Tell them I'm putting it down.",
                    after = function() c:task('target', 'go', 'witness') end })
                c:on('build', function() c:task('target', 'surrender') end)
                local function near() c:done('hunt') c:reveal('stop') end
                c:on('fact', function(_, fact) if fact == 'c_after' then c:blip('hunt', 'shooter') end end)
                -- A gun on him: a warning. Still on him 15 s later (long enough to use the PA, which needs it), or put back on him
                -- after that: it may go wrong, once.
                local clock, warned_at, settled = 0, nil, false
                c:on('tick', function()
                    clock = clock + 1
                    if c:get('built') and c:near('shooter', 25.0) then near() end
                end)
                c:on('aimed', function(who)
                    if who ~= 'shooter' or settled or c:get('over_shooter') then return end
                    near()
                    if not warned_at then
                        warned_at = clock
                        return c:say('shooter', "Don't! Don't point that at me! You don't know what they did!")
                    end
                    if clock - warned_at < 15 then return end
                    settled = true
                    if math.random() < 0.3 then
                        engage()
                        c:task('target', 'flee')
                    else
                        give_up("All right! All right! Don't shoot! It's down!")
                    end
                end)
                resolve(c, { 'shooter' }, function(out, t)
                    local text = report(c, out, t, 'A gunman who came for one person')
                    if not out.target and (c:health('target') or 0) > 150 then text = text .. (' %s, the person he held, was not hurt.'):format(c:name('target')) end
                    return text
                end)
            end,
        },
    },
})
