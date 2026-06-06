# Blueprint: Global Install for Verifier Agent (REVISED)

**Created:** 2026-05-04
**Revised:** 2026-05-04 (post-adversarial review)
**Objective:** Convert the verifier from a per-project clone-and-run setup to a globally installed harness extension that works in any directory with zero per-project files.
**Mode:** Direct (no git remote, anonymous fork)

> **Revision note:** Original plan proposed compiling `.ts` → `.js`. Adversarial review (oracle) found this contradicts the agent harness extension system — the harness loads `.ts` natively and all installed packages ship raw `.ts`. The packaging strategy has been redesigned as a proper harness package using `"pi": { "extensions": [...] }` in `package.json`.

---

## Current State: Per-Project Coupling Points

| Coupling                       | Location                                                                          | Why it's local                                                                        |
| ------------------------------ | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Extension loading              | `justfile: pi -e ./apps/verifier/verifiable.ts -e ./apps/verifier/cross-agent.ts` | Explicit `-e` paths relative to repo root                                             |
| `runtimeRoot` / `verifierHome` | `verifiable.ts:356-357`                                                           | `path.resolve(path.dirname(here), "..", "..")` — assumes repo layout `apps/verifier/` |
| Verifier child entry           | `launcher.ts:126`                                                                 | `path.join(opts.runtimeRoot, "apps", "verifier", "verifier.ts")` — hardcoded subpath  |
| Persona files                  | `verifiable.ts:370`                                                               | `ctx.cwd + ".mouthpeace/verifier/agents/verifier.md"` — project-local only                    |
| Prompt templates               | `verifier.ts` (handleBuilderEvent)                                                | `ctx.cwd + ".mouthpeace/verifier/prompts/verify_on_stop.md"` — project-local only             |
| Socket breadcrumb              | `socket-path.ts`                                                                  | `<cwd>/.mouthpeace/state/verifier-<sessionId>.sock.ref` — per-project (correct, keep)         |
| `node_modules/`                | `apps/verifier/`                                                                  | Dependencies inside cloned repo                                                       |
| Install command                | `.claude/commands/install.md`                                                     | Per-project workflow                                                                  |

---

## Target State: Harness Package

```
~/.mouthpeace/verifier/                              # Global verifier package
├── package.json                             # harness package manifest with "pi" field
├── apps/verifier/                           # Source tree preserved as-is
│   ├── verifiable.ts                        # Builder-side extension
│   ├── verifier.ts                          # Verifier-side extension
│   ├── cross-agent.ts                       # Cross-agent IPC
│   ├── verifiable-footer.ts                 # Builder footer status bar
│   └── _shared/
│       ├── env.ts
│       ├── frontmatter.ts
│       ├── ipc.ts
│       ├── launcher.ts                      # Modified: uses verifierHome
│       └── socket-path.ts
├── agents/
│   └── verifier.md                          # Default persona
├── prompts/
│   ├── verify_on_stop.md                    # Default prompt template
│   └── builder_error.md                     # Error prompt
└── node_modules/
    └── typebox/                             # Runtime dependency (only non-peer dep)
```

Key differences from original plan:

- **No compilation.** The harness loads `.ts` natively. All installed harness packages ship raw `.ts`.
- **`package.json` has `"pi"` field.** This is how the harness discovers extensions — not manual `-e` flags.
- **Source tree preserved.** No restructuring — the `apps/verifier/_shared/` imports stay intact.
- **`@mariozechner/*` resolved through the harness's peer mechanism.** No need to bundle harness packages separately.

---

## Step Dependency Graph

```
Step 1 (package.json "pi" field)
  ↓
Step 2 (runtimeRoot → verifierHome) ──→ Step 3 (persona/prompt resolver)
  ↓                                       ↓
Step 4 (install script) ←────────────────┘
  ↓
Step 5 (justfile + CLI entry) ──→ Step 6 (install.md + README)
  ↓
Step 7 (E2E verification)
```

Steps 2 and 3 are serial (both touch `verifiable.ts`). Steps 5 and 6 are parallel after Step 4.

---

## Step 1: Create Harness Package Manifest

**Why:** The harness discovers extensions via the `"pi"` field in `package.json`. Currently `apps/verifier/package.json` has no `"pi"` field — it's a plain Node package. Adding it makes `pi install ./apps/verifier/` work from any directory.

**Model tier:** default

**Tasks:**

1. Add `"pi"` field to `apps/verifier/package.json`:
   ```json
   "pi": {
     "extensions": [
       "./apps/verifier/verifiable.ts",
       "./apps/verifier/cross-agent.ts"
     ]
   }
   ```
   Note: paths are relative to the package root (the directory containing `package.json`). But the source tree starts one level deeper at `apps/verifier/`. The `package.json` must live at the root that contains `apps/`.
2. Move `apps/verifier/package.json` to the project root as `package.json` (or create a wrapper) so the `"pi": { "extensions": [...] }` paths resolve correctly against the directory containing `apps/verifier/`.
3. Alternatively, restructure: keep `package.json` in `apps/verifier/` and adjust extension paths to `"./verifiable.ts", "./cross-agent.ts"` (relative to `apps/verifier/`).
4. Add `"typebox"` as a regular `dependency` (it's the only non-peer runtime dep — `@mariozechner/*` are peers resolved through the harness).

**Exit criteria:** `pi install ./apps/verifier/` succeeds and `pi list` shows the verifier package.

**Rollback:** Remove `"pi"` field from `package.json`. Run `pi remove ./apps/verifier/`.

**Verification commands:**

```bash
pi install ./apps/verifier/
pi list | grep verifier
```

---

## Step 2: Decouple `runtimeRoot` — Make Extension Path-Aware

**Why:** `verifiable.ts:356-357` resolves `runtimeRoot` by walking up 2 levels from `import.meta.url` (`apps/verifier/verifiable.ts` → repo root). `launcher.ts:126` joins `runtimeRoot + "apps/verifier/verifier.ts"`. After global install at `~/.mouthpeace/verifier/`, the walk-up from `~/.mouthpeace/verifier/apps/verifier/verifiable.ts` goes 2 levels to `~/.mouthpeace/verifier/` — which is correct. BUT the hardcoded `"apps/verifier/verifier.ts"` subpath in launcher.ts will break if the package structure changes.

**Model tier:** strongest

**Tasks:**

1. In `verifiable.ts`, rename `runtimeRoot` to `verifierHome` and add env-var override:
   ```typescript
   const here = fileURLToPath(import.meta.url);
   const verifierHome =
     process.env.VERIFIER_HOME ?? path.resolve(path.dirname(here), "..", "..");
   ```
2. In `launcher.ts`:
   - Rename `runtimeRoot` → `verifierHome` in `SpawnOpts` interface.
   - Replace `path.join(opts.runtimeRoot, "apps", "verifier", "verifier.ts")` with a `resolveVerifierEntry()` function:
     ```typescript
     function resolveVerifierEntry(verifierHome: string): string {
       // Check for verifier.ts relative to verifierHome
       const candidate = path.join(
         verifierHome,
         "apps",
         "verifier",
         "verifier.ts",
       );
       // Could also check verifierHome directly if restructured later
       return candidate;
     }
     ```
3. This preserves the current repo-layout behavior AND works when installed at `~/.mouthpeace/verifier/` (since the source tree structure is identical).

**Exit criteria:** `apps/verifier/node_modules/.cache` deleted, `npx tsc --noEmit` passes, `just v` still works from repo.

**Rollback:** Revert the 2 files.

**Verification commands:**

```bash
cd apps/verifier && npx tsc --noEmit
just v  # smoke test — still works from source tree
```

---

## Step 3: Make Persona and Prompt Resolution CWD-Aware

**Why:** `verifiable.ts:370` resolves persona at `ctx.cwd + ".mouthpeace/verifier/agents/verifier.md"`. `verifier.ts` resolves prompts at `ctx.cwd + ".mouthpeace/verifier/prompts/verify_on_stop.md"`. In a global install, these defaults live at `~/.mouthpeace/verifier/agents/` — not under the project cwd. Resolution must check local (project override) first, then global fallback.

**Model tier:** strongest

**Tasks:**

1. Create `apps/verifier/_shared/resolver.ts`:

   ```typescript
   export function resolvePersona(
     agentName: string,
     cwd: string,
     verifierHome: string,
   ): string {
     // Project-local override wins
     const local = path.resolve(
       cwd,
       ".pi",
       "verifier",
       "agents",
       `${agentName}.md`,
     );
     if (existsSync(local)) return local;
     // Global fallback
     const global = path.resolve(verifierHome, "agents", `${agentName}.md`);
     if (existsSync(global)) return global;
     throw new Error(
       `Persona "${agentName}" not found at:\n  local:  ${local}\n  global: ${global}`,
     );
   }

   export function resolvePromptTemplate(
     name: string,
     cwd: string,
     verifierHome: string,
   ): string {
     const local = path.resolve(cwd, ".pi", "verifier", "prompts", name);
     if (existsSync(local)) return local;
     const global = path.resolve(verifierHome, "prompts", name);
     if (existsSync(global)) return global;
     throw new Error(
       `Prompt template "${name}" not found at:\n  local:  ${local}\n  global: ${global}`,
     );
   }
   ```

2. Update `verifiable.ts` — replace `path.resolve(ctx.cwd, ".mouthpeace/verifier/agents", ...)` with `resolvePersona(agentName, ctx.cwd, verifierHome)`.
3. Update `verifier.ts` — replace `path.join(ctx.cwd, ".pi", "verifier", "prompts", "verify_on_stop.md")` with `resolvePromptTemplate("verify_on_stop.md", ctx.cwd, verifierHome)`.
4. Pass `verifierHome` through to `verifier.ts` via the wrapper script's env or a new CLI flag. The launcher already writes a wrapper — add `export VERIFIER_HOME=<path>` to it, or pass it as a `--verifier-home` flag.

**Exit criteria:** Persona resolution works with global-only files. Local `.mouthpeace/verifier/agents/` overrides global. `npx tsc --noEmit` passes.

**Rollback:** Revert the 4 files. Delete `_shared/resolver.ts`.

**Verification commands:**

```bash
cd apps/verifier && npx tsc --noEmit
```

---

## Step 4: Global Install Script

**Why:** Single command to install the verifier globally.

**Model tier:** default

**Tasks:**

1. Create `scripts/install-global.sh`:

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail

   VERIFIER_HOME="${VERIFIER_HOME:-$HOME/.mouthpeace/verifier}"
   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

   echo "Installing Verifier Agent to $VERIFIER_HOME"

   # Prerequisites
   for cmd in node pi tmux; do
     if ! command -v "$cmd" &>/dev/null; then
       echo "ERROR: $cmd not found. Install it first." >&2; exit 1
     fi
   done

   # Create target directory
   mkdir -p "$VERIFIER_HOME"

   # Copy source tree (preserving structure)
   cp -R "$SOURCE_ROOT/apps" "$VERIFIER_HOME/"
   cp -R "$SOURCE_ROOT/.mouthpeace/verifier/agents" "$VERIFIER_HOME/"
   cp -R "$SOURCE_ROOT/.mouthpeace/verifier/prompts" "$VERIFIER_HOME/"

   # Create package.json for the harness
   cat > "$VERIFIER_HOME/package.json" << 'PKGJSON'
   {
     "name": "the-verifier-agent",
     "version": "0.1.0",
     "private": true,
     "type": "module",
     "pi": {
       "extensions": [
         "./apps/verifier/verifiable.ts",
         "./apps/verifier/cross-agent.ts"
       ]
     },
     "dependencies": {
       "typebox": "^1.1.34",
       "@mariozechner/pi-coding-agent": "^0.70.5",
       "@mariozechner/pi-tui": "^0.70.5",
       "typescript": "^5.6.0"
     }
   }
   PKGJSON

   # Install dependencies
   cd "$VERIFIER_HOME" && npm install

   # Register with the harness
   pi install "$VERIFIER_HOME"

   echo ""
   echo "✓ Verifier Agent installed globally."
   echo "  Location: $VERIFIER_HOME"
   echo "  Run 'pi --verifiable' in any directory to use."
   ```

2. `chmod +x scripts/install-global.sh`
3. Add `just install-global` recipe to justfile.

**Exit criteria:** `./scripts/install-global.sh` succeeds. `pi list | grep verifier` shows the package. `ls ~/.mouthpeace/verifier/apps/verifier/*.ts` shows source files.

**Rollback:** `pi remove ~/.mouthpeace/verifier/` and `rm -rf ~/.mouthpeace/verifier/`.

**Verification commands:**

```bash
./scripts/install-global.sh
pi list | grep verifier
ls ~/.mouthpeace/verifier/apps/verifier/_shared/*.ts
```

---

## Step 5: Justfile + Global CLI Entry Point

**Why:** After global install, `pi --verifiable` should work in any directory (the extension auto-loads and registers the flag). No `-e` flags needed. The justfile becomes optional.

**Model tier:** default

**Tasks:**

1. Add `v-global` recipe:
   ```just
   # Launch builder with globally installed verifier
   v-global:
       pi --verifiable
   ```
2. Keep existing `v` recipe as `v-local` for source-tree development.
3. Test: `cd /tmp && mkdir test-dir && cd test-dir && pi --verifiable` should spawn builder + verifier.
4. The `--verifier-agent <name>` flag already works (registered in `verifiable.ts`). Document it.

**Exit criteria:** `pi --verifiable` works from any directory with no local files.

**Rollback:** Revert justfile changes.

**Verification commands:**

```bash
cd /tmp && mkdir -p test-verifier && cd test-verifier && pi --verifiable
# builder starts, verifier spawns in tmux, no .mouthpeace/ directory needed
```

---

## Step 6: Rewrite Install Command and README

**Why:** Current docs describe per-project setup only.

**Model tier:** default

**Tasks:**

1. Update `.claude/commands/install.md` — add global install path:
   - "Global Install (recommended): `./scripts/install-global.sh`"
   - Keep per-project as "Development Install"
2. Update `README.md`:
   - Add "Global Install" section with one-command install.
   - Update "Quick Start" to show `pi --verifiable` as primary.
   - Add "Project-Local Customization" section.
   - Add `--verifier-agent` flag documentation.
3. Both can be done in parallel.

**Exit criteria:** README and install.md both describe global install as the primary path.

**Rollback:** Revert both files.

**Verification commands:**

```bash
grep -c "Global Install\|install-global" README.md .claude/commands/install.md
```

---

## Step 7: End-to-End Verification

**Why:** Full integration test.

**Model tier:** strongest

**Tasks:**

1. Clean slate: `rm -rf ~/.mouthpeace/verifier/ && pi remove the-verifier-agent 2>/dev/null || true`.
2. Run `./scripts/install-global.sh`.
3. Verify `pi list | grep verifier`.
4. `cd /tmp/test-verifier && pi --verifiable`.
5. Send a simple prompt. Verify verifier observes and reports.
6. Test project-local override: create `.mouthpeace/verifier/agents/custom.md`. Run `pi --verifiable --verifier-agent custom`.
7. Clean up.

**Exit criteria:** Steps 2-6 all pass. No per-project files required.

**Rollback:** Full cleanup.

**Verification commands:**

```bash
pi list | grep verifier
tmux ls 2>/dev/null | grep verifier
```

---

## Anti-Patterns Checked

| Anti-Pattern                    | Status        | Notes                                                                                                     |
| ------------------------------- | ------------- | --------------------------------------------------------------------------------------------------------- |
| Compile `.ts` → `.js`           | ❌ Eliminated | The harness loads `.ts` natively — shipping raw source is the ecosystem convention                       |
| Wrong `pi install` invocation   | ❌ Eliminated | Using `pi install <dir>` with `package.json` + `"pi"` field                                               |
| Missing co-located files        | ❌ Eliminated | Source tree preserved intact — all `_shared/` files remain in place                                       |
| Runtime npm deps unresolvable   | ❌ Eliminated | `@mariozechner/*` are peers resolved through the harness; `typebox` is a local dep                       |
| Breaking existing workflow      | ❌ Avoided    | `just v` keeps working; global install is additive                                                        |
| `runtimeRoot` hardcoded walk-up | ⚠️ Verified   | 2-level walk-up from `apps/verifier/verifiable.ts` resolves to `~/.mouthpeace/verifier/` when installed — correct |

---

## Parallelism

```
Step 1 → Step 2 → Step 3 → Step 4
                              → Step 5 ─┐
                              → Step 6 ─┤ (parallel)
                                         ┘
                              → Step 7
```

---

## Estimated Effort

| Step      | Scope                                                 | Time           |
| --------- | ----------------------------------------------------- | -------------- |
| 1         | Small (package.json edit + test)                      | 15 min         |
| 2         | Medium (path resolution refactor in 2 files)          | 30 min         |
| 3         | Medium (resolver module + 2 call sites + env passing) | 30 min         |
| 4         | Small (install script + justfile recipe)              | 20 min         |
| 5         | Small (justfile + smoke test)                         | 15 min         |
| 6         | Small (README + install.md rewrite)                   | 20 min         |
| 7         | Medium (full E2E test)                                | 30 min         |
| **Total** |                                                       | **~2.5 hours** |
