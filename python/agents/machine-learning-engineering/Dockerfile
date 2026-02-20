# Use a base image that supports your Python version
FROM python:3.12-slim

# Install system dependencies
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Copy your code
WORKDIR /home/agent
COPY . .

# Install Poetry and dependencies
RUN pip install poetry && poetry install

# Entrypoint script to run your ADK agent
ENTRYPOINT ["/bin/bash", "/home/agent/mle_wrapper.sh"]