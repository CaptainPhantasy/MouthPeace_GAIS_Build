# Build Order

Phased plan, per-phase tests, exit criteria. Each phase ends with all
tests green and the phase's contract behavior demonstrated in the test
harness at `pebkac/test/`.

## Phase 0 — Scaffold (1 file, no behavior change)

Files:
- `~/.mouthpeace/extensions/pebkacomp-defense.js` (stub `(pi) => { pi.setLabel("PEBKACOMP [mechanical]") }`)
- `bin/pebkac.js` copy pebkacomp-defense.js to the harness extensions directory in `init`
- `test/pebkacomp-smoke.test.js` (mirror of `test/smoke.test.js` for the
  pebkacomp extension)

Tests:
- `bun test test/pebkacomp-smoke.test.js` — extension loads, sets label,
  registers no hooks yet.

Exit:
- `bun test` exit 0, both smoke tests pass.
- `pebkacomp-defense.js` exists in the harness extensions directory after `pebkac init`.

## Phase 1 — Port the already-mechanical handlers

Move (copy + delete from PEBKAC) into PEBKACOMP:
- `rate-limiter.ts` (50 calls/turn)
- `repeat-detector.ts` (10-call history)
- `escalation.ts` (5 consecutive blocks)
- `tool-allowlist.ts` (configurable)
- `circuit-breaker.ts` (open/half-open/closed)
- `lifecycle.ts` (planning/review phase policy)
- `git-guard.ts` (10 destructive patterns)
- `secrets-guard.ts` (redact 7 patterns, block 9 exposure commands)
- `output-guard.ts` (50K char cap)
- `evidence-dedup.ts` (snippet hash dedup)
- `forbidden-behaviors.ts` (4 patterns, post-hoc, kept as backstop)

The `index.ts` `pebkacDefenseExtension(pi)` factory loses the corresponding
handlers; PEBKACOMP's `index.ts` `pebkacompDefenseExtension(pi)` factory
gains them. PEBKAC keeps the prompt-layer and post-hoc rewrite code that
is not replaced in this phase.

Tests:
- `test/pebkacomp-git.test.js` — port `test/redaction.test.js` patterns for
  git commands; assert `{block: true, reason}` shape.
- `test/pebkacomp-secrets.test.js` — port `test/redaction.test.js` for
  command and output redaction.
- `test/pebkacomp-rate-limit.test.js` — 50 calls pass, 51st blocks.
- `test/pebkacomp-circuit-breaker.test.js` — port `test/breaker-escalation.test.js`.

Exit:
- All `pebkacomp-*` tests pass.
- `test/smoke.test.js` and `test/redaction.test.js` and `test/breaker-escalation.test.js`
  no longer cover the moved code (delete those test cases or move them).

## Phase 2 — `before_provider_request` outbound patcher (SC-1, SC-3, SC-6, SC-11)

Add to PEBKACOMP:
- `outbound-patcher.ts` — strips forbidden patterns from outbound user-text
  AND injects MUST-VERIFY messages before high-risk claims.
- Wire `pi.on("before_provider_request", outboundPatchHandler)`.
- The handler returns the modified payload; the runner (`runner.ts:728-760`)
  uses it.

Tests:
- `test/pebkacomp-outbound-strip.test.js` — payload containing
  `"the harness requires me to"` is rewritten to `"the [redacted] requires me to"`
  (or stripped) before the LLM call. Use a fake `pi` that captures the
  handler result and asserts the modified payload.
- `test/pebkacomp-high-risk-verify.test.js` — payload containing
  `"OpenAI's API costs $0.03 per 1K tokens"` (matches `pricing` pattern) gets
  a synthetic message inserted before it: `"[MUST VERIFY: pricing] Call web_search
  before continuing."`.

Exit:
- Both tests pass; assertion is on the *returned* payload, not on the
  LLM's eventual output.

## Phase 3 — `before_agent_start` system-prompt patcher (SC-2, SC-8)

Add to PEBKACOMP:
- `prompt-augmentor.ts` — when `breaker.isOpen`, augment systemPrompt with
  the breaker reason. When `!hasFlarePlan && phase == "planning"`, augment
  with the FLARE-plan-required reminder.
- Wire `pi.on("before_agent_start", augmentHandler)`.
- The handler returns `{systemPrompt, message}`; the runner
  (`runner.ts:762-817`) merges.

Tests:
- `test/pebkacomp-breaker-augment.test.js` — when breaker is open, the
  system prompt returned to the LLM includes the breaker reason. Use a
  fake `pi` that captures the handler result.

Exit:
- Test passes; the assertion is on the `systemPrompt` field of the
  handler's return value.

## Phase 4 — `tool_call` evidence-required gate (SC-5, SC-9)

Add to PEBKACOMP:
- `evidence-gate.ts` — on `tool_call`, if `pendingCeremonialClaim` is true,
  return `{block, reason}`. On `tool_call`, if `turnsConsumed >= turnBudget`
  and tool is not `pebkacomp-status`, return `{block, reason}`.
- Wire `pi.on("tool_call", evidenceGateHandler)`.

Tests:
- `test/pebkacomp-ceremony-block.test.js` — when `pendingCeremonialClaim`
  is true, the next `tool_call` returns `{block: true}`. After evidence is
  recorded, the gate clears.
- `test/pebkacomp-budget-block.test.js` — when `turnsConsumed >= turnBudget`,
  the next `tool_call` returns `{block: true}` unless the tool is
  `pebkacomp-status`.

Exit:
- Both tests pass.

## Phase 5 — FLARE-plan via slash command (SC-10)

Add to PEBKACOMP:
- `flare-gate.ts` — slash command handler that sets `hasFlarePlan = true`
  from explicit user input.
- The `tool_call` lifecycle check now reads `hasFlarePlan` from the
  pebkacomp-state store, not from regex pattern matching.
- Delete the regex sniffing in PEBKAC's `index.ts:1551-1563` (or guard
  with `if (config.pebkacomp_mode === "sister") return;`).

Tests:
- `test/pebkacomp-flare-gate.test.js` — without `hasFlarePlan`, the
  planning-phase `tool_call` blocks with reason
  `"FLARE plan required. Call /pebkacomp-flare-plan with your plan."`. After
  `/pebkacomp-flare-plan <plan text>` is invoked, the next `tool_call`
  returns `{block: false}`.

Exit:
- Test passes.

## Phase 6 — Real subagent (SC-12, SC-13, SC-14)

Add to PEBKACOMP:
- `subagent-spawner.ts` — slash command handler that calls
  `ctx.sessionManager.newSession(...)` (or `spawnSubagent(...)` if the
  method exists on the harness's `SessionManager` type — verify with a follow-up
  read of `types.ts` and the `SessionManager` source). The sub-session
  inherits the pebkacomp-state checkpoint.
- `pi.on("agent_end", subagentEndHandler)` — when the sub-session ends,
  parse the final assistant message for evidence records; append to
  evidenceLedger; persist.
- `pipeline-runner.ts` — when the user invokes
  `/pebkacomp-pipeline start`, write the stage list to
  `.harness/checkpoints/pebkacomp.json` and immediately spawn the first
  stage via `ctx.sessionManager.newSession(...)`. `agent_start` and
  `agent_end` on the stage sessions update the pipeline state and trigger
  the next stage.

Tests:
- `test/pebkacomp-spawn.test.js` — assert that calling the spawn command
  invokes `ctx.sessionManager.newSession(...)` with the expected prompt
  and checkpoint state. (Mock the session manager.)
- `test/pebkacomp-pipeline.test.js` — port `test/pipeline.test.js` to the
  new state machine. Stage transitions are observed via `agent_end` from
  mocked sub-sessions.

Exit:
- Both tests pass. The pipeline is no longer a string-state object; it
  is observable end-to-end through real sub-session lifecycle events.

## Phase 7 — Config integration + PEBKAC legacy switch

- `bin/pebkac.js` `init` writes the new `pebkacomp:` block to
  `.harness/config.yaml`.
- PEBKAC's `index.ts:1199-1272` loader reads `pebkacomp.mode`. When
  `"sister"`, the prompt-layer code paths become no-ops; when `"off"`,
  the legacy prompt-injection behavior is preserved.
- Existing PEBKAC tests must continue to pass when `pebkacomp.mode == "off"`.

Tests:
- `test/pebkacomp-config.test.js` — assert that
  `config.pebkacomp.mode == "sister"` causes PEBKAC's `buildContractSystemPromptLayer`
  to be skipped. (Direct call to the function in PEBKAC's module.)
- All PEBKAC tests must pass with `pebkacomp.mode == "off"` (no behavior
  change for legacy path).

Exit:
- All tests pass in both modes.

## Final acceptance

`bun test` exit 0 with all PEBKAC + PEBKACOMP tests.

The following is observable in a real harness run:
1. PEBKACOMP extension loads, label visible in `/pebkacomp-status`.
2. A `tool_call` for `git reset --hard` returns `{block: true, reason: "..."}`.
3. A `before_provider_request` containing "the harness requires me to"
   arrives at the LLM with the phrase stripped.
4. A `tool_call` after a ceremonial claim without evidence records
   returns `{block: true, reason: "..."}`.
5. A `pebkacomp-spawn <task>` call results in a real sub-session
   observable via `agent_start` / `agent_end` events.
6. `pebkacomp-flare-plan <plan text>` is the only path that sets
   `hasFlarePlan`; no regex sniffing remains.

Any item not observable this way is not in PEBKACOMP.
