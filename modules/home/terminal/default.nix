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
  agents.sharedRules.agent-terminals = ./agent-terminals.md;
}
