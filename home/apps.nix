# User applications, and calango-open: the default browser, which hands each
# link to Quickshell's browser picker.
{ config, lib, pkgs, ... }:

let
  calangoOpenBin = pkgs.runCommand "calango-open" { } ''
    install -Dm755 ${./../bin/calango-open} "$out/libexec/calango-open"
    substituteInPlace "$out/libexec/calango-open" \
      --replace-fail '@quickshellSource@' '${config.calango.quickshellConfig}'
    if grep -q '@[a-zA-Z]*@' "$out/libexec/calango-open"; then
      echo "unsubstituted token left in calango-open:" >&2
      grep -n '@[a-zA-Z]*@' "$out/libexec/calango-open" >&2
      exit 1
    fi
  '';

  calangoOpen = pkgs.writeShellScriptBin "calango-open" ''
    export PATH=${lib.makeBinPath (with pkgs; [ quickshell python3 glib ])}''${PATH:+:$PATH}
    exec ${pkgs.bash}/bin/bash ${calangoOpenBin}/libexec/calango-open "$@"
  '';

  calangoOpenDesktop = pkgs.runCommand "calango-open-desktop" { } ''
    install -Dm644 ${./../data/eu.calangotech.CalangoOpen.desktop} \
      "$out/share/applications/eu.calangotech.CalangoOpen.desktop"
    substituteInPlace "$out/share/applications/eu.calangotech.CalangoOpen.desktop" \
      --replace-fail '@calangoOpen@' '${calangoOpen}/bin/calango-open'
  '';
in
{
  home.packages = with pkgs; [
    calangoOpen
    calangoOpenDesktop

    google-chrome
    # bin/code's flags, now passed by nixpkgs' own wrapper.
    (vscode.override {
      commandLineArgs = "--use-angle=vulkan --enable-features=Vulkan,VulkanFromANGLE";
    })
    slack
    signal-desktop
    bitwarden-desktop
    flatpak
    gammastep
    docker-credential-helpers
  ];

  # xdg-settings writes mimeapps.list, which browsers and file managers also
  # edit, so the default browser is set imperatively rather than by making the
  # file a read-only home-manager link.
  home.activation.defaultBrowser = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    previous=$(${pkgs.xdg-utils}/bin/xdg-settings get default-web-browser 2>/dev/null || true)
    if [ "$previous" != "eu.calangotech.CalangoOpen.desktop" ]; then
      run ${pkgs.xdg-utils}/bin/xdg-settings set default-web-browser \
        eu.calangotech.CalangoOpen.desktop \
        || echo "could not set the default browser (was: $previous)" >&2
    fi
  '';
}
