--[[
    c3r medical call: HEAT STROKE.

    Someone who has been out in the heat too long: dehydrated and muddled, maybe hurt in the fall, maybe diabetic too.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      heat      Red-faced and muddled, their skin hot and dry.
      fell      Collapsed in the heat, cut their head going down.
      sugar     Sweating through it, mumbling nonsense.

    Spots marked rough are from memory: check them in game and move them with /c3rplace ems_heat.
]]

Callout(Ems.call({
    id = 'ems_heat',
    name = 'Heat stroke',
    voice = 'call_heat', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    reports = {
        'Caller says someone has collapsed in the heat.',
        'Person confused and not making sense. They have been out in the sun all day.',
    },
    locations = {
        { street = 'Panorama Dr', at = vector3(1571.52, 3687.89, 34.73), points = {
            patient = vector4(1571.52, 3687.89, 34.73, 208.1),
            nearby = vector4(1572.32, 3688.49, 34.73, 0.0),
        } },
        { street = 'Route 68', at = vector3(618.21, 2786.29, 43.48), points = {
            patient = vector4(618.21, 2786.29, 43.48, 49.5),
            nearby = vector4(619.01, 2786.89, 43.48, 0.0),
        } },
        { street = 'Algonquin Blvd', at = vector3(1355.17, 3614.37, 34.87), points = {
            patient = vector4(1355.17, 3614.37, 34.87, 65.8),
            nearby = vector4(1355.97, 3614.97, 34.87, 0.0),
        } },
        -- rough (placed from memory): check in game, move with /c3rplace ems_heat
        { street = 'Panorama Dr', at = vector3(1717.50, 3295.60, 41.20), points = {
            patient = vector4(1717.50, 3295.60, 41.20, 105.0),
            nearby = vector4(1718.30, 3296.20, 41.20, 0.0),
        } },
        -- rough (placed from memory): check in game, move with /c3rplace ems_heat
        { street = 'Panorama Dr', at = vector3(1990.50, 3054.30, 47.20), points = {
            patient = vector4(1990.50, 3054.30, 47.20, 150.0),
            nearby = vector4(1991.30, 3054.90, 47.20, 0.0),
        } },
    },
    stories = {
        heat = { weight = 3, conditions = { 'dehydration' },
            says = 'Red-faced and muddled, their skin hot and dry.', what = 'with heat stroke', clue = { 'A water bottle', 'prop_ld_flow_bottle', 'A water bottle, empty.' }, },
        fell = { weight = 2, conditions = { 'dehydration', 'head', { 'hemorrhage', 'head' } },
            says = 'Collapsed in the heat, cut their head going down.', what = 'who collapsed from the heat and hit their head', },
        sugar = { weight = 1, conditions = { 'dehydration', 'hypoglycemia' },
            says = 'Sweating through it, mumbling nonsense.', what = 'a diabetic, dehydrated with low blood sugar', },
    },
}))
