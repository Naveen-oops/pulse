---
title: Build it live
description: Hand the spec to an agent, then keep your hands on the wheel.
---

# Build it live

Everything up to here was preparation. The repo is fenced, the spec is written, the
target service is already deployed and routed. Now the agent does the typing.

Budget: **fifteen minutes of agent time.** If it runs much longer, something in the setup
was wrong, not the model.

## Start from a branch

```bash
git checkout -b feature/qa-upvotes
```

Always a branch. You want the diff reviewable, the merge deliberate, and an easy exit if
the build wanders.

## The prompt

That is genuinely all of it:

```text
Implement docs/specs/qa-feature.md in packages/qa-service and packages/web.
Follow AGENTS.md. Add a test for every acceptance criterion.
Do not change deploy/ or .github/workflows/.
```

Three sentences, because the work was done earlier:

- **"Implement `docs/specs/qa-feature.md`"** — the requirements live in a file, not in
  this message. The agent can re-read it; it cannot re-read your chat reliably.
- **"Follow `AGENTS.md`"** — stack, test commands and hard rules, by reference.
- **"A test for every acceptance criterion"** — this is the line that makes review
  possible. Eight numbered rules should produce at least eight tests, and a missing test
  is a missing rule.
- **"Do not change `deploy/` or CI"** — repeated from `AGENTS.md` because it protects the
  next segment of the talk.

:::info[Why the prompt is short]
A long prompt is a symptom. Everything you would cram into it belongs somewhere
re-readable: requirements in the spec, constraints in `AGENTS.md`, conventions in the
code the agent can see.

Context in a chat message is the least durable place to put it. It falls out of the
window, it is invisible to your colleague, and it is gone next session.
:::

## Use plan mode first

If your tool has one — Claude Code's plan mode, Cursor's plan step — use it. You get the
intended approach before any file is written.

What to check in the plan, in about twenty seconds:

- Is it touching **only** `packages/qa-service` and `packages/web`?
- Is it adding a **migration or a new table** in the right schema?
- Is it planning to **reuse** `api.ts`, `usePolling.ts`, `device.ts`?
- Is it inventing anything you did not ask for?

Catching "I will add a Redis cache for question counts" in the plan costs nothing.
Catching it in the diff costs the segment.

## While it runs

Do not sit in silence — this is the part of the session with the most to say. Good things
to talk through:

- What you fenced off in `AGENTS.md`, and why each rule exists
- That `qa-service` was already deployed, and why that removes the risky ten minutes
- Which two rules you expect it to skip, **before** the diff appears

That last one is a strong move. Predict the gap out loud, then check. Whether you are
right or wrong, the audience learns something about where these tools are weak.

## Then stop and read the diff

```bash
git --no-pager diff --stat
git --no-pager diff
```

:::warning[This is the moment the whole session is built around]
It is very tempting to see green tests, say "and it works", and move on. Do not.

The tests passing tells you the tests pass. It does not tell you the rules are enforced,
because **the agent wrote the tests too.** A rule with no test is a rule that is silently
absent, and the suite will be perfectly green.

The [review checklist](/agentic/review) is the next page, and it is the most useful thing
here.
:::

## When it is right

```bash
npm run verify
git add -A && git commit -m "qa-service: questions with upvotes and moderation"
git push -u origin feature/qa-upvotes
gh pr create --fill     # or open the PR in the browser
```

Merge, and then say nothing for a moment and let the pipeline be watched: Actions builds,
pushes to GHCR, commits the new image tag, ArgoCD notices, the pod rolls.

Then the line the whole thing exists for:

> "Scan the QR code and ask me anything."

The audience uses the feature that did not exist when they sat down.

## When it goes wrong

It sometimes will. Have the exits ready and take them early.

| What happened | What to do |
| --- | --- |
| Missed a rule | `"Rule 6 has no test. Add the rate limit and a test for it."` |
| Touched `deploy/` | `git checkout -- deploy/` and say why the rule exists |
| Wandered badly | `git reset --hard` and re-prompt with a narrower scope |
| Out of time | Merge the prepared `demo/qa-done` branch and review *that* diff |

:::tip[A failure you narrate is better than a success you rush]
If the agent stalls or produces something wrong, say so plainly and show what you would
do about it. That is the actual skill you are teaching, and an audience of engineers can
tell the difference between a rehearsed demo and someone who knows the tool.

The fallback branch exists so that you can be relaxed about this. Having an exit is what
lets you take the risk at all.
:::

---

**[Review what it wrote →](/agentic/review)**
