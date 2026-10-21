from xwaykeyz.models.modifier import Modifier

# The marker lets Fcitx check composition in the same input event;
# a separate D-Bus state query can race with queued keystrokes.
Modifier("MAC_EDIT", aliases=["MacEdit"], key=Key.F22)


def helium_quit(ctx):
    if ctx.action == Action.PRESS:
        # The sentinel prevents the output combo from bypassing the repeat guard.
        return [C("RC-q"), None]


keymap("Helium native quit", {C("RC-q"): helium_quit}, when=lambda ctx:
    cnfg.screen_has_focus and not ctx_app_is_remote and matchProps(clas=r"^helium$")(ctx))


keymap("Konsole clipboard", {
    C("RC-c"): C("LC-Insert"),
    C("RC-v"): C("Shift-LC-v"),
}, when=lambda ctx:
    cnfg.screen_has_focus and matchProps(clas=r"^(konsole|org\.kde\.konsole)$")(ctx))


keymap("Terminal Control editing", {
    C(f"LC-{letter}"): [C(f"MacEdit-LC-{letter}"), None]
    for letter in "aebfpnhdk"
}, when=lambda ctx:
    cnfg.screen_has_focus and ctx_app_is_terminal)


keymap("Terminal native text editing", {
    C("RC-Left"): C("LC-a"),
    C("RC-Right"): C("LC-e"),
    C("RC-Backspace"): C("LC-u"),
    C("RC-Delete"): C("LC-k"),
    C("Alt-Left"): C("Alt-b"),
    C("Alt-Right"): C("Alt-f"),
    C("Shift-Alt-Left"): C("Shift-Alt-Left"),
    C("Shift-Alt-Right"): C("Shift-Alt-Right"),
    C("Alt-Backspace"): C("Alt-Backspace"),
    C("Alt-Delete"): C("Alt-d"),
}, when=lambda ctx:
    cnfg.screen_has_focus and ctx_app_is_terminal)


# The current Mod3 receiver reserves tagged Shift-Home/End for two-step macros.
_gui_control_keys = {
    "a": "Home", "e": "End", "b": "Left", "f": "Right",
    "n": "Down", "p": "Up", "d": "Delete", "h": "Backspace",
}
_gui_editing = {C(f"LC-{letter}"): C(output)
                for letter, output in _gui_control_keys.items()}
_gui_editing.update({C(f"Shift-LC-{letter}"): C(f"Shift-{output}")
                     for letter, output in _gui_control_keys.items()
                     if letter in "aebfnp"})
_gui_editing.update({C("LC-k"): ignore_combo, C("LC-y"): ignore_combo})
keymap("GUI Control editing", _gui_editing, when=lambda ctx:
    cnfg.screen_has_focus and not ctx_app_is_terminal)
