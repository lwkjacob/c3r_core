--[[
    lwk_mdt — server: encounter log in SQL, c3r + lwk_control events -> incidents, MDT requests.

    An incident is one stop, callout, pursuit or field contact, and it is also its report:
      open   -> still happening, c3r and radio events keep landing on its timeline
      draft  -> closed, waiting for the officer to review and sign
      signed -> locked; only its author or a supervisor can edit or delete it
    narrative = nil means "auto": it is rebuilt from the timeline every time the report is read.
]]

local People, Vehicles, Incidents = {}, {}, {} -- [key] / [plate] / [id]
local Open = {}     -- [src] = id of the officer's open incident
local Callsign = {} -- [src] = the callsign they signed on with (also on their lwkMdtCallsign state bag), or ''
local WebShow = {}  -- [src] = record a radio check opened, waiting for the officer's browser pop-out
local Meta = {}     -- [key] = value: 'seq' (last incident id), 'active:<licence>' (active civilian character)
local seq = 0
local loaded = false

local str = Records.str

local function log(fmt, ...)
    if Config.Debug then print(('[lwk_mdt] ' .. fmt):format(...)) end
end

-- ─── storage ─────────────────────────────────────────────────────────────────
-- Records live in memory and go to SQL (oxmysql) in one transaction every 5 s: the latest version of each
-- changed record, so writes can't land out of order. Tables are created on start.
-- ponytail: every record is loaded on start; move search and history to SQL queries if a server
-- outgrows Config.KeepDays / Config.MaxIncidents.

local TABLES = { p = 'lwk_mdt_people', v = 'lwk_mdt_vehicles', i = 'lwk_mdt_incidents', m = 'lwk_mdt_meta' }
local Dirty = {} -- [kind:key] = { kind, key, record | false (delete) }

local function save(kind, key, rec) Dirty[kind .. ':' .. key] = { kind, key, rec } end
local function forget(kind, key) Dirty[kind .. ':' .. key] = { kind, key, false } end
local function save_inc(inc) save('i', inc.id, inc) end

local function set_meta(key, value)
    Meta[key] = value
    if value == nil then forget('m', key) else save('m', key, { v = value }) end
end

local function next_id()
    seq = seq + 1
    set_meta('seq', seq)
    return seq
end

local function flush()
    if not next(Dirty) then return end
    local batch, queries = Dirty, {}
    Dirty = {}
    for _, d in pairs(batch) do
        local t = TABLES[d[1]]
        if d[3] == false then
            queries[#queries + 1] = { query = 'DELETE FROM ' .. t .. ' WHERE k = ?', values = { tostring(d[2]) } }
        else
            queries[#queries + 1] = { query = 'REPLACE INTO ' .. t .. ' (k, data) VALUES (?, ?)',
                                      values = { tostring(d[2]), json.encode(d[3]) } }
        end
    end
    if not MySQL.transaction.await(queries) then
        for k, d in pairs(batch) do Dirty[k] = Dirty[k] or d end -- a newer change wins over the retry
        print('[lwk_mdt] saving to SQL failed, retrying in 5 s')
    end
end

-- field = the record field that keys `into`; nil for meta rows ({ v = value }, keyed by k)
local function load(kind, into, field)
    for _, row in ipairs(MySQL.query.await('SELECT k, data FROM ' .. TABLES[kind]) or {}) do
        local ok, rec = pcall(json.decode, row.data or '')
        if ok and type(rec) == 'table' then
            if not field then into[row.k] = rec.v elseif rec[field] then into[rec[field]] = rec end
        end
    end
end

MySQL.ready(function()
    for _, t in pairs(TABLES) do
        MySQL.query.await('CREATE TABLE IF NOT EXISTS ' .. t .. ' (k VARCHAR(191) PRIMARY KEY, data LONGTEXT NOT NULL)')
    end
    load('p', People, 'key')
    load('v', Vehicles, 'plate')
    load('i', Incidents, 'id')
    load('m', Meta)
    seq = tonumber(Meta.seq) or 0

    -- prune: age first, then the oldest incidents over the cap
    local cutoff = Config.KeepDays > 0 and os.time() - Config.KeepDays * 86400 or 0
    local list = {}
    for id, inc in pairs(Incidents) do
        if (inc.updated or inc.started or 0) < cutoff then Incidents[id] = nil forget('i', id)
        else
            if inc.status == 'open' then inc.status = 'draft' save_inc(inc) end -- server stopped mid-incident
            if inc.status == 'pending' then Incidents[id] = nil forget('i', id) else list[#list + 1] = inc end -- stale 911
        end
    end
    table.sort(list, function(a, b) return a.started < b.started end)
    for i = 1, #list - Config.MaxIncidents do Incidents[list[i].id] = nil forget('i', list[i].id) end
    for _, set in ipairs({ { People, 'p' }, { Vehicles, 'v' } }) do
        for k, rec in pairs(set[1]) do
            if not rec.civ and (rec.last_seen or 0) < cutoff then set[1][k] = nil forget(set[2], k) end -- civ: player-made, kept
        end
    end
    local n = 0
    for _ in pairs(Incidents) do n = n + 1 end
    loaded = true
    print(('[lwk_mdt] %d incidents loaded'):format(n))
end)

-- Anything that writes waits for the records first, or it would hand out ids that are already taken.
local function wait_loaded()
    while not loaded do Wait(100) end
end

CreateThread(function()
    while true do
        Wait(5000)
        flush()
    end
end)

-- ─── permissions ─────────────────────────────────────────────────────────────

local function license(src) return GetPlayerIdentifierByType(src, 'license') or ('player:' .. GetPlayerName(src)) end
local function supervisor(src) return src == 0 or IsPlayerAceAllowed(src, Config.SupervisorAce) end

local function admin(src)
    if supervisor(src) then return true end
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        for _, a in ipairs(Config.Admins or {}) do
            if id == a then return true end
        end
    end
    return false
end
local function can_use(src) return not Config.AcePermission or IsPlayerAceAllowed(src, Config.AcePermission) end
local function can_edit(src, inc) -- (units who joined a callout can add to its report too)
    if inc.author == license(src) or supervisor(src) then return true end
    for _, l in ipairs(inc.assist or {}) do if l == license(src) then return true end end
    return false
end

-- Signed on this session: the player's state bag outlasts a restart of this resource, but not a rejoin.
local function signed_on(src) return Player(src).state.lwkMdtCallsign end

local function officer(src)
    local cs = Callsign[src]
    if not cs or cs == '' then cs = signed_on(src) end
    return cs and cs ~= '' and cs or GetPlayerName(src) or ('Unit ' .. src)
end

-- ─── incidents ───────────────────────────────────────────────────────────────

local function current(src) return Open[src] and Incidents[Open[src]] end

-- Takes an incident off whichever officer has it open (it stays on file).
local function detach(id)
    for s, i in pairs(Open) do
        if i == id then Open[s] = nil end
    end
end

local function event(inc, text)
    inc.events[#inc.events + 1] = { t = os.time(), text = text }
    while #inc.events > 80 do table.remove(inc.events, 1) end
    inc.updated = os.time()
    save_inc(inc)
end

-- lwk_npcai: a spoken line on the officer's open incident, for the narrative's Dialogue section.
-- Kept apart from the timeline so a long conversation can't push real events out of its 80.
local function add_dialogue(src, who, text)
    local inc = Open[tonumber(src)] and Incidents[Open[tonumber(src)]]
    text = str(text, 300)
    if not inc or not text then return end
    inc.dialogue = inc.dialogue or {}
    inc.dialogue[#inc.dialogue + 1] = { t = os.time(), who = str(who, 20) or 'Unknown', text = text }
    while #inc.dialogue > 100 do table.remove(inc.dialogue, 1) end
    inc.updated = os.time()
    save_inc(inc)
end
exports('AddDialogue', add_dialogue)
AddEventHandler('c3r:dialogue', add_dialogue) -- c3r's scripted conversation

-- c3r: a line for the open incident's timeline (a breathalyzer or drug swab result, say)
AddEventHandler('c3r:note', function(src, text)
    local inc = Open[tonumber(src)] and Incidents[Open[tonumber(src)]]
    text = str(text, 200)
    if inc and text then event(inc, text) end
end)

-- lwk_npcai: the subject's earlier contacts (newest first, at most 5), so a repeat offender can say
-- "not you again". person = a c3r person record. same_officer = it was this officer's report.
exports('GetPersonHistory', function(src, person)
    local p = Records.person(person)
    p = p and People[p.key]
    if not p then return {} end
    src = tonumber(src)
    local open = {} -- this stop, also as a backup unit's open incident: not an "earlier" contact
    for _, id in pairs(Open) do open[id] = true end
    local out = {}
    for i = #(p.contacts or {}), 1, -1 do
        local inc = Incidents[p.contacts[i]]
        if inc and not open[inc.id] then
            local charges = {}
            for _, c in ipairs(inc.charges or {}) do charges[#charges + 1] = c.label end
            out[#out + 1] = {
                when = os.date(Config.DateFormat or '%m/%d/%Y', inc.started), kind = Records.KIND[inc.kind] or 'Contact',
                -- only signed reports: a draft's form is just the default, nothing was actually issued
                outcome = inc.status == 'signed' and Records.FORMS[inc.form or Records.default_form(inc)] or nil,
                charges = #charges > 0 and table.concat(charges, ', ') or nil,
                same_officer = inc.author == license(src),
            }
            if #out >= 5 then break end
        end
    end
    return out
end)

local function close(src, text)
    local inc = current(src)
    if not inc then return end
    Open[src] = nil
    for _, id in pairs(Open) do -- another unit still on this call: only this one clears; the last one closes it
        if id == inc.id then
            event(inc, officer(src) .. ' cleared' .. (text and (': ' .. text:lower()) or ''))
            return
        end
    end
    if text then event(inc, text) end
    -- nothing to write up (no subject, no vehicle, nothing done): drop it
    if #inc.people == 0 and #inc.plates == 0 and #inc.events < 3 and not inc.fled then
        Incidents[inc.id] = nil
        return forget('i', inc.id)
    end
    inc.ended = os.time()
    local drafted = inc.status == 'open'
    if drafted then
        inc.status = 'draft'
        TriggerClientEvent('lwk_mdt:drafted', src, inc.id)
    end
    save_inc(inc)
    if drafted then TriggerEvent('lwk_mdt:reportDrafted', inc.id, src) end -- lwk_npcai writes its narrative
    log('closed #%d (%s)', inc.id, inc.status)
end

local function new_incident(src, kind, title)
    wait_loaded()
    local id = next_id()
    local now = os.time()
    local inc = {
        id = id, kind = kind, title = title, officer = officer(src), author = license(src),
        started = now, updated = now, status = 'open', people = {}, plates = {}, events = {}, charges = {}, total = 0,
    }
    Incidents[id] = inc
    if kind ~= 'manual' then
        Open[src] = id
        TriggerClientEvent('lwk_mdt:where', src, id) -- the street name is only known on the client
    end
    log('opened #%d %s for %d', id, kind, src)
    return inc
end

-- A field contact turns into whatever starts next, and a stop into the pursuit it became; a stop or a pursuit on a
-- callout is part of the callout's report. Anything else closes the open incident and starts a new one.
local function start(src, kind, title, text)
    local inc = current(src)
    if inc and inc.kind == 'callout' and kind ~= 'callout' then
        -- (stays the callout's)
    elseif inc and (inc.kind == 'contact' or (inc.kind == 'stop' and kind == 'pursuit')) then
        inc.kind, inc.title = kind, title or inc.title
    else
        if inc then close(src) end
        inc = new_incident(src, kind, title)
    end
    if text then event(inc, text) end
    return inc
end

local function ensure(src) return current(src) or start(src, 'contact') end

local function add_person(src, ped, label)
    local p = Records.person(ped)
    if not p then return end
    wait_loaded()
    p = Records.merge(People[p.key], p)
    p.last_seen = os.time()
    local inc = ensure(src)
    p.contacts = Records.add_unique(p.contacts, inc.id)
    People[p.key] = p
    save('p', p.key, p)
    for _, k in ipairs(inc.people) do
        if k == p.key then return p end
    end
    inc.people[#inc.people + 1] = p.key
    event(inc, label .. ': ' .. Records.person_desc(p))
    return p
end

local function add_vehicle(src, veh, label)
    local v = Records.vehicle(veh)
    if not v then return end
    wait_loaded()
    v = Records.merge(Vehicles[v.plate], v)
    v.last_seen = os.time()
    local inc = ensure(src)
    v.contacts = Records.add_unique(v.contacts, inc.id)
    Vehicles[v.plate] = v
    save('v', v.plate, v)
    for _, k in ipairs(inc.plates) do
        if k == v.plate then return v end
    end
    inc.plates[#inc.plates + 1] = v.plate
    event(inc, label .. ': ' .. Records.vehicle_desc(v))
    return v
end

RegisterNetEvent('lwk_mdt:location', function(id, text)
    local inc = Incidents[tonumber(id) or -1]
    if inc and inc.author == license(source) and not inc.location then
        inc.location = str(text, 80)
        save_inc(inc)
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for src, id in pairs(Open) do
            local inc = Incidents[id]
            if not inc or now - inc.updated > Config.IdleMinutes * 60 then close(src) end
        end
    end
end)

AddEventHandler('playerDropped', function()
    close(source)
    Callsign[source] = nil
end)

-- ─── c3r events ───────────────────────────────────────────────────────────
-- Server-only events (c3r/docs/contract.md): the first argument is the officer.

AddEventHandler('c3r:contact', function(src, ped) add_person(src, ped, 'Contact') end)
AddEventHandler('c3r:vehicleContact', function(src, veh) add_vehicle(src, veh, 'Vehicle') end)

AddEventHandler('c3r:stopStarted', function(src, ped, veh)
    start(src, 'stop', nil, 'Traffic stop initiated')
    add_vehicle(src, veh, 'Stopped')
    add_person(src, ped, 'Driver')
end)

-- outcome -> timeline line, and the form the draft starts as
local OUTCOME = {
    cited = { 'Citation issued', 'citation' }, warning = { 'Warning given', 'warning' },
    released = { 'Released, no action' }, fled = { 'Subject fled', 'arrest' }, cancelled = { 'Stop cleared' },
    arrested = { 'Subject arrested', 'arrest' },
}

AddEventHandler('c3r:stopEnded', function(src, outcome)
    local inc = current(src)
    if not inc or (inc.kind ~= 'stop' and inc.kind ~= 'pursuit' and inc.kind ~= 'callout') then return end -- a stop can start as a chase
    local o = OUTCOME[outcome] or OUTCOME.cancelled
    if o[2] and not inc.form then inc.form = o[2] end
    inc.outcome = outcome
    if inc.kind == 'callout' then return event(inc, o[1]) end -- (the call goes on: it closes when it ends)
    close(src, o[1])
end)

AddEventHandler('c3r:pursuitStarted', function(src, ped, veh)
    start(src, 'pursuit', nil, 'Pursuit initiated')
    add_vehicle(src, veh, 'Pursued')
    add_person(src, ped, 'Suspect')
end)

AddEventHandler('c3r:pursuitEnded', function(src)
    local inc = current(src)
    if inc then event(inc, 'Pursuit ended') end
end)

local function issue_warrant(id, text)
    if GetResourceState('c3r') == 'started' then pcall(function() exports.c3r:issueWarrant(id, text) end) end
end

-- Someone got away: their warrant waits for this report to be signed (H.save). No report to sign: it's issued now.
AddEventHandler('c3r:fled', function(src, person)
    local id = type(person) == 'table' and tonumber(person.id)
    if not id then return end
    local inc = current(src)
    if not inc then return issue_warrant(id, Records.EVADING) end
    inc.fled = Records.add_unique(inc.fled, id)
    inc.form = inc.form or 'arrest'
    save_inc(inc)
end)

-- A warrant or a BOLO issued or cleared: what's on file here keeps up (anyone not on file comes with it when met).
AddEventHandler('c3r:record', function(person, vehicle)
    local p, v = Records.person(person), Records.vehicle(vehicle)
    if p and People[p.key] then
        People[p.key] = Records.merge(People[p.key], p)
        save('p', p.key, People[p.key])
    end
    if v and Vehicles[v.plate] then
        Vehicles[v.plate] = Records.merge(Vehicles[v.plate], v)
        save('v', v.plate, Vehicles[v.plate])
    end
end)

-- The open incident of the callout c3r calls `id` that a unit is on right now, if any.
local function call_incident(id)
    if id == nil then return nil end
    for _, iid in pairs(Open) do
        local inc = Incidents[iid]
        if inc and inc.kind == 'callout' and inc.status == 'open' and inc.callout == id then return inc end
    end
end

-- A callout is one incident for every unit on it: the first one opens it (and writes the report); anyone after
-- joins it, and their stops, contacts and notes go into it too.
AddEventHandler('c3r:calloutAccepted', function(src, c)
    c = type(c) == 'table' and c or {}
    local id = math.type(c.id) == 'integer' and c.id or nil
    local joined = call_incident(id)
    if joined and Open[src] ~= joined.id then
        if current(src) then close(src) end
        Open[src] = joined.id
        joined.assist = Records.add_unique(joined.assist, license(src))
        event(joined, officer(src) .. ' responding')
        TriggerClientEvent('lwk_mdt:where', src, joined.id)
        return
    end
    local inc = start(src, 'callout', str(c.name, 60), 'Callout accepted')
    inc.callout = id
    local street = str(c.street, 80)
    if street and not inc.location then inc.location = street end
    save_inc(inc)
end)

AddEventHandler('c3r:calloutArrived', function(src)
    local inc = current(src)
    if not inc then return end
    inc.on_scene = inc.on_scene or {} -- (per unit: one arriving doesn't put the others on scene)
    local first = next(inc.on_scene) == nil
    inc.on_scene[license(src)] = true
    event(inc, first and 'Arrived on scene' or (officer(src) .. ' arrived on scene'))
end)

AddEventHandler('c3r:calloutEnded', function(src, completed)
    local inc = current(src)
    if inc and inc.kind == 'callout' then close(src, completed and 'Callout completed' or 'Callout ended') end
end)

-- ─── lwk_control intents (relayed by the client) ─────────────────────────────

local function last(list) return list[#list] end

-- A radio check opens the record in game and, at the next poll, in the browser pop-out.
local function show_record(src, view)
    WebShow[src] = view
    TriggerClientEvent('lwk_mdt:show', src, view)
end

RegisterNetEvent('lwk_mdt:action', function(id, ctx)
    local src = source
    if type(id) ~= 'string' then return end
    ctx = type(ctx) == 'table' and ctx or {}
    local inc = current(src)

    if id == 'plate_check' then
        local plate = Records.plate_key(ctx.plate) or (inc and last(inc.plates))
        if not plate then return end
        local v = Vehicles[plate]
        inc = inc or ensure(src)
        if v then add_vehicle(src, { plate = plate }, 'Vehicle') end
        event(inc, 'Plate check ' .. plate .. ': ' .. (v and Records.findings_text(Records.vehicle_findings(v)) or 'no record'))
        if v then show_record(src, { type = 'vehicle', key = plate }) end
        return
    end

    if not inc then return end -- radio traffic outside an incident isn't logged
    if id == 'name_check' then
        local p = People[last(inc.people) or '']
        if not p then return end
        event(inc, 'Name check ' .. Records.person_name(p) .. ': ' .. Records.findings_text(Records.person_findings(p)))
        return show_record(src, { type = 'person', key = p.key })
    end
    local text = Records.action_text(id, ctx)
    if text then event(inc, text) end
    -- back in service / code 4: the officer is done with this call, whatever c3r still thinks
    if id == 'status_10-8' or id == 'complete_callout' then close(src) end
end)

RegisterNetEvent('lwk_mdt:callsign', function(cs)
    Callsign[source] = signed_on(source) or type(cs) == 'string' and cs:sub(1, 20) or ''
end)

-- ─── unit board ──────────────────────────────────────────────────────────────
-- Each client reports shift, callsign and last 10-code; the open incident decides the rest.

local Units = {} -- [src] = { code, shown, since }

RegisterNetEvent('lwk_mdt:unit', function(on_duty, cs, code)
    local src = source
    if type(cs) == 'string' then Callsign[src] = signed_on(src) or cs:sub(1, 20) end
    if on_duty ~= true then Units[src] = nil return end
    Units[src] = Units[src] or { since = os.time() }
    Units[src].code = type(code) == 'string' and code:sub(1, 8) or nil
end)

AddEventHandler('playerDropped', function() Units[source] = nil end)

local CODE_STATUS = { ['10-8'] = 'AVL', ['10-6'] = 'BUSY', ['10-97'] = 'ONSC' }

local function unit_status(src, u)
    local inc = current(src)
    if not inc then return CODE_STATUS[u.code] or 'AVL' end
    if inc.kind == 'stop' then return 'STOP' end
    if inc.kind == 'pursuit' then return 'PURS' end
    if inc.kind == 'contact' then return 'CNTC' end
    if inc.on_scene then return (inc.on_scene[license(src)] or u.code == '10-97') and 'ONSC' or 'ENRT' end
    for _, e in ipairs(inc.events) do
        if e.text == 'Arrived on scene' then return 'ONSC' end
    end
    return u.code == '10-97' and 'ONSC' or 'ENRT'
end

local function units_board()
    local list = {}
    for src, u in pairs(Units) do
        local s = unit_status(src, u)
        if s ~= u.shown then u.shown, u.since = s, os.time() end
        local inc = current(src)
        list[#list + 1] = {
            unit = officer(src), status = s, since = u.since, call = inc and inc.id or nil,
            kind = inc and Records.KIND[inc.kind] or nil, title = inc and inc.title or nil,
            location = inc and inc.location or nil,
        }
    end
    table.sort(list, function(a, b) return a.unit < b.unit end)
    return list
end

-- ─── MDT requests ────────────────────────────────────────────────────────────

local PRIORITY = { pursuit = 1, call911 = 1, callout = 2, stop = 3, contact = 4 }

local function inc_summary(inc)
    local names = {}
    for _, k in ipairs(inc.people) do
        local p = People[k]
        if p then names[#names + 1] = Records.person_name(p) end
    end
    return {
        id = inc.id, kind = Records.KIND[inc.kind], title = inc.title, officer = inc.officer, started = inc.started,
        status = inc.status, form = Records.FORMS[inc.form or Records.default_form(inc)], location = inc.location,
        people = names, plates = inc.plates, total = inc.total, updated = inc.updated, priority = PRIORITY[inc.kind],
    }
end

local function contacts(list)
    local out = {}
    for i = #(list or {}), 1, -1 do
        local inc = Incidents[list[i]]
        if inc then out[#out + 1] = inc_summary(inc) end
    end
    return out
end

local function records_of(inc)
    local people, vehicles = {}, {}
    for _, k in ipairs(inc.people) do people[#people + 1] = People[k] end
    for _, k in ipairs(inc.plates) do vehicles[#vehicles + 1] = Vehicles[k] end
    return people, vehicles
end

-- Open incidents first, then most recently touched.
local function sorted_reports(filter)
    local out = {}
    for _, inc in pairs(Incidents) do
        if filter(inc) then out[#out + 1] = inc end
    end
    table.sort(out, function(a, b)
        if (a.status == 'open') ~= (b.status == 'open') then return a.status == 'open' end
        return a.updated > b.updated
    end)
    local list = {}
    for i = 1, math.min(#out, 50) do list[i] = inc_summary(out[i]) end
    return list
end

local H = {}

-- ─── sign-on and settings ────────────────────────────────────────────────────

local STYLES = { modern = true, command = true, enterprise = true, classic = true }

-- 1-ADAM-12, 2 BOY 4, K9-3: letters, numbers, dashes and spaces, 20 at most, upper case.
local function clean_callsign(cs)
    cs = str(cs, 20)
    cs = cs and cs:upper():gsub('%s+', ' ')
    return cs and cs:match('^[%w][%w%- ]*$') and cs or nil
end

local function prefs(src)
    local p = Meta['prefs:' .. license(src)] or {}
    local popups = p.popups
    if popups == nil then popups = Config.CalloutPopup ~= false end
    return { callsign = p.callsign or '', style = STYLES[p.style] and p.style or Config.DefaultStyle or 'modern', popups = popups }
end

-- c3r's calls, for the board (nothing if it isn't running).
local function c3r_calls(src)
    if GetResourceState('c3r') ~= 'started' then return {} end
    local ok, list = pcall(function() return exports.c3r:openCalls(src) end)
    return ok and list or {}
end

function H.init(src)
    local me = license(src)
    local inc = current(src)
    Player(src).state:set('c3rNoPopup', not prefs(src).popups, true) -- (read by c3r's game)
    return {
        forms = (function() -- ordered list: a Lua map reaches the page in random key order
            local out = {}
            for _, id in ipairs(Records.FORM_ORDER) do out[#out + 1] = { id = id, label = Records.FORMS[id] } end
            return out
        end)(), officer = officer(src),
        current = inc and inc_summary(inc) or nil,
        drafts = sorted_reports(function(i) return i.author == me and i.status == 'draft' end),
        calls = sorted_reports(function(i) return i.status == 'open' or i.status == 'pending' end), -- live calls only
        c3r = c3r_calls(src),
        admin = admin(src),
        units = units_board(), now = os.time(),
        signed = signed_on(src) ~= nil, prefs = prefs(src),
    }
end

-- Sign on (first open of a session) and the settings button: the callsign, and the CAD's style. Kept per
-- player, so the next session's sign-on starts with them filled in.
function H.signOn(src, a)
    local cs = clean_callsign(a.callsign)
    if not cs then return { error = 'Use letters, numbers and dashes, e.g. 1-ADAM-12.' } end
    local p = Meta['prefs:' .. license(src)] or {}
    p.callsign = cs
    if STYLES[a.style] then p.style = a.style end
    if type(a.popups) == 'boolean' then p.popups = a.popups end
    set_meta('prefs:' .. license(src), p)
    Callsign[src] = cs
    Player(src).state:set('lwkMdtCallsign', cs, true) -- lwk_control reads it from here
    return { ok = true, prefs = prefs(src) }
end
H.settings = H.signOn

-- Joined: the callout popup setting counts from the start, MDT opened or not.
RegisterNetEvent('lwk_mdt:hello', function()
    local src = source
    Player(src).state:set('c3rNoPopup', not prefs(src).popups, true)
end)

function H.charges() return Config.Charges end -- fetched once by the page (210 entries)

-- A whole plate nobody has met yet: c3r looks for that car near the officer and, if it's there, makes up its
-- papers (lookupPlate). Kept here like any other vehicle; a search alone doesn't open an incident.
local function lookup_plate(src, plate)
    if GetResourceState('c3r') ~= 'started' or not coroutine.isyieldable() then return nil end
    local p = promise.new()
    local ok = pcall(function() exports.c3r:lookupPlate(src, plate, function(v) p:resolve(v or false) end, true) end)
    local v = ok and Records.vehicle(Citizen.Await(p) or nil)
    if not v then return nil end
    v = Records.merge(Vehicles[v.plate], v)
    v.last_seen = os.time()
    Vehicles[v.plate] = v
    save('v', v.plate, v)
    return v
end

-- People c3r has on file (anyone it ever made up: a car's owner nobody has met yet), by name. Kept here like
-- anyone met, so their return opens and the next search finds them. -> list
local function lookup_people(q)
    if GetResourceState('c3r') ~= 'started' or not coroutine.isyieldable() then return {} end
    local p = promise.new()
    local ok = pcall(function() exports.c3r:findPeople(q, function(list) p:resolve(list or false) end) end)
    local out = {}
    for _, r in ipairs(ok and Citizen.Await(p) or {}) do
        local rec = Records.person(r)
        if rec then
            rec = Records.merge(People[rec.key], rec)
            People[rec.key] = rec
            save('p', rec.key, rec)
            out[#out + 1] = rec
        end
    end
    return out
end

-- c3r's record of one person by its id (a vehicle's registered owner), kept here as above. -> record | nil
local function lookup_person_id(id)
    if not id or GetResourceState('c3r') ~= 'started' or not coroutine.isyieldable() then return nil end
    local p = promise.new()
    local ok = pcall(function() exports.c3r:getPerson(id, function(r) p:resolve(r or false) end) end)
    local rec = Records.person(ok and Citizen.Await(p) or nil)
    if not rec then return nil end
    rec = Records.merge(People[rec.key], rec)
    People[rec.key] = rec
    save('p', rec.key, rec)
    return rec
end

function H.search(src, a)
    local terms, people, vehicles = Records.terms(a.q), {}, {}
    for _, p in pairs(People) do
        if Records.match_person(p, terms) then people[#people + 1] = p end
    end
    for _, v in pairs(Vehicles) do
        if Records.match_vehicle(v, a.q) then vehicles[#vehicles + 1] = v end
    end
    local plate = Records.plate_key(a.q)
    if #vehicles == 0 and #people == 0 and plate and #plate >= 5 then vehicles[1] = lookup_plate(src, plate) end
    -- nobody met by that name: everyone on file (a name with letters in it, not a plate that came back)
    if #people == 0 and #vehicles == 0 and tostring(a.q or ''):find('%a%a') then people = lookup_people(a.q) end
    local by_seen = function(x, y) return (x.last_seen or 0) > (y.last_seen or 0) end
    table.sort(people, by_seen)
    table.sort(vehicles, by_seen)
    for i = 26, #people do people[i] = nil end
    for i = 26, #vehicles do vehicles[i] = nil end
    return { people = people, vehicles = vehicles }
end

function H.person(_, a)
    local p = People[str(a.key, 160) or '']
    return p and { record = p, findings = Records.person_findings(p), contacts = contacts(p.contacts) } or nil
end

function H.vehicle(_, a)
    local v = Vehicles[Records.plate_key(a.key) or '']
    return v and { record = v, findings = Records.vehicle_findings(v), contacts = contacts(v.contacts) } or nil
end

-- The registered owner of a vehicle on file (double-click on REG OWNER): their person return. -> { key } | nil
function H.owner(_, a)
    local v = Vehicles[Records.plate_key(a.plate) or '']
    if not v then return nil end
    local p = lookup_person_id(v.owner_id)
    if not p and v.owner then -- (an older record without the owner's id: whoever on file has that name)
        local terms = Records.terms(v.owner)
        for _, x in pairs(People) do if Records.match_person(x, terms) then p = x break end end
        p = p or lookup_people(v.owner)[1]
    end
    return p and { key = p.key } or nil
end

-- Every officer's totals, from c3r, with this one's row marked. -> { list } | { off = true }: no c3r, or the pop-out,
-- whose requests can't wait on another resource.
function H.stats(src)
    if GetResourceState('c3r') ~= 'started' or not coroutine.isyieldable() then return { off = true } end
    local p = promise.new()
    local ok = pcall(function() exports.c3r:getStatsBoard(src, function(list) p:resolve(list or false) end) end)
    local list = ok and Citizen.Await(p)
    if not list then return { off = true } end
    return { list = list }
end

function H.reports(src, a)
    local me = license(src)
    local filters = {
        mine = function(i) return i.author == me end,
        drafts = function(i) return i.status == 'draft' end,
        signed = function(i) return i.status == 'signed' end,
    }
    return sorted_reports(filters[a.filter] or function() return true end)
end

function H.report(src, a)
    local inc = Incidents[tonumber(a.id) or -1]
    if not inc then return nil end
    local people, vehicles = records_of(inc)
    return {
        summary = inc_summary(inc), form = inc.form or Records.default_form(inc), charges = inc.charges,
        narrative = inc.narrative or Records.narrative(inc, people, vehicles, Config.DateFormat),
        auto = inc.narrative == nil, events = inc.events, people = people, vehicles = vehicles,
        can_edit = can_edit(src, inc), signed_by = inc.signed_by, signed_at = inc.signed_at,
        coords = inc.coords, caller = inc.caller,
    }
end

-- lwk_npcai writes a prose narrative for a freshly drafted report (lwk_mdt:reportDrafted). Only while the
-- report is an untouched draft: an officer's own edit or a signature always wins.
local function ai_target(id)
    local inc = Incidents[tonumber(id) or -1]
    return inc and inc.status == 'draft' and inc.narrative == nil and inc or nil
end

-- -> the auto narrative (who, what, where, timeline, dialogue), has dialogue, timeline length | nil
exports('GetReportDraft', function(id)
    local inc = ai_target(id)
    if not inc then return nil end
    local people, vehicles = records_of(inc)
    return Records.narrative(inc, people, vehicles, Config.DateFormat), inc.dialogue ~= nil and #inc.dialogue > 0,
        #inc.events
end)

exports('SetNarrative', function(id, text)
    local inc = ai_target(id)
    text = str(text, 6000)
    if not inc or not text then return false end
    inc.narrative = text -- frozen, like an officer's edit: "auto" would rebuild it from the timeline
    inc.updated = os.time()
    save_inc(inc)
    return true
end)

function H.save(src, a)
    local inc = Incidents[tonumber(a.id) or -1]
    if not inc or not can_edit(src, inc) then return { error = 'You can only edit your own reports.' } end
    if Records.FORMS[a.form] then inc.form = a.form end
    inc.charges, inc.total = Records.charges(a.charges, Config.Charges)
    if inc.form == 'warning' then inc.total = 0 end
    if a.auto then inc.narrative = nil else inc.narrative = str(a.narrative, 6000) end
    if a.sign then
        if inc.narrative == nil then
            local people, vehicles = records_of(inc)
            inc.narrative = Records.narrative(inc, people, vehicles, Config.DateFormat) -- freeze it
        end
        if inc.status ~= 'signed' then -- (once: a signed report edited and saved again changes nothing on anyone's record)
            local ids, reason = Records.wanted(inc, People)
            for _, id in ipairs(ids) do issue_warrant(id, reason) end
        end
        inc.status, inc.signed_by, inc.signed_at = 'signed', officer(src), os.time()
        detach(inc.id) -- a signed call is finished: off the calls grid and off its unit
    end
    inc.updated = os.time()
    save_inc(inc)
    return { ok = true }
end

function H.delete(src, a)
    local inc = Incidents[tonumber(a.id) or -1]
    if not inc or not can_edit(src, inc) then return { error = 'You can only delete your own reports.' } end
    detach(inc.id)
    Incidents[inc.id] = nil
    forget('i', inc.id)
    return { ok = true } -- people / vehicles keep the id; contacts() skips missing incidents
end

-- Every unsigned, closed report on the server (open calls and signed reports stay). Supervisors and Config.Admins only.
function H.deleteDrafts(src)
    if not admin(src) then return { error = 'Not allowed.' } end
    local n = 0
    for id, inc in pairs(Incidents) do
        if inc.status == 'draft' then
            Incidents[id] = nil
            forget('i', id)
            n = n + 1
        end
    end
    print(('[lwk_mdt] %s deleted all drafts (%d)'):format(GetPlayerName(src) or src, n))
    return { ok = true, count = n }
end

-- A blank report from a search result, with that person or vehicle attached.
function H.new(src, a)
    local inc = new_incident(src, 'manual')
    inc.status = 'draft'
    local p, v = People[str(a.person, 160) or ''], Vehicles[Records.plate_key(a.plate) or '']
    if p then inc.people[1] = p.key p.contacts = Records.add_unique(p.contacts, inc.id) save('p', p.key, p) end
    if v then inc.plates[1] = v.plate v.contacts = Records.add_unique(v.contacts, inc.id) save('v', v.plate, v) end
    save_inc(inc)
    return { id = inc.id }
end

-- "Write it up": the open incident, or the officer's latest draft.
function H.writeUp(src)
    local inc = current(src)
    if inc then return { id = inc.id } end
    local me, best = license(src), nil
    for _, i in pairs(Incidents) do
        if i.author == me and i.status == 'draft' and (not best or i.updated > best.updated) then best = i end
    end
    return best and { id = best.id } or nil
end

local function has(list, x)
    for _, v in ipairs(list) do
        if v == x then return true end
    end
    return false
end

-- "Add to Incident" on a person or vehicle return: attach it to the officer's open call.
function H.attach(src, a)
    local inc = current(src)
    if not inc then return { error = 'You have no open incident.' } end
    local p, v = People[str(a.person, 160) or ''], Vehicles[Records.plate_key(a.plate) or '']
    if not p and not v then return { error = 'Record not found.' } end
    if p and not has(inc.people, p.key) then
        inc.people[#inc.people + 1] = p.key
        p.contacts = Records.add_unique(p.contacts, inc.id)
        save('p', p.key, p)
        event(inc, 'Added: ' .. Records.person_desc(p))
    end
    if v and not has(inc.plates, v.plate) then
        inc.plates[#inc.plates + 1] = v.plate
        v.contacts = Records.add_unique(v.contacts, inc.id)
        save('v', v.plate, v)
        event(inc, 'Added: ' .. Records.vehicle_desc(v))
    end
    return { ok = true, id = inc.id }
end

-- ─── citizen portal ──────────────────────────────────────────────────────────
-- Off-duty players keep civilian characters and vehicles in the same records police search.
-- civ = the owner's licence: only they can change or delete them, and pruning never removes them.

local DL = { Valid = true, Suspended = false, Revoked = false, Expired = false, None = false }
local DL_ORDER = { 'Valid', 'Suspended', 'Revoked', 'Expired', 'None' }

local function notify(src, text) TriggerClientEvent('lwk_mdt:notify', src, text) end
local function mine(rec, src) return rec ~= nil and rec.civ == license(src) end
local function active_key(lic) return Meta['active:' .. lic] end
local function set_active(lic, key) set_meta('active:' .. lic, key) end
local function active(src)
    local p = People[active_key(license(src)) or '']
    return mine(p, src) and p or nil
end

-- The civilian sets everything except name and DOB after creation (they're the record's key).
local function civ_person(a, old)
    local first, last, dob = str(a.first, 40), str(a.last, 40), str(a.dob, 10)
    if old then first, last, dob = old.first, old.last, old.dob end
    if not first or not last or not (dob and dob:match('^%d%d/%d%d/%d%d%d%d$')) then
        return nil, 'First name, last name and date of birth (MM/DD/YYYY) are required.'
    end
    local dl = DL[a.dl] ~= nil and a.dl or 'Valid'
    local flags = {}
    for _, f in ipairs(type(a.flags) == 'table' and a.flags or {}) do
        if has(Config.CivFlags, f) and not has(flags, f) then flags[#flags + 1] = f end
    end
    return {
        key = (first .. '|' .. last .. '|' .. dob):lower(), first = first, last = last, dob = dob,
        gender = str(a.gender, 20) or 'Unknown', address = str(a.address, 60) or '', dl = dl, dl_valid = DL[dl], flags = flags,
    }
end

function H.civInit(src)
    local me = license(src)
    local chars, vehs, keys, plates = {}, {}, {}, {}
    for k, p in pairs(People) do
        if p.civ == me then chars[#chars + 1], keys[k] = p, true end
    end
    for pl, v in pairs(Vehicles) do
        if v.civ == me then vehs[#vehs + 1], plates[pl] = v, true end
    end
    table.sort(chars, function(x, y) return (x.last .. x.first) < (y.last .. y.first) end)
    table.sort(vehs, function(x, y) return x.plate < y.plate end)
    local record = {} -- signed reports naming one of my characters or vehicles
    for _, inc in pairs(Incidents) do
        local hit = false
        for _, k in ipairs(inc.people) do hit = hit or keys[k] == true end
        for _, pl in ipairs(inc.plates) do hit = hit or plates[pl] == true end
        if hit and inc.status == 'signed' then
            local s = inc_summary(inc)
            s.charges, s.narrative = inc.charges, inc.narrative
            record[#record + 1] = s
        end
    end
    table.sort(record, function(x, y) return x.started > y.started end)
    local act = active_key(me)
    return { characters = chars, vehicles = vehs, record = record, active = keys[act or ''] and act or nil,
             flags = Config.CivFlags, licences = DL_ORDER, now = os.time() }
end

function H.civSave(src, a)
    local old
    if a.key then
        old = People[str(a.key, 160) or '']
        if not mine(old, src) then return { error = 'Not your character.' } end
    end
    local p, err = civ_person(a, old)
    if not p then return { error = err } end
    if not old and People[p.key] then return { error = 'Someone with that name and date of birth is already on file.' } end
    p = Records.merge(old or {}, p) -- keeps prior contacts
    p.civ, p.last_seen = license(src), os.time()
    People[p.key] = p
    save('p', p.key, p)
    if not active(src) then set_active(license(src), p.key) end
    for _, v in pairs(Vehicles) do -- registered vehicles show the owner's current name
        if v.owner_key == p.key and v.civ == p.civ then v.owner = Records.person_name(p) save('v', v.plate, v) end
    end
    return { ok = true, key = p.key }
end

function H.civDelete(src, a)
    local p = People[str(a.key, 160) or '']
    if not mine(p, src) then return { error = 'Not your character.' } end
    People[p.key] = nil
    forget('p', p.key)
    for pl, v in pairs(Vehicles) do
        if v.owner_key == p.key and v.civ == p.civ then Vehicles[pl] = nil forget('v', pl) end
    end
    if active_key(p.civ) == p.key then set_active(p.civ, nil) end
    return { ok = true }
end

function H.civActive(src, a)
    local p = People[str(a.key, 160) or '']
    if not mine(p, src) then return { error = 'Not your character.' } end
    set_active(p.civ, p.key)
    return { ok = true }
end

function H.civVehicle(src, a)
    local v = Vehicles[Records.plate_key(a.plate) or '']
    if not mine(v, src) then return { error = 'Not your vehicle.' } end
    v.reg_valid, v.ins_valid, v.stolen = a.reg_valid == true, a.ins_valid == true, a.stolen == true
    save('v', v.plate, v)
    return { ok = true }
end

function H.civUnreg(src, a)
    local v = Vehicles[Records.plate_key(a.plate) or '']
    if not mine(v, src) then return { error = 'Not your vehicle.' } end
    Vehicles[v.plate] = nil
    forget('v', v.plate)
    return { ok = true }
end

-- /vehreg: the vehicle the player is driving, to their active character.
RegisterNetEvent('lwk_mdt:vehreg', function(d)
    local src = source
    local p = active(src)
    if not p then return notify(src, '~r~Not registered:~s~ pick an active character in the Citizen Portal (/' .. Config.OpenCommand .. ').') end
    d = type(d) == 'table' and d or {}
    local plate = Records.plate_key(d.plate)
    if not plate then return notify(src, '~r~Not registered:~s~ that vehicle has no plate.') end
    local old = Vehicles[plate]
    if old and old.civ and old.civ ~= p.civ then return notify(src, '~r~Not registered:~s~ ' .. plate .. ' belongs to someone else.') end
    local v = Records.merge(old or {}, {
        plate = plate, make = str(d.make, 30), model = str(d.model, 30), color = str(d.color, 30),
        owner = Records.person_name(p), owner_key = p.key, civ = p.civ, last_seen = os.time(),
    })
    if not (old and old.civ) then v.reg_valid, v.ins_valid, v.stolen, v.bolo = true, true, false, false end -- new: clean papers
    Vehicles[plate] = v
    save('v', plate, v)
    local name = ((v.color or '') .. ' ' .. (v.make or '') .. ' ' .. (v.model or 'vehicle')):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    notify(src, ('~b~MDT~s~ %s (%s) registered to %s.'):format(plate, name, v.owner))
end)

-- /showid: the active character's ID card to the nearest player (or to yourself with nobody close).
RegisterNetEvent('lwk_mdt:showid', function(target)
    local src = source
    local p = active(src)
    if not p then return notify(src, '~r~No ID:~s~ pick an active character in the Citizen Portal (/' .. Config.OpenCommand .. ').') end
    local card = { name = Records.person_name(p), dob = p.dob, gender = p.gender, address = p.address, dl = p.dl }
    target = tonumber(target)
    local close_enough = target and target ~= src and GetPlayerName(target)
        and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target))) < 5.0
    if not close_enough then return TriggerClientEvent('lwk_mdt:idcard', src, card) end
    TriggerClientEvent('lwk_mdt:idcard', target, card)
    if Units[target] then show_record(target, { type = 'person', key = p.key }) end -- an officer gets the record too
    notify(src, 'You showed your ID.')
end)

-- ─── 911 ─────────────────────────────────────────────────────────────────────
-- A call from the portal is a pending incident on every officer's calls board until a unit responds.

local Last911 = {}

local function to_officers(name, ...)
    for s in pairs(Units) do TriggerClientEvent(name, s, ...) end
end

function H.civ911(src, a)
    local text = str(a.text, 300)
    if not text then return { error = 'Describe your emergency.' } end
    local x, y, z = tonumber(a.x), tonumber(a.y), tonumber(a.z)
    if not x or not y then return { error = 'Your location is unavailable.' } end
    if Last911[src] and os.time() - Last911[src] < Config.Call911Cooldown then
        return { error = 'Your last call is still being handled. Try again in a minute.' }
    end
    Last911[src] = os.time()
    local p = active(src)
    local id = next_id()
    local now = os.time()
    local inc = {
        id = id, kind = 'call911', officer = '', started = now, updated = now, status = 'pending',
        people = {}, plates = {}, events = {}, charges = {}, total = 0, location = str(a.location, 80),
        coords = { x = x, y = y, z = z or 0.0 }, caller = p and Records.person_name(p) or 'Unknown caller',
    }
    if p then
        inc.people[1] = p.key
        p.contacts = Records.add_unique(p.contacts, inc.id)
        save('p', p.key, p)
    end
    Incidents[id] = inc
    event(inc, '911 from ' .. inc.caller .. ': ' .. text)
    -- the circle is off-centre so it shows the area, not the caller; Set Waypoint has the exact spot
    local r, ang = Config.Call911Radius, math.random() * 2 * math.pi
    local d = math.random() * r * 0.6
    to_officers('lwk_mdt:911', { id = id, text = text, location = inc.location, x = x + math.cos(ang) * d,
        y = y + math.sin(ang) * d, radius = r, ttl = Config.Call911ExpireMinutes * 60 })
    return { ok = true, id = id }
end

-- "Set Waypoint" on a call: the exact spot, which only the server holds.
function H.waypoint(src, a)
    local inc = Incidents[tonumber(a.id) or -1]
    if not inc or not inc.coords then return { error = 'No location on this call.' } end
    TriggerClientEvent('lwk_mdt:waypoint', src, inc.coords.x, inc.coords.y)
    return { ok = true }
end

-- Onto a c3r call from the board, whoever's on it, popup or not.
function H.joinCall(src, a)
    if GetResourceState('c3r') ~= 'started' then return { error = 'Calls are not available.' } end
    local ok, done, why = pcall(function() return exports.c3r:joinCall(src, tonumber(a.id)) end)
    if not ok or not done then return { error = why == 'already_on_call' and 'You are already on a call.' or 'Unable to attach to that call.' } end
    return { ok = true }
end

-- An officer takes a pending 911: it becomes their open incident.
function H.respond(src, a)
    local inc = Incidents[tonumber(a.id) or -1]
    if not inc or inc.kind ~= 'call911' then return { error = 'Call not found.' } end
    if inc.status ~= 'pending' then return { error = 'Another unit already has this call.' } end
    if current(src) then close(src) end
    inc.status, inc.author, inc.officer = 'open', license(src), officer(src)
    Open[src] = inc.id
    event(inc, officer(src) .. ' responding')
    to_officers('lwk_mdt:911done', inc.id)
    return { ok = true }
end

CreateThread(function()
    while true do
        Wait(30000)
        for id, inc in pairs(Incidents) do
            if inc.status == 'pending' and os.time() - inc.started > Config.Call911ExpireMinutes * 60 then
                Incidents[id] = nil
                forget('i', id)
                to_officers('lwk_mdt:911done', id)
            end
        end
    end
end)

AddEventHandler('playerDropped', function() Last911[source] = nil end)

RegisterNetEvent('lwk_mdt:req', function(rid, name, args)
    local src = source
    local h = type(name) == 'string' and H[name]
    local res
    wait_loaded()
    if h and can_use(src) then
        local ok, r = pcall(h, src, type(args) == 'table' and args or {})
        if ok then res = r else print(('[lwk_mdt] %s failed: %s'):format(name, tostring(r))) end
    end
    TriggerClientEvent('lwk_mdt:res', src, rid, res)
end)

-- ─── backup ──────────────────────────────────────────────────────────────────

RegisterCommand('mdtexport', function(src)
    if not supervisor(src) then return end
    local out = { people = {}, vehicles = {}, incidents = {} }
    for _, p in pairs(People) do out.people[#out.people + 1] = p end
    for _, v in pairs(Vehicles) do out.vehicles[#out.vehicles + 1] = v end
    for _, i in pairs(Incidents) do out.incidents[#out.incidents + 1] = i end
    local ok = SaveResourceFile(GetCurrentResourceName(), 'export.json', json.encode(out), -1)
    print(('[lwk_mdt] export %s: %d people, %d vehicles, %d incidents -> export.json'):format(ok and 'saved' or 'FAILED',
        #out.people, #out.vehicles, #out.incidents))
end, false)

-- ─── browser pop-out ─────────────────────────────────────────────────────────
-- The same page is served at <server>/lwk_mdt/ so an officer can keep it on another monitor.
-- A link token made in game authorises it: tied to that player's licence, dead once they disconnect.

local RES = GetCurrentResourceName()
local Links, LinkOf = {}, {} -- [token] = { src, license } / [src] = token

-- Config.PopoutBaseUrl, else the server's users.cfx.re address, else the ip:port the player's game is
-- connected to (FXServer answers web requests on its game port). cfx.re retired users.cfx.re: those
-- addresses now come back as "deprecated-xxxx.users.cfx.re" and don't resolve, so they're skipped.
local function base_url(endpoint)
    local b = Config.PopoutBaseUrl
    if not b then
        local web = GetConvar('web_baseUrl', '')
        if web ~= '' and not web:find('^deprecated%-') then
            b = 'https://' .. web
        elseif type(endpoint) == 'string' and endpoint:match('^[%w%.%-]+:%d+$') then
            b = 'http://' .. endpoint
        end
    end
    if not b or b == '' then return nil end
    if not b:find('^https?://') then b = 'https://' .. b end
    return (b:gsub('/+$', ''))
end

function H.popout(src, a)
    local base = base_url(a.endpoint)
    if not base then return { error = 'The pop-out is not set up on this server (Config.PopoutBaseUrl).' } end
    local t = LinkOf[src]
    if not t then
        local ok, tok = pcall(function() return exports[RES]:newToken() end)
        if not ok or type(tok) ~= 'string' or #tok < 32 then -- server/token.js isn't loaded: never fall back to weak tokens
            print('[lwk_mdt] pop-out: server/token.js is not loaded. Run "refresh" then "ensure lwk_mdt". (' .. tostring(tok) .. ')')
            return { error = 'The pop-out is not ready on this server yet. Ask staff to run refresh, then ensure lwk_mdt.' }
        end
        t = tok
        Links[t], LinkOf[src] = { src = src, license = license(src) }, t
    end
    return { url = ('%s/%s/?t=%s'):format(base, RES, t) }
end

AddEventHandler('playerDropped', function()
    if LinkOf[source] then Links[LinkOf[source]] = nil end
    LinkOf[source], WebShow[source] = nil, nil
end)

local page_html
local function page()
    if not page_html then
        local html, js = LoadResourceFile(RES, 'ui/index.html'), LoadResourceFile(RES, 'ui/app.js')
        page_html = (html:gsub('<script src="app.js"></script>', function() return '<script>\n' .. js .. '\n</script>' end))
    end
    return page_html
end

local function send(res, code, body, ctype)
    res.writeHead(code, { ['Content-Type'] = ctype or 'application/json', ['Cache-Control'] = 'no-store' })
    res.send(type(body) == 'string' and body or json.encode(body))
end

-- The browser's requests: the same handlers as the game's, plus poll (radio checks, status) and run.
local function web_request(src, name, args)
    if name == 'poll' then
        local v = WebShow[src]
        WebShow[src] = nil
        return { show = v, status = Units[src].code }
    end
    if name == 'run' then -- only the configured status-bar buttons, run by the officer's own game
        for _, q in ipairs(Config.Quick) do
            if q.intent == args.intent then
                TriggerClientEvent('lwk_mdt:run', src, q.intent)
                return { ok = true }
            end
        end
        return { error = 'Unknown button.' }
    end
    local h = name ~= 'popout' and H[name]
    if not h then return { error = 'Unknown request.' } end
    local r = h(src, args)
    if name == 'init' and r then r.quick, r.status = Config.Quick, Units[src].code end
    return r or {}
end

SetHttpHandler(function(req, res)
    local path = req.path:match('^[^?#]*') -- FXServer leaves the query string (?t=...) on the path
    if req.method == 'GET' and (path == '/' or path == '' or path == '/index.html') then
        return send(res, 200, page(), 'text/html; charset=utf-8')
    end
    if req.method ~= 'POST' or path ~= '/api' then return send(res, 404, { error = 'Not found.' }) end
    req.setDataHandler(function(body)
        if type(body) ~= 'string' or #body > 65536 then return send(res, 413, { error = 'Too large.' }) end
        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' then return send(res, 400, { error = 'Bad request.' }) end
        local link = type(data.t) == 'string' and Links[data.t]
        local src = link and link.src
        if not link or not GetPlayerName(src) or license(src) ~= link.license then
            return send(res, 403, { error = 'This link has expired. Open the MDT in game and press Pop Out again.', expired = true })
        end
        if not Units[src] or not can_use(src) then return send(res, 403, { error = 'Go on shift in game to use the MDT.' }) end
        local ok2, r = pcall(web_request, src, type(data.name) == 'string' and data.name or '', type(data.args) == 'table' and data.args or {})
        if not ok2 then
            print(('[lwk_mdt] web %s failed: %s'):format(tostring(data.name), tostring(r)))
            return send(res, 500, { error = 'Server error.' })
        end
        send(res, 200, r)
    end)
end)
