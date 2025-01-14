#!/bin/bash

# Function to get pod details
get_pod_details() {
    local pod_name=$1
    kubectl get pod -o wide | awk -v pod="$pod_name" '
    NR>1 && $1 == pod {
        printf "Pod IP: %s , %s , %s\n", $1, $6, $7
    }'
}

LOAD_BALANCER_URL=""

# Main loop
while true; do
    response=$(curl -s $LOAD_BALANCER_URL)
    pod_name=$(echo $response | awk '{print $3}')
    
    if [ ! -z "$pod_name" ]; then
        get_pod_details $pod_name
    fi
    
    sleep 0.1
done
