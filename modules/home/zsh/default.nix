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
  nix-path =
    pkgs.runCommand "kekma"
      {
        src = ../../../stuff/nixpkgs.tar.zst;
      }
      ''
        PATH=$PATH:${pkgs.zstd}/bin
        mkdir $out
        tar --strip-components=1 -xvf $src -C $out
      '';
in
{
  options.zsh = {
    enable = mkEnableOption "Enable zsh shell";
  };

  config = mkIf cfg.enable {
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
        dotDir = "${config.home.homeDirectory}/.zsh";
        oh-my-zsh.enable = true;
        oh-my-zsh.plugins = [ "sudo" ];
        syntaxHighlighting.enable = true;
        autosuggestion.enable = true;
        enable = true;
        shellAliases.ls = "lsd";
        envExtra = ''
          local NIX_FLAKE_PREAMBLE='import (builtins.getFlake "git+file://${nix-path}?rev=${inputs.nixpkgs.rev}&shallow=1") { system = "${pkgs.stdenv.hostPlatform.system}"; config.allowUnfree = true; }'
          _ns_parse_args() {
            flags=() pkgs=() pkgs_raw=()
            while (( $# > 0 )); do
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

          # Ad-hoc nix-develop devShell
          ns-dev () {
            _ns_parse_args "$@"
            nix develop "''${flags[@]}" --expr "with $NIX_FLAKE_PREAMBLE; mkShell rec { 
              buildInputs = let p = [ ''${pkgs[*]} ]; d = builtins.map (x: if (x ? dev) then x.dev else x) p; in p ++ d;
              name = \"ns_dev_''${pkgs_raw[*]}\";
              LD_LIBRARY_PATH = \"\''${lib.makeLibraryPath buildInputs}\";
              PKG_CONFIG_PATH = \"\''${builtins.concatStringsSep \":\" (builtins.map (x: \"\''${x}/lib/pkgconfig\") buildInputs)}\";
            }"
          }

          # Enter shell with build dependencies and build phases for 1 package
          ns-build-env () {
            _ns_parse_args "$@"
          
            local count=''${#pkgs_raw[@]}
          
            if [[ $count -eq 0 ]]; then
              echo "Error: No target specified. Usage: ns-build-env [flags] <package>"
              return 1
            elif [[ $count -gt 1 ]]; then
              echo "Error: Only 1 target allowed. Found $count targets: ''${pkgs_raw[*]}"
              return 1
            fi
          
            local target="''${pkgs_raw[1]}"
            
            echo "❄️ Entering build environment for: $target"
            nix develop "''${flags[@]}" --expr "with $NIX_FLAKE_PREAMBLE; $target"
          }

          # Ad-hoc python with modules env
          ns-py () {
            _ns_parse_args "$@"
            local py_pkgs=()
            for p in "''${pkgs_raw[@]}"; do py_pkgs+=("ps.$p"); done
            ns-dev "''${flags[@]}" "python3.withPackages (ps: [ ''${py_pkgs[*]} ])"
          }

          # Pure nix-shell -p alternative
          ns-old () { _ns_parse_args "$@"; nix shell "''${flags[@]}" --expr "with $NIX_FLAKE_PREAMBLE; [ ''${pkgs[*]} ]" }

          # ad-hoc nix build expr
          ns-build () { _ns_parse_args "$@"; nix build "''${flags[@]}" --expr "with $NIX_FLAKE_PREAMBLE; [ ''${pkgs[*]} ]" }

          # ad-hoc nix eval expr
          ns-eval () {
            _ns_parse_args "$@"
            nix eval "''${flags[@]}" --raw --expr "builtins.concatStringsSep \"\n\" (with $NIX_FLAKE_PREAMBLE; [ ''${pkgs[*]} ])"
          }

          proxify () {
            SOCKS_SERVER=127.0.0.1:2080 socksify $@
          }
          u-full () {
            echo "Updating locks, switching"
            setopt LOCAL_OPTIONS
            (
              setopt LOCAL_OPTIONS
              printf "Enable pipefail? [Y/n]: "
              read -k 1 response
              echo
              if [[ "$response" == [nN] ]]; then
                  unsetopt ERR_EXIT NO_UNSET PIPE_FAIL
                  echo "Pipefail disabled."
              else
                  setopt ERR_EXIT NO_UNSET PIPE_FAIL
                  echo "Pipefail enabled."
              fi
              export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.ssdeep}/lib:${pkgs.graphviz}/lib
              export PATH=$PATH:${pkgs.migrate-to-uv}/bin:${pkgs.uv}/bin
              export PYTHONPATH=${pkgs.python312}/lib/python3.12/site-packages
              export UV_PYTHON=${pkgs.python312}/bin/python
              export UV_NO_MANAGED_PYTHON=true
              export UV_SYSTEM_PYTHON=true
              export TEMPDIR=$(${pkgs.coreutils-full}/bin/mktemp -d)
              export GIT_LFS_SKIP_SMUDGE=1
              git clone https://github.com/NixOS/nixpkgs -b nixos-unstable --depth 1 $TEMPDIR/nixpkgs
              git clone https://github.com/kevoreilly/CAPEv2 --depth 1 $TEMPDIR/cape
              (
                cd $TEMPDIR/cape
                mkdir capev2
                sed -i '/package-mode/d' pyproject.toml
                sed -i '/tool.poetry/d' pyproject.toml
                echo "print(\"Hello World\")" > capev2/__init__.py
                echo "
                [tool.hatch.build.targets.wheel]
                packages = [
                  \"dummy\"
                ]
                " >> pyproject.toml
                uv add -r extra/optional_dependencies.txt
                uv lock
                mkdir nix_workspace
                mv pyproject.toml nix_workspace
                mv uv.lock nix_workspace
                mv capev2 nix_workspace
              )
              tar -cv --zstd -f $TEMPDIR/nixpkgs.tar.zst -C $TEMPDIR nixpkgs
              sudo rm -rf /etc/nixos/stuff/nixpkgs.tar.zst
              sudo rm -rf /etc/nixos/modules/system/cape/nix_workspace
              sudo cp -r $TEMPDIR/cape/nix_workspace /etc/nixos/modules/system/cape
              sudo cp $TEMPDIR/nixpkgs.tar.zst /etc/nixos/stuff
              rm -rf $TEMPDIR
              mkdir -p ~/.cache/flake-lock-backups
              cp /etc/nixos/flake.lock ~/.cache/flake-lock-backups/"flake.lock_''${(%):-%D{%Y.%m.%d_%H:%M:%S}}"
              sudo nix flake update --flake /etc/nixos
              nh os switch /etc/nixos
            )
          }
          detach-from-nixos() { patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $@ }
          umu-run() { umu-run-wrapper $@ }
          u() { nh os switch /etc/nixos $@ }
          nsl-full() { ${inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/nix-locate $@ }
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
              "nix-search --index-path \"${index}\" $@"}
          }
          7z() { 7zz $@ }
          u-test() { nh os test /etc/nixos $@ }
          u-boot() { nh os boot /etc/nixos $@ }
          u-build() { nh os build /etc/nixos $@ }
          u-debug() { nix build /etc/nixos\#nixosConfigurations.nixos.config.system.build.toplevel --no-link --debugger --ignore-try $@ }
          ns() { ns-dev $@ }
          ns-repl() { nix repl --expr "import (builtins.getFlake \"git+file://${nix-path}?rev=${inputs.nixpkgs.rev}&shallow=1\") { system = \"${pkgs.stdenv.hostPlatform.system}\"; config.allowUnfree = true; }" $@ }
          nsl() { nix-locate $@ }
          fastfetch() { command fastfetch --logo-color-1 'blue' --logo-color-2 'blue' $@ }
          cps() { rsync -ahr --progress $@ }
          res() { screen -r $@ }
          record-h264() { gpu-screen-recorder -k h264 -w screen -f 60 -a 'default_output|default_input' -o }
          nvide() { neovide --no-fork $@ }
          c() { 
            clear 
            printf '\n%.0s' {1..100}
            fastfetch $@
          }
          cl() { 
            clear
            printf '\n%.0s' {1..100}
            fastfetch --pipe false | lolcat -b -g 4f05fc:4287f5 $@
          }
          sudoe() { sudo -E $@ }
          suvide() { sudo -E neovide --no-fork $@ }
          cwp() { swww img --transition-type wipe --transition-fps 60 --transition-step 255 $@ }
          record() { gpu-screen-recorder -w screen -f 60 -a 'default_output|default_input' -o $@ }
          fzfd() { fzf | xargs xdg-open $@ }
          ${pkgs.any-nix-shell}/bin/any-nix-shell zsh | source /dev/stdin
          _zsh_nix_bridge
        '';
        initContent =
          let
            zshConfig = ''
              nixos_ascii () {
              echo -n $'\E[34m'
              cat << "EOF"
                _  _ _      ___  ___ 
               | \| (_)_ __/ _ \/ __|
               | .` | \ \ / (_) \__ \
               |_|\_|_/_\_\\___/|___/
              EOF
              }
              export MANPAGER='nvim +Man!'
              printf '\n%.0s' {1..100}
              setopt correct
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
                    if [[ "$curr_word" == *.* ]]; then
                      local packages_string
                      packages_string=$(nix eval --raw --expr "
                        let
                          pkgs = import (builtins.getFlake \"git+file://${nix-path}?rev=${inputs.nixpkgs.rev}&shallow=1\") {
                            system = \"${pkgs.stdenv.hostPlatform.system}\";
                            config.allowUnfree = true;
                          };
                          startAttr = pkgs.''${curr_word%.*};
                          startPrefix = \"''${curr_word%.*}\";
                          childNames = builtins.attrNames startAttr;
                          formattedNames = map (name: \"\''${startPrefix}.\''${name}\") childNames;
                        in
                        builtins.concatStringsSep \"\n\" formattedNames
                      " 2>/dev/null)
                      local -a packages
                      packages=(''${(f)packages_string})
                    elif [[ -f /tmp/nix_completer_cache ]]; then
                      local -a packages
                      packages=( ''${(f)"$(</tmp/nix_completer_cache)"} )
                    else
                      local packages_string
                      packages_string=$(nix eval --raw --expr "
                        builtins.concatStringsSep \"\n\" (
                          builtins.attrNames (
                            import (builtins.getFlake \"git+file://${nix-path}?rev=${inputs.nixpkgs.rev}&shallow=1\") {
                              system = \"x86_64-linux\";
                              config.allowUnfree = true;
                            }
                          )
                        )
                      " 2>/dev/null)
                      print -rn -- "$packages_string" > /tmp/nix_completer_cache
                      local -a packages
                      packages=(''${(f)packages_string})
                    fi

                    local -a suggestions_first
                    suggestions_first=( ''${(M)packages:#"$curr_word"*} )
                    local -a suggestions_second
                    suggestions_second=( ''${(M)packages:#*"$curr_word"*} )

                    typeset -A seen
                    for item in "''${suggestions_first[@]}"; do
                      seen[$item]=1
                    done

                    local -a suggestions_second_unique
                    suggestions_second_unique=()
                    for item in "''${suggestions_second[@]}"; do
                      if [[ -z "''${seen[$item]}" ]]; then
                        suggestions_second_unique+=("$item")
                      fi
                    done

                    local -a suggestions
                    suggestions=( ''${suggestions_first[@]} ''${suggestions_second_unique[@]} )
                    suggestions=( "''${(@)suggestions/#''${attr_prefix}/}" )
                    compadd -M 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} r:|[-_./]=* l:|=*' -a suggestions
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
