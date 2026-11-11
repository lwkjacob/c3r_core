--[[
    c3r — client: the Ambulance role. A shift: the uniform, and an ambulance on the road beside you. A patient: the bag
    from the back of the ambulance, the overhead treatment screen (nui/index.html #ems), the stretcher, the drive to
    hospital and the handover at the door. What's wrong with them and what fixes it is server/ems.lua's.

    Natives as documented in citizenfx/natives: SET_PLAYER_MODEL destroys the player's ped and makes a new one, so
    the old handle is gone; the clothes are read first and put back afterwards. The animation dictionaries aren't in
    the official docs: UNVERIFIED (one that's missing just doesn't play). Bone ids: GET_PED_BONE_INDEX's list. The
    ambulance's back doors as 2 and 3 are UNVERIFIED too (a car without them just doesn't open).
]]

local E = Config.Ems
local truck, was = nil, nil -- the shift's ambulance (brought, or whatever they drive); who they were before the uniform
local brought = false         -- truck is one the shift brought (and takes away again)
local bag_out, bag = false, nil -- carrying the bag; its prop (nil if no model loaded: it still counts)
local stretcher, fit = nil, nil -- the stretcher being pushed; how it sits, from its model's size
local lying, aboard = nil, nil -- { ped, net }: on the stretcher; in the back
local hospital = nil -- where they're going: an entry of Config.Hospitals, with its blip
local scr, opening = nil, false -- the treatment screen: { ped, net, cam }
local partner, ride = nil, nil -- the AI partner (a shift's, in the passenger seat); the ride: 'back' | 'drive' | 'there'
local DRIVE = 786469 | 2 | 16 -- (client/backup.lua's lights-on driving)
local Stable = {} -- [net] = true: ready for the stretcher

local PUSH = { 'anim@heists@box_carry@', 'idle' } -- UNVERIFIED
local SUPINE = { 'anim@gangops@morgue@table@', 'body_search' } -- flat on their back, as on a table (in the game's anim list)

local function on_ems() return LocalPlayer.state.c3rService == 'ambulance' end

local function load_model(name)
    local m = GetHashKey(name)
    if not IsModelInCdimage(m) then return nil end
    RequestModel(m)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(m) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(m) and m or nil
end

-- ─── the uniform ──────────────────────────────────────────────────────────────

-- What they're wearing, to put back: 12 components, and hats, glasses, ears, watch, bracelet.
local PROPS = { 0, 1, 2, 6, 7 }
local function read_clothes(p)
    local c = { comp = {}, prop = {} }
    for i = 0, 11 do c.comp[i] = { GetPedDrawableVariation(p, i), GetPedTextureVariation(p, i), GetPedPaletteVariation(p, i) } end
    for _, i in ipairs(PROPS) do c.prop[i] = { GetPedPropIndex(p, i), GetPedPropTextureIndex(p, i) } end
    return c
end
local function wear(p, c)
    for i, v in pairs(c.comp) do SetPedComponentVariation(p, i, v[1], v[2], v[3]) end
    ClearAllPedProps(p)
    for i, v in pairs(c.prop) do if v[1] >= 0 then SetPedPropIndex(p, i, v[1], v[2], true) end end
end

local function set_model(m)
    SetPlayerModel(PlayerId(), m)
    SetModelAsNoLongerNeeded(m)
end

local FREEMODE = { [GetHashKey('mp_m_freemode_01')] = 'outfit_m', [GetHashKey('mp_f_freemode_01')] = 'outfit_f' }

-- ponytail: a swapped model loses anything carried (SET_PLAYER_MODEL makes a new ped). c3r hands out no weapons, so
-- nothing's put back; list and re-give them if a server wants that.
local function dress()
    if not E.uniform then return end
    local p, model = PlayerPedId(), GetEntityModel(PlayerPedId())
    was = { model = model, clothes = read_clothes(p) }
    if FREEMODE[model] then return DressPed(p, E[FREEMODE[model]] or {}) end
    local m = load_model(E.ped)
    if not m then was = nil return end
    set_model(m)
    SetPedDefaultComponentVariation(PlayerPedId())
end

local function undress()
    local w = was
    if not w then return end
    was = nil
    if GetEntityModel(PlayerPedId()) ~= w.model then
        RequestModel(w.model)
        local deadline = GetGameTimer() + 3000
        while not HasModelLoaded(w.model) and GetGameTimer() < deadline do Wait(0) end
        if not HasModelLoaded(w.model) then return end
        set_model(w.model)
    end
    wear(PlayerPedId(), w.clothes)
end

-- ─── the ambulance ────────────────────────────────────────────────────────────

-- The nearest free bit of road within reach, else right in front of them.
local function truck_spot()
    local me = PlayerPedId()
    local at = GetEntityCoords(me)
    for n = 1, 8 do
        local ok, node, h = GetNthClosestVehicleNodeWithHeading(at.x, at.y, at.z, n, 0, 3.0, 0)
        if ok and #(node - at) < 60.0 and not IsAnyVehicleNearPoint(node.x, node.y, node.z, 4.0) then return node, h end
    end
    return GetOffsetFromEntityInWorldCoords(me, 0.0, 5.0, 0.0), GetEntityHeading(me)
end

local function bring_truck()
    local m = load_model(E.vehicle) or load_model('ambulance') -- (an add-on vehicle this server doesn't have: the game's own)
    if not m then return Notify('~b~C~w~3~r~R~s~ No ambulance available.') end
    local at, h = truck_spot()
    truck = CreateVehicle(m, at.x, at.y, at.z + 0.5, h, true, false)
    SetModelAsNoLongerNeeded(m)
    if truck == 0 then truck = nil return Notify('~b~C~w~3~r~R~s~ No ambulance available.') end
    brought = true
    SetEntityAsMissionEntity(truck, true, true)
    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(truck), false)
    SetVehicleOnGroundProperly(truck)
end

local function have_truck() return truck ~= nil and DoesEntityExist(truck) end

-- The partner: in the passenger seat all shift and never out on scene. On the ride they drive while the medic treats in
-- the back, or sit with the patient while the medic drives. Config flag 184: PreventAutoShuffleToDriversSeat.
local function bring_partner()
    local m = have_truck() and load_model(E.ped)
    if not m then return end
    partner = CreatePedInsideVehicle(truck, 4, m, 0, true, false)
    SetModelAsNoLongerNeeded(m)
    if partner == 0 then partner = nil return end
    SetEntityAsMissionEntity(partner, true, true)
    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(partner), false)
    SetBlockingOfNonTemporaryEvents(partner, true)
    SetPedCanBeDraggedOut(partner, false)
    SetPedConfigFlag(partner, 184, true)
    SetPedKeepTask(partner, true)
end

local function partner_ok() return partner ~= nil and DoesEntityExist(partner) and not IsEntityDead(partner) and have_truck() end

-- Whatever the medic gets in and drives is their ambulance (not with a patient on the go): the partner moves into it.
CreateThread(function()
    while true do
        Wait(1000)
        local me = PlayerPedId()
        local v = LocalPlayer.state.c3rService == 'ambulance' and not aboard and not lying and GetVehiclePedIsIn(me, false) or 0
        if v ~= 0 and v ~= truck and GetPedInVehicleSeat(v, -1) == me then
            truck = v
            if partner and DoesEntityExist(partner) and not IsEntityDead(partner) then
                if IsVehicleSeatFree(v, 0) then SetPedIntoVehicle(partner, v, 0) end
            elseif IsVehicleSeatFree(v, 0) then
                bring_partner()
            end
        end
    end
end)

-- Beside their vehicle, any side (pushing the stretcher, its length further off). Any model: no doors or bones needed.
local function near_truck()
    if not have_truck() then return false end
    local min, max = GetModelDimensions(GetEntityModel(truck))
    local at = GetEntityCoords(PlayerPedId())
    local p = GetOffsetFromEntityGivenWorldCoords(truck, at.x, at.y, at.z)
    local dx = math.max(min.x - p.x, p.x - max.x, 0.0) -- (how far outside its outline, across and along)
    local dy = math.max(min.y - p.y, p.y - max.y, 0.0)
    return math.sqrt(dx * dx + dy * dy) < 1.5 + (stretcher and fit and fit.len or 0.0)
end

local function back_doors(open)
    if not have_truck() then return end
    if open then
        SetVehicleDoorOpen(truck, 2, false, false)
        SetVehicleDoorOpen(truck, 3, false, false)
    else
        SetVehicleDoorsShut(truck, false)
    end
end

local function back_seat()
    for seat = 1, GetVehicleMaxNumberOfPassengers(truck) - 1 do -- (the back: 1 on)
        if IsVehicleSeatFree(truck, seat) then return seat end
    end
end

-- ─── props ────────────────────────────────────────────────────────────────────

local function make_prop(list)
    local at = GetEntityCoords(PlayerPedId())
    for _, name in ipairs(list) do
        local m = load_model(name)
        if m then
            local o = CreateObject(m, at.x, at.y, at.z - 2.0, true, false, false)
            SetModelAsNoLongerNeeded(m)
            if o ~= 0 then return o end
        end
    end
end

local function drop_prop(o)
    if o and DoesEntityExist(o) then
        DetachEntity(o, false, false)
        DeleteEntity(o)
    end
end

local function hold_bag()
    bag_out = true
    bag = bag or make_prop(E.bag)
    if not bag then return end
    local me = PlayerPedId()
    SetEntityCollision(bag, false, false)
    AttachEntityToEntity(bag, me, GetPedBoneIndex(me, 57005), 0.3, 0.0, 0.0, 0.0, -90.0, 0.0, false, false, false, false, 2, true)
end

local function put_bag_away()
    bag_out = false
    drop_prop(bag)
    bag = nil
end

local function clear_hospital()
    if hospital and hospital.blip and DoesBlipExist(hospital.blip) then RemoveBlip(hospital.blip) end
    hospital = nil
end

local function door(h) return vector3(h.x, h.y, h.z) end

local function route_to_hospital()
    local at, best, best_d = GetEntityCoords(PlayerPedId()), nil, math.huge
    for _, h in ipairs(Config.Hospitals) do
        local d = #(door(h) - at)
        if d < best_d then best, best_d = h, d end
    end
    if not best then return end
    hospital = { name = best.name, x = best.x, y = best.y, z = best.z, blip = AddBlipForCoord(best.x, best.y, best.z) }
    SetBlipColour(hospital.blip, 2)
    SetBlipRoute(hospital.blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(best.name .. ' hospital')
    EndTextCommandSetBlipName(hospital.blip)
end

-- ─── the stretcher ────────────────────────────────────────────────────────────

local function take_stretcher()
    back_doors(true)
    stretcher = make_prop(E.stretcher)
    if not stretcher then
        Prompt('ems', 'alert', 'No stretcher', "None of Config.Ems.stretcher's models are in this server's game build.", 7000)
        return false
    end
    -- sized from the model, so any stretcher stands on the ground, in front of them, the long way
    local min, max = GetModelDimensions(GetEntityModel(stretcher))
    local long_y = max.y - min.y >= max.x - min.x
    fit = { turn = long_y and 0.0 or 90.0, top = max.z, len = long_y and max.y - min.y or max.x - min.x, bottom = min.z }
    SetEntityCollision(stretcher, false, false)
    FreezeEntityPosition(stretcher, true)
    return true
end

local function ground(at)
    local ok, z = GetGroundZFor_3dCoord(at.x, at.y, at.z + 1.5, false)
    return ok and z or at.z - 1.0
end

-- In front of the medic, its near end at their hands, both ends on the ground: it tilts with the slope. Every frame.
local function roll_stretcher()
    local me = PlayerPedId()
    local near = GetOffsetFromEntityInWorldCoords(me, 0.0, 0.55, 0.0)
    local far = GetOffsetFromEntityInWorldCoords(me, 0.0, 0.55 + fit.len, 0.0)
    local zn, zf = ground(near), ground(far)
    local mid = (near + far) / 2
    local tilt = math.deg(math.atan(zf - zn, fit.len))
    SetEntityCoordsNoOffset(stretcher, mid.x, mid.y, (zn + zf) / 2 - fit.bottom, false, false, false)
    -- (the model's long way: along its y, it tilts about x; along its x, about y)
    if fit.turn == 0.0 then
        SetEntityRotation(stretcher, tilt, 0.0, GetEntityHeading(me), 2, true)
    else
        SetEntityRotation(stretcher, 0.0, -tilt, GetEntityHeading(me) + fit.turn, 2, true)
    end
end

local function put_stretcher_away()
    ClearPedTasks(PlayerPedId())
    drop_prop(stretcher)
    stretcher, fit = nil, nil
    back_doors(false)
end

local function attach_lying(ped, ent, x, y, z, yaw)
    AttachEntityToEntity(ped, ent, 0, x, y, z, 0.0, 0.0, yaw, false, false, false, false, 2, true)
end

-- Where their body is, in `ent`'s own terms: head, hips, back, feet.
local function body_on(ped, ent)
    local function at(b)
        local w = GetPedBoneCoords(ped, b, 0.0, 0.0, 0.0)
        return GetOffsetFromEntityGivenWorldCoords(ent, w.x, w.y, w.z)
    end
    return at(31086), at(11816), at(24817), (at(14201) + at(52301)) / 2
end

-- The lying animation carries the body well away from the ped's own origin (about a metre down, and to one side), so
-- a fixed offset leaves them in the wrong place. Put them on, see where the body went, then turn them head to the
-- head end (`ent`'s long way, +) and move them until their back is lie_height above `bed.top`, centred on bed.x, bed.y.
-- bed = { x, y, top, turn (0: ent's long way is its y; 90: its x) }
local function lie_on(ped, ent, bed)
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    local x, y, z, yaw = bed.x, bed.y, bed.top + 1.0, bed.turn + E.lie_turn
    attach_lying(ped, ent, x, y, z, yaw)
    Patients[ped] = Patients[ped] or {}
    Patients[ped].down, Patients[ped].gurney = true, true -- (client/medical.lua stops laying them on their side)
    if LoadDict(SUPINE[1]) then TaskPlayAnim(ped, SUPINE[1], SUPINE[2], 8.0, -8.0, -1, 1, 0.0, false, false, false) end
    Wait(500) -- (the pose is on)
    local head, hips = body_on(ped, ent)
    local want = bed.turn == 0.0 and 90.0 or 0.0 -- (the long way: its y, or its x)
    yaw = yaw + want - math.deg(math.atan(head.y - hips.y, head.x - hips.x))
    attach_lying(ped, ent, x, y, z, yaw)
    Wait(50)
    local back, feet
    head, hips, back, feet = body_on(ped, ent)
    local mid = (head + feet) / 2
    local tx, ty = bed.x, bed.y
    if bed.turn == 0.0 then ty = ty + (E.lie_shift or 0.0) else tx = tx + (E.lie_shift or 0.0) end
    attach_lying(ped, ent, x + tx - mid.x, y + ty - mid.y, z + bed.top + E.lie_height - back.z, yaw)
end

local function lie_on_stretcher(ped) lie_on(ped, stretcher, { x = 0.0, y = 0.0, top = fit.top, turn = fit.turn }) end

-- The cot in the back of the ambulance: between its two back seats, at their height, head to the cab. UNVERIFIED: the
-- bone names (GTA's usual ones for back seats); without them, the middle of the back half of the truck.
local function lie_in_back(ped)
    local function seat(name)
        local i = GetEntityBoneIndexByName(truck, name)
        if i == -1 then return nil end
        local w = GetWorldPositionOfEntityBone(truck, i)
        return GetOffsetFromEntityGivenWorldCoords(truck, w.x, w.y, w.z)
    end
    local l, r = seat('seat_dside_r'), seat('seat_pside_r')
    local min = GetModelDimensions(GetEntityModel(truck))
    local bed = l and r and { x = (l.x + r.x) / 2, y = (l.y + r.y) / 2, top = (l.z + r.z) / 2 } or { x = 0.0, y = min.y * 0.45, top = 0.0 }
    local nudge = E.cot or {}
    bed.y, bed.top, bed.turn = bed.y + (nudge.y_nudge or 0.0), bed.top + (nudge.z_nudge or 0.0), 0.0
    lie_on(ped, truck, bed)
end

local function lift(t)
    if not ControlPed(t.ped) then return end
    SetEntityAsMissionEntity(t.ped, true, true)
    SetNetworkIdCanMigrate(t.net, false) -- (they stay this game's, through the ride)
    lie_on_stretcher(t.ped)
    lying = t
end

local function load_patient()
    local t = lying
    if not ControlPed(t.ped) then return end
    TriggerServerEvent('c3r:ems:load', t.net) -- (the call hears it, before they're moved)
    DetachEntity(t.ped, true, false)
    lie_in_back(t.ped) -- (flat on the cot, not sat in a seat: both back seats stay free for the crew)
    lying, aboard = nil, t
    put_stretcher_away()
    route_to_hospital()
    Prompt('ems', 'ok', 'Patient loaded', hospital and ('Take them to %s. It is on your map.'):format(hospital.name) or 'Take them to hospital.', 7000)
end

-- Ride in the back with them: the partner takes the wheel to the hospital, lights on.
local function ride_back()
    local seat = back_seat()
    if not seat or not aboard then return end
    back_doors(false)
    TaskWarpPedIntoVehicle(PlayerPedId(), truck, seat)
    ride = 'back'
    if not partner_ok() then return end
    ClearPedTasks(partner)
    SetPedIntoVehicle(partner, truck, -1)
    SetVehicleSiren(truck, true)
    if hospital then TaskVehicleDriveToCoordLongrange(partner, truck, hospital.x, hospital.y, hospital.z, 25.0, DRIVE, 15.0) end
    Prompt('ems', 'info', 'Your partner drives', ('Press %s to treat them on the way.'):format(KeyName('+c3r_interact', 'E')), 7000)
end

-- Back to how a shift starts: the partner up front, no lights, the patient no longer held.
local function end_ride(net)
    if ride == 'drive' and net then TriggerServerEvent('c3r:ems:hold', net, false) end
    ride = nil
    if have_truck() then SetVehicleSiren(truck, false) end
    if partner_ok() and GetPedInVehicleSeat(truck, 0) ~= partner then
        ClearPedTasks(partner)
        SetPedIntoVehicle(partner, truck, 0)
    end
end

-- The medic at the wheel with a patient aboard: the partner sits with them, and they hold. A ride in the back at the
-- hospital: the partner pulls up and says so.
CreateThread(function()
    while true do
        Wait(500)
        if aboard and partner_ok() then
            if ride ~= 'drive' and GetPedInVehicleSeat(truck, -1) == PlayerPedId() then
                ride = 'drive'
                local seat = back_seat()
                if seat then SetPedIntoVehicle(partner, truck, seat) end -- (no seat in the back: they watch from the front)
                TriggerServerEvent('c3r:ems:hold', aboard.net, true)
                Prompt('ems', 'info', 'Your partner', "I've got them. Drive.", 6000)
            elseif ride == 'back' and hospital and #(GetEntityCoords(truck) - door(hospital)) < E.hospital_radius
                and GetEntitySpeed(truck) < 1.0 then
                ride = 'there'
                SetVehicleSiren(truck, false)
                Prompt('ems', 'ok', 'Your partner', ("We're here. Get out and unload them at the back."), 7000)
            end
        end
    end
end)

local function unload_patient()
    local t = aboard
    end_ride(t.net)
    if not ControlPed(t.ped) or not take_stretcher() then return end
    DetachEntity(t.ped, false, false) -- (off the cot)
    Wait(100)
    lie_on_stretcher(t.ped)
    lying, aboard = t, nil
    Prompt('ems', 'info', hospital.name, 'Push them to the door.', 5000)
end

local function hand_over()
    TriggerServerEvent('c3r:ems:deliver', lying.net, hospital and hospital.name) -- (they stay until it's answered: the server has to find them)
end

RegisterNetEvent('c3r:ems:handover', function(r)
    local t = lying
    Prompt('ems', 'ok', 'Handed over', ('%s. %d treated, %d min from first touch to the door. %s'):format(
        hospital and hospital.name or 'Hospital', r.treated, r.minutes, r.grade), 10000)
    clear_hospital()
    if not t then return end
    Stable[t.net] = nil
    put_stretcher_away()
    lying = nil
    if ControlPed(t.ped) then
        DetachEntity(t.ped, false, false)
        SetEntityAsMissionEntity(t.ped, true, true)
        DeleteEntity(t.ped)
    end
end)

-- ─── E: what the moment calls for ─────────────────────────────────────────────

local function stable_near()
    local at = GetEntityCoords(PlayerPedId())
    for net in pairs(Stable) do
        local ped = NetworkDoesEntityExistWithNetworkId(net) and NetToPed(net) or 0
        if ped ~= 0 and DoesEntityExist(ped) and #(GetEntityCoords(ped) - at) < 3.0 then return { ped = ped, net = net } end
    end
end

-- -> { label, fn } | nil
local function action()
    local me = PlayerPedId()
    if scr or opening or not on_ems() then return nil end
    if IsPedInAnyVehicle(me, false) then
        if aboard and (ride == 'back' or ride == 'there') and GetVehiclePedIsIn(me, false) == truck then
            return { 'Treat the patient', function() EmsTreat(aboard.ped) end }
        end
        return nil
    end
    if stretcher then
        if lying then
            if hospital and #(GetEntityCoords(me) - door(hospital)) < 3.5 then return { 'Hand over the patient', hand_over } end
            return nil
        end
        local t = stable_near()
        if t then return { 'Lift onto the stretcher', function() lift(t) end } end
    end
    return nil
end

local function restock()
    put_bag_away()
    TriggerServerEvent('c3r:ems:restock')
end
local WHEEL = { bag = hold_bag, bag_away = restock, stretcher = take_stretcher, stretcher_away = put_stretcher_away,
                load = load_patient, ride = ride_back, unload = unload_patient }

-- client/radial.lua's G wheel, on foot beside their vehicle: what the vehicle's for. -> wheel items | nil
function EmsWheel()
    if scr or opening or not on_ems() or IsPedInAnyVehicle(PlayerPedId(), false) or not near_truck() then return nil end
    local list = {}
    local function add(arg, label, icon, off) list[#list + 1] = { action = 'ems', arg = arg, label = label, icon = icon, off = off } end
    if stretcher then
        if lying then
            if not hospital then add('load', 'Load the patient', 'in') end
        else
            add('stretcher_away', 'Put the stretcher back', 'in')
        end
    elseif aboard then
        if hospital and #(GetEntityCoords(truck) - door(hospital)) < E.hospital_radius and GetEntitySpeed(truck) < 1.0 then
            add('unload', 'Unload the patient', 'out')
        elseif ride ~= 'drive' and back_seat() then
            add('ride', 'Ride in the back with them', 'medic')
        end
    else
        if bag_out then add('bag_away', 'Put the bag back and restock', 'medic') else add('bag', 'Medical bag', 'medic') end
        add('stretcher', 'Stretcher', 'in', not next(Stable) and 'Nobody ready to move' or nil)
    end
    return list[1] and list or nil
end

-- A wheel option picked: still there to do (the moment may have moved on), then done.
function EmsWheelAction(arg)
    for _, it in ipairs(EmsWheel() or {}) do
        if it.arg == arg and not it.off and WHEEL[arg] then return CreateThread(WHEEL[arg]) end
    end
end

-- client/menu.lua's E. -> true when it did something
function EmsInteract()
    local a = action()
    if not a then return false end
    CreateThread(a[2]) -- (models load: it can't run on the key's own thread)
    return true
end

-- Says what E would do, and keeps the pushing and the door.
CreateThread(function()
    local shown
    while true do
        local a = on_ems() and action() or nil
        local label = a and a[1] or (on_ems() and EmsWheel() and 'Your vehicle') or nil
        if label ~= shown then
            shown = label
            if a then Prompt('ems_e', 'info', label, ('Press %s.'):format(KeyName('+c3r_interact', 'E')))
            elseif label then Prompt('ems_e', 'info', label, ('Press %s for the bag, the stretcher and the patient.'):format(KeyName('+c3r_radial', 'G')))
            else ClearPrompt('ems_e') end
        end
        Wait(300)
    end
end)

CreateThread(function()
    while true do
        if stretcher or hospital or aboard then
            local t = lying or aboard
            local p = t and t.ped
            if p and DoesEntityExist(p) and NetworkHasControlOfEntity(p) and HasAnimDictLoaded(SUPINE[1])
                and not IsEntityPlayingAnim(p, SUPINE[1], SUPINE[2], 3) then -- (kept on their back)
                TaskPlayAnim(p, SUPINE[1], SUPINE[2], 8.0, -8.0, -1, 1, 0.0, false, false, false)
            end
            if stretcher then
                local me = PlayerPedId()
                if DoesEntityExist(stretcher) then roll_stretcher() end
                for _, c in ipairs({ 21, 22, 23, 24, 25, 44, 140, 141, 142 }) do DisableControlAction(0, c, true) end -- (a walk: no sprint, jump, car or fists)
                if not IsEntityPlayingAnim(me, PUSH[1], PUSH[2], 3) and HasAnimDictLoaded(PUSH[1]) then
                    TaskPlayAnim(me, PUSH[1], PUSH[2], 4.0, -4.0, -1, 49, 0.0, false, false, false)
                elseif not HasAnimDictLoaded(PUSH[1]) then
                    RequestAnimDict(PUSH[1])
                end
            end
            if hospital then
                DrawMarker(1, hospital.x, hospital.y, hospital.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.5, 2.5, 0.6, 80, 220, 140, 150,
                    false, false, 2, false, nil, nil, false)
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ─── the treatment screen ─────────────────────────────────────────────────────

local PARTS = {
    { 'head', 'Head', 31086 }, { 'neck', 'Neck', 39317 }, { 'thorax', 'Thorax', 24817 }, { 'abdomen', 'Abdomen', 23553 },
    { 'larm', 'Left Arm', 61163 }, { 'rarm', 'Right Arm', 28252 }, { 'lhand', 'Left Hand', 18905 }, { 'rhand', 'Right Hand', 57005 },
    { 'lleg', 'Left Leg', 63931 }, { 'rleg', 'Right Leg', 36864 }, { 'lfoot', 'Left Foot', 14201 }, { 'rfoot', 'Right Foot', 52301 },
}
local HIT = { [58271] = 'lleg', [51826] = 'rleg', [45509] = 'larm', [40269] = 'rarm', [11816] = 'abdomen', [24816] = 'abdomen', [24818] = 'thorax' }
for _, p in ipairs(PARTS) do HIT[p[3]] = p[1] end

-- What hurt them, from the weapon the damage came from: a fall, a car, a blast, fire, a blade, a gun, or a blow.
-- UNVERIFIED: CEventNetworkEntityDamage's args (1: the victim, 7: the weapon) aren't in the official docs; with no
-- weapon there, the ped's own record decides (HAS_PED_BEEN_DAMAGED_BY_WEAPON: 0 a weapon, 1 melee, 2 any).
local function h32(x) return math.type(x) == 'integer' and x % 4294967296 or nil end
local function named(list, cause, into) for _, n in ipairs(list) do into[h32(GetHashKey(n))] = cause end end
local BY_WEAPON, BY_GROUP = {}, {}
named({ 'WEAPON_FALL' }, 'fall', BY_WEAPON)
named({ 'WEAPON_RUN_OVER_BY_CAR', 'WEAPON_RAMMED_BY_CAR' }, 'vehicle', BY_WEAPON)
named({ 'WEAPON_EXPLOSION', 'WEAPON_GRENADE', 'WEAPON_STICKYBOMB', 'WEAPON_PIPEBOMB', 'WEAPON_PROXMINE', 'WEAPON_RPG',
        'WEAPON_GRENADELAUNCHER', 'WEAPON_HOMINGLAUNCHER', 'WEAPON_COMPACTLAUNCHER' }, 'explosion', BY_WEAPON)
named({ 'WEAPON_FIRE', 'WEAPON_MOLOTOV', 'WEAPON_FLARE' }, 'burn', BY_WEAPON)
named({ 'WEAPON_ANIMAL' }, 'bite', BY_WEAPON) -- (a big dog's attack, lwk_k9: its unarmed weapon in peds.meta)
named({ 'WEAPON_KNIFE', 'WEAPON_SWITCHBLADE', 'WEAPON_DAGGER', 'WEAPON_MACHETE', 'WEAPON_BOTTLE', 'WEAPON_HATCHET',
        'WEAPON_BATTLEAXE', 'WEAPON_STONE_HATCHET' }, 'stab', BY_WEAPON)
named({ 'GROUP_PISTOL', 'GROUP_SMG', 'GROUP_RIFLE', 'GROUP_MG', 'GROUP_SHOTGUN', 'GROUP_SNIPER' }, 'gunshot', BY_GROUP)
named({ 'GROUP_MELEE', 'GROUP_UNARMED' }, 'blunt', BY_GROUP)
named({ 'GROUP_HEAVY', 'GROUP_THROWN' }, 'explosion', BY_GROUP)
local FALL = GetHashKey('WEAPON_FALL')

local function cause_of(ped, weapon)
    weapon = h32(weapon)
    if weapon and weapon ~= 0 then
        local c = BY_WEAPON[weapon] or BY_GROUP[h32(GetWeapontypeGroup(weapon))]
        if c then return c end
    end
    if HasPedBeenDamagedByWeapon(ped, FALL, 0) then return 'fall' end
    if HasPedBeenDamagedByWeapon(ped, 0, 1) then return 'blunt' end
    if HasPedBeenDamagedByWeapon(ped, 0, 2) then return 'gunshot' end
    return nil -- (a taser, say: nothing a medic treats)
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local ped = args[1]
    if not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) or IsPedAPlayer(ped)
        or not NetworkGetEntityIsNetworked(ped) or not NetworkHasControlOfEntity(ped) then return end -- (the game that owns them says)
    local cause = cause_of(ped, args[7])
    if not cause then return end
    local ok, bone = GetPedLastDamageBone(ped)
    TriggerServerEvent('c3r:ems:hit', PedToNet(ped), ok and HIT[bone] or nil, cause)
end)

-- Shot, not hit with something (2: any weapon; 1: melee).
local function shot(ped) return HasPedBeenDamagedByWeapon(ped, 0, 2) and not HasPedBeenDamagedByWeapon(ped, 0, 1) end

local function hit_part(ped)
    local ok, bone = GetPedLastDamageBone(ped)
    return ok and HIT[bone] or nil
end

local function bone(ped, id) return GetPedBoneCoords(ped, id, 0.0, 0.0, 0.0) end

-- Where a part's marker goes: its bone. The spine runs down their back, so from above the chest and belly are a little
-- in front of it: toward their hands, across the body (on their back, hands at their sides, that's no way at all).
local function spot(ped, p)
    local at = bone(ped, p[3])
    if p[1] ~= 'thorax' and p[1] ~= 'abdomen' then return at end
    local axis = bone(ped, 31086) - bone(ped, 11816)
    axis = vector3(axis.x, axis.y, 0.0)
    axis = axis / math.max(#axis, 0.01)
    local hands = (bone(ped, 18905) + bone(ped, 57005)) / 2 - at
    local flat = vector3(hands.x, hands.y, 0.0)
    local front = flat - axis * (flat.x * axis.x + flat.y * axis.y)
    if #front < 0.05 then return at end
    return at + front / #front * math.min(#front, 0.14)
end

-- The bag goes down by their side, to the right of the view.
local function set_bag_down(ped)
    local head, feet = bone(ped, 31086), bone(ped, 14201)
    local d = head - feet
    local side = vector3(d.y, -d.x, 0.0)
    local at = bone(ped, 23553) + side / math.max(#side, 0.01) * 1.0
    if bag then
        DetachEntity(bag, false, false)
        SetEntityCoords(bag, at.x, at.y, at.z, false, false, false, false)
        PlaceObjectOnGroundProperly(bag)
        return GetEntityCoords(bag)
    end
    return at
end

-- Straight down on them, head at the top of the screen.
local function overhead(ped)
    local head, feet = bone(ped, 31086), bone(ped, 14201)
    local mid = (head + feet) / 2
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', mid.x, mid.y, mid.z + E.cam_height, -89.0, 0.0,
        GetHeadingFromVector_2d(head.x - feet.x, head.y - feet.y), 55.0, false, 2)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)
    return cam
end

-- In the back of the ambulance: straight down on them from the roof, head at the top, fixed to the truck (it moves).
local function in_the_back(ped)
    local head, feet = bone(ped, 31086), bone(ped, 14201)
    local mid = (head + feet) / 2
    local p = GetOffsetFromEntityGivenWorldCoords(truck, mid.x, mid.y, mid.z)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
    HardAttachCamToEntity(cam, truck, -89.0, 0.0, 0.0, p.x, p.y, p.z + E.back_cam_height, true)
    SetCamFov(cam, 80.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)
    return cam
end

local function project(at)
    local on, x, y = GetScreenCoordFromWorldCoord(at.x, at.y, at.z)
    return on and { x = x, y = y } or nil
end

local function net_of(ped)
    if not NetworkGetEntityIsNetworked(ped) then NetworkRegisterEntityAsNetworked(ped) end
    local deadline = GetGameTimer() + 1500
    while not NetworkGetEntityIsNetworked(ped) and GetGameTimer() < deadline do Wait(50) end
    return NetworkGetEntityIsNetworked(ped) and PedToNet(ped) or nil
end

-- A patient in the back (client/presence.lua).
function EmsAboard() return aboard ~= nil end

-- The treatment screen is up (client/callouts.lua leaves its arrows off, client/menu.lua its hint).
function EmsScreen() return scr ~= nil or opening end

-- client/menu.lua's E beside someone down.
function EmsTreat(ped)
    if scr or opening then return end
    local inside = aboard ~= nil and aboard.ped == ped -- (on the cot in the back: the kit's all there)
    if have_truck() and not bag_out and not inside then
        return Prompt('ems', 'info', 'No bag', ('Press %s at your vehicle for your medical bag.'):format(KeyName('+c3r_radial', 'G')), 5000)
    end
    opening = true
    CreateThread(function()
        local net = net_of(ped)
        if not net then opening = false return end
        if not inside then
            if not IsEntityDead(ped) then HoldDown(ped) end
            KneelAt(ped)
            local me = PlayerPedId()
            if LoadDict(MedicAnim.vitals[1]) then -- (what everyone else sees)
                TaskPlayAnim(me, MedicAnim.vitals[1], MedicAnim.vitals[2], 4.0, -4.0, -1, 1, 0.0, false, false, false)
            end
        end
        local kit = not inside and set_bag_down(ped) or nil
        local cam = inside and in_the_back(ped) or overhead(ped)
        Wait(450) -- (the camera's there: what's on screen can be worked out now)
        local parts = {}
        for _, p in ipairs(PARTS) do
            local s = project(spot(ped, p))
            if s then parts[#parts + 1] = { id = p[1], label = p[2], x = s.x, y = s.y } end
        end
        scr, opening = { ped = ped, net = net, cam = cam, inside = inside }, false
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'ems', open = true, parts = parts, bag = kit and project(kit), tools = E.tools, inside = inside })
        TriggerServerEvent('c3r:ems:start', net, hit_part(ped), IsEntityDead(ped) or IsPedDeadOrDying(ped, true), shot(ped))
        while scr do -- (the medic would stand in the way: the overhead view is of the patient)
            SetEntityLocallyInvisible(PlayerPedId())
            InvalidateIdleCam()
            Wait(0)
        end
    end)
end

local function close_screen()
    local s = scr
    if not s then return end
    scr = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'ems', open = false })
    NoPause()
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(s.cam, false)
    if not s.inside then ClearPedTasks(PlayerPedId()) end
    TriggerServerEvent('c3r:ems:leave', s.net)
    if bag_out then hold_bag() end
end

RegisterNetEvent('c3r:ems:view', function(net, view, result)
    if view.stable then Stable[net] = true else Stable[net] = nil end
    if not (scr and scr.net == net) then return end
    if result and result.kind == 'rosc' and IsEntityDead(scr.ped) then -- (found dead, and brought back)
        local ped = scr.ped
        CreateThread(function() if ControlPed(ped) then RevivePed(ped) end end)
    end
    local cpr = view.cpr ~= nil
    if cpr ~= (scr.cpr or false) and not scr.inside then -- (on the chest, or back to watching them: what everyone else sees)
        scr.cpr = cpr
        local anim = cpr and MedicAnim.cpr or MedicAnim.vitals
        CreateThread(function()
            if LoadDict(anim[1]) then TaskPlayAnim(PlayerPedId(), anim[1], anim[2], 4.0, -4.0, -1, 1, 0.0, false, false, false) end
        end)
    end
    SendNUIMessage({ type = 'ems', view = view, result = result })
end)

-- A bleed shows: blood on that part of them (server/ems.lua says where), in every game that has them.
-- UNVERIFIED: the zone numbers (torso, head, left arm, right arm, left leg, right leg) and the blood names, from peddamage.xml.
local ZONE = { thorax = 0, abdomen = 0, head = 1, neck = 1, larm = 2, lhand = 2, rarm = 3, rhand = 3, lleg = 4, lfoot = 4, rleg = 5, rfoot = 5 }
AddStateBagChangeHandler('c3r_blood', nil, function(bag, _, parts)
    if type(parts) ~= 'table' then return end
    CreateThread(function()
        local ent, deadline = GetEntityFromStateBagName(bag), GetGameTimer() + 5000
        while (ent == 0 or not DoesEntityExist(ent)) and GetGameTimer() < deadline do
            Wait(100)
            ent = GetEntityFromStateBagName(bag)
        end
        if ent == 0 or not DoesEntityExist(ent) then return end
        for _, part in ipairs(parts) do
            local z = ZONE[part]
            if z then
                ApplyPedBloodSpecific(ent, z, 0.5, part == 'abdomen' and 0.65 or 0.45, 0.0, 1.0, -1, 0.0, 'BulletLarge')
                ApplyPedBloodSpecific(ent, z, 0.5, 0.5, 0.0, 1.0, -1, 0.0, 'wound_sheet')
            end
        end
    end)
end)

-- Their time ran out, and this game owns them.
RegisterNetEvent('c3r:ems:kill', function(net)
    local ped = NetworkDoesEntityExistWithNetworkId(net) and NetToPed(net) or 0
    if ped ~= 0 and DoesEntityExist(ped) then SetEntityHealth(ped, 0) end
end)

RegisterNUICallback('emsUse', function(d, cb)
    cb({})
    if scr then TriggerServerEvent('c3r:ems:use', scr.net, d.part, d.tool) end
end)
RegisterNUICallback('emsClose', function(_, cb)
    cb({})
    close_screen()
end)
RegisterNUICallback('emsPronounce', function(_, cb)
    cb({})
    if not scr then return end
    TriggerServerEvent('c3r:ems:pronounce', scr.net)
    Stable[scr.net] = nil
    Prompt('ems', 'info', 'Pronounced', 'The coroner can take them.', 6000)
    close_screen()
end)

-- ─── a police unit asking for an ambulance (server/ems.lua) ───────────────────

local ask, job = nil, nil -- the request on the card: { id, at, from, until_t }; the one taken: { id, at, from, blip }

local function clear_job()
    if job and job.blip and DoesBlipExist(job.blip) then RemoveBlip(job.blip) end
    job = nil
end

RegisterNetEvent('c3r:ems:offer', function(o)
    if not o then
        if ask then
            ask = nil
            SendNUIMessage({ type = 'callout', offer = false })
        end
        return
    end
    ask = { id = o.id, at = vector3(o.at.x, o.at.y, o.at.z), from = o.from, until_t = GetGameTimer() + o.ms }
    local police = o.want == 'police' -- (a medic asking an officer for help on scene)
    local street = GetStreetNameFromHashKey((GetStreetNameAtCoord(ask.at.x, ask.at.y, ask.at.z)))
    SendNUIMessage({ type = 'callout', offer = { name = police and 'Police assistance requested' or 'Ambulance requested', street = street,
        distance = #(GetEntityCoords(PlayerPedId()) - ask.at),
        report = police and ('Paramedic %s needs police at their scene.'):format(o.from) or ('%s needs an ambulance at their scene.'):format(o.from),
        priority = 1, key = KeyName('+c3r_respond', 'Y'), decline = KeyName('+c3r_leavecall', 'X'), ms = o.ms } })
    local text = police and ('All units, paramedics request police assistance on %s.'):format(street)
        or ('Medic units, %s requests an ambulance on %s.'):format(o.from, street)
    local said = pcall(function() exports.lwk_control:sayCall(police and 'police_request' or 'ems_request', ask.at, text) end)
    if not said then Notify('~b~DISPATCH~s~ ' .. text) end
end)

RegisterNetEvent('c3r:ems:assigned', function(j, why)
    clear_job()
    if j then
        job = { id = j.id, at = vector3(j.at.x, j.at.y, j.at.z), from = j.from }
        job.blip = AddBlipForCoord(job.at.x, job.at.y, job.at.z)
        SetBlipColour(job.blip, 1)
        SetBlipRoute(job.blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(j.want == 'police' and 'Medic needs police' or 'Ambulance request')
        EndTextCommandSetBlipName(job.blip)
        return Prompt('ems', 'ok', 'Responding', ('To %s. It is on your map.'):format(j.from), 6000)
    end
    if why == 'cancelled' then Prompt('ems', 'info', 'Stood down', 'They no longer need you.', 6000)
    elseif why == 'arrived' then Prompt('ems', 'ok', 'On scene', 'Find the patient.', 5000) end
end)

-- client/callouts.lua's Y: take the request on the card. -> true when there was one
function EmsRespond()
    if not ask or GetGameTimer() > ask.until_t then return false end
    TriggerServerEvent('c3r:ems:accept', ask.id)
    ask = nil
    SendNUIMessage({ type = 'callout', offer = false })
    return true
end

-- client/callouts.lua's X: let the card go, or give up a request taken (the AI crew goes instead). -> true when it did
function EmsDecline()
    if ask and GetGameTimer() < ask.until_t then
        ask = nil
        SendNUIMessage({ type = 'callout', offer = false })
        return true
    end
    if not job then return false end
    clear_job()
    TriggerServerEvent('c3r:ems:drop')
    Prompt('ems', 'info', 'Request dropped', 'An AI unit goes instead.', 5000)
    return true
end

-- ─── the shift ────────────────────────────────────────────────────────────────

local function end_of_shift()
    close_screen()
    clear_hospital()
    put_bag_away()
    local t = lying or aboard
    lying, aboard = nil, nil
    if stretcher then put_stretcher_away() end
    if t and ControlPed(t.ped) then
        DetachEntity(t.ped, false, false)
        DeleteEntity(t.ped)
    end
    Stable = {}
    ride, ask = nil, nil
    clear_job()
    if partner and DoesEntityExist(partner) then DeleteEntity(partner) end
    partner = nil
    if brought and have_truck() then DeleteEntity(truck) end -- (their own vehicle stays theirs)
    truck, brought = nil, false
    ClearPrompt('ems_e')
end

-- (the handler is told before the bag's value is readable: go by what it's given)
AddStateBagChangeHandler('c3rService', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, service)
    CreateThread(function()
        if service == 'ambulance' then
            dress()
            if E.bring_vehicle then
                bring_truck()
                bring_partner()
            else
                Prompt('ems', 'info', 'On shift', 'Get in any vehicle and drive it: it is your ambulance for the shift.', 8000)
            end
        elseif truck or was or partner then
            end_of_shift()
            undress()
        end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if scr then
        SetNuiFocus(false, false)
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(scr.cam, false)
    end
    drop_prop(bag)
    drop_prop(stretcher)
    clear_hospital()
    if partner and DoesEntityExist(partner) then DeleteEntity(partner) end
    if brought and have_truck() then DeleteEntity(truck) end
end)
