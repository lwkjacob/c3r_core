--[[ c3r — word lists the generator draws from. Add your own: nothing else needs to change. ]]

Data = {}

Data.first = {
    male = { 'James', 'Michael', 'Robert', 'David', 'William', 'Richard', 'Joseph', 'Thomas', 'Chris', 'Daniel',
             'Matthew', 'Anthony', 'Mark', 'Steven', 'Paul', 'Andrew', 'Joshua', 'Kevin', 'Brian', 'Ryan',
             'Jason', 'Justin', 'Brandon', 'Tyler', 'Aaron', 'Marcus', 'Luis', 'Carlos', 'Jose', 'Miguel',
             'Andre', 'Darnell', 'Trevor', 'Cody', 'Kyle', 'Derek', 'Nathan', 'Sean', 'Victor', 'Tony' },
    female = { 'Mary', 'Jennifer', 'Linda', 'Sarah', 'Jessica', 'Karen', 'Lisa', 'Nancy', 'Ashley', 'Emily',
               'Michelle', 'Amanda', 'Melissa', 'Stephanie', 'Rebecca', 'Laura', 'Nicole', 'Rachel', 'Megan', 'Hannah',
               'Samantha', 'Brittany', 'Danielle', 'Vanessa', 'Maria', 'Rosa', 'Gabriela', 'Keisha', 'Tamika', 'Crystal',
               'Amber', 'Tiffany', 'Kayla', 'Courtney', 'Erin', 'Holly', 'Monica', 'Valerie', 'Diana', 'Paige' },
}

Data.last = { 'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez',
              'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson', 'Taylor', 'Moore', 'Jackson', 'Martin', 'Lee',
              'Perez', 'Thompson', 'White', 'Harris', 'Sanchez', 'Clark', 'Ramirez', 'Lewis', 'Robinson', 'Walker',
              'Young', 'Allen', 'King', 'Wright', 'Scott', 'Torres', 'Nguyen', 'Hill', 'Flores', 'Green',
              'Adams', 'Nelson', 'Baker', 'Hall', 'Rivera', 'Campbell', 'Mitchell', 'Carter', 'Roberts', 'Turner',
              'Phillips', 'Parker', 'Evans', 'Edwards', 'Collins', 'Stewart', 'Morris', 'Reyes', 'Cook', 'Murphy' }

-- Los Santos and Blaine County roads, for home addresses.
Data.streets = { 'Grove Street', 'Forum Drive', 'Strawberry Avenue', 'Davis Avenue', 'Carson Avenue', 'Innocence Boulevard',
                 'Vespucci Boulevard', 'San Andreas Avenue', 'Palomino Avenue', 'Alta Street', 'Hawick Avenue',
                 'Mirror Park Boulevard', 'West Eclipse Boulevard', 'Bay City Avenue', 'Magellan Avenue', 'Prosperity Street',
                 'Mad Wayne Thunder Drive', 'Integrity Way', 'Elgin Avenue', 'Vinewood Boulevard', 'Alhambra Drive',
                 'Panorama Drive', 'Algonquin Boulevard', 'Paleto Boulevard', 'Duluoz Avenue', 'Joshua Road' }

Data.warrants = { 'Failure to appear', 'Probation violation', 'Unpaid citations', 'Petty theft', 'Burglary',
                  'Assault', 'Possession of a controlled substance', 'Vandalism', 'Domestic battery', 'Grand theft auto' }

-- Record flags that show on a name check (Config.FlagChance of any one person having one).
Data.flags = { 'GANG AFFILIATION', 'PROBATION', 'PAROLE', 'DRUG RELATED', 'VIOLENT HISTORY', 'MENTAL HEALTH' }

Data.drugs = { 'Bag of marijuana (28 g)', 'Baggie of white powder', 'Glass pipe', 'Prescription pills, no label',
               'Small bag of crystals', 'Rolled joint' }
Data.drink = { 'Open can of beer', 'Half-empty bottle of vodka', 'Empty beer cans' }
Data.weapons = { 'Unregistered pistol', 'Switchblade', 'Brass knuckles', 'Revolver, serial number filed off' }
Data.stolen = { 'Screwdriver', 'Slim jim', "Someone else's mail" } -- tools of the trade in a stolen car

-- What a search turns up that's nobody's business: pockets, and the car.
Data.pockets = { 'Wallet', 'Phone', 'Keys', 'Lighter', 'Loose change', 'Receipts', 'Gum', 'Earbuds' }
Data.car = { 'Sunglasses', 'Phone charger', 'Fast-food bags', 'Gym bag', 'Umbrella', 'Water bottles', 'Parking tickets',
             'Jumper cables', 'Child seat', 'Work boots' }
