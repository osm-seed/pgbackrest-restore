#!/usr/bin/env bash
#   ./deploy.sh .env.prod        install
#   ./deploy.sh .env.prod down   remove it, data included
set -euo pipefail
set -a; . "${1:?usage: $0 <env-file> [down]}"; set +a
cd "$(dirname "$0")"

if [ "${2:-}" = down ]; then
  helm -n "$NAMESPACE" uninstall "$RELEASE"
  kubectl -n "$NAMESPACE" delete pvc "$RELEASE-pgbackrest-restore"
  exit
fi

for v in RELEASE NAMESPACE IMAGE S3_BUCKET S3_PATH S3_ACCESS_KEY S3_SECRET_KEY STORAGE_SIZE; do
  [ -n "${!v:-}" ] || { echo "missing $v in $1" >&2; exit 1; }
done

envsubst < values.yaml | helm upgrade --install "$RELEASE" . -n "$NAMESPACE" --create-namespace -f -
