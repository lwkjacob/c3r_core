-- c3r config: the Discord activity, what a player's Discord profile shows while they play.
-- Make an application at discord.com/developers/applications (its name is the title on the card), upload the images
-- under Rich Presence -> Art Assets, and paste its Application ID below. With no id, nothing here runs and players
-- keep FiveM's own activity. Filling in the id takes a restart of c3r.
--
-- In any text: {unit} callsign, {call} the callout's name, {players} {max} {duty} the server's counts, and this
-- shift's {stops} {contacts} {citations} {warnings} {arrests} {pursuits_won} {pursuits_lost} {callouts} {assists}.

Config.Presence = {
    appId = '1566648538606076056',                                      -- the Application ID, in quotes
    large = 'logo',                                    -- the big image: its name in Art Assets
    largeText = 'CODE3RESPONSE BY LWK DEVELOPMENT',    -- hovering over the big image
    line = 'Players {players}/{max} · {duty} on duty', -- the line under the state's text ('' for none)
    hover = 'This shift: {stops} stops · {arrests} arrests · {callouts} calls', -- hovering over the small image
    noCallsign = 'Officer',                            -- {unit} when they have no callsign yet

    -- Two buttons at most. url starts https:// or fivem://connect/ (else that button isn't shown), label up to 32
    -- characters. A player can't see the buttons on their own profile, only on someone else's.
    join = { label = 'Join Server', url = '' },        -- e.g. https://cfx.re/join/abc123
    website = { label = 'Main Website', url = 'https://c3r.network' },

    -- What the player is doing. icon = the small image's name in Art Assets.
    states = {
        off = { text = 'Off duty', icon = 'off_duty', hover = 'Off duty' },
        patrol = { text = '{unit} · On patrol', icon = 'patrol' },
        stop = { text = '{unit} · Traffic stop', icon = 'traffic_stop' },
        felony = { text = '{unit} · Felony stop', icon = 'traffic_stop' },
        contact = { text = '{unit} · Out of the car', icon = 'patrol' }, -- talking to someone on foot, a parked car
        pursuit = { text = '{unit} · In pursuit', icon = 'pursuit' },
        chase = { text = '{unit} · Foot chase', icon = 'pursuit' },
        callout = { text = '{unit} · Responding: {call}', icon = 'callout' },
        scene = { text = '{unit} · On scene: {call}', icon = 'callout' },
    },
}

-- A medic's shift (on duty as Ambulance): on shift, and on the way to hospital with a patient. On a call, the call's own
-- states above. {patients}: handed over at hospital this shift.
Config.Presence.states.ems = { text = '{unit} · Ambulance on shift', icon = 'patrol', hover = 'This shift: {patients} patients · {callouts} calls' }
Config.Presence.states.transport = { text = '{unit} · Transporting to hospital', icon = 'callout', hover = 'This shift: {patients} patients · {callouts} calls' }
Config.Presence.noCallsignMedic = 'Paramedic' -- {unit} for a medic with no callsign yet
