-- Server exports for other resources. Names follow LB Phone's where the meaning is the same,
-- so scripts written against that phone need little changing.

--- The number of the phone a player has out, or nil.
Export('GetEquippedPhoneNumber', function(src)
    return Phone.number(src)
end)

--- The player holding a phone right now, or nil.
Export('GetSourceFromNumber', function(number)
    return Phone.source(Util.number(number) or '')
end)

Export('HasPhoneItem', function(src)
    return not Inv.required or #Inv.phones(src) > 0
end)

Export('IsInCall', function(src)
    local number = Phone.number(src)
    return number ~= nil and Calls.active(number) ~= nil
end)

--- target: a player source or a phone number. data: { app?, title, content }.
Export('SendNotification', function(target, data)
    if type(target) == 'string' then target = Util.number(target) or target end
    return Phone.notify(target, data.app or 'settings', data.title or '', data.content or '')
end)

--- A text from one number to another. `from` does not have to be a real phone ('Bank', '911').
--- `attachments` (LB): a list of image links; the first is sent with the text.
Export('SendMessage', function(from, to, text, attachments)
    local body = Util.body({ text = text, pic = type(attachments) == 'table' and attachments[1] or nil })
    local sender = Util.number(from) or Util.text(from, 1, 16)
    if not body or not sender then return false end
    return Messages.text(nil, sender, { to }, nil, body) ~= nil
end)

--- data: { to = 'name@domain', sender = 'Display Name', subject, message }.
Export('SendMail', function(data)
    return Social.mail(Util.text(data.sender, 1, 64) or 'System', data.to, Util.text(data.subject, 0, 120) or '', Util.text(data.message, 0, 4000) or '') ~= false
end)

--- A line in a phone's Wallet history (the money itself is yours to move).
Export('AddTransaction', function(number, amount, label)
    number = Util.number(number)
    if not number or type(amount) ~= 'number' then return false end
    Wallet.record(number, Util.text(label, 1, 60) or '', amount)
    local src = Phone.source(number)
    if src then Phone.patch(src, { wallet = Wallet.slice(src, number) }) end
    return true
end)

--- Ring a phone from a script. opts: { number, video?, hidden? }. Returns success.
--- LB's form also works: CreateCall({ source = id }, '555-0142', { videoCall?, hideNumber? }).
Export('CreateCall', function(src, opts, lb)
    if type(src) == 'table' then
        lb = type(lb) == 'table' and lb or {}
        src, opts = src.source, { number = opts, video = lb.videoCall == true, hidden = lb.hideNumber == true }
    end
    local number = Phone.number(src)
    return number ~= nil and Calls.start(number, opts or {}) ~= nil
end)
