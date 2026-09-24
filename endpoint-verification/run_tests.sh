#!/bin/sh
#
# Tests for the screen-lock probe in device_state.sh.
#
# device_state.sh hard-codes absolute paths to its helper binaries, so each
# case runs against a rewritten copy whose pgrep and system-config paths point
# into a throwaway sandbox. Everything else -- awk, grep, kreadconfig -- is the
# real thing.

set -u

CDPATH=''
TESTS_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(dirname -- "$TESTS_DIR")
# The Nix check passes the built script, with its store paths substituted in,
# and a TEST_PATH for the stub pgrep's cat: its sandbox has no /usr/bin.
SCRIPT_UNDER_TEST=${SCRIPT_UNDER_TEST:-"$TESTS_DIR/device_state.sh"}

KREADCONFIG=
for candidate in /usr/bin/kreadconfig6 /usr/bin/kreadconfig5; do
  if [ -x "$candidate" ]; then
    KREADCONFIG="$candidate"
    break
  fi
done

PASS=0
FAIL=0
SKIP=0

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT INT TERM

# Rewrite the constants we need to control into sandbox paths.
prepare_script() {
  mkdir -p "$SANDBOX/bin"

  cat >"$SANDBOX/bin/pgrep" <<EOF
#!/bin/sh
# Stub: reports whatever \$SANDBOX/pgrep_out holds, empty file means "no match".
if [ -s "$SANDBOX/pgrep_out" ]; then
  cat "$SANDBOX/pgrep_out"
  exit 0
fi
exit 1
EOF
  chmod 0755 "$SANDBOX/bin/pgrep"

  sed \
    -e "s|^PGREP=.*|PGREP=$SANDBOX/bin/pgrep|" \
    -e "s|^HYPRIDLE_SYSTEM_CONFIG=.*|HYPRIDLE_SYSTEM_CONFIG=$SANDBOX/etc/hypr/hypridle.conf|" \
    "$SCRIPT_UNDER_TEST" >"$SANDBOX/device_state.sh"
  chmod 0755 "$SANDBOX/device_state.sh"
}

# Fresh per-case state: empty fake HOME, no hypridle running, no system config.
reset_case() {
  rm -rf "${SANDBOX:?}/home" "${SANDBOX:?}/etc" "${SANDBOX:?}/pgrep_out"
  mkdir -p "$SANDBOX/home/.config" "$SANDBOX/etc/hypr"
  : >"$SANDBOX/pgrep_out"
}

hypridle_running() {
  echo "${1:-4242 /usr/bin/hypridle}" >"$SANDBOX/pgrep_out"
}

write_config() {
  mkdir -p "$(dirname -- "$1")"
  cat >"$1"
}

# screen_lock_secured as reported for the given desktop environment.
report_for() {
  env -i \
    PATH="${TEST_PATH:-/usr/bin:/bin}" \
    HOME="$SANDBOX/home" \
    XDG_CONFIG_HOME="$SANDBOX/home/.config" \
    XDG_CURRENT_DESKTOP="$1" \
    DESKTOP_SESSION="$2" \
    /bin/sh "$SANDBOX/device_state.sh" 2>/dev/null |
    sed -n 's/^screen_lock_secured: //p'
}

expect() {
  description=$1
  expected=$2
  actual=$3
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "ok   - $description"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL - $description: expected '$expected', got '$actual'"
  fi
}

skip() {
  SKIP=$((SKIP + 1))
  echo "skip - $1: $2"
}

if [ ! -r "$SCRIPT_UNDER_TEST" ]; then
  echo "FAIL - script under test not found: $SCRIPT_UNDER_TEST"
  exit 1
fi

prepare_script

# --- Hyprland ---------------------------------------------------------------

reset_case
hypridle_running
write_config "$SANDBOX/home/.config/hypr/hypridle.conf" <<'EOF'
general {
  lock_cmd = pidof hyprlock || hyprlock
}

listener {
  timeout = 300
  on-timeout = loginctl lock-session
}
EOF
expect "hyprland: lock-on-idle configured and hypridle running is ENABLED" \
  ENABLED "$(report_for Hyprland hyprland)"

reset_case
hypridle_running
write_config "$SANDBOX/home/.config/hypr/hypridle.conf" <<'EOF'
listener {
  timeout = 330
  on-timeout = hyprctl dispatch dpms off
  on-resume = hyprctl dispatch dpms on
}
EOF
expect "hyprland: hypridle that only blanks the screen is DISABLED" \
  DISABLED "$(report_for Hyprland hyprland)"

reset_case
write_config "$SANDBOX/home/.config/hypr/hypridle.conf" <<'EOF'
listener {
  timeout = 300
  on-timeout = loginctl lock-session
}
EOF
expect "hyprland: lock configured but hypridle not running is DISABLED" \
  DISABLED "$(report_for Hyprland hyprland)"

reset_case
hypridle_running
expect "hyprland: hypridle running with no readable config is UNKNOWN" \
  UNKNOWN "$(report_for Hyprland hyprland)"

reset_case
hypridle_running "4242 /usr/bin/hypridle -c $SANDBOX/custom/hypridle.conf"
write_config "$SANDBOX/custom/hypridle.conf" <<'EOF'
listener {
  timeout = 600
  on-timeout = hyprlock
}
EOF
expect "hyprland: config path from hypridle -c is honoured" \
  ENABLED "$(report_for Hyprland hyprland)"

reset_case
hypridle_running
write_config "$SANDBOX/etc/hypr/hypridle.conf" <<'EOF'
listener {
  timeout = 300
  on-timeout = loginctl lock-session
}
EOF
expect "hyprland: system-wide config is used when the user has none" \
  ENABLED "$(report_for Hyprland hyprland)"

reset_case
hypridle_running
write_config "$SANDBOX/home/.config/hypr/hypridle.conf" <<'EOF'
# listener {
#   timeout = 300
#   on-timeout = loginctl lock-session
# }
EOF
expect "hyprland: a commented-out lock listener does not count" \
  DISABLED "$(report_for Hyprland hyprland)"

# uwsm registers the session as hyprland-uwsm rather than plain hyprland.
reset_case
hypridle_running
write_config "$SANDBOX/home/.config/hypr/hypridle.conf" <<'EOF'
listener {
  timeout = 300
  on-timeout = loginctl lock-session
}
EOF
expect "hyprland: uwsm-style session name is recognised" \
  ENABLED "$(report_for Hyprland hyprland-uwsm)"

# --- KDE regression ---------------------------------------------------------

if [ -n "$KREADCONFIG" ]; then
  reset_case
  expect "kde: absent kscreenlockerrc keeps KDE's compiled-in ENABLED default" \
    ENABLED "$(report_for KDE plasma)"

  reset_case
  write_config "$SANDBOX/home/.config/kscreenlockerrc" <<'EOF'
[Daemon]
Autolock=false
EOF
  expect "kde: Autolock=false is DISABLED" \
    DISABLED "$(report_for KDE plasma)"
else
  skip "kde regression cases" "no kreadconfig5/6 on this host"
fi

# --- Unrecognised desktops --------------------------------------------------

reset_case
hypridle_running
expect "unrecognised desktop stays UNKNOWN" \
  UNKNOWN "$(report_for sway sway)"

echo
echo "passed: $PASS  failed: $FAIL  skipped: $SKIP"
[ "$FAIL" -eq 0 ]
