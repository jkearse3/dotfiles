// Opens `herdr-space-new` in a popup terminal, so a key binding (`ctrl-b
// shift-n`) can make a space: `mod.open` takes only a mod name. The picker
// lists in fzf the focused terminal's live folder first, then the folders
// under the home directory, so Enter with an empty query makes the space
// where you are, as the app's plain `cmd-n` does. Enter makes an unnamed
// space in the picked folder, which the app names after where its first
// terminal is; Esc makes nothing. With no terminal of this machine focused (a
// mod pane, or a terminal of another machine), the picker lists the shown
// space's current folder first: its first terminal's live folder, else the
// folder it was made in. With no shown space, or one on another machine,
// whose folder means nothing here, the picker starts from home.
//
// `launcher.ts` and `paths.ts` beside this file are links to the shared
// copies in `mod-lib/`.

import { View, div } from "gpui-kit";
import { home, spaces } from "herdr";
import { launch } from "./launcher.js";
import { focusedFolder, place } from "./paths.js";

export default class SpaceNew extends View {
  init(_props, cx) {
    launch(cx, {
      title: "New space",
      prepare() {
        // The picker lists this machine's folders, so with a remote space
        // shown it starts from home. Otherwise the focused terminal's folder
        // is where the user is; without one, where the shown space is now.
        const space = spaces().find((s) => s.active);
        const folder =
          (space &&
            space.machine === null &&
            (focusedFolder() || place(space))) ||
          home();
        return {
          cli: "herdr-space-new",
          folder: home(),
          args: [folder],
        };
      },
    });
  }

  render(_cx) {
    return div();
  }
}
