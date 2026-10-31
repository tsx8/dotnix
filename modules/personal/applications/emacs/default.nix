{
  dotnix.modules.nixos =
    { pkgs, ... }:
    {
      # pgtk is the Wayland-native build, so frames do not go through XWayland.
      environment.systemPackages = [
        pkgs.emacs-pgtk
        pkgs.nixd
        pkgs.nixfmt
      ];

      environment.variables = {
        EDITOR = "emacsclient";
        VISUAL = "emacsclient";
      };
    };

  dotnix.modules.home =
    { pkgs, ... }:
    {
      xdg.configFile."emacs/init.el".source = ./init.el;

      # Starting with the graphical session gives the daemon the Wayland
      # environment, so emacsclient opens a frame without a cold start.
      services.emacs = {
        enable = true;
        package = pkgs.emacs-pgtk;
        startWithUserSession = "graphical";
      };
    };
}
