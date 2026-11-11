-- lwk_scene — c3r's /c3rconfig changed one of our values: live now, here and in every game (keys after a restart).
local function apply(res, list)
    if res ~= GetCurrentResourceName() or type(list) ~= 'table' then return end
    for _, c in ipairs(list) do
        local t = Config
        for i = 1, #c.keys - 1 do t = type(t) == 'table' and t[c.keys[i]] or nil end
        if type(t) == 'table' then t[c.keys[#c.keys]] = c.value end
    end
end
if IsDuplicityVersion() then AddEventHandler('c3r:configSet', apply) else RegisterNetEvent('c3r:configSet', apply) end
