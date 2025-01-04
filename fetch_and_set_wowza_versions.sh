#!/bin/bash

# Function to fetch and select Wowza Engine version
fetch_and_set_wowza_versions() {
  # Fetch all available versions of Wowza Engine from Docker
  all_versions=$(curl -s "https://registry.hub.docker.com/v2/repositories/wowzamedia/wowza-streaming-engine-linux/tags" | jq -r '.results[] | "\(.name) \(.last_updated)"')

  # Sort versions by date released and remove the date field
  sorted_versions=$(echo "$all_versions" | sort -k2 -r | awk '{print $1}')

  # Display the sorted versions
  echo "All available versions sorted by date released:"
  echo "$sorted_versions"

  # Prompt user for version of the engine and verify if it exists
  while true; do
    read -p "Enter the version of the engine you want to build from the list above: " engine_version
    if echo "$sorted_versions" | grep -q "^${engine_version}$"; then
      echo "$engine_version"
      return
    else
      echo "Error: The specified version ${engine_version} does not exist. Please enter a valid version from the list below:"
      echo "$sorted_versions"
    fi
  done
}
