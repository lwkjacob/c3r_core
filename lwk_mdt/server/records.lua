--[[
    lwk_mdt — Records: c3r records -> MDT records, findings, report narrative, search matching.
    Pure Lua (no FiveM calls), so tools/records_test.lua can run it outside the game.
]]

Records = {}

local function trim(s)
    if type(s) == 'number' then s = tostring(s) end
    return type(s) == 'string' and s:match('^%s*(.-)%s*$') or nil
end

-- Trimmed, capped string or nil when empty: every value from c3r or a client goes through this.
function Records.str(s, max)
    s = trim(s)
    if not s or s == '' then return nil end
    return s:sub(1, max or 80)
end
local str = Records.str

local function bool(v) if type(v) == 'boolean' then return v end end

function Records.plate_key(s)
    s = str(s, 16)
    return s and (s:upper():gsub('%s+', '')) or nil
end

-- A list of flag names (c3r), or a { name = true } map (older civilian records).
local function flag_labels(f)
    local out = {}
    local function add(name)
        name = str(name, 40)
        if name then out[#out + 1] = name:gsub('_', ' '):upper() end
    end
    if type(f) == 'string' then add(f)
    elseif type(f) == 'table' then
        for k, v in pairs(f) do
            if type(k) == 'number' then add(v) elseif v then add(k) end
        end
    end
    table.sort(out)
    return out
end

-- Same name + DOB = same person. c3r keeps its population, so the same driver turns up again: that is
-- what makes prior contacts work. p = a c3r person record.
function Records.person(p)
    if type(p) ~= 'table' then return nil end
    local first, last, dob = str(p.first, 40), str(p.last, 40), str(p.dob, 20)
    if not first and not last then return nil end
    return {
        key = ((first or '') .. '|' .. (last or '') .. '|' .. (dob or '')):lower(), pd_id = tonumber(p.id),
        first = first, last = last, dob = dob, gender = str(p.gender, 20), address = str(p.address, 80),
        dl = str(p.dl, 30), dl_valid = bool(p.dl_valid), flags = flag_labels(p.flags),
        warrant = str(p.warrant, 120) or false, -- (false, not nil: a served warrant has to overwrite the copy on file)
        unverified = p.unverified == true or nil, -- a name they gave that has no record behind it
    }
end

-- v = a c3r vehicle record
function Records.vehicle(v)
    if type(v) ~= 'table' then return nil end
    local plate = Records.plate_key(v.plate)
    if not plate then return nil end
    return {
        plate = plate, pd_id = tonumber(v.id), make = str(v.make, 30), model = str(v.model, 30), color = str(v.color, 30),
        year = str(v.year, 4), owner = str(v.owner, 60), owner_id = tonumber(v.owner_id),
        reg_valid = bool(v.reg_valid), ins_valid = bool(v.ins_valid),
        stolen = bool(v.stolen), bolo = bool(v.bolo), bolo_reason = str(v.bolo_reason, 120),
    }
end

-- New values win; fields the new record doesn't have (a plate check sends only a plate) are kept.
function Records.merge(old, new)
    if not old then return new end
    for k, v in pairs(new) do old[k] = v end
    return old
end

function Records.person_name(p) return ((p.first or '') .. ' ' .. (p.last or '')):match('^%s*(.-)%s*$') end

function Records.person_desc(p)
    return Records.person_name(p) .. (p.dob and (' (DOB ' .. p.dob .. ')') or '')
end

function Records.vehicle_desc(v)
    local parts = {}
    for _, k in ipairs({ 'year', 'color', 'make', 'model' }) do
        if v[k] then parts[#parts + 1] = v[k] end
    end
    return (#parts > 0 and table.concat(parts, ' ') .. ' ' or '') .. '(' .. v.plate .. ')'
end

function Records.person_findings(p)
    local out = {}
    if p.unverified then out[#out + 1] = 'NO RECORD ON FILE' end
    if p.warrant then out[#out + 1] = 'ACTIVE WARRANT: ' .. p.warrant end
    for _, f in ipairs(p.flags or {}) do out[#out + 1] = f end
    if p.dl_valid == false then out[#out + 1] = 'licence ' .. (p.dl or 'invalid'):lower() end
    return out
end

function Records.vehicle_findings(v)
    local out = {}
    if v.stolen then out[#out + 1] = 'STOLEN' end
    if v.bolo then out[#out + 1] = 'BOLO' .. (v.bolo_reason and (': ' .. v.bolo_reason) or '') end
    if v.reg_valid == false then out[#out + 1] = 'registration invalid' end
    if v.ins_valid == false then out[#out + 1] = 'uninsured' end
    return out
end

local function findings_text(list) return #list > 0 and table.concat(list, ', ') or 'clear' end
Records.findings_text = findings_text

-- ─── lwk_control intents -> timeline lines ───────────────────────────────────

local SERVICES = {
    ambulance = 'Ambulance', police = 'Prisoner transport', tow = 'Tow truck', coroner = 'Coroner',
    fire = 'Fire department', mechanic = 'Mechanic', roadservice = 'Road service',
    animalrescue = 'Animal control', taxi = 'Taxi', dot = 'DOT crew',
}

local ACTIONS = {
    hold_traffic = 'Traffic held', release_traffic = 'Traffic released', cancel_traffic_hold = 'Traffic released',
    air_support = 'Air support requested', cancel_backup = 'Backup cancelled', panic = '10-99, officer down',
    complete_callout = 'Code 4, scene clear',
    ['status_10-8'] = 'In service (10-8)', ['status_10-6'] = 'Busy (10-6)', ['status_10-97'] = 'On scene (10-97)',
}

-- Plate and name checks need the records, so the server words those itself.
function Records.action_text(id, ctx)
    if type(id) ~= 'string' then return nil end
    local t = id:match('^request_(.+)$')
    if t and SERVICES[t] then return SERVICES[t] .. ' requested' end
    t = id:match('^cancel_(.+)$')
    if t and SERVICES[t] then return SERVICES[t] .. ' cancelled' end
    if id == 'pursuit_backup' then
        local code = type(ctx) == 'table' and str(ctx.code, 8)
        return 'Backup requested' .. (code and (', code ' .. code) or '')
    end
    return ACTIONS[id]
end

-- ─── reports ─────────────────────────────────────────────────────────────────

Records.KIND = {
    stop = 'Traffic stop', callout = 'Callout', pursuit = 'Vehicle pursuit', contact = 'Field contact', manual = 'Report',
    call911 = '911 Call', patient = 'Patient care',
}
Records.FORMS = { warning = 'Written Warning', citation = 'Citation', arrest = 'Arrest Report', incident = 'Incident Report',
                  pcr = 'Patient Care Report' }
Records.FORM_ORDER = { 'warning', 'citation', 'arrest', 'incident' } -- the order the form picker shows

function Records.default_form(inc)
    if inc.kind == 'patient' then return 'pcr' end
    return inc.kind == 'stop' and 'citation' or inc.kind == 'pursuit' and 'arrest' or 'incident'
end

-- c3r's patient report (c3r:patientReport) -> what's kept on the incident: every value checked, lists capped.
local function vitals_set(v)
    if type(v) ~= 'table' then return nil end
    local n = function(x) return math.type(tonumber(x)) and tonumber(x) or (tonumber(x) and math.floor(tonumber(x) + 0.5)) or nil end
    return { t = n(v.t), hr = n(v.hr), sys = n(v.sys), dia = n(v.dia), spo2 = n(v.spo2), rr = n(v.rr), etco2 = n(v.etco2),
             gcs = n(v.gcs), rhythm = str(v.rhythm, 40) }
end
function Records.pcr(r)
    r = type(r) == 'table' and r or {}
    local out = { complaint = str(r.complaint, 60), says = str(r.says, 200), contact = tonumber(r.contact),
                  left_scene = tonumber(r.left_scene), ended = tonumber(r.ended), hospital = str(r.hospital, 40),
                  outcome = (r.outcome == 'transported' or r.outcome == 'pronounced') and r.outcome or nil,
                  arrested = r.arrested == true, rosc = r.rosc == true, first = vitals_set(r.first), last = vitals_set(r.last),
                  findings = {}, care = {} }
    for _, f in ipairs(type(r.findings) == 'table' and r.findings or {}) do
        if #out.findings < 20 and type(f) == 'table' and str(f.text, 160) then
            out.findings[#out.findings + 1] = { part = str(f.part, 20), text = str(f.text, 160), treated = f.treated == true }
        end
    end
    for _, c in ipairs(type(r.care) == 'table' and r.care or {}) do
        if #out.care < 80 and type(c) == 'table' and str(c.text, 160) then
            out.care[#out.care + 1] = { t = tonumber(c.t) or 0, text = str(c.text, 160) }
        end
    end
    return out
end

local function vitals_text(v)
    if not v then return nil end
    local bits = { 'HR ' .. (v.hr or '-'), v.sys and ('BP %d/%d'):format(v.sys, v.dia or 0) or 'BP not taken',
                   'SpO2 ' .. (v.spo2 or '-') .. '%', 'RR ' .. (v.rr or '-'), 'EtCO2 ' .. (v.etco2 or '-'), 'GCS ' .. (v.gcs or '-') }
    return table.concat(bits, ', ') .. (v.rhythm and (', ' .. v.rhythm) or '') .. (v.t and (' (' .. os.date('%H:%M', v.t) .. ')') or '')
end
local function cap(s) return s and (s:sub(1, 1):upper() .. s:sub(2)) or s end

-- A patient care report's narrative, CHART: Chief complaint, History, Assessment, Rx (treatment), Transport.
function Records.pcr_narrative(inc, people, date_fmt)
    local r, p = inc.pcr or {}, people[1]
    local L = {}
    local function add(s) L[#L + 1] = s end
    add('C - CHIEF COMPLAINT: ' .. (r.complaint or inc.title or 'Unknown') .. '.')
    add('')
    local who = p and (Records.person_name(p) .. (p.dob and (', DOB ' .. p.dob) or '') .. (p.gender and (', ' .. p.gender:lower()) or ''))
    add('H - HISTORY: ' .. (who or 'Unidentified patient') .. '. Patient contact at ' .. os.date('%H:%M', r.contact or inc.started)
        .. (inc.location and (', ' .. inc.location) or '') .. ', on ' .. os.date(date_fmt or '%m/%d/%Y', inc.started) .. '.'
        .. (r.says and (' On arrival: ' .. r.says) or ''))
    add('')
    add('A - ASSESSMENT:')
    if #(r.findings or {}) == 0 then add('No injuries or illness found on assessment.') end
    for _, f in ipairs(r.findings or {}) do add(cap(f.part or 'General') .. ': ' .. f.text) end
    if r.first then add('Initial vitals: ' .. vitals_text(r.first) .. '.') end
    if r.last then add('Final vitals: ' .. vitals_text(r.last) .. '.') end
    if r.arrested then add('Patient was in cardiac arrest during care' .. (r.rosc and '; circulation was restored.' or '.')) end
    add('')
    add('R - TREATMENT:')
    if #(r.care or {}) == 0 then add('None.') end
    for _, c in ipairs(r.care or {}) do add(os.date('%H:%M', c.t) .. '  ' .. c.text) end
    add('')
    if r.outcome == 'pronounced' then
        add('T - DISPOSITION: Pronounced dead at ' .. os.date('%H:%M', r.ended or inc.updated)
            .. (r.arrested and ' after resuscitation was unsuccessful.' or '.'))
    elseif r.outcome == 'transported' then
        local mins = r.contact and r.ended and math.max(1, math.floor((r.ended - r.contact) / 60 + 0.5))
        local scene = r.contact and r.left_scene and math.max(1, math.floor((r.left_scene - r.contact) / 60 + 0.5))
        add('T - TRANSPORT: Transported to ' .. (r.hospital and (r.hospital .. ' hospital') or 'hospital') .. '. Care handed over at '
            .. os.date('%H:%M', r.ended or inc.updated) .. (mins and (', ' .. mins .. ' min after patient contact') or '')
            .. (scene and (' (' .. scene .. ' min on scene)') or '') .. '.')
    else
        add('T - TRANSPORT: ')
    end
    return table.concat(L, '\n')
end

-- The draft an officer starts from: who, what, where, then the timeline.
-- people / vehicles: records in the order they joined the incident.
function Records.narrative(inc, people, vehicles, date_fmt)
    if inc.kind == 'patient' then return Records.pcr_narrative(inc, people, date_fmt) end
    local lines = {}
    local head = (Records.KIND[inc.kind] or 'Incident') .. (inc.title and (': ' .. inc.title) or '')
        .. ' handled by ' .. (inc.officer or 'unknown unit')
        .. (inc.location and (' at ' .. inc.location) or '')
        .. ' on ' .. os.date(date_fmt or '%m/%d/%Y', inc.started) .. '.'
    lines[1] = head
    for _, v in ipairs(vehicles) do
        lines[#lines + 1] = 'Vehicle: ' .. Records.vehicle_desc(v) .. (v.owner and (', registered to ' .. v.owner) or '')
            .. '. Return: ' .. findings_text(Records.vehicle_findings(v)) .. '.'
    end
    for _, p in ipairs(people) do
        lines[#lines + 1] = 'Subject: ' .. Records.person_desc(p) .. '. Return: ' .. findings_text(Records.person_findings(p)) .. '.'
    end
    if #inc.events > 0 then
        lines[#lines + 1] = ''
        for _, e in ipairs(inc.events) do lines[#lines + 1] = os.date('%H:%M', e.t) .. '  ' .. e.text end
    end
    if inc.dialogue and #inc.dialogue > 0 then -- spoken exchanges from lwk_npcai
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Dialogue:'
        for _, d in ipairs(inc.dialogue) do
            lines[#lines + 1] = os.date('%H:%M', d.t) .. '  ' .. d.who .. ': "' .. d.text .. '"'
        end
    end
    return table.concat(lines, '\n')
end

-- Charges picked in the UI (ids like "VC 22348(a)") -> copies of the config entries, and the fine total.
-- Unknown ids are dropped, so a client can't invent a charge or a fine.
function Records.charge_id(c) return c.code .. ' ' .. c.section end

function Records.charges(ids, list)
    local by_id, out, total, seen = {}, {}, 0, {}
    for _, c in ipairs(list) do by_id[Records.charge_id(c)] = c end
    for _, id in ipairs(type(ids) == 'table' and ids or {}) do
        local c = type(id) == 'string' and by_id[id]
        if c and not seen[id] then
            seen[id] = true
            out[#out + 1] = { id = id, label = c.label, class = c.class, fine = tonumber(c.fine) or 0 }
            total = total + (tonumber(c.fine) or 0)
        end
    end
    return out, total
end

Records.EVADING = 'Evading an officer'

local LET_GO = { released = true, cited = true, warning = true } -- a stop that ended with them walking free

-- Who a signed report puts a warrant on: an Arrest Report for whoever got away (inc.fled, c3r person ids), or with
-- charges, the one person on it if they walked free (more than one: a report doesn't say whose charges they are;
-- nothing known of how it ended, a stop still open or walked away from: they may be in cuffs). A report written by
-- hand is the officer's word. people = the MDT's records by key. -> ids, reason
function Records.wanted(inc, people)
    if (inc.form or Records.default_form(inc)) ~= 'arrest' then return {} end
    local labels = {}
    for _, c in ipairs(inc.charges or {}) do labels[#labels + 1] = c.label end
    -- (someone arrested too: the charges are theirs, the one who got away evaded)
    local reason = #labels > 0 and inc.outcome ~= 'arrested' and table.concat(labels, ', '):sub(1, 120) or Records.EVADING
    if inc.fled then return inc.fled, reason end
    local p = #inc.people == 1 and people[inc.people[1]]
    if not p or not p.pd_id or #labels == 0 or inc.kind == 'callout' then return {} end
    if inc.kind ~= 'manual' and not LET_GO[inc.outcome] then return {} end
    return { p.pd_id }, reason
end

-- ─── search ──────────────────────────────────────────────────────────────────

function Records.terms(q)
    local out = {}
    for w in (str(q, 60) or ''):lower():gmatch('%S+') do out[#out + 1] = w end
    return out
end

-- Every term must appear in the first or last name.
function Records.match_person(p, terms)
    if #terms == 0 then return false end
    local hay = ((p.first or '') .. ' ' .. (p.last or '')):lower()
    for _, t in ipairs(terms) do
        if not hay:find(t, 1, true) then return false end
    end
    return true
end

function Records.match_vehicle(v, q)
    local plate = Records.plate_key(q)
    return plate ~= nil and #plate >= 2 and v.plate:find(plate, 1, true) ~= nil
end

-- Keeps a list of ids unique and capped (oldest dropped).
function Records.add_unique(list, value, cap)
    list = list or {}
    for _, v in ipairs(list) do
        if v == value then return list end
    end
    list[#list + 1] = value
    while #list > (cap or 50) do table.remove(list, 1) end
    return list
end
