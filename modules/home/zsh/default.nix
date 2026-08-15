{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.zsh;
in
{
  options.zsh.enable = mkEnableOption "zsh shell";

  config = mkIf cfg.enable {
    home = {
      file.".zshenv".enable = false;
      sessionVariables.ZDOTDIR = "${config.programs.zsh.dotDir}";
    };
    programs = {
      zoxide = {
        enable = true;
        enableZshIntegration = true;
      };
      direnv = {
        enable = true;
        enableZshIntegration = true;
        nix-direnv.enable = true;
      };
      nix-index = {
        enable = true;
        enableZshIntegration = true;
        package =
          inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}.nix-index-with-small-db;
      };
      starship = {
        enable = true;
        enableZshIntegration = true;
        settings = {
          nix_shell.symbol = "❄️ ";
          directory = {
            style = "bold blue";
          };
        };
      };
      zsh = {
        dotDir = "${config.xdg.dataHome}/zsh";
        oh-my-zsh.enable = true;
        oh-my-zsh.plugins = [ "sudo" ];
        syntaxHighlighting.enable = true;
        autosuggestion.enable = true;
        enable = true;
        shellAliases.ls = "lsd";
        envExtra = /* zsh */ ''
          #touch "${config.home.homeDirectory}"/.zsh/.zshenv_add
          #source "${config.home.homeDirectory}"/.zsh/.zshenv_add
          local NIX_FLAKE_PREAMBLE='(
            let 
              flake = builtins.getFlake "git+file://${config.offline-path}?rev=${config.offline-rev}"; 
              nixpkgs = import flake.inputs.nixpkgs { 
                system = "${pkgs.stdenv.hostPlatform.system}";
                config = {
                  allowUnfree = true;
                  android_sdk.accept_license = true;
                };
                overlays = [
                  (
                    final: prev:
                    let
                      customFetchurl =
                        args:
                        let
                          nixFetch = import <nix/fetchurl.nix>;
                          isSet = builtins.typeOf args == "set";
                          supported = builtins.functionArgs nixFetch;
                          hasUnsupported = isSet && builtins.any (k: !builtins.hasAttr k supported) (builtins.attrNames args);
                          hasUrls = isSet && (args ? urls);
                          isMirror = u: builtins.isString u && builtins.substring 0 9 u == "mirror://";
                          hasMirror = isSet && (args ? url) && isMirror args.url;
                          needsFallback = !isSet || hasUnsupported || hasUrls || hasMirror;
                        in
                        if needsFallback then prev.fetchurl args 
                        else (nixFetch args) // {
                          overrideAttrs = f: (prev.fetchurl args).overrideAttrs f;
                          override = f: (prev.fetchurl args).override f;
                          overrideDerivation = f: (prev.fetchurl args).overrideDerivation f;
                        };
                    in
                    {
                      fetchurl =
                        if builtins.typeOf prev.fetchurl == "set" && prev.fetchurl ? __functor then
                          prev.fetchurl // { __functor = self: args: customFetchurl args; }
                        else
                          customFetchurl;
                    }
                  )
                ];
              };
            in
              nixpkgs // { inherit (flake) inputs; }
          )'
          _ns_parse_args() {
            flags=() pkgs=() pkgs_raw=()
            while (( $# > 0 )); do
              if [[ "$1" == -*\ * ]]; then
                flags+=(''${=1})
                shift 1
                continue
              fi
              case "$1" in
                --max-jobs|-j|--cores|--builders|--substituters|--impure-env|-I|--override-input|--arg|--argstr|-o|--output)
                  flags+=("$1" "$2")
                  shift 2
                  ;;
                -*)
                  flags+=("$1")
                  shift 1
                  ;;
                *)
                  pkgs+=("($1)")
                  pkgs_raw+=("$1")
                  shift 1
                  ;;
              esac
            done
          }
          _zsh_nix_bridge() {
            if [[ -n "$stdenv" ]]; then
              local funcs=($(bash -c 'source $stdenv/setup; declare -F | cut -d" " -f3'))
              for f in $funcs; do
                if ! builtin type "$f" >/dev/null 2>&1; then
                  eval "$f() { bash -c \"source \$stdenv/setup; $f \$*\" }"
                fi
              done
              unsetopt NOMATCH
            fi
          }

          # Internal replacement for nix develop
          _nix-develop() {
            local has_help=0
            for arg in "$@"; do
              if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
                has_help=1
                break
              fi
            done

            if (( has_help == 1 )); then
              nix print-dev-env "$@"
              return 0
            fi

            local env_file
            env_file=$(mktemp /tmp/nix-shell-env.XXXXXX)
            export PREV_SHELL="$SHELL"
            if OUT_SHELL="$(nix print-dev-env --log-format internal-json -v "$@" 2> >(nom --json))"; then
              printf "%s" "$OUT_SHELL" > "$env_file"
              ${pkgs.bash}/bin/bash -c "source $env_file; rm -f $env_file; export SHELL=$PREV_SHELL; exec $SHELL"
            else
              local status=$?
              rm -f "$env_file"
              return $status
            fi
          }

          ns-dev () {
            _ns_parse_args "$@"
            _nix-develop "''${flags[@]}" --no-use-registries --expr "with $NIX_FLAKE_PREAMBLE; mkShell rec { 
              buildInputs = let p = [ ''${pkgs[*]} ]; d = builtins.map (x: if (x ? dev) then x.dev else x) p; in p ++ d;
              name = builtins.substring 0 100 \"ns_dev_\''${builtins.concatStringsSep \"-\" (lib.lists.uniqueStrings (builtins.map (x: builtins.elemAt (lib.splitString \"-\" x.name) 0) buildInputs))}\";
              shellHook = '''
                export LD_LIBRARY_PATH=\"\$LD_LIBRARY_PATH:\''${lib.makeLibraryPath buildInputs}\";
                export PKG_CONFIG_PATH=\"\$PKG_CONFIG_PATH:\''${builtins.concatStringsSep \":\" (builtins.map (x: \"\''${x}/lib/pkgconfig\") buildInputs)}\";
              ''';
            }"
          }

          ns-build-env () {
            _ns_parse_args "$@"
            _nix-develop "''${flags[@]}" --no-use-registries --expr "with $NIX_FLAKE_PREAMBLE; ''${pkgs[*]}"
          }

          ns-py () {
            _ns_parse_args "$@"
            local py_pkgs=()
            local pkgs_new=()
            for p in "''${pkgs_raw[@]}"; do py_pkgs+=("(ps.$p)"); pkgs_new+=("(python3Packages.$p)"); done

            pkgs_new+=("(python3.withPackages (ps: [ ''${py_pkgs[*]} ]))")

            _nix-develop "''${flags[@]}" --no-use-registries --expr "with $NIX_FLAKE_PREAMBLE; mkShell rec { 
              buildInputs = let p = [ ''${pkgs_new[*]} ]; d = builtins.map (x: if (x ? dev) then x.dev else x) p; in p ++ d;
              name = \"ns_py_\''${builtins.concatStringsSep \"-\" (lib.lists.uniqueStrings (builtins.map (x: builtins.elemAt (lib.splitString \"-\" x.name) 1) buildInputs))}\";
              shellHook = '''
                export LD_LIBRARY_PATH=\"\$LD_LIBRARY_PATH:\''${lib.makeLibraryPath buildInputs}\";
                export PKG_CONFIG_PATH=\"\$PKG_CONFIG_PATH:\''${builtins.concatStringsSep \":\" (builtins.map (x: \"\''${x}/lib/pkgconfig\") buildInputs)}\";
              ''';
            }"
          }

          ns-old () { 
            _ns_parse_args "$@"
            nix shell "''${flags[@]}" --no-use-registries --expr "with $NIX_FLAKE_PREAMBLE; [ ''${pkgs[*]} ]"
          }

          ns-build () {
            _ns_parse_args "$@" 
            local OUT_PATH
            OUT_PATH="$(nix build "''${flags[@]}" --log-format internal-json -v --no-link --print-out-paths --no-use-registries --expr "with $NIX_FLAKE_PREAMBLE; [ ''${pkgs[*]} ]" 2> >(nom --json))"
            printf "$OUT_PATH" | wl-copy
            echo "$OUT_PATH"
          }

          ns-eval () {
            _ns_parse_args "$@"
            local OUT_PATH
            OUT_PATH="$(nix eval "''${flags[@]}" --log-format internal-json -v --raw --no-use-registries --expr "builtins.concatStringsSep \"\n\" (with $NIX_FLAKE_PREAMBLE; [ ''${pkgs[*]} ])" 2> >(nom --json))"
            printf "$OUT_PATH" | wl-copy
            echo "$OUT_PATH"
          }

          prefetch() {
            local OUT_PATH
            local -a resolved_args
            local arg

            for arg in "$@"; do
                if [[ -e "$arg" ]]; then
                    resolved_args+=("file://''${arg:A}")
                else
                    resolved_args+=("$arg")
                fi
            done

            if OUT_PATH="$(nix-prefetch-url --print-path "$resolved_args")"; then
              OUT_PATH="$(printf "$OUT_PATH" | tail -n 1)"
              printf '%s' "$OUT_PATH" | wl-copy
              echo "$OUT_PATH"
            fi
          }

          detach-from-nixos() { patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 "$@" }
          umu-run() { umu-run-wrapper "$@" }
          nsl() { ${
            inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}.default
          }/bin/nix-locate "$@" }
          nss() { ${
            let
              index = pkgs.runCommand "index" { } ''
                PATH=$PATH:${config.nix.package}/bin
                mkdir fake-state-dir
                mkdir -p "$out"
                HOME="$out" NIX_STATE_DIR="$(pwd)/fake-state-dir" NIX_PATH="nixpkgs=${inputs.nixpkgs}" ${
                  inputs.nix-search.packages.${pkgs.stdenv.hostPlatform.system}.default
                }/bin/nix-search -i -v 3
                mv "$out/.cache/nix-search/index-v4" "$out" 
                rm -rf "$out/.cache"
              '';
            in
            "nix-search --index-path \"${index}\" \"$@\""
          }
          }
          fix-dbx() {
            local DEFAULT_DBX_PATH=$(ls /sys/firmware/efi/efivars/dbxDefault-*)
            DEFAULT_DBX_PATH=$(ls /sys/firmware/efi/efivars/dbxDefault-*)
            sudo tail -c +5 "$DEFAULT_DBX_PATH" > /tmp/dbxDefault.esl
            sudo efi-updatevar -e -k /var/lib/sbctl/keys/KEK/KEK.key -f /tmp/dbxDefault.esl dbx
            sudo rm /tmp/dbxDefault.esl
          }
          7z() { 7zz "$@" }
          ns() { ns-dev "$@" }
          ns-repl() { nix repl --no-use-registries --expr "$NIX_FLAKE_PREAMBLE" "$@" }
          nsl-bin() { nix-locate "$@" }
          fastfetch() { command fastfetch --logo-color-1 'blue' --logo-color-2 'blue' "$@" }
          cps() { rsync -ahr --progress "$@" }
          res() { screen -r "$@" }
          record-h264() { gpu-screen-recorder -k h264 -w screen -a 'default_output|default_input' -o "$@" }
          nvide() { neovide --no-fork "$@" }
          c() { 
            clear 
            printf '\n%.0s' {1..100}
            fastfetch "$@"
          }
          cl() { 
            clear
            printf '\n%.0s' {1..100}
            fastfetch --pipe false | lolcat -b -g 4f05fc:4287f5 "$@"
          }
          sudoe() { sudo -E "$@" }
          suvide() { sudo -E neovide --no-fork "$@" }
          record() { gpu-screen-recorder -w screen -a 'default_output|default_input' -o "$@" }
          fzfd() { fzf | xargs xdg-open "$@" }
          ${pkgs.any-nix-shell}/bin/any-nix-shell zsh | source /dev/stdin
          _zsh_nix_bridge
          if [ -f /run/.containerenv ]; then
            export PATH=$(echo $PATH | tr ':' '\n' | tac | tr '\n' ':' | sed 's/:$//')
          fi
        '';
        initContent =
          let
            zshConfig = /* zsh */ ''
              if [[ -n "$INSIDE_SESATT" ]]; then
                export SUDO_EDITOR="sesatt --editor"
                export VISUAL="sesatt --editor"
                export EDITOR="sesatt --editor"
              elif [[ -n "$NVIM" && -e "$NVIM" ]]; then
                export SUDO_EDITOR="nvr-remote-editor"
                export VISUAL="nvr-remote-editor"
                export EDITOR="nvr-remote-editor"
              fi

              alias v="nvim"
              export MANPAGER="nvim +Man!"
              export PAGER="nvim"
              export SYSTEMD_PAGERSECURE=0
              export SYSTEMD_PAGERFLAGS=""
              export SYSTEMD_COLORS=1

              printf '\n%.0s' {1..100}
              setopt correct

              # Optimize path completion (especially for giant dirs like /nix/store)
              zstyle ':completion:*' accept-exact-dirs true

              # Prefer exact matches first before attempting case-insensitive or fuzzy/substring matches.
              # Prepending "" ensures precise inputs complete instantly without initiating heavy fuzzy directory scans.
              zstyle ':completion:*' matcher-list "" 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

              _ns_completer() {
                local subcommand
                subcommand="$1"
                local attr_prefix
                attr_prefix="$2"
                local -a processed_words
                for word in "''${words[@]}"; do
                  if [[ "$word" == -* || "$word" == "nix" || "$word" == "shell" || "$word" == "develop" || "$word" == "eval" ]]; then
                    processed_words+=("$word")
                  else
                    processed_words+=("''${attr_prefix}$word")
                  fi
                done
                local curr_word
                curr_word="''${processed_words[$CURRENT]}"
                
                if [[ ! "$curr_word" == -* ]]; then
                  if [[ -n "$curr_word" ]]; then
                    local cache_dir="/tmp/nix_completer_cache_dir"
                    local current_flake_source="${config.offline-path}?rev=${config.offline-rev}"
                    
                    # Cache invalidation if flake source changes
                    if [[ -d "$cache_dir" ]]; then
                      if [[ ! -f "$cache_dir/flake_source" || "$(<"$cache_dir/flake_source")" != "$current_flake_source" ]]; then
                        rm -rf "$cache_dir"
                      fi
                    fi
                    
                    mkdir -p "$cache_dir"
                    if [[ ! -f "$cache_dir/flake_source" ]]; then
                      echo -n "$current_flake_source" > "$cache_dir/flake_source"
                    fi

                    local cache_key
                    local eval_prefix=""
                    local start_attr="pkgs"
                    
                    # 1-Level On-Demand Path Builder
                    if [[ "$curr_word" == *.* ]]; then
                      cache_key="''${curr_word%.*}"
                      eval_prefix="''${cache_key}."
                      start_attr="pkgs.''${cache_key}"
                    else
                      cache_key="root"
                    fi
                    local cache_file="$cache_dir/''${cache_key//./_}"
                    
                    local packages_string=""
                    if [[ -f "$cache_file" ]]; then
                      # Fast path: Load from localized cache
                      packages_string="$(<"$cache_file")"
                    else
                      # Safe 1-level deep on-demand evaluation
                      packages_string=$(nix eval --raw --no-use-registries --expr "
                        let
                          pkgs = $NIX_FLAKE_PREAMBLE;
                          startAttr = builtins.tryEval ''${start_attr};
                        in
                        if startAttr.success && builtins.typeOf startAttr.value == \"set\" then
                          builtins.concatStringsSep \"\n\" (map (name: \"''${eval_prefix}\''${name}\") (builtins.attrNames startAttr.value))
                        else
                          \"\"
                      " 2>/dev/null)
                      print -rn -- "$packages_string" > "$cache_file"
                    fi

                    local -a packages
                    packages=(''${(f)packages_string})

                    # Match Categorization (using case-insensitive patterns to coordinate with compadd)
                    local -a exact_matches prefix_matches substring_matches

                    exact_matches=( ''${(M)packages:#(#i)"$curr_word"} )
                    exact_matches=( "''${(@)exact_matches/#''${attr_prefix}/}" )

                    prefix_matches=( ''${(M)packages:#(#i)"$curr_word"*} )
                    prefix_matches=( "''${(@)prefix_matches/#''${attr_prefix}/}" )
                    prefix_matches=( ''${prefix_matches:|exact_matches} )

                    substring_matches=( ''${(M)packages:#(#i)*"$curr_word"*} )
                    substring_matches=( "''${(@)substring_matches/#''${attr_prefix}/}" )
                    substring_matches=( ''${substring_matches:|exact_matches} )
                    substring_matches=( ''${substring_matches:|prefix_matches} )

                    # Check how many exact/prefix matches we have in total
                    local total_prefixes=$(( ''${#exact_matches[@]} + ''${#prefix_matches[@]} ))

                    if (( total_prefixes == 1 )); then
                      # EXACTLY 1 match: Instantly auto-complete it
                      if (( ''${#exact_matches[@]} == 1 )); then
                        compadd -M 'm:{[:lower:]}={[:upper:]} r:|[-_./]=*' -a exact_matches
                      else
                        compadd -M 'm:{[:lower:]}={[:upper:]} r:|[-_./]=*' -a prefix_matches
                      fi
                    elif (( total_prefixes > 1 )); then
                      # >1 prefix/exact matches: Only show prefix/exact matches so substring matches don't hijack completion
                      if (( ''${#exact_matches[@]} > 0 )); then
                        compadd -M 'm:{[:lower:]}={[:upper:]} r:|[-_./]=*' -J exact -a exact_matches
                      fi
                      if (( ''${#prefix_matches[@]} > 0 )); then
                        compadd -M 'm:{[:lower:]}={[:upper:]} r:|[-_./]=*' -J prefix -a prefix_matches
                      fi
                    elif (( ''${#substring_matches[@]} > 0 )); then
                      # 0 prefix matches: Fall back to substring matches
                      compadd -M 'm:{[:lower:]}={[:upper:]} r:|[-_./]=* l:|=*' -J substring -a substring_matches
                    fi
                  fi
                else
                  shift processed_words
                  local -a proc_words
                  for word in "''${processed_words[@]}"; do
                    if [[ "$word" == -* ]]; then
                      proc_words+=("$word")  
                    fi
                  done
                  proc_words=(nix $subcommand $proc_words)
                  local ifs_bk="$IFS" 
                  local input=("''${(Q)proc_words[@]}") 
                  IFS=$'\n' 
                  local res=($(NIX_GET_COMPLETIONS=$((CURRENT)) "$input[@]" 2>/dev/null)) 
                  IFS="$ifs_bk" 
                  local tpe="''${''${res[1]}%%>	*}" 
                  local -a suggestions
                  declare -a suggestions
                  for suggestion in ''${res:1}
                  do
                  	suggestions+=("''${suggestion%%	*}") 
                  done
                  local -a args
                  if [[ "$tpe" == filenames ]]
                  then
                  	args+=('-f') 
                  elif [[ "$tpe" == attrs ]]
                  then
                  	args+=('-S' ''') 
                  fi
                  compadd -J nix "''${args[@]}" -a suggestions
                fi
              }

              _sesatt() {
                local curr_word="''${words[$CURRENT]}"
                local prev_word="''${words[$CURRENT-1]}"
                local ret=1

                # Subcommands that expect a session name
                if [[ "$prev_word" == "-k" || "$prev_word" == "--kill" ]]; then
                  local -a sessions
                  for line in ''${(f)"$(sesatt -l 2>/dev/null)"}; do
                    if [[ "$line" == •* ]]; then
                      sessions+=("''${''${(z)line}[2]}")
                    fi
                  done
                  _describe -t sessions 'active/dead sessions' sessions && ret=0
                  return ret
                fi

                # First argument: suggest options and session names
                if [[ "$CURRENT" -eq 2 ]]; then
                  local -a sessions opts
                  for line in ''${(f)"$(sesatt -l 2>/dev/null)"}; do
                    if [[ "$line" == •* ]]; then
                      sessions+=("''${''${(z)line}[2]}")
                    fi
                  done
                  opts=(
                    '-h:Print help information'
                    '--help:Print help information'
                    '-l:List all background sessions'
                    '--list:List all background sessions'
                    '-c:Clean dead sessions'
                    '--clean:Clean dead sessions'
                    '--prune:Clean dead sessions'
                    '-k:Terminate specified session'
                    '--kill:Terminate specified session'
                    '-d:Start session in detached mode'
                    '--detach:Start session in detached mode'
                  )
                  _describe -t options 'options' opts && ret=0
                  _describe -t sessions 'active/dead sessions' sessions && ret=0
                  return ret
                fi

                # Argument after -d / --detach expects a session
                if [[ "$CURRENT" -eq 3 && ("$prev_word" == "-d" || "$prev_word" == "--detach") ]]; then
                  local -a sessions
                  for line in ''${(f)"$(sesatt -l 2>/dev/null)"}; do
                    if [[ "$line" == •* ]]; then
                      sessions+=("''${''${(z)line}[2]}")
                    fi
                  done
                  _describe -t sessions 'active/dead sessions' sessions && ret=0
                  return ret
                fi

                # Executable / path completion for commands passed after session name
                if [[ "$curr_word" != -* ]]; then
                  _command_names -e && ret=0
                  _files && ret=0
                  return ret
                fi

                return 1
              }

              _ns-old () { _ns_completer shell }
              _ns-py () { _ns_completer develop python3Packages. }
              _ns () { _ns_completer develop }
              _ns-dev () { _ns_completer develop }
              _ns-eval () { _ns_completer eval }
              _ns-build () { _ns_completer build }
              _ns-build-env () { _ns_completer develop }

              compdef _ns-old ns-old
              compdef _ns ns
              compdef _ns-dev ns-dev
              compdef _ns-py ns-py
              compdef _ns-eval ns-eval
              compdef _ns-build ns-build
              compdef _ns-build-env ns-build-env
              compdef _sesatt sesatt
            '';
            zshEarly = mkOrder 500 ''
              DISABLE_MAGIC_FUNCTIONS=true
            '';
          in
          mkMerge [
            zshConfig
            zshEarly
          ];
      };
    };
  };
}
