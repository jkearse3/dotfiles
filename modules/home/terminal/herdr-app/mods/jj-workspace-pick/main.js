// Opens `herdr-jj-workspace prompt-add --host app --pick` in a popup
// terminal, so a key binding (`ctrl-b shift-g`) can create a jj workspace in
// a repository picked with fzf: `mod.open` takes only a mod name. The picker
// lists the focused terminal's jj repository first, so Enter with an empty
// query picks it, then the jj repositories of the spaces open on this
// machine, one line per repository however many of its workspaces are open.
// Enter asks for a name, runs `jjx workspace add` from `trunk()`, and opens
// and focuses the new space; Esc closes the popup without creating anything.
// `jj-workspace-new` (`ctrl-b ctrl-g`) skips the picker and uses the focused
// terminal's repository.
//
// `launcher.js` and `paths.js` beside this file are copied in at build time
// from `mod-lib/` (deploy.nix `sharedModFiles`); edit them there. This source
// folder lacks them.

import { View, div } from "gpui-kit";
import { home } from "herdr";
import { launch } from "./launcher.js";
import { focusedFolder } from "./paths.js";

export default class JjWorkspacePick extends View {
  init(_props, cx) {
    launch(cx, {
      title: "New jj workspace",
      prepare() {
        const first = focusedFolder();
        // The picker reads its repositories from the app's spaces and takes
        // the focused folder as an option, not as its working directory, so
        // a removed folder cannot stop `hc run`.
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

  render(_cx) {
    return div();
  }
}
