{ inputs, lib, ... }:
let
  layout = import ./layout.data.nix;
  disks = layout.disk;
  hasData = disks ? data;
in
assert lib.assertMsg (
  disks ? system
  && lib.all (
    role:
    lib.elem role [
      "system"
      "data"
    ]
  ) (builtins.attrNames disks)
) "Storage requires a system disk and supports only an optional data disk.";
assert lib.assertMsg (
  !hasData || disks.system.device != disks.data.device
) "System and data roles must refer to different disks.";
{
  # The full layout serves the runtime config; the disk-wiping entry may only use the role-isolated configs.
  flake.diskoConfigurations = builtins.mapAttrs (role: disk: {
    disko.devices.disk.${role} = disk;
  }) disks;

  dotnix.modules.nixos = {
    imports = [ inputs.disko.nixosModules.disko ];
    disko.devices = layout;

    services.btrfs.autoScrub = {
      enable = true;
      fileSystems = [ "/" ] ++ lib.optional hasData "/data";
    };

    # Reject writes from regular users while unmounted; no data subdirectories are created inside the placeholder directories.
    systemd.tmpfiles.rules = [
      "d /mnt/btrfs 0700 root root -"
      "d /mnt/btrfs/firebat 0700 root root -"
    ]
    ++ lib.optionals hasData [
      "d /data 0755 root root -"
      "d /mnt/btrfs/asgard 0700 root root -"
    ];
  };

  dotnix.modules.home = { config, ... }: {
    home.file = lib.optionalAttrs hasData (
      builtins.mapAttrs
        (_: path: {
          source = config.lib.file.mkOutOfStoreSymlink path;
        })
        {
          Pictures = "/data/Pictures";
          Videos = "/data/Videos";
          "Documents/backups" = "/data/backups";
        }
    );
  };

  perSystem = { inputs', ... }: {
    packages.disko = inputs'.disko.packages.default;
  };
}
