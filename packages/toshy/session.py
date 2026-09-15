"""Keep the input grab inside the active, unlocked graphical session."""

import os
import signal
import subprocess
import sys

import dbus
import dbus.mainloop.glib
from gi.repository import GLib


def active_session(bus, uid):
    manager = dbus.Interface(
        bus.get_object("org.freedesktop.login1", "/org/freedesktop/login1"),
        "org.freedesktop.login1.Manager",
    )
    for _, owner, _, _, path in manager.ListSessions():
        if owner != uid:
            continue
        properties = dbus.Interface(
            bus.get_object("org.freedesktop.login1", path),
            "org.freedesktop.DBus.Properties",
        ).GetAll("org.freedesktop.login1.Session")
        if (
            properties["Type"] == "wayland"
            and properties["Desktop"] == "KDE"
            and properties["Active"]
            and not properties["LockedHint"]
        ):
            return True
    return False


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    loop = GLib.MainLoop()
    child = None
    failed = False
    config_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    command = [sys.argv[1], "-w", "-c", f"{config_home}/toshy/toshy_config.py"]

    def stop_child():
        nonlocal child
        if child is not None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
            child = None

    def reconcile(*_):
        nonlocal child, failed
        try:
            if child is not None and child.poll() is not None:
                raise RuntimeError(f"keymapper exited with status {child.returncode}")
            if active_session(bus, os.getuid()):
                if child is None:
                    child = subprocess.Popen(command)
            else:
                stop_child()
        except (dbus.DBusException, OSError, RuntimeError) as exc:
            print(f"Toshy session: {exc}", file=sys.stderr, flush=True)
            stop_child()
            failed = True
            loop.quit()
            return False
        return True

    bus.add_signal_receiver(
        reconcile,
        signal_name="PropertiesChanged",
        dbus_interface="org.freedesktop.DBus.Properties",
        bus_name="org.freedesktop.login1",
    )
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: loop.quit())
    GLib.timeout_add_seconds(1, reconcile)
    try:
        if reconcile():
            loop.run()
    finally:
        stop_child()
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
