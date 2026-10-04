export PATH="%{{{lib.makeBinPath [ pkgs.rustup pkgs.gnugrep pkgs.coreutils ]}}}:$PATH"

TOOLCHAIN_PATH="%{{{config.xdg.dataHome}}}/nix-system-toolchain"
RUSTUP_PATH="%{{{config.xdg.dataHome}}}/rustup"
mkdir -p "$RUSTUP_PATH/toolchains"
ln -s "$TOOLCHAIN_PATH" "$RUSTUP_PATH/toolchains/nix-system"
echo 'version = "12"' >"$RUSTUP_PATH/settings.toml"
echo 'default_toolchain = "nix-system"' >>"$RUSTUP_PATH/settings.toml"
