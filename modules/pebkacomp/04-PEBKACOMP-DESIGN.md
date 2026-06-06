# PEBKACOMP Design

PEBKACOMP is a normal harness extension. It lives at
`~/.mouthpeace/extensions/pebkacomp-defense.js` (a sibling of
`pebkac-defense.js`), is installed by `pebkac init` next to PEBKAC, and
registers handlers for harness events. It is registered *before* PEBKAC in the
loader order so its `tool_call` short-circuits win on collisions.

## Module layout

```
~/.mouthpeace/extensions/pebkacomp-defense.js     (single bundled extension, ~600 lines)
.harness/
  config.yaml                            (gains pebkacomp_mode: "sister" | "off")
  state/pebkacomp-state.json             (hasFlarePlan, breaker, evidenceLedger)
  checkpoints/pebkacomp.json             (pipeline state, subagent handles)
```

PEBKACOMP does not duplicate the L2 evidence enforcer or the L4 checkpoint
manager. It shares `.harness/state/` with PEBKAC by reading and writing the
same files. The two extensions are siblings, not a parent/child split.

## State owned by PEBKACOMP

All state is persisted to `.harness/state/pebkacomp-state.json` and reloaded
at `session_start`. Reset on `turn_start` only the per-turn counters.

| Field | Type | Purpose |
|-------|------|---------|
| `turnsConsumed` | int | per-session turn counter (L4 turn budget) |
| `turnBudget` | int \| null | L4 cap, default 100 |
| `breaker` | `{state, reason, reasonAtTurn}` | circuit breaker |
| `evidenceLedger` | `Array<{itemId, actionDescription, snippet, verified, ts, type}>` | evidence records |
| `activeItemId` | string \| null | currently enforced contract item |
| `hasFlarePlan` | boolean | FLARE plan gate |
| `pendingCeremonialClaim` | boolean | set by L2 ceremonial scan; cleared when evidence recorded |
| `outboundStripPatterns` | `RegExp[]` | patterns stripped from outbound payload before LLM call |
| `highRiskPatterns` | `RegExp[]` | patterns that trigger MUST-VERIFY injection |
| `pipeline` | `{stages[], currentIdx, results[]}` | pipeline state (persisted to checkpoints/pebkacomp.json) |
| `subagentHandles` | `{[id]: {sessionId, task, status, startedAt}}` | active sub-sessions |

## Event handlers

| Event | Handler summary |
|-------|-----------------|
| `session_start` | load `pebkacomp-state.json`, init pipeline handles, hook `ctx.ui.setStatus` |
| `before_agent_start` | if breaker open, augment system prompt with `produce evidence this turn`; if planning phase and `!hasFlarePlan`, augment system prompt with `call /pebkacomp-flare-plan` |
| `context` | (no handler; PEBKAC keeps the context reminder for backward compatibility) |
| `turn_start` | reset per-turn counters (`pendingCeremonialClaim`, `failedToolCallsThisTurn`); increment `turnsConsumed`; tick budget |
| `turn_end` | score degradation; tick breaker; write state if turn % 10 == 0 |
| `tool_call` | (a) rate limit, (b) repeat detector, (c) escalation, (d) tool allowlist, (e) breaker gate, (f) lifecycle phase, (g) git-guard, (h) secrets-guard, (i) evidence-required gate, (j) budget-exhaustion gate. All return `{block, reason}` per harness contract (`runner.ts:521-554`). |
| `tool_result` | (a) output length truncate, (b) secrets redact, (c) evidence dedup, (d) ceremonial scan sets `pendingCeremonialClaim`, (e) high-risk scan flags outbound for next `before_provider_request`, (f) forbidden-behavior scan (L2 backstop) |
| `before_provider_request` | (a) strip forbidden patterns from outbound user-text, (b) inject MUST-VERIFY messages for high-risk claims, (c) for SC-11, strip harness name references from outbound |
| `agent_start` | if pipeline active, record stage start in `.harness/checkpoints/pebkacomp.json` |
| `agent_end` | if pipeline active, record stage result; trigger next stage via `ctx.sessionManager.newSession(...)` |
| `session_before_compact` | save state to disk |
| `session_compact` | reload state from disk after compaction |
| `session_shutdown` | final state save |

## Slash commands registered

| Command | What it does |
|---------|-------------|
| `pebkacomp-status` | breaker state, evidence count, turn count, plan status, pipeline status |
| `pebkacomp-flare-plan` | accept a markdown plan as argument; set `hasFlarePlan = true`; persist |
| `pebkacomp-record-evidence` | accept `itemId`, `description`, `snippet`; append to evidenceLedger; clear `pendingCeremonialClaim`; clear breaker |
| `pebkacomp-spawn` | accept `task`, optional `vaultAccess`; call `ctx.sessionManager.newSession(...)` with structured handoff; store handle |
| `pebkacomp-pipeline start Build:test,lint Deploy:exit_code` | begin pipeline |
| `pebkacomp-pipeline status` | show pipeline state |
| `pebkacomp-pipeline complete <evidence>` | mark current stage done with evidence |
| `pebkacomp-pipeline block <reason>` | block current stage |

PEBKACOMP does *not* re-register the original PEBKAC slash commands
(`harness-status`, `flare-complete`, `harness-delegate`,
`harness-subagent-result`, `harness-pipeline`). The two extensions coexist;
the user's tooling chooses which to call. PEBKAC's commands stay for
backward compatibility; PEBKACOMP's commands are the new mechanical path.

## Coordination with PEBKAC

Both extensions can register handlers for the same event. The harness's
`emitToolCall` (`runner.ts:521-554`) short-circuits on the first
`{block: true}`. PEBKACOMP must register *before* PEBKAC so its
breakers/evidence-gates win.

For `tool_result`, the harness's `emitToolResult` (`runner.ts:473-519`) merges
results from all extensions. The two extensions both produce content; the
runner returns the last writer's `content`. PEBKACOMP writes the
post-ceremonial-scan content; PEBKAC writes the post-secret-redact
content. They must not both write the same field, or one will clobber the
other. Strategy: PEBKACOMP writes `content` and `details`; PEBKAC only
modifies `details.harnessMetadata` and only when PEBKACOMP has not already
written `details`.

For `before_provider_request`, the harness's `emitBeforeProviderRequest`
(`runner.ts:728-760`) applies handler results in order. The last writer's
payload is used. PEBKACOMP should be the only writer; PEBKAC does not
register a `before_provider_request` handler.

## Config integration

`bin/pebkac.js` `writeFileSync` for `.harness/config.yaml` gains:

```yaml
pebkacomp:
  mode: "sister"   # "sister" | "off"
  turn_budget: 100
  turn_warning: 20
  evidence_required: true
  grounding_required: true
  handoff_real_subagent: true
  pipeline_real_stages: true
```

PEBKAC's loader reads `pebkacomp.mode` at `session_start` (`index.ts:1199-1272`).
When `mode == "sister"`:
- PEBKAC's `buildContractSystemPromptLayer` (`contract-compiler.ts:384-465`)
  is replaced with a short banner pointing to PEBKACOMP.
- PEBKAC's context reminder injection (`index.ts:1551-1596`) is reduced to
  the `[HARNESS REMINDER]` prefix only.
- PEBKAC's forbidden-behavior post-hoc scan (`index.ts:1494-1499`) remains
  as a backstop, but with a note that PEBKACOMP's outbound patcher is the
  primary defense.
- PEBKAC's ceremonial-detection post-hoc scan (`index.ts:1500-1513`)
  remains as a user-visible annotation, but PEBKACOMP's `tool_call` block is
  the primary enforcement.

When `mode == "off"`, PEBKAC's current prompt-injection behavior is
unchanged (legacy path).

## Failure mode contract

If PEBKACOMP crashes (extension load error), the loader's behavior at
`loader.ts:263-297`
returns `{extension: null, error}`. The runner then continues with the
remaining extensions. PEBKAC remains active. The user's existing protection
is not removed by PEBKACOMP's failure.

This is the inverse of how PEBKAC is currently structured: PEBKAC is
load-bearing; PEBKACOMP is *additive*. PEBKAC never depends on PEBKACOMP.
