--[[
    c3r callout: MENTAL HEALTH CRISIS.

    Someone in a public place is frightening people. The report is the same every time, and the card is too: the caller,
    the bag they left, and making contact (three units can take one each). What's really going on is one of five stories:
      lsd        a bad trip: tabs in the bag, and the ground is moving
      veteran    a flashback: discharge papers and unfilled pills in the bag, and you're the enemy
      meds       schizophrenia, off their medication: the bag has an emergency contact, and their sister knows what helps
      diabetic   not a mental health call at all: blood sugar. Insulin in the bag, and a clock: too slow and they collapse
      dementia   wandered off from home: a label in the bag, and a relative out looking for them
    What matters is how they're handled. The right questions calm them; a gun on them, the wrong questions or searching them
    too soon make it worse, and pushed far enough they run or swing, by story. Calm, they'll always go with paramedics.
    It's dealt with when paramedics have taken them, family has, whoever's arrested is taken in, they're let go, get away or
    die, or the caller's been heard, they've been spoken to and every unit has left.

    Points per location: walk them out in game with /c3rplace crisis (it writes the location in below).
]]

local CALLER_Q = {
    { id = 'c_what', label = 'What did you see?' },
    { id = 'c_how', label = 'How long has this been going on?' },
    { id = 'c_hurt', label = 'Have they hurt anyone?' },
    { id = 'c_said', label = 'What are they saying?' },
}
local RELATIVE_Q = {
    { id = 'c_who', label = 'Who are you looking for?' },
    { id = 'c_take', label = 'Can you take them home?', needs = { c_calm = true } },
}
local CALM_NEEDED = 3 -- (a good answer's 1, the one that fits the story 2)
local GOOD = { c_name = 1, c_safe = 1, c_sit = 1, c_key = 2 }
local BAD = { c_order = true, c_drugs = true }

local function card(c)
    c:objective('caller', 'Talk to the caller', { hint = 'They are keeping their distance.', blip = 'caller' })
    c:objective('bag', 'Check the bag', { hint = 'Left nearby. It may say who this is.', blip = 'bag' })
    c:objective('subject', 'Make contact with them', { hint = 'Slowly. Keep your hands where they can see them.' })
    c:objective('relative', 'Talk to the relative', { hidden = true, blip = 'relative', hint = 'Out looking for them.' })
    c:objective('settle', 'Get them under control', { hidden = true, who = 'all', blip = 'subject', hint = 'They are not themselves. They give up if they have to.' })
    c:objective('medic', 'Call paramedics', { hidden = true, who = 'all', blip = 'subject', hint = 'Radio for an ambulance.' })
    c:objective('decide', 'Deal with it: paramedics, arrest, or let them go', { after = { 'subject' }, who = 'all' })
end

-- Done when: the caller's said what they saw, the bag's been looked at, they've been reached.
local function wire(c)
    c:on('act', function(who, action, arg)
        if who == 'caller' and action == 'ask' and arg == 'c_what' then
            c:done('caller')
            c:blip('subject', 'subject') -- (not before: the map would do the caller's job)
        end
        if who == 'relative' and action == 'ask' and arg == 'c_who' then c:done('relative') end
    end)
    c:on('inspect', function(clue) if clue == 'bag' then c:set('bag_seen', true) c:done('bag') end end)
    c:on('contact', function(who)
        if who ~= 'subject' then return end
        c:done('subject')
        c:blip('decide', 'subject')
    end)
    c:on('dead', function(who)
        if who == 'caller' then c:done('caller') end
        if who == 'relative' then c:done('relative') end
    end)
end

--[[ How they're doing. Calm: the good questions, each once. Worse: the bad ones, hands on them before they're calm, or a gun
     on them (one look at it is one step; still on them 6 s later, another). Two steps and they react, once, by story: `how`
     is 'swing' (they fight, unarmed, until hurt, told to stop half the time, or 45-120 s with units near), 'run' or 'cower'.
     After that it's over: spent, they're calm. -> agree(): they'll go with paramedics ]]
local function mood(c, s)
    local calm, upset, asked, settled, reacted = 0, 0, {}, false, false
    local clock, aimed_at, fighting, left, rant, next_rant = 0, -100, false, 0, 1, 0

    local function agree()
        c:patient('subject')
        c:reveal('medic')
    end
    local function calmed()
        if settled then return end
        settled = true
        c:set('calmed', true)
        agree()
        if s.how == 'cower' and not c:talking('subject') then c:task('subject', 'scene') end
        for _, key in ipairs({ 'subject', 'relative' }) do
            local o = c:who(key)
            if o then
                o.facts.c_calm = 'yes'
                c:questions(key)
            end
        end
    end
    local function surrender(line)
        fighting = false
        local o = c:who('subject')
        o.ran, o.gave_up = true, true -- (going for the cuffs won't send them running now)
        c:done('settle')
        c:say('subject', line)
        c:task('subject', 'surrender')
        calmed()
    end
    local function react()
        reacted = true
        c:note('The subject reacted to how they were approached')
        if s.how == 'swing' then
            fighting, left = true, math.random(45, 120)
            c:set('fought', true)
            c:reveal('settle')
            c:task('subject', 'shoot')
        elseif s.how == 'run' then
            c:set('ran', true)
            if not c:talking('subject') then c:set('loose', true) end -- (with no stop to chase them: see resolve)
            c:task('subject', 'flee')
        else
            c:say('subject', s.cower)
            if not c:talking('subject') then c:task('subject', 'surrender') end
        end
    end
    local function worse()
        if settled or reacted or c:who('subject').cuffed then return end
        upset = upset + 1
        if upset >= 2 then react() end
    end

    c:on('act', function(who, action, arg)
        if who ~= 'subject' then return end
        if action == 'frisk' then worse() end
        if action == 'cuff' and c:who('subject').cuffed and not settled then c:set('early', true) end
        if action ~= 'ask' then return end
        if BAD[arg] then worse() end
        if GOOD[arg] and not asked[arg] then
            asked[arg] = true
            calm, upset = calm + GOOD[arg], math.max(0, upset - 1)
            if calm >= CALM_NEEDED then calmed() end
        end
        if arg == 'c_medic' then agree() end
    end)
    c:on('aimed', function(who)
        if who ~= 'subject' or settled or c:get('collapsed') or clock - aimed_at < 6 then return end
        aimed_at = clock
        c:set('aimed', true)
        c:say('subject', s.gun)
        worse()
    end)
    c:on('hail', function(who)
        if who == 'subject' and fighting and math.random() < 0.5 then surrender(s.stop) end
    end)
    c:on('contact', function(who) -- (run down: it's gone out of them)
        if who ~= 'subject' or not c:get('loose') then return end
        c:set('loose', false)
        calmed()
    end)
    c:on('tick', function()
        clock = clock + 1
        local o = c:who('subject')
        if not o or o.cuffed or c:get('dead_subject') or c:get('collapsed') then return end
        if not settled and not c:talking() and clock >= next_rant and c:near('subject', 30.0) then
            next_rant = clock + 25
            c:say('subject', s.rants[rant])
            rant = rant % #s.rants + 1
        end
        if not fighting then return end
        local health = c:health('subject')
        left = c:near('subject', 45.0) and left - 1 or left
        if health and health > 100 and health < 150 then surrender(s.stop)
        elseif left <= 0 then surrender(s.stop) end
    end)
    return agree
end

--[[ It's over when paramedics have taken them or seen to them, family has, everyone arrested has been taken in, they've been
     let go or got away (run from units who've lost them: 20 s with nobody within 100 m), or the caller's been heard, they've
     been reached and every unit has left. Dead, the card says to call
     paramedics and it goes on until they're pronounced or the coroner's been. ends(out) -> the MDT summary; out.subject =
     'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' | 'pronounced' | 'hospital' | 'treated' | 'home' | 'gone';
     out.left = true.
     -> gone_with(how): they've left with someone ]]
local function resolve(c, ends)
    local out, taken, away_for, lost_for, done = {}, {}, 0, 0, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local OVER = { released = true, cited = true, warning = true, fled = true, pronounced = true, hospital = true, treated = true,
                   home = true, gone = true }
    local function check()
        if done or waiting() then return end
        if not (next(taken) or OVER[out.subject] or out.left) then return end
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
        check()
    end)
    c:on('custody', function(who) taken[who] = true check() end)
    local function seen_to(who, how)
        out[who] = how
        if who == 'subject' then c:done('medic') end
        check()
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true check() end
        if out[who] == 'dead' then seen_to(who, 'pronounced') end -- (the coroner's been)
        if who == 'subject' and not out.subject then -- (taken some way the call didn't hear about)
            out.subject = 'gone'
            check()
        end
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if who ~= 'subject' then return end
        c:set('dead_subject', true)
        for _, id in ipairs({ 'caller', 'bag', 'subject', 'relative', 'settle', 'decide' }) do c:done(id) end
        c:reveal('medic')
        c:dispatch('The subject is down. Paramedics needed at the scene.')
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' then seen_to(who, 'pronounced')
        elseif what == 'hospital' or what == 'treated' then seen_to(who, what) end
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or out[who] == 'pronounced' or out[who] == 'hospital' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        check() -- (walked off from them, 'cancelled': nothing decided)
    end)
    c:on('tick', function()
        lost_for = c:get('loose') and not c:near('subject', 100.0) and lost_for + 1 or 0
        if lost_for >= 20 and not out.subject then
            out.subject = 'fled'
            return check()
        end
        local here = c:near(nil, 80.0) or c:near('subject', 80.0) or c:talking()
        if c:is_done('caller') and c:is_done('subject') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then out.left = true check() end
        else
            away_for = 0
        end
    end)
    return function(how)
        out.subject = how
        check()
    end
end

-- What the summary says, whichever story it was: what became of them, then how it was handled.
local function report(c, out, what)
    local s = c:name('subject')
    local how = out.subject
    local text
    if how == 'hospital' then text = ('%s: %s went with paramedics.'):format(what, s)
    elseif how == 'treated' then text = ('%s: %s was seen by paramedics at the scene.'):format(what, s)
    elseif how == 'home' then text = ('%s: %s went home with family.'):format(what, s)
    elseif how == 'arrested' then text = ('%s: %s arrested.'):format(what, s)
    elseif how == 'dead' or how == 'pronounced' then text = ('%s: %s died at the scene.'):format(what, s)
    elseif how == 'fled' then text = ('%s: %s ran and was not found.'):format(what, s)
    elseif how == 'cited' or how == 'warning' then text = ('%s: %s was given a %s and left at the scene.'):format(what, s, how == 'cited' and 'ticket' or 'warning')
    else text = ('%s: %s was left at the scene.'):format(what, s) end
    if c:get('calmed') and not c:get('fought') then text = text .. ' Calmed by officers.' end
    if c:get('aimed') then text = text .. ' A weapon was pointed at them.' end
    if c:get('fought') then text = text .. ' They fought officers.' end
    if c:get('ran') then text = text .. ' They ran from officers.' end
    if c:get('early') then text = text .. ' Restrained before they were calm.' end
    if c:get('collapsed') then text = text .. ' They collapsed at the scene.' end
    local o = c:who('subject')
    if o and o.facts.found and how == 'arrested' then text = text .. ' Recorded: what was found on them.' end
    return text
end

-- One story, from its table. s = { what (for the report), how (see mood), male?, model?, age, secret?, items?, pockets?, key (the
-- question that fits), fact (what opens it: given by the bag), bag (the bag's text), caller (their lines), lines (the
-- subject's), rants, gun (a gun on them), stop (giving up), cower?, setup? (c, agree, gone_with) }
local function play(c, s)
    local male = s.male
    if male == nil then male = math.random() < .5 end
    c:person('caller', { at = 'caller', label = 'Caller', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = CALLER_Q, lines = s.caller })
    local q = {
        { id = 'c_name', label = "I'm here to help. What should I call you?" },
        { id = 'c_safe', label = "You're safe. Nobody's going to hurt you." },
        { id = 'c_sit', label = 'Can you sit down with me for a minute?' },
        { id = 'c_key', label = s.key, needs = { [s.fact] = true } },
        { id = 'c_order', label = 'Calm down, right now!', press = true, stress = true },
        { id = 'c_drugs', label = 'Are you on drugs?', press = true, stress = true },
        { id = 'c_medic', label = 'Will you let the paramedics check you over?', needs = { c_calm = true } },
    }
    s.lines.where = s.lines.where or { "I don't... I don't know." }
    c:person('subject', { at = 'subject', label = 'Person', male = male, model = s.model and s.model[male and 1 or 2], age = s.age,
        secret = s.secret or 'clean', demeanor = 'nervous', items = s.items or {}, pockets = s.pockets, scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = q, lines = s.lines })
    c:clue('bag', { at = 'bag', label = 'A bag', prop = 'prop_michael_backpack', text = s.bag })
    if s.relative then
        c:person('relative', { at = 'relative', label = 'Relative', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = RELATIVE_Q, lines = s.relative })
    end
    card(c)
    wire(c)
    local agree = mood(c, s)
    c:on('inspect', function(clue)
        if clue ~= 'bag' then return end
        c:who('subject').facts[s.fact] = 'yes'
        c:questions('subject')
    end)
    local gone_with = resolve(c, function(out) return report(c, out, s.what) end)
    if s.setup then s.setup(c, agree, gone_with) end
end

Callout({
    id = 'crisis',
    name = 'Mental health crisis',
    voice = 'call_crisis', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        "Caller reports someone shouting at people. They say it isn't making any sense.",
        "Person acting erratically and frightening people. Caller doesn't think they're drunk.",
        "Caller says someone is yelling at nobody and won't calm down. They're keeping their distance.",
    },
    -- The points each location needs, in the order /c3rplace crisis walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it).
    -- Skip the relative with Z in /c3rplace: without one, paramedics are the only way home in the dementia story.
    points = {
        { 'caller', 'The caller: at a safe distance, watching.' },
        { 'subject', 'The person in crisis: somewhere open, 20 m or so from the caller.' },
        { 'bag', 'Their bag: on a bench or the ground, a little way from them.' },
        { 'relative', 'A relative out looking for them: 50 m or so away, on a path.', optional = true },
    },
    -- Add more with /c3rplace crisis in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Legion Square', at = vector3(190.0, -925.0, 30.7), points = {
            caller = vector4(190.0, -925.0, 30.7, 180.0),
            subject = vector4(200.0, -945.0, 30.7, 0.0),
            bag = vector4(197.0, -940.0, 30.7, 0.0),
            relative = vector4(175.0, -950.0, 30.7, 90.0),
        } },
        { street = 'Adams Apple Blvd', at = vector3(13.68, -1119.13, 28.76), streets = { relative = 'Elgin Ave' }, points = {
            caller = vector4(13.68, -1119.13, 28.76, 177.4),
            subject = vector4(5.37, -1103.68, 29.80, 72.9),
            bag = vector4(11.42, -1104.07, 29.80, 267.2),
            relative = vector4(16.60, -1102.31, 29.80, 101.4),
        } },
        { street = 'Route 68', at = vector3(618.21, 2786.29, 43.48), points = {
            caller = vector4(618.21, 2786.29, 43.48, 49.5),
            subject = vector4(585.25, 2813.67, 41.79, 22.6),
            bag = vector4(590.60, 2802.26, 41.91, 212.5),
        } },
        { street = 'Senora Fwy', at = vector3(1721.98, 6411.74, 33.99), points = {
            caller = vector4(1721.98, 6411.74, 33.99, 119.3),
            subject = vector4(1707.93, 6416.51, 32.64, 182.0),
            bag = vector4(1710.12, 6421.21, 32.64, 1.1),
        } },
    },

    stories = {
        -- ── A bad trip. ──────────────────────────────────────────────────────────────────────────────────────────
        lsd = {
            weight = 3,
            setup = function(c)
                play(c, {
                    what = 'Mental health crisis, a bad LSD trip',
                    how = 'run',
                    age = { 19, 26 },
                    secret = 'drugs',
                    items = { 'Three tabs of LSD in foil' },
                    key = "You've taken something. It will wear off. You're going to be okay.",
                    fact = 'c_tabs',
                    bag = 'A backpack, left open. A festival wristband, a water bottle, and a square of foil with the corners torn off. Tabs.',
                    caller = {
                        c_what = { "They were with a couple of friends, laughing. Then the friends left and it all went wrong. Now they keep looking at the ground like it's moving." },
                        c_how = { "Half an hour? Getting worse." },
                        c_hurt = { "No. I think they're the one who's scared." },
                        c_said = { "That everything's breathing. I don't know." },
                    },
                    lines = {
                        c_name = { "My name's... it keeps moving. Why does it keep moving?" },
                        c_safe = { "Okay. Okay. Is the ground okay? Is it going to stop?" },
                        c_sit = { "If I sit down, will it still be there?" },
                        c_key = { "It'll wear off? How long? ...Okay. Okay. I took too much. I just wanted to see what it was like." },
                        c_order = { "I'm trying! I'm trying! Stop shouting, your face is melting!" },
                        c_drugs = { "What? No! Who told you? Are you real?" },
                        c_medic = { "Yeah. Yeah, okay. Stay with me till they come, though." },
                        explain = { "It was just the once. They said it'd be fun. Is it still working? Is it going to stop?" },
                    },
                    rants = { "It's breathing! The whole thing's breathing!", "Don't stand on it! Get off it!", "Somebody make it stop!" },
                    gun = "What's that? What's in your hand? No, no, no!",
                    stop = "Okay. Okay. I'm sorry.",
                })
            end,
        },

        -- ── A flashback. ─────────────────────────────────────────────────────────────────────────────────────────
        veteran = {
            weight = 3,
            setup = function(c)
                play(c, {
                    what = 'Mental health crisis, a veteran in a flashback',
                    how = 'swing',
                    age = { 38, 58 },
                    key = "Where did you serve? You're home now. This is Los Santos.",
                    fact = 'c_tags',
                    bag = 'A worn rucksack, packed like it was done by someone who was taught to. Discharge papers, a VA appointment card from last month, and a prescription that was never filled.',
                    caller = {
                        c_what = { "A car backfired by the road and they just dropped. Then they got up shouting orders at people. Telling everyone to get down." },
                        c_how = { "Fifteen minutes. They keep checking the rooftops." },
                        c_hurt = { "Not yet. They grabbed a guy's arm and told him to move. He ran." },
                        c_said = { "Names. Like they're calling people. And 'contact', over and over." },
                    },
                    lines = {
                        c_name = { "Identify yourself! Who's your commanding officer?" },
                        c_safe = { "Nobody's safe. You can't be standing out here. Get down!" },
                        c_sit = { "Sit? Here? We're exposed. ...How long have you been here?" },
                        c_key = { "Home? ...Two tours. I was... this isn't... There was a truck. I heard it. ...I'm home. Oh, God. Was I shouting?" },
                        c_order = { "Don't you give me orders! Who sent you?" },
                        c_drugs = { "You think this is a joke? I've got people out there!" },
                        c_medic = { "Yeah. I missed my appointment. I should've gone. Yes. I'll go." },
                    },
                    rants = { "Contact! Get down! Everybody get down!", "Where's the rest of the squad? Answer me!", "Rooftop! Check the rooftop!" },
                    gun = "Weapon! Weapon! Contact!",
                    stop = "Okay! Okay. I'm down. I'm down. I don't... where am I?",
                })
            end,
        },

        -- ── Off their medication. ────────────────────────────────────────────────────────────────────────────────
        meds = {
            weight = 2,
            setup = function(c)
                play(c, {
                    what = 'Mental health crisis, off their medication',
                    how = 'run',
                    age = { 24, 45 },
                    key = 'Your sister asked me to come and find you. She says the voices lie.',
                    fact = 'c_sister',
                    bag = 'A tote bag. A pharmacy bag with a month of pills, still sealed, and an emergency contact card: a sister.',
                    caller = {
                        c_what = { "They're arguing with someone. There's nobody there. They told an old lady to stop sending the messages." },
                        c_how = { "I see them round here sometimes and they're fine. Today's different." },
                        c_hurt = { "No. They just scare people." },
                        c_said = { "Something about messages. That they can hear what people are thinking." },
                    },
                    lines = {
                        c_name = { "Don't say it out loud. They'll hear it." },
                        c_safe = { "You don't know that. They told me you'd say that." },
                        c_sit = { "...Only if you tell them to be quiet first." },
                        c_key = { "She said that? That's what she always says. ...I stopped taking them. They make me slow. I thought I could do it." },
                        c_order = { "They're telling me what you're going to do. Don't. Don't!" },
                        c_drugs = { "They put it in the water. You know they do." },
                        c_medic = { "Will you tell my sister? ...Okay. Okay, I'll go." },
                    },
                    rants = { "Stop sending them! I said stop!", "I can hear you! I can hear all of you!", "Leave me alone! I didn't do it!" },
                    gun = "They said you would! They said! Get away!",
                    stop = "Okay. I'm tired. I'm so tired.",
                    setup = function(cc)
                        cc:on('inspect', function(clue)
                            if clue == 'bag' then cc:dispatch("Dispatch: we reached the emergency contact. It's their sister. She says they stopped their medication, and to tell them 'the voices lie'.") end
                        end)
                    end,
                })
            end,
        },

        -- ── Not mental health at all. ────────────────────────────────────────────────────────────────────────────
        diabetic = {
            weight = 2,
            setup = function(c)
                play(c, {
                    what = 'Reported mental health crisis, in fact a diabetic emergency',
                    how = 'cower',
                    age = { 30, 60 },
                    pockets = { 'Medical bracelet: Type 1 diabetic' },
                    key = 'When did you last eat? Do you have your insulin?',
                    fact = 'c_meter',
                    bag = 'A gym bag. An insulin pen, a glucose meter and an empty packet of dextrose tablets.',
                    caller = {
                        c_what = { "They're sweating and swaying, shouting at people, slurring. But I can't smell any drink on them. And they looked fine ten minutes ago." },
                        c_how = { "Ten minutes? It came on fast." },
                        c_hurt = { "No. I don't think they know where they are." },
                        c_said = { "It doesn't make sense. It's like they can't find the words." },
                    },
                    lines = {
                        c_name = { "I'm... it's... I know it. Give me a second." },
                        c_safe = { "Why is it so bright? I'm so cold." },
                        c_sit = { "Yes. Sit. My legs are... yes." },
                        c_key = { "Eat? I didn't... I gave myself... this morning. I need... sugar. I need sugar." },
                        c_order = { "I can't... what are you... stop it, stop shouting..." },
                        c_drugs = { "No... no... I'm not... I just need..." },
                        c_medic = { "Yes. Please. Something's wrong." },
                    },
                    rants = { "Get away from me! I don't... where's my... where's the car?", "Why won't you all stop looking at me?", "I need... I can't... somebody!" },
                    gun = "What? No... no, please...",
                    stop = "I'm sorry. I'm sorry.",
                    cower = "Please... don't... please...",
                    setup = function(cc, agree)
                        local left, running = 240, false
                        local function knows()
                            agree()
                            cc:dispatch('Sounds like a diabetic emergency, not a mental health call. Get paramedics there now.')
                        end
                        cc:on('arrive', function() running = true end)
                        cc:on('inspect', function(clue) if clue == 'bag' then knows() end end)
                        cc:on('act', function(who, action, arg)
                            if who ~= 'subject' then return end
                            if (action == 'ask' and arg == 'c_key') or action == 'frisk' then knows() end -- (the frisk: the bracelet)
                            if action == 'cuff' and cc:who('subject').cuffed then left = math.min(left, 15) end -- (a struggle's the last thing they need)
                        end)
                        cc:on('tick', function()
                            if not running or cc:is_done('medic') or cc:get('dead_subject') then return end
                            left = left - 1
                            if left ~= 0 then return end
                            -- ponytail: cuffed, they don't drop, as keep_up leaves prisoners be, and sat in a patrol car an
                            -- ambulance can't reach them. E beside them still opens first aid; booking them ends it.
                            cc:set('collapsed', true)
                            cc:collapse('subject')
                            agree()
                            cc:note('The subject collapsed at the scene')
                            cc:dispatch('They have collapsed. Paramedics needed now.')
                        end)
                    end,
                })
            end,
        },

        -- ── Wandered off. ────────────────────────────────────────────────────────────────────────────────────────
        dementia = {
            weight = 2,
            setup = function(c)
                play(c, {
                    what = 'Mental health crisis, a dementia patient who had wandered off',
                    how = 'cower',
                    age = { 72, 86 },
                    model = { 'a_m_o_genstreet_01', 'a_f_o_genstreet_01' },
                    key = "Let's get you home. Who's waiting for you?",
                    fact = 'c_label',
                    bag = "An old shopping bag. A cardigan with a name tape sewn in, a house key on a ribbon, and a laminated card: 'I have dementia. If I seem lost, please call my family.'",
                    caller = {
                        c_what = { "They keep stopping people and telling them off. Asking where the school is, and shouting when nobody knows. Then they got scared." },
                        c_how = { "An hour, maybe? They've been up and down this path." },
                        c_hurt = { "No. No, the poor thing. They just want to go home, I think." },
                        c_said = { "They say they're late. Late to pick up the children." },
                    },
                    lines = {
                        c_name = { "I'm late. I have to get the children. Do you know the time?" },
                        c_safe = { "That's very kind. Are you from the school?" },
                        c_sit = { "Only for a minute. They'll be waiting at the gate." },
                        c_key = { "Home? Yes. I'd like that. I don't... I don't know this road. It's all been moved." },
                        c_order = { "Don't you shout at me! Who are you? I want to go home!" },
                        c_drugs = { "I beg your pardon? How dare you?" },
                        c_medic = { "Are they nice? Alright, dear. If you say so." },
                    },
                    rants = { "Where's the school? Who moved the school?", "I'm late! Nobody will tell me the time!", "You can't just stand there! Those children are waiting!" },
                    gun = "Oh! Oh no, please, I haven't done anything!",
                    stop = "I'm sorry. I don't know where I am.",
                    cower = "Please don't. I want to go home.",
                    relative = {
                        c_who = { "Someone from my family. They've got dementia. They were at home an hour ago and the door was open. Have you seen them? Please say you've seen them." },
                        c_take = function()
                            if c:who('subject').cuffed then return { "In handcuffs? Please, they don't know where they are. Take those off them." } end
                            return { { "Yes. Yes, of course. Thank you. Thank you so much. The car's just over there.", set = { c_taken = 'yes' } } }
                        end,
                    },
                    setup = function(cc, _, gone_with)
                        cc:on('inspect', function(clue) if clue == 'bag' then cc:reveal('relative') end end)
                        cc:on('contact', function(who) if who == 'relative' then cc:reveal('relative') end end)
                        local walking = 0 -- (long enough to see the two of them together)
                        cc:on('fact', function(_, fact)
                            if fact ~= 'c_taken' then return end
                            walking = 15
                            cc:task('subject', 'go', 'relative')
                        end)
                        cc:on('tick', function()
                            if walking <= 0 then return end
                            walking = walking - 1
                            if walking == 0 then gone_with('home') end
                        end)
                    end,
                })
            end,
        },
    },
})
