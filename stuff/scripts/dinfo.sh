PROCPS='%{{{pkgs.procps}}}'

Kernel="$(uname -r)"
uptime="$("$PROCPS/bin/uptime" -p | sed 's/up //')"

tooltip+="<b>SystemInfo:</b>\n"
tooltip+="Kernel: $Kernel\n"
tooltip+="Uptime: $uptime"

cat <<EOF
{ "text":"", "tooltip":"$tooltip", "class":""}
EOF
