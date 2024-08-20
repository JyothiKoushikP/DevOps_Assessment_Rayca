#!/bin/bash

# Log File Definition
log_file="/spot_vm_status.log"

# Check if the log file exists; if not, create it
if [ ! -f "$log_file" ]; then
    touch "$log_file"
fi

# Function to log with timestamp
log_with_timestamp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$log_file"
}

# Get Spot VM's HostName and Resource Group using the tag 'zabbix-agent=spot-vm'
spot_vm_list=$(az resource list --tag zabbix-agent=spot-vm --query "[].{Name:name, ResourceGroup:resourceGroup}")

# Iterate over the list of VMs
# Checkpoint 1: JSON Parsing
# Reference: Adapted from example provided by Claude AI (https://claude.ai/new)
echo "$spot_vm_list" | jq -c '.[]' | while IFS= read -r item; do
    # Extract values using jq
    name=$(echo "$item" | jq -r '.Name')
    resource_group=$(echo "$item" | jq -r '.ResourceGroup')

    # Get the VM's private IP address to check the heartbeat of the Zabbix Agent
    vm_ip_address=$(nslookup ${name} | grep 'Address:' | awk '{ print $2 }' | tail -n 1)

    # Check if the Zabbix agent is active by pinging it from the Zabbix Server Container (Exit Status Code)
    agent_active_status=$(docker exec zabbix-server sh -c "zabbix_get -s ${vm_ip_address} -k agent.ping > /dev/null 2>&1; echo \$?")

    if [ $agent_active_status -eq 0 ]; then
        log_with_timestamp "Zabbix Agent: ${name} is Currently Active"
    else
        log_with_timestamp "Zabbix Agent: ${name} is Inactive....attempting to start the VM"

        # Attempt to restart the VM up to 5 times
        attempt=1
        while [ $attempt -le 5 ]; do
            az vm start -n ${name} -g ${resource_group} > /dev/null
            if [ $? -eq 0 ]; then
                log_with_timestamp "Zabbix Agent: ${name} restarted successfully on attempt $attempt"
                break
            else
                log_with_timestamp "Failed to restart Zabbix Agent: ${name} on attempt $attempt"
            fi
            attempt=$((attempt + 1))
        done

        # If all attempts fail, log the failure and Continue....
        if [ $attempt -gt 5 ]; then
            log_with_timestamp "Failed to restart Zabbix Agent: ${name} after 5 attempts"
        fi
    fi

done
