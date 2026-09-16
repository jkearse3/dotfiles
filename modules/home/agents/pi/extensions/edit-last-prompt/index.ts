import {
  CustomEditor,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";

import { EditLastPromptGesture, findLatestUserMessageId } from "./gesture.ts";

const EDIT_LAST_PROMPT_COMMAND = "edit-last-prompt";

type EditorFactory = ReturnType<ExtensionContext["ui"]["getEditorComponent"]>;

export default function editLastPromptExtension(pi: ExtensionAPI): void {
  let previousEditorFactory: EditorFactory;
  let installedEditorFactory: EditorFactory;

  pi.registerCommand(EDIT_LAST_PROMPT_COMMAND, {
    description: "Rewind the latest user message and restore it to the editor",
    handler: async (_args, ctx) => {
      if (!ctx.isIdle()) {
        ctx.abort();
        await ctx.waitForIdle();
      }

      if (ctx.ui.getEditorText().trim()) {
        ctx.ui.notify(
          "Kept the current draft instead of restoring the last prompt",
          "info",
        );
        return;
      }

      const userMessageId = findLatestUserMessageId(
        ctx.sessionManager.getBranch(),
      );
      if (!userMessageId) {
        ctx.ui.notify("No user message is available to edit", "info");
        return;
      }

      await ctx.navigateTree(userMessageId, { summarize: false });
    },
  });

  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;

    previousEditorFactory = ctx.ui.getEditorComponent();
    installedEditorFactory = (tui, theme, keybindings) => {
      const editor =
        previousEditorFactory?.(tui, theme, keybindings) ??
        new CustomEditor(tui, theme, keybindings);
      const handleInput = editor.handleInput.bind(editor);
      const gesture = new EditLastPromptGesture();

      editor.handleInput = (data: string): void => {
        if (!matchesKey(data, "escape")) {
          gesture.reset();
          handleInput(data);
          return;
        }

        const action = gesture.handleEscape(
          Date.now(),
          ctx.isIdle(),
          !editor.getText().trim(),
        );
        if (action === "pass-through") {
          handleInput(data);
          return;
        }

        pi.sendUserMessage(`/${EDIT_LAST_PROMPT_COMMAND}`, {
          deliverAs: "steer",
          expandPromptTemplates: true,
        });
      };

      return editor;
    };

    ctx.ui.setEditorComponent(installedEditorFactory);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    if (ctx.mode !== "tui" || !installedEditorFactory) return;
    if (ctx.ui.getEditorComponent() !== installedEditorFactory) return;

    ctx.ui.setEditorComponent(previousEditorFactory);
    installedEditorFactory = undefined;
    previousEditorFactory = undefined;
  });
}
