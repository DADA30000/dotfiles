set -x
export PATH="/run/wrappers/bin:$PATH"
mkdir -p "$HOME/Documents/Replays"

for status_file in /sys/class/drm/*/status; do
  if grep -q '^connected' "$status_file"; then
    mon=$(basename "$(dirname "$status_file")" | sed -E 's/^card[0-9]+-//')
    if [ -n "$mon" ]; then
      mkdir -p "$HOME/Documents/Replays/$mon"
      gpu-screen-recorder -w "$mon" -s 1920x1080 -k hevc -q ultra -a default_output -a default_input -f 60 -r 300 -c mkv -o "$HOME/Documents/Replays/$mon" &
    fi
  fi
done

wait
