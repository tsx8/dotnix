{ inputs, ... }: {
  dotnix.modules.nixos =
    { config, ... }:
    let
      coldDevice = "/dev/disk/by-id/nvme-Asgard_AN4.0_1TNVMe-M.2_80_202302200481-part1";
      optionalMountOptions = [
        "compress=zstd"
        "noatime"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    in
    {
      imports = [ inputs.disko.nixosModules.disko ];
      services.btrfs.autoScrub = {
        enable = true;
        fileSystems = [
          "/"
          "/data"
        ];
      };

      # Asgard 在迁移中先接收资料，不能加入安装时会整树擦除的 disko 目标。
      fileSystems = {
        "/data" = {
          device = coldDevice;
          fsType = "btrfs";
          options = optionalMountOptions ++ [ "subvol=@data" ];
        };
        "/mnt/btrfs/asgard" = {
          device = coldDevice;
          fsType = "btrfs";
          options = optionalMountOptions ++ [ "subvolid=5" ];
        };
        "/mnt/btrfs/firebat" = {
          inherit (config.fileSystems."/") device;
          fsType = "btrfs";
          options = optionalMountOptions ++ [ "subvolid=5" ];
        };
      };

      # 只创建不可由普通用户写入的占位目录；资料子目录必须在认盘后初始化。
      systemd.tmpfiles.rules = [
        "d /data 0755 root root -"
        "d /mnt/btrfs 0700 root root -"
        "d /mnt/btrfs/asgard 0700 root root -"
        "d /mnt/btrfs/firebat 0700 root root -"
      ];

      disko.devices.disk.main = {
        type = "disk";
        device = import ./disk-device.data.nix;

        content = {
          type = "gpt";

          partitions = {
            ESP = {
              label = "firebat-esp";
              size = "2G";
              type = "EF00";

              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };

            root = {
              label = "firebat-root";
              size = "100%";

              content = {
                type = "btrfs";
                extraArgs = [
                  "-L"
                  "firebat-system"
                ];

                subvolumes = {
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };

                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };

                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                };
              };
            };
          };
        };
      };

    };
  dotnix.modules.home = { config, ... }: {
    home.file =
      builtins.mapAttrs
        (_: path: {
          source = config.lib.file.mkOutOfStoreSymlink path;
        })
        {
          Pictures = "/data/Pictures";
          Videos = "/data/Videos";
          "Documents/backups" = "/data/backups";
        };
  };

  perSystem = { inputs', ... }: {
    packages.disko = inputs'.disko.packages.default;
  };
}
