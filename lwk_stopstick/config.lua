Config = {}

Config.Debug = false -- true: F8 logs + draws each stick's hit line and the wheel sweeps of vehicles near it

-- Who may use it. auto picks qbx_core > qb-core > es_extended > standalone
Config.Framework = 'auto' -- 'auto' | 'qb' | 'esx' | 'standalone'
Config.Jobs = { police = true, sheriff = true, state = true } -- qb/esx job names; empty table = anyone
Config.Ace = false -- standalone: e.g. 'lwk_stopstick.use' to need that ace, false = anyone

-- Where sticks come from:
--   'item'    use the inventory item to take one out, picking it up / putting it away gives the item back
--   'vehicle' each emergency vehicle carries Config.PerVehicle: take/return at the boot (ox_target or /stopstick)
--   'free'    /stopstick hands you one (testing)
--   'auto'    item when an inventory is found (ox_inventory, qb, esx), otherwise vehicle
Config.Source = 'vehicle'
Config.Item = 'stopstick'
Config.PerVehicle = 2
Config.Vehicles = {} -- model names that carry sticks, e.g. { 'police', 'police3' }; empty = any emergency-class vehicle

-- Rebindable in Settings > Key Bindings > FiveM
Config.Keys = {
    use = 'G',     -- carrying: throw at the ground marker. Holding the cord: yank the stick in
    release = 'X', -- let go of the cord (the stick stays where it is)
    take = '',     -- /stopstick: take one out / put it away. Empty = no default, bind it in the menu if you like
}

Config.ThrowMin = 2.5      -- metres
Config.ThrowRange = 9.0
Config.CordLength = 24.4   -- 80 ft reel: walking further lets go of the cord
Config.YankSpeed = 16.0    -- m/s the stick shoots toward you the instant the cord goes taut, then slides to a stop
Config.YankDistance = 12.0 -- most one yank brings it in
Config.MinDistance = 1.5   -- a yank stops this far from you

Config.BurstToRim = false  -- false: instantly flat but drivable; true: straight onto the rim
Config.HitWidth = 0.18     -- metres either side of the stick's line that count as running over it
Config.Despawn = 900       -- seconds a stick nobody holds the cord of stays on the road (0 = forever)
Config.DrawDistance = 100.0

-- Everything below comes from the models/animation build (models/build_stopstick.py, models/anim_stopstick.py)
-- the deployed sleeve is 3 sticks joined at the stitched waists, dragged as a physics chain (shared/tow.lua)
Config.Props = { sticks = { `lwk_stopstick_a`, `lwk_stopstick_b`, `lwk_stopstick_c` }, folded = `lwk_stopstick_folded`, reel = `lwk_stopstick_reel` }
Config.Anim = { dict = 'lwk_stopstick@anims', throw = 'throw', pull = 'pull', carry = 'carry', release = 0.6, yank = 0.2 } -- yank: where the hand starts hauling in the pull clip
Config.Attach = { -- AttachEntityToEntity offsets, rotation order 2
    pack = { bone = 28422, offset = vec3(-0.0094, 0.0, -0.088), rot = vec3(0.0, 0.0, -90.0) },  -- PH_R_Hand
    reel = { bone = 60309, offset = vec3(-0.0094, 0.0, 0.03), rot = vec3(-90.0, 15.0, 0.0) },   -- PH_L_Hand
}
Config.CordExit = vec3(0.0321, 0.0, 0.0631) -- reel space: where the cord leaves the reel
Config.HalfLength = 1.475                    -- half the deployed sleeve's length (throw preview)

Config.Text = {
    no_access = 'You are not equipped to deploy Stop Sticks.',
    none_left = 'This vehicle has no Stop Sticks left.',
    full = 'This vehicle\'s Stop Stick bay is full.',
    no_item = 'You don\'t have a Stop Stick.',
    hands_full = 'Your hands are full.',
    use_item = 'Use the Stop Stick item to take one out.',
    no_vehicle = 'Stand at the boot of an emergency vehicle.',
    out_of_cord = 'You ran out of cord and let go.',
    pickup = 'Press ~INPUT_PICKUP~ to pick up the Stop Stick',
    hit = '~g~Stop Stick hit!~s~ %s, %d tyre%s',             -- vehicle name, tyre count, plural s
    hint_carry = 'Aim at the road and press %s to throw',    -- %s = the bound key
    hint_cord = '%s yank the stick toward you  %s let go',
    take = 'Take Stop Stick',
    stow = 'Put Stop Stick away',
}
