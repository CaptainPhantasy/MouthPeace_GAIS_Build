# PEBKAC Social-Contract Catalog

Every enforcement point in PEBKAC that does not already use a mechanical harness
hook. Each row has a file:line citation and a verdict: **MECHANICAL** (real
block/rewrite) vs **SOCIAL** (prompt injection / post-hoc annotation that the
LLM can ignore).

Catalog of PEBKAC spots, derived from the bundled extension at
`pebkac/.mouthpeace/extensions/pebkac-defense.js`.

## Already mechanical (do not touch in PEBKACOMP)

| Layer | Module | Hook | What it does | File:line |
|-------|--------|------|--------------|-----------|
| L3 | git-guard | `tool_call` | block 10 destructive git patterns | `git-guard.ts:637-696`, wiring `index.ts:1430-1444` |
| L3 | secrets-guard | `tool_call` + `tool_result` | block credential-exposure commands, redact 7 secret patterns from output | `secrets-guard.ts:836-902`, wiring `index.ts:1438-1455`, `1469-1472` |
| L3 | rate-limiter | `tool_call` | block at 50 calls/turn | `rate-limiter.ts:982-1005`, wiring `index.ts:1382-1388` |
| L3 | repeat-detector | `tool_call` | block identical retry by `(toolName, inputHash)` | `repeat-detector.ts:1015-1031`, wiring `index.ts:1389-1395` |
| L3 | escalation | `tool_call` | block after 5 consecutive blocks | `escalation.ts:1033-1050`, wiring `index.ts:1396-1402` |
| L3 | tool-allowlist | `tool_call` | configurable per-tool allow/deny | `tool-allowlist.ts:1074-1089`, wiring `index.ts:1403-1409` |
| L3 | circuit-breaker | `tool_call` | block all tools when breaker open; only `harness-status`/`harness-audit` allowed in half-open | `circuit-breaker.ts:202-239`, wiring `index.ts:1410-1422` |
| L3 | lifecycle | `tool_call` | block `bash`/`write`/`edit`/`notebook` during planning/review | `lifecycle.ts:698-726`, wiring `index.ts:1423-1429` |
| L3 | output-guard | `tool_result` | truncate response at 50,000 chars | `output-guard.ts:1007-1013`, wiring `index.ts:1467-1468` |
| L4 | evidence-dedup | `tool_result` | filter duplicate evidence records | `evidence-dedup.ts:1091-1111`, wiring `index.ts:1476-1487` |

## Social-contract spots (the targets PEBKACOMP replaces or shrinks)

### SC-1: Forbidden-behavior scan / silent operation

- **Current code:** `forbidden-behaviors.ts:1113-1131` (4 regex patterns), wired into `tool_result` at `index.ts:1494-1499`.
- **Mechanism:** Post-hoc. When the LLM emits "the harness requires me to" or "PEBKAC is blocking", the output is *appended* with a reminder. The model has already spoken; the user has already seen the false claim.
- **Why it is social:** A regex that runs after the LLM emits text is not enforcement. The user already saw the wrong text. Stripping the pattern from output does not stop the model from emitting it next turn.
- **Verdict:** Replace with `before_provider_request` outbound patch (`runner.ts:728-760` accepts arbitrary payload replacement) so the forbidden patterns are stripped before the LLM sees them, OR drop the LLM-side claim entirely. Both are mechanical; the current is not.

### SC-2: Execution contract as system-prompt text

- **Current code:** `contract-compiler.ts:384-465` `buildContractSystemPromptLayer()`. The entire L1 contract — forbidden behaviors, mandatory protocol, evidence-ledger format, completeness matrix — is a multi-thousand-character system-prompt block injected at `before_agent_start` (`index.ts:1273-1309`).
- **Mechanism:** Prompt injection. The model is told "you MUST NOT" and "MUST produce X" via system-prompt text.
- **Why it is social:** Compliance depends on the LLM following the prompt. A jailbroken model, a smaller model, or a model that has competing instructions ignores it. There is no `block: true` here.
- **Verdict:** Drop the text wall. Move enforcement to `tool_call` blocks (don't run tools when an item is in violation) and `tool_result` rewrites (inject the evidence ledger into tool output for the model to use). Both are mechanical; the prompt wall is not.

### SC-3: Context reminder injection

- **Current code:** `index.ts:1551-1596`. Every `context` event appends a fake `role: "user"` reminder: "Execution contract active. Evidence required for every status claim. No 'done' without proof. ... Comply silently."
- **Mechanism:** Prompt injection disguised as a user message.
- **Why it is social:** Same as SC-2 — relies on the LLM reading and acting on the reminder.
- **Verdict:** Replace with `before_provider_request` patch that puts the reminder into the *last actual user message* (or into a message that the LLM literally cannot ignore because it precedes the next token the LLM will read). `runner.ts:728-760` accepts a full payload replacement.

### SC-4: FLARE planning-phase enforcement

- **Current code:** `lifecycle.ts:699-726`, wiring `index.ts:1423-1429`.
- **Mechanism:** `tool_call` `checkToolPolicy` blocks `bash`/`write`/`edit`/`notebook` during the planning phase.
- **Verdict:** **Already mechanical** — `tool_call` returns `{block, reason}`. Listed here for completeness. PEBKACOMP keeps this.

### SC-5: Ceremonial completion / evidence enforcer

- **Current code:** `evidence-enforcer.ts:524-570` (7 ceremonial regexes, 8 evidence regexes), wired into `tool_result` at `index.ts:1500-1513`.
- **Mechanism:** Post-hoc text append: "Completion claim detected without substantive evidence. Show actual command output, test results, or file diffs." or a `[PEBKAC HARD BLOCK]` annotation.
- **Why it is social:** The model has *already* emitted "tests passed!" and the user has already seen it. The annotation is just more text. Worse, the model is told "fix silently" — but the *evidence ledger* (the actual store) is never populated by the model anyway; the store is populated by `enforcer.recordEvidence` from the L2 tool-result scan (`index.ts:1478-1487`).
- **Verdict:** Replace with a `tool_call` block on the *next* tool after a ceremonial claim, refusing to run the tool until `enforcer.recordEvidence` has been called with a verified record. `runner.ts:521-554` accepts `{block, reason}`. This is mechanical.

### SC-6: Reality gate grounding

- **Current code:** `reality-gate.ts:783-834` (6 high-risk regexes: version_number, release_date, deprecation, security, pricing, best_practice), wired into `tool_result` at `index.ts:1520-1526`.
- **Mechanism:** Post-hoc text append: "This output contains a `<category>` claim ('<fragment>'). Verify with a current source before asserting."
- **Why it is social:** The model has already asserted the high-risk claim. The reminder only tells it to fix the next time. There is no enforcement of verification.
- **Verdict:** Use `before_provider_request` to patch the outbound payload to insert a literal `[MUST VERIFY: <category>]` instruction before the high-risk claim, so the next token the LLM reads is the instruction. `runner.ts:728-760` accepts payload replacement. This is mechanical.

### SC-7: Contradiction-guard

- **Current code:** `contradiction-guard.ts:467-493` (6 contradiction regexes), wired into `tool_result` at `index.ts:1514-1518`.
- **Mechanism:** Post-hoc string rewrite replacing the contradiction fragment with a hedge.
- **Why it is social:** This is not enforcement — it is output sanitization. The model can keep producing contradictory output; PEBKAC just rewrites the last one.
- **Verdict:** **Cannot be made mechanical without a second LLM call.** Pre-empting the model's output requires knowing what the model *would* say, which requires a model. PEBKACOMP **drops this**. Stays in PEBKAC as a soft post-hoc rewrite, with a candid note that it is not enforcement.

### SC-8: Circuit-breaker recovery

- **Current code:** `circuit-breaker.ts:202-239`, wiring `index.ts:1410-1422`. Recovery requires the user to call `/harness-status` (slash command), which triggers `breaker.halfOpen()` (`index.ts:1601-1603`).
- **Mechanism:** User-initiated slash command.
- **Why it is social:** The harness waits for a human to ask for status. The model is not informed; no tool is blocked.
- **Verdict:** Use `before_agent_start` to inspect breaker state; if open, return `{systemPrompt: <augmented>}` with an explicit "produce evidence this turn or the next tool call is blocked" instruction, and on the next `tool_call` block until evidence is recorded. `runner.ts:762-817` accepts `{systemPrompt, message}`. This is mechanical.

### SC-9: Turn budget

- **Current code:** `turn-budget.ts:1052-1072`, wiring `index.ts:1330-1340` (tick) and `1371-1379` (summary on exhaustion).
- **Mechanism:** Reminder injection at exhaustion; no `block: true`.
- **Why it is social:** The model is told "wrap up" but is not blocked from continuing to call tools.
- **Verdict:** Use `tool_call` to return `{block, reason}` when `turnsConsumed >= turnBudget`, except for `harness-status`. `runner.ts:521-554` accepts `{block, reason}`. This is mechanical.

### SC-10: FLARE-plan detection (regex sniffing)

- **Current code:** `index.ts:1551-1563`. Heuristic regex match for `"FLARE"`, `"confidence:"`, or `/^#{1,3}\s*(plan|steps)/im` in message content.
- **Mechanism:** String pattern matching in conversation history.
- **Why it is social:** The model is supposed to write a markdown plan with a "FLARE" header and `confidence:` lines. If the model writes a plan with different wording, the regex misses it. If the model writes the words but does not actually plan, the regex passes.
- **Verdict:** Replace with a slash command `pebkacomp-flare-plan` that the model calls explicitly when its plan is done. PEBKACOMP stores `hasFlarePlan: true` in the checkpoint store on receipt. The `tool_call` lifecycle check reads this store instead of regex-matching message content. `loader.ts:367-368` and `runner.ts:521-554`. This is mechanical.

### SC-11: Silent operation

- **Current code:** Same as SC-1. System prompt section "### SILENT OPERATION" (`contract-compiler.ts:406-419`) plus the post-hoc `forbidden-behaviors` scan.
- **Mechanism:** Prompt injection + post-hoc rewrite.
- **Why it is social:** A prompt section that says "do not mention the harness" is itself a mention of the harness (in the prompt). LLMs degrade compliance across long contexts. The post-hoc regex is sanitization, not enforcement.
- **Verdict:** Outbound `before_provider_request` patch rewrites the prompt to use the harness's actual name only in places where the model has no choice; the rest is stripped before the LLM sees it. `runner.ts:728-760`. This is mechanical.

### SC-12: Subagent handoff via copy-paste

- **Current code:** `index.ts:1654-1682`. Slash command prints a serialized handoff; user pastes it into a fresh agent context.
- **Mechanism:** Manual copy-paste.
- **Why it is social:** The harness is a glorified string formatter. There is no actual subagent; there is no state propagation.
- **Verdict:** Use `ctx.sessionManager` (exposed to extensions per `types.ts:217-246`) to spawn a real sub-session. PEBKACOMP registers a `pebkacomp-spawn` slash command that calls `ctx.sessionManager.spawnSubagent({...})`. The checkpoint state is passed as parameters, not as a string blob. `types.ts:217-246` and `loader.ts`. This is mechanical.

### SC-13: Subagent result parse

- **Current code:** `index.ts:1683-1743`. Slash command parses a pasted string and updates checkpoint.
- **Mechanism:** Manual paste-and-parse.
- **Why it is social:** The harness is a regex parser over a string the user typed. No connection to a real sub-session.
- **Verdict:** Subscribe to `agent_end` (`types.ts:498-502`) on the sub-session; parse the actual session transcript. PEBKACOMP updates its own checkpoint store on receipt. `runner.ts:435-471` (generic emit for non-`tool_*` events) and `types.ts:498-502`. This is mechanical.

### SC-14: Pipeline as state machine

- **Current code:** `loop-orchestrator.ts:728-781` `SequentialPipeline`, wired into slash command at `index.ts:1744-1828`.
- **Mechanism:** In-process state machine that is only manipulated by the user typing `/harness-pipeline start|status|complete|block`.
- **Why it is social:** The pipeline is not running. It is a state object the user can mutate. The "stages" do not have any LLM call behind them; they are names.
- **Verdict:** Run the pipeline as actual subagent invocations. PEBKACOMP's pipeline implementation: each stage = a `ctx.sessionManager.spawnSubagent({...})` call with a stage-specific prompt. `agent_start` (`types.ts:493-496`) marks stage start; `agent_end` (`types.ts:498-502`) marks stage end. Persistence: PEBKACOMP writes to `.harness/checkpoints/pipeline.json`. This is mechanical.

## Summary

11 of 14 social-contract spots map to a real harness hook:

| SC-# | PEBKACOMP hook |
|------|----------------|
| SC-1 | `before_provider_request` outbound patch |
| SC-2 | drop + `tool_call` block + `tool_result` rewrite |
| SC-3 | `before_provider_request` patch into last user message |
| SC-4 | keep (already `tool_call`) |
| SC-5 | `tool_call` block next tool until evidence |
| SC-6 | `before_provider_request` patch with MUST-VERIFY |
| SC-7 | **drop from PEBKACOMP** (no mechanical enforcement) |
| SC-8 | `before_agent_start` + `tool_call` block |
| SC-9 | `tool_call` block on exhaustion |
| SC-10 | slash command + checkpoint store, no regex |
| SC-11 | `before_provider_request` outbound patch |
| SC-12 | `ctx.sessionManager.spawnSubagent(...)` |
| SC-13 | `agent_end` event subscription |
| SC-14 | `ctx.sessionManager.spawnSubagent` per stage |

Honest reason for the SC-7 drop: output rewriting before the LLM speaks is a
model task, not a hook task. There is no event that fires "the model is about
to emit X but hasn't yet." Post-hoc rewriting is the only option, and that
stays in PEBKAC.
