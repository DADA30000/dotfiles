#!/usr/bin/env bash
exec nvr --servername "$NVIM" --remote-tab-wait +"setlocal bufhidden=wipe" "$@"
