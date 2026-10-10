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
  # 完整布局用于运行配置；擦盘入口只能使用按角色隔离的配置。
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

    # 未挂载时拒绝普通用户写入；不在占位目录中创建资料子目录。
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
