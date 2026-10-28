--[[
    lwk_control — the PA: what the officer says on the PA key (Config.PaKey), for c3r's stop to act on
    (exports.c3r:pa). Its own list, never the dispatch intents: dispatch doesn't hear the PA and never answers it.
    Phrases left out of hotwords.txt on purpose, so they don't pull dispatch's recognition toward them.
]]

PaIntents = {}

local function pa(id, cmd, say) PaIntents[#PaIntents + 1] = { id = 'pa_' .. id, cmd = cmd, say = say, run = function() end } end

pa('pull_over', 'pull_over', { 'pull over', 'pull over to the right', 'pull it over', 'stop the vehicle', 'stop the car' })
pa('felony', 'felony', { 'felony stop' })
pa('driver_out', 'driver_out', { 'driver step out', 'driver get out', 'driver step out of the vehicle',
    'driver out of the car', 'driver exit the vehicle', 'driver get out of the car', 'driver get out of the vehicle',
    'driver step out of the car' })
pa('passenger_out', 'passenger_out', { 'passenger step out', 'passenger get out', 'passenger step out of the vehicle',
    'passenger out of the car', 'passenger exit the vehicle', 'passenger get out of the car', 'passenger get out of the vehicle',
    'passenger step out of the car' })
pa('everyone_out', 'everyone_out', { 'everyone out', 'everybody out', 'everyone step out', 'everybody step out',
    'everyone out of the car', 'everybody out of the car', 'step out of the vehicle', 'get out of the car' })
pa('walk_back', 'walk_back', { 'walk backwards', 'walk back', 'walk backwards toward me', 'walk back toward me',
    'walk backwards towards me', 'walk back towards me', 'back up toward my voice', 'walk toward my voice',
    'walk backwards toward my voice' })
pa('kneel', 'kneel', { 'get on your knees', 'on your knees', 'get down on your knees', 'kneel down', 'get down' })
pa('hands_up', 'hands_up', { 'hands up', 'show me your hands', 'let me see your hands', 'hands where i can see them',
    'put your hands up' })
pa('back_in', 'back_in', { 'get back in the car', 'get back in your car', 'back in the vehicle', 'get back in the vehicle',
    'get back in your vehicle' })
pa('engine_off', 'engine_off', { 'turn off the engine', 'turn the engine off', 'shut off the engine', 'engine off',
    'kill the engine' })

-- The commands in what was said, in order. -> { 'driver_out', ... } (empty when nothing matched)
function PaCommands(text)
    local out = {}
    for _, c in ipairs(Brain.parse_all(text, PaIntents) or {}) do out[#out + 1] = c.intent.cmd end
    return out
end
