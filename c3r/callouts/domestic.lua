--[[
    c3r callout: DOMESTIC DISTURBANCE.

    A neighbour hears it go wrong next door. What really happened is one of four stories, and the card, the people
    on scene and the questions are the same for all of them: talk to the caller (the neighbour), the couple (each on
    their own), look around the yard, then decide. Only what they say, and what you find, is different.
      assault    he hit her; she covers for him, and only tells the truth when he can't hear (10 m, or him in cuffs)
      argument   a loud row about money; nobody touched anybody, and the neighbour calls every week
      left       he drove off drunk before you got there; she knows where he's gone and in what
      caller     she rang it in herself, drunk, and she's the one who went for him; the lamp she says he threw at her
                 is out on the porch, where she threw it at him
    It's dealt with when whoever's arrested is taken in (the card says so once they're cuffed: book them at a station
    or call prisoner transport), both are let go, or both have been spoken to and every unit has left.

    Points per location (rough placeholders below: stand on each in game and /c3rpos <name> to replace them):
      neighbour      where the neighbour who called it in waits (on their own lawn, on the phone)
      woman          her, at the front door
      man            him, in the yard: well within 10 m of her, so he can hear what she says until you separate them
      evidence       what's out in the yard (a smashed phone, a broken plate, tyre marks or a lamp, by story)
      man_drove_to   where he is in the "left" story, having driven off: within ~150 m of the house
      man_car        his car, parked there (sit in a car where it should be and /c3rpos man_car)
]]

-- ─── the same in every story: questions, card, how it's dealt with ───────────────────────────────────────────────
local NEIGHBOUR_Q = {
    { id = 'c_heard', label = 'What did you hear?' },
    { id = 'c_who', label = 'Who lives there?' },
    { id = 'c_before', label = 'Has anything like this happened before?' },
    { id = 'c_saw', label = 'Did you see anyone hurt, or leave?' },
}
local HIM_Q = {
    { id = 'c_night', label = 'What happened here tonight?', stress = true },
    { id = 'c_hands', label = 'What happened to your hands?', stress = true },
    { id = 'c_partner', label = 'Is your partner okay?' },
    { id = 'c_smash', label = 'Your neighbour heard something break.', stress = true, press = true },
    { id = 'c_drove', label = 'How did you get here?', needs = { c_away = true }, stress = true, press = true },
}
local HER_Q = {
    { id = 'c_night', label = 'What happened here tonight?', stress = true },
    { id = 'c_hurt', label = 'Are you hurt at all?' },
    { id = 'c_mark', label = 'How did you get that mark on your cheek?', needs = { c_mark = true }, stress = true },
    { id = 'c_safe', label = 'Do you feel safe here tonight?', stress = true, press = true },
    { id = 'c_who_hit', label = 'Did he do this to you?', needs = { c_disclosed = true }, stress = true },
    { id = 'c_where_he', label = 'Where is he now?' },
    { id = 'c_car', label = 'What is he driving?', needs = { c_left = true } },
}

-- Living there: the usual "where are you headed / do you live here / your address" answered as someone at home.
local function at_home(c, lines)
    lines.where = lines.where or { "Nowhere. I live here.", "I'm not going anywhere. This is my house." }
    lines.live = lines.live or { 'Right here. This is our house.' }
    lines.address = lines.address or function() return { ('This house. On %s.'):format(c:street()) } end
    return lines
end

local function card(c, opts)
    opts = opts or {}
    c:objective('caller', 'Talk to the caller', { hint = 'They called it in from next door.', blip = 'neighbour' })
    c:objective('house', 'Make contact at the house', { hint = 'Front door.', blip = 'woman' })
    c:objective('yard', 'Look around the yard', { hint = 'Anything thrown, broken or left behind.', blip = 'yard' })
    c:objective('talk_man', 'Talk to him', { after = { 'house' }, blip = not opts.away and 'man' or nil,
        hint = 'Keep him away from her while you do.' })
    c:objective('talk_woman', 'Talk to her on her own', { after = { 'house' }, blip = 'woman',
        hint = 'Out of his earshot: more than 10 m apart, or with him in cuffs.' })
    c:objective('decide', 'Decide: arrest, or release them both', { after = { 'talk_man', 'talk_woman' }, who = 'all', blip = { 'man', 'woman' } })
end

-- What marks each objective done: asking the caller what they heard, him what happened, her whether she's safe while
-- he can't hear it; contact at the door; looking at the yard.
local function wire(c)
    c:on('act', function(who, action, arg)
        if action ~= 'ask' then return end
        if who == 'neighbour' and arg == 'c_heard' then c:done('caller') end
        if who == 'man' and (arg == 'c_night' or arg == 'c_drove') then c:done('talk_man') end
        if who == 'woman' and arg == 'c_safe' and c:apart('man', 'woman') then c:done('talk_woman') end
    end)
    c:on('contact', function(who) if who == 'woman' then c:done('house') end end)
    c:on('inspect', function(clue) if clue == 'yard' then c:done('yard') end end)
end

--[[ It's over when: whoever's arrested is taken in (booked at a station, or by prisoner transport); both have been let
     go; he ran and got away; or, with nobody arrested, both have been spoken to and every unit has left.
     ends(out) -> the MDT summary, out = { man, woman = 'arrested' | 'released' | 'fled' | 'gone', left = true }. ]]
local function resolve(c, ends)
    local out, gone, away_for, done = {}, {}, 0, false
    local function over()
        if done then return end
        done = true
        c:done('decide')
        c:finish(ends(out))
    end
    local function arrest() return out.man == 'arrested' or out.woman == 'arrested' end
    local function check()
        if arrest() then return end -- (ends once they're taken in: 'custody')
        if (out.man and out.woman) or out.man == 'fled' or out.left or gone.man or gone.woman then
            if gone.man then out.man = out.man or 'gone' end
            if gone.woman then out.woman = out.woman or 'gone' end
            over()
        end
    end
    -- cuffed: under arrest, and the card says to take them in; uncuffed: not any more
    c:on('act', function(who, action)
        if who == 'man' or who == 'woman' then
            if action == 'cuff' and c:who(who).cuffed then
                out[who] = 'arrested'
                c:custody(who)
                c:done('decide')
            elseif action == 'uncuff' then
                out[who] = nil
                c:hide('custody:' .. who)
            end
        end
        check()
    end)
    c:on('custody', function() over() end)
    c:on('contact_ended', function(who, outcome)
        if who ~= 'man' and who ~= 'woman' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = 'released' end
        check() -- (walked off from them, 'cancelled': nothing decided)
    end)
    c:on('gone', function(who)
        if who ~= 'man' and who ~= 'woman' then return end
        if out[who] == 'arrested' then return over() end -- (taken away some other way: still taken in)
        gone[who] = true
        check()
    end)
    c:on('tick', function()
        if not arrest() and c:is_done('talk_man') and c:is_done('talk_woman') and not c:near(nil, 80.0) then
            away_for = away_for + 1
            if away_for >= 15 then out.left = true check() end
        else
            away_for = 0
        end
    end)
end

-- Heard from the street as the first unit gets close.
local function shouting(c, lines)
    local said = false
    c:on('tick', function()
        if said or not c:near(lines[1][1], 30.0) then return end
        said = true
        for _, l in ipairs(lines) do c:say(l[1], l[2]) end
    end)
end

local function house(street, at, p) return { street = street, at = at, points = p } end

Callout({
    id = 'domestic',
    name = 'Domestic disturbance',
    priority = 2,
    weight = 1,
    reports = {
        'Caller reports screaming next door, then something smashing.',
        'Neighbour reports a man and a woman shouting, and a loud bang.',
        'Caller can hear a woman crying and a door slamming at the house next door.',
        'Shouting and banging at a residence. Caller is concerned for the woman who lives there.',
    },
    -- Rough placeholders: replace every point with /c3rpos in game.
    locations = {
        house('Paleto Bay', vector3(-128.49, 6549.86, 28.51), {
            neighbour = vector4(-129.26, 6550.46, 29.52, 241.0), woman = vector4(-105.16, 6529.10, 30.17, 30.2),
            man = vector4(-111.54, 6533.10, 29.81, 357.8), evidence = vector4(-98.27, 6540.20, 29.81, 135.1),
            man_drove_to = vector4(-85.11, 6601.18, 29.47, 46.4), man_car = vector4(-73.23, 6603.38, 29.03, 97.9), }),
    },

    stories = {
        -- ── He hit her. She covers for him. ─────────────────────────────────────────────────────────────────────
        assault = {
            weight = 3,
            setup = function(c)
                c:person('neighbour', { at = 'neighbour', label = 'Neighbour', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = NEIGHBOUR_Q,
                    lines = {
                        c_heard = { { "Shouting, then a bang like something hitting the wall. Then a slap. I'm sure it was a slap. And she was crying.",
                                      set = { c_heard = 'slap' } } },
                        c_who = { "A couple. Moved in last year. He's got a temper on him when he drinks." },
                        c_before = { "Twice that I know of. She wore sunglasses for a week after the last time. In December." },
                        c_saw = { "He threw something out into the yard. I didn't see her come out until you pulled up." },
                    } })
                c:person('man', { at = 'man', label = 'Man', male = true, home = true, family = true,
                    secret = math.random() < .6 and 'drunk' or 'warrant', demeanor = 'rude', scene = 'WORLD_HUMAN_STAND_IMPATIENT',
                    questions = HIM_Q, lines = at_home(c, {
                        c_night = { "Nothing happened. We had words. That's it.", "Nothing. Who called you? It was next door, wasn't it?" },
                        c_hands = { { "Punched a wall. My wall. My business.", set = { c_hands = 'wall' } } },
                        c_partner = { "She's fine. Ask her. She'll tell you." },
                        c_smash = { "I dropped my phone, alright? It's a phone.", "It was my phone. Out the door. Clumsy." },
                    }) })
                local COVER = { "Yes. Everything's fine. Can you just... go?", "I'm fine. Please. He'll hear you." }
                local TRUTH = { { "...No. He hit me. He threw my phone outside so I couldn't call anyone. Please don't tell him I said.",
                                  set = { c_disclosed = 'yes' } } }
                local TOLD = { "I've told you. Please. Just... do something this time." }
                c:person('woman', { at = 'woman', label = 'Woman', male = false, home = true, family = true, secret = 'clean',
                    demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = HER_Q, lines = at_home(c, {
                        c_night = { "We were just... talking loud. It's nothing. I'm sorry they called you." },
                        c_hurt = { "No. No, I'm fine." },
                        c_mark = { { "I walked into the cupboard door. I'm so clumsy.", set = { c_story = 'fell' } } },
                        c_safe = function(o) -- whether he can hear it
                            if o.facts.c_disclosed then return TOLD end
                            return c:apart('man', 'woman') and TRUTH or COVER
                        end,
                        c_who_hit = { "...Yes. It's not the first time. Please. I can't do this again." },
                        c_where_he = { "Right there. He's not going anywhere." },
                    }) })
                c:clue('yard', { at = 'evidence', label = 'The yard', prop = 'prop_npc_phone_02',
                    text = 'A phone in the grass, screen shattered: thrown hard. The lock screen is a photo of her.' })
                card(c)
                wire(c)
                -- what the first officer to face her sees
                c:on('contact', function(who, src)
                    local her = c:who('woman')
                    if who ~= 'woman' or her.facts.c_mark then return end
                    her.facts.c_mark = true
                    c:tell(src, 'You notice', 'A fresh red mark on her cheek. She keeps that side of her face turned away.')
                    c:note(('Visible injury: fresh mark on %s\'s cheek'):format(c:name('woman')))
                end)
                shouting(c, { { 'man', 'Get back inside! Now!' }, { 'woman', 'Stop it! Just stop!' } })
                resolve(c, function(out)
                    local a, b = c:name('man'), c:name('woman')
                    if out.man == 'arrested' then
                        local on = {}
                        if c:who('woman').facts.c_disclosed then on[#on + 1] = 'her statement' end
                        if c:who('woman').facts.c_mark then on[#on + 1] = 'her injury' end
                        if c:is_done('yard') then on[#on + 1] = 'the phone thrown into the yard' end
                        return ('Domestic assault: %s arrested.'):format(a)
                            .. (on[1] and (' Recorded: ' .. table.concat(on, ', ') .. '.') or ' Nothing recorded against him.')
                    elseif out.man == 'fled' then
                        return ('%s ran from the scene. %s had a fresh injury.'):format(a, b)
                    elseif out.woman == 'arrested' then
                        return ('Arrested %s, who had been assaulted. %s was left at the home.'):format(b, a)
                    end
                    return ('No arrest. %s had a fresh injury; %s stays in the home with her.'):format(b, a)
                end)
            end,
        },

        -- ── A row about money. Loud, not violent. ───────────────────────────────────────────────────────────────
        argument = {
            weight = 3,
            setup = function(c)
                c:person('neighbour', { at = 'neighbour', label = 'Neighbour', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = NEIGHBOUR_Q,
                    lines = {
                        c_heard = { { 'Screaming at each other. Then a smash. Glass, or a plate or something.', set = { c_heard = 'shouting' } } },
                        c_who = { "The couple next door. They're always at it." },
                        c_before = { { "Every week. I've called three times this month. Somebody has to do something.", set = { c_regular = 'yes' } } },
                        c_saw = { "No. I heard it through the wall. I wasn't going to go round there." },
                    } })
                c:person('man', { at = 'man', label = 'Man', male = true, home = true, family = true, secret = 'clean', demeanor = 'rude',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = HIM_Q, lines = at_home(c, {
                        c_night = { "We had a row. About money, if you must know. Nobody touched anybody." },
                        c_hands = { "My hands? They're fine. Look." },
                        c_partner = { "She's fine. She's the one who threw the plate." },
                        c_smash = { "That was a plate. She threw it at the wall. Not at me. At the wall." },
                    }) })
                c:person('woman', { at = 'woman', label = 'Woman', male = false, home = true, family = true, secret = 'clean', demeanor = 'rude',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = HER_Q, lines = at_home(c, {
                        c_night = { "We argued. About his mother, about money, about everything. Loudly. That's not a crime." },
                        c_hurt = { 'Hurt? No. Annoyed. Very annoyed.' },
                        c_safe = { "Safe? From him? He wouldn't hurt a fly. He just won't stop going on about money.",
                                   "Yes. I'm embarrassed, that's what I am." },
                        c_where_he = { 'In the yard, sulking.' },
                    }) })
                c:clue('yard', { at = 'evidence', label = 'The yard', prop = 'prop_plate_01',
                    text = 'A dinner plate face down by the step, a chunk snapped out of the rim. Thrown, by where it landed: at the wall, not at anyone.' })
                card(c)
                wire(c)
                shouting(c, { { 'woman', 'Your mother, always your mother!' }, { 'man', 'Do NOT start on my mother!' } })
                resolve(c, function(out)
                    local who = out.man == 'arrested' and c:name('man') or out.woman == 'arrested' and c:name('woman')
                    if who then return ('Arrested %s after a verbal argument. No injuries or offence recorded.'):format(who) end
                    return 'Verbal argument, no offence. Both parties advised.'
                        .. (c:who('neighbour').facts.c_regular and ' The neighbour has called about them before.' or '')
                end)
            end,
        },

        -- ── He drove off drunk before you got there. ────────────────────────────────────────────────────────────
        left = {
            weight = 2,
            setup = function(c)
                c:person('neighbour', { at = 'neighbour', label = 'Neighbour', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = NEIGHBOUR_Q,
                    lines = {
                        c_heard = { { 'Shouting, a door slamming, then his car screeching off. Then quiet.', set = { c_heard = 'drove' } } },
                        c_who = { 'A couple. He drinks. A lot, lately.' },
                        c_before = { 'Shouting, yes. Never this bad.' },
                        c_saw = { "He drove off. Fast. He could barely walk to the car. She's okay, I think. She came out after." },
                    } })
                c:person('woman', { at = 'woman', label = 'Woman', male = false, home = true, family = true, secret = 'clean', demeanor = 'nervous',
                    scene = 'WORLD_HUMAN_STAND_MOBILE', questions = HER_Q, lines = at_home(c, {
                        c_night = { { "He'd been drinking all day. We fought, he grabbed his keys and drove off. I tried to stop him.",
                                      set = { c_left = 'yes' } } },
                        c_hurt = { "No. He pushed past me, that's all." },
                        c_safe = { "Now he's gone, yes. I'm scared for whoever's on the road with him." },
                        c_where_he = { { "His brother's, round the corner. He always goes there when we fight.", set = { c_left = 'yes', c_where = 'brother' } } },
                        c_car = { { "A silver Asea. His. He shouldn't be driving. He's had most of a bottle.", set = { c_car = 'told' } } },
                    }) })
                c:person('man', { at = 'man_drove_to', label = 'Man', male = true, home = true, family = true, secret = 'drunk', demeanor = 'rude',
                    scene = 'WORLD_HUMAN_SMOKING', questions = HIM_Q, facts = { c_away = true }, lines = {
                        c_night = { "Nothing. I went for a drive. That illegal now?" },
                        c_hands = { 'What about them?' },
                        c_partner = { "She called you? Course she did." },
                        c_smash = { "Nothing broke. I slammed a door. People slam doors." },
                        c_drove = { "Walked.", { "...Drove. It's two minutes. I'm fine.", set = { c_admit = 'yes' } },
                                    { 'I drove. Alright? I drove.', set = { c_admit = 'yes' } } },
                        where = { "Home. Eventually. When she's calmed down." },
                    } })
                c:vehicle('car', { at = 'man_car', model = 'asea', make = 'Declasse', name = 'Asea', color = 'Silver', paint = 4,
                    label = 'His car', owner = 'man', locked = false })
                c:clue('yard', { at = 'evidence', label = 'The yard', -- (no prop: marks on the ground)
                    text = 'Black tyre marks over the kerb and a garden light snapped off: a car pulled away fast and clipped it.' })
                c:clue('car', { on = 'car', label = 'His car', hidden = true,
                    text = 'Bonnet still warm. Keys in the ignition, an empty vodka bottle in the footwell.' })
                card(c, { away = true })
                wire(c)
                local found = false
                c:on('contact', function(who) if who == 'man' then found = true end end)
                c:on('fact', function(who, fact)
                    if who ~= 'woman' then return end
                    if fact == 'c_where' or fact == 'c_car' then c:blip('talk_man', { 'man', 'car' }) end -- (now you know where)
                    if fact == 'c_car' then
                        c:reveal('car')
                        if not found then
                            c:dispatch(('All units, look out for a silver Declasse Asea, plate %s. Driver possibly intoxicated, left %s a few minutes ago.')
                                :format(c:plate('car') or 'unknown', c:street()))
                        end
                    end
                end)
                resolve(c, function(out)
                    local a, b = c:name('man'), c:name('woman')
                    if out.man == 'arrested' then
                        return ('%s found nearby and arrested: drove from a domestic argument while intoxicated.'):format(a)
                            .. (c:who('man').facts.c_admit and ' He admitted driving.' or '')
                    elseif out.man == 'fled' then
                        return ('%s ran when found. He had driven from the address intoxicated.'):format(a)
                    elseif out.woman == 'arrested' then
                        return ('Arrested %s. %s, who had driven off intoxicated, was not dealt with.'):format(b, a)
                    elseif out.left and not found then
                        return ('%s, who drove off intoxicated, was not found.'):format(a)
                    end
                    return ('%s found and released after driving from the address intoxicated.'):format(a)
                end)
            end,
        },

        -- ── She rang it in. She's the one who went for him. ─────────────────────────────────────────────────────
        caller = {
            weight = 2,
            setup = function(c)
                c:person('neighbour', { at = 'neighbour', label = 'Neighbour', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = NEIGHBOUR_Q,
                    lines = {
                        c_heard = { { "Her, mostly. Screaming 'get off me', then 'give me my keys'. She rang you herself, I think: I heard her shouting the address.",
                                      set = { c_heard = 'keys' } } },
                        c_who = { "Nice enough couple. She's been drinking a lot since she lost her job." },
                        c_before = { 'Not like this.' },
                        c_saw = { "He came out into the yard to get away from her, I think. Then something came flying out the door after him." },
                    } })
                c:person('woman', { at = 'woman', label = 'Woman', male = false, home = true, family = true, secret = 'drunk', demeanor = 'polite',
                    scene = 'WORLD_HUMAN_STAND_MOBILE', questions = HER_Q, lines = at_home(c, {
                        c_night = { { "He attacked me! He threw the lamp at my head! I want him arrested! Now!", set = { c_lamp = 'thrown' } } },
                        c_hurt = { "Hurt? He threw a lamp at me! ...It missed. But he threw it!" },
                        c_safe = { 'No! Not with him here! Why are you asking me questions? Arrest HIM!' },
                        c_where_he = { 'Out there. Playing the victim.' },
                    }) })
                c:person('man', { at = 'man', label = 'Man', male = true, home = true, family = true, secret = 'clean', demeanor = 'polite',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', questions = HIM_Q, lines = at_home(c, {
                        c_night = { "She's had a lot to drink. She wanted to drive to her sister's. I took her keys, and she went for me." },
                        c_hands = { { "These? She scratched me when I took the keys. I didn't hit her back. I've never hit her.",
                                      set = { c_scratches = 'yes' } } },
                        c_partner = { "She's not hurt. She's drunk. That's all this is." },
                        c_smash = { "That lamp? She threw it out the door at me. Missed by a mile. It's on the porch. Look at it." },
                    }) })
                c:clue('yard', { at = 'evidence', label = 'The yard', prop = 'v_res_m_lamptbl',
                    text = 'A table lamp lying on the porch step, flex trailing out of the open door. Not a crack or a dent on it.' })
                card(c)
                wire(c)
                shouting(c, { { 'woman', "Give me my keys! They're MY keys!" }, { 'man', "You're not driving like this!" } })
                resolve(c, function(out)
                    local a, b = c:name('man'), c:name('woman')
                    if out.woman == 'arrested' then
                        local on = {}
                        if c:who('man').facts.c_scratches then on[#on + 1] = 'his scratches' end
                        if c:is_done('yard') then on[#on + 1] = 'the lamp thrown out after him, undamaged' end
                        return ('%s arrested for assault on %s.'):format(b, a)
                            .. (on[1] and (' Recorded: ' .. table.concat(on, ', ') .. '.') or '')
                    elseif out.man == 'arrested' then
                        return ('Arrested %s on %s\'s word. She had been drinking and had attacked him.'):format(a, b)
                    end
                    return ('No arrest. %s, intoxicated, stays at the home with %s; her car keys kept from her.'):format(b, a)
                end)
            end,
        },
    },
})
