---
title: Rules for your agent
description: AGENTS.md — why a written constraint beats a remembered one.
---

# Rules for your agent

Open `AGENTS.md` in the repo root. It is the first thing a coding agent should read, and
the highest-leverage file in the project.

```bash
cat AGENTS.md
```

## Why a file and not a prompt

You could type your constraints into the chat each time. You will not do it consistently,
and nothing carries between sessions, between tools, or between you and a colleague.

A file in the repo is:

- **Read by every agent** — Cursor, Claude Code and Copilot all pick up `AGENTS.md`
- **Version controlled** — the rules change through review, like code
- **Available to humans** — a new contributor reads the same thing
- **Re-read on every task**, so it does not fall out of a context window

:::info[Why this matters]
Agents are good at following explicit instructions and unreliable at inferring your
preferences from surrounding code.

If your codebase avoids WebSockets, an agent will not notice the absence. Absence is not
a signal. "Make the results update live" will get you WebSockets, because that is the
strongest convention in its training data, and it will look like good work.

Write the constraint down and it is followed. That is the whole mechanism.
:::

## What is in it

### The stack, stated plainly

```markdown
| Poll API | `packages/poll-service` | Python 3.12, FastAPI, SQLAlchemy 2, PostgreSQL |
| Web      | `packages/web`          | React 18, Vite 5, TypeScript (strict), plain CSS |
```

Without this, an agent guesses from what it sees and guesses inconsistently. One task
uses `requests`, the next uses `httpx`.

### The test command, per package

```markdown
cd packages/poll-service && python -m pytest
cd packages/web && npm test && npm run lint && npm run typecheck && npm run build
```

An agent that knows how to verify its own work usually will. An agent that does not know
will tell you it is done.

### Hard rules, numbered

```markdown
1. Never read, print, echo, or commit `.env`, `.env.*`, kubeconfig files, or anything
   under `secrets/`. This screen is recorded.
2. Do not change `deploy/` or `.github/workflows/` unless the task explicitly says to.
3. Do not add services, databases, or infrastructure. Stop and ask first.
4. Do not introduce WebSockets. Views refresh by polling every 2 seconds, on purpose.
5. Do not add a UI framework, CSS-in-JS, or a component library. Plain CSS only.
6. Do not weaken a quality gate to make it pass — no `# type: ignore`, `eslint-disable`,
   `# noqa`, `any`, or skipped tests.
7. Small commits, one logical change each.
```

Rules 1, 2 and 6 deserve a note each.

**Rule 1 is about the recording.** During a live session your editor is projected. An
agent that opens `.env` to "check the configuration" puts your credentials on a screen
and possibly on a video. `.cursorignore` blocks it mechanically as well — you want both,
because either can be forgotten.

**Rule 2 protects the demo.** The deploy pipeline is being shown live. An agent that
helpfully "improves" the CI workflow mid-build breaks the segment you are about to
present.

**Rule 6 is the one people forget to write down.**

:::warning[Agents will make your gates pass rather than make your code right]
Faced with a failing type check, an `eslint` error, or a stubborn test, the fastest route
to "done" is to silence the check. `# type: ignore` here, `as any` there, a `@pytest.mark.skip`
on the awkward one.

The work then looks finished. Tests are green, lint is clean, and a rule you thought you
had is gone. Nothing in the output tells you.

Writing rule 6 down converts this from something you must catch in review to something
the agent avoids in the first place. You should still search the diff for those tokens.
:::

## The instruction that matters most

At the bottom:

```markdown
## When you finish a task

State plainly: what you changed, which commands you ran, what passed, and anything you
skipped or could not verify. Do not report success for work you did not run.
```

The last sentence is doing real work. Without it you get confident summaries of unrun
tests — not dishonesty, just pattern completion: a task report *usually* ends with
success, so one gets written.

Ask for the distinction explicitly and you get it: "I ran the poll-service tests, 53
passed. I did not run the web tests." That is a report you can act on.

## Your own repos

Steal the shape:

1. **Stack** — languages, frameworks, versions, per directory
2. **Commands** — how to test, lint, build, run
3. **Hard rules** — numbered, specific, with the reason
4. **Conventions** — error shapes, naming, where things go
5. **Reporting** — say what you ran, and what you did not

Keep it under two pages. A long file is skimmed by humans and diluted for agents. Every
rule should be one you would actually enforce in review.

---

**[Write the spec →](/agentic/spec)**
