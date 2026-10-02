#!/usr/bin/env bash
#   ./deploy.sh .env.prod           install
#   ./deploy.sh .env.prod logs      follow the restore, then postgres
#   ./deploy.sh .env.prod lag       standby: how far behind the source it is
#   ./deploy.sh .env.prod promote   standby: stop following, become a normal database
#   ./deploy.sh .env.prod down      remove it (a HOST_PATH folder or EBS_VOLUME_ID stays)
set -euo pipefail
set -a; . "${1:?usage: $0 <env-file> [logs|lag|promote|down]}"; set +a
cd "$(dirname "$0")"
PSQL=(kubectl -n "$NAMESPACE" exec "deploy/$RELEASE-pgbackrest-restore" -c postgres -- psql -U "${PG_USER:-postgres}" -d postgres -c)

case "${2:-}" in
  logs)
    kubectl -n "$NAMESPACE" logs -f "deploy/$RELEASE-pgbackrest-restore" -c restore || true
    exec kubectl -n "$NAMESPACE" logs -f "deploy/$RELEASE-pgbackrest-restore" -c postgres ;;
  lag)
    "${PSQL[@]}" "select pg_is_in_recovery() as standby, pg_last_xact_replay_timestamp() as last_applied, now() - pg_last_xact_replay_timestamp() as behind"
    exit ;;
  promote)
    # pg_promote waits until the database leaves recovery (60s at most).
    "${PSQL[@]}" "select pg_promote()"
    # The copy keeps the source's passwords. Replace it, so whoever uses the
    # copy never holds the source's. Sent on stdin: not in any process list.
    if [ -n "${NEW_DB_PASSWORD:-}" ]; then
      case "$NEW_DB_PASSWORD" in *"'"*) echo "NEW_DB_PASSWORD cannot contain '" >&2; exit 1 ;; esac
      printf "ALTER ROLE %s PASSWORD '%s';\n" "${PG_USER:-postgres}" "$NEW_DB_PASSWORD" |
        kubectl -n "$NAMESPACE" exec -i "deploy/$RELEASE-pgbackrest-restore" -c postgres -- \
          psql -U "${PG_USER:-postgres}" -d postgres -v ON_ERROR_STOP=1 -q
      echo "password of ${PG_USER:-postgres} changed"
    fi
    # Mark it, so no later pod start restores over it.
    kubectl -n "$NAMESPACE" exec "deploy/$RELEASE-pgbackrest-restore" -c postgres -- \
      sh -c 'date -u +%FT%TZ > /var/lib/postgresql/data/promoted'
    echo "promoted. Set TARGET_TYPE and RESTORE_DELTA empty in $1 before the next ./deploy.sh."
    exit ;;
  down)
    helm -n "$NAMESPACE" uninstall "$RELEASE"
    kubectl -n "$NAMESPACE" delete pvc "$RELEASE-pgbackrest-restore" --ignore-not-found
    kubectl delete pv "$RELEASE-pgbackrest-restore" --ignore-not-found
    [ -z "${HOST_PATH:-}${EBS_VOLUME_ID:-}" ] || echo "the data stays in ${HOST_PATH:-EBS $EBS_VOLUME_ID}. Remove it there when done."
    exit ;;
esac

for v in RELEASE NAMESPACE CLOUD_PROVIDER IMAGE S3_BUCKET S3_PATH S3_ACCESS_KEY S3_SECRET_KEY; do
  [ -n "${!v:-}" ] || { echo "missing $v in $1" >&2; exit 1; }
done
[ -n "${HOST_PATH:-}${EBS_VOLUME_ID:-}${STORAGE_SIZE:-}" ] || { echo "set HOST_PATH, EBS_VOLUME_ID or STORAGE_SIZE in $1" >&2; exit 1; }

envsubst < values.yaml | helm upgrade --install "$RELEASE" . -n "$NAMESPACE" --create-namespace -f -
