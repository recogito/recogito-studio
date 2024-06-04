#!/bin/bash

echo "Starting Recogito Studio Install"

# Load ENV vars

set -o allexport
source ./docker/.env
set +o allexport

# Clone the client

echo "Cloning recogito-client"

git clone --depth 1 https://github.com/recogito/recogito-client.git

# Remove the default client config
rm -f ./recogito-client/src/config.json

# Copy the custom config
cp ./docker/config/config.json ./recogito-client/src/config.json

# Build the client
cd ./recogito-client

echo "Building Client docker container"

rm .env
cp ../docker/.env .env

docker build --no-cache -t recogito-studio-client:latest .


# Start docker

echo "Starting Supabase"
cd ../docker

docker compose pull

docker compose up -d

docker compose -f docker-compose.client.yml

cd ..

# Clone the server src

echo "Cloning recogito-server"

git clone --depth 1 https://github.com/recogito/recogito-server.git

# Add supabase
npm i supabase --save-dev

# Remove the default server config
rm -f ./recogito-server/config.json

# Copy the custom config
cp ./docker/config/config.json ./recogito-server/config.json

cd ./recogito-server


npm install

npx supabase db push --db-url postgresql://postgres:$POSTGRES_PASSWORD@localhost:$POSTGRES_PORT/postgres

sleep 5

node ./create-default-groups.js -f ./config.json

