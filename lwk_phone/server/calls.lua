-- Calls. The server owns who is ringing whom; voice itself is the voice script's job
-- (config/bridge/voice.lua). Video rides WebRTC between the two phones: the server only
-- relays the handshake.

Calls = {}

local calls  = {}   -- id -> { id, caller, callee, targets = { number... }, video, hidden, company, state, started, answered, muted = { number = true }, speaker = { number = true } }
local inCall = {}   -- number -> call id
local nextId = 0
local CHANNEL = 4200   -- voice channel offset, clear of radio frequencies other scripts use
local SPEAKER_RANGE = 4.0   -- how close someone has to stand to a phone on speaker to hear it
local listeners = {}   -- src -> id of the call they are overhearing

function Calls.active(number) return calls[inCall[number] or 0] end

--- Recent calls for the Phone app, from this phone's point of view.
function Calls.log(number)
    local out = {}
    local since = tonumber(Phone.get(number, 'callsCleared')) or 0
    for i, r in ipairs(MySQL.query.await('SELECT * FROM lwk_phone_calls WHERE (caller = ? OR callee = ?) AND created > ? ORDER BY id DESC LIMIT 60', { number, number, since })) do
        local outgoing = r.caller == number
        out[i] = {
            id = r.id, time = r.created, video = r.video == 1 or r.video == true or nil,
            dur = r.duration > 0 and r.duration or nil,
            dir = outgoing and 'out' or r.answered ~= 0 and r.answered ~= false and 'in' or 'missed',
            number = outgoing and r.callee or (r.hidden ~= 0 and r.hidden ~= false) and L('no_caller_id') or r.caller,
        }
    end
    return out
end

--- Take `src` back out of a call they were only overhearing. If the voice script has them somewhere
--- else by now (they took a call of their own), they are left alone.
local function unlisten(src)
    local id = listeners[src]
    listeners[src] = nil
    if id and Voice.channel(src) == CHANNEL + id then pcall(Voice.set, src, 0) end
end

--- Speakerphone. Whoever stands near a phone on speaker is put in the call's voice channel: they hear
--- the other end, and the other end hears them, as around a real phone. Run once a second.
function Calls.speakerTick()
    local near = {}   -- src -> call id
    for id, call in pairs(calls) do
        if call.state == 'active' and next(call.speaker) then
            local busy = {}   -- the two on the call
            for _, n in ipairs({ call.caller, call.targets[1] }) do busy[Phone.source(n) or 0] = true end
            for number in pairs(call.speaker) do
                local holder = Phone.source(number)
                local ped = holder and GetPlayerPed(holder) or 0
                if ped ~= 0 then
                    local at, bucket = GetEntityCoords(ped), GetPlayerRoutingBucket(holder)
                    for _, p in ipairs(GetPlayers()) do
                        p = tonumber(p)
                        local other = GetPlayerPed(p)
                        local channel = Voice.channel(p)
                        -- Not someone on a call of their own, and not someone in another instance.
                        if not busy[p] and other ~= 0 and (channel == 0 or channel == CHANNEL + id)
                            and GetPlayerRoutingBucket(p) == bucket and #(GetEntityCoords(other) - at) <= SPEAKER_RANGE then
                            near[p] = id
                        end
                    end
                end
            end
        end
    end
    for src, id in pairs(listeners) do
        if near[src] ~= id then unlisten(src) end
    end
    for src, id in pairs(near) do
        if not listeners[src] then
            listeners[src] = id
            pcall(Voice.set, src, CHANNEL + id)
        end
    end
end

-- Voicemail. A call nobody picks up ends with the caller being offered the chance to leave a
-- message: their phone records it, uploads it like a voice message, and hands over the link.
local leaving = {}   -- caller's number -> { to, from = what the other phone will show, at }

--- Can the caller of this unanswered call leave a message? Needs somewhere to store the recording
--- and a phone at the other end. Not for calls to a company: there is no one phone to leave it on.
local function takesMessage(call)
    if call.company or call.answered then return false end
    if Phone.uploadToken() == '' then return false end
    -- Blocking is done by the phone that blocks (it ignores the call), so a blocked caller rings out
    -- like anyone else. They do not get to leave a message.
    for _, c in ipairs(Phone.get(call.callee, 'contacts') or {}) do
        if c.blocked and Util.number(c.number) == call.caller then return false end
    end
    return MySQL.scalar.await('SELECT 1 FROM lwk_phone_phones WHERE number = ?', { call.callee }) ~= nil
end

local function finish(call, by)
    calls[call.id] = nil
    for src, id in pairs(listeners) do
        if id == call.id then unlisten(src) end
    end
    local duration = call.answered and os.time() - call.answered or 0
    -- Off the call before anything below waits on the database: nobody answers a call that is over.
    local parties = { call.caller, table.unpack(call.targets) }
    for _, n in ipairs(parties) do inCall[n] = nil end
    -- Rang out or was declined (anything but the caller giving up): over to voicemail.
    local message = by ~= call.caller and takesMessage(call)
    if message then
        leaving[call.caller] = { to = call.callee, from = call.hidden and L('no_caller_id') or call.caller, at = os.time() }
    end
    for _, n in ipairs(parties) do
        local src = Phone.source(n)
        if src then
            pcall(Voice.set, src, 0)
            if n == call.caller and message then
                Phone.push(src, { action = 'call', event = 'voicemail' })
            elseif n ~= by then
                Phone.push(src, { action = 'call', event = 'ended' })
            end
        end
    end
    MySQL.insert('INSERT INTO lwk_phone_calls (caller, callee, video, hidden, answered, duration, created) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { call.caller, call.callee, call.video and 1 or 0, call.hidden and 1 or 0, call.answered and 1 or 0, duration, call.started * 1000 })
end

--- Ring `callee` (a number) or every on-duty employee of a company. Used by the UI and the CreateCall export.
function Calls.start(number, opts)
    if inCall[number] then return nil, L('err_busy') end
    if Phone.flags(number).airplane then return nil, L('err_airplane') end

    local targets, callee, company = {}, nil, nil
    local function free(n) return n ~= number and Phone.source(n) and not inCall[n] and not Phone.flags(n).airplane end

    if opts.company then
        for _, c in ipairs(Config.companies) do
            if c.job == opts.company then company = c end
        end
        if not company then return nil, L('err_generic') end
        callee = company.name:sub(1, 16)
        for _, src in ipairs(Bridge.onDuty(company.job)) do
            local n = Phone.number(src)
            if n and free(n) then targets[#targets + 1] = n end
        end
    else
        callee = Util.number(opts.number)
        if not callee or callee == number then return nil, L('err_number') end
        if free(callee) then targets[1] = callee end
    end

    nextId = nextId + 1
    local call = {
        id = nextId, caller = number, callee = callee, targets = targets, company = company ~= nil,
        video = opts.video == true, hidden = opts.hidden == true or Phone.flags(number).hideCallerId,
        state = 'ringing', started = os.time(), muted = {}, speaker = {},
    }
    calls[call.id], inCall[number] = call, call.id
    for _, n in ipairs(targets) do
        inCall[n] = call.id
        Phone.push(n, { action = 'call', event = 'incoming', number = call.hidden and L('no_caller_id') or number, video = call.video })
    end
    return call
end

--- Clear this phone's call history (the other side keeps theirs).
RPC['call.clear'] = function(_, number)
    Phone.set(number, 'callsCleared', Phone.now())
    return Phone.ok()
end

RPC['call.start'] = function(_, number, data)
    local call, err = Calls.start(number, data)
    if not call then return Phone.fail(err) end
    return Phone.ok()
end

RPC['call.answer'] = function(src, number)
    local call = Calls.active(number)
    if not call or call.state ~= 'ringing' or call.caller == number then return Phone.fail(L('err_generic')) end
    call.state, call.answered = 'active', os.time()
    -- A company call rings every employee: the first to pick up takes it, the rest stop ringing.
    for _, n in ipairs(call.targets) do
        if n ~= number then
            inCall[n] = nil
            Phone.push(n, { action = 'call', event = 'ended' })
        end
    end
    call.targets = { number }
    if call.company then call.callee = number end

    local caller = Phone.source(call.caller)
    Voice.set(src, CHANNEL + call.id)
    if caller then Voice.set(caller, CHANNEL + call.id) end
    Phone.push(call.caller, { action = 'call', event = 'answered', peer = number })
    return Phone.ok({ peer = call.hidden and '' or call.caller })
end

RPC['call.end'] = function(_, number)
    local call = Calls.active(number)
    if not call then return Phone.ok() end
    -- One employee declining a company call does not end it for the others.
    if call.state == 'ringing' and call.company and number ~= call.caller and #call.targets > 1 then
        for i, n in ipairs(call.targets) do
            if n == number then table.remove(call.targets, i) break end
        end
        inCall[number] = nil
        return Phone.ok()
    end
    finish(call, number)
    return Phone.ok()
end

--- The message left after an unanswered call. Once, and only for the call that was just made.
RPC['voicemail.leave'] = function(_, number, data)
    local v = leaving[number]
    leaving[number] = nil
    local audio, seconds = Util.url(data.audio), Util.int(data.seconds, 1, 60)
    if not v or os.time() - v.at > 120 or not audio or not seconds then return Phone.fail(L('err_generic')) end
    local list = Phone.get(v.to, 'voicemail') or {}
    table.insert(list, 1, { id = Phone.now() + math.random(0, 999), number = v.from, time = Phone.now(), dur = seconds, audio = audio })
    while #list > 20 do table.remove(list) end
    Phone.set(v.to, 'voicemail', list)
    Phone.patch(v.to, { voicemail = list })
    Phone.notify(v.to, 'phone', v.from, L('voicemail_new'))
    return Phone.ok()
end

--- Mark a voicemail as listened to, or delete it.
RPC['voicemail.update'] = function(_, number, data)
    local id, list, kept = tonumber(data.id), Phone.get(number, 'voicemail') or {}, {}
    for _, v in ipairs(list) do
        if v.id ~= id then
            kept[#kept + 1] = v
        elseif not data.delete then
            v.heard = true
            kept[#kept + 1] = v
        end
    end
    Phone.set(number, 'voicemail', kept)
    return Phone.ok({ voicemail = kept })
end

--- Switch a call between voice and video while it is going. Turning the cameras on takes both
--- sides: the first to ask is put to the other, and it happens when they ask back (accept).
--- Either side can go back to voice on their own.
RPC['call.video'] = function(_, number, data)
    local call = Calls.active(number)
    if not call or call.state ~= 'active' then return Phone.fail(L('err_generic')) end
    local other = call.caller == number and call.targets[1] or call.caller
    local on = data.on == true
    if on and not call.video and call.wantsVideo ~= other then
        call.wantsVideo = number
        Phone.push(other, { action = 'call', event = 'videoAsk' })
        return Phone.ok()
    end
    call.video, call.wantsVideo = on, nil
    Phone.push(number, { action = 'call', event = 'video', on = on })
    Phone.push(other, { action = 'call', event = 'video', on = on })
    return Phone.ok()
end

--- The Mute and Speaker buttons. Muted: the other end stops hearing this phone (people standing next
--- to its holder still do). Speaker: people standing near it hear the call, see Calls.speakerTick.
RPC['call.audio'] = function(src, number, data)
    local call = Calls.active(number)
    if not call or call.state ~= 'active' then return Phone.ok() end
    local muted = data.muted == true
    if muted ~= (call.muted[number] == true) then
        call.muted[number] = muted or nil
        local peer = Phone.source(call.caller == number and call.targets[1] or call.caller)
        if peer then TriggerClientEvent('lwk_phone:callMute', peer, src, muted) end
    end
    -- Positions are only known to the server with OneSync; without it the speaker is just a button.
    call.speaker[number] = data.speaker == true and GetConvar('onesync', 'off') ~= 'off' or nil
    return Phone.ok()
end

--- WebRTC handshake relay (video calls, live streams). The media never touches the server.
--- Peers are named by role, not number: 'call' is the other end of the caller's active call,
--- 'lumen:<user>' is someone in the same live stream.
RPC['rtc'] = function(_, number, data)
    if type(data.signal) ~= 'table' or type(data.to) ~= 'string' then return Phone.fail(L('err_generic')) end
    if data.to == 'call' then
        local call = Calls.active(number)
        if not call or call.state ~= 'active' then return Phone.fail(L('err_generic')) end
        Phone.push(call.caller == number and call.targets[1] or call.caller, { action = 'rtc', from = 'call', signal = data.signal })
    else
        local to, from = Social.livePeer(number, data.to)
        if not to then return Phone.fail(L('err_generic')) end
        Messages.push(to, { action = 'rtc', from = from, signal = data.signal })
    end
    return Phone.ok()
end

AddEventHandler('lwk_phone:dropped', function(_, number)
    local call = Calls.active(number)
    if call then finish(call, number) end
end)

AddEventHandler('playerDropped', function()
    listeners[source] = nil
end)

CreateThread(function()
    while true do
        Wait(1000)
        Calls.speakerTick()
    end
end)

-- Unanswered calls stop ringing and become missed calls.
CreateThread(function()
    while true do
        Wait(2000)
        local now = os.time()
        for _, call in pairs(calls) do
            if call.state == 'ringing' and now - call.started >= Config.calls.ringSeconds then finish(call) end
        end
    end
end)
