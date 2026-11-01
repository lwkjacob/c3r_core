--[[
    c3r callout: PERSON UNRESPONSIVE.

    Someone's down and the caller hung up. The report is the same every time, and the card is too: the victim, the friend
    who doesn't want police there, and a search of the area (three units can take one each). It's an overdose, and there's a
    clock: about 4 minutes from the first unit arriving, and Narcan buys more. What's really going on is one of four stories:
      accident  a user took too much, and the friend hid the needle
      batch     the heroin's been cut with fentanyl, the dealer's nearby, and the second person goes down too
      dealer    the second person "helping" is the dealer, and the friend won't talk with them listening
      hotshot   it was no accident: the friend gave them too much, over a debt
    Saying what it was to paramedics helps. Even so, one in four die in hospital; not knowing, it's one in two.
    It's dealt with when everyone hurt has been taken or pronounced and whoever's responsible has been dealt with, or the
    victim's been seen, the friend's been heard and every unit has left.

    Points per location: walk them out in game with /c3rplace overdose (it writes the location in below).
]]

local FRIEND_Q = {
    { id = 'c_what', label = 'What happened here?', stress = true, press = true },
    { id = 'c_safe', label = "You're not in trouble. I need to know what they took.", stress = true, press = true },
    { id = 'c_where', label = 'Where did it come from?', needs = { c_drug = true }, stress = true, press = true },
}
local OTHER_Q = {
    { id = 'c_saw', label = 'What did you see?', stress = true, press = true },
    { id = 'c_here', label = 'What are you doing here?', stress = true },
    { id = 'c_know', label = 'How do you know them?', stress = true },
}
local SELL_Q = { id = 'c_sell', label = 'Someone just overdosed on what you sold them.', stress = true, press = true }
local DEALER_Q = {
    { id = 'c_here', label = 'What are you doing here?', stress = true },
    SELL_Q,
}
local TIME = 240 -- s from the first unit arriving
local NARCAN = 120 -- s a dose leaves them with
local DOSES = 2 -- (after that it isn't doing anything)
local DEAD_ANYWAY, DEAD_UNKNOWN = 0.25, 0.5
local VITALS = 'Barely breathing. Pinpoint pupils, blue lips. Looks like an opioid overdose. Narcan will buy time.'
local CALLED = { victim = 'The victim', other = 'The second person' }

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
    c:objective('victim', 'Check on the victim', { hint = 'On the ground.', blip = 'victim' })
    c:objective('friend', 'Talk to the friend', { hint = 'They would rather you were not here.', blip = 'friend' })
    c:objective('search', 'Search the area', { hint = 'What did they take?', blip = 'spot' })
    c:objective('medic', 'Call paramedics', { hidden = true, who = 'all', blip = 'victim', hint = 'Radio for an ambulance. Hurry.' })
    c:objective('medic2', 'Call paramedics for the second person', { hidden = true, who = 'all', blip = 'other', hint = 'Radio for an ambulance. Hurry.' })
    c:objective('drug', 'Find out what they took', { hidden = true, who = 'all', hint = 'Paramedics need to know.' })
    c:objective('dealer', 'Find the dealer', { hidden = true, who = 'all', blip = 'dealer', hint = 'The same stamp on the bags.' })
    c:objective('gunman', 'Stop the gunman', { hidden = true, who = 'all', hint = 'Take cover. They give up if they have to.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'friend' }, who = 'all' })
end

-- Someone's hurt: the ending waits for them, and the card says so.
local function hurt(c, key)
    local list = c:get('hurts') or {}
    list[key] = true
    c:set('hurts', list)
    c:patient(key)
    c:reveal(key == 'victim' and 'medic' or 'medic2')
end

-- Done when: someone's been beside the victim, the friend's said anything, the area's been searched. The clock runs from
-- the first arrival; Narcan and CPR buy time; anything saying what it was goes on the card.
local function wire(c)
    local left, running, known, doses, stopped, gone, seen = TIME, false, false, 0, false, false, false
    local function drug_known()
        if known then return end
        known = true
        c:set('known', true)
        c:done('drug')
        c:note('What was taken was established')
        c:dispatch('Copy, passing that on to paramedics.')
    end
    c:on('build', function()
        c:set('hurts', { victim = true })
        c:patient('victim')
        for _, key in ipairs({ 'friend', 'other' }) do -- (a swab finds what they all took)
            local o = c:who(key)
            if o then o.swab = 'Heroin' end
        end
    end)
    c:on('arrive', function()
        running = true
        c:reveal('drug')
    end)
    c:on('contact', function(who) if who == 'friend' then c:done('friend') end end)
    c:on('fact', function(_, fact) if fact == 'c_drug' then drug_known() end end)
    c:on('inspect', function(clue)
        if clue ~= 'spot' then return end
        c:done('search')
        drug_known()
    end)
    c:on('aid', function(who, what, src)
        if what == 'narcan' then
            if who == 'victim' then doses = doses + 1 end
            if who == 'victim' and doses > DOSES then return c:tell(src, 'Narcan given', 'No response. It is not doing anything now. They need paramedics.') end
            if who == 'victim' then left = math.max(left, NARCAN) end
            c:note('Narcan given')
            c:tell(src, 'Narcan given', 'A gasp, and their colour comes back a little. It will not last. They still need paramedics.')
        end
        if who ~= 'victim' then return end
        c:done('victim')
        if what == 'hospital' or what == 'treated' or what == 'pronounced' then stopped = true end
    end)
    c:on('dead', function(who)
        if who ~= 'victim' then return end
        gone, left = true, 0
    end)
    c:on('tick', function()
        if not seen and c:near('victim', 12.0) then
            seen = true
            c:done('victim')
            hurt(c, 'victim')
        end
        if gone and (c:health('victim') or 0) > 100 then -- (CPR, or paramedics: back, for now)
            gone, left = false, 120
        end
        if not running or stopped or left <= 0 then return end
        left = left - 1
        if left == 60 then c:dispatch('Paramedics advise they do not have long.') end
        if left <= 0 then
            c:die('victim')
            left = 5 -- (again, if that game didn't get it: `dead` stops the clock)
        end
    end)
    c:on('dead', function(who) if who == 'friend' then c:done('friend') end end)
end

-- They're fighting, until hurt, told to stop half the time, or 45-120 s with units near. -> start(), give_up(line)
local function fight(c, key)
    local fighting, left = false, 0
    local function give_up(line)
        fighting = false
        local o = c:who(key)
        o.ran, o.gave_up = true, true
        c:done('gunman')
        c:say(key, line)
        c:task(key, 'surrender')
    end
    local function start()
        fighting, left = true, math.random(45, 120)
        c:reveal('gunman')
        c:blip('gunman', key)
        c:task(key, 'shoot')
    end
    c:on('fired', function(who)
        if who ~= key then return end
        c:dispatch('Shots fired! All units, shots fired!')
        c:note('The suspect fired at officers')
    end)
    c:on('tick', function()
        if not fighting then return end
        local health = c:health(key)
        left = c:near(key, 45.0) and left - 1 or left
        if health and health > 100 and health < 150 then give_up("Okay! Okay, I'm hit! I'm done!")
        elseif left <= 0 then give_up("That's it! I'm done, don't shoot!") end
    end)
    c:on('hail', function(who)
        if who == key and fighting and math.random() < 0.5 then give_up("Alright! Alright! It's down!") end
    end)
    c:on('dead', function(who)
        if who ~= key then return end
        fighting = false
        c:done('gunman')
    end)
    return start, give_up
end

-- A unit within 6 m, nobody's spoken to them: 15% they pull a gun. Spoken to first, on foot: 30% they bolt.
local function armed(c, key, start)
    local reacted, spoken, bolting = false, false, false
    c:on('contact', function(who)
        if who ~= key or spoken then return end
        spoken, reacted = true, true
        bolting = not c:who(key).gave_up and math.random() < 0.3
    end)
    c:on('tick', function()
        local o = c:who(key)
        if bolting then
            bolting = false
            if c:talking(key) then c:task(key, 'flee') end
        end
        if reacted or not o or o.cuffed or (c:health(key) or 0) <= 100 or not c:near(key, 6.0) or c:talking() then return end
        reacted = true
        if math.random() < 0.15 then start() end
    end)
end

--[[ It's over when everyone arrested has been taken in, everyone hurt has been taken or pronounced, and the one responsible
     (culprit) has been dealt with; or the victim's been seen, the friend's been heard and every unit has left.
     ends(out) -> the MDT summary; out[person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' | 'pronounced' |
     'hospital' | 'died' (in hospital); out.left = true. ]]
local function resolve(c, culprit, ends)
    local out, taken, away_for, done = {}, {}, 0, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local LET_GO = { released = true, cited = true, warning = true, fled = true, pronounced = true, hospital = true, died = true, dead = true }
    local SEEN = { hospital = true, pronounced = true, died = true, fled = true }
    local function all_seen()
        for who in pairs(c:get('hurts') or {}) do
            if not (SEEN[out[who]] or taken[who]) then return false end
        end
        return true
    end
    local function check()
        if done or waiting() then return end
        local dealt = taken[culprit] or LET_GO[out[culprit]]
        if not ((dealt and all_seen()) or out.left) then return end
        done = true
        c:done('decide')
        c:finish(ends(out))
    end
    c:on('act', function(who, action)
        local o = c:who(who)
        if action == 'cuff' and o and o.cuffed then
            out[who] = 'arrested'
            c:custody(who)
            if who == culprit then c:done('decide') end
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
        if who == 'victim' then c:done('medic') end
        if who == 'other' then c:done('medic2') end
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if out[who] == 'dead' then seen_to(who, 'pronounced') end -- (the coroner's been)
        if (c:get('hurts') or {})[who] and not SEEN[out[who]] then seen_to(who, 'hospital') end -- (an ambulance the call didn't hear about)
        if who == culprit and not out[who] then out[who] = 'fled' end
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if who == culprit then c:done('decide') end
        if not CALLED[who] then return end
        hurt(c, who)
        c:dispatch(('%s is down. Paramedics needed at the scene.'):format(CALLED[who]))
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' then return seen_to(who, 'pronounced') end
        if what ~= 'hospital' and what ~= 'treated' then return end
        if SEEN[out[who]] then return end -- (a second ambulance)
        -- (only the overdose's own: anyone else, and anyone patched up on the spot, was never that close)
        local dies = what == 'hospital' and CALLED[who] and math.random() < (c:get('known') and DEAD_ANYWAY or DEAD_UNKNOWN)
        seen_to(who, dies and 'died' or 'hospital')
        if dies then c:dispatch(('Hospital update: %s did not make it.'):format(CALLED[who]:lower())) end
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or SEEN[out[who]] and out[who] ~= 'fled' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        if who == culprit and LET_GO[out[who]] then c:done('decide') end
    end)
    c:on('tick', function() -- (the hurt and the responsible are dealt with in either order: one place to look)
        check()
        local here = c:near(nil, 80.0) or c:near('friend', 80.0) or c:near('other', 80.0) or c:near('dealer', 80.0) or c:talking()
        if c:is_done('victim') and c:is_done('friend') and not waiting() and not here then
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
    if how == 'died' then return (' %s died in hospital.'):format(s) end
    if how == 'dead' or how == 'pronounced' then return (' %s died at the scene.'):format(s) end
    return ''
end

local function people(c, friend, other, spot)
    c:person('victim', { at = 'victim', label = 'Victim', secret = 'clean', injured = true, vitals = VITALS, age = { 19, 44 } })
    friend.where = friend.where or { "Nowhere. Can we hurry this up?" }
    c:person('friend', { at = 'friend', label = 'Friend', secret = other.friend_secret or 'drugs', demeanor = 'nervous', items = other.friend_items or {},
        age = { 19, 44 }, scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = FRIEND_Q, lines = friend })
    c:clue('spot', { at = 'spot', label = spot.label or 'On the ground', prop = 'p_syringe_01_s', text = spot.text })
end

local function second(c, spec, lines)
    lines.where = lines.where or { "Just leaving." }
    c:person('other', { at = 'other', label = 'Person', male = spec.male, age = { 19, 44 }, secret = spec.secret or 'drugs', demeanor = 'nervous',
        items = spec.items or {}, weapon = spec.weapon, scene = 'WORLD_HUMAN_SMOKING', questions = spec.questions or OTHER_Q, lines = lines })
end

local function dealer(c, lines)
    lines.where = lines.where or { "Nowhere you need to know about." }
    c:person('dealer', { at = 'dealer', label = 'Man', male = true, age = { 24, 40 }, secret = 'warrant', demeanor = 'rude', weapon = 'WEAPON_PISTOL',
        items = { 'Pistol, loaded', 'Twenty bags of heroin with a red stamp' }, scene = 'WORLD_HUMAN_SMOKING', questions = DEALER_Q, lines = lines })
    c:vehicle('dealer_car', { at = 'dealer_car', model = 'peyote', make = 'Vapid', name = 'Peyote', color = 'Black', paint = 0, owner = 'dealer', locked = false, label = 'Their car' })
end

Callout({
    id = 'overdose',
    name = 'Person unresponsive',
    voice = 'call_overdose', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    weight = 1,
    enabled = true,
    reports = {
        "Caller says someone has collapsed and won't wake up. They hung up before giving a name.",
        "Person unresponsive. Caller sounded panicked and wouldn't stay on the line.",
        'Report of someone not breathing properly. Caller refused to give details.',
    },
    -- The points each location needs, in the order /c3rplace overdose walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it).
    -- Skip the optional ones with Z in /c3rplace: without a dealer spot and car, the bad batch story doesn't play there.
    points = {
        { 'victim', 'The victim, on the ground.' },
        { 'friend', 'The friend, a few metres from them.' },
        { 'other', 'A second person, a little way off. They may walk over to the friend.' },
        { 'spot', 'What they took: on the ground near the victim.' },
        { 'dealer', 'The dealer, by a parked car, 50 to 150 m off.', optional = true },
        { 'dealer_car', 'The dealer\'s car. Sit in a car parked there.', 'car', optional = true },
    },
    -- Add more with /c3rplace overdose in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Grove St', at = vector3(-71.81, -1782.74, 28.19), points = {
            victim = vector4(-71.81, -1782.74, 28.19, 155.7),
            friend = vector4(-69.00, -1785.00, 28.10, 60.0),
            other = vector4(-48.03, -1761.61, 29.44, 145.7),
            spot = vector4(-71.56, -1786.14, 28.03, 227.9),
            dealer = vector4(-61.79, -1842.18, 26.63, 297.5),
            dealer_car = vector4(-62.54, -1840.41, 26.50, 142.0),
        } },
        { street = 'Amarillo Vista', at = vector3(1278.85, -1746.58, 52.17), points = {
            victim = vector4(1278.85, -1746.58, 52.17, 317.7),
            friend = vector4(1281.60, -1746.02, 52.06, 69.3),
            other = vector4(1285.06, -1734.75, 52.64, 347.4),
            spot = vector4(1273.64, -1749.18, 52.11, 130.1),
            dealer = vector4(1319.16, -1720.85, 54.79, 87.8),
            dealer_car = vector4(1323.27, -1718.31, 54.39, 283.5),
        } },
        { street = 'Panorama Dr', at = vector3(1572.29, 3683.56, 34.78), points = {
            victim = vector4(1572.29, 3683.56, 34.78, 343.3),
            friend = vector4(1571.52, 3687.89, 34.73, 208.1),
            other = vector4(1565.39, 3705.08, 34.46, 182.0),
            spot = vector4(1569.58, 3681.14, 34.80, 53.7),
        } },
        { street = 'Great Ocean Hwy', at = vector3(160.58, 6357.87, 31.39), points = {
            victim = vector4(160.58, 6357.87, 31.39, 278.3),
            friend = vector4(160.98, 6353.38, 31.45, 30.9),
            other = vector4(183.66, 6367.78, 31.43, 324.1),
            spot = vector4(164.30, 6359.02, 31.40, 144.0),
        } },
    },

    stories = {
        -- ── Too much. ────────────────────────────────────────────────────────────────────────────────────────────
        accident = {
            weight = 3,
            setup = function(c)
                people(c, {
                    c_what = cracks(2, { "They just fainted. It's the heat. You don't need to be here." },
                        { { "...Okay. They used. Heroin. I hid the needle. Please, just help them.", set = { c_drug = 'heroin', c_admit = 'yes' } } },
                        { "I told you. Heroin. Please help them." }),
                    c_safe = { { "...Heroin. Maybe twenty minutes ago. I thought they were sleeping.", set = { c_drug = 'heroin', c_admit = 'yes' } } },
                    c_where = { "I don't know a name. A guy. He's long gone." },
                }, {}, { text = 'A needle, kicked under the edge of something, and a burnt spoon. It was hidden in a hurry.' })
                second(c, {}, {
                    c_saw = { "I just saw them fall. I don't know them." },
                    c_here = { "Walking. I stopped. Is that okay?" },
                    c_know = { "I don't. I told you." },
                })
                card(c)
                wire(c)
                resolve(c, 'friend', function(out)
                    local text = 'An accidental opioid overdose.' .. part(c, out, 'victim') .. part(c, out, 'friend') .. part(c, out, 'other')
                    if out.friend == 'arrested' and not c:who('friend').ran then text = text .. ' The friend had stayed with them.' end
                    return text
                end)
            end,
        },

        -- ── A bad batch. ─────────────────────────────────────────────────────────────────────────────────────────
        batch = {
            weight = 3,
            needs = { 'dealer', 'dealer_car' },
            setup = function(c)
                people(c, {
                    c_what = cracks(2, { "They just fell. I don't know. Do you have to be here?" },
                        { { "...It's new stuff. Heroin, he said. It hit them straight away, it's not right, it's not right.", set = { c_drug = 'heroin', c_admit = 'yes' } } },
                        { "I told you. It's the new stuff." }),
                    c_safe = { { "Heroin. New stuff, a red stamp on the bag. It's not right. It hit them straight away.", set = { c_drug = 'heroin', c_admit = 'yes' } } },
                    c_where = { { "A guy by a black Peyote, down the road. He's still out there selling it.", set = { c_dealer = 'yes' } } },
                }, {}, { text = 'A needle and a bag with a red stamp. A pinch of the powder is the wrong colour for heroin. This looks cut with fentanyl.' })
                second(c, {}, {
                    c_saw = { "I had some too. I feel fine. I feel... give me a minute." },
                    c_here = { "We were all together. I'm alright. I'm alright." },
                    c_know = { "We use together. Is that what you want to hear?" },
                })
                dealer(c, {
                    c_here = { "Getting some air. Is that a crime?" },
                    c_sell = cracks(3, { "Sold? I don't know what you're talking about." },
                        { { "...It's what I got. I didn't cut it. I don't cut it.", set = { c_admit = 'yes' } } },
                        { "I told you. I don't cut it." }),
                })
                card(c)
                wire(c)
                c:on('fact', function(_, fact)
                    if fact == 'c_dealer' then c:reveal('dealer') end
                end)
                c:on('inspect', function(clue) if clue == 'spot' then c:reveal('dealer') end end)
                c:on('contact', function(who) if who == 'dealer' then c:reveal('dealer') c:done('dealer') end end)
                local clock, second_down = 0, false
                c:on('tick', function()
                    if second_down or not c:near(nil, 300.0) then return end
                    clock = clock + 1
                    if clock < 150 then return end
                    second_down = true
                    local o = c:who('other')
                    if not o or o.cuffed or (c:health('other') or 0) <= 100 then return end -- (gone, or held: not this time)
                    c:collapse('other', VITALS)
                    hurt(c, 'other')
                    c:dispatch('A second person is down. It is the same batch. Paramedics needed.')
                end)
                local start = fight(c, 'dealer')
                armed(c, 'dealer', start)
                resolve(c, 'dealer', function(out)
                    return 'A batch of heroin cut with fentanyl.' .. part(c, out, 'victim') .. part(c, out, 'other') .. part(c, out, 'friend') .. part(c, out, 'dealer')
                end)
            end,
        },

        -- ── The dealer's right there. ────────────────────────────────────────────────────────────────────────────
        dealer = {
            weight = 2,
            setup = function(c)
                local function safe_line(o)
                    if not c:apart('friend', 'other') then return { "I don't know anything. Ask him." } end
                    return { { "Heroin. He sold it to us, right there. Please. Don't tell him I said.", set = { c_drug = 'heroin', c_him = 'yes' } } }
                end
                people(c, {
                    c_what = { "I don't know. They just went down. Can we talk later?" },
                    c_safe = safe_line,
                    c_where = safe_line,
                }, {}, { text = 'A needle and a bag with a stamp on it. There is a roll of the same bags dropped nearby, far too many for one person.' })
                local asked = { OTHER_Q[1], OTHER_Q[2], OTHER_Q[3], { id = SELL_Q.id, label = SELL_Q.label, stress = true, press = true, needs = { c_him = true } } }
                second(c, { male = true, secret = 'warrant', weapon = 'WEAPON_PISTOL', questions = asked, items = { 'Pistol, loaded', 'Roll of cash', 'Fifteen stamped bags of heroin' } }, {
                    c_saw = { "They just dropped. Terrible. I came over to help. I've got first aid, you know." },
                    c_know = { "I don't. I was walking past." },
                    c_here = { "Helping, man. I was walking past. I called it in. You're welcome." },
                    c_sell = cracks(3, { "Me? I just got here." },
                        { { "...They knew what it was. I don't make them take it.", set = { c_admit = 'yes' } } },
                        { "I said. They knew what it was." }),
                    where = { "I was just going, actually." },
                })
                card(c)
                wire(c)
                c:on('build', function() c:task('other', 'go', 'friend') end) -- (stood right over the friend: they won't talk with him there)
                c:on('fact', function(_, fact)
                    if fact ~= 'c_him' then return end
                    c:who('other').facts.c_him = 'yes'
                    c:questions('other')
                end)
                local start = fight(c, 'other')
                armed(c, 'other', start)
                resolve(c, 'other', function(out)
                    return 'An opioid overdose, with the dealer still on scene.' .. part(c, out, 'victim') .. part(c, out, 'other') .. part(c, out, 'friend')
                end)
            end,
        },

        -- ── A hot shot. ──────────────────────────────────────────────────────────────────────────────────────────
        hotshot = {
            weight = 2,
            setup = function(c)
                people(c, {
                    c_what = cracks(3, { "They did it to themselves. They always do. I found them like this." },
                        { { "They owed me! Three months! I gave it to them, alright? I gave it to them. I only meant to scare them.", set = { c_admit = 'yes' } } },
                        { "I told you. I only meant to scare them." }),
                    c_safe = { { "Heroin. Theirs. Well, a lot of it. They must have done it themselves. They always do.", set = { c_drug = 'heroin' } } },
                    c_where = { "Theirs. I don't know. Why are you looking at me?" },
                }, { friend_secret = 'nervous' }, { text = 'A needle, and enough in the spoon for three people. Nobody who knew what they were doing would have fixed that much. There is a second, clean needle in its wrapper: someone else was here to do it.' })
                second(c, {}, {
                    c_saw = cracks(2, { "I didn't see anything." },
                        { { "They held the arm. The friend. They said it was what was owed. I should have called it in sooner.", set = { c_arm = 'yes', c_admit = 'yes' } } },
                        { "I told you what I saw." }),
                    c_here = { "I'm the one who called. I hung up. I'm sorry." },
                    c_know = { "They owed money. Everyone knows." },
                })
                card(c)
                wire(c)
                resolve(c, 'friend', function(out)
                    local died = out.victim == 'dead' or out.victim == 'pronounced' or out.victim == 'died'
                    return (died and 'A deliberate overdose: murder.' or 'A deliberate overdose: attempted murder.') .. part(c, out, 'victim') .. part(c, out, 'friend') .. part(c, out, 'other')
                end)
            end,
        },
    },
})
