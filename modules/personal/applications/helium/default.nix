{ inputs, ... }:
{
  dotnix.modules.nixos = {
    imports = [ inputs.helium-browser.nixosModules.default ];

    programs.helium = {
      enable = true;
      flags = [
        "--ozone-platform-hint=auto"
        "--enable-wayland-ime=true"
      ];
      policies.ExtensionInstallForcelist =
        let
          kissTranslator = "bdiifdefkgmcblbcghdlonllpjhhjgof";
          v2exPolish = "onnepejgdiojhiflfoemillegpgpabdm";
          tampermonkey = "dhdgffkkebhmkfjojejmpbldmpobfkfo";
        in
        [
          kissTranslator
          v2exPolish
          tampermonkey
        ];
    };
  };
}
