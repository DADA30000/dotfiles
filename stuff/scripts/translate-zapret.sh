SOURCE="$1"
TARGET="$2"
TARGET_DIR="$(dirname "$TARGET")"

if [ -z "$TARGET" ]; then
  echo "Usage: $0 <script_to_translate> <out_path>"
  exit 1
fi

mkdir -p "$TARGET_DIR"/lists
touch "$TARGET_DIR"/lists/ipset-exclude-user.txt
touch "$TARGET_DIR"/lists/list-exclude-user.txt
touch "$TARGET_DIR"/lists/list-general-user.txt
cp "$SOURCE" "$TARGET"

sed -i 's$start "zapret: %~n0" /min "%BIN%winws.exe"$nfqws --qnum=210$g' "$TARGET"
sed -i "s/%GameFilter%,//g; s/,%GameFilter%//g; s/%GameFilter%//g" "$TARGET"
sed -i $'s/\r//g' "$TARGET"
sed -i 's$\^$ \\$g' "$TARGET"
sed -i 's/ --/ \\\n--/g' "$TARGET"
sed -i '/^--comment/d' "$TARGET"
sed -i "s/--wf-udp/--filter-udp/g" "$TARGET"
sed -i "s/--wf-tcp/--filter-tcp/g" "$TARGET"
sed -i 's/--filter-udp=%GameFilterUDP%//g' "$TARGET"
sed -i 's/--filter-tcp=%GameFilterTCP%//g' "$TARGET"
sed -i 's$,%GameFilterUDP%$$g' "$TARGET"
sed -i 's$,%GameFilterTCP%$$g' "$TARGET"
sed -i 's&%LISTS%&$(dirname "$0")/lists/&g' "$TARGET"
sed -i 's&%BIN%&$(dirname "$0")/bin/&g' "$TARGET"
sed -i '/^[[:space:]]*\\*$/d' "$TARGET"
sed -i '$ s/ \\$//' "$TARGET"
sed -i "/--filter-tcp= /d" "$TARGET"
sed -i "/--filter-udp= /d" "$TARGET"
sed -i -n '/nfqws/,$p' "$TARGET"
sed -i -E 's/ +/ /g' "$TARGET"

TMP_FILE=$(mktemp)
cat <<EOF >"$TMP_FILE"
#!/usr/bin/env bash

iptables -t mangle -C OUTPUT -p tcp -m multiport --dports 80,443,853,2053,2083,2087,2096,8443 -j NFQUEUE --queue-num 210 --queue-bypass 2>/dev/null || \\
iptables -t mangle -I OUTPUT -p tcp -m multiport --dports 80,443,853,2053,2083,2087,2096,8443 -j NFQUEUE --queue-num 210 --queue-bypass

iptables -t mangle -C OUTPUT -p udp --dport 53:65535 -j NFQUEUE --queue-num 210 --queue-bypass 2>/dev/null || \\
iptables -t mangle -I OUTPUT -p udp --dport 53:65535 -j NFQUEUE --queue-num 210 --queue-bypass

EOF

cat "$TARGET" >>"$TMP_FILE"
mv "$TMP_FILE" "$TARGET"
chmod +x "$TARGET"

echo "Successfully translated $TARGET"
