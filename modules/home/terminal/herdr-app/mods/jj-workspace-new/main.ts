// Opens `herdr-jj-workspace prompt-add --host app` in a popup terminal, so a
// key binding (`ctrl-b ctrl-g`) can create a jj workspace from the focused
// terminal's repository: `mod.open` takes only a mod name. The prompt asks for
// a name, runs `jjx workspace add` from `trunk()`, and opens and focuses the
// new space. It takes the repository from its working directory, so the
// launcher starts it in the focused terminal's live folder, else where the
// space is now (its first terminal's live folder), else the folder the space
// was made in. `jj-workspace-pick` (`ctrl-b shift-g`) picks the repository
// with fzf instead.
//
// `launcher.ts` and `paths.ts` beside this file are links to the shared
// copies in `mod-lib/`.

import { View, div } from "gpui-kit";
import type { AsyncContext, Context } from "gpui-kit";
import type { Props } from "gpui-shell";
import { home, spaces } from "herdr";
import { launch } from "./launcher.js";
import { focusedFolder, place } from "./paths.js";

export default class JjWorkspaceNew extends View {
  init(_props: Props | undefined, cx: AsyncContext): void {
    launch(cx, {
      title: "New jj workspace",
      prepare() {
        const space = spaces().find((s) => s.active);
        // jj workspaces are made on this machine only, so a remote space's
        // folder means nothing here.
        if (!space) return { refuse: "No space is shown." };
        if (space.machine !== null) {
          return { refuse: "This space is on another machine." };
        }

        // The focused terminal's folder is the repository the user means.
        // Without one, the space's first terminal's folder is, since after a
        // `cd` it differs from the folder the space was made in. No folder at
        // all means home, where the prompt reports that there is no jj
        // repository.
        return {
          cli: "herdr-jj-workspace",
          folder: focusedFolder() || place(space) || home(),
          args: ["prompt-add", "--host", "app"],
        };
      },
    });
  }

  render(_cx: Context) {
    return div();
  }
}
