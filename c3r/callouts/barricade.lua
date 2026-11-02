--[[
    c3r callout: BARRICADED SUBJECT.

    Someone has shut themselves in and won't come out. The report is the same every time, and the card is too: the caller, securing
    the rear and what's by the entrance (three units can take one each), then making contact. What's really going on is one of five
    stories:
      eviction  a tenant put out with eighteen days left on the notice; the caller is the landlord
      refuge    she's hiding from the caller, her ex, who has a protective order against him. She won't come out while he's free
      despair   alone, with nothing left, and no danger to anyone else. His brother knows him. Paramedics, not cuffs
      cornered  he hurt a man in a fight and ran here. He tries the back after a few minutes, and he's the only one who'll fire
      drill     an old man boarding up his door: the "gun" is a nail gun, and his hearing aids are out
    Contain it, then talk from cover: E reaches them from REACH m. Listening earns trust, and what you found out earns more. Enough
    of it opens the terms, and they leave what they have inside and walk out to you. Time is on your side: every quiet minute helps.
    Orders, threats, a gun on them or anyone close add heat, and at HEAT they stop talking for a while. Pushed again, the one who
    fires, fires. It's dealt with when whoever's arrested is taken in, paramedics have them, they're let go, get away or die, or the
    caller's been heard, contact made and every unit has left.

    Points per location: walk them out in game with /c3rplace barricade (it writes the location in below).
]]

local CALLER_Q = {
    { id = 'c_what', label = 'What happened?' },
    { id = 'c_who', label = 'Who is in there?' },
    { id = 'c_gun', label = 'Did you see a gun?' },
    { id = 'c_why', label = 'Why are they in there?' },
    { id = 'c_door', label = 'That was kicked in from the outside.', needs = { c_kicked = true }, stress = true, press = true },
}
local RELATIVE_Q = {
    { id = 'c_who', label = 'Who are you to them?' },
    { id = 'c_help', label = 'What would get through to them?' },
}
local SUBJECT_Q = {
    { id = 'c_name', label = "I'm not coming in. What should I call you?" },
    { id = 'c_listen', label = "I'm listening. Tell me what's going on." },
    { id = 'c_want', label = 'What do you need to happen here?' },
    { id = 'c_order', label = 'Come out right now!', press = true },
    { id = 'c_force', label = "Open up or we're coming in.", press = true },
    { id = 'c_terms', label = 'Leave everything inside and walk out to me, hands where I can see them.', needs = { c_ready = true }, press = true },
}

local REACH = 12.0   -- m: how far off they can be talked to
local TRUST = 5      -- what opens the terms: a good answer's 1, the one that fits the story 2
local GOOD = { c_name = 1, c_listen = 1, c_want = 1, c_key = 2 }
local PUSH = { c_order = true, c_force = true }
local HEAT = 3       -- steps before they react
local CROWD = 5.0    -- m: anyone this close before they've agreed is pushing the door
local COOL = 45      -- s: heat drops a step
local PATIENCE = 90  -- s: with no heat on them, trust grows a step
local PUSH_GAP = 8   -- s: a gun on them, or someone close, counts once this often
local SHUT = 30      -- s: not talking after they react
local WALK = 15      -- s: walking out, then hands up wherever they've got to

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
    c:objective('caller', 'Talk to the caller', { hint = 'Find out who is in there, and why.', blip = 'caller' })
    c:objective('rear', 'Secure the rear', { hint = 'Nobody out the back. Chain it and it stays chained.', blip = 'rear' })
    c:objective('hook', 'Find something to reach them with', { blip = 'gate', hint = 'Whatever is by the entrance, and what the caller says.' })
    c:objective('subject', 'Make contact with them', { after = { 'caller' }, hint = 'From cover: E reaches them from behind your car.' })
    c:objective('relative', 'Talk to the relative', { hidden = true, blip = 'relative', hint = 'They know this person better than you do.' })
    c:objective('talk', 'Talk them out', { hidden = true, who = 'all', blip = 'subject', hint = 'Take your time. Guns down, stay back, and listen.' })
    c:objective('gunman', 'Stop the gunman', { hidden = true, who = 'all', blip = 'subject', hint = 'Take cover. He gives up if he has to.' })
    c:objective('medic', 'Call paramedics', { hidden = true, who = 'all', blip = 'subject', hint = 'Radio for an ambulance.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { hidden = true, who = 'all', blip = 'subject' })
end

-- Done when: the caller's said what happened, the rear's been chained, they've been reached.
local function wire(c)
    c:on('act', function(who, action, arg)
        if who == 'caller' and action == 'ask' and arg == 'c_what' then
            c:done('caller')
            c:blip('subject', 'subject') -- (not before: the map would do the caller's job)
        end
    end)
    c:on('fact', function(_, fact) if fact == 'c_family' and c:who('relative') then c:reveal('relative') end end)
    c:on('act', function(who, action, arg)
        if who == 'relative' and action == 'ask' and arg == 'c_help' then c:done('relative') end
    end)
    c:on('contact', function(who) if who == 'relative' then c:reveal('relative') end end)
    c:on('inspect', function(clue) if clue == 'rear' then c:done('rear') end end)
    local function no_more(who) -- (can't be asked any more, so the card can't stick)
        if who == 'caller' or who == 'relative' then c:done(who) end
        if who == 'caller' then c:blip('subject', 'subject') end
    end
    c:on('dead', no_more)
    c:on('gone', no_more)
end

-- What they carry stays behind when they walk out: a search finds nothing.
local function leave_behind(c, item)
    local o = c:who('subject')
    for _, list in ipairs({ o.items, o.pockets }) do
        for i = #list, 1, -1 do if list[i] == item then table.remove(list, i) end end
    end
end

--[[ The standoff. Trust: GOOD questions, each once, and quiet time once they've been spoken to; TRUST opens the terms, which they
     take when s.clear says so. Heat: PUSH questions, a gun on them, anyone within CROWD m; HEAT and they react: a warning shot if
     they've a weapon, and SHUT s of not talking. s.fires: pushed that far a second time, he fires from the window, until hurt, told
     to stop half the time, or 45-120 s with units near. -> api: free(), press(line), bolt(), gain(n) ]]
local function standoff(c, s)
    local trust, heat, asked, clock, shut = 0, 0, {}, 0, 0
    local spoke, hooked, ready, agreed, settled, warned, fighting = false, false, false, false, false, false, false
    local leaving, walking, left, aim_at, crowd_at, cool_at, rant, next_rant = nil, nil, 0, -100, -100, COOL, 1, 0

    local function gain(n)
        trust = trust + n
        if ready or trust < TRUST then return end
        ready = true
        c:who('subject').facts.c_ready = 'yes'
        c:questions('subject')
    end
    local function open_hook()
        if hooked then return end
        hooked = true
        c:who('subject').facts.c_hook = 'yes'
        c:questions('subject')
        c:done('hook')
        if s.on_hook then s.on_hook(c) end
    end
    local function over() -- (nothing left to talk about: the card moves on)
        settled, fighting, shut = true, false, 0
        c:set('over', true)
        for _, id in ipairs({ 'subject', 'hook', 'talk', 'gunman' }) do c:done(id) end
        c:reveal('decide')
    end
    local function give_up(line)
        over()
        local o = c:who('subject')
        o.ran, o.gave_up = true, true -- (going for the cuffs won't send them running now)
        c:say('subject', line)
        c:task('subject', 'surrender')
        if s.patient then
            c:patient('subject')
            c:reveal('medic')
        end
    end
    local function react()
        heat = 1
        if s.fires and warned then
            fighting, left = true, math.random(45, 120)
            c:task('subject', 'shoot', 'window')
            return
        end
        warned, shut = true, SHUT
        c:hangup('subject')
        c:say('subject', s.warn)
        c:task('subject', 'hold')
        c:note('The subject stopped talking to officers')
        if s.weapon then
            c:set('warning', true)
            c:bang(s.weapon, 'subject', 1)
            c:dispatch('Shot from the location, into the air. Nobody hit. Hold your positions.')
        end
    end
    local function free() return not (settled or agreed or fighting or shut > 0) end
    local function press(line)
        if not free() then return end
        heat = heat + 1
        if heat >= HEAT then return react() end
        if line then c:say('subject', line) end
    end
    local function bolt()
        over()
        c:done('subject')
        c:set('ran', true)
        c:set('loose', true)
        c:who('subject').facts.ran = 'yes' -- (they really did: the stop's questions follow it)
        c:hangup('subject')
        c:task('subject', 'flee')
        c:dispatch("They're out the back and running! All units!")
        c:note('The subject ran out of the back')
    end

    c:on('contact', function(who)
        if who ~= 'subject' then return end
        c:done('subject')
        if c:get('loose') then -- (run down: it's gone out of them)
            c:set('loose', false)
            return give_up(s.caught or s.stop)
        end
        spoke = true
        if not settled then c:reveal('talk') end
    end)
    c:on('fact', function(who, fact)
        if fact == 'c_hook' then open_hook() end
        if who ~= 'subject' or fact ~= 'c_out' or settled then return end
        agreed, leaving = true, 3 -- (long enough to read the answer)
        c:set('walked', true)
    end)
    c:on('inspect', function(clue) if clue == 'gate' then open_hook() end end)
    c:on('act', function(who, action, arg)
        if who ~= 'subject' then return end
        if action == 'cuff' and c:who('subject').cuffed and not settled then
            if not agreed then c:set('rushed', true) end
            return over()
        end
        if action ~= 'ask' then return end
        if PUSH[arg] then press() end
        if GOOD[arg] and not asked[arg] and not settled and (arg ~= 'c_key' or hooked) then
            asked[arg], heat = true, math.max(0, heat - 1)
            gain(GOOD[arg])
        end
    end)
    c:on('aimed', function(who)
        if who ~= 'subject' or clock - aim_at < PUSH_GAP or not free() then return end
        aim_at = clock
        c:set('aimed', true)
        press(s.gun)
    end)
    c:on('fired', function(who)
        if who ~= 'subject' then return end
        c:set('fired', true)
        c:reveal('gunman')
        c:dispatch('Shots fired! All units, shots fired!')
        c:note('The subject fired at officers')
    end)
    c:on('hail', function(who)
        if who == 'subject' and fighting and math.random() < 0.5 then give_up(s.stop) end
    end)
    c:on('tick', function()
        clock = clock + 1
        local o = c:who('subject')
        if not o or o.cuffed or settled or c:get('dead_subject') then return end
        if fighting then
            local health = c:health('subject')
            left = c:near('subject', 45.0) and left - 1 or left
            if health and health > 100 and health < 150 then give_up("Okay! Okay, I'm hit! I'm done!")
            elseif left <= 0 then give_up(s.stop) end
            return
        end
        if leaving then
            leaving = leaving - 1
            if leaving > 0 then return end
            leaving, walking = nil, WALK
            if s.item then leave_behind(c, s.item) end
            c:done('talk')
            c:hangup('subject')
            c:task('subject', 'go', 'out')
            c:note('The subject agreed to come out')
            return
        end
        if walking then
            walking = walking - 1
            if walking <= 0 then give_up(s.out) end
            return
        end
        if shut > 0 then
            shut = shut - 1
            if shut == 0 then c:task('subject', 'scene') end
            return
        end
        if clock >= cool_at then
            cool_at, heat = clock + COOL, math.max(0, heat - 1)
        end
        if spoke and heat == 0 and clock % PATIENCE == 0 then gain(1) end
        if not agreed and clock - crowd_at >= PUSH_GAP and c:near('subject', CROWD) then
            crowd_at = clock
            press(s.crowd)
        end
        if not free() or c:talking() or clock < next_rant or not c:near('subject', 30.0) then return end
        next_rant = clock + 25
        c:say('subject', s.rants[rant])
        rant = rant % #s.rants + 1
    end)
    return { free = free, press = press, bolt = bolt, gain = gain }
end

--[[ It's over when they've been taken in, seen to by paramedics, let go or got away (run from units who've lost them: 20 s with
     nobody within 100 m), with everyone arrested taken in; or the caller's been heard, contact made and every unit has left. Dead,
     the card says to call paramedics and it goes on until they're pronounced or the coroner's been. ends(out) -> the MDT summary;
     out.subject and out.caller = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' | 'pronounced' | 'hospital' |
     'treated' | 'gone'; out.left = true. ]]
local function resolve(c, ends)
    local out, taken, away_for, lost_for, done = {}, {}, 0, 0, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local OVER = { released = true, cited = true, warning = true, fled = true, pronounced = true, hospital = true, treated = true, gone = true }
    local function check()
        if done or waiting() then return end
        if not (taken.subject or OVER[out.subject] or out.left) then return end
        done = true
        c:done('decide')
        c:finish(ends(out))
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
        if who ~= 'subject' then return check() end
        c:set('dead_subject', true)
        c:set('loose', false)
        for _, id in ipairs({ 'caller', 'rear', 'subject', 'relative', 'hook', 'talk', 'gunman', 'decide' }) do c:done(id) end
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
        elseif outcome == 'released' and not out[who] then out[who] = 'released'
        elseif (outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        check() -- (walked off from them, 'cancelled': nothing decided)
    end)
    c:on('tick', function()
        lost_for = c:get('loose') and not c:near('subject', 100.0) and lost_for + 1 or 0
        if lost_for >= 20 and not out.subject then
            out.subject = 'fled'
            return check()
        end
        local here = c:near(nil, 80.0) or c:near('subject', 80.0) or c:talking() or c:get('loose') -- (run: the 20 s above decides)
        if c:is_done('caller') and c:is_done('subject') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then out.left = true check() end
        else
            away_for = 0
        end
    end)
    return out
end

-- What the summary says, whichever story it was: what became of them, how it went, then whatever the story adds.
local function report(c, out, s)
    local n, how = c:name('subject'), out.subject
    local text
    if how == 'arrested' then text = ('%s: %s arrested.'):format(s.what, n)
    elseif how == 'hospital' then text = ('%s: %s went with paramedics.'):format(s.what, n)
    elseif how == 'treated' then text = ('%s: %s was seen by paramedics at the scene.'):format(s.what, n)
    elseif how == 'dead' or how == 'pronounced' then text = ('%s: %s died at the scene.'):format(s.what, n)
    elseif how == 'fled' then text = ('%s: %s got away.'):format(s.what, n)
    elseif how == 'cited' or how == 'warning' then text = ('%s: %s was given a %s.'):format(s.what, n, how == 'cited' and 'ticket' or 'warning')
    elseif how == 'released' then text = ('%s: %s was spoken to and let go.'):format(s.what, n)
    elseif how == 'gone' then text = ('%s: %s was removed from the scene.'):format(s.what, n)
    elseif c:get('over') then text = ('%s: %s came out and was left at the scene.'):format(s.what, n)
    else text = ('%s: units left with %s still inside.'):format(s.what, n) end
    if c:get('walked') then text = text .. ' Talked out by officers.' end
    if c:get('rushed') then text = text .. ' Taken before they agreed to come out.' end
    if c:get('ran') then text = text .. ' They ran out of the back.' end
    if c:get('aimed') then text = text .. ' A weapon was pointed at them.' end
    if c:get('warning') then text = text .. ' A warning shot came from inside.' end
    if c:get('fired') then text = text .. ' They fired on officers.' end
    return text .. (s.after and s.after(c, out) or '')
end

-- One story, from its table. s = { what (for the report), male?, model?, age, secret?, weapon?, item? (what they leave inside), items?, key
-- (the question that fits), caller, relative?, lines (their lines), rants, gun (a gun on them), crowd (someone too close),
-- warn (reacting), stop (giving up), out (walking out: hands up), caught?, gate (the clue's text), not_yet? and clear? (the terms wait for
-- clear(c)), patient? (paramedics), fires?, on_hook? (c), setup? (c, api), after? (c, out) }
local function play(c, s)
    s.lines.where = s.lines.where or { "Nowhere. That's the whole point." }
    s.lines.c_terms = function(o)
        if o.facts.c_out then return { "I said I'm coming." } end
        if s.clear and not s.clear(c) then return s.not_yet end
        return { { s.terms, set = { c_out = 'yes' } } }
    end
    local q = { { id = 'c_key', label = s.key, needs = { c_hook = true } } }
    for _, x in ipairs(SUBJECT_Q) do q[#q + 1] = x end
    c:person('caller', { at = 'caller', label = 'Caller', male = s.caller_male, secret = s.caller_secret or 'clean', demeanor = s.caller_demeanor,
        scene = 'WORLD_HUMAN_STAND_MOBILE', questions = CALLER_Q, lines = s.caller })
    c:person('subject', { at = 'subject', label = 'Person', male = s.male, model = s.model, age = s.age, home = true, secret = s.secret or 'clean',
        demeanor = 'nervous', items = s.items or {}, weapon = s.weapon, reach = REACH, scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = q, lines = s.lines })
    if s.relative then
        c:person('relative', { at = 'relative', label = 'Relative', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = RELATIVE_Q, lines = s.relative })
    end
    c:clue('gate', { at = 'gate', label = 'By the entrance', text = s.gate })
    c:clue('rear', { at = 'rear', label = 'The back way', text = 'The only other way out. You run a chain through it and lock it. Nobody is getting out here now.' })
    card(c)
    wire(c)
    local api = standoff(c, s)
    resolve(c, function(out) return report(c, out, s) end)
    if s.setup then s.setup(c, api) end
end

Callout({
    id = 'barricade',
    name = 'Barricaded subject',
    voice = 'call_barricade', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        "Caller says someone has locked themselves inside and won't come out. There may be a gun.",
        "Person shut inside, refusing to open up. Caller thinks they're armed.",
        'Caller reports someone has blocked the door and is shouting at anyone who comes near.',
    },
    -- The points each location needs, in the order /c3rplace barricade walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it).
    -- Skip the optional ones with Z in /c3rplace: without `window` the cornered story doesn't play there; without `relative`
    -- nobody comes, and what's by the entrance has to do.
    points = {
        { 'caller', 'The caller: at a safe distance, on the street, 40 m or so from the place.' },
        { 'subject', 'Who is shut in: somewhere they can walk out of, like a garage, a doorway, a balcony or a shed. Units stand 10 m or so off and talk.' },
        { 'out', 'Open ground in front of them, within 10 m: where they walk out to.' },
        { 'gate', 'By the entrance: a gate, a mailbox or a fence, 10 m or so from them.' },
        { 'rear', 'The only other way out: a back gate or back door, round the far side.' },
        { 'window', 'Where they fire from if it comes to that: a window or doorway, close to them, facing the street.', optional = true },
        { 'relative', 'A relative who has come to help: back behind the cars, on the phone.', optional = true },
    },
    -- Add more with /c3rplace barricade in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Forum Dr', at = vector3(-29.50, -1453.99, 31.01), points = {
            caller = vector4(-29.50, -1453.99, 31.01, 239.8),
            subject = vector4(-15.39, -1439.35, 31.10, 165.0),
            out = vector4(-13.81, -1447.35, 30.65, 168.5),
            gate = vector4(-12.72, -1450.47, 30.54, 166.9),
            rear = vector4(-20.38, -1428.43, 30.66, 334.6),
            window = vector4(-10.43, -1441.80, 31.10, 216.3),
        } },
        { street = 'Amarillo Vista', at = vector3(1286.90, -1735.66, 52.94), points = {
            caller = vector4(1286.90, -1735.66, 52.94, 48.9),
            subject = vector4(1273.64, -1718.41, 54.77, 208.2),
            out = vector4(1276.76, -1724.79, 54.66, 204.0),
            gate = vector4(1279.93, -1729.15, 52.56, 206.5),
            rear = vector4(1267.66, -1714.35, 54.66, 66.2),
            window = vector4(1275.89, -1721.56, 54.66, 197.4),
        } },
    },

    stories = {
        -- ── Put out early. ───────────────────────────────────────────────────────────────────────────────────────
        eviction = {
            weight = 3,
            setup = function(c)
                play(c, {
                    what = 'Barricaded tenant, facing an early eviction',
                    male = true,
                    age = { 58, 72 },
                    weapon = 'WEAPON_PUMPSHOTGUN',
                    item = 'Pump shotgun, loaded',
                    items = { 'Pump shotgun, loaded' },
                    key = "I've read the notice. It gives you eighteen more days. He can't put you out today.",
                    caller_male = true,
                    caller_demeanor = 'rude',
                    caller = {
                        c_what = { "I came to change the locks and he's jammed the door. Then he showed me a shotgun through the gap. Me! It's my property!" },
                        c_who = { "My tenant. Twenty-odd years he's been in there, and now he's a problem." },
                        c_gun = { "A shotgun. Old thing. I didn't stay to look at it." },
                        c_why = { { "He's had his notice! Thirty days. Near enough. I've got buyers coming Friday.", set = { c_hook = 'yes' } } },
                    },
                    lines = {
                        c_name = { "My name's on twenty-two years of rent cheques. You can use that." },
                        c_listen = { "I pay on time. Every month. Then he turns up with a drill and a man with a van." },
                        c_want = { "I want him off my step. I want to go out of here on my own feet, when it's time. Not today." },
                        c_key = { "Eighteen? ...You read it? Nobody reads it. Nobody's read one word I've said. ...Eighteen days." },
                        c_order = { "I'm in my home! Who are you to order me out of it?" },
                        c_force = { "Then you'd better come ready, son!" },
                        explain = { "It was my father's. I only ever took it out to clean it. I never loaded it till today." },
                    },
                    rants = { "This is my home! You hear me? Twenty-two years!", "Get him off my property!", "I've got rights! Somebody read the damn paper!" },
                    gun = "You point that at me in my own home? Put it down!",
                    crowd = "That's far enough! You stay right there!",
                    warn = "That's your warning! I'm done talking!",
                    stop = "Alright! Alright. It's down. I'm an old man. It's down.",
                    terms = "Eighteen days. You'll put that in writing? ...Alright. It stays on the table. I'm coming out.",
                    out = "Here. Here I am. Hands are empty.",
                    gate = "The eviction notice, stapled to the post. Thirty days' notice, served twelve days ago: he has eighteen left. A new padlock still in its packet is lying under it.",
                    after = function(cc, out)
                        return out.caller == 'cited' and (' %s, the landlord, was ticketed for trying to lock out a tenant.'):format(cc:name('caller')) or ''
                    end,
                })
            end,
        },

        -- ── The one who called is who she's hiding from. ─────────────────────────────────────────────────────────
        refuge = {
            weight = 2,
            setup = function(c)
                play(c, {
                    what = 'Barricade, a woman hiding from her ex-partner',
                    male = false,
                    age = { 26, 44 },
                    weapon = 'WEAPON_PISTOL',
                    item = 'Pistol, registered to her, loaded',
                    items = { 'Pistol, registered to her, loaded' },
                    key = 'We know who kicked that in. He is not getting past us. Talk to me.',
                    caller_male = true,
                    caller_secret = 'warrant',
                    caller_demeanor = 'polite',
                    caller = {
                        c_what = { "My partner's lost it. She's locked me out and she's got a gun. She needs help, officer. I'm worried about her." },
                        c_who = { "My girlfriend. Well. It's complicated. Just get the door open and let me talk to her." },
                        c_gun = { "A pistol. She bought it a few months back. For no reason. See? That's what I'm saying." },
                        c_why = { "You tell me. She's not well. Everybody's against her, to hear her tell it." },
                        c_door = cracks(2, { "Kicked in? Must've been like that. It's an old place." },
                            { { "...She wouldn't answer. I only want to talk. She can't keep me out forever. Paper or no paper.", set = { c_admit = 'yes' } } },
                            { "I told you. I only wanted to talk." }),
                    },
                    lines = {
                        c_name = { "Is he still out there? Tell me first. Is he out there?" },
                        c_listen = { "I got a court order. I got a new address. It took him four months to find me." },
                        c_want = { "I want him gone. I don't want to hurt anybody. I just want him to stop." },
                        c_key = { "...You know? You're the first one who's asked. Every time, he's the one who's so calm, and I'm the one who's crazy." },
                        c_order = { "So you can hand me over to him? No! He told you I'm crazy, didn't he?" },
                        c_force = { "Don't! Please! If you open this, he comes through it!" },
                        explain = { "It's registered. It's mine. I've got the papers, and I've got the order against him too." },
                    },
                    rants = { "Get him away from me!", "I have a court order! Ask him! Ask him about the order!", "He's lying! Whatever he said, he's lying!" },
                    gun = "No! No, you're on his side! Don't point that at me!",
                    crowd = "Stay back! Who is that? Is that him?",
                    warn = "Stay away from this door! I mean it!",
                    stop = "Okay. Okay. It's down. Please don't let him near me.",
                    terms = "He's really gone? ...Okay. It's on the floor. I'm coming out. Stay where I can see you.",
                    not_yet = { "Not while he's out there. Not while he's free. Deal with him and I'll come out, I swear." },
                    out = "I'm here. I've got nothing. Is it over?",
                    gate = "The gate latch is torn off and there are boot marks on it, on the outside. In the mailbox, a court letter: a protective order, the address blacked out by hand.",
                    clear = function(cc)
                        local o = cc:who('caller')
                        return not o or o.cuffed or cc:get('caller_away')
                    end,
                    on_hook = function(cc)
                        cc:who('caller').facts.c_kicked = 'yes'
                        cc:questions('caller')
                        cc:dispatch('That address is on a protective order. Check who you are talking to out there.')
                    end,
                    setup = function(cc, api)
                        local told = false
                        local function away()
                            cc:set('caller_away', true)
                            if told then return end
                            told = true
                            cc:say('subject', "Is he gone? Is that him leaving?")
                            api.gain(1)
                        end
                        cc:on('contact_ended', function(who, outcome)
                            if who ~= 'caller' or outcome == 'cancelled' or outcome == 'arrested' then return end
                            away()
                            if outcome ~= 'fled' then cc:task('caller', 'wander') end
                        end)
                        cc:on('gone', function(who) if who == 'caller' then away() end end)
                        cc:on('dead', function(who) if who == 'caller' then away() end end)
                        cc:on('act', function(who, action) if who == 'caller' and action == 'cuff' and cc:who('caller').cuffed then away() end end)
                    end,
                    after = function(cc, out)
                        local n = cc:name('caller')
                        if out.caller == 'arrested' then return (' %s, her ex-partner, was arrested for breaching a protective order.'):format(n) end
                        return (' %s, her ex-partner, was not arrested.'):format(n)
                    end,
                })
            end,
        },

        -- ── Nothing left. ────────────────────────────────────────────────────────────────────────────────────────
        despair = {
            weight = 2,
            setup = function(c)
                play(c, {
                    what = 'Barricaded man in distress',
                    male = true,
                    age = { 38, 58 },
                    key = 'People are worried about you. I know about your daughter. Tell me about her.',
                    patient = true,
                    caller = {
                        c_what = { "He's not answered in days. Today I could hear him moving things against the door. He told me to go away and stop worrying." },
                        c_who = { "A friend of mine, from work. From when he had work." },
                        c_gun = { "I don't know. I don't think so. I said that because I got scared." },
                        c_why = { { "He lost the job, then the house, then she took their girl to her mother's. His brother's been ringing me. He's on his way.", set = { c_family = 'yes' } } },
                    },
                    relative = {
                        c_who = { "I'm his brother. He won't pick up. Please tell me he's okay." },
                        c_help = { { "Don't talk about the job. Talk about Ellie. She's nine. He'd walk through a wall for that kid.", set = { c_hook = 'yes' } } },
                    },
                    lines = {
                        c_name = { "It doesn't matter what you call me." },
                        c_listen = { "There's nothing to tell. It's all gone. I'm so tired." },
                        c_want = { "I want it to be quiet. I don't want anyone to get hurt. You should go home." },
                        c_key = { "...She's nine. She's got this laugh. ...Who told you about her? Somebody's asking after me?" },
                        c_order = { "Please don't shout. I can't. I just can't." },
                        c_force = { "Then come in. It doesn't matter." },
                        explain = { "I haven't done anything. I'm not going to hurt anyone." },
                    },
                    rants = { "Go home. Please. Everybody go home.", "There's nothing here for you.", "I'm sorry. Tell them I'm sorry." },
                    gun = "You don't need that. I'm not going to hurt you.",
                    crowd = "Please. Just leave me be.",
                    warn = "I'm done. I'm done talking.",
                    stop = "Okay.",
                    terms = "...Alright. Will you stay with me? Don't let them see me like this. ...Okay. I'm coming out.",
                    out = "I'm here. I'm so tired.",
                    gate = "The mailbox is jammed with unopened letters, the red kind. On top is a child's drawing in crayon, three people and a dog, with a phone number on the back: 'Uncle Dan'.",
                })
            end,
        },

        -- ── He hurt someone, and he ran here. ────────────────────────────────────────────────────────────────────
        cornered = {
            weight = 2,
            needs = { 'window' },
            setup = function(c)
                play(c, {
                    what = 'Barricaded assault suspect',
                    male = true,
                    age = { 24, 40 },
                    secret = 'nervous',
                    weapon = 'WEAPON_PISTOL',
                    item = 'Pistol, loaded, black',
                    items = { 'Pistol, loaded, black' },
                    key = 'The man you hit is alive. He is stable. This is not what you think it is.',
                    fires = true,
                    caller = {
                        c_what = { "A guy came running up the road, hand all bloody, and forced his way in. He's jammed it shut behind him. He had a gun in his belt." },
                        c_who = { { "No idea. It's not his place, I'd say. He didn't have a key. There's an older brother rents it. He's been ringing round.", set = { c_family = 'yes' } } },
                        c_gun = { "In his belt. A pistol, I think. He kept touching it." },
                        c_why = { "He kept looking back up the road, like somebody was after him. Then he saw me and shouted to call nobody." },
                    },
                    relative = {
                        c_who = { "He's my brother. He rang me crying. He said he thinks he killed a man." },
                        c_help = { { "He hit a guy at the bar. One punch, the guy went down and didn't get up. If he finds out the guy's alive, he'll stop. He won't believe it from me.", set = { c_hook = 'yes' } } },
                    },
                    lines = {
                        c_name = { "Don't try that. I know what you're doing." },
                        c_listen = { "It was one punch. One! He went down and he didn't move. There was blood everywhere." },
                        c_want = { "I want you all to back up, and I want to think. I can't go down for this." },
                        c_key = { "...Alive? You swear? He's alive? ...Oh, God. I thought... I've been in here thinking..." },
                        c_order = { "You want me out? Come and get me out!" },
                        c_force = { "Come through that door and see what happens!" },
                        explain = { "It's not even mine. I don't know why I took it. I don't know what I'm doing." },
                    },
                    rants = { "Back off! Everybody back off!", "I need to think! Just let me think!", "I'm not going to prison for this!" },
                    gun = "Get that off me! I see you! I see every one of you!",
                    crowd = "One more step! One more!",
                    warn = "That's the only warning you get!",
                    stop = "Alright! Alright, I'm putting it down! Don't shoot!",
                    terms = "...It's on the side. I'm not touching it. I'm coming out, okay? Don't shoot me. Tell them don't shoot.",
                    out = "Hands up. See? Hands up. Nobody shoot.",
                    caught = "Okay! Okay! I'm done. I'm done.",
                    gate = "Blood on the latch, still wet, and a boot-shaped dent where it was forced. Someone came through here in a hurry.",
                    on_hook = function(cc)
                        cc:dispatch("Dispatch: fight at a bar near you twenty minutes ago. Male victim at Pillbox with a broken jaw. He's stable. The other party matches who you've got.")
                    end,
                    setup = function(cc, api)
                        local at = nil -- (a few minutes after the first unit's there, he tries the back)
                        cc:on('arrive', function() at = at or math.random(180, 240) end)
                        cc:on('tick', function()
                            if not at then return end
                            at = at - 1
                            if at > 0 or not api.free() then return end
                            at = nil
                            if cc:is_done('rear') then
                                api.press("The back's chained! You've got me boxed in!")
                            else
                                api.bolt()
                            end
                        end)
                    end,
                })
            end,
        },

        -- ── Not a gun. ───────────────────────────────────────────────────────────────────────────────────────────
        drill = {
            weight = 1,
            setup = function(c)
                play(c, {
                    what = 'Reported armed barricade, in fact an old man boarding up his door',
                    male = true,
                    age = { 74, 88 },
                    model = 'a_m_o_genstreet_01',
                    items = { 'Cordless nail gun' },
                    key = 'PUT YOUR HEARING AIDS IN!',
                    caller = {
                        c_what = { "I came with a parcel. He's in there nailing boards over the way in, and he pointed a gun at me and went bang bang bang." },
                        c_who = { "Some old fella. I just do the deliveries." },
                        c_gun = { "Long thing, with a handle. I wasn't going to stand there and ask." },
                        c_why = { "He shouted something about raccoons. I'm not paid enough for this." },
                    },
                    lines = {
                        c_name = { "WHAT? SPEAK UP!" },
                        c_listen = { "NO, I DON'T WANT ANY! I TOLD THE OTHER FELLA!" },
                        c_want = { "THEY'VE HAD THE WHOLE BIN! THREE TIMES! I'LL HAVE THE LOT OF THEM!" },
                        c_key = { "Oh! Hang on. There we are. Why didn't you say? What's all this, then? Are those police cars?" },
                        c_order = { "WHAT? WHO'S THAT SHOUTING?" },
                        c_force = { "THERE'S NO NEED TO BE RUDE!" },
                        explain = { "It's a nail gun, you daft sod. Mind, it's good for raccoons." },
                    },
                    rants = { "COME ON THEN, YOU LITTLE BANDITS!", "I SEE YOU BEHIND THE BINS!", "NOT THIS TIME! NOT THIS TIME!" },
                    gun = "IS THAT A TORCH? GET IT OUT OF MY EYES!",
                    crowd = "WHO'S THAT? IF YOU'RE SELLING, I DON'T WANT IT!",
                    warn = "RIGHT! I'M NOT LISTENING TO ANY MORE OF THIS!",
                    stop = "ALRIGHT! ALRIGHT! KEEP YOUR HAIR ON!",
                    terms = "Come out? I'll have to take a board off. Hold on, hold on. I'm coming.",
                    out = "Now then. What's all the fuss? Is it the raccoons?",
                    gate = "A carton of nails and a torn packet of hearing-aid batteries on the post. Behind it, a bin that has been ripped open, with small muddy paw prints all over the lid.",
                })
            end,
        },
    },
})
