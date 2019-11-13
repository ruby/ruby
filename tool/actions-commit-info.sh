#!/bin/bash
set -euo pipefail
cd $(dirname "$0")/..
set_env () {
    echo "$1=$2"
    echo "::set-env name=$1::$2"
}
COMMIT_TIMESTAMP="$(git log -1 --format=%ct)"
set_env "COMMIT_TIMESTAMP" "$COMMIT_TIMESTAMP"
LOGS=$(TZ=UTC git log --since='0:00' --date=iso-local --format='%cd %s')
echo "commits of today:"
echo "$LOGS"
COUNT=$(echo "$LOGS" | wc -l)
# strip spaces
COUNT=$((0 + COUNT))
set_env "COMMIT_NUMBER_OF_DAY" "$COUNT"
set_env "COMMIT_DATE" "$(TZ=UTC git log --since='0:00' --date=short-local --format=%cd -1)"
