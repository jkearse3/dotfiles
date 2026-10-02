// The hint line text, or null until the session has measured itself.
export type StatuslineLine = string | null;

declare module "claude-code" {
  interface PluginState {
    statusline: { line: StatuslineLine };
  }
}
