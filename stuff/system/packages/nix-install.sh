if [[ $EUID -ne 0 ]]; then
  exec sudo WAYLAND_DISPLAY="$WAYLAND_DISPLAY" HOME="$HOME" GTK_THEME="$GTK_THEME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" nix-install
fi
setfont cyr-sun16
clear

offline_flag=""
if gum confirm "Провести оффлайн установку?"; then
  offline_flag="offline"
else
  echo -e "\e[34mПроверка наличия соединения с интернетом...\e[0m"
  if ! nc -zw1 google.com 443 >/dev/null 2>&1; then
    echo -e "\e[31mСоединение не установлено :(\e[0m"
    if gum confirm "Настроить подключение?"; then
      nmtui
      if ! nc -zw1 google.com 443 >/dev/null 2>&1; then
        echo -e "\e[34mСоединение не было установлено, перезапуск...\e[0m"
        sleep 2
        exec nix-install
      fi
    fi
  fi
  echo -e "\e[32mСоединение установлено!\e[0m"
fi
sleep 1
url="https://github.com/DADA30000/dotfiles"
clear

if gum confirm --default=false "Использовать встроенный в ISO репозиторий?"; then
  cd /repo || exit 1
  exec ./start.sh $offline_flag
else
  if [ "$offline_flag" = "offline" ]; then
    echo -e "\e[31mОффлайн установка требует использования встроенного репозитория!\e[0m"
    sleep 2
    exec nix-install
  fi
  if gum confirm --default=false "Поменять URL репозитория с файлами конфигурации?"; then
    url=$(gum input --placeholder "Пример: https://github.com/DADA30000/dotfiles")
  fi
  if GIT_ASKPASS=true git ls-remote "$url" >/dev/null 2>&1; then
    clear
    echo -e "\e[34mКлонирование репозитория...\e[0m"
    rm -rf /mnt2
    mkdir /mnt2
    if git clone "$url" --depth 1 /mnt2/dotfiles; then
      cd /mnt2/dotfiles || exit 1
      echo -e "\e[34mЗапуск start.sh...\e[0m"
      exec ./start.sh
    else
      echo -e "\e[31mОшибка клонирования репозитория, перезапуск скрипта...\e[0m"
      sleep 3
      rm -rf /mnt2
      exec nix-install
    fi
  else
    echo -e "\e[31mURL репозитория неверный или приватный, перезапуск скрипта...\e[0m"
    sleep 3
    exec nix-install
  fi
fi
