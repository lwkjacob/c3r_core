--[[
    lwk_control — Voice: dispatcher audio + text replies.
    Clips live in nui/voice/<key>_<n>.ogg (random variant per key) and nui/voice/letters/<c>.ogg.
]]

-- Clips ship in lwk_control_assets (same nui/voice/... paths) so code updates stay small.
local RES = 'lwk_control_assets'
local KVP_VOICE_VOL = 'lwk_control_voice_vol'

VoiceVolume = tonumber(GetResourceKvpString(KVP_VOICE_VOL) or '') or Config.VoiceVolume

local variants = {}
local callbacks, next_id = {}, 0

-- Probes key_1, key_2, ... once; owners add variants by dropping in more numbered files.
local function variants_of(key)
    if not variants[key] then
        local list = {}
        for i = 1, 20 do
            local p = ('nui/voice/%s_%d.ogg'):format(key, i)
            if not LoadResourceFile(RES, p) then break end
            list[#list + 1] = p
        end
        variants[key] = list
    end
    return variants[key]
end

local probed = {}

-- True when nui/voice/<folder>/<key>.ogg ships (probed once per file).
local function clip_exists(folder, key)
    local path = ('nui/voice/%s/%s.ogg'):format(folder, key)
    if probed[path] == nil then probed[path] = LoadResourceFile(RES, path) ~= nil end
    return probed[path]
end

function VehicleClipExists(key) return clip_exists('vehicle', key) end
function PlaceClipExists(key) return clip_exists('places', key) end

function Clip(key)
    local list = variants_of(key)
    return list[1] and list[math.random(#list)] or nil
end

-- Callsign the dispatcher addresses you by (set from main.lua); nil = no callsign.
Callsign = nil          -- display text, e.g. '1-ADAM-12'
local callsign_clips = nil
local last_addressed = -math.huge

function SetCallsign(text, clips)
    Callsign, callsign_clips = text, clips
end

-- Dispatch's last transmission, for "say again your last": the clips as played and its feed text.
LastTransmission = { clips = nil, text = nil }

function RepeatLast()
    local last = LastTransmission
    if not last.clips and not last.text then return Reply('repeat_none') end
    if last.clips and VoiceVolume > 0 then
        SendNUIMessage({ type = 'speak', clips = last.clips, volume = VoiceVolume }) -- not re-recorded
    end
    if last.text then Notify(last.text) end
end

--- Queues clips (keys or 'nui/...' paths); on_done runs when they finish (or are skipped).
--- addressed = true starts with "<callsign>," unless the last addressed line was within
--- Config.CallsignRepeatMs, so back-to-back replies don't repeat it.
function Speak(items, on_done, addressed)
    local clips = {}
    for _, it in ipairs(items) do
        local p = it:find('/') and it or Clip(it)
        if p then clips[#clips + 1] = p end
    end
    if #clips == 0 or VoiceVolume <= 0 then
        if on_done then on_done() end
        return
    end
    if addressed and callsign_clips and GetGameTimer() - last_addressed > Config.CallsignRepeatMs then
        last_addressed = GetGameTimer()
        local prefixed = {}
        for _, c in ipairs(callsign_clips) do prefixed[#prefixed + 1] = c end
        prefixed[#prefixed + 1] = 'nui/voice/pause.ogg'
        for _, c in ipairs(clips) do prefixed[#prefixed + 1] = c end
        clips = prefixed
    end
    if items[1] ~= 'say_again' then LastTransmission.clips = clips end -- "10-9, say again" isn't worth repeating
    next_id = next_id + 1
    callbacks[next_id] = on_done
    SendNUIMessage({ type = 'speak', id = next_id, clips = clips, volume = VoiceVolume })
end

RegisterNUICallback('spoke', function(data, cb)
    cb({})
    if data.id == nil then return end -- settings "Test voice" has no callback
    local fn = callbacks[data.id]
    callbacks[data.id] = nil
    if fn then fn() end
end)

-- ─── feed notifications ───────────────────────────────────────────────────────

local FEED_MAX = 90

local function post_feed(line)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(line)
    EndTextCommandThefeedPostTicker(false, true)
end

-- The feed truncates long strings, so split on newlines and ~90 chars.
--- skip_repeat = true keeps it out of "say again your last" (e.g. "10-9, say again" itself).
function Notify(body, skip_repeat)
    if not skip_repeat and body:find('DISPATCH', 1, true) then LastTransmission.text = body end
    local chunks = {}
    for line in (body .. '\n'):gmatch('(.-)\n') do
        while #line > FEED_MAX do
            local cut = line:sub(1, FEED_MAX):match('.*() ') or FEED_MAX
            chunks[#chunks + 1] = line:sub(1, cut - 1)
            line = line:sub(cut + 1)
        end
        if line ~= '' then chunks[#chunks + 1] = line end
    end
    CreateThread(function()
        for i, c in ipairs(chunks) do
            if i > 1 then Wait(75) end
            post_feed(c)
        end
    end)
end

--- Dispatcher reply: feed text + voice line. Either may be nil.
function Reply(key, text)
    if text then Notify('~b~DISPATCH~s~ ' .. (Callsign and ('~y~' .. Callsign .. '~s~, ') or '') .. text, key == 'say_again') end
    if key then Speak({ key }, nil, true) end
end

--- Letter / digit clips for a plate string.
function SpellClips(plate)
    local out = {}
    for c in plate:lower():gmatch('[%w]') do out[#out + 1] = ('nui/voice/letters/%s.ogg'):format(c) end
    return out
end

function SetVoiceVolume(v)
    VoiceVolume = math.max(0, math.min(100, math.floor(v)))
    SetResourceKvp(KVP_VOICE_VOL, tostring(VoiceVolume))
end

RegisterNetEvent('lwk_control:reply', Reply)
