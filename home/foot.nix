# foot, from the foot/ tree: the shared foot.ini, its theme, and an optional
# per-host include (foot/hosts/<host>.ini).
{ config, lib, pkgs, ... }:

let
  footState = "${config.home.homeDirectory}/.local/state/foot";

  footConfig = pkgs.runCommand "foot-config" { } ''
    cp -r ${./../foot} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/foot.ini" \
      --replace-fail '@footThemes@' "$out/themes" \
      --replace-fail '@footState@'  '${footState}'
    if [ -f "$out/hosts/${config.calango.host}.ini" ]; then
      substituteInPlace "$out/foot.ini" \
        --replace-fail '@footHostInclude@' \
          "include=$out/hosts/${config.calango.host}.ini"
    else
      substituteInPlace "$out/foot.ini" \
        --replace-fail '@footHostInclude@' \
          "# no foot/hosts/${config.calango.host}.ini on this machine"
    fi
    if grep -q '@[a-zA-Z]*@' "$out/foot.ini"; then
      echo "unsubstituted token left in foot.ini:" >&2
      grep -n '@[a-zA-Z]*@' "$out/foot.ini" >&2
      exit 1
    fi
  '';
in
{
  home.packages = [ pkgs.foot pkgs.xdg-utils ]; # xdg-utils: foot.ini's url launcher
  xdg.configFile."foot".source = footConfig;

  # foot.ini includes theme-colors.ini, which the theme switcher writes; foot
  # refuses to start if an include is missing, so seed an empty one.
  home.file.".local/state/foot/.keep".text = "";
  home.activation.footThemeColors = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e ${lib.escapeShellArg "${footState}/theme-colors.ini"} ]; then
      run mkdir -p ${lib.escapeShellArg footState}
      run touch ${lib.escapeShellArg "${footState}/theme-colors.ini"}
    fi
  '';
}
