--[[ lwk_control — client: push-to-talk, NUI bridge, context modes, intent dispatch. ]]

local KVP_MIC        = 'lwk_control_mic_device_id'
local KVP_CLICKS     = 'lwk_control_clicks'
local KVP_CLICKS_VOL = 'lwk_control_clicks_vol'
local KVP_CALLSIGN   = 'lwk_control_callsign'
local KVP_MIC_FX     = 'lwk_control_mic_processing' -- '0' = browser noise suppression etc. off
local KVP_RADIO_ANIM = 'lwk_control_radio_anim_name' -- Config.RadioAnimations name, or 'None'
local KVP_CS_SPOKEN  = 'lwk_control_callsign_spoken' -- '0' = dispatch doesn't address you by callsign
local KVP_LEARNED    = 'lwk_control_learned' -- JSON list of { from, to } corrections learned from say-agains

local function callsign_spoken() return GetResourceKvpString(KVP_CS_SPOKEN) ~= '0' end

-- ─── callsign ─────────────────────────────────────────────────────────────────
-- The one signed on with in lwk_mdt (on the player's state bag), else the one typed in /control.

local function cad_callsign() return LocalPlayer.state.lwkMdtCallsign end
local function manual_callsign() return GetResourceKvpString(KVP_CALLSIGN) or '' end

local function apply_callsign(cad)
    local raw = Config.UseCallsign and (cad or cad_callsign() or manual_callsign()) or ''
    local cs = Brain.callsign(raw)
    -- Toggled off: dispatch stops addressing you; your callsign still goes to the units list.
    local spoken = cs and callsign_spoken()
    SetCallsign(spoken and raw:upper() or nil, spoken and cs.clips or nil)
    -- reported to the server for the units list, even when not spoken (and a CAD callsign even if dispatch can't say it)
    CallsignRaw = raw ~= '' and (cs or cad or cad_callsign()) and raw:upper() or ''
end

CreateThread(function() apply_callsign() end)

-- Signed on (or changed in the CAD's settings): dispatch calls you that from now on. (The bag's new value
-- comes in here; the state itself updates just after.)
AddStateBagChangeHandler('lwkMdtCallsign', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, cs)
    apply_callsign(type(cs) == 'string' and cs ~= '' and cs or nil)
end)

local status = 'loading'
local settings_open = false

local function mic_processing()
    local v = GetResourceKvpString(KVP_MIC_FX)
    if v == nil or v == '' then return Config.MicProcessing ~= false end
    return v ~= '0'
end

local function clicks()
    local on = GetResourceKvpString(KVP_CLICKS)
    return {
        on      = Config.Clicks.on,
        off     = Config.Clicks.off,
        enabled = on == nil or on == '' or on == '1',
        volume  = tonumber(GetResourceKvpString(KVP_CLICKS_VOL) or '') or Config.Clicks.volume,
    }
end

-- Context mode decides how the next transmission is read:
--   normal  : commands
--   confirm : affirmative / negative (pending holds the commands to run)
--   plate   : phonetic alphabet + digits (after "run plate" with no vehicle stopped)
local mode, mode_until, pending = 'normal', 0, nil
local pending_fix, pending_text = nil, nil -- "did you mean" prompt: the correction to learn on "affirmative"
local failed = nil                         -- { text, at }: the last transmission that got "say again"

local function log(fmt, ...)
    if Config.Debug then print(('[lwk_control] ' .. fmt):format(...)) end
end

local function say_again() Reply('say_again', '10-9, say again.') end

local function set_mode(m)
    mode, mode_until = m, GetGameTimer() + Config.ContextWindowMs
    if m == 'normal' then pending, pending_fix, pending_text = nil, nil, nil end
end

-- ─── learned corrections ──────────────────────────────────────────────────────

local LEARN_MAX_FIXES = 40
local LEARN_WINDOW_MS = 20000 -- a retry this soon after "say again" counts as a correction

local function valid_fix(f)
    return type(f) == 'table' and type(f.from) == 'string' and type(f.to) == 'string' and f.from ~= f.to
        and #f.from <= 40 and #f.to <= 40 and f.from:match("^[%w' ]+$") ~= nil and f.to:match("^[%w' ]+$") ~= nil
end

local function load_fixes()
    local ok, list = pcall(json.decode, GetResourceKvpString(KVP_LEARNED) or '[]')
    local out = {}
    for _, f in ipairs(ok and type(list) == 'table' and list or {}) do
        if valid_fix(f) then out[#out + 1] = { from = f.from, to = f.to } end
    end
    return out
end

local learned = load_fixes()

local function save_fixes(list)
    learned = list
    SetResourceKvp(KVP_LEARNED, json.encode(learned))
end

local function remember_fix(f)
    if Config.LearnCorrections == false or not valid_fix(f) then return end
    local list = {}
    for _, old in ipairs(learned) do
        if old.from ~= f.from then list[#list + 1] = old end
    end
    list[#list + 1] = { from = f.from, to = f.to }
    while #list > LEARN_MAX_FIXES do table.remove(list, 1) end
    save_fixes(list)
    log('learned "%s" -> "%s"', f.from, f.to)
    Notify(('~c~Voice dispatch learned "%s" means "%s"%s'):format(f.from, f.to,
        Config.SettingsCommand and (' (remove it in /' .. Config.SettingsCommand .. ')') or ''))
end

-- A command that parsed soon after a "say again": learn what was misheard the first time.
local function learn_from_retry(text, cmds)
    local f = failed
    failed = nil
    if not f or GetGameTimer() - f.at > LEARN_WINDOW_MS then return end
    for _, c in ipairs(cmds) do
        if not c.intent.chat then
            for _, fix in ipairs(Brain.learn(f.text, text, Intents)) do remember_fix(fix) end
            return
        end
    end
end

function EnterPlateMode()
    set_mode('plate')
    Reply('plate_go_ahead', 'Go ahead with the plate.')
end

-- A confirm prompt or "go ahead with the plate" lapses after Config.ContextWindowMs.
local function expire_mode()
    if mode ~= 'normal' and GetGameTimer() > mode_until then set_mode('normal') end
end

local function run(intent, ctx)
    log('-> %s %s', intent.id, json.encode(ctx))
    local ok, err = pcall(intent.run, ctx)
    if not ok then print(('[lwk_control] intent %s errored: %s'):format(intent.id, tostring(err))) end
    TriggerEvent('lwk_control:ran', intent.id, ctx) -- lets other resources (lwk_mdt) log what was done
end

-- Each command replies on its own; the voice queue plays the replies back to back.
local function run_all(cmds)
    for _, c in ipairs(cmds) do run(c.intent, c.ctx) end
end

-- True when the transcript holds a real command (small talk doesn't count).
local function has_command(text)
    for _, c in ipairs(Brain.parse_all(text, Intents) or {}) do
        if not c.intent.chat then return true end
    end
    return false
end

local function handle(text)
    if mode == 'confirm' then
        local answer = Brain.parse_confirm(text)
        if answer == 'yes' then
            local p, fix = pending, pending_fix
            set_mode('normal')
            -- only the words that differed, and never real command words ("cool" -> "call")
            if fix then for _, f in ipairs(Brain.learn(fix.from, fix.to, Intents)) do remember_fix(f) end end
            return run_all(p)
        elseif answer == 'no' then
            -- a "did you mean" that was wrong still counts as a miss: the retry can teach the fix
            if pending_text then failed = { text = pending_text, at = GetGameTimer() } end
            set_mode('normal')
            return Reply('disregard', 'Copy, disregard.')
        elseif has_command(text) then
            -- moved on to something else: drop the prompt, handle the new command (after a "did you
            -- mean", that is usually the correct retry, so it can teach the fix)
            if pending_text then failed = { text = pending_text, at = GetGameTimer() } end
            set_mode('normal')
        elseif pending_text and text ~= '' then
            -- neither yes nor no to a "did you mean": drop it and read this one as a fresh transmission
            set_mode('normal')
        elseif text ~= '' then
            mode_until = GetGameTimer() + Config.ContextWindowMs
            return Reply('confirm', 'Affirmative or negative?')
        else
            return
        end
    end

    if mode == 'plate' then
        if text:find('disregard') then set_mode('normal') return Reply('disregard', 'Copy.') end
        if has_command(text) then set_mode('normal') return handle(text) end -- a new command, not a plate
        local tokens = {}
        for w in text:gmatch('%S+') do tokens[#tokens + 1] = w end
        local plate = Brain.read_plate(tokens)
        if plate then
            set_mode('normal')
            RunPlateCheck(plate)
        elseif text ~= '' then
            say_again()
        end
        return
    end

    local cmds, reason = Brain.parse_all(text, Intents)
    if cmds then
        learn_from_retry(text, cmds)
    elseif reason == 'unknown' then
        -- last resort: the command that SOUNDS closest ("play check" -> plate check), leaning toward
        -- what fits the situation; run it if clearly closest, otherwise ask
        local it, ctx, sure, fix = Brain.snap(text, Intents, LikelyIntents())
        if it and sure then
            log('snapped by sound -> %s', it.id)
            cmds = { { intent = it, ctx = ctx } }
        elseif it and Config.AskWhenUnsure ~= false then
            log('unsure, asking -> %s', it.id)
            set_mode('confirm')
            pending, pending_fix, pending_text = { { intent = it, ctx = ctx } }, fix, text
            local what = (it.verb == 'cancel' and 'cancel ' or '') .. fix.to
            return Reply('confirm', ('Did you mean "%s"? Affirmative or negative.'):format(what))
        end
    end
    if not cmds then
        log('no match (%s)', tostring(reason))
        if reason ~= 'empty' then
            failed = { text = text, at = GetGameTimer() }
            say_again()
        end
        return
    end
    -- Small talk said alongside a real command ("tow truck, thanks") is dropped.
    local real = {}
    for _, c in ipairs(cmds) do
        if not c.intent.chat then real[#real + 1] = c end
    end
    if #real > 0 then cmds = real end
    -- If any command needs confirming, the whole transmission waits for "affirmative".
    local needs_confirm, labels = false, {}
    for _, c in ipairs(cmds) do
        local cf = c.intent.confirm -- (true, or a function: only sometimes, e.g. 10-8 while on a call)
        needs_confirm = needs_confirm or cf == true or (type(cf) == 'function' and cf() == true)
        labels[#labels + 1] = c.intent.label or c.intent.say[1]
    end
    if needs_confirm and Config.Confirm then
        set_mode('confirm')
        pending = cmds
        return Reply('confirm', ('Confirm, %s? Affirmative or negative.'):format(table.concat(labels, ' and ')))
    end
    run_all(cmds)
end

-- ─── NUI callbacks ────────────────────────────────────────────────────────────

-- NUI asks for its config once loaded; answering here avoids guessing when the page is ready.
RegisterNUICallback('ready', function(_, cb)
    cb({
        debug       = Config.Debug == true,
        micMode     = Config.MicMode,
        lingerMs    = Config.MicLingerMs,
        preRollMs   = Config.PreRollMs,
        clicks      = clicks(),
        micDeviceId = GetResourceKvpString(KVP_MIC) or '',
        micProcessing = mic_processing(),
    })
end)

RegisterNUICallback('status', function(data, cb)
    status = data.state or 'idle'
    cb({})
end)

RegisterNUICallback('modelLoaded', function(data, cb)
    print(('[lwk_control] Speech model loaded in %d ms (%s)'):format(tonumber(data.ms) or -1, tostring(data.url)))
    cb({})
end)

-- Player-facing explanations for the NUI's known failure states (shown at most once per minute).
local ERROR_TEXT = {
    server_asr_failed = "~r~Voice dispatch unavailable:~s~ your game's browser has WebAssembly disabled and the "
        .. "server's speech recognition failed to start. Usually Windows Exploit Protection (Arbitrary code guard) "
        .. 'or antivirus exploit protection on FiveM: remove FiveM from those, then restart FiveM.',
    model_loading = 'Voice dispatch is still loading, try again in a moment.',
}
local last_error_notice = -60000

RegisterNUICallback('error', function(data, cb)
    cb({})
    local msg = tostring(data.message)
    print('[lwk_control] NUI error: ' .. msg)
    if ERROR_TEXT[msg] and GetGameTimer() - last_error_notice > 60000 then
        last_error_notice = GetGameTimer()
        Notify(ERROR_TEXT[msg])
    end
end)

RegisterNUICallback('transcript', function(data, cb)
    cb({})
    if data.target == 'pa' then
        local text = Brain.normalize(type(data.text) == 'string' and data.text or '')
        local cmds = PaCommands(text)
        log('[pa] heard "%s" -> %s', text, table.concat(cmds, ', '))
        if #cmds == 0 then
            if text ~= '' then Notify(('~c~PA: not understood ("%s")'):format(text)) end
            return
        end
        if GetResourceState('c3r') ~= 'started' then return Notify('~r~PA: c3r is not running.') end
        local ok, done = pcall(function() return exports.c3r:pa(cmds) end)
        if ok and not done then Notify('~c~PA: nobody to give that order to.') end
        return
    end
    if data.target == 'subject' then -- raw text: the dispatch word fixes would mangle free speech
        local text = type(data.text) == 'string' and data.text or '' -- '' too: the subject says "sorry, what?"
        if GetResourceState('lwk_npcai') ~= 'started' then return Notify('~r~lwk_npcai is not running.') end
        log('[subject] heard "%s" in %d ms', text, tonumber(data.ms) or -1)
        TriggerEvent('lwk_control:subjectSpeech', text)
        return
    end
    -- free-form transcript -> general word fixes ("callouts" -> "call outs", "code for" -> "code four")
    local text = Brain.apply_fixes(Brain.normalize(type(data.text) == 'string' and data.text or ''), learned)
    if data.test then -- /control mic check: show what it heard and would do, run nothing
        local cmds = Brain.parse_all(text, Intents)
        local command
        if cmds then
            local names = {}
            for _, c in ipairs(cmds) do
                names[#names + 1] = (c.intent.verb == 'cancel' and 'cancel ' or '') .. (c.intent.label or c.intent.say[1])
            end
            command = table.concat(names, ', ')
        elseif text ~= '' then
            local it, _, sure, fix = Brain.snap(text, Intents, LikelyIntents())
            if it then command = (sure and 'sounds like "%s"' or 'would ask: did you mean "%s"?'):format(fix.to) end
        end
        SendNUIMessage({ type = 'micTestResult', heard = text, command = command })
        return
    end
    if Config.Debug then
        local words = {}
        for _, w in ipairs(data.words or {}) do
            words[#words + 1] = ('%s(%.2f)'):format(w.word, tonumber(w.conf) or 0)
        end
        log('[%s] heard "%s" in %d ms  [%s]', mode, text, tonumber(data.ms) or -1, table.concat(words, ' '))
    end
    handle(text)
end)

-- ─── server-side recognition (NUI without WebAssembly) ───────────────────────
-- The NUI sends ~250 ms of 16-bit PCM per chunk (~11 KB base64); server/asr.js answers with the text.

RegisterNUICallback('asrWarm', function(_, cb)
    cb({})
    TriggerServerEvent('lwk_control:asrWarm')
end)

RegisterNUICallback('asrChunk', function(data, cb)
    cb({})
    local id, seq = tonumber(data.id), tonumber(data.seq)
    if not id or not seq or type(data.pcm) ~= 'string' then return end
    id, seq = math.floor(id), math.floor(seq)
    -- Latent: audio trickles up without delaying other events (~43 KB/s while talking).
    TriggerLatentServerEvent('lwk_control:asr', 96000, id, seq, data.pcm, data.final == true)
end)

RegisterNetEvent('lwk_control:asrResult', function(id, text, err, ms)
    SendNUIMessage({ type = 'serverTranscript', id = id, text = text, error = err, ms = ms })
end)

-- ─── push to talk ─────────────────────────────────────────────────────────────

-- Hand-to-shoulder radio, upper body only, looping while H is held.
local ptt_held = false
local anim_playing = nil

local function emotes_running() return GetResourceState(Config.EmoteResource or 'rpemotes') == 'started' end

-- The player's pick from /control, saved by name ('None' = off; unset or no longer in the list =
-- the default). Emote picks fall back to the default when rpemotes isn't running.
local function chosen_radio_anim()
    local saved = GetResourceKvpString(KVP_RADIO_ANIM)
    if saved == 'None' then return nil end
    local default = Config.RadioAnimations[Config.RadioAnimationDefault]
    local a = default
    for _, entry in ipairs(Config.RadioAnimations) do
        if entry.name == saved then a = entry break end
    end
    if a and a.emote and not emotes_running() then a = default end
    return a
end

local function radio_anim_start()
    local a = Config.RadioAnimation and chosen_radio_anim()
    if not a then return end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedSwimming(ped) then return end
    if IsPedInAnyVehicle(ped, false) and not Config.RadioAnimationInVehicle then return end
    if GetSelectedPedWeapon(ped) ~= joaat('WEAPON_UNARMED') then return end -- don't fight a drawn weapon
    if a.emote then
        anim_playing = a
        pcall(function() exports[Config.EmoteResource]:EmoteCommandStart(a.emote, 0) end)
        return
    end
    CreateThread(function()
        RequestAnimDict(a.dict)
        local deadline = GetGameTimer() + 1000
        while not HasAnimDictLoaded(a.dict) and GetGameTimer() < deadline do Wait(0) end
        if not ptt_held or not HasAnimDictLoaded(a.dict) then return end -- released while loading
        TaskPlayAnim(ped, a.dict, a.anim, 8.0, 2.0, -1, a.flag or 49, 0.0, false, false, false)
        anim_playing = a
    end)
end

local function radio_anim_stop()
    local a = anim_playing
    anim_playing = nil
    if not a then return end
    if a.emote then
        if emotes_running() then pcall(function() exports[Config.EmoteResource]:EmoteCancel(true) end) end
    else
        StopAnimTask(PlayerPedId(), a.dict, a.anim, -4.0)
    end
end

local talk_held = false -- "talk to subject" key (lwk_npcai); shares the one mic, so only one key at a time
local pa_held = false   -- the PA key: the same mic again

-- Holding the radio or PA key, your mic's live in pma-voice too, so players near you hear what you say. The PA carries
-- further. (If pma-voice isn't running, nothing here does anything.) UNVERIFIED in game: SET_CONTROL_NORMAL standing in for
-- the push-to-talk key.
local voice_held, voice_far = false, false
local function pma_on() return (Config.PmaVoice or {}).enabled ~= false and GetResourceState('pma-voice') == 'started' end
local function voice_down(range)
    if not pma_on() or voice_held then return end
    voice_held = true
    voice_far = range ~= nil
    if range then pcall(function() exports['pma-voice']:overrideProximityRange(range + 0.0, true) end) end
    CreateThread(function()
        while voice_held do
            SetControlNormal(0, 249, 1.0) -- INPUT_PUSH_TO_TALK
            Wait(0)
        end
    end)
end
local function voice_up()
    if not voice_held then return end
    voice_held = false
    if voice_far then pcall(function() exports['pma-voice']:clearProximityOverride() end) end
    voice_far = false
end
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then voice_up() end end)

RegisterCommand('+lwk_control_ptt', function()
    if IsPauseMenuActive() or talk_held or pa_held then return end
    ptt_held = true
    voice_down()
    expire_mode()
    SendNUIMessage({ type = 'pttDown' })
    radio_anim_start()
end, false)

RegisterCommand('-lwk_control_ptt', function()
    if not ptt_held then return end
    ptt_held = false
    voice_up()
    SendNUIMessage({ type = 'pttUp' })
    radio_anim_stop()
end, false)

RegisterKeyMapping('+lwk_control_ptt', 'Push to talk (lwk_control)', 'keyboard', Config.PttKey)

-- The PA: no radio animation or clicks, and dispatch never hears it.
RegisterCommand('+lwk_control_pa', function()
    if IsPauseMenuActive() or ptt_held or talk_held or pa_held then return end
    pa_held = true
    voice_down((Config.PmaVoice or {}).pa_range)
    SendNUIMessage({ type = 'paDown' })
end, false)
RegisterCommand('-lwk_control_pa', function()
    if not pa_held then return end
    pa_held = false
    voice_up()
    SendNUIMessage({ type = 'pttUp' })
end, false)
RegisterKeyMapping('+lwk_control_pa', 'PA: speak through the loudspeaker (lwk_control)', 'keyboard', Config.PaKey or 'n')

-- Speech to the subject: lwk_npcai owns the key and calls this on press (true) / release (false).
-- Same mic and model, no radio animation or clicks; the transcript goes back as lwk_control:subjectSpeech.
exports('SubjectTalk', function(down)
    if down then
        if IsPauseMenuActive() or ptt_held or talk_held or pa_held then return end
        talk_held = true
        SendNUIMessage({ type = 'talkDown' })
    elseif talk_held then
        talk_held = false
        SendNUIMessage({ type = 'pttUp' })
    end
end)

-- ─── server -> client ─────────────────────────────────────────────────────────

-- Callout location for "where's my call?": the c3r callout's coords.
RegisterNetEvent('lwk_control:callAccepted', function(coords)
    State.call_coords = coords
    log('callout accepted, coords: %s', tostring(coords))
end)

RegisterNetEvent('lwk_control:callEnded', function() State.call_coords = nil end)

RegisterNetEvent('lwk_control:activity', function(kind, on)
    if kind == 'stop' or kind == 'pursuit' then State[kind] = on == true end
end)

RegisterNetEvent('lwk_control:offered', function()
    State.offer_until = GetGameTimer() + Config.CalloutOfferWindowMs
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if settings_open then SetNuiFocus(false, false) end
    radio_anim_stop() -- also deletes a held radio prop
    SendNUIMessage({ type = 'shutdown' })
end)

-- ─── settings menu ────────────────────────────────────────────────────────────

-- Picker entries: None + every animation usable on this server (emotes only with rpemotes running).
local function radio_anim_options()
    local out = { 'None' }
    if not Config.RadioAnimation then return out end
    for _, a in ipairs(Config.RadioAnimations) do
        if not a.emote or emotes_running() then out[#out + 1] = a.name end
    end
    return out
end

local function open_settings()
    if settings_open then return end
    settings_open = true
    SetNuiFocus(true, true)
    local c = clicks()
    SendNUIMessage({
        type = 'openSettings', micDeviceId = GetResourceKvpString(KVP_MIC) or '', micProcessing = mic_processing(),
        voiceVolume = VoiceVolume, clicksEnabled = c.enabled, clicksVolume = c.volume,
        callsign = cad_callsign() or manual_callsign(), callsignFromCad = cad_callsign() ~= nil, callsignSpoken = callsign_spoken(),
        radioAnims = radio_anim_options(),
        radioAnim = (chosen_radio_anim() or { name = 'None' }).name,
        learned = learned,
    })
end

-- Mic and clicks as saved (also undoes a mic picked only for the /control mic check).
local function push_settings()
    SendNUIMessage({ type = 'applySettings', micDeviceId = GetResourceKvpString(KVP_MIC) or '', clicks = clicks(),
        micProcessing = mic_processing() })
end

local function close_settings()
    settings_open = false
    SetNuiFocus(false, false)
end

RegisterNUICallback('closeSettings', function(_, cb) close_settings() push_settings() cb({}) end)

RegisterNUICallback('saveSettings', function(data, cb)
    cb({})
    close_settings()
    SetResourceKvp(KVP_MIC, type(data.micDeviceId) == 'string' and data.micDeviceId or '')
    SetResourceKvp(KVP_MIC_FX, data.micProcessing == false and '0' or '1')
    SetResourceKvp(KVP_CLICKS, data.clicksEnabled == false and '0' or '1')
    local cv = tonumber(data.clicksVolume)
    if cv then SetResourceKvp(KVP_CLICKS_VOL, tostring(math.max(0, math.min(100, math.floor(cv))))) end
    if tonumber(data.voiceVolume) then SetVoiceVolume(tonumber(data.voiceVolume)) end
    SetResourceKvp(KVP_CS_SPOKEN, data.callsignSpoken == false and '0' or '1')
    if type(data.radioAnim) == 'string' then SetResourceKvp(KVP_RADIO_ANIM, data.radioAnim:sub(1, 40)) end
    local cs = type(data.callsign) == 'string' and data.callsign:match('^%s*(.-)%s*$') or ''
    if cad_callsign() then
        -- signed on in the CAD: that's the callsign (changed in the CAD's settings), not this box
    elseif cs == '' or Brain.callsign(cs) then
        SetResourceKvp(KVP_CALLSIGN, cs)
    else
        Notify('~r~Callsign not saved:~s~ use numbers and letters, e.g. 1-Adam-12')
    end
    if type(data.learned) == 'table' then
        local list = {}
        for _, f in ipairs(data.learned) do
            if valid_fix(f) and #list < LEARN_MAX_FIXES then list[#list + 1] = { from = f.from, to = f.to } end
        end
        save_fixes(list)
    end
    apply_callsign()
    push_settings()
end)

if Config.SettingsCommand then
    RegisterCommand(Config.SettingsCommand, open_settings, false)
end

exports('getStatus', function() return status end)
exports('addIntent', AddIntent)
exports('openSettings', open_settings)
exports('getCallsign', function() return CallsignRaw or '' end)

-- A dispatch transmission from another resource: feed text and/or clips (keys, nui/ paths, or
-- https://cfx-nui-<resource>/... URLs), queued with dispatch's own replies.
exports('say', function(clips, text)
    if type(text) == 'string' then Notify('~b~DISPATCH~s~ ' .. text) end
    if type(clips) == 'table' then Speak(clips) end
end)

-- A call going out: "<key>_to" + the location of `at`, from the location's own clips. A line with no "_to" version (a
-- server's own, in nui/voice/custom/): the plain line, then "Your call is at" + the location. No clips for that location:
-- the plain line, <key>.
exports('sayCall', function(key, at, text)
    if type(text) == 'string' then Notify('~b~DISPATCH~s~ ' .. text) end
    local where = Brain.location_words(LocationAt(at), PlaceClipExists)
    if not where then return Speak({ key }) end
    local clips = Clip(key .. '_to') and { key .. '_to' } or { key, 'call_at' }
    for _, it in ipairs(where) do clips[#clips + 1] = it end
    Speak(clips)
end)

-- Run an intent by id as if it had been said (no confirm prompt: a button press is deliberate).
exports('run', function(id, ctx)
    for _, it in ipairs(Intents) do
        if it.id == id then
            ctx = type(ctx) == 'table' and ctx or {}
            ctx.verb, ctx.text = ctx.verb or it.verb, ctx.text or ''
            run(it, ctx)
            return true
        end
    end
    return false
end)
