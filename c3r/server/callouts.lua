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
local seq, next_at = 0, nil

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
    Defs[def.id] = def
    DefList[#DefList + 1] = def
end

-- ─── what a story writes: the handle its setup gets ───────────────────────────

local C = {}
C.__index = C

-- An objective on the card. opts = { after = { ids }, who = 'one' (a unit holds it) | 'all' (on everyone's card),
-- hint, hidden (off the card until c:reveal) }.
function C:objective(id, text, opts)
    opts = opts or {}
    local inc = self.inc
    local o = { id = id, text = text, after = opts.after or {}, who = opts.who == 'all' and 'all' or 'one', hint = opts.hint,
                hidden = opts.hidden == true, done = false }
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

function C:reveal(id)
    local o = self.inc.objectives.by[id]
    if o and o.hidden then o.hidden = false Callouts.refresh(self.inc) end
end

function C:is_done(id) local o = self.inc.objectives.by[id] return o and o.done or false end

-- event: 'arrive' (src), 'tick' (seconds open), 'leave' (src); more come with the scene (people, clues).
function C:on(event, fn)
    local h = self.inc.handlers
    h[event] = h[event] or {}
    table.insert(h[event], fn)
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
            if o then card.mine[1] = { text = o.text, hint = o.hint } end
            for _, a in ipairs(inc.objectives.list) do
                if a.who == 'all' and available(inc, a) then card.mine[#card.mine + 1] = { text = a.text, hint = a.hint } end
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

local function close(inc, state)
    inc.state = state
    Open[inc.id] = nil
    for src in pairs(inc.responders) do if OnCall[src] == inc then OnCall[src] = nil end end
    board()
end

-- A new call near an officer (near = src), or near anyone on duty. -> incident | nil, reason
function Callouts.create(near)
    local c = cfg()
    local officers = near and { near } or on_duty_players()
    if not officers[1] then return nil, 'nobody_on_duty' end
    local used = {}
    for _, inc in pairs(Open) do used[inc.def.id .. ':' .. inc.loc_index] = true end
    local options = {}
    for _, def in ipairs(DefList) do
        if def.enabled ~= false then
            local locs = {}
            for i, l in ipairs(def.locations) do
                if not used[def.id .. ':' .. i] then
                    for _, src in ipairs(officers) do
                        local d = #(pos(src) - l.at)
                        if d >= (c.min_distance or 0) and d <= (c.max_distance or math.huge) then locs[#locs + 1] = i break end
                    end
                end
            end
            if locs[1] then options[#options + 1] = { def = def, locs = locs, weight = def.weight or 1 } end
        end
    end
    if not options[1] then return nil, 'no_callout' end
    local pick = weighted(options)
    local def, li = pick.def, pick.locs[math.random(#pick.locs)]
    seq = seq + 1
    local inc = { id = seq, def = def, loc = def.locations[li], loc_index = li, story = weighted(def.story_list),
                  report = def.reports[math.random(#def.reports)], objectives = { list = {}, by = {} }, responders = {},
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

-- /requestcall: a new call now, near you, put out to everyone (instead of waiting for the next one).
RegisterCommand('requestcall', function(src)
    if src <= 0 then return end
    if not IsOnDuty(src) then return TriggerClientEvent('c3r:callout:refused', src, 'off_duty') end
    local inc, why = Callouts.create(src)
    if not inc then TriggerClientEvent('c3r:callout:refused', src, why) end
end, false)

-- A game starting up (or c3r restarting on it): the calls open now.
RegisterNetEvent('c3r:callout:sync', function() board() end)

AddEventHandler('c3r:duty', function(src, on) if not on then Callouts.leave(src) end end)
AddEventHandler('playerDropped', function()
    Callouts.leave(source)
    Held[source] = nil
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
