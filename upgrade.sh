#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Starting Recogito Studio Upgrade..."

# --- Pre-flight Checks
if [ ! -f "./docker/.env" ]; then
    echo "Error: ./docker/.env not found! Please run this script from the root of the recogito-studio repository."
    exit 1
fi

# --- Client upgrade

echo "Cloning latest recogito-client..."
git clone --single-branch --branch main --depth 1 https://github.com/recogito/recogito-client.git

echo "Applying updated config.json to client..."
rm -f ./recogito-client/src/config.json
cp ./docker/config/config.json ./recogito-client/src/config.json

cd ./recogito-client

echo "Building new client docker image..."
rm -f .env
cp ../docker/.env .env

# Load env vars for the build process
set -a && source .env && set +a

# Rebuild the docker image
docker build --no-cache -t recogito-studio-client:latest .
cd ..


# --- Server upgrade

echo "Cloning latest recogito-server..."
git clone --single-branch --branch main --depth 1 https://github.com/recogito/recogito-server.git

echo "Applying updated config.json to server..."
rm -f ./recogito-server/config.json
cp ./docker/config/config.json ./recogito-server/config.json

cd ./recogito-server

echo "Installing server dependencies..."
npm install

echo "Applying database migrations..."
# Push any database schema changes to Postgres
PGSSLMODE=disable npx supabase db push --db-url postgresql://postgres:$POSTGRES_PASSWORD@localhost:$POSTGRES_PORT/postgres --include-all

echo "Syncing roles and policies..."
sleep 5 # Give Postgres a moment to settle the new schema
node ./create-default-groups.js -f ./config.json
cd ..


# --- Final steps

echo "Restarting the client container to apply the new image..."
cd ./docker

# Docker compose up with the new client container image
docker compose -f ./docker-compose.yml -f ./docker-compose.client.yml up -d --force-recreate client
cd ..

echo "Cleaning up temporary repositories..."
rm -rf ./recogito-client/
rm -rf ./recogito-server/

echo "Recogito Studio Upgrade Complete!"
