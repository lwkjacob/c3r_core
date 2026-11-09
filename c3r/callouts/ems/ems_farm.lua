--[[
    c3r medical call: FARM ACCIDENT.

    Someone hurt working the land: a leg crushed, an arm caught in machinery, or kicked by a horse.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      crushed   Their leg was caught under the machine.
      arm       Their arm was caught in the machinery, and it is bleeding badly.
      kicked    Kicked by a horse. Dazed, one arm hanging.

    Spots marked rough are from memory: check them in game and move them with /c3rplace ems_farm.
]]

Callout(Ems.call({
    id = 'ems_farm',
    name = 'Farm accident',
    voice = 'call_farm', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    trauma = true, -- (now and then a wrist or ankle broken too: felt on the head-to-toe check)
    age = { 18, 75 },
    reports = {
        'Caller says a farm worker has been hurt by the machinery.',
        'Injury on a farm. The caller says it looks bad.',
    },
    locations = {
        { street = 'Grapeseed Avenue', at = vector3(1690.38, 4758.41, 41.92), points = {
            patient = vector4(1690.38, 4758.41, 41.92, 46.0),
            nearby = vector4(1691.18, 4759.01, 41.92, 0.0),
        } },
        { street = 'Grapeseed Main St', at = vector3(1709.72, 4921.22, 42.08), points = {
            patient = vector4(1709.72, 4921.22, 42.08, 255.6),
            nearby = vector4(1710.52, 4921.82, 42.08, 0.0),
        } },
        { street = 'Joshua Rd', at = vector3(417.79, 2972.02, 40.97), points = {
            patient = vector4(417.79, 2972.02, 40.97, 105.7),
            nearby = vector4(418.59, 2972.62, 40.97, 0.0),
        } },
        -- rough (placed from memory): check in game, move with /c3rplace ems_farm
        { street = 'Grapeseed Main St', at = vector3(2442.00, 4974.00, 46.80), points = {
            patient = vector4(2442.00, 4974.00, 46.80, 45.0),
            nearby = vector4(2442.80, 4974.60, 46.80, 0.0),
        } },
        -- rough (placed from memory): check in game, move with /c3rplace ems_farm
        { street = 'Grapeseed Main St', at = vector3(2016.00, 4987.00, 41.20), points = {
            patient = vector4(2016.00, 4987.00, 41.20, 315.0),
            nearby = vector4(2016.80, 4987.60, 41.20, 0.0),
        } },
    },
    stories = {
        crushed = { weight = 2, conditions = { { 'fracture', 'lleg' }, { 'hemorrhage', 'lleg' }, 'pain' },
            says = 'Their leg was caught under the machine.', what = 'with a leg crushed by farm machinery', clue = { 'Hay bales', 'prop_haybale_01', 'Hay bales, tipped off the trailer.' }, },
        arm = { weight = 2, conditions = { { 'hemorrhage', 'rarm' }, 'pain' },
            says = 'Their arm was caught in the machinery, and it is bleeding badly.', what = 'with an arm torn in farm machinery', clue = { 'A toolbox', 'prop_tool_box_04', 'A toolbox, dropped open in the dirt.' }, },
        kicked = { weight = 1, conditions = { 'head', { 'fracture', 'rarm' }, 'pain' },
            says = 'Kicked by a horse. Dazed, one arm hanging.', what = 'kicked by a horse', },
    },
}))
