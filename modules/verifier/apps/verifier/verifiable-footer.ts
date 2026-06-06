/**
 * Builder-side UI: input-bar border embedding.
 *
 * `BuilderInputEditor` (CustomEditor subclass) embeds context info directly
 * into the input box's border lines via `fitBorder`:
 *
 *   ──────────────────────────────────── ◌ verifier idle ──
 *     [cursor — your normal input]
 *   ── claude-sonnet-4-6 ────────────────────────── 12% ───
 *
 *   Top-right border:    verifier connection status
 *   Bottom-left border:  active model id
 *   Bottom-right border: ctx-window utilization
 *
 * Pattern lifted from the agent harness documentation.
 *
 * The editor reads shared mutable state passed in by the caller (via getter
 * functions), so it re-renders correctly whenever `verifiable.ts` mutates
 * phase/sid. Pi calls `render()` on every TUI tick — no explicit nudge.
 *
 * History note: this file once also exported `installBuilderFooter` which
 * installed a bottom-of-screen custom footer with the same info. Removed
 * because it duplicated what the input-bar borders already show.
 */

import {
  CustomEditor,
  type ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";

// ─── Shared types ────────────────────────────────────────────────────────────

export type ConnectionPhase =
  | "idle"
  | "disconnected"
  | "spawning"
  | "connected"
  | "error";

export interface BuilderUIDeps {
  /** Current verifier-connection phase. Read on every render. */
  getPhase: () => ConnectionPhase;
  /** Builder session id (canonical, full uuid). Read on every render. */
  getSessionId: () => string;
}

/**
 * Safely read a property from a possibly-stale ctx. Pi marks captured ctx
 * stale across session-replacement boundaries (an internal `newSession` etc.
 * during async work invalidates the ctx we captured at session_start). Render
 * factories run when pi decides to render — wrap each access and fall back.
 */
function safeCtx<T>(fn: () => T, fallback: T): T {
  try {
    return fn();
  } catch {
    return fallback;
  }
}

// ─── Input-bar border embedding (CustomEditor subclass) ──────────────────────

/**
 * `fitBorder` — build a fresh border line with text embedded, sized to width.
 * Lifted verbatim from the agent harness documentation. Don't
 * splice into `super.render()`'s ANSI dashes; build a new line instead.
 */
function fitBorder(
  left: string,
  right: string,
  width: number,
  border: (text: string) => string,
  fill: (text: string) => string = border,
): string {
  if (width <= 0) return "";
  if (width === 1) return border("─");
  let leftText = left;
  let rightText = right;
  const fixedWidth = 2;
  const minimumGap = 3;
  while (
    fixedWidth + visibleWidth(leftText) + visibleWidth(rightText) + minimumGap > width &&
    visibleWidth(rightText) > 0
  ) {
    rightText = truncateToWidth(rightText, Math.max(0, visibleWidth(rightText) - 1), "");
  }
  while (
    fixedWidth + visibleWidth(leftText) + visibleWidth(rightText) + minimumGap > width &&
    visibleWidth(leftText) > 0
  ) {
    leftText = truncateToWidth(leftText, Math.max(0, visibleWidth(leftText) - 1), "");
  }
  const gapWidth = Math.max(
    0,
    width - fixedWidth - visibleWidth(leftText) - visibleWidth(rightText),
  );
  return `${border("─")}${leftText}${fill("─".repeat(gapWidth))}${rightText}${border("─")}`;
}

/**
 * Builder's input-box editor with status text embedded in the border lines.
 *
 *   Top border:    [empty left]  ──  ◌ verifier <phase>      [right]
 *   (input box)
 *   Bottom border: <model>       ──  <ctx-pct>%               [right]
 *
 * The verifier-connection state lives top-right so the operator's eye lands
 * on it as they're about to type — they see at a glance whether their next
 * prompt will be observed by a live verifier. Model + ctx live on the bottom
 * border, mirroring the position of the harness's default footer info.
 *
 * Width-safe via `fitBorder`. Pi crashes on width overflow; this helper
 * truncates right text first, then left, down to nothing.
 */
export class BuilderInputEditor extends CustomEditor {
  constructor(
    tui: ConstructorParameters<typeof CustomEditor>[0],
    theme: ConstructorParameters<typeof CustomEditor>[1],
    keybindings: ConstructorParameters<typeof CustomEditor>[2],
    private deps: BuilderUIDeps,
    private ctx: ExtensionContext,
  ) {
    super(tui, theme, keybindings, {});
  }

  override render(width: number): string[] {
    const lines = super.render(width);
    if (lines.length < 2) return lines;

    // The captured ctx (from constructor / session_start) can be stale by the
    // time pi calls render(). Wrap every ctx access in safeCtx and fall back
    // to a sane default so the editor always renders. If `theme` access fails,
    // we just bail to super's lines.
    const theme = safeCtx(() => this.ctx.ui.theme, null);
    if (!theme) return lines;
    const bc = (s: string) => this.borderColor(s);

    // ─── Top border: verifier connection status (top-right) ──────────────
    const phase = this.deps.getPhase();
    const glyph =
      phase === "connected"
        ? "●"
        : phase === "spawning"
          ? "◌"
          : phase === "error"
            ? "⚠"
            : phase === "disconnected"
              ? "✗"
              : "◌"; // idle
    const phaseFg =
      phase === "connected"
        ? "success"
        : phase === "error" || phase === "disconnected"
          ? "error"
          : "muted";
    const topRight = theme.fg(phaseFg, ` ${glyph} verifier ${phase} `);
    lines[0] = fitBorder("", topRight, width, bc);

    // ─── Bottom border: model (left) + ctx % (right) ─────────────────────
    const model = safeCtx(() => this.ctx.model?.id ?? "no-model", "no-model");
    const usage = safeCtx(() => this.ctx.getContextUsage?.(), undefined);
    const pct = usage && usage.percent !== null ? usage.percent : 0;
    const bottomLeft = theme.fg("dim", ` ${model} `);
    const bottomRight = theme.fg("dim", ` ${Math.round(pct)}% `);
    lines[lines.length - 1] = fitBorder(bottomLeft, bottomRight, width, bc);

    return lines;
  }
}
