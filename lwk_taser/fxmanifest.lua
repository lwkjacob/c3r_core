fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lwk_taser'
author 'LWK DEVELOPMENT'
version '0.0.1'
description 'TASER 10-style taser: 10-probe magazine, barbs, CID, laser, flashlight, drive stun, audit trail'

dependency 'ox_target'

shared_script 'config.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'

-- stream/: w_pi_stungun* (TASER 10 replacement for the stun gun, cartridge removed), lwk_taser_cart (cartridge),
-- lwk_taser_probe (barb), lwk_taser_screen (live rear display), lwk_taser@reload.ycd (cartridge-swap clip)
data_file 'DLC_ITYP_REQUEST' 'stream/lwk_taser_probe.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/lwk_taser_cart.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/lwk_taser_screen.ytyp'

ui_page 'nui/index.html'
files { 'nui/index.html', 'nui/cid.html', 'nui/sounds/*.ogg' }
