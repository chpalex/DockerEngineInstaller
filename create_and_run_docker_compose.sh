#!/bin/bash

# Function to create docker-compose.yml and run docker compose up
create_and_run_docker_compose() {
  local build_dir=$1
  local engine_version=$2
  local wse_lic=$3
  local wse_mgr_user=$4
  local wse_mgr_pass=$5

  # Prompt for Docker container name
  container_name=$(whiptail --inputbox "Enter Docker container name (default: wse_${engine_version}):" 8 78 "wse_${engine_version}" --title "Docker Container Name" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ] || [ -z "$container_name" ]; then
    container_name="wse_${engine_version}"
  fi

  # Define volume directories
  logs_dir="$build_dir/${container_name}_logs"
  content_dir="$build_dir/${container_name}_content"

  # Create volume directories
  mkdir -p "$logs_dir"
  mkdir -p "$content_dir"

  # Create docker-compose.yml
  cat <<EOL > docker-compose.yml
services:
  wowza:
    image: docker.io/library/wowza_engine:${engine_version}
    container_name: ${container_name}
    restart: always
    ports:
      - "6970-7000:6970-7000/udp"
      - "443:443"
      - "1935:1935"
      - "554:554"
      - "8084-8090:8084-8090/tcp"
    volumes:
      - $logs_dir:/usr/local/WowzaStreamingEngine/logs
      - $content_dir:/usr/local/WowzaStreamingEngine/content

    entrypoint: /sbin/entrypoint.sh
    env_file: 
      - ./.env
    environment:
      - WSE_LIC=${wse_lic}
      - WSE_MGR_USER=${wse_mgr_user}
      - WSE_MGR_PASS=${wse_mgr_pass}
EOL

  # Run docker compose up
  echo "Running docker compose up..."
  sudo docker compose up -d

  # Wait for the services to start and print logs
  echo "Waiting for services to start..."
  sleep 3  # Adjust the sleep time as needed

  echo "Printing docker compose logs..."
  sudo docker compose logs
}
