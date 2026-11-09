--[[
    c3r medical call: ATV CRASH.

    Someone who came off a quad in the desert: thrown, rolled on, or cut open on the frame.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      thrown    Lying in the dirt, leg twisted, slow to answer.
      rolled    The quad rolled onto them. Every breath hurts.
      cut       A deep gash down their leg from the frame.

    Spots marked rough are from memory: check them in game and move them with /c3rplace ems_atv.
]]

Callout(Ems.call({
    id = 'ems_atv',
    name = 'ATV crash',
    voice = 'call_atv', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    trauma = true, -- (now and then a wrist or ankle broken too: felt on the head-to-toe check)
    age = { 16, 60 },
    reports = {
        'Caller says someone has crashed a quad bike out in the desert.',
        'ATV rollover, rider hurt. Caller flagged it down from the road.',
    },
    locations = {
        { street = 'Joshua Rd', at = vector3(276.34, 2837.48, 43.51), points = {
            patient = vector4(276.34, 2837.48, 43.51, 264.7),
            nearby = vector4(277.14, 2838.08, 43.51, 0.0),
        } },
        { street = 'Joshua Rd', at = vector3(225.36, 2883.13, 43.49), points = {
            patient = vector4(225.36, 2883.13, 43.49, 249.6),
            nearby = vector4(226.16, 2883.73, 43.49, 0.0),
        } },
        { street = 'Route 68', at = vector3(585.25, 2813.67, 41.79), points = {
            patient = vector4(585.25, 2813.67, 41.79, 22.6),
            nearby = vector4(586.05, 2814.27, 41.79, 0.0),
        } },
        { street = 'Panorama Dr', at = vector3(1664.21, 3581.10, 35.02), points = {
            patient = vector4(1664.21, 3581.10, 35.02, 32.7),
            nearby = vector4(1665.01, 3581.70, 35.02, 0.0),
        } },
    },
    stories = {
        thrown = { weight = 2, conditions = { { 'fracture', 'lleg' }, 'head', 'pain' },
            says = 'Lying in the dirt, leg twisted, slow to answer.', what = 'thrown from an ATV', clue = { 'A wheel', 'prop_rub_tyre_01', 'A wheel, torn off in the crash.' }, },
        rolled = { weight = 2, conditions = { 'respiratory', { 'fracture', 'rarm' }, 'pain' },
            says = 'The quad rolled onto them. Every breath hurts.', what = 'crushed under a rolled ATV', },
        cut = { weight = 1, conditions = { { 'hemorrhage', 'rleg' }, 'pain' },
            says = 'A deep gash down their leg from the frame.', what = 'cut open in an ATV crash', clue = { 'A fuel can', 'prop_jerrycan_01a', 'A fuel can, thrown off the rack.' }, },
    },
}))
