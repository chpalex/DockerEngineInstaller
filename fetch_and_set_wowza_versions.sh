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
  
  # Sort versions by date released and remove the date field
  sorted_versions=$(echo "$all_versions" | sort -k2 -r | awk '{print $1}')

  # Convert sorted versions to a format suitable for whiptail
  version_list=()
  while IFS= read -r version; do
    version_list+=("$version" "")
  done <<< "$sorted_versions"

  # Calculate the height of the menu based on the number of versions
  menu_height=$((${#version_list[@]} / 2 + 10))
  [ $menu_height -gt 40 ] && menu_height=40  # Limit the height to 40

  # Use whiptail to create a menu for selecting the version
  engine_version=$(whiptail --title "Select Wowza Engine Version" --menu $menu_height 78 ${#version_list[@]} "${version_list[@]}" 3>&1 1>&2 2>&3)

  # Check if the user selected a version
  if [ $? -eq 0 ]; then
    echo "$engine_version"
  else
    echo "No version selected, exiting install process" >&2
    exit 1
  fi
}
