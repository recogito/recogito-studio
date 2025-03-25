# Backup and Restore DB

_Derived from [Supabase Documentation](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)_

## Connection String for Backup

This string is used in the steps below when executing from the running instance.

```
postgresql://postgres:[your-db-password]@localhost:5432/postgres
```

### Backup Database

These commands backup the current state of the DB. These backups exclude the parts of the DB schemas that are managed directly by Supabase. These commands place the files in the current working directory (i.e `/recogito-backup`)

```sh
supabase db dump --db-url [CONNECTION_STRING] -f roles.sql --role-only
```

```sh
supabase db dump --db-url [CONNECTION_STRING] -f schema.sql
```

```sh
supabase db dump --db-url [CONNECTION_STRING] -f data.sql --use-copy --data-only
```

```sh
supabase db dump --db-url [CONNECTION_STRING] -f history_schema.sql --schema supabase_migrations
```

```sh
supabase db dump --db-url [CONNECTION_STRING] -f history_data.sql --use-copy --data-only --schema supabase_migrations
```

## Restore Database

Before restoring a database, an empty 'postgres' database needs to be initialized by Supabase. If you are running with the default docker configuration, these are the steps to take before restoring the files.

1. Shut down the Supabase and Postgres containers

From the `/recogito-studio directory`:

```sh
sudo docker compose -f ./docker/docker-compose.yml down

sudo docker compose -f ./docker/docker-compose.postgres.yml down
```

2. Remove the DB volume

From the `/recogito-studio directory`:

```sh
sudo rm -rf ./docker/volumes/db/data
```

3. Restart the Supabase and Postgres containers.

From the `/recogito-studio directory`:

```sh
sudo docker compose -f ./docker/docker-compose.yml -f ./docker/docker-compose.postgres.yml up -d
```

This starts up Supabase and initializes the Postgres DB with the default Supabase configuration.

### Restore DB using psql

Run the following commands to restore your DB. You will be promted for you `Postgres Login`.

```psql
psql postgres \
    --single-transaction \
    --host [your-db-ip-address] \
    --user postgres \
    --variable ON_ERROR_STOP=1 \
    --file roles.sql \
    --file schema.sql \
    --command 'SET session_replication_role = replica' \
    --file data.sql
```

```psql
psql postgres \
    --single-transaction \
    --host [your-db-ip-address] \
    --user postgres \
    --variable ON_ERROR_STOP=1 \
    --file history_schema.sql \
    --file history_data.sql
```

### Restore Storage RLS policies

`supabase dump` does not allow dumping policies from the `storage` schema. To do this login to your instance's Supabase Studio app (i.e. https://server.example.com) and navigate to the `SQL Editor`:

![](./assets/images/studio-sql-editor.png)

Run the following SQL commands, they can be pasted into the editor all at once. :

```sql
DROP POLICY IF EXISTS "Users with correct policies can SELECT on objects" ON storage.objects;

CREATE POLICY "Users with correct policies can SELECT on objects" ON storage.objects FOR SELECT TO authenticated
    USING (TRUE);

DROP POLICY IF EXISTS "Users with correct policies can INSERT on objects" ON storage.objects;

CREATE POLICY "Users with correct policies can INSERT on objects" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Users with correct policies can UPDATE on objects" ON storage.objects;

CREATE POLICY "Users with correct policies can UPDATE on objects" ON storage.objects FOR UPDATE TO authenticated
    USING (TRUE)
    WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Users with correct policies can DELETE on objects" ON storage.objects;

CREATE POLICY "Users with correct policies can DELETE on objects" ON storage.objects FOR DELETE TO authenticated
    USING (TRUE);

DROP POLICY IF EXISTS "Users with correct policies can SELECT on buckets" ON storage.buckets;

CREATE POLICY "Users with correct policies can SELECT on buckets" ON storage.buckets FOR SELECT TO authenticated
    USING (TRUE);

DROP POLICY IF EXISTS "Users with correct policies can INSERT on buckets" ON storage.buckets;

CREATE POLICY "Users with correct policies can INSERT on buckets" ON storage.buckets FOR INSERT TO authenticated
    WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Users with correct policies can UPDATE on buckets" ON storage.buckets;

CREATE POLICY "Users with correct policies can UPDATE on buckets" ON storage.buckets FOR UPDATE TO authenticated
    USING (TRUE)
    WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Users with correct policies can DELETE on buckets" ON storage.buckets;

CREATE POLICY "Users with correct policies can DELETE on buckets" ON storage.buckets FOR DELETE TO authenticated
    USING (TRUE);
```

Your instance DB should now be restored!
