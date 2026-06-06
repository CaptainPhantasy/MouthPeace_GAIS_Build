# PROPOSAL: PEBKACOMP — Mechanical Hooks for PEBKAC

**Status:** Draft, ready for review
**Date:** 2026-06-05
**Repo:** `github.com/CaptainPhantasy/pebkacv2`
**Sister system name:** `pebkacomp`

## TL;DR

PEBKAC currently enforces 11 of its 14 defense layers through prompt
injection + post-hoc output rewrites. The model is told what to do via
system-prompt text and reminded after the fact when it deviates. This is
social contract, not enforcement.

**PEBKACOMP** is a sister harness extension that uses the harness's existing mechanical
hook surface (`tool_call`, `tool_result`, `before_provider_request`,
`before_agent_start`, `agent_start`, `agent_end`, `session_before_compact`,
`input`, `user_bash`, `user_python`) to do the same jobs with real
`block: true` returns, payload replacements, and content rewrites.

No new hook class is invented. No hypothetical behavior. Every PEBKACOMP
feature maps to a specific harness event whose runner code is verified in
`runner.ts`.

## Why

The PEBKAC extension's L1 contract compiler (`contract-compiler.ts:384-465`)
injects a multi-thousand-character system-prompt block telling the model
"you MUST NOT" and "MUST produce X." Compliance depends on the model
following the prompt. PEBKAC's L2 evidence enforcer
(`evidence-enforcer.ts:524-570`) detects ceremonial claims *after* the model
emits them, then *appends* a `[PEBKAC HARD BLOCK]` annotation. The model
has already spoken; the user has already seen the false claim.

The harness's `tool_call` runner (`runner.ts:521-554`) supports
`return {block: true, reason: "..."}` short-circuits. The first extension
to return that wins. This is the mechanical lever PEBKAC doesn't use.

PEBKACOMP uses that lever.

## Spots replaced

Full table in `03-PEBKACOMP-MAPPING.md`. Summary:

| SC-# | Spot | Was | PEBKACOMP |
|------|------|-----|-----------|
| SC-1 | Forbidden-behavior scan | post-hoc `tool_result` rewrite | `before_provider_request` outbound patch |
| SC-2 | Execution contract | system-prompt text wall | `tool_call` block + `tool_result` rewrite |
| SC-3 | Context reminder | fake user message | `before_provider_request` patch into real user message |
| SC-4 | FLARE planning phase | `tool_call` block (already mechanical) | keep, extended |
| SC-5 | Ceremonial completion | post-hoc annotation | `tool_call` block on next tool until evidence |
| SC-6 | Reality-gate grounding | post-hoc text append | `before_provider_request` MUST-VERIFY injection |
| SC-7 | Contradiction-guard | post-hoc string rewrite | **dropped** (no mechanical enforcement exists) |
| SC-8 | Circuit-breaker recovery | user-issued slash command | `before_agent_start` + `tool_call` block |
| SC-9 | Turn budget | reminder injection | `tool_call` block on exhaustion |
| SC-10 | FLARE-plan detection | regex sniff of message history | slash command + checkpoint store |
| SC-11 | Silent operation | prompt-section + post-hoc rewrite | `before_provider_request` outbound strip |
| SC-12 | Subagent handoff | manual copy-paste | `ctx.sessionManager.newSession(...)` |
| SC-13 | Subagent result | manual paste-parse | `agent_end` event subscription |
| SC-14 | Pipeline | string-state object | real sub-session invocations |

## Spot that does not ship

**SC-7 (contradiction-guard)** is dropped from PEBKACOMP. Pre-empting a
contradiction requires knowing what the model *would* say, which is a
model task, not a hook task. There is no harness event that fires "the model is
about to emit X." The post-hoc rewrite in PEBKAC stays with a candid note
that it is output sanitization, not enforcement.

## Architecture

PEBKAC and PEBKACOMP are siblings. Both are harness extensions. PEBKAC keeps the
prompt-layer narration (silent operation instructions, evidence-ledger
format guide, the [HARNESS REMINDER] prefix); PEBKACOMP owns the
mechanical enforcement.

```
~/.mouthpeace/extensions/
  pebkac-defense.js         (PEBKAC, existing — 1835 lines)
  pebkacomp-defense.js      (PEBKACOMP, new — ~600 lines)

.harness/
  config.yaml               (gains pebkacomp: {mode: "sister"})
  state/pebkacomp-state.json
  checkpoints/pebkacomp.json
```

PEBKACOMP registers before PEBKAC in the loader order so its `tool_call`
short-circuits win on collisions. If PEBKACOMP fails to load, PEBKAC
remains active and protects the session; PEBKACOMP is *additive*, not
*load-bearing*.

## Files to be added (Phase 0-7, in build order)

| Phase | File | Purpose |
|-------|------|---------|
| 0 | `~/.mouthpeace/extensions/pebkacomp-defense.js` (stub) | load-and-label smoke |
| 0 | `bin/pebkac.js` (modified) | install pebkacomp-defense.js next to pebkac-defense.js |
| 0 | `test/pebkacomp-smoke.test.js` | extension loads, sets label |
| 1 | port of `rate-limiter`, `repeat-detector`, `escalation`, `tool-allowlist`, `circuit-breaker`, `lifecycle`, `git-guard`, `secrets-guard`, `output-guard`, `evidence-dedup`, `forbidden-behaviors` (backstop) | already mechanical, just moved |
| 1 | `test/pebkacomp-git.test.js`, `pebkacomp-secrets.test.js`, `pebkacomp-rate-limit.test.js`, `pebkacomp-circuit-breaker.test.js` | moved tests |
| 2 | `outbound-patcher.ts` | `before_provider_request` handler (SC-1, SC-3, SC-6, SC-11) |
| 2 | `test/pebkacomp-outbound-strip.test.js`, `pebkacomp-high-risk-verify.test.js` | payload assertion tests |
| 3 | `prompt-augmentor.ts` | `before_agent_start` handler (SC-2, SC-8) |
| 3 | `test/pebkacomp-breaker-augment.test.js` | systemPrompt assertion test |
| 4 | `evidence-gate.ts` | `tool_call` block on ceremonial claim and budget exhaustion (SC-5, SC-9) |
| 4 | `test/pebkacomp-ceremony-block.test.js`, `pebkacomp-budget-block.test.js` | block assertion tests |
| 5 | `flare-gate.ts` | slash command + `tool_call` gate (SC-10) |
| 5 | `test/pebkacomp-flare-gate.test.js` | gate assertion test |
| 6 | `subagent-spawner.ts`, `pipeline-runner.ts` | sub-sessions via `ctx.sessionManager.newSession(...)` (SC-12, SC-13, SC-14) |
| 6 | `test/pebkacomp-spawn.test.js`, `pebkacomp-pipeline.test.js` | sub-session lifecycle tests |
| 7 | PEBKAC config integration (`.harness/config.yaml` `pebkacomp:` block, `pebkac-defense.js` `index.ts:1199-1272` reads `pebkacomp.mode`) | sister mode toggle |
| 7 | `test/pebkacomp-config.test.js` | mode-switch assertion test |

## Risks and open questions

1. **`SessionManager.spawnSubagent` may not exist** in the harness's current type.
   PEBKACOMP falls back to `ctx.sessionManager.newSession(...)` with a
   structured prompt. SC-12 and SC-14 work either way; only the API
   surface changes. Verification: a follow-up read of the harness's `SessionManager`
   type in `types.ts` and the `sessionManager/` source.

2. **Event-emission order in the harness's `emitToolCall`**: PEBKACOMP must register
   *before* PEBKAC to win short-circuits. The harness loader
   (`loader.ts:471-538`) processes configured paths in array order. PEBKAC
   init writes the extensions alphabetically; `pebkac-defense.js` sorts
   before `pebkacomp-defense.js` in C locale. PEBKACOMP needs explicit
   priority metadata, or PEBKAC init must write the array in the desired
   order. Verification: read `loader.ts:471-538` for the priority field,
   if any.

3. **Contract items** are not first-class in PEBKAC today. PEBKAC's
   `compileContract` (`contract-compiler.ts:327-364`) builds items from the
   task description, but there is no `pebkacomp-set-active-item` command.
   For Phase 4 (ceremony block), PEBKACOMP needs a way to know which item
   the LLM is currently working on. Either: (a) PEBKACOMP parses the
   task description itself at `before_agent_start`, or (b) the model
   explicitly calls `/pebkacomp-set-active-item <id>`. (a) is more
   automatic; (b) is more honest. **Recommend (b) with a slash command
   registered in Phase 5**.

4. **Detection vs enforcement symmetry**: PEBKAC's L2 layer detects
   ceremonial claims and high-risk claims. PEBKACOMP's mechanical ports
   need the *same* regex sets. PEBKACOMP imports the regex constants from
   PEBKAC's modules; do not duplicate them. Verification: PEBKACOMP
   imports `CEREMONIAL_PATTERNS` and `HIGH_RISK_PATTERNS` from
   `pebkac-defense.js`.

## What PEBKACOMP does NOT do

- Does not invent new harness hooks.
- Does not block on social-contract items (the items are enforced via
  tool_call blocks on the LLM's *next* tool, not on language).
- Does not maintain a parallel state store; reads and writes the same
  `.harness/state/` and `.harness/checkpoints/` directories as PEBKAC.
- Does not own the prompt-layer narration. PEBKAC keeps the
  "### HARNESS IDENTITY" / "### SILENT OPERATION" sections. PEBKACOMP
  just enforces the *behavior* they describe.

## Next step

Review this proposal. If approved, the build begins at Phase 0 (scaffold)
and proceeds through Phase 7 (config integration). Each phase ends with
`bun test` exit 0 and the phase's tests demonstrating the new mechanical
behavior. The audit ledger is in `07-EVIDENCE-LEDGER.md`.
