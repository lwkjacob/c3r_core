-- c3r config: first aid.

-- Someone down (dead, or on the ground hurt): the E wheel's first aid. CPR brings back the recently dead now and
-- then: cpr_chance a try, within cpr_window seconds of dying.
Config.Medical = { cpr_chance = 0.35, cpr_window = 300, cpr_seconds = 15 }
Config.Medical.paramedic_revive = 0.4 -- paramedics bring back anyone they find dead, this often (however long ago)
