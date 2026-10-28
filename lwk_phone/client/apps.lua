-- The bits of apps that need the game itself: waypoints, the player's position, the weather,
-- vehicle names and spawning, the flashlight, and the phone-to-ear animation.

local function ok(t)
    t = t or {}
    t.ok = true
    return t
end

-- Maps -------------------------------------------------------------------------------------------

Local['waypoint'] = function(data)
    local x, y = tonumber(data.x), tonumber(data.y)
    if data.clear then SetWaypointOff() end
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
    return ok()
end

Local['position'] = function()
    local pos = GetEntityCoords(PlayerPedId())
    local street = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
    return ok({ x = pos.x, y = pos.y, street = GetStreetNameFromHashKey(street) })
end

-- Weather ----------------------------------------------------------------------------------------
-- The game has a current weather and a clock, no forecast. The hours and days ahead are the current
-- conditions with a plausible temperature curve laid over them.

local WEATHER = {
    [joaat('EXTRASUNNY')] = { 'sun', 'weather_sunny', 28 },      [joaat('CLEAR')] = { 'sun', 'weather_clear', 24 },
    [joaat('CLOUDS')] = { 'cloudsun', 'weather_cloudy', 21 },    [joaat('OVERCAST')] = { 'cloud', 'weather_overcast', 18 },
    [joaat('CLEARING')] = { 'cloudsun', 'weather_clearing', 17 }, [joaat('RAIN')] = { 'rain', 'weather_rain', 15 },
    [joaat('THUNDER')] = { 'rain', 'weather_thunder', 14 },      [joaat('SMOG')] = { 'cloud', 'weather_smog', 22 },
    [joaat('FOGGY')] = { 'cloud', 'weather_fog', 16 },           [joaat('XMAS')] = { 'cloud', 'weather_snow', -2 },
    [joaat('SNOWLIGHT')] = { 'cloud', 'weather_snow', -1 },      [joaat('BLIZZARD')] = { 'cloud', 'weather_snow', -6 },
}
local DAYS = { 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' }

--- Degrees above or below the day's base temperature at a given hour: coldest at 4 am, warmest at 4 pm.
local function swing(hour)
    return math.floor(math.cos((hour - 16) / 24 * 2 * math.pi) * 5 + 0.5)
end

local function weather()
    local w = WEATHER[GetPrevWeatherTypeHashName()] or WEATHER[joaat('CLEAR')]
    local icon, base, hour = w[1], w[3], GetClockHours()
    local pos = GetEntityCoords(PlayerPedId())

    local hourly = {}
    for i = 0, 9 do
        local h = (hour + i) % 24
        local night = h < 6 or h >= 21
        hourly[i + 1] = { i == 0 and L('weather_now') or (('%d%s'):format(h % 12 == 0 and 12 or h % 12, h < 12 and 'AM' or 'PM')),
            (night and icon == 'sun') and 'moon' or icon, base + swing(h) }
    end
    local daily, today = {}, GetClockDayOfWeek()
    for i = 0, 6 do
        daily[i + 1] = { i == 0 and L('weather_today') or DAYS[(today + i) % 7 + 1], icon, base - 5 - i % 2, base + 5 + i % 3 }
    end
    return { weather = {
        city = GetLabelText(GetNameOfZone(pos.x, pos.y, pos.z)), temp = base + swing(hour), cond = L(w[2]), hi = base + 5, lo = base - 5,
        hourly = hourly, daily = daily, wind = math.floor(GetWindSpeed() * 3.6 + 0.5), humidity = icon == 'rain' and 88 or 48,
        uv = icon == 'sun' and 6 or 2, feels = base + swing(hour), visibility = (icon == 'sun' or icon == 'cloudsun') and 16 or 6, sunset = '8:00 PM',
    } }
end

-- Garage -----------------------------------------------------------------------------------------

local function vehicleName(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not hash or not IsModelInCdimage(hash) then return tostring(model) end
    local display = GetDisplayNameFromVehicleModel(hash)
    local label = GetLabelText(display)
    return label ~= 'NULL' and label or display
end

local function nameVehicles(list)
    for _, v in ipairs(list or {}) do v.name = vehicleName(v.model) end
end

After['appData'] = function(res, data)
    if data.app == 'garage' and res.data then nameVehicles(res.data.vehicles) end
    if data.app == 'weather' then res.data = weather() end
    -- A housing script that only lists a player's houses on the client fills the Home app from here.
    if data.app == 'home' and res.data then res.data.houses = Bridge.home.list() or res.data.houses end
end

-- Home ---------------------------------------------------------------------------------------------

--- Some housing scripts only take a lock or a key change from the player's own game. The server
--- answers such a request with what to do; do it, give the script a moment, and read the list again.
local function housed(res)
    if not res.client then return end
    Bridge.home.run(res.client)
    res.client = nil
    Wait(700)
    local fresh = lib.callback.await('lwk_phone:rpc', false, 'appData', { app = 'home' })
    if fresh and fresh.ok and fresh.data then res.houses = Bridge.home.list() or fresh.data.houses end
end

After['home.lock'] = housed
After['home.key'] = housed

Local['home.way'] = function(data)
    Bridge.home.waypoint(data.id)
    return ok()
end

After['garage.valet'] = function(res)
    nameVehicles(res.vehicles)
    local spawn = res.spawn
    res.spawn = nil
    local model = type(spawn.model) == 'string' and joaat(spawn.model) or spawn.model

    -- Park it on the nearest road rather than on top of the player.
    local pos = GetEntityCoords(PlayerPedId())
    local found, node, heading = GetClosestVehicleNodeWithHeading(pos.x + 12.0, pos.y + 12.0, pos.z, 1, 3.0, 0)
    local at = found and node or pos
    if spawn.server then
        -- This framework spawns its own vehicles: tell it where, and it does the rest (tuning included).
        local done = lib.callback.await('lwk_phone:rpc', false, 'garage.spawn', { plate = spawn.plate, x = at.x, y = at.y, z = at.z, h = heading or 0.0 })
        if not done or not done.ok then
            lib.callback.await('lwk_phone:rpc', false, 'garage.failed', { plate = spawn.plate })
            return { ok = false, error = L('err_valet_failed') }
        end
        nameVehicles(done.vehicles)
        res.vehicles = done.vehicles
        Bridge.giveKeys(nil, spawn.plate)
        SetNewWaypoint(at.x, at.y)
        return res
    end
    local vehicle = 0
    if model and pcall(lib.requestModel, model, 5000) then
        vehicle = CreateVehicle(model, at.x, at.y, at.z, heading or 0.0, true, false)
    end
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        -- Nothing arrived (a model this game does not have, usually). The server has already charged for it
        -- and marked it as out: have that undone, and tell the player.
        lib.callback.await('lwk_phone:rpc', false, 'garage.failed', { plate = spawn.plate })
        return { ok = false, error = L('err_valet_failed') }
    end
    if spawn.props then pcall(lib.setVehicleProperties, vehicle, spawn.props) end
    SetVehicleNumberPlateText(vehicle, spawn.plate)
    SetModelAsNoLongerNeeded(model)
    Bridge.giveKeys(vehicle, spawn.plate)
    SetNewWaypoint(at.x, at.y)
    return res
end

After['garage.locate'] = function(res)
    SetNewWaypoint(res.x + 0.0, res.y + 0.0)
end

-- Flashlight ---------------------------------------------------------------------------------------

local torch = false

Local['flashlight'] = function(data)
    if data.on == torch then return ok() end
    torch = data.on == true
    if torch then
        CreateThread(function()
            while torch do
                local ped = PlayerPedId()
                local pos, dir = GetEntityCoords(ped), GetEntityForwardVector(ped)
                DrawSpotLight(pos.x, pos.y, pos.z + 0.4, dir.x, dir.y, dir.z - 0.1, 255, 255, 240, 22.0, 6.0, 0.0, 18.0, 12.0)
                Wait(0)
            end
        end)
    end
    return ok()
end

-- Calls: phone to the ear while talking -----------------------------------------------------------

-- The other end of the call pressed Mute: their voice stops reaching this player.
RegisterNetEvent('lwk_phone:callMute', function(id, muted)
    Bridge.callMute(id, muted == true)
end)

Local['callAnim'] = function(data)
    Prop.call(data.on == true)
    return ok()
end
