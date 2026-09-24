#!/bin/sh

set -u

AWK=/usr/bin/awk
CAT=/bin/cat
CUT=/usr/bin/cut
DCONF=/usr/bin/dconf
ECHO=/bin/echo
GREP=/bin/grep
GSETTINGS=/usr/bin/gsettings
HOSTNAME_BIN=/bin/hostname
KREADCONFIG5=/usr/bin/kreadconfig5
KREADCONFIG6=/usr/bin/kreadconfig6
LSBLK=/bin/lsblk
MOUNTPOINT=/bin/mountpoint
PGREP=/usr/bin/pgrep
PRINTF=/usr/bin/printf
STAT=/usr/bin/stat
TR=/usr/bin/tr
UDEVADM=/bin/udevadm

INSTALL_PREFIX=/opt/google/endpoint-verification
GENERATED_ATTRS_FILE="$INSTALL_PREFIX/var/lib/device_attrs"

HYPRIDLE_SYSTEM_CONFIG=/etc/hypr/hypridle.conf

# The firewall state on systems without ufw, filled in at build time (NixOS
# substitutes yes or no from networking.firewall.enable). Empty means unknown.
OS_FIREWALL_STATIC=

ACTION=${1:-default}

# Every field printed below starts out empty. A probe that finds nothing leaves
# its field blank; left unset, it would abort the whole report under `set -u`
# -- which is what happened on NixOS, whose os-release is neither ubuntu nor
# debian and which has no /etc/ufw/ufw.conf.
SERIAL_NUMBER=
DISK_ENCRYPTED=
OS_VERSION=
SCREENLOCK_ENABLED=
HOSTNAME=
MODEL=
MAC_ADDRESSES=
OS_FIREWALL=

log_error() {
  echo "$1" 1>&2
}

get_serial_number() {
  SERIAL_NUMBER_FILE=/sys/class/dmi/id/product_serial
  if [ -r "$SERIAL_NUMBER_FILE" ]; then
    SERIAL_NUMBER=$("$CUT" -c -128 "$SERIAL_NUMBER_FILE" | "$TR" -d '"')
  fi
}

get_disk_encrypted() {
  # Major number of the root device in hexadecimal
  ROOT_MAJ_HEX=$("$STAT" / --format="%D" | "$AWK" '{print substr($1, 1, length($1)-2)}')
  # Major number of the root device
  ROOT_MAJ=$("$PRINTF" "%d" 0x"$ROOT_MAJ_HEX")
  if [ "$ROOT_MAJ" = "" ]; then
    # Root device taken from boot command line (/proc/cmdline)
    # Ubuntu: BOOT_IMAGE=/vmlinuz-5.0.0-31-generic root=/dev/mapper/ubuntu--vg-root ro quiet splash
    # Ubuntu: BOOT_IMAGE=/vmlinuz-5.0.0-31-generic root=UUID=2d1f8b16-ea0f-11e9-81b4-2a2ae2dbcce4 ro quiet splash
    # Random: console=ttyO0,115200n8 noinitrd mem=256M root=/dev/mmcblk0p2 rw rootfstype=ext4 rootwait=1 ip=none
    ROOT_DEV=$("$AWK" -v RS=" " '/^root=/ { print substr($0,6) }' /proc/cmdline)
    # udevadmin requires /dev/ file, but cmdline might refer to something else
    # or the line itself might have unexpected format.
    case "$ROOT_DEV" in
      /dev/*) ;;
      *) ROOT_DEV=$("$AWK" '$2 == "/" { print $1 }' /proc/mounts) ;;
    esac
    ROOT_MAJ=$("$UDEVADM" info --query=property "$ROOT_DEV" | "$GREP" MAJOR= | "$CUT" -f2 -d=)
  fi

  # Bail out if not a number
  case "$ROOT_MAJ" in
    ''|*[!0-9]*)
      DISK_ENCRYPTED=UNKNOWN
      return
      ;;
  esac

  # Parent of the root device shares the same major number and minor is zero.
  ROOT_PARENT_DEV_TYPE=$("$LSBLK" -ln -o MAJ:MIN,TYPE | "$AWK" '$1 == "'"$ROOT_MAJ":0'" { print $2 }')
  case "$ROOT_PARENT_DEV_TYPE" in
    '') DISK_ENCRYPTED=UNKNOWN ;;
    'crypt') DISK_ENCRYPTED=ENABLED ;;
    *) DISK_ENCRYPTED=DISABLED ;;
  esac
}

get_os_name_and_version() {
  OS_INFO_FILE=/etc/os-release
  if [ -r "$OS_INFO_FILE" ]; then
    OS_NAME=$("$GREP" -i '^NAME=' "$OS_INFO_FILE" | "$AWK" -F= '{ print $2 }' | "$TR" [:upper:] [:lower:])
    # KDE neon reports NAME="KDE neon" but ID_LIKE="ubuntu debian"; match either.
    OS_LIKE=$("$GREP" -i '^ID_LIKE=' "$OS_INFO_FILE" | "$AWK" -F= '{ print $2 }' | "$TR" [:upper:] [:lower:])
    case "$OS_NAME$OS_LIKE" in
      *ubuntu*|*debian*|*nixos*)
        OS_VERSION=$("$GREP" -i '^VERSION_ID=' "$OS_INFO_FILE" | "$AWK" -F= '{ print $2 }' | "$TR" -d '"')
        ;;
      *)
        ;;
    esac
  else
    log_error "$OS_INFO_FILE is not available."
  fi
}

# hypridle reads the first of these that exists, unless it was started with an
# explicit -c/--config, which is why the running command line is consulted
# first. Leaves HYPRIDLE_CONFIG empty when no config can be found.
get_hypridle_config() {
  HYPRIDLE_CONFIG=$(echo "$HYPRIDLE_PROC" | "$AWK" '{
      for (i = 1; i < NF; i++)
        if ($i == "-c" || $i == "--config") { print $(i + 1); exit }
    }')
  if [ -n "$HYPRIDLE_CONFIG" ]; then
    return
  fi

  for HYPRIDLE_CANDIDATE in \
      "${XDG_CONFIG_HOME:-${HOME:-}/.config}/hypr/hypridle.conf" \
      "${HOME:-}/.config/hypr/hypridle.conf" \
      "$HYPRIDLE_SYSTEM_CONFIG"; do
    if [ -r "$HYPRIDLE_CANDIDATE" ]; then
      HYPRIDLE_CONFIG="$HYPRIDLE_CANDIDATE"
      return
    fi
  done
}

# Hyprland itself has no screen-lock setting: hypridle is what turns an idle
# timeout into a lock, so the session auto-locks only when hypridle is running
# and one of its listeners locks on timeout.
get_hyprland_screenlock_value() {
  HYPRIDLE_PROC=$("$PGREP" -a -x hypridle) || HYPRIDLE_PROC=
  if [ -z "$HYPRIDLE_PROC" ]; then
    # Nothing is watching for idle, so the session never locks by itself.
    LOCK_ENABLED=false
    return
  fi

  HYPRIDLE_CONFIG=
  get_hypridle_config
  if [ ! -r "$HYPRIDLE_CONFIG" ]; then
    # hypridle is running but its config is out of reach; do not guess.
    return
  fi

  if "$AWK" '
      { line = tolower($0); sub(/#.*/, "", line) }
      line ~ /listener[[:space:]]*\{/ { in_listener = 1; next }
      in_listener && line ~ /\}/ { in_listener = 0; next }
      in_listener && line ~ /on-timeout/ &&
        line ~ /lock-session|hyprlock|swaylock|gtklock|waylock/ { found = 1 }
      END { exit found ? 0 : 1 }
    ' "$HYPRIDLE_CONFIG"; then
    LOCK_ENABLED=true
  else
    LOCK_ENABLED=false
  fi
}

get_screenlock_value() {
  # Left empty on purpose: every probe below may decline to set it, and an
  # unset value would abort the whole script under `set -u`.
  LOCK_ENABLED=

  SESSION_SPEC=$(echo "${XDG_CURRENT_DESKTOP:-unset}""${DESKTOP_SESSION:-unset}" | "$TR" [:upper:] [:lower:])
  case "$SESSION_SPEC" in
    *cinnamon*) DESKTOP_ENV=cinnamon ;;
    *gnome*) DESKTOP_ENV=gnome ;;
    *unity*) DESKTOP_ENV=gnome ;;
    *kde*|*plasma*) DESKTOP_ENV=kde ;;
    *hyprland*) DESKTOP_ENV=hyprland ;;
    *)
      SCREENLOCK_ENABLED=UNKNOWN
      return
      ;;
  esac

  # KDE Plasma stores screenlock config in kscreenlockerrc. Autolock defaults
  # to true when the key is absent, which matches KDE's compiled-in default.
  if [ "$DESKTOP_ENV" = kde ]; then
    if [ -x "$KREADCONFIG6" ]; then
      LOCK_ENABLED=$("$KREADCONFIG6" --file kscreenlockerrc --group Daemon --key Autolock --default true)
    elif [ -x "$KREADCONFIG5" ]; then
      LOCK_ENABLED=$("$KREADCONFIG5" --file kscreenlockerrc --group Daemon --key Autolock --default true)
    else
      SCREENLOCK_ENABLED=UNKNOWN
      return
    fi
  elif [ "$DESKTOP_ENV" = hyprland ]; then
    get_hyprland_screenlock_value
  # Try more reliable gsettings first, fall back to dconf
  elif [ -x "$GSETTINGS" ]; then
    # gsettings returns the effective state of the lock-enabled
    LOCK_ENABLED=$("$GSETTINGS" get org."$DESKTOP_ENV".desktop.screensaver lock-enabled)
  elif [ -x "$DCONF" ]; then
    # dconf returns the explicitly set value or nothing in case it has never changed
    LOCK_ENABLED=$("$DCONF" read /org/"$DESKTOP_ENV"/desktop/screensaver/lock-enabled)
    if [ "$LOCK_ENABLED" = "" ]; then
      # Implicit default value is true
      LOCK_ENABLED=true
    fi
  fi

  case "$LOCK_ENABLED" in
    true) SCREENLOCK_ENABLED=ENABLED ;;
    false) SCREENLOCK_ENABLED=DISABLED ;;
    *) SCREENLOCK_ENABLED=UNKNOWN ;;
  esac
}

get_hostname() {
  HOSTNAME="$("$HOSTNAME_BIN")"
}

get_model() {
  MODEL_FILE=/sys/class/dmi/id/product_name
  if [ -r "$MODEL_FILE" ]; then
    MODEL="$("$CAT" "$MODEL_FILE")"
  else
   log_error "$MODEL_FILE is not available."
  fi
}

get_all_mac_addresses() {
  SYS_CLASS_NET=/sys/class/net
  if [ -d "$SYS_CLASS_NET" ]; then
    # filter out loopback mac addr (00:00:00:00:00:00)
    MAC_ADDRESSES=$("$CAT" "$SYS_CLASS_NET"/*/address | "$GREP" -v 00:00:00:00:00:00)
  else
    log_error "$SYS_CLASS_NET is not available."
  fi
}

get_os_firewall() {
  UWF_CONFIG_FILE=/etc/ufw/ufw.conf
  if [ -r "$UWF_CONFIG_FILE" ]; then
    OS_FIREWALL=$("$GREP" -i '^ENABLED=' "$UWF_CONFIG_FILE" | "$AWK" -F= '{ print $2 }' | "$TR" [:upper:] [:lower:])
  elif [ -n "$OS_FIREWALL_STATIC" ]; then
    OS_FIREWALL=$OS_FIREWALL_STATIC
  else
   log_error "$UWF_CONFIG_FILE is not available."
  fi
}

case "$ACTION" in
  init)
    get_serial_number
    get_disk_encrypted

    "$PRINTF" "serial_number: \"%s\"\n" "$SERIAL_NUMBER"
    "$PRINTF" "disk_encrypted: %s\n" "$DISK_ENCRYPTED"

    exit 0
  ;;
esac

# Default action

if [ -r "$GENERATED_ATTRS_FILE" ]; then
  cat "$GENERATED_ATTRS_FILE"
fi

get_os_name_and_version
get_screenlock_value
get_hostname
get_model
get_all_mac_addresses
get_os_firewall

"$PRINTF" "os_version: \"%s\"\n" "$OS_VERSION"
"$PRINTF" "screen_lock_secured: %s\n" "$SCREENLOCK_ENABLED"
"$PRINTF" "hostname: \"%s\"\n" "$HOSTNAME"
"$PRINTF" "model: \"%s\"\n" "$MODEL"
"$PRINTF" "os_firewall: \"%s\"\n" "$OS_FIREWALL"

echo "$MAC_ADDRESSES" | while IFS= read -r item
do
  "$PRINTF" "mac_addresses: \"%s\"\n" "$item"
done
