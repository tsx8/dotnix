let
  btrfsOptions = [
    "compress=zstd"
    "noatime"
  ];
  optionalMountOptions = btrfsOptions ++ [
    "nofail"
    "x-systemd.device-timeout=10s"
  ];
in
{
  disk = {
    system = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-Firebat_FETE34-1TB_20230513000292";
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
              mountpoint = "/mnt/btrfs/firebat";
              mountOptions = optionalMountOptions ++ [ "subvolid=5" ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = btrfsOptions;
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = btrfsOptions;
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = btrfsOptions;
                };
              };
            };
          };
        };
      };
    };
    data =
      let
        device = "/dev/disk/by-id/nvme-Asgard_AN4.0_1TNVMe-M.2_80_202302200481";
      in
      {
        type = "disk";
        inherit device;
        content = {
          type = "gpt";
          partitions.data = {
            label = "asgard-data";
            device = "${device}-part1";
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "asgard-data"
              ];
              mountpoint = "/mnt/btrfs/asgard";
              mountOptions = optionalMountOptions ++ [ "subvolid=5" ];
              subvolumes."@data" = {
                mountpoint = "/data";
                mountOptions = optionalMountOptions;
              };
            };
          };
        };
      };
  };
}
