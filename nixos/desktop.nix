# The graphical session: Hyprland under uwsm, reached through greetd/tuigreet.
#
# On Debian this took nixGL wrappers, hand-copied uwsm and portal units, D-Bus
# activation files and polkit/PAM overlays. On NixOS all of that is the job of
# the modules below.
{ config, pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    withUWSM = true; # also enables programs.uwsm and its hyprland-uwsm session
    xwayland.enable = true;
  };

  # Same greeter and flags as calango-nix's /etc/greetd/config.toml; the
  # session list comes from the display-manager module rather than /usr/share.
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session = {
      user = "greeter";
      command = builtins.concatStringsSep " " [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
        "--remember --remember-user-session --time --asterisks"
      ];
    };
  };

  # Backend selection carried over from home/portals.nix. programs.hyprland
  # already adds the hyprland portal; gtk is the default for everything else.
  xdg.portal = {
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.hyprland = {
      default = [ "gtk" ];
      "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
      "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
      "org.freedesktop.impl.portal.GlobalShortcuts" = [ "hyprland" ];
      "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
    };
  };

  # The keyring unlocked at login, as /etc/pam.d/greetd did on Debian.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  # gcr's agent is the one SSH agent; openssh's stays off (the NixOS default),
  # which is what masking its units achieved on Debian.
  services.gnome.gcr-ssh-agent.enable = true;
  programs.ssh.startAgent = false;

  # D-Bus services the Quickshell panels read: battery (UPower), the bar's
  # power profile switcher, and the Bluetooth panel.
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  hardware.bluetooth.enable = true;

  # hyprlock authenticates against its own PAM service.
  security.pam.services.hyprlock = { };

  security.polkit.enable = true;

  # gsettings writes through dconf; apply-gtk-theme depends on it.
  programs.dconf.enable = true;

  # The families foot.ini, appearance.conf and hyprland.lua name, plus broad
  # coverage and metric-compatible substitutes for web content.
  fonts = {
    packages = with pkgs; [
      adwaita-fonts
      nerd-fonts.adwaita-mono
      noto-fonts
      noto-fonts-color-emoji
      dejavu_fonts
      liberation_ttf
    ];
    fontconfig.defaultFonts = {
      sansSerif = [ "Adwaita Sans" ];
      monospace = [ "Adwaita Mono" ];
    };
  };
  hardware.graphics.enable = true;

  # Syncthing (home/syncthing.nix): sync protocol and local discovery. This
  # was the calango-syncthing ufw profile on Debian.
  networking.firewall = {
    allowedTCPPorts = [ 22000 ];
    allowedUDPPorts = [ 22000 21027 ];
  };
}
