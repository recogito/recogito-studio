#!/bin/bash

# Creates docker/.env from docker/.env.example and fills in the values that can
# be generated: random secrets, the JWT secret and its API keys, and the
# variables that duplicate another variable.
#
# Safe to re-run. A value is only written when it is empty or still matches
# .env.example, so anything you have set yourself is left alone.
#
# Also run it after an upgrade: variables that have been renamed (RENAMED_VARS
# below) are renamed in docker/.env, and variables that are in .env.example but
# missing from docker/.env are appended with their .env.example values and listed.
#
# Requires openssl and node.

set -eo pipefail

usage() {
    cat <<'EOF'
Usage: ./env.sh [options]

Populates your `.env` file from `.env.example`.

This script does not overwrite values you've already set.

Options:
  --site-url <url>   Set SITE_URL, e.g. https://client.example.com
  --api-url <url>    Set API_EXTERNAL_URL and the variables that copy it,
                     e.g. https://server.example.com
  --saml             Generate SAML_PRIVATE_KEY and set SAML_ENABLED=true
  -h, --help         Show this help
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXAMPLE_FILE="$SCRIPT_DIR/docker/.env.example"
ENV_FILE="$SCRIPT_DIR/docker/.env"
DB_DATA_DIR="$SCRIPT_DIR/docker/volumes/db/data"

# Variables that have been renamed in Recogito releases
RENAMED_VARS="
    MINIO_ROOT_USER:S3_ACCESS_KEY
    MINIO_ROOT_PASSWORD:S3_SECRET_KEY
    KONG_HTTP_PORT:API_GW_HTTP_PORT
    IMGPROXY_ENABLE_WEBP_DETECTION:IMGPROXY_AUTO_WEBP
"

SITE_URL_ARG=""
API_URL_ARG=""
SAML=false

while [ $# -gt 0 ]; do
    case "$1" in
        --site-url|--api-url)
            if [ -z "${2:-}" ]; then
                echo "Error: $1 needs a value." >&2
                exit 1
            fi
            if [ "$1" = "--site-url" ]; then SITE_URL_ARG="${2%/}"; else API_URL_ARG="${2%/}"; fi
            shift
            ;;
        --saml) SAML=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: unknown option $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

for CMD in openssl node; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "Error: $CMD is required but was not found." >&2
        exit 1
    fi
done

if [ ! -f "$EXAMPLE_FILE" ]; then
    echo "Error: $EXAMPLE_FILE not found." >&2
    exit 1
fi

TMP_FILE=""
trap 'rm -f "$TMP_FILE"' EXIT

# --- Helpers

# get_val <file> <key>: the value of the first KEY= line, without surrounding quotes
get_val() {
    local value
    value="$(grep -m1 "^$2=" "$1" | cut -d= -f2-)" || true
    value="${value%\"}"
    value="${value#\"}"
    printf '%s' "$value"
}

# rewrite_env <awk program>: run docker/.env through awk and save the result
rewrite_env() {
    TMP_FILE="$(mktemp "$ENV_FILE.XXXXXX")"
    awk "$1" "$ENV_FILE" > "$TMP_FILE"
    # Write through the existing file to keep its owner and permissions
    cat "$TMP_FILE" > "$ENV_FILE"
    rm -f "$TMP_FILE"
    TMP_FILE=""
}

# set_val <key> <value>: replace the KEY= line in docker/.env, or append it
set_val() {
    KEY="$1" VALUE="$2" rewrite_env '
        BEGIN { prefix = ENVIRON["KEY"] "=" }
        !done && index($0, prefix) == 1 { print prefix ENVIRON["VALUE"]; done = 1; next }
        { print }
        END { if (!done) print prefix ENVIRON["VALUE"] }
    '
    CHANGED="$CHANGED $1"
}

# rename_var <old> <new>: rename the OLD= line, keeping its value, and point
# any ${OLD} references in other values at the new name
rename_var() {
    OLD="$1" NEW="$2" rewrite_env '
        BEGIN { old = ENVIRON["OLD"]; new = ENVIRON["NEW"] }
        index($0, old "=") == 1 { $0 = new substr($0, length(old) + 1) }
        !/^[[:space:]]*#/ { gsub("\\$\\{" old "\\}", "${" new "}") }
        { print }
    '
}

# True when the value is empty or is still the one from .env.example
is_unset() {
    local current
    current="$(get_val "$ENV_FILE" "$1")"
    [ -z "$current" ] || [ "$current" = "$(get_val "$EXAMPLE_FILE" "$1")" ]
}

# fill <key> <command...>: set the key to the command's output if it is unset
fill() {
    local key="$1"
    shift
    if is_unset "$key"; then
        set_val "$key" "$("$@")"
    fi
}

# Signs the anon and service_role JWTs with JWT_SECRET, valid for 10 years
sign_jwt() {
    JWT_SECRET="$1" ROLE="$2" node -e '
        const c = require("crypto");
        const iat = Math.floor(Date.now() / 1000);
        const exp = iat + 60 * 60 * 24 * 365 * 10;
        const enc = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
        const data = enc({ alg: "HS256", typ: "JWT" }) +
            "." + enc({ role: process.env.ROLE, iss: "supabase", iat, exp });
        console.log(data + "." +
            c.createHmac("sha256", process.env.JWT_SECRET).update(data).digest("base64url"));
    '
}

# Base64-encoded DER PKCS#1 RSA key. OpenSSL 3 needs -traditional to produce
# PKCS#1; LibreSSL and OpenSSL 1.x produce it by default and reject the flag.
saml_key() {
    local pem
    pem="$(openssl genrsa 2048 2>/dev/null)"
    {
        printf '%s\n' "$pem" | openssl rsa -outform DER -traditional 2>/dev/null ||
            printf '%s\n' "$pem" | openssl rsa -outform DER 2>/dev/null
    } | base64 | tr -d '\n'
}

# --- Create docker/.env

CHANGED=""

if [ -f "$ENV_FILE" ]; then
    echo "docker/.env already exists"
else
    cp "$EXAMPLE_FILE" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "docker/.env doesn't exist yet. Copying from docker/.env.example"
fi

# --- Renamed variables

# Runs before the missing-variable check, so a renamed variable keeps its value
# instead of being added again with the .env.example default.
RENAMED=""
for PAIR in $RENAMED_VARS; do
    OLD_KEY="${PAIR%%:*}"
    NEW_KEY="${PAIR##*:}"
    grep -q "^$OLD_KEY=" "$ENV_FILE" || continue
    if grep -q "^$NEW_KEY=" "$ENV_FILE"; then
        echo "$OLD_KEY is no longer used and $NEW_KEY is already set. You can remove $OLD_KEY from docker/.env."
    else
        rename_var "$OLD_KEY" "$NEW_KEY"
        RENAMED="$RENAMED $OLD_KEY:$NEW_KEY"
    fi
done

if [ -n "$RENAMED" ]; then
    echo
    echo "The following variables have been automatically renamed for the latest version of Recogito:"
    for PAIR in $RENAMED; do
        echo "  ${PAIR%%:*} -> ${PAIR##*:}"
    done
fi

# --- Variables added to .env.example since docker/.env was created

# Append each one with its .env.example value, so later steps and the report
# below treat it like any other variable that is still at its default.
MISSING=""
for KEY in $(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$EXAMPLE_FILE" | tr -d '='); do
    if ! grep -qE "^[[:space:]]*(export[[:space:]]+)?$KEY=" "$ENV_FILE"; then
        MISSING="$MISSING $KEY"
    fi
done

if [ -n "$MISSING" ]; then
    {
        # Start on a new line even if the file doesn't end with one
        [ -z "$(tail -c 1 "$ENV_FILE")" ] || echo
        echo
        echo "# Added by env.sh from .env.example on $(date +%Y-%m-%d)"
        for KEY in $MISSING; do
            grep -m1 "^$KEY=" "$EXAMPLE_FILE"
        done
    } >> "$ENV_FILE"

    echo
    echo "The following variables were not found in docker/.env. They have been added to the end with their .env.example values:"
    for KEY in $MISSING; do
        echo "  $KEY"
    done
    echo
fi

# --- Secrets

# These are stored in the database the first time it starts. Changing them in
# .env afterwards locks the services out, so leave them alone once a database exists.
if [ -e "$DB_DATA_DIR" ]; then
    echo "Found an existing database in docker/volumes/db/data. Skipping DB secret generation."
else
    fill POSTGRES_PASSWORD openssl rand -hex 24
    fill VAULT_ENC_KEY openssl rand -hex 16
    fill INVITE_CRYPTO_KEY openssl rand -base64 32
    fill ROOM_SECRET openssl rand -base64 24
    fill POOLER_TENANT_ID echo recogito

    # A new JWT secret invalidates any existing keys, so they are re-signed with it
    if is_unset JWT_SECRET; then
        set_val JWT_SECRET "$(openssl rand -base64 36)"
        NEW_JWT_SECRET=true
    fi
    JWT_SECRET_VALUE="$(get_val "$ENV_FILE" JWT_SECRET)"
    if [ "${NEW_JWT_SECRET:-false}" = true ] || is_unset ANON_KEY; then
        set_val ANON_KEY "$(sign_jwt "$JWT_SECRET_VALUE" anon)"
        set_val PUBLIC_SUPABASE_API_KEY "$(get_val "$ENV_FILE" ANON_KEY)"
    fi
    if [ "${NEW_JWT_SECRET:-false}" = true ] || is_unset SERVICE_ROLE_KEY; then
        set_val SERVICE_ROLE_KEY "$(sign_jwt "$JWT_SECRET_VALUE" service_role)"
        set_val SUPABASE_SERVICE_KEY "$(get_val "$ENV_FILE" SERVICE_ROLE_KEY)"
    fi
fi

# --- Duplicated variables

fill PUBLIC_SUPABASE_API_KEY get_val "$ENV_FILE" ANON_KEY
fill SUPABASE_SERVICE_KEY get_val "$ENV_FILE" SERVICE_ROLE_KEY

# --- URLs

if [ -n "$SITE_URL_ARG" ]; then
    set_val SITE_URL "$SITE_URL_ARG"
fi

if [ -n "$API_URL_ARG" ]; then
    set_val API_EXTERNAL_URL "$API_URL_ARG"
    set_val PUBLIC_SUPABASE "$API_URL_ARG"
    set_val PUBLIC_IIIF_CANTALOUPE_PATH "$API_URL_ARG/iiif/2"
elif ! is_unset API_EXTERNAL_URL; then
    # API_EXTERNAL_URL was edited by hand: fill in the copies that haven't been
    API_URL="$(get_val "$ENV_FILE" API_EXTERNAL_URL)"
    fill PUBLIC_SUPABASE echo "$API_URL"
    fill PUBLIC_IIIF_CANTALOUPE_PATH echo "$API_URL/iiif/2"
fi

# --- SAML

if [ "$SAML" = true ]; then
    if [ -z "$(get_val "$ENV_FILE" SAML_PRIVATE_KEY)" ]; then
        set_val SAML_PRIVATE_KEY "$(saml_key)"
    fi
    if [ "$(get_val "$ENV_FILE" SAML_ENABLED)" != "true" ]; then
        set_val SAML_ENABLED true
    fi
fi

# --- Report

if [ -n "$CHANGED" ]; then
    echo
    echo "Automatically populated in docker/.env:"
    for KEY in $CHANGED; do
        echo "  $KEY"
    done
elif [ -z "$MISSING" ] && [ -z "$RENAMED" ]; then
    echo "No automatic variable updates needed. docker/.env is unchanged."
fi

# Values only the operator can choose, still empty or at their .env.example default
REMAINING=""
for KEY in \
    DASHBOARD_PASSWORD ORG_ADMIN_PW S3_ACCESS_KEY S3_SECRET_KEY \
    PGADMIN_ADMIN_EMAIL PGADMIN_ADMIN_PASSWORD \
    SITE_URL API_EXTERNAL_URL PUBLIC_SUPABASE PUBLIC_IIIF_CANTALOUPE_PATH \
    TRIGGER_PROJECT_ID TRIGGER_SECRET_KEY \
    POSTGRES_PASSWORD JWT_SECRET ANON_KEY SERVICE_ROLE_KEY VAULT_ENC_KEY \
    INVITE_CRYPTO_KEY ROOM_SECRET POOLER_TENANT_ID; do
    if is_unset "$KEY"; then
        REMAINING="$REMAINING $KEY"
    fi
done

if [ -n "$REMAINING" ]; then
    echo
    echo "The following credentials are still using default values:"
    for KEY in $REMAINING; do
        echo "  $KEY"
    done
    echo "Updating these values in ./docker/.env is highly recommended."
fi
