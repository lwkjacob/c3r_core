--[[
    c3r — server: a patient's body (docs/spec/phase7-ems-realism.md, section 4). Pure: no natives, so the self-checks
    play it second by second.

    Vitals (heart rate, blood pressure, SpO2, breathing, EtCO2, GCS, blood sugar) drift each second toward targets that
    the patient's conditions set, and drugs, airway kit and bleeding control change those targets. Nothing is known until
    it's found: Body.act with an assessment tool finds what's there, and Body.view sends only what's been found. Bad
    numbers sound alarms for at least 30 s before the heart stops; an arrest has a real rhythm, and only VF and VT are
    shocked.

    b = Body.new({ { 'hemorrhage', 'lleg' }, 'pain' }, { rand = fn, dead = true })
    Body.tick(b, dt, hold) -> 'arrest' | 'rosc' | 'dead' | nil    (hold: the AI partner's watching them; nothing drifts)
    Body.act(b, tool, part) -> kind, text                         (kind: 'found' | 'nothing' | 'done' | 'wrong' |
                                                                   'harm' | 'not_shockable' | 'rosc' | 'no_rosc' | 'need')
    Body.view(b), Body.hint(b), Body.stable(b)
]]

Body = {}

local BASE = { hr = 75, sys = 120, spo2 = 98, rr = 14, etco2 = 38, gcs = 15, sugar = 5.5 }
local RATE = { hr = 3.0, sys = 2.0, spo2 = 0.8, rr = 0.8, etco2 = 1.5, gcs = 0.4, sugar = 0.1 } -- per second, toward target
local FALL = { spo2 = 0.35 } -- (oxygen runs down slower than it comes back: there's time to notice)
local LIMBS = { larm = true, rarm = true, lhand = true, rhand = true, lleg = true, rleg = true, lfoot = true, rfoot = true }

-- part: where it's found (nil: anywhere it's given); fix: what handles it; serious: holds up transport until handled
-- seen: plain to see on arrival (blood through the clothes, a limb at the wrong angle)
local KINDS = {
    hemorrhage = { serious = true, seen = true }, fracture = { serious = true, seen = true }, pain = { part = 'head' }, airway = { part = 'head', serious = true },
    respiratory = { part = 'thorax', serious = true }, opioid = { part = 'head', serious = true },
    hypoglycemia = { part = 'lhand', serious = true }, cardiac = { part = 'thorax', serious = true }, head = { part = 'head' },
    bradycardia = { part = 'neck', serious = true }, pneumothorax = { part = 'thorax', serious = true },
}
local FOUND_TEXT = {
    hemorrhage = 'Bright red blood, pumping from a wound.', fracture = 'Deformed, swollen and tender: broken.',
    pain = 'They rate their pain eight out of ten.', airway = 'Gurgling. Their mouth and throat are blocked.',
    respiratory = 'Wheezes and crackles on both sides.', opioid = 'Pinpoint pupils and slow, shallow breaths.',
    hypoglycemia = 'Blood sugar is very low.', cardiac = 'Crushing chest pain, spreading down the left arm.',
    head = 'A boggy swelling on the scalp, and one pupil is bigger than the other.', bradycardia = 'A slow, weak pulse.',
    pneumothorax = 'Air sucking in and out of a chest wound, and no breath sounds on that side.',
}
local DRUGS = { morphine = true, epi = true, narcan = true, oxygen = true, glucose = true, saline = true, aspirin = true }
local SHOCKABLE = { vf = true, vt = true }

local function cfg() return Config.Ems end

local function cond(b, kind, part)
    for _, c in ipairs(b.cond) do
        if c.kind == kind and (not part or c.part == part) then return c end
    end
end
-- the first of that kind still untreated (a second bleed is still a bleed)
local function open(b, kind)
    for _, c in ipairs(b.cond) do
        if c.kind == kind and not c.fixed then return c end
    end
end

-- A dose already taking hold or working isn't set back by another: it lasts longer.
local function give(b, name, onset, dur)
    local e = b.effects[name]
    if e and b.t < e.to then
        e.to = math.max(e.to, b.t + onset + dur)
        return
    end
    b.effects[name] = { from = b.t + onset, to = b.t + onset + dur }
end
local function on(b, name)
    local e = b.effects[name]
    return e ~= nil and b.t >= e.from and b.t < e.to
end
-- given, and taking hold or working
local function coming(b, name)
    local e = b.effects[name]
    return e ~= nil and b.t < e.to
end

local function secured(b) return b.airway_kit ~= nil and b.tube ~= 'wrong' end
-- (a slack airway only blocks someone too far gone to hold it open themselves)
local function airway_blocked(b) return b.airway == 'fouled' or (b.airway == 'slack' and b.v.gcs <= 8 and not secured(b)) end

-- 0 (nothing) to 1 (pain everywhere)
local function pain(b)
    local p = 0
    for _, c in ipairs(b.cond) do
        if c.kind == 'fracture' then p = p + (c.fixed and 0.3 or 0.6)
        elseif c.kind == 'pain' then p = p + 0.6
        elseif c.kind == 'cardiac' then p = p + 0.5
        elseif c.kind == 'hemorrhage' then p = p + 0.3 * (c.n or 1)
        elseif c.kind == 'pneumothorax' then p = p + 0.3 end
    end
    if on(b, 'morphine') then p = p * 0.3 end
    return math.min(p, 1)
end

-- What every vital is heading for now. -> table
local function target(b)
    local t = {}
    for k, v in pairs(BASE) do t[k] = v end
    local loss = 100 - b.blood
    local p = pain(b)
    local opioid = open(b, 'opioid') and not on(b, 'narcan')
    -- breathing: how fast, and how well (q: 0 nothing gets through, 1 fine)
    local rr = 14 + p * 4
    if open(b, 'respiratory') then rr = 28 end
    if opioid then rr = 5 end
    if open(b, 'head') then rr = 10 end
    if loss > 30 then rr = rr + 8 end
    if on(b, 'morphine_bad') then rr = rr - 4 end
    if airway_blocked(b) and b.v.gcs > 8 then rr = 30 end -- (awake and fighting for air; out cold, they just stop)
    local q = 1
    if airway_blocked(b) then q = b.airway == 'fouled' and 0.45 or 0.55 end
    if open(b, 'respiratory') then q = math.min(q, 0.75) end
    if open(b, 'pneumothorax') then rr, q = math.max(rr, 30), math.min(q, 0.7) end -- (one lung)
    if rr < 8 then q = math.min(q, rr / 8) end
    if b.bvm and not airway_blocked(b) then rr, q = 12, math.max(q, 0.95) end -- (breathed for)
    if b.tube == 'wrong' then q = 0 end -- (the bag fills their stomach)
    t.rr = math.max(rr, 0)
    t.spo2 = 98 - (1 - q) * 45
    if b.o2 and q > 0.2 then t.spo2 = math.min(t.spo2 + 10, 99) end
    t.etco2 = (rr < 10 and q > 0) and 55 or (airway_blocked(b) and 50 or 38)
    if b.tube == 'wrong' then t.etco2 = 0 end
    -- the heart
    local hr = 75 + p * 30
    if loss > 10 then hr = hr + (loss - 10) * 2.2 end
    if open(b, 'respiratory') then hr = hr + 15 end
    if open(b, 'pneumothorax') then hr = hr + 20 end
    if open(b, 'hypoglycemia') then hr = hr + 15 end
    if open(b, 'cardiac') then hr = hr + 15 end
    if open(b, 'head') then hr = hr - 20 end
    if open(b, 'bradycardia') then hr = 38 end
    if on(b, 'epi') then hr = hr + 40 end
    if on(b, 'epi_bad') then hr = hr + 50 end
    local c = open(b, 'cardiac')
    if c and (c.strain or 0) > cfg().cardiac_minutes * 60 then hr = hr + 60 end -- (an attack building: the warning)
    if b.v.spo2 < 85 then hr = hr + 20 end
    if b.v.spo2 < 68 then hr = 40 end -- (starved: slowing before it stops)
    t.hr = hr
    -- the blood pressure
    local sys = 120 + p * 20 - math.max(0, loss - 15) * 2.4
    if open(b, 'head') then sys = sys + 25 end
    if open(b, 'bradycardia') then sys = sys - 35 end
    if on(b, 'epi') then sys = sys + 30 end
    if on(b, 'saline') then sys = sys + math.min(loss, 30) * 1.2 end
    if on(b, 'morphine_bad') then sys = sys - 25 end
    t.sys = sys
    -- responsiveness, blood sugar
    local gcs = 15
    if opioid then gcs = 8 end
    if open(b, 'hypoglycemia') then gcs = math.min(gcs, 9) end
    if open(b, 'head') then gcs = math.min(gcs, 10) end
    if b.v.spo2 < 85 then gcs = gcs - 3 end
    if b.v.sys < 80 then gcs = gcs - 3 end
    t.gcs = math.max(3, gcs)
    t.sugar = open(b, 'hypoglycemia') and 2.1 or 5.5
    return t
end

local rhythm_check -- (below, with CPR)

local function set_rhythm(b)
    if b.arrest then return end
    local hr = b.v.hr
    b.rhythm = hr > 100 and 'tachy' or hr < 60 and 'brady' or 'sinus'
end

-- Their heart stops. cause: 'hypoxia' | 'hypovolemia' | 'cardiac' | 'vt' | 'dead'
local function arrest(b, cause)
    local r = b.rand()
    local rhythm
    if cause == 'vt' then rhythm = 'vt'
    elseif cause == 'cardiac' then rhythm = r < 0.7 and 'vf' or 'vt'
    elseif cause == 'dead' then rhythm = r < 0.6 and 'asystole' or 'pea'
    else rhythm = r < 0.5 and 'pea' or 'asystole' end
    b.arrest = { rhythm = rhythm, cause = cause, t = 0, cprs = 0, since_shock = 0 }
    b.rhythm = rhythm
    b.v.hr = rhythm == 'vt' and 180 or rhythm == 'pea' and 40 or 0
    b.v.sys, b.v.rr, b.v.gcs = 0, 0, 3
    b.low = {}
end

local function rosc(b)
    b.arrest = nil
    b.long_dead = nil
    b.v.hr, b.v.sys, b.v.spo2, b.v.rr, b.v.gcs = 110, 85, 85, 8, 3
    b.low = {}
    set_rhythm(b)
end

-- The cause of an arrest left unfixed halves the odds (a pump can't run empty, or on no air).
local function reversible(b)
    local cause = b.arrest.cause
    if cause == 'hypovolemia' then return not open(b, 'hemorrhage') end
    if cause == 'hypoxia' then return not airway_blocked(b) and b.tube ~= 'wrong' end
    return true
end

-- list = { { kind, part } | kind }
-- More wrong with them: list = { { kind, part } | kind }. The same wound again in the same place is one more wound
-- there (c.n: it bleeds harder); anything else already there is left as it is. A new one starts unfixed.
function Body.add(b, list)
    for _, c in ipairs(list or {}) do
        local kind, part = c, nil
        if type(c) == 'table' then kind, part = c[1], c[2] end
        if not KINDS[kind] then error('no condition "' .. tostring(kind) .. '"', 0) end
        part = part or KINDS[kind].part
        local had = cond(b, kind, part)
        if had then
            if kind == 'hemorrhage' then
                had.n, had.fixed = (had.n or 1) + 1, nil
                b.blood = b.blood - 8
            end
        else
            b.cond[#b.cond + 1] = { kind = kind, part = part, found = KINDS[kind].seen }
            if kind == 'hemorrhage' then b.blood = b.blood - 15 end -- (they've been bleeding since before the call)
            if kind == 'airway' then b.airway = 'fouled' end
        end
    end
    b.blood = math.max(b.blood, 45)
    if (open(b, 'opioid') or open(b, 'head')) and b.airway ~= 'fouled' then b.airway = 'slack' end
end

-- Their heart stops where they lie (a shot to the head, say).
function Body.stop(b)
    if not b.arrest and not b.dead then arrest(b, 'dead') end
end

function Body.new(list, opts)
    opts = opts or {}
    local b = { t = 0, v = {}, cond = {}, blood = 100, exposed = {}, checked = {}, given = {}, effects = {}, low = {},
                rand = opts.rand or math.random, airway = 'clear', monitor = false, o2 = false, bvm = false }
    for k, v in pairs(BASE) do b.v[k] = v end
    Body.add(b, list)
    for k, v in pairs(target(b)) do b.v[k] = v end -- (the first look is already true)
    for k, v in pairs(target(b)) do b.v[k] = v end -- (twice: some targets read the vitals)
    set_rhythm(b)
    if opts.dead then
        arrest(b, 'dead')
        b.long_dead = true
    elseif opts.arrest then -- (just gone: what stopped their heart picks the rhythm)
        arrest(b, cond(b, 'cardiac') and 'cardiac' or open(b, 'hemorrhage') and 'hypovolemia'
            or (cond(b, 'opioid') or cond(b, 'airway') or cond(b, 'respiratory')) and 'hypoxia' or 'cardiac')
    end
    return b
end

local function move(cur, to, rate, dt)
    if math.abs(to - cur) <= rate * dt then return to end
    return cur + (to > cur and rate or -rate) * dt
end

function Body.tick(b, dt, hold)
    b.t = b.t + dt
    if b.monitor and b.nibp_at and b.t >= b.nibp_at then -- the cuff: a reading every 30 s, as it stands then
        b.nibp = b.arrest and { 0, 0 } or { math.floor(b.v.sys + 0.5), math.floor(b.v.sys * 0.65 + 0.5) }
        b.nibp_at = b.t + 30
    end
    if b.dead then return nil end
    if b.arrest then
        local a = b.arrest
        a.t = a.t + dt
        if a.cpr_end and b.t >= a.cpr_end and rhythm_check(b) == 'rosc' then return 'rosc' end
        b.v.etco2 = a.cpr_end and 15 or 4 -- (good compressions show on the EtCO2)
        b.v.spo2 = 0
        if a.t > cfg().dead_minutes * 60 then
            b.dead = true
            return 'dead'
        end
        return nil
    end
    if hold then return nil end
    -- bleeding
    local rate = 0
    for _, h in ipairs(b.cond) do
        if h.kind == 'hemorrhage' and not h.fixed then
            rate = rate + cfg().bleed * (LIMBS[h.part] and 1 or 1.4) * (1 + 0.5 * ((h.n or 1) - 1)) -- (more holes, faster)
        end
    end
    if rate > 0 then b.blood = math.max(40, b.blood - rate * (b.given.aspirin and 1.5 or 1) * dt) end
    local c = open(b, 'cardiac')
    if c and not b.given.aspirin then c.strain = (c.strain or 0) + dt end
    local t = target(b)
    for k, v in pairs(t) do b.v[k] = move(b.v[k], v, v < b.v[k] and FALL[k] or RATE[k], dt) end
    set_rhythm(b)
    -- 30 s of a deadly number, then the heart stops
    local low = b.low
    low.spo2 = b.v.spo2 < 70 and (low.spo2 or 0) + dt or nil
    low.sys = b.v.sys < 60 and (low.sys or 0) + dt or nil
    low.hr = b.v.hr > 170 and (low.hr or 0) + dt or nil
    if (low.hr or 0) >= 30 then arrest(b, on(b, 'epi_bad') and 'vt' or 'cardiac') return 'arrest' end
    if c and (c.strain or 0) > cfg().cardiac_minutes * 60 + 50 then arrest(b, 'cardiac') return 'arrest' end
    if (low.spo2 or 0) >= 30 then arrest(b, 'hypoxia') return 'arrest' end
    if (low.sys or 0) >= 30 then arrest(b, 'hypovolemia') return 'arrest' end
    return nil
end

-- ─── hands on ─────────────────────────────────────────────────────────────────

local function find(b, kind, part)
    local c = cond(b, kind, part)
    if not c then return nil end
    c.found = true
    return c
end

local ASSESS = {}

function ASSESS.hands(b, part)
    b.checked[part] = true
    local c = find(b, 'fracture', part) or (part == 'head' and find(b, 'head'))
    if c then return 'found', FOUND_TEXT[c.kind] end
    return 'nothing', 'Nothing broken or swollen.'
end

function ASSESS.shears(b, part)
    b.exposed[part] = true
    if part == 'thorax' and find(b, 'pneumothorax') then return 'found', FOUND_TEXT.pneumothorax end
    local c = find(b, 'hemorrhage', part)
    if c then return 'found', FOUND_TEXT.hemorrhage end
    return 'nothing', 'Clothes cut away. No wound here.'
end

function ASSESS.look(b, part)
    if part ~= 'head' then
        return 'nothing', b.exposed[part] and 'Nothing more to see.' or 'Cut the clothes away to see the skin.'
    end
    if b.airway == 'fouled' then
        find(b, 'airway')
        return 'found', FOUND_TEXT.airway
    end
    if airway_blocked(b) then return 'found', 'Snoring breaths: their tongue is blocking the airway.' end
    return 'nothing', 'Airway clear.'
end

-- b.heard: what's in the earpieces (server/ems.lua sends it, the screen plays it): 'normal' | 'chest' (wheezes and
-- crackles) | 'quiet' (one side gone) | 'gurgle' | 'stomach' | 'absent'
function ASSESS.stethoscope(b, part)
    b.heard = nil
    if part ~= 'thorax' then return 'nothing', 'Listen to the chest.' end
    if b.arrest then
        b.heard = 'absent'
        return 'nothing', 'No heart sounds.'
    end
    if b.tube == 'wrong' then
        b.tube_checked, b.heard = true, 'stomach'
        return 'found', 'No breath sounds, and gurgling over the stomach: the tube is in the wrong place.'
    end
    if b.tube then b.tube_checked = true end
    if b.airway == 'fouled' then
        b.heard = 'gurgle'
        return 'found', 'Gurgling in the airway.'
    end
    if find(b, 'pneumothorax') then
        b.heard = 'quiet'
        return 'found', FOUND_TEXT.pneumothorax
    end
    if find(b, 'respiratory') then
        b.heard = 'chest'
        return 'found', FOUND_TEXT.respiratory
    end
    b.heard = 'normal'
    if b.tube then return 'nothing', 'Breath sounds on both sides: the tube is in.' end
    return 'nothing', 'Clear breath sounds on both sides.'
end

function ASSESS.penlight(b, part)
    if part ~= 'head' then return 'nothing', 'Shine it in their eyes.' end
    b.pupils = true
    if find(b, 'opioid') then return 'found', FOUND_TEXT.opioid end
    if find(b, 'head') then return 'found', FOUND_TEXT.head end
    return 'nothing', 'Pupils equal and reacting.'
end

function ASSESS.glucometer(b, part)
    if not LIMBS[part] then return 'nothing', 'Prick a finger.' end
    b.sugar_known = true
    local reading = ('Blood sugar %.1f mmol/L.'):format(b.v.sugar)
    if find(b, 'hypoglycemia') then return 'found', reading .. ' Very low.' end
    return 'nothing', reading
end

function ASSESS.ask(b, part)
    if part ~= 'head' then return 'nothing', 'Talk to them.' end
    if b.arrest or b.v.gcs < 13 then return 'nothing', 'No sensible answer.' end
    local c = find(b, 'cardiac')
    if c then return 'found', FOUND_TEXT.cardiac end
    if pain(b) >= 0.4 then
        local p = find(b, 'pain')
        return 'found', p and FOUND_TEXT.pain or ('They rate their pain %d out of ten.'):format(math.floor(pain(b) * 10 + 0.5))
    end
    return 'nothing', "They say they're alright."
end

-- a pulse by hand: the wrist or the neck
function ASSESS.pulse(b, part)
    if part ~= 'neck' and part ~= 'lhand' and part ~= 'rhand' then return 'nothing', 'Feel the wrist or the neck.' end
    if b.arrest then return 'found', 'No pulse.' end
    b.hand_hr = math.floor(b.v.hr + 0.5)
    if b.v.hr < 50 then find(b, 'bradycardia') end
    local feel = b.v.sys < 90 and 'weak' or 'strong'
    return 'found', ('Pulse %d, %s.'):format(b.hand_hr, feel)
end

function ASSESS.monitor(b)
    if not b.monitor then b.nibp_at = b.t + 15 end -- (the cuff's first reading)
    b.monitor = true
    if b.v.hr < 50 then find(b, 'bradycardia') end
    return 'done', 'Monitor on: leads, SpO2, blood pressure cuff and EtCO2.'
end

local FIX = {}

function FIX.tourniquet(b, part)
    local c = cond(b, 'hemorrhage', part)
    if not LIMBS[part] then return 'wrong', 'A tourniquet goes on an arm or a leg.' end
    if not (c and c.found) then return 'nothing', 'No bleeding found there.' end
    c.fixed = true
    return 'done', 'Tourniquet on. The bleeding has stopped.'
end

function FIX.dressing(b, part)
    local c = cond(b, 'hemorrhage', part)
    if not (c and c.found) then return 'nothing', 'No bleeding found there.' end
    if LIMBS[part] then return 'wrong', 'It soaks straight through. A bleed like this needs a tourniquet.' end
    c.fixed = true
    return 'done', 'Packed and dressed. The bleeding has stopped.'
end

function FIX.chest_seal(b, part)
    if part ~= 'thorax' then return 'wrong', 'A chest seal goes over a wound to the chest.' end
    local c = cond(b, 'pneumothorax')
    if not (c and c.found) then return 'nothing', 'No open chest wound found.' end
    c.fixed = true
    return 'done', 'Chest seal on. Their breathing eases.'
end

function FIX.splint(b, part)
    local c = cond(b, 'fracture', part)
    if not (c and c.found) then return 'nothing', 'No fracture found there.' end
    c.fixed = true
    return 'done', 'Splinted.'
end

function FIX.suction(b)
    if b.airway ~= 'fouled' then return 'nothing', 'Nothing to suction.' end
    b.airway = 'slack'
    local c = cond(b, 'airway')
    if c then
        c.found = true
        if b.v.gcs > 8 then c.fixed = true end -- (awake: they hold it open themselves now)
    end
    return 'done', b.v.gcs > 8 and 'Suctioned clear. They can breathe.' or 'Suctioned clear. Keep it open.'
end

local function seat(b, kit, max_gcs, text)
    if b.airway == 'fouled' then return 'wrong', "It won't go in past the vomit. Suction first." end
    if b.v.gcs > max_gcs then
        if kit == 'opa' then
            b.airway = 'fouled'
            return 'harm', 'They gag and vomit. Too awake for that one.'
        end
        return 'wrong', "They're fighting it. Too awake for that."
    end
    b.airway_kit = kit
    local c = cond(b, 'airway')
    if c then c.fixed = true end
    return 'done', text
end

function FIX.opa(b) return seat(b, 'opa', 8, 'Oral airway in.') end
function FIX.npa(b) return seat(b, 'npa', 13, 'Nasal airway in.') end
function FIX.igel(b) return seat(b, 'igel', 8, 'i-gel in. Airway secured.') end

function FIX.laryngoscope(b)
    if b.airway == 'fouled' then return 'wrong', "You can't see anything past the vomit. Suction first." end
    if b.v.gcs > 8 then return 'wrong', "They're fighting it. Too awake to intubate." end
    b.scoped = true
    return 'done', 'Cords in view.'
end

function FIX.tube(b)
    if not b.scoped then return 'wrong', 'Laryngoscope first.' end
    b.scoped = nil
    b.tube = b.rand() < cfg().misplace and 'wrong' or 'right'
    if b.tube == 'wrong' then b.v.etco2 = 0 end -- (no CO2 comes back up a tube in the stomach: the trace goes flat at once)
    b.airway_kit = 'tube'
    b.tube_checked = nil
    local c = cond(b, 'airway')
    if c then c.fixed = true end
    return 'done', 'Tube in, cuff up. Confirm it: listen to the chest and watch the EtCO2.'
end

function FIX.pull_tube(b)
    if not b.tube then return 'nothing', 'No tube in.' end
    b.tube, b.airway_kit, b.tube_checked = nil, nil, nil
    local c = cond(b, 'airway')
    if c then c.fixed = nil end
    return 'done', 'Tube out.'
end

function FIX.bvm(b)
    b.bvm = not b.bvm
    return 'done', b.bvm and 'Bagging them.' or 'Stopped bagging.'
end

-- CPR runs a cycle (a two-minute one, sped up to Config.Ems.cpr_seconds), with a rhythm check at the end.
function FIX.cpr(b)
    local a = b.arrest
    if not a then return 'wrong', 'They have a pulse.' end
    if a.cpr_end then return 'nothing', 'Already doing compressions.' end
    a.cpr_end = b.t + cfg().cpr_seconds
    b.v.etco2 = 15
    return 'done', 'Compressions. Rhythm check in ' .. cfg().cpr_seconds .. ' s.'
end

-- The end of a cycle: what the rhythm is now. The medic hears it through b.note. -> 'rosc' | nil
function rhythm_check(b)
    local a = b.arrest
    a.cpr_end, a.cprs, a.since_shock = nil, a.cprs + 1, a.since_shock + 1
    if SHOCKABLE[a.rhythm] then
        b.note = { kind = 'no_rosc', text = 'Rhythm check: ' .. a.rhythm:upper() .. '. Shock.' }
        return nil
    end
    -- non-shockable: with epi on board, a cycle sometimes brings them back, or turns it into VF
    local chance = (a.epi and b.t - a.epi < 300) and 0.2 or 0.05
    if not reversible(b) then chance = chance / 2 end
    if b.long_dead then chance = chance * cfg().revive end
    local r = b.rand()
    if r < chance then
        rosc(b)
        b.note = { kind = 'rosc', text = 'Rhythm check: a pulse! Return of circulation.' }
        return 'rosc'
    end
    if r < chance + 0.15 then
        a.rhythm, b.rhythm = 'vf', 'vf'
        b.note = { kind = 'no_rosc', text = 'Rhythm check: it has changed to VF. Shock.' }
        return nil
    end
    b.note = { kind = 'no_rosc', text = 'Rhythm check: still ' .. (a.rhythm == 'pea' and 'PEA' or 'asystole') .. '. Back on the chest.' }
    return nil
end

function FIX.defib(b)
    local a = b.arrest
    if not b.monitor then -- (the pads come first: the monitor and the defib are one box)
        ASSESS.monitor(b)
        return 'done', 'Pads on. Read the rhythm.'
    end
    if not a then return 'harm', "Shocking someone with a pulse: don't." end
    if not SHOCKABLE[a.rhythm] then return 'not_shockable', 'No shock advised. Continue CPR.' end
    a.cpr_end = nil -- (hands off for the shock)
    local chance = 0.25 + (a.since_shock > 0 and 0.15 or 0) + ((a.epi and b.t - a.epi < 300) and 0.15 or 0)
    if not reversible(b) then chance = chance - 0.15 end
    if b.long_dead then chance = chance * cfg().revive end
    a.since_shock = 0
    if b.rand() < chance then
        rosc(b)
        return 'rosc', 'Shock delivered. A pulse! Return of circulation.'
    end
    return 'no_rosc', 'Shock delivered. Still in ' .. a.rhythm:upper() .. '. CPR.'
end

-- ─── drugs ────────────────────────────────────────────────────────────────────

local DRUG = {}

function DRUG.morphine(b)
    if b.arrest then return 'wrong', 'Not in an arrest.' end
    if b.v.sys < 100 or b.v.rr < 12 then
        give(b, 'morphine', 30, 600)
        give(b, 'morphine_bad', 30, 300)
        return 'harm', 'Morphine given.'
    end
    give(b, 'morphine', 30, 600)
    local c = cond(b, 'pain')
    if c then c.fixed = true end
    return 'done', 'Morphine given.'
end

function DRUG.epi(b)
    if b.arrest then
        local a = b.arrest
        if a.epi and b.t - a.epi < 180 then return 'done', 'Epi given. Too soon: every three to five minutes.' end -- (no better for it)
        a.epi = b.t
        return 'done', 'Epi given.'
    end
    if b.v.hr > 120 then
        give(b, 'epi_bad', 20, 180)
        return 'harm', 'Epi given.'
    end
    give(b, 'epi', 20, 300)
    local c = cond(b, 'bradycardia')
    if c then c.fixed = true end
    return 'done', 'Epi given.'
end

function DRUG.narcan(b)
    give(b, 'narcan', 40, 300)
    local c = cond(b, 'opioid')
    if c then c.treated = true end -- (treated, not gone: it wears off before the drug does)
    return c and 'done' or 'nothing', 'Narcan given.'
end

function DRUG.oxygen(b)
    b.o2 = true
    local c = cond(b, 'respiratory')
    if c and c.found then c.fixed = true end
    return 'done', 'Oxygen on.'
end

function DRUG.glucose(b)
    local c = cond(b, 'hypoglycemia')
    if c then c.fixed = true end
    return c and 'done' or 'nothing', 'Glucose given.'
end

function DRUG.saline(b)
    give(b, 'saline', 30, 900)
    return 'done', 'Saline running.'
end

function DRUG.aspirin(b)
    local c = cond(b, 'cardiac')
    if c then c.fixed = true end
    if open(b, 'hemorrhage') then return 'harm', 'Aspirin given.' end
    return c and 'done' or 'nothing', 'Aspirin given.'
end

-- tool on part -> kind, text
function Body.act(b, tool, part)
    if b.dead then return 'nothing', 'They are gone.' end
    local fn = ASSESS[tool] or FIX[tool] or DRUG[tool]
    if not fn then return 'nothing', 'Nothing happens.' end
    if DRUGS[tool] then
        b.given[tool] = (b.given[tool] or 0) + 1
        b.given_at = b.given_at or {}
        b.given_at[tool] = b.t -- (the screen counts from the last dose: epi every three to five minutes)
    end
    return fn(b, part)
end

-- ─── what the medic's game sees ───────────────────────────────────────────────

local function alarms(b)
    local a, v = {}, b.v
    if b.arrest then return { 'ARREST' } end
    if v.hr > 140 then a[#a + 1] = 'HR HIGH' elseif v.hr < 45 then a[#a + 1] = 'HR LOW' end
    if b.nibp and b.nibp[1] < 90 then a[#a + 1] = 'BP LOW' end -- (the cuff's last reading: that's all the monitor knows)
    if v.spo2 < 90 then a[#a + 1] = 'SPO2 LOW' end
    if v.rr < 8 then a[#a + 1] = 'RESP LOW' elseif v.rr > 30 then a[#a + 1] = 'RESP HIGH' end
    if b.tube and v.etco2 < 10 then a[#a + 1] = 'NO ETCO2' end
    return a
end

local function round(x) return math.floor(x + 0.5) end

function Body.view(b)
    local found = {}
    for _, c in ipairs(b.cond) do
        if c.found then
            local text = FOUND_TEXT[c.kind] .. ((c.n or 1) > 1 and (' %d wounds.'):format(c.n) or '')
            found[#found + 1] = { kind = c.kind, part = c.part, text = text, fixed = c.fixed == true or c.treated == true }
        end
    end
    local v = b.v
    local view = { found = found, arrest = b.arrest ~= nil, dead = b.dead == true, stable = Body.stable(b),
                   airway = b.airway_kit, bvm = b.bvm, o2 = b.o2, hand_hr = b.hand_hr, given = {},
                   cpr = b.arrest and b.arrest.cpr_end and round(b.arrest.cpr_end - b.t) or nil }
    for drug, n in pairs(b.given) do
        view.given[#view.given + 1] = { id = drug, n = n, ago = round(b.t - (b.given_at and b.given_at[drug] or b.t)) }
    end
    table.sort(view.given, function(x, y) return x.ago < y.ago end)
    if b.monitor then
        view.monitor = {
            hr = (b.arrest and (b.arrest.rhythm == 'vf' or b.arrest.rhythm == 'asystole')) and 0 or round(v.hr),
            sys = b.nibp and b.nibp[1], dia = b.nibp and b.nibp[2], cuff = b.nibp_at ~= nil and b.nibp_at - b.t <= 6, spo2 = b.arrest and 0 or round(v.spo2), rr = round(v.rr),
            etco2 = round(v.etco2), rhythm = b.rhythm, alarms = alarms(b),
        }
    end
    return view
end

-- Ready to move: no arrest, nothing serious left found-and-not-handled or not found, and holding numbers.
function Body.stable(b)
    if b.arrest or b.dead then return false end
    for _, c in ipairs(b.cond) do
        if KINDS[c.kind].serious and not (c.found and (c.fixed or c.treated)) then return false end
    end
    if airway_blocked(b) or b.tube == 'wrong' then return false end
    return b.v.spo2 >= 90 and b.v.sys >= 90
end

-- The next useful thing, in the order medics work: airway, breathing, circulation, the monitor, disability, the rest,
-- drugs. Uses the truth, but says only what to check, never what's there.
function Body.hint(b) -- -> text, tool?, part? (the screen lights that tool and that part; 'pronounce': its button)
    local v = b.v
    if b.dead then return 'They are gone. Pronounce them.', 'pronounce' end
    if b.arrest then
        local a = b.arrest
        if not b.monitor then return 'No pulse: put the defib pads on to see the rhythm.', 'defib' end
        if SHOCKABLE[a.rhythm] and not a.cpr_end then return 'Shockable rhythm: shock, then a cycle of CPR.', 'defib' end
        if not a.cpr_end then return 'No shockable rhythm: start CPR.', 'cpr' end
        if (a.cprs > 0 or not SHOCKABLE[a.rhythm]) and (not a.epi or b.t - a.epi >= 240) then return 'Give epi: every three to five minutes.', 'epi' end
        if a.t > 600 then return "A long time without a pulse. You can pronounce them.", 'pronounce' end
        return 'Keep the compressions going until the rhythm check.'
    end
    if b.tube and not b.tube_checked then return 'Confirm the tube: listen to the chest and watch the EtCO2.', 'stethoscope', 'thorax' end
    if b.tube == 'wrong' then return 'The tube is in the wrong place: pull it and try again.', 'pull_tube' end
    if not b.checked_airway and airway_blocked(b) then return 'Check their airway: look in their mouth.', 'look', 'head' end
    if b.airway == 'fouled' then return 'Suction their airway.', 'suction' end
    if airway_blocked(b) then return 'Keep their airway open: a nasal airway works awake or not.', 'npa' end
    if v.rr < 8 and not b.bvm then return "They're barely breathing: bag them with the BVM.", 'bvm' end
    local r = cond(b, 'respiratory')
    if r and not r.found then return 'Listen to their chest.', 'stethoscope', 'thorax' end
    local pn = open(b, 'pneumothorax')
    if pn and not pn.found then return 'Listen to their chest.', 'stethoscope', 'thorax' end
    if pn then return 'An open chest wound: seal it.', 'chest_seal', 'thorax' end
    if v.spo2 < 94 and not b.o2 then return 'Put them on oxygen.', 'oxygen' end
    local h = open(b, 'hemorrhage')
    if h and not h.found then return 'Check for bleeding: cut the clothes away.', 'shears', h.part end
    if h then
        if LIMBS[h.part] then return 'Stop the bleeding: a tourniquet, above the wound.', 'tourniquet', h.part end
        return 'Stop the bleeding: pack it and press a dressing on.', 'dressing', h.part
    end
    if 100 - b.blood > 20 and v.sys < 100 and not coming(b, 'saline') then return 'They have lost a lot of blood: give saline.', 'saline' end
    if not b.monitor then return 'Put the monitor on.', 'monitor' end
    if on(b, 'epi_bad') then return 'The epi has their heart racing. Let it settle, and be ready to shock.' end
    if on(b, 'morphine_bad') and v.rr < 12 then return 'The morphine is slowing their breathing. Bag them if it drops further.', 'bvm' end
    if (cond(b, 'opioid') or cond(b, 'head')) and not b.pupils then return 'Check their pupils.', 'penlight', 'head' end
    if v.gcs < 15 and not b.sugar_known then return 'Not fully awake: check their blood sugar.', 'glucometer', 'lhand' end
    local f = open(b, 'fracture')
    if f and not f.found then return 'Feel each limb for breaks.', 'hands', f.part end
    if f then return 'Splint the fracture.', 'splint', f.part end
    local c = cond(b, 'cardiac')
    if (c or cond(b, 'pain')) and v.gcs >= 13 and not b.asked then return 'Ask them where it hurts.', 'ask', 'head' end
    local o = open(b, 'opioid')
    if o and not coming(b, 'narcan') then return o.treated and 'The Narcan is wearing off: give another dose.' or 'Give Narcan.', 'narcan' end
    if open(b, 'hypoglycemia') then return 'Give glucose.', 'glucose' end
    if open(b, 'cardiac') then return 'Give aspirin.', 'aspirin' end
    if open(b, 'bradycardia') then return 'Their heart is too slow: give epi.', 'epi' end
    if open(b, 'pain') then
        if v.sys >= 100 and v.rr >= 12 then return 'Give morphine for the pain.', 'morphine' end
        return 'In pain, but their blood pressure or breathing is too low for morphine.'
    end
    if Body.stable(b) then return 'Stable. Get the stretcher.' end
    return 'Keep watching the monitor.'
end

-- (the hint knows what's been looked at)
local look, ask = ASSESS.look, ASSESS.ask
ASSESS.look = function(b, part) if part == 'head' then b.checked_airway = true end return look(b, part) end
ASSESS.ask = function(b, part) if part == 'head' then b.asked = true end return ask(b, part) end
