{ inputs, ... }: {
  dotnix.modules.nixos = {
    imports = [ inputs.disko.nixosModules.disko ];
    services.btrfs.autoScrub.enable = true;

    disko.devices.disk.main = {
      type = "disk";
      device = import ./disk-device.data.nix;

      content = {
        type = "gpt";

        partitions = {
          ESP = {
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
            size = "100%";

            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "nixos"
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
  perSystem = { inputs', ... }: {
    packages.disko = inputs'.disko.packages.default;
  };
}
