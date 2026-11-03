--[[
    c3r callout: STING OPERATION.

    Nobody rang 911: a narcotics detective wants a uniform unit standing by while their undercover officer makes a buy.
    The report is the same every time, and the card is too: meet the detective, run the seller's car, cover the back way
    (three units can take one each), then tell the detective you're set. The UC walks in, the deal plays out on the wire,
    and a unit that gets close to the seller before the word blows it. How the deal really goes is one of five stories:
      clean    a straight sale: the go word, and the arrest
      rip      the seller's bags are baking soda and the plan is the money: a gun on the UC, the duress word and a clock
      runner   the seller is a frightened kid; the real dealer is watching from the car, and leaves when it goes wrong
      skim     it looks like clean, but the seller has $1,400 and the UC signed for $2,000
      blue     the seller is a state task force undercover: two agencies have just bought from each other
    It's dealt with when the one it's about has been taken in, let go, or got away, with anyone hurt seen to, or the
    detective's been heard, the deal's over and every unit has left.

    Points per location: walk them out in game with /c3rplace sting (it writes the location in below).
]]

local SPOOK = 18.0   -- (a unit this close to the seller before the word: the deal's blown)
local GO_AFTER = 240 -- (seconds after the briefing: nobody's said they're set, the detective sends the UC in anyway)
local WALK = 120     -- (seconds the UC gets to walk there: stuck on the way, the deal starts regardless)
local WALK_OFF = 90  -- (seconds after the sale: nobody's moved in, the seller walks off)
local AWAY = 250.0   -- (metres: further than this from everyone on the call, a unit has left. The points can be this far apart)

-- Spawn names, makes and names checked against the game's vehicle list; paint ids against docs.fivem.net's colours.
local CARS = {
    { model = 'buccaneer', make = 'Albany', name = 'Buccaneer' },
    { model = 'manana', make = 'Albany', name = 'Manana' },
    { model = 'primo', make = 'Albany', name = 'Primo' },
    { model = 'tornado', make = 'Declasse', name = 'Tornado' },
    { model = 'sultan', make = 'Karin', name = 'Sultan' },
}
local PAINTS = { { 'Black', 0 }, { 'Silver', 4 }, { 'Red', 27 }, { 'Dark blue', 62 }, { 'White', 111 } }

local DETECTIVE_Q = {
    { id = 'c_plan', label = "What's the plan?" },
    { id = 'c_word', label = "What's the go word?", needs = { c_plan = true } },
    { id = 'c_seller', label = 'What do we know about the seller?' },
    { id = 'c_uc', label = 'Who is your undercover?' },
    { id = 'c_send', label = "We're set. Send them in.", needs = { c_plan = true }, press = true },
    { id = 'c_short', label = 'The seller only had $1,400 on them.', needs = { c_short = true } },
    { id = 'c_onuc', label = 'The missing $600 was on your officer.', needs = { c_onuc = true } },
    { id = 'c_flag', label = 'The seller is a state task force officer.', needs = { c_flag = true } },
}
local UC_Q = {
    { id = 'c_ready', label = 'You ready for this?' },
    { id = 'c_cover', label = "What's your cover?" },
    { id = 'c_buy', label = 'What did you get?', needs = { c_sold = true } },
    { id = 'c_money', label = 'Where is the rest of the buy money?', needs = { c_missing = true }, stress = true, press = true },
}
local SELLER_Q = {
    { id = 'c_here', label = 'What are you doing here?', stress = true },
    { id = 'c_sold', label = 'You just sold to an undercover officer.', needs = { c_deal = true }, stress = true, press = true },
    { id = 'c_paid', label = 'How much did they pay you?', needs = { c_deal = true }, stress = true },
    { id = 'c_boss', label = 'Who do you get it from?', needs = { c_deal = true }, stress = true, press = true },
    { id = 'c_gun', label = 'Why did you pull a gun?', needs = { c_gun = true }, stress = true, press = true },
}
local BOSS_Q = {
    { id = 'c_here', label = 'What are you doing here?', stress = true },
    { id = 'c_kid', label = 'Do you know that kid?', stress = true, press = true },
}

-- Who it's about: the card says their name for paramedics.
local CALLED = { seller = 'the seller', uc = 'the undercover officer', detective = 'the detective', boss = 'the man in the car' }

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
    c:objective('brief', 'Meet the case detective', { hint = 'Get the plan and the go word.', blip = 'detective' })
    c:objective('car', "Run the seller's car", { hint = 'Up the street from the deal. Quietly: stay clear of the seller.', blip = 'car' })
    c:objective('exit', 'Cover the back way', { hint = 'Where they would run. Quietly: stay clear of the seller.', blip = 'exit' })
    c:objective('send', "Tell the detective you're set", { after = { 'brief' }, blip = 'detective',
        hint = 'The UC walks in when you say. Stay back until you hear the word.' })
    c:objective('gun', 'Get the gun off the undercover officer', { hidden = true, who = 'all', blip = 'seller', hint = 'Close the distance. Fast.' })
    c:objective('boss', 'Stop the car', { hidden = true, who = 'all', blip = 'boss', hint = "Whoever was running the kid. Don't let them leave." })
    c:objective('standdown', 'Stand down: uncuff and let the task force officer go', { hidden = true, who = 'all', blip = 'seller' })
    c:objective('short', 'Account for the buy money', { hidden = true, blip = 'detective', hint = 'The detective signed out $2,000.' })
    c:objective('buy', 'Get the buy from the undercover officer', { hidden = true, blip = 'uc', hint = 'They have walked back to the detective.' })
    c:objective('decide', 'Move in on the seller: arrest, ticket or warn, or let them go', { hidden = true, who = 'all', blip = 'seller' })
end

-- Done when: the detective's explained the plan, the car and the back way have been looked at, the buy's been handed over.
-- says(): what dispatch has on the car.
local function wire(c, says)
    c:on('act', function(who, action, arg)
        if action ~= 'ask' then return end
        if who == 'detective' and arg == 'c_plan' then c:done('brief') end
        if who == 'uc' and arg == 'c_buy' then
            c:done('buy')
            if c:get('phase') == 'sold' then c:set('handed', true) end
        end
    end)
    c:on('inspect', function(clue)
        if clue == 'exit' then c:done('exit') end
        if clue == 'car' then c:done('car') c:dispatch(says()) end
    end)
end

local function carry(c, key, item) -- (on them from now on: a search finds it)
    local o = c:who(key)
    if not o then return end
    o.items[#o.items + 1] = item
    table.insert(o.pockets, 1, item)
end

-- Someone hurt enough for paramedics: on the card, and nothing ends until they're seen to.
local function casualty(c, who)
    if c:get('medic_' .. who) then return end
    c:set('medic_' .. who, true)
    c:objective('medic:' .. who, ('Call paramedics for %s'):format(CALLED[who] or who), { who = 'all', blip = who,
        hint = 'Radio for an ambulance. If they pronounce them, the coroner can take them.' })
    c:dispatch(('%s is down. Paramedics needed at the scene.'):format(CALLED[who] or who))
end

--[[ The deal: 'wait' until a unit says they're set (or GO_AFTER after the briefing), 'walking' while the UC goes to the
     seller, 'meeting' while the wire plays, then 'sold', 'turned' (o.turn took over) or 'blown' (a unit got too close, or
     the UC can't go on). c:get('phase') says which. o = { wire = { [second] = line, over = seconds }, cash = what the
     seller's paid, sold? = run on the sale, turn? = run instead of the sale } ]]
local function deal(c, o)
    local phase, clock, since, after, met = 'wait', 0, nil, 0, false
    local function enter(next_phase)
        phase, clock = next_phase, 0
        c:set('phase', next_phase)
    end
    enter('wait')
    local function over() return phase == 'sold' or phase == 'turned' or phase == 'blown' end
    local function go(text)
        if phase ~= 'wait' then return end
        enter('walking')
        c:done('send')
        c:task('uc', 'go', 'deal')
        c:dispatch(text or 'Detective: UC is walking. Everyone stay back until you hear the word.')
    end
    local function sold()
        enter('sold')
        c:done('send') c:done('car') c:done('exit')
        carry(c, 'seller', o.cash)
        c:who('seller').facts.c_deal = 'yes'
        c:who('uc').facts.c_sold = 'yes'
        if o.sold then o.sold() end
        c:task('uc', 'go', 'uc')
        c:reveal('decide')
        c:reveal('buy')
        c:note('The buy was made, on the wire.')
        c:dispatch("On the wire: 'We're good to go.'")
        c:dispatch('Detective: That is the word. Move in, all units. Move in.')
    end
    local function blown(text)
        if over() then return end
        enter('blown')
        c:done('send') c:done('car') c:done('exit')
        local s, u = c:who('seller'), c:who('uc')
        if s and not s.cuffed then c:task('seller', 'wander') end
        if u and not u.cuffed then c:task('uc', 'go', 'uc') end
        c:reveal('decide')
        c:note('The deal was blown before the sale.')
        c:dispatch(text or 'Detective: They have made us. The deal is off, UC is walking out. Stop the seller if you can, but there is no sale on record.')
    end
    c:on('fact', function(_, fact)
        if fact == 'c_plan' then since = since or 0 elseif fact == 'c_go' then go() end
    end)
    c:on('contact', function(who)
        if who == 'seller' then met = true end
        if who == 'seller' or who == 'boss' then blown() end
    end)
    local function lost(who) -- (dead, or taken off the scene)
        if who == 'uc' or who == 'seller' then blown(('Detective: %s is down. The deal is off.'):format(who == 'uc' and 'My officer' or 'The seller')) end
        if who == 'detective' then c:done('brief') go('Dispatch: UC is walking on their own. Stay back until you hear the word.') end -- (nobody left to say it)
    end
    c:on('dead', lost)
    c:on('gone', lost)
    c:on('tick', function()
        if phase == 'sold' then
            after = after + 1
            local s = c:who('seller')
            if after == WALK_OFF and not met and s and not s.cuffed then c:task('seller', 'wander') end
        end
        if over() then return end
        local u = c:who('uc')
        if not (u and c:who('seller')) then return end -- (not built yet)
        if c:near('seller', SPOOK) or u.cuffed then return blown() end
        if phase == 'wait' then
            if since then
                since = since + 1
                if since >= GO_AFTER then go("Detective: We can't keep the seller waiting. UC is walking. Stay back until you hear the word.") end
            end
        elseif phase == 'walking' then
            if not c:talking('uc') then clock = clock + 1 end
            if not c:apart('uc', 'seller') or clock >= WALK then enter('meeting') end
        else
            clock = clock + 1
            if o.wire[clock] then c:dispatch(o.wire[clock]) end
            if clock >= o.wire.over then
                if o.turn then enter('turned') o.turn() else sold() end
            end
        end
    end)
end

-- Spoken to for the first time, on foot, `odds` they bolt (the stop's chase). Not once they've given up.
local function may_bolt(c, odds)
    local spoken, bolting = false, false
    c:on('contact', function(who)
        if who ~= 'seller' or spoken then return end
        spoken = true
        bolting = not c:who('seller').gave_up and math.random() < odds
    end)
    c:on('tick', function() -- (a moment after the stop's taken hold of them, or the stop's first order overrides it)
        if not bolting then return end
        bolting = false
        if c:talking('seller') then c:task('seller', 'flee') end
    end)
end

--[[ It's over when the one it's about (culprit) has been taken in, let go, got away or been seen to, nobody's left to take
     in, anyone down has been seen to and ready() (if any) says so. Or the detective's been heard, the deal's over and
     every unit has left. ends(out) -> the MDT summary; out = { [person] = 'arrested' | 'released' | 'cited' | 'warning' |
     'fled' | 'dead' | 'pronounced' | 'hospital' | 'treated', left = true }. ]]
local function resolve(c, culprit, ends, ready)
    local out, taken, away_for, done = {}, {}, 0, false
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function let_go(v) return v == 'released' or v == 'cited' or v == 'warning' or v == 'fled' or v == 'pronounced' or v == 'hospital' or v == 'treated' end
    local function hurt_seen_to()
        for who in pairs(CALLED) do
            if c:get('medic_' .. who) and not c:is_done('medic:' .. who) then return false end
        end
        return true
    end
    local function check()
        if done or waiting() then return end
        if not (out.left or ((taken[culprit] or let_go(out[culprit])) and hurt_seen_to() and (not ready or ready()))) then return end
        done = true
        c:done('decide')
        local text, also, more = ends(out), {}, {}
        for k, v in pairs(out) do
            if k ~= 'left' and not text:find(c:name(k), 1, true) then
                if v == 'arrested' then also[#also + 1] = c:name(k)
                elseif v == 'hospital' then more[#more + 1] = (' %s was taken to hospital.'):format(c:name(k))
                elseif v == 'treated' then more[#more + 1] = (' %s was treated by paramedics at the scene.'):format(c:name(k))
                elseif v == 'dead' or v == 'pronounced' then -- (CPR can have brought them back)
                    if (c:health(k) or 0) <= 100 then more[#more + 1] = (' %s died at the scene.'):format(c:name(k)) end
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
            if who == culprit or who == 'seller' then c:done('decide') end
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
        c:done('medic:' .. who)
        check()
    end
    c:on('gone', function(who)
        if out[who] == 'arrested' then taken[who] = true check() end
        if c:get('medic_' .. who) and not c:is_done('medic:' .. who) then -- (the coroner's been, or the ambulance has them)
            seen_to(who, out[who] == 'dead' and 'pronounced' or 'hospital')
        end
    end)
    c:on('dead', function(who)
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if who == culprit then -- (it's plain what happened: nothing left to work out, only seeing to them)
            for _, id in ipairs({ 'brief', 'car', 'exit', 'send', 'gun', 'boss', 'standdown', 'short', 'buy', 'decide' }) do c:done(id) end
        end
        if who == 'seller' then c:done('decide') c:done('gun') end
        if who == 'uc' then c:done('buy') c:done('short') end
        casualty(c, who)
    end)
    c:on('aid', function(who, what)
        if not c:get('medic_' .. who) then return check() end
        if what == 'pronounced' then seen_to(who, 'pronounced')
        elseif what == 'hospital' or what == 'treated' then seen_to(who, what) end
    end)
    c:on('contact_ended', function(who, outcome)
        if out[who] == 'dead' or out[who] == 'pronounced' or out[who] == 'hospital' or out[who] == 'treated' then return end
        if outcome == 'fled' then out[who] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then out[who] = outcome end
        if who == 'seller' and let_go(out[who]) then c:done('decide') end
        check() -- (walked off from them, 'cancelled': nothing decided)
    end)
    c:on('tick', function()
        local phase = c:get('phase')
        local over = phase == 'sold' or phase == 'blown' or (phase == 'turned' and c:is_done('gun'))
        local here = c:near(nil, AWAY) or c:near('seller', AWAY) or c:near('uc', AWAY) or c:near(culprit, AWAY) or c:talking()
        if over and c:is_done('brief') and not waiting() and not here and hurt_seen_to() and (not ready or ready()) then
            away_for = away_for + 1
            if away_for >= 15 then out.left = true check() end
        else
            away_for = 0
        end
    end)
end

-- What's on record: `on` = { found = what a search of the seller turned up }. The wire, the buy and an admission for free.
local function recorded(c, on)
    local list, s = {}, c:who('seller')
    if c:get('phase') == 'sold' then list[#list + 1] = 'the sale on the wire' end
    if c:get('handed') then list[#list + 1] = 'the buy from the undercover officer' end
    if s and s.facts.found then list[#list + 1] = c:get('phase') == 'blown' and 'what was on them' or on.found end
    if s and s.facts.c_admit then list[#list + 1] = 'an admission' end
    return list[1] and (' Recorded: ' .. table.concat(list, ', ') .. '.') or ''
end

-- What the summary says about whoever it's about.
local function told(c, who, out, what, on)
    local s, how = c:name(who), out[who]
    local blown = c:get('phase') == 'blown' and ' The deal was blown before the sale.' or ''
    if how == 'arrested' then return ('%s: %s arrested.'):format(what, s) .. blown .. recorded(c, on) end
    if how == 'dead' or how == 'pronounced' then return ('%s: %s died at the scene.'):format(what, s) .. blown .. recorded(c, on) end
    if how == 'hospital' or how == 'treated' then return ('%s: %s was seen to by paramedics.'):format(what, s) .. blown .. recorded(c, on) end
    if how == 'fled' then return ('%s: %s ran and got away.'):format(what, s) .. blown end
    if how == 'cited' or how == 'warning' then
        return ('%s: %s was given a %s and let go.'):format(what, s, how == 'cited' and 'ticket' or 'warning') .. blown
    end
    if how then return ('%s: %s was spoken to and let go.'):format(what, s) .. blown end
    return ('%s: %s was not stopped.'):format(what, s) .. blown
end

-- The detective and the UC, at the staging point, with what they say in every story.
local function crew(c, d, u)
    local male = math.random() < .5
    d.c_plan = { { "The UC walks to the seller when you tell me you're set. Two thousand in marked notes for twelve bags. When you hear the word on the wire, you go. Not before: if the seller sees a uniform, it's over.", set = { c_plan = 'yes' } } }
    d.c_word = { "'Good to go.' That's the sale done: move in. If you hear 'my aunt's birthday', that's duress. Forget quiet and come running." }
    d.c_seller = { "Works this spot. A couple of sales to an informant, nothing bigger on paper. No gun that we know of, but we don't know much." }
    d.c_uc = { "Beside me. Two years under, and good at it. Once they're walking, nobody goes near them." }
    d.c_send = function()
        if c:get('phase') == 'blown' then return { "It's off. Stop the seller if you can." } end
        if c:get('phase') ~= 'wait' then return { 'They are already in. Eyes on, and stay back.' } end
        return { { 'Copy. Sending them in. Eyes on, and stay back.', set = { c_go = 'yes' } } }
    end
    d.where = d.where or { "Nowhere until this is done." }
    c:person('detective', { at = 'staging', label = 'Detective', male = male, model = male and 's_m_m_ciasec_01' or 'a_f_y_business_02',
        secret = 'clean', demeanor = 'polite', items = {}, scene = 'WORLD_HUMAN_STAND_MOBILE', questions = DETECTIVE_Q, lines = d })
    local uc_male = math.random() < .5
    u.c_ready = u.c_ready or { "Always. Just stay out of sight until you hear the word." }
    u.c_cover = u.c_cover or { "A buyer from out of town with a friend who pays well. I've met this seller's kind a hundred times." }
    u.where = u.where or { "Over there, in a minute. Then back here." }
    c:person('uc', { at = 'uc', label = 'Undercover officer', male = uc_male, model = uc_male and 'a_m_y_stlat_01' or 'a_f_y_soucent_02',
        secret = 'clean', demeanor = 'polite', items = {}, scene = 'WORLD_HUMAN_SMOKING', questions = UC_Q, lines = u })
    c:on('build', function() -- (officers: going for the cuffs won't send them running)
        for _, key in ipairs({ 'detective', 'uc' }) do
            local o = c:who(key)
            o.ran, o.gave_up = true, true
        end
    end)
end

-- The seller, at the deal spot.
local function seller(c, spec, lines)
    spec.at, spec.label, spec.questions, spec.lines = 'deal', 'Seller', SELLER_Q, lines
    spec.male, spec.model = true, spec.model or 'a_m_y_stbla_01'
    spec.scene = 'WORLD_HUMAN_STAND_IMPATIENT'
    lines.where = lines.where or { "Nowhere. I'm just standing here." }
    c:person('seller', spec)
end

local function car_of(c, spec)
    local car, paint = CARS[math.random(#CARS)], PAINTS[math.random(#PAINTS)]
    spec.at, spec.model, spec.make, spec.name, spec.color, spec.paint = 'car', car.model, car.make, car.name, paint[1], paint[2]
    spec.label = "The seller's car"
    c:vehicle('car', spec)
end

-- What's on the car, from outside, and the back way when there's nothing on it.
local function car_clue(c, text)
    c:clue('car', { on = 'car', label = "The seller's car", text = text })
end
local function quiet_exit(c)
    c:clue('exit', { at = 'exit', label = 'The back way', text = "A gap behind the bins and a clear run through to the next street. Nobody here. If the seller runs, it's this way." })
end

local function registered(c, tail)
    local o = c:owner('car') or {}
    return ('Dispatch: that plate comes back to %s %s, %s.'):format(o.first or 'unknown', o.last or '', o.address or 'no fixed address') .. tail
end

local PRODUCT = 'Twelve bags of white powder'
local OPENING = "On the wire: 'You alone?' 'Just me. You got what I asked for?'"
local SHOW = "On the wire: 'Twelve, like we said. Let me see the money.'"

Callout({
    id = 'sting',
    name = 'Sting operation',
    voice = 'call_sting', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    alert = 'Assist request', -- (a planned job: nobody rang 911)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        'Narcotics detective requests a uniform unit for an undercover buy. Quiet approach, meet at the staging point.',
        'Planned buy operation. Case detective needs an arrest team standing by.',
        'Undercover officer making a buy tonight. Detective requests uniform backup, no lights.',
    },
    -- The points each location needs, in the order /c3rplace sting walks you through them. The first is where the call is
    -- (units are on scene within Config.Callouts.arrive m of it). Keep them all within about 250 m of it.
    points = {
        { 'staging', 'The detective, somewhere out of sight of the deal: behind a building or a car park round the corner.' },
        { 'uc', 'The undercover officer, standing beside the detective.' },
        { 'deal', 'The seller, waiting at the deal spot: a car park or a quiet corner, 80 to 200 m on foot from the detective.' },
        { 'car', "The seller's car, a little way up the street, at least 40 m from the deal spot. Sit in a car parked there.", 'car' },
        { 'exit', 'The back way out of the deal spot: an alley a car can back into, at least 30 m from the seller. Sit in a car parked there.', 'car' },
    },
    -- Add more with /c3rplace sting in game (it writes them here). This one is a rough placeholder.
    locations = {
        { street = 'Procopio Dr', at = vector3(-207.50, 6412.03, 31.57), points = {
            staging = vector4(-207.50, 6412.03, 31.57, 17.5),
            uc = vector4(-207.44, 6409.23, 31.27, 217.9),
            deal = vector4(-281.06, 6350.83, 32.60, 66.9),
            car = vector4(-226.94, 6402.68, 30.90, 303.9),
            exit = vector4(-354.40, 6263.55, 31.28, 137.0),
        } },
        { street = 'Invention Ct', at = vector3(-980.60, -1113.60, 2.15), points = {
            staging = vector4(-980.60, -1113.60, 2.15, 23.1),
            uc = vector4(-982.60, -1113.11, 2.15, 19.2),
            deal = vector4(-1042.64, -1148.68, 2.16, 5.7),
            car = vector4(-1072.84, -1149.52, 1.84, 209.8),
            exit = vector4(-1111.00, -1182.28, 1.83, 120.4),
        } },
        { street = 'Carson Ave', at = vector3(341.58, -1883.77, 25.84), streets = { car = 'Jamestown St', exit = 'Jamestown St' }, points = {
            staging = vector4(341.58, -1883.77, 25.84, 127.3),
            uc = vector4(344.57, -1880.92, 26.14, 339.2),
            deal = vector4(373.86, -1984.18, 24.14, 194.4),
            car = vector4(348.97, -1966.37, 24.11, 317.0),
            exit = vector4(269.44, -2001.81, 19.39, 242.2),
        } },
    },

    stories = {
        -- ── A straight sale. ─────────────────────────────────────────────────────────────────────────────────────
        clean = {
            weight = 3,
            setup = function(c)
                crew(c, {}, { c_buy = { 'Twelve bags, two thousand paid, every note marked. Bagged and signed. All yours.' } })
                seller(c, { secret = 'drugs', demeanor = 'rude', items = { PRODUCT } }, {
                    c_here = { "Waiting for a friend. Is that a crime?" },
                    c_sold = cracks(3, { "Sold what? That was a friend.", "I don't know what you're talking about." },
                        { { "...Yeah. Alright. It paid the rent, okay?", set = { c_admit = 'yes' } } },
                        { "I told you. It paid the rent." }),
                    c_paid = { "Two thousand. And I want it back when this is over." },
                    c_boss = { "You think I'm saying that with a wire in the room? No." },
                })
                car_of(c, { owner = 'seller' })
                car_clue(c, 'From the outside: a tidy car, a phone mount and an empty coffee cup. Nobody in it.')
                quiet_exit(c)
                card(c)
                wire(c, function() return registered(c, ' That is your seller. One prior for possession.') end)
                deal(c, { cash = '$2,000 in marked notes', wire = { [4] = OPENING, [12] = SHOW, [20] = "On the wire: 'Count it.' 'It's all there.'", over = 24 } })
                may_bolt(c, 0.25)
                resolve(c, 'seller', function(out)
                    return told(c, 'seller', out, 'Undercover buy', { found = 'the marked money and the product on them' })
                end)
            end,
        },

        -- ── The bags are baking soda, and the plan is the money. ─────────────────────────────────────────────────
        rip = {
            weight = 2,
            setup = function(c)
                crew(c, {}, { c_buy = { "There was no buy. Those bags are baking soda. They wanted the money, and me on the floor." } })
                seller(c, { secret = 'drugs', demeanor = 'rude', weapon = 'WEAPON_PISTOL',
                    items = { 'Twelve bags of baking soda', 'Pistol, loaded, serial filed off' } }, {
                    c_here = { "Waiting for a friend. Is that a crime?" },
                    c_gun = cracks(2, { "What gun? You saw a gun? I didn't see a gun." },
                        { { "...It's cheaper than having the stuff. You pull it, they hand it over. They never call you lot.", set = { c_admit = 'yes' } } },
                        { "I told you. They never call you lot." }),
                    c_sold = { "Sold? Nothing got sold." },
                    c_paid = { "Nobody paid me anything. Isn't that the point?" },
                    c_boss = { "Baking soda? The supermarket." },
                })
                car_of(c, { stolen = true })
                c:vehicle('getaway', { at = 'exit', model = 'emperor', make = 'Albany', name = 'Emperor', color = 'Black', paint = 0,
                    stolen = true, locked = false, label = 'A car in the alley' })
                car_clue(c, 'Through the glass: a chewed-up ignition barrel and no keys. Nobody in it.')
                c:clue('exit', { at = 'exit', on = 'getaway', label = 'The back way',
                    text = "A car backed into the alley, plates off, doors unlocked, engine still warm. Nobody leaves a car like that for a sale. Someone's planning to leave in a hurry." })
                card(c)
                wire(c, function() return 'Dispatch: that plate was reported stolen two days ago. Detective: Stolen? They told my informant it was theirs. Keep your eyes open.' end)
                local armed, fighting, dead, clock, left = false, false, false, 0, 0
                c:on('inspect', function(clue)
                    if clue ~= 'exit' then return end
                    c:set('warned', true) -- (the back way told them: they're closer when it goes wrong)
                    local phase = c:get('phase')
                    if phase == 'wait' or phase == 'walking' or phase == 'meeting' then
                        c:dispatch("Detective: Copy that. Nobody parks like that for a sale. Get as close as you dare. If I say run, you run.")
                    end
                end)
                local function surrender(line)
                    fighting, armed = false, false
                    local o = c:who('seller')
                    o.ran, o.gave_up = true, true -- (they're done: going for the cuffs won't send them running now)
                    c:done('gun')
                    c:reveal('decide')
                    c:say('seller', line)
                    c:task('seller', 'surrender')
                    c:task('uc', 'go', 'uc')
                end
                local function react() -- (a unit's on them: most give up, some don't)
                    armed = false
                    if math.random() < 0.75 then return surrender("Alright! Alright, it's down! Don't shoot!") end
                    fighting, left = true, math.random(45, 120)
                    c:task('seller', 'shoot')
                end
                local function whip() -- (nobody came)
                    armed = false
                    c:set('hurt', true)
                    carry(c, 'seller', '$2,000 in marked notes')
                    c:collapse('uc', 'A heavy blow to the side of the head. Conscious, confused, and bleeding.')
                    casualty(c, 'uc')
                    c:task('seller', 'flee')
                    c:done('gun')
                    c:reveal('decide')
                    c:note('The seller hit the undercover officer and ran with the buy money.')
                    c:dispatch('Detective: Officer down! They hit my UC and they are running with the money! Stop them!')
                end
                c:on('tick', function()
                    if dead or not (armed or fighting) then return end
                    local o = c:who('seller')
                    if o.cuffed then armed, fighting = false, false return end
                    if armed then
                        clock = clock - 1
                        if c:near('seller', 20.0) then react() elseif clock <= 0 then whip() end
                        return
                    end
                    local health = c:health('seller')
                    left = left - 1 -- (with or without anyone in range: units backing off mustn't leave it running for ever)
                    if health and health > 100 and health < 150 then surrender("Okay! Okay, I'm hit! I'm done! Don't shoot!")
                    elseif left <= 0 then surrender("I'm out! That's it! I'm done, don't shoot!") end
                end)
                c:on('aimed', function(who) if who == 'seller' and armed then react() end end)
                c:on('hail', function(who)
                    if who == 'seller' and fighting and math.random() < 0.5 then surrender("Alright! Alright! I'm putting it down!") end
                end)
                c:on('fired', function(who)
                    if who ~= 'seller' then return end
                    c:dispatch('Shots fired! All units, shots fired!')
                    c:note('Shots fired by the seller')
                end)
                c:on('dead', function(who)
                    if who ~= 'seller' then return end
                    dead, armed, fighting = true, false, false
                    c:task('uc', 'go', 'uc') -- (their hands can come down)
                end)
                deal(c, { wire = { [4] = OPENING, [12] = SHOW, [20] = "On the wire: 'Put the bag on the ground.' 'Money first.'", over = 24 }, turn = function()
                    armed, clock = true, c:get('warned') and 90 or 45
                    c:set('gun', true)
                    c:done('send') c:done('car') c:done('exit')
                    c:who('seller').facts.c_deal, c:who('seller').facts.c_gun = 'yes', 'yes'
                    c:who('uc').facts.c_sold = 'yes'
                    c:task('seller', 'aim', 'uc')
                    c:task('uc', 'surrender')
                    c:reveal('gun')
                    c:note('The seller pulled a gun on the undercover officer.')
                    c:dispatch("On the wire: 'Give me the money. All of it. Do it!' 'Easy. Easy. It's my aunt's birthday, don't do this.'")
                    c:dispatch('Detective: That is the duress word! Gun on my officer! Go, go, go!')
                end })
                resolve(c, 'seller', function(out)
                    local what = c:get('gun') and 'Armed robbery of an undercover officer' or 'Undercover buy'
                    local text = told(c, 'seller', out, what, { found = 'the pistol and the fake product' })
                    if c:get('hurt') and not out.seller then text = text .. ' They got away with the buy money.' end
                    return text
                end)
            end,
        },

        -- ── A frightened kid, and whoever sent them. ─────────────────────────────────────────────────────────────
        runner = {
            weight = 2,
            setup = function(c)
                crew(c, {}, { c_buy = { "Twelve bags, two thousand paid. But the seller's a kid, shaking like a leaf. Kept looking up the street at that car." } })
                seller(c, { model = 'a_m_y_skater_01', age = { 18, 19 }, secret = 'clean', demeanor = 'nervous', items = { PRODUCT } }, {
                    c_here = { "Nothing. I'm meeting someone. Please, can I just go?" },
                    c_sold = { "I know. I know what it was. I didn't want to." },
                    c_paid = { "Two thousand. It's not mine. None of it's mine." },
                    c_boss = cracks(2, { "Nobody. It's just me. Please." },
                        { { "...The man in the car. Up the street. My brother owes him, so now I do this. If he sees me talking to you...", set = { c_admit = 'yes' } } },
                        { "I told you. The man in the car." }),
                })
                c:person('boss', { at = 'car', seated = 'car', label = 'Man in the car', male = true, model = 'a_m_m_og_boss_01', age = { 34, 52 },
                    secret = 'drugs', demeanor = 'rude', runs = true, bail = 0.3, questions = BOSS_Q,
                    items = { 'Forty bags of white powder', "Burner phone: one number in it, the kid's" }, lines = {
                        c_here = { "Sitting in my own car. Going to arrest me for that?" },
                        c_kid = cracks(3, { "What kid?", "I don't know any kids." },
                            { { "...The kid owes me. That's business. You can't make that into anything.", set = { c_admit = 'yes' } } },
                            { "I told you. Business." }),
                        where = { "Home. Are we finished?" },
                    } })
                car_of(c, { owner = 'boss', locked = false })
                car_clue(c, "Someone at the wheel, engine running, phone to their ear. They're watching the deal spot, not you.")
                quiet_exit(c)
                card(c)
                wire(c, function() return registered(c, ' That is not your seller. Priors for supply.') end)
                deal(c, { cash = '$2,000 in marked notes', wire = { [4] = OPENING,
                    [12] = "On the wire: 'Money first. He said money first.' 'Who said?' 'Just... money first.'",
                    [20] = "On the wire: 'You okay, kid?' 'It's twelve. It's all there. Take it.'", over = 24 } })
                may_bolt(c, 0.1)
                local gone, wait = false, 15 -- (the kid's bust, seen from the car: gone in a quarter of a minute)
                local function off()
                    if gone then return end
                    gone = true
                    c:reveal('boss')
                    if c:task('boss', 'drive', { car = 'car', fast = true }) ~= false then
                        c:dispatch('Detective: That car is moving! Someone was running that kid. Stop it!')
                    end
                end
                c:on('tick', function()
                    local phase, b = c:get('phase'), c:who('boss')
                    if gone or not b or b.cuffed then return end
                    if phase == 'blown' then return off() end
                    if phase == 'sold' then
                        wait = wait - 1
                        if wait <= 0 then off() end
                    end
                end)
                c:on('fact', function(who, fact) if who == 'seller' and fact == 'c_admit' then c:reveal('boss') end end)
                c:on('contact', function(who) if who == 'boss' then gone = true c:reveal('boss') c:done('boss') end end)
                resolve(c, 'boss', function(out)
                    local text = told(c, 'boss', out, 'Undercover buy, the supplier', { found = 'the marked money and the product on the seller' })
                    if out.boss == 'arrested' and c:who('boss').facts.found then text = text .. ' Forty bags recovered from them.' end
                    if out.seller == 'released' then
                        local helped = c:who('seller').facts.c_admit
                        text = text .. (' The seller, %s, %s and was let go.'):format(c:name('seller'), helped and 'named them' or 'was spoken to')
                    end
                    return text
                end)
            end,
        },

        -- ── The UC kept $600 of it. ──────────────────────────────────────────────────────────────────────────────
        skim = {
            weight = 2,
            setup = function(c)
                crew(c, {
                    c_short = { { "Fourteen? I signed out two thousand and watched them count it. Ask them where the rest went.", set = { c_count = 'yes' } } },
                    c_onuc = { { "...On them. Two years I've known them. Leave it with me: badge, gun, Internal Affairs tonight. Thank you, officer.", set = { c_report = 'yes' } } },
                }, {
                    c_buy = { 'Twelve bags. Paid the two thousand, every note. It was a good clean buy.' },
                    c_money = cracks(3, { "What do you mean, the rest? I paid the two thousand.", "Then the seller stashed it. Check the ground." },
                        { { "...It was six hundred. Two years of this and I can't make rent. Please don't put this in writing.", set = { c_admit = 'yes' } } },
                        { "I told you. Six hundred. I know what I did." }),
                })
                seller(c, { secret = 'drugs', demeanor = 'rude', items = { PRODUCT } }, {
                    c_here = { "Waiting for a friend. Is that a crime?" },
                    c_sold = cracks(3, { "Sold what? That was a friend.", "I don't know what you're talking about." },
                        { { "...Yeah. Alright. It paid the rent, okay?", set = { c_admit = 'yes' } } },
                        { "I told you. It paid the rent." }),
                    c_paid = { { "Fourteen hundred. That's the price. It's always been the price. Ask your friend.", set = { c_price = 'yes' } } },
                    c_boss = { "You think I'm saying that with a wire in the room? No." },
                })
                car_of(c, { owner = 'seller' })
                car_clue(c, 'From the outside: a tidy car, a phone mount and an empty coffee cup. Nobody in it.')
                quiet_exit(c)
                card(c)
                wire(c, function() return registered(c, ' That is your seller. One prior for possession.') end)
                local function missing()
                    if c:get('missing') or c:get('phase') ~= 'sold' then return end
                    c:set('missing', true)
                    c:who('detective').facts.c_short = 'yes'
                    c:questions('detective')
                    c:reveal('short')
                end
                local function on_them()
                    if c:get('on_uc') then return end
                    c:set('on_uc', true)
                    missing()
                    c:who('detective').facts.c_onuc = 'yes'
                    c:questions('detective')
                end
                c:on('fact', function(who, fact)
                    if who == 'seller' and fact == 'c_price' then missing() end
                    if who == 'detective' and fact == 'c_count' then
                        c:who('uc').facts.c_missing = 'yes'
                        c:questions('uc')
                        c:blip('short', 'uc')
                    end
                    if who == 'detective' and fact == 'c_report' then c:set('reported', true) c:done('short') end
                    if who == 'uc' and fact == 'c_admit' then on_them() end
                end)
                c:on('act', function(who, action)
                    local o = c:who(who)
                    if action == 'frisk' and who == 'seller' and o.facts.found then missing() end
                    if action == 'frisk' and who == 'uc' and o.facts.found then on_them() end
                    if action == 'cuff' and who == 'uc' and o.cuffed then c:done('short') end
                end)
                deal(c, { cash = '$1,400 in marked notes', sold = function() carry(c, 'uc', '$600 in marked notes, folded into a boot') end,
                    wire = { [4] = OPENING, [12] = SHOW, [18] = 'On the wire: (static. The wire has dropped out.)',
                        [24] = 'Detective: Lost them for a second. Stand by, stand by.', [30] = "On the wire: 'Nice doing business.'", over = 34 } })
                may_bolt(c, 0.25)
                resolve(c, 'seller', function(out)
                    local text = told(c, 'seller', out, 'Undercover buy', { found = 'the marked money and the product on them' })
                    local u = c:name('uc')
                    if out.uc == 'arrested' then
                        return text .. (' The undercover officer, %s, was arrested with $600 of the buy money.'):format(u)
                    elseif c:get('reported') then
                        return text .. (' The undercover officer, %s, had $600 of the buy money on them: reported to the detective for Internal Affairs.'):format(u)
                    elseif c:get('missing') then
                        return text .. ' $600 of the buy money was not accounted for.'
                    elseif c:get('phase') == 'sold' then
                        return text .. ' The buy money was not counted.'
                    end
                    return text
                end, function() return not c:get('missing') or c:is_done('short') end)
            end,
        },

        -- ── Two agencies, one table. ─────────────────────────────────────────────────────────────────────────────
        blue = {
            weight = 1,
            setup = function(c)
                crew(c, { c_flag = { "State? On my buy? Nobody told me. Cut them loose. Someone's lieutenant is about to get a phone call." } }, {
                    c_buy = { 'Twelve bags, two thousand paid. Honestly? Smoothest buy I ever made. Almost like they wanted it as much as I did.' } })
                seller(c, { secret = 'clean', demeanor = 'polite', items = { 'Twelve bags of inert test powder', 'State task force badge, in a sock' } }, {
                    c_here = { "My job. Run my name. Slowly, and before you do anything you'll have to write up." },
                    c_sold = { "Did I? That's funny. I thought I was the one running the operation." },
                    c_paid = { "Two thousand in marked notes. Mine are marked too. You might want to make a call." },
                    c_boss = { "Run my name, officer." },
                })
                car_of(c, {})
                car_clue(c, 'From the outside: spotless. A short antenna on the boot lid and a second phone mount. Nobody in it.')
                quiet_exit(c)
                card(c)
                wire(c, function() return registered(c, ' That is not your seller, and the address is a mail drop. No history on it at all.') end)
                local flagged = false
                local function flag()
                    if flagged then return end
                    flagged = true
                    local text = ('Dispatch: hold on that name. %s is flagged: state narcotics task force, undercover. That is one of theirs. Stand down.'):format(c:name('seller'))
                    c:dispatch(text)
                    c:note(text)
                    c:who('detective').facts.c_flag = 'yes'
                    c:questions('detective')
                    c:reveal('standdown')
                end
                c:on('act', function(who, action, arg)
                    if who ~= 'seller' then return end
                    if action == 'licence' or (action == 'ask' and arg == 'name') or (action == 'frisk' and c:who('seller').facts.found) then flag() end
                end)
                c:on('contact_ended', function(who, outcome)
                    if who == 'seller' and outcome ~= 'cancelled' then c:done('standdown') end
                end)
                deal(c, { cash = '$2,000 in marked notes', wire = { [4] = "On the wire: 'You alone?' 'Just me. You?'",
                    [12] = "On the wire: 'Twelve, like we said.' 'Very tidy.'", [20] = "On the wire: 'You've done this before.' 'Not as often as you.'", over = 24 } })
                resolve(c, 'seller', function(out)
                    local s = c:name('seller')
                    if out.seller == 'arrested' then
                        return ('Undercover buy: %s, a state task force officer working the same deal, was booked.%s'):format(s,
                            flagged and ' The flag on the name was ignored.' or ' Nobody ran the name in time.')
                    elseif out.seller == 'fled' then
                        return ('Undercover buy: %s, a state task force officer working the same deal, walked away.'):format(s)
                    elseif out.seller == 'dead' or out.seller == 'pronounced' then
                        return ('Undercover buy: %s, a state task force officer working the same deal, died at the scene.'):format(s)
                    elseif flagged then
                        return ('Undercover buy, no crime: %s is a state task force officer working the same deal. Two agencies bought from each other. Stood down.'):format(s)
                    end
                    return told(c, 'seller', out, 'Undercover buy', { found = 'what was on them' })
                end)
            end,
        },
    },
})
