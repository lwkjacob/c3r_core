--[[
    lwk_scene — client: Scene ▸ on c3r's G wheel (police on patrol). Pick a cone, flare or barrier: its ghost follows
    where you look, scroll turns it, click puts it down, and the next is ready (right-click or Esc to stop). Tape: click
    where it starts, then where it ends, and it carries on from there. E picks up anything in reach, anyone's.
    Every game spawns its own copy of the scene near it (the server's list), slows AI traffic by it and closes the road
    at barriers. BY LWK DEVELOPMENT
]]

local Items = {}  -- [id] = item (shared/scene.lua), the server's
local Live = {}   -- [id] = { obj, fx }: props spawned in this game
local Push = {}   -- [tape id] = { s (m along it), off (m to one side) }: someone walking into it
local zones, closed = {}, {} -- speed zone handles; switched-off road boxes { x1, y1, z1, x2, y2, z2 }
local placing = nil -- { prop = Config.Props entry, h } | { tape = style id, a, an }
local ghost = nil
local near = nil  -- the item E picks up
local TXD = 'lwk_scene'

-- Not in the native docs (DurtyFree's dumps have them; how they look is UNVERIFIED in game)
local ANIM = { dict = 'pickup_object', name = 'pickup_low' }      -- UNVERIFIED look: bending down to place / pick up
local FX = { asset = 'core', name = 'exp_grd_flare' }             -- UNVERIFIED look: a road flare burning

local PROPS = setmetatable({}, { __index = function(_, k) return Scene.props[k] end })
local STYLES = setmetatable({}, { __index = function(_, k) return Scene.styles[k] end })
local dirty = false -- (the traffic zones want rebuilding)

local function log(...) if Config.Debug then print('[lwk_scene]', ...) end end
local function card(id, kind, title, text, ms) pcall(function() exports.c3r:prompt(id, kind, title, text, ms) end) end
local function patrol() return LocalPlayer.state.c3rDuty == true and LocalPlayer.state.c3rService == 'police' end
local function me() return GetPlayerServerId(PlayerId()) end

local function key_name(cmd, fallback)
    local s = GetControlInstructionalButton(0, (GetHashKey(cmd) | 0x80000000) & 0xFFFFFFFF, true)
    return type(s) == 'string' and s:match('^t_(.+)$') or fallback
end

local function load_model(model)
    local h = GetHashKey(model)
    if not IsModelInCdimage(h) then return log('no such model', model) end
    RequestModel(h)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(h) do
        if GetGameTimer() > deadline then return nil end
        Wait(0)
    end
    return h
end

local function anim() -- (its own thread: the dictionary loads)
    CreateThread(function()
        RequestAnimDict(ANIM.dict)
        local deadline = GetGameTimer() + 1000
        while not HasAnimDictLoaded(ANIM.dict) and GetGameTimer() < deadline do Wait(0) end
        TaskPlayAnim(PlayerPedId(), ANIM.dict, ANIM.name, 8.0, -8.0, 900, 0, 0.0, false, false, false)
    end)
end

-- ─── tape textures ───────────────────────────────────────────────────────────
local txd = CreateRuntimeTxd(TXD)
for _, s in ipairs(Config.Tape.styles) do CreateRuntimeTextureFromImage(txd, s.id, s.file) end

-- ─── props in this game ──────────────────────────────────────────────────────
local function despawn(id)
    local l = Live[id]
    Live[id] = nil
    if not l then return end
    if l.fx then StopParticleFxLooped(l.fx, false) end
    if l.obj and DoesEntityExist(l.obj) then DeleteEntity(l.obj) end
end

-- where tape ties on a scene prop: the middle of the model (its origin needn't be), just under its top
local function prop_top(id)
    local l = Live[id]
    if not l or not l.obj or not DoesEntityExist(l.obj) then return nil end
    if not l.top then
        local low, top = GetModelDimensions(GetEntityModel(l.obj))
        l.top = GetOffsetFromEntityInWorldCoords(l.obj, (low.x + top.x) / 2, (low.y + top.y) / 2, top.z - 0.12)
    end
    return l.top
end

local function spawn(id, it)
    local cfg = PROPS[it.prop]
    if not cfg then return end
    Live[id] = {} -- (loading)
    local h = load_model(cfg.model)
    if not h or Items[id] ~= it or not Live[id] then Live[id] = nil return end
    local o = CreateObjectNoOffset(h, it.pos.x, it.pos.y, it.pos.z, false, false, false)
    SetModelAsNoLongerNeeded(h)
    SetEntityHeading(o, it.h)
    FreezeEntityPosition(o, cfg.freeze == true)
    Live[id] = { obj = o }
    if cfg.flare then
        RequestNamedPtfxAsset(FX.asset)
        local deadline = GetGameTimer() + 2000
        while not HasNamedPtfxAssetLoaded(FX.asset) and GetGameTimer() < deadline do Wait(0) end
        if Live[id] and Live[id].obj == o then
            UseParticleFxAsset(FX.asset)
            local fx = StartParticleFxLoopedOnEntity(FX.name, o, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, false, false, false)
            Live[id].fx = fx ~= 0 and fx or nil -- (no flame: no glow either)
        end
    end
end

CreateThread(function()
    while true do
        local pos, todo = GetEntityCoords(PlayerPedId()), {}
        for id, it in pairs(Items) do
            if it.kind == 'prop' then
                local d = #(pos - vector3(it.pos.x, it.pos.y, it.pos.z))
                if d < Config.DrawDistance and not Live[id] then todo[#todo + 1] = it
                elseif d > Config.DrawDistance + 25.0 and Live[id] then despawn(id) end
            end
        end
        for id in pairs(Live) do if not Items[id] then despawn(id) end end
        for _, it in ipairs(todo) do if Items[it.id] == it and not Live[it.id] then spawn(it.id, it) end end -- (models load: it waits)
        Wait(500)
    end
end)

-- ─── AI traffic ──────────────────────────────────────────────────────────────
-- Every game sets its own. The last bool of SET_ROADS_IN_AREA / _BACK_TO_ORIGINAL is unnamed in the native docs
-- (Rockstar's scripts use it as "also over the network"): false, so each game only changes its own roads. UNVERIFIED in game.
local function traffic()
    for _, z in ipairs(zones) do RemoveRoadNodeSpeedZone(z) end
    for _, b in ipairs(closed) do SetRoadsBackToOriginal(b[1], b[2], b[3], b[4], b[5], b[6], false) end
    zones, closed = {}, {}
    local slow = {}
    for _, it in pairs(Items) do
        local cfg = it.kind == 'prop' and PROPS[it.prop]
        if cfg and cfg.slow then slow[#slow + 1] = it.pos end
        if cfg and cfg.close then
            local p, r = it.pos, Config.Close.radius
            local b = { p.x - r, p.y - r, p.z - 3.0, p.x + r, p.y + r, p.z + 3.0 }
            SetRoadsInArea(b[1], b[2], b[3], b[4], b[5], b[6], false, false)
            closed[#closed + 1] = b
        end
    end
    for _, c in ipairs(Scene.clusters(slow, Config.Slow.radius)) do
        zones[#zones + 1] = AddRoadNodeSpeedZone(c.x, c.y, c.z, Config.Slow.radius + c.spread, Config.Slow.speed, false)
    end
end

CreateThread(function() -- (rebuilt at most twice a second: a Clear scene is 25 changes)
    while true do
        if dirty then dirty = false traffic() end
        Wait(500)
    end
end)

RegisterNetEvent('lwk_scene:all', function(all)
    Items = {}
    for _, it in pairs(type(all) == 'table' and all or {}) do Items[it.id] = it end
    dirty = true
end)

RegisterNetEvent('lwk_scene:set', function(id, it)
    if Items[id] and Items[id] ~= it then despawn(id) Push[id] = nil end
    Items[id] = it
    dirty = true -- (rebuilt once in the props thread: a Clear scene is 25 of these)
end)

RegisterNetEvent('lwk_scene:no', function(why)
    if why == 'cap' then card('scene_no', 'alert', 'Scene', ('You have %d out already: pick some up first.'):format(Config.Cap), 5000) end
end)

-- ─── tape ────────────────────────────────────────────────────────────────────
local TILE = Config.Tape.height * 16.0 -- (the texture is 16 to 1)
local STEP = TILE / 4                    -- (short pieces near by: the sag and the wind bend smoothly)
local FAR = 30.0                         -- metres: further off, plain colour (the text would only shimmer)
local Near = {}                          -- peds that could walk into tape (refreshed 4 times a second)
local wind_dir, wind_speed = vector3(0.0, 0.0, 0.0), 0.0

local function sm(f) f = math.max(0.0, math.min(1.0, f)) return f * f * (3 - 2 * f) end

-- one stretch of tape: it.a to it.b, both faces. It sags, bows and flutters with the wind and gives where someone
-- walks into it. far: a few plain pieces. r, g, bl: a tint (placing: red when it can't go there)
local function draw_tape(it, far, r, g, bl)
    r, g, bl = r or 255, g or 255, bl or 255
    local a, b = it.a, it.b
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    local len, flat = math.sqrt(dx * dx + dy * dy + dz * dz), math.sqrt(dx * dx + dy * dy)
    if len < 0.05 then return end
    local nx, ny = 1.0, 0.0 -- (flat, square to the tape)
    if flat > 0.01 then nx, ny = -dy / flat, dx / flat end
    local h, sag = Config.Tape.height / 2, math.min(0.3, len * (Config.Tape.sag or 0.02))
    local wind = Config.Tape.wind or 1.0
    local now, ph = GetGameTimer() / 1000.0, (it.id or 0) * 1.7
    local square = wind_dir.x * nx + wind_dir.y * ny -- (wind straight at it bows it most)
    local bow = math.min(0.25, 0.015 * wind_speed) * square * wind
    local flut = math.min(0.5, 0.04 + 0.03 * wind_speed) * wind
    local push = Push[it.id]
    -- s metres along: centre x, y, z, then up (tilted by the flutter) and the face's normal
    local function at(s)
        local t = s / len
        local bell = 4 * t * (1 - t)
        local side = bow * bell * (0.75 + 0.25 * math.sin(now * 1.9 + t * 5 + ph))
        if push and push.off ~= 0 then
            side = side + push.off * sm(1 - math.abs(s - push.s) / (1.0 + math.abs(push.off) * 1.5)) * math.min(1.0, bell * 4)
        end
        local th = far and 0.0 or flut * bell * math.sin(now * 6.3 + t * 11 + ph)
        local c, sn = math.cos(th), math.sin(th)
        return a.x + dx * t + nx * side, a.y + dy * t + ny * side, a.z + dz * t - sag * bell,
               nx * sn, ny * sn, c, nx * c, ny * c, -sn
    end
    local step = far and TILE or STEP
    local pieces = math.max(1, math.ceil(len / step - 1e-6))
    local col = STYLES[it.style] and STYLES[it.style].colour or { 255, 255, 255 }
    local x0, y0, z0, ux0, uy0, uz0, fx0, fy0, fz0 = at(0)
    for i = 0, pieces - 1 do
        local s0, s1 = i * step, math.min((i + 1) * step, len)
        local x1, y1, z1, ux1, uy1, uz1, fx1, fy1, fz1 = at(s1)
        -- the faces sit 2 mm apart, each on the side it's seen from
        local o0x, o0y, o0z, o1x, o1y, o1z = fx0 * 0.002, fy0 * 0.002, fz0 * 0.002, fx1 * 0.002, fy1 * 0.002, fz1 * 0.002
        local ax, ay, az = x0 - ux0 * h, y0 - uy0 * h, z0 - uz0 * h -- start, bottom
        local bx, by, bz = x1 - ux1 * h, y1 - uy1 * h, z1 - uz1 * h -- end, bottom
        local cx, cy, cz = x1 + ux1 * h, y1 + uy1 * h, z1 + uz1 * h -- end, top
        local ex, ey, ez = x0 + ux0 * h, y0 + uy0 * h, z0 + uz0 * h -- start, top
        if far then
            local R, G, B = col[1] * r // 255, col[2] * g // 255, col[3] * bl // 255
            DrawPoly(ax, ay, az, bx, by, bz, cx, cy, cz, R, G, B, 255)
            DrawPoly(ax, ay, az, cx, cy, cz, ex, ey, ez, R, G, B, 255)
            DrawPoly(bx, by, bz, ax, ay, az, cx, cy, cz, R, G, B, 255)
            DrawPoly(ex, ey, ez, cx, cy, cz, ax, ay, az, R, G, B, 255)
        else
            local k = math.floor(s0 / TILE + 1e-6)
            local u0, u1 = s0 / TILE - k, s1 / TILE - k
            -- seen from -normal
            DrawTexturedPoly(ax - o0x, ay - o0y, az - o0z, bx - o1x, by - o1y, bz - o1z, cx - o1x, cy - o1y, cz - o1z, r, g, bl, 255, TXD, it.style, u0, 1.0, 1.0, u1, 1.0, 1.0, u1, 0.0, 1.0)
            DrawTexturedPoly(ax - o0x, ay - o0y, az - o0z, cx - o1x, cy - o1y, cz - o1z, ex - o0x, ey - o0y, ez - o0z, r, g, bl, 255, TXD, it.style, u0, 1.0, 1.0, u1, 0.0, 1.0, u0, 0.0, 1.0)
            -- seen from +normal: the texture flipped, so the words read the right way round from this side too
            local v0, v1 = 1.0 - u0, 1.0 - u1
            DrawTexturedPoly(bx + o1x, by + o1y, bz + o1z, ax + o0x, ay + o0y, az + o0z, cx + o1x, cy + o1y, cz + o1z, r, g, bl, 255, TXD, it.style, v1, 1.0, 1.0, v0, 1.0, 1.0, v1, 0.0, 1.0)
            DrawTexturedPoly(ex + o0x, ey + o0y, ez + o0z, cx + o1x, cy + o1y, cz + o1z, ax + o0x, ay + o0y, az + o0z, r, g, bl, 255, TXD, it.style, v0, 0.0, 1.0, v1, 0.0, 1.0, v0, 1.0, 1.0)
        end
        x0, y0, z0, ux0, uy0, uz0, fx0, fy0, fz0 = x1, y1, z1, ux1, uy1, uz1, fx1, fy1, fz1
    end
end

local view = {} -- (the span as drawn this frame)

-- someone walking into a span pushes it ahead of them; it springs back once they're clear (or through it)
local function push_tape(it, dt)
    local a, b = it.a, it.b
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    local f2 = dx * dx + dy * dy
    if f2 < 0.01 then return end
    local flat, len = math.sqrt(f2), math.sqrt(f2 + dz * dz)
    local nx, ny = -dy / flat, dx / flat
    local P = Push[it.id] or { s = len / 2, off = 0.0 }
    local target, ts = 0.0, P.s
    for _, ped in ipairs(Near) do
        if DoesEntityExist(ped) then
            local q = GetEntityCoords(ped) -- (about hip height)
            local t = ((q.x - a.x) * dx + (q.y - a.y) * dy) / f2
            if t > 0.03 and t < 0.97 then
                local d = (q.x - a.x - dx * t) * nx + (q.y - a.y - dy * t) * ny -- (to one side of the line, signed)
                local tz = a.z + dz * t
                local inside = math.abs(d) < 0.45 or (P.off * d > 0 and math.abs(d) < math.abs(P.off) + 0.1)
                if inside and math.abs(d) < 1.2 and q.z > tz - 0.8 and q.z < tz + 1.3 then
                    local v = GetEntityVelocity(ped)
                    local way = v.x * nx + v.y * ny
                    local sgn
                    if math.abs(way) > 0.05 then sgn = way > 0 and 1 or -1
                    elseif P.off ~= 0 then sgn = P.off > 0 and 1 or -1
                    else sgn = d >= 0 and 1 or -1 end
                    local want = math.max(-1.2, math.min(1.2, d + sgn * 0.3))
                    if math.abs(want) > math.abs(target) then target, ts = want, t * len end
                end
            end
        end
    end
    if target == 0.0 and P.off == 0.0 then Push[it.id] = nil return end
    P.off = P.off + (target - P.off) * math.min(1.0, dt * (target ~= 0.0 and 14.0 or 6.0))
    if target ~= 0.0 then P.s = ts end
    if target == 0.0 and math.abs(P.off) < 0.005 then P.off = 0.0 end
    Push[it.id] = P
end

CreateThread(function()
    while true do
        local list = {}
        if next(Items) then
            local me = GetEntityCoords(PlayerPedId())
            for _, p in ipairs(GetGamePool('CPed')) do
                if not IsEntityDead(p) and #(GetEntityCoords(p) - me) < FAR then list[#list + 1] = p end
            end
            wind_dir, wind_speed = GetWindDirection(), GetWindSpeed()
        end
        Near = list
        Wait(250)
    end
end)

local function text3d(x, y, z, s, red)
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    if red then SetTextColour(255, 90, 90, 255) else SetTextColour(255, 255, 255, 255) end
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(s)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

-- ─── placing ─────────────────────────────────────────────────────────────────
-- held while placing: shoot / aim (click), the weapon wheel and weapon scroll (turning), the pause menu (Esc)
local HELD = { 14, 15, 16, 17, 24, 25, 37, 69, 70, 92, 140, 141, 142, 199, 200, 257, 263 }
local next_at = 0

local function stop()
    placing = nil
    if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
    ghost = nil
    card('scene', nil)
end

-- where the officer is looking: -> hit point, surface normal, entity (or nil)
local function aim(flags)
    local c, r = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
    local x, z = math.rad(r.x), math.rad(r.z)
    local dir = vector3(-math.sin(z) * math.abs(math.cos(x)), math.cos(z) * math.abs(math.cos(x)), math.sin(x))
    local far = c + dir * 25.0
    local _, hit, p, n, ent = GetShapeTestResult(StartExpensiveSynchronousShapeTestLosProbe(c.x, c.y, c.z, far.x, far.y, far.z, flags, PlayerPedId(), 7))
    if hit ~= 1 and hit ~= true then return nil, nil, nil, c, far end
    return p, n, ent, c, far
end

-- how far point q is from the line a-b (3D)
local function line_dist(q, a, b)
    local ab, aq = b - a, q - a
    local l2 = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
    local t = l2 > 0 and math.max(0.0, math.min(1.0, (aq.x * ab.x + aq.y * ab.y + aq.z * ab.z) / l2)) or 0.0
    return #(aq - ab * t)
end

local starting = nil -- (the latest pick: one still loading its model gives way to it)
local function start(p)
    stop()
    starting = p
    next_at = GetGameTimer() + 400 -- (the click that picked it from the wheel isn't a place)
    local ped = PlayerPedId()
    if not patrol() or IsPedInAnyVehicle(ped, false) then return end
    if p.prop then
        local h = load_model(p.prop.model)
        if not h or starting ~= p then return end
        local pos = GetEntityCoords(ped)
        ghost = CreateObjectNoOffset(h, pos.x, pos.y, pos.z - 5.0, false, false, false)
        SetModelAsNoLongerNeeded(h)
        SetEntityCollision(ghost, false, false)
        SetEntityAlpha(ghost, 150, false)
        FreezeEntityPosition(ghost, true)
        p.h = GetEntityHeading(ped)
        card('scene', 'info', p.prop.label, 'Scroll to turn it. Click to put it down. Right-click or Esc when you are done.')
    else
        card('scene', 'info', STYLES[p.tape].label .. ' tape',
             ('Look at a post (or a cone or barrier) and click, then the next one (up to %d m). It carries on from there. Right-click or Esc when you are done.'):format(math.floor(Config.Tape.max)))
    end
    placing = p
end

local function prop_frame(p, ped)
    local pos, fwd = GetEntityCoords(ped), GetEntityForwardVector(ped)
    local hit = aim(1)
    local t = hit or (pos + fwd * 2.0)
    local v = vector2(t.x - pos.x, t.y - pos.y)
    local d = #v
    if d < 0.6 then v, d = vector2(fwd.x, fwd.y), 1.0 end
    d = math.max(0.8, math.min(Config.Reach, d))
    local xy = vector2(pos.x, pos.y) + v / #v * d
    local ok, gz = GetGroundZFor_3dCoord(xy.x, xy.y, pos.z + 2.0, false)
    SetEntityCoords(ghost, xy.x, xy.y, ok and gz or pos.z - 1.0, false, false, false, false)
    if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then p.h = p.h + 15.0 end
    if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then p.h = p.h - 15.0 end
    SetEntityHeading(ghost, p.h)
    PlaceObjectOnGroundProperly(ghost)
    if IsDisabledControlJustPressed(0, 24) and GetGameTimer() >= next_at then
        next_at = GetGameTimer() + 700
        local at = GetEntityCoords(ghost)
        anim()
        TriggerServerEvent('lwk_scene:place', { kind = 'prop', prop = p.prop.id, pos = { x = at.x, y = at.y, z = at.z }, h = p.h % 360.0 })
    end
end

local function tape_frame(p, ped)
    local hit, n, ent, cam, far = aim(1 + 2 + 16)
    local pos = GetEntityCoords(ped)
    local net, snapped
    -- the scene's own prop closest to where you look (within 0.75 m of the line of sight): the tape ties at its top, no
    -- need to hit a thin post exactly. Stood at one post you can click the next one along.
    local best, top_at = 0.75, nil
    for id, l in pairs(Live) do
        local q = l.obj and #(GetEntityCoords(l.obj).xy - pos.xy) < Config.Tape.max + 6.0 and prop_top(id)
        if q then
            local d = line_dist(q, cam, hit or far)
            if d < best then best, snapped, top_at = d, id, q end
        end
    end
    if snapped then
        hit = top_at
    elseif hit then
        if ent ~= 0 and DoesEntityExist(ent) and IsEntityAVehicle(ent) and NetworkGetEntityIsNetworked(ent) then
            net = NetworkGetNetworkIdFromEntity(ent)
        elseif (ent == 0 or not DoesEntityExist(ent) or GetEntityType(ent) == 0) and n.z > 0.7 then -- the ground: tie it at waist height
            hit = hit + vector3(0.0, 0.0, Config.Tape.ground)
        end
        if #(vector2(hit.x, hit.y) - vector2(pos.x, pos.y)) > Config.Reach + 2.0 then hit = nil end
    end
    local len = hit and p.a and #(hit - p.a)
    local bad = not hit or (len and (len > Config.Tape.max or len < 0.3))
    if hit then
        local sz = snapped and 0.12 or 0.06 -- (bigger: locked onto a prop)
        DrawMarker(28, hit.x, hit.y, hit.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, sz, sz, sz,
                   255, bad and 80 or 255, bad and 80 or 255, 200, false, false, 2, false, nil, nil, false)
    end
    if p.a and hit then
        draw_tape({ a = p.a, b = hit, style = p.tape }, false, 255, bad and 140 or 255, bad and 140 or 255)
        local m = (p.a + hit) / 2
        text3d(m.x, m.y, m.z + 0.15, ('%.2f / %d'):format(len, math.floor(Config.Tape.max)), bad)
    end
    if IsDisabledControlJustPressed(0, 24) and hit and not bad and GetGameTimer() >= next_at then
        next_at = GetGameTimer() + 300
        if p.a then
            TriggerServerEvent('lwk_scene:place', { kind = 'tape', style = p.tape, a = { x = p.a.x, y = p.a.y, z = p.a.z },
                                                    b = { x = hit.x, y = hit.y, z = hit.z }, an = p.an, bn = net, ap = p.ap, bp = snapped })
        end
        p.a, p.an, p.ap = hit, net, snapped
    end
end

-- ─── every frame: tape, flare glow, placing ──────────────────────────────────
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local busy = false
        for id, it in pairs(Items) do
            if it.kind == 'tape' then
                local d = Scene.dist2d(it.a, pos)
                if d < Config.DrawDistance then
                    view.id, view.style = it.id, it.style -- (an end tied to a prop: drawn from the prop as this game has it)
                    local A, B = it.ap and prop_top(it.ap), it.bp and prop_top(it.bp)
                    view.a, view.b = A or it.a, B or it.b
                    -- an end on a prop runs on into it a little (Config.Tape.into): no gap where it's tied
                    local ab = vector3(view.b.x - view.a.x, view.b.y - view.a.y, view.b.z - view.a.z)
                    local L = #ab
                    if L > 0.05 then
                        local into = ab / L * (Config.Tape.into or 0.15)
                        if A then view.a = A - into end
                        if B then view.b = B + into end
                    end
                    if d < FAR + Config.Tape.max then push_tape(view, GetFrameTime()) end
                    draw_tape(view, d > FAR + Config.Tape.max)
                    busy = true
                end
            elseif Live[id] and Live[id].fx then
                local p = it.pos
                DrawLightWithRange(p.x, p.y, p.z + 0.3, 255, 45, 20, Config.FlareLight.range, Config.FlareLight.intensity)
                busy = true
            end
        end
        local p = placing
        if p then
            if not patrol() or IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then
                stop()
            elseif IsNuiFocused() then
                next_at = GetGameTimer() + 400 -- (a click on the wheel isn't a place either)
            else
                for _, c in ipairs(HELD) do DisableControlAction(0, c, true) end
                if IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 199) then
                    stop()
                elseif p.prop then
                    if ghost and DoesEntityExist(ghost) then prop_frame(p, ped) else stop() end
                else
                    tape_frame(p, ped)
                end
            end
            busy = true
        end
        Wait(busy and 0 or 250)
    end
end)

-- ─── pick up (E) ─────────────────────────────────────────────────────────────
local function label(it)
    if it.kind == 'tape' then return 'the tape' end
    return 'the ' .. (PROPS[it.prop] and PROPS[it.prop].label:lower() or 'prop')
end

-- E is c3r's while the officer has someone to deal with: a stop on, anyone close by, or a Stop Stick in hand
local function busy_e(ped)
    if LocalPlayer.state.stopstick then return true end
    local ok, stop = pcall(function() return exports.c3r:getStop() end)
    if ok and stop then return true end
    local pos = GetEntityCoords(ped)
    for _, p in ipairs(GetGamePool('CPed')) do
        if p ~= ped and IsPedHuman(p) and not IsPedAPlayer(p) and not IsEntityDead(p) and #(GetEntityCoords(p) - pos) < 2.5 then return true end
    end
    return false
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local n
        if patrol() and not placing and not IsPedInAnyVehicle(ped, false) and next(Items) and not busy_e(ped) then
            local pos, best = GetEntityCoords(ped), Config.PickupReach
            for id, it in pairs(Items) do
                local d = Scene.itemDist(it, pos)
                if it.kind == 'tape' then d = d + Config.PickupReach - 0.8 end -- (tape: within 0.8 m, it runs past everything)
                if d < best then best, n = d, id end
            end
        end
        if n ~= near then
            near = n
            LocalPlayer.state:set('c3rKeyE', n ~= nil, false) -- (c3r's E stays out of it)
            if n then card('scene_e', 'info', 'Pick up ' .. label(Items[n]), ('Press %s.'):format(key_name('+lwk_scene_pickup', Config.Keys.pickup)))
            else card('scene_e', nil) end
        end
        Wait(200)
    end
end)

RegisterCommand('+lwk_scene_pickup', function()
    local id = near
    if not id or not Items[id] or IsNuiFocused() then return end
    anim()
    TriggerServerEvent('lwk_scene:pickup', id)
end, false)
RegisterCommand('-lwk_scene_pickup', function() end, false)
RegisterKeyMapping('+lwk_scene_pickup', 'Scene: pick up a cone, flare, barrier or tape (lwk_scene)', 'keyboard', Config.Keys.pickup or '')

-- ─── Scene ▸ on c3r's G wheel ────────────────────────────────────────────────
local function slice()
    local mine = Scene.count(Items, me())
    local full = mine >= Config.Cap and ('Limit reached (%d)'):format(Config.Cap) or nil
    local items = {}
    for _, p in ipairs(Config.Props) do items[#items + 1] = { label = p.label, icon = p.icon, action = 'place', arg = p.id, off = full } end
    items[#items + 1] = { label = 'Tape', icon = 'tape', to = 'tape', off = full }
    items[#items + 1] = { label = 'Clear scene', icon = 'wave', action = 'clear', off = mine == 0 and 'Nothing out' or nil,
                          desc = 'Pick up everything you put down.' }
    local tape = {}
    for _, s in ipairs(Config.Tape.styles) do tape[#tape + 1] = { label = s.label, icon = 'tape', action = 'tape', arg = s.id } end
    return { label = 'Scene', icon = 'cone', desc = 'Cones, flares, barriers and tape.', order = 10, root = 'scene',
             off = IsPedInAnyVehicle(PlayerPedId(), false) and 'On foot' or nil,
             levels = { scene = { title = 'Scene', items = items }, tape = { title = 'Tape', items = tape } } }
end

CreateThread(function()
    TriggerServerEvent('lwk_scene:sync')
    while true do
        local ok, err = pcall(function() exports.c3r:setRadialSlice('scene', slice()) end) -- (c3r restarting: next time)
        if not ok then log(err) end
        Wait(500)
    end
end)

AddEventHandler('c3r:radial', function(id, action, arg)
    if id ~= 'scene' then return end
    if action == 'place' and PROPS[arg] then CreateThread(function() start({ prop = PROPS[arg] }) end)
    elseif action == 'tape' and STYLES[arg] then start({ tape = arg })
    elseif action == 'clear' then TriggerServerEvent('lwk_scene:clear') end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stop()
    for id in pairs(Live) do despawn(id) end
    Items = {}
    traffic()
    LocalPlayer.state:set('c3rKeyE', false, false)
    card('scene_e', nil)
    pcall(function() exports.c3r:setRadialSlice('scene', nil) end)
end)
