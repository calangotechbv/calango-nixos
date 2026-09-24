# Syncthing and its tray. This machine's config.xml (folders, devices, GUI) is
# the authority; nothing here declares it.
{ config, pkgs, ... }:

{
  services.syncthing = {
    enable = true;
    tray = {
      enable = true;
      package = pkgs.syncthingtray;
      command = "syncthingtray qt-widgets-gui --single-instance --wait";
    };
  };

  assertions = [
    {
      assertion = config.systemd.user.services ? syncthing;
      message = ''
        services.syncthing produced no `syncthing` unit, so the assertion
        below asserts nothing. Either the module was disabled or it renamed
        its unit; update this pair together.
      '';
    }
    {
      assertion = !(config.systemd.user.services ? syncthing-init);
      message = ''
        services.syncthing produced `syncthing-init`, which PATCHes
        config.xml over syncthing's REST API: something set `settings`,
        `guiCredentials` or `guiAddress`. config.xml is the authority here;
        remove the option rather than changing its value.
      '';
    }
  ];
}
