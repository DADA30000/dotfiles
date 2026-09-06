hyprshutdown -t 'Выход из системы...' --post-cmd 'systemd-run --user --unit=desktop-logout --quiet sh -c "uwsm stop; loginctl terminate-user \"\""'
