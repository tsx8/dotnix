{ inputs, ... }: {
  dotnix.modules.nixos = {
    imports = [ inputs.helium-browser.nixosModules.default ];
    programs.helium = {
      enable = true;
      flags = [
        "--ozone-platform-hint=auto"
        "--enable-wayland-ime=true"
      ];
      policies.ExtensionInstallForcelist = [
        "bdiifdefkgmcblbcghdlonllpjhhjgof" # KISS Translator
        "onnepejgdiojhiflfoemillegpgpabdm" # V2EX Polish
        "dhdgffkkebhmkfjojejmpbldmpobfkfo" # Tampermonkey
      ];
    };
  };
}
