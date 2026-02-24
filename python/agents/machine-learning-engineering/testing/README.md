# Testing

All scripts and configuration for running and evaluating the ML Engineering agent against Kaggle competitions live here. Run all scripts from the **project root**.

## How it works

Each competition is split into two parts: what the agent can see, and what is kept hidden for grading.

**What the agent sees — `testing/tasks/<competition>/`**

`install_testing_env.sh` copies only the public split of each competition here. This includes the training data, a sample submission file, and the task description. The agent uses this folder as its workspace: it reads the data, trains a model, and writes a `submission.csv`.

**What is hidden — `~/.cache/mle-bench/data/<competition>/prepared/private/`**

The answer key (ground truth labels for the test set) is downloaded by `mlebench prepare` but stays in the local cache outside the project. The agent never has access to this folder. This mirrors how real Kaggle competitions work: competitors submit predictions without seeing the answers.

**Grading**

`evaluate_submissions.sh` passes the agent's `submission.csv` files to `mlebench grade`, which compares them against the hidden answer key and produces a grading report in `testing/results/grading/`.

## Interface with the rest of the repo

The only line that connects testing to the agent implementation is in `run_experiments.sh`:

```bash
poetry run adk run machine_learning_engineering /tmp/mle_input.json
```

This invokes the `machine_learning_engineering` agent (defined in `../machine_learning_engineering/`) with a JSON payload that tells it which task to solve and where to read/write data. To benchmark a different agent, replace this line with whatever command runs it, as long as it consumes the same input JSON and writes a `submission.csv` under `testing/results/`.

## Scripts

| Script | Purpose |
|---|---|
| `install_testing_env.sh` | One-time setup: clones mle-bench, installs dependencies, and populates `testing/tasks/` with the public competition data |
| `run_experiments.sh` | Runs the agent on every competition listed in `competition_list.yaml` |
| `evaluate_submissions.sh` | Grades the agent's submissions against the hidden answer key (run after `run_experiments.sh`) |

## Configuration

**`competition_list.yaml`** — the list of Kaggle competitions to run. Uncomment entries to include them in a run.

## Usage

```bash
# 1. Set up the environment and download competition data
./testing/install_testing_env.sh

# 2. Run the agent on all competitions
./testing/run_experiments.sh

# 3. Grade the results
./testing/evaluate_submissions.sh
```

## File reference

**Scripts**

- [install_testing_env.sh](testing/install_testing_env.sh) — Clones the `mle-bench` repo into `testing/temp_bench/`, installs it as a local editable package, then for each competition in `competition_list.yaml` runs `mlebench prepare` (which downloads data into `~/.cache/mle-bench/`) and copies the public split into `testing/tasks/<competition>/`.
- [run_experiments.sh](testing/run_experiments.sh) — Iterates over competitions, invokes the agent via `adk run`, and appends the path of each resulting `submission.csv` to `testing/results/submissions.jsonl`.
- [evaluate_submissions.sh](testing/evaluate_submissions.sh) — Reads `submissions.jsonl`, calls `mlebench grade` on each entry, writes per-competition JSON reports to `testing/results/grading/`, then prints a summary table (score, median threshold, medal, beat-median flag).

**Config**

- [competition_list.yaml](testing/competition_list.yaml) — YAML list of Kaggle competition slugs. Comment/uncomment lines to control which competitions are included in a run.

**Folders created**

| Folder | Created by | Contents |
|---|---|---|
| `testing/temp_bench/` | `install_testing_env.sh` | Full `mle-bench` git clone (source of competition definitions and grading logic) |
| `~/.cache/mle-bench/data/<competition>/` | `install_testing_env.sh` (via `mlebench prepare`) | Raw downloaded data, split into `public/` and `private/` (answer key) |
| `testing/tasks/<competition>/` | `install_testing_env.sh` | Public split only: training data (unzipped), `description.md`, sample submission |
| `testing/results/<competition>/` | `run_experiments.sh` (via the agent) | Agent work dir; contains the final `submission.csv` |
| `testing/results/grading/` | `evaluate_submissions.sh` | Per-run `*_grading_report.json` files with scores and medal thresholds |
