# lf, from the lf/ tree, wrapped with the PATH its lfrc commands and previewer
# need.
{ config, lib, pkgs, ... }:

let
  lfSource = ./../lf;

  lfPreview = pkgs.writeShellScriptBin "lf-preview" ''
    export PATH=${lib.makeBinPath (with pkgs; [
      bat coreutils file chafa poppler-utils jq libarchive
    ])}''${PATH:+:$PATH}
    exec ${lfSource}/preview "$@"
  '';

  lfConfig = pkgs.runCommand "lf-config" { } ''
    cp -r ${lfSource} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/lfrc" \
      --replace-fail '@lfPreview@' '${lfPreview}/bin/lf-preview'
    if grep -q '@[a-zA-Z]*@' "$out/lfrc"; then
      echo "unsubstituted token left in lfrc:" >&2
      grep -n '@[a-zA-Z]*@' "$out/lfrc" >&2
      exit 1
    fi
  '';

  lfWrapped = pkgs.symlinkJoin {
    name = "lf-wrapped";
    paths = [ pkgs.lf ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/lf" --prefix PATH : ${lib.makeBinPath (with pkgs; [
        file xdg-utils glib coreutils
      ])}
    '';
  };
in
{
  home.packages = [ lfWrapped ];
  xdg.configFile."lf".source = lfConfig;
}
