# the-verifier-agent-main SSOT (Single Source of Truth)
**Created:** 2026-05-04T08:46:27-0400
**Last Updated:** 2026-05-04T08:50:00-0400
**Governance:** .supercache/ v1.7.0

> **Compliance Notice:** This file must match the structure at
> `.supercache/templates/ssot-template.md`. This is the authoritative
> document for architecture and programmatic change facts of **the-verifier-agent-main**.

---

## Authority

This document is the **single source of truth** for architecture and programmatic change facts of the-verifier-agent-main. All other documents must be treated as **potentially flawed** unless their facts are confirmed here.

When a fact in any other document contradicts this SSOT, this SSOT wins. If this SSOT itself is wrong, it is corrected via the **Verification Sweep Protocol** below, not by editing other documents to match.

---

## Verification Sweep Protocol (required on every read)

When an agent reads this SSOT to perform a task:

1. Perform a **line-by-line verification review** of the sections relevant to the current task.
2. For each verified fact, append a verification entry to the **Verification Log** at the bottom of this file with:
   - Timestamp (`YYYY-MM-DD HH:MM TZ`)
   - Section/line reference
   - Evidence source (code path + line, command + output, build log, runtime behavior, etc.)
   - Confidence = 100%
3. If any fact cannot be verified to 100% confidence:
   - Mark it **UNVERIFIED** inline in the section where it appears
   - Add an entry to `Issues/the-verifier-agent-main_ISSUES.md` to track the discrepancy
   - Do NOT proceed on the assumption that the fact is true

### Positive Reinforcement (required)

For each fact verified at 100% confidence during a sweep, emit the acknowledgement:

```
Verified as fact (100%): <fact summary>
```

This pattern is deliberate — it reinforces evidence-first thinking and makes the verification record auditable after the fact.

---

## Current State

**Phase:** Prototype / Active modification
**Status:** Active
**Last Agent Session:** 2026-05-04 08:50 EDT

---

## Architecture Facts

### Stack

- **Primary language**: TypeScript (ES2022, strict, NodeNext module resolution)
- **Framework**: agent harness extension (`@mariozechner/pi-coding-agent ^0.70.5`)
- **Runtime**: Node.js >= 22.0.0 (loaded by the agent harness)
- **Module system**: ESM (`"type": "module"` in package.json)

### Key architectural choices

- **Two-agent observer pattern**: Builder agent runs interactively; Verifier agent runs in a sibling tmux window with input disabled, observing the builder's session JSONL via unix domain socket.
- **Unix domain socket IPC**: Cross-agent communication uses `/tmp/pi-verifier/*.sock`. The verifier connects, listens for builder lifecycle ticks, and pulls session slices.
- **Verifier prompt injection**: When verification fails, the verifier calls the `verifier_prompt` tool, which injects a follow-up user message into the builder via `sendUserMessage(deliverAs: "followUp")`. Max loops are persona-controlled and default to 3.
- **Launcher handles terminal detection**: The launcher detects `$TMUX`, `$TERM_PROGRAM`, and falls back to Terminal.app via osascript. The intended operator experience is a visible terminal window, not a headless verifier session.

---

## Key Decisions

| Date | Decision | Rationale | Decided By |
|---|---|---|---|
| 2026-05-04 | Anonymous local fork — no upstream remote | User requested privacy; MIT license permits modification | Douglas Talley |
| 2026-05-04 | Governance bootstrap via entry protocol | Project was initially missing current governance artifacts and needed a v1.7.0 stamp | Agent |
| 2026-05-04 | Canonical project name follows directory basename | Governance report spec uses directory basename as canonical identifier | Governance |
| 2026-05-04 | `verify install` is the supported global helper command | Avoids shadowing `/usr/bin/install`; command resolves source through symlink and copies verifier config safely into target cwd | Agent |
| 2026-05-04 | Ghostty launcher passes `tmux attach` as executable argv | Ghostty `-e` treats the following tokens as command argv; one shell string made Ghostty attempt to execute a literal filename with spaces | Agent |

---

## Dependencies

| Dependency | Version | Purpose | Criticality |
|---|---|---|---|
| `@mariozechner/pi-coding-agent` | ^0.70.5 | agent harness API | critical |
| `@mariozechner/pi-tui` | ^0.70.5 | Terminal UI components for status bar | critical |
| `typebox` | ^1.1.34 | Runtime type validation | supporting |
| `typescript` | ^5.6.0 | Type checking | dev-only |
| `@types/node` | ^22.0.0 | Node.js type definitions | dev-only |

---

## Deployment

| Environment | URL / Location | Status | Last Deploy |
|---|---|---|---|
| local | Terminal via `just v` | dev | N/A |

This project is a CLI extension — no server deployment.

---

## Known Patterns & Lessons

| Pattern | Trigger | Fix | Confidence |
|---|---|---|---|
| stale-verifier-socket | `EADDRINUSE` or "already connected" error | `just clean` then retry | 0.9 |
| env-missing | Agent fails to start with auth error | Copy `.env.sample` to `.env` and fill API keys locally | 0.8 |
| governance-name-drift | Bootstrap verify expects files named after directory basename | Use `the-verifier-agent-main_*` governance filenames | 1.0 |
| verify-install-conflict | Target project has a differing verifier persona or prompt | `verify install` blocks without `--force`; review target-specific file before replacing | 1.0 |
| ghostty-shell-string | Ghostty failure window shows `/usr/bin/login ... tmux attach -t ...` | Pass `tmux`, `attach`, `-t`, and the session name as separate argv tokens to `ghostty -e` | 1.0 |

---

## Verification Log (append-only)

Every sweep of this SSOT must append one or more entries here. Never edit or remove existing entries.

| Timestamp | Section / Line | Fact Verified | Evidence Source | Confidence |
|---|---|---|---|---|
| 2026-05-04T08:46:27-0400 | Authority | Document initialized as SSOT | `bootstrap.sh --repair` created from template | 100% |
| 2026-05-04 08:50 EDT | Stack | TypeScript ES2022 ESM project | `apps/verifier/package.json` and `apps/verifier/tsconfig.json` read in current session | 100% |
| 2026-05-04 08:50 EDT | Dependencies | Five dev dependencies listed | `apps/verifier/package.json` lines 10-16 read in current session | 100% |
| 2026-05-04 08:50 EDT | Architecture | Verifier uses builder/verifier two-agent IPC | `README.md` lines 7-12 and `apps/verifier/verifiable.ts` lines 1-14 read in current session | 100% |
| 2026-05-04 08:50 EDT | Governance | Project stamped at .supercache v1.7.0 | `bootstrap.sh --verify` output PASS 11/11 in current session | 100% |
| 2026-05-04 08:58 EDT | Installer | `verify install` copies verifier config through a symlink-resolved source root and preserves target settings | `node --test tests/verify-install.test.mjs` passed 4/4; symlink smoke test printed `cli symlink install ok` | 100% |
| 2026-05-04 12:11 EDT | Launcher | Ghostty launcher passes tmux attach as argv instead of one shell string | `ast_grep` matched `execFileP("ghostty", ["-e", "tmux", "attach", "-t", tmuxSession])`; `node --test tests/verify-install.test.mjs` passed 5/5 | 100% |
| 2026-05-04 12:11 EDT | Governance | Project remains compliant after Ghostty launcher fix | `bootstrap.sh --verify` run from this module output PASS 11/11 | 100% |

---

## Change Log (append-only)

- 2026-05-04T08:46:27-0400 — Initialized SSOT.
- 2026-05-04 08:50 EDT — Migrated verified facts from stale `the-verifier-agent_SSOT.md` into canonical `the-verifier-agent-main_SSOT.md` and aligned governance version to v1.7.0.

- 2026-05-04 08:58 EDT — Added global `verify install` helper, node:test coverage, and documented installer conflict behavior.
- 2026-05-04 12:11 EDT — Fixed Ghostty terminal dispatch to pass `tmux attach -t <session>` as argv tokens, added a regression test, and reran tests/typecheck/governance.
<!-- Append new entries BELOW this comment line, in chronological order. -->
<!-- Never edit or remove existing entries — this is the authoritative change history. -->

---

## Mandatory execution contract
For EACH requested item:
1) Show exact action taken
2) Show direct evidence (file/line/command/output)
3) Show verification result
4) Mark status only after proof

## Forbidden behaviors
- Declaring "done" without evidence
- Collapsing multiple requested items into one vague summary
- Skipping failed steps without explicit blocker report

## Required output structure
A) Requested items checklist
B) Per-item evidence ledger
C) Verification receipts
D) Completeness matrix (item -> done/blocked -> evidence)

## Hard gate
If any requested item has no evidence row, final status MUST be INCOMPLETE.
