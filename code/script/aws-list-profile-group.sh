#!/bin/bash

PROFILE=$1

get_user_groups() {
	local username=$1
	aws iam list-groups-for-user --user-name "$username" --query 'Groups[].GroupName' --profile "$PROFILE" | jq '.[]' -r
}

user_list=$(aws iam list-users --query 'Users[].UserName' --output text --profile "$PROFILE")

for username in $user_list; do
	echo "User: $username"
	echo -n "Groups: "
	get_user_groups "$username"
	echo ""
	echo "-----------------------"
done
