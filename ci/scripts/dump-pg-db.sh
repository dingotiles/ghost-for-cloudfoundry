#!/bin/bash

set -eu

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
cd $ROOT

SPACE=${SPACE:-staging}
DUMP_FILE=${DUMP_FILE:-dump.sql}

cf_org=$(spruce json ci/settings.yml | jq -r ".meta.cf.organization")
cf_space_staging=$(spruce json ci/settings.yml | jq -r ".meta.cf.spaces.${SPACE}")

if [[ "${CF_USERNAME:-X}" != "X" ]]; then
  : ${CF_PASSWORD:?required}
  : ${CF_API:?required}
  cf api "${CF_API}"
  cf auth "${CF_USERNAME}" "${CF_PASSWORD}"
fi

set -x
cf target -o $cf_org -s $cf_space_staging
set +x

space_guid=$(jq -r ".SpaceFields.GUID" ~/.cf/config.json)
cf_curl_app_url=$(cf curl "/v2/spaces/${space_guid}/apps?q=name:ghost" | jq -r ".resources[0].metadata.url")
elephantsql=$(cf curl "${cf_curl_app_url}/env" | jq -r '.system_env_json.VCAP_SERVICES.elephantsql // "X"')
if [[ "${elephantsql}" != "X" ]]; then
  echo "Found PostgreSQL DB via ElephantSQL"
  db_uri=$(echo "$elephantsql" | jq -r ".[0].credentials.uri")
  echo $db_uri
  pg_dump -O -v --clean --inserts --if-exists --no-privileges ${db_uri} | \
    grep -v -E '^(CREATE\ EXTENSION|DROP\ EXTENSION|COMMENT\ ON|CREATE\ SCHEMA|DROP\ SCHEMA|SET idle_in_transaction_session_timeout)' > ${DUMP_FILE}
else
  echo "Could not find an ElephantSQL database to which to upload"
  exit 1
fi