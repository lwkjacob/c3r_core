--[[
    lwk_calloutcreator: the generator. An editor's callout (doc, plain data from the NUI) -> a c3r callout file in plain
    SDK Lua, the same as a hand-written one in c3r/callouts/, needing nothing but c3r to run. Pure Lua, no natives.

    The file starts with the doc itself (JSON in a long comment), so the creator can open it again, and a hash of the
    code under it: if someone edits the code by hand, the hash no longer matches and the creator says so before it
    overwrites their changes. The locations are left out of the hash (between the c3rcc:locations / c3rcc:end lines),
    because c3r's /c3rplace writes new ones into the file.

    Gen.check(doc)  -> errors { 'text' }   (anything the client sent that can't be trusted or can't work)
    Gen.lua(doc)    -> text                (only after check passed)
    Gen.read(text)  -> doc | nil, edited   (edited: the code was changed outside the creator)
]]

Gen = {}

local encode = function(t) return json.encode(t) end
local decode = function(s) return json.decode(s) end
function Gen.json(enc, dec) encode, decode = enc, dec end -- (tools/test.lua: its own JSON)

-- ─── what's allowed ─────────────────────────────────────────────────────────────────────────────────────────

Gen.SECRETS = { clean = true, nervous = true, drunk = true, drugs = true, warrant = true, unlicensed = true, suspended = true }
Gen.DEMEANORS = { polite = true, nervous = true, rude = true, chatty = true }
Gen.DAMAGE = { dent = true, rear = true, side = true, front = true, wreck = true }
Gen.TASKS = { flee = 'none', surrender = 'none', wander = 'none', scene = 'none', go = 'point', aim = 'person', hold = 'person',
              brawl = 'person', spray = 'point', shoot = 'point?', drive = 'drive' }
-- events a rule can start on, and what each one says (the names c3r passes them in)
Gen.EVENTS = {
    build = {}, arrive = { 'src' }, leave = { 'src' },
    contact = { 'who', 'src' }, ask = { 'who', 'q', 'src' }, act = { 'who', 'action', 'arg', 'src' },
    fact = { 'who', 'fact', 'value', 'src' }, contact_ended = { 'who', 'outcome', 'src' }, inspect = { 'clue', 'src' },
    custody = { 'who', 'how', 'src' }, aid = { 'who', 'what', 'src' }, gone = { 'who' }, dead = { 'who' },
    fired = { 'who' }, aimed = { 'who', 'src' }, hail = { 'who', 'src' }, parked = { 'who' },
    dragged = { 'clue', 'clear', 'src' }, service = { 'kind', 'src' }, towed = { 'car', 'src' }, tow = { 'car', 'stage', 'src' },
    plate = { 'car', 'src' }, stunned = { 'who' }, near = {}, timer = {},
}
Gen.ACTS = { licence = true, frisk = true, search = true, breath = true, cuff = true, uncuff = true, cite = true, warn = true,
             release = true, escort = true, seat = true }
Gen.OUTCOMES = { released = true, cited = true, warning = true, arrested = true, fled = true, cancelled = true }
Gen.ENDS = { arrested = 1, cited = 1, warning = 1, released = 1, fled = 1, dead = 1, gone = 1, left = 1, none = 1 }

local function ident(s) return type(s) == 'string' and #s <= 40 and s:match('^[%a_][%w_]*$') ~= nil end
local function fact(s) return type(s) == 'string' and #s <= 40 and s:match('^c_[%w_]+$') ~= nil end
local function text(s, max) return type(s) == 'string' and #s <= (max or 600) end
local function model(s) return type(s) == 'string' and #s <= 60 and s:match('^[%w_%-@]+$') ~= nil end
local function list(t) return type(t) == 'table' and t or {} end
local function num(v, lo, hi) v = tonumber(v) return v and v == v and v >= lo and v <= hi and v or nil end
local function on(v) return v == true end
local function filled(t) -- (the editor leaves an empty answer ready to type into: those say nothing)
    local o = {}
    for _, a in ipairs(type(t) == 'table' and t or {}) do if type(a.text) == 'string' and a.text:match('%S') then o[#o + 1] = a end end
    return o
end

-- ─── checking a doc ─────────────────────────────────────────────────────────────────────────────────────────

function Gen.check(doc)
    local errs = {}
    local function bad(fmt, ...) if #errs < 40 then errs[#errs + 1] = fmt:format(...) end end
    if type(doc) ~= 'table' then return { 'nothing to save' } end
    if not ident(doc.id) or doc.id:match('^c_') then bad('The callout id must be letters, numbers and _ (and not start c_).') end
    if not text(doc.name, 60) or doc.name == '' then bad('The callout needs a name.') end
    if doc.alert and not text(doc.alert, 60) then bad('The alert line is too long.') end
    if not list(doc.reports)[1] then bad('Add at least one report: what the caller says.') end
    for i, r in ipairs(list(doc.reports)) do if not text(r, 300) or r == '' then bad('Report %d is empty or too long.', i) end end
    local points = {}
    for i, p in ipairs(list(doc.points)) do
        if not ident(p.name) then bad('Point %d needs a name: letters, numbers and _.', i)
        elseif points[p.name] then bad('Two points are called %s.', p.name) end
        if not text(p.text, 200) then bad('Point %s: the description is too long.', tostring(p.name)) end
        if i == 1 and on(p.optional) then bad('The first point (where the call is) cannot be optional.') end
        points[p.name or ''] = true
    end
    if not list(doc.points)[1] then bad('Add at least one point: the first is where the call is.') end
    for i, l in ipairs(list(doc.locations)) do
        if not text(l.street, 40) then bad('Location %d: the street name is too long.', i) end
        for k, p in pairs(list(l.points)) do
            if not points[k] then bad('Location %d has a point "%s" the callout does not list.', i, tostring(k)) end
            if type(p) ~= 'table' or not (num(p.x, -99999, 99999) and num(p.y, -99999, 99999) and num(p.z, -9999, 9999) and num(p.h or 0, -720, 720)) then
                bad('Location %d: point %s is not a position.', i, tostring(k))
            end
        end
        local first = list(doc.points)[1]
        if first and not list(l.points)[first.name] then bad('Location %d is missing %s, where the call is.', i, tostring(first.name)) end
    end
    local function answers(where, t)
        for _, a in ipairs(list(t)) do
            if not text(a.text, 400) then bad('%s: an answer is too long.', where) end
            for _, s in ipairs(list(a.set)) do
                if not fact(s.fact) then bad('%s: facts start with c_ and are letters, numbers and _ ("%s").', where, tostring(s.fact)) end
                if not text(s.value, 60) then bad('%s: a fact value is too long.', where) end
            end
        end
    end
    local function questions(where, qs)
        for _, q in ipairs(list(qs)) do
            if not fact(q.id) then bad('%s: question ids start with c_ ("%s").', where, tostring(q.id)) end
            if not text(q.label, 120) or q.label == '' then bad('%s: question %s needs its words.', where, tostring(q.id)) end
            for _, n in ipairs(list(q.needs)) do
                if not fact(n.fact) then bad('%s: question %s needs a fact that starts with c_.', where, tostring(q.id)) end
            end
        end
    end
    local qsets = {}
    for _, s in ipairs(list(doc.qsets)) do
        if not ident(s.id) then bad('A question list needs a name: letters, numbers and _.') end
        qsets[s.id or ''] = true
        questions('Question list ' .. tostring(s.id), s.questions)
    end
    local function objectives(where, os, ids)
        for _, o in ipairs(list(os)) do
            if not ident(o.id) then bad('%s: an objective needs an id.', where)
            elseif ids[o.id] then bad('%s: two objectives are called %s.', where, o.id) end
            ids[o.id or ''] = true
            if not text(o.text, 120) or o.text == '' then bad('%s: objective %s needs its words.', where, tostring(o.id)) end
            if o.hint and not text(o.hint, 200) then bad('%s: objective %s: the hint is too long.', where, tostring(o.id)) end
            for _, a in ipairs(list(o.after)) do if not ident(a) then bad('%s: objective %s: "after" is not an objective.', where, tostring(o.id)) end end
            for _, b in ipairs(list(o.blip)) do if not ident(b) then bad('%s: objective %s marks something that is not there.', where, tostring(o.id)) end end
        end
    end
    local card = {}
    objectives('The card', doc.card, card)
    local stories = {}
    if not list(doc.stories)[1] then bad('Add at least one story.') end
    for si, s in ipairs(list(doc.stories)) do
        local w = 'Story ' .. tostring(s.id or si)
        if not ident(s.id) then bad('Story %d needs a name: letters, numbers and _.', si)
        elseif stories[s.id] then bad('Two stories are called %s.', s.id) end
        stories[s.id or ''] = true
        if not num(s.weight or 1, 0, 100) then bad('%s: the weight is 0 to 100.', w) end
        for _, n in ipairs(list(s.needs)) do if not points[n] then bad('%s needs a point "%s" the callout does not list.', w, tostring(n)) end end
        local keys = {}
        local function key(k, what)
            if not ident(k) then bad('%s: a %s needs a key: letters, numbers and _.', w, what)
            elseif keys[k] then bad('%s: two things are called %s.', w, k) end
            keys[k or ''] = what
        end
        local function at(where, a)
            if not points[a] then bad('%s: %s is at "%s", which is not one of the points.', w, where, tostring(a)) end
        end
        for _, p in ipairs(list(s.people)) do key(p.key, 'person') end
        for _, v in ipairs(list(s.vehicles)) do key(v.key, 'vehicle') end
        for _, c in ipairs(list(s.clues)) do key(c.key, 'clue') end
        for _, p in ipairs(list(s.people)) do
            local pw = 'person ' .. tostring(p.key)
            at(pw, p.at)
            if not text(p.label, 40) or p.label == '' then bad('%s: %s needs a label (Caller, Man...).', w, pw) end
            if p.model and p.model ~= '' and not model(p.model) then bad('%s: %s: that is not a model name.', w, pw) end
            if p.secret and p.secret ~= '' and not Gen.SECRETS[p.secret] then bad('%s: %s: unknown secret.', w, pw) end
            if p.demeanor and p.demeanor ~= '' and not Gen.DEMEANORS[p.demeanor] then bad('%s: %s: unknown demeanor.', w, pw) end
            if p.weapon and p.weapon ~= '' and not model(p.weapon) then bad('%s: %s: that is not a weapon name.', w, pw) end
            if p.home and p.home ~= '' and p.home ~= 'yes' and not points[p.home] then bad('%s: %s lives on a point that is not there.', w, pw) end
            if p.seated and p.seated ~= '' and keys[p.seated] ~= 'vehicle' then bad('%s: %s sits in a car that is not in this story.', w, pw) end
            if p.qset and p.qset ~= '' and not qsets[p.qset] then bad('%s: %s uses a question list that is not there.', w, pw) end
            local sc = p.scene or {}
            if sc.kind == 'scenario' and not model(sc.name) then bad('%s: %s: that is not a scenario name.', w, pw) end
            if sc.kind == 'anim' and not (model(sc.dict) and model(sc.anim)) then bad('%s: %s: the animation needs a dictionary and a name.', w, pw) end
            for _, t in ipairs(list(p.items)) do if not text(t, 80) then bad('%s: %s: an item is too long.', w, pw) end end
            for _, t in ipairs(list(p.pockets)) do if not text(t, 80) then bad('%s: %s: a pocket item is too long.', w, pw) end end
            if p.vitals and not text(p.vitals, 200) then bad('%s: %s: vitals is too long.', w, pw) end
            for _, f in ipairs(list(p.facts)) do if not fact(f.fact) or not text(f.value, 60) then bad('%s: %s: facts start with c_.', w, pw) end end
            questions(w .. ', ' .. pw, p.questions)
            for _, l in ipairs(list(p.lines)) do
                if not ident(l.q) then bad('%s: %s: an answer is for a question that is not there.', w, pw) end
                if l.kind == 'cracks' then
                    if not num(l.times or 2, 1, 20) then bad('%s: %s: "gives in after" is 1 to 20 times.', w, pw) end
                    answers(w .. ', ' .. pw, l.deny) answers(w .. ', ' .. pw, l.admit) answers(w .. ', ' .. pw, l.again)
                    if not filled(l.deny)[1] or not filled(l.admit)[1] then bad('%s: %s: a denial needs what they deny and what they admit.', w, pw) end
                elseif l.kind == 'iffact' then
                    if not fact(l.fact) then bad('%s: %s: an answer that depends on a fact needs one that starts with c_.', w, pw) end
                    answers(w .. ', ' .. pw, l.yes) answers(w .. ', ' .. pw, l.no)
                else
                    answers(w .. ', ' .. pw, l.answers)
                end
            end
        end
        for _, v in ipairs(list(s.vehicles)) do
            local vw = 'vehicle ' .. tostring(v.key)
            at(vw, v.at)
            if not model(v.model) then bad('%s: %s needs a model name.', w, vw) end
            for _, f in ipairs({ 'make', 'name', 'color', 'label' }) do if v[f] and not text(v[f], 40) then bad('%s: %s: %s is too long.', w, vw, f) end end
            if v.owner and v.owner ~= '' and keys[v.owner] ~= 'person' then bad('%s: %s belongs to someone not in this story.', w, vw) end
            if v.damage and v.damage ~= '' and not Gen.DAMAGE[v.damage] then bad('%s: %s: unknown damage.', w, vw) end
            if v.paint and v.paint ~= '' and not num(v.paint, 0, 160) then bad('%s: %s: paint is a colour number, 0 to 160.', w, vw) end
        end
        for _, c in ipairs(list(s.clues)) do
            local cw = 'clue ' .. tostring(c.key)
            if c.on and c.on ~= '' then
                if keys[c.on] ~= 'vehicle' and keys[c.on] ~= 'person' then bad('%s: %s is on something not in this story.', w, cw) end
            else at(cw, c.at) end
            if not text(c.label, 60) or c.label == '' or not text(c.text, 600) or c.text == '' then bad('%s: %s needs a label and what it shows.', w, cw) end
            if c.prop and c.prop ~= '' and not model(c.prop) then bad('%s: %s: that is not a prop name.', w, cw) end
            if c.scatter and c.scatter.model and c.scatter.model ~= '' and not model(c.scatter.model) then bad('%s: %s: the scatter prop is not a prop name.', w, cw) end
        end
        local ids = {}
        for k in pairs(card) do ids[k] = true end
        objectives(w, s.objectives, ids)
        local function thing(k, what) return k ~= nil and k ~= '' and keys[k] == what end
        for ri, r in ipairs(list(s.rules)) do
            local rw = ('%s, rule %d'):format(w, ri)
            local wh = r.when or {}
            if not Gen.EVENTS[wh.event] then bad('%s: pick what it happens on.', rw) end
            for _, f in ipairs({ 'who', 'clue', 'car' }) do if wh[f] and wh[f] ~= '' and not keys[wh[f]] then bad('%s: %s is not in this story.', rw, tostring(wh[f])) end end
            if wh.event == 'ask' and not ident(wh.q) then bad('%s: which question?', rw) end
            if wh.event == 'fact' and wh.fact and wh.fact ~= '' and not fact(wh.fact) then bad('%s: facts start with c_.', rw) end
            if wh.event == 'near' and not num(wh.m or 30, 1, 500) then bad('%s: how near is 1 to 500 m.', rw) end
            if wh.event == 'timer' and not num(wh.s or 60, 1, 3600) then bad('%s: the time is 1 to 3600 s.', rw) end
            for _, f in ipairs({ 'action', 'outcome', 'how', 'what', 'stage', 'kind', 'value' }) do
                if wh[f] and not text(wh[f], 60) then bad('%s: %s is too long.', rw, f) end
            end
            for _, c in ipairs(list(r.ifs)) do
                if c.who and c.who ~= '' and not keys[c.who] then bad('%s: a condition is about %s, not in this story.', rw, tostring(c.who)) end
                if (c.kind == 'fact' or c.kind == 'nofact') and not fact(c.fact) then bad('%s: a condition needs a fact that starts with c_.', rw) end
                if (c.kind == 'flag' or c.kind == 'noflag') and not ident(c.flag) then bad('%s: a condition needs a flag name.', rw) end
                if (c.kind == 'done' or c.kind == 'notdone') and not ident(c.objective) then bad('%s: a condition needs an objective.', rw) end
                if c.kind == 'chance' and not num(c.p or 50, 0, 100) then bad('%s: a chance is 0 to 100.', rw) end
                if c.kind == 'near' and not num(c.m or 30, 1, 500) then bad('%s: how near is 1 to 500 m.', rw) end
                if c.kind == 'story' and not ident(c.story) then bad('%s: which story?', rw) end
                if c.value and not text(c.value, 60) then bad('%s: a value is too long.', rw) end
            end
            if not list(r.actions)[1] then bad('%s: add something for it to do.', rw) end
            for _, a in ipairs(list(r.actions)) do
                local k = a.kind
                if k == 'task' then
                    local need = Gen.TASKS[a.task]
                    if not need then bad('%s: unknown thing to do.', rw)
                    elseif need == 'point' and not points[a.point] then bad('%s: %s needs a point.', rw, a.task)
                    elseif need == 'person' and not thing(a.other, 'person') then bad('%s: %s needs someone in this story.', rw, a.task)
                    elseif need == 'drive' and not thing(a.car, 'vehicle') then bad('%s: drive needs one of the story\'s cars.', rw)
                    elseif (need == 'drive' or need == 'point?') and a.point and a.point ~= '' and not points[a.point] then bad('%s: that point is not there.', rw) end
                end
                for _, f in ipairs({ 'who' }) do
                    if a[f] and a[f] ~= '' and keys[a[f]] ~= 'person' then bad('%s: %s is not someone in this story.', rw, tostring(a[f])) end
                end
                if a.car and a.car ~= '' and keys[a.car] ~= 'vehicle' then bad('%s: %s is not one of the story\'s cars.', rw, tostring(a.car)) end
                if a.clue and a.clue ~= '' and keys[a.clue] ~= 'clue' then bad('%s: %s is not one of the story\'s clues.', rw, tostring(a.clue)) end
                if (k == 'done' or k == 'reveal' or k == 'hide' or k == 'blip') and not ident(a.id) then bad('%s: which objective?', rw) end
                if k == 'give' and not fact(a.fact) then bad('%s: facts start with c_.', rw) end
                if (k == 'flag') and not ident(a.flag) then bad('%s: a flag needs a name.', rw) end
                if k == 'bang' and not (model(a.weapon) and points[a.point]) then bad('%s: a bang needs a weapon and a point.', rw) end
                for _, f in ipairs({ 'text', 'title', 'value', 'vitals' }) do
                    if a[f] and not text(a[f], 400) then bad('%s: %s is too long.', rw, f) end
                end
                if k == 'blip' then for _, b in ipairs(list(a.keys)) do if not keys[b] then bad('%s: it marks %s, not in this story.', rw, tostring(b)) end end end
                if not ({ done = 1, reveal = 1, hide = 1, blip = 1, say = 1, dispatch = 1, note = 1, tell = 1, task = 1, give = 1, flag = 1,
                          custody = 1, warrant = 1, file = 1, collapse = 1, die = 1, remove = 1, hangup = 1, patient = 1, fare = 1,
                          bang = 1, clear = 1, finish = 1, wait = 1 })[k] then
                    bad('%s: unknown thing to do.', rw)
                end
                if k == 'wait' and not num(a.s or 1, 1, 600) then bad('%s: wait 1 to 600 s.', rw) end
            end
        end
        for xi, x in ipairs(list(s.presets)) do
            local xw = ('%s, preset %d'):format(w, xi)
            if not ({ brawl = 1, standoff = 1, shootout = 1, spray = 1, bolt = 1 })[x.kind] then bad('%s: unknown preset.', xw) end
            if not thing(x.who, 'person') then bad('%s: who is it about?', xw) end
            if (x.kind == 'brawl' or ((x.kind == 'standoff') and x.other and x.other ~= '')) and not thing(x.other, 'person') then bad('%s: who with?', xw) end
            if x.kind == 'spray' and not points[x.point] then bad('%s: spraying needs a point to fire over.', xw) end
            if x.kind == 'shootout' and x.point and x.point ~= '' and not points[x.point] then bad('%s: that point is not there.', xw) end
            if x.objective and x.objective ~= '' and not ident(x.objective) then bad('%s: which objective?', xw) end
            if not num(x.chance or 50, 0, 100) then bad('%s: a chance is 0 to 100.', xw) end
            for _, f in ipairs({ 'line', 'defy' }) do if x[f] and not text(x[f], 200) then bad('%s: a line is too long.', xw) end end
        end
        local e = s.ending or {}
        if not ({ subject = 1, arrests = 1, heard = 1 })[e.mode or 'subject'] then bad('%s: pick how it ends.', w) end
        if e.subject and e.subject ~= '' and not thing(e.subject, 'person') then bad('%s: the ending is about someone not in this story.', w) end
        if (e.mode or 'subject') == 'subject' and not thing(e.subject, 'person') then bad('%s: the ending needs who it is about.', w) end
        if e.mode == 'heard' and not ident(e.heard) then bad('%s: the ending needs the objective that means they were heard.', w) end
        if e.decide and e.decide ~= '' and not ident(e.decide) then bad('%s: the ending marks an objective that is not there.', w) end
        for k, v in pairs(list(e.lines)) do
            if not Gen.ENDS[k] or not text(v, 300) then bad('%s: an MDT summary is too long.', w) end
        end
    end
    return errs
end

-- ─── writing Lua ────────────────────────────────────────────────────────────────────────────────────────────

-- A string as a Lua literal: nothing in it can end the string or run.
local function q(s)
    return "'" .. tostring(s):gsub("[%c\\']", function(ch)
        if ch == '\n' then return '\\n' end
        if ch == "'" or ch == '\\' then return '\\' .. ch end
        return ('\\%03d'):format(ch:byte())
    end) .. "'"
end
Gen.q = q

local function n(v) -- a number, as it reads best
    v = tonumber(v) or 0
    return math.type and math.type(v) == 'integer' and tostring(v) or (v == math.floor(v) and ('%d'):format(v) or ('%.2f'):format(v))
end

local function fl(v) return ('%.1f'):format(tonumber(v) or 0) end -- (a distance: always a float)

local function strs(t)
    local o = {}
    for _, s in ipairs(list(t)) do o[#o + 1] = q(s) end
    return '{ ' .. table.concat(o, ', ') .. ' }'
end

local function value(v) -- a fact's value: 'yes' and the like, or true for "any"
    if v == nil or v == '' or v == true then return 'true' end
    return q(v)
end

local function sets(t)
    local o = {}
    for _, s in ipairs(list(t)) do o[#o + 1] = s.fact .. ' = ' .. value(s.value) end
    return '{ ' .. table.concat(o, ', ') .. ' }'
end

local function answer(a)
    if list(a.set)[1] then return '{ ' .. q(a.text) .. ', set = ' .. sets(a.set) .. ' }' end
    return q(a.text)
end

local function answers(t)
    local o = {}
    for _, a in ipairs(filled(t)) do o[#o + 1] = answer(a) end
    return '{ ' .. table.concat(o, ', ') .. ' }'
end

local function question(qn)
    local o = { 'id = ' .. q(qn.id), 'label = ' .. q(qn.label) }
    if list(qn.needs)[1] then o[#o + 1] = 'needs = ' .. sets(qn.needs) end
    if on(qn.press) then o[#o + 1] = 'press = true' end
    if on(qn.stress) then o[#o + 1] = 'stress = true' end
    return '{ ' .. table.concat(o, ', ') .. ' }'
end

local function questions(t, indent)
    local o = {}
    for _, qn in ipairs(list(t)) do o[#o + 1] = indent .. '    ' .. question(qn) .. ',' end
    return '{\n' .. table.concat(o, '\n') .. '\n' .. indent .. '}'
end

local function objective(o, indent)
    local opts = {}
    if o.hint and o.hint ~= '' then opts[#opts + 1] = 'hint = ' .. q(o.hint) end
    if o.who == 'all' then opts[#opts + 1] = "who = 'all'" end
    if list(o.after)[1] then opts[#opts + 1] = 'after = ' .. strs(o.after) end
    if on(o.hidden) then opts[#opts + 1] = 'hidden = true' end
    local b = list(o.blip)
    if b[2] then opts[#opts + 1] = 'blip = ' .. strs(b) elseif b[1] then opts[#opts + 1] = 'blip = ' .. q(b[1]) end
    return ('%sc:objective(%s, %s%s)'):format(indent, q(o.id), q(o.text), opts[1] and (', { ' .. table.concat(opts, ', ') .. ' }') or '')
end

-- ─── the helpers a file carries (only the ones it uses) ─────────────────────────────────────────────────────

local HELPERS = {}
HELPERS.cracks = [==[
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
]==]
HELPERS.knows = [==[
-- Have they given away (or been given) that fact? want = true: any value.
local function knows(c, key, fact, want)
    local o = c:who(key)
    local v = o and o.facts[fact]
    if want == true then return v ~= nil and v ~= false end
    return v == want
end
]==]
HELPERS.give = [==[
-- Someone now knows a fact (from what someone else said): the questions it opens are theirs to be asked.
local function give(c, key, fact, v)
    local o = c:who(key)
    if not o then return end
    o.facts[fact] = v
    c:questions(key)
end
]==]
HELPERS.later = [==[
-- Runs fn after s seconds of the call (the tick's clock).
local function later(c, s, fn)
    local at
    c:on('tick', function(now)
        at = at or now + s
        if at and now >= at then at = math.huge fn() end
    end)
end
]==]
HELPERS.resolve = [==[
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
]==]
HELPERS.brawl = [==[
-- Two people really fighting as units pull up. Told to stop (E or the PA), half the time they do; a taser stops it.
-- Left too long, one goes down hurt. -> stop(line)
local function brawl(c, a, b, o)
    local stopped, left = false, 90
    local function stop(line)
        if stopped then return end
        stopped = true
        if o.objective then c:done(o.objective) end
        if c:who(a) then c:task(a, 'surrender') end
        if c:who(b) then c:task(b, 'surrender') end
        if line then c:say(a, line) end
        c:note('The fight was broken up')
    end
    c:on('build', function()
        c:task(a, 'brawl', b)
        c:task(b, 'brawl', a)
    end)
    c:on('hail', function(who)
        if (who == a or who == b) and not stopped then
            if math.random(100) <= (o.chance or 50) then stop(o.line or "Alright! Alright! I'm done!") else c:say(who, o.defy or "I'm not finished with him!") end
        end
    end)
    c:on('stunned', function(who) if who == a or who == b then stop("Okay! Okay! I'm done!") end end)
    c:on('dead', function(who) if who == a or who == b then stop() end end)
    c:on('tick', function()
        if stopped then return end
        if c:near(a, 120.0) then left = left - 1 end
        local function beaten(k) local h = c:health(k) return h and h > 100 and h < 120 end
        local hit = beaten(b) and b or beaten(a) and a
        if left > 0 and not hit then return end
        stop()
        c:collapse(hit or b)
        c:dispatch('One of them is down. Paramedics needed at the scene.')
    end)
    return stop
end
]==]
HELPERS.standoff = [==[
-- Weapon out (on someone, or just held), and nobody can talk to them until they give up: told to drop it (E or the
-- PA), they do `chance` in 100 times; a taser always works. -> give_up(line)
local function standoff(c, key, other, o)
    local over = false
    local function give_up(line)
        if over then return end
        over = true
        if o.objective then c:done(o.objective) end
        c:say(key, line or o.line or "Okay! Okay! I'm putting it down!")
        c:task(key, 'surrender')
    end
    c:on('build', function()
        if other then c:task(key, 'aim', other) else c:task(key, 'hold') end
    end)
    c:on('hail', function(who)
        if who ~= key or over then return end
        if math.random(100) <= (o.chance or 50) then give_up() else c:say(key, o.defy or 'Stay back! I mean it!') end
    end)
    c:on('stunned', function(who) if who == key then give_up() end end)
    c:on('dead', function(who) if who == key then over = true if o.objective then c:done(o.objective) end end end)
    return give_up
end
]==]
HELPERS.shootout = [==[
-- They may open fire when a unit gets close (`chance` in 100), and fight until they're hurt, run out of time with
-- units near, or give up when told to drop it (half the time). -> open_fire(), give_up(line)
local function shootout(c, key, o)
    local reacted, fighting, over, left = false, false, false, 0
    local function give_up(line)
        if over then return end
        over, fighting = true, false
        local who = c:who(key)
        if who then who.ran, who.gave_up = true, true end
        if o.objective then c:done(o.objective) end
        c:say(key, line or o.line or "Okay! I'm done! Don't shoot!")
        c:task(key, 'surrender')
    end
    local function open_fire()
        if over or fighting then return end
        fighting, left = true, math.random(45, 120)
        c:task(key, 'shoot', o.point)
    end
    c:on('fired', function(who)
        if who ~= key then return end
        c:dispatch('Shots fired! All units, shots fired!')
        c:note('Shots fired by the suspect')
    end)
    c:on('contact', function(who) if who == key then reacted = true end end)
    c:on('tick', function()
        local who = c:who(key)
        if not who or who.cuffed or over then return end
        if not reacted and c:near(key, o.near or 18.0) and not c:talking() then
            reacted = true
            if math.random(100) <= (o.chance or 50) then open_fire() end
        end
        if not fighting then return end
        local h = c:health(key)
        left = c:near(key, 45.0) and left - 1 or left
        if h and h > 100 and h < 150 then give_up("Okay! Okay, I'm hit! I'm done! Don't shoot!")
        elseif left <= 0 then give_up("I'm out! That's it! I'm done, don't shoot!") end
    end)
    c:on('hail', function(who) if who == key and fighting and math.random() < 0.5 then give_up("Alright! Alright! I'm putting it down!") end end)
    c:on('dead', function(who) if who == key then over = true if o.objective then c:done(o.objective) end end end)
    return open_fire, give_up
end
]==]
HELPERS.spray = [==[
-- Shooting that's seen and heard, aimed high over a point, a burst every few seconds, until they're told to drop it
-- (`chance` in 100) or tased. -> give_up(line)
local function spray(c, key, at, o)
    local over, next_at = false, 0
    local function give_up(line)
        if over then return end
        over = true
        if o.objective then c:done(o.objective) end
        c:say(key, line or o.line or "Alright! Alright! I'm done!")
        c:task(key, 'surrender')
    end
    c:on('tick', function(now)
        if over or not c:near(key, 150.0) or now < next_at then return end
        next_at = now + math.random(4, 6)
        c:task(key, 'spray', at)
    end)
    c:on('hail', function(who)
        if who ~= key or over then return end
        if math.random(100) <= (o.chance or 50) then give_up() else c:say(key, o.defy or 'Get back!') end
    end)
    c:on('stunned', function(who) if who == key then give_up() end end)
    c:on('dead', function(who) if who == key then over = true if o.objective then c:done(o.objective) end end end)
    return give_up
end
]==]
HELPERS.bolt = [==[
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
]==]
local HELPER_ORDER = { 'cracks', 'knows', 'give', 'later', 'resolve', 'brawl', 'standoff', 'shootout', 'spray', 'bolt' }

-- ─── a story ────────────────────────────────────────────────────────────────────────────────────────────────

local function person(p, uses, qsets, I)
    local o = { 'at = ' .. q(p.at), 'label = ' .. q(p.label) }
    if p.sex == 'male' then o[#o + 1] = 'male = true' elseif p.sex == 'female' then o[#o + 1] = 'male = false' end
    local opt = function(k, v) o[#o + 1] = k .. ' = ' .. v end
    if p.model and p.model ~= '' then opt('model', q(p.model)) end
    if p.secret and p.secret ~= '' then opt('secret', q(p.secret)) end
    if p.demeanor and p.demeanor ~= '' then opt('demeanor', q(p.demeanor)) end
    local age = p.age or {}
    if num(age.min, 16, 99) and num(age.max, 16, 99) then opt('age', ('{ %d, %d }'):format(math.min(age.min, age.max), math.max(age.min, age.max))) end
    if p.home == 'yes' then opt('home', 'true') elseif p.home and p.home ~= '' then opt('home', q(p.home)) end
    if on(p.family) then opt('family', 'true') end
    if on(p.wanted) then opt('wanted', 'true') end
    if on(p.injured) then opt('injured', 'true') end
    if on(p.dead) then opt('dead', 'true') end
    if on(p.runs) then opt('runs', 'true') end
    if p.seated and p.seated ~= '' then opt('seated', q(p.seated)) end
    if p.vitals and p.vitals ~= '' then opt('vitals', q(p.vitals)) end
    if p.weapon and p.weapon ~= '' then opt('weapon', q(p.weapon)) end
    if num(p.reach, 1, 20) then opt('reach', n(p.reach)) end
    local sc = p.scene or {}
    if sc.kind == 'scenario' then opt('scene', q(sc.name))
    elseif sc.kind == 'anim' then opt('scene', ('{ %s, %s }'):format(q(sc.dict), q(sc.anim))) end
    if list(p.items)[1] then opt('items', strs(p.items)) end
    if list(p.pockets)[1] then opt('pockets', strs(p.pockets)) end
    if list(p.facts)[1] then opt('facts', sets(p.facts)) end
    -- their questions: the shared list, then their own
    local qs = {}
    if p.qset and p.qset ~= '' then qs[#qs + 1] = 'Q_' .. p.qset:upper() end
    if list(p.questions)[1] then
        if qs[1] then
            local own = {}
            for _, qn in ipairs(p.questions) do own[#own + 1] = question(qn) end
            uses.join = true
            qs = { ('join(%s, { %s })'):format(qs[1], table.concat(own, ', ')) }
        else
            qs[1] = questions(p.questions, I)
        end
    end
    if qs[1] then opt('questions', qs[1]) end
    local lines = {}
    for _, l in ipairs(list(p.lines)) do
        local v
        if l.kind == 'cracks' then
            uses.cracks = true
            v = ('cracks(%d, %s, %s, %s)'):format(math.floor(num(l.times or 2, 1, 20) or 2), answers(l.deny), answers(l.admit),
                filled(l.again)[1] and answers(l.again) or answers(l.admit))
        elseif l.kind == 'iffact' then
            v = ('function(o) local v = o.facts[%s] if %s then return %s end return %s end'):format(q(l.fact),
                (l.value == nil or l.value == '') and 'v ~= nil and v ~= false' or ('v == ' .. q(l.value)), answers(l.yes), answers(l.no))
        elseif filled(l.answers)[1] then -- (nothing typed yet: they give their usual answer)
            v = answers(l.answers)
        end
        if v then lines[#lines + 1] = ('%s    %s = %s,'):format(I, l.q, v) end
    end
    if lines[1] then opt('lines', '{\n' .. table.concat(lines, '\n') .. '\n' .. I .. '}') end
    return o
end

local function cond(c, uses, story)
    local k, who = c.kind, c.who and c.who ~= '' and q(c.who) or nil
    if k == 'fact' or k == 'nofact' then
        uses.knows = true
        local s = ('knows(c, %s, %s, %s)'):format(who or 'key', q(c.fact), value(c.value))
        return k == 'fact' and s or ('not ' .. s)
    elseif k == 'flag' then return ('c:get(%s)'):format(q(c.flag))
    elseif k == 'noflag' then return ('not c:get(%s)'):format(q(c.flag))
    elseif k == 'done' then return ('c:is_done(%s)'):format(q(c.objective))
    elseif k == 'notdone' then return ('not c:is_done(%s)'):format(q(c.objective))
    elseif k == 'cuffed' then return ('(c:who(%s) and c:who(%s).cuffed)'):format(who or 'key', who or 'key')
    elseif k == 'notcuffed' then return ('not (c:who(%s) and c:who(%s).cuffed)'):format(who or 'key', who or 'key')
    elseif k == 'near' then return ('c:near(%s, %s)'):format(who or 'nil', fl(num(c.m or 30, 1, 500) or 30))
    elseif k == 'talking' then return ('c:talking(%s)'):format(who or '')
    elseif k == 'nottalking' then return ('not c:talking(%s)'):format(who or '')
    elseif k == 'apart' then return ('c:apart(%s, %s)'):format(who or 'key', c.other and c.other ~= '' and q(c.other) or 'key')
    elseif k == 'chance' then return ('math.random(100) <= %d'):format(math.floor(num(c.p or 50, 0, 100) or 50))
    end
    return 'true'
end

local function action(a, uses, I)
    local k, who = a.kind, a.who and a.who ~= '' and q(a.who) or 'key'
    if k == 'done' then return ('%sc:done(%s)'):format(I, q(a.id))
    elseif k == 'reveal' then return ('%sc:reveal(%s)'):format(I, q(a.id))
    elseif k == 'hide' then return ('%sc:hide(%s)'):format(I, q(a.id))
    elseif k == 'blip' then return ('%sc:blip(%s, %s)'):format(I, q(a.id), strs(a.keys))
    elseif k == 'say' then return ('%sc:say(%s, %s)'):format(I, who, q(a.text or ''))
    elseif k == 'dispatch' then return ('%sc:dispatch(%s)'):format(I, q(a.text or ''))
    elseif k == 'note' then return ('%sc:note(%s)'):format(I, q(a.text or ''))
    elseif k == 'tell' then return ('%sif src then c:tell(src, %s, %s) end'):format(I, q(a.title or 'Noticed'), q(a.text or ''))
    elseif k == 'give' then uses.give = true return ('%sgive(c, %s, %s, %s)'):format(I, who, q(a.fact), value(a.value))
    elseif k == 'flag' then return ('%sc:set(%s, %s)'):format(I, q(a.flag), on(a.clear) and 'nil' or 'true')
    elseif k == 'custody' then return ('%sc:custody(%s)'):format(I, who)
    elseif k == 'warrant' then return ('%sc:warrant(%s, %s)'):format(I, who, a.text and a.text ~= '' and q(a.text) or 'nil')
    elseif k == 'file' then return ('%sc:file(%s)'):format(I, who)
    elseif k == 'collapse' then return ('%sc:collapse(%s%s)'):format(I, who, a.vitals and a.vitals ~= '' and (', ' .. q(a.vitals)) or '')
    elseif k == 'die' then return ('%sc:die(%s)'):format(I, who)
    elseif k == 'remove' then return ('%sc:remove(%s%s)'):format(I, who, a.car and a.car ~= '' and (', ' .. q(a.car)) or '')
    elseif k == 'hangup' then return ('%sc:hangup(%s)'):format(I, who)
    elseif k == 'patient' then return ('%sc:patient(%s)'):format(I, who)
    elseif k == 'fare' then return ('%sc:fare(%s)'):format(I, who)
    elseif k == 'bang' then return ('%sc:bang(%s, %s, %d)'):format(I, q(a.weapon), q(a.point), math.floor(num(a.shots or 1, 1, 10) or 1))
    elseif k == 'clear' then return ('%sc:clear(%s%s)'):format(I, q(a.clue), on(a.keep) and ', true' or '')
    elseif k == 'finish' then return ('%sc:finish(%s)'):format(I, q(a.text or 'Dealt with.'))
    elseif k == 'task' then
        local need = Gen.TASKS[a.task]
        if need == 'point' then return ('%sc:task(%s, %s, %s)'):format(I, who, q(a.task), q(a.point))
        elseif need == 'person' then return ('%sc:task(%s, %s, %s)'):format(I, who, q(a.task), q(a.other))
        elseif need == 'point?' then return ('%sc:task(%s, %s%s)'):format(I, who, q(a.task), a.point and a.point ~= '' and (', ' .. q(a.point)) or '')
        elseif need == 'drive' then
            local t = { 'car = ' .. q(a.car) }
            if a.point and a.point ~= '' then t[#t + 1] = 'to = ' .. q(a.point) end
            if on(a.fast) then t[#t + 1] = 'fast = true' end
            return ('%sc:task(%s, \'drive\', { %s })'):format(I, who, table.concat(t, ', '))
        end
        return ('%sc:task(%s, %s)'):format(I, who, q(a.task))
    end
    return I .. '-- (nothing)'
end

-- A rule: one c:on handler. "wait" in its list splits it: what's after runs that many seconds later.
local function rule(r, ri, uses, story)
    local w = r.when or {}
    local ev, args = w.event, Gen.EVENTS[w.event] or {}
    local I = '            '
    local tests = {}
    local function eq(var, v) if v ~= nil and v ~= '' then tests[#tests + 1] = ('%s == %s'):format(var, q(v)) end end
    local real, params = ev, {}
    if ev == 'ask' then real = 'act' params = { 'key', 'action', 'q', 'src' } tests[#tests + 1] = "action == 'ask'" eq('q', w.q)
    elseif ev == 'near' or ev == 'timer' then real = 'tick' params = { 'now' }
    else
        for _, a in ipairs(args) do params[#params + 1] = a == 'who' and 'key' or a end
    end
    if ev ~= 'near' and ev ~= 'timer' then
        eq('key', w.who) eq('clue', w.clue) eq('car', w.car) eq('action', ev == 'act' and w.action or nil) eq('fact', w.fact)
        eq('outcome', w.outcome) eq('how', w.how) eq('what', w.what) eq('stage', w.stage) eq('kind', w.kind)
        if ev == 'fact' and w.value and w.value ~= '' then tests[#tests + 1] = 'value == ' .. q(w.value) end
        if ev == 'dragged' and on(w.clear) then tests[#tests + 1] = 'clear' end
    elseif ev == 'near' then
        tests[#tests + 1] = ('c:near(%s, %s)'):format(w.who and w.who ~= '' and q(w.who) or 'nil', fl(num(w.m or 30, 1, 500) or 30))
    end
    local key_is = (w.who and w.who ~= '') and q(w.who) or nil
    for _, c in ipairs(list(r.ifs)) do tests[#tests + 1] = cond(c, uses, story) end
    local once = r.once ~= false
    local flag = ('r%d'):format(ri)
    local out = {}
    if once then out[#out + 1] = ('        local %s = false'):format(flag) end
    if ev == 'timer' then out[#out + 1] = ('        local %s_at'):format(flag) end
    out[#out + 1] = ('        c:on(%s, function(%s)'):format(q(real), table.concat(params, ', '))
    -- (an event with nobody in it: "them" is whoever the rule names, or nobody)
    if params[1] ~= 'key' then out[#out + 1] = ('            local key = %s'):format(key_is or 'nil') end
    local has_src = false
    for _, p in ipairs(params) do if p == 'src' then has_src = true end end
    if not has_src then out[#out + 1] = '            local src = nil' end
    if ev == 'timer' then
        out[#out + 1] = ('            %s_at = %s_at or now + %d'):format(flag, flag, math.floor(num(w.s or 60, 1, 3600) or 60))
        tests[#tests + 1] = ('now >= %s_at'):format(flag)
    end
    if once then table.insert(tests, 1, 'not ' .. flag) end
    if tests[1] then out[#out + 1] = ('            if not (%s) then return end'):format(table.concat(tests, ' and ')) end
    if once then out[#out + 1] = ('            %s = true'):format(flag) end
    -- the actions, a "wait" pushing what follows into a later() call
    local depth, body = 0, {}
    local function ind() return I .. string.rep('    ', depth) end
    for _, a in ipairs(list(r.actions)) do
        if a.kind == 'wait' then
            uses.later = true
            body[#body + 1] = ('%slater(c, %d, function()'):format(ind(), math.floor(num(a.s or 1, 1, 600) or 1))
            depth = depth + 1
        else
            body[#body + 1] = action(a, uses, ind())
        end
    end
    for d = depth, 1, -1 do body[#body + 1] = I .. string.rep('    ', d - 1) .. 'end)' end
    for _, b in ipairs(body) do out[#out + 1] = b end
    out[#out + 1] = '        end)'
    return table.concat(out, '\n')
end

local function preset(x, uses)
    local o = {}
    if x.objective and x.objective ~= '' then o[#o + 1] = 'objective = ' .. q(x.objective) end
    if num(x.chance, 0, 100) then o[#o + 1] = 'chance = ' .. math.floor(x.chance) end
    if x.line and x.line ~= '' then o[#o + 1] = 'line = ' .. q(x.line) end
    if x.defy and x.defy ~= '' then o[#o + 1] = 'defy = ' .. q(x.defy) end
    if x.kind == 'shootout' then
        if x.point and x.point ~= '' then o[#o + 1] = 'point = ' .. q(x.point) end
        if num(x.near, 3, 60) then o[#o + 1] = 'near = ' .. fl(x.near) end
    end
    local opts = '{ ' .. table.concat(o, ', ') .. ' }'
    uses[x.kind] = true
    if x.kind == 'brawl' then return ('        brawl(c, %s, %s, %s)'):format(q(x.who), q(x.other), opts)
    elseif x.kind == 'standoff' then return ('        standoff(c, %s, %s, %s)'):format(q(x.who), x.other and x.other ~= '' and q(x.other) or 'nil', opts)
    elseif x.kind == 'shootout' then return ('        shootout(c, %s, %s)'):format(q(x.who), opts)
    elseif x.kind == 'spray' then return ('        spray(c, %s, %s, %s)'):format(q(x.who), q(x.point), opts)
    elseif x.kind == 'bolt' then return ('        bolt(c, %s, %s)'):format(q(x.who), opts) end
end

local function ending(e, uses)
    uses.resolve = true
    local o = { 'mode = ' .. q(e.mode or 'subject') }
    if e.subject and e.subject ~= '' then o[#o + 1] = 'subject = ' .. q(e.subject) end
    if e.heard and e.heard ~= '' then o[#o + 1] = 'heard = ' .. q(e.heard) end
    if e.decide and e.decide ~= '' then o[#o + 1] = 'decide = ' .. q(e.decide) end
    if num(e.left, 5, 600) then o[#o + 1] = 'left = ' .. math.floor(e.left) end
    local lines = {}
    for _, k in ipairs({ 'arrested', 'cited', 'warning', 'released', 'fled', 'dead', 'gone', 'left' }) do
        local t = list(e.lines)[k]
        if type(t) == 'string' and t ~= '' then lines[#lines + 1] = ('            %s = %s,'):format(k, q(t)) end
    end
    if lines[1] then o[#o + 1] = 'lines = {\n' .. table.concat(lines, '\n') .. '\n        }' end
    return '        resolve(c, { ' .. table.concat(o, ', ') .. ' })'
end

local function story(s, uses, qsets, has_card)
    local out, I = {}, '            '
    local add = function(l) out[#out + 1] = l end
    for _, p in ipairs(list(s.people)) do
        add(('        c:person(%s, {\n%s%s,\n        })'):format(q(p.key), I, table.concat(person(p, uses, qsets, I), ',\n' .. I)))
    end
    for _, v in ipairs(list(s.vehicles)) do
        local o = { 'at = ' .. q(v.at), 'model = ' .. q(v.model) }
        for _, f in ipairs({ 'make', 'name', 'color', 'label' }) do if v[f] and v[f] ~= '' then o[#o + 1] = f .. ' = ' .. q(v[f]) end end
        if num(v.paint, 0, 160) then o[#o + 1] = 'paint = ' .. math.floor(v.paint) end
        if v.owner and v.owner ~= '' then o[#o + 1] = 'owner = ' .. q(v.owner) end
        if on(v.stolen) then o[#o + 1] = 'stolen = true' end
        if v.locked == false then o[#o + 1] = 'locked = false' end
        if v.damage and v.damage ~= '' then o[#o + 1] = 'damage = ' .. q(v.damage) end
        add(('        c:vehicle(%s, { %s })'):format(q(v.key), table.concat(o, ', ')))
    end
    for _, c in ipairs(list(s.clues)) do
        local o = {}
        if c.on and c.on ~= '' then o[1] = 'on = ' .. q(c.on) else o[1] = 'at = ' .. q(c.at) end
        o[#o + 1] = 'label = ' .. q(c.label)
        if c.prop and c.prop ~= '' then o[#o + 1] = 'prop = ' .. q(c.prop) end
        if on(c.hidden) then o[#o + 1] = 'hidden = true' end
        if on(c.drag) then o[#o + 1] = 'drag = true' end
        if num(c.spikes, 1, 20) then o[#o + 1] = 'spikes = ' .. fl(c.spikes) end
        local sc = c.scatter or {}
        if sc.model and sc.model ~= '' then
            o[#o + 1] = ('scatter = { model = %s, count = %d, radius = %s }'):format(q(sc.model), math.floor(num(sc.count or 6, 1, 30) or 6),
                n(num(sc.radius or 4, 0.5, 20) or 4))
        end
        o[#o + 1] = 'text = ' .. q(c.text)
        add(('        c:clue(%s, { %s })'):format(q(c.key), table.concat(o, ', ')))
    end
    if has_card then add('        card(c)') end
    for _, o in ipairs(list(s.objectives)) do add(objective(o, '        ')) end
    for ri, r in ipairs(list(s.rules)) do add(rule(r, ri, uses, s)) end
    for _, x in ipairs(list(s.presets)) do add(preset(x, uses)) end
    add(ending(s.ending or {}, uses))
    return table.concat(out, '\n')
end

-- ─── the file ───────────────────────────────────────────────────────────────────────────────────────────────

local function fnv(s) -- FNV-1a, 32 bit
    local h = 2166136261
    for i = 1, #s do h = ((h ~ s:byte(i)) * 16777619) & 0xffffffff end
    return ('%08x'):format(h)
end

local LOC_START, LOC_END = '    -- c3rcc:locations', '    -- c3rcc:end'
local function body_hash(body)
    local a = body:find(LOC_START, 1, true)
    local b = a and body:find(LOC_END, a, true)
    if a and b then body = body:sub(1, a - 1) .. body:sub(b) end
    return fnv((body:gsub('\r\n', '\n')))
end
Gen.hash = body_hash

local function locations(doc)
    local out = {}
    for _, l in ipairs(list(doc.locations)) do
        local first = list(doc.points)[1] and l.points[doc.points[1].name]
        local pts, other = {}, {}
        for _, p in ipairs(list(doc.points)) do
            local v = l.points[p.name]
            if v then pts[#pts + 1] = ('            %s = vector4(%.2f, %.2f, %.2f, %.1f),'):format(p.name, v.x, v.y, v.z, v.h or 0) end
            local st = type(l.streets) == 'table' and l.streets[p.name]
            if type(st) == 'string' and st ~= '' and st ~= l.street then other[#other + 1] = ('%s = %s'):format(p.name, q(st)) end
        end
        out[#out + 1] = ('        { street = %s, at = vector3(%.2f, %.2f, %.2f),%s points = {\n%s\n        } },'):format(
            q(l.street ~= '' and l.street or 'Unknown'), first.x, first.y, first.z,
            other[1] and (' streets = { ' .. table.concat(other, ', ') .. ' },') or '', table.concat(pts, '\n'))
    end
    return table.concat(out, '\n')
end

function Gen.lua(doc, credit)
    local uses, out = {}, {}
    local add = function(l) out[#out + 1] = l end
    local names = {}
    for _, s in ipairs(list(doc.stories)) do names[#names + 1] = ('%s (weight %s)'):format(s.id, n(s.weight or 1)) end
    add('--[[')
    add('    c3r callout: ' .. tostring(doc.name):upper():gsub('%]%]', '] ]') .. '.')
    add('    Made with ' .. (credit or 'LWK Callout Creator, BY LWK DEVELOPMENT') .. '. Stories: ' .. table.concat(names, ', ') .. '.')
    add('    Points per location: place them in the creator, or with /c3rplace ' .. doc.id .. ' in game.')
    add(']]')
    add('')
    for _, s in ipairs(list(doc.qsets)) do
        if list(s.questions)[1] then add(('local Q_%s = %s'):format(s.id:upper(), questions(s.questions, ''))) end
    end
    local has_card = list(doc.card)[1] ~= nil
    -- (filled in below, once the stories have said which helpers they use)
    local helpers_at = #out + 1
    add('')
    if has_card then
        add('-- The opening card: the same in every story, so it never gives the story away.')
        add('local function card(c)')
        for _, o in ipairs(doc.card) do add(objective(o, '    ')) end
        add('end')
        add('')
    end
    local stories = {}
    for _, s in ipairs(list(doc.stories)) do
        local needs = list(s.needs)[1] and (' needs = ' .. strs(s.needs) .. ',') or ''
        stories[#stories + 1] = ('    %s = { weight = %s,%s setup = function(c)\n%s\n    end },'):format(s.id, n(num(s.weight or 1, 0, 100) or 1),
            needs, story(s, uses, doc.qsets, has_card))
    end
    local pts = {}
    for _, p in ipairs(list(doc.points)) do
        pts[#pts + 1] = ('        { %s, %s%s%s },'):format(q(p.name), q(p.text or ''), on(p.car) and ", 'car'" or '', on(p.optional) and ', optional = true' or '')
    end
    add('Callout({')
    add('    id = ' .. q(doc.id) .. ',')
    add('    name = ' .. q(doc.name) .. ',')
    add('    priority = ' .. math.floor(num(doc.priority or 2, 1, 3) or 2) .. ',')
    add('    weight = ' .. n(num(doc.weight or 1, 0, 100) or 1) .. ',')
    add('    enabled = ' .. tostring(doc.enabled ~= false) .. ',')
    if doc.service == 'ambulance' then add("    service = 'ambulance',") end
    if doc.alert and doc.alert ~= '' then add('    alert = ' .. q(doc.alert) .. ',') end
    add('    reports = ' .. strs(doc.reports) .. ',')
    add('    points = {\n' .. table.concat(pts, '\n') .. '\n    },')
    add(LOC_START)
    add('    locations = {\n' .. locations(doc) .. '\n    },')
    add(LOC_END)
    add('    stories = {\n' .. table.concat(stories, '\n') .. '\n    },')
    add('})')
    local helpers = {}
    if uses.join then helpers[#helpers + 1] = [==[
-- A shared question list, and someone's own questions after it.
local function join(a, b)
    local t = {}
    for _, x in ipairs(a) do t[#t + 1] = x end
    for _, x in ipairs(b) do t[#t + 1] = x end
    return t
end
]==] end
    for _, h in ipairs(HELPER_ORDER) do if uses[h] then helpers[#helpers + 1] = HELPERS[h] end end
    table.insert(out, helpers_at, table.concat(helpers, '\n'))
    local body = table.concat(out, '\n') .. '\n'
    local data = encode(doc)
    local eq = '='
    while data:find(']' .. eq .. ']', 1, true) do eq = eq .. '=' end
    return ('--[%s[c3rcc\n%s\n]%s]\n-- c3rcc:hash %s\n'):format(eq, data, eq, body_hash(body)) .. body
end

-- -> doc | nil, edited
function Gen.read(text)
    if type(text) ~= 'string' then return nil end
    local eq, data, rest = text:match('^%-%-%[(=*)%[c3rcc\r?\n(.-)\r?\n%]%1%]\r?\n(.*)$')
    if not data then return nil end
    local hash, body = rest:match('^%-%- c3rcc:hash (%x+)\r?\n(.*)$')
    local ok, doc = pcall(decode, data)
    if not ok or type(doc) ~= 'table' then return nil end
    return doc, not hash or body_hash(body) ~= hash
end
