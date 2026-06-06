# Harness Hook Surface — Verified from Source

All claims here come from
`packages/coding-agent/src/extensibility/extensions/`
read directly from the harness source. Citations are file:line.

## Event union

`types.ts:799-825` defines `ExtensionEvent`:

```
export type ExtensionEvent =
  | ResourcesDiscoverEvent
  | SessionEvent           // session_start, session_before_switch, session_switch,
  |                        // session_before_branch, session_branch,
  |                        // session_before_compact, session.compacting, session_compact,
  |                        // session_shutdown, session_before_tree, session_tree
  | ContextEvent
  | BeforeProviderRequestEvent
  | BeforeAgentStartEvent
  | AgentStartEvent
  | AgentEndEvent
  | TurnStartEvent
  | TurnEndEvent
  | MessageStartEvent
  | MessageUpdateEvent
  | MessageEndEvent
  | ToolExecutionStartEvent
  | ToolExecutionUpdateEvent
  | ToolExecutionEndEvent
  | AutoCompactionStartEvent
  | AutoCompactionEndEvent
  | AutoRetryStartEvent
  | AutoRetryEndEvent
  | TtsrTriggeredEvent
  | TodoReminderEvent
  | UserBashEvent
  | UserPythonEvent
  | InputEvent
  | ToolCallEvent          // BLOCK-capable
  | ToolResultEvent;       // MODIFY-capable
```

## What each event can return

Verified against the runner implementation.

### Block-capable

| Event | Result type | Code | Source |
|-------|-------------|------|--------|
| `tool_call` | `{block: true, reason: string}` short-circuits the loop | `emitToolCall` | `runner.ts:521-554` |
| `user_bash` | `{block, reason, transformedInput}` | `emitUserBash` | `runner.ts:556-594` |
| `user_python` | `{block, reason, transformedInput}` | `emitUserPython` | `runner.ts:556-594` |
| `session_before_switch` | `{cancel: true}` | `emit()` | `runner.ts:435-471` (SessionBeforeEvent branch) |
| `session_before_branch` | `{cancel: true}` | `emit()` | `runner.ts:435-471` |
| `session_before_compact` | `{cancel: true}` | `emit()` | `runner.ts:435-471` |
| `session_before_tree` | `{cancel: true}` | `emit()` | `runner.ts:435-471` |
| `input` | `{handled: true}` short-circuits the user input | `emitInput` | `runner.ts:645-675` |

### Modify-capable

| Event | Result type | Code | Source |
|-------|-------------|------|--------|
| `tool_result` | `{content, details, isError}` — content/details/isError are individually settable | `emitToolResult` | `runner.ts:473-519` |
| `before_provider_request` | `unknown` — full payload replacement | `emitBeforeProviderRequest` | `runner.ts:728-760` |
| `before_agent_start` | `{systemPrompt?, message?}` — modifies system prompt and/or injects a message | `emitBeforeAgentStart` | `runner.ts:762-817` |
| `context` | `{messages?: AgentMessage[]}` — replaces the messages sent to the LLM | `emitContext` | `runner.ts:677-726` |
| `input` | `{text, images}` — rewrites user input before LLM | `emitInput` | `runner.ts:645-675` |
| `user_bash` / `user_python` | `{transformedInput}` — rewrites before execution | `runner.ts:556-594` | `runner.ts:556-594` |
| `session.compacting` | `{...}` — customizes compaction prompt | `emit()` | `runner.ts:454-456` |

### Notify-only

`session_start`, `session_compact`, `session_shutdown`, `session_switch`,
`session_branch`, `session_tree`, `turn_start`, `turn_end`, `agent_start`,
`agent_end`, `message_start`, `message_update`, `message_end`,
`tool_execution_start`, `tool_execution_update`, `tool_execution_end`,
`auto_compaction_start`, `auto_compaction_end`, `auto_retry_start`,
`auto_retry_end`, `ttsr_triggered`, `todo_reminder`, `resources_discover`.

These have no result field. They can call `ctx.ui.notify`, write to disk,
append audit, etc., but cannot block the agent loop.

## `ExtensionContext` actions extensions can call

`types.ts:217-246`:

```
interface ExtensionContext {
  ui: ExtensionUIContext;          // notify, setStatus, setWidget, etc.
  cwd: string;
  sessionManager: SessionManager;  // .newSession, .branch, .switchSession, .compact
  modelRegistry: ModelRegistry;
  get model(): Model | undefined;
  getContextUsage(): ContextUsage | undefined;
  compact(options?): Promise<void>;
  hasUI(): boolean;
  isIdle(): boolean;
  abort(): void;
  hasPendingMessages(): boolean;
  shutdown(): void;
  getSystemPrompt(): string;
}
```

`ExtensionCommandContext` (`types.ts:252-279`) extends with
`waitForIdle`, `newSession`, `branch`, `navigateTree`, `switchSession`,
`reload`, `compact`. Used only inside slash-command handlers.

The exact shape of `SessionManager` (whether it has `spawnSubagent`) needs a
follow-up read of `SessionManager`'s type. If `spawnSubagent` does not exist
on the harness type, SC-12 and SC-14 fall back to `ctx.sessionManager.newSession()`
with a structured prompt — same idea, slightly different wiring.

## Existing example extensions

`packages/coding-agent/examples/extensions/` contains harness-authored reference
extensions. PEBKACOMP will be modeled on those patterns, not invented.

## How the runner dispatches an extension's hook

`runner.ts:435-471` — for the generic `emit()` path (session/turn/agent events):

```
for (const ext of this.extensions) {
  const handlers = ext.handlers.get(event.type);
  for (const handler of handlers) {
    const handlerResult = await handler(event, ctx);
    if (this.#isSessionBeforeEvent(event) && handlerResult) {
      result = handlerResult;
      if (result.cancel) return result;
    }
  }
}
return result;
```

All registered extensions see the event in registration order. Each handler
can read state and return a result. The runner short-circuits only on
`cancel: true` for `session_before_*` events.

`runner.ts:521-554` — for `tool_call`:

```
for (const ext of this.extensions) {
  for (const handler of ext.handlers.get("tool_call")) {
    const handlerResult = await handler(event, ctx);
    if (handlerResult) {
      result = handlerResult;
      if (result.block) return result;   // short-circuit
    }
  }
}
```

The first extension to return `{block: true}` wins. Order matters: PEBKACOMP
must register before PEBKAC if it should win on collisions. PEBKAC currently
already returns `{block, reason}`; PEBKACOMP can either replace PEBKAC's
handlers for the events it owns or run alongside.

## Implications for PEBKACOMP

- PEBKACOMP is a normal harness extension: `(pi: ExtensionAPI) => void`.
- It can register handlers for any event in `ExtensionEvent`.
- It can return mechanical results for any block/modify event.
- It cannot enforce behavior that requires predicting model output (SC-7).
- It can call `ctx.sessionManager.*` to actually create sub-sessions.
- It runs in registration order with PEBKAC; PEBKACOMP must register first to
  win on `tool_call` short-circuits.
