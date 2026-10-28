--[[
    c3r — client: the vehicle's radial menu. Hold the radial key (G) on foot at any car: search it, call a
    tow, run its plate, order everyone out or back in, call backup. Sat in a car (the officer's own), or with no car
    at hand, it's the dispatch wheel: any unit, or in a chase, pursuit backup and air (and the rest under Services ▸).
    Every wheel has Backup ▸. A car that isn't stopped becomes a quiet stop first
    (stop.lua's RequestVehicle). On a traffic stop it's only for the car pulled over. Point at an option and
    click it, or let go of the key. The stopped car's felony stop is run from cover: from Config.PaRange, and from
    the officer's own (stopped) patrol car.
]]

local open = false
local target = nil -- { veh, stop = true when it's the stop's own car, far = from cover: felony orders only,
                   --   backup = the dispatch wheel (veh: the officer's car, or nil on foot) } while up
local REACH = 4.5 -- m from the car

-- The car the officer is standing at: the stop's own, else (unless on a traffic stop) the nearest one that's
-- standing still and isn't a player's.
local function target_car()
    local me = PlayerPedId()
    local own = GetVehiclePedIsIn(me, false)
    local s, pos = Stop, GetEntityCoords(me)
    if s and s.veh ~= 0 and DoesEntityExist(s.veh) and s.stopped and not s.empty then
        local d = #(GetEntityCoords(s.veh) - pos)
        if own == 0 and d < REACH then return { veh = s.veh, stop = true } end
        -- from cover (on foot, or sat in the patrol car once it's stopped): the felony stop only
        if d < Config.PaRange and not s.foot and not Casual(s) and (own == 0 or GetEntitySpeed(own) < 1.0) then
            return { veh = s.veh, stop = true, far = true }
        end
    end
    if own ~= 0 then return { veh = own, backup = true } end
    if s and not Casual(s) then return { backup = true } end
    local mine, best, best_d = GetVehiclePedIsIn(me, true), nil, REACH
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local driver = GetPedInVehicleSeat(veh, -1)
        local d = #(GetEntityCoords(veh) - pos)
        if d < best_d and veh ~= mine and GetEntitySpeed(veh) < 1.0 and not (driver ~= 0 and IsPedAPlayer(driver))
            and not IsBackup(veh) then
            best, best_d = veh, d
        end
    end
    return best and { veh = best } or { backup = true }
end

-- A felony stop's wheel: start one (nobody out yet), or each person's next order, and hands up for all.
local function felony_items(s)
    if not s.felony then
        local anyone_out = false
        for _, o in pairs(s.occ) do anyone_out = anyone_out or (o.out and not o.cuffed) end
        return { { action = 'felony', label = 'Felony stop', icon = 'siren', off = anyone_out and 'Someone is out' or nil } }
    end
    local list = {}
    for _, st in ipairs(FelonySteps(s)) do
        list[#list + 1] = { action = st.action, arg = st.o.net, label = st.label,
                            icon = st.action == 'fel_out' and 'out' or st.action == 'fel_back' and 'walk' or 'handsup' }
    end
    list[#list + 1] = { action = 'pa_hands_up', label = 'Everyone: hands up', icon = 'handsup' }
    return list
end

-- Units dispatch can send (client/backup.lua), as wheel options.
local SERVICES = {
    { 'police', 'Prisoner transport', 'cuffs' }, { 'ambulance', 'Ambulance', 'medic' }, { 'cover', 'Cover unit', 'siren' },
    { 'tow', 'Tow truck', 'tow' }, { 'fire', 'Fire department', 'flame' }, { 'coroner', 'Coroner', 'file' },
    { 'mechanic', 'Mechanic', 'wrench' }, { 'roadservice', 'Road service', 'wrench' },
    { 'animalrescue', 'Animal control', 'paw' }, { 'taxi', 'Taxi', 'car' },
}
local CHASE = {
    { 'light', 'Backup: code 1', 'siren' }, { 'medium', 'Backup: code 2', 'siren' }, { 'heavy', 'Backup: code 3', 'siren' },
    { 'air', 'Air support', 'heli' }, { 'cancel_pursuit', 'Cancel backup', 'radio' },
}
-- A unit already on its way is called off from the same place ("Cancel ..."); a tow truck can't be.
local function backup_items(list, skip)
    local out = {}
    for _, b in ipairs(list) do
        if b[1] ~= skip then
            local on = BackupActive(b[1])
            out[#out + 1] = b[1] == 'tow' and { action = 'backup', arg = 'tow', label = b[2], icon = b[3], off = on and 'On its way' or nil }
                or on and { action = 'backup', arg = 'cancel:' .. b[1], label = 'Cancel ' .. b[2]:lower(), icon = b[3] }
                or { action = 'backup', arg = b[1], label = b[2], icon = b[3] }
        end
    end
    return out
end

local BACKUP = { label = 'Backup', icon = 'radio', to = 'backup' }

-- The sub-levels: Backup ▸ (every unit but the tow, which the car wheel has itself; Pursuit ▸ first in a chase),
-- and the dispatch wheel's Services ▸ in a chase.
local function levels()
    local backup = backup_items(SERVICES, 'tow')
    if ChaseOn() then table.insert(backup, 1, { label = 'Pursuit', icon = 'siren', to = 'pursuit' }) end
    return { backup = { title = 'Backup', items = backup }, pursuit = { title = 'Pursuit', items = backup_items(CHASE) },
             services = { title = 'Services', items = backup_items(SERVICES) } }
end

-- The first half go on the left of the wheel, the rest on the right.
local function items(t)
    local s = Stop
    if t.backup then
        if not ChaseOn() then return backup_items(SERVICES) end
        local list = backup_items(CHASE)
        list[#list + 1] = { label = 'Services', icon = 'radio', to = 'services' }
        return list
    end
    if t.far then
        local list = felony_items(s)
        list[#list + 1] = BACKUP
        return list
    end
    local inside, outside = {}, {}
    if t.stop then
        inside, outside = VehicleFree(s)
    else
        for seat = -1, GetVehicleMaxNumberOfPassengers(t.veh) - 1 do
            local p = GetPedInVehicleSeat(t.veh, seat)
            if p ~= 0 and not IsPedAPlayer(p) then inside[#inside + 1] = p end
        end
    end
    local towed = t.stop and s.towed
    local felony = t.stop and not s.foot and not s.empty and felony_items(s) or {}
    if t.stop and s.felony then -- a felony stop, at the car: its orders, and the car's own things (no "everyone out / in")
        for _, it in ipairs({
            { action = 'search_car', label = 'Search vehicle', icon = 'search' },
            { action = 'tow', label = 'Request tow', icon = 'tow', off = towed and 'On its way' or nil },
            { action = 'run_plate', label = 'Run plate', icon = 'plate' },
            BACKUP,
        }) do felony[#felony + 1] = it end
        return felony
    end
    local list = {
        { action = 'search_car', label = 'Search vehicle', icon = 'search' },
        { action = 'tow', label = 'Request tow', icon = 'tow', off = towed and 'On its way' or nil },
        { action = 'run_plate', label = 'Run plate', icon = 'plate' },
        { action = 'all_out', label = 'Everyone out', icon = 'out', off = #inside == 0 and 'Nobody inside' or nil },
        { action = 'all_in', label = 'Everyone back in', icon = 'in',
          off = towed and 'Being towed' or #outside == 0 and 'Nobody out' or nil },
        BACKUP,
    }
    if felony[1] then table.insert(list, 1, felony[1]) end
    return list
end

-- Sat in a car the wheel stays up until clicked (G or Esc closes it) and the car still drives under it: only what
-- the mouse, Esc and the wheel's own keys do in game is held (look, aim, shoot, the pause menu, Q's radio wheel).
local HELD = { 1, 2, 24, 25, 68, 69, 70, 85, 91, 92, 106, 114, 199, 200, 257, 263, 330, 331 }
local closed_at = 0

local function close()
    if not open then return end
    open, target = false, nil
    closed_at = GetGameTimer()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'radial', open = false })
    NoPause()
end

RegisterCommand('+c3r_radial', function()
    if open then -- (sat in a car the game still sees G: it closes the wheel)
        if IsPedInAnyVehicle(PlayerPedId(), false) then close() end
        return
    end
    if IsNuiFocused() or not LocalPlayer.state.c3rDuty then return end
    if LocalPlayer.state.stopstick then return end -- (carrying a Stop Stick or on its cord: G throws / yanks it, lwk_stopstick)
    if GetGameTimer() - closed_at < 300 then return end -- (G closed it in a car: the game saw that press too)
    local t = target_car()
    local driving = IsPedInAnyVehicle(PlayerPedId(), false)
    open, target = true, t
    SetNuiFocus(true, true)
    if driving then
        SetNuiFocusKeepInput(true)
        CreateThread(function()
            while open do
                for _, c in ipairs(HELD) do DisableControlAction(0, c, true) end
                Wait(0)
            end
        end)
    end
    local plate = (t.veh and GetVehicleNumberPlateText(t.veh) or ''):match('^%s*(.-)%s*$') -- which car this is, in the middle of the wheel
    SendNUIMessage({ type = 'radial', open = true, kind = 'vehicle', hold = not driving, items = items(t), key = KeyName('+c3r_radial', 'G'),
                     title = t.backup and 'Dispatch' or plate ~= '' and plate or nil, levels = levels() })
end, false)
RegisterCommand('-c3r_radial', function() end, false) -- letting go is seen by the page (it has the keyboard)
RegisterKeyMapping('+c3r_radial', 'Vehicle radial menu, hold (c3r)', 'keyboard', Config.RadialKey)

RegisterNUICallback('radial', function(d, cb)
    cb({})
    local t = target
    close()
    if not t or type(d.action) ~= 'string' then return end
    if d.action == 'backup' then return CallBackup(d.arg) end
    if not t.veh or not DoesEntityExist(t.veh) then return end
    if d.action == 'run_plate' then return TriggerServerEvent('c3r:runPlate', GetVehicleNumberPlateText(t.veh)) end
    if d.action == 'felony' then return PaCommand('felony') end
    if d.action == 'pa_hands_up' then return PaCommand('hands_up') end
    if d.action:sub(1, 4) == 'fel_' then -- one person's felony order, shouted
        return TriggerServerEvent('c3r:stop:act', d.action, nil, tonumber(d.arg), true)
    end
    if t.stop then return VehicleAction(Stop, d.action) end
    -- another car: any chat on now is done with, and this car becomes the stop
    CreateThread(function()
        if Stop then
            TriggerServerEvent('c3r:stop:act', 'cancel')
            local deadline = GetGameTimer() + 2000
            while Stop and GetGameTimer() < deadline do Wait(50) end
            if Stop then return end
        end
        RequestVehicle(t.veh, d.action)
    end)
end)

-- walked off, or the car went: the wheel goes too
CreateThread(function()
    while true do
        local t = target
        if open and (not t or (t.veh and (not DoesEntityExist(t.veh) -- (the on-foot dispatch wheel has no car to walk off from)
            or (not t.far and (GetVehiclePedIsIn(PlayerPedId(), false) ~= 0) ~= (t.backup == true)) -- (got in / out; IsPedInAnyVehicle gives 1, not true)
            or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(t.veh)) > (t.far and Config.PaRange + 5.0 or REACH + 1.0)))) then
            close()
        end
        Wait(open and 250 or 1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then close() end
end)
