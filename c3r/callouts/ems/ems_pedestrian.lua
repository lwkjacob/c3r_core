--[[
    c3r medical call: PEDESTRIAN STRUCK.

    Someone hit by a car that drove on. A broken leg and a head injury, or a broken arm.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      bad       In the road, leg bent wrong, not making sense.
      arm       Sitting up, cradling their arm.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_pedestrian (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_pedestrian',
    name = 'Pedestrian struck',
    voice = 'call_pedestrian', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    trauma = true, -- (now and then a wrist or ankle broken too: felt on the head-to-toe check)
    reports = {
        'Caller says a car hit someone and kept going.',
        'Pedestrian down in the road after being hit.',
    },
    locations = {
        { street = 'West Mirror Drive', at = vector3(939.20, -486.62, 60.28), points = {
            patient = vector4(939.20, -486.62, 60.28, 126.5),
            nearby = vector4(940.00, -486.02, 60.28, 0.0),
        } },
        { street = 'Route 68', at = vector3(667.08, 2720.40, 41.40), points = {
            patient = vector4(667.08, 2720.40, 41.40, 200.0),
            nearby = vector4(667.88, 2721.00, 41.40, 0.0),
        } },
        { street = 'Clinton Ave', at = vector3(372.69, 323.39, 103.51), points = {
            patient = vector4(372.69, 323.39, 103.51, 173.8),
            nearby = vector4(373.49, 323.99, 103.51, 0.0),
        } },
        { street = 'San Andreas Ave', at = vector3(361.19, -835.97, 29.29), points = {
            patient = vector4(361.19, -835.97, 29.29, 215.3),
            nearby = vector4(361.99, -835.37, 29.29, 0.0),
        } },
        { street = 'Paleto Blvd', at = vector3(-150.98, 6489.88, 29.32), points = {
            patient = vector4(-150.98, 6489.88, 29.32, 344.2),
            nearby = vector4(-150.18, 6490.48, 29.32, 0.0),
        } },
        -- Sandy Shores, rough (placed from memory): check them in game, move any that are off with /c3rplace ems_pedestrian
        { street = 'Alhambra Dr', at = vector3(1961.50, 3740.50, 32.34), points = {
            patient = vector4(1961.50, 3740.50, 32.34, 300.0),
            nearby = vector4(1962.30, 3741.10, 32.34, 0.0),
        } },
        { street = 'Senora Fwy', at = vector3(2678.90, 3280.60, 55.24), points = {
            patient = vector4(2678.90, 3280.60, 55.24, 330.0),
            nearby = vector4(2679.70, 3281.20, 55.24, 0.0),
        } },
    },
    stories = {
        bad = { weight = 2, conditions = { { 'fracture', 'lleg' }, { 'hemorrhage', 'lleg' }, 'head', 'pain' },
            says = 'In the road, leg bent wrong, not making sense.', what = 'hit by a car', clue = { 'A shoe', 'prop_ld_shoe_01', 'A shoe, knocked off in the hit, metres from them.' }, },
        arm = { weight = 2, conditions = { { 'fracture', 'rarm' }, 'pain' },
            says = 'Sitting up, cradling their arm.', what = 'clipped by a car', },
    },
}))
