# PEBKACOMP Mapping — Spots to Harness Hooks

For each PEBKAC social-contract spot, the harness hook class that can do it
mechanically, the handler shape, and an honest reason for spots that cannot be
mechanically enforced.

All harness citations are in `02-HARNESS-HOOK-SURFACE.md`.

## Spot-by-spot

### SC-1: Forbidden-behavior scan

- **PEBKACOMP hook:** `pi.on("before_provider_request", handler)` — outbound.
- **Handler shape:**
  ```
  pi.on("before_provider_request", async (event, ctx) => {
    const payload = event.payload;
    // walk payload.messages; for each assistant text, strip forbidden patterns
    return strippedPayload;
  });
  ```
- **Result type:** `unknown` (full payload replacement). Verified
  `runner.ts:728-760`.
- **Mechanical proof:** the payload is replaced *before* the LLM call. The
  forbidden patterns never reach the LLM as input.
- **Limitation:** strips from outbound only. The LLM may still emit them
  on a later turn; the L2 post-hoc rewrite in PEBKAC catches that for the
  user-visible output.

### SC-2: Execution contract

- **PEBKACOMP hook:** drop the system-prompt text wall from PEBKACOMP; use
  `pi.on("tool_call", ...)` and `pi.on("tool_result", ...)` to enforce.
- **Handler shape (tool_call):**
  ```
  pi.on("tool_call", async (event, ctx) => {
    if (!enforcer.hasEvidenceForActiveItem()) {
      return { block: true, reason: "No evidence recorded for the active contract item. Run the test/build command, then call /pebkacomp-record-evidence." };
    }
  });
  ```
- **Result type:** `{block, reason}`. Verified `runner.ts:521-554`.
- **Mechanical proof:** the tool call is refused before the LLM gets to run
  it. There is no model-decides-to-comply step.

### SC-3: Context reminder

- **PEBKACOMP hook:** `pi.on("before_provider_request", handler)`.
- **Handler shape:** patch the *last user message* (or inject a synthetic
  message) with the reminder text, so the next token the LLM reads is the
  reminder.
- **Result type:** `unknown` payload replacement. Verified `runner.ts:728-760`.
- **Mechanical proof:** the reminder is in the literal token stream, not in a
  tail-appended `role: "user"` block that the LLM can ignore.

### SC-4: FLARE lifecycle (keep, extend)

- **PEBKACOMP hook:** `pi.on("tool_call", handler)` — keep PEBKAC's existing
  `lifecycle.ts:checkToolPolicy`. Cite `runner.ts:521-554`.
- **Mechanical proof:** already mechanical. Extend by adding
  `pebkacomp-flare-plan` slash command (see SC-10) to set the plan state
  without regex sniffing.

### SC-5: Ceremonial completion

- **PEBKACOMP hook:** `pi.on("tool_call", handler)`.
- **Handler shape:** maintain `pendingCeremonialClaim: boolean`. Set true when
  `tool_result` sees a ceremonial pattern. On the next `tool_call` while the
  flag is set, return `{block, reason: "Evidence required before next tool."}`.
  Clear the flag when `enforcer.recordEvidence` is called.
- **Result type:** `{block, reason}`. Verified `runner.ts:521-554`.
- **Mechanical proof:** the next tool is refused at the runtime layer. The
  LLM cannot proceed without producing a verified evidence record.

### SC-6: Reality-gate grounding

- **PEBKACOMP hook:** `pi.on("before_provider_request", handler)`.
- **Handler shape:** scan outbound payload for `HIGH_RISK_PATTERNS` (the same
  six from `reality-gate.ts:784-791`). When a high-risk claim is present in
  an assistant message, insert a synthetic message immediately before it
  containing `[MUST VERIFY: <category>]` and a `web_search` call hint.
- **Result type:** `unknown` payload replacement. Verified `runner.ts:728-760`.
- **Mechanical proof:** the LLM literally cannot generate the next token
  without first reading the MUST-VERIFY instruction. The L2 post-hoc reminder
  in PEBKAC remains as a backup.

### SC-7: Contradiction-guard

- **Status:** **dropped from PEBKACOMP.**
- **Honest reason:** pre-empting a contradiction requires knowing what the
  model *would* say, which is a model task, not a hook task. There is no
  harness event that fires "the model is about to emit X." The L2 post-hoc
  rewrite stays in PEBKAC; PEBKACOMP does not attempt it.
- **Mechanical proof of impossibility:** `ExtensionEvent` union
  (`types.ts:799-825`) has no `pre_message_emit` or `pre_text_emit` event.
  There is no `before_assistant_text` hook. The closest hooks (`input`,
  `before_provider_request`, `before_agent_start`) fire on *user* input or
  on the full provider payload, not on the model's incremental text.

### SC-8: Circuit-breaker recovery

- **PEBKACOMP hook:** `pi.on("before_agent_start", handler)` + `pi.on("tool_call", handler)`.
- **Handler shape (before_agent_start):** if `breaker.isOpen`, return
  `{systemPrompt: original + "\n\n[BREAKER OPEN] Produce evidence this turn or the next tool call is blocked."}`.
- **Handler shape (tool_call):** if `breaker.isOpen`, return `{block, reason: breaker.reason}`.
- **Result type:** `{systemPrompt}` for the first, `{block, reason}` for the second.
  Verified `runner.ts:762-817` and `runner.ts:521-554`.
- **Mechanical proof:** breaker state lives in the extension; the
  system-prompt augmentation is a real token-stream change; the tool block
  is a real block. No user-issued slash command is required to recover.

### SC-9: Turn budget

- **PEBKACOMP hook:** `pi.on("tool_call", handler)`.
- **Handler shape:** on each `turn_start`, increment `turnsConsumed`. On each
  `tool_call`, if `turnsConsumed >= turnBudget`, return
  `{block, reason: "Turn budget exhausted."}` except for `harness-status` /
  `pebkacomp-status`.
- **Result type:** `{block, reason}`. Verified `runner.ts:521-554`.
- **Mechanical proof:** the LLM cannot call tools past the budget. Reminder
  injection (current behavior) is removed.

### SC-10: FLARE-plan detection

- **PEBKACOMP hook:** `pi.registerCommand("pebkacomp-flare-plan", { ... })` +
  `pi.on("tool_call", handler)`.
- **Handler shape (command):** on call, parse the user's plan argument, set
  `checkpoint.state.hasFlarePlan = true`, write to disk, notify via
  `ctx.ui.notify`.
- **Handler shape (tool_call):** read `hasFlarePlan` from in-memory cache
  (synced from disk at `turn_start`); if planning phase and `!hasFlarePlan`,
  return `{block, reason: "FLARE plan required. Call /pebkacomp-flare-plan with your plan."}`.
- **Result type:** slash command, plus `{block, reason}` for tool_call.
  Verified `loader.ts:367-368` for command registration, `runner.ts:521-554`
  for the block.
- **Mechanical proof:** the planning-phase gate reads a boolean set by an
  explicit command, not a regex over conversation history. There is no
  pattern-match failure mode.

### SC-11: Silent operation

- **PEBKACOMP hook:** `pi.on("before_provider_request", handler)` for outbound.
- **Handler shape:** strip mentions of `PEBKAC`, `harness`, `pebkacomp` from
  the *outbound* payload's user-visible text fields. The LLM never sees
  references to the harness in the prompt; it cannot echo them.
- **Result type:** `unknown` payload replacement. Verified `runner.ts:728-760`.
- **Mechanical proof:** outbound patches run before the LLM call. The L2
  post-hoc output rewriter in PEBKAC remains as a backstop.

### SC-12: Subagent handoff

- **PEBKACOMP hook:** `pi.registerCommand("pebkacomp-spawn", { ... })` +
  `ctx.sessionManager.newSession(...)` or `ctx.sessionManager.spawnSubagent(...)`.
- **Handler shape:** if `spawnSubagent` exists on `SessionManager`, call it
  with the structured handoff (task, checkpoint state, vault access,
  timeout). If only `newSession` exists, create a fresh session with the
  handoff baked into the system prompt.
- **Result type:** slash command. Verified `loader.ts:367-368`.
- **Mechanical proof:** the sub-session actually exists. It runs in
  PEBKACOMP's process boundary (or a child process owned by the harness runner);
  it does not require a human to copy-paste a string.

### SC-13: Subagent result

- **PEBKACOMP hook:** `pi.on("agent_end", handler)` on the sub-session.
- **Handler shape:** when the sub-session emits `agent_end`, parse the final
  assistant message for evidence records and checkpoint updates, call
  `enforcer.recordEvidence` for each, persist.
- **Result type:** notify-only event. Verified `types.ts:498-502`,
  `runner.ts:435-471` (generic emit).
- **Mechanical proof:** PEBKACOMP reacts to the real end-of-subagent signal
  emitted by the harness. No manual paste step.

### SC-14: Pipeline

- **PEBKACOMP hook:** `pi.on("agent_start", handler)` + `pi.on("agent_end", handler)`
  + slash commands for stage control.
- **Handler shape:** each pipeline stage = a `ctx.sessionManager.newSession(...)`
  call with a stage-specific prompt. `agent_start` records the start of the
  stage to `.harness/checkpoints/pipeline.json`; `agent_end` records the
  result and triggers the next stage.
- **Result type:** notify events plus slash commands. Verified
  `types.ts:493-502`, `loader.ts`.
- **Mechanical proof:** the pipeline is a real sequence of LLM invocations,
  not a string-state object. Stage completion is observed from the runtime,
  not typed by the user.

## Summary table

| SC-# | PEBKACOMP hook | Harness file:line | Status |
|------|----------------|---------------|--------|
| SC-1 | `before_provider_request` | `runner.ts:728-760` | mechanical |
| SC-2 | `tool_call` block + `tool_result` rewrite | `runner.ts:521-554`, `runner.ts:473-519` | mechanical |
| SC-3 | `before_provider_request` payload patch | `runner.ts:728-760` | mechanical |
| SC-4 | `tool_call` block (keep PEBKAC) | `runner.ts:521-554` | mechanical |
| SC-5 | `tool_call` block on next tool | `runner.ts:521-554` | mechanical |
| SC-6 | `before_provider_request` MUST-VERIFY patch | `runner.ts:728-760` | mechanical |
| SC-7 | **dropped** | n/a | not mechanical |
| SC-8 | `before_agent_start` + `tool_call` | `runner.ts:762-817`, `runner.ts:521-554` | mechanical |
| SC-9 | `tool_call` block on budget exhaustion | `runner.ts:521-554` | mechanical |
| SC-10 | slash command + `tool_call` gate | `loader.ts:367-368`, `runner.ts:521-554` | mechanical |
| SC-11 | `before_provider_request` outbound strip | `runner.ts:728-760` | mechanical |
| SC-12 | slash command + `ctx.sessionManager` | `types.ts:217-246`, `loader.ts` | mechanical |
| SC-13 | `agent_end` subscription | `types.ts:498-502`, `runner.ts:435-471` | mechanical |
| SC-14 | `agent_start`/`agent_end` + session manager | `types.ts:493-502`, `loader.ts` | mechanical |
