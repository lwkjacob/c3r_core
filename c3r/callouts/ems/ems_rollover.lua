--[[
    c3r medical call: SINGLE VEHICLE COLLISION.

    A driver who came off the road, out of the car now. A head and chest hit on the wheel, or a broken leg and a bleed.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      chest     Short of breath, the steering wheel marked on their chest.
      leg       Dragged themselves out. Their leg is badly broken.
      drunk     Stinks of drink, a cut forehead, confused.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_rollover (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_rollover',
    name = 'Single vehicle collision',
    voice = 'call_rollover', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    age = { 17, 70 },
    reports = {
        'Caller says a car has come off the road. The driver is out and hurt.',
        'Single vehicle crash. Driver lying beside the road.',
    },
    locations = {
        { street = 'Senora Fwy', at = vector3(1599.62, 6416.18, 26.10), points = {
            patient = vector4(1599.62, 6416.18, 26.10, 213.4),
            nearby = vector4(1600.42, 6416.78, 26.10, 0.0),
        } },
        { street = 'Senora Fwy', at = vector3(2938.15, 3770.10, 52.65), points = {
            patient = vector4(2938.15, 3770.10, 52.65, 119.2),
            nearby = vector4(2938.95, 3770.70, 52.65, 0.0),
        } },
        { street = 'Route 68', at = vector3(537.47, 2657.87, 42.38), points = {
            patient = vector4(537.47, 2657.87, 42.38, 87.8),
            nearby = vector4(538.27, 2658.47, 42.38, 0.0),
        } },
        { street = 'Panorama Dr', at = vector3(1665.78, 3576.97, 35.42), points = {
            patient = vector4(1665.78, 3576.97, 35.42, 195.7),
            nearby = vector4(1666.58, 3577.57, 35.42, 0.0),
        } },
    },
    stories = {
        chest = { weight = 2, conditions = { 'head', { 'hemorrhage', 'thorax' }, 'pneumothorax', 'pain' },
            says = 'Short of breath, the steering wheel marked on their chest.', what = 'hurt in a crash, chest and head', },
        leg = { weight = 2, conditions = { { 'fracture', 'rleg' }, { 'hemorrhage', 'rleg' }, 'pain' },
            says = 'Dragged themselves out. Their leg is badly broken.', what = 'hurt in a crash, leg broken', },
        drunk = { weight = 1, secret = 'drunk', conditions = { 'head', { 'hemorrhage', 'head' }, 'pain' },
            says = 'Stinks of drink, a cut forehead, confused.', what = 'drunk, hurt in a crash', clue = { 'A bottle', 'prop_cs_beer_bot_01', 'A bottle, thrown from the car.' }, },
    },
}))
