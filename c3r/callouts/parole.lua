--[[
    c3r callout: PAROLE CHECK.

    A parole agent has had a tip about a client and wants a unit at the home check. The report and the card are the same
    every time: the agent, the door and the property (three units can take one each), then the client, his conditions, and
    back to the agent with what was found. Whether he's really broken his conditions is one of four stories:
      contact    the man at the door isn't a cousin: he's the co-defendant named in the conditions, leaning on the client for
                 one more job. His ID gives him away, and the client only talks out of his earshot
      clean      no breach: the tip's from his ex, the bottles in the yard are months old, and the man at the door is his boss
      relapse    a real breach, for a sad reason: drinking since a funeral. His sister made the call. The agent can find him a
                 treatment bed, and it's the officer's call which way it goes
      gone       he's cut his monitor and it's still reporting from the house. His partner covers for him; he's round the
                 corner with a packed car, and he'll most likely run
    The agent's answer to what was found goes by what the officers really found, not by the truth. It's dealt with when the
    client is taken in, or he's been let go or got away and the agent has been told, or he's been reached and every unit has
    left.

    Points per location: walk them out in game with /c3rplace parole (it writes the location in below).
]]

local AGENT_Q = {
    { id = 'c_tip', label = 'Why did you call us out?' },
    { id = 'c_conditions', label = 'What are his conditions?' },
    { id = 'c_client', label = 'Tell me about him.' },
    { id = 'c_monitor', label = 'What does his monitor say?' },
    { id = 'c_ex', label = 'Could the tip have come from his ex?', needs = { c_ex = true } },
    { id = 'c_option', label = 'Is there anything other than custody?', needs = { c_over = true } },
    { id = 'c_report', label = "Here's what we found.", needs = { c_met = true }, press = true },
}
local DOOR_Q = {
    { id = 'c_who', label = 'Who are you?' },
    { id = 'c_here', label = 'What are you doing here?' },
    { id = 'c_where_he', label = 'Where is he?' },
    { id = 'c_him', label = 'How has he been lately?', stress = true, press = true },
    { id = 'c_named', label = 'You are the man named in his conditions.', needs = { c_named = true }, stress = true, press = true },
    { id = 'c_cut', label = 'He cut his monitor. Where has he gone?', needs = { c_cut = true }, stress = true, press = true },
}
local CLIENT_Q = {
    { id = 'c_how', label = 'How have things been going?' },
    { id = 'c_day', label = 'Where have you been today?', stress = true },
    { id = 'c_tip', label = "We've had a report you've broken your conditions.", stress = true, press = true },
    { id = 'c_drink', label = 'Have you been drinking?', stress = true, press = true },
    { id = 'c_visitor', label = 'Who is that at the door?', stress = true, press = true },
    { id = 'c_monitor', label = 'Is your monitor on?' },
    { id = 'c_enemy', label = 'Who would want to make trouble for you?', stress = true },
}

local AWAY = 400.0 -- (running, and this far from every unit: he's got away)
local CALLED = { agent = 'the parole agent', client = 'the client', other = 'the person at the door' }
-- The co-defendant in the conditions, in the stories where he isn't the one at the door.
local NAMES = { 'Dale Rourke', 'Marcus Teal', 'Ronnie Vance', 'Curtis Boyle', 'Wade Hanlon', 'Glenn Pruitt' }

-- Denies it until pressed `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

-- Gives someone a fact the officer found out elsewhere, so the question it opens is there the next time they're spoken to.
local function tell(c, who, fact)
    local o = c:who(who)
    if not o then return end
    o.facts[fact] = 'yes'
    c:questions(who)
end

-- What's been found against him: what the agent answers to, and what's on the report.
local function found(c, what)
    local list = c:get('found') or {}
    for _, x in ipairs(list) do if x == what then return end end
    list[#list + 1] = what
    c:set('found', list)
end

local function the_agent(c, banned, lines)
    lines.c_tip = { "A tip to the office this morning, no name given. It says he's broken his conditions. I can't do a home check on that alone." }
    lines.c_conditions = function()
        return { ("Four. No alcohol or drugs. The monitor stays on. He stays in the county. And no contact with %s, his co-defendant."):format(banned()) }
    end
    lines.c_client = function()
        return { ("%s. Burglary, with a partner. Out fourteen months, and until today his name hadn't come up once."):format(c:name('client')) }
    end
    lines.c_monitor = { "Home. It's said home all day." }
    lines.c_report = function(o)
        local list = c:get('found')
        if list then
            return { ("So: %s. That's a breach. It goes in my report, and what happens to him today is down to you."):format(table.concat(list, ', ')) }
        end
        if o.facts.c_malicious then return { "Nothing against him, and a tip I've marked as malicious. I'll close it. Thanks for coming out." } end
        return { "Nothing against him, then. I'll log the tip as unfounded." }
    end
    c:person('agent', { at = 'agent', label = 'Parole agent', secret = 'clean', demeanor = 'polite', items = {},
        scene = 'WORLD_HUMAN_STAND_MOBILE', questions = AGENT_Q, lines = lines })
end

local function the_door(c, spec, lines)
    spec.at, spec.label, spec.questions, spec.lines = 'other', 'Person at the door', DOOR_Q, lines
    spec.scene = spec.scene or 'WORLD_HUMAN_STAND_IMPATIENT'
    c:person('other', spec)
end

local function the_client(c, spec, lines)
    lines.where = lines.where or { "Nowhere. I live here." }
    lines.live = lines.live or { 'Right here. This is the address on my paperwork.' }
    lines.address = lines.address or function() return { ('This house. %s.'):format(c:who('client').person.address) } end
    spec.at, spec.label, spec.male, spec.home, spec.flags = spec.at or 'client', 'Client', true, true, { 'PAROLE' }
    spec.age, spec.questions, spec.lines = { 30, 48 }, CLIENT_Q, lines
    spec.scene = spec.scene or 'WORLD_HUMAN_SMOKING'
    c:person('client', spec)
end

local function card(c, away)
    c:objective('agent', 'Talk to the parole agent', { hint = 'Get the tip, and his conditions.', blip = 'agent' })
    c:objective('door', 'Make contact at the address', { hint = 'Front door.', blip = 'other' })
    c:objective('yard', 'Look around the property', { hint = 'Anything that goes against his conditions.', blip = 'yard' })
    c:objective('client', 'Talk to the client', { after = { 'door' }, blip = not away and 'client' or nil, hint = 'He should be at home.' })
    c:objective('check', 'Check him against his conditions', { after = { 'client' }, blip = 'client',
        hint = 'A breath test, a drug swab, a search, and who he is with.' })
    c:objective('report', 'Report back to the parole agent', { after = { 'client' }, blip = 'agent', hint = 'Tell them what you found.' })
    c:objective('alone', 'Talk to him away from the visitor', { hidden = true, blip = 'client', hint = "Out of the visitor's earshot: more than 10 m apart, or with him in cuffs." })
    c:objective('tip', 'Check the tip with the agent', { hidden = true, blip = 'agent', hint = 'Ask them about his ex.' })
    c:objective('option', 'Ask the agent what can be done for him', { hidden = true, blip = 'agent', hint = "There may be more than one way to end this." })
    c:objective('find', 'Find him: he has cut his monitor', { hidden = true, hint = 'Somebody knows where he went.' })
    c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'client' }, who = 'all', blip = 'client' })
end

-- Reached him, or he's got away: the card moves on, and there's something to tell the agent.
local function met(c)
    c:done('client')
    c:done('find')
    tell(c, 'agent', 'c_met')
end

-- Done when: the agent has given the conditions, contact's made at the door, the property's been looked at, he's been
-- reached and tested or searched, and the agent has heard what was found. finds = { yard, car, client, other }: what each
-- turns up against him, for the report.
local function wire(c, finds)
    c:on('act', function(who, action, arg)
        local o = c:who(who)
        if who == 'agent' and action == 'ask' and arg == 'c_conditions' then c:done('agent') end
        if who == 'agent' and action == 'ask' and arg == 'c_report' then
            c:done('report')
            -- ponytail: found more after this and they've not heard: the report drops "was told", the card doesn't ask again
            c:set('told', #(c:get('found') or {}))
        end
        if who == 'client' and (action == 'breath' or action == 'drugs' or action == 'frisk') then c:done('check') end
        if action == 'frisk' and o and o.facts.found and finds[who] then found(c, finds[who]) end
    end)
    c:on('inspect', function(clue)
        if clue == 'yard' then c:done('yard') end
        if finds[clue] then found(c, finds[clue]) end
    end)
    c:on('contact', function(who)
        if who == 'other' then c:done('door') end
        if who == 'client' then
            met(c)
            c:reveal('car')
        end
    end)
    local function door_gone(who) if who == 'other' then c:done('door') end end
    c:on('dead', door_gone)
    c:on('gone', door_gone)
    local said = false -- (heard as the first unit gets close)
    c:on('tick', function()
        if said or not c:near('agent', 30.0) then return end
        said = true
        c:say('agent', "Over here, officer. Thanks for coming.")
    end)
end

-- -> a function that gives them `odds` of bolting (the stop's chase): a tick later, or the stop's first order overrides it.
local function may_bolt(c, who, odds)
    local bolting = false
    c:on('tick', function()
        if not bolting then return end
        bolting = false
        if c:talking(who) then c:task(who, 'flee') end
    end)
    return function() bolting = math.random() < odds end
end

--[[ It's over when the client has been taken in; or he's been let go or got away, or has died and been seen to, and the
     agent has been told; or he's been reached and every unit has left. Nobody's left waiting to be taken in first. Anyone
     hurt badly enough to die is a casualty: the card says to call paramedics.
     ends(out) -> the MDT summary; out = { [person] = 'arrested' | 'released' | 'cited' | 'warning' | 'fled' | 'dead' |
     'pronounced' | 'hospital', left = true }. ]]
local function resolve(c, ends)
    local out, taken, away_for, done, medic = {}, {}, 0, false, {}
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function let_go(v) return v == 'released' or v == 'cited' or v == 'warning' or v == 'fled' or v == 'pronounced' or v == 'hospital' end
    local function revived(who) -- (CPR can have brought them back)
        if out[who] == 'dead' and (c:health(who) or 0) > 100 then out[who] = nil end
    end
    local function no_agent()
        c:done('agent')
        c:done('report')
        c:done('tip')
        c:done('option')
    end
    local function check()
        if done or waiting() then return end
        if not (taken.client or out.left or (let_go(out.client) and c:is_done('report'))) then return end
        done = true
        c:done('decide')
        local text, also, more = ends(out), {}, {}
        for k, v in pairs(out) do
            if k ~= 'left' and not text:find(c:name(k), 1, true) then
                if v == 'arrested' then also[#also + 1] = c:name(k)
                elseif v == 'hospital' then more[#more + 1] = (' %s was taken to hospital.'):format(c:name(k))
                elseif v == 'dead' or v == 'pronounced' then -- (CPR can have brought them back)
                    if (c:health(k) or 0) <= 100 then more[#more + 1] = (' %s died at the scene.'):format(c:name(k)) end
                elseif v == 'fled' then more[#more + 1] = (' %s ran and got away.'):format(c:name(k))
                elseif v == 'cited' then more[#more + 1] = (' %s was given a ticket.'):format(c:name(k))
                elseif v == 'warning' then more[#more + 1] = (' %s was given a warning.'):format(c:name(k)) end
            end
        end
        table.sort(also)
        table.sort(more)
        c:finish(text .. (also[1] and (' Also arrested: ' .. table.concat(also, ', ') .. '.') or '') .. table.concat(more)
            .. (c:get('told') == #(c:get('found') or {}) and ' The parole agent was told.' or ''))
    end
    c:on('act', function(who, action)
        local o = c:who(who)
        revived(who)
        if action == 'cuff' and o and o.cuffed then
            out[who] = 'arrested'
            c:custody(who)
            if who == 'client' then c:done('decide') end
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
        if who == 'agent' then no_agent() end
        if out[who] == 'arrested' then taken[who] = true
        elseif out[who] == 'dead' then return seen_to(who, 'pronounced') -- (the coroner's been)
        elseif who == 'client' and not out.client then -- (got clear)
            out.client = 'fled'
            met(c)
            c:done('check')
        end
        check()
    end)
    c:on('dead', function(who)
        if who == 'client' then -- (it's plain what happened: nothing left to work out, only seeing to him)
            c:set('dead_client', true)
            met(c)
            for _, id in ipairs({ 'check', 'alone', 'tip', 'option', 'decide' }) do c:done(id) end
        end
        if who == 'agent' then no_agent() end
        out[who] = 'dead' -- (not taken in now, in cuffs or not)
        c:hide('custody:' .. who)
        if medic[who] then return end
        medic[who] = true
        c:objective('medic:' .. who, ('Call paramedics for %s'):format(CALLED[who] or who), { who = 'all', blip = who,
            hint = 'Radio for an ambulance. If they pronounce them, the coroner can take them.' })
        c:dispatch(('%s is down. Paramedics needed at the scene.'):format(CALLED[who] or who))
    end)
    c:on('aid', function(who, what)
        if what == 'pronounced' then seen_to(who, 'pronounced')
        elseif what == 'hospital' or what == 'treated' then seen_to(who, 'hospital') end
    end)
    c:on('contact_ended', function(who, outcome)
        revived(who)
        if out[who] == 'dead' or out[who] == 'pronounced' or out[who] == 'hospital' then return end
        if outcome == 'fled' then
            out[who] = 'fled'
            if who == 'client' then met(c) c:done('check') end
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[who] ~= 'arrested' then
            out[who] = outcome
        end
        check() -- (walked off from them, 'cancelled': nothing decided)
    end)
    c:on('tick', function()
        local here = c:near(nil, 80.0) or c:near('client', 80.0) or c:talking()
        if c:is_done('client') and not waiting() and not here then
            away_for = away_for + 1
            if away_for >= 15 then out.left = true check() end
        else
            away_for = 0
        end
    end)
end

-- What the summary says about him. `what`: the call, once something's been found against him. Nothing found reads the
-- same in every story.
local function told(c, out, what)
    local n, list, how = c:name('client'), c:get('found'), out.client
    local on = list and (' Recorded: ' .. table.concat(list, ', ') .. '.') or ''
    local head = list and what or 'Parole check, no breach found'
    if how == 'arrested' then return ('%s: %s arrested.'):format(head, n) .. (list and on or ' Nothing recorded against him.') end
    if how == 'dead' or how == 'pronounced' then return ('%s: %s died at the scene.'):format(head, n) .. on end
    if how == 'hospital' then return ('%s: %s was taken to hospital.'):format(head, n) .. on end
    if how == 'fled' then return ('%s: %s ran and got away.'):format(head, n) .. on end
    if how == 'cited' or how == 'warning' then
        return ('%s: %s was given a %s and let go.'):format(head, n, how == 'cited' and 'ticket' or 'warning') .. on
    end
    if how then return ('%s: %s was spoken to and let go.'):format(head, n) .. on end
    return ('%s: %s was not dealt with.'):format(head, n) .. on
end

local function a_name()
    local name = NAMES[math.random(#NAMES)]
    return function() return name end
end

Callout({
    id = 'parole',
    name = 'Parole check',
    voice = 'call_parole', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    weight = 1,
    enabled = true,
    reports = {
        "Parole agent requests a patrol unit at a client's address. Possible breach of conditions.",
        'Parole office has had a tip about one of their clients and wants an officer present for a home check.',
        'Parole agent on scene asking for a unit. Concerns about a client under supervision.',
    },
    -- The points each location needs, in the order /c3rplace parole walks you through them ('car': sit in a car). The first
    -- is where the call is (units are on scene within Config.Callouts.arrive m of it). Keep away and away_car within about
    -- 250 m: they're made when a unit gets near.
    points = {
        { 'agent', 'The parole agent, waiting on the pavement outside the house.' },
        { 'other', 'Whoever answers: at the front door.' },
        { 'client', 'The client, out in the yard or round the side: well within 10 m of the door, so he can hear what is said there.' },
        { 'yard', 'Something on the property: on the ground by the bins.' },
        { 'car', 'A car parked at the house. Sit in a car parked there.', 'car' },
        { 'away', 'Where he is in the story where he has left: on foot beside his car, round the corner.' },
        { 'away_car', 'His car there, pointing the way out. Sit in a car parked there.', 'car' },
    },
    -- Add more with /c3rplace parole in game (it writes them here). This one is a rough placeholder.
    locations = {
        { street = 'West Mirror Drive', at = vector3(881.40, -556.30, 57.60), points = {
            agent = vector4(881.40, -556.30, 57.60, 297.8),
            other = vector4(890.96, -548.03, 58.16, 110.8),
            client = vector4(896.50, -543.00, 58.10, 283.2),
            yard = vector4(903.65, -535.54, 58.14, 0.0),
            car = vector4(887.56, -553.01, 57.65, 297.8),
            away = vector4(923.90, -481.56, 60.70, 208.6),
            away_car = vector4(934.49, -492.57, 59.84, 156.6),
        } },
        { street = 'Roy Lowenstein Blvd', at = vector3(417.74, -1720.11, 29.19), streets = { away = 'Macdonald St', away_car = 'Macdonald St' }, points = {
            agent = vector4(417.74, -1720.11, 29.19, 74.1),
            other = vector4(430.15, -1725.21, 29.60, 61.3),
            client = vector4(443.56, -1731.82, 29.23, 235.9),
            yard = vector4(428.75, -1728.24, 29.54, 157.8),
            car = vector4(421.54, -1711.91, 28.74, 321.7),
            away = vector4(382.35, -1774.59, 29.29, 12.2),
            away_car = vector4(394.18, -1775.95, 28.74, 232.2),
        } },
        { street = 'Joshua Rd', at = vector3(384.71, 2952.26, 41.05), points = {
            agent = vector4(384.71, 2952.26, 41.05, 102.9),
            other = vector4(412.18, 2965.15, 41.89, 65.5),
            client = vector4(415.14, 2958.25, 40.88, 97.0),
            yard = vector4(417.79, 2972.02, 40.97, 105.7),
            car = vector4(408.46, 2969.64, 40.56, 121.2),
            away = vector4(276.34, 2837.48, 43.51, 264.7),
            away_car = vector4(273.33, 2839.48, 43.09, 209.7),
        } },
    },

    stories = {
        -- ── The man at the door is the one he's barred from. ─────────────────────────────────────────────────────
        contact = {
            weight = 3,
            setup = function(c)
                the_agent(c, function() return c:name('other') end, {})
                the_door(c, { male = true, secret = 'nervous', warrant = 'Failure to appear', demeanor = 'rude', -- (not secret = 'warrant': he hands over his real ID)
                    items = { 'Lock picks in a soft case', 'Floor plan of a pharmacy, marked up in pen' } }, {
                    c_who = { "His cousin. Visiting." },
                    c_here = { "Family. Is that a crime now?" },
                    c_where_he = { "Round the side. What's he done?" },
                    c_him = { "Keeping his head down. Like he should." },
                    c_named = cracks(2, { "Never heard of him. I'm his cousin.", "Names get mixed up. Check again." },
                        { { "...So what? We go back. He owes me, and he knows it.", set = { c_admit = 'yes' } } },
                        { "I said what I said. He owes me." }),
                    where = { "Nowhere. I'm visiting." },
                })
                local cover = { "My cousin. Just my cousin. Can we leave it there?", "Family. He's going soon." }
                local press = cracks(2, { "My cousin. I told you.", "Look, he's just a cousin." },
                    { { "...It's him. He turned up three days ago with a job lined up, and says I owe him for keeping my name out of the last one. I told him to go. I didn't know who I could call.",
                        set = { c_admit = 'yes' } } },
                    { "I told you. I never asked him here." })
                the_client(c, { secret = 'nervous', demeanor = 'nervous', items = {}, pockets = { 'A second phone, switched off' } }, {
                    c_how = { "Good. Working when I can, keeping my head down." },
                    c_day = { "Here. All day. Ask my agent, the monitor says so." },
                    c_tip = { "Who says? I've done everything they asked.", "Then they've got it wrong. Test me if you want." },
                    c_drink = { "No. Test me." },
                    c_visitor = function(o)
                        if not c:apart('client', 'other') then return cover end
                        return press(o)
                    end,
                    c_monitor = { "On. Look. It hasn't been off since the day I got out." },
                    c_enemy = { "Nobody. I keep to myself." },
                })
                c:vehicle('car', { at = 'car', model = 'emperor', make = 'Albany', name = 'Emperor', color = 'Black', paint = 0,
                    owner = 'other', label = 'The car' })
                c:clue('yard', { at = 'yard', label = 'By the bins', prop = 'prop_ing_crowbar',
                    text = 'A holdall pushed in behind the bins: a crowbar, bolt cutters, gloves and two cheap phones still in the packet.' })
                c:clue('car', { on = 'car', label = 'The car', hidden = true,
                    text = 'Through the window: a road map with a pharmacy circled on it, and a list of opening hours in the same pen.' })
                card(c)
                wire(c, { yard = 'the tools behind the bins', car = 'the map in the car', other = 'the lock picks and floor plan on the visitor' })
                local bolt = may_bolt(c, 'other', 0.3)
                local said = false
                c:on('act', function(who)
                    if who ~= 'other' or said or not c:who('other').identified then return end
                    said = true
                    local text = ('Dispatch: %s is the co-defendant named in the parole conditions.'):format(c:name('other'))
                    c:dispatch(text)
                    c:note(text)
                    found(c, 'the visitor identified as his co-defendant')
                    tell(c, 'other', 'c_named')
                    c:reveal('alone')
                    bolt()
                end)
                c:on('fact', function(who, fact)
                    if who == 'client' and fact == 'c_admit' then
                        c:reveal('alone')
                        c:done('alone')
                        found(c, 'his statement')
                        tell(c, 'other', 'c_named')
                    end
                end)
                resolve(c, function(out) return told(c, out, 'Parole breach, contact with a co-defendant') end)
            end,
        },

        -- ── Nothing in it: his ex rang it in. ────────────────────────────────────────────────────────────────────
        clean = {
            weight = 3,
            setup = function(c)
                the_agent(c, a_name(), {
                    c_ex = { { "...Hold on, the tip log has the number. Yes. That's hers. Third call this year. I'll mark it as malicious.", set = { c_malicious = 'yes' } } },
                })
                the_door(c, { secret = 'clean', demeanor = 'polite', items = {} }, {
                    c_who = { "I run the crew he's on. Roofing." },
                    c_here = { "Picking him up. We've got a job at four." },
                    c_where_he = { "Round the side, getting his boots on." },
                    c_him = { "First on site, last off it. I wish I had ten of him." },
                    where = { "To work, as soon as you're done with him." },
                })
                the_client(c, { secret = 'clean', demeanor = 'polite', items = {}, pockets = { 'Work rota: six shifts this week', "Last week's payslip" } }, {
                    c_how = { "Good. Three years off the drink, a steady job. It's the best it's been." },
                    c_day = { "On site from seven till two. Home for a shower. Back out at four." },
                    c_tip = { "Not again. Go on, test me. Search me. I've got nothing to hide." },
                    c_drink = { "No. Not in three years. Go on, test me." },
                    c_visitor = { "That's my boss. We've got a job at four." },
                    c_monitor = { "On. Have a look." },
                    c_enemy = { { "My ex. She said she'd have me sent back, and she's rung your lot before.", set = { c_ex = 'yes' } } },
                })
                c:vehicle('car', { at = 'car', model = 'burrito3', make = 'Declasse', name = 'Burrito', color = 'White', paint = 111,
                    owner = 'other', label = 'The van' })
                c:clue('yard', { at = 'yard', label = 'By the bins', prop = 'prop_cardbordbox_02a',
                    text = 'A box of empty beer bottles. Cobwebs across the top, the labels bleached: they have been out here for months. A note on the side in marker: LEFT BY LAST TENANT.' })
                c:clue('car', { on = 'car', label = 'The van', hidden = true,
                    text = 'Ladders on the rack, roofing tools in the back. A site pass and a rota on the dash, with his name on every shift this week.' })
                card(c)
                wire(c, {})
                c:on('fact', function(who, fact)
                    if who == 'client' and fact == 'c_ex' then
                        tell(c, 'agent', 'c_ex')
                        c:reveal('tip')
                    end
                    if who == 'agent' and fact == 'c_malicious' then c:done('tip') end
                end)
                resolve(c, function(out)
                    return told(c, out)
                        .. (c:who('agent') and c:who('agent').facts.c_malicious and ' The tip was malicious, from his ex.' or '')
                end)
            end,
        },

        -- ── A real breach, and a sad one. ────────────────────────────────────────────────────────────────────────
        relapse = {
            weight = 2,
            setup = function(c)
                the_agent(c, a_name(), {
                    c_option = { { "I can get him a treatment bed tonight. Let him go and I'll drive him there myself. Take him in and he goes back inside. It's your call.",
                        set = { c_bed = 'yes' } } },
                })
                local TRUTH = { { "...I rang it in. Our mum died last week and he's drinking again. He'll kill himself. I didn't know who else to call. Please don't tell him it was me.",
                    set = { c_worried = 'yes' } } }
                local COVER = { "He's fine. He's doing fine.", "Fine. Why wouldn't he be?" }
                the_door(c, { male = false, family = true, secret = 'clean', demeanor = 'nervous', items = {} }, {
                    c_who = { "His sister." },
                    c_here = { "I come by most days. Somebody has to." },
                    c_where_he = { "Round the side. He's fine. Leave him be." },
                    c_him = function(o)
                        if o.facts.c_worried then return { "I've told you. Please. Just help him." } end
                        return c:apart('client', 'other') and TRUTH or COVER
                    end,
                })
                the_client(c, { family = true, secret = 'drunk', demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_IMPATIENT', items = { 'Half a bottle of vodka in his jacket' } }, {
                    c_how = { "Alright. Up and down. Alright." },
                    c_day = { "Here. Just here." },
                    c_tip = { "Conditions? I've been here all day. Ask the monitor." },
                    c_drink = cracks(3, { "No. It's mouthwash.", "I've not touched it." },
                        { { "...Since the funeral. A bit. A lot. I can't sleep without it.", set = { c_admit = 'yes' } } },
                        { "I told you. Since the funeral." }),
                    c_visitor = { "My sister. Leave her out of it." },
                    c_monitor = { "On. It's on. I never touched it." },
                    c_enemy = { "Nobody. Nobody's left." },
                })
                c:vehicle('car', { at = 'car', model = 'premier', make = 'Declasse', name = 'Premier', color = 'Silver', paint = 4,
                    owner = 'other', label = 'The car' })
                c:clue('yard', { at = 'yard', label = 'By the bins', prop = 'prop_cs_beer_bot_01',
                    text = 'A carrier bag pushed down behind the bins: three empty vodka bottles. No dust on them. Recent.' })
                c:clue('car', { on = 'car', label = 'The car', hidden = true,
                    text = 'An order of service from a funeral on the passenger seat, dated last week.' })
                card(c)
                wire(c, { yard = 'the bottles behind the bins', client = 'the vodka on him' })
                c:on('act', function(who, action)
                    if who == 'client' and action == 'breath' and (tonumber(c:who('client').truth.bac) or 0) >= Config.Tests.bac_limit then
                        found(c, 'a breath test over the limit')
                    end
                end)
                c:on('fact', function(who, fact)
                    if who == 'client' and fact == 'c_admit' then found(c, 'his admission') end
                    if who == 'other' and fact == 'c_worried' then found(c, "his sister's statement") end
                    if who == 'agent' and fact == 'c_bed' then c:done('option') end
                end)
                local opened = false
                c:on('tick', function() -- (there's a breach, so now it's a question of what to do about it)
                    if opened or not c:get('found') then return end
                    opened = true
                    tell(c, 'agent', 'c_over')
                    c:reveal('option')
                end)
                resolve(c, function(out)
                    local a = c:who('agent')
                    local how = out.client
                    if a and a.facts.c_bed and (how == 'released' or how == 'cited' or how == 'warning') then
                        local list = c:get('found')
                        return ('Parole breach, drinking: %s left with the agent for a treatment bed.'):format(c:name('client'))
                            .. (list and (' Recorded: ' .. table.concat(list, ', ') .. '.') or '')
                    end
                    return told(c, out, 'Parole breach, drinking')
                end)
            end,
        },

        -- ── He's cut his monitor and gone. ───────────────────────────────────────────────────────────────────────
        gone = {
            weight = 2,
            setup = function(c)
                the_agent(c, a_name(), {})
                the_door(c, { male = false, secret = 'clean', demeanor = 'nervous', home = true, items = {} }, {
                    c_who = { "His partner. I live here." },
                    c_here = { "I live here. So does he." },
                    c_where_he = { "At work. He left this morning." },
                    c_him = { "He's fine. Same as ever. He's at work." },
                    c_cut = cracks(2, { "Cut it? I don't know anything about that.", "He wouldn't. He's only got three months left." },
                        { { "...He left an hour ago. He said he can't go back in there. He's round the corner, loading the car. Please don't hurt him.",
                            set = { c_admit = 'yes', c_where = 'away' } } },
                        { "I told you. Round the corner, with the car." }),
                    where = { "Nowhere. I'm waiting for him." },
                })
                the_client(c, { at = 'away', secret = 'nervous', demeanor = 'nervous', runs = true, bail = 0.5,
                    items = { 'Roll of cash in a sock', 'One-way bus ticket out of the county' } }, {
                    c_how = { "How do you think?" },
                    c_day = { "Getting ready." },
                    c_tip = { "...I know why you're here." },
                    c_drink = { "No." },
                    c_visitor = { "Leave her out of it. She doesn't know anything." },
                    c_monitor = { { "I cut it. I can't do another year in there. I just can't.", set = { c_admit = 'yes' } } },
                    c_enemy = { "Nobody. That's the point." },
                    where = { "Anywhere." },
                })
                c:vehicle('car', { at = 'away_car', model = 'asea', make = 'Declasse', name = 'Asea', color = 'Dark blue', paint = 62,
                    owner = 'client', locked = false, label = 'His car' })
                c:clue('yard', { at = 'yard', label = 'By the bins', prop = 'prop_cardbordbox_02a',
                    text = 'A box by the bins, old newspaper on top. Underneath, a GPS ankle monitor with the strap cut clean through, its light still blinking. It has been reporting from here all day.' })
                c:clue('car', { on = 'car', label = 'His car', hidden = true,
                    text = 'The back seat is full: a packed holdall, a pillow, boxes of food. A map folded open at the county line.' })
                card(c, true)
                wire(c, { yard = 'the cut monitor', car = 'the packed car', client = 'the cash and the bus ticket on him' })
                c:on('inspect', function(clue)
                    if clue ~= 'yard' then return end
                    tell(c, 'other', 'c_cut')
                    tell(c, 'agent', 'c_met')
                    c:reveal('find')
                    c:dispatch("Parole agent: his monitor's been cut and it's still at the address. He is not where it says he is.")
                end)
                local function locate(text)
                    if c:is_done('client') then return end
                    c:reveal('find')
                    c:blip('find', 'client')
                    c:blip('client', 'client')
                    c:dispatch(text)
                end
                c:on('fact', function(who, fact)
                    if who == 'client' and fact == 'c_admit' then found(c, 'his admission') end
                    if who == 'other' and fact == 'c_where' then
                        found(c, "his partner's statement")
                        locate("He's round the corner, loading a car. Marking it on your map.")
                    end
                end)
                local function no_partner(who) -- (taken in or down before she said: someone else saw him)
                    if who == 'other' then locate("A neighbour's seen him round the corner, loading a car. Marking it on your map.") end
                end
                c:on('dead', no_partner)
                c:on('gone', no_partner)
                -- a unit coming: most times he's off, by car; the rest he's had enough. Once clear of every unit, he's gone.
                local seen, running, by_car = false, false, false
                c:on('contact', function(who) if who == 'client' then running = false end end) -- (caught up with: the stop has him)
                c:on('tick', function()
                    local o = c:who('client')
                    if not o or o.cuffed or c:get('dead_client') or c:talking('client') then return end
                    if not seen and c:near('client', 35.0) then
                        seen = true
                        if math.random() >= 0.75 then
                            c:say('client', "Alright. I'm done. I'm not running.")
                        elseif c:task('client', 'drive', { car = 'car', fast = true }) ~= false then
                            running, by_car = true, true
                        else
                            running = true
                            c:task('client', 'flee')
                        end
                    end
                    if running and not c:near('client', AWAY) then
                        running = false
                        c:remove('client', by_car and 'car' or nil)
                    end
                end)
                resolve(c, function(out) return told(c, out, 'Parole breach, absconded') end)
            end,
        },
    },
})
