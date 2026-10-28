local weapons = {}
for name, cfg in pairs(Config.Weapons) do weapons[GetHashKey(name) & 0xFFFFFFFF] = cfg end

local equipped, laser, light = nil, true, false
local bays, device = {}, '-'

local function weaponCfg(ped) return weapons[GetSelectedPedWeapon(ped) & 0xFFFFFFFF] end

-- Every prop this resource spawns uses a model streamed by this resource. They are all tracked and deleted on
-- resource stop, and models are released right after spawning: an entity (or a loaded model) still alive when the
-- resource's .ytyp is unregistered on restart crashes the game.
local spawned = {}

-- a wrong model in config.lua (or a stream file that failed to load) used to hang the calling thread forever.
-- Returns 0 instead, which every caller tolerates; warned once per model
local warned = {}
local function spawnProp(model, at)
    local give = GetGameTimer() + 5000
    if IsModelInCdimage(model) then
        RequestModel(model)
        while not HasModelLoaded(model) and GetGameTimer() < give do Wait(0) end
    end
    if not HasModelLoaded(model) then
        if not warned[model] then
            warned[model] = true
            print(('[lwk_taser] model %s did not load: check config.lua and the stream/ folder'):format(model))
        end
        return 0
    end
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

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local function localSound(name) SendNUIMessage({ type = 'sound', name = name, vol = Config.Volume * 0.5, pan = 0.0 }) end

-- Live rear display: an off-screen DUI of nui/cid.html replaces the texture (taser10_cid) of the lwk_taser_screen
-- prop mounted on the gun. The page must load from https://cfx-nui-<resource>/: nui:// is no longer a secure context
-- and never loads, which left the screen black. ponytail: texture replacement is per model, so every TASER 10 near
-- you shows your CID; per-officer screens would need a screen model per player
local dui = CreateDui(('https://cfx-nui-%s/nui/cid.html'):format(GetCurrentResourceName()), 512, 208)
CreateRuntimeTextureFromDuiHandle(CreateRuntimeTxd('lwk_taser_cid'), 'cid', GetDuiHandle(dui))

-- the replacement is dropped whenever the screen's texture dictionary unloads: keep it requested, re-bind every spawn
local function bindScreen()
    RequestStreamedTextureDict('lwk_taser_screen')
    RemoveReplaceTexture('lwk_taser_screen', 'taser10_cid')
    AddReplaceTexture('lwk_taser_screen', 'taser10_cid', 'lwk_taser_cid', 'cid')
end
bindScreen()

local function screen(msg) SendDuiMessage(dui, json.encode(msg)) end

local function cid()
    local m = { type = 'cid', show = equipped ~= nil, bays = bays, laser = laser, light = light, device = device }
    SendNUIMessage(m)
    screen(m)
end

CreateThread(function() -- anything sent before the page finished loading was lost
    while not IsDuiAvailable(dui) do Wait(100) end
    Wait(500)
    cid()
end)

local function pushState()
    LocalPlayer.state:set('taser', equipped and { laser = laser, light = light } or nil, true)
end

local function ray(a, b, ignore)
    local _, hit, pos, _, ent = GetShapeTestResult(StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, 31, ignore, 7))
    return hit == 1 or hit == true, pos, ent
end

local function camDir()
    local r = GetFinalRenderedCamRot(2)
    local x, z = math.rad(r.x), math.rad(r.z)
    return vec3(-math.sin(z) * math.abs(math.cos(x)), math.cos(z) * math.abs(math.cos(x)), math.sin(x))
end

local function aimPoint(ped)
    local c = GetFinalRenderedCamCoord()
    local far = c + camDir() * 60.0
    local hit, pos = ray(c, far, ped)
    return hit and pos or far
end

-- Muzzle position + barrel direction for any ped holding a taser (works for custom models via config)
local function muzzle(ped, cfg)
    local w = GetCurrentPedWeaponEntityIndex(ped, 0)
    if w == 0 then return GetPedBoneCoords(ped, 57005, 0.15, 0.0, 0.0), GetEntityForwardVector(ped) end
    local base
    if cfg.muzzle then
        base = GetOffsetFromEntityInWorldCoords(w, cfg.muzzle.x, cfg.muzzle.y, cfg.muzzle.z)
    else
        local b = GetEntityBoneIndexByName(w, 'gun_muzzle')
        base = b ~= -1 and GetWorldPositionOfEntityBone(w, b) or GetEntityCoords(w)
    end
    local axis = cfg.axis or vec3(1.0, 0.0, 0.0)
    local dir = GetOffsetFromEntityInWorldCoords(w, axis.x, axis.y, axis.z) - GetEntityCoords(w)
    return base, dir / #dir
end

-- hit bone = nearest of these, so a barb hangs off a bone within a few cm and follows that limb (also when ragdolled)
local BONES = { 11816, 23553, 24816, 24817, 24818, 39317, 31086,   -- pelvis, spine 0-3, neck, head
                64729, 10706, 45509, 40269, 61163, 28252, 18905, 57005, -- clavicles, upper arms, forearms, hands
                58271, 51826, 63931, 36864, 14201, 52301 }               -- thighs, calves, feet
-- rough body radius around each bone (m). A standing ped is hit-tested against a big capsule, so the laser can
-- "hit" 20-30 cm off the skin; such hits get snapped onto this sphere along the shot line.
-- ponytail: spheres, not real limb shapes; good to a couple of cm, swap for per-bone capsules if that shows
local RADIUS = { [11816] = 0.15, [23553] = 0.16, [24816] = 0.17, [24817] = 0.17, [24818] = 0.16, [39317] = 0.07,
                 [31086] = 0.11, [64729] = 0.09, [10706] = 0.09, [45509] = 0.06, [40269] = 0.06, [61163] = 0.05,
                 [28252] = 0.05, [18905] = 0.05, [57005] = 0.05, [58271] = 0.09, [51826] = 0.09, [63931] = 0.07,
                 [36864] = 0.07, [14201] = 0.06, [52301] = 0.06 }

local function onBody(ent, bone, pos, dir)
    local c, r = GetPedBoneCoords(ent, bone, 0.0, 0.0, 0.0), (RADIUS[bone] or 0.1) * 0.85 -- err inside, never outside
    if #(pos - c) <= r + 0.03 then return pos end           -- already on the body (ragdoll bounds are tight)
    local t = (c.x - pos.x) * dir.x + (c.y - pos.y) * dir.y + (c.z - pos.z) * dir.z
    local near = pos + dir * t                               -- point on the shot line closest to the bone
    local v = near - c
    local d = #v
    if d < r then return near - dir * math.sqrt(r * r - d * d) end -- where the line enters the sphere
    return c + v / d * r                                     -- line passes beside it: graze the near side
end

local function nearestBone(ent, pos)
    local best, bd = 24817, math.huge
    for _, b in ipairs(BONES) do
        local d = #(GetPedBoneCoords(ent, b, 0.0, 0.0, 0.0) - pos)
        if d < bd then best, bd = b, d end
    end
    return best
end

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

-- World point + direction expressed in the frame AttachEntityToEntity uses for a ped bone, so a barb stays
-- where it hit and moves with the limb. That frame is read off an invisible marker attached to the bone itself
-- (GetPedBoneCoords' offset axes don't match it on every bone, which left barbs floating beside moving peds).
-- Must run in a thread: the marker's attach takes effect on the next frame.
local marker

-- the bone's orientation as GetPedBoneCoords' offsets see it (a fixed rotation away from the attach frame)
local function boneAxes(ent, bone)
    local c = GetPedBoneCoords(ent, bone, 0.0, 0.0, 0.0)
    return c, GetPedBoneCoords(ent, bone, 1.0, 0.0, 0.0) - c, GetPedBoneCoords(ent, bone, 0.0, 1.0, 0.0) - c,
        GetPedBoneCoords(ent, bone, 0.0, 0.0, 1.0) - c
end

-- shot = { rel = hit - bone (world), dir = shot dir (world), x/y/z = bone axes, all from the frame of the shot }
local function boneLocal(ent, bone, shot)
    if not (marker and DoesEntityExist(marker)) then
        marker = spawnProp(Config.BarbProp, GetEntityCoords(ent))
        SetEntityVisible(marker, false, false)
    end
    -- hit point and direction in the bone's own axes at the moment of the shot, so a limb that swings or turns
    -- while we measure (running) carries them along instead of leaving them behind
    local a = vec3(dot(shot.rel, shot.x), dot(shot.rel, shot.y), dot(shot.rel, shot.z))
    local ad = vec3(dot(shot.dir, shot.x), dot(shot.dir, shot.y), dot(shot.dir, shot.z))
    local function now() -- where the hit point / shot direction are this frame
        local c, x, y, z = boneAxes(ent, bone)
        return c + x * a.x + y * a.y + z * a.z, x * ad.x + y * ad.y + z * ad.z
    end
    local bi = GetPedBoneIndex(ent, bone)
    AttachEntityToEntity(marker, ent, bi, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    Wait(0)
    local o = GetOffsetFromEntityInWorldCoords(marker, 0.0, 0.0, 0.0)
    local x = GetOffsetFromEntityInWorldCoords(marker, 1.0, 0.0, 0.0) - o
    local y = GetOffsetFromEntityInWorldCoords(marker, 0.0, 1.0, 0.0) - o
    local z = GetOffsetFromEntityInWorldCoords(marker, 0.0, 0.0, 1.0) - o
    local function toLocal(v) return vec3(dot(v, x), dot(v, y), dot(v, z)) end
    local target, wdir = now()
    local off, ldir = toLocal(target - o), toLocal(wdir)
    -- close the loop: attach at the guess, see where the game really put it, correct, repeat
    local err = 0.0
    for _ = 1, 4 do
        AttachEntityToEntity(marker, ent, bi, off.x, off.y, off.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        Wait(0)
        target = now()
        local miss = target - GetEntityCoords(marker)
        err = #miss
        if err < 0.005 then break end
        off = off + toLocal(miss)
    end
    DetachEntity(marker, false, false)
    if Config.Debug then
        print(('[lwk_taser] barb placement error %.1f cm | hit %.1f cm from bone %d | ped speed %.1f m/s | ragdoll %s'):format(
            err * 100, #shot.rel * 100, bone, GetEntitySpeed(ent), tostring(IsPedRagdoll(ent))))
    end
    return off, ldir
end

local function fire(ped, cfg, aim) -- aim: world point to shoot at (lwk_cine), else the crosshair
    local bay
    for i = 1, #bays do if bays[i].s == 'live' then bay = i break end end
    if not bay then return localSound('click') end
    if IsEntityPlayingAnim(ped, Config.Reload.dict, Config.Reload.clip, 3) then return end -- mid cartridge swap

    local from = muzzle(ped, cfg)
    local dir = (aim or aimPoint(ped)) - from
    dir = dir / #dir
    local hit, pos, ent = ray(from, from + dir * Config.Range, ped)
    -- ponytail: un-networked peds count as a miss
    if not (hit and IsEntityAPed(ent) and NetworkGetEntityIsNetworked(ent)) then ent = 0 end
    if ent == 0 then return TriggerServerEvent('lwk_taser:fire', bay, 0, 0) end
    local bone = nearestBone(ent, pos)
    pos = onBody(ent, bone, pos, dir)
    -- hit vs bone in the same frame as the raycast: a running ped moves ~9 cm per frame
    local c, bx, by, bz = boneAxes(ent, bone)
    local shot = { rel = pos - c, dir = dir, x = bx, y = by, z = bz }
    local net = NetworkGetNetworkIdFromEntity(ent)
    CreateThread(function()
        local off, ldir = boneLocal(ent, bone, shot)
        TriggerServerEvent('lwk_taser:fire', bay, net, bone, off, ldir)
    end)
end

local function frontPed(ped)
    local pos, fwd = GetEntityCoords(ped), GetEntityForwardVector(ped)
    local best, bd = 0, Config.DriveStunRange
    for _, p in ipairs(GetGamePool('CPed')) do
        if p ~= ped then
            local d = GetEntityCoords(p) - pos
            local dist = #d
            if dist > 0 and dist < bd and (d.x * fwd.x + d.y * fwd.y) / dist > 0.5 and NetworkGetEntityIsNetworked(p) then
                best, bd = p, dist
            end
        end
    end
    return best ~= 0 and NetworkGetNetworkIdFromEntity(best) or 0
end

-- Equip watcher + trigger interception
local holding, nextHold = false, 0
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local cfg = weaponCfg(ped)
        if cfg ~= equipped then
            equipped = cfg
            if cfg then TriggerServerEvent('lwk_taser:sync') end
            pushState()
            cid()
        end
        if not cfg then
            Wait(250)
        else
            Wait(0)
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            if IsDisabledControlJustPressed(0, 24) and IsPlayerFreeAiming(PlayerId()) then
                fire(ped, cfg)
                holding, nextHold = true, GetGameTimer() + 300
            end
            -- trigger held after the shot: keep the cycle going (the server only re-energises once a cycle ends)
            if holding then
                if not IsDisabledControlPressed(0, 24) then
                    holding = false
                elseif GetGameTimer() >= nextHold then
                    TriggerServerEvent('lwk_taser:hold')
                    nextHold = GetGameTimer() + 300
                end
            end
        end
    end
end)

RegisterNetEvent('lwk_taser:bays', function(b, dev)
    bays, device = b, dev
    cid()
end)

-- lwk_cine (local events only): fire at a point on cue, hide the HUD overlay for clean footage
AddEventHandler('lwk_taser:cineFire', function(aim)
    local ped = PlayerPedId()
    local cfg = weaponCfg(ped)
    if cfg then fire(ped, cfg, aim) end
end)
AddEventHandler('lwk_taser:cineHud', function(hidden) SendNUIMessage({ type = 'hud', hidden = hidden }) end)

RegisterNetEvent('lwk_taser:cycle', function()
    SendNUIMessage({ type = 'cycle', ms = Config.CycleTime * 1000 })
    screen({ type = 'cycle', ms = Config.CycleTime * 1000 })
end)

RegisterNetEvent('lwk_taser:sound', function(pos, name, key)
    local cam = GetFinalRenderedCamCoord()
    local v = pos - cam
    local d = #v
    if d > Config.SoundRange then return end
    local yaw = math.rad(GetFinalRenderedCamRot(2).z)
    local pan = d > 0.5 and (v.x * math.cos(yaw) + v.y * math.sin(yaw)) / d or 0.0
    SendNUIMessage({ type = 'sound', name = name, key = key, vol = Config.Volume * (1 - d / Config.SoundRange) ^ 2, pan = pan, dur = Config.CycleTime })
end)

-- ped -> end of its current shock. One thread per ped: a re-energise (held trigger) only extends it, so the
-- earlier thread can't clear the screen effect / ragdoll restore in the middle of the next cycle
local stunned = {}

RegisterNetEvent('lwk_taser:shock', function(net, mode)
    local ped = NetToPed(net)
    if ped == 0 then return end
    local me = ped == PlayerPedId()
    -- Ambient peds get culled by population cleanup once tased; we're the owner here, so pin it like ERS does.
    -- ponytail: never released, the ped stays until something else (ERS, cleanup scripts) deletes it
    if not IsPedAPlayer(ped) then SetEntityAsMissionEntity(ped, true, true) end
    local stop = GetGameTimer() + (mode == 'lockout' and Config.CycleTime * 1000 or Config.PainTime)
    local running = stunned[ped]
    stunned[ped] = math.max(running or 0, stop)
    if running then return end
    if me then SetTimecycleModifier('Dont_tazeme_bro') end
    CreateThread(function()
        local nextRag = 0
        -- cuff scripts switch ragdoll off (often every frame); force it back on for the cycle, restore afterwards
        local couldRagdoll = CanPedRagdoll(ped)
        while GetGameTimer() < stunned[ped] and DoesEntityExist(ped) do
            SetPedCanRagdoll(ped, true)
            if GetGameTimer() >= nextRag or not IsPedRagdoll(ped) then
                SetPedToRagdoll(ped, 1000, 1000, 0, false, false, false)
                nextRag = GetGameTimer() + 500
            end
            if me then DisableAllControlActions(0) end
            Wait(0)
        end
        stunned[ped] = nil
        if DoesEntityExist(ped) and not couldRagdoll then SetPedCanRagdoll(ped, false) end
        if me then ClearTimecycleModifier() end
    end)
end)

-- Synced laser + flashlight: read every nearby player's state bag, draw locally
local fx = {}
CreateThread(function()
    while true do
        local myPos = GetEntityCoords(PlayerPedId())
        local list = {}
        for _, pl in ipairs(GetActivePlayers()) do
            local st = Player(GetPlayerServerId(pl)).state.taser
            local p = GetPlayerPed(pl)
            if st and (st.light or st.laser) and not IsPedInAnyVehicle(p, false)
                and #(GetEntityCoords(p) - myPos) < Config.ShowDistance then
                list[#list + 1] = { ped = p, st = st, cfg = weaponCfg(p), me = pl == PlayerId() }
            end
        end
        fx = list
        Wait(250)
    end
end)

CreateThread(function()
    local L, c = Config.Light, Config.Laser.color
    -- Script ticks run before the game moves peds and weapons, so the gun position read here is a frame old and the
    -- laser trailed the gun on fast moves. Adding last frame's motion predicts where the gun is drawn this frame.
    -- ponytail: linear prediction overshoots a frame when a move stops; an attached beam prop would be exact
    local prev = {}
    while true do
        if #fx == 0 then
            Wait(250)
        else
            Wait(0)
            local now, seen = GetFrameCount(), {}
            for _, f in ipairs(fx) do
                if f.cfg and DoesEntityExist(f.ped) then
                    local from, dir = muzzle(f.ped, f.cfg)
                    local p = prev[f.ped]
                    seen[f.ped] = { from = from, dir = dir, frame = now }
                    if p and p.frame == now - 1 and #(from - p.from) < 0.5 then -- skip after a gap or a teleport
                        from, dir = from + (from - p.from), dir + (dir - p.dir)
                        dir = dir / #dir
                    end
                    if f.me and IsPlayerFreeAiming(PlayerId()) then -- aimed: point at the crosshair from the predicted muzzle
                        dir = aimPoint(f.ped) - from
                        dir = dir / #dir
                    end
                    if f.st.light then
                        DrawSpotLight(from.x, from.y, from.z, dir.x, dir.y, dir.z, 255, 250, 235, L.range, L.brightness, 0.0, L.radius, 1.0)
                    end
                    if f.st.laser then
                        local hit, pos = ray(from, from + dir * Config.Laser.range, f.ped)
                        local to = hit and pos or from + dir * Config.Laser.range
                        DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, c[1], c[2], c[3], 200)
                        if hit then
                            DrawMarker(28, to.x, to.y, to.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.02, 0.02, 0.02, c[1], c[2], c[3], 230, false, false, 2, false, nil, nil, false)
                        end
                    end
                end
            end
            prev = seen
        end
    end
end)

-- Barbs + wires, driven by the target entity's 'taserBarbs' state bag
local barbs = {}

-- The server sets this bag, but the ped's owner can overwrite it: a flooded or malformed value would spawn props
-- without limit or throw inside the barb threads. Keep at most MAX_BARBS well-formed probes.
local MAX_BARBS = Config.Probes * 3 -- three officers' full magazines in one target
local function clean(v)
    if type(v) ~= 'table' or type(v.p) ~= 'table' then return nil end
    local p = {}
    for _, x in ipairs(v.p) do
        if #p == MAX_BARBS then break end
        if type(x) == 'table' and math.type(x.s) and math.type(x.b) then
            if not (type(x.o) == 'vector3' and type(x.d) == 'vector3' and #x.d > 0) then x.o, x.d = nil, nil end
            p[#p + 1] = x
        end
    end
    return { p = p }
end

local function clearAll(b)
    for _, p in ipairs(b.props) do despawn(p) end
    b.props = {}
end

-- Barb at the laser's hit point, spike (model +Y) along the shot direction, sunk Config.BarbDepth into the body
local function attachProp(ent, pr, i)
    local c = GetEntityCoords(ent)
    local p = spawnProp(Config.BarbProp, c)
    local off, rot
    if pr.o and pr.d then
        local d = pr.d / #pr.d
        off = pr.o + d * Config.BarbDepth
        rot = vec3(math.deg(math.asin(math.max(-1.0, math.min(1.0, d.z)))), 0.0, math.deg(math.atan(-d.x, d.y)))
    else -- old records without a hit point: spread barbs that share a bone so they don't stack
        off, rot = vec3(((i * 37) % 7 - 3) * 0.02, ((i * 53) % 5 - 2) * 0.03, 0.0), vec3(0.0, 0.0, 0.0)
    end
    AttachEntityToEntity(p, ent, GetPedBoneIndex(ent, pr.b), off.x, off.y, off.z, rot.x, rot.y, rot.z, false, false, false, false, 2, true)
    return p
end

-- Thin wire drawn as a sagging curve; sags more the closer the officer is (more slack)
local function drawWire(a, c)
    local d = #(c - a)
    local sag = math.min(math.max(Config.WireLength - d, 0.0) * 0.12, 0.6)
    local col = Config.WireColor
    local prev = a
    for i = 1, 12 do
        local t = i / 12
        local p = a + (c - a) * t - vec3(0.0, 0.0, sag * 4 * t * (1 - t))
        DrawLine(prev.x, prev.y, prev.z, p.x, p.y, p.z, col[1], col[2], col[3], col[4])
        prev = p
    end
end

AddStateBagChangeHandler('taserBarbs', nil, function(bag, _, value)
    if barbs[bag] then clearAll(barbs[bag]) barbs[bag] = nil end
    value = clean(value)
    if value then barbs[bag] = { v = value, props = {} } end
end)

local function sig(v) -- cheap identity of a barbs value: probe count + who/wired/bone of each
    local t = { #v.p }
    for i, p in ipairs(v.p) do t[#t + 1] = ('%s:%s:%s'):format(p.s, p.w and 1 or 0, p.b) end
    return table.concat(t, '|')
end

-- GetEntityFromStateBagName throws (and kills the loop) once the ped is gone; resolve the net id safely. 0 = not here
local function barbEnt(bag, b)
    b.net = b.net or tonumber(bag:match('^entity:(%d+)$')) or 0
    local ent = b.net ~= 0 and NetworkDoesEntityExistWithNetworkId(b.net) and NetworkGetEntityFromNetworkId(b.net) or 0
    return DoesEntityExist(ent) and ent or 0
end

-- The change handler only fires for updates this client receives; a ped that streams in later (we walked up
-- after the hit) already carries its bag value. Pick those up so every nearby client sees all barbs + wires.
CreateThread(function()
    while true do
        Wait(1000)
        for _, ped in ipairs(GetGamePool('CPed')) do
            if NetworkGetEntityIsNetworked(ped) then
                local v = clean(Entity(ped).state.taserBarbs)
                if v then
                    local bag = 'entity:' .. NetworkGetNetworkIdFromEntity(ped)
                    if not barbs[bag] then barbs[bag] = { v = v, props = {} } end
                end
            end
        end
        -- and the other way: a removal we never got (ped was out of scope) must not leave barbs/wires behind
        for bag, b in pairs(barbs) do
            local ent = barbEnt(bag, b)
            if ent ~= 0 then
                local v = clean(Entity(ent).state.taserBarbs)
                if not v then
                    clearAll(b); barbs[bag] = nil
                elseif sig(v) ~= sig(b.v) then
                    clearAll(b); barbs[bag] = { v = v, props = {} }
                end
            end
        end
    end
end)

local barbOption = { {
    name = 'lwk_taser_barbs', label = 'Remove barbs', icon = 'fa-solid fa-bolt', distance = 2.0,
    canInteract = function(ent) return NetworkGetEntityIsNetworked(ent) and Entity(ent).state.taserBarbs ~= nil end,
    onSelect = function(d) TriggerServerEvent('lwk_taser:remove', NetworkGetNetworkIdFromEntity(d.entity)) end,
} }
exports.ox_target:addGlobalPed(barbOption)
exports.ox_target:addGlobalPlayer(barbOption)

CreateThread(function()
    while true do
        if not next(barbs) then
            Wait(500)
        else
            Wait(0)
            for bag, b in pairs(barbs) do
                local ent = barbEnt(bag, b)
                if ent == 0 then
                    -- gone or out of scope: drop it (the sync thread re-adds it from the bag if the ped streams back
                    -- in). Kept entries made this loop run every frame forever, and a reused net id briefly wore
                    -- the old barbs
                    clearAll(b); barbs[bag] = nil
                else
                    if #b.props == 0 then
                        for i, p in ipairs(b.v.p) do b.props[i] = attachProp(ent, p, i) end
                    end
                    -- one wire per barb still connected, from its own bay on the taser of the officer who fired it
                    local who = {}
                    for i, p in ipairs(b.v.p) do
                        if p.w and p.s and b.props[i] then
                            if who[p.s] == nil then
                                local pl = GetPlayerFromServerId(p.s)
                                local off = pl ~= -1 and GetPlayerPed(pl) or 0
                                who[p.s] = off ~= 0 and { ped = off, w = GetCurrentPedWeaponEntityIndex(off, 0) } or false
                            end
                            local o = who[p.s]
                            if o then
                                local bay = p.k and Config.Bays[p.k]
                                local a = (bay and o.w ~= 0) and GetOffsetFromEntityInWorldCoords(o.w, bay.x, bay.y, bay.z)
                                    or muzzle(o.ped, weaponCfg(o.ped) or {})
                                -- wire leaves the probe's rear end (49 mm behind the spike base)
                                drawWire(a, GetOffsetFromEntityInWorldCoords(b.props[i], 0.0, -0.049, 0.0))
                            end
                        end
                    end
                    if Config.Debug then -- red dot = barb, yellow line = to the bone it rides on
                        for i, p in ipairs(b.v.p) do
                            local pr = b.props[i]
                            if pr then
                                local a, c = GetEntityCoords(pr), GetPedBoneCoords(ent, p.b, 0.0, 0.0, 0.0)
                                DrawMarker(28, a.x, a.y, a.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.015, 0.015, 0.015, 255, 0, 0, 255, false, false, 2, false, nil, nil, false)
                                DrawLine(a.x, a.y, a.z, c.x, c.y, c.z, 255, 220, 0, 255)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Cartridge prop: the weapon model has no cartridge of its own. Every client mounts one on any nearby taser and,
-- while the reload clip plays, moves it gun -> left hand -> dropped -> fresh one -> gun by the clip's playback time.
-- Peds' animations are already network-synced, so this needs no events of its own.
local R = Config.Reload
local carts = {} -- ped -> { prop = entity|nil, at = 'gun'|'hand'|'none', w = weapon entity }

local function hiddenProp(model, ped) -- shown only once it is seated where it belongs (follow thread)
    local p = spawnProp(model, GetEntityCoords(ped))
    SetEntityVisible(p, false, false)
    return p
end

-- Cartridge in the left hand. The default offset comes from the animation rig (Config.Reload.hand); every seat then
-- measures, in game, where the hand actually holds a seated cartridge and keeps that (saved per client), so after
-- the first reload it sits exactly in the palm. Axes come from GetOffsetFromEntityInWorldCoords (unambiguous).
-- GTA's attach Euler order isn't documented consistently, so the attach is checked and the other order tried once.
local HAND = 60309 -- PH_L_Hand
local euler, eulerLocked = 1, false -- attach Euler order; settled once on your own ped, then fixed

local function frame(e) -- world position + local X/Y/Z axes of an entity
    local p = GetOffsetFromEntityInWorldCoords(e, 0.0, 0.0, 0.0)
    return { p = p, x = GetOffsetFromEntityInWorldCoords(e, 1.0, 0.0, 0.0) - p,
             y = GetOffsetFromEntityInWorldCoords(e, 0.0, 1.0, 0.0) - p, z = GetOffsetFromEntityInWorldCoords(e, 0.0, 0.0, 1.0) - p }
end

local function relTo(h, c) -- frame c expressed in frame h
    local function loc(v) return vec3(dot(v, h.x), dot(v, h.y), dot(v, h.z)) end
    return { pos = loc(c.p - h.p), r = loc(c.x), f = loc(c.y), u = loc(c.z) }
end

local function fromConfig()
    local o, a = R.hand.offset, math.rad(R.hand.rot.z) -- rig offset is a pure Z rotation
    return { pos = o, r = vec3(math.cos(a), math.sin(a), 0.0), f = vec3(-math.sin(a), math.cos(a), 0.0), u = vec3(0.0, 0.0, 1.0) }
end

-- a learned grip is only kept if it is close to the rig's: a sample taken mid-blend or off a lagging remote ped
-- once put the cartridge off the palm until the next reload (and was saved)
local function sane(rel) return rel and #(rel.pos - R.hand.offset) < 0.08 end

local KVP = 'cart_hand_v4' -- v3 saves may hold such a bad sample
local function loadRel()
    local s = GetResourceKvpString(KVP)
    local t = s and json.decode(s)
    local function v(a) return vec3(a[1], a[2], a[3]) end
    local rel = t and t.pos and { pos = v(t.pos), r = v(t.r), f = v(t.f), u = v(t.u) }
    return sane(rel) and rel or fromConfig()
end

local function saveRel(rel)
    local function a(v) return { v.x, v.y, v.z } end
    SetResourceKvp(KVP, json.encode({ pos = a(rel.pos), r = a(rel.r), f = a(rel.f), u = a(rel.u) }))
end

local handRel = loadRel()

local function toEuler(rel, kind) -- rel axes = columns of the relative rotation matrix
    local M = { { rel.r.x, rel.f.x, rel.u.x }, { rel.r.y, rel.f.y, rel.u.y }, { rel.r.z, rel.f.z, rel.u.z } }
    local d = math.deg
    if kind == 1 then -- R = Rz * Rx * Ry
        return vec3(d(math.asin(math.max(-1, math.min(1, M[3][2])))), d(math.atan(-M[3][1], M[3][3])), d(math.atan(-M[1][2], M[2][2])))
    end -- R = Ry * Rx * Rz
    return vec3(d(math.asin(math.max(-1, math.min(1, -M[2][3])))), d(math.atan(M[1][3], M[3][3])), d(math.atan(M[2][1], M[2][2])))
end

local function attachHand(c, ped)
    local o, r = handRel.pos, toEuler(handRel, euler)
    AttachEntityToEntity(c.prop, ped, GetPedBoneIndex(ped, HAND), o.x, o.y, o.z, r.x, r.y, r.z, false, false, false, false, 2, true)
end

-- w: the ped's current weapon object (never 0: callers hide the cartridge instead)
local function mount(c, ped, where, w)
    local mine = ped == PlayerPedId()
    if where == 'gun' then
        if c.at == 'hand' and mine then -- seating: learn exactly where your hand holds a seated one
            local rel = relTo(frame(c.marker), frame(w))
            if sane(rel) then handRel = rel; saveRel(rel) end
        end
        AttachEntityToEntity(c.prop, w, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    else
        attachHand(c, ped)
        if mine and not eulerLocked then -- next frame: check the Euler order reproduced the pose, else switch; then fixed
            eulerLocked = 'checking' -- one check at a time
            CreateThread(function()
                Wait(0)
                if not (c.prop and DoesEntityExist(c.prop)) or c.at ~= 'hand' then eulerLocked = false; return end
                local now = relTo(frame(c.marker), frame(c.prop))
                if 1.0 - math.min(dot(now.f, handRel.f), dot(now.u, handRel.u)) > 0.01 then
                    euler = 3 - euler
                    attachHand(c, ped)
                end
                eulerLocked = true
                if Config.Debug then print(('[lwk_taser] cartridge hand attach: Euler order %d'):format(euler)) end
            end)
        end
    end
    c.at = where
end

local function show(e, on) -- only touch visibility on a change
    if e and DoesEntityExist(e) and IsEntityVisible(e) ~= on then SetEntityVisible(e, on, false) end
end

local function onGun(e, w) -- attached to this weapon object and actually sitting on it
    return e and DoesEntityExist(e) and IsEntityAttachedToEntity(e, w) and #(GetEntityCoords(e) - GetEntityCoords(w)) < 0.02
end

local function inHand(c, ped) -- attached to the ped and where the grip puts it
    if not (c.prop and DoesEntityExist(c.prop) and IsEntityAttachedToEntity(c.prop, ped)) then return false end
    local o = handRel.pos
    return #(GetEntityCoords(c.prop) - GetOffsetFromEntityInWorldCoords(c.marker, o.x, o.y, o.z)) < 0.03
end

-- The cartridge prop has no collision bounds, so physics can't move it: fall it by hand until its lowest
-- corner reaches the ground, then leave it there a while
local function lowestZ(p, mn, mx)
    local z = math.huge
    for _, x in ipairs({ mn.x, mx.x }) do for _, y in ipairs({ mn.y, mx.y }) do for _, zz in ipairs({ mn.z, mx.z }) do
        z = math.min(z, GetOffsetFromEntityInWorldCoords(p, x, y, zz).z)
    end end end
    return z
end

local function dropCart(p, ped)
    DetachEntity(p, true, false)
    CreateThread(function()
        local mn, mx = GetModelDimensions(GetEntityModel(p))
        local c = GetEntityCoords(p)
        -- floor straight below (ignores the ped), else the ground height, else the ped's feet
        local _, hit, at = GetShapeTestResult(StartExpensiveSynchronousShapeTestLosProbe(c.x, c.y, c.z, c.x, c.y, c.z - 5.0, 1 + 16, ped, 7))
        local found, gz = hit == 1 or hit == true, at.z
        if not found then found, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 0.5, false) end
        if not found then gz = GetEntityCoords(ped).z - 1.0 end
        local h = GetEntityForwardVector(ped) * 0.35 -- slides off the front of the bay
        local v, t = 0.0, 0
        while DoesEntityExist(p) and t < 3000 do
            local dt = GetFrameTime()
            v = v + 9.81 * dt
            local drop = v * dt
            local gap = lowestZ(p, mn, mx) - gz
            if gap <= drop then
                SetEntityCoordsNoOffset(p, c.x, c.y, c.z - gap, false, false, false)
                break
            end
            c = c - vec3(0.0, 0.0, drop) + h * dt
            SetEntityCoordsNoOffset(p, c.x, c.y, c.z, false, false, false)
            t = t + dt * 1000
            Wait(0)
        end
        if DoesEntityExist(p) then -- never left hanging: settle on the floor even if the fall timed out
            local q = GetEntityCoords(p)
            SetEntityCoordsNoOffset(p, q.x, q.y, q.z - (lowestZ(p, mn, mx) - gz), false, false, false)
        end
        Wait(20000)
        despawn(p)
    end)
end

local function clearCart(ped)
    local c = carts[ped]
    if c then despawn(c.prop); despawn(c.marker); despawn(c.screen) end
    carts[ped] = nil
end

CreateThread(function() -- which peds hold a taser near me
    while true do
        local me = GetEntityCoords(PlayerPedId())
        local seen = {}
        for _, ped in ipairs(GetGamePool('CPed')) do
            if weaponCfg(ped) and GetCurrentPedWeaponEntityIndex(ped, 0) ~= 0 and #(GetEntityCoords(ped) - me) < Config.ShowDistance then
                seen[ped] = true
                if not carts[ped] then
                    local marker = hiddenProp(Config.CartProp, ped) -- never shown: its frame is the hand bone's
                    AttachEntityToEntity(marker, ped, GetPedBoneIndex(ped, HAND), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
                    carts[ped] = { prop = hiddenProp(Config.CartProp, ped), marker = marker, screen = hiddenProp(`lwk_taser_screen`, ped) }
                    bindScreen()
                    mount(carts[ped], ped, 'gun', GetCurrentPedWeaponEntityIndex(ped, 0))
                end
            end
        end
        for ped in pairs(carts) do
            if not seen[ped] then clearCart(ped) end
        end
        Wait(250)
    end
end)

-- Every frame, for every nearby taser: the cartridge and the rear screen must sit exactly where they belong (on the
-- current weapon object, or in the grip), else they are re-attached on the spot, or hidden while there is nothing to
-- attach to (weapon object 0 mid-swap / re-equip, when an attach silently fails and used to leave them floating).
-- GTA recreates weapon objects and reuses handles, so "attached" alone isn't trusted: the position is checked too.
CreateThread(function() -- also follows the reload clip: old one drops off the gun, new one rides the hand until seated
    while true do
        for ped, c in pairs(carts) do
            local w = GetCurrentPedWeaponEntityIndex(ped, 0)
            local want = 'gun'
            if IsEntityPlayingAnim(ped, R.dict, R.clip, 3) then
                local t = GetEntityAnimCurrentTime(ped, R.dict, R.clip)
                if t >= R.drop and t < R.fetch then
                    want = 'none'
                elseif t >= R.fetch and t < R.seat then
                    want = 'hand'
                end
            end

            if w ~= 0 and DoesEntityExist(c.screen) and not onGun(c.screen, w) then
                AttachEntityToEntity(c.screen, w, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
            end
            show(c.screen, w ~= 0 and onGun(c.screen, w))

            if want == 'none' then
                if c.prop then dropCart(c.prop, ped) end
                c.prop, c.at = nil, 'none'
            else
                if c.prop and not DoesEntityExist(c.prop) then despawn(c.prop); c.prop = nil end
                if not c.prop then c.prop, c.at = hiddenProp(Config.CartProp, ped), nil end -- fresh cartridge from the belt
                if want == 'gun' then
                    if w ~= 0 and (c.at ~= 'gun' or not onGun(c.prop, w)) then mount(c, ped, 'gun', w) end
                    show(c.prop, w ~= 0 and onGun(c.prop, w))
                else
                    if c.at ~= 'hand' or not inHand(c, ped) then mount(c, ped, 'hand', w) end
                    show(c.prop, true)
                end
            end
        end
        Wait(next(carts) and 0 or 250)
    end
end)

RegisterNetEvent('lwk_taser:reloadAnim', function()
    local ped = PlayerPedId()
    RequestAnimDict(R.dict)
    while not HasAnimDictLoaded(R.dict) do Wait(0) end
    TaskPlayAnim(ped, R.dict, R.clip, 4.0, -4.0, -1, 48, 0.0, false, false, false) -- upper body, can walk
end)

-- Keys
local function cmd(name, key, desc, fn)
    RegisterCommand('taser_' .. name, function() fn(PlayerPedId()) end, false)
    RegisterKeyMapping('taser_' .. name, desc, 'keyboard', key)
end

local function toggle(set)
    if not equipped then return end
    set()
    TriggerServerEvent('lwk_taser:toggle')
    pushState()
    cid()
end

cmd('light', Config.Keys.light, 'Taser: toggle flashlight', function() toggle(function() light = not light end) end)
cmd('laser', Config.Keys.laser, 'Taser: toggle laser', function() toggle(function() laser = not laser end) end)

cmd('arc', Config.Keys.arc, 'Taser: ARC (drive stun / re-energise / warning arc)', function(ped)
    if not equipped then return end
    TriggerServerEvent('lwk_taser:arc', frontPed(ped))
end)

cmd('reload', Config.Keys.reload, 'Taser: reload cartridges', function(ped)
    if equipped and not IsEntityPlayingAnim(ped, R.dict, R.clip, 3) then TriggerServerEvent('lwk_taser:reload') end
end)

-- Calibration for custom models, local view only (nobody else is affected):
-- /tasercal draws the weapon's X (red) Y (green) Z (blue) axes + the current muzzle/laser (yellow)
-- /tasermuzzle x y z and /taseraxis x y z change them live and print the line for Config.Weapons
local cal = false
RegisterCommand('tasercal', function() cal = not cal end, false)

local function setVec(key)
    return function(_, a)
        local cfg = weaponCfg(PlayerPedId())
        if not cfg then return end
        cfg[key] = vec3(tonumber(a[1]) or 0.0, tonumber(a[2]) or 0.0, tonumber(a[3]) or 0.0)
        local m, x = cfg.muzzle or vec3(0, 0, 0), cfg.axis or vec3(1, 0, 0)
        print(('[lwk_taser] { muzzle = vec3(%.3f, %.3f, %.3f), axis = vec3(%.1f, %.1f, %.1f) }'):format(m.x, m.y, m.z, x.x, x.y, x.z))
    end
end
RegisterCommand('tasermuzzle', setVec('muzzle'), false)
RegisterCommand('taseraxis', setVec('axis'), false)

-- /taserbay n x y z: move bay n's wire start live (weapon space), prints the line for Config.Bays.
-- With Config.Debug on, every bay is drawn on your taser with its number.
RegisterCommand('taserbay', function(_, a)
    local n = tonumber(a[1])
    if not (n and Config.Bays[n]) then return print('[lwk_taser] usage: /taserbay <1-10> x y z') end
    Config.Bays[n] = vec3(tonumber(a[2]) or Config.Bays[n].x, tonumber(a[3]) or Config.Bays[n].y, tonumber(a[4]) or Config.Bays[n].z)
    local v = Config.Bays[n]
    print(('[lwk_taser] bay %d -> vec3(%.4f, %.4f, %.4f),'):format(n, v.x, v.y, v.z))
end, false)

CreateThread(function()
    while true do
        local w = Config.Debug and equipped and GetCurrentPedWeaponEntityIndex(PlayerPedId(), 0) or 0
        if w == 0 then
            Wait(500)
        else
            Wait(0)
            for n, v in ipairs(Config.Bays) do
                local p = GetOffsetFromEntityInWorldCoords(w, v.x, v.y, v.z)
                DrawMarker(28, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.004, 0.004, 0.004, 0, 200, 255, 255, false, false, 2, false, nil, nil, false)
                local on, sx, sy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
                if on then
                    SetTextScale(0.0, 0.22); SetTextFont(0); SetTextColour(255, 255, 255, 255); SetTextOutline(); SetTextCentre(true)
                    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(tostring(n)); EndTextCommandDisplayText(sx, sy - 0.012)
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local cfg = cal and weaponCfg(ped)
        local w = cfg and GetCurrentPedWeaponEntityIndex(ped, 0) or 0
        if w == 0 then
            Wait(500)
        else
            Wait(0)
            local o = GetEntityCoords(w)
            for i, v in ipairs({ vec3(0.15, 0, 0), vec3(0, 0.15, 0), vec3(0, 0, 0.15) }) do
                local e = GetOffsetFromEntityInWorldCoords(w, v.x, v.y, v.z)
                DrawLine(o.x, o.y, o.z, e.x, e.y, e.z, i == 1 and 255 or 0, i == 2 and 255 or 0, i == 3 and 255 or 0, 255)
            end
            local from, dir = muzzle(ped, cfg)
            local to = from + dir * 2.0
            DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, 255, 220, 0, 255)
            DrawMarker(28, from.x, from.y, from.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.012, 0.012, 0.012, 255, 220, 0, 255, false, false, 2, false, nil, nil, false)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in pairs(barbs) do clearAll(b) end
    for p in pairs(spawned) do if DoesEntityExist(p) then DeleteEntity(p) end end -- incl. markers + dropped carts
    RemoveReplaceTexture('lwk_taser_screen', 'taser10_cid')
    SetStreamedTextureDictAsNoLongerNeeded('lwk_taser_screen')
    DestroyDui(dui)
    for ped in pairs(carts) do clearCart(ped) end
    LocalPlayer.state:set('taser', nil, true)
    ClearTimecycleModifier()
end)
