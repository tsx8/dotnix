import json
import os
from pathlib import Path
import stat
import sys
import tempfile


# Native quit covers all windows and preserves beforeunload cancellation.
QUIT_COMMAND = "34031"
QUIT_SHORTCUT = "Control+KeyQ"


class ConfigurationError(RuntimeError):
    pass


def running_browser():
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            if process.stat().st_uid != os.getuid():
                continue
            executable = os.readlink(process / "exe").removesuffix(" (deleted)")
            if Path(executable).name == "helium":
                return True
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            # Sandboxed renderer processes may hide exe; the browser does not.
            continue
    return False


def dictionary(parent, key):
    value = parent.setdefault(key, {})
    if not isinstance(value, dict):
        raise ConfigurationError("invalid preference dictionary")
    return value


def shortcuts(command, key):
    value = command.setdefault(key, [])
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ConfigurationError("invalid shortcut list")
    return value


def configure(document):
    if not isinstance(document, dict):
        raise ConfigurationError("invalid preferences document")
    browser = dictionary(dictionary(document, "helium"), "browser")
    commands = dictionary(browser, "custom_accelerators")
    for command_id, command in commands.items():
        if not isinstance(command, dict):
            raise ConfigurationError("invalid shortcut command")
        if "added" in command:
            added = shortcuts(command, "added")
            if command_id != QUIT_COMMAND:
                command["added"] = [key for key in added if key != QUIT_SHORTCUT]
    quit_command = dictionary(commands, QUIT_COMMAND)
    added = shortcuts(quit_command, "added")
    if QUIT_SHORTCUT not in added:
        added.append(QUIT_SHORTCUT)
    if "removed" in quit_command:
        quit_command["removed"] = [
            key for key in shortcuts(quit_command, "removed") if key != QUIT_SHORTCUT
        ]


def configure_profiles(root):
    # Chromium's live-profile lock is itself a dangling symlink.
    if os.path.lexists(root / "SingletonLock"):
        raise ConfigurationError("Helium profile is locked; leaving its preferences unchanged")
    # Chromium removes SingletonLock before its final profile writes finish.
    if running_browser():
        raise ConfigurationError("Helium is still running; leaving its preferences unchanged")
    profiles = sorted(
        path for path in root.glob("*/Preferences")
        if path.parent.name == "Default" or path.parent.name.startswith("Profile ")
    )
    if not profiles:
        profiles = [root / "Default" / "Preferences"]
    changes = []
    for path in profiles:
        if path.is_symlink() or path.parent.is_symlink():
            raise ConfigurationError("refusing to replace linked browser preferences")
        original = path.read_text() if path.exists() else "{}"
        try:
            document = json.loads(original)
        except json.JSONDecodeError:
            raise ConfigurationError("invalid JSON; leaving all browser preferences unchanged") from None
        before = json.dumps(document, ensure_ascii=False)
        configure(document)
        after = json.dumps(document, ensure_ascii=False)
        if after != before:
            mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
            changes.append((path, after + "\n", mode))
    # Validate every profile before changing any of them.
    for path, content, mode in changes:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                             prefix=".Preferences.", delete=False) as output:
                temporary = Path(output.name)
                output.write(content)
                output.flush()
                os.fchmod(output.fileno(), mode)
                os.fsync(output.fileno())
            os.replace(temporary, path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    return len(changes)


if __name__ == "__main__":
    try:
        count = configure_profiles(Path(sys.argv[1]))
    except ConfigurationError as error:
        print(f"Helium keyboard configuration failed: {error}", file=sys.stderr)
        sys.exit(1)
    except OSError as error:
        print(f"Helium keyboard configuration failed: {error.strerror}", file=sys.stderr)
        sys.exit(1)
    print(f"Configured native Quit in {count} Helium profile(s)")
