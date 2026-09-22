---
title: Set up your machine
description: One command, then a look at exactly what it did.
---

# Set up your machine

## The whole thing

```bash
git clone <your-fork-url> Pulse && cd Pulse && npm run setup
```

That is it. Expect three to five minutes the first time, most of it downloading.

When it finishes you will see the URLs to open. If anything failed, skip to
[Troubleshooting](/reference/troubleshooting) — and read the error, because the script
tries hard to tell you the fix rather than just the failure.

## What it just did to your laptop

Worth knowing, because "run this script" is how people end up with machines they do
not understand.

| Step | What happened | Where it lives |
| --- | --- | --- |
| Found or installed **uv** | A fast Python package manager | System-wide, via winget/brew |
| Downloaded **CPython 3.12** | A standalone Python, managed by uv | uv's own cache |
| Created **`.venv/`** | The virtualenv both APIs run in | Inside the project |
| Installed Python deps | FastAPI, SQLAlchemy, pytest, ruff | `.venv/` |
| Ran `npm install` | Web app and tooling | `node_modules/` |
| Copied `.env.example` → **`.env`** | Local config | Inside the project, gitignored |
| Started **PostgreSQL** in Docker | The database | A container plus a named volume |
| **Seeded** room `CIT22A` | Three polls, ready to demo | Inside PostgreSQL |

:::info[Why this matters]
Notice what is **not** on that list: it did not install Python system-wide, did not
change your PATH beyond uv, and did not touch any database you already had.

Everything project-specific lives inside the project folder. `npm run clean` removes
all of it. That is the property you want from any setup script you run on a machine
you care about — and the property to check for before you run someone else's.
:::

## It works without Docker too

If Docker is not running, setup does not fail. It warns you, switches to SQLite, and
carries on:

```
⚠️  Docker is not running — falling back to SQLite
   💡 That is fine for development: nothing to start, same code path
```

The application code does not change. `PULSE_DATABASE_URL` points at either a SQLite
file or PostgreSQL, and SQLAlchemy handles the rest.

:::tip[The trade-off, honestly]
SQLite and PostgreSQL do not agree on everything — type coercion, concurrency
behaviour, and schema support all differ. For an app this small the difference never
shows, and being able to run with zero infrastructure is worth more than perfect
parity.

On a real product you would run the same engine everywhere. Know which rule you are
breaking and why; do not discover it later.
:::

## Check your machine

```bash
npm run doctor
```

This tells you what is present, what is missing, and what is holding each port:

```
🔹 Core
   ✅ node — v18.19.0
   ✅ uv — uv 0.12.17
🔹 Project
   ✅ .venv — Python 3.12.14
   ✅ node_modules — installed
🔹 Ports
   ✅ 5173 (web) — free
   ✅ 8001 (poll-service) — free
```

Run it before you debug anything. Most "it does not work" turns out to be a missing
tool or a port already in use, and this finds both in two seconds.

## Start it

```bash
npm run dev
```

Three services start together with colour-coded logs:

| Service | URL |
| --- | --- |
| Web | http://localhost:5173 |
| poll-service | http://localhost:8001/healthz |
| qa-service | http://localhost:8002/healthz |

You can also run just one — `npm run web`, `npm run poll-service`, `npm run qa-service`.
Useful when you are changing one thing and want its logs uncluttered.

## Run the tests

```bash
npm test
```

You should see **82 passing** — 53 Python, 29 web. If they pass, your setup is genuinely
correct, which is a stronger signal than the app merely starting.

```bash
npm run verify
```

That runs everything CI runs: lint, type check, tests, and a production build. Takes
about two minutes. Run it before you push and you will not be surprised by a red build.

:::warning[Windows: the `bash` on your PATH is probably WSL]
Every npm script here goes through `node scripts/run.mjs`, which resolves Git Bash
explicitly rather than trusting PATH.

The reason: on Windows, `bash` usually resolves to `C:\Windows\system32\bash.exe` — that
is WSL's bash, which cannot see your Windows Node or Docker. Meanwhile npm's default
shell is `cmd.exe`, which has no bash at all. Calling `bash scripts/dev.sh` directly
would break in a way that is genuinely hard to diagnose.

If you are on macOS or Linux, none of this applies and it just uses `/bin/bash`.
:::

---

**[Tour the app →](/tour)**
