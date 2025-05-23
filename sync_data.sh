#!/bin/bash

source ./logging.sh

write_info "Dumping data from the standalone and restoring to the cluster"

databases=$(psql -d "$STANDALONE_URL" -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false;")
dump_dir="db_dump"
mkdir -p $dump_dir

dump_database() {
  local database=$1
  local dump_file="$dump_dir/$database.sql"

  write_info "Dumping database: $database"

  write_info "Dump file will be saved to: $dump_file"

  local base_url=$(echo $STANDALONE_URL | sed -E 's/(postgresql:\/\/[^:]+:[^@]+@[^:]+:[0-9]+)\/.*/\1/')
  local db_url="${base_url}/${database}"

  pg_dump -d "$db_url" \
    --format=plain \
    --quote-all-identifiers \
    --no-tablespaces \
    --no-owner \
    --no-privileges \
    --disable-triggers \
    --file=$dump_file || error_exit "Failed to dump database from $database."

  write_ok "Database $database dumped successfully"
}

ensure_database_exists() {
  local db_url=$1
  local db_name=$(echo $db_url | sed -E 's/.*\/([^\/?]+).*/\1/')
  local psql_url=$(echo $db_url | sed -E 's/(.*)\/[^\/?]+/\1/')

  write_info "Ensuring database $database exists"

  if ! psql $psql_url -tA -c "SELECT 1 FROM pg_database WHERE datname='$db_name'" | grep -q 1; then
      write_ok "Database $db_name does not exist. Creating..."
      psql $psql_url -c "CREATE DATABASE \"$db_name\""
  else
      write_info "Database $db_name exists."
  fi
}

restore_database() {
  local database=$1
  local base_url=$(echo $PRIMARY_URL | sed -E 's/(postgresql:\/\/[^:]+:[^@]+@[^:]+:[0-9]+)\/.*/\1/') #change this back to postgresql
  local db_url="${base_url}/${database}"

  write_info "Restoring database: $database"

  ensure_database_exists "$db_url"

  psql $db_url -v ON_ERROR_STOP=1 --echo-errors \
    -f "$dump_dir/$database.sql" > /dev/null || error_exit "Failed to restore database $database to PRIMARY_URL"
  
  write_ok "Database $database restored successfully"
}

for db in $databases; do
  dump_database "$db"
done

for db in $databases; do
  restore_database "$db"
done