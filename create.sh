#! /bin/sh
echo Do not even try to use it as is. Adapt it to your conficuration
exit 1

sudo zfs program -j pool ./rsnapshot.lua pool /path/to/backup/folder > snapshot.json
jq -rS '.return[].mount' snapshot.json | jq -r '.[]' | sudo /bin/sh
