import {
  BorderedLoader,
  DynamicBorder,
  type ExtensionAPI,
  type ExtensionCommandContext,
} from "@earendil-works/pi-coding-agent";
import {
  Container,
  matchesKey,
  ScrollView,
  Text,
} from "@earendil-works/pi-tui";

import { UsageQueryCoordinator } from "./cache.ts";
import {
  handleUsageResultsAction,
  runUsageCommand,
  type UsageResultsAction,
} from "./command.ts";
import { errorMessage } from "./core.ts";
import { formatUsageDashboard } from "./format.ts";
import { createCodexUsageAdapter } from "./providers/codex.ts";
import { queryConfiguredUsage, validateUsageAdapters } from "./registry.ts";
import type { UsageProviderAdapter, UsageProviderResult } from "./types.ts";

export const USAGE_COMMAND = "usage";
const DEFAULT_ADAPTERS = [createCodexUsageAdapter()] as const;

/** Registers the dependency-free central usage dashboard and its provider adapters. */
export default function usageExtension(
  pi: ExtensionAPI,
  adapters: readonly UsageProviderAdapter[] = DEFAULT_ADAPTERS,
): void {
  validateUsageAdapters(adapters);
  const coordinator = new UsageQueryCoordinator();

  pi.registerCommand(USAGE_COMMAND, {
    description: "Show subscription usage from locally owned provider adapters",
    handler: async (argumentsText, context) => {
      if (argumentsText.trim()) {
        context.ui.notify(
          `/${USAGE_COMMAND} does not accept arguments.`,
          "warning",
        );
        return;
      }
      if (!context.hasUI) {
        throw new Error(`/${USAGE_COMMAND} requires TUI or RPC mode.`);
      }

      await runUsageCommand(
        (forceRefresh) =>
          loadUsageResults(context, adapters, coordinator, forceRefresh),
        (results) => showUsageResults(context, results),
      );
    },
  });
}

async function loadUsageResults(
  context: ExtensionCommandContext,
  adapters: readonly UsageProviderAdapter[],
  coordinator: UsageQueryCoordinator,
  forceRefresh: boolean,
): Promise<UsageProviderResult[] | undefined> {
  if (context.mode !== "tui") {
    const controller = new AbortController();
    return queryConfiguredUsage(
      adapters,
      {
        context,
        signal: controller.signal,
      },
      { coordinator, forceRefresh },
    );
  }

  return context.ui.custom<UsageProviderResult[] | undefined>(
    (tui, theme, _keybindings, done) => {
      const loader = new BorderedLoader(
        tui,
        theme,
        "Checking subscription usage…",
      );
      let settled = false;
      const finish = (result: UsageProviderResult[] | undefined) => {
        if (settled) return;
        settled = true;
        done(result);
      };
      loader.onAbort = () => finish(undefined);

      void queryConfiguredUsage(
        adapters,
        {
          context,
          signal: loader.signal,
        },
        { coordinator, forceRefresh },
      ).then(finish, (error) => {
        if (loader.signal.aborted) {
          finish(undefined);
          return;
        }
        context.ui.notify(
          `Could not load usage: ${errorMessage(error)}`,
          "error",
        );
        finish(undefined);
      });
      return loader;
    },
  );
}

async function showUsageResults(
  context: ExtensionCommandContext,
  results: readonly UsageProviderResult[],
): Promise<UsageResultsAction> {
  const content = formatUsageDashboard(results);
  if (context.mode !== "tui") {
    context.ui.notify(content, "info");
    return "close";
  }

  return context.ui.custom<UsageResultsAction>(
    (tui, theme, _keybindings, done) => {
      const container = new Container();
      const title = new Text("", 1, 0);
      const help = new Text("", 1, 0);
      const refreshTheme = () => {
        title.setText(theme.fg("accent", theme.bold("Subscription usage")));
        help.setText(
          theme.fg(
            "dim",
            "↑/↓/pgup/pgdn scroll · r refresh · enter/esc/q close",
          ),
        );
      };
      const scrollView = new ScrollView(new Text(content, 1, 1), {
        primary: true,
        overscroll: "contain",
        scrollbar: "auto",
        scrollbarTrackStyle: (text) => theme.fg("dim", text),
        scrollbarThumbStyle: (text) => theme.fg("accent", text),
      });
      refreshTheme();

      container.addChild(
        new DynamicBorder((text: string) => theme.fg("accent", text)),
      );
      container.addChild(title);
      container.addChild(scrollView);
      container.addChild(help);
      container.addChild(
        new DynamicBorder((text: string) => theme.fg("accent", text)),
      );

      return {
        render: (width: number) => container.render(width),
        invalidate: () => {
          refreshTheme();
          container.invalidate();
        },
        handleInput: (data: string) => {
          if (matchesKey(data, "up")) scrollView.scrollBy(-1);
          else if (matchesKey(data, "down")) scrollView.scrollBy(1);
          else if (matchesKey(data, "pageUp")) {
            scrollView.scrollBy(-Math.max(1, scrollView.viewportHeight - 1));
          } else if (matchesKey(data, "pageDown")) {
            scrollView.scrollBy(Math.max(1, scrollView.viewportHeight - 1));
          } else if (
            handleUsageResultsAction(
              data,
              matchesKey(data, "enter") ||
                matchesKey(data, "escape") ||
                data === "q",
              done,
            )
          ) {
            return;
          } else {
            return;
          }
          tui.requestRender();
        },
      };
    },
  );
}

export type {
  PreparedUsageQuery,
  UsageDataProvenance,
  UsageProviderAdapter,
  UsageProviderQueryContext,
  UsageProviderResult,
  UsageReport,
  UsageRow,
  UsageSection,
} from "./types.ts";
export { UsageQueryCoordinator } from "./cache.ts";
export { formatUsageDashboard, formatUsageReport } from "./format.ts";
export {
  createCodexUsageAdapter,
  normalizeCodexUsage,
} from "./providers/codex.ts";
