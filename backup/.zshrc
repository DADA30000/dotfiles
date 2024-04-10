printf '\n%.0s' {1..100}
/usr/bin/fastfetch --pipe false|/usr/bin/lolcat -b -g 4f05fc:4287f5
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
export ZSH_COMPDUMP=$ZSH/cache/.zcompdump-$HOST
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
TRAPUSR1() { rehash }
toh264 () {
  f=${1}
  s=${2}
  ffmpeg -i $f -map 0 -c:v libx264 -crf 18 -vf format=yuv420p -c:a copy $s
}
vvcut () {
  f=${1}
  s=${2}
  t=${3}
  ffmpeg -i $f -ss $s -t $t -c:v copy -c:a copy cutvideo.mp4
}
alias fastfetch="fastfetch --logo-color-1 'blue' --logo-color-2 'blue'"
alias imgfetch="neofetch --kitty ~/.config/neofetch/arch.png --image_size 360"
alias cps="rsync -ahr --progress"
alias res="screen -r"
alias p="paru"
alias pn="paru --noconfirm"
alias record-discord="gpu-screen-recorder -k h264 -w screen -f 60 -a "$(pactl get-default-sink).monitor" -o"
alias nvide="neovide --no-fork"
alias nvrs="NVR_CMD='sudo nvim' nvr"
alias cl="clear;printf '\n%.0s' {1..100};fastfetch"
alias c="clear;printf '\n%.0s' {1..100};fastfetch --pipe false|lolcat -b -g 4f05fc:4287f5"
alias sudoe="sudo -E"
alias suvide="sudo -E neovide --no-fork"
alias cwp="swww img --transition-type wipe --transition-fps 60 --transition-step 255"
alias record="gpu-screen-recorder -w screen -f 60 -a "$(pactl get-default-sink).monitor" -o"
# If you come from bash you might have to change your $PATH.
export PATH=$HOME/.local/bin:$PATH
# /home/l0lk3k/.local/bin/paleofetch | /usr/bin/lolcat -b -g 4f05fc:4287f5
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
  exec Hyprland >/dev/null 2>&1
fi
# Path to your oh-my-zsh installation.
export ZSH="/users/l0lk3k/.oh-my-zsh"
export EDITOR="/bin/nvim"
export VISUAL="/bin/nvim"
# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"
if [[ "$(tty)" == "/dev/tty1" ]]
 then
  export PATH=/usr/local/hyprland
  exec /bin/rbash
fi
# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(sudo colorize colored-man-pages zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh
source /usr/share/doc/find-the-command/ftc.zsh
# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
# if [ -z "${WAYLAND_DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
#     dbus-run-session Hyprland &> /dev/null & echo "Добро пожаловать! "
# fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
export ZSH_COMPDUMP=$ZSH/cache/.zcompdump-$HOST
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
case "$TERM" in
    xterm*)
        if [ -e /usr/share/terminfo/x/xterm-256color ]; then
            export TERM=xterm-256color
        elif [ -e /usr/share/terminfo/x/xterm-color ]; then
            export TERM=xterm-color;
        else
            export TERM=xterm
        fi
        ;;
    linux)
        [ -n "$FBTERM" ] && export TERM=fbterm
        ;;
esac
