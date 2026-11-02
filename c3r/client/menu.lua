--[[
    c3r — client: talking to the people in the stopped car. A hint beside the officer while they're
    in reach; with more than one person in the car, the arrow keys pick who (a marker over them) and
    Enter confirms; then the radial menu for that person, with the camera on them, until it's closed or
    something is done that needs watching.
]]

local open = false
local target = nil   -- the person the menu is for
local browsing = nil -- { list = people, i = selected } while picking who to talk to

-- The arrow keys are picking who to talk to (stop.lua leaves them alone then).
function PickingPerson() return browsing ~= nil end

local NEAR_PERSON = 2.0 -- m: at their window, or beside them once out
local NEAR_SEAT = 3.0   -- m: someone sat in a car (it's their seat that's measured, maybe across the car)
local FAR_TALK = 20.0   -- m: no one's reach (a callout's `reach`) goes further than this

-- How far E reaches them: a callout person with `reach` is talked to from there, from cover.
local function reach_of(ped) return NetworkGetEntityIsNetworked(ped) and Entity(ped).state.c3r_reach or NEAR_PERSON end
local SEAT_NAMES = { [-1] = 'Driver', [0] = 'Front passenger', [1] = 'Rear passenger', [2] = 'Rear passenger' }
local STAYS_OPEN = { greet = true, ask = true, licence = true, breath = true, drugs = true, cite = true, warn = true } -- talk: keep the menu up
local HEAD = 31086

local function who(o) return (o.role == 'pedestrian' or o.role == nil) and 'Person' or SEAT_NAMES[o.seat] or 'Passenger' end

-- Everyone from the stop who's still there and alive, nearest to the officer first.
local function people(s)
    local me, out = GetEntityCoords(PlayerPedId()), {}
    for _, o in pairs(s.occ) do
        if DoesEntityExist(o.ped) and not IsEntityDead(o.ped) then out[#out + 1] = o end
    end
    table.sort(out, function(a, b) return #(GetEntityCoords(a.ped) - me) < #(GetEntityCoords(b.ped) - me) end)
    return out
end

-- On foot, the car stopped, and right beside one of them (in the car or standing behind it). near: how close counts
-- (left out: as far as E reaches them).
local function in_reach(s, near)
    local me = PlayerPedId()
    if not s.stopped or IsPedInAnyVehicle(me, false) then return false end
    local pos = GetEntityCoords(me)
    for _, o in pairs(s.occ) do
        if DoesEntityExist(o.ped) and #(pos - GetEntityCoords(o.ped)) < (IsPedInAnyVehicle(o.ped, false) and NEAR_SEAT or near or reach_of(o.ped)) then
            return true
        end
    end
    return false
end

-- The camera while the menu is up: over the officer's right shoulder, on their face (the officer turns to them).
local cam = nil

local function focus(ped)
    local me = PlayerPedId()
    local h, m = GetPedBoneCoords(ped, HEAD, 0.0, 0.0, 0.0), GetEntityCoords(me)
    SetEntityHeading(me, GetHeadingFromVector_2d(h.x - m.x, h.y - m.y))
    local e = GetPedBoneCoords(me, HEAD, 0.0, 0.0, 0.0)
    local d = h - e
    if #d < 0.2 then return end
    d = d / #d
    local right = vector3(d.y, -d.x, 0.0)
    right = right / math.max(#right, 0.01)
    local p = e - d * 0.85 + right * 0.45 + vector3(0.0, 0.0, 0.1)
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', p.x, p.y, p.z, 0.0, 0.0, 0.0, 45.0, false, 0)
    PointCamAtCoord(cam, h.x, h.y, h.z - 0.05)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
end

FocusPed = focus -- (client/medical.lua's wheel too)

local function unfocus()
    if not cam then return end
    local c = cam
    cam = nil
    RenderScriptCams(false, true, 500, true, true)
    SetTimeout(600, function() DestroyCam(c, false) end)
end
UnfocusPed = unfocus

function CloseMenu()
    if not open then return end
    open, target = false, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'radial', open = false })
    unfocus()
    NoPause()
end

local function open_menu(s, o)
    -- following the officer: talking to them stops that, and they stand where they are (as "Stay here")
    if o.following and not o.cuffed then
        o.following = false -- (now, so the menu offers "Follow me" again)
        TriggerEvent('c3r:stop:task', 'stay', o.net)
    end
    browsing, open, target = nil, true, o
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'radial', open = true, kind = 'person', key = KeyName('+c3r_interact', 'E'),
                     who = who(o), role = o.role, medic = not OnPatrol(), out = o.out == true, following = o.following == true, foot = s.foot == true,
                     cuffed = o.cuffed == true, escorted = o.escorted == true, seated = o.seated ~= nil, sitting = o.sitting == true,
                     categories = s.categories, questions = o.questions or {},
                     active = { police = BackupActive('police'), ambulance = BackupActive('ambulance'), cover = BackupActive('cover'),
                                coroner = BackupActive('coroner'), taxi = BackupActive('taxi'), dot = BackupActive('dot') } })
    focus(o.ped)
end

-- stop.lua: a stop that began with walking up to someone opens the menu on them straight away.
function OpenMenuFor(net)
    local s = Stop
    local o = s and s.occ[net]
    if o and not open then open_menu(s, o) end
end

-- Someone to walk up to, nearest first: a person on foot, or sitting in a car that's standing still and no player is
-- driving (the back of a parked patrol car too). Two side by side, the officer picks (the same as a driver and passenger).
-- s: a stop on now, whose own people don't count (they're talked to through it). -> { { ped } }
local function contacts(s)
    local me = PlayerPedId()
    if IsPedInAnyVehicle(me, false) or not LocalPlayer.state.c3rDuty then return {} end
    local mine = {}
    for _, o in pairs(s and s.occ or {}) do mine[o.ped] = true end
    local pos, out = GetEntityCoords(me), {}
    for _, ped in ipairs(GetGamePool('CPed')) do
        local d = ped ~= me and not mine[ped] and #(GetEntityCoords(ped) - pos) -- (distance first: the rest only for someone close)
        if d and d < FAR_TALK and (d < NEAR_SEAT or d < reach_of(ped)) and not IsPedAPlayer(ped) and not IsEntityDead(ped) and IsPedHuman(ped)
            and not IsBackup(ped) and not IsDowned(ped) then
            local veh = GetVehiclePedIsIn(ped, false)
            local driver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) or 0
            if (veh == 0 and d < reach_of(ped)) or (veh ~= 0 and d < NEAR_SEAT and GetEntitySpeed(veh) < 1.0 and (driver == 0 or not IsPedAPlayer(driver))) then
                out[#out + 1] = { ped = ped, d = d }
            end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

local function nearest_contact(s)
    local first = contacts(s)[1]
    return first and first.ped
end

-- What each person can be asked, as it stands: answers open follow-ups (the server's dialogue tree).
RegisterNetEvent('c3r:stop:questions', function(net, list)
    local o = Stop and Stop.occ[net]
    if not o then return end
    o.questions = list
    if open and target == o then SendNUIMessage({ type = 'questions', questions = list }) end
end)

RegisterCommand('+c3r_interact', function()
    local s = Stop
    if open or MedicalOpen() then return end
    if CalloutPlacing and CalloutPlacing() then return end -- (/c3rplace: E sets a point)
    if CalloutInspect and CalloutInspect() then return end -- evidence on a call, right beside you (client/callouts.lua)
    if EmsInteract and EmsInteract() then return end -- a medic's bag, stretcher and handover (client/ems.lua)
    local down = LocalPlayer.state.c3rDuty and DownedNear()
    if down then return (OnPatrol() and OpenMedical or EmsTreat)(down) end -- someone down beside you: first aid (client/medical.lua), or a medic's work
    if not s then -- anyone at all: they become the stop
        if browsing then browsing = nil return end -- the key again: never mind
        local list = contacts()
        if #list == 1 then RequestContact(list[1].ped)
        elseif #list > 1 then browsing = { list = list, i = 1, free = true } end
        return
    end
    -- someone else, while only chatting to someone (on foot, or in a parked car): that one's done with, and
    -- this one becomes the stop. Not on a traffic stop, and not with anyone in cuffs.
    local other = Casual(s) and not in_reach(s, NEAR_PERSON) and nearest_contact(s)
    if other then
        TriggerServerEvent('c3r:stop:act', 'cancel')
        return CreateThread(function()
            local deadline = GetGameTimer() + 2000
            while Stop and GetGameTimer() < deadline do Wait(50) end
            if not Stop then RequestContact(other) end
        end)
    end
    if not in_reach(s) then return end
    if browsing then browsing = nil return end -- the key again: never mind
    local list = people(s)
    if #list == 1 then return open_menu(s, list[1]) end
    if #list > 1 then browsing = { list = list, i = 1 } end
end, false)
RegisterCommand('-c3r_interact', function() end, false)
RegisterKeyMapping('+c3r_interact', 'Traffic stop: talk to someone in the car (c3r)', 'keyboard', Config.InteractKey)

-- The hint (and, while picking, the marker and the arrow keys), every frame while in reach.
CreateThread(function()
    local shown, sent_at, contact, scan_at, down = false, 0, nil, 0, nil
    local last = {} -- (what the page was last told: only send again when it moves or changes)
    while true do
        local s = Stop
        local free = not s or (Casual(s) and not in_reach(s, NEAR_PERSON)) -- E would start talking to someone new
        local down_open = MedicalOpen()
        if not open and GetGameTimer() >= scan_at then -- anyone nearby (a few times a second is plenty)
            scan_at = GetGameTimer() + 400
            down = LocalPlayer.state.c3rDuty and DownedNear() or nil
            contact = free and nearest_contact(s) or nil
        end
        if browsing and browsing.free and (s or not contact) then browsing = nil end -- (a stop started, or walked off from them)
        if not open and not down_open and ((s and in_reach(s)) or (free and contact) or down) then
            if browsing then
                for _, c in ipairs({ 174, 175, 176, 177, 191, 201 }) do DisableControlAction(0, c, true) end
                local n = #browsing.list
                if IsDisabledControlJustPressed(0, 174) then browsing.i = (browsing.i - 2) % n + 1 end
                if IsDisabledControlJustPressed(0, 175) then browsing.i = browsing.i % n + 1 end
                local o = browsing.list[browsing.i]
                if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201)
                    or IsDisabledControlJustPressed(0, 176) then
                    if browsing.free then
                        browsing = nil
                        RequestContact(o.ped)
                    elseif s then
                        open_menu(s, o)
                    end
                elseif IsDisabledControlJustPressed(0, 177) then
                    browsing = nil
                elseif DoesEntityExist(o.ped) then
                    local h = GetPedBoneCoords(o.ped, HEAD, 0.0, 0.0, 0.0)
                    DrawMarker(2, h.x, h.y, h.z + 0.45, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.22, 0.22, 0.18, 240, 176, 64, 220,
                        true, true, 2, false, nil, nil, false)
                end
            end
            -- beside the officer, a little above the shoulder
            local me = GetEntityCoords(PlayerPedId())
            local on, x, y = GetScreenCoordFromWorldCoord(me.x, me.y, me.z + 0.85)
            if on and not open and GetGameTimer() - sent_at >= 33 then -- (at most ~30 a second, to follow it smoothly)
                local o = browsing and browsing.list[browsing.i]
                local i = browsing and browsing.i or nil
                if not shown or math.abs(x - (last.x or 0)) > 0.002 or math.abs(y - (last.y or 0)) > 0.002 or i ~= last.i
                    or (browsing ~= nil) ~= last.browse then
                    sent_at = GetGameTimer()
                    last.x, last.y, last.i, last.browse = x, y, i, browsing ~= nil
                    SendNUIMessage({ type = 'hint', show = true, x = x, y = y, browse = browsing ~= nil,
                                     key = KeyName('+c3r_interact', 'E'), who = o and who(o) or nil,
                                     count = browsing and #browsing.list or nil, index = i })
                    shown = true
                end
            end
            Wait(0)
        else
            if browsing and not (s and in_reach(s)) then browsing = nil end
            if shown then
                SendNUIMessage({ type = 'hint', show = false })
                shown = false
            end
            Wait(s and 150 or 500)
        end
    end
end)

-- With the menu up the game gets no input, so after ~30 s it cuts to its idle (cinematic) camera: keep
-- resetting it. Their ped walking off (or the stop ending) closes it.
CreateThread(function()
    while true do
        if open then
            InvalidateIdleCam()
            InvalidateVehicleIdleCam()
            if not Stop or not target or not DoesEntityExist(target.ped) or IsEntityDead(target.ped)
                or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(target.ped)) > reach_of(target.ped) + 2.0 then
                CloseMenu()
            end
        end
        Wait(500)
    end
end)

-- action: greet | ask (arg = question id) | licence | breath | drugs | sobriety | frisk | search_car | exit | back |
-- follow | stay | handsup | cuff | uncuff | escort | seat | unseat | tow | warn | cite | release
RegisterNUICallback('pick', function(d, cb)
    cb({})
    local o = target
    if d.action == 'backup' then CloseMenu() return CallBackup(d.arg) end
    if not Stop or not o or type(d.action) ~= 'string' then return CloseMenu() end
    TriggerServerEvent('c3r:stop:act', d.action, d.arg, o.net)
    if d.action == 'cite' then OfficerClipboard() end
    if not STAYS_OPEN[d.action] then CloseMenu() end -- orders and endings: watch it happen
end)

RegisterNUICallback('close', function(_, cb)
    cb({})
    CloseMenu()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    CloseMenu()
    if cam then RenderScriptCams(false, false, 0, true, true) DestroyCam(cam, false) end
end)
