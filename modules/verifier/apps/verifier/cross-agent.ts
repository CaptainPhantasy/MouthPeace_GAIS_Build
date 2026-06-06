/**
 * Cross-Agent — Load commands, skills, and agents from other AI coding agents
 *
 * Scans .claude/, .gemini/, .codex/ directories (project + global) for:
 *   commands/*.md  → registered as /name
 *   skills/        → listed as /skill:name (discovery only)
 *   agents/*.md    → listed as @name (discovery only)
 *
 * Adapted from an upstream cross-agent extension with two changes for use in the verifier project:
 *   1. The themeMap.ts dependency (synthwave palette defaults) is dropped —
 *      we only kept the parts that surface commands/skills to the builder.
 *   2. Loaded ONLY into the builder agent (via justfile `-e`); the verifier
 *      child intentionally does NOT load this — the verifier is read-only
 *      by architecture and must not be able to invoke arbitrary slash
 *      commands or skills from the user's .claude/ directory.
 *
 * Usage: pi -e ./apps/verifier/cross-agent.ts (already wired into justfile recipes)
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { readdirSync, readFileSync, existsSync, statSync } from "node:fs";
import { join, basename } from "node:path";
import { homedir } from "node:os";

interface Discovered {
  name: string;
  description: string;
  content: string;
}

interface SourceGroup {
  source: string;
  commands: Discovered[];
  skills: Discovered[];
  agents: Discovered[];
}

function parseFrontmatter(raw: string): { description: string; body: string; fields: Record<string, string> } {
  const match = raw.match(/^---\s*\n([\s\S]*?)\n---\s*\n([\s\S]*)$/);
  if (!match) return { description: "", body: raw, fields: {} };

  const front = match[1] ?? "";
  const body = match[2] ?? "";
  const fields: Record<string, string> = {};
  for (const line of front.split("\n")) {
    const idx = line.indexOf(":");
    if (idx > 0) fields[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
  }
  return { description: fields.description || "", body, fields };
}

function expandArgs(template: string, args: string): string {
  const parts = args.split(/\s+/).filter(Boolean);
  let result = template;
  result = result.replace(/\$ARGUMENTS|\$@/g, args);
  for (let i = 0; i < parts.length; i++) {
    result = result.replaceAll(`$${i + 1}`, parts[i]!);
  }
  return result;
}

function scanCommands(dir: string): Discovered[] {
  if (!existsSync(dir)) return [];
  const items: Discovered[] = [];
  try {
    for (const file of readdirSync(dir)) {
      if (!file.endsWith(".md")) continue;
      const raw = readFileSync(join(dir, file), "utf-8");
      const { description, body } = parseFrontmatter(raw);
      items.push({
        name: basename(file, ".md"),
        description: description || body.split("\n").find((l) => l.trim())?.trim() || "",
        content: body,
      });
    }
  } catch {
    // ignore
  }
  return items;
}

function scanSkills(dir: string): Discovered[] {
  if (!existsSync(dir)) return [];
  const items: Discovered[] = [];
  try {
    for (const entry of readdirSync(dir)) {
      const skillFile = join(dir, entry, "SKILL.md");
      const flatFile = join(dir, entry);
      if (existsSync(skillFile) && statSync(skillFile).isFile()) {
        const raw = readFileSync(skillFile, "utf-8");
        const { description, body } = parseFrontmatter(raw);
        items.push({
          name: entry,
          description: description || body.split("\n").find((l) => l.trim())?.trim() || "",
          content: raw,
        });
      } else if (entry.endsWith(".md") && statSync(flatFile).isFile()) {
        const raw = readFileSync(flatFile, "utf-8");
        const { description, body } = parseFrontmatter(raw);
        items.push({
          name: basename(entry, ".md"),
          description: description || body.split("\n").find((l) => l.trim())?.trim() || "",
          content: raw,
        });
      }
    }
  } catch {
    // ignore
  }
  return items;
}

function scanAgents(dir: string): Discovered[] {
  if (!existsSync(dir)) return [];
  const items: Discovered[] = [];
  try {
    for (const file of readdirSync(dir)) {
      if (!file.endsWith(".md")) continue;
      const raw = readFileSync(join(dir, file), "utf-8");
      const { fields } = parseFrontmatter(raw);
      items.push({
        name: fields.name || basename(file, ".md"),
        description: fields.description || "",
        content: raw,
      });
    }
  } catch {
    // ignore
  }
  return items;
}

export default function (pi: ExtensionAPI): void {
  // ── Scan + register at init time (top-level, synchronous) ────────────────
  //
  // registerCommand() must be called synchronously during extension load —
  // the same rule that applies to registerTool() and registerShortcut().
  // Calling it inside session_start lands too late and the commands are
  // silently dropped. Use process.cwd() here; the harness is always launched from
  // the project root so it is identical to ctx.cwd at runtime.
  //
  const home = homedir();
  const cwd = process.cwd();
  const providers = ["claude", "gemini", "codex"];
  const groups: SourceGroup[] = [];

  for (const p of providers) {
    for (const [dir, label] of [
      [join(cwd, `.${p}`), `.${p}`],
      [join(home, `.${p}`), `~/.${p}`],
    ] as const) {
      const commands = scanCommands(join(dir, "commands"));
      const skills = scanSkills(join(dir, "skills"));
      const agents = scanAgents(join(dir, "agents"));

      if (commands.length || skills.length || agents.length) {
        groups.push({ source: label, commands, skills, agents });
      }
    }
  }

  // Also scan .mouthpeace/agents/ for local agent definitions
  const localAgents = scanAgents(join(cwd, ".mouthpeace", "agents"));
  if (localAgents.length) {
    groups.push({ source: ".mouthpeace/agents", commands: [], skills: [], agents: localAgents });
  }

  // Register commands + skills once — never re-registered on /new
  const seenCmds = new Set<string>();
  for (const g of groups) {
    for (const cmd of g.commands) {
      if (seenCmds.has(cmd.name)) continue;
      seenCmds.add(cmd.name);
      pi.registerCommand(cmd.name, {
        description: `[${g.source}] ${cmd.description}`.slice(0, 120),
        handler: async (args) => {
          pi.sendUserMessage(expandArgs(cmd.content, args || ""));
        },
      });
    }
    for (const skill of g.skills) {
      const cmdName = `skill:${skill.name}`;
      if (seenCmds.has(cmdName)) continue;
      seenCmds.add(cmdName);
      pi.registerCommand(cmdName, {
        description: `[${g.source}] ${skill.description}`.slice(0, 120),
        handler: async (args) => {
          const task = args?.trim();
          pi.sendUserMessage(task ? `${skill.content}\n\nTask: ${task}` : skill.content);
        },
      });
    }
  }

  // Boot notification suppressed — the user explicitly asked to silence the
  // "loaded N commands / M skills" startup display. Registration above runs
  // synchronously at extension load, so commands/skills are still wired up;
  // we just don't surface the discovery banner.
}
