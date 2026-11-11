// Opens `herdr-jj-workspace prompt-remove --host app` in a popup terminal, so
// a key binding (`ctrl-b ctrl-q`) can remove the jj workspace the shown space
// holds: `mod.open` takes only a mod name. The prompt shows `jjx`'s dry-run
// report, and on confirmation removes the workspace and closes the space; it
// refuses primary checkouts and plain Git worktrees. The popup terminal has
// no space label, so the launcher names the space with `--workspace`.
//
// Remove jj workspaces this way rather than with the app's Remove worktree
// menu item: that item runs `git worktree remove` and leaves jj's record of
// the workspace, which `jj workspace forget <name>` then has to clear.
//
// `launcher.ts` and `paths.ts` beside this file are links to the shared
// copies in `mod-lib/`.

import { View, div } from "gpui-kit";
import type { AsyncContext, Context } from "gpui-kit";
import type { Props } from "gpui-shell";
import { home, spaces } from "herdr";
import { launch } from "./launcher.js";

export default class JjWorkspaceRemove extends View {
  init(_props: Props | undefined, cx: AsyncContext): void {
    launch(cx, {
      title: "Remove jj workspace",
      prepare() {
        const space = spaces().find((s) => s.active);
        // jj workspaces are removed on this machine only.
        if (!space) return { refuse: "No space is shown." };
        if (space.machine !== null) {
          return { refuse: "This space is on another machine." };
        }

        // The prompt finds the checkout from the space, not its own working
        // directory, so it starts at home rather than inside the directory it
        // may delete.
        return {
          cli: "herdr-jj-workspace",
          folder: home(),
          args: ["prompt-remove", "--host", "app", "--workspace", space.id],
        };
      },
    });
  }

  render(_cx: Context) {
    return div();
  }
}
