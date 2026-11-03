--[[
    c3r callout: NOISE COMPLAINT.

    A neighbour can't sleep for the noise next door. The report never says what the noise is, and the card is the same every
    time: the caller, the door, a walk round the property (three units can take one each). What's behind the door is one of five:
      party    a birthday party: the host is sorry, and a drunk guest is about to drive home unless someone gets there first
      sitter   the noise is a burglary: the polite man at the door is "house-sitting", and his partner has the van
      grow     a hum all night: fans and a generator feeding a cannabis grow, and a tenant with a fish tank story
      feud     speakers aimed at the caller's fence on purpose: the caller keyed his car first
      deaf     an old man who can't hear his own television: he mishears everything until he gets his hearing aid back
    Nobody's armed: the worst of it is someone running, or a van leaving in a hurry. It's dealt with when everyone arrested has
    been taken in and whoever it's about has been let go, ticketed, warned or got away, or the door's been answered and every unit
    has left.

    Points per location: walk them out in game with /c3rplace noise (it writes the location in below).
]]

local CALLER_Q = {
    { id = 'c_heard', label = 'What can you hear?' },
    { id = 'c_who', label = 'Who lives there?' },
    { id = 'c_long', label = 'How long has this been going on?' },
    { id = 'c_before', label = 'Have you spoken to them about it?' },
    { id = 'c_key', label = 'His car has been keyed. Was that you?', needs = { c_key = true }, stress = true, press = true },
}
local RESIDENT_Q = {
    { id = 'c_noise', label = "We've had a complaint about the noise.", stress = true, press = true },
    { id = 'c_lives', label = 'Is this your house?', stress = true, press = true },
    { id = 'c_down', label = 'Can you keep it down tonight?', press = true },
    { id = 'c_owner', label = 'Who owns this house?', needs = { c_sitter = true }, stress = true },
    { id = 'c_caught', label = 'The neighbour says the owners never mentioned a sitter.', needs = { c_away = true, c_sitter = true }, stress = true, press = true },
    { id = 'c_smell', label = "What's that smell, and what's all the power for?", needs = { c_smell = true }, stress = true, press = true },
    { id = 'c_speakers', label = 'Why are your speakers pointing at the fence?', needs = { c_speakers = true }, press = true },
    { id = 'c_aid', label = 'Is this your hearing aid?', needs = { c_found = true } },
}
local GUEST_Q = {
    { id = 'c_here', label = 'How much have you had to drink?', stress = true },
    { id = 'c_keys', label = 'How are you getting home?', stress = true, press = true },
    { id = 'c_cab', label = 'Do you want me to call you a cab?', needs = { c_ride = true } },
}
local HELPER_Q = {
    { id = 'c_here', label = 'What are you doing here?', stress = true },
    { id = 'c_whose', label = 'Whose house is this?', stress = true, press = true },
}

-- Denies it until pressed `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

-- Living there: the usual "where are you headed / do you live here / your address" answered as someone at home.
local function at_home(c, lines)
    lines.where = lines.where or { "Nowhere. I live here." }
    lines.live = lines.live or { 'Right here.' }
    lines.address = lines.address or function() return { ('This house. On %s.'):format(c:street()) } end
    return lines
end

local function neighbour(c, lines, spec)
    spec = spec or {}
    c:person('caller', { at = 'caller', label = 'Neighbour', secret = 'clean', demeanor = spec.demeanor or 'rude', items = spec.items or {},
        scene = 'WORLD_HUMAN_STAND_MOBILE', questions = CALLER_Q, lines = lines })
end

local function card(c)
    c:objective('caller', 'Talk to the caller', { hint = 'They called it in from next door.', blip = 'caller' })
    c:objective('door', 'Make contact at the door', { hint = 'Find out what the noise is.', blip = 'resident' })
    c:objective('yard', 'Walk round the property', { hint = 'Anything out of place.', blip = 'yard' })
    c:objective('driver', 'Keep the guest off the road', { hidden = true, who = 'all', blip = 'other', hint = 'They have been drinking and they have their keys.' })
    c:objective('taxi', 'Call a taxi', { hidden = true, who = 'all', blip = 'other', hint = 'By radio, or G.' })
    c:objective('van', 'Check the van', { hidden = true, blip = 'car', hint = 'From the outside: what can you see?' })
    c:objective('power', 'Find where the power is going', { hidden = true, blip = 'source', hint = 'Round the side of the house.' })
    c:objective('scratch', 'Look at his car', { hidden = true, blip = 'car', hint = 'On the driveway.' })
    c:objective('aid', 'Give him his hearing aid', { hidden = true, blip = 'resident', hint = 'Back at the door.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'door' }, who = 'all', blip = 'resident' })
end

-- Done when: the caller's said what they can hear, someone's at the door, the yard's been looked at.
local function wire(c)
    c:on('act', function(who, action, arg)
        if who == 'caller' and action == 'ask' and arg == 'c_heard' then c:done('caller') end
    end)
    c:on('contact', function(who) if who == 'resident' then c:done('door') end end)
    c:on('inspect', function(clue) if clue == 'yard' then c:done('yard') end end)
    c:on('dead', function(who)
        if who == 'caller' then c:done('caller') end
        if who == 'resident' then c:done('door') end
    end)
    c:on('gone', function(who) if who == 'resident' then c:done('door') end end) -- (nobody left to answer it: leaving ends it)
end

-- What the first look at the street tells each unit.
local function heard(c, text)
    c:on('arrive', function(src) c:tell(src, 'You hear', text) end)
end

-- Gives someone a fact the officer found elsewhere: the question it opens is there the next time they're spoken to.
local function give(c, key, fact)
    local o = c:who(key)
    if not o then return end
    o.facts[fact] = 'yes'
    c:questions(key)
end

--[[ It's over when everyone arrested has been taken in and `culprit` (and opts.also, someone who has to be dealt with too) has
     been let go, ticketed, warned or got away; or the door's been answered and every unit has left. opts.ready() (false: not
     yet: a taxi to wait for).
     ends(out) -> the MDT summary; out[person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' | 'home';
     out.left = true. -> settle(who, how): someone's dealt with some other way (a taxi) ]]
local function resolve(c, culprit, ends, opts)
    opts = opts or {}
    local out, taken, away_for, done, moved = {}, {}, 0, false, false
    local LET_GO = { released = true, cited = true, warning = true, fled = true, dead = true, home = true }
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function settled(who) return taken[who] or LET_GO[out[who]] end
    local function check()
        if done or waiting() then return end
        if opts.also and settled(culprit) and not moved then -- (the card moves on to whoever's left)
            moved = true
            c:blip('decide', opts.also)
        end
        local dealt = settled(culprit) and (not opts.also or settled(opts.also)) and (not opts.ready or opts.ready())
        if not (dealt or out.left) then return end
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
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true
        elseif not out[who] and (who == culprit or who == opts.also) then out[who] = 'fled' end
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or out[who] == 'home' or out[who] == 'arrested' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif outcome == 'cited' or outcome == 'warning' then out[who] = outcome
        elseif outcome == 'released' and not out[who] then out[who] = 'released' end
    end)
    c:on('tick', function()
        check()
        -- (500 m for the second person: they may be in a car, with a unit behind them)
        -- ponytail: lose the van by more than 500 m with the man at the door still uncuffed and it's "everyone left". Cuff first.
        local here = c:near(nil, 80.0) or c:near(culprit, 80.0) or (opts.also and c:near(opts.also, 500.0)) or c:talking()
        if c:is_done('door') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then
                out.left = true
                check()
            end
        else
            away_for = 0
        end
    end)
    return function(who, how)
        if out[who] == 'arrested' or out[who] == 'dead' or out[who] == 'cited' or out[who] == 'warning' then return check() end
        out[who] = how
        check()
    end
end

-- One person's part in the summary.
local function part(c, out, who)
    local s, how = c:name(who), out[who]
    if how == 'arrested' then return (' %s was arrested.'):format(s) end
    if how == 'cited' or how == 'warning' then return (' %s was given a %s.'):format(s, how == 'cited' and 'ticket' or 'warning') end
    if how == 'released' then return (' %s was spoken to and let go.'):format(s) end
    if how == 'fled' then return (' %s got away.'):format(s) end
    if how == 'home' then return (' %s went home in a taxi.'):format(s) end
    if how == 'dead' then return (' %s died at the scene.'):format(s) end
    return ''
end

Callout({
    id = 'noise',
    name = 'Noise complaint',
    voice = 'call_noise', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 3,
    weight = 1,
    enabled = true,
    reports = {
        'Neighbour complaining about loud noise from the house next door. It has been going on for hours.',
        "Caller can't sleep for the noise next door and wants someone to go round.",
        "Noise complaint at a residence. Caller says they have had enough.",
    },
    -- The points each location needs, in the order /c3rplace noise walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it).
    points = {
        { 'caller', 'The neighbour who called it in, on their own doorstep next door.' },
        { 'resident', 'Whoever answers, at the front door of the noisy house.' },
        { 'other', 'A second person at the side gate or the garage, 5 to 10 m from the door and close to the car.' },
        { 'yard', 'Something on the ground round the side or the back of the house.' },
        { 'source', 'What is making the noise: by a window, or against the fence between the two houses.' },
        { 'car', 'A car on the driveway, pointing at the road. Sit in a car parked where it should be.', 'car' },
    },
    -- Add more with /c3rplace noise in game (it writes them here). This one is a rough placeholder
    locations = {
        { street = 'Grove St', at = vector3(118.13, -1945.35, 20.69), points = {
            caller = vector4(118.13, -1945.35, 20.69, 84.6),
            resident = vector4(106.35, -1953.22, 20.72, 330.2),
            other = vector4(100.40, -1948.60, 20.70, 300.0),
            yard = vector4(98.20, -1956.10, 20.70, 90.0),
            source = vector4(103.10, -1958.40, 20.70, 150.0),
            car = vector4(97.50, -1944.20, 20.60, 45.0),
        } },
        { street = 'Goma St', at = vector3(-1167.99, -1522.49, 4.40), points = {
            caller = vector4(-1167.99, -1522.49, 4.40, 349.0),
            resident = vector4(-1151.37, -1519.66, 4.36, 123.5),
            other = vector4(-1148.57, -1525.09, 4.35, 106.7),
            yard = vector4(-1153.73, -1516.03, 4.38, 305.4),
            source = vector4(-1144.89, -1518.33, 7.56, 13.9),
            car = vector4(-1157.45, -1521.22, 3.88, 219.7),
        } },
        { street = 'Bridge St', at = vector3(847.84, -195.34, 72.43), points = {
            caller = vector4(847.84, -195.34, 72.43, 130.1),
            resident = vector4(880.22, -205.41, 71.98, 141.3),
            other = vector4(875.65, -199.85, 70.78, 122.6),
            yard = vector4(878.73, -210.25, 70.78, 258.2),
            source = vector4(878.60, -193.28, 70.78, 258.8),
            car = vector4(871.46, -203.28, 70.36, 143.9),
        } },
    },

    stories = {
        -- ── A party, and someone who shouldn't drive home from it. ──────────────────────────────────────────────
        party = {
            weight = 3,
            setup = function(c)
                neighbour(c, {
                    c_heard = { "Music. The bass comes right through my bedroom wall. And thirty people singing, badly." },
                    c_who = { "Nice enough people, the rest of the year." },
                    c_long = { "Since eight. It was fine at eight." },
                    c_before = { "I knocked. Nobody heard me knock." },
                })
                c:person('resident', { at = 'resident', label = 'Resident', home = true, secret = math.random() < .5 and 'drunk' or 'clean', demeanor = 'chatty',
                    scene = 'WORLD_HUMAN_DRINKING', questions = RESIDENT_Q, lines = at_home(c, {
                        c_noise = { "Oh no. Is it that loud? It's a birthday. Forty. It only happens once.", "It's nearly over, I promise. Nearly." },
                        c_lives = { "Mine. Well, mine and the bank's. Do you want some cake?" },
                        c_down = { "Yes. Of course. Sorry. I'll go and find whoever's got the speaker." },
                    }) })
                c:person('other', { at = 'other', label = 'Guest', secret = 'drunk', demeanor = 'chatty', scene = 'WORLD_HUMAN_DRINKING', questions = GUEST_Q, lines = {
                    c_here = { "Two. Or the... it's a party. Nobody's counting." },
                    c_keys = { { "Driving. It's ten minutes. I do it all the time. Where did I put my... here they are.", set = { c_ride = 'yes' } } },
                    c_cab = { { "A cab? Okay. Yeah. You're right. Don't tell my wife how much it was.", set = { c_cabbed = 'yes' } } },
                    where = { "Home. Soon." },
                } })
                c:vehicle('car', { at = 'car', model = 'asea', make = 'Declasse', name = 'Asea', color = 'Silver', paint = 4, label = 'The vehicle', owner = 'other', locked = false })
                c:clue('yard', { at = 'yard', label = 'The side of the house', prop = 'prop_cs_beer_bot_01', scatter = { model = 'prop_plastic_cup_02', count = 6, radius = 2.5 },
                    text = 'Empty bottles and plastic cups all down the side of the house. A paper banner: Happy 40th.' })
                c:clue('source', { at = 'source', label = 'Where the noise is from', prop = 'prop_speaker_05',
                    text = 'A party speaker dragged to the open window, turned up as far as it goes.' })
                c:clue('car', { on = 'car', label = 'The vehicle on the drive', text = 'Parked across the pavement, one wheel on the lawn. An open can in the cup holder.' })
                card(c)
                wire(c)
                heard(c, 'Thumping bass from next door, and a lot of people singing.')
                local settle = resolve(c, 'resident', function(out)
                    local text = ('Noise complaint: a birthday party at the home of %s.'):format(c:name('resident')) .. part(c, out, 'resident') .. part(c, out, 'other')
                    if c:get('drove') and (not out.other or out.other == 'fled') then text = text .. ' The guest drove off after drinking and was not stopped.' end
                    return text
                end, { also = 'other', ready = function() return not c:get('cab') end }) -- (offered a cab: it's the cab that ends it)
                -- Nobody's spoken to them a while after the door's answered: they go for the car.
                local spoken, left = false, 25
                c:on('contact', function(who)
                    if who ~= 'other' then return end
                    spoken = true
                    c:reveal('driver')
                end)
                c:on('tick', function()
                    if spoken or not c:is_done('door') or c:who('other').cuffed then return end
                    left = left - 1
                    if left > 0 or c:task('other', 'drive', { car = 'car' }) == false then return end
                    spoken = true
                    c:set('drove', true)
                    c:reveal('driver')
                    c:say('resident', "Hey! You're not driving like that! Come back!")
                end)
                c:on('fact', function(_, fact)
                    if fact ~= 'c_cabbed' then return end
                    c:set('cab', true)
                    c:fare('other')
                    c:done('driver')
                    c:reveal('taxi')
                end)
                local function no_cab()
                    c:done('driver')
                    if not c:get('cab') then return end
                    c:set('cab', false)
                    c:fare('other', true)
                    c:done('taxi')
                end
                c:on('contact_ended', function(who, outcome)
                    if who ~= 'other' or outcome == 'cancelled' then return end
                    if outcome == 'fled' then no_cab() end
                    c:done('driver')
                end)
                c:on('act', function(who, action)
                    if who == 'other' and action == 'cuff' and c:who('other').cuffed then no_cab() end -- (changed their mind)
                end)
                c:on('dead', function(who)
                    if who ~= 'other' then return end
                    spoken = true
                    no_cab()
                end)
                c:on('gone', function(who) -- (waiting for a cab: that's how they went, wherever the taxi found them)
                    if who ~= 'other' or not c:get('cab') then return end
                    c:done('taxi')
                    c:set('cab', false)
                    settle('other', 'home')
                end)
                c:on('service', function(kind)
                    if kind ~= 'taxi' then return end
                    c:done('taxi')
                    c:set('cab', false)
                    settle('other', 'home')
                end)
            end,
        },

        -- ── The noise is a burglary. ─────────────────────────────────────────────────────────────────────────────
        sitter = {
            weight = 2,
            setup = function(c)
                neighbour(c, {
                    c_heard = { "Bumping. Dragging. Something heavy going down the stairs, over and over. At this hour." },
                    c_who = { { "The Mortons. Lovely family. Two weeks in Cayo Perico, they left on Sunday. I've got their post.", set = { c_away = 'yes' } } },
                    c_long = { "An hour. Maybe more." },
                    c_before = { "Spoken to who? There's nobody there. That's why I rang." },
                }, { demeanor = 'nervous' })
                c:person('resident', { at = 'resident', label = 'Resident', male = true, age = { 28, 46 }, secret = math.random() < .5 and 'warrant' or 'nervous', demeanor = 'polite',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = RESIDENT_Q, items = { "Jewellery box with someone else's initials on it" }, lines = {
                        c_noise = { { "Sorry, officer. Moving a bit of furniture. I'm house-sitting, they want the place decorated.", set = { c_sitter = 'yes' } } },
                        c_lives = { { "Not mine, no. I'm house-sitting for the family.", set = { c_sitter = 'yes' } } },
                        c_down = { "Absolutely. Nearly done. Sorry about that." },
                        c_owner = { "Mr Walker. Lovely fella. Known him for years." },
                        c_caught = cracks(2, { "They'll have forgotten. They're very busy people." },
                            { { "...Alright. Alright. It's not my house. Don't do this in front of the street.", set = { c_admit = 'yes' } } },
                            { "I told you. It's not my house." }),
                        explain = { "That's... they asked me to look after it." },
                        where = { "Nowhere. Bit of work to finish." },
                        live = { "I'm staying here for now. House-sitting." },
                    } })
                c:person('other', { at = 'other', label = 'Man', male = true, age = { 24, 44 }, secret = 'nervous', demeanor = 'nervous', runs = true, bail = 0.3,
                    scene = 'WORLD_HUMAN_SMOKING', questions = HELPER_Q, lines = {
                        c_here = { "Helping my mate move some stuff." },
                        c_whose = cracks(2, { "My mate's. Sort of. Ask him." },
                            { { "...I just drive the van. I was told they were on holiday. That's all I know.", set = { c_admit = 'yes' } } },
                            { "I told you. I drive the van." }),
                        where = { "Nowhere. Having a smoke." },
                    } })
                c:vehicle('car', { at = 'car', model = 'speedo', make = 'Vapid', name = 'Speedo', color = 'White', paint = 111, label = 'The vehicle', stolen = true, locked = false })
                c:clue('yard', { at = 'yard', label = 'The side of the house', prop = 'prop_tool_box_02',
                    text = 'A toolbox left open by the back door. The frame is split where the lock was forced.' })
                c:clue('source', { at = 'source', label = 'Where the noise is from', prop = 'prop_cardbordbox_02a', scatter = { model = 'prop_cardbordbox_03a', count = 3, radius = 1.5 },
                    text = 'Boxes stacked by the window. A family photo album on top of one, a television flex trailing out of another.' })
                c:clue('car', { on = 'car', label = 'The vehicle on the drive', text = 'A television, two laptops, a guitar and a child\'s bike, thrown in with no blankets. Nobody moves house like that.' })
                card(c)
                wire(c)
                heard(c, 'Bumps and something heavy being dragged, from next door.')
                resolve(c, 'resident', function(out)
                    local caught = out.resident == 'arrested' or out.other == 'arrested'
                    local text = 'Reported as noise: a burglary in progress at a house whose owners were away.' .. part(c, out, 'resident') .. part(c, out, 'other')
                    if caught and c:get('van_seen') then return text .. " Recorded: the family's belongings in the van." end
                    return caught and text or text .. ' Nobody was arrested for it.'
                end, { also = 'other' })
                local function suspect(fact)
                    if fact == 'c_away' or fact == 'c_sitter' then c:reveal('van') end
                    if fact == 'c_away' then give(c, 'resident', 'c_away') end
                end
                local pending = false -- (the man at the door is caught: his partner goes for the van when he can)
                c:on('fact', function(who, fact)
                    suspect(fact)
                    if who == 'resident' and fact == 'c_admit' then pending = true end
                end)
                c:on('inspect', function(clue)
                    if clue ~= 'car' then return end
                    c:set('van_seen', true)
                    c:reveal('van')
                    c:done('van')
                end)
                c:on('act', function(who, action)
                    if who == 'resident' and action == 'cuff' and c:who('resident').cuffed then pending = true end
                end)
                c:on('contact_ended', function(who, outcome) if who == 'other' and outcome ~= 'cancelled' then pending = false end end)
                c:on('dead', function(who) if who == 'other' then pending = false end end)
                c:on('tick', function()
                    local o = c:who('other')
                    if not pending or not o or o.cuffed or c:talking('other') or not c:health('other') then return end
                    if c:task('other', 'drive', { car = 'car', fast = true }) == false then return end
                    pending = false
                    c:reveal('van')
                    c:dispatch(('The van is leaving %s at speed. White Vapid Speedo, plate %s.'):format(c:street(), c:plate('car') or 'unknown'))
                end)
            end,
        },

        -- ── A hum, and a house full of plants. ──────────────────────────────────────────────────────────────────
        grow = {
            weight = 2,
            setup = function(c)
                neighbour(c, {
                    c_heard = { { "A hum. Low, all day and all night. You feel it in your teeth. And there's a smell, sweet, like something's gone off.", set = { c_smell = 'yes' } } },
                    c_who = { "A young man. Renting. Never see him. All the windows are blacked out." },
                    c_long = { "Three months. It never stops." },
                    c_before = { "He says it's a fish tank. I've never heard a fish tank through a wall." },
                })
                c:person('resident', { at = 'resident', label = 'Resident', male = true, age = { 22, 38 }, home = true, secret = 'drugs', demeanor = 'nervous',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = RESIDENT_Q, items = { 'Bag of cannabis', 'Receipts for grow lights' }, lines = at_home(c, {
                        c_noise = { "Noise? It's a pump. For the fish tank. It's a big tank." },
                        c_lives = { "I rent it. It's all above board. You don't need to come in." },
                        c_down = { "It's a pump. It doesn't really go down. I'll look into it." },
                        c_smell = cracks(3, { "That's the fish food. Tropical. It's a very particular smell." },
                            { { "...It's not mine. I just water them. He said it was easy money.", set = { c_admit = 'yes' } } },
                            { "I told you. I just water them." }),
                        explain = { "That's for personal use. All of it. Personal." },
                    }) })
                c:person('other', { at = 'other', label = 'Man', male = true, age = { 22, 40 }, secret = 'nervous', demeanor = 'rude',
                    scene = 'WORLD_HUMAN_SMOKING', questions = HELPER_Q, lines = {
                        c_here = { "Having a smoke. It's a free country." },
                        c_whose = cracks(2, { "I don't know. I'm just stood here." },
                            { { "...I get paid to tell him if anyone comes. That's it. I don't go inside.", set = { c_admit = 'yes' } } },
                            { "I told you. I just stand here." }),
                        where = { "Nowhere you need to know about." },
                    } })
                c:vehicle('car', { at = 'car', model = 'primo', make = 'Albany', name = 'Primo', color = 'Black', paint = 0, label = 'The vehicle', owner = 'resident' })
                c:clue('yard', { at = 'yard', label = 'The side of the house', text = 'Silver ducting taped into a blacked-out window. Warm air coming out of it, and the smell of cannabis.' })
                c:clue('source', { at = 'source', label = 'Where the noise is from', prop = 'prop_generator_03b',
                    text = 'A generator running under a tarp, with a cable as thick as a thumb going in through the wall. That is the hum.' })
                c:clue('car', { on = 'car', label = 'The vehicle on the drive', text = 'Bags of compost and a roll of foil tape on the back seat.' })
                card(c)
                wire(c)
                heard(c, 'A low hum from next door. You feel it more than you hear it.')
                resolve(c, 'resident', function(out)
                    local on = {}
                    if c:get('duct') then on[#on + 1] = 'the ducting' end
                    if c:is_done('power') then on[#on + 1] = 'the generator' end
                    if c:who('resident').facts.found then on[#on + 1] = 'what he had on him' end
                    if c:who('resident').facts.c_admit then on[#on + 1] = 'his admission' end
                    local who = c:name('resident')
                    local text = on[1] and ('Reported as noise: a cannabis grow at the home of %s. Recorded: %s.'):format(who, table.concat(on, ', '))
                        or ('Noise complaint: a constant hum from the home of %s. Its cause was not found.'):format(who)
                    return text .. part(c, out, 'resident') .. part(c, out, 'other')
                end)
                local function lead()
                    c:reveal('power')
                    give(c, 'resident', 'c_smell')
                end
                c:on('fact', function(_, fact) if fact == 'c_smell' then lead() end end)
                c:on('inspect', function(clue)
                    if clue == 'yard' then c:set('duct', true) end
                    lead()
                    if clue == 'source' then c:done('power') end
                end)
            end,
        },

        -- ── The caller started it. ───────────────────────────────────────────────────────────────────────────────
        feud = {
            weight = 2,
            setup = function(c)
                neighbour(c, {
                    c_heard = { "The same song. The same song, for four hours, pointed at my house. He's doing it on purpose." },
                    c_who = { "An animal. That's who. I was here first." },
                    c_long = { "Tonight? Since six. The whole thing? Two years." },
                    c_before = { "I've written to the council. Nine times." },
                    c_key = cracks(2, { "Me? I don't know anything about his car. Why would I know about his car?" },
                        { { "...He cut my hedge. Twenty years, that hedge. So yes. Once. Down the whole side.", set = { c_admit = 'yes' } } },
                        { "I told you. He cut my hedge." }),
                    explain = { "That's my door key. Things get on keys." },
                }, { demeanor = 'polite', items = { 'Door key with paint in its teeth' } })
                c:person('resident', { at = 'resident', label = 'Resident', male = true, home = true, secret = 'clean', demeanor = 'rude',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = RESIDENT_Q, lines = at_home(c, {
                        c_noise = { { "Good. Tell them to look at my car. Then we'll talk about noise.", set = { c_scratch = 'yes' } } },
                        c_lives = { "Yes. And it's my fence, whatever they've told you." },
                        c_down = { "When I get paid for the paint, I'll think about it." },
                        c_speakers = { "It's my garden. I can point them where I like. I know what they did. I can't prove it, so I'm playing music." },
                    }) })
                c:vehicle('car', { at = 'car', model = 'premier', make = 'Declasse', name = 'Premier', color = 'White', paint = 111, label = 'The vehicle', owner = 'resident' })
                c:clue('yard', { at = 'yard', label = 'The side of the house', text = 'A hedge along the shared fence, cut straight back to bare wood on this side. Whoever did it took their time.' })
                c:clue('source', { at = 'source', label = 'Where the noise is from', prop = 'prop_speaker_06',
                    text = 'A pair of speakers on the fence, aimed across at the house next door and nowhere else. A phone taped to one, one song on repeat.' })
                c:clue('car', { on = 'car', label = 'The vehicle on the drive', text = 'One long scratch down the whole side, through the paint to the metal. Done with a key, slowly.' })
                card(c)
                wire(c)
                heard(c, 'One song, very loud, starting again as you pull up.')
                local function took_it()
                    c:reveal('scratch')
                    c:done('scratch')
                    give(c, 'caller', 'c_key')
                    c:blip('decide', { 'resident', 'caller' })
                end
                c:on('fact', function(_, fact) if fact == 'c_scratch' then c:reveal('scratch') end end)
                c:on('inspect', function(clue)
                    if clue == 'car' then took_it() end
                    if clue == 'source' then give(c, 'resident', 'c_speakers') end
                end)
                resolve(c, 'resident', function(out)
                    local text = ('Neighbour dispute: %s was playing music at %s on purpose.'):format(c:name('resident'), c:name('caller'))
                    if c:who('caller').facts.c_admit then text = text .. (' %s admitted keying his car.'):format(c:name('caller')) end
                    return text .. part(c, out, 'resident') .. part(c, out, 'caller')
                end, { also = 'caller' })
            end,
        },

        -- ── He can't hear it. ────────────────────────────────────────────────────────────────────────────────────
        deaf = {
            weight = 2,
            setup = function(c)
                neighbour(c, {
                    c_heard = { "The television. Game shows, at full volume, till three in the morning. I can tell you the answers." },
                    c_who = function() return { ("Mr. %s. Eighty-odd. His wife died last spring, she was the one who told him when it was too loud."):format(c:who('resident').person.last) } end,
                    c_long = { "Since Tuesday. It's never been this bad." },
                    c_before = { "I've knocked. He doesn't hear the door. He doesn't hear anything." },
                }, { demeanor = 'polite' })
                -- Hears nothing right until he has his hearing aid back.
                local function hears(wrong, right)
                    return function(o) return o.facts.c_back and right or wrong end
                end
                c:person('resident', { at = 'resident', label = 'Resident', model = 'a_m_o_genstreet_01', male = true, age = { 79, 90 }, home = true, secret = 'clean', demeanor = 'chatty',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = RESIDENT_Q, lines = at_home(c, {
                        c_noise = hears({ "Toys? No, thank you. No grandchildren.", "Boys? There's no boys here. Just me." },
                            { "Noise? ...Oh. Oh dear. Is that the television? Margaret always told me when it was too loud." }),
                        c_lives = hears({ "Mouse? I've had the man round about that.", "Eh? You'll have to speak up." },
                            { "Forty-one years. We bought it the week we married." }),
                        c_down = hears({ "Brown? No, that door's always been green.", "Eh?" },
                            { "Of course. I'll switch it off now. Nobody said. Tell them I'm sorry, will you?" }),
                        c_aid = { { "My... oh! There it is! I've been looking for that since Tuesday. Hold on. ...Goodness. You've got quite a voice.", set = { c_back = 'yes' } } },
                    }) })
                c:vehicle('car', { at = 'car', model = 'emperor', make = 'Albany', name = 'Emperor', color = 'Silver', paint = 4, label = 'The vehicle', owner = 'resident' })
                c:clue('yard', { at = 'yard', label = 'The side of the house', prop = 'prop_ld_can_01',
                    text = 'A tin of bird seed tipped over on the path, and a small beige hearing aid lying in the spilt seed.' })
                c:clue('source', { at = 'source', label = 'Where the noise is from', text = 'A game show through the window, loud enough to rattle the glass. One armchair, and a second that nobody has moved.' })
                c:clue('car', { on = 'car', label = 'The vehicle on the drive', text = 'Dust on the windscreen and flat front tyres. This has not moved in a long time.' })
                card(c)
                wire(c)
                heard(c, 'A television at full volume. A studio audience applauding.')
                c:on('inspect', function(clue)
                    if clue ~= 'yard' then return end
                    c:reveal('aid')
                    give(c, 'resident', 'c_found')
                end)
                c:on('fact', function(_, fact) if fact == 'c_back' then c:done('aid') end end)
                resolve(c, 'resident', function(out)
                    return 'Noise complaint: an elderly man who could not hear his own television.'
                        .. (c:who('resident').facts.c_back and ' His hearing aid was found in the garden and given back.' or ' His hearing aid was not found, and the noise may go on.')
                        .. part(c, out, 'resident')
                end)
            end,
        },
    },
})
