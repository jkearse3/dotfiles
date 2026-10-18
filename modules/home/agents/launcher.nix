# The launch step every agent launcher (`claude`, `pi`, `opencode` and their
# `nono-` variants) ends with, kept in one place so all six run their agent the
# same way.
{ lib, pkgs }:
let
  # caffeinate's `-i` assertion keeps the machine from idle-sleeping for as long
  # as the agent runs; elsewhere the agent runs directly.
  preventIdleSleep = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "/usr/bin/caffeinate -i ";

  # Store paths rather than `runtimeInputs`, so the agent's PATH stays as the
  # caller left it.
  mkdir = "${pkgs.coreutils}/bin/mkdir";
  mktemp = "${pkgs.coreutils}/bin/mktemp";
  stat = "${pkgs.coreutils}/bin/stat";

  # Shell text that gives this launch a private temp root and points TMPDIR and
  # each of `extraTmpdirVariables` at it, so everything the agent writes to temp
  # space belongs to this launch. The shared base `/tmp/agent-$UID` is used only
  # when it is a real directory, not a symlink, owned by the user with mode 0700.
  # When the base fails that check or the root cannot be created, the text warns
  # on stderr and leaves the environment untouched, so a launch never strands.
  # It sets `agent_launch_root` to the root's path, or to empty when it fell back.
  launchRootPrologue = extraTmpdirVariables: ''
    agent_tmp_base=/tmp/agent-$UID
    agent_launch_root=

    # A concurrent launch may win the race to create the base; the check below
    # accepts its result on the same terms as this launch's own.
    ${mkdir} -m 700 "$agent_tmp_base" 2>/dev/null || :
    if [ ! -L "$agent_tmp_base" ] && [ -d "$agent_tmp_base" ] &&
      [ "$(${stat} -c '%u %a' "$agent_tmp_base")" = "$UID 700" ]; then
      agent_launch_root=$(${mktemp} -d "$agent_tmp_base/XXXXXXXX") || agent_launch_root=
    else
      echo "''${0##*/}: $agent_tmp_base is not a directory owned by you with mode 0700" >&2
    fi

    if [ -n "$agent_launch_root" ]; then
      export ${
        lib.concatMapStringsSep " " (variable: ''${variable}="$agent_launch_root/"'') (
          [ "TMPDIR" ] ++ extraTmpdirVariables
        )
      }
    else
      echo "''${0##*/}: launching with the inherited temp directory" >&2
    fi
  '';
in
# Returns the shell text that ends a launcher by running `commandLine`, the
# agent's already-quoted command and arguments, under the idle-sleep assertion,
# inside a private per-launch temp root. TMPDIR always points at that root;
# `extraTmpdirVariables` names further variables to point there, such as an
# agent's own temp-dir override. The text replaces the launcher process, so the
# agent's exit status is the launcher's.
{
  commandLine,
  extraTmpdirVariables ? [ ],
}:
''
  ${launchRootPrologue extraTmpdirVariables}
  exec ${preventIdleSleep}${commandLine}
''
