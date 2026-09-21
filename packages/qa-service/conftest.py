"""Runs before any test module is imported. See poll-service/conftest.py."""

import os

os.environ["QA_DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
os.environ.setdefault("PULSE_PRESENTER_TOKEN", "demo-presenter-token")
