{ xkeyboard-config }:
xkeyboard-config.overrideAttrs (old: {
  # F13/F14 carry held window switching; F22 distinguishes Rime edits from Cmd actions.
  postInstall = (old.postInstall or "") + ''
    # evdev loads inet after the selected layout, including Fcitx's keyboard-us.
    substituteInPlace "$out/etc/X11/xkb/symbols/inet" \
      --replace-fail 'key <FK13>   {      [ XF86Tools         ]       };' 'key <FK13> { [ F13 ] };' \
      --replace-fail 'key <FK14>   {      [ XF86Launch5       ]       };' 'key <FK14> { [ F14 ] };' \
      --replace-fail 'key <FK22>   {      [ XF86TouchpadOn        ]       };' \
        'key <FK22> { type[Group1]="ONE_LEVEL", [ ISO_Level5_Shift ], actions[Group1]=[ SetMods(modifiers=Mod3) ] }; modifier_map Mod3 { <FK22> };'
  '';
})
