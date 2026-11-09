--[[
    c3r medical call: PERSON COLLAPSED.

    Someone's gone down in public and a bystander rang it in. Same report and card every time; the bystander only knows
    what they saw. What's really wrong is one of three stories, and the treatment screen shows it:
      heart     a heart attack: they say so when asked. No aspirin, and after a few minutes' warning it's VF.
      sugar     a diabetic with low blood sugar: barely awake. The glucometer, and the bracelet on their wrist.
      airway    choking on their lunch: look in their mouth, suction it. The half-eaten sandwich beside them.

    Points per location: walk them out in game with /c3rplace ems_collapse (it writes the location in below).
]]

local WITNESS_Q = {
    { id = 'c_what', label = 'What happened?', press = true },
    { id = 'c_know', label = 'Do you know them?' },
    { id = 'c_long', label = 'How long have they been down?' },
}

local function people(c, conditions, vitals, what, know, clue)
    c:person('patient', { at = 'patient', label = 'Patient', secret = 'clean', injured = true, age = { 28, 74 }, vitals = vitals, conditions = conditions })
    c:person('witness', { at = 'witness', label = 'Bystander', secret = 'clean', demeanor = 'chatty', scene = 'WORLD_HUMAN_STAND_MOBILE',
        questions = WITNESS_Q, lines = { c_what = what, c_know = know, c_long = { 'A few minutes. I called straight away.' } } })
    c:clue('nearby', { at = 'nearby', label = clue[1], prop = clue[2], text = clue[3] })
    Ems.card(c, 'patient')
    c:objective('witness', 'Ask the bystander what happened', { blip = 'witness' })
    c:on('contact', function(who) if who == 'witness' then c:done('witness') end end)
    c:on('dead', function(who) if who == 'witness' then c:done('witness') end end)
end

Callout({
    id = 'ems_collapse',
    service = 'ambulance',
    name = 'Person collapsed',
    priority = 1,
    voice = 'call_collapse', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    weight = 1,
    enabled = true,
    reports = {
        'Caller says someone has collapsed on the pavement and is not getting up.',
        'Person down in the street. A bystander is with them.',
    },
    points = {
        { 'patient', 'The patient, on the ground.' },
        { 'witness', 'The bystander who called, a few metres from them.' },
        { 'nearby', 'Something on the ground beside the patient.' },
    },
    -- Add more with /c3rplace ems_collapse in game (it writes them here). These are rough placeholders
    locations = {
        { street = 'Forum Dr', at = vector3(-37.12, -1452.05, 31.43), points = {
            patient = vector4(-37.12, -1452.05, 31.43, 90.0),
            witness = vector4(-34.12, -1450.05, 31.43, 120.0),
            nearby = vector4(-38.12, -1453.05, 31.43, 0.0),
        } },
        { street = 'Nikola Pl', at = vector3(1388.49, -569.63, 74.50), points = {
            patient = vector4(1388.49, -569.63, 74.50, 90.0),
            witness = vector4(1391.49, -567.63, 74.50, 120.0),
            nearby = vector4(1387.49, -570.63, 74.50, 0.0),
        } },
        { street = 'Joshua Rd', at = vector3(421.79, 2992.90, 40.62), points = {
            patient = vector4(421.79, 2992.90, 40.62, 90.0),
            witness = vector4(424.79, 2994.90, 40.62, 120.0),
            nearby = vector4(420.79, 2991.90, 40.62, 0.0),
        } },
        { street = 'Paleto Blvd', at = vector3(-0.10, 6519.90, 31.48), points = {
            patient = vector4(-0.10, 6519.90, 31.48, 31.8),
            witness = vector4(6.01, 6511.58, 31.88, 97.7),
            nearby = vector4(0.70, 6520.50, 31.48, 0.0),
        } },
        -- Sandy Shores, rough (placed from memory): check them in game, move any that are off with /c3rplace ems_collapse
        { street = 'Alhambra Dr', at = vector3(1853.00, 3689.50, 34.27), points = {
            patient = vector4(1853.00, 3689.50, 34.27, 210.0),
            witness = vector4(1856.00, 3691.50, 34.27, 30.0),
            nearby = vector4(1853.80, 3690.10, 34.27, 0.0),
        } },
        { street = 'Alhambra Dr', at = vector3(1961.50, 3740.50, 32.34), points = {
            patient = vector4(1961.50, 3740.50, 32.34, 300.0),
            witness = vector4(1964.50, 3742.50, 32.34, 120.0),
            nearby = vector4(1962.30, 3741.10, 32.34, 0.0),
        } },
    },

    stories = {
        heart = {
            weight = 3,
            setup = function(c)
                people(c, { 'cardiac' }, 'Grey and sweating, one hand on their chest.',
                    { 'They stopped, grabbed their chest and went down.' }, { "No. I just saw them fall." },
                    { 'Their bag', 'prop_ld_handbag', 'A work bag, spilled open. A box of heart tablets, nearly full.' })
                Ems.wire(c, 'patient', function(how)
                    if how == 'hospital' then return ('%s, a suspected heart attack, was treated and taken to hospital.'):format(c:name('patient')) end
                    if how == 'pronounced' then return ('%s, a suspected heart attack, died at the scene.'):format(c:name('patient')) end
                    return 'The patient was gone before treatment finished.'
                end)
            end,
        },
        sugar = {
            weight = 2,
            setup = function(c)
                people(c, { 'hypoglycemia' }, 'Confused, slurring, drenched in sweat.',
                    { "They were talking nonsense, then they just sat down and went over. I thought they were drunk." },
                    { "No. They were swaying about before it happened." },
                    { 'A bracelet', 'h4_prop_h4_bracelet_01a', 'A medical bracelet, come off in the fall. Type 1 diabetic.' })
                Ems.wire(c, 'patient', function(how)
                    if how == 'hospital' then return ('%s, a diabetic with low blood sugar, was treated and taken to hospital.'):format(c:name('patient')) end
                    if how == 'pronounced' then return ('%s, a diabetic with low blood sugar, died at the scene.'):format(c:name('patient')) end
                    return 'The patient was gone before treatment finished.'
                end)
            end,
        },
        airway = {
            weight = 2,
            setup = function(c)
                people(c, { 'airway' }, 'Blue around the lips, hands at their throat.',
                    { 'They were eating, then they went red and started grabbing at their neck.' },
                    { "A bit. They work round the corner." },
                    { 'Their lunch', 'prop_sandwich_01', 'A half-eaten sandwich, dropped where they stood.' })
                Ems.wire(c, 'patient', function(how)
                    if how == 'hospital' then return ('%s choked, had their airway cleared and was taken to hospital.'):format(c:name('patient')) end
                    if how == 'pronounced' then return ('%s choked and died at the scene.'):format(c:name('patient')) end
                    return 'The patient was gone before treatment finished.'
                end)
            end,
        },
    },
})
