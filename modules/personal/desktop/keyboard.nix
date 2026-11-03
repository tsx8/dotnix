{
  dotnix.modules.nixos =
    { pkgs, ... }:
    {
      services.kanata = {
        enable = true;
        keyboards.capslock = {
          # Preserve ordering when typing immediately after the language-switch tap.
          extraDefCfg = "process-unmapped-keys yes";
          # Layers track our CapsLock pulses only; restart the service with CapsLock off.
          config = ''
            (defsrc caps)
            (deflayer base
              (tap-hold 0 500 (macro C-spc) (multi (macro caps) (layer-switch caps-on))))
            (deflayer caps-on
              (tap-hold 0 500
                (multi (macro caps) (layer-switch base))
                (multi (macro caps C-f24) (layer-switch base))))
          '';
        };
      };

      # Existing uaccess ACLs can leave group::--- even after udev applies MODE=0660.
      system.activationScripts.kanata-uinput-acl = {
        deps = [ "users" ];
        text = ''
          if [ -c /dev/uinput ]; then
            ${pkgs.acl}/bin/setfacl -m g:uinput:rw- /dev/uinput
          fi
        '';
      };
    };
}
