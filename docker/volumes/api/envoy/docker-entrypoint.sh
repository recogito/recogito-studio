#!/bin/sh
set -e

fail() {
  echo "$1" >&2
  exit 1
}

# The legacy keys are matched verbatim by RBAC; an empty value would let an empty apikey header through
if [ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ]; then
  fail "ANON_KEY and SERVICE_ROLE_KEY must be set"
fi
if [ -z "$DASHBOARD_USERNAME" ] || [ -z "$DASHBOARD_PASSWORD" ]; then
  fail "DASHBOARD_USERNAME and DASHBOARD_PASSWORD must be set"
fi

# Keys land inside YAML and Lua string literals unescaped, so restrict them to JWT / sb_ key characters
for name in ANON_KEY SERVICE_ROLE_KEY ANON_KEY_ASYMMETRIC SERVICE_ROLE_KEY_ASYMMETRIC \
            SUPABASE_PUBLISHABLE_KEY SUPABASE_SECRET_KEY; do
  eval "value=\${$name}"
  case "$value" in
    *[!A-Za-z0-9._-]*) fail "$name contains characters not allowed in an API key" ;;
  esac
done
case "$DASHBOARD_USERNAME" in
  *:*) fail "DASHBOARD_USERNAME must not contain ':'" ;;
esac

# Escape a value for a sed replacement using | as the delimiter
sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

# Escape a value for a single-quoted YAML string inside a sed replacement
yaml_sed_escape() {
  sed_escape "$(printf '%s' "$1" | sed -e "s/'/''/g")"
}

# RBAC principals for optional keys: fall back to an unguessable value so an unset key matches nothing
rbac_value() {
  if [ -n "$1" ]; then
    printf '%s' "$1"
  else
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
  fi
}
ANON_KEY_ASYMMETRIC_RBAC=$(rbac_value "${ANON_KEY_ASYMMETRIC}")
SERVICE_ROLE_KEY_ASYMMETRIC_RBAC=$(rbac_value "${SERVICE_ROLE_KEY_ASYMMETRIC}")

# SHA1 base64 hash for the Envoy basic auth user list; coreutils fallback in case openssl is absent
sha1_base64() {
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$1" | openssl sha1 -binary | openssl base64
  elif command -v sha1sum >/dev/null 2>&1 && command -v base64 >/dev/null 2>&1; then
    for byte in $(printf '%s' "$1" | sha1sum | cut -c1-40 | sed 's/../& /g'); do
      # shellcheck disable=SC2059
      printf "\\$(printf '%03o' "0x$byte")"
    done | base64
  else
    return 1
  fi
}
PASSWORD_HASH=$(sha1_base64 "${DASHBOARD_PASSWORD}") || fail "Need openssl or sha1sum+base64 to hash DASHBOARD_PASSWORD"
DASHBOARD_BASIC_AUTH="${DASHBOARD_USERNAME}:{SHA}${PASSWORD_HASH}"

echo "Generating Envoy configuration..."

# Process the lds.yaml template with environment variables using sed
# Using | as delimiter since JWT tokens contain /. Keys are sed-escaped here, while
# YAML and Lua quoting relies on the allowlist above since they land in both.
sed -e "s|\${ANON_KEY}|$(sed_escape "${ANON_KEY}")|g" \
    -e "s|\${ANON_KEY_ASYMMETRIC}|$(sed_escape "${ANON_KEY_ASYMMETRIC}")|g" \
    -e "s|\${ANON_KEY_ASYMMETRIC_RBAC}|$(sed_escape "${ANON_KEY_ASYMMETRIC_RBAC}")|g" \
    -e "s|\${SERVICE_ROLE_KEY}|$(sed_escape "${SERVICE_ROLE_KEY}")|g" \
    -e "s|\${SERVICE_ROLE_KEY_ASYMMETRIC}|$(sed_escape "${SERVICE_ROLE_KEY_ASYMMETRIC}")|g" \
    -e "s|\${SERVICE_ROLE_KEY_ASYMMETRIC_RBAC}|$(sed_escape "${SERVICE_ROLE_KEY_ASYMMETRIC_RBAC}")|g" \
    -e "s|\${SUPABASE_PUBLISHABLE_KEY}|$(sed_escape "${SUPABASE_PUBLISHABLE_KEY}")|g" \
    -e "s|\${SUPABASE_SECRET_KEY}|$(sed_escape "${SUPABASE_SECRET_KEY}")|g" \
    -e "s|\${SUPABASE_PUBLIC_URL}|$(yaml_sed_escape "${SUPABASE_PUBLIC_URL}")|g" \
    -e "s|\${DASHBOARD_BASIC_AUTH}|$(yaml_sed_escape "${DASHBOARD_BASIC_AUTH}")|g" \
    /etc/envoy/lds.template.yaml > /etc/envoy/lds.yaml

if [ -n "$SUPABASE_SECRET_KEY" ] && \
   [ -n "$SUPABASE_PUBLISHABLE_KEY" ] && \
   [ -n "$SERVICE_ROLE_KEY_ASYMMETRIC" ] && \
   [ -n "$ANON_KEY_ASYMMETRIC" ]; then
  echo "Envoy sb_ key translation enabled"
else
  echo "Envoy running in legacy API key mode (sb_ keys disabled)"
fi

echo "Envoy configuration generated successfully"
echo "Starting Envoy..."

# Hand off to the image's entrypoint, which drops root to the envoy user before starting Envoy
exec /docker-entrypoint.sh envoy -c /etc/envoy/envoy.yaml "$@"
