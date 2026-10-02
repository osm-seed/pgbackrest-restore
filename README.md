# pgbackrest-restore

A Helm chart that restores a pgBackRest backup into Postgres: to the latest WAL,
to a minute, or to one backup set. It only reads from the source repo.

It pairs with `webDb.pgbackrest` in the osm-seed chart, which makes the backups,
but works with any pgBackRest repo on S3.

## Restore

```bash
cp .env.example .env.staging      # fill it in; .env* is gitignored
./deploy.sh .env.staging          # install
./deploy.sh .env.staging down     # remove it; a HOST_PATH folder or EBS volume stays
```

`deploy.sh` loads the env file, fills the `${VARS}` in `values.yaml` with it
(`envsubst`) and passes the result to helm on stdin. `TARGET_TIME` empty restores the
latest backup plus every WAL.

## Follow and check

```bash
./deploy.sh .env.staging logs     # the download, then postgres replaying WAL
```

It is ready when postgres logs `database system is ready to accept connections`.
Check the data stops where you asked:

```bash
kubectl -n <NAMESPACE> exec -it deploy/<RELEASE>-pgbackrest-restore -c postgres -- \
  psql -U postgres -d <database> -c "select max(created_at) from changesets"
```

Recovery time = download (printed by the `restore` container) + WAL replay (the
`postgres` log until "ready").

## Standby: move a database

`TARGET_TYPE=standby` restores and then keeps applying new WAL from the repo,
about a minute behind the source, until you promote it.

```bash
./deploy.sh .env.staging            # TARGET_TYPE=standby, PG_SETTINGS at least the source's
./deploy.sh .env.staging lag        # how far behind it is

# cutover: stop writes on the source, then on the source: select pg_switch_wal();
./deploy.sh .env.staging lag        # wait until it caught up
./deploy.sh .env.staging promote    # now a normal database; point the app at it
```

After promoting, give the new database its own backups, in a new repo path.
Never the source's.

## Never write to the source

The restored database must not send its WAL back to the source repo, or it
breaks the real backups. Three things stop it:

- the restore turns archiving off (`--archive-mode=off`);
- the config only has what is needed to read;
- the S3 keys can only read. This one works even if the other two fail.
