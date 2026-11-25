// Which machines the desk-spaces sidebar lists: the viewer's two saved
// choices (`MachineChoices`: the machines unchecked in the machine picker,
// and whether to hide offline machines), which machines they leave out
// (`machineLeftOut`), and the known machines the sidebar shares for the
// picker (`MachinePickerEntry`, read back with `readMachinePicker`). The
// choices and the known machines go through `shared`, persisted, because
// the sidebar and the top bar's picker are different mods.
//
// Each mod that uses this file links it into its own folder
// (`mods/<mod>/machine-choices.ts` -> `../../mod-lib/machine-choices.ts`),
// and the herdr-app-mods build copies the file in place of the link and
// strips its types to `machine-choices.js`. The app refuses imports that
// leave a mod's own folder. It imports nothing, so `mod-lib-test.mjs` can
// test it under Node.

/**
 * The shared key of the names of the machines unchecked in the machine
 * picker, an array of `hc machine ls` names. A machine not named shows, so
 * one seen for the first time does. This computer is never named.
 */
export const HIDDEN_MACHINES_KEY = "machines.hidden";

/**
 * The shared key of whether machines `hc machine ls` reports unreachable are
 * left out, a boolean; anything else, such as no value yet, means false.
 */
export const HIDE_OFFLINE_MACHINES_KEY = "machines.hide-offline";

/**
 * The shared key of the machines the sidebar gives a header, an array of
 * `MachinePickerEntry` in header order, this computer first. The sidebar
 * writes it; the machine picker reads it.
 */
export const MACHINE_PICKER_KEY = "machines.picker";

/** The viewer's choice of which machines the sidebar lists. */
export interface MachineChoices {
  /** The `hc machine ls` names of the machines unchecked in the picker. */
  hidden: Set<string>;
  /** Whether a machine `hc machine ls` reports unreachable is left out. */
  hideOffline: boolean;
}

/**
 * The choices from the shared values of `HIDDEN_MACHINES_KEY` and
 * `HIDE_OFFLINE_MACHINES_KEY`, as `shared` returns them: a missing or
 * malformed value counts as no choice made, so every machine shows, and a
 * non-string name is dropped.
 */
export function readMachineChoices(
  hiddenValue: unknown,
  hideOfflineValue: unknown,
): MachineChoices {
  const names = Array.isArray(hiddenValue) ? hiddenValue : [];
  return {
    hidden: new Set(names.filter((n): n is string => typeof n === "string")),
    hideOffline: hideOfflineValue === true,
  };
}

/**
 * Why `choices` leave `machine` out of the sidebar: "unchecked" when its box
 * is unchecked, else "offline" when offline machines are hidden and
 * `hc machine ls` reports it unreachable; null when it shows. This computer
 * (name null) always shows. A machine that is connecting or needs a login
 * shows, because it may need the user.
 */
export function machineLeftOut(
  machine: { name: string | null; state: string | null },
  choices: MachineChoices,
): "unchecked" | "offline" | null {
  if (machine.name === null) return null;
  if (choices.hidden.has(machine.name)) return "unchecked";
  if (choices.hideOffline && machine.state === "unreachable") return "offline";
  return null;
}

/** A machine the sidebar gives a header, as the machine picker lists it. */
export interface MachinePickerEntry {
  /** Its `hc machine ls` name; null for this computer. */
  name: string | null;
  /**
   * The name its header shows: this computer's herdr-core name, or "This
   * computer" before that is known.
   */
  label: string;
  /**
   * Its `hc machine ls` state; null for this computer, and for a machine
   * only a space or terminal names.
   */
  state: string | null;
  /**
   * The state badge its header shows ("needs login · 14m"); null while
   * connected and whenever `state` is null.
   */
  badge: string | null;
}

/**
 * The known machines from the shared value of `MACHINE_PICKER_KEY`, as
 * `shared` returns it: an entry without a string label, or with a name,
 * state or badge that is neither a string nor null, is dropped, and a value
 * that is not an array, such as none yet, gives none.
 */
export function readMachinePicker(value: unknown): MachinePickerEntry[] {
  if (!Array.isArray(value)) return [];

  const stringOrNull = (v: unknown): v is string | null =>
    v === null || typeof v === "string";
  return value
    .filter(
      (e) =>
        typeof e?.label === "string" &&
        stringOrNull(e.name) &&
        stringOrNull(e.state) &&
        stringOrNull(e.badge),
    )
    .map((e) => ({
      name: e.name,
      label: e.label,
      state: e.state,
      badge: e.badge,
    }));
}
