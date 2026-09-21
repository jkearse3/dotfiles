import { sanitizeDisplayText } from "./core.ts";
import type {
  UsageDataProvenance,
  UsageProviderResult,
  UsageReport,
  UsageRow,
} from "./types.ts";

const VALUE_COLUMN = 24;

/** Renders all provider results without merging unlike quota or billing semantics. */
export function formatUsageDashboard(
  results: readonly UsageProviderResult[],
): string {
  if (results.length === 0) {
    return "No supported subscription has configured authentication.";
  }

  return results
    .map((result) =>
      result.status === "ready"
        ? formatUsageReport(result.report, result.provenance)
        : [
            sanitizeDisplayText(result.providerName, 80),
            "",
            `Query failed: ${sanitizeDisplayText(result.message)}`,
          ].join("\n"),
    )
    .join("\n\n");
}

/** Renders one provider report while leaving row semantics provider-owned. */
export function formatUsageReport(
  report: UsageReport,
  provenance?: UsageDataProvenance,
): string {
  const lines = [
    sanitizeDisplayText(report.providerName, 80),
    sanitizeDisplayText(report.semantics, 120),
  ];

  for (const section of report.sections) {
    if (section.title) lines.push("", sanitizeDisplayText(section.title, 120));
    for (const row of section.rows) lines.push(formatUsageRow(row));
  }

  for (const note of report.notes ?? []) {
    lines.push("", sanitizeDisplayText(note));
  }
  lines.push("");
  if (provenance) lines.push(formatProvenance(provenance));
  lines.push(`Captured ${formatCapturedAt(report.capturedAt)}`);
  return lines.join("\n");
}

function formatUsageRow(row: UsageRow): string {
  const label = `${sanitizeDisplayText(row.label, 100)}:`;
  const value = sanitizeDisplayText(row.value, 160);
  const details = [
    row.detail ? sanitizeDisplayText(row.detail, 160) : undefined,
    row.resetsAt !== undefined
      ? `resets ${formatResetAt(row.resetsAt)}`
      : undefined,
  ].filter((item): item is string => Boolean(item));
  const suffix = details.length > 0 ? ` · ${details.join(" · ")}` : "";
  return `${label.padEnd(VALUE_COLUMN)}${value}${suffix}`;
}

function formatResetAt(epochSeconds: number): string {
  const date = new Date(epochSeconds * 1_000);
  if (Number.isNaN(date.getTime())) return "at an unknown time";
  return date.toLocaleString();
}

function formatProvenance(provenance: UsageDataProvenance): string {
  const source = provenance.source === "cache" ? "Cache" : "Provider response";
  return `Data: ${source} · ${formatAge(provenance.ageMs)}`;
}

function formatAge(ageMs: number): string {
  const boundedAgeMs = Number.isFinite(ageMs) ? Math.max(0, ageMs) : 0;
  const totalMinutes = Math.floor(boundedAgeMs / 60_000);
  if (totalMinutes < 1) return "<1m old";
  if (totalMinutes < 60) return `${totalMinutes}m old`;

  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${hours}h${minutes > 0 ? ` ${minutes}m` : ""} old`;
}

function formatCapturedAt(timestamp: number): string {
  const date = new Date(timestamp);
  if (Number.isNaN(date.getTime())) return "at an unknown time";
  return date.toLocaleTimeString();
}
