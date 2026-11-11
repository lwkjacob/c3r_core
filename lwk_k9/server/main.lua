--[[
    lwk_k9 — server: who has a police dog (c3r's on-duty police), what the nose finds (c3r's getStopFinds stays on this side: the
    officer's game only hears where the dog sat), the K9 apprehension note, and players' scent trails for Track.
    BY LWK DEVELOPMENT
]]

local function log(...) if Config.Debug then print('[lwk_k9]', ...) end end

-- c3r says who's police: on duty as police there (its own duty access decides who can go on)
local function police(src) return exports.c3r:isOnDuty(src) == true and Player(src).state.c3rService == 'police' end
local function access(src) return { police = police(src) } end

RegisterNetEvent('lwk_k9:access', function()
    local src = source
    TriggerClientEvent('lwk_k9:access', src, access(src))
end)
AddEventHandler('c3r:duty', function(src) TriggerClientEvent('lwk_k9:access', src, access(src)) end)

-- ─── Sniff ───────────────────────────────────────────────────────────────────
local function smells(name)
    name = name:lower()
    for _, w in ipairs(Config.Smells) do if name:find(w, 1, true) then return true end end
    return false
end

-- net: the person sniffed, nil: the stop's car (and whoever's by it). -> where it sat, and on whom
RegisterNetEvent('lwk_k9:sniff', function(net)
    local src = source
    if not police(src) then return TriggerClientEvent('lwk_k9:sniffed', src, false) end
    net = tonumber(net)
    local hit
    for _, f in ipairs(exports.c3r:getStopFinds(src, net) or {}) do
        if smells(f.name) and Config.Where[f.where] then hit = f break end
    end
    if not hit then
        exports.c3r:note(src, 'K9 sniff: no alert')
        return TriggerClientEvent('lwk_k9:sniffed', src, false)
    end
    exports.c3r:k9Alert(src, Config.Where[hit.where])
    log(('%d: alert, %s (%s)'):format(src, hit.where, hit.name))
    TriggerClientEvent('lwk_k9:sniffed', src, hit.where, hit.net)
end)

-- ─── Attack ──────────────────────────────────────────────────────────────────
local bit_at = {}
RegisterNetEvent('lwk_k9:bit', function(net)
    local src = source
    if not police(src) or (bit_at[src] or 0) > os.time() - 10 then return end
    local ped = NetworkGetEntityFromNetworkId(tonumber(net) or 0)
    if not ped or ped == 0 or not DoesEntityExist(ped) or IsPedAPlayer(ped) then return end
    if #(GetEntityCoords(ped) - GetEntityCoords(GetPlayerPed(src))) > Config.Bite.range + 20.0 then return end
    bit_at[src] = os.time()
    exports.c3r:note(src, 'K9 apprehension: the suspect was bitten and held')
end)

-- ─── Track: everyone's last few minutes on foot ──────────────────────────────
local Trails = {} -- [player] = { { t, x, y, z } } oldest first

CreateThread(function()
    while true do
        Wait(3000)
        local now, keep = os.time(), Config.Track.minutes * 60
        for _, id in ipairs(GetPlayers()) do
            id = tonumber(id)
            local ped = GetPlayerPed(id)
            local tr = Trails[id] or {}
            Trails[id] = tr
            while tr[1] and now - tr[1].t > keep do table.remove(tr, 1) end
            if ped ~= 0 and GetVehiclePedIsIn(ped, false) == 0 then -- (a car leaves no scent)
                local p, last = GetEntityCoords(ped), tr[#tr]
                if not last or #(p - vector3(last.x, last.y, last.z)) > 2.0 then
                    tr[#tr + 1] = { t = now, x = p.x, y = p.y, z = p.z }
                end
            end
        end
    end
end)
AddEventHandler('playerDropped', function() Trails[source], bit_at[source] = nil, nil end)

-- Where that player's trail comes closest to the officer, if within pick-up range: -> index, seconds old
local function picked_up(src, id)
    local tr = Trails[id]
    if not tr or id == src or exports.c3r:isOnDuty(id) then return nil end
    local me = GetEntityCoords(GetPlayerPed(src))
    for i = #tr, 1, -1 do -- (the freshest bit of trail near the officer)
        if #(me - vector3(tr[i].x, tr[i].y, tr[i].z)) < Config.Track.pick_up then return i, os.time() - tr[i].t end
    end
end

RegisterNetEvent('lwk_k9:scents', function()
    local src = source
    if not police(src) then return end
    local list = {}
    for id in pairs(Trails) do
        local i, age = picked_up(src, id)
        if i then list[#list + 1] = { id = id, age = age } end
    end
    table.sort(list, function(a, b) return a.age < b.age end)
    TriggerClientEvent('lwk_k9:scents', src, list)
end)

-- The trail from where the officer picked it up to the freshest point
RegisterNetEvent('lwk_k9:trail', function(id)
    local src = source
    id = tonumber(id)
    if not police(src) or not id then return end
    local i = picked_up(src, id)
    local tr, out = Trails[id], {}
    if i then for j = i, #tr do out[#out + 1] = { tr[j].x, tr[j].y, tr[j].z } end end
    TriggerClientEvent('lwk_k9:trail', src, id, out)
end)
