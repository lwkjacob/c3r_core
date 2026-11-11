--[[
    c3r special tasking: EVENT SECURITY, a political rally. Asked for on the radio ("requesting event security"), never put
    out; other units can join ("units needed").

    A speaker on the stage, a crowd of about 30 who come and go, and a steward from event security who calls things in.
    For about 20 minutes, 3 or 4 small things happen and get flagged: a drunk, a pickpocket (the victim says which way),
    a scuffle at the food stall, a lost teenager with a parent looking for them. The card is the same every time: check in
    with the steward, keep an eye on the stage, walk the crowd. What else happens is one of three stories:
      routine  just the small things
      rusher   a tip about a man at the front barrier shouting that he's getting up there; a few minutes later, if nobody's
               stopped him, he goes for the speaker
      gun      a tip about a man by the press area with a gun in his waistband (he's the only one standing there). Walked up
               to: he goes quietly, or runs, or draws on the speaker and the crowd scatters; he can be talked down
    Tips go by where someone is, never what they look like: nobody else in the crowd fits them. It's over when the rally
    ends (19-21 minutes in) and everything that happened has been dealt with.

    Points per location: walk them out in game with /c3rplace rally (it writes the location in below).
]]

local STEWARD_Q = {
    { id = 'c_what', label = 'Anything I should know about?' },
    { id = 'c_size', label = 'How many are you expecting?' },
}
local DRUNK_Q = {
    { id = 'c_ok', label = 'Had a few?' },
    { id = 'c_home', label = 'How are you getting home?' },
}
local MARK_Q = {
    { id = 'c_what', label = 'What happened?' },
    { id = 'c_way', label = 'Which way did he go?' },
}
local THIEF_Q = { { id = 'c_wallets', label = 'Whose wallets are these?', needs = { found = true }, stress = true, press = true } }
local SCUFFLE_Q = { { id = 'c_start', label = 'What started this?' } }
local KID_Q = { { id = 'c_lost', label = 'Are you lost?' } }
local PARENT_Q = {
    { id = 'c_where', label = 'Where did you last see him?' },
    { id = 'c_age', label = 'How old is he?' },
}
local RUSHER_Q = { { id = 'c_stage', label = 'What are you shouting about?', stress = true } }
local GUNMAN_Q = { { id = 'c_gun', label = 'Are you carrying anything?', stress = true, press = true } }

local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

-- A spot `m` metres in front of a point (its heading), facing back at it: someone beside someone else.
local function beside(c, at, m)
    local p = c:point(at)
    local h = math.rad(p.w)
    return vector4(p.x - math.sin(h) * m, p.y + math.cos(h) * m, p.z, (p.w + 180.0) % 360.0)
end

local function card(c)
    c:objective('steward', 'Check in with event security', { hint = 'The steward will know what is going on.', blip = 'steward' })
    c:objective('stage', 'Keep an eye on the stage', { hint = 'Stand near the front for a while.', blip = 'speaker' })
    c:objective('patrol', 'Walk the crowd until the rally ends', { who = 'all', hint = 'Event security will call things in.' })
    c:objective('drunk', 'Deal with the drunk shouting at people', { hidden = true, who = 'all', blip = 'drunk' })
    c:objective('pick', 'Find the pickpocket', { hidden = true, who = 'all', blip = 'mark', hint = 'Ask the victim which way he went.' })
    c:objective('scuffle', 'Break up the scuffle at the food stall', { hidden = true, who = 'all', blip = 'brawl1' })
    c:objective('kid', 'Find the lost teenager and get him back to his parent', { hidden = true, who = 'all', blip = 'parent' })
    c:objective('rusher', 'Deal with the man at the front barrier', { hidden = true, who = 'all', blip = 'rusher' })
    c:objective('gun', 'Find the man by the press area: reported armed', { hidden = true, who = 'all', blip = 'gunman',
        hint = 'He is the only one standing there. Go carefully.' })
    c:objective('armed', 'Stop him: he has a gun on the speaker', { hidden = true, who = 'all', blip = 'gunman',
        hint = 'Tell him to drop it.' })
end

-- ─── the small things ──────────────────────────────────────────────────────────

--[[ Each one: people (later = true), then start() when it's time (brought, flagged), tick() each second, and done() -> a
     line for the summary once it's dealt with. A shared outcome table (out[person]) is kept by resolve(). ]]

local function drunk(c, out)
    c:person('drunk', { at = 'drunk', later = true, label = 'Man', male = true, secret = 'drunk', demeanor = 'rude',
        scene = 'WORLD_HUMAN_DRINKING', questions = DRUNK_Q, lines = {
            c_ok = { "A few! It's a party! Democracy, officer!", "Not enough to listen to him." },
            c_home = { { "Home? I'll walk. Or get a cab. A cab. Can you get me a cab?", set = { c_ride = 'yes' } } },
        } })
    local shout = 0
    c:on('act', function(who, action, arg)
        if who == 'drunk' and action == 'ask' and arg == 'c_home' then c:fare('drunk') c:set('drunk_fare', true) end
    end)
    c:on('service', function(kind) if kind == 'taxi' and c:get('drunk_on') and out.drunk ~= 'arrested' then out.drunk = 'taxi' end end)
    return { ids = { 'drunk' },
        start = function()
            c:bring('drunk')
            c:set('drunk_on', true)
            c:reveal('drunk')
            c:dispatch('Event security: a man near the drinks is drunk and shouting at people. Can a unit take a look?')
        end,
        tick = function()
            shout = shout + 1
            if shout % 25 == 0 and not c:talking('drunk') and not out.drunk then c:say('drunk', "Liar! LIAR! Get off the stage!") end
        end,
        done = function()
            local v = out.drunk
            if v == 'taxi' then return 'a drunk man was put in a taxi home' end
            if v == 'arrested' then return out.drunk_taken and 'a drunk man was arrested' end
            if v == 'cited' or v == 'warning' then return ('a drunk man was given %s'):format(v == 'cited' and 'a ticket' or 'a warning') end
            if v == 'released' and not c:get('drunk_fare') then return 'a drunk man was spoken to and moved on' end
            if v == 'fled' or v == 'gone' then return 'a drunk man wandered off' end
            if v == 'hospital' then return 'a drunk man was taken to hospital' end
            if v == 'pronounced' then return 'a drunk man died at the scene' end
        end,
        left = 'a drunk man wandered off before he was dealt with', people = { 'drunk' },
    }
end

local function pickpocket(c, out)
    c:person('mark', { at = 'mark', later = true, label = 'Victim', secret = 'clean', demeanor = 'nervous',
        scene = 'WORLD_HUMAN_STAND_MOBILE', questions = MARK_Q, lines = {
            c_what = { "Someone bumped into me, said sorry, and two minutes later my wallet's gone. I didn't even feel it." },
            c_way = { { "He was heading for the way out, the far gate. He was walking fast.", set = { c_way = 'gate' } } },
        } })
    c:person('thief', { at = beside(c, 'mark', 2.0), later = true, label = 'Man', male = true, secret = 'nervous', demeanor = 'polite',
        items = { 'Three wallets, none of them his' }, questions = THIEF_Q, lines = {
            c_wallets = cracks(2, { "Found them. I was going to hand them in." },
                { { "...Alright. It's a crowd. They make it easy.", set = { c_admit = 'yes' } } }, { "I said what I said." }),
        } })
    local stage = nil
    c:on('fact', function(who, fact) if who == 'mark' and fact == 'c_way' then c:blip('pick', 'thief') end end)
    c:on('contact', function(who) if who == 'thief' then c:blip('pick', 'thief') end end)
    return { ids = { 'pick' },
        start = function()
            c:bring('mark')
            c:bring('thief')
            stage = 'on'
            c:reveal('pick')
            c:dispatch("Event security: someone's had their wallet lifted in the crowd. The victim's waiting for a unit.")
        end,
        tick = function()
            if stage == 'on' and c:health('thief') and c:health('mark') then
                stage = 'going'
                c:task('thief', 'go', 'gate2')
                c:say('mark', "My wallet! Someone's had my wallet!")
            elseif stage == 'going' and not out.thief and (c:distance('thief', 'gate2') or 99) < 5 and not c:near('thief', 30.0) and not c:talking('thief') then
                stage = 'away'
                c:remove('thief')
            end
        end,
        done = function()
            local v = out.thief
            if v == 'arrested' then return out.thief_taken and 'a pickpocket was arrested with three wallets' end
            if v == 'cited' or v == 'warning' or v == 'released' then return 'a man with three wallets was spoken to and let go' end
            if v == 'fled' or v == 'gone' then return 'a pickpocket got away through the crowd' end
            if v == 'hospital' or v == 'pronounced' then return 'a pickpocket was taken away by paramedics' end
        end,
        left = 'a pickpocket was not found', people = { 'thief' },
    }
end

local function scuffle(c, out)
    local function one(key, at, line)
        c:person(key, { at = at, later = true, label = 'Man', male = true, secret = math.random() < .5 and 'drunk' or 'clean', demeanor = 'rude',
            questions = SCUFFLE_Q, lines = { c_start = { line } } })
    end
    one('brawl1', 'stall', "He pushed in! Thirty minutes I've waited for a hot dog!")
    one('brawl2', beside(c, 'stall', 1.5), "He called the speaker a crook. I'm not having that.")
    local stage, ordered, left = nil, false, 90
    local function stop()
        if stage == 'stopped' then return end
        stage = 'stopped'
        c:task('brawl1', 'surrender')
        c:task('brawl2', 'surrender')
        c:say('brawl1', "Alright! Alright, it's done!")
    end
    c:on('hail', function(who)
        if stage ~= 'fight' or ordered or (who ~= 'brawl1' and who ~= 'brawl2') then return end
        ordered = true
        if math.random() < .5 then stop() else c:say('brawl2', "He started it!") end
    end)
    c:on('stunned', function(who) if who == 'brawl1' or who == 'brawl2' then stop() end end)
    c:on('dead', function(who) if who == 'brawl1' or who == 'brawl2' then stop() end end)
    return { ids = { 'scuffle' },
        start = function()
            c:bring('brawl1')
            c:bring('brawl2')
            stage = 'coming'
            c:reveal('scuffle')
            c:dispatch('Event security: fight at the food stall. Two men. Units needed.')
        end,
        tick = function()
            if stage == 'coming' and c:health('brawl1') and c:health('brawl2') then
                stage = 'fight'
                c:task('brawl1', 'brawl', 'brawl2')
                c:task('brawl2', 'brawl', 'brawl1')
            elseif stage == 'fight' then
                if c:near('brawl1', 120.0) then left = left - 1 end
                if left <= 0 then stop() c:note('The fight at the food stall burned itself out') end
            end
        end,
        done = function()
            if stage ~= 'stopped' then return end
            local a, b = out.brawl1, out.brawl2
            if not (a or b) then return end -- (stopped, and nobody's spoken to either yet)
            for _, k in ipairs({ 'brawl1', 'brawl2' }) do if out[k] == 'arrested' and not out[k .. '_taken'] then return end end
            local n = (a == 'arrested' and 1 or 0) + (b == 'arrested' and 1 or 0)
            if n > 0 then return ('a fight at the food stall was broken up: %d arrested'):format(n) end
            return 'a fight at the food stall was broken up and both men spoken to'
        end,
        left = 'a fight at the food stall broke up and both men left', people = { 'brawl1', 'brawl2' },
    }
end

local function lost(c, out)
    local parent_male = math.random() < .5
    c:person('parent', { at = 'parent', later = true, label = parent_male and 'Father' or 'Mother', male = parent_male, secret = 'clean',
        demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = PARENT_Q, lines = {
            c_where = { { "By the food stall, then the crowd moved and he was gone. He'll be somewhere he can see the way out, he always does that.", set = { c_where = 'yes' } } },
            c_age = { "Fourteen. He's got my number but his phone's dead. Please." },
        } })
    c:person('kid', { at = 'kid', later = true, label = 'Teenager', male = true, model = 'a_m_y_skater_01', age = { 14, 14 }, secret = 'clean',
        demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = KID_Q, lines = {
            c_lost = { { "I can't find my " .. (parent_male and 'dad' or 'mum') .. ". My phone's dead. Can you take me to them?", set = { c_found = 'yes' } } },
        } })
    local stage = nil
    c:on('fact', function(who, fact)
        if who == 'parent' and fact == 'c_where' then c:blip('kid', 'kid') end
        if who == 'kid' and fact == 'c_found' and stage == 'on' then stage = 'found' end
    end)
    return { ids = { 'kid' },
        start = function()
            c:bring('parent')
            c:bring('kid')
            stage = 'on'
            c:reveal('kid')
            c:dispatch('Event security: a parent has lost their son in the crowd. Fourteen years old. They are at the info point.')
        end,
        tick = function()
            if stage == 'found' then -- (a moment after he's said it: off to them, the officer with him)
                stage = 'going'
                c:blip('kid', 'parent')
                c:hangup('kid')
                c:task('kid', 'go', 'parent')
            elseif stage == 'going' and (c:distance('kid', 'parent') or 99) < 4 then
                stage = 'home'
                out.kid = 'home'
                c:say('parent', 'Oh thank God. Thank you. Thank you.')
            end
        end,
        done = function()
            if out.kid == 'home' then return 'a lost teenager was taken back to his parent' end
            if out.kid then return 'a lost teenager was seen to' end
        end,
        left = 'a lost teenager found his own way back', people = { 'kid' },
    }
end

-- ─── the big things ────────────────────────────────────────────────────────────

local function rusher(c, out)
    c:person('rusher', { at = 'barrier', later = true, label = 'Man', male = true, secret = 'nervous', demeanor = 'rude',
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = RUSHER_Q, lines = {
            c_stage = { "He's a liar! Someone has to say it to his face! I just want five minutes with the microphone!" },
        } })
    local t, stage, ordered = 0, nil, false
    local function stop(line)
        if stage == 'stopped' then return end
        stage = 'stopped'
        c:task('rusher', 'surrender')
        if c:who('speaker') then c:task('speaker', 'scene') end
        if line then c:say('rusher', line) end
    end
    c:on('contact', function(who) if who == 'rusher' and stage ~= 'rush' and stage ~= 'grab' then stage = 'stopped' end end)
    c:on('hail', function(who)
        if (stage ~= 'grab') or ordered or (who ~= 'rusher' and who ~= 'speaker') then return end
        ordered = true
        if math.random() < .5 then stop("Alright! Alright! I'm going!") else c:say('rusher', 'He needs to hear it!') end
    end)
    c:on('stunned', function(who) if who == 'rusher' then stop('Argh! Okay!') end end)
    return { ids = { 'rusher' },
        start = function() c:bring('rusher') stage = 'there' end,
        tick = function()
            t = t + 1
            if stage == 'there' and t == 30 then
                c:reveal('rusher')
                c:dispatch("Event security: a man at the front barrier keeps shouting that he's getting up on that stage.")
            end
            if stage == 'there' and t % 20 == 0 then c:say('rusher', "You're a liar! I'm coming up there!") end
            if stage == 'there' and t >= 210 and not c:talking('rusher') then
                stage = 'rush'
                c:reveal('rusher')
                c:note('A man went over the front barrier and rushed the stage')
                c:task('rusher', 'go', 'stage')
            elseif stage == 'rush' and (c:distance('rusher', 'stage') or 99) < 3 then
                stage = 'grab'
                c:task('rusher', 'brawl', 'speaker')
                c:task('speaker', 'brawl', 'rusher')
                c:say('speaker', 'Security! SECURITY!')
            end
        end,
        done = function()
            local v = out.rusher
            if v == 'arrested' then return out.rusher_taken and 'a man who tried to get on the stage was arrested' end
            if v == 'cited' or v == 'warning' or v == 'released' then return 'a man shouting at the stage was spoken to and sent home' end
            if v == 'fled' or v == 'gone' then return 'a man who tried to get on the stage got away' end
            if v == 'hospital' or v == 'pronounced' then return 'a man who rushed the stage was taken away by paramedics' end
        end,
        left = 'a man shouting at the stage left before he was dealt with', people = { 'rusher' },
    }
end

local function gunman(c, out)
    c:person('gunman', { at = 'press', later = true, label = 'Man', male = true, secret = 'nervous', demeanor = 'nervous',
        weapon = 'WEAPON_PISTOL', items = { 'Pistol, loaded, in his waistband' }, scene = 'WORLD_HUMAN_STAND_IMPATIENT',
        questions = GUNMAN_Q, lines = {
            c_gun = cracks(2, { "Anything? Like what? Keys. A phone." },
                { { "...It's for protection. You've seen what people are like at these things.", set = { c_admit = 'yes' } } },
                { "I told you. It's for protection." }),
        } })
    local t, stage, left, away = 0, nil, 0, 0
    local function surrender(line)
        if stage ~= 'drawn' then return end
        stage = 'down'
        c:done('armed')
        c:who('gunman').ran, c:who('gunman').gave_up = true, true
        c:say('gunman', line)
        c:task('gunman', 'surrender')
    end
    c:on('contact', function(who) if who == 'gunman' and stage == 'there' then stage = 'spoken' end end)
    c:on('hail', function(who)
        if who == 'gunman' and stage == 'drawn' and math.random() < .5 then surrender("Okay! Okay! It's on the ground!") end
    end)
    c:on('contact_ended', function(who, outcome) if who == 'gunman' and outcome == 'fled' then stage = 'ran' end end)
    return { ids = { 'gun', 'armed' },
        start = function() c:bring('gunman') stage = 'there' end,
        tick = function()
            t = t + 1
            if stage == 'there' and t == 20 then
                c:reveal('gun')
                c:dispatch('Event security: a caller says a man by the press area has a gun in his waistband. He is on his own there.')
            end
            if stage == 'there' and t > 20 and c:near('gunman', 12.0) and not c:talking() then -- (someone's walking up to him)
                local r = math.random()
                if r < .55 then stage = 'spoken' -- (he'll go quietly when spoken to)
                elseif r < .8 then
                    stage = 'ran'
                    c:task('gunman', 'flee')
                    c:note('The man reported armed ran from officers')
                else
                    stage, left = 'drawn', math.random(45, 120)
                    c:reveal('armed')
                    c:scatter('crowd')
                    c:note('The man reported armed drew a pistol on the speaker')
                    c:dispatch('All units: shots not fired, a man has a gun on the speaker. The crowd is running.')
                    c:task('gunman', 'hold', 'speaker')
                end
            elseif stage == 'drawn' then
                local health = c:health('gunman')
                if health and health > 100 and health < 150 then return surrender("I'm hit! Don't shoot!") end
                if c:near('gunman', 45.0) then left = left - 1 end
                if left <= 0 then surrender("Fine! Fine! It's down!") end
            elseif stage == 'ran' and not c:talking('gunman') and not out.gunman then
                away = c:near('gunman', 200.0) and 0 or away + 1
                if away >= 30 then c:remove('gunman') end
            end
        end,
        done = function()
            local v = out.gunman
            if v == 'arrested' then return out.gunman_taken and 'a man carrying a pistol by the press area was arrested' end
            if v == 'cited' or v == 'warning' or v == 'released' then return 'a man reported armed by the press area was spoken to and let go' end
            if v == 'fled' or v == 'gone' then return 'a man reported armed by the press area ran and got away' end
            if v == 'hospital' or v == 'pronounced' then return 'a man reported armed by the press area was taken away by paramedics' end
        end,
        left = 'a man reported armed by the press area left before he was found', people = { 'gunman' },
    }
end

-- ─── the rally ─────────────────────────────────────────────────────────────────

-- Everyone there from the start, the crowd, and the schedule: 3-4 small things spaced through the 20 minutes, and the
-- story's big one (big = a function above, or nil) at 7-15 minutes in. Over at the end (19-21 minutes), once everything
-- that started is dealt with, nobody's waiting to be taken in and anyone hurt has been seen to.
local function rally(c, big)
    c:person('speaker', { at = 'stage', label = 'Speaker', male = math.random() < .5, secret = 'clean', demeanor = 'polite',
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = { { id = 'c_ok', label = 'Everything alright up here?' } },
        lines = { c_ok = { "Wonderful turnout. Wonderful. Thank you for being here, officer." } } })
    c:person('steward', { at = 'steward', label = 'Steward', model = 's_m_m_security_01', secret = 'clean', demeanor = 'polite',
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = STEWARD_Q, lines = {
            c_what = { "Quiet so far. We'll radio you through dispatch if anything kicks off. Watch the front, that's where it goes wrong." },
            c_size = { "Couple of hundred over the afternoon. People come and go." },
        } })
    c:crowd('crowd', { at = 'crowd', radius = 20.0, count = 30, entries = { 'gate1', 'gate2' } })
    card(c)
    local out, units, medic = {}, {}, {}
    local small = { drunk(c, out), pickpocket(c, out), scuffle(c, out), lost(c, out) }
    for i = #small, 2, -1 do local j = math.random(i) small[i], small[j] = small[j], small[i] end
    local plan, at = {}, math.random(90, 150)
    for i = 1, math.random(3, 4) do plan[i] = { thing = small[i], at = at } at = at + math.random(200, 280) end
    if big then plan[#plan + 1] = { thing = big(c, out), at = math.random(420, 900) } end
    local ending, t0, near_stage, over = math.random(1140, 1260), nil, 0, false

    c:on('arrive', function(src) units[src] = true end)
    c:on('contact', function(who) if who == 'steward' then c:done('steward') end end)
    c:on('act', function(who, action)
        local o = c:who(who)
        if action == 'cuff' and o and o.cuffed then out[who] = 'arrested' c:custody(who)
        elseif action == 'uncuff' and out[who] == 'arrested' then out[who] = nil c:hide('custody:' .. who)
        elseif (action == 'cite' or action == 'warn') and out[who] ~= 'arrested' then out[who] = action == 'cite' and 'cited' or 'warning' end
    end)
    c:on('custody', function(who) out[who .. '_taken'] = true end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'arrested' or out[who] == 'dead' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif outcome == 'released' or outcome == 'cited' or outcome == 'warning' then
            out[who] = out[who] or outcome
            local stays = { steward = true, speaker = true, parent = true, mark = true, kid = true }
            if not stays[who] and not (who == 'drunk' and c:get('drunk_fare')) then c:task(who, 'wander') end -- (sent on their way)
        end
    end)
    c:on('gone', function(who)
        if out[who] == 'arrested' then out[who .. '_taken'] = true
        elseif out[who] == 'dead' then out[who] = 'pronounced' medic[who] = false c:done('medic:' .. who)
        elseif not out[who] then out[who] = 'gone' end
    end)
    c:on('dead', function(who)
        out[who] = 'dead'
        c:hide('custody:' .. who)
        if medic[who] ~= nil then return end
        medic[who] = true
        c:objective('medic:' .. who, 'Call paramedics for the casualty', { who = 'all', blip = who,
            hint = 'Radio for an ambulance. If they pronounce them, the coroner can take them.' })
        c:dispatch('Casualty at the rally. Paramedics needed.')
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' or what == 'hospital' or what == 'treated' then
            medic[who] = false
            c:done('medic:' .. who)
            if out[who] ~= 'arrested' then out[who] = what == 'pronounced' and 'pronounced' or 'hospital'
            elseif what == 'hospital' then out[who .. '_taken'] = true end
        end
    end)

    c:on('tick', function(secs)
        if over then return end
        if not t0 then
            if not next(units) then return end
            t0 = secs
        end
        local t = secs - t0
        if c:near('speaker', 15.0) then near_stage = near_stage + 1 if near_stage >= 30 then c:done('stage') end end
        local open = false
        for _, p in ipairs(plan) do
            if not p.started and t >= p.at and t < ending then p.started = true p.thing.start() end
            if p.started and not p.line then
                p.thing.tick()
                p.line = p.thing.done()
                if p.line then
                    for _, id in ipairs(p.thing.ids) do c:done(id) end
                    c:note(('Rally: %s.'):format(p.line))
                else
                    open = true
                end
            end
        end
        if t < ending then return end
        for _, p in ipairs(plan) do
            if p.started and not p.line and t >= ending + 90 then
                local busy = false
                for _, key in ipairs(p.thing.people) do
                    local o = c:who(key)
                    if (o and o.cuffed) or c:talking(key) then busy = true end
                end
                if not busy then
                    p.line = p.thing.left
                    for _, id in ipairs(p.thing.ids) do c:done(id) end
                    for _, key in ipairs(p.thing.people) do if c:health(key) and (c:health(key) or 0) > 100 then c:task(key, 'wander') end end
                    c:note(('Rally: %s.'):format(p.line))
                end
            end
        end
        open = false
        for _, p in ipairs(plan) do if p.started and not p.line then open = true end end
        if not c:get('ending_said') then
            c:set('ending_said', true)
            c:dispatch("Event security: the rally's wrapping up and the crowd's heading home. Finish what you've got and stand down.")
        end
        if open then return end
        for k, v in pairs(out) do if v == 'arrested' and not out[k .. '_taken'] then return end end
        for _, pending in pairs(medic) do if pending then return end end
        over = true
        c:done('patrol') c:done('steward') c:done('stage')
        local lines = {}
        for _, p in ipairs(plan) do if p.line then lines[#lines + 1] = p.line end end
        c:finish(('Event security at a political rally, %s.%s'):format(c:street(),
            lines[1] and (' ' .. #lines .. ' incidents: ' .. table.concat(lines, '; ') .. '.') or ' The rally passed without incident.'))
    end)
end

Callout({
    id = 'rally',
    name = 'Event security',
    tasking = 'event', -- (a special tasking: asked for on the radio, never put out by dispatch)
    joinable = true,   -- (once someone's on it, other units are asked for)
    voice = 'call_rally', -- (dispatch's line: lwk_control/tools/make_voice.py)
    alert = 'Special tasking',
    priority = 2,
    weight = 1,
    max_minutes = 40,
    enabled = true,
    reports = {
        'Event security for a political rally. Patrol the crowd and assist event staff until it ends.',
        'Political rally under way. Units requested to support event security until the crowd disperses.',
        'Large crowd expected at a political rally. Keep a presence, deal with anything event security calls in.',
    },
    -- The points each location needs, in the order /c3rplace rally walks you through them. The first is the stage.
    points = {
        { 'stage', 'The speaker, on the stage or at the podium.' },
        { 'steward', 'The steward from event security, at the entrance officers would walk in by.' },
        { 'crowd', 'The middle of the crowd, in front of the stage (people walk about within 20 m of here).' },
        { 'gate1', 'One way in and out of the crowd, at its edge.' },
        { 'gate2', 'Another way in and out, on the far side.' },
        { 'barrier', 'The front barrier, between the crowd and the stage.' },
        { 'press', 'The press area: off to one side, at least 25 m from the middle of the crowd (nobody walks about there).' },
        { 'stall', 'The food stall, at the edge of the crowd.' },
        { 'drunk', 'Somewhere near the drinks, at the edge of the crowd.' },
        { 'mark', 'Someone in the crowd, a little way in.' },
        { 'kid', 'A spot near a way out where a lost teenager would wait, away from the info point.' },
        { 'parent', 'The info point, where a parent would wait.' },
    },
    -- Add more with /c3rplace rally in game (it writes them here). This one is a rough placeholder (Maze Bank plaza).
    locations = {
        { street = 'Power St', at = vector3(-66.00, -799.00, 44.23), points = {
            stage = vector4(-66.00, -799.00, 44.23, 160.0),
            steward = vector4(-80.00, -830.00, 40.60, 340.0),
            crowd = vector4(-70.00, -812.00, 43.20, 340.0),
            gate1 = vector4(-92.00, -818.00, 40.60, 270.0),
            gate2 = vector4(-48.00, -826.00, 40.60, 90.0),
            barrier = vector4(-67.50, -803.50, 44.00, 340.0),
            press = vector4(-95.00, -797.00, 44.20, 250.0),
            stall = vector4(-55.00, -815.00, 43.30, 90.0),
            drunk = vector4(-58.00, -820.00, 43.00, 60.0),
            mark = vector4(-72.00, -815.00, 43.20, 20.0),
            kid = vector4(-90.00, -822.00, 40.60, 300.0),
            parent = vector4(-78.00, -828.00, 40.60, 160.0),
        } },
    },

    stories = {
        routine = { weight = 2, setup = function(c) rally(c) end },
        rusher = { weight = 1, setup = function(c) rally(c, rusher) end },
        gun = { weight = 1, setup = function(c) rally(c, gunman) end },
    },
})
