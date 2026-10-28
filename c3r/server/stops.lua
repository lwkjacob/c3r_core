--[[
    c3r — server: traffic stops. The officer's game asks; this side checks the entities (OneSync),
    makes up everyone in the car (Generator), decides what they say (Dialogue) and tells the officer's game
    what each ped does. Other resources hear about it through the c3r:stop* / contact / dialogue / note
    events.

    stop     = { src, key (veh_net, or 'ped:<net>' on foot), veh_net, plate, vehicle, occ = { [ped net] = occupant }, driver = occupant,
                 car_items = { { name, owner = occupant | nil } }, pursuit, towed, outcome }
    occupant = { net, seat, role ('driver' | 'passenger' | 'pedestrian'), person, truth, items, vehicle, answers, facts,
                 identified, alias_person, pockets, cuffed, refused, ran }
]]

local Stops = {}     -- [officer src] = stop
local ByVehicle = {} -- [vehicle net id] = officer src, so two officers can't stop the same car
local Recent = {}    -- [plate] = { driver = generated, passengers = { [seat] = generated }, at }
local Staged = {}    -- [vehicle net id] = officer src whose game is driving it as a staged violator

local TALK_RANGE = 8.0 -- m, officer to the person, for anything said face to face
local RECENT_SECONDS = 1800 -- a car stopped again within this keeps the same people

local function log(fmt, ...)
    if Config.Debug then print(('[c3r] ' .. fmt):format(...)) end
end

local function str(v, max)
    return type(v) == 'string' and v:gsub('[%c~]', ''):match('^%s*(.-)%s*$'):sub(1, max) or nil
end

local function entity(net) return math.type(net) == 'integer' and NetworkGetEntityFromNetworkId(net) or 0 end

local function dist(src, ent)
    return #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(ent))
end

-- The person record as it goes out: the name they gave when it's a false one (no record behind it).
local function given_identity(o)
    if o.truth.id ~= 'alias' then return o.person end
    local a = o.truth.alias
    o.alias_person = o.alias_person
        or { first = a.first, last = a.last, dob = a.dob, gender = o.person.gender, unverified = true }
    return o.alias_person
end

-- What the officer calls them on screen: their name once they've given one, else driver / passenger / person.
local function label(o)
    local p = o.identified
    return p and (p.first .. ' ' .. p.last) or ({ driver = 'Driver', passenger = 'Passenger' })[o.role] or 'Person'
end

-- who = 'officer', or the occupant speaking
local function say(s, text, who)
    local officer = who == 'officer'
    TriggerClientEvent('c3r:stop:say', s.src, text, officer and 'officer' or label(who), not officer and who.net or nil)
    TriggerEvent('c3r:dialogue', s.src, officer and 'Officer' or 'Subject', text)
end

-- The officer's line out loud (nui/voice/officer_<key>.ogg, tools/make_officer_voice.py): heard by them and any
-- player near them (Config.Voice), quieter further off.
local function voice(s, key)
    local v = Config.Voice or {}
    local range = v.range or 20.0
    if (v.volume or 1.0) <= 0 then return end
    local at = GetEntityCoords(GetPlayerPed(s.src))
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if id and #(GetEntityCoords(GetPlayerPed(id)) - at) < range then
            TriggerClientEvent('c3r:voice', id, key, s.src, range)
        end
    end
end

-- A line on the incident's timeline (lwk_mdt): test results and the like.
local function note(s, text) TriggerEvent('c3r:note', s.src, text) end

-- Told who they are (ID handed over, or a name given): name checks and the MDT can use it now.
local function identify(s, o, person)
    if o.identified == person then return end
    o.identified = person
    TriggerEvent('c3r:contact', s.src, person)
end

local function finish(src, outcome)
    local s = Stops[src]
    if not s then return end
    Stops[src], ByVehicle[s.key] = nil, nil
    for _, o in pairs(s.occ) do
        if o.cuffed then outcome = 'arrested' end -- whatever else happened, someone is going to jail
    end
    if s.pursuit then TriggerEvent('c3r:pursuitEnded', src) end
    TriggerEvent('c3r:stopEnded', src, outcome)
    TriggerClientEvent('c3r:stop:ended', src, outcome)
    -- lwk_npcai can still talk to them as they leave; then they're just traffic again
    SetTimeout(120000, function()
        if ByVehicle[s.key] then return end
        for net in pairs(s.occ) do UnbindSubject(net) end
    end)
    log('stop by %d ended: %s', src, outcome)
end

-- ─── starting a stop ──────────────────────────────────────────────────────────

local function refuse(src, why) TriggerClientEvent('c3r:stop:refused', src, why) end

local function gender(male) return male and 'Male' or 'Female' end

local function chance(list, secret) return math.random() < ((list or {})[secret] or 0) end

-- How they carry themselves, for the officer's game to show (it never learns why).
local function look(t)
    if t.secret == 'drunk' then return 'drunk' end
    if t.secret == 'drugs' then return 'high' end
    if t.demeanor == 'nervous' or ((t.secret == 'warrant' or t.secret == 'stolen') and math.random() < 0.6) then return 'nervous' end
    if t.demeanor == 'rude' then return 'rude' end
end

-- Each person's questions as they stand: the tree opens follow-ups as they talk.
local function send_questions(s)
    for net, o in pairs(s.occ) do
        TriggerClientEvent('c3r:stop:questions', s.src, net, Dialogue.available(o, { stop = s }))
    end
end

-- Someone on foot the officer walked up to: their own person and story (a pedestrian's, like a passenger's),
-- and the same menu, less what's about a car. p = { net, male }.
local function start_foot(src, p)
    local ped = type(p) == 'table' and entity(p.net) or 0
    if ped == 0 or IsPedAPlayer(ped) or GetVehiclePedIsIn(ped, false) ~= 0 or dist(src, ped) > TALK_RANGE then return end
    local key = 'ped:' .. p.net
    if ByVehicle[key] then return refuse(src, 'Another unit is already talking to them.') end
    ByVehicle[key] = src
    local ok, g = pcall(Generator.passenger, p.male == true) -- waits on SQL
    if not ok or Stops[src] or not IsOnDuty(src) or not GetPlayerName(src) then
        ByVehicle[key] = nil
        if not ok then refuse(src, 'Unable to talk to them (database error).') end
        return
    end
    local o = { net = p.net, role = 'pedestrian', person = g.person, truth = g.truth, items = g.items, answers = {}, facts = {} }
    o.pockets = Generator.some(Data.pockets, math.random(1, 3))
    for _, item in ipairs(g.items) do table.insert(o.pockets, 1, item) end -- no car to stash it in: it's all on them
    local s = { src = src, key = key, occ = { [p.net] = o }, driver = o, car_items = {}, foot = true }
    BindSubject(p.net, g.person, nil, g.items, g.truth)
    Stops[src] = s
    TriggerEvent('c3r:stopStarted', src, nil, nil)
    TriggerClientEvent('c3r:stop:started', src, nil, { { net = p.net, role = 'pedestrian', look = look(g.truth) } },
        { foot = true, contact = p.net }, Dialogue.CATEGORIES)
    send_questions(s)
    log('contact by %d on foot: %s %s (%s)', src, g.person.first, g.person.last, g.truth.secret)
end

--[[ veh_net: the car. people: { { seat, net, male }, ... }, the driver (seat -1) first, read on the
     officer's game; every one is checked against the car here. info = { make, model, color }.
     opts = { parked = true, contact = ped net }: walked up to a car that's standing still (no pull-over, no
     chase), to talk to that person. opts = { foot = true }: someone on foot, veh_net nil, people = { { net, male } }.
     opts = { empty = true }: a car nobody's in (to search or tow): its owner's things are in it. ]]
RegisterNetEvent('c3r:stop:start', function(veh_net, people, info, opts)
    local src = source
    local function no(why) log('stop by %d refused: %s', src, why) end
    if not IsOnDuty(src) then return no('off duty') end
    if Stops[src] then return no('already on a stop') end
    opts = type(opts) == 'table' and opts or {}
    if opts.foot then return start_foot(src, type(people) == 'table' and people[1]) end
    local veh = entity(veh_net)
    if veh == 0 then return no(('car not known to the server (net %s)'):format(tostring(veh_net))) end
    if ByVehicle[veh_net] then return refuse(src, 'Another unit already has that vehicle stopped.') end
    if dist(src, veh) > Config.Target.lose_distance + 10.0 then return no('too far away') end

    -- who's really in which seat: a client can't name a ped that isn't in this car
    local seats, count = {}, 0
    for _, p in ipairs(type(people) == 'table' and people or {}) do
        if count >= 4 then break end
        local seat = type(p) == 'table' and math.type(p.seat) == 'integer' and p.seat or nil
        local ped = seat and entity(p.net) or 0
        if seat and seat >= -1 and seat <= 6 and not seats[seat] and ped ~= 0 and not IsPedAPlayer(ped)
            and GetPedInVehicleSeat(veh, seat) == ped then
            seats[seat], count = { net = p.net, male = p.male == true }, count + 1
        end
    end
    local empty = opts.empty == true and count == 0
    if not seats[-1] and not empty then return no('no driver') end

    local plate = str(GetVehicleNumberPlateText(veh), 8)
    plate = plate and plate:upper():gsub('%s+', '')
    if not plate or plate == '' then return no('no plate') end
    info = type(info) == 'table' and info or {}
    ByVehicle[veh_net] = src -- held while everyone is made up (that waits on SQL)
    if Staged[veh_net] then -- a staged violator: whoever's game was driving it lets go (this officer's own: the stop takes over)
        if Staged[veh_net] ~= src then TriggerClientEvent('c3r:staged:release', Staged[veh_net], veh_net) end
        Staged[veh_net] = nil
    end
    local parked = opts.parked == true or empty

    local ok, gen = pcall(function()
        -- the same car again soon: the same people, and anyone new who's got in since is made up. Empty: its
        -- owner (or whoever last drove it), for what they left in it.
        local r = Recent[plate]
        local male = seats[-1] and seats[-1].male
        local out = not empty and r and os.time() - r.at < RECENT_SECONDS and r.driver.person.gender == gender(male) and r
        if male == nil then male = math.random() < .5 end
        out = out or { driver = Generator.stop(plate, {
            make = str(info.make, 30), model = str(info.model, 30), color = str(info.color, 30), male = male,
        }), passengers = {} }
        for seat, p in pairs(seats) do
            local g = out.passengers[seat]
            if seat ~= -1 and not (g and g.person.gender == gender(p.male)) then
                out.passengers[seat] = Generator.passenger(p.male)
            end
        end
        return out
    end)
    -- the officer may have left, gone off duty or started another stop while that waited on SQL
    if not ok or Stops[src] or not IsOnDuty(src) or not GetPlayerName(src) then
        ByVehicle[veh_net] = nil
        if not ok then
            print('[c3r] could not make up the people in the car: ' .. tostring(gen))
            refuse(src, 'Unable to start the stop (database error).')
        end
        return
    end
    gen.at = os.time()
    if not empty then Recent[plate] = gen end
    for p, r in pairs(Recent) do
        if os.time() - r.at > RECENT_SECONDS then Recent[p] = nil end
    end

    local vehicle = gen.driver.vehicle
    local s = { src = src, key = veh_net, veh_net = veh_net, plate = plate, vehicle = vehicle, occ = {}, car_items = {},
                parked = parked or nil, empty = empty or nil }
    local absent = empty and { facts = {} } or nil -- whoever left their things in an empty car: what's theirs is still evidence
    if empty then
        for _, item in ipairs(gen.driver.items) do s.car_items[#s.car_items + 1] = { name = item, owner = absent } end
    end
    local list = {} -- what the officer's game is told: seats and roles, never who they are
    for seat, p in pairs(seats) do
        local g = seat == -1 and gen.driver or gen.passengers[seat]
        if g then
            local o = { net = p.net, seat = seat, role = seat == -1 and 'driver' or 'passenger', person = g.person,
                        truth = g.truth, items = g.items, vehicle = vehicle, answers = {}, facts = {} }
            s.occ[p.net] = o
            if seat == -1 then s.driver = o end
            local on, car = Generator.stash(g.items)
            o.pockets = Generator.some(Data.pockets, math.random(1, 3))
            for _, item in ipairs(on) do table.insert(o.pockets, 1, item) end
            for _, item in ipairs(car) do s.car_items[#s.car_items + 1] = { name = item, owner = o } end
            BindSubject(p.net, g.person, vehicle, g.items, g.truth)
            list[#list + 1] = { net = p.net, seat = seat, role = o.role, look = look(g.truth) }
        end
    end
    for _, item in ipairs(Generator.some(Data.car, math.random(1, 3))) do s.car_items[#s.car_items + 1] = { name = item } end
    if (vehicle and vehicle.stolen) or gen.driver.truth.secret == 'stolen' then
        s.car_items[#s.car_items + 1] = { name = 'Ignition damaged, hot-wired', owner = s.driver or absent }
    end
    Stops[src] = s
    -- something to hide: they may run instead of pulling over
    s.pursuit = not parked and chance(Config.Flee.car, gen.driver.truth.secret) or nil
    -- who's driving isn't known until they're identified (ID or name): see identify()
    if empty then
        TriggerEvent('c3r:vehicleContact', src, vehicle) -- nobody to stop: a car looked at
    else
        TriggerEvent(s.pursuit and 'c3r:pursuitStarted' or 'c3r:stopStarted', src, nil, vehicle)
    end
    -- only what changes how they drive: the truth itself stays on the server
    TriggerClientEvent('c3r:stop:started', src, veh_net, list, { slow = gen.driver.truth.secret == 'drunk',
        flee = s.pursuit, bail = s.pursuit and math.random() < Config.Flee.bail,
        parked = parked or nil, empty = empty or nil,
        contact = parked and math.type(opts.contact) == 'integer' and s.occ[opts.contact] and opts.contact or nil },
        Dialogue.CATEGORIES)
    send_questions(s)
    log('stop by %d: %s, %s %s (%s), %d passenger(s)', src, plate, gen.driver.person.first, gen.driver.person.last,
        gen.driver.truth.secret, #list - 1)
end)

-- ─── what the officer does ────────────────────────────────────────────────────

local ENDINGS = { cite = 'cited', warn = 'warning', release = 'released' }

local ACT = {}

function ACT.greet(s, o)
    say(s, s.foot and "Hi there. Can I talk to you for a minute?"
        or s.parked and "Hi there. Mind if I ask you a few questions?"
        or 'Hi there. I pulled you over today, I just need a minute of your time.', 'officer')
    say(s, Dialogue.answer('greet', o), o)
end

function ACT.ask(s, o, q)
    if not q or not Dialogue.can_ask(q, o, { stop = s }) then return end -- not asked yet, or a follow-up not opened
    say(s, Dialogue.label(q, o, { stop = s }), 'officer')
    say(s, Dialogue.answer(q, o, { stop = s }), o)
    if q == 'name' then identify(s, o, given_identity(o)) end
end

-- The driver hands over licence and registration; a passenger, just their ID.
function ACT.licence(s, o)
    local driver = o.role == 'driver'
    say(s, driver and 'Hand me your license, registration and proof of insurance.' or 'Can I see some ID?', 'officer')
    if driver then voice(s, 'id') end
    say(s, Dialogue.answer('licence', o), o)
    if o.truth.id ~= 'hands' then return end
    local p, v = o.person, driver and s.vehicle or nil
    -- the registration comes with the licence: the car's record, and the owner's address (theirs, or the owner's)
    if v and s.owner_address == nil then
        local owner = v.owner_id and v.owner_id ~= p.id and Db.getPerson(v.owner_id)
        s.owner_address = owner and owner.address or (v.owner_id == p.id and p.address) or ''
    end
    TriggerClientEvent('c3r:stop:idcard', s.src, {
        first = p.first, last = p.last, dob = p.dob, gender = p.gender, address = p.address, dl = p.dl, net = o.net,
        plate = v and v.plate or nil, owner = v and v.owner or nil,
        vehicle = v and { plate = v.plate, make = v.make, model = v.model, year = v.year, owner = v.owner,
                          owner_address = s.owner_address, reg_valid = v.reg_valid } or nil,
    })
    identify(s, o, p)
end

local DRUG_NAMES = { { 'marijuana', 'THC' }, { 'joint', 'THC' }, { 'powder', 'Cocaine' }, { 'crystal', 'Methamphetamine' },
                     { 'pills', 'Opioids' }, { 'pipe', 'Methamphetamine' } }

local function result(s, title, text, bad)
    TriggerClientEvent('c3r:stop:result', s.src, { title = title, text = text, bad = bad })
end

function ACT.breath(s, o)
    say(s, 'Please blow into this.', 'officer')
    voice(s, 'breath')
    say(s, Dialogue.answer('breath', o), o)
    local bac = tonumber(o.truth.bac) or math.random(0, 2) / 100
    local over = bac >= Config.Tests.bac_limit
    result(s, 'Breathalyzer', ('%.3f BAC%s'):format(bac, over and ' · over the limit' or ''), over)
    note(s, ('Breathalyzer, %s: %.3f BAC%s'):format(label(o), bac, over and ' (over the limit)' or ''))
end

function ACT.drugs(s, o)
    say(s, "I'm going to swab your mouth for a drug test. It only takes a second.", 'officer')
    say(s, Dialogue.answer('drugtest', o), o)
    local found
    if o.truth.secret == 'drugs' then
        for _, item in ipairs(o.items or {}) do
            for _, d in ipairs(DRUG_NAMES) do
                if not found and item:lower():find(d[1], 1, true) then found = d[2] end
            end
        end
        found = found or 'THC'
    end
    result(s, 'Drug swab', found and ('Positive · ' .. found) or 'Negative', found ~= nil)
    note(s, ('Drug swab, %s: %s'):format(label(o), found and ('positive for ' .. found) or 'negative'))
end

-- Where someone is (in or out of the car) is the officer's game's call: only it sees the ped, and a task
-- can fail there. Asking again is harmless, so there's no guard here to get stuck on.
local function order(officer_line, answer, task)
    return function(s, o)
        say(s, officer_line, 'officer')
        say(s, Dialogue.answer(answer, o), o)
        TriggerClientEvent('c3r:stop:task', s.src, task, o.net)
    end
end

local GUILTY = { drunk = true, drugs = true, warrant = true, stolen = true }

-- Someone with a reason to run, once per stop: told to get out or turning to be cuffed, they bolt.
local function runs(s, o, odds)
    if o.ran or not chance(odds or Config.Flee.foot, o.truth.secret) then return false end
    o.ran, o.out_srv = true, true
    o.facts.ran = 'yes' -- (they remember it: the questions and answers change)
    say(s, Dialogue.answer('run', o), o)
    TriggerClientEvent('c3r:stop:task', s.src, 'flee', o.net)
    note(s, ('%s fled on foot'):format(label(o)))
    return true
end

function ACT.exit(s, o)
    say(s, 'Step out of the vehicle for me, please.', 'officer')
    -- the first time, the rude and the guilty may dig in; asked again, they get out
    if not o.refused and (o.truth.demeanor == 'rude' or GUILTY[o.truth.secret]) and math.random() < Config.Flee.refuse then
        o.refused = true
        return say(s, Dialogue.answer('refuse', o), o)
    end
    if runs(s, o) then return end
    say(s, Dialogue.answer('exit', o), o)
    o.out_srv = true
    TriggerClientEvent('c3r:stop:task', s.src, 'exit', o.net)
end
local back_in = order('Go ahead and get back in the vehicle.', 'back', 'back')
function ACT.back(s, o) o.out_srv = false back_in(s, o) end
ACT.follow = order('Come with me, please. Walk this way.', 'follow', 'follow')
ACT.stay = order('Stay right there.', 'back', 'stay')
ACT.handsup = order('Let me see your hands!', 'handsup', 'handsup')

-- A ticket or a warning is written down, but they stay until told they're free to go; the stop then ends
-- with the strongest of what they got (cited over warning over released).
local RANK = { released = 0, warning = 1, cited = 2 }
-- Said differently to someone who wasn't pulled over.
local STILL_LINES = { release = { foot = "You're free to go. Have a good one.", parked = "That's all. You're free to go. Have a good day." } }

local function ending(kind, officer_line)
    return function(s, o)
        local still = STILL_LINES[kind]
        say(s, still and (s.foot and still.foot or s.parked and still.parked) or officer_line, 'officer')
        say(s, Dialogue.answer(kind, o), o)
        local outcome = ENDINGS[kind]
        if kind == 'release' then return finish(s.src, s.outcome or outcome) end
        if RANK[outcome] > RANK[s.outcome or 'released'] then s.outcome = outcome end
        note(s, ('%s, %s'):format(kind == 'cite' and 'Citation issued' or 'Verbal warning', label(o)))
    end
end
ACT.cite = ending('cite', "I'm writing you a citation. Sign here, please.")

-- ─── searches, field sobriety, arrests, the tow ───────────────────────────────

-- A search's finds: whatever is part of someone's story is evidence (and opens "want to explain this?"
-- for them), the rest is everyday clutter. list = { { name, owner } }. Shown once the search is done.
local function found(s, what, list, delay)
    local bad, plain = {}, {}
    for _, f in ipairs(list) do
        if f.owner then
            bad[#bad + 1] = f.name
            f.owner.facts.found = f.owner.facts.found or f.name:lower()
        else
            plain[#plain + 1] = f.name:lower()
        end
    end
    local text = #bad > 0 and ('Found: %s.'):format(table.concat(bad, ', ')) or 'Nothing illegal.'
    if #plain > 0 then text = text .. (' Also %s.'):format(table.concat(plain, ', ')) end
    TriggerClientEvent('c3r:stop:result', s.src, { title = what, text = text, bad = #bad > 0, delay = delay })
    note(s, ('%s: %s'):format(what, #bad > 0 and (table.concat(bad, ', ') .. ' (seized)') or 'nothing illegal'))
end

function ACT.frisk(s, o)
    say(s, "I'm going to search you. Do you have anything you would like to declare before I proceed?", 'officer')
    voice(s, 'frisk')
    say(s, Dialogue.answer('frisk', o), o)
    TriggerClientEvent('c3r:stop:task', s.src, 'frisk', o.net)
    local list = {}
    for _, item in ipairs(o.pockets or {}) do
        local theirs = false
        for _, x in ipairs(o.items or {}) do theirs = theirs or x == item end
        list[#list + 1] = { name = item, owner = theirs and o or nil }
    end
    found(s, ('Pat-down, %s'):format(label(o)), list, 7000)
end

function ACT.search_car(s, o)
    if s.search_said then return found(s, 'Vehicle search', s.car_items, 8000) end -- (searched again: the same finds)
    s.search_said = true
    say(s, "I'm going to search the vehicle.", 'officer')
    if o then say(s, Dialogue.answer('search_car', o), o) end
    TriggerClientEvent('c3r:stop:task', s.src, 'search_car', o and o.net)
    local consent = s.driver and s.driver.facts.consent
    note(s, ('Vehicle searched (%s)'):format(consent == 'yes' and 'with consent'
        or consent == 'no' and 'consent refused' or 'consent not asked'))
    found(s, 'Vehicle search', s.car_items, 8000)
end

-- Eyes (HGN: 6 clues, 4 = impaired), walk-and-turn (8, 2 = impaired), one-leg stand (4, 2 = impaired).
-- -> hgn, wat, ols, impaired
function Sobriety(t)
    local drunk = (tonumber(t.bac) or 0) >= Config.Tests.bac_limit
    local high = t.secret == 'drugs'
    local hgn = drunk and math.random(4, 6) or math.random(0, high and 2 or 1)
    local wat = (drunk or high) and math.random(2, drunk and 8 or 5) or math.random(0, 1)
    local ols = (drunk or high) and math.random(2, 4) or math.random(0, 1)
    return hgn, wat, ols, hgn >= 4 or wat >= 2 or ols >= 2
end

function ACT.sobriety(s, o)
    say(s, "I'm going to have you do a few tests. Follow my pen with your eyes, then walk this line, heel to toe.", 'officer')
    say(s, Dialogue.answer('sobriety', o), o)
    local hgn, wat, ols, impaired = Sobriety(o.truth)
    TriggerClientEvent('c3r:stop:task', s.src, 'sobriety', o.net, { impaired = impaired })
    local text = ('Eyes %d/6 · Walk-and-turn %d/8 · One-leg stand %d/4'):format(hgn, wat, ols)
    TriggerClientEvent('c3r:stop:result', s.src, { title = 'Field sobriety', bad = impaired, delay = 12000,
        text = text .. (impaired and ' · Signs of impairment' or ' · Passed') })
    note(s, ('Field sobriety, %s: %s (%s)'):format(label(o), text, impaired and 'impaired' or 'passed'))
end

function ACT.cuff(s, o)
    if o.cuffed then return end
    say(s, 'Turn around and put your hands behind your back.', 'officer')
    if runs(s, o) then return end
    say(s, Dialogue.answer('cuff', o), o)
    o.cuffed = true
    TriggerClientEvent('c3r:stop:task', s.src, 'cuff', o.net)
    say(s, 'You have the right to remain silent. Anything you say can and will be used against you in the court of law. '
        .. 'If you cannot afford an attorney, one will be appointed for you.', 'officer')
    voice(s, 'miranda')
    note(s, ('%s placed under arrest'):format(label(o)))
end

function ACT.uncuff(s, o)
    if not o.cuffed then return end
    say(s, "I'm taking the cuffs off. Don't make me regret it.", 'officer')
    say(s, Dialogue.answer('uncuff', o), o)
    o.cuffed = nil
    TriggerClientEvent('c3r:stop:task', s.src, 'uncuff', o.net)
    note(s, ('%s released from handcuffs'):format(label(o)))
end

-- Only for someone in cuffs.
local function custody(officer_line, answer, task)
    local run = order(officer_line, answer, task)
    return function(s, o) if o.cuffed then run(s, o) end end
end
local walk_with, stand_there = custody('Walk with me.', 'escort', 'escort'), custody('Stand right there.', 'back', 'escort')
function ACT.escort(s, o) -- held at the officer's side, or let go of
    o.escorted = o.cuffed and not o.escorted
    if o.escorted then walk_with(s, o) else stand_there(s, o) end
end
local seat = custody('Watch your head.', 'seat', 'seat')
function ACT.seat(s, o) o.escorted = nil seat(s, o) end
ACT.unseat = custody('Step out for me.', 'unseat', 'unseat')

-- ─── felony stop ──────────────────────────────────────────────────────────────
-- High risk: everyone is ordered out one at a time from cover (PA range), walked back and put on their knees.
-- Each order may be frozen at once, or answered by running; the driver may floor it when it starts.

function ACT.felony(s)
    if s.felony or s.foot or s.empty or s.pursuit then return end -- (said twice: nothing re-rolls)
    s.felony = true
    say(s, 'Police! Driver, turn off the engine and drop the keys out the window! Nobody move!', 'officer')
    note(s, 'Felony stop initiated')
    local d = s.driver
    if d and not d.out_srv and not d.cuffed and chance(Config.Felony.drive, d.truth.secret) then
        s.felony, s.pursuit = nil, true
        d.facts.ran = 'yes'
        say(s, Dialogue.answer('run', d), d)
        note(s, 'Driver fled in the vehicle')
        TriggerEvent('c3r:pursuitStarted', s.src, d.identified, s.vehicle)
        return TriggerClientEvent('c3r:stop:fleeCar', s.src, math.random() < Config.Flee.bail)
    end
    if d and not d.out_srv then say(s, Dialogue.answer('felony', d), d) end
    TriggerClientEvent('c3r:felony', s.src)
end

local FELONY_LINES = {
    fel_out = { driver = 'Driver! Step out of the vehicle with your hands up! Face away from me!',
                passenger = 'Passenger! Step out of the vehicle with your hands up! Face away from me!' },
    fel_back = 'Walk backwards toward my voice! Keep your hands up!',
    fel_kneel = 'Stop! Get down on your knees! Cross your ankles!',
}
local function felony_order(kind)
    return function(s, o)
        if not s.felony or not o or o.cuffed then return end
        if (kind == 'fel_out') == (o.out_srv == true) then return end -- out: only someone in the car; the rest: only someone out
        local line = FELONY_LINES[kind]
        say(s, type(line) == 'table' and (line[o.role] or line.passenger) or line, 'officer')
        if not o.froze and math.random() < Config.Felony.freeze then -- frozen: asked again, they move
            o.froze = true
            return say(s, Dialogue.answer('freeze', o), o)
        end
        if runs(s, o, Config.Felony.run) then return end
        say(s, Dialogue.answer(kind, o), o)
        if kind == 'fel_out' then o.out_srv = true end
        TriggerClientEvent('c3r:stop:task', s.src, kind, o.net)
    end
end
ACT.fel_out, ACT.fel_back, ACT.fel_kneel = felony_order('fel_out'), felony_order('fel_back'), felony_order('fel_kneel')

-- To the impound lot, for the reason the papers (or the stop) give.
function ACT.tow(s)
    if s.towed then return end
    s.towed = true
    local v, d = s.vehicle or {}, s.driver
    local why = (v.stolen or (d and d.truth.secret == 'stolen')) and 'recovered stolen vehicle'
        or (d and d.cuffed) and 'driver arrested'
        or v.ins_valid == false and 'no insurance' or v.reg_valid == false and 'expired registration'
        or (d and d.person and d.person.dl ~= 'Valid') and 'unlicensed driver' or 'officer discretion'
    say(s, ('Dispatch, requesting a tow for plate %s.'):format(s.plate), 'officer')
    TriggerClientEvent('c3r:stop:tow', s.src)
    note(s, ('Vehicle towed to impound: %s'):format(why))
end
ACT.warn = ending('warn', "I'm letting you off with a warning today.")
ACT.release = ending('release', "You're free to go. Drive safe.") -- (on foot, or not pulled over: see ending)

local CAR_ACTS = { search_car = true, tow = true, felony = true } -- done at the car, not to a person
-- Shouted (the PA, or a felony stop's orders): heard from Config.PaRange. Everything else is said face to face.
local SHOUTED = { exit = true, back = true, handsup = true, stay = true, felony = true, fel_out = true, fel_back = true, fel_kneel = true }
local FELONY_ONLY = { felony = true, fel_out = true, fel_back = true, fel_kneel = true }

-- target = the occupant's ped net id (the driver when missing)
RegisterNetEvent('c3r:stop:act', function(action, arg, target, pa)
    local src = source
    local s = Stops[src]
    local radio_tow = action == 'tow' and pa
    if radio_tow and (not s or s.towed) then return TriggerClientEvent('c3r:stop:towRefused', src) end -- (said yes over the radio: say no back)
    if not s or type(action) ~= 'string' then return end
    if action == 'cancel' then return finish(src, s.outcome or 'cancelled') end -- driven away: ticketed or warned still counts
    local fn = ACT[action]
    if not fn then return end
    local o = s.occ[tonumber(target) or -1]
    if not o and (pa or FELONY_ONLY[action]) and not CAR_ACTS[action] then return end -- a shouted order at nobody here
    o = o or s.driver
    if not o and not CAR_ACTS[action] then return end -- an empty car: only what's done to the car
    local ent = entity(CAR_ACTS[action] and s.veh_net or o.net)
    local range = (pa or FELONY_ONLY[action]) and SHOUTED[action] and Config.PaRange or TALK_RANGE
    if radio_tow then range = Config.CancelDistance end -- a tow asked for over the radio
    if ent == 0 or dist(src, ent) > range then
        if radio_tow then TriggerClientEvent('c3r:stop:towRefused', src) end
        return
    end
    fn(s, o, type(arg) == 'string' and arg or nil)
    if Stops[src] == s then send_questions(s) end -- what they said may open (or close) questions, theirs or the others'
end)

-- The officer's game on a chase (only it sees the peds): 'caught' when someone gives up (net = who; a car
-- chase is over then too), 'lost' when they got away, which ends the stop.
RegisterNetEvent('c3r:stop:pursuit', function(state, net)
    local src = source
    local s = Stops[src]
    if not s then return end
    local o = s.occ[tonumber(net) or -1]
    if state == 'lost' then
        note(s, ('%s got away'):format(o and label(o) or 'The suspect'))
        return finish(src, 'fled')
    end
    if state ~= 'caught' then return end
    if s.pursuit then
        s.pursuit = nil
        TriggerEvent('c3r:pursuitEnded', src)
        note(s, 'Pursuit ended')
    end
    if o then
        o.out_srv, o.ran, o.facts.ran = true, true, 'yes' -- (gave up on foot, out of the car; they know they ran)
        say(s, Dialogue.answer('surrender', o), o)
        note(s, ('%s gave up'):format(label(o)))
    end
    -- whoever ran is high risk now: the rest of the stop is a felony stop (walk them back, on their knees, the
    -- others out one at a time)
    if not s.felony and not s.foot then
        s.felony = true
        note(s, 'Felony stop initiated')
        TriggerClientEvent('c3r:felony', src, true)
    end
end)

-- ─── staged violators ────────────────────────────────────────────────────────
-- The officer's game picks a car near them on patrol (client/staged.lua); its driver gets a story here, kept in
-- Recent so pulling it over (or running its plate) finds the same person, and the game is told how to drive it.

local StagedAt = {} -- [src] = os.time() of their last staged car
local BEHAVIOUR = { drunk = { 'weave' }, drugs = { 'weave', 'speed' }, stolen = { 'speed' }, warrant = { 'speed' },
                    suspended = { 'lights', 'speed' }, unlicensed = { 'lights', 'speed' }, expired = { 'lights' },
                    clean = { 'speed' }, nervous = { 'lights' } }

-- people = { { seat, net, male } } as their game saw them; info = { make, model, color }
RegisterNetEvent('c3r:staged:pick', function(veh_net, people, info)
    local src = source
    if not Config.Staged.enabled or not IsOnDuty(src) or Stops[src] then return end
    if os.time() - (StagedAt[src] or 0) < math.floor(Config.Staged.every[1] * .8) then return end -- (a game asking too often)
    local veh = entity(veh_net)
    if veh == 0 or ByVehicle[veh_net] or Staged[veh_net] or dist(src, veh) > 200.0 then return end
    for seat = -1, 6 do -- nobody's ride: no players aboard
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and IsPedAPlayer(ped) then return end
    end
    local d = type(people) == 'table' and people[1]
    if type(d) ~= 'table' or d.seat ~= -1 or entity(d.net) == 0 or GetPedInVehicleSeat(veh, -1) ~= entity(d.net) then return end
    local plate = str(GetVehicleNumberPlateText(veh), 8)
    plate = plate and plate:upper():gsub('%s+', '')
    if not plate or plate == '' then return end
    local function fresh() local r = Recent[plate] return r and os.time() - r.at < RECENT_SECONDS end
    if fresh() then return end -- already somebody: they keep it
    StagedAt[src] = os.time()
    info = type(info) == 'table' and info or {}
    local ok, gen = pcall(Generator.stop, plate, { make = str(info.make, 30), model = str(info.model, 30),
        color = str(info.color, 30), male = d.male == true, secret = Generator.weighted(Config.Staged.secrets) })
    if not ok then return print('[c3r] could not stage ' .. plate .. ': ' .. tostring(gen)) end
    -- meanwhile (that waited on SQL) it may have been stopped or run: then that story stands
    if fresh() or ByVehicle[veh_net] or Staged[veh_net] or not IsOnDuty(src) or Stops[src] or not GetPlayerName(src) then return end
    Recent[plate] = { driver = gen, passengers = {}, at = os.time() }
    Staged[veh_net] = src
    SetTimeout((Config.Staged.lasts + 30) * 1000, function() if Staged[veh_net] == src then Staged[veh_net] = nil end end)
    local ways = BEHAVIOUR[gen.truth.secret] or { 'speed' }
    TriggerClientEvent('c3r:staged:drive', src, veh_net, ways[math.random(#ways)])
    log('staged for %d: %s (%s)', src, plate, gen.truth.secret)
end)

-- ─── backup (client/backup.lua) ──────────────────────────────────────────────
-- The officer's game spawns and runs its own units; here: what goes on the MDT timeline, and deleting an officer's
-- units if they drop with some still out (their game can't any more).

local BACKUP_LABEL = { ambulance = 'ambulance', police = 'prisoner transport', tow = 'tow truck', coroner = 'coroner',
                       fire = 'fire department', mechanic = 'mechanic', roadservice = 'road service',
                       animalrescue = 'animal control', taxi = 'taxi', cover = 'cover unit',
                       light = 'pursuit units', medium = 'pursuit units', heavy = 'pursuit units', air = 'air unit' }
local BackupNoteAt, BackupNets = {}, {}

-- what: 'requested' (kind) | 'transported' (count) | 'treated' (count) | 'removed' (count) | 'repaired' |
-- 'hospital' (count) | 'pronounced' (count) | 'revived' | 'stabilised' (the medical wheel's, as kind 'ambulance')
RegisterNetEvent('c3r:backup', function(what, kind, count)
    local src = source
    if not IsOnDuty(src) or not BACKUP_LABEL[kind] then return end
    if (BackupNoteAt[src] or 0) > GetGameTimer() - 250 then return end -- (a few a second at most)
    BackupNoteAt[src] = GetGameTimer()
    count = math.type(count) == 'integer' and math.max(0, math.min(count, 20)) or 0
    local text = what == 'requested' and ('Backup requested: %s'):format(BACKUP_LABEL[kind])
        or what == 'transported' and ('Prisoner transport took %d into custody'):format(count)
        or what == 'treated' and ('Paramedics treated %d'):format(count)
        or what == 'removed' and (kind == 'coroner' and 'Coroner removed %d deceased' or 'Animal control removed %d'):format(count)
        or what == 'repaired' and 'Vehicle repaired by the mechanic'
        or what == 'hospital' and ('Paramedics took %d to hospital'):format(count)
        or what == 'pronounced' and ('Paramedics pronounced %d dead at the scene'):format(count)
        or what == 'revived' and (count > 0 and ('Paramedics revived %d'):format(count) or 'Patient revived with CPR')
        or what == 'stabilised' and 'Patient stabilised: pressure on the wound'
    if text then TriggerEvent('c3r:note', src, text) end
end)

-- the officer's units, as network ids (sent whenever they change). Only what their game owns right now is kept
-- (theirs to delete): a client can't get anyone else's car or ped deleted by naming it and leaving.
RegisterNetEvent('c3r:backup:units', function(nets)
    local src = source
    if type(nets) ~= 'table' then return end
    local list = {}
    for i = 1, math.min(#nets, 60) do
        local ent = math.type(nets[i]) == 'integer' and NetworkGetEntityFromNetworkId(nets[i]) or 0
        if ent ~= 0 and DoesEntityExist(ent) and NetworkGetEntityOwner(ent) == src and not IsPedAPlayer(ent) then
            list[#list + 1] = ent
        end
    end
    BackupNets[src] = list
end)

-- A pursuit unit up ahead lays a Stop Stick (lwk_stopstick) across the suspect's path; 'c3r:backup:spikesUp' pulls
-- them all. Only in a car chase, near the officer's chase, two at a time.
local Spikes = {} -- [src] = { stick ids }
local function spikes_up(src)
    for _, id in ipairs(Spikes[src] or {}) do pcall(function() exports.lwk_stopstick:remove(id) end) end
    Spikes[src] = nil
end
RegisterNetEvent('c3r:backup:spikes', function(at, angle, from)
    local src = source
    local s = Stops[src]
    if not IsOnDuty(src) or not s or not s.pursuit or GetResourceState('lwk_stopstick') ~= 'started' then return end
    if type(at) ~= 'vector3' or type(angle) ~= 'number' or (from and type(from) ~= 'vector3') then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - at) > 600.0 or (from and #(from - at) > 15.0) then return end
    local list = Spikes[src] or {}
    if #list >= 2 then return end
    local ok, id = pcall(function() return exports.lwk_stopstick:deploy(src, at, angle, from) end)
    if ok and id then
        list[#list + 1] = id
        Spikes[src] = list
        note(s, 'Stop Sticks deployed by a pursuit unit')
    end
end)
RegisterNetEvent('c3r:backup:spikesUp', function() spikes_up(source) end)
AddEventHandler('c3r:pursuitEnded', spikes_up)

-- A tow that failed (no truck, it never got there, or couldn't load the car): it can be asked for again, up to
-- Config.Tow.tries times, then the car is just removed. Only a car near the officer with no player in it.
local TowFails, TowFailAt = {}, {}
RegisterNetEvent('c3r:tow:failed', function(net)
    local src = source
    local ent = entity(net)
    if not IsOnDuty(src) or ent == 0 or GetEntityType(ent) ~= 2 or dist(src, ent) > Config.CancelDistance then return end
    if (TowFailAt[src] or 0) > GetGameTimer() - 5000 then return end -- (a real tow takes far longer)
    TowFailAt[src] = GetGameTimer()
    for seat = -1, 14 do
        local p = GetPedInVehicleSeat(ent, seat)
        if p ~= 0 and IsPedAPlayer(p) then return end
    end
    local s = Stops[src]
    local of_stop = s and s.veh_net == net
    TowFails[net] = (TowFails[net] or 0) + 1
    if TowFails[net] < Config.Tow.tries then
        if of_stop then s.towed = nil end
        return TriggerClientEvent('c3r:tow:retry', src, net)
    end
    TowFails[net] = nil
    if of_stop then note(s, 'Vehicle removed from the scene: tow truck unable to load it') end
    DeleteEntity(ent)
end)

AddEventHandler('playerDropped', function()
    local src = source
    TowFailAt[src] = nil
    Spikes[src] = nil -- (lwk_stopstick removes a dropped officer's sticks itself)
    for _, ent in ipairs(BackupNets[src] or {}) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    BackupNets[src], BackupNoteAt[src] = nil, nil
end)

AddEventHandler('c3r:duty', function(src, on)
    if not on then finish(src, 'cancelled') end
end)

-- Another resource ended the stop for them: lwk_npcai when someone is told they're free to go
-- ('released') or runs for it ('fled'), by voice. net = the ped it was about (anyone in the car), so a
-- stale call can't end a different stop. -> true when it ended one
local END_OUTCOMES = { released = true, cited = true, warning = true, fled = true, cancelled = true, arrested = true }
exports('endStop', function(src, net, outcome)
    src = tonumber(src)
    local s = Stops[src]
    if not s or not s.occ[tonumber(net) or -1] or not END_OUTCOMES[outcome] then return false end
    finish(src, outcome)
    return true
end)

AddEventHandler('playerDropped', function()
    finish(source, 'cancelled')
    StagedAt[source] = nil
    for net, src in pairs(Staged) do if src == source then Staged[net] = nil end end
end)

-- ─── every car has papers ─────────────────────────────────────────────────────
-- A plate run: the officer's game finds the car (within 150 m) and says what it is and who's at the wheel. Not on
-- file yet: its papers, owner and driver are made up then. Either way the driver is decided then and kept in
-- Recent, so pulling it over (or walking up to it) later finds the same person. Nothing near with that plate:
-- what's on file, or no record.

local Lookups, next_lookup = {}, 0 -- [id] = { src, done(info) }

local function plate_key(p) return type(p) == 'string' and p:upper():gsub('[^%w]', ''):sub(1, 8) or '' end

-- -> cb(vehicle | nil). Waits on SQL and on the officer's game, so it always answers through cb. quiet: don't
-- fire vehicleContact (an MDT search keeps the record itself; a radio plate check is a contact).
function LookupPlate(src, plate, cb, quiet)
    CreateThread(function()
        plate = plate_key(plate)
        if plate == '' then return cb(nil) end
        local v = Db.findVehicle(plate) -- on file already: it answers with that, whatever the car turns out to be
        next_lookup = next_lookup + 1
        local id = next_lookup
        Lookups[id] = { src = src, done = function(info)
            if type(info) ~= 'table' then return cb(v) end -- not near the officer: only what's on file
            if info.driver == nil and v then return cb(v) end -- nobody in it, papers on file: nothing to decide
            -- someone at the wheel already settled (a stop or a run a little while ago): the same person
            local r = Recent[plate]
            if r and info.driver ~= nil and os.time() - r.at < RECENT_SECONDS and r.driver.person.gender == gender(info.driver) then
                return cb(v or r.driver.vehicle)
            end
            -- who's at the wheel is decided now, so a stop of this car later finds the same person: the owner
            -- (or a relative, a friend, a thief) if the papers are on file, everyone made up if they aren't
            local ok, gen = pcall(Generator.stop, plate, {
                make = str(info.make, 30), model = str(info.model, 30), color = str(info.color, 30),
                male = info.driver == true or (info.driver == nil and math.random() < .5),
            })
            if not ok then print('[c3r] could not make up papers for ' .. plate .. ': ' .. tostring(gen)) return cb(v) end
            if info.driver ~= nil then Recent[plate] = { driver = gen, passengers = {}, at = os.time() } end
            if not quiet and not v then TriggerEvent('c3r:vehicleContact', src, gen.vehicle) end
            cb(gen.vehicle)
        end }
        TriggerClientEvent('c3r:describePlate', src, plate, id)
        SetTimeout(3000, function() -- their game never answered
            local l = Lookups[id]
            Lookups[id] = nil
            if l then cb(v) end
        end)
    end)
end
exports('lookupPlate', LookupPlate)

-- The vehicle menu's "Run plate": the record (made up now if it isn't on file) back to the officer's screen.
RegisterNetEvent('c3r:runPlate', function(plate)
    local src = source
    if not IsOnDuty(src) then return end
    LookupPlate(src, plate, function(v)
        if v then TriggerEvent('c3r:vehicleContact', src, v) end
        TriggerClientEvent('c3r:plateResult', src, plate_key(plate), v)
    end, true)
end)

-- info = { make, model, color, driver = true (a man at the wheel) | false (a woman) | nil (nobody) } | nil
RegisterNetEvent('c3r:describedPlate', function(id, info)
    local l = Lookups[tonumber(id) or -1]
    if not l or l.src ~= source then return end
    Lookups[tonumber(id)] = nil
    l.done(info)
end)
