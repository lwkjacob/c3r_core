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
local Hits = {}     -- [net id] = { { part, cause } }: what hurt them, as it happened (client/ems.lua)
local Stock = {}    -- [src] = { [tool] = count }: what's left in their bag

-- list: conditions ({ kind, part } | kind), or the first form ({ part, kind }). say: a line the screen always shows.
function Ems.new(list, say, dead, arrest)
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
    local b = Body.new(conds, { dead = dead, arrest = arrest })
    b.say = say
    return b
end

--[[ A medics' call that's just the patient, and sometimes something beside them that tells the story. Builds the
     Callout() definition: `Callout(Ems.call({ ... }))` in the call's own file (so /c3rplace writes there). spec = {
       id, name, voice?, priority?, weight?, age? ({ min, max }), trauma? (true: a hidden extra break, now and then),
       reports = { ... },
       locations = { { street, at, points = { patient = vector4, nearby = vector4 } } } (as /c3rplace writes them),
       stories = { key = { weight?, conditions, says (what they look like or say), what (for the MDT: 'a heart attack'),
                           clue? = { label, prop, text }, arrest? (found with no pulse), secret? } } } ]]
function Ems.call(spec)
    local stories = {}
    for key, st in pairs(spec.stories) do
        stories[key] = { weight = st.weight or 1, arrest = st.arrest, setup = function(c)
            local conditions = st.conditions
            if spec.trauma and math.random() < 0.35 then -- (a wrist or ankle broken too: felt on the head-to-toe check)
                conditions = { table.unpack(conditions) }
                conditions[#conditions + 1] = { 'fracture', ({ 'lhand', 'rhand', 'lfoot', 'rfoot' })[math.random(4)] }
            end
            c:person('patient', { at = 'patient', label = 'Patient', secret = st.secret or 'clean', injured = true,
                age = spec.age or { 18, 80 }, vitals = st.says, conditions = conditions, arrest = st.arrest })
            if st.clue then c:clue('nearby', { at = 'nearby', label = st.clue[1], prop = st.clue[2], text = st.clue[3] }) end
            Ems.card(c, 'patient')
            Ems.wire(c, 'patient', function(how)
                if how == 'hospital' then return ('%s, %s, was treated and taken to hospital.'):format(c:name('patient'), st.what) end
                if how == 'pronounced' then return ('%s, %s, died at the scene.'):format(c:name('patient'), st.what) end
                return 'The patient was gone before treatment finished.'
            end)
        end }
    end
    return { id = spec.id, service = 'ambulance', name = spec.name, voice = spec.voice, priority = spec.priority or 2,
             weight = spec.weight or 1, enabled = true, reports = spec.reports,
             points = { { 'patient', 'The patient, on the ground.' }, { 'nearby', 'Something beside them (only some stories use it).', optional = true } },
             locations = spec.locations, stories = stories }
end

-- What each hit did: { part | nil, cause } -> conditions, and whether one of them killed them outright. A gunshot to the
-- head kills; to the chest it collapses the lung; to the neck there's blood in the airway; a limb may break. A blow or
-- a fall to the head is a head injury, to a limb a break. A car or a blast: bleeding, breaks and the head. A dog bite: a
-- bleeding arm or leg.
local BREAKS = 0.4 -- (how often a bullet breaks the bone, or a blow a limb)
function Ems.wounds(hits, rand)
    rand = rand or math.random
    local list, killed = {}, false
    local function add(x) list[#list + 1] = x end
    for _, h in ipairs(hits) do
        local part, cause = h[1], h[2]
        if cause == 'gunshot' or cause == 'stab' then
            local at = part or 'abdomen'
            if at == 'head' and cause == 'gunshot' then killed = true end
            add({ 'hemorrhage', at })
            if at == 'thorax' then add('pneumothorax') end
            if at == 'neck' then add('airway') end
            if at == 'head' then add('head') end
            if LIMBS[at] and cause == 'gunshot' and rand() < BREAKS then add({ 'fracture', at }) end
        elseif cause == 'blunt' or cause == 'fall' then
            if part == 'head' or part == 'neck' then add('head')
            elseif LIMBS[part] and (cause == 'fall' or rand() < BREAKS) then add({ 'fracture', part }) end
            if cause == 'fall' and rand() < 0.35 then add({ 'fracture', rand() < 0.5 and 'lhand' or 'rfoot' }) end -- (put a hand out, or landed badly)
        elseif cause == 'vehicle' or cause == 'explosion' then
            add({ 'hemorrhage', LIMBS[part] and part or 'abdomen' })
            if LIMBS[part] then add({ 'fracture', part }) end
            if part == 'head' or cause == 'explosion' then add('head') end
        elseif cause == 'burn' then
            add('respiratory') -- (the smoke)
        elseif cause == 'bite' then -- (a police dog's: it holds an arm or a leg)
            add({ 'hemorrhage', LIMBS[part] and part or 'rarm' })
        end
        add('pain')
    end
    return list, killed
end

-- Someone with no callout behind them: what got them is what's wrong with them.
function Ems.guess(part, dead, shot)
    if part == 'head' and shot then return Ems.new({ { 'hemorrhage', 'head' }, 'head' }, nil, true) end -- (shot in the head: no pulse)
    if LIMBS[part] then return Ems.new({ { 'hemorrhage', part }, 'pain' }, nil, dead) end
    if part == 'head' then return Ems.new({ 'head' }, nil, dead) end
    return Ems.new({ { 'hemorrhage', (part == 'neck' or part == 'thorax') and part or 'abdomen' }, 'pain' }, nil, dead)
end

function Ems.stable(b) return Body.ready(b) end -- (ready to move: stable, and the workup done)

-- A callout's patient (spec.conditions, or the short form spec.injuries), before anyone's touched them.
function Ems.admit(net, list, say, arrest)
    local p = Ems.new(list, say, nil, arrest)
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
    view.stock, view.say = Stock[src] or fill_bag(src), b.say
    view.hint, view.hint_tool, view.hint_part = Body.hint(b)
    TriggerClientEvent('c3r:ems:view', src, net, view, result)
end

RegisterNetEvent('c3r:ems:start', function(net, part, dead, shot)
    local src = source
    if not beside(src, net) then return end
    local p = Patients[net]
    if not p then
        if Hits[net] then -- (what happened to them, hit by hit)
            local list, killed = Ems.wounds(Hits[net])
            p = Ems.new(list, nil, dead == true or killed)
        else
            p = Ems.guess(type(part) == 'string' and part or nil, dead == true, shot == true)
        end
        Patients[net] = p
    elseif dead == true and not p.arrest and not p.dead then
        p = Ems.new({}, p.say, true) -- (a call's patient who died before anyone got there)
        Patients[net] = p
    end
    p.medic, p.started = src, p.started or os.time()
    if not p.person then
        local who = Subject(net)
        p.person = who and who.person
        local inc = Callouts.of(src)
        p.call, p.street = inc and inc.def.name, inc and inc.loc and inc.loc.street
    end
    send(src, net, p)
end)

-- A hit, from the game that owns them: kept, and if they're already a patient, it's on their body now.
local PART = { head = 1, neck = 1, thorax = 1, abdomen = 1, larm = 1, rarm = 1, lhand = 1, rhand = 1, lleg = 1, rleg = 1, lfoot = 1, rfoot = 1 }
local CAUSE = { gunshot = 1, stab = 1, blunt = 1, fall = 1, vehicle = 1, explosion = 1, burn = 1, bite = 1 }
RegisterNetEvent('c3r:ems:hit', function(net, part, cause)
    local src = source
    if math.type(net) ~= 'integer' or not CAUSE[cause] or (part ~= nil and not PART[part]) then return end
    local ent = NetworkGetEntityFromNetworkId(net)
    if not ent or ent == 0 or not DoesEntityExist(ent) or NetworkGetEntityOwner(ent) ~= src then return end
    local list = Hits[net] or {}
    if #list >= 12 then return end -- (enough to go on: a magazine emptied into someone is no worse on paper)
    list[#list + 1] = { part, cause }
    Hits[net] = list
    local p = Patients[net]
    if p then
        local more, killed = Ems.wounds({ { part, cause } })
        Body.add(p, more)
        if killed then Body.stop(p) end
        p.stabilised = nil
    end
end)

-- ─── the patient care report ─────────────────────────────────────────────────
-- Each patient keeps a log of what was done for them, and the first and last full set of vitals. At the handover (or
-- when they're pronounced) it goes out as c3r:patientReport (docs/contract.md): lwk_mdt writes the report from it.

local PART_NAME = { head = 'head', neck = 'neck', thorax = 'chest', abdomen = 'abdomen', larm = 'left arm', rarm = 'right arm',
                    lhand = 'left hand', rhand = 'right hand', lleg = 'left leg', rleg = 'right leg', lfoot = 'left foot', rfoot = 'right foot' }
local FIX_ON = { tourniquet = true, dressing = true, splint = true } -- (the ones done to a part: the report names it)
local DONE = { -- what the report says for each thing done
    tourniquet = 'Tourniquet applied', dressing = 'Wound packed and dressed', splint = 'Splinted', chest_seal = 'Chest seal applied',
    suction = 'Airway suctioned', opa = 'Oral airway inserted', npa = 'Nasal airway inserted', igel = 'i-gel inserted',
    laryngoscope = 'Laryngoscopy', tube = 'Intubated', pull_tube = 'Endotracheal tube removed', cpr = 'CPR cycle started',
    defib = 'Defibrillated', monitor = 'Cardiac monitor attached', morphine = 'Morphine administered',
    epi = 'Epinephrine administered', narcan = 'Naloxone (Narcan) administered', oxygen = 'Oxygen applied',
    glucose = 'Glucose administered', saline = 'Saline IV started', aspirin = 'Aspirin administered', bvm = 'Bag-valve mask',
}
local RHYTHM_NAME = { vf = 'ventricular fibrillation', vt = 'ventricular tachycardia', asystole = 'asystole', pea = 'PEA',
                      sinus = 'sinus rhythm', tachy = 'sinus tachycardia', brady = 'sinus bradycardia' }

local function care(p, text)
    p.care = p.care or {}
    if #p.care < 80 then p.care[#p.care + 1] = { t = os.time(), text = text } end
end

-- The vitals now, as the medic knows them (the cuff's last reading for the blood pressure).
local function vitals(p)
    local v = p.v
    return { t = os.time(), hr = p.arrest and 0 or math.floor(v.hr + 0.5), sys = p.nibp and p.nibp[1], dia = p.nibp and p.nibp[2],
             spo2 = p.arrest and 0 or math.floor(v.spo2 + 0.5), rr = math.floor(v.rr + 0.5), etco2 = math.floor(v.etco2 + 0.5),
             gcs = math.floor(v.gcs + 0.5), rhythm = RHYTHM_NAME[p.rhythm] or p.rhythm }
end

-- The report, sent once: how = 'transported' | 'pronounced'.
local function report(src, p, how, hospital)
    if p.reported then return end
    p.reported = true
    local found = {}
    for _, c in ipairs(Body.view(p).found) do found[#found + 1] = { part = PART_NAME[c.part] or c.part, text = c.text, treated = c.fixed } end
    TriggerEvent('c3r:patientReport', src, {
        person = p.person, complaint = p.call or 'Patient found injured', says = p.say, street = p.street,
        contact = p.started, left_scene = p.left_scene, ended = os.time(), outcome = how, hospital = hospital,
        findings = found, first = p.first_vitals, last = p.monitor and vitals(p) or nil,
        care = p.care or {}, arrested = p.had_arrest == true, rosc = p.had_rosc == true,
    })
end

local SPENT = { done = true, harm = true, rosc = true, no_rosc = true } -- (what uses one up)
local ASSESS = { hands = true, look = true, ask = true, pulse = true, stethoscope = true, penlight = true, glucometer = true, shears = true }
RegisterNetEvent('c3r:ems:use', function(net, part, tool)
    local src = source
    local p = beside(src, net) and Patients[net]
    if not p or (part ~= nil and type(part) ~= 'string') or type(tool) ~= 'string' then return end
    local stock = Stock[src] or fill_bag(src)
    if not stock[tool] then return end
    if stock[tool] == 0 then return send(src, net, p, { kind = 'empty', text = 'None left. Restock at the ambulance.', ms = 0 }) end
    local had_monitor = p.monitor
    local how, text = Body.act(p, tool, part)
    if SPENT[how] and stock[tool] > 0 then stock[tool] = stock[tool] - 1 end
    if (SPENT[how] and DONE[tool] and tool ~= 'monitor') or (tool == 'monitor' and not had_monitor) then
        local line = DONE[tool] .. (part and PART_NAME[part] and FIX_ON[tool] and (', ' .. PART_NAME[part]) or '')
        if tool == 'defib' and how == 'done' then line = 'Defibrillator pads applied' end
        if how == 'rosc' then line = line .. ': return of spontaneous circulation' end
        if tool == 'bvm' then line = p.bvm and 'Ventilated with a bag-valve mask' or 'BVM ventilation stopped' end
        care(p, line)
    elseif how == 'not_shockable' then
        care(p, 'Rhythm analysed: no shock advised')
    end
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

-- The AI partner sits with them while the medic drives: nothing drifts (client/ems.lua).
RegisterNetEvent('c3r:ems:hold', function(net, on)
    local p = beside(source, net) and Patients[net]
    if p then p.held = on == true or nil end
end)

RegisterNetEvent('c3r:ems:restock', function() if ServiceOf(source) == 'ambulance' then fill_bag(source) end end)

-- Past saving: it's on record, and the coroner can take them.
RegisterNetEvent('c3r:ems:pronounce', function(net)
    local src = source
    local p = beside(src, net) and Patients[net]
    if not p or not (p.dead or p.arrest) then return end -- (no pulse, and they've called it)
    care(p, 'Pronounced dead')
    report(src, p, 'pronounced')
    Callouts.aid(src, net, 'pronounced')
    Patients[net], Hits[net] = nil, nil
end)

local Aboard = {} -- [medic src] = true: a patient in the back (not free for a police request)

-- On the stretcher and into the ambulance.
RegisterNetEvent('c3r:ems:load', function(net)
    local p = beside(source, net) and Patients[net]
    if p and Ems.stable(p) then
        Aboard[source] = true
        p.left_scene = os.time()
        care(p, 'Loaded for transport')
        Callouts.aid(source, net, 'hospital')
    end
end)

-- Through the doors: the call hears, and the medic gets their summary.
RegisterNetEvent('c3r:ems:deliver', function(net, hospital)
    local src = source
    local p = beside(src, net) and Patients[net]
    if not p then return end
    local where
    for _, h in ipairs(Config.Hospitals or {}) do if h.name == hospital then where = h.name end end -- (one of ours, by name)
    care(p, 'Care handed over at ' .. (where and (where .. ' hospital') or 'hospital'))
    report(src, p, 'transported', where)
    local mins = math.max(1, math.floor((os.time() - (p.started or os.time())) / 60 + 0.5))
    local fast, fair = cfg().grade[1], cfg().grade[2]
    local fixed = 0
    for _, c in ipairs(p.cond) do if c.found then fixed = fixed + 1 end end
    Callouts.aid(src, net, 'delivered')
    Patients[net], Hits[net] = nil, nil
    Aboard[src] = nil
    TriggerEvent('c3r:stat', src, 'patients', 1)
    TriggerClientEvent('c3r:ems:handover', src, { minutes = mins, treated = fixed,
        grade = mins <= fast and 'Excellent work.' or mins <= fair and 'Good work.' or 'They made it. It could have been quicker.' })
end)

-- ─── one service asking the other for help (client/backup.lua) ─────────────────
-- An officer asks for an ambulance, or a medic for police. A free player of that service first: on shift, not on a
-- call, not already answering one (a medic: no patient aboard). The first to accept takes it and joins the asker's
-- call. Nobody within accept_seconds, or the helper gone before they get there: the AI unit, at the scene. Offer and job
-- go to the helper's game as c3r:ems:offer and c3r:ems:assigned (nil: it's gone).

local Asks = {} -- [asker src] = { want ('ambulance' | 'police'), at, left (s to accept), offered = { src }, helper? }

local function answering(src)
    for _, a in pairs(Asks) do if a.helper == src then return true end end
    return false
end

local function free_helpers(want, asker)
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if id and id ~= asker and ServiceOf(id) == want and not Callouts.of(id) and not (want == 'ambulance' and Aboard[id])
            and not answering(id) then out[#out + 1] = id end
    end
    return out
end

-- Off the helpers' screens, and the asker's game sends the AI unit. why: 'timeout' | 'dropped'
local function to_ai(asker, why)
    local a = Asks[asker]
    if not a then return end
    Asks[asker] = nil
    if a.helper then TriggerClientEvent('c3r:ems:assigned', a.helper, nil, why)
    else for _, m in ipairs(a.offered) do TriggerClientEvent('c3r:ems:offer', m, nil) end end
    TriggerClientEvent('c3r:ems:request:ai', asker, why)
end

-- want: what they're asking for ('ambulance' from an officer, 'police' from a medic).
RegisterNetEvent('c3r:ems:request', function(at, want)
    local src = source
    want = want == 'police' and 'police' or 'ambulance'
    if ServiceOf(src) ~= (want == 'police' and 'ambulance' or 'police') or Asks[src]
        or type(at) ~= 'vector3' and not (type(at) == 'table' and tonumber(at.x)) then return end
    at = vector3(at.x + 0.0, at.y + 0.0, at.z + 0.0)
    local free = free_helpers(want, src)
    if #free == 0 then return TriggerClientEvent('c3r:ems:request:ai', src, 'none') end
    local secs = cfg().accept_seconds or 20
    Asks[src] = { want = want, at = at, left = secs, offered = free }
    for _, m in ipairs(free) do
        TriggerClientEvent('c3r:ems:offer', m, { id = src, at = at, from = GetPlayerName(src), ms = secs * 1000, want = want })
    end
end)

RegisterNetEvent('c3r:ems:accept', function(asker)
    local src = source
    local a = Asks[asker]
    local mine = false
    for _, m in ipairs(a and a.offered or {}) do mine = mine or m == src end
    if not a or a.helper or not mine or ServiceOf(src) ~= a.want then -- (someone else took it, or it's gone)
        return TriggerClientEvent('c3r:ems:offer', src, nil)
    end
    a.helper = src
    for _, m in ipairs(a.offered) do if m ~= src then TriggerClientEvent('c3r:ems:offer', m, nil) end end
    TriggerClientEvent('c3r:ems:assigned', src, { id = asker, at = a.at, from = GetPlayerName(asker), want = a.want })
    TriggerClientEvent('c3r:ems:request:accepted', asker, GetPlayerName(src))
    local inc = Callouts.of(asker)
    if inc then Callouts.respond(src, inc.id) end
end)

-- The asker called it off (or went off shift): off the helpers' screens.
local function called_off(asker)
    local a = Asks[asker]
    if not a then return end
    Asks[asker] = nil
    if a.helper then TriggerClientEvent('c3r:ems:assigned', a.helper, nil, 'cancelled')
    else for _, m in ipairs(a.offered) do TriggerClientEvent('c3r:ems:offer', m, nil) end end
end
RegisterNetEvent('c3r:ems:request:cancel', function() called_off(source) end)

-- The helper gave it up before getting there.
RegisterNetEvent('c3r:ems:drop', function()
    for asker, a in pairs(Asks) do if a.helper == source then to_ai(asker, 'dropped') end end
end)

-- Once a second: the time to accept, and the helper getting there.
function Ems.tick_asks()
    for asker, a in pairs(Asks) do
        if not a.helper then
            a.left = a.left - 1
            if a.left <= 0 then to_ai(asker, 'timeout') end
        elseif #(GetEntityCoords(GetPlayerPed(a.helper)) - a.at) < 40.0 then
            Asks[asker] = nil
            TriggerClientEvent('c3r:ems:assigned', a.helper, nil, 'arrived')
            TriggerClientEvent('c3r:ems:request:arrived', asker, GetPlayerName(a.helper))
        end
    end
end

-- Off shift or gone: their own request goes with them; one they took goes to the AI unit.
local function gone(src)
    Stock[src], Aboard[src] = nil, nil
    called_off(src)
    for asker, a in pairs(Asks) do if a.helper == src then to_ai(asker, 'dropped') end end
end

AddEventHandler('c3r:duty', function(src, on, service)
    if on and service == 'ambulance' then fill_bag(src) else gone(src) end
end)
AddEventHandler('playerDropped', function() gone(source) end)

-- ─── the clock ────────────────────────────────────────────────────────────────

-- ponytail: every open patient is walked once a second. There are a handful at most; index by medic if that changes.
local swept = 0
function Ems.tick_all()
    swept = swept + 1
    if swept >= 60 then -- (once a minute: the hurt nobody treated, gone from the world)
        swept = 0
        for net in pairs(Hits) do
            local ent = NetworkGetEntityFromNetworkId(net)
            if not Patients[net] and (not ent or ent == 0 or not DoesEntityExist(ent)) then Hits[net] = nil end
        end
    end
    for net, p in pairs(Patients) do
        local ent = NetworkGetEntityFromNetworkId(net)
        if not ent or ent == 0 or not DoesEntityExist(ent) then
            Patients[net], Hits[net] = nil, nil
        elseif p.started then
            local what = Body.tick(p, 1, p.held)
            if p.started and not p.first_vitals and p.nibp then p.first_vitals = vitals(p) end -- (the first full set: the cuff's in)
            if what == 'arrest' then
                p.had_arrest = true
                care(p, 'Patient went into cardiac arrest: ' .. (RHYTHM_NAME[p.rhythm] or p.rhythm))
            elseif what == 'rosc' then
                p.had_rosc = true
                care(p, 'Return of spontaneous circulation')
            elseif what == 'dead' then
                care(p, 'No response to resuscitation')
            end
            if p.note and what ~= 'rosc' then care(p, p.note.text) end
            if what == 'dead' then
                local owner = NetworkGetEntityOwner(ent)
                if owner and owner > 0 then TriggerClientEvent('c3r:ems:kill', owner, net) end
            end
            local note = p.note -- (a rhythm check at the end of a CPR cycle)
            p.note = nil
            if p.medic then send(p.medic, net, p, note and { kind = note.kind, text = note.text, ms = 0 }) end -- (the monitor moves every second)
            if p.medic and not p.stabilised and Body.ready(p) then
                p.stabilised = true
                Callouts.aid(p.medic, net, 'stabilised')
            end
        end
    end
end

local function loop()
    local ok, err = pcall(Ems.tick_all)
    if not ok then print('[c3r] ems: ' .. tostring(err)) end
    ok, err = pcall(Ems.tick_asks)
    if not ok then print('[c3r] ems requests: ' .. tostring(err)) end
    SetTimeout(1000, loop)
end
SetTimeout(1000, loop)
