// Opens `herdr-jj-workspace prompt-add --host app --pick` in a popup
// terminal, so a key binding (`ctrl-b shift-g`) can create a jj workspace in
// a repository picked with fzf: `mod.open` takes only a mod name. The picker
// lists the focused terminal's jj repository first, else, when no terminal of
// this machine is focused (a mod pane such as `files` has focus, or the
// space's terminals have exited), the shown space's repository when that
// space is on this machine, so Enter with an empty query picks it. Then it
// lists the jj repositories of the spaces open on this machine, one line per
// repository however many of its workspaces are open.
// Enter asks for a name, then in fzf for the base revision (Enter keeps
// `trunk()`, or pick one of the repository's local bookmarks to stack on it),
// runs `jjx workspace add` on it, and opens and focuses the new space; Esc in
// either picker closes the popup without creating anything.
//
// `launcher.ts` and `paths.ts` beside this file are links to the shared
// copies in `mod-lib/`.

import { View, div } from "gpui-kit";
import type { AsyncContext, Context } from "gpui-kit";
import type { Props } from "gpui-shell";
import { home, spaces } from "herdr";
import { launch } from "./launcher.js";
import { focusedFolder, place } from "./paths.js";

export default class JjWorkspacePick extends View {
  init(_props: Props | undefined, cx: AsyncContext): void {
    launch(cx, {
      title: "New jj workspace",
      prepare() {
        // The focused terminal's folder is the repository the user means.
        // Without one, the shown space's is, where the space is now (its first
        // terminal's live folder) rather than where it was made. A remote
        // space's folder means nothing here, since jj workspaces are made on
        // this machine only.
        const shown = spaces().find((s) => s.active);
        const first =
          focusedFolder() ||
          (shown && shown.machine === null ? place(shown) : "");

        // The picker reads its repositories from the app's spaces and takes
        // the first folder as an option, not as its working directory, so a
        // removed folder cannot stop `hc run`.
        return {
          cli: "herdr-jj-workspace",
          folder: home(),
          args: [
            "prompt-add",
            "--host",
            "app",
            "--pick",
            ...(first ? ["--first", first] : []),
          ],
        };
      },
    });
  }

  render(_cx: Context) {
    return div();
  }
}
