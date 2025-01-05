#!/bin/bash

# Function to clean up the install directory and prompt user to delete Docker images and containers
cleanup() {
  local base_dir=$1
  local build_dir=$2
  local compose_dir=$3
  local container_name=$4

  echo "Cleaning up the install directory..."

  if [ -f "$base_dir/VHost.xml" ]; then
    sudo rm "$base_dir/VHost.xml"
  fi

  if [ -f "$base_dir/Server.xml" ]; then
    sudo rm "$base_dir/Server.xml"
  fi

  if [ -f "$build_dir/Dockerfile" ]; then
    sudo rm "$build_dir/Dockerfile"
  fi

  if [ -f "$base_dir/tomcat.properties" ]; then
    sudo rm "$base_dir/tomcat.properties"
  fi

  if [ -f "$base_dir/log4j2-config.xml" ]; then
    sudo rm "$base_dir/log4j2-config.xml"
  fi

  # Move the COMPOSE_DIR to the container_name directory
  local container_dir="$build_dir/${container_name}"
  mkdir -p "$container_dir"
  mv "$compose_dir"/* "$container_dir/"
  mv "$build_dir/.env" "$container_dir/"
  mv "$build_dir/docker-compose.yml" "$container_dir/"

  # Prompt user to select Docker images and containers to delete
  local images=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}")
  local containers=$(docker ps -a --format "{{.Names}} {{.ID}}")

  # Combine images and containers into a single list for whiptail
  local options=()
  while IFS= read -r line; do
    options+=("$line" "")
  done <<< "$images"
  while IFS= read -r line; do
    options+=("$line" "")
  done <<< "$containers"

  # Display whiptail checkbox dialog
  local selected=$(whiptail --title "Select Docker Images and Containers to Delete" --checklist "Choose items to delete:" 20 78 10 "${options[@]}" 3>&1 1>&2 2>&3)

  # Check if user selected any items
  if [ $? -eq 0 ]; then
    IFS=" " read -r -a selected_items <<< "$selected"
    for item in "${selected_items[@]}"; do
      # Remove quotes from item
      item=$(echo "$item" | tr -d '"')
      # Check if item is an image or container and delete accordingly
      if docker images --format "{{.ID}}" | grep -q "$item"; then
        docker rmi "$item"
      elif docker ps -a --format "{{.ID}}" | grep -q "$item"; then
        docker rm "$item"
      fi
    done
  fi
}
