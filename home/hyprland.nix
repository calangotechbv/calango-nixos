# Hyprland's config, lock screen and idle policy, ported from calango-nix's
# home/hyprland.nix and home/session.nix without the nixGL wrappers: on NixOS
# the compositor, hyprlock and the portal find the GL drivers on their own.
{ config, lib, pkgs, hostname, ... }:

let
  hyprState = "${config.home.homeDirectory}/.local/state/hypr";
  quickshellState = "${config.home.homeDirectory}/.local/state/quickshell";

  # The hypr/ tree in the store, with its @tokens@ filled in. Fails the build
  # if hyprland.lua gains a token nothing here substitutes.
  hyprConfig = pkgs.runCommand "hypr-config" { } ''
    cp -r ${./../hypr} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/hyprland.lua" \
      --replace-fail '@hyprSource@'      "$out" \
      --replace-fail '@host@'            '${config.calango.host}' \
      --replace-fail '@quickshellState@' '${quickshellState}' \
      --replace-fail '@hyprState@'       '${hyprState}'
    if grep -q '@[a-zA-Z]*@' "$out/hyprland.lua"; then
      echo "unsubstituted token left in hyprland.lua:" >&2
      grep -n '@[a-zA-Z]*@' "$out/hyprland.lua" >&2
      exit 1
    fi
    test -f "$out/hosts/${config.calango.host}.lua" || {
      echo "no hypr/hosts/${config.calango.host}.lua for this host" >&2
      exit 1
    }
  '';

  idleSleep = pkgs.writeShellScriptBin "idle-sleep" ''
    export PATH=${lib.makeBinPath (with pkgs; [ coreutils systemd gnugrep gawk procps ])}''${PATH:+:$PATH}
    exec ${config.calango.hyprConfig}/idle-sleep.sh "$@"
  '';

  # PAM comes from security.pam.services.hyprlock (nixos/desktop.nix), which is
  # hyprlock's default service name, so no auth block is needed. The theme
  # switcher writes the sourced file.
  hyprlockConfig = pkgs.writeText "hyprlock.conf" ''
    source = ${hyprState}/hyprlock.conf
  '';
in
{
  options.calango = {
    host = lib.mkOption {
      type = lib.types.str;
      default = hostname;
      description = "Which hypr/hosts/<name>.lua this configuration bakes in.";
    };
    hyprConfig = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The Hyprland config tree, in the store.";
    };
  };

  config = {
    calango.hyprConfig = hyprConfig;
    xdg.configFile."hypr/hyprland.lua".source = "${hyprConfig}/hyprland.lua";

    # What hyprland.lua's binds and startup hooks call by bare name. On Debian
    # these were baked into the compositor's PATH; here the user profile is on
    # the session's PATH already. foot and lf come from their own modules; qs
    # (Quickshell) arrives in a later step.
    home.packages = with pkgs; [
      bash
      cliphist
      coreutils
      gnugrep
      grim
      jq
      playerctl
      procps
      slurp
      wireplumber
      wl-clipboard
      hyprlock
    ];

    # Reload a running session after a switch, so config changes show at once.
    home.activation.hyprlandReload = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.bash}/bin/sh -c '
        [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || exit 0
        ${pkgs.hyprland}/bin/hyprctl reload >/dev/null 2>&1 || exit 0
        echo "hyprland: reloaded the config of the running session" >&2
      ' || true
    '';

    home.file.".local/state/hypr/.keep".text = "";

    # hyprlock refuses a config whose `source` target is missing; seed an empty
    # one until the theme switcher writes the real thing.
    home.activation.hyprlockConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -e ${lib.escapeShellArg "${hyprState}/hyprlock.conf"} ]; then
        run mkdir -p ${lib.escapeShellArg hyprState}
        run touch ${lib.escapeShellArg "${hyprState}/hyprlock.conf"}
      fi
    '';

    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "${pkgs.procps}/bin/pidof hyprlock || ${pkgs.hyprlock}/bin/hyprlock --config ${hyprlockConfig}";
          before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
          after_sleep_cmd = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
        };
        listener = [
          {
            timeout = 300;
            on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
          }
          {
            timeout = 330;
            on-timeout = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
            on-resume = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
          }
          {
            timeout = 900;
            on-timeout = "${idleSleep}/bin/idle-sleep";
            on-resume = "${idleSleep}/bin/idle-sleep --cancel";
          }
        ];
      };
    };

    # hyprland.lua sets XCURSOR_THEME=Adwaita, size 24.
    home.pointerCursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };
  };
}
