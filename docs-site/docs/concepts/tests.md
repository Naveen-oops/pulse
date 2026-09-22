---
title: Tests as the spec
description: How to write a test that still tells you something a year later.
---

# Tests as the spec

82 tests: 53 Python, 29 web. Not a large suite. But every one of them names a rule, and
that is what makes them useful when an agent hands you a diff.

## Read one

```python
# packages/poll-service/tests/test_voting.py
def test_second_vote_from_same_device_is_rejected(client, open_poll):
    """Spec: A second vote is rejected with a friendly message."""
    client.post(f"{API}/polls/{open_poll['id']}/votes",
                json={"option_index": 0, "device_id": "device-aaa"})

    second = client.post(f"{API}/polls/{open_poll['id']}/votes",
                         json={"option_index": 2, "device_id": "device-aaa"})

    assert second.status_code == 409
    assert second.json()["detail"] == "You have already voted in this poll."

    results = client.get(f"{API}/polls/{open_poll['id']}/results").json()
    assert results["total_votes"] == 1, "the rejected vote must not be counted"
```

Four things make that a good test:

**The name is a sentence.** `test_second_vote_from_same_device_is_rejected`. When CI goes
red you read the failure list and immediately know which *rule* broke. Compare
`test_vote_2` or `test_duplicate` — both require opening the file.

**The docstring quotes the spec.** You can trace this test back to the line in
`docs/specs/pulse-spec.md` that demanded it. Coverage of *requirements* is the thing you
care about, and this is how you see it.

**It asserts the message, not just the status.** `409` alone would pass even if the text
read `Integrity error on uq_vote_poll_device`. That string is shown to an audience, so it
is part of the contract.

**It checks the side effect did not happen.** The call was refused — fine. But *was the
vote counted anyway?* A rejection that still writes the row is a real bug, and only the
last assertion catches it.

:::info[Why this matters]
That fourth point is the one most often missing, in human and agent code alike.

It is natural to test that the wrong thing was *refused*. It is less natural to test that
the wrong thing did not *happen*. Those come apart precisely when there is a bug — an
exception raised after the commit, a rollback that did not fire, an error path that
returns 409 and persists anyway.

Assert the observable state, not only the response.
:::

## No coverage percentage

There is no coverage gate in this repo, deliberately.

A percentage is easy to raise without testing anything that matters — call every getter,
assert nothing meaningful, watch the number climb. It measures lines executed, not rules
verified.

The gate here is the checklist in `docs/quality.md`: **every acceptance criterion has a
test that names it.** That is harder to fake and answers the question you actually have.

## Tests must not need infrastructure

```python
# packages/poll-service/conftest.py
os.environ["PULSE_DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
```

Python tests run against in-memory SQLite. `npm test` needs no database, no Docker, no
network. The whole suite finishes in about four seconds.

That file sits at the *package root*, not in `tests/`, so it runs before any test module
is imported. This matters: if your local `.env` points at PostgreSQL, a test run could
otherwise connect to your real development database and drop its tables.

:::warning[A test that touches shared state is not a test]
It is a coin flip. It passes alone and fails in parallel, or passes on your machine and
fails in CI, and every hour spent on that is an hour not spent on the product.

No network. No real database. No `sleep`. If a test needs any of those to pass, the
design is the thing to fix.
:::

## Where the test data bit me

Writing these, two tests failed like this:

```
assert [0, 0, 0] == [1, 0, 0]
```

The vote never registered. The cause was not the app — `device_id` has `min_length=4`,
and I had used `"d1"`. The API correctly returned `422`, and my test ignored the status
code and only checked the counts.

The fix was two lines:

```diff
-        client.post(url, json={"option_index": option, "device_id": "d1"})
+        response = client.post(url, json={"option_index": option, "device_id": "device-01"})
+        assert response.status_code == 201, response.text
```

:::tip[Assert the status of every call, including setup calls]
A silent `422` in a setup step produces a failure message that points at the assertion
instead of the cause. I lost a few minutes to it; in a live demo that is the difference
between recovering and not.

Every request in a test gets its status asserted — even the ones just arranging state.
:::

## What to run

```bash
npm test          # everything
npm run test:py   # Python only
npm run test:web  # web only
npm run verify    # what CI runs: lint, types, tests, production build
```

---

**[Containers →](/kubernetes/containers)**
