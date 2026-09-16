"""Adapt ordered Zed macOS keymaps to Toshy's Linux modifier identities."""

import json
import itertools
import string
import sys

import json5


def convert(sequence):
    modifiers = {"cmd": "ctrl", "ctrl": "super"}
    return " ".join(
        "-".join(modifiers.get(part, part) for part in chord.split("-"))
        for chord in sequence.split(" ")
    )


def identity(chord):
    parts = chord.split("-")
    return frozenset(parts[:-1]), parts[-1]


def main():
    with open(sys.argv[1]) as source:
        keymap = json5.load(source)
    default_sections = len(keymap)
    for path in sys.argv[2:]:
        with open(path) as source:
            keymap.extend(json5.load(source))
    # These actions require AppKit. Toshy supplies the desktop equivalents.
    desktop_actions = {"zed::Hide", "zed::HideOthers", "zed::ShowAll", "zed::Minimize"}
    for section in keymap:
        section["bindings"] = {
            convert(key): value
            for key, value in section["bindings"].items()
            if not (isinstance(value, str) and value in desktop_actions)
        }
    workspace_bindings = {}
    for section in keymap:
        if section.get("context") == "Workspace":
            workspace_bindings.update(section["bindings"])
    # Terminal fallbacks must not shadow parent actions or their chord prefixes.
    workspace_keys = {
        identity(key.split(" ")[0])
        for key, action in workspace_bindings.items() if action is not None
    }
    for index, section in enumerate(keymap):
        # Later presets must retain their overrides, including explicit unbindings.
        if index < default_sections and section.get("context") == "Terminal":
            # macOS leaves many Control chords to the terminal's native encoder.
            # Linux's encoder cannot infer that Toshy's Super means Control.
            bindings = section["bindings"]
            existing = workspace_keys | {
                identity(key) for key, action in bindings.items() if action is not None
            }
            shifted = dict(zip("`1234567890-=[]\\;',./", '~!@#$%^&*()_+{}|:"<>?'))
            keys = list(string.ascii_lowercase + string.digits) + [
                "space", "backspace", "enter", "tab", "escape", "[", "]", "\\",
                "/", "-", "=", ".", ",", ";", "'", "`", "left", "right", "up",
                "down", "home", "end", "pageup", "pagedown", "delete", "insert",
            ]
            keys += [f"f{index}" for index in range(1, 25)]
            for alt, shift in itertools.product((False, True), repeat=2):
                for key in keys:
                    # GPUI names shifted punctuation by its symbol, without Shift.
                    symbol = shifted.get(key, key) if shift else key
                    input_shift = shift and key not in shifted
                    suffix = ("alt-" if alt else "") + ("shift-" if input_shift else "")
                    chord = f"super-{suffix}{symbol}"
                    if identity(chord) not in existing:
                        # The terminal encodes Control+A..Z as the same control
                        # bytes as a..z, but SendKeystroke parses letters lowercase.
                        output_shift = input_shift and not (not alt and key in string.ascii_lowercase)
                        output_suffix = ("alt-" if alt else "") + ("shift-" if output_shift else "")
                        bindings[chord] = ["terminal::SendKeystroke", f"ctrl-{output_suffix}{symbol}"]
    json.dump(keymap, sys.stdout, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
