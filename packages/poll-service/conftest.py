"""Runs before any test module is imported.

Pins the test database to in-memory SQLite so a local .env pointing at Postgres
(or a file) can never be touched by a test run.
"""

import os

os.environ["PULSE_DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
os.environ.setdefault("PULSE_PRESENTER_TOKEN", "demo-presenter-token")
