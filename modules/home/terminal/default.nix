{
  ...
}:
{
  imports = [
    ./ghostty
    ./herdr-app
    ./resterm
    ./rex
    ./tmux
  ];

  # How an agent inside a terminal multiplexer runs jobs, servers, and other
  # agents in terminals the user can watch, and how agents it starts report
  # back, as a shared rule in the agent instruction files this repo renders.
  # Each multiplexer's own rule gives the commands for its steps.
  # `packages/rex-agents` repeats the rule's launch and resume steps (stem,
  # result path, harness commands, and instructions) for Rex; change both
  # together.
  agents.sharedRules.agent-terminals = ./agent-terminals.md;
}
