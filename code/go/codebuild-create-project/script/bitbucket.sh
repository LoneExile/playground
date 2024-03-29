#!/usr/bin/env bash

repository=$1
user=
password=
target=
branch=
workspace=

# echo "-------"
# echo "$repository"
# curl https://api.bitbucket.org/2.0/repositories/"${workspace}"/"${repository}"/refs/branches -s -u "${user}":"${password}" -X POST -H "Content-Type: application/json" -d '{"name": "'${branch}'","target": {"hash": "'${target}'"}}'
# echo "-------"

curl https://api.bitbucket.org/2.0/repositories/"${workspace}"/ -s -u "${user}":"${password}" -X GET -H "Content-Type: application/json" | jq # '.values[] | .name .language'
