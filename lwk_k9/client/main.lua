--[[
    lwk_k9 — client: your dog. Call it from the K9 slice of c3r's G wheel (on patrol) or the wheel key (anyone, on or
    off duty): Heel, Sit, Down, Speak, In / out of your car, Dismiss. A police breed with an officer on duty as police in
    c3r also does Sniff (the stop's car, or someone on it), Attack (whoever runs from the stop) and Track (a runner's
    route, or a player's). Every command cancels whatever the dog was doing. BY LWK DEVELOPMENT
]]

Dog = nil   -- the ped, while out
Setup = nil -- { model, name, comps = { ['comp'] = { drawable, texture } } }, saved per player
local Access = { police = false } -- (the server's: on duty as police in c3r)
local mode = nil    -- 'heel' | 'sit' | 'down' | 'car' | 'busy' (sniffing, going after someone, tracking)
local job = 0       -- bumped by every command: a running one sees it changed and stops
local in_car = nil  -- the vehicle it's sat in
local runners = {}  -- [net] = { ped, trail = { vector3 }, seen (game time) }: whoever ran from a stop, kept a while
local scents = {}   -- { { id, age } }: players whose trail passes near (the server's)

local KVP = 'lwk_k9:setup'
local function log(...) if Config.Debug then print('[lwk_k9]', ...) end end
local function card(kind, title, text, ms) exports.c3r:prompt('k9', kind, title, text, ms or 6000) end

function BreedOf(model)
    for _, b in ipairs(Config.Breeds) do if b.model == model then return b end end
    return Config.Breeds[1]
end
local function breed() return BreedOf(Setup.model) end
function DogName() return Setup.name ~= '' and Setup.name or breed().label end
local function police() return Access.police and breed().police == true end

local function load_setup()
    local ok, t = pcall(json.decode, GetResourceKvpString(KVP) or '')
    t = ok and type(t) == 'table' and t or {}
    Setup = { model = BreedOf(t.model).model, name = type(t.name) == 'string' and t.name:sub(1, 20) or '',
              comps = type(t.comps) == 'table' and t.comps or {} }
end
function SaveSetup() SetResourceKvp(KVP, json.encode(Setup)) end
load_setup()

RegisterNetEvent('lwk_k9:access', function(a) Access = type(a) == 'table' and a or Access end)
CreateThread(function() TriggerServerEvent('lwk_k9:access') end)

-- ─── moving it about ─────────────────────────────────────────────────────────
local function load_dict(d)
    RequestAnimDict(d)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(d) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(d)
end

local function play(what) -- 'sit' | 'down' | 'bark' | 'car'
    local a = (Config.Anims[breed().anims] or {})[what]
    if not a or not Dog then return end
    ClearPedTasks(Dog)
    if a.scenario then return TaskStartScenarioInPlace(Dog, a.scenario, -1, true) end -- (-1: until told otherwise)
    if load_dict(a.dict) then TaskPlayAnim(Dog, a.dict, a.anim, 8.0, -8.0, -1, 1, 0.0, false, false, false) end
end

local function go(p, speed) TaskGoToCoordAnyMeans(Dog, p.x, p.y, p.z, speed or 1.0, 0, false, 786603, 0.0) end
-- Wait until the dog is near p. -> false when told something else meanwhile (or it's gone)
local function reach(id, p, near, ms)
    local t = GetGameTimer() + ms
    while job == id and Dog and GetGameTimer() < t and #(GetEntityCoords(Dog) - p) > near do Wait(200) end
    return job == id and Dog ~= nil
end
local function face(ent) TaskTurnPedToFaceEntity(Dog, ent, 800) Wait(900) end

local function bone(veh, name, fallback_y)
    local i = GetEntityBoneIndexByName(veh, name)
    if i ~= -1 then return GetWorldPositionOfEntityBone(veh, i) end
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, fallback_y or 0.0, 0.0)
end
-- A spot just out from that part of the car (a door, the boot)
local function beside(veh, b, fallback_y)
    local p, c = bone(veh, b, fallback_y), GetEntityCoords(veh)
    local d = vector3(p.x - c.x, p.y - c.y, 0.0)
    local l = #d
    return l < 0.1 and p or p + d / l * 0.8
end

function Heel()
    if not Dog then return end
    if in_car then return GetOut() end
    job = job + 1
    ClearPedTasks(Dog)
    TaskFollowToOffsetOfEntity(Dog, PlayerPedId(), 0.6, -0.8, 0.0, 5.0, -1, 1.2, true)
    mode = 'heel'
end

local function stay(what)
    if not Dog or in_car then return end
    job = job + 1
    play(what)
    mode = what
end

local function speak()
    if not Dog or in_car then return end
    local was, id = mode, job + 1
    job = id
    play('bark')
    Wait(3500)
    if job ~= id or not Dog then return end
    if was == 'sit' or was == 'down' then stay(was) else Heel() end
end

local function load_model(m)
    local h = GetHashKey(m)
    if not IsModelInCdimage(h) then return nil end
    RequestModel(h)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(h) and GetGameTimer() < t do Wait(0) end
    return HasModelLoaded(h) and h or nil
end

function ApplyLook()
    if not Dog then return end
    for c, v in pairs(Setup.comps) do
        local comp = tonumber(c)
        if comp and type(v) == 'table' then SetPedComponentVariation(Dog, comp, tonumber(v[1]) or 0, tonumber(v[2]) or 0, 0) end
    end
end

function Spawn()
    if Dog then return true end
    local h = load_model(Setup.model)
    if not h then card('alert', 'K9', ('%s is not on this server.'):format(breed().label)) return false end
    local me = PlayerPedId()
    local at = GetOffsetFromEntityInWorldCoords(me, 0.0, 1.5, 0.0)
    Dog = CreatePed(28, h, at.x, at.y, at.z, GetEntityHeading(me), true, true)
    SetModelAsNoLongerNeeded(h)
    SetBlockingOfNonTemporaryEvents(Dog, true)
    SetPedFleeAttributes(Dog, 0, false)
    SetPedRelationshipGroupHash(Dog, GetPedRelationshipGroupHash(me))
    ApplyLook()
    Heel()
    log('out:', Setup.model)
    return true
end

function Dismiss()
    if not Dog then return end
    job = job + 1
    DeleteEntity(Dog)
    Dog, mode, in_car = nil, nil, nil
end

-- ─── the car ─────────────────────────────────────────────────────────────────
local SEATS = { { 1, 'door_dside_r' }, { 2, 'door_pside_r' }, { 0, 'door_pside_f' } } -- seat, its door's bone

-- The door at that spot: the nearest door's own entry point (add-on cars don't always number their doors as GTA's do).
local function door_at(veh, p)
    local best, door = math.huge, nil
    for i = 0, 3 do
        local d = #(GetEntryPositionOfDoor(veh, i) - p)
        if d < best then best, door = d, i end
    end
    return door
end

local function get_in()
    local me = PlayerPedId()
    local veh = GetVehiclePedIsIn(me, false)
    if veh == 0 then veh = GetVehiclePedIsIn(me, true) end
    if veh == 0 or not DoesEntityExist(veh) or #(GetEntityCoords(veh) - GetEntityCoords(Dog)) > 20.0 then
        return card('info', 'K9', 'No car of yours close by.', 4000)
    end
    for _, s in ipairs(SEATS) do
        if IsVehicleSeatFree(veh, s[1]) then
            job = job + 1
            local id = job
            mode = 'busy'
            local p = beside(veh, s[2])
            go(p, 2.0)
            if not reach(id, p, 1.5, 10000) then return end
            local door = door_at(veh, p)
            SetVehicleDoorOpen(veh, door, false, false)
            Wait(500)
            SetPedIntoVehicle(Dog, veh, s[1])
            play('car')
            Wait(700)
            SetVehicleDoorShut(veh, door, false)
            in_car, mode = veh, 'car'
            return
        end
    end
    card('info', 'K9', 'No free seat for the dog.', 4000)
end

function GetOut()
    local veh = in_car
    in_car = nil
    job = job + 1
    if not Dog then return end
    if not veh or not DoesEntityExist(veh) then return Heel() end
    local seat
    for _, s in ipairs(SEATS) do if GetPedInVehicleSeat(veh, s[1]) == Dog then seat = s end end
    local p = seat and beside(veh, seat[2]) or GetOffsetFromEntityInWorldCoords(veh, 2.0, 0.0, 0.0)
    local door = seat and door_at(veh, p)
    if door then SetVehicleDoorOpen(veh, door, false, false) Wait(400) end
    ClearPedTasksImmediately(Dog)
    SetEntityCoords(Dog, p.x, p.y, p.z, false, false, false, false)
    if door then Wait(500) SetVehicleDoorShut(veh, door, false) end
    Heel()
end

local function car() if in_car then GetOut() else get_in() end end

-- ─── Sniff ───────────────────────────────────────────────────────────────────
local ROUTE = { { 'driver', 'door_dside_f' }, { 'rear_left', 'door_dside_r' }, { 'trunk', 'boot', -3.0 },
                { 'rear_right', 'door_pside_r' }, { 'passenger', 'door_pside_f' } }
local BONE = {}
for _, r in ipairs(ROUTE) do BONE[r[1]] = r end

local sniffed -- the server's answer: { where, net } | false
RegisterNetEvent('lwk_k9:sniffed', function(where, net) sniffed = where and { where = where, net = net } or false end)

local function ent(net, veh)
    if not net or not NetworkDoesNetworkIdExist(net) then return 0 end
    return veh and NetToVeh(net) or NetToPed(net)
end

-- what: 'car' or a person's net id
local function sniff(what)
    local stop = exports.c3r:getStop()
    if not Dog or not police() or not stop then return end
    if in_car then GetOut() end
    job = job + 1
    local id = job
    mode = 'busy'
    local veh, ped = what == 'car' and ent(stop.veh_net, true) or 0, what ~= 'car' and ent(tonumber(what)) or 0
    if veh == 0 and ped == 0 then return Heel() end
    card('info', 'K9', ('%s is sniffing.'):format(DogName()), 4000)
    if veh ~= 0 then
        for _, r in ipairs(ROUTE) do
            local p = beside(veh, r[2], r[3])
            go(p, 1.0)
            if not reach(id, p, 1.0, 7000) then return end
            face(veh)
        end
    else
        for a = 0, 3 do
            local p = GetOffsetFromEntityInWorldCoords(ped, math.cos(a * math.pi / 2) * 1.2, math.sin(a * math.pi / 2) * 1.2, 0.0)
            go(p, 1.0)
            if not reach(id, p, 0.8, 5000) then return end
            face(ped)
        end
    end
    sniffed = nil
    TriggerServerEvent('lwk_k9:sniff', ped ~= 0 and tonumber(what) or nil)
    local t = GetGameTimer() + 5000
    while sniffed == nil and GetGameTimer() < t do Wait(100) end
    if job ~= id or not Dog then return end
    if not sniffed then
        card('info', 'K9: no alert', ('%s found nothing.'):format(DogName()))
        return Heel()
    end
    local who = sniffed.where == 'person' and ent(sniffed.net) or 0
    if who ~= 0 then
        local p = GetOffsetFromEntityInWorldCoords(who, 0.0, 0.9, 0.0)
        go(p, 1.0)
        if not reach(id, p, 0.8, 6000) then return end
        face(who)
    elseif veh ~= 0 and BONE[sniffed.where] then
        local r = BONE[sniffed.where]
        local p = beside(veh, r[2], r[3])
        go(p, 1.0)
        if not reach(id, p, 0.8, 7000) then return end
        face(veh)
    end
    play('sit')
    mode = 'sit'
    card('alert', 'K9 alert', ('%s sat: %s.'):format(DogName(), Config.Where[sniffed.where] or sniffed.where), 10000)
end

-- ─── Attack ──────────────────────────────────────────────────────────────────
local function attack(net)
    net = tonumber(net)
    local ped = ent(net)
    if not Dog or not police() or ped == 0 or IsPedAPlayer(ped) or IsEntityDead(ped) then return end
    if in_car then GetOut() end
    job = job + 1
    local id = job
    mode = 'busy'
    ClearPedTasks(Dog)
    ClearEntityLastDamageEntity(ped)
    TaskCombatPed(Dog, ped, 0, 16)
    card('info', 'K9', ('%s is after them.'):format(DogName()), 4000)
    local function floor() -- (a bite, not a mauling)
        if NetworkHasControlOfEntity(ped) and GetEntityHealth(ped) < Config.Bite.min_health then SetEntityHealth(ped, Config.Bite.min_health) end
    end
    local t, got = GetGameTimer() + 30000, false
    while job == id and Dog and GetGameTimer() < t and DoesEntityExist(ped) and not IsEntityDead(ped) do
        floor()
        if #(GetEntityCoords(Dog) - GetEntityCoords(ped)) < 2.5
            and (IsPedRagdoll(ped) or HasEntityBeenDamagedByEntity(ped, Dog, true)) then got = true break end
        if #(GetEntityCoords(Dog) - GetEntityCoords(PlayerPedId())) > Config.Bite.range then break end
        Wait(100)
    end
    if job ~= id or not Dog then return end
    if got then
        local ms = Config.Bite.hold_seconds * 1000
        if NetworkHasControlOfEntity(ped) then SetPedToRagdoll(ped, ms, ms, 0, false, false, false) end -- (down: c3r's chase has them give up)
        TriggerServerEvent('lwk_k9:bit', net)
        card('ok', 'K9 apprehension', ('%s has them. Go and cuff them.'):format(DogName()), 8000)
        local h = GetGameTimer() + ms
        while job == id and GetGameTimer() < h do floor() Wait(100) end
    else
        card('info', 'K9', ('%s was called off.'):format(DogName()), 4000)
    end
    if job == id then Heel() end
end

-- ─── Track ───────────────────────────────────────────────────────────────────
-- Everyone who runs from a stop: their route, kept while their ped is about (it's what the dog follows).
CreateThread(function()
    while true do
        Wait(1000)
        if Dog and police() then
            local now = GetGameTimer()
            for _, r in ipairs(exports.c3r:getRunners() or {}) do
                runners[r.net] = runners[r.net] or { ped = r.ped, trail = {} }
                runners[r.net].ped = r.ped
            end
            for net, r in pairs(runners) do
                if DoesEntityExist(r.ped) and not IsEntityDead(r.ped) then
                    local p, last = GetEntityCoords(r.ped), r.trail[#r.trail]
                    if not last or #(p - last) > 2.0 then
                        r.trail[#r.trail + 1], r.seen = p, now
                        if #r.trail > 600 then table.remove(r.trail, 1) end
                    end
                    r.seen = r.seen or now
                end
                if now - (r.seen or now) > Config.Track.minutes * 60000 then runners[net] = nil end
            end
        end
    end
end)

local trail_in -- the server's: { id, points }
RegisterNetEvent('lwk_k9:trail', function(pid, pts) trail_in = { id = pid, points = pts } end)
RegisterNetEvent('lwk_k9:scents', function(list) scents = type(list) == 'table' and list or {} end)
CreateThread(function()
    while true do
        Wait(5000)
        if Dog and police() then TriggerServerEvent('lwk_k9:scents') end
    end
end)

local function player_trail(pid)
    trail_in = nil
    TriggerServerEvent('lwk_k9:trail', pid)
    local t = GetGameTimer() + 3000
    while not trail_in and GetGameTimer() < t do Wait(100) end
    local out = {}
    for _, p in ipairs(trail_in and trail_in.points or {}) do out[#out + 1] = vector3(p[1], p[2], p[3]) end
    return out
end

-- what: 'n:<net>' (a runner) or 'p:<server id>' (a player). The dog leads, waits for you, and stops at them.
local function track(what)
    if not Dog or not police() then return end
    local kind, key = tostring(what):match('^(%a):(%d+)$')
    key = tonumber(key)
    if not key then return end
    if in_car then GetOut() end
    job = job + 1
    local id = job
    mode = 'busy'
    local r = kind == 'n' and runners[key]
    local function points() if r then return r.trail end return player_trail(key) end
    local function target()
        if r then return DoesEntityExist(r.ped) and r.ped or nil end
        local pl = GetPlayerFromServerId(key)
        return pl ~= -1 and GetPlayerPed(pl) or nil
    end
    card('info', 'K9', ('%s has the scent.'):format(DogName()), 4000)
    local me = PlayerPedId()
    local pts, i, refreshed = points(), 1, GetGameTimer()
    local best = math.huge -- start from the bit of trail nearest the dog
    for j, p in ipairs(pts) do local d = #(p - GetEntityCoords(Dog)) if d < best then best, i = d, j end end
    local give_up = GetGameTimer() + 5 * 60000
    while job == id and Dog and GetGameTimer() < give_up do
        local tgt = target()
        if tgt and #(GetEntityCoords(Dog) - GetEntityCoords(tgt)) < 3.0 then
            play('bark')
            mode = 'sit'
            return card('ok', 'K9', ('%s found them.'):format(DogName()), 8000)
        end
        if #(GetEntityCoords(Dog) - GetEntityCoords(me)) > Config.Track.wait_for then -- (waits for the handler)
            ClearPedTasks(Dog)
            TaskTurnPedToFaceEntity(Dog, me, 1000)
            Wait(1000)
        else
            local p = pts[i] or (tgt and GetEntityCoords(tgt))
            if not p then
                card('info', 'K9', ('%s lost the scent.'):format(DogName()), 5000)
                return Heel()
            end
            go(p, 2.0)
            reach(id, p, 1.8, 4000)
            if pts[i] then i = i + 1 end
            if not r and GetGameTimer() - refreshed > 5000 then -- (a player keeps moving: the fresh trail from here)
                pts, i, refreshed = points(), 1, GetGameTimer()
            end
        end
    end
    if job == id then Heel() end
end

-- ─── the wheel ───────────────────────────────────────────────────────────────
local ROLE = { driver = 'Driver', passenger = 'Passenger', pedestrian = 'Person' }
local function stop_people(stop)
    local by = {}
    for _, p in ipairs(stop and stop.people or {}) do by[p.net] = p end
    return by
end

-- One target: the option does it. Several: it opens a level to pick from. None: greyed, saying why.
local function pick(levels, key, label, icon, desc, list, why)
    if #list == 0 then return { label = label, icon = icon, desc = desc, off = why } end
    if #list == 1 then return { label = label, icon = icon, desc = desc, action = key, arg = list[1].arg } end
    local items = {}
    for _, t in ipairs(list) do items[#items + 1] = { label = t.label, icon = icon, action = key, arg = t.arg } end
    levels[key] = { title = label, items = items }
    return { label = label, icon = icon, desc = desc, to = key }
end

local function ago(s) return s < 60 and 'just now' or ('%d min ago'):format(s // 60) end

local function slice()
    local levels, root = {}, {}
    if not Dog then
        root[1] = { label = ('Call %s'):format(DogName()), icon = 'paw', action = 'spawn', desc = 'Your dog comes out to you.' }
        root[2] = { label = 'Dog options', icon = 'more', action = 'options', desc = 'Breed, name and look.' }
    else
        root[#root + 1] = { label = in_car and 'Out of the car' or 'Heel', icon = 'follow', action = 'heel', desc = 'Come to you and follow.' }
        root[#root + 1] = { label = 'Sit', icon = 'paw', action = 'sit', off = in_car and 'In the car' or nil }
        root[#root + 1] = { label = 'Down', icon = 'hand', action = 'down', off = in_car and 'In the car' or nil }
        root[#root + 1] = { label = 'Speak', icon = 'talk', action = 'speak', off = in_car and 'In the car' or nil }
        root[#root + 1] = { label = in_car and 'Out of the car' or 'In the car', icon = in_car and 'out' or 'in', action = 'car' }
        if police() then
            local stop = exports.c3r:getStop()
            local people, me = stop_people(stop), GetEntityCoords(PlayerPedId())
            local sniffs = {}
            if stop and ent(stop.veh_net, true) ~= 0 and #(GetEntityCoords(ent(stop.veh_net, true)) - me) < 25.0 then
                sniffs[1] = { label = 'Vehicle', arg = 'car' }
            end
            for net, p in pairs(people) do
                local ped = ent(net)
                if (p.out or p.role == 'pedestrian') and ped ~= 0 and #(GetEntityCoords(ped) - me) < 20.0 then
                    sniffs[#sniffs + 1] = { label = ROLE[p.role] or 'Person', arg = net }
                end
            end
            root[#root + 1] = pick(levels, 'sniff', 'Sniff', 'search', 'Sniff the stop: it sits where it smells something.',
                                   sniffs, 'No stop near')
            local runs = {}
            for _, r in ipairs(exports.c3r:getRunners() or {}) do
                if #(GetEntityCoords(r.ped) - me) < Config.Bite.range then
                    runs[#runs + 1] = { label = (people[r.net] and ROLE[people[r.net].role] or 'Runner'), arg = r.net }
                end
            end
            root[#root + 1] = pick(levels, 'attack', 'Attack', 'warn', 'Send it after whoever is running.', runs, 'Nobody running')
            local tracks, now = {}, GetGameTimer()
            for net, r in pairs(runners) do
                if #r.trail > 0 then tracks[#tracks + 1] = { label = ('Runner, %s'):format(ago((now - (r.seen or now)) // 1000)), arg = 'n:' .. net } end
            end
            for _, s in ipairs(scents) do tracks[#tracks + 1] = { label = ('Scent, %s'):format(ago(s.age)), arg = 'p:' .. s.id } end
            root[#root + 1] = pick(levels, 'track', 'Track', 'walk', "Follow someone's trail.", tracks, 'No scent here')
        end
        root[#root + 1] = { label = 'Dog options', icon = 'more', action = 'options' }
        root[#root + 1] = { label = 'Dismiss', icon = 'wave', action = 'dismiss', desc = 'Send it home.' }
    end
    levels.k9 = { title = DogName(), items = root }
    return { label = 'K9', icon = 'paw', desc = 'Your dog.', root = 'k9', levels = levels }
end

CreateThread(function()
    while true do
        if Dog and (not DoesEntityExist(Dog) or IsEntityDead(Dog)) then
            card('alert', 'K9', ('%s is down.'):format(DogName()))
            if DoesEntityExist(Dog) then SetEntityAsNoLongerNeeded(Dog) end
            Dog, mode, in_car = nil, nil, nil
        end
        if in_car and Dog and not IsPedInAnyVehicle(Dog, false) then in_car, mode = nil, nil end
        local ok, err = pcall(function() exports.c3r:setRadialSlice('k9', slice()) end) -- (c3r restarting: next time)
        if not ok then log(err) end
        Wait(500)
    end
end)

local DO = {
    spawn = Spawn, heel = Heel, sit = function() stay('sit') end, down = function() stay('down') end, speak = speak,
    car = function() if Dog then car() end end, sniff = sniff, attack = attack, track = track, dismiss = Dismiss,
    options = function() OpenOptions() end,
}
local function run(action, arg)
    local f = DO[action]
    if f then CreateThread(function() f(arg) end) end
end
AddEventHandler('c3r:radial', function(id, action, arg) if id == 'k9' then run(action, arg) end end)

-- ─── keys ────────────────────────────────────────────────────────────────────
local function key_name(cmd, fallback)
    local s = GetControlInstructionalButton(0, (GetHashKey(cmd) | 0x80000000) & 0xFFFFFFFF, true)
    return type(s) == 'string' and s:match('^t_(.+)$') or fallback
end

RegisterCommand('+lwk_k9_wheel', function() exports.c3r:openRadial('k9', key_name('+lwk_k9_wheel', Config.Keys.wheel)) end, false)
RegisterCommand('-lwk_k9_wheel', function() end, false)
RegisterKeyMapping('+lwk_k9_wheel', 'K9 wheel (lwk_k9)', 'keyboard', Config.Keys.wheel or '')

for _, k in ipairs({ { 'heel', 'K9: heel / out of the car' }, { 'sit', 'K9: sit' }, { 'down', 'K9: down' },
                     { 'speak', 'K9: speak' }, { 'car', 'K9: in / out of the car' }, { 'options', 'K9: dog options' } }) do
    RegisterCommand('lwk_k9_' .. k[1], function() run(k[1]) end, false)
    RegisterKeyMapping('lwk_k9_' .. k[1], k[2] .. ' (lwk_k9)', 'keyboard', Config.Keys[k[1]] or '')
end
RegisterCommand('k9', function() run('options') end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Dog and DoesEntityExist(Dog) then DeleteEntity(Dog) end
    pcall(function() exports.c3r:setRadialSlice('k9', nil) end)
end)
