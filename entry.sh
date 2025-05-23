#!/bin/bash

source ./logging.sh

main() {
  section "Starting the PostgreSQL Migration Orchestration"

  if [ -z "$STANDALONE_URL" ]; then
    error_exit "STANDALONE_URL environment variable is not set."
  fi

  if [ -z "$PRIMARY_URL" ]; then
    error_exit "PRIMARY_URL environment variable is not set."
  fi

  section "Syncing Data between the Standalone and Primary node"
  ./sync_data.sh
  if [ $? -ne 0 ]; then
    error_exit "Data sync failed!"
  fi
  write_ok "Data sync completed successfully"

  section "Enabling replication between the Standalone and Cluster"
  if [[ "$ENABLE_REPLICATION" == "true" ]]; then
    ./setup_replication.sh
    if [ $? -ne 0 ]; then
      error_exit "Replication setup failed!"
    fi
    write_ok "Replication setup completed successfully"
  else
    write_info "ENABLE_REPLICATION is false, no more work to do."
  fi

  section "PostgreSQL Migration Completed"
  write_info "You may delete this service"
  exit 0
}

main "$@"
