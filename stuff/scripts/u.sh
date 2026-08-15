#!/usr/bin/env bash

STATE_FILE="$HOME/.cache/update-state"
NIXOS_DIR="/etc/nixos"

# Default arguments passed to all `nh` and `nix build` commands
# Note: nh takes Nix options after `--`
NH_ARGS=(-- --option connect-timeout 5)
NIX_ARGS=(--option connect-timeout 5)

show_help() {
  cat <<EOF
Usage: u [command] [options...]

A unified wrapper for NixOS configuration updates and builds.

Commands:
  full      Update locks, fetch runtimes, build, and switch.
            (Saves state and resumes on failure)
            Use 'u full --reset' to clear state and start from step 1.
  test      Run 'nh os test'
  boot      Run 'nh os boot'
  build     Run 'nh os build'
  debug     Run 'nix build' with debugger enabled
  (none)    Run 'nh os switch --keep-going' by default

All unmapped arguments are passed to the underlying nh/nix command.
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
  nh os test "$NIXOS_DIR" "$@" "${NH_ARGS[@]}"
  ;;
boot)
  shift
  nh os boot "$NIXOS_DIR" "$@" "${NH_ARGS[@]}"
  ;;
build)
  shift
  nh os build "$NIXOS_DIR" "$@" "${NH_ARGS[@]}"
  ;;
debug)
  shift
  nix build "$NIXOS_DIR#nixosConfigurations.nixos.config.system.build.toplevel" \
    --no-link --debugger --ignore-try "$@" "${NIX_ARGS[@]}"
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

  # ------------------------------------------------------------------------------
  # STEP 1: CAPEv2 setup
  # ------------------------------------------------------------------------------
  if [[ $CURRENT_STATE -le 1 ]]; then
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:%{{{pkgs.ssdeep}}}/lib:%{{{pkgs.graphviz}}}/lib
    export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:%{{{pkgs.ssdeep}}}/lib/pkgconfig:%{{{pkgs.graphviz}}}/lib/pkgconfig
    export PATH=$PATH:%{{{pkgs.migrate-to-uv}}}/bin:%{{{pkgs.uv}}}/bin
    export PYTHONPATH=%{{{pkgs.python312}}}/lib/python3.12/site-packages
    export UV_PYTHON=%{{{pkgs.python312}}}/bin/python
    export UV_NO_MANAGED_PYTHON=true
    export UV_SYSTEM_PYTHON=true
    export TEMPDIR=$(%{{{pkgs.coreutils-full}}}/bin/mktemp -d)
    export GIT_LFS_SKIP_SMUDGE=1

    echo "Updating CAPEv2..."
    git clone https://github.com/kevoreilly/CAPEv2 --depth 1 "$TEMPDIR/cape"
    (
      cd "$TEMPDIR/cape" || exit 1
      mkdir -p capev2
      sed -i '/package-mode/d' pyproject.toml
      sed -i '/\[tool.poetry\]/d' pyproject.toml
      echo 'print("Hello World")' >capev2/__init__.py
      cat <<'EOF' >>pyproject.toml

[tool.hatch.build.targets.wheel]
packages = [
  "dummy"
]
EOF
      uv add -r extra/optional_dependencies.txt
      uv lock
      mkdir -p nix_workspace
      mv pyproject.toml nix_workspace
      mv uv.lock nix_workspace
      mv capev2 nix_workspace
    )
    sudo rm -rf /etc/nixos/modules/system/cape/nix_workspace
    sudo cp -r "$TEMPDIR/cape/nix_workspace" /etc/nixos/modules/system/cape
    rm -rf "$TEMPDIR"

    save_state 2
  fi

  # ------------------------------------------------------------------------------
  # STEP 2: Fetch SteamRT4
  # ------------------------------------------------------------------------------
  if [[ $CURRENT_STATE -le 2 ]]; then
    echo "Fetching steamrt4 version and hash..."
    STEAMRT4_VERSION="$(wget -q https://repo.steampowered.com/steamrt4/images/latest-public-stable.txt -O -)"
    STEAMRT4_HASH="$(wget -q https://repo.steampowered.com/steamrt4/images/$STEAMRT4_VERSION/SHA256SUMS -O - | grep SteamLinuxRuntime_4.tar.xz | awk '{print $1}' | xargs nix hash to-sri --type sha256)"
    echo "{ \"version\": \"$STEAMRT4_VERSION\", \"hash\": \"$STEAMRT4_HASH\" }" | sudo tee /etc/nixos/stuff/steamrt4.json
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
    echo "{ \"version\": \"$STEAMRT3_VERSION\", \"hash\": \"$STEAMRT3_HASH\" }" | sudo tee /etc/nixos/stuff/steamrt3.json
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

    nh os switch "$NIXOS_DIR" "${FULL_ARGS[@]}" "${NH_ARGS[@]}" --extra-substituters "https://hyprland.cachix.org"

    # Only remove state file on absolute success
    rm -f "$STATE_FILE"
    echo "Update completed successfully!"
  fi
  ;;
*)
  # Default behavior for just running `u` or `u --flag`
  # We pass everything directly down to `nh os switch`
  nh os switch --keep-going "$NIXOS_DIR" "$@" "${NH_ARGS[@]}"
  ;;
esac
