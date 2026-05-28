#!/usr/bin/env python3
"""Build the bundled LOINC SQLite database from a Regenstrief LOINC release.

Usage:
    python3 tools/build_loinc_db.py

Expects the unzipped LOINC release at tools/.loinc_source/ — specifically
the LoincTable/Loinc.csv file and (optionally) AccessoryFiles/LinguisticVariants/.
Writes LabImporter/Resources/loinc.db.

The LOINC content is licensed by the Regenstrief Institute. The repository
ships only this build script; the LOINC release itself must be downloaded
by each developer from https://loinc.org/downloads/ (free account required).
"""

from __future__ import annotations

import csv
import datetime
import os
import re
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO_ROOT / "tools" / ".loinc_source"
OUTPUT_DB = REPO_ROOT / "LabImporter" / "Resources" / "loinc.db"

# LOINC CLASS prefixes considered "lab observations" — filters out radiology,
# survey instruments, document ontology, etc. Adjust as needed.
LAB_CLASS_PREFIXES = (
    "CHEM",      # Chemistry
    "HEM/BC",    # Hematology / blood count
    "COAG",      # Coagulation
    "DRUG/TOX",  # Therapeutic drug monitoring & toxicology
    "MICRO",     # Microbiology
    "SERO",      # Serology
    "ALLERGY",
    "BLDBK",     # Blood bank
    "MOLPATH",   # Molecular pathology
    "PATH",      # Anatomic pathology
    "URINE",
    "CELLMARK",
    "CYTO",
    "FERT",      # Fertility
    "HORMONE",
    "TUMOR",     # Tumor markers
    "VITAMINS",
)

# Linguistic variant filenames look like "LinguisticVariants/deAT24LinguisticVariant.csv"
# Map the prefix code → ISO language code we'll store.
LANGUAGE_PREFIX_MAP = {
    "de": "de",
    "fr": "fr",
    "es": "es",
    "it": "it",
    "nl": "nl",
    "pt": "pt",
    "pl": "pl",
    "ru": "ru",
    "zh": "zh",
    "ja": "ja",
    "ko": "ko",
    "tr": "tr",
    "cs": "cs",
    "uk": "uk",
    "el": "el",
    "et": "et",
}


def find_loinc_table() -> Path:
    candidates = list(SOURCE_DIR.rglob("Loinc.csv"))
    if not candidates:
        sys.exit(
            f"Could not find Loinc.csv under {SOURCE_DIR}.\n"
            "Download the LOINC release from https://loinc.org/downloads/ "
            "(free Regenstrief account required), unzip it into tools/.loinc_source/, "
            "and re-run this script."
        )
    # Prefer the canonical LoincTable/Loinc.csv if multiple exist.
    canonical = [p for p in candidates if p.parent.name == "LoincTable"]
    return canonical[0] if canonical else candidates[0]


def detect_version() -> str:
    version_files = list(SOURCE_DIR.rglob("LoincTableUserGuide.htm")) + list(
        SOURCE_DIR.rglob("LOINC_*_README.txt")
    )
    for path in version_files:
        match = re.search(r"(\d+\.\d+)", path.name)
        if match:
            return match.group(1)
    # Fall back to a folder name like "Loinc_2.77".
    for child in SOURCE_DIR.iterdir():
        match = re.search(r"(\d+\.\d+)", child.name)
        if match:
            return match.group(1)
    return "unknown"


def is_lab_class(class_value: str) -> bool:
    if not class_value:
        return False
    upper = class_value.upper()
    return any(upper.startswith(prefix) for prefix in LAB_CLASS_PREFIXES)


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        DROP TABLE IF EXISTS loinc_codes;
        DROP TABLE IF EXISTS loinc_translations;
        DROP TABLE IF EXISTS meta;
        DROP TABLE IF EXISTS loinc_search;

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


def import_core_table(conn: sqlite3.Connection, loinc_csv: Path) -> int:
    inserted = 0
    with loinc_csv.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows: list[tuple] = []
        search_rows: list[tuple] = []
        for row in reader:
            if not is_lab_class(row.get("CLASS", "")):
                continue
            if row.get("STATUS", "ACTIVE").upper() == "DEPRECATED":
                continue
            loinc = row["LOINC_NUM"].strip()
            if not loinc:
                continue
            long_name = row.get("LONG_COMMON_NAME") or row.get("COMPONENT") or loinc
            rows.append(
                (
                    loinc,
                    long_name,
                    row.get("SHORTNAME") or None,
                    row.get("COMPONENT") or None,
                    row.get("PROPERTY") or None,
                    row.get("SYSTEM") or None,
                    row.get("SCALE_TYP") or None,
                    row.get("METHOD_TYP") or None,
                    row.get("CLASS") or None,
                    row.get("EXAMPLE_UCUM_UNITS") or None,
                    row.get("STATUS") or "ACTIVE",
                )
            )
            search_rows.append(
                (
                    loinc,
                    long_name,
                    row.get("SHORTNAME") or "",
                    row.get("COMPONENT") or "",
                )
            )
            inserted += 1
        conn.executemany(
            "INSERT OR REPLACE INTO loinc_codes "
            "(loinc, long_common_name, shortname, component, property, system, "
            "scale_typ, method_typ, class, example_ucum_units, status) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            rows,
        )
        conn.executemany(
            "INSERT INTO loinc_search (loinc, long_common_name, shortname, component) "
            "VALUES (?, ?, ?, ?)",
            search_rows,
        )
    return inserted


def import_translations(conn: sqlite3.Connection) -> int:
    linguistic_dir = next(
        (p for p in SOURCE_DIR.rglob("LinguisticVariants") if p.is_dir()), None
    )
    if linguistic_dir is None:
        return 0
    valid_loincs: set[str] = {
        row[0] for row in conn.execute("SELECT loinc FROM loinc_codes")
    }
    inserted = 0
    for csv_path in sorted(linguistic_dir.glob("*LinguisticVariant.csv")):
        match = re.match(r"([a-z]{2})", csv_path.name)
        if not match:
            continue
        lang = LANGUAGE_PREFIX_MAP.get(match.group(1))
        if lang is None:
            continue
        with csv_path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            rows: list[tuple] = []
            for row in reader:
                loinc = (row.get("LOINC_NUM") or "").strip()
                if not loinc or loinc not in valid_loincs:
                    continue
                rows.append(
                    (
                        loinc,
                        lang,
                        row.get("LONG_COMMON_NAME") or None,
                        row.get("SHORTNAME") or None,
                        row.get("COMPONENT") or None,
                    )
                )
            if rows:
                conn.executemany(
                    "INSERT OR REPLACE INTO loinc_translations "
                    "(loinc, language_code, long_common_name, shortname, component) "
                    "VALUES (?, ?, ?, ?, ?)",
                    rows,
                )
                inserted += len(rows)
    return inserted


def write_meta(conn: sqlite3.Connection, version: str, code_count: int, translation_count: int) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
        [
            ("loinc_version", version),
            ("built_at", datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z"),
            ("code_count", str(code_count)),
            ("translation_count", str(translation_count)),
            ("attribution", "This product includes all or a portion of the LOINC table, "
                            "LOINC codes, LOINC panels and forms file, LOINC linguistic "
                            "variants file, LOINC/RSNA Radiology Playbook, or LOINC/IEEE "
                            "Medical Device Code Mapping Table, copyright © 1995-2024, "
                            "Regenstrief Institute, Inc. and the Logical Observation "
                            "Identifiers Names and Codes (LOINC) Committee and available "
                            "at no cost under the license at http://loinc.org/license. "
                            "LOINC® is a registered United States trademark of "
                            "Regenstrief Institute, Inc."),
        ],
    )


def main() -> None:
    if not SOURCE_DIR.is_dir():
        sys.exit(
            f"Missing source directory {SOURCE_DIR}.\n"
            "Download the LOINC release from https://loinc.org/downloads/ "
            "(free Regenstrief account required), then unzip it into "
            "tools/.loinc_source/ so this script can find Loinc.csv."
        )

    OUTPUT_DB.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT_DB.exists():
        OUTPUT_DB.unlink()

    loinc_csv = find_loinc_table()
    version = detect_version()

    conn = sqlite3.connect(OUTPUT_DB)
    try:
        create_schema(conn)
        code_count = import_core_table(conn, loinc_csv)
        translation_count = import_translations(conn)
        write_meta(conn, version, code_count, translation_count)
        conn.execute("VACUUM")
        conn.commit()
    finally:
        conn.close()

    size_mb = OUTPUT_DB.stat().st_size / (1024 * 1024)
    print(f"Built {OUTPUT_DB} — LOINC v{version}, {code_count} lab codes, "
          f"{translation_count} translations, {size_mb:.1f} MB.")


if __name__ == "__main__":
    main()
