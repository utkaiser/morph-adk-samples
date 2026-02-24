#!/bin/bash
# evaluate_submissions.sh

SUBMISSIONS_JSONL="./testing/results/submissions.jsonl"

if [ ! -f "$SUBMISSIONS_JSONL" ]; then
    echo ">>> ERROR: $SUBMISSIONS_JSONL not found. Run run_experiments.sh first."
    exit 1
fi

echo ">>> Grading individual submissions..."
while IFS= read -r line; do
    comp=$(echo "$line" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['competition_id'])")
    submission=$(echo "$line" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['submission_path'])")

    if [ -f "$submission" ]; then
        echo ">>> Grading $comp with: $submission"
        poetry run mlebench grade-sample "$submission" "$comp"
    else
        echo ">>> WARNING: Submission file not found: $submission"
    fi

    echo "------------------------------------------"
done < "$SUBMISSIONS_JSONL"

echo ""
echo ">>> Grading all submissions as batch..."
poetry run mlebench grade --submission "$SUBMISSIONS_JSONL" --output-dir ./testing/results/grading
echo ">>> Grading complete. Results at: ./testing/results/grading"

echo ""
poetry run python3 - <<'EOF'
import json, glob, os, sys

reports = sorted(glob.glob("./testing/results/grading/*_grading_report.json"))
if not reports:
    print("No grading report found.")
    sys.exit(0)

with open(reports[-1]) as f:
    data = json.load(f)

rows = data["competition_reports"]

# Column widths
col_comp   = max(len("Competition"),    max(len(r["competition_id"]) for r in rows))
col_score  = max(len("Score"),          max(len(f"{r['score']:.5f}") if r["score"] is not None else len("N/A") for r in rows))
col_median = max(len("Median"),         max(len(f"{r['median_threshold']:.5f}") if r["median_threshold"] is not None else len("N/A") for r in rows))
col_medal  = len("Medal")
col_beat   = len(">Median")

sep = f"+-{'-'*col_comp}-+-{'-'*col_score}-+-{'-'*col_median}-+-{'-'*col_medal}-+-{'-'*col_beat}-+"
header = f"| {'Competition':<{col_comp}} | {'Score':<{col_score}} | {'Median':<{col_median}} | {'Medal':<{col_medal}} | {'>Median':<{col_beat}} |"

print(sep)
print(header)
print(sep)

for r in rows:
    score  = f"{r['score']:.5f}"  if r["score"]  is not None else "N/A"
    median = f"{r['median_threshold']:.5f}" if r["median_threshold"] is not None else "N/A"
    medal  = ("Gold" if r["gold_medal"] else "Silver" if r["silver_medal"] else "Bronze" if r["bronze_medal"] else "-")
    beat   = "Yes" if r["above_median"] else "No"
    print(f"| {r['competition_id']:<{col_comp}} | {score:<{col_score}} | {median:<{col_median}} | {medal:<{col_medal}} | {beat:<{col_beat}} |")

print(sep)

total   = data["total_runs"]
ab_med  = data["total_above_median"]
medals  = data["total_medals"]
gold    = data["total_gold_medals"]
silver  = data["total_silver_medals"]
bronze  = data["total_bronze_medals"]
pct     = (ab_med / total * 100) if total else 0.0

valid_scores = [r["score"] for r in rows if r["score"] is not None]
avg_score = sum(valid_scores) / len(valid_scores) if valid_scores else None
avg_str = f"{avg_score:.5f}" if avg_score is not None else "N/A"

print(f"\nAverage score: {avg_str} | Above median: {ab_med}/{total} ({pct:.1f}%) | Medals: {medals} (Gold {gold}, Silver {silver}, Bronze {bronze})")
EOF
