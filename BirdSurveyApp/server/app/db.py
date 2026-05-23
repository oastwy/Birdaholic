import os
from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row


DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://birdsurvey:change-me@localhost:5432/birdsurvey"
)


@contextmanager
def connect():
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        yield conn


def init_db():
    here = os.path.dirname(__file__)
    with open(os.path.join(here, "schema.sql"), "r", encoding="utf-8") as f:
        sql = f.read()
    with connect() as conn:
        conn.execute(sql)
        conn.commit()
