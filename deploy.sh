#!/usr/bin/env bash
#   ./deploy.sh .env.prod        install
#   ./deploy.sh .env.prod down   remove it (a HOST_PATH folder or EBS_VOLUME_ID stays)
set -euo pipefail
set -a; . "${1:?usage: $0 <env-file> [down]}"; set +a
cd "$(dirname "$0")"

if [ "${2:-}" = down ]; then
  helm -n "$NAMESPACE" uninstall "$RELEASE"
  kubectl -n "$NAMESPACE" delete pvc "$RELEASE-pgbackrest-restore" --ignore-not-found
  kubectl delete pv "$RELEASE-pgbackrest-restore" --ignore-not-found
  [ -z "${HOST_PATH:-}${EBS_VOLUME_ID:-}" ] || echo "the data stays in ${HOST_PATH:-EBS $EBS_VOLUME_ID}. Remove it there when done."
  exit
fi

for v in RELEASE NAMESPACE CLOUD_PROVIDER IMAGE S3_BUCKET S3_PATH S3_ACCESS_KEY S3_SECRET_KEY; do
  [ -n "${!v:-}" ] || { echo "missing $v in $1" >&2; exit 1; }
done
[ -n "${HOST_PATH:-}${EBS_VOLUME_ID:-}${STORAGE_SIZE:-}" ] || { echo "set HOST_PATH, EBS_VOLUME_ID or STORAGE_SIZE in $1" >&2; exit 1; }

envsubst < values.yaml | helm upgrade --install "$RELEASE" . -n "$NAMESPACE" --create-namespace -f -
