#!/usr/bin/env python3
"""Cache key shared by websearch-router.sh (reader) and websearch-cache.sh (writer).

One implementation on purpose. When the reader and the writer each normalise the
subject their own way, the two agree in testing and drift the first time a query
carries punctuation, so the cache silently never hits and the whole gate is theatre.

Usage:  websearch-key.py "<query> <url>"     -> 16 hex chars on stdout
        or pipe the subject on stdin
"""
import hashlib
import re
import sys


def key(subject: str) -> str:
    norm = re.sub(r"[^a-z0-9 ]", "", subject.lower())
    norm = re.sub(r"\s+", " ", norm).strip()
    return hashlib.sha1(norm.encode()).hexdigest()[:16]


if __name__ == "__main__":
    subject = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else sys.stdin.read()
    print(key(subject))
