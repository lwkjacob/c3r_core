--[[
    c3r medical call: UNCONSCIOUS PERSON.

    Someone's found unconscious and a friend is with them, not saying much. Same report and card every time:
      heroin    an opioid overdose: pinpoint pupils, and the friend hid the needle.
      pills     they meant to: an empty bottle of painkillers and a note. Narcan helps, and they've breathed some in:
                crackles in the chest, oxygen. The friend didn't know.
      mixed     heroin and drink: the overdose, and vomit in the airway to suction.

    Points per location: walk them out in game with /c3rplace ems_overdose (it writes the location in below).
]]

local FRIEND_Q = {
    { id = 'c_what', label = 'What did they take?', stress = true, press = true },
    { id = 'c_long', label = 'How long have they been like this?' },
}

local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

local function people(c, conditions, what, clue)
    c:person('patient', { at = 'patient', label = 'Patient', secret = 'drugs', injured = true, age = { 19, 52 },
        vitals = 'Unresponsive. Barely breathing.', conditions = conditions })
    c:person('friend', { at = 'friend', label = 'Friend', secret = 'nervous', demeanor = 'nervous', age = { 19, 52 }, scene = 'WORLD_HUMAN_STAND_IMPATIENT',
        questions = FRIEND_Q, lines = { c_what = what, c_long = { 'I do not know. I found them like this.' } } })
    c:clue('nearby', { at = 'nearby', label = clue[1], prop = clue[2], text = clue[3] })
    Ems.card(c, 'patient')
    c:objective('friend', 'Find out what they took', { blip = 'friend' })
    c:on('contact', function(who) if who == 'friend' then c:done('friend') end end)
    c:on('dead', function(who) if who == 'friend' then c:done('friend') end end)
end

Callout({
    id = 'ems_overdose',
    service = 'ambulance',
    name = 'Unconscious person',
    priority = 1,
    voice = 'call_overdose', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    weight = 1,
    enabled = true,
    reports = {
        'Caller says their friend will not wake up.',
        'Unconscious person. The caller is with them and sounds scared.',
    },
    points = {
        { 'patient', 'The patient, on the ground.' },
        { 'friend', 'The friend, a few metres away.' },
        { 'nearby', 'What they took, on the ground near the patient.' },
    },
    -- Add more with /c3rplace ems_overdose in game (it writes them here). These are rough placeholders
    locations = {
        { street = 'Grove St', at = vector3(-71.81, -1782.74, 28.19), points = {
            patient = vector4(-71.81, -1782.74, 28.19, 155.7),
            friend = vector4(-69.00, -1785.00, 28.10, 60.0),
            nearby = vector4(-71.56, -1786.14, 28.03, 227.9),
        } },
        { street = 'Amarillo Vista', at = vector3(1278.85, -1746.58, 52.17), points = {
            patient = vector4(1278.85, -1746.58, 52.17, 317.7),
            friend = vector4(1281.60, -1746.02, 52.06, 69.3),
            nearby = vector4(1273.64, -1749.18, 52.11, 130.1),
        } },
        { street = 'Panorama Dr', at = vector3(1572.29, 3683.56, 34.78), points = {
            patient = vector4(1572.29, 3683.56, 34.78, 343.3),
            friend = vector4(1571.52, 3687.89, 34.73, 208.1),
            nearby = vector4(1569.58, 3681.14, 34.80, 53.7),
        } },
        { street = 'Great Ocean Hwy', at = vector3(160.58, 6357.87, 31.39), points = {
            patient = vector4(160.58, 6357.87, 31.39, 278.3),
            friend = vector4(160.98, 6353.38, 31.45, 30.9),
            nearby = vector4(164.30, 6359.02, 31.40, 144.0),
        } },
        -- Sandy Shores, rough (placed from memory): check them in game, move any that are off with /c3rplace ems_overdose
        { street = 'Zancudo Ave', at = vector3(1975.60, 3818.80, 33.40), points = {
            patient = vector4(1975.60, 3818.80, 33.40, 120.0),
            friend = vector4(1978.60, 3820.80, 33.40, 300.0),
            nearby = vector4(1976.40, 3819.40, 33.40, 0.0),
        } },
        { street = 'Alhambra Dr', at = vector3(1864.60, 3747.90, 33.03), points = {
            patient = vector4(1864.60, 3747.90, 33.03, 30.0),
            friend = vector4(1867.60, 3749.90, 33.03, 210.0),
            nearby = vector4(1865.40, 3748.50, 33.03, 0.0),
        } },
    },

    stories = {
        heroin = {
            weight = 3,
            setup = function(c)
                people(c, { 'opioid' },
                    cracks(2, { 'I do not know! They just passed out.' }, { { "...Heroin. Twenty minutes ago. I hid the needle.", set = { c_admit = 'yes' } } }, { 'I told you. Heroin.' }),
                    { 'A needle', 'p_syringe_01_s', 'A needle and a burnt spoon, kicked out of sight.' })
                Ems.wire(c, 'patient', function(how)
                    if how == 'hospital' then return ('%s overdosed on heroin, and was given Narcan and taken to hospital.'):format(c:name('patient')) end
                    if how == 'pronounced' then return ('%s overdosed on heroin and died at the scene.'):format(c:name('patient')) end
                    return 'The patient was gone before treatment finished.'
                end)
            end,
        },
        pills = {
            weight = 2,
            setup = function(c)
                people(c, { 'opioid', 'respiratory' },
                    { "Nothing! They don't take anything. I don't understand." },
                    { 'A pill bottle', 'prop_cs_pills', 'An empty bottle of strong painkillers, and a folded note with a name on it.' })
                Ems.wire(c, 'patient', function(how)
                    if how == 'hospital' then return ('%s took an overdose of pills on purpose, and was treated and taken to hospital.'):format(c:name('patient')) end
                    if how == 'pronounced' then return ('%s took an overdose of pills on purpose and died at the scene.'):format(c:name('patient')) end
                    return 'The patient was gone before treatment finished.'
                end)
            end,
        },
        mixed = {
            weight = 2,
            setup = function(c)
                people(c, { 'opioid', 'airway' },
                    cracks(2, { 'Just a few drinks, that is all.' }, { { "...And heroin. On top of the drink. I told them not to.", set = { c_admit = 'yes' } } }, { 'Drink and heroin. I said.' }),
                    { 'A bottle', 'prop_cs_beer_bot_01', 'An empty bottle, and a needle under it.' })
                Ems.wire(c, 'patient', function(how)
                    if how == 'hospital' then return ('%s overdosed on heroin and drink, and was treated and taken to hospital.'):format(c:name('patient')) end
                    if how == 'pronounced' then return ('%s overdosed on heroin and drink and died at the scene.'):format(c:name('patient')) end
                    return 'The patient was gone before treatment finished.'
                end)
            end,
        },
    },
})
