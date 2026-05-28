# Tools

## `build_loinc_db.py` — bundled LOINC lookup database

LabImporter ships a read-only SQLite database (`LabImporter/Resources/loinc.db`)
that powers the per-code reference-range editor and the LOINC lookup section in
Settings. The DB is produced from the Regenstrief LOINC release and is **not
checked into git** (the LOINC table is licensed and must be downloaded by each
developer).

### Build steps

1. Register a free Regenstrief account at https://loinc.org/downloads/ and
   download the latest **LOINC Table File (CSV)** release plus the **LOINC
   Linguistic Variants** archive.
2. Unzip both into `tools/.loinc_source/` such that the directory tree looks
   like:

       tools/.loinc_source/
         LoincTable/Loinc.csv
         AccessoryFiles/LinguisticVariants/deAT24LinguisticVariant.csv
         AccessoryFiles/LinguisticVariants/frFR24LinguisticVariant.csv
         …

3. From the repo root, run:

       python3 tools/build_loinc_db.py

   The script filters to lab-observation classes (CHEM, HEM/BC, COAG, MICRO, …),
   builds an FTS5 search index, imports linguistic variants for the supported
   locales, stamps version metadata, and writes the resulting database to
   `LabImporter/Resources/loinc.db`. Typical output: ~6–8 MB.

4. Open `LabImporter.xcodeproj` and confirm `Resources/loinc.db` is included in
   the LabImporter target's Copy Bundle Resources phase (the project already
   references the path; rebuilding the DB just refreshes the file in place).

The app boots without the DB — Settings simply falls back to the legacy
hard-coded code list. Once you build and bundle the DB, the full LOINC
directory becomes searchable.

### Refreshing for a new LOINC release

Regenstrief publishes new LOINC versions roughly twice per year. Replace the
contents of `tools/.loinc_source/` with the new release and re-run the script.
The output filename and bundle path don't change.

### Licensing

The bundled LOINC content is licensed under the Regenstrief LOINC License
(see https://loinc.org/license). The required attribution is shown in the
app's **About → License** screen and stored in the `meta` table of the
generated database.
