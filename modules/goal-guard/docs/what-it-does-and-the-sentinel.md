# Goal Guard — What It Does, How It Stops Drift, and the Reasoning‑Trace Sentinel

## In one line

Goal Guard is a **headless guardian** that watches another agent's run and keeps
it honest to its **original goal** — observing, correcting, or escalating
depending on how much you trust it. You never chat with it; you set a goal once
and it works in the background.

---

## Part 1 — What it does today

**1. Anchor the goal.** At the start of a run you give it the goal once. It's
written to disk (`.goalguard/anchor.json`) as the single source of truth. Models
forget; the anchor doesn't.

**2. Judge the run against that anchor.** At each checkpoint it gathers the
run's current state — git changes, recent commits, and a tail of the session
transcript — and asks a model: *is this still serving the original goal?* It gets
back a structured verdict: `aligned`, `severity` (none/minor/major), `evidence`,
and a concrete `correction`.

**3. Act only as far as you trust it (the trust ladder).**

| Level | Behavior |
|------:|----------|
| **L0 Shadow** | Logs the drift and the fix it *would* make. Changes nothing. |
| **L1 Suggest** | Surfaces the fix for you to apply. |
| **L2 Ask** | Proposes the fix, waits for your approval. |
| **L3 Auto‑correct** | Injects the fix and continues; pings you only if it can't recover. |

**4. Leave a visible trail.** Every check and every would‑be action lands on a
plain feed you can read (`goalguard feed`). That feed is how it earns promotion.

**Why this stops drift:** the worst failure in a long run is *losing the original
goal* — scope creep, an unrequested refactor, quietly abandoning the task. A
reactive hook can't catch that, because nothing *illegal* happened — the agent
just wandered. Goal Guard holds the goal still and measures every checkpoint
against it, so wandering gets named (and, when you allow it, reversed) instead of
shipped.

It is **model‑ and harness‑agnostic**: the judge model is one env var to swap
(Gemini / GLM / MiniMax / any OpenAI‑compatible), and each harness plugs in
through a thin adapter over the same core.

---

## Part 2 — The gap in reactive hooks (the problem you described)

A normal hook system is **reactive**: it fires when a tool call is *attempted* —
PreToolUse, PostToolUse, Stop. That leaves two blind spots:

1. **Thoughts don't fire hooks.** An agent can reason: *"Best practice says do X,
   and we're supposed to follow best practice… but I'll take the shortcut here."*
   That decision triggers nothing — it's just text in a thinking block. By the
   time the shortcut becomes an actual tool call, the agent may already be
   mid‑action, or the call may be shaped to slip past the specific patterns your
   hook watches for. The guardrail is always one step behind the intent.

2. **Agents can be untruthful.** *"I ran the tests and they pass"* — when the
   transcript shows no test ever ran. A reactive hook checks the *action*, not the
   *claim about the action*, so a confident false report sails through.

Both are failures of **intent and honesty**, and both happen *before or beside*
the action a hook can see.

---

## Part 3 — The Sentinel: catch intent in the reasoning, then trip the wire

This is the capability you sketched, and it follows directly from the existing
core. Goal Guard already *reads the transcript* to judge drift. Point that same
reading at the **reasoning/thinking stream** and give the judge two more
questions besides "is this on‑goal?":

- **Deception check:** do the agent's *claims* match the *evidence* in the
  transcript and the working tree? ("Says tests pass" vs. "no test run recorded"
  → flag.)
- **Pre‑action intent check:** is the agent, in its reasoning, *deciding to do
  something it shouldn't* — violate a stated best practice, skip a required step,
  touch an out‑of‑scope system — **before** that becomes a tool call?

When the Sentinel sees that intent forming in the thought box, it doesn't wait for
the rogue action. Depending on trust level it can:

- **Observe** — log "intent to bypass best‑practice X detected" (L0).
- **Correct** — inject *"You're about to skip X. Best practice requires it. Do X
  first."* back into the run before the shortcut executes (L3).
- **Trip the wire (active enforcement)** — and this is your key insight: the
  Sentinel itself **performs the action that fires the guardrail the reactive
  system would have missed.** If a thought reveals an about‑to‑happen violation
  that *should* have been gated by a hook, the Sentinel proactively invokes that
  gate — runs the check, calls the validating tool, or emits the event — so the
  hook fires **because the guardian tripped it at intent‑time**, not because the
  rogue agent politely waited to be caught at action‑time.

That flips enforcement from **reactive** to **shift‑left**: from "stop the bad
action after it starts" to "the bad action never gets a clean start, because the
guardian read the intent and engaged the guardrail first."

### Worked example (your scenario)

> Thinking block: *"Best practice is to write a migration and back up the table.
> But that's slow — I'll just `ALTER TABLE` directly and move on."*

- A reactive hook sees nothing — it's a thought.
- The Sentinel reads it, recognizes **intent to bypass the migration/backup
  policy**, and *before* the `ALTER TABLE` runs:
  - injects: *"Stop. Policy requires a migration + backup before schema changes.
    Create the migration and back up the table first."*, and/or
  - **actively triggers the migration‑guard hook** (runs the backup check / emits
    the gate event), so the protective machinery engages on the guardian's call —
    catching what the agent's own (unannounced) action would have slipped past.

### Deception example

> Claim: *"All 25 tests pass."*  Transcript/state: no test command was ever run.

The Sentinel cross‑checks claim against evidence, flags `untruthful`, and (per
level) blocks the "done" or pings you — instead of trusting a green checkmark
that was never earned.

---

## Honest status: built vs. roadmap

- **Built today:** the anchor → judge → trust‑ladder → feed core, transcript
  sampling, the model‑agnostic judge, and a coding agent **Stop‑hook** adapter
  (verified live catching a real drift and injecting a correction).
- **The Sentinel is a natural extension, not magic, and has two honest
  dependencies:**
  1. **It can only read reasoning the harness exposes.** If a harness writes the
     model's thinking to its transcript/log, the Sentinel sees it; if a harness
     hides reasoning, the Sentinel falls back to actions + claims only. Its power
     scales with how much of the thought stream it's allowed to read.
  2. **Intent‑time catching needs a mid‑run hook**, not just Stop — a PostToolUse
     / streaming adapter that checkpoints *during* the run, so it reads the
     thought before the action lands. The Stop hook gates the finish; the Sentinel
     wants to gate the moment. Same core, a second adapter.

The "active trip‑wire" (the guardian performing the call that fires the proper
hook) is the most powerful piece and the one to build deliberately — with the
trust ladder in front of it, so it starts in Shadow (just *tells* you what it
would have tripped) and only earns the authority to act once you've watched it be
right.
