Config = {}

Config.Debug = false

-- 'ptt'  : mic opens on key press, click-on plays once it is live, stays open MicLingerMs after release.
-- 'warm' : mic stays open the whole session so pre-roll catches the first syllable. Audio is only
--          buffered in memory (PreRollMs) and never transcribed outside push-to-talk.
Config.MicMode     = 'ptt'
Config.MicLingerMs = 10000
Config.PreRollMs   = 300

-- Browser noise suppression / echo cancellation / auto gain on the mic. Helps in noisy rooms, can hurt
-- recognition otherwise. Default for players who haven't set it in /control.
Config.MicProcessing = true

Config.PttKey = 'h'
Config.PaKey = 'b' -- hold to speak through the PA (c3r stops: "pull over", "driver, step out", a felony stop's orders)

-- Hand-to-shoulder radio animation while push-to-talk is held (other players see it).
Config.RadioAnimation          = true
Config.RadioAnimationInVehicle = false -- the arm leaves the steering wheel, so off by default

-- Players pick one in /control (or "None"); it's saved by name. Entry [RadioAnimationDefault] is
-- used until they pick.
--   dict/anim/flag : a game animation (flag 49 = loop, upper body only)
--   emote          : an rpemotes emote (only offered when Config.EmoteResource is running)
Config.RadioAnimationDefault = 1
Config.EmoteResource = 'rpemotes'
Config.RadioAnimations = {
    { name = 'Shoulder',          dict = 'random@arrests', anim = 'generic_radio_chatter', flag = 49 },
    { name = 'Chest',             emote = 'copmicpose002' },
    { name = 'Chest 2',           emote = 'copmicpose001' },
    { name = 'Chest 3',           emote = 'copmicpose0022' },
    { name = 'Handheld',          emote = 'handheld2' },
    { name = 'Handheld 2',        emote = 'handheld1' },
    { name = 'Handheld 3',        emote = 'wt4' },
    { name = 'Right Shoulder',    emote = 'rshoulder' },
}

-- Dispatcher addresses players by callsign ("One Adam Twelve, copy..."). Players set it in the
-- settings menu (/control).
Config.UseCallsign      = true
Config.CallsignRepeatMs = 8000 -- don't repeat the callsign on replies closer together than this

-- "Dispatch, hold traffic": a speed zone at the officer's position that AI traffic stops for,
-- shown to everyone as a circle on the map. "Release traffic" clears it; it also expires.
Config.TrafficHold = {
    radius     = 50.0, -- metres
    mph        = 0,    -- 0 = stop; e.g. 15 to slow traffic instead
    minutes    = 15,   -- auto-release
    blipColour = 0,    -- 0 white, 1 red, 47 orange ...
    blipAlpha  = 90,   -- 0-255
}

-- "Dispatch, nearest hospital / police station / fire station / impound" sets a GPS waypoint to
-- the closest one. Move these to match your MLOs, or add your own: an entry whose `clip` has no
-- nui/voice/places/poi_<clip>.ogg is announced generically ("route set to the nearest hospital").
Config.Places = {
    hospital = {
        { name = 'Pillbox Hill Medical Center',       clip = 'pillbox',        coords = vector3(298.6, -584.4, 43.3) },
        { name = 'Central Los Santos Medical Center', clip = 'central_ls',     coords = vector3(340.6, -1396.0, 32.5) },
        { name = 'Mount Zonah Medical Center',        clip = 'mount_zonah',    coords = vector3(-449.0, -340.0, 34.5) },
        { name = 'St. Fiacre Hospital',               clip = 'st_fiacre',      coords = vector3(1151.2, -1529.6, 35.4) },
        { name = 'Sandy Shores Medical Center',       clip = 'sandy_medical',  coords = vector3(1839.6, 3672.9, 34.3) },
        { name = 'The Bay Care Center',               clip = 'bay_care',       coords = vector3(-247.8, 6331.2, 32.4) },
    },
    police = {
        { name = 'Mission Row Police Station',        clip = 'mission_row',    coords = vector3(428.2, -984.0, 30.7) },
        { name = 'Vespucci Police Station',           clip = 'vespucci_pd',    coords = vector3(-1093.0, -809.0, 19.3) },
        { name = 'Vinewood Police Station',           clip = 'vinewood_pd',    coords = vector3(638.0, 1.0, 82.8) },
        { name = 'Rockford Hills Police Station',     clip = 'rockford_pd',    coords = vector3(-561.0, -132.0, 38.0) },
        { name = 'Davis Sheriff Station',             clip = 'davis_so',       coords = vector3(360.9, -1584.4, 29.3) },
        { name = 'La Mesa Police Station',            clip = 'la_mesa_pd',     coords = vector3(826.0, -1290.0, 28.2) },
        { name = 'Sandy Shores Sheriff Station',      clip = 'sandy_so',       coords = vector3(1853.0, 3686.0, 34.3) },
        { name = 'Paleto Bay Sheriff Station',        clip = 'paleto_so',      coords = vector3(-448.0, 6013.0, 31.7) },
    },
    fire = {
        { name = 'Davis Fire Station',                clip = 'davis_fd',       coords = vector3(199.0, -1643.0, 29.8) },
        { name = 'El Burro Heights Fire Station',     clip = 'el_burro_fd',    coords = vector3(1192.0, -1474.0, 34.9) },
        { name = 'Rockford Hills Fire Station',       clip = 'rockford_fd',    coords = vector3(-635.0, -122.0, 39.0) },
        { name = 'Airport Fire Station',              clip = 'airport_fd',     coords = vector3(-1032.0, -2385.0, 14.1) },
        { name = 'Sandy Shores Fire Station',         clip = 'sandy_fd',       coords = vector3(1691.0, 3585.0, 35.6) },
        { name = 'Paleto Bay Fire Station',           clip = 'paleto_fd',      coords = vector3(-379.0, 6118.0, 31.9) },
    },
    impound = {
        { name = 'Mission Row Impound',               clip = 'impound_ls',     coords = vector3(409.0, -1623.0, 29.3) },
    },
}

-- Chat command for the settings menu (mic, volumes, clicks, callsign). false to disable.
Config.SettingsCommand = 'control'

-- Ask "affirmative / negative" before intents marked confirm (complete callout, off duty).
Config.Confirm = true

-- When a transmission only roughly sounds like a command, ask "did you mean ...?" instead of "say again".
Config.AskWhenUnsure = true

-- Remember each player's misheard words: after "say again", a retry that works teaches the fix
-- ("tote truck" then "tow truck" -> tote = tow). Players see and remove them in the settings menu.
Config.LearnCorrections = true

-- How long a confirm prompt or "go ahead with the plate" waits for the next transmission.
Config.ContextWindowMs = 10000

-- How long after a callout offer "attach me" still accepts it.
Config.CalloutOfferWindowMs = 30000

Config.PlateCooldownMs = 2800

-- 10-99 has no c3r export yet. The dispatcher line plays first; hook your panic system here.
Config.OnPanic = function()
    TriggerEvent('lwk_control:panic')
end

-- Dispatcher voice volume default (0-100). Players override it in the settings menu.
Config.VoiceVolume = 70

Config.Clicks = {
    on     = 'nui/clicks/mic_click_on.wav',
    off    = 'nui/clicks/mic_click_off.wav',
    volume = 5, -- 0-100
}
