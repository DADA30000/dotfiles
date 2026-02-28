{ lib, pkgs, ... }:
{

  flatpak.enable = lib.mkForce false;

  systemd.user.services.umu-check.Install.WantedBy = lib.mkForce [ ];

  systemd.user.services.easyeffects.Install.WantedBy = lib.mkForce [ ];

  home.packages = [ pkgs.zenity ];

  wayland.windowManager.hyprland.settings.exec-once = [
    "${pkgs.writeShellScript "prompt" ''
      while true; do
        selected_button=$(zenity --info \
          --title="Выберите доп. службы для запуска" \
          --text="singbox - это VPN\n\neasyeffects - звуковые эффекты, например шумоподавление\n\nreplays - служба повторов, записывает последние 5 минут, сохранять можно с помощью Ctrl + Super + R, повторы сохраняются в ~/Games/Replays\n\nopentabletdriver - служба для работы графических планшетов\n\n\n\nВсе эти службы потребляют ОЗУ и ЦП" \
          --extra-button="singbox" \
          --extra-button="easy-effects" \
          --extra-button="replays" \
          --extra-button="opentabletdriver")

        case $selected_button in
          "singbox")
            sudo systemctl start singbox
            ;;
          "easy-effects")
            systemctl --user start easyeffects
            ;;
          "replays")
            systemctl --user start replays
            ;;
          "opentabletdriver")
            systemctl --user start opentabletdriver
            ;;
          *)
            break
            ;;
        esac
      done
    ''}"
  ];
}
