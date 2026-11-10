#!/bin/bash

# Manages the SAML identity providers registered with the auth service.
# Requires curl and jq. Arguments take priority over values in the env file.

set -eo pipefail

usage() {
    cat <<EOF
Usage:
  $0 add [options]
  $0 list [options]
  $0 update <provider id> [options]
  $0 delete <provider id> [--yes] [options]

Connection options:
  --env-file <path>         Defaults to docker/.env next to this script
  --url <url>               Providers endpoint. Defaults to localhost on API_GW_HTTP_PORT
  --key <key>               Defaults to SERVICE_ROLE_KEY

Provider options, with the env file variable each one falls back to on add:
  --metadata-url <url>      SAML_METADATA_URL (must be HTTPS)
  --metadata-file <path>    SAML_METADATA_FILE
  --domains <a.edu,b.edu>   SAML_DOMAINS
  --email-attr <name>       SAML_EMAIL_ATTR (defaults to "email")
  --first-name-attr <name>  SAML_FIRST_NAME_ATTR
  --last-name-attr <name>   SAML_LAST_NAME_ATTR

update only changes what you pass as arguments, and ignores these variables.
--domains on update replaces the provider's whole domain list.
EOF
}

die() {
    echo "Error: $1" >&2
    exit 1
}

command -v curl >/dev/null || die "curl is required."
command -v jq >/dev/null || die "jq is required."

COMMAND="${1:-}"
[ $# -gt 0 ] && shift

PROVIDER_ID=""
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/docker/.env"
ENV_FILE_SET=false
ASSUME_YES=false
ARG_URL="" ARG_KEY="" ARG_METADATA_URL="" ARG_METADATA_FILE="" ARG_DOMAINS=""
ARG_EMAIL="" ARG_FIRST="" ARG_LAST=""

while [ $# -gt 0 ]; do
    if [ "$1" = "--yes" ]; then
        ASSUME_YES=true
        shift
        continue
    fi
    if [[ "$1" != --* ]] && [ -z "$PROVIDER_ID" ] && { [ "$COMMAND" = "update" ] || [ "$COMMAND" = "delete" ]; }; then
        PROVIDER_ID="$1"
        shift
        continue
    fi
    [ -n "${2:-}" ] || { usage >&2; die "$1 needs a value."; }
    case "$1" in
        --env-file) ENV_FILE="$2"; ENV_FILE_SET=true ;;
        --url) ARG_URL="$2" ;;
        --key) ARG_KEY="$2" ;;
        --metadata-url) ARG_METADATA_URL="$2" ;;
        --metadata-file) ARG_METADATA_FILE="$2" ;;
        --domains) ARG_DOMAINS="$2" ;;
        --email-attr) ARG_EMAIL="$2" ;;
        --first-name-attr) ARG_FIRST="$2" ;;
        --last-name-attr) ARG_LAST="$2" ;;
        *) usage >&2; die "Unknown option: $1" ;;
    esac
    shift 2
done

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    # Without an env file (--url and --key only) there's no way to tell, so the API reports it
    [ "${SAML_ENABLED:-}" = "true" ] || die "SAML_ENABLED is not true in $ENV_FILE. Set it, add SAML_PRIVATE_KEY and restart the auth container first."
elif [ "$ENV_FILE_SET" = "true" ]; then
    die "Env file not found: $ENV_FILE"
fi

BASE_URL="${ARG_URL:-http://localhost:${API_GW_HTTP_PORT:-${KONG_HTTP_PORT:-8000}}/auth/v1/admin/sso/providers}"
KEY="${ARG_KEY:-$SERVICE_ROLE_KEY}"
[ -n "$KEY" ] || die "No service role key. Set SERVICE_ROLE_KEY or pass --key."

METADATA_URL="$ARG_METADATA_URL"
METADATA_FILE="$ARG_METADATA_FILE"
DOMAINS="$ARG_DOMAINS"
EMAIL_ATTR="$ARG_EMAIL"
FIRST_ATTR="$ARG_FIRST"
LAST_ATTR="$ARG_LAST"

if [ "$COMMAND" = "add" ]; then
    if [ -z "$METADATA_URL$METADATA_FILE" ]; then
        METADATA_URL="$SAML_METADATA_URL"
        METADATA_FILE="$SAML_METADATA_FILE"
    fi
    DOMAINS="${DOMAINS:-$SAML_DOMAINS}"
    EMAIL_ATTR="${EMAIL_ATTR:-${SAML_EMAIL_ATTR:-email}}"
    FIRST_ATTR="${FIRST_ATTR:-$SAML_FIRST_NAME_ATTR}"
    LAST_ATTR="${LAST_ATTR:-$SAML_LAST_NAME_ATTR}"
fi

[ -z "$METADATA_URL" ] || [ -z "$METADATA_FILE" ] || die "Use only one of a metadata URL and a metadata file."
[ -z "$METADATA_FILE" ] || [ -f "$METADATA_FILE" ] || die "Metadata file not found: $METADATA_FILE"

# The key goes in through a curl config so this script doesn't expose it in the process list.
# Prints the response body and fails on HTTP errors. Checks the status itself because
# --fail-with-body needs curl 7.76, newer than Ubuntu 20.04 and Debian 11 ship.
api() {
    local method="$1" path="$2" response status
    shift 2
    response=$(curl -sS -X "$method" "${BASE_URL}${path}" -w '\n%{http_code}' \
        -K <(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"\n' "$KEY" "$KEY") \
        "$@") || return 1
    status="${response##*$'\n'}"
    printf '%s\n' "${response%$'\n'*}"
    [ "$status" -lt 400 ] || { echo "Error: HTTP $status" >&2; return 1; }
}

# Reads the current provider from stdin and writes the request body to stdout.
# GoTrue stores the attribute mapping as one value, so changes merge into the current keys.
build_body() {
    local xml_args=(--arg xml "")
    [ -z "$METADATA_FILE" ] || xml_args=(--rawfile xml "$METADATA_FILE")

    jq -c "${xml_args[@]}" \
        --arg command "$COMMAND" --arg url "$METADATA_URL" --arg domains "$DOMAINS" \
        --arg email "$EMAIL_ATTR" --arg first "$FIRST_ATTR" --arg last "$LAST_ATTR" '
        ({email: $email, first_name: $first, last_name: $last}
            | with_entries(select(.value != "") | .value = {name: .value})) as $changes
        | (.saml.attribute_mapping.keys // {}) as $current
        | (if $command == "add" then {type: "saml"} else {} end)
        + (if $url != "" then {metadata_url: $url} else {} end)
        + (if $xml != "" then {metadata_xml: $xml} else {} end)
        + (if $domains != ""
            then {domains: ($domains | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != "")))}
            else {} end)
        + (if ($changes | length) > 0
            then {attribute_mapping: {keys: ($current + $changes)}}
            else {} end)'
}

# Pretty-prints responses without the long metadata XML. Other bodies pass through unchanged.
show() {
    local raw
    raw=$(cat)
    jq 'del(.saml.metadata_xml, .items[]?.saml.metadata_xml)' <<<"$raw" 2>/dev/null || printf '%s\n' "$raw"
}

require_id() {
    [[ "$PROVIDER_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || die "$COMMAND needs a provider id. Run \"$0 list\" to find it."
}

case "$COMMAND" in
    add)
        [ -n "$METADATA_URL$METADATA_FILE" ] || die "add needs a metadata URL or file."
        [ -n "$DOMAINS" ] || die "add needs domains."
        echo '{}' | build_body | api POST "" -H "Content-Type: application/json" --data-binary @- | show
        ;;
    list)
        api GET "" | show
        ;;
    update)
        require_id
        [ -n "$METADATA_URL$METADATA_FILE$DOMAINS$EMAIL_ATTR$FIRST_ATTR$LAST_ATTR" ] || die "update needs at least one change."
        CURRENT=$(api GET "/$PROVIDER_ID") || { printf '%s\n' "$CURRENT"; exit 1; }
        printf '%s' "$CURRENT" | build_body | api PUT "/$PROVIDER_ID" -H "Content-Type: application/json" --data-binary @- | show
        ;;
    delete)
        require_id
        if [ "$ASSUME_YES" != "true" ]; then
            read -r -p "Delete SAML provider $PROVIDER_ID? Its users will no longer be able to sign in. [y/N] " REPLY
            [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ] || die "Cancelled."
        fi
        api DELETE "/$PROVIDER_ID" | show
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac
