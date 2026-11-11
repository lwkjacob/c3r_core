--[[
    lwk_k9 — client: the dog's options. Breed, name, and every part of the model that has more than one style or
    colour, shown on the dog itself as you change it. Saved per player as soon as it's changed. BY LWK DEVELOPMENT
]]

local open = false

local function parts()
    local list = {}
    if not Dog then return list end
    for c = 0, 11 do
        local n, d = GetNumberOfPedDrawableVariations(Dog, c), GetPedDrawableVariation(Dog, c)
        local tn = GetNumberOfPedTextureVariations(Dog, c, d)
        if n > 1 or tn > 1 then list[#list + 1] = { c = c, d = d, n = n, t = GetPedTextureVariation(Dog, c), tn = tn } end
    end
    return list
end

local function breeds()
    local list = {}
    for _, b in ipairs(Config.Breeds) do
        if IsModelInCdimage(GetHashKey(b.model)) then list[#list + 1] = { model = b.model, label = b.label, police = b.police == true } end
    end
    return list
end

local function send()
    SendNUIMessage({ type = 'k9', open = true, breeds = breeds(), model = Setup.model, name = Setup.name, parts = parts() })
end

function OpenOptions()
    if open or IsNuiFocused() then return end
    if not Dog and not Spawn() then return end
    open = true
    SetNuiFocus(true, true)
    send()
end

local function close()
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'k9', open = false })
end

RegisterNUICallback('breed', function(d, cb)
    cb({})
    if type(d.model) ~= 'string' or BreedOf(d.model).model ~= d.model or d.model == Setup.model then return end
    CreateThread(function()
        Setup.model, Setup.comps = d.model, {}
        SaveSetup()
        Dismiss()
        Spawn()
        send()
    end)
end)

RegisterNUICallback('part', function(d, cb)
    cb({})
    local c, dr, t = math.tointeger(d.c), math.tointeger(d.d), math.tointeger(d.t)
    if not Dog or not c or not dr or not t or c < 0 or c > 11 then return end
    if dr < 0 or dr >= GetNumberOfPedDrawableVariations(Dog, c) then return end
    if t < 0 or t >= math.max(GetNumberOfPedTextureVariations(Dog, c, dr), 1) then t = 0 end
    SetPedComponentVariation(Dog, c, dr, t, 0)
    Setup.comps[tostring(c)] = { dr, t }
    SaveSetup()
    send()
end)

RegisterNUICallback('name', function(d, cb)
    cb({})
    if type(d.name) ~= 'string' then return end
    Setup.name = d.name:gsub('[%c<>]', ''):sub(1, 20)
    SaveSetup()
end)

RegisterNUICallback('close', function(_, cb) cb({}) close() end)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() and open then SetNuiFocus(false, false) end end)
