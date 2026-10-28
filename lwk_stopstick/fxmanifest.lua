fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lwk_stopstick'
description 'Throwable Stop Stick: toss the folded sleeve, pull it into the lane on its cord, yank it clear'
version '0.0.1'

shared_scripts { 'config.lua', 'shared/tow.lua' }
client_script 'client/main.lua'
server_script 'server/main.lua'

-- stream/: lwk_stopstick_a/b/c (the deployed sleeve's 3 jointed sticks), lwk_stopstick_folded (thrown pack), lwk_stopstick_reel (cord reel),
-- lwk_stopstick@anims.ycd (throw + pull clips). Built by models/*.py.
data_file 'DLC_ITYP_REQUEST' 'stream/lwk_stopstick_a.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/lwk_stopstick_b.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/lwk_stopstick_c.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/lwk_stopstick_folded.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/lwk_stopstick_reel.ytyp'
