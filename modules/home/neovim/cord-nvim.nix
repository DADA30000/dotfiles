{
  fetchFromGitHub,
  rustPlatform,
  versionCheckHook,
  nix-update-script,
  vimUtils,
}:
let
  version = "2.3.7";
  src = fetchFromGitHub {
    owner = "vyfor";
    repo = "cord.nvim";
    tag = "v${version}";
    hash = "sha256-61Ufq6ndxF6410NyGR6Y0Is3Z+4F4BIUUNMLTHNQCpg=";
  };
  cord-server = rustPlatform.buildRustPackage {
    pname = "cord";
    inherit src version;

    # The version in .github/server-version.txt differs from the one in Cargo.toml
    postPatch = ''
      substituteInPlace .github/server-version.txt \
        --replace-fail "2.3.5" "${version}"
    '';

    cargoHash = "sha256-+ioj1jZiuBqypiOMbBTLE5BSkqL+qpGx1yW24ZUALNY=";

    # cord depends on nightly features
    RUSTC_BOOTSTRAP = 1;

    nativeInstallCheckInputs = [
      versionCheckHook
    ];
    versionCheckProgramArg = "--version";
    doInstallCheck = false;

    meta.mainProgram = "cord";
  };
in
vimUtils.buildVimPlugin {
  pname = "cord.nvim";
  inherit version src;

  # Patch the logic used to find the path to the cord server
  # This still lets the user set config.advanced.server.executable_path
  # https://github.com/vyfor/cord.nvim/blob/v2.2.3/lua/cord/server/fs/init.lua#L10-L15

  doCheck = false;

  postPatch = ''
    substituteInPlace lua/cord/server/fs/init.lua \
      --replace-fail \
        "or M.get_data_path()" \
        "or '${cord-server}'"
  '';

  passthru = {
    updateScript = nix-update-script {
      attrPath = "vimPlugins.cord-nvim.cord-nvim-rust";
    };

    # needed for the update script
    inherit cord-server;
  };

}
