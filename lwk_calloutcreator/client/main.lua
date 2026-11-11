--[[
    lwk_calloutcreator client: opens the editor (NUI), passes its requests to the server, and does what only the game can:
    trying a ped, prop, car, weapon, scenario or animation out in front of you (and saying if the name is wrong), walking
    out a location point by point, and taking you to one.
]]

local open, waiting, n = false, {}, 0

local function nui(msg) SendNUIMessage(msg) end

local function show(on)
    open = on
    SetNuiFocus(on, on)
    nui({ type = on and 'open' or 'close' })
end

RegisterCommand(Config.Command, function() TriggerServerEvent('lwk_calloutcreator:may') end, false)
RegisterKeyMapping(Config.Command, 'Open the callout creator (lwk_calloutcreator)', 'keyboard', Config.Key or '')

RegisterNetEvent('lwk_calloutcreator:may', function(ok)
    if ok then show(true)
    else TriggerEvent('chat:addMessage', { args = { 'Callout Creator', 'You need the ' .. Config.Ace .. ' ace to use this.' } }) end
end)

RegisterNUICallback('close', function(_, cb)
    show(false)
    cb({})
end)

-- the editor's requests, to the server and back
RegisterNUICallback('req', function(d, cb)
    n = n + 1
    local id = n
    waiting[id] = cb
    TriggerServerEvent('lwk_calloutcreator:req', id, d.action, d.req)
    SetTimeout(15000, function()
        if waiting[id] then waiting[id]({ ok = false, data = 'No answer from the server.' }) waiting[id] = nil end
    end)
end)

RegisterNetEvent('lwk_calloutcreator:res', function(id, ok, data)
    local cb = waiting[id]
    waiting[id] = nil
    if cb then cb({ ok = ok, data = data }) end
end)

-- ─── trying a name out ──────────────────────────────────────────────────────────────────────────────────────

local shown = {} -- what's out in front of the player now

local function clear()
    for _, e in ipairs(shown) do if DoesEntityExist(e) then DeleteEntity(e) end end
    shown = {}
end

local function want(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local deadline = GetGameTimer() + 4000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(hash)
end

local function ahead(m)
    local me = PlayerPedId()
    local at = GetOffsetFromEntityInWorldCoords(me, 0.0, m, 0.0)
    return at, GetEntityHeading(me) + 180.0
end

local function a_ped(model)
    local hash = GetHashKey(model ~= '' and model or 'a_m_y_hipster_01')
    if not (IsModelAPed(hash) and want(hash)) then return nil end
    local at, h = ahead(2.5)
    local e = CreatePed(4, hash, at.x, at.y, at.z - 1.0, h, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetBlockingOfNonTemporaryEvents(e, true)
    SetEntityInvincible(e, true)
    FreezeEntityPosition(e, true)
    shown[#shown + 1] = e
    return e
end

-- -> ok, what it says
local function preview(d)
    clear()
    local kind, name = d.kind, tostring(d.name or '')
    if kind == 'ped' then
        return a_ped(name) ~= nil
    elseif kind == 'prop' then
        local hash = GetHashKey(name)
        if IsModelAPed(hash) or IsModelAVehicle(hash) or not want(hash) then return false end
        local at = ahead(2.0)
        local e = CreateObject(hash, at.x, at.y, at.z, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        PlaceObjectOnGroundProperly(e)
        FreezeEntityPosition(e, true)
        shown[#shown + 1] = e
        return true
    elseif kind == 'vehicle' then
        local hash = GetHashKey(name)
        if not (IsModelAVehicle(hash) and want(hash)) then return false end
        local at, h = ahead(5.0)
        local e = CreateVehicle(hash, at.x, at.y, at.z, h - 90.0, false, false)
        SetModelAsNoLongerNeeded(hash)
        SetVehicleOnGroundProperly(e)
        if tonumber(d.paint) then SetVehicleColours(e, tonumber(d.paint), tonumber(d.paint)) end
        FreezeEntityPosition(e, true)
        shown[#shown + 1] = e
        return true
    elseif kind == 'weapon' then
        local hash = GetHashKey(name)
        if not IsWeaponValid(hash) then return false end
        local e = a_ped(d.model or '')
        if not e then return false end
        FreezeEntityPosition(e, false)
        GiveWeaponToPed(e, hash, 1, false, true)
        SetCurrentPedWeapon(e, hash, true)
        return true
    elseif kind == 'scenario' then
        local e = a_ped(d.model or '')
        if not e then return false end
        FreezeEntityPosition(e, false)
        TaskStartScenarioInPlace(e, name, 0, true)
        local deadline = GetGameTimer() + 1500 -- (a wrong name does nothing at all: no error, they just stand)
        while GetGameTimer() < deadline do
            if IsPedUsingScenario(e, name) then return true end
            Wait(100)
        end
        return IsPedUsingScenario(e, name)
    elseif kind == 'anim' then
        local dict, anim = tostring(d.dict or ''), tostring(d.anim or '')
        if not DoesAnimDictExist(dict) then return false, 'no such animation dictionary' end
        RequestAnimDict(dict)
        local deadline = GetGameTimer() + 4000
        while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
        if not HasAnimDictLoaded(dict) then return false end
        local e = a_ped(d.model or '')
        if not e then return false end
        TaskPlayAnim(e, dict, anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
        Wait(300)
        local playing = IsEntityPlayingAnim(e, dict, anim, 3)
        RemoveAnimDict(dict)
        return playing, playing and '' or 'the dictionary is there, but not that animation in it'
    end
    return false
end

-- The editor steps aside for a few seconds so it can be seen, then comes back.
RegisterNUICallback('preview', function(d, cb)
    CreateThread(function()
        local ok, why = preview(d)
        cb({ ok = ok == true, why = why })
        if ok then
            SetNuiFocus(false, false)
            nui({ type = 'peek', seconds = 6 })
            Wait(6000)
            clear()
            if open then SetNuiFocus(true, true) nui({ type = 'unpeek' }) end
        end
    end)
end)

-- ─── a location, walked out point by point ──────────────────────────────────────────────────────────────────

local function street_at(at)
    local s = GetStreetNameAtCoord(at.x, at.y, at.z)
    local name = s and s ~= 0 and GetStreetNameFromHashKey(s) or ''
    if name == '' then name = GetLabelText(GetNameOfZone(at.x, at.y, at.z)) end
    return name
end

local function ghost(car, p)
    local hash = GetHashKey(car and 'asea' or 'a_m_y_hipster_01')
    if not want(hash) then return nil end
    local e = car and CreateVehicle(hash, p.x, p.y, p.z, p.h, false, false) or CreatePed(4, hash, p.x, p.y, p.z - 1.0, p.h, false, false)
    SetModelAsNoLongerNeeded(hash)
    if car then SetVehicleOnGroundProperly(e) else SetBlockingOfNonTemporaryEvents(e, true) end
    SetEntityAlpha(e, 140, false)
    SetEntityCollision(e, false, false)
    SetEntityInvincible(e, true)
    FreezeEntityPosition(e, true)
    return e
end

-- points: { { name, text, car, optional } } -> { street, points = { [name] = { x, y, z, h } }, streets } | nil (cancelled)
local placing = false
RegisterNUICallback('place', function(d, cb)
    if placing then return cb({ ok = false }) end
    placing = true
    SetNuiFocus(false, false)
    local pts, got, ghosts, i = d.points or {}, {}, {}, 1
    local function say()
        local p = pts[i]
        nui({ type = 'placing', i = i, count = #pts, name = p.name, text = p.text, car = p.car == true, optional = p.optional == true })
    end
    say()
    CreateThread(function()
        local result
        while i <= #pts do
            for _, c in ipairs({ 20, 38, 73, 177 }) do DisableControlAction(0, c, true) end -- (Z, E, X, Backspace are the placer's)
            local me, p = PlayerPedId(), pts[i]
            if IsDisabledControlJustPressed(0, 38) then
                local veh = GetVehiclePedIsIn(me, false)
                if p.car and veh == 0 then nui({ type = 'placing_warn', text = 'Sit in a car parked where it should be, then E.' })
                elseif not p.car and veh ~= 0 then nui({ type = 'placing_warn', text = 'Get out and stand where they should stand, then E.' })
                else
                    local e = p.car and veh or me
                    local c, h = GetEntityCoords(e), GetEntityHeading(e)
                    got[p.name] = { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0, h = h + 0.0 }
                    ghosts[p.name] = ghost(p.car, got[p.name])
                    i = i + 1
                    if i <= #pts then say() end
                end
            elseif IsDisabledControlJustPressed(0, 20) then
                if p.optional then i = i + 1 if i <= #pts then say() end
                else nui({ type = 'placing_warn', text = "This one can't be skipped." }) end
            elseif IsDisabledControlJustPressed(0, 177) and i > 1 then
                i = i - 1
                local name = pts[i].name
                got[name] = nil
                if ghosts[name] and DoesEntityExist(ghosts[name]) then DeleteEntity(ghosts[name]) end
                ghosts[name] = nil
                say()
            elseif IsDisabledControlJustPressed(0, 73) then
                break
            end
            Wait(0)
        end
        for _, e in pairs(ghosts) do if DoesEntityExist(e) then DeleteEntity(e) end end
        if i > #pts and pts[1] and got[pts[1].name] then
            local streets = {}
            for name, p in pairs(got) do streets[name] = street_at(vector3(p.x, p.y, p.z)) end
            local f = got[pts[1].name]
            result = { street = street_at(vector3(f.x, f.y, f.z)), streets = streets, points = got }
        end
        placing = false
        if open then SetNuiFocus(true, true) end
        nui({ type = 'placed' })
        cb({ ok = result ~= nil, location = result })
    end)
end)

-- Taken to a location's first point, to look at it (or place again from there).
RegisterNUICallback('goto', function(d, cb)
    local p = d.at
    if type(p) == 'table' and tonumber(p.x) and tonumber(p.y) and tonumber(p.z) then
        local me = PlayerPedId()
        SetEntityCoords(me, p.x + 0.0, p.y + 0.0, p.z + 0.0, false, false, false, false)
        if tonumber(p.h) then SetEntityHeading(me, p.h + 0.0) end
    end
    cb({})
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clear()
    if open then SetNuiFocus(false, false) end
end)
