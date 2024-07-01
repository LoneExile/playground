#!/bin/bash

command="ls -al /nonexistent"
max_retries=3
retry_count=0
wait_time=5

while [ $retry_count -lt $max_retries ]; do
	error_output=$(eval $command 2>&1)
	exit_status=$?

	if [ $exit_status -eq 0 ]; then
		break
	fi

	echo "Command failed with exit code $exit_status."
	echo "Error output: $error_output"
	echo "Retrying in $wait_time seconds..."
	retry_count=$((retry_count + 1))
	sleep $wait_time
done

if [ $retry_count -eq $max_retries ]; then
	echo "Command failed after $max_retries attempts."
fi
