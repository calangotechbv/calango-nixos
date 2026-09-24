# Session daemons the Quickshell panels depend on: the Bluetooth pairing agent,
# the night light (driven by quickshell/night-light) and the NetworkManager
# secret agent that reads wifi keys from the login keyring.
{ config, lib, pkgs, ... }:

let
  nmSecretAgent = pkgs.writeShellScriptBin "nm-secret-agent" ''
    export GI_TYPELIB_PATH=${lib.concatStringsSep ":" [
      "${pkgs.networkmanager}/lib/girepository-1.0"
      "${pkgs.libsecret}/lib/girepository-1.0"
      "${pkgs.glib.out}/lib/girepository-1.0"
    ]}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}
    exec ${pkgs.python3.withPackages (ps: [ ps.pygobject3 ])}/bin/python3 \
      ${./../network/nm-secret-agent} "$@"
  '';
in
{
  home.packages = [ nmSecretAgent ];

  systemd.user.services.bt-agent = {
    Unit = {
      Description = "Bluetooth pairing agent";
      Documentation = "man:bt-agent(1)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      ConditionPathIsDirectory = "/sys/class/bluetooth";
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.bluez-tools}/bin/bt-agent -c NoInputNoOutput";
      KillSignal = "SIGINT";
      Restart = "on-failure";
      RestartSec = 2;
      Slice = "app.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Quickshell's night-light panel writes the mode to its state dir and
  # restarts this unit, whose run.sh reads it and drives gammastep.
  systemd.user.services.night-light = {
    Unit = {
      Description = "Night light (gammastep)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      Type = "simple";
      ExecStart = "${config.calango.quickshellConfig}/night-light/run.sh";
      Environment = [ "PATH=${lib.makeBinPath (with pkgs; [ gammastep gnused coreutils ])}" ];
      Slice = "app.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.nm-secret-agent = {
    Unit = {
      Description = "NetworkManager secret agent (login keyring)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "NetworkManager.service" ];
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "simple";
      ExecStart = "${nmSecretAgent}/bin/nm-secret-agent";
      Restart = "on-failure";
      RestartSec = 2;
      Slice = "app.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
