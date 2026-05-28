# LOINC Release Drop-in

Place the unmodified Regenstrief LOINC release zip in this directory, e.g.:

    tools/loinc/Loinc_2.78_Text.zip

The Xcode build phase reads it directly — no need to unzip by hand.

## Required files in the zip

- `LoincTable/Loinc.csv`
- `AccessoryFiles/LinguisticVariants/*.csv` (optional, enables translations)

Both come from the standard "LOINC Table File (CSV)" download at
<https://loinc.org/downloads/>.

## License

Drop `LICENSE.txt` from the LOINC release next to the zip. The Regenstrief
LOINC License permits redistribution as long as the license travels with
the data.

## Refresh procedure

Replace the existing zip with the new release and commit. The build phase
detects the change by mtime and rebuilds `LabImporter/Resources/loinc.db`
on the next build.

## Why not keep the zip out of git?

For now we commit the zip directly so every clone has everything it needs
to build. If the repo grows uncomfortably large across LOINC releases,
switch to `git lfs track "tools/loinc/*.zip"` — no other code change
required.
