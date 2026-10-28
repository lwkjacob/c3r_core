--[[ lwk_control — other on-duty officers: "nearest unit?" and "have Two Boy Four meet me". ]]

OtherUnits = {} -- { { id, callsign, words, clips } } for every on-duty player but you

local my_id = GetPlayerServerId(PlayerId())

-- Report our own c3r duty + callsign; the server only rebroadcasts on change.
CreateThread(function()
    local sent_on, sent_cs
    while true do
        local on = Pd('isOnDuty') == true
        local cs = CallsignRaw or ''
        if on ~= sent_on or cs ~= sent_cs then
            TriggerServerEvent('lwk_control:unit', on, cs)
            sent_on, sent_cs = on, cs
        end
        Wait(10000)
    end
end)

RegisterNetEvent('lwk_control:units', function(list)
    OtherUnits = {}
    for _, u in ipairs(list or {}) do
        local cs = Brain.callsign(u.callsign)
        if u.id ~= my_id then
            OtherUnits[#OtherUnits + 1] = { id = u.id, callsign = u.callsign,
                words = cs and cs.words or {}, clips = cs and cs.clips or {} }
        end
    end
end)

-- Callsign clips + feed text for a unit (empty when it has none).
local function unit_name(callsign)
    local cs = Brain.callsign(callsign or '')
    return cs and cs.clips or {}, (callsign and callsign ~= '') and callsign or 'a unit'
end

-- "Nearest unit is Three Charles Eleven, half a mile north."
RegisterNetEvent('lwk_control:nearestResult', function(r)
    if not r then return Reply('unit_none', 'No other units in service.') end
    local clips, name = unit_name(r.callsign)
    local dist_items, dist_text = Brain.distance_words(r.dist)
    local dir_key, dir_text = Brain.direction(r.dx, r.dy)
    local items = { 'unit_nearest' }
    for _, c in ipairs(clips) do items[#items + 1] = c end
    if #clips > 0 then items[#items + 1] = 'nui/voice/pause.ogg' end
    for _, c in ipairs(dist_items) do items[#items + 1] = c end
    if r.dist >= 190 then items[#items + 1] = dir_key end -- "right near you" needs no direction
    Reply(nil, 'Nearest unit: ' .. name .. ', ' .. dist_text .. (r.dist >= 190 and (' ' .. dir_text) or '') .. '.')
    Speak(items, nil, true)
end)

-- Our request went out: "Copy, notifying Two Boy Four."
RegisterNetEvent('lwk_control:meetResult', function(ok, callsign)
    if not ok then return Reply('meet_unknown', "That unit isn't in service.") end
    local clips, name = unit_name(callsign)
    local items = { 'meet_notify' }
    for _, c in ipairs(clips) do items[#items + 1] = c end
    Reply(nil, 'Copy, notifying ' .. name .. '.')
    Speak(items, nil, true)
end)

-- Someone asked us to meet them: "<our callsign>, One Adam Twelve requests you meet at Strawberry Avenue."
RegisterNetEvent('lwk_control:meetRequest', function(callsign, pos)
    if not pos then return end
    SetNewWaypoint(pos.x, pos.y)
    local clips, name = unit_name(callsign)
    local items = {}
    for _, c in ipairs(clips) do items[#items + 1] = c end
    items[#items + 1] = #clips > 0 and 'meet_requests' or 'meet_unit_requests'
    local where_items, where = Brain.location_words(LocationAt(pos), PlaceClipExists)
    for _, c in ipairs(where_items or {}) do items[#items + 1] = c end
    if not where_items then items[#items + 1] = 'meet_your_waypoint' end
    Reply(nil, '~y~' .. name .. '~s~ requests you meet at ' .. (where or 'their location') .. '. Waypoint set.')
    Speak(items, nil, true)
end)
