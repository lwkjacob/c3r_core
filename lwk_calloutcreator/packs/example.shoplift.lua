--[=[c3rcc
{"card":[{"blip":["clerk"],"hint":"At the store.","id":"clerk","text":"Talk to the clerk"},{"blip":["man"],"hidden":true,"id":"find","text":"Find the man"},{"blip":["man"],"hidden":true,"id":"decide","text":"Deal with him: arrest, ticket or warn, or let him go","who":"all"}],"enabled":false,"id":"shoplift","locations":[{"points":{"bag":{"h":0,"x":45.1,"y":-1365.2,"z":29.3},"clerk":{"h":270,"x":25.71,"y":-1347,"z":29.5},"man":{"h":180,"x":68.3,"y":-1390.4,"z":29.36}},"street":"Innocence Blvd"}],"name":"Shoplifting","points":[{"name":"clerk","text":"The clerk, at the store doorway."},{"name":"man","text":"Up the street: where the man is found."},{"name":"bag","optional":true,"text":"A dropped carrier bag on the pavement between them."}],"priority":3,"qsets":[{"id":"clerk","questions":[{"id":"c_what","label":"What happened?"},{"id":"c_way","label":"Which way did he go?"},{"id":"c_look","label":"What did he look like?"}]}],"reports":["Store clerk reports a man left without paying.","Caller says someone has just walked out of the shop with stolen goods."],"service":"police","stories":[{"clues":[{"at":"bag","key":"bag","label":"Dropped bag","prop":"prop_cs_cardbox_01","text":"Two packs of razor blades, security tags still on, in the gutter."}],"ending":{"decide":"decide","heard":"clerk","lines":{"arrested":"Shoplifting: {name} arrested.","cited":"Shoplifting: {name} was given a ticket.","left":"Shoplifting: the clerk was heard, nobody was found.","released":"Shoplifting: {name} was spoken to and let go."},"mode":"subject","subject":"man"},"id":"theft","people":[{"at":"clerk","demeanor":"chatty","key":"clerk","label":"Clerk","lines":[{"answers":[{"text":"A man filled his jacket with stuff off the shelves and walked straight out."}],"q":"c_what"},{"answers":[{"set":[{"fact":"c_way","value":"north"}],"text":"North. Up the street. He was not even running."}],"q":"c_way"},{"answers":[{"text":"Grey hoodie. Thirties. Carrier bag."}],"q":"c_look"}],"qset":"clerk","scene":{"kind":"scenario","name":"WORLD_HUMAN_STAND_IMPATIENT"}},{"age":{"max":40,"min":28},"at":"man","demeanor":"rude","items":["Carrier bag of razor blades and steaks, tags still on"],"key":"man","label":"Man","lines":[{"admit":[{"set":[{"fact":"c_admit","value":"yes"}],"text":"...Alright. I took some stuff. I have got nothing at home."}],"again":[{"text":"I said. I took it."}],"deny":[{"text":"What store?"},{"text":"Never been in it."}],"kind":"cracks","q":"c_store","times":3},{"answers":[{"text":"Shopping. Is that a crime now?"}],"q":"c_bag"},{"fact":"c_admit","kind":"iffact","no":[{"text":"Threw it away."}],"q":"c_receipt","yes":[{"text":"No. You know I have not."}]}],"pockets":["Bus ticket"],"questions":[{"id":"c_store","label":"Were you in the store on the corner just now?","press":true,"stress":true},{"id":"c_bag","label":"What's in the bag?","stress":true},{"id":"c_receipt","label":"Have you got a receipt?","needs":[{"fact":"c_way","value":""}]}],"scene":{"kind":"scenario","name":"WORLD_HUMAN_SMOKING"},"secret":"nervous","sex":"male"}],"presets":[{"chance":30,"kind":"bolt","line":"I'm not going back inside!","who":"man"}],"rules":[{"actions":[{"id":"clerk","kind":"done"}],"when":{"event":"ask","q":"c_what","who":"clerk"}},{"actions":[{"id":"find","kind":"reveal"},{"fact":"c_way","kind":"give","value":"north","who":"man"},{"kind":"dispatch","text":"Clerk says he went north on foot. Grey hoodie, carrier bag."}],"when":{"event":"fact","fact":"c_way"}},{"actions":[{"id":"find","kind":"done"},{"id":"decide","kind":"reveal"}],"when":{"event":"contact","who":"man"}},{"actions":[{"kind":"say","text":"Officer! In here! He went that way!","who":"clerk"}],"when":{"event":"near","m":25,"who":"clerk"}},{"actions":[{"kind":"dispatch","text":"The clerk is still waiting for a unit."}],"ifs":[{"kind":"notdone","objective":"clerk"}],"when":{"event":"timer","s":600}},{"actions":[{"kind":"note","text":"Recovered: dropped razor blades, tagged."}],"when":{"clue":"bag","event":"inspect"}},{"actions":[{"kind":"note","text":"The suspect admitted the theft."}],"when":{"event":"fact","fact":"c_admit","who":"man"}}],"weight":3},{"ending":{"decide":"decide","heard":"clerk","lines":{"arrested":"Shoplifting report: {name} arrested.","released":"Shoplifting report: {name} had a receipt. A self-checkout fault, no offence."},"mode":"subject","subject":"man"},"id":"mistake","people":[{"at":"clerk","demeanor":"chatty","key":"clerk","label":"Clerk","lines":[{"answers":[{"text":"A man filled his jacket with stuff off the shelves and walked straight out."}],"q":"c_what"},{"answers":[{"set":[{"fact":"c_way","value":"north"}],"text":"That way. North. He had a bag, and I did not see him pay."}],"q":"c_way"},{"answers":[{"text":"Grey hoodie. Thirties. Carrier bag."}],"q":"c_look"}],"qset":"clerk","scene":{"kind":"scenario","name":"WORLD_HUMAN_STAND_IMPATIENT"}},{"age":{"max":40,"min":28},"at":"man","demeanor":"polite","key":"man","label":"Man","lines":[{"answers":[{"text":"Yes, I just bought my dinner. Why?"}],"q":"c_store"},{"answers":[{"text":"Steak and razors. Here, look."}],"q":"c_bag"},{"answers":[{"set":[{"fact":"c_paid","value":"yes"}],"text":"Here. Paid at the self-checkout, it was not working properly."}],"q":"c_receipt"}],"pockets":["Receipt from the corner store, five minutes ago"],"questions":[{"id":"c_store","label":"Were you in the store on the corner just now?","press":true,"stress":true},{"id":"c_bag","label":"What's in the bag?","stress":true},{"id":"c_receipt","label":"Have you got a receipt?","needs":[{"fact":"c_way","value":""}]}],"scene":{"anim":"idle_b","dict":"amb@world_human_hang_out_street@male_b@idle_a","kind":"anim"},"secret":"clean","sex":"male"}],"rules":[{"actions":[{"id":"clerk","kind":"done"}],"when":{"event":"ask","q":"c_what","who":"clerk"}},{"actions":[{"id":"find","kind":"reveal"},{"fact":"c_way","kind":"give","value":"north","who":"man"},{"kind":"dispatch","text":"Clerk says he went north on foot. Grey hoodie, carrier bag."}],"when":{"event":"fact","fact":"c_way"}},{"actions":[{"id":"find","kind":"done"},{"id":"decide","kind":"reveal"}],"when":{"event":"contact","who":"man"}},{"actions":[{"kind":"say","text":"Officer! In here! He went that way!","who":"clerk"}],"when":{"event":"near","m":25,"who":"clerk"}},{"actions":[{"kind":"dispatch","text":"The clerk is still waiting for a unit."}],"ifs":[{"kind":"notdone","objective":"clerk"}],"when":{"event":"timer","s":600}},{"actions":[{"kind":"note","text":"He had a receipt: paid at the self-checkout."},{"kind":"wait","s":3},{"kind":"say","text":"Can I go now?","who":"man"}],"when":{"event":"fact","fact":"c_paid","who":"man"}}],"weight":2}],"v":1,"weight":1}
]=]
-- c3rcc:hash 7a802f86
--[[
    c3r callout: SHOPLIFTING.
    Made with LWK Callout Creator, BY LWK DEVELOPMENT. Stories: theft (weight 3), mistake (weight 2).
    Points per location: place them in the creator, or with /c3rplace shoplift in game.
]]

local Q_CLERK = {
    { id = 'c_what', label = 'What happened?' },
    { id = 'c_way', label = 'Which way did he go?' },
    { id = 'c_look', label = 'What did he look like?' },
}
-- Denies it until asked `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n, told = 0, false
    return function()
        if told then return again end
        n = n + 1
        if n < times then return deny end
        told = true
        return admit
    end
end

-- Someone now knows a fact (from what someone else said): the questions it opens are theirs to be asked.
local function give(c, key, fact, v)
    local o = c:who(key)
    if not o then return end
    o.facts[fact] = v
    c:questions(key)
end

-- Runs fn after s seconds of the call (the tick's clock).
local function later(c, s, fn)
    local at
    c:on('tick', function(now)
        at = at or now + s
        if at and now >= at then at = math.huge fn() end
    end)
end

--[=[ How it ends. e = { mode, subject, heard, decide, left, lines }:
      subject  ends once the person it's about is dealt with: taken in, ticketed, warned, let go, got away, gone or dead
      arrests  ends once everyone arrested has been taken in
      heard    ends once objective e.heard is done and every unit has left the scene
     Whatever the mode, with e.heard done and every unit gone for e.left s, it ends too. Anyone cuffed has to be taken
     in first. lines[outcome]: the MDT summary ({name}: the person it's about, {street}: the call's street). ]=]
local function resolve(c, e)
    local out, taken, away_for, done = {}, {}, 0, false
    local LET_GO = { released = true, cited = true, warning = true, fled = true, dead = true, gone = true }
    local DEFAULT = {
        arrested = '{name} was arrested.', cited = '{name} was given a ticket.', warning = '{name} was given a warning.',
        released = '{name} was spoken to and let go.', fled = '{name} ran and got away.', dead = '{name} died at the scene.',
        gone = '{name} left the scene.', left = 'Units cleared the scene.', none = 'Units cleared the scene.',
    }
    local function line(k)
        local t = (e.lines and e.lines[k] ~= '' and e.lines[k]) or DEFAULT[k] or DEFAULT.none
        return (t:gsub('{name}', function() return e.subject and c:name(e.subject) or 'Nobody' end)
                 :gsub('{street}', function() return c:street() or '' end))
    end
    local function waiting()
        for k, v in pairs(out) do if v == 'arrested' and not taken[k] then return true end end
        return false
    end
    local function check(left)
        if done or waiting() or c:talking() then return end
        local s, why = e.subject, nil
        if left then why = 'left'
        elseif e.mode == 'subject' and s and (taken[s] or LET_GO[out[s]]) then why = taken[s] and 'arrested' or out[s]
        elseif e.mode == 'arrests' and next(taken) then why = 'arrested' end
        if not why then return end
        done = true
        if e.decide then c:done(e.decide) end
        local main = why == 'left' and line('left') or line(why)
        local also, more = {}, {}
        for k, v in pairs(out) do
            if k ~= s or why == 'left' then
                if v == 'arrested' and (k ~= s or why == 'left') then also[#also + 1] = c:name(k)
                elseif v == 'cited' then more[#more + 1] = (' %s was given a ticket.'):format(c:name(k))
                elseif v == 'warning' then more[#more + 1] = (' %s was given a warning.'):format(c:name(k)) end
            end
        end
        table.sort(also)
        table.sort(more)
        c:finish(main .. (also[1] and (' Arrested: ' .. table.concat(also, ', ') .. '.') or '') .. table.concat(more))
    end
    c:on('act', function(key, action)
        local o = c:who(key)
        if action == 'cuff' and o and o.cuffed then
            out[key] = 'arrested'
            c:custody(key)
        elseif action == 'uncuff' and out[key] == 'arrested' then
            out[key] = nil
            c:hide('custody:' .. key)
        elseif (action == 'cite' or action == 'warn') and out[key] ~= 'arrested' then
            out[key] = action == 'cite' and 'cited' or 'warning'
        end
        check()
    end)
    c:on('custody', function(key) taken[key] = true check() end)
    c:on('dead', function(key)
        out[key] = 'dead'
        c:hide('custody:' .. key)
        check()
    end)
    c:on('gone', function(key)
        if out[key] == 'arrested' then taken[key] = true elseif not out[key] then out[key] = 'gone' end
        check()
    end)
    c:on('contact_ended', function(key, outcome)
        if outcome == 'fled' then out[key] = 'fled'
        elseif (outcome == 'released' or outcome == 'cited' or outcome == 'warning') and out[key] ~= 'arrested' then out[key] = outcome end
        check()
    end)
    c:on('tick', function()
        check()
        local heard = e.heard and c:is_done(e.heard)
        if heard and not waiting() and not c:near(nil, 130.0) and not (e.subject and c:near(e.subject, 130.0)) and not c:talking() then
            away_for = away_for + 1
            if away_for >= (e.left or 15) then check(true) end
        else
            away_for = 0
        end
    end)
end

-- Asked for their ID, they may run for it (`chance` in 100), a moment later.
local function bolt(c, key, o)
    local asked, going = false, false
    c:on('act', function(who, action)
        if who ~= key or action ~= 'licence' or asked then return end
        asked = true
        going = math.random(100) <= (o.chance or 50)
    end)
    c:on('tick', function()
        if not going then return end
        going = false
        local who = c:who(key)
        if c:talking(key) and who and not who.cuffed then
            if o.line then c:say(key, o.line) end
            c:task(key, 'flee')
        end
    end)
end


-- The opening card: the same in every story, so it never gives the story away.
local function card(c)
    c:objective('clerk', 'Talk to the clerk', { hint = 'At the store.', blip = 'clerk' })
    c:objective('find', 'Find the man', { hidden = true, blip = 'man' })
    c:objective('decide', 'Deal with him: arrest, ticket or warn, or let him go', { who = 'all', hidden = true, blip = 'man' })
end

Callout({
    id = 'shoplift',
    name = 'Shoplifting',
    priority = 3,
    weight = 1,
    enabled = false,
    reports = { 'Store clerk reports a man left without paying.', 'Caller says someone has just walked out of the shop with stolen goods.' },
    points = {
        { 'clerk', 'The clerk, at the store doorway.' },
        { 'man', 'Up the street: where the man is found.' },
        { 'bag', 'A dropped carrier bag on the pavement between them.', optional = true },
    },
    -- c3rcc:locations
    locations = {
        { street = 'Innocence Blvd', at = vector3(25.71, -1347.00, 29.50), points = {
            clerk = vector4(25.71, -1347.00, 29.50, 270.0),
            man = vector4(68.30, -1390.40, 29.36, 180.0),
            bag = vector4(45.10, -1365.20, 29.30, 0.0),
        } },
    },
    -- c3rcc:end
    stories = {
    theft = { weight = 3, setup = function(c)
        c:person('clerk', {
            at = 'clerk',
            label = 'Clerk',
            demeanor = 'chatty',
            scene = 'WORLD_HUMAN_STAND_IMPATIENT',
            questions = Q_CLERK,
            lines = {
                c_what = { 'A man filled his jacket with stuff off the shelves and walked straight out.' },
                c_way = { { 'North. Up the street. He was not even running.', set = { c_way = 'north' } } },
                c_look = { 'Grey hoodie. Thirties. Carrier bag.' },
            },
        })
        c:person('man', {
            at = 'man',
            label = 'Man',
            male = true,
            secret = 'nervous',
            demeanor = 'rude',
            age = { 28, 40 },
            scene = 'WORLD_HUMAN_SMOKING',
            items = { 'Carrier bag of razor blades and steaks, tags still on' },
            pockets = { 'Bus ticket' },
            questions = {
                { id = 'c_store', label = 'Were you in the store on the corner just now?', press = true, stress = true },
                { id = 'c_bag', label = 'What\'s in the bag?', stress = true },
                { id = 'c_receipt', label = 'Have you got a receipt?', needs = { c_way = true } },
            },
            lines = {
                c_store = cracks(3, { 'What store?', 'Never been in it.' }, { { '...Alright. I took some stuff. I have got nothing at home.', set = { c_admit = 'yes' } } }, { 'I said. I took it.' }),
                c_bag = { 'Shopping. Is that a crime now?' },
                c_receipt = function(o) local v = o.facts['c_admit'] if v ~= nil and v ~= false then return { 'No. You know I have not.' } end return { 'Threw it away.' } end,
            },
        })
        c:clue('bag', { at = 'bag', label = 'Dropped bag', prop = 'prop_cs_cardbox_01', text = 'Two packs of razor blades, security tags still on, in the gutter.' })
        card(c)
        local r1 = false
        c:on('act', function(key, action, q, src)
            if not (not r1 and action == 'ask' and q == 'c_what' and key == 'clerk') then return end
            r1 = true
            c:done('clerk')
        end)
        local r2 = false
        c:on('fact', function(key, fact, value, src)
            if not (not r2 and fact == 'c_way') then return end
            r2 = true
            c:reveal('find')
            give(c, 'man', 'c_way', 'north')
            c:dispatch('Clerk says he went north on foot. Grey hoodie, carrier bag.')
        end)
        local r3 = false
        c:on('contact', function(key, src)
            if not (not r3 and key == 'man') then return end
            r3 = true
            c:done('find')
            c:reveal('decide')
        end)
        local r4 = false
        c:on('tick', function(now)
            local key = 'clerk'
            local src = nil
            if not (not r4 and c:near('clerk', 25.0)) then return end
            r4 = true
            c:say('clerk', 'Officer! In here! He went that way!')
        end)
        local r5 = false
        local r5_at
        c:on('tick', function(now)
            local key = nil
            local src = nil
            r5_at = r5_at or now + 600
            if not (not r5 and not c:is_done('clerk') and now >= r5_at) then return end
            r5 = true
            c:dispatch('The clerk is still waiting for a unit.')
        end)
        local r6 = false
        c:on('inspect', function(clue, src)
            local key = nil
            if not (not r6 and clue == 'bag') then return end
            r6 = true
            c:note('Recovered: dropped razor blades, tagged.')
        end)
        local r7 = false
        c:on('fact', function(key, fact, value, src)
            if not (not r7 and key == 'man' and fact == 'c_admit') then return end
            r7 = true
            c:note('The suspect admitted the theft.')
        end)
        bolt(c, 'man', { chance = 30, line = 'I\'m not going back inside!' })
        resolve(c, { mode = 'subject', subject = 'man', heard = 'clerk', decide = 'decide', lines = {
            arrested = 'Shoplifting: {name} arrested.',
            cited = 'Shoplifting: {name} was given a ticket.',
            released = 'Shoplifting: {name} was spoken to and let go.',
            left = 'Shoplifting: the clerk was heard, nobody was found.',
        } })
    end },
    mistake = { weight = 2, setup = function(c)
        c:person('clerk', {
            at = 'clerk',
            label = 'Clerk',
            demeanor = 'chatty',
            scene = 'WORLD_HUMAN_STAND_IMPATIENT',
            questions = Q_CLERK,
            lines = {
                c_what = { 'A man filled his jacket with stuff off the shelves and walked straight out.' },
                c_way = { { 'That way. North. He had a bag, and I did not see him pay.', set = { c_way = 'north' } } },
                c_look = { 'Grey hoodie. Thirties. Carrier bag.' },
            },
        })
        c:person('man', {
            at = 'man',
            label = 'Man',
            male = true,
            secret = 'clean',
            demeanor = 'polite',
            age = { 28, 40 },
            scene = { 'amb@world_human_hang_out_street@male_b@idle_a', 'idle_b' },
            pockets = { 'Receipt from the corner store, five minutes ago' },
            questions = {
                { id = 'c_store', label = 'Were you in the store on the corner just now?', press = true, stress = true },
                { id = 'c_bag', label = 'What\'s in the bag?', stress = true },
                { id = 'c_receipt', label = 'Have you got a receipt?', needs = { c_way = true } },
            },
            lines = {
                c_store = { 'Yes, I just bought my dinner. Why?' },
                c_bag = { 'Steak and razors. Here, look.' },
                c_receipt = { { 'Here. Paid at the self-checkout, it was not working properly.', set = { c_paid = 'yes' } } },
            },
        })
        card(c)
        local r1 = false
        c:on('act', function(key, action, q, src)
            if not (not r1 and action == 'ask' and q == 'c_what' and key == 'clerk') then return end
            r1 = true
            c:done('clerk')
        end)
        local r2 = false
        c:on('fact', function(key, fact, value, src)
            if not (not r2 and fact == 'c_way') then return end
            r2 = true
            c:reveal('find')
            give(c, 'man', 'c_way', 'north')
            c:dispatch('Clerk says he went north on foot. Grey hoodie, carrier bag.')
        end)
        local r3 = false
        c:on('contact', function(key, src)
            if not (not r3 and key == 'man') then return end
            r3 = true
            c:done('find')
            c:reveal('decide')
        end)
        local r4 = false
        c:on('tick', function(now)
            local key = 'clerk'
            local src = nil
            if not (not r4 and c:near('clerk', 25.0)) then return end
            r4 = true
            c:say('clerk', 'Officer! In here! He went that way!')
        end)
        local r5 = false
        local r5_at
        c:on('tick', function(now)
            local key = nil
            local src = nil
            r5_at = r5_at or now + 600
            if not (not r5 and not c:is_done('clerk') and now >= r5_at) then return end
            r5 = true
            c:dispatch('The clerk is still waiting for a unit.')
        end)
        local r6 = false
        c:on('fact', function(key, fact, value, src)
            if not (not r6 and key == 'man' and fact == 'c_paid') then return end
            r6 = true
            c:note('He had a receipt: paid at the self-checkout.')
            later(c, 3, function()
                c:say('man', 'Can I go now?')
            end)
        end)
        resolve(c, { mode = 'subject', subject = 'man', heard = 'clerk', decide = 'decide', lines = {
            arrested = 'Shoplifting report: {name} arrested.',
            released = 'Shoplifting report: {name} had a receipt. A self-checkout fault, no offence.',
        } })
    end },
    },
})
