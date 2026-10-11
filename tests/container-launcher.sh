#!/usr/bin/env bash
set -euo pipefail
# The existing fixture supplies only synthetic credentials and loopback services.
exec docker run --rm --init --network host --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$PWD,dst=$PWD" --workdir "$PWD" \
  --env DB_USER --env DB_PASS_FILE --env DB_HOST --env DB_PORT --env DB_NAME \
  --env ROUTER_API_ADDRESS --env ROUTER_PUB_ADDRESS --env COUCHDB_LOG \
  database-actor:validation "$@"
