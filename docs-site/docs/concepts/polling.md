---
title: Why polling, not WebSockets
description: The decision people question most, and the reasoning behind it.
---

# Why polling, not WebSockets

Every live view in Pulse does the least fashionable thing possible. It asks again, every
two seconds:

```ts
// packages/web/src/hooks/usePolling.ts
const timer = window.setInterval(tick, intervalMs)
```

A real-time audience app that does not use WebSockets sounds like an oversight. It is
the opposite — it is the decision with the most thought behind it.

## What a WebSocket actually costs

The connection is the easy part. What you sign up for is everything after it drops:

- **Reconnect logic** with backoff, so a flaky network does not become a retry storm
- **State resync** on reconnect — you missed messages, and you must work out which
- **Heartbeats**, because a dead TCP connection can look alive for minutes
- **Sticky sessions or a shared bus**, the moment you run more than one replica
- **Proxy cooperation** — every hop must handle `Upgrade` correctly

Now compare a dropped poll request. It fails. Two seconds later another one goes out and
succeeds. There is no recovery path to write, because there is no state to recover.

:::info[Why this matters]
This is the actual trade being made: **polling converts a stateful problem into a
stateless one.**

A WebSocket is a long-lived, stateful thing that must be babysat. A poll is an
independent request that carries the whole answer. On hostile networks — venue wifi, a
phone dropping between cell towers, a laptop waking from sleep — the stateless version
degrades gracefully and the stateful one fails hard.
:::

## The numbers for this app

One room, say 200 people, each refreshing every 2 seconds:

```
200 viewers ÷ 2s = 100 requests/second
```

Each response is a JSON object of a few hundred bytes from a single indexed query. A
single FastAPI pod handles that without noticing.

Now suppose it did matter. The fixes are boring and available: cache results for one
second, or widen the interval to three. Neither requires new architecture.

## When this would be the wrong call

Be clear about the boundary — this is a judgement for *this* app, not a law:

| Polling is right when | Use WebSockets when |
| --- | --- |
| Updates are worth ~2s of staleness | Sub-100ms latency is the product |
| Every client wants the same data | Each client needs a different stream |
| Viewer counts are in the hundreds | Tens of thousands of concurrent viewers |
| Reliability beats elegance | You already run the infrastructure for it |

A collaborative text editor, a trading screen, a multiplayer game: sockets, obviously. A
poll chart in one conference room: polling, comfortably.

## The bit that is easy to miss

Polling made **the UI simpler**, not just the backend.

There is no connection state in the frontend. No "reconnecting…" banner, no stale-data
indicator, no message queue. `usePolling` is about forty lines and every component that
needs live data uses the same one:

```ts
const { data: room, error, loading } = usePolling(() => getRoom(code), 2000)
```

It is also trivially debuggable on stage. Open the network tab and every refresh is one
visible request with a visible response. Try explaining a WebSocket frame inspector to a
room of faculty in the ninety seconds you have.

:::warning[This is a hard rule in the repo]
`AGENTS.md` states: **do not introduce WebSockets.**

That rule exists because "use WebSockets for real-time" is such a strong convention that
an agent asked to "make the results update live" may well reach for them unprompted —
and produce something that looks more sophisticated and works less well.

A written constraint beats hoping the model shares your judgement.
:::

---

**[One vote per device →](/concepts/identity)**
