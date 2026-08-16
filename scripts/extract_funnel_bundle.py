#!/usr/bin/env python3
"""Extract demo/funnel_bundle.json from the four featured lookup CSVs.

Reads only data/estimates/lookup_<question>.csv. No refits, no frame reads.
"""
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ESTIMATES_DIR = REPO_ROOT / "data" / "estimates"
OUT_PATH = REPO_ROOT / "demo" / "funnel_bundle.json"

STATES = ["TX", "CA", "NY", "FL", "PA", "OH", "GA", "AZ", "WI", "NC", "MI", "CO", "VA"]

AGE_GROUPS = [
    "18-24", "25-29", "30-34", "35-39", "40-44", "45-49", "50-54",
    "55-59", "60-64", "65-69", "70-74", "75-79", "80 plus",
]
EDUCS = ["HS or less", "Some College", "BA/BS", "Postgrad"]

QUESTIONS = {
    "democracy_importance": {
        "lookup": "lookup_democracy_importance.csv",
        "funnel_role": "unity_opener",
        "lead_disclosure": "age_group",
        "question_text": "How important is it that the U.S. remains a democracy?",
        "positive_label": "% saying important",
        "party": {"dem": 91.6, "ind": 64.0, "rep": 81.6, "note": "% saying important"},
        "led_by": "age",
    },
    "no_say": {
        "lookup": "lookup_no_say.csv",
        "funnel_role": "spine",
        "lead_disclosure": "educ",
        "question_text": "'People like me don't have any say about what the government does.'",
        "positive_label": "% who agree",
        "party": {"dem": 72.6, "ind": 84.5, "rep": 75.8, "note": "% agreeing"},
        "led_by": "educ",
    },
    "country_offtrack": {
        "lookup": "lookup_country_offtrack.csv",
        "funnel_role": "grievance",
        "lead_disclosure": "age_group",
        "question_text": "Do you feel things in this country have gotten off on the wrong track?",
        "positive_label": "% saying wrong track",
        "party": {"dem": 55.8, "ind": 87.3, "rep": 94.8, "note": "% saying wrong track"},
        "led_by": "age",
    },
    "gov_few_interests": {
        "lookup": "lookup_gov_few_interests.csv",
        "funnel_role": "climax",
        "lead_disclosure": "age_group",
        "question_text": "Is the government run by a few big interests looking out for themselves, or for the benefit of all the people?",
        "positive_label": "% saying a few big interests",
        "party": {"dem": 77.8, "ind": 80.2, "rep": 89.2, "note": "% saying few big interests"},
        "led_by": "age",
    },
}


def load_lookup(path):
    """Index rows by (state, age_group, sex, race, educ) -> row dict."""
    index = {}
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = (row["state"], row["age_group"], row["sex"], row["race"], row["educ"])
            index[key] = row
    return index


def row_to_estimate(row):
    return {
        "estimate": round(float(row["estimate"]), 6),
        "q025": round(float(row["q025"]), 6),
        "q975": round(float(row["q975"]), 6),
        "ci_width": round(float(row["ci_width"]), 6),
        "reliability": row["reliability"],
        "n_survey": int(row["n_survey"]),
    }


def get(index, state, age, educ):
    key = (state, age, "ALL", "ALL", educ)
    return index.get(key)


def main():
    report = {"generated_at": datetime.now(timezone.utc).isoformat(), "questions": {}}
    bundle = {
        "generated_at": report["generated_at"],
        "vintage": "2024 ANES",
        "questions": {},
    }

    console_lines = []
    fallback_summary_lines = []

    for qkey, qmeta in QUESTIONS.items():
        path = ESTIMATES_DIR / qmeta["lookup"]
        index = load_lookup(path)

        national_row = get(index, "ALL", "ALL", "ALL")
        if national_row is None:
            print(f"FATAL: no national row for {qkey}", file=sys.stderr)
            sys.exit(1)
        national_est = row_to_estimate(national_row)

        slices = []
        excluded_low = 0
        excluded_states = set()
        always_national_states = []

        # National x age_group (13 rows)
        for age in AGE_GROUPS:
            r = get(index, "ALL", age, "ALL")
            if r is None:
                continue
            if r["reliability"] == "low":
                excluded_low += 1
                continue
            e = row_to_estimate(r)
            slices.append({"state": "ALL", "age_group": age, "educ": "ALL", **e})

        # National x educ (4 rows)
        for educ in EDUCS:
            r = get(index, "ALL", "ALL", educ)
            if r is None:
                continue
            if r["reliability"] == "low":
                excluded_low += 1
                continue
            e = row_to_estimate(r)
            slices.append({"state": "ALL", "age_group": "ALL", "educ": educ, **e})

        led_by = qmeta["led_by"]

        for state in STATES:
            # state-only gate
            state_only = get(index, state, "ALL", "ALL")
            if state_only is None or state_only["reliability"] == "low":
                excluded_states.add(state)
                fallback_summary_lines.append(
                    f"{qkey}: {state} excluded entirely (state-only slice reliability="
                    f"{'low' if state_only else 'missing'})"
                )
                continue

            e = row_to_estimate(state_only)
            slices.append({"state": state, "age_group": "ALL", "educ": "ALL", **e})

            state_has_any_deep = False

            if led_by == "age":
                for age in AGE_GROUPS:
                    r = get(index, state, age, "ALL")
                    if r is None:
                        continue
                    if r["reliability"] == "low":
                        excluded_low += 1
                        continue
                    e = row_to_estimate(r)
                    slices.append({"state": state, "age_group": age, "educ": "ALL", **e})
                    state_has_any_deep = True
                    for educ in EDUCS:
                        r2 = get(index, state, age, educ)
                        if r2 is None:
                            continue
                        if r2["reliability"] == "low":
                            excluded_low += 1
                            continue
                        e2 = row_to_estimate(r2)
                        slices.append({"state": state, "age_group": age, "educ": educ, **e2})
            else:  # led_by == "educ"
                for educ in EDUCS:
                    r = get(index, state, "ALL", educ)
                    if r is None:
                        continue
                    if r["reliability"] == "low":
                        excluded_low += 1
                        continue
                    e = row_to_estimate(r)
                    slices.append({"state": state, "age_group": "ALL", "educ": educ, **e})
                    state_has_any_deep = True
                    for age in AGE_GROUPS:
                        r2 = get(index, state, age, educ)
                        if r2 is None:
                            continue
                        if r2["reliability"] == "low":
                            excluded_low += 1
                            continue
                        e2 = row_to_estimate(r2)
                        slices.append({"state": state, "age_group": age, "educ": educ, **e2})

            if not state_has_any_deep:
                always_national_states.append(state)

        # Validate party figures against spec table (already literal, sanity only)
        for est in [national_est] + slices:
            if not (0 < est["estimate"] < 1):
                print(f"FATAL: estimate out of (0,1) for {qkey}: {est}", file=sys.stderr)
                sys.exit(1)

        bundle["questions"][qkey] = {
            "funnel_role": qmeta["funnel_role"],
            "lead_disclosure": qmeta["lead_disclosure"],
            "question_text": qmeta["question_text"],
            "positive_label": qmeta["positive_label"],
            "national": national_est,
            "party": qmeta["party"],
            "slices": slices,
        }

        console_lines.append(
            f"{qkey}: {len(slices)} slices, {excluded_low} low-reliability exclusions, "
            f"{len(excluded_states)} states excluded entirely "
            f"({', '.join(sorted(excluded_states)) or 'none'}), "
            f"{len(always_national_states)} states with no deep slices"
        )
        if excluded_states:
            fallback_summary_lines.append(
                f"{qkey}: excluded states -> {', '.join(sorted(excluded_states))}"
            )

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    def dump_size(b):
        return len(json.dumps(b, separators=(",", ":")).encode("utf-8"))

    trimmed = False
    if dump_size(bundle) > 500 * 1024:
        trimmed = True
        # Trim the deepest tier first: slices with all three of
        # state/age_group/educ non-ALL (state x age x educ).
        for qkey, qdata in bundle["questions"].items():
            qdata["slices"] = [
                s for s in qdata["slices"]
                if not (s["state"] != "ALL" and s["age_group"] != "ALL" and s["educ"] != "ALL")
            ]

    with open(OUT_PATH, "w") as f:
        json.dump(bundle, f, separators=(",", ":"))

    if trimmed:
        console_lines.append(
            "NOTE: bundle exceeded 500KB; trimmed state x age x educ (deepest) tier "
            "from all four questions to fit. Final slice counts:"
        )
        for qkey, qdata in bundle["questions"].items():
            console_lines.append(f"  {qkey}: {len(qdata['slices'])} slices (post-trim)")

    size_kb = OUT_PATH.stat().st_size / 1024

    print("=== Extraction report ===")
    for line in console_lines:
        print(line)
    print(f"\nFile size: {size_kb:.1f} KB")
    print("\n=== Plain-English fallback summary ===")
    if trimmed:
        fallback_summary_lines.insert(
            0,
            "The state x age x educ tier (three-way personalization within a state) "
            "was trimmed for size on all four questions. Once a visitor discloses "
            "state plus two demographics, the app falls back to the state x "
            "lead-disclosure figure (or national) rather than a fully personalized "
            "state-level number — that combination is not in the bundle for any "
            "state/question.",
        )
    if fallback_summary_lines:
        for line in fallback_summary_lines:
            print("- " + line)
    else:
        print("- No state/question combos excluded or without deep slices.")


if __name__ == "__main__":
    main()
