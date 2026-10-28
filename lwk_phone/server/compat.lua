-- LB Phone compatibility (server). See client/compat.lua for how the 'lb-phone' name is answered.
-- The exports the two phones share by name are in server/exports.lua; this file adds more of LB's.

local APPS = { birdy = 'flock', twitter = 'flock', instapic = 'lumen', instagram = 'lumen', trendy = 'loop', tiktok = 'loop',
    darkchat = 'shade', mail = 'mail' }

Export('FormatNumber', function(number) return Util.number(number) or tostring(number or '') end)

--- The account a phone is signed in to. `app` is LB's name for it or this phone's.
Export('GetSocialMediaUsername', function(number, app)
    app = tostring(app or ''):lower()
    return Social.user(Util.number(number) or '', APPS[app] or app) or false
end)

Export('HasAirplaneMode', function(number) return Phone.flags(Util.number(number) or '').airplane == true end)

Export('GetSettings', function(number)
    local s = Phone.get(Util.number(number) or '', 'settings')
    return type(s) == 'table' and Util.appSettings(s) or nil
end)

--- notify: 'all' or 'online' (both mean every phone that is up right now). data: { app?, title, content }.
Export('NotifyEveryone', function(_, data)
    for src in pairs(Phone.online()) do Phone.notify(src, data.app or 'settings', data.title or '', data.content or '') end
end)

Export('EmergencyNotification', function(src, data)
    Phone.notify(src, 'settings', data.title or '', data.content or '')
end)

Export('SendCoords', function(from, to, coords)
    local sender = Util.number(from) or Util.text(from, 1, 16)
    local body = type(coords) == 'vector3' or type(coords) == 'vector2' or type(coords) == 'table'
    if not sender or not body then return end
    Messages.text(nil, sender, { to }, nil, { loc = L('shared_location'), x = coords.x + 0.0, y = coords.y + 0.0 })
end)

Export('EndCall', function(src)
    local number = Phone.number(src)
    if not number or not Calls.active(number) then return false end
    RPC['call.end'](src, number, {})
    return true
end)

--- data: { number, firstname?, lastname?, name? }. Added to the phone's saved contacts.
Export('AddContact', function(number, data)
    number = Util.number(number)
    local who = type(data) == 'table' and Util.number(data.number)
    if not number or not who then return end
    local name = Util.text(data.name, 1, 64) or Util.text((data.firstname or '') .. ' ' .. (data.lastname or ''), 1, 64) or who
    local contacts = Phone.get(number, 'contacts') or {}
    contacts[#contacts + 1] = { id = Phone.now(), name = name, number = who }
    Phone.set(number, 'contacts', contacts)
    Phone.patch(number, { contacts = contacts })
end)

lib.callback.register('lwk_phone:inCall', function(src)
    local number = Phone.number(src)
    return number ~= nil and Calls.active(number) ~= nil
end)

-- LB's own callbacks, carried by ox_lib's.
Export('RegisterCallback', function(event, handler)
    lib.callback.register('lb-phone:' .. event, function(src, ...) return handler(src, ...) end)
end)

--- Like RegisterCallback, but the handler also gets the player's phone number: handler(source, number, ...).
Export('BaseCallback', function(event, handler, default)
    lib.callback.register('lb-phone:' .. event, function(src, ...)
        local number = Phone.number(src)
        if not number then return default end
        return handler(src, number, ...)
    end)
end)

Export('AwaitClientCallback', function(event, src, ...) return lib.callback.await('lb-phone:' .. event, src, ...) end)
Export('TriggerClientCallback', function(event, src, cb, ...) lib.callback('lb-phone:' .. event, src, cb or function() end, ...) end)

-- No counterpart here: they answer nil and say so once in the console (see client/compat.lua).
Util.stubs({
    'GetConfig', 'GetCellTowers', 'AirShare', 'ContainsBlacklistedWord', 'AddCheck', 'RemoveCheck', 'ToggleVerified', 'IsVerified',
    'ChangePassword', 'PostBirdy', 'GetBirdyPost', 'PostInstaPic', 'DeleteBirdyAccount', 'DeleteInstaPicAccount', 'DeleteTrendyAccount',
    'FactoryReset', 'GetPin', 'ResetSecurity', 'CreateMailAccount', 'GetEmailAddress', 'DeleteMail', 'SentMoney', 'SendDarkChatMessage',
    'SendDarkChatLocation', 'CreateDarkChatChannel', 'DeleteDarkChatChannel', 'AddUserToDarkChatChannel', 'RemoveUserFromDarkChatChannel',
    'SaveBattery', 'SaveAllBatteries', 'IsPhoneDead', 'GetCall', 'ForwardCall', 'AddCrypto', 'RemoveCrypto', 'AddCustomCoin', 'GetCoin',
    'GetOwnedCoin',
})

-- Scripts hold on to the exports they fetched. When this resource restarts, say so under the name
-- they know, so they fetch them again (see client/compat.lua).
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerEvent('onServerResourceStop', 'lb-phone')
    TriggerEvent('onResourceStop', 'lb-phone')
end)

CreateThread(function()
    Wait(500)
    TriggerEvent('onServerResourceStart', 'lb-phone')
    TriggerEvent('onResourceStart', 'lb-phone')
end)
