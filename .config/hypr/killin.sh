#!/usr/bin/env bash
iterate () {
    strr=$(ps -o ppid,cmd -U l0lk3k | grep ytstart.sh | awk '{print $1}')
    srt="${strr//$'\n'/ }"
    srtt=($srt)
    pkill .ytfzf-wrapped
    pkill mpv
    for var in "${srtt[@]}"
    do
	pkill -15 -P $var
    done
}
iterate
