-- The physical phone: the prop in the player's hand and the animation holding it.
-- All of this is cosmetic. If a model or animation fails to load, the screen still works.

Prop = {}

local object
local token = 0   -- every raise/lower takes the next number; a sequence that is no longer current stops

local function dict()
    return IsPedInAnyVehicle(PlayerPedId(), false) and Config.anim.carDict or Config.anim.dict
end

local function play(name, flag)
    local d = dict()
    if pcall(lib.requestAnimDict, d, 2000) then
        TaskPlayAnim(PlayerPedId(), d, name, 3.0, -4.0, -1, flag, 0.0, false, false, false)
    end
end

function Prop.destroy()
    if object and DoesEntityExist(object) then DeleteEntity(object) end
    object = nil
end

local function attach()
    Prop.destroy()
    local model = joaat(Config.prop.model)
    if not pcall(lib.requestModel, model, 2000) then return end
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    object = CreateObject(model, pos.x, pos.y, pos.z, true, true, false)
    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, Config.prop.bone), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
end

function Prop.raise()
    token = token + 1
    SetPedCurrentWeaponVisible(PlayerPedId(), false, true, true, true)
    attach()
    play(Config.anim.open, 50)   -- 50: hold the last frame, upper body only, player keeps control
end

function Prop.lower()
    token = token + 1
    local mine = token
    play(Config.anim.close, 48)
    SetTimeout(500, function()
        if token ~= mine then return end   -- raised again in the meantime: that sequence owns the prop now
        StopAnimTask(PlayerPedId(), dict(), Config.anim.close, 1.0)
        Prop.destroy()
    end)
end

--- Phone to the ear during a call, back in front afterwards.
function Prop.call(on)
    if not object then return end
    play(on and Config.anim.call or Config.anim.idle, on and 49 or 50)
end

--- The camera app hides the prop so it is not in every photo.
function Prop.hide(on)
    if object and DoesEntityExist(object) then SetEntityVisible(object, not on, false) end
end
