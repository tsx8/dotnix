{ inputs, ... }:
{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.etc."direnv/bash-env".text =
      builtins.replaceStrings [ "@direnv@" "@jq@" ] [ "${pkgs.direnv}/bin/direnv" "${pkgs.jq}/bin/jq" ]
        (builtins.readFile ./bash-env.sh);

    # direnv only reads DIRENV_LOG_FORMAT when a config file exists in ConfDir;
    # an empty file suffices. TOML cannot express disabling logging, so bash-env.sh implements it with an empty value.
    environment.etc."direnv/config.toml".text = "";
  };

  # Agent skill assembly point: the local skills/ tree and external flake inputs are installed alike into
  # ~/.agents/skills/ (the standard Agent Skills location), without binding to a specific harness.
  dotnix.modules.home = {
    home.file.".agents/skills/helium-use".source = ../../skills/helium-use;
    home.file.".agents/skills/obelisk".source = "${inputs.obelisk-skill}/skills/obelisk";
  };
}
