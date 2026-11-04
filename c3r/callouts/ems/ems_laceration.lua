--[[
    c3r medical call: BLEEDING INJURY.

    A bad cut. Through a window, on a kitchen knife, or a power tool.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      glass     Their arm sliced open on glass.
      hand      Hand wrapped in a soaked towel.
      tool      A deep wound in the thigh, pumping blood.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_laceration (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_laceration',
    name = 'Bleeding injury',
    voice = 'call_laceration', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    reports = {
        'Caller says someone has cut themselves badly and it will not stop bleeding.',
        'Person bleeding heavily from a cut.',
    },
    locations = {
        { street = 'Clinton Ave', at = vector3(367.79, 325.13, 103.62), points = {
            patient = vector4(367.79, 325.13, 103.62, 59.9),
            nearby = vector4(368.59, 325.73, 103.62, 0.0),
        } },
        { street = 'West Mirror Drive', at = vector3(1150.63, -328.56, 69.01), points = {
            patient = vector4(1150.63, -328.56, 69.01, 4.9),
            nearby = vector4(1151.43, -327.96, 69.01, 0.0),
        } },
        { street = 'Route 68', at = vector3(1158.05, 2702.15, 38.19), points = {
            patient = vector4(1158.05, 2702.15, 38.19, 60.0),
            nearby = vector4(1158.85, 2702.75, 38.19, 0.0),
        } },
        { street = 'Paleto Blvd', at = vector3(7.17, 6526.88, 31.43), points = {
            patient = vector4(7.17, 6526.88, 31.43, 315.9),
            nearby = vector4(7.97, 6527.48, 31.43, 0.0),
        } },
    },
    stories = {
        glass = { weight = 2, conditions = { { 'hemorrhage', 'rarm' }, 'pain' },
            says = 'Their arm sliced open on glass.', what = 'cut on broken glass', clue = { 'Broken glass', 'prop_cs_beer_bot_01', 'Broken glass, and blood on it.' }, },
        hand = { weight = 2, conditions = { { 'hemorrhage', 'lhand' }, 'pain' },
            says = 'Hand wrapped in a soaked towel.', what = 'with a deep cut to the hand', },
        tool = { weight = 1, conditions = { { 'hemorrhage', 'lleg' }, 'pain' },
            says = 'A deep wound in the thigh, pumping blood.', what = 'cut by a power tool', clue = { 'A drill', 'prop_tool_drill', 'A power tool, dropped where it slipped.' }, },
    },
}))
