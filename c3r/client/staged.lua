--[[
    c3r — client: staged violators. On duty at the wheel, with no stop on, every Config.Staged.every seconds a
    car ahead gets a hidden story (the server's call) and drives to match it for a while: a drunk weaves, a stolen
    car speeds, a suspended licence runs the lights. No marker: the officer has to spot it. Pulled over, it's an
    ordinary stop with that driver.
]]

local active = nil -- { veh, ped, net, how, ends, released, handed } while one is out there

-- Road cars only: compacts, sedans, SUVs, coupes, muscle, sports classics, sports, super, off-road, vans.
local CLASSES = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [9] = true, [12] = true }

local function control(ent)
    local deadline = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(ent)
        Wait(0)
    end
    return NetworkHasControlOfEntity(ent)
end

-- A car ahead, 35-120 m out, moving, in plain sight, an ordinary AI driver and nobody's ride.
local function candidate(own)
    local me, fwd = GetEntityCoords(own), GetEntityForwardVector(own)
    local best, best_d
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if veh ~= own and CLASSES[GetVehicleClass(veh)] and GetEntitySpeed(veh) > 5.0 and not IsEntityAMissionEntity(veh) then
            local p = GetEntityCoords(veh)
            local to = p - me
            local d = #to
            if d > 35.0 and d < 120.0 and (to.x * fwd.x + to.y * fwd.y) / d > math.cos(math.rad(25.0)) then
                local driver, ok = GetPedInVehicleSeat(veh, -1), true
                if driver == 0 or IsPedAPlayer(driver) or IsEntityAMissionEntity(driver) or IsEntityDead(driver) then ok = false end
                for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                    local p2 = GetPedInVehicleSeat(veh, seat)
                    if p2 ~= 0 and IsPedAPlayer(p2) then ok = false end
                end
                if ok and (not best_d or d < best_d) and HasEntityClearLosToEntity(own, veh, 17) then best, best_d = veh, d end
            end
        end
    end
    return best
end

-- Networked (ambient traffic often isn't), then the server is asked to give it a story.
local function pick(veh)
    local people = {}
    for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 then people[#people + 1] = { seat = seat, ped = ped } end
    end
    local ents = { veh }
    for _, p in ipairs(people) do ents[#ents + 1] = p.ped end
    for _, e in ipairs(ents) do if not NetworkGetEntityIsNetworked(e) then NetworkRegisterEntityAsNetworked(e) end end
    local deadline = GetGameTimer() + 1500
    while GetGameTimer() < deadline do
        local all = true
        for _, e in ipairs(ents) do all = all and NetworkGetEntityIsNetworked(e) end
        if all then break end
        Wait(100)
    end
    if not people[1] or people[1].seat ~= -1 or not NetworkGetEntityIsNetworked(veh) then return end
    local list = {}
    for i, p in ipairs(people) do
        if NetworkGetEntityIsNetworked(p.ped) then list[i] = { seat = p.seat, net = PedToNet(p.ped), male = IsMale(p.ped) } end
    end
    TriggerServerEvent('c3r:staged:pick', VehToNet(veh), list, VehicleInfo(veh))
end

-- Back to being ordinary traffic the game can clean up (unless the officer's stop has it now).
local function release(a)
    if a.handed then return end
    if a.released then -- another officer pulled it over: their stop has it now. Only let go of it, so their game can
        -- take it; never "no longer needed" here, or this game tidies the car (and them) away mid-stop
        if DoesEntityExist(a.ped) then SetNetworkIdCanMigrate(PedToNet(a.ped), true) end
        if DoesEntityExist(a.veh) then SetNetworkIdCanMigrate(a.net, true) end
        return
    end
    if DoesEntityExist(a.ped) then
        SetBlockingOfNonTemporaryEvents(a.ped, false)
        SetPedKeepTask(a.ped, false)
        if not IsEntityDead(a.ped) and DoesEntityExist(a.veh) and IsPedInVehicle(a.ped, a.veh, false)
            and NetworkHasControlOfEntity(a.ped) then
            TaskVehicleDriveWander(a.ped, a.veh, 15.0, 786603)
        end
        SetNetworkIdCanMigrate(PedToNet(a.ped), true)
        SetEntityAsNoLongerNeeded(a.ped)
    end
    if DoesEntityExist(a.veh) then
        SetNetworkIdCanMigrate(a.net, true)
        SetEntityAsNoLongerNeeded(a.veh)
    end
end

-- Something wrong with the car, plain to see from behind it. Damage names UNVERIFIED by eye: SET_VEHICLE_DAMAGE's offsets are
-- from the car's middle, and a small hit at a corner breaks the light there.
local FAULTS = {
    tail = function(veh)
        local low, high = GetModelDimensions(GetEntityModel(veh))
        SetVehicleDamage(veh, high.x * 0.8, low.y, 0.3, 150.0, 0.4, true)
    end,
    head = function(veh) SetVehicleLights(veh, 1) end,
    blinker = function(veh) SetVehicleIndicatorLights(veh, 1, true) end,
    tyre = function(veh) SetVehicleTyreBurst(veh, 0, false, 1000.0) end,
}

local STYLES = { -- speed (m/s), driving style
    weave = { 16.0, 786603 },   -- ordinary driving, with the swerves on top
    speed = { 38.0, 786468 },   -- flat out, round the traffic, through the lights
    lights = { 20.0, 786468 },  -- not fast, but no stopping at the lights
    fault = { 13.0, 786603 },   -- ordinary, unhurried: they don't know
}

local function drive(a)
    if not (control(a.veh) and control(a.ped)) then active = nil return end
    SetEntityAsMissionEntity(a.veh, true, true)
    SetEntityAsMissionEntity(a.ped, true, true)
    SetNetworkIdCanMigrate(a.net, false)
    SetNetworkIdCanMigrate(PedToNet(a.ped), false)
    SetBlockingOfNonTemporaryEvents(a.ped, true)
    local st = STYLES[a.how] or STYLES.speed
    if FAULTS[a.fault] then FAULTS[a.fault](a.veh) end
    TaskVehicleDriveWander(a.ped, a.veh, st[1], st[2])
    local next_swerve = GetGameTimer() + 2000
    while true do
        Wait(250)
        if Stop and Stop.veh == a.veh then a.handed = true break end -- pulled over: the stop has it now
        local me = PlayerPedId()
        if a.released or GetGameTimer() > a.ends or not LocalPlayer.state.c3rDuty or IsEntityDead(me)
            or not DoesEntityExist(a.veh) or not DoesEntityExist(a.ped) or IsEntityDead(a.ped)
            or not IsPedInVehicle(a.ped, a.veh, false) or #(GetEntityCoords(a.veh) - GetEntityCoords(me)) > 250.0 then
            break
        end
        if a.how == 'weave' and not a.released and GetGameTimer() > next_swerve and NetworkHasControlOfEntity(a.ped) then
            -- a temp action replaces the driving task: a short drift to one side, then driving again
            TaskVehicleTempAction(a.ped, a.veh, math.random() < .5 and 7 or 8, 450)
            Wait(500)
            TaskVehicleDriveWander(a.ped, a.veh, st[1], st[2])
            next_swerve = GetGameTimer() + math.random(1800, 3800)
        end
    end
    release(a)
    if active == a then active = nil end
end

RegisterNetEvent('c3r:staged:drive', function(veh_net, how, fault)
    if active then return end
    local veh = NetToVeh(veh_net)
    if not DoesEntityExist(veh) then return end
    local ped = GetPedInVehicleSeat(veh, -1)
    if ped == 0 or IsPedAPlayer(ped) then return end
    active = { veh = veh, ped = ped, net = veh_net, how = how, fault = fault, ends = GetGameTimer() + Config.Staged.lasts * 1000 }
    CreateThread(function() drive(active) end)
end)

-- Another officer pulled it over: their game drives it now.
RegisterNetEvent('c3r:staged:release', function(veh_net)
    if active and active.net == veh_net then active.released = true end
end)

-- When to look for one: on duty, at the wheel of a car, no stop, not picking a car, none out there already.
CreateThread(function()
    local function gap() return math.random(Config.Staged.every[1], Config.Staged.every[2]) * 1000 end
    local next_at = GetGameTimer() + gap()
    while true do
        Wait(1000)
        local me = PlayerPedId()
        local own = GetVehiclePedIsIn(me, false)
        if not Config.Staged.enabled or not LocalPlayer.state.c3rDuty or own == 0 or GetPedInVehicleSeat(own, -1) ~= me
            or Stop or Targeting() or active then
            if next_at < GetGameTimer() + 15000 then next_at = GetGameTimer() + 15000 end -- a little breathing room after
        elseif GetGameTimer() >= next_at then
            local veh = candidate(own)
            if veh then
                pick(veh)
                next_at = GetGameTimer() + gap()
            else
                next_at = GetGameTimer() + 10000 -- nothing suitable in sight: look again soon
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and active then release(active) end
end)
