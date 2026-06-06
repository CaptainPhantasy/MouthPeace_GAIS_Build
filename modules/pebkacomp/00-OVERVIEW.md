# PEBKACOMP — Research Overview

**Date:** 2026-06-05
**Author:** Main agent (audit cycle)
**Repo under audit:** PEBKAC repo
**Harness extension source under audit:** `packages/coding-agent/src/extensibility/extensions/`

## Purpose

Inspect the current PEBKAC defense extension, catalog every enforcement point
that depends on a social contract (prompt injection + post-hoc output rewrite
that the LLM can ignore), and propose a sister harness extension — **PEBKACOMP** —
that uses the harness's existing mechanical hook surface (`tool_call`, `tool_result`,
`before_provider_request`, `before_agent_start`, `agent_start`, `agent_end`,
`session_before_compact`, `input`, `user_bash`, `user_python`) to do the
enforcement *for real*.

## Hard rule

If a behavior cannot be expressed as one of:

- `block: true` on a `tool_call` event (`runner.ts:521-554`)
- content/details/isError rewrite on a `tool_result` event (`runner.ts:473-519`)
- payload replacement on `before_provider_request` (`runner.ts:728-760`)
- systemPrompt or message[] on `before_agent_start` (`runner.ts:762-817`)
- messages[] rewrite on `context` (`runner.ts:677-726`)
- cancel on `session_before_compact` (`runner.ts:435-471`)
- text/handled on `input` (`runner.ts:645-675`)
- block on `user_bash` / `user_python` (`runner.ts:556-594`)
- notify via `ctx.ui` from any event (`types.ts:67-195`)

…then it is **not in PEBKACOMP**. The behavior is either out of scope or stays
in PEBKAC's post-hoc text-rewrite layer (with a candid note that it is social
contract, not enforcement).

No hypotheticals. No "we hope it works." If the harness runner doesn't dispatch the
event, the feature does not ship.

## Docs in this folder

| # | File | Purpose |
|---|------|---------|
| 00 | `00-OVERVIEW.md` (this file) | Goal, hard rule, doc index |
| 01 | `01-PEBKAC-SOCIAL-CONTRACT-CATALOG.md` | Every social-contract spot in PEBKAC, file:line, current mechanism, why it is not mechanical |
| 02 | `02-HARNESS-HOOK-SURFACE.md` | Verified harness hook events, runner dispatch code, result types — what can mechanically block/rewrite |
| 03 | `03-PEBKACOMP-MAPPING.md` | Each social-contract spot → harness hook class → handler code shape |
| 04 | `04-PEBKACOMP-DESIGN.md` | Module layout, command set, shared store, PEBKAC coordination |
| 05 | `05-BUILD-ORDER.md` | Phased build order, per-phase tests, exit criteria |
| 06 | `06-PROPOSAL-PEBKACOMP.md` | The proposal itself: copy-pasteable into PR description, with the mapping table and the "what stays social contract" list |
| 07 | `07-EVIDENCE-LEDGER.md` | Per-item evidence ledger, verification receipts, completeness matrix |

## Source files cited

PEBKAC:

- `pebkac/.mouthpeace/extensions/pebkac-defense.js` (1835 lines, single bundled extension)
- `pebkac/bin/pebkac.js` (CLI)
- `pebkac/SSOT/pebkac_SSOT.md`
- `pebkac/CHANGELOG.md`
- `pebkac/README.md`
- `pebkac/package.json`
- `pebkac/test/smoke.test.js` (existing extension registration test)

Harness (verified from source):

- `packages/coding-agent/src/extensibility/extensions/types.ts` (event union types)
- `packages/coding-agent/src/extensibility/extensions/runner.ts` (event dispatch)
- `packages/coding-agent/src/extensibility/extensions/loader.ts` (extension loading)
- `packages/coding-agent/src/extensibility/extensions/index.ts` (barrel)
