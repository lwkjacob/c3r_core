--[[
    c3r — server: duty, the people / vehicle store, and the events other resources listen to.
    The full contract (every export and event) is in docs/contract.md.

    Events are server-only (TriggerEvent, never a net event), so a client can't fake a stop or a callout.
    Their records are the public ones; a ped's hidden truth only comes out through getPedSubject.
]]

local function log(fmt, ...)
    if Config.Debug then print(('[c3r] ' .. fmt):format(...)) end
end

-- ─── duty ─────────────────────────────────────────────────────────────────────
-- The player's state bag carries it to their client (and anyone else's), so isOnDuty never needs a round trip.

local Duty = {} -- [src] = their service while on duty: 'police' | 'ambulance'
local ACE = { police = function() return Config.DutyAce end, ambulance = function() return Config.Ems.ace end }

-- service: which one they're going on as (police unless said). c3rDuty is "on shift"; c3rService says as what.
local function set_duty(src, on, service)
    on = on == true
    service = service or 'police'
    if not ACE[service] then return false, 'no_service' end
    if (Duty[src] ~= nil) == on then
        if on and Duty[src] ~= service then return false, 'on_shift' end -- (end the shift first)
        return true
    end
    if on and ACE[service]() and not IsPlayerAceAllowed(src, ACE[service]()) then return false, 'not_allowed' end
    Duty[src] = on and service or nil
    if on then Player(src).state:set('c3rService', service, true) end -- (first: anything watching c3rDuty can read it)
    Player(src).state:set('c3rDuty', on, true)
    if not on then Player(src).state:set('c3rService', nil, true) end
    TriggerEvent('c3r:duty', src, on, service)
    log('%s is %s duty', GetPlayerName(src) or src, on and 'on' or 'off')
    return true
end

RegisterNetEvent('c3r:setDuty', function(on, service)
    local src = source
    local ok, reason = set_duty(src, on, type(service) == 'string' and service or nil)
    TriggerClientEvent('c3r:dutyResult', src, ok, reason)
end)

-- The bag lives on the player and outlasts a restart of this resource, but Duty doesn't: start everyone off.
CreateThread(function()
    for _, id in ipairs(GetPlayers()) do
        if Player(id).state.c3rDuty then
            Player(id).state:set('c3rDuty', false, true)
            Player(id).state:set('c3rService', nil, true)
        end
    end
end)

AddEventHandler('playerDropped', function()
    if Duty[source] then set_duty(source, false) end
end)

function IsOnDuty(src) return Duty[tonumber(src)] ~= nil end
function ServiceOf(src) return Duty[tonumber(src)] end -- 'police' | 'ambulance' | nil
exports('isOnDuty', IsOnDuty)
exports('getService', ServiceOf)
exports('setDuty', function(src, on, service) return set_duty(tonumber(src), on, service) end)

-- ─── people and vehicles ──────────────────────────────────────────────────────
-- These wait on SQL, and a call from another resource can't wait inside c3r: the result comes back
-- through cb. getPerson / createPerson also pass the truth to cb; it's for c3r's own scripts.

local function later(fn)
    return function(arg, cb)
        CreateThread(function()
            local ok, r = pcall(fn, arg)
            if not ok then print('[c3r] ' .. tostring(r)) end
            cb(ok and r or nil) -- always answer: a plate check waiting on this must not hang
        end)
    end
end

exports('getPerson', later(function(id) return (Db.getPerson(id)) end)) -- public record only
exports('getVehicle', later(Db.getVehicle))
exports('findVehicle', later(Db.findVehicle))
exports('createPerson', later(function(p) return (Db.createPerson(p)) end))
exports('findPeople', later(Db.findPeople)) -- by name: the MDT's search for someone nobody has met (a car's owner)
exports('createVehicle', later(Db.createVehicle))

-- ─── subjects ─────────────────────────────────────────────────────────────────
-- Which physical ped is which person: set when c3r puts someone in the world (a driver, a passenger,
-- a callout suspect). Keyed by network id, so any resource can ask about the ped in front of an officer.
-- Held in memory, so getPedSubject answers at once.

local Subjects = {} -- [net id] = { person, vehicle | nil, items = { 'Bag of weed', ... }, truth }

-- Phase 1's stop generator calls this for every ped it creates, with the records it just made.
function BindSubject(net, person, vehicle, items, truth)
    Subjects[net] = { person = person, vehicle = vehicle, items = items or {}, truth = truth or {} }
end

function UnbindSubject(net) Subjects[net] = nil end

-- Who a ped already is (put there by c3r, and not let go of yet), or nil: { person, vehicle, items, truth }.
function Subject(net) return Subjects[net] end

-- Is that person (their record id) someone's stop, or in a callout, right now? (They can't be in two places.)
function SubjectInUse(id)
    for _, s in pairs(Subjects) do if s.person and s.person.id == id then return true end end
    return false
end

-- Their warrant changed: whoever's in the world as them goes by the new one.
function UpdateSubject(id, warrant)
    for _, s in pairs(Subjects) do if s.person and s.person.id == id then s.person.warrant = warrant end end
end

-- -> person (public), vehicle | nil, items, truth | nil when c3r didn't put this ped there
exports('getPedSubject', function(net)
    local s = Subjects[tonumber(net) or -1]
    if not s then return nil end
    return s.person, s.vehicle, s.items, s.truth
end)
