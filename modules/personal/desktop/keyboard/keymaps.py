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
