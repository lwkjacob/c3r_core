--[[
    c3r — client: picking the car to stop, how its driver pulls over, and what they do after.
    The server decides everything about the driver; this side moves the ped and the car, which only
    the entity's owner can do, so the officer takes control of both for the length of the stop.
]]

-- { veh, veh_net, ped / ped_net (the driver), occ = { [net] = { net, ped, seat, role, look, out, following, task, doing,
--   questions, fleeing, escaped, cuffed, escorted, seated } }, hint = { slow, flee, bail }, categories, stopped, mode,
--   manual, pursuit, towed, lost_on_foot, foot (someone on foot: veh is 0), parked (walked up to a car standing still),
--   empty (a car with nobody in it: no ped) }
Stop = nil
local clipboard = nil -- the ticket clipboard prop while it's out (true while it loads)
Custody = {}         -- [net] = { ped, car }: arrested and sitting in the back of the officer's car, until booked
                     -- (global: client/backup.lua's prisoner transport takes them from here)
local towing = {}     -- [entity] = true: tow trucks and drivers out on a job, removed if c3r stops mid-tow

-- Backup units (client/backup.lua) and the tow truck: never something to pull over, talk to or tow. Tagged on the
-- entity (other officers' games see it too) and kept here (a server in state bag strict mode won't replicate the tag).
BackupEnts = {}
function IsBackup(ent)
    if BackupEnts[ent] then return true end
    local ok, tag = pcall(function() return Entity(ent).state.c3rBackup end)
    return ok and tag == true
end
function TagBackup(ent)
    BackupEnts[ent] = true
    pcall(function() Entity(ent).state:set('c3rBackup', true, true) end)
end

local function log(fmt, ...)
    if Config.Debug then print(('[c3r] ' .. fmt):format(...)) end
end

local function label(key)
    local text = GetLabelText(key)
    return text ~= 'NULL' and text or nil
end

-- GTA paint (rgb) -> the nearest of lwk_control's colour words, so the plate readout can say it.
local COLOURS = {
    { 'Black', 15, 15, 18 }, { 'Grey', 90, 92, 95 }, { 'Silver', 165, 168, 172 }, { 'White', 235, 235, 235 },
    { 'Red', 170, 20, 20 }, { 'Maroon', 85, 15, 22 }, { 'Orange', 220, 110, 25 }, { 'Yellow', 230, 200, 35 },
    { 'Gold', 175, 140, 60 }, { 'Bronze', 140, 90, 50 }, { 'Beige', 205, 185, 145 }, { 'Brown', 95, 60, 35 },
    { 'Green', 35, 110, 45 }, { 'Blue', 30, 70, 170 }, { 'Purple', 95, 40, 125 }, { 'Pink', 225, 110, 165 },
}

local function colour_name(r, g, b)
    local best, best_d
    for _, c in ipairs(COLOURS) do
        local d = (r - c[2]) ^ 2 + (g - c[3]) ^ 2 + (b - c[4]) ^ 2
        if not best_d or d < best_d then best, best_d = c[1], d end
    end
    return best
end

-- Network control, so tasks stick (temp actions don't work on another player's copy of the ped).
local function control(ent)
    local deadline = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(ent)
        Wait(0)
    end
    return NetworkHasControlOfEntity(ent)
end

-- IsPedMale comes back as 1 / 0, not a boolean; sent as is, the server's `== true` made every ped a woman.
local function is_male(ped)
    local m = IsPedMale(ped)
    return m == true or m == 1
end

local function wait_until(ms, done)
    local deadline = GetGameTimer() + ms
    while not done() and GetGameTimer() < deadline do Wait(200) end
    return done()
end

-- For client/staged.lua: what the officer's game knows about a car, the way a stop sends it.
function VehicleInfo(veh)
    local model = GetEntityModel(veh)
    return { make = label(GetMakeNameFromVehicleModel(model)),
             model = label(GetDisplayNameFromVehicleModel(model)) or GetDisplayNameFromVehicleModel(model),
             color = colour_name(GetVehicleColor(veh)) }
end
IsMale = is_male

local function load_dict(dict)
    RequestAnimDict(dict)
    wait_until(1000, function() return HasAnimDictLoaded(dict) end)
    return HasAnimDictLoaded(dict)
end

-- A walking style (drunk, say), which also changes how they stand.
local function walk_style(ped, set)
    RequestAnimSet(set)
    if wait_until(1000, function() return HasAnimSetLoaded(set) end) then SetPedMovementClipset(ped, set, 1.0) end
end

-- ─── picking the car ──────────────────────────────────────────────────────────
-- The target key in a police car puts a red circle on the road ahead that moves with the car. Drive so
-- it sits under the car you want: it locks on and lifts. Then lights, siren or the horn tell them to pull
-- over. The key again, or letting them get too far away, lets go.

local function police_car()
    local me = PlayerPedId()
    local veh = GetVehiclePedIsIn(me, false)
    -- any car you drive on duty: addon police cars often aren't GTA's emergency class
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= me then return nil end
    return veh
end

local targeting, locked, asking = false, nil, false

-- The point on the road the circle marks: Config.Target.distance ahead of the patrol car, on the ground.
local function circle_point(own)
    local p = GetOffsetFromEntityInWorldCoords(own, 0.0, Config.Target.distance, 0.0)
    local ok, z = GetGroundZFor_3dCoord(p.x, p.y, p.z + 2.0, false)
    return vector3(p.x, p.y, ok and z or p.z - 0.5)
end

-- The AI-driven car whose centre is over the circle, if any.
local function car_under(own, p)
    local best, best_d
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if veh ~= own and GetVehicleClass(veh) ~= 18 and not IsBackup(veh) then
            local c = GetEntityCoords(veh)
            local d = #(vector2(c.x, c.y) - vector2(p.x, p.y))
            local driver = GetPedInVehicleSeat(veh, -1)
            if d < Config.Target.radius and (not best_d or d < best_d) and driver ~= 0 and not IsPedAPlayer(driver)
                and not IsEntityDead(driver) then
                best, best_d = veh, d
            end
        end
    end
    return best
end

local function ring(x, y, z, size, alpha)
    local c = Config.Target.color
    DrawMarker(23, x, y, z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, 1.0, c[1], c[2], c[3], alpha,
        false, false, 2, false, nil, nil, false)
end

local function stop_targeting(reason)
    targeting, locked, asking = false, nil, false
    if reason then Prompt('target', 'info', 'Pull-over cancelled', reason, 3500) else ClearPrompt('target') end
end

local function target_key() return KeyName('+c3r_target', 'Shift') end

-- Everyone in the car, networked (ambient traffic often isn't, and then the server can't see it), then
-- the request. people: { { seat, net, male } }, the driver first.
local function request_stop(veh, opts)
    asking = true
    CreateThread(function()
        local people = {}
        for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
            local ped = GetPedInVehicleSeat(veh, seat)
            if ped ~= 0 and not IsPedAPlayer(ped) then people[#people + 1] = { seat = seat, ped = ped } end
        end
        local ents = { veh }
        for _, p in ipairs(people) do ents[#ents + 1] = p.ped end
        for _, e in ipairs(ents) do
            if not NetworkGetEntityIsNetworked(e) then NetworkRegisterEntityAsNetworked(e) end
        end
        local ok = wait_until(1500, function()
            for _, e in ipairs(ents) do
                if not NetworkGetEntityIsNetworked(e) then return false end
            end
            return true
        end)
        local empty = opts and opts.empty
        if not ok or (not empty and (not people[1] or people[1].seat ~= -1)) or (empty and people[1]) then
            asking = false
            return log('could not network %s', GetVehicleNumberPlateText(veh))
        end
        local list = {}
        for i, p in ipairs(people) do list[i] = { seat = p.seat, net = PedToNet(p.ped), male = is_male(p.ped) } end
        local model = GetEntityModel(veh)
        log('asking to stop %s (%d aboard)', GetVehicleNumberPlateText(veh), #list)
        if opts and opts.contact then opts.contact = PedToNet(opts.contact) end
        TriggerServerEvent('c3r:stop:start', VehToNet(veh), list, {
            make = label(GetMakeNameFromVehicleModel(model)),
            model = label(GetDisplayNameFromVehicleModel(model)) or GetDisplayNameFromVehicleModel(model),
            color = colour_name(GetVehicleColor(veh)),
        }, opts)
        SetTimeout(4000, function() asking = false end) -- refused or lost: the signal can be given again
    end)
end

CreateThread(function()
    local next_scan, siren_was = 0, false
    while true do
        local own = targeting and police_car()
        if targeting and (not own or Stop or not LocalPlayer.state.c3rDuty) then
            stop_targeting()
            own = nil
        end
        if own and locked then
            local c = GetEntityCoords(locked)
            if not DoesEntityExist(locked) or #(c - GetEntityCoords(own)) > Config.Target.lose_distance then
                stop_targeting('They got too far away.')
            else
                ring(c.x, c.y, c.z - 0.25, 3.6, 210) -- lifted onto the car
                -- the signal: lights or siren switched on, or a tap of the horn
                local siren = IsVehicleSirenOn(own)
                if not asking and ((siren and not siren_was) or IsControlJustPressed(0, 86)) then request_stop(locked) end
                siren_was = siren
            end
            Wait(0)
        elseif own then
            local p = circle_point(own)
            ring(p.x, p.y, p.z + 0.05, 4.2, 150)
            if GetGameTimer() >= next_scan then -- the search walks every car: a few times a second is plenty
                next_scan = GetGameTimer() + 150
                local car = car_under(own, p)
                if car then
                    locked, siren_was = car, IsVehicleSirenOn(own)
                    Prompt('target', 'alert', 'Vehicle locked',
                        'Turn on your lights or siren, or tap the horn, to signal the driver to pull over.')
                end
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- The vehicle menu on a car that isn't stopped (radial.lua): it becomes a quiet stop first (whoever's at the
-- wheel stays put; nobody in it: just the car), then the action is done.
local queued = nil
function RequestVehicle(veh, action)
    if Stop or asking or not DoesEntityExist(veh) then return end
    local driver = GetPedInVehicleSeat(veh, -1)
    local anyone = false
    for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        local p = GetPedInVehicleSeat(veh, seat)
        anyone = anyone or (p ~= 0 and not IsPedAPlayer(p))
    end
    if anyone and (driver == 0 or IsPedAPlayer(driver)) then return end -- passengers with nobody at the wheel: leave it
    queued = action
    request_stop(veh, anyone and { parked = true } or { empty = true })
end

-- Walking up to anyone (menu.lua's E with no stop on): someone sitting in a car that's standing still is a stop
-- of that car where it is; someone on foot is a stop of just them.
function RequestContact(ped)
    if Stop or asking or not DoesEntityExist(ped) then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        if GetPedInVehicleSeat(veh, -1) == 0 or IsPedAPlayer(GetPedInVehicleSeat(veh, -1)) or GetEntitySpeed(veh) > 1.0 then return end
        return request_stop(veh, { parked = true, contact = ped })
    end
    asking = true
    CreateThread(function()
        if not NetworkGetEntityIsNetworked(ped) then NetworkRegisterEntityAsNetworked(ped) end
        if wait_until(1500, function() return NetworkGetEntityIsNetworked(ped) end) then
            TriggerServerEvent('c3r:stop:start', nil, { { net = PedToNet(ped), male = is_male(ped) } }, nil, { foot = true })
        end
        SetTimeout(4000, function() asking = false end)
    end)
end

-- Who in the stop's car can be ordered: not in cuffs, running or gone. -> nets in the car, nets out of it
function VehicleFree(s)
    local inside, outside = {}, {}
    for net, o in pairs(s.occ) do
        if DoesEntityExist(o.ped) and not IsEntityDead(o.ped) and not o.cuffed and not o.fleeing and not o.escaped then
            if IsPedInVehicle(o.ped, s.veh, false) then inside[#inside + 1] = net elseif o.out then outside[#outside + 1] = net end
        end
    end
    return inside, outside
end

-- search_car | tow | all_out | all_in, on the stop's car
function VehicleAction(s, action)
    if action == 'all_out' or action == 'all_in' then
        local inside, outside = VehicleFree(s)
        for _, net in ipairs(action == 'all_out' and inside or outside) do
            TriggerServerEvent('c3r:stop:act', action == 'all_out' and 'exit' or 'back', nil, net)
        end
    elseif action == 'tow' then -- through dispatch (its voice, "tow truck en route for the ..."), like asking by radio
        CallBackup('tow')
    elseif action == 'search_car' then
        TriggerServerEvent('c3r:stop:act', action, nil, s.ped_net)
    end
end

-- "Run plate": the record as a card (nil: no such car near enough to have papers made up)
RegisterNetEvent('c3r:plateResult', function(plate, v)
    if not v then return Prompt('plate', 'info', 'Plate ' .. tostring(plate), 'No record.', 6000) end
    local bad = v.stolen or v.bolo or v.reg_valid == false or v.ins_valid == false
    local car = table.concat({ v.year or '', v.make or '', v.model or '' }, ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local text = ('%s%s. Registered to %s. Registration %s, insurance %s.'):format(car ~= '' and car or 'Vehicle',
        v.color and (', ' .. v.color:lower()) or '', v.owner or 'nobody on file', v.reg_valid == false and 'EXPIRED' or 'valid',
        v.ins_valid == false and 'NONE' or 'valid')
    if v.stolen then text = text .. ' REPORTED STOLEN.' end
    if v.bolo then text = text .. ' BOLO: ' .. tostring(v.bolo_reason or 'on file') .. '.' end
    Prompt('plate', bad and 'alert' or 'ok', 'Plate ' .. tostring(v.plate or plate), text, 12000)
end)

-- A plate run that isn't on file (the server's LookupPlate): the car with that plate near the officer, if any,
-- as their game sees it: make, model, colour, and whether a man or a woman is at the wheel.
RegisterNetEvent('c3r:describePlate', function(plate, id)
    local me = GetEntityCoords(PlayerPedId())
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local p = (GetVehicleNumberPlateText(veh) or ''):upper():gsub('[^%w]', '')
        if p == plate and #(GetEntityCoords(veh) - me) < 150.0 then
            local model, at_wheel = GetEntityModel(veh), GetPedInVehicleSeat(veh, -1)
            local driver = nil
            if at_wheel ~= 0 and not IsPedAPlayer(at_wheel) then driver = is_male(at_wheel) end
            return TriggerServerEvent('c3r:describedPlate', id, {
                make = label(GetMakeNameFromVehicleModel(model)),
                model = label(GetDisplayNameFromVehicleModel(model)) or GetDisplayNameFromVehicleModel(model),
                color = colour_name(GetVehicleColor(veh)), driver = driver,
            })
        end
    end
    TriggerServerEvent('c3r:describedPlate', id, nil)
end)

-- The PA's "pull over": the locked car is signalled, like lights or the horn. -> true when it was
function Targeting() return targeting end -- (client/staged.lua leaves the officer alone while they pick a car)

function PaPullOver()
    if Stop or asking then return false end
    if not (targeting and locked and DoesEntityExist(locked)) then
        Prompt('target', 'info', 'Nothing to pull over', ('Lock onto a car with %s first.'):format(target_key()), 3500)
        return false
    end
    request_stop(locked)
    return true
end

local last_toggle = 0
local function toggle_target()
    if GetGameTimer() - last_toggle < 300 then return end -- the key mapping and the control poll below both fired
    last_toggle = GetGameTimer()
    if Stop then return end -- during a stop, the mode key has "Stop pullover"
    if targeting then return stop_targeting() end
    -- off duty or on foot: say nothing (Left Shift is also sprint, so it's pressed all the time)
    if not LocalPlayer.state.c3rDuty or not police_car() then return end
    targeting = true
    Prompt('target', 'alert', 'Pick a vehicle',
        ('Drive so the red circle sits under the car you want to stop. %s again to cancel.'):format(target_key()))
end

RegisterCommand('+c3r_target', toggle_target, false)
RegisterCommand('-c3r_target', function() end, false)
RegisterKeyMapping('+c3r_target', 'Pick a car to pull over / cancel (c3r)', 'keyboard', Config.TargetKey)

-- FiveM's key mapping doesn't always fire for Left Shift in a car, so read the game's own control too
-- (21 is Left Shift). Only while driving on duty, and only for the default key.
CreateThread(function()
    while true do
        if Config.TargetKey == 'LSHIFT' and LocalPlayer.state.c3rDuty and police_car() then
            if IsDisabledControlJustPressed(0, 21) then toggle_target() end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ─── pulling over ─────────────────────────────────────────────────────────────

-- Stopped: a straight brake, then wait there with the engine running.
local function hold(s)
    if not s.ped then return end -- nobody at the wheel to hold it
    TaskVehicleTempAction(s.ped, s.veh, 27, 1500)
    SetTimeout(1500, function()
        if Stop == s and not s.mode and IsPedInVehicle(s.ped, s.veh, false) then
            TaskVehicleTempAction(s.ped, s.veh, 1, 10000000)
        end
    end)
end

-- Is p on a road running the same way as heading h (either direction), not on a street that crosses it?
local function along_road(p, h)
    local ok, _, nh = GetClosestVehicleNodeWithHeading(p.x, p.y, p.z, 1, 3.0, 0)
    if not ok then return false end
    local d = math.abs((nh - h + 180.0) % 360.0 - 180.0)
    return math.min(d, 180.0 - d) < 25.0
end

-- Near a junction: a road node within 12 m of p (flat distance: roads climb) belonging to a street that
-- crosses heading h. 12 nodes: on a wide road the nearest few all belong to the road itself.
local function near_junction(p, h)
    for n = 1, 12 do
        local ok, node, nh = GetNthClosestVehicleNodeWithHeading(p.x, p.y, p.z, n, 1, 3.0, 0)
        if ok and #(vector2(node.x, node.y) - vector2(p.x, p.y)) < 12.0 then
            local d = math.abs((nh - h + 180.0) % 360.0 - 180.0)
            if math.min(d, 180.0 - d) > 60.0 then return true end
        end
    end
    return false
end

-- Somewhere to stop that no parked car is already in (moving traffic will have passed by then).
local function clear(p, own)
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local c = GetEntityCoords(v)
        if v ~= own and GetEntitySpeed(v) < 0.5 and #(vector2(c.x, c.y) - vector2(p.x, p.y)) < 4.0 then return false end
    end
    return true
end

-- How far right of p the kerb is, out to `max` m (GTA's road boundary, which is the far side of the
-- pavement, so the kerb can't be past it). Walking out in 25 cm steps from 1.5 m, a kerb is a rise of
-- 8-40 cm over 50 cm (kerbs can be rounded) with flat pavement behind it; road camber is under 1 cm a step, and a hillside or verge keeps
-- climbing. nil: no kerb (a country road or a bridge). The boundary itself can't be used as the kerb:
-- drivers sent there park on the pavement.
local function ground(q)
    return GetGroundZFor_3dCoord(q.x, q.y, q.z + 2.0, false)
end

local function kerb_distance(p, right, max)
    local zs, n = {}, math.floor((max - 0.5) / 0.25) -- ground height every 25 cm out from 0.5 m
    for i = 0, n do
        local ok, z = ground(p + right * (0.5 + i * 0.25))
        zs[i] = ok and z or nil
    end
    for i = 4, n - 2 do -- from 1.5 m out (zs has holes where a probe found nothing: no #zs)
        local z0, z, z2 = zs[i - 2], zs[i], zs[i + 2]
        if z0 and z and z2 and z - z0 > 0.08 and z - z0 < 0.4 and math.abs(z2 - z) < 0.06 then
            return 0.5 + (i - 1) * 0.25 -- the middle of the rise
        end
    end
end

-- Pull a spot in towards the lane until it's level with the road beside it: up on a pavement, a verge or
-- a kerb's slope it would stand higher. lane = the point in the lane level with it. -> lateral offset
local function at_road_level(lane, right, side)
    local ok, road = ground(lane)
    if not ok then return side end
    while side > 0.0 do
        local found, z = ground(lane + right * side)
        if not found or z - road < 0.06 then break end
        side = side - 0.5
    end
    return math.max(side, 0.0)
end

local function half_width(veh)
    local min, max = GetModelDimensions(GetEntityModel(veh))
    return (max.x - min.x) / 2
end

local function diff(a, b) return math.abs((a - b + 180.0) % 360.0 - 180.0) end

-- The road ahead of the car, every 5 m out to `max` m, following its bends: each step goes 5 m along the
-- current heading and takes the heading of the nearest road node running roughly the same way (a node at
-- a sharp angle belongs to a crossing street: ignored, so the trace stays on this road). Positions stay
-- in the car's own lane. -> { { pos, h, dist }, ... }
local function trace_road(veh, max)
    local pos, h, out = GetEntityCoords(veh), GetEntityHeading(veh), {}
    for dist = 5.0, max, 5.0 do
        local r = math.rad(h)
        pos = pos + vector3(-math.sin(r), math.cos(r), 0.0) * 5.0
        for n = 1, 4 do
            local ok, node, nh = GetNthClosestVehicleNodeWithHeading(pos.x, pos.y, pos.z, n, 1, 3.0, 0)
            if ok and #(vector2(node.x, node.y) - vector2(pos.x, pos.y)) < 10.0 then
                if diff(nh, h) > 90.0 then nh = (nh + 180.0) % 360.0 end
                if diff(nh, h) < 35.0 then
                    h, pos = nh, vector3(pos.x, pos.y, node.z) -- the road's height too: it climbs and dips
                    break
                end
            end
        end
        out[#out + 1] = { pos = pos, h = h, dist = dist }
    end
    return out
end

-- Where the car's centre should stop level with lane point `lane` (road heading h): its right side
-- `kerb_gap` off the kerb. No kerb: GTA's road boundary less kerb_inset, at most 2.5 m out (the boundary
-- can be the far side of a verge or pavement). Either way pulled in to road level.
-- -> spot, room (a kerb was found, or there's at least half a metre of road to the right: a big junction
-- has neither, it's open tarmac with no edge)
local function edge_at(lane, h, half)
    local r = math.rad(h)
    local right = vector3(math.cos(r), math.sin(r), 0.0)
    local found, edge = GetRoadBoundaryUsingHeading(lane.x, lane.y, lane.z, h)
    local out = found and edge - lane
    local side = out and out.x * right.x + out.y * right.y or nil
    local kerb = kerb_distance(lane, right, side and math.min(side + 0.5, 9.0) or 6.0)
    local stop
    if kerb then
        stop = kerb - half - Config.Pullover.kerb_gap
    elseif side and side > 0.0 then
        stop = math.min(side - Config.Pullover.kerb_inset, 2.5)
    else
        stop = 1.5 -- no edge found at all: half a lane over
    end
    stop = at_road_level(lane, right, math.max(0.0, stop))
    log('  %s, stop %.2f m right', kerb and ('kerb %.2f m'):format(kerb) or 'no kerb', stop)
    return lane + right * stop, kerb ~= nil or stop >= 0.5
end

-- Where to stop, the way a driver picks a spot: further along the road they're on (following its bends,
-- never into a side street), out of the junction (both the spot and where they roll on to), and not
-- where a car is already parked (at the spot or where they roll on to). A few distances are tried,
-- nearest to `dist` first; one per frame. -> spot, road heading there, final point (the roll-on end,
-- measured on the road a little further on, so it follows a bend instead of cutting into its kerb)
local function kerb_point(veh, dist, min_dist)
    local trace = trace_road(veh, dist + 60.0)
    local half = half_width(veh)
    local roll_steps = math.max(1, math.floor(Config.Pullover.straighten / 5.0 + 0.5))
    local fallback, tried = nil, {}
    for _, extra in ipairs({ 0.0, -10.0, 10.0, -15.0, 20.0, 30.0, 45.0 }) do
        local want = math.max(min_dist, dist + extra) -- never so close they'd overshoot it and turn back
        local i = math.max(1, math.min(#trace - roll_steps, math.floor(want / 5.0 + 0.5)))
        local t, t2 = trace[i], trace[i + roll_steps]
        if t and t2 and not tried[i] then
            tried[i] = true
            local spot, room = edge_at(t.pos, t.h, half)
            local final = edge_at(t2.pos, t2.h, half)
            local junction = not room or near_junction(spot, t.h) or near_junction(final, t2.h)
            if not junction and clear(spot, veh) and clear(final, veh) then
                log('stop point %.0f m ahead', t.dist)
                return spot, t.h, final
            end
            if not junction and not (fallback and not fallback.junction) then
                fallback = { spot, t.h, final, junction = false } -- second best: a parked car near, out of the junction
            end
            fallback = fallback or { spot, t.h, final, junction = true } -- last resort: the nearest spot
            Wait(0) -- each try is ~70 ground probes and two passes over every car: spread them out
        end
    end
    log('stop point: no clear spot (%s)', fallback and (fallback.junction and 'nearest' or 'a parked car near') or 'none')
    if fallback then return fallback[1], fallback[2], fallback[3] end
    local h = GetEntityHeading(veh)
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, dist, 0.0), h,
        GetOffsetFromEntityInWorldCoords(veh, 0.0, dist + Config.Pullover.straighten, 0.0)
end

local function angle_off(veh, h) return math.abs((GetEntityHeading(veh) - h + 180.0) % 360.0 - 180.0) end

-- The automatic pull-over stands down when the stop ends, or the officer takes over with the mode key.
local function gone(s) return Stop ~= s or s.manual end

-- The car and everyone in it on this officer's game for the length of the stop. -> false: can't, called off
local function claim(s)
    if not ((s.foot or control(s.veh)) and (not s.ped or control(s.ped))) then
        log('cancelled: no network control of the car or driver')
        TriggerServerEvent('c3r:stop:act', 'cancel')
        return false
    end
    if not s.foot then
        SetEntityAsMissionEntity(s.veh, true, true)
        SetNetworkIdCanMigrate(s.veh_net, false) -- keep them on this officer's game while they're stopped
    end
    for net, o in pairs(s.occ) do
        if control(o.ped) then
            SetEntityAsMissionEntity(o.ped, true, true)
            SetNetworkIdCanMigrate(net, false)
            SetBlockingOfNonTemporaryEvents(o.ped, true)
            SetPedKeepTask(o.ped, true)
        end
    end
    return true
end

local function pull_over(s)
    if not claim(s) or gone(s) then return end -- or called off while we waited for control
    Wait(s.hint.slow and 2500 or 800) -- noticing the lights takes a moment (longer when drunk)
    -- Mid-turn at a junction? They finish the turn first and pull over on the road they end up on: a spot
    -- picked from a diagonal heading lands on the corner. (They're still on their own driving task here.)
    wait_until(5000, function()
        return gone(s) or along_road(GetEntityCoords(s.veh), GetEntityHeading(s.veh))
    end)
    if gone(s) then return end
    SetVehicleIndicatorLights(s.veh, 0, true) -- right
    -- Brake down to pulling-over speed first: the straight-line driving below doesn't brake on its own,
    -- and from highway speed a car would coast a long way past its spot.
    wait_until(8000, function()
        if gone(s) or GetEntitySpeed(s.veh) <= Config.Pullover.speed + 2.0 then return true end
        TaskVehicleTempAction(s.ped, s.veh, 1, 400)
        return false
    end)
    if gone(s) then return end
    local model, style = GetEntityModel(s.veh), Config.Pullover.driving_style
    -- far enough ahead to slow down in: about 3 s of travel at their speed, never less than Config's
    local min_dist = math.max(15.0, GetEntitySpeed(s.veh) * 2.5)
    local spot, road_h, final = kerb_point(s.veh, math.max(Config.Pullover.ahead, GetEntitySpeed(s.veh) * 3.0), min_dist)
    if gone(s) then return end
    local r = math.rad(road_h)
    local right = vector3(math.cos(r), math.sin(r), 0.0)
    -- Two points, the way a driver does it: in towards the kerb but not onto it, then a slow glide along it
    -- onto the final spot. Steering straight at the kerb ends nose-in, with the front wheel against it.
    local approach = spot - right * Config.Pullover.glide
    -- On a bend a straight line cuts the inside corner over the pavement: follow the road there instead.
    local bend = angle_off(s.veh, road_h) > 15.0
    if bend then
        style = Config.Pullover.bend_style
        log('on a bend: following the road to the spot')
    end
    TaskVehicleDriveToCoord(s.ped, s.veh, approach.x, approach.y, approach.z, Config.Pullover.speed, 0, model, style,
        1.5, true)
    -- there, or stopped close to it (the AI gave up on the exact point). Stopped far from it means stuck
    -- behind traffic: keep waiting, up to the timeout.
    -- Never let them wander off: more than 25 m past the planned stop and they just brake where they are.
    local origin, limit = GetEntityCoords(s.veh), #(final - GetEntityCoords(s.veh)) + 25.0
    local function strayed() return #(GetEntityCoords(s.veh) - origin) > limit end
    local started, still_since = GetGameTimer(), nil
    wait_until(Config.Pullover.timeout_ms, function()
        local moving = GetEntitySpeed(s.veh) > 0.5 or GetGameTimer() - started < 3000
        still_since = not moving and (still_since or GetGameTimer()) or nil
        local d = #(GetEntityCoords(s.veh) - approach)
        return gone(s) or strayed() or d < 3.0 or (d < 8.0 and still_since and GetGameTimer() - still_since > 1000)
    end)
    if gone(s) then return end
    log('at the approach point after %.1f s, %.1f m off it', (GetGameTimer() - started) / 1000,
        #(GetEntityCoords(s.veh) - approach))
    local to_final = final - GetEntityCoords(s.veh)
    local car_fwd = GetEntityForwardVector(s.veh)
    if strayed() then
        log('strayed past the stop: braking where they are')
    elseif to_final.x * car_fwd.x + to_final.y * car_fwd.y < 1.0 then
        log('final point is behind them: just stopping') -- going back for it would mean turning round
    else
        TaskVehicleDriveToCoord(s.ped, s.veh, final.x, final.y, final.z, 3.0, 0, model, style, 1.0, true)
        wait_until(7000, function()
            return gone(s) or strayed() or #(GetEntityCoords(s.veh) - final) < 1.5
                or (angle_off(s.veh, road_h) < 4.0 and #(GetEntityCoords(s.veh) - final) < 4.0)
        end)
    end
    if gone(s) then return end
    log('stopped, %.0f deg off the road', angle_off(s.veh, road_h))
    hold(s)
    Wait(1500)
    if gone(s) then return end -- ended meanwhile: drive_off has already made the car driveable again
    SetVehicleIndicatorLights(s.veh, 0, false)
    SetVehicleUndriveable(s.veh, true) -- nothing drives it off mid-stop, whoever ends up owning it
    s.stopped = true
end

-- While stopped: stay stopped, wind the windows down and look round when the officer walks up, and call
-- the stop off when it can't go on.
local function watch(s)
    local windows = false
    while Stop == s do
        local me = PlayerPedId()
        local car = DoesEntityExist(s.veh)
        -- (a towed car is gone on purpose; a driver booked into a station is too, and that ends it)
        if (not car and not s.towed and not s.foot) or (s.ped and (not DoesEntityExist(s.ped) or IsEntityDead(s.ped)))
            or (s.empty and not car) then
            log('cancelled: the car or driver is gone')
            TriggerServerEvent('c3r:stop:act', 'cancel')
            return
        end
        local chasing = s.pursuit -- (or walking someone by the cuffs: they're with the officer, wherever that is)
        for _, o in pairs(s.occ) do
            -- (a prisoner the transport took is no longer the officer's to walk)
            chasing = chasing or o.fleeing or (o.escorted and not o.transported and DoesEntityExist(o.ped))
        end
        local d = #(GetEntityCoords(me) - GetEntityCoords(((car and not s.towed) or not s.ped) and s.veh or s.ped))
        if Casual(s) and d > 25.0 then -- walked off from a chat: that's it, they go about their day
            log('walked away from the contact')
            TriggerServerEvent('c3r:stop:act', 'cancel')
            return
        end
        if d > Config.CancelDistance and not chasing then -- a chase has its own "got away"
            log('cancelled: %.0f m away', d)
            TriggerServerEvent('c3r:stop:act', 'cancel')
            return
        end
        -- Tasks only stick on the entity's owner: if ownership slipped to another game, take it back, and
        -- then put back what that game didn't keep (no migrating, and undriveable once stopped).
        if (s.ped and not NetworkHasControlOfEntity(s.ped)) or (car and not NetworkHasControlOfEntity(s.veh)) then
            if not s.lost then log('lost control of the car or driver: taking it back') end
            s.lost = true
            if s.ped then NetworkRequestControlOfEntity(s.ped) end
            if car then NetworkRequestControlOfEntity(s.veh) end
        elseif s.lost then
            s.lost = false
            if car then SetNetworkIdCanMigrate(s.veh_net, false) end
            for net in pairs(s.occ) do SetNetworkIdCanMigrate(net, false) end
            if s.stopped and car then SetVehicleUndriveable(s.veh, true) end
        end
        if s.ped and s.stopped and not s.mode and IsPedInVehicle(s.ped, s.veh, false) then
            if GetEntitySpeed(s.veh) > 1.5 then hold(s) end
            if not windows and d < 6.0 and not IsPedInAnyVehicle(me, false) then
                for _, o in pairs(s.occ) do
                    if IsPedInVehicle(o.ped, s.veh, false) then
                        RollDownWindow(s.veh, o.seat + 1) -- windows 0-3 go with seats -1..2
                        TaskLookAtEntity(o.ped, me, -1, 2048, 3)
                    end
                end
                windows = true
            end
        end
        Wait(500)
    end
end

-- The officer's stop as other resources may see it: nil when there's none. ped_net = the driver.
exports('getStop', function()
    local s = Stop
    if not s then return nil end
    local people = {}
    for net, o in pairs(s.occ) do people[#people + 1] = { net = net, seat = o.seat, role = o.role, out = o.out == true } end
    return { veh_net = s.veh_net, ped_net = s.ped_net, stopped = s.stopped == true, mode = s.mode, people = people }
end)

local pursuit, body -- the chase and their body language, further down with what the people in the car do

-- Only chatting: someone on foot, or in a parked car, walked up to; nobody in cuffs or being walked. Walking off,
-- or going to talk to someone else, ends it (menu.lua).
function Casual(s)
    if not s or s.felony or s.pursuit or not (s.foot or s.parked) then return false end
    for _, o in pairs(s.occ) do
        if o.cuffed or o.escorted then return false end
    end
    return true
end

-- Walked up to a car standing still: it stays put (no pull-over), and the menu opens on whoever they came to.
local function park(s)
    if not claim(s) or Stop ~= s then return end
    hold(s)
    SetVehicleUndriveable(s.veh, true)
    s.stopped = true
    if s.hint.contact then OpenMenuFor(s.hint.contact) end
    if queued then
        local action = queued
        queued = nil
        VehicleAction(s, action)
    end
end

-- Someone on foot: they stop where they are and face the officer, and the menu opens on them.
local function start_foot(people, hint, categories)
    local p = type(people) == 'table' and people[1]
    local ped = p and NetToPed(p.net) or 0
    if not DoesEntityExist(ped) then return TriggerServerEvent('c3r:stop:act', 'cancel') end
    local o = { net = p.net, ped = ped, role = 'pedestrian', look = p.look, out = true }
    local s = { foot = true, veh = 0, ped = ped, ped_net = p.net, hint = hint, categories = categories or {},
                occ = { [p.net] = o }, stopped = true }
    Stop = s
    ClearPrompt('target')
    CreateThread(function()
        if not claim(s) or Stop ~= s then return end
        TriggerEvent('c3r:stop:task', 'stay', p.net)
        OpenMenuFor(p.net)
    end)
    CreateThread(function() watch(s) end)
    CreateThread(function() body(s) end)
end

-- people: { { net, seat, role, look } } from the server (the driver among them)
RegisterNetEvent('c3r:stop:started', function(veh_net, people, hint, categories)
    asking = false
    if type(hint) == 'table' and hint.foot then return start_foot(people, hint, categories) end
    local veh = NetToVeh(veh_net)
    if not DoesEntityExist(veh) then return TriggerServerEvent('c3r:stop:act', 'cancel') end
    local s = { veh = veh, veh_net = veh_net, hint = hint or {}, categories = categories or {}, occ = {} }
    for _, p in ipairs(type(people) == 'table' and people or {}) do
        local ped = NetToPed(p.net)
        if DoesEntityExist(ped) then
            s.occ[p.net] = { net = p.net, ped = ped, seat = p.seat, role = p.role, look = p.look, out = false }
            if p.seat == -1 then s.ped, s.ped_net = ped, p.net end
        end
    end
    if not s.ped and not s.hint.empty then return TriggerServerEvent('c3r:stop:act', 'cancel') end
    s.empty = s.hint.empty
    Stop = s
    ClearPrompt('target')
    s.parked = s.hint.parked
    if not s.parked then
        Prompt('stop', 'info', 'Traffic stop',
            ('The driver is pulling over. Tap %s to change what they do.'):format(KeyName('+c3r_mode', 'U')), 9000)
    end
    CreateThread(function()
        if s.hint.flee then pursuit(s) elseif s.parked then park(s) else pull_over(s) end
    end)
    CreateThread(function() watch(s) end)
    CreateThread(function() body(s) end)
end)

-- ─── what the people in the car do ────────────────────────────────────────────

local TASKS = {}

-- Only the newest task for someone, on a live stop, may carry on after a wait: a newer task for them, or
-- the stop ending (and drive_off taking over), makes an older one stop where it is.
local function current(s, o, mine) return Stop == s and o.task == mine end

-- Where people stand once out: the back corner on the kerb side, then beside and behind it.
local STAND = { { 1.6, -3.4 }, { 2.7, -3.4 }, { 1.6, -4.6 }, { 2.7, -4.6 } }

local function stand_spot(s, o)
    for i, xy in ipairs(STAND) do
        local taken = false
        for _, other in pairs(s.occ) do taken = taken or (other ~= o and other.spot == i) end
        if not taken then
            o.spot = i
            return GetOffsetFromEntityInWorldCoords(s.veh, xy[1], xy[2], 0.0)
        end
    end
    return GetOffsetFromEntityInWorldCoords(s.veh, 2.0, -5.5, 0.0)
end

-- Standing where they are, facing the officer (hands still up, if they were told to), until told otherwise.
-- The spot is kept: GTA hands an idle ped back to wandering as soon as its task ends (a talking gesture
-- ends it), so the body language loop below brings them back to it.
local function rest(o)
    if o.felony then return end -- held in a felony pose: facing away, or on their knees
    local me = PlayerPedId()
    if o.doing == 'handsup' then TaskHandsUp(o.ped, -1, me, -1, false) else TaskTurnPedToFaceEntity(o.ped, me, -1) end
end
local function stand(o)
    o.anchor, o.returning = GetEntityCoords(o.ped), nil
    rest(o)
end

-- Out of the car, then stand behind it on the kerb side, facing the officer. Someone standing in the
-- door's way (the officer, often) can stop them: try again, then let them squeeze out.
function TASKS.exit(s, o, mine)
    o.out = true
    ClearPedTasks(o.ped)
    local out = false
    for _, flag in ipairs({ 256, 0, 16 }) do -- door left open; normal; teleport out
        TaskLeaveVehicle(o.ped, s.veh, flag)
        out = wait_until(flag == 16 and 2000 or 6000, function() return not IsPedInAnyVehicle(o.ped, false) end)
        if out or not current(s, o, mine) then break end
        log('%s could not get out (flag %d), trying again', o.role, flag)
    end
    if not current(s, o, mine) then return end
    if not out then o.out = false return end
    local spot = stand_spot(s, o)
    TaskGoStraightToCoord(o.ped, spot.x, spot.y, spot.z, 1.0, 8000, GetEntityHeading(s.veh) + 180.0, 0.5)
    wait_until(8000, function() return not current(s, o, mine) or #(GetEntityCoords(o.ped) - spot) < 1.0 end)
    if current(s, o, mine) then stand(o) end
end

function TASKS.back(s, o, mine)
    o.out, o.spot, o.following = false, nil, false
    TaskEnterVehicle(o.ped, s.veh, 15000, o.seat, 1.0, 1, 0)
    wait_until(16000, function() return not current(s, o, mine) or IsPedInVehicle(o.ped, s.veh, false) end)
    if current(s, o, mine) and o.seat == -1 and IsPedInVehicle(o.ped, s.veh, false) then hold(s) end
end

function TASKS.follow(s, o)
    if IsPedInAnyVehicle(o.ped, false) then return end
    o.following = true
    TaskFollowToOffsetOfEntity(o.ped, PlayerPedId(), 0.0, -1.3, 0.0, 1.0, -1, 1.5, true)
end

function TASKS.stay(s, o)
    if IsPedInAnyVehicle(o.ped, false) then return end
    o.following = false
    ClearPedTasks(o.ped)
    stand(o)
end

function TASKS.handsup(s, o)
    if o.felony then return end -- already hands up (and maybe on their knees): leave them be
    o.following = false
    if IsPedInAnyVehicle(o.ped, false) then return TaskHandsUp(o.ped, -1, PlayerPedId(), -1, false) end
    stand(o)
end

-- ─── searches, tests, arrests ─────────────────────────────────────────────────

local function cuffed_idle(ped)
    if load_dict('mp_arresting') then TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0.0, false, false, false) end
end

-- Sat on the ground, the cuffed idle on top (upper body) so the hands stay behind the back.
local SIT = { 'amb@world_human_picnic@male@base', 'base' } -- UNVERIFIED: the picnic scenario's sitting loop
local function sit_down(ped)
    if not load_dict(SIT[1]) then return end
    TaskPlayAnim(ped, SIT[1], SIT[2], 4.0, -4.0, -1, 1, 0.0, false, false, false)
    cuffed_idle(ped)
end

-- Stood still and facing the officer once a task is done with them.
local function settle(s, o, mine)
    if not current(s, o, mine) then return end
    o.doing = 'stay'
    stand(o)
end

-- The pat-down: they stand an arm's length in front of the officer, back turned, and are searched.
-- (custom@police / custom@suspect, streamed from stream/: a free pair from the FiveM forum.)
local FRISK_GAP = 0.7 -- m in front of the officer they stand; tune if the hands miss
function TASKS.frisk(s, o, mine)
    if IsPedInAnyVehicle(o.ped, false) or not load_dict('custom@police') then return end
    local me = PlayerPedId()
    o.following = false
    if o.escorted then DetachEntity(o.ped, true, false) o.escorted = false end
    local spot = GetOffsetFromEntityInWorldCoords(me, 0.0, FRISK_GAP, 0.0)
    ClearPedTasks(o.ped)
    SetEntityCoordsNoOffset(o.ped, spot.x, spot.y, GetEntityCoords(o.ped).z, false, false, false)
    SetEntityHeading(o.ped, GetEntityHeading(me))
    local ms = math.floor(GetAnimDuration('custom@police', 'police') * 1000)
    if ms <= 0 then ms = 6000 end
    if o.cuffed then
        cuffed_idle(o.ped)
    elseif load_dict('custom@suspect') then
        TaskPlayAnim(o.ped, 'custom@suspect', 'suspect', 8.0, -8.0, ms, 1, 0.0, false, false, false)
    end
    TaskPlayAnim(me, 'custom@police', 'police', 8.0, -8.0, ms, 0, 0.0, false, false, false)
    Wait(ms)
    if o.cuffed then
        if current(s, o, mine) then o.anchor = GetEntityCoords(o.ped) end
    else
        StopAnimTask(o.ped, 'custom@suspect', 'suspect', 1.0)
        settle(s, o, mine)
    end
end

-- the officer's own: the nearest door open, a look through it, the door shut
local DOORS = { { 'door_dside_f', 0 }, { 'door_pside_f', 1 }, { 'door_dside_r', 2 }, { 'door_pside_r', 3 }, { 'boot', 5 } }
local OFFICER_TASKS = { search_car = true }
function TASKS.search_car(s)
    local me = PlayerPedId()
    if not DoesEntityExist(s.veh) or IsPedInAnyVehicle(me, false) then return end
    local pos, door, best = GetEntityCoords(me), nil, nil
    for _, d in ipairs(DOORS) do
        local bone = GetEntityBoneIndexByName(s.veh, d[1])
        local dd = bone ~= -1 and #(GetWorldPositionOfEntityBone(s.veh, bone) - pos)
        if dd and (not best or dd < best) then door, best = d[2], dd end
    end
    if door and control(s.veh) then SetVehicleDoorOpen(s.veh, door, false, false) end
    TaskStartScenarioInPlace(me, 'PROP_HUMAN_BUM_BIN', 0, true)
    Wait(8000)
    ClearPedTasks(me)
    if door and DoesEntityExist(s.veh) then SetVehicleDoorShut(s.veh, door, false) end
end

-- The walk-and-turn: four metres out along the kerb and back, staggering if they're impaired.
local WALKS = { drunk = 'move_m@drunk@moderatedrunk', high = 'move_m@drunk@slightlydrunk' }
function TASKS.sobriety(s, o, mine, arg)
    if IsPedInAnyVehicle(o.ped, false) then return end
    o.following = false
    local impaired = type(arg) == 'table' and arg.impaired
    if impaired then walk_style(o.ped, 'move_m@drunk@verydrunk') end
    local start = GetEntityCoords(o.ped)
    local fwd = GetEntityForwardVector(DoesEntityExist(s.veh) and s.veh or o.ped)
    local to = start - fwd * 4.0
    for _, p in ipairs({ to, start }) do
        TaskGoStraightToCoord(o.ped, p.x, p.y, p.z, 1.0, 8000, 0.0, 0.2)
        wait_until(8000, function() return not current(s, o, mine) or #(GetEntityCoords(o.ped) - p) < 0.6 end)
        if not current(s, o, mine) then break end
    end
    if WALKS[o.look] then walk_style(o.ped, WALKS[o.look]) else ResetPedMovementClipset(o.ped, 0.0) end
    settle(s, o, mine)
end

function TASKS.cuff(s, o, mine)
    if IsPedInAnyVehicle(o.ped, false) or not load_dict('mp_arrest_paired') then return end
    local me = PlayerPedId()
    o.following = false
    ClearPedTasks(o.ped)
    -- the cuffing, as one move: they're held in front of the officer, back turned, for the length of it
    AttachEntityToEntity(o.ped, me, 11816, -0.1, 0.45, 0.0, 0.0, 0.0, 20.0, false, false, false, false, 20, false)
    TaskPlayAnim(o.ped, 'mp_arrest_paired', 'crook_p2_back_left', 8.0, -8.0, 3750, 2, 0.0, false, false, false)
    TaskPlayAnim(me, 'mp_arrest_paired', 'cop_p2_back_left', 8.0, -8.0, 3750, 48, 0.0, false, false, false)
    Wait(3760)
    DetachEntity(o.ped, true, false)
    o.cuffed = true
    SetEnableHandcuffs(o.ped, true) -- lwk_npcai reads this: cuffed people don't run or drive off
    o.anchor = GetEntityCoords(o.ped)
    cuffed_idle(o.ped)
end

function TASKS.uncuff(s, o, mine)
    if o.seated then return end
    if o.escorted then DetachEntity(o.ped, true, false) end
    o.escorted = false
    if load_dict('mp_arresting') then
        TaskPlayAnim(PlayerPedId(), 'mp_arresting', 'a_uncuff', 8.0, -8.0, 4000, 48, 0.0, false, false, false)
    end
    Wait(4000)
    o.cuffed = false
    SetEnableHandcuffs(o.ped, false)
    StopAnimTask(o.ped, 'mp_arresting', 'idle', 1.0)
    settle(s, o, mine)
end

-- Walked in front of the officer, back turned, held by the cuffs (or let go of again). ESCORT: where they're
-- held, m right / ahead of the officer: where the uncuffing move expects them, so the hands meet their wrists.
local ESCORT = { 0.0, 0.55 }
function TASKS.escort(s, o)
    if not o.cuffed or IsPedInAnyVehicle(o.ped, false) then return end
    o.escorted = not o.escorted
    if o.escorted then
        AttachEntityToEntity(o.ped, PlayerPedId(), 11816, ESCORT[1], ESCORT[2], 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        cuffed_idle(o.ped) -- hands behind the back again: attaching can drop it
        Prompt('custody', 'info', 'Escorting', 'Walk them into the blue circle at a police station to book them, or put them in your car.', 7000)
    else
        DetachEntity(o.ped, true, false)
        o.anchor = GetEntityCoords(o.ped) -- let go of: they stand where they were left
    end
end

-- While escorting: both hands on their cuffed wrists. That's the officer's half of taking cuffs off (played
-- alone, standing behind a cuffed person), frozen while the hands are at the wrists, on the upper body only
-- so walking carries on. Put back after a gesture; dropped once nobody is held. HOLD[3] is that moment
-- (0-1 through the move): tune it if the hands land short of or past the wrists.
local HOLD = { 'mp_arresting', 'a_uncuff', .3 }
CreateThread(function()
    local holding = false
    while true do
        local escorting = false
        for _, o in pairs(Stop and Stop.occ or {}) do escorting = escorting or (o.escorted and DoesEntityExist(o.ped)) end
        local me = PlayerPedId()
        if escorting and not IsEntityPlayingAnim(me, HOLD[1], HOLD[2], 3) and load_dict(HOLD[1]) then
            TaskPlayAnim(me, HOLD[1], HOLD[2], 8.0, -8.0, -1, 49, HOLD[3], false, false, false)
            Wait(0)
            SetEntityAnimCurrentTime(me, HOLD[1], HOLD[2], HOLD[3])
            SetEntityAnimSpeed(me, HOLD[1], HOLD[2], 0.0)
        elseif not escorting and holding then
            StopAnimTask(me, HOLD[1], HOLD[2], 1.0)
        end
        holding = escorting
        Wait(escorting and 250 or 750)
    end
end)

local function nearest_station(p)
    local best, best_d
    for _, st in ipairs(Config.Stations) do
        local d = #(vector3(st.x, st.y, st.z) - p)
        if not best_d or d < best_d then best, best_d = st, d end
    end
    return best, best_d
end

-- Into the back of the officer's car (the last one they drove, parked close by). From there they're the
-- officer's until booked at a station, whether or not the stop is still going.
function TASKS.seat(s, o)
    local me = PlayerPedId()
    local car = GetVehiclePedIsIn(me, true)
    if car == 0 or car == s.veh or #(GetEntityCoords(car) - GetEntityCoords(me)) > 15.0 then car = nil end
    local seat = car and ((IsVehicleSeatFree(car, 1) and 1) or (IsVehicleSeatFree(car, 2) and 2))
    if not seat then
        return Prompt('mode', 'info', 'No room', 'Park your patrol car close by, with a free back seat.', 4000)
    end
    if o.escorted then DetachEntity(o.ped, true, false) end
    o.escorted = false
    TaskWarpPedIntoVehicle(o.ped, car, seat) -- a warp: walking them there drops the cuffs
    o.seated, Custody[o.net] = car, { ped = o.ped, car = car }
    local st = nearest_station(GetEntityCoords(car))
    if st then SetNewWaypoint(st.x, st.y) end
    Prompt('custody', 'info', 'Prisoner in custody',
        ('Drive to a police station and stop in the blue circle to book them in. Waypoint set: %s.'):format(st and st.name or 'none'), 9000)
end

function TASKS.sit(s, o)
    if not o.cuffed or IsPedInAnyVehicle(o.ped, false) then return end
    if o.escorted then DetachEntity(o.ped, true, false) end
    o.escorted, o.sitting = false, true
    ClearPedTasks(o.ped)
    o.anchor = GetEntityCoords(o.ped)
    sit_down(o.ped)
end

function TASKS.getup(s, o)
    o.anchor = GetEntityCoords(o.ped) -- (run_task has already stood them up)
    cuffed_idle(o.ped)
end

function TASKS.unseat(s, o, mine)
    local car = o.seated
    o.seated, Custody[o.net] = nil, nil
    if car and IsPedInVehicle(o.ped, car, false) then
        TaskLeaveVehicle(o.ped, car, 16)
        wait_until(3000, function() return not IsPedInAnyVehicle(o.ped, false) end)
    end
    if current(s, o, mine) then
        o.anchor = GetEntityCoords(o.ped)
        cuffed_idle(o.ped)
    end
end

-- Whoever the officer is walking by the cuffs right now.
local function escorting()
    local out = {}
    for _, o in pairs(Stop and Stop.occ or {}) do
        if o.escorted and DoesEntityExist(o.ped) then out[#out + 1] = o end
    end
    return out
end

-- The station whose blue circle p is in, if any.
local function in_circle(p)
    local st = nearest_station(p)
    return st and #(vector2(st.x, st.y) - vector2(p.x, p.y)) < Config.BookingRadius and st or nil
end

local function book(ped, st)
    NetworkFadeOutEntity(ped, false, true)
    SetTimeout(1500, function() if DoesEntityExist(ped) then DeleteEntity(ped) end end)
    Prompt('custody', 'ok', 'Prisoner booked', ('Booked into %s.'):format(st.name), 6000)
end

-- Booked: stopped in a station's blue circle with them in the back, or walked into it with them by the cuffs.
CreateThread(function()
    while true do
        local walking = escorting()
        if next(Custody) or #walking > 0 then
            local me = PlayerPedId()
            local car = GetVehiclePedIsIn(me, false)
            for net, c in pairs(Custody) do
                if not DoesEntityExist(c.ped) or IsEntityDead(c.ped) or not IsPedInVehicle(c.ped, c.car, false) then
                    Custody[net] = nil
                elseif car == c.car and GetEntitySpeed(car) < 1.0 then
                    local st = in_circle(GetEntityCoords(car))
                    if st and control(c.ped) then
                        Custody[net] = nil
                        book(c.ped, st)
                    end
                end
            end
            local st = car == 0 and in_circle(GetEntityCoords(me))
            for _, o in ipairs(st and walking or {}) do
                if control(o.ped) then
                    DetachEntity(o.ped, true, false)
                    o.escorted = false -- still cuffed: the stop ends as an arrest
                    book(o.ped, st)
                end
            end
            Wait(500)
        else
            Wait(2000)
        end
    end
end)

-- Where to stop: a blue circle on the ground at each station near you, while someone's in the back or
-- being walked by the cuffs.
CreateThread(function()
    local ground = {} -- [station] = z of the ground there, found once
    while true do
        local near = false
        if next(Custody) or #escorting() > 0 then
            local me = GetEntityCoords(PlayerPedId())
            for _, st in ipairs(Config.Stations) do
                if #(vector2(st.x, st.y) - vector2(me.x, me.y)) < 150.0 then
                    near = true
                    if not ground[st] then
                        local ok, z = GetGroundZFor_3dCoord(st.x, st.y, st.z + 2.0, false)
                        ground[st] = ok and z or st.z - 1.0
                    end
                    local size = Config.BookingRadius * 2
                    DrawMarker(1, st.x, st.y, ground[st] - 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, 1.0,
                        40, 120, 255, 110, false, false, 2, false, nil, nil, false)
                end
            end
        end
        Wait(near and 0 or 1000)
    end
end)

-- ─── felony stop ──────────────────────────────────────────────────────────────
-- Out with hands up and their back to the officer, walked backwards toward them, then on their knees. The poses
-- hold (the body language loop puts them back) until another task, the cuffs say, takes over.

-- [step] = { dict, clip, flag }: hands up (upper body, so they can walk), and kneeling with hands on the head
FELONY_POSE = {
    out = { 'missminuteman_1ig_2', 'handsup_base', 49 },
    back = { 'missminuteman_1ig_2', 'handsup_base', 49 },
    kneel = { 'random@arrests@busted', 'idle_a', 1 },
}

function DropFelonyPose(o)
    local p = FELONY_POSE[o.felony]
    o.felony, o.moving = nil, false
    if p and DoesEntityExist(o.ped) then StopAnimTask(o.ped, p[1], p[2], 2.0) end
end

local function face_away(ped)
    local me, p = GetEntityCoords(PlayerPedId()), GetEntityCoords(ped)
    SetEntityHeading(ped, GetHeadingFromVector_2d(p.x - me.x, p.y - me.y))
end

-- moving: hands up while a walk task runs (standing still would replace the walk)
local function pose(o, step, moving)
    o.felony = step
    if step ~= 'kneel' and not moving then TaskStandStill(o.ped, -1) end -- (an idle ped wanders: this one stays put)
    local p = FELONY_POSE[step]
    if load_dict(p[1]) then TaskPlayAnim(o.ped, p[1], p[2], 4.0, -4.0, -1, p[3], 0.0, false, false, false) end
end

function TASKS.fel_out(s, o, mine)
    o.out, o.following, o.anchor = true, false, nil
    ClearPedTasks(o.ped)
    if IsPedInAnyVehicle(o.ped, false) then
        for _, flag in ipairs({ 256, 0, 16 }) do -- door left open; normal; teleport out
            TaskLeaveVehicle(o.ped, s.veh, flag)
            if wait_until(flag == 16 and 2000 or 6000, function() return not IsPedInAnyVehicle(o.ped, false) end)
                or not current(s, o, mine) then break end
        end
    end
    if not current(s, o, mine) or IsPedInAnyVehicle(o.ped, false) then return end
    Wait(300)
    face_away(o.ped)
    pose(o, 'out')
end

-- Backwards toward the officer: a strafing walk that keeps them facing the car. If that doesn't move them
-- (it isn't meant for the unarmed), they walk there and turn their back again. They stop a few metres short,
-- to one side of the line between the cars.
function TASKS.fel_back(s, o, mine)
    if IsPedInAnyVehicle(o.ped, false) then return end
    local me, car = GetEntityCoords(PlayerPedId()), DoesEntityExist(s.veh) and GetEntityCoords(s.veh) or GetEntityCoords(o.ped)
    local dir = vector3(me.x - car.x, me.y - car.y, 0.0)
    local len = #dir
    if len < 5.0 then return pose(o, 'back') end -- already close: just stay put
    dir = dir / len
    local side = vector3(-dir.y, dir.x, 0.0)
    local to = me - dir * 4.0 + side * 1.5
    local start = GetEntityCoords(o.ped)
    o.moving = true
    TaskGoToCoordWhileAimingAtCoord(o.ped, to.x, to.y, to.z, car.x, car.y, car.z, 1.0, false, 0.5, 4.0, true, 0, false, 0)
    pose(o, 'back', true)
    Wait(1500)
    if current(s, o, mine) and #(GetEntityCoords(o.ped) - start) < 0.3 then
        TaskGoStraightToCoord(o.ped, to.x, to.y, to.z, 1.0, math.floor(len + 6) * 1000, 0.0, 0.5)
        pose(o, 'back', true)
    end
    wait_until(math.floor(len + 8) * 1000, function() return not current(s, o, mine) or #(GetEntityCoords(o.ped) - to) < 1.0 end)
    o.moving = false
    if not current(s, o, mine) then return end
    ClearPedTasks(o.ped)
    face_away(o.ped)
    pose(o, 'back')
end

function TASKS.fel_kneel(s, o, mine)
    if IsPedInAnyVehicle(o.ped, false) or not load_dict('random@arrests@busted') then return end
    ClearPedTasks(o.ped)
    face_away(o.ped)
    o.felony, o.moving = 'kneel', true
    TaskPlayAnim(o.ped, 'random@arrests@busted', 'enter', 4.0, -4.0, -1, 2, 0.0, false, false, false)
    Wait(math.max(500, math.floor(GetAnimDuration('random@arrests@busted', 'enter') * 1000) - 100))
    o.moving = false
    if current(s, o, mine) then pose(o, 'kneel') end
end

-- The server started one: no casual chat, and the engine goes off.
RegisterNetEvent('c3r:felony', function(after_chase)
    local s = Stop
    if not s then return end
    s.felony = true
    CreateThread(function()
        if DoesEntityExist(s.veh) and control(s.veh) then SetVehicleEngineOn(s.veh, false, true, true) end
    end)
    Prompt('stop', 'alert', after_chase and 'They gave up: felony stop' or 'Felony stop',
        ('From cover, one at a time: hold %s (PA) and say "walk backwards toward me", "get on your knees", '
        .. '"passenger, step out of the vehicle". Or hold %s. Then walk up and cuff them.'):format(PaKeyName(), KeyName('+c3r_radial', 'G')), 14000)
end)

-- ─── running ──────────────────────────────────────────────────────────────────

function DropChaseBlip(s)
    if s.blip and DoesBlipExist(s.blip) then RemoveBlip(s.blip) end
    s.blip = nil
end

local function give_up(s, o)
    o.fleeing, o.doing, o.out, o.following, o.anchor = false, 'fel_out', true, false, nil
    ClearPedTasks(o.ped)
    if not s.foot then -- the stop turns into a felony stop (the server's too): hands up, back to the officer
        s.felony = true
        face_away(o.ped)
        pose(o, 'out')
    else
        stand(o)
    end
    TriggerServerEvent('c3r:stop:pursuit', 'caught', o.net)
end

-- They give up when the officer catches up (or tases them); far enough ahead for 10 s, they got away.
local function since(t, yes) return yes and (t or GetGameTimer()) or nil end
local function chase(s, o, mine)
    local near, far
    while current(s, o, mine) do
        if IsEntityDead(o.ped) then return end
        if IsPedRagdoll(o.ped) or IsPedBeingStunned(o.ped, 0) then -- tased or tackled: up again, they're done
            wait_until(8000, function() return not IsPedRagdoll(o.ped) and not IsPedBeingStunned(o.ped, 0) end)
            break
        end
        local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(o.ped))
        local tailed = BackupOnTarget and BackupOnTarget(GetEntityCoords(o.ped), Config.Flee.lose_distance)
        near, far = since(near, d < Config.Flee.catch_distance), since(far, d > Config.Flee.lose_distance and not tailed)
        if near and GetGameTimer() - near > 800 then break end
        if far and GetGameTimer() - far > 10000 then
            o.fleeing, o.escaped, s.lost_on_foot = false, true, true
            Prompt('stop', 'info', 'Suspect lost', 'They got away.', 5000)
            return TriggerServerEvent('c3r:stop:pursuit', 'lost', o.net)
        end
        Wait(200)
    end
    if current(s, o, mine) then give_up(s, o) end
end

function TASKS.flee(s, o, mine)
    o.fleeing, o.out, o.following, o.spot = true, true, false, nil
    if o.escorted then DetachEntity(o.ped, true, false) o.escorted = false end
    if IsPedInAnyVehicle(o.ped, false) then
        TaskLeaveVehicle(o.ped, GetVehiclePedIsIn(o.ped, false), 256)
        wait_until(4000, function() return not IsPedInAnyVehicle(o.ped, false) end)
    end
    if not current(s, o, mine) then return end
    TaskSmartFleePed(o.ped, PlayerPedId(), 1000.0, -1, false, false)
    Prompt('stop', 'alert', 'Foot pursuit', 'They ran! Catch up with them, or tase them.', 6000)
    chase(s, o, mine)
end

function TASKS.surrender(s, o, mine)
    if IsPedInAnyVehicle(o.ped, false) then
        TaskLeaveVehicle(o.ped, GetVehiclePedIsIn(o.ped, false), 256)
        wait_until(5000, function() return not IsPedInAnyVehicle(o.ped, false) end)
    end
    if current(s, o, mine) then give_up(s, o) end
end

-- net = whose task it is; arg = what it needs to know (the sobriety test: { impaired })
local function run_task(name, net, arg)
    local s, run = Stop, TASKS[name]
    local o = s and s.occ[net]
    if not s or not run then return end
    if OFFICER_TASKS[name] then return CreateThread(function() run(s, o) end) end -- it's the officer doing it
    if not o then return end
    local mine = {}
    if o.felony and name:sub(1, 4) ~= 'fel_' and name ~= 'handsup' then DropFelonyPose(o) end
    if o.sitting and name ~= 'sit' then -- any other order: up off the ground first
        o.sitting = false
        StopAnimTask(o.ped, SIT[1], SIT[2], 2.0)
    end
    o.task, o.doing, o.anchor = mine, name, nil
    CreateThread(function()
        if control(o.ped) then run(s, o, mine, arg) else log('task %s: no control of the %s', name, o.role) end
    end)
end
RegisterNetEvent('c3r:stop:task', run_task)

-- Pulled over? No: flat out, through the lights, until they're boxed in, wrecked or stuck. Then they give
-- up, or bail out and run (the server's call). Too far behind for 10 s and they got away.
pursuit = function(s)
    if not claim(s) or Stop ~= s then return end
    s.pursuit = true
    Wait(s.hint.slow and 1500 or 600)
    if Stop ~= s then return end
    SetDriverAbility(s.ped, 1.0)
    SetDriverAggressiveness(s.ped, 1.0)
    TaskVehicleDriveWander(s.ped, s.veh, 40.0, 786468)
    Prompt('stop', 'alert', 'Pursuit', 'They are not stopping! Stay with them.', 8000)
    if not s.blip then -- a flashing red marker on the fleeing car, gone when the chase is
        s.blip = AddBlipForEntity(s.veh)
        SetBlipColour(s.blip, 1)
        SetBlipFlashes(s.blip, true)
        ShowHeadingIndicatorOnBlip(s.blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Fleeing suspect')
        EndTextCommandSetBlipName(s.blip)
    end
    local far, still
    while Stop == s do
        if not DoesEntityExist(s.veh) or not DoesEntityExist(s.ped) or IsEntityDead(s.ped) then return end
        local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(s.veh))
        -- not lost while backup (a pursuit car or the helicopter) is still on them
        local tailed = BackupOnTarget and BackupOnTarget(GetEntityCoords(s.veh), Config.Flee.lose_distance)
        far, still = since(far, d > Config.Flee.lose_distance and not tailed), since(still, GetEntitySpeed(s.veh) < 1.0)
        if far and GetGameTimer() - far > 10000 then
            local driver = s.occ[s.ped_net]
            if driver then driver.escaped = true end
            Prompt('stop', 'info', 'Suspect lost', 'They got away.', 5000)
            return TriggerServerEvent('c3r:stop:pursuit', 'lost', s.ped_net)
        end
        if (still and GetGameTimer() - still > 3000) or GetVehicleEngineHealth(s.veh) < 250.0
            or IsEntityUpsidedown(s.veh) or not IsPedInVehicle(s.ped, s.veh, false) then
            break
        end
        Wait(250)
    end
    DropChaseBlip(s)
    if Stop ~= s then return end
    if control(s.veh) then SetVehicleUndriveable(s.veh, true) end
    s.pursuit, s.stopped = false, true
    run_task(s.hint.bail and 'flee' or 'surrender', s.ped_net)
end

-- A felony stop answered by flooring it: the car is let go of and the chase runs from here.
RegisterNetEvent('c3r:stop:fleeCar', function(bail)
    local s = Stop
    if not s or s.foot or not DoesEntityExist(s.veh) or not s.ped or not IsPedInVehicle(s.ped, s.veh, false) then return end
    s.felony, s.stopped, s.mode, s.manual, s.parked = false, false, nil, false, nil
    s.hint.bail = bail == true
    CreateThread(function()
        if not (control(s.veh) and control(s.ped)) then return end
        SetVehicleUndriveable(s.veh, false)
        SetVehicleEngineOn(s.veh, true, true, false)
        ClearPedTasks(s.ped) -- drop the hold
        pursuit(s)
    end)
end)

-- ─── body language ────────────────────────────────────────────────────────────
-- Out of the car and standing about, they show it: the drunk sway, the nervous fidget, the rude fold their
-- arms. The cuffed keep their hands behind their back.
local LOOKS = {
    nervous = { 'amb@world_human_stand_impatient@male@no_sign@base', 'base' },
    high = { 'amb@world_human_stand_impatient@male@no_sign@base', 'base' },
    rude = { 'amb@world_human_hang_out_street@female_arms_crossed@base', 'base' },
}
body = function(s)
    while Stop == s do
        for _, o in pairs(s.occ) do
            local ped = o.ped
            if DoesEntityExist(ped) and not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false)
                and NetworkHasControlOfEntity(ped) and not o.leaving and not o.transported then
                if o.felony and not o.cuffed and not o.moving then -- a felony pose dropped (a talking gesture): back to it
                    local p = FELONY_POSE[o.felony]
                    if p and not IsEntityPlayingAnim(ped, p[1], p[2], 3) and load_dict(p[1]) then
                        TaskPlayAnim(ped, p[1], p[2], 4.0, -4.0, -1, p[3], 0.0, false, false, false)
                    end
                end
                -- told to stand somewhere: drifted off it, they walk back; started wandering on it, they stop
                if o.anchor and not o.escorted and not o.fleeing and not o.following and not o.felony then
                    local d, now = #(GetEntityCoords(ped) - o.anchor), GetGameTimer()
                    if d > 1.0 and (not o.returning or now > o.returning) then
                        o.returning = now + 6000
                        TaskGoStraightToCoord(ped, o.anchor.x, o.anchor.y, o.anchor.z, 1.0, 6000, GetEntityHeading(ped), 0.3)
                    elseif d <= 1.0 and (o.returning or GetEntitySpeed(ped) > 0.3) then
                        o.returning = nil
                        rest(o)
                    end
                end
                if o.cuffed then
                    if o.sitting and not IsEntityPlayingAnim(ped, SIT[1], SIT[2], 3) then sit_down(ped)
                    elseif not IsEntityPlayingAnim(ped, 'mp_arresting', 'idle', 3) then cuffed_idle(ped) end
                elseif o.out and not o.fleeing and not o.felony then
                    if WALKS[o.look] and not o.walk then
                        o.walk = true
                        walk_style(ped, WALKS[o.look])
                    end
                    local a = LOOKS[o.look]
                    if a and (o.doing == 'exit' or o.doing == 'stay') and not IsEntityPlayingAnim(ped, a[1], a[2], 3)
                        and load_dict(a[1]) then
                        TaskPlayAnim(ped, a[1], a[2], 2.0, -2.0, -1, 49, 0.0, false, false, false)
                    end
                end
            end
        end
        Wait(500)
    end
end

-- ─── what the driver does: the mode key ───────────────────────────────────────
-- The AI pulls over by itself first. If it stops somewhere bad (or the officer wants it elsewhere), the
-- mode key takes over: lead it on, have it follow, steer it by hand, or halt it where it is.

local MODES = {
    { id = 'front', label = 'Follow in front', desc = 'They drive ahead of your car. Lead them to a better spot, then Halt.' },
    { id = 'behind', label = 'Follow behind', desc = 'They follow your car.' },
    { id = 'steer', label = 'Manual steer', desc = 'The arrow keys drive their car.' },
    { id = 'halt', label = 'Halt', desc = 'They stop where they are.' },
    { id = 'cancel', label = 'Stop pullover', desc = 'Let them go. The stop is cancelled.' },
}
local MODE_PROMPT = {
    front = 'The driver is staying in front of you.', behind = 'The driver is following you.',
    steer = 'You are steering their car with the arrow keys.', halt = 'The driver has stopped.',
}

local picking = nil -- index into MODES while the picker is open

local function mode_key() return KeyName('+c3r_mode', 'U') end

-- Brake to a stop where they are, then hold there like a normal stop.
local function halt(s)
    s.mode = nil
    SetEntityMaxSpeed(s.veh, 500.0)
    hold(s)
    wait_until(6000, function() return Stop ~= s or s.mode or GetEntitySpeed(s.veh) < 0.5 end)
    if Stop ~= s or s.mode then return end
    SetVehicleUndriveable(s.veh, true)
    s.stopped = true
end

-- Arrow keys -> a short temp action, renewed while held: up / down drive, left / right steer.
local function steer(s)
    SetEntityMaxSpeed(s.veh, Config.Modes.steer_speed)
    while Stop == s and s.mode == 'steer' do
        for _, c in ipairs({ 172, 173, 174, 175 }) do DisableControlAction(0, c, true) end
        local up, down = IsDisabledControlPressed(0, 172), IsDisabledControlPressed(0, 173)
        local left, right = IsDisabledControlPressed(0, 174), IsDisabledControlPressed(0, 175)
        local action = 1 -- nothing held: brake and wait
        if up then action = left and 7 or right and 8 or 9
        elseif down then action = left and 13 or right and 14 or 22
        elseif left then action = 7
        elseif right then action = 8 end
        TaskVehicleTempAction(s.ped, s.veh, action, 120)
        Wait(0)
    end
    if DoesEntityExist(s.veh) then SetEntityMaxSpeed(s.veh, 500.0) end
end

local function set_mode(s, id)
    if id == 'cancel' then return TriggerServerEvent('c3r:stop:act', 'cancel') end
    CreateThread(function()
        if not (control(s.veh) and control(s.ped)) then return Notify('~b~C~w~3~r~R~s~ Unable: no control of the car.') end
        if not IsPedInVehicle(s.ped, s.veh, false) then
            return Prompt('mode', 'info', 'Driver is out of the car', 'Have them get back in first.', 4000)
        end
        local own = GetVehiclePedIsIn(PlayerPedId(), false)
        if (id == 'front' or id == 'behind') and own == 0 then
            return Prompt('mode', 'info', 'Get in your car', 'They follow your vehicle, so you need to be in it.', 4000)
        end
        s.manual, s.stopped = true, false -- the automatic pull-over stops steering them from here on
        s.mode = id ~= 'halt' and id or nil
        SetVehicleUndriveable(s.veh, false)
        ClearPedTasks(s.ped)
        if id == 'front' then
            SetEntityMaxSpeed(s.veh, 500.0)
            TaskVehicleEscort(s.ped, s.veh, own, 0, Config.Modes.speed, Config.Pullover.bend_style, Config.Modes.gap, 0, 20.0)
        elseif id == 'behind' then
            SetEntityMaxSpeed(s.veh, 500.0)
            TaskVehicleFollow(s.ped, s.veh, own, Config.Modes.speed, Config.Pullover.bend_style, math.floor(Config.Modes.gap))
        elseif id == 'steer' then
            CreateThread(function() steer(s) end)
        else
            halt(s)
        end
        Prompt('stop', 'info', MODE_PROMPT[id], ('Tap %s to change mode.'):format(mode_key()), id == 'halt' and 5000 or nil)
    end)
end

local function close_picker()
    picking = nil
    SendNUIMessage({ type = 'modes', open = false })
end

RegisterCommand('+c3r_mode', function()
    if not Stop or Stop.pursuit or Stop.foot then return end
    if picking then return close_picker() end
    picking = 1 -- Follow in front first
    SendNUIMessage({ type = 'modes', open = true, items = MODES, index = picking, current = Stop.mode or (Stop.stopped and 'halt') })
    CreateThread(function()
        while picking and Stop do
            for _, c in ipairs({ 172, 173, 176, 177, 191, 201 }) do DisableControlAction(0, c, true) end
            if IsDisabledControlJustPressed(0, 172) then picking = (picking - 2) % #MODES + 1 end
            if IsDisabledControlJustPressed(0, 173) then picking = picking % #MODES + 1 end
            if IsDisabledControlJustPressed(0, 172) or IsDisabledControlJustPressed(0, 173) then
                SendNUIMessage({ type = 'modes', open = true, items = MODES, index = picking,
                                 current = Stop.mode or (Stop.stopped and 'halt') })
            end
            if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201) then
                local id = MODES[picking].id
                close_picker()
                set_mode(Stop, id)
            elseif IsDisabledControlJustPressed(0, 177) then
                close_picker()
            end
            Wait(0)
        end
        if picking then close_picker() end
    end)
end, false)
RegisterCommand('-c3r_mode', function() end, false)
RegisterKeyMapping('+c3r_mode', 'Traffic stop: what the driver does (c3r)', 'keyboard', Config.ModeKey)

-- ─── the end of a stop ────────────────────────────────────────────────────────

-- One person, back to being an ordinary ped the game can clean up.
local function free_ped(net, o)
    if o.felony then DropFelonyPose(o) end
    if o.cuffed then
        if o.escorted then DetachEntity(o.ped, true, false) end
        SetEnableHandcuffs(o.ped, false)
        StopAnimTask(o.ped, 'mp_arresting', 'idle', 1.0)
    end
    if o.sitting then StopAnimTask(o.ped, SIT[1], SIT[2], 1.0) end
    if o.walk then ResetPedMovementClipset(o.ped, 0.0) end
    SetBlockingOfNonTemporaryEvents(o.ped, false)
    SetPedKeepTask(o.ped, false)
    TaskClearLookAt(o.ped)
    SetNetworkIdCanMigrate(net, true)
    SetEntityAsNoLongerNeeded(o.ped)
end

-- Whatever happens, they go back to being ordinary traffic the game can clean up.
local function let_go(s)
    if DoesEntityExist(s.veh) and not s.towed then -- (a towed car is the tow truck's)
        SetVehicleUndriveable(s.veh, false)
        SetEntityMaxSpeed(s.veh, 500.0)
        SetVehicleIndicatorLights(s.veh, 0, false)
        SetVehicleIndicatorLights(s.veh, 1, false)
        SetNetworkIdCanMigrate(s.veh_net, true)
        SetEntityAsNoLongerNeeded(s.veh)
    end
    for net, o in pairs(s.occ) do
        if Custody[net] or o.transported then
            -- in the back of the officer's car (still theirs, until booked), or in the transport van (its, until it fades)
        elseif DoesEntityExist(o.ped) then
            free_ped(net, o)
        end
    end
end

-- Out of the car (if they're in it) and away on foot.
local function walk_off(o)
    if not control(o.ped) then return end
    if IsPedInAnyVehicle(o.ped, false) then
        TaskLeaveVehicle(o.ped, GetVehiclePedIsIn(o.ped, false), 0)
        wait_until(5000, function() return not IsPedInAnyVehicle(o.ped, false) end)
    end
    TaskWanderStandard(o.ped, 10.0, 10)
end

-- Done: everyone back in their seat, signal, and pull back into traffic. With the car towed or the driver
-- arrested (or gone), whoever's left walks.
local function drive_off(s)
    local free = {}
    for _, o in pairs(s.occ) do
        o.task = nil -- any task still running for them stops here
        if not o.cuffed and not o.escaped and DoesEntityExist(o.ped) and not IsEntityDead(o.ped) then free[#free + 1] = o end
    end
    local driver = s.occ[s.ped_net]
    if s.towed or not DoesEntityExist(s.veh) or not driver or driver.cuffed or driver.escaped
        or not DoesEntityExist(s.ped) or IsEntityDead(s.ped) then
        for _, o in ipairs(free) do CreateThread(function() walk_off(o) end) end
        return
    end
    if not (control(s.ped) and control(s.veh)) then return log('drive off: no control of the car or driver') end
    SetVehicleUndriveable(s.veh, false)
    SetEntityMaxSpeed(s.veh, 500.0)
    for _, o in ipairs(free) do
        if not IsPedInVehicle(o.ped, s.veh, false) and control(o.ped) then
            TaskEnterVehicle(o.ped, s.veh, 15000, o.seat, 1.0, 1, 0)
        end
    end
    if not wait_until(16000, function()
        for _, o in ipairs(free) do
            if DoesEntityExist(o.ped) and not IsEntityDead(o.ped) and not IsPedInVehicle(o.ped, s.veh, false) then return false end
        end
        return true
    end) and not IsPedInVehicle(s.ped, s.veh, false) then return end
    Wait(2500)
    SetVehicleIndicatorLights(s.veh, 1, true) -- left, back out into the lane
    SetBlockingOfNonTemporaryEvents(s.ped, false)
    ClearPedTasks(s.ped) -- drop the hold (a long wait temp action) first; a seated ped stays seated
    TaskVehicleDriveWander(s.ped, s.veh, 15.0, 786603)
    Wait(6000)
    SetVehicleIndicatorLights(s.veh, 1, false)
end

-- ─── the ID card ─────────────────────────────────────────────────────────────
-- Shown top right for 15 s when handed over; Tab hides and shows it again until the stop ends.

local id_shot = nil -- their headshot, registered while the card is held

-- The ped's headshot as an image the page can load (a transparent one: the card has its own blue).
local function headshot(ped)
    if id_shot then UnregisterPedheadshot(id_shot) id_shot = nil end
    if not ped or not DoesEntityExist(ped) then return nil end
    local h = RegisterPedheadshotTransparent(ped)
    local ok = wait_until(3000, function() return IsPedheadshotReady(h) and IsPedheadshotValid(h) end)
    if not ok then UnregisterPedheadshot(h) return nil end
    id_shot = h
    local txd = GetPedheadshotTxdString(h)
    -- GTA reuses the same few texture names (pedmugshot_01...): without something new on the address the page
    -- shows the image it already has, the first person's face
    return ('https://nui-img/%s/%s?t=%d'):format(txd, txd, GetGameTimer())
end

local id_held = false

local function drop_id()
    id_held = false
    SendNUIMessage({ type = 'idcard', clear = true })
    if id_shot then UnregisterPedheadshot(id_shot) id_shot = nil end
end

-- Tab (control 37) toggles the card while one is held; the weapon wheel only opens once Tab is held
-- Config.WeaponWheelHold ms. ← → (174 / 175) swap it for the car's registration; the menu's page handles both itself.
-- Not while the arrows steer their car or pick who to talk to.
local WHEEL_MS = Config.WeaponWheelHold or 500
CreateThread(function()
    local tab_down = nil
    while true do
        if id_held then
            local now = GetGameTimer()
            -- (the Disabled checks see the key whether it's disabled this frame or not)
            if IsDisabledControlJustPressed(0, 37) then tab_down = now end
            local wheel = tab_down and now - tab_down >= WHEEL_MS
            if not wheel then DisableControlAction(0, 37, true) end
            if IsDisabledControlJustReleased(0, 37) then
                if tab_down and not wheel then SendNUIMessage({ type = 'idcard', toggle = true }) end
                tab_down = nil
            end
            if not (Stop and Stop.mode == 'steer') and not PickingPerson()
                and (IsControlJustPressed(0, 174) or IsControlJustPressed(0, 175)) then
                SendNUIMessage({ type = 'idcard', swap = true })
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

RegisterNetEvent('c3r:stop:ended', function(outcome)
    local s = Stop
    if s then DropChaseBlip(s) end
    Stop = nil
    if picking then close_picker() end
    ClearPrompt('stop')
    ClearPrompt('mode')
    CloseMenu()
    drop_id()
    -- 'fled': lwk_npcai already has them running, or they got away from a chase; don't hand them a calm
    -- drive-off on top of that (one who got away on foot: the others still go)
    if s then CreateThread(function()
        if outcome ~= 'fled' or s.lost_on_foot then drive_off(s) end
        let_go(s)
    end) end
    if outcome == 'cancelled' and s and not (s.foot or s.parked) then
        Prompt('stop', 'info', 'Traffic stop cancelled', 'They are free to go.', 3500)
    end
end)

-- Free to go while someone else is under arrest: only them, and the stop carries on.
RegisterNetEvent('c3r:stop:released', function(net)
    local s = Stop
    local o = s and s.occ[net]
    if not o then return end
    s.occ[net] = nil
    if not DoesEntityExist(o.ped) then return end
    CreateThread(function()
        walk_off(o)
        free_ped(net, o)
    end)
end)

-- Getting out ends the driving part: the mode card fades, and a car still being led or steered halts
-- where it is, so the officer can walk up and talk to them.
CreateThread(function()
    local was_in = false
    while true do
        local now_in = IsPedInAnyVehicle(PlayerPedId(), false)
        local s = Stop
        if s and was_in and not now_in then
            Prompt('stop', 'info', 'Traffic stop', ('Walk up and press %s to talk to them. Hold %s at their car for the vehicle.')
                :format(KeyName('+c3r_interact', 'E'), KeyName('+c3r_radial', 'G')), 7000)
            if s.manual and not s.stopped and IsPedInVehicle(s.ped, s.veh, false) then
                CreateThread(function()
                    if control(s.veh) and control(s.ped) then
                        ClearPedTasks(s.ped)
                        halt(s)
                    end
                end)
            end
        end
        was_in = now_in
        Wait(Stop and 250 or 1000)
    end
end)

RegisterNetEvent('c3r:stop:refused', function(why) Prompt('target', 'info', 'Unable', tostring(why), 4000) end)

-- c3r restarting mid-stop: don't leave a car stuck undriveable by the road
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Stop then
        let_go(Stop)
        if Stop.blip and DoesBlipExist(Stop.blip) then RemoveBlip(Stop.blip) end
    end
    for e in pairs(towing) do if DoesEntityExist(e) then DeleteEntity(e) end end
    drop_id()
    if type(clipboard) == 'number' then DeleteEntity(clipboard) end
end)

-- ─── what's said ──────────────────────────────────────────────────────────────
-- GTA's own subtitles: the officer's line, then the answer (who = their name once given, or their role).

local lines, speaking = {}, false

-- Some life while they talk: a talking face, and on foot a hand gesture (upper body only, so walking
-- and standing tasks carry on). Not over raised hands, and not over the officer's clipboard.
local GESTURES = {
    officer = { 'gesture_easy_now', 'gesture_hand_down', 'gesture_point' },
    subject = { 'gesture_shrug_hard', 'gesture_why', 'gesture_me', 'gesture_easy_now' },
}

local function animate(l)
    CreateThread(function()
        local officer = l.who == 'officer'
        local o = not officer and Stop and Stop.occ[l.net]
        local ped = officer and PlayerPedId() or (o and o.ped)
        if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then return end
        if load_dict('mp_facial') then PlayFacialAnim(ped, 'mic_chatter', 'mp_facial') end
        if IsPedInAnyVehicle(ped, false) or (o and (o.doing == 'handsup' or o.cuffed or o.fleeing or o.felony)) or (officer and clipboard) then return end
        local dict = is_male(ped) and 'gestures@m@standing@casual' or 'gestures@f@standing@casual'
        local set = GESTURES[officer and 'officer' or 'subject']
        if load_dict(dict) then TaskPlayAnim(ped, dict, set[math.random(#set)], 4.0, -4.0, -1, 48, 0.0, false, false, false) end
    end)
end

-- Writing the ticket: a clipboard in the left hand for a few seconds (menu.lua calls it on Fine / Ticket).
function OfficerClipboard(ms)
    local me = PlayerPedId()
    if clipboard or IsPedInAnyVehicle(me, false) then return end
    clipboard = true
    CreateThread(function()
        local model = GetHashKey('p_amb_clipboard_01')
        RequestModel(model)
        wait_until(1000, function() return HasModelLoaded(model) end)
        if not HasModelLoaded(model) or not load_dict('missfam4') then clipboard = nil return end
        local c = GetEntityCoords(me)
        local prop = CreateObject(model, c.x, c.y, c.z + 0.2, true, true, false)
        SetModelAsNoLongerNeeded(model)
        AttachEntityToEntity(prop, me, GetPedBoneIndex(me, 36029), 0.16, 0.08, 0.1, -130.0, -50.0, 0.0,
            true, true, false, true, 1, true)
        TaskPlayAnim(me, 'missfam4', 'base', 2.0, -2.0, -1, 49, 0.0, false, false, false)
        clipboard = prop
        Wait(ms or 7000)
        StopAnimTask(me, 'missfam4', 'base', 1.0)
        DeleteEntity(prop)
        clipboard = nil
    end)
end

local function speak_next()
    speaking = #lines > 0
    if not speaking then return end
    local l = table.remove(lines, 1)
    local ms = 1800 + #l.text * 55
    animate(l)
    BeginTextCommandPrint('STRING')
    AddTextComponentSubstringPlayerName((l.who == 'officer' and '~b~You:~s~ ' or ('~y~' .. l.who .. ':~s~ ')) .. l.text)
    EndTextCommandPrint(ms, true)
    SetTimeout(l.who == 'officer' and 1300 or ms, speak_next)
end

RegisterNetEvent('c3r:stop:say', function(text, who, net)
    lines[#lines + 1] = { text = text, who = tostring(who), net = net }
    if not speaking then speak_next() end
end)

-- Their ID: the card on screen (nui) with their headshot; the registration and licence status as feed lines.
RegisterNetEvent('c3r:stop:idcard', function(p)
    if p.plate then -- whose car it is: often not the driver's (a relative's, or stolen)
        local own = p.owner and p.owner == (p.first .. ' ' .. p.last)
        Notify(('~b~REGISTRATION~s~ %s~n~Registered owner: %s'):format(p.plate,
            own and 'the driver' or ((p.owner or 'unknown') .. ' ~o~(not the driver)~s~')))
    end
    Notify('~b~LICENSE~s~ ' .. (p.dl == 'Valid' and '~g~VALID' or ('~r~' .. tostring(p.dl or 'NONE'):upper())))
    CreateThread(function()
        local o = Stop and p.net and Stop.occ[p.net]
        p.photo = headshot(o and o.ped)
        id_held = true
        SendNUIMessage({ type = 'idcard', card = p })
    end)
end)

-- A roadside test's result (breathalyzer, drug swab): a prompt card that stays a while.
RegisterNetEvent('c3r:stop:result', function(r)
    SetTimeout(tonumber(r.delay) or 0, function() Prompt('result', r.bad and 'alert' or 'ok', r.title, r.text, 12000) end)
end)

-- ─── the tow ──────────────────────────────────────────────────────────────────
-- A flatbed comes up the road from behind, stops just ahead of the car, loads it (anyone still inside is put
-- out first) and drives off with it to impound, fading away once it's down the road.


function TowBusy() return next(towing) ~= nil end

local function load_model(name)
    local m = GetHashKey(name)
    RequestModel(m)
    return wait_until(5000, function() return HasModelLoaded(m) end) and m or nil
end

local function fade_away(ents)
    for _, e in ipairs(ents) do if DoesEntityExist(e) then NetworkFadeOutEntity(e, false, true) end end
    Wait(1500)
    for _, e in ipairs(ents) do
        if DoesEntityExist(e) then
            DetachEntity(e, false, false)
            DeleteEntity(e)
        end
    end
end

-- Driving styles for the truck. Normal traffic driving, and, near the scene or once it's stuck, working its way
-- round: slowly, past stopped cars (a traffic hold's queue), into the other lane if it must, still stopping for
-- people. Without "stop for cars" it would sit behind the queue for good.
-- 2 stop for peds + 4 swerve round vehicles + 8 round empty ones + 16 round peds + 32 round objects
-- + 512 wrong way allowed + 262144 shortcut links + 524288 change lanes round obstructions
local TOW_NORMAL, TOW_AROUND = 786603, 787006

-- car: what's towed; s: the stop it belongs to (its people are put out first), or nil for a car on its own.
function TowCar(car, s)
    local function untow() -- (the server lets it be asked for again, or after a few tries removes the car)
        if DoesEntityExist(car) and NetworkGetEntityIsNetworked(car) then
            return TriggerServerEvent('c3r:tow:failed', NetworkGetNetworkIdFromEntity(car))
        end
        if s and Stop == s then s.towed = nil end -- (the stop lets go of the car normally again)
    end
    local tm, dm = load_model(Config.Tow.truck), load_model(Config.Tow.driver)
    if not DoesEntityExist(car) or not tm or not dm then
        pcall(function() exports.lwk_control:say(nil, 'Tow truck unavailable.') end)
        return untow()
    end
    local c, fwd = GetEntityCoords(car), GetEntityForwardVector(car)
    local back = c - fwd * Config.Tow.distance
    local ok, node, h = GetClosestVehicleNodeWithHeading(back.x, back.y, back.z, 0, 3.0, 0) -- (0: no switched-off nodes)
    if not ok then node, h = back, GetEntityHeading(car) end
    local r = math.rad(h)
    if (-math.sin(r)) * (c.x - node.x) + math.cos(r) * (c.y - node.y) < 0 then h = (h + 180.0) % 360.0 end -- facing the car
    local truck = CreateVehicle(tm, node.x, node.y, node.z + 0.5, h, true, false)
    if truck == 0 then
        pcall(function() exports.lwk_control:say(nil, 'Tow truck unavailable.') end)
        return untow()
    end
    local driver = CreatePedInsideVehicle(truck, 26, dm, -1, true, false)
    DressVehicle(truck, Config.Tow) -- (client/backup.lua: livery, paint, extras, the driver's outfit)
    DressPed(driver, Config.Tow)
    SetModelAsNoLongerNeeded(tm)
    SetModelAsNoLongerNeeded(dm)
    towing[truck], towing[driver] = true, true
    for _, e in ipairs({ truck, driver }) do SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(e), false) end -- (stays ours to delete)
    TagBackup(truck)
    TagBackup(driver)
    if ReportBackup then ReportBackup() end -- (deleted by the server if the officer drops mid-tow)
    SetEntityAsMissionEntity(truck, true, true)
    SetEntityAsMissionEntity(driver, true, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetVehicleOnGroundProperly(truck)
    SetVehicleEngineOn(truck, true, true, false)
    local blip = AddBlipForEntity(truck)
    SetBlipSprite(blip, 68)
    SetBlipColour(blip, 47)

    local stop_at = c + fwd * 10.0
    local around, still, stuck = false, nil, false
    TaskVehicleDriveToCoord(driver, truck, stop_at.x, stop_at.y, stop_at.z, 12.0, 0, tm, TOW_NORMAL, 4.0, true)
    local arrived = wait_until(Config.Tow.timeout_ms, function()
        if not DoesEntityExist(truck) then return true end
        local d = #(GetEntityCoords(truck) - stop_at)
        if d < 8.0 then return true end
        still = GetEntitySpeed(truck) < 0.5 and (still or GetGameTimer()) or nil
        if not around and (d < 80.0 or (still and GetGameTimer() - still > 4000)) then -- close, or boxed in: work round
            around = true
            TaskVehicleDriveToCoord(driver, truck, stop_at.x, stop_at.y, stop_at.z, 7.0, 0, tm, TOW_AROUND, 4.0, true)
        elseif around and still and GetGameTimer() - still > 5000 then -- still boxed in (behind the patrol car): skip the rest
            stuck = true
            return true
        end
        return false
    end)
    if not DoesEntityExist(truck) or not DoesEntityExist(car) then
        fade_away({ truck, driver })
        towing[truck], towing[driver] = nil, nil
        return untow()
    end
    if not arrived or stuck then -- stuck in traffic somewhere: it turns up anyway
        SetEntityCoords(truck, stop_at.x, stop_at.y, stop_at.z, false, false, false, false)
        SetEntityHeading(truck, GetEntityHeading(car))
        SetVehicleOnGroundProperly(truck)
    end
    TaskVehicleTempAction(driver, truck, 27, 1000)
    Wait(1000)
    StartVehicleHorn(truck, 1800, GetHashKey('HELDDOWN'), false) -- one long honk: here for it
    Wait(1800)

    local loaded = control(car) -- (another player's game may own it: then the truck leaves empty, and says so)
    if loaded then
        for _, o in pairs(s and s.occ or {}) do
            if DoesEntityExist(o.ped) and IsPedInVehicle(o.ped, car, false) and not Custody[o.net] and control(o.ped) then
                o.out = true
                TaskLeaveVehicle(o.ped, car, 16)
            end
        end
        if not s then -- a car on its own: whoever's in it gets out first
            for seat = -1, GetVehicleMaxNumberOfPassengers(car) - 1 do
                local p = GetPedInVehicleSeat(car, seat)
                if p ~= 0 and not IsPedAPlayer(p) then TaskLeaveVehicle(p, car, 16) end
            end
        end
        SetEntityAsMissionEntity(car, true, true)
        TagBackup(car)
        if ReportBackup then ReportBackup() end
        Wait(1000)
        AttachEntityToEntity(car, truck, GetEntityBoneIndexByName(truck, 'bodyshell'), 0.0, -2.35, 1.15, 0.0, 0.0, 0.0,
            true, true, false, true, 0, true)
    end
    if loaded then
        Prompt('tow', 'ok', 'Vehicle loaded', 'The tow truck is taking it to the impound lot.', 5000)
    else
        pcall(function() exports.lwk_control:say(nil, 'Tow truck unable to load the vehicle.') end)
        untow()
    end
    Wait(2000)
    RemoveBlip(blip)
    TaskVehicleDriveWander(driver, truck, 8.0, TOW_AROUND) -- out past whatever's held up behind the scene first
    SetTimeout(15000, function()
        if DoesEntityExist(truck) and DoesEntityExist(driver) and NetworkHasControlOfEntity(driver) then
            TaskVehicleDriveWander(driver, truck, 15.0, TOW_NORMAL)
        end
    end)
    wait_until(45000, function()
        return not DoesEntityExist(truck) or #(GetEntityCoords(truck) - GetEntityCoords(PlayerPedId())) > 120.0
    end)
    fade_away(loaded and { car, truck, driver } or { truck, driver })
    towing[truck], towing[driver] = nil, nil
    if ReportBackup then ReportBackup() end
end

RegisterNetEvent('c3r:stop:tow', function()
    local s = Stop
    if not s or s.towed then return end
    s.towed = true
    Prompt('tow', 'info', 'Tow requested', 'A tow truck is on its way.', 6000)
    CreateThread(function() TowCar(s.veh, s) end)
end)

-- A failed tow of the stop's car: it can be towed again.
RegisterNetEvent('c3r:tow:retry', function(net)
    local s = Stop
    if s and s.towed and DoesEntityExist(s.veh) and NetworkGetNetworkIdFromEntity(s.veh) == net then s.towed = nil end
end)
