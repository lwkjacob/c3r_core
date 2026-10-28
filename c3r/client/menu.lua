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
local SEAT_NAMES = { [-1] = 'Driver', [0] = 'Front passenger', [1] = 'Rear passenger', [2] = 'Rear passenger' }
local STAYS_OPEN = { greet = true, ask = true, licence = true, breath = true, drugs = true, cite = true, warn = true } -- talk: keep the menu up
local HEAD = 31086

local function who(o) return o.role == 'pedestrian' and 'Person' or SEAT_NAMES[o.seat] or 'Passenger' end

-- Everyone from the stop who's still there and alive, nearest to the officer first.
local function people(s)
    local me, out = GetEntityCoords(PlayerPedId()), {}
    for _, o in pairs(s.occ) do
        if DoesEntityExist(o.ped) and not IsEntityDead(o.ped) then out[#out + 1] = o end
    end
    table.sort(out, function(a, b) return #(GetEntityCoords(a.ped) - me) < #(GetEntityCoords(b.ped) - me) end)
    return out
end

-- On foot, the car stopped, and right beside one of them (in the car or standing behind it).
local function in_reach(s)
    local me = PlayerPedId()
    if not s.stopped or IsPedInAnyVehicle(me, false) then return false end
    local pos = GetEntityCoords(me)
    for _, o in pairs(s.occ) do
        if DoesEntityExist(o.ped) and #(pos - GetEntityCoords(o.ped)) < NEAR_PERSON then return true end
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
    browsing, open, target = nil, true, o
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'radial', open = true, kind = 'person', key = KeyName('+c3r_interact', 'E'),
                     who = who(o), role = o.role, out = o.out == true, following = o.following == true, foot = s.foot == true,
                     cuffed = o.cuffed == true, escorted = o.escorted == true, seated = o.seated ~= nil, sitting = o.sitting == true,
                     categories = s.categories, questions = o.questions or {},
                     active = { police = BackupActive('police'), ambulance = BackupActive('ambulance'), cover = BackupActive('cover'),
                                coroner = BackupActive('coroner'), taxi = BackupActive('taxi') } })
    focus(o.ped)
end

-- stop.lua: a stop that began with walking up to someone opens the menu on them straight away.
function OpenMenuFor(net)
    local s = Stop
    local o = s and s.occ[net]
    if o and not open then open_menu(s, o) end
end

-- Someone to walk up to when there's no stop on: a person on foot, or sitting in a car that's standing still.
-- s: a stop on now, whose own people don't count (they're talked to through it).
local function nearest_contact(s)
    local me = PlayerPedId()
    if IsPedInAnyVehicle(me, false) or not LocalPlayer.state.c3rDuty then return nil end
    local mine = {}
    for _, o in pairs(s and s.occ or {}) do mine[o.ped] = true end
    local pos, best, best_d = GetEntityCoords(me), nil, NEAR_PERSON
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and not mine[ped] and not IsPedAPlayer(ped) and not IsEntityDead(ped) and IsPedHuman(ped) and not IsBackup(ped)
            and not IsDowned(ped) then
            local d = #(GetEntityCoords(ped) - pos)
            if d < best_d then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh == 0 or (GetEntitySpeed(veh) < 1.0 and GetPedInVehicleSeat(veh, -1) ~= 0) then best, best_d = ped, d end
            end
        end
    end
    return best
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
    local down = LocalPlayer.state.c3rDuty and DownedNear()
    if down then return OpenMedical(down) end -- someone down beside you: first aid (client/medical.lua)
    if not s then -- anyone at all: they become the stop
        local ped = nearest_contact()
        if ped then RequestContact(ped) end
        return
    end
    -- someone else, while only chatting to someone (on foot, or in a parked car): that one's done with, and
    -- this one becomes the stop. Not on a traffic stop, and not with anyone in cuffs.
    local other = Casual(s) and not in_reach(s) and nearest_contact(s)
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
    while true do
        local s = Stop
        local free = not s or (Casual(s) and not in_reach(s)) -- E would start talking to someone new
        local down_open = MedicalOpen()
        if not open and GetGameTimer() >= scan_at then -- anyone nearby (a few times a second is plenty)
            scan_at = GetGameTimer() + 300
            down = LocalPlayer.state.c3rDuty and DownedNear() or nil
            contact = free and nearest_contact(s) or nil
        end
        if not open and not down_open and ((s and in_reach(s)) or (free and contact) or down) then
            if browsing then
                for _, c in ipairs({ 174, 175, 176, 177, 191, 201 }) do DisableControlAction(0, c, true) end
                local n = #browsing.list
                if IsDisabledControlJustPressed(0, 174) then browsing.i = (browsing.i - 2) % n + 1 end
                if IsDisabledControlJustPressed(0, 175) then browsing.i = browsing.i % n + 1 end
                local o = browsing.list[browsing.i]
                if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201)
                    or IsDisabledControlJustPressed(0, 176) then
                    open_menu(s, o)
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
            if on and not open and GetGameTimer() - sent_at >= 33 then -- ~30 updates a second follow it smoothly
                sent_at = GetGameTimer()
                local o = browsing and browsing.list[browsing.i]
                SendNUIMessage({ type = 'hint', show = true, x = x, y = y, browse = browsing ~= nil,
                                 key = KeyName('+c3r_interact', 'E'), who = o and who(o) or nil,
                                 count = browsing and #browsing.list or nil, index = browsing and browsing.i or nil })
                shown = true
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
                or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(target.ped)) > NEAR_PERSON + 2.0 then
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
