--[[
    c3r — client: AI backup. lwk_control's radio asks (requestService / requestPursuitBackup, the contract in
    docs/contract.md) and gets a true answer at once: the models and a place for the unit to appear are checked
    before saying yes; anything that goes wrong after that is said over dispatch. Each unit is this officer's own:
    it appears out of sight, drives to the scene, does its job and leaves, and is deleted if the officer drops.

    Natives as documented in citizenfx/natives (https://github.com/citizenfx/natives):
      TASK_VEHICLE_DRIVE_TO_COORD_LONGRANGE, TASK_VEHICLE_CHASE + SET_TASK_VEHICLE_CHASE_BEHAVIOR_FLAG (32: stay back,
      convoy-like; 8: boxing with a bit of PIT; called after the chase task), TASK_HELI_CHASE ("if the pilot finds
      enemies, it will engage them": crews ignore events and carry nothing), TASK_HELI_MISSION (4 = GoTo),
      SET_VEHICLE_FIXED ("if the vehicle's engine's broken then you cannot fix it": engine health first),
      SET_VEHICLE_SEARCHLIGHT (night only). Scenario names (CODE_HUMAN_MEDIC_*, WORLD_HUMAN_COP_IDLES) are not in
      the official docs: unverified, and nothing depends on them playing.
]]

local B = Config.Backup
Patients = Patients or {} -- (client/medical.lua: those the officer saw to)
local units = {}    -- [id] = { id, kind, veh, crew, blip, state = 'coming' | 'working' | 'leaving', cancelled, ... }
local spawned = {}  -- [entity] = true: everything spawned (and prisoners taken), deleted in the end whatever happens
local next_id = 0

-- driving styles (eVehicleDrivingFlags): on lights, round traffic but stopping for people; otherwise normal traffic
local RESPOND = 786469 | 2 | 16 -- AvoidVehicles + StopForPeds + SteerAroundPeds
local NORMAL = 786603           -- DrivingModeStopForVehicles

local function say(text) pcall(function() exports.lwk_control:say(nil, text) end) end
local function note(what, kind, count) TriggerServerEvent('c3r:backup', what, kind, count) end

local function wait_until(ms, done)
    local deadline = GetGameTimer() + ms
    while not done() and GetGameTimer() < deadline do Wait(250) end
    return done()
end

local function control(ent)
    local deadline = GetGameTimer() + 1500
    while DoesEntityExist(ent) and not NetworkHasControlOfEntity(ent) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(ent)
        Wait(0)
    end
    return DoesEntityExist(ent) and NetworkHasControlOfEntity(ent)
end

local function me() return PlayerPedId() end
local function pos() return GetEntityCoords(me()) end

-- ─── who's out there ──────────────────────────────────────────────────────────

local function active(kind)
    for _, u in pairs(units) do
        if u.kind == kind and u.state ~= 'leaving' then return u end
    end
end

-- The server deletes these if the officer drops (their game can't any more): every unit, the tow truck, the
-- prisoners and passengers taken. (TagBackup marks them all; gone ones are pruned here.)
local function report()
    local nets = {}
    for e in pairs(BackupEnts) do
        if not DoesEntityExist(e) then BackupEnts[e] = nil
        elseif NetworkGetEntityIsNetworked(e) then nets[#nets + 1] = NetworkGetNetworkIdFromEntity(e) end
    end
    TriggerServerEvent('c3r:backup:units', nets)
end
ReportBackup = report

-- A pursuit car or the helicopter within dist of p: the suspect isn't "lost" while backup is on them (stop.lua).
function BackupOnTarget(p, dist)
    for _, u in pairs(units) do
        if (u.kind == 'pursuit' or u.kind == 'air') and u.state ~= 'leaving' and u.veh and DoesEntityExist(u.veh)
            and #(GetEntityCoords(u.veh) - p) < dist then
            return true
        end
    end
    return false
end

-- ─── models and places ────────────────────────────────────────────────────────

local function models_ok(def, car)
    car = car or def.car
    if not (IsModelInCdimage(GetHashKey(car)) and IsModelAVehicle(GetHashKey(car))) then return false end
    for _, m in ipairs(def.crew) do if not IsModelInCdimage(GetHashKey(m)) then return false end end
    return true
end

local function load(model)
    local h = GetHashKey(model)
    RequestModel(h)
    return wait_until(5000, function() return HasModelLoaded(h) end) and h or nil
end

-- Where a unit appears: a road node B.spawn m from `around`, away from where the camera looks (out of sight),
-- and at least 120 m from the officer. ahead: a direction to prefer instead (in front of a fleeing suspect), and
-- then the unit faces that way too (the way the suspect is going, never at them). taken: points already used by
-- this request (kept 30 m apart). -> node, heading | nil
local function spawn_point(around, ahead, taken)
    local cam = GetGameplayCamRot(2)
    local look = vector3(-math.sin(math.rad(cam.z)), math.cos(math.rad(cam.z)), 0.0)
    local tries = {}
    for i = 0, 11 do
        local a = math.rad(i * 30)
        local dir = vector3(math.cos(a), math.sin(a), 0.0)
        local score = ahead and (dir.x * ahead.x + dir.y * ahead.y) or -(dir.x * look.x + dir.y * look.y)
        tries[#tries + 1] = { dir = dir, score = score }
    end
    table.sort(tries, function(x, y) return x.score > y.score end)
    local officer = pos()
    for _, t in ipairs(tries) do
        local d = B.spawn[1] + math.random() * (B.spawn[2] - B.spawn[1])
        local p = around + t.dir * d
        -- node flags 0: no switched-off nodes (1 would include them; GET_CLOSEST_VEHICLE_NODE's flags)
        local ok, node, h = GetClosestVehicleNodeWithHeading(p.x, p.y, p.z, 0, 3.0, 0)
        local apart = true
        for _, t2 in ipairs(taken or {}) do apart = apart and #(node - t2) > 30.0 end
        if ok and apart and #(node - officer) > 120.0 then
            local to = ahead or (around - node) -- face the suspect's way, or the scene
            local r = math.rad(h)
            if (-math.sin(r)) * to.x + math.cos(r) * to.y < 0 then h = (h + 180.0) % 360.0 end
            if taken then taken[#taken + 1] = node end
            return node, h
        end
    end
end

-- The scene: the stop's car (its people on foot, else the officer). Where to park: the nearest road node to it
-- (within 40 m), clear of the stop's car and the officer's own.
local function scene()
    local s = Stop
    local anchor = s and ((s.veh ~= 0 and DoesEntityExist(s.veh) and not s.towed and s.veh) or (s.ped and DoesEntityExist(s.ped) and s.ped))
    return anchor and GetEntityCoords(anchor) or pos()
end

local function park_point(at)
    local own = GetVehiclePedIsIn(me(), true)
    local busy = { own ~= 0 and GetEntityCoords(own) or nil, Stop and Stop.veh ~= 0 and DoesEntityExist(Stop.veh) and GetEntityCoords(Stop.veh) or nil }
    for n = 1, 12 do
        local ok, node, h = GetNthClosestVehicleNodeWithHeading(at.x, at.y, at.z, n, 0, 3.0, 0)
        if ok then
            local clear = #(node - at) < 40.0
            for _, b in pairs(busy) do clear = clear and #(node - b) > 8.0 end
            if clear then return node, true end
        end
    end
    return at, false
end

-- ─── a unit's life ────────────────────────────────────────────────────────────

local BLIP_COLOUR = { police = 38, cover = 38, pursuit = 38, air = 38, ambulance = 1, fire = 1, coroner = 0, mechanic = 47,
                      roadservice = 47, animalrescue = 2, taxi = 5, dot = 47 }

local LABEL = { police = 'Prisoner transport', ambulance = 'Ambulance', fire = 'Fire department', coroner = 'Coroner',
                mechanic = 'Mechanic', roadservice = 'Road service', animalrescue = 'Animal control', taxi = 'Taxi',
                cover = 'Cover unit', pursuit = 'Pursuit unit', air = 'Air unit', dot = 'DOT crew' }

-- How a unit looks, from its config (all optional): livery, paint, extras on the vehicle; outfit and props on the
-- crew. (SET_VEHICLE_EXTRA's last argument is "disable": true turns the extra off.)
function DressVehicle(veh, def)
    if def.livery then SetVehicleLivery(veh, def.livery) end
    if def.colours then SetVehicleColours(veh, def.colours[1], def.colours[2] or def.colours[1]) end
    for id, on in pairs(def.extras or {}) do SetVehicleExtra(veh, id, not on) end
end
function DressPed(p, def)
    for c, v in pairs(def.outfit or {}) do SetPedComponentVariation(p, c, v[1], v[2] or 0, 0) end
    for c, v in pairs(def.props or {}) do SetPedPropIndex(p, c, v[1], v[2] or 0, true) end
end

-- A unit counts (for "already en route", cancelling, the pursuit cap) from the moment it's asked for.
local function new_unit(kind, level)
    next_id = next_id + 1
    local u = { id = next_id, kind = kind, level = level, crew = {}, state = 'coming' }
    units[u.id] = u
    return u
end

-- Spawned in this thread (models are loaded here). -> true | false (then dispatch has said so, unless cancelled)
local function spawn(u, def, node, h, car_model)
    local kind = u.kind
    local function fail(quiet)
        units[u.id] = nil
        if not quiet then say(LABEL[kind] .. ' unavailable.') end
        return false
    end
    local cm = load(car_model or def.car)
    local crew_h = {}
    for i, m in ipairs(def.crew) do crew_h[i] = load(m) end
    if u.cancelled then return fail(true) end -- (called off while loading; nothing yields from here to the end)
    if not cm then return fail() end
    for _, x in ipairs(crew_h) do if not x then return fail() end end
    local z = kind == 'air' and node.z + 120.0 or node.z + 0.5
    local veh = CreateVehicle(cm, node.x, node.y, z, h, true, false)
    if veh == 0 then return fail() end
    spawned[veh] = true
    TagBackup(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), false)
    SetModelAsNoLongerNeeded(cm)
    DressVehicle(veh, def)
    local crew = {}
    for i, m in ipairs(crew_h) do
        local p = CreatePedInsideVehicle(veh, 26, m, i - 2, true, false) -- -1 driver, 0 front passenger...
        if p ~= 0 then
            spawned[p] = true
            crew[#crew + 1] = p
            TagBackup(p)
            SetEntityAsMissionEntity(p, true, true)
            SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(p), false)
            SetBlockingOfNonTemporaryEvents(p, true) -- ignore threats and gunfire: they never fight
            RemoveAllPedWeapons(p, true)
            SetPedKeepTask(p, true)
            DressPed(p, def)
        end
        SetModelAsNoLongerNeeded(m)
    end
    if not crew[1] then DeleteEntity(veh) spawned[veh] = nil return fail() end
    if kind == 'air' then SetHeliBladesFullSpeed(veh) end
    if def.lights then
        SetVehicleSiren(veh, true)
        if def.muted then SetVehicleHasMutedSirens(veh, true) end
    end
    u.veh, u.crew = veh, crew
    u.blip = AddBlipForEntity(veh)
    SetBlipColour(u.blip, BLIP_COLOUR[kind] or 0)
    SetBlipScale(u.blip, .8)
    report()
    return true
end

-- Still on the job (not called off, not leaving, crew and vehicle there): every step of a job checks it.
local function alive(u)
    return not u.cancelled and u.state ~= 'leaving' and u.veh and DoesEntityExist(u.veh) and u.crew[1]
        and DoesEntityExist(u.crew[1]) and not IsEntityDead(u.crew[1])
end

-- Drive to `at` and stop near it. Arrived: within B.arrive m of it or of the scene (a road that loops past the spot
-- would have them circling it), or stuck 12 s within 40 m (a few seconds' stop is the lights or traffic, not there
-- yet); too long: it turns up anyway. gap: stop this far from the scene and no nearer (a fire).
local function respond(u, at, found, lights, scene_at, gap)
    local driver = u.crew[1]
    local near = gap or B.arrive or 30.0
    TaskVehicleDriveToCoordLongrange(driver, u.veh, at.x, at.y, at.z, lights and B.speed or 15.0, lights and RESPOND or NORMAL, near)
    local still
    local arrived = wait_until(B.timeout * 1000, function()
        if not alive(u) then return true end
        local v = GetEntityCoords(u.veh)
        local d, moving = #(v - at), GetEntitySpeed(u.veh) > 0.5
        still = not moving and (still or GetGameTimer()) or nil
        return (not gap and d < near) or (scene_at and #(v - scene_at) < near)
            or (d < 40.0 and still and GetGameTimer() - still > 12000)
    end)
    if not alive(u) then return false end
    if not arrived and found and not gap and control(u.veh) then -- stuck: it turns up anyway (never onto the scene itself)
        SetEntityCoords(u.veh, at.x, at.y, at.z, false, false, false, false)
        SetVehicleOnGroundProperly(u.veh)
    end
    TaskVehicleTempAction(driver, u.veh, 27, 2000)
    Wait(1500)
    return alive(u)
end

local function delete(u)
    local ents = { u.veh }
    for _, p in ipairs(u.crew) do ents[#ents + 1] = p end -- (u.veh nil: called off before it spawned)
    for _, p in ipairs(u.carried or {}) do ents[#ents + 1] = p end
    for _, e in ipairs(ents) do if DoesEntityExist(e) then NetworkFadeOutEntity(e, false, true) end end
    Wait(1500)
    for _, e in ipairs(ents) do
        if DoesEntityExist(e) and control(e) then DetachEntity(e, false, false) DeleteEntity(e) end
        if not DoesEntityExist(e) then spawned[e], BackupEnts[e] = nil, nil end
    end
    if u.blip and DoesBlipExist(u.blip) then RemoveBlip(u.blip) end
    units[u.id] = nil
    report()
end

-- Back in, lights off, away; gone once well clear (or after a while).
local function leave(u)
    if u.state == 'leaving' then return end
    u.state, u.cancelled = 'leaving', true -- (spawn() checks this: one still loading never appears)
    CreateThread(function()
        if not u.veh or not DoesEntityExist(u.veh) then return delete(u) end
        for i, p in ipairs(u.crew) do
            if DoesEntityExist(p) and not IsEntityDead(p) and not IsPedInVehicle(p, u.veh, false) then
                ClearPedTasks(p)
                TaskEnterVehicle(p, u.veh, 15000, i - 2, 2.0, 1, 0)
            end
        end
        wait_until(16000, function()
            for _, p in ipairs(u.crew) do
                if DoesEntityExist(p) and not IsEntityDead(p) and not IsPedInVehicle(p, u.veh, false) then return false end
            end
            return true
        end)
        if u.kind == 'air' and NetworkGetEntityIsNetworked(u.veh) then Entity(u.veh).state:set('c3r_spot', nil, true) end -- (light off)
        local driver = u.crew[1]
        if DoesEntityExist(driver) and not IsEntityDead(driver) and IsPedInVehicle(driver, u.veh, false) and control(driver) then
            if u.kind == 'air' then
                local away = GetEntityCoords(u.veh) + vector3(math.random(-1, 1) * 900.0, 900.0, 150.0)
                TaskHeliMission(driver, u.veh, 0, 0, away.x, away.y, away.z, 4, 40.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0)
            else
                SetVehicleSiren(u.veh, false)
                TaskVehicleDriveWander(driver, u.veh, 15.0, NORMAL)
            end
        end
        local far = u.kind == 'air' and 400.0 or 150.0
        wait_until(u.kind == 'air' and 40000 or 60000, function()
            return not DoesEntityExist(u.veh) or #(GetEntityCoords(u.veh) - pos()) > far
        end)
        delete(u)
    end)
end

-- Out of the vehicle, then walk (or run) to an entity. -> true when there
local function walk_to(p, ent, run, within)
    if IsPedInAnyVehicle(p, false) then
        TaskLeaveVehicle(p, GetVehiclePedIsIn(p, false), 0)
        wait_until(5000, function() return not IsPedInAnyVehicle(p, false) end)
    end
    TaskGoToEntity(p, ent, -1, within or 1.5, run and 2.0 or 1.0, 0, 0)
    return wait_until(25000, function() return not DoesEntityExist(ent) or #(GetEntityCoords(p) - GetEntityCoords(ent)) < (within or 1.5) + 1.0 end)
end

local function scenario(p, name, ms)
    TaskStartScenarioInPlace(p, name, 0, true)
    Wait(ms)
    ClearPedTasks(p)
end

-- People and things near a point, the kind it's this unit's job to see to. Never another officer's stop, another
-- script's mission ped (unless it's this officer's own stop) or a player.
local function stop_ped(p)
    for _, o in pairs(Stop and Stop.occ or {}) do if o.ped == p then return o end end
end
-- (a callout's: the server marks them, client/medical.lua; or someone unhurt going with the ambulance: c:patient)
local casualty = function(p) return IsCasualty(p) or (NetworkGetEntityIsNetworked(p) and Entity(p).state.c3r_patient == true) end
local function ours(p) return stop_ped(p) ~= nil or Patients[p] ~= nil or casualty(p) or not IsEntityAMissionEntity(p) end
local function human(p) local h = IsPedHuman(p) return h == true or h == 1 end
local function peds_near(at, r, keep)
    local out = {}
    for _, p in ipairs(GetGamePool('CPed')) do
        if not IsBackup(p) and #(GetEntityCoords(p) - at) < r and keep(p) then out[#out + 1] = p end
    end
    return out
end

-- ─── the jobs ─────────────────────────────────────────────────────────────────

local JOB, CHECK = {}, {}

-- Prisoner transport: whoever's in custody (the back of the officer's car), or cuffed at the stop, within 60 m.
local function take_from_stop(net, s)
    if s and Stop == s then s.occ[net] = nil end
end

local function prisoners()
    local list, seen = {}, {}
    for net, c in pairs(Custody) do
        if DoesEntityExist(c.ped) and not IsEntityDead(c.ped) and #(GetEntityCoords(c.ped) - pos()) < 60.0 then
            list[#list + 1] = { ped = c.ped, net = net }
            seen[c.ped] = true
        end
    end
    for net, o in pairs(Stop and Stop.occ or {}) do
        if o.cuffed and not o.transported and not seen[o.ped] and DoesEntityExist(o.ped) and not IsEntityDead(o.ped)
            and #(GetEntityCoords(o.ped) - pos()) < 60.0 then
            list[#list + 1] = { ped = o.ped, net = net, o = o }
            seen[o.ped] = true
        end
    end
    -- anyone else in cuffs here: someone from a callout left standing cuffed while the officer talked to the next person
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not seen[ped] and IsPedCuffed(ped) and not IsPedAPlayer(ped) and not IsEntityDead(ped) and not IsBackup(ped)
            and not IsPedInAnyVehicle(ped, false) and NetworkGetEntityIsNetworked(ped) and #(GetEntityCoords(ped) - pos()) < 60.0 then
            list[#list + 1] = { ped = ped, net = PedToNet(ped) }
        end
    end
    return list
end
function CHECK.police() if #prisoners() == 0 then return 'no_prisoner' end end
function JOB.police(u)
    local taken, seat, s = 0, 1, Stop
    local max = GetVehicleMaxNumberOfPassengers(u.veh)
    u.carried = {}
    for _, pr in ipairs(prisoners()) do
        if not alive(u) then break end
        while seat < max and not IsVehicleSeatFree(u.veh, seat) do seat = seat + 1 end
        if seat >= max then break end
        if control(pr.ped) then
            local o = pr.o or stop_ped(pr.ped)
            if o then
                if o.escorted then DetachEntity(o.ped, true, false) o.escorted = false end
                o.transported, o.task, o.seated = true, {}, nil
                take_from_stop(pr.net, s)
            end
            Custody[pr.net] = nil
            ClearPedTasksImmediately(pr.ped) -- out of the patrol car at once
            TaskWarpPedIntoVehicle(pr.ped, u.veh, seat) -- a warp, as the cuffed are seated elsewhere (TASKS.seat)
            SetEnableHandcuffs(pr.ped, true)
            spawned[pr.ped] = true
            TagBackup(pr.ped)
            u.carried[#u.carried + 1] = pr.ped
            taken, seat = taken + 1, seat + 1
        end
    end
    if taken > 0 then
        local nets = {}
        for _, ped in ipairs(u.carried) do if NetworkGetEntityIsNetworked(ped) then nets[#nets + 1] = PedToNet(ped) end end
        TriggerServerEvent('c3r:callout:custody', nets, 'transport') -- (a callout's prisoner: taken in)
        note('transported', 'police', taken)
        Prompt('backup', 'ok', 'Prisoner transport', ('%d in custody, on the way to be booked.'):format(taken), 6000)
    else
        say('Prisoner transport: nobody in custody at the scene.')
    end
    report()
end

-- Paramedics, for everyone within 40 m of the scene, whether the officer saw to them or not: the downed (on the
-- ground hurt, or brought back with CPR) treated and taken to hospital in the back; the walking hurt (the officer
-- too) patched up where they stand; the dead checked and pronounced (the coroner takes them). The living first.
local function downed(p) return Patients[p] ~= nil or IsPedInWrithe(p) or IsPedInjured(p) or casualty(p) end
local function free_seat(veh)
    for seat = 1, GetVehicleMaxNumberOfPassengers(veh) - 1 do -- (the back: 1 on; the crew sit in front)
        if IsVehicleSeatFree(veh, seat) then return seat end
    end
end
function JOB.ambulance(u, at)
    local list = peds_near(at, 40.0, function(p)
        if not human(p) or IsPedInAnyVehicle(p, false) then return false end
        if p == me() then return not IsEntityDead(p) and GetEntityHealth(p) < GetEntityMaxHealth(p) end
        return not IsPedAPlayer(p) and ours(p) and (IsEntityDead(p) or GetEntityHealth(p) < GetEntityMaxHealth(p) or casualty(p))
    end)
    table.sort(list, function(a, b) return not IsEntityDead(a) and IsEntityDead(b) end)
    if #list == 0 then return say('Ambulance: nobody here needs treatment.') end
    local treated, taken, pronounced, revived = 0, 0, 0, 0
    u.carried = u.carried or {}
    for _, p in ipairs(list) do
        if not alive(u) then break end
        local was_dead = IsEntityDead(p) and not (Patients[p] and Patients[p].revived) -- (never someone brought back)
        for _, medic in ipairs(u.crew) do walk_to(medic, p, true, 1.2) end
        if not alive(u) then break end
        for _, medic in ipairs(u.crew) do TaskTurnPedToFaceEntity(medic, p, 1000) end
        Wait(800)
        -- the dead: one does CPR, the other helps (UNVERIFIED anim name, as client/medical.lua's); the rest: tended
        local cpr = was_dead and 'mini@cpr@char_a@cpr_str'
        if cpr then RequestAnimDict(cpr) wait_until(2000, function() return HasAnimDictLoaded(cpr) end) end
        for i, medic in ipairs(u.crew) do
            if i == 1 and cpr and HasAnimDictLoaded(cpr) then
                TaskPlayAnim(medic, cpr, 'cpr_pumpchest', 4.0, -4.0, 10000, 1, 0.0, false, false, false)
            else
                TaskStartScenarioInPlace(medic, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
            end
        end
        Wait(was_dead and 10000 or 8000)
        for _, medic in ipairs(u.crew) do ClearPedTasks(medic) end
        if IsEntityDead(p) and not (Patients[p] and Patients[p].revived) then was_dead = true end -- (gone while they worked)
        -- paramedics bring back Config.Medical.paramedic_revive of the dead; then they're a patient like any downed
        if was_dead and alive(u) and math.random() < (Config.Medical.paramedic_revive or 0) and control(p) and RevivePed(p) then
            was_dead, revived = false, revived + 1
        end
        if was_dead then
            pronounced = pronounced + 1
            if casualty(p) then TriggerServerEvent('c3r:callout:aid', PedToNet(p), 'pronounced') end -- (a callout's: the call hears it)
        elseif DoesEntityExist(p) and (p == me() or control(p)) then
            local seat = p ~= me() and downed(p) and free_seat(u.veh)
            if p ~= me() and casualty(p) then -- (a callout's: the call hears it, before they're moved)
                TriggerServerEvent('c3r:callout:aid', PedToNet(p), seat and 'hospital' or 'treated')
            end
            if seat then -- on a stretcher, into the back
                local o = stop_ped(p)
                if o then take_from_stop(o.net, Stop) end
                Patients[p] = nil
                FreezeEntityPosition(p, false) -- (a revived patient is held lying down)
                ClearPedTasksImmediately(p)
                SetEntityHealth(p, GetEntityMaxHealth(p))
                SetBlockingOfNonTemporaryEvents(p, true)
                TaskWarpPedIntoVehicle(p, u.veh, seat) -- (the project's convention for someone carried in)
                spawned[p] = true
                TagBackup(p)
                u.carried[#u.carried + 1] = p
                taken = taken + 1
            else
                SetEntityHealth(p, GetEntityMaxHealth(p))
                if p ~= me() and downed(p) then FreezeEntityPosition(p, false) ClearPedTasks(p) end -- (no room in the back: back on their feet)
                Patients[p] = nil
                treated = treated + 1
            end
        end
    end
    report()
    local lines = {}
    if revived > 0 then lines[#lines + 1] = ('%d brought back.'):format(revived) end
    if taken > 0 then lines[#lines + 1] = ('%d taken to hospital.'):format(taken) end
    if treated > 0 then lines[#lines + 1] = ('%d treated at the scene.'):format(treated) end
    if pronounced > 0 then lines[#lines + 1] = ('%d pronounced dead: the coroner can take them.'):format(pronounced) end
    if lines[1] then Prompt('backup', pronounced > 0 and 'info' or 'ok', 'Paramedics', table.concat(lines, ' '), 8000) end
    for _, n in ipairs({ { 'revived', revived }, { 'hospital', taken }, { 'treated', treated }, { 'pronounced', pronounced } }) do
        if n[2] > 0 then note(n[1], 'ambulance', n[2]) Wait(300) end -- (the server takes a few notes a second)
    end
end

-- Coroner / animal control: the dead within 40 m (people / animals), taken away.
local function remove_dead(u, at, kind, want_human)
    local dead = peds_near(at, 40.0, function(p)
        return IsEntityDead(p) and not IsPedAPlayer(p) and human(p) == want_human and ours(p)
    end)
    local removed = 0
    for _, p in ipairs(dead) do
        if not alive(u) then break end
        walk_to(u.crew[1], p, false, 1.2)
        if not alive(u) then break end
        scenario(u.crew[1], 'CODE_HUMAN_MEDIC_KNEEL', 6000)
        if alive(u) and control(p) then
            NetworkFadeOutEntity(p, false, true)
            Wait(1200)
            DeleteEntity(p)
            removed = removed + 1
        end
    end
    if removed > 0 then note('removed', kind, removed) end
    if #dead == 0 then
        say(LABEL[kind] .. ': nothing here for us.')
        Wait(4000)
    end
end
function JOB.coroner(u, at) remove_dead(u, at, 'coroner', true) end
function JOB.animalrescue(u, at) remove_dead(u, at, 'animalrescue', false) end

-- Fire: the fires within 30 m of the scene, and anything burning there.
function JOB.fire(u, at)
    for _, p in ipairs(u.crew) do
        TaskLeaveVehicle(p, u.veh, 0)
    end
    Wait(2500)
    for _, p in ipairs(u.crew) do -- (up to 8 m short of it, from the truck's side: never into the fire)
        local from = GetEntityCoords(u.veh)
        local d = #(from - at)
        local to = d > 8.0 and at + (from - at) / d * 8.0 or from
        TaskGoStraightToCoord(p, to.x, to.y, to.z, 2.0, 15000, 0.0, 1.0)
    end
    Wait(6000)
    StopFireInRange(at.x, at.y, at.z, 30.0)
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(v) - at) < 30.0 and IsEntityOnFire(v) then StopEntityFire(v) end
    end
    for _, p in ipairs(GetGamePool('CPed')) do
        if #(GetEntityCoords(p) - at) < 30.0 and IsEntityOnFire(p) then StopEntityFire(p) end
    end
    Wait(4000)
    if alive(u) then TriggerServerEvent('c3r:callout:service', 'fire', at) end
end

-- DOT: out of the truck, a sweep of the road, and the call hears it's clean.
function JOB.dot(u, at)
    for _, p in ipairs(u.crew) do TaskLeaveVehicle(p, u.veh, 0) end
    Wait(2500)
    for _, p in ipairs(u.crew) do TaskGoStraightToCoord(p, at.x, at.y, at.z, 1.5, 12000, 0.0, 3.0) end
    Wait(7000)
    if not alive(u) then return end
    for _, p in ipairs(u.crew) do TaskStartScenarioInPlace(p, 'WORLD_HUMAN_JANITOR', 0, true) end -- UNVERIFIED scenario
    Wait(14000)
    if not alive(u) then return end
    for _, p in ipairs(u.crew) do ClearPedTasks(p) end
    TriggerServerEvent('c3r:callout:service', 'dot', at)
end

-- Mechanic / road service: the officer's own car, within 40 m.
local function own_car()
    local v = GetVehiclePedIsIn(me(), true)
    return v ~= 0 and DoesEntityExist(v) and #(GetEntityCoords(v) - pos()) < 40.0 and v or nil
end
function CHECK.mechanic() if not own_car() then return 'no_vehicle' end end
CHECK.roadservice = CHECK.mechanic
function JOB.mechanic(u)
    local v = own_car()
    if not v then return say(LABEL[u.kind] .. ': no vehicle at the scene.') end
    local p = u.crew[1]
    walk_to(p, v, false, 3.0)
    local front = GetOffsetFromEntityInWorldCoords(v, 0.0, 2.6, 0.0)
    TaskGoStraightToCoord(p, front.x, front.y, front.z, 1.0, 6000, GetEntityHeading(v) + 180.0, 0.5)
    Wait(3000)
    if control(v) then SetVehicleDoorOpen(v, 4, false, false) end
    RequestAnimDict('mini@repair')
    wait_until(2000, function() return HasAnimDictLoaded('mini@repair') end)
    if HasAnimDictLoaded('mini@repair') then TaskPlayAnim(p, 'mini@repair', 'fixing_a_ped', 4.0, -4.0, 8000, 1, 0.0, false, false, false) end
    Wait(8000)
    if alive(u) and control(v) then
        SetVehicleEngineHealth(v, 1000.0) -- (SET_VEHICLE_FIXED can't fix a broken engine)
        SetVehicleBodyHealth(v, 1000.0)
        SetVehicleFixed(v)
        SetVehicleDoorShut(v, 4, false)
        note('repaired', u.kind)
        Prompt('backup', 'ok', 'Vehicle repaired', 'The mechanic fixed your car.', 5000)
    end
end
JOB.roadservice = JOB.mechanic

-- Taxi: stop occupants left without a ride (their car towed, the driver arrested, gone or run off), or someone on a call
-- waiting for one (c:fare).
local function stranded(at)
    local fares = {}
    for _, p in ipairs(peds_near(at or pos(), 40.0, function(p)
        return NetworkGetEntityIsNetworked(p) and Entity(p).state.c3r_taxi == true and not IsEntityDead(p) and not IsPedCuffed(p) and not IsPedInAnyVehicle(p, false)
    end)) do
        fares[#fares + 1] = { ped = p, net = PedToNet(p) }
    end
    if fares[1] then return fares end
    local s = Stop
    if not s or s.foot then return {} end
    local d = s.occ[s.ped_net]
    local no_ride = s.towed or not DoesEntityExist(s.veh) or not d or d.cuffed or d.transported or d.escaped
    if not no_ride then return {} end
    local list = {}
    for _, o in pairs(s.occ) do
        if not o.cuffed and not o.fleeing and not o.escaped and not o.transported and DoesEntityExist(o.ped)
            and not IsEntityDead(o.ped) and not IsPedInAnyVehicle(o.ped, false) then
            list[#list + 1] = o
        end
    end
    return list
end
function CHECK.taxi() if #stranded() == 0 then return 'nobody_to_collect' end end
function JOB.taxi(u, at)
    local seat, max, s = 0, GetVehicleMaxNumberOfPassengers(u.veh), Stop
    u.carried = {}
    local list = stranded(at)
    if #list == 0 then return say('Taxi: nobody waiting for a ride.') end
    for _, o in ipairs(list) do
        while seat < max and not IsVehicleSeatFree(u.veh, seat) do seat = seat + 1 end
        if seat >= max then break end
        if control(o.ped) then
            o.leaving, o.anchor, o.task, o.following = true, nil, {}, false
            if o.felony then DropFelonyPose(o) end
            if s and s.occ[o.net] then take_from_stop(o.net, s) end -- the stop's loops, menus and its end (walk off / let go) leave them be now
            spawned[o.ped] = true
            TagBackup(o.ped)
            ClearPedTasks(o.ped)
            TaskEnterVehicle(o.ped, u.veh, 20000, seat, 1.0, 1, 0)
            u.carried[#u.carried + 1] = o.ped
            seat = seat + 1
        end
    end
    wait_until(25000, function()
        for _, p in ipairs(u.carried) do if DoesEntityExist(p) and not IsPedInVehicle(p, u.veh, false) then return false end end
        return true
    end)
    report()
    local aboard = false
    for _, p in ipairs(u.carried) do aboard = aboard or (DoesEntityExist(p) and IsPedInVehicle(p, u.veh, false)) end
    if aboard then TriggerServerEvent('c3r:callout:service', 'taxi', GetEntityCoords(u.veh)) end
end

-- Cover: parks behind the officer's car, lights on, siren muted; one officer stands by.
function JOB.cover(u, at, started_on)
    local p = u.crew[1]
    TaskLeaveVehicle(p, u.veh, 0)
    wait_until(5000, function() return not IsPedInAnyVehicle(p, false) end)
    TaskStartScenarioInPlace(p, 'WORLD_HUMAN_COP_IDLES', 0, true)
    local ends = GetGameTimer() + B.cover_minutes * 60000
    local stop_gone
    wait_until(B.cover_minutes * 60000, function()
        if not alive(u) or GetGameTimer() > ends or #(GetEntityCoords(u.veh) - pos()) > 200.0 then return true end
        if started_on and Stop ~= started_on then stop_gone = stop_gone or GetGameTimer() end
        return stop_gone and GetGameTimer() - stop_gone > 30000
    end)
end

-- The tow: the stop's car (the server notes it, from up to the stop's own range), else the nearest car on its own.
-- The same rule as lwk_control's spoken "tow truck en route for the ..." (see the towTarget export).
local function tow_target()
    local s = Stop
    if s and not s.foot and s.veh ~= 0 and DoesEntityExist(s.veh) and not s.towed then return s.veh, true end
    local me_ = me()
    local own, last = GetVehiclePedIsIn(me_, false), GetVehiclePedIsIn(me_, true)
    local best, best_d = nil, 15.0
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(v) - pos())
        if d < best_d and v ~= own and v ~= last and GetVehicleClass(v) ~= 18 and not IsBackup(v) and GetEntitySpeed(v) < 1.0
            and (not IsEntityAMissionEntity(v) or (NetworkGetEntityIsNetworked(v) and Entity(v).state.c3r_callout == true)) then
            local last_driver = GetLastPedInVehicleSeat(v, -1)
            local anyone = last_driver ~= 0 and IsPedAPlayer(last_driver) -- (a player's own car, parked) or anyone in it
            for seat = -1, GetVehicleMaxNumberOfPassengers(v) - 1 do anyone = anyone or GetPedInVehicleSeat(v, seat) ~= 0 end
            if not anyone then best, best_d = v, d end
        end
    end
    return best, false
end
exports('towTarget', function() return (tow_target()) end)

-- ─── requests (the contract) ──────────────────────────────────────────────────

local KINDS = { police = true, ambulance = true, fire = true, coroner = true, mechanic = true, roadservice = true,
                animalrescue = true, taxi = true, cover = true, tow = true, dot = true }

local function on_duty() return LocalPlayer.state.c3rDuty == true and not IsEntityDead(me()) end

local tow_asked = -60000
local function chase_on()
    for _, o in pairs(Stop and Stop.occ or {}) do if o.fleeing then return true end end
    return Stop ~= nil and Stop.pursuit == true
end
local function request_tow()
    -- (TowBusy only once the truck's models load; tow_asked covers the moments before)
    if TowBusy() or GetGameTimer() - tow_asked < 15000 then return false, 'already_en_route' end
    if chase_on() then return false, 'in_pursuit' end
    local car, of_stop = tow_target()
    if not car then return false, 'no_vehicle' end
    if of_stop then
        if #(GetEntityCoords(car) - pos()) > Config.CancelDistance - 10.0 then return false, 'too_far' end -- (margin: the server checks too)
        TriggerServerEvent('c3r:stop:act', 'tow', nil, Stop.ped_net, true) -- the server notes it and starts the truck
    else
        CreateThread(function() TowCar(car, nil) end)
        note('requested', 'tow')
    end
    tow_asked = GetGameTimer()
    return true
end

-- The server turned down a radio tow the officer was told is coming (the stop ended, or the car is out of range).
RegisterNetEvent('c3r:stop:towRefused', function()
    tow_asked = -60000
    say('Unable to send a tow truck right now.')
end)

-- The AI crew: from out of sight to `at`, its job there, then away.
local function send_unit(kind, def, at, started_on)
    local node, h = spawn_point(at)
    if not node then return false, 'no_route' end
    local u = new_unit(kind)
    CreateThread(function()
        if not spawn(u, def, node, h) then return end
        local park, found = park_point(at)
        local arrived = respond(u, park, found, def.lights, at, kind == 'fire' and (B.fire_gap or 25.0) or nil)
        if not arrived and not u.cancelled and u.state ~= 'leaving' then say(LABEL[kind] .. ' unable to reach you.') end
        if arrived and JOB[kind] then
            u.state = 'working'
            local done = false
            CreateThread(function() JOB[kind](u, at, started_on) done = true end)
            wait_until(kind == 'cover' and (B.cover_minutes * 60000 + 5000) or B.job_timeout * 1000, function() return done or not alive(u) end)
        end
        leave(u)
    end)
    return true
end

local asked = nil -- help asked of the other service's players first (server/ems.lua): { kind, at, started_on }

local function medic() return LocalPlayer.state.c3rService == 'ambulance' end
-- Asked of players first: an officer's ambulance, a medic's police (a patrol unit to stand by, the AI fallback).
local function asks_players(kind) return (kind == 'ambulance' and not medic()) or (kind == 'cover' and medic()) end

local function request(kind)
    if not on_duty() then return false, 'off_duty' end
    if kind == 'police' and medic() then kind = 'cover' end -- (a medic asking for police wants help on scene, not a transport)
    if not KINDS[kind] then return false, 'not_available' end
    if kind == 'tow' then return request_tow() end
    if active(kind) or (asked and asked.kind == kind) then return false, 'already_en_route' end
    local def = B.units[kind]
    if not def or not models_ok(def) then return false, 'not_available' end
    local why = CHECK[kind] and CHECK[kind]()
    if why then return false, why end
    local at = scene()
    if kind == 'dot' or kind == 'animalrescue' or kind == 'fire' then at = CallSpot(200.0) or at end -- (the road, not whoever I'm talking to)
    if asks_players(kind) then -- (a free player first: the server answers, and the AI unit is the fallback)
        if asked then return false, 'already_en_route' end
        if not spawn_point(at) then return false, 'no_route' end
        asked = { kind = kind, at = at, started_on = Stop }
        TriggerServerEvent('c3r:ems:request', at, kind == 'cover' and 'police' or 'ambulance')
    else
        local ok, no = send_unit(kind, def, at, Stop)
        if not ok then return false, no end
    end
    note('requested', kind)
    return true
end

exports('requestService', request)

-- No medic free, none took it in time, or the one who did gave up: the AI crew, to where it was asked for.
RegisterNetEvent('c3r:ems:request:ai', function(why)
    local a = asked
    asked = nil
    if not a or not on_duty() then return end
    local police = a.kind == 'cover'
    if why ~= 'none' then
        say(police and 'No officer available. A patrol unit is on its way.' or 'No paramedic available. An ambulance crew is on its way.')
    end
    local def = B.units[a.kind]
    if not (def and send_unit(a.kind, def, a.at, a.started_on)) then say((police and 'Patrol unit' or 'Ambulance') .. ' unable to reach you.') end
end)
RegisterNetEvent('c3r:ems:request:accepted', function(name)
    say(('%s %s is responding to your location.'):format(asked and asked.kind == 'cover' and 'Officer' or 'Paramedic', name))
end)
RegisterNetEvent('c3r:ems:request:arrived', function(name)
    local police = asked and asked.kind == 'cover'
    asked = nil
    Prompt('backup', 'ok', police and 'Police' or 'Ambulance', ('%s is on scene.'):format(name), 5000)
end)

local function cancel(kind)
    if kind == 'tow' then -- (until the car's on the flatbed: client/stop.lua TowCancel)
        local ok, why = TowCancel(GetGameTimer() - tow_asked < 15000)
        if ok then tow_asked = -60000 end
        return ok, why
    end
    if kind == 'police' and medic() then kind = 'cover' end
    if asked and asked.kind == kind then -- (still with the other service's players)
        asked = nil
        TriggerServerEvent('c3r:ems:request:cancel')
        return true
    end
    local u = active(kind)
    if not u then return false, 'not_en_route' end
    u.cancelled = true
    leave(u)
    return true
end

-- ─── pursuit backup ───────────────────────────────────────────────────────────

-- What they chase: the fleeing car, or the fleeing person on foot. -> entity, on_foot | nil
local function chase_target()
    local s = Stop
    if not s then return nil end
    if s.pursuit and DoesEntityExist(s.veh) then return s.veh, false end
    for _, o in pairs(s.occ) do
        if o.fleeing and DoesEntityExist(o.ped) then return o.ped, true end
    end
end

local CHASE_FLAG = { light = 32, medium = 32, heavy = 8 } -- stay back / stay back / boxing with a bit of PIT

local function pursue(u, target, on_foot)
    local driver = u.crew[1]
    if not alive(u) or not control(driver) then return end
    if u.kind == 'air' then
        TaskHeliChase(driver, target, 0.0, 0.0, 50.0)
        SetVehicleSearchlight(u.veh, false, false) -- (the game's own sweeps about: ours stays on them, see spot below)
        if NetworkGetEntityIsNetworked(u.veh) and NetworkGetEntityIsNetworked(target) then
            Entity(u.veh).state:set('c3r_spot', NetworkGetNetworkIdFromEntity(target), true)
        end
        return
    end
    if not on_foot then
        TaskVehicleChase(driver, target)
        SetTaskVehicleChaseBehaviorFlag(driver, CHASE_FLAG[u.level] or 32, true)
        if u.level ~= 'heavy' then -- no ramming (1, 2, 16) for light and medium, whatever the task's defaults
            for _, f in ipairs({ 1, 2, 16 }) do SetTaskVehicleChaseBehaviorFlag(driver, f, false) end
        end
        SetTaskVehicleChaseIdealPursuitDistance(driver, u.level == 'light' and 25.0 or 15.0)
        return
    end
    -- on foot: drive to 30 m short of them, stopping for people, then run after them; never a car at a person
    CreateThread(function()
        local mine = {}
        u.foot = mine
        while u.foot == mine and alive(u) and DoesEntityExist(target) and IsPedInVehicle(driver, u.veh, false)
            and #(GetEntityCoords(u.veh) - GetEntityCoords(target)) > 40.0 do
            local t = GetEntityCoords(target)
            local v = GetEntityCoords(u.veh)
            local short = t + (v - t) / math.max(#(v - t), 1.0) * 30.0
            TaskVehicleDriveToCoordLongrange(driver, u.veh, short.x, short.y, short.z, 18.0, RESPOND, 5.0)
            Wait(3000)
        end
        if u.foot ~= mine or not alive(u) or not DoesEntityExist(target) then return end
        TaskVehicleTempAction(driver, u.veh, 27, 2000)
        Wait(1500)
        for _, p in ipairs(u.crew) do
            if DoesEntityExist(p) and not IsEntityDead(p) then
                TaskLeaveVehicle(p, u.veh, 0)
                SetTimeout(1500, function()
                    if DoesEntityExist(p) and DoesEntityExist(target) then TaskGoToEntity(p, target, -1, 2.0, 3.0, 0, 0) end
                end)
            end
        end
    end)
end

-- The air unit's searchlight, locked on whoever it's chasing (the car, or them on foot once they bail): drawn by
-- every game near the helicopter, since the game that runs it puts c3r_spot = the target's net id on it.
local Spots = {} -- [state bag name] = { net = target net id, seen = when the helicopter was last in this game }
AddStateBagChangeHandler('c3r_spot', nil, function(bag, _, value)
    Spots[bag] = math.type(value) == 'integer' and { net = value, seen = GetGameTimer() } or nil
end)
CreateThread(function()
    while true do
        if next(Spots) then
            local n = 0
            for bag, s in pairs(Spots) do
                local heli = GetEntityFromStateBagName(bag)
                local target = NetworkDoesNetworkIdExist(s.net) and NetToEnt(s.net) or 0
                if heli == 0 or not DoesEntityExist(heli) then
                    -- (not in this game yet, or gone: forgotten once it's been away a while)
                    if GetGameTimer() - s.seen > 30000 then Spots[bag] = nil end
                elseif DoesEntityExist(target) then
                    s.seen, n = GetGameTimer(), n + 1
                    local from = GetOffsetFromEntityInWorldCoords(heli, 0.0, 2.0, -1.2) -- (the nose, underneath)
                    local d = GetEntityCoords(target) - from
                    local len = #d
                    if len > 1.0 and len < 300.0 then
                        d = d / len
                        DrawSpotLightWithShadow(from.x, from.y, from.z, d.x, d.y, d.z, 255, 250, 235, len + 25.0, 14.0, 1.0, 9.0, 18.0, n)
                    end
                else
                    s.seen = GetGameTimer()
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- One loop for every pursuit unit: follow the chase as it changes (car to foot), and all leave once it's over.
local watching = false
local function watch_chase()
    if watching then return end
    watching = true
    CreateThread(function()
        local last_target, over_since
        while true do
            local any = false
            for _, u in pairs(units) do if (u.kind == 'pursuit' or u.kind == 'air') and u.state ~= 'leaving' then any = true end end
            if not any then break end
            local target, on_foot = chase_target()
            if target then
                over_since = nil
                if target ~= last_target then
                    last_target = target
                    local list = {} -- (pursue can wait on control; new units may be added meanwhile)
                    for _, u in pairs(units) do list[#list + 1] = u end
                    for _, u in ipairs(list) do
                        if (u.kind == 'pursuit' or u.kind == 'air') and u.state ~= 'leaving' and not u.spikes then u.foot = nil pursue(u, target, on_foot) end
                    end
                end
            else
                over_since = over_since or GetGameTimer() -- (a moment's grace: a driver bailing out is still the chase)
                if GetGameTimer() - over_since > 5000 then
                    for _, u in pairs(units) do if u.kind == 'pursuit' or u.kind == 'air' then leave(u) end end
                    break
                end
            end
            Wait(1000)
        end
        watching = false
    end)
end

exports('cancelService', cancel)

-- A unit up ahead stays put and its officer lays a Stop Stick (lwk_stopstick) across the suspect's path 20 m short
-- of the car, from the roadside; once the suspect is past (or the chase moves on) it's pulled and the unit gives chase.
-- (on the suspect's line of travel: their lane on a straight road, a miss on a bend)
local function lay_spikes(u, target, ahead)
    local p = u.crew[#u.crew]
    local tp, v = GetEntityCoords(target), GetEntityCoords(u.veh)
    local along = function(at) return (at.x - tp.x) * ahead.x + (at.y - tp.y) * ahead.y end
    local at = tp + ahead * (along(v) - 20.0)
    local ok, gz = GetGroundZFor_3dCoord(at.x, at.y, at.z + 5.0, false)
    at = vector3(at.x, at.y, ok and gz or at.z)
    local side = at + vector3(ahead.y, -ahead.x, 0.0) * 5.0 -- (the right-hand verge)
    local laid = false
    if along(at) > 40.0 and control(p) then -- (the suspect isn't already on top of it)
        TaskLeaveVehicle(p, u.veh, 0)
        wait_until(4000, function() return not IsPedInAnyVehicle(p, false) end)
        TaskGoStraightToCoord(p, side.x, side.y, side.z, 3.0, 8000, 0.0, 0.5)
        wait_until(8000, function()
            local tnow = DoesEntityExist(target) and GetEntityCoords(target)
            return not alive(u) or not tnow or #(GetEntityCoords(p) - side) < 1.5 or #(tnow - at) < 50.0
        end)
        if alive(u) and DoesEntityExist(target) and along(GetEntityCoords(target)) < along(at) then
            TaskTurnPedToFaceCoord(p, at.x, at.y, at.z, 600)
            RequestAnimDict('lwk_stopstick@anims')
            wait_until(1000, function() return HasAnimDictLoaded('lwk_stopstick@anims') end)
            TaskPlayAnim(p, 'lwk_stopstick@anims', 'throw', 4.0, -4.0, 1200, 0, 0.0, false, false, false)
            Wait(600)
            local angle = math.deg(math.atan(ahead.y, ahead.x)) + 90.0 -- across the road
            TriggerServerEvent('c3r:backup:spikes', at, angle, GetPedBoneCoords(p, 28422, 0.0, 0.0, 0.0))
            laid = true
        end
    end
    -- up once the suspect is 15 m past it, or gone, or the unit is called off; 90 s at most
    if laid then
        wait_until(90000, function()
            return not alive(u) or not DoesEntityExist(target) or chase_target() ~= target or along(GetEntityCoords(target)) > along(at) + 15.0
        end)
        Wait(1500)
        TriggerServerEvent('c3r:backup:spikesUp')
    end
    u.spikes = nil
    if not alive(u) then return end
    if not IsPedInVehicle(p, u.veh, false) then
        TaskEnterVehicle(p, u.veh, 10000, #u.crew - 2, 2.0, 1, 0)
        wait_until(10000, function() return not alive(u) or IsPedInVehicle(p, u.veh, false) end)
    end
    local t, foot = chase_target()
    if t and alive(u) then pursue(u, t, foot) end
end

local function request_pursuit(level)
    if not on_duty() then return false, 'off_duty' end
    local target, on_foot = chase_target()
    if not target then
        if level == 'air' then return false, 'no_pursuit' end
        local ok, why = request('cover') -- "backup" with no chase on: a unit to stand by
        return ok, ok and 'cover' or why -- (so dispatch says "cover unit", not "pursuit units")
    end
    local def = B.units[level == 'air' and 'air' or 'pursuit']
    if level == 'air' then
        if active('air') then return false, 'already_en_route' end
        if not models_ok(def) then return false, 'not_available' end
    end
    local count = level == 'air' and 1 or (B.pursuit[level] or B.pursuit.medium)
    if level ~= 'air' then
        local cars = 0
        for _, u in pairs(units) do if u.kind == 'pursuit' and u.state ~= 'leaving' then cars = cars + 1 end end
        count = math.min(count, B.pursuit.max - cars)
        if count <= 0 then return false, 'enough_units' end
    end
    -- they come from up ahead of the suspect, the way they're going (from behind they'd never catch up)
    local tp = GetEntityCoords(target)
    local vel = GetEntityVelocity(target)
    local ahead = #(vector3(vel.x, vel.y, 0.0)) > 2.0 and vector3(vel.x, vel.y, 0.0) / #(vector3(vel.x, vel.y, 0.0)) or nil
    local points, taken = {}, {}
    for i = 1, count do
        local node, h = spawn_point(tp, ahead, taken)
        if not node then break end
        points[#points + 1] = { node, h, level ~= 'air' and def.cars[math.random(#def.cars)] or nil }
    end
    if #points == 0 then return false, 'no_route' end
    if level ~= 'air' then
        for _, pt in ipairs(points) do if not models_ok(def, pt[3]) then return false, 'not_available' end end
    end
    local spikes = level ~= 'air' and ahead and not on_foot and math.random() < (B.spikes or 0)
        and GetResourceState('lwk_stopstick') == 'started'
    for i, pt in ipairs(points) do
        local u = new_unit(level == 'air' and 'air' or 'pursuit', level)
        CreateThread(function()
            if not spawn(u, def, pt[1], pt[2], pt[3]) then return end
            local t, foot = chase_target()
            if not t then return leave(u) end
            if spikes and i == 1 and not foot then
                u.spikes = true -- (watch_chase leaves it be until the stick is up)
                watch_chase()
                return lay_spikes(u, t, ahead)
            end
            -- (rolling the way the suspect is going, never at them: spawn_point faces them along `ahead`)
            if level ~= 'air' and ahead then SetVehicleForwardSpeed(u.veh, 12.0) end
            pursue(u, t, foot)
            watch_chase()
        end)
    end
    note('requested', level)
    return true
end

exports('requestPursuitBackup', request_pursuit)

local function cancel_pursuit()
    local any = false
    for _, u in pairs(units) do
        if (u.kind == 'pursuit' or u.kind == 'air' or u.kind == 'cover') and u.state ~= 'leaving' then
            u.cancelled = true
            leave(u)
            any = true
        end
    end
    if not any then return false, 'no_backup' end
    return true
end
exports('cancelPursuitBackup', cancel_pursuit)

-- ─── the radial menus (E, G) ──────────────────────────────────────────────────
-- Through dispatch, as if it had been said (its voice, its reply); straight here when lwk_control isn't running,
-- with the answer on screen. what: a service kind, a pursuit level, or 'cancel_pursuit'.
ChaseOn = chase_on
local CODE = { light = 1, medium = 2, heavy = 3 }
-- what: also 'cancel:<kind>' (a unit on its way or at work called off).
function CallBackup(what)
    local id, ctx = 'request_' .. tostring(what), nil
    local off = type(what) == 'string' and what:match('^cancel:(.+)$')
    if off then id = 'cancel_' .. off
    elseif what == 'air' then id = 'air_support'
    elseif CODE[what] then id, ctx = 'pursuit_backup', { code = CODE[what] }
    elseif what == 'cancel_pursuit' then id = 'cancel_backup' end
    local ok, ran = pcall(function() return exports.lwk_control:run(id, ctx) end)
    if ok and ran then return end
    local yes, why
    if off then yes, why = cancel(off)
    elseif what == 'cancel_pursuit' then yes, why = cancel_pursuit()
    elseif what == 'air' or CODE[what] then yes, why = request_pursuit(what)
    else yes, why = request(what) end
    local name = LABEL[off or what] or (CODE[what] or what == 'air') and 'Backup' or 'Tow truck'
    Prompt('backup', yes and 'ok' or 'alert', name, yes and (off and 'Cancelled.' or 'En route.')
        or ('Unable: ' .. tostring(why):gsub('_', ' ')), 5000)
end

-- On its way or at work: the wheels offer "Cancel ..." instead. (A tow can't be called back.)
function BackupActive(kind)
    if kind == 'tow' then return TowPending() or GetGameTimer() - tow_asked < 15000 end
    if asked and asked.kind == kind then return true end
    return active(kind) ~= nil
end

-- ─── when everyone goes home ──────────────────────────────────────────────────
-- Off duty or dead: every unit leaves. lwk_pd stopping: everything is deleted at once.
CreateThread(function()
    local tick = 0
    while true do
        Wait(1000)
        tick = tick + 1
        if asked and not on_duty() then asked = nil end -- (the server forgets it too)
        if next(units) and not on_duty() then
            local list = {}
            for _, u in pairs(units) do list[#list + 1] = u end
            for _, u in ipairs(list) do leave(u) end
        end
        if tick % 5 == 0 and next(BackupEnts) then report() end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for e in pairs(spawned) do if DoesEntityExist(e) then DeleteEntity(e) end end
    for e in pairs(BackupEnts) do if DoesEntityExist(e) then DetachEntity(e, false, false) DeleteEntity(e) end end -- (a towed car too)
    for _, u in pairs(units) do if u.blip and DoesBlipExist(u.blip) then RemoveBlip(u.blip) end end
end)
