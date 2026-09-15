import itertools
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


keymap("Terminal Control editing", {
    C(f"LC-{letter}"): [C(f"MacEdit-LC-{letter}"), None]
    for letter in "aebfpnhdk"
}, when=lambda ctx:
    cnfg.screen_has_focus and not ctx_app_is_remote and ctx_app_is_terminal)


# Zed consumes the macOS keymap with Cmd represented by Ctrl and Control by Super.
# Keep those identities distinct all the way to its Editor/Terminal contexts.
_zed_keys = {}
_zed_modifiers = ("RC", "Super", "Alt", "Shift")
_zed_keynames = (
    "a b c d e f g h i j k l m n o p q r s t u v w x y z "
    "0 1 2 3 4 5 6 7 8 9 "
    "Left Right Up Down Home End Page_Up Page_Down Backspace Delete Insert "
    "Enter Tab Esc Space Grave Minus Equal Left_Brace Right_Brace "
    "Backslash Semicolon Apostrophe Comma Dot Slash "
    "F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 "
    "F13 F14 F15 F16 F17 F18 F19 F20 F21 F22 F23 F24"
).split()
for count in range(1, len(_zed_modifiers) + 1):
    for modifiers in itertools.combinations(_zed_modifiers, count):
        for key in _zed_keynames:
            combo = C("-".join((*modifiers, key)))
            _zed_keys[combo] = combo

for index in range(1, 8):
    _zed_keys.pop(C(f"Super-RC-F{index}"), None)
for letter in "aebfpnhdk":
    _zed_keys[C(f"Super-{letter}")] = [C(f"MacEdit-Super-{letter}"), None]
keymap("Zed macOS actions", _zed_keys, when=lambda ctx:
    cnfg.screen_has_focus and
    matchProps(clas=r"^(dev\.zed\.zed(?:-preview)?|zed)$")(ctx))

keymap("macOS text editing additions", {
    C("Super-h"): C("Backspace"),
}, when=lambda ctx:
    cnfg.screen_has_focus and not ctx_app_is_remote and not ctx_app_is_terminal)


_mac_register_keymap = keymap


def keymap(name, mappings, when=None):
    # Tag existing text macros without changing app conditions or file operations.
    for source, first, last in (
        (C("Super-k"), "Shift-End", "Delete"),
        (C("RC-Backspace"), "Shift-Home", "Backspace"),
    ):
        commands = mappings.get(source)
        if (isinstance(commands, list) and len(commands) == 2
                and commands[0] == C(first)
                and commands[1] in (C("Backspace"), C("Delete"))):
            mappings[source] = [
                C(f"MacEdit-{first}"),
                C(f"MacEdit-{last}"),
                None,
            ]
    return _mac_register_keymap(name, mappings, when)
