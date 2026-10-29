--[[
    c3r callout: STORE ROBBERY.

    The clerk calls it in: someone's robbed the store and run. What really happened is one of three stories, and the
    card, the people on scene and the questions are the same for all of them: the clerk, a witness outside and the CCTV
    first (three units can take one each), then the area they went, where there's a young man.
      robbery    a man with a knife and a bandana over his face took the till; he's hiding nearby with the cash
      inside     the clerk staged it to cover a debt: the recording has a gap, nobody came out of the store, and the till
                 money is on him. The man out there had nothing to do with it: he's been on the phone for half an hour
      shoplift   a teenager walked out with a couple of beers and some chips; the clerk called it a robbery
    It's dealt with when everyone arrested has been taken in, the one it's about is let go or gets away, or the clerk's
    been heard and every unit has left (nobody still talking to anyone).

    Points per location: walk them out in game with /c3rplace robbery (it writes the location in below).
]]

local CLERK_Q = {
    { id = 'c_what', label = 'What happened?' },
    { id = 'c_amount', label = 'How much did they take?' },
    { id = 'c_weapon', label = 'Did they have a weapon?' },
    { id = 'c_way', label = 'Which way did they go?' },
    { id = 'c_look', label = 'What did they look like?' },
    { id = 'c_camera', label = 'Why is there a gap in the CCTV?', needs = { c_gap = true }, stress = true, press = true },
}
local WITNESS_Q = {
    { id = 'c_saw', label = 'What did you see?' },
    { id = 'c_way', label = 'Which way did they go?' },
    { id = 'c_look', label = 'What did they look like?' },
}
-- anyone found out in the area
local FOUND_Q = {
    { id = 'c_where', label = 'Where were you ten minutes ago?', stress = true },
    { id = 'c_store', label = 'Were you in the store just now?', stress = true, press = true },
    { id = 'c_proof', label = 'Can anyone back that up?', needs = { c_alibi = true } },
}

local LOOK = 'a_m_y_skater_01' -- (the man out in the area looks the same in every story: no telling which it is)

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
    c:objective('clerk', 'Talk to the clerk', { hint = 'They made the call.', blip = 'clerk' })
    c:objective('witness', 'Talk to the witness', { hint = 'Outside, in front of the store.', blip = 'witness' })
    c:objective('cctv', 'Check the CCTV', { hint = 'Behind the counter.', blip = 'cctv' })
    c:objective('search', 'Search the area they went', { hidden = true, blip = 'dropped',
        hint = 'Something was dropped on the way. Whoever you find out there: check before you cuff them.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'clerk' }, who = 'all', blip = 'suspect' })
end

-- Done when: the clerk's said what happened, the witness what they saw, the CCTV's been looked at. Which way they
-- went (from anyone, or the CCTV) opens the search; talking to either man out there completes it.
local function wire(c)
    c:on('act', function(who, action, arg)
        if action ~= 'ask' then return end
        if who == 'clerk' and arg == 'c_what' then c:done('clerk') end
        if who == 'witness' and arg == 'c_saw' then c:done('witness') end
    end)
    c:on('fact', function(_, fact) if fact == 'c_way' then c:reveal('search') end end)
    c:on('inspect', function(clue)
        if clue == 'cctv' then c:done('cctv') c:reveal('search') end
        if clue == 'dropped' then c:reveal('search') end
    end)
    c:on('contact', function(who) if who == 'suspect' then c:reveal('search') c:done('search') end end)
end

--[[ It's over when everyone arrested has been taken in (cuffed: the card says to book them or call transport), or the
     one it's about (culprit) has been let go or got away with nobody left to take in, or the clerk's been heard and
     every unit has left the store and the area with nobody mid-conversation. ends(out) -> the MDT summary (anyone else
     arrested is added to it); out = { [person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled', left = true }. ]]
local function resolve(c, culprit, ends)
    local out, taken, away_for, done = {}, {}, 0, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function let_go(v) return v == 'released' or v == 'cited' or v == 'warning' or v == 'fled' end
    local function check()
        if done or waiting() then return end
        if not (next(taken) or (culprit and let_go(out[culprit])) or out.left) then return end
        done = true
        c:done('decide')
        local text, also, more = ends(out), {}, {}
        for k, v in pairs(out) do
            if not text:find(c:name(k), 1, true) then
                if v == 'arrested' then also[#also + 1] = c:name(k)
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
            c:done('decide')
        elseif action == 'uncuff' and out[who] == 'arrested' then
            out[who] = nil
            c:hide('custody:' .. who)
        elseif (action == 'cite' or action == 'warn') and out[who] ~= 'arrested' then -- (a ticket or a warning: that's them dealt with)
            out[who] = action == 'cite' and 'cited' or 'warning'
        end
        check()
    end)
    c:on('custody', function(who) taken[who] = true check() end)
    c:on('gone', function(who) if out[who] == 'arrested' then taken[who] = true check() end end)
    c:on('contact_ended', function(who, outcome)
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        check() -- (walked off from them, 'cancelled': nothing decided)
    end)
    c:on('tick', function()
        local here = c:near(nil, 80.0) or c:near('suspect', 80.0) or c:talking()
        if c:is_done('clerk') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then out.left = true check() end
        else
            away_for = 0
        end
    end)
end

-- A man in the area who's nothing to do with it: dressed like the description, with his phone as his alibi.
local function bystander(c, key, at)
    c:person(key, { at = at, label = 'Man', male = true, model = LOOK, age = { 19, 28 }, secret = 'clean', demeanor = 'polite',
        scene = 'WORLD_HUMAN_STAND_MOBILE', questions = FOUND_Q, items = {},
        pockets = { 'Phone: a call to "Mel", 34 minutes, still connected' }, lines = {
            c_where = { { "Right here. I've been on the phone to my girlfriend the whole time. Half an hour, at least.", set = { c_alibi = 'phone' } } },
            c_store = { "The store? No. Look, she's still on the line. Thirty-four minutes. Ask her." },
            c_proof = { "Her. Mel. She's on the phone right now, here, talk to her. She'll tell you she hasn't let me get a word in." },
            where = { "Nowhere. Just standing here on the phone." },
        } })
end

local function clerk_lines(lines)
    lines.where = lines.where or { "Here. Behind this counter. All night." }
    return lines
end

Callout({
    id = 'robbery',
    name = 'Store robbery',
    priority = 1,
    weight = 1,
    reports = {
        'Clerk reports the store has just been robbed. Suspect fled on foot.',
        'Robbery at a convenience store. Caller says the suspect ran off.',
        'Store clerk reports a robbery in the last few minutes. Suspect left on foot.',
    },
    -- The points each location needs, in the order /c3rplace robbery walks you through them. The first is where the
    -- call is (units are on scene within Config.Callouts.arrive m of it).
    points = {
        { 'clerk', 'The clerk, behind the counter.' },
        { 'cctv', 'The CCTV screen behind the counter: what the officer looks at.' },
        { 'witness', 'A witness outside, on the pavement in front of the store.' },
        { 'dropped', 'Something dropped on the way: on the ground between the store and where they hide.' },
        { 'suspect', 'Where the one they are after hides: an alley or behind a building, a street or two away.' },
    },
    -- Add more with /c3rplace robbery in game (it writes them here). This one is a rough placeholder.
    locations = {
        { street = 'Davis Ave', at = vector3(-47.16, -1758.51, 29.42), points = {
            clerk = vector4(-47.16, -1758.51, 29.42, 82.3),
            cctv = vector4(-45.32, -1756.81, 29.42, 203.1),
            witness = vector4(-52.11, -1760.34, 29.14, 93.8),
            dropped = vector4(-56.07, -1764.09, 28.92, 200.8),
            suspect = vector4(-33.26, -1760.93, 29.38, 283.8),
            lookalike = vector4(-12.48, -1777.20, 28.66, 263.5),
        } },
        { street = 'Clinton Ave', at = vector3(373.00, 328.24, 103.57), points = {
            clerk = vector4(373.00, 328.24, 103.57, 238.5),
            cctv = vector4(372.36, 325.90, 103.57, 170.9),
            witness = vector4(372.69, 323.39, 103.51, 173.8),
            dropped = vector4(367.79, 325.13, 103.62, 59.9),
            suspect = vector4(375.00, 352.64, 102.75, 16.7),
        } },
        { street = 'West Mirror Drive', at = vector3(1164.85, -323.25, 69.21), points = {
            clerk = vector4(1164.85, -323.25, 69.21, 122.0),
            cctv = vector4(1164.78, -321.26, 69.21, 359.7),
            witness = vector4(1157.64, -327.44, 69.22, 191.1),
            dropped = vector4(1150.63, -328.56, 69.01, 4.9),
            suspect = vector4(1133.71, -315.60, 67.09, 216.0),
        } },
        { street = 'Palomino Ave', at = vector3(-706.07, -914.66, 19.20), points = {
            clerk = vector4(-706.07, -914.66, 19.20, 105.4),
            cctv = vector4(-705.94, -912.00, 19.22, 2.0),
            witness = vector4(-709.33, -917.77, 19.21, 153.9),
            dropped = vector4(-724.69, -914.37, 19.02, 76.5),
            suspect = vector4(-716.97, -896.46, 20.50, 37.6),
        } },
        { street = 'Route 68', at = vector3(1166.71, 2710.85, 38.16), points = {
            clerk = vector4(1166.71, 2710.85, 38.16, 231.2),
            cctv = vector4(1164.02, 2710.87, 38.16, 130.5),
            witness = vector4(1163.76, 2701.92, 38.18, 157.0),
            dropped = vector4(1158.05, 2702.15, 38.19, 60.0),
            suspect = vector4(1169.92, 2730.32, 38.00, 241.5),
        } },
        { street = 'Algonquin Blvd', at = vector3(1391.56, 3606.00, 34.98), points = {
            clerk = vector4(1391.56, 3606.00, 34.98, 236.9),
            cctv = vector4(1391.36, 3609.34, 35.03, 3.4),
            witness = vector4(1392.36, 3597.45, 35.04, 209.6),
            dropped = vector4(1385.67, 3601.34, 34.90, 52.1),
            suspect = vector4(1355.17, 3614.37, 34.87, 65.8),
        } },
        { street = 'Grapeseed Main St', at = vector3(1697.35, 4923.34, 42.06), points = {
            clerk = vector4(1697.35, 4923.34, 42.06, 311.0),
            cctv = vector4(1699.25, 4921.68, 42.06, 231.3),
            witness = vector4(1700.36, 4933.74, 42.08, 83.2),
            dropped = vector4(1712.23, 4940.87, 42.08, 224.4),
            suspect = vector4(1709.72, 4921.22, 42.08, 255.6),
        } },
        { street = 'Paleto Blvd', at = vector3(6.01, 6511.58, 31.88), points = {
            clerk = vector4(6.01, 6511.58, 31.88, 97.7),
            cctv = vector4(4.85, 6509.78, 31.88, 253.8),
            witness = vector4(-0.10, 6519.90, 31.48, 31.8),
            dropped = vector4(7.17, 6526.88, 31.43, 315.9),
            suspect = vector4(13.48, 6498.11, 31.49, 215.1),
        } },
    },

    stories = {
        -- ── He robbed it, with a knife. He's hiding nearby with the cash. ──────────────────────────────────────
        robbery = {
            weight = 3,
            setup = function(c)
                c:person('clerk', { at = 'clerk', label = 'Clerk', male = true, model = 'mp_m_shopkeep_01', secret = 'clean',
                    demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = CLERK_Q, lines = clerk_lines({
                        c_what = { "He came in, waited till it was empty, then pulled a knife on me. Told me to empty the till. I did. I'm not dying for minimum wage." },
                        c_amount = { 'Everything in the till. Three hundred and forty, about. Still in the bank bands.' },
                        c_weapon = { 'A knife. Folding one, black handle. He held it right up by my face.' },
                        c_way = { { 'Out the door and off that way. Running.', set = { c_way = 'pointed' } } },
                        c_look = { 'Young. Skinny. Hood up, and a bandana over his face. All I saw were his eyes.' },
                    }) })
                c:person('witness', { at = 'witness', label = 'Witness', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = WITNESS_Q, lines = {
                    c_saw = { "A guy came flying out of the store with his hood up, pulling a bandana off his face. Nearly knocked me over." },
                    c_way = { { "That way. Round the back of the buildings.", set = { c_way = 'pointed' } } },
                    c_look = { "Young guy, skinny. Something shiny in his hand, I think. I didn't hang about to look." },
                } })
                c:person('suspect', { at = 'suspect', label = 'Man', male = true, model = LOOK, age = { 19, 28 },
                    secret = math.random() < .5 and 'warrant' or 'drugs', demeanor = 'nervous', scene = 'WORLD_HUMAN_SMOKING',
                    questions = FOUND_Q, items = { '$340 in cash, still in bank bands', 'Folding knife, black handle' }, lines = {
                        c_where = { { "Around. Just walking. Is that illegal?", set = { c_alibi = 'none' } },
                                    { "Here. I've been here all night.", set = { c_alibi = 'here' } } },
                        c_store = cracks(3, { "What store? I don't even go in there.", "No. Why would I be in a store?" },
                            { { "...Alright. Alright. I needed the money. Nobody got hurt.", set = { c_admit = 'yes' } } },
                            { "I told you. I needed the money. I'm not saying it again." }),
                        c_proof = { "Back it up? No. I was on my own." },
                        where = { "Nowhere. Just hanging around." },
                    } })
                c:clue('cctv', { at = 'cctv', label = 'CCTV',
                    text = 'A few minutes before the call: a young man, hood up and a bandana over his face, waits for the store to empty, pulls a knife on the clerk and takes the till. He runs out, stuffing the cash in his pocket.' })
                c:clue('dropped', { at = 'dropped', label = 'Something dropped', prop = 'prop_cs_bandana',
                    text = 'A dark bandana on the ground, dropped in a hurry. Like the one in the description.' })
                card(c)
                wire(c)
                resolve(c, 'suspect', function(out)
                    local s = c:name('suspect')
                    if out.suspect == 'arrested' then
                        local on = {}
                        if c:who('suspect').facts.found then on[#on + 1] = 'the cash and the knife' end
                        if c:who('suspect').facts.c_admit then on[#on + 1] = 'his admission' end
                        if c:is_done('cctv') then on[#on + 1] = 'the CCTV' end
                        return ('Armed robbery: %s arrested.'):format(s) .. (on[1] and (' Recorded: ' .. table.concat(on, ', ') .. '.') or '')
                    elseif out.suspect == 'fled' then
                        return ('The robbery suspect, %s, ran and got away.'):format(s)
                    elseif out.suspect == 'cited' or out.suspect == 'warning' then
                        return ('%s, the robber, was given a %s and let go.'):format(s, out.suspect == 'cited' and 'ticket' or 'warning')
                    elseif out.suspect then
                        return ('%s, the robber, was spoken to and let go.'):format(s)
                    end
                    return c:is_done('search') and 'Robbery: nobody arrested.' or 'Robbery: nobody arrested. The area was not searched.'
                end)
            end,
        },

        -- ── The clerk staged it. ───────────────────────────────────────────────────────────────────────────────
        inside = {
            weight = 2,
            setup = function(c)
                local DENY = { "It does that. It's old. The owner never fixes anything.", "I don't know! Maybe it's on a timer." }
                c:person('clerk', { at = 'clerk', label = 'Clerk', male = true, model = 'mp_m_shopkeep_01', secret = 'nervous',
                    demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = CLERK_Q,
                    items = { 'Envelope with $410 inside his jacket, till bands still on it' }, lines = clerk_lines({
                        c_what = { "A guy came in with a knife and took the till. It was so fast. I didn't even get a good look at him." },
                        c_amount = { 'Four hundred and ten. Exactly. I mean, about. I count it every night.' },
                        c_weapon = { 'A knife. Or a gun? A knife. It happened so fast.' },
                        c_way = { { 'That way. Running. You should hurry.', set = { c_way = 'pointed' } } },
                        c_look = { "I don't know. Hood. Tall? Average. It was so fast." },
                        c_camera = cracks(3, DENY,
                            { { "...Okay. I owe some people money. I thought nobody would know. It's in my jacket. I'm sorry.", set = { c_admit = 'yes' } } },
                            { "I've told you. I owe people money. It's in my jacket." }),
                    }) })
                c:person('witness', { at = 'witness', label = 'Witness', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = WITNESS_Q, lines = {
                    c_saw = { "Nothing. That's the thing. I've been out here twenty minutes and nobody's come out of that store. Nobody's gone in, either." },
                    c_way = { { "Nobody went anywhere. The clerk came out, looked up and down the street, and went back in. Then you lot turned up.", set = { c_nobody = 'yes' } } },
                    c_look = { "Who? There wasn't anyone." },
                } })
                bystander(c, 'suspect', 'suspect') -- (someone out there all the same: nothing to do with it)
                c:clue('cctv', { at = 'cctv', label = 'CCTV',
                    text = 'The recording stops for nineteen minutes, just before the call. The last thing on it: the clerk, reaching up under the counter towards the recorder.' })
                c:clue('dropped', { at = 'dropped', label = 'Something dropped', prop = 'ng_proc_sodacan_01a',
                    text = 'An empty soda can, flattened, been there a while. Litter.' })
                card(c)
                wire(c)
                c:on('inspect', function(clue)
                    if clue == 'cctv' then
                        c:who('clerk').facts.c_gap = true -- (now there's something to ask him)
                        c:questions('clerk')
                    end
                end)
                resolve(c, 'clerk', function(out)
                    local k = c:name('clerk')
                    if out.clerk == 'arrested' then
                        local on = {}
                        if c:is_done('cctv') then on[#on + 1] = 'the gap in the CCTV' end
                        if c:who('clerk').facts.found then on[#on + 1] = 'the till money in his jacket' end
                        if c:who('clerk').facts.c_admit then on[#on + 1] = 'his admission' end
                        if c:who('witness').facts.c_nobody then on[#on + 1] = 'the witness: nobody came out' end
                        return ('Staged robbery: the clerk, %s, arrested.'):format(k) .. (on[1] and (' Recorded: ' .. table.concat(on, ', ') .. '.') or '')
                    elseif out.clerk == 'cited' or out.clerk == 'warning' or out.clerk == 'released' then
                        return ('Staged robbery: the clerk, %s, %s.'):format(k,
                            out.clerk == 'cited' and 'given a ticket' or out.clerk == 'warning' and 'given a warning' or 'let go')
                    end
                    return ('No arrest. The robbery reported by %s was never confirmed.'):format(k)
                end)
            end,
        },

        -- ── A teenager walked out with beer and chips. ────────────────────────────────────────────────────────
        shoplift = {
            weight = 2,
            setup = function(c)
                c:person('clerk', { at = 'clerk', label = 'Clerk', male = true, model = 'mp_m_shopkeep_01', secret = 'clean',
                    demeanor = 'rude', scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = CLERK_Q, lines = clerk_lines({
                        c_what = { "Little punk walked out with my stock. Third time this month. I want him locked up." },
                        c_amount = { "Two beers and a bag of chips. That's not the point! It's the principle." },
                        c_weapon = { "A weapon? No. He just walked out. Laughing at me." },
                        c_way = { { 'That way, the little punk.', set = { c_way = 'pointed' } } },
                        c_look = { "A kid. Eighteen, nineteen. Hood up like they all do." },
                    }) })
                c:person('witness', { at = 'witness', label = 'Witness', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = WITNESS_Q, lines = {
                    c_saw = { "Some kid ran out laughing with a couple of cans under his jacket. The clerk was screaming 'robbery'. Robbery! It was two beers." },
                    c_way = { { 'That way. He dropped one of the cans as he went.', set = { c_way = 'pointed' } } },
                    c_look = { 'A teenager. Skinny. Hood up.' },
                } })
                c:person('suspect', { at = 'suspect', label = 'Man', male = true, model = LOOK, age = { 18, 19 }, secret = 'clean',
                    demeanor = 'nervous', scene = 'WORLD_HUMAN_SMOKING', questions = FOUND_Q,
                    items = { 'A can of beer, still cold', 'Bag of chips, unpaid' }, lines = {
                        c_where = { { "Just here. Chilling.", set = { c_alibi = 'none' } } },
                        c_store = cracks(2, { "...Maybe. Why?" },
                            { { "Okay, yeah. It was two beers. I dropped one. I was gonna pay him back, I swear. Don't tell my mom.", set = { c_admit = 'yes' } } },
                            { "I said, it was two beers. I'm sorry, alright?" }),
                        c_proof = { 'No. I was on my own.' },
                        age = { "Nineteen." },
                        where = { "Home. In a bit." },
                    } })
                c:clue('cctv', { at = 'cctv', label = 'CCTV',
                    text = 'A few minutes before the call: a teenager stuffs two cans of beer and a bag of chips into his jacket and walks out. No weapon, no threat. The clerk shouts after him.' })
                c:clue('dropped', { at = 'dropped', label = 'Something dropped', prop = 'prop_ld_can_01',
                    text = 'A can of beer on the ground, still cold, the store price sticker on it.' })
                card(c)
                wire(c)
                resolve(c, 'suspect', function(out)
                    local s = c:name('suspect')
                    if out.suspect == 'arrested' then
                        return ('Shoplifting (two beers and chips): %s arrested.'):format(s)
                            .. (c:who('suspect').facts.found and ' Goods recovered.' or '')
                    elseif out.suspect == 'cited' then
                        return ('Shoplifting: %s given a ticket.'):format(s)
                    elseif out.suspect == 'warning' then
                        return ('Shoplifting: %s given a warning and let go.'):format(s)
                    elseif out.suspect == 'released' then
                        return ('Shoplifting: %s let go.'):format(s)
                    elseif out.suspect == 'fled' then
                        return ('The shoplifter, %s, ran off.'):format(s)
                    end
                    return 'Shoplifting: nobody found.'
                end)
            end,
        },
    },
})
