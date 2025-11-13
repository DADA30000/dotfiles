{ pkgs, user, ... }:
let
  scripts = [
    (pkgs.writers.writePython3Bin "krisp-patcher"
      {
        libraries = with pkgs.python3Packages; [
          capstone
          pyelftools
        ];
        flakeIgnore = [
          "E501" # line too long (82 > 79 characters)
          "F403" # 'from module import *' used; unable to detect undefined names
          "F405" # name may be undefined, or defined from star imports: module
        ];
      }
      ''
        import sys
        import shutil

        from elftools.elf.elffile import ELFFile
        from capstone import *
        from capstone.x86 import *

        if len(sys.argv) < 2:
            print(f"Usage: {sys.argv[0]} [path to discord_krisp.node]")
            # "Unix programs generally use 2 for command line syntax errors and 1 for all other kind of errors."
            sys.exit(2)

        executable = sys.argv[1]

        elf = ELFFile(open(executable, "rb"))
        symtab = elf.get_section_by_name('.symtab')

        krisp_initialize_address = symtab.get_symbol_by_name("_ZN7discordL17DoKrispInitializeEv")[0].entry.st_value
        isSignedByDiscord_address = symtab.get_symbol_by_name("_ZN7discord4util17IsSignedByDiscordERKNSt4__Cr12basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE")[0].entry.st_value

        text = elf.get_section_by_name('.text')
        text_start = text['sh_addr']
        text_start_file = text['sh_offset']
        # This seems to always be zero (.text starts at the right offset in the file). Do it just in case?
        address_to_file = text_start_file - text_start

        # Done with the ELF now.
        # elf.close()

        krisp_initialize_offset = krisp_initialize_address - address_to_file
        isSignedByDiscord_offset = krisp_initialize_address - address_to_file

        f = open(executable, "rb")
        f.seek(krisp_initialize_offset)
        krisp_initialize = f.read(256)
        f.close()

        # States
        found_issigned_by_discord_call = False
        found_issigned_by_discord_test = False
        found_issigned_by_discord_je = False
        found_already_patched = False
        je_location = None
        je_size = 0

        # We are looking for a call to IsSignedByDiscord, followed by a test, followed by a je.
        # Then we replace the je with nops.

        md = Cs(CS_ARCH_X86, CS_MODE_64)
        md.detail = True
        for i in md.disasm(krisp_initialize, krisp_initialize_address):
            if i.id == X86_INS_CALL:
                if i.operands[0].type == X86_OP_IMM:
                    if i.operands[0].imm == isSignedByDiscord_address:
                        found_issigned_by_discord_call = True

            if i.id == X86_INS_TEST:
                if found_issigned_by_discord_call:
                    found_issigned_by_discord_test = True

            if i.id == X86_INS_JE:
                if found_issigned_by_discord_test:
                    found_issigned_by_discord_je = True
                    je_location = i.address
                    je_size = len(i.bytes)
                    break

            if i.id == X86_INS_NOP:
                if found_issigned_by_discord_test:
                    found_already_patched = True
                    break

        if je_location:
            print(f"Found patch location: 0x{je_location:x}")

            shutil.copyfile(executable, executable + ".orig")
            f = open(executable, 'rb+')
            f.seek(je_location - address_to_file)
            f.write(b'\x90' * je_size)   # je can be larger than 2 bytes given a large enough displacement :(
            f.close()
        else:
            if found_already_patched:
                print("Couldn't find patch location - already patched.")
            else:
                print("Couldn't find patch location - review manually. Sorry.")
      ''
    )
    (pkgs.writeShellScriptBin "dinfo" ''
      Kernel="$(uname -r)"
      uptime="$(uptime -p | sed 's/up //')"

      tooltip+="<b>SystemInfo:</b>\n"
      tooltip+="Kernel: $Kernel\n"
      tooltip+="Uptime: $uptime"

      cat <<EOF
      { "text":"", "tooltip":"$tooltip", "class":""}
      EOF
    '')
    (pkgs.writeShellScriptBin "qemu-system-x86_64-uefi" ''
      qemu-system-x86_64 \
        -bios ''${pkgs.OVMF.fd}/FV/OVMF.fd \
        "$@"
    '')
    (pkgs.writeShellScriptBin "dmenu" ''
      rofi -dmenu "$@"
    '')
    (pkgs.writeShellScriptBin "gpu" ''
      usage=$(nvidia-smi | grep % | cut -b 73,74,75,76,77 | sed 's/ //g')
      temp=$(nvidia-smi | grep % | cut -b 9,10)
      text="<span color='#02a62d'>  $usage  󰢮 </span>"
      tooltip="GPU Usage: $usage\rGPU Temp: $temp°C"
      cat <<EOF
      {"text":"$text","tooltip":"$tooltip",}
      EOF
    '')
    (pkgs.writeShellScriptBin "amd-gpu" ''
      if test -f /sys/class/hwmon/hwmon0/device/gpu_busy_percent; then
        usage=$(cat /sys/class/hwmon/hwmon0/device/gpu_busy_percent)
        num=0
      elif test -f /sys/class/hwmon/hwmon1/device/gpu_busy_percent; then
        usage=$(cat /sys/class/hwmon/hwmon1/device/gpu_busy_percent)
        num=1
      elif test -f /sys/class/hwmon/hwmon2/device/gpu_busy_percent; then
        usage=$(cat /sys/class/hwmon/hwmon2/device/gpu_busy_percent)
        num=2
      elif test -f /sys/class/hwmon/hwmon3/device/gpu_busy_percent; then
        usage=$(cat /sys/class/hwmon/hwmon3/device/gpu_busy_percent)
        num=3
      elif test -f /sys/class/hwmon/hwmon4/device/gpu_busy_percent; then
        usage=$(cat /sys/class/hwmon/hwmon4/device/gpu_busy_percent)
        num=4
      fi
      name=$(lspci | grep VGA | cut -d ":" -f3 | cut -d "[" -f3 | cut -d "]" -f1)
      temp1=$(cat /sys/class/hwmon/hwmon''${num}/temp1_input)
      temp=$(echo $temp1 | rev | cut -c 4- | rev)
      text="<span color='#990000'>  ''${usage}%  󰢮 </span>"
      tooltip="$name\rGPU Usage: ''${usage}%\rGPU Temp: $temp°C"
      cat <<EOF
      {"text":"$text","tooltip":"$tooltip",}
      EOF
    '')
    (pkgs.writeShellScriptBin "nixos" ''
      cat <<EOF
      {"text":"<span color='#4575DA'> </span>","tooltip":"<span color='#4575DA'>⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\r⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⣿⣿⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\r⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\r⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⣿⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\r⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣷⣤⣙⢻⣿⣿⣿⣿⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀\r⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡀⠀⠀⠀⠀⠀⠀⠀⠀\r⠀⠀⠀⠀⠀⠀⠀⢠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⡄⠀⠀⠀⠀⠀⠀⠀\r⠀⠀⠀⠀⠀⠀⢠⣿⣿⣿⣿⣿⡿⠛⠛⠿⣿⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀\r⠀⠀⠀⠀⠀⢠⣿⣿⣿⣿⣿⠏⠀⠀⠀⠀⠙⣿⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀\r⠀⠀⠀⠀⣰⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⢿⣿⣿⣿⣿⠿⣆⠀⠀⠀⠀\r⠀⠀⠀⣴⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⣷⣦⡀⠀⠀⠀\r⠀⢀⣾⣿⣿⠿⠟⠛⠋⠉⠉⠀⠀⠀⠀⠀⠀⠉⠉⠙⠛⠻⠿⣿⣿⣷⡀⠀\r⣠⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠻⣄</span>",}
      EOF
    '')
    (pkgs.writeShellScriptBin "nixos.sh" ''
      echo -n $'\E[34m'
      cat << "EOF"
               _  _ _      ___  ___ 
           							      | \| (_)_ __/ _ \/ __|
        							      | .` | \ \ / (_) \__ \
         					 		      |_|\_|_/_\_\\___/|___/
      EOF
    '')
    (pkgs.writeShellScriptBin "update-cloudflare-dns" ''
      FILE=/update-cloudflare-dns.log
      if ! [ -x "$FILE" ]; then
        touch "$FILE"
      fi

      LOG_FILE='/update-cloudflare-dns.log'

      ### Write last run of STDOUT & STDERR as log file and prints to screen
      exec > >(tee $LOG_FILE) 2>&1
      echo "==> $(date "+%Y-%m-%d %H:%M:%S")"

      ### Validate if config-file exists

      if [[ -z "$1" ]]; then
        if ! source /update-cloudflare-dns.conf; then
          echo 'Error! Missing configuration file update-cloudflare-dns.conf or invalid syntax!'
          exit 0
        fi
      else
        if ! source "$1"; then
          echo 'Error! Missing configuration file '$1' or invalid syntax!'
          exit 0
        fi
      fi

      ### Check validity of "ttl" parameter
      if [ "''${ttl}" -lt 120 ] || [ "''${ttl}" -gt 7200 ] && [ "''${ttl}" -ne 1 ]; then
        echo "Error! ttl out of range (120-7200) or not set to 1"
        exit
      fi

      ### Check validity of "proxied" parameter
      if [ "''${proxied}" != "false" ] && [ "''${proxied}" != "true" ]; then
        echo 'Error! Incorrect "proxied" parameter, choose "true" or "false"'
        exit 0
      fi

      ### Check validity of "what_ip" parameter
      if [ "''${what_ip}" != "external" ] && [ "''${what_ip}" != "internal" ]; then
        echo 'Error! Incorrect "what_ip" parameter, choose "external" or "internal"'
        exit 0
      fi

      ### Check if set to internal ip and proxy
      if [ "''${what_ip}" == "internal" ] && [ "''${proxied}" == "true" ]; then
        echo 'Error! Internal IP cannot be proxied'
        exit 0
      fi

      ### Valid IPv4 Regex
      REIP='^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])\.){3}(25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])$'

      ### Get external ip from https://checkip.amazonaws.com
      if [ "''${what_ip}" == "external" ]; then
        ip=$(curl -4 -s -X GET https://checkip.amazonaws.com --max-time 10)
        if [ -z "$ip" ]; then
          echo "Error! Can't get external ip from https://checkip.amazonaws.com"
          exit 0
        fi
        if ! [[ "$ip" =~ $REIP ]]; then
          echo "Error! IP Address returned was invalid!"
          exit 0
        fi
        echo "==> External IP is: $ip"
      fi

      ### Get Internal ip from primary interface
      if [ "''${what_ip}" == "internal" ]; then
        ### Check if "IP" command is present, get the ip from interface
        if which ip >/dev/null; then
          ### "ip route get" (linux)
          interface=$(ip route get 1.1.1.1 | awk '/dev/ { print $5 }')
          ip=$(ip -o -4 addr show ''${interface} scope global | awk '{print $4;}' | cut -d/ -f 1)
        ### If no "ip" command use "ifconfig" instead, to get the ip from interface
        else
          ### "route get" (macOS, Freebsd)
          interface=$(route get 1.1.1.1 | awk '/interface:/ { print $2 }')
          ip=$(ifconfig ''${interface} | grep 'inet ' | awk '{print $2}')
        fi
        if [ -z "$ip" ]; then
          echo "Error! Can't read ip from ''${interface}"
          exit 0
        fi
        echo "==> Internal ''${interface} IP is: $ip"
      fi

      ### Build coma separated array fron dns_record parameter to update multiple A records
      IFS=',' read -d "" -ra dns_records <<<"$dns_record,"
      unset 'dns_records[''${#dns_records[@]}-1]'
      declare dns_records

      for record in "''${dns_records[@]}"; do
        ### Get IP address of DNS record from 1.1.1.1 DNS server when proxied is "false"
        if [ "''${proxied}" == "false" ]; then
          ### Check if "nslookup" command is present
          if which nslookup >/dev/null; then
            dns_record_ip=$(nslookup ''${record} 1.1.1.1 | awk '/Address/ { print $2 }' | sed -n '2p')
          else
            ### if no "nslookup" command use "host" command
            dns_record_ip=$(host -t A ''${record} 1.1.1.1 | awk '/has address/ { print $4 }' | sed -n '1p')
          fi

          if [ -z "$dns_record_ip" ]; then
            echo "Error! Can't resolve the ''${record} via 1.1.1.1 DNS server"
            exit 0
          fi
          is_proxed="''${proxied}"
        fi

        ### Get the dns record id and current proxy status from Cloudflare API when proxied is "true"
        if [ "''${proxied}" == "true" ]; then
          dns_record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=A&name=$record" \
            -H "Authorization: Bearer $cloudflare_zone_api_token" \
            -H "Content-Type: application/json")
          if [[ ''${dns_record_info} == *"\"success\":false"* ]]; then
            echo ''${dns_record_info}
            echo "Error! Can't get dns record info from Cloudflare API"
            exit 0
          fi
          is_proxed=$(echo ''${dns_record_info} | grep -o '"proxied":[^,]*' | grep -o '[^:]*$')
          dns_record_ip=$(echo ''${dns_record_info} | grep -o '"content":"[^"]*' | cut -d'"' -f 4)
        fi

        ### Check if ip or proxy have changed
        if [ ''${dns_record_ip} == ''${ip} ] && [ ''${is_proxed} == ''${proxied} ]; then
          echo "==> DNS record IP of ''${record} is ''${dns_record_ip}", no changes needed.
          continue
        fi

        echo "==> DNS record of ''${record} is: ''${dns_record_ip}. Trying to update..."

        ### Get the dns record information from Cloudflare API
        cloudflare_record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=A&name=$record" \
          -H "Authorization: Bearer $cloudflare_zone_api_token" \
          -H "Content-Type: application/json")
        if [[ ''${cloudflare_record_info} == *"\"success\":false"* ]]; then
          echo ''${cloudflare_record_info}
          echo "Error! Can't get ''${record} record information from Cloudflare API"
          exit 0
        fi

        ### Get the dns record id from response
        cloudflare_dns_record_id=$(echo ''${cloudflare_record_info} | grep -o '"id":"[^"]*' | cut -d'"' -f4)

        ### Push new dns record information to Cloudflare API
        update_dns_record=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$cloudflare_dns_record_id" \
          -H "Authorization: Bearer $cloudflare_zone_api_token" \
          -H "Content-Type: application/json" \
          --data "{\"type\":\"A\",\"name\":\"$record\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied}")
        if [[ ''${update_dns_record} == *"\"success\":false"* ]]; then
          echo ''${update_dns_record}
          echo "Error! Update failed"
          exit 0
        fi

        echo "==> Success!"
        echo "==> $record DNS Record updated to: $ip, ttl: $ttl, proxied: $proxied"

        ### Telegram notification
        if [ ''${notify_me_telegram} == "no" ]; then
          exit 0
        fi

        if [ ''${notify_me_telegram} == "yes" ]; then
          telegram_notification=$(
            curl -s -X GET "https://api.telegram.org/bot''${telegram_bot_API_Token}/sendMessage?chat_id=''${telegram_chat_id}" --data-urlencode "text=''${record} DNS record updated to: ''${ip}"
          )
          if [[ ''${telegram_notification=} == *"\"ok\":false"* ]]; then
            echo ''${telegram_notification=}
            echo "Error! Telegram notification failed"
            exit 0
          fi
        fi
      done
    '')
    (pkgs.writeShellScriptBin "gamemode.sh" ''
      HYPRGAMEMODE=$(hyprctl getoption animations:enabled | awk 'NR==1{print $2}')
      if [ "$HYPRGAMEMODE" = 1 ] ; then
          hyprctl --batch "\
              keyword animations:enabled 0;\
              keyword decoration:drop_shadow 0;\
              keyword decoration:blur:enabled 0;\
              keyword general:gaps_in 0;\
              keyword general:gaps_out 0;\
              keyword general:border_size 0;\
      	keyword windowrule opacity 1 override 1 override, title:^(.*)$;\
              keyword decoration:rounding 0"
          systemctl --user stop waybar
          systemctl --user stop replays
          systemctl --user stop hyprpaper
          pkill hyprpaper
          exit
      fi
      hyprctl reload
      systemctl --user start replays
      systemctl --user start waybar
      systemctl --user start hyprpaper
      exit
    '')
    (pkgs.writeShellScriptBin "sheesh.sh" ''
      THE_MOUNT_POINT="$HOME/.local/state/nixos-config"
      USER_ID="$(id -u)"
      GROUP_ID="$(id -g)"
      USER_NAME="$(id -un)"
      USER_HOME="$HOME"
      WAYLAND_DISPLAY_VAR="$WAYLAND_DISPLAY"
      DISPLAY_VAR="$DISPLAY"
      XAUTHORITY_VAR="$XAUTHORITY"
      XDG_RUNTIME_DIR_VAR="$XDG_RUNTIME_DIR"

      pkexec unshare -m --propagation slave -- bash -c '
        MOUNT_POINT="$9"

        cleanup() {
          if findmnt -M "$MOUNT_POINT" > /dev/null; then
            umount "$MOUNT_POINT"
          fi
          if [ -d "$MOUNT_POINT" ]; then
            rmdir "$MOUNT_POINT"
          fi
        }

        trap cleanup EXIT

        mkdir -p "$MOUNT_POINT"
        chown "$1:$2" "$MOUNT_POINT"
        bindfs --force-user=$1 --force-group=$2 /etc/nixos "$MOUNT_POINT"

        runuser -u "$3" -- \
          env \
            HOME="$4" \
            WAYLAND_DISPLAY="$5" \
            DISPLAY="$6" \
            XAUTHORITY="$7" \
            XDG_RUNTIME_DIR="$8" \
            NEOVIDE_MOUNT_POINT="$MOUNT_POINT" \
            neovide "$MOUNT_POINT"

      ' bash "$USER_ID" "$GROUP_ID" "$USER_NAME" "$USER_HOME" "$WAYLAND_DISPLAY_VAR" "$DISPLAY_VAR" "$XAUTHORITY_VAR" "$XDG_RUNTIME_DIR_VAR" "$THE_MOUNT_POINT"
    '')
    (pkgs.writeShellScriptBin "finder.sh" ''
      if [ ! -z "$@" ]
      then
        QUERY=$@
        if [[ "$@" == /* ]]
        then
          if [[ "$@" == *\?\? ]]
          then
            coproc ( exo-open "''${QUERY%\/* \?\?}"  > /dev/null 2>&1 )
            exec 1>&-
            exit;
          else
            coproc ( exo-open "$@"  > /dev/null 2>&1 )
            exec 1>&-
            exit;
          fi
        elif [[ "$@" == \!\!* ]]
        then
          echo "!!-- Type your search query to find files"
          echo "!!-- To search again type !<search_query>"
          echo "!!-- To search parent directories type ?<search_query>"
          echo "!!-- You can print this help by typing !!"
        elif [[ "$@" == \?* ]]
        then
          echo "!!-- Type another search query"
          while read -r line; do
            echo "$line" \?\?
          done <<< $(find ~ -type d -path '*/\.*' -prune -o -not -name '.*' -type f -iname *"''${QUERY#\?}"* -print)
        else
          echo "!!-- Type another search query"
          find ~ -type d -path '*/\.*' -prune -o -not -name '.*' -type f -iname *"''${QUERY#!}"* -print
        fi
      else
        echo "!!-- Type your search query to find files"
        echo "!!-- To seach again type !<search_query>"
        echo "!!-- To seach parent directories type ?<search_query>"
        echo "!!-- You can print this help by typing !!"
      fi
    '')
    (pkgs.writeShellScriptBin "startup-sound" ''
      beep -f 130 -l 100 -n -f 262 -l 100 -n -f 330 -l 100 -n -f 392 -l 100 -n -f 523 -l 100 -n -f 660 -l 100 -n -f 784 -l 300 -n -f 660 -l 300 -n -f 146 -l 100 -n -f 262 -l 100 -n -f 311 -l 100 -n -f 415 -l 100 -n -f 523 -l 100 -n -f 622 -l 100 -n -f 831 -l 300 -n -f 622 -l 300 -n -f 155 -l 100 -n -f 294 -l 100 -n -f 349 -l 100 -n -f 466 -l 100 -n -f 588 -l 100 -n -f 699 -l 100 -n -f 933 -l 300 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 1047 -l 400
    '')
    (pkgs.writeShellScriptBin "update-damn-nixos" ''
      LOG_FILE="$HOME/.cache/nixos-rebuild.log"
      rm -f "$LOG_FILE"
      NOTIFY_ID=$(notify-send -p "Обновление" "Ожидание ввода пароля...")
      
      if [ -z "$NOTIFY_ID" ]; then
        echo "Could not create notification. Aborting." >&2
        exit 1
      fi
      
      pkexec nixos-rebuild switch -v &> "$LOG_FILE" &
      REBUILD_PID=$!
      time=0
      while [[ -d "/proc/$REBUILD_PID" ]]; do
        if [[ -s "$LOG_FILE" ]]; then
          notify-send -r "$NOTIFY_ID" "Обновление" "Обновление началось, прошло $time секунд"
          sleep 1
          time=$((time + 1))
        else
          sleep 0.1
        fi
      done
      
      wait "$REBUILD_PID"
      EXIT_CODE=$?
      
      kek() {
        if [[ $(notify-send -u critical -A "openlog=Открыть логи" "$1" "$2") == "openlog" ]]; then
          neovide -- -c "normal! G" "$LOG_FILE"
        fi
      }
      
      if [ $EXIT_CODE -eq 0 ]; then
        notify-send "Успех" "Система успешно обновлена."
      elif [ $EXIT_CODE -eq 1 ]; then
        kek "Ошибка сборки" "Произошла ошибка во время сборки. Лог: $LOG_FILE"
      elif [ $EXIT_CODE -eq 2 ]; then
        kek "Ошибка активации" "Сборка прошла успешно, но активация не удалась. Лог: $LOG_FILE"
      else
        kek "Неизвестная ошибка" "Произошла ошибка с кодом $EXIT_CODE. Лог: $LOG_FILE"
      fi
    '')
    (pkgs.writeShellScriptBin "toggle-restriction" ''
      if grep '    power_cap: 125.0' "/etc/lact/config.yaml"; then
        notify-send "Включено" "Ограничение питания видеокарты включено"
        sed -i 's/    power_cap: 125.0/    power_cap: 60.0/' /etc/lact/config.yaml
      else
        notify-send "Выключено" "Ограничение питания видеокарты выключено";
        sed -i 's/    power_cap: 60.0/    power_cap: 125.0/' /etc/lact/config.yaml
      fi
    '')
  ];
in
{
  environment.systemPackages = scripts ++ [ pkgs.bindfs ];
}
