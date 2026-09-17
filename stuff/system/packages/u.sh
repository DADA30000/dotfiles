#!/usr/bin/env bash

GIT_CREDENTIALS="$XDG_CONFIG_HOME/git/credentials"
if [[ -f "$GIT_CREDENTIALS" ]]; then
  GH_TOKEN=$(grep -oP 'https://[^:]+:\K[^@]+(?=@github\.com)' "$GIT_CREDENTIALS" | head -1)
  if [[ -n "$GH_TOKEN" ]]; then
    if [[ -n "$NIX_CONFIG" ]]; then
      export NIX_CONFIG="${NIX_CONFIG}
extra-access-tokens = github.com=$GH_TOKEN"
    else
      export NIX_CONFIG="extra-access-tokens = github.com=$GH_TOKEN"
    fi
  fi
fi

STATE_FILE="$HOME/.cache/update-state"
NIXOS_DIR="/etc/nixos"

# Builder selection for debug mode: prefer nom, fallback to nix build
if command -v nom &>/dev/null; then
  DEBUG_BUILD_CMD=(nom build)
else
  DEBUG_BUILD_CMD=(nix build)
fi

# Default arguments passed to underlying commands
NH_ARGS=()
NIX_ARGS=()

get_target_host() {
  if [[ -n "$TARGET_HOST" ]]; then
    echo "$TARGET_HOST"
    return
  fi
  local host
  host="$(hostname 2>/dev/null || uname -n)"
  if nix eval "$NIXOS_DIR#nixosConfigurations.${host}" --apply "x: true" >/dev/null 2>&1; then
    echo "$host"
  else
    echo "nixos"
  fi
}

run_action() {
  local action="$1"
  shift

  local HOST
  HOST="$(get_target_host)"

  local EVAL_ARGS=()
  local NH_PASSTHROUGH=()

  # Route arguments between eval and nh
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -H|--hostname)
        HOST="$2"
        shift 2
        ;;
      --hostname=*)
        HOST="${1#*=}"
        shift
        ;;
      # Flags specific to nh or build actions
      -n|-a|--ask|--diff|--diff=*|-e|--elevation-strategy|-e=*|--elevation-strategy=*)
        NH_PASSTHROUGH+=("$1")
        shift
        ;;
      --dry|--dry-run)
        NH_PASSTHROUGH+=("--dry")
        shift
        ;;
      --no-validate|--show-activation-logs|--install-bootloader|-R|--bypass-root-check|--no-nom)
        NH_PASSTHROUGH+=("$1")
        shift
        ;;
      -o|--out-link|--profile)
        NH_PASSTHROUGH+=("$1" "$2")
        shift 2
        ;;
      --out-link=*|--profile=*)
        NH_PASSTHROUGH+=("$1")
        shift
        ;;
      *)
        EVAL_ARGS+=("$1")
        NH_PASSTHROUGH+=("$1")
        shift
        ;;
    esac
  done

  # ----------------------------------------------------------------------------
  # Stage 1: Explicit evaluation stage (times eval & warms the Nix flake cache)
  # ----------------------------------------------------------------------------
  echo -e "\e[1;34m==>\e[0m \e[1m[1/2] Evaluating NixOS configuration for '$HOST'...\e[0m" >&2
  local EVAL_START EVAL_END EVAL_MS EVAL_TIME
  EVAL_START=$(date +%s%N)

  if [[ "$action" == "debug" ]]; then
    EVAL_ARGS+=("--debugger" "--ignore-try")
  fi

  local DRV
  DRV=$(nix path-info --derivation "$NIXOS_DIR#nixosConfigurations.${HOST}.config.system.build.toplevel" \
    "${EVAL_ARGS[@]}" "${NIX_ARGS[@]}") || exit $?

  EVAL_END=$(date +%s%N)
  EVAL_MS=$(( (EVAL_END - EVAL_START) / 1000000 ))
  if (( EVAL_MS < 1000 )); then
    EVAL_TIME="${EVAL_MS}ms"
  else
    EVAL_TIME="$(printf "%d.%02ds" "$(( EVAL_MS / 1000 ))" "$(( (EVAL_MS % 1000) / 10 ))")"
  fi

  echo -e "\e[1;32m==>\e[0m \e[1mEvaluation finished in $EVAL_TIME. Derivation:\e[0m $DRV" >&2

  # ----------------------------------------------------------------------------
  # Stage 2: Build / Action stage (single nom build run by nh, or direct for debug)
  # ----------------------------------------------------------------------------
  case "$action" in
    debug)
      echo -e "\e[1;34m==>\e[0m \e[1m[2/2] Realising derivation with ${DEBUG_BUILD_CMD[0]} (debugger enabled)...\e[0m" >&2
      "${DEBUG_BUILD_CMD[@]}" "${DRV}^*" --no-link "${NH_PASSTHROUGH[@]}" "${NIX_ARGS[@]}"
      ;;
    build)
      echo -e "\e[1;34m==>\e[0m \e[1m[2/2] Building NixOS configuration with nh...\e[0m" >&2
      nh os build "$NIXOS_DIR" -H "$HOST" "${NH_PASSTHROUGH[@]}" "${NH_ARGS[@]}"
      ;;
    test)
      echo -e "\e[1;34m==>\e[0m \e[1m[2/2] Testing NixOS configuration with nh...\e[0m" >&2
      nh os test "$NIXOS_DIR" -H "$HOST" "${NH_PASSTHROUGH[@]}" "${NH_ARGS[@]}"
      ;;
    boot)
      echo -e "\e[1;34m==>\e[0m \e[1m[2/2] Setting boot configuration with nh...\e[0m" >&2
      nh os boot "$NIXOS_DIR" -H "$HOST" "${NH_PASSTHROUGH[@]}" "${NH_ARGS[@]}"
      ;;
    switch)
      echo -e "\e[1;34m==>\e[0m \e[1m[2/2] Building and switching with nh...\e[0m" >&2
      nh os switch "$NIXOS_DIR" -H "$HOST" "${NH_PASSTHROUGH[@]}" "${NH_ARGS[@]}"
      ;;
  esac
}

show_help() {
  cat <<EOF
Usage: u [command] [options...]

A unified wrapper for NixOS configuration updates and builds.
Separates evaluation and derivation building so progress is always visible.

Commands:
  full      Update locks, fetch runtimes, eval, build, and switch.
            (Saves state and resumes on failure)
            Use 'u full --reset' to clear state and start from step 1.
  test      Evaluate, then run 'nh os test'
  boot      Evaluate, then run 'nh os boot'
  build     Evaluate, then run 'nh os build'
  debug     Evaluate with debugger enabled, then build with nom
  switch    Evaluate, then run 'nh os switch'
  (none)    Same as switch, with --keep-going by default

All unmapped arguments are passed to the underlying commands.
EOF
}

# Check for help flag
for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    show_help
    exit 0
  fi
done

COMMAND="$1"

case "$COMMAND" in
test)
  shift
  run_action test "$@"
  ;;
boot)
  shift
  run_action boot "$@"
  ;;
build)
  shift
  run_action build "$@"
  ;;
debug)
  shift
  run_action debug "$@"
  ;;
switch)
  shift
  run_action switch --keep-going "$@"
  ;;
full)
  shift
  # Parse arguments specifically for 'full'
  RESET_STATE=0
  FULL_ARGS=()
  for arg in "$@"; do
    if [[ "$arg" == "--reset" ]]; then
      RESET_STATE=1
    else
      FULL_ARGS+=("$arg") # Store other args for nh
    fi
  done

  # Configure error handling
  printf "pipefail? [Y/n]: "
  read -n 1 -r response
  echo
  if [[ "$response" =~ ^[nN]$ ]]; then
    set +eo pipefail
    echo "Pipefail disabled."
  else
    set -eo pipefail
    echo "Pipefail enabled."
  fi

  mkdir -p "$HOME/.cache"
  if [[ $RESET_STATE -eq 1 ]]; then
    rm -f "$STATE_FILE"
    echo "State reset. Starting from step 1."
  fi

  CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo 1)
  [[ $CURRENT_STATE -gt 1 ]] && echo "Resuming update from step $CURRENT_STATE..."

  save_state() { echo "$1" >"$STATE_FILE"; }

  save_state 2

  # ------------------------------------------------------------------------------
  # STEP 2: Fetch SteamRT4
  # ------------------------------------------------------------------------------
  if [[ $CURRENT_STATE -le 2 ]]; then
    echo "Fetching steamrt4 version and hash..."
    STEAMRT4_VERSION="$(wget -q https://repo.steampowered.com/steamrt4/images/latest-public-stable.txt -O -)"
    STEAMRT4_HASH="$(wget -q https://repo.steampowered.com/steamrt4/images/$STEAMRT4_VERSION/SHA256SUMS -O - | grep SteamLinuxRuntime_4.tar.xz | awk '{print $1}' | xargs nix hash to-sri --type sha256)"
    echo "{ \"version\": \"$STEAMRT4_VERSION\", \"hash\": \"$STEAMRT4_HASH\" }" | sudo tee /etc/nixos/stuff/modules/home/umu/steamrt4.json
    echo "Finished fetching steamrt4"

    save_state 3
  fi

  # ------------------------------------------------------------------------------
  # STEP 3: Fetch SteamRT3
  # ------------------------------------------------------------------------------
  if [[ $CURRENT_STATE -le 3 ]]; then
    echo "Fetching steamrt3 version and hash..."
    STEAMRT3_VERSION="$(wget -q https://repo.steampowered.com/steamrt3/images/latest-public-stable.txt -O -)"
    STEAMRT3_HASH="$(wget -q https://repo.steampowered.com/steamrt3/images/$STEAMRT3_VERSION/SHA256SUMS -O - | grep SteamLinuxRuntime_sniper.tar.xz | awk '{print $1}' | xargs nix hash to-sri --type sha256)"
    echo "{ \"version\": \"$STEAMRT3_VERSION\", \"hash\": \"$STEAMRT3_HASH\" }" | sudo tee /etc/nixos/stuff/modules/home/umu/steamrt3.json
    echo "Finished fetching steamrt3"

    save_state 4
  fi

  # ------------------------------------------------------------------------------
  # STEP 4: Backup flake.lock
  # ------------------------------------------------------------------------------
  if [[ $CURRENT_STATE -le 4 ]]; then
    echo "Backing up flake.lock..."
    mkdir -p "$HOME/.cache/flake-lock-backups"
    cp "$NIXOS_DIR/flake.lock" "$HOME/.cache/flake-lock-backups/flake.lock_$(date +%Y.%m.%d_%H:%M:%S)"

    save_state 5
  fi

  # ------------------------------------------------------------------------------
  # STEP 5: Nix Flake Update
  # ------------------------------------------------------------------------------
  if [[ $CURRENT_STATE -le 5 ]]; then
    echo "Updating Nix flake..."
    TEMP_LOCK="$(mktemp)"

    if nix flake update --flake "$NIXOS_DIR" --output-lock-file "$TEMP_LOCK"; then
      echo "Flake update succeeded. Copying lock file to $NIXOS_DIR..."
      sudo cp "$TEMP_LOCK" "$NIXOS_DIR/flake.lock"
      rm -f "$TEMP_LOCK"
      save_state 6
    else
      rm -f "$TEMP_LOCK"
      echo "Error: 'nix flake update' failed." >&2
      exit 1
    fi
  fi

  # ------------------------------------------------------------------------------
  # STEP 6: Switch Configuration
  # ------------------------------------------------------------------------------
  if [[ $CURRENT_STATE -le 6 ]]; then
    echo "Building and switching NixOS configuration..."

    run_action switch "${FULL_ARGS[@]}" --extra-substituters "https://hyprland.cachix.org"

    # Only remove state file on absolute success
    rm -f "$STATE_FILE"
    echo "Update completed successfully!"
  fi
  ;;
*)
  # Default behavior for just running `u` or `u --flag`
  run_action switch --keep-going "$@"
  ;;
esac
