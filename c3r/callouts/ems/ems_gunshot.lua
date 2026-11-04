--[[
    c3r medical call: GUNSHOT WOUND.

    Someone shot, the shooter long gone. In the chest, the leg (bone broken), or the stomach.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      chest     Fighting for breath, a hole in their chest.
      leg       Screaming, blood pumping from their thigh.
      belly     Pale and clammy, two holes in their stomach.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_gunshot (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_gunshot',
    name = 'Gunshot wound',
    voice = 'call_gunshot', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    age = { 16, 55 },
    reports = {
        'Caller says someone has been shot. Shots heard a few minutes ago.',
        'Person with a gunshot wound. Police say the area is clear.',
    },
    locations = {
        { street = 'Grove St', at = vector3(85.68, -1967.23, 20.75), points = {
            patient = vector4(85.68, -1967.23, 20.75, 313.8),
            nearby = vector4(86.48, -1966.63, 20.75, 0.0),
        } },
        { street = 'Amarillo Vista', at = vector3(1276.76, -1724.79, 54.66), points = {
            patient = vector4(1276.76, -1724.79, 54.66, 204.0),
            nearby = vector4(1277.56, -1724.19, 54.66, 0.0),
        } },
        { street = 'San Andreas Ave', at = vector3(382.56, -833.80, 29.29), points = {
            patient = vector4(382.56, -833.80, 29.29, 151.3),
            nearby = vector4(383.36, -833.20, 29.29, 0.0),
        } },
        { street = 'Grove St', at = vector3(-71.81, -1782.74, 28.19), points = {
            patient = vector4(-71.81, -1782.74, 28.19, 155.7),
            nearby = vector4(-71.01, -1782.14, 28.19, 0.0),
        } },
    },
    stories = {
        chest = { weight = 2, conditions = { { 'hemorrhage', 'thorax' }, 'pneumothorax', 'pain' },
            says = 'Fighting for breath, a hole in their chest.', what = 'shot in the chest', },
        leg = { weight = 2, conditions = { { 'hemorrhage', 'lleg' }, { 'fracture', 'lleg' }, 'pain' },
            says = 'Screaming, blood pumping from their thigh.', what = 'shot in the leg', },
        belly = { weight = 2, conditions = { { 'hemorrhage', 'abdomen' }, { 'hemorrhage', 'abdomen' }, 'pain' },
            says = 'Pale and clammy, two holes in their stomach.', what = 'shot twice in the stomach', },
    },
}))
