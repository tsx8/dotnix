{
  dotnix.modules.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      sourceMount = "/mnt/btrfs/firebat";
      targetMount = "/mnt/btrfs/asgard";
      targetDirectory = "${targetMount}/backups/${config.networking.hostName}";
      btrbkConfig = pkgs.writeText "btrbk-maco.conf" ''
        backend btrfs-progs
        timestamp_format long-iso
        snapshot_dir snapshots
        snapshot_create always
        snapshot_preserve_min latest
        snapshot_preserve no
        target_preserve_min latest
        target_preserve 7d
        incremental yes

        volume ${sourceMount}
          subvolume @root
            snapshot_name root
            target ${targetDirectory}
          subvolume @home
            snapshot_name home
            target ${targetDirectory}
      '';
      settings = pkgs.writeText "backup-disks.json" (
        builtins.toJSON {
          source = {
            disk = config.disko.devices.disk.system.device;
            device = config.fileSystems.${sourceMount}.device;
            mount = sourceMount;
          };
          target = {
            disk = config.disko.devices.disk.data.device;
            device = config.fileSystems."/data".device;
            mount = targetMount;
            directory = targetDirectory;
          };
          timezone = config.time.timeZone;
          btrbkConfig = toString btrbkConfig;
        }
      );
      backupDisks = pkgs.writeShellApplication {
        name = "backup-disks";
        runtimeEnv.TZDIR = "${pkgs.tzdata}/share/zoneinfo";
        runtimeInputs = [
          pkgs.python3
          pkgs.btrbk
          pkgs.btrfs-progs
          pkgs.util-linux
          pkgs.coreutils
        ];
        text = ''
          exec python3 -I ${./backup.py} ${settings} "$@"
        '';
      };
    in
    lib.mkIf (config.disko.devices.disk ? data) {
      environment.systemPackages = [ backupDisks ];
      environment.etc."btrbk/maco.conf".source = btrbkConfig;
      system.build.backupDisks = backupDisks;
    };
}
