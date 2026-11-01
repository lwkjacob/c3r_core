--[[
    c3r — client: someone down (dead, or on the ground hurt). Press E beside them for the medical wheel: check their
    vitals, CPR, pressure on the wound, or call an ambulance or the coroner. Paramedics (client/backup.lua) see to
    anyone down near the officer, whether they were seen to first or not: the downed go to hospital, the dead are
    pronounced.

    Natives as documented in citizenfx/natives: IS_PED_IN_WRITHE ("on the ground, in pain from a (gunshot) wound"),
    IS_PED_INJURED (health below the injured threshold, 100 by default), RESURRECT_PED (place the ped first and clear
    its tasks, or it can drop through the ground). GET_PED_TIME_OF_DEATH isn't used: its unit isn't documented. How
    long they've been dead is watched here instead: seen alive, then dead, they died then; dead the first time
    they're seen, they've been gone a while. The animation dictionaries aren't in the official docs: UNVERIFIED (one
    that's missing just doesn't play).
]]

local M = Config.Medical
local REACH = 2.2 -- m from the body (its root is at the hips)
local open, target, busy = false, nil, false
local life = {}             -- [ped] = true: seen alive; a game timer: when they were seen to die (0: already dead)
Patients = Patients or {}   -- [ped] = { stable = health held at, down = held lying, revived } : seen to by the officer (paramedics take them)

local ANIM = { -- UNVERIFIED names (see the header)
    vitals = { 'amb@medic@standing@kneel@idle_a', 'idle_a' },
    pressure = { 'amb@medic@standing@tendtodead@idle_a', 'idle_a' },
    cpr = { 'mini@cpr@char_a@cpr_str', 'cpr_pumpchest' },
    lying = { 'amb@world_human_bum_slumped@male@laying_on_left_side@base', 'base' },
}
local SPINE = 24818 -- SKEL_Spine3: their chest

local function human(p) local h = IsPedHuman(p) return h == true or h == 1 end

-- Down: dead, or on the ground hurt (or a callout's casualty: the c3r_down state the server puts on them). Never a
-- player, backup, or someone sat in a car.
function IsDowned(p)
    return DoesEntityExist(p) and not IsPedAPlayer(p) and human(p) and not IsBackup(p) and not IsPedInAnyVehicle(p, false)
        and (IsEntityDead(p) or IsPedInWrithe(p) or IsPedInjured(p) or Patients[p] ~= nil or IsCasualty(p))
end

-- A callout's casualty (server/callouts.lua marks them). Only networked peds have state bags.
function IsCasualty(p) return NetworkGetEntityIsNetworked(p) and Entity(p).state.c3r_down == true end

-- The nearest one beside the officer (on foot), or nil.
function DownedNear()
    local me = PlayerPedId()
    if IsPedInAnyVehicle(me, false) then return nil end
    local pos, best, best_d = GetEntityCoords(me), nil, REACH
    for _, p in ipairs(GetGamePool('CPed')) do
        local d = p ~= me and #(GetEntityCoords(p) - pos)
        if d and d < best_d and IsDowned(p) then best, best_d = p, d end
    end
    return best
end
function MedicalOpen() return open or busy end

local function control(ent)
    local deadline = GetGameTimer() + 1500
    while DoesEntityExist(ent) and not NetworkHasControlOfEntity(ent) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(ent)
        Wait(0)
    end
    return DoesEntityExist(ent) and NetworkHasControlOfEntity(ent)
end

local function load_dict(d)
    RequestAnimDict(d)
    local deadline = GetGameTimer() + 2000
    while not HasAnimDictLoaded(d) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(d)
end

-- ms since they died (nil: alive)
local function dead_for(p)
    if not IsEntityDead(p) then return nil end
    local now = GetGameTimer()
    if type(life[p]) ~= 'number' then life[p] = life[p] and now or 0 end -- (died since the last look, or long ago)
    return now - life[p]
end

-- Who's alive and who just died, every second, everyone the game has loaded.
local function watch_lives()
    local now = GetGameTimer()
    for _, p in ipairs(GetGamePool('CPed')) do
        if not IsEntityDead(p) then life[p] = true
        elseif type(life[p]) ~= 'number' then life[p] = life[p] and now or 0 end
    end
    for ped in pairs(life) do if not DoesEntityExist(ped) then life[ped] = nil end end
end

-- ─── the wheel ────────────────────────────────────────────────────────────────

local function items(p)
    local dead, pt = IsEntityDead(p), Patients[p] or {}
    return {
        { action = 'vitals', label = 'Check vitals', icon = 'pulse', desc = 'Pulse, breathing and bleeding.' },
        { action = 'cpr', label = 'CPR', icon = 'cpr', off = not dead and 'They have a pulse' or nil,
          desc = 'Chest compressions. It sometimes brings back someone who has only just gone.' },
        { action = 'pressure', label = 'Apply pressure', icon = 'bandage', off = dead and 'No pulse' or pt.stable and 'Bleeding controlled' or nil,
          desc = 'Hold the wound so they stop bleeding out until paramedics arrive.' },
        { action = 'narcan', label = 'Give Narcan', icon = 'medic', off = dead and 'No pulse' or nil,
          desc = 'Reverses an opioid overdose for a while. It does nothing for anything else.' },
        BackupActive('ambulance') and { action = 'cancel_ambulance', label = 'Cancel ambulance', icon = 'medic', desc = 'Call it off.' }
            or { action = 'ambulance', label = 'Call ambulance', icon = 'medic', desc = 'Paramedics treat them and take them to hospital.' },
        BackupActive('coroner') and { action = 'cancel_coroner', label = 'Cancel coroner', icon = 'file', desc = 'Call it off.' }
            or { action = 'coroner', label = 'Call coroner', icon = 'file', off = not dead and 'Still alive' or nil,
                 desc = 'The coroner takes the body away.' },
    }
end

local function close()
    if not open then return end
    open, target = false, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'radial', open = false })
    UnfocusPed()
    NoPause()
end

-- Lying where they fell, held there (not a ragdoll's drift), until paramedics take them.
local function lie(p)
    if load_dict(ANIM.lying[1]) then TaskPlayAnim(p, ANIM.lying[1], ANIM.lying[2], 8.0, -8.0, -1, 1, 0.0, false, false, false) end
end

-- Lying where they fell, held there: a writhe or a ragdoll is something they can get up out of.
local function hold_down(p)
    if IsEntityDead(p) or (Patients[p] and Patients[p].down) or not control(p) then return end
    SetBlockingOfNonTemporaryEvents(p, true)
    FreezeEntityPosition(p, true)
    lie(p)
    Patients[p] = Patients[p] or {}
    Patients[p].down = true
end
HoldDown = hold_down -- (client/callouts.lua: a callout's casualty, on the game that owns them)

function OpenMedical(p)
    if open or busy then return end
    CreateThread(function() hold_down(p) end) -- (seen to now: they stay down until paramedics take them)
    open, target = true, p
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'radial', open = true, kind = 'casualty', key = KeyName('+c3r_interact', 'E'),
                     title = IsEntityDead(p) and 'Unresponsive' or 'Injured', items = items(p) })
    FocusPed(p)
end

-- ─── first aid ────────────────────────────────────────────────────────────────

-- Kneel at their chest, on the officer's side, facing it.
local function kneel_at(p)
    local me = PlayerPedId()
    local chest, mine = GetPedBoneCoords(p, SPINE, 0.0, 0.0, 0.0), GetEntityCoords(me)
    local away = vector3(mine.x - chest.x, mine.y - chest.y, 0.0)
    local spot = chest + away / math.max(#away, 0.01) * 0.75
    TaskGoStraightToCoord(me, spot.x, spot.y, spot.z, 1.0, 3000, 0.0, 0.1)
    local deadline = GetGameTimer() + 3000
    while #(GetEntityCoords(me).xy - spot.xy) > 0.35 and GetGameTimer() < deadline do Wait(100) end
    TaskTurnPedToFaceCoord(me, chest.x, chest.y, chest.z, 800)
    Wait(800)
end

-- The officer plays it for ms (or until they walk off the job: the body's gone).
local function act(p, anim, ms)
    local me = PlayerPedId()
    kneel_at(p)
    if load_dict(anim[1]) then TaskPlayAnim(me, anim[1], anim[2], 4.0, -4.0, ms, 1, 0.0, false, false, false) end
    local deadline = GetGameTimer() + ms
    while GetGameTimer() < deadline and DoesEntityExist(p) do Wait(200) end
    ClearPedTasks(me)
end

-- Back from the dead. Placed on the ground under their chest first (a dead ragdoll's own position can be off the
-- ground, and RESURRECT_PED's docs: place it first or it can drop through), then again once alive; cured
-- (REVIVE_INJURED_PED: "the ped must not be dead"), kept by this game (no migrating: another game's copy still
-- has them dead). -> true when they're really alive
local function revive(p)
    local chest, h = GetPedBoneCoords(p, SPINE, 0.0, 0.0, 0.0), GetEntityHeading(p)
    local ok, gz = GetGroundZFor_3dCoord(chest.x, chest.y, chest.z + 1.0, false)
    local z = ok and gz or chest.z
    SetEntityAsMissionEntity(p, true, true) -- (not cleaned up as a body)
    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(p), false)
    SetEntityCoords(p, chest.x, chest.y, z, false, false, false, false)
    ResurrectPed(p)
    ClearPedTasksImmediately(p)
    ReviveInjuredPed(p)
    SetEntityCoords(p, chest.x, chest.y, z, false, false, false, false) -- (stood on the ground at z)
    SetEntityHeading(p, h)
    SetEntityHealth(p, 150)
    if IsEntityDead(p) then return false end
    SetBlockingOfNonTemporaryEvents(p, true)
    FreezeEntityPosition(p, true)
    lie(p)
    Patients[p] = { stable = 150, revived = true, down = true }
    return true
end

RevivePed = revive -- (client/backup.lua: paramedics bring people back too)

local DO = {}

function DO.vitals(p)
    act(p, ANIM.vitals, 5000)
    local gone = dead_for(p)
    if gone then
        local fresh = gone < M.cpr_window * 1000
        return Prompt('medical', 'alert', 'No pulse',
            fresh and 'Not breathing. Start CPR, and get paramedics on the way.' or 'Not breathing, and cold to the touch: they have been gone a while.', 9000)
    end
    local pt = Patients[p]
    local says = NetworkGetEntityIsNetworked(p) and Entity(p).state.c3r_vitals -- (a callout's: not everyone's bleeding)
    Prompt('medical', 'info', 'Weak pulse',
        says or pt and pt.stable and 'Breathing. The bleeding is under control.' or 'Breathing, but bleeding heavily. Apply pressure.', 9000)
end

function DO.cpr(p)
    local gone = dead_for(p)
    if not gone then return false end
    act(p, ANIM.cpr, M.cpr_seconds * 1000)
    if not DoesEntityExist(p) or not IsEntityDead(p) then return end
    if gone < M.cpr_window * 1000 and math.random() < M.cpr_chance and control(p) and revive(p) then
        TriggerServerEvent('c3r:backup', 'revived', 'ambulance')
        return Prompt('medical', 'ok', 'Pulse is back', "They're breathing. Get an ambulance on the way.", 9000)
    end
    Prompt('medical', 'alert', 'No response', 'Still no pulse.', 6000)
end

function DO.pressure(p)
    if IsEntityDead(p) then return false end
    act(p, ANIM.pressure, 8000)
    if not DoesEntityExist(p) or IsEntityDead(p) then return end
    Patients[p] = Patients[p] or {}
    Patients[p].stable = math.max(GetEntityHealth(p), 1)
    TriggerServerEvent('c3r:backup', 'stabilised', 'ambulance')
    Prompt('medical', 'ok', 'Bleeding controlled', 'They will hold on until paramedics arrive.', 7000)
end

function DO.narcan(p)
    if IsEntityDead(p) then return false end
    act(p, ANIM.vitals, 4000)
    if not DoesEntityExist(p) or IsEntityDead(p) then return false end
    -- (an overdose on a call: the call says what it did)
    if not (NetworkGetEntityIsNetworked(p) and Entity(p).state.c3r_vitals) then Prompt('medical', 'info', 'Narcan given', 'No change.', 6000) end
end

function DO.ambulance() CallBackup('ambulance') end
function DO.coroner() CallBackup('coroner') end
function DO.cancel_ambulance() CallBackup('cancel:ambulance') end
function DO.cancel_coroner() CallBackup('cancel:coroner') end

local CALL_AID = { vitals = true, pressure = true, cpr = true, narcan = true }
RegisterNUICallback('medical', function(d, cb)
    cb({})
    local p = target
    close()
    local fn = type(d.action) == 'string' and DO[d.action]
    if not fn or not p or not DoesEntityExist(p) then return end
    busy = true
    CreateThread(function()
        local ran = fn(p) ~= false
        busy = false
        -- a callout's casualty: the call hears they were seen to (not CPR on someone alive: nothing was done)
        if ran and CALL_AID[d.action] and DoesEntityExist(p) and IsCasualty(p) then
            TriggerServerEvent('c3r:callout:aid', PedToNet(p), d.action)
        end
    end)
end)

-- Walked off, or they're gone: the wheel goes. Stabilised patients don't bleed out (their health is held), and the
-- ones that died anyway, were taken or are gone are forgotten.
CreateThread(function()
    while true do
        local p = target
        if open and (not p or not DoesEntityExist(p) or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(p)) > REACH + 1.5) then
            close()
        end
        for ped, pt in pairs(Patients) do
            if not DoesEntityExist(ped) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false)
                or (NetworkGetEntityIsNetworked(ped) and Entity(ped).state.c3r_down == false) then -- (a casualty paramedics saw to)
                if DoesEntityExist(ped) then FreezeEntityPosition(ped, false) end
                Patients[ped] = nil
            elseif NetworkHasControlOfEntity(ped) then
                if pt.stable and GetEntityHealth(ped) < pt.stable then SetEntityHealth(ped, pt.stable) end
                if pt.down and not IsEntityPlayingAnim(ped, ANIM.lying[1], ANIM.lying[2], 3) then lie(ped) end
            end
        end
        watch_lives()
        Wait(open and 250 or 1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then close() end
end)
