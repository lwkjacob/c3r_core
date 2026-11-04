--[[
    c3r medical call: CYCLIST DOWN.

    A cyclist who came off: hit their head, broke a collarbone or arm, or took the skin off a leg.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      head      Helmet cracked, slow to answer.
      arm       Holding their arm tight to their side.
      leg       A long, deep gash down their leg.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_cyclist (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_cyclist',
    name = 'Cyclist down',
    voice = 'call_cyclist', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    reports = {
        'Caller says a cyclist has come off their bike and is not getting up.',
        'Cyclist down at the side of the road.',
    },
    locations = {
        { street = 'Panorama Dr', at = vector3(1697.99, 3523.87, 36.19), points = {
            patient = vector4(1697.99, 3523.87, 36.19, 158.9),
            nearby = vector4(1698.79, 3524.47, 36.19, 0.0),
        } },
        { street = 'Great Ocean Hwy', at = vector3(1065.69, 6500.54, 21.04), points = {
            patient = vector4(1065.69, 6500.54, 21.04, 221.7),
            nearby = vector4(1066.49, 6501.14, 21.04, 0.0),
        } },
        { street = 'Mirror Park', at = vector3(1087.52, -484.08, 65.17), points = {
            patient = vector4(1087.52, -484.08, 65.17, 90.1),
            nearby = vector4(1088.32, -483.48, 65.17, 0.0),
        } },
        { street = 'Vinewood Boulevard', at = vector3(232.81, 210.23, 105.43), points = {
            patient = vector4(232.81, 210.23, 105.43, 159.1),
            nearby = vector4(233.61, 210.83, 105.43, 0.0),
        } },
    },
    stories = {
        head = { weight = 2, conditions = { 'head', { 'hemorrhage', 'head' }, 'pain' },
            says = 'Helmet cracked, slow to answer.', what = 'a cyclist who hit their head', },
        arm = { weight = 2, conditions = { { 'fracture', 'larm' }, 'pain' },
            says = 'Holding their arm tight to their side.', what = 'a cyclist with a broken arm', },
        leg = { weight = 1, conditions = { { 'hemorrhage', 'rleg' }, 'pain' },
            says = 'A long, deep gash down their leg.', what = 'a cyclist with a bad cut to the leg', },
    },
}))
