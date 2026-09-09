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
        "hehggadaopoacecdllhhajmbjkdcmajg" # ChatGPT for Chrome
        "bdiifdefkgmcblbcghdlonllpjhhjgof" # KISS Translator
        "onnepejgdiojhiflfoemillegpgpabdm" # V2EX Polish
        "dhdgffkkebhmkfjojejmpbldmpobfkfo" # Tampermonkey
      ];
    };
  };
  dotnix.modules.home = { config, ... }: {
    # ChatGPT 只为已识别的浏览器生成通信配置；Helium 复用其更新后的 Chromium 配置。
    xdg.configFile."net.imput.helium/NativeMessagingHosts/com.openai.codexextension.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/chromium/NativeMessagingHosts/com.openai.codexextension.json";
  };
}
