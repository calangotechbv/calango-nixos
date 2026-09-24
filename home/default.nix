# The user layer. Starts empty; each step ports one module from calango-nix.
{ username, ... }:

{
  imports = [ ./hyprland.nix ./foot.nix ./lf.nix ./gtk.nix ./quickshell.nix ./services.nix ./apps.nix ./syncthing.nix ./shell.nix ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";

  # Polkit's authentication dialog.
  services.hyprpolkitagent.enable = true;

  programs.home-manager.enable = true;
}
