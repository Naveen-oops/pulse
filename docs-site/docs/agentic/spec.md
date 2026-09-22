---
title: Write the spec
description: The difference between a prompt that works and one that wanders.
---

# Write the spec

Open the spec you are about to hand over:

```bash
cat docs/specs/qa-feature.md
```

This is the input to the live build. Its quality decides almost everything about the
output — more than the model, more than the tool.

## A prompt is not a spec

Here is the same request, twice.

**A prompt:**

> Add a Q&A feature where people can ask questions and upvote them.

You will get *something*. It will run. It will be missing the rate limit, allow
self-upvoting, have no moderation, and store questions in a way that makes the export
endpoint awkward later. None of that is the agent being bad — you did not say.

**A spec:**

| # | Rule |
| --- | --- |
| 1 | Question text is 5 to 280 characters. Shorter, longer or empty is rejected with a message. |
| 2 | One upvote per device per question. A second upvote is ignored, not counted. |
| 3 | A device cannot upvote its own question. |
| 4 | Hidden questions disappear from both the audience and presenter views. |
| 5 | Only the presenter token can hide a question or mark it answered. |
| 6 | At most 5 questions per device per minute. The 6th is rejected with a message. |
| 7 | `GET /rooms/{code}/questions/export` returns every question with votes and status. |
| 8 | Questions are returned sorted by votes descending, then newest first. |

Eight numbered, checkable statements. Each one can be true or false about a diff, and
each one can be a test.

:::info[Why this matters]
The numbering is not decoration. It gives you and the agent a shared address space.

"Rule 6 has no test" is unambiguous and immediately actionable. "The rate limiting seems
incomplete" starts a conversation.

It also makes review tractable. You are not judging whether the code is *good* — an
unbounded question. You are checking eight specific claims, which is a task you can
finish and know you finished.
:::

## Say where things go

```markdown
| Part | Location |
| --- | --- |
| Question and upvote logic, export | `packages/qa-service` |
| "Ask" tab on audience page | `packages/web` |
| Ranked question panel beside the poll chart | `packages/web` |
```

Without this, an agent decides. It might add the API to `poll-service` because that is
where the existing endpoints are — reasonable, and it breaks the service boundary you
built the whole demo around.

## Say what to reuse

```markdown
Reuse what exists: all HTTP goes through `src/api.ts`, polling through
`src/hooks/usePolling.ts`, device identity through `src/device.ts`. Plain CSS in
`src/styles.css` — no UI framework.
```

This is the highest-value paragraph in the file.

Left alone, agents write new code. They will produce a second polling hook, a second
fetch wrapper, a second way to get a device id — each individually fine, and collectively
the thing that makes a codebase unmaintainable.

Naming the existing utilities converts "write this feature" into "wire these pieces
together", which is both smaller and better.

## Say what is out of scope

```markdown
## Out of scope

Editing or deleting a question · threading and replies · profanity filtering ·
notifications · the AI "Group questions" stretch.
```

Scope creep from an agent is usually helpfulness. You asked for questions and upvotes; it
notices you would obviously want editing too. Now the diff is twice the size and you are
reviewing features you did not ask for at a moment when you have fifteen minutes.

An explicit non-goals list is cheap and stops it.

## Say what the errors should say

```markdown
- "Your question needs to be at least 5 characters."
- "Questions are limited to 280 characters."
- "You are posting too quickly — try again in a moment."
- "You cannot upvote your own question."
```

These strings appear on a projector in front of an audience. Specify them and you get
them. Leave them out and you get `{"detail": "Validation error"}`, which is correct and
useless.

## Where the spec comes from

In the live session, this file is written **on stage**, in a brainstorm with the room,
minutes before the build. That is the demo: a conversation becomes a document becomes
working software.

The version in the repo exists so rehearsals have something real to run against. Either
way the shape is the same:

1. **User stories** — who wants what, and why
2. **Numbered acceptance criteria** — checkable, one rule each
3. **Data model** — entities and their fields
4. **API surface** — method, path, auth, which rules apply
5. **Where it lands** — exact directories
6. **What to reuse** — the existing utilities by name
7. **Out of scope** — the non-goals
8. **Error messages** — the exact strings

:::tip[The test is whether someone else could implement it]
Before handing a spec to an agent, ask: could a competent developer who has never seen
this project build the right thing from this document alone?

If yes, an agent probably can too. If no, the gaps are exactly where the agent will
improvise — and improvisation is what you are trying to avoid.
:::

---

**[Build it live →](/agentic/live-build)**
