--[[
    c3r — server: callouts. Dispatch puts a call out to every officer on duty; anyone can respond. A call is one
    incident for the whole server: everyone on it works the same scene, and its objectives are split between them
    (each unit on scene holds one; whoever does it, it's done). The calls themselves are in callouts/*.lua: each
    calls Callout{} with its reports, locations and stories (see callouts/_example.lua, the template).

    incident = { id, def, story, loc, report, objectives = { list, by id }, responders = { [src] = { arrived, holds } },
                 facts, handlers, state ('open' | 'done' | 'gone'), created }
    Leaving (clearing with dispatch, X, going off duty) takes that one unit off; the last one off cancels the call.
]]

Callouts = {}

local Defs = {}     -- [id] = definition, in load order in DefList
local DefList = {}
local Open = {}     -- [incident id] = incident
local OnCall = {}   -- [officer src] = incident
local Held = {}     -- [officer src] = true: offers held ("hold my call outs")
local ByNet = {}    -- [ped net id] = person (built, on an open call): talking to them goes through the call
local seq, next_at = 0, nil

-- Who a callout person looks like when the story doesn't say (ordinary townspeople).
local MODELS = {
    male = { 'a_m_y_downtown_01', 'a_m_m_skater_01', 'a_m_y_hipster_01', 'a_m_y_stwhi_01', 'a_m_m_bevhills_01' },
    female = { 'a_f_y_hipster_01', 'a_f_m_downtown_01', 'a_f_y_business_01', 'a_f_y_tourist_01' },
}

local function log(fmt, ...)
    if Config.Debug then print(('[c3r] ' .. fmt):format(...)) end
end

local function cfg() return Config.Callouts or {} end

local function pos(src) return GetEntityCoords(GetPlayerPed(src)) end

local function weighted(list)
    local total = 0
    for _, x in ipairs(list) do total = total + (x.weight or 1) end
    local roll = math.random() * total
    for _, x in ipairs(list) do
        roll = roll - (x.weight or 1)
        if roll <= 0 then return x end
    end
    return list[#list]
end

-- ─── the definitions ──────────────────────────────────────────────────────────

-- Called by each file in callouts/. A broken one is left out (and said why), never the rest.
function Callout(def)
    local function bad(why) print(('[c3r] callout %s left out: %s'):format(tostring(type(def) == 'table' and def.id), why)) end
    if type(def) ~= 'table' or type(def.id) ~= 'string' then return bad('no id') end
    if Defs[def.id] then return bad('a callout with that id is already loaded') end
    if type(def.name) ~= 'string' then return bad('no name') end
    if type(def.reports) ~= 'table' or not def.reports[1] then return bad('no reports') end
    if type(def.locations) ~= 'table' or not def.locations[1] then return bad('no locations') end
    for i, l in ipairs(def.locations) do
        if type(l) ~= 'table' or not l.at or type(l.street) ~= 'string' then return bad('location ' .. i .. ' needs at and street') end
    end
    local stories = {}
    for id, s in pairs(type(def.stories) == 'table' and def.stories or {}) do
        if type(s) ~= 'table' or type(s.setup) ~= 'function' then return bad('story ' .. tostring(id) .. ' has no setup') end
        s.id = id
        stories[#stories + 1] = s
    end
    if not stories[1] then return bad('no stories') end
    table.sort(stories, function(a, b) return tostring(a.id) < tostring(b.id) end) -- (pairs order: same weights, same pick)
    def.story_list = stories
    def.priority = tonumber(def.priority) or 2
    -- the file it's in (for /c3rplace to write new locations into)
    local source = debug and debug.getinfo and (debug.getinfo(2, 'S') or {}).source or ''
    def.file = source:match('(callouts/[%w_%-]+%.lua)$')
    Defs[def.id] = def
    DefList[#DefList + 1] = def
end

-- ─── what a story writes: the handle its setup gets ───────────────────────────

local C = {}
C.__index = C

-- An objective on the card. opts = { after = { ids }, who = 'one' (a unit holds it) | 'all' (on everyone's card),
-- hint, hidden (off the card until c:reveal), blip = person / vehicle / clue key (or a list): marked on the map of
-- whoever has it }.
function C:objective(id, text, opts)
    opts = opts or {}
    local inc = self.inc
    local blip = opts.blip
    local o = { id = id, text = text, after = opts.after or {}, who = opts.who == 'all' and 'all' or 'one', hint = opts.hint,
                hidden = opts.hidden == true, done = false, blips = type(blip) == 'table' and blip or { blip } }
    if not inc.objectives.by[id] then inc.objectives.list[#inc.objectives.list + 1] = o end
    inc.objectives.by[id] = o
    Callouts.refresh(inc)
end

function C:done(id)
    local o = self.inc.objectives.by[id]
    if not o or o.done then return end
    o.done = true
    for _, r in pairs(self.inc.responders) do if r.holds == id then r.holds = nil end end
    Callouts.refresh(self.inc)
end

-- An objective, or a clue, that was hidden: on the card / inspectable now.
function C:reveal(id)
    local o = self.inc.objectives.by[id]
    if o and o.hidden then o.hidden = false Callouts.refresh(self.inc) end
    local cl = self.inc.clues[id]
    if cl and cl.hidden then cl.hidden = false Callouts.send_clues(self.inc) end
end

function C:is_done(id) local o = self.inc.objectives.by[id] return o and o.done or false end

-- event: 'arrive' (src), 'tick' (seconds open), 'leave' (src); more come with the scene (people, clues).
function C:on(event, fn)
    local h = self.inc.handlers
    h[event] = h[event] or {}
    table.insert(h[event], fn)
end

-- Story facts must be the callout's own ("c_..."): the dialogue engine has its own (ran, found, dest...).
local function check_facts(t, where)
    if type(t) ~= 'table' then return end
    for k, v in pairs(t) do
        if k == 'set' and type(v) == 'table' then
            for f in pairs(v) do
                if not tostring(f):match('^c_') then error(('%s sets fact "%s": callout facts start with c_'):format(where, f), 0) end
            end
        elseif type(v) == 'table' then
            check_facts(v, where)
        end
    end
end

--[[ Someone in the story. spec = {
       at = 'point' (the location's points) | vector3 / vector4, model?, male?, label ('Caller': on screen until named),
       secret?, demeanor?, flags?, warrant?, items? (what's on them that matters: a search finds it as evidence),
       pockets? (everyday things a search finds that aren't evidence: a receipt, keys), age? ({ min, max }: their ID),
       scene? ('WORLD_HUMAN_...' scenario, or { dict, anim }), questions? (asked under "The call"), lines?, facts? } ]]
function C:person(key, spec)
    local inc = self.inc
    if inc.people[key] then error('person "' .. key .. '" twice', 0) end
    for _, q in ipairs(spec.questions or {}) do
        if type(q.id) ~= 'string' or type(q.label) ~= 'string' then error('person "' .. key .. '": a question needs id and label', 0) end
    end
    check_facts(spec.lines, 'person "' .. key .. '"')
    check_facts({ set = spec.facts }, 'person "' .. key .. '"')
    local p = { key = key, spec = spec }
    inc.people[key] = p
    inc.people_list[#inc.people_list + 1] = p
end

-- A parked car in the story, on file: run its plate and it's registered to `owner` (a person key), or to someone
-- else. spec = { at, model ('asea'), make ('Declasse'), name ('Asea'), color ('Silver'), paint? (GTA colour id),
-- owner?, stolen?, locked? (default true), label? (on the map) }
function C:vehicle(key, spec)
    if type(spec.model) ~= 'string' then error('vehicle "' .. key .. '" needs a model', 0) end
    if self.inc.vehicles[key] then error('vehicle "' .. key .. '" twice', 0) end
    self.inc.vehicles[key] = { key = key, spec = spec }
    self.inc.vehicle_list[#self.inc.vehicle_list + 1] = self.inc.vehicles[key]
end

-- Evidence. spec = { at = 'point' | vector3, or on = a person or vehicle key; label; text (what inspecting it shows);
-- prop?; hidden? }
function C:clue(key, spec)
    if type(spec.label) ~= 'string' or type(spec.text) ~= 'string' then error('clue "' .. key .. '" needs label and text', 0) end
    self.inc.clues[key] = { key = key, spec = spec, hidden = spec.hidden == true }
    self.inc.clue_list[#self.inc.clue_list + 1] = self.inc.clues[key]
end

-- Their occupant table once the scene is built (facts, answers, cuffed...): read it, don't replace it.
function C:who(key) local p = self.inc.people[key] return p and p.o end

-- Their real name (once built), for summaries and radio updates.
function C:name(key)
    local o = self:who(key)
    return o and o.person and (o.person.first .. ' ' .. o.person.last) or (self.inc.people[key] and self.inc.people[key].spec.label) or key
end

-- A story car's plate (once built).
function C:plate(key) local v = self.inc.vehicles[key] return v and v.plate end

-- The street the call is on.
function C:street() return self.inc.loc.street end

-- Change what an objective marks on the map (keys, or nil for nothing), e.g. once someone's said where he went.
function C:blip(id, keys)
    local o = self.inc.objectives.by[id]
    if not o then return end
    o.blips = type(keys) == 'table' and keys or { keys }
    Callouts.refresh(self.inc)
end

-- Someone's under arrest: the card says to take them in (book them at a station, or call prisoner transport), with a
-- blip on them; it's done, and 'custody' (person, 'booked' | 'transport', src) fires, when they're taken in.
-- Call it again after an uncuff + re-arrest: the same objective comes back. -> its objective id
function C:custody(key)
    local id = 'custody:' .. key
    local o = self.inc.objectives.by[id]
    if o then
        if o.hidden then o.hidden = false Callouts.refresh(self.inc) end
        return id
    end
    self:objective(id, ('Take %s in: book them at a station, or call prisoner transport'):format(self:name(key)),
        { who = 'all', blip = key, hint = 'Seat them in your car and drive to a station, or radio for prisoner transport.' })
    return id
end

-- Off the card again (not done), e.g. the custody objective once they're uncuffed.
function C:hide(id)
    local o = self.inc.objectives.by[id]
    if o and not o.hidden then o.hidden = true Callouts.refresh(self.inc) end
end

-- Is an officer talking to anyone on the call right now? (Not "everyone's left" while someone's mid-conversation.)
function C:talking()
    for _, p in ipairs(self.inc.people_list) do if p.in_contact then return true end end
    return false
end

-- After a story gives someone a fact from elsewhere (c:who(key).facts.x = ...): the officer talking to them now sees
-- the questions it opens without having to do something first.
function C:questions(key)
    local p = self.inc.people[key]
    if p and p.in_contact then StopQuestions(p.in_contact) end
end

-- Something one officer notices (a card on their screen), e.g. "a fresh mark on her cheek".
function C:tell(src, title, text) TriggerClientEvent('c3r:callout:found', src, title, text) end

-- Is any unit on the call within m metres of that person (or, with no key, of the call's location)?
function C:near(key, m)
    local p = key and self.inc.people[key]
    if key and not (p and p.ent and DoesEntityExist(p.ent)) then return false end
    local at = p and GetEntityCoords(p.ent) or self.inc.loc.at
    for src in pairs(self.inc.responders) do
        if #(pos(src) - vector3(at.x, at.y, at.z)) < m then return true end
    end
    return false
end

-- Out of each other's earshot: more than 10 m apart, or either cuffed or sat in a car.
function C:apart(a, b)
    local pa, pb = self.inc.people[a], self.inc.people[b]
    if not (pa and pb and pa.ent and pb.ent) then return true end
    if (pa.o and pa.o.cuffed) or (pb.o and pb.o.cuffed) then return true end
    if GetVehiclePedIsIn(pa.ent, false) ~= 0 or GetVehiclePedIsIn(pb.ent, false) ~= 0 then return true end
    return #(GetEntityCoords(pa.ent) - GetEntityCoords(pb.ent)) > 10.0
end

-- A line heard on scene (a shout through a door), by the units near them.
function C:say(key, text)
    local p = self.inc.people[key]
    if not (p and p.ent) then return end
    for src in pairs(self.inc.responders) do
        if #(pos(src) - GetEntityCoords(p.ent)) < 30.0 then
            TriggerClientEvent('c3r:stop:say', src, text, (p.o and p.o.identified and (p.o.identified.first .. ' ' .. p.o.identified.last))
                or p.spec.label or 'Someone', p.net)
        end
    end
end

-- What they do now: 'scene' (back to what they were doing), 'go' (args = point), 'flee', 'surrender', 'wander'.
-- While an officer is talking to them, only flee and surrender go through (the stop runs them).
local STOP_TASKS = { flee = 'flee', surrender = 'surrender' }
function C:task(key, name, args)
    local p = self.inc.people[key]
    if not p then return end
    if type(args) == 'string' then args = self.inc.loc.points and self.inc.loc.points[args] or nil end
    p.task = name ~= 'scene' and { name = name, args = args } or nil
    if not p.net then return end
    if p.in_contact then
        if STOP_TASKS[name] then TriggerClientEvent('c3r:stop:task', p.in_contact, STOP_TASKS[name], p.net) end
    elseif p.owner then
        TriggerClientEvent('c3r:callout:task', p.owner, p.net, name, args, p.spec.scene)
    end
end

function C:set(k, v) self.inc.facts[k] = v end
function C:get(k) return self.inc.facts[k] end

-- A radio update to every unit on the call.
function C:dispatch(text, clips)
    for src in pairs(self.inc.responders) do TriggerClientEvent('c3r:callout:dispatch', src, text, clips) end
end

-- A line on every unit's MDT incident.
function C:note(text)
    for src in pairs(self.inc.responders) do TriggerEvent('c3r:note', src, text) end
end

function C:finish(summary) Callouts.finish(self.inc, summary) end

-- ─── the incident ─────────────────────────────────────────────────────────────

local function record(inc)
    local l = inc.loc
    return { id = inc.id, name = inc.def.name, street = l.street, coords = l.at, priority = inc.def.priority,
             description = inc.report }
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Runs a story's handlers. One that errors cancels its own call, nothing else.
local function fire(inc, event, ...)
    for _, fn in ipairs(inc.handlers[event] or {}) do
        if inc.state ~= 'open' then return end
        local ok, err = pcall(fn, ...)
        if not ok then
            print(('[c3r] callout %s (%s): %s'):format(inc.def.id, tostring(inc.story.id), tostring(err)))
            return Callouts.cancel(inc)
        end
    end
end
Callouts.fire = fire

local function available(inc, o)
    if o.done or o.hidden then return false end
    for _, id in ipairs(o.after) do
        local a = inc.objectives.by[id]
        if not (a and a.done) then return false end
    end
    return true
end

local function name_of(src) return GetPlayerName(src) or ('Unit ' .. src) end

-- Where an objective's people / cars / evidence are, for the map: { net?, at, label, kind }.
local function blips_for(inc, o)
    local out = {}
    for _, key in ipairs(o.blips) do
        local p, v, cl = inc.people[key], inc.vehicles[key], inc.clues[key]
        local t = p or v
        if t then
            local at = t.ent and DoesEntityExist(t.ent) and GetEntityCoords(t.ent) or inc.loc.points and inc.loc.points[t.spec.at]
                or (type(t.spec.at) ~= 'string' and t.spec.at) or inc.loc.at
            out[#out + 1] = { net = t.net, at = vector3(at.x, at.y, at.z), label = t.spec.label or (v and t.spec.name) or key,
                              kind = v and 'vehicle' or 'person' }
        elseif cl and not cl.hidden then
            local at = inc.loc.points and inc.loc.points[cl.spec.at] or (type(cl.spec.at) ~= 'string' and cl.spec.at) or inc.loc.at
            out[#out + 1] = { at = vector3(at.x, at.y, at.z), label = cl.spec.label, kind = 'clue' }
        end
    end
    return out
end

-- Each unit on scene holds one objective: theirs if it's still open, else the first free one. Then everyone's card.
function Callouts.refresh(inc)
    if inc.state ~= 'open' then return end
    local held = {}
    for _, r in pairs(inc.responders) do
        local o = r.holds and inc.objectives.by[r.holds]
        if o and available(inc, o) then held[o.id] = true else r.holds = nil end
    end
    local srcs = {}
    for src, r in pairs(inc.responders) do if r.arrived then srcs[#srcs + 1] = src end end
    table.sort(srcs, function(a, b) return inc.responders[a].arrived < inc.responders[b].arrived end) -- first there, first pick
    for _, src in ipairs(srcs) do
        local r = inc.responders[src]
        if not r.holds then
            for _, o in ipairs(inc.objectives.list) do
                if o.who == 'one' and not held[o.id] and available(inc, o) then
                    r.holds, held[o.id] = o.id, true
                    break
                end
            end
        end
    end
    for src, r in pairs(inc.responders) do
        local card = { id = inc.id, name = inc.def.name, street = inc.loc.street, arrived = r.arrived ~= nil, mine = {}, team = {} }
        if not r.arrived then
            card.mine[1] = { text = 'Respond to ' .. inc.loc.street }
        else
            local o = r.holds and inc.objectives.by[r.holds]
            if o then card.mine[1] = { text = o.text, hint = o.hint, blips = blips_for(inc, o) } end
            for _, a in ipairs(inc.objectives.list) do
                if a.who == 'all' and available(inc, a) then
                    card.mine[#card.mine + 1] = { text = a.text, hint = a.hint, blips = blips_for(inc, a) }
                end
            end
            for other, ro in pairs(inc.responders) do
                local oo = other ~= src and ro.holds and inc.objectives.by[ro.holds]
                if oo then card.team[#card.team + 1] = { unit = name_of(other), text = oo.text } end
            end
            if not card.mine[1] then -- nothing free: help someone else
                card.mine[1] = card.team[1] and { text = 'Assist ' .. card.team[1].unit .. ': ' .. card.team[1].text }
                    or { text = 'Look around the scene' }
            end
        end
        TriggerClientEvent('c3r:callout:card', src, card)
    end
end

-- Every open call, for the clients (what "attach me" and /respond can join).
local function board()
    local list = {}
    for _, inc in pairs(Open) do
        local r = record(inc)
        r.units = count(inc.responders)
        list[#list + 1] = r
    end
    TriggerClientEvent('c3r:callout:board', -1, list)
end

local function on_duty_players()
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if id and IsOnDuty(id) then out[#out + 1] = id end
    end
    return out
end

local function offer(inc)
    local r = record(inc)
    for _, src in ipairs(on_duty_players()) do
        if not Held[src] and not OnCall[src] then
            r.distance = #(pos(src) - inc.loc.at)
            TriggerClientEvent('c3r:callout:offer', src, r)
            TriggerEvent('c3r:calloutOffered', src, record(inc))
        end
    end
    board()
end

-- ─── the scene: made by the server, so every unit sees the same people ───────

local function point(inc, at)
    if type(at) == 'string' then
        local p = inc.loc.points and inc.loc.points[at]
        if not p then error(('location %s has no point "%s"'):format(inc.loc.street, at), 0) end
        return p
    end
    return at or inc.loc.at
end

-- Their record: a real person (name checks find them), with the story's secret and record. home = they live at the
-- call's address; family = one surname for everyone in the household with family = true.
local function make_record(inc, spec)
    local male = spec.male
    if male == nil then male = math.random() < .5 end
    local secret = spec.secret or 'clean'
    local person, truth
    for _ = 1, 3 do -- a name already on file keeps its own story: try another
        local p = Generator.person(male, secret)
        if spec.home then
            inc.address = inc.address or (math.random(10, 999) .. ' ' .. inc.loc.street)
            p.address = inc.address
        end
        if spec.family then
            inc.surname = inc.surname or p.last
            p.last = inc.surname
        end
        if type(spec.age) == 'table' then -- (their ID says what the story says: a teenager is a teenager)
            p.dob = ('%02d/%02d/%d'):format(math.random(1, 12), math.random(1, 28),
                os.date('*t').year - math.random(spec.age[1], spec.age[2] or spec.age[1]))
        end
        if spec.demeanor then p.truth.demeanor = spec.demeanor end
        if spec.flags then p.flags = spec.flags end
        if spec.warrant then p.warrant = spec.warrant end
        person, truth = Db.createPerson(p)
        if truth.secret == secret then break end
    end
    return male, person, truth
end

-- Server-made entities exist at once but get a net id once a game near them has made them: wait for it.
local function net_of(ent)
    local deadline = GetGameTimer() + 5000
    while (ent == 0 or not DoesEntityExist(ent) or NetworkGetNetworkIdFromEntity(ent) == 0) and GetGameTimer() < deadline do Wait(50) end
    local net = ent ~= 0 and DoesEntityExist(ent) and NetworkGetNetworkIdFromEntity(ent) or 0
    return net ~= 0 and net or nil
end

local function copy(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end

-- A point's heading: vector4s have one (vector3s don't, and asking one for .w is an error).
local function heading_of(at)
    if type(at) == 'vector4' then return at.w end
    return type(at) == 'table' and at.w or nil
end

function Callouts.send_clues(inc)
    local list = {}
    for _, cl in ipairs(inc.clue_list) do
        if not cl.hidden then
            local on = cl.spec.on and (inc.people[cl.spec.on] or inc.vehicles[cl.spec.on])
            local car = on and inc.vehicles[cl.spec.on]
            list[#list + 1] = { key = cl.key, label = cl.spec.label, at = not on and point(inc, cl.spec.at) or nil, on = on and on.net or nil,
                                range = car and 3.2 or 1.6, glow = cl.net or (car and car.net) or nil }
        end
    end
    for src in pairs(inc.responders) do TriggerClientEvent('c3r:callout:clues', src, inc.id, list) end
end

-- Who everyone is: their records (a real person, the story's truth, what they carry) and the cars' papers. Made once,
-- when the first unit gets close: what a story knows about someone doesn't depend on where the officers are.
local function records(inc)
    for _, p in ipairs(inc.people_list) do
        if inc.state ~= 'open' then return end
        local spec = p.spec
        local male, person, truth = make_record(inc, spec)
        local items = spec.items or Generator.items(truth.secret)
        local o = { role = 'pedestrian', part = spec.label, person = person, truth = truth, items = items,
                    answers = {}, facts = copy(spec.facts), callout = inc.id, key = p.key,
                    extra = { questions = spec.questions, lines = spec.lines } }
        o.pockets = Generator.some(Data.pockets, math.random(1, 3))
        for _, item in ipairs(spec.pockets or {}) do table.insert(o.pockets, 1, item) end -- (theirs, not evidence)
        for _, item in ipairs(items) do table.insert(o.pockets, 1, item) end
        p.o, p.male, p.inc = o, male, inc
    end
    for _, v in ipairs(inc.vehicle_list) do
        if inc.state ~= 'open' then return end
        local spec = v.spec
        local owner = spec.owner and inc.people[spec.owner] and inc.people[spec.owner].o.person
        owner = owner or Db.createPerson(Generator.person(math.random() < .5, 'clean'))
        local plate
        repeat -- a plate nobody has
            plate = ('%d%s%03d'):format(math.random(1, 9), string.char(math.random(65, 90), math.random(65, 90), math.random(65, 90)),
                math.random(0, 999))
        until not Db.findVehicle(plate)
        local rec = Generator.vehicle(plate, { make = spec.make, model = spec.name, color = spec.color },
            spec.stolen and 'stolen' or 'clean', owner and owner.id)
        rec.stolen = spec.stolen == true
        Db.createVehicle(rec)
        v.plate = plate
    end
end

-- Is any unit on the call within the build distance of that point?
local function in_range(inc, at)
    local r = cfg().build or 300.0
    for src in pairs(inc.responders) do
        if #(pos(src) - vector3(at.x, at.y, at.z)) < r then return true end
    end
    return false
end

-- The people, cars and props, each made once a unit is near its own point: a game has to be close to a spot for the
-- server to make something there, and this way a point can be any distance from the call (round the corner, or
-- across town). Cancels the call if someone can't be made at all.
local function make_near(inc)
    local made = false
    for _, p in ipairs(inc.people_list) do
        if inc.state ~= 'open' then return end
        local at = point(inc, p.spec.at)
        if not p.ent and in_range(inc, at) then
            local spec = p.spec
            local models = spec.model and { spec.model } or (p.male and MODELS.male or MODELS.female)
            local ent = CreatePed(4, GetHashKey(models[math.random(#models)]), at.x, at.y, at.z, heading_of(at) or 0.0, true, true)
            local net = net_of(ent)
            if inc.state ~= 'open' then if ent ~= 0 then DeleteEntity(ent) end return end
            if not net then
                print(('[c3r] callout %s: could not make "%s" (no game near that point?)'):format(inc.def.id, p.key))
                if ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
                return Callouts.cancel(inc)
            end
            SetEntityOrphanMode(ent, 2) -- (kept while the call is open, whoever's game it moves to)
            p.ent, p.net, p.o.net = ent, net, net
            ByNet[net] = p
            BindSubject(net, p.o.person, nil, p.o.items, p.o.truth)
            made = true
        end
    end
    for _, v in ipairs(inc.vehicle_list) do
        if inc.state ~= 'open' then return end
        local at = point(inc, v.spec.at)
        if not v.ent and in_range(inc, at) then
            local ent = CreateVehicleServerSetter(GetHashKey(v.spec.model), 'automobile', at.x, at.y, at.z, heading_of(at) or 0.0)
            local net = net_of(ent)
            if not net then
                print(('[c3r] callout %s: could not make vehicle "%s" (%s)'):format(inc.def.id, v.key, v.spec.model))
                return Callouts.cancel(inc)
            end
            SetEntityOrphanMode(ent, 2)
            SetVehicleNumberPlateText(ent, v.plate)
            v.ent, v.net = ent, net
            made = true
        end
    end
    for _, cl in ipairs(inc.clue_list) do
        local prop = cl.spec.prop
        if prop and not cl.spec.on and not cl.tried then
            local at = point(inc, cl.spec.at)
            if in_range(inc, at) then
                cl.tried = true
                cl.ent = CreateObjectNoOffset(GetHashKey(prop), at.x, at.y, at.z, true, true, false)
                cl.net = cl.ent ~= 0 and net_of(cl.ent) or nil
                if cl.net then SetEntityOrphanMode(cl.ent, 2)
                else print(('[c3r] callout %s: no prop "%s" for clue "%s" (the marker still shows it)'):format(inc.def.id, prop, cl.key)) end
                made = true
            end
        end
    end
    if made and inc.built then
        Callouts.send_clues(inc)
        Callouts.refresh(inc) -- (the map's blips can follow them now)
    end
end

local function build(inc)
    inc.building = true
    records(inc)
    if inc.state ~= 'open' then return end
    make_near(inc)
    if inc.state ~= 'open' then return end
    inc.built, inc.building = true, false
    log('callout %d: scene built (%d people)', inc.id, #inc.people_list)
    fire(inc, 'build')
    Callouts.send_clues(inc)
    Callouts.refresh(inc)
end

-- Each person's AI runs on whichever game owns them: tell that game what they're doing, again whenever it changes
-- hands. Not while an officer is talking to them (the stop runs them then).
local function keep_up(inc)
    for _, p in ipairs(inc.people_list) do
        if p.ent and not p.in_contact and DoesEntityExist(p.ent) and not (p.o and p.o.cuffed) -- (in cuffs: the officer's now)
            and GetVehiclePedIsIn(p.ent, false) == 0 then
            local owner = NetworkGetEntityOwner(p.ent)
            if owner and owner > 0 and owner ~= p.owner then
                p.owner = owner
                TriggerClientEvent('c3r:callout:apply', owner, { net = p.net, scene = p.spec.scene, task = p.task,
                    place = not p.placed, heading = heading_of(point(inc, p.spec.at)) })
                p.placed = true
            end
        elseif p.ent and not p.gone and not DoesEntityExist(p.ent) then
            p.gone = true
            fire(inc, 'gone', p.key)
        end
    end
    for _, cl in ipairs(inc.clue_list) do
        if cl.net and DoesEntityExist(cl.ent) then
            local owner = NetworkGetEntityOwner(cl.ent)
            if owner and owner > 0 and owner ~= cl.owner then
                cl.owner = owner
                TriggerClientEvent('c3r:callout:apply', owner, { net = cl.net, prop = true, place = not cl.placed })
                cl.placed = true
            end
        end
    end
    for _, v in ipairs(inc.vehicle_list) do
        if v.ent and DoesEntityExist(v.ent) then
            local owner = NetworkGetEntityOwner(v.ent)
            if owner and owner > 0 and owner ~= v.owner then
                v.owner = owner
                TriggerClientEvent('c3r:callout:apply', owner, { net = v.net, vehicle = true, paint = v.spec.paint, plate = v.plate,
                    locked = v.spec.locked ~= false, place = not v.placed })
                v.placed = true
            end
        end
    end
end

-- The call's over: people not under arrest walk off and are left to the game; props go; nobody is the call's any more.
local function clean(inc)
    for _, p in ipairs(inc.people_list) do
        if p.net then
            ByNet[p.net] = nil
            if p.ent and DoesEntityExist(p.ent) then
                SetEntityOrphanMode(p.ent, 0)
                -- (not someone an officer's still talking to, or has in cuffs: they're that officer's to finish with)
                if not (p.o and p.o.cuffed) and not p.in_contact and p.owner then TriggerClientEvent('c3r:callout:task', p.owner, p.net, 'wander') end
            end
            local net = p.net
            SetTimeout(120000, function() UnbindSubject(net) end)
        end
    end
    for _, v in ipairs(inc.vehicle_list) do
        if v.ent and DoesEntityExist(v.ent) then SetEntityOrphanMode(v.ent, 0) end -- (stays parked: the game tidies it up)
    end
    for _, cl in ipairs(inc.clue_list) do
        if cl.ent and cl.ent ~= 0 and DoesEntityExist(cl.ent) then DeleteEntity(cl.ent) end
    end
end

local function close(inc, state)
    inc.state = state
    Open[inc.id] = nil
    for src in pairs(inc.responders) do if OnCall[src] == inc then OnCall[src] = nil end end
    if inc.built or inc.building then clean(inc) end
    board()
end

-- ─── stops.lua: talking to callout people ─────────────────────────────────────

-- The callout person with this ped net id (on an open call), or nil.
function Callouts.person(net)
    local p = ByNet[net]
    return p and p.inc.state == 'open' and p or nil
end

-- An officer started talking to them (s = their contact).
function Callouts.contact(s, p)
    p.in_contact = s.src
    fire(p.inc, 'contact', p.key, s.src)
end

-- After anything the officer did with them: facts they gave away, then the action itself.
function Callouts.acted(s, o, action, arg, before)
    local p = ByNet[o.net]
    if not p or p.inc.state ~= 'open' then return end
    for k, v in pairs(o.facts) do
        if before[k] ~= v then fire(p.inc, 'fact', p.key, k, v, s.src) end
    end
    fire(p.inc, 'act', p.key, action, arg, s.src)
end

-- The officer's done talking to them (walked off, let them go, took them in): back to the call's hands.
function Callouts.contact_ended(s, outcome)
    for net in pairs(s.occ) do
        local p = ByNet[net]
        if p then
            p.in_contact, p.owner = nil, nil -- (keep_up gives their task back to whoever owns them)
            fire(p.inc, 'contact_ended', p.key, outcome, s.src)
        end
    end
end

-- The callout an officer named: its id or its file's name (example, _example, domestic...). -> def | nil
function Callouts.find(name)
    name = type(name) == 'string' and name:lower():gsub('%.lua$', '') or ''
    for _, def in ipairs(DefList) do
        local file = def.file and def.file:match('([^/]+)%.lua$')
        if def.id:lower() == name or file == name or (file and file:gsub('^_', '') == name) then return def end
    end
end

-- A new call near an officer (near = src), or near anyone on duty. only = one callout (by name, even one switched
-- off: someone asked for it), and then the nearest free location if none is within the usual distances.
-- -> incident | nil, reason
function Callouts.create(near, only)
    local c = cfg()
    local officers = near and { near } or on_duty_players()
    if not officers[1] then return nil, 'nobody_on_duty' end
    local used = {}
    for _, inc in pairs(Open) do used[inc.def.id .. ':' .. inc.loc_index] = true end
    local options = {}
    for _, def in ipairs(DefList) do
        if (only and def == only) or (not only and def.enabled ~= false) then
            local locs, nearest, nearest_d = {}, nil, math.huge
            for i, l in ipairs(def.locations) do
                if not used[def.id .. ':' .. i] then
                    for _, src in ipairs(officers) do
                        local d = #(pos(src) - l.at)
                        if d < nearest_d then nearest, nearest_d = i, d end
                        if d >= (c.min_distance or 0) and d <= (c.max_distance or math.huge) then locs[#locs + 1] = i break end
                    end
                end
            end
            if not locs[1] and only and nearest then locs[1] = nearest end
            if locs[1] then options[#options + 1] = { def = def, locs = locs, weight = def.weight or 1 } end
        end
    end
    if not options[1] then return nil, 'no_callout' end
    local pick = weighted(options)
    local def, li = pick.def, pick.locs[math.random(#pick.locs)]
    seq = seq + 1
    local inc = { id = seq, def = def, loc = def.locations[li], loc_index = li, story = weighted(def.story_list),
                  report = def.reports[math.random(#def.reports)], objectives = { list = {}, by = {} }, responders = {},
                  people = {}, people_list = {}, vehicles = {}, vehicle_list = {}, clues = {}, clue_list = {},
                  facts = {}, handlers = {}, state = 'open', created = os.time() }
    inc.c = setmetatable({ inc = inc }, C)
    Open[inc.id] = inc
    local ok, err = pcall(inc.story.setup, inc.c)
    if not ok then
        print(('[c3r] callout %s (%s) setup: %s'):format(def.id, tostring(inc.story.id), tostring(err)))
        close(inc, 'gone')
        return nil, 'no_callout'
    end
    log('callout %d: %s (%s) at %s', inc.id, def.id, tostring(inc.story.id), inc.loc.street)
    offer(inc)
    return inc
end

function Callouts.open_list() local l = {} for _, inc in pairs(Open) do l[#l + 1] = inc end return l end

-- Respond: to call id, or (nil) the nearest open one. -> true | nil, reason
function Callouts.respond(src, id)
    if not IsOnDuty(src) then return nil, 'off_duty' end
    if OnCall[src] then return nil, 'already_on_call' end
    local inc = id and Open[id]
    if not id then
        local best
        for _, x in pairs(Open) do
            local d = #(pos(src) - x.loc.at)
            if not best or d < best then inc, best = x, d end
        end
    end
    if not inc or inc.state ~= 'open' then return nil, 'no_callout' end
    inc.responders[src] = {}
    OnCall[src] = inc
    TriggerEvent('c3r:calloutAccepted', src, record(inc))
    TriggerClientEvent('c3r:callout:joined', src, record(inc))
    Callouts.refresh(inc)
    if inc.built then Callouts.send_clues(inc) end
    board()
    return true
end

-- Done: completed for every unit on it.
function Callouts.finish(inc, summary)
    if inc.state ~= 'open' then return end
    for src in pairs(inc.responders) do
        if summary then TriggerEvent('c3r:note', src, summary) end
        TriggerEvent('c3r:calloutEnded', src, true)
        TriggerClientEvent('c3r:callout:ended', src, true, summary)
    end
    close(inc, 'done')
end

-- Called off (the last unit left, the time limit, a broken story): not completed.
function Callouts.cancel(inc)
    if inc.state ~= 'open' then return end
    for src in pairs(inc.responders) do
        TriggerEvent('c3r:calloutEnded', src, false)
        TriggerClientEvent('c3r:callout:ended', src, false)
    end
    close(inc, 'gone')
end

-- One unit off the call (cleared, X, off duty, gone). The last one off cancels it.
function Callouts.leave(src)
    local inc = OnCall[src]
    if not inc then return nil, 'not_on_call' end
    OnCall[src] = nil
    inc.responders[src] = nil
    TriggerEvent('c3r:calloutEnded', src, false)
    TriggerClientEvent('c3r:callout:ended', src, false)
    if not next(inc.responders) then
        log('callout %d: last unit left', inc.id)
        Callouts.cancel(inc)
    else
        fire(inc, 'leave', src)
        Callouts.refresh(inc)
        board()
    end
    return true
end

-- Once a second: new calls, arrivals, calls nobody took, the time limit.
function Callouts.tick(now)
    now = now or os.time()
    local c = cfg()
    if c.enabled ~= false and DefList[1] then
        local every = c.every or { 240, 480 }
        next_at = next_at or now + math.random(every[1], every[2])
        if now >= next_at and count(Open) < (c.max_open or 2) then
            next_at = now + math.random(every[1], every[2])
            Callouts.create()
        end
    end
    for _, inc in pairs(Open) do
        if not next(inc.responders) and now - inc.created > (c.expire or 300) then
            log('callout %d: nobody took it', inc.id)
            close(inc, 'gone')
        elseif now - inc.created > (c.max_minutes or 30) * 60 then
            log('callout %d: time limit', inc.id)
            Callouts.cancel(inc)
        else
            if not inc.built and not inc.building then
                for src in pairs(inc.responders) do
                    if #(pos(src) - inc.loc.at) < (c.build or 300.0) then
                        CreateThread(function()
                            local ok, err = pcall(build, inc)
                            if not ok then
                                print(('[c3r] callout %s (%s) build: %s'):format(inc.def.id, tostring(inc.story.id), tostring(err)))
                                Callouts.cancel(inc)
                            end
                        end)
                        break
                    end
                end
            end
            if inc.built then
                keep_up(inc)
                if not inc.making then -- (the rest of the scene, as units get near it)
                    inc.making = true
                    CreateThread(function()
                        local ok, err = pcall(make_near, inc)
                        inc.making = false
                        if not ok then
                            print(('[c3r] callout %s (%s) build: %s'):format(inc.def.id, tostring(inc.story.id), tostring(err)))
                            Callouts.cancel(inc)
                        end
                    end)
                end
            end
            for src, r in pairs(inc.responders) do
                if not r.arrived and #(pos(src) - inc.loc.at) < (c.arrive or 40.0) then
                    r.arrived = now + src / 1e6 -- (when, and a tie-break: the order units pick objectives in)
                    TriggerEvent('c3r:calloutArrived', src)
                    fire(inc, 'arrive', src)
                    Callouts.refresh(inc)
                end
            end
            fire(inc, 'tick', now - inc.created)
        end
    end
end

local function loop()
    Callouts.tick()
    SetTimeout(1000, loop)
end
SetTimeout(1000, loop)

-- ─── the officers' games ──────────────────────────────────────────────────────

RegisterNetEvent('c3r:callout:respond', function(id)
    local src = source
    local ok, why = Callouts.respond(src, math.type(id) == 'integer' and id or nil)
    if not ok then TriggerClientEvent('c3r:callout:refused', src, why) end
end)

RegisterNetEvent('c3r:callout:leave', function() Callouts.leave(source) end)

-- A prisoner booked at a station or loaded into prisoner transport (the officer's game says who): if they're someone's
-- callout prisoner, that call's custody objective is done.
RegisterNetEvent('c3r:callout:custody', function(nets, how)
    local src = source
    if not IsOnDuty(src) or type(nets) ~= 'table' or #nets > 8 then return end
    for _, net in ipairs(nets) do
        local p = math.type(net) == 'integer' and Callouts.person(net)
        if p and p.o and p.o.cuffed and not p.taken then
            p.taken = how == 'booked' and 'booked' or 'transport'
            p.inc.c:done('custody:' .. p.key)
            fire(p.inc, 'custody', p.key, p.taken, src)
        end
    end
end)

-- "E Inspect": a unit on the call, beside the evidence (checked here). The first look puts it on everyone's MDT.
RegisterNetEvent('c3r:callout:inspect', function(id, key)
    local src = source
    local inc = OnCall[src]
    local cl = inc and inc.id == id and type(key) == 'string' and inc.clues[key]
    if not cl or cl.hidden or not inc.built then return end
    local on = cl.spec.on and (inc.people[cl.spec.on] or inc.vehicles[cl.spec.on])
    local at = on and on.ent and GetEntityCoords(on.ent) or (cl.ent and cl.ent ~= 0 and GetEntityCoords(cl.ent)) or point(inc, cl.spec.at)
    if #(pos(src) - vector3(at.x, at.y, at.z)) > (on and inc.vehicles[cl.spec.on] and 5.0 or 3.0) then return end
    TriggerClientEvent('c3r:callout:found', src, cl.spec.label, cl.spec.text, cl.key)
    if cl.found then return end
    cl.found = src
    inc.c:note(('Evidence: %s. %s'):format(cl.spec.label, cl.spec.text))
    fire(inc, 'inspect', key, src)
end)

-- /requestcall [callout]: a new call now, near you, put out to everyone (instead of waiting for the next one). Name
-- one (its file: /requestcall domestic) for that one; none for any.
RegisterCommand('requestcall', function(src, args)
    if src <= 0 then return end
    if not IsOnDuty(src) then return TriggerClientEvent('c3r:callout:refused', src, 'off_duty') end
    local only
    if args[1] then
        only = Callouts.find(args[1])
        if not only then
            local names = {}
            for _, d in ipairs(DefList) do names[#names + 1] = d.file and d.file:match('([^/]+)%.lua$'):gsub('^_', '') or d.id end
            return TriggerClientEvent('c3r:callout:refused', src, ('No callout "%s". Callouts: %s'):format(args[1], table.concat(names, ', ')))
        end
    end
    local inc, why = Callouts.create(src, only)
    if not inc then TriggerClientEvent('c3r:callout:refused', src, only and why == 'no_callout' and (only.name .. ': every location is in use.') or why) end
end, false)

-- A game starting up (or c3r restarting on it): the calls open now.
RegisterNetEvent('c3r:callout:sync', function() board() end)

AddEventHandler('c3r:duty', function(src, on) if not on then Callouts.leave(src) end end)
AddEventHandler('playerDropped', function()
    Callouts.leave(source)
    Held[source] = nil
end)

-- ─── /c3rplace: a new location for a callout, walked out in game ─────────────
-- An admin (the command.c3rconfig ace, as /c3rconfig) types /c3rplace <callout> [n]: their game walks them through the
-- callout's points (def.points), and the location is written into the callout's file (added to its locations, or
-- replacing location n) and used straight away.

local function admin(src) return src > 0 and IsPlayerAceAllowed(src, 'command.c3rconfig') end

-- The items of the Lua table whose '{' is at `open` in text: { { s, e } } (where each one's text is), and where it
-- closes. Strings and comments are skipped.
local function table_items(text, open)
    local i, n, depth, list, start, last = open + 1, #text, 0, {}, nil, open
    while i <= n do
        local ch = text:sub(i, i)
        if text:sub(i, i + 1) == '--' then
            local eq = text:match('^%-%-%[(=*)%[', i)
            if eq then i = (text:find(']' .. eq .. ']', i, true) or n) + #eq + 2
            else i = (text:find('\n', i, true) or n) + 1 end
        elseif ch == '"' or ch == "'" then
            if depth == 0 and not start then start = i end
            local j = i + 1
            while j <= n and text:sub(j, j) ~= ch do j = j + (text:sub(j, j) == '\\' and 2 or 1) end
            last, i = j, j + 1
        elseif ch:match('%s') then
            i = i + 1
        else
            if depth == 0 and ch == '}' then
                if start then list[#list + 1] = { s = start, e = last } end
                return list, i
            elseif depth == 0 and ch == ',' then
                if start then list[#list + 1] = { s = start, e = last } end
                start = nil
            else
                if depth == 0 and not start then start = i end
                if ch == '{' or ch == '(' or ch == '[' then depth = depth + 1
                elseif ch == '}' or ch == ')' or ch == ']' then depth = depth - 1 end
            end
            last, i = i, i + 1
        end
    end
end
Callouts.table_items = table_items

local function num(v) return type(v) == 'number' and v == v and math.abs(v) < 100000 end

-- data = { street, points = { [name] = { x, y, z, h } } } from the admin's game -> the location's Lua text, and the table
local function location_of(def, data, indent)
    local pts, lines = {}, {}
    for _, pt in ipairs(def.points) do
        local p = data.points[pt[1]]
        pts[pt[1]] = vector4(p.x, p.y, p.z, p.h)
        lines[#lines + 1] = ('%s    %s = vector4(%.2f, %.2f, %.2f, %.1f),'):format(indent, pt[1], p.x, p.y, p.z, p.h)
    end
    local first = data.points[def.points[1][1]]
    local at = vector3(first.x, first.y, first.z) -- (the first point, the caller's: on scene within Config.Callouts.arrive m of it)
    local head = ("{ street = '%s', at = vector3(%.2f, %.2f, %.2f), points = {"):format(data.street, at.x, at.y, at.z)
    return head .. '\n' .. table.concat(lines, '\n') .. '\n' .. indent .. '} }', { street = data.street, at = at, points = pts }
end

RegisterCommand('c3rplace', function(src, args)
    if not admin(src) then return end
    local def = Defs[args[1] or '']
    if not def or not def.points or not def.file then
        local ids = {}
        for _, d in ipairs(DefList) do if d.points and d.file then ids[#ids + 1] = d.id end end
        return TriggerClientEvent('c3r:place:msg', src, 'Usage: /c3rplace <callout> [location number]. Callouts: ' .. table.concat(ids, ', '))
    end
    local n = tonumber(args[2])
    TriggerClientEvent('c3r:place:start', src, { id = def.id, name = def.name, points = def.points,
        index = n and def.locations[n] and math.floor(n) or nil, count = #def.locations })
end, false)

RegisterNetEvent('c3r:place:save', function(id, index, data)
    local src = source
    local def = admin(src) and type(id) == 'string' and Defs[id]
    if not (def and def.points and def.file and type(data) == 'table' and type(data.points) == 'table') then return end
    for _, pt in ipairs(def.points) do
        local p = data.points[pt[1]]
        if type(p) ~= 'table' or not (num(p.x) and num(p.y) and num(p.z) and num(p.h)) then
            return TriggerClientEvent('c3r:place:msg', src, 'Not saved: point ' .. pt[1] .. ' is missing.')
        end
    end
    data.street = (type(data.street) == 'string' and data.street or 'Unknown'):gsub("[%c'\\]", ''):sub(1, 40)
    local text = LoadResourceFile(GetCurrentResourceName(), def.file)
    local at_id = text and (text:find("id = '" .. id .. "'", 1, true) or text:find('id = "' .. id .. '"', 1, true))
    local brace = text and select(2, text:find('locations%s*=%s*{', at_id or 1)) -- (where its '{' is)
    local list = brace and table_items(text, brace)
    if not list then return TriggerClientEvent('c3r:place:msg', src, 'Not saved: no locations = { ... } found in ' .. def.file) end
    local first = list[1] and text:sub(1, list[1].s - 1):match('\n([ \t]*)$')
    local indent = first or '        '
    local entry, loc = location_of(def, data, indent)
    index = math.type(index) == 'integer' and list[index] and index or nil
    if index then
        local it = list[index]
        text = text:sub(1, it.s - 1) .. entry .. text:sub(it.e + 1)
        def.locations[index] = loc
    else
        local at, sep = brace, ''
        if list[1] then
            local last = list[#list]
            local comma = text:match('^%s*(),', last.e + 1)
            if comma then at = comma else at, sep = last.e, ',' end
        end
        text = text:sub(1, at) .. sep .. '\n' .. indent .. entry .. ',' .. text:sub(at + 1)
        def.locations[#def.locations + 1] = loc
        index = #def.locations
    end
    if not load(text) then return TriggerClientEvent('c3r:place:msg', src, 'Not saved: the file would not load (nothing changed).') end
    SaveResourceFile(GetCurrentResourceName(), def.file, text, -1)
    print(('[c3r] %s placed %s location %d (%s) with /c3rplace'):format(GetPlayerName(src) or src, id, index, data.street))
    TriggerClientEvent('c3r:place:saved', src, ('%s: location %d saved to %s, in use now.'):format(def.name, index, def.file), entry)
end)

-- ─── the contract (docs/contract.md) ──────────────────────────────────────────

exports('setCalloutOffers', function(src, on)
    src = tonumber(src)
    if not src then return nil, 'no_player' end
    Held[src] = not on or nil
    return true
end)

-- A new call now, near that officer, put out to everyone.
exports('offerCallout', function(src)
    src = tonumber(src)
    if not src or not IsOnDuty(src) then return nil, 'off_duty' end
    local inc, why = Callouts.create(src)
    return inc and true or nil, why
end)
