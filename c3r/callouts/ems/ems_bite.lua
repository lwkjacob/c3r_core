--[[
    c3r medical call: ANIMAL BITE.

    Someone bitten by a dog. A bleeding arm or leg; the dog has gone.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      arm       Their forearm torn open.
      leg       Deep bite wounds on the calf.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_bite (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_bite',
    name = 'Animal bite',
    voice = 'call_bite', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    reports = {
        'Caller says they have been bitten by a dog.',
        'Person bitten by a dog, bleeding badly. The dog has run off.',
    },
    locations = {
        { street = 'Paleto Blvd', at = vector3(-111.54, 6533.10, 29.81), points = {
            patient = vector4(-111.54, 6533.10, 29.81, 357.8),
            nearby = vector4(-110.74, 6533.70, 29.81, 0.0),
        } },
        { street = 'Calafia Rd', at = vector3(105.17, 3728.36, 40.00), points = {
            patient = vector4(105.17, 3728.36, 40.00, 91.1),
            nearby = vector4(105.97, 3728.96, 40.00, 0.0),
        } },
        { street = 'Joshua Rd', at = vector3(417.79, 2972.02, 40.97), points = {
            patient = vector4(417.79, 2972.02, 40.97, 105.7),
            nearby = vector4(418.59, 2972.62, 40.97, 0.0),
        } },
        { street = 'Grapeseed Avenue', at = vector3(1694.96, 4780.10, 42.00), points = {
            patient = vector4(1694.96, 4780.10, 42.00, 99.4),
            nearby = vector4(1695.76, 4780.70, 42.00, 0.0),
        } },
    },
    stories = {
        arm = { weight = 2, conditions = { { 'hemorrhage', 'rarm' }, 'pain' },
            says = 'Their forearm torn open.', what = 'bitten by a dog', },
        leg = { weight = 2, conditions = { { 'hemorrhage', 'lleg' }, 'pain' },
            says = 'Deep bite wounds on the calf.', what = 'bitten on the leg by a dog', },
    },
}))
