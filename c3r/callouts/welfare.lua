--[[
    c3r callout: WELFARE CHECK.

    Someone can't reach a person they're worried about, and they're outside the house. The report is the same every time, and
    the card is too: the caller, the neighbour, the front door and round the back (four units can take one each). What's
    really happened is one of five stories:
      fall      they fell off a ladder days ago and have been lying round the back ever since
      natural   they died quietly at home: the coroner, then telling the caller
      hiding    the caller is an ex under a restraining order, using police to find someone who ran from them. The card says
                to let the caller know, as it always does; tell them before you've heard the person out and they go for them
      intruder  nobody's in trouble but the house: they're on a cruise, and the "house sitter" broke in
      carer     the carer at the door has shut them away round the back and is living off their money
    It's dealt with when they've been reached, anyone hurt or dead has been seen to, anyone arrested has been taken in, whoever's
    responsible has been dealt with and the caller has been told; or the caller's been heard, the door and the back have been
    checked and every unit has left.

    Points per location: walk them out in game with /c3rplace welfare (it writes the location in below).
]]

local CALLER_Q = {
    { id = 'c_who', label = 'Who are we looking for?' },
    { id = 'c_last', label = 'When did you last hear from them?' },
    { id = 'c_worry', label = 'What has you worried?' },
    { id = 'c_know', label = 'How do you know them?', stress = true, press = true },
    { id = 'c_news', label = 'I have news about them.', needs = { c_found = true } },
    { id = 'c_quiet', label = "I can't tell you anything about them.", needs = { c_hide = true } },
}
local NEIGHBOUR_Q = {
    { id = 'c_seen', label = 'When did you last see them?' },
    { id = 'c_who', label = 'Who lives there?' },
    { id = 'c_odd', label = 'Anything unusual lately?' },
}
local OTHER_Q = { -- (whoever's at the house, in the stories with someone there)
    { id = 'c_who', label = 'Who are you?', stress = true },
    { id = 'c_them', label = 'Where is the person who lives here?', stress = true },
    { id = 'c_see', label = 'I need to see them.', stress = true, press = true },
    { id = 'c_put', label = 'We know what has been going on here.', needs = { c_back = true }, stress = true, press = true },
}
local SUBJECT_Q = {
    { id = 'c_ok', label = 'Are you alright?' },
    { id = 'c_caller', label = 'Someone out front is asking for you.', stress = true },
    { id = 'c_how', label = 'How did they find you?', needs = { c_hide = true } },
}
local AWAY = vector3(-6000.0, -6000.0, 0.0) -- (out at sea: a real record to run, and no unit ever near enough to make them)
local PARENT = { 'father', 'mother' }
local ELDERLY = { 'a_m_o_genstreet_01', 'a_f_o_genstreet_01' }

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
    c:objective('caller', 'Talk to the caller', { hint = 'Waiting outside the house.', blip = 'caller' })
    c:objective('neighbour', 'Talk to the neighbour', { hint = 'Next door.', blip = 'neighbour' })
    c:objective('door', 'Try the front door', { hint = 'Is anyone home?', blip = 'door' })
    c:objective('back', 'Check round the back', { hint = 'Gates, windows, the yard.', blip = 'back' })
    c:objective('medic', 'Call paramedics', { hidden = true, who = 'all', blip = 'subject', hint = 'Radio for an ambulance.' })
    c:objective('coroner', 'Call the coroner', { hidden = true, who = 'all', blip = 'subject', hint = 'By radio.' })
    c:objective('tell', 'Let the caller know', { hidden = true, who = 'all', blip = 'caller', hint = 'Still waiting out front.' })
    c:objective('breakup', 'Keep them apart', { hidden = true, who = 'all', blip = 'caller', hint = 'Press E beside them, or the PA with your gun out. If they will not stop, the taser will.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { hidden = true, who = 'all' })
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

-- Done when: the caller's said who it is, the neighbour's said when they last saw them, the door's been looked at or
-- whoever's there spoken to, the back's been looked at or they've been reached, the caller's been told.
-- -> seen(): they've been found (or, on a cruise, heard from), and the caller can be told. s.reached (c) follows.
local function wire(c, s)
    local function seen()
        if c:get('seen') then return end
        c:set('seen', true)
        c:done('back')
        c:reveal('tell')
        if c:get('body') then c:reveal('coroner')
        elseif s.hurt then hurt(c, 'subject') end
        local o = c:who('caller')
        if o then
            o.facts.c_found = 'yes'
            c:questions('caller')
        end
        if s.reached then s.reached(c) end
    end
    c:on('act', function(who, action, arg)
        if action ~= 'ask' then return end
        if who == 'caller' and arg == 'c_who' then c:done('caller') end
        if who == 'neighbour' and arg == 'c_seen' then c:done('neighbour') end
    end)
    c:on('contact', function(who)
        if who == 'other' then c:done('door') end
        if who == 'subject' then seen() end
    end)
    c:on('inspect', function(clue)
        if clue == 'door' then c:done('door') end
        if clue == 'back' then c:done('back') end
        if clue == 'car' then c:set('car_seen', true) end
    end)
    c:on('fact', function(_, fact)
        if fact == 'c_told' or fact == 'c_quiet' then c:done('tell') end
    end)
    c:on('tick', function()
        if not s.away and c:near('subject', 8.0) then seen() end -- (out of sight of the street: place them so, and it's the same)
    end)
    c:on('aid', function(who, what) -- (an ambulance called from the door: taken before anyone walked round)
        if who == 'subject' and (what == 'hospital' or what == 'treated' or what == 'pronounced') then seen() end
    end)
    c:on('gone', function(who) if who == 'subject' then seen() end end)
    c:on('dead', function(who)
        if who == 'caller' or who == 'neighbour' then c:done(who) end
    end)
    return seen
end

--[[ The caller told where they are, before anyone's dealt with them. When the officer's done talking they walk round there;
     within 10 m it's fists, both of them, until told to stop (half the time), tased, or 45 s with units near, when the one
     who's lost goes down. After 60 s without getting there (no way through, or nobody left to get to) they give up. Spoken to
     on the way, they carry on afterwards. While it's going on (`wild`), and until the person they're after has been heard or
     they've been told, letting them go doesn't count: there's more to find out. -> ready() ]]
local function trap(c)
    local state, walking, left, ordered = nil, 60, 45, false
    local function calm(line)
        state = 'over'
        c:done('breakup')
        if line ~= nil then
            c:task('caller', 'surrender')
            if (c:health('subject') or 0) > 100 then c:task('subject', 'scene') end
            if line then c:say('caller', line) end
            c:note('The caller went for them and was stopped')
        end
    end
    c:on('fact', function(_, fact)
        if fact ~= 'c_told' then return end
        c:set('heard', true)
        if c:who('caller').cuffed then return end
        state = 'told'
        c:set('wild', true)
    end)
    c:on('act', function(who, action)
        if who ~= 'caller' or action ~= 'cuff' or not c:who('caller').cuffed or not c:get('wild') then return end
        c:set('wild', false)
        calm()
    end)
    c:on('contact_ended', function(who, outcome)
        if who == 'subject' then c:set('heard', true) end
        if who ~= 'caller' then return end
        if outcome == 'fled' then
            c:set('wild', false)
            return calm()
        end
        if state == 'over' and outcome ~= 'cancelled' then c:set('wild', false) end -- (the fight's over, and now they've been dealt with)
        if state ~= 'told' then return end
        state = 'walking'
        c:reveal('breakup')
        c:reveal('decide')
        c:say('caller', "I knew it. I knew they were here.")
        c:task('caller', 'go', 'found')
    end)
    local function order()
        if state ~= 'fighting' or ordered then return end
        ordered = true
        if math.random() < .5 then calm("Alright! Alright! Get off me!")
        else c:say('caller', "You're not getting away from me again!") end
    end
    c:on('hail', function(who) if who == 'caller' or who == 'subject' then order() end end)
    c:on('stunned', function(who)
        if (who == 'caller' or who == 'subject') and state == 'fighting' then calm("Okay! Okay! I'm done!") end
    end)
    local function lost(who) -- (dead, or taken away: there's nobody left to fight, or nobody left to deal with)
        if who ~= 'caller' and who ~= 'subject' then return end
        if who == 'caller' then c:set('wild', false) else c:set('heard', true) end
        if state == 'walking' or state == 'fighting' then calm(false) end
    end
    c:on('dead', lost)
    c:on('gone', lost)
    local function beaten(key) -- (a ped just made reads 0: not beaten, not there yet)
        local h = c:health(key)
        return h and h > 100 and h < 120
    end
    c:on('tick', function()
        if state == 'walking' and not c:talking('caller') then
            walking = walking - 1
            if not c:apart('caller', 'subject') then
                state = 'fighting'
                c:say('caller', "You thought you could hide from me?")
                c:task('caller', 'brawl', 'subject')
                c:task('subject', 'brawl', 'caller')
            elseif walking <= 0 then
                c:set('wild', false)
                c:task('caller', 'scene')
                calm()
            end
        elseif state == 'fighting' then
            if c:near('caller', 60.0) then left = left - 1 end
            local hit = beaten('subject') and 'subject' or beaten('caller') and 'caller'
            if left > 0 and not hit then return end
            calm(false)
            hit = hit or 'subject'
            if hit == 'caller' then c:set('wild', false) end
            c:collapse(hit)
            hurt(c, hit)
            c:dispatch('One of them is down. Paramedics needed at the scene.')
        end
    end)
    return function() return c:get('heard') and not c:get('wild') end
end

--[[ It's over when they've been reached, everyone arrested has been taken in, everyone hurt or dead has been seen to, the one
     responsible (culprit, if any) has been dealt with and the caller's been told; or the caller's been heard, the door and the
     back have been checked and every unit has left. ready(): false, letting the culprit go doesn't count yet.
     ends(out) -> the MDT summary; out[person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' | 'pronounced' |
     'hospital' | 'treated'; out.left = true. ]]
local function resolve(c, culprit, ends, ready)
    local out, taken, away_for, done = {}, {}, 0, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local LET_GO = { released = true, cited = true, warning = true, fled = true, dead = true, pronounced = true, hospital = true, treated = true }
    local SEEN = { hospital = true, treated = true, pronounced = true }
    local function all_seen()
        for who in pairs(c:get('hurts') or {}) do
            if not (SEEN[out[who]] or taken[who]) then return false end
        end
        return true
    end
    local function check()
        if done or waiting() then return end
        local dealt = not culprit or taken[culprit] or (LET_GO[out[culprit]] and (not ready or ready()))
        if not (out.left or (c:get('seen') and dealt and all_seen() and c:is_done('tell'))) then return end
        done = true
        c:done('decide')
        c:finish(ends(out))
    end
    local function let_go(who, how) -- (not the culprit, until there's nothing left to find out)
        out[who] = (who ~= culprit or not ready or ready()) and how or nil
    end
    local function dealt_with(who) -- (a caller who's the culprit, dealt with, needs no telling)
        if who ~= culprit then return end
        c:done('decide')
        if who == 'caller' then c:done('tell') end
    end
    c:on('act', function(who, action)
        local o = c:who(who)
        if action == 'cuff' and o and o.cuffed then
            out[who] = 'arrested'
            c:custody(who)
            if who == culprit then c:hide('decide') end -- (off the card, not done: they can be uncuffed)
            if who == culprit and who == 'caller' then c:done('tell') end
        elseif action == 'uncuff' and out[who] == 'arrested' then
            out[who] = nil
            c:hide('custody:' .. who)
            if who == culprit then c:reveal('decide') end
        elseif (action == 'cite' or action == 'warn') and out[who] ~= 'arrested' then
            let_go(who, action == 'cite' and 'cited' or 'warning')
        end
    end)
    c:on('custody', function(who)
        taken[who] = true
        if who == 'caller' then c:done('tell') end
    end)
    local function seen_to(who, how)
        out[who] = how
        c:hide('custody:' .. who)
        if all_seen() then c:done('medic') end
        if who == 'subject' then c:done('coroner') end
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if who == 'caller' then c:done('tell') end
        -- (the coroner's been; or an ambulance the call didn't hear about)
        if (c:get('hurts') or {})[who] and not SEEN[out[who]] then seen_to(who, (out[who] == 'dead' or (who == 'subject' and c:get('body'))) and 'pronounced' or 'hospital') end
        if who == culprit and not out[who] then
            out[who] = 'fled'
            dealt_with(who)
        end
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        dealt_with(who)
        if who == 'caller' then c:done('tell') end
        local list = c:get('hurts') or {}
        list[who] = who == 'subject' or list[who] -- (the ending waits for the coroner)
        c:set('hurts', list)
        if who ~= 'subject' then return end
        c:set('body', true)
        c:done('medic')
        if c:get('seen') then c:reveal('coroner') end
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' then return seen_to(who, 'pronounced') end
        -- ponytail: paramedics called to a body bring it back Config.Medical.paramedic_revive of the time, even in `natural`
        -- (the card says coroner), and CPR can if the game saw the ped alive. The summary and the caller follow; brought back by
        -- CPR with no ambulance after it, leaving is the only way out. A no-revive option on the person would stop both.
        if (what == 'hospital' or what == 'treated') and not SEEN[out[who]] then
            if who == 'subject' and c:get('body') then c:set('revived', true) end
            seen_to(who, what)
        end
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or SEEN[out[who]] then return end
        if outcome == 'fled' then
            out[who] = 'fled'
            if who == 'caller' then c:done('tell') end
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then
            let_go(who, outcome)
        end
        if LET_GO[out[who]] and (not ready or ready()) then dealt_with(who) end
    end)
    c:on('tick', function() -- (everything's dealt with in any order: one place to look)
        check()
        local here = c:near(nil, 80.0) or c:near('caller', 80.0) or c:near('subject', 80.0) or c:near('other', 80.0) or c:talking()
        if c:is_done('caller') and c:is_done('door') and c:is_done('back') and not waiting() and not here then
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

-- One person's part in the summary.
local function part(c, out, who)
    if not c:who(who) then return '' end
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

-- What the summary says, whichever story it was. s = the story's table.
local function report(c, out, s)
    local how, text = out.subject, ('Welfare check: %s was not found.'):format(c:name('subject'))
    if c:get('revived') then
        text = 'Welfare check: found unresponsive at home and brought back.' .. part(c, out, 'subject')
    elseif c:get('seen') and s.safe and (not how or how == 'released') then
        text = s.what .. (' %s was found safe.'):format(c:name('subject'))
    elseif c:get('seen') then
        text = s.what .. ((s.dead and (how == 'dead' or how == 'pronounced')) and '' or part(c, out, 'subject'))
    end
    if s.other or s.safe then text = text .. part(c, out, s.culprit) end
    local o = c:who('caller')
    if o.facts.c_told then text = text .. (s.safe and ' The caller was told where they were.' or ' The caller was told.')
    elseif o.facts.c_quiet then text = text .. ' The caller was told nothing.'
    elseif c:get('seen') then text = text .. (s.safe and ' The caller was not told where they were.' or ' The caller was not told.') end
    if s.note and c:get('car_seen') then text = text .. ' ' .. s.note end
    return text
end

-- One story, from its table. s = { what (the summary's opening), kin ({ if male, if female }: what the caller calls them),
-- who (the caller's answer: %s their name, %s kin), caller, neighbour (their lines), age, model?, hurt?, dead?, vitals?, away?,
-- stranger? (the caller's no family: flags, items), lines? (theirs, when they can talk), other? ({ male, age, secret, home,
-- items, lines }: whoever's at the door), culprit?, safe?, door, back, car (clue text), door_prop?, back_prop?, van?, note?
-- (the summary, once the car's been checked), reached? (c), setup? (c, seen) }
local function play(c, s)
    local male = math.random() < .5
    local family = not s.stranger
    s.caller.c_who = function()
        return { { s.who:format(c:name('subject'), s.kin[male and 1 or 2]), set = { c_name = 'yes' } } }
    end
    s.caller.c_know = s.caller.c_know or { "I told you. They're family. Please, can someone just go and look?" }
    s.caller.where = s.caller.where or { "I'm not going anywhere until I know they're okay." }
    c:person('caller', { at = 'caller', label = 'Caller', family = family, age = { 35, 55 }, secret = 'clean', demeanor = 'nervous', flags = s.flags,
        items = s.items or {}, scene = 'WORLD_HUMAN_STAND_MOBILE', questions = CALLER_Q, lines = s.caller })
    s.neighbour.where = s.neighbour.where or { "Nowhere. I live next door." }
    c:person('neighbour', { at = 'neighbour', label = 'Neighbour', age = { 40, 70 }, secret = 'clean', demeanor = 'chatty', items = {},
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = NEIGHBOUR_Q, lines = s.neighbour })
    c:person('subject', { at = s.away and AWAY or 'found', label = 'Person', male = male, model = s.model and s.model[male and 1 or 2], home = true, family = family,
        age = s.age, secret = 'clean', demeanor = 'nervous', items = {}, injured = s.hurt, dead = s.dead, vitals = s.vitals,
        scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = s.lines and SUBJECT_Q, lines = s.lines })
    if s.other then
        c:person('other', { at = 'answer', label = 'Person at the house', male = s.other.male, age = s.other.age, secret = s.other.secret, demeanor = s.other.demeanor,
            home = s.other.home, family = s.other.home, items = s.other.items, scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = OTHER_Q, lines = s.other.lines })
    end
    local van = s.van or { model = 'asea', make = 'Declasse', name = 'Asea', color = 'Silver', paint = 4 }
    c:vehicle('car', { at = 'car', model = van.model, make = van.make, name = van.name, color = van.color, paint = van.paint,
        owner = s.van and 'other' or 'subject', label = 'Car on the drive' })
    c:clue('door', { at = 'door', label = 'The front door', prop = s.door_prop, scatter = s.door_prop and { model = s.door_prop, count = 3, radius = 1.0 } or nil, text = s.door })
    c:clue('back', { at = 'back', label = 'Round the back', prop = s.back_prop, text = s.back })
    c:clue('car', { on = 'car', label = 'Car on the drive', text = s.car })
    card(c)
    if s.dead then c:set('body', true) end
    if s.hurt or s.dead then c:set('hurts', { subject = true }) end
    if s.culprit then c:blip('decide', s.culprit) end
    local seen = wire(c, s)
    local ready = s.safe and trap(c) or nil
    if s.setup then s.setup(c, seen) end
    resolve(c, s.culprit, function(out) return report(c, out, s) end, ready)
end

Callout({
    id = 'welfare',
    name = 'Welfare check',
    voice = 'call_welfare', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        "Caller can't reach someone close to them and hasn't heard from them in days. They're outside the house now.",
        "Caller says someone they know has stopped answering the phone. Nobody's coming to the door.",
        "Request for a welfare check. Caller is worried and hasn't been able to reach them.",
    },
    -- The points each location needs, in the order /c3rplace welfare walks you through them ('car': sit in a car).
    -- The first is where the call is (units are on scene within Config.Callouts.arrive m of it).
    points = {
        { 'caller', 'The caller, on the pavement outside the house.' },
        { 'neighbour', 'The neighbour, on their own step or lawn next door.' },
        { 'door', 'The front door, on the step: what is on the doorstep lies here.' },
        { 'answer', 'Whoever is at the house, on the path 2 to 3 m from the door.' },
        { 'back', 'A back door or window, on the ground beside it.' },
        { 'found', 'Further round the back, on the ground, out of sight of the street and the door: more than 8 m from anywhere a unit would stand out front.' },
        { 'car', 'A car on the drive. Sit in a car parked where it should be.', 'car' },
    },
    -- Add more with /c3rplace welfare in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Nikola Pl', at = vector3(1388.49, -569.63, 74.50), points = {
            caller = vector4(1388.49, -569.63, 74.50, 180.0),
            neighbour = vector4(1405.00, -575.00, 74.40, 90.0),
            door = vector4(1385.28, -592.50, 74.49, 47.8),
            answer = vector4(1386.90, -590.00, 74.45, 200.0),
            back = vector4(1383.12, -598.31, 74.34, 48.2),
            found = vector4(1378.00, -606.00, 74.34, 40.0),
            car = vector4(1394.00, -585.00, 74.41, 356.8),
        } },
    },

    stories = {
        -- ── A fall. ──────────────────────────────────────────────────────────────────────────────────────────────
        fall = {
            weight = 3,
            setup = function(c)
                play(c, {
                    what = 'Welfare check: found after a fall at home.',
                    kin = PARENT,
                    who = "%s. My %s. I ring every evening and they always pick up.",
                    age = { 68, 86 },
                    model = ELDERLY,
                    hurt = true,
                    vitals = 'Conscious, just. Badly dehydrated, and one leg is broken. They have been lying here for days.',
                    caller = {
                        c_last = { "Three days ago. They said they were going to do the gutters. At their age." },
                        c_worry = { "Three days of nothing. That's not them. I've been knocking for ten minutes." },
                        c_news = { { "Oh, thank God. A fall? I told them not to go up that ladder. Can I go with them?", set = { c_told = 'yes' } } },
                    },
                    neighbour = {
                        c_seen = { "A few days ago. Round the back with a ladder." },
                        c_who = { "One older person, on their own since their partner passed. Nice. Keeps to themselves." },
                        c_odd = { "Their papers have been piling up. I should have knocked. I thought they'd gone away." },
                    },
                    door = 'No answer. Three days of newspapers on the step, and the porch light left on.',
                    door_prop = 'prop_cs_newspaper',
                    back = 'A ladder lying where it fell, and a bucket of leaves tipped over. Scuffs in the dirt lead away from it.',
                    back_prop = 'prop_byard_ladder01',
                    car = 'Cold, with dust and leaves across the windscreen. It has not moved for days.',
                    reached = function(cc) cc:say('subject', "Oh, thank God. I don't know how long I've been here.") end,
                    setup = function(cc)
                        local next_call = 0 -- (heard from a little way off, before anyone gets there)
                        cc:on('tick', function(t)
                            if cc:get('seen') or t < next_call or not cc:near('subject', 30.0) then return end
                            next_call = t + 20
                            cc:say('subject', "Help... is someone there? Round the back...")
                        end)
                    end,
                })
            end,
        },

        -- ── Gone in their sleep. ─────────────────────────────────────────────────────────────────────────────────
        natural = {
            weight = 2,
            setup = function(c)
                play(c, {
                    what = 'Welfare check: found dead at home, with no sign of foul play.',
                    kin = PARENT,
                    who = "%s. My %s. They've got a bad heart, so I check in.",
                    age = { 72, 88 },
                    model = ELDERLY,
                    dead = true,
                    caller = {
                        c_last = { "Sunday. They sounded tired, but they always sound tired these days." },
                        c_worry = { "They never go this long without ringing. Never." },
                        c_news = function()
                            if c:get('revived') then return { { "They're alive? Oh, thank God. Thank you. Thank you.", set = { c_told = 'yes' } } } end
                            return { { "...No. No, I spoke to them on Sunday. ...Were they in pain? ...Thank you for telling me.", set = { c_told = 'yes' } } }
                        end,
                    },
                    neighbour = {
                        c_seen = { "The day before yesterday, in the yard with a cup of tea. They waved." },
                        c_who = { "One older person, on their own. Bad heart, for years. The doctor comes by." },
                        c_odd = { "Nobody's been round. It's been very quiet. Too quiet, I suppose." },
                    },
                    door = 'Locked, and no answer. The curtains are drawn. Nothing forced, nothing out of place.',
                    back = 'A garden chair pulled round into the sun and a mug of tea gone cold. A pill organiser, filled up to Tuesday. Nothing has been disturbed.',
                    back_prop = 'prop_mug_01',
                    car = 'Cold and locked, with a disabled badge on the dash. Nothing inside but a folded blanket.',
                })
            end,
        },

        -- ── Someone who doesn't want to be found. ────────────────────────────────────────────────────────────────
        hiding = {
            weight = 3,
            setup = function(c)
                play(c, {
                    what = 'Welfare check called in by someone under a restraining order.',
                    kin = { 'partner', 'partner' },
                    who = "%s. My %s. We've been together for years.",
                    age = { 24, 45 },
                    stranger = true,
                    flags = { 'RESTRAINING ORDER' },
                    items = { 'Phone open on a GPS tracker app, showing this street' },
                    culprit = 'caller',
                    safe = true,
                    caller = {
                        c_last = { "A while. Their number's changed. I just need to see them and know they're okay." },
                        c_worry = { "They just stopped talking to me. It's not like them. Someone's got in their head." },
                        c_know = cracks(3, { "I told you. We're together." },
                            { { "...We were. Alright? It's complicated. There was some paperwork. That doesn't mean I can't worry about them.", set = { c_admit = 'yes' } } },
                            { "I said. It's complicated." }),
                        c_news = { { "You found them? Round the back? Good. That's all I needed.", set = { c_told = 'yes' } } },
                        c_quiet = { { "What do you mean, you can't tell me? I've got a right to know! ...Fine.", set = { c_quiet = 'yes' } } },
                    },
                    neighbour = {
                        c_seen = { "This morning. They went out the back as soon as that one out front turned up." },
                        c_who = { "Moved in six months ago. Asked me not to tell anyone they live here. I thought that was odd." },
                        c_odd = { "That one out front has been sat in a car down the road three nights running, watching this house." },
                    },
                    lines = {
                        c_ok = { "I'm fine. Keep your voice down. Are they still out there?" },
                        c_caller = { { "Did you tell them I'm here? Please. Please don't. There's an order against them. They're not allowed anywhere near me.", set = { c_hide = 'yes' } } },
                        c_how = { "I don't know. I changed everything. New number, new town. I don't know how they keep finding me." },
                        where = { "Nowhere. I'm not going out there." },
                        live = { "Right here. Please don't tell them that." },
                    },
                    door = 'No answer. A brand new lock, a camera doorbell and no name on the letterbox. Whoever lives here does not want to be found.',
                    back = 'The back gate is unlatched, and a packed bag sits by the wall, ready to go.',
                    back_prop = 'prop_ld_suitcase_01',
                    car = 'Up under the rear arch, a small magnetic box with a blinking light: a GPS tracker.',
                    note = 'A GPS tracker was found on their car.',
                    reached = function(cc) cc:say('subject', "Shh. Please. Are they still out there?") end,
                    setup = function(cc)
                        cc:on('fact', function(_, fact)
                            if fact ~= 'c_hide' then return end
                            cc:reveal('decide')
                            local o = cc:who('caller')
                            o.facts.c_hide = 'yes'
                            cc:questions('caller')
                        end)
                    end,
                })
            end,
        },

        -- ── Away, and someone's in the house. ────────────────────────────────────────────────────────────────────
        intruder = {
            weight = 2,
            setup = function(c)
                play(c, {
                    what = 'Welfare check: the resident was away on a cruise, and someone had broken in.',
                    kin = { 'uncle', 'aunt' },
                    who = "%s. My %s. They're all the family I've got.",
                    age = { 58, 72 },
                    away = true,
                    culprit = 'other',
                    van = { model = 'speedo', make = 'Vapid', name = 'Speedo', color = 'White', paint = 111 },
                    caller = {
                        c_last = { "Over a week. It's their birthday tomorrow, and it goes straight to voicemail." },
                        c_worry = { "Voicemail, every time. And who's that at the house? I've never seen them in my life." },
                        c_news = { { "On a cruise? They never said a word! ...Oh, thank goodness. I'm going to kill them. Who was that in the house?", set = { c_told = 'yes' } } },
                    },
                    neighbour = {
                        c_seen = { "Last week. Getting in a taxi with a big suitcase. I figured they were off on a trip." },
                        c_who = { "One person, retired. Quiet." },
                        c_odd = { "That van turned up last night, and someone's been in and out with boxes. I thought they were movers." },
                    },
                    other = {
                        age = { 25, 45 },
                        secret = 'warrant',
                        demeanor = 'polite',
                        items = { 'Jewellery in a sock', "A bank card in someone else's name" },
                        lines = {
                            c_who = { { "House sitter. Friend of the family. Is there a problem?", set = { c_sitter = 'yes' } } },
                            c_them = { "Away. On holiday. I'm looking after the place." },
                            c_see = { "You can't. They're away, I told you. Back next week, I think." },
                            c_put = cracks(2, { "I told you. I'm house sitting. Call them yourself." },
                                { { "...The window was already broke. I only took what nobody'd miss.", set = { c_admit = 'yes' } } },
                                { "I said. I only took what nobody'd miss." }),
                            where = { "Nowhere. I'm staying here." },
                            live = { "Here, for now. Just while they're away." },
                        },
                    },
                    door = 'The door is on the latch, and the frame around the lock has fresh splinters in it.',
                    back = 'A window has been forced, with pry marks in the frame. Boxes are stacked by the gate, ready to carry out.',
                    back_prop = 'prop_cs_cardbox_01',
                    car = 'The back is full: a television, a jewellery box, a computer and a set of golf clubs.',
                    reached = function(cc)
                        local o = cc:who('other')
                        o.facts.c_back = 'yes'
                        cc:questions('other')
                    end,
                    setup = function(cc, seen)
                        local left -- (s until dispatch gets through: they start trying once something's not right)
                        local bolted, bolting = false, false
                        local function soon() left = left or 30 end
                        cc:on('fact', function(_, fact) if fact == 'c_sitter' then soon() end end)
                        cc:on('inspect', function(clue) if clue == 'back' or clue == 'car' then soon() end end)
                        cc:on('act', function(who, action)
                            local o = cc:who('other')
                            if who ~= 'other' then return end
                            if action == 'cuff' and o.cuffed then return soon() end
                            if action ~= 'frisk' or bolted or o.cuffed then return end
                            bolted = true -- (they know what you're about to find)
                            bolting = math.random() < .4
                        end)
                        cc:on('tick', function()
                            if bolting then
                                bolting = false
                                if cc:talking('other') and not cc:who('other').cuffed then cc:task('other', 'flee') end
                            end
                            if not left or left <= 0 then return end
                            left = left - 1
                            if left > 0 then return end
                            cc:dispatch(("Dispatch: we reached %s through the cruise line. They're at sea and they're fine. They have no house sitter, and nobody should be at that address."):format(cc:name('subject')))
                            cc:reveal('decide')
                            seen()
                        end)
                    end,
                })
            end,
        },

        -- ── Shut away by the person looking after them. ──────────────────────────────────────────────────────────
        carer = {
            weight = 2,
            setup = function(c)
                play(c, {
                    what = 'Welfare check: found neglected by the person looking after them.',
                    kin = PARENT,
                    who = "%s. My %s. I can't get through to them any more.",
                    age = { 70, 88 },
                    model = ELDERLY,
                    hurt = true,
                    vitals = 'Thin, weak and badly dehydrated. Old bruises on both arms. They have not been looked after for a long time.',
                    culprit = 'other',
                    caller = {
                        c_last = { "Two months. Every time I ring, their carer picks up and says they're asleep." },
                        c_worry = { "The letters started coming back. The carer says they're sleeping. It's always sleeping." },
                        c_news = { { "Round the back? In that state? All this time I was told they were asleep. ...Thank you for looking.", set = { c_told = 'yes' } } },
                    },
                    neighbour = {
                        c_seen = { "Weeks ago. Months? The carer's the only one I see now." },
                        c_who = { "One older person, and a carer who moved in last year. Family, they said." },
                        c_odd = { "That car's out every day and they're never in it. And I've heard crying, nights. I thought it was the television." },
                    },
                    other = {
                        age = { 28, 50 },
                        secret = 'nervous',
                        home = true,
                        items = { "Someone else's bank card and pension letters" },
                        lines = {
                            c_who = { "I look after them. I'm family. Who called you?" },
                            c_them = { "Asleep. They're always asleep this time of day. They don't want visitors." },
                            c_see = cracks(3, { "I told you. They're sleeping. Come back tomorrow." },
                                { { "...They're out back. They get confused. They wander. I had to keep them somewhere. You don't know what it's like.", set = { c_admit = 'yes' } } },
                                { "I said. You don't know what it's like." }),
                            c_put = cracks(1, { "I told you." },
                                { { "...I needed the money. I was going to pay it back. You don't know what it's like.", set = { c_admit = 'yes' } } },
                                { "I said. You don't know what it's like." }),
                            where = { "Nowhere. I live here." },
                            live = { "Right here. I look after them." },
                        },
                    },
                    door = 'Final demands sticking out of the letterbox, all in the resident\'s name. Someone has been answering this door, but nobody has been paying these.',
                    back = 'A padlock on the outside of a door, and a plate of old food left on the ground beside it.',
                    back_prop = 'prop_cs_padlock',
                    car = 'Fast food wrappers on the seat, and the driver\'s seat pushed right back. A bank statement on the dash shows the account emptied, a little at a time.',
                    reached = function(cc)
                        cc:say('subject', "Have they gone? Please. Don't leave me here.")
                        cc:reveal('decide')
                        local o = cc:who('other')
                        o.facts.c_back = 'yes'
                        cc:questions('other')
                    end,
                    setup = function(cc)
                        cc:on('fact', function(_, fact) if fact == 'c_admit' then cc:reveal('decide') end end)
                    end,
                })
            end,
        },
    },
})
