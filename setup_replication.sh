#!/bin/bash

source ./logging.sh

write_info "Setting up replication"

restart_service() {
  write_info "Redeploying Stand-alone Postgres to apply WAL"
  local body http_code
  read -r body http_code < <(
    curl -s -w "\n%{http_code}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${RAILWAY_API_TOKEN}" \
      -X POST https://backboard.railway.app/graphql/v2 \
      --data "{\"query\":\"mutation serviceInstanceRedeploy(\$environmentId: String!, \$serviceId: String!) { serviceInstanceRedeploy(environmentId: \$environmentId, serviceId: \$serviceId) }\",\"variables\":{\"environmentId\":\"${ENVIRONMENT_ID}\",\"serviceId\":\"${STANDALONE_SERVICE_ID}\"}}"
  )
  [[ $http_code == 200 && $body != *'"errors":'* ]] \
    || error_exit "API restart failed: $body"
  write_ok "Redeploy request accepted."
}

set_wal_level_logical() {
  psql "$STANDALONE_URL" -c "ALTER SYSTEM SET wal_level = 'logical';"
}

wait_for_logical() {
  write_info "Waiting for wal_level to switch to logical…"
  for _ in {1..20}; do
    level=$(psql "$STANDALONE_URL" -t -A -c "SHOW wal_level;" 2>/dev/null)
    [[ $level == logical ]] && { write_ok "wal_level=logical"; return; }
    sleep 15
  done
  error_exit "wal_level never became logical"
}

create_publication() {
  local database=$1

  local hostname=$(echo $STANDALONE_URL | sed -E 's/.*@([^:]+):.*/\1/')
  local user=$(echo $STANDALONE_URL | sed -E 's/^postgresql:\/\/([^:]+):.*/\1/')
  local port=$(echo $STANDALONE_URL | sed -E 's/.*:([0-9]+)\/.*/\1/')

  write_info "Creating publication for $database"
  psql -h "$hostname" -p "$port" -U "$user" -d "$database" -c "CREATE PUBLICATION pub_$database FOR ALL TABLES;" || error_exit "Failed to create publication for $database"
}

create_subscription() {
  local database=$1
  local base_url=$(echo $PRIMARY_URL | sed -E 's/(postgresql:\/\/[^:]+:[^@]+@[^:]+:[0-9]+)\/.*/\1/')
  local db_url="${base_url}/${database}"

  local hostname=$(echo $STANDALONE_URL | sed -E 's/.*@([^:]+):.*/\1/')
  local user=$(echo $STANDALONE_URL | sed -E 's/^postgresql:\/\/([^:]+):.*/\1/')
  local password=$(echo $STANDALONE_URL | sed -E 's/^postgresql:\/\/[^:]+:([^@]+)@.*/\1/')

  write_info "Creating subscription for $database"
  psql "$db_url" -c "CREATE SUBSCRIPTION sub_$database CONNECTION 'host=$hostname dbname=$database user=$user password=$password' PUBLICATION pub_$database WITH (copy_data = false);" || error_exit "Failed to create subscription for $database"
}

set_wal_level_logical
restart_service
wait_for_logical



databases=$(psql -d "$STANDALONE_URL" -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false;")

for db in $databases; do
  create_publication "$db"
done

for db in $databases; do
  create_subscription "$db"
done

write_ok "Replication setup completed successfully"
