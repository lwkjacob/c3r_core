--[[
    c3r medical call: EXPLOSION REPORTED.

    A gas explosion at a trailer or house: burns and smoke, metal through them, or thrown by the blast.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      smoke     Singed and coughing, their voice hoarse.
      shrapnel  Peppered with metal, bleeding from their belly and leg.
      thrown    Thrown by the blast. A wound in their chest, fighting for breath.

    Spots marked rough are from memory: check them in game and move them with /c3rplace ems_blast.
]]

Callout(Ems.call({
    id = 'ems_blast',
    name = 'Explosion reported',
    voice = 'call_blast', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    trauma = true, -- (now and then a wrist or ankle broken too: felt on the head-to-toe check)
    age = { 18, 60 },
    reports = {
        'Caller heard a bang and saw smoke. Someone is hurt.',
        'Explosion at a property. One person down outside.',
    },
    locations = {
        -- rough (placed from memory): check in game, move with /c3rplace ems_blast
        { street = 'Zancudo Ave', at = vector3(1975.60, 3818.80, 33.40), points = {
            patient = vector4(1975.60, 3818.80, 33.40, 120.0),
            nearby = vector4(1976.40, 3819.40, 33.40, 0.0),
        } },
        { street = 'Panorama Dr', at = vector3(1572.29, 3683.56, 34.78), points = {
            patient = vector4(1572.29, 3683.56, 34.78, 343.3),
            nearby = vector4(1573.09, 3684.16, 34.78, 0.0),
        } },
        { street = 'Joshua Rd', at = vector3(412.09, 2966.05, 41.89), points = {
            patient = vector4(412.09, 2966.05, 41.89, 352.7),
            nearby = vector4(412.89, 2966.65, 41.89, 0.0),
        } },
        { street = 'Senora Fwy', at = vector3(2634.11, 3291.89, 55.73), points = {
            patient = vector4(2634.11, 3291.89, 55.73, 174.3),
            nearby = vector4(2634.91, 3292.49, 55.73, 0.0),
        } },
    },
    stories = {
        smoke = { weight = 2, conditions = { 'respiratory', 'pain' },
            says = 'Singed and coughing, their voice hoarse.', what = 'hurt in an explosion: burns and smoke', clue = { 'A gas cylinder', 'prop_gascyl_01a', 'A gas cylinder, blown open.' }, },
        shrapnel = { weight = 2, conditions = { { 'hemorrhage', 'abdomen' }, { 'hemorrhage', 'lleg' }, 'pain' },
            says = 'Peppered with metal, bleeding from their belly and leg.', what = 'hit by debris in an explosion', clue = { 'A gas tank', 'prop_gas_tank_01a', 'A gas tank, torn apart.' }, },
        thrown = { weight = 1, conditions = { 'head', { 'fracture', 'larm' }, { 'hemorrhage', 'thorax' }, 'pneumothorax', 'pain' },
            says = 'Thrown by the blast. A wound in their chest, fighting for breath.', what = 'thrown by an explosion', },
    },
}))
