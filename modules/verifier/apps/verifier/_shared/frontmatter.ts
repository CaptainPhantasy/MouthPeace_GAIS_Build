/**
 * Verifier persona frontmatter parser + body templating.
 *
 * Wraps `parseFrontmatter` from `@earendil-works/pi-coding-agent`, layering
 * verifier-specific shape validation on top:
 *
 *   - Required scalar fields: name, description, tools, model, domain.
 *   - Optional: max_loops (number), verification_focus (string[]).
 *
 * Templating is deliberately the dumbest possible thing — global string
 * replace on `<UPPER_SNAKE>` placeholders. No Jinja, no Mustache, no
 * conditionals. The verifier persona body is markdown that the LLM reads;
 * we substitute spawn-time values (BUILDER_SESSION_ID, BUILDER_SESSION_FILE,
 * SOCKET_PATH, etc.) into angle-bracketed slots and pass the result to
 * the harness via `--system-prompt` as a full overwrite.
 */

import { parseFrontmatter } from "@earendil-works/pi-coding-agent";

// ─── Types ───────────────────────────────────────────────────────────────────

export interface VerifierFrontmatter {
  name: string;
  description: string;
  tools: string; // comma-separated, parsed downstream by the verifier extension
  model: string;
  domain: string;
  max_loops?: number;
  verification_focus?: string[];
}

export interface ParsedVerifierPersona {
  frontmatter: VerifierFrontmatter;
  body: string;
}

// ─── Parser ──────────────────────────────────────────────────────────────────

/**
 * Parse a `.mouthpeace/verifier/agents/<name>.md` persona file into typed
 * frontmatter + raw body. Throws with a clear, field-naming message on
 * any missing required field — these are user-authored files, so the
 * error needs to point a human at exactly what's wrong.
 *
 * Note: we do NOT validate `tools` content (e.g. "is `bash` actually a
 * known Pi tool name") here — that's the verifier extension's job at
 * spawn time, where it has access to the Pi runtime tool registry.
 */
export function parseVerifierPersona(content: string): ParsedVerifierPersona {
  const { frontmatter: raw, body } = parseFrontmatter<Record<string, unknown>>(content);

  // Required scalars.
  const name = requireString(raw, "name");
  const description = requireString(raw, "description");
  const tools = requireString(raw, "tools");
  const model = requireString(raw, "model");
  const domain = requireString(raw, "domain");

  // Optional fields.
  const max_loops = optionalNumber(raw, "max_loops");
  const verification_focus = optionalStringArray(raw, "verification_focus");

  const frontmatter: VerifierFrontmatter = {
    name,
    description,
    tools,
    model,
    domain,
    ...(max_loops !== undefined ? { max_loops } : {}),
    ...(verification_focus !== undefined ? { verification_focus } : {}),
  };

  return { frontmatter, body };
}

// ─── Templating ──────────────────────────────────────────────────────────────

/**
 * Replace `<UPPER_SNAKE_CASE>` placeholders in `body` with values from
 * `vars`. Pure string replacement, global, case-sensitive.
 *
 * Keys in `vars` should be the placeholder name without the angle
 * brackets (e.g. `BUILDER_SESSION_ID`, not `<BUILDER_SESSION_ID>`).
 *
 * Placeholders that don't appear in `vars` are left untouched. This is
 * intentional: the body is templated in two stages (system-prompt vars
 * at spawn, user-prompt vars per cycle); the first stage shouldn't fail
 * on slots the second stage will fill.
 */
export function templateBody(body: string, vars: Record<string, string>): string {
  let out = body;
  for (const key of Object.keys(vars)) {
    if (!/^[A-Z][A-Z0-9_]*$/.test(key)) {
      throw new Error(
        `templateBody: variable name "${key}" must be UPPER_SNAKE_CASE (matches /^[A-Z][A-Z0-9_]*$/).`,
      );
    }
    const pattern = new RegExp(`<${key}>`, "g");
    out = out.replace(pattern, vars[key]!);
  }
  return out;
}

// ─── Internal helpers ────────────────────────────────────────────────────────

function requireString(obj: Record<string, unknown>, fieldPath: string): string {
  const v = lookup(obj, fieldPath);
  if (typeof v !== "string" || v.length === 0) {
    throw new Error(
      `Verifier persona frontmatter: required field "${fieldPath}" is missing or not a non-empty string.`,
    );
  }
  return v;
}

function optionalNumber(obj: Record<string, unknown>, fieldPath: string): number | undefined {
  const v = lookup(obj, fieldPath);
  if (v === undefined || v === null) return undefined;
  if (typeof v !== "number" || !Number.isFinite(v)) {
    throw new Error(
      `Verifier persona frontmatter: optional field "${fieldPath}" must be a finite number if present. Got: ${JSON.stringify(v)}.`,
    );
  }
  return v;
}

function optionalStringArray(obj: Record<string, unknown>, fieldPath: string): string[] | undefined {
  const v = lookup(obj, fieldPath);
  if (v === undefined || v === null) return undefined;
  if (!Array.isArray(v) || !v.every((x) => typeof x === "string")) {
    throw new Error(
      `Verifier persona frontmatter: optional field "${fieldPath}" must be an array of strings if present.`,
    );
  }
  return v as string[];
}

/**
 * Tiny dotted-path lookup so we can address nested fields with the same
 * error-message machinery as top-level scalars. Only used by the `require*`
 * helpers, never user-facing.
 */
function lookup(obj: Record<string, unknown>, fieldPath: string): unknown {
  const parts = fieldPath.split(".");
  let cur: unknown = obj;
  for (const part of parts) {
    if (typeof cur !== "object" || cur === null) return undefined;
    cur = (cur as Record<string, unknown>)[part];
  }
  return cur;
}
