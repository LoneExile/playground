#!/bin/bash

# Get all secrets and their values
echo "Retrieving all secrets from AWS Secrets Manager..."
echo "=================================================="

# Get list of all secret names
secret_names=$(aws secretsmanager list-secrets --query 'SecretList[].Name' --output text)

# Check if any secrets were found
if [ -z "$secret_names" ]; then
  echo "No secrets found in AWS Secrets Manager."
  exit 0
fi

# Loop through each secret and get its value
for secret_name in $secret_names; do
  echo ""
  echo "Secret Name: $secret_name"
  echo "----------------------------------------"

  # Get the secret value
  secret_value=$(aws secretsmanager get-secret-value --secret-id "$secret_name" --query 'SecretString' --output text 2>/dev/null)

  if [ $? -eq 0 ]; then
    echo "Secret Value: $secret_value"
  else
    echo "Error: Unable to retrieve value for secret '$secret_name'"
  fi

  echo "----------------------------------------"
done
