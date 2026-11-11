--[[
    c3r — client: callouts (server/callouts.lua). The offer card (Y responds), the waypoint to the call, the objective
    card (Backspace hides / shows it), and leaving the call (X, then "Leave this call?"). Clearing with dispatch
    (lwk_control's "code four") leaves it too, through completeCallout.
]]

local board = {}   -- the open calls: { { id, name, street, coords, priority, description, units } }
local offer = nil  -- the call on the offer card while it's up
local call = nil   -- the call I'm on: its record, and its blip
local hidden, last_text = false, nil
local confirming = false

local REFUSED = { already_on_call = 'You are already on a call.', off_duty = 'You are not on duty.',
                  no_callout = 'No call available near you right now.', no_tasking = 'No special tasking available right now.',
                  solo_tasking = "That tasking is another unit's." }

local function clear_blip()
    if call and call.blip and DoesBlipExist(call.blip) then RemoveBlip(call.blip) end
end

-- The map marks who / what my objective is about (the caller, then the person or the car...), following them once
-- they're near enough to be in my game.
local marks = {} -- { { blip, net?, label, kind } }
local SPRITE = { person = 280, vehicle = 225, clue = 586 } -- UNVERIFIED: blip sprite ids (person / car / magnifier)

local function clear_marks()
    for _, m in ipairs(marks) do if DoesBlipExist(m.blip) then RemoveBlip(m.blip) end end
    marks = {}
end

local function mark(m)
    local ent = m.net and NetworkDoesNetworkIdExist(m.net) and NetToEnt(m.net) or 0
    local blip = DoesEntityExist(ent) and AddBlipForEntity(ent) or AddBlipForCoord(m.at.x, m.at.y, m.at.z)
    SetBlipSprite(blip, SPRITE[m.kind] or 1)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.85)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(m.label or 'Objective')
    EndTextCommandSetBlipName(blip)
    m.blip, m.on_entity = blip, DoesEntityExist(ent)
    marks[#marks + 1] = m
end

-- Who / what my objectives are about, in the world: a bobbing amber arrow over their head (or the car), so it's
-- plain who to talk to. { { net, kind } }
local pointed = {}

local function set_marks(card)
    clear_marks()
    pointed = {}
    for _, item in ipairs(card and card.mine or {}) do
        for _, b in ipairs(item.blips or {}) do
            mark(b)
            if b.net and (b.kind == 'person' or b.kind == 'vehicle') then pointed[#pointed + 1] = { net = b.net, kind = b.kind } end
        end
    end
end

-- The arrows: within 60 m, not for someone I'm talking to right now (the menu's on them), drawn every frame only
-- while one is close.
local ARROW_RANGE = 60.0
CreateThread(function()
    local HEAD = 31086 -- SKEL_Head
    while true do
        local drew = false
        if call and pointed[1] and not (EmsScreen and EmsScreen()) then -- (not over a medic's treatment screen)
            local me = GetEntityCoords(PlayerPedId())
            for _, p in ipairs(pointed) do
                local ent = NetworkDoesNetworkIdExist(p.net) and NetToEnt(p.net) or 0
                if ent ~= 0 and DoesEntityExist(ent) and not IsEntityDead(ent) and not (Stop and Stop.occ and Stop.occ[p.net]) then
                    local at = p.kind == 'person' and GetPedBoneCoords(ent, HEAD, 0.0, 0.0, 0.0) + vector3(0.0, 0.0, 0.55)
                        or GetEntityCoords(ent) + vector3(0.0, 0.0, 1.6)
                    if #(at - me) < ARROW_RANGE then
                        DrawMarker(0, at.x, at.y, at.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.28, 0.28, 0.28, 240, 176, 64, 210,
                            true, true, 2, false, nil, nil, false)
                        drew = true
                    end
                end
            end
        end
        Wait(drew and 0 or 400)
    end
end)

CreateThread(function() -- a mark on a spot becomes one on the person / car once they're in my game
    while true do
        Wait(2000)
        for i, m in ipairs(marks) do
            if not m.on_entity and m.net and NetworkDoesNetworkIdExist(m.net) and DoesEntityExist(NetToEnt(m.net)) then
                if DoesBlipExist(m.blip) then RemoveBlip(m.blip) end
                table.remove(marks, i)
                mark(m)
                break
            end
        end
    end
end)

RegisterNetEvent('c3r:callout:board', function(list) board = type(list) == 'table' and list or {} end)

-- Dispatch over the radio: the call's own line, or "Incoming 911 call", in the area of where it is (lwk_control_assets
-- voice/<key>_to_1.ogg + the location's clips; voice/<key>_1.ogg with no location), the details as text. -> said it
local function announce(r)
    local clip = r.voice and LoadResourceFile('lwk_control_assets', ('nui/voice/%s_1.ogg'):format(r.voice)) and r.voice or 'incoming_call'
    local alert = r.alert or 'Incoming 911 call' -- (a planned job isn't a 911 call: the callout's `alert`)
    return pcall(function()
        exports.lwk_control:sayCall(clip, vector3(r.coords.x, r.coords.y, r.coords.z), ('%s: %s, %s. Priority %d.'):format(alert, r.name:lower(), r.street, r.priority))
    end)
end

RegisterNetEvent('c3r:callout:offer', function(r)
    if call then return end
    local cad_only = LocalPlayer.state.c3rNoPopup -- (lwk_mdt's settings: no card, it's on the board there; dispatch still says it)
    if not cad_only then
        local ms = ((Config.Callouts or {}).offer_window or 30) * 1000
        offer = r
        offer.until_t = GetGameTimer() + ms
        for _, b in ipairs(board) do if b.id == r.id then r.units = b.units end end
        SendNUIMessage({ type = 'callout', offer = { name = r.name, street = r.street, distance = r.distance, report = r.description,
            priority = r.priority, units = r.units, key = KeyName('+c3r_respond', 'Y'), decline = KeyName('+c3r_leavecall', 'X'), ms = ms } })
    end
    local said = announce(r)
    if cad_only then
        Notify(('~b~C~w~3~r~R~s~ New call in the CAD: %s, %s.'):format(r.name, r.street))
    elseif not said then
        Notify(('~b~DISPATCH~s~ %s: %s, %s.'):format(r.alert or 'Incoming 911 call', r.name:lower(), r.street))
    end
end)

-- The call's waypoint moved (c:waypoint, a route of places): the marker and the GPS route go there, until I'm close.
local function route_to(at)
    if not (call and call.blip and DoesBlipExist(call.blip)) then return end
    local wp = vector3(at.x, at.y, at.z)
    call.wp = wp
    SetBlipCoords(call.blip, wp.x, wp.y, wp.z)
    SetBlipRoute(call.blip, true)
    SetBlipRouteColour(call.blip, 1)
    CreateThread(function()
        while call and call.wp == wp do
            if #(GetEntityCoords(PlayerPedId()) - wp) < 40.0 then
                if DoesBlipExist(call.blip) then SetBlipRoute(call.blip, false) end
                return
            end
            Wait(1000)
        end
    end)
end

RegisterNetEvent('c3r:callout:waypoint', function(id, at) if call and call.id == id then route_to(at) end end)

RegisterNetEvent('c3r:callout:joined', function(r)
    if r.say and not announce(r) then Notify(('~b~DISPATCH~s~ %s: %s, %s.'):format(r.alert or 'Assigned', r.name:lower(), r.street)) end -- (a tasking handed to me)
    offer = nil
    SendNUIMessage({ type = 'callout', offer = false })
    clear_blip()
    call, hidden, last_text = r, false, nil
    local at = r.coords
    call.blip = AddBlipForCoord(at.x, at.y, at.z)
    SetBlipSprite(call.blip, 280) -- (a person with an exclamation mark)
    SetBlipColour(call.blip, 1)
    SetBlipRoute(call.blip, true)
    SetBlipRouteColour(call.blip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(r.name)
    EndTextCommandSetBlipName(call.blip)
    if r.waypoint then route_to(r.waypoint) end
end)

RegisterNetEvent('c3r:callout:card', function(card)
    if not call or card.id ~= call.id then return end
    if card.arrived and not call.wp and call.blip and DoesBlipExist(call.blip) then SetBlipRoute(call.blip, false) end -- (a moved one: route_to)
    local text = card.mine[1] and card.mine[1].text
    if hidden and text and text ~= last_text then Prompt('callout', 'info', 'New objective', text, 5000) end
    if last_text and text and text ~= last_text then SendNUIMessage({ type = 'sfx', name = 'ding' }) end -- (a new objective)
    last_text = text
    set_marks(card)
    SendNUIMessage({ type = 'callout', card = card, hidden = hidden, keys = { hide = KeyName('+c3r_objective', 'BACKSPACE'),
        leave = KeyName('+c3r_leavecall', 'X') } })
end)

local function close_confirm()
    if not confirming then return end
    confirming = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'callout', confirm = false })
    NoPause()
end

RegisterNetEvent('c3r:callout:ended', function(completed, summary)
    close_confirm()
    clear_blip()
    clear_marks()
    call = nil
    SendNUIMessage({ type = 'callout', card = false })
    if completed then
        Prompt('callout', 'ok', 'Callout complete', summary or 'Dispatch shows you clear.', 7000)
    else
        Prompt('callout', 'info', 'Off the call', 'You are clear of the call.', 5000)
    end
end)

RegisterNetEvent('c3r:callout:refused', function(why)
    Prompt('callout', 'info', 'Unable', REFUSED[why] or tostring(why), 4000)
end)

-- A radio update from the call (the story): dispatch says it.
RegisterNetEvent('c3r:callout:dispatch', function(text, clips)
    local ok = pcall(function() exports.lwk_control:say(clips, text) end)
    if not ok then Notify('~b~DISPATCH~s~ ' .. tostring(text)) end
end)

-- ─── keys ─────────────────────────────────────────────────────────────────────

local function respond(id) TriggerServerEvent('c3r:callout:respond', id) end

RegisterCommand('+c3r_respond', function()
    if EmsRespond and not IsNuiFocused() and EmsRespond() then return end -- (a police unit asking for an ambulance: client/ems.lua)
    if call or not offer or GetGameTimer() > offer.until_t or IsNuiFocused() then return end
    respond(offer.id)
end, false)
RegisterCommand('-c3r_respond', function() end, false)
RegisterKeyMapping('+c3r_respond', 'Callout: respond (c3r)', 'keyboard', Config.RespondKey or 'Y')

RegisterCommand('respond', function() if not call then respond(nil) end end, false) -- the nearest open call

-- /c3rpos [name]: where you are, as a callout point, copied to the clipboard (and printed in F8) to paste into a
-- callout's locations. Sat in a car: the car's position and heading (for a c:vehicle point).
RegisterCommand('c3rpos', function(_, args)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local e = veh ~= 0 and veh or ped
    local p, h = GetEntityCoords(e), GetEntityHeading(e)
    local text = ('%svector4(%.2f, %.2f, %.2f, %.1f),'):format(args[1] and (args[1] .. ' = ') or '', p.x, p.y, p.z, h)
    print(text)
    SendNUIMessage({ type = 'copy', text = text })
    Notify('~b~C~w~3~r~R~s~ Copied: ' .. text)
end, false)

RegisterCommand('+c3r_objective', function()
    -- (Backspace also closes the who-to-talk-to and driver pickers: those turn it off while they're open)
    if not call or CalloutPlacing() or IsNuiFocused() or not IsControlEnabled(0, 177) then return end
    if IdCardHeld and IdCardHeld() and (Config.IdCardKey or 'BACK') == (Config.ObjectiveKey or 'BACK') then return end -- (the ID card has it)
    hidden = not hidden
    SendNUIMessage({ type = 'callout', hidden = hidden })
end, false)
RegisterCommand('-c3r_objective', function() end, false)
RegisterKeyMapping('+c3r_objective', 'Callout: hide / show the objective (c3r)', 'keyboard', Config.ObjectiveKey or 'BACK')

RegisterCommand('+c3r_leavecall', function()
    -- (X is also the taser's arc and the Stop Stick's let-go: not while either is in hand)
    if confirming or CalloutPlacing() or IsNuiFocused() or LocalPlayer.state.taser or LocalPlayer.state.stopstick then return end
    if EmsDecline and EmsDecline() then return end -- (an ambulance request: let it go, or give it up: client/ems.lua)
    if not call and offer and GetGameTimer() < offer.until_t then -- an offer up: decline it (it stays open for others)
        offer = nil
        return SendNUIMessage({ type = 'callout', offer = false })
    end
    if not call then return end
    confirming = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'callout', confirm = true, name = call.name })
end, false)
RegisterCommand('-c3r_leavecall', function() end, false)
RegisterKeyMapping('+c3r_leavecall', 'Callout: decline the offer / leave the call (c3r)', 'keyboard', Config.LeaveCallKey or 'X')

RegisterNUICallback('calloutLeave', function(d, cb)
    cb({})
    close_confirm()
    if d.leave and call then TriggerServerEvent('c3r:callout:leave') end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    close_confirm()
    clear_blip()
    clear_marks()
end)

-- ─── the call's people, on whichever game owns them (any player's: the server sends it to that one) ───────

local function with_dict(dict)
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
end

-- What they're doing when nobody's dealing with them: a scenario ('WORLD_HUMAN_...'), an anim { dict, name, flag },
-- or just standing there.
local function scene(ped, sc)
    ClearPedTasks(ped)
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true) -- (back from 'hold': the gun's put away)
    if type(sc) == 'string' then
        TaskStartScenarioInPlace(ped, sc, 0, true) -- UNVERIFIED per scenario: the callout names it
    elseif type(sc) == 'table' and sc[1] and with_dict(sc[1]) then
        TaskPlayAnim(ped, sc[1], sc[2], 4.0, -4.0, -1, sc[3] or 1, 0.0, false, false, false)
    else
        TaskStandStill(ped, -1)
    end
end

local function nearest_player_ped(from)
    local best, best_d = PlayerPedId(), math.huge
    for _, pl in ipairs(GetActivePlayers()) do
        local p = GetPlayerPed(pl)
        local d = #(GetEntityCoords(p) - from)
        if d < best_d then best, best_d = p, d end
    end
    return best
end

-- Their weapon out, in their hand.
local function draw(ped, weapon)
    if not weapon then return end
    local hash = GetHashKey(weapon)
    GiveWeaponToPed(ped, hash, 250, false, true)
    SetCurrentPedWeapon(ped, hash, true)
end

-- Fighting whoever's near. With a spot (`at`: a window, a doorway) they go there and hold it, using cover within 4 m of
-- it (combat movement 1, defensive); with none they come after the officer, taking cover as they go (2, offensive).
-- Attributes UNVERIFIED by name, from the game's enum: 0 use cover, 5 and 46 fight rather than flee. HATES_PLAYER: every
-- player's their enemy, so it carries on when the first target's gone.
local StoodDown = {} -- [ped] = true: gave up (a surrender can land while they're still walking to their spot)
local Fought = {} -- [ped] = true: fighting, armed or not
local function shoot(ped, at, weapon)
    StoodDown[ped], Fought[ped] = nil, true
    ClearPedTasks(ped) -- (out of whatever they were doing: a scenario, aiming at someone)
    draw(ped, weapon)
    CreateThread(function() -- (the server hears of the first real shot: drawing a gun isn't "shots fired")
        local net, deadline = NetworkGetNetworkIdFromEntity(ped), GetGameTimer() + 180000
        while DoesEntityExist(ped) and not StoodDown[ped] and GetGameTimer() < deadline do
            if IsPedShooting(ped) then return TriggerServerEvent('c3r:callout:fired', net) end
            Wait(100)
        end
    end)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedSeeingRange(ped, 150.0)
    SetPedHearingRange(ped, 150.0)
    SetPedRelationshipGroupHash(ped, GetHashKey('HATES_PLAYER'))
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 0, true)
    SetPedCombatAttributes(ped, 5, true)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAbility(ped, 1) -- (average)
    SetPedCombatRange(ped, 2) -- (far)
    SetPedAccuracy(ped, 25)
    if at then
        TaskFollowNavMeshToCoord(ped, at.x, at.y, at.z, 3.0, 6000, 0.75, 0, type(at) == 'vector4' and at.w or 0.0)
        local deadline = GetGameTimer() + 6000
        while DoesEntityExist(ped) and GetGameTimer() < deadline and #(GetEntityCoords(ped) - vector3(at.x, at.y, at.z)) > 1.0 do Wait(100) end
        if not DoesEntityExist(ped) or StoodDown[ped] then StoodDown[ped] = nil return end
        SetPedSphereDefensiveArea(ped, at.x, at.y, at.z, 4.0, false, false)
        SetPedCombatMovement(ped, 1)
    else
        SetPedCombatMovement(ped, 2)
    end
    if DoesEntityExist(ped) then TaskCombatPed(ped, nearest_player_ped(GetEntityCoords(ped)), 0, 16) end
end

-- Done fighting: weapon away, and no longer everyone's enemy.
local function stand_down(ped)
    StoodDown[ped], Fought[ped] = true, nil
    ClearPedTasks(ped)
    SetPedRelationshipGroupHash(ped, GetHashKey(IsPedMale(ped) and 'CIVMALE' or 'CIVFEMALE'))
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    SetBlockingOfNonTemporaryEvents(ped, true)
end

-- Into their car (args.net) and off to args.at, with the traffic. The server says when they're there: 'get_out'.
local DRIVE_STYLE = 786603 -- (the same as a backup unit's: stops for cars)
local FAST_STYLE = 786468 -- (the same as a fleeing car's: client/stop.lua)
local function drive(ped, args)
    local veh = NetworkDoesNetworkIdExist(args.net) and NetToVeh(args.net) or 0
    if not DoesEntityExist(veh) then return end
    if not IsPedInVehicle(ped, veh, false) then
        ClearPedTasks(ped)
        local walk = math.min(100000, math.floor(10000 + #(GetEntityCoords(ped) - GetEntityCoords(veh)) * 800)) -- (from up the street, too)
        TaskEnterVehicle(ped, veh, walk, -1, 1.5, 1, 0)
        local deadline = GetGameTimer() + walk + 1000
        while DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) and not IsPedInVehicle(ped, veh, false) and GetGameTimer() < deadline do Wait(200) end
    end
    if not DoesEntityExist(ped) or not IsPedInVehicle(ped, veh, false) or not NetworkHasControlOfEntity(ped) then return end -- (not: another game has them now, and its own copy of this)
    if Stop and Stop.occ[NetworkGetNetworkIdFromEntity(ped)] then return end -- (an officer got to them first)
    NetworkRequestControlOfEntity(veh)
    local deadline = GetGameTimer() + 2000
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < deadline do Wait(0) end
    SetVehicleUndriveable(veh, false)
    SetVehicleEngineOn(veh, true, true, false)
    if args.fast then
        SetDriverAbility(ped, 1.0)
        SetDriverAggressiveness(ped, 1.0)
    end
    local speed, style = args.fast and 45.0 or 12.0, args.fast and FAST_STYLE or DRIVE_STYLE
    if args.at then TaskVehicleDriveToCoordLongrange(ped, veh, args.at.x, args.at.y, args.at.z, speed, style, 4.0)
    else TaskVehicleDriveWander(ped, veh, speed, style) end
end

-- The other one may not have reached this game yet.
function their_ped_soon(net)
    local deadline = GetGameTimer() + 3000
    while not NetworkDoesNetworkIdExist(net) and GetGameTimer() < deadline do Wait(100) end
    local ped = NetworkDoesNetworkIdExist(net) and NetToEnt(net) or 0
    return DoesEntityExist(ped) and ped or nil
end

-- Fists, on one other person. Their game watches for a stun gun: nobody else can see it. (lwk_taser: the server sees it.)
local function brawl(ped, args)
    local target = their_ped_soon(args.net)
    if not target then return end
    StoodDown[ped], Fought[ped] = nil, true
    ClearPedTasks(ped)
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 5, true)
    SetPedCombatAttributes(ped, 46, true)
    TaskCombatPed(ped, target, 0, 16)
    local net = NetworkGetNetworkIdFromEntity(ped)
    while DoesEntityExist(ped) and Fought[ped] and NetworkHasControlOfEntity(ped) do
        if IsPedBeingStunned(ped, 0) then return TriggerServerEvent('c3r:callout:stunned', net) end
        Wait(200)
    end
end

-- One of a crowd (c:crowd): an ordinary passer-by, reacting to the street as anyone does. Just made: onto the ground first
-- (made from the middle's height, wherever in the area). Outside the area: walks in, then wanders it.
local function crowd(ped, a)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedKeepTask(ped, true)
    local mid = vector3(a.x, a.y, a.z)
    if a.place then
        local p = GetEntityCoords(ped)
        RequestCollisionAtCoord(p.x, p.y, p.z)
        local ok, z = GetGroundZFor_3dCoord(p.x, p.y, p.z + 2.0, false)
        if ok and math.abs(z - p.z) < 6.0 then SetEntityCoords(ped, p.x, p.y, z, false, false, false, false) end
    end
    if #(GetEntityCoords(ped) - mid) > a.r then
        TaskFollowNavMeshToCoord(ped, mid.x, mid.y, mid.z, 1.0, -1, a.r * 0.5, 0, 0.0)
        local deadline = GetGameTimer() + 90000
        while DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) and #(GetEntityCoords(ped) - mid) > a.r and GetGameTimer() < deadline do Wait(1000) end
        if not (DoesEntityExist(ped) and NetworkHasControlOfEntity(ped)) then return end
    end
    TaskWanderInArea(ped, mid.x, mid.y, mid.z, a.r, 2, 8.0) -- (at least 2 m a walk, ~8 s stood between: UNVERIFIED by eye)
end

local SPRAY_UP = 6.0 -- m over the point a 'spray' is aimed at
local function run(ped, name, args, sc, weapon)
    if name == 'go' and args then -- (walking there round buildings and cars, not through them)
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        TaskFollowNavMeshToCoord(ped, args.x, args.y, args.z, 1.0, -1, 1.5, 0, type(args) == 'vector4' and args.w or 0.0)
    elseif name == 'flee' then
        RunFrom(ped, nearest_player_ped(GetEntityCoords(ped))) -- (client/stop.lua)
    elseif name == 'surrender' then
        if weapon or Fought[ped] then stand_down(ped) end
        TaskHandsUp(ped, -1, nearest_player_ped(GetEntityCoords(ped)), -1, false)
    elseif name == 'aim' then
        local target = args and NetworkDoesNetworkIdExist(args.net) and NetToEnt(args.net) or 0
        draw(ped, weapon)
        if DoesEntityExist(target) then TaskAimGunAtEntity(ped, target, -1, false) end
    elseif name == 'hold' then
        ClearPedTasks(ped)
        draw(ped, weapon)
        local target = args and their_ped_soon(args.net)
        if target then TaskAimGunAtEntity(ped, target, -1, false) else TaskStandStill(ped, -1) end
    elseif name == 'spray' and args then -- (a 3 s burst, aimed SPRAY_UP m over the point: heard and seen, over everyone's heads)
        ClearPedTasks(ped)
        draw(ped, weapon)
        if weapon then SetPedInfiniteAmmo(ped, true, GetHashKey(weapon)) end
        TaskShootAtCoord(ped, args.x, args.y, args.z + SPRAY_UP, 3000, GetHashKey('FIRING_PATTERN_FULL_AUTO')) -- (pattern name UNVERIFIED)
    elseif name == 'shoot' then
        shoot(ped, args, weapon)
    elseif name == 'brawl' and args then
        brawl(ped, args)
    elseif name == 'drive' and args then
        drive(ped, args)
    elseif name == 'die' then
        FreezeEntityPosition(ped, false)
        SetEntityHealth(ped, 0)
    elseif name == 'get_out' then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 then TaskLeaveVehicle(ped, veh, 0) end
    elseif name == 'crowd' and args then -- (c:crowd: into the area if outside it, then walking about in it)
        crowd(ped, args)
    elseif name == 'wander' then
        if weapon or Fought[ped] then stand_down(ped) end -- (the call ended mid-fight: it's over for them too)
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedKeepTask(ped, false)
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 then -- (the call ended with them at the wheel of their own car)
            SetVehicleUndriveable(veh, false)
            SetVehicleEngineOn(veh, true, true, false)
            TaskVehicleDriveWander(ped, veh, 12.0, DRIVE_STYLE)
        else
            TaskWanderStandard(ped, 10.0, 10)
        end
    else
        scene(ped, sc)
    end
end

local function their_ped(net)
    local deadline = GetGameTimer() + 2000
    while not NetworkDoesNetworkIdExist(net) and GetGameTimer() < deadline do Wait(50) end
    local ped = NetworkDoesNetworkIdExist(net) and NetToEnt(net) or 0
    return DoesEntityExist(ped) and ped or nil
end

-- Evidence: lying on the ground (a /c3rpos point is at hip height), and staying there.
-- Down onto the ground, once this game has the ground: a prop is made as soon as a unit is within 300 m, too far for the
-- game to have loaded the collision under it, and with none it would stay frozen in the air. Waits for me to be close, for
-- as long as this game has the prop (a game that takes it over does the same).
local function to_ground(obj)
    while DoesEntityExist(obj) and NetworkHasControlOfEntity(obj) and not IsEntityAttached(obj) do
        local p = GetEntityCoords(obj)
        if #(GetEntityCoords(PlayerPedId()) - p) < 120.0 then
            RequestCollisionAtCoord(p.x, p.y, p.z)
            local ok, z = GetGroundZFor_3dCoord(p.x, p.y, p.z + 1.5, false)
            if ok and math.abs(z - p.z) < 5.0 then
                SetEntityCoordsNoOffset(obj, p.x, p.y, z, false, false, false)
                PlaceObjectOnGroundProperly(obj)
                return FreezeEntityPosition(obj, true)
            end
        end
        Wait(500)
    end
end

local function lay(obj, a)
    if IsEntityAttached(obj) then return end -- (being dragged: it changed games to whoever picked it up)
    SetEntityAsMissionEntity(obj, true, true)
    FreezeEntityPosition(obj, true)
    if a.place then to_ground(obj) end
end

-- What a crash did to a parked car. SET_VEHICLE_DAMAGE's offsets are from the car's middle: high.y is the front bumper,
-- low.y the back, high.x the right side. How each one looks UNVERIFIED by eye.
local function dents(veh, how)
    local low, high = GetModelDimensions(GetEntityModel(veh))
    if how == 'dent' then
        SetVehicleDamage(veh, 0.0, high.y, 0.1, 250.0, 0.8, true)
    elseif how == 'rear' then
        SetVehicleDamage(veh, 0.0, low.y, 0.1, 300.0, 0.9, true)
    elseif how == 'front' or how == 'wreck' then
        SetVehicleDamage(veh, 0.0, high.y, 0.1, 400.0, 1.2, true)
        SetVehicleDamage(veh, high.x * 0.6, high.y, 0.2, 300.0, 0.8, true) -- (one corner worse: the headlight)
        SetVehicleBodyHealth(veh, 550.0)
        SetVehicleEngineHealth(veh, 700.0) -- (dented, not on fire)
    end
    if how == 'side' or how == 'wreck' then
        SetVehicleDamage(veh, high.x, 0.0, 0.2, 400.0, 1.2, true)
        SetVehicleDamage(veh, high.x, high.y * 0.5, 0.2, 300.0, 0.8, true)
        SetVehicleBodyHealth(veh, 550.0)
    end
    if how == 'wreck' then
        SetVehicleDamage(veh, 0.0, low.y, 0.1, 400.0, 1.2, true)
        SmashVehicleWindow(veh, 6) -- (the windscreen)
        SetVehicleDoorOpen(veh, 4, true, true) -- (the bonnet, sprung)
        SetVehicleBodyHealth(veh, 300.0)
        SetVehicleEngineHealth(veh, 250.0) -- (smoking, and not burning: that's under 0)
    end
end

-- Once, when I'm close: a car's made at 300 m, too far off for the game to dent it. Waits for as long as this game has the
-- car (a game that takes it over does the same); the state bag stops it happening twice, because dents add up.
local function dent_when_close(veh, how)
    while DoesEntityExist(veh) and NetworkHasControlOfEntity(veh) and not Entity(veh).state.c3r_dented do
        if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(veh)) < 60.0 then
            Entity(veh).state:set('c3r_dented', true, true)
            return dents(veh, how)
        end
        Wait(500)
    end
end

-- A parked car in the story: its paint, its plate, locked, engine off, wheels on the ground; damage: 'dent', 'rear', 'side',
-- 'front' (caved in) or 'wreck'.
local function park(veh, a)
    SetEntityAsMissionEntity(veh, true, true)
    if a.place then SetVehicleOnGroundProperly(veh) end
    if a.paint then SetVehicleColours(veh, a.paint, a.paint) end
    if a.plate then SetVehicleNumberPlateText(veh, a.plate) end
    if GetPedInVehicleSeat(veh, -1) == 0 then SetVehicleEngineOn(veh, false, true, true) end -- (not under someone driving it: it changes games with them)
    SetVehicleDoorsLocked(veh, a.locked and 2 or 1)
    if a.damage then dent_when_close(veh, a.damage) end
end

-- a = { net, scene, task, place (the first time: facing the point's heading), heading, down } (a person), or
-- { net, vehicle = true, paint, plate, locked, place, damage } (a car)
RegisterNetEvent('c3r:callout:apply', function(a)
    CreateThread(function()
        local ped = their_ped(a.net)
        if not ped then return end
        if a.vehicle then return park(ped, a) end
        if a.prop then return lay(ped, a) end
        if a.dead then -- (dead when found: an animal in the road, say)
            SetEntityAsMissionEntity(ped, true, true)
            return SetEntityHealth(ped, 0)
        end
        if IsPedInAnyVehicle(ped, false) and not (a.task and a.task.name == 'drive') then return end -- (in an ambulance by now)
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true) -- (they do the story, not whatever the street is doing)
        SetPedKeepTask(ped, true)
        if a.place and a.heading then SetEntityHeading(ped, a.heading) end -- (stood exactly where the callout says)
        -- hurt, on the ground (client/medical.lua holds them there), unless paramedics have just seen to them
        if a.down and IsCasualty(ped) then
            if GetEntityHealth(ped) >= GetEntityMaxHealth(ped) then SetEntityHealth(ped, 140) end -- (hurt)
            return HoldDown(ped)
        end
        if a.seat then -- (at the wheel, engine running)
            local veh = their_ped(a.seat)
            if veh then
                SetPedIntoVehicle(ped, veh, -1)
                NetworkRequestControlOfEntity(veh)
                local deadline = GetGameTimer() + 1000
                while not NetworkHasControlOfEntity(veh) and GetGameTimer() < deadline do Wait(0) end
                SetVehicleEngineOn(veh, true, true, false)
            end
        end
        if a.task then run(ped, a.task.name, a.task.args, a.scene, a.weapon)
        elseif not a.seat then scene(ped, a.scene) end
    end)
end)

RegisterNetEvent('c3r:callout:task', function(net, name, args, sc, weapon)
    CreateThread(function()
        local ped = their_ped(net)
        if ped then run(ped, name, args, sc, weapon) end
    end)
end)

-- A real shot or firework from a point, straight up (c:bang). Nobody's weapon: nobody's hurt.
RegisterNetEvent('c3r:callout:bang', function(weapon, at, shots)
    CreateThread(function()
        local hash = GetHashKey(weapon)
        RequestWeaponAsset(hash, 31, 0)
        local deadline = GetGameTimer() + 2000
        while not HasWeaponAssetLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
        for i = 1, shots do
            ShootSingleBulletBetweenCoords(at.x, at.y, at.z + 2.5, at.x, at.y + 0.1, at.z + 60.0, 0, true, hash, 0, true, false, -1.0) -- (clear of a car's roof)
            if i < shots then Wait(math.random(300, 900)) end
        end
    end)
end)

-- On a call, the server hears who this officer has their gun on (AimedPed: client/pa.lua), a few times a second at most.
CreateThread(function()
    local told = {} -- [net] = when
    while true do
        Wait(call and 250 or 1500)
        local ped = call and AimedPed()
        if ped and NetworkGetEntityIsNetworked(ped) then
            local net, now = PedToNet(ped), GetGameTimer()
            if not told[net] or now - told[net] > 3000 then
                told[net] = now
                TriggerServerEvent('c3r:callout:aimed', net)
            end
        end
    end
end)

-- ─── evidence ─────────────────────────────────────────────────────────────────

local clues, clue_call = {}, nil -- what can be inspected on my call: { { key, label, at | on (a net), range, glow } }
local looked = {} -- [clue key] = true: inspected by me (its arrow goes)

RegisterNetEvent('c3r:callout:clues', function(id, list) clue_call, clues = id, type(list) == 'table' and list or {} end)

-- Dragging a clue with drag = true: E picks it up (once it's been looked at), E lets it go, and the server hears where.
local dragging = nil -- { key, obj }
local function let_go()
    local d = dragging
    dragging = nil
    if not d then return end
    ClearPedSecondaryTask(PlayerPedId())
    if not DoesEntityExist(d.obj) then return end
    DetachEntity(d.obj, true, false)
    PlaceObjectOnGroundProperly(d.obj)
    FreezeEntityPosition(d.obj, true)
    local p = GetEntityCoords(d.obj)
    TriggerServerEvent('c3r:callout:dragged', clue_call, d.key, not IsPointOnRoad(p.x, p.y, p.z, 0), p)
end

local function grab(cl)
    local obj = cl.glow and NetworkDoesNetworkIdExist(cl.glow) and NetToObj(cl.glow) or 0
    if not DoesEntityExist(obj) then return end
    NetworkRequestControlOfEntity(obj)
    local deadline = GetGameTimer() + 1000
    while not NetworkHasControlOfEntity(obj) and GetGameTimer() < deadline do Wait(0) end
    if not NetworkHasControlOfEntity(obj) then return end
    local me = PlayerPedId()
    FreezeEntityPosition(obj, false)
    AttachEntityToEntity(obj, me, 0, 0.0, 1.1, -0.85, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    if with_dict('anim@heists@box_carry@') then TaskPlayAnim(me, 'anim@heists@box_carry@', 'idle', 4.0, -4.0, -1, 49, 0.0, false, false, false) end -- UNVERIFIED anim
    dragging = { key = cl.key, obj = obj }
    CreateThread(function()
        while dragging do
            DisableControlAction(0, 21, true) -- (no running with it)
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then let_go() end
            Wait(0)
        end
    end)
end

AddEventHandler('c3r:callout:ended', function()
    let_go()
    clues, clue_call, looked = {}, nil, {}
end)

-- Where it is: the person or car it's on, its prop (which may have rolled a little as it landed), or its point.
local function clue_pos(cl)
    local net = cl.on or cl.glow
    if net then
        local ent = NetworkDoesNetworkIdExist(net) and NetToEnt(net) or 0
        if DoesEntityExist(ent) then return GetEntityCoords(ent) end
        if cl.on then return nil end
    end
    return cl.at and vector3(cl.at.x, cl.at.y, cl.at.z)
end

local function nearest_clue()
    local me = PlayerPedId()
    if not call or IsPedInAnyVehicle(me, false) then return nil end
    local here, best, best_d = GetEntityCoords(me), nil, math.huge
    for _, cl in ipairs(clues) do
        local at = (cl.drag or not looked[cl.key]) and clue_pos(cl) -- (seen: it's on the MDT, and E is for whoever's beside it now)
        local d = at and #(at - here)
        if d and d < (cl.range or 1.6) and d < best_d then best, best_d = cl, d end
    end
    return best, best and clue_pos(best)
end

-- E (client/menu.lua asks first): evidence beside you is looked at before anyone's talked to.
-- The call's spot, if I'm on one and within m metres: backup that works on the scene goes there, not to whoever I'm with.
function CallSpot(m)
    if not call then return nil end
    local at = vector3(call.coords.x, call.coords.y, call.coords.z)
    return #(GetEntityCoords(PlayerPedId()) - at) < m and at or nil
end

function CalloutInspect()
    if dragging then
        let_go()
        return true
    end
    local cl = nearest_clue()
    if not cl then return false end
    if cl.drag and looked[cl.key] then
        CreateThread(function() grab(cl) end)
        return true
    end
    TriggerServerEvent('c3r:callout:inspect', clue_call, cl.key)
    return true
end

RegisterNetEvent('c3r:callout:found', function(label, text, key)
    Prompt('evidence', 'info', tostring(label), tostring(text), 9000)
    if key then looked[key] = true end
end)

-- Evidence I haven't looked at yet has a bobbing amber arrow over it (the prop, its spot, or the car it's on) once
-- I'm within CLUE_RANGE of it, like the people my objective is about. (Not an outline: those redraw the object every
-- frame, and cost far more.) Drawn every frame only while one is in range.
local CLUE_RANGE = 30.0
CreateThread(function()
    while true do
        local drew = false
        if call and clues[1] and not (EmsScreen and EmsScreen()) then
            local me = GetEntityCoords(PlayerPedId())
            for _, cl in ipairs(clues) do
                local car = cl.on and (cl.range or 0) > 2 -- (on a person: their own arrow, if they're the objective)
                if not looked[cl.key] and (car or not cl.on) then
                    local at = clue_pos(cl)
                    if at and #(at - me) < CLUE_RANGE then
                        at = at + vector3(0.0, 0.0, car and 1.6 or 0.7)
                        DrawMarker(0, at.x, at.y, at.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.24, 0.24, 0.24, 240, 176, 64, 210,
                            true, true, 2, false, nil, nil, false)
                        drew = true
                    end
                end
            end
        end
        Wait(drew and 0 or 400)
    end
end)

-- Up close: the game's help text with the key.
CreateThread(function()
    while true do
        local cl = nil
        if call and clues[1] then cl = nearest_clue() end
        if cl then
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('~INPUT_CONTEXT~ %s: %s'):format(cl.drag and looked[cl.key] and 'Drag' or 'Inspect', cl.label))
            EndTextCommandDisplayHelp(0, false, false, -1)
            Wait(0)
        else
            Wait(call and clues[1] and 250 or 1000)
        end
    end
end)

-- spikes: any car here driven through it loses its tyres (the officer's too, and traffic, on whichever game drives it).
-- Not backup's own trucks.
local WHEELS = { 0, 1, 4, 5 }
CreateThread(function()
    while true do
        local close = false
        if call and clues[1] then
            local me = GetEntityCoords(PlayerPedId())
            for _, cl in ipairs(clues) do
                local at = cl.spikes and cl.at and vector3(cl.at.x, cl.at.y, cl.at.z)
                if at and #(me - at) < 150.0 then
                    close = true
                    for _, v in ipairs(GetGamePool('CVehicle')) do
                        if #(GetEntityCoords(v) - at) < cl.spikes and GetEntitySpeed(v) > 1.0 and NetworkHasControlOfEntity(v) and not IsBackup(v) then
                            for _, w in ipairs(WHEELS) do
                                if not IsVehicleTyreBurst(v, w, false) then SetVehicleTyreBurst(v, w, false, 1000.0) end
                            end
                        end
                    end
                end
            end
        end
        Wait(close and 150 or 1500)
    end
end)

TriggerServerEvent('c3r:callout:sync') -- (the calls open now)

-- ─── /c3rplace (server/callouts.lua): walk out a new location for a callout, point by point ──────────────────────

local placing = nil -- { id, name, points = { { name, what, kind } }, index, i, got = { [name] = { x, y, z, h } }, ghosts }
function CalloutPlacing() return placing ~= nil end -- (client/menu.lua: E sets a point, it doesn't talk to anyone)

-- A see-through stand-in where a point was set, so the whole layout shows as it's built (only in this game).
local function ghost(kind, p)
    local model = GetHashKey(kind == 'car' and 'asea' or 'a_m_y_hipster_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return nil end
    local e = kind == 'car' and CreateVehicle(model, p.x, p.y, p.z, p.h, false, false)
        or CreatePed(4, model, p.x, p.y, p.z - 1.0, p.h, false, false) -- (a ped's position is its hips: its feet are lower)
    SetModelAsNoLongerNeeded(model)
    if kind == 'car' then SetVehicleOnGroundProperly(e) else SetBlockingOfNonTemporaryEvents(e, true) end
    SetEntityAlpha(e, 140, false)
    SetEntityCollision(e, false, false)
    SetEntityInvincible(e, true)
    FreezeEntityPosition(e, true)
    return e
end

local function clear_ghosts()
    for _, e in pairs(placing and placing.ghosts or {}) do if DoesEntityExist(e) then DeleteEntity(e) end end
end

local function stop_placing(msg)
    clear_ghosts()
    placing = nil
    ClearPrompt('place')
    if msg then Prompt('place', 'info', 'Placing', msg, 5000) end
end

local function show_point()
    local pt = placing.points[placing.i]
    Prompt('place', 'info', ('%s %d/%d: %s'):format(placing.name, placing.i, #placing.points, pt[1]),
        pt[2] .. (pt[3] == 'car' and ' Sit in the car, then E.' or ' Stand there, facing their way, then E.')
        .. (pt[4] and ' Z: skip, not at this location.' or '') .. ' Backspace: back. X: cancel.')
end

local function where(at)
    local s1 = GetStreetNameAtCoord(at.x, at.y, at.z)
    local street = s1 and s1 ~= 0 and GetStreetNameFromHashKey(s1) or ''
    if street == '' then street = GetLabelText(GetNameOfZone(at.x, at.y, at.z)) end
    return street
end

local function finish_placing()
    local first = placing.got[placing.points[1][1]] -- (the scene: where the first point is, the caller's)
    Prompt('place', 'info', 'Placing', 'Saving...', 4000)
    local streets = {} -- (each point's: a home round the corner is on another street)
    for name, p in pairs(placing.got) do streets[name] = where(vector3(p.x, p.y, p.z)) end
    TriggerServerEvent('c3r:place:save', placing.id, placing.index,
        { street = where(vector3(first.x, first.y, first.z)), streets = streets, points = placing.got })
end

RegisterNetEvent('c3r:place:start', function(d)
    if placing then stop_placing() end
    placing = { id = d.id, name = d.name, points = d.points, index = d.index, i = 1, got = {}, ghosts = {} }
    show_point()
    CreateThread(function()
        while placing and placing.i <= #placing.points do
            for _, c in ipairs({ 20, 38, 73, 177 }) do DisableControlAction(0, c, true) end -- (Z, E, X, Backspace are the placer's)
            local me = PlayerPedId()
            if IsDisabledControlJustPressed(0, 38) then
                local pt = placing.points[placing.i]
                local veh = GetVehiclePedIsIn(me, false)
                if pt[3] == 'car' and veh == 0 then
                    Prompt('place_warn', 'info', 'A car point', 'Sit in a car parked where it should be, then E.', 4000)
                elseif pt[3] ~= 'car' and veh ~= 0 then
                    Prompt('place_warn', 'info', 'On foot', 'Get out and stand where they should stand, then E.', 4000)
                else
                    local e = pt[3] == 'car' and veh or me
                    local c, h = GetEntityCoords(e), GetEntityHeading(e)
                    local p = { x = c.x, y = c.y, z = c.z, h = h }
                    placing.got[pt[1]] = p
                    CreateThread(function() local g = ghost(pt[3], p) if g and placing then placing.ghosts[pt[1]] = g elseif g then DeleteEntity(g) end end)
                    placing.i = placing.i + 1
                    if placing.i > #placing.points then finish_placing() else show_point() end
                end
            elseif IsDisabledControlJustPressed(0, 20) then
                if placing.points[placing.i][4] then
                    placing.i = placing.i + 1
                    if placing.i > #placing.points then finish_placing() else show_point() end
                else
                    Prompt('place_warn', 'info', 'Needed', 'This one can\'t be skipped.', 3000)
                end
            elseif IsDisabledControlJustPressed(0, 177) and placing.i > 1 then
                placing.i = placing.i - 1
                local name = placing.points[placing.i][1]
                placing.got[name] = nil
                if placing.ghosts[name] and DoesEntityExist(placing.ghosts[name]) then DeleteEntity(placing.ghosts[name]) end
                placing.ghosts[name] = nil
                show_point()
            elseif IsDisabledControlJustPressed(0, 73) then
                return stop_placing('Cancelled: nothing saved.')
            end
            Wait(0)
        end
    end)
end)

RegisterNetEvent('c3r:place:saved', function(msg, entry)
    stop_placing()
    Prompt('place', 'ok', 'Location saved', msg, 7000)
    SendNUIMessage({ type = 'copy', text = entry }) -- (and on the clipboard, in case)
end)

RegisterNetEvent('c3r:place:msg', function(msg)
    if placing and placing.i > #placing.points then stop_placing() end -- (the save was refused)
    Prompt('place', 'info', 'Placing', tostring(msg), 8000)
end)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() and placing then stop_placing() end end)

-- ─── the contract (docs/contract.md) ──────────────────────────────────────────

exports('isOnCallout', function() return call ~= nil end)
exports('isOfferedCallout', function() return call == nil and board[1] ~= nil end) -- an open call I could join
exports('acceptCallout', function()
    if call then return nil, 'already_on_call' end
    if not board[1] then return nil, 'no_callout' end
    respond(offer and GetGameTimer() < offer.until_t and offer.id or nil)
    return true
end)
-- clearing with dispatch: off the call. -> true, 'cancelled' (the last unit on it: the call is called off) | 'left'
exports('completeCallout', function()
    if not call then return nil, 'not_attached' end
    local units = 1
    for _, b in ipairs(board) do if b.id == call.id then units = b.units or 1 end end
    TriggerServerEvent('c3r:callout:leave')
    return true, units <= 1 and 'cancelled' or 'left'
end)
