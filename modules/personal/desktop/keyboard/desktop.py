import json
import os
import re
import subprocess

from xwaykeyz.models.action import Action


with open(os.path.join(os.path.dirname(__config__), "desktop-bindings.json")) as source:
    _desktop_spec = json.load(source)


def desktop_action(component, action):
    def invoke(ctx):
        if ctx.action != Action.PRESS:
            return
        try:
            dbus.SessionBus().call_blocking(
                "org.kde.kglobalaccel",
                "/component/" + re.sub(r"[^a-zA-Z0-9_]", "_", component),
                "org.kde.kglobalaccel.Component", "invokeShortcut", "s",
                (action,), timeout=0.2,
            )
        except dbus.DBusException as exc:
            error(f"Desktop action {component}/{action} failed: {exc}")
    return invoke


def desktop_command(program, *args):
    def launch(ctx):
        if ctx.action != Action.PRESS:
            return
        try:
            subprocess.Popen([_desktop_programs[program], *args], start_new_session=True)
        except OSError as exc:
            error(f"Desktop command {program} failed: {exc}")
    return launch


_desktop_keys = {}
for item in _desktop_spec["actions"]:
    output = desktop_action(item["component"], item["action"])
    for key in item["keys"]:
        _desktop_keys[C(key)] = output

# Physical Option outputs left Alt, so Option+F4 arrives as Alt-F4; keep it ignored
# instead of letting KDE treat it as the Alt+F4 window-close binding.
_desktop_keys[C("Alt-F4")] = ignore_combo

for key in ("F2",):
    for control in ("Super", "LC"):
        _desktop_keys[C(f"{control}-{key}")] = C("F10")

for key in ("RC-Shift-Key_3", "RC-Shift-Key_4", "RC-Shift-Key_5"):
    mode = {"3": "--fullscreen", "4": "--region", "5": "--launchonly"}[key[-1]]
    args = (mode,) if key.endswith("5") else ("--background", mode)
    _desktop_keys[C(key)] = desktop_command("spectacle", *args)
    if not key.endswith("5"):
        for control in ("Super", "LC"):
            _desktop_keys[C(f"{control}-{key}")] = desktop_command(
                "spectacle", *args, "--copy-image"
            )

# Fcitx manages both configured input sources; KDE layout switching is a separate layer.
for control in ("Super", "LC"):
    for extra in ("", "Alt-", "Shift-"):
        _desktop_keys[C(f"{extra}{control}-Space")] = C("LC-Space")
_desktop_keys[C("F20")] = C("LC-Space")

keymap("macOS desktop", _desktop_keys, when=lambda ctx:
    cnfg.screen_has_focus and not ctx_app_is_remote)
