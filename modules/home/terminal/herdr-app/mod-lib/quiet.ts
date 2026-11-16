// When a working agent counts as quiet (`quietFor`): it has shown no activity
// (a new report message, turn or state) for `QUIET_MS`, so its row can tell
// a busy agent from a hung one. Quiet only changes how the row draws; it is
// not a status and never makes an agent need you.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/quiet.ts` -> `../../mod-lib/quiet.ts`), and the herdr-app-mods
// build copies the file in place of the link and strips its types to
// `quiet.js`. The app refuses imports that leave a mod's own folder;
// `./quiet.js` beside the importing file is allowed. It imports only types
// from `./status.js`, so linking `status.ts` beside it is enough.

import type { AgentStatus } from "./status.js";

// How long a working agent shows no activity before it counts as quiet, in
// ms: 10 minutes.
export const QUIET_MS = 10 * 60000;

// How long the agent showing `status` has been quiet, in ms: `now -
// activeAt` when it is working and that is at least `QUIET_MS`, else null.
// `activeAt` is when it last showed activity, in ms since the epoch; null
// when unknown, which never counts as quiet. `now` is the time in ms since
// the epoch.
export function quietFor(
  status: AgentStatus | null,
  activeAt: number | null,
  now: number,
): number | null {
  if (status !== "working" || activeAt === null) return null;
  const quietMs = now - activeAt;
  return quietMs >= QUIET_MS ? quietMs : null;
}
