--[[
    c3r medical call: INJURED HIKER.

    A hiker hurt out in the hills: a broken leg after hours in the heat, a fall onto the rocks, or chest pain on the climb.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      leg       Stuck for hours with a broken leg, out of water.
      rocks     Slipped on the rocks and hit their head.
      heart     Chest pain halfway up the climb, grey and sweating.

    Spots marked rough are from memory: check them in game and move them with /c3rplace ems_hiker.
]]

Callout(Ems.call({
    id = 'ems_hiker',
    name = 'Injured hiker',
    voice = 'call_hiker', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    trauma = true, -- (now and then a wrist or ankle broken too: felt on the head-to-toe check)
    age = { 18, 70 },
    reports = {
        'Caller says a hiker is hurt and cannot walk out.',
        'Hiker down on the trail. They called it in themselves.',
    },
    locations = {
        { street = 'Route 68', at = vector3(585.25, 2813.67, 41.79), points = {
            patient = vector4(585.25, 2813.67, 41.79, 22.6),
            nearby = vector4(586.05, 2814.27, 41.79, 0.0),
        } },
        { street = 'Senora Fwy', at = vector3(1707.93, 6416.51, 32.64), points = {
            patient = vector4(1707.93, 6416.51, 32.64, 182.0),
            nearby = vector4(1708.73, 6417.11, 32.64, 0.0),
        } },
        { street = 'Joshua Rd', at = vector3(276.34, 2837.48, 43.51), points = {
            patient = vector4(276.34, 2837.48, 43.51, 264.7),
            nearby = vector4(277.14, 2838.08, 43.51, 0.0),
        } },
        { street = 'Panorama Dr', at = vector3(1664.21, 3581.10, 35.02), points = {
            patient = vector4(1664.21, 3581.10, 35.02, 32.7),
            nearby = vector4(1665.01, 3581.70, 35.02, 0.0),
        } },
    },
    stories = {
        leg = { weight = 2, conditions = { { 'fracture', 'rleg' }, 'pain', 'dehydration' },
            says = 'Stuck for hours with a broken leg, out of water.', what = 'a hiker with a broken leg, out in the heat', clue = { 'A water bottle', 'prop_ld_flow_bottle', 'A water bottle, empty.' }, },
        rocks = { weight = 2, conditions = { 'head', { 'hemorrhage', 'head' }, 'pain' },
            says = 'Slipped on the rocks and hit their head.', what = 'a hiker who fell and hit their head', },
        heart = { weight = 1, conditions = { 'cardiac' },
            says = 'Chest pain halfway up the climb, grey and sweating.', what = 'a hiker with a heart attack', },
    },
}))
