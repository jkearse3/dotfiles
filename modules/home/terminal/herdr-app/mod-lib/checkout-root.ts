// Which checkout holds a folder, from the two cheap root queries the
// desk-spaces sidebar asks there: `jj root` and `git rev-parse
// --show-toplevel`.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/checkout-root.ts` -> `../../mod-lib/checkout-root.ts`), and
// the herdr-app-mods build copies the file in place of the link and strips
// its types to `checkout-root.js`. The app refuses imports that leave a
// mod's own folder; `./checkout-root.js` beside the importing file is
// allowed.

// The root folder of the checkout holding a folder, and which tool's
// checkout it is.
export interface InnermostRoot {
  top: string;
  kind: "jj" | "git";
}

// The innermost checkout holding a folder, given the root `jj root` printed
// there (`jjTop`) and the one `git rev-parse --show-toplevel` printed
// (`gitTop`), each null (or empty) when that tool found no checkout. A
// checkout nested inside another's tree has the longer root, so the longer
// path wins; jj wins a tie, a colocated repo, since jj keeps Git's HEAD
// detached there. Null when neither found one.
export function innermostRoot(
  jjTop: string | null,
  gitTop: string | null,
): InnermostRoot | null {
  if (jjTop && (!gitTop || jjTop.length >= gitTop.length))
    return {
      top: jjTop,
      kind: "jj",
    };
  return gitTop
    ? {
        top: gitTop,
        kind: "git",
      }
    : null;
}
