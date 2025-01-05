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
  rm -r "$compose_dir"

  # Prompt user to select Docker images to delete
  local images=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}")
  local image_options=()
  while IFS= read -r line; do
    image_options+=("$line" "")
  done <<< "$images"

  local selected_images=$(whiptail --title "Select Docker Images to Delete" --checklist "Choose images to delete:" 20 78 10 "${image_options[@]}" 3>&1 1>&2 2>&3)

  # Check if user selected any images
  if [ $? -eq 0 ]; then
    IFS=" " read -r -a selected_image_items <<< "$selected_images"
    for item in "${selected_image_items[@]}"; do
      # Remove quotes from item
      item=$(echo "$item" | tr -d '"')
      # Delete the selected image
      docker rmi "$item"
    done
  fi

  # Prompt user to select Docker containers to delete
  local containers=$(docker ps -a --format "{{.Names}} {{.ID}}")
  local container_options=()
  while IFS= read -r line; do
    container_options+=("$line" "")
  done <<< "$containers"

  local selected_containers=$(whiptail --title "Select Docker Containers to Delete" --checklist "Choose containers to delete:" 20 78 10 "${container_options[@]}" 3>&1 1>&2 2>&3)

  # Check if user selected any containers
  if [ $? -eq 0 ]; then
    IFS=" " read -r -a selected_container_items <<< "$selected_containers"
    for item in "${selected_container_items[@]}"; do
      # Remove quotes from item
      item=$(echo "$item" | tr -d '"')
      # Delete the selected container
      docker rm "$item"
    done
  fi
}