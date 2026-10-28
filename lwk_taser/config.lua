Config = {}

Config.Debug = false -- true: F8 prints barb placement error per hit and the cartridge hand-attach convention

-- auto picks ox_inventory > qb-core > es_extended > standalone (unlimited cartridges)
Config.Framework = 'auto' -- 'auto' | 'ox' | 'qb' | 'esx' | 'standalone'
Config.CartridgeItem = 'taser_cartridge'

-- Any weapon listed here becomes a taser. Bring your own model: add its weapon name.
-- muzzle/axis are only needed if the model has no 'gun_muzzle' bone or the laser points wrong.
-- In game: /tasercal, then /tasermuzzle x y z and /taseraxis x y z until it lines up; F8 prints the line to paste here.
Config.Weapons = {
    -- muzzle = the green laser LED on the TASER 10 model's face (models/taser10.blend, LedGreen)
    WEAPON_STUNGUN = { muzzle = vec3(0.163, 0.0006, 0.027) },
    WEAPON_STUNGUN_MP = {},
    -- WEAPON_MYTASER = { muzzle = vec3(0.20, 0.0, 0.05), axis = vec3(1.0, 0.0, 0.0) },
}

Config.Probes = 10            -- TASER 10: one magazine (CartridgeItem) = 10 single probes, one per trigger pull
Config.Range = 13.7           -- probe range in metres: TASER 10 is 45 ft (keep WireLength above this)
Config.CycleTime = 5          -- seconds per energy cycle; any probe hit = full cycle
Config.PainTime = 1500        -- ms of ragdoll for a drive stun
Config.DriveStun = false      -- TASER 10 has no drive stun: ARC only re-energises / warning-arcs. true adds it back
Config.DriveStunRange = 1.5
Config.DriveStunLockout = false -- true: drive stun alone locks out. false: only when it completes a circuit with a barb

Config.WireLength = 15.0      -- barbs rip out past this distance
Config.WireColor = { 200, 200, 200, 170 } -- r, g, b, alpha of the thin barb wires
Config.BarbProp = `lwk_taser_probe` -- TASER 10 probe streamed by this resource (stock fallback: `prop_dart_1`)
Config.BarbDepth = 0.02 -- metres the probe sinks past the hit point; errs into the body rather than floating
-- Where each bay's wire leaves the taser, in weapon space (x forward, z up), in firing order: shot 1 uses Bays[1].
-- Taken from the model's 10 probe holes. Check in game with Config.Debug (numbers drawn on the taser) and
-- /taserbay n x y z, which moves one live and prints the line to paste here.
Config.Bays = {
    vec3(0.165, 0.0, 0.010),       -- 1 top centre
    vec3(0.165, -0.0108, 0.0037),  -- 2
    vec3(0.165, 0.0108, 0.0037),   -- 3
    vec3(0.165, 0.0, -0.0025),     -- 4
    vec3(0.165, -0.0108, -0.0085), -- 5
    vec3(0.165, 0.0108, -0.0085),  -- 6
    vec3(0.165, 0.0, -0.0146),     -- 7
    vec3(0.165, -0.0108, -0.0208), -- 8
    vec3(0.165, 0.0108, -0.0208),  -- 9
    vec3(0.165, 0.0, -0.0271),     -- 10 bottom centre
}

-- Cartridge swap: the stun gun model has no cartridge; this prop is mounted on it and handled by the reload clip
Config.CartProp = `lwk_taser_cart`
Config.Reload = {
    dict = 'lwk_taser@reload', clip = 'reload', length = 2.0, -- seconds
    drop = 0.067, fetch = 0.233, seat = 0.600,  -- clip phases: old one falls off, new one in hand, seated
    -- cartridge in the left hand (PH_L_Hand) from the animation rig; refined in game after the first reload
    hand = { offset = vec3(-0.0181, -0.0871, 0.0980), rot = vec3(0.0, 0.0, 59.04) },
}

Config.Laser = { color = { 40, 255, 40 }, range = 50.0 }
Config.Light = { range = 25.0, brightness = 8.0, radius = 14.0 }
Config.ShowDistance = 60.0    -- draw other players' laser/light within this range

Config.SoundRange = 30.0
Config.Volume = 0.6

-- Rebindable in Settings > Key Bindings > FiveM
-- Barb removal is an ox_target option
Config.Keys = { arc = 'X', light = 'H', laser = 'J', reload = 'R' }
