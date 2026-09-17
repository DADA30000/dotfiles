SOURCE="$1"
TARGET="$2"

if [ -z "$TARGET" ]; then
  echo "Usage: $0 <script_to_translate> <out_path>"
  exit 1
fi

translate-zapret "$SOURCE" "$TARGET"

sed -i 's/\\$//' "$TARGET"
sed -i 's/\$(dirname "$0")/\$(dirname_TEMP_0)/g' "$TARGET"
sed -i 's%$(dirname_TEMP_0)%\%{{{inputs.zapret-flowseal}}}%g' "$TARGET"
sed -i "s/\"/'/g" "$TARGET"
sed -i -E 's/ +/ /g' "$TARGET"
sed -i '/user\.txt/d' "$TARGET"
sed -i '1,/--qnum=210/d' "$TARGET"
sed -i 's/^[[:space:]]*//; s/[[:space:]]*$//; s/.*/"&"/' "$TARGET"
sed -i '$! s/$/ \\/' "$TARGET"
sed -i "s/'//g" "$TARGET"
