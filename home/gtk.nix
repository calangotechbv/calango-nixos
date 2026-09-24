# GTK appearance, pushed by gtk/apply-gtk-theme from gtk/appearance.conf (plus
# gtk/hosts/<host>.conf). The script owns gsettings and the gtk-3.0/gtk-4.0
# settings.ini files, so home-manager's gtk module stays off.
{ config, lib, pkgs, ... }:

let
  gsettingsSchemas =
    "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/"
    + "${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";

  gtkConfig = pkgs.runCommand "gtk-config" { } ''
    cp -r ${./../gtk} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/apply-gtk-theme" \
      --replace-fail '@hyprSource@' '${config.calango.hyprConfig}'
    if [ -f "$out/hosts/${config.calango.host}.conf" ]; then
      substituteInPlace "$out/appearance.conf" \
        --replace-fail '@gtkHostConf@' "$out/hosts/${config.calango.host}.conf"
    else
      substituteInPlace "$out/appearance.conf" \
        --replace-fail '@gtkHostConf@' '/dev/null'
    fi
    for f in "$out/apply-gtk-theme" "$out/appearance.conf"; do
      if grep -q '@[a-zA-Z]*@' "$f"; then
        echo "unsubstituted token left in $f:" >&2
        grep -n '@[a-zA-Z]*@' "$f" >&2
        exit 1
      fi
    done
  '';

  # XDG_DATA_DIRS names the Adwaita icons explicitly: activation runs outside
  # the session, where the script's /usr/share fallback holds nothing on NixOS.
  applyGtkTheme = pkgs.writeShellScriptBin "apply-gtk-theme" ''
    export PATH=${lib.makeBinPath (with pkgs; [
      bash glib coreutils gnugrep gawk gnused diffutils hyprland xrdb dbus systemd
    ])}''${PATH:+:$PATH}
    export XDG_DATA_DIRS=${pkgs.adwaita-icon-theme}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}
    export GSETTINGS_SCHEMA_DIR=${gsettingsSchemas}
    export GIO_EXTRA_MODULES=${pkgs.dconf.lib}/lib/gio/modules
    exec ${pkgs.bash}/bin/bash ${gtkConfig}/apply-gtk-theme "$@"
  '';
in
{
  home.packages = [ applyGtkTheme pkgs.adwaita-icon-theme ];

  home.activation.gtkAppearance = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.bash}/bin/sh -c '
      . ${gtkConfig}/appearance.conf
      exec ${applyGtkTheme}/bin/apply-gtk-theme \
        --theme "$theme" --icons "$icons" \
        --cursor "$cursor" --cursor-size "$cursor_size" \
        --font "$font" --mono-font "$mono_font"
    ' || echo "apply-gtk-theme failed; GTK appearance not pushed" >&2
  '';
}
