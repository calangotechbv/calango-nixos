# Google Endpoint Verification's native helper, with calango's
# endpoint-verification/device_state.sh in place of the vendor's -- what the
# endpoint-verification-lock-overlay .deb did with dpkg-divert on Debian.
#
# apihelper hardcodes /opt/google/endpoint-verification/bin/device_state.sh,
# so the NixOS module links the store tree to that path.
{ lib
, stdenvNoCC
, fetchurl
, autoPatchelfHook
, dpkg
, coreutils
, dconf
, gawk
, glib
, gnugrep
, inetutils
, procps
, systemdMinimal
, util-linux
, osFirewall ? "" # yes, no or unknown (empty): what os_firewall reports
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "endpoint-verification";
  version = "1765828494702-842239260";

  # The vendor .deb from packages.cloud.google.com/apt, suite
  # endpoint-verification. The hash is the SHA256 apt's index lists for it.
  src = fetchurl {
    url = "https://packages.cloud.google.com/apt/pool/endpoint-verification/endpoint-verification_${finalAttrs.version}_amd64_3bcef7ad4e9e6bf8b16dae869190fca7.deb";
    hash = "sha256-LqglFD/VahDWrjo/JxnNR4M0effdP6pu7X9izi0KxmQ=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    prefix=$out/opt/google/endpoint-verification
    install -Dm755 opt/google/endpoint-verification/bin/apihelper "$prefix/bin/apihelper"
    install -Dm755 ${./../endpoint-verification/device_state.sh} "$prefix/bin/device_state.sh"
    # Kept for comparison when Google ships a new vendor script, as the
    # dpkg-divert kept device_state.sh.distrib.
    install -Dm644 opt/google/endpoint-verification/bin/device_state.sh "$prefix/bin/device_state.sh.distrib"

    install -Dm644 etc/opt/chrome/native-messaging-hosts/com.google.endpoint_verification.api_helper.json \
      "$out/etc/opt/chrome/native-messaging-hosts/com.google.endpoint_verification.api_helper.json"

    runHook postInstall
  '';

  # The script names every tool by absolute path; point each at the store.
  # kreadconfig5/6 stay as they are: absent here, so the KDE probe reports
  # UNKNOWN, as it does on any machine without KDE.
  postInstall = ''
    s=$out/opt/google/endpoint-verification/bin/device_state.sh
    substituteInPlace "$s" \
      --replace-fail 'AWK=/usr/bin/awk'          'AWK=${gawk}/bin/awk' \
      --replace-fail 'CAT=/bin/cat'              'CAT=${coreutils}/bin/cat' \
      --replace-fail 'CUT=/usr/bin/cut'          'CUT=${coreutils}/bin/cut' \
      --replace-fail 'DCONF=/usr/bin/dconf'      'DCONF=${dconf}/bin/dconf' \
      --replace-fail 'ECHO=/bin/echo'            'ECHO=${coreutils}/bin/echo' \
      --replace-fail 'GREP=/bin/grep'            'GREP=${gnugrep}/bin/grep' \
      --replace-fail 'GSETTINGS=/usr/bin/gsettings' 'GSETTINGS=${glib}/bin/gsettings' \
      --replace-fail 'HOSTNAME_BIN=/bin/hostname' 'HOSTNAME_BIN=${inetutils}/bin/hostname' \
      --replace-fail 'LSBLK=/bin/lsblk'          'LSBLK=${util-linux}/bin/lsblk' \
      --replace-fail 'MOUNTPOINT=/bin/mountpoint' 'MOUNTPOINT=${util-linux}/bin/mountpoint' \
      --replace-fail 'PGREP=/usr/bin/pgrep'      'PGREP=${procps}/bin/pgrep' \
      --replace-fail 'PRINTF=/usr/bin/printf'    'PRINTF=${coreutils}/bin/printf' \
      --replace-fail 'STAT=/usr/bin/stat'        'STAT=${coreutils}/bin/stat' \
      --replace-fail 'TR=/usr/bin/tr'            'TR=${coreutils}/bin/tr' \
      --replace-fail 'UDEVADM=/bin/udevadm'      'UDEVADM=${systemdMinimal}/bin/udevadm' \
      --replace-fail 'OS_FIREWALL_STATIC='       'OS_FIREWALL_STATIC=${osFirewall}'
    patchShebangs "$s"

    # Any other absolute /bin or /usr/bin path left behind would fail quietly
    # at runtime, so refuse to build with one (kreadconfig excepted, above).
    left=$(grep -nE '=/(usr/)?bin/' "$s" | grep -v KREADCONFIG || true)
    if [ -n "$left" ]; then
      echo "device_state.sh still names FHS paths:" >&2
      echo "$left" >&2
      exit 1
    fi
  '';

  meta = {
    description = "Google Endpoint Verification native helper, with calango's screen-lock probe";
    homepage = "https://support.google.com/a/answer/9007320";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
