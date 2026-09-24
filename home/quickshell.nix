# Quickshell: the bar and every panel hyprland.lua's `qs ipc call` binds talk
# to, run as a user service in the graphical session.
{ config, lib, pkgs, username, ... }:

let
  # What AppLaunch.qml appends to PATH when resolving an application to launch.
  # The NixOS equivalents of Debian's /usr/bin and ~/.nix-profile/bin: the
  # per-user profile (home-manager's packages), the system profile, and the
  # setuid wrappers.
  appPath = lib.concatStringsSep ":" [
    "${config.home.homeDirectory}/.local/bin"
    "/etc/profiles/per-user/${username}/bin"
    "/run/current-system/sw/bin"
    "/run/wrappers/bin"
  ];

  # The main display comes from the host's hypr/hosts/<host>.lua, which
  # hyprland.nix already requires to exist.
  hostLua = builtins.readFile (./../hypr/hosts + "/${config.calango.host}.lua");
  primaryMonitor =
    let m = builtins.match ''.*primary[ ]*=[ ]*"([^"]+)".*'' hostLua;
    in if m == null
       then throw ("hypr/hosts/${config.calango.host}.lua declares no "
                   + "`primary = \"<output>\"`, so home/quickshell.nix cannot "
                   + "resolve the main display for quickshell/common/Screens.qml.")
       else builtins.head m;

  quickshellConfig = pkgs.runCommand "quickshell-config" { } ''
    cp -r ${./../quickshell} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/theme-switcher/wallpaper-theme/matugen/config.toml" \
      --replace-fail "@quickshellStore@" "$out" \
      --replace-fail "@quickshellState@" "~/.local/state/quickshell"
    substituteInPlace "$out/common/AppLaunch.qml" \
      --replace-fail "@appPath@" '${appPath}'
    substituteInPlace "$out/common/Screens.qml" \
      --replace-fail "@primaryMonitor@" '${primaryMonitor}'
    if grep -rq '@[a-zA-Z]*@' "$out"; then
      echo "unsubstituted token left in the quickshell tree:" >&2
      grep -rn '@[a-zA-Z]*@' "$out" >&2
      exit 1
    fi
  '';

  # The unit's own PATH: every command the QML runs by name.
  runtimeDeps = with pkgs; [
    brightnessctl                                 # OSD, brightness keys
    cliphist                                      # clipboard picker (list/decode/delete)
    wl-clipboard                                  # clipboard picker (wl-copy)
    swaybg                                        # wallpaper
    glib                                          # gio (browser discovery), gsettings (theme switcher)
    libnotify                                     # notifications
    jq                                            # theme switcher, night-light locate.sh
    matugen                                       # wallpaper-derived theming
    wallust                                       # the matugen fallback
    curl                                          # night-light locate.sh geolocation
    hyprland                                      # hyprctl (monitors, layout, borders, blur)
    systemd                                       # systemctl, loginctl, systemd-run
    uwsm                                          # session/SessionMenu.qml "Log out"
    networkmanager                                # nmcli, bar/SystemInfo.qml network pill
    gnugrep                                       # grep, throughout bar/SystemInfo.qml, SystemPanel.qml, MonitorService.qml
    gnused                                        # sed, bar/SystemInfo.qml CPU pill
    gawk                                          # awk, bar/SystemInfo.qml, bar/SystemPanel.qml
    procps                                        # top (CPU pill), ps/pgrep (SystemPanel sampler, WallpaperService)
    findutils                                     # find, wallpaper/WallpaperService.qml scanner
    util-linux                                    # setsid, common/AppLaunch.qml, wallpaper/WallpaperService.qml
    bash coreutils                                # sh, cat, ls, sort, head, cut, mktemp, mv, dirname, ...
    (python3.withPackages (ps: [ ps.pillow ]))    # wallpaper/generate-abstract.py, browser/discover.py
  ];
in
{
  options.calango.quickshellConfig = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    description = "The quickshell config tree, in the store.";
  };

  config = {
    calango.quickshellConfig = quickshellConfig;
    home.packages = [ pkgs.quickshell ]; # qs, for hyprland.lua's ipc binds
    xdg.configFile."quickshell".source = quickshellConfig;

    home.file = {
      ".local/state/quickshell/.keep".text = "";
      ".local/state/quickshell/theme-switcher/.keep".text = "";
    };

    systemd.user.services.quickshell = {
      Unit = {
        Description = "Quickshell shell";
        Documentation = "https://quickshell.outfoxxed.me";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        Wants = [ "tray.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
        X-Restart-Triggers = [ "${quickshellConfig}" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.quickshell}/bin/quickshell";
        Environment = [
          "PATH=${lib.makeBinPath runtimeDeps}"
          "GIO_EXTRA_MODULES=${pkgs.dconf.lib}/lib/gio/modules"
        ];
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "app.slice";
        KillMode = "process";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
