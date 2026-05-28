# Tools

## `sync_loinc.py` — bundled LOINC database via fhir.loinc.org

LabImporter ships a read-only SQLite database (`LabImporter/Resources/loinc.db`)
powering the LOINC search and per-code customisation in Settings.
`tools/sync_loinc.py` builds it by hitting the Regenstrief FHIR
terminology server at <https://fhir.loinc.org/> over HTTP Basic Auth.

### Credential setup (one-time)

1. Make sure you have a free Regenstrief account at
   <https://loinc.org/my-account/>.
2. Copy `tools/.env.example` to `tools/.env`. The path is gitignored.
3. Fill in:

       LOINC_USERNAME=your-loinc-username
       LOINC_PASSWORD=your-loinc-password

Alternatively export them in your shell (`export LOINC_USERNAME=...`)
or store them in macOS Keychain and source them at run time.

### Running the script

From the repo root:

    python3 tools/sync_loinc.py                  # respects 30-day cache
    python3 tools/sync_loinc.py --force          # rebuild now
    python3 tools/sync_loinc.py --languages de,fr  # pull translations too

The script:

1. Expands the configured ValueSet (default: LOINC Top 2000+ Lab
   Observations) via FHIR `ValueSet/$expand`.
2. Optionally calls `CodeSystem/$lookup` per code per requested language
   to pull linguistic variants. (Skip with empty `--languages` if you
   only need English — ~2000 lookups per language is slow.)
3. Builds a fresh SQLite with FTS5 search and atomically replaces
   `LabImporter/Resources/loinc.db`.

The default ValueSet (`http://loinc.org/vs/top-2000-plus-lab-results-us`)
covers the ~2000 most commonly ordered lab tests — sufficient for every
chemistry, hematology, lipid, liver, and endocrine panel a consumer
report would carry. Override with `--valueset` or `LOINC_VALUESET` to
target a different one.

### Build-time integration

The Xcode "Sync LOINC" Run Script phase invokes the same script on every
build. It is intentionally non-fatal:

- No credentials in the environment → script prints a status and exits
  0, leaving whatever DB is already on disk.
- Cached DB younger than 30 days → script exits 0 without contacting
  the network.
- Network failure → script warns and exits 0.

That means CI / cloud Xcode sessions without secrets still build cleanly.

### Refreshing

Run `python3 tools/sync_loinc.py --force` whenever Regenstrief publishes
a new LOINC release (typically twice a year). The committed `loinc.db`
will pick up the new version on the next push.

### Licensing

LOINC identifiers and display content are © Regenstrief Institute,
licensed under the LOINC License (<http://loinc.org/license>). The
attribution is stored in the `meta` table of `loinc.db` and surfaced
in **Settings → About → License** at runtime.
