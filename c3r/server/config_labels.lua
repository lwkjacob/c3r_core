--[[
    c3r — server: what /c3rconfig calls things. The tabs, the sections and every row, in the order they're shown; the
    values and the comments stay in config/. Each row names a path in Config, its label and how to show it:
        * in a path        any one key or list index; {name} in the text is names[that key], {n} the last index
        help = '...'       the line under it
        unit = 's'         m, s, min, ms, mph, pct, or any word. min, ms, mph and pct are shown converted (0.35 as 35%)
                           but the file keeps its own form
        as = 'key'         press the key; 'pos' x, y, z with Set here; 'range' two numbers; 'rgb' three numbers
        opts = { { value, text } }  a choice
        blank = '...'      may be left empty (a nil in the file): what that means. Without it a text can't be empty
        neg = true         may be negative
        adv = true         only under Advanced settings (on a section: all of it)
        add = '...'        the list's add button (on its last row)
    A value with no row here ends up on an Other tab, by its path (and the self-check fails on any in the shipped config).
]]

local TRUTH = {
    clean = 'Nothing to hide', nervous = 'Just nervous', unlicensed = 'No licence', suspended = 'Suspended licence',
    expired = 'Expired papers', drunk = 'Drunk', drugs = 'Carrying drugs', warrant = 'Wanted on a warrant', stolen = 'Stolen car',
}

local UNIT = {
    police = 'Prisoner transport', ambulance = 'Ambulance', fire = 'Fire engine', coroner = 'Coroner', mechanic = 'Mechanic',
    roadservice = 'Road service', animalrescue = 'Animal rescue', taxi = 'Taxi', cover = 'Cover unit', pursuit = 'Pursuit',
    air = 'Air support', dot = 'Road crew',
}

local STATE = {
    off = 'Off duty', patrol = 'On patrol', stop = 'Traffic stop', felony = 'Felony stop', contact = 'On foot with someone',
    pursuit = 'Car chase', chase = 'Foot chase', callout = 'Responding to a call', scene = 'On scene at a call',
    ems = 'Ambulance on shift', transport = 'Taking a patient to hospital',
}

local MODEL = 'A model name, from docs.fivem.net/docs/game-references.'

ConfigMenu = {
    fixed = { ['Ems.tools'] = true, ['Ems.grade'] = true }, -- lists with no add or remove: the game looks for these by name or place

    { name = 'General', sections = {
        { title = 'Going on duty', rows = {
            { 'DutyCommand', 'Duty command', help = 'What players type in chat, without the slash. Takes a restart of c3r.' },
            { 'DutyAce', 'Police permission', blank = 'Anyone can go on duty', help = 'To limit police to a group, enter a name such as c3r.police, then add this to server.cfg: add_ace group.police c3r.police allow' },
        } },
        { title = 'Keys', help = 'Click a key, then press the new one. Takes a restart of c3r, and only reaches players who have not saved that key yet: anyone else rebinds it in Settings > Key Bindings > FiveM > c3r.', rows = {
            { 'DutyKey', 'Service screen', as = 'key', help = 'Pick a service to go on duty, or end the shift.' },
            { 'TargetKey', 'Pick a car to stop', as = 'key', help = 'In a police vehicle: shows the red circle ahead. Drive it under a car to pick it.' },
            { 'ModeKey', 'What the driver does', as = 'key', help = 'During a stop: follow in front or behind, steer, halt, cancel.' },
            { 'InteractKey', 'Talk', as = 'key', help = 'On foot, beside a car or a person.' },
            { 'RadialKey', 'Radial menu and dispatch wheel', as = 'key', help = 'Held. At a car: search, tow, everyone out or in. Anywhere else: the dispatch wheel.' },
            { 'RespondKey', 'Respond to a callout', as = 'key' },
            { 'LeaveCallKey', 'Decline or leave a callout', as = 'key', help = 'Leaving a call asks first.' },
            { 'ObjectiveKey', 'Hide or show the objective', as = 'key', help = 'On a callout.' },
            { 'IdCardKey', 'Hide or show an ID', as = 'key', help = "While someone's ID or registration is showing. May share a key with the objective: the ID goes first." },
        } },
        { title = "The officer's voice", help = 'Lines spoken out loud: asking for ID, the Miranda rights, a search, the breathalyzer.', rows = {
            { 'Voice.range', 'Heard up to', unit = 'm', help = 'By any player, quieter further off.' },
            { 'Voice.volume', 'Volume', unit = 'pct', help = '0 turns the lines off.' },
        } },
        { title = 'For developers', adv = true, rows = {
            { 'Debug', 'Debug mode', help = 'Extra output for testing. Leave it off on a live server.' },
        } },
    } },

    { name = 'Traffic stops', sections = {
        { title = 'How drivers pull over', rows = {
            { 'Pullover.default', 'When you turn on the lights', opts = { { 'front', 'They drive ahead and stop when you stop' }, { 'kerb', 'They pull over by themselves' } } },
            { 'CancelDistance', 'Cancel the stop after driving', unit = 'm', help = 'How far you can drive from a stop before it ends.' },
            { 'Pullover.speed', 'Speed while pulling over', unit = 'mph', adv = true },
            { 'Pullover.ahead', 'Stopping point ahead', unit = 'm', adv = true, help = 'Where they aim to stop, ahead of where they were.' },
            { 'Pullover.kerb_gap', 'Gap to the kerb', unit = 'm', adv = true, help = "Between the car's right side and the kerb. GTA's driving differs per road: adjust these if drivers stop too far out, too short or in the lane." },
            { 'Pullover.kerb_inset', 'Roads with no kerb: stop this far in', unit = 'm', adv = true, help = "From GTA's road edge." },
            { 'Pullover.straighten', 'Final glide', unit = 'm', adv = true, help = 'The slow run along the kerb onto the final spot.' },
            { 'Pullover.glide', 'Distance from the kerb before the glide', unit = 'm', adv = true, help = 'Stops nose-in parking.' },
            { 'Pullover.timeout_ms', 'Give up and just stop after', unit = 'ms', adv = true },
            { 'Pullover.driving_style', 'Driving flags', adv = true, help = "GTA's driving style number. Only change it if you know the flags: it's explained in config/stops.lua." },
            { 'Pullover.bend_style', 'Driving flags on a bend', adv = true, help = "GTA's driving style number. Leave it unless you know the flags." },
        } },
        { title = 'Following and steering', help = 'What the mode key makes the driver do.', rows = {
            { 'Modes.speed', 'Top speed while following', unit = 'mph' },
            { 'Modes.gap', 'Gap to your car', unit = 'm', help = 'More for anything longer than a car.' },
            { 'Modes.steer_speed', 'Top speed while you steer them', unit = 'mph', help = 'With the arrow keys.' },
        } },
        { title = 'Picking the car', rows = {
            { 'Target.distance', 'Circle ahead of the patrol car', unit = 'm', help = 'Where the red circle sits.' },
            { 'Target.radius', 'Picks a car within', unit = 'm', adv = true, help = "Of the circle, measured to the car's centre." },
            { 'Target.lose_distance', 'Lets go of the car at', unit = 'm', adv = true, help = 'If the picked car gets this far away.' },
            { 'Target.color', 'Circle colour', as = 'rgb', adv = true, help = 'Red, green, blue: 0 to 255 each.' },
        } },
        { title = 'Who runs', help = 'The chance each kind of driver runs. Anyone not listed never does.', rows = {
            { 'Flee.car.*', 'Drives off: {name}', names = TRUTH, unit = 'pct', help = 'Instead of pulling over.' },
            { 'Flee.foot.*', 'Runs on foot: {name}', names = TRUTH, unit = 'pct', help = 'When ordered out, or when you go to cuff them.' },
            { 'Flee.bail', 'Bails out after a car chase', unit = 'pct', help = 'A chase that ends: they run for it on foot instead of giving up.' },
            { 'Flee.gun', 'Shoots and drives off', unit = 'pct', help = 'With a warrant, a stolen car or drugs: as you walk up.' },
            { 'Flee.refuse', 'Refuses to get out', unit = 'pct', help = 'Rude, or with something to hide: refuses the first order.' },
            { 'Flee.lose_distance', 'Gets away at', unit = 'm', help = 'Further than this for 10 seconds.' },
            { 'Flee.catch_distance', 'Gives up on foot at', unit = 'm', adv = true },
        } },
        { title = 'Felony stops', help = 'G at a stopped car, or "felony stop" on the PA: each person is ordered out, walked back and put on their knees.', rows = {
            { 'Felony.freeze', "Doesn't move at first", unit = 'pct', help = 'Asked again, they do.' },
            { 'Felony.run.*', 'Bolts on foot: {name}', names = TRUTH, unit = 'pct', help = 'Once, instead of coming out.' },
            { 'Felony.drive.*', 'Driver floors it: {name}', names = TRUTH, unit = 'pct', help = 'When the felony stop starts.' },
        } },
        { title = 'At the roadside', rows = {
            { 'Tests.bac_limit', 'Breathalyzer limit', unit = 'BAC', help = 'At or over this shows as over the limit.' },
            { 'PaRange', 'PA and shouted orders reach', unit = 'm', help = 'Talking to someone still needs you beside them.' },
        } },
    } },

    { name = 'People', sections = {
        { title = 'Drivers', help = 'How often each comes up, compared to the others. Bigger means more often, 0 turns it off.', rows = {
            { 'Secrets.*', '{name}', names = TRUTH, unit = 'share' },
        } },
        { title = 'Passengers', help = 'The same for passengers, who have no licence or papers to hide.', rows = {
            { 'PassengerSecrets.*', '{name}', names = TRUTH, unit = 'share' },
        } },
        { title = 'Mood', help = 'How they act with you. Bigger means more often.', rows = {
            { 'Demeanors.polite', 'Polite', unit = 'share' },
            { 'Demeanors.nervous', 'Nervous', unit = 'share' },
            { 'Demeanors.rude', 'Rude', unit = 'share' },
            { 'Demeanors.chatty', 'Chatty', unit = 'share' },
        } },
        { title = 'Records and repeat faces', rows = {
            { 'FlagChance', 'Has a record flag', unit = 'pct', help = 'PROBATION, GANG AFFILIATION and so on.' },
            { 'BorrowedChance', 'The car belongs to a relative', unit = 'pct' },
            { 'AlprChance', 'ALPR picks up a flagged car', unit = 'pct', help = 'Of the stolen or expired cars that drive past. At 0 it only reads cars already on file.' },
            { 'OwnerDrivesChance', 'A car stopped before has its owner driving again', unit = 'pct', adv = true },
            { 'RepeatChance', 'Someone who looks familiar really is', unit = 'pct', adv = true, help = 'Same ped model as a person met before.' },
            { 'RepeatSameSecret', 'Someone met again hides the same thing', unit = 'pct', adv = true },
        } },
    } },

    { name = 'Patrol', sections = {
        { title = 'Staged violators', help = 'On duty in your car, every so often a car near you starts driving to match its hidden story. No marker: you have to spot it.', rows = {
            { 'Staged.enabled', 'Turn on' },
            { 'Staged.every', 'Time between them', as = 'range', unit = 'min' },
            { 'Staged.lasts', 'Keeps it up for', unit = 's', help = 'Pull it over before then.' },
            { 'Staged.fault', 'A car fault instead', unit = 'pct', help = 'A light out, a stuck blinker, a flat tyre.' },
            { 'Staged.secrets.*', 'How often: {name}', names = TRUTH, unit = 'share', adv = true, help = 'Bigger means more often. A car already on file keeps its own story.' },
        } },
        { title = 'Booking stations', help = 'Arrested people are booked when you stop in the blue circle at any of these. It shows while you have someone in custody.', rows = {
            { 'BookingRadius', 'Circle size', unit = 'm' },
            { 'Stations[*].name', 'Station' },
            { 'Stations[*]', 'Position', as = 'pos', neg = true, add = 'Add a station' },
        } },
    } },

    { name = 'Callouts', sections = {
        { title = 'How often', rows = {
            { 'Callouts.enabled', 'Turn on' },
            { 'Callouts.every', 'Time between calls', as = 'range', unit = 'min', help = 'While anyone is on duty.' },
            { 'Callouts.max_open', 'Calls open at once' },
            { 'Callouts.recent', 'Before the same call comes up again', unit = 'min', help = 'A unit gets other calls first, or at least another version of it.' },
        } },
        { title = 'Where', rows = {
            { 'Callouts.min_distance', 'Closest to the officer', unit = 'm' },
            { 'Callouts.max_distance', 'Furthest from the officer', unit = 'm' },
            { 'Callouts.arrive', 'Counts as on scene at', unit = 'm', adv = true },
            { 'Callouts.build', 'Scene is built at', unit = 'm', adv = true, help = 'Each person, car and prop appears when a unit gets this close to it.' },
        } },
        { title = 'Timing out', rows = {
            { 'Callouts.offer_window', 'Offer card stays up', unit = 's' },
            { 'Callouts.expire', 'A call nobody takes closes after', unit = 's', help = 'This includes the time the offer card is up.' },
            { 'Callouts.max_minutes', 'A call still open is cancelled after', unit = 'minutes' },
        } },
    } },

    { name = 'Backup', sections = {
        { title = 'Vehicles', help = MODEL .. ' One unit of each kind at a time.', rows = {
            { 'Backup.units.*.car', '{name}', names = UNIT },
            { 'Backup.units.pursuit.cars[*]', 'Pursuit car {n}', add = 'Add a pursuit car' },
            { 'Tow.truck', 'Tow truck' },
        } },
        { title = 'Getting there', rows = {
            { 'Backup.speed', 'Speed on lights and siren', unit = 'mph', help = 'Others drive at about 34 mph.' },
            { 'Backup.timeout', 'Time to get there', unit = 's', help = 'Stuck in traffic, it turns up anyway.' },
            { 'Backup.job_timeout', 'Time for the work at the scene', unit = 's', help = 'Before they pack up.' },
            { 'Backup.arrive', 'Counts as there within', unit = 'm', help = 'Of where it parks, or of you: they stop instead of circling the block.' },
            { 'Backup.fire_gap', 'Fire engine stops this far from the fire', unit = 'm', help = 'And no nearer.' },
            { 'Backup.cover_minutes', 'A cover unit stands by for', unit = 'minutes', help = 'At most.' },
            { 'Backup.spawn', 'Appears this far from the scene', as = 'range', unit = 'm', adv = true, help = 'Out of your sight.' },
        } },
        { title = 'Pursuit', help = 'Cars sent per request.', rows = {
            { 'Backup.pursuit.light', 'Light request', unit = 'cars' },
            { 'Backup.pursuit.medium', 'Medium request', unit = 'cars' },
            { 'Backup.pursuit.heavy', 'Heavy request', unit = 'cars' },
            { 'Backup.pursuit.max', 'Most in a chase', unit = 'cars' },
            { 'Backup.spikes', 'First car lays a Stop Stick', unit = 'pct', help = 'In a car chase. Needs lwk_stopstick.' },
        } },
        { title = 'Tow truck', rows = {
            { 'Tow.distance', 'Comes from', unit = 'm', help = 'Up the road, behind the car.' },
            { 'Tow.timeout_ms', 'Time to get there', unit = 'ms', help = 'Stuck in traffic, it turns up anyway.' },
            { 'Tow.tries', 'Failed tows before the car is removed' },
            { 'Tow.driver', 'Driver', adv = true, help = MODEL },
        } },
        { title = 'Crews', adv = true, help = MODEL, rows = {
            { 'Backup.units.*.crew[*]', '{name}: crew {n}', names = UNIT, add = 'Add to the {name} crew' },
        } },
        { title = 'Lights', adv = true, rows = {
            { 'Backup.units.*.lights', '{name}: lights on', names = UNIT },
            { 'Backup.units.*.muted', '{name}: no siren', names = UNIT },
        } },
    } },

    { name = 'Ambulance', sections = {
        { title = 'The shift', rows = {
            { 'Ems.ace', 'Ambulance permission', blank = 'Anyone can go on duty', help = 'To limit it to a group, enter a name such as c3r.ambulance, then grant it in server.cfg with add_ace.' },
            { 'Ems.bring_vehicle', 'Bring a vehicle on shift', help = 'Off: whatever they drive is their ambulance.' },
            { 'Ems.vehicle', 'Vehicle', help = MODEL },
            { 'Ems.uniform', 'Put players in uniform', help = 'Turn off on a server with its own clothing script.' },
            { 'Ems.ped', 'Uniform model', adv = true, help = "For a player who isn't an online character. " .. MODEL },
        } },
        { title = 'The patient', rows = {
            { 'Ems.revive', 'CPR or the defib brings back someone found dead', unit = 'pct' },
            { 'Ems.bleed', 'An untreated limb bleed loses a second', unit = 'pct', adv = true, help = 'Of their blood. A wound to the body loses 1.4 times as much.' },
            { 'Ems.misplace', 'A tube goes into the wrong place', unit = 'pct', adv = true, help = 'The stethoscope and the EtCO2 show it.' },
            { 'Ems.dead_minutes', 'In arrest, they are gone after', unit = 'minutes' },
            { 'Ems.accept_seconds', 'Players have this long to take a request', unit = 's', help = "An officer's ambulance or a medic's police: then the AI unit goes." },
            { 'Ems.cardiac_minutes', 'A heart attack with no aspirin gets worse after', unit = 'minutes', adv = true },
            { 'Ems.cpr_seconds', 'A cycle of CPR before the rhythm check', unit = 's', help = 'Two minutes in life.' },
            { 'Ems.use_ms', 'A tool that helps takes', unit = 'ms' },
            { 'Ems.wrong_ms', 'A wrong tool costs', unit = 'ms' },
            { 'Ems.assess_ms', 'An assessment takes', unit = 'ms' },
            { 'Ems.grade[1]', 'Excellent grade: hand over within', unit = 'minutes', help = 'From starting treatment.' },
            { 'Ems.grade[2]', 'Good grade: hand over within', unit = 'minutes' },
        } },
        { title = 'First aid for police', rows = {
            { 'Medical.cpr_chance', 'CPR works', unit = 'pct', help = 'Each try.' },
            { 'Medical.cpr_window', 'Only within', unit = 'min', help = 'Of dying.' },
            { 'Medical.cpr_seconds', 'A try takes', unit = 's' },
            { 'Medical.paramedic_revive', 'AI paramedics bring someone back', unit = 'pct', help = 'However long ago they died.' },
        } },
        { title = 'Hospitals', help = 'Patients are handed over at the door of the nearest one.', rows = {
            { 'Ems.hospital_radius', 'Stop within', unit = 'm' },
            { 'Hospitals[*].name', 'Hospital' },
            { 'Hospitals[*]', 'Position', as = 'pos', neg = true, add = 'Add a hospital' },
        } },
        { title = 'The bag', adv = true, help = 'In hotbar order. How many is restocked at the ambulance.', rows = {
            { 'Ems.tools[*].label', 'Tool {n}: name' },
            { 'Ems.tools[*].count', 'Tool {n}: how many' },
            { 'Ems.tools[*].icon', 'Tool {n}: icon' },
            { 'Ems.tools[*].id', 'Tool {n}: id', help = "The game knows the tool by this. Don't change it." },
            { 'Ems.tools[*].group', 'Tool {n}: pouch', opts = { { 'assess', 'Assess' }, { 'treat', 'Treat' }, { 'airway', 'Airway' }, { 'drugs', 'Drugs' } } },
            { 'Ems.tools[*].part', 'Tool {n}: used on a body part', adv = true },
            { 'Ems.tools[*].at', 'Tool {n}: always on', adv = true, help = 'A body part, such as head.' },
        } },
        { title = 'Props and camera', adv = true, help = 'The first model of each list that your game build has.', rows = {
            { 'Ems.bag[*]', 'Medical bag {n}', add = 'Add a bag model' },
            { 'Ems.stretcher[*]', 'Stretcher {n}', add = 'Add a stretcher model' },
            { 'Ems.cam_height', 'Treatment camera height', unit = 'm', help = 'Above the patient.' },
            { 'Ems.lie_height', 'Patient lies above the stretcher', unit = 'm' },
            { 'Ems.lie_turn', 'Turn the patient', unit = 'degrees', neg = true, help = 'If they lie across the stretcher.' },
            { 'Ems.lie_shift', 'Move the patient toward the head end', unit = 'm', neg = true, adv = true, help = 'If they lie too far up or down it.' },
            { 'Ems.cot.y_nudge', 'In the ambulance, move the patient toward the cab', unit = 'm', neg = true, adv = true },
            { 'Ems.cot.z_nudge', 'In the ambulance, raise the patient', unit = 'm', neg = true, adv = true },
            { 'Ems.back_cam_height', 'In the ambulance, the treatment camera looks down from', unit = 'm', adv = true, help = 'Above the patient.' },
        } },
    } },

    { name = 'Discord', sections = {
        { title = 'Connecting', help = "What a player's Discord profile shows while they play. Make an application at discord.com/developers/applications and upload its images under Rich Presence > Art Assets.", rows = {
            { 'Presence.appId', 'Application ID', blank = 'Off: players keep the FiveM activity', help = 'Takes a restart of c3r.' },
            { 'Presence.large', 'Big image', help = 'Its name in Art Assets.' },
            { 'Presence.largeText', 'Big image hover text' },
        } },
        { title = 'Text', help = 'You can use {unit} {call} {players} {max} {duty}, and this shift\'s {stops} {contacts} {citations} {warnings} {arrests} {pursuits_won} {pursuits_lost} {callouts} {assists}.', rows = {
            { 'Presence.line', 'Line under the status', blank = 'None' },
            { 'Presence.hover', 'Small image hover text', blank = 'None' },
            { 'Presence.noCallsign', 'Name with no callsign yet', help = 'Used for {unit}.' },
            { 'Presence.noCallsignMedic', 'A medic with no callsign yet', help = 'Used for {unit}.' },
        } },
        { title = 'Buttons', help = 'A link starts https:// or fivem://connect/, or the button is not shown. Labels up to 32 characters. Players only see the buttons on other people\'s profiles.', rows = {
            { 'Presence.join.label', 'Join button text' },
            { 'Presence.join.url', 'Join button link', blank = 'No button', help = 'For example https://cfx.re/join/abc123' },
            { 'Presence.website.label', 'Website button text' },
            { 'Presence.website.url', 'Website button link', blank = 'No button' },
        } },
        { title = 'What the player is doing', rows = {
            { 'Presence.states.*.text', '{name}', names = STATE },
            { 'Presence.states.*.icon', '{name}: small image', names = STATE, adv = true, help = 'Its name in Art Assets.' },
            { 'Presence.states.*.hover', '{name}: small image hover', names = STATE, adv = true, blank = 'None' },
        } },
    } },
}
