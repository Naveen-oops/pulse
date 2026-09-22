---
title: Session run sheet
description: What to say, what to click, and what to do when something breaks.
---

# Session run sheet

## Before you start

| Check | Command / URL |
| --- | --- |
| App is live | https://pulse-web.victoriouscliff-b6c1062a.centralindia.azurecontainerapps.io/r/CIT22A |
| Docs are live | https://pulse-docs.victoriouscliff-b6c1062a.centralindia.azurecontainerapps.io/docs/ |
| Votes cleared | `az containerapp exec -n pulse-poll-service -g rg-pulse-demo --command "python -m app.seed --reset"` |
| Presenter token | `9eda21a235b6c3b87b98bc878d526e75` |
| Close before sharing | `.env`, kubeconfig, personal tabs |

Open **`/present/CIT22A`** and project it. The QR on that screen is generated from
the page's own origin, so it is already correct — do not make one by hand.

## Opening (2 minutes)

> "Everyone take out your phone and scan this. No app, no login."
>
> *(wait for the first votes to land, then point at the chart)*
>
> "That is running in Azure right now. In about forty minutes we are going to add a
> whole new feature to it — live, with a coding agent — and you are going to use that
> feature from the same phone before you leave."

Then the honest framing, which is the actual point of the session:

> "The interesting part is not that the agent writes code. It is what I do *after* it
> writes code. That is the skill I want you to leave with."

## Beat 1 — Tour the app (10 min)

1. Vote from your own phone, on camera.
2. Try to vote twice — show the message: *"You have already voted in this poll."*
3. Open poll 2 from the presenter controls. Phones follow automatically.

Point worth making: that rule is enforced **twice** — a check for the friendly
message, and a `UNIQUE (poll_id, device_id)` constraint that is the real guard. Two
taps in the same millisecond beat the check but not the constraint.

## Beat 2 — Show the gap (3 min)

```bash
curl https://pulse-web.victoriouscliff-b6c1062a.centralindia.azurecontainerapps.io/api/qa/healthz
```

> "That is everything the Q&A service does. One endpoint. The Dockerfile, the CI job,
> the manifest and the ingress route all already exist — so the agent only has to write
> feature logic. That is deliberate, and it is most of why this works in fifteen minutes
> instead of failing in forty."

## Beat 3 — The live build (20 min)

```bash
git checkout -b feature/qa-upvotes
```

Prompt, verbatim:

```text
Implement docs/specs/qa-feature.md in packages/qa-service and packages/web.
Follow AGENTS.md. Add a test for every acceptance criterion.
Do not change deploy/ or .github/workflows/.
```

**Predict the gap out loud before the diff appears.** Say which rules you expect it to
skip — rule 3 (no self-upvote) and rule 6 (rate limit) are the usual ones. Then check.
Being wrong in public is as useful as being right.

While it runs, talk about `AGENTS.md` and why a written constraint beats a remembered one.

## Beat 4 — The review (10 min)

This is the segment the whole session exists for. Five checks:

1. Does every numbered rule have a test that **names** it?
2. Is each rule enforced where it cannot be bypassed — a constraint, not just an `if`?
3. Is anything here nobody asked for?
4. Was a gate silenced to go green? `grep -nE "noqa|eslint-disable|as any|skip"`
5. Can a non-developer read the error messages?

> "The tests are green. But the agent wrote the tests too. A rule it forgot is a rule
> with no test — and the suite is green, because nothing is checking."

## Beat 5 — Ship it

Merge, then let the pipeline be watched in silence for a moment. Then:

> "Scan the QR again and ask me anything."

## If something breaks

Say so openly — it is part of the lesson, and an engineering audience can tell the
difference between a rehearsed demo and someone who knows the tool.

| Problem | Do this |
| --- | --- |
| Agent stalls or drifts | `git reset --hard`, re-prompt with narrower scope |
| Agent misses a rule | *"Rule 6 has no test. Add the rate limit and a test for it."* |
| Out of time | Merge the prepared branch and review **that** diff instead |
| Votes look wrong | Reseed: `... --command "python -m app.seed --reset"` |
| Cloud app down | Fall back to local: `npm run dev`, then `npm run tunnel` |
| Phones cannot reach it | Scan from your own phone on camera; vote from a second browser |

## A true story worth telling

Getting this live hit four failures in a row, and the last one is a good teaching
moment. The API worked perfectly with `curl` but returned **426 Upgrade Required**
through nginx. Cause: **nginx proxies with HTTP/1.0 by default**, and Azure Container
Apps requires HTTP/1.1. One line fixed it:

```nginx
proxy_http_version 1.1;
```

Before that, a deploy silently ran the *old* image because the tag was `:latest` and
therefore cached — the exact mutable-tag trap written up on the CI page here.

Neither bug was a coding-agent failure. Both were infrastructure defaults behaving
exactly as documented, in a combination nobody had tried. That is still most of
engineering, and no agent removes it.
