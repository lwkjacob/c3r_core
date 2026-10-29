--[[
    c3r callout: the example. A template to copy when you write your own callout (slice 1b turns this into the full,
    commented template: people to talk to, evidence, a story that changes the ending).

    For now it shows the shape: reports (the 911 call, shared by every story so it never gives the story away),
    locations, stories, and objectives on the card. With two units on it, each gets a different objective.
]]

Callout({
    id = 'example',
    name = 'Suspicious person',
    priority = 3,
    enabled = true, -- set false once the real callouts are in
    reports = {
        'Caller reports someone hanging around the parked cars, looking in the windows.',
        'Caller says a man has been walking up and down the street for an hour, trying car doors.',
    },
    -- street: shown on the card; at: the scene (on scene within Config.Callouts.arrive m). Approximate: move to suit.
    locations = {
        { street = 'Legion Square', at = vector3(195.2, -933.8, 30.7) },
        { street = 'Grove Street', at = vector3(100.4, -1937.0, 20.8) },
        { street = 'Vespucci Beach', at = vector3(-1222.0, -1490.0, 4.4) },
        { street = 'Mirror Park', at = vector3(1102.0, -458.0, 67.0) },
        { street = 'Vinewood Boulevard', at = vector3(250.0, 222.0, 106.3) },
    },
    stories = {
        gone = {
            weight = 1,
            setup = function(c)
                -- two objectives open at once: one unit each
                c:objective('look', 'Look around the area', { hint = 'Walk the street and check the parked cars.' })
                c:objective('caller', 'Find the caller', { hint = 'They said they would wait nearby.' })
                c:objective('report', 'Tell dispatch what you found', { after = { 'look', 'caller' }, who = 'all' })
                -- (placeholder until 1b brings people and evidence: time spent on scene does the objectives)
                local on_scene = nil
                c:on('arrive', function() on_scene = on_scene or 0 end)
                c:on('tick', function()
                    if not on_scene then return end
                    on_scene = on_scene + 1
                    if on_scene == 20 then c:done('look') end
                    if on_scene == 30 then c:done('caller') end
                    if on_scene == 40 then c:finish('Area checked: nobody matching the description. Caller had gone.') end
                end)
            end,
        },
    },
})
