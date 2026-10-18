# The launch step every agent launcher (`claude`, `pi`, `opencode` and their
# `nono-` variants) ends with, kept in one place so all six run their agent the
# same way.
#
# `scratchSweep` is the `scratch-sweep` package, and `exitSweepIdleFor` the
# `--idle-for` duration its exit sweep of the launch root passes.
{
  lib,
  pkgs,
  scratchSweep,
  exitSweepIdleFor,
}:
let
  # caffeinate's `-i` assertion keeps the machine from idle-sleeping for as long
  # as the agent runs; elsewhere the agent runs directly.
  preventIdleSleep = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "/usr/bin/caffeinate -i ";

  # Store paths rather than `runtimeInputs`, so the agent's PATH stays as the
  # caller left it.
  mkdir = "${pkgs.coreutils}/bin/mkdir";
  mktemp = "${pkgs.coreutils}/bin/mktemp";
  stat = "${pkgs.coreutils}/bin/stat";

  # Runs its arguments in a new session, so a signal sent to the launcher's
  # process group, such as the TERM and then KILL an agent host sends to stop a
  # subagent, does not reach them. The fork makes the child a non-leader, which
  # `setsid` requires.
  newSession = "${pkgs.perl}/bin/perl -MPOSIX -e ${lib.escapeShellArg "fork and exit; POSIX::setsid(); exec @ARGV"} --";

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

  # Shell text that runs the agent as a child of the launcher and, once it
  # exits, starts a detached `scratch-sweep clean` of `agent_launch_root` and
  # exits with the agent's status. `trap :` installs a handler rather than
  # ignoring the signals: the agent still gets default dispositions, because
  # handlers reset on exec, while bash defers the handler until the foreground
  # child returns, so the launcher survives a Ctrl-C or a closed terminal long
  # enough to start the sweep. SIGQUIT needs no trap, because bash ignores it in
  # the shell itself while its children keep the default. Without a launch root
  # there is nothing to sweep, so the launcher is replaced by the agent as
  # before.
  runWithExitSweep = commandLine: ''
    if [ -n "$agent_launch_root" ]; then
      trap : HUP INT TERM

      agent_status=0
      ${preventIdleSleep}${commandLine} || agent_status=$?

      # The sweep runs in its own session, so neither a signal to this
      # launcher's process group nor the hangup the kernel sends when this
      # launcher, a terminal's controlling process, exits reaches it. It
      # inherits an ignored SIGHUP to cover the moment before it leaves the
      # group.
      trap "" HUP
      ${newSession} ${lib.getExe' scratchSweep "scratch-sweep"} clean --idle-for ${lib.escapeShellArg exitSweepIdleFor} \
        "$agent_launch_root" >/dev/null 2>&1 </dev/null &

      # Status 130, an agent's death by SIGINT, ends the launcher by SIGINT
      # too, so a calling shell sees the interrupt and stops, say, a loop of
      # `pi -p` runs. Other statuses stay plain exits: agents also exit 129 and
      # 143 from their own HUP and TERM handlers, and bash does not stop a loop
      # when a child dies by SIGQUIT. When SIGINT was ignored on entry, as for
      # a background job of a non-interactive shell, the kill has no effect
      # and 130 is returned as an exit.
      if [ "$agent_status" = 130 ]; then
        trap - INT
        kill -s INT "$$"
      fi
      exit "$agent_status"
    fi

    exec ${preventIdleSleep}${commandLine}
  '';
in
# Returns the shell text that ends a launcher by running `commandLine`, the
# agent's already-quoted command and arguments, under the idle-sleep assertion,
# inside a private per-launch temp root. TMPDIR always points at that root;
# `extraTmpdirVariables` names further variables to point there, such as an
# agent's own temp-dir override. When the agent exits, the launcher removes the
# build output it left in the root through a detached `scratch-sweep clean`, and
# exits with the agent's status. When no root could be created, the agent
# replaces the launcher and nothing is swept.
{
  commandLine,
  extraTmpdirVariables ? [ ],
}:
''
  ${launchRootPrologue extraTmpdirVariables}
  ${runWithExitSweep commandLine}
''
