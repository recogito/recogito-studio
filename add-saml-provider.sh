#!/bin/bash

# Registers a SAML identity provider with the Supabase auth service.
#
# Usage:
#   ./add-saml-provider.sh <metadata_url> <domain>[,<domain>...] [email_attribute]
#
# Example:
#   ./add-saml-provider.sh https://idp.university.edu/metadata university.edu mail

set -eo pipefail

if [ ! -f "./docker/.env" ]; then
    echo "Error: ./docker/.env not found! Please run this script from the root of the recogito-studio repository."
    exit 1
fi

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <metadata_url> <domain>[,<domain>...] [email_attribute]"
    exit 1
fi

METADATA_URL="$1"
DOMAINS="$2"
EMAIL_ATTRIBUTE="${3:-email}"

set -a && source ./docker/.env && set +a

if [ "$SAML_ENABLED" != "true" ]; then
    echo "Error: SAML_ENABLED is not true in ./docker/.env. Enable SAML and restart the auth container first."
    exit 1
fi

# "a.edu,b.edu" -> "a.edu","b.edu"
DOMAINS_JSON="\"${DOMAINS//,/\",\"}\""

curl --fail-with-body -sS -X POST "${API_EXTERNAL_URL}/auth/v1/admin/sso/providers" \
    -H "apikey: ${SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
        \"type\": \"saml\",
        \"metadata_url\": \"${METADATA_URL}\",
        \"domains\": [${DOMAINS_JSON}],
        \"attribute_mapping\": { \"keys\": { \"email\": { \"name\": \"${EMAIL_ATTRIBUTE}\" } } }
    }"
echo
