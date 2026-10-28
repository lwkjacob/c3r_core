--[[ lwk_control — plate / name check results (records arrive normalised from the server). ]]

local function head(title) return '~b~DISPATCH~s~ ' .. title end

local function valid_label(v, bad)
    if v == nil then return nil end
    return v and '~g~VALID' or ('~r~' .. bad)
end

-- Returns the feed text and the closing voice lines (one per flag, or the clean return).
local function show_vehicle(v)
    local desc = {}
    for _, k in ipairs({ 'color', 'year', 'make', 'model' }) do
        if v[k] and v[k] ~= '' then desc[#desc + 1] = v[k] end
    end
    local lines = {
        head('Plate Check — ~y~' .. v.plate),
        '~s~Vehicle: ~y~' .. (#desc > 0 and table.concat(desc, ' ') or 'Unknown Vehicle'),
    }
    if v.owner and v.owner ~= '' then lines[#lines + 1] = '~s~Owner: ~y~' .. v.owner end
    local reg, ins = valid_label(v.reg_valid, 'INVALID'), valid_label(v.ins_valid, 'UNINSURED')
    if reg then lines[#lines + 1] = '~s~Registration: ' .. reg end
    if ins then lines[#lines + 1] = '~s~Insurance: ' .. ins end
    if v.stolen then lines[#lines + 1] = '~r~⚑ STOLEN VEHICLE' end
    if v.bolo then lines[#lines + 1] = '~r~⚑ BOLO' .. (v.bolo_reason and v.bolo_reason ~= '' and (' — ' .. v.bolo_reason) or '') end
    -- one spoken line per problem, or the clean return
    local outro = {}
    if v.stolen then outro[#outro + 1] = 'plate_stolen' end
    if v.bolo then outro[#outro + 1] = 'plate_bolo' end
    if v.reg_valid == false then outro[#outro + 1] = 'plate_unregistered' end
    if v.ins_valid == false then outro[#outro + 1] = 'plate_uninsured' end
    if #outro == 0 then outro[1] = 'plate_return' end
    return table.concat(lines, '\n'), outro
end

local function show_person(p)
    local lines = {
        head('Name Check — ~y~' .. (p.last or 'UNKNOWN') .. ', ' .. (p.first or 'UNKNOWN')),
        '~s~DOB: ~y~' .. (p.dob or 'Unknown') .. '~s~ · Gender: ~y~' .. (p.gender or 'Unknown'),
    }
    local dl = valid_label(p.dl_valid, (p.dl or 'INVALID'):upper())
    if dl then lines[#lines + 1] = '~s~DL Status: ' .. dl end
    if p.warrant then lines[#lines + 1] = '~r~⚑ WARRANT — ' .. p.warrant end
    if p.flags and #p.flags > 0 then lines[#lines + 1] = '~s~Flags: ~o~' .. table.concat(p.flags, ', ') end
    local outro = {}
    if p.warrant then outro[#outro + 1] = 'name_warrant' end
    if p.flags and #p.flags > 0 then outro[#outro + 1] = 'name_flags' end
    if p.dl_valid == false then outro[#outro + 1] = 'name_license_invalid' end
    if #outro == 0 then outro[1] = 'name_return' end
    return table.concat(lines, '\n'), outro
end

-- A vehicle may come with a spawn name ("buffalo2"); the clips are named after display names ("Buffalo S").
local function spoken_model(model)
    if not model or model == '' or VehicleClipExists('model_' .. Brain.clip_key(model)) then return model end
    local label = GetLabelText(GetDisplayNameFromVehicleModel(GetHashKey(model)))
    return (label and label ~= 'NULL') and label or model
end

-- Dispatcher reads the plate back; the result text lands when the audio ends.
RegisterNetEvent('lwk_control:plateResult', function(data)
    if data.found then
        local v = data.vehicle
        local text, outro = show_vehicle(v)
        local clips = { 'plate_intro' }
        for _, c in ipairs(SpellClips(v.plate or '')) do clips[#clips + 1] = c end
        -- "... returns to a 2015 black Bravado Buffalo" — any word without a clip is skipped
        local words, article = Brain.vehicle_words({ year = v.year, color = v.color, make = v.make,
            model = spoken_model(v.model) }, VehicleClipExists)
        if words then
            clips[#clips + 1] = 'returns_to_' .. article
            for _, k in ipairs(words) do clips[#clips + 1] = ('nui/voice/vehicle/%s.ogg'):format(k) end
        end
        for _, k in ipairs(outro) do clips[#clips + 1] = k end
        return Speak(clips, function() Notify(text) end, true)
    end
    if data.reason == 'no_vehicle' then return EnterPlateMode() end
    Reply('plate_no_record', 'Plate Check — ~y~' .. tostring(data.plate) .. '\n~r~No record found.')
end)

-- Debug: hear a readout without a traffic stop, e.g. /controlplate 4ABC123 2015 Black Bravado Buffalo
if Config.Debug then
    RegisterCommand('controlplate', function(_, args)
        TriggerEvent('lwk_control:plateResult', { found = true, vehicle = {
            plate = args[1] or 'ABC123', year = args[2], color = args[3], make = args[4],
            model = args[5] and table.concat(args, ' ', 5) or nil, -- rest of the line: "Buffalo S"
        } })
    end, false)
end

-- The intro clip was queued when the check was requested; the result clip follows it.
RegisterNetEvent('lwk_control:nameResult', function(data)
    if data.found then
        local text, outro = show_person(data.person)
        return Speak(outro, function() Notify(text) end)
    end
    if data.reason == 'no_interaction' then
        Reply('name_no_subject', 'Name Check\n~r~No recent subject — talk to someone first.')
    else
        Reply('name_no_record', 'Name Check\n~r~No record found.')
    end
end)
