---
title: One vote per device
description: No login, a rule enforced twice, and a trust boundary we chose not to defend.
---

# One vote per device

There is no login anywhere in Pulse. An audience member has about ninety seconds of
patience and zero interest in an account.

So identity is a random string in the browser:

```ts
// packages/web/src/device.ts
export function getDeviceId(): string {
  const existing = localStorage.getItem(DEVICE_KEY)
  if (existing) return existing
  const created = `device-${randomId()}`
  localStorage.setItem(DEVICE_KEY, created)
  return created
}
```

The API enforces one vote per `device_id` per poll. That is the whole scheme.

## It is weak on purpose

Clear your site data and you get another vote. Open a private window and you get
another. Use a second phone and you get another.

**We know. That is the trade.**

:::info[Why this matters]
This is a *trust boundary we chose not to defend*, and being able to say that sentence
clearly is the point.

The alternatives all cost more than the problem is worth:

| Defence | What it costs |
| --- | --- |
| Email login | Nobody votes. The feature dies. |
| IP address | A whole venue behind one NAT gets one vote between them. |
| Device fingerprinting | Privacy-hostile, and still defeatable. |
| CAPTCHA | Adds friction everywhere to stop a problem nobody has. |

The threat here is one attendee voting twice to nudge a bar chart in a room where the
result changes nothing. The correct amount of engineering to spend on that is *a random
string in localStorage*.

Being deliberate about this is different from being naive about it. Naive is not
thinking about it. Deliberate is knowing exactly what you are exposed to, and having
decided the exposure is cheaper than the defence.
:::

## The rule is enforced twice

Look carefully at how a vote is handled:

```python
# packages/poll-service/app/main.py
already_voted = db.scalar(
    select(Vote).where(Vote.poll_id == poll.id, Vote.device_id == payload.device_id)
)
if already_voted is not None:
    raise HTTPException(status_code=409, detail="You have already voted in this poll.")

db.add(Vote(...))
try:
    db.commit()
except IntegrityError:
    # Two taps racing each other: the unique constraint is the real guard.
    db.rollback()
    raise HTTPException(status_code=409, detail="You have already voted in this poll.") from None
```

Two guards, doing different jobs:

1. **The `if` check** produces the friendly message in the normal case.
2. **The database constraint** is what actually makes the rule true.

```python
# packages/poll-service/app/models.py
__table_args__ = (UniqueConstraint("poll_id", "device_id", name="uq_vote_poll_device"),)
```

:::warning[The check alone is a bug]
Two taps arriving in the same millisecond both run the `SELECT`, both find nothing, and
both proceed to insert. The `if` cannot stop that — there is a window between reading
and writing, and no amount of application code closes it.

The unique constraint closes it, because the database serialises the write. The second
insert raises `IntegrityError`, which we catch and turn into the same friendly 409.

This is the single most useful thing to check in agent-written code. Agents produce the
`if` reliably. They add the constraint far less often, and the resulting bug **never
shows up in a demo** — it shows up in production, rarely, and is miserable to reproduce.
:::

## The rule you can state

Anything enforced by a business rule should **also** be enforced by a database
constraint wherever one can express it.

The application check is for the human-readable message. The constraint is for the
truth. If you only get one, take the constraint.

## Presenter actions are different

Voting is anonymous. Opening a poll, hiding a question, marking one answered — those
need the token:

```python
def require_presenter(x_presenter_token: str = Header(default="")) -> None:
    if x_presenter_token != settings.presenter_token:
        raise HTTPException(status_code=401, detail="Presenter token required.")
```

A shared secret in a header. Also not sophisticated — and also right-sized, because the
only person who needs it is the one running the room, and it is checked server-side
where it cannot be bypassed by hiding a button.

---

**[Relative paths →](/concepts/relative-paths)**
