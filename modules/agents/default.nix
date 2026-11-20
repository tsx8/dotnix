{ inputs, ... }:
{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.etc."direnv/bash-env".text =
      builtins.replaceStrings [ "@direnv@" "@jq@" ] [ "${pkgs.direnv}/bin/direnv" "${pkgs.jq}/bin/jq" ]
        (builtins.readFile ./bash-env.sh);

    # direnv ignores DIRENV_LOG_FORMAT unless a config file exists.
    environment.etc."direnv/config.toml".text = "";
  };

  dotnix.modules.home = {
    home.file.".agents/skills/obelisk".source = "${inputs.obelisk-skill}/skills/obelisk";
  };
}
