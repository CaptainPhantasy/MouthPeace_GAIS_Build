# MouthPeace Process Monitor Webapp — Custom Report and Build Instructions

**Created:** 2026-05-20  
**Audience:** Douglas / harness implementation agents  
**Decision state:** Not approved for build yet. This document defines the exact build shape if you decide to proceed.  
**Primary post-read action:** Decide whether to build the MouthPeace Process Monitor webapp, then hand Phase 0 to an LLM orchestrator without requiring additional context.

---

## 1. Executive Summary

We should build a webapp version of the hardware desk companion concept, but not as a BLE or hardware feature. The useful part of that concept is the **small live state contract**:

```text
heartbeat snapshot -> current state -> recent entries -> waiting prompt -> optional response command
```

For the agent harness, that becomes:

```text
running harness instances
  -> local runtime heartbeat files
  -> monitor aggregator
  -> local HTTP + SSE server
  -> React dashboard
  -> optional guarded control actions
```

The result should be a local cockpit for harness work:

- which harness sessions are alive,
- which are actively thinking or running tools,
- which background bash/task jobs are still running,
- which prompts need attention,
- which heartbeats are stale,
- which MCP/system surfaces look degraded,
- which sessions are spending tokens or erroring,
- and what changed recently without opening every terminal.

The build should **not** use any temporary support files at the repo root that are not project inputs and must not become harness dependencies.

Recommended implementation: create a new package named `@mouthpeace/buddy-monitor` under `packages/monitor`, reuse the existing harness stats dashboard patterns, and wire the CLI command as `mouthpeace monitor`.

---

## 2. Source Context Used

| Source | What it contributed | Build implication |
|---|---|---|
| Hardware desk companion reference | Heartbeat snapshot fields, turn event shape, prompt decision idea, state machine. | Reuse concept, not BLE transport. |
| Harness `AGENTS.md` | Bun-first rules, no console logs in coding-agent TUI paths, no `ReturnType<>`, namespace node imports, `bun check` verification. | Implementation agents must follow harness repo rules. |
| Harness `packages/stats` | Existing local web dashboard, React/Tailwind/Chart.js client, `Bun.serve()` server, `mouthpeace stats` command shape. | Copy proven package pattern instead of inventing a new stack. |
| Harness `AgentEvent` and `AsyncJobManager` | Existing lifecycle and job state signals. | Heartbeat writer should consume existing events; avoid OS polling as primary truth. |
| BLEED front-end docs | CSS-first, Motion only for state-driven UI, avoid heavy dashboard animation, reduced-motion and performance gates. | V1 should use CSS transitions only; no GSAP/Rive/R3F/Spline/tldraw/React Flow. |
| Monorepo dependency graph | `pi-coding-agent` already depends on `buddy-stats`; stats depends on React/date-fns/lucide/chart stack. | Monitor can share exact existing dependencies and avoid new runtime dependency risk. |

---

## 3. Expected Result

After implementation, `mouthpeace monitor` should open a local browser dashboard at:

```text
http://127.0.0.1:3848
```

The dashboard should show:

1. **Command Center**
   - total live harness instances,
   - running turns,
   - waiting prompts,
   - degraded/stale processes,
   - active jobs,
   - tokens today,
   - error rate.

2. **Process Board**
   - one card per harness runtime instance,
   - status badge,
   - PID,
   - cwd/project,
   - session title/path,
   - active tool,
   - active background jobs,
   - last heartbeat age.

3. **Attention Lane**
   - pending `ask`, `resolve`, or permission-style decisions,
   - read-only by default,
   - guarded one-shot controls only when explicitly enabled.

4. **Jobs View**
   - active background bash/task jobs,
   - recent completed/failed/cancelled jobs,
   - labels and elapsed time,
   - stale job detection.

5. **Session Detail View**
   - recent turns,
   - model/provider,
   - tool timeline,
   - selected request details from existing stats where available.

6. **Health View**
   - heartbeat freshness,
   - crash/debug log pointers,
   - stats database freshness,
   - monitor server status,
   - dependency/config health.

7. **Settings / Safety View**
   - read-only mode indicator,
   - control plane disabled/enabled state,
   - bind address,
   - token status,
   - redaction policy.

Expected operator experience:

> Open one page and know whether the agent harness is idle, busy, waiting, stuck, or degraded without scanning terminals.

---

## 4. Architecture Recommendation

### 4.1 Recommended architecture

```text
Harness Runtime Instance
  - subscribes to AgentSession/Agent events
  - writes heartbeat to ~/.mouthpeace/agent/runtime/<instance-id>.json
  - marks shutting_down on clean exit

Runtime Heartbeat Directory
  - one JSON file per harness process
  - cheap local source of truth
  - stale threshold: 30 seconds

Monitor Aggregator
  - reads heartbeat files
  - reads existing stats database/session logs
  - computes snapshot and buddy state

Monitor Server
  - Bun.serve()
  - GET /api/v1/monitor/snapshot
  - GET /api/v1/monitor/events via SSE
  - local-only by default

React Webapp
  - Command Center
  - Process Board
  - Attention Lane
  - Jobs, Sessions, Health, Settings

Optional Control Plane
  - disabled by default
  - token + CSRF required
  - one-shot prompt decisions
```

### 4.2 Why heartbeat files are the correct source of truth

OS process polling can prove a PID exists. It cannot prove what the agent harness is doing.

The harness itself knows:

- the session ID,
- the active model,
- whether a turn is running,
- which tool is executing,
- whether background jobs exist,
- whether a prompt is waiting,
- and whether the session is intentionally shutting down.

So runtime heartbeats should be the primary signal. OS checks should only verify stale/orphaned heartbeats.

---

## 5. Architecture Options: Pros and Cons

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| New `packages/monitor` package | Clean boundary; avoids overloading stats; easier security model; can reuse stats patterns. | More new files; must wire new package export and CLI command. | Recommended. |
| Extend `packages/stats` | Fewer package files; existing server/client already present. | Mixes historical analytics with live process control; harder to secure controls separately. | Acceptable fallback, not preferred. |
| Poll OS processes only | Easy first demo; no runtime integration. | Cannot know agent state, prompts, jobs, or active tools reliably. | Reject as primary architecture. |
| Use hardware desk companion BLE protocol directly | Matches desk companion reference; hardware possible later. | Wrong transport for webapp; BLE adds pairing/security complexity. | Reject for webapp V1. |
| External SaaS telemetry backend | Centralized and scalable. | Privacy and operational overhead; unnecessary for local harness cockpit. | Defer. |

---

## 6. BLEED Front-End Guidance Applied

BLEED documents recommend a layered front-end policy:

1. CSS first.
2. Motion for React only when state-driven animation needs it.
3. GSAP only for directed timelines or scroll choreography.
4. Rive for interactive character animation.
5. R3F/Spline only for 3D that is central to product value.
6. Heavy visuals must be route-split, reduced-motion aware, and profiled.

For this exact dashboard:

| UI Need | Recommended implementation | Why |
|---|---|---|
| Status changes | CSS transitions on color, opacity, transform. | Cheap, no dependency. |
| Busy/attention pulse | CSS keyframes with reduced-motion override. | Good enough for cockpit state. |
| Buddy avatar | CSS/SVG state badge in V1. | Avoid Rive dependency until the behavior proves useful. |
| Charts | Reuse existing Chart.js from stats. | Already present in harness catalog. |
| Process board | Plain React components + CSS grid. | No need for React Flow; this is not a graph editor. |
| System map | Static grouped cards first. | Avoid tldraw/React Flow until users need direct manipulation. |
| Route transitions | None in V1. | Operational dashboard values clarity over flourish. |

Production dependency decision: **no new front-end dependency for V1**.

If a later version adds an animated character, use this decision tree:

| Candidate | Use if | Do not use if | Risk class |
|---|---|---|---|
| CSS/SVG | State icon and simple expression changes are enough. | Character needs runtime state machine animation. | Low |
| Motion for React | UI state transitions need declarative React animation. | Only simple hover/focus/pulse is needed. | Medium |
| Rive | Character animation becomes product-critical. | It is decorative only. | High |
| React Flow | Operators need editable workflow graphs. | We only show process cards. | High |
| R3F/Spline | 3D is central to a launch/demo surface. | This is a dense operational dashboard. | Critical |

---

## 7. Advanced Wireframes

### 7.1 Global shell

```text
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ MouthPeace Monitor                                      Local Only  Read-Only  12:04 │
│ 127.0.0.1:3848                                      Last snapshot: 1.2s ago         │
├───────────────┬──────────────────────────────────────────────────────────────────────┤
│ Nav           │ Page content                                                          │
│               │                                                                      │
│ Command       │                                                                      │
│ Processes     │                                                                      │
│ Attention     │                                                                      │
│ Jobs          │                                                                      │
│ Sessions      │                                                                      │
│ Health        │                                                                      │
│ Settings      │                                                                      │
│               │                                                                      │
│ Footer        │                                                                      │
│ - version     │                                                                      │
│ - bind addr   │                                                                      │
│ - controls    │                                                                      │
└───────────────┴──────────────────────────────────────────────────────────────────────┘
```

Required global elements:

| Element | Behavior | Verification |
|---|---|---|
| Local-only badge | Shows bind address and rejects non-loopback by default. | Server test asserts default host is `127.0.0.1`. |
| Read-only badge | Visible unless control plane enabled. | UI test verifies controls hidden/disabled by default. |
| Snapshot age | Updates from SSE or polling fallback. | SSE test emits initial snapshot and update. |
| Nav | Keyboard reachable, active page announced. | Browser/a11y check. |

### 7.2 Command Center page

```text
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ Buddy State: BUSY  [animated CSS status mark]       Message: 2 agents working         │
├──────────────┬──────────────┬──────────────┬──────────────┬──────────────┬───────────┤
│ Live         │ Running      │ Waiting      │ Degraded     │ Jobs         │ Tokens    │
│ 5            │ 2            │ 1            │ 0            │ 3            │ 31200     │
├────────────────────────────────────────────┬─────────────────────────────────────────┤
│ Process Board Preview                       │ Attention Lane                         │
│ ┌────────────────────────────────────────┐  │ ┌─────────────────────────────────────┐ │
│ │ Agent #a13  running  /the-harness-repo  │  │ │ waiting: resolve action            │ │
│ │ Tool: bash  00:01:22                   │  │ │ tool: edit                          │ │
│ │ Jobs: task/2, bash/4                   │  │ │ hint: pending action requires gate   │ │
│ └────────────────────────────────────────┘  │ └─────────────────────────────────────┘ │
│ ┌────────────────────────────────────────┐  │                                         │
│ │ Agent #b42  idle     /my-project        │  │ Recent alerts                         │
│ │ Last heartbeat: 2.1s                   │  │ - stale heartbeat cleared             │
│ └────────────────────────────────────────┘  │ - job failed in 34s                    │
├────────────────────────────────────────────┴─────────────────────────────────────────┤
│ Timeline: turn_start -> tool_execution_start -> job_update -> turn_end               │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### 7.3 Processes page

```text
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ Filters: [All] [Running] [Waiting] [Degraded] [This repo]       Search: ____________ │
├──────────────────────────────────────────────────────────────────────────────────────┤
│ Project Group: packages/the-harness-repo                                             │
│ ┌──────────────────────────────────────────────────────────────────────────────────┐ │
│ │ instance: agent-01J...      PID 88211        status running        heartbeat 1s  │ │
│ │ session: 01J...             model: <provider/model>               mode: none     │ │
│ │ active turn: 00:02:14       active tool: bash                     jobs: 2        │ │
│ │ latest: running package-local check                                                │ │
│ │ actions: [open session] [copy path] [view jobs] [signal disabled]                 │ │
│ └──────────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

Process card required fields:

| Field | Source | Redaction |
|---|---|---|
| `instanceId` | runtime heartbeat | display short prefix by default |
| `pid` | runtime heartbeat | visible locally |
| `cwd` | runtime heartbeat | shorten home path; keep repo path local only |
| `sessionPath` | runtime heartbeat | short path; full path on copy only |
| `status` | heartbeat + stale calculation | no redaction |
| `activeTool.hint` | runtime heartbeat | truncate and redact secrets |
| `jobs` | `AsyncJobManager` snapshot | label truncated |

### 7.4 Attention page

```text
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ Pending Attention                                                                    │
├──────────────────────────────────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────────────────────────────────────┐ │
│ │ kind: resolve               prompt id: prm_01J...              age: 00:00:09     │ │
│ │ session: /the-harness-repo                                                      │ │
│ │ tool: edit                                                                        │ │
│ │ hint: pending patch preview requires apply/discard                               │ │
│ │ controls: disabled in read-only mode                                             │ │
│ │ [Enable controls in Settings]                                                    │ │
│ └──────────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

Control rules:

- V1 may show prompts read-only.
- If controls are implemented, every decision must include:
  - local auth token,
  - CSRF token,
  - exact prompt ID,
  - allowed decision from prompt choices,
  - one-shot replay protection.

### 7.5 Jobs page

```text
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ Jobs                                                      [Running] [Recent] [Failed] │
├──────────────────────────────────────────────────────────────────────────────────────┤
│ Running                                                                              │
│ ┌────────────┬────────┬──────────┬──────────┬─────────────────────────────────────┐ │
│ │ Job ID     │ Type   │ Status   │ Elapsed  │ Label                               │ │
│ ├────────────┼────────┼──────────┼──────────┼─────────────────────────────────────┤ │
│ │ bash/4     │ bash   │ running  │ 00:02:13 │ bun --cwd packages/monitor check    │ │
│ │ task/2     │ task   │ running  │ 00:08:41 │ verifier reviewing server           │ │
│ └────────────┴────────┴──────────┴──────────┴─────────────────────────────────────┘ │
│ Recent                                                                               │
│ ┌────────────┬────────┬───────────┬──────────┬────────────────────────────────────┐ │
│ │ bash/3     │ bash   │ completed │ 00:00:44 │ aggregator tests                   │ │
│ │ bash/2     │ bash   │ failed    │ 00:00:11 │ DepLock audit                      │ │
│ └────────────┴────────┴───────────┴──────────┴────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### 7.6 Session detail page

```text
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ Session 01J...                                      status running     model opus... │
├──────────────────────────────────────────────────────────────────────────────────────┤
│ Summary                                                                              │
│ cwd: packages/the-harness-repo                                                       │
│ started: 2026-05-20T...        last event: 1.1s ago        tokens today: 31200       │
├────────────────────────────────────────────┬─────────────────────────────────────────┤
│ Turn Timeline                               │ Tool Timeline                          │
│ - 12:01 turn_start                          │ - bash start 12:02                     │
│ - 12:03 message_update                      │ - bash end 12:04 exit 0                │
│ - 12:04 turn_end                            │ - edit preview pending                 │
├────────────────────────────────────────────┴─────────────────────────────────────────┤
│ Recent transcript snippets, newest first, redacted and capped.                       │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### 7.7 Health page

```text
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ Health                                                                               │
├──────────────────────────────────────────────────────────────────────────────────────┤
│ Runtime Heartbeats                                                                   │
│ - fresh: 5                                                                           │
│ - stale: 0                                                                           │
│ - orphaned: 0                                                                        │
│                                                                                      │
│ Stats                                                                                │
│ - stats db exists: yes                                                               │
│ - last sync: 12s ago                                                                 │
│                                                                                      │
│ Logs                                                                                 │
│ - crash log present: no                                                              │
│ - recent server errors: 0                                                            │
│                                                                                      │
│ Config                                                                               │
│ - controls enabled: false                                                            │
│ - bind host: 127.0.0.1                                                               │
│ - redaction: strict                                                                  │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### 7.8 Settings / Safety page

```text
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ Settings / Safety                                                                    │
├──────────────────────────────────────────────────────────────────────────────────────┤
│ Server                                                                               │
│ [x] Bind to loopback only                                                            │
│ Host: 127.0.0.1                                                                      │
│ Port: 3848                                                                           │
│                                                                                      │
│ Control Plane                                                                        │
│ [x] Read-only mode                                                                   │
│ [ ] Enable prompt decisions                                                          │
│ [ ] Enable process signals                                                           │
│                                                                                      │
│ Redaction                                                                            │
│ [x] Shorten home paths                                                               │
│ [x] Truncate tool hints                                                              │
│ [x] Drop env values                                                                  │
│ [x] Drop full prompt bodies from snapshots                                           │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 8. API Contract

### 8.1 Snapshot endpoint

```http
GET /api/v1/monitor/snapshot
```

Response:

```ts
interface MonitorSnapshot {
  schemaVersion: 1;
  total: number;
  running: number;
  waiting: number;
  degraded: number;
  msg: string;
  entries: string[];
  tokens: number;
  tokensToday: number;
  buddyState: "sleep" | "idle" | "busy" | "attention" | "celebrate" | "dizzy" | "heart";
  sessions: SessionSummary[];
  jobs: JobSummary[];
  prompts: PendingPrompt[];
  alerts: MonitorAlert[];
  updatedAt: number;
}
```

### 8.2 Events endpoint

```http
GET /api/v1/monitor/events
```

SSE events:

```ts
type MonitorEvent =
  | { type: "snapshot"; data: MonitorSnapshot }
  | { type: "heartbeat"; instanceId: string; data: RuntimeHeartbeat }
  | { type: "stale"; instanceId: string }
  | { type: "prompt"; prompt: PendingPrompt }
  | { type: "job_update"; job: JobSummary };
```

Rules:

- First SSE message must be a full `snapshot`.
- Follow-up messages may be deltas.
- Client must fall back to polling `snapshot` every 5 seconds if SSE fails.
- Server sends keepalive comments every 10 seconds.

### 8.3 Health endpoint

```http
GET /api/v1/monitor/health
```

Response:

```ts
interface MonitorHealth {
  status: "healthy" | "degraded" | "down";
  runtimeDirReadable: boolean;
  heartbeatCount: number;
  staleHeartbeatCount: number;
  statsDbReadable: boolean;
  controlsEnabled: boolean;
  bindHost: string;
  updatedAt: number;
}
```

### 8.4 Prompt decision endpoint

Disabled by default.

```http
POST /api/v1/monitor/prompts/:id/decision
```

Request:

```ts
interface PromptDecisionRequest {
  decision: "once" | "deny" | "apply" | "discard";
  csrfToken: string;
}
```

Response:

```ts
interface PromptDecisionResponse {
  ok: true;
  promptId: string;
  appliedAt: number;
}
```

Error shape:

```ts
interface MonitorErrorResponse {
  error: {
    code: string;
    message: string;
    details?: Record<string, unknown>;
    requestId: string;
  };
}
```

No endpoint may return `200 OK` with an error body.

---

## 9. Runtime Heartbeat Contract

Create runtime files under:

```text
~/.mouthpeace/agent/runtime/<instance-id>.json
```

Heartbeat shape:

```ts
interface RuntimeHeartbeat {
  schemaVersion: 1;
  instanceId: string;
  pid: number;
  ppid: number;
  cwd: string;
  sessionId: string;
  sessionPath?: string;
  terminalId?: string;
  startedAt: number;
  updatedAt: number;
  status: "idle" | "running" | "waiting" | "degraded" | "shutting_down";
  mode?: string;
  model?: string;
  activeTurn?: {
    startedAt: number;
    latestText?: string;
  };
  activeTool?: {
    id: string;
    name: string;
    startedAt: number;
    hint?: string;
  };
  jobs: Array<{
    id: string;
    type: "bash" | "task";
    status: "running" | "completed" | "failed" | "cancelled";
    label: string;
    startTime: number;
  }>;
  pendingPrompt?: {
    id: string;
    kind: "permission" | "ask" | "resolve";
    tool?: string;
    hint?: string;
    createdAt: number;
    choices: string[];
  };
  counters: {
    turns: number;
    toolCalls: number;
    errors: number;
    outputTokens: number;
  };
}
```

Write rules:

- Use atomic write: write temp file, then rename.
- Do not write every token delta. Coalesce updates to at most 2 Hz unless state changes.
- Always write immediately on status transitions.
- Mark `shutting_down` on clean exit.
- Aggregator marks stale when `Date.now() - updatedAt > 30_000`.

---

## 10. New Path Creation Plan

All paths are relative to the repo root.

Create exactly this new package root:

```text
packages/monitor/
```

Do not create any of these accidental nests:

```text
packages/stats/packages/monitor/
packages/coding-agent/packages/monitor/
packages/monitor/packages/monitor/
```

Required new files:

```text
packages/monitor/package.json
packages/monitor/CHANGELOG.md
packages/monitor/README.md
packages/monitor/build.ts
packages/monitor/tsconfig.json
packages/monitor/tsconfig.client.json
packages/monitor/tsconfig.publish.json
packages/monitor/tailwind.config.js
packages/monitor/scripts/generate-client-bundle.ts
packages/monitor/src/index.ts
packages/monitor/src/types.ts
packages/monitor/src/aggregator.ts
packages/monitor/src/server.ts
packages/monitor/src/security.ts
packages/monitor/src/runtime/heartbeat-reader.ts
packages/monitor/src/runtime/heartbeat-writer.ts
packages/monitor/src/embedded-client.generated.txt
packages/monitor/src/client/index.tsx
packages/monitor/src/client/App.tsx
packages/monitor/src/client/api.ts
packages/monitor/src/client/types.ts
packages/monitor/src/client/useMonitorEvents.ts
packages/monitor/src/client/useSystemTheme.ts
packages/monitor/src/client/styles.css
packages/monitor/src/client/components/Header.tsx
packages/monitor/src/client/components/CommandCenter.tsx
packages/monitor/src/client/components/ProcessBoard.tsx
packages/monitor/src/client/components/ProcessCard.tsx
packages/monitor/src/client/components/AttentionLane.tsx
packages/monitor/src/client/components/JobsTable.tsx
packages/monitor/src/client/components/SessionDetail.tsx
packages/monitor/src/client/components/HealthPanel.tsx
packages/monitor/src/client/components/SettingsPanel.tsx
packages/monitor/test/aggregator.test.ts
packages/monitor/test/heartbeat-reader.test.ts
packages/monitor/test/server.test.ts
packages/monitor/test/security.test.ts
```

Required edits:

```text
packages/coding-agent/src/cli.ts
packages/coding-agent/src/commands/monitor.ts
packages/coding-agent/src/cli/monitor-cli.ts
packages/coding-agent/src/session/agent-session.ts
packages/coding-agent/src/async/job-manager.ts
package.json
```

Root `package.json` edit should only add the internal catalog entry if needed:

```json
"@mouthpeace/buddy-monitor": "14.2.1"
```

No external dependency should be added for V1.

---

## 11. Scaffold Instructions To Prevent Unwanted Nesting

Implementation agents must follow this scaffold protocol exactly:

1. Set working directory to the repo root.

2. Verify the repo root contains:

   ```text
   package.json
   packages/stats/package.json
   packages/coding-agent/package.json
   AGENTS.md
   ```

3. Create `packages/monitor` directly under repo root.

4. Before writing any monitor file, verify:

   ```text
   packages/monitor/package.json does not already exist
   packages/stats/packages does not exist
   packages/coding-agent/packages does not exist
   ```

5. Copy structural patterns from `packages/stats`, but do not copy stats-specific names into exported APIs.

6. Use namespace imports for `node:fs`, `node:path`, and `node:os`.

7. Do not use `console.log`, `console.error`, or `console.warn` in coding-agent TUI/runtime code. CLI command files may follow existing CLI patterns, but monitor package server/runtime should use the centralized logger where diagnostics are needed.

8. Do not introduce `private`, `protected`, or `public` class keywords except constructor parameter properties already allowed by repo rules.

9. Do not use `ReturnType<>`.

10. Do not use dynamic imports for types.

11. Do not add prompts as inline strings. This feature should not require model prompts.

---

## 12. DepLock Instructions

Current system facts:

| Item | Current value / rule |
|---|---|
| Package manager | `bun@1.3.12` from root `package.json` |
| Minimum runtime | Bun `>=1.3.7` from package engines pattern |
| Workspaces | `packages/*` |
| Existing UI deps | React, React DOM, Chart.js, react-chartjs-2, lucide-react, Tailwind, PostCSS, date-fns |
| New external deps for V1 | None |
| Temporary PDF deps | Explicitly out of scope; do not import or reference |

DepLock policy:

1. **No caret or tilde in newly added dependency versions.**
2. Prefer `catalog:` for dependencies already present in the root catalog.
3. If a new dependency becomes unavoidable, add it to the root catalog with an exact version only.
4. Do not normalize existing catalog ranges as part of this feature. That is a separate dependency cleanup.
5. Do not run `npm install`. This repo uses Bun.
6. Do not add `motion`, `gsap`, `rive`, `tldraw`, `@xyflow/react`, `three`, or Spline packages in V1.
7. `bun.lock` must change only if a real dependency change is made.

Suggested V1 monitor package dependencies:

```json
{
  "dependencies": {
    "@mouthpeace/pi-utils": "catalog:",
    "@mouthpeace/buddy-stats": "catalog:",
    "@tailwindcss/node": "catalog:",
    "chart.js": "catalog:",
    "date-fns": "catalog:",
    "lucide-react": "catalog:",
    "react": "catalog:",
    "react-chartjs-2": "catalog:",
    "react-dom": "catalog:"
  },
  "devDependencies": {
    "@types/bun": "catalog:",
    "@types/react": "catalog:",
    "@types/react-dom": "catalog:",
    "postcss": "catalog:",
    "tailwindcss": "catalog:"
  }
}
```

DepLock verification gate:

```text
Reject the phase if any newly added package manifest line contains a dependency version beginning with ^ or ~.
Reject the phase if package-lock.json appears anywhere in the harness repo diff.
Reject the phase if any temporary root-level package.json or package-lock.json is referenced.
```

---

## 13. Phased Build Plan

### Phase 0 — Orchestrator preflight and file-lock map

**Model tier:** strongest.  
**Branch:** `feature/buddy-monitor-preflight`.  
**Dependencies:** none.  
**Primary owner:** LLM orchestrator.

Tasks:

1. Read repo rules.
2. Confirm git branch, dirty files, remote, and GitHub CLI availability.
3. Record that existing untracked files are user work and must not be reverted.
4. Create a file-lock map for all paths in this report.
5. Decide whether implementation uses one branch or PR-per-phase.
6. Confirm no dependency install is needed for V1.

Verification:

```text
bun --cwd packages/stats run check
bun --cwd packages/coding-agent run check
```

Exit criteria:

- lock map exists in orchestration notes,
- no files modified except orchestration notes if used,
- dependency policy confirmed.

### Phase 1 — Contract and package scaffold

**Model tier:** strongest for types; default for scaffold.  
**Branch:** `feature/buddy-monitor-contract`.  
**Depends on:** Phase 0.

Tasks:

1. Create `packages/monitor` at repo root only.
2. Add package metadata mirroring stats package conventions.
3. Add `src/types.ts` with public contracts:
   - `RuntimeHeartbeat`,
   - `MonitorSnapshot`,
   - `MonitorEvent`,
   - `MonitorHealth`,
   - `PendingPrompt`,
   - `MonitorErrorResponse`.
4. Add `src/index.ts` exports.
5. Add tsconfig/build files based on stats package.
6. Add package-local tests for type/shape invariants where useful.

Verification:

```text
bun --cwd packages/monitor run check
```

Exit criteria:

- monitor package typechecks,
- no CLI integration yet,
- no external deps added,
- no accidental nested package paths.

### Phase 2 — Runtime heartbeat writer and reader

**Model tier:** strongest.  
**Branch:** `feature/buddy-monitor-runtime-heartbeats`.  
**Depends on:** Phase 1.

Tasks:

1. Implement heartbeat writer.
2. Implement heartbeat reader.
3. Add runtime directory helper. Prefer adding a utility path helper if repo convention supports it; otherwise keep monitor-local path derivation isolated.
4. Integrate writer with `AgentSession` lifecycle events.
5. Add async job snapshot capture using existing `getAsyncJobSnapshot()` or minimal event hooks.
6. Coalesce update frequency to avoid write storms.
7. Mark `shutting_down` on clean exit.
8. Add tests for:
   - atomic write behavior,
   - stale threshold calculation,
   - redaction/truncation,
   - no per-token write storm.

Verification:

```text
bun --cwd packages/monitor run check
bun --cwd packages/coding-agent run check
```

Exit criteria:

- heartbeat files can be generated from fixture/session events,
- coding-agent still typechecks,
- runtime writes do not block agent turns.

### Phase 3 — Aggregator and state derivation

**Model tier:** strongest.  
**Branch:** `feature/buddy-monitor-aggregator`.  
**Depends on:** Phase 2.

Tasks:

1. Implement aggregator reading heartbeat directory.
2. Merge existing stats package totals where safe:
   - tokens,
   - tokens today,
   - error rate,
   - recent requests/errors.
3. Compute `buddyState`:
   - `sleep`: no fresh heartbeats,
   - `idle`: fresh but no running/waiting,
   - `busy`: active turn/tool/job,
   - `attention`: pending prompt,
   - `dizzy`: stale/degraded/error cluster,
   - `celebrate`: completed all-clear threshold,
   - `heart`: fast prompt resolution or recovery event.
4. Add alert generation.
5. Add fixtures for fresh, busy, waiting, stale, and degraded states.

Verification:

```text
bun --cwd packages/monitor run check
bun --cwd packages/monitor test/aggregator.test.ts
```

Exit criteria:

- all buddy states are derivable from fixtures,
- stale heartbeats never appear as healthy,
- aggregator tolerates malformed heartbeat files without crashing the server.

### Phase 4 — HTTP/SSE server and security surface

**Model tier:** strongest.  
**Branch:** `feature/buddy-monitor-server`.  
**Depends on:** Phase 3.

Tasks:

1. Implement `Bun.serve()` server.
2. Add endpoints:
   - `GET /api/v1/monitor/snapshot`,
   - `GET /api/v1/monitor/events`,
   - `GET /api/v1/monitor/health`.
3. Add standard error shape.
4. Bind to `127.0.0.1` by default.
5. Add CORS only as needed for local served client.
6. Add token/CSRF scaffolding but keep controls disabled.
7. Add SSE keepalive and polling fallback contract.
8. Add tests for:
   - initial SSE snapshot,
   - health response,
   - 404 and 500 error shape,
   - loopback default,
   - controls disabled.

Verification:

```text
bun --cwd packages/monitor run check
bun --cwd packages/monitor test/server.test.ts
bun --cwd packages/monitor test/security.test.ts
```

Exit criteria:

- server returns snapshot and health from fixtures,
- SSE emits initial snapshot,
- no control endpoint can mutate state by default.

### Phase 5 — CLI command integration

**Model tier:** default.  
**Branch:** `feature/buddy-monitor-cli`.  
**Depends on:** Phase 4.

Tasks:

1. Add `packages/coding-agent/src/commands/monitor.ts`.
2. Add `packages/coding-agent/src/cli/monitor-cli.ts`.
3. Register `monitor` in CLI command registry.
4. Implement flags:
   - `--port`, default `3848`,
   - `--host`, default `127.0.0.1`,
   - `--json`, output one snapshot and exit,
   - `--summary`, console summary and exit,
   - `--no-open`, do not open browser,
   - `--allow-controls`, explicit opt-in.
5. Lazy import `@mouthpeace/buddy-monitor` like stats lazy-imports `@mouthpeace/buddy-stats`.
6. Update root package catalog with `@mouthpeace/buddy-monitor` exact internal version only if needed.

Verification:

```text
bun --cwd packages/coding-agent run check
bun packages/coding-agent/src/cli.ts monitor --help
bun packages/coding-agent/src/cli.ts monitor --summary
```

Exit criteria:

- `mouthpeace monitor --help` renders,
- `--summary` exits,
- default web mode starts local server,
- no new external dependencies.

### Phase 6 — React dashboard V1

**Model tier:** default for components; strongest for state architecture review.  
**Branch:** `feature/buddy-monitor-dashboard`.  
**Depends on:** Phase 4; can run partly in parallel with Phase 5 using fixture API.

Tasks:

1. Build client shell.
2. Implement pages:
   - Command Center,
   - Processes,
   - Attention,
   - Jobs,
   - Sessions,
   - Health,
   - Settings.
3. Implement `useMonitorEvents()` SSE hook with polling fallback.
4. Add CSS-first status animations.
5. Add reduced-motion CSS.
6. Route heavy charts only where useful; do not add new visualization dependencies.
7. Add accessible table/card markup.
8. Use truncation and redaction for paths/tool hints.

Verification:

```text
bun --cwd packages/monitor run check
bun --cwd packages/monitor run build
```

Manual browser verification:

```text
Start fixture-backed monitor server.
Open dashboard.
Verify busy, attention, degraded, and idle states render correctly.
Verify keyboard navigation reaches nav, filters, cards, and modal close buttons.
Verify reduced-motion mode disables pulse/transition loops.
```

Exit criteria:

- all pages render from fixture snapshot,
- UI remains useful at 1280px and mobile width,
- no continuous animation loop except cheap CSS state indicator,
- reduced motion works.

### Phase 7 — Optional prompt control plane

**Model tier:** strongest.  
**Branch:** `feature/buddy-monitor-controls`.  
**Depends on:** Phases 4, 5, 6.

Tasks:

1. Keep controls disabled unless `--allow-controls` and config agree.
2. Create local token file under `~/.mouthpeace/monitor/token` if controls enabled.
3. Add CSRF token to served page.
4. Implement prompt decision endpoint only for explicitly supported prompt types.
5. Add one-shot replay prevention.
6. Add audit event for every accepted or rejected control action.
7. Do not implement process kill in this phase unless explicitly approved.

Verification:

```text
bun --cwd packages/monitor test/security.test.ts
bun --cwd packages/coding-agent run check
```

Exit criteria:

- invalid token rejected,
- missing CSRF rejected,
- prompt ID mismatch rejected,
- replay rejected,
- controls remain absent in default read-only mode.

### Phase 8 — Final hardening and release readiness

**Model tier:** strongest verifier.  
**Branch:** `feature/buddy-monitor-hardening`.  
**Depends on:** all prior phases.

Tasks:

1. Run package checks.
2. Run package-local tests.
3. Run targeted browser verification.
4. Review dependency diff.
5. Review security posture.
6. Review performance and reduced-motion behavior.
7. Update package README/CHANGELOG.
8. Prepare PR description with evidence.

Verification:

```text
bun --cwd packages/monitor run check
bun --cwd packages/coding-agent run check
bun run check:ts
```

Exit criteria:

- all verification commands pass,
- completion matrix has evidence for every phase,
- no TODO/stub/no-op implementation remains,
- no accidental dependency drift,
- no local-only sensitive data in committed files.

---

## 14. Multi-Agent Execution Contract

### 14.1 Orchestrator contract

The orchestrator owns sequence, file locks, dependency gates, and completion registration.

Rules:

1. Never assign two workers to the same file path.
2. Never mark a phase complete from worker claims alone.
3. Only verifier evidence can close a phase.
4. If a verifier finds drift, reopen the phase and assign a repair worker.
5. If a phase needs new dependency, stop and run DepLock approval before install.
6. Keep implementation under the repo root only.
7. Treat existing untracked files as user work.
8. Never revert, stash, delete, or overwrite files outside the phase lock map.

### 14.2 Worker contract

A worker owns implementation inside one phase.

Rules:

1. Read `AGENTS.md` before editing.
2. Edit only assigned files.
3. Use existing project patterns from stats/coding-agent.
4. Do not invent parallel conventions.
5. Add tests for behavior, not plumbing.
6. Do not add mocks when real fixture paths can test behavior.
7. Do not suppress tests or weaken checks.
8. Return exact files changed and verification evidence.

### 14.3 Verifier contract

The verifier owns completion proof.

Rules:

1. Re-read the phase brief and changed files.
2. Run specified verification commands.
3. Add at least one negative-path check for each new server/control behavior.
4. Confirm DepLock if package manifests changed.
5. Confirm no accidental nesting.
6. Confirm reduced-motion and accessibility gates for UI phases.
7. Reject completion if evidence is stale or from a narrower command than specified.
8. Write a concise verdict: PASS, PASS WITH NOTES, or FAIL.

---

## 15. Deterministic Build Prompt

Use this prompt to start the implementation orchestration.

```text
You are the LLM orchestrator for the MouthPeace Process Monitor webapp build.

Repository root: the repo root (see AGENTS.md for canonical path).

Decision:
Build a new harness package at packages/monitor named @mouthpeace/buddy-monitor. Do not modify any temporary root-level package files unrelated to the project.

Non-negotiable rules:
1. Read AGENTS.md before any edit.
2. Treat existing untracked files as user work. Do not revert, stash, delete, or overwrite them.
3. Create packages/monitor directly under repo root. Do not nest it under packages/stats, packages/coding-agent, or another packages directory.
4. Add no external dependency for V1. Reuse existing catalog dependencies only.
5. DepLock: any newly added dependency version must be exact or catalog:. No new ^ or ~ versions. Reject package-lock.json changes.
6. Bind the monitor server to 127.0.0.1 by default.
7. Implement read-only dashboard first. Prompt/control endpoints must be disabled by default.
8. Use CSS-first UI motion only; no Motion, GSAP, Rive, R3F, Spline, React Flow, or tldraw dependency in V1.
9. Use harness runtime heartbeats as source of truth; do not use OS process polling as primary state.
10. No phase can be marked complete until a verifier runs the phase verification commands and records evidence.

Target command:
mouthpeace monitor

Default URL:
http://127.0.0.1:3848

Planned phases:
0. Preflight and file-lock map.
1. Contract and package scaffold.
2. Runtime heartbeat writer and reader.
3. Aggregator and buddy-state derivation.
4. HTTP/SSE server and security surface.
5. CLI command integration.
6. React dashboard V1.
7. Optional prompt control plane.
8. Final hardening and release readiness.

For each phase:
- assign one worker with a self-contained phase brief,
- lock files before work begins,
- require worker to report changed files and commands run,
- assign a verifier after worker completion,
- only register phase complete when verifier returns PASS with evidence.

If any phase discovers a required dependency not already in the repo catalog, stop implementation and run a DepLock decision gate before continuing.

Begin with Phase 0 only.
```

### 15.1 Worker prompt template

```text
You are an LLM worker implementing Phase <N>: <name> of the MouthPeace Process Monitor webapp.

Repo root: the repo root (see AGENTS.md for canonical path).

You may edit only these files:
<locked file list>

You must read:
- AGENTS.md
- this phase brief
- existing package patterns in packages/stats when relevant
- existing coding-agent command patterns when relevant

Scope:
<phase scope>

Do not:
- modify any temporary root-level package or lockfiles unrelated to the project,
- add external dependencies,
- create nested packages,
- implement controls unless this phase explicitly allows it,
- change unrelated behavior,
- mark completion yourself.

Required verification before handing off:
<commands>

Return:
1. Files changed.
2. Behavior implemented.
3. Tests added/updated.
4. Verification commands and observed result.
5. Any risks or follow-up needed inside this same phase.
```

### 15.2 Verifier prompt template

```text
You are the LLM verifier for Phase <N>: <name> of the MouthPeace Process Monitor webapp.

Repo root: the repo root (see AGENTS.md for canonical path).

Verify only this phase, but check for cross-phase drift.

Inputs:
- phase brief,
- worker report,
- changed files,
- required verification commands.

You must:
1. Re-read changed files.
2. Confirm edits are limited to locked paths.
3. Confirm no accidental nested package was created.
4. Confirm no external dependency was added unless the phase explicitly approved it.
5. Confirm no new ^ or ~ dependency versions were introduced.
6. Run the required verification commands.
7. For UI phases, check reduced-motion and keyboard accessibility requirements.
8. For server/control phases, check error shapes, auth defaults, loopback binding, and negative paths.
9. Return PASS only if every exit criterion is met with observed evidence.

Output exactly:
- Verdict: PASS | PASS WITH NOTES | FAIL
- Evidence:
- Defects:
- Required fixes before registration:
```

---

## 16. Risk Analysis

| Risk | Probability | Impact | Mitigation | Residual risk |
|---|---:|---:|---|---:|
| Sensitive prompt/tool data leaks to dashboard | Medium | High | Snapshot redaction, truncate tool hints, no full prompt bodies, loopback default. | Medium |
| Heartbeat write storm slows agent | Medium | Medium | Coalesce to 2 Hz; immediate writes only on transitions. | Low |
| Stale heartbeat shown as live | Medium | High | 30s stale threshold; health view flags stale/orphaned; PID verification optional. | Low |
| Control endpoint misused | Low in V1 | High | Read-only default; token + CSRF + one-shot decisions; process signals deferred. | Medium if controls enabled |
| Dashboard becomes animation-heavy | Medium | Medium | CSS-only V1; reduced-motion; no heavy visual deps. | Low |
| New package drifts from stats conventions | Medium | Medium | Copy stats package structure; package-local checks. | Low |
| CLI integration breaks default launch routing | Low | High | Add explicit command registry entry; run CLI help/summary checks. | Low |
| Dependency drift via casual install | Medium | Medium | DepLock gate; no external deps; reject package-lock changes. | Low |
| Tests assert implementation details | Medium | Medium | Contract tests only: snapshot shape, stale behavior, SSE initial event, auth rejection. | Low |
| Agent overwrites user untracked work | Low | High | File-lock map; no revert/stash/delete; verifier checks changed files. | Low |

---

## 17. Four-Pass Simulation and impact_simulate Log

`impact_simulate` was run against the planned operation groups using the repo root as the resolved project root so relative paths remained stable. Import/test/git deep checks were not enabled inside `impact_simulate` because the project-level simulation timed out when full checks were requested; the plan compensates with explicit package verification commands in every phase.

| Pass | Operation group | impact_simulate result | Interpretation | Plan adjustment |
|---|---|---|---|---|
| 1 | Package scaffold + CLI registration | Overall risk: low; 2 new files, 1 modified file. | Base package creation is low risk if paths are correct. | Add strict anti-nesting scaffold protocol. |
| 2 | Runtime heartbeat writer/reader + session/job integration | Overall risk: low; 2 new files, 2 modified files. | Runtime integration touches load-bearing session/job code. Tool classified low because it does not know semantic blast radius. | Assign strongest model and require coding-agent check. |
| 3 | Aggregator/server/security/tests | Overall risk: medium; 5 new files. | Server/API surface has medium product/security risk. | Add negative-path tests and error-shape requirements. |
| 4 | UI pages/components/styles | Overall risk: high; 7 new UI files. | UI scope can sprawl and drift. | Split UI into explicit pages, CSS-only motion, reduced-motion gate. |

Manual simulation conclusions:

1. The highest risk is not package creation; it is semantic integration with live agent state.
2. Controls must remain disabled until read-only monitoring is proven.
3. UI must not import heavy animation/flow libraries in V1.
4. Verification must be phase-local and repo-level at hardening.

Confidence after mitigations: **[INFERENCE] 95%+ plan success likelihood** if the orchestrator enforces phase gates and does not skip verifier evidence.

---

## 18. Completion Matrix

| Phase | Deliverable | Required evidence | Completion owner | Status |
|---|---|---|---|---|
| 0 | Preflight and file-lock map | Git/gh status recorded; dependency policy confirmed; no code changes. | Verifier | Planned |
| 1 | Monitor package scaffold and shared types | `bun --cwd packages/monitor run check` passes. | Verifier | Planned |
| 2 | Heartbeat writer/reader integrated with runtime | Monitor and coding-agent checks pass; heartbeat fixtures pass. | Verifier | Planned |
| 3 | Aggregator and buddy-state derivation | Aggregator tests cover fresh, busy, waiting, stale, degraded. | Verifier | Planned |
| 4 | Local HTTP/SSE server | Server/security tests pass; loopback default verified. | Verifier | Planned |
| 5 | `mouthpeace monitor` CLI command | CLI help/summary observed; coding-agent check passes. | Verifier | Planned |
| 6 | Dashboard V1 | Monitor build/check pass; browser verification covers main states. | Verifier | Planned |
| 7 | Optional prompt controls | Security negative tests pass; default read-only remains enforced. | Verifier | Deferred until explicitly approved |
| 8 | Hardening and release readiness | `bun run check:ts` plus package-local evidence; dependency diff clean. | Verifier | Planned |

---

## 19. Completion Registration Rules

A phase may be registered complete only when all of these are true:

1. Worker changed only assigned files.
2. Verifier re-read changed files.
3. Required commands were run after the final edit.
4. Evidence is copied into the phase record.
5. DepLock passed if package manifests changed.
6. No accidental nested paths exist.
7. No TODO/stub/no-op implementation remains.
8. No unrelated user work was modified.
9. UI phases include reduced-motion and keyboard checks.
10. Server/control phases include negative-path security checks.

A phase must be rejected when:

- a test was skipped to pass,
- a dependency was added without DepLock,
- a control endpoint mutates state in read-only mode,
- a heartbeat can be stale but displayed as healthy,
- a worker claims completion without verifier evidence,
- or the implementation drifts from this report's contracts.

---

## 20. Final Recommendation

Build this, but as a **boring local observability surface first**.

Do not start with animated pets, 3D, external telemetry, or remote control. Start with reliable truth:

```text
Who is running?
What are they doing?
Who is waiting?
What is stale?
What failed?
What needs attention?
```

Once that is correct, a richer Buddy-style visual layer can be added safely. The first version should be useful at 3 AM with animations disabled, controls off, and only local data visible.
