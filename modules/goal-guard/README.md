# Goal Guard — Quickstart

A **headless guardian** that keeps your LLM/agent runs locked to their original
goal. You never chat with it. You set a goal once; at checkpoints it judges the
run against that goal and — depending on how much you trust it — observes,
suggests, asks, or auto-corrects, pinging you only when it can't recover.

It's **model-agnostic** (swap the judge between Gemini / GLM / MiniMax / any
OpenAI-compatible model with one env var) and **harness-agnostic** (a small core
plus thin adapters). Default trust level is **L0 = Shadow: it changes nothing.**

---

## 1. Install (once)

```bash
cd modules/goal-guard     # from the repository root
pip install -e .          # gives you the `goalguard` command
```

## 2. Give it a judge model (this is the API-key step)

The judge defaults to **Gemini**. Point it at a key:

```bash
export GOOGLE_API_KEY=<your Gemini key>     # default judge (gemini-2.5-flash)
```

Prefer your own subscriptions? One env var swaps the judge — no code change:

```bash
# Z.AI GLM (coding-plan quota):
export GUARD_LLM_PROVIDER=glm   ZAI_API_KEY=<key>
# MiniMax:
export GUARD_LLM_PROVIDER=minimax   MINIMAX_API_KEY=<key>
```

> Even **Shadow mode needs the judge** — that's how it detects drift. It just
> never *acts* on what it finds at L0.

## 3. Use it on a real project (Shadow first)

```bash
cd /path/to/your/project

# Anchor the goal for this run:
goalguard set "Add a CSV export button to the reports page"

# Confirm you're at L0 (shadow — changes nothing):
goalguard level 0

# Run a checkpoint whenever you want a drift read
# (--activity = what the run is doing now; --transcript = a log/transcript file):
goalguard checkpoint --activity "Refactoring the auth system instead"

# Read what it caught — this is the visible feed:
goalguard feed
```

Example feed entry it produces:

```text
👁️  observe  [major]
    why: Rewriting auth is unrelated to adding a CSV export button.
    fix: Stop the auth refactor and return to the CSV export button.
```

At L0 that `fix` is only *logged* — nothing is changed. Watch the feed across a
few real runs; when it's consistently right, promote it.

## 4. Climb the trust ladder when it's earned it

| Level | `goalguard level N` | What it does |
|------:|---------------------|--------------|
| **L0** | `goalguard level 0` | **Shadow** — logs the drift + the fix it *would* make. No changes. |
| **L1** | `goalguard level 1` | **Suggest** — surfaces the fix for you to apply. |
| **L2** | `goalguard level 2` | **Ask** — proposes the fix, waits for your approval. |
| **L3** | `goalguard level 3` | **Auto-correct** — applies the fix and continues; pings you only if it can't recover after `GUARD_MAX_RECOVERIES` (default 2). |

Demote anytime (`goalguard level 0`). Remove entirely: delete the `.goalguard/`
folder and the hook — no other trace.

## 5. Wire it into Claude Code

Two adapters — use either or both. Add them to `.claude/settings.json` using
the absolute path to your checkout:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command",
        "command": "python3 /absolute/path/to/modules/goal-guard/adapters/claude_code/goalguard_stop_hook.py" } ] }
    ],
    "PreToolUse": [
      { "hooks": [ { "type": "command",
        "command": "python3 /absolute/path/to/modules/goal-guard/adapters/claude_code/goalguard_pretooluse_hook.py" } ] }
    ],
    "PostToolUse": [
      { "hooks": [ { "type": "command",
        "command": "python3 /absolute/path/to/modules/goal-guard/adapters/claude_code/goalguard_posttooluse_hook.py" } ] }
    ]
  }
}
```

Then `goalguard set "<goal>"` in the project.

- **PreToolUse hook (Sentinel, pre-execution)** — judges the *pending* tool call
  before it runs and, by level, **denies it (L3), asks you to approve (L2)**, or
  allows + logs (L0/L1). This is the hard gate: a dangerous/off-goal call never
  executes.
- **PostToolUse hook (Sentinel)** — checks *during* the run, right after each tool
  call, for **drift**, **deception** (claims the evidence doesn't support), and
  **intent-to-violate**. At L3 it injects a correction before the next step. At
  L2 it records the proposed correction without feeding it back automatically;
  only PreToolUse can present the operator approval prompt.
- **Stop hook** — gates the *end* of a run: at L2/L3 it blocks the stop and feeds
  a correction back so the run realigns instead of ending drifted (the `/goal`
  pattern). Checks goal drift.

The PreToolUse and PostToolUse adapters throttle to *mutating* tools by default
(override `GUARD_SENTINEL_TOOLS`). All three adapters **fail open** — if the
guard errors, your run is never blocked. Other harnesses can use the same core
through their own thin adapters.

## 6. Optional: the ping

At L3, when it can't recover it escalates. By default that's a feed entry; add a
real notification:

```bash
export GUARD_NOTIFY_CMD='curl -s -d "$GUARD_MESSAGE" ntfy.sh/your-topic'   # any command
export GUARD_MACOS_NOTIFY=1                                                 # macOS banner
```

## Commands

```text
goalguard set "<goal>"        anchor the goal for this run
goalguard checkpoint [...]    run one drift check (prints JSON)
goalguard sentinel [...]      run one sentinel check: drift + deception + intent

goalguard feed [--limit N]    show recent activity (the visible artifact)
goalguard level [0-3]         get/set the trust level
goalguard status              goal, level, recovery state
goalguard reset               clear the anchor
```

## Config (env)

| Var | Default | Purpose |
|-----|---------|---------|
| `GOOGLE_API_KEY` | — | Gemini judge key (default provider) |
| `GUARD_LLM_PROVIDER` | `gemini` | `gemini` \| `glm` \| `minimax` \| `custom` |
| `GUARD_LLM_MODEL` | per provider | override judge model |
| `GUARD_LEVEL` | `0` | trust level (env overrides config) |
| `GUARD_MAX_RECOVERIES` | `2` | auto-correct attempts before escalating |
| `GUARD_SENTINEL_TOOLS` | mutating tools | comma-separated allowlist of tools the PostToolUse Sentinel judges |
| `GUARD_NOTIFY_CMD` | — | shell command for the ping (`$GUARD_MESSAGE` set) |
| `GUARD_MACOS_NOTIFY` | — | `1` to show a macOS banner on escalation |
