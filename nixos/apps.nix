# Applications that need system integration: setuid helpers, polkit, daemons
# or groups. On Debian these came from apt and vendor repositories.
{ lib, pkgs, username, ... }:

{
  # The unfree packages this flake installs, named one by one so nothing else
  # unfree slips in.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "1password"
    "1password-cli"
    "endpoint-verification"
    "google-chrome"
    "slack"
    "vscode"
  ];

  # The GUI needs a setgid helper for browser integration and polkit for
  # system-authentication unlock; the CLI needs its own group.
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ username ];
  };

  # docker-ce, with buildx and compose, which nixpkgs builds in.
  virtualisation.docker.enable = true;
  users.users.${username}.extraGroups = [ "docker" ];

  # Seahorse, D-Bus activatable, with its service file on the bus's path.
  programs.seahorse.enable = true;

  services.flatpak.enable = true;
  services.printing.enable = true;
}
