# Backup and Restore DB

_Derived from [Supabase Documentation](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)_

## Connection String for Backup

This string is used in the steps below

```
postgresql://postgres:[your-db-password]@localhost:5432/postgres
```

## Backup Database

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

With an empty target DB.

### Connection String for Restore

This assumes that you are restoring to the same DB with a now empty `postgres` database and the same password.

```
postgresql://postgres:[your-db-password]@localhost:5432/postgres
```
