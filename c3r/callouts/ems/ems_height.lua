--[[
    c3r medical call: FALL FROM HEIGHT.

    Someone who fell off a roof or ladder doing jobs: both legs broken, a head injury, or a cut from the tools.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      legs      Landed on their feet. Neither leg is straight.
      head      Landed on their head. Barely responding.
      tools     A broken leg, and their arm cut open by the saw they fell with.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_height (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_height',
    name = 'Fall from height',
    voice = 'call_height', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    trauma = true, -- (now and then a wrist or ankle broken too: felt on the head-to-toe check)
    age = { 20, 70 },
    reports = {
        'Caller says someone fell off a roof.',
        'Person fell from a ladder. They are on the ground and not moving much.',
    },
    locations = {
        { street = 'Calafia Rd', at = vector3(95.92, 3751.11, 40.63), points = {
            patient = vector4(95.92, 3751.11, 40.63, 281.3),
            nearby = vector4(96.72, 3751.71, 40.63, 0.0),
        } },
        { street = 'Nikola Pl', at = vector3(1401.20, -597.47, 74.39), points = {
            patient = vector4(1401.20, -597.47, 74.39, 163.2),
            nearby = vector4(1402.00, -596.87, 74.39, 0.0),
        } },
        { street = 'Forum Dr', at = vector3(-20.38, -1428.43, 30.66), points = {
            patient = vector4(-20.38, -1428.43, 30.66, 334.6),
            nearby = vector4(-19.58, -1427.83, 30.66, 0.0),
        } },
        { street = 'Amarillo Vista', at = vector3(1267.66, -1714.35, 54.66), points = {
            patient = vector4(1267.66, -1714.35, 54.66, 66.2),
            nearby = vector4(1268.46, -1713.75, 54.66, 0.0),
        } },
        { street = 'Paleto Blvd', at = vector3(-111.54, 6533.10, 29.81), points = {
            patient = vector4(-111.54, 6533.10, 29.81, 357.8),
            nearby = vector4(-110.74, 6533.70, 29.81, 0.0),
        } },
        -- Sandy Shores, rough (placed from memory): check them in game, move any that are off with /c3rplace ems_height
        { street = 'Panorama Dr', at = vector3(1717.50, 3295.60, 41.20), points = {
            patient = vector4(1717.50, 3295.60, 41.20, 105.0),
            nearby = vector4(1718.30, 3296.20, 41.20, 0.0),
        } },
        { street = 'Zancudo Ave', at = vector3(1975.60, 3818.80, 33.40), points = {
            patient = vector4(1975.60, 3818.80, 33.40, 120.0),
            nearby = vector4(1976.40, 3819.40, 33.40, 0.0),
        } },
    },
    stories = {
        legs = { weight = 2, conditions = { { 'fracture', 'lleg' }, { 'fracture', 'rleg' }, 'pain' },
            says = 'Landed on their feet. Neither leg is straight.', what = 'who fell from a roof', clue = { 'A ladder', 'prop_byard_ladder01', 'A ladder, fallen away from the wall.' }, },
        head = { weight = 2, conditions = { 'head', { 'hemorrhage', 'head' }, 'pain' },
            says = 'Landed on their head. Barely responding.', what = 'who fell and hit their head', clue = { 'A ladder', 'prop_byard_ladder01', 'A ladder, fallen away from the wall.' }, },
        tools = { weight = 1, conditions = { { 'hemorrhage', 'larm' }, { 'fracture', 'rleg' }, 'pain' },
            says = 'A broken leg, and their arm cut open by the saw they fell with.', what = 'who fell holding a saw', clue = { 'A toolbox', 'prop_tool_box_04', 'A toolbox, spilled out across the ground.' }, },
    },
}))
