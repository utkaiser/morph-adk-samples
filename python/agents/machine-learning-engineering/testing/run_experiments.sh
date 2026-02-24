#!/bin/bash
# run_all.sh

SUBMISSIONS_JSONL="./testing/results/submissions.jsonl"
mkdir -p ./testing/results
> "$SUBMISSIONS_JSONL"

while IFS= read -r comp || [ -n "$comp" ]; do
    [ -z "$comp" ] && continue

    echo ">>> Running agent on: $comp"

    # Pre-compute the timestamp so we can create RUN_DIR before the run starts
    # and write logs directly into it. The timestamp is also passed into the
    # agent's state so it uses the same directory name.
    TIMESTAMP=$(date +"%m-%d-%Y-%H-%M-%S")
    RUN_DIR="./testing/results/${comp}_${TIMESTAMP}"
    mkdir -p "$RUN_DIR"

    cat > /tmp/mle_input.json <<EOF
{
  "state": {
    "data_dir": "./testing/tasks/",
    "task_name": "$comp",
    "results_dir": "./testing/results/",
    "timestamp": "$TIMESTAMP"
  },
  "queries": [
    "execute the task"
  ]
}
EOF

    # Point agent.log at the live ADK log so it can be tailed during the run
    ln -sfn /tmp/agents_log/agent.latest.log "$RUN_DIR/agent.log"

    # PYTHONUNBUFFERED=1 ensures run.log is written line-by-line, not in chunks
    PYTHONUNBUFFERED=1 poetry run adk run machine_learning_engineering /tmp/mle_input.json \
        2>&1 | tee "$RUN_DIR/run.log"

    # Replace the agent.log symlink with a real copy now that the run is done
    LATEST=$(readlink -f /tmp/agents_log/agent.latest.log 2>/dev/null)
    if [ -n "$LATEST" ] && [ -f "$LATEST" ]; then
        rm -f "$RUN_DIR/agent.log"
        cp "$LATEST" "$RUN_DIR/agent.log"
    fi
    echo ">>> Logs saved to: $RUN_DIR"

    # Find the most recently created submission.csv in the timestamped run directory
    SUBMISSION=$(find "$RUN_DIR" -name "submission.csv" -path "*/final/*" 2>/dev/null | sort | tail -1)

    if [ -n "$SUBMISSION" ]; then
        echo "{\"competition_id\": \"$comp\", \"submission_path\": \"$SUBMISSION\"}" >> "$SUBMISSIONS_JSONL"
    else
        echo ">>> WARNING: No submission.csv found for $comp."
    fi

    echo "------------------------------------------"
    # echo ">>> Waiting 30 seconds to reset quota..."
    # sleep 30
    
done < <(poetry run python -c "import yaml; [print(c) for c in yaml.safe_load(open('testing/competition_list.yaml'))['competitions']]")

echo ""
echo ">>> All runs complete. Submissions recorded at: $SUBMISSIONS_JSONL"
echo ">>> Run ./evaluate_submissions.sh to grade results."
