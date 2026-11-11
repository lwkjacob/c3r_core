// lwk_calloutcreator: what the editor offers. Lists of game names to pick from (any other name can be typed, and
// Preview says whether the game has it), and the shapes of rules, conditions, actions and presets.
'use strict';

const ASSETS = {
  ped: ['a_m_y_hipster_01', 'a_m_y_downtown_01', 'a_m_m_skater_01', 'a_m_y_skater_01', 'a_m_y_stwhi_01', 'a_m_m_bevhills_01', 'a_m_m_business_01',
    'a_m_y_business_01', 'a_m_m_farmer_01', 'a_m_m_hillbilly_01', 'a_m_m_tramp_01', 'a_m_o_tramp_01', 'a_m_y_methhead_01', 'a_m_m_salton_01',
    'a_m_y_beach_01', 'a_m_m_eastsa_01', 'a_m_y_mexthug_01', 'a_m_y_golfer_01', 'a_m_y_runner_01', 'a_m_m_soucent_01', 'a_m_y_soucent_01',
    'a_m_m_afriamer_01', 'a_m_y_vinewood_01', 'a_m_y_genstreet_01', 'a_m_o_genstreet_01', 'a_m_m_og_boss_01', 'a_m_m_fatlatin_01',
    'a_m_m_polynesian_01', 'a_m_y_hippy_01', 'a_f_y_hipster_01', 'a_f_m_downtown_01', 'a_f_y_business_01', 'a_f_y_tourist_01', 'a_f_m_tramp_01',
    'a_f_y_beach_01', 'a_f_y_fitness_01', 'a_f_m_soucent_01', 'a_f_y_vinewood_01', 'a_f_y_genhot_01', 'a_f_m_fatwhite_01', 'a_f_y_hippie_01',
    'g_m_y_ballaorig_01', 'g_m_y_famca_01', 'g_m_y_lost_01', 'g_m_y_mexgoon_01', 'g_m_y_salvagoon_01', 'mp_m_shopkeep_01', 's_m_m_bouncer_01',
    's_m_m_security_01', 's_m_y_construct_01', 's_m_m_gardener_01', 's_m_y_dealer_01', 's_m_m_postal_01', 's_f_y_shop_mid', 's_m_y_waiter_01',
    's_m_y_barman_01', 's_f_y_bartender_01', 'a_c_deer', 'a_c_chop', 'a_c_husky', 'a_c_rottweiler', 'a_c_shepherd', 'a_c_retriever',
    'a_c_cat_01', 'a_c_coyote', 'a_c_boar', 'a_c_cow'],
  prop: ['prop_cs_beer_bot_01', 'prop_beer_bottle', 'prop_amb_beer_bottle', 'ng_proc_brkbottle_02a', 'prop_plastic_cup_02', 'ng_proc_sodacan_01a',
    'prop_ld_can_01', 'prop_mug_01', 'prop_plate_01', 'prop_npc_phone_02', 'prop_ld_wallet_01', 'prop_ld_suitcase_01', 'prop_michael_backpack',
    'prop_cs_cardbox_01', 'prop_cardbordbox_02a', 'prop_cardbordbox_03a', 'prop_cs_newspaper', 'prop_cs_bandana', 'prop_tool_box_02',
    'prop_ing_crowbar', 'prop_cs_padlock', 'prop_byard_ladder01', 'prop_generator_03b', 'prop_speaker_05', 'prop_speaker_06', 'v_res_m_lamptbl',
    'p_syringe_01_s', 'prop_drug_package', 'prop_money_bag_01', 'prop_cash_pile_01', 'prop_sgun_casing', 'w_pi_pistol', 'w_ar_carbinerifle',
    'w_me_knife_01', 'w_me_bat', 'imp_prop_impexp_front_bumper_01a', 'v_ind_cs_hubcap', 'ind_prop_firework_01', 'prop_roadcone02a',
    'prop_barrier_work05', 'prop_bin_01a', 'prop_rub_binbag_01', 'prop_bench_01a'],
  vehicle: ['asea', 'premier', 'stanier', 'emperor', 'emperor2', 'tailgater', 'fugitive', 'intruder', 'primo', 'washington', 'oracle', 'schafter2',
    'sultan', 'manana', 'tornado', 'peyote', 'buccaneer', 'blista', 'dilettante', 'issi2', 'panto', 'prairie', 'futo', 'penumbra', 'comet2',
    'elegy2', 'banshee', 'feltzer2', 'jester', 'rapidgt', 'baller', 'cavalcade', 'granger', 'landstalker', 'rocoto', 'patriot', 'rebel', 'bison',
    'bobcatxl', 'sadler', 'burrito3', 'speedo', 'mule', 'pounder', 'towtruck2', 'taxi', 'bus', 'faggio', 'sanchez', 'bati', 'akuma', 'pcj', 'bmx',
    'scorcher'],
  weapon: ['WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_PISTOL50', 'WEAPON_SNSPISTOL', 'WEAPON_REVOLVER', 'WEAPON_MICROSMG', 'WEAPON_SMG',
    'WEAPON_ASSAULTRIFLE', 'WEAPON_CARBINERIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_KNIFE', 'WEAPON_SWITCHBLADE',
    'WEAPON_MACHETE', 'WEAPON_BAT', 'WEAPON_CROWBAR', 'WEAPON_HAMMER', 'WEAPON_GOLFCLUB', 'WEAPON_BOTTLE', 'WEAPON_KNUCKLE', 'WEAPON_FLASHLIGHT',
    'WEAPON_STUNGUN', 'WEAPON_FIREWORK', 'WEAPON_MOLOTOV', 'WEAPON_PETROLCAN'],
  scenario: ['WORLD_HUMAN_STAND_IMPATIENT', 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_DRINKING', 'WORLD_HUMAN_HANG_OUT_STREET',
    'WORLD_HUMAN_LEANING', 'WORLD_HUMAN_CLIPBOARD', 'WORLD_HUMAN_GUARD_STAND', 'WORLD_HUMAN_AA_COFFEE', 'WORLD_HUMAN_AA_SMOKE',
    'WORLD_HUMAN_BUM_STANDING', 'WORLD_HUMAN_BUM_SLUMPED', 'WORLD_HUMAN_BUM_WASH', 'WORLD_HUMAN_CAR_PARK_ATTENDANT', 'WORLD_HUMAN_CHEERING',
    'WORLD_HUMAN_DRUG_DEALER', 'WORLD_HUMAN_DRUG_DEALER_HARD', 'WORLD_HUMAN_GARDENER_PLANT', 'WORLD_HUMAN_HAMMERING', 'WORLD_HUMAN_JOG_STANDING',
    'WORLD_HUMAN_MOBILE_FILM_SHOCKING', 'WORLD_HUMAN_MUSICIAN', 'WORLD_HUMAN_PARTYING', 'WORLD_HUMAN_PICNIC', 'WORLD_HUMAN_SEAT_LEDGE',
    'WORLD_HUMAN_SEAT_STEPS', 'WORLD_HUMAN_SEAT_WALL', 'WORLD_HUMAN_STAND_FIRE', 'WORLD_HUMAN_STAND_FISHING', 'WORLD_HUMAN_STUPOR',
    'WORLD_HUMAN_SUNBATHE_BACK', 'WORLD_HUMAN_TOURIST_MAP', 'WORLD_HUMAN_TOURIST_MOBILE', 'WORLD_HUMAN_VEHICLE_MECHANIC', 'WORLD_HUMAN_WELDING',
    'WORLD_HUMAN_WINDOW_SHOP_BROWSE', 'WORLD_HUMAN_YOGA', 'WORLD_HUMAN_JANITOR', 'WORLD_HUMAN_MAID_CLEAN', 'WORLD_HUMAN_SECURITY_SHINE_TORCH',
    'WORLD_HUMAN_BINOCULARS', 'WORLD_HUMAN_PAPARAZZI', 'PROP_HUMAN_SEAT_BENCH', 'PROP_HUMAN_SEAT_CHAIR', 'CODE_HUMAN_MEDIC_KNEEL',
    'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 'CODE_HUMAN_POLICE_INVESTIGATE', 'CODE_HUMAN_CROSS_ROAD_WAIT'],
  anim: [
    ['amb@world_human_hang_out_street@male_b@idle_a', 'idle_b', 'Hanging about'],
    ['missminuteman_1ig_2', 'handsup_base', 'Hands up'],
    ['random@arrests@busted', 'idle_a', 'Kneeling, hands on head'],
    ['amb@code_human_cower@male@base', 'base', 'Cowering'],
    ['mp_arresting', 'idle', 'Hands behind back'],
    ['combat@damage@writhe', 'writhe_loop', 'Writhing in pain'],
    ['timetable@floyd@cryingonbed@base', 'base', 'Crying'],
    ['anim@mp_player_intcelebrationmale@face_palm', 'face_palm', 'Face palm'],
    ['amb@world_human_bum_slumped@male@laying_on_left_side@base', 'base', 'Lying down'],
  ],
};

const PAINTS = [[0, 'Black'], [1, 'Graphite'], [4, 'Silver'], [27, 'Red'], [28, 'Torino red'], [38, 'Orange'], [42, 'Yellow'], [49, 'Dark green'],
  [53, 'Green'], [62, 'Dark blue'], [64, 'Blue'], [70, 'Bright blue'], [96, 'Brown'], [111, 'White'], [112, 'Frost white'], [135, 'Hot pink'], [145, 'Purple']];

const SECRETS = [['', 'Random'], ['clean', 'Clean'], ['nervous', 'Nervous'], ['drunk', 'Drunk'], ['drugs', 'On drugs / carrying'], ['warrant', 'Has a warrant'],
  ['unlicensed', 'No licence'], ['suspended', 'Licence suspended']];
const DEMEANORS = [['', 'Random'], ['polite', 'Polite'], ['nervous', 'Nervous'], ['rude', 'Rude'], ['chatty', 'Chatty']];
const DAMAGE = [['', 'None'], ['dent', 'Small dent'], ['rear', 'Rear smashed'], ['side', 'Side smashed'], ['front', 'Front smashed in'], ['wreck', 'Wrecked, smoking']];

// The usual questions someone can be asked, whose answer a callout person's lines can replace.
const USUAL_Q = [['where', 'Where are you headed?'], ['from', 'Where are you coming from?'], ['live', 'Do you live around here?'],
  ['work', 'What do you do for work?'], ['hurry', 'Are you in a hurry today?'], ['nervous', 'You seem nervous. Is everything okay?'],
  ['drugsincar', 'Any drugs on you?'], ['weapons', 'Are you carrying any weapons?'], ['arrested', 'Have you ever been arrested?'],
  ['probation', 'Are you on probation or parole?'], ['warrants', 'Do you have any warrants out for you?']];

// A field: [key, label, type, options?, hint?]. Types: text, long, num, bool, sel (options), person, person?, car, clue, point,
// point?, thing (person, car or clue), objective, question (of the rule's person), fact, story, asset:<kind>.
const EVENTS = {
  build: { label: 'The scene is made (a unit gets close)', f: [] },
  arrive: { label: 'A unit arrives on scene', f: [] },
  contact: { label: 'An officer starts talking to someone', f: [['who', 'Who', 'person?']] },
  ask: { label: 'Someone is asked a question', f: [['who', 'Who', 'person'], ['q', 'Question', 'question']] },
  act: { label: 'An officer does something with someone', f: [['who', 'Who', 'person?'], ['action', 'What', 'sel', [['', 'Anything'],
    ['licence', 'Asks for ID'], ['frisk', 'Frisks them'], ['search', 'Searches them'], ['breath', 'Breath test'], ['cuff', 'Cuffs them'],
    ['uncuff', 'Uncuffs them'], ['cite', 'Tickets them'], ['warn', 'Warns them'], ['release', 'Lets them go'], ['escort', 'Escorts them'], ['seat', 'Seats them in a car']]]] },
  fact: { label: 'Someone gives a fact away', f: [['who', 'Who', 'person?'], ['fact', 'Fact', 'fact'], ['value', 'Value (empty: any)', 'text']] },
  contact_ended: { label: 'A conversation ends', f: [['who', 'Who', 'person?'], ['outcome', 'How', 'sel', [['', 'Any way'], ['released', 'Let go'],
    ['cited', 'Ticketed'], ['warning', 'Warned'], ['arrested', 'Arrested'], ['fled', 'Ran off'], ['cancelled', 'Officer walked off']]]] },
  inspect: { label: 'Evidence is looked at (first time)', f: [['clue', 'Clue', 'clue?']] },
  plate: { label: 'A car\'s plate is run', f: [['car', 'Car', 'car?']] },
  custody: { label: 'A prisoner is taken in', f: [['who', 'Who', 'person?'], ['how', 'How', 'sel', [['', 'Any way'], ['booked', 'Booked at a station'], ['transport', 'Prisoner transport']]]] },
  aid: { label: 'Someone hurt is seen to', f: [['who', 'Who', 'person?'], ['what', 'What', 'sel', [['', 'Anything'], ['vitals', 'Vitals checked'],
    ['pressure', 'Pressure applied'], ['cpr', 'CPR'], ['narcan', 'Narcan'], ['hospital', 'Taken to hospital'], ['treated', 'Treated'],
    ['stabilised', 'Stabilised'], ['delivered', 'Delivered to hospital'], ['pronounced', 'Pronounced dead']]]] },
  dead: { label: 'Someone dies', f: [['who', 'Who', 'person?']] },
  gone: { label: 'Someone is gone (taken away or deleted)', f: [['who', 'Who', 'person?']] },
  hail: { label: 'Someone armed or fighting is told to drop it', f: [['who', 'Who', 'person?']] },
  aimed: { label: 'An officer points a gun at someone', f: [['who', 'Who', 'person?']] },
  fired: { label: 'Someone told to shoot really fires', f: [['who', 'Who', 'person?']] },
  stunned: { label: 'Someone fighting is tased', f: [['who', 'Who', 'person?']] },
  parked: { label: 'Someone told to drive gets there and gets out', f: [['who', 'Who', 'person?']] },
  dragged: { label: 'A dragged clue is let go', f: [['clue', 'Clue', 'clue?'], ['clear', 'Only when off the road', 'bool']] },
  tow: { label: 'A tow truck is called or called off', f: [['car', 'Car', 'car?'], ['stage', 'When', 'sel', [['', 'Either'], ['coming', 'On its way'], ['off', 'Called off']]]] },
  towed: { label: 'A car is towed away', f: [['car', 'Car', 'car?']] },
  service: { label: 'A backup unit finishes its job', f: [['kind', 'Which', 'sel', [['', 'Any'], ['dot', 'Road crew'], ['fire', 'Fire department'], ['taxi', 'Taxi']]]] },
  leave: { label: 'A unit leaves the call', f: [] },
  near: { label: 'A unit gets near', f: [['who', 'Near who (empty: the scene)', 'person?'], ['m', 'Within (m)', 'num']] },
  timer: { label: 'Time passes', f: [['s', 'Seconds after the call opens', 'num']] },
};

const CONDS = {
  fact: { label: 'They know a fact', f: [['who', 'Who (empty: them)', 'person?'], ['fact', 'Fact', 'fact'], ['value', 'Value (empty: any)', 'text']] },
  nofact: { label: 'They don\'t know a fact', f: [['who', 'Who (empty: them)', 'person?'], ['fact', 'Fact', 'fact'], ['value', 'Value (empty: any)', 'text']] },
  flag: { label: 'A flag is set', f: [['flag', 'Flag', 'text']] },
  noflag: { label: 'A flag is not set', f: [['flag', 'Flag', 'text']] },
  done: { label: 'An objective is done', f: [['objective', 'Objective', 'objective']] },
  notdone: { label: 'An objective is not done', f: [['objective', 'Objective', 'objective']] },
  cuffed: { label: 'They are cuffed', f: [['who', 'Who (empty: them)', 'person?']] },
  notcuffed: { label: 'They are not cuffed', f: [['who', 'Who (empty: them)', 'person?']] },
  near: { label: 'A unit is near', f: [['who', 'Near who (empty: the scene)', 'person?'], ['m', 'Within (m)', 'num']] },
  talking: { label: 'An officer is talking to them', f: [['who', 'Who (empty: anyone)', 'person?']] },
  nottalking: { label: 'Nobody is talking to them', f: [['who', 'Who (empty: anyone)', 'person?']] },
  apart: { label: 'Two people are out of earshot', f: [['who', 'One', 'person'], ['other', 'The other', 'person']] },
  chance: { label: 'A chance', f: [['p', 'In 100', 'num']] },
};

const TASKS = [['flee', 'Run away'], ['surrender', 'Give up (hands up)'], ['wander', 'Wander off'], ['scene', 'Back to what they were doing'],
  ['go', 'Walk to a point'], ['drive', 'Get in a car and drive'], ['aim', 'Point their weapon at someone'], ['hold', 'Hold their weapon, waiting'],
  ['brawl', 'Fight someone, with fists'], ['spray', 'Fire bursts over a point'], ['shoot', 'Fight every officer near']];

const ACTIONS = {
  done: { label: 'Mark an objective done', f: [['id', 'Objective', 'objective']] },
  reveal: { label: 'Show a hidden objective or clue', f: [['id', 'Objective or clue', 'objective+clue']] },
  hide: { label: 'Hide an objective again', f: [['id', 'Objective', 'objective']] },
  blip: { label: 'Change what an objective marks on the map', f: [['id', 'Objective', 'objective'], ['keys', 'Marks', 'things']] },
  say: { label: 'Someone shouts a line (heard within 30 m)', f: [['who', 'Who', 'person?'], ['text', 'Line', 'long']] },
  dispatch: { label: 'Dispatch radios every unit', f: [['text', 'Message', 'long']] },
  note: { label: 'A line on the MDT incident', f: [['text', 'Note', 'long']] },
  tell: { label: 'The officer notices something (a card)', f: [['title', 'Title', 'text'], ['text', 'What they notice', 'long']] },
  give: { label: 'Someone now knows a fact', f: [['who', 'Who (empty: them)', 'person?'], ['fact', 'Fact', 'fact'], ['value', 'Value (empty: yes)', 'text']] },
  flag: { label: 'Set or clear a flag', f: [['flag', 'Flag', 'text'], ['clear', 'Clear it instead', 'bool']] },
  task: { label: 'Someone does something', f: [['who', 'Who (empty: them)', 'person?'], ['task', 'What', 'sel', TASKS], ['point', 'Point', 'point?'],
    ['other', 'At / with', 'person?'], ['car', 'Car', 'car?'], ['fast', 'Flat out', 'bool']] },
  custody: { label: 'Put "take them in" on the card', f: [['who', 'Who (empty: them)', 'person?']] },
  warrant: { label: 'Put a warrant on their record (empty: clear it)', f: [['who', 'Who (empty: them)', 'person?'], ['text', 'Warrant', 'text']] },
  file: { label: 'Their record goes on the MDT incident now', f: [['who', 'Who (empty: them)', 'person?']] },
  collapse: { label: 'They collapse, hurt', f: [['who', 'Who (empty: them)', 'person?'], ['vitals', 'What Check vitals says', 'text']] },
  die: { label: 'They die', f: [['who', 'Who (empty: them)', 'person?']] },
  remove: { label: 'They get clean away (gone)', f: [['who', 'Who (empty: them)', 'person?'], ['car', 'With their car', 'car?']] },
  hangup: { label: 'End the conversation with them', f: [['who', 'Who (empty: them)', 'person?']] },
  patient: { label: 'They go with paramedics', f: [['who', 'Who (empty: them)', 'person?']] },
  fare: { label: 'They wait for a taxi', f: [['who', 'Who (empty: them)', 'person?']] },
  bang: { label: 'A real shot or firework from a point (nobody hurt)', f: [['weapon', 'Weapon', 'asset:weapon'], ['point', 'From', 'point'], ['shots', 'Shots', 'num']] },
  clear: { label: 'A clue is dealt with', f: [['clue', 'Clue', 'clue'], ['keep', 'Leave the prop there', 'bool']] },
  wait: { label: 'Wait, then do the rest', f: [['s', 'Seconds', 'num']] },
  finish: { label: 'End the call now, with a summary', f: [['text', 'MDT summary', 'long']] },
};

const PRESETS = {
  brawl: { label: 'Fight: two people really fighting', hint: 'Told to stop, they stop "chance" in 100 times; a taser always stops it. Left too long, one goes down hurt.',
    f: [['who', 'One', 'person'], ['other', 'The other', 'person'], ['objective', 'Marks done when it stops', 'objective?'], ['chance', 'Stop when told (in 100)', 'num'],
      ['line', 'What they say stopping', 'text'], ['defy', 'What they say when they don\'t', 'text']] },
  standoff: { label: 'Standoff: weapon out, waiting', hint: 'Nobody can talk to them until they give up. Told to drop it, they do "chance" in 100 times; a taser always works.',
    f: [['who', 'Who', 'person'], ['other', 'On who (empty: just held)', 'person?'], ['objective', 'Marks done when they give up', 'objective?'],
      ['chance', 'Drop it when told (in 100)', 'num'], ['line', 'What they say giving up', 'text'], ['defy', 'What they say when they don\'t', 'text']] },
  shootout: { label: 'Shootout: may open fire, then gives up', hint: 'When a unit gets close they open fire "chance" in 100 times, and fight until hurt, out of time, or told to drop it.',
    f: [['who', 'Who', 'person'], ['point', 'Fires from (empty: where they stand)', 'point?'], ['near', 'Reacts within (m)', 'num'],
      ['chance', 'Opens fire (in 100)', 'num'], ['objective', 'Marks done when it\'s over', 'objective?'], ['line', 'What they say giving up', 'text']] },
  spray: { label: 'Shooting in the air', hint: 'Bursts aimed high over a point while units are near, until told to drop it ("chance" in 100) or tased.',
    f: [['who', 'Who', 'person'], ['point', 'Over', 'point'], ['objective', 'Marks done when they stop', 'objective?'], ['chance', 'Stop when told (in 100)', 'num'],
      ['line', 'What they say stopping', 'text'], ['defy', 'What they say when they don\'t', 'text']] },
  bolt: { label: 'Runs when asked for ID', hint: 'Asked for their ID, they run for it "chance" in 100 times.',
    f: [['who', 'Who', 'person'], ['chance', 'Runs (in 100)', 'num'], ['line', 'What they shout', 'text']] },
};

const ENDINGS = [['subject', 'When the person it\'s about is dealt with'], ['arrests', 'When everyone arrested is taken in'], ['heard', 'When someone has been heard and every unit has left']];
const END_LINES = [['arrested', 'Arrested'], ['cited', 'Ticketed'], ['warning', 'Warned'], ['released', 'Let go'], ['fled', 'Got away'], ['dead', 'Died'],
  ['gone', 'Left the scene'], ['left', 'Every unit left']];
