--[[ c3r — client: the NUI's prompts, and key names for them. ]]

-- The key a player bound to one of our commands, as text for the NUI ("E", "U"). The game reports
-- letter keys as "t_E"; anything else (Shift, arrows) falls back to the name given.
function KeyName(cmd, fallback)
    local s = GetControlInstructionalButton(0, (GetHashKey(cmd) | 0x80000000) & 0xFFFFFFFF, true)
    return type(s) == 'string' and s:match('^t_(.+)$') or fallback
end

--[[ A prompt card, top left. id: one card per id, shown again = updated in place.
     kind: 'info' | 'alert' (the pull-over red) | 'ok'. ms: hide after this long (nil: until cleared). ]]
function Prompt(id, kind, title, text, ms)
    SendNUIMessage({ type = 'prompt', id = id, kind = kind, title = title, text = text, ms = ms })
end

-- The PA key, as lwk_control has it bound ('B' when lwk_control isn't running).
function PaKeyName() return KeyName('+lwk_control_pa', 'B') end

-- An officer's line out loud (server/stops.lua voice()): from = their server id, quieter with distance from them.
RegisterNetEvent('c3r:voice', function(key, from, range)
    local pl = GetPlayerFromServerId(from)
    if pl == -1 then return end
    local d = #(GetEntityCoords(GetPlayerPed(pl)) - GetEntityCoords(PlayerPedId()))
    local volume = (Config.Voice or {}).volume or 1.0
    SendNUIMessage({ type = 'voice', clip = key, volume = volume * math.max(0.0, 1.0 - d / (range or 20.0)) })
end)

function ClearPrompt(id) SendNUIMessage({ type = 'prompt', id = id, clear = true }) end

-- A menu just closed: keep what closed it from reaching the game. Esc would open the pause menu, and a click that
-- picked an option is still held down when the game gets the mouse back: attack and melee wait until it's let go.
local ATTACK = { 24, 25, 140, 141, 142, 257, 263, 264 }
function NoPause(ms)
    CreateThread(function()
        local now = GetGameTimer()
        local until_t, cap = now + (ms or 600), now + 3000
        while GetGameTimer() < until_t or (GetGameTimer() < cap and (IsDisabledControlPressed(0, 24) or IsDisabledControlPressed(0, 25))) do
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            for _, c in ipairs(ATTACK) do DisableControlAction(0, c, true) end
            Wait(0)
        end
    end)
end
