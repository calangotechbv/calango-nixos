# Google Endpoint Verification: the Chrome extension's native helper, which
# reports device posture (serial, disk encryption, screen lock, firewall).
# Replaces the vendor .deb plus endpoint-verification-lock-overlay on Debian.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  prefix = "/opt/google/endpoint-verification";

  endpointVerification = pkgs.callPackage ./../pkgs/endpoint-verification.nix {
    osFirewall = if config.networking.firewall.enable then "yes" else "no";
  };
in
{
  options.calango.endpointVerification = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    description = "The endpoint-verification package as built for this host.";
  };

  config = {
    calango.endpointVerification = endpointVerification;

    # apihelper and Chrome's manifest both name /opt/google/endpoint-verification
    # absolutely. bin/ is a link into the store; var/lib holds the device_attrs
    # the boot service writes, so it is a real, root-owned directory.
    systemd.tmpfiles.rules = [
      "d ${prefix} 0755 root root -"
      "L+ ${prefix}/bin - - - - ${endpointVerification}${prefix}/bin"
      "d ${prefix}/var 0755 root root -"
      "d ${prefix}/var/lib 0755 root root -"
    ];

    # Chrome looks for system-wide native messaging hosts here, NixOS or not.
    environment.etc."opt/chrome/native-messaging-hosts/com.google.endpoint_verification.api_helper.json".source =
      "${endpointVerification}/etc/opt/chrome/native-messaging-hosts/com.google.endpoint_verification.api_helper.json";

    # The vendor unit: `device_state.sh init` as root at boot, writing the
    # serial number and disk encryption state the unprivileged helper cannot
    # read for itself.
    systemd.services.endpoint-verification = {
      description = "Endpoint Verification state initialization";
      after = [
        "local-fs.target"
        "systemd-tmpfiles-setup.service"
      ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ endpointVerification ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${endpointVerification}${prefix}/bin/device_state.sh init";
        StandardOutput = "file:${prefix}/var/lib/device_attrs";
        RemainAfterExit = true;
      };
    };
  };
}
