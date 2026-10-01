# pgbackrest-restore

A Helm chart that restores a pgBackRest backup into Postgres: to the latest WAL,
to a minute, or to one backup set. It only reads from the source repo.

It pairs with `webDb.pgbackrest` in the osm-seed chart, which makes the backups,
but works with any pgBackRest repo on S3.

## Restore

```bash
cp .env.example .env.prod      # fill it in; .env* is gitignored
./deploy.sh .env.prod          # install
./deploy.sh .env.prod down     # remove it; a HOST_PATH folder or EBS volume stays
```

`deploy.sh` loads the env file, fills the `${VARS}` in `values.yaml` with it
(`envsubst`) and passes the result to helm on stdin. `TARGET_TIME` empty restores the
latest backup plus every WAL.

## Follow and check

```bash
kubectl -n restore-test logs deploy/prod-1800-pgbackrest-restore -c restore -f    # download
kubectl -n restore-test logs deploy/prod-1800-pgbackrest-restore -c postgres -f   # WAL replay
```

It is ready when postgres logs `database system is ready to accept connections`.
Check the data stops where you asked:

```bash
kubectl -n restore-test exec -it deploy/prod-1800-pgbackrest-restore -c postgres -- \
  psql -U postgres -d <database> -c "select max(created_at) from changesets"
```

Recovery time = download (printed by the `restore` container) + WAL replay (the
`postgres` log until "ready").

## Never write to the source

The restored database must not send its WAL back to the source repo, or it
breaks the real backups. Three things stop it:

- the restore turns archiving off (`--archive-mode=off`);
- the config only has what is needed to read;
- the S3 keys can only read. This one works even if the other two fail.
