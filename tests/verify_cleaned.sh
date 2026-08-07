#!/usr/bin/env bash
# Verify that R/process_anes_2024.R still produces byte-identical cleaned data.
#
# The recode is deterministic, so any change to the checksums means the survey
# processing changed. That is either intentional -- rerun with --update and
# commit the new manifest alongside the code change -- or a regression.
#
# Run from the repository root:
#   tests/verify_cleaned.sh            # check
#   tests/verify_cleaned.sh --update   # re-record after an intentional change
#
# Cleaned data must agree with the ACS poststratification frame cell-for-cell,
# so a silent shift in the recode invalidates every downstream estimate without
# raising an error anywhere else in the pipeline. This check is the guard.

set -euo pipefail

cd "$(dirname "$0")/.."
MANIFEST="tests/cleaned_manifest.sha256"

if [[ "${1:-}" == "--update" ]]; then
    sha256sum data/cleaned/*.csv > "$MANIFEST"
    echo "Manifest updated:"
    cat "$MANIFEST"
    echo
    echo "Commit this alongside the change to R/process_anes_2024.R that caused it."
    exit 0
fi

if [[ ! -f "$MANIFEST" ]]; then
    echo "FAIL: $MANIFEST not found." >&2
    exit 1
fi

missing=0
while read -r _ path; do
    if [[ ! -f "$path" ]]; then
        echo "MISSING: $path" >&2
        missing=1
    fi
done < "$MANIFEST"

if [[ $missing -eq 1 ]]; then
    echo >&2
    echo "Cleaned data absent. Regenerate it with:" >&2
    echo "  Rscript R/process_anes_2024.R" >&2
    exit 1
fi

if sha256sum -c "$MANIFEST"; then
    echo
    echo "PASS: cleaned data matches the recorded manifest."
else
    echo >&2
    echo "FAIL: cleaned data has drifted from the manifest." >&2
    echo "If the change was intentional, rerun with --update and commit the result." >&2
    exit 1
fi
