-- Banking bridge (server).
--
-- A player's own balance is framework bank money with every bank script, so Wallet works with
-- all of them and needs nothing from this file. What differs per bank is:
--   1. where a job's money lives (the Company Account under Services > My Job), and
--   2. how to add a line to the history the bank shows in its own app.
--
--   bank               written from
--   lwk_bank           its source
--   Renewed-Banking    its source
--   qb-banking         its source
--   qb-management      its source
--   okokBanking        its documentation
--   wasabi_banking     its documentation
--   tgg-banking        its documentation
--   p_banking          its documentation
--   fd_banking         other open-source bridges (its own documentation is not public)
--   tgiann-bank        other open-source bridges (its documentation could not be read)
--   esx_addonaccount   its source. This is also where esx_society keeps a job's money (`society_<job>`).
--   ox_core            its source: a group's own account (the group needs `hasAccount`)
--
-- For another bank: add an entry to BANKS with the calls it has, and its resource name to ORDER.

Bank = {}

-- One entry per bank, named after its resource:
--   balance(job)                        the company account's balance, or nil when the job has none
--   add(job, amount, reason)            money in. Answers whether it worked
--   remove(job, amount, reason)         money out (the balance has been checked already)
--   statement(src, amount, label, out)  optional: a line in the player's own history. `out`: the money left them
-- An error in any of them is taken as "no".
local BANKS = {}

BANKS['lwk_bank'] = {
    balance = function(job) return exports.lwk_bank:GetBusinessBalance(job) end,
    add = function(job, amount, reason) return exports.lwk_bank:AddBusinessMoney(job, amount, reason) end,
    remove = function(job, amount, reason) return exports.lwk_bank:RemoveBusinessMoney(job, amount, reason) end,
}

BANKS['Renewed-Banking'] = {
    balance = function(job) return exports['Renewed-Banking']:getAccountMoney(job) end,
    add = function(job, amount) return exports['Renewed-Banking']:addAccountMoney(job, amount) end,
    remove = function(job, amount) return exports['Renewed-Banking']:removeAccountMoney(job, amount) end,
    statement = function(src, amount, label, out)
        local name = Bridge.name(src)
        exports['Renewed-Banking']:handleTransaction(Bridge.identifier(src), label, amount, label,
            out and name or label, out and label or name, out and 'withdraw' or 'deposit')
    end,
}

BANKS['qb-banking'] = {
    balance = function(job) return exports['qb-banking']:GetAccountBalance(job) end,
    add = function(job, amount, reason) return exports['qb-banking']:AddMoney(job, amount, reason) end,
    remove = function(job, amount, reason) return exports['qb-banking']:RemoveMoney(job, amount, reason) end,
    statement = function(src, amount, label, out)
        exports['qb-banking']:CreateBankStatement(src, 'checking', amount, label, out and 'withdraw' or 'deposit', 'player')
    end,
}

BANKS['wasabi_banking'] = {
    balance = function(job) return exports.wasabi_banking:GetAccountBalance(job, 'society') end,
    add = function(job, amount) return exports.wasabi_banking:AddMoney('society', job, amount) end,
    remove = function(job, amount) return exports.wasabi_banking:RemoveMoney('society', job, amount) end,
    statement = function(src, amount, label, out)
        exports.wasabi_banking:Transaction(Bridge.identifier(src), label, amount, out and 'sent' or 'deposit', 'personal')
    end,
}

BANKS['tgg-banking'] = {
    balance = function(job) return exports['tgg-banking']:GetSocietyAccountMoney(job) end,
    add = function(job, amount) return exports['tgg-banking']:AddSocietyMoney(job, amount) end,
    remove = function(job, amount) return exports['tgg-banking']:RemoveSocietyMoney(job, amount) end,
}

BANKS['p_banking'] = {
    balance = function(job) return exports['p_banking']:getAccountMoney(job) end,
    add = function(job, amount) return exports['p_banking']:addAccountMoney(job, amount) end,
    remove = function(job, amount) return exports['p_banking']:removeAccountMoney(job, amount) end,
}

BANKS['fd_banking'] = {
    balance = function(job) return exports['fd_banking']:GetAccount(job) end,
    add = function(job, amount, reason) return exports['fd_banking']:AddMoney(job, amount, reason) end,
    remove = function(job, amount, reason) return exports['fd_banking']:RemoveMoney(job, amount, reason) end,
}

-- The next three do not say whether a movement worked: no error is taken as success.
BANKS['tgiann-bank'] = {
    balance = function(job) return exports['tgiann-bank']:GetJobAccountBalance(job) end,
    add = function(job, amount) exports['tgiann-bank']:AddJobMoney(job, amount) return true end,
    remove = function(job, amount) exports['tgiann-bank']:RemoveJobMoney(job, amount) return true end,
}

for _, res in ipairs({ 'okokBanking', 'qb-management' }) do   -- the same three calls under two names
    BANKS[res] = {
        balance = function(job) return exports[res]:GetAccount(job) end,
        add = function(job, amount) exports[res]:AddMoney(job, amount) return true end,
        remove = function(job, amount) exports[res]:RemoveMoney(job, amount) return true end,
    }
end

-- esx_addonaccount hands the account over through an event, and the account has its own methods.
local function society(job)
    local account
    TriggerEvent('esx_addonaccount:getSharedAccount', 'society_' .. job, function(a) account = a end)
    return account
end

BANKS['esx_addonaccount'] = {
    balance = function(job)
        local a = society(job)
        return a and a.money
    end,
    add = function(job, amount)
        local a = society(job)
        if a then a.addMoney(amount) end
        return a ~= nil
    end,
    remove = function(job, amount)
        local a = society(job)
        if a then a.removeMoney(amount) end
        return a ~= nil
    end,
}

--- Call a method of an ox_core group's account (see the notes on ox_core in config/bridge/framework.lua).
local function group(job, ...)
    local a = exports.ox_core:GetGroupAccount(job)
    return a and exports.ox_core:CallAccount(a.accountId, ...)
end

local function moved(res) return type(res) == 'table' and res.success == true end

BANKS['ox_core'] = {
    balance = function(job) return group(job, 'get', 'balance') end,
    add = function(job, amount, reason) return moved(group(job, 'addBalance', { amount = amount, message = reason })) end,
    remove = function(job, amount, reason) return moved(group(job, 'removeBalance', { amount = amount, message = reason })) end,
}

-- lwk_bank also answers to the other banks' names, so it is looked for first.
-- esx_addonaccount comes after them: on ESX it runs under every bank above, and they are the ones holding the money then.
local ORDER = {
    'lwk_bank', 'Renewed-Banking', 'qb-banking', 'okokBanking', 'wasabi_banking', 'tgg-banking', 'p_banking', 'fd_banking', 'tgiann-bank',
    'qb-management', 'esx_addonaccount', 'ox_core',
}
local kind

--- Which bank is running. Worked out on first use, by which time every resource has started.
function Bank.kind()
    if kind then return kind end
    kind = Config.bank ~= 'auto' and Config.bank or 'none'
    if Config.bank == 'auto' then
        for _, res in ipairs(ORDER) do
            if GetResourceState(res) == 'started' then kind = res break end
        end
    end
    return kind
end

--- Balance of a job's company account, or nil when there is no such account (or no bank).
function Bank.balance(job)
    local bank = BANKS[Bank.kind()]
    if not bank then return nil end
    local ok, v = pcall(bank.balance, job)
    return ok and tonumber(v) or nil
end

local function move(way, job, amount, reason)
    local bank = BANKS[Bank.kind()]
    if not bank then return false end
    local ok, v = pcall(bank[way], job, amount, reason)
    return ok and v ~= nil and v ~= false and v ~= 0
end

function Bank.add(job, amount, reason)
    return move('add', job, amount, reason)
end

-- Checks the balance itself: not every bank refuses an overdraft.
function Bank.remove(job, amount, reason)
    local have = Bank.balance(job)
    if not have or have < amount then return false end
    return move('remove', job, amount, reason)
end

--- Add a line to the player's history in the bank's own app. The money has already moved;
--- `amount` is negative for money leaving the player.
-- ponytail: Renewed-Banking, qb-banking and wasabi_banking only. lwk_bank lists framework money
-- movements by itself; tgg-banking and p_banking want the account's IBAN, which the phone does not
-- know; the others have no public call for it. There, phone payments do not show in the bank's history.
function Bank.statement(src, amount, label)
    local bank = BANKS[Bank.kind()]
    if bank and bank.statement then pcall(bank.statement, src, math.abs(amount), label, amount < 0) end
end
