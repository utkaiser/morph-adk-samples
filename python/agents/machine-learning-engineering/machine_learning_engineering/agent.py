"""Demonstration of Machine Learning Engineering Agent using Agent Development Kit"""

import json
import os

from google.adk import agents
from google.adk.agents import callback_context as callback_context_module
from google.genai import types

from machine_learning_engineering import prompt
from machine_learning_engineering.shared_libraries import common_util
from machine_learning_engineering.sub_agents.ensemble import (
    agent as ensemble_agent_module,
)
from machine_learning_engineering.sub_agents.initialization import (
    agent as initialization_agent_module,
)
from machine_learning_engineering.sub_agents.refinement import (
    agent as refinement_agent_module,
)
from machine_learning_engineering.sub_agents.submission import (
    agent as submission_agent_module,
)


def save_state(
    callback_context: callback_context_module.CallbackContext,
) -> types.Content | None:
    """Saves the final state to the timestamped run directory."""
    results_dir = callback_context.state.get("results_dir", "")
    task_name = callback_context.state.get("task_name", "")
    timestamp = callback_context.state.get("timestamp", "")
    run_cwd = os.path.join(results_dir, f"{task_name}_{timestamp}")
    os.makedirs(run_cwd, exist_ok=True)
    with open(os.path.join(run_cwd, "final_state.json"), "w") as f:
        json.dump(callback_context.state.to_dict(), f, indent=2)
    return None


mle_pipeline_agent = agents.SequentialAgent(
    name="mle_pipeline_agent",
    sub_agents=[
        initialization_agent_module.initialization_agent,
        refinement_agent_module.refinement_agent,
        ensemble_agent_module.ensemble_agent,
        submission_agent_module.submission_agent,
    ],
    description="Executes a sequence of sub-agents for solving the MLE task.",
    after_agent_callback=save_state,
)

# For ADK tools compatibility, the root agent must be named `root_agent`
root_agent = agents.Agent(
    model=os.getenv("ROOT_AGENT_MODEL"),
    name="mle_frontdoor_agent",
    instruction=prompt.FRONTDOOR_INSTRUCTION,
    global_instruction=prompt.SYSTEM_INSTRUCTION,
    sub_agents=[mle_pipeline_agent],
    generate_content_config=types.GenerateContentConfig(temperature=0.01),
)
