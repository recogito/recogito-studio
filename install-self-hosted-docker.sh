#!/bin/bash

set -eo pipefail
trap 'echo "Install FAILED at line $LINENO: $BASH_COMMAND" >&2' ERR

echo "Starting Recogito Studio Install"

# Use the operator's untracked config.local.json when present, otherwise the default config.json
CONFIG_FILE=./docker/config/config.json
if [ -f ./docker/config/config.local.json ]; then
    CONFIG_FILE=./docker/config/config.local.json
fi
echo "Using config file $CONFIG_FILE"

# Clone the client

echo "Cloning recogito-client"

rm -rf ./recogito-client
git clone --single-branch --branch main --depth 1 https://github.com/recogito/recogito-client.git

# Remove the default client config
rm -f ./recogito-client/src/config.json

# Copy the custom config
cp "$CONFIG_FILE" ./recogito-client/src/config.json

# Build the client
cd ./recogito-client

echo "Building Client docker container"

rm -f .env
cp ../docker/.env .env

# Load ENV vars
set -a && source .env && set +a

# Build 
docker build --pull --no-cache -t recogito-studio-client:latest .

# Start docker

echo "Starting Postgres, wait 30 seconds before starting other containers"
cd ../docker

docker network inspect recogito >/dev/null 2>&1 || docker network create recogito

docker compose -f ./docker-compose.postgres.yml up -d

sleep 15

echo "Starting Supabase"
docker compose -f ./docker-compose.yml -f ./docker-compose.client.yml up -d

# Start Portainer
echo "Starting Portainer"
docker compose -f ./docker-compose.portainer.yml up -d

cd ..

# Clone the server src

echo "Cloning recogito-server"

rm -rf ./recogito-server
git clone --single-branch --branch main --depth 1 https://github.com/recogito/recogito-server.git

# Remove the default server config
rm -f ./recogito-server/config.json

# Copy the custom config
cp "$CONFIG_FILE" ./recogito-server/config.json

cd ./recogito-server


npm install

PGSSLMODE=disable npx supabase db push --db-url postgresql://postgres:$POSTGRES_PASSWORD@localhost:$POSTGRES_PORT/postgres --include-all

sleep 5

node ./create-default-groups.js -f ./config.json

# Remove the client and server repos

echo "Removing repositories"

cd ..

rm -rf ./recogito-client/
rm -rf ./recogito-server/

echo "Recogito Studio Installed!"