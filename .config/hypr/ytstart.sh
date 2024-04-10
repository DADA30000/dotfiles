#!/usr/bin/env bash
export invidious_instance="https://vid.lilay.dev"
atype=$(echo -e "video\naudio\nkill"| tofi --prompt-text="type: ")
if [[ $atype == "video" ]]
    then
            commando='ytfzf --rii -c youtube -D "$search"'
fi
if [[ $atype == "audio" ]]
    then
	    commando='ytfzf --rii -m -c youtube -D "$search"'
fi
if [[ $atype == "kill" ]]
    then
	    exec ~/.config/hypr/killin.sh
	    exit 1
fi
search=$(:| tofi --prompt-text="search: ")
first () {
until eval "$commando"
    do
        read -r line
        [[ $line == "[ERROR]*" ]] && second
    done
}
first
second () {
until eval "$commando"
    do
        read -r line
	[[ $line == "[ERROR]*" ]] && first
    done
}
