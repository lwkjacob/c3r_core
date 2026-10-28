-- The phone on the player's side: raising and lowering it, who gets the mouse and keyboard,
-- and the pipe between the UI and the server.
--
-- UI -> here:  NUI callbacks 'ready', 'rpc', 'close', 'typing', 'customApp'
-- here -> UI:  SendNUIMessage({ action = ... })   (see web/src/nui.ts)

Local = {}   -- rpc name -> function(data): handled here instead of on the server (needs game natives)
After = {}   -- rpc name -> function(result, data): touches up a server answer before the UI sees it

local isOpen, uiReady, loaded = false, false, false
local typing, cursorOff = false, false
local number, settings, disabled = nil, {}, false   -- the phone in hand, its saved settings, and whether another script has switched it off

function PhoneNumber() return loaded and number or nil end
function PhoneSettings() return loaded and settings or nil end
function IsPhoneDisabled() return disabled end

local function nui(msg) SendNUIMessage(msg) end

function IsPhoneOpen() return isOpen end

--- True while the phone is up but the mouse has been handed back to the game (Config.cursorKey).
function GameHasMouse() return isOpen and cursorOff end

Keys = {}   -- the phone's keybinds, by purpose

local NAMES = {
    LMENU = 'Left Alt', RMENU = 'Right Alt', LSHIFT = 'Left Shift', LCONTROL = 'Left Ctrl', RETURN = 'Enter',
    SPACE = 'Space', TAB = 'Tab', UP = '↑', DOWN = '↓', LEFT = '←', RIGHT = '→',
}

--- What to print for a keybind in an on-screen hint.
-- ponytail: a rebound letter or F-key is followed; keys the game reports as an icon number (Alt, Enter,
-- arrows) show the default key's name even after rebinding. Map those numbers if it ever matters.
function KeyLabel(bind)
    local key = bind.currentKey or ''
    if key == '' or tonumber(key) then key = bind.defaultKey end
    return NAMES[key] or key
end

--- The key that closed the phone is still down when the game gets the keyboard back, and Escape
--- would open the pause menu. Keep pause blocked until that key has been let go.
local function swallowPause()
    CreateThread(function()
        local atLeast = GetGameTimer() + 250
        while GetGameTimer() < atLeast or IsDisabledControlPressed(0, 200) do
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            Wait(0)
        end
    end)
end

--- Hand out mouse and keyboard. With Config.walk the game keeps the keyboard so the player can
--- move; while a text field has focus it does not, or typing would walk the character about.
local function focus()
    SetNuiFocus(isOpen, isOpen and not cursorOff)
    SetNuiFocusKeepInput(isOpen and (Config.walk or cursorOff) and not typing)
end

--- Fetch the phone from the server and hand it to the UI. `slot` is the inventory slot just used.
local function load(slot)
    local data = lib.callback.await('lwk_phone:load', false, slot)
    if not data or data.error then
        loaded = false
        return false, data and data.error
    end
    loaded = true
    number, settings = data.number, Util.decode(data.kv and data.kv.settings)
    nui({ action = 'init', data = data })
    CustomApps.resend()
    return true
end

-- The phone's clock shows the game's time of day: the UI is told whenever the minute changes.
local minute

local function tellTime()
    if not Config.gameTime then return end
    local h, m = GetClockHours(), GetClockMinutes()
    if h * 60 + m == minute then return end
    minute = h * 60 + m
    nui({ action = 'time', h = h, m = m })
end

function ClosePhone()
    if not isOpen then return end
    isOpen, typing, cursorOff = false, false, false
    nui({ action = 'close' })
    focus()
    swallowPause()
    Camera.stop()
    Prop.lower()
end

--- Another script switches the phone off (and back on): it closes and will not open.
function DisablePhone(off)
    disabled = off == true
    if disabled then ClosePhone() end
end

function OpenPhone(slot)
    if isOpen or disabled or not uiReady or not Bridge.canOpen() then return end
    if not loaded or slot then
        local ok, why = load(slot)
        if not ok then
            if why == 'no_phone' then lib.notify({ description = L('err_no_phone'), type = 'error' }) end
            return
        end
    end
    isOpen = true
    minute = nil
    tellTime()
    nui({ action = 'open' })
    focus()
    Prop.raise()
end

local function unload()
    ClosePhone()
    loaded = false
    nui({ action = 'unload' })
end

-- Keys ---------------------------------------------------------------------------------------

Keys.open = lib.addKeybind({
    name = 'lwk_phone',
    description = L('key_open'),
    defaultKey = Config.keybind,
    onPressed = function()
        if isOpen then ClosePhone() else OpenPhone() end
    end,
})

-- Gives the mouse back to the game while the phone stays up: look around, aim the camera.
Keys.cursor = lib.addKeybind({
    name = 'lwk_phone_cursor',
    description = L('key_cursor'),
    defaultKey = Config.cursorKey,
    onPressed = function()
        if not isOpen then return end
        cursorOff = not cursorOff
        focus()
    end,
})

RegisterCommand(Config.command, function()
    if isOpen then ClosePhone() else OpenPhone() end
end, false)

-- While the game still has the keyboard, stop it acting on clicks and keys meant for the phone.
CreateThread(function()
    while true do
        if isOpen and not typing then
            if not cursorOff then
                DisableControlAction(0, 1, true)    -- look left/right
                DisableControlAction(0, 2, true)    -- look up/down
            end
            DisableControlAction(0, 24, true)       -- attack
            DisableControlAction(0, 25, true)       -- aim
            DisableControlAction(0, 37, true)       -- weapon wheel
            DisableControlAction(0, 140, true)      -- melee
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 199, true)      -- pause (P)
            DisableControlAction(0, 200, true)      -- pause (ESC)
            DisableControlAction(0, 257, true)      -- attack 2
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- Put the phone away when the player can no longer hold it (death, cuffs), and keep its clock right.
CreateThread(function()
    while true do
        Wait(500)
        if isOpen and not Bridge.canOpen() then ClosePhone() end
        if isOpen then tellTime() end
    end
end)

-- UI -> Lua -----------------------------------------------------------------------------------

RegisterNUICallback('ready', function(_, cb)
    uiReady = true
    cb({})
    -- The page said this before, so it has been reloaded and lost everything: hand the phone over again.
    if loaded then CreateThread(function() load() end) end
end)

RegisterNUICallback('rpc', function(req, cb)
    local name, data = req.name, type(req.data) == 'table' and req.data or {}
    if Local[name] then return cb(Local[name](data) or { ok = true }) end
    if name == 'save' and data.k == 'settings' then settings = Util.decode(data.v) end
    local res = lib.callback.await('lwk_phone:rpc', false, name, data) or { ok = false }
    if After[name] and res.ok then res = After[name](res, data) or res end
    cb(res)
end)

RegisterNUICallback('close', function(_, cb)
    ClosePhone()
    cb({})
end)

RegisterNUICallback('typing', function(data, cb)
    typing = data.on == true
    focus()
    cb({})
end)

RegisterNUICallback('customApp', function(data, cb)
    CustomApps.event(data)
    cb({})
end)

-- Server -> UI ---------------------------------------------------------------------------------

RegisterNetEvent('lwk_phone:nui', function(msg)
    if msg.action == 'unload' then return unload() end
    nui(msg)
end)

-- The phone item was used (qb-inventory; ox_inventory calls the usePhone export instead).
RegisterNetEvent('lwk_phone:use', function(slot)
    if isOpen then ClosePhone() else OpenPhone(slot) end
end)

-- Character lifecycle ----------------------------------------------------------------------------

Bridge.watch(function()
    if uiReady and not loaded then load() end
end, function()
    unload()
    TriggerServerEvent('lwk_phone:unload')
end)

-- Covers standalone servers and resource restarts, where no "loaded" event will arrive.
CreateThread(function()
    while not uiReady or not Bridge.loaded() do Wait(500) end
    if not loaded then load() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false) end
    Camera.stop()
    Prop.destroy()
end)
