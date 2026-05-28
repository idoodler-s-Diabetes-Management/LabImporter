#!/usr/bin/env python3
"""Fetch LOINC codes from fhir.loinc.org and build LabImporter/Resources/loinc.db.

Authenticates with HTTP Basic against the Regenstrief FHIR terminology server
using credentials read from LOINC_USERNAME / LOINC_PASSWORD environment
variables (or a gitignored tools/.env file in the same KEY=VALUE format).

Behaviour:
- If LabImporter/Resources/loinc.db is younger than --max-age-days
  (default 30) AND already has rows, exit 0 without contacting the network.
- Else expand the configured ValueSet, optionally pull linguistic variants
  via per-code $lookup, and atomically replace loinc.db.
- If the credentials aren't set (e.g. on a build machine without secrets),
  print a status message and exit 0 so the Xcode build doesn't fail.

Default ValueSet is the LOINC Top 2000+ Lab Observations panel
(http://loinc.org/vs/top-2000-plus-lab-results-us) — the curated subset of
the most commonly ordered lab tests. Override with --valueset or the
LOINC_VALUESET env var to target a different one (e.g. a custom panel).
"""

from __future__ import annotations

import argparse
import base64
import datetime
import json
import os
import pathlib
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT_DB = REPO_ROOT / "LabImporter" / "Resources" / "loinc.db"
ENV_FILE = REPO_ROOT / "tools" / ".env"

FHIR_BASE = "https://fhir.loinc.org/"
DEFAULT_VALUESET = "http://loinc.org/vs/top-2000-plus-lab-results-us"
USER_AGENT = (
    "LabImporter-Sync/0.2 "
    "(https://github.com/idoodler-s-Diabetes-Management/LabImporter)"
)


def load_dotenv(path: pathlib.Path) -> None:
    """Tiny .env loader (no third-party dep). Only sets vars not already in env."""
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def credentials() -> tuple[str, str] | None:
    user = os.environ.get("LOINC_USERNAME")
    password = os.environ.get("LOINC_PASSWORD")
    if not user or not password:
        return None
    return user, password


def auth_header(user: str, password: str) -> str:
    encoded = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    return "Basic " + encoded


def fhir_get(
    path: str,
    params: dict[str, str | int],
    header: str,
    timeout: int = 60,
    retries: int = 3,
    backoff: float = 2.0,
) -> dict:
    url = FHIR_BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={
        "Authorization": header,
        "Accept": "application/fhir+json",
        "User-Agent": USER_AGENT,
    })
    last: Exception | None = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            if exc.code == 401:
                sys.exit(
                    "error: 401 Unauthorized from fhir.loinc.org — "
                    "check LOINC_USERNAME / LOINC_PASSWORD."
                )
            if exc.code == 403:
                sys.exit(
                    "error: 403 Forbidden — your Regenstrief account isn't "
                    "approved for this endpoint."
                )
            if exc.code in (429, 500, 502, 503, 504):
                wait = backoff * (attempt + 1)
                print(f"  HTTP {exc.code} — retrying in {wait:.0f}s", flush=True)
                time.sleep(wait)
                last = exc
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as exc:
            wait = backoff * (attempt + 1)
            print(f"  network error — retrying in {wait:.0f}s", flush=True)
            time.sleep(wait)
            last = exc
    raise last if last else RuntimeError("unreachable")


def expand_valueset(uri: str, header: str) -> list[tuple[str, str]]:
    print(f"Expanding ValueSet: {uri}", flush=True)
    offset = 0
    count = 1000
    collected: list[tuple[str, str]] = []
    while True:
        payload = fhir_get(
            "ValueSet/$expand",
            {"url": uri, "offset": offset, "count": count},
            header,
        )
        contains = payload.get("expansion", {}).get("contains", [])
        if not contains:
            break
        for entry in contains:
            code = entry.get("code")
            if not code:
                continue
            display = entry.get("display") or code
            collected.append((code, display))
        if len(contains) < count:
            break
        offset += count
        print(f"  {len(collected)} codes…", flush=True)
    print(f"  total: {len(collected)} codes", flush=True)
    return collected


def lookup_translations(
    codes: list[tuple[str, str]],
    languages: list[str],
    header: str,
    sleep_between: float = 0.02,
) -> list[tuple[str, str, str]]:
    print(f"Fetching translations for {len(languages)} language(s)…", flush=True)
    out: list[tuple[str, str, str]] = []
    total = len(codes) * len(languages)
    done = 0
    for code, _ in codes:
        for lang in languages:
            try:
                payload = fhir_get(
                    "CodeSystem/$lookup",
                    {
                        "system": "http://loinc.org",
                        "code": code,
                        "displayLanguage": lang,
                    },
                    header,
                )
            except urllib.error.HTTPError as exc:
                if exc.code == 404:
                    continue
                raise
            for param in payload.get("parameter", []):
                if param.get("name") == "display":
                    value = param.get("valueString") or ""
                    if value:
                        out.append((code, lang, value))
                    break
            done += 1
            if done % 250 == 0:
                print(f"  translations: {done}/{total}", flush=True)
            time.sleep(sleep_between)
    print(f"  total translations: {len(out)}", flush=True)
    return out


def build_db(codes: list[tuple[str, str]], translations: list[tuple[str, str, str]]) -> pathlib.Path:
    OUTPUT_DB.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUTPUT_DB.with_suffix(".db.tmp")
    if tmp.exists():
        tmp.unlink()
    conn = sqlite3.connect(tmp)
    try:
        conn.executescript(
            """
            CREATE TABLE loinc_codes (
                loinc TEXT PRIMARY KEY,
                long_common_name TEXT NOT NULL,
                shortname TEXT,
                component TEXT,
                property TEXT,
                system TEXT,
                scale_typ TEXT,
                method_typ TEXT,
                class TEXT,
                example_ucum_units TEXT,
                status TEXT
            );
            CREATE TABLE loinc_translations (
                loinc TEXT NOT NULL,
                language_code TEXT NOT NULL,
                long_common_name TEXT,
                shortname TEXT,
                component TEXT,
                PRIMARY KEY (loinc, language_code)
            );
            CREATE TABLE meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE VIRTUAL TABLE loinc_search USING fts5(
                loinc UNINDEXED,
                long_common_name,
                shortname,
                component,
                tokenize='porter unicode61'
            );
            """
        )
        conn.executemany(
            "INSERT OR REPLACE INTO loinc_codes "
            "(loinc, long_common_name, shortname, component, property, system, "
            "scale_typ, method_typ, class, example_ucum_units, status) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (code, display, None, None, None, None, None, None, None, None, "ACTIVE")
                for code, display in codes
            ],
        )
        conn.executemany(
            "INSERT INTO loinc_search (loinc, long_common_name, shortname, component) "
            "VALUES (?, ?, ?, ?)",
            [(code, display, "", "") for code, display in codes],
        )
        conn.executemany(
            "INSERT OR REPLACE INTO loinc_translations "
            "(loinc, language_code, long_common_name, shortname, component) "
            "VALUES (?, ?, ?, ?, ?)",
            [(code, lang, label, None, None) for code, lang, label in translations],
        )
        attribution = (
            "This product includes LOINC content retrieved from "
            "https://fhir.loinc.org/. LOINC® is a registered trademark of "
            "Regenstrief Institute, Inc., used under the LOINC License "
            "(http://loinc.org/license)."
        )
        conn.executemany(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
            [
                ("loinc_version", "fhir-" + datetime.datetime.utcnow().strftime("%Y%m%d")),
                ("built_at", datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z"),
                ("code_count", str(len(codes))),
                ("translation_count", str(len(translations))),
                ("attribution", attribution),
                ("source", "fhir.loinc.org"),
            ],
        )
        conn.execute("VACUUM")
        conn.commit()
    finally:
        conn.close()
    os.replace(tmp, OUTPUT_DB)
    return OUTPUT_DB


def existing_is_fresh(max_age_days: int) -> bool:
    if not OUTPUT_DB.exists():
        return False
    try:
        conn = sqlite3.connect(OUTPUT_DB)
        try:
            placeholder = conn.execute(
                "SELECT value FROM meta WHERE key = 'placeholder' LIMIT 1"
            ).fetchone()
            if placeholder and (placeholder[0] or "").lower() == "true":
                return False
            count = conn.execute("SELECT COUNT(*) FROM loinc_codes").fetchone()
            if not count or count[0] == 0:
                return False
        finally:
            conn.close()
    except sqlite3.DatabaseError:
        return False
    age = time.time() - OUTPUT_DB.stat().st_mtime
    return age < max_age_days * 86400


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-age-days", type=int, default=30)
    parser.add_argument("--force", action="store_true",
                        help="Refresh even if the existing DB is recent.")
    parser.add_argument("--valueset",
                        default=os.environ.get("LOINC_VALUESET", DEFAULT_VALUESET),
                        help="Canonical ValueSet URI to expand.")
    parser.add_argument("--languages",
                        default=os.environ.get("LOINC_LANGUAGES", ""),
                        help="Comma-separated language codes for linguistic variants "
                             "(e.g. 'de,fr,es'). Empty = English only.")
    args = parser.parse_args()

    load_dotenv(ENV_FILE)

    if not args.force and existing_is_fresh(args.max_age_days):
        size = OUTPUT_DB.stat().st_size / 1024
        print(f"loinc.db is fresh (< {args.max_age_days} days, {size:.0f} KB) — skipping.")
        return

    creds = credentials()
    if creds is None:
        msg = (
            "LOINC_USERNAME / LOINC_PASSWORD not set — skipping LOINC refresh."
        )
        if OUTPUT_DB.exists():
            print(msg + " Existing loinc.db left in place.")
        else:
            print(msg + " loinc.db will be the placeholder bundled with the repo.")
        return

    header = auth_header(*creds)

    try:
        codes = expand_valueset(args.valueset, header)
    except urllib.error.URLError as exc:
        print(f"warning: ValueSet expansion failed ({exc}). Keeping existing loinc.db.",
              file=sys.stderr)
        sys.exit(0)

    if not codes:
        sys.exit(
            "error: ValueSet expansion returned zero codes. "
            f"Check --valueset (was: {args.valueset})."
        )

    languages = [lang.strip() for lang in args.languages.split(",") if lang.strip()]
    translations: list[tuple[str, str, str]] = []
    if languages:
        try:
            translations = lookup_translations(codes, languages, header)
        except urllib.error.URLError as exc:
            print(f"warning: translation lookup failed ({exc}). Continuing without.",
                  file=sys.stderr)

    db_path = build_db(codes, translations)
    size_kb = db_path.stat().st_size / 1024
    print(
        f"Built {db_path} — {len(codes)} codes, {len(translations)} translations, "
        f"{size_kb:.0f} KB."
    )


if __name__ == "__main__":
    main()
