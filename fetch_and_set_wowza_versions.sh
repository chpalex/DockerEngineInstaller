#!/bin/bash

# Function to fetch and select Wowza Engine version
fetch_and_set_wowza_versions() {
  # Fetch all available versions of Wowza Engine from Docker
  all_versions=""
  url="https://registry.hub.docker.com/v2/repositories/wowzamedia/wowza-streaming-engine-linux/tags"
  while [ "$url" != "null" ]; do
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
  [ $menu_height -gt 20 ] && menu_height=20  # Limit the height to 20

  # Calculate the list height
  list_height=$((${#version_list[@]} / 2))
  [ $list_height -gt 10 ] && list_height=10  # Limit the list height to 10

  # Use whiptail to create a menu for selecting the version
  engine_version=$(whiptail --title "Select Wowza Engine Version" --menu "Available Docker Wowza Engine Versions:" $menu_height 80 $list_height "${version_list[@]}" 3>&1 1>&2 2>&3)

  # Check if the user selected a version
  if [ $? -eq 0 ]; then
    echo "$engine_version"
  else
    return 1
  fi

  # Prompt for Docker container name
  container_name=$(whiptail --inputbox "Enter Docker container name (default: wse_${engine_version}):" 8 78 "wse_${engine_version}" --title "Docker Container Name" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ] || [ -z "$container_name" ]; then
    container_name="wse_${engine_version}"
  fi

  # Export the container_name variable to make it available to other scripts
  export container_name
}