--[[
    c3r — server: the Ambulance role's patients. What's wrong with someone, what fixes it and how long they've got lives
    here, as a callout's truth does; the medic's game (client/ems.lua) shows it and asks.

    A patient has injuries on body parts, each fixed by its steps in order, and a stability from 100 to 0. Only serious
    injuries left open drain it. At 0 their heart stops, and CPR then the defib bring them back; left alone in arrest,
    they die. Someone found dead has the same two steps, and they only sometimes work (Config.Ems.revive). A wrong tool
    says so and costs a moment, nothing more: it's guided.
]]

Ems = {}

local KINDS = {
    bleed = { text = 'Heavy bleeding.', steps = { 'tourniquet' }, serious = true },
    wound = { text = 'Blood coming through the clothes.', next = 'A deep wound. Dress it.', steps = { 'shears', 'dressing' }, serious = true },
    fracture = { text = 'Swollen and out of line: probably broken.', steps = { 'splint' } },
    airway = { text = 'Noisy, gurgling breaths: the airway is blocked.', steps = { 'airway' }, serious = true },
    breathing = { text = 'Short of breath. Listen to the chest.', next = 'Crackles on both sides. Give oxygen.', steps = { 'stethoscope', 'oxygen' }, serious = true },
    overdose = { text = 'Pinpoint pupils, barely breathing.', steps = { 'narcan' }, serious = true },
    sugar = { text = 'Pale, sweating and confused: low blood sugar.', steps = { 'glucose' }, serious = true },
    pulse = { text = 'No pulse.', next = 'Rhythm on the monitor. Shock them.', steps = { 'cpr', 'defib' }, serious = true },
}
local LIMBS = { larm = true, rarm = true, lhand = true, rhand = true, lleg = true, rleg = true, lfoot = true, rfoot = true }

local Patients = {} -- [net id] = patient
local Stock = {}    -- [src] = { [tool] = count }: what's left in their bag

-- list = { { part, kind } }. vitals: a line the screen always shows ('Clutching their chest').
function Ems.new(list, vitals)
    local p = { injuries = {}, stability = 100, vitals = vitals }
    for _, i in ipairs(list or {}) do
        if not KINDS[i[2]] then error('no injury kind "' .. tostring(i[2]) .. '"', 0) end
        p.injuries[#p.injuries + 1] = { part = i[1], kind = i[2], step = 1 }
    end
    return p
end

-- Someone with no callout behind them: what got them is what's wrong with them.
function Ems.guess(part)
    if LIMBS[part] then return Ems.new({ { part, 'bleed' } }) end
    if part == 'head' or part == 'neck' or part == 'thorax' or part == 'abdomen' then return Ems.new({ { part, 'wound' } }) end
    return Ems.new({ { 'thorax', 'breathing' } })
end

local function open_on(p, part)
    for _, i in ipairs(p.injuries) do
        if i.part == part and not i.done then return i end
    end
end

function Ems.stable(p)
    if p.dead then return false end
    for _, i in ipairs(p.injuries) do
        if not i.done and KINDS[i.kind].serious then return false end
    end
    return true
end

-- Their heart's stopped, or was already.
local function no_pulse(p)
    for _, i in ipairs(p.injuries) do
        if i.kind == 'pulse' then i.step, i.done = 1, nil return end
    end
    p.injuries[#p.injuries + 1] = { part = 'thorax', kind = 'pulse', step = 1 }
end

function Ems.found_dead(p)
    p.dead, p.arrest = true, nil
    no_pulse(p)
end

-- -> 'wrong' | 'nothing' (no problem there) | 'step' (more to do) | 'done' | 'back' (a pulse) | 'revive' | 'no_response'
function Ems.use(p, part, tool, revive)
    local i = open_on(p, part)
    if not i then return 'nothing' end
    local kind = KINDS[i.kind]
    if kind.steps[i.step] ~= tool then return 'wrong' end
    if i.step < #kind.steps then
        i.step = i.step + 1
        return 'step'
    end
    i.done = true
    if i.kind ~= 'pulse' then return 'done' end
    if p.dead then
        if math.random() >= (revive or 0) then
            p.tries = (p.tries or 0) + 1
            no_pulse(p)
            return 'no_response'
        end
        p.dead, p.stability = nil, 30
        return 'revive'
    end
    p.arrest, p.stability = nil, 30
    return 'back'
end

-- dt seconds pass. minutes: to arrest from 100, with something serious left open. arrest_s: how long arrest lasts.
-- -> 'arrest' | 'dead' | nil
function Ems.tick(p, dt, minutes, arrest_s)
    if p.dead or Ems.stable(p) then return nil end
    if p.arrest then
        p.arrest = p.arrest - dt
        if p.arrest > 0 then return nil end
        Ems.found_dead(p)
        return 'dead'
    end
    p.stability = math.max(0, p.stability - dt * 100 / (minutes * 60))
    if p.stability > 0 then return nil end
    p.arrest = arrest_s
    no_pulse(p)
    return 'arrest'
end

-- What the screen shows.
function Ems.view(p, stock)
    local list = {}
    for _, i in ipairs(p.injuries) do
        if not i.done then
            local kind = KINDS[i.kind]
            list[#list + 1] = { part = i.part, text = i.step > 1 and kind.next or kind.text, tool = kind.steps[i.step] }
        end
    end
    return { injuries = list, stability = math.ceil(p.stability), arrest = p.arrest ~= nil, dead = p.dead == true,
             stable = Ems.stable(p), vitals = p.vitals, stock = stock }
end

-- A callout's patient (spec.injuries), before anyone's touched them.
function Ems.admit(net, list, vitals) Patients[net] = Ems.new(list, vitals) end
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

local function send(src, net, p, result)
    TriggerClientEvent('c3r:ems:view', src, net, Ems.view(p, Stock[src] or fill_bag(src)), result)
end

RegisterNetEvent('c3r:ems:start', function(net, part, dead)
    local src = source
    if not beside(src, net) then return end
    local p = Patients[net]
    if not p then
        p = Ems.guess(type(part) == 'string' and part or nil)
        Patients[net] = p
    end
    if dead == true and not p.dead then Ems.found_dead(p) end
    p.medic, p.started = src, p.started or os.time()
    send(src, net, p)
end)

local REPLY = {
    wrong = "That won't help here.", nothing = 'Nothing to treat there.', step = 'Done.', done = 'Treated.',
    back = "A pulse! They're back.", revive = "A pulse! They're back.", no_response = 'No response. Start CPR again.',
}
RegisterNetEvent('c3r:ems:use', function(net, part, tool)
    local src = source
    local p = beside(src, net) and Patients[net]
    if not p or type(part) ~= 'string' or type(tool) ~= 'string' then return end
    local stock = Stock[src] or fill_bag(src)
    if not stock[tool] then return end
    if stock[tool] == 0 then return send(src, net, p, { kind = 'empty', text = 'None left. Restock at the ambulance.', ms = 0 }) end
    local how = Ems.use(p, part, tool, cfg().revive)
    local worked = how ~= 'wrong' and how ~= 'nothing'
    if worked and stock[tool] > 0 then stock[tool] = stock[tool] - 1 end
    send(src, net, p, { kind = how, text = REPLY[how], ms = worked and cfg().use_ms or cfg().wrong_ms })
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
    if not p or not p.dead then return end
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
    for _, i in ipairs(p.injuries) do if i.done then fixed = fixed + 1 end end
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
            local was = p.stability
            local what = Ems.tick(p, 1, cfg().arrest_minutes, cfg().arrest_seconds)
            if what == 'dead' then
                local owner = NetworkGetEntityOwner(ent)
                if owner and owner > 0 then TriggerClientEvent('c3r:ems:kill', owner, net) end
            end
            if p.medic and (what or math.ceil(was) ~= math.ceil(p.stability) or p.arrest) then send(p.medic, net, p) end
        end
    end
end

local function loop()
    local ok, err = pcall(Ems.tick_all)
    if not ok then print('[c3r] ems: ' .. tostring(err)) end
    SetTimeout(1000, loop)
end
SetTimeout(1000, loop)
