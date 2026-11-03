--[[
    c3r callout: DISTURBANCE AT A STRIP CLUB.

    Security have put a customer out and want police. The report is the same every time, and the card is too: security, the
    customer, the dancer at the staff door and the door book (four units can take one each). Why he was put out is one of
    four stories:
      drunk     cut off, and he means to drive home: a cab, his keys or the cells. Let go, he gets in his car and goes
      hands     a house rule broken and a complaint from a dancer: she wants him charged, or just barred. Sometimes he swings
      tab       he's angry and he's right: the bill's been padded and security are holding his wallet
      fixated   polite, sober, and he knows where she lives: the proof is in his pocket and his car, and he runs from it
    It's dealt with when everyone arrested has been taken in and the one it's about has been let go or got away, or the
    customer's been reached and every unit has left.

    Points per location: walk them out in game with /c3rplace stripclub (it writes the location in below).
]]

local SECURITY_Q = {
    { id = 'c_what', label = "What's the problem?" },
    { id = 'c_why', label = 'Why did you put him out?', stress = true },
    { id = 'c_know', label = 'Has he been in before?' },
    { id = 'c_bill', label = "He says the bill's wrong and you've kept his wallet.", needs = { c_bill = true }, stress = true, press = true },
    { id = 'c_giveback', label = 'Give him his wallet back.', needs = { c_held = true } },
}
local CUSTOMER_Q = {
    { id = 'c_here', label = 'Why did they put you out?', stress = true },
    { id = 'c_drink', label = 'How much have you had to drink?', stress = true },
    { id = 'c_home', label = 'How are you getting home?' },
    { id = 'c_cab', label = 'Do you want me to call you a cab?', needs = { c_ride = true } },
    { id = 'c_keys', label = "Give me your car keys.", needs = { c_ride = true } },
    { id = 'c_complaint', label = "There's a complaint about you, and it's not the first.", needs = { c_complaint = true }, stress = true, press = true },
    { id = 'c_address', label = 'Whose address is this?', needs = { c_address = true }, stress = true },
}
local DANCER_Q = {
    { id = 'c_saw', label = 'What happened tonight?', stress = true },
    { id = 'c_know', label = 'Do you know him?' },
    { id = 'c_statement', label = 'Do you want to make a complaint?', needs = { c_complaint = true } },
}
local CALLED = { customer = 'The customer', security = 'Security', dancer = 'The dancer' }

-- Denies it until pressed `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

-- They've been given a fact from elsewhere: it opens their questions.
local function tell(c, key, fact)
    local o = c:who(key)
    if not o or o.facts[fact] then return end
    o.facts[fact] = 'yes'
    c:questions(key)
end

local function card(c)
    c:objective('security', 'Talk to security', { hint = 'On the door.', blip = 'security' })
    c:objective('customer', 'Speak to the customer', { hint = 'Out front.', blip = 'customer' })
    c:objective('dancer', 'Hear from the dancer', { hint = 'At the staff door.', blip = 'dancer' })
    c:objective('book', 'Check the door book', { hint = 'By the door.', blip = 'book' })
    c:objective('taxi', 'Keep him off the road', { hidden = true, who = 'all', blip = 'customer', hint = 'Take his keys or offer a cab. A cab comes by radio, or G.' })
    c:objective('stop', 'Stop his car', { hidden = true, who = 'all', blip = 'car', hint = "He's driving drunk. Pull him over." })
    c:objective('complaint', 'Take her complaint', { hidden = true, who = 'all', blip = 'dancer', hint = 'Ask her if she wants to make one.' })
    c:objective('bill', 'Sort out the bill', { hidden = true, who = 'all', blip = 'security', hint = 'The tab is in the door book.' })
    c:objective('find', 'Find out what he has on her', { hidden = true, who = 'all', blip = { 'customer', 'car' }, hint = 'Search him, and look at his car.' })
    c:objective('subdue', 'Get him under control', { hidden = true, who = 'all', blip = 'customer', hint = 'Press E beside him, or the PA with your gun out. The taser works too.' })
    c:objective('medic', 'Call paramedics', { hidden = true, who = 'all', hint = 'Radio for an ambulance.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let him go', { after = { 'customer' }, who = 'all', blip = 'customer' })
end

-- Done when: security have said what the problem is, she's said what happened, the book's been read, he's been reached.
local function wire(c)
    c:on('act', function(who, action, arg)
        if action ~= 'ask' then return end
        if who == 'security' and arg == 'c_what' then c:done('security') end
        if who == 'dancer' and arg == 'c_saw' then c:done('dancer') end
    end)
    c:on('inspect', function(clue) if clue == 'book' then c:set('book_seen', true) c:done('book') end end)
    c:on('contact', function(who) if who == 'customer' then c:done('customer') end end)
    c:on('dead', function(who) if CALLED[who] then c:done(who) end end)
    c:on('gone', function(who) if who == 'customer' then c:done('customer') end end)
    c:on('towed', function(car) if car == 'car' then c:set('no_car', true) end end)
end

--[[ It's over when everyone arrested has been taken in, the customer's been taken in, the one it's about (culprit) has been
     let go or got away, or the customer's been reached and every unit has left.
     opts.ready() (false: being let go doesn't count: there's more to find out, or a cab to wait for. It's read as the talking
     ends, so a let-go that came too early stays one until they're let go again), opts.over() (true: it's settled without
     anyone being dealt with).
     ends(out) -> the MDT summary; out[person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' | 'pronounced' |
     'hospital' | 'treated' | 'home'; out.left = true. -> gone_with(how): the one it's about has left with someone ]]
local function resolve(c, culprit, ends, opts)
    opts = opts or {}
    local out, taken, away_for, done, settled = {}, {}, 0, false, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local LET_GO = { released = true, cited = true, warning = true, fled = true, home = true }
    local SEEN = { pronounced = true, hospital = true, treated = true }
    local function check()
        if done or waiting() then return end
        local dealt = taken[culprit] or taken.customer or SEEN[out[culprit]] or settled or (opts.over and opts.over())
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
    c:on('contact', function(who) if who == culprit then settled = false end end) -- (back with them: it's open again)
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true end
        if out[who] == 'dead' then
            out[who] = 'pronounced' -- (the coroner's been)
            c:done('medic')
        end
        if who ~= culprit then return end
        out[who] = out[who] or 'fled'
        settled = LET_GO[out[who]] or false
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if not CALLED[who] then return end
        c:reveal('medic')
        c:blip('medic', who)
        c:dispatch(('%s is down. Paramedics needed at the scene.'):format(CALLED[who]))
    end)
    c:on('aid', function(who, what)
        if what ~= 'pronounced' and what ~= 'hospital' and what ~= 'treated' then return end
        out[who] = what
        c:done('medic')
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or SEEN[out[who]] then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        if who == culprit and LET_GO[out[who]] and (outcome == 'fled' or not opts.ready or opts.ready()) then
            settled = true
            c:done('decide')
        end
    end)
    c:on('tick', function()
        check()
        local here = c:near(nil, 80.0) or c:near('customer', 200.0) or c:talking() -- (200: a car following him)
        if c:is_done('customer') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then
                out.left = true
                check()
            end
        else
            away_for = 0
        end
    end)
    return function(how) -- (not someone arrested or dead in the meantime)
        if out[culprit] == 'arrested' or out[culprit] == 'dead' then return end
        out[culprit], settled = how, true
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
    if how == 'hospital' then return (' %s went with paramedics.'):format(s) end
    if how == 'treated' then return (' %s was seen by paramedics at the scene.'):format(s) end
    if how == 'dead' or how == 'pronounced' then return (' %s died at the scene.'):format(s) end
    return ''
end

-- The people every story has. lines: what each says; book: what the door book says.
local function people(c, spec, lines, book)
    lines.customer.where = lines.customer.where or { "Nowhere. Out here, where they put me." }
    c:person('security', { at = 'security', label = 'Security', male = true, model = 's_m_m_bouncer_01', age = { 28, 48 }, secret = 'clean', demeanor = 'polite',
        items = spec.security_items or {}, scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = SECURITY_Q, lines = lines.security })
    c:person('customer', { at = 'customer', label = 'Customer', male = true, age = { 26, 55 }, secret = spec.secret or 'clean', demeanor = spec.demeanor or 'rude',
        items = spec.items or {}, scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = CUSTOMER_Q, lines = lines.customer })
    c:person('dancer', { at = 'dancer', label = 'Dancer', male = false, age = { 23, 38 }, secret = 'clean', demeanor = spec.dancer or 'nervous',
        scene = 'WORLD_HUMAN_SMOKING', questions = DANCER_Q, lines = lines.dancer })
    c:clue('book', { at = 'book', label = 'Door book', text = book })
    c:vehicle('car', { at = 'car', model = 'asea', make = 'Declasse', name = 'Asea', color = 'Silver', paint = 4, owner = 'customer', locked = false, label = 'His car' })
end

-- Let go with nothing stopping him, he gets in his car and goes. -> false: he can't
local function drives_off(c)
    if c:get('no_car') or c:task('customer', 'drive', { car = 'car' }) == false then return false end
    c:set('drove', true)
    return true
end

Callout({
    id = 'stripclub',
    name = 'Disturbance at a strip club',
    voice = 'call_stripclub', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        'Security at a strip club have put a customer out and want police.',
        "Door staff say a customer won't leave the club car park.",
        "Caller says there's shouting outside a strip club and security can't move someone on.",
    },
    -- The points each location needs, in the order /c3rplace stripclub walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it).
    points = {
        { 'security', 'Head of security, on the club door.' },
        { 'customer', 'The customer, on the pavement or in the car park, 10 to 15 m from the door.' },
        { 'dancer', 'The dancer at the staff or side door, at least 15 m from the customer: she has to be able to talk.' },
        { 'book', 'The door book: a spot on the wall or counter by the door.' },
        { 'car', "The customer's car, in the car park. Sit in a car parked there.", 'car' },
    },
    -- Add more with /c3rplace stripclub in game (it writes them here). This one is a rough placeholder at the Vanilla Unicorn
    locations = {
        { street = 'Strawberry Ave', at = vector3(127.55, -1299.73, 29.23), points = {
            security = vector4(127.55, -1299.73, 29.23, 210.4),
            customer = vector4(138.36, -1301.14, 29.20, 183.7),
            dancer = vector4(117.10, -1294.64, 29.27, 316.2),
            book = vector4(129.53, -1287.60, 29.28, 321.3),
            car = vector4(153.71, -1311.16, 28.78, 243.7),
        } },
    },

    stories = {
        -- ── Too drunk, and he means to drive. ────────────────────────────────────────────────────────────────────
        drunk = {
            weight = 3,
            setup = function(c)
                people(c, { secret = 'drunk', demeanor = 'chatty', dancer = 'chatty' }, {
                    security = {
                        c_what = { "Put a customer out tonight and he won't move off the lot. I want it on record, and I want him gone." },
                        c_why = { "Cut off. Then he fell on a table. Then he fell on a different table. He's had enough." },
                        c_know = { "First time I've seen him. Hope it's the last." },
                    },
                    customer = {
                        c_here = { "Too... too what? I'm fine. I'm absolutely fine. Ask the big guy. He likes me." },
                        c_drink = { "Four. Four-ish. Is a bottle one? I don't know how you're counting." },
                        c_home = { { "Drive! Car's right there. I'm a great driver. Ask anyone.", set = { c_ride = 'yes' } } },
                        c_cab = { { "A cab? You'd do that? You're a good cop. You're the best cop.", set = { c_cabbed = 'yes' } } },
                        c_keys = { { "My keys? ...Fine. Here. You're the boss. Mind the little bear on them.", set = { c_keyed = 'yes' } } },
                    },
                    dancer = {
                        c_saw = { { "He's harmless. He kept telling everyone he's driving home to Sandy Shores tonight. He could hardly find the door.", set = { c_tip = 'yes' } } },
                        c_know = { "Never seen him. He tips well, if he can find his pocket." },
                    },
                }, "Tonight's entry: 'Cut off, put out, unsteady on his feet.' His tab is clipped to the page: eleven drinks in ninety minutes. Someone has written 'keys?' in the margin.")
                card(c)
                wire(c)
                local gone_with
                local function risk() -- (somebody's noticed: it's on the card, and he can be asked)
                    if c:get('safe') or c:get('drove') then return end
                    c:reveal('taxi')
                    tell(c, 'customer', 'c_ride')
                end
                c:on('fact', function(who, fact)
                    if fact == 'c_ride' or fact == 'c_tip' then risk() end
                    if who ~= 'customer' then return end
                    if fact == 'c_keyed' then
                        c:set('safe', true)
                        c:set('keys', true)
                        c:set('cab', false) -- (nothing to wait for now: a cab's only a kindness)
                        c:done('taxi')
                        c:note('His car keys were taken off him')
                    elseif fact == 'c_cabbed' then
                        c:fare('customer')
                        if c:get('keys') then return end
                        c:set('cab', true)
                        c:reveal('taxi')
                    end
                end)
                c:on('inspect', function(clue) if clue == 'book' then risk() end end)
                c:on('act', function(who, action)
                    if who ~= 'customer' then return end
                    if action == 'breath' then risk() end
                    if action ~= 'cuff' or not c:who('customer').cuffed then return end
                    c:done('taxi')
                    if c:get('drove') then c:done('stop') end
                    c:set('cab', false) -- (changed their mind: no cab now)
                    c:fare('customer', true)
                end)
                c:on('service', function(kind)
                    if kind ~= 'taxi' then return end
                    c:done('taxi')
                    c:set('cab', false)
                    c:set('safe', true)
                    gone_with('home')
                end)
                c:on('contact', function(who)
                    if who ~= 'customer' or not c:get('drove') then return end
                    c:set('safe', true)
                    c:set('stopped', true)
                    c:done('stop')
                end)
                c:on('contact_ended', function(who, outcome) -- (before resolve: it reads the same state)
                    if who ~= 'customer' or c:get('safe') or c:get('cab') or c:get('drove') or c:who('customer').cuffed then return end
                    if outcome ~= 'released' and outcome ~= 'cited' and outcome ~= 'warning' then return end
                    if not drives_off(c) then return c:set('safe', true) end
                    c:hide('taxi')
                    c:reveal('stop')
                    c:dispatch('The customer is getting into his car. He is in no state to drive.')
                end)
                gone_with = resolve(c, 'customer', function(out)
                    local text = 'A customer put out of a strip club for being too drunk.' .. part(c, out, 'customer')
                    if c:get('keys') then text = text .. ' His car keys were taken off him.' end
                    if c:get('stopped') then text = text .. ' He was stopped after driving off.'
                    elseif c:get('drove') then text = text .. ' He drove away drunk and nobody stopped him.' end
                    return text
                end, { ready = function() return c:get('safe') and not c:get('cab') end }) -- (a cab: it's the cab that ends it)
            end,
        },

        -- ── A house rule and a complaint. ────────────────────────────────────────────────────────────────────────
        hands = {
            weight = 3,
            setup = function(c)
                local charge = math.random() < .6
                people(c, { demeanor = 'rude' }, {
                    security = {
                        c_what = { "Put a customer out tonight and he won't move off the lot. I want it on record, and I want him gone." },
                        c_why = { "House rules. He knows which one. One of the girls can tell you if she wants to. I'm not saying it for her." },
                        c_know = { "He's in the book. Look at the book." },
                    },
                    customer = {
                        c_here = { "Nothing! A misunderstanding. I paid to be in there and that gorilla walks me out in front of everyone." },
                        c_drink = { "A couple. That's not why I'm out here." },
                        c_home = { "Same way I got here. When I'm ready." },
                        c_complaint = cracks(3, { "What complaint? I didn't do anything. Who said that?" },
                            { { "...Alright. I was told. I was told twice. It won't happen again.", set = { c_admit = 'yes' } } },
                            { "I said. It won't happen again." }),
                    },
                    dancer = {
                        c_saw = { { "He broke the rule. Security told him, and he broke it again. That's all I'm putting into words out here.", set = { c_complaint = 'yes' } } },
                        c_know = { "He's been in before. It's not the first time he's been told." },
                        c_statement = { charge and { "Yes. I'm tired of being told it comes with the job. Put it on record. I want him charged.", set = { c_statement = 'charge' } }
                            or { "I want it on record and I want him barred. I don't want a courtroom. I just want him gone.", set = { c_statement = 'barred' } } },
                    },
                }, "Tonight's entry: 'House rule. Put out. Complaint from staff.' The same name appears twice more this month, both marked 'final warning'.")
                card(c)
                wire(c)
                local spoken, swinging, fighting, left = false, false, false, 0
                local function give_up(line)
                    fighting = false
                    local o = c:who('customer')
                    o.ran, o.gave_up = true, true -- (he's done: going for the cuffs won't send him running now)
                    c:done('subdue')
                    c:say('customer', line)
                    c:task('customer', 'surrender')
                end
                c:on('fact', function(who, fact)
                    if who == 'dancer' and fact == 'c_complaint' then
                        c:reveal('complaint')
                        tell(c, 'customer', 'c_complaint')
                    elseif who == 'dancer' and fact == 'c_statement' then
                        c:set('statement', c:who('dancer').facts.c_statement)
                        c:done('complaint')
                        c:note('Complaint taken from a member of staff')
                    end
                end)
                c:on('inspect', function(clue) if clue == 'book' then tell(c, 'customer', 'c_complaint') end end)
                c:on('act', function(who, action, arg)
                    if who ~= 'customer' or action ~= 'ask' or arg ~= 'c_complaint' or spoken then return end
                    spoken = true
                    swinging = not c:who('customer').cuffed and math.random() < .25
                end)
                c:on('tick', function()
                    local o = c:who('customer')
                    if not o or o.cuffed or c:get('dead') then return end
                    if swinging then -- (a moment after he's answered)
                        swinging, fighting, left = false, true, math.random(30, 75)
                        c:set('swung', true)
                        c:reveal('subdue')
                        c:say('customer', "You're all the same! Get off me!")
                        c:note('The customer swung at an officer')
                        c:task('customer', 'shoot')
                    end
                    if not fighting then return end
                    local health = c:health('customer')
                    left = c:near('customer', 45.0) and left - 1 or left
                    if health and health > 100 and health < 150 then give_up("Okay! Okay! I'm done!")
                    elseif left <= 0 then give_up("Alright! Alright. I'm done.") end
                end)
                c:on('hail', function(who)
                    if who == 'customer' and fighting and math.random() < 0.5 then give_up("Alright! Alright! Hands up!") end
                end)
                -- ponytail: 'stunned' reaches a fists fight only through lwk_taser's barbs: the game's own stun gun leaves it to the clock
                c:on('stunned', function(who) if who == 'customer' and fighting then give_up("Okay! Okay! I'm done!") end end)
                c:on('dead', function(who) if who == 'customer' then fighting = false c:set('dead', true) c:done('subdue') end end)
                resolve(c, 'customer', function(out)
                    local text = 'A customer put out of a strip club after a complaint from a member of staff.' .. part(c, out, 'customer')
                    local said = c:get('statement')
                    if said == 'charge' then text = text .. ' She asked for him to be charged.'
                    elseif said == 'barred' then text = text .. ' She asked for him to be barred, no more.'
                    else text = text .. ' No statement was taken from her.' end
                    if c:get('book_seen') then text = text .. ' The door book shows two earlier final warnings.' end
                    if c:get('swung') then text = text .. ' He swung at an officer.' end
                    return text
                end, { ready = function() return c:get('statement') end }) -- (letting him go before she's been heard isn't an ending)
            end,
        },

        -- ── A padded bill: he's angry, and he's right. ───────────────────────────────────────────────────────────
        tab = {
            weight = 2,
            setup = function(c)
                people(c, { demeanor = 'rude', security_items = { "Customer's wallet and bank card" } }, {
                    security = {
                        c_what = { "Put a customer out tonight and he won't move off the lot. I want it on record, and I want him gone." },
                        c_why = { "Got aggressive over his bill. Customers pay what they owe, or they leave. He's done neither." },
                        c_know = { "No. They don't come back twice, that sort." },
                        c_bill = cracks(2, { "Bill's the bill. Take it up with the office. I've got nothing of his." },
                            { { "...Alright. It's in my jacket. I hold it till they pay. That's how we do it here. The bill's not my department.", set = { c_admit = 'yes', c_held = 'yes' } } },
                            { "I told you. It's in my jacket." }),
                        c_giveback = { { "...Fine. Here. Bill's void, tell him. Just get him off the lot.", set = { c_returned = 'yes' } } },
                    },
                    customer = {
                        c_here = { { "Two thousand dollars! For a beer! I said no, and that gorilla took my wallet. Arrest HIM!", set = { c_bill = 'yes' } } },
                        c_drink = { "One beer. ONE. Check the bill. Oh wait, I can't. He's got it." },
                        c_home = { "How? My wallet's in there with him. I'm not going anywhere." },
                    },
                    dancer = {
                        c_saw = { { "Quiet one. One beer, watched the game. Then his bill came and he went through the roof. Ask to see his tab.", set = { c_tip = 'yes' } } },
                        c_know = { "No. They do this to the ones from out of town. I didn't say that." },
                    },
                }, "Tonight's entry: 'Aggressive over bill. Put out.' The tab clipped to it shows one beer, then eleven bottles of champagne rung up to his card in twenty minutes, at a table he never sat at.")
                card(c)
                wire(c)
                local function query() -- (now there's a question to put to security)
                    c:reveal('bill')
                    tell(c, 'security', 'c_bill')
                end
                local function evidence()
                    c:set('proof', true)
                    query()
                    c:blip('decide', 'security')
                end
                c:on('fact', function(who, fact)
                    if fact == 'c_bill' or fact == 'c_tip' then query() end
                    if who ~= 'security' then return end
                    if fact == 'c_admit' then
                        evidence()
                    elseif fact == 'c_returned' then
                        c:set('returned', true)
                        c:done('bill')
                        c:note("The customer's wallet was handed back")
                    end
                end)
                c:on('inspect', function(clue) if clue == 'book' then evidence() end end)
                c:on('act', function(who, action)
                    if who ~= 'security' then return end
                    if action == 'cite' or (action == 'cuff' and c:who('security').cuffed) then c:done('bill') end
                    if c:who('security').facts.found then -- (here, not on 'fact': the engine's still going through their facts then)
                        evidence()
                        tell(c, 'security', 'c_held')
                    end
                end)
                resolve(c, 'security', function(out)
                    local text = 'A customer put out of a strip club over a bill.'
                    if c:get('proof') then text = text .. ' The bill had been padded and security had kept his wallet.'
                    else text = text .. ' The bill was never looked at.' end
                    if c:get('returned') then text = text .. ' The wallet was handed back: the bill is a civil matter.' end
                    return text .. part(c, out, 'security') .. part(c, out, 'customer')
                end, { ready = function() return c:get('proof') end, -- (telling him he's free to go before you know what he did isn't an ending)
                       over = function() return c:get('returned') and not c:talking() end })
            end,
        },

        -- ── He knows where she lives. ────────────────────────────────────────────────────────────────────────────
        fixated = {
            weight = 2,
            setup = function(c)
                people(c, { secret = 'nervous', demeanor = 'polite', items = { 'Folded note with a home address on it' } }, {
                    security = {
                        c_what = { "Put a customer out tonight and he won't move off the lot. I want it on record, and I want him gone." },
                        c_why = { "Nothing you'd call trouble. Polite as you like. He just won't stop asking when one of the girls finishes. I don't like it, so he's out." },
                        c_know = { "Four nights running. It's in the book." },
                    },
                    customer = {
                        c_here = { "A misunderstanding. I asked a question. I'm sure it's fine. I was about to leave." },
                        c_drink = { "A soda. I'm driving." },
                        c_home = { "My car. It's just there. Am I free to go?" },
                        c_address = { { "...I only have it so I can make sure she gets home safe. Somebody has to. You wouldn't understand.", set = { c_admit = 'yes' } } },
                    },
                    dancer = {
                        c_saw = { { "He's here every night I work. Four nights now, and he only asks for me. Tonight he used my real name. Nobody here knows my real name.", set = { c_tip = 'yes' } } },
                        c_know = { "Only from in there. I think. There was a car on my street on Tuesday." },
                    },
                }, "Four nights in a row, the same name. Tonight's entry: 'Barred.' A staff note beside it: 'Asked what time she finishes. Asked her real name.' His plate is written in the margin.")
                c:clue('note', { on = 'car', label = 'His car', hidden = true, text = 'On the passenger seat: a street map with one block circled, and a handwritten list of dates and times. They are her shifts.' })
                card(c)
                wire(c)
                local function lead()
                    c:reveal('find')
                    c:reveal('note')
                end
                local function evidence(how)
                    c:set(how, true)
                    if c:get('proof') then return end
                    c:set('proof', true)
                    lead()
                    c:done('find')
                    tell(c, 'customer', 'c_address')
                end
                c:on('fact', function(_, fact) if fact == 'c_tip' then lead() end end)
                c:on('inspect', function(clue)
                    if clue == 'book' then lead() end
                    if clue == 'note' then evidence('seat') end
                end)
                local spoken, bolting = false, false
                c:on('act', function(who, action, arg)
                    if who ~= 'customer' then return end
                    if c:who('customer').facts.found then evidence('pocket') end -- (here, not on 'fact': the engine's still going through their facts then)
                    if action ~= 'ask' or arg ~= 'c_address' or spoken then return end
                    spoken = true
                    bolting = not c:who('customer').cuffed
                end)
                c:on('tick', function() -- (a moment after he's answered, or the stop's first order overrides it)
                    if not bolting then return end
                    bolting = false
                    local o = c:who('customer')
                    if o and not o.cuffed and c:talking('customer') then c:task('customer', 'flee') end
                end)
                c:on('contact_ended', function(who, outcome) -- (before resolve: it reads the same state)
                    if who ~= 'customer' or c:get('proof') or c:who('customer').cuffed then return end
                    if outcome == 'released' or outcome == 'cited' or outcome == 'warning' then drives_off(c) end
                end)
                resolve(c, 'customer', function(out)
                    local text = 'A customer barred from a strip club after four nights asking for one dancer.' .. part(c, out, 'customer')
                    if c:get('pocket') then text = text .. ' He had her home address on him.' end
                    if c:get('seat') then text = text .. ' His car held a map and a list of her shifts.' end
                    if out.customer == 'fled' then text = text .. ' Attempt to locate: his plate is in the door book.' end
                    if not c:get('proof') then text = text .. ' Nothing was found to show what he wanted with her.' end
                    return text
                end, { ready = function() return c:get('proof') end }) -- (let go knowing nothing: he drives off, and it ends when the units do)
            end,
        },
    },
})
