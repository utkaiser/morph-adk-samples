#!/usr/bin/env python3
"""
execute_runs.py - Run competitions in parallel.

Each competition from competition_list.yaml gets its own subprocess running
`adk run`, so they all execute concurrently instead of sequentially.

By default the script detaches itself into the background so you can close
your terminal and come back later. Logs go to testing/results/system_logs/.

Usage:
    poetry run python testing/scripts/execute_runs.py [--jobs N] [--no-daemon]

    --jobs N      Max parallel runs (default: all at once)
    --no-daemon   Run in the foreground (useful inside tmux/screen/CI)
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

PT = ZoneInfo("America/Los_Angeles")

import yaml


def daemonize(log_path: Path) -> None:
    """Re-launch this script detached from the terminal and exit the parent."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [sys.executable] + sys.argv + ["--no-daemon"]
    with open(log_path, "w") as log:
        proc = subprocess.Popen(
            cmd,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,  # detaches from controlling terminal
            close_fds=True,
            env={**os.environ, "PYTHONUNBUFFERED": "1"},
        )
    print(f">>> Running in background (PID {proc.pid})")
    print(f">>> Tail logs: tail -f {log_path}")
    sys.exit(0)


def status_monitor(running: set, stop_event: threading.Event, interval: int = 60) -> None:
    """Periodically prints which competitions are still running."""
    while not stop_event.wait(interval):
        still_running = sorted(running)
        if still_running:
            print(f"\n>>> [{datetime.now(PT).strftime('%H:%M:%S')}] Still running ({len(still_running)}):")
            for comp in still_running:
                print(f"      {comp}")


def run_competition(comp: str, run_dir: Path, timestamp: str, running: set) -> dict | None:
    """Run a single competition and return its submission entry, or None."""
    input_data = {
        "state": {
            "data_dir": "./testing/tasks/",
            "task_name": comp,
            "results_dir": "./testing/results/",
            "timestamp": timestamp,
        },
        "queries": ["execute the task"],
    }

    # Each run gets its own temp input file so parallel runs don't clobber each other.
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False, prefix=f"mle_{comp}_"
    ) as f:
        json.dump(input_data, f)
        input_file = f.name

    running.add(comp)
    try:
        with open(run_dir / "run.log", "w") as log:
            subprocess.run(
                [
                    "poetry", "run", "adk", "run", "machine_learning_engineering",
                    "--replay", input_file,
                    "--session_service_uri", "memory://",
                ],
                stdout=log,
                stderr=subprocess.STDOUT,
                env={**os.environ, "PYTHONUNBUFFERED": "1"},
            )
    finally:
        os.unlink(input_file)
        running.discard(comp)

    # Find submission.csv, excluding sample_submission.csv inside input/ dirs.
    submissions = [
        s for s in run_dir.rglob("submission.csv")
        if "input" not in s.parts
    ]

    if submissions:
        return {"competition_id": comp, "submission_path": str(sorted(submissions)[-1])}
    return None


def main():
    parser = argparse.ArgumentParser(description="Run MLE-bench competitions in parallel.")
    parser.add_argument(
        "--jobs", "-j", type=int, default=None,
        help="Max number of parallel runs (default: all at once)",
    )
    parser.add_argument(
        "--no-daemon", action="store_true",
        help="Run in the foreground instead of detaching to the background",
    )
    args = parser.parse_args()

    results_dir = Path("./testing/results")
    timestamp = datetime.now(PT).strftime("%m-%d-%Y-%H-%M-%S")

    if not args.no_daemon:
        daemonize(results_dir / "system_logs" / f"execute_runs_{timestamp}.log")

    with open("testing/competition_list.yaml") as f:
        competitions = yaml.safe_load(f)["competitions"]

    # Pre-create run dirs so we can print all paths upfront.
    run_dirs = {}
    for comp in competitions:
        run_dir = results_dir / f"{comp}_{timestamp}"
        run_dir.mkdir(parents=True, exist_ok=True)
        run_dirs[comp] = run_dir

    print(f">>> Competitions ({len(competitions)}):")
    for comp, run_dir in run_dirs.items():
        print(f"      {comp}")
        print(f"        logs -> {run_dir}/run.log")

    submissions = []
    lock = threading.Lock()
    running: set = set()
    stop_event = threading.Event()

    monitor = threading.Thread(target=status_monitor, args=(running, stop_event), daemon=True)
    monitor.start()

    with ThreadPoolExecutor(max_workers=args.jobs) as executor:
        futures = {
            executor.submit(run_competition, comp, run_dirs[comp], timestamp, running): comp
            for comp in competitions
        }
        for future in as_completed(futures):
            comp = futures[future]
            try:
                result = future.result()
                if result:
                    with lock:
                        submissions.append(result)
            except Exception as e:
                print(f">>> [{comp}] ERROR: {e}")

    stop_event.set()

    submissions_file = results_dir / "submissions.jsonl"
    with open(submissions_file, "w") as f:
        for entry in submissions:
            f.write(json.dumps(entry) + "\n")

    print(f"\n>>> All {len(competitions)} run(s) complete.")
    print(f">>> Submissions: {submissions_file}")
    print(">>> Run testing/scripts/evaluate_submissions.sh to grade results.")


if __name__ == "__main__":
    main()
