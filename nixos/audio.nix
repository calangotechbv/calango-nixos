# PipeWire through the NixOS module, plus calango-nix's noise-canceling source
# and the Chrome microphone-volume quirk.
#
# What home/audio.nix did by hand on Debian -- copying the upstream units,
# owning their enablement links, the pipewire-session-manager alias, the
# WirePlumber data dir, LADSPA_PATH for filter-chain -- is the module's job
# here.
{ lib, pkgs, ... }:

let
  noiseCancelingSource = ./../pipewire/50-noise-canceling-source.conf;

  ladspaPackages = [ pkgs.rnnoise-plugin pkgs.ladspaPlugins ];

  # The filter lives in filter-chain.conf.d and runs in pipewire's separate
  # filter-chain.service, so a broken filter cannot take the main daemon down.
  noiseCancelingConf = pkgs.runCommand "noise-canceling-source-conf" { } ''
    install -Dm644 ${noiseCancelingSource} \
      "$out/share/pipewire/filter-chain.conf.d/50-noise-canceling-source.conf"
  '';

  # Chrome drives the microphone's volume on its own; this stops it.
  blockSourceVolumeConf = pkgs.runCommand "block-source-volume-conf" { } ''
    install -Dm644 ${./../pipewire/20-block-source-volume.conf} \
      "$out/share/pipewire/pipewire-pulse.conf.d/20-block-source-volume.conf"
  '';

  # Build-time check, carried over from home/audio.nix: every plugin, label
  # and control the filter config names must exist in the LADSPA libraries
  # PipeWire will load, and both calango.role properties quickshell's audio
  # panel looks for must be present. A misspelt control is otherwise ignored
  # silently.
  noiseCancelingGuard =
    pkgs.runCommand "noise-canceling-source-guard"
      {
        conf = noiseCancelingSource;
        dirs = lib.concatMapStringsSep " " (p: "${p}/lib/ladspa") ladspaPackages;
        builtinSo = "${pkgs.pipewire}/lib/spa-0.2/filter-graph/libspa-filter-graph-plugin-builtin.so";
        nativeBuildInputs = [ pkgs.binutils ];
      }
      ''
        # A state machine over the config, not a list of names. The selector is
        # the PLUGIN name rather than the node type, because the graph now uses
        # two LADSPA plugins from two different packages and `type = ladspa` no
        # longer identifies which library a name must be found in.
        #
        # A control KEY is quoted and sits left of the `=`. A quoted VALUE sits
        # right of it, so the trailing `=` in the pattern is what tells the two
        # apart -- node.description = "Noise Canceling source" must not be read
        # as a control name.
        awk '
          # Comments first, and this rule is not optional. It keeps a future
          # comment from being read as config -- a mention of a plugin or
          # control name in prose would otherwise parse the same as the real
          # thing. Same species as the spec 11 appPath guard, which matched
          # the very comment written to describe it.
          #
          # NOTE for anyone editing this awk program: it is inside a
          # single-quoted shell string, so no apostrophe may appear anywhere
          # in it, comments included. One apostrophe ends the string and the
          # rest of the program becomes shell words.
          /^[[:space:]]*#/ { next }
          # type = is optional in PipeWire filter-graph syntax, so lib must
          # not simply persist from the previous node -- a node that names no
          # plugin and no type would otherwise be checked against whatever
          # library the PRIOR node happened to use. Reset at the name = line
          # that starts every node, before the plugin rule below can set it.
          # Deliberately no next. Verified against the shipped config rather
          # than assumed: this pattern does NOT also catch the modules own
          # header line, { name = libpipewire-module-filter-chain -- the
          # leading brace on that line means it does not start with
          # whitespace then name, so ^ anchors past it. Harmless either way,
          # since that line is followed immediately by a real node whose own
          # type or plugin line sets lib correctly. A node that declares no
          # plugin and no type reaches the orphan branch below.
          /^[[:space:]]*name[[:space:]]*=/ { lib = "" }
          /type[[:space:]]*=[[:space:]]*ladspa/  { lib = ""; next }
          /type[[:space:]]*=[[:space:]]*builtin/ { lib = "builtin"; next }
          match($0, /plugin[[:space:]]*=[[:space:]]*"[^"]+"/) {
            s = substr($0, RSTART, RLENGTH)
            sub(/plugin[[:space:]]*=[[:space:]]*"/, "", s); sub(/"$/, "", s)
            lib = s
            print "PLUGIN " (lib == "" ? "-" : lib) " " s; next
          }
          match($0, /label[[:space:]]*=[[:space:]]*[A-Za-z0-9_]+/) {
            s = substr($0, RSTART, RLENGTH)
            sub(/label[[:space:]]*=[[:space:]]*/, "", s)
            print "LABEL " (lib == "" ? "-" : lib) " " s; next
          }
          # A loop over every match on the line, not a single match(). match()
          # finds only the FIRST occurrence, and the shipped config already
          # has an inline control block on one line --
          # control = { "VAD Threshold (%)" = 50.0 } -- so a second control
          # added to that same line would otherwise go entirely unchecked,
          # silently, with the vacuity anchor below none the wiser since its
          # counters would still be non-zero.
          {
            rest = $0
            while (match(rest, /"[^"]+"[[:space:]]*=/)) {
              s = substr(rest, RSTART, RLENGTH)
              rest = substr(rest, RSTART + RLENGTH)
              sub(/^"/, "", s); sub(/"[[:space:]]*=$/, "", s)
              print "CONTROL " (lib == "" ? "-" : lib) " " s
            }
          }
        ' "$conf" > names.txt

        labels=0
        controls=0
        plugins=0
        bad=0

        # Redirected from a file, never piped: a `while read` on the right of a
        # pipe runs in a subshell and every counter below would be discarded.
        #
        # The awk program above prints "-" rather than leaving lib blank when
        # a name belongs to no plugin. An empty field is invisible to `read`
        # under the default IFS: "LABEL␣␣name" (two spaces, empty middle
        # field) collapses on whitespace, so lib would receive the NEXT
        # non-blank word instead of empty, and name would receive nothing.
        # `[ -z "$lib" ]` against that misparse is never true, so the orphan
        # branch below could never fire -- the build would still fail, but
        # through the wrong branch, blaming a missing .so instead of the real
        # fault: a node with no plugin line at all. The sentinel makes the
        # empty case a real, non-empty token that `read` cannot swallow.
        while read -r kind lib name; do
          # Resolve which library this name must be found in.
          so=""
          if [ "$lib" = "builtin" ]; then
            so="$builtinSo"
            if [ ! -e "$so" ]; then
              echo "The config uses a builtin filter, but pipewire no longer" >&2
              echo "ships its builtin filter-graph plugin at" >&2
              echo "  $so" >&2
              echo "Find where upstream moved it and update builtinSo." >&2
              exit 1
            fi
          elif [ -n "$lib" ]; then
            for d in $dirs; do
              if [ -e "$d/$lib.so" ]; then so="$d/$lib.so"; break; fi
            done
          fi

          if [ "$lib" = "-" ]; then
            echo "nixos/audio.nix's guard read a $kind named '$name' that" >&2
            echo "belongs to no filter node -- no plugin line and no" >&2
            echo "'type = builtin' preceded it in the config. Either a node" >&2
            echo "lost its plugin, or a new node type was added and this" >&2
            echo "guard has not been taught about it." >&2
            exit 1
          fi

          if [ -z "$so" ]; then
            echo "The config names the LADSPA plugin '$lib', but no" >&2
            echo "'$lib.so' exists in any directory of LADSPA_PATH:" >&2
            for d in $dirs; do echo "  $d" >&2; done
            echo "The package that provides it has moved or renamed it. Note" >&2
            echo "the config must NOT be changed to an absolute path --" >&2
            echo "pipewire refuses one; fix ladspaPackages instead." >&2
            bad=1
            continue
          fi

          # A whole-line test, not a substring one. PipeWire matches a control
          # name exactly and IGNORES one it does not know, so a name that is
          # merely a substring of a real port -- "Threshold" against
          # "Threshold (dB)" -- would pass a substring grep and then be
          # silently dropped at runtime, which is the exact failure this
          # guard exists to stop. Measured against the shipped library:
          # `grep -caF -e Threshold gate_1410.so` reads 1, so a truncated
          # name would have gone undetected.
          #
          # Cached to a file rather than piped. `strings ... | grep -q` looks
          # obvious and is wrong here: grep -q exits at the first match and
          # SIGPIPEs strings, and under pipefail the pipeline then reports
          # 141, so the guard would announce a name as missing precisely when
          # it is present.
          cache="strings-$(printf '%s' "$so" | tr -c 'A-Za-z0-9' '_')"
          if [ ! -f "$cache" ]; then
            strings "$so" > "$cache"
          fi

          case "$kind" in
            PLUGIN)
              # Resolution above WAS the existence check, and it is what makes
              # the LADSPA_PATH drop-in honest: some directory it names must
              # really hold this object.
              plugins=$((plugins + 1))
              ;;
            LABEL)
              labels=$((labels + 1))
              # A condition, not a bare grep: this builder runs with errexit,
              # and a grep that matches nothing exits 1.
              if ! grep -qxF -e "$name" "$cache"; then
                echo "The config uses the filter label '$name', which does" >&2
                echo "not appear in $so." >&2
                echo "  (from $conf)" >&2
                echo "Upstream renamed or dropped it. The config's flags do" >&2
                echo "NOT include nofail, so this would fail the unit at" >&2
                echo "runtime rather than pass silently." >&2
                bad=1
              fi
              ;;
            CONTROL)
              controls=$((controls + 1))
              if ! grep -qxF -e "$name" "$cache"; then
                echo "The config sets the control '$name', which does not" >&2
                echo "appear in $so." >&2
                echo "  (from $conf)" >&2
                echo "A control pipewire does not know is IGNORED, so the" >&2
                echo "filter would run at its default instead of the value" >&2
                echo "the config asks for -- silently. Note this guard checks" >&2
                echo "that a NAME exists; it cannot tell you that a filter" >&2
                echo "loads and then emits silence, which is how the builtin" >&2
                echo "noisegate defect reached a live machine." >&2
                bad=1
              fi
              ;;
          esac
        done < names.txt

        # The vacuity anchor. Without it a config the parser cannot read at all
        # -- a reformat, a renamed key, a file replaced by an empty one --
        # produces zero names to check, zero failures, and a guard that reports
        # success having asserted nothing.
        if [ "$plugins" -eq 0 ] || [ "$labels" -eq 0 ] || [ "$controls" -eq 0 ]; then
          echo "The guard parsed $plugins plugin(s), $labels label(s) and" >&2
          echo "$controls control(s) out of" >&2
          echo "  $conf" >&2
          echo "and at least one of those is zero, so it checked nothing." >&2
          echo "The config's syntax has changed under the parser above. Read" >&2
          echo "the file and update the awk program, and do not delete this" >&2
          echo "check -- it is the only thing standing between a reformat and" >&2
          echo "a guard that passes vacuously for ever." >&2
          exit 1
        fi

        [ "$bad" -eq 0 ] || exit 1

        # The two calango.role declarations the audio panel identifies these
        # nodes by. quickshell/audio/AudioService.qml filters on this property
        # rather than on node.name, so that renaming a node does not silently
        # change what the panel shows -- but that indirection only helps while
        # the property is actually there.
        #
        # Losing it degrades SILENTLY and in the wrong direction: the panel
        # stops recognising the filter, so the filtered source reappears in the
        # Input device list and the filter's own capture stream reappears as a
        # permanent "Recording" row. Nothing errors, nothing looks broken, and
        # the cleanup this property exists to enable is simply undone. That is
        # the shape this repository keeps paying for, so it is asserted here.
        # Counted with awk over NON-COMMENT lines, and that is not fastidiousness:
        # written as a plain `grep -c` this read 3, because the comment above the
        # two props blocks explains what calango.role is and names it once in
        # prose. The guard would have failed on a correct config, for the same
        # reason the spec 11 appPath guard PASSED on a broken one -- a check
        # answering to the prose written to describe it. awk also exits 0 on a
        # count of zero, where `grep -c` exits 1 and would abort this builder
        # under errexit before the message below could print.
        roles="$(awk '!/^[[:space:]]*#/ && /calango\.role/ { n++ } END { print n + 0 }' "$conf")"
        if [ "$roles" != 2 ]; then
          echo "The config declares calango.role $roles time(s); the audio" >&2
          echo "panel needs exactly 2 -- one in capture.props and one in" >&2
          echo "playback.props of" >&2
          echo "  $conf" >&2
          echo "quickshell/audio/AudioService.qml finds the filter by that" >&2
          echo "property. Without both, the filtered source returns to the" >&2
          echo "Input list and the filter's capture side returns as a" >&2
          echo "permanent Recording row, with nothing reporting an error." >&2
          exit 1
        fi

        echo "ok: $plugins plugin(s), $labels label(s), $controls control(s), $roles role(s) checked"
        mkdir -p "$out"
      '';

  # pactl and friends without the pulseaudio daemon, which must never be on
  # PATH to autospawn and seize the ALSA devices from PipeWire.
  pulseaudioClients = pkgs.runCommand "pulseaudio-clients" { } ''
    mkdir -p "$out/bin"
    for f in ${pkgs.pulseaudio}/bin/*; do
      name="$(basename "$f")"
      [ "$name" = "pulseaudio" ] && continue
      ln -s "$f" "$out/bin/$name"
    done
    test -e "$out/bin/pactl"
  '';
in
{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
    extraLadspaPackages = ladspaPackages;
    configPackages = [ noiseCancelingConf blockSourceVolumeConf ];
  };

  # Upstream ships filter-chain.service but nothing enables it.
  systemd.user.services.filter-chain = {
    wantedBy = [ "default.target" ];
    restartTriggers = [ noiseCancelingSource ];
  };

  environment.systemPackages = [ pulseaudioClients ];

  system.checks = [ noiseCancelingGuard ];
}
