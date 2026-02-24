#!/bin/bash

echo ">>> Initializing local virtual environment..."
poetry config virtualenvs.in-project true

# 1. Clone MLE-bench if missing
if [ ! -d "testing/temp_bench" ]; then
    git clone https://github.com/openai/mle-bench.git testing/temp_bench
fi

# 2. Setup isolated environment
echo ">>> Installing dependencies..."
poetry add "kaggle<1.7"
poetry add --editable ./testing/temp_bench

mkdir -p testing/tasks

# 3. The Loop
while IFS= read -r comp || [ -n "$comp" ]; do
    [ -z "$comp" ] && continue
    echo "------------------------------------------"
    echo ">>> Extracting Dev Data for: $comp"

    # Prepare and cache the competition data
    poetry run mlebench prepare -c "$comp" || continue

    # Create target folder for the agent to use
    mkdir -p "testing/tasks/$comp"

    # Copy description from the competition definition
    cp "testing/temp_bench/mlebench/competitions/$comp/description.md" "testing/tasks/$comp/" 2>/dev/null || true

    # Copy only the public split of the prepared data (no private/answer key)
    PUBLIC_DIR="$HOME/.cache/mle-bench/data/$comp/prepared/public"
    if [ -d "$PUBLIC_DIR" ]; then
        cp -rn "$PUBLIC_DIR"/. "testing/tasks/$comp/" 2>/dev/null || true

        # Unzip any zip files into a subdirectory named after the zip (e.g. train.zip -> train/)
        for zipfile in "testing/tasks/$comp/"*.zip; do
            [ -f "$zipfile" ] || continue
            zipname=$(basename "$zipfile" .zip)
            mkdir -p "testing/tasks/$comp/$zipname"
            unzip -q -n "$zipfile" -d "testing/tasks/$comp/$zipname/" && rm -f "$zipfile"
        done
    fi

done < <(poetry run python -c "import yaml; [print(c) for c in yaml.safe_load(open('testing/competition_list.yaml'))['competitions']]")

echo ">>> DONE"
