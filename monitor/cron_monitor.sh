#! /usr/bin/env bash
# set -x
# set -e
post_test_notification(){
    curl -X POST https://discord.com/api/webhooks/970347000719609866/To3ULCRUJ9SCusjVUvyLCGrifSCAvH6VTowKJlUOP6rUDQeUxgLmL3XWMY_CRcYYWHRe \
        -H 'Content-Type: application/json' \
        -d '{"embeds":[{"color":"14365807","title":"cron","type":"rich","description":"Cron executed","fields":[{"name":"source","value":"db"},{"name":"time","value":"2022-10-06 12:00:00"},{"name":"status","value":"failed"},{"name":"size","value":"450MB"},{"name":"frequency","value":"hourly"}]}]}'
}
