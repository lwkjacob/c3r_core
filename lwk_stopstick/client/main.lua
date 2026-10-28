local A, T = Config.Anim, Config.Text
local me = GetPlayerServerId(PlayerId())

-- Every prop is a local object of a model streamed by this resource, tracked and deleted on resource stop: a
-- model still alive when its .ytyp is unregistered on restart crashes the game (same rule as lwk_taser).
local spawned = {}

local function spawnProp(model, at)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end
    local p = CreateObject(model, at.x, at.y, at.z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityCollision(p, false, false)
    spawned[p] = true
    return p
end

local function despawn(p)
    if not p then return end
    spawned[p] = nil
    if DoesEntityExist(p) then DeleteEntity(p) end
end

local function loadDict(d)
    RequestAnimDict(d)
    while not HasAnimDictLoaded(d) do Wait(0) end
end

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end
RegisterNetEvent('lwk_stopstick:notify', notify)

local function help(msg)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

-- the key the player bound to one of our commands, as text ("G"). ~INPUT_<hash>~ icons don't resolve for key
-- mappings in help text, so ask for the button name and fall back to the config default
local function key(cmd, default)
    local h = (joaat(cmd) | 0x80000000) & 0xFFFFFFFF
    if h >= 0x80000000 then h = h - 0x100000000 end -- natives take a signed int
    local s = GetControlInstructionalButton(0, h, true)
    return '~y~' .. ((s and s:sub(1, 2) == 't_') and s:sub(3) or default) .. '~s~'
end

local function holdOf(sid) return Player(sid).state.stopstick end
local function myHold() return LocalPlayer.state.stopstick end

local function playing(ped, clip) return IsEntityPlayingAnim(ped, A.dict, clip, 3) end

-- ---------------------------------------------------------------- props in hands (everyone, from the state bag)
local held = {} -- [serverId] = { ped, pack, reel }
local released = false -- own pack already left the hand (the server state catches up a moment later)
local releasedAt = 0

local function attach(p, ped, a)
    AttachEntityToEntity(p, ped, GetPedBoneIndex(ped, a.bone), a.offset.x, a.offset.y, a.offset.z, a.rot.x, a.rot.y, a.rot.z,
        false, false, false, false, 2, true)
end

local function want(h, slot, ped, model, on)
    if on and not (h[slot] and DoesEntityExist(h[slot]) and IsEntityAttachedToEntity(h[slot], ped)) then
        despawn(h[slot])
        h[slot] = spawnProp(model, GetEntityCoords(ped))
        attach(h[slot], ped, Config.Attach[slot])
    elseif not on and h[slot] then
        despawn(h[slot]); h[slot] = nil
    end
end

CreateThread(function()
    while true do
        local seen = {}
        for _, pl in ipairs(GetActivePlayers()) do
            local sid, ped = GetPlayerServerId(pl), GetPlayerPed(pl)
            local st = holdOf(sid)
            if sid == me and (not (st and st.s == 'carry') or GetGameTimer() - releasedAt > 2000) then released = false end -- or the server refused the throw
            if st or held[sid] then
                seen[sid] = true
                local h = held[sid] or {}
                held[sid] = h
                local onFoot = not IsPedInAnyVehicle(ped, false)
                want(h, 'pack', ped, Config.Props.folded, st and st.s == 'carry' and onFoot and not (sid == me and released))
                want(h, 'reel', ped, Config.Props.reel, st and st.s == 'cord' and onFoot)
                h.ped = ped
            end
        end
        for sid, h in pairs(held) do
            if not seen[sid] then despawn(h.pack); despawn(h.reel); held[sid] = nil end
        end
        Wait(200)
    end
end)

-- ---------------------------------------------------------------- sticks on the road: 3 sticks on a physics chain
local sticks = {} -- [id] = { id, owner, c (chain), z, land, from, flight, t0, props, seg, folded, unfurl, sim }

local function now() return GetGameTimer() end

local function add(d)
    sticks[d.id] = { id = d.id, owner = d.owner, c = d.c, z = d.z, land = d.land, from = d.from, flight = d.flight, t0 = now() - d.age }
end

local function drop(id)
    local s = sticks[id]
    if not s then return end
    for _, p in ipairs(s.props or {}) do despawn(p) end
    despawn(s.folded)
    sticks[id] = nil
end

RegisterNetEvent('lwk_stopstick:spawn', add)
RegisterNetEvent('lwk_stopstick:remove', drop)
RegisterNetEvent('lwk_stopstick:sync', function(list) for _, d in ipairs(list) do drop(d.id); add(d) end end)
RegisterNetEvent('lwk_stopstick:cord', function(id, owner) if sticks[id] then sticks[id].owner = owner end end)
RegisterNetEvent('lwk_stopstick:yank', function(id, dx, dy, dist, start)
    local s = sticks[id]
    if not s then return end
    s.c = start -- everyone starts from the server's resting chain, steps the same physics, ends in the same place
    if s.props then s.sim, s.simT, s.unfurl = StopStickYankStart(start, dx, dy, dist), now(), nil end
end)
TriggerServerEvent('lwk_stopstick:sync')

local function landed(s) return s.props ~= nil end

local function center(s)
    local x, y = StopStickCenter(s.c)
    return vec3(x, y, s.z)
end

-- put the 3 stick props on the chain's joints, each on the road under its middle; remembers them for the wheel test
local function place(s, c)
    s.seg = s.seg or {}
    for i = 1, 3 do
        local ax, ay, bx, by = c.x[i], c.y[i], c.x[i + 1], c.y[i + 1]
        local mx, my = (ax + bx) / 2.0, (ay + by) / 2.0
        local ok, gz = GetGroundZFor_3dCoord(mx, my, s.z + 1.0, false)
        local z = ok and gz or s.z
        SetEntityCoordsNoOffset(s.props[i], mx, my, z, false, false, false)
        SetEntityHeading(s.props[i], math.deg(math.atan(by - ay, bx - ax))) -- entity heading = angle of the prop's +X axis
        s.seg[i] = { ax, ay, bx, by, z }
    end
end

local function wrap(a) return (a + 180.0) % 360.0 - 180.0 end

local function flightStep(s, t)
    -- folded pack on a lob from the release point, rolling once about its length, coming down where stick A lies
    local k = t / s.flight
    if k < 1.0 then
        local d = #(s.land.xy - s.from.xy)
        if not s.folded then s.folded = spawnProp(Config.Props.folded, s.from) end
        local p = s.from + (s.land - s.from) * k + vec3(0.0, 0.0, 4.0 * (0.5 + 0.05 * d) * k * (1.0 - k))
        local h = math.deg(math.atan(s.c.y[2] - s.c.y[1], s.c.x[2] - s.c.x[1]))
        SetEntityCoordsNoOffset(s.folded, p.x, p.y, p.z, false, false, false)
        SetEntityRotation(s.folded, 360.0 * k, 0.0, h, 2, true) -- entity heading = angle of the prop's +X axis
        return
    end
    despawn(s.folded); s.folded = nil
    s.props = {}
    for i, m in ipairs(Config.Props.sticks) do s.props[i] = spawnProp(m, s.land) end
    s.unfurl = now()
end

-- landing: B swings out from over A, C from over B (folded accordion -> the chain the server laid out)
local function unfurlStep(s)
    local k = math.min((now() - s.unfurl) / 350.0, 1.0)
    local e = 1.0 - (1.0 - k) ^ 3
    local c = s.c
    local a = {}
    for i = 1, 3 do a[i] = math.deg(math.atan(c.y[i + 1] - c.y[i], c.x[i + 1] - c.x[i])) end
    local r2, r3 = 179.0 + (wrap(a[2] - a[1]) - 179.0) * e, -179.0 + (wrap(a[3] - a[2]) + 179.0) * e
    place(s, k < 1.0 and StopStickChain(c.x[1], c.y[1], { a[1], a[1] + r2, a[1] + r2 + r3 }) or c)
    if k >= 1.0 then s.unfurl = nil end
end

-- yank: fixed steps on the clock since it arrived, exactly as the server ran them
local function simStep(s)
    local want = math.floor((now() - s.simT) / 1000.0 / StopStickDT)
    local done = false
    while s.sim.n < want and not done do done = StopStickYankStep(s.sim) end
    place(s, s.sim)
    if done then s.c, s.sim = { x = s.sim.x, y = s.sim.y }, nil end
end

-- cord: reel -> (right fist, while the pull clip holds the ready pose / pulls) -> the stick's grommet
local function drawCord(s)
    local pl = s.owner and GetPlayerFromServerId(s.owner) or -1
    if pl == -1 then return end
    local ped = GetPlayerPed(pl)
    local h = held[s.owner]
    local a = (h and h.reel and DoesEntityExist(h.reel)) and GetOffsetFromEntityInWorldCoords(h.reel, Config.CordExit.x, Config.CordExit.y, Config.CordExit.z)
        or GetPedBoneCoords(ped, Config.Attach.reel.bone, 0.0, 0.0, 0.0)
    local e = s.seg and vec3(s.seg[1][1], s.seg[1][2], s.seg[1][5] + 0.01) or GetEntityCoords(s.folded or 0) -- cord end
    local c = 25
    if playing(ped, A.pull) then
        local fist = GetPedBoneCoords(ped, Config.Attach.pack.bone, 0.0, 0.0, 0.0)
        DrawLine(a.x, a.y, a.z, fist.x, fist.y, fist.z, c, c, c, 255)
        a = fist
        if s.sim or GetEntityAnimCurrentTime(ped, A.dict, A.pull) < 0.95 then -- yanking: taut
            return DrawLine(a.x, a.y, a.z, e.x, e.y, e.z, c, c, c, 255)
        end
    end
    -- slack: drops from the hand to the road about a metre out, then lies along it
    local v = e - a
    local g = a + v * math.min(1.2 / math.max(#v.xy, 0.01), 1.0)
    g = vec3(g.x, g.y, e.z)
    DrawLine(a.x, a.y, a.z, g.x, g.y, g.z, c, c, c, 255)
    DrawLine(g.x, g.y, g.z, e.x, e.y, e.z, c, c, c, 255)
end

-- ---------------------------------------------------------------- wheels: the vehicle's owner bursts its own tyres
local WHEELS = { { 'wheel_lf', 0 }, { 'wheel_rf', 1 }, { 'wheel_lm1', 2 }, { 'wheel_rm1', 3 }, { 'wheel_lr', 4 }, { 'wheel_rr', 5 } }
local near = {} -- [veh] = { bones = { {bi, tyre} }, prev = {} }

local function segDist(p1, p2, q1, q2) -- shortest distance between two segments, on the ground plane (x, y only)
    local function cross(o, a, b) return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) end
    local d1, d2, d3, d4 = cross(q1, q2, p1), cross(q1, q2, p2), cross(p1, p2, q1), cross(p1, p2, q2)
    if d1 * d2 < 0 and d3 * d4 < 0 then return 0.0 end
    local function pt(p, a, b)
        local abx, aby = b.x - a.x, b.y - a.y
        local l2 = abx * abx + aby * aby
        local t = l2 > 0 and math.max(0.0, math.min(1.0, ((p.x - a.x) * abx + (p.y - a.y) * aby) / l2)) or 0.0
        local dx, dy = a.x + abx * t - p.x, a.y + aby * t - p.y
        return math.sqrt(dx * dx + dy * dy)
    end
    return math.min(pt(p1, q1, q2), pt(p2, q1, q2), pt(q1, p1, p2), pt(q2, p1, p2))
end

CreateThread(function() -- every 250 ms: which vehicles I own are close to a stick on the road
    while true do
        local any = {}
        for _, s in pairs(sticks) do if landed(s) then any[#any + 1] = center(s) end end
        local found = {}
        if #any > 0 then
            local myId = PlayerId()
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                if NetworkGetEntityOwner(veh) == myId then
                    local c = GetEntityCoords(veh)
                    for _, p in ipairs(any) do
                        if #(c - p) < 40.0 then found[veh] = true break end
                    end
                end
            end
        end
        for veh in pairs(near) do if not found[veh] then near[veh] = nil end end
        for veh in pairs(found) do
            if not near[veh] then
                local b = {}
                for _, w in ipairs(WHEELS) do
                    local bi = GetEntityBoneIndexByName(veh, w[1])
                    if bi ~= -1 then b[#b + 1] = { bi, w[2] } end
                end
                near[veh] = { bones = b, prev = {}, hit = {} }
            end
        end
        Wait(250)
    end
end)

local function testWheels(lines)
    for veh, n in pairs(near) do
        if DoesEntityExist(veh) then
            for i, b in ipairs(n.bones) do
                local p = GetWorldPositionOfEntityBone(veh, b[1])
                local q = n.prev[i]
                n.prev[i] = p
                if q then
                    if Config.Debug then DrawLine(q.x, q.y, q.z, p.x, p.y, p.z, 0, 255, 0, 255) end
                    for _, l in ipairs(lines) do
                        -- swept: the path the wheel took since last frame against the stick, so 160 km/h can't skip it
                        if math.abs(p.z - l.z) < 1.0 and segDist(q, p, l.a, l.b) <= Config.HitWidth then
                            if not IsVehicleTyreBurst(veh, b[2], false) then
                                SetVehicleTyreBurst(veh, b[2], Config.BurstToRim, 1000.0)
                                n.hit[l.id] = n.hit[l.id] or {}
                                table.insert(n.hit[l.id], b[2])
                            end
                        end
                    end
                end
            end
            for id, tyres in pairs(n.hit) do -- one report per stick and vehicle pass
                if #tyres > 0 then
                    local model = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
                    local label = GetLabelText(model)
                    TriggerServerEvent('lwk_stopstick:hit', id, NetworkGetEntityIsNetworked(veh) and VehToNet(veh) or nil, tyres,
                        label ~= 'NULL' and label or model)
                    n.hit[id] = {}
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- per frame: flights, drags, cords, wheels, pickup
local function nearestStick(pos, max)
    local best, bd
    for _, s in pairs(sticks) do
        if landed(s) and not s.sim and not s.unfurl then
            local d = #(center(s).xy - pos.xy)
            if d < max and (not bd or d < bd) then best, bd = s, d end
        end
    end
    return best
end

CreateThread(function()
    while true do
        if not next(sticks) then
            Wait(300)
        else
            Wait(0)
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local lines = {}
            for _, s in pairs(sticks) do
                local t = (now() - s.t0) / 1000.0
                if not landed(s) then
                    flightStep(s, t)
                elseif s.unfurl then
                    unfurlStep(s)
                elseif s.sim then
                    simStep(s)
                end
                if s.owner and #(center(s) - pos) < Config.DrawDistance then drawCord(s) end
                for _, g in ipairs(landed(s) and s.seg or {}) do -- every stick of the chain bursts tyres
                    lines[#lines + 1] = { id = s.id, a = vec2(g[1], g[2]), b = vec2(g[3], g[4]), z = g[5] }
                    if Config.Debug then DrawLine(g[1], g[2], g[5] + 0.05, g[3], g[4], g[5] + 0.05, 255, 0, 0, 255) end
                end
            end
            if next(near) then testWheels(lines) end

            local h = myHold()
            local s = not IsPedInAnyVehicle(ped, false) and nearestStick(pos, 2.0)
            if s and (not h or (h.s == 'cord' and h.id == s.id)) then
                help(T.pickup)
                if IsControlJustPressed(0, 38) then
                    loadDict('pickup_object')
                    TaskPlayAnim(ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 1000, 48, 0.0, false, false, false)
                    TriggerServerEvent('lwk_stopstick:pickup', s.id)
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------- own hands: aim, throw, pull, ready pose
local busy, aim, cordCheck = false, nil, 0

local function aimPoint(ped)
    local c = GetFinalRenderedCamCoord()
    local r = GetFinalRenderedCamRot(2)
    local x, z = math.rad(r.x), math.rad(r.z)
    local dir = vec3(-math.sin(z) * math.abs(math.cos(x)), math.cos(z) * math.abs(math.cos(x)), math.sin(x))
    local far = c + dir * 40.0
    local _, hit, p = GetShapeTestResult(StartExpensiveSynchronousShapeTestLosProbe(c.x, c.y, c.z, far.x, far.y, far.z, 1, ped, 7))
    if hit ~= 1 and hit ~= true then return end
    local me = GetEntityCoords(ped)
    local v = p.xy - me.xy
    local d = #v
    if d < 0.1 then return end
    d = math.max(Config.ThrowMin, math.min(Config.ThrowRange, d))
    local t = me.xy + v / #v * d
    local ok, gz = GetGroundZFor_3dCoord(t.x, t.y, me.z + 2.0, false)
    return vec3(t.x, t.y, ok and gz or me.z - 1.0)
end

local function throw(ped)
    if not aim or IsPedInAnyVehicle(ped, false) then return end
    local target = aim
    busy = true
    local me = GetEntityCoords(ped)
    SetEntityHeading(ped, GetHeadingFromVector_2d(target.x - me.x, target.y - me.y))
    loadDict(A.dict)
    TaskPlayAnim(ped, A.dict, A.throw, 4.0, -4.0, -1, 48, 0.0, false, false, false)
    local started = now()
    while now() - started < 3000 do -- release on the clip's own clock, not a timer
        Wait(0)
        if playing(ped, A.throw) then
            if GetEntityAnimCurrentTime(ped, A.dict, A.throw) >= A.release then
                local p = held[me] and held[me].pack
                local from = (p and DoesEntityExist(p)) and GetEntityCoords(p) or GetPedBoneCoords(ped, Config.Attach.pack.bone, 0.0, 0.0, 0.0)
                released, releasedAt = true, now()
                want(held[me] or {}, 'pack', ped, Config.Props.folded, false)
                TriggerServerEvent('lwk_stopstick:throw', from, target)
                break
            end
        elseif now() - started > 500 then
            break -- interrupted (ragdoll, vehicle...): keep the pack
        end
    end
    busy = false
end

-- one press, one yank: the full pull clip; the stick goes the moment the hand starts hauling
local function yank(ped)
    local h = myHold()
    local s = h and sticks[h.id]
    if not s or not landed(s) or s.sim or s.unfurl then return end
    busy = true
    loadDict(A.dict)
    if playing(ped, A.pull) then StopAnimTask(ped, A.dict, A.pull, 8.0); Wait(0) end -- restart from the reach, not the held end
    TaskPlayAnim(ped, A.dict, A.pull, 8.0, -4.0, -1, 50, 0.0, false, false, false) -- ends on (and holds) the ready pose
    local started, sent = now(), false
    while now() - started < 2000 do
        Wait(0)
        local t = playing(ped, A.pull) and GetEntityAnimCurrentTime(ped, A.dict, A.pull) or 1.0
        if not sent and t >= A.yank then
            TriggerServerEvent('lwk_stopstick:yank')
            sent = true
        end
        if sent and t >= 0.8 then break end
    end
    busy = false
end

local function cmd(name, keyName, desc, fn)
    RegisterCommand(name, function() fn(PlayerPedId()) end, false)
    RegisterKeyMapping(name, desc, 'keyboard', keyName) -- '' = listed in the key bindings menu, unbound
end

cmd('+stopstick_use', Config.Keys.use, 'Stop Stick: throw / yank the cord', function(ped)
    local h = myHold()
    if busy or not h then return end
    if h.s == 'carry' then throw(ped) else yank(ped) end
end)
RegisterCommand('-stopstick_use', function() end, false) -- key-up of the +command

cmd('stopstick_release', Config.Keys.release, 'Stop Stick: let go of the cord', function()
    local h = myHold()
    if h and h.s == 'cord' then TriggerServerEvent('lwk_stopstick:release') end
end)

-- vehicles that carry sticks
local function carrier(veh)
    if veh == 0 or not DoesEntityExist(veh) then return false end
    if next(Config.Vehicles) then
        local m = GetEntityModel(veh)
        for _, n in ipairs(Config.Vehicles) do if m == joaat(n) then return true end end
        return false
    end
    return GetVehicleClass(veh) == 18
end

local function nearestCarrier(ped)
    local me, best, bd = GetEntityCoords(ped), nil, 6.0
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(veh) - me)
        if d < bd and carrier(veh) then best, bd = veh, d end
    end
    return best
end

local function net(veh) return veh and NetworkGetEntityIsNetworked(veh) and VehToNet(veh) or nil end

cmd('stopstick', Config.Keys.take, 'Stop Stick: take out / put away', function(ped)
    local h, mode = myHold(), GlobalState.stopstickSource
    if h and h.s == 'cord' then return notify(T.hands_full) end
    local veh = mode == 'vehicle' and nearestCarrier(ped)
    if mode == 'vehicle' and not veh then return notify(T.no_vehicle) end
    if h then return TriggerServerEvent('lwk_stopstick:stow', net(veh)) end
    if mode == 'item' then return notify(T.use_item) end
    TriggerServerEvent('lwk_stopstick:take', net(veh))
end)

CreateThread(function() -- boot options on emergency vehicles
    if GlobalState.stopstickSource ~= 'vehicle' or GetResourceState('ox_target') ~= 'started' then return end
    exports.ox_target:addGlobalVehicle({
        { name = 'lwk_stopstick_take', icon = 'fa-solid fa-road-spikes', label = T.take, bones = { 'boot' }, distance = 2.0,
          canInteract = function(veh) return not myHold() and carrier(veh) end,
          onSelect = function(d) TriggerServerEvent('lwk_stopstick:take', net(d.entity)) end },
        { name = 'lwk_stopstick_stow', icon = 'fa-solid fa-box', label = T.stow, bones = { 'boot' }, distance = 2.0,
          canInteract = function(veh) local h = myHold() return h and h.s == 'carry' and carrier(veh) end,
          onSelect = function(d) TriggerServerEvent('lwk_stopstick:stow', net(d.entity)) end },
    })
end)

CreateThread(function() -- aim marker while carrying; ready pose + cord limits while holding the cord
    while true do
        local ped = PlayerPedId()
        local h = myHold()
        local onFoot = not IsPedInAnyVehicle(ped, false)
        if h and h.s == 'carry' and onFoot and not busy then
            Wait(0)
            if not playing(ped, A.carry) and not playing(ped, A.throw) then -- hand round the pack, arm relaxed at the side
                loadDict(A.dict)
                TaskPlayAnim(ped, A.dict, A.carry, 4.0, -4.0, -1, 49, 0.0, false, false, false) -- looped, upper body, can walk
            end
            aim = aimPoint(ped)
            if aim then
                local me = GetEntityCoords(ped)
                local v = aim.xy - me.xy
                local u = vec3(v.x, v.y, 0.0) / #v * Config.HalfLength
                local a, b = aim - u, aim + u
                DrawLine(a.x, a.y, aim.z + 0.03, b.x, b.y, aim.z + 0.03, 255, 90, 20, 200) -- where the sleeve will lie
                DrawMarker(25, aim.x, aim.y, aim.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 255, 90, 20, 120, false, false, 2, false, nil, nil, false)
            end
            help(T.hint_carry:format(key('+stopstick_use', Config.Keys.use)))
        elseif h and h.s == 'cord' then
            Wait(0)
            if onFoot and not busy then help(T.hint_cord:format(key('+stopstick_use', Config.Keys.use), key('stopstick_release', Config.Keys.release))) end
            local s = sticks[h.id]
            if GetGameTimer() >= cordCheck then -- the hint is drawn every frame, these checks every 100 ms
                cordCheck = GetGameTimer() + 100
                if not onFoot or (s and #(GetEntityCoords(ped).xy - center(s).xy) > Config.CordLength) then
                    if onFoot then notify(T.out_of_cord) end
                    TriggerServerEvent('lwk_stopstick:release')
                    cordCheck = GetGameTimer() + 500
                elseif not busy and not playing(ped, A.pull) then -- the pull clip's last frame is the ready pose
                    loadDict(A.dict)
                    TaskPlayAnim(ped, A.dict, A.pull, 4.0, -4.0, -1, 50, 0.999, false, false, false)
                end
            end
        else
            if playing(ped, A.pull) then StopAnimTask(ped, A.dict, A.pull, 2.0) end
            if playing(ped, A.carry) and not (h and h.s == 'carry') then StopAnimTask(ped, A.dict, A.carry, 2.0) end
            aim = nil
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for p in pairs(spawned) do if DoesEntityExist(p) then DeleteEntity(p) end end
    local ped = PlayerPedId()
    StopAnimTask(ped, A.dict, A.pull, 2.0); StopAnimTask(ped, A.dict, A.throw, 2.0); StopAnimTask(ped, A.dict, A.carry, 2.0)
end)
