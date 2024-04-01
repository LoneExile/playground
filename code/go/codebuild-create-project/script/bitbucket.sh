#!/usr/bin/env bash

user=
password=
workspace=

for ((i = 1; i <= 10; i++)); do
	curl https://api.bitbucket.org/2.0/repositories/"${workspace}"/?page="${i}" -s -u "${user}":"${password}" -X GET -H "Content-Type: application/json" | jq '.values[] | .links.clone[] | select(.name | contains("ssh")) | .href' -r
done
