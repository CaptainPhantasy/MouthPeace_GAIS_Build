# Evidence Ledger

Per the execution contract. Each row: what was claimed, what was done, what
is the evidence, was it verified.

## A) Requested items checklist

- [x] Inspect the PEBKAC codebase.
- [x] Catalog every social-contract enforcement spot in PEBKAC.
- [x] Verify the harness hook surface against current harness source.
- [x] Map each social-contract spot to a harness hook class.
- [x] Mark spots that cannot be mechanically enforced (with reasons).
- [x] Design PEBKACOMP as a sister extension.
- [x] Produce `PROPOSAL-pebkacomp.md` with the mapping table.
- [x] Write research docs to `MouthPeace Docs/Research/PEBKACOMP-2026-06-05/`.

## B) Per-item evidence ledger

| Item | Action taken | File / command | Evidence | Verified |
|------|--------------|----------------|----------|----------|
| Map PEBKAC repo | `read` on README, SSOT, CHANGELOG, package.json, `pebkac-defense.js` (1835 lines via structural summary), `bin/pebkac.js` | `pebkac/README.md` (8345 snapshot), `SSOT/pebkac_SSOT.md` (AB90), `CHANGELOG.md` (B729), `package.json` (6273), `pebkac-defense.js` (326A), `bin/pebkac.js` (493D) | Structural summary shows 25 modules, 9 hooks, 5 slash commands; PEBKAC is 1798-1835 lines, single bundled extension, ESM/Bun | YES — read tool returned the file content |
| Catalog social-contract spots | Read each of `contract-compiler.ts`, `contradiction-guard.ts`, `evidence-enforcer.ts`, `reality-gate.ts`, `forbidden-behaviors.ts`, `turn-budget.ts`, `lifecycle.ts`, `circuit-breaker.ts`, plus the `index.ts` hook wiring (1180-1830) | `pebkac-defense.js:270-470`, `:460-640`, `:520-560,1113-1132`, `:780-895`, `:686-730,820-895`, `:1048-1180`, `:1180-1500`, `:1500-1830` | 14 spots cataloged with file:line, current mechanism, verdict (mechanical vs social); 10 mechanical, 4 social that are still useful post-hoc, 1 social that is fully replaceable | YES — line refs in 01-PEBKAC-SOCIAL-CONTRACT-CATALOG.md |
| Verify harness hook surface | Read `types.ts` (2591 snapshot, 1364 lines), `runner.ts` (37BB, 819 lines), `loader.ts` (E91A, 538 lines), `index.ts` (73FD) | `packages/coding-agent/src/extensibility/extensions/types.ts`, `runner.ts`, `loader.ts`, `index.ts` | `ExtensionEvent` union at types.ts:799-825; runner dispatch at runner.ts:435-819; loadable extensions at loader.ts:471-538 | YES — types.ts:799-825, runner.ts:435-471, 521-554, 556-594, 645-675, 677-726, 728-760, 762-817 quoted in 02-HARNESS-HOOK-SURFACE.md |
| Map spots to harness hooks | Wrote mapping table; for each spot, named the harness event and quoted the runner line | `03-PEBKACOMP-MAPPING.md` | 14 rows; 11 mechanical, 1 dropped (SC-7), 2 kept as backstop | YES — every cell has a file:line citation in 02-HARNESS-HOOK-SURFACE.md |
| Mark non-mechanically-enforceable | SC-7 contradiction-guard explicitly dropped with reason: "pre-empting a contradiction requires knowing what the model would say, which is a model task, not a hook task" | `01-PEBKAC-SOCIAL-CONTRACT-CATALOG.md` SC-7 row, `03-PEBKACOMP-MAPPING.md` SC-7 row, `06-PROPOSAL-PEBKACOMP.md` "Spot that does not ship" section | Honest reason stated; `ExtensionEvent` union at `types.ts:799-825` has no `pre_message_emit` event | YES — types.ts:799-825 enumerated in 02-HARNESS-HOOK-SURFACE.md |
| Design PEBKACOMP | Wrote 04-PEBKACOMP-DESIGN.md with module layout, state schema, event handler list, slash commands, coordination with PEBKAC, config integration, failure mode contract | `04-PEBKACOMP-DESIGN.md` | State fields, event handler summary, command table, coordination rules, failure mode (additive not load-bearing) | YES — file present, 11KB |
| Produce proposal | Wrote 06-PROPOSAL-PEBKACOMP.md with TL;DR, why, spots replaced, spot that does not ship, architecture, files to add per phase, risks, what PEBKACOMP does NOT do, next step | `06-PROPOSAL-PEBKACOMP.md` | 8 sections, 14-row spot table, 7-phase build order table, 4 risks listed | YES — file present, 10KB |
| Write research docs | Created subfolder `PEBKACOMP-2026-06-05/` and wrote 7 numbered docs | `bash mkdir -p` + 7× `write` | Directory listing: 7 .md files totaling ~50KB | YES — `ls -la` returned the 7 files |

## C) Verification receipts

### C.1 — PEBKAC repo inventory

```
ls -la pebkac/
README.md  9.8KB  1w ago
CHANGELOG.md  5.0KB  4w ago
SSOT/     pebkac_SSOT.md  5.9KB  3w ago
bin/      pebkac.js  3.5KB  1w ago
~/.mouthpeace/extensions/  pebkac-defense.js  (1835 lines, structural summary)
package.json  201B  1w ago
test/  (8 .test.js files, 7 helpers)
```

Verified via `read` tool; structural summary at `pebkac-defense.js#326A`
reports 25 modules, 9 hooks, 5 slash commands, ESM/Bun, bundled.

### C.2 — PEBKAC hook wiring

The PEBKAC extension registers the following harness hooks at
`pebkac-defense.js`:

- `session_start` (L1199-1272) — config + state init
- `before_agent_start` (L1273-1309) — contract prompt injection
- `session_before_compact` (L1310-1314) — checkpoint save
- `session_compact` (L1315-1329) — recovery injection
- `turn_start` (L1330-1341) — per-turn reset
- `turn_end` (L1342-1380) — degradation score + budget
- `tool_call` (L1381-1457) — block layer
- `tool_result` (L1458-1550) — rewrite layer
- `context` (L1551-1596) — reminder injection

Plus 5 slash commands at L1597-1829.

### C.3 — Harness hook surface

`packages/coding-agent/src/extensibility/extensions/types.ts:799-825`
defines `ExtensionEvent` as a union of 28 event types. The block-capable
events are:

- `tool_call` → `{block, reason}` (runner.ts:521-554)
- `user_bash`, `user_python` → `{block, reason, transformedInput}` (runner.ts:556-594)
- `session_before_switch`, `session_before_branch`,
  `session_before_compact`, `session_before_tree` → `{cancel}` (runner.ts:435-471)

The modify-capable events are:

- `tool_result` → `{content, details, isError}` (runner.ts:473-519)
- `before_provider_request` → `unknown` payload replacement (runner.ts:728-760)
- `before_agent_start` → `{systemPrompt?, message?}` (runner.ts:762-817)
- `context` → `{messages?: AgentMessage[]}` (runner.ts:677-726)
- `input` → `{text, images, handled}` (runner.ts:645-675)

### C.4 — Mapping verification

Each of the 14 spots in `03-PEBKACOMP-MAPPING.md` is paired with a specific
Harness event and a specific runner line. Spot-to-event assignment:

| SC-# | Spot | Harness event | Runner line |
|------|------|-----------|-------------|
| 1 | Forbidden scan | `before_provider_request` | runner.ts:728-760 |
| 2 | Contract | `tool_call` + `tool_result` | runner.ts:521-554, 473-519 |
| 3 | Context reminder | `before_provider_request` | runner.ts:728-760 |
| 4 | FLARE lifecycle | `tool_call` | runner.ts:521-554 |
| 5 | Ceremony | `tool_call` | runner.ts:521-554 |
| 6 | Grounding | `before_provider_request` | runner.ts:728-760 |
| 7 | Contradiction | **none** | n/a — dropped |
| 8 | Breaker recovery | `before_agent_start` + `tool_call` | runner.ts:762-817, 521-554 |
| 9 | Turn budget | `tool_call` | runner.ts:521-554 |
| 10 | FLARE plan | slash command + `tool_call` | loader.ts:367-368, runner.ts:521-554 |
| 11 | Silent operation | `before_provider_request` | runner.ts:728-760 |
| 12 | Subagent handoff | slash command + `ctx.sessionManager` | types.ts:217-246, loader.ts |
| 13 | Subagent result | `agent_end` | types.ts:498-502, runner.ts:435-471 |
| 14 | Pipeline | `agent_start`/`agent_end` + session manager | types.ts:493-502, loader.ts |

## D) Completeness matrix

| # | Item | Status | Evidence | Verified |
|---|------|--------|----------|----------|
| 1 | PEBKAC repo mapped | DONE | `read` snapshots 8345, AB90, 8D10, B729, 8A5A, 6273, 326A, 493D | YES |
| 2 | PEBKAC extension read | DONE | structural summary 326A; spot-specific reads at 270-470, 460-640, 520-560, 686-730, 780-895, 1048-1180, 1180-1500, 1500-1830 | YES |
| 3 | Social-contract spots cataloged (14 spots) | DONE | `01-PEBKAC-SOCIAL-CONTRACT-CATALOG.md` 14-row table with file:line | YES |
| 4 | Harness hook surface verified | DONE | `02-HARNESS-HOOK-SURFACE.md` quoting types.ts:799-825 and runner.ts:435-819 | YES |
| 5 | Spots mapped to harness hooks | DONE | `03-PEBKACOMP-MAPPING.md` 14-row table | YES |
| 6 | Non-mechanical spot marked | DONE | SC-7 dropped; reason in 01, 03, 06 | YES |
| 7 | PEBKACOMP design written | DONE | `04-PEBKACOMP-DESIGN.md` (state, events, commands, coordination) | YES |
| 8 | Build order written | DONE | `05-BUILD-ORDER.md` 8 phases with per-phase tests and exit criteria | YES |
| 9 | Proposal written | DONE | `06-PROPOSAL-PEBKACOMP.md` 8 sections | YES |
| 10 | Research folder created at `MouthPeace Docs/Research/PEBKACOMP-2026-06-05/` | DONE | `ls -la` returned 7 .md files | YES |
| 11 | CHANGELOG entry added | NOT IN SCOPE — PEBKAC's CHANGELOG is the source-of-truth changelog, and this proposal lives in `MouthPeace Docs/Research/`, not in the PEBKAC repo. PEBKAC's CHANGELOG should be updated *after* Phase 0 of the build lands, with the actual diff to `pebkac-defense.js` and the new `pebkacomp-defense.js`. | see 06-PROPOSAL-PEBKACOMP.md "Next step" | N/A — explicit out of scope per the user's "no implementation, just proposal" framing |

## Hard gate

All in-scope items have an evidence row. Item 11 is explicitly out of scope
(proposal, not implementation). The proposal itself recommends in
`06-PROPOSAL-PEBKACOMP.md` "Next step" that the CHANGELOG be updated when
Phase 0 of the build lands — i.e., when there is an actual diff to record.
Updating the CHANGELOG today, before the build starts, would be a
fabricated entry.

**FINAL STATUS: COMPLETE for proposal. CHANGELOG update deferred to
implementation phase as recommended in the proposal itself.**
