-- Voice bridge (server): puts two players in a private call channel.
-- With no voice script, calls still connect but are silent.
--
--   pma-voice     its setPlayerCall export
--   saltychat     its AddPlayerToCall / RemovePlayerFromCall exports (calls there have names, not numbers)
--   mumble-voip   its SetCallChannel export, which only exists in the player's own game (config/bridge/client.lua)

Voice = {}

local function present(res) return GetResourceState(res) ~= 'missing' end

local kind = Config.calls.voice ~= 'auto' and Config.calls.voice
    or (present('pma-voice') and 'pma')
    or (present('saltychat') and 'salty')
    or (present('mumble-voip') and 'mumble')
    or 'none'
Voice.kind = kind

local at = {}   -- src -> the channel this file put them in, for the voice scripts that cannot be asked

--- `channel` is any positive number unique to the call; 0 leaves the call.
function Voice.set(src, channel)
    if kind == 'pma' then
        exports['pma-voice']:setPlayerCall(src, channel)
    elseif kind == 'salty' then
        if at[src] then exports.saltychat:RemovePlayerFromCall(tostring(at[src]), src) end
        if channel ~= 0 then exports.saltychat:AddPlayerToCall(tostring(channel), src) end
    elseif kind == 'mumble' then
        TriggerClientEvent('lwk_phone:voice', src, channel)
    end
    at[src] = channel ~= 0 and channel or nil
end

--- The call channel `src` is in right now (0 for none). pma-voice says so whoever put them there;
--- for the others it is the channel this phone last put them in.
function Voice.channel(src)
    if kind == 'pma' then return Player(src).state.callChannel or 0 end
    return at[src] or 0
end

AddEventHandler('playerDropped', function() at[source] = nil end)
