--[[
    c3r — server: the Ambulance role's patients and the medic's bag. What's wrong with someone, and how it's going, is
    their body (server/ems_body.lua), held here per ped as a callout's truth is; the medic's game (client/ems.lua) shows
    only what's been found, and asks.
]]

Ems = {}

-- A call's injuries in the first form (callouts/ems/, { part, kind }): the body's conditions.
local OLD = { bleed = 'hemorrhage', wound = 'hemorrhage', fracture = 'fracture', airway = 'airway', breathing = 'respiratory',
              overdose = 'opioid', sugar = 'hypoglycemia' }
local LIMBS = { larm = true, rarm = true, lhand = true, rhand = true, lleg = true, rleg = true, lfoot = true, rfoot = true }

local Patients = {} -- [net id] = a body (Body.new), plus medic, started, stabilised, say
local Stock = {}    -- [src] = { [tool] = count }: what's left in their bag

-- list: conditions ({ kind, part } | kind), or the first form ({ part, kind }). say: a line the screen always shows.
function Ems.new(list, say, dead)
    local conds, pain = {}, false
    for _, c in ipairs(list or {}) do
        if type(c) == 'table' and OLD[c[2]] then
            conds[#conds + 1] = { OLD[c[2]], c[1] }
            pain = pain or c[2] == 'fracture' or c[2] == 'bleed' or c[2] == 'wound'
        else
            conds[#conds + 1] = c
        end
    end
    if pain then conds[#conds + 1] = 'pain' end
    local b = Body.new(conds, { dead = dead })
    b.say = say
    return b
end

-- Someone with no callout behind them: what got them is what's wrong with them.
function Ems.guess(part, dead, shot)
    if part == 'head' and shot then return Ems.new({ { 'hemorrhage', 'head' }, 'head' }, nil, true) end -- (shot in the head: no pulse)
    if LIMBS[part] then return Ems.new({ { 'hemorrhage', part }, 'pain' }, nil, dead) end
    if part == 'head' then return Ems.new({ 'head' }, nil, dead) end
    return Ems.new({ { 'hemorrhage', (part == 'neck' or part == 'thorax') and part or 'abdomen' }, 'pain' }, nil, dead)
end

function Ems.stable(b) return Body.stable(b) end

-- A callout's patient (spec.injuries), before anyone's touched them.
function Ems.admit(net, list, say)
    local p = Ems.new(list, say)
    Patients[net] = p
    local parts = {}
    for _, c in ipairs(p.cond) do if c.kind == 'hemorrhage' then parts[#parts + 1] = c.part end end
    local ent = NetworkGetEntityFromNetworkId(net)
    if #parts > 0 and ent and ent ~= 0 then Entity(ent).state:set('c3r_blood', parts, true) end -- (client/ems.lua: blood where they bleed)
end
function Ems.patient(net) return Patients[net] end

-- ─── a medical call's card and ending (callouts/ems/) ───────────────────

function Ems.card(c, who)
    c:objective('treat', 'Treat the patient', { hint = 'Take your bag from the back of the ambulance.', blip = who })
    c:objective('load', 'Stretcher them to the ambulance', { after = { 'treat' }, blip = who })
    c:objective('deliver', 'Take them to hospital', { after = { 'load' }, hint = 'The nearest one is on your map.' })
end

-- ends(how) -> the MDT summary. how = 'hospital' | 'pronounced' | 'gone' (the patient's not in the world any more)
function Ems.wire(c, who, ends)
    local over = false
    local function finish(how)
        if over then return end
        over = true
        for _, id in ipairs({ 'treat', 'load', 'deliver' }) do c:done(id) end
        c:finish(ends(how))
    end
    c:on('aid', function(key, what)
        if key ~= who then return end
        if what == 'stabilised' then c:done('treat') end
        if what == 'hospital' then c:done('load') end
        if what == 'delivered' then finish('hospital') end
        if what == 'pronounced' then finish('pronounced') end
    end)
    c:on('gone', function(key) if key == who then finish('gone') end end)
end

-- ─── the medic's game asks ───────────────────────────────────────────────────

local function cfg() return Config.Ems end

local function fill_bag(src)
    local s = {}
    for _, t in ipairs(cfg().tools) do s[t.id] = t.count or -1 end -- (-1: never runs out)
    Stock[src] = s
    return s
end

-- The medic, beside them. -> the entity
local function beside(src, net)
    if ServiceOf(src) ~= 'ambulance' or math.type(net) ~= 'integer' then return nil end
    local ent = NetworkGetEntityFromNetworkId(net)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    return #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(ent)) <= 8.0 and ent or nil
end

local function send(src, net, b, result)
    local view = Body.view(b)
    view.stock, view.say, view.hint = Stock[src] or fill_bag(src), b.say, Body.hint(b)
    TriggerClientEvent('c3r:ems:view', src, net, view, result)
end

RegisterNetEvent('c3r:ems:start', function(net, part, dead, shot)
    local src = source
    if not beside(src, net) then return end
    local p = Patients[net]
    if not p then
        p = Ems.guess(type(part) == 'string' and part or nil, dead == true, shot == true)
        Patients[net] = p
    elseif dead == true and not p.arrest and not p.dead then
        p = Ems.new({}, p.say, true) -- (a call's patient who died before anyone got there)
        Patients[net] = p
    end
    p.medic, p.started = src, p.started or os.time()
    send(src, net, p)
end)

local SPENT = { done = true, harm = true, rosc = true, no_rosc = true } -- (what uses one up)
local ASSESS = { hands = true, look = true, ask = true, pulse = true, stethoscope = true, penlight = true, glucometer = true, shears = true }
RegisterNetEvent('c3r:ems:use', function(net, part, tool)
    local src = source
    local p = beside(src, net) and Patients[net]
    if not p or (part ~= nil and type(part) ~= 'string') or type(tool) ~= 'string' then return end
    local stock = Stock[src] or fill_bag(src)
    if not stock[tool] then return end
    if stock[tool] == 0 then return send(src, net, p, { kind = 'empty', text = 'None left. Restock at the ambulance.', ms = 0 }) end
    local how, text = Body.act(p, tool, part)
    if SPENT[how] and stock[tool] > 0 then stock[tool] = stock[tool] - 1 end
    local ms = (how == 'wrong' or how == 'nothing' or how == 'not_shockable') and cfg().wrong_ms
        or ASSESS[tool] and cfg().assess_ms or cfg().use_ms
    -- (a harmful dose looks like any other: the monitor is what tells them)
    send(src, net, p, { kind = how == 'harm' and tool ~= 'opa' and 'done' or how, text = text, ms = ms,
        shock = tool == 'defib' and (how == 'rosc' or how == 'no_rosc' or how == 'harm') or nil, tool = tool,
        heard = tool == 'stethoscope' and p.heard and { what = p.heard, hr = math.floor(p.v.hr + 0.5), rr = math.floor(p.v.rr + 0.5) } or nil })
    if Ems.stable(p) and not p.stabilised then
        p.stabilised = true
        Callouts.aid(src, net, 'stabilised')
    end
end)

RegisterNetEvent('c3r:ems:leave', function(net)
    local p = Patients[net]
    if p and p.medic == source then p.medic = nil end
end)

RegisterNetEvent('c3r:ems:restock', function() if ServiceOf(source) == 'ambulance' then fill_bag(source) end end)

-- Past saving: it's on record, and the coroner can take them.
RegisterNetEvent('c3r:ems:pronounce', function(net)
    local src = source
    local p = beside(src, net) and Patients[net]
    if not p or not (p.dead or p.arrest) then return end -- (no pulse, and they've called it)
    Callouts.aid(src, net, 'pronounced')
    Patients[net] = nil
end)

-- On the stretcher and into the ambulance.
RegisterNetEvent('c3r:ems:load', function(net)
    local p = beside(source, net) and Patients[net]
    if p and Ems.stable(p) then Callouts.aid(source, net, 'hospital') end
end)

-- Through the doors: the call hears, and the medic gets their summary.
RegisterNetEvent('c3r:ems:deliver', function(net)
    local src = source
    local p = beside(src, net) and Patients[net]
    if not p then return end
    local mins = math.max(1, math.floor((os.time() - (p.started or os.time())) / 60 + 0.5))
    local fast, fair = cfg().grade[1], cfg().grade[2]
    local fixed = 0
    for _, c in ipairs(p.cond) do if c.found then fixed = fixed + 1 end end
    Callouts.aid(src, net, 'delivered')
    Patients[net] = nil
    TriggerClientEvent('c3r:ems:handover', src, { minutes = mins, treated = fixed,
        grade = mins <= fast and 'Excellent work.' or mins <= fair and 'Good work.' or 'They made it. It could have been quicker.' })
end)

AddEventHandler('c3r:duty', function(src, on, service)
    if on and service == 'ambulance' then fill_bag(src) else Stock[src] = nil end
end)
AddEventHandler('playerDropped', function() Stock[source] = nil end)

-- ─── the clock ────────────────────────────────────────────────────────────────

-- ponytail: every open patient is walked once a second. There are a handful at most; index by medic if that changes.
function Ems.tick_all()
    for net, p in pairs(Patients) do
        local ent = NetworkGetEntityFromNetworkId(net)
        if not ent or ent == 0 or not DoesEntityExist(ent) then
            Patients[net] = nil
        elseif p.started then
            local what = Body.tick(p, 1, p.held)
            if what == 'dead' then
                local owner = NetworkGetEntityOwner(ent)
                if owner and owner > 0 then TriggerClientEvent('c3r:ems:kill', owner, net) end
            end
            local note = p.note -- (a rhythm check at the end of a CPR cycle)
            p.note = nil
            if p.medic then send(p.medic, net, p, note and { kind = note.kind, text = note.text, ms = 0 }) end -- (the monitor moves every second)
            if p.medic and not p.stabilised and Body.stable(p) then
                p.stabilised = true
                Callouts.aid(p.medic, net, 'stabilised')
            end
        end
    end
end

local function loop()
    local ok, err = pcall(Ems.tick_all)
    if not ok then print('[c3r] ems: ' .. tostring(err)) end
    SetTimeout(1000, loop)
end
SetTimeout(1000, loop)
