// Which saved folds the desk-spaces sidebar shows open for now because the
// focused terminal moved into them: its focus-reveal rule, as a pure state
// update over fold keys. The sidebar (`trackFocusReveal` in
// `mods/desk-spaces/main.ts`) finds the folds holding the focused terminal
// and keeps the state between renders.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/focus-reveal.ts` -> `../../mod-lib/focus-reveal.ts`), and
// the herdr-app-mods build copies the file in place of the link and strips
// its types to `focus-reveal.js`.

/**
 * The focus-reveal state after a render. A fold is a container that can be
 * saved folded (a machine's spaces, a space's rows, a machine's Background
 * row), named by an opaque key the caller chooses.
 */
export interface FocusReveal {
  /**
   * The folds shown open, without changing their saved fold, because focus
   * moved into them from outside while they were saved folded.
   */
  revealed: Set<string>;
  /** The folds focus is inside. */
  focusFolds: Set<string>;
}

/**
 * The focus-reveal state once focus is inside the folds `inside` (each
 * mapped to whether it is saved folded; empty when focus is in none), given
 * the state of the previous render (`revealed`, `focusFolds`). A reveal
 * ends once focus leaves its fold. A fold focus has just entered from
 * outside is revealed when saved folded; one focus was already inside is
 * not newly revealed, so a fold saved while focus is inside, whose reveal
 * the caller ends on saving, holds while focus moves within it. Reads its
 * arguments without changing them.
 */
export function nextFocusReveal(
  revealed: ReadonlySet<string>,
  focusFolds: ReadonlySet<string>,
  inside: ReadonlyMap<string, boolean>,
): FocusReveal {
  const next = new Set([...revealed].filter((key) => inside.has(key)));
  for (const [key, saved] of inside)
    if (saved && !focusFolds.has(key)) next.add(key);
  return {
    revealed: next,
    focusFolds: new Set(inside.keys()),
  };
}
