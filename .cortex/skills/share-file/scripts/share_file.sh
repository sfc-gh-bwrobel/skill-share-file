#!/usr/bin/env bash
# share-file: share local files via 7-day presigned links from a Snowflake stage.
#
#   share_file.sh [-c conn] [-d db] -p partner -m purpose file [file ...]   upload + links
#   share_file.sh [-c conn] [-d db] -r folder                                fresh links for an existing folder
#   share_file.sh [-c conn] [-d db] -l [-p partner]                          list shares
#
# Defaults: -c coco_183, -d TO_SHARE. Output is JSON from snow (FOLDER=<key> is printed first on upload).
set -euo pipefail

CONN="coco_183"
DB="TO_SHARE"
PARTNER=""
PURPOSE=""
RENEW=""
LIST=""

usage() {
  sed -n '4,6p' "$0" | sed 's/^#   //' >&2
  exit 2
}

while getopts "c:d:p:m:r:lh" opt; do
  case "$opt" in
    c) CONN="$OPTARG" ;;
    d) DB="$OPTARG" ;;
    p) PARTNER="$OPTARG" ;;
    m) PURPOSE="$OPTARG" ;;
    r) RENEW="$OPTARG" ;;
    l) LIST=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[[ "$DB" =~ ^[A-Za-z_][A-Za-z0-9_$]*$ ]] || { echo "Invalid database name: $DB" >&2; exit 2; }

# Use snow's own login for this connection, not session tokens a calling tool may have injected.
CONN_VAR=$(printf '%s' "$CONN" | tr '[:lower:]-' '[:upper:]_')
unset "SNOWFLAKE_CONNECTIONS_${CONN_VAR}_SESSION_TOKEN" "SNOWFLAKE_CONNECTIONS_${CONN_VAR}_MASTER_TOKEN" "SNOWFLAKE_CONNECTIONS_${CONN_VAR}_TOKEN"

sq() { printf "%s" "$1" | sed "s/'/''/g"; }
run_sql() { snow sql -c "$CONN" --format json -q "$1" 2> >(grep -v Skipping >&2); }

if [ -n "$LIST" ]; then
  WHERE=""
  [ -n "$PARTNER" ] && WHERE="WHERE PARTNER_NAME ILIKE '$(sq "$PARTNER")'"
  run_sql "SELECT FOLDER_NAME, PARTNER_NAME, DESCRIPTION, CREATED_AT FROM ${DB}.APP.FOLDER_METADATA ${WHERE} ORDER BY CREATED_AT DESC"
  exit 0
fi

if [ -n "$RENEW" ]; then
  # REGISTER_SHARE validates the folder key; partner/description are ignored for existing folders.
  run_sql "CALL ${DB}.APP.REGISTER_SHARE('$(sq "$RENEW")', '', '')"
  exit 0
fi

[ -n "$PARTNER" ] && [ -n "$PURPOSE" ] && [ "$#" -ge 1 ] || usage
for f in "$@"; do
  [ -f "$f" ] || { echo "File not found: $f" >&2; exit 1; }
done

RAND=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 5 || true)
FOLDER="$(date +%y%m%d)-${RAND}"

ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT
for f in "$@"; do
  snow stage copy "$f" "@${DB}.PUBLIC.SHARE_FILES/${FOLDER}/" -c "$CONN" --overwrite --no-auto-compress >/dev/null 2>"$ERR" \
    || { grep -v Skipping "$ERR" >&2; echo "Upload failed: $f" >&2; exit 1; }
done

echo "FOLDER=${FOLDER}"
run_sql "CALL ${DB}.APP.REGISTER_SHARE('${FOLDER}', '$(sq "$PARTNER")', '$(sq "$PURPOSE")')"
