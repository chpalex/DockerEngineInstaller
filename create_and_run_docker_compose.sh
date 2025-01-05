#!/bin/bash

# Function to create docker-compose.yml and run docker compose up
create_and_run_docker_compose() {
  local build_dir=$1
  local engine_version=$2
  local wse_lic=$3
  local wse_mgr_user=$4
  local wse_mgr_pass=$5
  local container_name=$6
  local container_dir=$7

  # Define volume directories
  logs_dir="$build_dir/${container_name}/Engine_logs"
  content_dir="$build_dir/${container_name}/Engine_content"
  #conf_dir="$build_dir/${container_name}/Engine_conf"

  # Create volume directories
  mkdir -p "$logs_dir"
  mkdir -p "$content_dir"
  #mkdir -p "$conf_dir"

  # Create docker-compose.yml
  cat <<EOL > "$container_dir/docker-compose.yml"
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
  cd "$container_dir"
  sudo docker compose up -d

  echo "Printing docker compose logs..."
  sudo docker compose logs

}
