fx_version 'cerulean'
game 'rdr3'

rdr3_warning 'I acknowledge that this is a pre-release game build.'

author 'Codex'
description 'Persistent public farming for VORP / RedM'
version '0.1.0'

ui_page 'html/index.html'

shared_script 'config.lua'
client_script 'client.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependencies {
    'vorp_core',
    'vorp_inventory',
    'oxmysql'
}

files {
    'html/index.html',
    'html/styles.css',
    'html/app.js',
    'docs/animation-integrations.md'
}
