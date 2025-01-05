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

  # Get the image ID of the currently used image
  local current_image_id=$(docker images --format "{{.ID}}" "docker.io/library/wowza_engine:${engine_version}")

  # Prompt user to select Docker images to delete
  while true; do
    local images=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}")
    local image_options=()
    while IFS= read -r line; do
      if [[ "$line" == *"$current_image_id"* ]]; then
        image_options+=("$line [IN USE]" "ON")
      else
        image_options+=("$line" "OFF")
      fi
    done <<< "$images"

    local selected_images=$(whiptail --title "Select Docker Images to Delete" --checklist "Choose images to delete:" 20 78 10 "${image_options[@]}" 3>&1 1>&2 2>&3)

    # Check if user selected any images
    if [ $? -eq 0 ]; then
      IFS=" " read -r -a selected_image_items <<< "$selected_images"
      local valid_selection=true
      for item in "${selected_image_items[@]}"; do
        # Remove quotes from item
        item=$(echo "$item" | tr -d '"')
        if [[ "$item" == *"$current_image_id"* ]]; then
          valid_selection=false
          break
        fi
      done
      if [ "$valid_selection" = true ]; then
        for item in "${selected_image_items[@]}"; do
          # Remove quotes from item
          item=$(echo "$item" | tr -d '"')
          # Delete the selected image
          docker rmi "$item"
        done
        break
      else
        whiptail --title "Error" --msgbox "Deleting the in-use image will break the installation. Please try again." 8 78
      fi
    else
      break
    fi
  done

  # Prompt user to select Docker containers to delete
  while true; do
    local containers=$(docker ps -a --format "{{.Names}} {{.ID}}")
    local container_options=()
    while IFS= read -r line; do
      if [[ "$line" == *"$container_name"* ]]; then
        container_options+=("$line [IN USE]" "ON")
      else
        container_options+=("$line" "OFF")
      fi
    done <<< "$containers"

    local selected_containers=$(whiptail --title "Select Docker Containers to Delete" --checklist "Choose containers to delete:" 20 78 10 "${container_options[@]}" 3>&1 1>&2 2>&3)

    # Check if user selected any containers
    if [ $? -eq 0 ]; then
      IFS=" " read -r -a selected_container_items <<< "$selected_containers"
      local valid_selection=true
      for item in "${selected_container_items[@]}"; do
        # Remove quotes from item
        item=$(echo "$item" | tr -d '"')
        if [[ "$item" == *"$container_name"* ]]; then
          valid_selection=false
          break
        fi
      done
      if [ "$valid_selection" = true ]; then
        for item in "${selected_container_items[@]}"; do
          # Remove quotes from item
          item=$(echo "$item" | tr -d '"')
          # Delete the selected container
          docker rm "$item"
        done
        break
      else
        whiptail --title "Error" --msgbox "Deleting the in-use container will break the installation. Please try again." 8 78
      fi
    else
      break
    fi
  done
}