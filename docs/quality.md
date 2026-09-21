# Quality standards

What "done" means here, and what enforces it. [`AGENTS.md`](../AGENTS.md) is the short
version that coding agents read; this is the reasoning behind it.

## The bar

A change is done when **all** of these are true:

- [ ] Every acceptance criterion in the spec has a test naming it.
- [ ] Tests for every package you touched pass locally.
- [ ] `ruff check` and `ruff format --check` pass (Python).
- [ ] `npm run lint`, `npm run typecheck`, `npm run build` pass (web).
- [ ] No gate was weakened to get there — no `noqa`, `eslint-disable`, `type: ignore`,
      `any`, or skipped test.
- [ ] `.env`, kubeconfig and secrets were never read, printed, or committed.

## Gates

| Gate | Tool | Runs where |
| --- | --- | --- |
| Python lint + import order | `ruff check` | local, CI |
| Python formatting | `ruff format --check` | local, CI |
| Python tests | `pytest` | local, CI |
| TS type checking | `tsc --noEmit` (strict) | local, CI |
| JS/TS lint | `eslint --max-warnings 0` | local, CI |
| Web tests | `vitest run` | local, CI |
| Production build | `vite build` | local, CI |

`--max-warnings 0` is deliberate: a warning nobody fixes is a rule nobody has.

### Strictness worth calling out

`packages/web/tsconfig.json` enables `noUncheckedIndexedAccess`. Indexing an array gives
you `T | undefined`, so `results.counts[i]` must be handled:

```ts
const count = results.counts[index] ?? 0   // yes
const count = results.counts[index]!       // no — that is the bug you are about to ship
```

This caught a real class of bug in the chart: a poll whose options were edited after
voting had counts shorter than its option list.

## How to write a test here

One acceptance criterion per test. The name is a sentence; the docstring quotes the spec.

```python
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

What makes it good:

- **The name states the rule**, so a failure report reads as a sentence.
- **It asserts the message**, not just `409` — the audience reads that string.
- **It checks the side effect did not happen**, not only that the call was refused.

### Rules

- Test through the public interface. Do not reach into private helpers.
- No network, no real database, no `sleep`. Python tests run on in-memory SQLite,
  pinned by `packages/<service>/conftest.py` so a local `.env` can never leak in.
- Assert on behaviour, not implementation. `assert counts == [1, 0, 2]`, never
  "the ORM was called once".
- A bug fix starts with a failing test that reproduces it.

## Coverage, honestly

There is no coverage percentage gate. A number is easy to game and says nothing about
whether the **rules** are tested. The gate is the checklist at the top: every acceptance
criterion has a test that names it.

Current suites:

| Package | Tests | Covers |
| --- | --- | --- |
| `poll-service` | 45 | voting rules, results counting, validation, seed idempotency, helpers |
| `qa-service` | 3 | health endpoints (the feature is built live) |
| `web` | 27 | API client + error mapping, device identity, chart rendering |

## Reviewing agent-written code

The review moment in the session is the point of the whole thing. What to look for, in
order:

1. **Did it test the rule, or just the happy path?** The most common gap by far.
2. **Did it enforce the rule where it matters** — a database constraint, not only an
   `if`? Race conditions do not show up in a demo, they show up in production.
3. **Did it invent scope?** New endpoints, new tables, a caching layer nobody asked for.
4. **Did it weaken a gate to go green?** Search the diff for `noqa`, `eslint-disable`,
   `any`, `skip`.
5. **Are the error messages readable by a human** who is not a developer?

If a rule is missing, the right prompt is *"add the rate limit and a test for it"* —
name the rule and demand the test in the same breath.

## Security hygiene

This repo is edited by agents on a recorded screen.

- `.cursorignore` keeps `.env`, kubeconfigs, keys and `secrets/` out of agent context.
- `.gitignore` keeps them out of git.
- `.env.example` documents every variable by **name only**.
- Agents are told, in `AGENTS.md`, never to read or print them.

Those are four independent layers because any one of them can be forgotten.
