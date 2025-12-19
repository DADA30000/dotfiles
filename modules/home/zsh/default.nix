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
        oh-my-zsh.enable = true;
        oh-my-zsh.plugins = [ "sudo" ];
        syntaxHighlighting.enable = true;
        autosuggestion.enable = true;
        enable = true;
        shellAliases.ls = "lsd";
        envExtra = ''
          # Ad-hoc python with modules env
          ns-py () {
            local flags=()
            local pkgs=()
            for arg in "$@"; do
              [[ "$arg" == -* ]] && flags+=("$arg") || pkgs+=("($arg)")
            done

            nix shell "''${flags[@]}" --expr "with import (builtins.getFlake \"git+file://${nix-path}?rev=${inputs.nixpkgs.rev}&shallow=1\") { system = \"${pkgs.stdenv.hostPlatform.system}\"; config.allowUnfree = true; }; python3.withPackages (ps: with ps; [ ''${pkgs[*]} ])"
          }
          # Ad-hoc nix-develop devShell
          ns-dev () {
            local flags=()
            local pkgs=()
            for arg in "$@"; do
              [[ "$arg" == -* ]] && flags+=("$arg") || pkgs+=("($arg)")
            done

            nix develop "''${flags[@]}" --expr "with import (builtins.getFlake \"git+file://${nix-path}?rev=${inputs.nixpkgs.rev}&shallow=1\") { 
              system = \"${pkgs.stdenv.hostPlatform.system}\"; 
              config.allowUnfree = true; 
            }; mkShell rec { 
              buildInputs = let 
                buildInputs_prev = [ ''${pkgs[*]} ]; 
                buildInputs_dev = builtins.map (x: if (x ? dev) then x.dev else x) buildInputs_prev;
              in
                buildInputs_prev ++ buildInputs_dev;
              LD_LIBRARY_PATH = \"\''${lib.makeLibraryPath buildInputs}\";
              PKG_CONFIG_PATH = \"\''${builtins.concatStringsSep \":\" (builtins.map (x: \"\''${x}/lib/pkgconfig\") buildInputs)}\";
            }"
          }
          # Pure nix-shell -p alternative
          ns-old () {
            local flags=()
            local pkgs=()
            for arg in "$@"; do
              [[ "$arg" == -* ]] && flags+=("$arg") || pkgs+=("($arg)")
            done

            nix shell "''${flags[@]}" --expr "with import (builtins.getFlake \"git+file://${nix-path}?rev=${inputs.nixpkgs.rev}&shallow=1\") { system = \"${pkgs.stdenv.hostPlatform.system}\"; config.allowUnfree = true; }; [ ''${pkgs[*]} ]"
          }
          # ad-hoc nix eval expr
          ns-eval () {
            local flags=()
            local pkgs=()
            for arg in "$@"; do
              [[ "$arg" == -* ]] && flags+=("$arg") || pkgs+=("($arg)")
            done

            nix eval "''${flags[@]}" --expr "builtins.concatStringsSep \"\n\" (with import (builtins.getFlake \"git+file://${nix-path}?rev=${inputs.nixpkgs.rev}&shallow=1\") { system = \"${pkgs.stdenv.hostPlatform.system}\"; config.allowUnfree = true; }; [ ''${pkgs[*]} ])"
          }
          # ad-hoc nix build expr
          ns-build () {
            local flags=()
            local pkgs=()
            for arg in "$@"; do
              [[ "$arg" == -* ]] && flags+=("$arg") || pkgs+=("($arg)")
            done

            nix build "''${flags[@]}" --expr "builtins.concatStringsSep \"\n\" (with import (builtins.getFlake \"git+file://${nix-path}?rev=${inputs.nixpkgs.rev}&shallow=1\") { system = \"${pkgs.stdenv.hostPlatform.system}\"; config.allowUnfree = true; }; [ ''${pkgs[*]} ])"
          }
          u-full () {
            echo "Updating locks, switching"
            (
              export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.ssdeep}/lib:${pkgs.graphviz}/lib
              export PATH=$PATH:${pkgs.migrate-to-uv}/bin:${pkgs.uv}/bin
              export PYTHONPATH=${pkgs.python312}/lib/python3.12/site-packages
              export UV_PYTHON=${pkgs.python312}/bin/python
              export UV_NO_MANAGED_PYTHON=true
              export UV_SYSTEM_PYTHON=true
              export TEMPDIR=$(${pkgs.coreutils-full}/bin/mktemp -d)
              export GIT_LFS_SKIP_SMUDGE=1
              sudo rm -rf /etc/nixos/stuff/nixpkgs.tar.zst
              sudo rm -rf /etc/nixos/modules/system/cape/nix_workspace
              git clone https://github.com/NixOS/nixpkgs -b nixos-unstable --depth 5 $TEMPDIR/nixpkgs
              git clone https://github.com/kevoreilly/CAPEv2 --depth 1 $TEMPDIR/cape
              (
                cd $TEMPDIR/cape
                migrate-to-uv
                uv add -r extra/optional_dependencies.txt
                uv lock
                mkdir dummy
                echo "print(\"Hello World\")" > dummy/kek.py
                echo "
                [tool.hatch.build.targets.wheel]
                packages = [
                  \"dummy\"
                ]
                " >> pyproject.toml
                mkdir nix_workspace
                mv pyproject.toml nix_workspace
                mv uv.lock nix_workspace
                mv dummy nix_workspace
              )
              tar -cv --zstd -f $TEMPDIR/nixpkgs.tar.zst -C $TEMPDIR nixpkgs
              sudo cp -r $TEMPDIR/cape/nix_workspace /etc/nixos/modules/system/cape
              sudo cp $TEMPDIR/nixpkgs.tar.zst /etc/nixos/stuff
              rm -rf $TEMPDIR
              sudo nix flake update --flake /etc/nixos
              nh os switch /etc/nixos
            )
          }
          detach-from-nixos() { patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $@ }
          umu-run() { umu-run-wrapper $@ }
          u() { nh os switch /etc/nixos $@ }
          nsl-full() { ${inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/nix-locate }
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
                            system = \"x86_64-linux\";
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
                    compadd -M 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} r:|[-_./]=* l:|=* r:|=*' -a suggestions
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
              _ns-py () {
                _ns_completer shell python3Packages.
              }
              _ns () {
                _ns_completer shell
              }
              _ns-dev () {
                _ns_completer develop
              }
              _ns-eval () {
                _ns_completer eval
              }
              _ns-build () {
                _ns_completer build
              }
              compdef _ns ns
              compdef _ns-dev ns-dev
              compdef _ns-py ns-py
              compdef _ns-eval ns-eval
              compdef _ns-build ns-build
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
