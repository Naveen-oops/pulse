---
title: Review what it wrote
description: Five checks, in order, on code you did not type.
---

# Review what it wrote

The tests are green. The feature works when you click it. **Now do the actual work.**

Reviewing generated code is a different skill from reviewing a colleague's. A colleague
has intentions you can ask about, and habits you know. An agent produces plausible code
uniformly — the bugs do not cluster where inexperience would put them, and nothing in the
style signals "I was unsure here".

So you need a checklist rather than instinct. Five checks, in this order.

## 1. Did it test the rule, or the happy path?

The most common gap by a wide margin.

Take your numbered spec and grep for each rule. Eight acceptance criteria should produce
at least eight tests whose names describe rules:

```bash
cd packages/qa-service && python -m pytest --collect-only -q
```

Read the test names as sentences. You want to see the *rules*:

```
test_a_question_shorter_than_5_characters_is_rejected
test_a_second_upvote_from_the_same_device_is_ignored
test_a_device_cannot_upvote_its_own_question
test_the_sixth_question_in_a_minute_is_rejected
```

If you see only `test_create_question` and `test_upvote_question`, the happy path is
covered and the rules are not.

:::warning[The agent wrote the tests, so green means little]
This is the trap. A suite written by the same process that wrote the code tests what the
code does, not what the spec required.

A rule the agent forgot is a rule with no test — and the suite is green, because nothing
is checking. **Coverage of requirements is the only coverage that matters here**, and
only your spec can tell you about it.
:::

## 2. Is the rule enforced where it cannot be bypassed?

Find the "one upvote per device" rule and look for a database constraint, not just an
`if`:

```bash
grep -rn "UniqueConstraint" packages/qa-service/
```

You want:

```python
__table_args__ = (UniqueConstraint("question_id", "device_id", name="uq_vote_question_device"),)
```

If it is only an `if`, two taps in the same millisecond both pass the check and both
insert. The test passes — a sequential test cannot produce the race — and the bug reaches
production, where it is rare and awful to reproduce.

Same question for the rate limit: is it counted in the database, or in a Python dict that
resets when the pod restarts and is wrong the moment there are two replicas?

## 3. Did it invent scope?

```bash
git --no-pager diff --stat
```

Scan for things nobody asked for:

- New endpoints not in the spec
- A caching layer
- A new dependency in `requirements.txt` or `package.json`
- A second polling hook or fetch wrapper instead of reusing `api.ts`
- Changes under `deploy/` or `.github/`

```bash
git --no-pager diff -- requirements.txt package.json packages/*/requirements.txt
```

A new dependency is the one to challenge hardest. It is the most expensive line in any
diff and the least visible.

## 4. Did it weaken a gate to go green?

```bash
git --no-pager diff | grep -nE "noqa|type: ignore|eslint-disable|@ts-ignore|as any|skip|xfail"
```

Any hit needs a justification you accept. This is rule 6 in `AGENTS.md`, and it is worth
checking mechanically because it is invisible in behaviour: the code works, the gates
pass, and a rule you thought you had is gone.

The signature to watch for is a silenced check right next to the tricky part of the
feature.

## 5. Would a person understand the error messages?

```bash
grep -rn "detail=" packages/qa-service/app/
```

Compare:

```python
detail="Validation error on field text"                    # no
detail="Your question needs to be at least 5 characters."  # yes
```

These strings go on a projector. If the spec named them, check they match exactly.

## How to ask for a fix

Name the rule, demand the test, in one sentence:

```text
Rule 3 (a device cannot upvote its own question) has no test and no enforcement.
Add both.
```

Not "the upvoting logic looks incomplete". Specific, addressable, and verifiable when it
comes back.

:::tip[Ask for the test in the same breath as the fix]
"Add the rate limit" gets you a rate limit you then have to verify by hand.

"Add the rate limit and a test for it" gets you the rule *and* the thing that proves the
rule — and the test is a durable check that survives the next refactor. It costs the same
number of words.
:::

## The habit worth keeping

| Check | Question |
| --- | --- |
| 1 | Does every numbered rule have a test that names it? |
| 2 | Is each rule enforced where it cannot be bypassed? |
| 3 | Is anything here that I did not ask for? |
| 4 | Was any gate silenced to make this pass? |
| 5 | Can a non-developer read the error messages? |

Five questions, two minutes, on any generated diff in any codebase.

:::info[The real lesson of the session]
Agents have moved the bottleneck. Writing the code is no longer the slow part;
**knowing whether the code is right** is.

That makes specification and review the high-value skills — and both are teachable,
which is convenient for a room full of educators. The checklist above is the teachable
version.
:::

---

**[Every command →](/reference/commands)**
