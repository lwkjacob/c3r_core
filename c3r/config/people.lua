-- c3r config: who you stop: their hidden truths, demeanours and records.

-- How often each hidden truth comes up (relative weights, any numbers; 0 turns one off).
Config.Secrets = {
    clean = 40, nervous = 10, unlicensed = 8, suspended = 8, expired = 8, drunk = 8, drugs = 7, warrant = 6, stolen = 5,
}
Config.Demeanors = { polite = 50, nervous = 20, rude = 15, chatty = 15 }
-- Passengers' own hidden truths (they aren't driving, so no licence or papers secrets).
Config.PassengerSecrets = { clean = 55, nervous = 15, warrant = 10, drugs = 10, drunk = 10 }

Config.FlagChance = 0.06        -- a record flag (PROBATION, GANG AFFILIATION...) on anyone
Config.BorrowedChance = 0.15    -- the car belongs to a relative
Config.OwnerDrivesChance = 0.8  -- a car stopped before: its owner is at the wheel again
