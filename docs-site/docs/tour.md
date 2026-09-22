---
title: Tour the app
description: Vote from your phone, watch the chart move, and find the missing feature.
---

# Tour the app

Three screens. Open them side by side — the presenter view on your laptop, the audience
view on your phone. That is the actual demo setup.

## The audience view

```
http://localhost:5173/r/CIT22A
```

Mobile-first, no login, one open poll with big tap targets. Vote and the buttons are
replaced by a live chart with your own choice marked.

Now try to vote twice. You cannot — and the message you get is deliberate:

> You have already voted in this poll.

Not `409 Conflict`. Not "duplicate key violation". A sentence a person in row twelve can
read on a phone.

:::info[Why this matters]
Error messages in this app are a product surface, not a debugging aid. Every `detail`
string the API returns is written to be shown directly to a non-technical reader,
because that is exactly where it ends up.

When you review agent-written code later, check this. Agents reliably produce correct
status codes and reliably produce error text nobody would want to read on a projector.
:::

## The presenter view

```
http://localhost:5173/present/CIT22A
```

It asks for a presenter token — `demo-presenter-token`, from your `.env`. Then you get
the projector screen: a big QR code, the room code in large type, a live bar chart, and
controls to open each poll.

Vote on your phone and watch the laptop chart move within about two seconds.

Now open poll 2 from the presenter controls. **Your phone follows automatically** — it
notices the change on its next refresh and swaps to the new question. Nobody reloads
anything.

:::tip[A bug that only testing finds]
Originally, opening poll 2 left poll 1 open as well. The audience view renders *the*
open poll — meaning the first one it finds — so the room stayed stuck on poll 1 while
the presenter thought they had moved on. A dead end, mid-session, in front of everyone.

The spec said "shows the open poll", singular, but never stated the invariant: **a room
has exactly one open poll at a time.** Reading the spec would not catch it. Clicking the
button did.

It is now enforced in `update_poll` and covered by six tests in
`test_open_poll_switching.py`. This is the whole argument for running the thing you
built instead of only reading it.
:::

## The admin view

```
http://localhost:5173/admin
```

Create rooms, add polls, open and close them. Also needs the presenter token.

Try one thing: open your browser devtools, and send a `PATCH` without the token.

```bash
curl -X PATCH http://localhost:8001/api/polls/polls/2 \
  -H "Content-Type: application/json" \
  -d '{"is_open":true}'
```

```json
{"detail":"Presenter token required."}
```

401. The check is server-side, where it belongs — hiding the admin UI would protect
nothing.

## The shape of the code

```
packages/
  web/              React 18 + Vite + TypeScript — all three screens
  poll-service/     FastAPI — rooms, polls, votes, results    ← finished
  qa-service/       FastAPI — /healthz and nothing else       ← your target
  crew/             CrewAI session report
```

One directory per **independently deployable** thing. Each has its own dependencies,
Dockerfile, CI job and ingress route.

:::info[Why two API services and not one?]
Honestly? Partly to make the live build safe.

Because `qa-service` is already deployed and routed, adding the Q&A feature touches only
application code. No new Dockerfile, no new CI job, no new ingress rule, no new secret.
The riskiest ten minutes of a live demo simply do not happen.

It is also a truthful small-scale example of the real pattern: two deployables, one
database instance, a separate schema each, and **no service reading another's tables.**
When `qa-service` needs to know about a room, it goes over HTTP. That boundary is the
entire discipline — break it once and you have a distributed monolith.
:::

## Find the gap

```bash
curl http://localhost:8002/healthz
```

```json
{"status":"ok","service":"qa-service"}
```

That is everything `qa-service` does. Look at `packages/qa-service/app/main.py` — about
thirty lines, and a comment telling you not to fill it in early.

The spec for what goes there is already written:
**`docs/specs/qa-feature.md`** — eight acceptance criteria, the data model, the API
surface, and where the UI lands.

That file is what you will hand to your agent.

---

**[Why it is built this way →](/concepts/polling)**
