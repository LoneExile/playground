#!/bin/bash

# Configuration
# API_URL=${1:-"https://canary.voidbox.io/status"}
API_URL=${1:-"https://blue-green.voidbox.io/status"}
LOG_FILE="api_monitor.log"
REQUEST_INTERVAL=1

# Print headers
echo "Starting API monitoring at $(date)"
echo "Sending requests to $API_URL every $REQUEST_INTERVAL second(s)"
echo "Results are being logged to $LOG_FILE"
echo "Press CTRL+C to stop monitoring"
echo "----------------------------------------"

# Main loop
while true; do
  # Get current timestamp
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
  
  # Send request and capture response
  RESPONSE=$(curl -s $API_URL)
  
  # Extract status from JSON response (using grep and cut for simplicity)
  STATUS=$(echo $RESPONSE | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  
  # Log the response with timestamp
  echo "[$TIMESTAMP] $RESPONSE" | tee -a $LOG_FILE
  
  # Color output based on status
  if [ "$STATUS" == "success" ]; then
    echo -e "\033[0;32m✓ Success\033[0m"
  else
    echo -e "\033[0;31m✗ Failed\033[0m"
  fi
  
  # Add separator for readability
  echo "----------------------------------------"
  
  # Wait before sending the next request
  sleep $REQUEST_INTERVAL
done
