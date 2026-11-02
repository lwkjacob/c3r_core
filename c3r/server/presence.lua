--[[ c3r — server: what the Discord activity (client/presence.lua) can't work out in a player's own game. ]]

-- A game only knows the players near it, so the counts come from here.
CreateThread(function()
    local max = GetConvarInt('sv_maxclients', 48)
    local last_players, last_duty
    while true do
        local players, duty = GetPlayers(), 0
        for _, id in ipairs(players) do
            if Player(id).state.c3rDuty then duty = duty + 1 end
        end
        if #players ~= last_players or duty ~= last_duty then
            last_players, last_duty = #players, duty
            GlobalState.c3rOnline = { players = #players, max = max, duty = duty }
        end
        Wait(15000)
    end
end)

AddEventHandler('c3r:stat', function(src, stat, n) TriggerClientEvent('c3r:presence:stat', src, stat, n) end)
