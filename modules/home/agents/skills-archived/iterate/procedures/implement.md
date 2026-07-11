# Implement

Use only for `Status: active` with `Next: implement`.

This procedure dispatches implementation to a fresh worker. Do not perform implementation directly
in the dispatcher.

Steps:

1. Read the state file fresh.
2. Validate `Status: active` and `Next: implement`. If the pair is invalid, stop and report the
   invalid state.
3. Launch a fresh subagent with `procedures/implement-worker.md` as the worker prompt. Tell the
   worker the workspace root and state-file path, and instruct it to read the state file from disk
   before acting.
4. After the worker returns, ignore the worker summary for routing decisions. Treat it only as a
   diagnostic note.
5. Reread the state file from disk.
6. Route only from the reread `Status` and `Next` fields:
   - `Status: active`, `Next: implement`: return to the active loop for another implement pass.
   - `Status: active`, `Next: verify`: return to the active loop for verify.
   - Any other allowed pair: stop so the main router can handle the state boundary.
7. If the reread control fields are missing or invalid, stop and report the invalid state.

The state file is authoritative.
