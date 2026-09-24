# Checks carried over from calango-nix's flake that still mean something on
# NixOS. Run with `nix flake check`.
{ pkgs, nixos, username }:

let
  hm = nixos.config.home-manager.users.${username};
  toplevel = nixos.config.system.build.toplevel;
in
{
  # The whole system builds, including system.checks (the noise-canceling
  # source guard in nixos/audio.nix).
  system = toplevel;

  # Every home-manager link resolves.
  no-dangling-home-files = pkgs.runCommand "no-dangling-home-files" { } ''
    dir=${hm.home-files}
    if [ ! -e "$dir/.config/hypr/hyprland.lua" ]; then
      echo "$dir has no .config/hypr/hyprland.lua; the layout changed or" >&2
      echo "this path is wrong, so an empty result below would be vacuous." >&2
      exit 1
    fi
    dangling="$(find -L "$dir" -type l || true)"
    if [ -n "$dangling" ]; then
      echo "Dangling symlink(s) under home-files:" >&2
      echo "$dangling" | sed 's/^/  /' >&2
      exit 1
    fi
    touch "$out"
  '';

  # pactl is on PATH but the pulseaudio daemon is not: libpulse autospawns it
  # by bare name, and it would take the ALSA devices from PipeWire.
  no-pulseaudio-daemon = pkgs.runCommand "no-pulseaudio-daemon" { } ''
    for bindir in ${toplevel}/sw/bin ${hm.home.path}/bin; do
      [ -d "$bindir" ] || { echo "$bindir does not exist" >&2; exit 1; }
      if [ -e "$bindir/pulseaudio" ]; then
        echo "a pulseaudio binary is on PATH: $bindir/pulseaudio" >&2
        exit 1
      fi
    done
    if [ ! -e ${toplevel}/sw/bin/pactl ]; then
      echo "no pactl in ${toplevel}/sw/bin; the check above looked in the" >&2
      echo "wrong place rather than proving the daemon absent." >&2
      exit 1
    fi
    touch "$out"
  '';

  # The endpoint-verification overlay's screen-lock tests, run against the
  # script as built: store paths substituted, os-release and ufw.conf absent
  # (the sandbox has neither, as NixOS has no ufw.conf), so a report that
  # aborts under `set -u` fails every case.
  endpoint-verification = pkgs.runCommand "endpoint-verification-tests" { } ''
    export SCRIPT_UNDER_TEST=${nixos.config.calango.endpointVerification}/opt/google/endpoint-verification/bin/device_state.sh
    export TEST_PATH=${pkgs.coreutils}/bin
    ${pkgs.bash}/bin/sh ${./endpoint-verification/run_tests.sh}
    touch "$out"
  '';

  # The bar's title slot QML test, unchanged from calango-nix.
  bar-title-slot = pkgs.runCommand "bar-title-slot"
    { nativeBuildInputs = [ pkgs.qt6.qtdeclarative ]; }
    ''
      export HOME=$TMPDIR
      export XDG_RUNTIME_DIR=$TMPDIR
      export QT_QPA_PLATFORM=offscreen
      export QT_ASSUME_STDERR_HAS_CONSOLE=1
      export QT_LOGGING_RULES='*=true;qt.*=false'
      export QML2_IMPORT_PATH=${pkgs.qt6.qtdeclarative}/lib/qt-6/qml
      export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; }}

      mkdir -p src/quickshell src/test
      cp -r ${./quickshell/bar} src/quickshell/bar
      cp ${./test/title-slot.qml} src/test/title-slot.qml
      cd src

      log=$TMPDIR/qml.log
      if qml test/title-slot.qml > "$log" 2>&1; then status=ok; else status=failed; fi
      cat "$log"
      for want in "bt connected" "bt disconnected" "empty bar" "no room at all"; do
        grep -qF "$want" "$log" || { echo "no line for case: $want" >&2; exit 1; }
      done
      grep -qF PASS "$log" || { echo "the QML test did not report PASS" >&2; exit 1; }
      [ "$status" = ok ] || exit 1
      touch "$out"
    '';
}
