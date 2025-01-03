#!/bin/bash

# Function to fetch and select Wowza Engine version
fetch_and_set_wowza_versions() {
  # Fetch all available versions of Wowza Engine from Docker
  all_versions=""
  url="https://registry.hub.docker.com/v2/repositories/wowzamedia/wowza-streaming-engine-linux/tags"
  while [ -n "$url" ]; do
    response=$(curl -s "$url")
    tags=$(echo "$response" | jq -r '.results[] | "\(.name) \(.last_updated)"')
    all_versions="$all_versions"$'\n'"$tags"
    url=$(echo "$response" | jq -r '.next')
  done

  # Sort versions by date released
  sorted_versions=$(echo "$all_versions" | sort -k2 -r)

  # Remove the date field and display only the version names
  sorted_versions=$(echo "$sorted_versions" | awk '{print $1}')
  echo "All available versions sorted by date released:"
  echo "$sorted_versions"

  # Prompt user for version of the engine and verify if it exists
  while true; do
    read -p "Enter the version of the engine you want to build from the list above: " engine_version
    if echo "$sorted_versions" | grep -q "^${engine_version}$"; then
      echo "$engine_version"
      break
    else
      echo "Error: The specified version ${engine_version} does not exist. Please enter a valid version from the list below:"
      echo "$sorted_versions"
    fi
  done
}
