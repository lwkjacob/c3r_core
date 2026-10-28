-- LB Phone compatibility (client).
--
-- Apps written for LB Phone call exports['lb-phone']:... and wait for a resource of that name.
-- Export() (shared/util.lua) answers every export under that name as well as under this resource's
-- own; that needs nothing else. The resource of that name is a four-line one the server owner adds
-- (README, "Apps written for LB Phone"). It is deliberately not done with `provide` in fxmanifest:
-- after this resource restarts, the game client starts a second, broken copy of a providing
-- resource whenever something that depends on the provided name starts.
--
-- The custom-app exports themselves are in client/exports.lua; this file adds the rest of LB's
-- client exports that apps tend to use. What a page inside an app can call is in
-- web/src/apps/Custom.tsx.

Export('FormatNumber', function(number) return Util.number(number) or tostring(number or '') end)
Export('GetEquippedPhoneNumber', PhoneNumber)
Export('HasPhoneItem', function() return PhoneNumber() ~= nil end)
Export('IsPhoneOnScreen', IsPhoneOpen)
Export('IsDisabled', IsPhoneDisabled)
Export('ToggleDisabled', DisablePhone)
Export('IsLive', function() return false end)

Export('GetSettings', function()
    local s = PhoneSettings()
    return s and Util.appSettings(s) or nil
end)
Export('GetAirplaneMode', function() return (PhoneSettings() or {}).airplane == true end)
Export('GetStreamerMode', function() return (PhoneSettings() or {}).streamer == true end)

Export('IsInCall', function() return lib.callback.await('lwk_phone:inCall', false) == true end)

-- Things the UI does: each is a message it already knows how to act on (web/src/nui.ts).
Export('ToggleHomeIndicator', function(show) SendNUIMessage({ action = 'patch', data = { hideHomeBar = show == false } }) end)
Export('ToggleLandscape', function(landscape) SendNUIMessage({ action = 'patch', data = { landscape = landscape == true } }) end)
Export('ToggleFlashlight', function(on) SendNUIMessage({ action = 'patch', data = { flashlight = on == true } }) end)
Export('OpenApp', function(app) SendNUIMessage({ action = 'openApp', app = tostring(app) }) end)
Export('CloseApp', function() SendNUIMessage({ action = 'closeApp' }) end)
Export('SaveToGallery', function(link) SendNUIMessage({ action = 'savePhoto', url = link }) end)

--- options: { number?, company?, videoCall?, hideNumber? }
Export('CreateCall', function(options)
    options = type(options) == 'table' and options or {}
    SendNUIMessage({ action = 'startCall', number = options.number and tostring(options.number), company = options.company, video = options.videoCall == true })
end)

--- data: { number, firstname?, lastname?, name? }
Export('AddContact', function(data)
    local number = type(data) == 'table' and Util.number(data.number)
    if not number then return false end
    local name = data.name or ((data.firstname or '') .. ' ' .. (data.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    SendNUIMessage({ action = 'addContact', number = number, name = name ~= '' and name or number })
    return true
end)

-- Pop-ups and menus opened from Lua. Functions cannot be sent to the UI, so the buttons go over
-- without their callbacks and the UI answers with which one was pressed.
local dialogs, lastDialog = {}, 0

local function dialog(action, data)
    if type(data) ~= 'table' or type(data.buttons) ~= 'table' then return end
    lastDialog = lastDialog + 1
    local plain = {}
    for i, b in ipairs(data.buttons) do plain[i] = { title = tostring(b.title or ''), color = b.color, bold = b.bold == true } end
    dialogs[lastDialog] = data
    local input = type(data.input) == 'table' and data.input or type(data.inputs) == 'table' and data.inputs[1] or nil
    SendNUIMessage({ action = action, id = lastDialog, data = {
        title = data.title, description = data.description, buttons = plain,
        attachment = type(data.attachment) == 'table' and { src = data.attachment.src } or nil,
        input = input and { placeholder = input.placeholder, value = input.value or input.defaultValue } or nil,
    } })
end

Export('SetPopUp', function(data) dialog('popUp', data) end)
Export('SetContextMenu', function(data) dialog('contextMenu', data) end)

RegisterNUICallback('dialog', function(res, cb)
    cb({})
    local data = dialogs[res.id]
    dialogs[res.id] = nil
    if not data then return end
    local input = type(data.input) == 'table' and data.input or type(data.inputs) == 'table' and data.inputs[1] or nil
    if input and input.onChange and res.value then input.onChange(res.value) end
    local button = data.buttons[(tonumber(res.button) or -1) + 1]
    if button and button.cb then button.cb(res.value) end
end)

-- LB's camera you can walk around with is this phone's camera mode.
Export('EnableWalkableCam', function(selfie) Camera.start(selfie == true) end)
Export('DisableWalkableCam', function() Camera.stop() end)
Export('IsWalkingCamEnabled', function() return (Camera.state()) end)
Export('IsCameraOpen', function() return (Camera.state()) end)
Export('IsSelfieCam', function() return select(2, Camera.state()) end)
Export('ToggleSelfieCam', function(selfie)
    if Camera.state() then Camera.start(selfie == true) end
end)

-- LB's own callbacks, carried by ox_lib's.
Export('RegisterClientCallback', function(event, handler) lib.callback.register('lb-phone:' .. event, handler) end)
Export('AwaitCallback', function(event, ...) return lib.callback.await('lb-phone:' .. event, false, ...) end)
Export('TriggerCallback', function(event, cb, ...) lib.callback('lb-phone:' .. event, false, cb or function() end, ...) end)

-- The rest of LB's client exports have no counterpart here. They exist, so an app that calls one
-- carries on instead of stopping with "no such export", and say so once in the console.
Util.stubs({
    'GetConfig', 'GetCellTowers', 'AddCheck', 'RemoveCheck', 'SetPhonePartiallyVisible', 'DeleteNotification', 'GetFlashlight',
    'SetServiceBars', 'ReloadPhone', 'SetPhoneVariation', 'SetAnimations', 'ResetAnimations', 'ToggleCameraFrozen', 'AddKeyBind',
    'ShowMusicTray', 'UpdateMusicTray', 'RemoveMusicTray', 'ShowLiveTray', 'UpdateLiveTray', 'RemoveLiveTray', 'PostBirdy',
    'UpdateContact', 'RemoveContact', 'SetAppHidden', 'SetAppInstalled', 'ShowComponent', 'SetCameraComponent', 'SetContactModal',
    'IsPhoneDead', 'GetBattery', 'SetBattery', 'ToggleCharging', 'IsCharging', 'SendCompanyMessage', 'SendCompanyCoords',
    'GetCompanyCallsStatus', 'ToggleCompanyCalls', 'GetCoinValue', 'GetCryptoWallet', 'GetOwnedCoin', 'CreateCustomNumber',
    'RemoveCustomNumber', 'CreateDynamicCustomNumber', 'RemoveDynamicCustomNumber', 'EndCustomCall',
})

-- When this resource restarts, apps have to notice: they hold on to the exports they fetched, and
-- they register again when they see the phone start. The name they watch is the one above, so say
-- it stopped and started under that name too.
AddEventHandler('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerEvent('onClientResourceStop', 'lb-phone')
    TriggerEvent('onResourceStop', 'lb-phone')
end)

CreateThread(function()
    Wait(500)
    TriggerEvent('onClientResourceStart', 'lb-phone')
    TriggerEvent('onResourceStart', 'lb-phone')
end)
