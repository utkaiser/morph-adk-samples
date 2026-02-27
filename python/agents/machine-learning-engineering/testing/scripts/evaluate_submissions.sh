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
import json, glob, os, sys, subprocess, io, csv, bisect

MLEBENCH_DIR = "./testing/temp_bench/mlebench"

def get_leaderboard_scores(competition_id):
    """Read leaderboard CSV, handling git-lfs pointers."""
    lb_path = os.path.join(MLEBENCH_DIR, "competitions", competition_id, "leaderboard.csv")
    if not os.path.exists(lb_path):
        return []
    raw = open(lb_path, "rb").read()
    if raw.startswith(b"version https://git-lfs.github.com"):
        result = subprocess.run(
            ["git", "lfs", "smudge", "--skip"],
            input=raw, capture_output=True, cwd=MLEBENCH_DIR
        )
        content = result.stdout.decode()
    else:
        content = raw.decode()
    reader = csv.DictReader(io.StringIO(content))
    scores = [float(r["score"]) for r in reader if r.get("hasScore") == "True" and r.get("score")]
    return scores

def get_rank(score, scores, is_lower_better):
    """Return 1-based rank of score among sorted leaderboard scores."""
    if not scores:
        return None, 0
    if is_lower_better:
        sorted_scores = sorted(scores)
        rank = bisect.bisect_right(sorted_scores, score)
    else:
        sorted_desc = sorted(scores, reverse=True)
        rank = next((i + 1 for i, s in enumerate(sorted_desc) if score >= s), len(sorted_desc) + 1)
    return rank, len(scores)

reports = sorted(glob.glob("./testing/results/grading/*_grading_report.json"))
if not reports:
    print("No grading report found.")
    sys.exit(0)

with open(reports[-1]) as f:
    data = json.load(f)

rows = data["competition_reports"]

# Pre-compute ranks
rank_strs = []
for r in rows:
    if r["score"] is not None:
        scores = get_leaderboard_scores(r["competition_id"])
        is_lower = r.get("is_lower_better", True)
        rank, total_entries = get_rank(r["score"], scores, is_lower)
        rank_strs.append(f"{rank}/{total_entries}" if rank else "N/A")
    else:
        rank_strs.append("N/A")

# Column widths
col_comp   = max(len("Competition"),    max(len(r["competition_id"]) for r in rows))
col_score  = max(len("Score"),          max(len(f"{r['score']:.5f}") if r["score"] is not None else len("N/A") for r in rows))
col_median = max(len("Median"),         max(len(f"{r['median_threshold']:.5f}") if r["median_threshold"] is not None else len("N/A") for r in rows))
col_medal  = len("Medal")
col_beat   = len(">Median")
col_rank   = max(len("Rank"), max(len(s) for s in rank_strs))

sep = f"+-{'-'*col_comp}-+-{'-'*col_score}-+-{'-'*col_median}-+-{'-'*col_medal}-+-{'-'*col_beat}-+-{'-'*col_rank}-+"
header = f"| {'Competition':<{col_comp}} | {'Score':<{col_score}} | {'Median':<{col_median}} | {'Medal':<{col_medal}} | {'>Median':<{col_beat}} | {'Rank':<{col_rank}} |"

print(sep)
print(header)
print(sep)

for r, rank_str in zip(rows, rank_strs):
    score  = f"{r['score']:.5f}"  if r["score"]  is not None else "N/A"
    median = f"{r['median_threshold']:.5f}" if r["median_threshold"] is not None else "N/A"
    medal  = ("Gold" if r["gold_medal"] else "Silver" if r["silver_medal"] else "Bronze" if r["bronze_medal"] else "-")
    beat   = "Yes" if r["above_median"] else "No"
    print(f"| {r['competition_id']:<{col_comp}} | {score:<{col_score}} | {median:<{col_median}} | {medal:<{col_medal}} | {beat:<{col_beat}} | {rank_str:<{col_rank}} |")

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
