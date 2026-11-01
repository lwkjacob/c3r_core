--[[ lwk_control — server: c3r subject caching, callout control, plate / name lookups. ]]

local LastPed, LastVehicle = {}, {} -- [src] = c3r person / vehicle (contract records)
local PedVehicle = {} -- [src] = the vehicle that came with LastPed (stop / pursuit); nil for a ped on foot
-- [src] = { id = owner's record id, at }: the registered owner of the last plate run, and LastPedAt[src] when
-- LastPed was identified: "run the name" after a plate check runs whoever it came back to
local LastOwner, LastPedAt = {}, {}

local function log(fmt, ...)
    if Config.Debug then print(('[lwk_control] ' .. fmt):format(...)) end
end

local function reply(src, key, msg) TriggerClientEvent('lwk_control:reply', src, key, msg) end

local function started(res) return GetResourceState(res) == 'started' end

local function plate_key(s) return type(s) == 'string' and s:upper():gsub('%s+', '') or nil end

-- ─── c3r event caching ─────────────────────────────────────────────────────

local function cache(src, ped, veh, why)
    if type(ped) == 'table' then
        -- the stopped driver keeps their car once identified; someone else on foot doesn't get it
        local other = LastPed[src] and LastPed[src].id ~= ped.id
        LastPed[src], LastPedAt[src] = ped, GetGameTimer()
        if veh then PedVehicle[src] = veh elseif other then PedVehicle[src] = nil end
    end
    if type(veh) == 'table' then LastVehicle[src] = veh end
    log('cached %s for %d: ped=%s plate=%s', why, src,
        type(ped) == 'table' and tostring(ped.first) .. ' ' .. tostring(ped.last) or '-', tostring(veh and veh.plate))
    -- raw values the plate readout maps to clips (year / color / make / model)
    if type(veh) == 'table' then
        log('  vehicle: year=%s color=%s make=%s model=%s', tostring(veh.year), tostring(veh.color),
            tostring(veh.make), tostring(veh.model))
    end
end

AddEventHandler('c3r:contact', function(src, ped) cache(src, ped, nil, 'npc') end)
AddEventHandler('c3r:vehicleContact', function(src, veh) cache(src, nil, veh, 'vehicle') end)

-- Traffic stop / pursuit start and end also go to the client for "what's my status".
local function activity(src, kind, on) TriggerClientEvent('lwk_control:activity', src, kind, on) end

AddEventHandler('c3r:stopStarted', function(src, ped, veh)
    -- a new stop: the last driver is not this one (c3r sends ped = nil until they're identified)
    LastPed[src], PedVehicle[src], LastOwner[src] = nil, veh, nil
    cache(src, ped, veh, 'pullover')
    activity(src, 'stop', true)
end)
AddEventHandler('c3r:stopEnded', function(src) activity(src, 'stop', false) end)
AddEventHandler('c3r:pursuitStarted', function(src, ped, veh)
    cache(src, ped, veh, 'pursuit')
    activity(src, 'pursuit', true)
end)
AddEventHandler('c3r:pursuitEnded', function(src) activity(src, 'pursuit', false) end)

-- A warrant or a BOLO issued or cleared: the next check answers with the new record.
AddEventHandler('c3r:record', function(ped, veh)
    for src, p in pairs(LastPed) do
        if ped and p.id == ped.id then LastPed[src] = ped end
    end
    for _, list in ipairs({ LastVehicle, PedVehicle }) do
        for src, v in pairs(list) do
            if veh and v.plate == veh.plate then list[src] = veh end
        end
    end
end)

AddEventHandler('c3r:calloutOffered', function(src) TriggerClientEvent('lwk_control:offered', src) end)

-- ─── traffic holds ────────────────────────────────────────────────────────────
-- One speed zone per player ("hold traffic" again moves it). Every client gets every zone, since
-- AI traffic is simulated by whichever client is nearest, not by the officer who asked.

local Zones = {} -- [src] = { x, y, z, radius, speed (m/s), expires (os.time) }

local function set_zone(src, zone)
    Zones[src] = zone
    TriggerClientEvent('lwk_control:zone', -1, src, zone)
end

RegisterNetEvent('lwk_control:holdTraffic', function(client_pos)
    local src = source
    -- Server-side position (OneSync); the client's only as a fallback, and only if it's a vector.
    local pos = GetEntityCoords(GetPlayerPed(src))
    if pos.x == 0.0 and pos.y == 0.0 then
        if type(client_pos) ~= 'vector3' then return end
        pos = client_pos
    end
    local moved = Zones[src] ~= nil
    set_zone(src, {
        x = pos.x, y = pos.y, z = pos.z,
        radius = Config.TrafficHold.radius + 0.0,
        speed = Config.TrafficHold.mph * 0.44704,
        expires = os.time() + Config.TrafficHold.minutes * 60,
    })
    if moved then reply(src, 'traffic_moved', 'Copy, traffic hold moved to your location.')
    else reply(src, 'traffic_held', 'Copy, holding traffic at your location.') end
end)

RegisterNetEvent('lwk_control:releaseTraffic', function()
    local src = source
    if not Zones[src] then return reply(src, 'traffic_none', 'You have no traffic hold.') end
    set_zone(src, nil)
    reply(src, 'traffic_released', 'Copy, releasing traffic.')
end)

-- Is anyone holding traffic within m metres of there? (c3r's callouts ask.)
exports('isTrafficHeld', function(at, m)
    for _, z in pairs(Zones) do
        if #(vector3(z.x, z.y, z.z) - vector3(at.x, at.y, at.z)) <= (m or 0.0) + z.radius and z.expires > os.time() then return true end
    end
    return false
end)

-- ─── units ────────────────────────────────────────────────────────────────────
-- On-duty officers for "nearest unit" / "have Two Boy Four meet me". Each client reports its own
-- c3r duty and callsign; positions come from the server (OneSync).

local Units = {} -- [src] = callsign ('' when the officer has none); absent = off duty

local function units_list()
    local list = {}
    for id, cs in pairs(Units) do list[#list + 1] = { id = id, callsign = cs } end
    return list
end

local function pos_of(id) return GetEntityCoords(GetPlayerPed(id)) end

RegisterNetEvent('lwk_control:unit', function(on_duty, callsign)
    local src = source
    local now = on_duty == true and (type(callsign) == 'string' and callsign:sub(1, 20) or '') or nil
    if Units[src] == now then return end
    Units[src] = now
    TriggerClientEvent('lwk_control:units', -1, units_list())
end)

RegisterNetEvent('lwk_control:nearestUnit', function()
    local src = source
    local me = pos_of(src)
    local best, best_d
    for id in pairs(Units) do
        if id ~= src then
            local d = #(pos_of(id) - me)
            if not best_d or d < best_d then best, best_d = id, d end
        end
    end
    if not best then return TriggerClientEvent('lwk_control:nearestResult', src, nil) end
    local p = pos_of(best)
    TriggerClientEvent('lwk_control:nearestResult', src,
        { callsign = Units[best], dist = best_d, dx = p.x - me.x, dy = p.y - me.y })
end)

RegisterNetEvent('lwk_control:meet', function(target)
    local src = source
    target = tonumber(target)
    if not target or target == src or not Units[target] then
        return TriggerClientEvent('lwk_control:meetResult', src, false)
    end
    TriggerClientEvent('lwk_control:meetRequest', target, Units[src] or '', pos_of(src))
    TriggerClientEvent('lwk_control:meetResult', src, true, Units[target])
end)

-- c3r callout accepted / ended -> client, for "where's my call?".
AddEventHandler('c3r:calloutAccepted', function(src, c)
    TriggerClientEvent('lwk_control:callAccepted', src, type(c) == 'table' and c.coords or nil)
end)
AddEventHandler('c3r:calloutEnded', function(src) TriggerClientEvent('lwk_control:callEnded', src) end)

-- Clients ask once on start (covers joins and resource restarts).
RegisterNetEvent('lwk_control:zonesSync', function()
    TriggerClientEvent('lwk_control:zones', source, Zones)
    TriggerClientEvent('lwk_control:units', source, units_list())
end)

CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for src, z in pairs(Zones) do
            if now >= z.expires then
                set_zone(src, nil)
                reply(src, 'traffic_expired', 'Your traffic hold has expired.')
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    LastPed[source], LastVehicle[source], PedVehicle[source] = nil, nil, nil
    LastOwner[source], LastPedAt[source] = nil, nil
    if Zones[source] then set_zone(source, nil) end
    if Units[source] then
        Units[source] = nil
        TriggerClientEvent('lwk_control:units', -1, units_list())
    end
end)

-- ─── callouts ─────────────────────────────────────────────────────────────────
-- c3r adds callouts in Phase 4; until then these exports are missing and dispatch says "unable".

local function pd(fn, ...)
    if not started('c3r') then return nil, 'c3r is not running' end
    local res = exports.c3r
    local ok, a, b = pcall(function(...) return res[fn](res, ...) end, ...)
    if not ok then return nil, 'not available' end
    return a, b
end

RegisterNetEvent('lwk_control:setOffers', function(enabled)
    local src = source
    local ok, reason = pd('setCalloutOffers', src, enabled == true)
    if ok == nil and reason then return reply(src, 'unable', '~r~Unable: ' .. reason) end
    if enabled then reply(src, 'callouts_resume', 'Copy, resuming your call outs.')
    else reply(src, 'callouts_hold', 'Copy, holding your call outs.') end
end)

RegisterNetEvent('lwk_control:requestCallout', function()
    local src = source
    local ok, reason = pd('offerCallout', src)
    if not ok then reply(src, 'no_callout', '~r~No call: ' .. tostring(reason or 'unavailable'):gsub('_', ' ')) end
end)

-- ─── plate check ──────────────────────────────────────────────────────────────

-- plate = spoken plate, or nil for "the vehicle I stopped"
RegisterNetEvent('lwk_control:plateCheck', function(plate)
    local src = source
    local spoken = type(plate) == 'string' and plate_key(plate) or nil
    local stopped = LastVehicle[src]

    if not spoken and not stopped then
        return TriggerClientEvent('lwk_control:plateResult', src, { found = false, reason = 'no_vehicle' })
    end

    local function owner_of(veh) -- (the name a plate came back to: "run the name" runs them next)
        if type(veh) == 'table' and veh.owner_id then LastOwner[src] = { id = veh.owner_id, at = GetGameTimer() } end
    end
    if stopped and (not spoken or plate_key(stopped.plate) == spoken) then
        owner_of(stopped)
        return TriggerClientEvent('lwk_control:plateResult', src, { found = true, vehicle = stopped })
    end

    local function result(veh)
        owner_of(veh)
        if veh then return TriggerClientEvent('lwk_control:plateResult', src, { found = true, vehicle = veh }) end
        TriggerClientEvent('lwk_control:plateResult', src, { found = false, reason = 'not_found', plate = spoken })
    end
    -- lookupPlate: a car that isn't on file yet gets its papers made up, if it's near the officer
    local _, err = pd('lookupPlate', src, spoken, result)
    if err then _, err = pd('findVehicle', spoken, result) end -- an older c3r: what's on file only
    if err then result(nil) end -- c3r isn't running, so result never comes
end)

-- ─── name check ───────────────────────────────────────────────────────────────

RegisterNetEvent('lwk_control:nameCheck', function()
    local src = source
    local ped = LastPed[src]
    local owner = LastOwner[src]
    -- a plate run since the last person identified: the name it came back to (the registered owner)
    if owner and (not ped or owner.at > (LastPedAt[src] or 0)) then
        local _, err = pd('getPerson', owner.id, function(p)
            if type(p) == 'table' then return TriggerClientEvent('lwk_control:nameResult', src, { found = true, person = p }) end
            TriggerClientEvent('lwk_control:nameResult', src, { found = false, reason = 'no_record' })
        end)
        if not err then return end
    end
    if not ped then
        return TriggerClientEvent('lwk_control:nameResult', src, { found = false, reason = 'no_interaction' })
    end
    if ped.unverified then -- a name they made up: nobody by that name and DOB on file
        return TriggerClientEvent('lwk_control:nameResult', src, { found = false, reason = 'no_record' })
    end
    TriggerClientEvent('lwk_control:nameResult', src, { found = true, person = ped })
end)

-- lwk_npcai: the officer's last subject -> person, vehicle (nil when they were on foot) | nil
exports('GetSubject', function(src)
    src = tonumber(src)
    return LastPed[src], PedVehicle[src]
end)
