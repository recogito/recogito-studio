#!/bin/bash

# Deploys the project import/export tasks from recogito-client to Trigger.dev.
#
# install-self-hosted-docker.sh and upgrade.sh run this automatically. Run it by hand to
# retry a failed deploy:
#
#   ./deploy-trigger-tasks.sh [path/to/recogito-client]
#
# Without a path, the script clones recogito-client into a temporary directory.
# Settings are read from docker/.env. The deploy is skipped unless TRIGGER_ACCESS_TOKEN is set.

set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$REPO_ROOT/docker/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found." >&2
    exit 1
fi

set -a && source "$ENV_FILE" && set +a

if [ -z "$TRIGGER_ACCESS_TOKEN" ]; then
    echo "Skipping Trigger.dev task deploy: TRIGGER_ACCESS_TOKEN is not set in docker/.env."
    echo "Project import/export needs the tasks deployed. Set the token and run ./deploy-trigger-tasks.sh, or deploy them manually."
    exit 0
fi

if [ -z "$TRIGGER_PROJECT_ID" ] || [ "$TRIGGER_PROJECT_ID" = "proj_abcdefg" ]; then
    echo "Error: TRIGGER_ACCESS_TOKEN is set, but TRIGGER_PROJECT_ID in docker/.env is not a real project ref." >&2
    exit 1
fi

# The deploy copies the service key into the Trigger.dev project for the tasks to use
export SUPABASE_SERVICE_KEY="${SUPABASE_SERVICE_KEY:-$SERVICE_ROLE_KEY}"
if [ -z "$SUPABASE_SERVICE_KEY" ]; then
    echo "Error: SUPABASE_SERVICE_KEY is not set in docker/.env." >&2
    exit 1
fi

# The CLI deploys to Trigger.dev Cloud unless TRIGGER_API_URL points at a self-hosted instance
if [ -z "$TRIGGER_API_URL" ] && [ -n "$TRIGGER_SERVER_URL" ]; then
    export TRIGGER_API_URL="$TRIGGER_SERVER_URL"
fi

CLIENT_DIR="$1"
if [ -z "$CLIENT_DIR" ]; then
    TEMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TEMP_DIR"' EXIT
    CLIENT_DIR="$TEMP_DIR/recogito-client"
    echo "Cloning recogito-client..."
    git clone --single-branch --branch main --depth 1 https://github.com/recogito/recogito-client.git "$CLIENT_DIR"
fi

cd "$CLIENT_DIR"

# Use the CLI version that matches the client's Trigger.dev SDK
TRIGGER_CLI_VERSION="$(node -p "require('./package.json').dependencies['@trigger.dev/sdk'].replace(/^[^0-9]*/, '')")"

echo "Installing client dependencies..."
npm install

echo "Deploying tasks to ${TRIGGER_API_URL:-Trigger.dev Cloud} (project $TRIGGER_PROJECT_ID) with trigger.dev@$TRIGGER_CLI_VERSION..."
# CI=true stops the CLI from prompting or opening a browser
CI=true npx --yes "trigger.dev@$TRIGGER_CLI_VERSION" deploy -c ./trigger.config.ts --skip-update-check

echo "Trigger.dev tasks deployed."
