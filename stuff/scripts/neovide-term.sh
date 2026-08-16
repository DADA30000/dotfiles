TITLE=""
APP_ID=""
WORKDIR=""
HOLD=""

while [ $# -gt 0 ]; do
  case "$1" in
  -T | --title)
    TITLE="$2"
    shift 2
    ;;
  --class | --app-id)
    APP_ID="$2"
    shift 2
    ;;
  --working-directory)
    WORKDIR="$2"
    shift 2
    ;;
  --hold)
    HOLD="1"
    shift
    ;;
  -e | --)
    shift
    break
    ;;
  *)
    break
    ;;
  esac
done

CMD=""
for arg in "$@"; do
  escaped="''${arg//\'/\'\\\'\'}"
  if [ -z "$CMD" ]; then
    CMD="'$escaped'"
  else
    CMD="$CMD '$escaped'"
  fi
done

# Construct Neovide CLI arguments array safely
set -- --frame none --mouse-cursor-icon i-beam

if [ -n "$APP_ID" ]; then
  set -- "$@" --app-id "$APP_ID"
fi

if [ -n "$TITLE" ]; then
  set -- "$@" --title "$TITLE"
fi

if [ -n "$WORKDIR" ]; then
  set -- "$@" "+cd $WORKDIR"
fi

if [ -n "$CMD" ]; then
  if [ -n "$HOLD" ]; then
    set -- "$@" "+term $CMD; \$SHELL"
  else
    set -- "$@" "+term $CMD"
  fi
else
  set -- "$@" "+term"
fi

set -- "$@" +startinsert \
  '+set laststatus=0' \
  '+set cmdheight=0' \
  '+nnoremap <C-S-t> :tabnew +term<CR>' \
  '+inoremap <C-S-t> <C-o>:tabnew +term<CR>' \
  '+tnoremap <C-S-t> <C-\><C-n>:tabnew +term<CR>' \
  '+xnoremap <C-S-t> <Esc>:tabnew +term<CR>' \
  '+snoremap <C-S-t> <Esc>:tabnew +term<CR>'

exec neovide "$@"
