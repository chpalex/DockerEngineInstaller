#!/bin/bash

# Function to fetch and select Wowza Engine version
fetch_and_set_wowza_versions() {
  # Fetch all available versions of Wowza Engine from Docker
  all_versions=$(curl -s "https://registry.hub.docker.com/v2/repositories/wowzamedia/wowza-streaming-engine-linux/tags" | jq -r '.results[] | "\(.name) \(.last_updated)"')

  # Sort versions by date released and remove the date field
  sorted_versions=$(echo "$all_versions" | sort -k2 -r | awk '{print $1}')

  # Convert sorted versions to a format suitable for whiptail
  version_list=()
  column1=()
  column2=()
  count=0
  while IFS= read -r version; do
    if (( count % 2 == 0 )); then
      column1+=("$version")
    else
      column2+=("$version")
    fi
    count=$((count + 1))
  done <<< "$sorted_versions"

  # Combine columns into a single list for whiptail
  combined_list=()
  for ((i = 0; i < ${#column1[@]}; i++)); do
    combined_list+=("${column1[i]}" "${column2[i]:-}")
  done

  # Calculate the height of the menu based on the number of versions
  menu_height=$((${#combined_list[@]} / 2 + 10))
  [ $menu_height -gt 40 ] && menu_height=40  # Limit the height to 40

  # Use whiptail to create a menu for selecting the version
  engine_version=$(whiptail --title "Select Wowza Engine Version" --menu "Choose a version:" $menu_height 78 ${#combined_list[@]} "${combined_list[@]}" 3>&1 1>&2 2>&3)

  # Check if the user selected a version
  if [ $? -eq 0 ]; then
    echo "$engine_version"
  else
    echo "No version selected, exiting install process" >&2
    exit 1
  fi
}
