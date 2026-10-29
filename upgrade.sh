#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
trap 'echo "Upgrade FAILED at line $LINENO: $BASH_COMMAND. Check container status with \"docker ps -a\" and \"docker logs <container>\"." >&2' ERR

echo "Starting Recogito Studio Upgrade..."

# --- Pre-flight Checks
if [ ! -f "./docker/.env" ]; then
    echo "Error: ./docker/.env not found! Please run this script from the root of the recogito-studio repository."
    exit 1
fi

# Use the operator's untracked config.local.json when present, otherwise the default config.json
CONFIG_FILE=./docker/config/config.json
if [ -f ./docker/config/config.local.json ]; then
    CONFIG_FILE=./docker/config/config.local.json
fi
echo "Using config file $CONFIG_FILE"

# --- Client upgrade

echo "Cloning latest recogito-client..."
git clone --single-branch --branch main --depth 1 https://github.com/recogito/recogito-client.git

echo "Applying updated config.json to client..."
rm -f ./recogito-client/src/config.json
cp "$CONFIG_FILE" ./recogito-client/src/config.json

cd ./recogito-client

echo "Building new client docker image..."
rm -f .env
cp ../docker/.env .env

# Load env vars for the build process
set -a && source .env && set +a

# Rebuild the docker image
docker build --pull --no-cache -t recogito-studio-client:latest .
cd ..

# --- Server setup

# Installed before the backup so the dump uses the server's pinned Supabase CLI
echo "Cloning latest recogito-server..."
git clone --single-branch --branch main --depth 1 https://github.com/recogito/recogito-server.git

echo "Applying updated config.json to server..."
rm -f ./recogito-server/config.json
cp "$CONFIG_FILE" ./recogito-server/config.json

cd ./recogito-server

echo "Installing server dependencies..."
npm install

cd ..


# --- Database backup

# Dump the database before anything changes using the same commands as backup-and-restore.md.
# Set SKIP_DB_BACKUP=true to skip this step, e.g. if you snapshot the whole server before upgrading.
if [ "$SKIP_DB_BACKUP" = "true" ]; then
    echo "Skipping database backup (SKIP_DB_BACKUP=true)"
else
    BACKUP_DIR="$PWD/backups/pre-upgrade-$(date +%Y%m%d-%H%M%S)"
    echo "Backing up database to $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"

    cd ./recogito-server
    DB_URL=postgresql://postgres:$POSTGRES_PASSWORD@localhost:$POSTGRES_PORT/postgres
    PGSSLMODE=disable npx supabase db dump --db-url "$DB_URL" -f "$BACKUP_DIR/roles.sql" --role-only
    PGSSLMODE=disable npx supabase db dump --db-url "$DB_URL" -f "$BACKUP_DIR/schema.sql"
    PGSSLMODE=disable npx supabase db dump --db-url "$DB_URL" -f "$BACKUP_DIR/data.sql" --use-copy --data-only
    PGSSLMODE=disable npx supabase db dump --db-url "$DB_URL" -f "$BACKUP_DIR/history_schema.sql" --schema supabase_migrations
    PGSSLMODE=disable npx supabase db dump --db-url "$DB_URL" -f "$BACKUP_DIR/history_data.sql" --use-copy --data-only --schema supabase_migrations
    cd ..

    # Keep only the 5 most recent pre-upgrade backups
    ls -1d ./backups/pre-upgrade-* | sort -r | tail -n +6 | while read -r OLD_BACKUP; do
        echo "Removing old backup $OLD_BACKUP"
        rm -rf "$OLD_BACKUP"
    done
fi


# --- Stack upgrade

echo "Updating containers to the image versions in the compose files..."
cd ./docker

# Remove Kong if it exists from an old version
docker rm -f supabase-kong 2>/dev/null || true

# Envoy only listens on HTTP; TLS is expected to terminate at the reverse proxy (see nginx.server.example.com)
if grep -q '^KONG_HTTPS_PORT=' .env; then
    echo "Warning: KONG_HTTPS_PORT is set in docker/.env, but the API gateway no longer serves HTTPS."
    echo "         Point your reverse proxy at port ${API_GW_HTTP_PORT:-${KONG_HTTP_PORT:-8000}} (HTTP) instead of ${KONG_HTTPS_PORT}."
fi

docker compose -f ./docker-compose.postgres.yml up -d --wait --wait-timeout 300
COMPOSE_IGNORE_ORPHANS=true docker compose -f ./docker-compose.yml up -d --wait --wait-timeout 300
docker compose -f ./docker-compose.portainer.yml up -d --wait --wait-timeout 300
cd ..


# --- Server upgrade

cd ./recogito-server

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

# The client image tag never changes, so force a recreate to pick up the new build
docker compose -f ./docker-compose.yml -f ./docker-compose.client.yml up -d --wait --wait-timeout 300 --force-recreate client
cd ..

echo "Cleaning up temporary repositories..."
rm -rf ./recogito-client/
rm -rf ./recogito-server/

echo "Recogito Studio Upgrade Complete!"
