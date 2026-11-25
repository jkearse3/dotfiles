// A program's icon (`programIcon`) as the app's program table gives it: a
// one-color glyph drawn in a color the caller picks, or a picture.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/program-icon.ts` -> `../../mod-lib/program-icon.ts`), and the
// herdr-app-mods build copies the file in place of the link and strips its
// types to `program-icon.js`. The app refuses imports that leave a mod's own
// folder; `./program-icon.js` beside the importing file is allowed.

import { image, svg } from "gpui-kit";
import type { Color, Element } from "gpui-kit";
import type { Program } from "herdr";

/**
 * Program P's icon, SIZE pixels square and never shrunk by its row: a tinted
 * icon is a glyph drawn in COLOR, any other a picture in its own colors. Null
 * when P is missing or has no icon. Copied from the shipped `agents` mod.
 */
export function programIcon(
  p: Program | undefined,
  size: number,
  color: Color,
): Element | null {
  if (!p?.icon) return null;
  return p.tint
    ? svg(p.icon).size(size).flex_none().text_color(color)
    : image(p.icon).w(size).h(size).flex_none();
}
