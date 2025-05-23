#!/bin/bash

source ./logging.sh

write_info "Setting up replication"

restart_service() {
  write_info "Redeploying Standalone Postgres to apply WAL"
  local environment_id="$ENVIRONMENT_ID"
  local service_id="$STANDALONE_SERVICE_ID"
  local api_token="$RAILWAWY_API_TOKEN"

  local response=$(curl -s -w "%{http_code}" -o /tmp/curl_output.txt -X POST "https://backboard.railway.app/graphql/v2" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $api_token" \
    --data "{\"query\":\"mutation serviceInstanceRedeploy(\$environmentId: String!, \$serviceId: String!) { serviceInstanceRedeploy(environmentId: \$environmentId, serviceId: \$serviceId) }\",\"variables\":{\"environmentId\":\"$environment_id\",\"serviceId\":\"$service_id\"}}")

  local http_code=$(tail -n1 <<< "$response")

  if [[ "$http_code" -ne 200 ]]; then
    write_error "Failed to restart service. HTTP status code: $http_code"
    write_error "Response: $(cat /tmp/curl_output.txt)"
    error_exit "API call to restart service failed."
  else
    write_ok "Redeploy request sent to the API."
  fi

}

set_wal_level_logical() {
  write_info "Setting wal_level to logical"
  psql "$STANDALONE_URL" -c "ALTER SYSTEM SET wal_level = 'logical';" || error_exit "Failed to set wal_level to logical."
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

write_info "Wait 30s for the standalone instance to redeploy."
sleep 30

databases=$(psql -d "$STANDALONE_URL" -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false;")

for db in $databases; do
  create_publication "$db"
done

for db in $databases; do
  create_subscription "$db"
done

write_ok "Replication setup completed successfully"
