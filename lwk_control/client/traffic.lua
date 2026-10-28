--[[ lwk_control — traffic holds: a road-node speed zone + radius blip for every active hold. ]]

local active = {} -- [owner server id] = { node, blip }

local function remove(owner)
    local z = active[owner]
    if not z then return end
    RemoveRoadNodeSpeedZone(z.node)
    RemoveBlip(z.blip)
    active[owner] = nil
end

local function add(owner, z)
    remove(owner)
    local blip = AddBlipForRadius(z.x, z.y, z.z, z.radius)
    SetBlipColour(blip, Config.TrafficHold.blipColour)
    SetBlipAlpha(blip, Config.TrafficHold.blipAlpha)
    active[owner] = { node = AddRoadNodeSpeedZone(z.x, z.y, z.z, z.radius, z.speed, false), blip = blip }
end

RegisterNetEvent('lwk_control:zone', function(owner, z)
    if z then add(owner, z) else remove(owner) end
end)

RegisterNetEvent('lwk_control:zones', function(all)
    for owner, z in pairs(all or {}) do add(owner, z) end
end)

CreateThread(function() TriggerServerEvent('lwk_control:zonesSync') end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for owner in pairs(active) do remove(owner) end
end)
