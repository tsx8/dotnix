import argparse
import datetime
import fcntl
import json
import os
import re
import stat
import subprocess
import sys
import uuid
from pathlib import Path


class BackupError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise BackupError(message)


def capture(*args):
    result = subprocess.run(args, text=True, capture_output=True, check=False)
    if result.returncode:
        raise BackupError(f"{args[0]} failed: {result.stderr.strip()[-2000:]}")
    return result.stdout.strip()


def block_number(path):
    info = os.stat(path)
    require(stat.S_ISBLK(info.st_mode), f"Not a block device: {path}")
    return info.st_rdev


def device_identity(spec):
    disk = spec["disk"]
    device = spec["device"]
    require(disk.startswith("/dev/disk/by-id/"), "Whole disks must use by-id paths")
    disk_number = block_number(disk)
    device_number = block_number(device)
    info = json.loads(
        capture("lsblk", "--json", "--nodeps", "--output", "TYPE,MODEL,SERIAL", disk)
    )
    rows = info.get("blockdevices", [])
    require(len(rows) == 1 and rows[0]["type"] == "disk", f"Not one whole disk: {disk}")
    serial = (rows[0].get("serial") or "").strip()
    model = (rows[0].get("model") or "").strip()
    model_id = model.replace(" ", "_").replace("/", "_")
    expected_id = f"nvme-{model_id}_{serial}"
    require(
        model and serial and Path(disk).name in (expected_id, expected_id + "_1"),
        f"Model/serial does not match the by-id path: {disk}",
    )
    parent = capture(
        "lsblk", "--noheadings", "--nodeps", "--raw", "--output", "PKNAME", device
    )
    require(parent and "\n" not in parent, f"Not one disk partition: {device}")
    require(
        block_number("/dev/" + parent) == disk_number,
        f"Partition is on the wrong disk: {device}",
    )
    filesystem_uuid = capture(
        "blkid", "--probe", "--match-tag", "UUID", "--output", "value", device
    )
    require(filesystem_uuid, f"No filesystem UUID: {device}")
    return {
        "number": device_number,
        "disk_number": disk_number,
        "uuid": filesystem_uuid,
        "model": model,
        "serial": serial,
    }


def check_mount(path, identity, fsroot):
    data = json.loads(
        capture(
            "findmnt",
            "--json",
            "--mountpoint",
            path,
            "--output",
            "TARGET,SOURCE,FSTYPE,UUID,FSROOT,OPTIONS",
        )
    )
    rows = data.get("filesystems", [])
    require(len(rows) == 1, f"Not an exact mount point: {path}")
    mount = rows[0]
    require(
        mount["target"] == path and mount["fstype"] == "btrfs",
        f"Not the expected Btrfs mount: {path}",
    )
    require(mount["uuid"] == identity["uuid"], f"Wrong filesystem UUID at {path}")
    require(mount["fsroot"] == fsroot, f"Wrong subvolume at {path}")
    require("rw" in mount["options"].split(","), f"Read-only filesystem at {path}")
    source = mount["source"].split("[", 1)[0]
    require(
        block_number(source) == identity["number"], f"Wrong backing device at {path}"
    )


def check_layout(settings):
    source = device_identity(settings["source"])
    target = device_identity(settings["target"])
    require(
        source["disk_number"] != target["disk_number"],
        "Source and target are on the same disk",
    )
    require(
        source["uuid"] != target["uuid"],
        "Source and target have the same filesystem UUID",
    )
    check_mount(settings["source"]["mount"], source, "/")
    check_mount(settings["target"]["mount"], target, "/")
    check_mount("/", source, "/@root")
    check_mount("/home", source, "/@home")
    check_mount("/data", target, "/@data")
    for spec in (settings["source"], settings["target"]):
        output = capture("btrfs", "filesystem", "show", "--raw", spec["mount"])
        require(
            re.search(r"Total devices\s+1\b", output),
            f"Not a single-device filesystem: {spec['mount']}",
        )
    return {"source": source, "target": target}


def private_directory(path):
    require(path.parent.resolve() == path.parent, f"Symlink in directory path: {path}")
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    info = path.lstat()
    require(
        stat.S_ISDIR(info.st_mode) and info.st_uid == 0,
        f"Not a root-owned directory: {path}",
    )
    require(
        stat.S_IMODE(info.st_mode) == 0o700, f"Directory must have mode 0700: {path}"
    )


def subvolume(path):
    require(path.resolve() == path, f"Symlink in subvolume path: {path}")
    output = capture("btrfs", "subvolume", "show", str(path))
    fields = {}
    # btrfs 7.1 does not support JSON here; snapshot names below this section are not metadata.
    for line in output.splitlines():
        if line.strip() == "Snapshot(s):":
            break
        match = re.match(r"\s+(UUID|Parent UUID|Received UUID|Flags):\s+(.+)$", line)
        if match:
            fields[match[1]] = match[2].strip()
    require(
        set(fields) == {"UUID", "Parent UUID", "Received UUID", "Flags"},
        f"Incomplete subvolume metadata: {path}",
    )
    uuid.UUID(fields["UUID"])
    return fields


def inventory(directory, name):
    return {
        path.name for path in directory.iterdir() if path.name.startswith(name + ".")
    }


def write_receipt(settings, path, receipt):
    check_layout(settings)
    temporary = path.with_suffix(".tmp")
    with temporary.open("x") as output:
        json.dump(receipt, output, ensure_ascii=True, indent=2)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, path)
    descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def backup(settings, preserve, lock_descriptor):
    identities = check_layout(settings)
    available = {}
    for role in ("source", "target"):
        space = os.statvfs(settings[role]["mount"])
        available[role] = space.f_bavail * space.f_frsize
        require(available[role] > 0, f"No available space on {role} filesystem")
        if available[role] < 100 * 1024**3:
            print(
                f"Warning: {role} has {available[role] / 1024**3:.1f} GiB available, below the 100 GiB planning margin",
                file=sys.stderr,
            )
    source_mount = Path(settings["source"]["mount"])
    snapshots = source_mount / "snapshots"
    target = Path(settings["target"]["directory"])
    require(
        target.parent == Path(settings["target"]["mount"]) / "backups",
        "Unexpected target directory",
    )
    for directory in (snapshots, target.parent, target, target / "receipts"):
        private_directory(directory)

    before = {name: inventory(snapshots, name) for name in ("root", "home")}
    sources = {name: subvolume(source_mount / ("@" + name))["UUID"] for name in before}
    run_id = (
        datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ")
        + "-"
        + uuid.uuid4().hex
    )
    receipt_path = target / "receipts" / (run_id + ".json")
    receipt = {
        "started_at": datetime.datetime.now(datetime.UTC).isoformat(),
        "system": os.path.realpath("/run/current-system"),
        "filesystems": identities,
        "available_bytes_before": available,
        "preserve": preserve,
        "status": "running",
        "backups": {},
    }
    command = ["btrbk", "-c", settings["btrbkConfig"]]
    stage = "transfer"
    try:
        # Preserve history on partial failure; the child retains the lock if this coordinator dies.
        subprocess.run(
            command + ["--preserve", "run"], check=True, pass_fds=(lock_descriptor,)
        )
        check_layout(settings)
        for name, old_snapshots in before.items():
            new = inventory(snapshots, name) - old_snapshots
            require(len(new) == 1, f"Expected one new {name} snapshot, got {len(new)}")
            snapshot_name = new.pop()
            snapshot = subvolume(snapshots / snapshot_name)
            received = subvolume(target / snapshot_name)
            require(
                snapshot["Flags"] == "readonly",
                f"Source snapshot is not read-only: {snapshot_name}",
            )
            require(
                snapshot["Parent UUID"] == sources[name],
                f"Wrong snapshot parent: {snapshot_name}",
            )
            require(
                received["Flags"] == "readonly",
                f"Received snapshot is not read-only: {snapshot_name}",
            )
            require(
                received["Received UUID"] == snapshot["UUID"],
                f"Received UUID mismatch: {snapshot_name}",
            )
            receipt["backups"][name] = {
                "name": snapshot_name,
                "source_uuid": snapshot["UUID"],
                "target_uuid": received["UUID"],
            }
        receipt["status"] = "received"
        stage = "receipt"
        write_receipt(settings, receipt_path, receipt)
        if not preserve:
            stage = "cleanup"
            check_layout(settings)
            subprocess.run(command + ["prune"], check=True, pass_fds=(lock_descriptor,))
        receipt["status"] = "complete"
        receipt["finished_at"] = datetime.datetime.now(datetime.UTC).isoformat()
        stage = "receipt"
        write_receipt(settings, receipt_path, receipt)
    except (BackupError, OSError, ValueError, subprocess.CalledProcessError) as error:
        receipt["status"] = stage + "-failed"
        receipt["error"] = str(error)
        receipt["finished_at"] = datetime.datetime.now(datetime.UTC).isoformat()
        try:
            write_receipt(settings, receipt_path, receipt)
        except (BackupError, OSError, ValueError) as receipt_error:
            print(
                f"Could not persist failure receipt: {receipt_error}", file=sys.stderr
            )
        raise BackupError(str(error)) from error
    print(
        f"Backup complete; {'all history preserved' if preserve else 'expired history pruned'}."
    )
    print(f"Receipt: {receipt_path}")


def main():
    parser = argparse.ArgumentParser(
        prog="backup-disks",
        description="Back up Firebat root/home to Asgard, verify receipt metadata, then prune expired versions.",
    )
    parser.add_argument(
        "--preserve",
        action="store_true",
        help="Keep all existing snapshots and backups; use until migration acceptance.",
    )
    args = parser.parse_args(sys.argv[2:])
    require(
        os.geteuid() == 0,
        "Run backup-disks as root; it does not elevate privileges automatically",
    )
    os.umask(0o077)
    os.environ["LC_ALL"] = "C"
    os.environ.pop("BASH_ENV", None)
    with open(sys.argv[1]) as file:
        settings = json.load(file)
    os.environ["TZ"] = settings["timezone"]
    descriptor = os.open(
        "/run/lock/backup-disks.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600
    )
    try:
        info = os.fstat(descriptor)
        require(
            stat.S_ISREG(info.st_mode)
            and info.st_uid == 0
            and stat.S_IMODE(info.st_mode) == 0o600
            and info.st_nlink == 1,
            "Invalid backup lock file",
        )
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise BackupError("Another backup-disks operation is running") from error
        # Keep verified mounts attached if the host unmounts them during the backup.
        os.unshare(os.CLONE_NEWNS)
        capture("mount", "--make-rprivate", "/")
        backup(settings, args.preserve, descriptor)
    finally:
        os.close(descriptor)


if __name__ == "__main__":
    try:
        main()
    except (BackupError, OSError, ValueError, KeyError) as error:
        print(f"backup-disks: {error}", file=sys.stderr)
        sys.exit(1)
