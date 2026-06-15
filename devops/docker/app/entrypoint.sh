#!/bin/bash

# -e          : causes script to fail if any command below has non-zero exit status
# -u          : a reference to any variable you haven't previously defined cause immediate exit
# -o pipefail : prevents errors in a pipeline from being masked. If any command in a pipeline fails, 
#               that return code will be used as the return code of the whole pipeline.

# Increase file descriptor limit for Vite precompile later
ulimit -n 65536

set -euo pipefail 

# shellcheck disable=SC1091

VAULT_SECRETS_DIR=/vault/secrets

if [ -d ${VAULT_SECRETS_DIR} ]; then
  set -a # enable mark variables which are modified or created for export
  for i in ${VAULT_SECRETS_DIR}/*.env; do
    echo "[entrypoint] Adding environment variables from ${i}"
    source ${i}
  done
  set +a # disable mark variables which are modified or created for export
else
  echo "[entrypoint] Vault secrets directory (${VAULT_SECRETS_DIR}) does not exist"
fi

configure_database_pool() {
  if [ -z "${DATABASE_URL:-}" ]; then
    return
  fi

  if [[ "${DATABASE_URL}" == *"pool="* ]]; then
    return
  fi

  local pool="${DATABASE_POOL:-}"
  if [ -z "${pool}" ]; then
    if [[ "$*" == *"sidekiq"* ]] && [ -n "${SIDEKIQ_CONCURRENCY:-}" ]; then
      pool=$((SIDEKIQ_CONCURRENCY + 5))
    else
      pool="${RAILS_MAX_THREADS:-5}"
    fi
  fi

  if [[ ! "${pool}" =~ ^[0-9]+$ ]] || [ "${pool}" -le 0 ]; then
    echo "[entrypoint] DATABASE_POOL value (${pool}) is invalid; leaving DATABASE_URL unchanged"
    return
  fi

  local separator="?"
  if [[ "${DATABASE_URL}" == *"?"* ]]; then
    separator="&"
  fi

  export DATABASE_URL="${DATABASE_URL}${separator}pool=${pool}"
  echo "[entrypoint] ActiveRecord database pool set to ${pool}"
}

configure_database_pool "$@"

# Rails Entrypoint
# If running the rails server then create or migrate existing database
if [ "${1}" == "./bin/rails" ] && [ "${2}" == "server" ]; then
  # Defensive cleanup in case a stale PID file made it into the image or volume.
  rm -f /app/tmp/pids/server.pid

  until nc -z -v -w30 ${DATABASE_OPENSHIFT_SERVICE_HOST} 5432; do
    echo "Waiting for PostgreSQL database (${DATABASE_OPENSHIFT_SERVICE_HOST}) to start..."
    sleep 1
  done

  echo "*** Preparing Database..."
  
  IS_APP_SERVER=true ./bin/rails db:migrate

  echo "*** reindexing models for search..."
  
  IS_APP_SERVER=true ./bin/rails search:reindex
fi

exec "$@"
