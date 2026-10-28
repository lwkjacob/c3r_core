-- Client exports for other resources, including community apps. The three custom-app exports
-- take the same arguments as LB Phone's, and Export() also answers them as exports['lb-phone'],
-- so an app written for that phone registers here unchanged. More of LB's exports: client/compat.lua.

CustomApps = {}

local apps = {}   -- identifier -> { def = <what the UI needs>, callbacks = { use = fn, ... }, resource = name }

local CALLBACKS = { open = 'onOpen', close = 'onClose', use = 'onUse', install = 'onInstall', delete = 'onDelete' }

--- AddCustomApp({ identifier, name, description?, developer?, ui?, icon?, defaultApp?, price?, size?, images?, landscape?, keepOpen?,
---               onOpen?, onClose?, onUse?, onInstall?, onDelete? }) -> success, error
Export('AddCustomApp', function(app)
    if type(app) ~= 'table' or type(app.identifier) ~= 'string' or type(app.name) ~= 'string' then
        return false, 'identifier and name are required'
    end
    local callbacks = {}
    for event, field in pairs(CALLBACKS) do callbacks[event] = app[field] end
    apps[app.identifier] = {
        resource = GetInvokingResource(),
        callbacks = callbacks,
        def = {
            identifier = app.identifier, name = app.name, description = app.description, developer = app.developer,
            ui = app.ui, icon = app.icon, defaultApp = Config.autoInstallApps and app.defaultApp == true, price = tonumber(app.price), size = tonumber(app.size),
            images = app.images, landscape = app.landscape == true, keepOpen = app.keepOpen == true,
        },
    }
    SendNUIMessage({ action = 'addCustomApp', app = apps[app.identifier].def })
    return true
end)

local function remove(identifier)
    if not apps[identifier] then return false, 'no such app' end
    apps[identifier] = nil
    SendNUIMessage({ action = 'removeCustomApp', identifier = identifier })
    return true
end
Export('RemoveCustomApp', remove)

--- Replacement for SendNUIMessage: delivers `data` to the app's own page (only while it is open).
Export('SendCustomAppMessage', function(identifier, data)
    if not apps[identifier] then return false, 'no such app' end
    SendNUIMessage({ action = 'customAppMessage', identifier = identifier, data = data })
    return true
end)

--- The UI lost its app list (first load, or a new phone): send every registered app again.
function CustomApps.resend()
    for _, app in pairs(apps) do SendNUIMessage({ action = 'addCustomApp', app = app.def }) end
end

--- The UI reports that an app was opened, closed, used, installed or deleted.
function CustomApps.event(data)
    local app = apps[data.identifier]
    local fn = app and app.callbacks[data.event]
    if fn then fn() end
    if data.event == 'use' and app and not app.def.ui and not app.def.keepOpen then ClosePhone() end
end

-- An app disappears with the resource that registered it.
AddEventHandler('onResourceStop', function(res)
    for identifier, app in pairs(apps) do
        if app.resource == res then remove(identifier) end
    end
end)

-- Phone state ----------------------------------------------------------------------------------------

Export('IsOpen', IsPhoneOpen)

Export('ToggleOpen', function(open)
    if open == false or (open == nil and IsPhoneOpen()) then ClosePhone() else OpenPhone() end
end)

--- data: { app?, title, content }
Export('SendNotification', function(data)
    SendNUIMessage({ action = 'notify', app = data.app or 'settings', title = data.title or '', body = data.content or '' })
end)

--- ox_inventory calls this when the phone item is used (client = { export = 'lwk_phone.usePhone' }).
Export('usePhone', function(_, slot)
    if IsPhoneOpen() then ClosePhone() else OpenPhone(slot and slot.slot) end
end)
